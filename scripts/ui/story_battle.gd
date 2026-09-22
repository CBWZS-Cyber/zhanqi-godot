extends Control
## 骑士线第一关 · 白灵殿 可玩关卡（魔渊 7 人 vs 白灵殿 10 人 · 护送关）
##
## 阵营：蓝方 = 白灵殿（玩家控制，10 单位）／红方 = 魔渊（AI 控制，7 单位）
## 目标（2026-09-12 改）：把【昊】与【祁】都送进地图最右侧 4 格青绿色逃生区；
##   两人任意一人阵亡 / 白灵殿全灭 = 失败。
## 操作：点自己的棋子 → 点绿色格移动（每回合 2 步、8 方向各 1 格）／点右侧技能 → 再点橙色目标。
##      昊携带白灵核心，每回合只能走 1 步。
## 界面结构沿用 4V4（team_duel.gd）：顶栏 + 左棋盘 + 右侧信息卡（血条/能量/状态/技能/日志）。

const _BAT := preload("res://scripts/combat/battle_story.gd")
const _BD := preload("res://scripts/ui/story_battle_board.gd")
# Terrain 已由 scripts/combat/terrain.gd 的 class_name 全局注册，直接用即可

const COL_BG := Color(0.20, 0.18, 0.16)
const COL_PANEL := Color(0.10, 0.12, 0.19, 0.94)
const COL_GOLD := Color(0.941, 0.780, 0.369)
const COL_RED := Color(0.78, 0.25, 0.18)
const COL_BLUE := Color(0.24, 0.42, 0.75)
const SIDE_W := 330.0

var _phase := "play"          # play / over
var _battle: BattleStory = null
var _focus: BattleUnit = null
var _cast_slot := 0
var _multi_targets: Array = []
var _hint_text := ""
var _sfx_round := -1
var _settings = null
var _over_layer = null

# UI
var _title: Label
var _hint: Label
var _round_lab: Label
var _goal_lab: Label
var _action_lab: Label
var _name_lab: Label
var _hp_bar: HBoxContainer
var _en_bar: HBoxContainer
var _sub_lab: Label
var _state_lab: RichTextLabel
var _skill_grid: GridContainer
var _skill_buttons: Array = []
var _skill_desc: Label
var _log: RichTextLabel
var _over_lab: Label
var _board: Control
var _roster: HBoxContainer
var _skip_btn: Button

# ============================================================ 生命周期
func _ready() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", _panel_style(COL_BG, 0))
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var pad := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(k, 10)
	root.add_child(pad)
	pad.add_child(_build_main())
	_start()

# ============================================================ 界面搭建
func _build_main() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	# —— 顶栏 ——
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "⚙ 设置"
	back.pressed.connect(_open_settings)
	_style_btn(back)
	top.add_child(back)
	_round_lab = Label.new()
	_round_lab.add_theme_font_size_override("font_size", 17)
	_round_lab.add_theme_color_override("font_color", COL_GOLD)
	top.add_child(_round_lab)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	top.add_child(_title)
	_goal_lab = Label.new()
	_goal_lab.add_theme_font_size_override("font_size", 15)
	_goal_lab.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	top.add_child(_goal_lab)
	_skip_btn = Button.new()
	_skip_btn.text = "结束行动"
	_skip_btn.pressed.connect(_on_skip)
	_style_btn(_skip_btn)
	top.add_child(_skip_btn)
	v.add_child(top)

	# —— 中栏：左棋盘 / 右信息卡 ——
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	v.add_child(mid)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 5)
	mid.add_child(left)
	_board = _BD.new()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(620, 400)
	left.add_child(_board)
	_board.cell_clicked.connect(_on_cell)
	_board.right_clicked.connect(_on_right_click)
	_roster = HBoxContainer.new()
	_roster.add_theme_constant_override("separation", 4)
	left.add_child(_roster)
	_hint = Label.new()
	_hint.text = ""
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 34)
	_hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	left.add_child(_hint)

	mid.add_child(_build_right_card())
	return v

