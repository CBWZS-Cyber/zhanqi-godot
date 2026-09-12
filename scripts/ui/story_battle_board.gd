extends Control
## 剧情关卡棋盘控件（自由拼格地图，如 maps/白灵殿.json）
## 与 team_board（4V4 标准 8×8）的区别：
##   - 格子来自地图文件（可为负坐标、非矩形），按 bbox 自动缩放适配；
##   - 支持滚轮缩放 / 拖动平移（地图 32×12 远大于视口）；
##   - 额外渲染：逃生区（青色高亮，2026-09-12 起为最右侧 4 格）、护送目标（昊 / 祁，金色光环；
##     已就位者转为青色光环）。
## 渲染数据由上层 story_battle.gd 灌入；点击发 cell_clicked(cell)。

signal cell_clicked(cell: Vector2i)
signal right_clicked(cell: Vector2i)

const UnitToken = preload("res://scripts/ui/unit_token.gd")

const GRID := 46.0
const COL_EDGE := Color(0.16, 0.13, 0.10, 0.85)
const COL_MOVE := Color(0.40, 0.82, 0.48, 0.45)
const COL_MOVE_EDGE := Color(0.55, 0.95, 0.62, 0.9)
const COL_TARGET := Color(0.98, 0.55, 0.25, 0.5)
const COL_ESCAPE := Color(0.35, 0.85, 0.95, 0.42)
const COL_ESCAPE_EDGE := Color(0.70, 1.0, 1.0, 0.95)

var cells: Dictionary = {}          # "x,y" -> type(int)
var type_colors: Dictionary = {}    # type(int) -> Color
var escape_cells: Array = []
var move_cells: Array = []
var target_cells: Array = []
var chosen_cells: Array = []        # 多目标技已点选的格（比 target_cells 更亮的环）
var protect_unit = null             # 护送目标①（昊）
var protect_unit2 = null            # 护送目标②（祁）—— 2026-09-12 起双人护送
var unit_objs: Array = []           # BattleUnit（存活）

var _bbox_min := Vector2.ZERO
var _bbox_max := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _press_pos := Vector2.ZERO
var _press_moved := false
var _tokens := {}
var _focus_ref = null
var _cur_ref = null
var _last_size := Vector2.ZERO

func set_map(cells_dict: Dictionary, types: Dictionary, escapes: Array) -> void:
	cells = cells_dict
	type_colors = {}
	for t in types:
		type_colors[int(t)] = _hex_color(str((types[t] as Dictionary).get("color", "#888888")))
	escape_cells = escapes
	# bbox
	var minx := 999999
	var maxx := -999999
	var miny := 999999
	var maxy := -999999
	for k in cells:
		var c := _v2i(str(k))
		minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	_bbox_min = Vector2(minx, miny)
	_bbox_max = Vector2(maxx, maxy)
	_fit_view()
	queue_redraw()

func set_battle_units(arr: Array, focus_u = null, cur_u = null, protect_u = null, protect_u2 = null) -> void:
	unit_objs = []
	for u in arr:
		if u != null and u.alive:
			unit_objs.append(u)
	_focus_ref = focus_u
	_cur_ref = cur_u
	if protect_u != null:
		protect_unit = protect_u
	if protect_u2 != null:
		protect_unit2 = protect_u2
	_sync_tokens()
	queue_redraw()

# ------------------------------------------------------------ 坐标
func _world_size() -> Vector2:
	return (_bbox_max - _bbox_min + Vector2.ONE) * GRID

func _fit_view() -> void:
	var w := _world_size()
	if w.x <= 0 or w.y <= 0 or size.x <= 0 or size.y <= 0:
		return
	_zoom = clampf(minf((size.x - 16.0) / w.x, (size.y - 16.0) / w.y), 0.25, 2.0)
	var center := (_bbox_min + _bbox_max + Vector2.ONE) * 0.5 * GRID
	_pan = size * 0.5 - center * _zoom
	queue_redraw()

func cell_rect(cell: Vector2i) -> Rect2:
	var p := (Vector2(cell) - _bbox_min) * GRID * _zoom + _pan
	return Rect2(p, Vector2(GRID, GRID) * _zoom)

func cell_at(pos: Vector2) -> Vector2i:
	var v := (pos - _pan) / (GRID * _zoom) + _bbox_min
	return Vector2i(int(floor(v.x)), int(floor(v.y)))

func has_cell(c: Vector2i) -> bool:
	return cells.has(_ck(c))

func _ck(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _v2i(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1]))

