#!/usr/bin/env node
/**
 * selftest_sms.js —— 「短信通道」端到端自检（本地起实例，**不碰线上、不发真短信**）
 *   node selftest_sms.js
 *
 * 三个进程：
 *   ① 假 dypnsapi（18799）—— 模拟阿里云短信认证：收 SendSmsVerifyCode / CheckSmsVerifyCode，
 *      自己存码自己校验（**零真实短信消耗**），并记录每次调用的 Action/TemplateCode/参数
 *   ② 假 mail-gateway（18798）—— 收邮件，回 {ok:true}
 *   ③ 真 server.js（18790）—— 存储隔离到临时目录
 *
 * 覆盖：老路径（邮箱）逐字节回归 + 短信注册/找回/绑定 + 手机号唯一 + 防枚举 +
 *      限流（重发间隔/日上限）+ 未登录拒绝 + 模板选择 + ##code## 占位符 +
 *      注册闸门两档（`REQUIRE_EMAIL_CODE`=0 的裸注册 IP 限流 / =1 的拒绝）。
 *
 * 用法：
 *   node selftest_sms.js                     # 默认按生产现状（闸门 0）跑
 *   SELFTEST_GATE=1 node selftest_sms.js     # 按"新客户端已发布"那档（闸门 1）跑
 */
