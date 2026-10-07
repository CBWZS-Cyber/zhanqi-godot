#!/usr/bin/env node
/**
 * 账号冷备到 OSS（2026-10-04）
 * =============================================================================
 * **为什么需要**：账号只存在云服务器的本地磁盘上 —— 那台机器是**单点**。
 * 磁盘挂了、误删了、系统重装了，所有玩家账号（含进度）一次性全没。
 * 这个脚本把 `/opt/zhanqi-cloud/accounts/` 打包传到 OSS，保留最近 N 份。
 *
 * 用法：
 *   node backup_accounts.js                 # 备份一次
 *   node backup_accounts.js --dry-run       # 只看会做什么，不真跑
 *   node backup_accounts.js --keep 14       # 保留份数（默认 7）
 *   node backup_accounts.js --dir <路径>    # 指定账号目录（默认 /opt/zhanqi-cloud/accounts）
 *   node backup_accounts.js --bucket-prefix <前缀>  # 默认 zhanqi/backup
 *
 * 由 systemd timer `zhanqi-backup.timer` 每天跑一次（见 zhanqi-backup.service）。
 *
 * -----------------------------------------------------------------------------
 * 🔴 三条设计取舍（别随手改）：
 *   1. **用系统 `tar` 流式打包，不用 Node 把全部账号读进内存。**
 *      100 万账号 = 300 MB JSON，全读进内存对 1.7 GB 的机器是玩火；
 *      tar 是边读边写，内存恒定。压缩由 tar -z 做。
 *   2. **备份包里带一个 manifest.json**（时间、账号数、来源主机），
 *      恢复时能一眼看清"这份备份是什么时候、从哪来的"，不靠猜文件名。
 *   3. **上传成功后才清理旧份**。顺序反过来的话，上传失败就两头空。
 * =============================================================================
 */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const oss = require('./oss');

const argv = process.argv.slice(2);
const flag = (k) => argv.includes(k);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const ACCT_DIR = opt('--dir', '/opt/zhanqi-cloud/accounts');
const PREFIX = opt('--bucket-prefix', 'zhanqi/backup').replace(/\/+$/, '');
const KEEP = Math.max(1, Number(opt('--keep', '7')));
const DRY = flag('--dry-run');
const STATE_FILE = path.join(path.dirname(ACCT_DIR), '.last_backup.json');

function log(...a) { console.log('[backup]', ...a); }

/** 统计账号数与分片数（tar 之前先看清要备多少） */
function countAccounts(dir) {
  let n = 0, shards = 0;
  if (!fs.existsSync(dir)) return { n, shards };
  for (const s of fs.readdirSync(dir)) {
    const sp = path.join(dir, s);
    let st;
    try { st = fs.statSync(sp); } catch { continue; }
    if (!st.isDirectory()) continue;
    shards += 1;
    for (const f of fs.readdirSync(sp)) if (f.endsWith('.json')) n += 1;
  }
  return { n, shards };
}

function stamp() {
  const d = new Date();
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`;
}

function writeState(obj) {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify(obj, null, 2));
  } catch (e) {
    log('⚠ 状态文件写不了（不影响备份本身）:', e.message);
  }
}

(async () => {
  const { n: acctCount, shards } = countAccounts(ACCT_DIR);
  log(`账号目录 ${ACCT_DIR}：${acctCount} 个账号 / ${shards} 个分片`);
  if (acctCount === 0) {
    log('没有账号，跳过（空备份没有意义，还会白占 OSS 配额）');
    writeState({ at: new Date().toISOString(), accounts: 0, skipped: 'empty' });
    process.exit(0);
  }

  const ts = stamp();
  const key = `${PREFIX}/accounts-${ts}.tar.gz`;
  // 放进一个临时目录：里面既有 accounts/ 也有 manifest.json
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'zqbk-'));
  const pkg = path.join(stage, `accounts-${ts}.tar.gz`);
  const manifest = {
    backupAt: new Date().toISOString(),
    host: os.hostname(),
    sourceDir: ACCT_DIR,
    accountCount: acctCount,
    shardCount: shards,
    format: 1,
  };
  fs.writeFileSync(path.join(stage, 'manifest.json'), JSON.stringify(manifest, null, 2));

  try {
    if (DRY) {
      log(`（--dry-run）会打包 ${ACCT_DIR} + manifest.json → oss://${oss.loadCred().bucket}/${key}`);
      process.exit(0);
    }
    // ① tar（流式，内存恒定）
    log('打包中…');
    execFileSync('tar', ['czf', pkg, '-C', path.dirname(ACCT_DIR),
      path.basename(ACCT_DIR), '-C', stage, 'manifest.json'], { stdio: 'inherit' });
    const bytes = fs.statSync(pkg).size;
    log(`包大小 ${(bytes / 1048576).toFixed(2)} MB（原始 JSON 约 ${(acctCount * 316 / 1048576).toFixed(2)} MB）`);

    // ② 上传
    log(`上传 oss://${oss.loadCred().bucket}/${key}`);
    const up = await oss.putObject(fs.readFileSync(pkg), key, { ctype: 'application/gzip' });
    if (!up.ok) throw new Error('上传失败: ' + (up.error || '未知'));
    log(`✓ 已上传 ${(up.bytes / 1048576).toFixed(2)} MB`);

    // ③ 上传成功后才清理旧份
    const all = await oss.listObjects(PREFIX + '/');
    const mine = all.filter(o => /accounts-\d{8}-\d{4}\.tar\.gz$/.test(o.key))
      .sort((a, b) => a.key.localeCompare(b.key));   // key 里含时间，字典序即时间序
    const stale = mine.slice(0, Math.max(0, mine.length - KEEP));
    for (const o of stale) {
      await oss.deleteObject(o.key);
      log(`♻ 已删旧份 ${o.key}`);
    }
    log(`OSS 上现有 ${mine.length - stale.length} 份备份（保留上限 ${KEEP}）`);

    writeState({ at: manifest.backupAt, accounts: acctCount, bytes, key, kept: mine.length - stale.length });
    log('✓ 备份完成');
  } catch (e) {
    writeState({ at: new Date().toISOString(), accounts: acctCount, error: e.message });
    console.error('[backup] ✗ 失败：' + e.message);
    process.exit(1);
  } finally {
    try { fs.rmSync(stage, { recursive: true, force: true }); } catch { /* 无所谓 */ }
  }
})();
