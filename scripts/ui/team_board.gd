extends Control
## 4V4 标准棋盘控件（自绘）：10 列 × 8 行（x0..9 / y1..8，y 向上）
## 主区 x1..8 国际象棋木色；两翼 x0/x9 出生列（蓝翼色）
## 数据驱动渲染：set_units(数组) / 高亮三类(可移动/位移落点/可选目标)
## 点击：把鼠标坐标换算成格子，发 cell_clicked(cell) 信号

signal cell_clicked(cell: Vector2i)
signal right_clicked(cell: Vector2i)   # 右键：带真实格（上层据此弹棋子信息或取消）

const X_MIN := 0
const X_MAX := 9
const Y_MIN := 1
const Y_MAX := 8
const COL_LIGHT := Color(0.93, 0.87, 0.74)
const COL_DARK := Color(0.55, 0.40, 0.28)
const COL_WING := Color(0.40, 0.56, 0.74)
const COL_EDGE := Color(0.15, 0.12, 0.10)
const COL_WING_EDGE := Color(0.16, 0.28, 0.44)
const COL_MOVE := Color(0.45, 0.85, 0.45)
const COL_LAND := Color(0.95, 0.80, 0.30)
const COL_TARGET := Color(0.98, 0.55, 0.30)
const COL_RED := Color(0.80, 0.27, 0.20)
const COL_BLUE := Color(0.26, 0.45, 0.80)
const COL_GOLD := Color(1.0, 0.9, 0.5)

var _cell := 70.0
var _last_size := Vector2.ZERO

## 渲染数据（由对局脚本填充）
var units: Array = []            # {cell,name,team,hp,max_hp,selected}
var move_cells: Array = []       # Vector2i 绿色可移动
var land_cells: Array = []       # Vector2i 黄色位移落点
var target_cells: Array = []     # Vector2i 橙色可选技能目标
var stars: Array = []             # [{cell: Vector2i, big: bool}] 得分制星星

func _process(_d: float) -> void:
	if size != _last_size:
		_last_size = size
		queue_redraw()

func _cell_size() -> float:
	return minf(size.x / float(X_MAX - X_MIN + 1), size.y / float(Y_MAX - Y_MIN + 1))

## 逻辑格 → 控件内像素矩形
func cell_rect(cell: Vector2i) -> Rect2:
	var cs := _cell_size()
	var px := (cell.x - X_MIN) * cs
	var py := (Y_MAX - cell.y) * cs
	return Rect2(px, py, cs, cs)

## 控件内像素点 → 逻辑格（越界返回 null 由调用方判定）
func cell_at(pos: Vector2) -> Vector2i:
	var cs := _cell_size()
	var gx := int(pos.x / cs) + X_MIN
	var gy := Y_MAX - int(pos.y / cs)
	return Vector2i(gx, gy)

func in_board(c: Vector2i) -> bool:
	return c.x >= X_MIN and c.x <= X_MAX and c.y >= Y_MIN and c.y <= Y_MAX

## 格子是否存在：主区 x1..8 全高；两翼 x0/x9 只有出生行 y3..6（与战斗层 _cell_exists 一致）
func cell_exists(c: Vector2i) -> bool:
	if not in_board(c):
		return false
	if c.x >= 1 and c.x <= 8:
		return true
	return c.y >= 3 and c.y <= 6

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(ev.position)
		if cell_exists(c):
			cell_clicked.emit(c)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		# 右键：把真实格发给上层（有棋子→弹信息，无棋子→取消选择）
		right_clicked.emit(cell_at(ev.position))

