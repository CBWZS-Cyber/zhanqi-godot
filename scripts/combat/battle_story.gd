class_name BattleStory
extends BattleBase
## 骑士线第一关 · 白灵殿 剧情战斗管理器（7V10 护送关）
##
## 阵营：红方 = 魔渊（team 0，AI 控制，7 单位）／蓝方 = 白灵殿（team 1，玩家控制，10 单位）
## 胜利（2026-09-12 改）：【昊】与【祁】都存活，且两人都抵达地图最右侧 4 格逃生区
## 失败：昊阵亡 / 祁阵亡 / 蓝方全灭 / 超过 MAX_ROUNDS 回合仍未脱身
## 歼灭红方同样判胜（打得过也可以硬推）
##
## 与 4V4（battle_team）的差异：
##   1. 棋盘来自 maps/白灵殿.json（自由拼格 296 格，含地形障碍），不再是 8×8 标准盘；
##   2. 每回合移动 = MOVE_STEPS 步 × 每步 8 方向 1 格（BFS 绕障碍），昊因携带白灵核心只有 1 步；
##   3. 无星星得分制；胜负改护送判定；
##   4. 红方 AI 追加「追杀昊 / 祁 / 奔袭逃生区拦截」的目标逻辑（_hunt_move）。
##
## 【2026-09-12 平衡调整】蓝方（白灵殿）整体削弱、红方（魔渊）整体加强，
## 数值全部改按《角色属性与技能表2.0.xlsx》。逃生区由「x≥16 整列」收缩为
## 地图最右侧 4 格（x=18, y=0~3），昊与祁必须一起钻进去 —— 详见 story_defs.gd 与 CHANGELOG。

const MAP_PATH := "res://maps/白灵殿.json"
const TEAM_RED := 0      # 魔渊
const TEAM_BLUE := 1     # 白灵殿
## 逃生区（2026-09-12 用户要求「逃生区缩小，仅为地图最右侧 4 格」）：
## 地图 x 最大列为 18，取该列 y=0~3 的 4 格（4 格均为森林，可通行）。
## 旧规则是 ESCAPE_X=16 的整列带（12 格）；收缩后昊与祁都得挤进这 4 格才算脱身。
const ESCAPE_CELLS := [Vector2i(18, 0), Vector2i(18, 1), Vector2i(18, 2), Vector2i(18, 3)]
const DEFAULT_MOVE_STEPS := 2   # 默认每回合移动步数（用户 2026-09-10 定：每回合两次，每次 8 方向 1 格）
const BLOCK_TYPES := [1, 2]     # 地图地形：1 可破坏障碍 / 2 不可破坏障碍 → 均不可通行
## 【畏惧】每层速度惩罚（属性表 2.0：每层速度 -5；旧值为 -10）
const FEAR_SPEED_PER_LAYER := -5

## 昊的「不受控前进」：每 HAO_AUTO_EVERY 个回合末，自动朝 HAO_AUTO_DIR 挪 1 格（2026-09-10 用户要求加难度）
## 设计意图：玩家管不住昊的腿 —— 他会自己往东（逃生区方向）走，容易跑在护卫前面落单，
##           而他只有 0 甲 5 血，一旦被魔渊贴上就极易暴毙。
## 调参：改成 3 = 每 3 回合末走一次；改成 0 = 关闭自动移动；方向改 Vector2i(-1,0) 即向西倒退。
const HAO_AUTO_EVERY := 2
const HAO_AUTO_DIR := Vector2i(1, 0)   # 向东（x+1），即逃生区方向
## 祁的「不受控前进」（2026-09-12 新增）：祁同样带白灵族血印，也被核心牵引。
## 频率比昊低（3 回合一次；祁基础速度 90，本来就比许多魔渊单位慢），同样玩家无法阻止。
const QI_AUTO_EVERY := 3
const QI_AUTO_DIR := Vector2i(1, 0)

const BREAKABLE := 1            # 地形 id：可破坏障碍（= Terrain.OBST_BREAKABLE）
## 拆障碍所需伤害（用户 2026-09-12：「受到一点伤害后可变为空地」）
## 当前实现为"被选为目标即碎"，此常量保留用于后续如果需要引入障碍结构值。
const OBSTACLE_HP := 1

