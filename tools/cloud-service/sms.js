#!/usr/bin/env node
/**
 * sms.js —— 阿里云「**短信认证**」（号码认证服务 dypns）薄封装（2026-10-09）
 * =============================================================================
 * 零依赖：只用 Node 内置 `crypto` + 全局 `fetch`（v18+），与 ./oss.js 同风格。
 *
 * 🔴 **别把它当成「阿里云短信服务(dysms)」**——两者是**不同的产品**：
 *   · 我们用：`dypnsapi.aliyuncs.com`（**短信认证**，个人实名可用，用系统赠送的签名与模板）
 *   · 不是：  `dysmsapi.aliyuncs.com`（短信服务，**要企业资质+签名报备**，个人办不了）
 *   两者的套餐包**不通用**（短信服务送的免费额度在这里一分用不上）。
 *
 * ── 关键机制（决定了本模块为什么这么薄）────────────────────────────────
 *   发码时 `TemplateParam` 必须传 **`##code##` 占位符**（不是具体数字）——
 *   这样验证码由**阿里云生成并存储**，随后用 `CheckSmsVerifyCode` 校验。
 *   ⇒ 我们**不需要自己存短信验证码**，也不需要防重放表（阿里云侧一次性消费）。
 *   ⇒ 但**限流必须自己做**：每次调用都**计费**（套餐包 1000 次，用完要再买）。
 *   ⚠️ 若传具体数字（如 `{"code":"123456"}`）则 API 侧**不校验**，
 *      `CheckSmsVerifyCode` 会形同虚设 —— 这是最容易踩的坑。
 *
 * ── 凭证 ────────────────────────────────────────────────────────────────
 *   读 `<同目录>/.aliyun-sms.json`（600，属主 svc-cloud），格式：
 *     { "accessKeyId": "LTAI...", "accessKeySecret": "..." }
 *   可用 `ALIYUN_SMS_CONFIG` 指向别处（测试用）。
 *   与 `.aliyun-oss.txt` 同一套放置约定：**凭证不进代码、不进仓库**。
 *
 * ── 实测参数（2026-10-09 首次实发成功）──────────────────────────────────
 *   SignName=恒创联众（6 个赠送签名任选）· TemplateCode=100001（登录/注册）
 *   CodeLength=6 · ValidTime=300 · CodeType=1 · TemplateParam={"code":"##code##","min":"5"}
 * =============================================================================
 */
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const ENDPOINT = process.env.ALIYUN_SMS_ENDPOINT || 'https://dypnsapi.aliyuncs.com/';
const API_VERSION = '2017-05-25';                 // dypnsapi 的固定版本号，别改
const REGION = process.env.ALIYUN_SMS_REGION || 'cn-hangzhou';
const TIMEOUT_MS = Number(process.env.ALIYUN_SMS_TIMEOUT_MS || 8000);

/** 赠送签名（必须与赠送模板**配套**使用，不可交叉、不可自定义） */
const SIGN_NAME = process.env.ALIYUN_SMS_SIGN || '恒创联众';
/** 赠送模板：100001 登录/注册 · 100003 重置密码 · 100004 绑定新手机号 */
const TPL = {
  login: process.env.ALIYUN_SMS_TPL_LOGIN || '100001',
  reset: process.env.ALIYUN_SMS_TPL_RESET || '100003',
  bind: process.env.ALIYUN_SMS_TPL_BIND_NEW || '100004',
};

function configPath() {
  return process.env.ALIYUN_SMS_CONFIG || path.join(__dirname, '.aliyun-sms.json');
}

/** 读凭证。失败**抛错**（调用方决定是降级还是拒绝），并把原因说清楚。 */
function loadCred() {
  const p = configPath();
  let j;
  try {
    j = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    throw new Error(`读不到短信凭证 ${p}：${e.message}`);
  }
  const id = String(j.accessKeyId || '').trim();
  const secret = String(j.accessKeySecret || '').trim();
  if (!id || !secret) throw new Error(`短信凭证不完整（${p} 缺 accessKeyId / accessKeySecret）`);
  return { accessKeyId: id, accessKeySecret: secret };
}

