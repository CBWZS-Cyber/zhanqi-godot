class_name UiTheme
extends RefCounted
## 由「墨金」令牌生成的全局 Theme + 组件库。
##
## ============================ 这个文件解决什么 ============================
## 工程原先**没有 Theme**（`find -name "*.theme"` 只找到编辑器自己的 tres），
## 所有样式靠 `add_theme_*_override` 逐控件手写 —— 于是：
##
##   · **没有焦点样式**：键盘/手柄操作时，界面上看不出"当前选中哪个控件"。
##     这是无障碍硬伤（WCAG 2.4.7 Focus Visible），也是手柄玩家的实际障碍。
##   · **LineEdit 没有聚焦反馈**：点进输入框和没点进去长得一样（用户实报过输入框问题）。
##   · **Tooltip / PopupMenu 用的是引擎默认皮肤**：和整体风格割裂。
##   · **ScrollBar / ProgressBar 未统一**：各界面各自为政。
##
## ============================ 与 override 的关系（重要） ============================
## Godot 的样式优先级是 **控件 override > Theme**。所以挂上本 Theme 之后：
##   · 已有 override 的控件 —— 外观不变（Migration 阶段由令牌统一接管颜色）
##   · 没有 override 的控件（Tooltip / 菜单 / 滚动条 / 焦点环）—— 立刻统一到墨金体系
## 也就是说：**挂 Theme 不会破坏任何既有观感**，只会补齐缺失的部分。
##
## ============================ 用法 ============================
##     func _ready() -> void:
##         UiTheme.attach(self)        # 幂等，重复调用无害

# ============================================================================
# 组件类型
# ============================================================================

const KIND_PRIMARY := "primary"     # 金底深字 —— 全屏**只允许一个**（主 CTA）
const KIND_SECONDARY := "secondary" # 墨底金边 —— 默认次级操作
const KIND_GHOST := "ghost"         # 无底透明 —— 低频/关闭类
const KIND_DANGER := "danger"       # 危险操作（删除/退出/清档）

static var _cache: Theme = null

# ============================================================================
# Theme 构建
# ============================================================================

static func build() -> Theme:
	if _cache != null:
		return _cache
	var t := Theme.new()
	t.default_font = body_font(W_REGULAR)   # 正文：思源黑体（打包，跨设备渲染一致）
	t.default_font_size = UiDesign.FS_BASE

	_theme_label(t)
	_theme_button(t)
	_theme_input(t)
	_theme_panels(t)
	_theme_bars(t)
	_theme_scroll(t)
	_theme_popups(t)
	_theme_misc(t)

	_cache = t
	return t


