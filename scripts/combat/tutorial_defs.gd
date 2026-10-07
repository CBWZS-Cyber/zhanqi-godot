class_name TutorialDefs
extends RefCounted
## 新手教程 · 专用单位定义与角色表（2026-09-28 新增）
##
## 与 HeroDefs **完全隔离**（照 story_defs.gd 的先例）：
##   · 木桩不进选人池 / 匹配池 / 英雄图鉴（HeroDefs.is_pickable 不受影响）；
##   · 不修改 HeroDefs 里任何英雄的数值。
##
## 木桩参数是**教学参数**，不是平衡数值——改它不影响任何正式对局。
##
## ⚠️ 为什么木桩护甲 = 0（2026-09-28 实测后改的，别再改回 1）：
##   伤害结算里 armor 是**平摊减伤**（`reduced = minf(armor, rest)`，见 battle_unit.gd:504）。
##   教程 4 个角色里，剑舞「瞬击」与追猎「狙击」都只有 **1 点**伤害 ——
##   木桩若设 1 甲，这两个英雄打上去恒为 **0 伤害**，教程直接卡死。
##   更糟的是追猎「流炎飞弹」（3 伤）带 per_game=1（一局仅一次），打不出第二次。
##   → 木桩必须 0 甲；「护甲减伤」改用**玩家自己的甲**演示（木桩轻击 1 伤，追猎 3 甲吃满 = 掉 0 血）。

const DUMMY_ID := "tut_dummy"

## 训练木桩：只会挪动 + 偶尔轻击，不会放技能
const DUMMY := {
	"name": "训练木桩",
	"element": "",          # 无属性：不触发任何元素增伤/减免匹配
	"hp": 8,                # 够撑完整个教程（教程过关条件是「造成一次伤害」，不是击杀）
	"energy": 0,
	"energy_max": 0,
	"armor": 0,             # 见文件头：**必须为 0**
	"speed": 1,             # 永远最后行动，玩家总能先手
	"skills": {"passive": "", "actives": ["", "", "", ""]},   # 无技能：行为全在 BattleTutorial._dummy_act()
}

## 木桩轻击：走 BattleUnit.take_damage → 玩家的「盾 → 甲 → 血」链路照常结算
const DUMMY_STRIKE_DMG := 1.0
const DUMMY_STRIKE_RANGE := 1
## 每 N 个「木桩自己的回合」轻击一次（其余回合只挪动）。
## 整局教程通常 3~5 回合，所以新手最多挨 1~2 下，6 血的光雨也不会被打死。
const DUMMY_STRIKE_EVERY := 3

## 「位移」机制步用的**残血窗口**血量（2026-09-30 新增）。
##
## 为什么要它：剑舞唯一能演示位移的技能是「诛心」，而它是**斩杀技** ——
## 描述写着"只能对生命 ≤30% 的目标使用"。木桩满血 8，30% = 2.4，
## 所以木桩必须被压到 ≤2 血，这个技能才放得出来（否则教程只能"看说明、跳过去"）。
##
## ⚠️ 连带风险与对策（这里是坑所在）：木桩残血 → 玩家一放斩杀就**把它打死** →
## 基类 `_check_win()` 立刻判"蓝方全灭" → `run_step()` 返回 `{"over": ...}` → 教程中途被强行结束。
## 所以要**两件事一起做**，缺一不可：
##   ① `BattleTutorial._check_win()` 覆写为空 —— 教程的结束由步骤机决定，不判胜负；
##   ② 离开该步时 `restore_dummy()` 把木桩修回来（被斩杀就复活）。
const DUMMY_LOW_HP := 2

## 教程棋盘的地形布置（2026-09-28 新增）—— 键为 "x,y"（与 GridBoard 的 _key 一致）
##
## 只放两类，且都取「对本作最典型」的效果：
##   森林 Terrain.FOREST = 3 → 受击伤害 ×0.8、移出该格额外耗 1 能量
##   水域 Terrain.WATER  = 5 → 回合末扣 1 能量、**禁止位移类技能**
##
## ⚠️ 摆位刻意**避开双方出生格与两国中点**（(0,2) 玩家 / (2,2) 木桩）：
##    新手一开局不该被地形收费；同时避开木桩脚下，免得"打伤木桩"这一步被森林减免干扰。
##    地形生效与否由 Terrain.story_active() 白名单决定（见 BattleTutorial._build_terrain）。
const TERRAIN := {
	"1,1": 3,   # 森林
	"1,3": 3,   # 森林
	"3,1": 5,   # 水域
	"3,3": 5,   # 水域
}

## 取某格的教程地形（'x,y' → 地形 id；没有则空地）
static func terrain_at(c: Vector2i) -> int:
	return int(TERRAIN.get("%d,%d" % [c.x, c.y], 0))

## 教程可选角色（精选 4 个，覆盖四种教学面）
##   only_4 的理由：14 英雄差异过大（10 个没位移、虞美人零伤害技+速度0、流萤只有 1 个技能、
##   辛克莱没有能量条），全开会让教程步骤大面积降级；这 4 个能演示全部核心机制。
const HEROES := [
	{
		"id": "crystal_dragon",
		"tag": "无位移 · 有护盾自益技",
		"why": "最适合第一次接触：技能直白，还能演示「计数资源（元晶）」与「自益护盾」。",
	},
	{
		"id": "guang_yu",
		"tag": "纯远程输出 · 射程 3",
		"why": "演示「射程」概念与「多目标技能」；没有位移，走位全靠自己。",
	},
	{
		"id": "jianwu",
		"tag": "带位移 · 斩杀",
		"why": "演示「位移技」与「斩杀条件（只能打残血）」，教你看技能描述里的限制。",
	},
	{
		"id": "zhuilie",
		"tag": "位移 + 全图技",
		"why": "演示「射程 99 的全图技」与「一局仅限一次」的资源管理。",
	},
]

static func hero_ids() -> Array[String]:
	var out: Array[String] = []
	for h in HEROES:
		out.append(str(h["id"]))
	return out

static func hero_entry(id: String) -> Dictionary:
	for h in HEROES:
		if str(h["id"]) == id:
			return h
	return {}
