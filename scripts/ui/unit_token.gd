extends Control
## 单位棋子：
##   - 有骨骼的英雄（剑舞/追猎/元晶龙王）：显示 DragonBones 角色（站桩）
##   - 其余英雄：保持圆形棋子
##   - 头顶统一：名字 + 血条 + 能量条（辛克莱等理智系 → 理智条）

const BONE_HERO := {"剑舞": "剑舞", "追猎": "追猎", "元晶龙王": "龙王", "流萤": "流萤", "孤狼": "孤狼",
	"李太白": "李太白", "rapper睡神": "睡神", "邪神": "邪神", "灵虚数影": "灵虚数影", "药师": "药师", "虞美人": "虞美人", "光雨": "光雨"}

var team := 0
var hero_name := ""
var selected := false
var statuses: Array = []     # [{cn, lv, id, rounds, label, badge_num}] —— 状态徽章
                             #（2026-09-10 起不再画在头顶，改在右键详情弹窗显示；
                             #  2026-09-18 起 label/badge_num 由 SkillEffects 统一生成，勿自行拼接）
var equipment: Array = []    # 已装备武器名（显示在棋子下方）
var _col := UiDesign.ALLY

var hp := 0.0
var max_hp := 1.0
var shield := 0.0
var energy := 0.0
var max_energy := 1.0
var sanity := 0.0
var sanity_cap := 1.0
var has_sanity := false
var hero_key := ""

var _bone: DragonBonesSprite = null

## ---------- 掉血特效（2026-09-13）----------
## 数据来源：BattleUnit 的 damaged / hp_drained 信号（战斗层唯一出口，含盾吸/减免/真伤/击杀）。
## 三处界面（1V1 / 4V4 / 剧情关）都用本 token，所以特效改这一处就全生效。
##
## FX_SHAKE：位移抖动。**默认关**（用户 2026-09-13 决定不做位移抖动——程序化刚性位移
## 达不到 DragonBones 骨骼动作的效果，容易显得廉价）。打开即恢复。
const FX_SHAKE := false
const FX_FLASH_TIME := 0.20      # 闪红衰减时长（秒）
const FX_GHOST_HOLD := 0.20      # 白条残影停留时长（秒），之后开始追平
const FX_GHOST_SPEED := 0.75     # 白条残影追平速度（每秒掉多少倍 max_hp）

var _unit: BattleUnit = null     # 当前绑定的单位（用于订阅伤害信号；换绑时自动转订阅）
var _hp_ghost := 0.0             # 头顶血条的「白条残影」值（恒 ≥ hp；掉血段用它显示）
var _flash := 0.0                # 受击闪红强度 0..1
var _ghost_hold := 0.0           # 白条残影剩余停留时间
var _shake := Vector2.ZERO       # 位移抖动偏移（仅 FX_SHAKE 打开时使用）

# 虞美人系花模式：flower="red"(母体红花)/"white"(子体白花)；corner=true 表示所在格被他人占据 → 花显示在格右上角
var flower := ""
var corner := false

func setup(u: BattleUnit, sel: bool) -> void:
	_bind_unit(u)          # 订阅伤害信号（换绑才重新连接，防重复连接）
	team = u.team
	hero_name = u.name
	hp = u.hp
	max_hp = maxf(1.0, u.max_hp)
	shield = maxf(0.0, u.shield)
	energy = u.energy
	max_energy = maxf(1.0, u.max_energy)
	sanity = u.sanity
	sanity_cap = maxf(1.0, u.sanity_cap)
	has_sanity = u.has_sanity
	selected = sel
	statuses = u.status_icons() if u.status_icons() != null else []
	equipment = u.equipment_names()
	_col = UiDesign.ALLY_PIECE if team == 0 else UiDesign.ENEMY_PIECE
	hero_key = BONE_HERO.get(hero_name, "")
	# 虞美人子体 = 白花（不显建模/圆）；母体由上层按叠格决定是否显示红花
	if u.has_flag("子体"):
		flower = "white"
	elif flower == "white":
		flower = ""
	# 白条残影只允许「比血条高」：回血/首次出现时直接对齐，掉血时保留高值交给缓动追平
	# （注意：这里绝不能把 _hp_ghost 清零，否则受击动画会被每次 UI 刷新打断）
	if _hp_ghost < hp:
		_hp_ghost = hp
	_refresh_bone()
	queue_redraw()

