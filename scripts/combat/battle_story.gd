class_name BattleStory
extends BattleBase
## 骑士线第一关 · 白灵殿 剧情战斗管理器（7V10 护送关）
##
## 阵营：红方 = 魔渊（team 0，AI 控制，7 单位）／蓝方 = 白灵殿（team 1，玩家控制，10 单位）
## 胜利：把「昊」护送到地图右侧逃生区（x >= ESCAPE_X 的可通行格）
## 失败：昊阵亡 / 蓝方全灭 / 超过 MAX_ROUNDS 回合仍未脱身
## 歼灭红方同样判胜（打得过也可以硬推）
##
## 与 4V4（battle_team）的差异：
##   1. 棋盘来自 maps/白灵殿.json（自由拼格 296 格，含地形障碍），不再是 8×8 标准盘；
##   2. 每回合移动 = MOVE_STEPS 步 × 每步 8 方向 1 格（BFS 绕障碍），昊因携带白灵核心只有 1 步；
##   3. 无星星得分制；胜负改护送判定；
##   4. 红方 AI 追加「追杀昊 / 奔袭逃生区拦截」的目标逻辑（_hunt_move）。

const MAP_PATH := "res://maps/白灵殿.json"
const TEAM_RED := 0      # 魔渊
const TEAM_BLUE := 1     # 白灵殿
const ESCAPE_X := 16     # 逃生区：x >= 16 的可通行格（昊踏入即胜）
const DEFAULT_MOVE_STEPS := 2   # 默认每回合移动步数（用户 2026-09-10 定：每回合两次，每次 8 方向 1 格）
const BLOCK_TYPES := [1, 2]     # 地图地形：1 可破坏障碍 / 2 不可破坏障碍 → 均不可通行

## 昊的「不受控前进」：每 HAO_AUTO_EVERY 个回合末，自动朝 HAO_AUTO_DIR 挪 1 格（2026-09-10 用户要求加难度）
## 设计意图：玩家管不住昊的腿 —— 他会自己往东（逃生区方向）走，容易跑在护卫前面落单，
##           而他只有 0 甲 5 血，一旦被魔渊贴上就极易暴毙。
## 调参：改成 3 = 每 3 回合末走一次；改成 0 = 关闭自动移动；方向改 Vector2i(-1,0) 即向西倒退。
const HAO_AUTO_EVERY := 2
const HAO_AUTO_DIR := Vector2i(1, 0)   # 向东（x+1），即逃生区方向

var max_rounds_limit := 60
var map_name := "白灵殿"
var cells: Dictionary = {}          # "x,y" -> type(int)
var terrain_types: Dictionary = {}  # type(int) -> {name,color}
var escape_cells: Array = []        # 逃生区格
var _dist_escape: Dictionary = {}   # "x,y" -> 到最近逃生格的步数（多源 BFS，开局算一次）
var _board: GridBoard = null
var protect_target: BattleUnit = null   # 昊（被护送者）
var escaped := false

func _init() -> void:
	_hd = load("res://scripts/combat/hero_defs.gd")
	_se = load("res://scripts/combat/skill_effects.gd")
	rng.randomize()
	max_rounds = max_rounds_limit
	child_limit = 0
	human_mode = true
	human_teams = [TEAM_BLUE]     # 玩家只控制蓝方
	human_team = TEAM_BLUE
	if not _load_map():
		log.push_back("!! 地图加载失败：%s" % MAP_PATH)
		return
	_build_board()
	_spawn_units()
	_compute_escape_dist()
	log.push_back("骑士线第一关 · %s：护送【昊】抵达地图右侧逃生区（x ≥ %d）" % [map_name, ESCAPE_X])
	log.push_back("魔渊 %d units vs 白灵殿 %d units" % [_count_team(TEAM_RED), _count_team(TEAM_BLUE)])

