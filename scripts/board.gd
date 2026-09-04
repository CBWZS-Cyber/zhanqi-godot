@tool
extends Node2D
## 局内对战场景：标准棋盘（左区）+ 右侧棋子信息栏（battle_hud.gd）。
## 棋盘不含玩法逻辑；HUD 默认显示演示数据，接入棋子后由战斗逻辑更新。
## 自适应：以 1280x720 为设计基准；棋盘在扣除右侧信息栏后的左区等比居中，
## 右侧信息栏（宽度 = 视口宽 * 300/1280）覆盖棋子状态。每帧重排保证全屏生效。

const BASE := Vector2(1280, 720)
const CELL := 72.0
## 布局参数（可被 1V1 改写成 3×3+两侧出生格）：
var _x_min := 0
var _x_max := 9
var _y_min := 1
var _y_max := 8
var _cell := CELL
var _duel := false           # 1V1 专用：3×3 主区 + 左右各 1 出生格
const BG := Color(0.22, 0.20, 0.18)
const SIDE_PANEL_W := 300.0        # 与 battle_hud.gd 的 PANEL_RATIO 匹配（基准 1280）

var _scale := 1.0
var _origin := Vector2.ZERO
var _last_size := Vector2.ZERO
var main_cells: Array[Vector2i] = []
var wing_cells: Array[Vector2i] = []
var _hud: Control
var _back_btn: Button

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_duel = (Global.battle_mode == "1v1")
	if _duel:
		# 1V1 布局：主对局区 3×3（x1..3 / y1..3，y 向上），左右贴边各 1 个出生格（中间行 y=2）
		_x_min = 0
		_x_max = 4
		_y_min = 1
		_y_max = 3
		_cell = CELL * 2.2
		for x in range(1, 4):
			for y in range(1, 4):
				main_cells.append(Vector2i(x, y))
		wing_cells.append(Vector2i(0, 2))
		wing_cells.append(Vector2i(4, 2))
		print("[Board] 1V1 布局：3×3 主区 + 左(0,2)/右(4,2) 出生格")
	else:
		for x in range(1, 9):
			for y in range(1, 9):
				main_cells.append(Vector2i(x, y))
		for y in [3, 4, 5, 6]:
			wing_cells.append(Vector2i(0, y))
			wing_cells.append(Vector2i(9, y))
	# 右侧信息栏（CanvasLayer 隔离 UI 层，不随 Node2D 移动）
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hud = (load("res://scripts/ui/battle_hud.gd") as Script).new()
	layer.add_child(_hud)
	_hud.run_demo(Global.battle_mode)
	_make_back_button()
	_fit()
	get_viewport().size_changed.connect(_fit)

## 左上角：返回菜单（退出对局）
func _make_back_button() -> void:
	var bl := CanvasLayer.new()
	bl.layer = 20
	add_child(bl)
	_back_btn = Button.new()
	_back_btn.text = "‹ 返回菜单"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.12, 0.19, 0.9)
	normal.border_color = Color(0.45, 0.42, 0.30)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.20, 0.23, 0.36)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.08, 0.09, 0.15)
	_back_btn.add_theme_stylebox_override("normal", normal)
	_back_btn.add_theme_stylebox_override("hover", hover)
	_back_btn.add_theme_stylebox_override("pressed", pressed)
	_back_btn.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	_back_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	_back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/MainUI.tscn"))
	bl.add_child(_back_btn)

## 每帧都重排：不依赖 size_changed 信号，保证最大化/全屏必定生效
## F11 在 Godot 里默认没绑任何事；这里手动切换真正的全屏/窗口模式
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN

## 按当前视口尺寸，等比缩放（取较小边，保证整块棋盘可见、不裁切）
## 水平：扣除右侧信息栏后的左区内居中；垂直：整体居中。
func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp == _last_size:
		return
	_last_size = vp
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = min(vp.x / BASE.x, vp.y / BASE.y)
	var board_w := (_x_max - _x_min + 1) * _cell * _scale
	var board_h := (_y_max - _y_min + 1) * _cell * _scale
	var side := vp.x * (SIDE_PANEL_W / BASE.x)   # 右侧信息栏占宽
	var inner := vp.x - side
	var ox := (inner - board_w) / 2.0
	var oy := (vp.y - board_h) / 2.0
	_origin = Vector2(maxf(ox, 6.0), maxf(oy, 6.0))
	position = _origin
	# 返回按钮：左上角，随窗口等比
	if _back_btn != null:
		_back_btn.position = Vector2(10.0 * _scale, 10.0 * _scale)
		_back_btn.size = Vector2(130.0 * _scale, 40.0 * _scale)
		_back_btn.add_theme_font_size_override("font_size", maxi(11, int(round(16.0 * _scale))))
	print("[Board] 视口=", get_viewport_rect().size, " 缩放=", snapped(_scale, 0.001))
	queue_redraw()

## 棋盘坐标 -> 该格左上角像素矩形（本地坐标，已含缩放）
func _cell_rect(cell: Vector2i) -> Rect2:
	var px := (cell.x - _x_min) * _cell * _scale
	var py := (_y_max - cell.y) * _cell * _scale   # y 向上，故用 Y_MAX - y
	var sz := _cell * _scale
	return Rect2(px, py, sz, sz)

func _draw() -> void:
	# 铺满整个视口（缩放/居中由本脚本处理，底色随窗口铺满，无灰边）
	draw_rect(Rect2(-_origin, get_viewport_rect().size), BG)

	# 主对局区：国际象棋式深浅交替
	for c in main_cells:
		var r := _cell_rect(c)
		var dark := ((c.x + c.y) % 2 == 0)
		var col := Color(0.55, 0.40, 0.28) if dark else Color(0.93, 0.87, 0.74)
		draw_rect(r, col)
		draw_rect(r, Color(0.15, 0.12, 0.10), false, 2.0 * _scale)

	# 两翼：用不同颜色，明确“不属于对局区”
	for c in wing_cells:
		var r := _cell_rect(c)
		draw_rect(r, Color(0.40, 0.56, 0.74))
		draw_rect(r, Color(0.16, 0.28, 0.44), false, 2.0 * _scale)
