#!/usr/bin/env node
/**
 * 战棋 · 云端服务（2026-10-04）
 * =============================================================================
 * 一个端口干三件事，全部零依赖（只用 Node 内置模块 + ./oss.js）：
 *
 *   1) GET  /version.json    自动更新用的版本清单（约 1 KB，代理 OSS，缓存 60s）
 *   2) POST /register        注册
 *      POST /login           登录
 *      GET  /me              用 token 换账号
 *      POST /progress        上传进度（水平档位 / 教程进度）
 *      POST /send-code       验证码。**channel 缺省 = 邮箱**（与老版逐字节一致）；
 *                            channel="sms" 走**短信**（阿里云 dypns，见 sms.js）。
 *                            带 purpose="reset" 时按**昵称**找账号，发到它绑定的渠道。
 *      POST /reset-password  忘记密码：用验证码换新密码，成功即下发 token（= 已登录）
 *      POST /bind-phone      登录后绑定手机号（action="send" 发码 / "commit" 提交）
 *      POST /bug-report      Bug 上报（直投 AgentMail，不抄送玩家本人）
 *   3) GET  /health          自检
 *
 * -----------------------------------------------------------------------------
 * 账号**存哪由 ./store.js 决定**，默认 `STORE_MODE=local` —— 存服务器本地磁盘：
 *
 *   /opt/zhanqi-cloud/accounts/<uid 前 2 位>/<uid>.json   uid = sha256(小写昵称) 前 16 位
 *
 * 设 `STORE_MODE=oss` 才改成存 OSS 对象 `zhanqi/accounts/<uid>.json`
 * （代价是每次登录/注册多一趟外网往返；容量与分片账见 store.js 头注释）。
 *
 * ★ 昵称唯一性靠**条件写**保证 —— 已存在直接 409，
 *   服务端**没有锁、也没有"先查再写"**。后者（TOCTOU）会有竞态：两个请求同时
 *   查、都说"没被占用"、都写，后写的把先写的覆盖掉。条件写是原子的，没这问题：
 *     local → fs.writeFileSync(..., { flag: 'wx' }) = O_CREAT|O_EXCL，内核级原子
 *     oss   → x-oss-forbid-overwrite: true
 *
 * ⚠️ OSS 在本项目里**不是账号主存储**，只干两件事：
 *     · /version.json 版本清单（代理读 OSS `zhanqi/version.json`，缓存 60s）
 *     · `backup_accounts.js` 每天把本地账号目录冷备到 `zhanqi/backup/`（systemd timer）
 *
 * ★ token 是**无状态 HMAC**，服务端不存 token 表：
 *       token = <uid>.<过期秒>.<HMAC-SHA256(uid.过期秒, SECRET)>
 *   所以服务重启、换机器都不影响已发出的 token（只要 SECRET 一样）。
 *
 * ⚠️ 已知限制（有意为之，不是 bug）：
 *   · 明文 HTTP，没有 TLS —— 租户没有域名就签不了证书。密码在链路上是明文，
 *     **对内测/朋友之间可接受，公开运营前必须上 HTTPS**。
 *   · /progress 是"读-改-写"覆盖，同一账号多端同时写是"后写赢"。进度是低频小数据，
 *     不做冲突合并；真要多人多端同时编辑进度再说。
 *   · 限流（试密码 / 验证码 / 老师工具 AI 次数）是单进程内存的，重启清零；
 *     但**战棋战术模型的每日额度是落盘的**（`llm_quota.json`，见下方 GAME_QUOTA），
 *     重启**不会**白送次数 —— 那正是"重启服务 = 白拿 3 次"这个漏洞的堵法。
 *   · 战棋额度：未登录 3 次/设备 + 9 次/IP 兜底；登录后 10 次/账号。IP 由 TCP 源地址取，
 *     **不读 X-Forwarded-For**，且本服务直连公网（无反向代理）⇒ 客户端伪造不了身份。
 * =============================================================================
 */
'use strict';
const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const oss = require('./oss');
const store = require('./store');   // 账号存储后端（local / oss，见 store.js 头注释）
const sms = require('./sms');       // 短信通道（阿里云 dypns 短信认证，见 sms.js 头注释）

// ── 配置 ──────────────────────────────────────────────────────────────────
const PORT = Number(process.env.PORT || 8789);
// 2026-11-24：**默认只监听本机**。公网入口统一走 nginx（https://game.learnest.cn），
//   裸 IP:8789 已关闭 —— 之前的 `0.0.0.0` 让密码在明文 HTTP 上裸奔过一段时间。
//   要在局域网里用手机直连调试：`BIND_HOST=0.0.0.0 node server.js`（明确写出来才算许可）。
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const PREFIX = 'zhanqi';
const VERSION_KEY = `${PREFIX}/version.json`;
const TOKEN_TTL_SEC = 30 * 24 * 3600;      // token 有效期 30 天
const MAX_BODY = 4096;                      // 默认请求体上限（4 KB 足够账号类接口）
const LLM_MAX_BODY = 131072;                // /llm 的请求体上限（战局卷子几 KB，留足）
const VERSION_CACHE_MS = 60 * 1000;         // 版本清单内存缓存
const NAME_MIN = 1, NAME_MAX = 24;          // 昵称：按 UTF-16 单元计（中文 1 个算 1）
const PASS_MIN = 6, PASS_MAX = 64;
const TIERS = new Set(['', 'new', 'played', 'veteran']);
const RATE_WINDOW_MS = 10 * 60 * 1000;      // 10 分钟
const RATE_MAX_FAILS = 8;                   // 同 IP 连续失败上限

// ── 邮件通道（2026-10-04 新增）─────────────────────────────────────────────
// 发信一律走**本机 mail-gateway**（8791）：邮箱授权码只在那一个服务里，
// 本进程和客户端都不持有 —— 与 LLM 走 llm-gateway 是同一个思路。
const MAIL_GATEWAY = process.env.MAIL_GATEWAY || 'http://127.0.0.1:8791/send';
const AGENT_MAIL = process.env.AGENT_MAIL || 'sgrh9516@agent.qq.com'; // Bug 上报收件人（AI 侧）
// 🔴 默认**不抄送任何人**（2026-10-04 用户明确：QQ 邮箱是私人邮箱，不要往那儿投上报邮件）。
//    保留 REPORT_CC 环境变量只是给"将来想留档"留个口子，留空 = 只投 AgentMail。
//    ⚠️ 注意：授权码所在的 SMTP 账号仍是那个 QQ 邮箱 → 邮件的 From 仍是它（这是认证账号，
//       无法更换，除非另配一个发信邮箱）。用户不希望的是**收件箱被打扰**，不是发信身份。
const REPORT_CC = String(process.env.REPORT_CC || '')
  .split(',').map((s) => s.trim()).filter(Boolean).slice(0, 3);
const MAIL_TIMEOUT_MS = 20000;
// 注册验证码（阈值均可被环境变量覆盖 —— 测试要能在秒级跑完，不必真等 60 秒冷却）
const envNum = (k, d) => {
  const v = Number(process.env[k]);
  return Number.isFinite(v) && v > 0 ? v : d;
};
const CODE_TTL_MS = envNum('CODE_TTL_MS', 5 * 60 * 1000);      // 验证码有效期 5 分钟
const CODE_RESEND_MS = envNum('CODE_RESEND_MS', 60 * 1000);    // 同邮箱重发间隔
const CODE_MAX_TRIES = envNum('CODE_MAX_TRIES', 5);            // 同一验证码最多试错次数
const CODE_PER_EMAIL_DAY = envNum('CODE_PER_EMAIL_DAY', 5);    // 同邮箱每日上限
const CODE_PER_IP_HOUR = envNum('CODE_PER_IP_HOUR', 10);
const CODE_PER_IP_DAY = envNum('CODE_PER_IP_DAY', 30);
// Bug 上报
const REPORT_PER_IP_HOUR = envNum('REPORT_PER_IP_HOUR', 5);
const REPORT_PER_IP_DAY = envNum('REPORT_PER_IP_DAY', 20);
const REPORT_MAX_BODY = 16384;
// 注册是否强制邮箱验证码（`REQUIRE_EMAIL_CODE=0` 可临时关掉，供未升级的老客户端过渡）
const REQUIRE_EMAIL_CODE = String(process.env.REQUIRE_EMAIL_CODE == null ? '1' : process.env.REQUIRE_EMAIL_CODE) !== '0';
const EMAIL_RE = /^[^\s@,;<>]{1,64}@[^\s@,;<>]+\.[A-Za-z]{2,}$/;

// ── 短信通道（2026-10-09 新增）──────────────────────────────────────────
// 产品是阿里云「**短信认证**」(dypns)，不是「短信服务」——详见 sms.js 头注释。
// 🔴 短信**每条计费**（套餐 1000 次）⇒ 限流比邮箱更严，另有全局日上限兜底。只支持大陆号。
const PHONE_RE = /^1[3-9]\d{9}$/;
const SMS_ON = process.env.SMS_DISABLED !== '1';              // 紧急开关：=1 时短信整体拒绝
const SMS_RESEND_MS = envNum('SMS_RESEND_MS', 60 * 1000);     // 同号重发间隔
const SMS_PER_PHONE_DAY = envNum('SMS_PER_PHONE_DAY', 5);     // 同号每日上限
const SMS_PER_IP_HOUR = envNum('SMS_PER_IP_HOUR', 10);
const SMS_PER_IP_DAY = envNum('SMS_PER_IP_DAY', 20);
const SMS_GLOBAL_PER_DAY = envNum('SMS_GLOBAL_PER_DAY', 200); // 全局日上限（保护套餐）
const SMS_CODE_TTL_SEC = envNum('SMS_CODE_TTL_SEC', 300);     // 与阿里云 ValidTime 一致

// ── token 密钥：env > 同目录 secret.txt > 自动生成并落盘 ────────────────────
function loadSecret() {
  if (process.env.ZHANQI_TOKEN_SECRET) return process.env.ZHANQI_TOKEN_SECRET;
  const p = path.join(__dirname, 'secret.txt');
  try {
    if (fs.existsSync(p)) {
      const s = fs.readFileSync(p, 'utf8').trim();
      if (s.length >= 32) return s;
    }
    const s = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(p, s + '\n', { mode: 0o600 });
    console.log('[init] 已生成 token 密钥 → secret.txt（权限 600）');
    return s;
  } catch (e) {
    const s = crypto.randomBytes(32).toString('hex');
    console.warn('[warn] 无法读写 secret.txt，本次使用临时密钥（重启后旧 token 失效）：' + e.message);
    return s;
  }
}
const SECRET = loadSecret();

// ── 小工具 ────────────────────────────────────────────────────────────────
const nowIso = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const trim = (s) => String(s == null ? '' : s).trim();
/** 昵称归一：大小写不敏感 → 同一个昵称不会因为大小写注册出两个账号 */
const normName = (s) => trim(s).toLowerCase();
const uidOf = (name) => crypto.createHash('sha256').update(normName(name), 'utf8').digest('hex').slice(0, 16);

function hashPass(pass, salt) {
  return crypto.scryptSync(pass, salt, 32).toString('hex');
}
function safeEqHex(a, b) {
  try {
    const ba = Buffer.from(a, 'hex'), bb = Buffer.from(b, 'hex');
    if (ba.length !== bb.length || ba.length === 0) return false;
    return crypto.timingSafeEqual(ba, bb);
  } catch { return false; }
}
function signToken(uid, exp) {
  return crypto.createHmac('sha256', SECRET).update(`${uid}.${exp}`).digest('hex');
}
function makeToken(uid) {
  const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_SEC;
  return `${uid}.${exp}.${signToken(uid, exp)}`;
}
/** 验签 + 过期检查。失败一律返回 ""，调用方不必区分原因 */
function verifyToken(tok) {
  const parts = String(tok || '').split('.');
  if (parts.length !== 3) return '';
  const [uid, expS, sig] = parts;
  const exp = Number(expS);
  if (!uid || !Number.isFinite(exp) || exp < Math.floor(Date.now() / 1000)) return '';
  const want = signToken(uid, exp);
  if (sig.length !== want.length) return '';
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) return '';
  return uid;
}
/** 对外返回的账号：**绝不含 salt / hash** */
function publicAccount(a) {
  return {
    uid: a.uid,
    name: a.name,
    email: a.email || '',
    // 手机号只回**掩码**（本人确认"绑的是我的号"够用了；完整号码只留服务端）
    phone: maskPhone(normPhone(a.phone)),
    phoneBound: !!normPhone(a.phone),
    created: a.created || '',
    progress: a.progress || { tier: '', tutorial_done: false, tutorial_hero: '' },
  };
}

