extends SceneTree
## 剧情关棋盘缩放回归 —— 2026-09-14 建立
## 用法：Godot --headless --path 工程 -s res://tests/board_zoom_smoke.gd
##
## 背景：白灵殿地图 32 列 × 12 行（世界 1472×552px）。手机横屏 fit 之后
## 每格只剩 ~29px（720p 仅 ~20px），而触摸屏没有滚轮 → 之前完全没法缩放。
## 本测试用**合成触摸事件**驱动 _input()，无头验证双指捏合缩放。
## 全部通过 exit 0，有失败 exit 1。

var _pass := 0
var _fail := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)

# ---- 事件注入小工具 ----
func _touch(b, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	b._input(e)

func _drag(b, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	b._input(e)

func _mouse(b, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	b._gui_input(e)

func _initialize() -> void:
	await process_frame
	var Board = load("res://scripts/ui/story_battle_board.gd")
	var host := Control.new()
	host.size = Vector2(1000, 640)
	root.add_child(host)
	var b = Board.new()
	b.size = Vector2(1000, 640)
	host.add_child(b)
	await process_frame

	# ---------- 合成一张和真实白灵殿同规模的地图（32 × 12 格）----------
	var cells := {}
	for x in range(-13, 19):
		for y in range(-4, 8):
			cells["%d,%d" % [x, y]] = 0
	var types := {0: {"name": "空地", "color": "#E6DCC3"}}
	b.set_map(cells, types, [Vector2i(18, 0)], true)
	await process_frame

	var z_fit: float = b._zoom
	ck(z_fit > 0.0, "set_map 后已适配视图（zoom=%.3f）" % z_fit)
	ck(absf(z_fit - 0.62) < 0.08,
		"32 格宽地图在 1000px 棋盘上 fit 到 ~0.62（实际 %.3f）→ 每格 %.0fpx" % [z_fit, 46.0 * z_fit])

	# ---------- 双指张开 → 放大 ----------
	_touch(b, 0, Vector2(400, 300), true)
	_touch(b, 1, Vector2(600, 300), true)          # 间距 200
	ck(b._touch_pts.size() == 2, "两个触摸点已记录")
	ck(b._press_moved and not b._drag, "双指落下即掐断单指拖动 + 标记已移动")
	_drag(b, 1, Vector2(700, 300))                 # 间距 300 → 1.5x
	var z1: float = b._zoom
	ck(z1 > z_fit * 1.3, "双指张开 → 放大（%.3f → %.3f）" % [z_fit, z1])

	# ---------- 双指收拢 → 缩小 ----------
	var before: float = b._zoom
	_drag(b, 1, Vector2(500, 300))                 # 300 → 100
	ck(b._zoom < before, "双指收拢 → 缩小（%.3f → %.3f）" % [before, b._zoom])

	# ---------- 双指整体移动 → 顺带平移 ----------
	var pan_before: Vector2 = b._pan
	_touch(b, 0, Vector2(410, 300), true)
	_touch(b, 1, Vector2(510, 300), true)
	_touch(b, 0, Vector2(410, 360), true)
	_touch(b, 1, Vector2(510, 360), true)
	_drag(b, 0, Vector2(410, 360) + Vector2(0, 20))
	_drag(b, 1, Vector2(510, 360) + Vector2(0, 20))
	ck(b._pan != pan_before, "双指整体移动会带动地图平移")

	# 清场
	_touch(b, 0, Vector2(400, 300), false)
	_touch(b, 1, Vector2(500, 300), false)
	ck(b._touch_pts.is_empty(), "抬指后触摸点清空")
	ck(absf(b._pinch_dist) < 0.001, "抬指后双指间距基准归零")

	# ---------- 上限 / 下限 ----------
	b.zoom_at(100.0, b.size * 0.5)
	ck(absf(b._zoom - b.ZOOM_MAX) < 0.0001, "放大被 ZOOM_MAX 截住（%.2f）" % b._zoom)
	b.zoom_at(0.000001, b.size * 0.5)
	ck(absf(b._zoom - b.ZOOM_MIN) < 0.0001, "缩小被 ZOOM_MIN 截住（%.2f）" % b._zoom)

	# ---------- 单指不应触发缩放（手机单指只负责平移）----------
	b.reset_view()
	var zs: float = b._zoom
	_touch(b, 0, Vector2(400, 300), true)
	_drag(b, 0, Vector2(760, 420))
	_drag(b, 0, Vector2(300, 200))
	ck(absf(b._zoom - zs) < 0.0001, "单指拖动完全不改变缩放（保持 %.3f）" % b._zoom)
	_touch(b, 0, Vector2(300, 200), false)

	# ---------- 缩放锚点：锚点处的世界坐标必须不动 ----------
	b.reset_view()
	var anchor := Vector2(300, 200)
	var world_before: Vector2 = (anchor - b._pan) / b._zoom
	b.zoom_at(1.6, anchor)
	var world_after: Vector2 = (anchor - b._pan) / b._zoom
	ck(world_before.distance_to(world_after) < 0.01,
		"以锚点缩放后锚点处世界坐标不动（偏差 %.4f px）" % world_before.distance_to(world_after))

	# ---------- reset_view 回到 fit 档 ----------
	b.zoom_at(2.0, Vector2(500, 320))
	b.reset_view()
	ck(absf(b._zoom - z_fit) < 0.01, "reset_view() 回到 fit 档（%.3f ≈ %.3f）" % [b._zoom, z_fit])

	# ================= 关键安全项：捏合后抬手不能误触格子 =================
	# 手机没有右键，长按/捏合都靠触摸事件；放开时 emulate_mouse_from_touch 会补一个
	# 鼠标左键 release —— 如果不掐断，会被当成"点了一下格子"，可能误下移动/技能指令。
	var clicked: Array = []
	b.cell_clicked.connect(func(c: Vector2i) -> void: clicked.append(c))
	b.reset_view()
	# 先确认这个位置本来就点得到格子（否则测试没意义）
	var probe: Vector2i = b.cell_at(Vector2(500, 320))
	ck(b.has_cell(probe), "测试用点位 %s 确实是有效格子（保证测试有意义）" % str(probe))

	# 第 1 指按下（模拟鼠标左键同时按下）→ 第 2 指落下 → 捏开 → 两指抬起 → 鼠标 release
	_mouse(b, true, Vector2(500, 320))
	_touch(b, 0, Vector2(420, 300), true)
	_touch(b, 1, Vector2(620, 300), true)
	_drag(b, 1, Vector2(820, 300))
	_touch(b, 0, Vector2(420, 300), false)
	_touch(b, 1, Vector2(820, 300), false)
	_mouse(b, false, Vector2(500, 320))
	ck(clicked.is_empty(), "捏合缩放后抬手**不会**误触格子点击（实际触发 %d 次）" % clicked.size())

	# 对照：正常单指点击仍然必须能选中
	clicked.clear()
	_mouse(b, true, Vector2(500, 320))
	_mouse(b, false, Vector2(500, 320))
	ck(clicked.size() == 1, "普通单击仍然正常选中格子（实际 %d 次）" % clicked.size())

	# 对照：单指拖动（平移）后抬手也不应算点击
	clicked.clear()
	_mouse(b, true, Vector2(500, 320))
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(540, 340)
	mm.relative = Vector2(40, 20)
	b._gui_input(mm)
	_mouse(b, false, Vector2(540, 340))
	ck(clicked.is_empty(), "拖动平移后抬手不算点击（实际 %d 次）" % clicked.size())

	print("== 棋盘缩放回归结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
