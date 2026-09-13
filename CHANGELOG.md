# 更新日志 / CHANGELOG

> 本文件记录每个版本相对上一版的变更，用于跨会话与跨人追溯。
> 格式参照 [Keep a Changelog]：每版本分 **Added / Changed / Fixed / Removed** 四类。
> 项目"现状/进度/计划/注意点"见 [README.md](README.md)；历史变更在这里。

> ⚠️ 本压缩包根目录必须有一份 [README.md](README.md) 说明文件（含自传播提醒），详见 README 末尾。

## [9.13整合版] — 2026-09-13（v1 + v2 + v3_昊祁移中 + v4 全量合并）

**一句话**：9.13 当天 4 个包**不是一条迭代线**，其中 v4 与 v2 同版本号却基线不同，
直接推送任何一个都会丢功能；本版把 4 个包的全部更新内容合并为一个当日整合版。

> **基线 = `9.12代码_v1_白灵殿难度调整`**（也是 v1/v2/v3/v4 的共同祖先）。
> 本段是 9.13 整合的**完整记录**（含合并方式与冲突判定）。
> 改代码前请先读 [README.md](README.md) 的「附录 A：设计约束与防坑」。

### 当日版本关系（实测）

| 包名 | 基线 | 是否迭代 |
|---|---|---|
| `9.13代码_v1_白灵殿修复` | 9.12_v1 | — |
| `9.13代码_v2_掉血特效与护盾血条` | 9.13_v1 | ✅ v1 → v2 |
| `9.13代码_v3_昊祁移中` | **9.12_v2**（跨日） | ❌ 与 v2 **平行** |
| `9.13代码_v4_掉血特效与护盾血条` | **9.12_v1** | ❌ 与 v2 **同号平行** |

> ⚠️ **本项目多人并行开发，同日多包常互为平行线**。版本号只是"当天第几次发包"的序号，
> **不代表迭代关系**。判断两个包的关系必须看**基线**，不能看名字或版本号。
> 后续发包建议在备注里写明基线（如 `9.14代码_v1_某某_基线9.13整合版`）。

### Fixed（v4 打包遗漏，本版补回）

- **`9.12_v2` 地形可破坏与龙水域豁免整体丢失** —— v4 中 `Terrain.story_active`、
  `WATER_IMMUNE_DEFS`、`battle_unit.gd` 的 `water_immune` 均为 **0 次**：
  - `scripts/combat/terrain.gd`：补回 `STORY_ACTIVE` / `story_active()` / `WATER_IMMUNE_DEFS` / `water_immune_def()`
  - `scripts/combat/battle_unit.gd`：补回 `water_immune`（7 处）与 `dash_blocked_by_terrain()` 豁免分支
  - `scripts/combat/battle_story.gd`：补回拆障系统（`BREAKABLE` / `OBSTACLE_HP` / `_plan_break` /
    `breakable_in_range` / `can_break_any` / `damage_obstacle`）与 `Terrain.story_active` 地形门禁
  - `scripts/ui/story_battle.gd`：补回拆障 UI（3 处）
- **`tests/story_regression.gd` 整个文件缺失** —— 已从 v3 补回（9010 B，12 组断言）。
- **`maps/白灵殿.json` 昊/祁 出生点被回退** —— v4 仍是 `(7,1)` / `(5,2)`，
  已合入 v3 的 `(0,1)` / `(0,2)`（难度根因解法，仿真蓝方胜率 55.5% → 1.0%~100%）。
- **`story/骑士线_剧情.md`** 内容回退 —— 已取 v3 版（69 行）。

### Added

- `scripts/ui/damage_fx.gd`、`scripts/ui/hp_shield_bar.gd`（v4 新增，保留）
- `tests/damage_fx_smoke.gd`（47 断言）、`tests/story_battle_smoke.gd`（28 断言）

### Changed

- `scripts/combat/battle_story.gd`：4 处合并冲突已手工判定，采用
  **v3 的 `Terrain.story_active` 门禁 + v4 的 `set_cell_terrain()` 一次同步**（9.13_v1 修复），
  落位统一用 v4 的 `_place()` 封装。
- `scripts/combat/battle_unit.gd`：1086 行，v3 的 `water_immune` + v4 的 `damaged`/`hp_drained` 信号并存。
- `scripts/ui/story_battle.gd`：988 行（v3 拆障 UI + v4 盾条接入）。
- `scripts/ui/story_battle_board.gd`：取 v3 版（含 `var p: BattleUnit` 类型推断 P0 修复）。

### Removed（文档收敛）

- 删除 7 份单版/过程说明：`9.12_v2说明.md`(415 行)、`9.12_v3说明.md`(179)、
  `9.13_v2特效版_说明.md`(187)、`9.13修复版_说明.md`(193)、`9.10整合版_说明.md`(204)、
  `9.12整合版_说明.md`(110)、`白灵殿可玩化_说明.txt`(121，自标"已作废")。
  其独有内容（设计约束 / 防坑 / 遗留问题 / 调参）**已并入 README「附录 A」**，
  变更条目已并入本 CHANGELOG。**包内文档收敛为 README + CHANGELOG 两份。**

### 合并过程（备查）

**骨架 = v4**（当日最新，且包内中文文件名映射最完整）。
三方合并基线取 **`9.12代码_v1_白灵殿难度调整`**（v1/v2/v3/v4 共同祖先）。

| 文件 | 合并方式 | 冲突 | 结果 |
|---|---|---|---|
| `scripts/combat/battle_unit.gd` | 三方合并 | **0** | 1086 行；v3 的 `water_immune`(7) + v4 的 `damaged`/`hp_drained` 全保留 |
| `scripts/combat/battle_story.gd` | 三方合并 | 4（手工判定） | 885 行；拆障系统 + `story_active` 门禁 + v4 的 `_place()` 全保留 |
| `scripts/ui/duel.gd` | 三方合并 | **0** | 1435 行（= v4） |
| `scripts/ui/story_battle.gd` | 三方合并 | **0** | 988 行（v3 拆障 UI + v4 盾条） |
| `scripts/ui/team_duel.gd` | 三方合并 | **0** | 1356 行（= v4） |
| `scripts/ui/unit_token.gd` | 三方合并 | **0** | 423 行（= v4 特效本体） |
| `scripts/ui/story_battle_board.gd` | 三方合并 | **0** | 262 行（= v3，含 P0 修复） |
| `scripts/combat/terrain.gd` | 取 v3 版 | — | 含 `STORY_ACTIVE` + `WATER_IMMUNE_DEFS` |
| `tests/terrain_regression.gd` | 三方合并 | **0** | 122 行（= v4，已含第 ⑦ 项） |
| `tests/story_regression.gd` | 从 v3 补回 | — | 9010 B（v4 完全缺失） |
| `maps/白灵殿.json` | v4 结构 + v3 出生点 | — | 昊 `(0,1)` / 祁 `(0,2)` |
| `story/骑士线_剧情.md` | 三方合并 | **0** | 69 行（= v3） |