var max_rounds_limit := 60
var map_name := "白灵殿"
var cells: Dictionary = {}          # "x,y" -> type(int)
var terrain_types: Dictionary = {}  # type(int) -> {name,color}
var escape_cells: Array = []        # 逃生区格（= ESCAPE_CELLS 中真实存在且可通行的格）
var _dist_escape: Dictionary = {}   # "x,y" -> 到最近逃生格的步数（多源 BFS，开局算一次）
var _board: GridBoard = null
var protect_target: BattleUnit = null   # 昊（被护送者 · 主目标）
var escort_qi: BattleUnit = null        # 祁（2026-09-12 起同为被护送者）
var escaped := false

func _init() -> void:
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
	# 2026-09-13 修复：出生即同步脚下地形（此前 terrain_id 一直是 0，直到单位首次移动）
	for _su in units:
		_sync_terrain(_su)
	_compute_escape_dist()
	log.push_back("骑士线第一关 · %s：护送【昊】与【祁】同时抵达地图最右侧 4 格逃生区" % map_name)
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
	# 逃生区：2026-09-12 起为固定 4 格（ESCAPE_CELLS），只保留地图上真实存在且可通行的格
	escape_cells = []
	for c in ESCAPE_CELLS:
		var cc: Vector2i = c
		if _terrain_ok(cc):
			escape_cells.append(cc)
	return not cells.is_empty()

func _build_board() -> void:
	_board = GridBoard.new([], true)
	for k in cells:
		var c := _v2i(k)
		var t := int(cells[k])
		_board.add_cell(c)
		# 地形层：只把“本关启用”的地形写进地形层，其余一律写空地(0)。
		# 这样沼泽/雪地/沙漠/山地/冰面即使出现在地图里也不会产生任何效果（Terrain.STORY_ACTIVE 门禁，来自 9.12_v2）。
		# 2026-09-13 修复：地形必须一并灌进格图（含障碍同步），否则 board.terrain_at() 恒为 0 ——
		# 改用 set_cell_terrain()（地形 + 障碍一次同步），替代原 set_terrain() + set_obstacle() 两步写法。
		_board.set_cell_terrain(c, t if Terrain.story_active(t) else Terrain.EMPTY)
	# ★ 关键：接入基类 board 字段，基类 _sync_terrain() 才会真正把 terrain_id 写到单位上。
	#   2026-09-12 修复：此前 BattleStory 只用自己的 _board，从未给 board 赋值，
	#   导致本关所有单位 terrain_id 恒为 0，森林免伤/水域扣能量等全是死代码。
	board = _board

## 同步单位所在地形（生成 / 移动 / 牵引后都必须调用，否则地形效果不生效）
func _sync_terrain(u: BattleUnit) -> void:
	if u == null:
		return
	super._sync_terrain(u)

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
		_sync_terrain(u)          # 出生即确定所在地形（森林/水域等）
		units.append(u)
		if def_id == "story_hao":
			protect_target = u
		elif def_id == "story_qi":
			escort_qi = u
		var terr_note := ""
		if u.terrain_id != 0:
			terr_note = "（地形：%s%s）" % [Terrain.name_of(u.terrain_id),
				"，无视水域" if u.water_immune and u.terrain_id == Terrain.WATER else ""]
		log.push_back("· %s〔%s〕出生 %s%s（速 %d，移动 %d 步）" % [
			u.name, "魔渊" if team == TEAM_RED else "白灵殿", cell, terr_note,
			u.effective_speed(), steps_of(u)])

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

## 2026-09-13 新增：落位并同步脚下地形。
## 任何「直接改 u.cell」的地方都改走这里 —— 否则地形 id 会残留，
## 出现「站进森林却按空地算伤害」的错算（AI 移动、回合末牵引都是这种直改）。
func _place(u: BattleUnit, c: Vector2i) -> void:
	u.cell = c
	_sync_terrain(u)

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
	# 魔渊集火目标：优先咬「血量最低的护送目标」（昊 0 甲 5 血 / 祁 1 甲 7 血，通常先锁昊）
	if escort_focus() != null:
		llm_tactics = {"focus": _idx_of(escort_focus())}
	else:
		llm_tactics = {}

