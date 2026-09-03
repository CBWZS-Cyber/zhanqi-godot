class_name SkillEffects
## 技能元信息 + 效果函数注册表（剧情模式）。
##
## 给一个英雄加技能的两步：
##   1) 在本文件 DATA 中登记技能元信息（name/kind/energy_cost/cooldown/desc）；
##   2) 在 EFFECTS 中把技能 id 指向一个效果函数，并在下方实现函数体。
##
## 效果函数签名（所有技能统一）：
##   func 效果_xxx(user: BattleUnit, ctx: Dictionary) -> String
##   - user：释放者（被动触发时 = 该英雄自己）
##   - ctx ：战斗上下文字典，至少约定：
##       ctx["targets"] : Array[BattleUnit]（主动技能的目标，被动可为空）
##       ctx["battle"]  : 战斗层对象（未来提供，目前可传 {}）
##   - 返回 String：本效果产生的一条战斗日志文本（可为空字符串）
##
## 护盾相关说明：BattleUnit.shield 初始恒为 0，战斗中的护盾只能由本文件的
## “护盾技能/效果”加出来（add_shield / set_shield）。英雄基础属性里不放护盾值。

const DATA := {
	# 被动技能示例（后续由剧情英雄数据替换/新增）
	"stub_passive": {
		"name": "模板被动",
		"element": "光",
		"kind": "passive",
		"desc": "占位被动，效果待填写。",
	},
	# 主动技能示例
	"stub_skill_1": {
		"name": "模板攻击",
		"element": "火",
		"kind": "active",
		"energy_cost": 10,
		"cooldown": 0,
		"desc": "占位主动技能，效果待填写。",
	},
	"stub_skill_2": {
		"name": "模板护盾",
		"element": "—",
		"kind": "active",
		"energy_cost": 15,
		"cooldown": 2,
		"desc": "给自己加一层护盾（示例调用 add_shield）。",
	},
	"stub_skill_3": {
		"name": "模板治疗",
		"element": "光",
		"kind": "active",
		"energy_cost": 20,
		"cooldown": 0,
		"desc": "治疗自己（示例调用 heal）。",
	},
	"stub_skill_4": {
		"name": "模板爆发",
		"element": "雷",
		"kind": "active",
		"energy_cost": 30,
		"cooldown": 3,
		"desc": "占位大招，效果待填写。",
	},

	# ===== 元晶龙王（老方案 = 英雄资料汇总 01）=====
	## 元晶：开局 3 枚，从第 2 回合起每回合初 +1（引擎 counters start_round 自动处理）
	"yuan_jing_mark": {
		"name": "元晶印记",
		"element": "元",
		"kind": "passive",
		"desc": "初始持有 3 枚元晶，从第 2 回合起每回合初获得 1 枚元晶。",
	},
	"ning_cheng_jian_ren": {
		"name": "凝元晶为刃",
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "消耗 1 枚元晶，对 1 个目标造成 3 点伤害。",
	},
	"hua_jing_kai": {
		"name": "化晶为铠",
		"element": "元",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "消耗 2 枚元晶，获得 3 点护盾并回复 2 点能量。",
	},
	"sui_jing_zhan": {
		"name": "碎晶斩",
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "自身有护盾时，清空护盾，对 1 个目标造成 3 点真实伤害（无护盾无法发动）。",
	},
	"yu_jing_wei_long": {
		"name": "御晶为龙",
		"element": "元",
		"kind": "ultimate",
		"energy_cost": 9,
		"cooldown": 0,
		"desc": "消耗 3 枚元晶，对最多 3 个目标各造成 2 点伤害，并获得 1 枚元晶。",
	},

	# ===== 追猎（孙广泽 · 新版本表；创伤/流血/灼烧体系示范）=====
	"zhuilie_ymxb": {
		"name": "以命相搏",
		"element": "机械",
		"kind": "passive",
		"desc": "生命值≤3时，速度增加200点，护甲清零，每回合获得2点护盾。",
	},
	"snap_shot": {
		"name": "狙击",
		"element": "机械",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程3格，对1个目标造成1点伤害，附加「创伤」印记；积累3层时清空印记并触发「流血2级」。",
	},
	"hunt": {
		"name": "追猎",
		"element": "机械",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "位移后额外发动一次「狙击」。（位移由战斗层执行）",
	},
	"shield_up": {
		"name": "架盾",
		"element": "机械",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "获得2点护盾，护甲+1（上限3）。",
	},
	"meteor_shot": {
		"name": "流星飞弹",
		"element": "机械",
		"kind": "ultimate",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "全图射程，攻击2个目标各造成3点伤害，附加「灼烧1级」；若目标已有「流血2级」则升为「流血3级」；护甲-1。一局仅限一次。",
	},

	# ===== 邪神（王泽）· 同学设计 + 用户改版 2026-09-03 =====
	## 污染层 = 每层使目标速度 -15；层数 ≥3 → 失神
	"ji_sheng": {
		"name": "寄生",
		"element": "暗",
		"kind": "passive",
		"desc": "每回合末向附近格子内的敌人 +1 层污染。每层污染使该单位速度 -15；污染 ≥3 时进入失神状态。",
	},
	"hun_qi": {
		"name": "魂契（暂名，待定）",
		"element": "暗",
		"kind": "active",
		"energy_cost": 7,
		"cooldown": 0,
		"desc": "本回合所有伤害由失神状态下的敌方棋子均摊；回合末吸取失神敌当前生命的 30%。（伤害均摊需战斗层接伤害管线）",
	},
	"zhi_pei": {
		"name": "支配",
		"element": "暗",
		"kind": "active",
		"energy_cost": 5,
		"cooldown": 0,
		"desc": "对周围敌人触发：污染 ≥5 时消耗 3 层，支配该单位 2 回合（下一回合起生效）。单挑模式：污染 ≥8 直接斩杀敌方并获胜。",
	},
	"qin_ran": {
		"name": "侵染",
		"element": "暗",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "对周围所有敌人造成 2 点伤害；60% 概率使每个目标额外 +1 污染；回复 5 点能量和 2 点生命。",
	},
	"hei_shan": {
		"name": "黑闪",
		"element": "暗",
		"kind": "active",
		"energy_cost": 15,
		"cooldown": 0,
		"desc": "对周围所有敌人触发：消耗其全部污染层，每层使其失去 10% 最大生命；原污染 ≥6：4V4 永久支配该单位，单挑直接斩杀获胜。",
	},
}

