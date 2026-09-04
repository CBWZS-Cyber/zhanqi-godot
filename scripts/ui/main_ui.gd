extends Control
## 游戏总菜单（仅 UI 导航，不含玩法）：
##   开始界面 → 选择模式（联机 / 离线 / 剧情模式）
##     联机 → 1V1 / 4V4
##     离线 → 选难度（简单/普通/困难）→ 1V1 / 4V4
##     剧情模式 → 直接进入（不再选难度）
##   最终选择进入“结果占位”页（玩法后续再接）。
## 居中：卡片显式取内容尺寸，绕自身中心缩放（pivot），
##       position 使卡片中心 = 视口中心 → 引擎布局不参与也能保证居中。
## 自适应：每帧按窗口尺寸算 _scale，放大/全屏时文字按钮等比变大且始终居中。

const BG_COLOR := Color(0.102, 0.125, 0.208)  # 深蓝灰
const BASE := Vector2(1280, 720)               # 设计基准
const BOARD_SCENE := "res://scenes/Board.tscn"

var _bg: ColorRect
var _scale := 1.0
var _panels := {}
var _current := ""
var _config := {}
var _result_label: Label
var _confs: Array[Dictionary] = []   # 各卡片 VBox 间距/边距（随 _scale 重算）

func _ready() -> void:
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	add_child(_bg)

	_build_screen("start", "战棋", 80, true,
		[["开始游戏", Callable(self, "_on_start")],
		 ["退出", Callable(self, "_on_quit")]], "")
	# 图鉴/介绍：横排独立一行（界面下部）
	var start_card: PanelContainer = _panels["start"]
	var clear_sb := StyleBoxFlat.new()
	clear_sb.bg_color = Color(0.145, 0.176, 0.271, 0.0)
	start_card.add_theme_stylebox_override("panel", clear_sb)
	var start_vbox: VBoxContainer = _panels["start"].get_meta("vbox")
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 16)
	for e in [["英雄图鉴", "hero"], ["武器图鉴", "weapon"], ["地形介绍", "terrain"], ["规则介绍", "rules"]]:
		var cb2 := _make_button(e[0], Callable(self, "_open_codex").bind(e[1]))
		cb2.custom_minimum_size = Vector2(190, 48)
		cb2.set_meta("min_x", 190.0)
		cb2.set_meta("min_y", 48.0)
		cb2.set_meta("fz", 17.0)
		cb2.add_theme_font_size_override("font_size", 17)
		crow.add_child(cb2)
	start_vbox.add_child(crow)
	# 目前仅开放：离线 → 简单 → 1V1；其余入口点击弹“暂未开放”
	_build_screen("mode", "选择模式", 44, false,
		[["联机模式", Callable(self, "_on_locked").bind("联机模式")],
		 ["离线模式", Callable(self, "_on_offline")],
		 ["剧情模式", Callable(self, "_on_locked").bind("剧情模式")]], "start")
	_build_screen("online", "联机模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_locked").bind("联机 1V1")],
		 ["4V4", Callable(self, "_on_locked").bind("联机 4V4")]], "mode")
	_build_screen("diff", "离线模式 · 选择难度", 44, false,
		[["简单", Callable(self, "_on_diff").bind("easy")],
		 ["普通", Callable(self, "_on_locked").bind("普通难度")],
		 ["困难", Callable(self, "_on_locked").bind("困难难度")]], "mode")
	_build_screen("offline", "离线模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_battle").bind("offline", "1v1")],
		 ["4V4", Callable(self, "_on_locked").bind("离线 4V4")]], "diff")
	_build_result()

	_show_panel("start")
	get_viewport().size_changed.connect(_fit)
	call_deferred("_fit")

func _process(_delta: float) -> void:
	_fit()

