#!/usr/bin/env node
/**
 * 房间号目录服务 · 自检 / 回归
 * 用法：node selftest.js      （全部通过 exit 0，有失败 exit 1）
 *
 * 为什么不用 curl 手测：① Windows 上 http_proxy 会把 127.0.0.1 的请求也代理走；
 * ② 后台起的服务在 shell 命令结束时会被回收。自包含脚本两个问题都没有，
 * 而且能留在仓库里当回归（和 tests/*.gd 的定位一致）。
 *
 * 顺带覆盖一个**多房间并发**场景：同时开两个房，各自用自己的号查到自己的地址，
 * 不能串号 —— 这是目录服务唯一可能出的功能性错误。
 */

const { spawn } = require("node:child_process");
const path = require("node:path");

const PORT = 18787; // 特意避开默认 8787，免得和你手动起的实例打架
const BASE = `http://127.0.0.1:${PORT}`;

let pass = 0;
let fail = 0;
function ck(cond, name) {
  if (cond) {
    pass++;
    console.log("  \u2713", name);
  } else {
    fail++;
    console.error("  \u2717 FAIL:", name);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitUp(ms = 8000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) return true;
    } catch {
      /* 还没起来 */
    }
    await sleep(150);
  }
  return false;
}

const post = (body) =>
  fetch(`${BASE}/room`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

const get = (code) => fetch(`${BASE}/room?code=${encodeURIComponent(code)}`);

async function main() {
  const server = spawn(process.execPath, [path.join(__dirname, "server.js")], {
    env: { ...process.env, PORT: String(PORT), CODE_LEN: "4", TTL_SEC: "600" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let serverLog = "";
  server.stdout.on("data", (d) => (serverLog += d));
  server.stderr.on("data", (d) => (serverLog += d));

  try {
    console.log("【A】服务可用性");
    ck(await waitUp(), `服务在 ${PORT} 端口起来了`);

    const h = await (await fetch(`${BASE}/health`)).json();
    ck(h.ok === true, "/health 返回 ok");
    ck(h.code_len === 4, `房间号位数 = 4（实际 ${h.code_len}）`);

    console.log("【B】建房 → 拿码 → 用码查地址（核心链路）");
    const addrA = "6.tcp.cpolar.top:12345";
    const ra = await (await post({ addr: addrA, kind: "tcp" })).json();
    ck(typeof ra.code === "string", "建房拿到房间号");
    ck(/^\d+$/.test(ra.code), `房间号是纯数字（${ra.code}）`);
    ck(ra.code.length === 4, `房间号正好 4 位（实际 ${ra.code.length}）`);

    const ga = await (await get(ra.code)).json();
    ck(ga.addr === addrA, `用码查到房主地址（${ga.addr}）`);
    ck(ga.kind === "tcp", "房型 kind 一起带回来了");

    console.log("【C】多房间不串号");
    const addrB = "192.168.1.7:3457";
    const rb = await (await post({ addr: addrB, kind: "lan" })).json();
    ck(rb.code !== ra.code, "两个房间号不同");
    const gb = await (await get(rb.code)).json();
    ck(gb.addr === addrB, `B 房查到自己的地址（${gb.addr}）`);
    ck(gb.kind === "lan", "B 房的 kind = lan（局域网房）");
    const ga2 = await (await get(ra.code)).json();
    ck(ga2.addr === addrA, "A 房再查仍是自己的地址（没被 B 覆盖）");

    console.log("【D】号码永不重复（同秒内连开 40 个房）");
    const codes = new Set();
    for (let i = 0; i < 40; i++) {
      const r = await (await post({ addr: `10.0.0.${i % 250}:3457`, kind: "lan" })).json();
      codes.add(r.code);
    }
    ck(codes.size === 40, `40 次建房拿到 40 个不同号（实际 ${codes.size} 个）`);

    console.log("【E】坏输入要被挡住（不能把垃圾写进目录）");
    ck((await post({ addr: "\u4e0d\u662f\u5730\u5740" })).status === 400, "非 host:port → 400");
    ck((await post({ addr: "a.b:99999" })).status === 400, "端口越界(99999) → 400");
    ck((await post({ addr: "a.b:0" })).status === 400, "端口 0 → 400");
    ck((await post({})).status === 400, "缺 addr → 400");
    ck((await get("99999")).status === 404, "查不存在的号 → 404（5 位数必不存在）");
    ck((await get("abc")).status === 400, "非数字号 → 400");

    console.log("【F】关房后号码立即失效");
    const rc = await (await post({ addr: "1.2.3.4:3457" })).json();
    ck((await get(rc.code)).status === 200, "关房前查得到");
    const del = await fetch(`${BASE}/room?code=${rc.code}`, { method: "DELETE" });
    ck(del.status === 200, "DELETE 关房成功");
    ck((await get(rc.code)).status === 404, "关房后查不到（号已释放）");
  } catch (e) {
    fail++;
    console.error("  \u2717 自检异常：", e && e.message);
  } finally {
    server.kill();
  }

  if (fail > 0) {
    console.error("\n=== 服务端自检: PASS %d / FAIL %d ===", pass, fail);
    console.error("服务端日志：\n" + serverLog);
    process.exit(1);
  }
  console.log(`\n=== 服务端自检: PASS ${pass} / FAIL 0 ===`);
  process.exit(0);
}

main();
