class_name UiKit
extends RefCounted
## 对局界面共用的控件样式工厂。
##
## 2026-09-30 结构收敛：原先 _style_btn / _panel_style / _make_bar 在
## duel.gd / team_duel.gd / story_battle.gd / tutorial.gd 里各存一份实现（共 15 份），
## 已合并到本文件。各界面保留同名薄壳转发，因此所有调用点无需改动。

const TEXT_COLOR := UiDesign.INK_100
const TEXT_HOVER_COLOR := UiDesign.GOLD_300
const TAG_COLOR := UiDesign.INK_200
const PANEL_BORDER_COLOR := UiDesign.BORDER
const BAR_BG_COLOR := UiDesign.BAR_TRACK
const BAR_NUM_COLOR := UiDesign.BAR_NUM
const BAR_NUM_SHADOW_COLOR := UiDesign.BAR_NUM_SHADOW


## 按钮三态样式（原各处 _style_btn）。
static func style_button(b: Button, text_color: Color = TEXT_COLOR) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = UiDesign.BTN_BG
	n.border_color = UiDesign.BTN_BORDER
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	var h := n.duplicate()
	h.bg_color = UiDesign.INK_650
	var pr := n.duplicate()
	pr.bg_color = UiDesign.BTN_BG_PRESSED
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", TEXT_HOVER_COLOR)


## 面板底色（原各处 _panel_style）。
## [param with_border] 置 false 时不描边，配合 margin_h / margin_v 走教程面板的内边距口径。
static func panel_style(col: Color, radius: int, with_border := true, margin_h := 0, margin_v := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	if radius > 0:
		sb.set_corner_radius_all(radius)
	if with_border:
		sb.border_color = PANEL_BORDER_COLOR
		sb.set_border_width_all(1)
	if margin_h > 0:
		sb.content_margin_left = margin_h
		sb.content_margin_right = margin_h
	if margin_v > 0:
		sb.content_margin_top = margin_v
		sb.content_margin_bottom = margin_v
	return sb


## 一行数值条：标签 + 条体（HpShieldBar 或 ProgressBar）+ 居中数字。
## [param compact] = 4V4 / 剧情用的紧凑口径（间距 8 / 字号 14 / 条高 22 / 数字无阴影）。
## [param show_num] 置 false 时数字标签留空，交由 DamageFx.update_bar 后续写入。
static func make_bar(tag: String, col: Color, value: float, max_value: float, tiled := false,
		compact := false, show_num := true) -> HBoxContainer:
	var font_size := 14 if compact else 15
	var bar_h := 22 if compact else 26
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if compact else 10)
	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.custom_minimum_size = Vector2(42, 0)
	tag_l.add_theme_font_size_override("font_size", font_size)
	tag_l.add_theme_color_override("font_color", TAG_COLOR)
	row.add_child(tag_l)
	var bar: Control
	if tiled:
		var hsb := HpShieldBar.new()
		hsb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hsb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hsb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hsb.custom_minimum_size = Vector2(0, bar_h)
		bar = hsb
	else:
		var pb := ProgressBar.new()
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.show_percentage = false
		pb.min_value = 0
		pb.max_value = max_value if max_value > 0 else 1
		pb.value = clampi(int(value), 0, int(pb.max_value))
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.custom_minimum_size = Vector2(0, bar_h)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(5)
		var bgst := StyleBoxFlat.new()
		bgst.bg_color = BAR_BG_COLOR
		bgst.set_corner_radius_all(5)
		pb.add_theme_stylebox_override("fill", fill)
		pb.add_theme_stylebox_override("background", bgst)
		bar = pb
	var num := Label.new()
	num.text = ("%.2f / %.2f" % [value, max_value]) if show_num else ""
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_color_override("font_color", BAR_NUM_COLOR)
	if not compact:
		num.add_theme_color_override("font_shadow_color", BAR_NUM_SHADOW_COLOR)
		num.add_theme_constant_override("shadow_offset_x", 2)
		num.add_theme_constant_override("shadow_offset_y", 2)
	bar.add_child(num)
	row.add_child(bar)
	return row
