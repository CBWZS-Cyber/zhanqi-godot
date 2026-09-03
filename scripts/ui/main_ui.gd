extends Control
## 游戏总菜单（仅 UI 导航，不含玩法）：
##   开始界面 → 选择模式（联机 / 离线 / 剧情模式）
##     联机 → 1V1 / 4V4
##     离线 → 选难度（简单/普通/困难）→ 1V1 / 4V4
##     剧情模式 → 直接进入（不再选难度）
##   最终选择进入“结果占位”页（玩法后续再接）。
## 居中：卡片显式取内容尺寸，绕自身中心缩放（pivot），
##       position 使卡片中心 = 视口中心 → 引擎布局不参与也能保证居中。
## 自适应：每帧按窗口尺寸算 _scale，放大/全屏时文字按钮等比变大且始终居中。

const BG_COLOR := Color(0.102, 0.125, 0.208)  # 深蓝灰
const BASE := Vector2(1280, 720)               # 设计基准
const BOARD_SCENE := "res://scenes/Board.tscn"

var _bg: ColorRect
var _scale := 1.0
var _panels := {}
var _current := ""
var _config := {}
var _result_label: Label
var _confs: Array[Dictionary] = []   # 各卡片 VBox 间距/边距（随 _scale 重算）

func _ready() -> void:
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	add_child(_bg)

	_build_screen("start", "战棋", 80, true,
		[["开始游戏", Callable(self, "_on_start")],
		 ["退出", Callable(self, "_on_quit")]], "")
	_build_screen("mode", "选择模式", 44, false,
		[["联机模式", Callable(self, "_on_online")],
		 ["离线模式", Callable(self, "_on_offline")],
		 ["剧情模式", Callable(self, "_on_story")]], "start")
	_build_screen("online", "联机模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_battle").bind("online", "1v1")],
		 ["4V4", Callable(self, "_on_battle").bind("online", "4v4")]], "mode")
	_build_screen("diff", "离线模式 · 选择难度", 44, false,
		[["简单", Callable(self, "_on_diff").bind("easy")],
		 ["普通", Callable(self, "_on_diff").bind("normal")],
		 ["困难", Callable(self, "_on_diff").bind("hard")]], "mode")
	_build_screen("offline", "离线模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_battle").bind("offline", "1v1")],
		 ["4V4", Callable(self, "_on_battle").bind("offline", "4v4")]], "diff")
	_build_result()

	_show_panel("start")
	get_viewport().size_changed.connect(_fit)
	call_deferred("_fit")

func _process(_delta: float) -> void:
	_fit()

## 每帧：字号/间距/最小尺寸按 _scale 真实重算（不用 Control.scale 放大，避免全屏文字发糊），
## 卡片取最新内容尺寸后绕中心居中。
func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = clampf(min(vp.x / BASE.x, vp.y / BASE.y), 0.5, 2.4)
	_bg.size = vp
	_bg.position = Vector2.ZERO

	# 各卡片 VBox 的间距/边距
	for cf in _confs:
		var box: Variant = cf.get("box")
		if typeof(box) != TYPE_OBJECT or box == null or not is_instance_valid(box):
			continue
		var bc: Container = box as Container
		bc.add_theme_constant_override("separation", int(cf.get("sep", 0.0) * _scale))
		bc.add_theme_constant_override("margin_left", int(cf.get("ml", 0.0) * _scale))
		bc.add_theme_constant_override("margin_right", int(cf.get("mr", 0.0) * _scale))
		bc.add_theme_constant_override("margin_top", int(cf.get("mt", 0.0) * _scale))
		bc.add_theme_constant_override("margin_bottom", int(cf.get("mb", 0.0) * _scale))

	# 可见卡片：真实字号/尺寸 + 居中
	var p: Control = _panels.get(_current)
	if p != null and p.visible:
		_apply_node_sizes(p)
		var m := p.get_combined_minimum_size()
		p.size = m
		p.scale = Vector2.ONE
		p.pivot_offset = Vector2.ZERO
		p.position = vp / 2.0 - m / 2.0

## 递归：把带 meta("fz"/"min_x"/"min_y") 的控件字号/最小尺寸乘 _scale
func _apply_node_sizes(n: Node) -> void:
	for ch in n.get_children():
		if not is_instance_valid(ch):
			continue
		if ch is Control:
			var co := ch as Control
			if co.has_meta("fz"):
				var sz: int = maxi(8, int(round(float(co.get_meta("fz")) * _scale)))
				if ch is Label:
					(co as Label).add_theme_font_size_override("font_size", sz)
				elif ch is Button:
					(co as Button).add_theme_font_size_override("font_size", sz)
			if co.has_meta("min_x"):
				co.custom_minimum_size.x = float(co.get_meta("min_x")) * _scale
			if co.has_meta("min_y"):
				co.custom_minimum_size.y = float(co.get_meta("min_y")) * _scale
		if ch.get_child_count() > 0:
			_apply_node_sizes(ch)