## 每帧：字号/间距/最小尺寸按 _scale 真实重算（不用 Control.scale 放大，避免全屏文字发糊），
## 卡片取最新内容尺寸后绕中心居中。
func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = clampf(min(vp.x / BASE.x, vp.y / BASE.y), 0.5, 2.4)
	_bg.size = vp
	_bg.position = Vector2.ZERO

	# 各卡片 VBox 的间距/边距
	for cf in _confs:
		var box: Variant = cf.get("box")
		if typeof(box) != TYPE_OBJECT or box == null or not is_instance_valid(box):
			continue
		var bc: Container = box as Container
		bc.add_theme_constant_override("separation", int(cf.get("sep", 0.0) * _scale))
		bc.add_theme_constant_override("margin_left", int(cf.get("ml", 0.0) * _scale))
		bc.add_theme_constant_override("margin_right", int(cf.get("mr", 0.0) * _scale))
		bc.add_theme_constant_override("margin_top", int(cf.get("mt", 0.0) * _scale))
		bc.add_theme_constant_override("margin_bottom", int(cf.get("mb", 0.0) * _scale))

	# 可见卡片：真实字号/尺寸 + 居中
	var p: Control = _panels.get(_current)
	if p != null and p.visible:
		_apply_node_sizes(p)
		var m := p.get_combined_minimum_size()
		p.size = m
		p.scale = Vector2.ONE
		p.pivot_offset = Vector2.ZERO
		p.position = vp / 2.0 - m / 2.0

## 递归：把带 meta("fz"/"min_x"/"min_y") 的控件字号/最小尺寸乘 _scale
func _apply_node_sizes(n: Node) -> void:
	for ch in n.get_children():
		if not is_instance_valid(ch):
			continue
		if ch is Control:
			var co := ch as Control
			if co.has_meta("fz"):
				var sz: int = maxi(8, int(round(float(co.get_meta("fz")) * _scale)))
				if ch is Label:
					(co as Label).add_theme_font_size_override("font_size", sz)
				elif ch is Button:
					(co as Button).add_theme_font_size_override("font_size", sz)
			if co.has_meta("min_x"):
				co.custom_minimum_size.x = float(co.get_meta("min_x")) * _scale
			if co.has_meta("min_y"):
				co.custom_minimum_size.y = float(co.get_meta("min_y")) * _scale
		if ch.get_child_count() > 0:
			_apply_node_sizes(ch)

## F11 在 Godot 里默认没绑任何事；这里手动切换真正的全屏/窗口模式
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN

# ---------- 导航 ----------
func _show_panel(name: String) -> void:
	for k in _panels:
		_panels[k].visible = (k == name)
	_current = name
	_fit()

func _on_start() -> void:
	_show_panel("mode")

func _on_online() -> void:
	_config["mode"] = "online"
	_show_panel("online")

func _on_offline() -> void:
	_config["mode"] = "offline"
	_show_panel("diff")

func _on_story() -> void:
	_config = {"mode": "story"}
	_show_result()

func _on_diff(d: String) -> void:
	_config["difficulty"] = d
	_show_panel("offline")

func _on_battle(mode: String, battle: String) -> void:
	_config["mode"] = mode
	_config["battle"] = battle
	_show_result()

func _on_back(to: String) -> void:
	_show_panel(to)

func _on_to_menu() -> void:
	_config = {}
	_show_panel("start")

func _on_quit() -> void:
	get_tree().quit()

func _on_enter_board() -> void:
	var battle: String = _config.get("battle", "")
	Global.battle_mode = battle if battle == "4v4" else "1v1"
	# 1V1 = 可玩对局（选英雄 + 人机操作）；4V4 暂用展示棋盘
	if battle == "1v1":
		get_tree().change_scene_to_file("res://scenes/Duel.tscn")
	else:
		get_tree().change_scene_to_file(BOARD_SCENE)

func _show_result() -> void:
	var mode: String = _config.get("mode", "")
	var diff: String = _config.get("difficulty", "")
	var battle: String = _config.get("battle", "")
	var parts: Array[String] = []
	if mode == "story":
		parts.append("剧情模式")
	else:
		parts.append("联机模式" if mode == "online" else "离线模式")
		if mode == "offline" and diff != "":
			parts.append(_diff_name(diff))
		match battle:
			"1v1":
				parts.append("1V1")
			"4v4":
				parts.append("4V4")
	_result_label.text = " · ".join(parts)
	_show_panel("result")

func _diff_name(d: String) -> String:
	return "简单" if d == "easy" else ("普通" if d == "normal" else "困难")

