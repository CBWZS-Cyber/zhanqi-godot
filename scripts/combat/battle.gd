class_name Battle
extends RefCounted
## 战棋 · 战斗管理器（1V1，3×3 主区 + 左右出生格）
## 回合结构：每棋每回合 = 移动权 + 技能权（先移后放、各自可选；位移技不限制在未移动时使用）
## 驱动方式：
##   - run_step() 自动结算直到“轮到人类/分出胜负”，返回状态
##   - 人类回合：human_move(cell) → human_cast(slot, enemy) / human_done()
##   - AI 回合：BattleAI 自动决策（plan_move + plan_skill）
## simulate() = 全自动（测试用）

const SPAWN_RED := Vector2i(0, 2)
const SPAWN_BLUE := Vector2i(4, 2)
const MAX_ROUNDS := 80

var units: Array[BattleUnit] = []
var log: Array[String] = []
var round := 0
var winner := ""
var human_mode := false
var human_team := 0
var _hd: GDScript
var _se: GDScript
var _queue: Array = []
var _wait := false
var _cur: BattleUnit = null
var _h_moved := false

func _init(red_hero_id: String, blue_hero_id: String) -> void:
	_hd = load("res://scripts/combat/hero_defs.gd")
	_se = load("res://scripts/combat/skill_effects.gd")
	units = [_make(red_hero_id, 0, SPAWN_RED), _make(blue_hero_id, 1, SPAWN_BLUE)]
	log.push_back("对局开始：红方 %s（速%d）vs 蓝方 %s（速%d）" % [units[0].name, units[0].speed, units[1].name, units[1].speed])

func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	var u := BattleUnit.new(_hd.ALL[hero_id].duplicate(true))
	u.team = team
	u.cell = cell
	return u

## 全自动跑完整局（测试用）
func simulate() -> String:
	while winner == "" and round < MAX_ROUNDS:
		if run_step().has("over"):
			break
	return winner

## 步进：结算至“人类待操作”或“对局结束”。
func run_step() -> Dictionary:
	while winner == "" and round < MAX_ROUNDS:
		if _queue.is_empty():
			_start_round()
		var actor := _poll_next()
		if actor == null:
			_end_round()
			continue
		if human_mode and actor.team == human_team:
			_wait = true
			_h_moved = false
			_cur = actor
			return {"wait": actor}
		_turn_ai(actor)
		_check_win()   # 每次行动后立刻判胜负（避免“已全灭仍继续”）
	if winner == "":
		winner = "僵局（%d 回合超时）" % MAX_ROUNDS
		log.push_back("== %s ==" % winner)
	return {"over": winner}

func _start_round() -> void:
	round += 1
	log.push_back("—— 第 %d 回合 ——" % round)
	for u in units:
		var s: String = u.on_turn_start()
		if s != "":
			log.push_back(s)
	_queue = []
	for u in units:
		if u.alive:
			_queue.append(u)

func _poll_next() -> BattleUnit:
	if _queue.is_empty():
		return null
	var lst: Array = _se.speed_order(_queue)
	var actor: BattleUnit = lst[0]
	_queue.erase(actor)
	return actor

func _end_round() -> void:
	for u in units:
		var r: String = u.end_turn()
		if r != "":
			log.push_back(r)
	_check_win()

func _turn_ai(u: BattleUnit) -> void:
	if not u.alive:
		return
	if u.has_flag("stun"):
		log.push_back("%s 被眩晕，跳过本回合" % u.name)
		return
	if u.has_flag("sanity_break"):
		_crazy(u)
		return
	var moved := false
	var mv: Dictionary = BattleAI.plan_move(self, u)
	if mv.get("act", "") == "move":
		var cell: Vector2i = mv.get("cell", Vector2i.ZERO)
		if cell in move_cells_of(u):
			u.cell = cell
			moved = true
			log.push_back("%s 移动 → %s" % [u.name, cell])
	var sk: Dictionary = BattleAI.plan_skill(self, u, moved)
	if sk.get("act", "") == "skill":
		_exec_skill(u, int(sk.get("slot", 1)), sk.get("targets", []), moved)

func _crazy(u: BattleUnit) -> void:
	var all: Array = []
	for x in units:
		if x.alive:
			all.append(x)
	var slot := 1 + (randi() % 4)
	var res: String = u.use_active(slot, {"targets": all, "mode": "1v1"})
	log.push_back("【失控】%s 不受控制地释放技能：%s" % [u.name, res])

## =============== 人类操作接口 ===============
func waiting() -> bool:
	return _wait

func current() -> BattleUnit:
	return _cur