## 绑定/换绑单位并订阅伤害信号。BattleUnit 是 RefCounted，重复 connect 会报错，必须先判 is_connected。
func _bind_unit(u: BattleUnit) -> void:
	if _unit == u:
		return
	if _unit != null and is_instance_valid(_unit):
		if _unit.damaged.is_connected(_on_damaged):
			_unit.damaged.disconnect(_on_damaged)
		if _unit.hp_drained.is_connected(_on_drained):
			_unit.hp_drained.disconnect(_on_drained)
	_unit = u
	if _unit != null and is_instance_valid(_unit):
		if not _unit.damaged.is_connected(_on_damaged):
			_unit.damaged.connect(_on_damaged)
		if not _unit.hp_drained.is_connected(_on_drained):
			_unit.hp_drained.connect(_on_drained)

func _refresh_bone() -> void:
	if hero_key != "" and flower == "":
		if _bone == null:
			_bone = DragonBonesSprite.new()
			_bone.hero = hero_key   # 先设 hero 再 add_child，否则 _ready 会用默认"剑舞"构建
			add_child(_bone)
		else:
			_bone.hero = hero_key
		_bone.visible = true
	else:
		if _bone != null:
			_bone.visible = false

## 播放一次骨骼动作动画（技能释放时由信号触发）
func play_bone_animation() -> void:
	if _bone != null and hero_key != "":
		_bone.play_animation()

func _on_skill_cast(_slot: int) -> void:
	play_bone_animation()

# ---------------------------------------------------------------- 掉血特效

## 一次完整挨打的结算（盾吸/减免/真掉血/闪避/免疫/击杀）
func _on_damaged(_u: BattleUnit, result: Dictionary) -> void:
	_prepare_fx()
	var lost := float(result.get("hp_lost", 0.0))
	var blocked := float(result.get("absorbed", 0.0)) + float(result.get("reduced", 0.0))
	if bool(result.get("missed", false)):
		_spawn_float("闪避", UiDesign.FX_DODGE, false)
	elif bool(result.get("invuln", false)):
		_spawn_float("免疫", UiDesign.FX_IMMUNE, false)
	elif lost > 0.0:
		_spawn_float("-%s" % _fx_num(lost), UiDesign.FX_DAMAGE, lost >= 3.0)
		_flash = 1.0
		if FX_SHAKE:
			_do_shake()
	elif blocked > 0.0:
		_spawn_float("挡 %s" % _fx_num(blocked), UiDesign.FX_BLOCK, false)
		_flash = maxf(_flash, 0.55)
	if bool(result.get("killed", false)):
		_spawn_float("击破", UiDesign.FX_BREAK, true)
		_spawn_break_fx()
	_start_fx_process()

## 绕过 take_damage 的直接掉血（真伤/自损/回合末地形扣血）
func _on_drained(_u: BattleUnit, amount: float) -> void:
	if amount <= 0.0:
		return
	_prepare_fx()
	_spawn_float("-%s" % _fx_num(amount), UiDesign.FX_TRUE, amount >= 3.0)
	_flash = maxf(_flash, 0.8)
	_start_fx_process()

## 冻结白条残影在「挨打之前」的血量，并重置停留计时
func _prepare_fx() -> void:
	_hp_ghost = maxf(_hp_ghost, hp)
	_ghost_hold = FX_GHOST_HOLD

func _start_fx_process() -> void:
	if not is_processing():
		set_process(true)

func _process(delta: float) -> void:
	var busy := false
	if _flash > 0.0001:
		_flash = maxf(0.0, _flash - delta / FX_FLASH_TIME)
		modulate = Color(1.0, 1.0 - 0.62 * _flash, 1.0 - 0.62 * _flash, 1.0) if _flash > 0.0001 else UiDesign.MODULATE_RESET
		busy = true
	if _hp_ghost > hp + 0.005:
		if _ghost_hold > 0.0:
			_ghost_hold = maxf(0.0, _ghost_hold - delta)
		else:
			_hp_ghost = maxf(hp, _hp_ghost - maxf(1.0, max_hp) * FX_GHOST_SPEED * delta)
		busy = true
	elif _hp_ghost < hp:
		_hp_ghost = hp
		busy = true
	if busy:
		queue_redraw()
	else:
		_hp_ghost = hp
		set_process(false)

