extends Control
## 战棋 1V1 可玩对局（人类=红方 vs AI=蓝方）
## 流程：选英雄 → 对局：点击己方棋子聚焦 → 点绿色移动格 / 点技能(需目标时再点敌人) → AI 自动应战

const CELL := 118.0
const CELL_SEP := 6.0
const _HD := preload("res://scripts/combat/hero_defs.gd")
const _BAT := preload("res://scripts/combat/battle.gd")
const COL_BG := Color(0.20, 0.18, 0.16)
const COL_DARK := Color(0.55, 0.40, 0.28)
const COL_LIGHT := Color(0.93, 0.87, 0.74)
const COL_WING := Color(0.40, 0.56, 0.74)
const COL_BORDER := Color(0.15, 0.12, 0.10)
const COL_WING_EDGE := Color(0.16, 0.28, 0.44)
const COL_TEXT := Color(0.18, 0.13, 0.09)
const COL_PANEL := Color(0.10, 0.12, 0.19, 0.94)
const COL_GOLD := Color(0.941, 0.780, 0.369)
const COL_MOVE := Color(0.45, 0.85, 0.45)
const COL_CAST := Color(0.95, 0.80, 0.3)
const COL_RED := Color(0.78, 0.25, 0.18)
const COL_BLUE := Color(0.24, 0.42, 0.75)

var _phase := "select"   # select / play / over
var _battle: Battle = null
var _pick_lab: Label
var _red_pick_btns := {}
var _blue_pick_btns := {}
var _blue_picked := false   # 玩家是否手动为 AI 选过英雄
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
var _skill_row: GridContainer
var _skill_buttons: Array = []
var _skill_desc: Label
var _action_lab: Label
var _hero_lab: Label
var _hp_bar: HBoxContainer
var _en_bar: HBoxContainer
var _sub_lab: Label
var _foe_lab: Label
var _over: Label
var _board: GridContainer
var _wrap: Control
var _unit_layer: Control
var _tokens := {}
var _cells: Array = []                 # 与 _board 子按钮对应 (列x 行 y) 11 个按钮索引
var _cell_coords: Array = []
var _cell_buttons: Array = []
var _end_turn_btn: Button
var _again_btn: Button
var _last_cell := -1.0

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
		if str(k) == "demo_hero":
			continue   # 演示占位英雄不进选人池
		_hero_ids.append(str(k))
	get_viewport().size_changed.connect(_apply_board_size)
	_apply_board_size()
	_last_cell = _board_cell_size()
	_select_screen()

func _style_btn(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.10, 0.12, 0.19, 0.9)
	n.border_color = Color(0.45, 0.42, 0.30)
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	var h := n.duplicate(); h.bg_color = Color(0.20, 0.23, 0.36)
	var pr := n.duplicate(); pr.bg_color = Color(0.08, 0.09, 0.15)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))

func _make_bar(tag: String, col: Color, value: int, max_value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.custom_minimum_size = Vector2(42, 0)
	tag_l.add_theme_font_size_override("font_size", 15)
	tag_l.add_theme_color_override("font_color", Color(0.84, 0.87, 0.92))
	row.add_child(tag_l)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = max_value if max_value > 0 else 1
	bar.value = clampi(value, 0, bar.max_value)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 26)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	var bgst := StyleBoxFlat.new()
	bgst.bg_color = Color(0.04, 0.05, 0.09, 0.9)
	bgst.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bgst)
	var num := Label.new()
	num.text = "%d / %d" % [value, max_value]
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_color_override("font_color", Color(1, 1, 1))
	num.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	bar.add_child(num)
	row.add_child(bar)
	return row

