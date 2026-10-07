extends SceneTree
## 云端登录态 + 离线进度回归（2026-10-04 建；2026-10-05 随「删本地账号」重构）
## 用法：godot --headless --path 工程 -s res://tests/cloud_auth_smoke.gd
##
## ⚠️ 2026-10-05 按客户要求删掉了**整套本地账号**（原 `AccountStore` / `accounts.json` /
##    登录页的「选择已有账号」弹窗）。现在的模型只有两层：
##      · **账号 = 云端账号**（唯一）；
##      · **离线玩** = 用一份**匿名本机进度**（`ProgressStore` → `user://progress.json`）——
##        没有名字、没有 id、不出现在任何列表，本机首次玩就是「0 进度原始账号」；
##      · **两份进度互不污染**：登录中读写云端，离线玩读写本机。
##
## 覆盖：
##   A. `CloudSession` 的 remember 语义（remember=false = 只记昵称、不记登录）
##   B. 账号行只有两种形态；**界面上永不出现「本机账号 / 未登录 / 选择已有账号 / 当前账号」**
##   C. 启动分流：有登录态 / 有离线进度 → 主菜单；什么都没有 → 登录页
##   D. 离线玩走本机匿名进度：写得进、读得回、再点一次能接着玩
##   E. 登录中写进度**不碰**本机离线档（两份隔离）
##
## ⚠️ 会读写 `user://cloud_session.json` 与 `user://progress.json` → **先快照、跑完还原**。
## ⚠️ `-s` 模式里不能直接写 `Global.xxx`（autoload 名解析不了）→ 用 get_node_or_null。
##
## 全部通过 exit 0，有失败 exit 1。

const SESSION_PATH := "user://cloud_session.json"
const PROGRESS_PATH := "user://progress.json"

var _pass := 0
var _fail := 0
var _bak := {}      # path -> {"existed": bool, "text": String}


func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)


# ---------------- 存档快照（测试卫生）----------------

func _snap(path: String) -> void:
	var existed := FileAccess.file_exists(path)
	var txt := ""
	if existed:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			txt = f.get_as_text()
			f.close()
	_bak[path] = {"existed": existed, "text": txt}


func _restore_all() -> void:
	for path in _bak.keys():
		var b: Dictionary = _bak[path]
		if bool(b.get("existed", false)):
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(str(b.get("text", "")))
				f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _g() -> Variant:
	return root.get_node_or_null("Global")


