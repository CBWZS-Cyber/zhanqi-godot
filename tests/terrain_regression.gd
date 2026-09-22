extends SceneTree
## 地形效果回归（Terrain 规则）——2026-09-10 建立
## 覆盖：沼泽减速/森林免伤/山地增伤/移出代价/水域沙地禁位移/冰面滑行
##       + ⑦ 棋盘→terrain_id 同步链路（2026-09-13 补，剧情关曾因缺此链路整体空转）
func _initialize() -> void:
	await process_frame
	var B = load("res://scripts/combat/battle.gd")
	var T = load("res://scripts/combat/terrain.gd")
	var ok_all := true

	# ---------- 1) 沼泽减速 -30 ----------
	var b = B.new("jianwu", "gu_lang")
	var u: BattleUnit = b.units[0]
	var base_spd := u.effective_speed()
	u.terrain_id = T.SWAMP
	var swamp_spd := u.effective_speed()
	var t1: bool = swamp_spd == maxi(1, base_spd - 30)
	print("① 沼泽减速: base=%d swamp=%d → %s" % [base_spd, swamp_spd, "PASS" if t1 else "FAIL"])

	# ---------- 2) 森林免伤（同一攻击强度对比） ----------
	var defender: BattleUnit = b.units[1]
	defender.terrain_id = T.EMPTY
	var hp0: float = defender.hp
	defender.take_damage(5.0, {"sure_hit": true})
	var dmg_open: float = hp0 - defender.hp
	defender.hp = hp0
	defender.alive = true
	defender.terrain_id = T.FOREST
	defender.take_damage(5.0, {"sure_hit": true})
	var dmg_forest: float = hp0 - defender.hp
	var t2: bool = absf(dmg_forest - dmg_open * 0.8) < 0.51 and dmg_open > 0
	print("② 森林免伤20%%: 空地=%.1f 森林=%.1f（期望 %.1f）→ %s" % [dmg_open, dmg_forest, dmg_open * 0.8, "PASS" if t2 else "FAIL"])

	# ---------- 3) 山地增伤 +30% ----------
	var b2 = B.new("jianwu", "gu_lang")
	var atk: BattleUnit = b2.units[0]
	var def2: BattleUnit = b2.units[1]
	atk.terrain_id = T.EMPTY
	var h2: float = def2.hp
	def2.take_damage(5.0, {"sure_hit": true, "attacker": atk})
	var d_open2: float = h2 - def2.hp
	def2.hp = h2
	def2.alive = true
	atk.terrain_id = T.MOUNTAIN
	def2.take_damage(5.0, {"sure_hit": true, "attacker": atk})
	var d_mount: float = h2 - def2.hp
	var t3: bool = absf(d_mount - d_open2 * 1.3) < 0.51 and d_open2 > 0
	print("③ 山地增伤30%%: 平地=%.1f 山地=%.1f（期望 %.1f）→ %s" % [d_open2, d_mount, d_open2 * 1.3, "PASS" if t3 else "FAIL"])

	# ---------- 4) 移出能量代价（不足则禁止） ----------
	var b3 = B.new("jianwu", "gu_lang")
	var m: BattleUnit = b3.units[0]
	m.terrain_id = T.MOUNTAIN
	m.energy = 1                     # 山地需 2 → 不足
	var gate1: String = b3._terrain_exit_gate(m)
	var t4a: bool = gate1.begins_with("!") and m.energy == 1
	m.energy = 5
	var gate2: String = b3._terrain_exit_gate(m)
	var t4b: bool = gate2 == "" and m.energy == 3
	print("④ 移出代价: 能量不足拦截=%s 充足扣2=%s → %s" % [t4a, t4b, "PASS" if (t4a and t4b) else "FAIL"])

	# ---------- 5) 水域/沙地禁位移技能 ----------
	var b4 = B.new("xin_kelai", "gu_lang")   # 辛克莱有冲刺位移技
	var sk: BattleUnit = b4.units[0]
	# 找一个位移技能槽
	var dash_slot := -1
	for i in range(4):
		if b4.is_dash(sk, i):
			dash_slot = i
			break
	var t5 := false
	if dash_slot >= 0:
		sk.terrain_id = T.WATER
		var g1: String = b4._terrain_dash_gate(sk, dash_slot)
		sk.terrain_id = T.SAND
		var g2: String = b4._terrain_dash_gate(sk, dash_slot)
		sk.terrain_id = T.EMPTY
		var g3: String = b4._terrain_dash_gate(sk, dash_slot)
		t5 = g1.begins_with("!") and g2.begins_with("!") and g3 == ""
		print("⑤ 水域/沙地禁位移: 水=%s 沙=%s 空地=%s → %s" % [g1.begins_with("!"), g2.begins_with("!"), g3 == "", "PASS" if t5 else "FAIL"])
	else:
		print("⑤ 未找到位移技能槽（FAIL）")

	# ---------- 6) 冰面滑行 ----------
	var gb = GridBoard.new()
	for x in range(0, 5):
		gb.add_cell(Vector2i(x, 0))
	for x in range(1, 4):
		gb.set_cell_terrain(Vector2i(x, 0), T.ICE)   # 1,2,3 为冰面
	var start := Vector2i(1, 0)
	var end := gb.slide_end(start, Vector2i(1, 0))
	var t6: bool = end == Vector2i(4, 0)   # 滑到冰面边缘外第一格（4 空地）
	print("⑥ 冰面滑行: 从%s 向右 → %s（期望 (4,0)）→ %s" % [start, end, "PASS" if t6 else "FAIL"])

	# ---------- 7) 棋盘 → terrain_id 的同步链路（2026-09-13 补）----------
	# 前 6 项都是「手动给 u.terrain_id 赋值」后测规则，绕过了同步这一步。
	# 剧情关曾因此整体空转：格图建好了但没交给基类 board，且地形没灌进格图，
	# 导致 terrain_id 恒为 0 —— 森林免伤/水域耗能/移出代价全部失效却无人报错。
	var BS = load("res://scripts/combat/battle_story.gd")
	var sb = BS.new()
	var t7a: bool = sb.board != null
	var t7b := false
	var t7c := false
	if t7a:
		var forest := Vector2i(-999, -999)
		for k in sb.cells:
			if int(sb.cells[k]) == T.FOREST:
				forest = sb._v2i(k)
				break
		if forest.x != -999:
			t7b = sb.board.terrain_at(forest) == T.FOREST
			var pu: BattleUnit = sb.units[0]
			var keep: Vector2i = pu.cell
			sb._place(pu, forest)
			t7c = pu.terrain_id == T.FOREST and pu.exit_energy_cost() == 1
			sb._place(pu, keep)
	print("⑦ 棋盘→terrain_id 同步: board 接线=%s 格图读森林=%s 落位同步=%s → %s" % [
		t7a, t7b, t7c, "PASS" if (t7a and t7b and t7c) else "FAIL"])

	ok_all = t1 and t2 and t3 and t4a and t4b and t5 and t6 and t7a and t7b and t7c
	print("==== 地形效果总结果:", "PASS ✅" if ok_all else "FAIL ❌", "====")
	quit(0 if ok_all else 1)
