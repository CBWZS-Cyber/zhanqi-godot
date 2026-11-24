# 战棋（Godot 4.7）项目说明

> **许可 / License**
> 代码 [GPL-3.0](LICENSE) —— 可自由使用/修改/分发，**衍生作品须同样以 GPL-3.0 开源**；作者保留另行商业授权的权利。
> 剧情、人设、世界观等创作内容 [CC BY-NC-ND 4.0](LICENSE-CONTENT.md) —— 署名、非商业、禁止演绎。
> **美术资源与字体不在本仓库内，保留所有权利**。第三方组件（Godot / Noto / Ma Shan Zheng / DragonBones）
> 的许可与归属见 [LICENSE-CONTENT.md](LICENSE-CONTENT.md)。

> 📌 **文档纪律（先读这条）**：包内文档**只有 `README.md` + `CHANGELOG.md` 两份**。
> **禁止新建任何 `9.xx说明.md` / `*_说明.txt` 单版说明** —— 一个版本 = CHANGELOG 里的一段，不是一个新文件。
> 本版改了什么 → 写 `CHANGELOG.md` 顶部；进度 / 注意点 / 设计约束 → 写本文件对应章节。
> 完整规则见本文件末尾「文档纪律」段。

> 本说明文件随主程序压缩包分发。任何会话/人拿到压缩包，先读本文件即可了解全局。
> **历史变更**（每版新增/修复/改动）见 [CHANGELOG.md](CHANGELOG.md)。
> ⚠️ **本文件夹 = 最新对外版本 `10.4.1`（2026-10-04 已发包）+ 之后的本地改动。**
> 未发包的本地改动逐条见 [CHANGELOG.md](CHANGELOG.md) 顶部各段（每段都标了发包状态）。
> ⚠️ **10.4.1 的两条硬约束**：① 房间号 **11 位 → 4 位**，**11 位的旧客户端无法加入房间**，
> 已发出去的安装包 / APK 需同步更新；② 安装目录由 `C:\Program Files\战棋` 改为
> `%LOCALAPPDATA%\Programs\战棋`（为自动更新让路 —— Program Files 下普通用户没有写权限）。
> ⚠️ **别只看 CHANGELOG 的「未发包」标记就断定某改动没对外**：Godot 的更新包是**全量替换**
> （整包 130~170 MB），一个全量包会**一次性带走当时所有已完成的改动** —— 标记只反映"这段代码
> 写完时的状态"，不代表之后没有被打包带走。要确认就查时间戳，或直接搜包体内容
> （用注意点 33 的 `tools/inspect_pck.py`）。
>
> 📜 **历史口径（2026-09-30 之前，仅存档参考）**：本文件夹曾经是「`9.13整合版` + 9.14 / 9.17 /
> 9.18 / 9.28 / 9.30 五个本地补丁」，那时桌面 `9.13整合版_v3.zip` 里没有这五项：
> ① 侧栏条统一走 `DamageFx.update_bar()`；② 剧情关棋盘支持双指捏合缩放；
> ③ 流血 / 烧伤「等级与剩余回合」解耦（2026-09-18）；④ 新手教程 + 本地账号（2026-09-28）；
> ⑤ 房间号联机（2026-09-30）。—— **不要把那个 zip 反向覆盖到本文件夹**。
> `9.13整合版` 口径 = v1 + v2 + v3_昊祁移中 + v4 全量合并，基线 = `9.12代码_v1_白灵殿难度调整`；
> 9.13 当天 4 个包不是一条迭代线（v2 / v4 / v3 互为平行包，v4 整体丢失了 9.12_v2 的地形门禁 /
> 龙水域豁免 / 拆障系统，并回退了昊祁出生点）。
> 本版把 4 个包的全部更新内容合并：**掉血特效与护盾血条 + 地形可破坏与龙水域豁免 + 昊祁移中（难度根因解法）**。
> **完整变更条目与合并过程**见 [CHANGELOG.md](CHANGELOG.md) 的 `[9.13整合版]` 段。
> **改代码前必读本文件末尾的「附录 A：设计约束与防坑」**（设计铁律 / 防坑清单 / 遗留问题 / 调参方法）。
> ⚠️ **三件仍需注意的事**：
> 1. **AI 回合仍是同帧结算** —— 玩家自己操作的回合特效完整可见；AI 回合的伤害特效会**同时出现**，
>    看不到"谁先打谁"的过程。要解决需加**表现层回放队列**（会改变回合节奏手感），待拍板；
> 2. 「获胜太简单」的**根因已由本版修掉**（昊祁出生点东移至 `(0,1)`/`(0,2)`，红方追击几何上成立），
>    但**难度手感需在真机上重新评估**（仿真：差 AI 1.0% / 完美护送 100.0%），
>    调参只改 `maps/白灵殿.json` 的 `spawns`、**不需改代码**，速查表见「附录 A.3.5」；
> 3. 9.13_v1 起地形真正生效（森林免伤 / 森林移出耗能 / 水域回合末耗能），**调难度时要把地形一并算进去**。

## 零之零、9.13 版做了什么（本版必读）

**基线**：`9.12代码_v1_白灵殿难度调整`。**纯修复，零数值改动。**

| # | 问题 | 症状 | 修法 |
|---|---|---|---|
| ① | **白灵殿关卡打不开**（P0） | `story_battle_board.gd:203` 的 `var p := pu` 类型推断失败 → 该脚本编译失败 → `story_battle.gd` 连带失败 → `StoryBattle.tscn` UI 建不起来 | `var p: BattleUnit = pu` |
| ② | **剧情关地形全失效** | `battle_base.board` 从未赋值 + 地形从未灌进格图 → `terrain_id` 恒为 0；18 格森林（受击 ×0.8、移出耗 1）与 12 格水域（回合末 −1 能）全按空地算 | `_build_board()` 灌地形并 `board = _board`；出生即 `_sync_terrain`；新增 `_place()` 替换三处直改 `u.cell` |
| ③ | **游戏本体起不来** | `_backup_912merge/`、`.workbuddy/backup_2026*/` 里的脚本副本重复声明 14 个 `class_name` → `main_ui.gd`（主菜单）编译失败；跑测试得到假绿 `PASS 0 / FAIL 0` | 给这些目录各加一个空文件 `.gdignore` |

**为什么 9.12 没发现**：9.12 的校验只做了「括号配对 + `res://` 引用存在」这类**静态检查**，
抓不到类型推断错误、编译失败和运行期接线缺失。本版已改为真机 `godot --headless` 全量验证（见「三、运行与测试」）。

**⚠️ 本版把地形接上后，白灵殿手感会变**：森林免伤、森林/山地移出耗能、水域回合末耗能开始真正生效。
这不改变「红方追不上昊」的几何结论，但影响双方的实际抗打与续航，下次调难度请一并纳入。

**校验状态（本版实测，Godot 4.7.2 win64）**：

| 项 | 结果 |
|---|---|
| 逐文件语法检查（56 个 `.gd`） | ✅ 0 错 |
| `--import` 资源导入 | ✅ 0 ERROR |
| 冒烟 `--quit-after 2` | ✅ 0 SCRIPT ERROR |
| 1V1 战斗回归 | ✅ **PASS 97 / FAIL 0** |
| 4V4 战斗回归 | ✅ **PASS 58 / FAIL 0** |
| 地形回归（含新增第 ⑦ 项） | ✅ **7/7 PASS** |
| 剧情关冒烟（新增） | ✅ **PASS 28 / FAIL 0** |
| 剧情关场景加载 | ✅ 0 SCRIPT ERROR |

## 零之零二、9.12 版做了什么（历史，保留备查）

**基线**：`9.10代码_v3_整合版`（网盘「主程序」文件夹）。

| 项 | 9.10_v3 | 9.12_v1（本版） |
|---|---|---|
| 属性/技能表 | 《角色属性与技能表.xlsx》 | **《角色属性与技能表2.0.xlsx》**（蓝方削弱、红方加强） |
| 逃生区 | `x ≥ 16` 整列带（12 格） | **`x = 18, y = 0~3`（最右 4 格）** |
| 胜利条件 | 昊 1 人抵达逃生区 | **昊与祁都存活且都抵达逃生区** |
| 判负条件 | 昊阵亡 / 白灵殿全灭 | 昊阵亡 / **祁阵亡** / 白灵殿全灭 |
| 牵引 | 只有昊（每 2 回合） | 昊（每 2 回合） + **祁（每 3 回合）** |
| UI | 单金环（昊） | **双金环（昊+祁）**，已就位转青色 |

**⚠️ 本版最关键的结论**：白灵殿「太简单」的根因**不是数值，而是地图几何 + 移动力**。

| 单位 | 起点 | 到新逃生区步数 | 移动力 |
|---|---|---|---|
| 昊 | (7,1) | **11 步** | 1 步/回合 + 每 2 回合牵引 1 格 |
| 祁 | (5,2) | **13 步** | 2 步/回合 + 每 3 回合牵引 1 格 |
| 宵 | (-9,1) | **27 步** | 2 步/回合 |
| 龙1 | (-10,-1) | 28 步 | 2 步/回合 |
| 熊2 | (-13,1) | 31 步 | 2 步/回合 |

红方落后昊 **16 步**，双方移动力只差 1 步/回合 → **红方在数学上追不上**（纯追击需 16 回合，
而昊 7~8 回合就能脱身）。所以加强红方数值只能延长「打了也白打」的过程，**不能改变胜负**。
下一版必须在下面三种解法里选一个（详见 CHANGELOG「遗留问题」）：
① 挪红方出生点到地图中部；② 胜利条件改「守满 N 回合」；③ 在 x≈10~12 加通路阻塞。

**校验状态**：静态检查通过（括号配对 0 异常；`story_defs` 引用 26 技能全在 `SkillEffects.DATA`；
`EFFECTS` 引用 18 个 `_ef_s1_*` 函数全部存在）。⚠️ **未跑真机 `godot --headless`**（沙箱无 wine，
Godot 编译器是 win64 exe），本地需补跑冒烟 + 三条回归。

## 零之一、9.10 当日版本关系与整合说明（历史，保留备查）

**结论：9.10 当天的 v1 与 v2 并非迭代关系，而是从同一基线 `9.09代码_v1_图鉴与故事系统` 分出的两条平行分支。** 直接取「修改时间最新」的 v2 当主程序，会静默丢失 v1 的整个白灵殿可玩关卡（6 个文件）。

| 包（网盘文件名） | 修改时间 | 基线 | 独有内容 | 是否含另一支 |
|---|---|---|---|---|
| `9.09代码_v1_图鉴与故事系统` | 09-09 | 9.08 | 图鉴、英雄故事、故事系统 | —（共同祖先，232 文件） |
| `9.10代码_v1_白灵殿可玩化` | 09-10 20:54 | **9.09** | `StoryBattle.tscn`、`battle_story.gd`、`story_defs.gd`、`story_battle.gd`、`story_battle_board.gd`、17 个剧情技能（`skill_effects.gd` 82423→101482 B） | ❌ 无地形/武器系统 |
| `9.10代码_v2` | 09-10 21:59 | **9.09** | `terrain.gd`、`weapons.gd`、`terrain_regression.gd`、`武器系统_设计.md`、全量 `.import`、工程线→凛黎线改名 | ❌ **丢失 v1 的白灵殿 6 文件** |

**判定证据（不止看文件名/修改时间）**：

1. v2 相对 9.09 只新增 62 文件、改动 13 文件，**没有 v1 新增的 6 个文件**；
2. v1 的 `skill_effects.gd` = 101482 B，9.09 与 v2 均为 82423 B → v2 根本没碰过技能表；
3. v1 的 CHANGELOG 多了 `[9.10代码_v1]` 段，v2 的 CHANGELOG 停留在 9.08_v2 → **v2 的 CHANGELOG 是回退版本**，证明它在 v1 之前就分出去了。

**整合方式（本版）**：

1. 以 **v2** 为骨架（文件最全，含 62 个新文件与 `.import`）；
2. 补回 v1 独有的 6 个文件 + v1 版 `skill_effects.gd`（17 个剧情技能）+ `story_video_knight.gd`（`NEXT` 指向 `StoryBattle.tscn`）；
3. 两边都改过的 2 个文件做三方合并（base=9.09）：
   - `scripts/combat/battle_unit.gd`：`git merge-file` **零冲突**（v2 加地形/装备字段，v1 加 `init_flags`/`energy_guard`/`guard_note`，改动区域不重叠）；
   - `story/骑士线_剧情.md`：v2 只做了「工程线→凛黎线」整文件改名，v1 改的是胜利条件正文 → 取 v1 正文再套用改名；
4. 打包遗漏补齐：`installer/`（战棋.iss + 使用说明 + 证书）在 9.09/v1/v2 三包中**全部缺失**，从 `9.07代码_v4_整合版` 补回，`战棋.iss` MD5 仍为 `d90becbe7afe3448ca8c2262e3939ea4`；
5. 说明文件同步：README 头部改为本版、CHANGELOG 补 `[9.10代码_v2]` 与 `[9.10代码_v3_整合版]` 两段、新增 `9.10整合版_说明.md`。

**校验状态**：55 个 `.gd` 括号配对/缩进检查通过；`res://` 引用除 3 处模板字符串外全部存在；`skill_effects.gd` 对战斗层/单位层的跨文件调用 0 处找不到定义。⚠️ 沙箱无 wine，**未跑 `godot --headless` 真机冒烟与回归**，本地需补跑 `combat_regression.gd` / `team4v4_regression.gd` / `terrain_regression.gd`。

## 零、关于 9.05 整合版（历史，保留备查）

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

> 📌 **顶层命名说明（2026-09-18 补 —— 先看这条，别把同一份工程当成两个项目）**
>
> **同一份工程，在三个地方各有一份，但"顶层文件夹名"不一样：**
>
> | 在哪儿 | 顶层名 | 说明 |
> |---|---|---|
> | **Gitee 仓库（远端）** | `zhanqi-godot` | `https://gitee.com/cao-bowencs666/zhanqi-godot`（私有）。**下面这棵树是按"仓库视角"画的** |
> | **本地工程目录** | `godot-chess-tactics` | 本文件所在目录（例：`…/WorkBuddy/<会话>/godot-chess-tactics/`） |
> | **整合包 `.zip` 内** | `godot-chess-tactics` | 解压后的顶层文件夹，**与本地同名**（**不叫** `zhanqi-godot`） |
>
> **一句话**：`zhanqi-godot` 是**远端仓库名**，`godot-chess-tactics` 是**本地与包内的文件夹名**；
> 包内那份 `README.md` 与本文件是同一份。
>
> ⚠️ **推送前必须核对仓库名**：Gitee 账号 `cao-bowencs666` 下**还有一个与本项目无关的仓库 `666`**，
> 推错仓库是**已经发生过**的事故类型 —— 推送目标只能是 `zhanqi-godot`，且**只推 orphan 分支、不动 `main`、不 `--force`**。

