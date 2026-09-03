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

## 全部英雄注册表（剧情名单由用户随后提供；demo_hero 仅用于链路验证）
const ALL := {
	# —— 剧情英雄 · 曹博文 = 元晶龙王（表格 2026-09-03 导出，小数值制；速度 128）——
	"crystal_dragon": {
		"name": "元晶龙王",
		"element": "元",
		"hp": 5, "energy": 15, "armor": 2, "speed": 128,
		"counters": {
			"元晶": {"start": 2, "per_turn": 1, "max": 0},
		},
		"skills": {
			"passive": "yuan_jing",
			"actives": ["jing_kai", "jing_ren", "ning_jing", "jing_long"],
		},
	},
	# —— 剧情英雄 · 王泽 = 邪神（同学设计 + 用户改版 2026-09-03；hp4/armor1/speed174）——
	"xie_shen": {
		"name": "邪神",
		"element": "暗",
		"hp": 4, "energy": 10, "energy_max": 20, "armor": 1, "speed": 174,
		"skills": {
			"passive": "ji_sheng",
			"actives": ["hun_qi", "zhi_pei", "qin_ran", "hei_shan"],
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
