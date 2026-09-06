extends Control
## 战棋 4V4 可玩对局（离线 PVE / 热座）
## 流程：点己方棋子聚焦 → 点绿色格移动 / 点技能（需目标时再点橙色敌人）→ 结束行动
## PVE：红方=玩家 vs 蓝方=AI；热座：红蓝都是玩家（Global.offline_type）
## 行动节奏与 1V1 一致：每棋每回合 1 移动 + 1 技能，按实时速度依次行动。

const CELL_SEP := 0.0
const _BAT := preload("res://scripts/combat/battle_team.gd")
const _HD := preload("res://scripts/combat/hero_defs.gd")
const _BD := preload("res://scripts/ui/team_board.gd")
const COL_BG := Color(0.20, 0.18, 0.16)
const COL_TEXT := Color(0.18, 0.13, 0.09)
const COL_PANEL := Color(0.10, 0.12, 0.19, 0.94)
const COL_GOLD := Color(0.941, 0.780, 0.369)
const COL_RED := Color(0.78, 0.25, 0.18)
const COL_BLUE := Color(0.24, 0.42, 0.75)
const SIDE_W := 300.0

var _phase := "play"        # play / over
var _battle: BattleTeam = null
var _focus: BattleUnit = null
var _cast_slot := 0
var _sfx_round: int = -1               # 音效：已提示过回合开始 alarm 的回合数
var _multi_targets: Array = []   # 多目标技（如追猎流星飞弹）已点选的目标
var _hint_text := ""
var _red_ids: Array = []
var _blue_ids: Array = []
var _settings: SettingsLayer = null

# UI
var _title: Label
var _hint: Label
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
var _board_holder: Control
var _skip_btn: Button
var _bar_hero_lab: Label
var _round_lab: Label

## ===== 选人（draft）状态 =====
var _draft_seq: Array = []       # [{side,n}...] 蛇形轮次
var _draft_i := 0                # 当前轮次下标
var _draft_done := 0             # 当前轮次内已选数
var _draft_overlay: Control = null
var _draft_title: Label
var _draft_sub: Label
var _red_lab: Label
var _blue_lab: Label
var _draft_grid: GridContainer

# ===== 联机（阶段5）=====
const _NP := preload("res://scripts/net/net_protocol.gd")
var _autonet_role := ""
func _my_team() -> int:
	return 0 if Global.net_is_host else 1
func _can_input() -> bool:
	if _battle == null or _phase != "play" or not _battle.waiting():
		return false
	if Global.net_mode and _battle.current().team != _my_team():
		return false
	return true

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
	_autonet_detect()
	if Global.net_mode:
		if not Net.cmd_received.is_connected(_on_net_cmd):
			Net.cmd_received.connect(_on_net_cmd)
		if not Net.opening_received.is_connected(_on_net_opening):
			Net.opening_received.connect(_on_net_opening)
		if not Net.peer_left.is_connected(_on_net_left):
			Net.peer_left.connect(_on_net_left)
	_enter_select()
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

func _panel_style(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.35, 0.32, 0.26)
	if radius > 0:
		sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	return sb

func _make_bar(tag: String, col: Color, value: int, max_value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.custom_minimum_size = Vector2(42, 0)
	tag_l.add_theme_font_size_override("font_size", 14)
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
	bar.custom_minimum_size = Vector2(0, 22)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	var bgst := StyleBoxFlat.new()
	bgst.bg_color = Color(0.04, 0.05, 0.09, 0.9)
	bgst.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bgst)
	var num := Label.new()
	num.text = "%.2f / %.2f" % [value, max_value]
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_color_override("font_color", Color(1, 1, 1))
	bar.add_child(num)
	row.add_child(bar)
	return row

func _update_bar(bar: HBoxContainer, value: float, max_value: float, num_text := "", tag_text := "") -> void:
	for c in bar.get_children():
		if c is Label and tag_text != "":
			(c as Label).text = tag_text
			break
	for c in bar.get_children():
		if c is ProgressBar:
			var pb := c as ProgressBar
			pb.max_value = max_value if max_value > 0 else 1
			pb.value = clampf(value, 0.0, pb.max_value)
			for cc in pb.get_children():
				if cc is Label:
					(cc as Label).text = num_text if num_text != "" else ("%.2f / %.2f" % [value, max_value])