# ---------------------------------------------------------------- 地图
func _load_map() -> bool:
	if not FileAccess.file_exists(MAP_PATH):
		return false
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var m: Dictionary = parsed
	map_name = str(m.get("name", "白灵殿"))
	cells = {}
	for c in m.get("cells", []):
		var cd: Dictionary = c
		cells["%d,%d" % [int(cd.get("x", 0)), int(cd.get("y", 0))]] = int(cd.get("type", 0))
	terrain_types = {}
	for t in m.get("types", []):
		var td: Dictionary = t
		terrain_types[int(td.get("id", 0))] = td
	escape_cells = []
	for k in cells:
		if int(_v2i(k).x) >= ESCAPE_X and not _is_block(int(cells[k])):
			escape_cells.append(_v2i(k))
	return not cells.is_empty()

func _build_board() -> void:
	_board = GridBoard.new([], true)
	for k in cells:
		var c := _v2i(k)
		_board.add_cell(c)
		if _is_block(int(cells[k])):
			_board.set_obstacle(c, true)

## 多源 BFS：每格到最近逃生格的步数（地形障碍不可通行，忽略单位）
func _compute_escape_dist() -> void:
	_dist_escape = {}
	if escape_cells.is_empty() or _board == null:
		return
	var frontier: Array = []
	for c in escape_cells:
		var cc: Vector2i = c
		_dist_escape[_key(cc)] = 0
		frontier.append(cc)
	var step := 0
	while not frontier.is_empty():
		step += 1
		var nxt: Array = []
		for c in frontier:
			var cur: Vector2i = c
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var nb: Vector2i = cur + (d as Vector2i)
				if not _terrain_ok(nb) or _dist_escape.has(_key(nb)):
					continue
				_dist_escape[_key(nb)] = step
				nxt.append(nb)
		frontier = nxt

func _spawn_units() -> void:
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	for sp in (parsed as Dictionary).get("spawns", []):
		var sd: Dictionary = sp
		var unit_name := str(sd.get("unit", ""))
		var def_id := StoryDefs.def_of(unit_name)
		if def_id == "":
			log.push_back("!! 未登记的剧情单位：%s" % unit_name)
			continue
		var team := TEAM_RED if str(sd.get("team", "blue")) == "red" else TEAM_BLUE
		var cell := Vector2i(int(sd.get("x", 0)), int(sd.get("y", 0)))
		if not _terrain_ok(cell):
			cell = _nearest_free_cell(cell)
		var u := StoryDefs.make(def_id, team, cell, unit_name)
		if u == null:
			continue
		u.rng = rng
		units.append(u)
		if def_id == "story_hao":
			protect_target = u
		log.push_back("· %s〔%s〕出生 %s（速 %d，移动 %d 步）" % [
			u.name, "魔渊" if team == TEAM_RED else "白灵殿", cell, u.effective_speed(), steps_of(u)])

func _count_team(team: int) -> int:
	var n := 0
	for u in units:
		if u.team == team:
			n += 1
	return n

func units_of_team(team: int) -> Array:
	var out: Array = []
	for u in units:
		if u.team == team:
			out.append(u)
	return out

# ---------------------------------------------------------------- 格子工具
func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _v2i(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1]))

func _is_block(t: int) -> bool:
	return BLOCK_TYPES.has(t)

## 地形层面可站立（在地图内且非障碍）
func _terrain_ok(c: Vector2i) -> bool:
	return cells.has(_key(c)) and not _is_block(int(cells[_key(c)]))

func _nearest_free_cell(from: Vector2i) -> Vector2i:
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := from + Vector2i(dx, dy)
				if _terrain_ok(c):
					return c
	return from

## 战斗层接口：格子是否存在（供基类 _grid_free / 落点判定）
func _cell_exists(cell: Vector2i) -> bool:
	return _terrain_ok(cell)

func terrain_at(cell: Vector2i) -> int:
	return int(cells.get(_key(cell), -1))

func is_escape_cell(cell: Vector2i) -> bool:
	return escape_cells.has(cell)

## 到最近逃生格还剩几步（-1 = 不可达）
func dist_to_escape(cell: Vector2i) -> int:
	return int(_dist_escape.get(_key(cell), -1))

## 该单位每回合可走几步（昊携带白灵核心 = 1 步）
func steps_of(u: BattleUnit) -> int:
	if u == null:
		return DEFAULT_MOVE_STEPS
	var d: Dictionary = StoryDefs.ALL.get(u.def_id, {}) as Dictionary
	return int(d.get("move_steps", DEFAULT_MOVE_STEPS))