## 集火对象：两个护送目标里血最少的那个（都没有则 null）
func escort_focus() -> BattleUnit:
	var best: BattleUnit = null
	var bh := 1.0e9
	for e in [protect_target, escort_qi]:
		var eu := e as BattleUnit
		if eu == null or not eu.alive:
			continue
		if eu.hp < bh:
			bh = eu.hp
			best = eu
	return best

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
		# 宵·不灭：生命低于 10% 时无法行动（2026-09-12 由 50% 下调，红方加强）
		if actor.def_id == "story_xiao" and actor.hp <= actor.max_hp * 0.1:
			log.push_back("【不灭】%s 生命低于一成，无法行动" % actor.name)
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
	_qi_auto_advance()
	_flush_guard_notes()
	_check_win()

## 昊在回合末被白灵核心牵引，自动朝 HAO_AUTO_DIR 挪 1 格（玩家无法阻止）
## 阻挡规则：地形不可通行 / 该格站着别的单位 → 原地不动并写战报
func _hao_auto_advance() -> void:
	_auto_advance_one(protect_target, HAO_AUTO_EVERY, HAO_AUTO_DIR)

## 祁同样被牵引（2026-09-12 新增，频率 QI_AUTO_EVERY）
func _qi_auto_advance() -> void:
	_auto_advance_one(escort_qi, QI_AUTO_EVERY, QI_AUTO_DIR)

## 回合末牵引通用逻辑：每 every 回合朝 dir 挪 1 格，被障碍/单位挡住则原地不动
func _auto_advance_one(h: BattleUnit, every: int, dir: Vector2i) -> void:
	if h == null or not h.alive:
		return
	if every <= 0 or round % every != 0:
		return
	var dest: Vector2i = h.cell + dir
	if not _terrain_ok(dest):
		log.push_back("【失控】%s 被核心牵引想往逃生区走，但 %s 是障碍，原地不动" % [h.name, dest])
		return
	var blocker := _unit_at(dest)
	if blocker != null:
		log.push_back("【失控】%s 被核心牵引想往逃生区走，但被 %s 挡住" % [h.name, blocker.name])
		return
	_place(h, dest)
	var d := dist_to_escape(dest)
	var terr := ""
	if h.terrain_id != 0:
		terr = "，进入【%s】" % Terrain.name_of(h.terrain_id)
	log.push_back("【失控】回合末：%s 不由自主向东挪了 1 格 → %s%s（距逃生区 %s）" % [
		h.name, dest, terr, ("%d 步" % d) if d > 0 else "已就位"])
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

## 畏惧：每回合末 -1 层（每层速度 -5；2026-09-12 由 -10 改为 -5，与属性表 2.0 对齐）
func _tick_fear() -> void:
	for u in units:
		var n := u.status_stacks("fear")
		if n <= 0:
			continue
		u.set_status("fear", n - 1)
		u.set_speed_mod_src("畏惧", FEAR_SPEED_PER_LAYER * u.status_stacks("fear"))
		log.push_back("%s【畏惧】衰减 %d → %d 层（速度 %d）" % [
			u.name, n, u.status_stacks("fear"), u.effective_speed()])

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
				_place(u, cell)
				moved = true
				log.push_back("%s 移动 → %s" % [u.name, cell])
	# 技能优先级（红方）：能打到护送目标 → 就咬人；咬不到但有障碍挡路 → 拆障碍
	var sk: Dictionary = BattleAI.plan_skill(self, u, moved)
	if str(sk.get("act", "")) != "skill" and u.team == TEAM_RED:
		var brk := _plan_break(u)
		if not brk.is_empty():
			sk = brk
	if str(sk.get("act", "")) == "skill":
		var slot := int(sk.get("slot", 1))
		var targets: Array = []
		var t0 = sk.get("target", null)
		if t0 != null:
			targets = [t0]
		_exec_skill(u, slot, targets, moved)

