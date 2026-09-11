class_name BattleAI
extends RefCounted
## 战棋 · AI 操纵系统 v4（难度分层 · 集火强化）
## 回合规则：每棋一回合 = 移动权 + 技能权（先移后放、各自可选）
## 难度（读 battle.ai_level，默认 easy）：
##   easy  ：基础型：就近交火、技能先大招、很少保命（保留旧版观感，偶发失误）
##   normal：战斗型：全队集火共识、残血优先、低血自保、走位权衡敌情
##   hard  ：进取型：集火更坚决（偏切治疗/自疗单位）、更早自保、远程保持距离
## 集火共识 _team_focus：同队各单位算出同一目标（评分与本单位无关），形成多打一滚雪球；
##   豆包 llm_tactics.focus 存在时以它为最高优先（指挥官指令）。
## Battle 提供视图 → AI 决策动作 dict → Battle 权威执行

## 移动阶段：返回 move dict 或 {}（不动）
static func plan_move(battle, actor: BattleUnit) -> Dictionary:
	if actor == null or not actor.alive:
		return {}
	var lvl := _lvl(battle)
	var foes: Array = battle.alive_enemies_of(actor)
	if foes.is_empty():
		return {}
	# 大招已充能但当前位置够不着 → 主动走进大招射程。
	# 否则像药师这类“小技能 range2 / 大招 range1”的单位会因 _ranged_ready 命中而永远原地放小技能，
	# 能量攒到几百也放不出大招。easy 保持原莽夫走位，不启用。
	if lvl != "easy" and _ult_ready_but_out_of_range(battle, actor):
		var uc: Vector2i = _step_into_range(battle, actor, foes, 4)
		if uc != actor.cell:
			return {"act": "move", "cell": uc}
	# 已有可命中的技能与目标 → 倾向原地输出（easy 一律原地；normal+ 还要看是否需要保持/拉近距离）
	if _ranged_ready(battle, actor):
		if lvl == "easy":
			return {}
		# normal/hard：远程单位若离最近敌太近（≤1）先拉开一步，否则站定输出
		if (lvl == "hard" or _posture(battle) == "kite") and _nearest_foe_dist(actor, foes) <= 1 and _wants_ranged_keepaway(battle, actor):
			return _retreat_step(battle, actor, foes)
		return {}
	# 需要走位接近才能打：一律“就近攻脆”推进（避免长途追后排被白打）；集火在技能阶段兑现
	var target := _approach_target(actor, foes)
	if target == null:
		return {}
	var cands: Array = battle.move_cells_of(actor)
	if cands.is_empty():
		return {}
	var posture := _posture(battle)
	var threat_k := 0.6
	if posture == "aggressive":
		threat_k = 0.35
	elif posture == "defensive":
		threat_k = 1.3
	var protect_idx := _tactic_protect_idx(battle, actor)
	# 远程距离管理：normal/hard 中带“非位移”攻击射程≥2 的单位，站位保持“能打到的边缘距离”，
	# 避免像本日志复盘那样远程射手前冲贴脸被白打（easy 保持原莽夫走位）
	var is_ranged := false
	var keep := 1
	if lvl != "easy":
		for si in range(1, 5):
			if not battle.base_usable(actor, si) or battle.self_skill(actor, si):
				continue
			if battle.skill_range(actor, si) >= 2:
				keep = maxi(keep, battle.skill_range(actor, si))
				is_ranged = true
	var best_cell := Vector2i.ZERO
	var best_score := -1.0e9
	for c in cands:
		var cc: Vector2i = c
		var d := _cell_dist(actor, target, cc)
		var score := -float(d)
		# 得分制拾星引力：停在星格（=拾取）重奖；邻星格轻奖（全难度适用）。
		# 权重读取战斗层常量自动随分值联动：小星≈3*3=9 / 大星≈5*2.6=13 / 邻星 1.8。
		# 1V1（battle.gd）无星星字段 → 用 get 安全判空，避免 AI 走棋崩溃
		var star_list: Variant = battle.get("stars")
		if star_list is Array and (star_list as Array).size() > 0:
			var small_v: Variant = battle.get("SMALL_STAR_VAL")
			var big_v: Variant = battle.get("BIG_STAR_VAL")
			var sv := float(small_v) if (typeof(small_v) == TYPE_INT or typeof(small_v) == TYPE_FLOAT) else 3.0
			var bv := float(big_v) if (typeof(big_v) == TYPE_INT or typeof(big_v) == TYPE_FLOAT) else 5.0
			for st in star_list:
				var spos: Vector2i = (st as Dictionary)["pos"]
				if spos == cc:
					score += bv * 2.6 if bool((st as Dictionary).get("big", false)) else sv * 3.0
				elif absi(spos.x - cc.x) + absi(spos.y - cc.y) == 1:
					score += 1.8
		# normal+：站在该格后的敌方近身威胁越小越好（easy 忽略）；posture 调制冒险度
		if lvl != "easy":
			score -= 1.5 * threat_k * float(_foes_within_of(actor, foes, cc, 1))
			if lvl == "hard" or posture == "kite":
				score -= 0.8 * float(_foes_within_of(actor, foes, cc, 2))
			if is_ranged:
				var dnear := _nearest_foe_dist_at(foes, cc)
				if dnear < 2:
					score -= float(2 - dnear) * 3.0      # 贴脸格重罚
				elif dnear > keep + 1:
					score -= float(dnear - keep - 1) * 0.7  # 太远轻罚（避免反向拉开）
		# 守护倾向：若在保护对象附近且移动会远离它则轻微罚（别丢下要保护的人）
		if protect_idx >= 0 and protect_idx < battle.units.size():
			var pguard: BattleUnit = battle.units[protect_idx]
			if pguard.alive and pguard.team == actor.team and _cell_dist(actor, pguard, cc) > 2 and _cell_dist(actor, pguard, actor.cell) <= 2:
				score -= 1.4
		# 联机确定性：优先用 battle.rng（同种子→双方 AI 决策一致）；无 rng 的旧调用回退全局
		var g: RandomNumberGenerator = battle.rng if battle != null and "rng" in battle else null
		if lvl == "easy" and (g.randf() if g != null else randf()) < 0.15:
			score -= float((g.randi() if g != null else randi()) % 3)   # 简单难度偶尔乱走一步
		if score > best_score:
			best_score = score
			best_cell = cc
	return {"act": "move", "cell": best_cell}