## 效果注册表：id -> Callable
const EFFECTS := {
	"stub_passive": Callable(SkillEffects, "_ef_stub_passive"),
	"stub_skill_1": Callable(SkillEffects, "_ef_stub_attack"),
	"stub_skill_2": Callable(SkillEffects, "_ef_stub_shield"),
	"stub_skill_3": Callable(SkillEffects, "_ef_stub_heal"),
	"stub_skill_4": Callable(SkillEffects, "_ef_stub_burst"),
	# 元晶龙王（老方案）
	"yuan_jing_mark": Callable(SkillEffects, "_ef_yuan_jing_mark"),
	"ning_cheng_jian_ren": Callable(SkillEffects, "_ef_ning_cheng_jian_ren"),
	"hua_jing_kai": Callable(SkillEffects, "_ef_hua_jing_kai"),
	"sui_jing_zhan": Callable(SkillEffects, "_ef_sui_jing_zhan"),
	"yu_jing_wei_long": Callable(SkillEffects, "_ef_yu_jing_wei_long"),
	# 追猎（孙广泽）
	"zhuilie_ymxb": Callable(SkillEffects, "_ef_zl_ymxb"),
	"snap_shot": Callable(SkillEffects, "_ef_snap_shot"),
	"hunt": Callable(SkillEffects, "_ef_hunt"),
	"shield_up": Callable(SkillEffects, "_ef_shield_up"),
	"meteor_shot": Callable(SkillEffects, "_ef_meteor_shot"),
	# 邪神（王泽）
	"ji_sheng": Callable(SkillEffects, "_ef_ji_sheng"),
	"hun_qi": Callable(SkillEffects, "_ef_hun_qi"),
	"zhi_pei": Callable(SkillEffects, "_ef_zhi_pei"),
	"qin_ran": Callable(SkillEffects, "_ef_qin_ran"),
	"hei_shan": Callable(SkillEffects, "_ef_hei_shan"),
}

## 兜底：未注册效果的技能
static func effect_stub(_user: BattleUnit, _ctx: Dictionary) -> String:
	return "（效果未实现）"

