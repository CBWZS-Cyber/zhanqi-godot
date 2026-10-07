#!/usr/bin/env node
/**
 * 战棋 · 打「自动更新包」并推到 OSS
 *
 *   node push_update_pkg.js <游戏 exe 路径> [版本号] [--local] [--clean-old]
 *
 * 与 push_pkg.js 的分工（**两个不同的东西，别混**）：
 *   push_pkg.js        → 安装包 .exe（给玩家手动下载安装）→ version.json 的 downloads.win64
 *   push_update_pkg.js → 更新包 .zip（给客户端自动替换）  → version.json 的 update.win64
 *
 * 为什么必须是 zip：`build/战棋.exe` 是 211 MB 的裸文件，压完约 130 MB（省 ~38%）；
 *   而且客户端 `AutoUpdate` 就是按「从 zip 里抠出 exe」实现的（ZIPReader）。
 *
 * 为什么不调 7z / Compress-Archive：本机与云服务器都不保证装了这个工具。
 *   这里用 node:zlib 的 deflateRaw **手写最小 zip 容器** —— 零依赖，两边都能跑。
 *   结构 = local header + 文件名 + 压缩数据 + central directory + EOCD；
 *   单文件、无目录、deflate(8)、UTF-8 文件名标志位。（该格式已由 Godot 侧解压路径验证过。）
 *
 * ⚠️ 清理旧版**必须带本项目前缀白名单** —— `cbw666` 是多个项目共用的 bucket，
 *    `game/` 下同时住着乱世五方和战棋的产物。按"列出全部、删掉除自己以外的"写会误删别人
 *    （2026-10-04 真出过事故：乱世的清理脚本删掉了战棋 132.5 MB 的安装包）。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const oss = require('./oss');

// ---------- 最小 ZIP（单文件、deflate）----------
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

/** 把单个文件打成 zip（deflate）。innerName 用 ASCII，避免任何编码歧义。 */
function zipSingle(innerName, data, level = 9) {
  const nameBuf = Buffer.from(innerName, 'utf8');
  const comp = zlib.deflateRawSync(data, { level });
  const crc = crc32(data);

  const lh = Buffer.alloc(30);
  lh.writeUInt32LE(0x04034b50, 0);
  lh.writeUInt16LE(20, 4);      // version needed
  lh.writeUInt16LE(0x0800, 6);  // flag: 文件名为 UTF-8
  lh.writeUInt16LE(8, 8);       // method: deflate
  lh.writeUInt16LE(0, 10);      // mod time
  lh.writeUInt16LE(0x21, 12);   // mod date（1980-01-01，固定值保证可复现）
  lh.writeUInt32LE(crc, 14);
  lh.writeUInt32LE(comp.length, 18);
  lh.writeUInt32LE(data.length, 22);
  lh.writeUInt16LE(nameBuf.length, 26);
  lh.writeUInt16LE(0, 28);

  const cd = Buffer.alloc(46);
  cd.writeUInt32LE(0x02014b50, 0);
  cd.writeUInt16LE(20, 4);      // version made by
  cd.writeUInt16LE(20, 6);      // version needed
  cd.writeUInt16LE(0x0800, 8);
  cd.writeUInt16LE(8, 10);
  cd.writeUInt16LE(0, 12);
  cd.writeUInt16LE(0x21, 14);
  cd.writeUInt32LE(crc, 16);
  cd.writeUInt32LE(comp.length, 20);
  cd.writeUInt32LE(data.length, 24);
  cd.writeUInt16LE(nameBuf.length, 28);
  cd.writeUInt16LE(0, 30);      // extra
  cd.writeUInt16LE(0, 32);      // comment
  cd.writeUInt16LE(0, 34);      // disk number
  cd.writeUInt16LE(0, 36);      // internal attrs
  cd.writeUInt32LE(0, 38);      // external attrs
  cd.writeUInt32LE(0, 42);      // local header offset

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(1, 8);
  eocd.writeUInt16LE(1, 10);
  eocd.writeUInt32LE(cd.length + nameBuf.length, 12);
  eocd.writeUInt32LE(30 + nameBuf.length + comp.length, 16);
  eocd.writeUInt16LE(0, 20);

  return Buffer.concat([lh, nameBuf, comp, cd, nameBuf, eocd]);
}

// ---------- 主流程 ----------
const argv = process.argv.slice(2);
const flags = argv.filter(a => a.startsWith('--'));
const args = argv.filter(a => !a.startsWith('--'));
const src = args[0];
const localOnly = flags.includes('--local');

if (!src || !fs.existsSync(src)) {
  console.error('用法：node push_update_pkg.js <游戏 exe 路径> [版本号] [--local] [--clean-old]');
  process.exit(1);
}

let ver = args[1] || '';
if (!ver) {
  // 从 exe 同级目录的 version.json 抠，或从文件名抠
  const vj = path.join(path.dirname(src), 'version.json');
  if (fs.existsSync(vj)) {
    try { ver = String(JSON.parse(fs.readFileSync(vj, 'utf8')).latest || ''); } catch { /* 忽略 */ }
  }
  if (!ver) {
    const mm = path.basename(src).match(/(\d+\.\d+(?:\.\d+)*)/);
    ver = mm ? mm[1] : '';
  }
}
if (!ver) { console.error('✗ 无法确定版本号，请显式传入'); process.exit(1); }

const raw = fs.readFileSync(src);
console.log(`▸ 源文件 ${path.basename(src)}（${(raw.length / 1048576).toFixed(1)} MB）`);

const t0 = Date.now();
const zip = zipSingle('zhanqi.exe', raw, 9);   // 内层用 ASCII 名；客户端按 *.exe 通配符找
const dt = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`▸ 已压缩 → ${(zip.length / 1048576).toFixed(1)} MB（省 ${(100 - zip.length / raw.length * 100).toFixed(1)}%，耗时 ${dt}s）`);

const outZip = path.join(path.dirname(src), `zhanqi-update-v${ver}.zip`);
fs.writeFileSync(outZip, zip);
console.log(`▸ 本地更新包：${outZip}`);

if (localOnly) {
  console.log('\n（--local：不上传。加 --clean-old 与不传 --local 即可推到 OSS）');
  process.exit(0);
}

const key = `game/zhanqi-update-v${ver}.zip`;
oss.putObject(zip, key, { ctype: 'application/zip' })
  .then(async (r) => {
    console.log(`✓ 已上传 ${(r.bytes / 1048576).toFixed(1)} MB → oss://${oss.loadCred().bucket}/${key}`);
    console.log(`\nversion.json 里填：\n  "update": { "win64": "${oss.signedUrl(key, 315360000)}" },\n  "sizeUpdateWin64": "${(zip.length / 1048576).toFixed(1)} MB"\n`);
    if (flags.includes('--clean-old')) {
      // 🔴 前缀白名单：只删本项目的更新包，绝不碰安装包与别的项目
      const existing = await oss.listObjects('game/');
      for (const o of existing.filter(x => x.key !== key && x.key.startsWith('game/zhanqi-update-'))) {
        await oss.deleteObject(o.key);
        console.log(`♻ 已删旧更新包 ${o.key}`);
      }
    }
  })
  .catch(e => { console.error('✗ 上传失败：' + e.message); process.exit(1); });
