class_name BattleBase
extends RefCounted
## 战斗引擎公共基类：1V1(battle.gd) 与 4V4(battle_team.gd) 共享的单位查询/距离/射程/移动/技能校验/状态结算。
## 2026-09-08 引擎统一重构抽取；差异（棋盘尺寸/胜负/回合队列/AI/出生）在子类各自实现。

var max_rounds := 80        # 最大回合数（1V1=80 / 4V4=120，子类 _init 可覆盖）
var child_limit := 3        # 虞美人子体上限（1V1=3 / 4V4=5，子类 _init 可覆盖）

var units: Array[BattleUnit] = []
var log: Array[String] = []
var round := 0
var winner := ""
var human_mode := false
var human_team := 0
var human_teams: Array = []   # 人类操作的阵营列表（热座 = [0, 1]）
var ai_level := "easy"        # easy / normal / hard（PVE 由对局脚本按 Global.difficulty 注入）
var ai_backend := "llm"      # 困难后端："llm"(豆包) | "local"(本地)，_maybe_llm_plan 据此门控
var _llm_plans := {}          # 最高难度：本回合豆包预案 idx_str -> plan
var side_levels := {}        # 阵营难度缓存 team(int) -> "easy"/"normal"/"hard"：推演模拟按对手真实难度执行（未设则用当前 ai_level 近似）
var llm_tactics := {}        # 豆包战术倾向 {focus, posture, protect}（第2步规则 AI 消费）
## 英雄配置表 / 技能效果表。
## 2026-09-30 上提到基类：原在 battle / battle_team / battle_story 的 _init 里各写一遍相同的两行 load。
## 用 preload 常量持有：避免全局类缓存问题，且只解析一次。
const HeroDefsScript := preload("res://scripts/combat/hero_defs.gd")
const SkillEffectsScript := preload("res://scripts/combat/skill_effects.gd")
var _queue: Array = []
var _wait := false
var _cur: BattleUnit = null
var _h_moved := false
var rng := RandomNumberGenerator.new()   # 联机确定性随机源（_init 默认 randomize；联机开局 set_rng_seed）

func _allies_within(u: BattleUnit, r: int) -> Array:
	var out: Array = []
	for x in units:
		if x.alive and x.team == u.team and _cell_dist(x.cell, u.cell) <= r:
			out.append(x)
	return out


func _best_land_cell(u: BattleUnit, enemy: BattleUnit, dd: int) -> Vector2i:
	var cells := landable_cells(u, dd)
	if enemy == null or cells.is_empty():
		return u.cell
	var best := u.cell
	var bd := 9999
	for c in cells:
		var cc: Vector2i = c
		var d := _cell_dist(cc, enemy.cell)
		if d < bd:
			bd = d
			best = cc
	return best


func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## ---- 英雄专属规则：基类只留转发壳，实现见 hero_rules.gd ----
## 调用点（battle / battle_team / battle_story / battle_tutorial 合计 20+ 处）保持不变。
## 新增英雄专属机制请写进 hero_rules.gd，不要再往基类堆实现。

func _check_fear(u: BattleUnit) -> void:
	HeroRules.check_fear(self, u)


func _child_act(child: BattleUnit) -> void:
	HeroRules.child_act(self, child)


func _end_round() -> void:
	for u in units:
		var r: String = u.end_turn()
		if r != "":
			log.push_back(r)
	_yumeiren_round_end()
	_check_win()


func _enemies_within(u: BattleUnit, r: int) -> Array:
	var out: Array = []
	for f in alive_enemies_of(u):
		if dist(u, f) <= r:
			out.append(f)
	return out


func _exec_llm_plan(u: BattleUnit, plan: Dictionary) -> bool:
	var has_any := false
	if bool(plan.get("has_move", false)):
		has_any = true
		var cell: Vector2i = plan.get("move", Vector2i(-1, -1))
		if cell in move_cells_of(u):
			u.cell = cell
			_check_fear(u)
			log.push_back("%s 移动 → %s" % [u.name, cell])
	var sk: Dictionary = plan.get("skill", {})
	if not sk.is_empty() and not u.has_flag("no_skill"):
		var slot := int(sk.get("slot", 1))
		var ok := false
		if u.get_skill(slot) != null and base_usable(u, slot) and not u.is_skill_lost(u.get_skill(slot).id):
			var tid := int(sk.get("target", -1))
			if self_skill(u, slot):
				ok = true
				_exec_skill(u, slot, [], false)
			elif tid >= 0 and tid < units.size():
				var t: BattleUnit = units[tid]
				if t.alive and t.team != u.team and t in targets_in_range(u, slot):
					ok = true
					_exec_skill(u, slot, [t], false)
		if ok:
			has_any = true
	return has_any


func _grid_free(cell: Vector2i) -> bool:
	if not _cell_exists(cell):
		return false
	for x in units:
		if x.cell == cell and not x.non_solid:
			return false
	return true


