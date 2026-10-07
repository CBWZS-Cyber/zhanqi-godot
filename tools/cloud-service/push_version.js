#!/usr/bin/env node
/**
 * 把一份本地 version.json 推到 OSS 的 zhanqi/version.json
 *   node push_version.js <本地 version.json 路径>
 *
 * 客户端（scripts/net/update_check.gd）读的就是这份清单 ——
 * 由 zhanqi-cloud 代理转发（GET http://39.105.223.8:8789/version.json），
 * 所以 bucket 保持私有即可，玩家拿不到 AK。
 *
 * 为什么会需要在**服务器上**跑：本机沙盒可能拦对 OSS 的出网请求，
 * 而服务器一直有凭证（/opt/zhanqi-cloud/.aliyun-oss.txt）且出网自由。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const oss = require('./oss');

const src = process.argv[2];
if (!src) {
  console.error('用法：node push_version.js <本地 version.json 路径>');
  process.exit(1);
}
if (!fs.existsSync(src)) {
  console.error(`找不到文件：${path.resolve(src)}`);
  process.exit(1);
}
const raw = fs.readFileSync(src, 'utf8');
let parsed;
try { parsed = JSON.parse(raw); } catch (e) {
  console.error('不是合法 JSON：' + e.message);
  process.exit(1);
}
if (!parsed.latest) {
  console.error('清单缺少 latest 字段');
  process.exit(1);
}

oss.putObject(raw, 'zhanqi/version.json', { ctype: 'application/json' })
  .then(r => {
    console.log(`✓ oss://cbw666/zhanqi/version.json（${r.bytes} 字节）latest=${parsed.latest}`);
  })
  .catch(e => { console.error('✗ 上传失败：' + e.message); process.exit(1); });
