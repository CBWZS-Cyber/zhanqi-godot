extends SceneTree
## 主菜单背景视频验证：资源加载 + 播放状态 + 压暗遮罩
## 运行：godot --headless --path . -s res://tests/menu_bg_check.gd

var _asserts := 0
var _fails := 0

func _ok(cond: bool, msg: String) -> void:
	_asserts += 1
	print(("  [OK] " if cond else "  [FAIL] ") + msg)
	if not cond:
		_fails += 1

func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null

func _initialize() -> void:
	print("=== 主菜单背景视频验证 ===")

	# 1. 资源层
	_ok(ResourceLoader.exists("res://assets/video/menu_bg.ogv"), "menu_bg.ogv 资源存在")
	var stream: VideoStream = load("res://assets/video/menu_bg.ogv")
	_ok(stream != null, "视频流可加载（VideoStreamTheora）")

	# 2. MainUI 实例化后背景视频层工作正常
	var packed: PackedScene = load("res://scenes/MainUI.tscn")
	var ui: Node = packed.instantiate()
	root.add_child(ui)
	await process_frame

	var vsp: Node = _find(ui, "VideoStreamPlayer")
	_ok(vsp != null, "主菜单中存在背景视频层（VideoStreamPlayer）")
	if vsp != null:
		_ok(vsp.stream != null, "视频流已设置")
		_ok(vsp.is_playing(), "视频正在播放")
		_ok(vsp.mouse_filter == Control.MOUSE_FILTER_IGNORE, "视频层不拦截鼠标（UI 可正常点击）")

	# 3. 压暗遮罩存在（保证 UI 可读）
	var dim_found := false
	for c in ui.get_children():
		if c is ColorRect and c != ui._bg and c.color.a >= 0.3:
			dim_found = true
			break
	_ok(dim_found, "压暗遮罩存在（视频之上、UI 之下）")

	# 4. 循环信号已连接（finished -> play）
	if vsp != null:
		var connected: bool = vsp.finished.is_connected(vsp.play)
		_ok(connected, "循环播放已连接（finished -> play）")

	print("")
	print("断言 %d 条，失败 %d 条" % [_asserts, _fails])
	quit(1 if _fails > 0 else 0)
