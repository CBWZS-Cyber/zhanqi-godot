#!/usr/bin/env node
/**
 * 服务器侧：把安装包推到 OSS（release_desktop.js 本机上传失败时的降级通道）
 *
 *   node push_pkg.js <安装包路径> [版本号]
 *
 * 版本号不给就从文件名里抠（"战棋安装包_10.4.0_20261004.exe" → 10.4.0）。
 * 上传后打印 download 的**签名 URL**，把它填进 version.json 的 downloads.win64。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const oss = require('./oss');

const src = process.argv[2];
if (!src || !fs.existsSync(src)) {
  console.error('用法：node push_pkg.js <安装包路径> [版本号]');
  process.exit(1);
}
let ver = process.argv[3] && !process.argv[3].startsWith('-') ? process.argv[3] : '';
if (!ver) {
  const mm = path.basename(src).match(/(\d+\.\d+(?:\.\d+)*)/);
  ver = mm ? mm[1] : '';
}
if (!ver) { console.error('✗ 无法确定版本号，请显式传入'); process.exit(1); }

const key = `game/zhanqi-install-v${ver}.exe`;
const bytes = fs.statSync(src).size;
console.log(`▸ ${path.basename(src)}（${(bytes / 1048576).toFixed(1)} MB）→ oss://${oss.loadCred().bucket}/${key}`);

oss.putObject(fs.readFileSync(src), key, { ctype: 'application/vnd.microsoft.portable-executable' })
  .then(async (r) => {
    console.log(`✓ 已上传 ${(r.bytes / 1048576).toFixed(1)} MB`);
    console.log(`\ndownloads.win64 =\n${oss.signedUrl(key, 315360000)}\n`);
    if (process.argv.includes('--clean-old')) {
      const existing = await oss.listObjects('game/');
      for (const o of existing.filter(x => x.key !== key && x.key.indexOf('zhanqi-install-') === 0)) {
        await oss.deleteObject(o.key);
        console.log(`♻ 已删旧版 ${o.key}`);
      }
    }
  })
  .catch(e => { console.error('✗ 上传失败：' + e.message); process.exit(1); });
