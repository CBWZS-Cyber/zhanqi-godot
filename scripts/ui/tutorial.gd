extends Control
## 新手教程 · 引导关（2026-09-28 新增）
##
## 结构：顶部标题 / 左侧三条（生命·能量·理智）/ 中间棋盘 / 右侧技能 / 底部步骤提示框。
## 战斗全部交给 BattleTutorial（继承 1V1 的 Battle），本文件**只做表现与引导**：
##   · 不读写战斗状态（除了调用 human_move / human_cast / human_done 这三个公开接口）；
##   · 不使用随机数（表现层铁律，见 README 附录 A.1.2）。
##
## 步骤机是**数据驱动**的：改 `_steps` 数组即可增删步骤，不用动逻辑。
## 每个步骤 = {id, title, text, expect, gate}
##   expect：这一步「期望玩家做什么」，用于点错东西时给提醒（不做硬禁用，避免新手卡死）
##   gate  ：过关条件，`{"flag": 名}` 或 `{"manual": true}`（按「下一步」）
##
## ⚠️ 教程完成**不看战斗胜负**（木桩血厚是故意的，胜负判定由 battle 层照常跑但教程不依赖它）：
##    最后一步的过关条件是「木桩掉过一次血」。

const _BT := preload("res://scripts/combat/battle_tutorial.gd")
const _TD := preload("res://scripts/combat/tutorial_defs.gd")
const _HD := preload("res://scripts/combat/hero_defs.gd")
const _SE := preload("res://scripts/combat/skill_effects.gd")
const _TOKEN := preload("res://scripts/ui/unit_token.gd")

const CELL_SEP := 6.0
const MENU := "res://scenes/MainUI.tscn"
const DUEL_SCENE := "res://scenes/Duel.tscn"

const COL_BG := UiDesign.BOARD_BG
const COL_PANEL := UiDesign.SURFACE_PANEL
const COL_GOLD := UiDesign.GOLD_500
const COL_TEXT := UiDesign.INK_100
const COL_DIM := UiDesign.INK_300
const COL_MOVE := UiDesign.CELL_HL_MOVE
const COL_CAST := UiDesign.CELL_HL_CAST
const COL_HP := UiDesign.ALLY
const COL_ENERGY := UiDesign.ENERGY
const COL_SANITY := UiDesign.SANITY

## 步骤表：基础篇（所有教程角色通用）。第二步迭代再按英雄数据插入机制步。
const CORE_STEPS := [
	{
		"id": "select",
		"title": "先点自己的棋子",
		"text": "棋盘上这个[color=#ffd95a]带名字的圆[/color]就是你的棋子。\n[b]用鼠标点它一下[/b]，选中之后才能行动。",
		"expect": "own_unit",
		"gate": {"flag": "selected"},
	},
	{
		"id": "move",
		"title": "走一步 · 绿色格",
		"text": "选中棋子后，周围亮起[color=#7ed87e]绿色格[/color] —— 那是它能走到的地方。\n"
			+ "棋子可以向[b]周围 8 个方向[/b]（含斜向）各走 1 格。\n[b]点一个绿格走过去。[/b]",
		"expect": "move_cell",
		"gate": {"flag": "moved"},
	},
	{
		"id": "skill",
		"title": "挑一个技能",
		"text": "右边是你的 4 个技能，按钮上只有名字。\n"
			+ "[b]把鼠标停在按钮上[/b]可以看完整说明，[b]点一下选中它[/b]。",
		"expect": "skill_btn",
		"gate": {"flag": "skill_opened"},
	},
	{
		"id": "cast",
		"title": "释放技能",
		"text": "技能分三种打法：\n"
			+ "· [color=#ffd95a]要选目标[/color]的：再点一下敌人（金色格）才算放出去\n"
			+ "· [color=#ffd95a]只对自己[/color]的：点按钮就直接生效\n"
			+ "· [color=#ffd95a]位移类[/color]：要先点一个黄色落点\n"
			+ "[b]把当前这个技能放出去。[/b]\n"
			+ "[i]（本作规则：放完技能，这个回合就结束了 —— 每个棋子每回合只有 1 次移动 + 1 次技能。）[/i]",
		"expect": "cast",
		"gate": {"flag": "skill_cast"},
	},
	{
		"id": "bars",
		"title": "看懂左边三条",
		"text": "战斗中你只需要盯这三条：\n"
			+ "· [color=#c7412e]生命[/color] —— 归零就出局。护盾会画在同一条里，先替血顶伤害\n"
			+ "· [color=#5aa0e6]能量[/color] —— 放技能要花，每回合回一点\n"
			+ "· [color=#9e7ad1]理智[/color] —— 部分英雄才有的第三条\n"
			+ "伤害的扣血顺序永远是：[b]护盾 → 护甲 → 生命[/b]。",
		"expect": "manual",
		"gate": {"manual": true},
	},
	{
		"id": "end_turn",
		"title": "「结束回合」是干什么的",
		"text": "先记住规则：每回合只有[b] 1 次移动 + 1 次技能[/b]，而且"
			+ "[b]技能一放，这回合就自动结束了[/b] —— 所以刚才你并没有按过任何按钮，回合就交出去了。\n"
			+ "行动顺序按[b]速度[/b]从高到低排，木桩速度只有 1，永远最后动。\n"
			+ "那[color=#ffd95a]「结束回合」[/color]按钮是给谁用的？\n"
			+ "[i]给「这回合我只想走位、不打算放技能」的情况。[/i]\n"
			+ "现在正好轮到你的新回合，[b]点一下「结束回合」，把它直接交出去。[/b]",
		"expect": "end_turn",
		"gate": {"flag": "end_turn_pressed"},
	},
	{
		"id": "damage",
		"title": "打出伤害 · 完成",
		"text": "轮到你了。用技能[b]打木桩一次[/b]，让它掉血。\n"
			+ "（木桩血很厚、打不空是故意的；教程只要求你成功命中一次。）",
		"expect": "cast",
		"gate": {"flag": "damage"},
	},
]