**4 处冲突的判定依据：**

| # | 位置 | v4 写法 | v3 写法 | 取用 | 理由 |
|---|---|---|---|---|---|
| 1 | `_build_board()` 地形灌图 | `set_cell_terrain(c, int(cells[k]))` | `set_terrain(…)` + `set_obstacle()` | **两者合并** | v3 的 `story_active` 门禁必须保留；v4 的 `set_cell_terrain()` 是 9.13_v1 的"地形+障碍一次同步"修复，更优。最终写法：`_board.set_cell_terrain(c, t if Terrain.story_active(t) else Terrain.EMPTY)` |
| 2 | `_hunt_move()` 落位 | `_place(h, dest)` | `h.cell = dest; _sync_terrain(h)` | **v4** | 语义等价，`_place()` 更简洁 |
| 3 | `_auto_advance_one()` 牵引 | `_place(u, cell)` | `u.cell = cell; _sync_terrain(u)` | **v4** | 同上 |
| 4 | `_turn_ai()` 移动 | `_place(u, best)` | `u.cell = best; _sync_terrain(u)` | **v4** | 同上 |

### 校验

- 全部 `.gd` 括号配对静态扫描 ✅ 0 异常；合并冲突标记残留 ✅ 0 条；
- 逐特性计数比对 **16 项全部 ✅**：

  | 特性 | 来源 | 合并前 v3/v4 | 合并后 |
  |---|---|---|---|
  | `water_immune`（龙免水域） | v3 ← 9.12_v2 | 7 / **0** | 7 ✅ |
  | `dash_blocked_by_terrain()` | 共有 | 2 / 2 | 2 ✅ |
  | `damaged` 信号 | v4 ← 9.13_v2 | 0 / 5 | 5 ✅ |
  | `hp_drained` 信号 | v4 ← 9.13_v2 | 0 / 3 | 3 ✅ |
  | `_take_damage_impl` / `_in_damage` | v4 ← 9.13_v2 | 0 / 3,5 | 3,5 ✅ |
  | `story_active()` 地形门禁 | v3 ← 9.12_v2 | 1 / **0** | 1 ✅ |
  | `BREAKABLE` / `damage_obstacle` | v3 ← 9.12_v2 | 3,3 / **0,0** | 3,3 ✅ |
  | `breakable_in_range` / `can_break_any` | v3 ← 9.12_v2 | 4,2 / **0,0** | 4,2 ✅ |
  | `_plan_break` / `human_move` | v3 ← 9.12_v2 | 2,3 / **0,0** | 2,3 ✅ |
  | `set_cell_terrain()` 地形接线 | v4 ← 9.13_v1 | 2 / 1 | 4 ✅ |
  | `var p: BattleUnit`（P0 修复） | v3 ← 9.13_v1 | 0 / 1 | 1 ✅ |
  | `HpShieldBar`（盾条接入） | v4 ← 9.13_v2 | 0 / 4 | 4 ✅ |
  | `unit_token.gd` 特效行数 | v4 ← 9.13_v2 | 228 / 423 | 423 ✅ |
  | 拆障 UI（`story_battle.gd`） | v3 ← 9.12_v2 | 3 / **0** | 3 ✅ |
  | `tests/story_regression.gd` | v3 | 有 / **无** | 有 ✅ |
  | 昊/祁 出生点 | v3 | `(0,1)/(0,2)` / `(7,1)/(5,2)` | **`(0,1)/(0,2)`** ✅ |

- ⚠️ **未跑真机 `godot --headless`**（沙箱无 win64 运行环境），本地需补跑：

  ```
  godot --headless --path . --import
  godot --headless --path . --quit-after 2
  godot --headless --path . -s res://tests/combat_regression.gd        # 1V1    97 断言
  godot --headless --path . -s res://tests/team4v4_regression.gd       # 4V4    58 断言
  godot --headless --path . -s res://tests/terrain_regression.gd       # 地形   7 项
  godot --headless --path . -s res://tests/story_regression.gd         # 剧情  12 组（本版补回）
  godot --headless --path . -s res://tests/story_battle_smoke.gd       # 剧情关 28 断言
  godot --headless --path . -s res://tests/damage_fx_smoke.gd          # 特效+盾条 47 断言
  ```

  **重点验证**：`battle_story.gd` 是本版唯一做手工判定的文件（4 处冲突），
  `story_regression.gd` + `story_battle_smoke.gd` 正好覆盖它。

---

## [9.13代码_v2_掉血特效与护盾血条] — 2026-09-13

**一句话**：新增「掉血动态特效」与「护盾并入血条显示」，并给战斗层补上伤害事件信号。
**纯表现层新增 + 一处战斗层信号，不改任何数值与战斗规则。**

> 基线 = `9.13代码_v1_白灵殿修复`。

### Added

- **战斗层伤害信号**（`scripts/combat/battle_unit.gd`）：
  - `damaged(unit, result)` —— 一次「挨打」的完整结算（含盾吸 / 减免 / 真掉血 / 击杀 / 闪避 / 免疫）；
  - `hp_drained(unit, amount)` —— 绕过 `take_damage` 的直接掉血（真伤 / 自损 / 回合末地形扣血）。
  - `take_damage()` 外面包一层转调 `_take_damage_impl()`，保证一次挨打**只发一次** `damaged`；
    `lose_hp()` 是全工程唯一写 hp 的地方，在该处兜底通知 → **信号出口完备，不会漏**。
  - 无订阅者时零开销，**不参与任何战斗计算**（联机同步不受影响）。
- **掉血特效**（`scripts/ui/unit_token.gd` —— 三个界面共用 token，改这一处全生效）：
  - **伤害飘字**：真掉血 `-3`（红色，≥3 放大）／全挡 `挡 2`（蓝灰）／`闪避`／`免疫`／击杀 `击破`（金色大字）；
  - **受击闪红**：modulate 脉冲，0.20s 衰减，骨骼棋子一起闪；
  - **血条白条残影**：绿条先掉，白条滞后 0.20s 再收拢 —— 一眼看出这一下掉了多少；
  - **击杀碎裂**：圆环扩散淡出（挂父节点，不受 token 被回收影响）。
- **护盾并入血条**（新增 `scripts/ui/hp_shield_bar.gd`，`class_name HpShieldBar`）：
  - `hp + shield ≤ max_hp` → 护盾按点数等比占位，血条不满，剩余留空；
  - `hp + shield > max_hp` → 铺满整条，按 `hp : shield` 比例分配长度；
  - 两式在 `total == max_hp` 处**取值相同（连续）**，护盾刚好看满条时不跳变；
  - 顺序 **hp 在左、护盾在右**（护盾作为外层缓冲接在血量后面）；
  - **护盾变化不做任何动效**（只有 hp 掉才有白条残影）；
  - **头顶血条与右侧信息栏血条同时生效**，1V1 / 4V4 / 剧情关三处一体。
