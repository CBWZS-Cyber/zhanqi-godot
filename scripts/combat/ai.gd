class_name BattleAI
extends RefCounted
## 战棋 · AI 操纵系统 v2
## 回合规则：每棋一回合 = 移动权 + 技能权（先移后放、各自可选；移过则禁用位移技）
## Battle 提供视图 → AI 决策动作 dict → Battle 权威执行

## 阶段1：要不要移动？返回 move dict 或 {}（不动）
static func plan_move(battle, actor: BattleUnit) -> Dictionary:
	for i in [1, 2, 3, 4]:
		if not battle.base_usable(actor, i):
			continue
		if battle.is_dash(actor, i):
			return {}   # 想用位移技接近：保留移动权
		if not battle.self_skill(actor, i) and not battle.targets_in_range(actor, i).is_empty():
			return {}   # 静止技能已能命中，无需走位
	var foes: Array = battle.alive_enemies_of(actor)
	if foes.is_empty():
		return {}
	var best: BattleUnit = null
	var bd := 9999
	for f in foes:
		var ff: BattleUnit = f
		var d := absi(ff.cell.x - actor.cell.x) + absi(ff.cell.y - actor.cell.y)
		if d < bd:
			bd = d
			best = ff
	if best == null:
		return {}
	var cands: Array = battle.move_cells_of(actor)
	var pick := Vector2i.ZERO
	var pd := 9999
	for c in cands:
		var cc: Vector2i = c
		var dc := absi(best.cell.x - cc.x) + absi(best.cell.y - cc.y)
		if dc < pd:
			pd = dc
			pick = cc
	if pd == 9999:
		return {}
	return {"act": "move", "cell": pick}

## 阶段2：放什么技能？返回 skill dict 或 {}（不放）
static func plan_skill(battle, actor: BattleUnit, moved: bool) -> Dictionary:
	var hp_ratio := float(actor.hp) / float(maxi(1, actor.max_hp))
	if hp_ratio <= 0.45:
		for i in [4, 3, 2, 1]:
			if _castable(battle, actor, i, moved):
				var k := _self_kind(battle, actor, i)
				if k == "heal" or k == "shield":
					return _skill_action(battle, actor, i)
	if _castable(battle, actor, 4, moved):
		return _skill_action(battle, actor, 4)
	for i in _by_energy(battle, actor):
		if not _castable(battle, actor, i, moved):
			continue
		if battle.self_skill(actor, i):
			if _self_kind(battle, actor, i) != "heal" and hp_ratio > 0.55:
				return _skill_action(battle, actor, i)
		else:
			return _skill_action(battle, actor, i)
	return {}

static func _castable(battle, actor: BattleUnit, slot: int, _moved: bool) -> bool:
	if not battle.base_usable(actor, slot):
		return false
	if not battle.self_skill(actor, slot) and battle.targets_in_range(actor, slot).is_empty():
		return false
	return true

static func _skill_action(battle, actor: BattleUnit, slot: int) -> Dictionary:
	if battle.self_skill(actor, slot):
		return {"act": "skill", "slot": slot, "targets": []}
	return {"act": "skill", "slot": slot, "targets": battle.targets_in_range(actor, slot)}

static func _self_kind(battle, actor: BattleUnit, slot: int) -> String:
	var sk := actor.get_skill(slot)
	if sk == null:
		return ""
	return str(battle.skill_data(sk.id).get("ai", {}).get("self_kind", ""))

static func _by_energy(battle, actor: BattleUnit) -> Array:
	var arr: Array = []
	for i in [1, 2, 3, 4]:
		var sk := actor.get_skill(i)
		if sk != null:
			arr.append({"slot": i, "cost": sk.energy_cost})
	arr.sort_custom(func(a, b): return int(a.cost) > int(b.cost))
	var out: Array = []
	for e in arr:
		out.append(int(e.slot))
	return out
