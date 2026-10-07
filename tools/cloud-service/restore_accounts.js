#!/usr/bin/env node
/**
 * 从 OSS 冷备恢复账号（2026-10-04）
 * =============================================================================
 * 备份不验证恢复 = 没有备份。这个脚本就是那条"验证"路径。
 *
 * 用法：
 *   node restore_accounts.js                     # 列出 OSS 上所有备份（不动任何东西）
 *   node restore_accounts.js --latest            # 恢复最新一份
 *   node restore_accounts.js --key <OSS key>     # 恢复指定一份
 *   node restore_accounts.js --latest --to <dir> # 恢复到别处（默认 /opt/zhanqi-cloud/accounts）
 *
 * 🔴 安全设计：**绝不直接覆盖现有账号目录**。
 *    恢复前先把现有的整目录改名成 `accounts.bak-<时间戳>/`（原地保留，可回退），
 *    再把备份内容放进去。恢复完要 `systemctl restart zhanqi-cloud`。
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

const PREFIX = opt('--bucket-prefix', 'zhanqi/backup').replace(/\/+$/, '');
const TARGET = opt('--to', '/opt/zhanqi-cloud/accounts');
const log = (...a) => console.log('[restore]', ...a);

function stamp() {
  const d = new Date();
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

(async () => {
  // ① 列备份
  const all = await oss.listObjects(PREFIX + '/');
  const list = all.filter(o => /accounts-\d{8}-\d{4}\.tar\.gz$/.test(o.key))
    .sort((a, b) => b.key.localeCompare(a.key));   // 新的在前
  if (list.length === 0) {
    console.log('OSS 上还没有任何备份。先跑一次 backup_accounts.js。');
    process.exit(1);
  }

  console.log(`OSS 上的账号备份（${list.length} 份，新 → 旧）：`);
  list.forEach((o, i) => console.log(`  ${i === 0 ? '★' : ' '} ${o.key}  ${(o.size / 1048576).toFixed(2)} MB`));

  const key = opt('--key', '') || (flag('--latest') ? list[0].key : '');
  if (!key) {
    console.log('\n（以上只是列表，未做任何修改。要恢复请加 --latest 或 --key <上面的 key>）');
    process.exit(0);
  }
  if (!list.some(o => o.key === key)) {
    console.error(`✗ 备份不存在：${key}`);
    process.exit(1);
  }

  // ② 下载
  log(`下载 ${key} …`);
  const got = await oss.getBuffer(key);
  if (!got.ok) { console.error('✗ 下载失败：' + (got.error || '缺失')); process.exit(1); }
  log(`✓ 已下载 ${(got.data.length / 1048576).toFixed(2)} MB`);

  const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'zqrs-'));
  const pkg = path.join(stage, 'backup.tar.gz');
  fs.writeFileSync(pkg, got.data);

  try {
    // ③ 解压
    execFileSync('tar', ['xzf', pkg, '-C', stage], { stdio: 'inherit' });
    const src = path.join(stage, 'accounts');
    if (!fs.existsSync(src)) throw new Error('包里没有 accounts/ 目录 —— 备份文件可能坏了');
    const mfPath = path.join(stage, 'manifest.json');
    if (fs.existsSync(mfPath)) {
      const mf = JSON.parse(fs.readFileSync(mfPath, 'utf8'));
      log(`备份信息：${mf.backupAt} · 来自 ${mf.host} · ${mf.accountCount} 个账号`);
    }

    // ④ 现存目录改名保留（绝不覆盖）
    if (fs.existsSync(TARGET)) {
      const old = `${TARGET}.bak-${stamp()}`;
      fs.renameSync(TARGET, old);
      log(`原目录已保留为 ${old}`);
    }
    fs.mkdirSync(path.dirname(TARGET), { recursive: true });
    fs.renameSync(src, TARGET);

    let n = 0;
    for (const s of fs.readdirSync(TARGET)) {
      const sp = path.join(TARGET, s);
      if (fs.statSync(sp).isDirectory()) n += fs.readdirSync(sp).filter(f => f.endsWith('.json')).length;
    }
    log(`✓ 已恢复 ${n} 个账号到 ${TARGET}`);
    log('⚠ 记得重启服务：systemctl restart zhanqi-cloud');
  } catch (e) {
    console.error('[restore] ✗ 失败：' + e.message);
    process.exit(1);
  } finally {
    try { fs.rmSync(stage, { recursive: true, force: true }); } catch { /* 无所谓 */ }
  }
})();
