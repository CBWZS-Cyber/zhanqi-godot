#!/usr/bin/env node
/**
 * 战棋 · 房间号目录服务（room-code rendezvous）
 * ============================================
 * 作用只有一个：把「4 位数字房间号」翻译成「房主的可达地址」。
 *
 *   POST /room        {"addr":"6.tcp.cpolar.top:12345","kind":"tcp"}  → {"code":"4829"}
 *   GET  /room?code=4829  → {"addr":"...","kind":"tcp"}
 *   GET  /health                                                      → {"ok":true,"rooms":3}
 *
 * 它**不碰游戏状态、不做裁决、不转发游戏流量** —— 只存一个键值对，交换完地址双方就直连。
 * 真正的对局数据仍然走 Godot 自己的 ENet / cpolar 隧道（那条线一行都没动）。
 *
 * 依赖：**零**（只用 node:http / node:crypto），Node 18+ 直接 `node server.js` 就能跑。
 *
 * 环境变量（都有默认值）：
 *   PORT        监听端口，默认 8787（也可用第一个命令行参数：`node server.js 9000`，
 *               给 Godot 侧回归测试用独立端口，免得和你手动起的实例打架）
 *   TTL_SEC     房间号有效期（秒），默认 600（10 分钟）。**每次查询会续期**，
 *               这样"建房后等半天才有人加入"不会失效。
 *   CODE_LEN    房间号位数，默认 4
 *   RATE_PER_MIN 每 IP 每分钟最多请求数，默认 60
 *
 * 部署（任选其一，都是免费额度够用的）：
 *   1) 本机跑 + 用你已有的 cpolar 把自己的 8787 端口暴露出去（注意：免费隧道地址会变，
 *      所以这个地址要给客户端**留一个可配置项**，别写死在代码里）
 *   2) Render / Fly / Railway 免费实例：把本文件丢进去，`node server.js`
 *   3) Cloudflare Workers：需把 handler 改成 Workers 的 fetch 风格（逻辑一样）
 *
 * ⚠️ 已知边界（不是缺陷，是有意为之）：
 *   · 内存存储 → 进程重启房间号全丢（对"建完房马上发码"的用法无影响）；
 *   · 房间号**先到先得**，谁都能查询（所以是"知道号码就能连"的语义，与"加密码"是两件事）；
 *   · 无 TLS（明文）→ 公网部署建议放在 https 反代后面。
 */

const http = require("node:http");
const crypto = require("node:crypto");

const PORT = Number(process.env.PORT || process.argv[2] || 8787);
// 2026-11-24：默认只听本机，公网入口走 nginx（https://game.learnest.cn/room-service）。
//   局域网手机调试时用 `BIND_HOST=0.0.0.0 node server.js`。
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const TTL_SEC = Number(process.env.TTL_SEC || 600);
const CODE_LEN = Number(process.env.CODE_LEN || 4);
const RATE_PER_MIN = Number(process.env.RATE_PER_MIN || 60);

/** code -> { addr, kind, created, expire, hits } */
const rooms = new Map();
/** ip -> { count, resetAt } */
const rate = new Map();

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function clientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.length > 0) return fwd.split(",")[0].trim();
  return req.socket.remoteAddress || "?";
}

function rateOk(ip) {
  const now = Date.now();
  let r = rate.get(ip);
  if (!r || now >= r.resetAt) {
    r = { count: 0, resetAt: now + 60_000 };
    rate.set(ip, r);
  }
  r.count += 1;
  return r.count <= RATE_PER_MIN;
}

/** 纯数字房间号；用 crypto 随机，避免 Math.random 被猜到规律 */
function newCode() {
  for (let attempt = 0; attempt < 200; attempt++) {
    let s = "";
    for (let i = 0; i < CODE_LEN; i++) s += crypto.randomInt(0, 10);
    if (!rooms.has(s)) return s;
  }
  throw new Error("房间号池耗尽（房间太多了？）");
}