## ---------- 下方是各技能效果的“填写区” ----------
## 用户之后逐个把函数体替换成真正的效果逻辑，并在 EFFECTS 中保持映射即可。
## 常用数值操作速查（battle_unit.gd）：
##   user.take_damage(x) -> 扣血（护盾吸收→护甲减免）
##   user.lose_hp(x)      -> 无视护盾直接扣血
##   user.heal(x)         -> 回血
##   user.add_shield(x) / set_shield(x) / remove_shield(x) / clear_shield()
##   user.add_energy(x) / user.spend_energy(x)
##   ctx.get("targets", []) 可取目标数组（BattleUnit）

static func _ef_stub_passive(user: BattleUnit, _ctx: Dictionary) -> String:
	# TODO: 被动效果（例如“每回合开始回 X 血/加 X 盾”等）
	return "%s 的【模板被动】触发（效果待填写）" % user.name

static func _ef_stub_attack(user: BattleUnit, ctx: Dictionary) -> String:
	# TODO: 主动技能效果
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【模板攻击】" % user.name
	for t in targets:
		var r: Dictionary = t.take_damage(20)
		out += "，对 %s 造成 %d 伤害" % [t.name, r["hp_lost"] + r["absorbed"]]
	return out

static func _ef_stub_shield(user: BattleUnit, _ctx: Dictionary) -> String:
	# 示例：护盾函数用法 —— 给 30 护盾
	var before := user.shield
	user.add_shield(30)
	return "%s 获得护盾 %d → %d" % [user.name, 30, user.shield]

static func _ef_stub_heal(user: BattleUnit, _ctx: Dictionary) -> String:
	var amount := user.heal(25)
	return "%s 恢复 %d 生命（%d/%d）" % [user.name, amount, user.hp, user.max_hp]

static func _ef_stub_burst(user: BattleUnit, _ctx: Dictionary) -> String:
	# TODO: 大招效果
	return "%s 释放【模板爆发】（效果待填写）" % user.name

## ========== 元晶龙王（老方案）效果 ==========
## 元晶 = 计数资源池（BattleUnit.counter / grant_counter / consume_counter）；
## 自动增长由 counters{"元晶": start3, per_turn1, start_round2} 引擎维护（第 2 回合起 +1）。

