class_name BattleTeam
extends RefCounted
## 战棋 · 4V4 战斗管理器（标准棋盘：8×8 主区 x1..8/y1..8 + 左右翼出生列 x0/x9）
## 队伍：红方 team=0（左翼 x0, y3..6 出生）vs 蓝方 team=1（右翼 x9, y3..6 出生），各 4 棋
## 回合结构：与 1V1 完全一致 —— 每棋每回合 = 1 移动权 + 1 技能权（先移后放、各自可选）
##   - 每回合所有存活棋子按“实时速度”从高到低依次行动（速度变化立即影响后续顺序）
## 驱动方式（与 battle.gd 同构，UI/AI 可直接套用 1V1 的查询接口）：
##   - run_step() 自动结算直到“轮到人类 / 分出胜负”，返回状态
##   - 人类回合：human_move(cell) → human_cast(slot, enemy) / human_done()
##   - AI 回合：BattleAI 自动决策；v1 所有技能按单目标处理（AI 自动选最近敌人）
##   - simulate() = 全自动（测试用）
##
## 【v1 边界说明（待后续迭代）】
##   1. 技能目标：暂统一“单目标”（与 1V1 行为一致），范围/多目标声明式支持后续补；
##   2. 被动触发：与现有 1V1 战斗层保持一致，暂不在回合流程中显式 trigger_passive；
##   3. 地图：固定标准棋盘（无地形障碍），地形/剧情图后续接入。

const X_MIN := 0
const X_MAX := 9
const Y_MIN := 1
const Y_MAX := 8
const SPAWN_RED: Array = [Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6)]
const SPAWN_BLUE: Array = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6)]
const TEAM_RED := 0
const TEAM_BLUE := 1
const TEAM_SIZE := 4
const WIN_SCORE := 30        # 得分制胜利分数
const KILL_REWARD := 6        # 击杀敌方单位 +6 分
const SMALL_STAR_VAL := 3     # 小星星 +3 分
const BIG_STAR_VAL := 5       # 大星星 +5 分
const SMALL_STAR_MAX := 2
const BIG_STAR_MAX := 1
const BIG_STAR_EVERY := 5
const MAX_ROUNDS := 120

var units: Array[BattleUnit] = []
var log: Array[String] = []
var round := 0
var winner := ""
var human_mode := false
var human_team := 0
var human_teams: Array = []   # 人类操作的阵营列表（热座 = [0, 1]）
var ai_level := "easy"        # easy / normal / hard（PVE 由对局脚本按 Global.difficulty 注入）
var enable_lookahead := true  # 前瞻开关（测试/批量模拟可关掉提速，不影响决策公平性）
var ai_backend := "llm"      # 困难后端："llm"(豆包) | "local"(本地)，_maybe_llm_plan 据此门控
var _llm_plans := {}          # 最高难度：本回合豆包预案 idx_str -> plan
var side_levels := {}        # 阵营难度缓存 team(int) -> "easy"/"normal"/"hard"：推演模拟按对手真实难度执行（未设则用当前 ai_level 近似）
var llm_tactics := {}        # 豆包战术倾向 {focus, posture, protect}（第2步规则 AI 消费）
var scores := {0: 0, 1: 0}    # 得分制：{team: 分数}
var stars: Array = []         # 场上星星：[{pos: Vector2i, big: bool}]
var _dead_tally := {0: 0, 1: 0}  # 累计死亡数（用于击杀计分增量）
var _hd: GDScript
var _se: GDScript
var _queue: Array = []
var _wait := false
var _cur: BattleUnit = null
var _h_moved := false
var rng := RandomNumberGenerator.new()   # 联机确定性随机源（_init 默认 randomize；联机开局 set_rng_seed）

func _init(red_ids: Array, blue_ids: Array) -> void:
	_hd = load("res://scripts/combat/hero_defs.gd")
	_se = load("res://scripts/combat/skill_effects.gd")
	rng.randomize()
	var red_n := ""
	var blue_n := ""
	for i in range(TEAM_SIZE):
		var rid := str(red_ids[i]) if i < red_ids.size() else "demo_hero"
		var bid := str(blue_ids[i]) if i < blue_ids.size() else "demo_hero"
		var ru := _make(rid, TEAM_RED, SPAWN_RED[i])
		var bu := _make(bid, TEAM_BLUE, SPAWN_BLUE[i])
		units.append(ru)
		units.append(bu)
		red_n += (", " if i > 0 else "") + ru.name
		blue_n += (", " if i > 0 else "") + bu.name
	log.push_back("4V4 对局开始：红方〔%s〕 vs 蓝方〔%s〕" % [red_n, blue_n])
	for u in units:
		log.push_back("· %s 出生 %s（速%d）" % [u.name, u.cell, u.effective_speed()])

