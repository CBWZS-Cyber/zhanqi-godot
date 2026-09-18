extends SceneTree
## 战棋 · 战斗层回归测试（combat regression）
## 用法：Godot --headless --path 工程 -s res://tests/combat_regression.gd
## 覆盖：伤害管线/状态印记/资源层/英雄关键机制。全部通过 exit 0，有失败 exit 1。

var _passes := 0
var _fails := 0
var _quiet := false

func ck(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		if not _quiet:
			print("  ✓ ", name)
	else:
		_fails += 1
		printerr("  ✗ FAIL: ", name)

var BU
var HD
var SE

func u(idd: String) -> BattleUnit:
	return BU.new(HD.ALL[idd].duplicate(true))

func foe(nm: String, hp := 10, sp := 60, elem := "火") -> BattleUnit:
	var x: BattleUnit = BU.new({"name": nm, "hp": hp, "energy": 20, "armor": 0, "speed": sp, "element": elem, "skills": {}})
	x.team = 1
	return x

func _initialize() -> void:
	BU = load("res://scripts/combat/battle_unit.gd")
	HD = load("res://scripts/combat/hero_defs.gd")
	SE = load("res://scripts/combat/skill_effects.gd")
	var t0 := Time.get_ticks_msec()
	_test_damage_pipeline()
	_test_status_system()
	_test_counters_layers()
	_test_speed_damage_timers()
	_test_revive_aura_misc()
	_test_heroes()
	var dt := Time.get_ticks_msec() - t0
	print("== 回归结果: PASS %d / FAIL %d（%d ms）==" % [_passes, _fails, dt])
	quit(1 if _fails > 0 else 0)

## ---------- A. 伤害管线 ----------
func _test_damage_pipeline() -> void:
	print("[A] 伤害管线")
	var t := foe("靶", 20)
	t.armor = 2
	t.add_shield(5)
	var r: Dictionary = t.take_damage(10)
	ck(r["absorbed"] == 5 and r["hp_lost"] == 3, "盾5先吸收→甲2减免→掉3（10伤）")
	ck(t.hp == 17, "hp 17")
	var d2: Dictionary = t.take_damage(4)   # 甲2
	ck(d2["hp_lost"] == 2 and t.hp == 15, "无盾后甲2减免")
	# 真伤
	var h0 := t.hp
	t.lose_hp(6)
	ck(t.hp == h0 - 6, "真伤无视盾/甲")
	# 锁血
	var y := u("yao_shi")
	y.hp = 3
	y.add_flag("lock_min_hp")
	var d3: Dictionary = y.take_damage(50)
	ck(y.hp == 1 and y.alive, "锁血：1点保底")
	y.clear_flag("lock_min_hp")
	# 无敌
	y.hp = 5
	y.add_flag("invuln")
	var d4: Dictionary = y.take_damage(99)
	ck(d4["invuln"] and y.hp == 5, "无敌吸收全部")
	y.clear_flag("invuln")
	# 闪避（必中可穿透）
	var lx := u("ling_xu")
	ck(lx.evasion_pct == 60, "灵虚闪避60%")
	var d5: Dictionary = lx.take_damage(1, {"sure_hit": true})
	ck(not d5["missed"], "必中无视闪避")
	# 免伤 all + per-attacker
	var g := u("gu_lang")
	g.set_armor(0)
	g.add_mitigation("all", 50)
	g.trigger_passive({})   # 注册锻体（受击对该攻击者+5%免伤）
	var a1 := foe("打手A", 20, 50)
	var b1 := foe("打手B", 20, 50)
	g.hp = 20
	var g0 := g.hp
	g.take_damage(10, {"attacker": a1, "element": "火"})
	ck(g.hp == g0 - 5, "all免伤50%生效（10→5）")
	g0 = g.hp
	g.take_damage(10, {"attacker": a1, "element": "火"})
	# 浮点化后不再进位：第 2 击时锻体只累积了 1 层(5%)，合计免伤 55% → 10 伤实扣 4.5
	# （旧版 ceili 把 5.5 进位成 6，看起来像"共 60% 扣 4"，实际是取整造成的假象）
	ck(g.mitigation_att(a1) == 10 and is_equal_approx(g.hp, g0 - 4.5), "锻体1层(5%)与all共55%（10→4.5）")
	ck(g.mitigation_att(b1) == 0, "对B独立为0")
	# 反伤
	var re := u("gu_lang")
	re.set_armor(0)
	re.set_reflect(50)
	re.hp = 20
	var atk := foe("攻击者", 20, 50)
	var atk0 := atk.hp
	re.take_damage(10, {"attacker": atk, "element": "火"})  # 无甲无盾 → 掉10 → 反弹5
	ck(atk.hp == atk0 - 5, "反伤50%弹回攻击者5")
	# 重伤：受击额外 0.5×层
	var hw := foe("重伤者", 20, 50)
	hw.add_status("heavy_wound", 4)
	var hw0 := hw.hp
	hw.take_damage(4, {"attacker": atk, "element": "物理"})
	ck(hw.hp == hw0 - 4 - 2, "重伤4层受击额外2真伤")

## ---------- B. 状态/印记 ----------
func _test_status_system() -> void:
	print("[B] 状态与印记")
	var t := foe("敌", 20)
	# 流血（设计表 Z4）：被攻击时按攻击伤害 20%（1级）/30%（2级）受额外真伤（不再行动自伤）
	var atk := foe("攻击者", 20)
	atk.team = 1
	SE.apply_bleed(t, 2)   # 2级 = 30%
	var t0 := t.hp
	t.take_damage(10, {"attacker": atk})
	ck(is_equal_approx(t.hp, t0 - 10 - 3), "流血2级：受击 10 伤 + 30% 额外真伤 3")
	t.take_damage(0, {"attacker": atk})
	ck(t.status_stacks("bleed") == 2, "0 伤攻击不触发流血")
	var t1 := foe("敌1级", 20)
	SE.apply_bleed(t1, 1)
	var a2 := foe("攻2", 20); a2.team = 1
	t1.take_damage(10, {"attacker": a2})
	ck(is_equal_approx(t1.hp, 8.0), "流血1级：受击 10 伤 + 20% 额外真伤 2（20→8）")
	# 流血真伤穿透护盾（龙王盾场景）
	var t2 := foe("盾靶", 20)
	SE.apply_bleed(t2, 2)
	t2.add_shield(5)
	var t20 := t2.hp
	t2.take_damage(10, {"attacker": a2})
	# 盾 5 全吸 → 余 5 伤打本体扣 5 → hp 15；流血 30%×10=3 真伤直扣本体 → hp 12
	ck(is_equal_approx(t2.hp, t20 - 5.0 - 3.0) and t2.shield == 0.0, "流血2级真伤穿透（盾吸5+本体扣5+流血真伤3直扣）")
	ck(SE.tick_action_statuses(t) == "", "行动不再触发流血自伤")
	# 持续时间（设计表 Z4）：1级 2 回合、2级 3 回合；等级不再随回合数衰减
	var td1 := foe("流血1级靶", 20)
	SE.apply_bleed(td1, 1)
	ck(td1.timer_left("bleed_end") == 2, "流血1级：时长 2 回合")
	var d1 := td1.hp
	td1.end_turn()
	ck(td1.status_stacks("bleed") == 1 and is_equal_approx(td1.hp, d1) and td1.timer_left("bleed_end") == 1, "流血1级：第1回合末仍在、无真伤")
	td1.end_turn()
	ck(td1.status_stacks("bleed") == 0, "流血1级：第2回合末到期清除")
	var td2 := foe("流血2级靶", 20)
	SE.apply_bleed(td2, 2)
	ck(td2.timer_left("bleed_end") == 3, "流血2级：时长 3 回合")
	var d0 := td2.hp
	td2.end_turn()
	ck(is_equal_approx(td2.hp, d0 - 1.0) and td2.status_stacks("bleed") == 2 and td2.timer_left("bleed_end") == 2, "流血2级：回合末 1 真伤、等级不变（余2回合）")
	td2.end_turn()
	td2.end_turn()
	ck(is_equal_approx(td2.hp, d0 - 3.0) and td2.status_stacks("bleed") == 0, "流血2级：3 回合共 3 真伤后清除")
	# 创伤3 → 流血1级（设计表 M4）
	var tu := foe("敌2", 20)
	tu.add_status("wound", 2)
	var txt: String = SE.add_wound(tu, 1)
	ck("流血1级" in txt, "狙击触发日志文案")
	ck(tu.status_stacks("bleed") == 1 and tu.status_stacks("wound") == 0 and tu.timer_left("bleed_end") == 2, "创伤满3→流血1级、持续2回合（设计表 M4）")
	# 重复触发只刷新时长、不自行升档（升 2 级只有「流炎飞弹」一条路，设计表 Y4）
	tu.add_status("wound", 2)
	txt = SE.add_wound(tu, 1)
	ck(tu.status_stacks("bleed") == 1 and tu.timer_left("bleed_end") == 2, "再次创伤满3：流血仍1级（不叠加升档）")
	# 流炎飞弹：附加灼烧 + 已有流血1级→升2级（两者并存，设计表 Y4）
	var tms := foe("飞弹靶", 20)
	SE.apply_bleed(tms, 1)
	var zl := foe("追猎", 8)
	SE._ef_meteor_shot(zl, {"targets": [tms]})
	ck(tms.status_stacks("bleed") == 2, "流炎飞弹：流血1级→升2级")
	ck(tms.timer_left("bleed_end") == 3, "流炎飞弹：升2级后时长刷新为3回合")
	ck(tms.status_stacks("burn") == 1 and tms.timer_left("burn_end") == 2, "流炎飞弹：同时附加灼烧（2 回合）")
	# 烧伤（设计表 Z4：速度-10、每回合末 1 真伤、持续 2 回合）—— 2026-09-18 时长与层数解耦
	var tb := foe("敌3", 20)
	SE.apply_burn(tb)
	ck(tb.status_stacks("burn") == 1 and tb.timer_left("burn_end") == 2 and tb.speed_mod_total() == -10, "烧伤：标记+2回合+减速10")
	var h0 := tb.hp
	tb.end_turn()
	ck(tb.hp == h0 - 1 and tb.timer_left("burn_end") == 1, "烧伤回合末1真伤、余1回合")
	tb.end_turn()
	ck(tb.status_stacks("burn") == 0 and tb.speed_mod_total() == 0, "烧伤到期：状态与减速一起清")
	# 烧伤叠加=延长时长（炎拳+1 / 不知火+2 的口径）；重复施加取更长者、不缩短
	var tb2 := foe("敌3b", 20)
	SE.extend_burn(tb2, 1)
	ck(tb2.timer_left("burn_end") == 1, "烧伤 +1 → 1 回合")
	SE.extend_burn(tb2, 2)
	ck(tb2.timer_left("burn_end") == 3, "烧伤再 +2 → 3 回合（累加）")
	SE.apply_burn(tb2)
	ck(tb2.timer_left("burn_end") == 3, "重复施加烧伤不缩短（取更长者）")
	var hb2 := tb2.hp
	SE.clear_burn(tb2)
	ck(tb2.status_stacks("burn") == 0 and tb2.speed_mod_total() == 0 and tb2.timer_left("burn_end") == 0 and tb2.hp == hb2, "clear_burn：状态/计时器/减速一起清")
	# 状态文本（UI 共用同一函数）：流血带等级+剩余回合，灼烧只有剩余回合，创伤仍是层数
	ck(SE.status_label("bleed", 2, 3) == "流血2级·余3回合" and SE.status_label("burn", 1, 2) == "灼烧·余2回合", "status_label：流血/灼烧文本")
	ck(SE.status_label("wound", 2, 0) == "创伤2层" and SE.status_badge_num("burn", 1, 2) == 2 and SE.status_badge_num("bleed", 2, 3) == 2, "status_label 层数系 + 徽章数字")
	# 冰冻
	var tf := foe("敌4", 20)
	tf.add_status("freeze", 1)
	tf.set_speed_mod_src("冰封", -20)
	var hf := tf.hp
	var tf1: String = tf.end_turn()
	ck(tf.hp == hf - 1, "冻伤回合末1真伤")
	# 星矢满3眩晕
	var gy := u("guang_yu")
	var es := foe("眩敌", 10)
	gy.use_active(1, {"targets": [es]})
	gy.use_active(1, {"targets": [es]})
	gy.use_active(1, {"targets": [es]})
	ck(es.has_flag("stun") and gy.counter("星河") == 1, "星矢3→眩晕1回合+星河1")
	# 沉默/魅惑/封大 门禁
	var q := foe("门禁敌", 10)
	q.add_flag("no_skill")
	q.actives = u("guang_yu").actives
	var qout: String = q.use_active(1, {"targets": []})
	ck("沉默" in qout, "no_skill 门禁拦截")
	q.clear_flag("no_skill")
	q.add_flag("no_ult")
	var q2: String = q.use_active(4, {"targets": []})
	ck("封印" in q2, "no_ult 门禁拦截")

## ---------- C. 计数/层规则 ----------
func _test_counters_layers() -> void:
	print("[C] 资源池与层数规则")
	var dg := u("crystal_dragon")
	ck(dg.counter("元晶") == 3, "龙王开局3晶")
	var s1: String = dg.on_turn_start()
	ck(dg.counter("元晶") == 3, "第1回合不涨晶（start_round=2）")
	dg.on_turn_start()
	ck(dg.counter("元晶") == 4, "第2回合起+1（4）")
	# 污染层
	var xs := u("xie_shen")
	var e := foe("污敌", 20)
	xs.trigger_passive({"targets": [e]})
	xs.trigger_passive({"targets": [e]})
	xs.trigger_passive({"targets": [e]})
	ck(e.counter("污染") == 3 and e.has_flag("失神"), "污染3层→失神")
	ck(e.effective_speed() == 60 - 45, "污染每层-15速度")
	# 能量无上限
	var ys := u("yao_shi")
	ck(ys.max_energy < 0 and ys.energy == 0, "药师无能量（0，无上限）")
	ys.add_energy(500)
	ck(ys.energy == 500, "无上限可存500")

## ---------- D. 速度/伤害加成/计时 ----------
func _test_speed_damage_timers() -> void:
	print("[D] 速度·伤害·计时")
	var a := u("guang_yu")
	var b := foe("减速者", 20, 100)
	b.set_speed_mod_src("污染", -15)
	b.set_speed_mod_src("断流", -50)
	ck(b.effective_speed() == 35 and b.speed_mod_total() == -65, "速度多源求和")
	b.set_speed_buff(200)
	ck(b.effective_speed() == 235, "buff叠加")
	# 伤害槽加成（剑意）
	var jw := u("jianwu")
	for i in range(6):
		jw.add_slot_damage(1, 1, 4)
	ck(jw.slot_damage(1, 1) == 5 and jw.slot_damage(2, 1) == 1, "槽1伤害加成上限4")
	# timer
	var tim := foe("计时", 10, 40)
	tim.add_timer("buff", 2, Callable(func(): return "到期"))
	tim.end_turn()
	var tl: String = tim.end_turn()
	ck("到期" in tl and tim.timer_left("buff") == 0, "持续计时器到期回调")
	# 动态行动顺序
	var fast := foe("快", 10, 200)
	var slow := foe("慢", 10, 40)
	var ord: Array = SE.speed_order([slow, fast])
	ck(ord[0] == fast and ord[1] == slow, "speed_order 降序")
	slow.set_speed_mod_src("加速", 500)
	var nx: BattleUnit = SE.next_actor([slow, fast])
	ck(nx == slow, "速度变化实时改变下一位")

## ---------- E. 复活/剑域等 ----------
func _test_revive_aura_misc() -> void:
	print("[E] 复活·剑域")
	var xz := u("xian_zun")
	xz.hp = 1
	xz.lose_hp(2)
	ck(not xz.alive and xz.has_flag("corpse"), "仙尊死亡进入尸体态")
	xz.end_turn()
	ck(xz.alive and xz.hp == 3, "仙尊复活回50%血（3/6）")
	# 万剑剑域
	var e := foe("域敌", 10)
	xz.add_energy(30)
	xz.energy = 18
	var wj: String = xz.use_active(4, {"targets": [e]})
	ck(e.status_stacks("sword_field") == 1, "剑域施加")
	var h0 := e.hp
	var te: String = e.end_turn()
	ck(e.hp == h0 - 2, "剑域回合末2真伤")

## ---------- F. 英雄关键机制 ----------
func _test_heroes() -> void:
	print("[F] 英雄关键机制")
	# 龙王 碎晶斩/御龙
	var dg := u("crystal_dragon")
	var e1 := foe("龙敌1", 10)
	dg.add_shield(3)
	var h0 := e1.hp
	var cz: String = dg.use_active(3, {"targets": [e1]})
	ck(e1.hp == h0 - 3 and dg.shield == 0, "碎晶斩清盾3真伤")
	dg.grant_counter("元晶", 6)
	dg.add_energy(30)
	var e2 := foe("龙敌2", 8)
	var e3 := foe("龙敌3", 8)
	var yl: String = dg.use_active(4, {"targets": [e1, e2, e3]})
	ck(dg.counter("元晶") >= 4, "御龙消耗3晶回1晶")
	# 剑舞 诛心回8
	var jw := u("jianwu")
	jw.energy = 14
	var low := foe("残", 3, 40)
	low.max_hp = 10
	var zx: String = jw.use_active(4, {"targets": [low]})
	ck(not low.alive and jw.energy == 12, "诛心斩杀回8能量")
	# 追猎 创伤与架盾上限
	var zl := u("zhuilie")
	ck(zl.armor == 3, "追猎初始甲3")
	var jd: String = zl.use_active(3, {})
	ck(zl.armor == 3 and zl.shield == 2, "架盾甲cap3、盾+2")
	# 药师 建木
	var ys := u("yao_shi")
	var foe1 := foe("药靶", 10)
	foe1.lose_hp(4)  # 6/10，已损4
	ys.hp = 10
	var jm: String = ys.use_active(1, {"targets": [foe1]})
	ck(ys.hp == 7 and ys.energy == 3, "建木：耗3（目标6/2）回3能（伤2=已损4半）")
	# 药师 建木（满血 + 高护甲目标也必须打出伤害，且能量只能回到药师自己身上）
	var ys2 := u("yao_shi")
	var foe2 := foe("满血靶", 10)
	foe2.armor = 3
	var en0 := foe2.energy
	ys2.use_active(1, {"targets": [foe2]})
	ck(foe2.hp <= 8, "建木：满血甲3目标仍造成伤害（保底2）")
	ck(foe2.energy == en0 and ys2.energy > 0, "建木：敌人能量不变，能量只回到药师自身")
	# 药师 寿瘟祸祖（3伤不被护甲全免）
	var ys3 := u("yao_shi")
	var foe3 := foe("祸祖靶", 10)
	foe3.armor = 3
	ys3.use_active(2, {"targets": [foe3]})
	ck(foe3.hp == 7, "寿瘟祸祖：对甲3目标稳定3伤")
	# 药师 药灵（大招不能是 self_buff，否则战斗层不给目标 → 永远打不到人）
	ck(not bool((SE.DATA["yao_ling"] as Dictionary).get("ai", {}).get("self_buff", false)), "药灵非 self_buff（否则无目标）")
	var ys4 := u("yao_shi")
	ys4.add_energy(12)
	var foe4 := foe("药灵靶", 10)
	foe4.armor = 3
	ys4.use_active(4, {"targets": [foe4]})
	# 浮点化：耗血 9 → 护盾 4.5（旧版 ceili 为 5），真伤 4.5 → 10 → 5.5
	ck(is_equal_approx(foe4.hp, 5.5) and ys4.hp == 1, "药灵：对相邻敌人造成护盾量真伤并锁血1")
	# 孤狼 伸缩远击封大 + 阴阳
	var gl := u("gu_lang")
	var ff := foe("孤敌", 10)
	var ss: String = gl.use_active(2, {"targets": [ff], "dist": 2})
	ck(ff.has_flag("no_ult"), "伸缩远击封大招")
	var yss: String = gl.use_active(1, {})
	ck(gl.has_flag("yin") and gl.mitigation_of("火") == 15, "阴阳阴态15%减伤")
	# rapper 掠夺/无敌
	var rp := u("he_zhigao")
	var tar: BattleUnit = BU.new({"name": "靶", "hp": 10, "energy": 20, "armor": 0, "speed": 50, "element": "火", "skills": {"actives": ["snap_shot", "hunt", "shield_up"]}})
	tar.team = 1
	var lv: String = rp.use_active(1, {"targets": [tar]})
	ck(tar.is_skill_lost("snap_shot"), "掠夺禁技（限时锁）")
	ck(rp.get_skill(1).id == "lve_duo", "掠夺当回合仍是原技能")
	rp.on_turn_start()
	ck(rp.get_skill(1).id == "snap_shot" and rp.stolen_skill_id == "snap_shot", "下回合起第1槽换成掠夺技")
	var blocked: String = tar.use_active(1, {"targets": [rp]})
	ck(blocked.contains("被掠夺") and tar.is_skill_lost("snap_shot"), "被掠夺方下个对方回合无法释放该技")
	tar.end_turn()
	ck(not tar.is_skill_lost("snap_shot"), "被掠夺方回合结束解锁该技")
	var reuse: String = tar.use_active(1, {"targets": [rp]})
	ck(not reuse.contains("被掠夺"), "解锁后可重新使用")
	rp.end_turn()
	ck(rp.get_skill(1).id == "snap_shot", "掠夺技第1个自身回合仍在")
	rp.end_turn()
	ck(rp.get_skill(1).id == "lve_duo" and rp.stolen_skill_id == "", "掠夺技第2个自身回合结束归还第1槽")
	rp.lose_hp(3)
	var h1 := rp.hp
	var sx: String = rp.use_active(3, {})
	ck(rp.has_flag("免伤60") and rp.hp == h1 + 1, "锁血60%免伤+回1")
	var db4: Dictionary = rp.take_damage(10)
	ck(db4["hp_lost"] <= 4, "锁血期间10伤最多承受4")
	# 仙尊五行 & 束缚
	var xz := u("xian_zun")
	xz.add_energy(30)
	xz.energy = 18
	var fe := foe("仙敌", 6)
	var wx: String = xz.use_active(1, {"targets": [fe]})
	ck(fe.hp <= 4, "五行之力命中伤害")
	# 辛克莱：理智上限25/失控归零/烧伤
	var xk := u("xin_kelai")
	ck(xk.sanity_cap == 25 and xk.hp == 6, "辛克莱理智25/6血")
	var xe := foe("克敌", 10)
	xk.use_active(1, {"targets": [xe]})
	xk.use_active(1, {"targets": [xe]})
	xk.use_active(1, {"targets": [xe]})  # -21
	xk.use_active(4, {"targets": [xe]})  # -15 → -36 且 已损>0 大招
	ck(xk.has_flag("sanity_break"), "理智转负触发失控")
	# 新时序（2026-09-06 修复）：理智为负 → 回合末保留负值等下回合失控 → 失控执行后归零 → 再下回合起正常回复
	var te: String = xk.end_turn()
	ck(xk.sanity < 0, "理智为负时回合末保留负值（不提前归零，否则战斗层看不到失控信号）")
	xk.add_flag("sanity_outbreak")   # 模拟战斗层 _crazy 已执行
	var te2: String = xk.end_turn()
	ck(xk.sanity == 0 and not xk.has_flag("sanity_outbreak"), "失控执行后回合末理智归零")
	var te3: String = xk.end_turn()
	ck(xk.sanity > 0, "理智非负时回合末回复 30% 缺损（理智能重新积累）")
	ck(xe.status_stacks("burn") > 0, "辛克莱施加烧伤")
	# 灵虚 解析破甲恢复
	var lx := u("ling_xu")
	var lxe := foe("灵敌", 10, 40)
	lxe.armor = 3
	lx.add_energy(30)
	var jx: String = lx.use_active(2, {"targets": [lxe]})
	ck(lxe.armor == 1, "解析破甲2")
	lxe.end_turn(); lxe.end_turn(); lxe.end_turn()
	ck(lxe.armor == 3, "破甲3回合后恢复")
	# 流萤（火萤IV型）：形态切换闭环
	var ly := u("liu_ying")
	ck(ly.hp == 12 and ly.get_skill(1).id == "tian_huo" and ly.get_skill(2) == null, "流萤初始次级形态（12血/仅天火）")
	var le := foe("萤靶", 10)
	le.add_shield(5)
	ly.use_active(1, {"targets": [le]})
	ck(is_equal_approx(ly.hp, 6.0), "天火烧 50% 血（12→6）")
	ck(ly.has_status("full_burn") and ly.effective_speed() == 180, "进入完全燃烧（速度 100+80=180）")
	ck(ly.get_skill(1).id == "di_huo_zhan_ji" and ly.get_skill(2).id == "si_xing_guo_zai" and ly.get_skill(4).id == "chao_xin_xing", "技能组切换为完全形态")
	ck(le.shield == 3, "天火对盾额外烧毁 1（盾吸1+额外1：5→3）")
	ly.use_active(1, {"targets": [le]})
	ck(is_equal_approx(le.hp, 9.0) and le.shield == 1 and ly.energy == 20, "底火 1 真伤+烧盾 2（3→1）+回能（满截断 20）")
	ck(ly.counter("燃烧攻击") == 1, "燃烧攻击 1/3")
	le.add_shield(1)   # 盾 2
	ly.use_active(2, {"targets": [le]})
	ck(is_equal_approx(le.hp, 7.0) and le.shield == 0, "死星 2 伤（盾2全吸扣血0）+烧盾2+追真伤2")
	ck(ly.counter("燃烧攻击") == 2, "燃烧攻击 2/3")
	var le2 := foe("萤靶2", 10)
	le2.team = 1
	ly.use_active(4, {"targets": [le, le2]})
	ck(is_equal_approx(le.hp, 5.0) and is_equal_approx(le2.hp, 8.0), "超新星对 2 目标各 2 真伤")
	ck(not ly.has_status("full_burn") and ly.get_skill(1).id == "tian_huo" and ly.effective_speed() == 100, "超新星后强制退回次级形态")
	# 李太白（诗仙）：醉意闭环
	var lb := u("li_taibai")
	ck(lb.counter("醉意") == 0 and lb.speed == 205, "李太白初始醉意 0/速 205")
	lb.use_active(1, {})
	ck(lb.counter("醉意") == 2, "将进酒 +2 醉意")
	lb.on_turn_start()
	ck(lb.counter("醉意") == 3, "回合开始自动 +1 醉意（3）")
	lb.add_energy(30)
	var b1 := foe("诗敌1", 10); b1.team = 1
	var b2 := foe("诗敌2", 10); b2.team = 1
	lb.use_active(2, {"targets": [b1, b2]})
	ck(lb.counter("醉意") == 1, "笔墨挥洒后醉意 -2（1）")
	lb.grant_counter("醉意", 3)
	var b3 := foe("诗敌3", 10); b3.team = 1
	lb.use_active(3, {"targets": [b3]})
	ck(lb.counter("醉意") == 0 and is_equal_approx(b3.hp, 6.0), "肆意消耗 4 醉意造成 4 伤并清零")
	lb.set_counter("醉意", 5)
	lb.on_turn_start()
	ck(lb.has_flag("stun") and lb.counter("醉意") == 0, "醉意≥5 回合开始酒醉（stun）并清零")
	# 虞美人（怀恨）：基础 + 情愫 + 悔恨
	var ym := u("yu_mei_ren")
	ck(is_equal_approx(ym.hp, 15.0) and ym.counter("愤恨") == 2, "虞美人 15 血/愤恨 2")
	ck(ym.effective_speed() == 1, "速度 0 → 有效速度 1（永最后行动）")
	var ally := foe("花友", 6); ally.team = 0; ally.lose_hp(2)
	ym.use_active(2, {"allies": [ym, ally]})
	ck(is_equal_approx(ally.hp, 4.3), "情愫 3×3 友方回 5% 最大生命（6→4.3）")
	var hfe := foe("悔敌", 10); hfe.team = 1
	ym.use_active(4, {"targets": [hfe]})
	ck(hfe.status_stacks("fear") == 3, "悔恨恐惧 +3")