## 幂等接入：把主题挂到场景根（Control 或 Window 均可），全局生效。
static func attach(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var t := build()
	if root is Window:
		if (root as Window).theme != t:
			(root as Window).theme = t
	elif root is Control:
		if (root as Control).theme != t:
			(root as Control).theme = t


# ============================================================================
# 各控件族
# ============================================================================

static func _theme_label(t: Theme) -> void:
	t.set_color("font_color", "Label", UiDesign.INK_100)
	t.set_font_size("font_size", "Label", UiDesign.FS_BASE)
	t.set_color("default_color", "RichTextLabel", UiDesign.INK_100)
	t.set_font_size("normal_font_size", "RichTextLabel", UiDesign.FS_BASE)
	t.set_color("font_color", "RichTextLabel", UiDesign.INK_100)


static func _theme_button(t: Theme) -> void:
	t.set_font_size("font_size", "Button", UiDesign.FS_LG)
	# 按钮用 Medium：同样的字号下比正文（Regular）更有存在感，这是可变字重最划算的一处用法
	t.set_font("font", "Button", body_font(W_MEDIUM))
	t.set_stylebox("focus", "Button", UiDesign.focus_ring())
	# 默认给"次级"外观；主 CTA 由 style_button(b, KIND_PRIMARY) 覆盖
	var n := UiDesign.panel(UiDesign.BTN_BG, UiDesign.R_MD, UiDesign.BTN_BORDER)
	_margins(n, UiDesign.SPACE_LG, UiDesign.SPACE_SM)
	var h := UiDesign.panel(UiDesign.BTN_BG_HOVER, UiDesign.R_MD, UiDesign.BORDER_STRONG)
	_margins(h, UiDesign.SPACE_LG, UiDesign.SPACE_SM)
	var p := UiDesign.panel(UiDesign.BTN_BG_PRESSED, UiDesign.R_MD, UiDesign.GOLD_600)
	_margins(p, UiDesign.SPACE_LG, UiDesign.SPACE_SM)
	var d := UiDesign.panel(Color(UiDesign.INK_800.r, UiDesign.INK_800.g, UiDesign.INK_800.b, 0.55),
		UiDesign.R_MD, UiDesign.BORDER_SUBTLE, 0)
	_margins(d, UiDesign.SPACE_LG, UiDesign.SPACE_SM)
	t.set_stylebox("normal", "Button", n)
	t.set_stylebox("hover", "Button", h)
	t.set_stylebox("pressed", "Button", p)
	t.set_stylebox("disabled", "Button", d)
	t.set_color("font_color", "Button", UiDesign.BTN_TEXT)
	t.set_color("font_hover_color", "Button", UiDesign.BTN_TEXT_HOVER)
	t.set_color("font_pressed_color", "Button", UiDesign.GOLD_400)
	t.set_color("font_focus_color", "Button", UiDesign.BTN_TEXT)
	t.set_color("font_disabled_color", "Button", UiDesign.INK_500)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Button", 0)


static func _theme_input(t: Theme) -> void:
	t.set_font_size("font_size", "LineEdit", UiDesign.FS_LG)
	var n := UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.BORDER)
	_margins(n, UiDesign.SPACE_MD, UiDesign.SPACE_SM)
	# ★ 聚焦态：金环。这是"点进输入框看得出自己点进去了"的唯一保证。
	var f := UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.FOCUS, UiDesign.FOCUS_WIDTH)
	_margins(f, UiDesign.SPACE_MD, UiDesign.SPACE_SM)
	var r := UiDesign.panel(UiDesign.INK_950, UiDesign.R_MD, UiDesign.BORDER_SUBTLE)
	_margins(r, UiDesign.SPACE_MD, UiDesign.SPACE_SM)
	t.set_stylebox("normal", "LineEdit", n)
	t.set_stylebox("focus", "LineEdit", f)
	t.set_stylebox("read_only", "LineEdit", r)
	t.set_color("font_color", "LineEdit", UiDesign.INK_100)
	t.set_color("font_placeholder_color", "LineEdit", UiDesign.INK_400)
	t.set_color("font_selected_color", "LineEdit", UiDesign.INK_050)
	t.set_color("font_uneditable_color", "LineEdit", UiDesign.INK_500)
	t.set_color("caret_color", "LineEdit", UiDesign.GOLD_500)
	t.set_color("selection_color", "LineEdit", Color(UiDesign.GOLD_500.r, UiDesign.GOLD_500.g,
		UiDesign.GOLD_500.b, 0.34))
	t.set_stylebox("focus", "TextEdit", f)


static func _theme_panels(t: Theme) -> void:
	var card := UiDesign.panel(UiDesign.SURFACE_CARD, UiDesign.R_XL, UiDesign.BORDER)
	# 卡片带一点投影，和棋盘/背景拉开层次
	t.set_stylebox("panel", "PanelContainer", UiDesign.elevated(card, UiDesign.SHADOW_SM))
	t.set_stylebox("panel", "Panel", UiDesign.panel(UiDesign.SURFACE_CARD, UiDesign.R_LG, UiDesign.BORDER))
	# 对话框：**不透明** + 重投影（用户铁律）
	t.set_stylebox("panel", "AcceptDialog", UiDesign.elevated(
		UiDesign.panel(UiDesign.SURFACE_MODAL, UiDesign.R_2XL, UiDesign.BORDER_STRONG), UiDesign.SHADOW_LG))
	t.set_stylebox("panel", "Window", UiDesign.elevated(
		UiDesign.panel(UiDesign.SURFACE_MODAL, UiDesign.R_2XL, UiDesign.BORDER_STRONG), UiDesign.SHADOW_LG))


