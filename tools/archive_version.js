#!/usr/bin/env node
/**
 * 战棋 · 版本存档 —— 把工程打成「代码包」zip 放进版本存档夹
 *
 *   node tools/archive_version.js --theme "自动更新与4位房间号"
 *   node tools/archive_version.js --theme "xx" --dry-run     # 只列清单，不写盘
 *   node tools/archive_version.js --theme "xx" --dir <目录>  # 换存档位置
 *   node tools/archive_version.js --theme "xx" --no-oss     # 只存本地，不上传 OSS
 *
 * 存档成功后**顺带把这份源码包留在 OSS**（固定对象名 `game/zhanqi-source.zip`，
 *   覆盖即最新 ⇒ 上面永远只有唯一一份）。用途：维护者电脑不在身边时，可从 OSS 抽源码看。
 *   🔴 玩家下载的是**安装包**；源码包不进 version.json / 客户端 / 网页。OSS 桶 private ACL。
 *   上传为 best-effort：失败只警告（本地存档已完成），加 `--no-oss` 可显式跳过。
 *
 * 依据：**README 第 21 条「包内容清单（2026-09-18 立）」** —— 那份清单是唯一权威，
 *   本脚本只是把它自动化。**不要靠"对比上一版 zip"反推范围。**
 *
 * 🔴 三条硬规矩（同 README 第 21 条）：
 *   ① 顶层统一套一层 `godot-chess-tactics/`；
 *   ② `.import` 必须带上（Godot 靠它识别资源，`.gitignore` 忽略它但包内必须有）；
 *   ③ **禁止静默覆盖既有版本号** —— 同名已存在就自动递增 `_v2` / `_v3`，并在报告里说明。
 *
 * ⚠️ 打包后必查 4 项（本脚本会自己跑一遍）：
 *   ① installer/ 在不在（曾在 9.09/v1/v2 三版**整目录丢失**）；
 *   ② 根目录 5 文件齐不齐；③ 有没有混进 .mp4 / *.exe；④ 顶层目录名是否统一。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const ROOT = path.resolve(__dirname, '..');
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const flag = (k) => argv.includes(k);

const ARCHIVE_DIR = opt('--dir', 'C:/Users/Caobo/cbw/战棋/战棋版本存档');
const THEME = opt('--theme', '');
const DRY = flag('--dry-run');
const TOP = 'godot-chess-tactics';

// ── 包内容清单（README 第 21 条）──────────────────────────────────────────
const KEEP_ROOT_FILES = ['README.md', 'CHANGELOG.md', '.gitignore', 'project.godot', 'export_presets.cfg'];
const KEEP_DIRS = ['art', 'assets', 'data', 'installer', 'maps', 'scenes', 'scripts', 'story', 'tests', 'tools'];
/** installer/ 只收这 3 个（其余是 .exe 安装包，138MB 一个） */
const INSTALLER_KEEP = ['战棋.iss', '战棋-使用说明.txt', '战棋证书.cer'];
const DROP_DIRS = ['.godot', 'build', 'Godot', '.git', '.workbuddy'];
/** 路径里出现任一片段就丢（_backup* 全系列 / 视频参考帧） */
const DROP_PATH_PARTS = ['_backup', path.join('video', 'frames')];
const DROP_EXT = ['.exe', '.log', '.tmp', '.mp4'];

// ── CRC32 + 多文件 ZIP（零依赖，本机与服务器都能跑）─────────────────────
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = (c >>> 8) ^ CRC_TABLE[(c ^ buf[i]) & 0xff];
  return (c ^ -1) >>> 0;
}
function buildZip(entries) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const e of entries) {
    const nameBuf = Buffer.from(e.name, 'utf8');
    const comp = zlib.deflateRawSync(e.data, { level: 6 });
    const crc = crc32(e.data);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);
    lh.writeUInt16LE(0x0800, 6);      // UTF-8 文件名
    lh.writeUInt16LE(8, 8);           // deflate
    lh.writeUInt16LE(0, 10);
    lh.writeUInt16LE(0x21, 12);
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(comp.length, 18);
    lh.writeUInt32LE(e.data.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26);
    lh.writeUInt16LE(0, 28);
    parts.push(lh, nameBuf, comp);

    const cd = Buffer.alloc(46);
    cd.writeUInt32LE(0x02014b50, 0);
    cd.writeUInt16LE(20, 4);
    cd.writeUInt16LE(20, 6);
    cd.writeUInt16LE(0x0800, 8);
    cd.writeUInt16LE(8, 10);
    cd.writeUInt16LE(0, 12);
    cd.writeUInt16LE(0x21, 14);
    cd.writeUInt32LE(crc, 16);
    cd.writeUInt32LE(comp.length, 20);
    cd.writeUInt32LE(e.data.length, 24);
    cd.writeUInt16LE(nameBuf.length, 28);
    cd.writeUInt16LE(0, 30);
    cd.writeUInt16LE(0, 32);
    cd.writeUInt16LE(0, 34);
    cd.writeUInt16LE(0, 36);
    cd.writeUInt32LE(0, 38);
    cd.writeUInt32LE(offset, 42);
    central.push(cd, nameBuf);
    offset += 30 + nameBuf.length + comp.length;
  }
  const cdBuf = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(cdBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cdBuf, eocd]);
}

