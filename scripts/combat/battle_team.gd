class_name BattleTeam
extends BattleBase
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

## ---------- 开局地形生成（2026-09-10 用户设计）----------
## 设计要点：不对称（每局不同）但公平（双方半场价值对等）
##   中央：必刷 1~2 个强地形，类型/数量/具体格随机（"固定中带随机"）
##   半场：左右各随机 2 个，类型随机、位置随机，但两侧价值分相等
##   水域/沙漠（负面地形）不参与随机生成
const TERRAIN_CENTER_COUNT := [1, 2]          # 中央地形数量范围
const TERRAIN_SIDE_MIN := 5                   # 每侧地形总数下限（正+负混合）
const TERRAIN_SIDE_MAX := 8                   # 每侧地形总数上限（弹性更大，便于价值补平）
const TERRAIN_NEG_MIN := 2                    # 每侧负面地形数量下限（保证"负面多一点"）
const TERRAIN_NEG_MAX := 3                    # 每侧负面地形数量上限
const STAR_NEG_BIAS := 70                     # 星星落在负面地形格上的概率（%，诱导冒险）
## 负面地形类型池（每局随机选一种）
const NEG_POOL := [Terrain.WATER, Terrain.SAND]
const TERRAIN_RETRY := 120                    # 价值均衡最大重掷次数（中央偏侧时需更多次才补平）
## 地形价值分（用于两侧均衡；负面地形为负，暂不参与生成）
const TERRAIN_VALUE := {
	Terrain.FOREST: 3, Terrain.SWAMP: 3, Terrain.MOUNTAIN: 4, Terrain.ICE: 2,
	Terrain.WATER: -2, Terrain.SAND: -2, Terrain.SNOW: 0,
}
## 中央强地形候选（权重）
const CENTER_POOL := [Terrain.MOUNTAIN, Terrain.MOUNTAIN, Terrain.ICE, Terrain.ICE, Terrain.FOREST]
## 半场地形候选（权重）
const SIDE_POOL := [Terrain.FOREST, Terrain.FOREST, Terrain.SWAMP, Terrain.SWAMP,
	Terrain.MOUNTAIN, Terrain.MOUNTAIN, Terrain.ICE]
var terrain_summary := ""     # 本局地形摘要（日志用）

var enable_lookahead := true  # 前瞻开关（测试/批量模拟可关掉提速，不影响决策公平性）
var scores := {0: 0, 1: 0}    # 得分制：{team: 分数}
var stars: Array = []         # 场上星星：[{pos: Vector2i, big: bool}]
var _dead_tally := {0: 0, 1: 0}  # 累计死亡数（用于击杀计分增量）

func _init(red_ids: Array, blue_ids: Array) -> void:
	_hd = load("res://scripts/combat/hero_defs.gd")
	_se = load("res://scripts/combat/skill_effects.gd")
	rng.randomize()
	max_rounds = 120
	child_limit = 5
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
	_setup_standard_board()   # 建立含地形层的标准棋盘
	_roll_terrain()           # 开局地形生成（不对称但价值均衡）
	if terrain_summary != "":
		log.push_back("⚡ 本局地形：" + terrain_summary)
	for u in units:
		_sync_terrain(u)
		log.push_back("· %s 出生 %s（速%d）" % [u.name, u.cell, u.effective_speed()])

## 联机确定性随机：开局包设定同一种子 → 双方引擎随机结果一致
func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	var def: Dictionary = (_hd.ALL.get(hero_id, _hd.ALL.get("demo_hero", {})) as Dictionary).duplicate(true)
	def["id"] = hero_id
	var u := BattleUnit.new(def)
	u.team = team
	u.cell = cell
	_sync_terrain(u)   # 地形：落位后同步所在地形（BattleBase 提供）
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
			# 人类方失控：理智为负时同样强制随机放技（旧版失控只挂在 _turn_ai，人类辛克莱理智会一路跌到负几十不触发）
			if actor.sanity < 0:
				_crazy(actor)
				_check_win()
				continue
			_wait = true
			_h_moved = false
			_cur = actor
			return {"wait": actor}
		_turn_ai(actor)
		_landed(actor)      # 拾取星星（若停到星格）
		_check_win()        # 击杀计分 / 20 分 / 全灭 判定
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
	_spawn_stars()
	# 2026-09-05 v2 调整：改为"每步现场决策"——回合初不再批量预生成预案，
	# 每个 AI 单位行动前在 _turn_ai 中现问豆包（见 _maybe_llm_plan(u)）