```
zhanqi-godot/
├─ project.godot           # 引擎配置（Godot 4.7 / Forward Plus；主场景 MainUI；autoload: Global / Net）
├─ scenes/                 # 场景：MainUI(总菜单) / Duel(1V1 对局) / TeamDuel(4V4 可玩对局)
│                          #        Board(棋盘展示) / StartMenu / StoryMap(旧沙盒，已非主入口)
│                          #        ★ StoryBattle(骑士线第一关·白灵殿 可玩关卡) / StoryVideoKnight(开场动画)
│                          #        ★ Tutorial(新手引导关，2026-09-28 新增)
├─ scripts/
│  ├─ global.gd            # autoload 全局状态（battle_mode: 1v1|4v4、offline_type: pve|hotseat）
│  │                       #   2026-09-28 起新增 current_account / tutorial_hero / tutorial_tier
│  ├─ board.gd             # Node2D 棋盘绘制
│  ├─ save/                # ★ 存档（2026-09-28 建；2026-10-05 删「本地账号」后重构）
│  │   ├─ progress_store.gd #   ProgressStore：**匿名本机进度**（user://progress.json）
│  │   │                    #   ⚠️ 它**不是账号** —— 没有名字/没有 id/不能切换；「离线玩」用的就是它
│  │   └─ cloud_session.gd  # ★ CloudSession：云端登录态缓存 —— **只存 token + 账号信息，不存密码**
│  ├─ net/                 # ★ 联机系统（2026-09-05 v4 新增，Net 为 autoload）
│  │   ├─ net_session.gd   #   会话管理（autoload 入口 ENet/WebSocket 双模式）
│  │   ├─ net_protocol.gd  #   指令协议（指令重放式同步 + 同步种子确定性 RNG）
│  │   ├─ net_tunnel.gd    #   cpolar 公网穿透（已由 net_relay_host 取代，保留可回退）
│  │   ├─ net_roomcode.gd  # ★ 房间号客户端：4 位数字号 ↔ 地址（2026-09-30）
│  │   ├─ net_relay_host.gd# ★ 反向隧道房主侧桥接器（纯 GDScript，房主零安装，2026-10-03）
│  │   ├─ cloud_api.gd     # ★ CloudApi：云端账号 / 进度客户端（2026-10-04）
│  │   ├─ update_check.gd  # ★ UpdateCheck：自动更新检测（2026-10-04）
│  │   └─ auto_update.gd   # ★ AutoUpdate：自动下载 + 解压 + 写更新脚本（2026-10-04）
│  ├─ ai/                  # ai_cfg.gd(战术模型配置：**只放云端端点，不含任何 Key**)
│  │                       # llm_decider.gd(「选择题」战术决策；调云端 /llm，失败回退本地)
│  │                       # ⚠️ ai_key.bin 已于 2026-10-04 删除 —— Key 只在服务器上
│  ├─ ui/                  # duel.gd(1V1) / team_duel.gd(4V4) / main_ui.gd(菜单导航)
│  │                       # battle_hud.gd / unit_token.gd / start_menu.gd / team_board.gd
│  │                       # ★ ui_kit.gd(UiKit：按钮/面板/数值条工厂，四个界面共用，2026-09-30 抽出)
│  │                       # ★ battle_screen.gd(BattleScreen：1V1/4V4 对局界面公共基类，2026-09-30 抽出)
│  │                       # ★ rules_text.gd(RulesText：规则介绍文案，2026-09-30 从 Global 移出)
│  │                       # ★ ui_design.gd(UiDesign：「墨金」设计令牌，全工程唯一视觉真源，2026-10-04)
│  │                       # ★ ui_theme.gd(UiTheme：令牌→全局 Theme + 组件库；补上原缺失的焦点环，2026-10-04)
│  │                       # ★ tutorial.gd(新手引导关：步骤机 + 金色描边高亮，2026-09-28 新增)
│  │                       # settings_layer.gd(局内设置+Bug上报) / story_map.gd(旧沙盒)
│  │                       # ★ story_battle.gd(剧情关卡对局界面) / story_battle_board.gd(自由拼格棋盘)
│  │                       # ★ damage_fx.gd(DamageFx：血条换算+缓动共用工具) / hp_shield_bar.gd(护盾血条控件)
│  └─ combat/              # 战斗层（纯逻辑，无节点）
│     ├─ battle_base.gd    # 战斗引擎公共基类（共享的单位查询/距离/射程/移动/技能校验/状态结算/max_targets_of）
│     │                    #   英雄专属规则只留转发壳，实现见 hero_rules.gd（2026-09-30）
│     ├─ battle.gd         # 1V1 战斗管理器（2 棋 / 5×3 格，继承 battle_base）
│     ├─ battle_team.gd    # 4V4 战斗管理器（8 棋 / 10×8 标准棋盘，星星得分制，继承 battle_base）
│     ├─ battle_unit.gd    # 棋子运行时（hp/energy/盾甲/速度/状态/资源池/掠夺限时锁/联机 rng）
│     ├─ hero_defs.gd      # 英雄登记表（龙王/剑舞/邪神/光雨/药师/追猎/孤狼/rapper/仙尊/灵虚/辛克莱）
│     ├─ skill.gd          # 技能运行时（冷却/耗能/per_game 整局限次/效果调用）
│     ├─ skill_data.gd     # ★ 技能元信息数据表（原 skill_effects 的 const DATA，667 行纯数据，2026-09-30 拆出）
│     ├─ skill_effects.gd  # 技能效果函数 EFFECTS（DATA 转发到 skill_data.gd；药师保底伤害、掠夺限时、联机同步随机）
│     ├─ hero_rules.gd     # ★ 英雄专属规则（虞美人恐惧/治疗光环/子体行动与生成，2026-09-30 从 battle_base 摘出）
│     ├─ ai.gd             # BattleAI（1V1/4V4 共用：plan_move / plan_skill，含大招追击射程）
│     ├─ battle_story.gd   # ★ 骑士线第一关战斗管理器（BattleStory extends BattleBase，7V10 双人护送关）
│     │                    #   ESCAPE_CELLS=最右4格 / 属性表2.0 / escort_qi 双目标 / QI_AUTO_EVERY=3
│     ├─ story_defs.gd     # ★ 剧情兵种登记表（昊/祁/大长老/战士/法师/宵/龙/熊，与 HeroDefs 隔离）
│     ├─ battle_tutorial.gd# ★ 新手教程战斗层（BattleTutorial extends Battle，只覆写 _make/_turn_ai）
│     ├─ tutorial_defs.gd  # ★ 教程兵种表（训练木桩 + 4 个教程角色，与 HeroDefs 隔离）
│     └─ grid_board.gd     # 通用格图 BFS/可达模块（4V4 / 剧情关均已接入）
├─ tests/                  # 回归测试（headless -s 运行）
│  ├─ combat_regression.gd    # 1V1 战斗层回归（113 断言，含药师/掠夺限时断言）
│  ├─ team4v4_regression.gd   # 4V4 战斗层回归（58 断言）
│  ├─ terrain_regression.gd   # 地形效果回归（7 项，含棋盘→terrain_id 同步链路）
│  ├─ story_battle_smoke.gd   # 剧情关（白灵殿）冒烟（28 断言，2026-09-13 新增）
│  ├─ damage_fx_smoke.gd      # 掉血特效 + 护盾血条回归（54 断言，2026-09-17 由 47 扩充）
│  ├─ board_zoom_smoke.gd     # 剧情关棋盘缩放回归（18 断言，2026-09-14 新增）
│  ├─ tutorial_smoke.gd       # 新手教程回归（156 断言，2026-09-28 新增；含端到端"走完动态步骤表"）
│  ├─ room_code_smoke.gd      # 房间号链路回归（14 断言，2026-09-30 新增；真拉起 Node 服务；无 Node 则 SKIP）
│  ├─ mainui_fit_smoke.gd     # 主菜单布局回归（27 断言，2026-10-04 新增；钉"点输入框卡死"这个 bug 类 + "新手教程归位/工具条尺寸"）
│  ├─ ui_design_smoke.gd      # 设计系统回归（128 断言，2026-10-04 新增 / 2026-10-05 加层级段；令牌锚点/WCAG 对比度/色阶单调/弹窗不透明/迁移完整性/主题/组件库/资源条四色/字体三档/bbcode 调色板/**弹层层级 z_index**）
│  ├─ duel_select_smoke.gd    # 1V1 选人界面布局（14 断言，2026-10-05 新增；「开始对战」完整可见 + 英雄区可滚动 + 内容撑高按钮不动）
│  ├─ cloud_auth_smoke.gd     # 云端登录态回归（116 断言，2026-10-04 建、2026-10-05 随「删本地账号」重写 + 加 F 段；`CloudSession` 语义 / 账号行两形态 + **界面禁用词扫描** / 启动分流 / **离线玩走本机匿名档** / **两份进度互不污染** / **忘记密码（契约+界面，F 段）** / **短信·邮箱双通道（契约+界面，G 段）**；会快照并还原存档）
│  ├─ ai_tier_bench.gd / hero_team_rank.gd   # AI 强度基准 / 英雄梯度排行
│  └─ *_tmp.gd               # 临时验证脚本（确定性/热座导航/联机重放等，可清理）
├─ maps/                   # 地图数据（白灵殿.json）
├─ tools/                  # map-editor.html(地图编辑器) / map_exe_app(打包版) / update_installer.sh
│  └─ room-service/        # ★ 房间号目录服务（2026-09-30）
│     ├─ server.js         #   Node 零依赖：POST /room 建房取号 · GET /room?code= 查地址
│     ├─ sms.js            #   阿里云「短信认证」(dypns) 零依赖封装（2026-10-09）
│     ├─ selftest.js       #   服务端自检（22 断言，自己拉起服务再跑）
│     └─ selftest_sms.js   #   短信通道自检（假 dypns + 假邮件网关，零真实短信；两档注册闸门）
├─ docs/                   # ★ 设计文档（2026-10-04 建，从根目录挪入 —— 见注意点 33）
│                          #   UI设计系统.md(规范) / UI设计系统_视觉稿.html(视觉稿)
│                          #   ★ 忘记密码_接口契约.md（2026-10-05：**两端都已实现并生产验证**，
│                          #     含服务端实现记录 / 残留风险 / 限流计数待修项）
│                          #   ★ 短信验证_接口契约.md（2026-10-09：注册/找回的**双通道**契约，
│                          #     渠道语义 / 四个接口 / 限流 / 回归红线）
├─ installer/战棋.iss      # Inno Setup 打包脚本
└─ _backup_doc_20260918/   # 2026-09-18 文档收敛前的旧的 README/CHANGELOG + 8 份单版说明（已带 .gdignore）
```

> 📌 **2026-09-18 文档收敛**：8 份单版/过程说明（`9.10整合版_说明.md`、`9.12_v2说明.md`、`9.12_v3说明.md`、
> `9.12整合版_说明.md`、`9.13_v2特效版_说明.md`、`9.13修复版_说明.md`、`9.13整合版_说明.md`、
> `白灵殿可玩化_说明.txt`）已删除，其独有内容并入本文件「附录 A」与 CHANGELOG。
> **包内文档收敛为 README + CHANGELOG 两份。**原文件存于 `_backup_doc_20260918/`。

## 二、进度与计划

- **已完成**：主菜单导航；1V1 可玩对局；4V4 星星得分制与可玩 UI；局内设置 + Bug 上报引导；4V4 蛇形选人页；AI 难度分层（简单/普通/困难）；**联机（输 4 位数字房间号即连，走自研反向隧道，双方无需任何配置，1V1/4V4 均可）**；**新手教程 + 交互式引导关**；**账号上云 + 自动更新**；**「墨金」UI 设计系统（色彩令牌化 + 三档字体）**；药师三技能修复；AI 大招释放修复；掠夺改限时锁技；追猎流炎飞弹整局限次；**「忘记密码」邮箱自助找回（2026-10-05 服务端两条接口上线，端到端可用）**；**主菜单「离线模式」改名「单机模式」**（消除与登录页「离线玩」的撞名）；**战术模型每日额度（未登录 3 次/设备·天 + IP 池 9 次兜底；登录后 10 次/账号·天）**；**短信验证通道（注册 + 找回密码，邮箱并列保留；2026-10-09 两端上线）**；**手机版更新修复（安卓改走浏览器下载 APK + 更新失败提示人话；安卓 versionCode 首次与游戏版本挂钩；2026-10-10）**；**服务端迁到自有域名 + HTTPS（`game.learnest.cn`，裸 IP 的 8787/8789 已关闭；2026-11-24）**。
- **进行中**：
  1. ✅ 战斗层 BattleTeam + 4V4 回归测试；
  2. ✅ 4V4 可玩交互 UI（TeamDuel + 棋盘控件 + 菜单解锁 PVE/热座）；
  3. ✅ 局内设置 + Bug 上报引导；
  4. ✅ 4V4 蛇形选人页；
  5. ✅ AI 难度分层 + PVE 难度入口；
  6. ✅ 联机系统 MVP（含断线判负、状态漂移护栏、同步种子确定性 RNG）；
  7. 🚧 最高难度＝豆包战术模型融合（协议/消费/后端选择已完成，网络层真机联调待验证）；
  8. ⏳ 数值平衡观察；公网真实双机对局持续观察（cpolar 免费隧道中转）；
  9. ✅ **骑士线第一关「白灵殿」难度根因已解决**：昊/祁出生点东移至 `(0,1)`/`(0,2)`，
     红方追击在几何上成立（见「零之零」与「附录 A.3.3」几何推导表）。
     ⚠️ **但难度手感需真机重新评估**（仿真：差 AI 场景蓝方胜率 1.0%，完美护送 100.0%）。
- **后续计划**：
  - **白灵殿难度手感实测**（只改 `maps/白灵殿.json` 的 `spawns`，**不需改代码**，调参速查见附录 A.3.5）；
  - **拆障机制可触发性重测**（9.12_v2 时代实测「50 局只拆成功 3 次」，昊移位后路径已穿过障碍带，但**尚未重测**）；
  - **AI 回合特效回放队列**（解决「同帧结算」，属设计决策待拍板，见附录 A.3.7）；
  - 4V4 数值平衡（护甲 vs 单体伤 1~3 的僵局问题，含暗影刺打甲1+英雄=0 伤）；
  - 地形障碍接入 grid_board；李太白属性/虞美人母体子体完整规则等设计者确认后微调。
- **2026-10-05 两处 UI 修复：局内弹层被棋子盖住 + 1V1 选人界面按钮被裁（已随 10.5.0 发包，纯 UI）**：
  ① **「人物显示在设置弹窗上面」** —— 根因是 Godot 同层**先比 `z_index`、再比树顺序**，
     棋子自带 z_index（名字 120 / 特效 110 / 骨骼部件由数据给）而弹层默认 0。
     令牌层新增 `Z_UNIT_FX / Z_UNIT_LABEL / Z_OVERLAY`，**12 处**改走令牌（含三处共用的局内设置）。
  ② **「1v1 选人界面开始对战按钮没显示全」** —— 选人层原是全屏直排 VBox，11 英雄 6 行
     约 650px，基准 720 只剩 40px 余量，窗口稍矮就挤出视口。按用户建议
     **英雄卡缩一档 + 英雄区套 `ScrollContainer`（纵向可滚）**，按钮钉在底部不再被挤。
     ⚠️ 对照：**4V4 蛇形选人早就有 ScrollContainer**，只有 1V1 漏了 —— 是漏做，不是取舍。
  验证：新增 `tests/duel_select_smoke.gd`（14 断言，含"内容撑高 600px 按钮位置不变"）；
  `ui_design_smoke` 110 → **128**；五场景各 0 真实错误。
- **2026-10-05 删除「本地账号」（未发包，数据层重构）**：客户要求「**不要有本地账号这个东西！
  离线玩相当于玩 0 进度原始账号**」。整套删掉：`scripts/save/account_store.gd`（202 行）+
  `user://accounts.json` + 登录页的「选择已有账号」按钮与弹窗 + 本机建号回调。
  新增 `scripts/save/progress_store.gd`（`ProgressStore`）—— 一份**匿名本机进度**
  （`user://progress.json`：只有 `tier`/`tutorial_done`/`tutorial_hero`，**没有名字、没有 id**）。
  **账号只剩云端账号一种**；`Global.current_account` 拆成 `cloud_account` 与 `player_progress`。
  **两份进度互不污染**：登录中读写云端（断网靠 `cloud_session.json` 里的 `account.progress` 兜底），
  离线玩读写本机 —— 于是「登录后进度跟着账号走」与「离线玩是 0 进度」同时成立。
  账号行只剩两种形态：`云端账号：…`+「退出登录」／`离线游玩（进度只在这台电脑）`+「登录云端」；
  **界面永不出现「本机账号 / 未登录」**（已写成禁用词扫描断言）。
  启动分流改由 `_initial_panel()` 决定（有登录态或有离线进度 → 主菜单；否则登录页），
  且**必须在 `_setup_cloud()` 之后**跑（原来顺序反了，正是"已登录却显示未登录"的根源）。
  回归：`cloud_auth_smoke` 重写 **45 断言**（含"界面禁用词扫描"与"两份进度隔离"），
  `tutorial_smoke` **156 断言**。详见 CHANGELOG `[10.5 删除「本地账号」]` 段。