# ---------- 构建界面 ----------
func _build_screen(key: String, title: String, title_size: int, with_shadow: bool,
		specs: Array, back_to: String) -> void:
	var card := _make_card(title, title_size, with_shadow)
	var vbox: VBoxContainer = card.get_meta("vbox")
	for i in range(specs.size()):
		var entry: Array = specs[i]
		var text: String = entry[0]
		var cb: Callable = entry[1]
		vbox.add_child(_make_button(text, cb))
	if back_to != "":
		vbox.add_child(_make_button("返回", Callable(self, "_on_back").bind(back_to)))
	add_child(card)
	card.visible = false
	_panels[key] = card

func _build_result() -> void:
	var card := _make_card("准备开始", 44, false)
	var vbox: VBoxContainer = card.get_meta("vbox")
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 30)
	_result_label.set_meta("fz", 30.0)
	_result_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96))
	vbox.add_child(_result_label)
	vbox.add_child(_make_button("进入棋盘（占位）", Callable(self, "_on_enter_board")))
	vbox.add_child(_make_button("返回菜单", Callable(self, "_on_to_menu")))
	add_child(card)
	card.visible = false
	_panels["result"] = card

func _make_card(title: String, title_size: int, with_shadow: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.176, 0.271, 0.92)
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style["corner_radius_" + r] = 18
	card.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.add_theme_constant_override("margin_left", 56)
	vbox.add_theme_constant_override("margin_right", 56)
	vbox.add_theme_constant_override("margin_top", 44)
	vbox.add_theme_constant_override("margin_bottom", 44)
	_confs.append({"box": vbox, "sep": 24.0, "ml": 56.0, "mr": 56.0, "mt": 44.0, "mb": 44.0})
	card.add_child(vbox)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", title_size)
	t.set_meta("fz", float(title_size))
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))  # 金色
	if with_shadow:
		t.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.55))
		t.add_theme_constant_override("shadow_offset_x", 3)
		t.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(t)
	card.set_meta("vbox", vbox)
	return card

func _make_button(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.set_meta("min_x", 300.0)
	btn.set_meta("min_y", 60.0)
	btn.set_meta("fz", 24.0)
	btn.custom_minimum_size = Vector2(300, 60)
	btn.add_theme_stylebox_override("normal", _btn_style(Color(0.941, 0.780, 0.369)))
	btn.add_theme_stylebox_override("hover", _btn_style(Color(1.0, 0.88, 0.55)))
	btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.78, 0.62, 0.22)))
	btn.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(cb)
	return btn

func _btn_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s["corner_radius_" + r] = 10
	return s


## ================= 图鉴/介绍（开始界面入口） =================
var _codex_layer: Control = null

func _open_codex(key: String) -> void:
	_close_codex()
	var titles := {"hero": "英雄图鉴", "weapon": "武器图鉴", "terrain": "地形介绍", "rules": "规则介绍"}
	var layer := Panel.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.19, 0.97)
	layer.add_theme_stylebox_override("panel", sb)
	add_child(layer)
	_codex_layer = layer
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 60)
	m.add_theme_constant_override("margin_right", 60)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 30)
	layer.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var title := Label.new()
	title.text = str(titles.get(key, "图鉴"))
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.text = _codex_content(key)
	v.add_child(rt)
	var back := Button.new()
	back.text = "返 回"
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(_close_codex)
	var bc := CenterContainer.new()
	bc.add_child(back)
	v.add_child(bc)

func _close_codex() -> void:
	if _codex_layer != null and is_instance_valid(_codex_layer):
		_codex_layer.queue_free()
	_codex_layer = null