## 技能阶段：返回 skill dict 或 {}（不放）
static func plan_skill(battle, actor: BattleUnit, moved: bool) -> Dictionary:
	if actor == null or not actor.alive:
		return {}
	var lvl := _lvl(battle)
	var hp_ratio := float(actor.hp) / float(maxi(1, actor.max_hp))
	var heal_th := 0.45 if lvl == "normal" else (0.55 if lvl == "hard" else 0.35)
	var _post := _posture(battle)
	if _post == "defensive":
		heal_th = clampf(heal_th + 0.07, 0.2, 0.9)
	elif _post == "aggressive":
		heal_th = clampf(heal_th - 0.07, 0.2, 0.9)
	# 1) 保命优先：血线危险时用治疗/护盾类
	# 大招已充能且能命中 → 先放大招。否则像药师这种“自残流”（血量长期压在 heal_th 以下）
	# 会被常规自保循环卡住，能量攒到几百也放不出大招。
	if lvl != "easy" and _ult_ready_in_range(battle, actor):
		return _skill_single(battle, actor, 4)
	if hp_ratio <= heal_th:
		for i in [3, 2, 4, 1]:
			if _castable(battle, actor, i):
				var k := _self_kind(battle, actor, i)
				if k == "heal" or k == "shield":
					return _skill_single(battle, actor, i)
	# 2) easy：原版观感 —— 大招优先；但低智：经常发呆、打错目标、乱走
	if lvl == "easy":
		for i in [4, 3, 2, 1]:
			if _castable(battle, actor, i) and not battle.self_skill(actor, i):
				return _skill_single(battle, actor, i)
		# 简单的自 buff（无目标可打时）
		for i in [4, 3, 2, 1]:
			if _castable(battle, actor, i) and battle.self_skill(actor, i):
				return _skill_single(battle, actor, i)
		return {}
	# 3) normal / hard：评估每个可用技能对“最佳目标”的价值，选最优
	return _pick_best_skill(battle, actor, hp_ratio, lvl == "hard")

