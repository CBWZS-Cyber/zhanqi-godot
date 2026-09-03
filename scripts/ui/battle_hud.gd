extends Control
## 局内对战 · 右侧信息栏 v4（双人/多人通用）：
##   1V1：上方「先手方」+ 下方「后手方」两块棋子状态；技能只显示当前操作方
##   4V4：只显示「轮到行动」的一方
##   底部剩余空间：战斗日志（自动伸缩）
## 接入玩法后调用：
##   show_1v1(先手cfg, 后手cfg) / show_4v4(行动cfg)
##   cfg = { side:"先手方", color:Color, name:"剑士甲",
##           hp:120, hp_max:120, energy:80, energy_max:80, active:true, skills:[{name,desc}] }
##   add_log("文本")：追加战斗日志

const BASE := Vector2(1280, 720)
const SIDE := 300.0        # 右侧栏基准宽（与 board.gd SIDE_PANEL_W 一致）

var _f := 1.0
var _card: PanelContainer
var _panel_style: StyleBoxFlat
var _arena: VBoxContainer
var _scroll: ScrollContainer
var _log_box: VBoxContainer
var _tip: PanelContainer
var _tip_name: Label
var _tip_desc: Label
var _confs: Array[Dictionary] = []   # 容器缩放配置

func _ready() -> void:
	_build()
	run_demo("1v1")
	_refit()

func _process(_delta: float) -> void:
	_fit()              # 每帧无条件重排：缩放/内容变化即时生效，杜绝错拍
	if _tip.visible:
		_place_tip()

## ================= 构建 =================
func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_card = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.10, 0.12, 0.19, 0.94)
	_panel_style.set_corner_radius_all(16)
	_card.add_theme_stylebox_override("panel", _panel_style)
	add_child(_card)

	var vb := _box(VBoxContainer.new(), 10, 20, 20, 16, 18)
	_card.add_child(vb)

	_arena = _box(VBoxContainer.new(), 14, 0, 0, 4, 0)
	vb.add_child(_arena)

	# 战斗日志
	var log_title := _label("战斗日志", 16, Color(0.941, 0.780, 0.369))
	log_title.set_meta("fz", 16)
	log_title.add_theme_constant_override("margin_top", 8)
	vb.add_child(_sep())
	vb.add_child(log_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 只纵向滚动
	_scroll = scroll
	vb.add_child(scroll)
	_log_box = _box(VBoxContainer.new(), 6, 2, 2, 2, 2)
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL               # 撑满宽度，避免自动换行按“单字宽”排成竖排
	scroll.add_child(_log_box)

	# 悬停说明浮窗
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.06, 0.08, 0.14, 0.97)
	tip_style.border_color = Color(0.941, 0.780, 0.369, 0.55)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(8)
	_tip.add_theme_stylebox_override("panel", tip_style)
	var tip_vb := _box(VBoxContainer.new(), 4, 12, 12, 7, 9)
	_tip.add_child(tip_vb)
	_tip_name = _label("", 15, Color(0.941, 0.780, 0.369))
	tip_vb.add_child(_tip_name)
	_tip_desc = _label("", 13, Color(0.86, 0.90, 0.96))
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_vb.add_child(_tip_desc)
	_tip.visible = false
	add_child(_tip)

func _box(c: Container, sep: int, ml: int, mr: int, mt: int, mb: int) -> Container:
	c.add_theme_constant_override("separation", sep)
	c.add_theme_constant_override("margin_left", ml)
	c.add_theme_constant_override("margin_right", mr)
	c.add_theme_constant_override("margin_top", mt)
	c.add_theme_constant_override("margin_bottom", mb)
	_confs.append({"box": c, "sep": float(sep), "ml": float(ml), "mr": float(mr), "mt": float(mt), "mb": float(mb)})
	return c

## ================= 对局显示 =================
func show_1v1(a: Dictionary, b: Dictionary) -> void:
	_build_arena([a, b])

func show_4v4(cfg: Dictionary) -> void:
	_build_arena([cfg])

func _build_arena(cfgs: Array) -> void:
	for c in _arena.get_children():
		_arena.remove_child(c)
		c.queue_free()
	for i in range(cfgs.size()):
		if i > 0:
			_arena.add_child(_sep())
		_arena.add_child(_make_side(cfgs[i]))
	_refit()

func _make_side(cfg: Dictionary) -> VBoxContainer:
	var vb := _box(VBoxContainer.new(), 8, 0, 0, 0, 0)
	var side := str(cfg.get("side", "行动"))
	var color: Color = cfg.get("color", Color(0.941, 0.780, 0.369))
	var active: bool = bool(cfg.get("active", false))

	var role := _label(side, 15, color)
	role.set_meta("fz", 15)
	role.text += ("  ◀ 行动" if active else "")
	vb.add_child(role)

	var nm := _label(str(cfg.get("name", "—")), 27, Color(0.93, 0.96, 0.99))
	nm.set_meta("fz", 27)
	vb.add_child(nm)

	vb.add_child(_bar_box("生命", Color(0.86, 0.26, 0.28), int(cfg.get("hp", 0)), int(cfg.get("hp_max", 1))))
	vb.add_child(_bar_box("能量", Color(0.25, 0.55, 0.95), int(cfg.get("energy", 0)), int(cfg.get("energy_max", 1))))

	# 技能：行动方或 cfg 显式带技能时显示（1V1 双方都可给技能）
	if active or bool(cfg.get("show_skills", false)):
		var skills: Array = cfg.get("skills", [])
		if skills.size() > 0:
			vb.add_child(_sep())
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			_confs.append({"box": grid, "hs": 8.0, "vs": 8.0})
			for s in skills:
				grid.add_child(_make_skill_button(s))
			vb.add_child(grid)
	return vb

