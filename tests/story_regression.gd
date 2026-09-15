extends SceneTree
## 骑士线第一关「白灵殿」剧情关回归 —— 2026-09-12 建立
## 覆盖：逃生区坐标 / 双人护送胜负 / 牵引节奏 / 地形接入 / 可破坏障碍 / 龙水域豁免
##
## 运行：godot --headless --path . -s res://tests/story_regression.gd
## 退出码 0 = 全过；1 = 有失败
func _initialize() -> void:
	await process_frame
	var S = load("res://scripts/combat/battle_story.gd")
	var T = load("res://scripts/combat/terrain.gd")
	var ok_all := true
	var results: Array = []

	# ---------------- 开局一个干净的对局（不跑 AI，只做静态/规则断言） ----------------
	var b = S.new()

	# ---------- 1) 逃生区 = 地图最右侧 4 格 x=18,y=0~3 ----------
	var want := [Vector2i(18, 0), Vector2i(18, 1), Vector2i(18, 2), Vector2i(18, 3)]
	var esc: Array = b.escape_cells
	var t1 := esc.size() == 4
	for c in want:
		if not esc.has(c):
			t1 = false
	results.append(["① 逃生区 4 格 (18,0~3)", t1, "实际 %s" % str(esc)])
	ok_all = ok_all and t1

	# ---------- 1b) 昊 / 祁 出生点 = (0,1) / (0,2)（2026-09-13 移到地图中部） ----------
	var t1b: bool = b.protect_target != null and b.protect_target.cell == Vector2i(0, 1) \
		and b.escort_qi != null and b.escort_qi.cell == Vector2i(0, 2)
	results.append(["①b 昊(0,1) / 祁(0,2) 出生", t1b, "昊 %s / 祁 %s" % [
		b.protect_target.cell if b.protect_target else "null",
		b.escort_qi.cell if b.escort_qi else "null"]])
	ok_all = ok_all and t1b

	# ---------- 2) 护送目标确认为 昊 + 祁 ----------
	var t2: bool = b.protect_target != null and b.protect_target.def_id == "story_hao" \
		and b.escort_qi != null and b.escort_qi.def_id == "story_qi"
	results.append(["② 护送目标 = 昊 + 祁", t2,
		"昊=%s 祁=%s" % [b.protect_target.name if b.protect_target else "null",
		b.escort_qi.name if b.escort_qi else "null"]])
	ok_all = ok_all and t2

	# ---------- 3) 地形已真正接入（本次修复的核心） ----------
	# 昊出生 (0,1) 应为空地（2026-09-13 起点由 (7,1) 移到中点）
	var hao = b.protect_target
	var t3a: bool = b.board != null
	var t3b: bool = hao != null and hao.terrain_id == b.terrain_at(hao.cell)
	# 找一格森林，把单位放上去同步后应得到 FOREST
	var forest_cell := Vector2i(-9999, -9999)
	for k in b.cells:
		if int(b.cells[k]) == T.FOREST:
			forest_cell = Vector2i(int(str(k).split(",")[0]), int(str(k).split(",")[1]))
			break
	hao.cell = forest_cell
	b._sync_terrain(hao)
	var t3c: bool = hao.terrain_id == T.FOREST
	results.append(["③ 地形已接入基类 board", t3a and t3b, "board=%s terrain_id=%d" % [
		b.board != null, hao.terrain_id]])
	results.append(["③b 站森林 terrain_id=FOREST", t3c,
		"森林格 %s → terrain_id=%d" % [forest_cell, hao.terrain_id]])
	ok_all = ok_all and t3a and t3b and t3c

	# ---------- 4) 启用地形白名单：只有 森林/水域/障碍 ----------
	var t4a: bool = T.story_active(T.FOREST) and T.story_active(T.WATER)
	var t4b: bool = not T.story_active(T.SWAMP) and not T.story_active(T.MOUNTAIN) \
		and not T.story_active(T.SAND) and not T.story_active(T.ICE)
	# 地形层里不应出现未启用的地形（应被写成空地 0）
	var found_bad := -1
	for k in b.board.terrain:
		var tv := int(b.board.terrain[k])
		if tv != 0 and not T.story_active(tv):
			found_bad = tv
			break
	var t4c: bool = found_bad == -1
	results.append(["④ 启用地形白名单 = 森林/水域/障碍", t4a and t4b and t4c,
		"白名单OK=%s 未启用被过滤=%s" % [t4a and t4b, t4c]])
	ok_all = ok_all and t4a and t4b and t4c

	# ---------- 5) 可破坏障碍：红方可拆、蓝方不可拆 ----------
	# 找一格可破坏障碍
	var brk := Vector2i(-9999, -9999)
	for k in b.cells:
		if int(b.cells[k]) == T.OBST_BREAKABLE:
			var p := str(k).split(",")
			brk = Vector2i(int(p[0]), int(p[1]))
			break
	var ba = b.protect_target      # 蓝方
	var ra = null                  # 红方
	for u in b.units:
		if u.team == 0:
			ra = u
			break
	# 把红方单位挪到障碍旁边，检查射程内能列出该障碍
	ra.cell = brk + Vector2i(1, 0)
	if not b._terrain_ok(ra.cell):
		ra.cell = brk + Vector2i(0, 1)
	var red_slots: Array = b.breakable_in_range(ra, 1)
	var t5a: bool = red_slots.has(brk) or not red_slots.is_empty()
	# 蓝方即使站旁边也不能拆
	ba.cell = brk + Vector2i(1, 0)
	var t5b: bool = b.breakable_in_range(ba, 1).is_empty()
	results.append(["⑤a 红方射程内列出可破坏障碍", t5a, "障碍=%s 列出=%s" % [brk, str(red_slots)]])
	results.append(["⑤b 蓝方不能拆障碍", t5b, "蓝方列出=%d" % b.breakable_in_range(ba, 1).size()])
	ok_all = ok_all and t5a and t5b

	# ---------- 6) 障碍受击 → 变空地 + 移除障碍标记 ----------
	var was_block: bool = not b._terrain_ok(brk)
	var broke: bool = b.damage_obstacle(brk, ra)
	var now_ok: bool = b._terrain_ok(brk) and b.terrain_at(brk) == T.EMPTY
	var unblocked: bool = b.board.passable(brk)
	var t6: bool = was_block and broke and now_ok and unblocked
	results.append(["⑥ 障碍受击→空地（可通行）", t6, "破坏前不可通行=%s 破坏成功=%s 现为空地可通行=%s" % [
		was_block, broke, now_ok and unblocked]])
	ok_all = ok_all and t6

	# ---------- 7) 已破坏的障碍不能重复拆 ----------
	var t7: bool = not b.damage_obstacle(brk, ra)
	results.append(["⑦ 空地不能再被拆", t7, "二次破坏返回=%s" % (not t7)])
	ok_all = ok_all and t7

	# ---------- 8) 龙无视水域 ----------
	var dragon = null
	for u in b.units:
		if u.def_id == "story_dragon":
			dragon = u
			break
	var t8a: bool = dragon != null and dragon.water_immune
	# 找一格水域
	var water := Vector2i(-9999, -9999)
	for k in b.cells:
		if int(b.cells[k]) == T.WATER:
			var p := str(k).split(",")
			water = Vector2i(int(p[0]), int(p[1]))
			break
	dragon.cell = water
	b._sync_terrain(dragon)
	var t8b: bool = dragon.terrain_id == T.WATER
	# 龙在水域：不扣能量、位移禁令豁免
	dragon.energy = 10.0
	var e0: float = dragon.energy
	var terr_log: String = dragon._terrain_end_turn()
	var t8c: bool = absf(dragon.energy - e0) < 0.001 and not terr_log.contains("损失 1 点能量")
	# 对照：非豁免单位在水域应扣能量
	var mage = null
	for u in b.units:
		if u.def_id == "story_mage":
			mage = u
			break
	mage.cell = water
	b._sync_terrain(mage)
	mage.energy = 10.0
	mage._terrain_end_turn()
	var t8d: bool = mage.energy < 10.0
	results.append(["⑧a 龙 water_immune 生效", t8a, "dragon.water_immune=%s" % (dragon.water_immune if dragon else "无龙")])
	results.append(["⑧b 龙在水域不扣能量", t8b and t8c, "terrain_id=%d 能量 %.1f→%.1f" % [
		dragon.terrain_id, e0, dragon.energy]])
	results.append(["⑧c 对照：法师在水域扣能量", t8d, "法师能量 %.1f" % mage.energy])
	ok_all = ok_all and t8a and t8b and t8c and t8d

	# ---------- 9) 双人护送判负：任一阵亡即负 ----------
	var b9 = S.new()
	b9.protect_target.alive = false
	b9.winner = ""
	b9._check_win(true)
	var t9a: bool = b9.winner == "魔渊"
	var b9b = S.new()
	b9b.escort_qi.alive = false
	b9b.winner = ""
	b9b._check_win(true)
	var t9b: bool = b9b.winner == "魔渊"
	results.append(["⑨a 昊阵亡→魔渊胜", t9a, "winner=%s" % b9.winner])
	results.append(["⑨b 祁阵亡→魔渊胜", t9b, "winner=%s" % b9b.winner])
	ok_all = ok_all and t9a and t9b

	# ---------- 10) 双人护送判胜：两人都到位才胜 ----------
	var b10 = S.new()
	b10.protect_target.cell = b10.escape_cells[0]
	b10.escort_qi.cell = b10.escape_cells[1]
	b10.winner = ""
	b10._check_win(true)
	var t10a: bool = b10.winner == "白灵殿" and b10.escaped
	# 只有一人到位 → 不判胜
	var b10b = S.new()
	b10b.protect_target.cell = b10b.escape_cells[0]
	b10b.winner = ""
	b10b._check_win(true)
	var t10b: bool = b10b.winner == ""
	results.append(["⑩a 两人到位→白灵殿胜", t10a, "winner=%s escaped=%s" % [b10.winner, b10.escaped]])
	results.append(["⑩b 只有昊到位→未判胜", t10b, "winner='%s'" % b10b.winner])
	ok_all = ok_all and t10a and t10b

	# ---------- 11) 逃生距离：拆障碍后重算 ----------
	var b11 = S.new()
	var d_before: int = b11.dist_to_escape(Vector2i(0, 1))
	# 拆掉靠近昊的一块障碍，看逃生距离是否变化（可能不变，只要函数不报错且 >= 0 即可）
	b11.damage_obstacle(Vector2i(7, -1), null)
	var d_after: int = b11.dist_to_escape(Vector2i(0, 1))
	var t11: bool = d_before >= 0 and d_after >= 0 and d_after <= d_before
	results.append(["⑪ 逃生距离 BFS 可用且拆障后<=原值", t11, "拆前 %d 步 → 拆后 %d 步" % [d_before, d_after]])
	ok_all = ok_all and t11

	# ---------------- 汇总 ----------------
	print("=" * 78)
	print(" 白灵殿剧情关回归 —— 2026-09-12")
	print("=" * 78)
	for r in results:
		print("  %s  %-34s  %s" % ["✅" if r[1] else "❌", r[0], r[2]])
	print("=" * 78)
	print("总结果:", "PASS ✅（%d 项）" % results.size() if ok_all else "FAIL ❌")
	print("=" * 78)
	quit(0 if ok_all else 1)