## —— 内部工具 ——
static func _lvl(battle) -> String:
	return str(battle.ai_level) if battle != null else "easy"

static func _cell_dist(actor: BattleUnit, target: BattleUnit, cc: Vector2i) -> int:
	return absi(cc.x - target.cell.x) + absi(cc.y - target.cell.y)

## 大招（4 号槽）已可释放，但当前位置射程内没有敌人
static func _ult_ready_but_out_of_range(battle, actor: BattleUnit) -> bool:
	if not battle.base_usable(actor, 4) or battle.self_skill(actor, 4):
		return false
	return battle.targets_in_range(actor, 4).is_empty()

## 大招（4 号槽）已可释放，且当前位置就能命中敌人
static func _ult_ready_in_range(battle, actor: BattleUnit) -> bool:
	if not battle.base_usable(actor, 4) or battle.self_skill(actor, 4):
		return false
	return not battle.targets_in_range(actor, 4).is_empty()

## 从“原地 + 本回合可移动格”中挑出能命中任一敌人的最近格（用于为大招贴脸）；无解则返回原地
static func _step_into_range(battle, actor: BattleUnit, foes: Array, slot: int) -> Vector2i:
	var rng: int = battle.skill_range(actor, slot)
	var best := actor.cell
	var bd := 9999
	var cands: Array = battle.move_cells_of(actor)
	cands.append(actor.cell)
	for c in cands:
		var cc: Vector2i = c
		for f in foes:
			var ff: BattleUnit = f
			var d := absi(cc.x - ff.cell.x) + absi(cc.y - ff.cell.y)
			if d <= rng and d < bd:
				bd = d
				best = cc
	return best

## 射程内可命中且非空（已有目标可输出）
static func _ranged_ready(battle, actor: BattleUnit) -> bool:
	for i in [1, 2, 3, 4]:
		if _castable(battle, actor, i) and not battle.self_skill(actor, i):
			return true
	return false

static func _nearest_foe_dist(actor: BattleUnit, foes: Array) -> int:
	var bd := 9999
	for f in foes:
		var ff: BattleUnit = f
		bd = mini(bd, absi(ff.cell.x - actor.cell.x) + absi(ff.cell.y - actor.cell.y))
	return bd

## 该单位是否有“远程风筝”倾向：有 range≥3 的攻击技且能量能释放
static func _wants_ranged_keepaway(battle, actor: BattleUnit) -> bool:
	for i in [1, 2, 3, 4]:
		if not battle.base_usable(actor, i) or battle.self_skill(actor, i):
			continue
		if battle.skill_range(actor, i) >= 3:
			return true
	return false

## 威胁：站在该格后，1/2 格内有几个敌人
static func _foes_within_of(actor: BattleUnit, foes: Array, cc: Vector2i, r: int) -> int:
	var n := 0
	for f in foes:
		var ff: BattleUnit = f
		var d := absi(ff.cell.x - cc.x) + absi(ff.cell.y - cc.y)
		if d <= r:
			n += 1
	return n

## 远离最近敌一格（向敌少的方向撤）
static func _retreat_step(battle, actor: BattleUnit, foes: Array) -> Dictionary:
	var cands: Array = battle.move_cells_of(actor)
	if cands.is_empty():
		return {}
	var best_cell := Vector2i.ZERO
	var best_score := -1.0e9
	for c in cands:
		var cc: Vector2i = c
		var score := 1.5 * float(_nearest_foe_dist_at(foes, cc))
		score -= 1.0 * float(_foes_within_of(actor, foes, cc, 2))
		if score > best_score:
			best_score = score
			best_cell = cc
	return {"act": "move", "cell": best_cell}

