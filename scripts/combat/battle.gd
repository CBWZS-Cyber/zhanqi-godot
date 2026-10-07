class_name Battle
extends BattleBase
## 战棋 · 战斗管理器（1V1，3×3 主区 + 左右出生格）
## 回合结构：每棋每回合 = 移动权 + 技能权（先移后放、各自可选；位移技不限制在未移动时使用）
## 驱动方式：
##   - run_step() 自动结算直到“轮到人类/分出胜负”，返回状态
##   - 人类回合：human_move(cell) → human_cast(slot, enemy) / human_done()
##   - AI 回合：BattleAI 自动决策（plan_move + plan_skill）
## simulate() = 全自动（测试用）

const SPAWN_RED := Vector2i(0, 2)
const SPAWN_BLUE := Vector2i(4, 2)


func _init(red_hero_id: String, blue_hero_id: String) -> void:
	rng.randomize()
	units = [_make(red_hero_id, 0, SPAWN_RED), _make(blue_hero_id, 1, SPAWN_BLUE)]
	log.push_back("对局开始：红方 %s（速%d）vs 蓝方 %s（速%d）" % [units[0].name, units[0].speed, units[1].name, units[1].speed])

## 联机确定性随机源：开局包设定同一种子 → 双方引擎随机结果一致
func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	var u := BattleUnit.new(HeroDefsScript.ALL[hero_id].duplicate(true))
	u.team = team
	u.cell = cell
	_sync_terrain(u)
	_check_fear(u)
	u.rng = rng
	return u

## 全自动跑完整局（测试用）
## 步进：结算至“人类待操作”或“对局结束”。
func run_step() -> Dictionary:
	while winner == "" and round < max_rounds:
		if _queue.is_empty():
			# 修复：队列空 = 本回合行动完毕。旧版直接 _start_round 跳过了回合末结算，
			# 导致灼烧/流血衰减、膏腴、理智回复与失控归零、剑域、掠夺解锁等
			# 所有 end_turn 机制在真实对局中从未执行（单测直调 end_turn 掩盖了这一点）。
			if round > 0:
				_end_round()
				if winner != "":
					break
			_start_round()
		var actor := _poll_next()
		if actor == null:
			continue
		if actor.has_flag("子体"):
			_child_act(actor)
			continue
		if _is_human_side(actor):
			if actor.has_flag("stun"):
				log.push_back("%s 酒醉/眩晕，跳过本回合" % actor.name)
				continue
			if actor.sanity < 0:
				_crazy(actor)
				_check_win()
				continue
			_wait = true
			_h_moved = false
			_cur = actor
			return {"wait": actor}
		_turn_ai(actor)
		_check_win()   # 每次行动后立刻判胜负（避免“已全灭仍继续”）
	if winner == "":
		winner = "僵局（%d 回合超时）" % max_rounds
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
	# 2026-09-05 v2 调整：改为"每步现场决策"——回合初不再预生成预案，
	# 每个 AI 单位行动前在 _turn_ai 中现问豆包（见 _maybe_llm_plan(u)）

## 最高难度：为单个 AI 单位现场生成豆包预案（同步阻塞 ~1-4s/次）
## v2：由 _turn_ai 在每个单位行动前调用，只决策当前单位 → 每步基于最新局面重新思考
func _turn_ai(u: BattleUnit) -> void:
	if not u.alive:
		return
	if u.has_flag("stun"):
		log.push_back("%s 被眩晕，跳过本回合" % u.name)
		return
	if u.sanity < 0:
		_crazy(u)
		return
	# 最高难度·豆包：每个 AI 单位行动前现场问豆包（v2，每步现想）；失败回退本地 AI
	if ai_level == "hard" and ai_backend == "llm":
		_maybe_llm_plan(u)
		if _llm_plans.has(str(_idx_of(u))):
			if _exec_llm_plan(u, _llm_plans[str(_idx_of(u))]):
				return
	var moved := false
	var mv: Dictionary = BattleAI.plan_move(self, u)
	if mv.get("act", "") == "move":
		var cell: Vector2i = mv.get("cell", Vector2i.ZERO)
		if cell in move_cells_of(u):
			# 地形：移出代价（能量不足则 AI 放弃本次移动）
			if _terrain_exit_gate(u) == "":
				var _odir := cell - u.cell
				u.cell = cell
				u.cell = _terrain_slide(u, u.cell, _odir)
				_sync_terrain(u)
				_check_fear(u)
				moved = true
				_check_fear(u)
				log.push_back("%s 移动 → %s" % [u.name, u.cell])
	var sk: Dictionary = BattleAI.plan_skill(self, u, moved)
	if sk.get("act", "") == "skill":
		var tg: BattleUnit = sk.get("target", null)
		var tgs: Array = sk.get("targets", [])
		if tgs.is_empty() and tg != null:
			tgs = [tg]
		_exec_skill(u, int(sk.get("slot", 1)), tgs, moved)

