#!/usr/bin/env node
/**
 * zhanqi-cloud 自检（本地起实例跑，不碰线上、不碰生产账号库）
 *   node selftest.js
 *
 * 存储用临时目录（STORE_DIR），跑完删掉。
 * 覆盖：健康检查 / 注册 / **重名原子性（含真并发）** / 登录 / 错密码 / token 验签 /
 *       篡改 token / 进度上传读回 / 版本清单 / 参数校验 / 限流。
 */
'use strict';
const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 18789;
const BASE = `http://127.0.0.1:${PORT}`;
const stats = { pass: 0, fail: 0 };
function ck(cond, name, extra) {
  if (cond) { stats.pass++; console.log(`  ✓ ${name}`); }
  else { stats.fail++; console.log(`  ✗ FAIL: ${name}${extra ? '  → ' + extra : ''}`); }
}
async function jpost(p, body, token) {
  const r = await fetch(BASE + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: JSON.stringify(body),
  });
  let j = null;
  try { j = await r.json(); } catch { /* 空 */ }
  return { code: r.status, j };
}
async function jget(p, token) {
  const r = await fetch(BASE + p, { headers: token ? { Authorization: 'Bearer ' + token } : {} });
  let j = null;
  try { j = await r.json(); } catch { /* 空 */ }
  return { code: r.status, j };
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

/** 带自定义请求头的 POST（用来伪造 X-Forwarded-For，验证边缘不信任它） */
async function postRaw(p, body, headers) {
  const r = await fetch(BASE + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' }, headers || {}),
    body: JSON.stringify(body),
  });
  let j = null;
  try { j = await r.json(); } catch { /* 空 */ }
  return { code: r.status, j };
}
const uidOf = (n) => crypto.createHash('sha256').update(n.trim().toLowerCase()).digest('hex').slice(0, 16);

