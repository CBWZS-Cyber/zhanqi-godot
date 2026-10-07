extends SceneTree
## 首屏决策探针（2026-10-05）
##
## 回答一个问题：**启动后第一屏是什么**，以及它由什么决定。
## 判据在 `main_ui._initial_panel()`：
##     有登录态 → "start" ｜ 本机有离线进度 → "start" ｜ 全新 → "tut_login"
##
## 用法（关键：`APPDATA` 指向别处 = 模拟一台全新机器，**不动真实存档**）：
##   godot --headless --path . -s res://tests/_probes/first_screen_probe.gd
##   APPDATA=/tmp/fakeappdata godot --headless --path . -s res://tests/_probes/first_screen_probe.gd
##
## ⚠️ Windows 上 Godot 的 `user://` 由 `%APPDATA%\Godot\app_userdata\<项目名>\` 决定，
##    所以换 `APPDATA` 就等于换了一台"没玩过"的机器 —— 比挪用户存档安全得多。

var _ok := 0
var _bad := 0


func _initialize() -> void:
	_run()


func ck(cond: bool, name: String, extra := "") -> void:
	if cond:
		_ok += 1
		print("  ✓ ", name)
	else:
		_bad += 1
		print("  ✗ FAIL: ", name, ("  → " + extra) if extra != "" else "")


func _run() -> void:
	await process_frame

	print("\n=== 启动首屏探针 ===")
	print("  user:// 实际落点 = ", OS.get_user_data_dir())

	var ui: Node = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame          # 多等一帧：_ready 里有 call_deferred 的布局

	# ⚠️ `-s 脚本`模式下 **autoload 名在编译期解析不了**（本项目踩过，见 AICfg 头注释），
	#    所以这里一律走**运行时查找**（`get_node_or_null`）与 `call()`，不直接写 `Global.xxx`。
	var g: Node = root.get_node_or_null("Global")
	if g == null:
		ck(false, "能取到 autoload Global（-s 模式下的运行时查找）")
		print("\n=== 首屏探针：PASS %d / FAIL %d ===" % [_ok, _bad])
		quit(1)
		return

	# 判据的实际取值
	var online: bool = bool(g.get("cloud_online"))
	var has_prog: bool = ProgressStore.has_any()
	var panel: String = str(ui.call("_initial_panel"))
	var panels: Dictionary = ui.get("_panels")

	print("  Global.cloud_online      = ", online)
	print("  ProgressStore.has_any()  = ", has_prog)
	print("  _initial_panel()         = ", panel)

	# 当前真正可见的面板
	var shown: Array = []
	for k in panels.keys():
		var c = panels[k]
		if is_instance_valid(c) and c.visible:
			shown.append(k)
	print("  当前可见面板             = ", shown)

	print("  ⇒ 结论：", "直接进主菜单（跳过登录页）" if panel == "start" else "进登录页 tut_login")

	# 判据自洽性（不依赖环境）
	ck(panel == ("start" if (online or has_prog) else "tut_login"),
		"首屏与判据自洽（online/has_any → start，否则 tut_login）")
	ck(shown.size() == 1, "同一时刻只有一个面板可见", str(shown))

	print("\n=== 首屏探针：PASS %d / FAIL %d ===" % [_ok, _bad])
	quit(1 if _bad > 0 else 0)