static func _theme_bars(t: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiDesign.BAR_TRACK
	bg.set_corner_radius_all(UiDesign.R_SM)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiDesign.HP
	fill.set_corner_radius_all(UiDesign.R_SM)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", UiDesign.BAR_NUM)
	t.set_font_size("font_size", "ProgressBar", UiDesign.FS_SM)

	t.set_stylebox("slider", "HSlider", bg)
	t.set_stylebox("grabber_area", "HSlider", fill)


static func _theme_scroll(t: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UiDesign.INK_950.r, UiDesign.INK_950.g, UiDesign.INK_950.b, 0.6)
	track.set_corner_radius_all(UiDesign.R_PILL)
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiDesign.INK_550
	grab.set_corner_radius_all(UiDesign.R_PILL)
	var grab_hl := StyleBoxFlat.new()
	grab_hl.bg_color = UiDesign.GOLD_600
	grab_hl.set_corner_radius_all(UiDesign.R_PILL)
	var grab_pr := StyleBoxFlat.new()
	grab_pr.bg_color = UiDesign.GOLD_500
	grab_pr.set_corner_radius_all(UiDesign.R_PILL)
	var empty := StyleBoxEmpty.new()
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grab)
		t.set_stylebox("grabber_highlight", bar, grab_hl)
		t.set_stylebox("grabber_pressed", bar, grab_pr)
		t.set_constant("minimum_grab_thickness", bar, 10)


static func _theme_popups(t: Theme) -> void:
	# Tooltip：不透明 + 金边（弹窗不透明是用户铁律，tooltip 也算弹窗）
	t.set_stylebox("panel", "TooltipPanel", UiDesign.elevated(
		UiDesign.panel(UiDesign.SURFACE_MODAL, UiDesign.R_MD, UiDesign.BORDER_STRONG), UiDesign.SHADOW_MD))
	# TooltipPanel 默认有 content_margin，这里给足呼吸
	var tp: StyleBoxFlat = t.get_stylebox("panel", "TooltipPanel")
	tp.content_margin_left = UiDesign.SPACE_MD
	tp.content_margin_right = UiDesign.SPACE_MD
	tp.content_margin_top = UiDesign.SPACE_SM
	tp.content_margin_bottom = UiDesign.SPACE_SM
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", UiDesign.INK_100)
	t.set_font_size("font_size", "TooltipLabel", UiDesign.FS_SM)

	# PopupMenu：不透明
	t.set_stylebox("panel", "PopupMenu", UiDesign.elevated(
		UiDesign.panel(UiDesign.SURFACE_MODAL, UiDesign.R_MD, UiDesign.BORDER), UiDesign.SHADOW_MD))
	t.set_color("font_color", "PopupMenu", UiDesign.INK_100)
	t.set_color("font_hover_color", "PopupMenu", UiDesign.GOLD_300)
	t.set_color("font_disabled_color", "PopupMenu", UiDesign.INK_500)
	t.set_color("font_separator_color", "PopupMenu", UiDesign.INK_400)
	t.set_font_size("font_size", "PopupMenu", UiDesign.FS_SM)
	var hl := StyleBoxFlat.new()
	hl.bg_color = Color(UiDesign.GOLD_500.r, UiDesign.GOLD_500.g, UiDesign.GOLD_500.b, 0.16)
	hl.set_corner_radius_all(UiDesign.R_XS)
	t.set_stylebox("hover", "PopupMenu", hl)


static func _theme_misc(t: Theme) -> void:
	var sep := StyleBoxLine.new()
	sep.color = UiDesign.BORDER_SUBTLE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "VSeparator", sep)
	t.set_color("font_color", "CheckBox", UiDesign.INK_100)
	t.set_color("font_hover_color", "CheckBox", UiDesign.GOLD_300)
	t.set_stylebox("focus", "CheckBox", UiDesign.focus_ring())
	t.set_color("font_color", "OptionButton", UiDesign.INK_100)
	t.set_color("font_color", "LinkButton", UiDesign.GOLD_400)
	t.set_color("font_hover_color", "LinkButton", UiDesign.GOLD_300)