func _initialize() -> void:
	await process_frame
	_snap(SESSION_PATH)
	_snap(PROGRESS_PATH)

	print("【A】CloudSession 的「记住我」语义")
	_test_session_layer()

	print("【B】账号行只有两种形态（本机已无「账号」这个概念）")
	await _test_label_forms()

	print("【C】启动分流")
	await _test_initial_panel()

	print("【D】离线玩 = 本机匿名进度")
	await _test_offline_progress()

	print("【E】登录中写进度不碰本机离线档（两份隔离）")
	await _test_isolation()

	print("【F】忘记密码：客户端契约 + 界面（不真发信）")
	await _test_forgot_password()

	_restore_all()
	print("== 云端登录态结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------- A. 数据层 ----------------

func _test_session_layer() -> void:
	const SVC := "http://test-svc"
	CloudSession.clear()
	ck(not CloudSession.has_session(SVC), "clear 之后没有会话")
	ck(CloudSession.cached_name(SVC) == "", "clear 之后昵称也取不到")

	var acc := {"name": "测试账号", "uid": "u-test"}

	# —— 不勾「记住我」——
	CloudSession.save(SVC, "tok-abc", acc, false)
	ck(not CloudSession.has_session(SVC), "★ remember=false → has_session 为假（下次启动不自动登录）")
	ck(CloudSession.load_session(SVC).is_empty(), "★ remember=false → load_session 返回空")
	ck(CloudSession.cached_name(SVC) == "测试账号",
		"★ remember=false 时**昵称仍能取到**（登录页照样预填，只是要再输密码）")

	# —— 勾「记住我」——
	CloudSession.save(SVC, "tok-abc", acc, true)
	ck(CloudSession.has_session(SVC), "remember=true → 会自动登录")
	var sess := CloudSession.load_session(SVC)
	ck(str(sess.get("token", "")) == "tok-abc", "token 读回一致")
	ck(str(sess.get("account", {}).get("name", "")) == "测试账号", "账号信息读回一致（断网时进度就从这里兜底）")

	CloudSession.save(SVC, "tok-xyz", acc)
	ck(CloudSession.has_session(SVC), "不传 remember 时默认 true（老调用点行为不变）")
	ck(CloudSession.load_session("http://other-svc").is_empty(), "换了服务地址 → 旧会话作废")

	CloudSession.clear()
	ck(not CloudSession.has_session(SVC), "再次 clear → 回到无会话")


# ---------------- B. 账号行的两种形态 ----------------

func _test_label_forms() -> void:
	var g: Variant = _g()
	ck(g != null, "取到 Global")
	if g == null:
		return

	# —— 离线态：本机有进度，但**没有任何名字** ——
	ProgressStore.save_progress({"tier": "veteran", "tutorial_done": false, "tutorial_hero": ""})
	g.cloud_online = false
	g.cloud_account = {}
	g.player_progress = ProgressStore.load_progress()

	var ui: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	for i in range(8):
		await process_frame

	ck(str(ui._acct_label.text) == "离线游玩（进度只在这台电脑）",
		"★ 离线 → 标签是「离线游玩（进度只在这台电脑）」（实际 %s）" % str(ui._acct_label.text))
	ck(str(ui._sign_btn.text) == "登录云端", "离线 → 按钮文案「登录云端」")
	ck(ui._sign_btn.visible, "离线 → 按钮可见（它是唯一的登录入口）")
	# ★ 客户 2026-10-05 明确要求：界面上不再有「本地账号」这套东西
	for bad in ["本机账号", "未登录", "选择已有账号", "当前账号"]:
		ck(not _has_text(ui, bad), "★ 整个界面不出现「%s」" % bad)

	# —— 已登录态 ——
	g.cloud_online = true
	g.cloud_account = {"name": "云端测试号", "uid": "u-1",
		"progress": {"tier": "played", "tutorial_done": true, "tutorial_hero": "guang_yu"}}
	g.player_progress = {"v": 1, "tier": "played", "tutorial_done": true, "tutorial_hero": "guang_yu"}
	ui._refresh_account_label()
	ck(str(ui._acct_label.text).find("云端账号：云端测试号") == 0,
		"★ 已登录 → 标签是「云端账号：名字 …」（实际 %s）" % str(ui._acct_label.text))
	ck(str(ui._acct_label.text).find("已过教程") >= 0,
		"标签带上教程状态（实际 %s）" % str(ui._acct_label.text))
	ck(str(ui._sign_btn.text) == "退出登录", "已登录 → 按钮文案「退出登录」")

	# 退出登录：云端态清干净、回登录页，但**本机离线进度不受影响**
	var keep := str(ProgressStore.load_progress().get("tier", ""))
	ui._on_sign_action()
	for i in range(3):
		await process_frame
	ck(not bool(g.cloud_online), "★ 退出后 cloud_online = false")
	ck(not CloudSession.has_session(str(g.cloud_service)), "★ 退出后云端会话已清（下次启动不自动登录）")
	ck(g.cloud_account.is_empty(), "★ 退出后 cloud_account 清空（界面不会再出现名字）")
	ck(str(ui._current) == "tut_login", "退出后回到登录页（实际 %s）" % str(ui._current))
	ck(str(ProgressStore.load_progress().get("tier", "")) == keep,
		"★ 退出登录**不动**本机离线进度（仍是 %s）" % keep)

	ui.queue_free()
	await process_frame


# ---------------- C. 启动分流 ----------------

func _test_initial_panel() -> void:
	var g: Variant = _g()
	if g == null:
		return

	# ① 什么都没有 → 登录页
	ProgressStore.reset()
	g.cloud_online = false
	g.cloud_account = {}
	CloudSession.clear()
	var ui1: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui1)
	for i in range(5):
		await process_frame
	ck(str(ui1._current) == "tut_login",
		"★ 全新（无登录态、无离线进度）→ 落登录页（实际 %s）" % str(ui1._current))
	ui1.queue_free()
	await process_frame

	# ② 本机有离线进度 → 直接主菜单（接着上次玩）
	ProgressStore.update({"tier": "played"})
	var ui2: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui2)
	for i in range(5):
		await process_frame
	ck(str(ui2._current) == "start",
		"★ 本机有离线进度 → 直接进主菜单（实际 %s）" % str(ui2._current))
	ck(str(ui2._acct_label.text).find("离线游玩") == 0,
		"★ 且标签是「离线游玩…」（实际 %s）" % str(ui2._acct_label.text))
	ui2.queue_free()
	await process_frame

	# ③ 有登录态 → 主菜单且是云端账号
	var svc := str(g.cloud_service)
	CloudSession.save(svc, "tok-boot", {"name": "开机号", "uid": "u-boot",
		"progress": {"tier": "veteran", "tutorial_done": true, "tutorial_hero": ""}}, true)
	var ui3: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui3)
	for i in range(6):
		await process_frame
	ck(bool(g.cloud_online), "★ 有会话 → 启动即已登录")
	ck(str(ui3._current) == "start", "★ 有登录态 → 直接进主菜单（实际 %s）" % str(ui3._current))
	ck(str(ui3._acct_label.text).find("云端账号：开机号") == 0,
		"★ 标签是「云端账号：开机号…」（实际 %s）" % str(ui3._acct_label.text))
	ck(str(g.player_progress.get("tier", "")) == "veteran",
		"★ 进度从会话缓存恢复（断网时靠它兜底；实际 %s）" % str(g.player_progress.get("tier", "")))
	ui3.queue_free()
	CloudSession.clear()
	g.cloud_online = false
	g.cloud_account = {}
	await process_frame