func _update_bar(bar: HBoxContainer, value: int, max_value: int, num_text: String) -> void:
	for c in bar.get_children():
		if c is ProgressBar:
			var pb := c as ProgressBar
			pb.max_value = max_value if max_value > 0 else 1
			pb.value = clampi(value, 0, pb.max_value)
			for cc in pb.get_children():
				if cc is Label:
					(cc as Label).text = num_text

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
	_style_btn(back)
	top.add_child(back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	top.add_child(_title)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "结束回合"
	_end_turn_btn.pressed.connect(_on_end_turn)
	_style_btn(_end_turn_btn)
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
	# 右侧面板（照 4V4 battle_hud 结构：行动指示/英雄名/血条能量条/技能/日志）
	var right_card := Panel.new()
	var rcs := StyleBoxFlat.new()
	rcs.bg_color = COL_PANEL
	rcs.set_corner_radius_all(16)
	right_card.add_theme_stylebox_override("panel", rcs)
	right_card.custom_minimum_size = Vector2(320, 0)
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right_card)
	var rmargin := MarginContainer.new()
	rmargin.set_anchors_preset(Control.PRESET_FULL_RECT)
	rmargin.add_theme_constant_override("margin_left", 12)
	rmargin.add_theme_constant_override("margin_right", 12)
	rmargin.add_theme_constant_override("margin_top", 10)
	rmargin.add_theme_constant_override("margin_bottom", 10)
	right_card.add_child(rmargin)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	rmargin.add_child(right)

	_action_lab = Label.new()
	_action_lab.add_theme_font_size_override("font_size", 15)
	_action_lab.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(_action_lab)

	_hero_lab = Label.new()
	_hero_lab.add_theme_font_size_override("font_size", 26)
	_hero_lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	right.add_child(_hero_lab)

	_hp_bar = _make_bar("生命", COL_RED, 1, 1)
	right.add_child(_hp_bar)
	_en_bar = _make_bar("能量", COL_BLUE, 1, 1)
	right.add_child(_en_bar)

	_sub_lab = Label.new()
	_sub_lab.add_theme_font_size_override("font_size", 13)
	_sub_lab.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	right.add_child(_sub_lab)

	_foe_lab = Label.new()
	_foe_lab.add_theme_font_size_override("font_size", 13)
	_foe_lab.add_theme_color_override("font_color", Color(0.62, 0.67, 0.75))
	right.add_child(_foe_lab)

	var lab_skill := Label.new()
	lab_skill.text = "技能"
	lab_skill.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(lab_skill)
	_skill_row = GridContainer.new()
	_skill_row.columns = 2
	_skill_row.add_theme_constant_override("h_separation", 8)
	_skill_row.add_theme_constant_override("v_separation", 8)
	right.add_child(_skill_row)
	_skill_desc = Label.new()
	_skill_desc.text = ""
	_skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_desc.add_theme_color_override("font_color", Color(0.72, 0.77, 0.85))
	right.add_child(_skill_desc)

	var log_title := Label.new()
	log_title.text = "战斗日志"
	log_title.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(log_title)
	var log_panel := Panel.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lps := StyleBoxFlat.new()
	lps.bg_color = Color(0.06, 0.08, 0.14, 0.85)
	lps.set_corner_radius_all(10)
	log_panel.add_theme_stylebox_override("panel", lps)
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
	_over.add_theme_font_size_override("font_size", 26)
	_over.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	right.add_child(_over)
	_again_btn = Button.new()
	_again_btn.text = "再来一局（重选英雄）"
	_again_btn.visible = false
	_again_btn.pressed.connect(_on_again)
	_style_btn(_again_btn)
	right.add_child(_again_btn)
	return v


func _board_cell_size() -> float:
	var vp := get_viewport_rect().size
	if vp.y <= 0 or vp.x <= 0:
		return CELL
	var side := vp.x * (340.0 / 1280.0)
	var avail_h := vp.y - 150.0
	var avail_w := vp.x - side - 60.0
	return clampf(minf(avail_h / 3.0, avail_w / 5.0), 100.0, 250.0)

func _apply_board_size() -> void:
	if _board == null:
		return
	var cs := _board_cell_size()
	for i in range(_cell_buttons.size()):
		var b: Button = _cell_buttons[i]
		b.custom_minimum_size = Vector2(cs, cs)
		b.add_theme_font_size_override("font_size", maxi(14, int(cs * 0.17)))
	if _wrap != null:
		var w := cs * 5.0 + CELL_SEP * 4.0
		var h := cs * 3.0 + CELL_SEP * 2.0
		_wrap.custom_minimum_size = Vector2(w, h)
		_unit_layer.size = Vector2(w, h)
	for k in _tokens:
		var tk = _tokens[k]
		if is_instance_valid(tk):
			tk.custom_minimum_size = Vector2(cs, cs)