- 新增 `scripts/ui/damage_fx.gd`（`class_name DamageFx`）——表现层共用工具：
  - `hp_shield_layout()`：hp/shield/max 换算成（分母, hp 占比, shield 占比），头顶与侧栏共用同一套算式；
  - `ease_bar()`：侧栏血条缓动 —— 涨立即到位 / 跌 0.38s 平滑滑落。
- 新增 `tests/damage_fx_smoke.gd`（**47 条断言**）：信号契约 + token 特效 + 护盾分段换算 + 控件行为。

### Changed

- 侧栏**生命条**由 `ProgressBar` 换成 `HpShieldBar`（**能量条 / 理智条不变**）；
- `_make_bar(..., tiled := false)`、`_update_bar(..., shield := 0.0)` 新增可选参数 —— **老调用点不受影响**；
- README 新增注意点 19、20（特效接入约定 / 护盾血条规则）。

### 已知限制（本版未做，待拍板）

- ⚠️ **AI 回合仍是"同帧结算"**：`run_step()` 会把 AI 全部行动**同步**算完才 return →
  AI 回合的伤害特效会**同时出现**（各单位在各自位置显示，不会重叠，但看不到"谁先打谁"的过程）。
  玩家自己操作的回合特效是完整可见的。要看到过程必须加**表现层回放队列**
  （战斗逻辑不动，UI 收集事件后逐条延时回放 + 期间锁输入），**这会改变 AI 回合的节奏手感**，
  属设计决策，本版未做。
- **位移抖动（FX_SHAKE）默认关闭**：程序化刚性位移达不到 DragonBones 骨骼动作的效果，用户已决定不做。
  真要开：`unit_token.gd` 里改 `FX_SHAKE = true`。
- **骨骼受击动作（原 C 档）未做**：12 套骨骼目前**每套只有 1 个动作**（DragonBones 默认名 `newAnimation`），
  且运行时不支持按名播放多动作；另剧情关兵种（昊/祁/长老/战士/法师/宵/龙/熊）**没有骨骼**，只能靠程序化反馈。

## [9.13代码_v1_白灵殿修复] — 2026-09-13

**一句话**：补齐 9.12 遗漏的三处缺陷——白灵殿关卡此前**根本打不开**（UI 脚本编译失败），
剧情关地形系统**整体空转**，以及备份目录污染工程导致**游戏本体无法启动**。
本版为纯修复，**不改任何数值与机制**。

> 基线 = `9.12代码_v1_白灵殿难度调整`。来源：9.12 交付后做本机 `godot --headless`
> 完整验证（9.12 的校验只做了静态括号配对检查，抓不到下面这三类问题）。

### Fixed

- **【P0】白灵殿关卡打不开**（`scripts/ui/story_battle_board.gd:203`）：
  `for pu in [protect_unit, protect_unit2]: var p := pu`
  —— 无类型 Array 的元素推为 Variant，`var p := pu` 无法推断类型 →
  该文件编译失败 → 依赖它的 `story_battle.gd` 连带失败 →
  `StoryBattle.tscn` 整个 UI 建不起来（`rp_child` 为 null、标签赋值到 Nil）。
  **修法**：`var p: BattleUnit = pu`。
  **影响**：9.12 交付包里主菜单可进，但「骑士线第一关」点进去是坏的。

- **【P1】剧情关地形效果全部失效**（`scripts/combat/battle_story.gd`）：
  基类 `battle_base.board` 从未被赋值（只建了 `_board` 供 BFS 用），
  且 `_build_board()` 从未把地形灌进格图（只调 `add_cell`/`set_obstacle`），
  导致 `terrain_at()` 恒返回 0、`_sync_terrain()` 永远把 `terrain_id` 置 0。
  白灵殿地图上的 **18 格森林（受击 ×0.8、移出耗 1 能量）** 与
  **12 格水域（回合末 −1 能量、禁位移技）** 全部按空地结算。
  **修法**：
  1. `_build_board()` 改用 `_board.set_cell_terrain(c, t)`（地形 + 障碍一次同步）并 `board = _board`；
  2. `_init()` 里 `_spawn_units()` 之后对所有单位 `_sync_terrain()`（出生即同步）；
  3. 新增 `_place(u, c)` 辅助函数（落位 + 同步地形），
     把 `_turn_ai()` / `_hunt_move()` / `_auto_advance_one()` 三处**直接改 `u.cell`** 的写法全部换掉
     —— 否则 AI 移动与回合末牵引后地形 id 会残留，出现「站进森林却按空地算伤害」的错算。

- **【P0】备份目录污染工程 → 游戏本体无法启动**：
  工程根目录下 `_backup_912merge/`、`.workbuddy/backup_2026*/` 里的脚本副本
  也声明了同名 `class_name`（BattleUnit / SkillEffects / BattleAI / GridBoard 等 **14 个**），
  Godot 递归扫描后报 `Class "X" hides a global script class` → `skill_effects.gd` 解析失败
  → `main_ui.gd` 编译失败 → **主菜单起不来**；跑测试则得到假绿 `PASS 0 / FAIL 0`。
  **修法**：给这些目录各放一个空文件 `.gdignore`（Godot 官方机制，目录对资源系统不可见），
  不删除任何文件。

### Added

- `tests/story_battle_smoke.gd` —— 剧情关无头冒烟测试（28 条断言）：
  地图/阵营/逃生区/双人护送目标/到逃生区步数**/地形接线**/AI 打满全场/胜负收敛。
- `tests/terrain_regression.gd` 新增 **第 ⑦ 项**：棋盘 → `terrain_id` 同步链路断言。
  （前 6 项都是「手动给 `u.terrain_id` 赋值」后测规则，**绕过了同步这一步**，
  这正是地形 bug 长期无人发现的原因。）
- `_backup_913fix/`：本次修改前的 `story_battle_board.gd` 与 `battle_story.gd` 原始副本（含 `.gdignore`）。

### Changed

- 逐文件语法检查扩展为全量 56 个 `.gd`（`--check-only`），全部通过。
- README 更新：断言数修正（1V1 `71→97`、4V4 `52→58`）、补充 `--import` / `--check-only` 用法、
  新增「备份目录必须带 `.gdignore`」注意点。

### 遗留问题（未解决，沿自 9.12）

- 白灵殿「获胜太简单」的**根因仍未解决**：红方出生点离逃生区太远（最近 27 步 vs 昊 11 步），
  纯追击需 16 回合而昊 7~8 回合就能脱身 → 数学上追不上。三选一待拍板：
  ① 挪红方出生点到地图中部；② 胜利条件改「守满 N 回合」；③ 在 x≈10~12 加通路阻塞。
- ⚠️ 本版把地形接上后，白灵殿的**实际手感会变**：森林免伤会让蹲森林的白灵殿更扛打、
  森林移出耗能与水域回合末耗能会拖慢移动。**这会影响上述难度平衡的判断**，
  建议下次调难度时把地形效果一并纳入考虑。

