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

## ========== 联机确定性随机（阶段1）==========
## 效果函数内的随机一律走 user.rng（战斗层注入的同步 RNG）；null 回退全局（单机旧路径）
static func _sync_randf(user: BattleUnit) -> float:
	return user.rng.randf() if user.rng != null else randf()

static func _sync_randi(user: BattleUnit) -> int:
	return user.rng.randi() if user.rng != null else randi()

## 技能元信息表已拆分到 skill_data.gd（2026-09-30）；此处转发，SkillEffects.DATA 的调用点保持不变。
const DATA := SkillData.DATA

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
	# 剑舞（王佳欣）
	"jian_yi": Callable(SkillEffects, "_ef_jian_yi"),
	"shun_ji": Callable(SkillEffects, "_ef_shun_ji"),
	"duan_liu": Callable(SkillEffects, "_ef_duan_liu"),
	"guan_chuan": Callable(SkillEffects, "_ef_guan_chuan"),
	"zhu_xin": Callable(SkillEffects, "_ef_zhu_xin"),
	# 光雨（刘星泽）
	"xing_he": Callable(SkillEffects, "_ef_xing_he"),
	"guang_ru_shi": Callable(SkillEffects, "_ef_guang_ru_shi"),
	"shi_ru_yu": Callable(SkillEffects, "_ef_shi_ru_yu"),
	"yu_ru_xing": Callable(SkillEffects, "_ef_yu_ru_xing"),
	"xing_ru_he": Callable(SkillEffects, "_ef_xing_ru_he"),
	# 药师（杨鑫翰）
	"gao_yu": Callable(SkillEffects, "_ef_gao_yu"),
	"jian_mu_sheng_fa": Callable(SkillEffects, "_ef_jian_mu_sheng_fa"),
	"shou_wan_huo_zu": Callable(SkillEffects, "_ef_shou_wan_huo_zu"),
	"shi_zhe_yi_xin": Callable(SkillEffects, "_ef_shi_zhe_yi_xin"),
	"yao_ling": Callable(SkillEffects, "_ef_yao_ling"),

	# 孤狼（叶麟）
	"duan_ti": Callable(SkillEffects, "_ef_duan_ti"), "yin_yang_san_shou": Callable(SkillEffects, "_ef_yyss"),
	"shen_suo_quan": Callable(SkillEffects, "_ef_ssq"), "pu_tong_quan": Callable(SkillEffects, "_ef_ptq"),
	"xue_yu": Callable(SkillEffects, "_ef_xue_yu"),
	# rapper睡神（何至高）
	"kuang_nu": Callable(SkillEffects, "_ef_kn"), "lve_duo": Callable(SkillEffects, "_ef_lve"),
	"mei_huo": Callable(SkillEffects, "_ef_meihuo"), "suo_xue": Callable(SkillEffects, "_ef_suoxue"),
	"wan_li_bing_feng": Callable(SkillEffects, "_ef_wanli"),
	# 仙尊（陈雨晴）
	"nie_pan": Callable(SkillEffects, "_ef_niepan"), "wu_xing_zhi_li": Callable(SkillEffects, "_ef_wuxing"),
	"shu_fu_zhi_ling": Callable(SkillEffects, "_ef_shufu"), "zhuan_jia_kui_lei": Callable(SkillEffects, "_ef_zhuanjia"),
	"wan_jian_gui_zong": Callable(SkillEffects, "_ef_wanjian"),
	# 灵虚数影
	"shu_yu": Callable(SkillEffects, "_ef_shuyu"), "tian_ji": Callable(SkillEffects, "_ef_tianji"),
	"jie_xi": Callable(SkillEffects, "_ef_jiexi"), "ji_dian": Callable(SkillEffects, "_ef_jidian"),
	"shu_hai_teng_nuo": Callable(SkillEffects, "_ef_shuhai"),
	# 辛克莱
	"he_bi": Callable(SkillEffects, "_ef_hebi"), "po_bu_de_yi": Callable(SkillEffects, "_ef_pbdy"),
	"hei_bai": Callable(SkillEffects, "_ef_heibai"), "zi_wo_destroy": Callable(SkillEffects, "_ef_zishu"),
	"xuan_zhong": Callable(SkillEffects, "_ef_xuanzhong"),

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
	# 流萤（火萤IV型）
	"tian_huo": Callable(SkillEffects, "_ef_tian_huo"),
	"di_huo_zhan_ji": Callable(SkillEffects, "_ef_di_huo_zhan_ji"),
	"si_xing_guo_zai": Callable(SkillEffects, "_ef_si_xing_guo_zai"),
	"chao_xin_xing": Callable(SkillEffects, "_ef_chao_xin_xing"),
	# 李太白
	"mei_jiu": Callable(SkillEffects, "_ef_stub_passive"), "jiang_jin_jiu": Callable(SkillEffects, "_ef_jiang_jin_jiu"),
	"bi_mo_hui_sa": Callable(SkillEffects, "_ef_bi_mo_hui_sa"), "si_yi": Callable(SkillEffects, "_ef_si_yi"),
	"yu_jun_tong_zui": Callable(SkillEffects, "_ef_yu_jun_tong_zui"),
	# 虞美人
	"ku_chu": Callable(SkillEffects, "_ef_stub_passive"), "man_yan": Callable(SkillEffects, "_ef_man_yan"),
	"qing_su": Callable(SkillEffects, "_ef_qing_su"), "ni_bu_zai_ai_wo": Callable(SkillEffects, "_ef_ni_bu_zai_ai_wo"),
	"hui_hen": Callable(SkillEffects, "_ef_hui_hen"),
	# 骑士线第一关 · 白灵殿（剧情兵种）
	"s1_jie_yu_lv": Callable(SkillEffects, "_ef_s1_jie_yu_lv"),
	"s1_zhi_yu_ze": Callable(SkillEffects, "_ef_s1_zhi_yu_ze"),
	"s1_qiang_quan": Callable(SkillEffects, "_ef_s1_qiang_quan"),
	"s1_ling_zhen": Callable(SkillEffects, "_ef_s1_ling_zhen"),
	"s1_jian_gu": Callable(SkillEffects, "_ef_s1_jian_gu"),
	"s1_jue_xin": Callable(SkillEffects, "_ef_s1_jue_xin"),
	"s1_yin_lei": Callable(SkillEffects, "_ef_s1_yin_lei"),
	"s1_guan_huai": Callable(SkillEffects, "_ef_s1_guan_huai"),
	"s1_ling_dong": Callable(SkillEffects, "_ef_s1_ling_dong"),
	"s1_chi_cheng": Callable(SkillEffects, "_ef_s1_chi_cheng"),
	"s1_ke_ran_dian": Callable(SkillEffects, "_ef_s1_ke_ran_dian"),
	"s1_yan_quan": Callable(SkillEffects, "_ef_s1_yan_quan"),
	"s1_bu_zhi_huo": Callable(SkillEffects, "_ef_s1_bu_zhi_huo"),
	"s1_lian_yu": Callable(SkillEffects, "_ef_s1_lian_yu"),
	"s1_jiao_zuan": Callable(SkillEffects, "_ef_s1_jiao_zuan"),
	"s1_long_xi2": Callable(SkillEffects, "_ef_s1_long_xi2"),
	"s1_yan_zhua": Callable(SkillEffects, "_ef_s1_yan_zhua"),
	"s1_yan_ya": Callable(SkillEffects, "_ef_s1_yan_ya"),

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
		out += "，对 %s 造成 %.2f 伤害" % [t.name, r["hp_lost"] + r["absorbed"]]
	return out

static func _ef_stub_shield(user: BattleUnit, _ctx: Dictionary) -> String:
	# 示例：护盾函数用法 —— 给 30 护盾
	var before := user.shield
	user.add_shield(30)
	return "%s 获得护盾 %.2f → %d" % [user.name, 30, user.shield]

static func _ef_stub_heal(user: BattleUnit, _ctx: Dictionary) -> String:
	var amount := user.heal(25)
	return "%s 恢复 %d 生命（%.2f/%.2f）" % [user.name, amount, user.hp, user.max_hp]

static func _ef_stub_burst(user: BattleUnit, _ctx: Dictionary) -> String:
	# TODO: 大招效果
	return "%s 释放【模板爆发】（效果待填写）" % user.name

## ========== 元晶龙王（老方案）效果 ==========
## 元晶 = 计数资源池（BattleUnit.counter / grant_counter / consume_counter）；
## 自动增长由 counters{"元晶": start3, per_turn1, start_round2} 引擎维护（第 2 回合起 +1）。