// ── 登录失败限流（单进程内存） ─────────────────────────────────────────────
const fails = new Map();   // ip -> { n, first }
function isRateLimited(ip) {
  const f = fails.get(ip);
  if (!f) return false;
  if (Date.now() - f.first > RATE_WINDOW_MS) { fails.delete(ip); return false; }
  return f.n >= RATE_MAX_FAILS;
}
function noteFail(ip) {
  const f = fails.get(ip);
  if (!f || Date.now() - f.first > RATE_WINDOW_MS) fails.set(ip, { n: 1, first: Date.now() });
  else f.n += 1;
}
function clearFail(ip) { fails.delete(ip); }

// ── HTTP 辅助 ─────────────────────────────────────────────────────────────
function readBody(req, maxBytes) {
  const limit = Number(maxBytes || MAX_BODY);
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { resolve({ tooLarge: true }); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      if (!raw) return resolve({ data: {} });
      try {
        const d = JSON.parse(raw);
        resolve({ data: typeof d === 'object' && d !== null ? d : {} });
      } catch { resolve({ bad: true }); }
    });
    req.on('error', () => resolve({ bad: true }));
  });
}
// 🔴 刻意**不**发 CORS 头（2026-10-05 移除 `Access-Control-Allow-Origin: *`）：
//    游戏客户端（Godot 原生）与单机工具（桌面 exe）都不走浏览器、不需要 CORS；
//    而全放通会让**任意网页**在浏览器里跨域读取本服务响应，甚至静默消耗访客的 AI 额度
//    （AI 代理本身无身份校验，唯一门槛就是"浏览器调不到"）。
//    ⚠️ 将来若真要做网页端，改成**固定来源白名单**，别再用 `*`。
function sendJson(res, code, obj) {
  const body = Buffer.from(JSON.stringify(obj), 'utf8');
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Cache-Control': 'no-store',
  });
  res.end(body);
}
function bearer(req) {
  const h = String(req.headers['authorization'] || '');
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}
/**
 * 取调用方真实 IP（用于限流）。
 *
 * 🔴 **绝对不信任请求头里的 `X-Forwarded-For`**（2026-10-04 修正）：
 *    本服务**就是公网边缘**，前面没有任何可信代理。若信任它，客户端只要自己塞一个
 *    `X-Forwarded-For: 1.2.3.4`，就能**逐个假 IP 轮换，把按 IP 的配额完全绕过**
 *    （老师工具那 20 次/天 会形同虚设）。所以只取真实 TCP 对端地址。
 *    实测确认：伪造 XFF 的 6 次连续请求现在会算进同一个桶、第 6 次被拦。
 *
 * ⚠️ 将来若在前面加了反向代理 / SLB，要改成"只信任来自代理网段的 XFF"，
 *    否则所有真实客户端会因为你取到代理 IP 而共享一个桶。
 */
const clientIp = (req) =>
  (req.socket && req.socket.remoteAddress) || '?';

/** 是否来自本机回环（真实 TCP 对端，同样不读任何请求头）—— 用于给详情接口分级 */
const isLoopback = (req) => {
  const a = (req.socket && req.socket.remoteAddress) || '';
  return a === '127.0.0.1' || a === '::1' || a === '::ffff:127.0.0.1';
};

// ── 版本清单缓存 ──────────────────────────────────────────────────────────
let verCache = { at: 0, text: '' };
async function versionJson() {
  if (verCache.text && Date.now() - verCache.at < VERSION_CACHE_MS) return verCache.text;
  const r = await oss.getText(VERSION_KEY);
  if (!r.ok) return null;
  verCache = { at: Date.now(), text: r.text };
  return r.text;
}

// ── 冷备状态（backup_accounts.js 写的 .last_backup.json）──────────────────
// 塞进 /health 的理由：备份挂了却没人知道 = 等于没有备份。
// 这样不登服务器也能一眼看到"上次备份是什么时候、有没有报错"。
function backupState() {
  try {
    const p = path.join(path.dirname(store.LOCAL_DIR), '.last_backup.json');
    if (!fs.existsSync(p)) return { never: true };
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    return { error: '读不到备份状态: ' + e.message };
  }
}

// ══ 邮件：发信 / 注册验证码 / Bug 上报 ═══════════════════════════════════

/** 调本机 mail-gateway 发信。失败抛错，由调用方决定怎么告诉用户。 */
async function mailSend({ to, subject, text, cc }) {
  const payload = { to, subject, text };
  if (cc && cc.length) payload.cc = cc;
  const r = await fetch(MAIL_GATEWAY, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(MAIL_TIMEOUT_MS),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok || !j || j.ok !== true) throw new Error((j && j.error) || `mail-gateway HTTP ${r.status}`);
  return j;
}

/** 日志里不出现完整邮箱（避免日志本身成为一份邮箱清单） */
function maskEmail(e) {
  const [u, d] = String(e).split('@');
  if (!d) return '(?)';
  return `${u.slice(0, 2)}***@${d}`;
}

/**
 * **回给账号本人**看的邮箱掩码：首尾各留 1 个字符，如 `c***n@qq.com`。
 *
 * 为什么不复用上面那个 maskEmail：两者**受众不同、取舍相反**。
 *   · maskEmail（日志用）—— 受众是自己人排障，目标是"能认出是哪个邮箱"，
 *     所以域名给全；本地部分只留 2 字符，免得日志变成邮箱清单。
 *   · 本函数（回给本人）—— 受众是**账号持有者**，目标是让他确认"发到的是我的信箱"，
 *     沿用他熟悉的 `c***n` 形态；域名给全反而是必要的（他有多个邮箱时靠域名区分）。
 * ⚠️ 本地部分不足 3 字符时**不显示尾字符**：`ab@x.com` 若输出 `a***b@x.com`
 *    等于把整个本地部分暴露出来，等于没掩码。
 */
function maskEmailForUser(e) {
  const s = String(e == null ? '' : e);
  const at = s.lastIndexOf('@');
  if (at <= 0 || at === s.length - 1) return '';
  const u = s.slice(0, at), d = s.slice(at + 1);
  const tail = u.length >= 3 ? u.slice(-1) : '';
  return `${u.slice(0, 1)}***${tail}@${d}`;
}

function safeStrEq(a, b) {
  const ba = Buffer.from(String(a), 'utf8'), bb = Buffer.from(String(b), 'utf8');
  if (ba.length !== bb.length || ba.length === 0) return false;
  return crypto.timingSafeEqual(ba, bb);
}

// ── 注册验证码（单进程内存）──────────────────────────────────────────────
// 为什么不落盘：验证码只活 5 分钟，重启后让用户重发一次即可 —— 落盘反而多一套
//   清理逻辑和一次 IO。**代价**：多进程 / 多机部署会失效（各自的 Map 不共享），
//   到那时改 Redis 即可，接口不用动。
const codes = new Map();     // email -> { code, exp, tries, lastSent, day, dayN }
const codeIp = new Map();    // ip    -> { hourAt, hourN, day, dayN }

const genCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

/**
 * 作废验证码，但**保留记账字段**（`lastSent` / `day` / `dayN`）。
 *
 * 🔴 2026-10-05 修（用户批准）：原先三处作废都写 `codes.delete(email)`，把整条记录连
 *    **60 秒重发冷却**与**同邮箱 5 封/天**的计数一起抹掉 ⇒ 每成功注册/改密一次，那个邮箱的
 *    冷却与日配额就**归零**：能立刻重发、日上限形同虚设（只剩按 IP 的 10 封/时 + 30 封/天兜）。
 *    实测证据：注册码 `17:48:07` 发出，重置码 `17:48:36` 就出去了（相隔 **29 秒** ≪ 60 秒冷却）；
 *    紧接着第三次请求被正常拦下（429「请 48 秒后再试」）⇒ 冷却逻辑本身是好的，
 *    是"记录被删"造成的**计数清零**（注意：不是"记录被刷新"——刷新会把值留下，这里是值没了）。
 * ⚠️ 必须把 `code` 清成 `''`：`codeTake()` 第一行靠 `!rec.code` 判"没有可用的码"，
 *    留成旧值会让同一张码被**重复使用**（防重放就废了）。
 */
function codeDrop(rec) {
  rec.code = '';
  rec.exp = 0;
  rec.tries = 0;
}

/**
 * 顺手回收"没有待用码"的老记录。
 *
 * 为什么需要：`codeDrop()` 不再删记录（要保住冷却与日配额），于是一旦某个邮箱发过码，
 * 它的记录就会**长期留着** ⇒ Map 随"发过码的不同邮箱数"单调增长。
 * 这条 GC 只清**同时满足**下列三条的条目 —— 它们再也不可能被 `codeRateCheck` 用到：
 *   ① 没有待用的码  ② 不是今天的（日配额只在同一天内有效）  ③ 不在冷却窗口内
 * 用计数器每 100 次发码扫一遍：O(n) 全扫不值当每次都做。
 */
let _codeGcTick = 0;
function codeGc() {
  if ((_codeGcTick = (_codeGcTick + 1) % 100) !== 0) return;
  const now = Date.now(), day = _todayBJ();
  for (const [k, v] of codes) {
    if (v.code) continue;
    if (v.day === day) continue;
    if (now - (v.lastSent || 0) < CODE_RESEND_MS) continue;
    codes.delete(k);
  }
}

/** 返回 "" 表示放行，否则是给用户看的中文原因 */
function codeRateCheck(ip, email) {
  const now = Date.now(), day = _todayBJ();
  const rec = codes.get(email);
  if (rec && rec.lastSent && now - rec.lastSent < CODE_RESEND_MS) {
    const wait = Math.ceil((CODE_RESEND_MS - (now - rec.lastSent)) / 1000);
    return `验证码刚发过，请 ${wait} 秒后再试`;
  }
  if (rec && rec.day === day && rec.dayN >= CODE_PER_EMAIL_DAY) {
    return '这个邮箱今天收到的验证码太多了，明天再试';
  }
  let r = codeIp.get(ip);
  if (!r) { r = { hourAt: now, hourN: 0, day, dayN: 0 }; codeIp.set(ip, r); }
  if (now - r.hourAt > 3600000) { r.hourAt = now; r.hourN = 0; }
  if (r.day !== day) { r.day = day; r.dayN = 0; }
  if (r.hourN >= CODE_PER_IP_HOUR) return '操作太频繁，请过一会儿再试';
  if (r.dayN >= CODE_PER_IP_DAY) return '今天验证码发得太多了，明天再试';
  return '';
}

/** 记账（发信成功后调用），返回该邮箱的记录，供写入验证码 */
function codeNote(ip, email) {
  const now = Date.now(), day = _todayBJ();
  let rec = codes.get(email);
  if (!rec) { rec = { code: '', exp: 0, tries: 0, lastSent: 0, day, dayN: 0 }; codes.set(email, rec); }
  if (rec.day !== day) { rec.day = day; rec.dayN = 0; }
  rec.lastSent = now; rec.dayN += 1;
  const r = codeIp.get(ip);
  if (r) { r.hourN += 1; r.dayN += 1; }
  codeGc();                     // 见 codeGc()：codeDrop 不再删记录，靠它兜住 Map 增长
  return rec;
}

/**
 * 校验并**立即作废**验证码（防重放）。
 * 成功返回 { ok:true, saved } —— saved 是作废前的快照，供"码对了但注册失败（昵称被占）"
 * 时用 codeRestore() 放回去，避免用户白等 60 秒冷却。
 *
 * ⚠️ 作废一律走 `codeDrop()`（只清 `code/exp/tries`），**不要**改回 `codes.delete(email)` ——
 *    那会把 `lastSent`（60 秒冷却）与 `day/dayN`（同邮箱 5 封/天）一起抹掉，见 codeDrop 的注释。
 */