## [9.12代码_v1_白灵殿难度调整] — 2026-09-12

**一句话**：按《角色属性与技能表2.0.xlsx》重做白灵殿平衡（蓝方削弱 / 红方加强），
逃生区收缩为地图最右侧 4 格，胜利条件改为「昊与祁都存活并同时抵达逃生区」。

### Changed

- **数值全量替换为属性表 2.0**（`scripts/combat/story_defs.gd`）：
  - 蓝方（白灵殿，削弱）：战士 `hp 8→7`、`speed 114→100`；法师 `speed 113→95`；
  - 红方（魔渊，加强）：宵 `不灭` 无法行动阈值 `50%→10%`、回合末 `+1血+5能量`；
    龙 `hp 7→8`、`speed 115→110`、回合末 `+2能量`；熊 `speed 110→90`。
- **技能改动**（`scripts/combat/skill_effects.gd`）：
  - 战士：`坚固` 免伤持续 `3→2` 回合；`引雷` 目标数 `3→2`；
  - 法师：`灵动` 射程 `4→3`；`赤诚` 目标数 `3→2`；
  - 大长老：`强权` 畏惧每层减速 `-10→-5`；`灵震` 眩晕 `2→1` 回合；
  - 宵：`可燃点` 伤害加成 `+20%→+30%`、回能 `5→10`、耗能 `1→4`；
    `炎拳` 伤害 `3→5`；`炼狱` 追加「全体单位各受 1 点真伤」；
  - 龙：`角钻` 射程 `2→4`、伤害 `1→2`；`龙息` 真伤 `1→2`；
  - 熊：`炎爪` 射程 `1→2`、伤害 `1→2`；`炎牙` 射程 `1→2`、伤害 `2→3`、新增速度 -10（持续 2 回合）。
- **逃生区收缩**（`battle_story.gd`）：由「`x >= 16` 整列带（12 格）」改为固定 4 格
  `x=18, y=0~3`（新增常量 `ESCAPE_CELLS`，移除 `ESCAPE_X`）。**注意：逃生区变小但离昊更近了**
  （昊到最近逃生格 9→11 步的表述有误，详见下方「遗留问题」——实为 9→11 步变远 2 步）。
- **胜利条件改为双人护送**：`昊` 与 `祁` 必须**都存活**且**都站在逃生区格上**才判胜；
  任意一人阵亡立即判负（新增 `escort_qi`、`_is_escorted()`、`hao_arrived()`、`qi_arrived()`）。
- **祁也受核心牵引**（新增 `QI_AUTO_EVERY = 3`，昊保持 2），AI 追击目标改为「两个护送目标里更近/更脆的那个」。

### Added

- `BattleStory.escort_qi` 字段 + `escort_focus()`（AI 集火血量最低的护送目标）；
- `BattleStory.ESCAPE_CELLS`、`FEAR_SPEED_PER_LAYER`、`QI_AUTO_EVERY`、`QI_AUTO_DIR` 常量；
- UI：顶栏同时显示昊/祁各自进度（`_escort_txt`、`_auto_tip`）；棋盘双金环（已就位转青色环）。

### ⚠️ 遗留问题（重要，需下次处理）

**本轮仿真发现：白灵殿「太简单」的根因不是数值，而是地图几何 + 移动力。**

| 单位 | 到逃生区步数（新） | 说明 |
|---|---|---|
| 昊（起点 7,1） | **11 步** | 1 步/回合 + 每 2 回合牵引 1 格 |
| 祁（起点 5,2） | **13 步** | 2 步/回合 + 每 3 回合牵引 1 格 |
| 宵（起点 -9,1） | **27 步** | 2 步/回合 |
| 龙（起点 -10,-1） | 28 步 | 2 步/回合 |
| 熊（起点 -13,1） | 31 步 | 2 步/回合 |

红方落后昊 **16 步**，且双方移动力只差 1 步/回合 → **红方在数学上追不上**（纯追击需 16 回合，
而昊 7~8 回合就能脱身）。因此无论怎么加强红方数值，只要玩家沿右路直走，本关都会轻松通过。
**加数值只能延长「打了也白打」的时间，不能改变胜负。**

可行的三种解法（需用户拍板，本轮未实施）：

1. **挪红方出生点**：把宵/龙/熊整体向东平移到地图中部（如 x = -2 ~ 2），让追击有意义；
2. **改胜利条件为「守满 N 回合」或「昊祁抵达后需再守 2 回合」**，让红方有时间咬到人；
3. **加通路阻塞**：在昊东侧（x ≈ 10~12）加一道障碍/关卡窄口，迫使蓝方减速或绕路。

## [9.10代码_v3_整合版] — 2026-09-10 当日整合（合并 v1 白灵殿可玩化 + v2 地形与武器系统）

### 版本关系（合并前实测，重要）

**9.10 的 v1 与 v2 不是迭代关系，是从 `9.09代码_v1_图鉴与故事系统` 分出的两条平行分支。**

| 包 | 基线 | 独有内容 | 是否含另一支 |
|---|---|---|---|
| `9.10代码_v1_白灵殿可玩化` | 9.09 | 白灵殿 7V10 护送关（6 新文件）+ 17 剧情技能 | ❌ 无地形/武器 |
| `9.10代码_v2` | 9.09 | 地形系统 + 武器系统（62 新文件） | ❌ **丢失 v1 的白灵殿 6 文件** |

证据：v2 相对 9.09 无 v1 的 6 个新文件；v1 `skill_effects.gd`=101482 B 而 9.09/v2 均 82423 B；v2 的 CHANGELOG 缺 `[9.10代码_v1]` 段（回退到 9.08_v2）。

### Added

- 合并 v1 的白灵殿可玩关卡：`scenes/StoryBattle.tscn`、`scripts/combat/battle_story.gd`、`scripts/combat/story_defs.gd`、`scripts/ui/story_battle.gd`、`scripts/ui/story_battle_board.gd`、`白灵殿可玩化_说明.txt`；
- 合并 v1 的 `skill_effects.gd`（17 个剧情主动技能，`s1_` 前缀）与 `story_video_knight.gd`（`NEXT` → `StoryBattle.tscn`）；
- 保留 v2 的 `scripts/combat/terrain.gd`、`scripts/combat/weapons.gd`、`tests/terrain_regression.gd`、`story/武器系统_设计.md` 与全部 `.import` 文件；
- **补回打包遗漏 `installer/`**（`战棋.iss` / `战棋-使用说明.txt` / `战棋证书.cer`）：9.09、v1、v2 三包均缺失，从 `9.07代码_v4_整合版` 取回，`战棋.iss` MD5 = `d90becbe7afe3448ca8c2262e3939ea4`。

### Changed

