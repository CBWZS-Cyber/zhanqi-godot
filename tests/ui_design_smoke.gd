extends SceneTree
## 战棋 · 设计系统回归（墨金令牌 / 全局主题 / 组件库）
## 用法：godot --headless --path 工程 -s res://tests/ui_design_smoke.gd
##
## 为什么要有这条测试：
##   2026-10-04 做的「墨金」令牌化，把 UI 层 373 处硬编码颜色收敛到 147 处。
##   这个改造最容易出的问题是**静默漂移** —— 有人为了"顺手好看一点"直接改
##   ui_design.gd 里的一个常量，全工程 20 个界面跟着变，没有任何测试会发现。
##   所以这里把「值」和「可读性」都钉死：
##
##   A. 令牌锚点   —— 值必须等于迁移前的原值（防漂移）
##   B. WCAG 对比度 —— 文字在对应底色上必须达标（防不可读）
##   C. 色阶单调   —— 墨阶/金阶亮度必须单调（防插错位置）
##   D. 铁律       —— 弹窗底色必须不透明
##   E. 迁移完整性 —— 界面脚本里不许再出现核心语义色的字面量
##   F. 全局主题   —— 焦点环 / 输入框聚焦态 / 弹窗面板（原先完全缺失）
##   G. 组件库     —— 主 CTA 用金、三态互异、主题接入幂等
##   H. 资源条四色 —— 生命/护盾/能量/理智两两可区分（用户实报要求）
##   I. 字体       —— 三档：毛笔主视觉 / 宋体小标题 / 黑体正文（含字距）
##   J. bbcode 调色板 —— 与 Color 令牌同源，且不许出现「深底深字」
##
## 全部通过 exit 0，有失败 exit 1。

# 直接用全局类名（UiDesign / UiTheme）。注意：不能 preload 后用 UiDesign.xxx() 调静态函数——
# preload 拿到的是 GDScript 资源，只有**常量**能从它上面取，静态函数取不到。

var _passes := 0
var _fails := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  ✓ ", name)
	else:
		_fails += 1
		printerr("  ✗ FAIL: ", name)


# ---------------- K. 层级（z_index）：弹层必须压住棋子 ----------------

## 用户 2026-10-05 实报「人物显示在设置弹窗上面」。
##
## 根因：Godot 同层节点**先比 z_index、再比树顺序**。棋子相关节点自带 z_index
## （头顶名字 120 / 击破特效 110 / DragonBones 骨骼部件由数据给），而弹层原先
## **一个都没设**（默认 0）→ 棋子就画在弹窗之上。
## `unit_info_popup` 早就踩过这个坑、并单独写死了 4096，但 `SettingsLayer` 与
## 教程的挖洞遮罩**没跟上** —— 于是同一个 bug 又犯了一次。
##
## 这条做两件事：① 钉住"弹层层级 > 所有棋子层级"这个不变量；
## ② 扫描各战斗/菜单界面的源码，确保都走 `UiDesign.Z_OVERLAY`，不再写死数字。
func _test_layers() -> void:
	print("【K】层级：弹层必须高于棋子（用户实报「人物显示在设置弹窗上面」）")
	ck(UiDesign.Z_OVERLAY == 4096, "Z_OVERLAY = 4096（Godot z_index 上限，够压住一切）")
	ck(UiDesign.Z_OVERLAY > UiDesign.Z_UNIT_LABEL,
		"弹层(%d) > 棋子名字标签(%d)" % [UiDesign.Z_OVERLAY, UiDesign.Z_UNIT_LABEL])
	ck(UiDesign.Z_OVERLAY > UiDesign.Z_UNIT_FX,
		"弹层(%d) > 棋子特效(%d)" % [UiDesign.Z_OVERLAY, UiDesign.Z_UNIT_FX])
	ck(UiDesign.Z_UNIT_LABEL > UiDesign.Z_UNIT_FX,
		"名字标签(%d) > 击破特效(%d)" % [UiDesign.Z_UNIT_LABEL, UiDesign.Z_UNIT_FX])

	var must: Dictionary = {
		"settings_layer": "局内设置（1V1 / 4V4 / 剧情关共用）",
		"tutorial": "教程挖洞遮罩",
		"unit_info_popup": "棋子信息浮层",
		"duel": "1V1 选人层",
		"team_duel": "4V4 蛇形选人层",
		"main_ui": "主菜单各弹层",
	}
	for f in must.keys():
		var fn := str(f)
		var src := FileAccess.get_file_as_string("res://scripts/ui/%s.gd" % fn)
		ck(src.length() > 0, "%s.gd 源码可读" % fn)
		ck(src.find("Z_OVERLAY") >= 0, "%s.gd 的弹层走 UiDesign.Z_OVERLAY（%s）" % [fn, str(must[f])])

	var ut := FileAccess.get_file_as_string("res://scripts/ui/unit_token.gd")
	ck(ut.find("Z_UNIT_LABEL") >= 0 and ut.find("Z_UNIT_FX") >= 0,
		"unit_token.gd 的棋子层级也走令牌")
	ck(ut.find("z_index = 120") < 0 and ut.find("z_index = 110") < 0,
		"unit_token.gd 里没有写死的 120 / 110")


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("== 设计系统回归（墨金令牌） ==")
	_test_anchor_values()
	_test_contrast()
	_test_ramps()
	_test_modal_opaque()
	_test_migration_complete()
	_test_theme()
	_test_component_library()
	_test_resource_colors()
	_test_fonts()
	_test_markup_palette()
	_test_layers()
	var dt := Time.get_ticks_msec() - t0
	print("== 设计系统结果: PASS %d / FAIL %d（%d ms）==" % [_passes, _fails, dt])
	quit(1 if _fails > 0 else 0)


