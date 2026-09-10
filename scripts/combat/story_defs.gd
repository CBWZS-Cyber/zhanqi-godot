class_name StoryDefs
## 骑士线第一关 · 白灵殿 剧情兵种登记表（数值源自《角色属性与技能表.xlsx》2026-09-10 版）
##
## 与 HeroDefs（14 位可收集英雄）完全隔离：
##   - 剧情兵种不进选人池、不进图鉴、不参与匹配；
##   - 只有 BattleStory（骑士线战斗层）会读本表。
##
## 【如何加一个剧情兵种】
##   1. 在 ALL 里加 def（字段语义同 hero_defs.gd，另有两个剧情专用字段）：
##        "init_flags"  : 开局自带的 flag 数组（"energy_guard" 能量抵消致命伤 / "lock_min_hp" 锁 1 血）
##        "move_steps"  : 每回合移动步数（缺省用 BattleStory.DEFAULT_MOVE_STEPS）
##   2. 被动只做"展示 + 声明式实现"：
##        - 展示：skill_effects.gd 的 DATA 里登记 passive 元信息（name/desc）
##        - 实现：turn_end_effects / hp_threshold_flags / init_flags 声明式，或战斗层特判
##      （注：战斗层不会自动 trigger_passive，被动效果函数不会被调用，不要写进 EFFECTS）
##   3. 主动技能：skill_effects.gd 的 DATA + EFFECTS 各登记一条。

const ALL := {
	# —— 被护送者：携带白灵核心，行动迟缓（move_steps=1），无主动技能 ——
	"story_hao": {
		"name": "昊", "element": "灵",
		"hp": 5, "energy": 18, "armor": 0, "speed": 100,
		"move_steps": 1,
		"turn_end_effects": [{"kind": "hp", "amount": 1}],
		"skills": {"passive": "s1_hao_aura", "actives": ["", "", "", ""]},
	},
	# —— 昊的同伴，与昊同行 ——
	"story_qi": {
		"name": "祁", "element": "灵",
		"hp": 7, "energy": 15, "armor": 1, "speed": 90,
		"turn_end_effects": [{"kind": "hp", "amount": 1}],
		"skills": {"passive": "s1_qi_partner", "actives": ["", "", "", ""]},
	},
	# —— 白灵族大长老（蓝方指挥官；能量池 27，靠能量硬抗致命伤）——
	"story_elder": {
		"name": "大长老", "element": "灵",
		"hp": 7, "energy": 27, "armor": 1, "speed": 120,
		"init_flags": ["energy_guard"],
		"turn_end_effects": [{"kind": "energy", "amount": 4}],
		"skills": {
			"passive": "s1_quan_yong",
			"actives": ["s1_jie_yu_lv", "s1_zhi_yu_ze", "s1_qiang_quan", "s1_ling_zhen"],
		},
	},
	# —— 白灵殿战士（前排肉盾，靠「坚固」自保）——
	"story_warrior": {
		"name": "战士", "element": "灵",
		"hp": 8, "energy": 12, "armor": 2, "speed": 114,
		"turn_end_effects": [{"kind": "energy", "amount": 3}],
		"skills": {
			"passive": "s1_du_xin",
			"actives": ["s1_jian_gu", "s1_jue_xin", "", "s1_yin_lei"],
		},
	},
	# —— 白灵殿法师（治疗 + 真伤远程）——
	"story_mage": {
		"name": "法师", "element": "灵",
		"hp": 6, "energy": 15, "armor": 1, "speed": 113,
		"turn_end_effects": [{"kind": "energy", "amount": 4}],
		"skills": {
			"passive": "s1_qian_cheng",
			"actives": ["s1_guan_huai", "s1_ling_dong", "", "s1_chi_cheng"],
		},
	},
	# —— 魔渊首领·宵（不死身：锁 1 血；血量低于 50% 无法行动）——
	"story_xiao": {
		"name": "宵", "element": "火",
		"hp": 9, "energy": 16, "armor": 3, "speed": 130,
		"init_flags": ["lock_min_hp"],
		"turn_end_effects": [{"kind": "hp", "amount": 1}],
		"skills": {
			"passive": "s1_bu_mie",
			"actives": ["s1_ke_ran_dian", "s1_yan_quan", "s1_bu_zhi_huo", "s1_lian_yu"],
		},
	},
	# —— 魔渊·龙（射程 2/4，伤害附带灼烧）——
	"story_dragon": {
		"name": "龙", "element": "火",
		"hp": 7, "energy": 15, "armor": 2, "speed": 115,
		"skills": {
			"passive": "s1_long_yan",
			"actives": ["s1_jiao_zuan", "s1_long_xi2", "", ""],
		},
	},
	# —— 魔渊·熊（近战双技；血量低于 30% 获得 60% 免伤）——
	"story_bear": {
		"name": "熊", "element": "火",
		"hp": 8, "energy": 12, "armor": 2, "speed": 110,
		"hp_threshold_flags": [{"flag": "免伤60", "pct": 30}],
		"skills": {
			"passive": "s1_xiong_xin",
			"actives": ["s1_yan_zhua", "s1_yan_ya", "", ""],
		},
	},
}

## 出生点 unit 字段（去掉末尾数字）→ def_id
const UNIT_KEY := {
	"昊": "story_hao",
	"祁": "story_qi",
	"大长老": "story_elder",
	"战士": "story_warrior",
	"法师": "story_mage",
	"宵": "story_xiao",
	"龙": "story_dragon",
	"熊": "story_bear",
}

## 单位类型名 → def_id（去掉末尾数字后查表；查不到返回 ""）
static func def_of(unit_name: String) -> String:
	var s := unit_name
	while s.length() > 0 and s[-1] >= "0" and s[-1] <= "9":
		s = s.substr(0, s.length() - 1)
	return str(UNIT_KEY.get(s, ""))

## 构造剧情单位（team：0 红方魔渊 / 1 蓝方白灵殿）
static func make(def_id: String, team: int, cell: Vector2i, display_name := "") -> BattleUnit:
	var def: Dictionary = (ALL.get(def_id, {}) as Dictionary).duplicate(true)
	if def.is_empty():
		return null
	def["id"] = def_id
	if display_name != "":
		def["name"] = display_name
	var u := BattleUnit.new(def)
	u.team = team
	u.cell = cell
	return u