- `scripts/combat/battle_unit.gd` 三方合并（base=9.09，ours=v2，theirs=v1）**零冲突**：同时具备 v2 的 `terrain_id` / `equipment` / `exit_energy_cost` / `dash_blocked_by_terrain` / `_terrain_end_turn` 与 v1 的 `init_flags` / `energy_guard`（泉涌）/ `guard_note`；
- `story/骑士线_剧情.md`：取 v1 的「护送逃生型」胜利条件正文，并套用 v2 的「工程线→凛黎线」改名；
- README 头部改为本版并新增「零之一、9.10 当日版本关系与整合说明」。

### 合并方式与校验

- 工具：`git merge-file -p OURS BASE THEIRS`（仅 `battle_unit.gd` 需要，`骑士线_剧情.md` 手工合成）；
- 静态检查：55 个 `.gd` 括号配对与缩进通过；`res://` 引用除 3 处模板字符串外无缺失；`skill_effects.gd` 对战斗层/单位层跨文件调用 0 处悬空；
- 固定校验值：`installer/战棋.iss` = `d90becbe7afe3448ca8c2262e3939ea4` ✅；`maps/白灵殿.json` = `144a0f75e3624e78426c511d777ab6d5` ✅（9.06 剧情系统重写后的新值，三包一致）。
- ⚠️ 沙箱无 wine，**未跑 `godot --headless` 冒烟与回归**（Godot 为 win64 exe）。本地需补跑 `combat_regression.gd` / `team4v4_regression.gd` / `terrain_regression.gd`。

### Known

- 武器技能效果（黄金圣甲/黄金剑斩/魂归/迷魂/能爆/万灭归一/审判/圣环）仍未实现；
- 地形视觉效果只有棋盘底色，缺图标与悬停说明；
- 白灵殿关仿真偏易（见 [9.10代码_v1] 的 Known）。

---

## [9.10代码_v2] - 2026-09-10 · 地形效果系统 + 武器系统（包内《更新说明.txt》自述为 v1）

> 本段内容依据 v2 包内 `更新说明.txt` 补记（原包 CHANGELOG 未写本段，属于说明文件遗漏）。

### Added

- **地形效果系统**：新增 `scripts/combat/terrain.gd`（0 空地 / 1 可破坏障碍 / 2 不可破坏障碍 / 3 森林 / 4 沼泽 / 5 水域 / 6 雪地 / 7 沙漠 / 8 山地 / 9 冰面）。规则（乘法叠加）：森林格内免伤 20% 且移出额外消耗 1 能量；沼泽速度 −30、移出 +1 能量；山地伤害 +30%、移出 +2 能量；水域禁止位移类技能、回合末 −1 能量；沙漠禁止位移类技能、回合末 −0.5 生命；冰面进入后沿方向滑行至离开。能量不足则无法从森林/沼泽/山地移出。
- `GridBoard` 加地形层（`set_cell_terrain` / `terrain_at` / `slide_end`）；`battle_base` / `battle_team` 接入移动代价、冰面滑行、位移门禁、伤害与速度修正、回合末结算；4V4 棋盘按地形上色（`team_board.TERRAIN_COL`）。
- **4V4 开局地形生成**（不对称但公平）：中央必刷 1~2 个强地形；每侧半场 5~8 格含 2~3 个本局负面地形（水域/沙漠随机一种）。公平机制用价值分总账（森林/沼泽 3、山地 4、冰面 2、水域/沙漠 −2），重掷至左右总价值相等（上限 120 次）。实测 40 局左右差值全为 0。
- **武器系统数据落地**：新增 `scripts/combat/weapons.gd`（13 件：超神器 3 / 终极神器 3 / 神器素材 6 / 专属 1），武器图鉴由占位改为真数据。获取链路：小星星→神器（素材 6 件，可装备），大星星→超神器（3 件），超神器×2→终极神器；已删除「神器素材→超神器」合成链。
- **装备与详情 UI**：拾取即装备，棋子下方显示武器名（最多 3 件 + N）；移除头顶印记/状态徽章；右键棋子详情弹窗新增「装备」「所在地形」；右键星星格可查看内含武器；弹窗 `z_index` 置顶；手机端长按 0.48 秒 = 右键。
- 新增 `tests/terrain_regression.gd`（地形专项回归）、`story/武器系统_设计.md`。

### Changed

- 剧情分支「工程线」正式更名「凛黎线」（视频与世界观文档同步改名，`main_ui.gd` / `story_video.gd` 内引用一并更新）。
- 图鉴详情页按钮改为「背景」（无文档者置灰）/「英雄故事」/「返回」；英雄故事支持多篇（`story/stories/{id}/*.txt`，多篇先弹目录）。
- 合并 9.08 内容：追猎「流炎飞弹」、`duel.gd` 血条 float 修复、龙王「凝晶为刃」。

### Known

- 武器技能效果未实现；装备上限与合成入口 UI 未定；武器"刷出来"的规则待定；
- 地形缺图标/悬停说明；6 位英雄缺动态海报素材、10 位缺小传；
- 本包**打包时整体丢失 v1 的白灵殿可玩化 6 个文件**（见上一段整合说明）。

---

## [9.10代码_v1] - 2026-09-10 · 骑士线第一关「白灵殿」可玩化

### Added
- **骑士线第一关从"展示沙盒"变成可玩关卡**：新增 `scenes/StoryBattle.tscn` + `scripts/ui/story_battle.gd`（对局界面，沿用 4V4 `team_duel.gd` 的顶栏＋左棋盘＋右信息卡结构），开场动画播完直接进关（`story_video_knight.gd` 的 `NEXT` 由 `StoryMap.tscn` 改为 `StoryBattle.tscn`）。
- **`scripts/combat/battle_story.gd`**（`class_name BattleStory extends BattleBase`）：7V10 护送关战斗管理器。地图来自 `maps/白灵殿.json`（296 格自由拼格），逃生区 = `x ≥ 16` 的可通行格；胜负 = 昊踏入逃生区／昊阵亡／一方全灭。
- **`scripts/combat/story_defs.gd`**：8 个剧情兵种登记表（昊/祁/大长老/战士/法师/宵/龙/熊），数值取自《角色属性与技能表.xlsx》，与 `HeroDefs`（14 位可收集英雄）完全隔离，不进选人池／图鉴／匹配。
- **17 个剧情主动技能实装**（`skill_effects.gd` 的 DATA + EFFECTS + 效果函数，全部 `s1_` 前缀，无 id 冲突）。
- **`scripts/ui/story_battle_board.gd`**：自由拼格地图棋盘控件（bbox 自适应缩放、滚轮缩放、拖动平移、逃生区高亮、护送目标金色光环、多目标已选高亮）。
- **战况条**：棋盘下方一排单位徽标，点一下把镜头挪过去（32×12 的大图很容易看丢人）。
- **昊的「不受控前进」**：每 2 回合末自动向东（逃生区方向）挪 1 格，玩家无法阻止；撞地形／被单位挡住则原地不动并写战报。常量 `BattleStory.HAO_AUTO_EVERY` / `HAO_AUTO_DIR` 可调（改 0 = 关闭）。

