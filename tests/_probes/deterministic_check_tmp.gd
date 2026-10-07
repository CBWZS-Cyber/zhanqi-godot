extends SceneTree
## 阶段1验证：同种子双局 log 完全一致（联机确定性）；异种子 log 不同
func _initialize() -> void:
	var BT := load("res://scripts/combat/battle_team.gd")
	var red: Array = ["crystal_dragon", "jianwu", "guang_yu", "yao_shi"]
	var blue: Array = ["xie_shen", "gu_lang", "xian_zun", "he_zhigao"]
	var b1 = BT.new(red.duplicate(), blue.duplicate())
	b1.ai_level = "easy"
	b1.enable_lookahead = false
	b1.set_rng_seed(20260905)
	b1.simulate()
	var b2 = BT.new(red.duplicate(), blue.duplicate())
	b2.ai_level = "easy"
	b2.enable_lookahead = false
	b2.set_rng_seed(20260905)
	b2.simulate()
	var same: bool = (b1.log == b2.log) and (b1.winner == b2.winner)
	print("同种子一致: ", same, " | winner=", b1.winner, "/", b2.winner, " | log=", b1.log.size(), "/", b2.log.size())
	if not same:
		for i in range(mini(b1.log.size(), b2.log.size())):
			if b1.log[i] != b2.log[i]:
				print("首个差异@", i, ": [", b1.log[i], "] vs [", b2.log[i], "]")
				break
	var b3 = BT.new(red.duplicate(), blue.duplicate())
	b3.ai_level = "easy"
	b3.enable_lookahead = false
	b3.set_rng_seed(1)
	b3.simulate()
	var diff: bool = (b1.log != b3.log)
	print("异种子差异: ", diff, " | winner=", b3.winner)
	# 1V1 同样验证
	var B1 := load("res://scripts/combat/battle.gd")
	var d1 = B1.new("zhuilie", "xian_zun")
	d1.set_rng_seed(777)
	d1.simulate()
	var d2 = B1.new("zhuilie", "xian_zun")
	d2.set_rng_seed(777)
	d2.simulate()
	var same1v1: bool = (d1.log == d2.log) and (d1.winner == d2.winner)
	print("1V1 同种子一致: ", same1v1, " | winner=", d1.winner, "/", d2.winner)
	if not same1v1:
		for i in range(mini(d1.log.size(), d2.log.size())):
			if d1.log[i] != d2.log[i]:
				print("1V1 首个差异@", i, ": [", d1.log[i], "] vs [", d2.log[i], "]")
				break
	var ok := same and diff and same1v1
	print("==== 结果:", "PASS ✅" if ok else "FAIL ❌", "====")
	quit(0 if ok else 1)