# ---------------- A. 令牌锚点：值必须等于迁移前的原值 ----------------

func _test_anchor_values() -> void:
	print("【A】令牌锚点（等于迁移前的硬编码值，防静默改色）")
	# 这些是迁移前散落在 3~9 个文件里的原值，改动它们 = 全工程改色，必须是显式决定
	ck(UiDesign.GOLD_500.is_equal_approx(Color(0.941, 0.780, 0.369)), "GOLD_500 = 原 COL_GOLD（9 个文件里的同一个金）")
	ck(UiDesign.INK_100.is_equal_approx(Color(0.92, 0.95, 0.99)), "INK_100 = 原 UiKit.TEXT_COLOR")
	ck(UiDesign.INK_200.is_equal_approx(Color(0.84, 0.87, 0.92)), "INK_200 = 原 UiKit.TAG_COLOR")
	ck(UiDesign.INK_300.is_equal_approx(Color(0.68, 0.72, 0.80)), "INK_300 = 原 tutorial.COL_DIM")
	ck(UiDesign.INK_800.is_equal_approx(Color(0.10, 0.12, 0.19)), "INK_800 = 原 COL_PANEL 的 RGB（4 个文件一致）")
	ck(UiDesign.BTN_BG.is_equal_approx(Color(0.10, 0.12, 0.19, 0.9)), "BTN_BG = 原 UiKit 按钮 normal")
	ck(UiDesign.BTN_BG_HOVER.is_equal_approx(Color(0.20, 0.23, 0.36)), "BTN_BG_HOVER = 原 UiKit hover")
	ck(UiDesign.BTN_BG_PRESSED.is_equal_approx(Color(0.08, 0.09, 0.15)), "BTN_BG_PRESSED = 原 UiKit pressed")
	ck(UiDesign.ALLY.is_equal_approx(Color(0.78, 0.25, 0.18)), "ALLY = 原 COL_RED（我方=红，3 个文件一致）")
	ck(UiDesign.ENEMY.is_equal_approx(Color(0.24, 0.42, 0.75)), "ENEMY = 原 COL_BLUE")
	ck(UiDesign.HP.is_equal_approx(Color(0.42, 0.78, 0.36)), "HP = 原 hp_shield_bar.COL_HP")
	ck(UiDesign.SHIELD.is_equal_approx(Color(0.33, 0.68, 0.95)), "SHIELD = 原 hp_shield_bar.COL_SHIELD")
	ck(UiDesign.ENERGY.is_equal_approx(Color(0.85, 0.65, 0.25)),
		"ENERGY = 原**棋子迷你条**的琥珀（2026-10-04 有意由蓝改琥珀：与 SHIELD 蓝区分开）")
	ck(UiDesign.SANITY.is_equal_approx(Color(0.62, 0.48, 0.82)), "SANITY = 原 tutorial.COL_SANITY")
	ck(UiDesign.BOARD_BG.is_equal_approx(Color(0.20, 0.18, 0.16)), "BOARD_BG = 原 COL_BG（4 个文件一致）")
	ck(UiDesign.BOARD_LIGHT.is_equal_approx(Color(0.93, 0.87, 0.74)), "BOARD_LIGHT = 原 COL_LIGHT")
	ck(UiDesign.BOARD_DARK.is_equal_approx(Color(0.55, 0.40, 0.28)), "BOARD_DARK = 原 COL_DARK")
	ck(UiDesign.SPAWN.is_equal_approx(Color(0.40, 0.56, 0.74)), "SPAWN = 原 COL_WING（x==0 / x==4 出生格）")
	ck(UiDesign.CELL_HL_MOVE.is_equal_approx(Color(0.45, 0.85, 0.45)), "CELL_HL_MOVE = 原 COL_MOVE")
	ck(UiDesign.CELL_HL_CAST.is_equal_approx(Color(0.95, 0.80, 0.30)), "CELL_HL_CAST = 原 COL_CAST")
	ck(UiDesign.APP_BG.is_equal_approx(Color(0.102, 0.125, 0.208)), "APP_BG = 原 BG_COLOR")
	ck(UiDesign.SURFACE_PANEL.is_equal_approx(Color(0.10, 0.12, 0.19, 0.94)), "SURFACE_PANEL = 原 COL_PANEL")
	ck(UiDesign.OVERLAY_DIM.is_equal_approx(Color(0.05, 0.07, 0.12, 0.45)), "OVERLAY_DIM = 原 MENU_BG_DIM")
	ck(UiDesign.BTN_TEXT_ON_GOLD.is_equal_approx(Color(0.12, 0.09, 0.05)), "BTN_TEXT_ON_GOLD = 原主按钮字色")
	ck(UiDesign.BORDER.is_equal_approx(Color(0.35, 0.32, 0.26)), "BORDER = 原 UiKit.PANEL_BORDER_COLOR")