### Changed
- **`battle_unit.gd`**：`def["init_flags"]` 开局状态标记（大长老 `energy_guard` 能量抵消致命伤、宵 `lock_min_hp` 锁 1 血）；`hit_events` / `guard_note` 供战报输出。
- **红方 AI**：移动改用 `_hunt_move`（能咬住昊就追昊，追不上就奔袭逃生区拦截），并通过 `llm_tactics.focus` 让 AI 集火昊；多目标技会打满目标数（原先 AI 只打 1 个，2~3 目标技被用成单体）。
- **法师「关怀」** 不再标 `self_buff`（否则会被当成无目标自增益空放），改为点选射程内的伤员友军。

### Known
- 沙箱无 Godot 可执行，只做了静态检查（缩进/括号/`res://` 引用）＋ Python 规则仿真，**未跑 `godot --headless` 冒烟**。
- 仿真显示本关偏易：昊 1 步/回合时约 6 回合脱身（开启自动前进后由 9 降为 6），蓝方 10 人真伤输出远高于红方 1~2 点物理伤害（红方普攻会被蓝方 1~2 点护甲完全吃掉）。想加难度优先调 `HAO_AUTO_EVERY`／把方向改成向西倒退／或给红方补真伤。

---

## [9.08代码_v2] - 2026-09-08

### Added
- **战斗引擎统一（重构）**：新建 `scripts/combat/battle_base.gd`（`class_name BattleBase` 基类），把 1V1（`battle.gd`）与 4V4（`battle_team.gd`）的 **19 个公共成员变量 + 36 个实现完全相同的函数** 抽到基类，两个子类改为 `extends BattleBase`，各自只保留差异（棋盘尺寸、胜负判定、回合队列、AI、出生位置）。行为与 v1 完全一致（回归全绿）。以后公共逻辑改一处即可，不再两处同步。

### Changed
- **光雨被动调整**：由"回合开始 +2 能量、每 2 回合 +3 生命 +2 能量"改为"**每回合末 +2 能量 +1 生命**"（`battle_unit` 新增回合末通用效果 kind `hp` / `energy`）
- **药师削弱**：护盾上限 `shield_cap` 由 10 降为 6

### Fixed
- **光雨移动后同一回合射不到（1V1）**：移动后漏刷新技能栏（`_refresh_ui`），射程/置灰判定停留在移动前 → 移动后补刷新；技能按钮灰字改为显示"最近敌 X 格 / 射程 Y"便于判断距离

### Known（同 v1）
- 虞美人建模包围盒较大，缩进格子后视觉偏满，后续统一 fit 比例
- 蔓延"选格态"点非法格会保留选格状态，右键/点空格可取消
- AI 全自动对局仍可能僵局（数值问题，见 9.04 Known）

---

## [9.08代码_v1] - 2026-09-08

### Added
- **4V4 建模接入**：`team_board` 单位由"自绘圆形"改为 Node 棋子层（`unit_token`），有建模显骨骼角色、无建模兜底圆，与 1V1 统一；支持点击穿透、窗口缩放重摆、死亡移除
- **建模资源扩容**：`assets/db/` 由 6 → 11 个英雄（新增 虞美人 / 睡神 / 药师 / 邪神 / 灵虚数影）
- **虞美人花贴图**：`assets/heroes/yu_mei_ren_flower_red.png`（红花·母体）/`_white.png`（白花·子体）——豆包图生图（海报当参考）+ 绿幕去背
- **龙王资源技能声明式门禁**：技能数据加 `crystal_cost`(耗元晶) / `need_shield`(需护盾) 字段，`base_usable` 与按钮统一据此置灰（凝晶1 / 化晶2 / 御晶3、碎晶斩需护盾）
- **战斗日志放大阅读**：点日志区弹全屏大字日志层（最近 500 行、字号 15、✕ 或点暗底收起；背景不透明 + 高 CanvasLayer 置顶）
- **虞美人移动/叠格规则**：非实体单位可走进实体单位格（叠格）；母体移动到自己子体格 → 母子互换格子

### Changed
- **流血按设计表重写**：改为"被攻击时按本次攻击伤害的 20%(1级)/30%(2级)/40%(3级) 受额外真伤（无视甲盾）"，删除旧的"行动时自伤"逻辑（旧实现偏离设计表）
- **1V1 选人**：PVE 进选人界面即由 AI 随机定好蓝方英雄（不再默认显示邪神），红方换卡撞车时蓝方重选，界面始终显示蓝方真正会选的人
- **蔓延技能重做**：母体原地不动 → 在周围相邻空格（且没有子体的格子）生成子体，最多 2 格由玩家点选；只剩 1 格自动蔓延、无可蔓延格按钮置灰、本回合 2 次用尽置灰；新增可蔓延格绿色指示器
- **4V4 叠格显示优先级**：solid 单位 > 母体 > 子体；中央者正常显示，其余虞美人系退右上角（母体红花 / 子体白花）

### Fixed
- **1V1 普通/困难难度进不去（手机空界面 / 电脑闪退）**：`duel._on_start` 给 1V1 战斗对象赋 `side_levels`，而 `battle.gd` 未声明该属性 → 运行时崩溃。已补 `battle.gd.side_levels`
- **1V1 棋子走进"幽灵格"**：`move_cells_of` 用宽松边界漏查 `_cell_exists`（出生列上下已删格仍可走）→ 统一走 `_cell_exists` 判定
- **龙王技能坑玩家**：化晶为铠 / 碎晶斩在资源不足时按钮不置灰，点了白耗一回合 → 资源不足即置灰并给出原因
- **日志弹窗被棋子盖住 / 点不开**：日志层放入高 CanvasLayer 保证置顶；点击监听改挂到日志文本控件（原挂父层收不到点击）
- **虞美人 4V4 建模"巨大"**：母体被设 `flower=red` 使 `_draw` 走花分支跳过 `fit`，骨骼节点按原始尺寸（1046×1907）渲染 → 母体独立时走建模并正常 fit
- **队友走不到虞美人格**：点击判定优先"选中队友"而非移动 → 改为移动优先（已聚焦且格在可达格内即移动）
- **虞美人子体显示**：token 自判子体白花（1V1 / 4V4 通用）

### Known（已知遗留）
- 虞美人建模为"身体形态"且包围盒较大，缩进格子后视觉偏满，后续可统一 fit 比例
- 蔓延处于"选格态"时点非法格会保留选格状态，右键 / 点空格可取消
- AI 全自动对局仍可能僵局（数值问题，见 9.04 Known）

---

## [9.07代码_v3] - 2026-09-07

### Added
- **DragonBones 骨骼动画棋子**：剑舞 / 追猎 / 元晶龙王 / 流萤 / 孤狼 五个英雄的棋子由圆形改为骨骼角色（站桩=动画第一帧），头顶统一显示 名字 + 血条 + 能量条（理智系英雄显示理智条）
- **官方矩阵回放播放器**：`scripts/ui/dragonbones_sprite.gd`（读 `<英雄>_bake.json`，每帧回放官方算好的贴图变换，与龙骨编辑器 100% 一致）
- 骨骼数据 `assets/db/`（三件套 + `<英雄>_bake.json` 官方烘焙矩阵）
- 技能释放触发动作动画：`battle_unit.gd` 加 `signal skill_cast`，释放成功时棋子播放一次动作，播完回站桩
- 「表情包」「建模录入」等技能（见工作区，独立于本包）

