extends SceneTree
## v3 快速验证：红方人类(草草走)，蓝方 4 AI hard+llm。
## 每步进度可见；收集到 >=3 次"战术模型思考"即提前退出（证明"每单位行动前现问"，而非每回合 1 次）
func _initialize() -> void:
	var BT := load("res://scripts/combat/battle_team.gd")
	var red := ["crystal_dragon", "jianwu", "guang_yu", "yao_shi"]
	var blue := ["xie_shen", "gu_lang", "xian_zun", "he_zhigao"]
	var b = BT.new(red, blue)
	b.ai_level = "hard"
	b.ai_backend = "llm"
	b.enable_lookahead = false
	b.human_mode = true
	b.human_team = 0
	b.human_teams = [0]
	var t0 := Time.get_ticks_msec()
	var guard := 0
	var last_n := 0
	while guard < 400 and b.winner == "":
		guard += 1
		var st: Dictionary = b.run_step()
		var n := 0
		for l in b.log:
			if l.find("战术模型") >= 0:
				n += 1
		if n != last_n:
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			print("[%4.1fs] 战术模型思考次数=%d 回合=%d" % [el, n, b.round])
			last_n = n
			if n >= 3:
				break
		if st.has("wait"):
			var cur: Object = b.current()
			if cur != null:
				var mcs: Array = b.move_cells_of(cur)
				if mcs.size() > 0:
					b.human_move(mcs[0])
				# 能量够就放个便宜技能，不够就直接结束
				var cast: bool = false
				for slot in range(1, 5):
					if b.base_usable(cur, slot):
						var foes: Array = b.alive_enemies_of(cur)
						if foes.size() > 0:
							b.human_cast(slot, foes[0])
							cast = true
							break
				if not cast:
					b.human_done()
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	var n := 0
	for l in b.log:
		if l.find("战术模型") >= 0:
			n += 1
	print("总耗时 %.1fs, '战术模型思考'次数 = %d（期望 >=3，证明每单位行动前现问）" % [el, n])
	quit(0 if n >= 3 else 1)