/** 凭证是否就绪（用于启动自检与 /health，不抛错） */
function available() {
  try { loadCred(); return true; } catch (e) { return false; }
}
function configError() {
  try { loadCred(); return ''; } catch (e) { return e.message; }
}

/** 阿里云 RPC 风格的百分号编码：与 `encodeURIComponent` 有三处不同 */
function pe(s) {
  return encodeURIComponent(String(s))
    .replace(/\+/g, '%20')
    .replace(/\*/g, '%2A')
    .replace(/%7E/g, '~');
}

/** 经典 RPC 签名：HMAC-SHA1(secret + "&", "POST&%2F&" + pe(排序后的查询串)) */
function sign(params, secret) {
  const qs = Object.keys(params).sort().map((k) => `${pe(k)}=${pe(params[k])}`).join('&');
  const sts = `POST&${pe('/')}&${pe(qs)}`;
  return crypto.createHmac('sha1', `${secret}&`).update(sts, 'utf8').digest('base64');
}

/**
 * 调一次 dypnsapi。返回**结构化结果**（不抛 HTTP 错，只抛凭证/网络错）：
 *   { ok, code, message, requestId, http }
 * `ok` 的判据是阿里云返回的 `Code === 'OK'`（HTTP 200 也可能是业务失败）。
 */
async function call(action, args) {
  const cred = loadCred();
  const params = Object.assign({
    Format: 'JSON',
    Version: API_VERSION,
    AccessKeyId: cred.accessKeyId,
    SignatureMethod: 'HMAC-SHA1',
    Timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    SignatureVersion: '1.0',
    SignatureNonce: crypto.randomUUID(),
    RegionId: REGION,
    Action: action,
  }, args);
  params.Signature = sign(params, cred.accessKeySecret);

  const body = Object.keys(params).sort().map((k) => `${pe(k)}=${pe(params[k])}`).join('&');
  const r = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  let j = null;
  try { j = await r.json(); } catch (e) { j = null; }
  const code = (j && j.Code) || '';
  return {
    ok: code === 'OK',
    code,
    message: (j && (j.Message || j.LocalizedMessage)) || (j ? '' : `HTTP ${r.status} 非 JSON`),
    requestId: (j && j.RequestId) || '',
    http: r.status,
  };
}

/**
 * 发验证码。`purpose`: 'login'（默认，注册/登录模板）| 'reset' | 'bind'
 * ⚠️ `TemplateParam` 传 `##code##` 占位符 —— 由阿里云生成并校验，见文件头。
 */
async function sendVerifyCode(phone, purpose) {
  const tpl = TPL[purpose] || TPL.login;
  const validSec = String(Number(process.env.ALIYUN_SMS_VALID_SEC || 300));
  const min = String(Math.max(1, Math.round(Number(validSec) / 60)));
  return call('SendSmsVerifyCode', {
    PhoneNumber: String(phone),
    CountryCode: '86',
    SignName: SIGN_NAME,
    TemplateCode: tpl,
    TemplateParam: JSON.stringify({ code: '##code##', min }),
    CodeLength: String(Number(process.env.ALIYUN_SMS_CODE_LEN || 6)),
    ValidTime: validSec,
    CodeType: '1',            // 1 = 纯数字
    ReturnVerifyCode: 'false',
  });
}

/** 校验验证码（一次性消费）。成功 = `ok:true` */
async function checkVerifyCode(phone, code) {
  return call('CheckSmsVerifyCode', {
    PhoneNumber: String(phone),
    VerifyCode: String(code),
  });
}

module.exports = {
  sendVerifyCode, checkVerifyCode, available, configError, call,
  SIGN_NAME, TPL,
};