func _build_main() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	# 顶栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "⚙ 设置"
	back.pressed.connect(_open_settings)
	_style_btn(back)
	top.add_child(back)
	_round_lab = Label.new()
	_round_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_lab.add_theme_font_size_override("font_size", 18)
	_round_lab.add_theme_color_override("font_color", COL_GOLD)
	top.add_child(_round_lab)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(240, 0)
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	top.add_child(_title)
	_skip_btn = Button.new()
	_skip_btn.text = "结束行动"
	_skip_btn.pressed.connect(_on_skip)
	_style_btn(_skip_btn)
	top.add_child(_skip_btn)
	v.add_child(top)
	# 中栏：左棋盘 / 右面板
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(mid)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	mid.add_child(left)
	_board_holder = CenterContainer.new()
	_board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_board_holder)
	_board = _BD.new()
	_board.custom_minimum_size = Vector2(700, 520)
	_board_holder.add_child(_board)
	_hint = Label.new()
	_hint.text = ""
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	left.add_child(_hint)
	# 右侧信息卡
	var right_card := Panel.new()
	var rcs := StyleBoxFlat.new()
	rcs.bg_color = COL_PANEL
	rcs.set_corner_radius_all(14)
	right_card.add_theme_stylebox_override("panel", rcs)
	right_card.custom_minimum_size = Vector2(SIDE_W, 0)
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right_card)
	var rmargin := MarginContainer.new()
	rmargin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		rmargin.add_theme_constant_override(k, 10)
	right_card.add_child(rmargin)
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
	_hp_bar = _make_bar("生命", COL_RED, 1, 1)
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
	_skill_desc.custom_minimum_size = Vector2(0, 34)
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
	lps.set_corner_radius_all(8)
	log_panel.add_theme_stylebox_override("panel", lps)
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
	_over_lab = Label.new()
	_over_lab.text = ""
	_over_lab.add_theme_font_size_override("font_size", 18)
	_over_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_lab.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	right.add_child(_over_lab)
	_board.cell_clicked.connect(_on_cell)
	_board.right_clicked.connect(_on_right_click)
	return v

## ================= 对局流程 =================
## 进入选人阶段（4V4 蛇形选人：红1 → 蓝2 → 红2 → 蓝2 → 红1）
func _enter_select() -> void:
	_phase = "select"
	_red_ids = []
	_blue_ids = []
	_focus = null
	_cast_slot = 0
	_multi_targets = []
	_skip_btn.visible = false
	if Global.net_mode:
		_title.text = "联机 4V4 · 选人（你执%s，轮到你时点击）" % ("红方" if _my_team() == 0 else "蓝方")
	else:
		_title.text = "4V4 · 选人" + ("（红方你 vs 蓝方 AI）" if Global.offline_type != "hotseat" else "（热座）")
	_round_lab.text = "蛇形选人：红 1 → 蓝 2 → 红 2 → 蓝 2 → 红 1"
	_over_lab.text = ""
	_draft_seq = [{"side": 0, "n": 1}, {"side": 1, "n": 2}, {"side": 0, "n": 2}, {"side": 1, "n": 2}, {"side": 0, "n": 1}]
	_draft_i = 0
	_draft_done = 0
	_build_draft_ui()

## 选人完成 → 创建对局
func _start_battle() -> void:
	_phase = "play"
	_battle = _BAT.new(_red_ids, _blue_ids)
	_battle.human_mode = true
	if Global.net_mode:
		_battle.set_rng_seed(Global.net_seed)
		_battle.human_teams = [0, 1]   # 双侧 wait：操作全部走指令流镜像
		_battle.human_team = 0
	elif Global.offline_type == "hotseat":
		_battle.human_teams = [0, 1]
		_battle.human_team = 0
	else:
		_battle.human_team = 0
		var diff := str(Global.difficulty)
		if diff == "normal" or diff == "hard":
			_battle.ai_level = diff
			_battle.side_levels = {1: diff}
			if diff == "hard":
				_battle.ai_backend = str(Global.ai_backend)
	_focus = null
	_cast_slot = 0
	_multi_targets = []
	if Global.net_mode:
		_title.text = "联机 4V4 · 你执%s" % ("红方" if _my_team() == 0 else "蓝方")
	else:
		_title.text = "4V4 · 红方（你）vs 蓝方（AI）" if Global.offline_type != "hotseat" else "4V4 · 热座"
	_skip_btn.visible = true
	_over_lab.text = ""
	_step()

