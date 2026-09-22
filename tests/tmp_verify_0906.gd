extends SceneTree
## 临时验证：开局 2 格移动 / 状态图标 / 辛克莱大招重伤阈值 3 / 追猎大招多目标
## 用法：godot --headless --path . -s res://tests/tmp_verify_0906.gd

var _pass := 0
var _fail := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)

func _initialize() -> void:
	var BT = load("res://scripts/combat/battle_team.gd")
	var BU = load("res://scripts/combat/battle_unit.gd")
	var HD = load("res://scripts/combat/hero_defs.gd")
	var SE = load("res://scripts/combat/skill_effects.gd")

	print("[1] 4V4 开局第 1 回合可走 2 格")
	var b = BT.new(["zhuilie", "gu_lang", "yao_shi", "xin_kelai"],
				   ["jianwu", "xie_shen", "guang_yu", "ling_xu"])
	b.human_mode = true
	b.human_team = 0
	var u0 = b.units[0]
	b.round = 1
	var c1: Array = b.move_cells_of(u0)
	var far := 0
	for c in c1:
		if b._cell_dist(c, u0.cell) == 2:
			far += 1
	ck(far > 0, "第1回合含距离2的格子（%d 个）" % far)
	b.round = 2
	var c2: Array = b.move_cells_of(u0)
	var far2 := 0
	for c in c2:
		if b._cell_dist(c, u0.cell) == 2:
			far2 += 1
	ck(far2 == 0, "第2回合起恢复1格（距离2的格子数=%d）" % far2)
	ck(c2.size() < c1.size(), "第1回合可走格数(%d) > 第2回合(%d)" % [c1.size(), c2.size()])

	print("[2] 切比雪夫射程：斜对角算 1")
	ck(b._cell_dist(Vector2i(3, 3), Vector2i(4, 4)) == 1, "斜对角距离 = 1")
	ck(b._cell_dist(Vector2i(3, 3), Vector2i(5, 3)) == 2, "直线2格 = 2")

	print("[3] 状态图标数据")
	var x = BU.new(HD.ALL["zhuilie"].duplicate(true))
	x.add_status("bleed", 2)
	x.add_status("poison", 1)
	var icons: Array = x.status_icons()
	ck(icons.size() == 2, "返回 2 个状态图标")
	var has_poison := false
	for d in icons:
		if str((d as Dictionary).get("id", "")) == "poison":
			has_poison = true
			ck(str((d as Dictionary).get("cn", "")) == "中毒", "中毒状态中文名正确")
	ck(has_poison, "中毒状态可见")

	print("[4] 辛克莱大招：重伤 3 层即施加灼烧")
	var xk = BU.new(HD.ALL["xin_kelai"].duplicate(true))
	var tgt = BU.new({"name": "靶", "hp": 10, "energy": 0, "armor": 0, "speed": 50, "element": "火", "skills": {}})
	tgt.team = 1
	tgt.lose_hp(4)
	tgt.add_status("heavy_wound", 3)
	var before_burn: int = tgt.status_stacks("burn")
	var out4: String = xk.use_active(4, {"targets": [tgt], "mode": "4v4"})
	ck(tgt.status_stacks("burn") > before_burn, "重伤3层 → 大招施加灼烧")
	print("     日志：", out4)

	print("[5] 追猎大招：max_targets = 2")
	ck(int(SE.DATA["meteor_shot"].get("max_targets", 1)) == 2, "meteor_shot max_targets=2")
	var zl = BU.new(HD.ALL["zhuilie"].duplicate(true))
	ck(b.max_targets_of(zl, 4) == 2, "战斗层 max_targets_of(追猎,4)=2")
	var e1 = BU.new({"name": "敌1", "hp": 10, "energy": 0, "armor": 0, "speed": 50, "element": "火", "skills": {}})
	var e2 = BU.new({"name": "敌2", "hp": 10, "energy": 0, "armor": 0, "speed": 50, "element": "火", "skills": {}})
	e1.team = 1
	e2.team = 1
	var h1: int = e1.hp
	var h2: int = e2.hp
	var out5: String = zl.use_active(4, {"targets": [e1, e2], "mode": "4v4"})
	ck(e1.hp < h1 and e2.hp < h2, "两个目标都受到伤害")
	print("     日志：", out5)

	print("[6] 冲刺 8 方向")
	var xk2 = BU.new(HD.ALL["xin_kelai"].duplicate(true))
	xk2.cell = Vector2i(2, 4)
	xk2.team = 0
	var b2 = BT.new(["xin_kelai", "zhuilie", "yao_shi", "gu_lang"],
					["jianwu", "xie_shen", "guang_yu", "ling_xu"])
	b2.units[0].cell = Vector2i(2, 4)
	# 斜向冲刺（右下）
	var r6: Dictionary = b2._charge_along(b2.units[0], Vector2i(4, 6), 3)
	var dest6: Vector2i = r6["cell"]
	# 起点(2,4) 斜向右下冲 3 格 → (3,5)→(4,6)→(5,7)
	ck(dest6.x == 5 and dest6.y == 7, "斜向冲刺落点 (%d,%d) = 起点+3×(1,1)" % [dest6.x, dest6.y])
	# 只冲 1 格（辛克莱迫不得已 dash_dist=1）
	var r6b: Dictionary = b2._charge_along(b2.units[0], Vector2i(4, 6), 1)
	var dest6b: Vector2i = r6b["cell"]
	ck(dest6b.x == 3 and dest6b.y == 5, "斜向冲刺1格落点 (%d,%d)" % [dest6b.x, dest6b.y])
	var aims: Array = b2.charge_aim_cells(b2.units[0], 2)
	ck(aims.size() > 8, "冲刺方向高亮格数=%d（8方向×步数）" % aims.size())

	print("\n== 临时验证结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
