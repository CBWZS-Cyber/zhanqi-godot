class_name UnitInfoPopup
extends Control
## 右键棋子 · 信息浮层（1V1 / 4V4 共用）
## 用法：add_child(UnitInfoPopup.make(unit))
## 全屏半透明拦截层 + 居中信息卡：属性 / 被动 / 4 技能 / 状态印记；点 ✕ 或点暗背景关闭

static func make(u: BattleUnit) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 4096          # 置顶：否则棋子骨骼部件（自带 z_index）会盖住弹窗
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
	cs.bg_color = Color(0.985, 0.97, 0.93, 0.995)   # 米白（与图鉴主题一致）
	cs.set_corner_radius_all(14)
	cs.border_color = Color(0.65, 0.55, 0.40)
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
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
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
	out += "[color=#7a5a10][b]%s[/b][/color] 〔%s〕· %s\n" % [u.name, u.element, camp]
	out += "[color=#b3aa98]────────────────────[/color]\n"
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
		out += "\n[color=#2e5d9e]被动·%s[/color]\n%s\n" % [u.passive.display_name, u.passive.desc]
	# 技能
	out += "\n[color=#2e6b3c]技能[/color]\n"
	for i in range(1, 5):
		var sk = u.get_skill(i)
		if sk == null:
			continue
		var tag := ""
		if u.is_skill_lost(sk.id):
			tag = " [color=#b54a28]（被掠夺/禁用）[/color]"
		elif sk.current_cd > 0:
			tag = " [color=#8a8578]（冷却 %d）[/color]" % sk.current_cd
		var kind := "大招" if i == 4 else "技能%d" % i
		out += "[color=#2e6b3c]%s·%s[/color]%s\n%s\n" % [kind, sk.display_name, tag, sk.desc]
	# 印记 / 状态
	var extra: Array[String] = []
	for k in u.counters:
		var v := int(u.counters[k])
		if v > 0:
			extra.append("[color=#2e7a46]%s×%d[/color]" % [k, v])
	var sts: Array = u.status_icons()
	for d in sts:
		extra.append("[color=#b54a28]%s[/color]" % str((d as Dictionary).get("label", "")))
	if not extra.is_empty():
		out += "\n[color=#a06a10]印记 / 状态[/color]\n" + "　".join(extra)
	# 装备（武器）
	out += "\n[color=#a06a10]装备[/color]\n"
	if u.equipment.is_empty():
		out += "[color=#8a8578]（未装备武器）[/color]\n"
	else:
		for wid in u.equipment:
			var wname: String = Weapons.name_of(str(wid))
			var wdef: Dictionary = Weapons.get_def(str(wid))
			out += "[color=#2e5d9e]%s[/color]（%s）" % [wname, str(wdef.get("tier", ""))]
			var aff := str(wdef.get("affinity", ""))
			if aff != "":
				out += "　[color=#2e7a46]%s[/color]" % aff
			out += "\n"
	# 所在地形
	var tid: int = u.terrain_id
	out += "\n[color=#a06a10]所在地形[/color]\n[color=#2e7a46]%s[/color]：%s\n" % [
		Terrain.name_of(tid), Terrain.desc_of(tid)]
	return out


## 星星格 · 信息浮层（右键星格查看内含武器）
static func make_star(star: Dictionary) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 4096          # 置顶（同上）
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var card := Panel.new()
	card.custom_minimum_size = Vector2(420, 0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -210.0
	card.offset_right = 210.0
	card.offset_top = -110.0
	card.offset_bottom = 110.0
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.985, 0.97, 0.93, 0.995)
	cs.set_corner_radius_all(14)
	cs.border_color = Color(0.65, 0.55, 0.40)
	cs.set_border_width_all(2)
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
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
	var is_big := bool(star.get("big", false))
	var wid := str(star.get("weapon", ""))
	var val := 5 if is_big else 3
	var out := "[color=#7a5a10][b]★ %s星星[/b][/color]（拾取 +%d 分）\n" % ["大" if is_big else "小", val]
	out += "[color=#b3aa98]────────────────────[/color]\n"
	if wid == "":
		out += "[color=#8a8578]（未登记武器）[/color]\n"
	else:
		var d: Dictionary = Weapons.get_def(wid)
		out += "[color=#2e5d9e][b]%s[/b][/color]（%s · %s）\n" % [Weapons.name_of(wid), str(d.get("element", "")), str(d.get("tier", ""))]
		var aff := str(d.get("affinity", ""))
		if aff != "":
			out += "[color=#2e7a46]契合：%s[/color]\n" % aff
		var st := Weapons.skills_text(wid)
		if st != "":
			out += "\n[color=#2e6b3c]技能[/color]\n" + st
	out += "\n[color=#8a8578]棋子走上去即可拾取（同时得分与装备）[/color]"
	rt.text = out
	m.add_child(rt)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.anchor_top = 0.0
	x.offset_left = -44.0
	x.offset_right = -4.0
	x.offset_top = 4.0
	x.offset_bottom = 44.0
	x.pressed.connect(func() -> void: layer.queue_free())
	card.add_child(x)
	bg.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			layer.queue_free())
	return layer
