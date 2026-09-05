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
	ck(g.mitigation_att(a1) == 10 and g.hp == g0 - 4, "锻体2层(10%)与all共60%（10→4）")
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
	t.add_status("bleed", 3)
	var act: String = SE.tick_action_statuses(t)
	ck(t.hp == 17, "流血行动结算 3 真伤")
	var te: String = t.end_turn()
	ck(t.status_stacks("bleed") == 2, "回合末流血 -1")
	# 创伤3 → 流血2
	var tu := foe("敌2", 20)
	tu.add_status("wound", 2)
	var txt: String = SE.add_wound(tu, 1)
	ck(tu.status_stacks("bleed") == 2 and tu.status_stacks("wound") == 0, "创伤满3→流血2级")
	# 烧伤（新表：末1真伤·2回合·减速·刷新）
	var tb := foe("敌3", 20)
	SE.apply_burn(tb)
	ck(tb.status_stacks("burn") == 2 and tb.speed_mod_total() == -10, "烧伤：2回合+减速10")
	var h0 := tb.hp
	tb.end_turn()
	ck(tb.hp == h0 - 1 and tb.status_stacks("burn") == 1, "烧伤回合末1真伤、余1")
	tb.end_turn()
	ck(tb.status_stacks("burn") == 0 and tb.speed_mod_total() == 0, "烧伤到期清除减速")
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
	ck(tar.is_skill_lost("snap_shot"), "掠夺禁技")
	ck(rp.get_skill(1).id == "lve_duo", "掠夺当回合仍是原技能")
	rp.on_turn_start()
	ck(rp.get_skill(1).id == "snap_shot" and rp.stolen_skill_id == "snap_shot", "下回合起第1槽换成掠夺技")
	var blocked: String = tar.use_active(1, {"targets": [rp]})
	ck(blocked.contains("被掠夺") and tar.is_skill_lost("snap_shot"), "被掠夺方本局无法释放该技")
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
	var te: String = xk.end_turn()
	ck(xk.sanity == 0 and not xk.has_flag("sanity_break"), "失控回合末理智归零")
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