# ---------------- B. WCAG 对比度 ----------------

func _test_contrast() -> void:
	print("【B】WCAG 对比度（AA 正文 4.5 / 大字与图形 3.0）")
	var card: Color = UiDesign.SURFACE_CARD
	# 正文级：4.5
	var text_tokens := {"INK_100": UiDesign.INK_100, "INK_200": UiDesign.INK_200,
		"INK_250": UiDesign.INK_250, "INK_300": UiDesign.INK_300, "INK_400（占位符）": UiDesign.INK_400}
	for k in text_tokens.keys():
		var c: float = UiDesign.contrast(text_tokens[k], card)
		ck(c >= 4.5, "%s 在卡片底 %.2f ≥ 4.5（AA 正文）" % [str(k), c])
	# 弹窗（不透明底）
	var modal_tokens := {"INK_100": UiDesign.INK_100, "INK_200": UiDesign.INK_200, "INK_300": UiDesign.INK_300}
	for k in modal_tokens.keys():
		var c: float = UiDesign.contrast(modal_tokens[k], UiDesign.SURFACE_MODAL)
		ck(c >= 4.5, "%s 在弹窗底 %.2f ≥ 4.5" % [str(k), c])
	# 金
	var c1: float = UiDesign.contrast(UiDesign.BTN_TEXT_ON_GOLD, UiDesign.GOLD_500)
	ck(c1 >= 4.5, "金底深字 %.2f ≥ 4.5（主 CTA 可读）" % c1)
	var c2: float = UiDesign.contrast(UiDesign.GOLD_500, UiDesign.APP_BG)
	ck(c2 >= 4.5, "金色标题在菜单底 %.2f ≥ 4.5" % c2)
	# ★ 实测发现的边界：阵营色只能当「图形」，不能当正文
	var ca: float = UiDesign.contrast(UiDesign.ALLY, card)
	var ce: float = UiDesign.contrast(UiDesign.ENEMY, card)
	ck(ca >= 3.0, "ALLY 在卡片底 %.2f ≥ 3.0（图形级；**不可当正文用**）" % ca)
	ck(ce >= 3.0, "ENEMY 在卡片底 %.2f ≥ 3.0（图形级；**不可当正文用**）" % ce)
	ck(ca < 4.5 and ce < 4.5,
		"已知：阵营色对卡片底**不足 4.5**（%.2f/%.2f）→ 需要文字时用 ALLY_SOFT/INK_100" % [ca, ce])
	# ★ 实测发现的边界：INK_500 只许做禁用态
	var c5: float = UiDesign.contrast(UiDesign.INK_500, card)
	ck(c5 >= 3.0, "INK_500 在卡片底 %.2f ≥ 3.0（禁用态下限）" % c5)
	ck(c5 < 4.5, "已知：INK_500 %.2f 不足 4.5 → **只许用于禁用态**，不可做正文" % c5)
	# 棋盘上的文字
	var cb: float = UiDesign.contrast(UiDesign.BOARD_TEXT, UiDesign.BOARD_LIGHT)
	ck(cb >= 4.5, "棋盘正文在浅格上 %.2f ≥ 4.5" % cb)
	# 相邻格子的区分度（3:1 是"可辨"下限）
	var cs: float = UiDesign.contrast(UiDesign.BOARD_LIGHT, UiDesign.BOARD_DARK)
	ck(cs >= 3.0, "浅格/深格区分度 %.2f ≥ 3.0" % cs)