- **2026-10-05 主菜单账号区调整（未发包，纯 UI）**：① 「新手教程」从主按钮列并入下方「图鉴 / 介绍」
  **工具条**（该条整体收小到 158×44、字号 16，5 个一行共 838px），主按钮列只剩「开始游戏 / 退出」——
  教程是**引导入口**不是主流程，和查资料同属次级，不该跟主 CTA 争权重；
  ② 「选择已有账号」由**内联列表**改为**按钮 + 弹窗**（账号按钮原来直接铺在登录页上，
  账号一多就把页面撑长、还跟「登录」抢注意力；现在登录页永远是「昵称 → 密码 → 登录」一条直线，
  数量写在按钮上如「选择已有账号（5）」）。弹层用**不透明**底、当前账号带「（当前）」、
  **三种关闭**（ESC / 点遮罩 / 「取消」），且切面板时自动收起。
  回归：`mainui_fit_smoke` **27 断言**（新增工具条归位段）、`cloud_auth_smoke` **45 断言**
  （新增弹窗段）。**并纠正了一处会造成误解的命名与文案**：主菜单账号行不再写「未登录」
  （账号与云端登录是**两层** —— 退出登录 / 选「离线玩」只影响"连不连云端"，
  本机账号、水平、教程进度都在），前缀改成 **`本机账号：` / `云端账号：`**；
  登录页那颗「离线模式（不登录）」**改名「离线玩（不登录云端）」** ——
  它原先与主菜单的**玩法**「离线模式」同名，玩家会以为"点了就不要账号了"。
  ⚠️ 两个「离线」是**不同维度**：主菜单那个是玩法（vs 联机 / 剧情），登录页那个是账号。
- **2026-10-04 设计系统「墨金」令牌化（已随 10.4.1 发包，纯视觉层，无机制改动）**：把 UI 层 **373 处硬编码颜色
  / 188 种不同值**收敛成一套设计系统。新增 `scripts/ui/ui_design.gd`（令牌）+ `ui_theme.gd`（全局 Theme
  + 组件库），**226 处字面量令牌化、覆盖 21 个界面脚本**。
  · 迁移动线：令牌值**全部锚定迁移前的历史值** —— 155 处**逐像素不变**，71 处为单通道 ≤3% 的归并
    （ΔE &lt; 1，低于 JND）。**视频素材 12 个一字未动**（含 `menu_bg.ogv`、英雄视频、剧情开场）。
  · 顺带修掉两处真问题：`_make_edit` **零样式**且聚焦看不出差别（现补墨底描边 + **金环焦点态**）；
    `_apply_node_sizes` 只处理 `Label`/`Button` → **LineEdit 的 `fz` 从未生效**（已补）。
  · 补上工程原先**完全缺失**的焦点环（WCAG 2.4.7）与 Tooltip / PopupMenu / 滚动条 / 进度条皮肤。
  · 新增 `tests/ui_design_smoke.gd`（**110 断言**）+ `docs/UI设计系统.md` + `docs/UI设计系统_视觉稿.html`。
  · **同日第二轮**：棋子头顶迷你条重做为「生命/护盾/能量**三条各自独立**、一色一义」
    （原先生命与盾挤在一条里只靠颜色分，而能量借用的还是**敌方阵营蓝**）。
  · **同日第三轮（全产品统一深色 + 字体三档）**：作废「图鉴/关卡/故事/详情」那套**浅色羊皮纸子主题**
    （米白底 + 奶油按钮 + 深墨字，在视频背景菜单上像另一个产品），全转深色玻璃；
    **隐藏最深的坑**是那些面板正文的 **bbcode 硬编码深色**（`#2e6b3c` 等 48 处）会变「深底深字」，
    已换成 `UiDesign.MD_*` 调色板并加了扫描式断言。字体升三档：
    **毛笔主视觉**（≥60px）/ **思源宋体小标题**（≥22px）/ **思源黑体正文**（可变字重，按钮 Medium）。
    字体共 34MB 随包（`assets/fonts/`，OFL，**必须随包附 LICENSE**）。
  回归全绿（combat 113 / team4v4 58 / terrain 7 / story 28 / damage_fx 54 / board_zoom 18 /
  tutorial 177 / room_code 14 / mainui_fit 17 / **ui_design 96**）+ **十场景冒烟 0 错误**。
  备份在 `C:\Users\Caobo\WorkBuddy\2026-09-18-11-32-18\_backup_ui1004tokens\`（**故意放在工程树之外**，
  见注意点 32）。规矩见注意点 31。
- **2026-10-04 账号上云 + 自动更新（已随 10.4.1 全量包发包）**：账号从「只存本机」升级为**云端账号**，
  并接上**自动更新检测**；新增「**离线模式**」，不登录照样玩。
  · 云服务 `tools/cloud-service/`（零依赖 Node，只用内置模块）部署在自有云服务器：
    **端口 8789**，systemd 单元 `zhanqi-cloud`。一个服务三件事 ——
    更新清单 `GET /version.json` / 账号 `POST /register` `/login` `GET /me` / 进度 `POST /progress`。
  · **账号存服务器本地**（用户 2026-10-04 定）：一人一个 JSON，按 uid 前 2 位分片
    （`accounts/7f/7fbf….json`）。实测单账号紧凑 JSON 仅 **316 字节**。
    昵称唯一性靠 `writeFileSync(..., {flag:'wx'})` 的**原子创建**（POSIX `O_CREAT|O_EXCL`），
    **不是"先查再写"** —— 后者有 TOCTOU 竞态，两个请求会互相覆盖。
    密码 `scrypt` 加盐哈希；token 是**无状态 HMAC**（服务端不存 token 表，重启不影响）；
    响应**永不返回 salt/hash**；不存在的账号与错密码同样 401（不泄漏存在性）。
  · 客户端新增：`scripts/net/update_check.gd`（只拉约 1 KB 清单比对版本号；
    🔴 **检查失败一律放行**，绝不挡玩家进游戏）· `scripts/net/auto_update.gd`
    （2026-10-04 晚追加：**自动下载 → 解压 → 写更新脚本**；玩家点「重启更新」后由
    `_update/apply_update.bat` 在主程序退出后替换 exe 再重启 —— 照搬乱世五方的做法）·
    `scripts/net/cloud_api.gd` · `scripts/save/cloud_session.gd`（**只存 token，不存密码**）。
    `project.godot` 新增 `config/version` 作为**版本号唯一来源**。
  · 「谁在玩」面板：昵称 + 密码 + 「登录」「注册新账号」「**离线模式**」。
    **离线模式 = 不登录不联网，功能一点不缩水**，只是进度只留在这台电脑。
  · 发版链 `tools/release_desktop.js`：导出 → Inno 打包 → 传 OSS → 生成 version.json
    （并自动把版本号同步进 `installer/战棋.iss`，杜绝"包里 9.20、文件名 10.4"的漂移）。
  · **自动更新包另有一条链**（2026-10-04 晚）：`tools/cloud-service/push_update_pkg.js <build/战棋.exe> <版本> --clean-old`
    → Node **手写 zip 容器**（零依赖，本机/服务器都能跑）压 `build/战棋.exe`（211 MB → 约 130 MB）
    → OSS `game/zhanqi-update-v{ver}.zip` → 直链填进 `version.json` 的 **`update.win64`**。
    ⚠️ **`downloads.win64`（安装包 .exe）与 `update.win64`（更新包 .zip）是两个东西**：
    前者给玩家手动下载安装，后者给客户端自动替换 —— 填混了客户端会拿安装包当 zip 解，必报"压缩包打不开"。
  · **账号冷备到 OSS**：`backup_accounts.js` / `restore_accounts.js` +
    systemd timer `zhanqi-backup.timer`（**每天 04:30**，保留最近 7 份，
    `Persistent=true` 错过会补跑）。恢复**不覆盖**原目录（先改名 `accounts.bak-*` 留住）。
    已实测：造 3 个账号 → 备份 → 删库 → 恢复 → 3 个账号原样回来。
  · **战术模型也改由云端代调**（2026-10-04）：`scripts/ai/ai_key.bin` **已删除** ——
    原先 Key 只是 XOR+base64 混淆后随客户端分发，拿到客户端就能提取出来。
    现在客户端只发战局卷子；Key 只存服务器 `/opt/llm-gateway/providers.json`（600，**唯一持有者**），
    `zhanqi-cloud` 只做**转发**（`127.0.0.1:8790`，本机回环、iptables 只放 lo）。
    接口不要求登录（离线模式也要能玩困难模式），且**战棋用途不按 IP 限流**（只计数）；
    兜底是**整机日熔断 2 万次/天**（对全部用途生效；正常用量约 160 次/天，不会误伤）；
    老师工具（语文/数学资料整理系统）**每 IP 每天 20 次**（它们没有账号体系）。
    **任何失败都回退本地 AI**，绝不阻断开局。
    ⚠️ 不限流的代价：8789 的战棋入口是不限额的公开模型入口（拿不到 Key，但会烧额度）。
    **缓解手段 = 服务端角色约束**（借《乱世五方》的做法）：网关给 `doubao` 配了一行
    `systemPrompt`，作为第一条 system 消息注入 —— 该入口**只能问战局决策**，
    非战局请求一律回 `{"error":"not_a_battle"}`。于是白嫖者**拿不到文章/代码/问答**，
    **账号被封的风险基本消除**；合法卷子的输出格式**实测没变**。
    （仍管不住"调多少次"，那要靠账号或全局熔断。）
  · 验证：云服务自检 **31/0**（含★并发同名注册恰好一个成功；★4 条配额回归：老师工具
    20/天·5/分、战棋连打 40 次不被限流、伪造 XFF 无法扩充配额 —— 自检把转发目标指向死端口，
    **不烧额度**）· 网关自检 **26/0**（含★服务端约束不影响合法卷子的 JSON 输出、
    ★非战局请求被回绝、★老师工具/乱世没被误加约束、
    ★整机熔断对"不按 IP 限流"的战棋用途同样生效）· 公网链路 **11/0** ·
    客户端探针 **25/0**（含★另一客户端读到同样进度 = 云端持久化生效）·
    战术模型探针 **9/0**（★真实战局走通云端→豆包，3.1s，客户端无 Key）·
    **配额实测**（2026-10-04 晚）：战棋并发 **40/40 全放行**、伪造 XFF 无法绕过
    老师工具 20/天（第 6 次 429）· 既有回归全绿。
  · 验证：云服务自检 **27/0**（含★并发同名注册恰好一个成功）· 公网链路 **11/0** ·
    客户端探针 **25/0**（含★另一客户端读到同样进度 = 云端持久化生效）·
    战术模型探针 **9/0**（★真实战局走通云端→豆包，3.1s，客户端无 Key）· 既有回归全绿。
  ⚠️ **明文 HTTP，无 TLS** —— 密码在链路上是明文，内测可接受，**公开运营前必须上 HTTPS**
    （签证书需要**域名**，裸 IP 签不了；有了域名用 Let's Encrypt 免费签，代码几乎不用改）。
  ⚠️ **磁盘按 4 KB 块分配**：316 字节的账号文件实占 4 KB（**放大 13 倍**）→
  100 万账号 ≈ **3.8 GB**，1000 万 ≈ 38 GB。当前剩 34 GB，约撑到 800 万，到那规模要换 SQLite。
  详见 CHANGELOG `[10.4 账号上云 + 自动更新]` 段。
- **2026-10-03 联机上云·阶段1（已随 10.4.x 发包）**：房间号目录服务部署到**自有阿里云 ECS**
  （`39.105.223.8:8787`，`/opt/room-service`，systemd 单元 `room-service.service`，安全组已放行 8787）——
  **玩家不再需要在自己电脑上跑服务**。`server.js` 一行未改；`Global.net_room_service` 与
  `NetRoomCode.DEFAULT_SERVICE` 的默认值改指云端（本地自测可临时改回 `127.0.0.1:8787`）。
  新增 `tests/_probes/net_cloud_probe.gd`（对云端跑真实链路，5 断言）。
  验证：`selftest.js` 22/0 + 云端核心链路 18/0 + Godot→云端 5/0 + 既有回归全绿。
  **阶段2（替代 cpolar）选型已定并实测**：推荐**「反向隧道 + 房主侧 GDScript 桥接器」** ——
  战棋本来就是 1V1 单连接，交接文档担心的"多客户端"难点不成立；4 进程实验已跑通
  「房主 NAT 后主动连出 → 中继配对 → 纯 GDScript 桥接 → Godot server 认到 peer（520 字节双向转发）」。
  **阶段2（替代 cpolar）的实现见下一条。** 详见 CHANGELOG `[10.03 联机上云]` 段。
- **2026-10-04 房间号 11 位 → 4 位（已随 10.4.1 发包）**：`NetRoomCode.CODE_LEN` 与服务端 `CODE_LEN` 同步改 **4**，
  玩家报号不用再分段。自测：`selftest.js` **22/22** + `room_code_smoke.gd` **14/14** 全绿。
  ✅ **云端 `/opt/room-service` 已于 2026-10-04 重新部署完成**（旧版是 11 位）；**11 位的旧客户端无法加入房间**
  （本地长度校验会先挡下），已发出去的安装包 / APK 需同步更新。
  房间号空间降到 1 万（TTL 600s 内活跃房间数百以内无碰撞风险，服务端仍 200 次重试兜底）。
- **2026-10-04 自动更新上线（已随 10.4.1 发包）**：从"只提示"升级为**自动下载并替换** ——
  新增 `scripts/net/auto_update.gd`（下载 → 解压 → 写 `.bat` → 重启生效）与发版脚本
  `tools/cloud-service/push_update_pkg.js`（Node 手写 zip，零依赖）；`main_ui` 更新页加进度条 +
  「重启更新」。⚠️ **安装目录随之变更**：`installer/战棋.iss` 从 `{autopf}\战棋`（Program Files）
  改为 **`{localappdata}\Programs\战棋`** —— 否则普通进程对自己的目录没有写权限，自动替换必然失败；
  `PrivilegesRequired=admin` **不变**（免杀软加固的证书要写 HKLM 根证书库）。
  验证：`tests/update_smoke.gd` **19/19**。
- **2026-10-03 联机上云·阶段2 完成（已随 10.4.x 发包）**：公网建房**不再依赖 cpolar** ——
  新增自研反向隧道：服务端 `tools/relay-service/relay-service.js`（房主入口 19001，
  公网端口池 20000-20099 **按需分配**）+ 房主侧 `scripts/net/net_relay_host.gd`
  （**纯 GDScript** 的 `StreamPeerTCP` 桥接器，房主**什么都不用装**）。
  `Global.net_transport` 默认改为 `"ws"`，于是**建房拿号、对方输号即连，不区分网络环境**。
  云端实跑验证：房主 `★ RELAY ADDR = 39.105.223.8:20000` → `★ ROOM CODE = 85358467640`
  → 玩家输号 → 查到地址 → 连上 → 房主 `★ PEER_CONNECTED`。
  加入者与房主的**对局/同步逻辑零改动**（server 以为只是被一个本地客户端连上了）。
  服务器上 `lswf`(3000) / `room-service`(8787) / `relay-service`(19001) 三者共存。
  ⚠️ 仍差**两台不同网络的真机**实连验证（本机单机做不到）。
- **2026-09-30 结构收敛·第二批（已随 10.4.x 发包，无机制改动）**：
  ① `skill_effects.gd` 里 667 行纯数据表拆到 `scripts/combat/skill_data.gd`（`SkillData`），
  原文件 2560 → 1895 行，**`SkillEffects.DATA` 的调用点一处未改**；
  ② 新增 `scripts/ui/battle_screen.gd`（`BattleScreen`）：`duel.gd` / `team_duel.gd` 逐字重复的
  `_my_team` / `_can_input` / `_op_move` / `_op_done` 与近乎相同的 `_op_cast` 上提到基类，
  两个界面各只留一个 `_cast_via()` 覆写点（三个模式的 `human_cast` 签名本就不同）；
  ③ 过程中撞出并修掉一个**真实编译 bug**：`team_duel.gd` 的 `var mx := _battle.max_targets_of(...)`
  在 `_battle` 类型由 `BattleTeam` 收紧为 `BattleBase` 后报 `Cannot infer the type of "mx"` ——
  根因是 `max_targets_of()` 只写在 `BattleTeam` / `BattleStory`（两份逐字相同）而基类没有，
  已上提到 `BattleBase` 并删掉那两份重复。
  ⚠️ **这个错只有场景冒烟抓得到**：`--check-only` 对引用 autoload 的 UI 脚本会误报（见注意点 29）。
  ④ `Global.rules_text()`（26 行展示文案）移到 `scripts/ui/rules_text.gd`（`RulesText.text()`），
  `global.gd` 56 → 29 行；
  ⑤ 两处**配色表**收敛（`team_board.gd` 的 `TERRAIN_COL` → 转发 `Terrain.COLORS`；
  `unit_token.gd` / `team_board.gd` 的两份 `_status_color` → `SkillEffects.status_color()`，
  差异只在已废弃的 `burn2` 上，**零视觉变化**）+ `battle_unit.gd` 的 28 个成员变量
  从"夹在函数之间"集中到头部变量区（纯文本搬移，零语义变化）。
  回归全绿（combat 113 / team4v4 58 / terrain 7 / story 18 / damage_fx 54 / board_zoom 18 / tutorial 177 / room_code 14）
  + 五场景冒烟 0 错误。备份在 `_backup_0930skilldata/`。
  ⚠️ **同批评估后决定不动的**：三个界面的 `_state_bbcode` / `_refresh_log` 是**有意分叉**的
  （4V4 状态栏简化 + 日志配色两档），强行合并会改变视觉行为；`BattleUnit` 拆组件、`main_ui` 拆面板、
  棋盘三套统一属需人目视的 UI 级重构，均留待有真机验证条件时再做（详见 CHANGELOG 该段"五"）。
- **2026-09-30 结构收敛（已随 10.4.x 发包，无机制改动）**：把 UI 工具函数 `_style_btn` / `_panel_style` / `_make_bar`
  从 4 个界面文件的 **15 份重复实现**收敛为 `scripts/ui/ui_kit.gd` 唯一实现
  （各文件留一行转发壳，**调用点零改动**，UI 布局无变化）；
  把虞美人专属规则（恐惧发作 / 治疗光环 / 子体暗影刺 / 子体生成 / 母子换位）
  从所有模式共享的 `BattleBase` 摘到 `scripts/combat/hero_rules.gd`（**20+ 处调用点不变**）；
  `_hd` / `_se` 三处重复 `load` 改为基类 `preload` 常量；顺带删掉 `human_move()` 里重复的 `_check_fear` 调用；
  `tests/` 的 13 个临时探针移入 `tests/_probes/`，清掉 3 个孤儿 `.uid`。
  回归全绿（combat 113 / team4v4 58 / terrain 7 / story 18 / damage_fx 54 / board_zoom 18 / tutorial 177 / room_code 14）
  + 五场景冒烟 0 错误。**新增脚本必须跑一次 `--import`** 注册进 `.godot/global_script_class_cache.cfg`，
  否则报 `Identifier "UiKit" not declared in the current scope`（详见注意点 29）。备份在 `_backup_0930struct/`。
- **2026-09-30 新增（房间号联机）**：联机不再让玩家输 IP/端口 ——
  建房拿 **4 位数字房间号**，对方**输号即连**（输入框回车直接连）。
  新增零依赖 Node 目录服务 `tools/room-service/server.js`（只做 `码 → 地址` 翻译，
  **不碰游戏状态、不裁决、不转发对局流量**）+ Godot 客户端 `scripts/net/net_roomcode.gd`（异步 HTTPRequest）。
  **局域网与公网两种模式都覆盖**（局域网上报内网地址；公网等 cpolar 隧道就绪后上报公网地址），
  并**保留"直接填地址"作为兜底**。回归：`selftest.js`（22 断言）+ `tests/room_code_smoke.gd`（14 断言）。
  ⚠️ 房间号是**口令语义不是密码语义**；`Global.net_room_service` 需按部署点改；
  联机这一块**还没拿两台真机跑过**（只在单机验证了链路）。详见 CHANGELOG `[9.30]` 段。
- **2026-09-28 ~ 09-30 新增（新手教程 + 本地账号）**：主菜单开始界面新增「新手教程」入口；
  新增**本地账号系统**（`AccountStore`，`user://accounts.json`，首个本地存档，损坏自动降级）；
  首次启动无账号 → 自动走「谁在玩 → 你的水平怎么样（新手 / 玩过战棋 / 老手）」→ 选教程角色 → 进**交互式引导关**。
  引导关继承 1V1 的 `Battle`（**只覆写 `_make` / `_turn_ai`，战斗规则零改动**）；
  步骤表**按所选英雄的实际技能数据动态组装**（基础 4 步 + 机制步 + 收尾 3 步）：
  元晶龙王 10 步 / 光雨 10 步 / 剑舞 11 步 / 追猎 12 步（机制步随英雄变化，见 CHANGELOG 的 `[9.28–9.29]` 段表格）。
  高亮用**遮罩挖洞**（棋盘区压暗、只亮当前该点的控件），步骤标题的圈码运行时生成。
  教程棋盘铺了**森林 / 水域**地形（受击 ×0.8、移出耗能、水域禁位移），且**实测生效**（不是只摆了几格颜色）。
  完成页有「去实战一局 →」直接进 1V1 简单 PVE（学完就能上手）。
  新增 `tests/tutorial_smoke.gd`（156 断言，含端到端"真建场景走完动态步骤表" + 地形实测）。
  ⚠️ 两条设计铁律与"未做项"见 CHANGELOG 的 `[9.28–9.29]` 段。
