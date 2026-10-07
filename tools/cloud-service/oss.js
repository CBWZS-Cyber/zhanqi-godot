#!/usr/bin/env node
/**
 * 阿里云 OSS 极简客户端（零依赖，V1 签名）
 * 2026-10-04 移植自 乱世五方 tools/oss.js，并按战棋云端账号服务的需要扩展。
 *
 * ★ 与乱世版的关键差异：**支持 x-oss-forbid-overwrite（条件写）**。
 *   OSS V1 签名的签名串是 6 段：
 *       VERB \n Content-MD5 \n Content-Type \n Date \n CanonicalizedOSSHeaders CanonicalizedResource
 *   `x-oss-*` 头必须按字典序拼进 CanonicalizedOSSHeaders（每个头以 \n 结尾），
 *   **否则返回 403 SignatureDoesNotMatch** —— 这条是实测踩出来的，不是文档抄的。
 *
 *   有了条件写，注册的「昵称唯一」由 OSS 自己保证原子性（已存在 → 409 FileAlreadyExists），
 *   服务端**不需要任何锁**，也不怕两个请求同时注册同一个昵称。
 *
 * 凭证查找顺序（部署到服务器时用第 2 条，权限 600）：
 *   1) 环境变量 OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET / OSS_BUCKET / OSS_ENDPOINT
 *   2) 本文件同目录的 .aliyun-oss.txt
 *   3) ~/.aliyun-oss.txt
 *
 * 🔴 凭证铁律：任何日志、错误信息、返回值里**不许出现 AK/SK**。
 */
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');

/** 解析 key=value 文本为配置对象（忽略注释与空行） */
function parseCred(txt) {
  const cfg = {};
  for (const line of String(txt).split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#') || !t.includes('=')) continue;
    const i = t.indexOf('=');
    cfg[t.slice(0, i).trim().toLowerCase()] = t.slice(i + 1).trim();
  }
  return cfg;
}

function loadCred() {
  const envAk = process.env.OSS_ACCESS_KEY_ID;
  const envSk = process.env.OSS_ACCESS_KEY_SECRET;
  if (envAk && envSk) {
    return {
      ak: envAk, sk: envSk,
      bucket: process.env.OSS_BUCKET || 'cbw666',
      endpoint: process.env.OSS_ENDPOINT || 'oss-cn-beijing.aliyuncs.com',
    };
  }
  const candidates = [
    path.join(__dirname, '.aliyun-oss.txt'),
    path.join(os.homedir(), '.aliyun-oss.txt'),
  ];
  for (const p of candidates) {
    if (!fs.existsSync(p)) continue;
    const cfg = parseCred(fs.readFileSync(p, 'utf8'));
    const ak = cfg.access_key_id || cfg.accesskeyid;
    const sk = cfg.access_key_secret || cfg.accesskeysecret;
    if (!ak || !sk) continue;
    return {
      ak, sk,
      bucket: cfg.bucket || 'cbw666',
      endpoint: cfg.endpoint || 'oss-cn-beijing.aliyuncs.com',
    };
  }
  throw new Error('未找到 OSS 凭证（环境变量或 .aliyun-oss.txt）');
}

const cred = loadCred();

/** 逐段编码 key，保留路径分隔符 '/' */
function encKey(key) {
  return String(key).split('/').map(encodeURIComponent).join('/');
}

/** x-oss-* 头 → CanonicalizedOSSHeaders（字典序，每项以 \n 结尾） */
function canonicalOssHeaders(h) {
  const keys = Object.keys(h || {}).filter(k => k.toLowerCase().startsWith('x-oss-')).sort();
  if (!keys.length) return '';
  return keys.map(k => `${k.toLowerCase()}:${String(h[k]).trim()}\n`).join('');
}

/** V1 签名 */
function sign(method, contentType, dateOrExpires, resource, ossHeaders) {
  const sts = [method, '', contentType || '', dateOrExpires, (ossHeaders || '') + resource].join('\n');
  return crypto.createHmac('sha1', cred.sk).update(sts, 'utf8').digest('base64');
}

/**
 * 底层请求。opts: { body?: Buffer|string, ctype?, ossHeaders?, query?, expiresSec? }
 * 返回 { code, body, headers }
 */
