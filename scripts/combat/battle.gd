class_name Battle
extends RefCounted
## 战棋 · 战斗管理器（1V1，3×3 主区 + 左右出生格）
## 回合结构：每棋每回合 = 移动权 + 技能权（先移后放、各自可选；移过禁用位移技）
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

func human_cast(slot: int, enemy: BattleUnit = null) -> String:
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
	if is_dash(u, slot) and _h_moved:
		return "!已移动，本回合不能使用位移技能"
	var targets: Array = []
	if not self_skill(u, slot):
		if enemy == null or not (enemy in targets_in_range(u, slot)):
			return "!请选择射程内的敌人作为目标"
		targets = [enemy]
	var res: String = u.use_active(slot, {"targets": targets, "mode": "1v1"})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

func human_done() -> void:
	if _wait:
		_finish_human()

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
	if is_dash(u, slot) and moved:
		log.push_back("%s 已移动，本回合无法使用位移技【%s】" % [u.name, sk.display_name])
		return
	if not self_skill(u, slot):
		var legal := targets_in_range(u, slot)
		var valid: Array = []
		for t in targets:
			if t in legal:
				valid.append(t)
		if valid.is_empty():
			return
		targets = valid
	var res: String = u.use_active(slot, {"targets": targets, "mode": "1v1"})
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
