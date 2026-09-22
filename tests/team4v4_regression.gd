extends SceneTree
## 战棋 · 4V4 战斗层回归测试（BattleTeam）
## 用法：Godot --headless --path 工程 -s res://tests/team4v4_regression.gd
## 覆盖：8 棋出生/阵营、速度实时排序行动、人类操作、胜负判定、全自动多局模拟。
## 全部通过 exit 0，有失败 exit 1。

var _passes := 0
var _fails := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  ✓ ", name)
	else:
		_fails += 1
		printerr("  ✗ FAIL: ", name)

var BT
var HD
var SE

## 测试用红/蓝阵容（避免同一英雄同场两队，便于断言归属）
const RED_A := ["crystal_dragon", "xie_shen", "jianwu", "he_zhigao"]
const BLUE_A := ["zhuilie", "xian_zun", "yao_shi", "gu_lang"]
const RED_B := ["guang_yu", "xin_kelai", "xian_zun", "yao_shi"]
const BLUE_B := ["crystal_dragon", "jianwu", "gu_lang", "zhuilie"]
const RED_C := ["ling_xu", "he_zhigao", "xie_shen", "crystal_dragon"]
const BLUE_C := ["xin_kelai", "xian_zun", "guang_yu", "yao_shi"]

func _initialize() -> void:
	BT = load("res://scripts/combat/battle_team.gd")
	HD = load("res://scripts/combat/hero_defs.gd")
	SE = load("res://scripts/combat/skill_effects.gd")
	var t0 := Time.get_ticks_msec()
	_test_spawn_and_sides()
	_test_move_grid()
	_test_speed_order()
	_test_human_ops()
	_test_win()
	_test_auto_matches()
	var dt := Time.get_ticks_msec() - t0
	print("== 4V4 回归结果: PASS %d / FAIL %d（%d ms）==" % [_passes, _fails, dt])
	quit(1 if _fails > 0 else 0)

## ---------- A. 出生与阵营 ----------
func _test_spawn_and_sides() -> void:
	print("[A] 出生与阵营")
	var b = BT.new(RED_A, BLUE_A)
	ck(b.units.size() == 8, "共 8 棋")
	var rc := 0
	var bc := 0
	for u in b.units:
		if u.team == 0:
			rc += 1
		else:
			bc += 1
	ck(rc == 4 and bc == 4, "红 4 / 蓝 4")
	ck(b.SPAWN_RED.size() == 4 and b.SPAWN_BLUE.size() == 4, "两翼各有 4 个出生格")
	# 每方出生格坐标归属
	for u in b.units:
		if u.team == 0:
			ck(u.cell.x == 0 and u.cell.y >= 3 and u.cell.y <= 6, "%s 在红翼出生 %s" % [u.name, u.cell])
		else:
			ck(u.cell.x == 9 and u.cell.y >= 3 and u.cell.y <= 6, "%s 在蓝翼出生 %s" % [u.name, u.cell])
	ck(b.log.size() > 0 and "4V4 对局开始" in b.log[0], "开局日志含双方阵容")

## ---------- B. 网格与查询 ----------
func _test_move_grid() -> void:
	print("[B] 移动格与目标查询")
	var b = BT.new(RED_A, BLUE_A)
	var u0: BattleUnit = b.units[0]          # crystal_dragon 位于 (0,3)
	ck(u0.cell == Vector2i(0, 3), "红 0 号出生 (0,3)")
	var mvs: Array = b.move_cells_of(u0)
	ck(not mvs.is_empty(), "有可移动格")
	for c in mvs:
		var cc: Vector2i = c
		ck(cc.x >= 0 and cc.x <= 9 and cc.y >= 1 and cc.y <= 8, "移动格不越界 %s" % cc)
	# (0,4) 被己方占 → 不是可动格；(9,3) 被敌方占 → 也不可重叠
	ck(not (Vector2i(0, 4) in mvs), "己方占格不可走")
	ck(not (Vector2i(9, 3) in mvs), "敌方占格不可走")
	# 敌人列表：红方视角 4 个敌人
	ck(b.alive_enemies_of(u0).size() == 4, "红方视角敌人 = 4")
	# 距离判定
	var blue0: BattleUnit = b.units[1]
	ck(b.dist(u0, blue0) == 9, "翼间距离 9")
	# targets_in_range：出生相隔 9 格，技能 range<=3 时无目标
	ck(b.targets_in_range(u0, 1).is_empty(), "出生期射程内无敌人")

