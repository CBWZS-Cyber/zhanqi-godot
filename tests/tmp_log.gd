extends SceneTree
func _initialize() -> void:
	var BAT = load("res://scripts/combat/battle.gd")
	var b = BAT.new("xin_kelai", "yao_shi")
	b.human_mode = true
	b.human_team = 0
	b.units[0].cell = Vector2i(3, 2)
	b.units[1].cell = Vector2i(4, 2)
	var t := 0
	while b.winner == "" and t < 60:
		t += 1
		var st: Dictionary = b.run_step()
		if st.has("over"):
			break
		if st.has("wait"):
			var me = b.current()
			print("[t%d] 轮到 %s 理智=%d" % [t, me.name, me.sanity])
			var r: String = b.human_cast(1, b.units[1])
			print("   cast1 → ", r)
			if r.begins_with("!"):
				b.human_done()
	print("winner=", b.winner, " round=", b.round)
	for i in range(maxi(0, b.log.size() - 15), b.log.size()):
		print("  |", b.log[i])
	quit(0)