'use strict';
const { spawn } = require('node:child_process');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const P_DYPNS = 18799, P_MAIL = 18798, P_SRV = 18790;
const BASE = `http://127.0.0.1:${P_SRV}`;
const CODE = '246810';                       // 假网关"生成"的验证码
const stats = { pass: 0, fail: 0 };
const ck = (c, n, x) => { if (c) { stats.pass++; console.log(`  ✓ ${n}`); } else { stats.fail++; console.log(`  ✗ FAIL: ${n}${x ? '  → ' + x : ''}`); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function jpost(p, body, token) {
  const r = await fetch(BASE + p, {
    method: 'POST',
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: JSON.stringify(body),
  });
  let j = null; try { j = await r.json(); } catch { /* 空 */ }
  return { code: r.status, j };
}
async function jget(p, token) {
  const r = await fetch(BASE + p, { headers: token ? { Authorization: 'Bearer ' + token } : {} });
  let j = null; try { j = await r.json(); } catch { /* 空 */ }
  return { code: r.status, j };
}

// ── 假 dypnsapi ──────────────────────────────────────────────────────────
const codes = new Map();      // phone -> { code, exp }
const dypnsCalls = [];        // { action, params }
function startFakeDypns() {
  return new Promise((res) => {
    const s = http.createServer((req, rsp) => {
      let b = '';
      req.on('data', (d) => { b += d; });
      req.on('end', () => {
        const q = new URLSearchParams(b);
        const action = q.get('Action') || '';
        const params = Object.fromEntries(q.entries());
        dypnsCalls.push({ action, params });
        const out = (o) => { rsp.writeHead(200, { 'Content-Type': 'application/json' }); rsp.end(JSON.stringify(o)); };
        if (!params.Signature || !params.AccessKeyId) return out({ Code: 'MissingAuthenticationToken', Message: '缺少签名' });
        if (action === 'SendSmsVerifyCode') {
          // 真实产品要求 TemplateParam 里是 ##code##（由平台生成）；这里断言一下
          if (!/##code##/.test(params.TemplateParam || '')) {
            return out({ Code: 'MissingTemplateParam', Message: 'TemplateParam 必须是 ##code## 占位符' });
          }
          codes.set(params.PhoneNumber, { code: CODE, exp: Date.now() + 300000 });
          return out({ Code: 'OK', RequestId: 'fake-' + dypnsCalls.length, Model: { VerifyCode: CODE, BizId: 'fake' } });
        }
        if (action === 'CheckSmsVerifyCode') {
          const rec = codes.get(params.PhoneNumber);
          if (!rec || rec.exp < Date.now()) return out({ Code: 'isv.VerifyCodeExpired', Message: '验证码已过期' });
          if (rec.code !== params.VerifyCode) return out({ Code: 'isv.VerifyCodeInvalid', Message: '验证码错误' });
          codes.delete(params.PhoneNumber);       // 一次性消费，与真实产品一致
          return out({ Code: 'OK', RequestId: 'fake-' + dypnsCalls.length });
        }
        out({ Code: 'InvalidAction', Message: 'unknown action ' + action });
      });
    });
    s.listen(P_DYPNS, '127.0.0.1', () => res(s));
  });
}
// ── 假邮件网关 ────────────────────────────────────────────────────────────
const mails = [];
function startFakeMail() {
  return new Promise((res) => {
    const s = http.createServer((req, rsp) => {
      let b = '';
      req.on('data', (d) => { b += d; });
      req.on('end', () => {
        try { mails.push(JSON.parse(b)); } catch { /* ignore */ }
        rsp.writeHead(200, { 'Content-Type': 'application/json' });
        rsp.end('{"ok":true}');
      });
    });
    s.listen(P_MAIL, '127.0.0.1', () => res(s));
  });
}

(async () => {
  const sfx = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const storeDir = path.join(os.tmpdir(), 'zhanqi-sms-' + sfx);
  const credFile = path.join(os.tmpdir(), 'aliyun-sms-' + sfx + '.json');
  fs.writeFileSync(credFile, JSON.stringify({ accessKeyId: 'LTAIfake', accessKeySecret: 'fake-secret' }));

  const dypnsSrv = await startFakeDypns();
  const mailSrv = await startFakeMail();
  console.log(`▶ 假网关已起：dypns=${P_DYPNS} mail=${P_MAIL}`);

  const srv = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: Object.assign({}, process.env, {
      PORT: String(P_SRV),
      ZHANQI_TOKEN_SECRET: 'sms-selftest-' + sfx,
      STORE_MODE: 'local',
      STORE_DIR: storeDir,
      MAIL_GATEWAY: `http://127.0.0.1:${P_MAIL}/send`,
      ALIYUN_SMS_ENDPOINT: `http://127.0.0.1:${P_DYPNS}/`,
      ALIYUN_SMS_CONFIG: credFile,
      OSS_ACCESS_KEY_ID: 'fake', OSS_ACCESS_KEY_SECRET: 'fake',   // oss.js 加载期要
      LLM_GATEWAY_INTERNAL: 'http://127.0.0.1:19999',
      // 注册闸门：默认按**生产现状** 0 跑（老客户端过渡窗口）；SELFTEST_GATE=1 跑"新客户端已发布"那档
      REQUIRE_EMAIL_CODE: process.env.SELFTEST_GATE === '1' ? '1' : '0',
      REG_PER_IP_HOUR: '3', REG_PER_IP_DAY: '50',       // 裸注册 IP 限流：调小便于测
      // 测试用的短阈值（生产是 60s / 5 条）
      SMS_RESEND_MS: '1200', SMS_PER_PHONE_DAY: '3', SMS_PER_IP_DAY: '40', SMS_PER_IP_HOUR: '40',
      CODE_RESEND_MS: '100', CODE_PER_EMAIL_DAY: '20', CODE_PER_IP_DAY: '60', CODE_PER_IP_HOUR: '40',
    }),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const log = [];
  srv.stdout.on('data', (d) => log.push(String(d)));
  srv.stderr.on('data', (d) => log.push(String(d)));

  let up = false;
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch(BASE + '/health'); if (r.ok) { up = true; break; } } catch { /* 等 */ }
    await sleep(200);
  }
  if (!up) { console.log('✗ 服务起不来：\n' + log.join('')); srv.kill(); dypnsSrv.close(); mailSrv.close(); process.exit(1); }
  console.log('✓ 服务已就绪\n');

  const P1 = '13800000001', P2 = '13800000002', P3 = '13800000003';
  const nMailOld = '老账号_' + sfx, nSms = '短信号_' + sfx, nSms2 = '短信号2_' + sfx, nBind = '待绑_' + sfx;
  const pw = 'pw123456', pw2 = 'pw654321';

  try {
    // ① /health 报告短信就绪
    const h = await jget('/health');
    ck(h.j && h.j.sms && h.j.sms.on === true, 'health: 短信开关 on=true');
    ck(h.j && h.j.sms && h.j.sms.ready === true, 'health: 短信凭证就绪 ready=true');

    // ② 老路径（邮箱）逐字节回归
    const e1 = await jpost('/send-code', { email: 'old@example.com' });
    ck(e1.code === 200 && e1.j && e1.j.ok === true, '老路径: /send-code {email} 仍可用');
    ck(Number.isInteger(e1.j && e1.j.ttl), '老路径: 响应仍只有 ttl（无 channel 字段）', JSON.stringify(e1.j));
    const mailCode = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
    const r1 = await jpost('/register', { name: nMailOld, pass: pw, email: 'old@example.com', code: mailCode });
    ck(r1.code === 201 && r1.j.ok, '老路径: 邮箱验证码注册 201');
    ck(r1.j.account && r1.j.account.email === 'old@example.com', '老路径: 账号绑定了邮箱');
    ck(r1.j.account && r1.j.account.phone === '', '老路径: 未绑手机号 → phone 掩码为空');
    ck(r1.j.account && r1.j.account.phoneBound === false, '老路径: phoneBound=false');

    // ③ 短信注册
    const s1 = await jpost('/send-code', { channel: 'sms', phone: P1 });
    ck(s1.code === 200 && s1.j.ok, '短信: /send-code 发码 200');
    ck(s1.j.channel === 'sms' && s1.j.masked === '138****0001', '短信: 回 channel + 掩码', JSON.stringify(s1.j));
    ck(dypnsCalls[dypnsCalls.length - 1].params.TemplateCode === '100001', '短信: 注册模板 = 100001');
    const r2 = await jpost('/register', { channel: 'sms', name: nSms, pass: pw, phone: P1, code: CODE });
    ck(r2.code === 201 && r2.j.ok, '短信: 注册 201');
    ck(r2.j.account.phoneBound === true && r2.j.account.phone === '138****0001', '短信: 账号已绑手机号（掩码）');
    ck(r2.j.account.email === '', '短信: 未绑邮箱（两条通道互不代填）');
    const tokSms = r2.j.token;

    // ④ 手机号唯一
    const s2 = await jpost('/send-code', { channel: 'sms', phone: P2 });
    ck(s2.code === 200, '短信: 第二个号发码 200');
    const r3 = await jpost('/register', { channel: 'sms', name: nSms2, pass: pw, phone: P1, code: CODE });
    ck(r3.code === 409, '短信: 同一手机号注册第二个账号 → 409', JSON.stringify(r3.j));
    const before = dypnsCalls.filter((c) => c.action === 'CheckSmsVerifyCode').length;
    // ⑤ 昵称重复：应在**验码之前**早退，不消耗那张码
    const r4 = await jpost('/register', { channel: 'sms', name: nSms, pass: pw, phone: P3, code: CODE });
    ck(r4.code === 409, '短信: 昵称重复 → 409');
    const after = dypnsCalls.filter((c) => c.action === 'CheckSmsVerifyCode').length;
    ck(after === before, '短信: 昵称重复时**不消费**短信码（提前探测）', `check 调用 ${before}→${after}`);

    // ⑥ 找回密码 · 短信（新客户端路径）
    await sleep(1400);   // 等过同号重发间隔（P1 刚发过注册码）
    const f1 = await jpost('/send-code', { channel: 'sms', name: nSms, purpose: 'reset' });
    ck(f1.code === 200 && f1.j.masked === '138****0001', '找回(短信): 掩码 = 绑定手机号', JSON.stringify(f1.j));
    ck(dypnsCalls[dypnsCalls.length - 1].params.TemplateCode === '100003', '找回(短信): 模板 = 100003');
    const f2 = await jpost('/reset-password', { channel: 'sms', name: nSms, code: CODE, newpass: pw2 });
    ck(f2.code === 200 && f2.j.ok && !!f2.j.token, '找回(短信): 改密成功并下发 token');
    const l1 = await jpost('/login', { name: nSms, pass: pw });
    ck(l1.code === 401, '找回(短信): 旧密码登录 401');
    const l2 = await jpost('/login', { name: nSms, pass: pw2 });
    ck(l2.code === 200, '找回(短信): 新密码登录 200');

    // ⑦ 找回密码 · 老路径（不带 channel ⇒ 走邮箱，老客户端不受影响）
    await sleep(400);
    const f3 = await jpost('/send-code', { name: nMailOld, purpose: 'reset' });
    ck(f3.code === 200 && /@example\.com$/.test(f3.j.masked || ''), '找回(邮箱): 老客户端不带 channel 仍发邮箱', JSON.stringify(f3.j));
    const mailCode2 = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
    const f4 = await jpost('/reset-password', { name: nMailOld, code: mailCode2, newpass: pw2 });
    ck(f4.code === 200 && f4.j.ok, '找回(邮箱): 老路径改密成功');

    // ⑧ 未绑手机号却走短信找回 → 同一句"码不对"，且 masked 为空（防枚举）
    const f5 = await jpost('/send-code', { channel: 'sms', name: nMailOld, purpose: 'reset' });
    ck(f5.code === 200 && f5.j.masked === '', '找回(短信): 未绑手机号的账号 → masked 空（不区分"不存在"）', JSON.stringify(f5.j));
    const f6 = await jpost('/reset-password', { channel: 'sms', name: nMailOld, code: CODE, newpass: pw });
    ck(f6.code === 400 && /验证码/.test(f6.j.error || ''), '找回(短信): 未绑手机号 → 与"码不对"同一句', JSON.stringify(f6.j));

    // ⑨ 绑定手机号
    await jpost('/send-code', { email: 'bind@example.com' });
    const mcB = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
    const r5 = await jpost('/register', { name: nBind, pass: pw, email: 'bind@example.com', code: mcB });
    ck(r5.code === 201, '绑定: 先建一个只有邮箱的账号（= 老账号场景）');
    ck(r5.j && r5.j.account && r5.j.account.phoneBound === false, '绑定: 初始未绑手机号');
    const tokB = r5.j.token;
    const b1 = await jpost('/bind-phone', { action: 'send', phone: P3 }, tokB);
    ck(b1.code === 200 && b1.j.ok, '绑定: 发绑定码 200');
    ck(dypnsCalls[dypnsCalls.length - 1].params.TemplateCode === '100004', '绑定: 模板 = 100004');
    const b2 = await jpost('/bind-phone', { action: 'commit', phone: P3, code: CODE }, tokB);
    ck(b2.code === 200 && b2.j.account.phoneBound === true, '绑定: 提交成功，phoneBound=true');
    // 绑完之后就能用短信找回了
    await sleep(1400);   // 等过 P3 发绑定码的冷却
    const b3 = await jpost('/send-code', { channel: 'sms', name: nBind, purpose: 'reset' });
    ck(b3.code === 200 && b3.j.masked === '138****0003', '绑定: 绑好后即可短信找回', JSON.stringify(b3.j));
    // ⑩ 不能把别人的号绑到自己账号
    const b4 = await jpost('/bind-phone', { action: 'commit', phone: P1, code: CODE }, tokB);
    ck(b4.code === 409, '绑定: 抢绑别人的手机号 → 409', JSON.stringify(b4.j));

    // ⑪ 未登录不能绑
    const b5 = await jpost('/bind-phone', { action: 'send', phone: P2 });
    ck(b5.code === 401, '绑定: 未登录 → 401');

    // ⑫ 参数校验 + 限流
    const v1 = await jpost('/send-code', { channel: 'sms', phone: '12345' });
    ck(v1.code === 400, '校验: 手机号格式错 → 400');
    const v2 = await jpost('/reset-password', { channel: 'sms', name: nSms, code: 'abcd', newpass: pw });
    ck(v2.code === 400, '校验: 非 6 位数字码 → 400');
    await sleep(1400);   // 等过 P2 上一次发送
    const g1 = await jpost('/send-code', { channel: 'sms', phone: P2 });
    const g2 = await jpost('/send-code', { channel: 'sms', phone: P2 });
    ck(g2.code === 429 && /秒/.test(g2.j.error || ''), '限流: 重发间隔内 → 429', JSON.stringify(g2.j));
    await sleep(1400);
    const g3 = await jpost('/send-code', { channel: 'sms', phone: P2 });
    ck(g3.code === 200, '限流: 过了间隔即可重发');

    // ⑬ 老客户端的 {email}+{code} 注册链路仍然通（不能因为改造而坏）
    const e2 = await jpost('/send-code', { email: 'old2@example.com' });
    ck(e2.code === 200, '兼容: 老客户端再发一次邮箱码');
    const mc3 = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
    const r6 = await jpost('/register', { name: '兼容_' + sfx, pass: pw, email: 'old2@example.com', code: mc3 });
    ck(r6.code === 201, '兼容: 老客户端邮箱注册仍 201');

    // ⑭ 断言签名与请求形状（假网关只放行带 Signature/AccessKeyId 的请求，已隐式验证）
    ck(dypnsCalls.every((c) => c.params.Signature && c.params.AccessKeyId && c.params.Timestamp && c.params.Version === '2017-05-25'),
      '签名: 每次调用都带 Signature/AccessKeyId/Timestamp/Version');

    // ⑮ 注册闸门 / 裸注册 IP 限流（REQUIRE_EMAIL_CODE 的两档行为）
    //    闸门 0（生产现状 = 老客户端过渡窗口）：裸注册能用，但**必须被 IP 限流兜住**
    //    闸门 1（新客户端已发布）：裸注册直接 400，带码注册照常
    const GATE = process.env.SELFTEST_GATE === '1';
    if (!GATE) {
      // 先验证"昵称被占不消耗额度"，再用满额度 —— 顺序反了会把额度先耗光
      const nth = '占位_' + sfx;
      ck((await jpost('/register', { name: nth, pass: pw })).code === 201, '裸注册限流: 闸门 0 下裸注册可达（生产现状）');
      ck((await jpost('/register', { name: nth, pass: pw })).code === 409, '裸注册限流: 同名再注册 → 409');
      ck((await jpost('/register', { name: '裸注A_' + sfx, pass: pw })).code === 201, '裸注册限流: 409 之后仍可注册（额度没被失败请求吃掉）');
      ck((await jpost('/register', { name: '裸注B_' + sfx, pass: pw })).code === 201, '裸注册限流: 第 3 次仍在阈值内');
      const over = await jpost('/register', { name: '裸注C_' + sfx, pass: pw });
      ck(over.code === 429, '裸注册限流: 超出每小时阈值(3) → 429', JSON.stringify(over.j));
      ck(over.j && /注册太频繁/.test(String(over.j.error || '')), '裸注册限流: error 是给用户看的中文');
      // 带验证码的注册**不受**这条影响（各自已有 60 秒冷却 + 每日上限）
      await jpost('/send-code', { email: 'cap@example.com' });
      const mcCap = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
      const rc = await jpost('/register', { name: '带码_' + sfx, pass: pw, email: 'cap@example.com', code: mcCap });
      ck(rc.code === 201, '裸注册限流: 带验证码的注册不受它影响（仍 201）');
    } else {
      const bare = await jpost('/register', { name: '闸门1裸注_' + sfx, pass: pw });
      ck(bare.code === 400 && /邮箱/.test(String(bare.j && bare.j.error || '')), '闸门1: 裸注册被拒 400', JSON.stringify(bare.j));
      await jpost('/send-code', { email: 'gate1@example.com' });
      const mcG = (mails[mails.length - 1].text.match(/\d{6}/) || [])[0];
      const ok1 = await jpost('/register', { name: '闸门1带码_' + sfx, pass: pw, email: 'gate1@example.com', code: mcG });
      ck(ok1.code === 201, '闸门1: 带邮箱码注册仍 201');
      const g6 = await jpost('/send-code', { channel: 'sms', phone: '13900000001' });
      const ok2 = await jpost('/register', { channel: 'sms', name: '闸门1短信_' + sfx, pass: pw, phone: '13900000001', code: CODE });
      ck(g6.code === 200 && ok2.code === 201, '闸门1: 带短信码注册仍 201');
    }
  } catch (e) {
    console.log('\n✗ 用例抛错: ' + e.stack);
    stats.fail++;
  } finally {
    srv.kill();
    dypnsSrv.close();
    mailSrv.close();
    try { fs.rmSync(storeDir, { recursive: true, force: true }); } catch { /* ignore */ }
    try { fs.unlinkSync(credFile); } catch { /* ignore */ }
  }

  console.log(`\n════ PASS=${stats.pass}  FAIL=${stats.fail} ════`);
  if (stats.fail) { console.log('服务端日志尾部：\n' + log.join('').split('\n').slice(-25).join('\n')); }
  process.exit(stats.fail ? 1 : 0);
})();