## 最高难度：为单个 AI 单位现场生成豆包预案（同步阻塞 ~1-4s/次）
## v2：由 _turn_ai 在每个单位行动前调用，只决策当前单位 → 每步都基于最新局面重新思考
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
			# 地形：移出代价（能量不足则放弃移动）+ 冰面滑行 + 同步
			if _terrain_exit_gate(u) == "":
				var odir := cell - u.cell
				u.cell = cell
				u.cell = _terrain_slide(u, u.cell, odir)
				_sync_terrain(u)
				_check_fear(u)
				moved = true
				_check_fear(u)
				log.push_back("%s 移动 → %s" % [u.name, u.cell])
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
	var all: Array = []
	for x in units:
		# 失控敌我不分，但绝不会打到自己（设计稿：失控只是敌我不分）
		if x.alive and x != u:
			all.append(x)
	if all.is_empty():
		u.add_flag("sanity_outbreak")
		return
	u.add_flag("sanity_outbreak")   # 回合末 _apply_tefx 据此把理智归零
	var slot := 1 + (rng.randi() % 4)
	var res: String = u.use_active(slot, {"targets": all, "mode": "4v4", "battle": self, "allies": _allies_within(u, 1)})
	log.push_back("【失控】%s 不受控制地释放技能：%s" % [u.name, res])

## =============== 人类操作接口 ===============
func human_cast(slot: int, enemy: BattleUnit = null, landing := Vector2i(-1, -1), extra_targets: Array = []) -> String:
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
	# 蔓延（虞美人）：不移动本体，改为在相邻空格生成子体，不消耗行动次数
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
	var charge_hit: BattleUnit = null   # 冲刺撞到的单位
	var aimed := false                  # 玩家是否主动指定了冲刺方向
	# 地形：水域/沙地禁止位移类技能（2026-09-10）
	var dgate := _terrain_dash_gate(u, slot)
	if dgate != "":
		return dgate

	if is_dash(u, slot) and dd > 0:
		if is_charge(u, slot):
			# 冲刺：既可点敌人，也可点任意格作为 8 方向。
			# 旧版强制 enemy != null，想"选个方向冲出去"的玩家会被直接取消（"冲刺需点敌人"）。
			var aim := u.cell
			if landing != Vector2i(-1, -1):
				aim = landing
				aimed = true
			elif enemy != null:
				aim = enemy.cell
			if aim == u.cell:
				return "!冲刺需要选择一个方向（点要冲去的格子或敌人）"
			var cr: Dictionary = _charge_along(u, aim, dd)
			dest = cr["cell"]
			charge_hit = cr["hit"]
		else:
			dest = landing if (landing in landable_cells(u, dd)) else _best_land_cell(u, enemy, dd)
	# 位移落点可达性预检：失败则不移动
	var rng := skill_range(u, slot)
	var can := true
	if not self_skill(u, slot):
		if land_aoe(u, slot):
			can = true
		elif charge_hit != null and charge_hit.team != u.team:
			can = true   # 撞上了就是命中，无需再判射程
		elif aimed:
			can = true   # 玩家主动选方向的纯位移冲刺：允许不打到人（位移本身就是效果）
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
	# 目标：撞到的单位 > 群体(AOE) > 指定敌人 > 射程内最近敌人
	# 注意顺序：land_aoe 优先于 enemy。旧版先判 enemy，导致药师寿瘟祸祖/药灵这类
	# "对附近敌人群伤"的技能只打到玩家点的那 1 个人，与技能描述不符。
	var targets: Array = []
	if not self_skill(u, slot):
		if land_aoe(u, slot):
			targets = _enemies_within(u, 1)
		elif charge_hit != null and charge_hit.team != u.team:
			targets = [charge_hit]
		elif not extra_targets.is_empty():
			# 多目标技（追猎流炎飞弹等）：玩家点选的多个目标
			var cap := max_targets_of(u, slot)
			for t in extra_targets:
				var tu := t as BattleUnit
				if tu != null and tu.alive and tu.team != u.team and targets.size() < cap:
					targets.append(tu)
		elif enemy != null:
			targets = [enemy]
		else:
			for f in alive_enemies_of(u):
				if _cell_dist(u.cell, f.cell) <= rng:
					targets.append(f)
					break
	var res: String = u.use_active(slot, {"targets": targets, "mode": "4v4", "battle": self, "allies": _allies_within(u, 1)})
	if res != "":
		log.push_back(res)
	_finish_human()
	return res

