extends Control
## 剧情地图展示器（骑士线第一关：白灵殿）
## 读取 maps/*.json（zhanqi-map v5，自由拼格）：地形配色渲染 + 出生点/单位标注 + 平移缩放
## 操作：左键拖动平移；滚轮缩放（以鼠标为中心）；返回按钮回主菜单

const MAP_PATH := "res://maps/白灵殿.json"
const GRID := 48.0
const BG := Color(0.16, 0.15, 0.13)
const PANEL := Color(0.08, 0.10, 0.15, 0.85)
const TEAM_COL := {"red": Color(0.80, 0.27, 0.20), "blue": Color(0.26, 0.45, 0.80),
	"green": Color(0.30, 0.62, 0.34), "yellow": Color(0.80, 0.72, 0.25)}

var _map: Dictionary = {}
var _cells: Array = []
var _types: Dictionary = {}
var _spawns: Array = []
var _units_names: Dictionary = {}   # cell(x,y) → 显示名
var _bbox_min := Vector2.ZERO
var _bbox_max := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _drag_last := Vector2.ZERO
var _info := ""

func _ready() -> void:
	get_viewport().size_changed.connect(func(): queue_redraw())
	_build_ui()
	if not _load_map():
		_info = "地图加载失败：%s" % MAP_PATH
		return
	_info = "%s：%d 格 · %d 出生点 · 滚轮缩放 / 拖动平移" % [str(_map.get("name", "")), _cells.size(), _spawns.size()]
	_fit_view()
	queue_redraw()

func _load_map() -> bool:
	if not FileAccess.file_exists(MAP_PATH):
		return false
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	_map = parsed
	_cells = _map.get("cells", [])
	for t in _map.get("types", []):
		var td: Dictionary = t
		_types[int(td.get("id", 0))] = td
	_spawns = _map.get("spawns", [])
	# 出生点名称映射（spawn 已带 unit；units 表按队给面板用，展示只取名）
	for sp in _spawns:
		var sd: Dictionary = sp
		var key := Vector2(int(sd.get("x", 0)), int(sd.get("y", 0)))
		_units_names[key] = "%s·%s" % [str(sd.get("team", "?")), str(sd.get("unit", "?"))]
	if _cells.is_empty():
		return false
	var minx := 99999
	var maxx := -99999
	var miny := 99999
	var maxy := -99999
	for c in _cells:
		var cd: Dictionary = c
		minx = mini(minx, int(cd.get("x", 0)))
		maxx = maxi(maxx, int(cd.get("x", 0)))
		miny = mini(miny, int(cd.get("y", 0)))
		maxy = maxi(maxy, int(cd.get("y", 0)))
	_bbox_min = Vector2(minx, miny)
	_bbox_max = Vector2(maxx, maxy)
	return true

func _fit_view() -> void:
	var vp := size
	var world := (_bbox_max - _bbox_min + Vector2.ONE) * GRID
	if world.x <= 0 or world.y <= 0:
		return
	_zoom = minf((vp.x - 240.0) / world.x, (vp.y - 160.0) / world.y)
	_zoom = clampf(_zoom, 0.3, 2.5)
	_center_view()

func _center_view() -> void:
	var center := (_bbox_min + _bbox_max + Vector2.ONE) * 0.5 * GRID
	_pan = size * 0.5 - center * _zoom

func _build_ui() -> void:
	var back := Button.new()
	back.text = "‹ 返回菜单"
	back.position = Vector2(14, 14)
	back.custom_minimum_size = Vector2(140, 40)
	back.add_theme_font_size_override("font_size", 16)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainUI.tscn"))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.10, 0.12, 0.19, 0.9)
	n.border_color = Color(0.45, 0.42, 0.30)
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	var h := n.duplicate(); h.bg_color = Color(0.20, 0.23, 0.36)
	back.add_theme_stylebox_override("normal", n)
	back.add_theme_stylebox_override("hover", h)
	back.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	add_child(back)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_drag_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			var nz := clampf(_zoom * factor, 0.25, 4.0)
			_pan = mb.position - (mb.position - _pan) * (nz / _zoom)
			_zoom = nz
			queue_redraw()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_pan += mm.relative
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	# 格子
	for c in _cells:
		var cd: Dictionary = c
		var cell := Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0)))
		var tp := int(cd.get("type", 0))
		var td: Dictionary = _types.get(tp, {"color": "#666666"})
		var col := _hex_color(str(td.get("color", "#666666")))
		var r := Rect2(Vector2(cell) * GRID * _zoom + _pan, Vector2(GRID, GRID) * _zoom)
		draw_rect(r, col)
		draw_rect(r, Color(0.9, 0.9, 0.9, 0.10), false, 1.0)
	# 出生点 + 单位名
	var fnt := get_theme_default_font()
	for sp in _spawns:
		var sd: Dictionary = sp
		var p := Vector2(float(sd.get("x", 0)) + 0.5, float(sd.get("y", 0)) + 0.5) * GRID * _zoom + _pan
		var tc: Color = TEAM_COL.get(str(sd.get("team", "red")), Color.WHITE)
		draw_circle(p, 7.0 * _zoom, tc)
		draw_arc(p, 7.0 * _zoom, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 2.0, true)
		if fnt != null:
			var label := str(sd.get("unit", ""))
			var fs := maxi(9, int(12.0 * _zoom))
			var w := fnt.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(fnt, p - Vector2(w / 2.0, -13.0 * _zoom), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.98, 0.9))
	# 顶部信息条
	var ib := Rect2(Vector2(170, 14), Vector2(size.x - 200.0, 40))
	draw_rect(ib, PANEL)
	draw_rect(ib, Color(0.941, 0.780, 0.369), false, 1.0)
	if fnt != null:
		draw_string(fnt, Vector2(184, 42), "白灵殿 · 骑士线", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.97, 0.9))
	# 图例（左下）
	var ly := size.y - 30.0
	draw_rect(Rect2(12, ly - 18.0 * _types.size() - 14, 210, 18.0 * _types.size() + 20), PANEL)
	var i := 0
	for k in _types:
		var td: Dictionary = _types[k]
		draw_rect(Rect2(22, ly - 18.0 * _types.size() + i * 18.0, 12, 12), _hex_color(str(td.get("color", "#888"))))
		draw_string(fnt, Vector2(42, ly - 18.0 * _types.size() + i * 18.0 + 11), "%d %s" % [int(k), str(td.get("name", ""))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.94))
		i += 1
	# 底部提示
	if fnt != null:
		draw_string(fnt, Vector2(size.x * 0.5 - 220.0, size.y - 12.0), _info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.64, 0.7))

func _hex_color(h: String) -> Color:
	var s := h.trim_prefix("#")
	if s.length() != 6:
		return Color(0.4, 0.4, 0.4)
	return Color(s.substr(0, 2).hex_to_int() / 255.0,
		s.substr(2, 2).hex_to_int() / 255.0,
		s.substr(4, 2).hex_to_int() / 255.0)