## 红方 AI：追击路线确实被「可破坏障碍」挡住时，主动拆掉能缩短路径的那块
## 设计意图（用户 2026-09-12）：「方便敌方破除障碍追击昊」。
## 触发条件（保守，避免 AI 无脑拆墙浪费时间 —— 拆墙会占用整回合技能，代价很高）：
##   · 目标始终是护送目标（昊 / 祁），且当前尚未贴身（切比雪夫 > 2）；
##   · 到目标的【真实可走步数】明显大于直线切比雪夫距离 → 说明被障碍绕路了；
##   · 射程内的某块可破坏障碍，拆掉后能让"到目标的真实距离"变小。
## 返回 BattleAI 同构的技能字典；无可拆则返回 {}。
func _plan_break(u: BattleUnit) -> Dictionary:
	var prey := _nearest_escort_to(u.cell)
	if prey == null:
		return {}
	if _cheb(u.cell, prey.cell) <= 2:
		return {}                      # 快贴上了，优先打人而不是拆墙
	var straight := _cheb(u.cell, prey.cell)
	var d_now := _board.distance(u.cell, prey.cell) if _board != null else straight
	# 没有绕路（真实距离 ≈ 直线距离）→ 不必拆墙
	if d_now < 0 or d_now <= straight + 1:
		return {}
	var best := {}
	var best_d := d_now
	for cand in can_break_any(u):
		var cd: Dictionary = cand
		var c: Vector2i = cd["cell"]
		# 试算：把该障碍当空地后，从本单位到目标的真实距离是否缩短
		_board.set_obstacle(c, false)
		var d_after := _board.distance(u.cell, prey.cell)
		_board.set_obstacle(c, true)
		if d_after >= 0 and d_after < best_d:
			best_d = d_after
			best = {"act": "skill", "slot": int(cd["slot"]), "target": c}
	return best

## 魔渊追击逻辑：能咬住护送目标（昊 / 祁）就咬，追不上则直接奔袭逃生区拦截
## 2026-09-12：昊与祁同为护送目标 → 取「更近的那个」为追击对象（谁好咬就咬谁）
func _hunt_move(u: BattleUnit) -> bool:
	var prey := _nearest_escort_to(u.cell)
	var goal := Vector2i(-9999, -9999)
	var goal_name := "逃生区"
	if prey != null:
		var d_prey: int = _cheb(u.cell, prey.cell)
		var d_esc: int = dist_to_escape(u.cell)
		if d_esc < 0 or d_prey <= d_esc + 2 or d_prey <= 8:
			goal = prey.cell
			goal_name = prey.name
	if goal == Vector2i(-9999, -9999):
		goal = _nearest_escape_cell(u.cell)
	if goal == Vector2i(-9999, -9999):
		return false
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
	_place(u, best)
	_check_fear(u)
	var tw := ""
	if u.terrain_id != 0:
		tw = "，进入【%s】%s" % [Terrain.name_of(u.terrain_id),
			"（无视水域）" if u.water_immune and u.terrain_id == Terrain.WATER else ""]
	log.push_back("%s 移动 → %s%s（追击目标：%s）" % [u.name, best, tw, goal_name])
	return true

## 最近的存活护送目标（昊 / 祁）；都没有则返回 null
func _nearest_escort_to(from: Vector2i) -> BattleUnit:
	var best: BattleUnit = null
	var bd := 999999
	for e in [protect_target, escort_qi]:
		var eu := e as BattleUnit
		if eu == null or not eu.alive:
			continue
		var d := _cheb(from, eu.cell)
		if d < bd:
			bd = d
			best = eu
	return best

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
		var legal: Array = all_targets_of(u, slot)    # 单位 + 可破坏障碍格
		for t in targets:
			if final_targets.size() >= cap:
				break
			if t is Vector2i:
				var tc: Vector2i = t
				if tc in breakable_in_range(u, slot):
					final_targets.append(tc)          # 拆障占 1 个目标名额
				continue
			var tu := t as BattleUnit
			if tu != null and tu.alive and legal.has(tu):
				final_targets.append(tu)
		# 多目标技：AI 只挑了 1 个目标，补满到上限（否则 2~3 目标技被 AI 用成单体，红方强度虚低）
		if cap > 1 and final_targets.size() < cap:
			if legal.size() > cap:
				legal = legal.slice(0, cap)
			if legal.size() >= final_targets.size():
				final_targets = legal
		if final_targets.is_empty():
			return
	# 先结算"拆障碍"的目标（不进入单位技能效果），再让单位效果只处理 BattleUnit
	var unit_targets: Array = []
	var broke := 0
	for t in final_targets:
		if t is Vector2i:
			if damage_obstacle(t, u):
				broke += 1
		else:
			unit_targets.append(t)
	var res := ""
	if not unit_targets.is_empty() or self_skill(u, slot):
		res = u.use_active(slot, {
			"targets": unit_targets, "mode": "story", "battle": self,
			"allies": _allies_within(u, 1),
		})
		if res != "":
			log.push_back(res)
	elif broke > 0:
		# 纯拆障碍：不走 use_active（效果函数拿不到单位目标会吐噪声文案），手动扣能量 + 计冷却
		u.spend_energy(sk.energy_cost)
		sk.current_cd = sk.cooldown
		sk.used_count += 1
		log.push_back("%s 使用【%s】击碎了 %d 处障碍" % [u.name, sk.display_name, broke])
	_sync_terrain(u)

