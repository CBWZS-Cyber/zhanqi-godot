class_name Terrain
extends RefCounted
## 地形效果定义（2026-09-10 用户设计）
## 与 maps/*.json 的 types id 对齐（0-9）
##   0 空地  1 障碍(可破坏)  2 障碍(不可破坏)  3 森林  4 沼泽  5 水域
##   6 雪地  7 沙漠          8 山地            9 冰面
##
## 规则汇总：
##   森林：格内单位免伤 20%（受伤 ×0.8）；移出额外消耗 1 能量
##   沼泽：格内单位速度 -30；移出额外消耗 1 能量
##   山地：格内单位伤害 +30%（造成 ×1.3）；移出额外消耗 2 能量
##   水域 / 沙地：禁用位移类技能（普通走格允许）
##   冰面：进入后沿移动方向持续滑行，直到离开冰面（前方受阻则停在原格）
##   能量不足 → 无法移出该格（禁止移动）
##   叠加规则：乘法（免伤与增伤均乘算，与元素加成等按乘法叠加）

const EMPTY := 0
const OBST_BREAKABLE := 1
const OBST_SOLID := 2
const FOREST := 3
const SWAMP := 4
const WATER := 5
const SNOW := 6
const SAND := 7
const MOUNTAIN := 8
const ICE := 9

const NAMES := {
	EMPTY: "空地", OBST_BREAKABLE: "障碍（可破坏）", OBST_SOLID: "障碍（不可破坏）",
	FOREST: "森林", SWAMP: "沼泽", WATER: "水域", SNOW: "雪地",
	SAND: "沙漠", MOUNTAIN: "山地", ICE: "冰面",
}

## 不可通行地形（障碍）
const BLOCKING := [OBST_BREAKABLE, OBST_SOLID]

## 移出该格需要额外消耗的能量（不足则无法移出）
const EXIT_ENERGY_COST := {
	FOREST: 1,
	SWAMP: 1,
	MOUNTAIN: 2,
}

## 格内单位受到的伤害倍率（森林免伤 20%）
const DAMAGE_TAKEN_MULT := {
	FOREST: 0.8,
}

## 格内单位造成的伤害倍率（山地 +30%）
const DAMAGE_DEALT_MULT := {
	MOUNTAIN: 1.3,
}

## 格内单位的速度修正（沼泽 -30）
const SPEED_DELTA := {
	SWAMP: -30,
}

## 禁止位移类技能的地形（水域 / 沙地）
const DASH_BLOCKED := [WATER, SAND]

## 回合末：格内单位损失的生命（沙地 0.5 血/回合，2026-09-10 用户设计）
const END_TURN_HP_LOSS := {
	SAND: 0.5,
}

## 回合末：格内单位损失的能量（水域 1 能量/回合，2026-09-10 用户设计）
const END_TURN_ENERGY_LOSS := {
	WATER: 1,
}

## 冰面：进入后滑行
const SLIDING := [ICE]

## ---------------------------------------------------------------------------
## 剧情关（骑士线第一关·白灵殿）实际启用的地形
## 2026-09-12 用户要求「加入地形效果」，并明确只生效这三类：
##   森林（免伤 20%）/ 水域（禁位移技 + 回合末扣 1 能量）/ 障碍（可破坏 + 不可破坏）
## 其余地形（沼泽/雪地/沙漠/山地/冰面）在本关一律按空地处理，
## 避免"一开地形就把关卡平衡打崩"。terrain.gd 自身的规则表保持不动，
## 由 story_active() 决定战场是否消费它。
const STORY_ACTIVE := [FOREST, WATER, OBST_BREAKABLE, OBST_SOLID]

## 该地形 id 在剧情关是否生效
static func story_active(id: int) -> bool:
	return STORY_ACTIVE.has(id)

## ---------------------------------------------------------------------------
## 无视水域地形的兵种（2026-09-12 用户要求：红方「龙」可无视水域地形效果）
## 命中后：水域不扣其能量，也不禁止其位移类技能。
## 按 def_id 判定（兵种特性），与 init_flags 通用 flag 体系解耦。
const WATER_IMMUNE_DEFS := ["story_dragon"]

## 该 def_id 是否无视水域
static func water_immune_def(def_id: String) -> bool:
	return WATER_IMMUNE_DEFS.has(def_id)

static func name_of(id: int) -> String:
	return str(NAMES.get(id, "未知地形"))

static func exit_energy_cost(id: int) -> int:
	return int(EXIT_ENERGY_COST.get(id, 0))

static func damage_taken_mult(id: int) -> float:
	return float(DAMAGE_TAKEN_MULT.get(id, 1.0))

static func damage_dealt_mult(id: int) -> float:
	return float(DAMAGE_DEALT_MULT.get(id, 1.0))

static func speed_delta(id: int) -> int:
	return int(SPEED_DELTA.get(id, 0))

static func dash_blocked(id: int) -> bool:
	return DASH_BLOCKED.has(id)

static func end_turn_hp_loss(id: int) -> float:
	return float(END_TURN_HP_LOSS.get(id, 0.0))

static func end_turn_energy_loss(id: int) -> int:
	return int(END_TURN_ENERGY_LOSS.get(id, 0))

static func is_sliding(id: int) -> bool:
	return SLIDING.has(id)

static func is_blocking(id: int) -> bool:
	return BLOCKING.has(id)

## 地形效果说明（UI 悬停/规则展示用）
static func desc_of(id: int) -> String:
	match id:
		FOREST:
			return "森林：格内免伤 20%；移出时额外消耗 1 点能量"
		SWAMP:
			return "沼泽：格内速度 -30；移出时额外消耗 1 点能量"
		MOUNTAIN:
			return "山地：格内伤害 +30%；移出时额外消耗 2 点能量"
		WATER:
			return "水域：禁止使用位移类技能；格内每回合末损失 1 点能量"
		SAND:
			return "沙漠：禁止使用位移类技能；格内每回合末损失 0.5 点生命"
		ICE:
			return "冰面：进入后沿移动方向持续滑行，直到离开冰面"
		OBST_BREAKABLE:
			return "障碍（可破坏）：不可通行；魔渊的攻击技能可把它当作目标，受 1 点伤害后变为空地"
		OBST_SOLID:
			return "障碍（不可破坏）：不可通行，无法被摧毁"
		_:
			return "空地：无特殊效果"