## 联机确定性随机：开局包设定同一种子 → 双方引擎随机结果一致
func set_rng_seed(s: int) -> void:
	rng.seed = s

func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	var def: Dictionary = (_hd.ALL.get(hero_id, _hd.ALL.get("demo_hero", {})) as Dictionary).duplicate(true)
	def["id"] = hero_id
	var u := BattleUnit.new(def)
	u.team = team
	u.cell = cell
	u.rng = rng
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
		if _is_human_side(actor):
			_wait = true
			_h_moved = false
			_cur = actor
			return {"wait": actor}
		_turn_ai(actor)
		_landed(actor)      # 拾取星星（若停到星格）
		_check_win()        # 击杀计分 / 20 分 / 全灭 判定
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
	_spawn_stars()
	# 2026-09-05 v2 调整：改为"每步现场决策"——回合初不再批量预生成预案，
	# 每个 AI 单位行动前在 _turn_ai 中现问豆包（见 _maybe_llm_plan(u)）

## 最高难度：为单个 AI 单位现场生成豆包预案（同步阻塞 ~1-4s/次）
## v2：由 _turn_ai 在每个单位行动前调用，只决策当前单位 → 每步都基于最新局面重新思考
func _maybe_llm_plan(u: BattleUnit) -> void:
	_llm_plans = {}
	if ai_level != "hard" or ai_backend != "llm":
		return
	if u == null or not u.alive or _is_human_side(u):
		return
	if not AICfg.ready():
		log.push_back("== 困难：未内置战术模型密钥，回退本地 AI ==")
		return
	log.push_back("== 敌方请来战术模型思考… ==")
	_llm_plans = LLMDecider.plan_round(self, [u])
	if _llm_plans.is_empty():
		log.push_back("== 战术模型未响应，回退本地 AI ==")

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
	# 最高难度·豆包：每个 AI 单位行动前现场问豆包（v2，每步现想）；失败回退本地 AI
	if ai_level == "hard" and ai_backend == "llm":
		_maybe_llm_plan(u)
		if _llm_plans.has(str(_idx_of(u))):
			if _exec_llm_plan(u, _llm_plans[str(_idx_of(u))]):
				return
	# 前瞻推演：normal 2 步 / hard 5 步选最优；easy 不推演走常规逻辑
	if enable_lookahead and (ai_level == "normal" or ai_level == "hard"):
		if _turn_lookahead(u):
			return
	_exec_regular_turn(u)

## 常规本地 AI 回合（无前瞻），供 easy 与推演模拟共用
func _exec_regular_turn(u: BattleUnit) -> void:
	if not u.alive:
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
		var slot := int(sk.get("slot", 1))
		var targets: Array = sk.get("targets", [])
		if targets.is_empty() and sk.get("target", null) != null:
			targets = [sk.get("target")]
		# 兜底：非自身技若仍给出多目标，收敛为最近单目标（新 AI 通常直接给出 1 个）
		if not self_skill(u, slot) and targets.size() > 1:
			targets = [_nearest_enemy_of(u, targets)]
		_exec_skill(u, slot, targets, moved)

## 从候选敌人里挑离自己最近的（距离相同取先遍历者）
func _nearest_enemy_of(u: BattleUnit, cands: Array) -> BattleUnit:
	var best: BattleUnit = null
	var bd := 9999
	for t in cands:
		var tu := t as BattleUnit
		if tu == null or not tu.alive:
			continue
		var d := _cell_dist(u.cell, tu.cell)
		if d < bd:
			bd = d
			best = tu
	return best