func _build_board(holder: CenterContainer) -> void:
	_wrap = Control.new()
	holder.add_child(_wrap)
	_board = GridContainer.new()
	_board.columns = 5
	_board.add_theme_constant_override("h_separation", int(CELL_SEP))
	_board.add_theme_constant_override("v_separation", int(CELL_SEP))
	_board.position = Vector2.ZERO
	_wrap.add_child(_board)
	_unit_layer = Control.new()
	_unit_layer.position = Vector2.ZERO
	_unit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.add_child(_unit_layer)
	# 按视觉行 y=3..1，每行 x=0..4；两侧角格不存在（出生格每边仅 1 个：y=2）
	_cell_coords.clear()
	_cell_buttons.clear()
	for row in range(3):
		var y := 3 - row
		for x in range(5):
			if (x == 0 or x == 4) and y != 2:
				var ph := Control.new()
				ph.custom_minimum_size = Vector2(CELL, CELL)
				_board.add_child(ph)   # 空占位，保持网格对齐
				continue
			var ccell := Vector2i(x, y)
			_cell_coords.append(ccell)
			var b := Button.new()
			b.custom_minimum_size = Vector2(CELL, CELL)
			b.toggle_mode = false
			b.add_theme_font_size_override("font_size", 18)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func(): _on_cell_clicked(ccell))
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
	_title.text = "战棋 · 1V1"
	_skill_desc.text = ""
	_over.text = ""
	_hint.text = ""
	_end_turn_btn.visible = false
	for b2 in _cell_buttons:
		b2.visible = false
	# 全屏选人层
	var ov := Panel.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.10, 0.12, 0.19, 0.97)
	ov.add_theme_stylebox_override("panel", osb)
	add_child(ov)
	ov.name = "SelectOverlay"
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 50)
	m.add_theme_constant_override("margin_right", 50)
	m.add_theme_constant_override("margin_top", 26)
	m.add_theme_constant_override("margin_bottom", 26)
	ov.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var ti := Label.new()
	ti.text = "选择英雄"
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_font_size_override("font_size", 34)
	ti.add_theme_color_override("font_color", COL_GOLD)
	v.add_child(ti)
	var sub := Label.new()
	sub.text = "你控制红方 · 与 AI 对战（点击头像选择，再点一次可更换）"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.66, 0.71, 0.79))
	v.add_child(sub)
	# 双方选择卡片
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	_red_pick_btns = {}
	_blue_pick_btns = {}
	cols.add_child(_pick_card("红方（你）", COL_RED, true))
	cols.add_child(_pick_card("蓝方（AI）", COL_BLUE, false))
	# 已选提示 + 开始
	_pick_lab = Label.new()
	_pick_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_lab.text = "红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	_pick_lab.add_theme_font_size_override("font_size", 16)
	_pick_lab.add_theme_color_override("font_color", Color(0.85, 0.89, 0.95))
	v.add_child(_pick_lab)
	var start := Button.new()
	start.text = "开 始 对 战"
	start.custom_minimum_size = Vector2(300, 58)
	start.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.941, 0.780, 0.369)
	sb.set_corner_radius_all(10)
	var sh := sb.duplicate(); sh.bg_color = Color(1.0, 0.88, 0.55)
	var sp := sb.duplicate(); sp.bg_color = Color(0.78, 0.62, 0.22)
	start.add_theme_stylebox_override("normal", sb)
	start.add_theme_stylebox_override("hover", sh)
	start.add_theme_stylebox_override("pressed", sp)
	start.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	start.pressed.connect(_on_start)
	var sc := CenterContainer.new()
	sc.add_child(start)
	v.add_child(sc)