## 结算到“轮到人类”或结束
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
		_over_lab.text = "对局结束：%s" % str(st["over"])
		_skip_btn.visible = false
		_hint.text = "胜负已分，可返回菜单再来"
	elif st.has("wait"):
		if _battle.round != _sfx_round:
			_sfx_round = _battle.round
			Sfx.play("alarm")
		var cur: BattleUnit = _battle.current()
		if Global.net_mode and cur != null and cur.team != _my_team():
			_hint.text = "等待对方行动…"
		elif cur != null:
			var side := "红方" if cur.team == 0 else "蓝方"
			if Global.offline_type == "hotseat":
				_hint.text = "轮到 %s【%s】：点己方棋走位 / 点技能行动（%s 玩家操作）" % [side, cur.name, side]
			else:
				_hint.text = "轮到 %s【%s】：点己方棋走位 / 点技能行动" % [side, cur.name]
		_round_lab.text = "第 %d 回合 · ★红 %d : %d 蓝★" % [_battle.round, int(_battle.scores.get(0, 0)), int(_battle.scores.get(1, 0))]
	else:
		_hint.text = ""
	_skill_desc.text = ""
	_refresh_board()
	_refresh_ui()

## 本方操作 → 本地执行 + 成功才广播（与 duel.gd 同构）
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
	var r: String = _battle.human_cast(slot, enemy, landing, _multi_targets)
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

## 远端指令 → 镜像重放
func _on_net_cmd(cmd: Dictionary) -> void:
	if not Global.net_mode:
		return
	var op := str(cmd.get("op", ""))
	if op == "pick":
		_on_net_pick(int(cmd.get("side", -1)), str(cmd.get("hero", "")), int(cmd.get("seq", -1)))
		return
	if _battle == null or _phase != "play":
		return
	# 发送方校验：对方只能驱动对方的单位
	var actor_idx := int(cmd.get("actor", -1))
	if actor_idx >= 0 and actor_idx < _battle.units.size():
		if _battle.units[actor_idx].team == _my_team():
			return
	var r: String = _NP.apply_cmd(_battle, cmd)
	if r.begins_with("!REPLAY_"):
		_phase = "over"
		_over_lab.text = "对局中断：与对方状态不同步（%s）" % r
		return
	match op:
		"move":
			_refresh_board()
			_hint.text = "对方已移动"
		"cast":
			_step()
		"done":
			_step()

## 对方选秀 pick 到达（seq 校验防错位）
func _on_net_pick(side: int, hero_id: String, seq: int) -> void:
	if hero_id == "" or (side != 0 and side != 1):
		return
	if side == _my_team():
		return   # 对方无权替我方选
	var cur := _red_ids.size() + _blue_ids.size()
	if seq >= 0 and seq != cur:
		return   # 错位：丢弃（理论上 reliable 有序不会发生）
	if hero_id in _red_ids or hero_id in _blue_ids:
		return
	_add_draft_pick(side, hero_id)
	_advance_draft()

func _on_net_opening(pkg: Dictionary) -> void:
	if not Global.net_mode or _phase != "select":
		return
	Global.net_seed = int(pkg.get("seed", 0))
	_red_ids = []
	_blue_ids = []
	for x in (pkg.get("red", []) as Array):
		_red_ids.append(str(x))
	for x in (pkg.get("blue", []) as Array):
		_blue_ids.append(str(x))
	if _draft_overlay != null and is_instance_valid(_draft_overlay):
		_draft_overlay.queue_free()
		_draft_overlay = null
	_start_battle()

func _on_net_left() -> void:
	if Global.net_mode and _phase == "play":
		_phase = "over"
		_over_lab.text = "对方断线，判你获胜！"

func _on_skip() -> void:
	if not _can_input():
		return
	_op_done()
	_hint.text = "等待对方行动…" if Global.net_mode else "已结束行动…"
	_step()

## 打开局内设置（含 Bug 上报）
func _open_settings() -> void:
	if _settings == null or not is_instance_valid(_settings):
		_settings = SettingsLayer.new()
		add_child(_settings)
		_settings.visible = false
	var mode := "4V4"
	if Global.offline_type == "hotseat":
		mode += " · 热座"
	else:
		mode += " · 离线 PVE"
	_settings.ctx = {
		"mode": mode,
		"round": _battle.round if _battle != null else 0,
		"logs": _battle.log if _battle != null else [],
	}
	_settings.open_popup()

## ================= 棋盘交互 =================
## 右键：有棋子 → 弹信息浮层（不限阵营/回合）；空格 → 取消选择（原右键行为）
func _on_right_click(cell: Vector2i) -> void:
	if _battle == null or _phase != "play":
		return
	var u := _unit_at(cell) if cell.x >= 0 else null
	if u != null and u.alive:
		add_child(UnitInfoPopup.make(u))
	else:
		_focus = null
		_cast_slot = 0
		_multi_targets = []
		_hint.text = "已取消选择"
		_refresh_board()
		_refresh_ui()