# ---------------- D. 离线玩 = 本机匿名进度 ----------------

func _test_offline_progress() -> void:
	ProgressStore.reset()
	var g: Variant = _g()
	if g != null:
		g.cloud_online = true                                     # 故意弄脏
		g.cloud_account = {"name": "不该出现", "uid": "u-dirty"}   # 确认会被切掉

	var ui: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	for i in range(6):
		await process_frame

	ui._on_offline_mode()
	for i in range(4):
		await process_frame
	if g != null:
		ck(not bool(g.cloud_online), "★ 点「离线玩」→ cloud_online 置 false")
		ck(g.cloud_account.is_empty(), "★ 并清掉云端账号信息（界面不会再冒名字）")
	ck(str(ui._current) == "tut_level",
		"★ 本机还没有进度 → 先问水平（= 0 进度原始账号；实际 %s）" % str(ui._current))
	ck(not _has_text(ui, "不该出现"), "★ 弄脏的名字没有泄漏到界面上")

	# 选水平 → 写进本机 progress.json（登录中则不会写这里，见 E 段）
	ui._on_tier("played")
	for i in range(3):
		await process_frame
	ck(str(ProgressStore.load_progress().get("tier", "")) == "played",
		"★ 离线选的档位写进了本机 progress.json（实际 %s）" % str(ProgressStore.load_progress()))
	ck(str(ui._current) == "tut_hero", "选完水平 → 去选教程角色（实际 %s）" % str(ui._current))

	# 再点一次「离线玩」→ **接着上次那份**（不再重复问水平）
	ui._on_tut_hero("guang_yu")
	await process_frame
	ui._show_panel("tut_login")
	ui._on_offline_mode()
	for i in range(3):
		await process_frame
	ck(str(ui._current) == "start",
		"★ 已有离线进度 → 再点「离线玩」直接进主菜单（实际 %s）" % str(ui._current))
	ck(str(ProgressStore.load_progress().get("tutorial_hero", "")) == "guang_yu",
		"★ 教程角色也留在本机（实际 %s）" % str(ProgressStore.load_progress()))

	ui.queue_free()
	await process_frame


# ---------------- E. 两份进度互不污染 ----------------