func _crazy(u: BattleUnit) -> void:
	var foes := alive_enemies_of(u)
	if foes.is_empty():
		return
	var slot := 1 + (rng.randi() % 4)
	var res: String = u.use_active(slot, {"targets": foes, "mode": "4v4"})
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
	# 目标：非自身技统一单目标（玩家点谁打谁）
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
	var res: String = u.use_active(slot, {"targets": targets, "mode": "4v4"})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

func human_done() -> void:
	if _wait:
		_finish_human()

## =============== 真位移（落格） ===============
## 普通位移 = 跃迁：跳到 dash_dist 内任意合法空格（无视路径；落地格必须无阻挡/无单位）
## 冲刺 = 朝目标方向逐格冲，停在被挡前一格 / 目标邻格 / 冲满
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

## 标准 4V4 棋盘上是否存在该格（整板 x0..9 / y1..8，含翼列）
func _cell_exists(cell: Vector2i) -> bool:
	return cell.x >= X_MIN and cell.x <= X_MAX and cell.y >= Y_MIN and cell.y <= Y_MAX

func _grid_free(cell: Vector2i) -> bool:
	if not _cell_exists(cell):
		return false
	for x in units:
		if x.cell == cell:
			return false
	return true

## 跃迁可达格（曼哈顿距离 <= dd 的合法空格，可含原地）
func landable_cells(u: BattleUnit, dd: int) -> Array:
	var out: Array = []
	for y in range(Y_MIN, Y_MAX + 1):
		for x in range(X_MIN, X_MAX + 1):
			var c := Vector2i(x, y)
			if c == u.cell:
				out.append(c)
				continue
			if _grid_free(c) and _cell_dist(c, u.cell) <= dd:
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
		var d := _cell_dist(cc, enemy.cell)
		if d < bd:
			bd = d
			best = cc
	return best

## 冲刺：朝敌逐格推进至邻格 / 被挡前一格 / 冲满步数
func _charge_end_cell(u: BattleUnit, enemy: BattleUnit, dd: int) -> Vector2i:
	var cell := u.cell
	for i in range(maxi(1, dd)):
		if _cell_dist(enemy.cell, cell) <= 1:
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
	if _cur != null:
		_landed(_cur)
		_check_win()
	_wait = false
	_cur = null

## =============== 查询（AI 与 UI 共用） ===============
func _is_human_side(u: BattleUnit) -> bool:
	if not human_mode:
		return false
	if human_teams.is_empty():
		return u.team == human_team
	return human_teams.has(u.team)

func alive_enemies_of(u: BattleUnit) -> Array:
	var out: Array = []
	for x in units:
		if x.alive and x != u and x.team != u.team:
			out.append(x)
	return out

func dist(a: BattleUnit, b: BattleUnit) -> int:
	return _cell_dist(a.cell, b.cell)

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

## 射程内的存活敌人（AI 决策 / UI 目标高亮用；顺序 = units 顺序）
func targets_in_range(u: BattleUnit, slot: int) -> Array:
	var r := skill_range(u, slot)
	var out: Array = []
	for f in alive_enemies_of(u):
		if dist(u, f) <= r:
			out.append(f)
	return out

## 移动可达格：8 方向（含斜向）各 1 步，落在棋盘内且无单位占格
func move_cells_of(u: BattleUnit) -> Array:
	var out: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var d: Vector2i = dv
		var c := u.cell + d
		if c.x < X_MIN or c.x > X_MAX or c.y < Y_MIN or c.y > Y_MAX:
			continue
		var occ := false
		for x in units:
			if x.alive and x != u and x.cell == c:
				occ = true
				break
		if not occ:
			out.append(c)
	return out

## AI 侧执行技能（含位移与打空回滚），语义与 battle.gd 一致
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
	var res: String = u.use_active(slot, {"targets": final_targets, "mode": "4v4"})
	if res != "":
		log.push_back(res)