// ── 采集文件 ─────────────────────────────────────────────────────────────
function shouldDrop(rel) {
  const segs = rel.split(/[\\/]/);
  for (const d of DROP_DIRS) if (segs.includes(d)) return true;
  for (const p of DROP_PATH_PARTS) if (rel.includes(p)) return true;
  const ext = path.extname(rel).toLowerCase();
  if (DROP_EXT.includes(ext)) return true;
  return false;
}
const entries = [];
const skipped = [];
function collect(absDir, relDir) {
  for (const name of fs.readdirSync(absDir)) {
    const abs = path.join(absDir, name);
    const rel = relDir ? `${relDir}/${name}` : name;
    const st = fs.statSync(abs);
    if (st.isDirectory()) {
      if (shouldDrop(rel + '/')) { skipped.push(rel + '/'); continue; }
      collect(abs, rel);
    } else {
      if (shouldDrop(rel)) { skipped.push(rel); continue; }
      if (relDir === 'installer' && !INSTALLER_KEEP.includes(name)) { skipped.push(rel); continue; }
      entries.push({ name: `${TOP}/${rel}`, data: fs.readFileSync(abs), rel });
    }
  }
}
for (const f of KEEP_ROOT_FILES) {
  const abs = path.join(ROOT, f);
  if (fs.existsSync(abs)) entries.push({ name: `${TOP}/${f}`, data: fs.readFileSync(abs), rel: f });
  else console.warn(`⚠ 根目录缺文件：${f}`);
}
for (const d of KEEP_DIRS) {
  const abs = path.join(ROOT, d);
  if (fs.existsSync(abs)) collect(abs, d);
  else console.warn(`⚠ 缺目录：${d}/`);
}

// ── 打包自检（README 第 21 条的"必查 4 项"）─────────────────────────────
const rels = new Set(entries.map(e => e.rel));
const chk = [];
chk.push(['① installer/ 在包内', [...rels].some(r => r.startsWith('installer/'))]);
chk.push(['② 根目录 5 文件齐', KEEP_ROOT_FILES.every(f => rels.has(f))]);
chk.push(['③ 无 .mp4 / *.exe 混入', ![...rels].some(r => /\.(mp4|exe|log|tmp)$/i.test(r))]);
chk.push(['④ 顶层目录名统一', entries.every(e => e.name.startsWith(TOP + '/'))]);

const ver = (fs.readFileSync(path.join(ROOT, 'project.godot'), 'utf8').match(/^config\/version\s*=\s*"([^"]+)"/m) || [])[1] || '0.0';
const d = new Date();
const stamp = `${d.getMonth() + 1}.${d.getDate()}`;
let base = THEME ? `${stamp}整合版_${THEME}` : `${stamp}整合版`;
let target = '';
for (let n = 1; n <= 20; n++) {
  const name = n === 1 ? `${base}.zip` : `${base}_v${n}.zip`;
  const p = path.join(ARCHIVE_DIR, name);
  if (!fs.existsSync(p)) { target = p; break; }
}

console.log(`▸ 工程 v${ver} · 收集 ${entries.length} 个文件（跳过 ${skipped.length} 项）`);
console.log('  跳过示例：', skipped.slice(0, 6).join('  '), skipped.length > 6 ? '…' : '');
for (const [name, ok] of chk) console.log(`  ${ok ? '✓' : '✗'} ${name}`);
if (chk.some(([, ok]) => !ok)) { console.error('\n✗ 自检未通过，已中止（没写盘）'); process.exit(1); }
if (!target) { console.error('✗ 同名版本已到 _v20，请换主题名'); process.exit(1); }

if (DRY) {
  console.log(`\n（--dry-run：不写盘）将生成 → ${target}`);
  process.exit(0);
}
fs.mkdirSync(ARCHIVE_DIR, { recursive: true });
const zip = buildZip(entries);
fs.writeFileSync(target, zip);
console.log(`\n✓ 已存档：${target}`);
console.log(`  大小 ${(zip.length / 1048576).toFixed(1)} MB（未压缩 ${(entries.reduce((s, e) => s + e.data.length, 0) / 1048576).toFixed(1)} MB）`);

// ── 顺带把源码留一份在 OSS（2026-10-06 立的发版规矩）────────────────────────
// 固定对象名 ⇒ OSS 上**永远只有最新这一份**（覆盖，不堆历史）。用途见文件头。
// best-effort：失败只警告，本地存档已算完成（与「存档失败不影响发版」同一原则）。
if (flag('--no-oss')) {
  console.log('（--no-oss：跳过 OSS 源码留存）');
} else {
  uploadSourceToOss(zip).catch((e) => {
    console.warn(`⚠ 源码留存 OSS 失败（本地存档已完成，不影响发版）：${e.message}`);
  });
}

async function uploadSourceToOss(zipBuf) {
  const oss = require('../cloud-service/oss');
  const KEY = 'game/zhanqi-source.zip';
  const r = await oss.putObject(zipBuf, KEY, { ctype: 'application/zip' });
  if (!r.ok) throw new Error(r.error || 'putObject 未成功');
  console.log(`✓ 源码已留存 OSS：${KEY}（${(r.bytes / 1048576).toFixed(1)} MB）—— 固定名，只留最新一份`);
  const url = oss.signedUrl(KEY, 315360000);   // 10 年
  const linkFile = path.join(ARCHIVE_DIR, '源码-OSS直链.txt');
  fs.writeFileSync(linkFile,
    '# 战棋 · 最新源码（OSS 固定直链，10 年有效）\n'
    + '# 每次发版覆盖同一对象 ⇒ 这个链接永远指向最新源码。\n'
    + '# 🔴 仅供维护者自用；**不要**发给玩家 —— 玩家应下载安装包。\n'
    + `# 版本：v${ver}    更新：${new Date().toISOString().slice(0, 10)}\n`
    + url + '\n', 'utf8');
  console.log(`  直链已写入本机（不进任何玩家可见产物）：${linkFile}`);
}