### Changed
- 播放器由"自写解析"改为"官方核心烘焙矩阵回放"（dragonbones.js 5.7 headless 算出每帧矩阵，Godot 只回放，不再自己算骨骼变换）

### Fixed
- 孤狼腿部崩坏：自写解析对非均匀缩放（scX≠scY）+ 贴图定位与编辑器不一致 → 改用官方矩阵回放彻底解决
- 棋子整体偏出格子：`fit()` 覆盖了外部定位的 `position` → 改用内部容器缩放/偏移
- 选中棋子时出现多余黄色圆点 → 改为选中格子发光
- 再来一局后选人界面残留上一局棋子模型 → `_on_again()` 清理所有旧 token

---

## [9.07代码_v1] - 2026-09-07

### Added
- **新英雄·李太白（诗仙）**：醉意计数（每回合+1，≥5 酒醉跳过并清零）、将进酒/笔墨挥洒（随机诗行攻击）/肆意（冲锋按醉意伤害）/与君同醉（菱形13格全体含自己酒醉）。属性暂定金系（设计表空缺）
- **新英雄·虞美人（怀恨）**：速度0、蔓延生子体（不占行动、每回合2次）、恐惧状态（进3×3 触发层数×0.5 真伤）、悔恨、情愫、苦楚治疗光环、你不再爱我、非实体（可叠格）、母体阵亡子体枯萎、**暗影刺（子体自动攻击）+ 互助反击（被击反伤1真伤）**、子体上限（1V1=3 / 4V4=5）
- 虞美人立绘 `assets/heroes/yu_mei_ren.jpg`（图鉴海报）
- 14 英雄全部实装、可入选人/匹配池（移除 BANNED 禁用）

### Changed
- 虞美人/李太白从 BANNED 解除，删除 wip 占位 def
- 情愫/苦楚治疗按设计表 5%/20% 最大生命（两位小数）
- 虞美人元素维持「木」（图上有「精神」标注，暂作为暗影刺/互助反击的伤害类型处理）

### Fixed
- 虞美人子体继承母体被动/counter 的脏数据（改用最小 def）
- 子体影响胜负判定（存活统计跳过子体 + 母体阵亡清子体）
- 恐惧触发覆盖全部移动/位移路径


---

## [9.05代码_v5_整合版] — 2026-09-05 当日整合（合并 v1 ~ v4）

**本版不是新功能开发，而是当天四个版本的合并汇总。** 经核对更新日志与代码，v4 并非 v3 的迭代，而是从 **v1 基线**分出的平行分支，导致 v2/v3 的修复在 v4 中整体丢失。本版以 v4 为骨架，把 v2、v3 的修复全部合并回来。

### 版本关系（合并前实测）

| 版本 | 基线 | 独有内容 | 含前版修复 |
|---|---|---|---|
| v1 | 9.04 | 4V4 星星得分制、护盾上限 | — |
| v2 | v1 | 药师三技能修复、AI 大招修复 | ✅ |
| v3 | v2 | 掠夺改限时锁技 | ✅ |
| v4 | **v1** | 联机系统 MVP、豆包提速、主菜单弹窗修复、热座导航、追猎 per_game 限次 | ❌ 丢失 v2+v3 |

核验标记：`_deal_with_floor`（药师保底）v4 为 0 次、`_ult_ready_in_range`（AI 大招）v4 为 0 次、`lock_skill`（掠夺限时）v4 为 0 次；而 v4 独有 `per_game` 4 处。

### Added
- **联机系统 MVP**（来自 v4，最大更新）：
  - ENet 局域网直连 + WebSocket 公网穿透双模式（游戏内选择）；
  - 1V1 与 4V4 蛇形选秀均可联机；**指令重放式同步 + 同步种子确定性 RNG**；
  - 公网一键建房：自动调起 cpolar 隧道，房间号自动生成 + 一键复制（防泄漏三件套：残留清理、退出回收）；
  - 断线判负、状态漂移护栏、单位归属校验、pick seq 防错位。
  - 新文件 `scripts/net/{net_session,net_protocol,net_tunnel}.gd`，`Net` 为 autoload（见 `project.godot`）。
- **4V4 星星得分制**（来自 v1）`scripts/combat/battle_team.gd`：每回合刷新 1 颗小星（上限 2）+ 每 5 回合刷新 1 颗大星（上限 1），只落空格；单位停到星格拾取得分（小星 +3 / 大星 +5）；击杀 +6；**先到 30 分者胜**，全灭仍判负兜底。AI 寻路加入"落星格 + 邻星格"引力；棋盘渲染星星；顶栏显示"第 N 回合 · ★红 X : Y 蓝★"。
- **护盾上限机制（per-hero）**（来自 v1）`battle_unit.gd` / `hero_defs.gd`：def 支持 `shield_cap`（0=不限，>0 时裁剪），龙王/药师/灵虚已配置 cap = max_hp，堵死"无限叠盾乌龟流"。
- **AI 满状态空放自保技**（来自 v1）`ai.gd`：`heal` 需残血可治疗、`shield` 需未到上限才用，避免白放浪费技能权。
- **新场景/资源**：`scenes/StoryMap.tscn` + `scripts/ui/story_map.gd`；`tools/map_exe_app/战棋地图设计器.spec`；临时验证脚本 `tests/*_tmp.gd`（确定性、热座导航、联机重放等）。

### Fixed
- **药师三技能打不出伤害（且被误读为"给敌人回能"）**（来自 v2）`skill_effects.gd`：
  - 一技能【建木生发】伤害 = 目标已损生命一半，**满血目标恒为 0**，且 2~3 点伤害常被 1~3 点护甲全免 → 现加保底 2 点，削减到保底以下时差额以真伤补足；自残量原取目标血量一半，对高血量目标会"生命不足"无法发动 → 现封顶为"保留自身 1 血"。
  - 二技能【寿瘟祸祖】3 点伤害被护甲 3 完全减免 → 加保底 3 点真伤补足，并按描述改为作用于附近**全体**敌人（`ai.land_aoe`）。
  - 大招【药灵】误配 `ai.self_buff = true` → 战斗层 `self_skill()` 返回 true、目标列表恒为空（日志永远"相邻无敌人"）、AI 从不把它当攻击技 → **已去掉 self_buff**，并改为相邻全体敌人。
  - 三技能伤害统一走新增 `_deal_with_floor()`：`sure_hit`（不吃闪避）+ 伤害下限真伤补足，避免"自残了却 0 伤害"。
  - 日志歧义修复：原"追猎 受 0 伤，回复 4 能量"易被读成敌人回能，现改为"自身消耗 N 生命 → 目标受 X 点伤害；药师 自身回复 N 能量"。
