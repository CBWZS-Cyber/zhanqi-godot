extends Control
## 战棋 1V1 可玩对局（人类=红方 vs AI=蓝方）
## 流程：选英雄 → 对局：点击己方棋子聚焦 → 点绿色移动格 / 点技能(需目标时再点敌人) → AI 自动应战

const CELL := 118.0
const _HD := preload("res://scripts/combat/hero_defs.gd")
const _BAT := preload("res://scripts/combat/battle.gd")
const COL_BG := Color(0.20, 0.18, 0.16)
const COL_DARK := Color(0.55, 0.40, 0.28)
const COL_LIGHT := Color(0.93, 0.87, 0.74)
const COL_WING := Color(0.40, 0.56, 0.74)
const COL_MOVE := Color(0.45, 0.85, 0.45)
const COL_CAST := Color(0.95, 0.80, 0.3)
const COL_RED := Color(0.78, 0.25, 0.18)
const COL_BLUE := Color(0.24, 0.42, 0.75)

var _phase := "select"   # select / play / over
var _battle: Battle = null
var _pick_lab: Label
var _red_id := "crystal_dragon"
var _blue_id := "xie_shen"
var _hero_ids: Array = []

var _focus: BattleUnit = null          # 人类当前聚焦的己方棋子
var _cast_slot := 0                    # 等待选目标的技能槽
var _msg := ""
var _human_team := 0

# UI 引用
var _title: Label
var _hint: Label
var _log: RichTextLabel
var _skill_row: HBoxContainer
var _skill_buttons: Array = []
var _skill_desc: Label
var _unit_info: Label
var _over: Label
var _board: GridContainer
var _cells: Array = []                 # 与 _board 子按钮对应 (列x 行 y) 11 个按钮索引
var _cell_coords: Array = []
var _cell_buttons: Array = []
var _end_turn_btn: Button
var _again_btn: Button

func _ready() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", _panel_style(COL_BG, 0))
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	root.add_child(pad)
	pad.add_child(_build_main())
	_hero_ids = []
	for k in _HD.ALL:
		_hero_ids.append(str(k))
	_select_screen()

func _panel_style(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.35, 0.32, 0.26)
	if radius > 0:
		sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	return sb

func _build_main() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	# 顶栏
	var top := HBoxContainer.new()
	var back := Button.new()
	back.text = "‹ 返回菜单"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainUI.tscn"))
	top.add_child(back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	top.add_child(_title)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "结束回合"
	_end_turn_btn.pressed.connect(_on_end_turn)
	top.add_child(_end_turn_btn)
	v.add_child(top)
	# 中栏：左棋盘 / 右面板
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mid)
	# 棋盘区（程序绘制放在独立 Container 中）
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(680, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	var board_holder := CenterContainer.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(board_holder)
	_build_board(board_holder)
	_hint = Label.new()
	_hint.text = ""
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_hint)
	# 右侧面板
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	mid.add_child(right)
	_unit_info = Label.new()
	_unit_info.text = ""
	_unit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_unit_info)
	var lab_skill := Label.new(); lab_skill.text = "技能"; right.add_child(lab_skill)
	_skill_row = HBoxContainer.new()
	right.add_child(_skill_row)
	_skill_desc = Label.new()
	_skill_desc.text = ""
	_skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_skill_desc)
	var log_panel := Panel.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.12, 0.14), 8))
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", 8)
	inner.add_theme_constant_override("margin_right", 8)
	inner.add_theme_constant_override("margin_top", 6)
	inner.add_theme_constant_override("margin_bottom", 6)
	log_panel.add_child(inner)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_log)
	right.add_child(log_panel)
	_over = Label.new()
	_over.text = ""
	_over.add_theme_font_size_override("font_size", 30)
	_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	right.add_child(_over)
	_again_btn = Button.new()
	_again_btn.text = "再来一局（重选英雄）"
	_again_btn.visible = false
	_again_btn.pressed.connect(_on_again)
	right.add_child(_again_btn)
	return v

