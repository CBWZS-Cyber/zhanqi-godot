extends SceneTree
## 1V1 选人界面布局回归（2026-10-05 新增）
##
## 【为什么单独一条】
##   用户实报：「1v1 选人界面，开始对战按钮没显示全」，并建议
##   「人物弹窗搞小一点，可以滚动浏览」。
##   根因：选人层是**全屏直排 VBox** —— 11 个英雄 × 2 列 = 6 行 ≈ 440px，
##   加标题/副标题/已选提示/按钮/间距 ≈ 650px，而基准视口 720 减掉上下边距只剩 668px。
##   **只剩 40px 余量**，Debug 窗口稍矮（窗口模式常不是满高）就把「开 始 对 战」
##   挤出视口底部 —— 按钮还在，只是看不到、点不到。
##
## 【钉住什么（都是这个 bug 的可测特征）】
##   ① 「开始对战」按钮**完整落在视口内**（上沿 ≥ 0 且下沿 ≤ 视口高）
##   ② 英雄区是**纵向可滚、横向不滚**的 ScrollContainer，且 `size_flags_vertical = EXPAND_FILL`
##      —— 滚动区吃掉「剩余空间」= 按钮被钉在底部，以后英雄再多也挤不到它
##
## ⚠️ 不能写 `Global.xxx`（`-s` 模式下 autoload 在脚本里编不过，会整个测试起不来，
##    见 README 注意点 27）。所以这里一律通过**场景实例化 + 节点查找**来断言。

var _passes := 0
var _fails := 0

const V_SCROLL_MIN_H := 80.0   # 滚动区至少要有这么高，否则等于白设

func _initialize() -> void:
	await _run()

func _run() -> void:
	print("【1V1 选人界面】「开始对战」必须完整可见 + 英雄区可滚动")
	var ps: PackedScene = load("res://scenes/Duel.tscn")
	ck(ps != null, "Duel 场景可加载")
	if ps == null:
		_report()
		return
	var d: Variant = ps.instantiate()
	root.add_child(d)
	for i in range(6):
		await process_frame

	var ov: Node = d.find_child("SelectOverlay", true, false)
	ck(ov != null, "选人层 SelectOverlay 已创建（Duel._ready 默认进选人阶段）")
	if ov == null:
		d.queue_free()
		_report()
		return

	# ---- ① 英雄区可滚动 ----
	var sc: ScrollContainer = _find_scroll(ov)
	ck(sc != null, "英雄区套了 ScrollContainer（人物弹窗可滚动浏览）")
	if sc != null:
		ck(sc.size_flags_vertical == Control.SIZE_EXPAND_FILL,
			"滚动区竖向 EXPAND_FILL（吃掉剩余空间 → 按钮被固定在底部）")
		ck(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"横向不滚动（宽度放得下，不该出横向滚动条）")
		ck(sc.size.y >= V_SCROLL_MIN_H, "滚动区有实际高度（%.0f px）" % sc.size.y)
		ck(sc.get_child_count() == 1, "滚动区里恰好一个子节点（装两张英雄卡的那一行）")

	# ---- ② 「开始对战」完整落在视口内（用户报的那条）----
	var start: Button = _find_start(ov)
	ck(start != null, "找到「开始对战」按钮")
	if start != null:
		var vp: Vector2 = Vector2(root.get_visible_rect().size)
		var top: float = start.global_position.y
		var bottom: float = top + start.size.y
		ck(top >= -1.0, "按钮上沿在视口内（top=%.0f）" % top)
		ck(bottom <= vp.y + 1.0, "★ 按钮下沿不超出视口（bottom=%.1f ≤ 视口 %.0f）" % [bottom, vp.y])
		ck(start.size.y >= 40.0, "按钮高度够点（%.0f px）" % start.size.y)
		ck(start.visible, "按钮可见")

	# ---- ③ 内容变多也挤不走按钮（滚动区的真正价值）----
	# headless 下改 root.size 不改变视口（实测），所以没法直接缩小窗口复现。
	# 改测**等价且更强**的性质：把滚动区内容撑高 600px（= 再来十几个英雄），
	# 按钮位置必须**纹丝不动** —— 因为高度是被滚动区吸收的，不是被按钮让位的。
	if start != null and sc != null:
		var before: float = start.global_position.y
		var filler := Control.new()
		filler.custom_minimum_size = Vector2(0, 600)
		sc.get_child(0).add_child(filler)
		for i in range(4):
			await process_frame
		var after: float = start.global_position.y
		ck(absf(after - before) < 1.0,
			"★ 内容撑高 600px 后按钮位置不变（%.0f → %.0f）：高度由滚动区吸收，不是按钮让位" % [before, after])
		ck(sc.size.y < 600.0, "此时滚动区高度仍受限（%.0f px < 600）→ 内容超出会出纵向滚动条" % sc.size.y)
		filler.queue_free()
		await process_frame

	d.queue_free()
	await process_frame
	_report()

func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n as ScrollContainer
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null

## 找「开 始 对 战」（文本里带"开"和"战"，中间的空格不算）
func _find_start(n: Node) -> Button:
	if n is Button:
		var t := str((n as Button).text)
		if t.find("开") >= 0 and t.find("战") >= 0:
			return n as Button
	for c in n.get_children():
		var r := _find_start(c)
		if r != null:
			return r
	return null

func ck(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  ✓ %s" % name)
	else:
		_fails += 1
		print("  ✗ %s" % name)

func _report() -> void:
	print("== 选人界面回归结果: PASS %d / FAIL %d ==" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
