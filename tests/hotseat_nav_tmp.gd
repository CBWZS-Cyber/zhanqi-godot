extends SceneTree
## 验证热座导航修复：热座全链路不应出现"选择难度"页
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/MainUI.tscn")
	if scene == null:
		print("FAIL: MainUI.tscn 加载失败")
		quit(1)
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	var pass_all := true
	var cur = func(): return ui._current

	# PVE 路径：mode → offline_type(pve) → diff → offline → back 应回 diff
	ui._on_offline_type("pve")
	if ui._current != "diff":
		print("FAIL: PVE 应进难度页, got ", ui._current)
		pass_all = false
	ui._on_diff("easy")
	if ui._current != "offline":
		print("FAIL: 选难度后应进对局页")
		pass_all = false
	ui._on_back("diff")
	if ui._current != "diff":
		print("FAIL: PVE 从对局页返回应回难度页, got ", ui._current)
		pass_all = false
	else:
		print("PASS: PVE 返回 → 难度页")

	# 热座路径：mode → offline_type(hotseat) → 直接 offline（跳过 diff）→ back 应回 offline_type
	ui._on_to_menu()
	ui._show_panel("offline_type")
	ui._on_offline_type("hotseat")
	if ui._current != "offline":
		print("FAIL: 热座应直接进对局页（跳过难度）, got ", ui._current)
		pass_all = false
	else:
		print("PASS: 热座直接进对局页（不出现难度页）")
	if str(ui._config.get("difficulty", "")) != "-":
		print("FAIL: 热座 difficulty 应为 '-', got ", ui._config.get("difficulty"))
		pass_all = false
	ui._on_back("diff")
	if ui._current == "diff":
		print("FAIL: 热座返回不应进入难度页")
		pass_all = false
	elif ui._current == "offline_type":
		print("PASS: 热座返回 → 选择类型页（不经过难度）")
	else:
		print("FAIL: 热座返回到了意外页面: ", ui._current)
		pass_all = false

	print("==== 结果:", "PASS ✅" if pass_all else "FAIL ❌", "====")
	quit(0 if pass_all else 1)
