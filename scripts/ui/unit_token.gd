extends Control
## 单位棋子（实体渲染）：圆形棋子 + 阵营色 + 名字标在棋子上方

var team := 0
var hero_name := ""
var hp_text := ""
var selected := false
var statuses: Array = []     # [{cn, lv, id}] —— 棋子上方状态徽章
var _col := Color(0.78, 0.25, 0.18)

func setup(t: int, uname: String, hpt: String, sel: bool, sts: Array = []) -> void:
	team = t
	hero_name = uname
	hp_text = hpt
	selected = sel
	statuses = sts if sts != null else []
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
	# 名字：棋子正中（长名自动缩小字号）
	var f := get_theme_default_font()
	if f != null and hero_name != "":
		var fs := int(size.y * 0.15)
		var max_fs := int(r * 2.0 / maxi(2.0, hero_name.length() * 1.05))
		fs = clampi(mini(fs, max_fs), 10, 22)
		var w := f.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, Vector2(c.x - w / 2.0, c.y + fs * 0.36), hero_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1), -1.0)
	# 状态徽章（棋子上方一排，让玩家一眼看到流血/灼烧/中毒…）
	if not statuses.is_empty():
		var br := maxf(5.0, minf(size.x, size.y) * 0.055)
		var gap := br * 0.45
		var n := statuses.size()
		var total := float(n) * (br * 2.0) + float(maxi(0, n - 1)) * gap
		var sx := c.x - total / 2.0 + br
		var sy := c.y - r - br * 1.2
		for st in statuses:
			var d: Dictionary = st as Dictionary
			var cn := str(d.get("cn", ""))
			var lv := int(d.get("lv", 0))
			draw_circle(Vector2(sx, sy), br, _status_color(str(d.get("id", ""))))
			draw_arc(Vector2(sx, sy), br, 0.0, TAU, 20, Color(0.05, 0.04, 0.03), 1.0, true)
			var label := cn.substr(0, 1) if cn.length() > 0 else "?"
			if lv > 1:
				label += str(lv)
			var lfs := maxi(8, int(br * 1.05))
			var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
			draw_string(f, Vector2(sx - lw / 2.0, sy + lfs * 0.34), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(1, 1, 1), -1.0)
			sx += br * 2.0 + gap
	# mouse_filter 忽略，点击穿透到格子按钮
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 状态徽章配色（与 4V4 team_board.gd 保持一致）
func _status_color(sid: String) -> Color:
	match sid:
		"bleed":
			return Color(0.75, 0.10, 0.12)
		"burn", "burn2":
			return Color(0.92, 0.45, 0.08)
		"wound":
			return Color(0.60, 0.20, 0.55)
		"heavy_wound":
			return Color(0.45, 0.12, 0.40)
		"freeze":
			return Color(0.30, 0.65, 0.90)
		"blind":
			return Color(0.35, 0.35, 0.40)
		"stun":
			return Color(0.95, 0.80, 0.20)
		"full_burn":
			return Color(1.00, 0.35, 0.10)
		"sword_field":
			return Color(0.85, 0.75, 0.45)
		"poison", "poison_layer":
			return Color(0.30, 0.60, 0.20)
		_:
			return Color(0.42, 0.44, 0.52)
