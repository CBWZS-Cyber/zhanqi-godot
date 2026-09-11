class_name Weapons
extends RefCounted
## 武器系统 · 数据定义（2026-09-10 由用户「武器资料汇总」整理）
##
## 档位：神器（素材）→ 超神器 → 终极神器；另有「专属武器」
## 获取链路（用户 2026-09-10 定稿 · 方案 A）：
##   小星星（拾取）→ 神器（素材 6 件，可装备，仅契合加成）
##   大星星（拾取）→ 超神器（3 件随机）
##   超神器 + 超神器 → 终极神器（合成，3 条配方）
##     · 黄金剑 + 灵环     → 裁决
##     · 黄金剑 + 永恒核心 → 终结之剑
##     · 灵环   + 永恒核心 → 圣环
##   ⚠️ 「神器（素材）→ 超神器」的合成链已删除
##
## 说明：本文件只登记数据（名称/属性/契合加成/合成配方/技能定义）；
##       武器的获取方式、装备规则、技能效果实现待用户后续指定。
##
## 字段：
##   name     武器名
##   tier     档位（超神器 / 终极神器 / 神器 / 专属）
##   element  属性（王 / 灵 / 元 / 神圣 / 光 / 暗 / 火）
##   affinity 契合加成（文本；装备者属性匹配时生效，具体判定待定）
##   recipe   合成配方（材料武器 id 数组；空=不可合成/可掉落）
##   skills   技能数组，每项：
##              id / name / kind（被动 passive / 伤害 damage / 控制 control / 特殊 special）
##              cost（能量消耗；-1 = 每人一次）
##              range（射程，格）/ targets（目标数）/ desc（效果文本）

const TIER_SUPER := "超神器"
const TIER_ULTIMATE := "终极神器"
const TIER_ARTIFACT := "神器"
const TIER_EXCLUSIVE := "专属"

const ALL := {
	# ================= 超神器 =================
	"golden_sword": {
		"name": "黄金剑", "tier": TIER_SUPER, "element": "王",
		"affinity": "30% 免伤（上限 50%）",
		"recipe": [],   # 神器→超神器 合成链已删（2026-09-10）；超神器来源：大星星
		"skills": [
			{"id": "golden_aegis", "name": "黄金圣甲", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "每回合末获得 1 点真实护盾（可挡真伤），上限 4 点"},
			{"id": "golden_slash", "name": "黄金剑斩", "kind": "damage",
			 "cost": 4, "range": 1, "targets": 1,
			 "desc": "对 1 个目标造成 3 点真实伤害；目标护甲下降 2 点"},
		],
	},
	"spirit_ring": {
		"name": "灵环", "tier": TIER_SUPER, "element": "灵",
		"affinity": "抵挡 2 次致命伤害",
		"recipe": [],   # 神器→超神器 合成链已删；超神器来源：大星星
		"skills": [
			{"id": "soul_return", "name": "魂归", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "阵亡后立即原地复活（每个穿戴者仅一次）；复活后 HP 为 50%，其余数值与复活前相同"},
			{"id": "soul_bewitch", "name": "迷魂", "kind": "control",
			 "cost": 5, "range": 2, "targets": 1,
			 "desc": "使目标进入临时「失魂」状态，持续 2 回合"},
		],
	},
	"eternal_core": {
		"name": "永恒核心", "tier": TIER_SUPER, "element": "元",
		"affinity": "立即回满能量，之后增加 6 点能量上限",
		"recipe": [],   # 神器→超神器 合成链已删；超神器来源：大星星
		"skills": [
			{"id": "endless_spring", "name": "无尽源泉", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "每回合末额外回复 1 点能量"},
			{"id": "energy_burst", "name": "能爆", "kind": "damage",
			 "cost": 3, "range": 2, "targets": 1,
			 "desc": "消耗当前能量的一半，将其转化为伤害（对 1 个目标）"},
		],
	},

	# ================= 终极神器（由两件超神器合成）=================
	"sword_of_end": {
		"name": "终结之剑", "tier": TIER_ULTIMATE, "element": "神圣",
		"affinity": "无（队伍中无神圣属性英雄）",
		"recipe": ["golden_sword", "eternal_core"],
		"skills": [
			{"id": "ultimate_energy", "name": "终极能量", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "提高 10 点能量上限，并回满能量（每人一次）"},
			{"id": "annihilation", "name": "万灭归一", "kind": "special",
			 "cost": -1, "range": 1, "targets": 1,
			 "desc": "斩杀 HP≤30% 的目标；无视其保命技能、无视闪避，必中必死（每人一次）"},
		],
	},
	"verdict": {
		"name": "裁决", "tier": TIER_ULTIMATE, "element": "神圣",
		"affinity": "无",
		"recipe": ["golden_sword", "spirit_ring"],
		"skills": [
			{"id": "soul_rend", "name": "裂魂", "kind": "control",
			 "cost": -1, "range": 2, "targets": 1,
			 "desc": "使目标进入「碎魂」状态（相当于无法解除的「失魂」）（每人一次）"},
			{"id": "judgement", "name": "审判", "kind": "special",
			 "cost": 2, "range": 99, "targets": 1,
			 "desc": "对自身与目标同时进行「审判」（不可闪避）：50% 概率自己死亡（无视保命技）；50% 概率目标死亡且无法复活（无视保命技）"},
		],
	},
	"holy_ring": {
		"name": "圣环", "tier": TIER_ULTIMATE, "element": "神圣",
		"affinity": "无",
		"recipe": ["spirit_ring", "eternal_core"],
		"skills": [
			{"id": "endless_life", "name": "生生不息", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "每回合末额外回复 3 点能量、1 点生命"},
			{"id": "divine_blessing", "name": "神佑", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "解除所有负面效果；速度 ≥250、护甲 ≥2、持续霸体，并获得 30% 免伤（≤50%）"},
		],
	},

	# ================= 神器（素材）=================
	"yuan_blade": {
		"name": "元刃", "tier": TIER_ARTIFACT, "element": "元",
		"affinity": "15% 额外真伤", "recipe": [], "skills": [],
	},
	"knight_token": {
		"name": "骑士王令牌", "tier": TIER_ARTIFACT, "element": "王",
		"affinity": "10% 免伤（上限 30%）", "recipe": [], "skills": [],
	},
	"white_spirit_core": {
		"name": "白灵核心", "tier": TIER_ARTIFACT, "element": "光",
		"affinity": "10% 能量消耗减免", "recipe": [], "skills": [],
	},
	"ink_spirit_core": {
		"name": "墨灵核心", "tier": TIER_ARTIFACT, "element": "暗",
		"affinity": "10% 能量回复加成", "recipe": [], "skills": [],
	},
	"demon_soul": {
		"name": "魔魂", "tier": TIER_ARTIFACT, "element": "火",
		"affinity": "每回合末对周围敌人造成 0.5 真实伤害", "recipe": [], "skills": [],
	},
	"spirit_ring_sealed": {
		"name": "灵环（封印）", "tier": TIER_ARTIFACT, "element": "灵",
		"affinity": "10% 闪避率", "recipe": [], "skills": [],
	},

	# ================= 专属武器 =================
	"flame_heart": {
		"name": "焰心", "tier": TIER_EXCLUSIVE, "element": "火",
		"affinity": "",
		"recipe": [],
		"skills": [
			{"id": "fire_feather", "name": "火羽", "kind": "passive",
			 "cost": 0, "range": 0, "targets": 0,
			 "desc": "穿戴者带 40% 反伤"},
			{"id": "leave_fire", "name": "离火", "kind": "damage",
			 "cost": 2, "range": 1, "targets": 1,
			 "desc": "对 1 个目标造成 1 点真实伤害；高瓷本人使用此技能时，获得一层「淬羽」"},
		],
	},
}