- **2026-09-17 修复（已随 9.18整合版 发包）**：侧栏生命条数字**永远显示 `1.00 / 1.00`**（用户实报）。
  根因：9.13_v2 换 `HpShieldBar` 时三处界面各写一份 `_update_bar`，只改了其中一部分分支，
  漏掉写数字标签那段。修法：抽成 `DamageFx.update_bar()` 单一实现，三处转调（详见注意点 24）。
- **2026-09-14 新增（已随 9.18整合版 发包）**：剧情关棋盘**双指捏合缩放**（`story_battle_board.gd`）
  + `tests/board_zoom_smoke.gd`（18 断言）。
- **2026-09-08 修复**：「流炎飞弹」显示名统一（原代码写作「流星飞弹」，已改名）；1V1 对局血条/能量条浮点截断修复（duel.gd _update_bar 由 int/clampi 改为 float/clampf，与 4V4 对齐）。
- **2026-09-07 更新**：新增李太白、虞美人（含蔓延子体/恐惧/暗影刺/互助反击/母体阵亡清子体），14 英雄全实装。
- **2026-09-06 更新**：新英雄流萤（双形态）；菱形射程系统；理智栏+状态面板+状态徽章+右键查看棋子；全量数值浮点化（两位小数）；修复重大 bug（回合末结算失效/吞技能/理智深跌/图鉴无法退出/4V4 棋盘收窄为 8×8+出生格）。

## 三、运行与测试

> ⚠️ **路径必须用 Windows 形式**（`--path C:/Users/.../godot-chess-tactics`）。
> 用 MSYS 形式 `--path /c/Users/...` 会报 `Invalid project path specified`。

```bash
# 首次（或换机器后）必须先导入一次资源，否则会误报
#   Cannot find type "BattleUnit" / Failed loading resource: ...wav.sample
# —— 那是缺 .godot 缓存，不是 bug
godot --headless --path . --import

# 冒烟：不报 ERROR 即通过
godot --headless --path . --quit-after 2

# 十一道回归（退出码 0=全过，1=有失败）
godot --headless --path . -s res://tests/combat_regression.gd      # 1V1   113 断言
godot --headless --path . -s res://tests/team4v4_regression.gd     # 4V4   58 断言
godot --headless --path . -s res://tests/terrain_regression.gd     # 地形  7 项
godot --headless --path . -s res://tests/story_battle_smoke.gd     # 剧情关 28 断言
godot --headless --path . -s res://tests/damage_fx_smoke.gd        # 特效+盾条 54 断言
godot --headless --path . -s res://tests/board_zoom_smoke.gd       # 棋盘缩放 18 断言
godot --headless --path . -s res://tests/tutorial_smoke.gd         # 新手教程 156 断言
godot --headless --path . -s res://tests/room_code_smoke.gd        # 房间号链路 14 断言（需 node）
godot --headless --path . -s res://tests/mainui_fit_smoke.gd       # 主菜单布局 27 断言（_fit 幂等 + 工具条归位）
godot --headless --path . -s res://tests/ui_design_smoke.gd        # 设计系统 128 断言（改颜色/字号/字体/bbcode 色/**弹层层级**都要跑）
godot --headless --path . -s res://tests/duel_select_smoke.gd      # 1V1 选人界面 14 断言（改选人层布局/英雄数量都要跑）
godot --headless --path . -s res://tests/cloud_auth_smoke.gd       # 云端登录态 116 断言（改登录/退出/会话缓存/账号行/离线进度/**忘记密码**都要跑）
godot --headless --path . -s res://tests/update_smoke.gd           # 自动更新器 19 断言（改 update_check/auto_update/main_ui 更新页要跑）

# 剧情关场景级加载（查 UI 脚本编译错误，这类问题 -s 脚本测不出来）
godot --headless --path . res://scenes/StoryBattle.tscn --quit-after 40

# 逐文件语法检查（能抓出「没被任何场景加载过」的脚本里的编译错误）
godot --headless --path . --check-only -s res://scripts/ui/xxx.gd
```

> ⚠️ `--check-only -s` 会对 autoload（`Global` / `Net` / `Sfx`）误报
> `Identifier not found`。这 3 个名字的报错是**假阳性**，属正常，不要去"修"。

## 四、注意点

1. **版本命名与多人并行**：主程序压缩包用 `日期+版本号`（如 `9.05代码_v1.zip`），禁止无声覆盖旧版本；改主程序前先备份。
   ⚠️ **本项目多人并行开发，同日多版本经常互为平行线**（版本号只是"当天第几次发包"的序号，**不代表迭代关系**）。
   因此：
   - 发包时**建议在备注里写明基线**（如 `9.13代码_v4_某某_基线9.12v1`），便于他人判断是否绕开了自己的改动；
   - **当日多版本若非迭代关系，必须合并出「当日整合版」再上传仓库**，整合版作为当天对外唯一版本；
   - 单独的功能包留在网盘作过程记录即可，**不直接推仓库**（否则会丢别的线的内容）。
2. **回合结构（1V1 与 4V4 一致）**：每棋每回合 = 1 移动权（8 方向 1 格）+ 1 技能权（先移后放、可放弃）；同回合内所有存活棋按实时速度从高到低依次行动；速度变化立即影响后续顺序。
3. **出生与棋盘**：1V1 = 3×3 主区 + 左右翼各 1 出生格；4V4 = 8×8 主区（x1..8,y1..8）+ 左翼红方 4 出生（x0,y3..6）/ 右翼蓝方 4 出生（x9,y3..6）。棋盘格 x0..9/y1..8 均可通行。
4. **4V4 已知边界**：技能目标暂统一"单目标"（AI 选最近、玩家点选）；范围/多目标后续声明式补。**数值未平衡**：英雄普伤 1~3 vs 护甲 1~3，护甲为固定减伤，AI 全自动局常出现"互相打不动→80 回合僵局"，属已知现象。
5. **伤害口径**：普伤=盾先吸→甲减免→扣血；真伤走 `lose_hp` 无视盾甲；百分比伤害未标真伤按普伤结算。
6. 英雄 hp 为小数值制（6~10），盾/甲/伤害同样小数值，调数值时注意整体比例。
7. **最高难度（困难·战术模型）**：豆包每回合做「选择题」（A进攻/B稳守/C保命）+ 填「战术倾向」（focus/posture/protect）；规则 AI 据此调权重后精确执行，失败自动回退本地 hard。API Key 以混淆加密随包（ai_key.bin），仅本地解密；离线/断网时困难自动用本地 AI。
8. **联机依赖**：公网建房需 cpolar（免安装版可用）—— 将 `cpolar.exe` 放游戏同目录 `cpolar/` 下，authtoken 配置于 `~/.cpolar/cpolar.yml`；**局域网直连与加入方零依赖**。
9. **联机确定性**：效果函数内随机一律走 `user.rng`（战斗层注入的同步 RNG），`null` 时回退全局随机（单机旧路径）。新增效果函数务必沿用 `_sync_randf` / `_sync_randi`，否则联机双方会状态漂移。
10. **数值全为浮点（两位小数）**：hp/能量/盾/甲/伤害均为 float，显示用 `%.2f`。⚠️ GDScript 的 `mini/maxi/clampi` 是整数版，传 float 会**静默截断**，数值比较一律用 `minf/maxf/clampf`。
11. **射程形状**：默认切比雪夫（斜对角=1）；声明式菱形射程 `range_shape: "diamond"`（曼哈顿距离，如流萤超新星 13 格）；多目标 `max_targets`（如流炎飞弹 2、超新星 3）。
12. **流萤双形态**：技能组动态替换见 `skill_effects.gd` 的 `_liuying_enter_full/_exit_full/_tick_attack`；新增"形态切换型"英雄照此范式。控制类负面一律走 `BattleUnit.try_control(flag)`（接入 40% 免控等抵抗机制），不要直接 `add_flag`。
13. **右键棋子**：弹 `UnitInfoPopup`（scripts/ui/unit_info_popup.gd），1V1/4V4 共用。
14. **剧情关（骑士线）逃生区与胜利条件**：逃生区是**显式格列表** `BattleStory.ESCAPE_CELLS`
    （当前 `x=18, y=0~3` 共 4 格），**不再是 `ESCAPE_X` 整列带**——改逃生区请直接改这个数组，
    并确认每格在 `maps/白灵殿.json` 中可通行（`_terrain_ok()` 会过滤掉不可通行的格）。
15. **剧情关双人护送**：胜负判定在 `BattleStory._check_win()` / `_is_escorted()`；
    `protect_target`=昊、`escort_qi`=祁，两者**任一死亡立即判负**，两者**都到位才判胜**。
    新增护送目标时，记得同时更新 `scripts/ui/story_battle.gd` 的 `_refresh_goal()` 与
    `story_battle_board.gd` 的 `set_battle_units()`（金环数量）。
16. **改单位位置一律走 `_place(u, c)`**（落位 + 同步地形），**不要直接写 `u.cell = c`** ——
    否则地形 id 会残留，出现「站进森林却按空地算伤害」的**静默错算**（9.13_v1 修的就是这个）。
17. **备份目录必须放 `.gdignore`**：Godot 递归扫全工程，备份里的脚本副本会因同名 `class_name`
    导致主菜单起不来；更阴险的是测试会得到**假绿 `PASS 0 / FAIL 0`**（测试脚本自己没编译成功）。
    含 `.gdignore` 的目录对资源系统完全不可见，**不需要删文件**。详见「附录 A.4」。