## 被动（展示；增长由引擎处理）
static func _ef_yuan_jing_mark(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【元晶印记】生效：当前元晶 %d 枚（第 2 回合起每回合 +1）" % [user.name, user.counter("元晶")]

## 凝元晶为刃：耗 1 元晶 → 单体 3 伤
static func _ef_ning_cheng_jian_ren(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("元晶") < 1:
		return "%s 元晶不足，【凝元晶为刃】无法发动" % user.name
	user.consume_counter("元晶", 1)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【凝元晶为刃】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
	if targets.is_empty():
		out += "（无目标）"
	return out

## 化晶为铠：耗 2 元晶 → 3 盾 + 回 2 能
static func _ef_hua_jing_kai(user: BattleUnit, _ctx: Dictionary) -> String:
	if user.counter("元晶") < 2:
		return "%s 元晶不足 2 枚，【化晶为铠】无法发动" % user.name
	user.consume_counter("元晶", 2)
	user.add_shield(3)
	var got := user.add_energy(2)
	return "%s 消耗 2 枚元晶：护盾 +3（现 %d），回复 %d 能量（%d/%d）" % [user.name, user.shield, got, user.energy, user.max_energy]

## 碎晶斩：自身有盾 → 清空护盾，单体 3 真伤（无盾无法发动）
static func _ef_sui_jing_zhan(user: BattleUnit, ctx: Dictionary) -> String:
	if user.shield <= 0:
		return "%s 没有护盾，【碎晶斩】无法发动（先用化晶为铠等获取护盾）" % user.name
	var before_shield := user.shield
	user.clear_shield()
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【碎晶斩】（清空 %d 点护盾）" % [user.name, before_shield]
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var before := tu.hp
		tu.lose_hp(3)
		out += "；%s 受 %d 真伤" % [tu.name, before - tu.hp]
	if targets.is_empty():
		out += "（无目标）"
	return out

## 御晶为龙（终极）：耗 3 元晶 → 至多 3 目标各 2 伤 + 回 1 元晶
static func _ef_yu_jing_wei_long(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("元晶") < 3:
		return "%s 元晶不足 3 枚，【御晶为龙】无法发动" % user.name
	user.consume_counter("元晶", 3)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【御晶为龙】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		hit += 1
	user.grant_counter("元晶", 1)
	out += "；收回 1 枚元晶（现 %d）" % user.counter("元晶")
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 邪神（王泽）效果 ==========
## 污染层：挂在每个目标自己身上（target.counter("污染")），每层速度 -15，≥3 层失神。
## 同步速度惩罚/失神标志的公共维护：
static func _pollute(t: BattleUnit, n: int) -> void:
	# 施加端注册污染规则（幂等）：每层 -15 速、≥3 层失神。敌方单位无需自带配置。
	t.watch_layer_speed("污染", 15)
	t.watch_layer_flag("污染", 3, "失神")
	t.grant_counter("污染", n)

## 被动寄生：回合末对“附近敌人”（ctx.targets）各 +1 污染
static func _ef_ji_sheng(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 的【寄生】回合末发动" % user.name
	if targets.is_empty():
		return out + "（附近无敌人）"
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		_pollute(tu, 1)
		out += "；%s 污染 +1（共 %d，速度 %d）" % [tu.name, tu.counter("污染"), tu.effective_speed()]
	return out

## 一技能·魂契（暂名，待定）：登记本回合分担/回合末吸血（伤害均摊需战斗层拦截伤害管线）
static func _ef_hun_qi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	user.begin_share_round(targets)
	return "%s 立下【魂契】：本回合伤害由失神敌人均摊，回合末吸取失神敌当前生命的 30%%" % user.name

## 二技能·支配：周围敌人触发；目标污染≥5 → 耗 3 层，支配 2 回合（下回合起）；
## 单挑模式：目标污染 ≥8 → 斩杀获胜
static func _ef_zhi_pei(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var mode := str(ctx.get("mode", "4v4"))
	var out := "%s 释放【支配】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if mode == "1v1":
			if tu.counter("污染") >= 8:
				tu.lose_hp(tu.hp)
				out += "；单挑斩杀 %s（污染 %d ≥ 8）→ 邪神获胜" % [tu.name, tu.counter("污染")]
				_call_win(ctx)
			else:
				out += "；%s 污染 %d 不足 8，无法斩杀" % [tu.name, tu.counter("污染")]
			continue
		if tu.counter("污染") < 5:
			out += "；%s 污染 %d 不足 5" % [tu.name, tu.counter("污染")]
			continue
		tu.consume_counter("污染", 3)
		tu.add_flag("将被支配")            # 下一回合起生效（战斗层读）
		tu.set_meta("dominate_rounds", 2)  # 持续 2 回合
		out += "；%s 被支配 2 回合（污染≥5，耗3层，现 %d）" % [tu.name, tu.counter("污染")]
	return out

## 三技能·侵染：周围所有敌人 2 伤；60% 概率额外 +1 污染；回 5 能量 + 回 2 生命
static func _ef_qin_ran(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【侵染】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		if randf() < 0.6:
			_pollute(tu, 1)
			out += "，污染+1（共 %d）" % tu.counter("污染")
	user.add_energy(5)
	var healed := user.heal(2)
	out += "；回复 5 能量（%d/%d）、%d 点生命" % [user.energy, user.max_energy, healed]
	return out

## 大招·黑闪：周围敌人——耗其全部污染层，每层失去 10% 最大生命；
## 原污染 ≥6：4V4 永久支配；单挑改为斩杀获胜
static func _ef_hei_shan(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var mode := str(ctx.get("mode", "4v4"))
	var out := "%s 释放【黑闪】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var layers := tu.counter("污染")
		if layers > 0:
			tu.consume_counter("污染", layers)
			var loss := ceili(float(tu.max_hp) * 0.1 * float(layers))
			tu.lose_hp(loss)
			out += "；%s 失去 %d 点生命（%d 层×10%%）" % [tu.name, loss, layers]
		if layers >= 6:
			if mode == "1v1":
				tu.lose_hp(tu.hp)
				out += "，单挑斩杀 %s → 邪神获胜" % tu.name
				_call_win(ctx)
			else:
				tu.add_flag("永久支配")
				out += "，%s 被永久支配" % tu.name
	return out

static func _call_win(ctx: Dictionary) -> void:
	var hook: Variant = ctx.get("on_win", null)
	if hook is Callable:
		(hook as Callable).call()

## ========== 通用工具（写新英雄效果时直接调用，避免重复循环） ==========

## 对一组目标造成伤害（true_dmg=true 走真伤 lose_hp）。返回追加的日志片段。
static func hit_group(targets: Array, dmg: int, true_dmg := false) -> String:
	var out := ""
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if true_dmg:
			var before := tu.hp
			tu.lose_hp(dmg)
			out += "，%s 受 %d 真伤" % [tu.name, before - tu.hp]
		else:
			var r: Dictionary = tu.take_damage(dmg)
			out += "，%s 受 %d 伤害" % [tu.name, r["hp_lost"] + r["absorbed"]]
	return out

## 目标失去“最大生命 N%”（每层×pct 的百分比扣血用），返回实际损失量
static func lose_pct_max_hp(t: BattleUnit, pct_per: int, times: int) -> int:
	var loss := ceili(float(t.max_hp) * 0.01 * float(pct_per) * float(times))
	if loss > 0:
		t.lose_hp(loss)
	return loss

## 给一组目标各 +n 层资源（自动触发 layer_rules）
static func grant_layer_each(targets: Array, layer: String, n: int) -> String:
	var out := ""
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.grant_counter(layer, n)
		out += "，%s %s +%d（共 %d）" % [tu.name, layer, n, tu.counter(layer)]
	return out

## ========== 状态/印记公共基元（通用，勿为单个英雄复制） ==========
## 层数制：bleed 流血 / burn 灼烧 / wound 创伤 / freeze 冻伤… 存 unit.statuses
## 结算时机：行动时(施放技能/移动)看 bleed；回合开始时看 burn；回合末 bleed 衰减 1。

static func status_cn(id: String) -> String:
	var m := {
		"bleed": "流血", "burn": "灼烧", "wound": "创伤", "freeze": "冻伤",
		"poison": "中毒", "burn2": "灼烧2",
	}
	return String(m.get(id, id))

## 行动触发（施放技能/移动）：结算自身流血 —— 每层 1 点真伤，层数不变（回合末才减）
static func tick_action_statuses(u: BattleUnit) -> String:
	var b := u.status_stacks("bleed")
	if b <= 0:
		return ""
	var before := u.hp
	u.lose_hp(b)
	return "%s 行动触发流血：失去 %d 点生命（%d/%d）" % [u.name, before - u.hp, u.hp, u.max_hp]

## 回合开始触发：灼烧 —— 造成层数伤害后层数 -2
static func tick_start_of_turn_statuses(u: BattleUnit) -> String:
	var b := u.status_stacks("burn")
	if b <= 0:
		return ""
	var dmg := b
	u.set_status("burn", b - 2)
	var before := u.hp
	u.lose_hp(dmg)
	return "%s 被灼烧：失去 %d 点生命，灼烧层 %d→%d" % [u.name, before - u.hp, b, u.status_stacks("burn")]

## 回合末触发：流血层数 -1
static func tick_end_of_turn_statuses(u: BattleUnit) -> String:
	if u.status_stacks("bleed") <= 0:
		return ""
	var b := u.status_stacks("bleed")
	u.set_status("bleed", b - 1)
	return "%s 流血衰减：%d→%d 层" % [u.name, b, u.status_stacks("bleed")]

## 施加创伤印记（wound）：满 3 层清空并触发「流血2级」
static func add_wound(t: BattleUnit, n: int) -> String:
	t.add_status("wound", n)
	if t.status_stacks("wound") >= 3:
		t.set_status("wound", 0)
		t.add_status("bleed", 2)
		return "，%s 创伤满 3 层 → 触发流血2级" % t.name
	return "，%s 创伤 +%d（共 %d）" % [t.name, n, t.status_stacks("wound")]

## 对目标打一发“狙击”（1 伤 + 创伤）
static func _fire_snap(user: BattleUnit, t: BattleUnit, extra: String) -> String:
	var r: Dictionary = t.take_damage(1)
	var out := "%s%s：%s 受 %d 伤" % [user.name, extra, t.name, r["hp_lost"] + r["absorbed"]]
	out += add_wound(t, 1)
	return out

## ========== 追猎（孙广泽）效果 ==========
## 被动·以命相搏：生命≤3 → 速+200、护甲清零、每回合+2盾（战斗层每回合开始调用 trigger_passive）
static func _ef_zl_ymxb(user: BattleUnit, _ctx: Dictionary) -> String:
	if user.hp <= 3:
		if not user.has_flag("zl_lowhp"):
			user.add_flag("zl_lowhp")
			user.set_speed_buff(200)
			user.set_armor(0)
		user.add_shield(2)
		return "%s 触发【以命相搏】：速度 +200（现 %d）、护甲清零、获得 2 点护盾" % [user.name, user.effective_speed()]
	if user.has_flag("zl_lowhp"):
		user.clear_flag("zl_lowhp")
		user.set_speed_buff(0)
	return "%s 生命 %d/3 以上，【以命相搏】未触发" % [user.name, user.hp]

## 主动1·狙击：单体 1 伤 + 创伤
static func _ef_snap_shot(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【狙击】（无目标）" % user.name
	return _fire_snap(user, targets[0] as BattleUnit, " 释放【狙击】")

## 主动2·追猎：位移后额外发动一次狙击（位移本体由战斗层执行）
static func _ef_hunt(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【追猎】（位移后无目标）" % user.name
	return _fire_snap(user, targets[0] as BattleUnit, " 释放【追猎】位移后额外狙击")

## 主动3·架盾：2 盾 + 护甲+1（上限3）
static func _ef_shield_up(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_shield(2)
	var ag := user.add_armor(1, 3)
	return "%s 释放【架盾】：护盾 +2（现 %d），护甲 +%d（现 %d）" % [user.name, user.shield, ag, user.armor]

## 终极·流星飞弹：至多2目标各3伤 + 灼烧1；已有流血2级→升3级；护甲-1（一局一次由战斗层限制）
static func _ef_meteor_shot(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【流星飞弹】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 2:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		if tu.status_stacks("bleed") >= 2:
			tu.set_status("bleed", 3)
			out += "，流血升级为3级"
		else:
			tu.add_status("burn", 1)
			out += "，附加灼烧1级"
		tu.remove_armor(1)
		out += "，护甲-1"
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 重灾区防护基元（目标/阵营/加成/斩杀/先手） ==========

## 按关系过滤目标：rel = "enemy"(敌对) / "ally"(同队,含自己可选) / "any"
static func filter_by_relation(targets: Array, me: BattleUnit, rel: String, include_self := false) -> Array:
	var out: Array = []
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if not include_self and tu == me:
			continue
		var enemy := tu.team != me.team
		var hit_ok := false
		if rel == "any":
			hit_ok = true
		elif rel == "enemy":
			hit_ok = enemy
		elif rel == "ally":
			hit_ok = not enemy
		if hit_ok:
			out.append(tu)
	return out

## 目标当前生命百分比（0..100，按最大生命）
static func hp_pct(t: BattleUnit) -> int:
	if t.max_hp <= 0:
		return 100
	return int(round(float(t.hp) / float(t.max_hp) * 100.0))

## 条件斩杀：目标当前生命 ≤ 最大生命的 pct% 时直接斩杀（返回真）
static func cut_if_under_pct(t: BattleUnit, pct: int) -> bool:
	if hp_pct(t) <= pct:
		t.lose_hp(t.hp)
		return true
	return false

## 伤害结算走“技能槽伤害加成”：user.slot_damage(slot, base) 后统一打
static func hit_group_slot(user: BattleUnit, slot: int, targets: Array, base: int, true_dmg := false) -> String:
	var dmg := user.slot_damage(slot, base)
	return hit_group(targets, dmg, true_dmg)

## 先手排序：按 effective_speed 降序；同速按数组原顺序（Battle 每轮开始时取一次快照，
## 本轮内速度变化不重排——固定规则，见 battle 层约定）
static func speed_order(units: Array) -> Array:
	var lst: Array = []
	for u in units:
		if u is BattleUnit:
			lst.append(u)
	# 冒泡降序（严格大于才交换 → 同速保持原顺序，作为先手快照稳定）
	for i in range(lst.size()):
		for j in range(i + 1, lst.size()):
			var ai: BattleUnit = lst[i]
			var aj: BattleUnit = lst[j]
			if aj.effective_speed() > ai.effective_speed():
				lst[i] = aj
				lst[j] = ai
	return lst