func _bar_box(tag: String, fill_col: Color, value: int, max_value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_meta("min_y", 48.0)
	row.add_child(_label_min(tag, 18, 42, Color(0.84, 0.87, 0.92)))

	var bar := ProgressBar.new()
	bar.set_meta("min_y", 32.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = max_value if max_value > 0 else 1
	bar.value = clampi(value, 0, max_value)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("fill_col", fill_col)
	row.add_child(bar)
	_style_bar(bar)

	var num := _label("%d / %d" % [value, max_value], 16, Color(1, 1, 1))
	num.set_meta("fz", 16.0)
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	bar.add_child(num)
	return row

func _style_bar(bar: ProgressBar) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = bar.get_meta("fill_col")
	fill.set_corner_radius_all(5)
	var bgst := StyleBoxFlat.new()
	bgst.bg_color = Color(0.04, 0.05, 0.09, 0.9)
	bgst.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bgst)

## ================= 战斗日志 =================
func add_log(text: String) -> void:
	var l := _label(text, 13, Color(0.72, 0.77, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_box.add_child(l)
	# 顶掉过旧的行
	while _log_box.get_child_count() > 60:
		var old := _log_box.get_child(0)
		_log_box.remove_child(old)
		old.queue_free()
	# 自动滚到底部，始终显示最新一条
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = maxi(0, int(_log_box.size.y))

## ================= 部件工具 =================
func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.modulate = Color(1, 1, 1, 0.12)
	return s

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _label_min(text: String, size: int, min_x: float, color: Color) -> Label:
	var l := _label(text, size, color)
	l.set_meta("fz", float(size))
	l.set_meta("min_x", min_x)
	return l

func _make_skill_button(skill) -> Button:
	var sname := ""
	var sdesc := ""
	if skill is Dictionary:
		sname = str(skill.get("name", ""))
		sdesc = str(skill.get("desc", ""))
	else:
		sname = str(skill)
	var b := Button.new()
	b.text = sname
	b.set_meta("fz", 16.0)
	b.set_meta("min_y", 40.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.19, 0.29)
	normal.border_color = Color(0.40, 0.36, 0.26)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.23, 0.27, 0.42)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.12, 0.15, 0.24)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(_on_skill_pressed.bind(sname))
	b.mouse_entered.connect(_on_skill_hover.bind(sname, sdesc))
	b.mouse_exited.connect(_on_skill_unhover)
	return b

func _on_skill_pressed(skill_name: String) -> void:
	print("[BattleHUD] 释放技能：%s（占位，待接入技能逻辑）" % skill_name)

## ================= 悬停浮窗 =================
func _on_skill_hover(sname: String, sdesc: String) -> void:
	_tip_name.text = sname
	_tip_desc.text = sdesc if sdesc != "" else "（技能详细说明待补充）"
	_fit_tip_width()
	_tip.visible = true
	_place_tip()

func _on_skill_unhover() -> void:
	_tip.visible = false

func _fit_tip_width() -> void:
	if _tip_desc.text == "":
		return
	var fsize := _tip_desc.get_theme_font_size("font_size")
	var font := _tip_desc.get_theme_font("font")
	var text_w := 0.0
	if font != null:
		text_w = font.get_string_size(_tip_desc.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	else:
		text_w = float(_tip_desc.text.length()) * fsize * 0.9
	var w := clampf(text_w + 20.0 * _f, 90.0 * _f, 210.0 * _f)
	_tip_desc.custom_minimum_size.x = w

func _place_tip() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	var m := get_viewport().get_mouse_position()
	var off := Vector2(20, 18) * _f
	var tw := _tip.size.x
	var th := _tip.size.y
	var p := m + off
	if p.x + tw > vp.x - 4:
		p.x = m.x - tw - 16 * _f
	if p.y + th > vp.y - 4:
		p.y = m.y - th - 16 * _f
	p.x = maxf(6, p.x)
	p.y = maxf(6, p.y)
	_tip.position = p

## ================= 演示（由棋盘按对局模式调用） =================
func run_demo(mode: String) -> void:
	_clear_log()
	if mode == "4v4":
		show_4v4({
			"side": "行动 · 红方 3 号", "color": Color(0.95, 0.55, 0.50),
			"name": "炎龙·领主", "hp": 300, "hp_max": 300, "energy": 150, "energy_max": 150,
			"active": true,
			"skills": [
				{"name": "烈焰吐息", "desc": "向前方锥形区域喷吐烈焰，造成范围伤害。"},
				{"name": "龙威震慑", "desc": "发出威压，降低周围敌人命中率。"},
				{"name": "愈合之鳞", "desc": "龙鳞再生，回复自身生命。"}
			]
		})
		add_log("[4V4] 当前轮到红方行动。")
		add_log("[回合] 红方 炎龙·领主 可以移动或使用技能。")
		add_log("[提示] 演示数据 · 接入玩法后自动更新")
	else:
		show_1v1(
			{
				"side": "先手方", "color": Color(0.95, 0.55, 0.50),
				"name": "演示·剑士甲", "hp": 120, "hp_max": 120, "energy": 80, "energy_max": 80,
				"active": true,
				"skills": [
					{"name": "火焰斩", "desc": "挥出烈焰斩击，对单个敌人造成大量火焰伤害，并附加灼烧。"},
					{"name": "寒冰箭", "desc": "凝聚寒冰之箭射出，减速目标并有一定几率冻结。"},
					{"name": "治疗术", "desc": "吟唱圣光，立即回复自身或友军大量生命值。"},
					{"name": "雷鸣", "desc": "召唤天雷轰击目标区域，造成范围雷属性伤害。"}
				]
			},
			{
				"side": "后手方", "color": Color(0.55, 0.75, 0.95),
				"name": "炎龙·领主", "hp": 300, "hp_max": 300, "energy": 150, "energy_max": 150,
				"active": false,
				"show_skills": true,
				"skills": [
					{"name": "龙炎吐息", "desc": "向前方喷吐烈焰，造成范围伤害。"},
					{"name": "龙翼护体", "desc": "振翅防御，本回合受到的伤害减半。"},
					{"name": "蓄力一击", "desc": "蓄力后挥出重击，造成大量物理伤害。"}
				]
			}
		)
		add_log("[开局] 先手方 演示·剑士甲 登场（红方）。")
		add_log("[开局] 后手方 炎龙·领主 登场（蓝方）。")
		add_log("[回合] 先手方行动开始。")
		add_log("[提示] 演示数据 · 接入玩法后自动更新")

func _clear_log() -> void:
	for c in _log_box.get_children():
		c.queue_free()

## ================= 自适应 =================
## 内容动态重建后立即重排（同步执行一次完整缩放）
func _refit() -> void:
	_fit()

func _fit() -> void:
	_apply_scaling()

func _apply_scaling() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	# 信息栏跟随窗口放大：取“较大边”的比例（拉宽或拉高都会变大），并限制上限
	_f = clampf(maxf(vp.x / BASE.x, vp.y / BASE.y), 0.4, 2.4)
	var pad := 12.0 * _f
	var bw := SIDE * _f - pad * 2.0
	var bh := vp.y - pad * 2.0
	_card.size = Vector2(bw, bh)
	_card.position = Vector2(vp.x - pad - bw, pad)

	# 容器间距/边距随窗口
	for cf in _confs:
		var box: Variant = cf.get("box")
		if typeof(box) != TYPE_OBJECT or box == null or not is_instance_valid(box):
			continue
		var boxc: Container = box as Container
		boxc.add_theme_constant_override("separation", int(cf.get("sep", 0.0) * _f))
		if cf.has("hs"):
			boxc.add_theme_constant_override("h_separation", int(cf["hs"] * _f))
			boxc.add_theme_constant_override("v_separation", int(cf["vs"] * _f))
		boxc.add_theme_constant_override("margin_left", int(cf.get("ml", 0.0) * _f))
		boxc.add_theme_constant_override("margin_right", int(cf.get("mr", 0.0) * _f))
		boxc.add_theme_constant_override("margin_top", int(cf.get("mt", 0.0) * _f))
		boxc.add_theme_constant_override("margin_bottom", int(cf.get("mb", 0.0) * _f))

	# 字号/尺寸（meta 标注过的一律按基准值缩放）
	_walk_fonts(self)

	# 浮窗自适应
	_set_font(_tip_name, maxi(8, int(round(15.0 * _f))))
	_set_font(_tip_desc, maxi(8, int(round(13.0 * _f))))
	_fit_tip_width()

func _walk_fonts(n: Node) -> void:
	for ch in n.get_children():
		if not is_instance_valid(ch):
			continue
		if ch is Control:
			var co := ch as Control
			if co.has_meta("fz"):
				_set_font(co, maxi(8, int(round(float(co.get_meta("fz")) * _f))))
			if co.has_meta("min_x"):
				co.custom_minimum_size.x = float(co.get_meta("min_x")) * _f
			if co.has_meta("min_y"):
				co.custom_minimum_size.y = float(co.get_meta("min_y")) * _f
		if ch.get_child_count() > 0:
			_walk_fonts(ch)

func _set_font(c: Control, size: int) -> void:
	if c is Label:
		(c as Label).add_theme_font_size_override("font_size", size)
	elif c is Button:
		(c as Button).add_theme_font_size_override("font_size", size)