func _build_right_card() -> Panel:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, 14))
	card.custom_minimum_size = Vector2(SIDE_W, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rmargin := MarginContainer.new()
	rmargin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		rmargin.add_theme_constant_override(k, 10)
	card.add_child(rmargin)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	rmargin.add_child(right)

	_action_lab = Label.new()
	_action_lab.add_theme_font_size_override("font_size", 14)
	_action_lab.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(_action_lab)
	_name_lab = Label.new()
	_name_lab.add_theme_font_size_override("font_size", 22)
	_name_lab.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	right.add_child(_name_lab)
	_hp_bar = _make_bar("生命", COL_RED, 1, 1, true)
	right.add_child(_hp_bar)
	_en_bar = _make_bar("能量", COL_BLUE, 1, 1)
	right.add_child(_en_bar)
	_sub_lab = Label.new()
	_sub_lab.add_theme_font_size_override("font_size", 12)
	_sub_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_lab.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	right.add_child(_sub_lab)
	_state_lab = RichTextLabel.new()
	_state_lab.bbcode_enabled = true
	_state_lab.fit_content = true
	_state_lab.scroll_active = false
	_state_lab.add_theme_font_size_override("normal_font_size", 13)
	_state_lab.add_theme_color_override("default_color", Color(0.75, 0.80, 0.88))
	right.add_child(_state_lab)

	var lab_skill := Label.new()
	lab_skill.text = "技能"
	lab_skill.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(lab_skill)
	_skill_grid = GridContainer.new()
	_skill_grid.columns = 2
	_skill_grid.add_theme_constant_override("h_separation", 6)
	_skill_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_skill_grid)
	_skill_desc = Label.new()
	_skill_desc.text = ""
	_skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_desc.custom_minimum_size = Vector2(0, 40)
	_skill_desc.add_theme_color_override("font_color", Color(0.72, 0.77, 0.85))
	right.add_child(_skill_desc)

	var log_title := Label.new()
	log_title.text = "战斗日志"
	log_title.add_theme_color_override("font_color", COL_GOLD)
	right.add_child(log_title)
	var log_panel := Panel.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.14, 0.85), 8))
	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(k, 6)
	log_panel.add_child(inner)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_log)
	right.add_child(log_panel)
	log_panel.gui_input.connect(_on_log_panel_click)
	_log.gui_input.connect(_on_log_panel_click)

	_over_lab = Label.new()
	_over_lab.text = ""
	_over_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_lab.add_theme_font_size_override("font_size", 18)
	_over_lab.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	right.add_child(_over_lab)
	return card

# ============================================================ 小控件
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

func _panel_style(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.35, 0.32, 0.26)
	if radius > 0:
		sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	return sb

