class_name HeroDefs
## 剧情模式 · 英雄数据工厂与登记处。
##
## 【如何新增一个剧情英雄】（等用户提供名单与数值后照此填写）
##   1. 在下方加一个 def 字典，形如：
##        "example_hero": {
##            "name": "剑士·示例",
##            "element": "火",                  # 主属性 = 元素（火/冰/雷/风/土/光/暗…）
##            "hp": 120, "energy": 80, "armor": 5, "speed": 6,
##            "skills": {
##                "passive": "passive_id_xxx",
##                "actives": ["s1_id", "s2_id", "s3_id", "s4_id"],   # 恰好 4 个
##            },
##        }
##      - 注意：不要写 shield 字段——护盾初始恒为 0，除非特殊情况再用 set_shield。
##   2. 在 skill_effects.gd 里登记这 5 个技能的 DATA 元信息（含各自 element）与 EFFECTS 效果函数。
##
## 数值位说明：
##   element   = 英雄主属性（元素）
##   hp/energy = 生命 / 能量（初始值；能量可另写 energy_max 指定上限，缺省上限=初始）
##   armor     = 护甲（减伤字段，公式待定义）
##   speed     = 速度（决定行动先后，战斗层使用）
##   shield    = 一律不写（=0）
##   counters  = 通用计数资源池（叠层/攒资源）：
##        "元晶": {"start": 3, "per_turn": 1, "max": 0}
##        start=初始值, per_turn=每回合开始自动+（可省=0）, max=上限(0=不限)
##        技能用 unit.grant_counter/consume_counter/counter/grant_end_of_turn 操作
##   layer_rules = 层数规则（声明式，任何“叠层型”英雄复用）：
##        "污染": {"speed_per_layer": 15, "flag_threshold": {"失神": 3}}
##        speed_per_layer : 每层使该单位速度 -N（自动）
##        flag_threshold  : 层数>=阈值 自动置状态，层降自动清（可多条）
##        （层数增减自动触发，效果函数无需手动同步）

static func make(def_id: String) -> BattleUnit:
	var def: Dictionary = ALL.get(def_id, {})
	if def.is_empty():
		def = ALL.get("demo_hero", {})
	var d: Dictionary = def.duplicate(true)
	d["id"] = def_id
	return BattleUnit.new(d)

## 禁用英雄池：匹配/选人不可选（数据保留，待平衡后从列表移除即可恢复）
const BANNED := []   # 2026-09-07 李太白/虞美人已实装，移除禁用，全部 14 英雄可入选人/匹配池

## 该英雄是否可进入选人/匹配池
static func is_pickable(id: String) -> bool:
	return not BANNED.has(id) and str(id) != "demo_hero" and str(id) != "example_hero"