## 完整结算器：击杀计分（增量）→ 得分制胜利 / 全灭胜负 / 平局。
## quiet=true 用于干推演：只同步计分不判胜负不写日志。
func _check_win(quiet := false) -> void:
	if not quiet and winner != "":
		return
	_reward_kills(quiet)
	if not quiet:
		var rs := int(scores.get(TEAM_RED, 0))
		var bs := int(scores.get(TEAM_BLUE, 0))
		if rs >= WIN_SCORE:
			winner = "红方"
			log.push_back("== 红方率先达到 %d 分，胜出！ ==" % rs)
		elif bs >= WIN_SCORE:
			winner = "蓝方"
			log.push_back("== 蓝方率先达到 %d 分，胜出！ ==" % bs)
		if winner != "":
			return
	var ra := false
	var ba := false
	for u in units:
		if u.alive:
			if u.team == TEAM_RED:
				ra = true
			else:
				ba = true
	if not quiet:
		if not ra and not ba:
			winner = "平局"
		elif not ra:
			winner = "蓝方"
		elif not ba:
			winner = "红方"
		if winner != "":
			log.push_back("== 胜者：%s（第 %d 回合）==" % [winner, round])

## 击杀计分：对比累计死亡增量，每新阵亡一名给对面 +KILL_REWARD
func _reward_kills(quiet := false) -> void:
	var cur := {TEAM_RED: 0, TEAM_BLUE: 0}
	for u in units:
		if not u.alive:
			cur[u.team] = int(cur.get(u.team, 0)) + 1
	for team in cur:
		var d := int(cur[team]) - int(_dead_tally.get(team, 0))
		if d > 0:
			_dead_tally[team] = int(cur[team])
			var foe := 1 if team == TEAM_RED else 0
			scores[foe] = int(scores.get(foe, 0)) + KILL_REWARD * d
			if not quiet:
				log.push_back("== 敌方阵亡 %d 名 → %s +%d 分（总分 %d）==" % [d, "红方" if foe == TEAM_RED else "蓝方", KILL_REWARD * d, int(scores[foe])])

## =============== 得分制 · 星星 ===============
## 空格：棋盘内且无单位站立（含翼列；不含其它星星所在格已判 by star_at? 星星也可重叠? 不重叠生成）
func _empty_cells() -> Array:
	var occ := {}
	for u in units:
		occ[u.cell] = true
	for st in stars:
		occ[(st as Dictionary)["pos"]] = true
	var out: Array = []
	for y in range(Y_MIN, Y_MAX + 1):
		for x in range(X_MIN, X_MAX + 1):
			var c := Vector2i(x, y)
			if not occ.has(c):
				out.append(c)
	return out

## 每回合初刷新：补 1 颗小星（上限 2）；每 5 回合刷 1 颗大星（上限 1）。只落在空格。
func _spawn_stars() -> void:
	var small := 0
	var big := 0
	for st in stars:
		if bool((st as Dictionary).get("big", false)):
			big += 1
		else:
			small += 1
	var cells := _empty_cells()
	if cells.is_empty():
		return
	if small < SMALL_STAR_MAX:
		# 每回合补 1 颗小星（场上不足 2 颗时）
		var c: Vector2i = cells[rng.randi() % cells.size()]
		stars.append({"pos": c, "big": false})
		log.push_back("★ 小星星在 %s 出现（+1 分）" % c)
	elif round % BIG_STAR_EVERY == 0 and big < BIG_STAR_MAX:
		# 每 5 回合补 1 颗大星（场上无大星时）
		var c2: Vector2i = cells[rng.randi() % cells.size()]
		stars.append({"pos": c2, "big": true})
		log.push_back("★ 大星星在 %s 出现（+3 分）" % c2)

## 单位停到星星格 → 拾取得分（quiet 供干推演，不写日志）
func _landed(u: BattleUnit, quiet := false) -> void:
	for i in range(stars.size()):
		var st: Dictionary = stars[i]
		if (st["pos"] as Vector2i) == u.cell:
			var val := BIG_STAR_VAL if bool(st.get("big", false)) else SMALL_STAR_VAL
			stars.remove_at(i)
			scores[u.team] = int(scores.get(u.team, 0)) + val
			if not quiet:
				log.push_back("★ %s 拾取%s星星 +%d 分（%s 总分 %d）" % [
					u.name, "大" if bool(st.get("big", false)) else "小",
					val, "红方" if u.team == TEAM_RED else "蓝方", int(scores[u.team])])
			return

## AI 查询：离某单位最近星星的位置（无则返回 Vector2i(-1,-1)）
func nearest_star(u: BattleUnit) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 9999
	for st in stars:
		var pos: Vector2i = (st as Dictionary)["pos"]
		var d := absi(pos.x - u.cell.x) + absi(pos.y - u.cell.y)
		if d < bd:
			bd = d
			best = pos
	return best