18. **战斗层伤害出口只有两处**（`damaged` / `hp_drained` 信号），`lose_hp()` 是全工程唯一写 hp 的地方。
    **新增伤害路径必须走这两处**，否则特效会漏（契约细节见「附录 A.1.1」）。
19. **表现层两条铁律**：不读写战斗状态、不用随机数（联机同步只认战斗层，否则状态漂移）；
    空闲时 `set_process(false)`。特效三个已踩过的坑见「附录 A.1.3」。
20. **改代码前先读本文件末尾的「附录 A：设计约束与防坑」** ——
    里面是设计约束、防坑清单、遗留问题与调参方法，CHANGELOG 不含这些。
21. **打包纪律**：每次打包**必须**更新 `README.md`（本文件的「进度与计划 / 注意点 / 附录 A / **头部版本身份段**」）
    与 `CHANGELOG.md`，使其与当下情况一致；**未更新视为打包未完成**。
    ⚠️ **禁止用「新建一份 `9.xx说明.md`」来记录本版改动** —— 那正是历史上 8 份说明文件的来源，
    已于 2026-09-18 全部删除并合并。**一个版本 = CHANGELOG 里的一段。**规则见文末「文档纪律」段。
    📦 **包内容清单（2026-09-18 立 —— 照本清单打，不要再靠"对比上一版 zip"反推）**：
    - **收**：根目录 5 份 —— `README.md` / `CHANGELOG.md` / `.gitignore` / `project.godot` / `export_presets.cfg`；
      目录 —— `art/ assets/ data/ docs/ installer/ maps/ scenes/ scripts/ story/ tests/ tools/`；
      **带上 `.import`**（Godot 靠它识别资源，`.gitignore` 虽忽略但**包内必须有**）；
      顶层统一套一个 `godot-chess-tactics/` 文件夹。
    - **不收**：`.godot/` `build/` `Godot/` `.git/` `.workbuddy/`、**所有 `_backup*` 备份目录**（含 `_backup_doc_20260918/`，它是旧文档存档，只留在工程里，不进包）。
    - **不收生成物 / 安装包**：`installer/*.exe`（其中一个就 138MB）、`tools/*.exe`、`*.log *.tmp`。
      `installer/` **只收 3 个文件**：`战棋.iss` + `战棋-使用说明.txt` + `战棋证书.cer`。
    - ⚠️ **不收素材与中间产物**：`story/video/*.mp4`（`.ogv` 的源文件）、`story/video/frames/`（AI 生成视频用的参考帧）。
      **游戏只读 `.ogv`**。2026-09-18 第一版误收这两项，包凭空胖 32MB（14.26MB mp4 + 18.2MB 参考帧）。
    - **打完包必查 4 项**：① `installer/` 在不在（它曾在 9.09/v1/v2 **三版整目录丢失**）；
      ② 根目录 5 文件齐不齐；③ 有没有混进 `.mp4` / `*.exe`；④ 包内 `README.md` 头部版本身份段是否**已是本版**。
    - **命名**：`日期整合版_vN_主题.zip`（如 `9.18整合版_v1_流血烧伤修复.zip`），放桌面，禁止静默覆盖既有版本号。
22. **剧情技能前缀**：剧情主动技能一律 `s1_` 前缀，注册在 `SkillEffects.DATA`（元信息）+
    `SkillEffects.EFFECTS`（id → Callable）；剧情兵种与 `HeroDefs` 完全隔离，**不要混进选人池/图鉴**。
23. **血条与护盾的显示规则（2026-09-13）**：血条同时承载 hp 与护盾，换算式统一在
    `DamageFx.hp_shield_layout(hp, shield, max_hp) -> Vector3(分母, hp占比, shield占比)`：
    - `hp + shield ≤ max_hp` → 分母 = `max_hp`（护盾按点数等比占位，条不满，剩余留空）；
    - `hp + shield > max_hp` → 分母 = `hp + shield`（铺满整条，按比例分配）；
    - 两式在 `total == max_hp` 处连续，不会跳变。**改血条显示务必走这个函数**，别在 UI 里各写一份。
    - 顺序 hp 在左、护盾在右；**护盾变化不做动效**（只有 hp 掉才有白条残影）。
    - 头顶血条（`unit_token._draw_overhead`）与侧栏血条（`HpShieldBar`）共用同一套算式，改一处要同步看另一处。
24. **侧栏条一律走 `DamageFx.update_bar()`（2026-09-17）**：`duel.gd` / `team_duel.gd` / `story_battle.gd`
    三处各写一份 `_update_bar` 的历史已终结 —— **要改侧栏条的行为，去改 `scripts/ui/damage_fx.gd`，
    不要改那三个文件里的转调点**。它统一负责：写「生命/能量/理智」标签、`HpShieldBar` 与 `ProgressBar`
    两条分支、`num_text` 优先、`smooth` 缓动。
    ⚠️ **历史教训**：9.13_v2 把生命条换成 `HpShieldBar` 时只改了其中**一部分分支**，漏掉写数字标签那段 →
    生命条数字**永远停在 `_make_bar` 的初值 `1.00 / 1.00`**（用户实报的 bug）。
    三处重复实现 = 改一份必漏两份，**收敛成一份是这个坑的唯一解**。回归：`tests/damage_fx_smoke.gd`。
25. **流血 / 烧伤：等级与「剩余回合」彻底分离，UI 文本一律走 `SkillEffects.status_label`（2026-09-18）**：
    追猎【狙击】3 层创伤 → **触发流血1级**（设计表 M4）；【流炎飞弹】把**已有流血1级升为2级**（Y4），
    且「附加灼烧」与「升级流血」是**分号并列、两者并存**（不是二选一）。
    数值口径（Z4）：1级 = 被攻击时 20% 额外真伤、**持续 2 回合**；2级 = 30% 额外真伤 + 每回合末 1 真伤、**持续 3 回合**。
    **等级只升不降、时长可刷新**：`SkillEffects.apply_bleed(t, level)` 是唯一入口（以后新技能要挂流血也走它），
    时长由通用计时器 `bleed_end` 承载（与冻伤 `freeze_end` 同一套），
    ⚠️ **不要再用「层数」表示剩余回合数**，也不要直接用 `add_status("bleed", n)` 挂流血。
    **烧伤走完全同源的解耦**（2026-09-18 补丁二）：`SkillEffects.apply_burn(t, rounds)` / `extend_burn(t, n)` /
    `clear_burn(t)` 三件套是唯一入口，时长由 `burn_end` 计时器承载，
    `statuses["burn"]` **只表示「是否处于烧伤」（恒为 1）、不再是回合数**；
    重复施加取**更长者**（`maxi(现值, 新值)`），所以「炎拳 +1 / 不知火 +2」这类语义是**延长时长**（`extend_burn`）。
    ⚠️ 别再写 `set_status("burn", n)` 或按 `status_stacks("burn")` 当回合数算账 ——
    旧实现靠「层数≡回合数」碰巧等于设计表的 2 回合，属**隐藏同源坑**。
    **UI 显示剩余回合**：`SkillEffects.status_label(id, lv, rounds)` 是**唯一**的状态文本生成处
    （`流血2级·余3回合` / `灼烧·余2回合` / `创伤2层` / `眩晕`），配套 `status_timer_id(id)` / `status_rounds(u, id)` /
    `status_badge_num(id, lv, rounds)`；`BattleUnit.status_icons()` 的每个元素带
    `rounds` / `label` / `badge_num` 三个字段，`to_status_summary()`（战斗日志 + LLM 决策）同样走它。
    ⚠️ **各界面不要再自己拼一遍 `"%s%d" % [cn, lv]`** —— 4 个消费点（`duel.gd` / `story_battle.gd` /
    `unit_info_popup.gd` / `unit_token.gd`）已统一改为直接取 `label` / `badge_num`，重复实现 = 改一份必漏三份。
    改状态/计时后 `BattleUnit.clear_statuses()` 会把 `bleed_end` / `burn_end` / `freeze_end` 一起清掉，
    否则会残留「余 N 回合」。
    ⚠️ **历史教训 1**：初版实现把设计表的 1 级基准写成 2 级、大招升级目标写成 3 级，**整条链上移一档**，
    直到玩家用 3 次狙击实测显示「流血2级」才暴露。
    ⚠️ **历史教训 2**：层数同时当等级与剩余回合用（`tick_end` 每回合 `bleed-1`），
    导致 1 级只撑 1 回合、2 级只撑 2 回合，且「创伤满 3」再来一次会被叠成 2 级。
    **动这套状态前先对一眼设计表 `战棋5.xlsx` 里追猎那一行**（Z4 状态定义 + M4/Y4 技能说明）。
    ⚠️ 剑舞【贯穿】的 `heavy_wound +5` 与设计表 U9 不符，但**是用户有意设计，不要"修正"回去**。