## F11 在 Godot 里默认没绑任何事；这里手动切换真正的全屏/窗口模式
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN

# ---------- 导航 ----------
func _show_panel(name: String) -> void:
	for k in _panels:
		_panels[k].visible = (k == name)
	_current = name
	_fit()

func _on_start() -> void:
	_show_panel("mode")

func _on_online() -> void:
	_config["mode"] = "online"
	_show_panel("online")

func _on_offline() -> void:
	_config["mode"] = "offline"
	_show_panel("diff")

func _on_story() -> void:
	_config = {"mode": "story"}
	_show_result()

func _on_diff(d: String) -> void:
	_config["difficulty"] = d
	_show_panel("offline")

func _on_battle(mode: String, battle: String) -> void:
	_config["mode"] = mode
	_config["battle"] = battle
	_show_result()

func _on_back(to: String) -> void:
	_show_panel(to)

func _on_to_menu() -> void:
	_config = {}
	_show_panel("start")

func _on_quit() -> void:
	get_tree().quit()

func _on_enter_board() -> void:
	var battle: String = _config.get("battle", "")
	Global.battle_mode = battle if battle == "4v4" else "1v1"
	# 1V1 = 可玩对局（选英雄 + 人机操作）；4V4 暂用展示棋盘
	if battle == "1v1":
		get_tree().change_scene_to_file("res://scenes/Duel.tscn")
	else:
		get_tree().change_scene_to_file(BOARD_SCENE)

func _show_result() -> void:
	var mode: String = _config.get("mode", "")
	var diff: String = _config.get("difficulty", "")
	var battle: String = _config.get("battle", "")
	var parts: Array[String] = []
	if mode == "story":
		parts.append("剧情模式")
	else:
		parts.append("联机模式" if mode == "online" else "离线模式")
		if mode == "offline" and diff != "":
			parts.append(_diff_name(diff))
		match battle:
			"1v1":
				parts.append("1V1")
			"4v4":
				parts.append("4V4")
	_result_label.text = " · ".join(parts)
	_show_panel("result")

func _diff_name(d: String) -> String:
	return "简单" if d == "easy" else ("普通" if d == "normal" else "困难")

# ---------- 构建界面 ----------
func _build_screen(key: String, title: String, title_size: int, with_shadow: bool,
		specs: Array, back_to: String) -> void:
	var card := _make_card(title, title_size, with_shadow)
	var vbox: VBoxContainer = card.get_meta("vbox")
	for i in range(specs.size()):
		var entry: Array = specs[i]
		var text: String = entry[0]
		var cb: Callable = entry[1]
		vbox.add_child(_make_button(text, cb))
	if back_to != "":
		vbox.add_child(_make_button("返回", Callable(self, "_on_back").bind(back_to)))
	add_child(card)
	card.visible = false
	_panels[key] = card

func _build_result() -> void:
	var card := _make_card("准备开始", 44, false)
	var vbox: VBoxContainer = card.get_meta("vbox")
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 30)
	_result_label.set_meta("fz", 30.0)
	_result_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96))
	vbox.add_child(_result_label)
	vbox.add_child(_make_button("进入棋盘（占位）", Callable(self, "_on_enter_board")))
	vbox.add_child(_make_button("返回菜单", Callable(self, "_on_to_menu")))
	add_child(card)
	card.visible = false
	_panels["result"] = card

func _make_card(title: String, title_size: int, with_shadow: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.176, 0.271, 0.92)
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style["corner_radius_" + r] = 18
	card.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.add_theme_constant_override("margin_left", 56)
	vbox.add_theme_constant_override("margin_right", 56)
	vbox.add_theme_constant_override("margin_top", 44)
	vbox.add_theme_constant_override("margin_bottom", 44)
	_confs.append({"box": vbox, "sep": 24.0, "ml": 56.0, "mr": 56.0, "mt": 44.0, "mb": 44.0})
	card.add_child(vbox)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", title_size)
	t.set_meta("fz", float(title_size))
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))  # 金色
	if with_shadow:
		t.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.55))
		t.add_theme_constant_override("shadow_offset_x", 3)
		t.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(t)
	card.set_meta("vbox", vbox)
	return card

func _make_button(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.set_meta("min_x", 300.0)
	btn.set_meta("min_y", 60.0)
	btn.set_meta("fz", 24.0)
	btn.custom_minimum_size = Vector2(300, 60)
	btn.add_theme_stylebox_override("normal", _btn_style(Color(0.941, 0.780, 0.369)))
	btn.add_theme_stylebox_override("hover", _btn_style(Color(1.0, 0.88, 0.55)))
	btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.78, 0.62, 0.22)))
	btn.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(cb)
	return btn

func _btn_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s["corner_radius_" + r] = 10
	return s