func _crazy(u: BattleUnit) -> void:
	var all: Array = []
	for x in units:
		# 失控不分敌我，但绝不会打到自己（设计稿：失控只是敌我不分）
		if x.alive and x != u:
			all.append(x)
	u.add_flag("sanity_outbreak")   # 回合末 _apply_tefx 据此把理智归零
	var slot := 1 + (rng.randi() % 4)
	var res: String = u.use_active(slot, {"targets": all, "mode": "1v1", "battle": self, "allies": _allies_within(u, 1)})
	log.push_back("【失控】%s 不受控制地释放技能：%s" % [u.name, res])

## =============== 人类操作接口 ===============
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
	if is_spread(u, slot):
		if landing == Vector2i(-1, -1) or _cell_dist(landing, u.cell) != 1 or not _grid_free(landing):
			return "!蔓延目标需为相邻空格"
		if u.spread_used >= 2:
			return "!本回合蔓延次数已用完（2/2）"
		var _cc := 0
		for _x in units:
			if _x.has_flag("子体") and _x.team == u.team:
				_cc += 1
		if _cc >= child_limit:
			return "!子体已达上限（%d）" % child_limit
		u.spread_used += 1
		var child := spawn_child(u, landing)
		log.push_back("%s 蔓延出子体（HP %.0f）于 %s（本回合 %d/2）" % [u.name, child.hp, landing, u.spread_used])
		return "%s 蔓延出子体于 %s（本回合 %d/2，不消耗行动）" % [u.name, landing, u.spread_used]
	var dd := dash_dist_of(u, slot)
	# 地形：水域/沙地禁止位移类技能
	var _dg := _terrain_dash_gate(u, slot)
	if _dg != "":
		return _dg

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
		_sync_terrain(u)   # 地形：位移后同步所在地形
		_check_fear(u)
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
	var res: String = u.use_active(slot, {"targets": targets, "mode": "1v1", "battle": self, "allies": _allies_within(u, 1)})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

## =============== 真位移（落格） ===============
## 普通位移 = 跃迁：跳到 dash_dist 内任意合法空格（无视路径；落地格必须无阻挡/无单位）
## 冲刺（辛克莱等）= 朝目标方向逐格冲，停在被挡前一格 / 目标邻格 / 冲满
## 格距：切比雪夫距离（斜对角算 1 格）——与 8 方向移动一致。
## 旧版用曼哈顿距离，导致斜对角的敌人"看着在旁边"却判定为距离 2、打不到。
func _cell_exists(cell: Vector2i) -> bool:
	if cell.x >= 1 and cell.x <= 3:
		return cell.y >= 1 and cell.y <= 3
	if cell.x == 0 or cell.x == 4:
		return cell.y == 2   # 两侧各 1 个出生格
	return false

## 跃迁可达格（距离<=dd 的合法空格，可含原地）
func landable_cells(u: BattleUnit, dd: int) -> Array:
	var out: Array = []
	for y in range(1, 4):
		for x in range(0, 5):
			var c := Vector2i(x, y)
			if c == u.cell:
				out.append(c)
				continue
			if _grid_free(c) and _cell_dist(c, u.cell) <= dd:
				out.append(c)
	return out

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

func _finish_human() -> void:
	_wait = false
	_cur = null

## =============== 查询（AI 与 UI 共用） ===============
func move_cells_of(u: BattleUnit) -> Array:
	var out: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var d: Vector2i = dv
		var c := u.cell + d
		# 必须落在有效格（主区 3×3 + 两侧各 1 个出生格）。旧版用宽松 y1..3 边界，
		# 把出生列上下"幽灵格"也算可走，棋子会走进 UI 空占位格（2026-09-08 修复）
		if not _cell_exists(c):
			continue
		var occ := false
		for x in units:
			if x.alive and x != u and x.cell == c and not x.non_solid and not u.non_solid:
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
			_check_fear(u)
		else:
			u.cell = _best_land_cell(u, t0, dd)
			_check_fear(u)
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
	var res: String = u.use_active(slot, {"targets": final_targets, "mode": "1v1", "battle": self, "allies": _allies_within(u, 1)})
	if res != "":
		log.push_back(res)

func _check_win(_quiet: bool = false) -> void:
	if winner != "":
		return
	# 虞美人母体阵亡 → 其子体瞬间枯萎
	for mu in units:
		if mu.def_id == "yu_mei_ren" and not mu.has_flag("子体") and not mu.alive:
			for cu in units:
				if cu.has_flag("子体") and cu.team == mu.team and cu.alive:
					cu.hp = 0.0
					cu.alive = false
					log.push_back("虞美人阵亡，其子体随之枯萎")
	var ra := false
	var ba := false
	for u in units:
		if u.alive and not u.has_flag("子体"):
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

## =============== 最高难度 · 豆包预案执行 ===============
## 执行 LLM 给单个单位的预案（move + skill）；返回 true=已按预案行动
## ========== 虞美人·蔓延子体 / 恐惧 ==========


## 蔓延可选格：相邻（切比雪夫1）空格，且该格无自己的子体（子体非实体不挡格，需显式排除）
## 虞美人回合末：治疗光环（3×3 友方回 20% 最大生命）+ 刷新「你不再爱我」庇佑标记

## 子体自动行动：暗影刺 —— 对相邻（切比雪夫1）所有敌人各造成 1 点暗系伤害