func _idx_of(u: BattleUnit) -> int:
	for i in range(units.size()):
		if units[i] == u:
			return i
	return -1


func _is_human_side(u: BattleUnit) -> bool:
	if not human_mode:
		return false
	if human_teams.is_empty():
		return u.team == human_team
	return human_teams.has(u.team)


func _maybe_llm_plan(u: BattleUnit) -> void:
	_llm_plans = {}
	if ai_level != "hard" or ai_backend != "llm":
		return
	if u == null or not u.alive or _is_human_side(u):
		return
	if not AICfg.ready():
		log.push_back("== 困难：战术模型未配置，回退本地 AI ==")
		return
	log.push_back("== 敌方请来战术模型思考… ==")
	_llm_plans = LLMDecider.plan_round(self, [u])
	if _llm_plans.is_empty():
		# 失败原因**分开说**：文案直接取服务端给的中文，避免两边各写一份迟早漂移。
		# "次数用完了"是玩家自己能解决的（去登录），和"模型抽风"混成一句他就不知道该干什么。
		if LLMDecider.last_error != "":
			log.push_back("== %s ==" % LLMDecider.last_error)
			if LLMDecider.last_need_login:
				log.push_back("== 已回退本地 AI；登录后每天可用 10 次 ==")
			else:
				log.push_back("== 已回退本地 AI ==")
		else:
			log.push_back("== 战术模型未响应，回退本地 AI ==")


func _poll_next() -> BattleUnit:
	if _queue.is_empty():
		return null
	var lst: Array = SkillEffectsScript.speed_order(_queue)
	var actor: BattleUnit = lst[0]
	_queue.erase(actor)
	return actor


func _yumeiren_round_end() -> void:
	HeroRules.yumeiren_round_end(self)


func alive_enemies_of(u: BattleUnit) -> Array:
	var out: Array = []
	for x in units:
		if x.alive and x != u and x.team != u.team:
			out.append(x)
	return out