## =============== 真位移（落格） ===============
## 普通位移 = 跃迁：跳到 dash_dist 内任意合法空格（无视路径；落地格必须无阻挡/无单位）
## 冲刺 = 朝目标方向逐格冲，停在被挡前一格 / 目标邻格 / 冲满
## 格距：切比雪夫距离（斜对角算 1 格）——与 8 方向移动一致。
## 旧版用曼哈顿距离，导致斜对角的敌人"看着在旁边"却判定为距离 2、打不到。
## 标准 4V4 棋盘上是否存在该格（整板 x0..9 / y1..8，含翼列）
## 格子是否存在：主区 x1..8 全高（8×8）；两翼 x0/x9 只保留出生行 y3..6 四格。
## 旧版两翼整列（y1..8）都可通行，视觉上成了 10×8 大棋盘，星星也会刷进翼格。
func _cell_exists(cell: Vector2i) -> bool:
	if cell.y < Y_MIN or cell.y > Y_MAX:
		return false
	if cell.x >= 1 and cell.x <= 8:
		return true
	if cell.x == X_MIN or cell.x == X_MAX:
		return cell.y >= 3 and cell.y <= 6
	return false

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

func _unit_at_cell(cell: Vector2i) -> BattleUnit:
	for x in units:
		if x.alive and x.cell == cell:
			return x
	return null

## 冲刺方向：由施法者指向目标格的单位方向（8 方向，支持斜向）
func _charge_dir_of(u: BattleUnit, aim: Vector2i) -> Vector2i:
	var dx := aim.x - u.cell.x
	var dy := aim.y - u.cell.y
	if dx == 0 and dy == 0:
		return Vector2i.ZERO
	return Vector2i(1 if dx > 0 else (-1 if dx < 0 else 0),
					1 if dy > 0 else (-1 if dy < 0 else 0))

## 沿 8 方向逐格冲刺：撞到棋子 / 越界 / 冲满步数即停。
## 返回 {"cell": 落点, "hit": 撞到的单位(可空)}。
## 旧版 _charge_end_cell 只走单轴（先x后y），斜向敌人会冲偏导致落地后超出射程、技能被静默取消。
func _charge_along(u: BattleUnit, aim: Vector2i, dd: int) -> Dictionary:
	var dir := _charge_dir_of(u, aim)
	if dir == Vector2i.ZERO:
		return {"cell": u.cell, "hit": null}
	var cell := u.cell
	var hit: BattleUnit = null
	for _i in range(maxi(1, dd)):
		var nxt := cell + dir
		if not _cell_exists(nxt):
			break
		var blocker := _unit_at_cell(nxt)
		if blocker != null:
			hit = blocker
			break
		cell = nxt
	return {"cell": cell, "hit": hit}

## 冲刺可选落点（8 方向逐格展开），供 UI 高亮
func charge_aim_cells(u: BattleUnit, dd: int) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for dir in dirs:
		var cell := u.cell
		for _i in range(maxi(1, dd)):
			var nxt: Vector2i = cell + dir
			if not _cell_exists(nxt) or _unit_at_cell(nxt) != null:
				break
			cell = nxt
			out.append(cell)
	return out

func _finish_human() -> void:
	if _cur != null:
		_landed(_cur)
		_check_win()
	_wait = false
	_cur = null

## =============== 查询（AI 与 UI 共用） ===============
## 该技能一次最多可选几个目标（默认 1；如追猎流炎飞弹 = 2）
func max_targets_of(u: BattleUnit, slot: int) -> int:
	var sk := u.get_skill(slot)
	if sk == null:
		return 1
	return maxi(1, int(skill_data(sk.id).get("max_targets", 1)))

## 射程内的存活敌人（AI 决策 / UI 目标高亮用；顺序 = units 顺序）
## 移动可达格：8 方向（含斜向）各 1 步，落在棋盘内且无单位占格
## 开局第 1 回合每棋可一次走 2 格（加快开局展开），之后恢复 1 格
const OPENING_MOVE_STEPS := 2

