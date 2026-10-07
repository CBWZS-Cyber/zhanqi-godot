extends SceneTree
## Bug 上报 UI + CloudApi 邮件接口 · 无头自检（2026-10-04）
## 用法：godot --headless --path 工程 -s res://tests/bug_report_ui_check.gd
##
## 覆盖：
##   A SettingsLayer 构造（提交框 / 联系方式 / 提交按钮 / 三个菜单项 / 默认收起）
##   B 战局上下文的渲染与截断（只带最近 10 条）
##   C 描述为空**不发请求**
##   D 视图切换（设置 ↔ Bug 上报）
##   E CloudApi 的 send_code / submit_bug_report / 新信号
##
## ⚠️ 不出网：E 只检查"请求被正确发出"（`_req` 字段），不真的发 HTTP。

const SETTINGS_GD := "res://scripts/ui/settings_layer.gd"
const CLOUD_GD := "res://scripts/net/cloud_api.gd"

var _pass := 0
var _fail := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)


func _initialize() -> void:
	await process_frame
	print("【Bug 上报 UI + CloudApi 邮件接口】无头自检")

	# ── A 构造 ───────────────────────────────────────────────────────────
	print("\nA. SettingsLayer 构造")
	var S: GDScript = load(SETTINGS_GD)
	ck(S != null, "A1 settings_layer.gd 能加载")
	if S == null:
		_finish()
		return
	var layer: Control = S.new()
	root.add_child(layer)
	await process_frame
	ck(layer.get("_desc") is TextEdit, "A2 描述框是 TextEdit（能输入，不只是展示）")
	ck(layer.get("_contact") is LineEdit, "A3 联系方式是 LineEdit")
	var submit: Button = layer.get("_submit_btn")
	ck(submit != null and submit.text == "提交上报", "A4 主按钮文案 = 提交上报")
	ck(layer.get("_status") is Label, "A5 状态行存在")
	ck(layer.get("_report_body") is RichTextLabel, "A6 上下文预览存在")
	ck(layer.get("_mail_btn") != null and layer.get("_tpl_btn") != null,
		"A7 手动发信那两个按钮保留（降级路径）")
	var menu: VBoxContainer = layer.get("_menu_box")
	ck(menu != null and menu.get_child_count() == 3, "A8 设置菜单仍是 3 项")
	var rbox: VBoxContainer = layer.get("_report_box")
	ck(rbox != null and not rbox.visible, "A9 上报视图默认隐藏")
	ck(str(layer.get("service_url")) == "", "A10 服务地址默认空（由调用方注入）")

	# ── B 上下文渲染 ─────────────────────────────────────────────────────
	print("\nB. 战局上下文")
	var logs: Array[String] = []
	for i in range(1, 26):
		logs.append("第 %d 条战况" % i)
	layer.set("ctx", {"mode": "1V1 · 热座", "round": 7, "logs": logs})
	layer.call("_refresh_report_body")
	var body: RichTextLabel = layer.get("_report_body")
	ck(body.text.contains("1V1 · 热座") and body.text.contains("第 7 回合"),
		"B1 预览含对局模式与回合数")
	var detail: String = layer.call("_detail_ctx")
	ck(detail.contains("战局上下文") and detail.contains("第 25 条战况"),
		"B2 详情含上下文标题与最新战况")
	ck(not detail.contains("第 1 条战况"), "B3 旧战况被截掉（只带最近 10 条）")
	ck(detail.contains("第 16 条战况"), "B4 第 16 条（倒数第 10 条）在范围内")
	ck(str(layer.call("_first_line", "第一行内容\n第二行内容")) == "第一行内容",
		"B5 邮件主题取描述第一行")
	ck(str(layer.call("_first_line", "x".repeat(200))).length() <= 40,
		"B6 主题超长被截到 40 字内")

	# ── C 空描述不上报 ───────────────────────────────────────────────────
	print("\nC. 空描述")
	var desc: TextEdit = layer.get("_desc")
	desc.text = "  "
	layer.call("_submit_report")
	await process_frame
	ck(str((layer.get("_status") as Label).text) != "", "C1 给出提示文案")
	ck(layer.get("_cloud") == null, "C2 没建 CloudApi（一条请求都没发）")

	# ── D 视图切换 ───────────────────────────────────────────────────────
	print("\nD. 视图切换")
	layer.call("open_popup")
	ck(layer.visible and menu.visible and not rbox.visible, "D1 open_popup 落在设置菜单")
	layer.call("_show_report")
	ck(rbox.visible and not menu.visible, "D2 切到 Bug 上报视图")
	ck(str((layer.get("_title") as Label).text) == "Bug 上报", "D3 标题跟着切")
	layer.call("close_popup")
	ck(not layer.visible, "D4 能关闭")

	# ── E CloudApi 接口 ──────────────────────────────────────────────────
	print("\nE. CloudApi")
	var C: GDScript = load(CLOUD_GD)
	ck(C != null, "E1 cloud_api.gd 能加载")
	if C != null:
		var api: Node = C.new()
		root.add_child(api)
		await process_frame
		ck(api.has_method("send_code"), "E2 有 send_code()")
		ck(api.has_method("submit_bug_report"), "E3 有 submit_bug_report()")
		var sigs := ""
		for s in api.get_signal_list():
			sigs += str(s.get("name", "")) + ","
		ck(sigs.contains("send_code_done"), "E4 有 send_code_done 信号")
		ck(sigs.contains("report_done"), "E5 有 report_done 信号")
		var a2: Node = C.new()
		root.add_child(a2)
		a2.call("send_code", "player@example.com")
		ck(str(a2.get("_req")) == "send_code", "E6 send_code 走 /send-code")
		var a3: Node = C.new()
		root.add_child(a3)
		a3.call("register", "甲", "pass1234", "player@example.com", "123456")
		ck(str(a3.get("_req")) == "register", "E7 register 带上邮箱与验证码后仍走 /register")
		var a4: Node = C.new()
		root.add_child(a4)
		a4.call("submit_bug_report", {"title": "t", "detail": "d"})
		ck(str(a4.get("_req")) == "bug_report", "E8 submit_bug_report 走 /bug-report")
		api.queue_free()
		a2.queue_free()
		a3.queue_free()
		a4.queue_free()

	_finish()


func _finish() -> void:
	print("\n%s Bug 上报 UI / CloudApi：%d 通过 / %d 失败" % [
		"✅" if _fail == 0 else "❌", _pass, _fail])
	quit(0 if _fail == 0 else 1)
