class_name SettingsLayer
extends Control
## 局内设置弹层（1V1 Duel / 4V4 TeamDuel / 剧情战斗 通用）
## 视图1「设置」：Bug 上报 / 返回主菜单 / 关闭
## 视图2「Bug 上报」（2026-10-04 改成**直接提交**）：
##   玩家在框里写清问题 → 点「提交上报」→ **服务端直接把邮件投到 AI 邮箱**。
##   原先那套「自己复制邮箱、开邮箱、贴模板」保留为**降级路径**
##   （没网 / 提交失败时才需要），不再要求玩家手动发信。
##
## 🔴 本文件**不接触任何邮件凭据**：只调 CloudApi（8789），发信在服务器侧完成。

signal closed

const MAIL := "sgrh9516@agent.qq.com"
const MAIL_NETEASE := "https://mail.163.com/"
const MAIL_QQ := "https://mail.qq.com/"
const COL_PANEL := UiDesign.SURFACE_PANEL
const COL_GOLD := UiDesign.GOLD_500

## 上报上下文（由对局填充）：{mode, round, logs:[String]}
var ctx: Dictionary = {}
## 云服务地址：由调用方注入（不注入就用 CloudApi 的默认地址）
var service_url := ""
var _card: PanelContainer
var _title: Label
var _menu_box: VBoxContainer
var _report_box: VBoxContainer
var _report_body: RichTextLabel
var _mail_btn: Button
var _tpl_btn: Button
var _desc: TextEdit
var _contact: LineEdit
var _submit_btn: Button
var _status: Label
var _cloud: CloudApi = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 必须置顶（2026-10-05 用户实报「人物显示在设置弹窗上面」）：
	#   棋子自带 z_index（名字标签 120 / 击破特效 110 / 骨骼部件由数据给），
	#   而弹层默认 0 → 棋子会画在弹窗之上。统一从 UiDesign 取层级，别再写死。
	z_index = UiDesign.Z_OVERLAY
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
	sb.border_color = UiDesign.BTN_BORDER
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
	var tip := _label("在下面把问题写清楚，点「提交上报」就行 —— 不用你自己开邮箱发信。", 13, UiDesign.INK_200)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_box.add_child(tip)

	# 描述框（RichTextLabel 只能看不能写，这里必须是 TextEdit）
	_desc = TextEdit.new()
	_desc.placeholder_text = "做了什么 → 看到什么 → 期望什么"
	_desc.custom_minimum_size = Vector2(360, 104)
	_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc.add_theme_stylebox_override("normal", UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.BORDER))
	_desc.add_theme_stylebox_override("focus", UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.FOCUS, UiDesign.FOCUS_WIDTH))
	_desc.add_theme_color_override("font_color", UiDesign.INK_100)
	_desc.add_theme_color_override("font_placeholder_color", UiDesign.INK_400)
	_desc.add_theme_color_override("caret_color", UiDesign.GOLD_500)
	_desc.add_theme_font_size_override("font_size", 14)
	_report_box.add_child(_desc)

	# 联系方式：可选。不登录的玩家也能留个邮箱，方便追问
	_contact = _small_edit("联系方式（可选，方便我们追问）")
	_report_box.add_child(_contact)

	_submit_btn = _big_btn("提交上报", Callable(self, "_submit_report"))
	_report_box.add_child(_submit_btn)

	_status = _label("", 13, UiDesign.GOLD_300)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_box.add_child(_status)

	# 会自动附上的战局信息（只读）—— 让玩家知道到底发出去了什么
	var ctx_tip := _label("会一起附上（只读）：", 12, UiDesign.INK_200)
	_report_box.add_child(ctx_tip)
	_report_body = RichTextLabel.new()
	_report_body.bbcode_enabled = true
	_report_body.scroll_active = true
	_report_body.custom_minimum_size = Vector2(0, 76)
	_report_body.fit_content = false
	_report_body.add_theme_font_size_override("normal_font_size", 12)
	_report_box.add_child(_report_body)

	# —— 手动发信：降级路径，只在没网 / 提交失败时才用得上 ——
	var manual_tip := _label("提交不了？也可以自己发邮件到 %s" % MAIL, 12, UiDesign.INK_200)
	manual_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_box.add_child(manual_tip)
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
	n.bg_color = UiDesign.INK_700
	n.border_color = UiDesign.BTN_BORDER
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	var h := n.duplicate(); h.bg_color = UiDesign.INK_600
	var pr := n.duplicate(); pr.bg_color = UiDesign.INK_750
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", UiDesign.INK_100)
	b.add_theme_color_override("font_hover_color", UiDesign.GOLD_300)
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