26. **新手教程不许改战斗规则（2026-09-28）**：`BattleTutorial extends Battle`，**只允许覆写
    `_make()`（让木桩走教程表）与 `_turn_ai()`（木桩行为）**，其余全部继承。
    木桩参数在 `scripts/combat/tutorial_defs.gd`，⚠️ **木桩护甲必须是 0** ——
    伤害里 `armor` 是平摊减伤（`minf(armor, rest)`），而剑舞「瞬击」、追猎「狙击」都只有 **1 点**伤害，
    木桩带 1 甲这两个英雄就恒为 **0 伤害、教程第 7 步永远过不去**（追猎「流炎飞弹」还 `per_game=1`）。
    「护甲减伤」改用**玩家自己的甲**演示。`tests/tutorial_smoke.gd` 的 B3/B4 就是钉这条的。
    教程过关看**步骤机的 gate**，不依赖 `_check_win`（木桩血厚打不空是故意的）。
    ⚠️ **1V1 里「放完技能 = 本回合结束」**（`Battle.human_cast()` 末尾无条件 `_finish_human()`），
    教程收尾统一走 `Tutorial._after_player_action()`，**不要写成"等玩家点结束回合"**（会永远卡住）。
    ⚠️ **步骤表是按英雄数据动态组装的**（`MECH_STEPS` 模板 + `_build_steps()`，判定全读 `SkillEffects.DATA`）：
    完整篇 = 基础 4 步 + 机制步 + 收尾 3 步；精简篇 = 机制步 + 收尾 3 步。
    要加机制步：`MECH_STEPS` 加模板 + `_mech_steps_for()` 加触发条件；
    **步骤标题里不要写死 ①②③** —— 圈码由 `_circled()` 运行时生成，硬编码插一步就全乱。
    机制步的 gate **必须带 `"manual_ok": true`**：有些技能有前置条件放不出来
    （剑舞「诛心」是斩杀技，只能打生命 ≤30% 的目标，对满血木桩放不了），硬卡会让教程死在那儿。
    改完机制步要同步 `tests/tutorial_smoke.gd` 的 `EXPECT_MECH`（它会变红，这是设计如此）。
    ⚠️ **教程棋盘铺了地形**（`TutorialDefs.TERRAIN` + `BattleTutorial._build_terrain()`）：
    森林(3) 受击 ×0.8 / 移出多花 1 能，水域(5) 回合末 −1 能 / 禁位移。
    **地形必须在摆位之前建好**（`_put()` 会 `_sync_terrain()` 读地形），否则 id 残留为 0。
    配色走 `Terrain.COLORS` / `Terrain.color_of()`（**不要再各写一份配色表**）；
    ✅ 2026-09-30 已收敛：`team_board.gd` 那份 `TERRAIN_COL` 改为转发 `Terrain.COLORS`，
    状态徽章配色也统一到 `SkillEffects.status_color()`（原先 `unit_token.gd` / `team_board.gd` 各一份）。
    ⚠️ **遮罩挖洞只盖棋盘区、不盖底部步骤框**（否则说明文字被压暗看不清），
    且 `mouse_filter = IGNORE`（**只压暗、不拦点击**）；要换聚光目标去改 `_focus_control_for_step()`。
    ⚠️ **两个"回合"标记别混用**（2026-09-29 踩过）：
    `turn_ended` = "回合已经交出去了"（**放完技能自动结束时也会置位**）；
    `end_turn_pressed` = "玩家亲手按了结束回合按钮"。
    要求玩家动手的步骤 **必须用后者** —— 用 `turn_ended` 当 gate 会让那一步白给
    （玩家没按过按钮就自动过了）。回归在 `tutorial_smoke.gd` 的 G 段。
    完成页的「去实战一局」照 `MainUI._on_enter_board` + `_on_diff` 配 `Global`
    （`battle_mode`/`offline_type`/`difficulty`/`ai_backend`/**`net_mode`**）——
    **少设一个就会带着上一局的残留进对局**。
    ⚠️ **教程覆写了 `_check_win()` 为空**（`BattleTutorial`）：教程的结束**只由步骤机决定**。
    原因：「位移」步要把木桩压到残血（`TutorialDefs.DUMMY_LOW_HP = 2`，好让斩杀类位移技真能生效），
    玩家完全可能顺手把木桩**打死** —— 沿用基类就会立刻判"蓝方全灭" → `run_step()` 返回 over →
    教程在半途被强行结束。**改这条时两件事必须配套**：残血窗口 + 胜负接管 + 离步 `restore_dummy()`（被斩杀就复活）。
    步骤之间的状态切换**只写在 `Tutorial._set_idx()` 一处**（`_goto_step` / `_advance_if_gate` 都走它），
    别散到各处。
    ⚠️ 顺带纠正一个容易记错的判断：**「诛心」这类斩杀技对满血目标并非"放不出来"** ——
    效果函数只是不执行斩杀（返回"无法斩杀"文字），而 `human_cast()` 里的位移段落在该判断**之前**就执行完了。
27. **账号与存档（2026-09-28 立；2026-10-04 账号上云；2026-10-05 删本地账号后大改）**：
    ⚠️ **「账号」在本工程只剩一个概念：云端账号。**
    客户 2026-10-05 明确要求「不要有本地账号这个东西！离线玩相当于玩 0 进度原始账号」——
    于是原 `AccountStore` / `user://accounts.json` / 登录页的「选择已有账号」**整套删除**。
    现在本机只有**两份文件**：
    · **`user://progress.json`**（`ProgressStore`）—— **匿名本机进度**：没有名字、没有 id、
      没有列表、不能切换。「离线玩」用的就是它；本机首次玩即「0 进度原始账号」。
      写入只认 `tier` / `tutorial_done` / `tutorial_hero` 三个字段，
      **脏数据（name / id）会被丢掉 —— 它永远不会退化成账号**。
    · **`user://cloud_session.json`**（`CloudSession`）—— 云端登录态：token + 账号信息
      （含 `account.progress`，**断网时进度就靠它兜底**）。**只存 token，绝不存密码**。
    **两份进度互不污染**：登录中读写云端、离线玩读写本机 —— 所以"进度跟账号走"与
    "离线玩是 0 进度"能同时成立。进度写入**统一走 `MainUI._save_progress()`**，别在各处手写
    （原先 `tutorial.gd` 就漏过一条）。这两份都不参与任何战斗计算、不进联机同步。
    **存档损坏必须降级为「没有进度」而不是报错**（最多重问一次水平，不能让玩家进不去游戏）。
    跑测试若要动存档（`tutorial_smoke` / `cloud_auth_smoke`），**先快照再还原**。
    ⚠️ `-s 脚本` 测试里取 autoload 必须 `var g: Variant = root.get_node_or_null("Global")`
    —— 写 `var g := ...` 会因"从 Variant 推断"警告被当错误拒绝编译（2026-10-05 踩到）。
    ⚠️ 在 `-s 脚本` 模式的测试里**不能直接写 `Global.xxx`**（autoload 名解析不了会编译失败、
    整个测试跑不起来）；要用 `root.get_node_or_null("Global")` 取。
    ⚠️ **更要紧的一条（2026-09-30 实测踩到）**：不只是"测试里"，
    **被测试依赖的脚本里也不能引用 autoload** —— 只要出现在依赖链上，
    那个测试会 `Compile Error: Identifier not found: Global` →
    `Failed to compile depended scripts` → **进程只吐一个 SIGTERM、一个字都不输出**（极难查）。
    所以**纯逻辑/工具类脚本（如 `net_roomcode.gd`）不许引用 `Global`**，配置一律由界面注入。

28. **房间号联机（2026-09-30）**：玩家不再输 IP/端口 —— 建房拿 4 位数字号，对方输号即连。
    链路：房主 `NetSession.host_game()` +（ws 模式）`NetTunnel` 拿公网地址 →
    向 `tools/room-service/server.js` 上报 → 换回号码；加入者输号 → 查到地址 → `NetSession.join_game()` 直连。
    **目录服务只存 `码 → 地址` 一个键值对**，不碰游戏状态、不裁决、不转发对局流量 ——
    对局数据仍然走原来的 ENet / cpolar 隧道（**那条线一行没动**）。
    ⚠️ 房间号是**口令语义，不是密码语义**（知道号码就能连）；服务进程重启号码全丢；无 TLS。
    ✅ **2026-10-03 已上云**：服务部署在自有阿里云 ECS —— `http://39.105.223.8:8787`
    （`/opt/room-service`，systemd 单元 `room-service.service`，安全组已放行 8787）。
    `Global.net_room_service` 与 `NetRoomCode.DEFAULT_SERVICE` 的默认值都已指向它，
    **玩家不再需要在自己电脑上跑服务**；本地自测想用本机实例时把前者临时改回 `127.0.0.1:8787`。
    ✅ **同期解决了「房主在 NAT 后别人连不上」**：公网建房走**自研反向隧道**
    （`tools/relay-service/relay-service.js` + 房主侧 `scripts/net/net_relay_host.gd`）——
    房主主动连出、**不用装 cpolar**，中继只转发字节。`Global.net_transport` 默认 `"ws"` 即走这条路，
    **任何网络环境下对方输号即连**；选 `"enet"` 则是局域网直连（同一 WiFi 更快，属可选的进阶用法）。
    ⚠️ 中继/房间服务的地址分别在 `Global.net_relay_host`+`net_relay_port` 与 `net_room_service`，
    换部署点只改这几处。
    ⚠️ `net_roomcode.gd` **不许引用 `Global`**（理由见注意点 27 的依赖链那条），服务地址由 main_ui 注入。
    改服务端后跑 `node tools/room-service/selftest.js`；改客户端后跑 `tests/room_code_smoke.gd`
    （**没装 Node 会 SKIP 而不是 FAIL**，这是有意设计）。

29. **新增带 `class_name` 的脚本后，必须跑一次 `--import` 再验证（2026-09-30 实测踩到）**：
    新建脚本文件后直接跑 `--check-only` 或回归，会报
    `Parse Error: Identifier "UiKit" not declared in the current scope`。
    这**不是代码错**，而是新类还没进 `.godot/global_script_class_cache.cfg`
    （Godot 只在扫描/导入项目时注册全局类）。
    解法：`Godot_v4.7.2-stable_win64_console.exe --headless --path <工程> --import`，
    然后确认 `grep UiKit .godot/global_script_class_cache.cfg` 能命中。
    ⚠️ **别急着把新类改成 `preload` 绕过去** —— 工程里 `class_name` 是主流用法
    （`BattleUnit` / `SkillEffects` / `DamageFx` / `HpShieldBar` / `Terrain` / `UiKit` / `HeroRules`…），统一走 `--import` 即可。
    ⚠️ 另外 `--check-only -s <脚本>` 对 autoload（`Global` / `Net` / `Sfx`）会误报 `Identifier not found`
    （见「三、运行与测试」的告示与注意点 27），**UI 脚本的编译错误要靠场景冒烟抓**：
    `--quit-after 150 res://scenes/Xxx.tscn`，抓 `SCRIPT ERROR` 计数。

30. **`main_ui._fit()` 必须保持幂等（2026-10-04，用户实报"账号界面点输入框就卡"）**：
    它每帧被 `_process` 调用，**只能"值变了才写控件"**。
    原因：`add_theme_constant_override` / `add_theme_font_size_override` **写入相同值也会发
    `NOTIFICATION_THEME_CHANGED`**，`Control.position` setter 会发 transform 通知；
    整棵树每帧被判"变了"，而面板里若有**获得焦点的 `LineEdit`**，祖先的 transform 通知会让它
    每帧更新**输入法候选窗位置** → 中文输入法下直接卡死。
    ⚠️ 往 `_fit` / `_apply_node_sizes` 里加新写入点时，**必须带"变了才写"判断**；
    主题常量走 `_set_theme_int()`、字号缓存走控件 meta `_fz_applied`。
    回归：`tests/mainui_fit_smoke.gd` —— 它断言 `fit_writes`（诊断计数）在静止后**不再增长**。
    ⚠️ 卡死症状 headless 复现不出来（无窗口/无 IME），所以回归钉的是"零写入"这个可测特征，别删。
    ⚠️ **测试不得依赖 `user://` 里有没有账号（2026-10-04 踩到）**：`_ready` 第 98 行按
    `_initial_panel()` 决定默认显示 `start` 还是 `tut_login`，而"切过去时会产生几次
    冷启动写入"取决于**之前显示的是哪个面板** —— 于是谁建了账号，谁就把这个测试跑红
    （从 PASS 17/0 变成 FAIL 2）。现状：切面板后先等 4 帧再计数，且**不数**"切面板必须写入"
    （那条断言本身就是错的）。另注：跑 `MainUI` 场景的测试都会经 `_setup_cloud()` 碰 `user://`，
    `tutorial_smoke` 的快照只保 `progress.json`、**不覆盖 `cloud_session.json`**。
    ⚠️ **写 start 面板的控件断言别"见到横排就收集"**：该面板里有**两个** `HBoxContainer`
    —— 标题下的**账号行**（只含 1 个按钮）和末尾的**工具条**（含 5 个）。要取**按钮最多的那个**
    才是工具条，否则断言会把「登录云端」当成工具条第一个按钮（2026-10-05 加第 ⑦ 段时踩到）。

31. **UI 颜色一律从 `UiDesign` 取、样式一律走 `UiTheme` 组件库（2026-10-04 立）**：
    界面文件里**不许再写 `Color(...)` 字面量**。审计过：改造前 UI 层有 **373 处**硬编码颜色、
    188 种不同值 —— 其中「同一个金写了 19 遍 / 9 个文件」「同一个面板色 5 遍且 alpha 各不相同
    （0.94 / 0.90 / 0.97）」「7 种彼此差不到 3% 的灰蓝小字」。这类问题的特征是**改不干净**：
    改一处不影响另一处。
    · 要新颜色 → 先在 `scripts/ui/ui_design.gd` 加令牌。令牌值**锚定历史值**（保证迁移像素不变）。
    · 要新组件样式 → 加到 `scripts/ui/ui_theme.gd` 的组件库区（`style_button` / `style_input` /
      `style_card` / `style_modal`），**不要在界面文件里手写 `add_theme_*_override`**。
    · 新场景根要在 `_ready()` 首行挂 `UiTheme.attach(self)`（幂等）。样式优先级是
      **控件 override > Theme**，所以挂主题不会破坏既有观感，只补缺失部分（Tooltip / PopupMenu /
      滚动条 / **焦点环**）。
    · **改令牌值 = 全工程改色**，属显式设计决定；改完必须跑 `tests/ui_design_smoke.gd`
      （A 段会红，提醒你同步更新锚点值）。
    · ⚠️ **不要** `preload("...ui_design.gd")` 之后拿它调**静态函数** —— preload 得到的是
      GDScript 资源，**只有常量能从它上面取**，静态函数会报
      `Nonexistent function 'contrast' in base 'GDScript'`。直接用全局类名 `UiDesign.contrast()`。
    · ⚠️ 令牌编号**必须与亮度同序**（墨阶 950→050、金阶 700→100，数字越小越亮）——
      编号错乱会让层级关系被读反，测试 C 段已抓出过一次真实倒挂。
    · 两条无障碍硬边界（实测）：**阵营色不得当正文用**（ALLY 3.28 / ENEMY 3.18 < 4.5，只做条/圆/描边）；
      **`INK_500` 只许用于禁用态**（4.16 < 4.5，看着"够亮"但做正文不达标）。
    · **弹窗底色恒不透明**（`SURFACE_MODAL` alpha=1.0）；半透的只有 `SURFACE_PANEL`
      ——那是棋盘上的对局侧栏，**不是弹窗**。
    规范全文见 `docs/UI设计系统.md`，视觉稿见 `docs/UI设计系统_视觉稿.html`。
    回归：`tests/ui_design_smoke.gd`（128 断言，含"界面文件里不许有核心语义色字面量"的扫描）。
    · **资源条四色四义**：生命绿 `HP` / 护盾蓝 `SHIELD` / 能量琥珀 `ENERGY` / 理智紫 `SANITY`。
      ⚠️ **不要拿 `ENEMY`（敌方阵营蓝）当能量色** —— 侧栏曾这么写过；也不要把生命与护盾
      画进同一根条里（并排只靠颜色分，在细条上看不出谁是谁）。测试 H 段会断言四色两两通道差 ≥0.25。
      ⚠️ 棋子头顶迷你条**不再使用** `DamageFx.hp_shield_layout`（那条换算式是侧栏 `HpShieldBar`
      的语义，且有 7 条断言钉着，**别动**）；迷你条是三条各自独立的简单比例。
    · **字体三档**（硬字号阈值，不是偏好）：`UiTheme.title_font(size)` 自动选 ——
      **≥60px 毛笔楷书**（带字距）／**≥22px 思源宋体 Bold**／**<22px 思源黑体**。
      标题一律走 `UiTheme.style_title(label, size)`，别在界面里自己 `add_theme_font_override`。
      ⚠️ 毛笔小字会糊、宋体小字不如黑体清楚，所以阈值不能"顺手调低"。
      ⚠️ `display_font()` / `serif_font()` 在字体文件缺失时**降级到正文字体，绝不返回 null**
      （否则整屏标题消失）；测试 I 段会断言三档字体**真的加载到了**（降级是静默的，没人会发现）。
      字体在 `assets/fonts/`（**OFL，必须随包附各自 `LICENSE-*.txt`**，共 34 MB）。
      正文用**可变字重**（`body_font(UiTheme.W_MEDIUM)` 给按钮、`W_BOLD` 给强调）——
      别把字重写死成 400，否则界面会显得"平"。
    · **RichTextLabel 的内联色必须用 `UiDesign.MD_*` 调色板**，不许写裸 hex。
      ⚠️ 这是踩过坑的：图鉴/故事正文原来硬编码了一批**纸面深色**（`#2e6b3c` `#7a5a10` `#55504a`…），
      面板底转深色后就成了「**深底深字，一个字都看不见**」——而**渲染之前完全无法察觉**。
      J 段会扫描全部界面脚本的 `color=#`，断言每一处对卡片底对比度 ≥3.0。改面板底色前先跑它。
    · **不要**再引入"浅色子主题"（米白面板 / 奶油按钮那一套）。
      全产品已统一为深色 + 金；"书卷气"由**宋体标题 + 金描边**表达，不靠浅色底。

32. **备份目录不要放在 Godot 工程树内（2026-10-04 踩到，代价是一次假"挂起"）**：
    Godot 会扫描**整个工程目录**给每个 `class_name` 注册全局类。把 `scripts/ui/` 的副本
    （23 个同名脚本）备份到工程里之后，类缓存被**指向了备份路径**：

    ```
    "class": &"HpShieldBar", "path": "res://_backup_xxx/scripts/ui/hp_shield_bar.gd"   ← 被劫持
    ```

    两个后果，第二个更凶险：
    · `load("res://scripts/ui/xxx.gd")` 报 `Class "X" hides a global script class` → **返回 null**。
      若发生在 `-s` 测试的 `_initialize` 协程里，协程静默死掉、`quit()` 再不执行 →
      **进程永不退出，表现为"挂起"**（低 CPU、零输出），极难往"备份目录"这个方向想。
    · 这些类**在别处按类名引用时会静默解析到备份里的旧代码** —— 改了却"没生效"。
    ⚠️ **工程里现存 14 个 `_backup_*` 目录，是同一颗雷。**
    本工程已有的正确做法是：**每个备份目录里放一个 `.gdignore`**（Godot 官方机制，见到就跳过该目录）。
    **先后漏过两个，而且都是补漏时又漏的**：
    ① `_backup_roomcode1004/`（2026-10-04 首次发现）—— `NetRoomCode` 被劫持到
    `res://_backup_roomcode1004/scripts/net/net_roomcode.gd`。这个具体事故很凶险：
    备份版是 `CODE_LEN := 11`、现用版是 `CODE_LEN := 4`，而 `main_ui.gd:298` 会用
    `NetRoomCode.CODE_LEN` 生成加入面板的占位提示、并按它校验位数 ——
    **等于联机的 4 位房间号功能整体失效**（会要求输 11 位）。已补 `.gdignore` 修复。
    ② `_backup_autoupdate1004/`（同日二次发现）—— 它**没**劫持类缓存（里面只有 `main_ui.gd`，无 `class_name`），
    但被当成正常资源**打进了程序包**（导出规则见注意点 33）。已补 `.gdignore` + 给导出加排除规则。

    **检查命令**（改完脚本/动过备份后都值得跑一次）：
    ```bash
    grep -c "_backup" .godot/global_script_class_cache.cfg     # 必须是 0
    grep -A 8 '"class": &"NetRoomCode"' .godot/global_script_class_cache.cfg | grep '"path"'
    ```
    若不为 0：给对应备份目录补 `.gdignore` → 删 `.godot/global_script_class_cache.cfg` → `--import` 重扫。
    新增备份目录时**第一件事就是放 `.gdignore`**（或直接放工程树之外，如工作区目录）。
    📌 补漏时**别只补刚发现的那一个** —— 把全部 `_backup_*/` 扫一遍再收工
    （2026-10-04 就是"补了一个、漏了另一个"）。

33. **程序包 ≠ 源码包（2026-10-04 立，起因是一次误解）**：
    两套规则**互不相干**，别互相套用。
    - **程序包**（Godot 导出的 exe/pck）：由 `export_presets.cfg` 决定。本工程是
      `export_filter="all_resources"` = 导出**工程里所有资源**（`.gd/.tscn/.tres/.png/.ttf/.wav`…），
      **不管有没有被引用**。而 `.md` / `.html` **不是 Godot 资源**（引擎不认识该类型、也没有脚本 `load()`），
      所以**天然不进包** → **「放进工程目录」≠「进程序包」**。
    - **源码包**（zip，规则见注意点 21）：`.md` 是要收的，根目录固定 5 份。
    - ⚠️ `all_resources` 的副作用 —— 这些会**真的进包**，现已用 `exclude_filter` 挡掉：
      `tests/`（76 条，其中 `_probes/` 里**硬编码服务器地址** `39.105.223.8:8787/8789`）、
      漏了 `.gdignore` 的 `_backup_*/`、根目录那个 611MB 的 `Godot/`（`editor_settings-4.7.tres` 是资源）。
    - 当前设置：`exclude_filter="tests/*, _backup_*/*, Godot/*, *.md, *.html"`。
    - **改完导出设置必须实测**（filter 写错会把脚本一起排除、包直接废，而"导出成功"**不会报错**）：
      `godot --headless --path . --export-pack "Windows Desktop" /tmp/t.pck`
      → `python tools/inspect_pck.py /tmp/t.pck`
      （一键判断：该排除的为 0、`.gdc`/`scripts/`/`assets/` 仍在。改前那版能准确报出 `tests/ 76 条`。）
    - 设计文档已从根目录挪进 `docs/`（根目录保持「5 份」不变，见注意点 21）。

34. **全屏弹层必须设 `z_index = UiDesign.Z_OVERLAY`（2026-10-05 立，起因是「人物盖住弹窗」又犯了一次）**：
    Godot **同层节点先比 `z_index`、再比树顺序** —— 所以「最后 `add_child` 就画在最上面」
    **只在没有高 z_index 子节点时成立**。而棋子自带 z_index（名字标签 **120**、击破特效 **110**、
    DragonBones 骨骼部件由数据给），弹层默认 0 → 棋子就画在弹窗之上。
    ⚠️ 这个坑**踩过两次**：`unit_info_popup` 早就写死 4096 并留了注释（「否则棋子骨骼部件会盖住弹窗」），
    但 `SettingsLayer`（局内设置）和教程的挖洞遮罩**没跟上**。教训：**「有先例」不等于「有规矩」**。
    现在层级进了令牌：`Z_UNIT_FX` / `Z_UNIT_LABEL` / `Z_OVERLAY`，**弹层侧与棋子侧都从令牌取**；
    `ui_design_smoke` 的 K 段会扫描 6 个界面的源码 + 断言大小关系 —— 谁再写死数字就直接变红。
    ⚠️ `Z_OVERLAY = 4096` 已是 Godot `z_index` 的**上限**；**弹层内部子控件不要再设 z_index**
    （`z_as_relative` 默认开启，父子相加会溢出被钳制）。

35. **「忘记密码」走服务端自有邮箱通道（2026-10-05 立，服务端已上线）**：
    两条接口（`/send-code` 带 `purpose:"reset"`、以及 `/reset-password`）已上线并做了**生产真链路**验证；
    契约与实现记录见 `docs/忘记密码_接口契约.md`。四条要点：
    - **收件地址只从账号里取**（`acct.email`），**绝不信**请求体里的任何地址；而账号里存的 email
      又只可能来自**验证过**的注册（注册时 `email: saved ? email : ''`）⇒ 谁也拿不到别人账号的重置码。
      **这两条必须同时在**，少一条就漏。
    - `handleSendCode` **只在带 `purpose:"reset"` 时分流**；不传时行为与改前**逐字节一致** ——
      已发布的客户端仍用 `{email}` 发注册码，**改签名会打断线上注册**。
    - ✅ **顺带发现的既有问题已修（2026-10-05，用户批准后改并上线）**：
      原 `codeTake()` 会把验证码记录**整条删掉**，而 **60 秒重发冷却**与 **同邮箱 5 封/天**的
      计数正寄存在同一条记录上 ⇒ **每成功注册/改密一次，该邮箱的冷却与日配额都被清零**。
      证据：注册码 `17:48:07` 发出、重置码 `17:48:36` 就发出去了（相隔 29 秒 ≪ 60 秒），
      紧接着第三次请求被正常 429 ⇒ 冷却本身有效，是"记录被删"造成的清零。
      现在改成 `codeDrop()`：只清 `code`/`exp`/`tries`，**保留** `lastSent`/`day`/`dayN`；
      另加 `codeGc()` 回收老记录（不再整条删，Map 会一直长）。
      ⚠️ **最易漏的地方**：这种"删记录"的写法散在多个 handler 里（当时 `handleResetPassword`
      里还藏着一处 `codes.delete(email)`）—— 改这类语义要**全库搜 `codes.delete`**，
      只改 `codeTake` 远远不够（本地测试台就是这么抓出那处漏改的）。
    - 已知残留（**有意接受**）：该接口对"存在且已绑邮箱"的昵称会回掩码 ⇒ 可用来**枚举昵称是否存在**；
      限流（同 IP 10 封/时 + 30 封/天）让它又慢又吵 —— 每次命中都往对方信箱投一封真邮件。
      将来公开运营时改成统一文案即可，**客户端无需动**。

36. **战术模型的每日额度由服务端算，客户端改时间无效（2026-10-05 立）**：
    未登录 = **设备 3 次/天 + 来源 IP 9 次/天（两道都要过）**；登录后 = 按 uid **10 次/天**。
    起因：客户端被分享出去后**任何人都能无限烧豆包额度**。四条**别踩**：
    - 日期一律用 `_todayBJ()`（北京时间）。**别用 `toISOString()`** —— 那是 UTC，
      "每天"会变成北京时间**早上 8 点**重置，玩家会以为"莫名其妙又多了一次"。
    - 身份只认两样：**token**（HMAC，伪造不了）与 `req.socket.remoteAddress`（真实 TCP 源地址）。
      ⚠️ **不要改成读 `X-Forwarded-For`** —— 那个客户端随便编，一改整个防作弊就归零
      （现在 8789 直连公网、前面没有反向代理，才敢这么写）。
    - 计数**必须落盘**（`llm_quota.json`）：只放内存的话，服务一重启就等于白送次数。
    - 客户端 `user://device_id.txt` **不是安全凭据**（删了就换一个）—— 它只是"区分机器"的标签；
      防线在"设备池与 IP 池取更严"这个**组合**上，别把它单独当令牌用。
    改这块之后必跑两套：服务端 Node 额度测试台（含"换源 IP 打账号额度"这条）
    + `tests/_probes/quota_probe.gd`（客户端 429 解析，用本地假服务器造 429，不烧真额度）。