func _on_cell(cell: Vector2i) -> void:
	if not _can_input():
		return
	if cell.x < 0:
		_focus = null
		_cast_slot = 0
		_multi_targets = []
		_hint.text = "已取消选择"
		_refresh_board()
		_refresh_ui()
		return
	_handle_cell(cell)

func _handle_cell(cell: Vector2i) -> void:
	var me := _battle.current()
	if me == null:
		return
	# 技能选目标阶段
	if _cast_slot >= 1:
		var slot := _cast_slot
		if _battle.is_dash(me, slot):
			if _battle.is_charge(me, slot):
				# 冲刺：点任意格 = 朝该方向冲（8 方向），点敌人 = 直接冲过去。
				# 旧版只认敌人格，点其它格一律"冲刺需点敌人，已取消"，等于没法选方向。
				if cell == me.cell:
					_cast_slot = 0
					_multi_targets = []
					_hint.text = "方向无效（不能冲向自己所在格），已取消"
				else:
					var tt := _unit_at(cell)
					var aim_enemy: BattleUnit = tt if (tt != null and tt.team != me.team) else null
					var rc: String = _op_cast(slot, aim_enemy, cell)
					if rc.begins_with("!"):
						# 失败不得推进：旧版无条件 _step() 会吞掉本回合行动、甚至提前开新回合
						_hint.text = rc
					else:
						_hint.text = "冲刺完毕"
						_step()
			else:
				# 跃迁：点黄色落点格
				var dd := _battle.dash_dist_of(me, slot)
				if cell in _battle.landable_cells(me, dd):
					var rj: String = _op_cast(slot, null, cell)
					if rj.begins_with("!"):
						_hint.text = rj
					else:
						_hint.text = "位移完成"
						_step()
				else:
					_cast_slot = 0
					_multi_targets = []
					_hint.text = "落点无效（需空格且在位移距离内），已取消"
			return
		var t := _unit_at(cell)
		if t != null and t.team != me.team and t in _battle.targets_in_range(me, slot):
			var mx := _battle.max_targets_of(me, slot)
			if mx > 1:
				# 多目标：逐个点选累积，选满即自动施放
				if not _multi_targets.has(t):
					_multi_targets.append(t)
				if _multi_targets.size() < mx:
					_hint.text = "已选 %d/%d 个目标，继续点选（也可直接结束回合）" % [_multi_targets.size(), mx]
					_refresh_board()
					_refresh_ui()
					return
			var r: String = _op_cast(slot, t)
			if r.begins_with("!"):
				_hint.text = r
			else:
				_hint.text = "已行动"
				_step()
		else:
			_cast_slot = 0
			_multi_targets = []
			_hint.text = "目标无效（不在射程内），已取消技能选择"
		return
	# 常规：聚焦 / 移动 / 查看敌情
	var unit := _unit_at(cell)
	if unit != null and unit.team == me.team and unit.alive:
		_focus = unit
		_hint.text = "已选中 %s：点绿色格移动，或点右侧技能" % unit.name
	elif _focus != null and _battle.waiting() and cell in _battle.move_cells_of(_focus):
		var r2: String = _op_move(cell)
		if r2.begins_with("!"):
			_hint.text = r2
		else:
			_hint.text = "已移动。可点技能、再移动本队其它棋，或结束行动"
	elif unit != null and unit.team != me.team:
		_hint.text = "敌方 %s（HP %.2f/%.2f）盾%.2f 甲%.2f" % [unit.name, unit.hp, unit.max_hp, unit.shield, unit.armor]
	else:
		_hint.text = "（空格）点自己的棋子开始行动"
	_refresh_board()
	_refresh_ui()

func _unit_at(cell: Vector2i) -> BattleUnit:
	if _battle == null:
		return null
	for u in _battle.units:
		if u.cell == cell:
			return u
	return null

## ================= 技能按钮 =================
func _on_skill(i: int) -> void:
	if not _can_input():
		return
	var me := _battle.current()
	if me == null:
		return
	if _battle.is_dash(me, i):
		_cast_slot = i
		if _battle.is_charge(me, i):
			_hint.text = "冲刺：点一个黄色格子作为冲刺方向（8 方向均可），或点敌人直接冲过去"
		else:
			_hint.text = "位移：点黄色落点格（落地自动进入射程判定）"
		_refresh_board()
		_refresh_ui()
		return
	if _battle.self_skill(me, i):
		var r: String = _op_cast(i)
		if r.begins_with("!"):
			_hint.text = r
		else:
			_hint.text = "已行动"
			_step()
	else:
		var ts: Array = _battle.targets_in_range(me, i)
		var mx := _battle.max_targets_of(me, i)
		_multi_targets = []
		if ts.is_empty():
			_hint.text = "射程内没有敌人"
		elif ts.size() == 1 or mx <= 1:
			var r2: String = _op_cast(i, ts[0])
			if r2.begins_with("!"):
				_hint.text = r2
			else:
				_hint.text = "已行动"
				_step()
		else:
			# 多目标技（如追猎流星飞弹 2 个）：进入点选模式，选满自动施放
			_cast_slot = i
			_hint.text = "点击橙色高亮敌人（可选 %d 个，已选 0）" % mx
	_refresh_board()
	_refresh_ui()