func move_cells_of(u: BattleUnit) -> Array:
	var steps := OPENING_MOVE_STEPS if round <= 1 else 1
	var out: Array = []
	for dy in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			if dx == 0 and dy == 0:
				continue
			# 切比雪夫距离：与 8 方向移动一致（斜对角算 1 格）
			if maxi(absi(dx), absi(dy)) > steps:
				continue
			var c := u.cell + Vector2i(dx, dy)
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
	var res: String = u.use_active(slot, {"targets": final_targets, "mode": "4v4", "battle": self, "allies": _allies_within(u, 1)})
	if res != "":
		log.push_back(res)

## 完整结算器：击杀计分（增量）→ 得分制胜利 / 全灭胜负 / 平局。
## quiet=true 用于干推演：只同步计分不判胜负不写日志。
func _check_win(quiet := false) -> void:
	# 虞美人母体阵亡 → 其子体瞬间枯萎
	for mu in units:
		if mu.def_id == "yu_mei_ren" and not mu.has_flag("子体") and not mu.alive:
			for cu in units:
				if cu.has_flag("子体") and cu.team == mu.team and cu.alive:
					cu.hp = 0.0
					cu.alive = false
					log.push_back("虞美人阵亡，其子体随之枯萎")

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
		if u.alive and not u.has_flag("子体"):
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
## ---------- 开局地形生成实现 ----------
## 标准 4V4 棋盘所有合法格（与 _cell_exists 一致）
func _all_cells() -> Array:
	var out: Array = []
	for x in range(X_MIN, X_MAX + 1):
		for y in range(Y_MIN, Y_MAX + 1):
			var c := Vector2i(x, y)
			if _cell_exists(c):
				out.append(c)
	return out

## 建立含地形层的棋盘（board 未注入时）
func _setup_standard_board() -> void:
	if board != null:
		return
	board = GridBoard.new()
	for c in _all_cells():
		board.add_cell(c)

## 中央区（主区正中 2×2 附近）：中央强地形候选位置
func _center_cells() -> Array:
	return [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]

## 开局地形生成：中央固定带随机 + 半场随机但价值均衡
func _roll_terrain() -> void:
	if board == null:
		return
	board.clear_terrain()
	# —— 中央：必刷 1~2 个强地形，**位置/数量/类型全随机（不对称）** ——
	# 公平不靠对称，而靠价值分：中央偏一侧的收益，会在半场用等价值补回（见下方均衡）
	var used: Array = []
	var center_pool := _center_cells().duplicate()
	center_pool.shuffle()
	var n_center: int = TERRAIN_CENTER_COUNT[0] + (rng.randi() % (TERRAIN_CENTER_COUNT[1] - TERRAIN_CENTER_COUNT[0] + 1))
	n_center = mini(n_center, center_pool.size())
	var center_lv := 0
	var center_rv := 0
	for i in range(n_center):
		var c: Vector2i = center_pool[i]
		var tid: int = CENTER_POOL[rng.randi() % CENTER_POOL.size()]
		board.set_cell_terrain(c, tid)
		used.append(c)
		if c.x <= 4:
			center_lv += int(TERRAIN_VALUE.get(tid, 0))
		else:
			center_rv += int(TERRAIN_VALUE.get(tid, 0))
	# —— 半场：混合池（正面 + 本局负面类型），左右**数量与类型都不必等量**，
	#     仅以「价值分」均衡：一侧负面多 → 另一侧好地形多 → 总分持平（2026-09-10 用户设计）
	var banned := _spawn_and_reserved_cells()
	var neg_tid: int = NEG_POOL[rng.randi() % NEG_POOL.size()]
	var left_cells := _half_cells(true, banned, used)
	var right_cells := _half_cells(false, banned, used)
	var best_left: Array = []
	var best_right: Array = []
	var best_diff := 99999
	for attempt in range(TERRAIN_RETRY):
		var n_l: int = TERRAIN_SIDE_MIN + rng.randi() % (TERRAIN_SIDE_MAX - TERRAIN_SIDE_MIN + 1)
		var n_r: int = TERRAIN_SIDE_MIN + rng.randi() % (TERRAIN_SIDE_MAX - TERRAIN_SIDE_MIN + 1)
		var li := _pick_cells(left_cells, n_l)
		var ri := _pick_cells(right_cells, n_r)
		# 每侧强制 2~3 个负面地形（本局统一负面类型），其余为正面 → 保证"负面多一点"
		var n_neg_l: int = TERRAIN_NEG_MIN + rng.randi() % (TERRAIN_NEG_MAX - TERRAIN_NEG_MIN + 1)
		var n_neg_r: int = TERRAIN_NEG_MIN + rng.randi() % (TERRAIN_NEG_MAX - TERRAIN_NEG_MIN + 1)
		var lty: Array = []
		var lv := center_lv      # 基线：中央已贡献的价值
		for i in range(li.size()):
			var t: int = neg_tid if i < n_neg_l else SIDE_POOL[rng.randi() % SIDE_POOL.size()]
			lty.append(t)
			lv += int(TERRAIN_VALUE.get(t, 0))
		var rty: Array = []
		var rv := center_rv      # 基线：中央已贡献的价值
		for i in range(ri.size()):
			var t2: int = neg_tid if i < n_neg_r else SIDE_POOL[rng.randi() % SIDE_POOL.size()]
			rty.append(t2)
			rv += int(TERRAIN_VALUE.get(t2, 0))
		var df := absi(lv - rv)
		if df < best_diff:
			best_diff = df
			best_left = [li, lty]
			best_right = [ri, rty]
		if df == 0:
			break
	# 应用两侧地形（含正面与本局负面类型）
	var names_tally := {}
	if best_left.size() == 2:
		var li: Array = best_left[0]
		var lty: Array = best_left[1]
		for i in range(li.size()):
			board.set_cell_terrain(li[i], int(lty[i]))
	if best_right.size() == 2:
		var ri: Array = best_right[0]
		var rty: Array = best_right[1]
		for i in range(ri.size()):
			board.set_cell_terrain(ri[i], int(rty[i]))
	# —— 摘要日志 ——
	for c in _all_cells():
		var tid2: int = board.terrain_at(c)
		if tid2 > 0:
			var nm := Terrain.name_of(tid2)
			names_tally[nm] = int(names_tally.get(nm, 0)) + 1
	var parts: Array = []
	for nm in names_tally:
		parts.append("%s×%d" % [nm, int(names_tally[nm])])
	terrain_summary = "、".join(parts)