# ============================================================================
# 字体（2026-10-04 三档制）
# ============================================================================
## **小字要清晰，大字要有性格。** 一副字体做不好这两件事，所以分三档：
##
## | 档位 | 字体 | 用在哪 | 体积 |
## |---|---|---|---|
## | **主视觉 hero** | 马善政毛笔楷书 | 只有超大字（≥60px）：主菜单「战棋」、结算/胜利标题 | 5.6 MB |
## | **标题 title** | 思源宋体 Bold | 面板标题、图鉴标题、章节名、关卡名、英雄名（≥22px） | 11.5 MB |
## | **正文 body** | 思源黑体（**可变字重 100–900**） | 正文、按钮、数值、标签、所有小字 | 17.0 MB |
##
## 为什么正文也打包（而不是继续用系统字体）：
##   ① 可变字重让我能真正做出**字重层次** —— 按钮 Medium(500)、强调 Bold(700)、
##      正文 Regular(400)。系统字体只能拿到一个 400，界面会显得"平"。
##   ② 跨设备一致：Windows 是微软雅黑、Android 是系统思源，**同一份设计渲染出来不一样**。
##      （用户 2026-10-04 明确："怎么美观怎么来，体积先不管太多"。）
##
## 三档之间**必须有字号差**才成立：毛笔 ≥60 ／ 宋体 ≥22 ／ 黑体 <22。
## 毛笔字在 22px 会糊成一团，宋体在 14px 也不如黑体清楚 —— 所以是硬阈值，不是偏好。
##
## ⚠️ 字体文件全部是 OFL 授权，**分发时必须随包附各自的 LICENSE-*.txt**。
## ⚠️ 任何一个文件缺失都必须**降级到系统字体**，绝不返回 null（否则整屏文字会消失）。

const FONT_HERO_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"    # 毛笔楷书
const FONT_TITLE_PATH := "res://assets/fonts/NotoSerifSC-Bold.otf"      # 思源宋体 Bold
const FONT_BODY_PATH := "res://assets/fonts/NotoSansSC-VF.ttf"          # 思源黑体（可变字重）

const HERO_MIN_SIZE := 60    ## ≥ 此字号才用毛笔体
const TITLE_MIN_SIZE := 22   ## ≥ 此字号（且 < HERO_MIN_SIZE）用宋体

## 字重（可口可取的档位；可变字体支持 100–900 连续值）
const W_REGULAR := 400
const W_MEDIUM := 500
const W_SEMIBOLD := 600
const W_BOLD := 700

const BODY_FONT_NAMES := ["Noto Sans SC", "Microsoft YaHei UI", "Microsoft YaHei",
	"PingFang SC", "Source Han Sans SC", "Heiti SC", "sans-serif"]

static var _hero: Font = null
static var _hero_tracked := {}
static var _title: Font = null
static var _body: Font = null
static var _body_weighted := {}
static var _system: Font = null


## 读打包字体；读到就用，读不到回 null（由调用方降级）。
static func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as Font if res is Font else null


## 系统字体兜底链。**只在打包字体缺失时使用。**
static func _system_font() -> Font:
	if _system == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(BODY_FONT_NAMES)
		sf.allow_system_fallback = true
		sf.font_weight = W_REGULAR
		_system = sf
	return _system


## 正文（思源黑体，可变字重）。[param weight] 取 W_REGULAR / W_MEDIUM / … 或任意 100–900。
## 用 `UiTheme.body_font(UiTheme.W_MEDIUM)` 给按钮、`W_BOLD` 给强调。
static func body_font(weight: int = W_REGULAR) -> Font:
	if _body == null:
		_body = _load_font(FONT_BODY_PATH)
	if _body == null:
		return _system_font()          # 字体文件缺失 → 降级
	if weight == W_REGULAR:
		return _body
	var key := str(weight)
	if not _body_weighted.has(key):
		var fv := FontVariation.new()
		fv.base_font = _body
		fv.variation_opentype = {"wght": weight}
		_body_weighted[key] = fv
	return _body_weighted[key] as Font


