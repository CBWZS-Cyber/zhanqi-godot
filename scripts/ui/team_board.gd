extends Control
## 4V4 标准棋盘控件（自绘）：10 列 × 8 行（x0..9 / y1..8，y 向上）
## 主区 x1..8 国际象棋木色；两翼 x0/x9 出生列（蓝翼色）
## 数据驱动渲染：set_units(数组) / 高亮三类(可移动/位移落点/可选目标)
## 点击：把鼠标坐标换算成格子，发 cell_clicked(cell) 信号

signal cell_clicked(cell: Vector2i)
signal right_clicked(cell: Vector2i)   # 右键：带真实格（上层据此弹棋子信息或取消）

# 长按识别（移动端）：按住 0.48s 视为右键（弹棋子详情）
const LONG_PRESS_MS := 480
var _lp_active := false
var _lp_fired := false
var _lp_ms := 0
var _lp_cell := Vector2i(-9, -9)

const UnitToken = preload("res://scripts/ui/unit_token.gd")   # 棋子 Node（有建模显角色/无建模兜底圆），1V1/4V4 共用

const X_MIN := 0
const X_MAX := 9
const Y_MIN := 1
const Y_MAX := 8
const COL_LIGHT := UiDesign.BOARD_LIGHT
const COL_DARK := UiDesign.BOARD_DARK
const COL_WING := UiDesign.SPAWN

## 地形底色（2026-09-10）：格子按 board 的地形层上色（无地形则用棋盘原色）。
## 2026-09-30 收敛：原先本文件自存一份副本（值与 Terrain.COLORS 逐项一致），
## 现直接转发到 Terrain.COLORS —— 以后改地形配色只需动 terrain.gd 一处。
const TERRAIN_COL := Terrain.COLORS
var board: GridBoard = null     # 地形数据源（由上层注入；null = 无地形）

## 地形悬浮提示用（可选）
func terrain_of(c: Vector2i) -> int:
	return board.terrain_at(c) if board != null else 0
const COL_EDGE := UiDesign.BOARD_FRAME
const COL_WING_EDGE := UiDesign.SPAWN_EDGE
const COL_MOVE := UiDesign.CELL_HL_MOVE
const COL_LAND := UiDesign.CELL_HL_CAST
const COL_TARGET := Color(0.98, 0.55, 0.30)
const COL_RED := UiDesign.ALLY
const COL_BLUE := Color(0.26, 0.45, 0.80)
const COL_GOLD := Color(1.0, 0.9, 0.5)

var _cell := 70.0
var _last_size := Vector2.ZERO

## 渲染数据（由对局脚本填充）
var units: Array = []            # {cell,name,team,hp,max_hp,selected}
var unit_objs: Array = []        # BattleUnit 数组（建模棋子用，由 set_battle_units 灌入）
var _tokens := {}                # cell_key("x,y") -> unit_token
var _focus_ref = null            # 上层聚焦单位（选中金环）
var _cur_ref = null              # 当前行动单位
var move_cells: Array = []       # Vector2i 绿色可移动
var land_cells: Array = []       # Vector2i 黄色位移落点
var target_cells: Array = []     # Vector2i 橙色可选技能目标
var stars: Array = []             # [{cell: Vector2i, big: bool}] 得分制星星

func _process(_d: float) -> void:
	if size != _last_size:
		_last_size = size
		_sync_tokens()
		queue_redraw()
	# 长按 → 右键（弹棋子详情）
	if _lp_active and not _lp_fired and Time.get_ticks_msec() - _lp_ms >= LONG_PRESS_MS:
		_lp_fired = true
		_lp_active = false
		right_clicked.emit(_lp_cell)

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
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var c := cell_at(ev.position)
			if cell_exists(c):
				cell_clicked.emit(c)
				# 同时启动长按计时（移动端长按 = 右键详情）
				_lp_active = true
				_lp_fired = false
				_lp_ms = Time.get_ticks_msec()
				_lp_cell = c
		else:
			_lp_active = false
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
			# 地形：按地形层上色（叠底，保留一点棋盘明暗差异以便辨格）
			var tid: int = terrain_of(c)
			if tid > 0 and TERRAIN_COL.has(tid):
				var tc: Color = TERRAIN_COL[tid]
				base = tc if (x + y) % 2 == 0 else tc.darkened(0.12)
				edge = tc.darkened(0.45)
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
	# 单位棋子由 Node 层渲染（_sync_tokens → unit_token），此处不再自绘

## 状态徽章配色（2026-09-30 收敛：统一走 SkillEffects.status_color，全工程只此一份）
func _status_color(sid: String) -> Color:
	return SkillEffects.status_color(sid)

# ================= 棋子 Node 层（建模/圆 token） =================
## 上层每步刷新调用：喂全部存活 BattleUnit + 聚焦/当前行动单位
func set_battle_units(arr: Array, focus_u = null, cur_u = null) -> void:
	unit_objs = []
	for u in arr:
		var bu = u
		if bu != null and bu.alive:
			unit_objs.append(bu)
	_focus_ref = focus_u
	_cur_ref = cur_u
	_sync_tokens()

func _ck(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

## 同步 token：按单位实例增删/更新。
## 同格多单位（虞美人 non_solid 可叠格）→ 各自保留，缩小错开显示，不再互相掩盖。
func _sync_tokens() -> void:
	if _tokens.is_empty() and unit_objs.is_empty():
		return
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
	# 同格分组 → 每格按序号偏移，叠格都可见
	var by_cell := {}
	for u in unit_objs:
		var ck := _ck(u.cell)
		if not by_cell.has(ck):
			by_cell[ck] = []
		by_cell[ck].append(u)
	for ck in by_cell:
		var arr: Array = by_cell[ck]
		var rect := cell_rect(arr[0].cell)
		# 叠格显示优先级：solid 单位 > 母体 > 子体；中央者正常显示，其余虞美人系退右上角花
		var central = arr[0]
		for u in arr:
			if not u.non_solid:
				central = u
				break
		if central.non_solid:
			for u in arr:
				if u.def_id == "yu_mei_ren" and not u.has_flag("子体"):
					central = u
					break
		for u in arr:
			var tok = _tokens.get(str(u.get_instance_id()))
			if tok == null:
				tok = UnitToken.new()
				tok.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透给棋盘
				add_child(tok)
				_tokens[str(u.get_instance_id())] = tok
			var is_center: bool = (u == central)
			if u.def_id == "yu_mei_ren":
				if u.has_flag("子体"):
					tok.flower = "white"
				else:
					tok.flower = "" if is_center else "red"
				tok.corner = not is_center
			else:
				tok.flower = ""
				tok.corner = false
			tok.position = rect.position
			tok.size = rect.size
			tok.setup(u, u == _focus_ref or u == _cur_ref)
