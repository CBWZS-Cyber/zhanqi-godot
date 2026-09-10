extends Control
## 剧情地图·可交互棋盘（骑士线第一关：白灵殿）
## 读取 maps/白灵殿.json（zhanqi-map v5，自由拼格）：地形配色渲染 + 障碍。
## 单位：按地图出生点生成，数值/技能取自 data/story_chars.json（源自《角色属性与技能表.xlsx》）。
## 交互：
##   左键点击单位 → 选中并高亮其移动范围（蓝/红半透明）；点击高亮空格 → 移动至该格。
##   滚轮缩放（以鼠标为中心）；左键拖动平移。
##   回合制：全员按速度从高到低依次行动，仅“当前行动单位”可操作；上方高亮 + 右侧行动顺序表。
##   自由模式：解除回合限制，任意单位可点选移动（用于验证跑位 / 地图）。
##   返回按钮回主菜单。

const MAP_PATH := "res://maps/白灵殿.json"
const CHARS_PATH := "res://data/story_chars.json"
const GridBoardCls = preload("res://scripts/combat/grid_board.gd")
const GRID := 48.0
const BG := Color(0.16, 0.15, 0.13)
const PANEL := Color(0.08, 0.10, 0.15, 0.88)
const REACH_COL := Color(0.36, 0.78, 0.55, 0.42)
const REACH_EDGE := Color(0.55, 0.95, 0.70, 0.9)
const TEAM_COL := {0: Color(0.80, 0.27, 0.20), 1: Color(0.26, 0.45, 0.80)}

## 剧情单位（轻量运行时状态；数值来自 data/story_chars.json）
class StoryUnit extends RefCounted:
	var uid := 0
	var kind := ""        # 角色类型 key（战士/法师/龙/熊/昊/祁/大长老/宵）
	var name := ""
	var team := 1         # 0 红方 / 1 蓝方
	var element := ""
	var max_hp := 1
	var hp := 1
	var max_energy := 0
	var energy := 0
	var armor := 0
	var speed := 0
	var move_range := 3
	var passive := {}
	var skills := []
	var cell := Vector2i.ZERO

var _map: Dictionary = {}
var _cells: Array = []
var _types: Dictionary = {}
var _spawns: Array = []
var _board: GridBoard = null
var _units: Array = []            # Array[StoryUnit]
var _units_by_cell: Dictionary = {}  # "x,y" -> StoryUnit
var _order: Array = []            # 行动顺序（速度降序）
var _turn := 0
var _selected: StoryUnit = null
var _reach: Dictionary = {}       # "x,y" -> cost（选中单位可达空格）

var _free_mode := false

var _bbox_min := Vector2.ZERO
var _bbox_max := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _drag_last := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _press_moved := false
var _info := ""

# 按钮
var _back_btn: Button
var _free_btn: Button
var _next_btn: Button

func _ready() -> void:
	get_viewport().size_changed.connect(_on_resize)
	_build_ui()
	if not _load_map():
		_info = "地图加载失败：%s" % MAP_PATH
		queue_redraw()
		return
	_build_board()
	_build_units()
	_compute_order()
	_fit_view()
	_layout_buttons()
	queue_redraw()

# ---------------- 数据加载 ----------------
func _load_map() -> bool:
	if not FileAccess.file_exists(MAP_PATH):
		return false
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	_map = parsed
	_cells = _map.get("cells", [])
	for t in _map.get("types", []):
		var td: Dictionary = t
		_types[int(td.get("id", 0))] = td
	_spawns = _map.get("spawns", [])
	if _cells.is_empty():
		return false
	var minx := 99999; var maxx := -99999; var miny := 99999; var maxy := -99999
	for c in _cells:
		var cd: Dictionary = c
		minx = mini(minx, int(cd.get("x", 0))); maxx = maxi(maxx, int(cd.get("x", 0)))
		miny = mini(miny, int(cd.get("y", 0))); maxy = maxi(maxy, int(cd.get("y", 0)))
	_bbox_min = Vector2(minx, miny); _bbox_max = Vector2(maxx, maxy)
	_info = "%s：%d 格 · %d 出生点 · 滚轮缩放 / 拖动平移 / 点击单位移动" % [str(_map.get("name", "")), _cells.size(), _spawns.size()]
	return true