## 位移抖动（FX_SHAKE 打开时才走这里）。注意：这里改的是 _shake，
## 在 _draw 里叠加到绘制中心——绝不能直接 tween 自身 position 或 _bone.position，
## 因为 _draw() 每次重绘都会把 _bone.position 写回格子中心，会互相打架。
func _do_shake() -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_shake = Vector2(v, 0.0)
		queue_redraw(), 6.0, 0.0, 0.26).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## 漂浮伤害数字。挂到父节点（棋盘）而不是自己身上：
## 单位阵亡时 token 会被棋盘立刻回收，挂在自己身上会导致击杀飘字看不到。
func _spawn_float(text: String, col: Color, big: bool) -> void:
	var host: Node = get_parent()
	if host == null:
		host = self
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 23 if big else 17)
	lab.add_theme_color_override("font_color", col)
	lab.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.9))
	lab.add_theme_constant_override("outline_size", 5)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.z_index = UiDesign.Z_UNIT_LABEL
	# 固定尺寸 + 居中：不依赖字体度量（add_child 后 size 才可能算出来，直接读 size 会拿到 0）
	lab.size = Vector2(150.0, 30.0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	host.add_child(lab)
	var c := global_position + size * 0.5
	lab.global_position = c - Vector2(lab.size.x * 0.5, lab.size.y * 0.5 + 8.0)
	var p2 := lab.global_position + Vector2(0.0, -36.0)
	var tw := lab.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "global_position", p2, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.9).set_delay(0.28)
	tw.finished.connect(lab.queue_free)

## 击杀碎裂：同样挂父节点，脱离 token 生命周期
func _spawn_break_fx() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var fx := BreakFx.new()
	fx.name = "BreakFx"
	fx.col = _col
	fx.center = position + size * 0.5   # 父节点局部坐标（fx 自身在原点、零尺寸，与父同坐标系）
	host.add_child(fx)

## 数值显示：整数不带小数点，其余保留一位
static func _fx_num(v: float) -> String:
	if absf(v - roundf(v)) < 0.005:
		return "%d" % int(roundf(v))
	return "%.1f" % v

## 击杀碎裂特效（自绘圆环扩散淡出）
class BreakFx extends Control:
	var col := Color.WHITE
	var center := Vector2.ZERO
	var _t := 0.0
	const LIFE := 0.55

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = UiDesign.Z_UNIT_FX
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / LIFE, 0.0, 1.0)
		var a: float = 1.0 - k
		var r: float = 16.0 + 22.0 * k
		draw_arc(center, r, 0.0, TAU, 36, Color(col.r, col.g, col.b, a * 0.95), 3.0, true)
		draw_arc(center, r * 0.62, 0.0, TAU, 36, Color(1, 1, 1, a * 0.55), 2.0, true)

func _draw() -> void:
	var c := size / 2.0 + _shake
	var r := minf(size.x, size.y) * 0.34
	# 选中：所在格子发光（替代原来的黄色圆环）
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.4, 0.32))
		draw_rect(Rect2(Vector2.ZERO, size).grow(-2.0), Color(1.0, 0.85, 0.3), false, 3.0)
	# 虞美人系花模式：母体=红花，子体=白花；corner=被踩时挪到右上角
	if flower != "":
		var fr := minf(size.x, size.y) * (0.20 if corner else 0.30)
		var fc := Vector2(size.x - fr * 1.1, fr * 1.1) if corner else c
		_draw_flower(fc, fr, flower)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	# 有骨骼时角色居中缩放
	if hero_key != "" and _bone != null and is_instance_valid(_bone):
		_bone.position = c
		_bone.fit(size * 0.96)
	# 无骨骼 → 圆形棋子本体
	if hero_key == "":
		draw_circle(c, r, _col)
		draw_arc(c, r, 0.0, TAU, 48, Color(0.08, 0.06, 0.04), 3.0, true)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.32), r * 0.22, Color(1, 1, 1, 0.35))
	# 头顶信息：名字 + 血条 + 能量/理智条
	_draw_overhead(c, r)
	# 印记/状态徽章：2026-09-10 起不再画在头顶（右键棋子 → 详情弹窗查看）
	# 棋子下方：已装备武器
	_draw_equipment(c, r)
	# 点击穿透
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 虞美人花（豆包图生图·海报同款）：red=母体 / white=子体白化版；贴图缺失回退程序花
static var _flower_tex := {}
func _draw_flower(center: Vector2, r: float, kind: String) -> void:
	var tex: Texture2D = _flower_tex.get(kind)
	if tex == null:
		tex = load("res://assets/heroes/yu_mei_ren_flower_%s.png" % kind)
		_flower_tex[kind] = tex
	if tex != null:
		var sz := r * 2.3
		draw_texture_rect(tex, Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)
		return
	var petal := Color(0.85, 0.13, 0.16) if kind == "red" else Color(0.96, 0.95, 0.93)
	for i in range(5):
		var a := TAU * float(i) / 5.0 - PI / 2.0
		var p := center + Vector2(cos(a), sin(a)) * r * 0.72
		draw_circle(p, r * 0.55, petal)
	draw_circle(center, r * 0.32, Color(0.98, 0.88, 0.45))