func human_moved() -> bool:
	return _h_moved

func human_move(cell: Vector2i) -> String:
	if not _wait or _cur == null:
		return "!当前不在你的回合"
	if _h_moved:
		return "!本回合已移动"
	if not (cell in move_cells_of(_cur)):
		return "!非法移动格"
	_cur.cell = cell
	_h_moved = true
	log.push_back("%s 移动 → %s" % [_cur.name, cell])
	return "%s 移动 → %s" % [_cur.name, cell]

func human_cast(slot: int, enemy: BattleUnit = null, landing := Vector2i(-1, -1)) -> String:
	if not _wait or _cur == null:
		return "!当前不在你的回合"
	var u := _cur
	var sk := u.get_skill(slot)
	if sk == null:
		return "!技能槽无效"
	if u.is_skill_lost(sk.id):
		return "!该技能已被掠夺/禁用"
	if u.has_flag("no_skill") or (slot == 4 and u.has_flag("no_ult")) or u.has_flag("no_damage"):
		return "!当前状态禁止使用技能"
	if sk.current_cd > 0:
		return "!技能冷却中"
	if u.energy < sk.energy_cost:
		return "!能量不足"
	var old := u.cell
	var dest := old
	var dd := dash_dist_of(u, slot)

	if is_dash(u, slot) and dd > 0:
		if is_charge(u, slot):
			if enemy == null:
				return "!冲刺技能需先选择方向上的敌人"
			dest = _charge_end_cell(u, enemy, dd)
		else:
			dest = landing if (landing in landable_cells(u, dd)) else _best_land_cell(u, enemy, dd)
	# 位移落点可达性预检：失败则不移动
	var rng := skill_range(u, slot)
	var can := true
	if not self_skill(u, slot):
		if land_aoe(u, slot):
			can = true
		elif enemy != null:
			can = _cell_dist(dest, enemy.cell) <= rng
		else:
			can = false
			for f in alive_enemies_of(u):
				if _cell_dist(dest, f.cell) <= rng:
					can = true
					break
	if not can:
		return "!位移后目标不在射程内（敌人太远，先靠近或换落点）"
	if dest != old:
		u.cell = dest
		log.push_back("%s %s至 %s" % [u.name, "冲刺" if is_charge(u, slot) else "跃迁", dest])
	# 目标
	var targets: Array = []
	if not self_skill(u, slot):
		if enemy != null:
			targets = [enemy]
		elif land_aoe(u, slot):
			targets = _enemies_within(u, 1)
		else:
			for f in alive_enemies_of(u):
				if _cell_dist(u.cell, f.cell) <= rng:
					targets.append(f)
					break
	var res: String = u.use_active(slot, {"targets": targets, "mode": "1v1"})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

func human_done() -> void:
	if _wait:
		_finish_human()