## 构建可通行格 + 障碍（类型 1/2 不可通行）
func _build_board() -> void:
	_board = GridBoardCls.new([], false)
	for c in _cells:
		var cd: Dictionary = c
		var cell := Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0)))
		_board.add_cell(cell)
		var tp := int(cd.get("type", 0))
		if tp == 1 or tp == 2:
			_board.set_obstacle(cell, true)

## 按出生点生成单位；数值查 data/story_chars.json
func _build_units() -> void:
	var chars := _load_chars()
	_units.clear()
	_units_by_cell.clear()
	var uid := 0
	for sp in _spawns:
		var sd: Dictionary = sp
		var team_s := str(sd.get("team", "blue"))
		var unit_s := str(sd.get("unit", ""))
		var role := _role_of(unit_s)
		var st: Dictionary = chars.get(role, {})
		if st.is_empty():
			push_warning("剧情单位缺少数值配置：%s（role=%s）" % [unit_s, role])
			continue
		var u := StoryUnit.new()
		u.uid = uid; uid += 1
		u.kind = role
		u.name = str(st.get("name", unit_s))
		u.team = 0 if team_s == "red" else 1
		u.element = str(st.get("element", ""))
		u.max_hp = int(st.get("hp", 1)); u.hp = u.max_hp
		u.max_energy = int(st.get("energy", 0)); u.energy = u.max_energy
		u.armor = int(st.get("armor", 0))
		u.speed = int(st.get("speed", 0))
		u.move_range = int(st.get("move", 3))
		u.passive = st.get("passive", {})
		u.skills = st.get("skills", [])
		u.cell = Vector2i(int(sd.get("x", 0)), int(sd.get("y", 0)))
		_units.append(u)
		_units_by_cell[_key(u.cell)] = u

func _load_chars() -> Dictionary:
	if not FileAccess.file_exists(CHARS_PATH):
		return {}
	var f := FileAccess.open(CHARS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		d.erase("_doc")
		return d
	return {}

## 角色类型归一：去掉末尾数字（战士1→战士，法师2→法师，龙3→龙，熊1→熊，昊→昊）
func _role_of(unit_s: String) -> String:
	var s := unit_s
	while s.length() > 0 and s[-1] >= "0" and s[-1] <= "9":
		s = s.substr(0, s.length() - 1)
	return s

# ---------------- 行动顺序（速度降序）----------------
func _compute_order() -> void:
	_order = _units.duplicate()
	_order.sort_custom(Callable(self, "_cmp_speed"))
	_turn = 0

func _cmp_speed(a: StoryUnit, b: StoryUnit) -> bool:
	if a.speed != b.speed:
		return a.speed > b.speed
	return a.uid < b.uid

func _current_unit() -> StoryUnit:
	if _order.is_empty() or _turn >= _order.size():
		return null
	return _order[_turn]

# ---------------- 选择 / 移动 ----------------
func _can_select(u: StoryUnit) -> bool:
	if u == null:
		return false
	if _free_mode:
		return true
	return u == _current_unit()

func _select(u: StoryUnit) -> void:
	_selected = u
	if u != null:
		_compute_reach(u)
	else:
		_reach = {}
	queue_redraw()

func _compute_reach(u: StoryUnit) -> void:
	_reach = {}
	if u == null:
		return
	# 暂时把其他单位占格设为障碍，避免穿人或停在人上
	for o in _units:
		if o != u:
			_board.set_obstacle(o.cell, true)
	var r := _board.reachable(u.cell, u.move_range)
	for o in _units:
		if o != u:
			_board.set_obstacle(o.cell, false)
	_reach = r

func _move_selected_to(cell: Vector2i) -> void:
	if _selected == null or not _reach.has(_key(cell)):
		return
	_units_by_cell.erase(_key(_selected.cell))
	_selected.cell = cell
	_units_by_cell[_key(cell)] = _selected
	if _free_mode:
		# 自由模式：保留选中，可继续移动（沙盒）
		_compute_reach(_selected)
	else:
		# 回合制：行动完毕，推进到下一位
		_selected = null
		_reach = {}
		_advance_turn()
	queue_redraw()

func _advance_turn() -> void:
	if _order.is_empty():
		return
	_turn = (_turn + 1) % _order.size()
	_selected = null
	_reach = {}
	queue_redraw()

# ---------------- 输入 ----------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_press_moved = false
				_press_pos = mb.position
				_drag_last = mb.position
			else:
				_drag = false
				if not _press_moved:
					_on_click_board(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			var nz := clampf(_zoom * factor, 0.25, 4.0)
			_pan = mb.position - (mb.position - _pan) * (nz / _zoom)
			_zoom = nz
			queue_redraw()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 6.0:
			_press_moved = true
		_pan += mm.relative
		queue_redraw()

func _on_click_board(pos: Vector2) -> void:
	if _board == null:
		return
	var cell := _screen_to_cell(pos)
	if not _board.has_cell(cell):
		return
	var u := _unit_at(cell)
	if u != null:
		if _can_select(u):
			if _selected == u:
				_select(null)   # 再次点击自己 → 取消选择
			else:
				_select(u)
		else:
			_select(null)
		return
	# 点到空格
	if _selected != null and _reach.has(_key(cell)):
		_move_selected_to(cell)
	else:
		_select(null)

# ---------------- 坐标换算 ----------------
func _screen_to_cell(pos: Vector2) -> Vector2i:
	var v := (pos - _pan) / (GRID * _zoom)
	return Vector2i(int(floor(v.x)), int(floor(v.y)))

func _cell_top_left(cell: Vector2i) -> Vector2:
	return Vector2(cell.x, cell.y) * GRID * _zoom + _pan

func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)) * GRID * _zoom + _pan

