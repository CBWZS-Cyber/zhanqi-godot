extends SceneTree
## 主菜单 · `_fit()` 幂等回归（2026-10-04 建立）
## 用法：godot --headless --path 工程 -s res://tests/mainui_fit_smoke.gd
##
## 背景：用户实报「账号输入界面点了一下输入框就卡了」。
## 根因：`_fit()` 每帧**无条件**写控件 —— `add_theme_constant_override` /
## `add_theme_font_size_override` / `custom_minimum_size` / `position`。
## 这些 API **即使写入值相同**也会发通知（THEME_CHANGED / transform 变化），
## 于是整棵可见面板树每帧都被判为"变了"。而面板里一旦有**获得焦点的 LineEdit**，
## 祖先的 transform 通知会让它每帧更新**输入法候选窗位置** —— 中文输入法下同步卡死。
##
## ⚠️ 这个 bug 的**症状**（卡死）在 headless 下复现不出来（无窗口、无 IME）。
## 所以本测试钉的是它的**可测特征**：`fit_writes`（实际写入次数）在静止后必须停止增长。
## 只要有人再往 _fit / _apply_node_sizes 里加"无条件写"，这里就会红。
##
## 全部通过 exit 0，有失败 exit 1。

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
	print("【主菜单 _fit 幂等】")

	var ui = load("res://scenes/MainUI.tscn").instantiate()
	root.add_child(ui)
	for i in range(6):
		await process_frame

	ck(ui.has_method("_fit"), "MainUI 有 _fit")
	ck(ui.fit_writes >= 0, "有 fit_writes 诊断计数")
	ui._show_panel("tut_login")

	# ⚠️ 必须先等首次布局收敛再开始计数。
	#    `_show_panel()` 是同步的，但它切换可见性后，容器的 `get_combined_minimum_size()`
	#    要到下一帧才结算完 —— 于是 `_fit()` 会有 1~2 次「从 0 收敛到实际值」的写入。
	#    那不是 bug，是冷启动。
	#    ⚠️ 更要紧的是：**切过去时是否产生这批写入，取决于之前显示的是哪个面板**，
	#    而默认面板由 `_ready` 的 `_initial_panel()` 决定（有登录态 / 有离线进度 → 主菜单，否则登录页）——
	#    也就是**取决于 user:// 里有没有账号**。等 4 帧后，本测试就与 user:// 状态无关了。
	for i in range(4):
		await process_frame

	# ---- ① 静止后必须零写入（幂等的核心）----
	var w0 := await measure(ui, 60)
	ck(w0 == 0, "账号面板静止 60 帧：零写入（实际 %d 次）" % w0)
	var w0b := await measure(ui, 60)
	ck(w0b == 0, "再 60 帧仍是零写入（实际 %d 次）" % w0b)

	# ---- ② 输入框获得焦点后仍然零写入 ← 直接对应这个 bug ----
	var card: Control = ui._panels["tut_login"]
	var e = ui._login_name
	ck(e != null, "账号面板有昵称输入框")
	var sz0: Vector2 = card.size
	var pos0: Vector2 = card.position
	var emin0: Vector2 = e.custom_minimum_size
	e.grab_focus()
	await process_frame
	ck(e.has_focus(), "输入框已聚焦")
	var w1 := await measure(ui, 60)
	ck(w1 == 0, "★ 输入框有焦点时静止 60 帧：零写入（实际 %d 次）" % w1)
	ck(card.size == sz0 and card.position == pos0,
		"★ 焦点状态下卡片尺寸/位置没有被反复改写（%s / %s）" % [str(card.size), str(card.position)])
	ck(e.custom_minimum_size == emin0, "★ 输入框最小尺寸没有被反复改写")

	# 打字时也不该触发布局写入（文本变化不改变面板几何）
	e.text = "测试账号"
	var w2 := await measure(ui, 40)
	ck(w2 == 0, "打字时也不产生布局写入（实际 %d 次）" % w2)

	# ---- ③ 换面板仍要正常生效（幂等不能把功能一起干掉）----
	# ⚠️ 这里**不数写入次数**。原来的断言「切面板必须产生写入」是错的：
	#    切到一个**已经算过尺寸**的面板（比如 start —— 只要 user:// 里已有账号，
	#    `_ready` 默认显示的就是它）本来就不该写，那正是幂等想要的效果。
	#    幂等的反面是「该写的时候不写」，所以改成直接验**功能结果**：可见性 / 尺寸 / 居中。
	ui._show_panel("start")
	for i in range(4):
		await process_frame
	var sp: Control = ui._panels["start"]
	ck(sp.visible and not (ui._panels["tut_login"] as Control).visible, "切面板后可见性正确")
	ck(sp.size.x > 0.0 and sp.size.y > 0.0, "切到 start 后尺寸已被设置（%s）" % str(sp.size))
	var vp1: Vector2 = ui.get_viewport_rect().size
	var cd1: Vector2 = (sp.position + sp.size / 2.0) - vp1 / 2.0
	ck(cd1.length() < 1.5, "切到 start 后卡片居中（偏移 %.2f px）" % cd1.length())
	var w3 := await measure(ui, 60)
	ck(w3 == 0, "切到开始界面后静止 60 帧：零写入（实际 %d 次）" % w3)

	# ---- ④ 「变了才写」而不是「永远不写」----
	# ⚠️ 不能在 headless 下改 root.size 来验缩放：headless 的视口恒为项目默认的 1280×720，
	#    赋值不生效（实测 `root.size = Vector2i(1024,640)` 后 get_viewport_rect().size 仍是 1280×720）。
	#    所以改成**直接破坏缓存**来证明重算路径还活着。
	var cf: Dictionary = ui._confs[0]
	cf["_t_separation"] = -12345
	var w3b := await measure(ui, 3)
	ck(w3b > 0, "缓存被破坏后会重新写入（说明是「变了才写」不是「永远不写」）")
	var w3c := await measure(ui, 60)
	ck(w3c == 0, "重算完又回到零写入（实际 %d 次）" % w3c)

	# ---- ⑤ 缩放仍在生效：字号应等于 meta 值 × _scale ----
	var p: Control = ui._panels["start"]
	var vp: Vector2 = ui.get_viewport_rect().size
	var scale_now: float = ui._scale
	var title_lab: Label = null
	for ch in p.get_children():
		if ch is VBoxContainer:
			for c2 in ch.get_children():
				if c2 is Label and c2.has_meta("fz") and float(c2.get_meta("fz")) >= 80.0:
					title_lab = c2
	ck(title_lab != null, "找到标题 Label（fz meta ≥ 80）")
	if title_lab != null:
		var want_fz: int = maxi(8, int(round(float(title_lab.get_meta("fz")) * scale_now)))
		ck(int(title_lab.get_theme_font_size("font_size")) == want_fz,
			"标题字号 = meta(%.0f) × scale(%.3f) = %d（实际 %d）"
				% [float(title_lab.get_meta("fz")), scale_now, want_fz,
					int(title_lab.get_theme_font_size("font_size"))])

	# ---- ⑥ 卡片仍居中 ----
	p = ui._panels["start"]
	var center_delta: Vector2 = (p.position + p.size / 2.0) - vp / 2.0
	ck(center_delta.length() < 1.5,
		"卡片仍居中（偏移 %.2f px，卡片 %s / 视口 %s、scale %.3f）"
			% [center_delta.length(), str(p.size), str(vp), scale_now])

	# ---- ⑦ 「新手教程」的归位（2026-10-05 用户要求）----
	# 它从**主按钮列**移到了下方的「图鉴 / 介绍」次级工具条，整条工具条也收小了一档。
	# 直接读控件 meta（设计值，不受 _scale 影响）—— 谁把按钮挪回主列、或改回大号，这里就红。
	# ⚠️ start 面板里有**两个** HBoxContainer：账号行（标题下，只含 1 个按钮）
	#    和工具条（末尾，含 5 个）。所以不能"见到横排就收集"，要取**按钮最多的那个**。
	var main_names := []
	var tool_names := []
	var tool_xs := []
	var tool_box: HBoxContainer = null
	for ch in p.get_children():
		if ch is VBoxContainer:
			for c2 in ch.get_children():
				if c2 is Button:
					var b2 := c2 as Button
					if b2.has_meta("min_x") and float(b2.get_meta("min_x")) >= 300.0:
						main_names.append(str(b2.text))
				elif c2 is HBoxContainer:
					var hb := c2 as HBoxContainer
					var nb := 0
					for c3 in hb.get_children():
						if c3 is Button:
							nb += 1
					if nb > tool_names.size():
						tool_box = hb
						tool_names.clear()
						tool_xs.clear()
						for c3 in hb.get_children():
							if c3 is Button:
								var b3 := c3 as Button
								tool_names.append(str(b3.text))
								tool_xs.append(float(b3.get_meta("min_x")) if b3.has_meta("min_x") else 0.0)
	ck(tool_box != null, "找到工具条（按钮最多的横排）")
	ck(not main_names.has("新手教程"), "★ 主按钮列里没有「新手教程」（实际 %s）" % str(main_names))
	ck(main_names.has("开始游戏"), "主按钮列仍有「开始游戏」")
	ck(tool_names.has("新手教程"), "★ 工具条里有「新手教程」（实际 %s）" % str(tool_names))
	ck(tool_names.size() == 5, "工具条共 5 个入口（新手教程 + 4 个图鉴/介绍），实际 %d" % tool_names.size())
	ck(tool_names.size() > 0 and str(tool_names[0]) == "新手教程",
		"「新手教程」排在工具条第一位（先引导、后查资料）")
	var max_tool_x := 0.0
	for x in tool_xs:
		max_tool_x = maxf(max_tool_x, float(x))
	ck(max_tool_x > 0.0 and max_tool_x < 200.0,
		"★ 工具条按钮明显小于主按钮（最大 %.0f < 200，主按钮 300）" % max_tool_x)
	var tool_total := 0.0
	for x in tool_xs:
		tool_total += float(x)
	tool_total += 12.0 * float(maxi(0, tool_xs.size() - 1))
	ck(tool_total + 56.0 * 2.0 <= vp.x,
		"工具条整条放得下（%.0f + 卡片边距 ≤ 视口 %.0f，不会被裁剪）" % [tool_total, vp.x])

	ui.queue_free()
	await process_frame
	print("== _fit 幂等结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## 等 frames 帧，返回这段时间内 fit_writes 的增量
func measure(ui, frames: int) -> int:
	var t0: int = ui.fit_writes
	for i in range(frames):
		await process_frame
	return int(ui.fit_writes) - t0