## 小标题（思源宋体 Bold）。用于面板标题 / 章节名 / 关卡名 / 英雄名。
static func serif_font() -> Font:
	if _title == null:
		_title = _load_font(FONT_TITLE_PATH)
	return _title if _title != null else body_font(W_SEMIBOLD)


## 主视觉（毛笔楷书）。[param tracking] 为字距（px），毛笔体加字距才有"设计感"。
static func hero_font(tracking: int = 0) -> Font:
	if _hero == null:
		_hero = _load_font(FONT_HERO_PATH)
	if _hero == null:
		return serif_font()
	if tracking <= 0:
		return _hero
	var key := str(tracking)
	if not _hero_tracked.has(key):
		var fv := FontVariation.new()
		fv.base_font = _hero
		fv.spacing_glyph = tracking
		_hero_tracked[key] = fv
	return _hero_tracked[key] as Font


## 按字号自动选档：≥60 毛笔（带字距）／≥22 宋体／其余正文。
## 字距随字号缩放：80px → 7px。
## 说明：`style_title` 只会被 ≥22 的标题调用；下面这条 <22 的分支是给"万一有人接错"兜底的，
## 回落的是**标准正文**（Regular），不是 Medium —— 免得小字莫名加粗。
static func title_font(size: int) -> Font:
	if size >= HERO_MIN_SIZE:
		return hero_font(clampi(int(round(size / 12.0)), 1, 8))
	if size >= TITLE_MIN_SIZE:
		return serif_font()
	return body_font(W_REGULAR)


## 把标题字体刷到一个 Label 上。**标题一律走这里**，别在界面里自己 add_theme_font_override。
static func style_title(lab: Label, size: int) -> void:
	if lab == null or not is_instance_valid(lab):
		return
	lab.add_theme_font_override("font", title_font(size))


## 三档字体是否都**真的加载到了**（回归测试用）。
## 打包字体缺失时降级是**静默**的 —— 没人会注意到标题全变回黑体，所以必须断言。
static func font_report() -> Dictionary:
	return {
		"hero": _load_font(FONT_HERO_PATH) != null,
		"title": _load_font(FONT_TITLE_PATH) != null,
		"body": _load_font(FONT_BODY_PATH) != null,
	}


# ============================================================================
# 组件库：把一套样式刷到一个控件上（替代各界面手写 add_theme_*_override）
# ============================================================================