func base_usable(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null or u.is_skill_lost(sk.id) or sk.exhausted():
		return false
	if u.has_flag("no_skill") or u.has_flag("no_damage"):
		return false
	if slot == 4 and u.has_flag("no_ult"):
		return false
	if sk.current_cd > 0 or u.energy < sk.energy_cost:
		return false
	# 资源型技能（龙王·元晶系）：元晶不足 / 需要护盾（UI 置灰与 AI 选技共用）
	var _sd: Dictionary = skill_data(sk.id)
	if int(_sd.get("crystal_cost", 0)) > u.counter("元晶"):
		return false
	if bool(_sd.get("need_shield", false)) and u.shield <= 0:
		return false
	return true


func current() -> BattleUnit:
	return _cur


func dash_dist_of(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 0
	return int(skill_data(sk.id).get("dash_dist", 0))


func dist(a: BattleUnit, b: BattleUnit) -> int:
	return _cell_dist(a.cell, b.cell)


func human_done() -> void:
	if _wait:
		_finish_human()


## ---------- 地形效果（2026-09-10） ----------
## board 由剧情关卡战斗注入（含地形层）；标准棋盘为 null → 全部按空地处理
var board: GridBoard = null

## 同步单位所在地形（移动/位移/生成后必须调用）
func _sync_terrain(u: BattleUnit) -> void:
	u.terrain_id = board.terrain_at(u.cell) if board != null else 0

## 移出当前格的地形检查与扣费；返回 "!..." 表示不允许移出
func _terrain_exit_gate(u: BattleUnit) -> String:
	var cost := u.exit_energy_cost()
	if cost <= 0:
		return ""
	if u.energy < cost:
		return "!能量不足（需 %d），无法从【%s】移出" % [cost, Terrain.name_of(u.terrain_id)]
	u.energy = maxi(0, u.energy - cost)
	log.push_back("%s 从【%s】移出，额外消耗 %d 点能量（余 %d）" % [u.name, Terrain.name_of(u.terrain_id), cost, u.energy])
	return ""

## 目标格占用判定（冰面滑行用）
func _cell_occupied_by_other(u: BattleUnit, c: Vector2i) -> bool:
	for x in units:
		if x.alive and x != u and x.cell == c and not x.non_solid:
			return true
	return false

## 位移技能地形门禁：水域/沙地禁止位移技（返回 "!..." 表示禁止）
func _terrain_dash_gate(u: BattleUnit, slot: int) -> String:
	if not is_dash(u, slot):
		return ""
	if u.dash_blocked_by_terrain():
		var nm := Terrain.name_of(u.terrain_id)
		if u.terrain_id == Terrain.WATER:
			nm = "水域"
		elif u.terrain_id == Terrain.SAND:
			nm = "沙漠"
		return "!【%s】中无法使用位移类技能" % nm
	return ""

## 冰面滑行：若落点/停留格为冰面 → 沿方向滑到冰面边缘；返回最终格
func _terrain_slide(u: BattleUnit, dest: Vector2i, dir: Vector2i) -> Vector2i:
	if board == null or dir == Vector2i.ZERO:
		return dest
	if not Terrain.is_sliding(board.terrain_at(dest)):
		return dest
	var end := board.slide_end(dest, dir, func(c: Vector2i) -> bool: return _cell_occupied_by_other(u, c))
	if end != dest:
		log.push_back("%s 在【冰面】滑行 → %s" % [u.name, end])
	return end


func human_move(cell: Vector2i) -> String:
	if not _wait or _cur == null:
		return "!当前不在你的回合"
	if _h_moved:
		return "!本回合已移动"
	if not (cell in move_cells_of(_cur)):
		return "!非法移动格"
	# 地形：移出代价检查（森林/沼泽 1、山地 2；能量不足禁止移出）
	var _gate := _terrain_exit_gate(_cur)
	if _gate != "":
		return _gate
	# 虞美人母体：移动到有自己的子体的格子 → 母体与子体互换格子（不叠格）
	var _old := _cur.cell
	var _child_at: BattleUnit = HeroRules.child_at_cell(self, _cur, cell)
	# 地形：冰面滑行（按移动方向滑到冰面边缘）
	var _dir := cell - _old
	_cur.cell = cell
	if _child_at != null:
		_child_at.cell = _old
	_cur.cell = _terrain_slide(_cur, _cur.cell, _dir)
	_sync_terrain(_cur)
	_check_fear(_cur)
	_h_moved = true
	log.push_back("%s 移动 → %s" % [_cur.name, _cur.cell])
	return "%s 移动 → %s" % [_cur.name, _cur.cell]


func human_moved() -> bool:
	return _h_moved


func is_charge(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return str(skill_data(sk.id).get("ai", {}).get("dash_kind", "jump")) == "charge"


func is_dash(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("dash", false))


func is_spread(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("spread", false))


func land_aoe(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("land_aoe", false))


func result_text() -> String:
	return "\n".join(log)


func self_skill(u: BattleUnit, slot: int) -> bool:
	var sk := u.get_skill(slot)
	if sk == null:
		return false
	return bool(skill_data(sk.id).get("ai", {}).get("self_buff", false))


func set_rng_seed(s: int) -> void:
	rng.seed = s


func simulate() -> String:
	while winner == "" and round < max_rounds:
		if run_step().has("over"):
			break
	return winner


func skill_data(id: String) -> Dictionary:
	return SkillEffectsScript.DATA.get(id, {}) as Dictionary


func skill_range(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 0
	return int(skill_data(sk.id).get("range", 1))


## 该技能一次最多可选几个目标（默认 1；如追猎流炎飞弹 = 2）。
## 2026-09-30 上提到基类：原先 battle_team / battle_story 各存一份逐字相同的实现，
## 而 4V4 界面（team_duel）要以 BattleBase 类型调它，重复实现会直接编译失败。
func max_targets_of(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 1
	return maxi(1, int(skill_data(sk.id).get("max_targets", 1)))


func spawn_child(parent: BattleUnit, cell: Vector2i) -> BattleUnit:
	return HeroRules.spawn_child(self, parent, cell)


func spread_cells_of(u: BattleUnit) -> Array:
	var out: Array = []
	for dv in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
		var c: Vector2i = u.cell + dv
		if not _cell_exists(c):
			continue
		if not _grid_free(c):
			continue
		var has_child := false
		for x in units:
			if x.has_flag("子体") and x.team == u.team and x.cell == c:
				has_child = true
				break
		if not has_child:
			out.append(c)
	return out

func targets_in_range(u: BattleUnit, slot: int) -> Array:
	var r := skill_range(u, slot)
	var shape := ""
	var sk := u.get_skill(slot)
	if sk != null:
		shape = str(skill_data(sk.id).get("range_shape", ""))
	var out: Array = []
	for f in alive_enemies_of(u):
		if shape == "diamond":
			# 菱形（曼哈顿距离）：如流萤超新星的"九宫格+两轴外扩"13 格
			if absi(u.cell.x - f.cell.x) + absi(u.cell.y - f.cell.y) <= r:
				out.append(f)
		elif dist(u, f) <= r:
			out.append(f)
	return out


func waiting() -> bool:
	return _wait

## ---- 子类必须覆盖的差异方法（基类给默认实现，保证基类可独立编译；子类同名覆盖）----
func _cell_exists(_cell: Vector2i) -> bool:
	return false

func move_cells_of(_u: BattleUnit) -> Array:
	return []

func landable_cells(_u: BattleUnit, _dd: int) -> Array:
	return []

func _exec_skill(_u: BattleUnit, _slot: int, _targets: Array, _moved: bool) -> void:
	pass

func _finish_human() -> void:
	pass

func _check_win(_quiet: bool = false) -> void:
	pass

func run_step() -> Dictionary:
	return {"over": true}