## ================= 棋盘刷新 =================
func _refresh_board() -> void:
	if _board == null or _battle == null:
		return
	var ud: Array = []
	for u in _battle.units:
		if not u.alive:
			continue
		ud.append({
			"cell": u.cell, "name": u.name, "team": u.team,
			"hp": u.hp, "max_hp": u.max_hp,
			"statuses": u.status_icons(),
			"selected": (u == _focus) or (u == _battle.current()),
		})
	_board.units = ud
	_board.stars = []
	for st in _battle.stars:
		_board.stars.append({"cell": (st as Dictionary)["pos"], "big": bool((st as Dictionary).get("big", false))})
	_board.move_cells = []
	_board.land_cells = []
	_board.target_cells = []
	if _phase == "play" and _battle.waiting():
		var me := _battle.current()
		if me != null:
			# 聚焦棋的可移动格（且本轮未移动时）
			if _cast_slot == 0 and _focus != null and _focus.alive and not _battle.human_moved() and _focus == me:
				_board.move_cells = _battle.move_cells_of(_focus)
			# 技能选目标/落点高亮
			if _cast_slot >= 1:
				if _battle.is_dash(me, _cast_slot):
					if _battle.is_charge(me, _cast_slot):
						_board.land_cells = _battle.charge_aim_cells(me, _battle.dash_dist_of(me, _cast_slot))
					else:
						_board.land_cells = _battle.landable_cells(me, _battle.dash_dist_of(me, _cast_slot))
				else:
					var tc: Array = _battle.targets_in_range(me, _cast_slot)
					for t in tc:
						_board.target_cells.append((t as BattleUnit).cell)
	_board.queue_redraw()

## ================= 右侧信息栏刷新 =================
func _refresh_ui() -> void:
	if _battle == null:
		return
	var shown: BattleUnit = _battle.current()
	if shown == null:
		for u in _battle.units:
			if u.alive:
				shown = u
				break
	if shown == null:
		return
	var side := "红方" if shown.team == 0 else "蓝方"
	var who := "（你）" if (_battle.human_teams.has(shown.team)) else ""
	if _battle.human_mode and not _battle.human_teams.is_empty():
		who = "（玩家）" if _battle.human_teams.has(shown.team) else "（AI）"
	_action_lab.text = "行动 · %s %s" % [side, who]
	_name_lab.text = "%s · %s" % [shown.name, side]
	_update_bar(_hp_bar, shown.hp, shown.max_hp)
	# 理智系英雄（如辛克莱）：能量栏整体换成理智栏
	if shown.has_sanity:
		_update_bar(_en_bar, clampf(shown.sanity, 0.0, shown.sanity_cap), shown.sanity_cap,
			"理智 %.2f / %.2f" % [shown.sanity, shown.sanity_cap], "理智")
	elif shown.max_energy < 0:
		_update_bar(_en_bar, shown.energy, maxf(shown.energy, 1.0), "%.2f / ∞" % shown.energy, "能量")
	else:
		_update_bar(_en_bar, shown.energy, shown.max_energy)
	_sub_lab.text = "盾 %.2f · 甲 %.2f · 速 %d%s" % [shown.shield, shown.armor, shown.effective_speed(), shown.to_status_summary()]
	_state_lab.text = _state_bbcode(shown)
	# 技能按钮（仅当前单位可操作时）
	for nb in _skill_buttons:
		if nb != null and is_instance_valid(nb):
			nb.queue_free()
	_skill_buttons.clear()
	var me := _battle.current() if (_phase == "play" and _battle.waiting() and _battle.current() != null) else null
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
			why = "被掠夺"
		elif sk.exhausted():
			# 整局限次技（如追猎流星飞弹 per_game=1）用尽后必须置灰：
			# 旧版漏判，按钮看着还能点，点了却没有任何效果
			why = "本局已用尽"
		elif me.energy < sk.energy_cost:
			why = "能量不足"
		elif sk.current_cd > 0:
			why = "冷却%d" % sk.current_cd
		elif me.has_flag("no_skill") or (i == 4 and me.has_flag("no_ult")) or me.has_flag("no_damage"):
			why = "禁用"
		elif not _battle.self_skill(me, i) and not _battle.is_dash(me, i) and _battle.targets_in_range(me, i).is_empty():
			why = "射程内无目标"
		nb.text = sk.display_name
		var tip := "[%s] 耗能 %d" % [sk.display_name, sk.energy_cost]
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