function codeTake(email, code) {
  const rec = codes.get(email);
  if (!rec || !rec.code) return { ok: false, error: '请先点「获取验证码」' };
  if (Date.now() > rec.exp) { codeDrop(rec); return { ok: false, error: '验证码已过期，请重新获取' }; }
  if (rec.tries >= CODE_MAX_TRIES) {
    codeDrop(rec);
    return { ok: false, error: '验证码错误次数过多，请重新获取' };
  }
  if (!safeStrEq(rec.code, code)) {
    rec.tries += 1;
    const left = Math.max(0, CODE_MAX_TRIES - rec.tries);
    return { ok: false, error: left ? `验证码不正确（还可试 ${left} 次）` : '验证码错误次数过多，请重新获取' };
  }
  const saved = { code: rec.code, exp: rec.exp, tries: rec.tries, lastSent: rec.lastSent, day: rec.day, dayN: rec.dayN };
  codeDrop(rec);
  return { ok: true, saved };
}
function codeRestore(email, saved) { if (saved) codes.set(email, saved); }

/**
 * POST /send-code {email}                 → 给该邮箱发 6 位**注册**验证码
 * POST /send-code {name, purpose:"reset"} → 给该昵称账号绑定的邮箱发**重置**验证码
 *   （分流在函数第一行；**不传 name/purpose 时行为与以前逐字节一致**）
 */
async function handleSendCode(req, res) {
  const ip = clientIp(req);
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  // 🔴 忘记密码走这里分流。**必须放在邮箱校验之前**（reset 请求体里根本没有 email）。
  //    已发布的客户端仍用 {email} 调本接口发注册码 —— 那边不带 purpose，走下面的老路。
  if (trim(data.purpose).toLowerCase() === 'reset') return handleSendResetCode(res, ip, data);

  // ── 短信通道：**必须显式传 channel="sms"**；不传一律走下面的邮箱老路
  //    （已发布客户端只会发 {email}，语义不能变，否则老客户端注册直接坏）
  if (trim(data.channel).toLowerCase() === 'sms') return handleSendRegisterSms(res, ip, data);

  const email = trim(data.email).toLowerCase();
  if (!EMAIL_RE.test(email)) return sendJson(res, 400, { ok: false, error: '邮箱格式不对' });

  const why = codeRateCheck(ip, email);
  if (why) {
    console.log(`[code] 限流 ip=${ip} email=${maskEmail(email)} :: ${why}`);
    return sendJson(res, 429, { ok: false, error: why });
  }

  // 【2026-10-05 修复】发信失败要**回滚到发信前的完整状态**，而不是简单删记录。
  //   原写法 `codes.delete(email)` 会把**用户手上那张还没过期的旧码一起作废**，
  //   且随后的 `rec.lastSent = 0` 作用在已被移出 Map 的孤立对象上、对 Map 无效 ——
  //   结果是"点重发失败 → 原来那张能用的码也用不了了，且没有任何提示"。
  const prevRec = codes.get(email);
  const prevSnap = prevRec ? { code: prevRec.code, exp: prevRec.exp, tries: prevRec.tries } : null;
  const ipRec = codeIp.get(ip);
  const ipHourN0 = ipRec ? ipRec.hourN : 0;
  const ipDayN0 = ipRec ? ipRec.dayN : 0;

  const rec = codeNote(ip, email);          // 先记账（抢冷却），发失败再退
  rec.code = genCode();
  rec.exp = Date.now() + CODE_TTL_MS;
  rec.tries = 0;

  try {
    await mailSend({ to: email, subject: '【战棋】注册验证码', text: codeMailText(rec.code) });
  } catch (e) {
    if (prevSnap) {                          // 有旧记录 → 整条放回（旧码继续有效）
      prevRec.code = prevSnap.code; prevRec.exp = prevSnap.exp; prevRec.tries = prevSnap.tries;
      prevRec.lastSent = 0;                  // 退掉冷却，让用户能立刻重试
      if (prevRec.dayN > 0) prevRec.dayN -= 1;
      codes.set(email, prevRec);
    } else {
      codes.delete(email);
    }
    if (ipRec) { ipRec.hourN = ipHourN0; ipRec.dayN = ipDayN0; }
    console.error('[code] 发信失败（已回滚到发信前状态，旧码仍有效）:', e.message);
    return sendJson(res, 502, { ok: false, error: '验证码发送失败，请稍后再试' });
  }
  console.log(`[code] 已发送 email=${maskEmail(email)} ip=${ip}（今日第 ${rec.dayN} 封）`);
  return sendJson(res, 200, {
    ok: true, ttl: Math.floor(CODE_TTL_MS / 1000), resendAfter: Math.floor(CODE_RESEND_MS / 1000),
  });
}

function codeMailText(code) {
  return [
    `你的注册验证码是：${code}`,
    '',
    `${Math.floor(CODE_TTL_MS / 60000)} 分钟内有效。如果不是你本人操作，忽略本邮件即可。`,
    '',
    '—— 骑士外传 · 战棋',
  ].join('\n');
}

// ══ 忘记密码（2026-10-05）═══════════════════════════════════════════════
// 客户端早已实现并自测通过，服务端按 `docs/忘记密码_接口契约.md` 补齐这两条。
// 设计的地基是 handleRegister 里那条不变量：账号**只绑定"验证过"的邮箱**
// （过渡档里"填了邮箱但没走验证码"一律存空串）—— 所以重置码永远发不到
// 攻击者能指定的地址，只能是账号自己的信箱。

function resetMailText(code) {
  return [
    '你正在重置《骑士外传 · 战棋》的账号密码。',
    '',
    `重置验证码是：${code}`,
    '',
    `${Math.floor(CODE_TTL_MS / 60000)} 分钟内有效。如果不是你本人操作，忽略本邮件即可 —— 你的密码不会被改动。`,
    '',
    '—— 骑士外传 · 战棋',
  ].join('\n');
}

/**
 * POST /send-code {name, purpose:"reset"} → 给**该昵称对应账号自己绑定的**邮箱发重置码。
 *
 * 🔴 三条不变量，改之前先想清楚：
 *  1. **收件地址只从账号里取**（`acct.email`），绝不看请求体里的任何地址
 *     ⇒ 不存在"把重置信发到受害者信箱"的路径。
 *  2. 限流/冷却**复用注册那一套**（同一个 codes/codeIp、同一组阈值）。
 *     为 reset 另开一套 = 发信额度翻倍 = 直接可以拿来刷别人的邮箱。
 *  3. 与注册码**共用同一个 codes Map**（键=邮箱）是有意的：同一邮箱任意时刻只有一张
 *     有效码；而且两种码都只有"能收到该邮箱信件的人"才拿得到，互相**不可提权**。
 *     ⇒ 契约里"成功后作废该账号所有未用验证码"天然满足（一次只可能有一张）。
 *
 * ⚠️ **残留风险（有意接受，别当成已解决）**：本接口对"存在且有绑定邮箱"的昵称会回
 *    `masked`，因此**可被用来枚举昵称是否存在**（拿到掩码=存在）。要彻底消除只能
 *    一律回同一句"如果该账号存在，我们已发送重置邮件"，但那样用户就看不到"发到哪了"。
 *    取舍依据：这是内测/朋友间的服务（见文件头"已知限制"），且限流（同 IP 10 封/时 +
 *    30 封/天、同邮箱 5 封/天）让枚举既慢又吵——每次命中都会往对方信箱投一封真邮件。
 *    将来若公开运营，改成统一文案即可，客户端那句提示无需动。
 */
