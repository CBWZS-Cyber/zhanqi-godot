class_name BattleTutorial
extends Battle
## 新手教程 · 战斗管理器（2026-09-28 新增）
##
## 设计原则：**只做加法，不改战斗规则。**
##   · 继承 1V1 的 `Battle`——回合流程、行动顺序、技能执行、伤害结算（盾→甲→血）、
##     状态、理智、胜负判定**全部照旧**，一行不动；
##   · 只覆写两处：
##       `_make()`    —— 让 `"tut_dummy"` 这个 id 走 `TutorialDefs.DUMMY`（而不是 HeroDefs）；
##       `_turn_ai()` —— 木桩的行为（挪动 + 每 N 回合轻击一次）；
##   · 玩家英雄**完全走原路径**（HeroDefs + SkillEffects），技能/护盾/理智一律不变；
##   · 木桩轻击走 `BattleUnit.take_damage()`，所以「盾 → 甲 → 血」照常结算、
##     且会照常发出 `damaged` 信号（掉血飘字等表现层自动生效）。
##
## ⚠️ 教程的「过关」**不依赖 `_check_win`**：木桩血厚（8）是故意打不空的，
##    通关由 `Tutorial` 界面按步骤判定（见 tutorial.gd 的 step gate）。

## 教程棋盘摆位（1V1 有效格 = 主区 x1..3 + 两侧出生列 x0/x4，y1..3）
## 默认 1V1 是 (0,2) vs (4,2) 隔 4 格——教程不需要走那么远，摆近两格。
const PLAYER_START := Vector2i(0, 2)
const DUMMY_START := Vector2i(2, 2)

var dummy: BattleUnit = null      ## 训练木桩（units[1]）
var strike_count := 0             ## 木桩累计轻击次数（教程可用于讲解）
var _dummy_turns := 0             ## 木桩已经行动过的回合数（轻击节流用）
var dummy_weakened := false       ## 是否处于「位移」步的残血窗口内
var dummy_revive_count := 0       ## 木桩被斩杀后自我修复的次数（教程可用于讲解）

func _init(hero_id: String) -> void:
	super(hero_id, TutorialDefs.DUMMY_ID)
	# 教程永远是「玩家(红方 0) 操作 vs 木桩(AI)」。
	# 必须在构造里就设好：不设 human_mode 时 run_step() 会把两边都当 AI、一口气跑完整局，
	# 永远不会停在「轮到玩家」（对局界面是进入时设的，教程这里做成默认值，调用方不用记）。
	human_mode = true
	human_team = 0
	dummy = units[1]
	# 地形必须在**摆位之前**建好：_put() 会 _sync_terrain() 读地形，
	# 否则出生格的地形 id 会残留为 0（"站进森林却按空地算" 的经典静默错算）。
	_build_terrain()
	# 摆近一点（走 _put：落位 + 同步地形 + 恐惧检查，与工程约定一致）
	_put(units[0], PLAYER_START)
	_put(dummy, DUMMY_START)
	log.push_back("教程对局：%s vs 训练木桩（木桩每 %d 回合轻击一次）" % [units[0].name, TutorialDefs.DUMMY_STRIKE_EVERY])


## 建地形层：所有合法格都进格图，再按 TutorialDefs.TERRAIN 铺地形。
##
## 只有 `Terrain.story_active()` 白名单里的地形才真的写进去，其余一律按空地 ——
## 这是本工程既有约定（README 附录 A.2.3「地形启用白名单」），照做即可。
## ⚠️ 建好后必须 `board = _board`：所有地形效果只认基类的这个引用（README 注意点 18）。
func _build_terrain() -> void:
	var b := GridBoard.new()
	for c in _all_tutorial_cells():
		b.add_cell(c)
		var t := TutorialDefs.terrain_at(c)
		b.set_cell_terrain(c, t if Terrain.story_active(t) else Terrain.EMPTY)
	board = b


## 教程棋盘的全部合法格（与 Battle._cell_exists 同一套边界：主区 x1..3 × y1..3 + 两侧出生格）
func _all_tutorial_cells() -> Array:
	var out: Array = []
	for x in range(5):
		for y in range(1, 4):
			if (x == 0 or x == 4) and y != 2:
				continue
			out.append(Vector2i(x, y))
	return out

## 玩家单位（红方）
func player_unit() -> BattleUnit:
	return units[0] if not units.is_empty() else null


## 覆写 1：让木桩 id 走教程自己的定义表，玩家仍走 HeroDefs
func _make(hero_id: String, team: int, cell: Vector2i) -> BattleUnit:
	if hero_id != TutorialDefs.DUMMY_ID:
		return super(hero_id, team, cell)
	var d: Dictionary = TutorialDefs.DUMMY.duplicate(true)
	d["id"] = TutorialDefs.DUMMY_ID          # BattleUnit.def_id 取自 def["id"]
	var u := BattleUnit.new(d)
	u.team = team
	u.cell = cell
	_sync_terrain(u)
	_check_fear(u)
	u.rng = rng
	return u