## ================= 战斗日志 =================
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
	var lines: Array = _battle.log
	var head := maxi(0, lines.size() - 120)
	var out := ""
	for j in range(head, lines.size()):
		var s: String = lines[j]
		if s.begins_with("——") or s.begins_with("=="):
			out += "[color=#ffd95a]%s[/color]\n" % s
		else:
			out += s + "\n"
	_log.text = out
	if lines.size() > 0:
		_log.scroll_to_line(_log.get_line_count())

## ================= 4V4 选人（蛇形） =================
func _draft_turn() -> Dictionary:
	if _draft_i < _draft_seq.size():
		return _draft_seq[_draft_i]
	return {}

func _draft_pool() -> Array:
	var used := {}
	for id in _red_ids:
		used[id] = true
	for id in _blue_ids:
		used[id] = true
	var out: Array = []
	for id in _HD.ALL:
		if not HeroDefs.is_pickable(str(id)):
			continue
		if not used.has(str(id)):
			out.append(str(id))
	return out

func _side_name(side: int) -> String:
	return "红方" if side == 0 else "蓝方"

func _build_draft_ui() -> void:
	if _draft_overlay != null and is_instance_valid(_draft_overlay):
		_draft_overlay.queue_free()
	var ov := Panel.new()
	ov.name = "DraftOverlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.10, 0.12, 0.19, 0.97)
	ov.add_theme_stylebox_override("panel", osb)
	add_child(ov)
	_draft_overlay = ov
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 26)
	ov.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var ti := Label.new()
	ti.text = "4V4 · 蛇形选人"
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_font_size_override("font_size", 30)
	ti.add_theme_color_override("font_color", COL_GOLD)
	v.add_child(ti)
	_draft_title = Label.new()
	_draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draft_title.add_theme_font_size_override("font_size", 17)
	_draft_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	v.add_child(_draft_title)
	_draft_sub = Label.new()
	_draft_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draft_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_draft_sub.add_theme_font_size_override("font_size", 13)
	_draft_sub.add_theme_color_override("font_color", Color(0.66, 0.71, 0.79))
	v.add_child(_draft_sub)
	# 红蓝已选摘要
	var picked := HBoxContainer.new()
	picked.add_theme_constant_override("separation", 24)
	picked.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(picked)
	_red_lab = Label.new()
	_red_lab.custom_minimum_size = Vector2(340, 0)
	_red_lab.add_theme_font_size_override("font_size", 15)
	_red_lab.add_theme_color_override("font_color", COL_RED)
	picked.add_child(_red_lab)
	_blue_lab = Label.new()
	_blue_lab.custom_minimum_size = Vector2(340, 0)
	_blue_lab.add_theme_font_size_override("font_size", 15)
	_blue_lab.add_theme_color_override("font_color", COL_BLUE)
	picked.add_child(_blue_lab)
	# 英雄池
	var pool_panel := Panel.new()
	var pps := StyleBoxFlat.new()
	pps.bg_color = Color(0.06, 0.08, 0.13, 0.9)
	pps.set_corner_radius_all(12)
	pool_panel.add_theme_stylebox_override("panel", pps)
	pool_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(pool_panel)
	var pm := MarginContainer.new()
	pm.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pm.add_theme_constant_override(k, 14)
	pool_panel.add_child(pm)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pm.add_child(sc)
	_draft_grid = GridContainer.new()
	_draft_grid.columns = 4
	_draft_grid.add_theme_constant_override("h_separation", 10)
	_draft_grid.add_theme_constant_override("v_separation", 10)
	_draft_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_draft_grid)
	for id in _draft_pool():
		_draft_grid.add_child(_draft_hero_button(id))
	# 底部按钮
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 20)
	v.add_child(bottom)
	var rand_btn := Button.new()
	rand_btn.text = "🎲 一键随机配队"
	rand_btn.pressed.connect(_random_all)
	if Global.net_mode:
		rand_btn.visible = false   # 联机选秀由双方轮流点选
	_style_btn(rand_btn)
	bottom.add_child(rand_btn)
	var cancel := Button.new()
	cancel.text = "‹ 返回菜单"
	cancel.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainUI.tscn"))
	_style_btn(cancel)
	bottom.add_child(cancel)
	_draft_refresh()

