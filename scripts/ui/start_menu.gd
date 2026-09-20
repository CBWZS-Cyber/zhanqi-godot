extends Control
## 开始界面：标题 + “开始游戏” / “退出”。
## 点“开始游戏”切换到棋盘场景；点“退出”关闭游戏。
## 自适应：每帧按窗口尺寸等比缩放整块 UI 并居中。

const START_SCENE := "res://scenes/Board.tscn"
const BG_COLOR := Color(0.102, 0.125, 0.208)  # 深蓝灰
const BASE := Vector2(1280, 720)               # 设计基准

var _vbox: VBoxContainer
var _panel: Panel
var _bg: ColorRect
var _scale := 1.0
var _last_size := Vector2.ZERO

func _ready() -> void:
	# 背景：显式铺满视口，不依赖锚点布局
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	add_child(_bg)

	# 标题
	var title := Label.new()
	title.text = "战棋"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))  # 金色
	title.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)

	# 按钮样式
	var btn_normal := _make_button_style(Color(0.941, 0.780, 0.369))
	var btn_hover := _make_button_style(Color(1.0, 0.88, 0.55))
	var btn_pressed := _make_button_style(Color(0.78, 0.62, 0.22))

	var start_btn := _make_button("开始游戏", btn_normal, btn_hover, btn_pressed)
	var quit_btn := _make_button("退出", btn_normal, btn_hover, btn_pressed)

	# 垂直容器
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 28)
	_vbox.add_child(title)
	_vbox.add_child(start_btn)
	_vbox.add_child(quit_btn)

	# 装饰面板（在 vbox 后面）
	_panel = Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.145, 0.176, 0.271, 0.92)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(_panel)
	add_child(_vbox)

	_fit()
	get_viewport().size_changed.connect(_fit)

	start_btn.pressed.connect(_on_start_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

## 每帧都重排：不依赖 size_changed 信号，保证最大化/全屏必定生效
func _process(_delta: float) -> void:
	_fit()

## F11 在 Godot 里默认没绑任何事；这里手动切换真正的全屏/窗口模式
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN

## 按当前视口尺寸，等比缩放（取较小边，保证整块 UI 可见）并居中
func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp == _last_size:
		return
	_last_size = vp
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = min(vp.x / BASE.x, vp.y / BASE.y)

	# 背景铺满整窗
	_bg.size = vp
	_bg.position = Vector2.ZERO

	var minsz := _vbox.get_combined_minimum_size()
	_vbox.scale = Vector2(_scale, _scale)
	_vbox.position = (vp - minsz * _scale) / 2.0

	var pmin := minsz + Vector2(80, 70)
	_panel.scale = Vector2(_scale, _scale)
	_panel.position = (vp - pmin * _scale) / 2.0

	print("[Menu] 视口=", get_viewport_rect().size, " 缩放=", snapped(_scale, 0.001))

func _make_button(text: String, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 64)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_font_size_override("font_size", 24)
	return btn

func _make_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style

func _on_start_pressed() -> void:
	Sfx.play("click")
	get_tree().change_scene_to_file(START_SCENE)

func _on_quit_pressed() -> void:
	Sfx.play("click")
	get_tree().quit()
