class_name HeroRules
extends RefCounted
## 英雄专属规则的集中处。
##
## 2026-09-30 结构外移：原先虞美人的恐惧发作 / 治疗光环 / 子体行动 / 子体生成
## 直接写在 BattleBase（1V1、4V4、剧情、教程共享的基类）里。11 个英雄各有独立的
## 回血与机制，继续往基类堆专属逻辑只会持续膨胀，故集中到本文件。
##
## 约定：每个函数首参是战斗实例（BattleBase），规则内部只经它的公开接口读写，
## 不反向依赖任何具体对局子类。BattleBase 里保留同名转发壳，调用点无需改动。

## 恐惧发作：恐惧层数 > 0 且相邻格有敌方虞美人时，一次性结算并清空层数。
static func check_fear(battle: BattleBase, u: BattleUnit) -> void:
	var n := u.status_stacks("fear")
	if n <= 0:
		return
	for x in battle.units:
		if x.alive and x.def_id == "yu_mei_ren" and x != u and battle.dist(x, u) <= 1:
			var dmg: float = ceili(float(n) * 0.5)
			u.set_status("fear", 0)
			var before: float = u.hp
			u.lose_hp(dmg)
			battle.log.push_back("【恐惧】%s 逼近虞美人：恐惧 %d 层发作，受 %.2f 真伤" % [u.name, n, before - u.hp])
			return


## 子体行动：对 3×3 内所有敌方各打 1 点暗伤。
static func child_act(battle: BattleBase, child: BattleUnit) -> void:
	var foes: Array = battle.alive_enemies_of(child)
	var out := "%s（子体）发动【暗影刺】" % child.name
	var hit := 0
	for f in foes:
		var fu := f as BattleUnit
		if fu == null or not fu.alive:
			continue
		if battle.dist(fu, child) <= 1:
			var r: Dictionary = fu.take_damage(1, {"element": "暗", "attacker": child})
			out += "；%s 受 %.2f 伤" % [fu.name, float(r["hp_lost"]) + float(r["absorbed"])]
			hit += 1
	if hit > 0:
		battle.log.push_back(out)


## 虞美人治疗光环：回合末清旧庇佑，3×3 内有虞美人的同阵营单位回 20% 最大生命。
static func yumeiren_round_end(battle: BattleBase) -> void:
	var ym: Array = []
	for x in battle.units:
		if x.alive and x.def_id == "yu_mei_ren":
			ym.append(x)
	# 清旧庇佑
	for x in battle.units:
		if x.has_flag("yumeiren_protect"):
			x.clear_flag("yumeiren_protect")
	if ym.is_empty():
		return
	for x in battle.units:
		if x.alive and x.team == ym[0].team:
			var near := false
			for y in ym:
				if battle.dist(x, y) <= 1:
					near = true
					break
			if near:
				var h := x.heal(x.max_hp * 0.2)
				if h > 0:
					battle.log.push_back("【苦楚】%s 回复 %.2f 生命" % [x.name, h])
				if x.def_id != "yu_mei_ren":
					x.add_flag("yumeiren_protect")


## 取 [param cell] 格上属于自己的子体（没有则 null）。
## 用于虞美人母体移动时与子体互换格子（不叠格）。
static func child_at_cell(battle: BattleBase, u: BattleUnit, cell: Vector2i) -> BattleUnit:
	if u.def_id != "yu_mei_ren" or u.has_flag("子体"):
		return null
	for x in battle.units:
		if x.has_flag("子体") and x.team == u.team and x.cell == cell:
			return x
	return null


## 生成虞美人子体并加入战场。
static func spawn_child(battle: BattleBase, parent: BattleUnit, cell: Vector2i) -> BattleUnit:
	var child := BattleUnit.new({"name": "虞美人子体", "element": "木", "hp": 5, "energy": 0, "armor": 0, "speed": 0, "skills": {}})
	child.def_id = "yu_mei_ren"
	child.team = parent.team
	child.cell = cell
	child.hp = 5.0
	child.max_hp = 5.0
	child.non_solid = true
	child.add_flag("子体")
	child.rng = battle.rng
	battle.units.append(child)
	return child
