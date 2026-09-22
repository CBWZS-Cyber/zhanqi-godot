extends SceneTree
func _initialize() -> void:
	await process_frame
	var BT: GDScript = load("res://scripts/combat/battle_team.gd")
	var T: GDScript = load("res://scripts/combat/terrain.gd")
	var bad := 0
	var samples := []
	for trial in range(30):
		var t = BT.new(["jianwu","gu_lang","yao_shi","xie_shen"], ["guang_yu","he_zhigao","xian_zun","ling_xu"])
		var b = t.board
		var nl := 0
		var nr := 0
		var lv := 0
		var rv := 0
		var neg_name := ""
		for c in t._all_cells():
			var tid: int = b.terrain_at(c)
			if tid <= 0: continue
			var v: int = int(t.TERRAIN_VALUE.get(tid, 0))
			if tid == T.WATER or tid == T.SAND:
				neg_name = T.name_of(tid)
				if c.x <= 4: nl += 1
				else: nr += 1
			if c.x <= 4: lv += v
			else: rv += v
		if nl != nr: bad += 1
		if trial < 3:
			samples.append("局%d: %s 左%d右%d 价值差%d" % [trial+1, neg_name, nl, nr, absi(lv-rv)])
	for s in samples: print(s)
	print("负面左右不等量的局数:", bad, "（应为0）")
	print("==== 结果:", "PASS ✅" if bad == 0 else "FAIL ❌", "====")
	quit(0 if bad == 0 else 1)