## 全部英雄注册表（剧情名单由用户随后提供；demo_hero 仅用于链路验证）
## 开发中英雄（用户制作中）：wip 骨架仅登记身份，供图鉴展示与小传挂载；数值/技能由用户填充后移除 wip
## BANNED 已收录 → 选人/匹配不可选
const ALL := {
	# —— 剧情英雄 · 元晶龙王（老方案 = 英雄资料汇总 01：血7/能12/速175；元晶印记 第2回合起 +1）——
	"crystal_dragon": {
		"name": "元晶龙王",
		"element": "元",
		"hp": 7, "shield_cap": 7, "energy": 12, "armor": 2, "speed": 175,
		"counters": {
			"元晶": {"start": 3, "per_turn": 1, "start_round": 2, "max": 0},
		},
		"skills": {
			"passive": "yuan_jing_mark",
			"actives": ["ning_cheng_jian_ren", "hua_jing_kai", "sui_jing_zhan", "yu_jing_wei_long"],
		},
	},
	# —— 剧情英雄 · 剑舞（王佳欣 · 新版本表；金 8/14/甲2/172）——
	"jianwu": {
		"name": "剑舞",
		"element": "金",
		"hp": 8, "energy": 14, "armor": 2, "speed": 172,
		"skills": {
			"passive": "jian_yi",
			"actives": ["shun_ji", "duan_liu", "guan_chuan", "zhu_xin"],
		},
	},
	# —— 剧情英雄 · 王泽 = 邪神（同学设计 + 用户改版 2026-09-03；hp4/armor1/speed174）——
	"xie_shen": {
		"name": "邪神",
		"element": "暗",
		"hp": 6, "energy": 20, "energy_max": 20, "armor": 1, "speed": 174,
		"skills": {
			"passive": "ji_sheng",
			"actives": ["hun_qi", "zhi_pei", "qin_ran", "hei_shan"],
		},
	},
	# —— 剧情英雄 · 光雨（刘星泽 · 新版本表；光 6/8/甲0/180）——
	"guang_yu": {
		"name": "光雨",
		"element": "光",
		"hp": 6, "energy": 8, "armor": 0, "speed": 180,
		"counters": {
			"星河": {"start": 0, "per_turn": 0, "max": 0},
		},
		# 2026-09-08：光雨被动改为每回合末回复 2 能量 + 1 生命（原为回合开始 +2 能、每 2 回合 +3 血 +2 能）
		"turn_end_effects": [
			{"kind": "energy", "amount": 2},
			{"kind": "hp", "amount": 1},
		],
		"skills": {
			"passive": "xing_he",
			"actives": ["guang_ru_shi", "shi_ru_yu", "yu_ru_xing", "xing_ru_he"],
		},
	},
	# —— 剧情英雄 · 药师（杨鑫翰 · 新版本表；木 10血/能量见被动·无上限/甲1/102）——
	"yao_shi": {
		"name": "药师",
		"element": "木",
		"hp": 10, "shield_cap": 6, "energy": 0, "energy_max": -1, "armor": 1, "speed": 102,   # 2026-09-08 平衡：护盾上限 10→6
		"turn_end_effects": [
			{"kind": "if_hp_shield", "hp_max": 4, "hp": 1, "shield": 1},
		],
		"skills": {
			"passive": "gao_yu",
			"actives": ["jian_mu_sheng_fa", "shou_wan_huo_zu", "shi_zhe_yi_xin", "yao_ling"],
		},
	},
	# —— 剧情英雄 · 追猎（孙广泽 · 新版本表；创伤/流血/灼烧体系示范）——
	"zhuilie": {
		"name": "追猎",
		"element": "机械",
		"hp": 8, "energy": 6, "armor": 3, "speed": 120,
		"skills": {
			"passive": "zhuilie_ymxb",
			"actives": ["snap_shot", "hunt", "shield_up", "meteor_shot"],
		},
	},

	# —— 剧情英雄 · 孤狼（叶麟 · 物理 8/12/甲2/160；锻体/防守/斩杀低血）——
	"gu_lang": {
		"name": "孤狼", "element": "物理",
		"hp": 8, "energy": 12, "armor": 2, "speed": 160,
		"skills": {"passive": "duan_ti", "actives": ["yin_yang_san_shou", "shen_suo_quan", "pu_tong_quan", "xue_yu"]},
	},
	# —— 剧情英雄 · rapper睡神（何至高 · 神秘 7/13/甲1/170；掠夺/魅惑/无敌/冰封）——
	"he_zhigao": {
		"name": "rapper睡神", "element": "神秘",
		"hp": 7, "energy": 13, "armor": 1, "speed": 170,
		"hp_threshold_flags": [{"flag": "rage", "pct": 20, "dmg_mult": 2.0}],
		"skills": {"passive": "kuang_nu", "actives": ["lve_duo", "mei_huo", "suo_xue", "wan_li_bing_feng"]},
	},
	# —— 剧情英雄 · 仙尊（陈雨晴 · 圣灵 6/18/甲1/131；涅槃复活/五行/剑域）——
	"xian_zun": {
		"name": "仙尊", "element": "圣灵",
		"hp": 6, "energy": 18, "armor": 1, "speed": 131,
		"turn_end_effects": [{"kind": "energy", "amount": 4}],
		"death_revive": {"rounds": 1, "hp_pct": 50, "per_game": 1},
		"skills": {"passive": "nie_pan", "actives": ["wu_xing_zhi_li", "shu_fu_zhi_ling", "zhuan_jia_kui_lei", "wan_jian_gui_zong"]},
	},
	# —— 剧情英雄 · 灵虚数影（辛子祺老师不离谱版 · 神秘 6/32/甲0/234；60%闪避/增伤/破甲）——
	"ling_xu": {
		"name": "灵虚数影", "element": "神秘",
		"hp": 6, "shield_cap": 6, "energy": 32, "armor": 0, "speed": 234, "evasion_pct": 60,
		"skills": {"passive": "shu_yu", "actives": ["tian_ji", "jie_xi", "ji_dian", "shu_hai_teng_nuo"]},
	},
	# —— 剧情英雄 · 辛克莱（新表：火 6血/理智机制 上限25/甲1/136）——
	"xin_kelai": {
		"name": "辛克莱", "element": "火",
		"hp": 6, "energy": 0, "energy_max": -1, "armor": 1, "speed": 136, "sanity_cap": 25,
		"element_damage_bonus": {"机械": 10},
		"turn_end_effects": [{"kind": "sanity", "ratio": 0.3}],
		"skills": {"passive": "he_bi", "actives": ["po_bu_de_yi", "hei_bai", "zi_wo_destroy", "xuan_zhong"]},
	},

	# —— 剧情英雄 · 流萤（【火萤IV型】SAM战略强袭装甲）——
	"liu_ying": {
		"name": "流萤", "element": "火",
		"hp": 12, "energy": 20, "armor": 0, "speed": 100,
		"skills": {
			"passive": "ying_huo_zhong_shu",
			"actives": ["tian_huo", "", "", ""],
		},
	},

	# —— 剧情英雄 · 李太白（诗仙）——
	"li_taibai": {
		"name": "李太白", "element": "金",
		"hp": 8, "energy": 25, "armor": 1, "speed": 205,
		"counters": {
			"醉意": {"start": 0, "per_turn": 1, "max": 20},
		},
		"turn_start_effects": [
			{"kind": "drunk_check"},
		],
		"skills": {
			"passive": "mei_jiu",
			"actives": ["jiang_jin_jiu", "bi_mo_hui_sa", "si_yi", "yu_jun_tong_zui"],
		},
	},
	# —— 剧情英雄 · 虞美人（怀恨）——
	"yu_mei_ren": {
		"name": "虞美人", "element": "木",
		"hp": 15, "energy": 30, "armor": 0, "speed": 0,
		"non_solid": true,
		"counters": {
			"愤恨": {"start": 2, "max": 99},
		},
		"skills": {
			"passive": "ku_chu",
			"actives": ["man_yan", "qing_su", "ni_bu_zai_ai_wo", "hui_hen"],
		},
	},

	"demo_hero": {
		"name": "演示英雄",
		"element": "火",
		"hp": 120, "energy": 80, "armor": 5, "speed": 6,
		"skills": {
			"passive": "stub_passive",
			"actives": ["stub_skill_1", "stub_skill_2", "stub_skill_3", "stub_skill_4"],
		},
	},
}

static func list_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in ALL:
		ids.append(str(k))
	return ids