37. **发版产物放哪（2026-10-05 立，2026-11-24 纠正交付目录）**：
    - **交付目录**：`<桌面>\一些程序包\`，固定名 `战棋安装包_最新.exe`，每次发版**覆盖**
      （本机各项目的安装包都集中在这一层；**桌面根目录不放二进制**）。
      🔴 2026-11-24 纠正：此前写的是"桌面"（根目录），用户明确「安装包放哪是有规定的，
      **不要乱放桌面上**」—— 脚本第 9 步已改指向 `一些程序包\`，旧位置那份已送回收站。
    - `installer/`：**只留本次这一份**，旧的自动删；
    - `cbw\战棋\战棋版本存档\`：**只放源码包**，不塞安装包。
    三条都已内建进 `tools/release_desktop.js`（第 7/8/9 步），**别再手工搬**。
    起因：`installer/` 曾堆到 **11 个安装包 / 1.2 GB**；用户明确"只要源码存档、不要安装包存档"。
    ⚠️ 桌面属**个人目录**，清旧必须走回收站（见「安全删除」skill），不要 `rm` ——
    这也是脚本选择"固定名覆盖"而不是"改个名字再删旧的"的原因之一。
    ⚠️ 固定名意味着**版本号不在文件名里**：查版本看文件属性「详细信息」（Inno 写的 `VersionInfo`）。

38. **注册 / 找回密码走**双通道**：短信优先、邮箱并列（2026-10-09 立，两端都已上线）**：
    - 产品是阿里云「**短信认证**」(dypns)，**不是**「短信服务」—— 后者个人实名办不了；
      赠送签名/模板免报备，模板 `100001` 注册 / `100003` 重置 / `100004` 绑定手机号。
    - 渠道由**请求里的 `channel` 字段**表达：`"sms"` 或 `"email"`。
      🔴 **`channel` 缺省 = 邮箱老路** —— 已发布客户端不传该字段，语义必须逐字节不变。
    - 🔴 **验证码由阿里云生成与校验**（发码时传 `##code##` 占位符）⇒ 服务端**不存短信码**，
      因而没有重放问题；但也**放不回去**（与邮箱码不同，没有 `codeRestore`）。
    - 🔴 **找回密码的码只发到"该账号自己绑定的"那个号/邮箱** —— 绝不按请求体里的号码发，
      否则就是把重置码投给攻击者指定的号。
    - 客户端侧：`cloud_api.gd` 的短信方法**显式**带 `channel`（不给默认参数 ——
      服务端缺省是邮箱，"以为发短信其实发邮件"这种错极难查）；
      `main_ui.gd` 的注册/找回面板各有**两个横排小按钮**切换渠道，找回面板**发码后锁渠道**。
    - 短信**每条计费**（套餐 1000 次）：同号 60 秒 / 5 条每日；同 IP 10 条每小时 / 20 条每日；
      **全局日 200**。客户端的职责是**把服务端返回的 `error` 原样展示**（那是给人看的中文）。
    - ⚠️ **回归绝不触网**：`tests/cloud_auth_smoke.gd` 用 `_detach_cloud()` 摘掉 CloudApi ——
      原先它会真的往线上发"忘记密码"请求（并真发邮件），加了短信渠道后会**真发短信**。
      契约见 `docs/短信验证_接口契约.md`；服务端自检 `tools/cloud-service/selftest_sms.js`。

39. **自动更新分平台走两条链（2026-10-10 立，起因是手机端更新从根上就是坏的）**：
    - **Windows**：后台下载 zip → 换 exe → `.bat` 重启替换（`AutoUpdate`，桌面专属）；
    - **安卓**：`can_auto()` 返回 false —— 那条链在手机上全不成立（APK 内部只读、没有 cmd.exe），
      硬走会一开下载就失败（玩家实测的「下载中断 result=10」就是 `RESULT_DOWNLOAD_FILE_CANT_OPEN`）。
      安卓走 **「去下载新版本」→ `OS.shell_open(清单 downloads.android)` 打开浏览器下载 APK → 手动安装**。
    - 🔴 **清单必须带 `downloads.android`**（`release_desktop.js --android-url`），否则手机端提示
      「清单里还没有安卓安装包地址」。发版时**双端一起发**（先传 APK 拿直链，再跑 Windows 流水线）。
      ⚠️ 该参数在 `release_desktop.js` 里**有两份 manifest 构造**（`--manifest-only` 分支与完整发版分支），
      改一处不够 —— 2026-10-10 实测踩过。
    - 🔴 **安卓包在 OSS 上必须以 `.zip` 后缀存放**（2026-10-10 实测）：阿里云 OSS 默认公网 endpoint
      **禁止分发 `.apk`**（返回 `ApkDownloadForbidden`，官方要求改用 CNAME/备案域名）——
      同一份字节，`.apk` 后缀 400、`.zip` 后缀 **206 正常下载**（APK 本质就是 zip，政策按**后缀**拦，
      签名 URL 一样拦、与签名无关）。所以对象名是 `game/zhanqi-android-v<版本>.zip`，
      手机端文案按「下载 → 文件管理解压 → 安装」来写。想要"下载即装"，只能等绑了备案域名。
    - 🔴 **下载/更新失败的提示一律走 `AutoUpdate.human_error()`**（错误码 → 可行动的中文），
      **绝不把 `result=N` 这种内部码怼给玩家**（有回归断言钉着，见 `tests/update_smoke.gd` ⑤b）。
    - 安卓 `versionCode` 必须随版本递增，否则新 APK 无法覆盖安装。
      🔴 **2026-11-24 核实：主工程 `export_presets.cfg` 里已经只剩 `Windows Desktop` 一个预设**，
      安卓预设与 `android/` 构建模板都不在主工程内（10.5.4 的 APK 是从
      `WorkBuddy/2026-09-06-09-51-06/project/zhanqi-godot` 那份旧副本打的，该副本已停在 10.5.4）。
      **下次要出安卓包，得先把预设与构建模板搬回主工程**，再改 `version/code`。
40. **服务端入口只有一个域名：`game.learnest.cn`（2026-11-24 立）**：
    - 公网只走 **nginx + HTTPS**；`cloud-service`(8789) 与 `room-service`(8787) 只监听 `127.0.0.1`
      （代码里 `BIND_HOST` 默认 `127.0.0.1`，局域网手机调试时临时 `BIND_HOST=0.0.0.0`）。
    - 🔴 **19001 与 20000-20099 必须保持公网** —— 那是联机的裸 TCP 数据通道，**不经 nginx**，
      一起关掉联机直接全废（域名只解决 HTTP 那一段）。
    - 🔴 **改服务端地址后必须跑 `tests/_probes/https_probe.gd`**：`curl` 通 ≠ Godot 引擎通
      （mbedtls / 系统 CA / SNI 任一不对，引擎里就是失败而 curl 照样 200）。
    - 证书续期钩子 `/etc/letsencrypt/renewal-hooks/deploy/50-game-deploy.sh`（只管这个域名，
      与服务器上已有的 `20-`/`30-`/`40-` 并存）。
    - nginx 路由：`/room-service/*` → `127.0.0.1:8787`（**剥前缀**，服务端路由不用改），其余 → `127.0.0.1:8789`。

---

## 附录 A：设计约束与防坑（改代码前必读）

> 本附录汇总**不随版本变化的工程约束**：设计铁律、已踩过的坑、遗留问题、调参方法、关键坐标。
> 变更条目见 [CHANGELOG.md](CHANGELOG.md)；历史版本说明已摘编至此，包内不再单列。

### A.1 战斗层与表现层的契约

#### A.1.1 伤害出口只有两处

```gdscript
signal damaged(unit: BattleUnit, result: Dictionary)   # 一次挨打（含盾吸/减免/真掉血/击杀/闪避/免疫）
signal hp_drained(unit: BattleUnit, amount: float)     # 绕过 take_damage 的直接掉血（真伤/自损/地形扣血）
```

- `take_damage()` 外面包了一层，转调 `_take_damage_impl()`，**保证一次挨打只发一次 `damaged`**；
- `lose_hp()` 是**全工程唯一写 hp 的地方**（`hp -= amount` 只有 `battle_unit.gd` 一处），
  在那里兜底发 `hp_drained` → **出口完备，不会漏**；
- 用 `_in_damage` **计数**（不是布尔）避免 `take_damage` 内部的 `lose_hp` 重复通知
  —— 因为提前 return 会漏掉复位，布尔标志会卡住；
- 无订阅者时零开销，**不参与任何战斗计算**。

#### A.1.2 表现层两条铁律

1. **不读写战斗状态、不用随机数** —— 联机同步只认战斗层，掺进去会造成状态漂移；
2. **空闲时 `set_process(false)`** —— 棋盘上几十个棋子，空转成本会累积。

#### A.1.3 三个已踩过的坑（别再踩）

| 坑 | 现象 | 正确做法 |
|---|---|---|
| tween `_bone.position` / `_root` | 「抖一下就卡住」 | `unit_token._draw()` 每次重绘都会把这两个值写回格子中心，tween 被当场覆盖；**要位移就走 `_draw` 里的绘制偏移** |
| 飘字/碎裂挂在 token 自己身上 | 看不到击杀反馈 | 单位阵亡时棋盘**立刻回收** token；**要挂父节点**（三处界面 token 的父节点都是普通 `Control`，不是自动布局容器，挂父节点安全） |
| 在 `setup()` 里清 `_hp_ghost` / `_flash` | 受击动画被打断 | `setup()` **每次刷新都会调**，不能在里面对特效状态做清理 |
| 订阅方重复 `connect` | 运行时直接报错 | `BattleUnit` 是 `RefCounted`，而 `setup()` 每次刷新都会调；绑定前先查 `is_connected`，见 `unit_token._bind_unit()` |

#### A.1.4 编辑器报 `Identifier "X" not declared`

新增带 `class_name` 的脚本后若报此类错，是**编辑器全局类列表没刷新**
（打开项目那一刻扫的，不会热注册运行中新增的类），**不是代码错**。

- 编辑器：`项目 → 重新加载当前项目`
- headless：先跑一次 `--import`

### A.2 地形系统的实现要点

#### A.2.1 地形为什么曾经「完全不生效」

两个断点叠在一起：

1. 基类 `battle_base.board`（注释写明「board 由剧情关卡战斗注入（含地形层）」）
   **从未被赋值** —— `_build_board()` 只建了私有的 `_board`（供 BFS 算距离），没有 `board = _board`；
