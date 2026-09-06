class_name UnitInfoPopup
extends Control
## 右键棋子 · 信息浮层（1V1 / 4V4 共用）
## 用法：add_child(UnitInfoPopup.make(unit))
## 全屏半透明拦截层 + 居中信息卡：属性 / 被动 / 4 技能 / 状态印记；点 ✕ 或点暗背景关闭

static func make(u: BattleUnit) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	# 暗背景（点击关闭）
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	# 居中卡片
	var card := Panel.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -280.0
	card.offset_right = 280.0
	card.offset_top = -290.0
	card.offset_bottom = 290.0
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.12, 0.19, 0.97)
	cs.set_corner_radius_all(14)
	cs.border_color = Color(0.55, 0.50, 0.36)
	cs.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", cs)
	layer.add_child(card)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	card.add_child(m)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.text = bbcode(u)
	m.add_child(rt)
	# 右上角 ✕
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.offset_left = -50.0
	x.offset_right = -10.0
	x.offset_top = 8.0
	x.offset_bottom = 48.0
	x.pressed.connect(func(): layer.queue_free())
	card.add_child(x)
	# 点暗背景关闭
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			layer.queue_free())
	return layer

## 信息 BBCode：属性行 / 被动 / 4 技能 / 状态与印记
static func bbcode(u: BattleUnit) -> String:
	var out := ""
	var camp := "红方" if u.team == 0 else "蓝方"
	out += "[color=#ffd95a][b]%s[/b][/color] 〔%s〕· %s\n" % [u.name, u.element, camp]
	out += "[color=#9aa5b5]────────────────────[/color]\n"
	# 属性行（理智系显示理智，无上限显示 ∞）
	var res_txt := ""
	if u.has_sanity:
		res_txt = "理智 %.2f/%.2f" % [u.sanity, u.sanity_cap]
	elif u.max_energy < 0:
		res_txt = "能量 %.2f/∞" % u.energy
	else:
		res_txt = "能量 %.2f/%.2f" % [u.energy, u.max_energy]
	out += "HP %.2f/%.2f　%s\n盾 %.2f　甲 %.2f　速 %d\n" % [
		u.hp, u.max_hp, res_txt, u.shield, u.armor, u.effective_speed()]
	# 被动
	if u.passive != null:
		out += "\n[color=#ffd95a]被动·%s[/color]\n%s\n" % [u.passive.display_name, u.passive.desc]
	# 技能
	out += "\n[color=#ffd95a]技能[/color]\n"
	for i in range(1, 5):
		var sk = u.get_skill(i)
		if sk == null:
			continue
		var tag := ""
		if u.is_skill_lost(sk.id):
			tag = " [color=#ff7a7a]（被掠夺/禁用）[/color]"
		elif sk.current_cd > 0:
			tag = " [color=#9aa5b5]（冷却 %d）[/color]" % sk.current_cd
		var kind := "大招" if i == 4 else "技能%d" % i
		out += "[color=#e8d48a]%s·%s[/color]%s\n%s\n" % [kind, sk.display_name, tag, sk.desc]
	# 印记 / 状态
	var extra: Array[String] = []
	for k in u.counters:
		var v := int(u.counters[k])
		if v > 0:
			extra.append("[color=#8fd48f]%s×%d[/color]" % [k, v])
	var sts: Array = u.status_icons()
	for d in sts:
		extra.append("[color=#ff7a7a]%s%d[/color]" % [str((d as Dictionary).get("cn", "")), int((d as Dictionary).get("lv", 0))])
	if not extra.is_empty():
		out += "\n[color=#ffd95a]印记/状态[/color]\n" + "　".join(extra)
	return out
