extends Control
## 单位棋子（实体渲染）：圆形棋子 + 阵营色 + 名字标在棋子上方

var team := 0
var hero_name := ""
var hp_text := ""
var selected := false
var _col := Color(0.78, 0.25, 0.18)

func setup(t: int, uname: String, hpt: String, sel: bool) -> void:
	team = t
	hero_name = uname
	hp_text = hpt
	selected = sel
	_col = Color(0.80, 0.27, 0.20) if team == 0 else Color(0.26, 0.45, 0.80)
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) * 0.34
	# 选中环
	if selected:
		draw_circle(c, r + 6.0, Color(1.0, 0.9, 0.5, 0.95))
	# 棋子本体（圆 + 深描边 + 高光）
	draw_circle(c, r, _col)
	draw_arc(c, r, 0.0, TAU, 48, Color(0.08, 0.06, 0.04), 3.0, true)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.32), r * 0.22, Color(1, 1, 1, 0.35))
	# 名字：棋子上方
	var f := get_theme_default_font()
	if f != null:
		var fs := maxi(12, int(size.y * 0.13))
		var w := f.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y - r - 6.0), hero_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.98, 0.9, 0.98))
		# 名字底影
	# HP 数字：棋子中心
	if f != null and hp_text != "":
		var fs2 := maxi(12, int(size.y * 0.14))
		var w2 := f.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(f, Vector2(c.x - w2 / 2.0, c.y + fs2 * 0.35), hp_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1))
	# mouse_filter 忽略，点击穿透到格子按钮
	mouse_filter = Control.MOUSE_FILTER_IGNORE