async function handleSendResetCode(res, ip, data) {
  const name = trim(data.name);
  if (!name) return sendJson(res, 400, { ok: false, error: '请先填昵称' });

  // 短信通道：按昵称找账号 → 发到它**自己绑定的**手机号（绝不看请求体里的号码）
  if (trim(data.channel).toLowerCase() === 'sms') return handleSendResetSms(res, ip, name);

  let g;
  try { g = await store.getAccount(uidOf(name)); }
  catch (e) {
    console.error('[reset] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  const email = (g.ok && g.data && typeof g.data.email === 'string')
    ? g.data.email.trim().toLowerCase() : '';

  // 昵称不存在 / 该账号没绑邮箱 → **同一个**"成功了但没发"的响应。
  //   不报错（客户端把 masked=="" 呈现为"无法自助找回"），也不区分这两种情况。
  if (!email) {
    console.log(`[reset] 无可用邮箱（昵称不存在或未绑定邮箱） ip=${ip}`);
    return sendJson(res, 200, { ok: true, masked: '', ttl: Math.floor(CODE_TTL_MS / 1000) });
  }

  const why = codeRateCheck(ip, email);
  if (why) {
    console.log(`[reset] 限流 ip=${ip} email=${maskEmail(email)} :: ${why}`);
    return sendJson(res, 429, { ok: false, error: why });
  }

  // 发信失败必须**回滚到发信前的完整状态**（与 handleSendCode 同一处修复的同一理由）：
  //   简单 `codes.delete(email)` 会把用户手上那张还没过期的旧码一起废掉，且毫无提示。
  const prevRec = codes.get(email);
  const prevSnap = prevRec ? { code: prevRec.code, exp: prevRec.exp, tries: prevRec.tries } : null;
  const ipRec = codeIp.get(ip);
  const ipHourN0 = ipRec ? ipRec.hourN : 0;
  const ipDayN0 = ipRec ? ipRec.dayN : 0;

  const rec = codeNote(ip, email);           // 先记账（抢冷却），发失败再退
  rec.code = genCode();
  rec.exp = Date.now() + CODE_TTL_MS;
  rec.tries = 0;

  try {
    await mailSend({ to: email, subject: '【战棋】重置密码验证码', text: resetMailText(rec.code) });
  } catch (e) {
    if (prevSnap) {
      prevRec.code = prevSnap.code; prevRec.exp = prevSnap.exp; prevRec.tries = prevSnap.tries;
      prevRec.lastSent = 0;                  // 退掉冷却，让用户能立刻重试
      if (prevRec.dayN > 0) prevRec.dayN -= 1;
      codes.set(email, prevRec);
    } else {
      codes.delete(email);
    }
    if (ipRec) { ipRec.hourN = ipHourN0; ipRec.dayN = ipDayN0; }
    console.error('[reset] 发信失败（已回滚到发信前状态，旧码仍有效）:', e.message);
    return sendJson(res, 502, { ok: false, error: '验证码发送失败，请稍后再试' });
  }
  console.log(`[reset] 已发送 email=${maskEmail(email)} ip=${ip}（今日第 ${rec.dayN} 封）`);
  return sendJson(res, 200, {
    ok: true,
    masked: maskEmailForUser(email),
    ttl: Math.floor(CODE_TTL_MS / 1000),
    resendAfter: Math.floor(CODE_RESEND_MS / 1000),
  });
}

/**
 * POST /reset-password {name, code, newpass} → 用重置码换新密码，成功即下发 token（= 已登录）。
 *
 * ★ 顺序很重要：**先做纯本地校验（码格式 / 密码长度），再消费验证码**。
 *   反过来的话，"密码太短"这种本地错误会把码烧掉，用户得白等 60 秒重发
 *   —— 与 handleRegister 里 codeRestore 是同一个考虑。
 *
 * ★ 枚举防护靠"结构性一致"而不是靠文案：昵称不存在 ⇒ 取不到 email ⇒ email='' ⇒
 *   `codeTake('', ...)` 取不到记录 ⇒ 与"没点过获取验证码"返回**同一句**。
 *   所以这里**不要**为"昵称不存在"另写一句专属提示 —— 那正好是枚举探测器。
 */
async function handleResetPassword(req, res) {
  const ip = clientIp(req);
  if (isRateLimited(ip)) return sendJson(res, 429, { ok: false, error: '尝试次数过多，请十分钟后再试' });
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  const name = trim(data.name);
  const code = trim(data.code);
  const newpass = String(data.newpass == null ? '' : data.newpass);
  // 本地校验失败【不计】失败次数 —— 密码长度写错不该把用户往"十分钟后再试"推
  const rej = (msg) => sendJson(res, 400, { ok: false, error: msg });
  // 码相关的失败才计数（这是真正会被暴力猜的那一面）
  const rejCode = (msg) => { noteFail(ip); return sendJson(res, 400, { ok: false, error: msg }); };

  if (!name) return rej('请先填昵称');
  if (!/^\d{6}$/.test(code)) return rej('请填 6 位数字验证码');
  if (newpass.length < PASS_MIN || newpass.length > PASS_MAX) {
    return rej(`密码需要 ${PASS_MIN}~${PASS_MAX} 位`);
  }

  let g;
  try { g = await store.getAccount(uidOf(name)); }
  catch (e) {
    console.error('[reset] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  const email = (g.ok && g.data && typeof g.data.email === 'string')
    ? g.data.email.trim().toLowerCase() : '';

  // ── 短信通道（channel="sms"）：验证码在**阿里云**侧存储与校验，不经本地 codes Map ──
  //    ⚠️ 这里刻意**不复用**下面邮箱路径的落库代码：邮箱那条有"失败要把码放回"的语义
  //    （codeRestore），短信码是一次性的、放不回去 —— 两条路的失败处理不同，硬合并更危险。
  if (trim(data.channel).toLowerCase() === 'sms') {
    const ph = (g.ok && g.data) ? normPhone(g.data.phone) : '';
    if (!PHONE_RE.test(ph)) {
      // 未绑手机号 / 昵称不存在 → 与"码不对"同一句，不给枚举探测器
      console.log(`[reset] sms 通道但账号未绑手机号（或不存在的昵称） ip=${ip}`);
      noteFail(ip);
      return sendJson(res, 400, { ok: false, error: '验证码不正确或已过期' });
    }
    if (!(await smsCheckOrFail(res, ph, code))) { noteFail(ip); return; }
    if (!g.ok || !g.data) {
      console.error('[reset] 异常状态：验码通过却取不到账号');
      return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
    }
    const acctS = g.data;
    const saltS = crypto.randomBytes(16).toString('hex');
    acctS.salt = saltS;
    acctS.hash = hashPass(newpass, saltS);
    acctS.updated = nowIso();
    // ⚠️ 只动 salt/hash/updated：uid / name / created / email / phone / progress 一律保留
    try {
      const rS = await store.saveAccount(acctS.uid, acctS);
      if (!rS.ok) {
        console.error('[reset] 写回失败:', rS.error || '');
        return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
      }
    } catch (e) {
      console.error('[reset] 存储异常:', e.message);
      return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
    }
    clearFail(ip);
    console.log(`[reset] 改密成功(sms) uid=${acctS.uid}`);
    return sendJson(res, 200, { ok: true, token: makeToken(acctS.uid), account: publicAccount(acctS) });
  }

  const c = codeTake(email, code);          // 成功即已作废该邮箱上的码（防重放）
  if (!c.ok) return rejCode(c.error);
  if (!g.ok || !g.data || !email) {
    // 走不到：没有 email 就取不到码。留着当护栏，避免将来改动引入空引用崩溃。
    console.error('[reset] 异常状态：验码通过却取不到账号 ip=' + ip);
    return rejCode('验证码不正确，请重新获取');
  }

  const acct = g.data;
  const uid = acct.uid || uidOf(name);
  const salt = crypto.randomBytes(16).toString('hex');
  acct.salt = salt;                         // 重算加盐 —— 换 salt 顺带废掉"旧哈希预计算"的可能
  acct.hash = hashPass(newpass, salt);
  acct.updated = nowIso();
  // ⚠️ 只动 salt/hash/updated：uid / name / created / email / progress 一律原样保留
  //   （progress 是玩家的档位与教程进度，改密码不能顺手清档）

  try {
    const r = await store.saveAccount(uid, acct);
    if (!r.ok) {
      console.error('[reset] 写回失败:', r.error || '');
      codeRestore(email, c.saved);          // 放回验证码，别让用户白等冷却
      return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
    }
  } catch (e) {
    codeRestore(email, c.saved);
    console.error('[reset] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }

  // 契约要求"作废该账号所有未用的验证码"：`codeTake()` 已经把该邮箱的码作废了
  //   （register / reset 两类共用同一个 Map ⇒ 两类一起清）。
  // ⚠️ 这里**绝对不要**再写 `codes.delete(email)` —— 那会把 `lastSent` / `day` / `dayN`
  //    一并删掉，等于又把该邮箱的 60 秒冷却与日配额清零。
  //    （2026-10-05 本地测试台抓到的：同邮箱 2 封/天的上限在"注册→改密"之后失效。）
  clearFail(ip);
  console.log(`[reset] 改密成功 uid=${uid}`);
  return sendJson(res, 200, { ok: true, token: makeToken(uid), account: publicAccount(acct) });
}

// ── Bug 上报 ─────────────────────────────────────────────────────────────
const reportIp = new Map();  // ip -> { hourAt, hourN, day, dayN }

function reportRateCheck(ip) {
  const now = Date.now(), day = _todayBJ();
  let r = reportIp.get(ip);
  if (!r) { r = { hourAt: now, hourN: 0, day, dayN: 0 }; reportIp.set(ip, r); }
  if (now - r.hourAt > 3600000) { r.hourAt = now; r.hourN = 0; }
  if (r.day !== day) { r.day = day; r.dayN = 0; }
  if (r.hourN >= REPORT_PER_IP_HOUR) return '上报太频繁了，过一会儿再试';
  if (r.dayN >= REPORT_PER_IP_DAY) return '今天上报的次数用完了，明天再试';
  r.hourN += 1; r.dayN += 1;
  return '';
}

/** 主题里不能有换行（否则可被注入额外邮件头） */
const oneLine = (s) => String(s == null ? '' : s).replace(/[\r\n]+/g, ' ').trim();

/**
 * POST /bug-report —— 玩家在游戏里点「上报」，**服务端直接投递给 AgentMail**。
 * 取代原来的"引导玩家自己开邮箱发信"（那种方式玩家连主题都不填，实测收到过「(无主题)」）。
 */
async function handleBugReport(req, res) {
  const ip = clientIp(req);
  const { data, bad, tooLarge } = await readBody(req, REPORT_MAX_BODY);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '内容太长了，精简一点再发' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  const detail = String(data.detail == null ? '' : data.detail).replace(/\r\n/g, '\n').slice(0, 8000);
  if (detail.trim().length < 4) return sendJson(res, 400, { ok: false, error: '请把问题描述清楚一点' });

  const why = reportRateCheck(ip);
  if (why) {
    console.log(`[report] 限流 ip=${ip} :: ${why}`);
    return sendJson(res, 429, { ok: false, error: why });
  }

  const title = oneLine(data.title).slice(0, 120);
  const summary = title || oneLine(detail.split('\n')[0]).slice(0, 60) || '(无标题)';
  const id = 'R' + Date.now().toString(36) + crypto.randomBytes(2).toString('hex');

  const text = [
    `上报编号：${id}`,
    `时间：${nowIso()}`,
    `版本：${oneLine(data.version).slice(0, 40) || '(未提供)'}`,
    `平台：${oneLine(data.platform).slice(0, 40) || '(未提供)'}`,
    `玩家：${oneLine(data.name).slice(0, 24) || '(未登录)'}`,
    `账号：${oneLine(data.uid).slice(0, 32) || '-'}`,
    `联系方式：${oneLine(data.contact).slice(0, 120) || '(未留)'}`,
    `分类：${oneLine(data.category).slice(0, 20) || '其他'}`,
    `来源 IP：${ip}`,
    '',
    '────── 问题描述 ──────',
    detail.trim(),
    '',
    `（本邮件由战棋服务端自动投递；直接回复此邮件不会送达玩家）`,
  ].join('\n');

  try {
    // ✅ 只投 AgentMail。**不抄送用户本人邮箱**（那是私人邮箱）。
    await mailSend({ to: AGENT_MAIL, subject: `【战棋Bug上报】${summary}`, text, cc: REPORT_CC });
  } catch (e) {
    console.error(`[report] ${id} 投递失败:`, e.message);
    return sendJson(res, 502, { ok: false, error: '上报通道暂时不通，请稍后再试' });
  }
  console.log(`[report] ${id} -> ${AGENT_MAIL} ip=${ip} ver=${oneLine(data.version).slice(0, 16) || '-'}`);
  return sendJson(res, 200, { ok: true, id });
}

// ── 业务 ──────────────────────────────────────────────────────────────────

// ── 注册 IP 限流（2026-10-09）────────────────────────────────────────────
// 背景：`REQUIRE_EMAIL_CODE=0` 的过渡窗口里，“裸注册”（不带任何验证码）是**唯一没有
//   验证码把关**的入口 ⇒ 可被脚本批量灌垃圾号（email-gate.conf 里点名的就是这个洞）。
// ⚠️ **只对“没走任何验证码”的注册计数**：
//   · 带邮箱码 / 短信码的注册已有各自的 60 秒冷却 + 每日上限，不受这里影响；
//   · 于是闸门切回 1 后这条路径自然失效（那时无码注册会被直接 400），不必再改代码。
// 额度按**建号成功**计（昵称被占反复重试不消耗），避免误伤正常玩家。
const REG_PER_IP_HOUR = envNum('REG_PER_IP_HOUR', 5);   // 裸注册：同 IP 每小时上限
const REG_PER_IP_DAY = envNum('REG_PER_IP_DAY', 20);    // 裸注册：同 IP 每日上限
const regIp = new Map();               // ip -> { hourAt, hourN, day, dayN }

/** 返回 "" 放行，否则是给用户看的中文原因（只查不计） */
function regRateCheck(ip) {
  const now = Date.now(), day = _todayBJ();
  const r = regIp.get(ip);
  if (!r) return '';
  if (r.day !== day) return '';                      // 跨天：下次计数时会重建
  if (now - r.hourAt > 3600000) return '';           // 滑出小时窗
  if (r.hourN >= REG_PER_IP_HOUR) return `这台设备注册太频繁了（每小时最多 ${REG_PER_IP_HOUR} 个账号），过一会儿再试`;
  if (r.dayN >= REG_PER_IP_DAY) return `这台设备今天注册的新账号太多了（上限 ${REG_PER_IP_DAY} 个），明天再试`;
  return '';
}

/** 只在**建号成功**时调 */
function regNote(ip) {
  const now = Date.now(), day = _todayBJ();
  let r = regIp.get(ip);
  if (!r) { r = { hourAt: now, hourN: 0, day: day, dayN: 0 }; regIp.set(ip, r); }
  if (r.day !== day) { r.day = day; r.dayN = 0; }
  if (now - r.hourAt > 3600000) { r.hourAt = now; r.hourN = 0; }
  r.hourN += 1; r.dayN += 1;
}

/** 注册：条件写保证昵称唯一（原子） */
async function handleRegister(req, res) {
  const ip = clientIp(req);
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });
  const name = trim(data.name), pass = String(data.pass == null ? '' : data.pass);
  if (name.length < NAME_MIN || name.length > NAME_MAX) {
    return sendJson(res, 400, { ok: false, error: `昵称需要 ${NAME_MIN}~${NAME_MAX} 个字` });
  }
  if (pass.length < PASS_MIN || pass.length > PASS_MAX) {
    return sendJson(res, 400, { ok: false, error: `密码需要 ${PASS_MIN}~${PASS_MAX} 位` });
  }

  // ── 短信注册通道（2026-10-09）：**必须显式传 channel="sms"** ──
  //    不传就是下面的邮箱老路（已发布客户端的语义不能变）。
  if (trim(data.channel).toLowerCase() === 'sms') return handleRegisterBySms(res, name, pass, data);

  // ── 邮箱验证码（2026-10-04；2026-10-05 修了一个**能让验证码完全失效**的洞）──
  // 🔴 原写法 `if (REQUIRE_EMAIL_CODE || code)` 里 `code` 是 **falsy 判断**：
  //    JS 中 `""` / `null` 都为假 ⇒ 客户端只要**不带 code**（或带空串），
  //    整个邮箱+验证码校验就被跳过。2026-10-05 实测：不带 code / `code:""` /
  //    `code:null` 三种请求**全部注册成功**；而客户端 CloudApi.register() 只在
  //    `code != ""` 时才带上该字段 ⇒ UI 里验证码为空时，服务端直接放行。
  //    ⇒ **教训：判断"客户端有没有带某字段"绝不能用 falsy，要用显式的存在性判断。**
  // ⚠️ `REQUIRE_EMAIL_CODE=0` 是**危险开关**（等于把邮箱校验整个关掉），只应作为
  //    "老客户端升级窗口"短暂存在；线上已由 drop-in 显式置为 1（见 email-gate.conf）。
  const email = trim(data.email).toLowerCase();
  const codeRaw = data.code;
  const code = trim(codeRaw);
  const hasCodeField = typeof codeRaw === 'string' && codeRaw.trim() !== '';
  let saved = null;
  if (REQUIRE_EMAIL_CODE || hasCodeField) {
    if (!EMAIL_RE.test(email)) return sendJson(res, 400, { ok: false, error: '请填一个能收到信的邮箱' });
    if (!/^\d{6}$/.test(code)) return sendJson(res, 400, { ok: false, error: '请填 6 位数字验证码' });
    const c = codeTake(email, code);
    if (!c.ok) return sendJson(res, 400, { ok: false, error: c.error });
    saved = c.saved;
  } else {
    // ⚠️ 走到这里 = 既没开闸门（REQUIRE_EMAIL_CODE=0）也没带码 = 裸注册。
    //    这是过渡期唯一没有验证码把关的入口 ⇒ 靠 IP 限流兜底。
    const why = regRateCheck(ip);
    if (why) {
      console.log(`[register] 限流 ip=${ip}（裸注册）:: ${why}`);
      return sendJson(res, 429, { ok: false, error: why });
    }
  }

  // 建号收敛到 createAccountCore（与短信通道共用，避免两条路把账号形状写歪）。
  // `onExists` = 昵称被占时把邮箱验证码放回去（否则用户白等 60 秒冷却）。
  // `onCreated` = **只在建号成功**时调 —— 裸注册此刻记一笔 IP 额度。
  return createAccountCore(res, name, pass, { email: saved ? email : '' },
    () => codeRestore(email, saved),
    hasCodeField || REQUIRE_EMAIL_CODE ? null : () => regNote(ip));
}


// ══ 短信通道（2026-10-09）════════════════════════════════════════════════
// 产品是阿里云「**短信认证**」(dypns)，不是「短信服务」——详见 ./sms.js 头注释。三条红线：
//   1. **绝不按请求体里的手机号**发"找回密码"的码 —— 只发到账号**自己绑定的**号，
//      否则就是把重置验证码投给攻击者指定的号码。
//   2. **每次调用都计费**（套餐 1000 次）⇒ 限流比邮箱更严，另有**全局日上限**兜底。
//   3. 验证码由**阿里云存储与校验**（发码时传 `##code##` 占位符）⇒ 本地没有短信码表，
//      因而也没有"重放"问题：`CheckSmsVerifyCode` 是一次性消费。

/** 归一：去空格/横线/括号、去 +86 前缀 ⇒ 统一成 11 位 */
function normPhone(s) {
  let t = String(s == null ? '' : s).replace(/[\s\-()]/g, '');
  if (t.startsWith('+86')) t = t.slice(3);
  else if (t.startsWith('86') && t.length === 13) t = t.slice(2);
  return t;
}
/** 回给**账号本人**看的掩码：`182****0225`（完整号码只留服务端） */
function maskPhone(p) {
  const s = String(p == null ? '' : p);
  return PHONE_RE.test(s) ? `${s.slice(0, 3)}****${s.slice(-4)}` : '';
}

const smsPhone = new Map();            // phone -> { lastSent, day, dayN }
const smsIp = new Map();               // ip    -> { hourAt, hourN, day, dayN }
let smsGlobal = { day: '', dayN: 0 };  // 全局日计数（保护 1000 次套餐）

/** 返回 "" 放行，否则是给用户看的中文原因。**调用即记账**（发失败要 smsUnnote 退）。 */
function smsRateCheck(ip, phone) {
  const now = Date.now(), day = _todayBJ();
  if (!SMS_ON) return '短信通道暂时不可用，请改用邮箱验证';
  if (!sms.available()) return '短信通道暂时不可用，请改用邮箱验证';
  if (smsGlobal.day !== day) smsGlobal = { day: day, dayN: 0 };
  if (smsGlobal.dayN >= SMS_GLOBAL_PER_DAY) return '今天短信额度已用完，请改用邮箱验证';

  let pr = smsPhone.get(phone);
  if (!pr) { pr = { lastSent: 0, day: day, dayN: 0 }; smsPhone.set(phone, pr); }
  if (pr.day !== day) { pr.day = day; pr.dayN = 0; }
  if (pr.lastSent && now - pr.lastSent < SMS_RESEND_MS) {
    return `请 ${Math.ceil((SMS_RESEND_MS - (now - pr.lastSent)) / 1000)} 秒后再试`;
  }
  if (pr.dayN >= SMS_PER_PHONE_DAY) return '这个手机号今天的验证码次数用完了，明天再试，或改用邮箱验证';

  let ir = smsIp.get(ip);
  if (!ir) { ir = { hourAt: now, hourN: 0, day: day, dayN: 0 }; smsIp.set(ip, ir); }
  if (now - ir.hourAt > 3600000) { ir.hourAt = now; ir.hourN = 0; }
  if (ir.day !== day) { ir.day = day; ir.dayN = 0; }
  if (ir.hourN >= SMS_PER_IP_HOUR) return '操作太频繁了，过一会儿再试';
  if (ir.dayN >= SMS_PER_IP_DAY) return '今天这台设备的短信次数用完了，明天再试';

  pr.lastSent = now; pr.dayN += 1;
  ir.hourN += 1; ir.dayN += 1;
  smsGlobal.dayN += 1;
  return '';
}

/** 发失败时退账 + 退冷却（否则用户白等 60 秒） */
function smsUnnote(ip, phone) {
  const pr = smsPhone.get(phone);
  if (pr) { if (pr.dayN > 0) pr.dayN -= 1; pr.lastSent = 0; }
  const ir = smsIp.get(ip);
  if (ir) { if (ir.dayN > 0) ir.dayN -= 1; if (ir.hourN > 0) ir.hourN -= 1; }
  if (smsGlobal.dayN > 0) smsGlobal.dayN -= 1;
}

/**
 * 按手机号找账号：扫本地账号目录（账号量级百级，O(n) 读文件是毫秒级）。
 * 为什么不用"手机号索引文件"：索引会漂移，而这里**正确性优先**（注册/绑定靠它判唯一）。
 * STORE_MODE=oss 时直接返回 null（当前线上是 local；真换 OSS 再补索引）。
 */
function findAccountByPhone(phone) {
  const root = store.LOCAL_DIR;
  let shards = [];
  try { shards = fs.readdirSync(root, { withFileTypes: true }); } catch (e) { return null; }
  for (const d of shards) {
    if (!d.isDirectory()) continue;
    let files = [];
    try { files = fs.readdirSync(path.join(root, d.name)); } catch (e) { continue; }
    for (const f of files) {
      if (!f.endsWith('.json')) continue;
      try {
        const a = JSON.parse(fs.readFileSync(path.join(root, d.name, f), 'utf8'));
        if (a && normPhone(a.phone) === phone) return a;
      } catch (e) { /* 单个坏文件跳过，不影响整体 */ }
    }
  }
  return null;
}

/** 校验短信码；失败时**自己发好响应**并返回 false（调用方只管 `return`） */
async function smsCheckOrFail(res, phone, code) {
  let r;
  try {
    r = await sms.checkVerifyCode(phone, code);
  } catch (e) {
    console.error('[sms] 校验异常:', e.message);
    sendJson(res, 502, { ok: false, error: '短信通道暂时不可用，请改用邮箱验证' });
    return false;
  }
  if (!r.ok) {
    console.log(`[sms] 校验未通过 phone=${maskPhone(phone)} code=${r.code} ${r.message}`);
    sendJson(res, 400, { ok: false, error: '验证码不正确或已过期' });
    return false;
  }
  return true;
}

/** 发短信验证码（共用）。true = 已发出 */
async function smsSendOrFail(res, ip, phone, purpose) {
  const why = smsRateCheck(ip, phone);
  if (why) {
    console.log(`[sms] 限流 ip=${ip} phone=${maskPhone(phone)} :: ${why}`);
    sendJson(res, 429, { ok: false, error: why });
    return false;
  }
  try {
    const r = await sms.sendVerifyCode(phone, purpose);
    if (!r.ok) {
      smsUnnote(ip, phone);
      console.error(`[sms] 发送失败 phone=${maskPhone(phone)} code=${r.code} ${r.message}`);
      sendJson(res, 502, { ok: false, error: '短信发送失败，请稍后再试，或改用邮箱验证' });
      return false;
    }
  } catch (e) {
    smsUnnote(ip, phone);
    console.error('[sms] 发送异常:', e.message);
    sendJson(res, 502, { ok: false, error: '短信通道暂时不可用，请改用邮箱验证' });
    return false;
  }
  console.log(`[sms] 已发送 phone=${maskPhone(phone)} ip=${ip} purpose=${purpose}`);
  return true;
}

/** 发送成功的统一响应形状（客户端据 channel 决定文案） */
function smsOkBody(phone) {
  return {
    ok: true, channel: 'sms', masked: maskPhone(phone),
    ttl: SMS_CODE_TTL_SEC, resendAfter: Math.floor(SMS_RESEND_MS / 1000),
  };
}

/** POST /send-code {channel:"sms", phone} —— 注册用短信码 */
async function handleSendRegisterSms(res, ip, data) {
  const phone = normPhone(data.phone);
  if (!PHONE_RE.test(phone)) {
    return sendJson(res, 400, { ok: false, error: '手机号格式不对（只支持中国大陆 11 位）' });
  }
  if (!(await smsSendOrFail(res, ip, phone, 'login'))) return;
  return sendJson(res, 200, smsOkBody(phone));
}

/** POST /send-code {channel:"sms", name, purpose:"reset"} —— 重置码只发账号**自己绑定的**号 */
async function handleSendResetSms(res, ip, name) {
  let g;
  try { g = await store.getAccount(uidOf(name)); }
  catch (e) {
    console.error('[reset] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  const phone = (g.ok && g.data) ? normPhone(g.data.phone) : '';
  // 昵称不存在 / 未绑手机号 → 与"已发出"同一形状（masked 为空），不区分这两种情况（防枚举）
  if (!PHONE_RE.test(phone)) {
    console.log(`[reset] sms 无可用手机号（昵称不存在或未绑定） ip=${ip}`);
    return sendJson(res, 200, { ok: true, channel: 'sms', masked: '', ttl: SMS_CODE_TTL_SEC });
  }
  if (!(await smsSendOrFail(res, ip, phone, 'reset'))) return;
  return sendJson(res, 200, smsOkBody(phone));
}

/**
 * 建号（**两条通道共用** —— 保证账号形状不会在两条路上漂移）。
 * `contact` = { email } 或 { phone }，只写**验证过**的那个。
 * `onExists` 用于邮箱通道把码放回去（短信码是一次性的，放不回去，所以传 null）。
 * `onCreated` **只在建号成功**时调（昵称被占不调）—— 裸注册用它记 IP 额度。
 */
async function createAccountCore(res, name, pass, contact, onExists, onCreated) {
  const uid = uidOf(name);
  const salt = crypto.randomBytes(16).toString('hex');
  const acct = {
    v: 1, uid, name, salt, hash: hashPass(pass, salt),
    // 🔴 只绑定**验证过**的联系方式；没走验证的一律空串 ——
    //    否则谁都能填别人的邮箱/手机号，将来做「忘记密码」就会把重置信发到受害者那边。
    email: contact.email || '',
    phone: contact.phone || '',
    created: nowIso(), updated: nowIso(),
    progress: { tier: '', tutorial_done: false, tutorial_hero: '' },
  };
  let r;
  try {
    r = await store.createAccount(uid, acct);
  } catch (e) {
    console.error('[register] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  if (r.exists) {
    if (onExists) onExists();
    return sendJson(res, 409, { ok: false, error: '这个昵称已经有人用了，换一个' });
  }
  if (!r.ok) {
    console.error('[register] 写入失败:', r.error || '');
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  if (onCreated) onCreated();
  console.log(`[register] ok uid=${uid} via=${contact.phone ? 'sms' : 'email'}`);
  return sendJson(res, 201, { ok: true, token: makeToken(uid), account: publicAccount(acct) });
}

/** 注册 · 短信通道（channel="sms"） */
async function handleRegisterBySms(res, name, pass, data) {
  const phone = normPhone(data.phone);
  const code = trim(data.code);
  if (!PHONE_RE.test(phone)) return sendJson(res, 400, { ok: false, error: '请填一个中国大陆手机号' });
  if (!/^\d{6}$/.test(code)) return sendJson(res, 400, { ok: false, error: '请填 6 位数字验证码' });

  // ① 先**探测**昵称（非原子，只为"别白烧一张短信码"；唯一性最终仍由条件写保证）
  try {
    const g = await store.getAccount(uidOf(name));
    if (g.ok) return sendJson(res, 409, { ok: false, error: '这个昵称已经有人用了，换一个' });
  } catch (e) {
    console.error('[register] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  // ② 手机号全站唯一（否则"按手机号找回"会有歧义）
  if (findAccountByPhone(phone)) {
    return sendJson(res, 409, { ok: false, error: '这个手机号已经绑过账号了' });
  }
  // ③ 验码（阿里云侧一次性消费）
  if (!(await smsCheckOrFail(res, phone, code))) return;
  // ④ 建号
  return createAccountCore(res, name, pass, { phone: phone }, null);
}

/**
 * POST /bind-phone（**需登录**）
 *   {action:"send",   phone}        → 给该号发绑定码（模板 100004）
 *   {action:"commit", phone, code}  → 验码并写入当前账号（缺省 action = commit）
 */
async function handleBindPhone(req, res, uid) {
  const ip = clientIp(req);
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  const action = trim(data.action).toLowerCase() || 'commit';
  const phone = normPhone(data.phone);
  if (!PHONE_RE.test(phone)) {
    return sendJson(res, 400, { ok: false, error: '手机号格式不对（只支持中国大陆 11 位）' });
  }
  const owner = findAccountByPhone(phone);
  if (owner && owner.uid !== uid) {
    return sendJson(res, 409, { ok: false, error: '这个手机号已经绑过别的账号了' });
  }
  if (action === 'send') {
    if (!(await smsSendOrFail(res, ip, phone, 'bind'))) return;
    return sendJson(res, 200, smsOkBody(phone));
  }
  if (action !== 'commit') return sendJson(res, 400, { ok: false, error: 'action 只支持 send / commit' });

  const code = trim(data.code);
  if (!/^\d{6}$/.test(code)) return sendJson(res, 400, { ok: false, error: '请填 6 位数字验证码' });
  if (!(await smsCheckOrFail(res, phone, code))) return;

  let g;
  try { g = await store.getAccount(uid); }
  catch (e) {
    console.error('[bind-phone] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  if (!g.ok || !g.data) return sendJson(res, 401, { ok: false, error: '登录已过期，请重新登录' });
  g.data.phone = phone;
  g.data.updated = nowIso();
  try {
    const r = await store.saveAccount(uid, g.data);
    if (!r.ok) {
      console.error('[bind-phone] 写入失败:', r.error || '');
      return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
    }
  } catch (e) {
    console.error('[bind-phone] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  console.log(`[bind-phone] ok uid=${uid} phone=${maskPhone(phone)}`);
  return sendJson(res, 200, { ok: true, account: publicAccount(g.data) });
}

/** 登录：验哈希。失败一律同一句话，不泄漏"昵称是否存在" */
async function handleLogin(req, res) {
  const ip = clientIp(req);
  if (isRateLimited(ip)) return sendJson(res, 429, { ok: false, error: '尝试次数过多，请十分钟后再试' });
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });
  const name = trim(data.name), pass = String(data.pass == null ? '' : data.pass);
  const uid = uidOf(name);
  let g;
  try { g = await store.getAccount(uid); }
  catch (e) {
    console.error('[login] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用，请稍后再试' });
  }
  const fail = () => { noteFail(ip); return sendJson(res, 401, { ok: false, error: '昵称或密码不对' }); };
  if (!g.ok) return fail();
  if (!safeEqHex(hashPass(pass, g.data.salt || ''), String(g.data.hash || ''))) return fail();
  clearFail(ip);
  console.log(`[login] ok uid=${g.data.uid}`);
  return sendJson(res, 200, { ok: true, token: makeToken(g.data.uid), account: publicAccount(g.data) });
}

/** 用 token 换账号 */
async function handleMe(req, res, uid) {
  let g;
  try { g = await store.getAccount(uid); }
  catch (e) {
    console.error('[me] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用' });
  }
  if (!g.ok) return sendJson(res, 404, { ok: false, error: '账号不存在' });
  return sendJson(res, 200, { ok: true, account: publicAccount(g.data) });
}

/** 上传进度：白名单字段，读-改-写（后写赢） */
async function handleProgress(req, res, uid) {
  const { data, bad, tooLarge } = await readBody(req);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体过大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });
  let g;
  try { g = await store.getAccount(uid); }
  catch (e) {
    console.error('[progress] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用' });
  }
  if (!g.ok) return sendJson(res, 404, { ok: false, error: '账号不存在' });

  const acct = g.data;
  const p = acct.progress && typeof acct.progress === 'object' ? acct.progress : {};
  if (data.tier != null) {
    const t = trim(data.tier);
    if (!TIERS.has(t)) return sendJson(res, 400, { ok: false, error: '水平档位取值不合法' });
    p.tier = t;
  }
  if (data.tutorial_done != null) p.tutorial_done = !!data.tutorial_done;
  if (data.tutorial_hero != null) p.tutorial_hero = trim(data.tutorial_hero).slice(0, 32);
  acct.progress = p;
  acct.updated = nowIso();
  try {
    const r = await store.saveAccount(uid, acct);
    if (!r.ok) return sendJson(res, 502, { ok: false, error: '云端暂时不可用' });
  } catch (e) {
    console.error('[progress] 存储异常:', e.message);
    return sendJson(res, 502, { ok: false, error: '云端暂时不可用' });
  }
  return sendJson(res, 200, { ok: true, account: publicAccount(acct) });
}

// ── LLM 统一出口：转发到本机网关（2026-10-04 重构）──────────────────────
//
// 【为什么改成转发】
//   上一版这里自己也持有一份豆包 Key、自己调豆包 —— 结果全项目有**两套 AI 调用、
//   两份 Key**（llm-gateway 一套、这里一套），正是要消除的重复。
//   现在：本服务只当**公网入口 + 转发**，Key 的唯一持有者是 llm-gateway。
//
// 【拓扑】
//   客户端 ──公网 8789/v1/chat──► zhanqi-cloud ──本机回环──► 127.0.0.1:8790
//                                                                   ↓
//                                                          llm-gateway（唯一持 Key）
//   8790 由 iptables 限制为**只允许本机**（llm-gateway-firewall.service），
//   所以公网永远只能从 8789 这一个口进来 —— 少暴露一个面。
//
// 【限流：按用途分开算】
//   · 老师工具（语文/数学资料整理系统）：**每 IP 每天 20 次**（2026-10-04 用户指定）
//   · 战棋战术模型：**不限流**（2026-10-04 用户明确要求，见下）
//   怎么区分：请求体里的 provider 字段（战棋用 "doubao"，工具用 doubao-text/ocr/web）。
//
//   【为什么战棋不限流】一局困难对局就要调 10~30 次，且调用时机由战局推进触发，
//   任何分钟级 / 天级限制都可能**在局中途把玩家打断**（第 15 手突然 429 回退本地 AI，
//   玩家看到的是"AI 变傻了"）。用户明确要求不设限，所以按他说的做：
//   perMin / perDay 都置 0（= 只计数、不拦截），日志里仍能看到用量。
//
//   ⚠️ 代价必须说明白：8789 上的战棋入口因此是一个**不限额的公开模型入口** ——
//   任何人 curl 一下就能用你的豆包额度（既不是 Key 泄露，也拿不到 Key，
//   但你的钱在烧）。这里只保留观测，不做拦截。真要收口，只能让战棋走账号
//   （战棋本来就有账号体系；难点是离线模式也要能用战术模型）。
//
//   ⚠️ 为什么老师工具只能靠限流：它们是**发给老师的单机 exe，没有账号体系**。
//   任何放进客户端的凭据都会被提取出来（和当初把 Key 打进客户端是同一个错），
//   所以身份验证在这类工具上无解 —— 能做的只有把损失上限压住。
//   换 IP 仍可绕过。
const GATEWAY_URL = process.env.LLM_GATEWAY_INTERNAL || 'http://127.0.0.1:8790';

/**
 * 战棋「战术模型」用的 provider 名。
 * ⚠️ 必须与下面 `quotaKindOf()` 里那个字面量保持一致 —— 单独提出来是因为 `/llm/ping`
 *    要按它回答"战术模型就绪没有"；再写一遍字面量迟早会漂移。
 */
const TACTIC_PROVIDER = 'doubao';

/** perMin / perDay 为 0 表示**该项不限流**（仍计数，便于日志观测） */
const QUOTA = {
  tool: { perDay: 20, perMin: 5, label: '今天的 AI 次数用完了（每台电脑每天 20 次），明天再来吧' },
};
const GATEWAY_TIMEOUT_MS = 180000;
const GATEWAY_MAX_BODY = 524288; // 512 KB（OCR 的 base64 图片可能不小）

/** 战棋用 provider="doubao"（Responses 端点）；其余用途名归老师工具 */
function quotaKindOf(provider) {
  return provider === 'doubao' ? 'game' : 'tool';
}

/**
 * 北京时间（UTC+8）的 YYYY-MM-DD。
 * 🔴 别用 `toISOString()` —— 那是 UTC，会让"每天"在北京时间**早上 8 点**重置，
 *    玩家看到的是"莫名其妙又多出来一次"，而不是"过了零点重置"。中国无夏令时，固定 +8h 正确。
 */
const _todayBJ = () => new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);

// ── 战棋「战术模型」每日额度（2026-10-05）──────────────────────────────────
/**
 * 为什么要做：客户端被分享出去之后，**任何人都能无限制地烧豆包额度**。
 * 规则：未登录（本地账户）每台设备每天 3 次；登录后每账号每天 10 次。
 *
 * 🔴 防作弊（用户点名："别让人调系统时间快进一天就多 3 次"）：
 *   · 日期由**服务端**算（`_todayBJ()`）—— 客户端时间**完全不参与** ⇒ 改本机时间无效。
 *   · 身份来源都不可由客户端伪造：
 *       已登录 → token（HMAC 签名，验不过就当未登录）
 *       未登录 → `req.socket.remoteAddress`（真实 TCP 源地址，**不读 X-Forwarded-For**，
 *                且本服务直连公网、前面没有反代）
 *                + 客户端自报的 `device_id`
 *   · device_id 是**可以删掉重生成的**，所以它不是唯一防线 —— IP 池（9 次/天）兜底：
 *     删掉标识只是回到"和同网其他人共用 9 次"，比 3 次多，但**刷不出无限量**。
 *   · 计数**落盘**（llm_quota.json）：否则服务一重启配额就清零，等于白送。
 *
 * ⚠️ 取舍说明：纯设备计数 = 删个文件就重置；纯 IP 计数 = 宿舍里一个人用光全屋没得玩。
 *    取并集（每台设备 3、每 IP 池 9）才是"既不误伤、也刷不动"。
 */
const GAME_QUOTA = {
  guestPerDevice: 3,   // 未登录：每台设备每天
  guestPerIp: 9,       // 未登录：每个 IP 每天（兜底，≈3 台设备）
  memberPerDay: 10,    // 已登录：每账号每天
};
const GUEST_LIMIT_LABEL = '今天免费的 3 次战术模型用完了 —— 登录后每天可以用 10 次';
const MEMBER_LIMIT_LABEL = '今天战术模型的 10 次用完了，明天再来吧';

/** 键：`d:<deviceId>` / `ip:<ip>` / `u:<uid>` → { day, n } */
const _gameQuota = new Map();
const QUOTA_FILE = process.env.QUOTA_FILE || path.join(__dirname, 'llm_quota.json');

/** 启动时载入（**只载今天的** —— 昨天的留着只会让文件无限膨胀） */
function quotaLoad() {
  try {
    const j = JSON.parse(fs.readFileSync(QUOTA_FILE, 'utf8'));
    const day = _todayBJ();
    let kept = 0;
    for (const [k, v] of Object.entries((j && j.entries) || {})) {
      if (v && v.day === day && Number.isFinite(v.n)) { _gameQuota.set(k, { day: v.day, n: v.n }); kept += 1; }
    }
    console.log(`[quota] 载入今日额度记录 ${kept} 条（${day}）`);
  } catch (e) {
    if (e && e.code !== 'ENOENT') console.error('[quota] 读取失败:', (e && e.message) || e);
  }
}

/** 防抖写盘：一局可能连发几个请求，没必要每次请求都落一次盘 */
let _quotaSaveTimer = null;
function quotaSaveSoon() {
  if (_quotaSaveTimer) return;
  _quotaSaveTimer = setTimeout(() => {
    _quotaSaveTimer = null;
    try {
      const entries = {};
      for (const [k, v] of _gameQuota) entries[k] = v;
      fs.writeFileSync(QUOTA_FILE, JSON.stringify({ day: _todayBJ(), entries }), { mode: 0o600 });
    } catch (e) {
      console.error('[quota] 落盘失败:', (e && e.message) || e);
    }
  }, 1500);
  if (_quotaSaveTimer.unref) _quotaSaveTimer.unref();
}

/**
 * 额度豁免（开发/自用）。任一命中即豁免，**只按 IP**：
 *   · 环境变量 `QUOTA_EXEMPT_IPS="1.2.3.4,5.6.7.8"`
 *   · 文件 `<服务目录>/quota_exempt.json` → `{ "ips": ["1.2.3.4"], "note": "..." }`（按 mtime 热加载）
 * ⚠️ 不做 token 豁免 —— 那等于"登录即无限"，是另一回事。
 */
const EXEMPT_FILE = process.env.QUOTA_EXEMPT_FILE || path.join(__dirname, 'quota_exempt.json');
let _exempt = { ips: new Set(), mtime: -1 };
function exemptReload() {
  let mtime = 0;
  let fromFile = [];
  try {
    mtime = fs.statSync(EXEMPT_FILE).mtimeMs;
    if (mtime === _exempt.mtime) return;
    fromFile = (JSON.parse(fs.readFileSync(EXEMPT_FILE, 'utf8')).ips) || [];
  } catch (e) {
    if (e && e.code !== 'ENOENT') { console.error('[quota] 豁免文件读取失败:', (e && e.message) || e); return; }
  }
  const ips = new Set(String(process.env.QUOTA_EXEMPT_IPS || '').split(',').map((s) => s.trim()).filter(Boolean));
  for (const ip of fromFile) if (ip) ips.add(String(ip).trim());
  _exempt = { ips, mtime };
  if (ips.size) console.log(`[quota] 豁免 IP ${ips.size} 个: ${[...ips].join(', ')}`);
}
const isExempt = (ip) => { exemptReload(); return _exempt.ips.has(ip); };

/** 取今天的计数（不改） */
function quotaPeek(key) {
  const rec = _gameQuota.get(key);
  return (rec && rec.day === _todayBJ()) ? rec.n : 0;
}
function quotaBump(key) {
  const day = _todayBJ();
  const rec = _gameQuota.get(key);
  if (!rec || rec.day !== day) _gameQuota.set(key, { day, n: 1 });
  else rec.n += 1;
  quotaSaveSoon();
  // 跨日残留清理（只在 Map 变大时才扫，摊薄到可忽略）
  if (_gameQuota.size > 2048) {
    for (const [k, v] of _gameQuota) if (v.day !== day) _gameQuota.delete(k);
  }
}

/**
 * **检查 + 计数一步到位**：调用一次 ≈ 消耗一次（被拒时不计数）。
 * @param uid 已登录用户 uid（verifyToken 通过才有；空 = 未登录）
 * @returns {{allowed:boolean, why:string, needLogin:boolean, quota:object}}
 */
function gameQuotaCheck(ip, deviceId, uid) {
  const dev = String(deviceId || '').trim().slice(0, 64);
  const day = _todayBJ();

  // ① 已登录：按账号 10 次/天（换 IP 也刷不动）
  if (uid) {
    const limit = GAME_QUOTA.memberPerDay;
    const used = quotaPeek(`u:${uid}`);
    if (used >= limit) {
      return { allowed: false, why: MEMBER_LIMIT_LABEL, needLogin: false,
               quota: { tier: 'member', used, limit, left: 0 } };
    }
    quotaBump(`u:${uid}`);
    return { allowed: true, why: '', needLogin: false,
             quota: { tier: 'member', used: used + 1, limit, left: Math.max(0, limit - used - 1) } };
  }

  // ② 豁免（只对未登录有意义 —— 登录本来就有 10 次）
  if (isExempt(ip)) {
    return { allowed: true, why: '', needLogin: false,
             quota: { tier: 'exempt', used: 0, limit: null, left: null } };
  }

  // ③ 未登录：设备池与 IP 池**两道都要过**
  const devKey = dev ? `d:${dev}` : '';
  const ipKey = `ip:${ip}`;
  const devUsed = devKey ? quotaPeek(devKey) : 0;
  const ipUsed = quotaPeek(ipKey);

  if (devKey && devUsed >= GAME_QUOTA.guestPerDevice) {
    return { allowed: false, why: GUEST_LIMIT_LABEL, needLogin: true,
             quota: { tier: 'guest', used: devUsed, limit: GAME_QUOTA.guestPerDevice, left: 0 } };
  }
  if (ipUsed >= GAME_QUOTA.guestPerIp) {
    return { allowed: false, why: GUEST_LIMIT_LABEL, needLogin: true,
             quota: { tier: 'guest', used: ipUsed, limit: GAME_QUOTA.guestPerIp, left: 0 } };
  }

  quotaBump(ipKey);
  if (devKey) quotaBump(devKey);
  let left = GAME_QUOTA.guestPerIp - ipUsed - 1;
  if (devKey) left = Math.min(left, GAME_QUOTA.guestPerDevice - devUsed - 1);
  return { allowed: true, why: '', needLogin: false,
           quota: { tier: 'guest', used: devKey ? devUsed + 1 : ipUsed + 1,
                    limit: devKey ? GAME_QUOTA.guestPerDevice : GAME_QUOTA.guestPerIp,
                    left: Math.max(0, left) } };
}

/** 只读版：告诉客户端"今天还剩几次"（探针用，**不消耗额度**） */
function gameQuotaPeek(ip, deviceId, uid) {
  const dev = String(deviceId || '').trim().slice(0, 64);
  if (uid) {
    const limit = GAME_QUOTA.memberPerDay;
    const used = quotaPeek(`u:${uid}`);
    return { tier: 'member', used, limit, left: Math.max(0, limit - used) };
  }
  if (isExempt(ip)) return { tier: 'exempt', used: 0, limit: null, left: null };
  const devUsed = dev ? quotaPeek(`d:${dev}`) : 0;
  const ipUsed = quotaPeek(`ip:${ip}`);
  let left = GAME_QUOTA.guestPerIp - ipUsed;
  if (dev) left = Math.min(left, GAME_QUOTA.guestPerDevice - devUsed);
  return {
    tier: 'guest',
    used: dev ? devUsed : ipUsed,
    limit: dev ? GAME_QUOTA.guestPerDevice : GAME_QUOTA.guestPerIp,
    left: Math.max(0, left),
  };
}

/**
 * 限流总入口：战棋（provider=doubao）走上面的每日额度，其余用途走老的每分钟+每天。
 * 返回 `allowed:true` 时**额度已经扣掉了**。
 */
function llmGate(req, data) {
  const ip = clientIp(req);
  const provider = String((data && data.provider) || '');
  if (quotaKindOf(provider) === 'game') {
    return gameQuotaCheck(ip, (data && data.device_id) || '', verifyToken(bearer(req)));
  }
  const why = toolRateCheck(ip, provider);
  return { allowed: !!(!why), why, needLogin: false, quota: toolQuota(ip, provider) };
}

/** 老的"按用途 + 按分钟"限流桶（老师工具在用；战棋已改走上面的每日额度） */
const _gwIp = new Map();         // "ip|kind" -> {minAt, minN, day, dayN}

quotaLoad();

/**
 * 返回 "" 表示放行，否则返回给用户看的中文原因。
 * perMin / perDay 为 0 → 该项不限流（**仍然计数**，只是不拦截）。
 */
function toolRateCheck(ip, provider) {
  const kind = quotaKindOf(provider);
  const q = QUOTA[kind];
  if (!q) return '';   // 该用途没有配额定义（战棋已改走 gameQuotaCheck）→ 放行
  const key = `${ip}|${kind}`;
  const now = Date.now();
  const day = _todayBJ();

  let rec = _gwIp.get(key);
  if (!rec) { rec = { minAt: now, minN: 0, day, dayN: 0 }; _gwIp.set(key, rec); }
  if (now - rec.minAt > 60000) { rec.minAt = now; rec.minN = 0; }
  if (rec.day !== day) { rec.day = day; rec.dayN = 0; }

  if (q.perMin > 0 && rec.minN >= q.perMin) return '点得太快了，歇一分钟再试';
  if (q.perDay > 0 && rec.dayN >= q.perDay) return q.label;

  rec.minN += 1; rec.dayN += 1;
  return '';
}

/** 给客户端看"今天还能用几次"；不限流的用途返回 limit=null / left=null */
function toolQuota(ip, provider) {
  const kind = quotaKindOf(provider);
  const q = QUOTA[kind];
  if (!q) return { kind, used: 0, limit: null, left: null };
  const rec = _gwIp.get(`${ip}|${kind}`);
  const day = _todayBJ();
  const used = (rec && rec.day === day) ? rec.dayN : 0;
  if (q.perDay === 0) return { kind, used, limit: null, left: null };
  return { kind, used, limit: q.perDay, left: Math.max(0, q.perDay - used) };
}

/** 一行日志用的用量描述（不限流时只报已用次数） */
function quotaLog(ip, provider) {
  const q = toolQuota(ip, provider);
  return q.limit == null ? `已用${q.used}次(不限流)` : `余${q.left}次`;
}

/**
 * 把客户端的 LLM 请求转发给**本机网关**（127.0.0.1:8790）。
 * 本服务**不再持有任何模型 Key** —— Key 的唯一持有者是 llm-gateway。
 *
 * @param gpath      网关上的路径，如 '/v1/chat'
 * @param rateLimit  是否按用途限流（老师工具 20/天，战棋 400/天）
 */
async function handleGatewayProxy(req, res, gpath, { rateLimit = true } = {}) {
  const ip = clientIp(req);

  const { data, bad, tooLarge } = await readBody(req, GATEWAY_MAX_BODY);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '请求体太大' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  const provider = req.method === 'POST' ? String(data.provider || '') : '';
  let gate = null;                 // 记下来给成功日志用（战棋与老师工具的"余量"描述不一样）
  if (rateLimit && req.method === 'POST') {
    gate = llmGate(req, data);
    if (!gate.allowed) {
      console.log(`[gw] 限流 ip=${ip} provider=${provider || '(默认)'} tier=${gate.quota.tier} used=${gate.quota.used} :: ${gate.why}`);
      return sendJson(res, 429, { ok: false, error: gate.why, quota: gate.quota, need_login: !!gate.needLogin });
    }
  }

  const t0 = Date.now();
  try {
    const r = await fetch(GATEWAY_URL + gpath, {
      method: req.method === 'GET' ? 'GET' : 'POST',
      // 🔴 必须带真实客户端 IP：网关按 X-Forwarded-For 分桶。不传的话所有转发请求
      //    都会被算成 127.0.0.1，**一个人刷满就把所有人（含战棋）卡住**（2026-10-04 实测发现）。
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
      body: req.method === 'GET' ? undefined : JSON.stringify(data),
      signal: AbortSignal.timeout(GATEWAY_TIMEOUT_MS),
    });
    const text = await r.text();
    const ms = Date.now() - t0;
    if (gate) {
      console.log(`[gw] ${r.status} ${ms}ms ip=${ip} provider=${provider || '(默认)'} tier=${gate.quota.tier} 余${gate.quota.left == null ? '不限' : gate.quota.left}`);
    }
    res.writeHead(r.status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(text),
      'Cache-Control': 'no-store',
    });
    return res.end(text);
  } catch (e) {
    const why = e && e.name === 'TimeoutError' ? '超时' : (e && e.message) || '未知';
    console.error('[gw] 转发失败:', why);
    return sendJson(res, 502, { ok: false, error: 'AI 服务暂时联系不上' });
  }
}

/**
 * GET /llm/ping · /v1/ping —— 客户端"云端战术模型就绪没有"的探针（**不调模型、不烧额度**）。
 *
 * 🔴 2026-10-05 修（用户实报「界面显示云端模型没有正常连接，无法使用豆包」）：
 *    原先这里只把网关的 `/health` **原样转发**，而客户端判的是**顶层 `ready`**；
 *    网关 `/health` 里 `ready` 只存在于 `providers[].ready` ⇒ 顶层永远没有 `ready`
 *    ⇒ 客户端 `get("ready", false)` **恒为 false** ⇒ 界面永远显示
 *    「云端不可用（云端还没配好战术模型）」，把本来好好的战术模型误判成连不上。
 *    实测证据（同一分钟内）：`/llm/ping` 里 `doubao.ready === true`，同时 `POST /llm`
 *    真调返回 **200 + 模型正常作答**（517ms / 141 tokens）⇒ 是**判据形状对不上**，
 *    不是模型不通。
 *
 * ⇒ 由**本服务**（客户端契约的对面）负责翻译成客户端要的形状，而不是把网关的内部诊断
 *   格式直接泄漏给客户端。修这一处即可：**不用改客户端、不用重发版**，已发布的版本直接受益。
 */
async function handlePing(req, res) {
  const t0 = Date.now();
  // 探测**不消耗额度**，只回报"今天还剩几次"：客户端带 ?device_id= 查设备、
  // 带 Authorization 则按账号查（两者都没有就按 IP 池算 —— 老客户端走这条）。
  const quota = gameQuotaPeek(
    clientIp(req),
    new URL(req.url, 'http://x').searchParams.get('device_id') || '',
    verifyToken(bearer(req)),
  );
  let j = null, why = '';
  try {
    const r = await fetch(GATEWAY_URL + '/health', {
      method: 'GET',
      headers: { 'X-Forwarded-For': clientIp(req) },
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) why = `网关 HTTP ${r.status}`;
    else j = await r.json().catch(() => null);
  } catch (e) {
    why = (e && e.name === 'TimeoutError') ? '网关超时' : ((e && e.message) || '网关不可达');
  }

  if (!j || typeof j !== 'object') {
    console.error('[ping] 战术模型网关不可用:', why);
    return sendJson(res, 200, { ok: true, ready: false, gatewayOk: false, error: why || '网关返回异常', ms: Date.now() - t0, quota });
  }

  const list = Array.isArray(j.providers) ? j.providers : [];
  const pick = list.find((p) => p && p.name === TACTIC_PROVIDER) || null;
  const ready = !!(pick && pick.ready);
  if (!ready) console.warn(`[ping] 战术模型未就绪 provider=${TACTIC_PROVIDER}`);
  return sendJson(res, 200, {
    ok: true,                                   // 探测通道本身是通的（与"模型就绪"分开看 ready）
    ready,                                      // ★ 客户端唯一判据
    provider: TACTIC_PROVIDER,
    model: pick ? String(pick.model || '') : '',
    // 网关的诊断信息按**明确的形状**带上（不做整包 ...spread，免得将来网关加字段就悄悄改变对外契约）
    gateway: { ok: j.ok !== false, service: j.service || '', default: j.default || '', ts: j.ts || '' },
    providers: list.map((p) => ({
      name: (p && p.name) || '', kind: (p && p.kind) || '',
      model: (p && p.model) || '', ready: !!(p && p.ready),
    })),
    readyCount: `${list.filter((p) => p && p.ready).length}/${list.length}`,
    ms: Date.now() - t0,
    quota,                                      // ★ 今日剩余额度（客户端用来显示"还剩 N 次"）
  });
}

/**
 * 旧接口 `/llm`（战棋已发布的客户端在用）—— 语义等价于网关的 `/v1/chat`。
 * 保留是为了**不用重发战棋安装包**；走战棋每日额度（未登录 3 次/设备、登录后 10 次/账号）。
 *
 * ⚠️ 老客户端（≤10.5.1）**不带 token、也不带 device_id** ⇒ 只剩 IP 池（9 次/天）兜底，
 *    照样限得住；只是它读不到 429 的 body，会**静默回退本地 AI**，看不到"登录可解锁"那句提示。
 *    新客户端（10.5.2 起）两样都带，且会把提示显示出来。
 */
async function handleLegacyLlm(req, res) {
  const ip = clientIp(req);
  const { data, bad, tooLarge } = await readBody(req, GATEWAY_MAX_BODY);
  if (tooLarge) return sendJson(res, 413, { ok: false, error: '卷子太大了' });
  if (bad) return sendJson(res, 400, { ok: false, error: '请求格式不对' });

  // 这个接口的语义就是战棋 → 强制 provider=doubao，走战棋每日额度
  const gate = llmGate(req, Object.assign({}, data, { provider: 'doubao' }));
  if (!gate.allowed) {
    console.log(`[llm-legacy] 限流 ip=${ip} tier=${gate.quota.tier} used=${gate.quota.used} :: ${gate.why}`);
    return sendJson(res, 429, { ok: false, error: gate.why, quota: gate.quota, need_login: !!gate.needLogin });
  }

  // device_id 是本服务自己用来认额的，**不要透传给网关**（它不认识这个字段）
  const upstream = Object.assign({}, data);
  delete upstream.device_id;

  const t0 = Date.now();
  try {
    const r = await fetch(GATEWAY_URL + '/v1/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
      body: JSON.stringify({ provider: 'doubao', ...upstream }),
      signal: AbortSignal.timeout(GATEWAY_TIMEOUT_MS),
    });
    const text = await r.text();
    console.log(`[llm-legacy] ${r.status} ${Date.now() - t0}ms ip=${ip} tier=${gate.quota.tier} 余${gate.quota.left == null ? '不限' : gate.quota.left}`);
    res.writeHead(r.status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(text),
      'Cache-Control': 'no-store',
    });
    return res.end(text);
  } catch (e) {
    console.error('[llm-legacy] 失败:', (e && e.message) || e);
    return sendJson(res, 502, { ok: false, error: '战术模型暂时联系不上' });
  }
}

// ── 路由 ──────────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname.replace(/\/+$/, '') || '/';

  // 预检：**不再回任何 CORS 头**。缺了 `Access-Control-Allow-Origin`，浏览器会把后续真实
  // 请求直接拦下 —— 这正是想要的：本服务不给网页用。原生客户端不发预检，不受影响。
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  if (p === '/health') {
    // 公网只给"活着"这一条：详情（存储 / 备份 / 邮件 / OSS / 网关）合起来等于一份
    // **资产与依赖清单**（含投递邮箱、对象存储桶名与接入点、供应商模型名），不该给陌生人看。
    // 本机调用（探针 / systemd / 运维 ssh）行为完全不变（2026-10-05 收紧）。
    const base = { ok: true, service: 'zhanqi-cloud', ts: nowIso() };
    if (!isLoopback(req)) return sendJson(res, 200, base);

    const info = oss.bucketInfo();
    const st = store.stats();
    return sendJson(res, 200, Object.assign(base, {
      store: {
        mode: st.mode, accounts: st.accounts, dataBytes: st.bytes,
        // 磁盘实占按 4 KB 块估（小文件会放大，见 store.js 头注释）
        diskBytesEst: st.accounts * 4096,
      },
      backup: backupState(),
      // LLM 出口：本服务只转发，Key 在网关那一侧（不在这里，也不在客户端）
      gateway: { url: GATEWAY_URL },
      // 邮件出口：同样只转发，授权码在 mail-gateway（8791）那一侧
      mail: {
        gateway: MAIL_GATEWAY,
        agentMail: AGENT_MAIL,            // Bug 上报唯一收件人（AI 侧）
        cc: REPORT_CC.length ? REPORT_CC : null,
        requireEmailCode: REQUIRE_EMAIL_CODE,
      },
      // 短信出口：凭证在本机 .aliyun-sms.json；这里只回"就绪没有"，不回任何凭证内容
      sms: {
        product: 'aliyun-dypns(短信认证)',
        on: SMS_ON,
        ready: sms.available(),
        detail: SMS_ON ? (sms.available() ? 'ok' : sms.configError()) : 'SMS_DISABLED=1',
      },
      oss: { bucket: info.bucket, endpoint: info.endpoint },
    }));
  }

  if (p === '/llm/ping' || p === '/v1/ping') {
    // 轻量探测：问"战术模型就绪没有"（**不调模型、不计限流**，零成本）。
    // 客户端那个"检测云端"按钮点一次就跑这里 —— 让用户每点一次都烧一次额度是荒唐的。
    // ⚠️ 别再改回 handleGatewayProxy('/health')：那会把网关的形状直接透给客户端，
    //    而客户端判的是顶层 `ready`，见 handlePing 的注释（2026-10-05 修过一次）。
    return handlePing(req, res);
  }

  if (p === '/version.json') {
    let text = null;
    try { text = await versionJson(); }
    catch (e) { console.error('[version] OSS 异常:', e.message); }
    if (text == null) return sendJson(res, 404, { ok: false, error: '版本清单还没发布' });
    const body = Buffer.from(text, 'utf8');
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': body.length,
      'Cache-Control': 'public, max-age=60',
    });
    return res.end(body);
  }

  if (p === '/register' && req.method === 'POST') return handleRegister(req, res);
  if (p === '/login' && req.method === 'POST') return handleLogin(req, res);

  // ── 邮件相关（2026-10-04）───────────────────────────────────────────
  // 验证码：注册前先拿码（/send-code），注册时带上 {email, code}
  if ((p === '/send-code' || p === '/register/code') && req.method === 'POST') return handleSendCode(req, res);
  // 忘记密码 · 第②步：用重置码换新密码（第①步走上面 /send-code + purpose:"reset"）
  if (p === '/reset-password' && req.method === 'POST') return handleResetPassword(req, res);
  // 绑定手机号（**需登录**）：action="send" 发码 / 缺省 "commit" 提交
  if (p === '/bind-phone' && req.method === 'POST') {
    const uidB = verifyToken(bearer(req));
    if (!uidB) return sendJson(res, 401, { ok: false, error: '登录已过期，请重新登录' });
    return handleBindPhone(req, res, uidB);
  }
  // Bug 上报：服务端直投 AgentMail（**不抄送本人邮箱**）
  if ((p === '/bug-report' || p === '/report') && req.method === 'POST') return handleBugReport(req, res);

  // ── LLM 出口（全部转发给本机 llm-gateway）─────────────────────────────
  // 新客户端用 /v1/chat；老战棋客户端用 /llm（语义相同，保留以省一次重发包）。
  // 🔴 拒绝"来自浏览器"的调用：浏览器**一定**带 Origin，原生客户端（Godot / 桌面 exe）不带。
  //    光去掉 CORS 头还不够 —— 用 text/plain 发的"简单请求"不触发预检，副作用（真的调模型、
  //    真的扣额度）照样会发生。所以这里显式拦掉带 Origin 的调用（2026-10-05）。
  const fromBrowser = !!req.headers.origin;
  if (p === '/v1/chat' && req.method === 'POST') {
    if (fromBrowser) return sendJson(res, 403, { ok: false, error: '本接口仅供客户端调用' });
    return handleGatewayProxy(req, res, '/v1/chat');
  }
  if (p === '/v1/providers') {
    if (fromBrowser) return sendJson(res, 403, { ok: false, error: '本接口仅供客户端调用' });
    return handleGatewayProxy(req, res, '/v1/providers', { rateLimit: false });
  }
  if (p === '/llm' && req.method === 'POST') {
    if (fromBrowser) return sendJson(res, 403, { ok: false, error: '本接口仅供客户端调用' });
    return handleLegacyLlm(req, res);
  }

  if (p === '/me' || p === '/progress') {
    const uid = verifyToken(bearer(req));
    if (!uid) return sendJson(res, 401, { ok: false, error: '登录已过期，请重新登录' });
    if (p === '/me') return handleMe(req, res, uid);
    if (req.method === 'POST') return handleProgress(req, res, uid);
    return sendJson(res, 405, { ok: false, error: '方法不对' });
  }

  return sendJson(res, 404, { ok: false, error: '没有这个接口' });
});

server.listen(PORT, BIND_HOST, () => {
  const info = oss.bucketInfo();
  const st = store.stats();
  console.log(`[zhanqi-cloud] 监听 0.0.0.0:${PORT}`);
  // 2026-10-05：把"邮箱验证码是否强制"打到启动日志 —— 这个开关一旦置 0，
  //   注册就等于**完全不做邮箱校验**，属于必须一眼可见的状态。
  console.log(`[zhanqi-cloud] 注册邮箱验证码：${REQUIRE_EMAIL_CODE ? '强制' : '🔴 已关闭（REQUIRE_EMAIL_CODE=0）—— 任何人都能不带邮箱注册'}`);
  console.log(`[zhanqi-cloud] 账号存储 mode=${st.mode} dir=${st.dir}（现有 ${st.accounts} 个）`);
  console.log(`[zhanqi-cloud] OSS bucket=${info.bucket}（版本清单 + 账号冷备）`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => { console.log(`[zhanqi-cloud] 收到 ${sig}，退出`); server.close(() => process.exit(0)); });
}

module.exports = { uidOf, makeToken, verifyToken };