## ---------- C. 速度实时排序行动 ----------
func _test_speed_order() -> void:
	print("[C] 行动顺序按速度")
	var b = BT.new(RED_A, BLUE_A)      # 全场最高速 crystal_dragon(175)
	b.human_mode = true
	b.human_teams = [0, 1]             # 双方都是人类 → run_step 停在每个行动者
	var got: Array = []
	for i in range(8):
		var st: Dictionary = b.run_step()
		ck(st.has("wait"), "第 %d 次停在人类行动" % (i + 1))
		if st.has("wait"):
			got.append(b.current())
		b.human_done()
	ck(got.size() == 8, "完整收集 8 个行动者")
	var expect: Array = SE.speed_order(b.units)
	var same := true
	if got.size() == expect.size():
		for i in range(expect.size()):
			if got[i] != expect[i]:
				same = false
				break
	else:
		same = false
	ck(same, "行动顺序 = 速度降序（高速先动）")

## ---------- D. 人类操作 ----------
func _test_human_ops() -> void:
	print("[D] 人类移动与施放")
	# 场景1：龙王(175) 全场最快先手，前方无敌人，先测移动
	var b = BT.new(RED_A, BLUE_A)
	b.human_mode = true
	b.human_team = 0
	var st: Dictionary = b.run_step()
	ck(st.has("wait") and b.current().def_id == "crystal_dragon", "红方首动 = 龙王")
	var mvs: Array = b.move_cells_of(b.current())
	var r1: String = b.human_move(mvs[0] as Vector2i)
	ck(not r1.begins_with("!"), "人类移动成功：%s" % r1)
	ck(b.human_moved(), "已移动标记")
	var r2: String = b.human_move(mvs[0] as Vector2i)
	ck(r2.begins_with("!"), "同回合不可二次移动")
	# 场景2：把蓝方单位搬到龙王身边，测技能施放
	var b2 = BT.new(RED_A, BLUE_A)
	b2.human_mode = true
	b2.human_team = 0
	var _s2: Dictionary = b2.run_step()
	var dragon: BattleUnit = b2.current()
	var prey: BattleUnit = b2.units[1]     # zhuilie（蓝 0 号）
	prey.cell = Vector2i(1, 3)             # 搬到龙王(0,3) 旁边
	prey.armor = 0                         # 追猎默认甲3会吃满3点普伤，置0专注验证施放链路
	var ts: Array = b2.targets_in_range(dragon, 1)
	ck(ts.size() == 1 and ts[0] == prey, "射程内恰好该敌")
	var hp0 := prey.hp
	var res: String = b2.human_cast(1, prey)   # 凝元晶为刃 3 伤（耗1晶）
	ck(not res.begins_with("!"), "人类施放成功：%s" % res)
	ck(prey.hp == hp0 - 3, "龙王命中：3 真伤落地")
	ck(dragon.counter("元晶") == 2, "元晶 3→2（耗1）")

## ---------- E. 胜负判定 ----------
func _test_win() -> void:
	print("[E] 胜负判定")
	var b = BT.new(RED_A, BLUE_A)
	for u in b.units:
		if u.team == 1:
			u.lose_hp(9999)
	var st: Dictionary = b.run_step()
	ck(st.has("over") and str(st["over"]) == "红方", "蓝方全灭 → 红方胜")
	var b2 = BT.new(RED_A, BLUE_A)
	for u in b2.units:
		if u.team == 0:
			u.lose_hp(9999)
	var st2: Dictionary = b2.run_step()
	ck(st2.has("over") and str(st2["over"]) == "蓝方", "红方全灭 → 蓝方胜")

## ---------- F. 全自动模拟（多阵容） ----------
func _test_auto_matches() -> void:
	print("[F] 全自动多局模拟")
	for i in range(3):
		var reds: Array = [RED_A, RED_B, RED_C][i]
		var blues: Array = [BLUE_A, BLUE_B, BLUE_C][i]
		var b = BT.new(reds, blues)
		var w: String = b.simulate()
		ck(w != "", "对局 %d 有结果" % (i + 1))
		ck(w in ["红方", "蓝方", "平局"] or w.begins_with("僵局"), "对局 %d 结果合法：%s" % [i + 1, w])
		ck(b.log.size() > 5, "对局 %d 日志完整" % (i + 1))
		print("    模拟 %d → 胜者：%s（%d 回合）" % [i + 1, w, b.round])