## 机制步模板 —— 按该英雄**实际技能数据**动态插入（见 _build_steps）。
## 插在「释放技能」之后、「看懂左边三条」之前：刚学会放技能，接着看它的花样。
##
## ⚠️ 机制步的 gate 一律带 `"manual_ok": true`（能放出来就自动过，放不出来可以点「下一步」继续）。
##    原因：有些技能带前置条件放不出来 —— 剑舞「诛心」是斩杀技，只能对生命 ≤30% 的目标使用，
##    对满血木桩根本放不了。硬卡"必须放成功"会让教程直接死在那儿。
const MECH_STEPS := {
	"range": {
		"id": "mech_range",
		"title": "看看技能里的「射程」",
		"text": "技能说明里都会写[color=#ffd95a]射程[/color]，它决定你能打多远：\n"
			+ "· 射程 1 = 贴身近战\n"
			+ "· 射程 2~3 = 隔一两格就能打\n"
			+ "· 写「全图射程」的 = 整个棋盘都在范围里\n"
			+ "[b]把鼠标移到右边技能上，看看描述里的射程数字。[/b]",
		"expect": "manual",
		"gate": {"manual": true},
	},
	"dash": {
		"id": "mech_dash",
		"title": "试着用一次位移技",
		"text": "你的技能里有[color=#ffd95a]位移类[/color]的。位移分两种：\n"
			+ "· [b]冲刺[/b]：朝目标方向逐格冲，撞到东西就停\n"
			+ "· [b]瞬移[/b]：直接跳到范围内的任意空格\n"
			+ "（木桩已经被我压成[color=#ffd95a]残血[/color]了 —— 如果你的位移技带「只能打残血目标」这类条件，"
			+ "现在正好放得出来。）\n"
			+ "[b]点一下那个位移技能试试[/b]（先点技能，再点黄色落点）。\n"
			+ "[i]（实在放不出来就点「下一步」跳过，不影响继续。）[/i]",
		"expect": "cast",
		"gate": {"flag": "dash_cast", "manual_ok": true},
	},
	"self": {
		"id": "mech_self",
		"title": "试着用一次自身技",
		"text": "你的技能里有[color=#ffd95a]只对自己生效[/color]的（护盾 / 增益之类）。\n"
			+ "这种技能[b]不用选目标[/b]，点按钮就直接生效 —— 注意左边血条上会多出一段护盾。\n"
			+ "[b]点一下那个技能试试。[/b]",
		"expect": "cast",
		"gate": {"flag": "self_cast", "manual_ok": true},
	},
	"status": {
		"id": "mech_status",
		"title": "状态与印记",
		"text": "你的技能会给目标挂[color=#ffd95a]状态[/color]，它们显示在棋子头上和右侧状态区。\n"
			+ "常见几种：\n"
			+ "· [b]流血[/b]：被攻击时受额外真伤（1 级 20% / 2 级 30%）\n"
			+ "· [b]灼伤[/b]：每回合末受真伤，持续若干回合\n"
			+ "· [b]眩晕[/b]：跳过行动　·　[b]沉默[/b]：不能用技能\n"
			+ "[i]（状态都带「余 N 回合」，到点自动消失。）[/i]",
		"expect": "manual",
		"gate": {"manual": true},
	},
	"terrain": {
		"id": "mech_terrain",
		"title": "地形：站哪儿不一样",
		"text": "棋盘上**带颜色**的格子是[color=#ffd95a]地形[/color]，站上去就有额外效果：\n"
			+ "· [color=#4d8c52]森林[/color]：受到的伤害 ×0.8（少掉 20% 血）；从格子里走出去要多花 1 点能量\n"
			+ "· [color=#427ab8]水域[/color]：回合结束时扣 1 点能量，且[b]不能在水域里发动位移技[/b]\n"
			+ "（沼泽 / 山地 / 冰面 / 沙地等出现在别的模式里。）\n"
			+ "[i]（走位时顺手把地形算进去，是这游戏拉开差距的地方。）[/i]",
		"expect": "terrain",
		"gate": {"manual": true},
	},
}

## 组装本次教程的步骤表 = 核心步 + 按英雄数据插入的机制步
##   完整篇（我是新手）：核心前 4 步 → 机制步 → 核心后 3 步
##   精简篇（玩过战棋）：**不带**核心前 4 步（基础操作不用再教）→ 机制步 → 核心后 3 步
func _build_steps() -> void:
	var mech: Array = _mech_steps_for(_hero_id)
	var tail: Array = CORE_STEPS.slice(CORE_STEPS.size() - 3)
	if _tier_full():
		_steps = CORE_STEPS.slice(0, 4) + mech + tail
	else:
		_steps = mech + tail


