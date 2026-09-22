extends SceneTree
func _initialize() -> void:
	var BAT = load("res://scripts/combat/battle.gd")
	# 模拟 duel._on_start 的难度注入逻辑
	for diff in ["normal", "hard"]:
		for backend in ["local", "llm"]:
			var b = BAT.new("zhuilie", "gu_lang")
			b.human_mode = true
			b.human_team = 0
			b.ai_level = diff
			b.side_levels = {1: diff}   # ← 之前崩溃点
			if diff == "hard":
				b.ai_backend = backend
			var steps := 0
			var err := ""
			while b.winner == "" and b.round < 60 and steps < 200:
				steps += 1
				var st: Dictionary = b.run_step()
				if st.has("over"):
					break
				if st.has("wait"):
					b.human_done()
			print("difficulty=%s backend=%s → round=%d winner=%s（未崩溃）" % [diff, backend, b.round, b.winner])
	quit(0)