## 一侧选择卡片（标题 + 2 列英雄按钮）
func _pick_card(title_txt: String, col: Color, is_red: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = COL_PANEL
	cs.set_corner_radius_all(16)
	cs.border_color = col
	cs.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(430, 0)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 12)
	mg.add_theme_constant_override("margin_right", 12)
	mg.add_theme_constant_override("margin_top", 10)
	mg.add_theme_constant_override("margin_bottom", 12)
	card.add_child(mg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	mg.add_child(v)
	var lab := Label.new()
	lab.text = title_txt
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 19)
	lab.add_theme_color_override("font_color", col)
	v.add_child(lab)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for hid in _hero_ids:
		var def: Dictionary = _HD.ALL[hid]
		var nb := Button.new()
		nb.text = "%s\n〔%s〕" % [def.name, def.element]
		nb.custom_minimum_size = Vector2(196, 54)
		nb.add_theme_font_size_override("font_size", 15)
		_apply_pick_style(nb, false, col)
		if is_red:
			_red_pick_btns[hid] = nb
		else:
			_blue_pick_btns[hid] = nb
		nb.pressed.connect(func():
			if is_red:
				_red_id = hid
			else:
				_blue_id = hid
				_blue_picked = true
			_refresh_pick_highlight())
		grid.add_child(nb)
	return card

func _apply_pick_style(nb: Button, selected: bool, col: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.16, 0.19, 0.29) if not selected else col.lerp(Color(0.16, 0.19, 0.29), 0.35)
	n.border_color = COL_GOLD if selected else Color(0.40, 0.36, 0.26)
	n.set_border_width_all(2 if selected else 1)
	n.set_corner_radius_all(8)
	var h := n.duplicate(); h.bg_color = n.bg_color.lerp(Color(1, 1, 1), 0.08)
	nb.add_theme_stylebox_override("normal", n)
	nb.add_theme_stylebox_override("hover", h)
	nb.add_theme_stylebox_override("pressed", n)
	nb.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8) if selected else Color(0.92, 0.95, 0.99))

func _refresh_pick_highlight() -> void:
	for hid in _red_pick_btns:
		var nb: Button = _red_pick_btns[hid]
		if is_instance_valid(nb):
			_apply_pick_style(nb, hid == _red_id, COL_RED)
	for hid in _blue_pick_btns:
		var nb2: Button = _blue_pick_btns[hid]
		if is_instance_valid(nb2):
			_apply_pick_style(nb2, hid == _blue_id, COL_BLUE)
	if is_instance_valid(_pick_lab):
		_pick_lab.text = "红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]

func _on_start() -> void:
	if Global.offline_type != "hotseat" and not _blue_picked:
		var pool: Array = []
		for hid in _hero_ids:
			if hid != _red_id:
				pool.append(hid)
		_blue_id = pool[randi() % pool.size()]
	var ov := get_node_or_null("SelectOverlay")
	if ov != null:
		ov.queue_free()
	_phase = "play"
	_battle = _BAT.new(_red_id, _blue_id)
	_battle.human_mode = true
	_battle.human_team = 0
	if not _battle.log_appended.is_connected(_on_battle_log):
		_battle.log_appended.connect(_on_battle_log)
	if not _battle.state_changed.is_connected(_on_battle_state):
		_battle.state_changed.connect(_on_battle_state)
	if not _battle.battle_ended.is_connected(_on_battle_end):
		_battle.battle_ended.connect(_on_battle_end)
	if Global.offline_type == "hotseat":
		_battle.human_teams = [0, 1]
	_focus = null
	_cast_slot = 0
	_title.text = "红方 %s（你）vs 蓝方 %s（AI）" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	_end_turn_btn.visible = true
	_step()

func _on_battle_log(line: String) -> void:
	if line.begins_with("——"):
		_log.append_text("[color=#d8c9a0]%s[/color]\n" % line)
	elif line.begins_with("=="):
		_log.append_text("[color=#ffd95a]%s[/color]\n" % line)
	else:
		_log.append_text(line + "\n")

func _on_battle_state() -> void:
	_refresh_board_view()