func _draw_overhead(c: Vector2, r: float) -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var bw := size.x * 0.8
	var bh := maxf(3.0, minf(5.0, size.y * 0.033))
	var bx := c.x - bw / 2.0
	var gap := 1.0
	# ---- 两条条：能量/理智（紧贴棋子）+ 生命·护盾**合体条**（2026-10-07 改回用户原设计）----
	# 历史：2026-10-04 曾把「生命」和「护盾」拆成**两条各自独立**的细条（护盾顶在最上面）。
	# 用户 2026-10-07 实报：这跟原设计不符 —— **盾和血要共用一条**，长度按两种情形来：
	#   ① hp + shield ≤ max_hp → 分母 = max_hp（血按点数占位、盾紧接其后、剩余留空）
	#   ② hp + shield >  max_hp → 分母 = hp + shield（两段按比例铺满整条）
	# 换算**直接复用** DamageFx.hp_shield_layout()，与侧栏 hp_shield_bar 同源（改一处两处都变）。
	# 能量/理智仍是独立一条：2026-10-04 用户点名要求「生命/盾/能量」三者可区分，分开才分得清。
	var top := c.y - r - bh - 2.0
	var ev_cur := sanity if has_sanity else energy
	var ev_max := sanity_cap if has_sanity else max_energy
	_mini_bar(bx, top, bw, bh, ev_cur / maxf(1.0, ev_max),
		UiDesign.SANITY if has_sanity else UiDesign.ENERGY)
	top -= bh + gap
	# 生命 + 护盾：同一条内左血右盾。白条残影必须用**同一个分母**，否则和血段对不齐。
	var lay := DamageFx.hp_shield_layout(hp, shield, max_hp)
	var denom: float = lay.x
	_mini_hp_bar(bx, top, bw, bh, bw * clampf(hp / denom, 0.0, 1.0),
		bw * clampf(_hp_ghost / denom, 0.0, 1.0), bw * clampf(lay.z, 0.0, 1.0))
	# 名字（所有条的上方）：白字 + 深色描边。
	# 用户 2026-10-07 实报「棋子名字在棋盘上很淡、看不清」——根因是只画白字、无描边，
	# 而棋盘是浅色羊皮纸格，白字直接"化"进背景。描边色沿用 BAR_NUM_SHADOW（数字阴影专用令牌）。
	var fs := clampi(int(size.y * 0.14), 9, 16)
	var w := f.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var np := Vector2(c.x - w / 2.0, top - 3.0)
	draw_string_outline(f, np, hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		maxi(2, int(round(fs * 0.22))), UiDesign.BAR_NUM_SHADOW)
	draw_string(f, np, hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiDesign.BAR_NUM, -1.0)


## 画一条迷你条：底槽 + 填充 +（可选）白条残影 + 深色描边。
## 描边是必需的 —— 棋盘上有羊皮纸浅格，没有描边的条会"化"进背景里。
## 颜色**只能**来自 UiDesign 的资源条令牌（生命=HP / 护盾=SHIELD / 能量=ENERGY / 理智=SANITY）。
func _mini_bar(x: float, y: float, w: float, h: float, ratio: float, col: Color,
		ghost_ratio := -1.0) -> void:
	draw_rect(Rect2(x, y, w, h), UiDesign.BAR_TRACK)
	var r := clampf(ratio, 0.0, 1.0)
	if r > 0.002:
		draw_rect(Rect2(x, y, w * r, h), col)
	if ghost_ratio > 0.0:
		var g := clampf(ghost_ratio, 0.0, 1.0)
		if g > r + 0.002:
			draw_rect(Rect2(x + w * r, y, w * (g - r), h), UiDesign.GHOST)
	draw_rect(Rect2(x, y, w, h), UiDesign.BAR_EDGE, false, 1.0)