func _draft_hero_button(id: String) -> Button:
	var def: Dictionary = _HD.ALL[id]
	var nb := Button.new()
	nb.text = "%s\n〔%s〕" % [def.name, def.element]
	nb.custom_minimum_size = Vector2(180, 58)
	nb.add_theme_font_size_override("font_size", 15)
	nb.pressed.connect(func(): _pick_draft_hero(id))
	nb.set_meta("hid", id)
	return nb

## 点击池中英雄：仅允许当前轮次的“人类方可操作”时生效
func _pick_draft_hero(id: String) -> void:
	if _phase != "select" or _draft_overlay == null or not is_instance_valid(_draft_overlay):
		return
	var turn: Dictionary = _draft_turn()
	if turn.is_empty():
		return
	var side := int(turn.get("side", -1))
	if Global.net_mode:
		if side != _my_team():
			return   # 联机：非本方轮次不接收点击（由对方 pick 指令驱动）
	elif side == 1 and Global.offline_type != "hotseat":
		return   # PVE：AI 的轮次不接收点击
	if side < 0 or _draft_done >= int(turn.get("n", 0)):
		return
	if _red_ids.size() + _blue_ids.size() >= 8:
		return
	if id in _red_ids or id in _blue_ids:
		return
	_add_draft_pick(side, id)
	if Global.net_mode:
		Net.send_cmd(_NP.make_pick(side, id, _red_ids.size() + _blue_ids.size() - 1))
	_advance_draft()

func _add_draft_pick(side: int, id: String) -> void:
	if side == 0:
		if _red_ids.size() < 4:
			_red_ids.append(id)
	else:
		if _blue_ids.size() < 4:
			_blue_ids.append(id)
	_draft_done += 1

## 轮次推进：AI（PVE 蓝方）轮次自动补选，直到轮到人类操作或选人完成
func _advance_draft() -> void:
	while _phase == "select":
		var turn: Dictionary = _draft_turn()
		if turn.is_empty():
			_finish_draft()
			return
		var n := int(turn.get("n", 0))
		# 当前轮选满 → 进入下一轮
		if _draft_done >= n:
			_draft_i += 1
			_draft_done = 0
			continue
		# 联机：双方都是人类，轮到谁谁点（对方通过 pick 指令驱动）
		if Global.net_mode:
			break
		# PVE 蓝方轮次：AI 自动补齐
		if int(turn.get("side", -1)) == 1 and Global.offline_type != "hotseat":
			var pool := _draft_pool()
			pool.shuffle()
			var pick_n := mini(n - _draft_done, 4 - _blue_ids.size())
			for i in range(pick_n):
				if pool.is_empty():
					break
				_add_draft_pick(1, str(pool.pop_back()))
			continue
		break   # 轮到人类操作，停下等点击
	if _draft_i >= _draft_seq.size():
		_finish_draft()
		return
	_draft_refresh()

func _finish_draft() -> void:
	if _draft_overlay != null and is_instance_valid(_draft_overlay):
		_draft_overlay.queue_free()
	_draft_overlay = null
	if Global.net_mode:
		if Global.net_is_host:
			Net.send_opening({"seed": Global.net_seed, "red": _red_ids, "blue": _blue_ids})
			_start_battle()
		# joiner 等 opening 开局包
		return
	_start_battle()

## 一键随机：双方都由系统从池中随机各 4
func _random_all() -> void:
	var pool := _draft_pool()
	pool.shuffle()
	var reds: Array = []
	var blues: Array = []
	for i in range(4):
		if pool.is_empty():
			break
		reds.append(str(pool.pop_back()))
		if pool.is_empty():
			break
		blues.append(str(pool.pop_back()))
	if reds.size() == 4 and blues.size() == 4:
		_red_ids = reds
		_blue_ids = blues
		_finish_draft()

