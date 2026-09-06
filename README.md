# 战棋（Godot 4.7）项目说明

> 本说明文件随主程序压缩包分发。任何会话/人拿到压缩包，先读本文件即可了解全局。
> **历史变更**（每版新增/修复/改动）见 [CHANGELOG.md](CHANGELOG.md)。
> **本包为 2026-09-06 版（9.06代码_v1）**：新增英雄流萤（双形态）、全量数值浮点化（两位小数）、修复重大结算 bug（回合末机制此前从未生效），详见 CHANGELOG.md 的 [9.06代码_v1] 段。9.05 整合版说明见「零、关于本整合版」。

## 零、关于本整合版（必读）

**为什么有这一版**：9.05 当天的 v1 → v2 → v3 → v4 并非严格迭代，v4 是从 v1 基线分出去的**平行分支**。

| 版本 | 基线 | 独有内容 | 是否含前一版修复 |
|---|---|---|---|
| 9.05代码_v1 | 9.04 | 4V4 星星得分制、护盾上限 | — |
| 9.05代码_v2 | v1 | 药师三技能修复、AI 大招修复 | ✅ 含 v1 |
| 9.05代码_v3 | v2 | 掠夺「本局禁技」改「限时锁技」 | ✅ 含 v1+v2 |
| 9.05代码_v4 | **v1** | 联机系统 MVP、豆包提速、主菜单弹窗修复、热座导航、追猎 per_game 限次 | ❌ **丢失 v2 药师修复 / v3 掠夺限时** |

核验证据（合并前实测）：v4 的 `skill_effects.gd` 无 `_deal_with_floor`（药师保底伤害）、`ai.gd` 无 `_ult_ready_in_range`（AI 大招）、`battle_unit.gd` 无 `lock_skill`（掠夺限时）。

**整合方式**：以 v4 为骨架（功能最新最全），把 v2 / v3 的修复三方合并回来，并补回 v4 打包时**丢失的 `installer/战棋.iss`**。

- 合并工具：`git merge-file` 三方合并（base=v1，ours=v4，theirs=v3），**零冲突**；
- `ai.gd` 因改动区域相邻，手工合入 3 个函数 + 2 处调用点；
- `tests/combat_regression.gd` 取 v3 全量版（v4 该文件回退成了 v1，丢失药师/掠夺断言，共 71 处断言）；
- `installer/战棋.iss` 从 v3 补回，MD5 与 v1~v3 一致（`d90becbe7afe3448ca8c2262e3939ea4`）。

**校验状态**：静态检查全通过（35 个 .gd 脚本括号配对/缩进、autoload 与场景脚本引用、AI 调用的战斗层接口全部存在）。

## 一、项目结构