## 画「生命 + 护盾」合体条：底槽 → 血段 → 盾段 → 白条残影 → 血盾分隔线 → 深色外描边。
## 绘制顺序照抄 hp_shield_bar._draw()：残影要盖住盾一小会儿（反映"这一下掉了多少"），
## 分隔线必须画在残影**之后**，否则细条上会被残影糊掉、看不出血到哪、盾多少。
## 参数用**像素宽度**而不是比例：分段要严格首尾相接，先算比例再乘回来会因取整出现 1px 缝。
func _mini_hp_bar(x: float, y: float, w: float, h: float,
		hp_w: float, ghost_w: float, sh_w: float) -> void:
	draw_rect(Rect2(x, y, w, h), UiDesign.BAR_TRACK)
	if hp_w > 0.5:
		draw_rect(Rect2(x, y, hp_w, h), UiDesign.HP)
	if sh_w > 0.5:
		draw_rect(Rect2(x + hp_w, y, sh_w, h), UiDesign.SHIELD)
	if ghost_w > hp_w + 0.5:
		draw_rect(Rect2(x + hp_w, y, ghost_w - hp_w, h), UiDesign.GHOST)
	if hp_w > 0.5 and sh_w > 0.5:
		draw_rect(Rect2(x + hp_w - 1.0, y, 2.0, h), UiDesign.BAR_EDGE)
	draw_rect(Rect2(x, y, w, h), UiDesign.BAR_EDGE, false, 1.0)

## 棋子下方：装备武器名（最多显示 3 件，超出显示 +N）
func _draw_equipment(c: Vector2, r: float) -> void:
	if equipment.is_empty():
		return
	var f := get_theme_default_font()
	if f == null:
		return
	var fs := clampi(int(size.y * 0.115), 8, 13)
	var shown := minf(3.0, equipment.size())
	var y := c.y + r + 2.0
	for i in range(int(shown)):
		var nm := str(equipment[i])
		var w := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pad := 3.0
		# 深色底条 + 浅金字，保证在任意地形色上可读
		draw_rect(Rect2(c.x - w / 2.0 - pad, y, w + pad * 2.0, fs + 3.0), Color(0.08, 0.07, 0.05, 0.72), true)
		draw_string(f, Vector2(c.x - w / 2.0, y + fs + 0.5), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.88, 0.62), -1.0)
		y += fs + 5.0
	if equipment.size() > 3:
		var more := "+%d" % (equipment.size() - 3)
		var w2 := f.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(c.x - w2 / 2.0 - 3.0, y, w2 + 6.0, fs + 3.0), Color(0.08, 0.07, 0.05, 0.72), true)
		draw_string(f, Vector2(c.x - w2 / 2.0, y + fs + 0.5), more,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.80, 0.70), -1.0)

func _draw_status(c: Vector2, r: float) -> void:
	if statuses.is_empty():
		return
	var f := get_theme_default_font()
	if f == null:
		return
	var br := maxf(5.0, minf(size.x, size.y) * 0.055)
	var gap := br * 0.45
	var n := statuses.size()
	var total := float(n) * (br * 2.0) + float(maxi(0, n - 1)) * gap
	var sx := c.x - total / 2.0 + br
	var sy := c.y - r - 8.0 - br
	for st in statuses:
		var d: Dictionary = st as Dictionary
		var cn := str(d.get("cn", ""))
		var lv := int(d.get("lv", 0))
		draw_circle(Vector2(sx, sy), br, _status_color(str(d.get("id", ""))))
		draw_arc(Vector2(sx, sy), br, 0.0, TAU, 20, Color(0.05, 0.04, 0.03), 1.0, true)
		# 徽章数字：有等级用等级（流血2级→2），只有时长用剩余回合（灼烧→2）—— 由 SkillEffects 统一判定
		var num := int(d.get("badge_num", lv))
		var label := "晕" if str(d.get("id", "")) == "stun" else (cn.substr(0, 1) if cn.length() > 0 else "?")
		if num > 1:
			label += str(num)
		var lfs := maxi(8, int(br * 1.05))
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(f, Vector2(sx - lw / 2.0, sy + lfs * 0.34), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, UiDesign.BAR_NUM, -1.0)
		sx += br * 2.0 + gap

## 状态徽章配色（2026-09-30 收敛：统一走 SkillEffects.status_color，全工程只此一份）
func _status_color(sid: String) -> Color:
	return SkillEffects.status_color(sid)