static func _nearest_foe_dist_at(foes: Array, cc: Vector2i) -> int:
	var bd := 9999
	for f in foes:
		var ff: BattleUnit = f
		bd = mini(bd, absi(ff.cell.x - cc.x) + absi(ff.cell.y - cc.y))
	return bd

## 旧版走位目标（easy 专用，行为不变）：近 + 脆 优先
static func _approach_target(actor: BattleUnit, foes: Array) -> BattleUnit:
	var best: BattleUnit = null
	var bs := 1.0e9
	for f in foes:
		var ff: BattleUnit = f
		var d := absi(ff.cell.x - actor.cell.x) + absi(ff.cell.y - actor.cell.y)
		var score := float(d) * 10.0 + float(ff.hp + ff.shield)
		if score < bs:
			bs = score
			best = ff
	return best

## ========== 全队集火共识（normal/hard 核心强化） ==========
## 优先豆包 focus；否则在“全体敌人”里选一个公共目标 —— 评分与本单位位置无关，
## 因此同队各单位算出的结果一致 → 多打一滚雪球。
## hard 额外偏向“治疗/自疗型”敌人（先切奶）；hp≤2 的可斩目标天然最小。
static func _team_focus(battle, actor: BattleUnit) -> BattleUnit:
	var fu := _tactic_focus(battle, actor)
	if fu != null:
		return fu
	var lvl := _lvl(battle)
	if lvl == "easy":
		return null
	var foes: Array = battle.alive_enemies_of(actor)
	if foes.is_empty():
		return null
	var best: BattleUnit = null
	var bs := 1.0e18
	for f in foes:
		var ff: BattleUnit = f
		var sc := float(ff.hp + ff.shield) * 10.0
		if lvl == "hard":
			if _is_healer(ff):
				sc -= 26.0            # 优先处理自疗/回血单位，避免“打不死”
			if ff.hp <= 2:
				sc -= 14.0            # 硬斩残血
		if sc < bs:
			bs = sc
			best = ff
	return best

## 该敌方单位是否带“治疗/自疗”类技能（药师回血、孤狼膏腴等）
static func _is_healer(e: BattleUnit) -> bool:
	for s in range(1, 5):
		var sk := e.get_skill(s)
		if sk == null:
			continue
		if _healer_kind(sk.id) == "heal":
			return true
	return false

static func _healer_kind(skill_id: String) -> String:
	var se := load("res://scripts/combat/skill_effects.gd")
	if se == null:
		return ""
	var data: Dictionary = se.DATA as Dictionary
	var sk: Dictionary = data.get(skill_id, {}) as Dictionary
	return str(sk.get("ai", {}).get("self_kind", ""))