function sweep() {
  const now = Date.now();
  let n = 0;
  for (const [code, r] of rooms) {
    if (now > r.expire) {
      rooms.delete(code);
      n++;
    }
  }
  if (n > 0) log(`清理过期房间号 ${n} 个，当前 ${rooms.size} 个`);
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function readBody(req, limit = 4096) {
  return new Promise((resolve) => {
    let buf = "";
    req.on("data", (c) => {
      buf += c;
      if (buf.length > limit) req.destroy();
    });
    req.on("end", () => resolve(buf));
    req.on("error", () => resolve(""));
  });
}

/** 地址合法性：host:port，host 允许域名/IPv4，port 1..65535 —— 挡掉明显的垃圾数据 */
function validAddr(addr) {
  if (typeof addr !== "string" || addr.length < 4 || addr.length > 128) return false;
  const m = addr.match(/^([A-Za-z0-9.\-]+):(\d{1,5})$/);
  if (!m) return false;
  const port = Number(m[2]);
  return port >= 1 && port <= 65535;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const ip = clientIp(req);

  if (req.method === "OPTIONS") return json(res, 204, {});

  if (!rateOk(ip)) {
    log(`限流 ${ip} ${req.method} ${url.pathname}`);
    return json(res, 429, { error: "too_many_requests" });
  }

  // 健康检查（部署后自检用）
  if (req.method === "GET" && url.pathname === "/health") {
    return json(res, 200, { ok: true, rooms: rooms.size, code_len: CODE_LEN, ttl_sec: TTL_SEC });
  }

  // 建房：房主上报自己的可达地址，换一个房间号
  if (req.method === "POST" && url.pathname === "/room") {
    let payload = {};
    try {
      payload = JSON.parse((await readBody(req)) || "{}");
    } catch {
      return json(res, 400, { error: "bad_json" });
    }
    const addr = String(payload.addr || "").trim();
    const kind = payload.kind === "lan" ? "lan" : "tcp";
    if (!validAddr(addr)) return json(res, 400, { error: "bad_addr" });

    const code = newCode();
    const now = Date.now();
    rooms.set(code, { addr, kind, created: now, expire: now + TTL_SEC * 1000, hits: 0 });
    log(`建房 code=${code} addr=${addr} kind=${kind} 共 ${rooms.size} 个`);
    return json(res, 200, { code, ttl: TTL_SEC, code_len: CODE_LEN });
  }

  // 查房：加入者用房间号换地址（并**续期**，避免"聊半天才加入"时号码已过期）
  if (req.method === "GET" && url.pathname === "/room") {
    const code = String(url.searchParams.get("code") || "").trim();
    if (!/^\d+$/.test(code)) return json(res, 400, { error: "bad_code" });
    const r = rooms.get(code);
    if (!r) {
      log(`查房未命中 code=${code}`);
      return json(res, 404, { error: "not_found" });
    }
    r.expire = Date.now() + TTL_SEC * 1000;
    r.hits += 1;
    log(`加入者查到 code=${code} addr=${r.addr}（第 ${r.hits} 次）`);
    return json(res, 200, { addr: r.addr, kind: r.kind, hits: r.hits });
  }

  // 房主关房：主动释放房间号（可选，过期也会自动清）
  if (req.method === "DELETE" && url.pathname === "/room") {
    const code = String(url.searchParams.get("code") || "").trim();
    if (rooms.delete(code)) {
      log(`房间号已释放 code=${code}`);
      return json(res, 200, { ok: true });
    }
    return json(res, 404, { error: "not_found" });
  }

  json(res, 404, { error: "no_route" });
});

setInterval(sweep, 30_000).unref();

server.listen(PORT, BIND_HOST, () => {
  log(`房间号目录服务已启动 http://${BIND_HOST}:${PORT}  CODE_LEN=${CODE_LEN} TTL=${TTL_SEC}s`);
  log("自检: curl http://127.0.0.1:" + PORT + "/health");
});