```
zhanqi-godot/
├─ project.godot           # 引擎配置（Godot 4.7 / Forward Plus；主场景 MainUI；autoload: Global / Net）
├─ scenes/                 # 场景：MainUI(总菜单) / Duel(1V1 对局) / TeamDuel(4V4 可玩对局)
│                          #        Board(棋盘展示) / StartMenu / StoryMap(剧情地图)
├─ scripts/
│  ├─ global.gd            # autoload 全局状态（battle_mode: 1v1|4v4、offline_type: pve|hotseat）
│  ├─ board.gd             # Node2D 棋盘绘制
│  ├─ net/                 # ★ 联机系统（2026-09-05 v4 新增，Net 为 autoload）
│  │   ├─ net_session.gd   #   会话管理（autoload 入口 ENet/WebSocket 双模式）
│  │   ├─ net_protocol.gd  #   指令协议（指令重放式同步 + 同步种子确定性 RNG）
│  │   └─ net_tunnel.gd    #   cpolar 公网穿透隧道（一键建房/房间号/防泄漏回收）
│  ├─ ai/                  # ai_cfg.gd(配置) / llm_decider.gd(豆包战术模型) / ai_key.bin(混淆密钥)
│  ├─ ui/                  # duel.gd(1V1) / team_duel.gd(4V4) / main_ui.gd(菜单导航)
│  │                       # battle_hud.gd / unit_token.gd / start_menu.gd / team_board.gd
│  │                       # settings_layer.gd(局内设置+Bug上报) / story_map.gd
│  └─ combat/              # 战斗层（纯逻辑，无节点）
│     ├─ battle.gd         # 1V1 战斗管理器（2 棋 / 5×3 格）
│     ├─ battle_team.gd    # 4V4 战斗管理器（8 棋 / 10×8 标准棋盘，星星得分制）
│     ├─ battle_unit.gd    # 棋子运行时（hp/energy/盾甲/速度/状态/资源池/掠夺限时锁/联机 rng）
│     ├─ hero_defs.gd      # 英雄登记表（龙王/剑舞/邪神/光雨/药师/追猎/孤狼/rapper/仙尊/灵虚/辛克莱）
│     ├─ skill.gd          # 技能运行时（冷却/耗能/per_game 整局限次/效果调用）
│     ├─ skill_effects.gd  # 技能元信息 DATA + 效果函数 EFFECTS（药师保底伤害、掠夺限时、联机同步随机）
│     ├─ ai.gd             # BattleAI（1V1/4V4 共用：plan_move / plan_skill，含大招追击射程）
│     └─ grid_board.gd     # 通用格图 BFS/可达模块（待接入战斗层）
├─ tests/                  # 回归测试（headless -s 运行）
│  ├─ combat_regression.gd    # 1V1 战斗层回归（71 断言，含药师/掠夺限时断言）
│  ├─ team4v4_regression.gd   # 4V4 战斗层回归（52 断言）
│  ├─ ai_tier_bench.gd / hero_team_rank.gd   # AI 强度基准 / 英雄梯度排行
│  └─ *_tmp.gd               # 临时验证脚本（确定性/热座导航/联机重放等，可清理）
├─ maps/                   # 地图数据（白灵殿.json）
├─ tools/                  # map-editor.html(地图编辑器) / map_exe_app(打包版) / update_installer.sh
└─ installer/战棋.iss      # Inno Setup 打包脚本
```

## 二、进度与计划

- **已完成**：主菜单导航；1V1 可玩对局；4V4 星星得分制与可玩 UI；局内设置 + Bug 上报引导；4V4 蛇形选人页；AI 难度分层（简单/普通/困难）；**联机系统 MVP（ENet 局域网 + WebSocket 公网穿透，1V1/4V4 均可）**；药师三技能修复；AI 大招释放修复；掠夺改限时锁技；追猎流炎飞弹整局限次。
- **进行中**：
  1. ✅ 战斗层 BattleTeam + 4V4 回归测试；
  2. ✅ 4V4 可玩交互 UI（TeamDuel + 棋盘控件 + 菜单解锁 PVE/热座）；
  3. ✅ 局内设置 + Bug 上报引导；
  4. ✅ 4V4 蛇形选人页；
  5. ✅ AI 难度分层 + PVE 难度入口；
  6. ✅ 联机系统 MVP（含断线判负、状态漂移护栏、同步种子确定性 RNG）；
  7. 🚧 最高难度＝豆包战术模型融合（协议/消费/后端选择已完成，网络层真机联调待验证）；
  8. ⏳ 数值平衡观察；公网真实双机对局持续观察（cpolar 免费隧道中转）。
- **后续计划**：新英雄虞美人（等设计者补"子体"规则）、李太白（等补属性）；地形障碍接入 grid_board；4V4 数值平衡（僵局观察）；技能"流星飞弹"真名统一为"流炎飞弹"（代码内显示名待改）。
- **2026-09-06 更新**：新英雄流萤（双形态）；菱形射程系统；理智栏+状态面板+状态徽章+右键查看棋子；全量数值浮点化（两位小数）；修复重大 bug（回合末结算失效/吞技能/理智深跌/图鉴无法退出/4V4 棋盘收窄为 8×8+出生格）。

## 三、运行与测试

- 运行：Godot 打开 `project.godot`，或导出后运行。
- 无头冒烟：`godot --headless --path . --import` 后 `--quit-after 2` 无 ERROR 即通过。
- 1V1 回归：`godot --headless --path . -s res://tests/combat_regression.gd`
- 4V4 回归：`godot --headless --path . -s res://tests/team4v4_regression.gd`
- 退出码 0=全过；1=有失败。

