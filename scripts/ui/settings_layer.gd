class_name SettingsLayer
extends Control
## 局内设置弹层（1V1 Duel / 4V4 TeamDuel 通用）
## 视图1「设置」：Bug 上报 / 返回主菜单 / 关闭
## 视图2「Bug 上报」：引导玩家用自己的邮箱发信到 AI 邮箱，
##   提供【复制收件邮箱】【打开网易邮箱】【打开 QQ 邮箱】【复制上报模板】并致谢。

signal closed

const MAIL := "sgrh9516@agent.qq.com"
const MAIL_NETEASE := "https://mail.163.com/"
const MAIL_QQ := "https://mail.qq.com/"
const COL_PANEL := Color(0.10, 0.12, 0.19, 0.97)
const COL_GOLD := Color(0.941, 0.780, 0.369)

## 上报上下文（由对局填充）：{mode, round, logs:[String]}
var ctx: Dictionary = {}
var _card: PanelContainer
var _title: Label
var _menu_box: VBoxContainer
var _report_box: VBoxContainer
var _report_body: RichTextLabel
var _mail_btn: Button
var _tpl_btn: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 半透明遮罩
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	# 中央卡片
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb["corner_radius_" + r] = 16
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.42, 0.30)
	_card.add_theme_stylebox_override("panel", sb)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.add_child(_card)
	add_child(cc)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_title = _label("设置", 26, COL_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	# —— 设置菜单视图 ——
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	box.add_child(_menu_box)
	_menu_box.add_child(_big_btn("🐞 Bug 上报", Callable(self, "_show_report")))
	_menu_box.add_child(_big_btn("🏠 返回主菜单", Callable(self, "_back_to_menu")))
	_menu_box.add_child(_big_btn("✕ 关闭", Callable(self, "close_popup")))
	# —— Bug 上报视图 ——
	_report_box = VBoxContainer.new()
	_report_box.add_theme_constant_override("separation", 10)
	box.add_child(_report_box)
	var thanks := _label("感谢你的反馈！💝", 18, Color(0.95, 0.9, 0.6))
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_box.add_child(thanks)
	var tip := _label("遇到问题请用【你自己的邮箱】发一封邮件到下面的地址，把情况告诉我们，我们会尽快处理！", 13, Color(0.84, 0.87, 0.94))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_box.add_child(tip)
	var mail_lab := _label(MAIL, 22, Color(1.0, 0.85, 0.4))
	mail_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_box.add_child(mail_lab)
	_report_body = RichTextLabel.new()
	_report_body.bbcode_enabled = true
	_report_body.scroll_active = true
	_report_body.custom_minimum_size = Vector2(0, 110)
	_report_body.fit_content = false
	_report_body.add_theme_font_size_override("normal_font_size", 13)
	_report_box.add_child(_report_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_report_box.add_child(row)
	_mail_btn = _small_btn("复制收件邮箱", Callable(self, "_copy_mail"))
	row.add_child(_mail_btn)
	_tpl_btn = _small_btn("复制上报模板", Callable(self, "_copy_template"))
	row.add_child(_tpl_btn)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_report_box.add_child(row2)
	row2.add_child(_small_btn("打开 网易邮箱", Callable(self, "_open").bind(MAIL_NETEASE)))
	row2.add_child(_small_btn("打开 QQ 邮箱", Callable(self, "_open").bind(MAIL_QQ)))
	var back := _small_btn("‹ 返回设置", Callable(self, "_show_menu"))
	_report_box.add_child(back)
	_report_box.visible = false

func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _style(b: Button, small: bool) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.16, 0.19, 0.29)
	n.border_color = Color(0.45, 0.42, 0.30)
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	var h := n.duplicate(); h.bg_color = Color(0.23, 0.27, 0.42)
	var pr := n.duplicate(); pr.bg_color = Color(0.12, 0.15, 0.24)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	if small:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
	else:
		b.custom_minimum_size = Vector2(360, 50)
		b.add_theme_font_size_override("font_size", 16)

func _big_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.pressed.connect(cb)
	_style(b, false)
	return b

func _small_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.pressed.connect(cb)
	_style(b, true)
	return b

## 对局脚本调用：填入上报上下文后打开
func open_popup() -> void:
	visible = true
	_show_menu()
	_refresh_report_body()

func close_popup() -> void:
	visible = false
	closed.emit()

func _show_menu() -> void:
	_title.text = "设置"
	_menu_box.visible = true
	_report_box.visible = false

func _show_report() -> void:
	_title.text = "Bug 上报"
	_menu_box.visible = false
	_report_box.visible = true
	_refresh_report_body()

func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainUI.tscn")

func _refresh_report_body() -> void:
	if _report_body == null:
		return
	_report_body.text = "[color=#9fd0ff]3 步完成上报：[/color]\n" \
		+ "1. 复制上面的收件邮箱\n" \
		+ "2. 打开 网易邮箱 / QQ 邮箱，点“写邮件”\n" \
		+ "3. 粘贴邮箱地址，可点“复制上报模板”把当前战局信息一起贴上，补上你的问题描述后发送\n\n" \
		+ "[color=#7d8796]小提示：写清“做了什么 → 看到什么 → 期望什么”，能帮我们更快修复。[/color]"

## 上报模板（含当前对局上下文，供玩家粘贴进邮件）
func report_template() -> String:
	var lines: Array[String] = []
	lines.append("【战棋 Bug 上报】")
	lines.append("对局：%s　·　第 %d 回合" % [str(ctx.get("mode", "未知")), int(ctx.get("round", 0))])
	var logs: Array = ctx.get("logs", [])
	var tail := logs.slice(maxi(0, logs.size() - 10))
	if tail.size() > 0:
		lines.append("—— 最近战况 ——")
		for s in tail:
			lines.append(String(s))
	lines.append("—— 请补充 ——")
	lines.append("现象描述：")
	lines.append("操作步骤：")
	lines.append("期望表现：")
	return "\n".join(lines)

func _copy_mail() -> void:
	DisplayServer.clipboard_set(MAIL)
	_mail_btn.text = "已复制 ✓"
	_mail_btn.modulate = Color(0.7, 1.0, 0.7)
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(func():
		if is_instance_valid(_mail_btn):
			_mail_btn.text = "复制收件邮箱"
			_mail_btn.modulate = Color.WHITE)

func _copy_template() -> void:
	DisplayServer.clipboard_set(report_template())
	_tpl_btn.text = "模板已复制 ✓"
	_tpl_btn.modulate = Color(0.7, 1.0, 0.7)
	var t2 := get_tree().create_timer(1.6)
	t2.timeout.connect(func():
		if is_instance_valid(_tpl_btn):
			_tpl_btn.text = "复制上报模板"
			_tpl_btn.modulate = Color.WHITE)

func _open(url: String) -> void:
	var err := OS.shell_open(url)
	if err != OK:
		print("[Settings] 打开浏览器失败：", err)