# ---------------------------------------------------------------- 玩家操作
## 施放技能：target / extra_targets 里既可以放 BattleUnit，也可以放 Vector2i（可破坏障碍格）
func human_cast(slot: int, target = null, extra_targets: Array = []) -> String:
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
		var legal: Array = all_targets_of(u, slot)
		if not extra_targets.is_empty():
			for t in extra_targets:
				if targets.size() >= cap:
					break
				if t is Vector2i:
					if (t as Vector2i) in legal:
						targets.append(t)
					continue
				var tu2 := t as BattleUnit
				if tu2 != null and tu2.alive and legal.has(tu2):
					targets.append(tu2)
		elif target != null:
			if target is Vector2i:
				# 点可破坏障碍格
				if not ((target as Vector2i) in legal):
					return "!该障碍不在射程内（或不是可破坏障碍）"
				targets = [target]
			else:
				var tu := target as BattleUnit
				if tu == null or not legal.has(tu):
					return "!目标不在射程内（或不是合法目标）"
				targets = [tu]
		else:
			for t in legal:
				if targets.size() >= cap:
					break
				targets.append(t)
		if targets.is_empty():
			return "!射程内没有合法目标"
	return _cast_and_finish(u, slot, targets)

## 施放并把回合交给下一位（玩家操作收尾统一入口）
func _cast_and_finish(u: BattleUnit, slot: int, targets: Array) -> String:
	var res := ""
	var sk := u.get_skill(slot)
	# 障碍目标先单独结算（占名额，但不进入单位技能效果）
	var unit_targets: Array = []
	var broke := 0
	for t in targets:
		if t is Vector2i:
			if damage_obstacle(t, u):
				broke += 1
		else:
			unit_targets.append(t)
	if not unit_targets.is_empty() or self_skill(u, slot):
		res = u.use_active(slot, {
			"targets": unit_targets, "mode": "story", "battle": self,
			"allies": _allies_within(u, 1),
		})
		if res != "":
			log.push_back(res)
	elif broke > 0:
		# 纯拆障碍：技能效果函数拿不到目标会返回"未配置"之类的噪声文案，
		# 所以不走 use_active，改为手动扣能量 + 计冷却（与正常施放口径一致）。
		if sk != null:
			u.spend_energy(sk.energy_cost)
			sk.current_cd = sk.cooldown
			sk.used_count += 1
		res = "%s 使用【%s】击碎了 %d 处障碍" % [
			u.name, sk.display_name if sk != null else "技能", broke]
		for line in [res]:
			log.push_back(line)
	_sync_terrain(u)
	_finish_human()
	return res

## 覆写移动：基类 human_move 内部会用 _terrain_exit_gate 读 terrain_id，
## 因此必须在移动【前后】都同步地形，否则水域禁令 / 森林免伤会算在错误的格子上。
func human_move(cell: Vector2i) -> String:
	if _cur != null:
		_sync_terrain(_cur)
	var r: String = super.human_move(cell)
	if not r.begins_with("!") and _cur != null:
		_sync_terrain(_cur)
		if _cur.terrain_id != 0:
			log.push_back("%s 所处地形：%s" % [_cur.name, Terrain.name_of(_cur.terrain_id)])
	return r

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

# ---------------------------------------------------------------- 可破坏障碍（2026-09-12）
## 「红方攻击可破坏障碍」规则（用户 2026-09-12 要求）：
##   1. 只有魔渊（红方）能拆 —— 蓝方点障碍无反应（决策：只有红方能拆）；
##   2. 红方全部单位的所有攻击技能都能把射程内的可破坏障碍当作目标；
##   3. 障碍受 1 点伤害后地形变为空地（id 0），随即重新计算逃生距离；
##   4. 拆障碍【占用法术的目标名额】（单目标技即完全消耗该单位本回合的技能）。

