class_name Battle
extends RefCounted
## 战棋 · 战斗管理器（1V1，3×3 主区 + 左右出生格）
## 回合结构（用户规则 2026-09-04）：
##   每棋每回合 = 移动权 + 技能权；行动时先移动再放技能；两者都可跳过；
##   一旦移动，本回合禁用位移技能（突进/冲刺/传送/位移后攻击）。
## 回合流程：round 开始全体 on_turn_start → 动态行动序（实时速度）逐棋两阶段决策 → 全场 end_turn。

const SPAWN_RED := Vector2i(0, 2)
const SPAWN_BLUE := Vector2i(4, 2)
const MAX_ROUNDS := 80

var units: Array[BattleUnit] = []
var log: Array[String] = []
var round := 0
var winner := ""
var _hd: GDScript
var _se: GDScript

func _init(red_hero_id: String, blue_hero_id: String) -> void:
	_hd = load("res://scripts/combat/hero_defs.gd")
	_se = load("res://scripts/combat/skill_effects.gd")
	var a := _make(red_hero_id, 0, SPAWN_RED)
	var b := _make(blue_hero_id, 1, SPAWN_BLUE)
	units = [a, b]
	log.push_back("对局开始：红方 %s（速%d）vs 蓝方 %s（速%d）" % [a.name, a.speed, b.name, b.speed])

func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	var u := BattleUnit.new(_hd.ALL[hero_id].duplicate(true))
	u.team = team
	u.cell = cell
	return u

func simulate(round_hook: Callable = Callable()) -> String:
	while winner == "" and round < MAX_ROUNDS:
		round += 1
		if not round_hook.is_null():
			round_hook.call(round)
		log.push_back("—— 第 %d 回合 ——" % round)
		for u in units:
			var s: String = u.on_turn_start()
			if s != "":
				log.push_back(s)
		var remaining: Array = []
		for u in units:
			if u.alive:
				remaining.append(u)
		while not remaining.is_empty() and winner == "":
			var actor: BattleUnit = _se.next_actor(remaining)
			remaining.erase(actor)
			_take_turn(actor)
		for u in units:
			var r: String = u.end_turn()
			if r != "":
				log.push_back(r)
		_check_win()
	if winner == "":
		winner = "僵局（%d 回合超时）" % MAX_ROUNDS
		log.push_back("== %s ==" % winner)
	return winner

## 一名棋子的完整回合：移动 → 技能（可各自跳过）
func _take_turn(u: BattleUnit) -> void:
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
	# 移动了没放技能 / 放完了都合法结束；无任何操作 = 待机（不刷日志）

func _exec_skill(u: BattleUnit, slot: int, targets: Array, moved: bool) -> void:
	var sk := u.get_skill(slot)
	if sk == null:
		return
	if is_dash(u, slot) and moved:
		log.push_back("%s 已移动，本回合无法使用位移技【%s】" % [u.name, sk.display_name])
		return
	# 目标护栏：只能打射程内敌方；自身类技能不需要目标
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

## 辛克莱失控：随机放技能，目标敌我不分
func _crazy(u: BattleUnit) -> void:
	var all: Array = []
	for x in units:
		if x.alive:
			all.append(x)
	var slot := 1 + (randi() % 4)
	var res: String = u.use_active(slot, {"targets": all, "mode": "1v1"})
	log.push_back("【失控】%s 不受控制地释放技能：%s" % [u.name, res])

## ---- AI/执行共享查询 ----
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