func _hex_color(h: String) -> Color:
	var s := h.trim_prefix("#")
	if s.length() != 6:
		return Color(0.45, 0.42, 0.36)
	return Color(s.substr(0, 2).hex_to_int() / 255.0,
		s.substr(2, 2).hex_to_int() / 255.0,
		s.substr(4, 2).hex_to_int() / 255.0)

# ------------------------------------------------------------ 输入
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_press_moved = false
				_press_pos = mb.position
			else:
				_drag = false
				if not _press_moved:
					var c := cell_at(mb.position)
					if has_cell(c):
						cell_clicked.emit(c)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(cell_at(mb.position))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			var nz := clampf(_zoom * factor, 0.25, 3.0)
			_pan = mb.position - (mb.position - _pan) * (nz / _zoom)
			_zoom = nz
			_sync_tokens()
			queue_redraw()
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 6.0:
			_press_moved = true
		_pan += mm.relative
		_sync_tokens()
		queue_redraw()

func _process(_d: float) -> void:
	if size != _last_size:
		_last_size = size
		_sync_tokens()
		queue_redraw()

func center_on(cell: Vector2i) -> void:
	var center := (Vector2(cell) - _bbox_min + Vector2(0.5, 0.5)) * GRID
	_pan = size * 0.5 - center * _zoom
	_sync_tokens()
	queue_redraw()

# ------------------------------------------------------------ 绘制
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.12, 0.11))
	if cells.is_empty():
		return
	for k in cells:
		var c := _v2i(str(k))
		var r := cell_rect(c)
		if not r.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var t := int(cells[k])
		var col: Color = type_colors.get(t, Color(0.45, 0.42, 0.36))
		draw_rect(r, col)
		if escape_cells.has(c):
			draw_rect(r, COL_ESCAPE)
			draw_rect(r, COL_ESCAPE_EDGE, false, maxf(1.5, 2.0 * _zoom))
		elif move_cells.has(c):
			draw_rect(r, COL_MOVE)
			draw_rect(r, COL_MOVE_EDGE, false, maxf(1.0, 1.5 * _zoom))
		elif target_cells.has(c):
			draw_rect(r, COL_TARGET)
			draw_rect(r, Color(1.0, 0.75, 0.35, 0.95), false, maxf(1.5, 2.0 * _zoom))
		else:
			draw_rect(r, COL_EDGE, false, maxf(1.0, 1.0 * _zoom))
		if chosen_cells.has(c):
			draw_rect(r, Color(1.0, 0.95, 0.55, 0.30))
			draw_rect(r, Color(1.0, 0.98, 0.70, 1.0), false, maxf(2.5, 4.0 * _zoom))
	# 逃生区标记文字（缩放够大时才画）
	if _zoom > 0.45:
		var fnt := get_theme_default_font()
		if fnt != null:
			for c in escape_cells:
				var cc: Vector2i = c
				var r2 := cell_rect(cc)
				if not r2.intersects(Rect2(Vector2.ZERO, size)):
					continue
				var fs := clampi(int(GRID * _zoom * 0.30), 8, 22)
				draw_string(fnt, Vector2(r2.position.x + 4.0, r2.position.y + r2.size.y - 4.0), "逃生",
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.35, 0.45))
	# 护送目标金色光环（昊 + 祁；已就位的用青色环区分）
	for pu in [protect_unit, protect_unit2]:
		var p := pu
		if p != null and p.alive:
			var pr := cell_rect(p.cell)
			var arrived: bool = escape_cells.has(p.cell)
			var ring_col := Color(0.45, 1.0, 0.95, 0.95) if arrived else Color(1.0, 0.88, 0.35, 0.95)
			draw_arc(pr.get_center(), pr.size.x * 0.46, 0.0, TAU, 40, ring_col, maxf(2.0, 3.0 * _zoom), true)

# ------------------------------------------------------------ 棋子 Node 层
func _sync_tokens() -> void:
	var want := {}
	for u in unit_objs:
		want[str(u.get_instance_id())] = u
	var dead: Array = []
	for k in _tokens:
		if not want.has(k):
			dead.append(k)
	for k in dead:
		var t = _tokens[k]
		if is_instance_valid(t):
			t.queue_free()
		_tokens.erase(k)
	for u in unit_objs:
		var tok = _tokens.get(str(u.get_instance_id()))
		if tok == null:
			tok = UnitToken.new()
			tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tok)
			_tokens[str(u.get_instance_id())] = tok
		var r := cell_rect(u.cell)
		tok.position = r.position
		tok.size = r.size
		tok.setup(u, u == _focus_ref or u == _cur_ref)
