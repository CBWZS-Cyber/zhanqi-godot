extends SceneTree
## 英雄图鉴改造验证：卡片网格 + 详情弹窗 + 海报加载
## 运行：godot --headless --path . -s res://tests/hero_codex_check.gd

var _asserts := 0
var _fails := 0

func _ok(cond: bool, msg: String) -> void:
	_asserts += 1
	if cond:
		print("  [OK] " + msg)
	else:
		_fails += 1
		print("  [FAIL] " + msg)

func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r: Node = _find(c, cls)
		if r != null:
			return r
	return null

func _initialize() -> void:
	print("=== 英雄图鉴改造验证 ===")
	var packed: PackedScene = load("res://scenes/MainUI.tscn")
	var ui: Node = packed.instantiate()
	root.add_child(ui)
	await process_frame

	# ---- 1. 打开英雄图鉴卡片页 ----
	ui._open_codex("hero")
	await process_frame
	_ok(ui._codex_layer != null, "英雄图鉴层已创建")

	var grid: Node = _find(ui._codex_layer, "GridContainer")
	_ok(grid != null, "卡片网格 GridContainer 存在")
	if grid == null:
		_quit()
		return

	var cards: Array = grid.get_children()
	_ok(cards.size() == 11, "卡片数量 = 11（实际 %d）" % cards.size())

	# ---- 2. 每张卡片必须有头像贴图 ----
	var with_img := 0
	var missing: Array = []
	for c in cards:
		var tex: Node = _find(c, "TextureRect")
		var nm: Node = _find(c, "Label")
		if tex != null and tex.texture != null:
			with_img += 1
		else:
			missing.append(str(nm.text) if nm != null else "?")
	_ok(with_img == cards.size(), "全部卡片都有头像贴图（%d/%d，缺：%s）" % [with_img, cards.size(), "无" if missing.is_empty() else str(missing)])

	# ---- 3. 点击卡片打开详情 ----
	ui._open_hero_detail("crystal_dragon")
	await process_frame
	_ok(ui._hero_detail_layer != null, "详情弹窗已创建")

	var poster = _find(ui._hero_detail_layer, "TextureRect")
	_ok(poster != null and poster.texture != null, "详情页海报贴图已加载")

	var rt = _find(ui._hero_detail_layer, "RichTextLabel")
	var txt := str(rt.text) if rt != null else ""
	_ok(txt.length() > 100, "详情文本非空（%d 字符）" % txt.length())
	_ok(txt.contains("基础属性"), "详情含「基础属性」段")
	_ok(txt.contains("被动"), "详情含「被动」段")
	_ok(txt.contains("技能 1") or txt.contains("技能1"), "详情含技能段")

	# ---- 4. 逐个英雄都能打开详情且有海报 ----
	var HD = load("res://scripts/combat/hero_defs.gd")
	var all_ok := true
	var no_img := []
	for id in HD.ALL:
		if id == "demo_hero":
			continue
		ui._open_hero_detail(id)
		await process_frame
		var p = _find(ui._hero_detail_layer, "TextureRect")
		if p == null or p.texture == null:
			all_ok = false
			no_img.append(id)
	_ok(all_ok, "11 个英雄详情都能加载海报（缺图：%s）" % ("无" if no_img.is_empty() else str(no_img)))

	# ---- 5. 关闭不报错 ----
	ui._close_hero_detail()
	await process_frame
	_ok(ui._hero_detail_layer == null, "详情层可正常关闭")
	ui._close_codex()
	await process_frame
	_ok(ui._codex_layer == null, "图鉴层可正常关闭")

	_quit()

func _quit() -> void:
	print("")
	print("断言 %d 条，失败 %d 条" % [_asserts, _fails])
	quit(1 if _fails > 0 else 0)