func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func _unit_at(cell: Vector2i) -> StoryUnit:
	return _units_by_cell.get(_key(cell), null)

# ---------------- 视图 ----------------
func _fit_view() -> void:
	var vp := size
	var world := (_bbox_max - _bbox_min + Vector2.ONE) * GRID
	if world.x <= 0 or world.y <= 0:
		return
	_zoom = minf((vp.x - 260.0) / world.x, (vp.y - 160.0) / world.y)
	_zoom = clampf(_zoom, 0.25, 2.5)
	_center_view()

func _center_view() -> void:
	var center := (_bbox_min + _bbox_max + Vector2.ONE) * 0.5 * GRID
	_pan = size * 0.5 - center * _zoom

# ---------------- UI ----------------
func _build_ui() -> void:
	_back_btn = Button.new()
	_back_btn.text = "‹ 返回菜单"
	_back_btn.custom_minimum_size = Vector2(140, 40)
	_back_btn.add_theme_font_size_override("font_size", 16)
	_back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainUI.tscn"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.19, 0.92)
	sb.border_color = Color(0.45, 0.42, 0.30)
	sb.set_border_width_all(1); sb.set_corner_radius_all(8)
	var sbh := sb.duplicate(); sbh.bg_color = Color(0.20, 0.23, 0.36)
	_back_btn.add_theme_stylebox_override("normal", sb)
	_back_btn.add_theme_stylebox_override("hover", sbh)
	_back_btn.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	add_child(_back_btn)

	_free_btn = Button.new()
	_free_btn.text = "自由模式：关"
	_free_btn.custom_minimum_size = Vector2(150, 40)
	_free_btn.add_theme_font_size_override("font_size", 15)
	_free_btn.pressed.connect(_on_toggle_free)
	_free_btn.add_theme_stylebox_override("normal", sb)
	_free_btn.add_theme_stylebox_override("hover", sbh)
	_free_btn.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	add_child(_free_btn)

	_next_btn = Button.new()
	_next_btn.text = "下一位 ▶"
	_next_btn.custom_minimum_size = Vector2(150, 40)
	_next_btn.add_theme_font_size_override("font_size", 15)
	_next_btn.pressed.connect(_advance_turn)
	_next_btn.add_theme_stylebox_override("normal", sb)
	_next_btn.add_theme_stylebox_override("hover", sbh)
	_next_btn.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	add_child(_next_btn)

