extends Control
## 战棋 1V1 可玩对局（人类=红方 vs AI=蓝方）
## 流程：选英雄 → 对局：点击己方棋子聚焦 → 点绿色移动格 / 点技能(需目标时再点敌人) → AI 自动应战

const CELL := 118.0
const CELL_SEP := 6.0
const _HD := preload("res://scripts/combat/hero_defs.gd")
const _BAT := preload("res://scripts/combat/battle.gd")
const _NP := preload("res://scripts/net/net_protocol.gd")
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
var _sfx_round: int = -1               # 音效：已提示过回合开始 alarm 的回合数
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
var _state_lab: RichTextLabel
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
var _settings: SettingsLayer = null
var _last_cell := -1.0
# 长按识别（移动端）：按住 0.48s = 右键详情
const _LONG_PRESS_MS := 480
var _lp_active := false
var _lp_fired := false
var _lp_ms := 0
var _lp_cell := Vector2i(-9, -9)

# ---------- 联机（Global.net_mode=true 时生效，阶段4）----------
var _net_my_picked := false    # 本方已选英雄
var _net_foe_picked := false   # 对方已选英雄（pick 指令到达）
var _net_starting := false     # 开局防重入

func _ready() -> void:
	_autonet_detect()   # 无头端到端测试钩子：godot --headless scenes/Duel.tscn ++ autonet=host|join（须在初始化前设置 Global）
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
		if not HeroDefs.is_pickable(str(k)):
			continue
		_hero_ids.append(str(k))
	_apply_board_size()
	_last_cell = _board_cell_size()
	if Global.net_mode:
		if not Net.cmd_received.is_connected(_on_net_cmd):
			Net.cmd_received.connect(_on_net_cmd)
		if not Net.opening_received.is_connected(_on_net_opening):
			Net.opening_received.connect(_on_net_opening)
		if not Net.peer_left.is_connected(_on_net_left):
			Net.peer_left.connect(_on_net_left)
	_select_screen()
	if _autonet_role != "":
		_autonet_run()

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

