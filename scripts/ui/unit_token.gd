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
var statuses: Array = []     # [{cn, lv, id}] —— 状态徽章（2026-09-10 起不再画在头顶，改在右键详情弹窗显示）
var equipment: Array = []    # 已装备武器名（显示在棋子下方）
var _col := Color(0.78, 0.25, 0.18)

var hp := 0.0
var max_hp := 1.0
var energy := 0.0
var max_energy := 1.0
var sanity := 0.0
var sanity_cap := 1.0
var has_sanity := false
var hero_key := ""

var _bone: DragonBonesSprite = null

# 虞美人系花模式：flower="red"(母体红花)/"white"(子体白花)；corner=true 表示所在格被他人占据 → 花显示在格右上角
var flower := ""
var corner := false

func setup(u: BattleUnit, sel: bool) -> void:
	team = u.team
	hero_name = u.name
	hp = u.hp
	max_hp = maxf(1.0, u.max_hp)
	energy = u.energy
	max_energy = maxf(1.0, u.max_energy)
	sanity = u.sanity
	sanity_cap = maxf(1.0, u.sanity_cap)
	has_sanity = u.has_sanity
	selected = sel
	statuses = u.status_icons() if u.status_icons() != null else []
	equipment = u.equipment_names()
	_col = Color(0.80, 0.27, 0.20) if team == 0 else Color(0.26, 0.45, 0.80)
	hero_key = BONE_HERO.get(hero_name, "")
	# 虞美人子体 = 白花（不显建模/圆）；母体由上层按叠格决定是否显示红花
	if u.has_flag("子体"):
		flower = "white"
	elif flower == "white":
		flower = ""
	_refresh_bone()
	queue_redraw()

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

func _draw() -> void:
	var c := size / 2.0
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
	var bh := maxf(3.0, size.y * 0.035)
	var bx := c.x - bw / 2.0
	var base_y := c.y - r - bh - 2.0
	# 能量/理智条（最贴近棋子）
	var ecol := Color(0.85, 0.65, 0.25) if not has_sanity else Color(0.60, 0.45, 0.90)
	var ev := sanity if has_sanity else energy
	var evmax := sanity_cap if has_sanity else max_energy
	draw_rect(Rect2(bx, base_y, bw, bh), Color(0.1, 0.1, 0.12, 0.8))
	draw_rect(Rect2(bx, base_y, bw * clampf(ev / evmax, 0.0, 1.0), bh), ecol)
	# 血条（能量条上方）
	var hp_y := base_y - bh - 1.0
	draw_rect(Rect2(bx, hp_y, bw, bh), Color(0.1, 0.1, 0.12, 0.8))
	draw_rect(Rect2(bx, hp_y, bw * clampf(hp / max_hp, 0.0, 1.0), bh), Color(0.35, 0.85, 0.40))
	# 名字（血条上方）
	var fs := clampi(int(size.y * 0.14), 9, 16)
	var w := f.get_string_size(hero_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(c.x - w / 2.0, hp_y - 2.0), hero_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1), -1.0)

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
		var label := "晕" if str(d.get("id", "")) == "stun" else (cn.substr(0, 1) if cn.length() > 0 else "?")
		if lv > 1:
			label += str(lv)
		var lfs := maxi(8, int(br * 1.05))
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		draw_string(f, Vector2(sx - lw / 2.0, sy + lfs * 0.34), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(1, 1, 1), -1.0)
		sx += br * 2.0 + gap

## 状态徽章配色（与 4V4 team_board.gd 保持一致）
func _status_color(sid: String) -> Color:
	match sid:
		"bleed":
			return Color(0.75, 0.10, 0.12)
		"burn", "burn2":
			return Color(0.92, 0.45, 0.08)
		"wound":
			return Color(0.60, 0.20, 0.55)
		"heavy_wound":
			return Color(0.45, 0.12, 0.40)
		"freeze":
			return Color(0.30, 0.65, 0.90)
		"blind":
			return Color(0.35, 0.35, 0.40)
		"stun":
			return Color(0.95, 0.80, 0.20)
		"full_burn":
			return Color(1.00, 0.35, 0.10)
		"fear":
			return Color(0.55, 0.30, 0.70)
		"sword_field":
			return Color(0.85, 0.75, 0.45)
		"poison", "poison_layer":
			return Color(0.30, 0.60, 0.20)
		_:
			return Color(0.42, 0.44, 0.52)