func _layout_buttons() -> void:
	if _back_btn == null:
		return
	_back_btn.position = Vector2(14, 14)
	_free_btn.position = Vector2(size.x - 320.0, 14)
	_next_btn.position = Vector2(size.x - 162.0, 14)

func _on_toggle_free() -> void:
	_free_mode = not _free_mode
	_free_btn.text = "自由模式：开" if _free_mode else "自由模式：关"
	_next_btn.disabled = _free_mode
	_selected = null
	_reach = {}
	queue_redraw()

func _on_resize() -> void:
	_layout_buttons()
	queue_redraw()

# ---------------- 绘制 ----------------
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if _cells.is_empty():
		var f := get_theme_default_font()
		if f != null:
			draw_string(f, Vector2(40, 80), _info, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.7, 0.6))
		return
	# 地形
	for c in _cells:
		var cd: Dictionary = c
		var cell := Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0)))
		var tp := int(cd.get("type", 0))
		var td: Dictionary = _types.get(tp, {"color": "#666666"})
		var col := _hex_color(str(td.get("color", "#666666")))
		var r := Rect2(_cell_top_left(cell), Vector2(GRID, GRID) * _zoom)
		draw_rect(r, col)
		draw_rect(r, Color(0.9, 0.9, 0.9, 0.10), false, 1.0)
	# 移动范围高亮
	if _selected != null:
		for k in _reach:
			var parts := str(k).split(",")
			var cc := Vector2i(int(parts[0]), int(parts[1]))
			draw_rect(Rect2(_cell_top_left(cc), Vector2(GRID, GRID) * _zoom), REACH_COL)
			draw_rect(Rect2(_cell_top_left(cc), Vector2(GRID, GRID) * _zoom), REACH_EDGE, false, 1.5)
	# 单位
	for u in _units:
		_draw_unit(u)
	# 顶部信息条
	_draw_top_bar()
	# 右侧行动顺序
	_draw_order_panel()
	# 选中单位详情
	_draw_selected_panel()
	# 图例
	_draw_legend()
	# 底部提示
	var fnt := get_theme_default_font()
	if fnt != null:
		draw_string(fnt, Vector2(size.x * 0.5 - 240.0, size.y - 12.0), _info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.64, 0.7))

func _draw_unit(u: StoryUnit) -> void:
	var fnt := get_theme_default_font()
	var c := _cell_center(u.cell)
	var rad := GRID * _zoom * 0.34
	var col: Color = TEAM_COL.get(u.team, Color.WHITE)
	# 当前行动者光环
	var cur := _current_unit()
	if not _free_mode and cur == u:
		draw_circle(c, rad + 8.0, Color(1.0, 0.92, 0.35, 0.30))
	# 棋子
	draw_circle(c, rad, col)
	draw_arc(c, rad, 0.0, TAU, 48, Color(0.08, 0.06, 0.04), 3.0, true)
	draw_circle(c + Vector2(-rad * 0.3, -rad * 0.32), rad * 0.22, Color(1, 1, 1, 0.35))
	# 选中环
	if _selected == u:
		draw_arc(c, rad + 4.0, 0.0, TAU, 40, Color(1.0, 0.95, 0.5, 0.98), 3.0, true)
	# 名字
	if fnt != null and u.name != "":
		var fs := clampi(int(rad * 0.8), 9, 20)
		var w := fnt.get_string_size(u.name, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(fnt, Vector2(c.x - w / 2.0, c.y + fs * 0.36), u.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1), -1.0)
	# 血条（小）
	var bw := rad * 1.7
	var bx := c.x - bw / 2.0
	var by := c.y - rad - 7.0
	draw_rect(Rect2(bx, by, bw, 4.0), Color(0.1, 0.1, 0.1, 0.8))
	var hpr := clampf(float(u.hp) / float(maxi(1, u.max_hp)), 0.0, 1.0)
	draw_rect(Rect2(bx, by, bw * hpr, 4.0), col)

func _draw_top_bar() -> void:
	var fnt := get_theme_default_font()
	var ib := Rect2(Vector2(170, 14), Vector2(size.x - 500.0, 40))
	draw_rect(ib, PANEL)
	draw_rect(ib, Color(0.941, 0.780, 0.369), false, 1.0)
	if fnt != null:
		var title := "白灵殿 · 骑士线"
		if _free_mode:
			title += "（自由模式）"
		else:
			var cur := _current_unit()
			if cur != null:
				title += "　行动：%s（速%d）" % [cur.name, cur.speed]
		draw_string(fnt, Vector2(184, 42), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.97, 0.9))