## 星星落点偏好：STAR_NEG_BIAS% 概率优先落在负面地形格（水域/沙漠）上——
## 制造"高风险高回报"：想要武器就得冒险踩负面地形（2026-09-10 用户设计）
func _star_cell_pref(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i(-9, -9)
	var neg_cells: Array = []
	for c in cells:
		var tid: int = board.terrain_at(c) if board != null else 0
		if Terrain.end_turn_hp_loss(tid) > 0.0 or Terrain.end_turn_energy_loss(tid) > 0 or Terrain.dash_blocked(tid):
			neg_cells.append(c)
	if not neg_cells.is_empty() and rng.randi() % 100 < STAR_NEG_BIAS:
		return neg_cells[rng.randi() % neg_cells.size()]
	return cells[rng.randi() % cells.size()]

## 随机挑 n 个格（不足则全取）
func _pick_cells(cells: Array, n: int) -> Array:
	var pool := cells.duplicate()
	pool.shuffle()
	var out: Array = []
	for i in range(mini(n, pool.size())):
		out.append(pool[i])
	return out

## 出生点 / 星格 等禁止生成地形的格
func _spawn_and_reserved_cells() -> Array:
	var out: Array = []
	for c in SPAWN_RED:
		out.append(c)
	for c in SPAWN_BLUE:
		out.append(c)
	for st in stars:
		out.append((st as Dictionary).get("pos", Vector2i(-9, -9)))
	# 出生点周围 1 格也不放（保证开局活动空间）
	var grown: Array = []
	for c in SPAWN_RED + SPAWN_BLUE:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				grown.append(c + Vector2i(dx, dy))
	return out + grown

## 取某一侧的可用格（left=true 取 x1..4，false 取 x5..8），排除禁用格与已用格
func _half_cells(left: bool, banned: Array, used: Array) -> Array:
	var out: Array = []
	for c in _all_cells():
		if c.x < 1 or c.x > 8:
			continue                      # 只算主区；出生列不放地形
		var is_left: bool = c.x <= 4
		if is_left != left:
			continue
		if banned.has(c) or used.has(c):
			continue
		if _center_cells().has(c):
			continue
		out.append(c)
	return out


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
			if not _cell_exists(c):
				continue
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
		# 每回合补 1 颗小星（场上不足 2 颗时）→ 内含随机神器
		var c: Vector2i = _star_cell_pref(cells)
		var wid := _random_weapon_of_tier(Weapons.TIER_ARTIFACT)
		stars.append({"pos": c, "big": false, "weapon": wid})
		log.push_back("★ 小星星在 %s 出现（内含【%s】）" % [c, Weapons.name_of(wid)])
	elif round % BIG_STAR_EVERY == 0 and big < BIG_STAR_MAX:
		# 每 5 回合补 1 颗大星（场上无大星时）→ 内含随机超神器
		var c2: Vector2i = _star_cell_pref(cells)
		var wid2 := _random_weapon_of_tier(Weapons.TIER_SUPER)
		stars.append({"pos": c2, "big": true, "weapon": wid2})
		log.push_back("★ 大星星在 %s 出现（内含【%s】）" % [c2, Weapons.name_of(wid2)])

## 单位停到星星格 → 拾取得分 + 获得武器（quiet 供干推演，不写日志）
## 计分是 4V4 结束条件（比分达标）的必需来源，不可省略
func _landed(u: BattleUnit, quiet := false) -> void:
	for i in range(stars.size()):
		var st: Dictionary = stars[i]
		if (st["pos"] as Vector2i) == u.cell:
			var is_big := bool(st.get("big", false))
			var val := BIG_STAR_VAL if is_big else SMALL_STAR_VAL
			var wid := str(st.get("weapon", ""))
			stars.remove_at(i)
			scores[u.team] = int(scores.get(u.team, 0)) + val
			var wtxt := ""
			if wid != "":
				var err := u.add_equipment(wid)
				wtxt = ("并获得【%s】" % Weapons.name_of(wid)) if err == "" else ("（【%s】%s）" % [Weapons.name_of(wid), err.trim_prefix("!")])
			if not quiet:
				log.push_back("★ %s 拾取%s星星 +%d 分（%s 总分 %d）%s" % [
					u.name, "大" if is_big else "小", val,
					"红方" if u.team == TEAM_RED else "蓝方", int(scores[u.team]), wtxt])
			return

## 从指定档位随机抽一件武器 id（星星投放用）
func _random_weapon_of_tier(tier: String) -> String:
	var ids: Array = Weapons.ids_of_tier(tier)
	if ids.is_empty():
		return ""
	return str(ids[rng.randi() % ids.size()])

## 某格上的星星（无则空字典）——供「右键星格查看内含武器」使用
func star_at(c: Vector2i) -> Dictionary:
	for st in stars:
		if (st as Dictionary).get("pos", Vector2i(-9, -9)) == c:
			return st as Dictionary
	return {}

## AI 查询：离某单位最近星星的位置（无则返回 Vector2i(-1,-1)）
func nearest_star(u: BattleUnit) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 9999
	for st in stars:
		var pos: Vector2i = (st as Dictionary)["pos"]
		var d := _cell_dist(pos, u.cell)
		if d < bd:
			bd = d
			best = pos
	return best

## AI 查询：场上是否有星（供决策分心用）
func has_stars() -> bool:
	return not stars.is_empty()

## =============== 最高难度 · 豆包预案执行 ===============
## 执行 LLM 给单个单位的预案（move + skill）；返回 true=已按预案行动（不再走本地 AI）
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
	if not u.alive or u.has_flag("stun") or u.sanity < 0:
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
			_check_fear(u)
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
		bd = mini(bd, _cell_dist(ff.cell, v.cell))
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

## ========== 虞美人·蔓延子体 / 恐惧 ==========


## 蔓延可选格：相邻（切比雪夫1）空格，且该格无自己的子体（子体非实体不挡格，需显式排除）
## 在指定格生成一个子体（hp 5，不可操控，可被击杀）
## 同队存活单位（含自己），切比雪夫 r 内；情愫等友方治疗用
## 恐惧触发：带恐惧的单位移动到虞美人（母体/子体）3×3 内 → 层数×0.5 真伤并清空
## 虞美人回合末：治疗光环（3×3 友方回 20% 最大生命）+ 刷新「你不再爱我」庇佑标记

## 子体自动行动：暗影刺 —— 对相邻（切比雪夫1）所有敌人各造成 1 点暗系伤害