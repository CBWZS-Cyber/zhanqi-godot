#!/usr/bin/env node
/**
 * 生成服务器用的 llm.json（换方舟 API Key 时用）
 * =============================================================================
 * 用法：
 *   node set_llm_key.js <放着新 key 的文件> [输出路径]
 *
 * 🔴 **绝不打印 Key**：只校验、只写文件。写完由调用方 scp 上去、重启服务、再删掉本地文件。
 *
 * 为什么要单独一个脚本：Key 不该经过聊天/终端回显。
 * 把新 Key 粘进一个本地文本文件，让脚本读 —— 就避免了它出现在任何日志里。
 *
 * 安全提示：生成的文件权限设 600。上传到服务器后同样 chmod 600。
 * =============================================================================
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const SRC = process.argv[2];
const OUT = process.argv[3] || '/tmp/llm.json';
if (!SRC) {
  console.error('用法：node set_llm_key.js <放着新 key 的文件> [输出路径]');
  process.exit(1);
}
if (!fs.existsSync(SRC)) {
  console.error(`✗ 找不到文件：${path.resolve(SRC)}`);
  process.exit(1);
}

// 允许文件里有多余空白/换行；也容忍 "apiKey=xxx" 这种写法
let raw = fs.readFileSync(SRC, 'utf8').trim();
const m = raw.match(/^(?:apiKey|api_key|key)\s*[=:]\s*(.+)$/im);
if (m) raw = m[1].trim();
const key = raw.split(/\s+/)[0];

if (!key || key.length < 20) {
  console.error(`✗ 看起来不像 Key（长度 ${key ? key.length : 0}）。方舟的 Key 通常是 36 字符的 UUID 形式。`);
  process.exit(1);
}
if (/[^\x21-\x7e]/.test(key)) {
  console.error('✗ Key 里出现非 ASCII 可打印字符 —— 可能粘到了中文标点或引号。');
  process.exit(1);
}

const out = {
  baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/responses',
  model: 'doubao-seed-evolving',
  // 2026-09-05 实测：doubao-seed-evolving 默认深度思考 20s+ 必然超时；必须关掉（真卷 ~4s）
  thinking: 'disabled',
  apiKey: key,
};
fs.writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n', { mode: 0o600 });

console.log(`✓ 已写出 ${OUT}（权限 600）`);
console.log(`  key：${key.length} 字符，开头 ${key.slice(0, 3)}…（其余不回显）`);
console.log(`  model：${out.model} · thinking：${out.thinking}`);
console.log('');
console.log('下一步（两条命令）：');
console.log(`  1) 上传：把 ${OUT} 传到服务器 /opt/zhanqi-cloud/llm.json，chmod 600`);
console.log(`  2) 生效：ssh 到服务器执行 systemctl restart zhanqi-cloud`);
console.log('     验证：curl -s http://127.0.0.1:8789/llm/ping   → 应回 {"ok":true,"ready":true,...}');
console.log('最后：删掉本地那份临时文件。');
