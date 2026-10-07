extends SceneTree
func _initialize() -> void:
	await process_frame
	var BT: GDScript = load("res://scripts/combat/battle_team.gd")
	var T: GDScript = load("res://scripts/combat/terrain.gd")
	var max_diff := 0
	var no_neg := 0
	var themes := {}
	var samples := []
	for trial in range(30):
		var t = BT.new(["jianwu","gu_lang","yao_shi","xie_shen"], ["guang_yu","he_zhigao","xian_zun","ling_xu"])
		var b = t.board
		var lv := 0
		var rv := 0
		var nl := 0
		var nr := 0
		var neg_name := ""
		var total := 0
		for c in t._all_cells():
			var tid: int = b.terrain_at(c)
			if tid <= 0: continue
			total += 1
			var v: int = int(t.TERRAIN_VALUE.get(tid, 0))
			if tid == T.WATER or tid == T.SAND:
				neg_name = T.name_of(tid)
				if c.x <= 4: nl += 1
				else: nr += 1
			if c.x <= 4: lv += v
			else: rv += v
		if neg_name == "": no_neg += 1
		themes[neg_name] = int(themes.get(neg_name, 0)) + 1
		max_diff = maxi(max_diff, absi(lv - rv))
		if trial < 4:
			samples.append("局%d: %s 负左%d/右%d 总数%d 价值差%d" % [trial+1, neg_name, nl, nr, total, absi(lv-rv)])
	for s in samples: print(s)
	print("负面主题分布:", themes, "| 无负面的局数:", no_neg)
	print("30 局最大左右价值差:", max_diff)
	var ok: bool = max_diff <= 1 and no_neg == 0 and themes.size() == 2
	print("==== 结果:", "PASS ✅" if ok else "FAIL ❌", "====")
	quit(0 if ok else 1)
