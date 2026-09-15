extends SceneTree
## v2 验证：全 AI 跑 1 回合，每 AI 单位行动前现场问豆包
func _initialize() -> void:
	var BT := load("res://scripts/combat/battle_team.gd")
	var red := ["crystal_dragon", "jianwu", "guang_yu", "yao_shi"]
	var blue := ["xie_shen", "gu_lang", "xian_zun", "he_zhigao"]
	var b = BT.new(red, blue)
	b.ai_level = "hard"
	b.ai_backend = "llm"
	b.enable_lookahead = false
	var t0 := Time.get_ticks_msec()
	var guard := 0
	while guard < 400 and b.winner == "" and b.round <= 1:
		guard += 1
		b.run_step()
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	var n := 0
	for l in b.log:
		if l.find("战术模型") >= 0: n += 1
	print("回合数=", b.round, " 总耗时 %.1fs" % el)
	print("'战术模型思考'次数 = ", n, "（期望 = 1回合内 AI 单位数，8单位全AI → ~8）")
	quit(0 if n >= 6 else 1)