# ---------------- C. 色阶单调性 ----------------

func _test_ramps() -> void:
	print("【C】色阶单调性（插错位置会让层级关系倒挂）")
	var ink_order: Array[Color] = [UiDesign.INK_950, UiDesign.INK_900, UiDesign.INK_800, UiDesign.INK_750, UiDesign.INK_700,
		UiDesign.INK_650, UiDesign.INK_600, UiDesign.INK_550, UiDesign.INK_500, UiDesign.INK_400,
		UiDesign.INK_300, UiDesign.INK_250, UiDesign.INK_200, UiDesign.INK_100, UiDesign.INK_050]
	var ok := true
	for i in range(1, ink_order.size()):
		if UiDesign.luminance(ink_order[i]) <= UiDesign.luminance(ink_order[i - 1]):
			ok = false
			printerr("      墨阶第 %d 级不递增" % (i + 1))
	ck(ok, "墨阶 950 → 050 亮度严格递增（共 %d 级）" % ink_order.size())

	var gold_order: Array[Color] = [UiDesign.GOLD_700, UiDesign.GOLD_600, UiDesign.GOLD_500,
		UiDesign.GOLD_400, UiDesign.GOLD_300, UiDesign.GOLD_200, UiDesign.GOLD_100]
	var ok2 := true
	for i in range(1, gold_order.size()):
		if UiDesign.luminance(gold_order[i]) <= UiDesign.luminance(gold_order[i - 1]):
			ok2 = false
	ck(ok2, "金阶 700 → 100 亮度严格递增（共 %d 级）" % gold_order.size())


# ---------------- D. 弹窗铁律 ----------------

func _test_modal_opaque() -> void:
	print("【D】弹窗背景必须不透明（用户铁律）")
	ck(is_equal_approx(UiDesign.SURFACE_MODAL.a, 1.0), "SURFACE_MODAL alpha = 1.0（不透明）")
	ck(is_equal_approx(UiDesign.SURFACE_CARD.a, 1.0), "SURFACE_CARD alpha = 1.0（卡片不透明）")
	ck(is_equal_approx(UiDesign.INK_900.a, 1.0), "INK_900 alpha = 1.0")
	# 侧栏是"棋盘上的浮层"，允许半透（要看得到棋盘），但必须明确区分
	ck(UiDesign.SURFACE_PANEL.a < 1.0, "SURFACE_PANEL 半透（对局侧栏，非弹窗）——与弹窗明确区分")
	ck(UiDesign.SURFACE_PANEL.a >= 0.9, "SURFACE_PANEL 半透但足够实（%.2f），压在棋盘上仍可读" % UiDesign.SURFACE_PANEL.a)