## 该英雄该插哪些机制步（纯数据判断，不看人）
func _mech_steps_for(hero_id: String) -> Array:
	var out: Array = []
	var acts: Array = (_HD.ALL.get(hero_id, {}).get("skills", {}) as Dictionary).get("actives", [])
	var has_range := false
	var has_dash := false
	var has_self := false
	var has_status := false
	for sid in acts:
		var s := str(sid)
		if s == "":
			continue
		var d: Dictionary = _SE.DATA.get(s, {})
		if d.is_empty():
			continue
		var ai: Dictionary = d.get("ai", {})
		var rng := int(d.get("range", -1))
		if bool(ai.get("dash", false)):
			has_dash = true
		if bool(ai.get("self_buff", false)) or rng == 0:
			has_self = true
		if rng >= 2 and rng < 90:      # 90+ 视为「全图」单独讲，不并入射程步
			has_range = true
		var desc := str(d.get("desc", ""))
		for kw in ["流血", "灼伤", "烧伤", "眩晕", "沉默", "印记", "创伤", "恐惧", "冰封", "重伤"]:
			if desc.find(kw) >= 0:
				has_status = true
				break
	if has_range:
		out.append(MECH_STEPS["range"])
	if has_dash:
		out.append(MECH_STEPS["dash"])
	if has_self:
		out.append(MECH_STEPS["self"])
	if has_status:
		out.append(MECH_STEPS["status"])
	# 地形：教程棋盘恒铺了森林/水域（BattleTutorial._build_terrain），所以恒插这一步
	out.append(MECH_STEPS["terrain"])
	return out


func _tier_full() -> bool:
	return str(Global.tutorial_tier) != ProgressStore.TIER_PLAYED

# ---------- 战斗 ----------
var _battle = null
var _hero_id := ""
var _hero_name := ""

# ---------- 界面 ----------
var _title: Label
var _sub: Label
var _hint: Label
var _board: GridContainer
var _wrap: Control
var _unit_layer: Control
var _cell_coords: Array[Vector2i] = []
var _cell_buttons: Array[Button] = []
var _tokens := {}
var _skill_btns: Array[Button] = []
var _skill_panel: PanelContainer
var _bar_panel: PanelContainer
var _end_btn: Button
var _bar_rows := {}
var _step_title: Label
var _step_text: RichTextLabel
var _prev_btn: Button
var _next_btn: Button
var _over_layer: Control = null

# ---------- 步骤状态 ----------
var _steps: Array = []        # 运行时的步骤表（_build_steps 组装出来的）
var _idx := 0
var _flags := {}
var _focus: BattleUnit = null
var _cast_slot := 0
var _phase := "play"          # play | over

# ---------- 遮罩挖洞高亮 ----------
var _step_panel: PanelContainer
var _mask: Control
var _mask_rects: Array[ColorRect] = []
var _hole_frame: Panel
var _hole := Rect2()
var _has_hole := false


func _ready() -> void:
	UiTheme.attach(self)   # 全局墨金主题（幂等）
	_hero_id = str(Global.tutorial_hero)
	if _hero_id == "" or not _HD.ALL.has(_hero_id):
		_hero_id = str(_TD.HEROES[0]["id"])
		Global.tutorial_hero = _hero_id
	_hero_name = str(_HD.ALL[_hero_id]["name"])

	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_steps()
	_build_layout()
	_start_battle()
	get_viewport().size_changed.connect(_apply_sizes)
	call_deferred("_apply_sizes")
	# 档次分流由 _build_steps() 完成（精简篇的步骤表里已经没有前 4 步基础操作），
	# 所以这里两种档位都从第 1 步开始走组装后的表。
	if not _tier_full():
		# 精简篇：基础操作那几步不在表里，但这几个标记照旧占位，避免残留 gate 挡路
		_flags["selected"] = true
		_flags["moved"] = true
		_flags["skill_opened"] = true
		_flags["skill_cast"] = true
	_goto_step(0)


# ================= 界面搭建 =================