## 全部武器（按档位分组展示用）
static func tier_order() -> Array:
	return [TIER_SUPER, TIER_ULTIMATE, TIER_ARTIFACT, TIER_EXCLUSIVE]

## 某档位的武器 id 列表
static func ids_of_tier(tier: String) -> Array:
	var out: Array = []
	for id in ALL:
		if str(ALL[id].get("tier", "")) == tier:
			out.append(id)
	return out

static func get_def(id: String) -> Dictionary:
	return ALL.get(id, {})

static func name_of(id: String) -> String:
	return str(ALL.get(id, {}).get("name", id))

## 合成：由两件材料求产物 id；无匹配返回 ""
static func product_of(a: String, b: String) -> String:
	var pair := [a, b]
	pair.sort()
	for id in ALL:
		var r: Array = ALL[id].get("recipe", [])
		if r.size() == 2:
			var rr := [r[0], r[1]]
			rr.sort()
			if rr == pair:
				return id
	return ""

## 该武器的合成材料名（展示用）
static func recipe_text(id: String) -> String:
	var r: Array = ALL.get(id, {}).get("recipe", [])
	if r.is_empty():
		return "—"
	var parts: Array = []
	for m in r:
		parts.append(name_of(str(m)))
	return " + ".join(parts)

## 技能摘要文本（图鉴展示）
static func skills_text(id: String) -> String:
	var out := ""
	var sks: Array = ALL.get(id, {}).get("skills", [])
	for i in range(sks.size()):
		var s: Dictionary = sks[i]
		var cost := int(s.get("cost", 0))
		var cost_txt := "每人一次" if cost < 0 else ("被动" if str(s.get("kind", "")) == "passive" else "耗能 %d" % cost)
		var rng := int(s.get("range", 0))
		var rng_txt := ""
		if rng > 0:
			rng_txt = " · 射程 %s" % ("全图" if rng >= 99 else "%d 格" % rng)
		out += "　%s %s（%s%s）\\n　　%s\\n" % [
			"①②③④⑤"[i] if i < 5 else "-", str(s.get("name", "")), cost_txt, rng_txt, str(s.get("desc", ""))]
	return out