## 四、注意点

1. **版本命名**：主程序压缩包用 `日期+版本号`（如 `9.05代码_v1.zip`），禁止无声覆盖旧版本；改主程序前先备份。**当日多版本若非迭代关系，需合并出当日整合版再上传仓库。**
2. **回合结构（1V1 与 4V4 一致）**：每棋每回合 = 1 移动权（8 方向 1 格）+ 1 技能权（先移后放、可放弃）；同回合内所有存活棋按实时速度从高到低依次行动；速度变化立即影响后续顺序。
3. **出生与棋盘**：1V1 = 3×3 主区 + 左右翼各 1 出生格；4V4 = 8×8 主区（x1..8,y1..8）+ 左翼红方 4 出生（x0,y3..6）/ 右翼蓝方 4 出生（x9,y3..6）。棋盘格 x0..9/y1..8 均可通行。
4. **4V4 已知边界**：技能目标暂统一"单目标"（AI 选最近、玩家点选）；范围/多目标后续声明式补。**数值未平衡**：英雄普伤 1~3 vs 护甲 1~3，护甲为固定减伤，AI 全自动局常出现"互相打不动→80 回合僵局"，属已知现象。
5. **伤害口径**：普伤=盾先吸→甲减免→扣血；真伤走 `lose_hp` 无视盾甲；百分比伤害未标真伤按普伤结算。
6. 英雄 hp 为小数值制（6~10），盾/甲/伤害同样小数值，调数值时注意整体比例。
7. **最高难度（困难·战术模型）**：豆包每回合做「选择题」（A进攻/B稳守/C保命）+ 填「战术倾向」（focus/posture/protect）；规则 AI 据此调权重后精确执行，失败自动回退本地 hard。API Key 以混淆加密随包（ai_key.bin），仅本地解密；离线/断网时困难自动用本地 AI。
8. **联机依赖**：公网建房需 cpolar（免安装版可用）—— 将 `cpolar.exe` 放游戏同目录 `cpolar/` 下，authtoken 配置于 `~/.cpolar/cpolar.yml`；**局域网直连与加入方零依赖**。
9. **联机确定性**：效果函数内随机一律走 `user.rng`（战斗层注入的同步 RNG），`null` 时回退全局随机（单机旧路径）。新增效果函数务必沿用 `_sync_randf` / `_sync_randi`，否则联机双方会状态漂移。
10. **数值全为浮点（两位小数）**：hp/能量/盾/甲/伤害均为 float，显示用 `%.2f`。⚠️ GDScript 的 `mini/maxi/clampi` 是整数版，传 float 会**静默截断**，数值比较一律用 `minf/maxf/clampf`。
11. **射程形状**：默认切比雪夫（斜对角=1）；声明式菱形射程 `range_shape: "diamond"`（曼哈顿距离，如流萤超新星 13 格）；多目标 `max_targets`（如流星飞弹 2、超新星 3）。
12. **流萤双形态**：技能组动态替换见 `skill_effects.gd` 的 `_liuying_enter_full/_exit_full/_tick_attack`；新增"形态切换型"英雄照此范式。控制类负面一律走 `BattleUnit.try_control(flag)`（接入 40% 免控等抵抗机制），不要直接 `add_flag`。
13. **右键棋子**：弹 `UnitInfoPopup`（scripts/ui/unit_info_popup.gd），1V1/4V4 共用。

---

> 【说明文件 · 自传播提醒 —— 请勿删除本段】
> 1. 本压缩包根目录必须有一份说明文件（README.md），写明：项目结构、进度与计划、注意点；
> 2. 每当你新建或更新说明文件时，必须把【本段提醒】原样复制到新说明文件的结尾；
> 3. 若发现某压缩包缺说明文件或结尾无本提醒：补上（内容参考包内代码），并把本段一起附上；
> 4. 说明文件也同步到网盘「主程序」文件夹随压缩包一起上传。