## 覆写 2：木桩行为（其余单位照旧走原 AI）
func _turn_ai(u: BattleUnit) -> void:
	if u == dummy or (u != null and u.def_id == TutorialDefs.DUMMY_ID):
		_dummy_act(u)
		return
	super(u)


## 木桩行为：够得着且到点 → 轻击；否则朝玩家挪一步。
## 全程只用基类现成能力（`move_cells_of` / `_cell_dist` / `take_damage`），不自造规则。
func _dummy_act(u: BattleUnit) -> void:
	if not u.alive:
		return
	var foe := player_unit()
	if foe == null or not foe.alive:
		return
	_dummy_turns += 1
	var due: bool = (_dummy_turns % TutorialDefs.DUMMY_STRIKE_EVERY) == 0
	if due and _cell_dist(u.cell, foe.cell) <= TutorialDefs.DUMMY_STRIKE_RANGE:
		var res: Dictionary = foe.take_damage(TutorialDefs.DUMMY_STRIKE_DMG, {"attacker": u, "element": u.element})
		strike_count += 1
		log.push_back("训练木桩 轻击 %s：%s" % [foe.name, _strike_text(res)])
		return
	# 朝玩家挪一步（8 方向相邻格，取离玩家最近的那个）
	var cells: Array = move_cells_of(u)
	if cells.is_empty():
		log.push_back("训练木桩 原地不动")
		return
	var best: Vector2i = cells[0]
	var bd := 999
	for c in cells:
		var dd := _cell_dist(c, foe.cell)
		if dd < bd:
			bd = dd
			best = c
	_put(u, best)
	log.push_back("训练木桩 挪动 → %s" % str(best))


## 落位统一入口：落位 + 同步地形 + 恐惧检查
## （工程约定：不要直接写 `u.cell =`，否则地形 id 残留 —— 见 README 注意点 16）
func _put(u: BattleUnit, c: Vector2i) -> void:
	u.cell = c
	_sync_terrain(u)
	_check_fear(u)


# ================= 教程专用：胜负接管 + 残血窗口 =================
#
# 这两件事是**配套**的，拆开任何一个都会让教程出错，原因见 TutorialDefs.DUMMY_LOW_HP 的注释。

## ⚠️ 覆写关键点：**教程不判胜负。**
##
## 基类 `_check_win()` 会在任意一方全灭时置 `winner`，`run_step()` 随即返回 `{"over": ...}`。
## 而教程的「位移」步需要把木桩压到残血（斩杀技才放得出来），玩家完全可能顺手把它斩杀 ——
## 若沿用基类行为，教程会在半途被强行结束（`Tutorial._step()` 见到 over 就调 `_finish(true)`）。
##
## 教程的结束**只由步骤机决定**（走完最后一步 → `_finish(false)`），所以这里清空。
func _check_win(_quiet: bool = false) -> void:
	pass


## 把木桩压到残血，开启「位移」步的斩杀窗口。幂等：重复调用不会继续掉血。
func weaken_dummy() -> void:
	if dummy == null or not dummy.alive:
		return
	dummy.hp = minf(float(TutorialDefs.DUMMY_LOW_HP), dummy.max_hp)
	dummy.shield = 0.0
	dummy_weakened = true
	log.push_back("训练木桩被压到残血（HP %.0f）—— 斩杀类技能现在放得出来" % dummy.hp)


## 修木桩：活着就回满血，已经被斩杀就**复活**（训练木桩"自我修复"）。
##
## ⚠️ 复活只需把 `alive` / `hp` 置回，**不需要手动往回合队列里塞** ——
## `Battle._start_round()` 每回合都按 `u.alive` 重建 `_queue`，下一回合它会自动重新入队
## （这一点是读 battle.gd:74-78 确认过的，不是推测）。
func restore_dummy() -> void:
	if dummy == null:
		return
	var died := not dummy.alive
	if died:
		dummy.alive = true
		dummy_revive_count += 1
	dummy.hp = dummy.max_hp
	dummy.shield = 0.0
	dummy.clear_statuses()
	if died:
		_put(dummy, _free_cell_near(DUMMY_START))
		log.push_back("训练木桩自我修复（教程继续）")
	else:
		log.push_back("训练木桩回复满血")
	dummy_weakened = false


## 从 preferred 开始找第一个没被占用的合法格（复活时避免和玩家叠格）
func _free_cell_near(preferred: Vector2i) -> Vector2i:
	var occupied := {}
	for u in units:
		if u.alive and u != dummy:
			occupied[u.cell] = true
	if not occupied.has(preferred):
		return preferred
	for c in _all_tutorial_cells():
		if not occupied.has(c):
			return c
	return preferred


## 轻击结果文案（给战报用；数值取整，教程里更好读）
func _strike_text(res: Dictionary) -> String:
	if bool(res.get("missed", false)):
		return "被闪避"
	var parts: Array[String] = []
	if float(res.get("absorbed", 0.0)) > 0.0:
		parts.append("护盾吸收 %.0f" % float(res["absorbed"]))
	if float(res.get("reduced", 0.0)) > 0.0:
		parts.append("护甲减免 %.0f" % float(res["reduced"]))
	parts.append("掉血 %.0f" % float(res.get("hp_lost", 0.0)))
	return "，".join(parts)