## =============== 真位移（落格） ===============
## 普通位移 = 跃迁：跳到 dash_dist 内任意合法空格（无视路径；落地格必须无阻挡/无单位）
## 冲刺（辛克莱等）= 朝目标方向逐格冲，停在被挡前一格 / 目标邻格 / 冲满
func dash_dist_of(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 0
	return int(skill_data(sk.id).get("dash_dist", 0))

func is_charge(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return str(skill_data(sk.id).get("ai", {}).get("dash_kind", "jump")) == "charge"

func land_aoe(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("land_aoe", false))

func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _cell_exists(cell: Vector2i) -> bool:
	if cell.x >= 1 and cell.x <= 3:
		return cell.y >= 1 and cell.y <= 3
	if cell.x == 0 or cell.x == 4:
		return cell.y == 2   # 两侧各 1 个出生格
	return false

func _grid_free(cell: Vector2i) -> bool:
	if not _cell_exists(cell):
		return false
	for x in units:
		if x.cell == cell:
			return false
	return true

## 跃迁可达格（距离<=dd 的合法空格，可含原地）
func landable_cells(u: BattleUnit, dd: int) -> Array:
	var out: Array = []
	for y in range(1, 4):
		for x in range(0, 5):
			var c := Vector2i(x, y)
			if c == u.cell:
				out.append(c)
				continue
			if _grid_free(c) and absi(c.x - u.cell.x) + absi(c.y - u.cell.y) <= dd:
				out.append(c)
	return out

func _best_land_cell(u: BattleUnit, enemy: BattleUnit, dd: int) -> Vector2i:
	var cells := landable_cells(u, dd)
	if enemy == null or cells.is_empty():
		return u.cell
	var best := u.cell
	var bd := 9999
	for c in cells:
		var cc: Vector2i = c
		var d := absi(enemy.cell.x - cc.x) + absi(enemy.cell.y - cc.y)
		if d < bd:
			bd = d
			best = cc
	return best

## 冲刺：朝敌逐格推进至邻格 / 被挡前一格 / 冲满步数
func _charge_end_cell(u: BattleUnit, enemy: BattleUnit, dd: int) -> Vector2i:
	var cell := u.cell
	for i in range(maxi(1, dd)):
		if absi(enemy.cell.x - cell.x) + absi(enemy.cell.y - cell.y) <= 1:
			break
		var step := Vector2i.ZERO
		if enemy.cell.x != cell.x:
			step = Vector2i(1 if enemy.cell.x > cell.x else -1, 0)
		elif enemy.cell.y != cell.y:
			step = Vector2i(0, 1 if enemy.cell.y > cell.y else -1)
		var nxt := cell + step
		if not _grid_free(nxt):
			break
		cell = nxt
	return cell

func _enemies_within(u: BattleUnit, r: int) -> Array:
	var out: Array = []
	for f in alive_enemies_of(u):
		if dist(u, f) <= r:
			out.append(f)
	return out

func _finish_human() -> void:
	_wait = false
	_cur = null

## =============== 查询（AI 与 UI 共用） ===============
func alive_enemies_of(u: BattleUnit) -> Array:
	var out: Array = []
	for x in units:
		if x.alive and x != u and x.team != u.team:
			out.append(x)
	return out

func dist(a: BattleUnit, b: BattleUnit) -> int:
	return absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y)

func base_usable(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null or u.is_skill_lost(sk.id):
		return false
	if u.has_flag("no_skill") or u.has_flag("no_damage"):
		return false
	if slot == 4 and u.has_flag("no_ult"):
		return false
	if sk.current_cd > 0 or u.energy < sk.energy_cost:
		return false
	return true

func skill_data(id: String) -> Dictionary:
	return _se.DATA.get(id, {}) as Dictionary

func skill_range(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 0
	return int(skill_data(sk.id).get("range", 1))

func is_dash(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("dash", false))

func self_skill(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("self_buff", false))

func targets_in_range(u: BattleUnit, slot: int) -> Array:
	var r := skill_range(u, slot)
	var out: Array = []
	for f in alive_enemies_of(u):
		if dist(u, f) <= r:
			out.append(f)
	return out

func move_cells_of(u: BattleUnit) -> Array:
	var out: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var d: Vector2i = dv
		var c := u.cell + d
		if c.x < 0 or c.x > 4 or c.y < 1 or c.y > 3:
			continue
		var occ := false
		for x in units:
			if x.alive and x != u and x.cell == c:
				occ = true
				break
		if not occ:
			out.append(c)
	return out

func _exec_skill(u: BattleUnit, slot: int, targets: Array, moved: bool) -> void:
	var sk := u.get_skill(slot)
	if sk == null:
		return
	var old := u.cell
	var dd := dash_dist_of(u, slot)
	if is_dash(u, slot) and dd > 0 and not targets.is_empty():
		var t0: BattleUnit = targets[0]
		if is_charge(u, slot):
			u.cell = _charge_end_cell(u, t0, dd)
		else:
			u.cell = _best_land_cell(u, t0, dd)
		if u.cell != old:
			log.push_back("%s 位移 → %s" % [u.name, u.cell])
	# 位移后重算本技目标；打不到就回滚位置放弃
	var final_targets: Array = []
	if not self_skill(u, slot):
		if land_aoe(u, slot):
			final_targets = _enemies_within(u, 1)
		else:
			for t in targets:
				if t in targets_in_range(u, slot):
					final_targets.append(t)
			if final_targets.is_empty():
				final_targets = targets_in_range(u, slot)
		if final_targets.is_empty():
			if u.cell != old:
				u.cell = old
			return
	if final_targets.is_empty() and not self_skill(u, slot):
		return
	var res: String = u.use_active(slot, {"targets": final_targets, "mode": "1v1"})
	if res != "":
		log.push_back(res)

func _check_win() -> void:
	if winner != "":
		return
	var ra := false
	var ba := false
	for u in units:
		if u.alive:
			if u.team == 0:
				ra = true
			else:
				ba = true
	if not ra and not ba:
		winner = "平局"
	elif not ra:
		winner = "蓝方"
	elif not ba:
		winner = "红方"
	if winner != "":
		log.push_back("== 胜者：%s（第 %d 回合）==" % [winner, round])

func result_text() -> String:
	return "\n".join(log)