func _codex_content(key: String) -> String:
	if key == "hero":
		return _codex_heroes()
	if key == "terrain":
		return """[color=#ffd95a]基础地形表（标准棋盘 / 剧情地图通用）[/color]
0 空地：无特殊效果
1 障碍（可破坏）：不可通行，可被特定效果摧毁
2 障碍（不可破坏）：不可通行
3 森林：地形效果待定
4 沼泽：地形效果待定
5 水域：地形效果待定
6 雪地：地形效果待定
7 沙漠：地形效果待定
8 山地：地形效果待定
9 冰面：地形效果待定

[color=#ffd95a]当前棋盘[/color]
1V1：3×3 主对局区 + 双方各 1 个出生格
4V4 / 标准：8×8 主对局区 + 左右翼各 4 格"""
	if key == "rules":
		return """[color=#ffd95a]回合结构[/color]
· 每个棋子每回合 = 1 次移动权 + 1 次技能权
· 先移动、后释放技能；两者都可放弃
· 行动顺序按当前速度实时决定，速度变化立即影响后续顺序

[color=#ffd95a]伤害口径[/color]
· 普通伤害：护盾先吸收 → 护甲减免 → 扣生命
· 真伤：只有明确标注「真伤」的伤害才无视盾甲
· 百分比伤害未标真伤的一律按普伤结算

[color=#ffd95a]状态规则[/color]
· 烧伤：速度-10，每回合末受 1 真伤，持续 2 回合，重复施加刷新时长
· 重伤：被攻击时额外受 0.5×层数 真伤，每回合末层数-1
· 流血：行动（移动/施放）时受层数伤害，回合末层数-1
· 眩晕：跳过行动；沉默：无法用技能；魅惑：无法造成伤害

[color=#ffd95a]位移规则[/color]
· 冲刺类（辛克莱审判系）：朝方向逐格冲，遇阻挡停止
· 瞬移类（追猎/诛心/自我毁灭等）：直接跳到距离内任意空格
· 落点必须为空格（无障碍/无棋子）

[color=#ffd95a]胜负[/color]
· 一方棋子全部阵亡即告负
· 特殊：龙王单挑 6 层污染直接斩杀获胜等英雄专属规则"""
	return "[color=#ffd95a]武器图鉴[/color]\n\n武器系统尚在设计中，敬请期待。"

func _codex_heroes() -> String:
	var HD = preload("res://scripts/combat/hero_defs.gd")
	var SE = preload("res://scripts/combat/skill_effects.gd")
	var out := ""
	for id in HD.ALL:
		var d: Dictionary = HD.ALL[id]
		var emax: int = int(d.get("energy_max", int(d.get("energy", 0))))
		var en_txt := "%d/%d" % [int(d.get("energy", 0)), emax] if emax >= 0 else "%d（无上限）" % int(d.get("energy", 0))
		out += "\n[color=#ffd95a]%s〔%s〕[/color]  生命 %d · 能量 %s · 护甲 %d · 速度 %d\n" % [d.name, d.element, d.hp, en_txt, d.armor, d.speed]
		var sk: Dictionary = d.get("skills", {})
		var pid := str(sk.get("passive", ""))
		if pid != "":
			var pm: Dictionary = SE.DATA.get(pid, {})
			out += "  [color=#9fd0ff]被动·%s[/color]：%s\n" % [pm.get("name", pid), pm.get("desc", "")]
		var acts: Array = sk.get("actives", [])
		for i in range(acts.size()):
			var aid := str(acts[i])
			if aid == "":
				continue
			var am: Dictionary = SE.DATA.get(aid, {})
			out += "  [color=#c8f0c8]技能%d·%s[/color]：%s\n" % [i + 1, am.get("name", aid), am.get("desc", "")]
	return out


## ================= 未开放提示 =================
var _locked_layer: Control = null

func _on_locked(name: String) -> void:
	_close_locked()
	var layer := Panel.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.9)
	layer.add_theme_stylebox_override("panel", sb)
	add_child(layer)
	_locked_layer = layer
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var card := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.12, 0.19, 0.97)
	cs.set_corner_radius_all(16)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(520, 0)
	cc.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 30)
	mg.add_theme_constant_override("margin_right", 30)
	mg.add_theme_constant_override("margin_top", 26)
	mg.add_theme_constant_override("margin_bottom", 26)
	v.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	mg.add_child(box)
	var t := Label.new()
	t.text = "暂未开放"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))
	box.add_child(t)
	var d := Label.new()
	d.text = "「%s」暂未开放，敬请期待。" % name
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 17)
	d.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	box.add_child(d)
	var back := Button.new()
	back.text = "回到主菜单"
	back.custom_minimum_size = Vector2(240, 48)
	back.pressed.connect(func():
		_close_locked()
		_on_to_menu())
	var bc := CenterContainer.new()
	bc.add_child(back)
	box.add_child(bc)

func _close_locked() -> void:
	if _locked_layer != null and is_instance_valid(_locked_layer):
		_locked_layer.queue_free()
	_locked_layer = null