func _draft_refresh() -> void:
	if _draft_overlay == null or not is_instance_valid(_draft_overlay):
		return
	# 摘要
	var red_txt := "红方："
	var blue_txt := "蓝方："
	for i in range(4):
		if i < _red_ids.size():
			red_txt += " " + str(_HD.ALL[_red_ids[i]].name)
		else:
			red_txt += " ［待选］"
		if i < _blue_ids.size():
			blue_txt += " " + str(_HD.ALL[_blue_ids[i]].name)
		else:
			blue_txt += " ［待选］"
	red_txt += "（%d/4）" % _red_ids.size()
	blue_txt += "（%d/4）" % _blue_ids.size()
	_red_lab.text = red_txt
	_blue_lab.text = blue_txt
	# 标题与副标题
	var turn: Dictionary = _draft_turn()
	if turn.is_empty():
		_draft_title.text = "选人完成，正在开局…"
		_draft_sub.text = ""
	else:
		var side := int(turn.get("side", 0))
		var n := int(turn.get("n", 0))
		var done := mini(_draft_done, n)
		var who := _side_name(side)
		var ai_tip := ""
		if side == 1 and Global.offline_type != "hotseat":
			ai_tip = "（AI 自动选人）"
		else:
			ai_tip = "（%s 操作）" % ("你" if side == 0 or Global.offline_type == "hotseat" else "玩家2")
		_draft_title.text = "轮到 %s选 %d 个英雄 · 第 %d/%d 步%s" % [who, n, _draft_i + 1, _draft_seq.size(), ai_tip]
		_draft_sub.text = "已选 %d/%d · 规则：红 1 → 蓝 2 → 红 2 → 蓝 2 → 红 1 · 英雄不可重复" % [done, n]
	# 池按钮可用性刷新
	var can_pick := false
	if not turn.is_empty():
		var side := int(turn.get("side", -1))
		can_pick = _phase == "select" and _draft_done < int(turn.get("n", 0)) \
				and not (side == 1 and Global.offline_type != "hotseat")
	for nb in _draft_grid.get_children():
		var b := nb as Button
		if b == null:
			continue
		var hid := str(b.get_meta("hid"))
		var used := hid in _red_ids or hid in _blue_ids
		b.disabled = used or not can_pick
		var n2 := b.get_theme_stylebox("normal").duplicate()
		n2.bg_color = Color(0.16, 0.19, 0.29) if not (used or not can_pick) else Color(0.10, 0.11, 0.16)
		b.add_theme_stylebox_override("normal", n2)


# ---------- 无头联机端到端测试钩子（4V4）----------
## godot --headless --path . res://scenes/TeamDuel.tscn ++ autonet4=host|join
func _autonet_detect() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("autonet4="):
			_autonet_role = a.trim_prefix("autonet4=")
	if _autonet_role != "host" and _autonet_role != "join":
		_autonet_role = ""
		return
	Global.net_mode = true
	Global.net_is_host = (_autonet_role == "host")
	var err: int = ERR_UNAVAILABLE
	if Global.net_is_host:
		Global.net_seed = 888888
		err = Net.host_game(Global.net_port)
	else:
		err = Net.join_game("127.0.0.1", Global.net_port)
	print("AUTONET4[%s]: net ready err=%d" % [_autonet_role, err])

func _autonet_run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		if Net.multiplayer_peer_active():
			break
	print("AUTONET4[%s]: peer connected" % _autonet_role)
	# 选秀自动化：轮到本方就选池中第一个可用英雄
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and _phase == "select":
		await get_tree().process_frame
		var turn := _draft_turn()
		if turn.is_empty():
			break
		if int(turn.get("side", -1)) == _my_team() and _draft_done < int(turn.get("n", 0)):
			var pool := _draft_pool()
			var pick_id := ""
			for pid in pool:
				if not (pid in _red_ids) and not (pid in _blue_ids):
					pick_id = str(pid)
					break
			if pick_id != "":
				_pick_draft_hero(pick_id)
	if _battle == null:
		print("AUTONET4[%s]: FAIL 对局未建立（选秀/opening 超时）" % _autonet_role)
		get_tree().quit(1)
		return
	print("AUTONET4[%s]: 开局 OK red=%s blue=%s seed=%d" % [_autonet_role, str(_red_ids), str(_blue_ids), Global.net_seed])
	# 操作：本方 2 次行动
	var acts := 0
	t0 = Time.get_ticks_msec()
	var my_t := _my_team()
	while acts < 2 and Time.get_ticks_msec() - t0 < 25000 and _battle != null and _battle.winner == "":
		await get_tree().process_frame
		if _battle.waiting() and _battle.current() != null and _battle.current().team == my_t:
			var me = _battle.current()
			var cells: Array = _battle.move_cells_of(me)
			if cells.size() > 0 and not _battle.human_moved():
				_op_move(cells[0])
			else:
				_op_done()
				_step()
				acts += 1
	await get_tree().create_timer(1.0).timeout
	var log_len: int = _battle.log.size() if _battle != null else -1
	var rd := _battle.round if _battle != null else -1
	var cells_txt := ""
	if _battle != null:
		for u in _battle.units:
			cells_txt += str(u.cell) + ","
	print("AUTONET4-SUMMARY[%s] log=%d round=%d cells=%s" % [_autonet_role, log_len, rd, cells_txt])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