func _on_battle_end(winner: String) -> void:
	_phase = "over"
	_over.text = "对局结束：%s" % winner
	_end_turn_btn.visible = false
	_again_btn.visible = true

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
	var shown: BattleUnit = null
	if _battle.current() != null:
		shown = _battle.current()
	else:
		shown = _battle.units[0]
	# 行动指示 + 英雄名
	_action_lab.text = "行动 · %s" % ("红方（你）" if shown.team == 0 else "蓝方（AI）")
	_hero_lab.text = shown.name
	# 血条 / 能量条
	_update_bar(_hp_bar, shown.hp, shown.max_hp, "%d / %d" % [shown.hp, shown.max_hp])
	if shown.max_energy < 0:
		_update_bar(_en_bar, shown.energy, maxi(shown.energy, 1), "%d / ∞" % shown.energy)
	else:
		_update_bar(_en_bar, shown.energy, shown.max_energy, "%d / %d" % [shown.energy, shown.max_energy])
	_sub_lab.text = "盾 %d · 甲 %d · 速 %d%s" % [shown.shield, shown.armor, shown.effective_speed(), shown.to_status_summary()]
	# 对手简况
	for x in _battle.units:
		if x != shown:
			_foe_lab.text = "对手：%s  HP %d/%d  盾%d 甲%d" % [x.name, x.hp, x.max_hp, x.shield, x.armor]
	# 技能按钮（battle_hud 款式，2 列）
	for nb in _skill_buttons:
		if nb != null and is_instance_valid(nb):
			nb.queue_free()
	_skill_buttons.clear()
	var me := _battle.current() if (_phase == "play" and _battle.waiting() and _battle.current() != null) else null
	if me == null:
		_skill_row.visible = false
		_refresh_log()
		return
	_skill_row.visible = true
	for i in range(1, 5):
		var sk := me.get_skill(i)
		if sk == null:
			continue
		var nb := Button.new()
		var why := ""
		if me.energy < sk.energy_cost:
			why = "能量不足"
		elif sk.current_cd > 0:
			why = "冷却%d" % sk.current_cd
		elif me.has_flag("no_skill") or (i == 4 and me.has_flag("no_ult")) or me.has_flag("no_damage"):
			why = "禁用"
		elif not _battle.self_skill(me, i) and _battle.targets_in_range(me, i).is_empty():
			why = "射程内无目标"
		nb.text = sk.display_name
		var tip := "[%s] 耗能 %d" % [sk.display_name, sk.energy_cost]
		if why != "":
			tip += "（不可用：%s）" % why
		tip += "\n" + sk.desc
		nb.mouse_entered.connect(func(): _skill_desc.text = tip)
		nb.mouse_exited.connect(func(): _skill_desc.text = "")
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 42)
		nb.add_theme_font_size_override("font_size", 15)
		nb.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
		nb.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
		var bn := StyleBoxFlat.new()
		bn.bg_color = Color(0.16, 0.19, 0.29)
		bn.border_color = Color(0.40, 0.36, 0.26)
		bn.set_border_width_all(1)
		bn.set_corner_radius_all(7)
		var bh := bn.duplicate(); bh.bg_color = Color(0.23, 0.27, 0.42)
		var bp := bn.duplicate(); bp.bg_color = Color(0.12, 0.15, 0.24)
		nb.add_theme_stylebox_override("normal", bn)
		nb.add_theme_stylebox_override("hover", bh)
		nb.add_theme_stylebox_override("pressed", bp)
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
	_refresh_log()

func _on_skill(i: int) -> void:
	if _battle == null or not _battle.waiting():
		return
	var me := _battle.current()
	if me == null:
		return
	if _battle.is_dash(me, i):
		_cast_slot = i
		if _battle.is_charge(me, i):
			_hint.text = "冲刺技能：点击一个敌人作为冲刺方向"
		else:
			_hint.text = "位移技能：点击一个黄色高亮格子作为落点（落地后自动选取目标）"
		_refresh_board_view()
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

func _on_cell_clicked(cell: Vector2i) -> void:
	if _phase != "play" or _battle == null or not _battle.waiting():
		return
	_handle_cell(cell)