(async () => {
  const suffix = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const name = '自检_' + suffix;
  const pass = 'pw_' + suffix;
  const storeDir = path.join(os.tmpdir(), 'zhanqi-selftest-' + suffix);

  console.log('▶ 启动本地实例（存储隔离到临时目录）…');
  const srv = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: Object.assign({}, process.env, {
      PORT: String(PORT),
      ZHANQI_TOKEN_SECRET: 'selftest-secret-' + suffix,
      STORE_MODE: 'local',
      STORE_DIR: storeDir,
      // 🔴 把网关转发目标指到一个**必然没人监听**的端口：这样 /v1/chat、/llm 的
      //    配额判定照样跑（配额在转发之前），但**永远不会真的调模型**。
      //    否则在服务器上跑自检时，会真打网关、烧豆包额度（2026-10-04 起固定成这样）。
      LLM_GATEWAY_INTERNAL: 'http://127.0.0.1:19999',
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const srvLog = [];
  srv.stdout.on('data', d => srvLog.push(String(d)));
  srv.stderr.on('data', d => srvLog.push(String(d)));

  let up = false;
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(BASE + '/health'); if (r.ok) { up = true; break; } } catch { /* 还没起 */ }
    await sleep(250);
  }
  if (!up) {
    console.log('✗ 服务起不来，日志：\n' + srvLog.join(''));
    srv.kill(); process.exit(1);
  }
  console.log(`✓ 服务已就绪（${BASE}）\n`);

  try {
    // ① 健康检查 + 存储后端
    const h = await jget('/health');
    ck(h.code === 200 && h.j && h.j.ok === true, '健康检查 /health');
    ck(h.j && h.j.store && h.j.store.mode === 'local', `health 报告存储后端 mode=${h.j && h.j.store && h.j.store.mode}`);
    ck(h.j && h.j.store && h.j.store.accounts === 0, 'health 初始账号数为 0');

    // ② 版本清单（没发布时应 404 而不是 500）
    const v = await jget('/version.json');
    ck(v.code === 200 || v.code === 404, `版本清单 /version.json（HTTP ${v.code}）`);

    // ③ 注册
    const reg = await jpost('/register', { name, pass });
    ck(reg.code === 201 && reg.j && reg.j.ok === true, '注册成功返回 201');
    ck(!!(reg.j && reg.j.token), '注册返回 token');
    ck(!(reg.j && reg.j.account && (reg.j.account.hash || reg.j.account.salt)), '响应不含 hash/salt');
    const token = reg.j && reg.j.token;

    // ④ 账号确实落到分片目录里（uid 前 2 位）
    const uid = uidOf(name);
    const shard = uid.slice(0, 2);
    const acctFile = path.join(storeDir, shard, uid + '.json');
    ck(fs.existsSync(acctFile), `账号落盘到分片目录 ${shard}/${uid}.json`);
    ck(fs.existsSync(acctFile) && Buffer.byteLength(fs.readFileSync(acctFile)) < 1024, '落盘文件 < 1 KB（体积预期）');

    // ⑤ ★ 重名 —— 原子拒绝
    const dup = await jpost('/register', { name, pass });
    ck(dup.code === 409, '重名注册被拒（409，原子创建）', `实际 ${dup.code}`);

    // ⑥ 大小写不同也算重名（归一化生效）
    const dup2 = await jpost('/register', { name: name.toUpperCase(), pass });
    ck(dup2.code === 409, '大小写不同的同名也算重名');

    // ⑦ ★★ 真并发同名注册：两个请求同时打，只能有一个成功
    const cname = '并发_' + suffix;
    const [c1, c2] = await Promise.all([
      jpost('/register', { name: cname, pass }),
      jpost('/register', { name: cname, pass }),
    ]);
    const codes = [c1.code, c2.code].sort();
    ck(codes[0] === 201 && codes[1] === 409, `并发同名注册：恰好一个成功（实际 ${codes.join('/')}）`);

    // ⑧ 登录
    const login = await jpost('/login', { name, pass });
    ck(login.code === 200 && login.j && login.j.ok === true, '登录成功');
    const tk = login.j && login.j.token;

    // ⑨ 错密码
    ck((await jpost('/login', { name, pass: 'wrong-password-xyz' })).code === 401, '错密码返回 401');

    // ⑩ 不存在的账号 —— 与错密码同样 401（不泄漏昵称是否存在）
    ck((await jpost('/login', { name: '不存在的人_' + suffix, pass: 'whatever123' })).code === 401,
      '不存在的账号同样 401（不泄漏存在性）');

    // ⑪ /me
    const me = await jget('/me', tk);
    ck(me.code === 200 && me.j && me.j.account && me.j.account.name === name, '/me 用 token 换到账号');

    // ⑫ 篡改 token
    ck((await jget('/me', (tk || '').slice(0, -2) + 'zz')).code === 401, '篡改 token 被拒（HMAC 验签生效）');

    // ⑬ 无 token
    ck((await jget('/me')).code === 401, '无 token 被拒');

    // ⑭ 进度上传 + 读回
    const pr = await jpost('/progress', { tier: 'veteran', tutorial_done: true, tutorial_hero: 'jianwu' }, tk);
    ck(pr.code === 200 && pr.j && pr.j.account.progress.tier === 'veteran', '进度上传成功');
    const me2 = await jget('/me', tk);
    ck(me2.j && me2.j.account.progress.tutorial_done === true && me2.j.account.progress.tutorial_hero === 'jianwu',
      '进度读回一致', JSON.stringify(me2.j && me2.j.account.progress));

    // ⑮ 非法档位
    ck((await jpost('/progress', { tier: 'god' }, tk)).code === 400, '非法水平档位被拒（白名单）');

    // ⑯ 进度上传不影响密码（读-改-写有没有把 salt/hash 弄丢）
    ck((await jpost('/login', { name, pass })).code === 200, '上传进度后仍能用原密码登录（salt/hash 未被破坏）');

    // ⑰ 参数校验
    ck((await jpost('/register', { name: 'x' + suffix, pass: '123' })).code === 400, '密码过短被拒');
    ck((await jpost('/register', { name: '  ', pass: 'longenough123' })).code === 400, '空昵称被拒');

    // ⑱ 限流
    let got429 = false;
    for (let i = 0; i < 12; i++) {
      if ((await jpost('/login', { name, pass: 'wrong-' + i })).code === 429) { got429 = true; break; }
    }
    ck(got429, '连续错密码触发限流（429）');

    // ⑲ 未知接口
    ck((await jget('/nope')).code === 404, '未知接口返回 404');

    // ⑳ 磁盘上恰好只有自检造的 2 个账号文件
    const files = [];
    for (const s of fs.readdirSync(storeDir)) {
      for (const f of fs.readdirSync(path.join(storeDir, s))) if (f.endsWith('.json')) files.push(f);
    }
    ck(files.length === 2, `磁盘上恰好 2 个账号文件，实际 ${files.length}`);

    // ── LLM 转发入口的配额（2026-10-04 加）────────────────────────────────
    // 🔴 转发目标被强制指向一个**必然连不上**的端口（见上面 spawn 的 env），
    //    所以这里只验证"配额判定"，**不会真的调模型** —— 在任何机器上跑都不烧额度，
    //    即使是在服务器上跑（那里 8790 真的活着）也一样安全。
    //    配额检查发生在"转发之前"，所以连不上网关不影响判定结果：
    //      过了配额 → 卡在转发 → 502；没过配额 → 429。
    const toolCodes = [];
    for (let i = 0; i < 6; i++) {
      toolCodes.push((await jpost('/v1/chat', { provider: 'doubao-text', prompt: 'x' })).code);
    }
    ck(toolCodes.slice(0, 5).every(c => c === 502),
      '老师工具前 5 次过了配额（502 = 卡在转发层，非被拦）', toolCodes.join(','));
    ck(toolCodes[5] === 429,
      '老师工具第 6 次被配额拦（每分钟 5 次）', toolCodes.join(','));

    // ㉑ 战棋用途**不受限**：连打 40 次，一次都不该 429（只计数、不拦截）
    let zq429 = 0;
    for (let i = 0; i < 40; i++) {
      if ((await jpost('/llm', { prompt: 'x' })).code === 429) zq429++;
    }
    ck(zq429 === 0, '战棋入口连打 40 次不被限流（只计数）', `429 出现 ${zq429} 次`);

    // ㉒ 伪造 X-Forwarded-For **不能**扩充配额
    //     边缘服务若信任该头，每个假 IP 都会是一个新桶 → 8 次全放行；
    //     现在按真实 TCP 对端计数 → 一分钟内**放行数必然 ≤ 5**。
    let spoofPass = 0;
    for (let i = 0; i < 8; i++) {
      const r = await postRaw('/v1/chat', { provider: 'doubao-text', prompt: 'x' },
        { 'X-Forwarded-For': `10.9.9.${i}` });
      if (r.code === 502) spoofPass++;
    }
    ck(spoofPass <= 5,
      '伪造 X-Forwarded-For 无法绕过按 IP 配额（放行数 ≤ 5/分）', `放行 ${spoofPass} 次`);

  } catch (e) {
    stats.fail++;
    console.log('  ✗ FAIL: 自检抛异常 → ' + e.message);
  } finally {
    console.log('\n▶ 清理临时存储…');
    try { fs.rmSync(storeDir, { recursive: true, force: true }); console.log(`  ✓ 已删 ${storeDir}`); }
    catch (e) { console.log(`  ⚠ 清理失败（不影响结论）：${e.message}`); }
    srv.kill();
  }

  console.log(`\n=== zhanqi-cloud 自检：PASS ${stats.pass} / FAIL ${stats.fail} ===`);
  process.exit(stats.fail > 0 ? 1 : 0);
})();