# ---------------------------------------------------------------- 移动
## 8 方向 BFS：steps 步内可达格（绕地形障碍、不可穿越其他单位）
func move_cells_of(u: BattleUnit) -> Array:
	var out: Array = []
	if u == null or _board == null:
		return out
	var steps := steps_of(u)
	for x in units:
		if x.alive and x != u and not x.non_solid:
			_board.set_obstacle(x.cell, true)
	var r: Dictionary = _board.reachable(u.cell, steps)
	for x in units:
		if x.alive and x != u and not x.non_solid:
			_board.set_obstacle(x.cell, false)
	for k in r:
		var c := _v2i(str(k))
		if c != u.cell:
			out.append(c)
	return out

func landable_cells(_u: BattleUnit, _dd: int) -> Array:
	return []   # 剧情兵种无位移技

# ---------------------------------------------------------------- 回合流程
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
	# 魔渊集火目标锁定「昊」：AI 在射程内会优先打他
	if protect_target != null and protect_target.alive:
		llm_tactics = {"focus": _idx_of(protect_target)}
	else:
		llm_tactics = {}

## 步进：结算到「轮到玩家」或「分出胜负」
func run_step() -> Dictionary:
	while winner == "" and round < max_rounds:
		if _queue.is_empty():
			if round > 0:
				_end_round()
				if winner != "":
					break
			_start_round()
			if _queue.is_empty():
				break
		var actor := _poll_next()
		if actor == null:
			continue
		if not actor.alive:
			continue
		if actor.has_flag("stun"):
			log.push_back("%s 被眩晕，跳过本回合" % actor.name)
			continue
		# 宵·不灭：生命低于 50% 时无法行动
		if actor.def_id == "story_xiao" and actor.hp <= actor.max_hp * 0.5:
			log.push_back("【不灭】%s 生命低于五成，无法行动" % actor.name)
			continue
		if _is_human_side(actor):
			_wait = true
			_h_moved = false
			_cur = actor
			return {"wait": actor}
		_turn_ai(actor)
		_flush_guard_notes()
		_check_win()
	if winner == "":
		winner = "魔渊"
		log.push_back("== %d 回合过去，昊仍未脱身——魔渊得手 ==" % max_rounds)
	return {"over": winner}

func _end_round() -> void:
	for u in units:
		var r: String = u.end_turn()
		if r != "":
			log.push_back(r)
	_flush_guard_notes()
	_tick_fear()
	_hao_auto_advance()
	_flush_guard_notes()
	_check_win()

## 昊在回合末被白灵核心牵引，自动朝 HAO_AUTO_DIR 挪 1 格（玩家无法阻止）
## 阻挡规则：地形不可通行 / 该格站着别的单位 → 原地不动并写战报
func _hao_auto_advance() -> void:
	if HAO_AUTO_EVERY <= 0 or round % HAO_AUTO_EVERY != 0:
		return
	var h := protect_target
	if h == null or not h.alive:
		return
	var dest: Vector2i = h.cell + HAO_AUTO_DIR
	if not _terrain_ok(dest):
		log.push_back("【失控】%s 被核心牵引想往东走，但 %s 是障碍，原地不动" % [h.name, dest])
		return
	var blocker := _unit_at(dest)
	if blocker != null:
		log.push_back("【失控】%s 被核心牵引想往东走，但被 %s 挡住" % [h.name, blocker.name])
		return
	h.cell = dest
	var d := dist_to_escape(dest)
	log.push_back("【失控】回合末：%s 不由自主向东挪了 1 格 → %s（距逃生区 %s）" % [
		h.name, dest, ("%d 步" % d) if d > 0 else "—"])
	_check_win()

func _unit_at(cell: Vector2i) -> BattleUnit:
	for u in units:
		if u.alive and u.cell == cell:
			return u
	return null

## 大长老·泉涌等「抵消致命伤」产生的日志
func _flush_guard_notes() -> void:
	for u in units:
		if u.guard_note != "":
			log.push_back(u.guard_note)
			u.guard_note = ""