## 按钮样式。kind 取 KIND_PRIMARY / KIND_SECONDARY / KIND_GHOST / KIND_DANGER。
## 只写 override，不改布局、不连信号 —— 调用点可以完全保留原有行为。
static func style_button(b: Button, kind: String = KIND_SECONDARY) -> void:
	if b == null or not is_instance_valid(b):
		return
	var bg: Color
	var bd: Color
	var bg_h: Color
	var bg_p: Color
	var fg: Color
	var fg_h: Color
	match kind:
		KIND_PRIMARY:
			# 金底深字：全屏唯一主 CTA
			bg = UiDesign.GOLD_500
			bd = UiDesign.GOLD_600
			bg_h = UiDesign.GOLD_400
			bg_p = UiDesign.GOLD_600
			fg = UiDesign.BTN_TEXT_ON_GOLD
			fg_h = UiDesign.BTN_TEXT_ON_GOLD
		KIND_GHOST:
			bg = Color(0, 0, 0, 0)
			bd = Color(0, 0, 0, 0)
			bg_h = Color(1, 1, 1, 0.07)
			bg_p = Color(1, 1, 1, 0.12)
			fg = UiDesign.INK_300
			fg_h = UiDesign.GOLD_300
		KIND_DANGER:
			bg = Color(UiDesign.DANGER.r, UiDesign.DANGER.g, UiDesign.DANGER.b, 0.22)
			bd = UiDesign.DANGER
			bg_h = Color(UiDesign.DANGER.r, UiDesign.DANGER.g, UiDesign.DANGER.b, 0.38)
			bg_p = Color(UiDesign.DANGER.r, UiDesign.DANGER.g, UiDesign.DANGER.b, 0.5)
			fg = Color(1.0, 0.84, 0.82)
			fg_h = Color(1.0, 0.93, 0.92)
		_:
			bg = UiDesign.BTN_BG
			bd = UiDesign.BTN_BORDER
			bg_h = UiDesign.BTN_BG_HOVER
			bg_p = UiDesign.BTN_BG_PRESSED
			fg = UiDesign.BTN_TEXT
			fg_h = UiDesign.BTN_TEXT_HOVER
	var n := UiDesign.panel(bg, UiDesign.R_MD, bd, 1 if bd.a > 0.0 else 0)
	var h := UiDesign.panel(bg_h, UiDesign.R_MD, UiDesign.BORDER_STRONG,
		1 if kind != KIND_GHOST else 0)
	var p := UiDesign.panel(bg_p, UiDesign.R_MD, UiDesign.GOLD_600,
		1 if kind != KIND_GHOST else 0)
	for pair in [[n, "normal"], [h, "hover"], [p, "pressed"]]:
		_margins(pair[0], UiDesign.SPACE_LG, UiDesign.SPACE_SM)
		b.add_theme_stylebox_override(str(pair[1]), pair[0])
	b.add_theme_stylebox_override("focus", UiDesign.focus_ring())
	# 主 CTA 用 SemiBold：全屏唯一的主按钮，字重压过其他按钮是应该的
	b.add_theme_font_override("font",
		body_font(W_SEMIBOLD) if kind == KIND_PRIMARY else body_font(W_MEDIUM))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg_h)
	b.add_theme_color_override("font_pressed_color", fg_h)
	b.add_theme_color_override("font_focus_color", fg)


## 输入框样式。替换各界面手写的 LineEdit override，保证聚焦反馈一致。
static func style_input(e: LineEdit, w: float = 420.0, h: float = 48.0) -> void:
	if e == null or not is_instance_valid(e):
		return
	var n := UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.BORDER)
	_margins(n, UiDesign.SPACE_MD, UiDesign.SPACE_SM)
	var f := UiDesign.panel(UiDesign.INK_900, UiDesign.R_MD, UiDesign.FOCUS, UiDesign.FOCUS_WIDTH)
	_margins(f, UiDesign.SPACE_MD, UiDesign.SPACE_SM)
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_color_override("font_color", UiDesign.INK_100)
	e.add_theme_color_override("font_placeholder_color", UiDesign.INK_400)
	e.add_theme_color_override("caret_color", UiDesign.GOLD_500)
	e.add_theme_color_override("selection_color",
		Color(UiDesign.GOLD_500.r, UiDesign.GOLD_500.g, UiDesign.GOLD_500.b, 0.34))
	if w > 0.0:
		e.set_meta("min_x", w)
	if h > 0.0:
		e.set_meta("min_y", h)


## 卡片/浮层面板样式（不透明，带描边与投影）。
static func style_card(c: Control, radius: int = UiDesign.R_XL, strong := false) -> void:
	if c == null or not is_instance_valid(c):
		return
	var sb := UiDesign.panel(UiDesign.SURFACE_CARD, radius,
		UiDesign.BORDER_STRONG if strong else UiDesign.BORDER)
	c.add_theme_stylebox_override("panel", UiDesign.elevated(sb, UiDesign.SHADOW_SM))


## 弹窗面板样式：**强制不透明** + 金边 + 重投影（用户铁律的代码化）。
static func style_modal(c: Control, radius: int = UiDesign.R_2XL) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.add_theme_stylebox_override("panel", UiDesign.elevated(
		UiDesign.panel(UiDesign.SURFACE_MODAL, radius, UiDesign.BORDER_STRONG), UiDesign.SHADOW_LG))


# ============================================================================
# 内部
# ============================================================================

static func _margins(sb: StyleBoxFlat, h: int, v: int) -> void:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