## 被动（展示；增长由引擎处理）
static func _ef_yuan_jing_mark(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【元晶印记】生效：当前元晶 %d 枚（第 2 回合起每回合 +1）" % [user.name, user.counter("元晶")]

## 凝晶为刃：耗 1 元晶 → 单体 3 伤
static func _ef_ning_cheng_jian_ren(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("元晶") < 1:
		return "%s 元晶不足，【凝晶为刃】无法发动" % user.name
	user.consume_counter("元晶", 1)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【凝晶为刃】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
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
	return "%s 消耗 2 枚元晶：护盾 +3（现 %.2f），回复 %.2f 能量（%.2f/%.2f）" % [user.name, user.shield, got, user.energy, user.max_energy]

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
		out += "；%s 受 %.2f 真伤" % [tu.name, before - tu.hp]
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
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		hit += 1
	user.grant_counter("元晶", 1)
	out += "；收回 1 枚元晶（现 %.2f）" % user.counter("元晶")
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

## 一技能·替死：登记本回合分担/回合末吸血（伤害均摊需战斗层拦截伤害管线）
static func _ef_hun_qi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	user.begin_share_round(targets)
	return "%s 立下【替死】：本回合伤害由失神敌人均摊，回合末吸取失神敌当前生命的 30%%" % user.name

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
		var r: Dictionary = tu.take_damage(1)
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		if _sync_randf(user) < 0.6:
			_pollute(tu, 1)
			out += "，污染+1（共 %d）" % tu.counter("污染")
	user.add_energy(5)
	out += "；回复 5 能量（%.2f/%.2f）" % [user.energy, user.max_energy]
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
			var loss: float = tu.max_hp * 0.1 * float(layers)
			var r: Dictionary = tu.take_damage(loss)
			out += "；%s 失去 %d 点生命（%d 层×10%%）" % [tu.name, r["hp_lost"] + r["absorbed"], layers]
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
			out += "，%s 受 %.2f 真伤" % [tu.name, before - tu.hp]
		else:
			var r: Dictionary = tu.take_damage(dmg)
			out += "，%s 受 %.2f 伤害" % [tu.name, r["hp_lost"] + r["absorbed"]]
	return out

## 目标失去“最大生命 N%”（每层×pct 的百分比扣血用），返回实际损失量
static func lose_pct_max_hp(t: BattleUnit, pct_per: int, times: int) -> int:
	var loss: float = t.max_hp * 0.01 * float(pct_per) * float(times)
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
## 结算时机：流血=被攻击时受额外真伤（take_damage 内）；持续回合由计时器 bleed_end 承载（见 apply_bleed）。

static func status_cn(id: String) -> String:
	var m := {
		"bleed": "流血", "burn": "灼烧", "wound": "创伤", "freeze": "冻伤",
		"poison": "中毒", "burn2": "灼烧2",
		"heavy_wound": "重伤", "blind": "失明", "stun": "眩晕",
		"sword_field": "剑域", "corpse": "尸体", "star": "星矢", "full_burn": "完全燃烧", "fear": "恐惧",
	}
	return String(m.get(id, id))

## —— 状态“剩余回合”统一读法（2026-09-18：时长与层数解耦后，UI / 日志一律走这里）——
## 带计时的状态 → 计时器 id（与 battle_unit.add_timer 同一套）
## ⚠️ 不要把“层数”当剩余回合用（历史 bug：一个数字既当等级又当剩余回合，见 README 注意点 25）
static func status_timer_id(id: String) -> String:
	match id:
		"bleed":
			return "bleed_end"
		"burn":
			return "burn_end"
		"freeze":
			return "freeze_end"
	return ""

## 剩余回合（0 = 该状态不带计时器，如 创伤 / 重伤 / 失明）
static func status_rounds(u: BattleUnit, id: String) -> int:
	var tid := status_timer_id(id)
	if tid == "":
		return 0
	return u.timer_left(tid)

## 状态显示文本（**UI 共用，勿在三个界面各写一份**）
##   流血2级·余3回合 / 灼烧·余2回合 / 创伤2层 / 眩晕
static func status_label(id: String, lv: int, rounds: int) -> String:
	if id == "stun":
		return "眩晕"
	var cn := status_cn(id)
	if status_timer_id(id) == "":
		return "%s%d层" % [cn, lv]
	if id == "bleed":
		return "%s%d级·余%d回合" % [cn, lv, rounds] if rounds > 0 else "%s%d级" % [cn, lv]
	return "%s·余%d回合" % [cn, rounds] if rounds > 0 else cn

## 棋子头顶徽章上的数字：有等级用等级（流血2级→2），只有时长的用剩余回合（灼烧2回合→2）
static func status_badge_num(id: String, lv: int, rounds: int) -> int:
	if id == "bleed":
		return lv
	return rounds if (rounds > 0 and lv <= 1) else lv


## 状态徽章配色（渲染用）—— **全工程共用这一份**。
## 2026-09-30 收敛：原先 `unit_token.gd`（棋子头顶）与 `team_board.gd`（4V4 棋盘）各存一份
## 自己的 `_status_color`，两份只在**已废弃的** `"burn2"` 上有差异（战斗逻辑已不再产生该 id），
## 现统一到此处；两个界面改为转发。
static func status_color(sid: String) -> Color:
	match sid:
		"bleed":
			return Color(0.75, 0.10, 0.12)      # 流血 深红
		"burn", "burn2":
			return Color(0.92, 0.45, 0.08)      # 灼烧 橙
		"wound":
			return Color(0.60, 0.20, 0.55)      # 创伤 紫
		"heavy_wound":
			return Color(0.45, 0.12, 0.40)      # 重伤 深紫
		"freeze":
			return Color(0.30, 0.65, 0.90)      # 冻伤 冰蓝
		"blind":
			return Color(0.35, 0.35, 0.40)      # 失明 灰
		"stun":
			return Color(0.95, 0.80, 0.20)
		"full_burn":
			return Color(1.00, 0.35, 0.10)
		"fear":
			return Color(0.55, 0.30, 0.70)      # 恐惧 紫
		"sword_field":
			return Color(0.85, 0.75, 0.45)      # 剑域 金
		"poison", "poison_layer":
			return Color(0.30, 0.60, 0.20)      # 中毒 绿
		_:
			return Color(0.42, 0.44, 0.52)      # 其它 石灰


## 行动触发（施放技能/移动）：2026-09-08 起流血改为「被攻击时受额外真伤」（见 battle_unit.take_damage），不再行动自伤。
static func tick_action_statuses(_u: BattleUnit) -> String:
	return ""

## 回合开始触发：原灼烧逻辑改为回合末结算（新表备注：每回合末1真伤，持续2回合）
static func tick_start_of_turn_statuses(u: BattleUnit) -> String:
	return ""

## 回合末触发：流血2级每回合末 1 真伤（设计表 Z4）、烧伤每回合末 1 真伤；冻伤每回合末 1 真伤
## 注：流血 / 烧伤 / 冻伤的“持续回合”都由计时器承载（bleed_end / burn_end / freeze_end，到期回调收尾），
##     这里只做每回合结算，**不再用层数当剩余回合数**（历史 bug，见 README 注意点 25）
static func tick_end_of_turn_statuses(u: BattleUnit) -> String:
	var out := ""
	var b := u.status_stacks("bleed")
	if b > 0:
		var left := u.timer_left("bleed_end")
		if b >= 2:
			u.lose_hp(1)
			out += "%s 受流血2级 1 真伤（余 %d 回合）" % [u.name, left]
		else:
			out += "%s 流血1级持续中（余 %d 回合）" % [u.name, left]
	var fz := u.status_stacks("freeze")
	if fz > 0:
		var before := u.hp
		u.lose_hp(fz)
		out += "；%s 受冻伤 %d 真伤" % [u.name, before - u.hp]
	var bn := u.status_stacks("burn")
	if bn > 0:
		var bbefore := u.hp
		u.lose_hp(1)
		out += "；%s 被烧伤失去 %.2f 生命（余 %d 回合）" % [u.name, bbefore - u.hp, u.timer_left("burn_end")]
	var hw := u.status_stacks("heavy_wound")
	if hw > 0:
		u.set_status("heavy_wound", hw - 1)
		out += "；%s 重伤衰减 %d→%d 层" % [u.name, hw, hw - 1]
	if u.status_stacks("sword_field") > 0:
		var b2 := u.hp
		u.lose_hp(2)
		out += "；%s 受剑域 2 真伤" % u.name
	return out

## 施加烧伤/灼烧（设计表 Z4：速度 -10，每回合末 1 真伤，持续 2 回合；重复施加刷新时长）
##   2026-09-18 与流血同源改造：**时长交给计时器 burn_end**，status["burn"] 只表示“是否处于烧伤”，
##   不再用层数同时表示时长（历史 bug）。数值口径**保持不变**：原实现 `maxi(现值, 新值)` = 取更长的那个。
static func apply_burn(t: BattleUnit, rounds := 2) -> void:
	var left := t.timer_left("burn_end")
	var total := maxi(left, maxi(1, rounds))
	t.set_status("burn", 1)
	t.set_speed_mod_src("灼烧", -10)
	t.remove_timer("burn_end")
	t.add_timer("burn_end", total, Callable(func(): clear_burn(t)))

## 延长烧伤时长（炎拳 +1 / 不知火 +2 那类“烧伤 +N 层”，数值上等价于 +N 回合）
static func extend_burn(t: BattleUnit, n: int) -> void:
	apply_burn(t, t.timer_left("burn_end") + maxi(1, n))

## 清除烧伤（状态 + 计时器 + 速度 -10 一起清）—— 炼狱清零 / 药师清负面 共用
static func clear_burn(t: BattleUnit) -> void:
	t.set_status("burn", 0)
	t.remove_timer("burn_end")
	t.remove_speed_mod_src("灼烧")

## 施加重伤（heavy_wound）：受击额外 0.5×层真伤，回合末层-1
static func apply_heavy_wound(t: BattleUnit, stacks: int) -> void:
	t.add_status("heavy_wound", stacks)

## 流血持续时间（设计表 Z4）：1级 2 回合 / 2级 3 回合
static func bleed_rounds(level: int) -> int:
	return 3 if level >= 2 else 2

## 施加/刷新流血（设计表 Z4）—— 等级与持续时间**解耦**：
##   等级：1级 = 被攻击时 20% 额外真伤；2级 = 30% 额外真伤 + 每回合末 1 真伤。只升不降。
##   时长：用通用计时器 bleed_end 承载（与冻伤 freeze_end 同一套），到期清空流血；
##         再次施加把时长重置为该等级的基础时长（1级 2 回合 / 2级 3 回合）。
##   注：2026-09-18 前是「层数即剩余回合数」，导致 1 级只撑 1 回合、2 级只撑 2 回合，与设计表不符。
static func apply_bleed(t: BattleUnit, level: int) -> void:
	var lv := maxi(t.status_stacks("bleed"), clampi(level, 1, 2))
	t.set_status("bleed", lv)
	t.remove_timer("bleed_end")
	t.add_timer("bleed_end", bleed_rounds(lv), Callable(func(): t.set_status("bleed", 0)))

## 施加创伤印记（wound）：满 3 层清空并触发「流血1级」（设计表·孙广泽 技能1「狙击」M4）
## 注：重复触发只刷新时长、不自行升档 —— 升到 2 级只有「流炎飞弹」一条路（设计表 Y4）
static func add_wound(t: BattleUnit, n: int) -> String:
	t.add_status("wound", n)
	if t.status_stacks("wound") >= 3:
		t.set_status("wound", 0)
		apply_bleed(t, 1)
		return "，%s 创伤满 3 层 → 触发流血1级（持续 2 回合）" % t.name
	return "，%s 创伤 +%d（共 %d）" % [t.name, n, t.status_stacks("wound")]

## 对目标打一发“狙击”（1 伤 + 创伤）
static func _fire_snap(user: BattleUnit, t: BattleUnit, extra: String) -> String:
	var r: Dictionary = t.take_damage(1)
	var out := "%s%s：%s 受 %.2f 伤" % [user.name, extra, t.name, r["hp_lost"] + r["absorbed"]]
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
		return "%s 触发【以命相搏】：速度 +200（现 %.2f）、护甲清零、获得 2 点护盾" % [user.name, user.effective_speed()]
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
	return "%s 释放【架盾】：护盾 +2（现 %.2f），护甲 +%d（现 %.2f）" % [user.name, user.shield, ag, user.armor]

## 终极·流炎飞弹：至多2目标各3伤 + 附加灼烧1；若已有流血1级→升2级（两者并存，设计表 Y4）；护甲-1（一局一次由战斗层限制）
static func _ef_meteor_shot(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【流炎飞弹】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 2:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		apply_burn(tu, 2)
		out += "，附加灼烧"
		if tu.status_stacks("bleed") >= 1:
			apply_bleed(tu, 2)
			out += "，流血升级为2级（持续 3 回合）"
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
	if absf(user.dmg_mult - 1.0) > 0.001:
		dmg = maxf(1.0, float(dmg) * user.dmg_mult)
	return hit_group(targets, dmg, true_dmg)

## 按当前 effective_speed 降序（同速保持数组原顺序）。用于：每轮初始排列，
## 以及战斗中任意时刻的“动态重排”。注意：速度变化会立即影响后续行动顺序。
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


## —— 动态行动判定（Battle 采用）——
## 模型：不冻结“轮内顺序”。每次需要决定下一位行动者时，对所有本轮回合尚未行动
## （或按规则可行动）的单位实时取 effective_speed 最高者；任何减速/加速都立即
## 参与下一次比较。requeue_by_speed 用于在一次行动结算后重排剩余单位。

## 重新按当前速度降序排列（传入剩余待行动单位）
static func requeue_by_speed(remaining: Array) -> Array:
	return speed_order(remaining)

## 取当前“应行动”的单位（速度最高者），无则 null
static func next_actor(units: Array) -> BattleUnit:
	var lst := speed_order(units)
	return lst[0] as BattleUnit if lst.size() > 0 else null

## ========== 剑舞（王佳欣）效果 ==========
## 被动·剑意：成长由瞬击施放后 add_slot_damage(1,1,4) 维护（这里仅展示说明）
static func _ef_jian_yi(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【剑意】生效：瞬击伤害加成 %d（上限4）" % [user.name, int(user.slot_damage(1, 1)) - 1]

## 主动1·瞬击：单体基础1伤（吃剑意成长）+ 目标减速10；施放后剑意+1（封顶4）
static func _ef_shun_ji(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【瞬击】" % user.name
	if targets.is_empty():
		return out + "（无目标）"
	var tu := targets[0] as BattleUnit
	out += hit_group_slot(user, 1, [tu], 1)
	tu.add_speed_mod_src("剑舞:瞬击", -10)
	out += "；%s 速度 -10（现 %.2f）" % [tu.name, tu.effective_speed()]
	var gained := user.add_slot_damage(1, 1, 4)
	if gained > 0:
		out += "；剑意 +1（伤害加成 %d/4）" % (int(user.slot_damage(1, 1)) - 1)
	return out

## 主动2·断流：单体减速 50
static func _ef_duan_liu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【断流】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	tu.add_speed_mod_src("剑舞:断流", -50)
	return "%s 释放【断流】：%s 速度 -50（现 %.2f）" % [user.name, tu.name, tu.effective_speed()]

## 主动3·贯穿：目标「重伤」+5（用户 2026-09-18 确认：此为有意设计，不走流血）
static func _ef_guan_chuan(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【贯穿】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	tu.add_status("heavy_wound", 5)
	return "%s 释放【贯穿】：%s 重伤 +5（现 %d 层）" % [user.name, tu.name, tu.status_stacks("heavy_wound")]

## 终极·诛心：仅对生命≤30%目标生效，斩杀成功回8能量（战斗层应只允许此类目标被选中）
static func _ef_zhu_xin(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【诛心】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if not cut_if_under_pct(tu, 30):
			out += "；%s 生命高于30%%（%d%%），无法斩杀" % [tu.name, hp_pct(tu)]
			continue
		out += "；斩杀 %s" % tu.name
		if not tu.alive:
			var got := user.add_energy(8)
			out += "，回 %d 能量（%.2f/%.2f）" % [got, user.energy, user.max_energy]
	if targets.is_empty():
		out += "（无目标）"
	return out

## ========== 光雨（刘星泽）效果 ==========
## 星河 = 自身计数器（counters["星河"]，攒3层给大招）；星矢 = 目标 status "star"
## 眩晕/失明：flag + 持续回合 timer（执行由战斗层看 flag：眩晕跳过回合/失明按概率）

## 眩晕辅助（通用）：施加 flag + N 回合后自动清除
static func apply_stun(t: BattleUnit, rounds: int) -> String:
	var msg := t.try_control("stun")
	if msg != "":
		return msg
	t.add_flag("stun")
	t.remove_timer("stun_clear")
	t.add_timer("stun_clear", rounds, Callable(func(): t.clear_flag("stun")))
	return ""

## 光雨被动（展示；每回合回能/每2回合回血能由 def turn_start_effects 自动处理）
static func _ef_xing_he(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【星河】生效：星河 %d 层" % [user.name, user.counter("星河")]

## 施加星矢：满3 → 清空 + 眩晕1（目标）；返回追加文本
static func _add_star(user: BattleUnit, t: BattleUnit, n: int) -> String:
	var msg := ""
	t.add_status("star", n)
	if t.status_stacks("star") >= 3:
		t.set_status("star", 0)
		msg = apply_stun(t, 1)
		user.grant_counter("星河", 1)
		return "，%s 星矢满3层→眩晕1回合%s，%s 星河+1（共%d）" % [t.name, msg, user.name, user.counter("星河")]
	return "，%s 星矢+%d（共%d）" % [t.name, n, t.status_stacks("star")]

## 主动1·光如矢
static func _ef_guang_ru_shi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【光如矢】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(2)
	var out := "%s 释放【光如矢】：%s 受 %.2f 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	out += _add_star(user, tu, 1)
	return out

## 主动2·矢如雨（≤4目标各2伤+减速2）
static func _ef_shi_ru_yu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【矢如雨】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 4:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2)
		tu.add_speed_mod_src("光雨:矢如雨", -2)
		out += "；%s 受 %.2f 伤，速度-2（现%d）" % [tu.name, r["hp_lost"] + r["absorbed"], tu.effective_speed()]
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## 主动3·雨如星：3伤 + 星矢2 + 星河1
static func _ef_yu_ru_xing(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【雨如星】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(3)
	var out := "%s 释放【雨如星】：%s 受 %.2f 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	out += _add_star(user, tu, 2)
	user.grant_counter("星河", 1)
	out += "，%s 星河+1（共%d）" % [user.name, user.counter("星河")]
	return out

## 终极·星如河：消耗3星河 → 单体5伤 + 全体敌人星矢+1/失明1
static func _ef_xing_ru_he(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("星河") < 3:
		return "%s 星河不足 3 层，【星如河】无法发动" % user.name
	user.consume_counter("星河", 3)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【星如河】" % user.name
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if hit == 0:
			var r: Dictionary = tu.take_damage(5)
			out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		tu.add_status("star", 1)
		tu.add_status("blind", 1)
		hit += 1
	out += "；全体敌人星矢+1、失明1级（%d 目标）" % hit
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 药师（杨鑫翰）效果 ==========
## 负面状态定义（用于“清除负面”类技能）：bleed/burn/wound/star/blind/stun 及减速
static func _clear_random_debuff(t: BattleUnit) -> String:
	var pool := ["bleed", "burn", "wound", "blind"]
	for k in pool:
		if t.status_stacks(k) > 0:
			if k == "burn":
				clear_burn(t)                    # 连计时器 + 速度-10 一起清
			else:
				t.set_status(k, 0)
				var tid := status_timer_id(k)
				if tid != "":
					t.remove_timer(tid)          # 带时长的状态：计时器一起清，避免残留“余 N 回合”
			return "%s（清除）" % status_cn(k)
	if t.speed_mod_total() < 0:
		t.set_speed_mod_src("药师:负面", 0)
		return "减速（清除）"
	if t.has_flag("stun"):
		t.clear_flag("stun")
		return "眩晕（清除）"
	return "无负面可清"

static func _ef_gao_yu(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【膏腴】生效：能量无上限（当前 %d）" % [user.name, user.energy]

## 对 t 造成 amount 点伤害（护盾/护甲正常结算），返回实际损失量（掉血 + 破盾）。
## floor_amount：伤害下限。护盾/护甲把伤害削减到该值以下时，差额以真伤补足，
##   保证技能一定能打出描述中的伤害量（药师以自残换输出，被护甲全免等于白自残）。
## sure_hit：技能伤害不走闪避判定，避免“自残了却因闪避 0 伤害”。
static func _deal_with_floor(t: BattleUnit, amount: int, element: String, floor_amount: int = 1) -> int:
	if t == null or not t.alive:
		return 0
	var hp0 := t.hp
	var sh0 := t.shield
	t.take_damage(amount, {"element": element, "sure_hit": true})
	var dealt := (hp0 - t.hp) + (sh0 - t.shield)
	var short := floor_amount - dealt
	if short > 0 and t.alive:
		t.lose_hp(short)
		dealt += short
	return dealt

## 主动1·建木生发：耗自身血=目标当前血一半 → 目标受“已损生命一半（保底2）”伤害 → 自身回能=消耗量
## 修复记录：
##  - 原实现对满血目标算出 0 伤害（已损生命一半 = 0），且 3 点以内的伤害会被护甲（多数英雄 1~3）全部吃掉；
##  - 原自残量取目标血量一半，目标血越高越可能 ≥ 自身当前生命，导致技能对高血量目标直接无法发动；
##  - 原日志“%s 受 0 伤，回复 N 能量”被读成“敌人回复能量”，现明确写出主语是施法者自己。
static func _ef_jian_mu_sheng_fa(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【建木生发】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	if tu == null or not tu.alive:
		return "%s 释放【建木生发】（无目标）" % user.name
	if user.hp <= 1:
		return "%s 生命不足（%.2f/%.2f），【建木生发】无法发动（需保留至少 1 点生命）" % [user.name, user.hp, user.max_hp]
	# 消耗：目标当前生命的一半（向上取整，至少 1）；至多留自身 1 血，不会自杀
	var cost: float = maxf(1.0, tu.hp * 0.5)
	cost = minf(cost, user.hp - 1.0)
	user.lose_hp(cost)
	# 伤害：目标已损生命的一半，保底 2 点（满血目标也能打出伤害）
	var lost := tu.max_hp - tu.hp
	var dmg: float = maxf(2.0, maxf(0.0, float(lost)) * 0.5)
	var dealt := _deal_with_floor(tu, dmg, "木", 2)
	var got := user.add_energy(cost)
	return "%s 释放【建木生发】：自身消耗 %.2f 生命 → %s 受 %.2f 点伤害；%s 自身回复 %.2f 能量" % [
		user.name, cost, tu.name, dealt, user.name, got,
	]

## 主动2·寿瘟祸祖：耗一半当前生命 → 清一负面 → 附近敌人3伤（护甲全免时真伤兜底 1 点）
static func _ef_shou_wan_huo_zu(user: BattleUnit, ctx: Dictionary) -> String:
	if user.hp <= 1:
		return "%s 生命不足，【寿瘟祸祖】无法发动" % user.name
	var cost: float = maxf(1.0, user.hp * 0.5)
	cost = minf(cost, user.hp - 1.0)
	var clean := _clear_random_debuff(user)
	user.lose_hp(cost)
	var out := "%s 释放【寿瘟祸祖】：自身消耗 %.2f 生命，%s" % [user.name, cost, clean]
	var targets: Array = ctx.get("targets", [])
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		var dealt := _deal_with_floor(tu, 3, "木", 3)
		out += "；%s 受 %.2f 点伤害" % [tu.name, dealt]
		hit += 1
	if hit == 0:
		out += "（附近无敌人）"
	return out

## 主动3·莳者一心：回2血2能 + 1盾
static func _ef_shi_zhe_yi_xin(user: BattleUnit, _ctx: Dictionary) -> String:
	var h := user.heal(2)
	var e := user.add_energy(2)
	user.add_shield(1)
	return "%s 释放【莳者一心】：回复 %.2f 生命、%d 能量，+1 护盾（现 %.2f）" % [user.name, h, e, user.shield]

## 终极·药灵：生命降至1 → 盾=消耗量一半；锁血本回合；相邻敌人受当前盾量伤害
static func _ef_yao_ling(user: BattleUnit, ctx: Dictionary) -> String:
	var spend := user.hp - 1
	if spend <= 0:
		return "%s 生命过低，【药灵】无法发动" % user.name
	user.lose_hp(spend)
	var gained: float = spend * 0.5
	user.add_shield(gained)
	user.add_flag("lock_min_hp")
	user.remove_timer("yaoling_lock")
	user.add_timer("yaoling_lock", 1, Callable(func(): user.clear_flag("lock_min_hp")))
	var out := "%s 释放【药灵】：生命降至 1，获得 %d 护盾（现 %.2f），本回合锁血" % [user.name, gained, user.shield]
	var targets: Array = ctx.get("targets", [])
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		var dmg: float = maxf(1.0, user.shield)
		var before := tu.hp
		tu.lose_hp(dmg)
		out += "；%s 受 %.2f 点真伤" % [tu.name, before - tu.hp]
		hit += 1
	if hit == 0:
		out += "（相邻无敌人）"
	return out

## ========== 孤狼（叶麟）效果 ==========
static func _ef_duan_ti(user: BattleUnit, _ctx: Dictionary) -> String:
	if not user.has_flag("duanti_reg"):
		user.add_flag("duanti_reg")
		var u := user
		user.hit_events.append(Callable(func(atk, _el): u.add_mitigation_att(atk, 5, 20)))
	return "%s 的【锻体】生效：每次受击，对该攻击者的伤害免伤 +5%%（对同一人上限20%%）" % user.name

## 阴阳散手：进入防守阴态（15%减伤），受击3次转阳（2回合50%反伤）
static func _ef_yyss(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_flag("yin")
	user.set_mitigation("all", 15)
	user.set_counter("受击", 0)
	if not user.has_flag("yyss_reg"):
		user.add_flag("yyss_reg")
		var u := user
		user.hit_events.append(Callable(func(_atk, _el): _yyss_on_hit(u)))
	return "%s 释放【阴阳散手】：进入阴状态（减伤15%%），受击3次后转阳" % user.name

static func _yyss_on_hit(u: BattleUnit) -> void:
	if not u.has_flag("yin"):
		return
	u.grant_counter("受击", 1)
	if u.counter("受击") >= 3:
		u.clear_flag("yin")
		u.set_mitigation("all", 0)
		u.add_flag("yang")
		u.set_reflect(50)
		u.remove_timer("yang_end")
		u.add_timer("yang_end", 2, Callable(func():
			u.clear_flag("yang")
			u.set_reflect(0)))

## 伸缩拳：相邻4伤 / 两格2伤；远击嘲讽禁大2回合，近击获得对方属性免伤5%(上限30%)
static func _ef_ssq(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【伸缩拳】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var dist := int(ctx.get("dist", 1))
	var dmg := 4 if dist <= 1 else 2
	var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": user.element})
	var out := "%s 释放【伸缩拳】%s：%s 受 %.2f 伤" % [user.name, "（远击）" if dist >= 2 else "（近击）", tu.name, r["hp_lost"] + r["absorbed"]]
	if dist >= 2:
		tu.add_flag("taunted")
		out += tu.try_control("no_ult")
		tu.remove_timer("taunt_end")
		tu.add_timer("taunt_end", 2, Callable(func():
			tu.clear_flag("taunted")
			tu.clear_flag("no_ult")))
		out += "；%s 被嘲讽：大招封印2回合" % tu.name
	else:
		user.add_mitigation_att(tu, 5, 30)
		out += "；习得对 %s 的免伤+5%%（对 %s 共 %d%%）" % [tu.name, tu.name, user.mitigation_att(tu)]
	return out

## 普通拳：2伤 + 对被嘲讽目标1真伤；回2能
static func _ef_ptq(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【普通拳】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": user.element})
	var out := "%s 释放【普通拳】：%s 受 %.2f 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	if tu.has_flag("taunted"):
		var before := tu.hp
		tu.lose_hp(1)
		out += "，嘲讽目标额外 %d 真伤" % (before - tu.hp)
	user.add_energy(2)
	return out

## 血狱：首个目标已损15%伤害；范围内每目标 +5%免伤(总40)
static func _ef_xue_yu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【血狱】" % user.name
	if not targets.is_empty():
		var tu := targets[0] as BattleUnit
		var dmg: float = maxf(0.0, tu.max_hp - tu.hp) * 0.15
		var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": user.element})
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
	for t in targets:
		user.add_mitigation("all", 5, 40)
	out += "；免伤 +%d%%（总 %d%%）" % [targets.size() * 5, user.mitigation_of("all")]
	return out

## ========== rapper睡神（何至高）效果 ==========
static func _ef_kn(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【狂怒】生效：生命≤20%% 时伤害翻倍（当前倍率 %.1f）" % [user.name, user.dmg_mult]

## 掠夺：目标直到下个对方回合无法使用该技；自身下回合起第 slot 槽获得它（持续 2 个自身回合）
static func _ef_lve(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【掠夺】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var slot := int(ctx.get("slot", 1))
	for i in tu.actives.size():
		if i >= 3:
			break             # 第 4 槽（大招）不可掠夺
		var s := tu.actives[i]
		if s == null:
			continue
		if not tu.is_skill_lost(s.id):
			tu.lock_skill(s.id, 1)
			user.set_stolen_pending(s.id, slot)
			user.add_flag("has_stolen")
			return "%s 掠夺了 %s 的【%s】：对方直到下个对方回合无法使用，自己下两个自己回合可在第 %d 技能槽使用" % [user.name, tu.name, s.display_name, slot]
	return "%s 释放【掠夺】：%s 没有可掠夺的技能（大招除外）" % [user.name, tu.name]

## 魅惑：≤2 目标本回合无法造成伤害
static func _ef_meihuo(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【魅惑】" % user.name
	var n := 0
	for t in targets:
		if n >= 2:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		out += tu.try_control("no_damage")
		tu.remove_timer("meihuo_end")
		tu.add_timer("meihuo_end", 1, Callable(func(): tu.clear_flag("no_damage")))
		out += "；%s 本回合无法造成伤害" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 锁血：本回合 60% 免伤 + 回1血2能（不再是无敌）
static func _ef_suoxue(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_flag("免伤60")
	user.remove_timer("mianguan60_end")
	user.add_timer("mianguan60_end", 1, Callable(func(): user.clear_flag("免伤60")))
	var h := user.heal(1)
	var e := user.add_energy(2)
	return "%s 释放【锁血】：本回合获得 60%% 免伤，回复 %.2f 生命、%d 能量" % [user.name, h, e]

## 万里冰封：三格内敌人 冻伤1（减速20·回合末1真伤·2回合）+3伤
static func _ef_wanli(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【万里冰封】" % user.name
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": "冰"})
		out += "；%s 受 %.2f 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		tu.add_status("freeze", 1)
		tu.set_speed_mod_src("冰封", -20)
		tu.remove_timer("freeze_end")
		tu.add_timer("freeze_end", 2, Callable(func():
			tu.remove_speed_mod_src("冰封")
			tu.set_status("freeze", 0)))
		out += "，冻伤1级（速-20，2回合）"
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 仙尊（陈雨晴）效果 ==========
static func _ef_niepan(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【涅槃】生效：死亡复活回一半生命（每局1次）；回合末自动回4能量" % user.name

## 五行之力：随机一道五行法力，相邻≤3敌人各2伤
static func _ef_wuxing(user: BattleUnit, ctx: Dictionary) -> String:
	var elems := ["金", "木", "水", "火", "土"]
	var pick: String = elems[_sync_randi(user) % elems.size()]
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【五行之力】（%s）：" % [user.name, pick]
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": pick})
		out += "%s 受 %.2f 伤；" % [tu.name, r["hp_lost"] + r["absorbed"]]
		hit += 1
	if hit == 0:
		out += "无目标"
	return out

## 束缚之灵：相邻敌人本回合无法使用技能
static func _ef_shufu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【束缚之灵】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		out += tu.try_control("no_skill")
		tu.remove_timer("shufu_end")
		tu.add_timer("shufu_end", 1, Callable(func(): tu.clear_flag("no_skill")))
		out += "；%s 本回合沉默" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 转嫁傀儡：目标位移由战斗层执行；造成已损生命20%伤害
static func _ef_zhuanjia(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【转嫁傀儡】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var dmg: float = maxf(0.0, tu.max_hp - tu.hp) * 0.2
	var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": "土"})
	return "%s 释放【转嫁傀儡】：%s 被转移到仙尊相邻空格（战斗层执行），受 %.2f 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]

## 万剑归宗：两格内敌人每回合末2真伤，持续3回合
static func _ef_wanjian(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【万剑归宗】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.add_status("sword_field", 1)
		tu.remove_timer("sword_end")
		tu.add_timer("sword_end", 3, Callable(func(): tu.set_status("sword_field", 0)))
		out += "；%s 剑域3回合" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## ========== 灵虚数影（辛子祺）效果 ==========
static func _ef_shuyu(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【数域】生效：对非必中攻击 90%% 闪避" % user.name

static func _ef_tianji(user: BattleUnit, _ctx: Dictionary) -> String:
	user.set_dmg_mult(1.5)
	user.remove_timer("tianji_end")
	user.add_timer("tianji_end", 1, Callable(func(): user.set_dmg_mult(1.0)))
	return "%s 释放【天机】：下回合伤害 1.5 倍" % user.name

## 解析：单体3伤 + 破甲2（护甲-2，3回合后恢复）
static func _ef_jiexi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【解析】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": user.element, "sure_hit": true})
	tu.remove_armor(2)
	tu.remove_timer("pojia_restore")
	tu.add_timer("pojia_restore", 3, Callable(func(): tu.add_armor(2)))
	return "%s 释放【解析】：%s 受 %.2f 伤，破甲二级（甲-2，3回合）" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]

static func _ef_jidian(user: BattleUnit, _ctx: Dictionary) -> String:
	var e := user.add_energy(5)
	user.add_shield(1)
	return "%s 释放【极点】：回复 %.2f 能量、1 护盾（现 %.2f）" % [user.name, e, user.shield]

## 数海腾挪：天机+解析+本回合及下回合无法被选中
static func _ef_shuhai(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【数海腾挪】" % user.name
	user.set_dmg_mult(1.5)
	user.remove_timer("tianji_end")
	user.add_timer("tianji_end", 1, Callable(func(): user.set_dmg_mult(1.0)))
	var targets: Array = ctx.get("targets", [])
	if not targets.is_empty():
		var tu := targets[0] as BattleUnit
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": user.element, "sure_hit": true})
		tu.remove_armor(2)
		tu.remove_timer("pojia_restore")
		tu.add_timer("pojia_restore", 3, Callable(func(): tu.add_armor(2)))
		out += "；%s 受 %.2f 伤、破甲二级" % [tu.name, r["hp_lost"] + r["absorbed"]]
	user.add_flag("untargetable")
	user.remove_timer("untargetable_end")
	user.add_timer("untargetable_end", 2, Callable(func(): user.clear_flag("untargetable")))
	out += "；本回合及下回合无法被选中"
	return out

## ========== 辛克莱（新表）效果 ==========
static func _ef_hebi(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【何必如此】生效：理智 %d/%d；对机械属性目标伤害 +10%%" % [user.name, user.sanity, user.sanity_cap]

## 迫不得已的审判：突进2格穿过目标 → 2伤 + 烧伤（刷新）；理智-7
static func _ef_pbdy(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【迫不得已的审判】（突进2格）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": "火"})
		apply_burn(tu)
		out += "；%s 受 %.2f 伤、获烧伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(7)
	out += "；理智 -7（现 %.2f）" % user.sanity
	if n == 0:
		out += "（未穿过棋子）"
	return out

## 黑白不分的执行：突进撞墙/撞人 → 撞到棋子3伤 + 2层重伤；理智-10
static func _ef_heibai(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【黑白不分的执行】（快速突进）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": "火"})
		apply_heavy_wound(tu, 2)
		out += "；撞到 %s：受 %.2f 伤、重伤+2" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(10)
	out += "；理智 -10（现 %.2f）" % user.sanity
	if n == 0:
		out += "（未撞到棋子）"
	return out

## 自我毁灭的进化：传送后对周围敌人 2伤+3重伤；理智 -3×命中数
static func _ef_zishu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【自我毁灭的进化】（传送）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": "物理"})
		apply_heavy_wound(tu, 3)
		out += "；%s 受 %.2f 伤、重伤+3" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(3 * n)
	out += "；理智 -%d（现 %.2f）" % [3 * n, user.sanity]
	if n == 0:
		out += "（周围无敌人）"
	return out

## 因为我是被选中的：冲刺3格穿过 → 已损生命20%真伤；重伤≥4再获烧伤；理智-15
static func _ef_xuanzhong(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【因为我是被选中的】（冲刺3格）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var dmg: float = maxf(0.0, tu.max_hp - tu.hp) * 0.2
		var before := tu.hp
		tu.lose_hp(dmg)
		out += "；%s 失去 %.2f 真伤（已损生命20%%）" % [tu.name, before - tu.hp]
		# 2026-09-06 用户改：重伤阈值 4 → 3 层
		if tu.status_stacks("heavy_wound") >= 3:
			apply_burn(tu)
			out += "，重伤≥3层 → 获烧伤"
		n += 1
	user.lose_sanity(15)
	out += "；理智 -15（现 %.2f）" % user.sanity
	if n == 0:
		out += "（未穿过棋子）"
	return out

## ========== 流萤（火萤IV型）· 形态切换 ==========
static func _liuying_make(u: BattleUnit, sid: String) -> Skill:
	return u._make_skill(sid)

## 进入【完全燃烧】：速度+80，技能组切换为 底火/死星/超新星
static func _liuying_enter_full(u: BattleUnit) -> String:
	if u.has_status("full_burn"):
		return ""
	u.add_status("full_burn", 1)
	u.set_speed_mod_src("完全燃烧", 80)
	u.actives[0] = _liuying_make(u, "di_huo_zhan_ji")
	u.actives[1] = _liuying_make(u, "si_xing_guo_zai")
	u.actives[2] = null
	u.actives[3] = _liuying_make(u, "chao_xin_xing")
	u.set_counter("燃烧攻击", 0)
	return "；流萤 进入【完全燃烧】（速度+80，技能组切换）"

## 退出【完全燃烧】：恢复【次级燃烧】技能组
static func _liuying_exit_full(u: BattleUnit) -> String:
	if not u.has_status("full_burn"):
		return ""
	u.set_status("full_burn", 0)
	u.remove_speed_mod_src("完全燃烧")
	u.actives[0] = _liuying_make(u, "tian_huo")
	u.actives[1] = null
	u.actives[2] = null
	u.actives[3] = null
	return "；流萤 燃烧耗尽，退回【次级燃烧】"

## 完全燃烧下每释放一次技能计数，满 3 次退回
static func _liuying_tick_attack(u: BattleUnit) -> String:
	if not u.has_status("full_burn"):
		return ""
	var n := u.counter("燃烧攻击") + 1
	u.set_counter("燃烧攻击", n)
	if n >= 3:
		return _liuying_exit_full(u)
	return "；燃烧攻击 %d/3" % n

## 技能1·天火：烧 50% 血 → 1 伤 + 对盾额外 1；进入完全燃烧
static func _ef_tian_huo(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var tu := targets[0] as BattleUnit if targets.size() > 0 else null
	if tu == null:
		return "%s 释放【天火】（无目标）" % user.name
	var cost: float = minf(user.hp - 1.0, user.hp * 0.5)
	user.lose_hp(cost)
	var r: Dictionary = tu.take_damage(1, {"element": "火", "attacker": user})
	var out := "%s 释放【天火】：自身燃烧 %.2f 生命 → %s 受 %.2f 伤" % [user.name, cost, tu.name, float(r["hp_lost"]) + float(r["absorbed"])]
	if float(r["absorbed"]) > 0.0:
		tu.remove_shield(1)
		out += "，额外烧毁 1 点护盾"
	out += _liuying_enter_full(user)
	return out

## 完全形态技能1·底火斩击：1 真伤 + 对盾额外 2 + 回 3 能量
static func _ef_di_huo_zhan_ji(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var tu := targets[0] as BattleUnit if targets.size() > 0 else null
	if tu == null:
		return "%s 释放【底火斩击】（无目标）" % user.name
	var had_shield := tu.shield > 0
	tu.lose_hp(1)
	var out := "%s 释放【底火斩击】：%s 受 1.00 真伤" % [user.name, tu.name]
	if had_shield:
		tu.remove_shield(2)
		out += "，烧毁 2 点护盾"
	var e := user.add_energy(3)
	out += "；回复 %.2f 能量" % e
	out += _liuying_tick_attack(user)
	return out

## 完全形态技能2·死星过载：突进后对落点相邻至多 3 名单位 2 伤；有盾目标额外烧盾 2 + 真伤 2
static func _ef_si_xing_guo_zai(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【死星过载】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null or not tu.alive or tu == user:
			continue
		var r: Dictionary = tu.take_damage(2, {"element": "火", "attacker": user})
		out += "；%s 受 %.2f 伤" % [tu.name, float(r["hp_lost"]) + float(r["absorbed"])]
		if float(r["absorbed"]) > 0.0:
			tu.remove_shield(2)
			tu.lose_hp(2)
			out += "，烧盾 2 并追加 2.00 真伤"
		hit += 1
	if hit == 0:
		out += "（范围内无敌人）"
	out += _liuying_tick_attack(user)
	return out

## 大招·超新星过载：菱形两格内至多 3 目标 2 真伤（有盾烧盾 3 且真伤 4）；释放后强制退出完全燃烧
static func _ef_chao_xin_xing(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【超新星过载】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		if tu.shield > 0:
			tu.remove_shield(3)
			tu.lose_hp(4)
			out += "；%s 烧毁 3 护盾并受 4.00 真伤" % tu.name
		else:
			tu.lose_hp(2)
			out += "；%s 受 2.00 真伤" % tu.name
		hit += 1
	if hit == 0:
		out += "（范围内无目标）"
	out += _liuying_exit_full(user)
	return out

## ========== 李太白（诗仙）==========
## 技能1·将进酒：醉意 +2
static func _ef_jiang_jin_jiu(user: BattleUnit, _ctx: Dictionary) -> String:
	user.grant_counter("醉意", 2)
	return "%s 释放【将进酒，杯莫停】：醉意 +2（现 %d）" % [user.name, user.counter("醉意")]

## 技能2·笔墨挥洒：随机攻击（醉意）行，每行 1 伤；醉意 -2
static func _ef_bi_mo_hui_sa(user: BattleUnit, ctx: Dictionary) -> String:
	var n := user.counter("醉意")
	var foes: Array = _ctx_enemies(user, ctx)
	if foes.is_empty():
		return "%s 释放【笔墨挥洒】（无敌人）" % user.name
	var out := "%s 释放【笔墨挥洒】（%d 行小诗）" % [user.name, n]
	var hit := 0
	for _i in range(maxi(0, n)):
		var t: BattleUnit = foes[_sync_randi(user) % foes.size()]
		var r: Dictionary = t.take_damage(1, {"element": "金", "attacker": user})
		out += "；%s 受 %.2f 伤" % [t.name, float(r["hp_lost"]) + float(r["absorbed"])]
		hit += 1
	if n > 0:
		user.set_counter("醉意", maxi(0, n - 2))
		out += "；醉意 -2（现 %d）" % user.counter("醉意")
	if hit == 0:
		out += "（醉意不足，未成诗）"
	return out

## 技能3·肆意：消耗全部醉意，向目标冲锋并造成醉意数伤害
static func _ef_si_yi(user: BattleUnit, ctx: Dictionary) -> String:
	var dmg := user.counter("醉意")
	user.set_counter("醉意", 0)
	var targets: Array = ctx.get("targets", [])
	var tu := targets[0] as BattleUnit if targets.size() > 0 else null
	if tu == null or dmg <= 0:
		return "%s 释放【肆意】（无目标或醉意不足）" % user.name
	var r: Dictionary = tu.take_damage(dmg, {"element": "金", "attacker": user})
	return "%s 释放【肆意】：醉意清零，%s 受 %.2f 伤" % [user.name, tu.name, float(r["hp_lost"]) + float(r["absorbed"])]

## 大招·与君同醉：菱形 13 格内所有敌方 + 自己 → 酒醉（本回合跳过）
static func _ef_yu_jun_tong_zui(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【与君同醉】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		apply_stun(tu, 1)
		out += "；%s 陷入酒醉" % tu.name
		n += 1
	apply_stun(user, 1)
	user.set_counter("醉意", 0)
	out += "；%s 也醉了（醉意清零）" % user.name
	if n == 0:
		out += "（范围内无敌人）"
	return out

## ========== 虞美人（怀恨）==========
## 技能1·蔓延：移动由战斗层 human_cast 的 spread 分支处理（不消耗行动次数），效果函数只作兜底
static func _ef_man_yan(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 蔓延" % user.name

## 技能2·情愫：3×3 内友方（含自己）各回 1 血
static func _ef_qing_su(user: BattleUnit, ctx: Dictionary) -> String:
	var allies: Array = ctx.get("allies", [])
	if allies.is_empty():
		allies = [user]
	var out := "%s 释放【情愫】" % user.name
	var n := 0
	for a in allies:
		var au := a as BattleUnit
		if au == null or not au.alive:
			continue
		var h := au.heal(au.max_hp * 0.05)
		if h > 0:
			out += "；%s 回复 %.2f 生命" % [au.name, h]
			n += 1
	if n == 0:
		out += "（无友方）"
	return out

## 技能3·你不再爱我：被动监听（暂未实装，需战斗层跨单位受击事件）
static func _ef_ni_bu_zai_ai_wo(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的「你不再爱我」已就绪（被动监听待实装）" % user.name

## 大招·悔恨：相邻敌人 +3 层恐惧（上限 6）
static func _ef_hui_hen(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【悔恨】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		var cur := tu.status_stacks("fear")
		var add := mini(6 - cur, 3)
		if add > 0:
			tu.add_status("fear", add)
			out += "；%s 恐惧 +%d（现 %d）" % [tu.name, add, tu.status_stacks("fear")]
			n += 1
	if n == 0:
		out += "（相邻无敌人）"
	return out

## 从 ctx 取敌方列表（battle 注入）；单测无 battle 时回退 targets
static func _ctx_enemies(user: BattleUnit, ctx: Dictionary) -> Array:
	var b = ctx.get("battle", null)
	if b != null and b.has_method("alive_enemies_of"):
		return b.alive_enemies_of(user)
	var out: Array = []
	for t in ctx.get("targets", []):
		var tu := t as BattleUnit
		if tu != null and tu.alive:
			out.append(tu)
	return out

## ===================== 骑士线第一关 · 白灵殿 剧情兵种 =====================
## 被动只在 DATA 登记展示信息（战斗层不 trigger_passive），此处只实现主动技能。
## 数值口径：普伤 = 盾先吸 → 甲减免 → 扣血；真伤 = 直接扣血无视盾甲。

## 取本次有效目标（已由战斗层按射程与 any_target/ally_target 过滤）
static func _s1_targets(ctx: Dictionary) -> Array:
	var out: Array = []
	for t in ctx.get("targets", []):
		var tu := t as BattleUnit
		if tu != null and tu.alive:
			out.append(tu)
	return out

## 普伤（含施法者伤害倍率）：返回实际损失（扣血 + 盾吸收）
static func _s1_hit(user: BattleUnit, tu: BattleUnit, dmg: float) -> float:
	var d := dmg * user.dmg_mult
	var r: Dictionary = tu.take_damage(d, {"attacker": user, "element": user.element})
	return float(r["hp_lost"]) + float(r["absorbed"])

## 真伤（含施法者伤害倍率）：无视盾甲直接扣血
static func _s1_true(user: BattleUnit, tu: BattleUnit, dmg: float) -> float:
	var before := tu.hp
	tu.lose_hp(dmg * user.dmg_mult)
	return before - tu.hp

## 龙炎（龙）：普通攻击额外附带 10% 真伤
static func _s1_longyan(user: BattleUnit, tu: BattleUnit, dealt: float) -> String:
	if user.def_id != "story_dragon" or dealt <= 0:
		return ""
	var before := tu.hp
	tu.lose_hp(dealt * 0.1)
	return "，龙炎附伤 %.2f" % (before - tu.hp)

## 施加【烧伤】（设计表 Z4：速度 -10、每回合末 1 真伤、持续 2 回合；重复施加刷新时长）
##   n = 追加的回合数（炎拳 +1 / 不知火 +2）；减速与计时器都在 apply_burn/extend_burn 里统一处理
static func _s1_burn(t: BattleUnit, n: int) -> void:
	extend_burn(t, n)

## 施加【畏惧】层数（每层速度 -5，每回合末 -1 层，由战斗层 _end_round 衰减）
static func _s1_fear(t: BattleUnit, n: int) -> String:
	t.add_status("fear", n)
	var layers := t.status_stacks("fear")
	t.set_speed_mod_src("畏惧", -5 * layers)
	return "，畏惧 +%d（现 %d 层，速度 -%d）" % [n, layers, 5 * layers]

## 定时器回调：清除指定速度修正来源（炎牙减速等）
static func _s1_clear_speed_src(u: BattleUnit, src: String) -> void:
	if u != null:
		u.remove_speed_mod_src(src)

## 定时器回调：清除全局免伤
static func _s1_clear_mitig(u: BattleUnit) -> void:
	if u != null:
		u.set_mitigation("all", 0)

## 定时器回调：清除状态标记
static func _s1_clear_flag(u: BattleUnit, f: String) -> void:
	if u != null:
		u.clear_flag(f)

## 定时器回调：恢复伤害倍率
static func _s1_reset_dmg_mult(u: BattleUnit) -> void:
	if u != null:
		u.set_dmg_mult(1.0)

## —— 大长老 ——
## 戒与律：目标（除宵外）一回合内无法使用技能二
static func _ef_s1_jie_yu_lv(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		return "%s 释放【戒与律】（无目标）" % user.name
	var tu: BattleUnit = ts[0]
	if tu.def_id == "story_xiao":
		return "%s 释放【戒与律】：宵 不受戒律约束（无效）" % user.name
	var sk2 := tu.get_skill(2)
	if sk2 == null:
		return "%s 释放【戒与律】：%s 没有技能二（无效）" % [user.name, tu.name]
	tu.lock_skill(sk2.id, 1)
	return "%s 释放【戒与律】：%s 一回合内无法使用【%s】" % [user.name, tu.name, sk2.display_name]

## 职与责：己方全体 30% 免伤 2 回合 + 最多 3 个敌人各 1 伤
static func _ef_s1_zhi_yu_ze(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【职与责】：己方全体获得 30%% 免伤（2 回合）" % user.name
	var b = ctx.get("battle", null)
	if b != null and b.has_method("units_of_team"):
		for a in b.units_of_team(user.team):
			var au := a as BattleUnit
			if au == null or not au.alive:
				continue
			au.add_mitigation("all", 30, 90)
			au.remove_timer("职与责")
			au.add_timer("职与责", 2, Callable(SkillEffects, "_s1_clear_mitig").bind(au))
	else:
		user.add_mitigation("all", 30, 90)
		user.add_timer("职与责", 2, Callable(SkillEffects, "_s1_clear_mitig").bind(user))
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 3:
			break
		var tu: BattleUnit = t
		var dealt := _s1_hit(user, tu, 1)
		out += "；%s 受 %.2f 伤" % [tu.name, dealt]
		n += 1
	if n == 0:
		out += "（射程内无敌人）"
	return out

## 强权：最多 2 个目标 2 真伤 + 2 层畏惧
static func _ef_s1_qiang_quan(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【强权】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_true(user, tu, 2)
		out += "；%s 受 %.2f 真伤" % [tu.name, dealt]
		out += _s1_fear(tu, 2)
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 灵震：最多 2 个目标 4 伤 + 清空护甲 + 眩晕 1 回合（2026-09-12：2 回合 → 1 回合）
static func _ef_s1_ling_zhen(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【灵震】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_hit(user, tu, 4)
		out += "；%s 受 %.2f 伤" % [tu.name, dealt]
		out += _s1_longyan(user, tu, dealt)
		if tu.armor > 0:
			tu.set_armor(0)
			out += "，护甲清空"
		tu.add_flag("stun")
		tu.remove_timer("灵震眩晕")
		tu.add_timer("灵震眩晕", 1, Callable(SkillEffects, "_s1_clear_flag").bind(tu, "stun"))
		out += "，眩晕 1 回合"
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## —— 战士 ——
## 坚固：自身 20% 免伤 2 回合（2026-09-12：3 回合 → 2 回合）
static func _ef_s1_jian_gu(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_mitigation("all", 20, 90)
	user.remove_timer("坚固")
	user.add_timer("坚固", 2, Callable(SkillEffects, "_s1_clear_mitig").bind(user))
	return "%s 释放【坚固】：获得 20%% 免伤（2 回合）" % user.name

## 决心：1 伤
static func _ef_s1_jue_xin(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		return "%s 释放【决心】（无目标）" % user.name
	var tu: BattleUnit = ts[0]
	var dealt := _s1_hit(user, tu, 1)
	return "%s 释放【决心】：%s 受 %.2f 伤" % [user.name, tu.name, dealt]

## 引雷：最多 2 个目标 1.5 真伤（2026-09-12：3 目标 → 2 目标）
static func _ef_s1_yin_lei(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【引雷】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_true(user, tu, 1.5)
		out += "；%s 受 %.2f 真伤" % [tu.name, dealt]
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## —— 法师 ——
## 关怀：最多 2 个己方单位各回 1 血（无友方可选时对自己生效）
static func _ef_s1_guan_huai(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		var h := user.heal(1)
		return "%s 释放【关怀】：治疗自身 %.2f 生命" % [user.name, h]
	var out := "%s 释放【关怀】" % user.name
	var n := 0
	for t in ts:
		if n >= 2:
			break
		var tu: BattleUnit = t
		var h2 := tu.heal(1)
		out += "；%s 回复 %.2f 生命" % [tu.name, h2]
		n += 1
	return out

## 灵动：最多 2 个目标 1 真伤
static func _ef_s1_ling_dong(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【灵动】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_true(user, tu, 1)
		out += "；%s 受 %.2f 真伤" % [tu.name, dealt]
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 赤诚：最多 2 个目标 2 真伤（2026-09-12：3 目标 → 2 目标）
static func _ef_s1_chi_cheng(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【赤诚】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_true(user, tu, 2)
		out += "；%s 受 %.2f 真伤" % [tu.name, dealt]
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## —— 宵 ——
## 可燃点：自身伤害 +30% 两回合 + 回 10 能量（2026-09-12：+20%/回5 → +30%/回10，耗能 1 → 4）
static func _ef_s1_ke_ran_dian(user: BattleUnit, _ctx: Dictionary) -> String:
	user.set_dmg_mult(1.3)
	user.remove_timer("可燃点")
	user.add_timer("可燃点", 2, Callable(SkillEffects, "_s1_reset_dmg_mult").bind(user))
	var got := user.add_energy(10)
	return "%s 释放【可燃点】：伤害 +30%%（2 回合），回复 %.0f 能量（现 %.0f）" % [user.name, got, user.energy]

## 炎拳：5 伤 + 1 层烧伤（2026-09-12：3 伤 → 5 伤）
static func _ef_s1_yan_quan(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		return "%s 释放【炎拳】（无目标）" % user.name
	var tu: BattleUnit = ts[0]
	var dealt := _s1_hit(user, tu, 5)
	_s1_burn(tu, 1)
	return "%s 释放【炎拳】：%s 受 %.2f 伤，烧伤 +1（余 %d 回合）" % [user.name, tu.name, dealt, status_rounds(tu, "burn")]

## 不知火：最多 2 个目标 1 伤 + 2 层烧伤
static func _ef_s1_bu_zhi_huo(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【不知火】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_hit(user, tu, 1)
		_s1_burn(tu, 2)
		out += "；%s 受 %.2f 伤，烧伤 +2（余 %d 回合）" % [tu.name, dealt, status_rounds(tu, "burn")]
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 炼狱：全体单位 1 真伤 + 烧伤清零，每 1 层烧伤额外 0.2 真伤（敌我不分）
## 2026-09-12 加强：追加「全体单位各受 1 点真伤」（原版只有按烧伤层数的 0.2 真伤）
static func _ef_s1_lian_yu(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【炼狱】：全体单位受 1 真伤，烧伤清零" % user.name
	var b = ctx.get("battle", null)
	var all: Array = []
	if b != null and "units" in b:
		all = b.units as Array
	for x in all:
		var u := x as BattleUnit
		if u == null or not u.alive:
			continue
		# ① 固定 1 点真伤（对全体，含友方与自身）
		var b0 := u.hp
		u.lose_hp(1)
		var fixed_lost := b0 - u.hp
		# ② 烧伤清零 + 按剩余回合数 0.2 真伤（口径与原「层数」一致：层数≡剩余回合，数值不变）
		var n := status_rounds(u, "burn")
		var burn_lost := 0.0
		if n > 0:
			var b1 := u.hp
			u.lose_hp(0.2 * float(n))
			burn_lost = b1 - u.hp
			clear_burn(u)
		if n > 0:
			out += "；%s 受 %.2f 真伤（烧伤 %d 回合清零）" % [u.name, fixed_lost + burn_lost, n]
		else:
			out += "；%s 受 %.2f 真伤" % [u.name, fixed_lost]
	return out

## —— 龙 ——
## 角钻：最多 2 个目标 2 伤（龙炎附伤）—— 2026-09-12：射程 2→4，1 伤→2 伤
static func _ef_s1_jiao_zuan(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【角钻】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_hit(user, tu, 2)
		out += "；%s 受 %.2f 伤" % [tu.name, dealt]
		out += _s1_longyan(user, tu, dealt)
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 龙息：最多 2 个目标 2 真伤 + 1 层烧伤（2026-09-12：1 真伤 → 2 真伤）
static func _ef_s1_long_xi2(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【龙息】" % user.name
	var n := 0
	for t in _s1_targets(ctx):
		if n >= 2:
			break
		var tu: BattleUnit = t
		var dealt := _s1_true(user, tu, 2)
		_s1_burn(tu, 1)
		out += "；%s 受 %.2f 真伤，烧伤 +1（余 %d 回合）" % [tu.name, dealt, status_rounds(tu, "burn")]
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## —— 熊 ——
## 炎爪：2 伤 + 1 层烧伤 —— 2026-09-12：射程 1→2，1 伤→2 伤
static func _ef_s1_yan_zhua(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		return "%s 释放【炎爪】（无目标）" % user.name
	var tu: BattleUnit = ts[0]
	var dealt := _s1_hit(user, tu, 2)
	_s1_burn(tu, 1)
	return "%s 释放【炎爪】：%s 受 %.2f 伤，烧伤 +1（余 %d 回合）" % [user.name, tu.name, dealt, status_rounds(tu, "burn")]

## 炎牙：3 伤 + 1 层烧伤 + 速度 -10（2026-09-12：射程 1→2，2 伤→3 伤，新增减速）
## 减速持续 2 回合（与烧伤同源）：用独立来源名「炎牙」，避免与灼烧的 -10 互相覆盖
static func _ef_s1_yan_ya(user: BattleUnit, ctx: Dictionary) -> String:
	var ts := _s1_targets(ctx)
	if ts.is_empty():
		return "%s 释放【炎牙】（无目标）" % user.name
	var tu: BattleUnit = ts[0]
	var dealt := _s1_hit(user, tu, 3)
	_s1_burn(tu, 1)
	tu.set_speed_mod_src("炎牙", -10)
	tu.remove_timer("炎牙减速")
	tu.add_timer("炎牙减速", 2, Callable(SkillEffects, "_s1_clear_speed_src").bind(tu, "炎牙"))
	return "%s 释放【炎牙】：%s 受 %.2f 伤，烧伤 +1（余 %d 回合），速度 -10（2 回合，现 %d）" % [
		user.name, tu.name, dealt, status_rounds(tu, "burn"), tu.effective_speed()]