# ---------------- E. 迁移完整性 ----------------

## 核心语义色的字面量一旦重新出现，说明有人在界面文件里又写死了颜色。
## 允许保留的：纯透明/纯黑阴影等一次性装饰色（它们不是语义色）。
const _BANNED := [
	"Color(0.941,0.780,0.369)",   # 金
	"Color(0.10,0.12,0.19",       # 面板（任何 alpha）
	"Color(0.92,0.95,0.99)",      # 正文
	"Color(0.84,0.87,0.92)",      # 标签
	"Color(0.68,0.72,0.80)",      # 说明
	"Color(0.78,0.25,0.18)",      # 我方
	"Color(0.24,0.42,0.75)",      # 敌方
	"Color(0.20,0.18,0.16)",      # 棋盘底
	"Color(0.93,0.87,0.74)",      # 浅格
	"Color(0.55,0.40,0.28)",      # 深格
	"Color(0.45,0.85,0.45)",      # 移动高亮
	"Color(0.95,0.80,0.3)",       # 技能高亮
	"Color(0.35,0.32,0.26)",      # 面板描边
	"Color(0.45,0.42,0.30)",      # 按钮描边
]

## 迁移后的字面量总数上限（当前 147）。涨过这个数说明在开倒车。
const _LITERAL_CEILING := 170


func _test_migration_complete() -> void:
	print("【E】迁移完整性（界面文件里不许再写核心语义色）")
	var dir := DirAccess.open("res://scripts/ui")
	if dir == null:
		print("  （跳过：拿不到 res://scripts/ui 目录）")
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "ui_design.gd" and f != "ui_theme.gd":
			names.append(f)
	names.sort()
	ck(names.size() > 0, "读到 %d 个界面脚本" % names.size())

	var banned_hits: Array = []
	var literal_total := 0
	var pat := RegEx.new()
	pat.compile("Color\\([0-9.,\\s]+\\)")
	for fn in names:
		var fh := FileAccess.open("res://scripts/ui/" + str(fn), FileAccess.READ)
		if fh == null:
			continue
		var raw := fh.get_as_text()
		fh.close()
		var flat := raw.replace(" ", "").replace("\t", "").replace("\n", "")
		for b in _BANNED:
			if flat.find(str(b)) >= 0:
				banned_hits.append("%s 里有 %s" % [str(fn), str(b)])
		literal_total += pat.search_all(raw).size()

	for h in banned_hits:
		printerr("      ", h)
	ck(banned_hits.is_empty(), "14 个核心语义色在界面脚本里**零残留**（扫了 %d 个文件）" % names.size())
	ck(literal_total <= _LITERAL_CEILING,
		"字面量总数 %d ≤ 上限 %d（迁移前 373）" % [literal_total, _LITERAL_CEILING])
	print("      （现存字面量 %d 处，均为一次性装饰色/透明遮罩）" % literal_total)


# ---------------- F. 全局主题 ----------------