func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# —— 顶部标题 ——
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_title = Label.new()
	_title.text = "新手教程"
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", COL_GOLD)
	head.add_child(_title)
	_sub = Label.new()
	_sub.text = ""
	_sub.add_theme_font_size_override("font_size", 19)
	_sub.add_theme_color_override("font_color", COL_DIM)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_sub)
	col.add_child(head)

	# —— 中部：左栏 / 棋盘 / 右栏 ——
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)

	# 左：三条
	_bar_panel = PanelContainer.new()
	_bar_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, 12))
	_bar_panel.custom_minimum_size = Vector2(268, 0)
	mid.add_child(_bar_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 12)
	_bar_panel.add_child(bv)
	_bar_rows["hp"] = _make_bar("生命", COL_HP, true)
	_bar_rows["energy"] = _make_bar("能量", COL_ENERGY, false)
	bv.add_child(_bar_rows["hp"])
	bv.add_child(_bar_rows["energy"])
	# 理智条：只有带 sanity_cap 的英雄才有（教程 4 个角色都没有，留着按需显示）
	_bar_rows["sanity"] = _make_bar("理智", COL_SANITY, false)
	_bar_rows["sanity"].visible = false
	bv.add_child(_bar_rows["sanity"])
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", COL_DIM)
	_hint.custom_minimum_size = Vector2(240, 0)
	bv.add_child(_hint)

	# 中：棋盘
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	_build_board(center)

	# 右：技能 + 结束回合
	_skill_panel = PanelContainer.new()
	_skill_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, 12))
	_skill_panel.custom_minimum_size = Vector2(300, 0)
	mid.add_child(_skill_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	_skill_panel.add_child(sv)
	for i in range(4):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 46)
		b.focus_mode = Control.FOCUS_NONE
		_style_btn(b)
		var slot := i + 1
		b.pressed.connect(func(): _on_skill_clicked(slot))
		_skill_btns.append(b)
		sv.add_child(b)
	_end_btn = Button.new()
	_end_btn.text = "结束回合"
	_end_btn.custom_minimum_size = Vector2(0, 46)
	_end_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(_end_btn)
	_end_btn.pressed.connect(_on_end_turn)
	sv.add_child(_end_btn)

	# —— 底部：步骤提示框 ——
	_step_panel = PanelContainer.new()
	_step_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, 12))
	_step_panel.custom_minimum_size = Vector2(0, 176)
	col.add_child(_step_panel)
	var sp := VBoxContainer.new()
	sp.add_theme_constant_override("separation", 8)
	_step_panel.add_child(sp)
	_step_title = Label.new()
	_step_title.add_theme_font_size_override("font_size", 22)
	UiTheme.style_title(_step_title, 22)   # 步骤标题：宋体档
	_step_title.add_theme_color_override("font_color", COL_GOLD)
	sp.add_child(_step_title)
	_step_text = RichTextLabel.new()
	_step_text.bbcode_enabled = true
	_step_text.fit_content = false
	_step_text.scroll_active = false
	_step_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_text.add_theme_font_size_override("normal_font_size", 18)
	sp.add_child(_step_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	sp.add_child(row)
	_prev_btn = Button.new()
	_prev_btn.text = "上一步"
	_prev_btn.custom_minimum_size = Vector2(120, 40)
	_prev_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(_prev_btn)
	_prev_btn.pressed.connect(func(): _goto_step(_idx - 1))
	row.add_child(_prev_btn)
	_next_btn = Button.new()
	_next_btn.text = "下一步"
	_next_btn.custom_minimum_size = Vector2(140, 40)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(_next_btn)
	_next_btn.pressed.connect(func(): _on_next_pressed())
	row.add_child(_next_btn)
	var quit_btn := Button.new()
	quit_btn.text = "退出教程"
	quit_btn.custom_minimum_size = Vector2(140, 40)
	quit_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(quit_btn)
	quit_btn.pressed.connect(_to_menu)
	row.add_child(quit_btn)
	_build_mask()


# ================= 遮罩挖洞高亮 =================
#
# 做法：在**棋盘区**（不含底部步骤框，否则说明文字会被压暗看不清）铺 4 块半透明黑矩形，
# 围出中间一个"洞"；洞里什么都不画，于是只有目标控件是亮的。
# 再给洞口套一圈金边。
# ⚠️ 全程 mouse_filter = IGNORE —— 遮罩只负责"压暗"，**不拦点击**
#    （教程故意不做硬禁用：新手点错地方只会收到一句提醒，不会卡住）。

func _build_mask() -> void:
	_mask = Control.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ 「最后 add_child 就画在最上面」**不成立**（2026-10-05 修）：
	#    Godot 同层先比 z_index、再比树顺序。棋子名字标签 z=120、击破特效 z=110，
	#    都高于遮罩默认的 0 → 棋子会浮在压暗遮罩之上，挖洞高亮就废了。
	_mask.z_index = UiDesign.Z_OVERLAY
	add_child(_mask)
	for i in range(4):
		var r := ColorRect.new()
		r.color = Color(0.02, 0.03, 0.06, 0.66)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mask.add_child(r)
		_mask_rects.append(r)
	_hole_frame = Panel.new()
	_hole_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = COL_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	_hole_frame.add_theme_stylebox_override("panel", sb)
	_mask.add_child(_hole_frame)
	_mask.visible = false


## 设置当前高亮的控件（null = 不挖洞、不加暗）
func _set_hole(ctrl: Control, pad := 8.0) -> void:
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_visible_in_tree() \
			or ctrl.size.x <= 1.0 or ctrl.size.y <= 1.0:
		_has_hole = false
		return
	var g := Rect2(ctrl.global_position, ctrl.size)
	_hole = Rect2(g.position - Vector2(pad, pad), g.size + Vector2(pad, pad) * 2.0)
	_has_hole = true


## 遮罩只盖"棋盘区"：从顶部到步骤框上沿
func _mask_area() -> Rect2:
	var bottom := size.y
	if _step_panel != null and is_instance_valid(_step_panel):
		bottom = _step_panel.global_position.y - 6.0
	return Rect2(Vector2.ZERO, Vector2(size.x, maxf(0.0, bottom)))


func _apply_mask() -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	var area := _mask_area()
	_mask.position = area.position
	_mask.size = area.size
	_mask.visible = _has_hole and _phase == "play"
	if not _mask.visible:
		return
	var h := Rect2(_hole.position - area.position, _hole.size)   # 转成遮罩的局部坐标
	var vp := area.size
	# 上 / 下 / 左 / 右 四块拼出"洞"
	_mask_rects[0].position = Vector2(0.0, 0.0)
	_mask_rects[0].size = Vector2(vp.x, maxf(0.0, h.position.y))
	_mask_rects[1].position = Vector2(0.0, h.position.y + h.size.y)
	_mask_rects[1].size = Vector2(vp.x, maxf(0.0, vp.y - (h.position.y + h.size.y)))
	_mask_rects[2].position = Vector2(0.0, h.position.y)
	_mask_rects[2].size = Vector2(maxf(0.0, h.position.x), h.size.y)
	_mask_rects[3].position = Vector2(h.position.x + h.size.x, h.position.y)
	_mask_rects[3].size = Vector2(maxf(0.0, vp.x - (h.position.x + h.size.x)), h.size.y)
	_hole_frame.position = h.position
	_hole_frame.size = h.size


## 当前步骤要聚光的**唯一**控件（决定洞挖在哪）
func _focus_control_for_step(expect: String) -> Control:
	var p: BattleUnit = _battle.player_unit() if _battle != null else null
	match expect:
		"own_unit":
			return _cell_button_at(p.cell) if p != null else null
		"move_cell":
			return _wrap                       # 绿格有好几个 → 整个棋盘聚光
		"skill_btn":
			return _skill_panel                # 到这一步要挑技能，整块技能区聚光
		"cast":
			return _cell_button_at(_battle.dummy.cell)
		"manual":
			return _bar_panel                  # 「看懂左边三条」
		"terrain":
			return _cell_button_at(_first_terrain_cell())   # 聚光一个森林格
		"end_turn":
			return _end_btn
	return null


## 教程地形里第一个有地形的格（给「地形」步骤聚光用；键排序后取首个）
func _first_terrain_cell() -> Vector2i:
	var keys: Array = _TD.TERRAIN.keys()
	keys.sort()
	if keys.is_empty():
		return Vector2i(-1, -1)
	var parts: Array = str(keys[0]).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _cell_button_at(cell: Vector2i) -> Control:
	for i in range(_cell_coords.size()):
		if _cell_coords[i] == cell:
			return _cell_buttons[i]
	return null


func _build_board(holder: CenterContainer) -> void:
	_wrap = Control.new()
	holder.add_child(_wrap)
	_board = GridContainer.new()
	_board.columns = 5
	_board.add_theme_constant_override("h_separation", int(CELL_SEP))
	_board.add_theme_constant_override("v_separation", int(CELL_SEP))
	_wrap.add_child(_board)
	_unit_layer = Control.new()
	_unit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.add_child(_unit_layer)
	_cell_coords.clear()
	_cell_buttons.clear()
	# 1V1 棋盘：主区 x1..3 × y1..3，两侧各 1 个出生格 (0,2)/(4,2)
	for row in range(3):
		var y := 3 - row
		for x in range(5):
			if (x == 0 or x == 4) and y != 2:
				var ph := Control.new()
				_ph(ph)
				_board.add_child(ph)
				continue
			var ccell := Vector2i(x, y)
			_cell_coords.append(ccell)
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			# ⚠️ 格子点击必须走 Button.pressed：全局 _unhandled_input 会被 Button 吃掉（README 注意点）
			b.pressed.connect(func(): _on_cell_clicked(ccell))
			_cell_buttons.append(b)
			_board.add_child(b)

func _ph(ph: Control) -> void:
	ph.custom_minimum_size = Vector2(100, 100)


func _make_bar(tag: String, col: Color, tiled: bool) -> HBoxContainer:
	return UiKit.make_bar(tag, col, 0.0, 1.0, tiled, false, false)


func _style_btn(b: Button) -> void:
	UiKit.style_button(b, COL_TEXT)


func _panel_style(col: Color, radius: int) -> StyleBoxFlat:
	return UiKit.panel_style(col, radius, false, 14, 12)


# ================= 开局 =================

func _start_battle() -> void:
	_battle = _BT.new(_hero_id)
	_flags = {"selected": false, "moved": false, "skill_opened": false,
		"skill_cast": false, "turn_ended": false, "damage": false, "dummy_acted": false,
		"dash_cast": false, "self_cast": false, "end_turn_pressed": false}
	_idx = 0
	_focus = null
	_cast_slot = 0
	_phase = "play"
	_sub.text = "%s  vs  训练木桩" % _hero_name
	# 木桩挨打 → 点亮「造成伤害」步骤
	if not _battle.dummy.damaged.is_connected(_on_dummy_damaged):
		_battle.dummy.damaged.connect(_on_dummy_damaged)
	_skill_rows_update()
	_step()
	_refresh_all()


## 技能按钮文案：只显示名字，完整说明走 tooltip（用户 UI 标准）
func _skill_rows_update() -> void:
	var p: BattleUnit = _battle.player_unit()
	for i in range(4):
		var b := _skill_btns[i]
		var sk = p.get_skill(i + 1)
		if sk == null:
			b.visible = false
			continue
		b.visible = true
		b.text = sk.display_name
		b.tooltip_text = "%s\n耗能 %d · 冷却 %d\n%s" % [sk.display_name, sk.energy_cost, sk.cooldown, sk.desc]


func _step() -> void:
	var st: Dictionary = _battle.run_step()
	_focus = null
	_cast_slot = 0
	if st.has("over"):
		_finish(true)
		return
	if st.has("wait"):
		_focus = _battle.current()
	_hint.text = ""


# ================= 交互 =================

func _on_cell_clicked(cell: Vector2i) -> void:
	if _phase != "play" or _battle == null:
		return
	if not _battle.human_mode or _battle.current() != _battle.player_unit():
		_nudge("现在还没轮到你行动。")
		return
	var p: BattleUnit = _battle.player_unit()
	var step: Dictionary = _steps[_idx]
	# 点自己棋子 = 选中
	if cell == p.cell:
		_focus = p
		_flags["selected"] = true
		_refresh_all()
		_advance_if_gate()
		return
	# 点空格 = 移动（必须在绿格内）
	if not _battle.human_moved() and cell in _battle.move_cells_of(p):
		var r: String = _battle.human_move(cell)
		if r != "" and not r.begins_with("!"):
			_flags["moved"] = true
			_focus = p
			_after_player_action()
			return
		_nudge(r)
		return
	# 点木桩 = 释放当前选中的技能
	if cell == _battle.dummy.cell:
		if _cast_slot <= 0:
			_nudge("先在右边点一个技能，再来点目标。")
			return
		_do_cast(_cast_slot)
		return
	_nudge(_expect_hint(str(step.get("expect", ""))))


func _on_skill_clicked(slot: int) -> void:
	if _phase != "play" or _battle == null:
		return
	if _battle.current() != _battle.player_unit():
		_nudge("现在还没轮到你行动。")
		return
	var p: BattleUnit = _battle.player_unit()
	if p.get_skill(slot) == null:
		return
	_cast_slot = slot
	_flags["skill_opened"] = true
	_do_cast(slot)


func _do_cast(slot: int) -> void:
	var p: BattleUnit = _battle.player_unit()
	var sk = p.get_skill(slot)
	var r: String = _battle.human_cast(slot, _battle.dummy)
	if r.begins_with("!"):
		_cast_slot = 0
		_nudge(r.substr(1))
		return
	_flags["skill_cast"] = true
	_classify_cast(sk)
	# 「木桩是否掉血」**不在这里比 hp 快照**，改由木桩的 damaged 信号驱动（见 _on_dummy_damaged）
	# —— 比快照会漏同帧多次变化，这是 README 注意点 19 明写的约定。
	_cast_slot = 0
	_focus = p
	_skill_rows_update()
	_after_player_action()


## 记下"这次放的是哪一类技能"（给机制步当 gate 用）。
## 判定与战斗层一致：dash 看 `DATA[id].ai.dash`（等价于 battle_base.is_dash），
## 自身技看 `ai.self_buff` 或 `range == 0`。
func _classify_cast(sk) -> void:
	if sk == null:
		return
	var d: Dictionary = _SE.DATA.get(str(sk.id), {})
	if d.is_empty():
		return
	var ai: Dictionary = d.get("ai", {})
	if bool(ai.get("dash", false)):
		_flags["dash_cast"] = true
	if bool(ai.get("self_buff", false)) or int(d.get("range", -1)) == 0:
		_flags["self_cast"] = true


func _on_end_turn() -> void:
	if _phase != "play" or _battle == null:
		return
	# 玩家确实按了这个按钮 → 点亮「结束回合」那一步（gate 用的是这个，不是 turn_ended；
	# turn_ended 在「放完技能自动结束」时也会置位，拿它当 gate 会让这一步白给）
	_flags["end_turn_pressed"] = true
	# 本回合若已自动结束（1V1 里「放完技能」就结束），这个按钮这时是没用的 → 直接推进
	if _battle.current() == null:
		_after_player_action()
		return
	if _battle.current() != _battle.player_unit():
		return
	_battle.human_done()
	_flags["turn_ended"] = true
	_step()
	_flags["dummy_acted"] = true
	_refresh_all()
	_advance_if_gate()


## 玩家动作之后统一收尾。
## ⚠️ 1V1 的 `Battle.human_cast()` 末尾**无条件** `_finish_human()`（`battle.gd`），
## 也就是「放完技能本回合就结束、行动权自动交出去」，玩家根本不需要点「结束回合」。
## 所以这里必须识别「回合已结束」这种情况并自己推进，否则步骤会永远卡在「把回合交出去」。
func _after_player_action() -> void:
	if _phase != "play" or _battle == null:
		return
	if _battle.current() != _battle.player_unit():
		_flags["turn_ended"] = true
		_step()                       # 跑木桩的回合 + 开下一个回合
		_flags["dummy_acted"] = true
	if _phase != "play":
		return
	_refresh_all()
	_advance_if_gate()


func _on_dummy_damaged(_u: BattleUnit, _res: Dictionary) -> void:
	# ⚠️ 只在「打出伤害」这一步里认这个标记。
	# 否则玩家在第 4 步（释放技能）就顺手打伤木桩时，标记会提前点亮，
	# _advance_if_gate 会一路跳到结尾、把第 5/6 步（看侧栏 / 结束回合）整段跳过。
	if _idx < _steps.size() and str(_steps[_idx].get("id", "")) == "damage":
		_flags["damage"] = true
		_advance_if_gate()


func _on_next_pressed() -> void:
	var step: Dictionary = _steps[_idx]
	var g: Dictionary = step.get("gate", {})
	if g.has("manual") or bool(g.get("manual_ok", false)):
		_goto_step(_idx + 1)
	else:
		_nudge("这一步要动手做一下才算过 —— " + _expect_hint(str(step.get("expect", ""))))


# ================= 步骤机 =================

func _goto_step(i: int) -> void:
	_set_idx(i)
	_refresh_all()


## 统一的"切到第 i 步"入口：除了夹取下标，还负责**步骤之间的状态切换**。
## 目前只有「位移」步要进出时开/关木桩的残血窗口（见 TutorialDefs.DUMMY_LOW_HP 的注释：
## 残血是为了让斩杀类位移技放得出来，但它同时会带来"木桩可能被打死"的连锁风险，
## 所以必须配套 `BattleTutorial._check_win()` 覆写 + 离步时 `restore_dummy()`）。
## 以后再有"某一步需要特殊准备/收尾"，都加在这里，别散到各处。
func _set_idx(i: int) -> void:
	var prev := str(_steps[_idx].get("id", "")) if _idx < _steps.size() else ""
	_idx = clampi(i, 0, maxi(0, _steps.size() - 1))
	var now := str(_steps[_idx].get("id", "")) if _idx < _steps.size() else ""
	if _battle == null or prev == now:
		return
	if now == "mech_dash":
		_battle.weaken_dummy()
	elif prev == "mech_dash":
		_battle.restore_dummy()


## 当前步的过关条件满足就前进（可连跳，处理"一次动作满足多步"的情况）
func _advance_if_gate() -> void:
	if _phase != "play":
		return
	var guard := 0
	while guard < _steps.size():
		guard += 1
		var step: Dictionary = _steps[_idx]
		if not _gate_ok(step):
			break
		if _idx >= _steps.size() - 1:
			_finish(false)
			return
		_set_idx(_idx + 1)
	_refresh_all()


func _gate_ok(step: Dictionary) -> bool:
	var g: Dictionary = step.get("gate", {})
	if g.has("manual"):
		return false
	if g.has("flag"):
		return bool(_flags.get(str(g["flag"]), false))
	return false


## 圈码：①..⑳（U+2460..U+2473），够教程用了
func _circled(n: int) -> String:
	if n < 1 or n > 20:
		return "%d." % n
	return char(0x2460 + n - 1)


func _expect_hint(expect: String) -> String:
	match expect:
		"own_unit": return "先点你自己的棋子（棋盘左侧那个带名字的圆）。"
		"move_cell": return "点一个绿色格走一步。"
		"skill_btn": return "在右边点一个技能按钮。"
		"cast": return "把技能放出去：自益技点按钮即生效；需要目标的技能要再点一下木桩。"
		"terrain": return "看棋盘上带颜色的格子 —— 绿色是森林、蓝色是水域。"
		"end_turn": return "点右下角的「结束回合」。"
	return "跟着上面提示做就行。"


func _nudge(msg: String) -> void:
	if msg.begins_with("!"):
		msg = msg.substr(1)
	_hint.text = msg


# ================= 刷新 =================

func _refresh_all() -> void:
	_refresh_step_text()
	_refresh_bars()
	_refresh_tokens()
	_refresh_board()


func _refresh_step_text() -> void:
	if _steps.is_empty():
		return
	var step: Dictionary = _steps[_idx]
	# 圈码由序号生成（步骤表里不再硬编码 ①②③ —— 机制步是动态插的，硬编码必乱）
	_step_title.text = "%s %s　（第 %d / %d 步）" % [
		_circled(_idx + 1), str(step["title"]), _idx + 1, _steps.size()]
	_step_text.text = str(step["text"])
	_prev_btn.disabled = _idx <= 0
	# 「下一步」常显：手动步走它，动作步点了会给"这一步要动手做"的提醒（不藏按钮，新手更不迷惑）
	_next_btn.disabled = _idx >= _steps.size() - 1


func _refresh_bars() -> void:
	var p: BattleUnit = _battle.player_unit()
	DamageFx.update_bar(_bar_rows["hp"], p.hp, p.max_hp, "%.0f / %.0f" % [p.hp, p.max_hp], "生命", true, p.shield)
	var en_txt := "无限" if int(_HD.ALL[_hero_id].get("energy_max", 0)) == -1 else "%.0f / %.0f" % [p.energy, p.max_energy]
	DamageFx.update_bar(_bar_rows["energy"], p.energy, maxf(1.0, p.max_energy), en_txt, "能量")
	var show_sanity: bool = bool(p.has_sanity)
	_bar_rows["sanity"].visible = show_sanity
	if show_sanity:
		DamageFx.update_bar(_bar_rows["sanity"], p.sanity, p.sanity_cap,
			"%.0f / %.0f" % [p.sanity, p.sanity_cap], "理智")


func _refresh_tokens() -> void:
	var cs := _cell_size()
	var seen := {}
	for u in _battle.units:
		if not u.alive:
			continue
		var tok = _tokens.get(u)
		if tok == null or not is_instance_valid(tok):
			tok = _TOKEN.new()
			tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_unit_layer.add_child(tok)
			_tokens[u] = tok
			if not u.skill_cast.is_connected(tok._on_skill_cast):
				u.skill_cast.connect(tok._on_skill_cast)
		tok.setup(u, u == _focus)
		tok.custom_minimum_size = Vector2(cs, cs)
		tok.size = Vector2(cs, cs)
		var grow := cs + CELL_SEP
		tok.position = Vector2(u.cell.x * grow + 3.0, (3.0 - u.cell.y) * grow + 3.0)
		seen[u] = true
	for u in _tokens:
		var tk = _tokens[u]
		if is_instance_valid(tk) and not seen.has(u):
			tk.visible = false


## 棋盘三态上色（移动绿 / 技能金色 / 默认）+ 当前步高亮
func _refresh_board() -> void:
	var p: BattleUnit = _battle.player_unit()
	var step: Dictionary = _steps[_idx] if _idx < _steps.size() else {}
	var expect := str(step.get("expect", ""))
	var moves: Array = []
	if _battle.current() == p and not _battle.human_moved():
		moves = _battle.move_cells_of(p)
	for i in range(_cell_coords.size()):
		var c: Vector2i = _cell_coords[i]
		var b: Button = _cell_buttons[i]
		var col := UiDesign.BOARD_LIGHT
		# 地形底色（教程棋盘铺了森林/水域，见 BattleTutorial._build_terrain）
		if _battle.board != null:
			var tid: int = _battle.board.terrain_at(c)
			if tid != Terrain.EMPTY:
				col = Terrain.color_of(tid)
		if c == _battle.dummy.cell:
			col = Color(0.86, 0.72, 0.62)
		if moves.has(c):
			col = COL_MOVE if expect == "move_cell" else Color(0.55, 0.72, 0.55)
		if _cast_slot > 0 and c == _battle.dummy.cell:
			col = COL_CAST
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(8)
		sb.border_color = UiDesign.BOARD_FRAME
		sb.set_border_width_all(1)
		b.add_theme_stylebox_override("normal", sb)
		var h := sb.duplicate()
		h.bg_color = col.lightened(0.12)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		_hl(b, _cell_is_current_focus(c, expect))
	# 面板级高亮
	_hl(_skill_panel, expect == "skill_btn" or expect == "cast")
	_hl(_bar_panel, expect == "manual")
	_hl(_end_btn, expect == "end_turn")
	# 遮罩挖洞：棋盘区整体压暗，只亮当前该点的那个控件
	_set_hole(_focus_control_for_step(expect))
	_apply_mask()


func _cell_is_current_focus(c: Vector2i, expect: String) -> bool:
	if _battle == null:
		return false
	var p: BattleUnit = _battle.player_unit()
	if expect == "own_unit":
		return c == p.cell
	if expect == "move_cell":
		return _battle.current() == p and not _battle.human_moved() and c in _battle.move_cells_of(p)
	if expect == "cast":
		return c == _battle.dummy.cell
	return false


## 金色描边高亮：把控件原有的 stylebox 存进 meta，撤销时还原
func _hl(ctrl: Control, on: bool) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	# Button 用 normal，PanelContainer 用 panel
	var key := "panel" if ctrl is PanelContainer else "normal"
	if on:
		if not ctrl.has_meta("_hl_on"):
			ctrl.set_meta("_hl_orig", ctrl.get_theme_stylebox(key))
			ctrl.set_meta("_hl_on", true)
		ctrl.add_theme_stylebox_override(key, _gold_style())
	else:
		if ctrl.has_meta("_hl_on"):
			var orig = ctrl.get_meta("_hl_orig")
			if orig != null:
				ctrl.add_theme_stylebox_override(key, orig)
			else:
				ctrl.remove_theme_stylebox_override(key)
			ctrl.remove_meta("_hl_on")
			ctrl.remove_meta("_hl_orig")


func _gold_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiDesign.INK_750
	sb.border_color = COL_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# ================= 尺寸 =================

func _cell_size() -> float:
	var by_h := (size.y * 0.50) / 3.0 - CELL_SEP
	var by_w := (size.x * 0.44) / 5.0 - CELL_SEP
	return clampf(minf(by_h, by_w), 58.0, 128.0)


func _apply_sizes() -> void:
	if _board == null:
		return
	var cs := _cell_size()
	var grow := cs + CELL_SEP
	for b in _cell_buttons:
		b.custom_minimum_size = Vector2(cs, cs)
	# 空占位格跟着缩放（保持网格对齐）
	for ch in _board.get_children():
		if ch is Control and not (ch is Button):
			(ch as Control).custom_minimum_size = Vector2(cs, cs)
	_wrap.custom_minimum_size = Vector2(grow * 5.0, grow * 3.0)
	_wrap.size = _wrap.custom_minimum_size
	_refresh_tokens()
	# 尺寸变了 → 洞要按新坐标重算。
	# 走 _refresh_board 而不是直接 _apply_mask：洞的位置依赖各控件的 global_position，
	# 必须等容器布局完成后再取一次（首次 _ready 时布局还没结算，洞会算错）。
	_refresh_board()


# ================= 结束 =================

func _finish(by_battle_over: bool) -> void:
	if _phase == "over":
		return
	_phase = "over"
	_apply_mask()      # phase 已不是 play → 遮罩自动隐藏
	Sfx.play("victory")
	_over_layer = Panel.new()
	(_over_layer as Panel).set_anchors_preset(Control.PRESET_FULL_RECT)
	var ov := _over_layer as Panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiDesign.BAR_TRACK
	ov.add_theme_stylebox_override("panel", sb)
	add_child(ov)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	cc.add_child(box)
	var t := Label.new()
	t.text = "教程完成！" if not by_battle_over else "教程结束"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", COL_GOLD)
	box.add_child(t)
	var d := Label.new()
	d.text = ("你刚练完了：选棋 → 走位 → 放技能 → 看左边三条 → 交回合。\n"
		+ "也见过了：射程、位移技、自身技、状态、地形。\n"
		+ "剩下的都是手感问题 —— 去实战打几局，比再看十遍教程管用。")
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 19)
	d.add_theme_color_override("font_color", COL_DIM)
	box.add_child(d)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	# 主按钮：学完直接上手（按「离线 → 简单 → 1V1」配好全局状态，进对局场景先弹选人）
	var play := Button.new()
	play.text = "去实战一局 →"
	play.custom_minimum_size = Vector2(200, 48)
	_style_btn(play)
	play.pressed.connect(_to_practice)
	row.add_child(play)
	var again := Button.new()
	again.text = "再来一次"
	again.custom_minimum_size = Vector2(170, 48)
	_style_btn(again)
	again.pressed.connect(func():
		ov.queue_free()
		_over_layer = null
		for tk in _tokens.values():
			if is_instance_valid(tk):
				tk.queue_free()
		_tokens.clear()
		_start_battle())
	row.add_child(again)
	var back := Button.new()
	back.text = "返回主菜单"
	back.custom_minimum_size = Vector2(170, 48)
	_style_btn(back)
	back.pressed.connect(_to_menu)
	row.add_child(back)
	# 记进度（2026-10-05：进度**不再挂在"账号"上** ——
	#   登录中 → 写内存（真源是云端，回到主菜单时由 MainUI._sync_cloud_progress 补上传）；
	#   离线玩 → 写本机那份匿名进度 `progress.json`，下次启动接着玩。）
	var p: Dictionary = Global.player_progress
	p["tutorial_done"] = true
	p["tutorial_hero"] = _hero_id
	Global.player_progress = p
	if not Global.cloud_online:
		ProgressStore.save_progress(p)


func _to_menu() -> void:
	get_tree().change_scene_to_file(MENU)


## 学完直接上手：按「离线 → 简单 → 1V1」把全局状态配好，进对局场景（Duel 会先弹选人）。
## 这里设的字段与 MainUI._on_enter_board / _on_diff 完全一致 —— 少设一个就会带着上一局的残留状态进去。
func _to_practice() -> void:
	Global.battle_mode = "1v1"
	Global.offline_type = "pve"
	Global.difficulty = "easy"
	Global.ai_backend = "local"     # 简单难度用不到战术模型，显式给本地值免得留残留
	Global.net_mode = false         # 关掉联机分支（Duel 按这个分流）
	get_tree().change_scene_to_file(DUEL_SCENE)