func _build_board(holder: CenterContainer) -> void:
	_board = GridContainer.new()
	_board.columns = 5
	_board.add_theme_constant_override("h_separation", 6)
	_board.add_theme_constant_override("v_separation", 6)
	holder.add_child(_board)
	# 按视觉行 y=3..1，每行 x=0..4
	_cell_coords.clear()
	_cell_buttons.clear()
	for row in range(3):
		var y := 3 - row
		for x in range(5):
			_cell_coords.append(Vector2i(x, y))
			var b := Button.new()
			b.custom_minimum_size = Vector2(CELL, CELL)
			b.toggle_mode = false
			b.add_theme_font_size_override("font_size", 18)
			_cell_buttons.append(b)
			_board.add_child(b)
	_refresh_board_view()

func _cell_button_at(cell: Vector2i) -> Button:
	for i in range(_cell_coords.size()):
		if _cell_coords[i] == cell:
			return _cell_buttons[i]
	return null

func _select_screen() -> void:
	_phase = "select"
	_title.text = "选择英雄（你=红方 vs AI=蓝方）"
	_unit_info.text = ""
	_skill_desc.text = ""
	_over.text = ""
	_hint.text = ""
	_end_turn_btn.visible = false
	# 隐藏棋盘中点击作用；棋盘清空
	for b in _cell_buttons:
		b.text = ""
		b.visible = false
	# 选人面板（悬浮层）
	var ov := Panel.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_theme_stylebox_override("panel", _panel_style(Color(0.13, 0.13, 0.15, 0.96), 12))
	add_child(ov)
	ov.name = "SelectOverlay"
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(880, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.add_child(box)
	var ti := Label.new(); ti.text = "你控制红方 —— 请选择双方英雄"
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_font_size_override("font_size", 24)
	box.add_child(ti)
	var sel := HBoxContainer.new()
	box.add_child(sel)
	var _pick_column := func(title_txt: String, is_red: bool) -> VBoxContainer:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(420, 0)
		var lab := Label.new(); lab.text = title_txt
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lab)
		var grid := GridContainer.new()
		grid.columns = 2
		col.add_child(grid)
		for hid in _hero_ids:
			var def: Dictionary = _HD.ALL[hid]
			var nb := Button.new()
			nb.text = "%s〔%s〕" % [def.name, def.element]
			nb.custom_minimum_size = Vector2(200, 40)
			nb.pressed.connect(func():
				if is_red:
					_red_id = hid
				else:
					_blue_id = hid
				if is_instance_valid(_pick_lab):
					_pick_lab.text = "已选择红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name])
			grid.add_child(nb)
		return col
	sel.add_child(_pick_column.call("红方（你）", true))
	sel.add_child(_pick_column.call("蓝方（AI）", false))
	_pick_lab = Label.new()
	_pick_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_lab.text = "已选择红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	box.add_child(_pick_lab)
	var start := Button.new()
	start.text = "开 始"
	start.custom_minimum_size = Vector2(220, 50)
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(_on_start)
	box.add_child(start)
	_end_turn_btn.visible = false

func _refresh_pick_highlight() -> void:
	if is_instance_valid(_pick_lab):
		_pick_lab.text = "已选择红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]

func _on_start() -> void:
	var ov := get_node_or_null("SelectOverlay")
	if ov != null:
		ov.queue_free()
	_phase = "play"
	_battle = _BAT.new(_red_id, _blue_id)
	_battle.human_mode = true
	_battle.human_team = 0
	_focus = null
	_cast_slot = 0
	_title.text = "红方 %s（你）vs 蓝方 %s（AI）" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	_end_turn_btn.visible = true
	_step()

func _step() -> void:
	if _battle == null:
		return
	var st: Dictionary = _battle.run_step()
	_focus = null
	_cast_slot = 0
	if st.has("over"):
		_phase = "over"
		_over.text = "对局结束：%s" % str(st["over"])
		_end_turn_btn.visible = false
		_again_btn.visible = true
		_hint.text = "可再来一局或返回菜单"
	elif st.has("wait"):
		_hint.text = "轮到你了（红方 %s）：点己方棋子走位 / 点技能行动" % _battle.current().name
		_title.text = "第 %d 回合 · 你的回合" % _battle.round
	else:
		_hint.text = ""
	_refresh_board_view()
	_refresh_ui()

func _refresh_ui() -> void:
	if _battle == null:
		return
	_unit_info.text = ""
	# 双方信息
	for u in _battle.units:
		var line := "%s%s %s  HP %d/%d 能%d 盾%d 甲%d 速%d%s" % [
			"🟥 " if u.team == 0 else "🟦 ", u.name, "（你）" if u.team == 0 else "（AI）",
			u.hp, u.max_hp, u.energy, u.shield, u.armor, u.effective_speed(),
			u.to_status_summary()]
		if u == _focus:
			line += "  ← 已选中"
		_unit_info.text += line + "\n"
	# 技能按钮
	for nb in _skill_buttons:
		if nb != null and is_instance_valid(nb):
			nb.queue_free()
	_skill_buttons.clear()
	var me := _battle.current() if (_phase == "play" and _battle.waiting() and _battle.current() != null) else null
	if me == null:
		_skill_row.visible = false
		return
	_skill_row.visible = true
	for i in range(1, 6):
		var sk := me.get_skill(i)
		if sk == null:
			continue
		var nb := Button.new()
		var why := ""
		var en := !me.alive
		if me.energy < sk.energy_cost:
			why = "能量不足"
		elif sk.current_cd > 0:
			why = "冷却%d" % sk.current_cd
		elif me.has_flag("no_skill") or (i == 4 and me.has_flag("no_ult")) or me.has_flag("no_damage"):
			why = "禁用"
		elif _battle.is_dash(me, i) and _battle.human_moved():
			why = "已移动·禁位移"
		elif not _battle.self_skill(me, i) and _battle.targets_in_range(me, i).is_empty():
			why = "射程内无目标"
		nb.text = "%s(%d)%s" % [sk.display_name, sk.energy_cost, ("⚠" + why) if why != "" else ""]
		if why != "":
			nb.disabled = true
		else:
			nb.pressed.connect(func():
				_on_skill(i))
		_skill_buttons.append(nb)
		_skill_row.add_child(nb)
	_skill_desc.text = ""
	var slot_i := _cast_slot
	if slot_i >= 1:
		var s := me.get_skill(slot_i)
		if s != null:
			_skill_desc.text = s.desc

func _on_skill(i: int) -> void:
	if _battle == null or not _battle.waiting():
		return
	var me := _battle.current()
	if me == null:
		return
	if _battle.self_skill(me, i):
		var r: String = _battle.human_cast(i)
		if r.begins_with("!"):
			_hint.text = r
		else:
			_hint.text = "已行动，AI 应战中…"
		_step()
	else:
		var ts: Array = _battle.targets_in_range(me, i)
		if ts.size() == 1:
			var r2: String = _battle.human_cast(i, ts[0])
			if r2.begins_with("!"):
				_hint.text = r2
			else:
				_hint.text = "已行动…"
			_step()
		elif ts.is_empty():
			_hint.text = "射程内没有敌人"
		else:
			_cast_slot = i
			_hint.text = "请点击一个高亮敌人作为目标（右键取消）"
	_refresh_ui()

func _on_again() -> void:
	var ov := get_node_or_null("SelectOverlay")
	if ov != null:
		ov.queue_free()
	_again_btn.visible = false
	_battle = null
	_select_screen()

func _on_end_turn() -> void:
	if _battle != null and _battle.waiting():
		_battle.human_done()
		_hint.text = "AI 应战中…"
		_step()

## 棋盘点击
func _unhandled_input(ev: InputEvent) -> void:
	if _phase != "play" or _battle == null:
		return
	if not (_battle.waiting()):
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var me := _battle.current()
		if me == null:
			return
		# 找到被点击格
		for i in range(_cell_buttons.size()):
			var cb: Button = _cell_buttons[i]
			if cb.get_global_rect().has_point(ev.global_position):
				var cell: Vector2i = _cell_coords[i]
				_handle_cell(cell)
				break
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_focus = null
		_cast_slot = 0
		_hint.text = "已取消选择"
		_refresh_board_view()

func _handle_cell(cell: Vector2i) -> void:
	var me := _battle.current()
	if _cast_slot >= 1:
		# 选目标阶段：点击敌人 → 施放
		var t := _unit_at(cell)
		if t != null and t.team != me.team and t in _battle.targets_in_range(me, _cast_slot):
			var r: String = _battle.human_cast(_cast_slot, t)
			if r.begins_with("!"):
				_hint.text = r
			_step()
		else:
			_cast_slot = 0
			_hint.text = "目标无效，已取消技能选择"
		return
	# 聚焦己方棋 / 点可移动格 / 点敌人提示
	var unit := _unit_at(cell)
	if unit != null and unit.team == me.team and unit.alive:
		_focus = unit
		_hint.text = "已选中 %s：点绿色格移动，或用右侧技能" % unit.name
	elif _focus != null and cell in _battle.move_cells_of(_focus):
		var r2: String = _battle.human_move(cell)
		if r2.begins_with("!"):
			_hint.text = r2
		else:
			_hint.text = "已移动（位移技本回合禁用）。可点技能或结束回合"
	elif unit != null and unit.team != me.team:
		_hint.text = "敌方 %s（HP %d/%d）" % [unit.name, unit.hp, unit.max_hp]
	else:
		_hint.text = "（空格）点自己的棋子开始"
	_refresh_board_view()

func _unit_at(cell: Vector2i) -> BattleUnit:
	for u in _battle.units:
		if u.cell == cell:
			return u
	return null

func _refresh_board_view() -> void:
	if _board == null:
		return
	for i in range(_cell_buttons.size()):
		var cell: Vector2i = _cell_coords[i]
		var cb: Button = _cell_buttons[i]
		var u := _unit_at(cell) if _battle != null else null
		var st: StyleBoxFlat = cb.get_theme_stylebox("normal")
		if st == null:
			st = _panel_style(Color(1, 1, 1), 6)
			cb.add_theme_stylebox_override("normal", st)
		if cell.x == 0 or cell.x == 4:
			st.bg_color = COL_WING
		else:
			st.bg_color = COL_LIGHT if (cell.x + cell.y) % 2 == 0 else COL_DARK
		# 状态色
		if _phase == "play" and _battle != null and _battle.waiting():
			var me := _battle.current()
			if me != null:
				if _focus != null and cell in _battle.move_cells_of(_focus):
					st.bg_color = COL_MOVE
				if _cast_slot >= 1:
					var t2 := _unit_at(cell)
					if t2 != null and t2.team != me.team and t2 in _battle.targets_in_range(me, _cast_slot):
						st.bg_color = COL_CAST
		if u != null:
			var mark := "红" if u.team == 0 else "蓝"
			var col := COL_RED if u.team == 0 else COL_BLUE
			cb.text = "%s · %s\n%d/%d" % [mark, u.name, u.hp, u.max_hp]
			if (u.team == 0 and cell.x == 0) or (u.team == 1 and cell.x == 4):
				st.bg_color = col
			else:
				st.bg_color = st.bg_color.lerp(col, 0.82)
			cb.add_theme_color_override("font_color", Color(1, 1, 1))
			cb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
			cb.add_theme_constant_override("shadow_offset_x", 1)
			cb.add_theme_constant_override("shadow_offset_y", 1)
		else:
			cb.text = ""
		if _phase == "select":
			cb.visible = false
		else:
			cb.visible = true
	_refresh_log()

func _refresh_log() -> void:
	if _battle == null:
		return
	var lines := _battle.log
	var head := maxi(0, lines.size() - 120)
	var out := ""
	for i in range(head, lines.size()):
		var s: String = lines[i]
		if s.begins_with("——"):
			out += "[color=#d8c9a0]%s[/color]\n" % s
		elif s.begins_with("=="):
			out += "[color=#ffd95a]%s[/color]\n" % s
		else:
			out += s + "\n"
	_log.text = out
	if _battle.log.size() > 0:
		_log.scroll_to_line(_log.get_line_count())