func _small_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, 40)
	UiTheme.style_input(e, 0, 40)      # 与主界面输入框同一套皮肤
	return e

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

## 战局上下文预览（只读）：让玩家看到"会一起发出去什么"
func _refresh_report_body() -> void:
	if _report_body == null:
		return
	var lines: Array[String] = []
	lines.append("对局：%s　·　第 %d 回合" % [str(ctx.get("mode", "未知")), int(ctx.get("round", 0))])
	for s in _ctx_logs():
		lines.append(String(s))
	if _ctx_logs().size() == 0:
		lines.append("[color=#7d8796]（暂无战况记录）[/color]")
	lines.append("[color=#7d8796]小提示：写清“做了什么 → 看到什么 → 期望什么”，能帮我们更快修复。[/color]")
	_report_body.text = "\n".join(lines)


## 最近战况（最多 10 条）—— 手动模板与自动上报共用这一份来源
func _ctx_logs() -> Array:
	var logs: Array = ctx.get("logs", [])
	return logs.slice(maxi(0, logs.size() - 10))


## 提交上报：**服务端直投 AI 邮箱**，玩家不用自己开邮箱、不用复制地址
func _submit_report() -> void:
	var txt := "" if _desc == null else _desc.text.strip_edges()
	if txt.length() < 4:
		_status.text = "先写清楚问题（至少几个字）"
		return
	if _cloud == null:
		_cloud = CloudApi.new()
		_cloud.service_url = service_url if service_url != "" else CloudApi.DEFAULT_SERVICE
		add_child(_cloud)
		_cloud.report_done.connect(_on_report_done)
	if _submit_btn != null:
		_submit_btn.disabled = true
		_submit_btn.text = "提交中…"
	_status.text = ""
	_cloud.submit_bug_report({
		"title": _first_line(txt),
		"detail": txt + _detail_ctx(),
		"contact": "" if _contact == null else _contact.text.strip_edges(),
		"category": str(ctx.get("mode", "")),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"platform": OS.get_name(),
	})


func _on_report_done(ok: bool, msg: String) -> void:
	if _submit_btn != null:
		_submit_btn.disabled = false
		_submit_btn.text = "提交上报"
	if ok:
		_status.text = "已提交 ✓ 编号 %s —— 感谢你的反馈！" % msg
		if _desc != null:
			_desc.text = ""
	else:
		_status.text = "提交失败：%s（可改用下面「复制收件邮箱」手动发给我们）" % msg


## 邮件主题取描述第一行；太长就截断（服务端也会再截一次）
func _first_line(s: String) -> String:
	var head := s.split("\n")[0].strip_edges()
	return head.substr(0, 40)


## 附在描述后面的战局上下文（服务端会把整段放进邮件正文）
func _detail_ctx() -> String:
	var lines: Array[String] = ["", "—— 战局上下文（自动附上）——",
		"对局：%s　·　第 %d 回合" % [str(ctx.get("mode", "未知")), int(ctx.get("round", 0))]]
	var tail := _ctx_logs()
	if tail.size() > 0:
		lines.append("—— 最近战况 ——")
		for s in tail:
			lines.append(String(s))
	return "\n".join(lines)

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