func _test_theme() -> void:
	print("【F】全局主题（焦点环等原先完全缺失的部分）")
	var t: Theme = UiTheme.build()
	ck(t != null, "Theme 构建成功")
	ck(t.default_font_size == UiDesign.FS_BASE, "默认字号 = FS_BASE(%d)" % UiDesign.FS_BASE)

	# ★ 焦点环：工程原先**任何控件都没有 focus 样式**，键盘/手柄看不出选中谁
	var bf: StyleBox = t.get_stylebox("focus", "Button")
	ck(bf != null, "Button 有 focus 样式（原先没有）")
	if bf is StyleBoxFlat:
		var sbf := bf as StyleBoxFlat
		ck(not sbf.draw_center, "Button 焦点环只画框、不填色（不遮住按钮本身）")
		ck(sbf.border_color.is_equal_approx(UiDesign.FOCUS), "Button 焦点环颜色 = FOCUS")

	var ef: StyleBox = t.get_stylebox("focus", "LineEdit")
	var en: StyleBox = t.get_stylebox("normal", "LineEdit")
	ck(ef != null and en != null, "LineEdit 有 normal + focus 两态（原先两态一样，看不出点没点进去）")
	if ef is StyleBoxFlat and en is StyleBoxFlat:
		ck(not (ef as StyleBoxFlat).border_color.is_equal_approx((en as StyleBoxFlat).border_color),
			"LineEdit 聚焦时描边变色（%s → %s）" % [
				UiDesign.to_hex((en as StyleBoxFlat).border_color), UiDesign.to_hex((ef as StyleBoxFlat).border_color)])

	# 弹窗类控件必须不透明
	for pair in [["TooltipPanel", "panel"], ["PopupMenu", "panel"]]:
		var sb: StyleBox = t.get_stylebox(str(pair[1]), str(pair[0]))
		ck(sb != null, "%s 有样式（原先吃引擎默认皮肤）" % str(pair[0]))
		if sb is StyleBoxFlat:
			ck(is_equal_approx((sb as StyleBoxFlat).bg_color.a, 1.0),
				"%s 面板不透明（弹窗铁律）" % str(pair[0]))

	var card_sb: StyleBox = t.get_stylebox("panel", "PanelContainer")
	if card_sb is StyleBoxFlat:
		ck((card_sb as StyleBoxFlat).shadow_size > 0, "卡片带投影（与背景拉开层次）")
	ck(t.get_stylebox("background", "ProgressBar") != null, "ProgressBar 底槽已统一")
	ck(t.get_stylebox("grabber", "VScrollBar") != null, "滚动条 grabber 已统一")


# ---------------- G. 组件库 ----------------