## normal/hard：攻击技能优先打分（目标越脆越优、队伍集火目标必选、大招加权）；
## 只有攻击全部不可用时才考虑护盾类兜底（治疗已在保命分支处理）
static func _pick_best_skill(battle, actor: BattleUnit, hp_ratio: float, aggressive: bool) -> Dictionary:
	var tf := _team_focus(battle, actor)
	var best := {}      # 攻击选择
	var bs := -1.0e9
	var has_attack := false
	for i in [4, 3, 2, 1]:
		if not _castable(battle, actor, i) or battle.self_skill(actor, i):
			continue
		var sk := actor.get_skill(i)
		if sk == null:
			continue
		has_attack = true
		var foes: Array = battle.targets_in_range(actor, i)
		for f in foes:
			var ff: BattleUnit = f
			var sc := -float(ff.hp + ff.shield) * 10.0 + float(sk.energy_cost) * 2.0
			if i == 4:
				sc += 28.0   # 大招偏好
			if ff.hp <= 2:
				sc += 60.0   # 可斩残血
			if tf != null and ff == tf:
				sc += 300.0  # 队伍集火目标（豆包 focus 或本地共识）：远大于其它加分，命中即必选
			if sc > bs:
				bs = sc
				best = {"act": "skill", "slot": i, "target": ff}
	if has_attack:
		return best
	# 无攻击可打（目标都不在射程）：不整回合空过，但也不“空放无收益的自保技” ——
	# heal 仅在自身残血可治疗时；shield 仅在未达护盾上限时；高耗大招一律不空放
	var hp_low: bool = hp_ratio < (0.75 if aggressive else 0.6)
	for i in [3, 2, 1, 4]:
		if _castable(battle, actor, i) and battle.self_skill(actor, i):
			var sk2 := actor.get_skill(i)
			if sk2 == null:
				continue
			var k := _self_kind(battle, actor, i)
			if k != "shield" and k != "heal":
				continue
			var cheap: bool = sk2.energy_cost <= (5 if aggressive else 4)
			if not (cheap or hp_low):
				continue
			# 空放判定：heal 需 hp 未满；shield 需未到护盾上限（无上限英雄按盾≥4 视为饱和）
			var useful := false
			if k == "heal":
				useful = actor.hp < actor.max_hp
			else:
				var at_cap: bool = (actor.shield_cap > 0 and actor.shield >= actor.shield_cap) or (actor.shield_cap <= 0 and actor.shield >= 4)
				useful = not at_cap
			if useful:
				return _skill_single(battle, actor, i)
	return {}

static func _skill_single(battle, actor: BattleUnit, slot: int) -> Dictionary:
	if battle.self_skill(actor, slot):
		return {"act": "skill", "slot": slot, "target": null}
	# 单体目标：队伍集火目标在射程内则优先，否则取 hp+盾 最低者
	var foes: Array = battle.targets_in_range(actor, slot)
	if foes.is_empty():
		return {}
	var focus := _team_focus(battle, actor)
	if focus != null and focus in foes:
		return {"act": "skill", "slot": slot, "target": focus}
	var best: BattleUnit = null
	var bs := 1.0e9
	for f in foes:
		var ff: BattleUnit = f
		var sc := float(ff.hp + ff.shield)
		if sc < bs:
			bs = sc
			best = ff
	if best == null:
		return {}
	return {"act": "skill", "slot": slot, "target": best}

static func _castable(battle, actor: BattleUnit, slot: int) -> bool:
	if not battle.base_usable(actor, slot):
		return false
	if not battle.self_skill(actor, slot) and battle.targets_in_range(actor, slot).is_empty():
		return false
	return true

static func _self_kind(battle, actor: BattleUnit, slot: int) -> String:
	var sk := actor.get_skill(slot)
	if sk == null:
		return ""
	return str(battle.skill_data(sk.id).get("ai", {}).get("self_kind", ""))

## =============== 豆包战术倾向读取（battle.llm_tactics） ===============
## 仅当豆包在本回合答题后才非空；空时全部走默认（balanced / 无集火 / 无保护）。
static func _posture(battle) -> String:
	var t: Dictionary = battle.llm_tactics if battle != null else {}
	return str(t.get("posture", "balanced"))

## 集火目标：返回敌方 BattleUnit；无/已死/是友方 → null
static func _tactic_focus(battle, actor: BattleUnit) -> BattleUnit:
	if battle == null:
		return null
	var t: Dictionary = battle.llm_tactics
	var idx := int(t.get("focus", -1))
	if idx < 0 or idx >= battle.units.size():
		return null
	var fu := battle.units[idx] as BattleUnit
	if fu == null or not fu.alive or fu.team == actor.team:
		return null
	return fu

## 保护对象下标（己方）；无 → -1
static func _tactic_protect_idx(battle, actor: BattleUnit) -> int:
	if battle == null:
		return -1
	var t: Dictionary = battle.llm_tactics
	var idx := int(t.get("protect", -1))
	if idx < 0 or idx >= battle.units.size():
		return -1
	var pu := battle.units[idx] as BattleUnit
	if pu == null or not pu.alive or pu.team != actor.team:
		return -1
	return idx
