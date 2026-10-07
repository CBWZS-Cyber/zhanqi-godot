extends SceneTree
## 临时探针：把 14 个英雄的实际技能结构打出来，用于设计新手教程的步骤生成规则。
## 运行：godot --headless --path . -s res://tests/tmp_tut_probe.gd

func _initialize() -> void:
	await process_frame
	var HD = load("res://scripts/combat/hero_defs.gd")
	var SE = load("res://scripts/combat/skill_effects.gd")
	var ids: Array = HD.list_ids()
	ids.sort()
	print("==== 英雄技能结构（源：HeroDefs.ALL + SkillEffects.DATA 实际读取）====")
	for hid in ids:
		if str(hid) == "demo_hero":
			continue
		var def: Dictionary = HD.ALL[hid]
		var sk: Dictionary = def.get("skills", {})
		var acts: Array = sk.get("actives", [])
		var parts: Array = []
		var n_dash := 0
		var n_self := 0
		var n_tgt := 0
		var n_dmg := 0
		for sid in acts:
			if str(sid) == "":
				parts.append("(空槽)")
				continue
			var d: Dictionary = SE.DATA.get(sid, {})
			if d.is_empty():
				parts.append("%s[无DATA]" % str(sid))
				continue
			var rng: int = int(d.get("range", -1))
			var ai: Dictionary = d.get("ai", {})
			var is_dash: bool = bool(ai.get("dash", false))
			var is_self: bool = bool(ai.get("self_buff", false)) or rng == 0
			var is_dmg: bool = "伤害" in str(d.get("desc", ""))
			var tag := "目标"
			if is_dash:
				tag = "位移%s(%s)" % [str(d.get("dash_dist", 0)), str(ai.get("dash_kind", "jump"))]
				n_dash += 1
			elif is_self:
				tag = "自益"
				n_self += 1
			else:
				n_tgt += 1
			if is_dmg:
				n_dmg += 1
			parts.append("%s[%s r%s%s]" % [str(d.get("name", sid)), tag, str(rng), " 伤" if is_dmg else ""])
		var ebar := "无能量条"
		if def.get("sanity_cap", null) != null:
			ebar = "理智条(sanity_cap=%s)" % str(def["sanity_cap"])
		elif int(def.get("energy_max", 0)) == -1:
			ebar = "无限能量"
		print("%-10s hp=%-3s en=%-3s %-18s spd=%-4s 位移%d/自益%d/目标%d/含伤害%d" % [
			str(def.get("name", hid)), str(def.get("hp", "-")), str(def.get("energy", "-")),
			ebar, str(def.get("speed", "-")), n_dash, n_self, n_tgt, n_dmg])
		print("           ", " · ".join(parts))
	quit(0)
