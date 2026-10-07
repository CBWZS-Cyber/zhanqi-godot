#!/usr/bin/env node
/**
 * 账号存储层（2026-10-04）
 * =============================================================================
 * 把「账号存哪」这件事从业务逻辑里隔离出来，两种后端：
 *
 *   STORE_MODE=local （默认）  存服务器本地磁盘 /opt/zhanqi-cloud/accounts/
 *   STORE_MODE=oss             存阿里云 OSS 对象 zhanqi/accounts/<uid>.json
 *
 * 为什么默认改成 local（用户 2026-10-04 定）：
 *   单账号紧凑 JSON 实测只有 **316 字节**，100 万账号 = 301 MB，1000 万 = 2.9 GB，
 *   服务器磁盘还剩 34 GB —— 存本地完全够，而且**登录/注册少一次外网往返**
 *   （本机磁盘 µs 级 vs OSS 30~50 ms）。
 *
 * ⚠️ 但 316 字节 ≠ 占用 316 字节：ext4 按 **4 KB 块**分配，一个小文件实占 4 KB，
 *    **放大 13 倍**。所以：
 *      · 100 万账号 → 磁盘约 3.8 GB（不是 301 MB）
 *      · 1000 万账号 → 约 38 GB —— 会爆盘，到那规模必须换 SQLite / 打包存储
 *    当前 34 GB 余量 → 大约撑到 **800 万账号**。心里有这本账，别只看 JSON 大小。
 *
 * ⚠️ 目录必须**分片**：100 万个文件堆在一个目录里，ext4 的目录项查找会显著变慢，
 *    备份/rsync 也痛苦。这里按 uid 前 2 位分成 256 个子目录（每片约 4000 个文件/百万）。
 *
 * ★ 昵称唯一性的原子保证：
 *     local → `fs.writeFileSync(path, data, { flag: 'wx' })`
 *             wx 就是 POSIX 的 O_CREAT|O_EXCL，**内核级原子**，已存在直接 EEXIST。
 *     oss   → `x-oss-forbid-overwrite: true`，已存在返回 409 FileAlreadyExists。
 *   两条路都是「写失败即冲突」，而不是「先查再写」（后者有 TOCTOU 竞态，两个请求
 *   同时查都说没占用、都写，后写的把先写的覆盖掉）。
 * =============================================================================
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const MODE = String(process.env.STORE_MODE || 'local').toLowerCase();
const LOCAL_DIR = process.env.STORE_DIR || path.join(__dirname, 'accounts');
const OSS_PREFIX = 'zhanqi/accounts';

let oss = null;
function ossMod() {
  if (oss == null) oss = require('./oss');
  return oss;
}

/** uid → 本地路径（按前 2 位分片） */
function localPath(uid) {
  return path.join(LOCAL_DIR, uid.slice(0, 2), `${uid}.json`);
}
function ossKey(uid) { return `${OSS_PREFIX}/${uid}.json`; }

/** 新建账号。返回 { ok, exists, error? }。exists=true 表示昵称已被占用。 */
async function createAccount(uid, obj) {
  if (MODE === 'oss') {
    return ossMod().putObject(JSON.stringify(obj), ossKey(uid), {
      ctype: 'application/json', forbidOverwrite: true,
    });
  }
  const p = localPath(uid);
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, JSON.stringify(obj), { flag: 'wx' });   // ← 原子创建
    return { ok: true, exists: false };
  } catch (e) {
    if (e && e.code === 'EEXIST') return { ok: false, exists: true };
    console.error('[store] 写入失败:', e && e.message);
    return { ok: false, exists: false, error: (e && e.code) || 'IO_ERROR' };
  }
}

/** 读账号。{ ok, data } | { ok:false, missing:true } */
async function getAccount(uid) {
  if (MODE === 'oss') return ossMod().getObject(ossKey(uid));
  const p = localPath(uid);
  try {
    const raw = fs.readFileSync(p, 'utf8');
    return { ok: true, data: JSON.parse(raw) };
  } catch (e) {
    if (e && e.code === 'ENOENT') return { ok: false, missing: true };
    console.error('[store] 读取失败:', e && e.message);
    return { ok: false, missing: false, error: (e && e.code) || 'IO_ERROR' };
  }
}

/** 覆盖保存（已存在）。原子替换：先写临时文件再 rename，避免"读到半截 JSON" */
async function saveAccount(uid, obj) {
  if (MODE === 'oss') {
    return ossMod().putObject(JSON.stringify(obj), ossKey(uid), { ctype: 'application/json' });
  }
  const p = localPath(uid);
  const tmp = `${p}.tmp${process.pid}`;
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(tmp, JSON.stringify(obj));
    fs.renameSync(tmp, p);      // rename 在同一文件系统内是原子的
    return { ok: true, exists: false };
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch { /* 清理失败无所谓 */ }
    console.error('[store] 保存失败:', e && e.message);
    return { ok: false, exists: false, error: (e && e.code) || 'IO_ERROR' };
  }
}

async function deleteAccount(uid) {
  if (MODE === 'oss') return ossMod().deleteObject(ossKey(uid));
  try { fs.unlinkSync(localPath(uid)); return true; } catch { return false; }
}

/** 统计（/health 用）：账号数 + 数据字节数。结果缓存 5 秒 ——
 *  账号上百万时全量扫描要几秒，而 /health 会被探针频繁打，不能每次都扫。 */
let _statsCache = { at: 0, val: null };
function stats() {
  const out = { mode: MODE, dir: MODE === 'local' ? LOCAL_DIR : `oss://${OSS_PREFIX}`, accounts: 0, bytes: 0 };
  if (MODE !== 'local') return out;
  if (_statsCache.val && Date.now() - _statsCache.at < 5000) return _statsCache.val;
  try {
    if (fs.existsSync(LOCAL_DIR)) {
      for (const shard of fs.readdirSync(LOCAL_DIR)) {
        const sp = path.join(LOCAL_DIR, shard);
        let st;
        try { st = fs.statSync(sp); } catch { continue; }
        if (!st.isDirectory()) continue;
        for (const f of fs.readdirSync(sp)) {
          if (!f.endsWith('.json')) continue;
          out.accounts += 1;
          try { out.bytes += fs.statSync(path.join(sp, f)).size; } catch { /* 竞态忽略 */ }
        }
      }
    }
  } catch { /* 目录还没建 */ }
  _statsCache = { at: Date.now(), val: out };
  return out;
}

module.exports = {
  MODE, LOCAL_DIR, createAccount, getAccount, saveAccount, deleteAccount, stats, localPath,
};
