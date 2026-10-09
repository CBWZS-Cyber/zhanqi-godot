#!/usr/bin/env node
/**
 * 战棋 · Windows 发版（2026-10-04）
 *
 *   node tools/release_desktop.js                 # 全流程：导出 → Inno 打包 → 传 OSS → 生成清单
 *   node tools/release_desktop.js --skip-export   # 复用已有的 build/战棋.exe，只重打包
 *   node tools/release_desktop.js --no-upload     # 只出包 + 生成清单，不碰 OSS
 *   node tools/release_desktop.js --keep-old      # 保留 OSS 上的历史版本包
 *   node tools/release_desktop.js --no-archive    # 跳过版本存档（不往 cbw\战棋\战棋版本存档 放代码包）
 *   node tools/release_desktop.js --no-desktop    # 不往桌面放安装包（默认会同步，见流程「8.」）
 *   node tools/release_desktop.js --theme "主题"  # 存档文件名用的主题，如 "自动更新与4位房间号"
 *
 * 版本号唯一来源：`project.godot` 的 `application/config/version`。
 * 本脚本会把它同步进 `installer/战棋.iss`（AppVersion / 文件名 / VersionInfo 全套），
 * 所以**只改 project.godot 一处就行**，不会出现"包里写 9.20、文件名写 10.4"的漂移。
 *
 * 产物：
 *   build/战棋.exe                                   导出的可执行（内嵌 pck）
 *   installer/战棋安装包_<VER>_<日期>.exe             Inno 安装包 ← 玩家下载的就是它
 *   build/version.json                                客户端读的更新清单
 *
 * 清单最终要放到 OSS 的 `zhanqi/version.json`（由 zhanqi-cloud 代理转发给客户端）。
 * 上传那步若在本机被沙盒拦住，脚本会打印"走服务器中转"的命令。
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const argv = process.argv.slice(2);
const flag = (k) => argv.includes(k);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };

const GODOT = opt('--godot', 'C:/Users/Caobo/Godot/Godot_v4.7.2-stable_win64_console.exe');
const ISCC = opt('--iscc', 'C:/Users/Caobo/AppData/Local/Programs/Inno Setup 6/ISCC.exe');
const PRESET = 'Windows Desktop';

// ── 1. 版本号（唯一来源）────────────────────────────────────────────────
const projPath = path.join(ROOT, 'project.godot');
const proj = fs.readFileSync(projPath, 'utf8');
const m = proj.match(/^config\/version\s*=\s*"([^"]+)"/m);
if (!m) { console.error('✗ project.godot 里找不到 config/version'); process.exit(1); }
const VER = m[1];
if (!/^\d+(\.\d+)*$/.test(VER)) { console.error(`✗ 版本号非法：${VER}（只允许数字和点）`); process.exit(1); }
// ⚠️ 用**本地日期**，不要用 toISOString()（那是 UTC）——
//    北京时间凌晨发版会被写成前一天（2026-10-05 01:36 实测：UTC 仍停在 10-04，
//    安装包会命名成 `..._20261004.exe`，与发布日不符）。
const _d = new Date();
const _p2 = (n) => String(n).padStart(2, '0');
const today = `${_d.getFullYear()}${_p2(_d.getMonth() + 1)}${_p2(_d.getDate())}`;
const todayDash = `${_d.getFullYear()}-${_p2(_d.getMonth() + 1)}-${_p2(_d.getDate())}`;
console.log(`▶ 版本 v${VER}（${today}）`);

// ── 2. 同步 .iss 的版本字段 ─────────────────────────────────────────────
const issPath = path.join(ROOT, 'installer', '战棋.iss');
let iss = fs.readFileSync(issPath, 'utf8');
const before = iss;
const setLine = (text, key, val) => {
  const re = new RegExp(`^${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}=.*$`, 'm');
  return re.test(text) ? text.replace(re, `${key}=${val}`) : text;
};
iss = setLine(iss, 'AppVersion', VER);
iss = setLine(iss, 'AppVerName', `战棋 ${VER}`);
iss = setLine(iss, 'UninstallDisplayName', `战棋 ${VER}`);
iss = setLine(iss, 'OutputBaseFilename', `战棋安装包_${VER}_${today}`);
iss = setLine(iss, 'VersionInfoVersion', `${VER}.0`);
iss = setLine(iss, 'VersionInfoDescription', `战棋 ${VER} 安装程序`);
iss = setLine(iss, 'VersionInfoProductVersion', VER);
if (iss !== before) {
  fs.copyFileSync(issPath, issPath + '.bak');
  fs.writeFileSync(issPath, iss);
  console.log('✓ 已同步 installer/战棋.iss 的版本字段（旧文件备份为 .iss.bak）');
} else {
  console.log('✓ installer/战棋.iss 版本字段已是最新');
}
const outBase = (iss.match(/^OutputBaseFilename=(.*)$/m) || [])[1].trim();
const installerPath = path.join(ROOT, 'installer', `${outBase}.exe`);

// ── 3. 导出 exe ─────────────────────────────────────────────────────────
if (flag('--notes-only')) {
  // 只看看"玩家会读到什么"，不编译 —— 改完 CHANGELOG 想快速确认时用
  const n = releaseNotes();
  console.log(`\n玩家会看到的更新说明（${n.length} 条）：`);
  n.forEach((s, i) => console.log(`  ${i + 1}. ${s}`));
  process.exit(n.length ? 0 : 1);
}

if (flag('--manifest-only')) {
  // 不导出、不编译、不上传，只按给定下载链接重生成 build/version.json。
  // 用途：包已经传上去了（可能是在另一个环境传的），只差把清单补全。
  const url = opt('--download-url', '');
  const size = fs.existsSync(installerPath)
    ? `${(fs.statSync(installerPath).size / 1048576).toFixed(1)} MB`
    : opt('--size', '');
  const manifest = {
    latest: VER,
    releasedAt: todayDash,
    downloads: { win64: url },
    sizeWin64: size,
    update: { win64: opt('--update-url', '') },   // 缺省空 —— 补清单时用 --update-url <zip 直链>
    sizeUpdateWin64: opt('--update-size', ''),
    notes: releaseNotes(),
  };
  const outPath = path.join(ROOT, 'build', 'version.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(`✓ 已重新生成 ${outPath}`);
  console.log(`  latest=${VER} · ${size || '（无包）'} · 说明 ${manifest.notes.length} 条 · 链接${url ? '已带' : '为空'}`);
  process.exit(0);
}

const exePath = path.join(ROOT, 'build', '战棋.exe');
if (flag('--skip-export')) {
  console.log('（--skip-export：复用已有 exe）');
} else {
  console.log('▸ 导出 Windows 可执行（Godot headless）…');
  fs.mkdirSync(path.dirname(exePath), { recursive: true });
  execFileSync(GODOT, ['--headless', '--path', ROOT, '--export-release', PRESET, exePath], { stdio: 'inherit' });
}
if (!fs.existsSync(exePath)) {
  console.error(`✗ 没生成 ${exePath} —— export template 装了吗？`);
  process.exit(1);
}
console.log(`✓ 导出完成：${(fs.statSync(exePath).size / 1048576).toFixed(1)} MB`);

// ── 4. Inno 编译安装包 ──────────────────────────────────────────────────
if (!fs.existsSync(ISCC)) { console.error(`✗ 找不到 Inno 编译器：${ISCC}`); process.exit(1); }
console.log('▸ Inno Setup 打包…');
execFileSync(ISCC, [issPath], { stdio: 'inherit' });
if (!fs.existsSync(installerPath)) { console.error(`✗ 没生成安装包：${installerPath}`); process.exit(1); }
const pkgBytes = fs.statSync(installerPath).size;
console.log(`✓ 安装包：${path.basename(installerPath)}（${(pkgBytes / 1048576).toFixed(1)} MB）`);

// ── 5. 从 CHANGELOG 取「玩家可读」的更新说明 ────────────────────────────
//
// ⚠️ 只认显式的 RELEASE-NOTES 区块，**不做"抓技术条目"的兜底**：
//    那些条目带反引号、被行宽截断，塞给玩家看是灾难（乱世五方实测踩过）。
//    没有区块 → notes 为空 + 警告，逼维护者写人话。
//
// ⚠️ 正则**没有 g 标志，只取第一组** —— 所以写新版本说明时要同时删掉旧的那组，
//    否则 version.json 会一直显示上一版的内容（同一个坑，乱世记过）。
//
// ⚠️ 标记必须**独占一行**（^...$ + m 标志）：曾经在 CHANGELOG 的说明文字里
//    写了字面的标记串，正则先匹配到那段说明、抓到空内容 → notes 变成 0 条。
function releaseNotes() {
  const cl = fs.readFileSync(path.join(ROOT, 'CHANGELOG.md'), 'utf8');
  const block = cl.match(/^<!--\s*RELEASE-NOTES-START\s*-->\s*$([\s\S]*?)^<!--\s*RELEASE-NOTES-END\s*-->\s*$/m);
  if (!block) {
    console.warn('⚠ CHANGELOG.md 里没有 RELEASE-NOTES 区块 —— 玩家会看不到更新说明。');
    console.warn('  在最新版本段落里加一对 <!-- RELEASE-NOTES-START --> / <!-- RELEASE-NOTES-END -->，');
    console.warn('  中间每行写一条「- 一句话」。详见 CHANGELOG.md 顶部的说明。');
    return [];
  }
  return block[1].split(/\r?\n/)
    .map(s => s.trim())
    .filter(s => s.startsWith('- '))
    .map(s => s.slice(2).trim())
    .filter(s => s.length > 0 && s.length < 120)
    .slice(0, 8);
}

// ── 6. 上传 OSS + 生成清单 ──────────────────────────────────────────────
(async () => {
  const ossKey = `game/zhanqi-install-v${VER}.exe`;
  let downloadUrl = '';
  let updateUrl = '';      // 自动更新包（zip）的直链，填进清单的 update.win64
  let updateSize = '';

  if (flag('--no-upload')) {
    console.log('（--no-upload：跳过 OSS）');
  } else {
    const oss = require('./cloud-service/oss');
    console.log(`▸ 上传 OSS：oss://${oss.loadCred().bucket}/${ossKey}`);
    try {
      const r = await oss.putObject(fs.readFileSync(installerPath), ossKey,
        { ctype: 'application/vnd.microsoft.portable-executable' });
      console.log(`✓ 已上传 ${(r.bytes / 1048576).toFixed(1)} MB`);
      downloadUrl = oss.signedUrl(ossKey, 315360000);   // 10 年有效
      // 自动更新包（2026-10-04 新增）：另传一份 zip —— 客户端 AutoUpdate 直接下载替换用。
      // 以前要手工跑 push_update_pkg.js 再手抄链接进清单，现在一条龙。
      if (!flag('--no-update-pkg')) {
        try {
          console.log('▸ 打并上传自动更新包（zip，客户端自动替换用）…');
          const out = execFileSync(process.execPath,
            [path.join(__dirname, 'cloud-service', 'push_update_pkg.js'), exePath, VER, '--clean-old'],
            { encoding: 'utf8' });
          process.stdout.write(out.split('\n').map(l => (l ? '  ' + l : l)).join('\n'));
          const um = out.match(/(https:\/\/\S+?\.zip\?\S+)/);
          if (um) {
            updateUrl = um[1];
            const zp = path.join(ROOT, 'build', `zhanqi-update-v${VER}.zip`);
            if (fs.existsSync(zp)) updateSize = `${(fs.statSync(zp).size / 1048576).toFixed(1)} MB`;
          } else {
            console.warn('  ⚠ 没从输出里解析到更新包直链 —— 清单的 update.win64 会是空的');
          }
        } catch (e) {
          console.error(`⚠ 更新包上传失败（安装包已传好，玩家仍可手动安装）：${e.message}`);
        }
      }
      // 清旧版：顺序放在上传成功之后，万一上传失败旧版还在，不至于两头空
      // ⚠️ 前缀必须写全 `game/zhanqi-install-`（2026-10-05 修）：
      //    原写法 `o.key.indexOf('zhanqi-install-') === 0` —— listObjects 返回的是**完整 key**
      //    （`game/zhanqi-install-v10.5.0.exe`），前缀在索引 5 而不是 0 ⇒ **永远匹配不到，是死代码**。
      //    后果实测：OSS `game/` 下堆了 4 个安装包（v10.4.0/10.4.1/10.5.0/10.5.1）共 611 MB，
      //    而日志一直显示"（无旧版本需清理）"。写全前缀后既真的会清、又不会误伤共存的项目
      //    （乱世五方用 `game/lswf-`，更新包用 `game/zhanqi-update-`，两者都不匹配本条前缀）。
      if (!flag('--keep-old')) {
        const existing = await oss.listObjects('game/');
        const stale = existing.filter(o => o.key !== ossKey && o.key.startsWith('game/zhanqi-install-'));
        for (const o of stale) {
          await oss.deleteObject(o.key);
          console.log(`  ♻ 已删旧版：${o.key}（${(o.size / 1048576).toFixed(1)} MB）`);
        }
        console.log(stale.length ? `✓ 清理 ${stale.length} 个旧版本` : '（无旧版本需清理）');
      }
    } catch (e) {
      console.error(`⚠ 上传失败：${e.message}`);
      console.error('');
      console.error('  OSS 与云服务器是**两个东西** —— 正常路径永远是「本机直传 OSS」。');
      console.error('  若失败原因是沙盒拦出网（sandbox-center ... missing actual resource subject），');
      console.error('  用提权方式重跑本脚本即可（实测提权后 putObject 正常）：');
      console.error(`    node tools/release_desktop.js --skip-export   # 在提权环境下`);
      console.error('');
      console.error('  ⛔ 不要"scp 到云服务器再让服务器传 OSS" —— 那会白占服务器磁盘一份包');
      console.error('     （132 MB）+ 3 Mbps 上行约 6 分钟。仅在提权也不可用时才走，且用完删干净：');
      console.error(`    node tools/cloud-service/push_pkg.js <包路径> --clean-old   # 在服务器上跑`);
    }
  }

  const manifest = {
    latest: VER,
    releasedAt: todayDash,
    downloads: { win64: downloadUrl },        // 安装包 .exe —— 玩家手动下载安装
    sizeWin64: `${(pkgBytes / 1048576).toFixed(1)} MB`,
    update: { win64: updateUrl },             // 更新包 .zip —— 客户端自动下载替换（2026-10-04）
    sizeUpdateWin64: updateSize,
    notes: releaseNotes(),
  };
  const outPath = path.join(ROOT, 'build', 'version.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(`✓ 已生成 ${outPath}`);
  console.log(`  latest=${VER} · 说明 ${manifest.notes.length} 条 · 下载链接${downloadUrl ? '已签名（10 年）' : '为空'}`);
  // ── 7. 版本存档（2026-10-04 新增）：把工程打成代码包放进版本存档夹 ──────
  // 依据 README 第 21 条「包内容清单（2026-09-18 立）」。此前这一步是**手工**做的，
  // 常有"这版忘了存"的情况。存档失败**不影响发版**，只警告。
  if (!flag('--no-archive')) {
    console.log('\n▸ 版本存档…');
    try {
      // 存档脚本会自动把源码按固定名 `game/zhanqi-source.zip` 留在 OSS（只留最新一份）。
      // `--no-upload`（只出包、不碰 OSS）时透传 `--no-oss`，语义保持一致。
      execFileSync(process.execPath,
        [path.join(__dirname, 'archive_version.js'), '--theme', opt('--theme', ''),
          ...(flag('--no-upload') ? ['--no-oss'] : [])],
        { stdio: 'inherit' });
    } catch (e) {
      console.error(`⚠ 版本存档失败（发版不受影响）：${e.message}`);
    }
  } else {
    console.log('（--no-archive：跳过版本存档）');
  }

  // ── 8. installer/ 只留本次这一份 ─────────────────────────────────────────
  // 它每次发版都会新增一个 159 MB 的包，不清理就跟着堆 ——
  // 2026-10-05 实测：`installer/` 里堆了 **11 个**共 **1.2 GB**（用户点名要清）。
  // ⚠️ 这里用 `unlinkSync`（永久删）而非回收站：`installer/` 是**构建输出目录**，
  //    包能由源码重打、OSS 与版本存档也都有；而送回收站得 spawn python，
  //    本机那条路会**间歇性 EBUSY**（见下一步开头的说明）。
  // 🔴 严格限定：`installer/` 的**直接子项** + 文件名以「战棋安装包」开头，不做递归。
  try {
    const myName = path.basename(installerPath);
    const instDir = path.join(ROOT, 'installer');
    const olds = fs.readdirSync(instDir)
      .filter((n) => n.endsWith('.exe') && n.startsWith('战棋安装包') && n !== myName);
    for (const n of olds) fs.unlinkSync(path.join(instDir, n));
    if (olds.length) console.log(`\n♻ installer/ 清掉 ${olds.length} 个旧安装包，只留本次这份`);
  } catch (e) {
    console.warn(`⚠ 清理 installer/ 旧包失败（不影响本次发版）：${e.message}`);
  }

  // ── 9. 同步安装包到桌面（2026-10-05 用户立的规矩：「桌面那个安装包每次要更新一下」）──
  //
  // 🔴 **用固定文件名覆盖，不做任何删除**。理由（本机实测）：
  //    在这台机器的沙箱里，`execFileSync` 去 spawn `.workbuddy/binaries/` 下的 exe 会
  //    **间歇性**报 `spawnSync … EBUSY`（node.exe 与 python.exe 都撞过，ISCC 却不撞）。
  //    而"清掉桌面旧版"按规矩必须**送回收站**（桌面是个人目录，不能 `fs.unlinkSync`），
  //    回收站又只能靠那个 python 脚本 ⇒ 一旦 EBUSY，"清理"就变成"报错"。
  //    ⇒ 改成固定名 `战棋安装包_最新.exe` 覆盖：**零删除、零 spawn**，问题整体消失；
  //      桌面上永远只有一份最新的，比"每次换名字再删旧的"更省心。
  //      具体版本号仍能在文件属性的「详细信息」里看到（Inno 已写 VersionInfo）。
  if (!flag('--no-desktop')) {
    const desktop = path.join(os.homedir(), 'Desktop');
    const DESKTOP_NAME = '战棋安装包_最新.exe';
    if (!fs.existsSync(desktop)) {
      console.log('（没找到桌面目录，跳过同步）');
    } else {
      console.log('\n▸ 同步安装包到桌面…');
      try {
        fs.copyFileSync(installerPath, path.join(desktop, DESKTOP_NAME));
        console.log(`✓ 已覆盖桌面：${DESKTOP_NAME}（v${VER} · ${(pkgBytes / 1048576).toFixed(1)} MB）`);
      } catch (e) {
        console.error(`⚠ 拷贝到桌面失败：${e.message}`);
      }
      // 只提示、不删：桌面上若还留着**带版本号的旧命名**（历史遗留），列出来由人自己处理。
      let legacy = [];
      try {
        legacy = fs.readdirSync(desktop).filter((n) => n.endsWith('.exe') && /^战棋安装包_(?!最新)/.test(n));
      } catch (_) { /* 读不到就算了，不影响发版 */ }
      if (legacy.length) {
        console.log('  提示：桌面上还有带版本号的旧包（我没动，要清理请手动送回收站）：');
        legacy.forEach((n) => console.log(`    ${n}`));
      }
    }
  } else {
    console.log('（--no-desktop：不往桌面放）');
  }

  // ── 10. 源码同步到 Gitee（2026-10-07 新增）──────────────────────────────
  // 规矩与乱世一致：**一条 main 线性历史 + 版本 tag**，保留最近 5 个 tag。
  // 取代早先的「每版一个孤儿分支」—— 孤儿分支之间不共享对象、没有 diff、
  // 与 main 无血缘，`git log --graph` / `cherry-pick` 全废（2026-10-07 已清理）。
  //
  //   🔴 三条硬约束（脚本内部已强制）：
  //      ① 只推 main 与 tag，**绝不 --force**，绝不碰其它分支；
  //      ② 推送前跑安全闸：明文密钥（sk- 长串）与敏感文件名一律拦下、中止；
  //      ③ 令牌不进 `.git/config` —— 走本机 credentials 文件。
  //   ⚠️ 失败**不阻断发版**（代码仓是附加备份），但会**大声告警**。
  if (flag('--no-publish') || flag('--no-gitee')) {
    console.log('\n（--no-publish：跳过源码仓同步）');
  } else {
    const pub = opt('--publish-script',
      'C:/Users/Caobo/.workbuddy/skills/云端服务器/scripts/repo_publish.js');
    if (!fs.existsSync(pub)) {
      console.warn(`\n⚠ 未找到源码发布脚本，已跳过源码同步：${pub}`);
    } else {
      console.log('\n▸ 同步源码到代码仓（Gitee + GitHub：提交 + 打 tag + 推送）…');
      try {
        execFileSync(process.execPath, [pub, '--dir', ROOT, '--version', `v${VER}`],
          { stdio: 'inherit' });
      } catch (e) {
        console.error('\n⚠⚠ 源码仓推送失败 —— **本次源码未进 Gitee / GitHub**（其余发版步骤不受影响）。');
        console.error(`   ${String(e.message).split('\n')[0]}`);
        console.error('   可单独重跑该脚本，或手动提交推送。');
      }
    }
  }

  console.log('\n最后一步 —— 把清单推到 OSS（客户端读的就是它）：');
  console.log(`  local : node tools/cloud-service/push_version.js "${outPath}"`);
  console.log(`  server: scp "${outPath}" root@39.105.223.8:/tmp/ && \\`);
  console.log(`          ssh root@39.105.223.8 "cd /opt/zhanqi-cloud && node push_version.js /tmp/version.json"`);
})();