func _handle_cell(cell: Vector2i) -> void:
	var me := _battle.current()
	if _cast_slot >= 1:
		var slot := _cast_slot
		if _battle.is_dash(me, slot):
			if _battle.is_charge(me, slot):
				# 冲刺：点敌人 → 朝其方向冲刺并结算
				var tt := _unit_at(cell)
				if tt != null and tt.team != me.team:
					var rc: String = _battle.human_cast(slot, tt)
					if rc.begins_with("!"):
						_hint.text = rc
					_step()
				else:
					_cast_slot = 0
					_hint.text = "已取消冲刺"
			else:
				# 跃迁：点落点格 → 落地并自动选目标
				var dd := _battle.dash_dist_of(me, slot)
				if cell in _battle.landable_cells(me, dd):
					var rj: String = _battle.human_cast(slot, null, cell)
					if rj.begins_with("!"):
						_hint.text = rj
					else:
						_step()
				else:
					_cast_slot = 0
					_hint.text = "落点无效（需空格且在位移距离内），已取消"
			return
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
			_hint.text = "已移动。可点技能或结束回合"
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
		# 底色：国际象棋木色 / 翼格蓝
		var base := COL_WING if (cell.x == 0 or cell.x == 4) else (COL_LIGHT if (cell.x + cell.y) % 2 == 0 else COL_DARK)
		var edge := COL_WING_EDGE if (cell.x == 0 or cell.x == 4) else COL_BORDER
		var border_col := edge
		var bw := 2.0
		# 高亮
		if _phase == "play" and _battle != null and _battle.waiting():
			var me := _battle.current()
			if me != null:
				if _focus != null and cell in _battle.move_cells_of(_focus):
					base = base.lerp(COL_MOVE, 0.45)
				if _cast_slot >= 1:
					if _battle.is_dash(me, _cast_slot):
						if _battle.is_charge(me, _cast_slot):
							var tc := _unit_at(cell)
							if tc != null and tc.team != me.team:
								base = base.lerp(COL_CAST, 0.5)
						else:
							if cell in _battle.landable_cells(me, _battle.dash_dist_of(me, _cast_slot)):
								base = base.lerp(COL_CAST, 0.5)
					else:
						var t2 := _unit_at(cell)
						if t2 != null and t2.team != me.team and t2 in _battle.targets_in_range(me, _cast_slot):
							base = base.lerp(COL_CAST, 0.5)
		# 占格：保持木色，用阵营边框标识
		if u != null:
			border_col = COL_RED if u.team == 0 else COL_BLUE
			bw = 3.0
		# 三态样式：按按钮缓存实例（只改属性不新建，避免刷新期 GC 压力）
		var st3 = cb.get_meta("styles") if cb.has_meta("styles") else null
		if st3 == null:
			var n0 := StyleBoxFlat.new()
			var h0 := StyleBoxFlat.new()
			var p0 := StyleBoxFlat.new()
			cb.add_theme_stylebox_override("normal", n0)
			cb.add_theme_stylebox_override("hover", h0)
			cb.add_theme_stylebox_override("pressed", p0)
			cb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			cb.set_meta("styles", [n0, h0, p0])
			st3 = [n0, h0, p0]
		var n: StyleBoxFlat = st3[0]
		n.bg_color = base
		n.border_color = border_col
		n.set_border_width_all(int(bw))
		st3[1].bg_color = base.lerp(Color(1, 1, 1), 0.10)
		st3[2].bg_color = base.lerp(Color(0, 0, 0), 0.12)
		cb.queue_redraw()
		cb.text = ""
		if _phase == "select":
			cb.visible = false
		else:
			cb.visible = true
	_refresh_tokens()
	_refresh_log()

func _refresh_tokens() -> void:
	if _battle == null or _unit_layer == null:
		return
	var cs := _board_cell_size()
	var seen := {}
	for u in _battle.units:
		if not u.alive:
			continue
		var cell_pos := u.cell
		if not (cell_pos.x in [0, 1, 2, 3, 4]) or cell_pos.y < 1 or cell_pos.y > 3:
			continue
		var tok = _tokens.get(u)
		if tok == null or not is_instance_valid(tok):
			tok = preload("res://scripts/ui/unit_token.gd").new()
			tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_unit_layer.add_child(tok)
			_tokens[u] = tok
		tok.setup(u.team, u.name, str(u.hp), u == _focus)
		tok.custom_minimum_size = Vector2(cs, cs)
		tok.size = Vector2(cs, cs)
		var grow := cs + CELL_SEP
		tok.position = Vector2(cell_pos.x * grow + 3.0, (3.0 - cell_pos.y) * grow + 3.0)
		tok.visible = _phase != "select"
		seen[u] = true
	for u in _tokens:
		var tk = _tokens[u]
		if is_instance_valid(tk) and not seen.has(u):
			tk.visible = false

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