2. 即使赋了值也没用：`_build_board()` 只调 `add_cell()` / `set_obstacle()`，
   **从未把地形灌进格图** → `terrain_at()` 恒返回 0。

结果基类 `_sync_terrain()` 永远把 `terrain_id` 置 0，白灵殿地图上：

| 地形 | 格数 | 应有规则 | 修复前 |
|---|---|---|---|
| 森林 | 18 格 | 受击 ×0.8（免伤 20%）、移出耗 1 能量 | ❌ 按空地算 |
| 水域 | 12 格 | 回合末 −1 能量、禁位移类技能 | ❌ 按空地算 |
| 障碍（可破坏 / 不可破坏） | 12 + 40 格 | 不可通行 | ✅ 正常（走 `cells` 表） |

> **为什么以前测不出来**：`terrain_regression.gd` 前 6 项都是「手动给 `u.terrain_id` 赋值」
> 再测规则，**恰好绕过了"从棋盘同步"这一步**。9.13_v1 已补第 ⑦ 项堵上。

#### A.2.2 落位必须走 `_place()`

`_turn_ai()` / `_hunt_move()` / `_auto_advance_one()` 三处**曾经直接改 `u.cell`** ——
这样会导致 AI 移动与回合末牵引后地形 id 残留，出现「**站进森林却按空地算伤害**」的静默错算。

**约定**：改单位位置一律用 `_place(u, c)`（落位 + 同步地形），不要直接写 `u.cell = c`。

#### A.2.3 地形启用白名单

```gdscript
const STORY_ACTIVE := [FOREST, WATER, OBST_BREAKABLE, OBST_SOLID]
static func story_active(id: int) -> bool: return STORY_ACTIVE.has(id)
```

剧情关**只把"本关启用"的地形写进地形层**，其余一律写空地(0)。
这样沼泽/雪地/沙漠/山地/冰面即使出现在地图里也不会产生任何效果。

#### A.2.4 龙的水域豁免

```gdscript
const WATER_IMMUNE_DEFS := ["story_dragon"]
static func water_immune_def(def_id: String) -> bool: return WATER_IMMUNE_DEFS.has(def_id)
```

红方「龙」无视水域地形效果（不扣能量、禁位移技能对它无效）。
`battle_unit.gd` 侧由 `water_immune` 标志承接，并在 `dash_blocked_by_terrain()` 里提前返回 `false`。

#### A.2.5 可破坏障碍

- 拆障所需伤害：**受到一点伤害后即变为空地**；
- 蓝方**无**拆障权限，仅红方可拆（`breakable_in_range` / `can_break_any` / `_plan_break`）；
- 变空后格子可通行，且**不可重复拆**。

### A.3 遗留问题与调参

#### A.3.1 地形效果对难度的影响测出来几乎为零

9.12_v2 实测（200 局/格仿真，红方强 AI × 蓝方手忙脚乱）：

| 配置 | 蓝方胜率 | 平均回合 | 昊死亡率 | 祁死亡率 |
|---|---|---|---|---|
| v2 基线（9.12_v1，无地形） | 55.5% | 11.4 | 29.5% | 15.0% |
| 地形开（森林+水域） | 56.0% | 11.4 | 29.0% | 15.0% |
| 地形开 + 红方主动拆障 | **57.0%** | 11.5 | 28.0% | 15.0% |

→ **地形效果对难度的影响只有 ±1.5 个百分点，基本无效。**
（原因见 A.3.3：红方在几何上就追不上，地形救不了。）

#### A.3.2 拆障机制在实际对局中几乎触发不了

**50 局里红方只拆成功过 3 次障碍**（每局平均 **0.06 块**）—— 因为红方根本走不到障碍附近，
障碍都在它身后（地图中部的障碍是为了挡蓝方，不在红方的追击路径上）。

> **注**：此结论是 **9.12_v2 时代（昊在 (7,1)）** 测的。
> 9.12_v3 把昊移到 (0,1) 后，红方追击路径**穿过地图中部的障碍带**，本机制终于有机会真正被用上
> —— 但**尚未重新实测**，这是个待验证项。

#### A.3.3 「获胜太简单」的根因（9.12_v3 已解，保留推导供调参用）

**改动前（昊 (7,1)）：**

| 单位 | 起点 | 到逃生区 | 移动力 |
|---|---|---|---|
| 昊 | (7,1) | **11 步** | 1 步/回合 + 每 2 回合牵引 1 格 |
| 宵 | (-9,1) | 到昊 **16 步** | 2 步/回合 |
| 龙1 | (-10,-1) | 17 步 | 2 步/回合 |
| 熊2 | (-13,1) | 20 步 | 2 步/回合 |

**昊 11 步脱身、红方最近 16 步** —— 双方移动力只差 1 步/回合 → **红方在数学上追不上**。
这就是为什么 v1 的数值加强、v2 的地形效果都救不了难度。

**改动后（昊 (0,1) / 祁 (0,2)）：**

| 单位 | 起点 | 到逃生区 | **到昊(0,1)** |
|---|---|---|---|
| 昊 | **(0,1)** | **18 步** | — |
| 祁 | **(0,2)** | **18 步** | — |
| 宵 | (-9,1) | — | **9 步** |
| 龙1 | (-10,-1) | — | 10 步 |
| 龙3 | (-10,3) | — | 10 步 |
| 熊1 | (-12,-1) | — | 12 步 |
| 熊3 | (-12,3) | — | 12 步 |
| 熊2 | (-13,1) | — | 13 步 |

→ **红方离昊只有 9~13 步，而昊要走 18 步才到逃生区** —— 追得上，也必须打。

#### A.3.4 难度仿真结果与判读

**200 局/格仿真（`sim_v4.py`，红方强 AI）：**

| 配置 | 蓝方胜率 | 平均回合 | 昊死亡率 | 祁死亡率 |
|---|---|---|---|---|
| 改动前（昊 7,1 / 祁 5,2） | 55.5% | 11.4 | 29.5% | 15.0% |
| **改动后 · 蓝方手忙脚乱** | **1.0%** | 7.3 | **80.0%** | 19.5% |
| **改动后 · 蓝方完美护送** | **100.0%** | 12.0 | **0.0%** | 0.0% |

**怎么读这三个数：**

- ✅ **「太简单」已彻底解决** —— 从 55.5% 掉到 1.0%（差 AI 场景）；
- ⚠️ **但 1.0% 与 100.0% 是同一仿真的两个极端**：
  - 「蓝方手忙脚乱」= 蓝方有一半回合随机乱走、技能也随便放；
  - 「蓝方完美护送」= 蓝方每一步都最优。
- **两者的巨大落差说明：胜负现在完全由玩家水平决定，而不是数值** ——
  这正是战棋关该有的样子。真人玩家水平落在两者之间，**具体体感必须实测**。

#### A.3.5 难度调参速查（**不需要改任何代码**）

只改 `maps/白灵殿.json` 的 `spawns`：

| 体感 | 建议微调 |
|---|---|
| 太难（几乎必输） | 昊/祁 起点回退到 `x = 2~3`（`y` 不变），或红方出生点西移 1~2 格 |
| 刚好 | 保持不动 |
| 还想更难 | 红方出生点东移（如 `x = -6 ~ -3`），或叠加「守满 N 回合」条件 |

#### A.3.6 其他未动项

1. 4V4 数值平衡（护甲 vs 单体伤 1~3 的僵局）；
2. 李太白属性 / 虞美人母体子体完整规则；
3. 最高难度「豆包战术模型」的网络层真机联调。

#### A.3.7 AI 回合「同帧结算」，特效会挤在一帧（已知，未做）

`duel.gd` / `team_duel.gd` / `story_battle.gd` 都是 `_step()` 里**一次性**调 `_battle.run_step()`，
而 `run_step()` 会一路把 AI 行动**同步**算完才 return（4V4 回合里最多 4 个单位）。

| 场景 | 现在的表现 |
|---|---|
| 玩家自己攻击 | ✅ 特效完整可见 |
| AI 回合 | ⚠️ 伤害数字都会出（各单位在各自位置，不重叠），但**看不到"谁先打谁"的过程**，是同时爆出来的 |

**解法**：加一层**表现层回放队列** —— 战斗逻辑完全不动，UI 把伤害事件收进队列后逐条延时回放，
期间锁输入；血条按回放进度推进。**这会改变 AI 回合的节奏手感**，属设计决策，**需拍板后再做**。

#### A.3.8 骨骼受击动作（原 C 档，未做）

- 12 套骨骼（剑舞/追猎/龙王/流萤/孤狼/李太白/睡神/邪神/灵虚数影/药师/虞美人/光雨）
  目前**每套只有 1 个动作**，名字是 DragonBones 默认的 `newAnimation`；
- 运行时读的是 `assets/db/<hero>_bake.json`（**不是** `_ske.json`），
  `play_animation()` **无参数**、**不支持按名播放第二个动作** —— 要做得先扩展运行时；
- **剧情关兵种（昊/祁/大长老/战士/法师/宵/龙/熊）没有骨骼**，只能靠程序化反馈；
- 12 套部件命名完全不统一（`剑舞=09_head`、`龙王=13_head`、`李太白=头`、
  `光雨=部件集_part_01~08` 完全无语义），程序化生成受击动作要逐套人工核对。

**结论**：想要真正的「受击姿态」，只能在 DragonBones 里 K 再重新 bake
（唯一能保证和编辑器里一致的路径）。

### A.4 工程卫生：备份目录必须加 `.gdignore`

工程根目录下的备份目录（`_backup_912merge/`、`.workbuddy/backup_2026*/` 等）里的脚本副本
也会声明同名 `class_name`（BattleUnit / SkillEffects / BattleAI / GridBoard 等**共 14 个**）。
Godot **递归扫描整个工程目录**，于是：

```
Parse Error: Class "SkillEffects" hides a global script class.   at: skill_effects.gd:1
Compile Error: Failed to compile depended scripts.               at: main_ui.gd:0
ERROR: Failed to load script "res://scripts/ui/main_ui.gd"       ← 主菜单起不来
```

**更阴险的是**：跑测试会得到**假绿 `PASS 0 / FAIL 0`**（测试脚本自己就没编译成功），
看起来「跑过了」，其实一行都没执行。

**约定**：备份目录一律放一个**空文件** `.gdignore`
（Godot 官方机制：含该文件的目录对资源系统完全不可见）。**不删除任何文件**。

已加 `.gdignore` 的目录：`_backup_0928tutorial/`、`_backup_0930struct/`、`_backup_908merge/`、
`_backup_912merge/`、`_backup_913fix/`、`_backup_913v4merge/`、`_backup_918bleed_dur/`、
`_backup_918bleedfix/`、`_backup_doc_20260918/`、`.workbuddy/`。
⚠️ **新建备份目录必须同步补上 `.gdignore`**（2026-09-30 实测：漏建时先建后测，容易埋进"假绿"）。

### A.5 白灵殿关卡的关键坐标（改地图/调难度前先对照）

| 项 | 值 |
|---|---|
| 逃生区 | `x = 18, y = 0~3`（共 4 格，均为森林，可通行） |
| 昊（护送目标 1） | `story_hao`，起点 `(0, 1)` |
| 祁（护送目标 2） | `story_qi`，起点 `(0, 2)` |
| 蓝方最远起点 | 宵 `(-9, 1)` |
| 红方最远起点 | 熊2 `(-13, 1)` |
| 湖泊 / 龙水域豁免方 | 红方「龙」（`story_dragon`） |
| 拆障权限 | **仅红方**（蓝方为空） |

### A.6 上一版（9.13_v2）实测通过的回归基线

以下为 9.13_v2 包在本机跑出的结果，**本整合版沿用其代码**，可作为对照基线：

| 验证项 | 命令 | 9.13_v2 结果 |
|---|---|---|
| 逐文件语法检查 | `--check-only -s` × 59 个 `.gd` | ✅ 0 错 |
| 资源导入 | `--import` | ✅ 0 ERROR |
| 冒烟 | `--quit-after 2` | ✅ 0 SCRIPT ERROR |
| 1V1 战斗回归 | `-s res://tests/combat_regression.gd` | ✅ PASS 97 / FAIL 0 |
| 4V4 战斗回归 | `-s res://tests/team4v4_regression.gd` | ✅ PASS 58 / FAIL 0 |
| 地形回归 | `-s res://tests/terrain_regression.gd` | ✅ 7/7 PASS |
| 剧情关冒烟 | `-s res://tests/story_battle_smoke.gd` | ✅ PASS 28 / FAIL 0 |
| 掉血特效回归 | `-s res://tests/damage_fx_smoke.gd` | ✅ PASS 47 / FAIL 0 |
| 剧情关场景加载 | `res://scenes/StoryBattle.tscn --quit-after 40` | ✅ 0 SCRIPT ERROR |

> ⚠️ **上表是 9.13_v2 当时的历史基线，不等于当前值。**当前实际断言数已增长（2026-09-17 真机实测）：
> `damage_fx_smoke` 47 → **54**，并新增 `board_zoom_smoke` **18**。
> **当前该跑的六条命令与断言数见本文「三、运行与测试」。**

> `damage_fx_smoke.gd` 的 47 条断言覆盖：信号契约（只发一次 / 真伤兜底 / 全挡 hp_lost=0 / 免疫 / killed）·
> token 订阅与**防重复连接**/**换绑退订不串台** · 白条残影冻结→收敛→回血对齐 · 飘字生成 · 击杀碎裂 ·
> 空闲自动关 `_process` · **护盾分段换算 7 个用例**（无盾/未满/超限/**临界连续**/空值/巨盾/负值防御）·
> `HpShieldBar` 控件行为（首次对齐 / 掉血冻结 / 收敛 / **只加护盾不产生残影**）。

---

> 【文档纪律 —— 请勿删除本段】
> **1. 包内文档只有两份：`README.md`（现状 / 结构 / 进度 / 注意点 / 附录 A）与 `CHANGELOG.md`（版本变更）。**
>    **禁止再新建任何单版 / 过程说明文件** —— 即 `9.xx说明.md`、`9.xx_说明.md`、`9.xx整合版_说明.md`、
>    `*_说明.txt`、`某某可玩化_说明.txt` 这一类。**一个版本 = CHANGELOG 里的一段，不是一个新文件。**
>    2026-09-18 已把历史遗留的 **8 份**此类文件删除并合并进来（原件存于 `_backup_doc_20260918/`），
>    此前它们正是"每版一个新文件"累积出来的，**不要重蹈覆辙**。
> 2. **什么内容写哪里**（先对照这张表，再动手写）：
>
>    | 你要写的内容 | 写到这里 |
>    |---|---|
>    | 本版**改了什么**（新增/修复/改动/删除） | `CHANGELOG.md` **顶部**新增一段 `## [版本号] — 日期`，按 Added / Changed / Fixed / Removed 分类 |
>    | 版本间关系、基线、整合与合并过程 | 同上，写进对应版本的 CHANGELOG 段 |
>    | **进度 / 计划** | 本文件「二、进度与计划」 |
>    | **注意事项 / 防坑** | 本文件「四、注意点」（编号连续，别重号） |
>    | **设计约束 / 遗留问题 / 调参方法 / 关键坐标** | 本文件「附录 A」 |
>    | 临时验证过程、中间产物 | **不写文档** —— 放 `tests/*_tmp.gd` 或直接删掉 |
>
> 3. 每次打包**必须**更新本文件与 `CHANGELOG.md`，使二者与当下情况一致；
>    **未更新视为打包未完成**（同注意点 21）。
> 4. 若拿到某个压缩包，发现根目录**没有** `README.md`：按包内代码补一份，并把本段原样附在结尾。
> 5. 本文件同步到网盘「主程序」文件夹，随压缩包一起上传。
> 6. **本段自身不要复制到别处**（因为包内不该再有第三份文档）；发现有人新开了说明文件，按第 1 条合并回去并删除。