func _make_bar(tag: String, col: Color, value: int, max_value: int, tiled := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.custom_minimum_size = Vector2(42, 0)
	tag_l.add_theme_font_size_override("font_size", 14)
	tag_l.add_theme_color_override("font_color", Color(0.84, 0.87, 0.92))
	row.add_child(tag_l)
	var bar: Control
	if tiled:
		# 生命条改用 HpShieldBar：能在同一条里分段显示 hp + 护盾（2026-09-13）
		var hsb := HpShieldBar.new()
		hsb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hsb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hsb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hsb.custom_minimum_size = Vector2(0, 22)
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
		pb.custom_minimum_size = Vector2(0, 22)
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
	num.text = "%.2f / %.2f" % [float(value), float(max_value)]
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.add_child(num)
	row.add_child(bar)
	return row

func _update_bar(bar: HBoxContainer, value: float, max_value: float, num_text := "", tag_text := "", smooth := false, shield := 0.0) -> void:
	# 统一走 DamageFx.update_bar（兼容 HpShieldBar / ProgressBar，并保证数字标签一定被写）
	DamageFx.update_bar(bar, value, max_value, num_text, tag_text, smooth, shield)

# ============================================================ 对局流程
func _start() -> void:
	_phase = "play"
	_focus = null
	_cast_slot = 0
	_multi_targets = []
	_hint_text = ""
	_over_lab.text = ""
	_skip_btn.visible = true
	if _over_layer != null and is_instance_valid(_over_layer):
		_over_layer.queue_free()
	_over_layer = null
	_battle = _BAT.new()
	_battle.human_mode = true
	_battle.human_teams = [_BAT.TEAM_BLUE]
	_battle.human_team = _BAT.TEAM_BLUE
	_title.text = "骑士线 · 第一关 白灵殿"
	_board.set_map(_battle.cells, _battle.terrain_types, _battle.escape_cells)
	_board.set_battle_units(_battle.units, null, null, _battle.protect_target, _battle.escort_qi)
	if _battle.protect_target != null:
		_board.center_on(_battle.protect_target.cell)
	_step()

## 结算到「轮到玩家」或「分出胜负」
func _step() -> void:
	if _battle == null:
		return
	var st: Dictionary = _battle.run_step()
	_focus = null
	_cast_slot = 0
	_multi_targets = []
	if st.has("over"):
		_phase = "over"
		Sfx.play("victory")
		var who := str(st["over"])
		_over_lab.text = "对局结束：%s" % who
		_hint_text = "胜负已分"
		_skip_btn.visible = false
		_show_over(who == "白灵殿")
	elif st.has("wait"):
		if _battle.round != _sfx_round:
			_sfx_round = _battle.round
			Sfx.play("alarm")
		var cur := _battle.current()
		if cur != null:
			var steps: int = _battle.steps_of(cur)
			_hint_text = "轮到【%s】：点绿色格移动（本回合 %d 步，8 方向）或点右侧技能；也可直接结束行动" % [cur.name, steps]
			_board.center_on(cur.cell)
	_refresh_board()
	_refresh_ui()

func _can_input() -> bool:
	return _battle != null and _phase == "play" and _battle.waiting()

func _on_skip() -> void:
	if not _can_input():
		return
	Sfx.play("click")
	_battle.human_done()
	_hint_text = "已结束行动…"
	_step()

func _quit() -> void:
	Sfx.play("click")
	get_tree().change_scene_to_file("res://scenes/MainUI.tscn")

func _open_settings() -> void:
	if _settings == null or not is_instance_valid(_settings):
		_settings = SettingsLayer.new()
		add_child(_settings)
		_settings.visible = false
	_settings.ctx = {
		"mode": "剧情 · 骑士线第一关（白灵殿护送）",
		"round": _battle.round if _battle != null else 0,
		"logs": _battle.log if _battle != null else [],
	}
	_settings.open_popup()

# ============================================================ 棋盘交互
func _unit_at(cell: Vector2i) -> BattleUnit:
	if _battle == null:
		return null
	for u in _battle.units:
		if u.cell == cell and u.alive:
			return u
	return null

## 该格地形 id（-1 = 地图外）
func _terrain_at(cell: Vector2i) -> int:
	if _battle == null:
		return -1
	var k := "%d,%d" % [cell.x, cell.y]
	if not _battle.cells.has(k):
		return -1
	return int(_battle.cells[k])

## 该格地形名（地图外/空地返回 ""）
func _terrain_name(cell: Vector2i) -> String:
	var t := _terrain_at(cell)
	if t <= 0:
		return ""
	return Terrain.name_of(t)

func _on_right_click(cell: Vector2i) -> void:
	if _battle == null or _phase != "play":
		return
	var u := _unit_at(cell)
	if u != null:
		add_child(UnitInfoPopup.make(u))
		return
	# 空格：取消当前选择
	_focus = null
	_cast_slot = 0
	_multi_targets = []
	_hint_text = "已取消选择"
	_refresh_board()
	_refresh_ui()

func _on_cell(cell: Vector2i) -> void:
	if not _can_input():
		return
	var me := _battle.current()
	if me == null:
		return
	# —— 技能选目标阶段 ——
	if _cast_slot >= 1:
		_pick_cast_target(cell)
		return
	# —— 常规：移动 / 选中 / 查看 ——
	var unit := _unit_at(cell)
	if _focus != null and _focus == me and not _battle.human_moved() and cell in _battle.move_cells_of(_focus):
		var r2: String = _battle.human_move(cell)
		if r2.begins_with("!"):
			Sfx.play("error")
			_hint_text = r2.trim_prefix("!")
		else:
			Sfx.play("footstep")
			_hint_text = "已移动。可再点技能，或结束行动"
	elif unit != null and unit.team == me.team:
		_focus = unit
		_hint_text = "已选中 %s：点绿色格移动，或点右侧技能" % unit.name
	elif unit != null:
		_hint_text = "敌方 %s（HP %.2f/%.2f）盾 %.2f · 甲 %.2f · 速 %d" % [unit.name, unit.hp, unit.max_hp, unit.shield, unit.armor, unit.effective_speed()]
	elif _terrain_at(cell) == 1:
		# 可破坏障碍（2026-09-12）：不作为报错，只给说明
		_hint_text = "可破坏障碍：魔渊（红方）的攻击技能可把它当目标击碎（受 1 点伤害后变空地）"
	else:
		var tn := _terrain_name(cell)
		_hint_text = "（%s）点自己的棋子开始行动" % (tn if tn != "" else "空地")
	_refresh_board()
	_refresh_ui()

## 技能已按下后的点格：按目标类型（敌/友/任意/可破坏障碍）校验并累积多目标
func _pick_cast_target(cell: Vector2i) -> void:
	var me := _battle.current()
	var slot := _cast_slot
	var kind := _battle.target_kind_of(me, slot)
	var t := _unit_at(cell)
	# —— 情况一：点在可破坏障碍格上（2026-09-12 新增）——
	if t == null:
		var bl: Array = _battle.breakable_in_range(me, slot)
		if bl.has(cell):
			_do_cast(slot, cell, [])
			return
		_cast_slot = 0
		_multi_targets = []
		_hint_text = "目标无效（该格不是单位，也不是射程内的可破坏障碍），已取消技能"
		_refresh_board()
		_refresh_ui()
		return
	if t == me:
		_cast_slot = 0
		_multi_targets = []
		_hint_text = "目标无效（不能选自己），已取消技能"
		_refresh_board()
		_refresh_ui()
		return
	if kind == "enemy" and t.team == me.team:
		_hint_text = "这是友军，该技能只能选敌人"
		_refresh_ui()
		return
	if kind == "ally" and t.team != me.team:
		_hint_text = "这是敌人，该技能只能选友军"
		_refresh_ui()
		return
	if not (t in _battle.targets_in_range(me, slot)):
		_cast_slot = 0
		_multi_targets = []
		_hint_text = "目标不在射程内，已取消技能"
		_refresh_board()
		_refresh_ui()
		return
	var mx := _battle.max_targets_of(me, slot)
	if mx <= 1:
		_do_cast(slot, t, [])
		return
	if _multi_targets.has(t):
		_multi_targets.erase(t)
		_hint_text = "已取消选中 %s（当前 %d/%d）" % [t.name, _multi_targets.size(), mx]
		_refresh_board()
		_refresh_ui()
		return
	_multi_targets.append(t)
	if _multi_targets.size() >= mx:
		_do_cast(slot, _multi_targets[0], _multi_targets)
		return
	_hint_text = "已选 %d/%d 个目标，继续点选（再点该技能按钮可直接施放）" % [_multi_targets.size(), mx]
	_refresh_board()
	_refresh_ui()

# ============================================================ 技能
func _on_skill(i: int) -> void:
	if not _can_input():
		return
	Sfx.play("click")
	var me := _battle.current()
	if me == null:
		return
	# 已在该技能的多目标选点模式 → 按当前已选目标直接施放
	if _cast_slot == i:
		if _multi_targets.is_empty():
			_cast_slot = 0
			_hint_text = "已取消技能选择"
			_refresh_board()
			_refresh_ui()
			return
		_do_cast(i, _multi_targets[0], _multi_targets)
		return
	if _battle.self_skill(me, i):
		_do_cast(i, null, [])
		return
	var ts: Array = _battle.targets_in_range(me, i)
	var bs: Array = _battle.breakable_in_range(me, i)
	if ts.is_empty() and bs.is_empty():
		_hint_text = "射程内没有合法目标"
		_refresh_ui()
		return
	var mx := _battle.max_targets_of(me, i)
	_multi_targets = []
	# 只有单位目标且恰好 1 个 / 上限 1 → 直接放；否则进入点选模式
	if mx <= 1 and ts.size() == 1 and bs.is_empty():
		_do_cast(i, ts[0], [])
		return
	_cast_slot = i
	var kind_cn := "敌人" if _battle.target_kind_of(me, i) == "enemy" else ("友军" if _battle.target_kind_of(me, i) == "ally" else "单位")
	var brk_tip := "，或点橙红色描边的可破坏障碍将其击碎" if not bs.is_empty() else ""
	_hint_text = "点橙色高亮的%s（可选 %d 个，已选 0）%s" % [kind_cn, mx, brk_tip]
	_refresh_board()
	_refresh_ui()

func _do_cast(slot: int, target, extras: Array) -> void:
	var r: String = _battle.human_cast(slot, target, extras)
	var failed := r.begins_with("!")
	if not failed:
		for kw in ["未配置", "能量不足", "还在冷却", "无法使用", "被掠夺", "本局已用尽", "被封印"]:
			if r.contains(kw):
				failed = true
				break
	if failed:
		Sfx.play("error")
		_hint_text = r.trim_prefix("!")
		_cast_slot = 0
		_multi_targets = []
		_refresh_board()
		_refresh_ui()
		return
	Sfx.play("powerup" if _battle != null and _cast_slot == 0 else "hit")
	_cast_slot = 0
	_multi_targets = []
	_hint_text = "已行动"
	_step()

# ============================================================ 刷新
func _refresh_board() -> void:
	if _board == null or _battle == null:
		return
	var cur := _battle.current() if _battle.waiting() else null
	_board.set_battle_units(_battle.units, _focus, cur, _battle.protect_target, _battle.escort_qi)
	_board.move_cells = []
	_board.target_cells = []
	_board.break_cells = []
	_board.chosen_cells = []
	if _phase == "play" and _battle.waiting():
		var me := _battle.current()
		if me != null:
			if _cast_slot == 0 and not _battle.human_moved() and (_focus == null or _focus == me):
				_board.move_cells = _battle.move_cells_of(me)
			if _cast_slot >= 1:
				if _battle.self_skill(me, _cast_slot):
					pass
				else:
					for t in _battle.targets_in_range(me, _cast_slot):
						_board.target_cells.append((t as BattleUnit).cell)
					for c in _battle.breakable_in_range(me, _cast_slot):
						_board.break_cells.append(c)
					for t in _multi_targets:
						if t is Vector2i:
							_board.chosen_cells.append(t)
						else:
							_board.chosen_cells.append((t as BattleUnit).cell)
	# 格子数据可能已被"拆障碍"改写 → 用最新 cells 重新灌一遍（refit=false 保住缩放/平移）
	_board.set_map(_battle.cells, _battle.terrain_types, _battle.escape_cells, false)
	_board.queue_redraw()

func _refresh_ui() -> void:
	if _battle == null:
		return
	_refresh_goal()
	_refresh_roster()
	var shown: BattleUnit = _battle.current()
	if shown == null:
		for u in _battle.units:
			if u.alive:
				shown = u
				break
	if shown == null:
		return
	var side := "魔渊" if shown.team == _BAT.TEAM_RED else "白灵殿"
	var who := "（玩家）" if shown.team == _BAT.TEAM_BLUE else "（AI）"
	_action_lab.text = "行动 · %s%s" % [side, who]
	_name_lab.text = "%s · %s" % [shown.name, side]
	_update_bar(_hp_bar, shown.hp, shown.max_hp, "", "", true, shown.shield)
	_update_bar(_en_bar, shown.energy, shown.max_energy)
	_sub_lab.text = "盾 %.2f · 甲 %.2f · 速 %d%s" % [shown.shield, shown.armor, shown.effective_speed(), shown.to_status_summary()]
	_state_lab.text = _state_bbcode(shown)
	# 技能按钮
	for nb in _skill_buttons:
		if nb != null and is_instance_valid(nb):
			nb.queue_free()
	_skill_buttons.clear()
	var me := _battle.current() if (_phase == "play" and _battle.waiting()) else null
	if me == null:
		_skill_grid.visible = false
		_refresh_log()
		return
	_skill_grid.visible = true
	for i in range(1, 5):
		var sk := me.get_skill(i)
		if sk == null:
			continue
		var nb := Button.new()
		var why := ""
		if me.is_skill_lost(sk.id):
			why = "被禁用"
		elif sk.exhausted():
			why = "本局已用尽"
		elif sk.current_cd > 0:
			why = "冷却 %d 回合" % sk.current_cd
		elif me.energy < float(sk.energy_cost):
			why = "能量不足（需 %d，现 %.0f）" % [sk.energy_cost, me.energy]
		elif me.has_flag("no_skill") or me.has_flag("no_damage") or (i == 4 and me.has_flag("no_ult")):
			why = "被沉默"
		elif not _battle.self_skill(me, i) and _battle.targets_in_range(me, i).is_empty():
			var nd := 99
			var kind := _battle.target_kind_of(me, i)
			for f in _battle.units:
				var fu: BattleUnit = f
				if not fu.alive or fu == me:
					continue
				if kind == "enemy" and fu.team == me.team:
					continue
				if kind == "ally" and fu.team != me.team:
					continue
				nd = mini(nd, _battle.dist(me, fu))
			why = "射程内无目标（最近 %s 格 / 射程 %d）" % [("?" if nd >= 99 else str(nd)), _battle.skill_range(me, i)]
		nb.text = sk.display_name
		var tip := "[%s] 耗能 %d · 射程 %d" % [sk.display_name, sk.energy_cost, _battle.skill_range(me, i)]
		if why != "":
			tip += "（不可用：%s）" % why
		tip += "\n" + sk.desc
		nb.mouse_entered.connect(func(): _skill_desc.text = tip)
		nb.mouse_exited.connect(func(): _skill_desc.text = "")
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size = Vector2(0, 40)
		nb.add_theme_font_size_override("font_size", 13)
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
			nb.pressed.connect(func(): _on_skill(i))
		_skill_buttons.append(nb)
		_skill_grid.add_child(nb)
	_refresh_log()

## 顶栏目标进度：昊 + 祁 各自离逃生区还有几步 + 双方存活数
func _refresh_goal() -> void:
	var h = _battle.protect_target
	var q = _battle.escort_qi
	var nr := 0
	var nb2 := 0
	for u in _battle.units:
		if not u.alive:
			continue
		if u.team == _BAT.TEAM_RED:
			nr += 1
		else:
			nb2 += 1
	_round_lab.text = "第 %d 回合 · 魔渊 %d : %d 白灵殿" % [_battle.round, nr, nb2]
	_goal_lab.text = "护送【昊 + 祁】→ 最右侧 4 格 %s%s" % [
		_escort_txt("昊", h), _escort_txt("祁", q)]

## 单个护送目标的进度文案
func _escort_txt(label: String, u) -> String:
	if u == null:
		return " · %s：缺失" % label
	if not u.alive:
		return " · %s：已阵亡" % label
	if _battle.escape_cells.has(u.cell):
		return " · %s：✅ 已就位（HP %.0f/%.0f）" % [label, u.hp, u.max_hp]
	var d: int = _battle.dist_to_escape(u.cell)
	var dist_txt := ("还差 %d 步" % d) if d > 0 else "不可达"
	return " · %s：%s（HP %.0f/%.0f）" % [label, dist_txt, u.hp, u.max_hp]

## 昊的自动东移提示文案
func _auto_tip(u) -> String:
	if u == null or not u.alive:
		return ""
	var every: int = _BAT.HAO_AUTO_EVERY if u == _battle.protect_target else int(_BAT.QI_AUTO_EVERY)
	if every <= 0:
		return ""
	var mod: int = _battle.round % every
	return " · 本回合末自动东移 1 格" if mod == 0 else " · 再 %d 回合自动东移 1 格" % (every - mod)

## 棋盘下方战况条：点一下把镜头挪过去
func _refresh_roster() -> void:
	for c in _roster.get_children():
		c.queue_free()
	for u in _battle.units:
		var bu: BattleUnit = u
		if not bu.alive:
			continue
		var b := Button.new()
		var mine := bu.team == _BAT.TEAM_BLUE
		b.text = "%s %.0f" % [bu.name, bu.hp]
		b.tooltip_text = "%s（%s）\n生命 %.2f/%.2f · 能量 %.0f/%.0f · 甲 %.2f · 速 %d\n位于 %s" % [
			bu.name, "白灵殿" if mine else "魔渊", bu.hp, bu.max_hp, bu.energy, bu.max_energy,
			bu.armor, bu.effective_speed(), bu.cell]
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(0, 26)
		var col := Color(0.28, 0.46, 0.82, 0.85) if mine else Color(0.72, 0.26, 0.20, 0.85)
		if bu == _battle.current():
			col = Color(0.90, 0.72, 0.25, 0.95)
		if bu == _battle.protect_target:
			col = Color(0.95, 0.82, 0.30, 0.95)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.10, 0.10, 0.12, 0.8)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(1, 1, 1))
		var cell: Vector2i = bu.cell
		b.pressed.connect(func():
			_board.center_on(cell)
			_hint_text = "镜头已移到 %s（%s）" % [bu.name, cell]
			_refresh_ui())
		_roster.add_child(b)

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
			sp.append(str((d as Dictionary).get("label", "")))   # 文本由 SkillEffects.status_label 统一生成
		parts.append("[color=#ff7a7a]" + "、".join(sp) + "[/color]")
	if u.team == _BAT.TEAM_BLUE and (u == _battle.protect_target or u == _battle.escort_qi):
		parts.append("[color=#ffd95a]★ 护送目标：与另一名同伴一起站进地图最右侧 4 格逃生区[/color]")
		var every: int = int(_BAT.HAO_AUTO_EVERY) if u == _battle.protect_target else int(_BAT.QI_AUTO_EVERY)
		if every > 0:
			parts.append("[color=#ff9a6a]▲ 不受控：每 %d 回合末自动向东挪 1 格（别让他跑在护卫前面）[/color]" % every)
	if parts.is_empty():
		return "[color=#66707f]（无被动/状态）[/color]"
	return "\n".join(parts)