func _test_component_library() -> void:
	print("【G】组件库（主 CTA 金 / 三态互异 / 接入幂等）")

	var b := Button.new()
	UiTheme.style_button(b, UiTheme.KIND_PRIMARY)
	var n: StyleBox = b.get_theme_stylebox("normal")
	var h: StyleBox = b.get_theme_stylebox("hover")
	var p: StyleBox = b.get_theme_stylebox("pressed")
	ck(n is StyleBoxFlat, "主 CTA 有 normal 样式")
	if n is StyleBoxFlat:
		ck((n as StyleBoxFlat).bg_color.is_equal_approx(UiDesign.GOLD_500), "主 CTA 底色 = GOLD_500（全屏唯一金）")
	ck(h is StyleBoxFlat and p is StyleBoxFlat, "主 CTA 有 hover / pressed")
	if n is StyleBoxFlat and h is StyleBoxFlat and p is StyleBoxFlat:
		var c1 := (n as StyleBoxFlat).bg_color
		var c2 := (h as StyleBoxFlat).bg_color
		var c3 := (p as StyleBoxFlat).bg_color
		ck(not c1.is_equal_approx(c2) and not c2.is_equal_approx(c3) and not c1.is_equal_approx(c3),
			"三态底色互不相同")
	ck(b.get_theme_color("font_color").is_equal_approx(UiDesign.BTN_TEXT_ON_GOLD), "主 CTA 字色 = 金底深字")
	ck(b.get_theme_stylebox("focus") != null, "主 CTA 也有焦点环")

	var b2 := Button.new()
	UiTheme.style_button(b2, UiTheme.KIND_SECONDARY)
	if b2.get_theme_stylebox("normal") is StyleBoxFlat:
		var c := (b2.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
		ck(not c.is_equal_approx(UiDesign.GOLD_500), "次级按钮**不用金**（金只留给主 CTA）")
		b.free()
		b2.free()
	else:
		b.free()
		b2.free()

	# 输入框组件
	var e := LineEdit.new()
	UiTheme.style_input(e, 420.0, 48.0)
	ck(e.get_theme_stylebox("focus") != null, "style_input 给出聚焦态")
	ck(e.has_meta("min_x") and is_equal_approx(float(e.get_meta("min_x")), 420.0),
		"style_input 写入 min_x 供 _fit 缩放")
	e.free()

	# 接入幂等：同一个 Theme 实例，重复 attach 不重建
	var n1 := Control.new()
	var n2 := Control.new()
	UiTheme.attach(n1)
	UiTheme.attach(n1)
	UiTheme.attach(n2)
	ck(n1.theme != null and n1.theme == n2.theme, "attach 幂等且全局共用同一 Theme 实例")
	n1.free()
	n2.free()


# ---------------- H. 资源条四色必须互相可区分 ----------------

## 用户 2026-10-04 实报「生命值、盾、能量值要做区分」。
## 根因：同一个「能量」有三种颜色（侧栏 COL_BLUE / 教程蓝 / 迷你条琥珀），
## 而且护盾与旧能量都是蓝、几乎同色 —— 盾和能量根本分不出。
## 这条断言把「四色四义」钉死：任意两色的**最大通道差**必须 ≥ 0.25。
const _RES_MIN_GAP := 0.25

func _test_resource_colors() -> void:
	print("【H】资源条四色必须互相可区分（生命/护盾/能量/理智）")
	var pal := {"HP": UiDesign.HP, "SHIELD": UiDesign.SHIELD,
		"ENERGY": UiDesign.ENERGY, "SANITY": UiDesign.SANITY}
	var keys: Array = pal.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Color = pal[keys[i]]
			var b: Color = pal[keys[j]]
			var d: float = maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			ck(d >= _RES_MIN_GAP, "%s vs %s 通道差 %.2f ≥ %.2f" % [keys[i], keys[j], d, _RES_MIN_GAP])
	# 能量**不能**再等于敌方阵营蓝（历史 bug：侧栏能量条用的就是 COL_BLUE）
	var de: float = maxf(maxf(absf(UiDesign.ENERGY.r - UiDesign.ENEMY.r),
		absf(UiDesign.ENERGY.g - UiDesign.ENEMY.g)), absf(UiDesign.ENERGY.b - UiDesign.ENEMY.b))
	ck(de >= _RES_MIN_GAP, "能量 ≠ 敌方阵营蓝（通道差 %.2f）" % de)
	# 每条资源色对底槽都要看得出来（细条最窄只有 3px）
	for k in keys:
		var c: float = UiDesign.contrast(pal[k], UiDesign.BAR_TRACK)
		ck(c >= 3.0, "%s 对底槽 %.2f ≥ 3.0（细条也要看得见）" % [str(k), c])


# ---------------- I. 字体 ----------------

## 正文走系统黑体链（0 体积），标题走打包的毛笔楷书 + 字距。
## 钉住三件事：① 字体真的加载了（否则标题会静默变回黑体，没人会发现）；
## ② 小字**必须**回落正文（毛笔小字会糊成一团）；
## ③ 字距随字号缩放。


func _test_fonts() -> void:
	print("【I】字体三档（毛笔主视觉 / 宋体小标题 / 黑体正文）")
	var rep: Dictionary = UiTheme.font_report()
	for k in ["hero", "title", "body"]:
		ck(bool(rep.get(k, false)), "打包字体已加载：%s" % str(k))

	var body: Font = UiTheme.body_font()
	ck(body != null, "正文字体可用（思源黑体）")
	var medium: Font = UiTheme.body_font(UiTheme.W_MEDIUM)
	ck(medium is FontVariation, "可变字重生效：Medium 是 FontVariation（按钮用）")
	ck((medium as FontVariation).variation_opentype.get("wght", 0) == UiTheme.W_MEDIUM,
		"Medium 的 wght = %d" % UiTheme.W_MEDIUM)

	# 三档的判定阈值
	var f_hero: Font = UiTheme.title_font(UiDesign.FS_HERO)        # 80 → 毛笔
	var f_serif: Font = UiTheme.title_font(UiDesign.FS_2XL)        # 24 → 宋体
	var f_body: Font = UiTheme.title_font(UiDesign.FS_XL)          # 20 → 正文
	ck(f_hero is FontVariation, "80px 走毛笔体（带字距的 FontVariation）")
	ck(f_serif == UiTheme.serif_font(), "24px 走宋体档")
	ck(f_body == body, "20px 回落到正文字体（< %d 不用宋体）" % UiTheme.TITLE_MIN_SIZE)
	ck(f_hero != f_serif and f_serif != f_body, "三档互不相同")
	if f_hero is FontVariation:
		var fv := f_hero as FontVariation
		ck(fv.spacing_glyph > 0, "毛笔标题带字距（%d px）" % fv.spacing_glyph)
		var g60: int = (UiTheme.title_font(60) as FontVariation).spacing_glyph
		var g80: int = (UiTheme.title_font(80) as FontVariation).spacing_glyph
		ck(g80 >= g60, "字距随字号不缩（60px→%d，80px→%d）" % [g60, g80])
	var th: Theme = UiTheme.build()
	ck(th.default_font == body, "Theme.default_font = 正文（控件默认吃到）")
	ck(th.get_font("font", "Button") != body, "按钮用 Medium（与正文拉开一档）")


# ---------------- J. bbcode 调色板（RichTextLabel 内联色） ----------------

## bbcode 只能吃 `#RRGGBB` 字符串，所以调色板以 `UiDesign.MD_*` 字符串常量形式存在。
## 这里钉两件事：
##   ① 每个 MD_* 与它的 Color 令牌**同源** —— 改令牌漏改调色板就红；
##   ② **所有界面脚本里的 `color=#` 都必须对卡片底 ≥3.0 对比度**。
##      这条是 2026-10-04 把图鉴/详情面板转深色时踩出来的：那些正文原来配的是**纸面深色**
##      （#2e6b3c / #7a5a10 / #55504a / #403a2e …），面板一变深就成了「深底深字」，
##      一个字都看不见 —— 而这类问题**渲染之前完全无法察觉**，必须靠扫描兜住。
func _test_markup_palette() -> void:
	print("【J】bbcode 调色板（与令牌同源 + 不允许深底深字）")
	var pairs := [
		["MD_OK", UiDesign.MD_OK, UiDesign.OK],
		["MD_GOLD", UiDesign.MD_GOLD, UiDesign.GOLD_400],
		["MD_HL", UiDesign.MD_HL, UiDesign.GOLD_HL],
		["MD_DIM", UiDesign.MD_DIM, UiDesign.INK_300],
		["MD_MUTED", UiDesign.MD_MUTED, UiDesign.INK_400],
		["MD_INFO", UiDesign.MD_INFO, UiDesign.INFO],
		["MD_WARN", UiDesign.MD_WARN, UiDesign.ALLY_SOFT],
	]
	for row in pairs:
		var got := str(row[1]).to_upper()
		var want := UiDesign.to_hex(row[2]).to_upper()
		ck(got == want, "%s = %s 与令牌同源" % [str(row[0]), got])

	var dir := DirAccess.open("res://scripts/ui")
	if dir == null:
		print("  （跳过扫描：拿不到 res://scripts/ui）")
		return
	var pat := RegEx.new()
	pat.compile("color=#([0-9a-fA-F]{6})")
	var checked := 0
	var bad: Array = []
	for f in dir.get_files():
		if not str(f).ends_with(".gd"):
			continue
		var fh := FileAccess.open("res://scripts/ui/" + str(f), FileAccess.READ)
		if fh == null:
			continue
		var raw := fh.get_as_text()
		fh.close()
		for m in pat.search_all(raw):
			var hex := "#" + m.get_string(1)
			checked += 1
			var c: float = UiDesign.contrast(Color(hex), UiDesign.SURFACE_CARD)
			if c < 3.0:
				bad.append("%s 里的 %s 对比度仅 %.2f" % [str(f), hex, c])
	for b in bad:
		printerr("      ", b)
	ck(checked >= 50, "扫到 %d 处 bbcode 内联色（≥50 才算真扫到了）" % checked)
	ck(bad.is_empty(), "全部 bbcode 色对卡片底 ≥3.0（深底深字 0 处，共扫 %d 处）" % checked)