## 畏惧：每回合末 -1 层（每层速度 -10）
func _tick_fear() -> void:
	for u in units:
		var n := u.status_stacks("fear")
		if n <= 0:
			continue
		u.set_status("fear", n - 1)
		u.set_speed_mod_src("畏惧", -10 * u.status_stacks("fear"))
		log.push_back("%s【畏惧】衰减 %d → %d 层" % [u.name, n, u.status_stacks("fear")])

# ---------------------------------------------------------------- AI（魔渊）
func _turn_ai(u: BattleUnit) -> void:
	if not u.alive:
		return
	var moved := false
	if u.team == TEAM_RED:
		moved = _hunt_move(u)
	else:
		var mv: Dictionary = BattleAI.plan_move(self, u)
		if str(mv.get("act", "")) == "move":
			var cell: Vector2i = mv.get("cell", u.cell)
			if cell in move_cells_of(u):
				u.cell = cell
				moved = true
				log.push_back("%s 移动 → %s" % [u.name, cell])
	var sk: Dictionary = BattleAI.plan_skill(self, u, moved)
	if str(sk.get("act", "")) == "skill":
		var slot := int(sk.get("slot", 1))
		var targets: Array = []
		var t0 = sk.get("target", null)
		if t0 != null:
			targets = [t0]
		_exec_skill(u, slot, targets, moved)

## 魔渊追击逻辑：能咬住昊就咬昊，追不上则直接奔袭逃生区拦截
func _hunt_move(u: BattleUnit) -> bool:
	var goal := Vector2i(-9999, -9999)
	if protect_target != null and protect_target.alive:
		var d_hao: int = _cheb(u.cell, protect_target.cell)
		var d_esc: int = dist_to_escape(u.cell)
		if d_esc < 0 or d_hao <= d_esc + 2 or d_hao <= 8:
			goal = protect_target.cell
	if goal == Vector2i(-9999, -9999):
		goal = _nearest_escape_cell(u.cell)
	if goal == Vector2i(-9999, -9999):
		return false
	var goal_name := "逃生区"
	if protect_target != null and protect_target.alive and goal == protect_target.cell:
		goal_name = "昊"
	var best := u.cell
	var bd := _cheb(u.cell, goal)
	for c in move_cells_of(u):
		var cc: Vector2i = c
		var d := _cheb(cc, goal)
		if d < bd:
			bd = d
			best = cc
	if best == u.cell:
		return false
	u.cell = best
	_check_fear(u)
	log.push_back("%s 移动 → %s（追击目标：%s）" % [u.name, best, goal_name])
	return true

func _nearest_escape_cell(from: Vector2i) -> Vector2i:
	var best := Vector2i(-9999, -9999)
	var bd := 999999
	for c in escape_cells:
		var cc: Vector2i = c
		var d := _cheb(from, cc)
		if d < bd:
			bd = d
			best = cc
	return best

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _exec_skill(u: BattleUnit, slot: int, targets: Array, _moved: bool) -> void:
	var sk := u.get_skill(slot)
	if sk == null:
		return
	var final_targets: Array = []
	if not self_skill(u, slot):
		var cap := max_targets_of(u, slot)
		for t in targets:
			var tu := t as BattleUnit
			if tu != null and tu.alive and tu in targets_in_range(u, slot) and final_targets.size() < cap:
				final_targets.append(tu)
		# 多目标技：AI 只挑了 1 个目标，补满到上限（否则 2~3 目标技被 AI 用成单体，红方强度虚低）
		if cap > 1 and final_targets.size() < cap:
			var legal: Array = targets_in_range(u, slot)
			if legal.size() > cap:
				legal = legal.slice(0, cap)
			if legal.size() >= final_targets.size():
				final_targets = legal
		if final_targets.is_empty():
			return
	var res: String = u.use_active(slot, {
		"targets": final_targets, "mode": "story", "battle": self,
		"allies": _allies_within(u, 1),
	})
	if res != "":
		log.push_back(res)