func _refresh_log() -> void:
	if _battle == null:
		return
	var lines: Array = _battle.log
	var head := maxi(0, lines.size() - 140)
	var out := ""
	for j in range(head, lines.size()):
		var s: String = lines[j]
		if s.begins_with("——") or s.begins_with("=="):
			out += "[color=#ffd95a]%s[/color]\n" % s
		elif s.begins_with("【破障】"):
			out += "[color=#ffa060]%s[/color]\n" % s
		elif s.begins_with("!"):
			out += "[color=#ff8a8a]%s[/color]\n" % s
		else:
			out += s + "\n"
	_log.text = out
	if lines.size() > 0:
		_log.scroll_to_line(_log.get_line_count())
	if _hint != null:
		_hint.text = _hint_text

# ============================================================ 日志放大
func _on_log_panel_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _battle != null:
		_open_log_popup()

func _open_log_popup() -> void:
	if _battle == null:
		return
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
	bg.color = Color(0.04, 0.05, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70.0
	panel.offset_top = 55.0
	panel.offset_right = -70.0
	panel.offset_bottom = -60.0
	var ps := _panel_style(Color(0.09, 0.11, 0.17, 0.99), 14)
	ps.border_color = Color(0.55, 0.50, 0.36)
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
	tt.add_theme_color_override("font_color", COL_GOLD)
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
	_style_btn(xb)
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

# ============================================================ 结算
func _show_over(win: bool) -> void:
	if _over_layer != null and is_instance_valid(_over_layer):
		return
	var cl := CanvasLayer.new()
	cl.layer = 60
	add_child(cl)
	_over_layer = cl
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	layer.add_child(box)

	var t := Label.new()
	t.text = "胜 利 · 昊 成 功 脱 身" if win else "失 败 · 白 灵 核 心 失 守"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", COL_GOLD if win else Color(0.95, 0.45, 0.38))
	box.add_child(t)

	var sub := Label.new()
	sub.text = _over_summary()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.86, 0.89, 0.94))
	box.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var b1 := Button.new()
	b1.text = "再 试 一 次"
	b1.custom_minimum_size = Vector2(160, 46)
	_style_btn(b1)
	b1.pressed.connect(func():
		Sfx.play("click")
		layer.queue_free()
		_start())
	row.add_child(b1)

	var b2 := Button.new()
	b2.text = "查 看 战 报"
	b2.custom_minimum_size = Vector2(160, 46)
	_style_btn(b2)
	b2.pressed.connect(func():
		Sfx.play("click")
		_open_log_popup())
	row.add_child(b2)

	var b3 := Button.new()
	b3.text = "返 回 主 菜 单"
	b3.custom_minimum_size = Vector2(160, 46)
	_style_btn(b3)
	b3.pressed.connect(_quit)
	row.add_child(b3)

func _over_summary() -> String:
	if _battle == null:
		return ""
	var nr := 0
	var nb2 := 0
	for u in _battle.units:
		if u.alive:
			if u.team == _BAT.TEAM_RED:
				nr += 1
			else:
				nb2 += 1
	var h = _battle.protect_target
	var q = _battle.escort_qi
	return "第 %d 回合结束 · 魔渊存活 %d · 白灵殿存活 %d\n%s" % [
		_battle.round, nr, nb2, _escort_txt("昊", h) + _escort_txt("祁", q)]