func _draw_order_panel() -> void:
	var fnt := get_theme_default_font()
	if fnt == null or _order.is_empty():
		return
	var pw := 200.0
	var ph := 30.0 + float(_order.size()) * 22.0
	var px := size.x - pw - 14.0
	var py := 64.0
	var rect := Rect2(px, py, pw, ph)
	draw_rect(rect, PANEL)
	draw_rect(rect, Color(0.941, 0.780, 0.369), false, 1.0)
	draw_string(fnt, Vector2(px + 12.0, py + 22.0), "行动顺序（速度↓）", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.97, 0.9))
	for i in range(_order.size()):
		var u: StoryUnit = _order[i]
		var y := py + 44.0 + float(i) * 22.0
		var mark := "▶ " if (not _free_mode and i == _turn) else "   "
		var col: Color = TEAM_COL.get(u.team, Color.WHITE)
		draw_string(fnt, Vector2(px + 12.0, y), "%s%d. %s 速%d" % [mark, i + 1, u.name, u.speed],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

func _draw_selected_panel() -> void:
	var fnt := get_theme_default_font()
	if fnt == null or _selected == null:
		return
	var u: StoryUnit = _selected
	var pw := 260.0
	var ph := 200.0
	var px := 14.0
	var py := size.y - ph - 14.0
	var rect := Rect2(px, py, pw, ph)
	draw_rect(rect, PANEL)
	draw_rect(rect, TEAM_COL.get(u.team, Color.WHITE), false, 1.0)
	var y := py + 22.0
	draw_string(fnt, Vector2(px + 12.0, y), "%s　〔%s〕" % [u.name, u.element], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.97, 0.9)); y += 22.0
	draw_string(fnt, Vector2(px + 12.0, y), "生命 %d/%d　能量 %d/%d" % [u.hp, u.max_hp, u.energy, u.max_energy],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.94)); y += 20.0
	draw_string(fnt, Vector2(px + 12.0, y), "护甲 %d　速度 %d　移动 %d 格" % [u.armor, u.speed, u.move_range],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.94)); y += 20.0
	var pn := str(u.passive.get("name", ""))
	if pn != "":
		draw_string(fnt, Vector2(px + 12.0, y), "被动·%s" % pn, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.85, 0.6)); y += 18.0
	for s in u.skills:
		var sd: Dictionary = s
		var sn := str(sd.get("name", ""))
		if sn == "" or sn == "（无）":
			continue
		draw_string(fnt, Vector2(px + 12.0, y), "· %s(%d)" % [sn, int(sd.get("cost", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.86, 0.92)); y += 16.0

func _draw_legend() -> void:
	var fnt := get_theme_default_font()
	if fnt == null or _types.is_empty():
		return
	var lh := 18.0 * float(_types.size()) + 20.0
	# 堆叠在“选中单位详情”面板（底部居中偏左）上方，避免重叠
	var sel_h := 200.0
	var lx := 14.0
	var ly_top := size.y - sel_h - 14.0 - lh - 8.0
	draw_rect(Rect2(lx, ly_top, 210, lh), PANEL)
	var i := 0
	for k in _types:
		var td: Dictionary = _types[k]
		var yy := ly_top + 22.0 + float(i) * 18.0
		draw_rect(Rect2(lx + 10.0, yy - 1.0, 12, 12), _hex_color(str(td.get("color", "#888"))))
		draw_string(fnt, Vector2(lx + 30.0, yy + 11.0), "%d %s" % [int(k), str(td.get("name", ""))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.94))
		i += 1

func _hex_color(h: String) -> Color:
	var s := h.trim_prefix("#")
	if s.length() != 6:
		return Color(0.4, 0.4, 0.4)
	return Color(s.substr(0, 2).hex_to_int() / 255.0,
		s.substr(2, 2).hex_to_int() / 255.0,
		s.substr(4, 2).hex_to_int() / 255.0)