## AI 查询：场上是否有星（供决策分心用）
func has_stars() -> bool:
	return not stars.is_empty()

func result_text() -> String:
	return "\n".join(log)

## =============== 最高难度 · 豆包预案执行 ===============
func _idx_of(u: BattleUnit) -> int:
	for i in range(units.size()):
		if units[i] == u:
			return i
	return -1

## 执行 LLM 给单个单位的预案（move + skill）；返回 true=已按预案行动（不再走本地 AI）
func _exec_llm_plan(u: BattleUnit, plan: Dictionary) -> bool:
	var has_any := false
	if bool(plan.get("has_move", false)):
		has_any = true
		var cell: Vector2i = plan.get("move", Vector2i(-1, -1))
		if cell in move_cells_of(u):
			u.cell = cell
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

## =============== 前瞻推演（normal 1 步 / hard 2 步；easy 不走此路径） ===============
func _turn_lookahead(u: BattleUnit) -> bool:
	var depth := 5 if ai_level == "hard" else 2
	var cands := _lookahead_cands(u)
	if cands.is_empty():
		return false
	var best: Dictionary = {}
	var bs := -1.0e18
	for c in cands:
		var snap := _snapshot_all()
		var ok := _apply_dry(u, c)
		if ok:
			_landed(u, true)
		if ok and depth > 0:
			_sim_followups(u, depth)
		if ok:
			_check_win(true)   # 同步击杀计分（不判胜负不写日志）
		var sc := _eval_board(u.team)
		_restore_all(snap)
		if ok and sc > bs:
			bs = sc
			best = c
	if best.is_empty():
		return false
	_apply_real(u, best)
	return true

## 候选：每个可移动格 ×（不放技 / 各可用非位移技能）
func _lookahead_cands(u: BattleUnit) -> Array:
	var cands: Array = []
	var cells: Array = move_cells_of(u)
	if not (u.cell in cells):
		cells.append(u.cell)
	for c in cells:
		var cc: Vector2i = c
		cands.append({"cell": cc, "slot": 0})
		for slot in range(1, 5):
			if not base_usable(u, slot):
				continue
			if is_dash(u, slot):
				continue   # v1：位移技不进前瞻候选（保留给常规逻辑）
			cands.append({"cell": cc, "slot": slot})
	return cands

## 干推演执行候选（无日志）；返回是否合法可继续
func _apply_dry(u: BattleUnit, c: Dictionary) -> bool:
	var cc: Vector2i = c.get("cell", u.cell)
	if cc != u.cell:
		if not (cc in move_cells_of(u)):
			return false
		u.cell = cc
	var slot := int(c.get("slot", 0))
	if slot < 1:
		return true
	var tg: Array = []
	if not self_skill(u, slot):
		var foes := targets_in_range(u, slot)
		if foes.is_empty():
			return false
		tg = [_weakest_of(foes)]
	u.use_active(slot, {"targets": tg, "mode": "4v4"})
	return true

## 干推演：模拟后续 depth 个单位的常规行动（同难度近似，不递归前瞻）
func _sim_followups(after: BattleUnit, depth: int) -> void:
	var seq: Array = []
	for v in units:
		if v.alive and v != after:
			seq.append(v)
	if seq.is_empty():
		return
	seq = _se.speed_order(seq)
	var n := 0
	for v in seq:
		if n >= depth:
			break
		var vu: BattleUnit = v
		if vu.alive:
			_silent_turn(vu)
		n += 1

## 静默常规回合（无日志）：供推演模拟；位移技跳过。
## 按该单位阵营的真实难度（side_levels）执行 → 我方前瞻时把对手按其实际水平建模。
func _silent_turn(u: BattleUnit) -> void:
	if not u.alive or u.has_flag("stun") or u.has_flag("sanity_break"):
		return
	var saved := ai_level
	var lvl_of := str(side_levels.get(u.team, ""))
	if lvl_of != "" and lvl_of != saved:
		ai_level = lvl_of
	var mv: Dictionary = BattleAI.plan_move(self, u)
	if mv.get("act", "") == "move":
		var cell: Vector2i = mv.get("cell", Vector2i.ZERO)
		if cell in move_cells_of(u):
			u.cell = cell
	var sk: Dictionary = BattleAI.plan_skill(self, u, false)
	if sk.get("act", "") == "skill":
		var slot := int(sk.get("slot", 1))
		if is_dash(u, slot):
			return
		var tg: Array = []
		if not self_skill(u, slot):
			var tgt: BattleUnit = sk.get("target", null)
			if tgt == null or not (tgt in targets_in_range(u, slot)):
				ai_level = saved
				return
			tg = [tgt]
		u.use_active(slot, {"targets": tg, "mode": "4v4"})
	ai_level = saved