func _draw() -> void:
	var cs := _cell_size()
	# 全部格底（两翼只画出生行 y3..6，其余翼格不渲染——与战斗层 _cell_exists 一致）
	for x in range(X_MIN, X_MAX + 1):
		for y in range(Y_MIN, Y_MAX + 1):
			var c := Vector2i(x, y)
			if not cell_exists(c):
				continue
			var r := Rect2((x - X_MIN) * cs, (Y_MAX - y) * cs, cs, cs)
			var is_wing := (x == X_MIN or x == X_MAX)
			var base := COL_WING if is_wing else (COL_LIGHT if (x + y) % 2 == 0 else COL_DARK)
			var edge := COL_WING_EDGE if is_wing else COL_EDGE
			# 高亮底（叠加 tint）
			if c in move_cells:
				base = base.lerp(COL_MOVE, 0.5)
			elif c in land_cells:
				base = base.lerp(COL_LAND, 0.5)
			elif c in target_cells:
				base = base.lerp(COL_TARGET, 0.55)
			draw_rect(r, base)
			draw_rect(r, edge, false, maxf(1.0, cs * 0.03))
	# 星星（得分制）：小星金色菱形，大星更大+亮金+光晕
	for st in stars:
		var pos: Vector2i = st.get("cell", Vector2i(-1, -1))
		if pos.x < X_MIN or pos.x > X_MAX:
			continue
		var is_big := bool(st.get("big", false))
		var ctr := cell_rect(pos).get_center()
		var rad := cs * 0.20 if is_big else cs * 0.13
		var col := Color(1.0, 0.86, 0.25) if is_big else Color(1.0, 0.93, 0.55)
		if is_big:
			draw_circle(ctr, rad * 1.9, Color(1.0, 0.86, 0.25, 0.25))
		# 四角星（菱形叠十字高光）
		var pts := PackedVector2Array([ctr + Vector2(0, -rad), ctr + Vector2(rad * 0.5, 0),
			ctr + Vector2(0, rad), ctr + Vector2(-rad * 0.5, 0)])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(0.55, 0.4, 0.05) if is_big else Color(0.75, 0.6, 0.15), maxf(1.0, cs * 0.02), true)
	# 单位棋子
	var f := get_theme_default_font()
	for u in units:
		if f == null:
			continue
		var cc: Vector2i = u.get("cell", Vector2i(-1, -1))
		if cc.x < X_MIN or cc.x > X_MAX:
			continue
		var hp := float(u.get("hp", 0))
		var mx := float(u.get("max_hp", 1))
		if hp <= 0:
			continue
		var center := cell_rect(cc).get_center()
		var team := int(u.get("team", 0))
		var col := COL_RED if team == 0 else COL_BLUE
		var rad := cs * 0.36
		# 选中金环
		if bool(u.get("selected", false)):
			draw_circle(center, rad + cs * 0.07, COL_GOLD)
		draw_circle(center, rad, col)
		draw_arc(center, rad, 0.0, TAU, 48, Color(0.08, 0.06, 0.04), maxf(1.5, cs * 0.05), true)
		draw_circle(center + Vector2(-rad * 0.3, -rad * 0.32), rad * 0.22, Color(1, 1, 1, 0.35))
		# 名字（缩小到棋子内）
		var nm := str(u.get("name", ""))
		var fs := int(cs * 0.14)
		var max_fs := int(rad * 2.0 / maxf(2.0, float(nm.length()) * 0.9))
		fs = clampi(mini(fs, max_fs), 9, 20)
		var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(center.x - w / 2.0, center.y - rad * 0.25 + fs * 0.3), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
		# 血量小字（棋下沿）
		var hp_txt := "%.2f/%.2f" % [float(hp), float(mx)]
		var hfs := maxi(9, int(cs * 0.12))
		var hw := f.get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
		draw_string(f, Vector2(center.x - hw / 2.0, center.y + rad * 0.8), hp_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, Color(1, 1, 0.85, 0.95))
		# 状态图标（棋子上方一排小徽章，让玩家一眼看到流血/烧伤/破甲…）
		var sts: Array = u.get("statuses", [])
		if not sts.is_empty():
			var br := maxf(5.0, cs * 0.075)          # 徽章半径
			var gap := br * 0.5
			var n := sts.size()
			var total := float(n) * (br * 2.0) + float(maxi(0, n - 1)) * gap
			var sx := center.x - total / 2.0 + br
			var sy := center.y - rad - br * 1.15
			for st in sts:
				var d: Dictionary = st as Dictionary
				var sid := str(d.get("id", ""))
				var cn := str(d.get("cn", ""))
				var lv := int(d.get("lv", 0))
				var bcol := _status_color(sid)
				draw_circle(Vector2(sx, sy), br, bcol)
				draw_arc(Vector2(sx, sy), br, 0.0, TAU, 24, Color(0.05, 0.04, 0.03), maxf(1.0, cs * 0.012), true)
				# 徽章内文字：中文名首字（2字以上取前两字放不下，取首字）+ 层数
				var label := cn.substr(0, 1) if cn.length() > 0 else "?"
				if lv > 1:
					label += str(lv)
				var lfs := maxi(8, int(br * 1.05))
				var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
				draw_string(f, Vector2(sx - lw / 2.0, sy + lfs * 0.34), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(1, 1, 1))
				sx += br * 2.0 + gap

## 状态徽章配色（按状态 id）
func _status_color(sid: String) -> Color:
	match sid:
		"bleed":
			return Color(0.75, 0.10, 0.12)      # 流血 深红
		"burn":
			return Color(0.92, 0.45, 0.08)      # 烧伤 橙
		"wound":
			return Color(0.60, 0.20, 0.55)      # 创伤 紫
		"heavy_wound":
			return Color(0.45, 0.12, 0.40)      # 重伤 深紫
		"freeze":
			return Color(0.30, 0.65, 0.90)      # 冰冻 冰蓝
		"blind":
			return Color(0.35, 0.35, 0.40)      # 失明 灰
		"stun":
			return Color(0.95, 0.80, 0.20)
		"full_burn":
			return Color(1.00, 0.35, 0.10)      # 眩晕 黄
		"sword_field":
			return Color(0.85, 0.75, 0.45)      # 剑域 金
		"poison", "poison_layer":
			return Color(0.30, 0.60, 0.20)      # 毒 绿
		_:
			return Color(0.42, 0.44, 0.52)      # 其它 石灰
