extends SceneTree
## 掉血特效回归测试（Damage FX）—— 2026-09-13 建立
## 用法：Godot --headless --path 工程 -s res://tests/damage_fx_smoke.gd
##
## 覆盖两块：
##   ① 战斗层信号契约：damaged（一次挨打只发一次）/ hp_drained（真伤兜底，且不重复发）
##   ② unit_token 特效：订阅、闪红、白条残影、飘字、击杀碎裂、缓动收敛
## 全部通过 exit 0，有失败 exit 1。

var _pass := 0
var _fail := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)

# 信号计数（用信号连到测试脚本自身）
var _dmg_events: Array = []
var _drain_events: Array = []

func _on_dmg(u: BattleUnit, result: Dictionary) -> void:
	_dmg_events.append({"u": u, "r": result})

func _on_drain(u: BattleUnit, amount: float) -> void:
	_drain_events.append({"u": u, "a": amount})

func _initialize() -> void:
	await process_frame
	var BU = load("res://scripts/combat/battle_unit.gd")
	var HD = load("res://scripts/combat/hero_defs.gd")
	var UT = load("res://scripts/ui/unit_token.gd")
	print("== 掉血特效回归 ==")

	# ================= ① 战斗层信号契约 =================
	var a: BattleUnit = BU.new(HD.ALL["jianwu"].duplicate(true))
	var b: BattleUnit = BU.new(HD.ALL["gu_lang"].duplicate(true))
	a.cell = Vector2i(0, 0)
	b.cell = Vector2i(1, 0)
	a.team = 1
	b.team = 0
	a.damaged.connect(_on_dmg)
	a.hp_drained.connect(_on_drain)
	a.max_hp = 20.0
	a.hp = 20.0
	a.shield = 0.0
	a.armor = 0.0

	# 1) 普通攻击 → 恰好 1 次 damaged，0 次 hp_drained（内部 lose_hp 不重复报）
	var r1: Dictionary = a.take_damage(3.0, {"attacker": b, "sure_hit": true})
	ck(_dmg_events.size() == 1, "take_damage 只发 1 次 damaged（实际 %d）" % _dmg_events.size())
	ck(_drain_events.size() == 0, "take_damage 内部不再发 hp_drained（实际 %d）" % _drain_events.size())
	ck(float(r1.get("hp_lost", 0.0)) > 0.0, "伤害确实扣了血（hp_lost=%s）" % r1.get("hp_lost"))

	# 2) 绕过 take_damage 的直接掉血（真伤）→ 发 hp_drained
	var hp_before: float = a.hp
	a.lose_hp(2.5)
	ck(_drain_events.size() == 1, "lose_hp 直接掉血发 hp_drained（实际 %d）" % _drain_events.size())
	if _drain_events.size() == 1:
		ck(absf(float(_drain_events[0]["a"]) - 2.5) < 0.001,
			"hp_drained 金额正确（2.5，实际 %s）" % _drain_events[0]["a"])
	ck(a.hp < hp_before, "直接掉血确实生效")

	# 3) 被护盾全挡 → hp_lost=0 但 absorbed>0（UI 据此显示"挡 N"）
	a.shield = 50.0
	_dmg_events.clear()
	var r3: Dictionary = a.take_damage(4.0, {"attacker": b, "sure_hit": true})
	ck(_dmg_events.size() == 1, "全挡也发 damaged（供 UI 显示格挡）")
	ck(float(r3.get("hp_lost", 0.0)) == 0.0 and float(r3.get("absorbed", 0.0)) > 0.0,
		"全挡时 hp_lost=0 / absorbed>0")

	# 4) 免疫 / 闪避不崩且带标记
	a.shield = 0.0
	a.add_flag("invuln")
	_dmg_events.clear()
	var r4: Dictionary = a.take_damage(5.0, {"attacker": b})
	ck(_dmg_events.size() == 1 and bool(r4.get("invuln", false)), "免疫帧照发 damaged 且 marked invuln")
	a.clear_flag("invuln")

	# 5) 击杀 → killed=true
	a.hp = 1.0
	_dmg_events.clear()
	var r5: Dictionary = a.take_damage(9.0, {"attacker": b, "sure_hit": true})
	ck(bool(r5.get("killed", false)), "致死伤害 killed=true")

	# ================= ② unit_token 特效 =================
	var host := Control.new()
	host.size = Vector2(600, 400)
	root.add_child(host)
	await process_frame

	var u2: BattleUnit = BU.new(HD.ALL["jianwu"].duplicate(true))
	u2.max_hp = 10.0
	u2.hp = 10.0
	u2.team = 1
	u2.cell = Vector2i(0, 0)

	var tok = UT.new()
	tok.size = Vector2(64, 64)
	host.add_child(tok)
	tok.setup(u2, false)
	ck(tok._unit == u2, "token 已绑定单位")
	ck(u2.damaged.is_connected(tok._on_damaged), "token 已订阅 damaged 信号")
	ck(u2.hp_drained.is_connected(tok._on_drained), "token 已订阅 hp_drained 信号")

	# 重复 setup 不应重复连接（Godot 重复 connect 会报错）
	var guard := true
	for i in range(5):
		tok.setup(u2, false)
	guard = u2.damaged.is_connected(tok._on_damaged)
	ck(guard, "反复 setup 不会重复连接（无报错）")

	ck(absf(tok._hp_ghost - 10.0) < 0.001, "首次 setup 白条残影对齐血条（=10）")

	# 造成伤害：白条残影应冻结在旧值、闪红点亮、飘字生成
	var labels_before := _count_labels(host)
	u2.take_damage(3.0, {"sure_hit": true})
	ck(tok._hp_ghost >= 9.9, "受击瞬间白条残影冻结在旧血量（=%.2f）" % tok._hp_ghost)
	ck(tok._flash > 0.5, "受击闪红点亮（flash=%.2f）" % tok._flash)
	ck(tok.is_processing(), "特效期间开启 _process")
	var labels_after := _count_labels(host)
	ck(labels_after > labels_before, "生成了飘字 Label（%d → %d）" % [labels_before, labels_after])

	# 直接掉血（真伤）也要有反馈
	labels_before = _count_labels(host)
	u2.lose_hp(1.5)
	ck(_count_labels(host) > labels_before, "真伤也生成飘字")

	# 模拟棋盘刷新（真实流程：伤害发生在 run_step 内，之后 UI 才调 setup 刷新）
	# 刷新后 hp 才降到新值，白条残影应保持在旧值 → 露出"掉了多少"的白段
	tok.setup(u2, false)
	ck(tok._hp_ghost > tok.hp + 1.0,
		"刷新后白条残影高于血条，露出掉血段（ghost=%.2f hp=%.2f）" % [tok._hp_ghost, tok.hp])

	# 推进若干帧：闪红应衰减、白条残影应收敛到新血量、_process 自动关闭
	for i in range(120):
		await process_frame
	ck(tok._flash < 0.001, "闪红已衰减归零（%.4f）" % tok._flash)
	ck(absf(tok._hp_ghost - tok.hp) < 0.005,
		"白条残影收敛到当前血条（ghost=%.2f hp=%.2f）" % [tok._hp_ghost, tok.hp])
	ck(not tok.is_processing(), "空闲后 _process 自动关闭（不空转）")

	# 回血时白条残影应立刻跟上（不允许出现"白条比血条低"的反向缺口）
	u2.hp = u2.max_hp
	tok.setup(u2, false)
	ck(absf(tok._hp_ghost - u2.max_hp) < 0.001,
		"回血时白条残影直接对齐（=%.2f）" % tok._hp_ghost)

	# 击杀 → 应生成碎裂特效（挂在父节点，不随 token 消失）
	var fx_before := _count_breakfx(host)
	u2.take_damage(99.0, {"sure_hit": true})
	var fx_after := _count_breakfx(host)
	ck(fx_after > fx_before, "击杀生成碎裂特效（%d → %d）" % [fx_before, fx_after])

	# 解绑后不应再收到旧单位的信号（防串台）
	var u3: BattleUnit = BU.new(HD.ALL["gu_lang"].duplicate(true))
	u3.max_hp = 10.0
	u3.hp = 10.0
	tok.setup(u3, false)
	ck(not u2.damaged.is_connected(tok._on_damaged), "换绑后已从旧单位退订")
	ck(u3.damaged.is_connected(tok._on_damaged), "换绑后已订阅新单位")
	ck(tok._unit == u3, "token 绑定已切换到新单位")

	# ================= ③ 护盾 + 血量同条显示（2026-09-13）=================
	# 规则：hp+shield ≤ max_hp → 按 max_hp 等比（条不满）
	#       hp+shield >  max_hp → 按 hp:shield 比例铺满
	var v1: Vector3 = DamageFx.hp_shield_layout(7.0, 0.0, 10.0)
	ck(absf(v1.x - 10.0) < 0.001 and absf(v1.y - 0.7) < 0.001 and v1.z == 0.0,
		"① 无盾：分母=10 hp=0.70 sh=0（实际 %.2f/%.2f/%.2f）" % [v1.x, v1.y, v1.z])
	var v2: Vector3 = DamageFx.hp_shield_layout(7.0, 2.0, 10.0)
	ck(absf(v2.x - 10.0) < 0.001 and absf(v2.y - 0.7) < 0.001 and absf(v2.z - 0.2) < 0.001,
		"② 血+盾未满：分母=10 hp=0.70 sh=0.20，合计 0.90 不满条")
	ck(v2.y + v2.z < 1.0 - 0.001, "   合计 0.90 < 1 → 血条留有空白")
	var v3: Vector3 = DamageFx.hp_shield_layout(7.0, 5.0, 10.0)
	ck(absf(v3.y + v3.z - 1.0) < 0.001, "③ 血+盾超上限：两段合计=1.00（铺满整条）")
	ck(absf(v3.y - 7.0 / 12.0) < 0.001 and absf(v3.z - 5.0 / 12.0) < 0.001,
		"   按 hp:shield 比例分配（7/12=%.4f, 5/12=%.4f）" % [v3.y, v3.z])
	# 连续性：total == max_hp 处两式取值必须一致（护盾刚好看满条时不跳变）
	var v4: Vector3 = DamageFx.hp_shield_layout(6.0, 4.0, 10.0)
	ck(absf(v4.y - 0.6) < 0.001 and absf(v4.z - 0.4) < 0.001 and absf(v4.y + v4.z - 1.0) < 0.001,
		"④ 临界点 total==max_hp：0.60 + 0.40 = 1.00，与两式都吻合（连续）")
	# 边界与防御
	var v5: Vector3 = DamageFx.hp_shield_layout(0.0, 0.0, 10.0)
	ck(v5.y == 0.0 and v5.z == 0.0, "⑤ 空血空盾：两段都是 0")
	var v6: Vector3 = DamageFx.hp_shield_layout(1.0, 999.0, 10.0)
	ck(absf(v6.y + v6.z - 1.0) < 0.001 and v6.z > 0.98, "⑥ 巨盾：仍铺满且盾段几乎占满")
	var v7: Vector3 = DamageFx.hp_shield_layout(-5.0, -5.0, 0.0)
	ck(v7.x >= 1.0 and v7.y == 0.0 and v7.z == 0.0, "⑦ 负值/max≤0 不炸（分母兜底 ≥1）")

	# HpShieldBar 控件行为
	var HSB = load("res://scripts/ui/hp_shield_bar.gd")
	var hb = HSB.new()
	hb.size = Vector2(200.0, 22.0)
	host.add_child(hb)
	await process_frame
	hb.set_values(7.0, 2.0, 10.0)
	ck(absf(hb.hp - 7.0) < 0.001 and absf(hb.shield - 2.0) < 0.001 and absf(hb.max_hp - 10.0) < 0.001,
		"HpShieldBar 记录了 hp/shield/max_hp")
	ck(absf(hb._shown - 7.0) < 0.001, "首次 set_values 直接对齐（不播掉血动画）")
	hb.set_values(5.0, 2.0, 10.0)
	ck(absf(hb._ghost - 7.0) < 0.001, "掉血时白条残影冻结在旧 hp（=7）")
	ck(hb.is_processing(), "掉血期间开启 _process")
	for i in range(90):
		await process_frame
	ck(absf(hb._shown - 5.0) < 0.005 and absf(hb._ghost - 5.0) < 0.005,
		"hp 段与白条残影都收敛到新血量（shown=%.2f ghost=%.2f）" % [hb._shown, hb._ghost])
	ck(not hb.is_processing(), "空闲后 _process 自动关闭")
	# 只改护盾（血量不变）→ 不应触发任何残影/缓动
	hb.set_values(5.0, 4.0, 10.0)
	ck(absf(hb._ghost - 5.0) < 0.001, "只加护盾不产生白条残影（用户要求护盾不做动态特效应）")
	# 护盾段宽度按规则走：hp=5 sh=4 max=10 → 分母 10 → 0.5 + 0.4
	var v8: Vector3 = DamageFx.hp_shield_layout(hb.hp, hb.shield, hb.max_hp)
	ck(absf(v8.y - 0.5) < 0.001 and absf(v8.z - 0.4) < 0.001,
		"   控件当前值换算：hp 0.50 / shield 0.40（条不满 0.90）")

	# token 的 shield 也要从单位同步过来
	u3.shield = 3.0
	tok.setup(u3, false)
	ck(absf(tok.shield - 3.0) < 0.001, "token.shield 从单位同步（=3）")

	print("== 掉血特效回归结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _count_labels(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Label:
			c += 1
	return c

func _count_breakfx(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch.name == "BreakFx":
			c += 1
	return c