function request(method, key, opts = {}) {
  return new Promise((resolve, reject) => {
    const body = opts.body != null ? Buffer.from(opts.body) : null;
    const ctype = opts.ctype || '';
    const ossH = opts.ossHeaders || {};
    let dateOrExpires = new Date().toUTCString();
    let query = opts.query || '';
    if (opts.expiresSec) {
      dateOrExpires = String(Math.floor(Date.now() / 1000) + Number(opts.expiresSec));
      query = `?OSSAccessKeyId=${encodeURIComponent(cred.ak)}&Expires=${dateOrExpires}`;
    }
    const resource = `/${cred.bucket}/${key === null ? '' : key}`;
    const sig = sign(method, ctype, dateOrExpires, resource, canonicalOssHeaders(ossH));
    const headers = { Date: new Date().toUTCString(), Authorization: `OSS ${cred.ak}:${sig}` };
    if (opts.expiresSec) {
      headers.Authorization = `OSS ${cred.ak}:${sign(method, ctype, dateOrExpires, resource, '')}`;
      query += `&Signature=${encodeURIComponent(headers.Authorization.split(':')[1])}`;
    }
    if (ctype) headers['Content-Type'] = ctype;
    if (body) headers['Content-Length'] = body.length;
    for (const k of Object.keys(ossH)) headers[k] = ossH[k];

    const req = https.request({
      host: `${cred.bucket}.${cred.endpoint}`,
      method,
      path: (key === null ? '/' : '/' + encKey(key)) + query,
      headers,
      // 超时按体积给：安装包 130+ MB 用固定 15 秒必然超时（实测踩过）。
      // 每 MB 给 4 秒，下限 15 秒，上限 10 分钟。
      timeout: Math.min(600000, Math.max(15000, Math.ceil((body ? body.length : 0) / 1048576) * 4000)),
    }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({
        code: res.statusCode,
        body: Buffer.concat(chunks),
        headers: res.headers,
      }));
    });
    req.on('timeout', () => { req.destroy(new Error('OSS 请求超时')); });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

/**
 * 上传对象。
 * @param {Buffer|string} data
 * @param {string} key
 * @param {object} [opts] ctype / forbidOverwrite
 * @returns {Promise<{ok:boolean, exists:boolean, error?:string}>}
 *          forbidOverwrite 且对象已存在 → { ok:false, exists:true }
 */
async function putObject(data, key, opts = {}) {
  const ossHeaders = {};
  if (opts.forbidOverwrite) ossHeaders['x-oss-forbid-overwrite'] = 'true';
  const r = await request('PUT', key, {
    body: data,
    ctype: opts.ctype || 'application/octet-stream',
    ossHeaders,
  });
  if (r.code === 200) return { ok: true, exists: false, bytes: Buffer.byteLength(data) };
  const bodyText = r.body.toString('utf8');
  if (r.code === 409 || /FileAlreadyExists/.test(bodyText)) return { ok: false, exists: true };
  const code = (bodyText.match(/<Code>([^<]*)<\/Code>/) || [])[1] || `HTTP ${r.code}`;
  return { ok: false, exists: false, error: code };
}

/** 读对象。不存在 → { ok:false, missing:true } */
async function getObject(key) {
  const r = await request('GET', key);
  if (r.code === 200) {
    const parsed = JSON.parse(r.body.toString('utf8'));
    return { ok: true, data: parsed };
  }
  if (r.code === 404) return { ok: false, missing: true };
  const code = (r.body.toString('utf8').match(/<Code>([^<]*)<\/Code>/) || [])[1] || `HTTP ${r.code}`;
  return { ok: false, missing: false, error: code };
}

/** 读原始文本对象（version.json 用；不做 JSON 解析，保持原样转发） */
async function getText(key) {
  const r = await request('GET', key);
  if (r.code === 200) return { ok: true, text: r.body.toString('utf8') };
  if (r.code === 404) return { ok: false, missing: true };
  return { ok: false, missing: false, error: `HTTP ${r.code}` };
}

/** 读**二进制**对象（备份包 .tar.gz 用 —— 不能走 getObject 的 JSON.parse） */
async function getBuffer(key) {
  const r = await request('GET', key);
  if (r.code === 200) return { ok: true, data: r.body };
  if (r.code === 404) return { ok: false, missing: true };
  const code = (r.body.toString('utf8').match(/<Code>([^<]*)<\/Code>/) || [])[1] || `HTTP ${r.code}`;
  return { ok: false, missing: false, error: code };
}

async function deleteObject(key) {
  const r = await request('DELETE', key);
  return r.code === 204 || r.code === 200;
}

async function listObjects(prefix) {
  const r = await request('GET', null, {
    query: `?prefix=${encodeURIComponent(prefix || '')}&max-keys=1000`,
  });
  if (r.code !== 200) throw new Error(`list HTTP ${r.code}`);
  const t = r.body.toString('utf8');
  const keys = [...t.matchAll(/<Key>([^<]*)<\/Key>/g)].map(m => m[1]);
  const sizes = [...t.matchAll(/<Size>(\d+)<\/Size>/g)].map(m => Number(m[1]));
  return keys.map((k, i) => ({ key: k, size: sizes[i] || 0 }));
}

/** 生成带签名的长期下载 URL（默认 10 年） */
function signedUrl(key, expiresSec) {
  const exp = Math.floor(Date.now() / 1000) + Number(expiresSec || 315360000);
  const resource = `/${cred.bucket}/${key}`;
  const sig = sign('GET', '', String(exp), resource, '');
  return `https://${cred.bucket}.${cred.endpoint}/${encKey(key)}`
    + `?OSSAccessKeyId=${encodeURIComponent(cred.ak)}&Expires=${exp}&Signature=${encodeURIComponent(sig)}`;
}

function bucketInfo() {
  return { bucket: cred.bucket, endpoint: cred.endpoint, akTail: cred.ak.slice(-4), akLen: cred.ak.length };
}

module.exports = {
  putObject, getObject, getText, getBuffer, deleteObject, listObjects, signedUrl, bucketInfo, loadCred,
};