func _test_isolation() -> void:
	ProgressStore.save_progress({"tier": "veteran", "tutorial_done": true, "tutorial_hero": "li_tai_bai"})
	var before := ProgressStore.load_progress()
	var g: Variant = _g()
	if g == null:
		return
	g.cloud_online = true
	g.cloud_account = {"name": "云端号", "uid": "u-iso"}
	g.player_progress = {"v": 1, "tier": "", "tutorial_done": false, "tutorial_hero": ""}

	var ui: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	for i in range(6):
		await process_frame

	ck(str(g.player_progress.get("tier", "")) == "",
		"（准备）登录态下进度是云端给的空档（实际 %s）" % str(g.player_progress.get("tier", "")))

	ui._on_tier("new")
	for i in range(3):
		await process_frame

	ck(str(g.player_progress.get("tier", "")) == "new", "登录中选的档位进了内存进度")
	var after := ProgressStore.load_progress()
	ck(str(after.get("tier", "")) == str(before.get("tier", ""))
		and bool(after.get("tutorial_done", false)) == bool(before.get("tutorial_done", false)),
		"★ 登录中写进度**完全不碰**本机离线档（本机仍是 %s；实际 %s）" % [str(before), str(after)])

	ui.queue_free()
	await process_frame


# ---------------- 控件树辅助（只读遍历）----------------

func _collect_all_texts(n: Node) -> Array:
	var out := []
	if n is Label:
		out.append(str((n as Label).text))
	elif n is Button:
		out.append(str((n as Button).text))
	elif n is CheckBox:
		out.append(str((n as CheckBox).text))
	for ch in n.get_children():
		out.append_array(_collect_all_texts(ch))
	return out


func _any_contains(arr: Array, sub: String) -> bool:
	for t in arr:
		if str(t).find(sub) >= 0:
			return true
	return false


func _has_text(n: Node, sub: String) -> bool:
	return _any_contains(_collect_all_texts(n), sub)


# ---------------- F. 忘记密码（2026-10-05 加）----------------

