extends SceneTree
## 剧情关（骑士线第一关·白灵殿）无头冒烟测试 —— 2026-09-13 建立
## 用法：Godot --headless --path 工程 -s res://tests/story_battle_smoke.gd
## 覆盖：地图加载 / 单位生成与阵营 / 逃生区 / 双人护送目标 / 到逃生区步数 /
##       地形接线（棋盘 → terrain_id）/ 回合驱动（AI 打满全场不报错）/ 胜负收敛。
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

func _initialize() -> void:
	await process_frame
	var BS = load("res://scripts/combat/battle_story.gd")
	print("== 剧情关冒烟 ==")

	# ---------- 1) 构建与地图 ----------
	var b = BS.new()
	ck(b != null, "BattleStory 可实例化")
	if b == null:
		print("== 冒烟结果: PASS %d / FAIL %d ==" % [_pass, _fail])
		quit(1)
		return
	ck(b.cells.size() > 0, "白灵殿地图已加载（cells=%d 格）" % b.cells.size())
	ck(b.escape_cells.size() == 4, "逃生区 = 4 格（实际 %d）" % b.escape_cells.size())
	ck(b._board != null, "BFS 用格图 _board 已构建")

	# ---------- 1b) 地形接线（2026-09-13 修复点，此前全程空转）----------
	# 基类 battle_base 的地形效果全依赖 board；不接线则 terrain_id 恒为 0，
	# 森林免伤 / 水域耗能 / 移出代价 / 冰面滑行全部失效。
	ck(b.board != null, "基类 board 已接线（地形系统生效前提）")
	if b.board != null:
		ck(b.board == b._board, "board 与 _board 是同一格图（移动/可达/地形一致）")
		var forest_cell := Vector2i(-999, -999)
		var water_cell := Vector2i(-999, -999)
		for k in b.cells:
			var tid: int = int(b.cells[k])
			if tid == 3 and forest_cell.x == -999:
				forest_cell = b._v2i(k)
			elif tid == 5 and water_cell.x == -999:
				water_cell = b._v2i(k)
		# 森林：格图里必须能读出 3
		if forest_cell.x != -999:
			ck(b.board.terrain_at(forest_cell) == 3,
				"格图能读出森林格 %s 的地形 id（=3）" % forest_cell)
			# 站在森林上 → 基类 _sync_terrain 应把 terrain_id 同步为 3
			var probe = b.units[0]
			var keep: Vector2i = probe.cell
			b._place(probe, forest_cell)
			ck(probe.terrain_id == 3,
				"_place() 后 terrain_id 同步为 3（实际 %d）" % probe.terrain_id)
			# 森林免伤 20%：受击倍率 0.8
			ck(absf(Terrain.damage_taken_mult(probe.terrain_id) - 0.8) < 0.001,
				"森林受击倍率 = 0.8（免伤 20%）")
			# 森林移出代价 1
			ck(probe.exit_energy_cost() == 1,
				"森林移出耗能 = 1（实际 %d）" % probe.exit_energy_cost())
			b._place(probe, keep)
			ck(probe.terrain_id == int(b.cells.get("%d,%d" % [keep.x, keep.y], 0)),
				"移回原地后 terrain_id 正确回落（实际 %d）" % probe.terrain_id)
		else:
			ck(false, "地图里存在森林格（未找到）")
		if water_cell.x != -999:
			ck(b.board.terrain_at(water_cell) == 5,
				"格图能读出水域格 %s 的地形 id（=5）" % water_cell)
	# 出生即同步：所有单位 terrain_id 应等于脚下格地形
	var spawn_sync := true
	for u in b.units:
		if u.terrain_id != b.board.terrain_at(u.cell):
			spawn_sync = false
			break
	ck(spawn_sync, "所有单位出生时 terrain_id 已同步")

	# ---------- 2) 单位与阵营 ----------
	var blue: Array = b.units_of_team(1)
	var red: Array = b.units_of_team(0)
	ck(blue.size() == 10, "白灵殿（蓝）10 单位（实际 %d）" % blue.size())
	ck(red.size() == 7, "魔渊（红）7 单位（实际 %d）" % red.size())
	ck(b.units.size() == 17, "总单位 17（实际 %d）" % b.units.size())

	# ---------- 3) 双人护送目标 ----------
	ck(b.protect_target != null, "护送主目标「昊」已登记")
	ck(b.escort_qi != null, "护送目标「祁」已登记")
	ck(b.protect_target != null and b.protect_target.team == 1, "昊属白灵殿（蓝）")
	ck(b.escort_qi != null and b.escort_qi.team == 1, "祁属白灵殿（蓝）")

	# ---------- 4) 到逃生区步数（核对 README「零之零」表）----------
	if b.protect_target != null:
		var d_hao: int = b.dist_to_escape(b.protect_target.cell)
		print("    昊 起点 %s → 距逃生区 %d 步" % [b.protect_target.cell, d_hao])
		ck(d_hao > 0, "昊 到逃生区步数 > 0（= %d）" % d_hao)
	if b.escort_qi != null:
		var d_qi: int = b.dist_to_escape(b.escort_qi.cell)
		print("    祁 起点 %s → 距逃生区 %d 步" % [b.escort_qi.cell, d_qi])
		ck(d_qi > 0, "祁 到逃生区步数 > 0（= %d）" % d_qi)
	var d_red_best := 9999
	var red_count := 0
	for u in red:
		red_count += 1
		var d: int = b.dist_to_escape(u.cell)
		if d < d_red_best:
			d_red_best = d
	print("    红方 %d 个单位，最近者距逃生区 %d 步" % [red_count, d_red_best])
	ck(d_red_best < 9999, "红方最近单位到逃生区 %d 步" % d_red_best)

	# ---------- 5) 玩家操作接口可用 ----------
	ck(b.move_cells_of(b.protect_target).size() > 0, "昊 有可移动格（每回合 1 步）")

	# ---------- 6) 回合驱动：玩家放着不动，让 AI 打满全场 ----------
	var steps := 0
	var res: Dictionary = {}
	while steps < 400:
		steps += 1
		res = b.run_step()
		if res.has("wait"):
			b.human_done()      # 玩家放弃本回合（不移动、不放技能）
			continue
		break
	ck(b.winner != "", "对局收敛出胜负（winner=「%s」，round=%d，步进 %d 次）" % [b.winner, b.round, steps])
	ck(b.log.size() > 0, "战报有内容（%d 条）" % b.log.size())
	ck(b.result_text() != null, "result_text() 可调用")
	print("    结局标题：%s" % b.result_title())

	# ---------- 7) 逃跑路线可解析（BFS 可达性）----------
	var reach := 0
	for e in b.escape_cells:
		if b._terrain_ok(e):
			reach += 1
	ck(reach == b.escape_cells.size(), "逃生区 %d/%d 格在地图上可通行" % [reach, b.escape_cells.size()])

	print("== 冒烟结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