func _make_bar(tag: String, col: Color, value: int, max_value: int, tiled := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.custom_minimum_size = Vector2(42, 0)
	tag_l.add_theme_font_size_override("font_size", 15)
	tag_l.add_theme_color_override("font_color", Color(0.84, 0.87, 0.92))
	row.add_child(tag_l)
	var bar: Control
	if tiled:
		# 生命条改用 HpShieldBar：能在同一条里分段显示 hp + 护盾（2026-09-13）
		var hsb := HpShieldBar.new()
		hsb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hsb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hsb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hsb.custom_minimum_size = Vector2(0, 26)
		bar = hsb
	else:
		var pb := ProgressBar.new()
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.show_percentage = false
		pb.min_value = 0
		pb.max_value = max_value if max_value > 0 else 1
		pb.value = clampi(value, 0, pb.max_value)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.custom_minimum_size = Vector2(0, 26)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col
		fill.set_corner_radius_all(5)
		var bgst := StyleBoxFlat.new()
		bgst.bg_color = Color(0.04, 0.05, 0.09, 0.9)
		bgst.set_corner_radius_all(5)
		pb.add_theme_stylebox_override("fill", fill)
		pb.add_theme_stylebox_override("background", bgst)
		bar = pb
	var num := Label.new()
	num.text = "%.2f / %.2f" % [value, max_value]
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

func _update_bar(bar: HBoxContainer, value: float, max_value: float, num_text: String, tag_text := "", smooth := false, shield := 0.0) -> void:
	# 标签（"生命/能量/理智"）：HBox 第一个直接子 Label
	for c in bar.get_children():
		if c is Label:
			if tag_text != "":
				(c as Label).text = tag_text
			break
	for c in bar.get_children():
		if c is HpShieldBar:
			# 生命条：hp 与护盾分段画在同一条里（护盾不做动态特效应）
			(c as HpShieldBar).set_values(value, shield, max_value)
		elif c is ProgressBar:
			var pb := c as ProgressBar
			pb.max_value = max_value if max_value > 0 else 1
			# 2026-09-13 掉血特效：smooth=true 时走缓动（涨立即 / 跌平滑滑落）
			if smooth:
				DamageFx.ease_bar(pb, value)
			else:
				pb.value = clampf(value, 0.0, pb.max_value)
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
	back.text = "⚙ 设置"
	back.pressed.connect(_open_settings)
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

	_hp_bar = _make_bar("生命", COL_RED, 1, 1, true)
	right.add_child(_hp_bar)
	_en_bar = _make_bar("能量", COL_BLUE, 1, 1)
	right.add_child(_en_bar)

	_sub_lab = Label.new()
	_sub_lab.add_theme_font_size_override("font_size", 13)
	_sub_lab.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	right.add_child(_sub_lab)

	_state_lab = RichTextLabel.new()
	_state_lab.bbcode_enabled = true
	_state_lab.fit_content = true
	_state_lab.scroll_active = false
	_state_lab.add_theme_font_size_override("normal_font_size", 13)
	_state_lab.add_theme_color_override("default_color", Color(0.75, 0.80, 0.88))
	right.add_child(_state_lab)

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
	# 点击日志任意处 → 放大到全屏大字阅读（默认面板太小，2026-09-08 用户要求）
	log_panel.gui_input.connect(_on_log_panel_click)
	_log.gui_input.connect(_on_log_panel_click)   # 日志文本占满面板，父层收不到点击，直接挂文本上

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

func _process(_d: float) -> void:
	var cs := _board_cell_size()
	if absf(cs - _last_cell) > 0.5:
		_last_cell = cs
		_apply_board_size()
	# 长按 → 棋子详情（移动端）
	if _lp_active and not _lp_fired and Time.get_ticks_msec() - _lp_ms >= _LONG_PRESS_MS:
		_lp_fired = true
		_lp_active = false
		var hit: BattleUnit = _unit_at(_lp_cell)
		if hit != null and hit.alive and _battle != null and _phase == "play":
			add_child(UnitInfoPopup.make(hit))

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
	sub.text = "联机对战：点击自己一侧头像选择（双方选完自动开始）" if Global.net_mode else "你控制红方 · 与 AI 对战（点击头像选择，再点一次可更换）"
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
	cols.add_child(_pick_card("红方（主机）" if Global.net_mode else "红方（你）", COL_RED, true))
	cols.add_child(_pick_card("蓝方（加入者）" if Global.net_mode else "蓝方（AI）", COL_BLUE, false))
	# 已选提示 + 开始
	_pick_lab = Label.new()
	_pick_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick_lab.text = "红方：%s ｜ 蓝方：%s" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	_pick_lab.add_theme_font_size_override("font_size", 16)
	_pick_lab.add_theme_color_override("font_color", Color(0.85, 0.89, 0.95))
	v.add_child(_pick_lab)
	# PVE：进选人界面即让 AI 随机定好蓝方（界面从第一刻就显示蓝方真正会选的人，而非默认邪神）
	if not Global.net_mode and Global.offline_type != "hotseat":
		_ai_pick_blue()
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
	if Global.net_mode:
		start.visible = false   # 联机：双方选完自动开局
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
			if Global.net_mode:
				var my_side := 0 if Global.net_is_host else 1
				if (is_red and my_side != 0) or (not is_red and my_side != 1):
					_pick_lab.text = "联机中只能选择自己一侧（%s）" % ("红方" if my_side == 0 else "蓝方")
					return
				if is_red:
					_red_id = hid
				else:
					_blue_id = hid
				_net_my_picked = true
				_refresh_pick_highlight()
				Net.send_cmd(_NP.make_pick(my_side, hid))
				_net_try_start()
			else:
				if is_red:
					_red_id = hid
					# PVE：红方换卡若与蓝方 AI 撞车 → 蓝方重选（界面始终显示真实蓝方）
					if not Global.net_mode and Global.offline_type != "hotseat" and _blue_id == _red_id:
						_ai_pick_blue()
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
	if Global.net_mode:
		return   # 联机开局走 _net_start_battle（opening 驱动），不经此处
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
	if Global.offline_type == "hotseat":
		_battle.human_teams = [0, 1]
	else:
		var diff := str(Global.difficulty)
		if diff == "normal" or diff == "hard":
			_battle.ai_level = diff
			_battle.side_levels = {1: diff}
			if diff == "hard":
				_battle.ai_backend = str(Global.ai_backend)
	_focus = null
	_cast_slot = 0
	_title.text = "红方 %s（你）vs 蓝方 %s（AI）" % [_HD.ALL[_red_id].name, _HD.ALL[_blue_id].name]
	_end_turn_btn.visible = true
	_step()

# ---------- 联机核心（阶段4）----------
func _my_team() -> int:
	return 0 if Global.net_is_host else 1

func _can_input() -> bool:
	if _battle == null or _phase != "play" or not _battle.waiting():
		return false
	if Global.net_mode and _battle.current().team != _my_team():
		return false
	return true

## 本方操作 → 本地执行 + 成功才广播（失败仅本地提示，与单机一致）
func _op_move(cell: Vector2i) -> String:
	var idx := _battle.units.find(_battle.current())
	var r: String = _battle.human_move(cell)
	if r.begins_with("!"):
		Sfx.play("error")
	else:
		Sfx.play("footstep")
	if not r.begins_with("!") and Global.net_mode:
		Net.send_cmd(_NP.make_move(idx, cell))
	return r

func _op_cast(slot: int, enemy: BattleUnit = null, landing := Vector2i(-1, -1)) -> String:
	var idx := _battle.units.find(_battle.current())
	var me_u: BattleUnit = _battle.current()
	var old_cell: Vector2i = me_u.cell if me_u != null else Vector2i(-9, -9)
	var was_dash: bool = me_u != null and _battle.is_charge(me_u, slot)
	var r: String = _battle.human_cast(slot, enemy, landing)
	if r.begins_with("!"):
		Sfx.play("error")
	elif me_u != null:
		if me_u.cell != old_cell:
			Sfx.play("dash" if was_dash else "teleport")
		elif _battle.land_aoe(me_u, slot):
			Sfx.play("explosion")
		elif _battle.self_skill(me_u, slot):
			Sfx.play("powerup")
		else:
			Sfx.play("hit")
	if not r.begins_with("!") and Global.net_mode:
		Net.send_cmd(_NP.make_cast(idx, slot, enemy, _battle, landing))
	return r

func _op_done() -> void:
	var idx := _battle.units.find(_battle.current())
	_battle.human_done()
	if Global.net_mode:
		Net.send_cmd(_NP.make_done(idx))

## 选英雄交换：对方 pick 到达 / 本方 pick 已发 → 双方齐即开局
func _on_net_pick(side: int, hero_id: String) -> void:
	if hero_id == "" or (Global.net_mode and side == _my_team()):
		return   # 对方无权替我方选英雄
	if side == 0:
		_red_id = hero_id
	else:
		_blue_id = hero_id
	_net_foe_picked = true
	_refresh_pick_highlight()
	_net_try_start()

func _net_try_start() -> void:
	if _net_starting or not (_net_my_picked and _net_foe_picked):
		return
	if Global.net_is_host:
		_net_starting = true
		Net.send_opening({"seed": Global.net_seed, "red": _red_id, "blue": _blue_id})
		_net_start_battle()
	# joiner 等 host 的 opening 开局包

func _on_net_opening(pkg: Dictionary) -> void:
	if _net_starting:
		return
	_net_starting = true
	Global.net_seed = int(pkg.get("seed", 0))
	_red_id = str(pkg.get("red", _red_id))
	_blue_id = str(pkg.get("blue", _blue_id))
	_net_start_battle()

func _net_start_battle() -> void:
	var ov := get_node_or_null("SelectOverlay")
	if ov != null:
		ov.queue_free()
	_phase = "play"
	_battle = _BAT.new(_red_id, _blue_id)
	_battle.set_rng_seed(Global.net_seed)
	_battle.human_mode = true
	_battle.human_team = 0
	_battle.human_teams = [0, 1]   # 两侧都"人类"：run_step 对双方 wait，操作走指令流镜像
	_focus = null
	_cast_slot = 0
	var my_hero: String = _HD.ALL[_red_id].name if _my_team() == 0 else _HD.ALL[_blue_id].name
	var foe_hero: String = _HD.ALL[_blue_id].name if _my_team() == 0 else _HD.ALL[_red_id].name
	_title.text = "联机 1V1：%s（你·%s）vs %s（对方）" % [my_hero, "红方" if _my_team() == 0 else "蓝方", foe_hero]
	_end_turn_btn.visible = true
	_step()

## 远端指令 → 镜像重放（本地操作成功后的 UI 动作，重放侧做一样的动作）
func _on_net_cmd(cmd: Dictionary) -> void:
	if not Global.net_mode:
		return
	var op := str(cmd.get("op", ""))
	if op == "pick":
		_on_net_pick(int(cmd.get("side", -1)), str(cmd.get("hero", "")))
		return
	if _battle == null or _phase != "play":
		return
	# 发送方校验：对方只能驱动对方的单位（防误发/伪造）
	var actor_idx := int(cmd.get("actor", -1))
	if actor_idx >= 0 and actor_idx < _battle.units.size():
		if _battle.units[actor_idx].team == _my_team():
			return   # 静默丢弃：对方无权驱动我方单位
	var r: String = _NP.apply_cmd(_battle, cmd)
	if r.begins_with("!REPLAY_"):
		_phase = "over"
		_over.text = "对局中断：与对方状态不同步（%s）" % r
		return
	match op:
		"move":
			_refresh_board_view()
			_hint.text = "对方已移动"
		"cast":
			_step()
		"done":
			_step()

func _on_net_left() -> void:
	if Global.net_mode and _phase == "play":
		_phase = "over"
		_over.text = "对方断线，判你获胜！"
		_hint.text = "返回菜单可再来一局"

# ---------- 无头联机端到端测试钩子（正常启动模式，autoload 环境完整）----------
## 用法：
##   host: godot --headless --path . res://scenes/Duel.tscn ++ autonet=host
##   join: godot --headless --path . res://scenes/Duel.tscn ++ autonet=join
var _autonet_role := ""

func _autonet_detect() -> void:
	var ws_mode := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("autonet="):
			_autonet_role = a.trim_prefix("autonet=")
		elif a.begins_with("autonetws="):
			_autonet_role = a.trim_prefix("autonetws=")
			ws_mode = true   # WebSocket 传输（公网穿透模式本地验证）
	if _autonet_role != "host" and _autonet_role != "join":
		_autonet_role = ""
		return
	Global.net_mode = true
	Global.net_is_host = (_autonet_role == "host")
	Net.transport = "ws" if ws_mode else "enet"
	var err: int = ERR_UNAVAILABLE
	if Global.net_is_host:
		Global.net_seed = 424242
		err = Net.host_game(Global.net_port)
	else:
		err = Net.join_game("127.0.0.1", Global.net_port)
	print("AUTONET[%s%s]: net ready err=%d" % [_autonet_role, "/ws" if ws_mode else "", err])

func _autonet_run() -> void:
	# 等 peer 就绪（host 等对方连入；joiner 等连上）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		if Net.multiplayer_peer_active():
			break
	print("AUTONET[%s]: peer connected" % _autonet_role)
	# 选人（本方英雄固定：host=zhuilie 红 / join=xian_zun 蓝）
	if Global.net_is_host:
		_red_id = "zhuilie"
		_net_my_picked = true
		Net.send_cmd(_NP.make_pick(0, _red_id))
		_net_try_start()
		# joiner 的 pick 到达后 _net_try_start 自动开局
	else:
		# 等对方 pick
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 8000 and not _net_foe_picked:
			await get_tree().process_frame
		_blue_id = "xian_zun"
		_net_my_picked = true
		Net.send_cmd(_NP.make_pick(1, _blue_id))
		_net_try_start()
	# 等开局
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and _battle == null:
		await get_tree().process_frame
	if _battle == null:
		print("AUTONET[%s]: FAIL 开局超时" % _autonet_role)
		get_tree().quit(1)
		return
	print("AUTONET[%s]: 开局 OK red=%s blue=%s seed=%d" % [_autonet_role, _red_id, _blue_id, Global.net_seed])
	# 驱动本方操作：3 次行动（move+done），远端指令自动重放
	var acts := 0
	t0 = Time.get_ticks_msec()
	var my_t := _my_team()
	while acts < 3 and Time.get_ticks_msec() - t0 < 15000 and _battle != null and _battle.winner == "":
		await get_tree().process_frame
		if _battle.waiting() and _battle.current() != null and _battle.current().team == my_t:
			var me = _battle.current()
			var cells: Array = _battle.move_cells_of(me)
			if cells.size() > 0 and not _battle.human_moved():
				_op_move(cells[0])
			else:
				_op_done()
				_step()   # 与真实 UI（_on_end_turn）一致：done 后推进引擎
				acts += 1
	# 收尾：等 1s 让最后的指令包到达对端
	await get_tree().create_timer(1.0).timeout
	var log_len: int = _battle.log.size() if _battle != null else -1
	var r0 := str(_battle.units[0].cell) if _battle != null else "?"
	var r1 := str(_battle.units[1].cell) if _battle != null else "?"
	var rd := _battle.round if _battle != null else -1
	print("AUTONET-SUMMARY[%s] log=%d red@=%s blue@=%s round=%d" % [_autonet_role, log_len, r0, r1, rd])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

func _step() -> void:
	if _battle == null:
		return
	var st: Dictionary = _battle.run_step()
	_focus = null
	_cast_slot = 0
	if st.has("over"):
		_phase = "over"
		Sfx.play("victory")
		_over.text = "对局结束：%s" % str(st["over"])
		_end_turn_btn.visible = false
		_again_btn.visible = not Global.net_mode   # 联机 over 不提供"再来一局"（回菜单重开）
		_hint.text = "可再来一局或返回菜单"
	elif st.has("wait"):
		if _battle.round != _sfx_round:
			_sfx_round = _battle.round
			Sfx.play("alarm")
		var cur_u = _battle.current()
		if Global.net_mode and cur_u != null and cur_u.team != _my_team():
			_hint.text = "等待对方行动…"
			_title.text = "第 %d 回合 · 对方回合" % _battle.round
		else:
			_hint.text = "轮到你了（%s %s）：点己方棋子走位 / 点技能行动" % [("红方" if cur_u.team == 0 else "蓝方") if Global.net_mode else "红方", cur_u.name]
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
	var my_t := _my_team() if Global.net_mode else 0
	_action_lab.text = "行动 · %s" % ("你（%s）" % ("红方" if shown.team == my_t else "蓝方") if shown.team == my_t else ("对方（%s）" % ("红方" if shown.team == 0 else "蓝方")))
	_hero_lab.text = shown.name
	# 血条 / 能量条（理智系英雄：能量栏整体换成理智栏）
	_update_bar(_hp_bar, shown.hp, shown.max_hp, "%.2f / %.2f" % [shown.hp, shown.max_hp], "", true, shown.shield)
	if shown.has_sanity:
		_update_bar(_en_bar, clampf(shown.sanity, 0.0, shown.sanity_cap), shown.sanity_cap,
			"理智 %.2f / %.2f" % [shown.sanity, shown.sanity_cap], "理智")
	elif shown.max_energy < 0:
		_update_bar(_en_bar, shown.energy, maxf(shown.energy, 1.0), "%.2f / ∞" % shown.energy, "能量")
	else:
		_update_bar(_en_bar, shown.energy, shown.max_energy, "%.2f / %.2f" % [shown.energy, shown.max_energy], "能量")
	_sub_lab.text = "盾 %.2f · 甲 %.2f · 速 %d%s" % [shown.shield, shown.armor, shown.effective_speed(), shown.to_status_summary()]
	# 状态区：被动 / 理智 / 印记层数 / 流血灼烧等
	_state_lab.text = _state_bbcode(shown)
	# 对手简况
	for x in _battle.units:
		if x != shown:
			_foe_lab.text = "对手：%s  HP %.2f/%.2f  盾%.2f 甲%.2f" % [x.name, x.hp, x.max_hp, x.shield, x.armor]
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
		if me.is_skill_lost(sk.id):
			why = "被掠夺"
		elif sk.exhausted():
			why = "本局已用尽"
		elif me.energy < sk.energy_cost:
			why = "能量不足"
		else:
			var _cd: Dictionary = _battle.skill_data(sk.id)
			if int(_cd.get("crystal_cost", 0)) > me.counter("元晶"):
				why = "元晶不足（需 %d，现 %d）" % [int(_cd.get("crystal_cost", 0)), me.counter("元晶")]
			elif bool(_cd.get("need_shield", false)) and me.shield <= 0:
				why = "需要护盾（当前无盾）"
		if sk.current_cd > 0:
			why = "冷却%d" % sk.current_cd
		elif me.has_flag("no_skill") or (i == 4 and me.has_flag("no_ult")) or me.has_flag("no_damage"):
			why = "禁用"
		elif _battle.is_spread(me, i):
			# 蔓延不需要敌方目标：按周围可蔓延格判定
			if me.spread_used >= 2:
				why = "本回合蔓延次数已用完"
			elif _battle.spread_cells_of(me).is_empty():
				why = "无可蔓延格"
		elif not _battle.self_skill(me, i) and _battle.targets_in_range(me, i).is_empty():
			var _nd := 99
			for _f in _battle.alive_enemies_of(me):
				_nd = mini(_nd, _battle.dist(me, _f))
			why = "射程内无目标（最近敌 %s 格 / 射程 %d）" % [("?" if _nd >= 99 else str(_nd)), _battle.skill_range(me, i)]
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
	if not _can_input():
		return
	var me := _battle.current()
	if me == null:
		return
	if _battle.is_spread(me, i):
		var _sc: Array = _battle.spread_cells_of(me)
		if _sc.is_empty():
			_hint.text = "周围没有可蔓延的空格"
			return
		if _sc.size() == 1:
			_hint.text = _op_cast(i, null, _sc[0])
			_refresh_board_view()
			_refresh_ui()
			return
		_cast_slot = i
		_hint.text = "蔓延：点选相邻格（可连续点 2 格，点完自动结束）"
		_refresh_board_view()
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
		var r: String = _op_cast(i)
		if r.begins_with("!"):
			_hint.text = r
		else:
			_hint.text = "已行动，AI 应战中…"
		_step()
	else:
		var ts: Array = _battle.targets_in_range(me, i)
		if ts.size() == 1:
			var r2: String = _op_cast(i, ts[0])
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
	# 清理上一局残留棋子（含骨骼角色），否则选人界面会残留旧模型
	for k in _tokens:
		var tk = _tokens[k]
		if is_instance_valid(tk):
			tk.queue_free()
	_tokens.clear()
	if _unit_layer != null and is_instance_valid(_unit_layer):
		for c in _unit_layer.get_children():
			c.queue_free()
	_battle = null
	_select_screen()

## 打开局内设置（含 Bug 上报）
func _open_settings() -> void:
	if _settings == null or not is_instance_valid(_settings):
		_settings = SettingsLayer.new()
		add_child(_settings)
		_settings.visible = false
	var mode := "1V1 · 热座" if Global.offline_type == "hotseat" else "1V1 · 离线 PVE"
	_settings.ctx = {
		"mode": mode,
		"round": _battle.round if _battle != null else 0,
		"logs": _battle.log if _battle != null else [],
	}
	_settings.open_popup()

func _on_end_turn() -> void:
	if _can_input():
		_op_done()
		_hint.text = "等待对方行动…" if Global.net_mode else "AI 应战中…"
		_step()

## 棋盘点击
func _unhandled_input(ev: InputEvent) -> void:
	# 左键按下/抬起：记录长按候选格（移动端长按 = 右键详情）
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			for i in range(_cell_buttons.size()):
				if _cell_buttons[i].get_global_rect().has_point(ev.global_position):
					_lp_active = true
					_lp_fired = false
					_lp_ms = Time.get_ticks_msec()
					_lp_cell = _cell_coords[i]
					break
		else:
			_lp_active = false
		return
	# 右键查看棋子信息：不要求是本方回合（AI 回合也能查），只要对局进行中
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		if _battle != null and _phase == "play":
			var hit: BattleUnit = null
			for i in range(_cell_buttons.size()):
				if _cell_buttons[i].get_global_rect().has_point(ev.global_position):
					hit = _unit_at(_cell_coords[i])
					break
			if hit != null and hit.alive:
				add_child(UnitInfoPopup.make(hit))
			else:
				_focus = null
				_cast_slot = 0
				_hint.text = "已取消选择"
				_refresh_board_view()
		return
	if not _can_input():
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

func _on_cell_clicked(cell: Vector2i) -> void:
	if not _can_input():
		return
	_handle_cell(cell)

func _handle_cell(cell: Vector2i) -> void:
	var me := _battle.current()
	if _cast_slot >= 1:
		var slot := _cast_slot
		if _battle.is_spread(me, slot):
			var rs: String = _op_cast(slot, null, cell)
			if rs.begins_with("!"):
				_hint.text = rs
			else:
				var _rem: Array = _battle.spread_cells_of(me)
				if me.spread_used >= 2 or _rem.is_empty():
					_hint.text = "蔓延完成"
					_cast_slot = 0
				else:
					_hint.text = "已蔓延，还可再点 %d 格（点完自动结束，或右键取消）" % mini(_rem.size(), 2 - me.spread_used)
			_refresh_board_view()
			_refresh_ui()
			return
		if _battle.is_dash(me, slot):
			if _battle.is_charge(me, slot):
				# 冲刺：点敌人 → 朝其方向冲刺并结算
				var tt := _unit_at(cell)
				if tt != null and tt.team != me.team:
					var rc: String = _op_cast(slot, tt)
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
					var rj: String = _op_cast(slot, null, cell)
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
			var r: String = _op_cast(_cast_slot, t)
			if r.begins_with("!"):
				_hint.text = r
			_step()
		else:
			_cast_slot = 0
			_hint.text = "目标无效，已取消技能选择"
		return
	# 聚焦己方棋 / 点可移动格 / 点敌人提示
	var unit := _unit_at(cell)
	# 移动优先：已聚焦且点击格在可达格内（即使格上有 non_solid 队友如虞美人，也可踩上去）
	if _focus != null and cell in _battle.move_cells_of(_focus):
		var r2: String = _op_move(cell)
		if r2.begins_with("!"):
			_hint.text = r2
		else:
			_hint.text = "已移动。可点技能或结束回合"
	elif unit != null and unit.team == me.team and unit.alive:
		_focus = unit
		_hint.text = "已选中 %s：点绿色格移动，或用右侧技能" % unit.name
	elif unit != null and unit.team != me.team:
		_hint.text = "敌方 %s（HP %.2f/%.2f）" % [unit.name, unit.hp, unit.max_hp]
	else:
		_hint.text = "（空格）点自己的棋子开始"
	_refresh_board_view()
	_refresh_ui()   # 移动后必须刷新技能栏（射程/目标/置灰），否则显示移动前的旧判定（2026-09-08 光雨 bug）

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
					if _battle.is_spread(me, _cast_slot):
						if cell in _battle.spread_cells_of(me):
							base = base.lerp(COL_MOVE, 0.45)
					elif _battle.is_dash(me, _cast_slot):
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
		# 三态样式（独立实例，避免共享主题样式互串）
		var n := StyleBoxFlat.new()
		n.bg_color = base
		n.border_color = border_col
		n.set_border_width_all(int(bw))
		var h := n.duplicate(); h.bg_color = base.lerp(Color(1, 1, 1), 0.10)
		var pr := n.duplicate(); pr.bg_color = base.lerp(Color(0, 0, 0), 0.12)
		cb.add_theme_stylebox_override("normal", n)
		cb.add_theme_stylebox_override("hover", h)
		cb.add_theme_stylebox_override("pressed", pr)
		cb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
			if not u.skill_cast.is_connected(tok._on_skill_cast):
				u.skill_cast.connect(tok._on_skill_cast)
		tok.setup(u, u == _focus)
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

## 右侧状态区：被动 / 理智 / 计数印记（元晶、污染…）/ 流血灼烧等状态层数
func _state_bbcode(u: BattleUnit) -> String:
	var parts: Array[String] = []
	if u.passive != null:
		parts.append("[color=#ffd95a]被动·%s[/color] %s" % [u.passive.display_name, u.passive.desc])
	for k in u.counters:
		var v := int(u.counters[k])
		if v > 0:
			parts.append("[color=#8fd48f]%s×%d[/color]" % [k, v])
	var sts: Array = u.status_icons()
	if not sts.is_empty():
		var sp: Array[String] = []
		for d in sts:
			sp.append("%s%d" % [str((d as Dictionary).get("cn", "")), int((d as Dictionary).get("lv", 0))])
		parts.append("[color=#ff7a7a]" + "、".join(sp) + "[/color]")
	if parts.is_empty():
		return "[color=#66707f]（无被动/状态）[/color]"
	return "\n".join(parts)

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

# ================= 战斗日志放大阅读（点击日志区触发） =================
func _on_log_panel_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _battle != null:
		_open_log_popup()

func _open_log_popup() -> void:
	if _battle == null:
		return
	# 放进高 CanvasLayer：日志必须盖过棋盘/棋子（2026-09-08：棋子曾渲染在日志前面）
	var cl := CanvasLayer.new()
	cl.layer = 50
	add_child(cl)
	var layer := Control.new()
	layer.name = "LogPopup"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(layer)
	layer.tree_exited.connect(func():
		if is_instance_valid(cl):
			cl.queue_free())
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 1.0)   # 不透明：挡死底下棋子（用户要求弹窗不透明）
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70.0
	panel.offset_top = 55.0
	panel.offset_right = -70.0
	panel.offset_bottom = -60.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.09, 0.11, 0.17, 0.99)
	ps.set_corner_radius_all(14)
	ps.border_color = Color(0.55, 0.50, 0.36)
	ps.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", ps)
	layer.add_child(panel)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 16)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var tt := Label.new()
	tt.text = "战斗日志（完整 · 最近 500 行）"
	tt.add_theme_font_size_override("font_size", 22)
	tt.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))
	v.add_child(tt)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.text = _logs_full_bbcode()
	v.add_child(rt)
	var xb := Button.new()
	xb.text = "✕ 收 起"
	xb.focus_mode = Control.FOCUS_NONE
	xb.custom_minimum_size = Vector2(150, 42)
	xb.pressed.connect(func(): layer.queue_free())
	var bc := CenterContainer.new()
	bc.add_child(xb)
	v.add_child(bc)
	bg.gui_input.connect(func(ev2: InputEvent):
		if ev2 is InputEventMouseButton and ev2.pressed:
			layer.queue_free())

func _logs_full_bbcode() -> String:
	if _battle == null:
		return ""
	var out := ""
	var head := maxi(0, _battle.log.size() - 500)
	for i in range(head, _battle.log.size()):
		var s: String = _battle.log[i]
		if s.begins_with("——") or s.begins_with("=="):
			out += "[color=#ffd95a]%s[/color]\n" % s
		else:
			out += s + "\n"
	return out

## PVE：AI 随机为蓝方选一个英雄（排除红方已选），并刷新界面显示。
## 2026-09-08 修复：进选人界面即定下蓝方，界面从第一刻就显示蓝方真正会选的人，不再默认亮邪神。
func _ai_pick_blue() -> void:
	var pool: Array = []
	for hid in _hero_ids:
		if hid != _red_id:
			pool.append(hid)
	if pool.is_empty():
		return
	_blue_id = str(pool[randi() % pool.size()])
	_blue_picked = true
	_refresh_pick_highlight()
