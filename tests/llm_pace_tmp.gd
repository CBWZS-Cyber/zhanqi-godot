extends SceneTree
## 实测：蓝方 hard+豆包，红方=人类(简单操作)。看豆包每回合调用节奏与耗时
func _initialize() -> void:
	var BT := load("res://scripts/combat/battle_team.gd")
	var red := ["crystal_dragon", "jianwu", "guang_yu", "yao_shi"]
	var blue := ["xie_shen", "gu_lang", "xian_zun", "he_zhigao"]
	var b = BT.new(red, blue)
	b.human_mode = true
	b.human_team = 0          # 红=人
	b.ai_level = "hard"
	b.ai_backend = "llm"
	b.enable_lookahead = false
	var t_prev := Time.get_ticks_msec()
	var human_acts := 0
	var target_round := 3
	var guard := 0
	while guard < 400 and b.winner == "" and b.round < target_round:
		guard += 1
		var st: Dictionary = b.run_step()
		if st.has("wait"):
			# 人类单位简单行动：能放4技就放，否则等待
			var cur = b.current()
			var acted := false
			if cur != null and cur.alive:
				for s in [4, 3, 2, 1]:
					if b.base_usable(cur, s):
						var tgt = b._weakest_in_range(cur, s) if b.has_method("_weakest_in_range") else null
						acted = true
						break
				# 直接让人类等待结束本行动（模拟玩家点"跳过技能"）
			human_acts += 1
			var r2: Dictionary = b.run_step()
			if r2.has("over"): break
	var el := (Time.get_ticks_msec() - t_prev) / 1000.0
	print("== 跑了 %.0f 回合（守卫%d次步进） 总耗时 %.1fs ==" % [b.round, guard, el])
	var llm_lines: Array = []
	for l in b.log:
		if l.find("战术模型") >= 0:
			llm_lines.append(l)
	print("日志中'战术模型'出现 ", llm_lines.size(), " 次（期望=每回合1次+回退）:")
	for l in llm_lines:
		print("   · ", l)
	quit(0)