## 该单位技能射程内的可破坏障碍格列表（蓝方恒为空 = 不能拆）
## 距离口径与单位目标一致：切比雪夫（斜向 1 格）
func breakable_in_range(u: BattleUnit, slot: int) -> Array:
	var out: Array = []
	if u == null or _board == null:
		return out
	if u.team != TEAM_RED:
		return out                       # 只有红方能拆
	var r := skill_range(u, slot)
	if r <= 0:
		return out
	for k in cells:
		if int(cells[k]) != BREAKABLE:
			continue
		var c := _v2i(str(k))
		if _cheb(u.cell, c) <= r:
			out.append(c)
	return out

## 该单位当前有无任何技能能拆到障碍（AI 用）
func can_break_any(u: BattleUnit) -> Array:
	var out: Array = []
	for slot in [1, 2, 3, 4]:
		if u.get_skill(slot) == null:
			continue
		for c in breakable_in_range(u, slot):
			out.append({"slot": slot, "cell": c})
	return out

## 障碍受击：变为空地。返回 true = 本次确实破坏了
func damage_obstacle(cell: Vector2i, by: BattleUnit = null) -> bool:
	var k := _key(cell)
	if int(cells.get(k, -1)) != BREAKABLE:
		return false
	cells[k] = Terrain.EMPTY
	if _board != null:
		# set_cell_terrain 内部会同步 obstacles（空地 → is_blocking=false → 移除障碍）
		_board.set_cell_terrain(cell, Terrain.EMPTY)
	var who := by.name if by != null else "魔渊"
	log.push_back("【破障】%s 击碎了 %s 处的可破坏障碍，该格变为空地" % [who, cell])
	# 通路变了 → 逃生距离必须重算（红方 AI 的 dist_to_escape 判断依赖它）
	_compute_escape_dist()
	return true

## 技能可选目标全集：单位（BattleUnit）+ 可破坏障碍格（Vector2i）
## 红方两类都可选；蓝方只有单位。UI 与 AI 都用这个函数取目标。
func all_targets_of(u: BattleUnit, slot: int) -> Array:
	var out: Array = targets_in_range(u, slot).duplicate()
	for c in breakable_in_range(u, slot):
		out.append(c)
	return out

## 该技能当前是否"有目标可打"（单位或障碍）
func has_any_target(u: BattleUnit, slot: int) -> bool:
	return not all_targets_of(u, slot).is_empty()

# ---------------------------------------------------------------- 胜负
## 胜利：昊与祁【都存活】且【都站在逃生区格上】（2026-09-12 用户要求）
## 失败：昊或祁任一阵亡 / 白灵殿全灭 / 超时；魔渊全灭仍判胜
func _check_win(_quiet := false) -> void:
	if winner != "":
		return
	if protect_target != null and not protect_target.alive:
		winner = "魔渊"
		log.push_back("== 昊阵亡，白灵核心落入魔渊之手（第 %d 回合）==" % round)
		return
	if escort_qi != null and not escort_qi.alive:
		winner = "魔渊"
		log.push_back("== 祁阵亡，昊失去唯一同行者（第 %d 回合）==" % round)
		return
	if _is_escorted(protect_target) and _is_escorted(escort_qi):
		escaped = true
		winner = "白灵殿"
		log.push_back("== 昊与祁一同踏入逃生区，成功脱身！白灵殿守住了白灵核心（第 %d 回合）==" % round)
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

## 该单位是否已在逃生区（存活且站在逃生格上）
func _is_escorted(u: BattleUnit) -> bool:
	return u != null and u.alive and escape_cells.has(u.cell)

## 对外：昊是否已就位（UI 用）
func hao_arrived() -> bool:
	return _is_escorted(protect_target)

## 对外：祁是否已就位（UI 用）
func qi_arrived() -> bool:
	return _is_escorted(escort_qi)

## 玩家视角的胜负文案（UI 用）
func result_title() -> String:
	if winner == "":
		return ""
	if winner == "白灵殿":
		return "胜利 · 昊与祁成功脱身"
	if protect_target != null and not protect_target.alive:
		return "失败 · 昊阵亡"
	if escort_qi != null and not escort_qi.alive:
		return "失败 · 祁阵亡"
	return "失败 · 护送失败"