## 客户 2026-10-05 定「建 SMTP 邮件通道：忘记密码 + 注册验证码 + Bug 上报三件一起做真」。
## 核实后：**注册验证码与 Bug 上报服务端早已实现**（走 8789 → mail-gateway 8791 → QQ 邮箱），
## 只有**忘记密码**是新的。所以这条只覆盖新增的那部分。
##
## ⚠️ 这里**只测客户端契约与界面**：不真发邮件、不碰线上。
##    服务端的 `/send-code`(purpose=reset) 与 `/reset-password` 按本文件钉的这套形状实现
##    （路径 + 字段名 + 回包），两边对齐就不会返工。
func _test_forgot_password() -> void:
	print("【F】忘记密码：客户端契约 + 界面（不真发信）")

	# ① 接口契约 —— 服务端照这个形状实现
	var api_src: String = FileAccess.get_file_as_string("res://scripts/net/cloud_api.gd")
	ck(api_src.find("func send_reset_code") >= 0, "CloudApi 有 send_reset_code()")
	ck(api_src.find("func reset_password") >= 0, "CloudApi 有 reset_password()")
	ck(api_src.find("signal reset_code_done") >= 0, "有信号 reset_code_done")
	ck(api_src.find("signal reset_password_done") >= 0, "有信号 reset_password_done")
	ck(api_src.find("/reset-password") >= 0, "走 POST /reset-password")
	ck(api_src.find("purpose") >= 0, "重置码复用 /send-code 并带 purpose 区分用途")

	var api := CloudApi.new()
	root.add_child(api)
	await process_frame
	ck(api.has_method("send_reset_code"), "实例上有 send_reset_code")
	ck(api.has_method("reset_password"), "实例上有 reset_password")
	var names: Array = []
	for s in api.get_signal_list():
		names.append(str((s as Dictionary).get("name", "")))
	ck(names.has("reset_code_done"), "信号表里有 reset_code_done")
	ck(names.has("reset_password_done"), "信号表里有 reset_password_done")
	api.queue_free()
	await process_frame

	# ② 界面：登录页有入口 → 点开弹层 → 初始状态正确
	ProgressStore.reset()
	var g: Variant = _g()
	if g == null:
		return
	g.cloud_online = false
	g.cloud_account = {}
	CloudSession.clear()
	var ui: Variant = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	for i in range(5):
		await process_frame
	ck(str(ui._current) == "tut_login", "先落登录页（实际 %s）" % str(ui._current))
	ck(_has_text(ui, "忘记密码"), "★ 登录页有「忘记密码？」入口")

	ui._open_forgot_panel()
	await process_frame
	ck(ui._forgot_layer != null, "★ 点开后弹层已创建")
	ck(ui._forgot_step == 0, "初始是第 0 步（还没发码）")
	ck(not ui._forgot_code.editable, "★ 没发码时验证码框**不可编辑**（不让人对着空框干点）")
	ck(not ui._forgot_pass.editable, "★ 没发码时新密码框不可编辑")
	ck(not ui._forgot_send_btn.disabled, "「发送验证码」可用")
	ck(ui._forgot_apply_btn.disabled, "★ 「重置密码」初始**禁用**")

	var sb: StyleBoxFlat = null
	for ch in ui._forgot_layer.get_children():
		if ch is PanelContainer:
			var st = (ch as PanelContainer).get_theme_stylebox("panel")
			if st is StyleBoxFlat:
				sb = st as StyleBoxFlat
	ck(sb != null, "弹层里有卡片")
	if sb != null:
		ck(is_equal_approx(sb.bg_color.a, 1.0), "★ 弹窗底色**不透明**（alpha=%.2f）" % sb.bg_color.a)
	ck(ui._forgot_layer.z_index == UiDesign.Z_OVERLAY,
		"弹层置顶（z_index=%d）" % ui._forgot_layer.z_index)

	# ③ 空昵称点发送 → 只提示、不发请求
	ui._forgot_name.text = ""
	ui._on_forgot_send()
	ck(str(ui._forgot_msg.text).find("昵称") >= 0,
		"空昵称时给出提示（实际「%s」）" % str(ui._forgot_msg.text))

	# ④ 服务端回「空掩码」= 该账号没绑邮箱 → 必须给出明确出路
	#    （老账号就是这个下场：过渡档里填了邮箱却没走验证码的，服务端存的是空）
	ui._forgot_name.text = "老账号"
	ui._on_forgot_send()
	ui._on_forgot_send_done(true, "")
	ck(str(ui._forgot_msg.text).find("没有绑定邮箱") >= 0,
		"★ 无绑定邮箱时明确告知（实际「%s」）" % str(ui._forgot_msg.text))
	ck(ui._forgot_step == 0, "这种情况**不进入第 1 步**（没码可填）")

	# ⑤ 正常发码 → 进入第 1 步，昵称锁定，码/密码解锁
	ui._forgot_name.text = "曹博文"
	ui._on_forgot_send()
	ui._on_forgot_send_done(true, "c***n@qq.com")
	ck(ui._forgot_step == 1, "★ 发码成功 → 进入第 1 步")
	ck(not ui._forgot_name.editable, "★ 昵称锁定（防中途改掉 → 第二步对不上账号）")
	ck(ui._forgot_code.editable and ui._forgot_pass.editable, "验证码与新密码解锁")
	ck(not ui._forgot_apply_btn.disabled, "「重置密码」启用")
	ck(str(ui._forgot_msg.text).find("c***n@qq.com") >= 0, "提示里带掩码邮箱（不泄露完整地址）")

	# ⑥ 本地校验：码位数 / 新密码长度
	ui._forgot_code.text = "12"
	ui._forgot_pass.text = "abcdef"
	ui._on_forgot_apply()
	ck(str(ui._forgot_msg.text).find("6 位") >= 0, "码不是 6 位 → 拦住")
	ui._forgot_code.text = "123456"
	ui._forgot_pass.text = "123"
	ui._on_forgot_apply()
	ck(str(ui._forgot_msg.text).find("6 位") >= 0, "新密码太短 → 拦住")

	# ⑦ 切面板必须收起弹层（它独立于面板叠加，不收起会盖在新面板上）
	ui._show_panel("start")
	await process_frame
	ck(ui._forgot_layer == null, "★ 切面板后弹层自动收起")

	ui.queue_free()
	await process_frame