# ---------------------------------------------------------------- 玩家操作
func human_cast(slot: int, target: BattleUnit = null, extra_targets: Array = []) -> String:
	if not _wait or _cur == null:
		return "!当前不在你的回合"
	var u := _cur
	var sk := u.get_skill(slot)
	if sk == null:
		return "!技能槽无效"
	if u.is_skill_lost(sk.id):
		return "!该技能已被禁用"
	if u.has_flag("no_skill") or (slot == 4 and u.has_flag("no_ult")) or u.has_flag("no_damage"):
		return "!当前状态禁止使用技能"
	if sk.current_cd > 0:
		return "!技能冷却中"
	if u.energy < sk.energy_cost:
		return "!能量不足"
	var targets: Array = []
	if not self_skill(u, slot):
		var cap := max_targets_of(u, slot)
		var legal: Array = targets_in_range(u, slot)
		if not extra_targets.is_empty():
			for t in extra_targets:
				var tu := t as BattleUnit
				if tu != null and tu.alive and legal.has(tu) and targets.size() < cap:
					targets.append(tu)
		elif target != null:
			if not legal.has(target):
				return "!目标不在射程内（或不是合法目标）"
			targets = [target]
		else:
			for t in legal:
				if targets.size() >= cap:
					break
				targets.append(t)
		if targets.is_empty():
			return "!射程内没有合法目标"
	var res: String = u.use_active(slot, {
		"targets": targets, "mode": "story", "battle": self,
		"allies": _allies_within(u, 1),
	})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

func _finish_human() -> void:
	_flush_guard_notes()
	_check_win()
	_wait = false
	_cur = null

## 覆盖：支持 ally_target（治疗友方）/ any_target（任意单位）技能的目标集合
func targets_in_range(u: BattleUnit, slot: int) -> Array:
	var sk := u.get_skill(slot)
	if sk == null:
		return []
	var sd: Dictionary = skill_data(sk.id)
	var r := skill_range(u, slot)
	var out: Array = []
	if bool(sd.get("ally_target", false)):
		# 优先伤员：射程内有掉血的友军就只列他们，AI 不会对着满血队友空奶
		var wounded: Array = []
		var healthy: Array = []
		for x in units:
			if x.alive and x.team == u.team and dist(u, x) <= r:
				if x.hp < x.max_hp:
					wounded.append(x)
				else:
					healthy.append(x)
		out = wounded if not wounded.is_empty() else healthy
	elif bool(sd.get("any_target", false)):
		for x in units:
			if x.alive and x != u and dist(u, x) <= r:
				out.append(x)
	else:
		out = super.targets_in_range(u, slot)
	return out

func max_targets_of(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 1
	return maxi(1, int(skill_data(sk.id).get("max_targets", 1)))

## 该技能是否可选友方/任意单位（UI 目标高亮用）
func target_kind_of(u: BattleUnit, slot: int) -> String:
	var sk := u.get_skill(slot)
	if sk == null:
		return "enemy"
	var sd: Dictionary = skill_data(sk.id)
	if bool(sd.get("ally_target", false)):
		return "ally"
	if bool(sd.get("any_target", false)):
		return "any"
	return "enemy"

# ---------------------------------------------------------------- 胜负
func _check_win(_quiet := false) -> void:
	if winner != "":
		return
	if protect_target != null:
		if protect_target.alive and escape_cells.has(protect_target.cell):
			escaped = true
			winner = "白灵殿"
			log.push_back("== 昊抵达逃生区，成功脱身！白灵殿守住了白灵核心（第 %d 回合）==" % round)
			return
		if not protect_target.alive:
			winner = "魔渊"
			log.push_back("== 昊阵亡，白灵核心落入魔渊之手（第 %d 回合）==" % round)
			return
	var ra := false
	var ba := false
	for u in units:
		if u.alive:
			if u.team == TEAM_RED:
				ra = true
			else:
				ba = true
	if not ra:
		winner = "白灵殿"
		log.push_back("== 魔渊全灭，护送成功（第 %d 回合）==" % round)
	elif not ba:
		winner = "魔渊"
		log.push_back("== 白灵殿守军全灭（第 %d 回合）==" % round)

## 玩家视角的胜负文案（UI 用）
func result_title() -> String:
	if winner == "":
		return ""
	if winner == "白灵殿":
		return "胜利 · 昊成功脱身"
	return "失败 · %s" % ("昊阵亡" if (protect_target != null and not protect_target.alive) else "护送失败")