- **AI 攒满能量也放不出大招**（来自 v2）`ai.gd`：新增 `_ult_ready_in_range()`（大招已充能且能命中时优先于常规自保）、`_ult_ready_but_out_of_range()` + `_step_into_range()`（大招够不着时主动走进射程）。药师这类自残流血量长期压在自保阈值以下，原会被"残血就回血"循环卡死（实测能量攒到 160 仍 0 次大招）。
- **主菜单弹窗"无法选择豆包"**（来自 v4）`main_ui.gd`：`_online_done_cb(res: Array)` 只声明 1 个参数，但 `HTTPRequest.request_completed` 发 4 个参数 → 回调一触发即报错、检测结果永远回不来 → 豆包按钮长期 disabled。改为 4 参签名后实测 2.5s 判定"网络正常：可选用豆包战术模型"。
- **主菜单弹窗偏左下**（来自 v4）`main_ui.gd`：根因 = 裸 `Panel` 作居中卡片时高度塌缩为 0（headless 实测 card S=(560,0)），子内容溢出致整体错位；改 `PanelContainer` 后中心实测 640,360 = 视口正中，并显式设置 layer/CenterContainer 尺寸 + 锚点归零。
- **豆包战术模型提速**（来自 v4）`llm_decider.gd` / `main_ui.gd`：请求体补 `"thinking": {"type": "disabled"}`（默认深度思考 20s+ 必撞 10s 超时）；`TIMEOUT_MS` 10s → 30s；`_post_json` 加"读到过数据后 1.5s 无新数据即结束"判据（实测单回合 30.1s → 3.1s，10 倍提速）。
- **热座模式导航**（来自 v4）：返回键不再误入难度选择页。
- **打包丢失文件修复**（本版）：补回 `installer/战棋.iss`——v4 打包时整个 `installer/` 目录缺失，本版从 v3 补回，MD5 与 v1~v3 一致（`d90becbe7afe3448ca8c2262e3939ea4`）。
- **测试断言回退修复**（本版）：`tests/combat_regression.gd` 在 v4 中回退成了 v1 版本（丢失药师/掠夺限时断言），本版取 v3 全量版（71 处断言）。

### Changed
- **掠夺由"本局禁技"改为"限时锁技"**（来自 v3）`battle_unit.gd` / `skill_effects.gd`：
  - 新增 `lock_skill(id, rounds)` + `_unlock_skill()`：对方直到下个对方回合无法使用该技（原为整局禁用）；
  - 新增 `_stolen_backup` / `STOLEN_ROUNDS = 2` / `_expire_stolen()`：自身可在第 1 技能槽使用掠夺来的技能 2 个自身回合，到期自动归还原技能；
  - 快照/回滚补充 `actives_ids` / `_lost_skills` / `_stolen_pending` / `_stolen_slot` / `_stolen_backup_id`，保证前瞻推演不污染掠夺状态；
  - 描述与日志文案同步更新。
- **联机确定性随机**（来自 v4）：效果函数内随机一律走 `user.rng`（`_sync_randf` / `_sync_randi`），`null` 时回退全局随机（单机旧路径）；`battle_unit.take_damage` 闪避判定改走 `_randi_sync()`；AI 走位随机改走 `battle.rng`。
- **追猎「流炎飞弹」整局限次**（来自 v4）：新增 `per_game` 机制（技能元数据 + `Skill.per_game`），锦标赛复测统治力 +0.73 → +0.16，回归正常带。
- **测试基准**（来自 v1）`ai_tier_bench.gd` / `hero_team_rank.gd`：胜负判定改为直接读战斗层 `b.winner`（30 分 / 全灭 / 120 回合兜底僵局），删除原先 30 回合多数决与 1v1 血量比防僵局规则；难度评价加入"得分差 × 2.5"项。
- **文档**：`README.md` 新增「零、关于本整合版」章节（版本关系表、合并方式、校验状态），项目结构补充 `scripts/net/`、StoryMap、临时测试脚本；注意点补充联机依赖与联机确定性约定。

### Removed
- **追猎回归匹配池**：得分制后统治力由 +1.0 降至 0.82（easy AI 全池 526 场）；经 `per_game` 限次后进一步降至 +0.16。

### 合并方式与校验
- `battle_unit.gd`、`skill_effects.gd`：用 `git merge-file` 三方合并（base=v1，ours=v4，theirs=v3），**零冲突**；
- `ai.gd`：改动区域相邻，手工合入 3 个函数 + 2 处调用点，保留 v4 联机 rng；
- 静态校验：35 个 .gd 脚本括号配对与缩进一致、autoload 与场景脚本引用齐全、AI 调用的战斗层接口全部存在；
- ⚠️ **待真机验证**：本沙箱为 Linux 且网盘仅有 win64 版 Godot（无 wine），**未能执行 `godot --headless` 冒烟与双回归**，建议本地补跑 `combat_regression.gd`（71 断言）与 `team4v4_regression.gd`（52 断言）后再打包分发。

### Known（已知遗留）
- **AI 全自动对局常现僵局**：英雄普伤 1~3 vs 护甲 1~3，护甲为固定减伤，AI 互砍常被完全减免，加上药师回血循环，3 局模拟 2 局打到 80 回合僵局。属数值问题，待统一调数值。
- 4V4 技能统一"单目标"（与 1V1 一致），范围/多目标技能的实际效果按 1V1 行为执行；声明式多目标支持留作后续。
- 被动触发时机：暂不在回合流程中显式 `trigger_passive`，被动多由效果函数自身维护。
- ~~技能"流星飞弹"真名为"流炎飞弹"~~（已于 2026-09-08 统一改名）。
- 公网真实双机对局待持续观察（cpolar 免费隧道中转）。
- `tests/*_tmp.gd` 为临时验证脚本，可择机清理。

---

## 战棋代码_9.04_修复掠夺（2026-09-04）

### Fixed
- 修复「掠夺」技能机制：`lve_duo` 的掠夺行为改为"当回合仍按原技能释放，下回合起被掠夺方在本局无法释放该技能"等正确语义（具体规则以代码注释与 `combat_regression.gd` 中 `_test_heroes()` 的 rapper 段断言为准）。

> 备注：9.04 之前的更早变更历史未在此整理，按仓库代码与回归测试推断。

---

> 【说明文件 · 自传播提醒 —— 请勿删除本段】
> 1. 本压缩包根目录必须有一份说明文件（README.md），写明：项目结构、进度与计划、注意点；
> 2. 每当你新建或更新说明文件时，必须把【本段提醒】原样复制到新说明文件的结尾；
> 3. 若发现某压缩包缺说明文件或结尾无本提醒：补上（内容参考包内代码），并把本段一起附上；
> 4. 说明文件与本 CHANGELOG 同步到网盘「主程序」文件夹随压缩包一起上传。