## 局势评价（team 视角）
## 价值 = 真实血量 + 盾(折价0.35，盾易碎且会诱导“乌龟流”) + 甲(0.3) + 存活权重 6
## 推进惩罚：单位离最近敌人超过其最大攻击射程的部分按格扣分 → 驱动接敌进攻，
## 避免推演算出“远离战线叠盾”为最优（这是本日志复盘发现的核心缺陷）
func _eval_board(team: int) -> float:
	var sc := 0.0
	# 得分差：每分权重高（≈2.5），推演会为抢星与击杀布局（小星3/大星5分、击杀6分）
	sc += (float(int(scores.get(team, 0))) - float(int(scores.get(1 - team, 0)))) * 2.5
	for v in units:
		if v == null:
			continue
		var val := 0.0
		if v.alive:
			val = float(v.hp) + float(v.shield) * 0.35 + float(v.armor) * 0.3 + 6.0
			var maxr := _max_atk_range(v)
			var dmin := _min_dist_to_enemy(v)
			if dmin > maxr:
				val -= float(dmin - maxr) * 1.2
		sc += val if v.team == team else -val
	return sc

func _max_atk_range(v: BattleUnit) -> int:
	var mr := 1
	for i in range(1, 5):
		var sk := v.get_skill(i)
		if sk == null or self_skill(v, i):
			continue
		mr = maxi(mr, skill_range(v, i))
	return mr

func _min_dist_to_enemy(v: BattleUnit) -> int:
	var foes := alive_enemies_of(v)
	if foes.is_empty():
		return 0
	var bd := 9999
	for f in foes:
		var ff: BattleUnit = f
		bd = mini(bd, absi(ff.cell.x - v.cell.x) + absi(ff.cell.y - v.cell.y))
	return bd

func _weakest_of(foes: Array) -> BattleUnit:
	var best: BattleUnit = null
	var bs := 1.0e18
	for f in foes:
		var ff: BattleUnit = f
		var sc := float(ff.hp + ff.shield)
		if sc < bs:
			bs = sc
			best = ff
	return best

## 真实执行选中的最优候选（带日志）
func _apply_real(u: BattleUnit, c: Dictionary) -> void:
	var cc: Vector2i = c.get("cell", u.cell)
	var moved := false
	if cc != u.cell:
		u.cell = cc
		moved = true
		log.push_back("%s 移动 → %s" % [u.name, cc])
	var slot := int(c.get("slot", 0))
	if slot < 1:
		return
	if not self_skill(u, slot):
		var foes := targets_in_range(u, slot)
		if foes.is_empty():
			return
		var res: String = u.use_active(slot, {"targets": [_weakest_of(foes)], "mode": "4v4"})
		if res != "":
			log.push_back(res)
	else:
		var res2: String = u.use_active(slot, {"targets": [], "mode": "4v4"})
		if res2 != "":
			log.push_back(res2)

## 全局快照（推演回滚用）：单位状态 + 分数 + 星星 + 死亡计数
func _snapshot_all() -> Dictionary:
	var us: Array = []
	for v in units:
		us.append(v.snapshot())
	return {
		"units": us,
		"scores": (scores as Dictionary).duplicate(),
		"stars": (stars as Array).duplicate(true),
		"dead": (_dead_tally as Dictionary).duplicate(),
	}

func _restore_all(s: Dictionary) -> void:
	var us: Array = s.get("units", [])
	for i in range(units.size()):
		if i < us.size():
			units[i].restore(us[i])
	scores = (s.get("scores", scores) as Dictionary).duplicate()
	stars = (s.get("stars", stars) as Array).duplicate(true)
	_dead_tally = (s.get("dead", _dead_tally) as Dictionary).duplicate()
