extends Node2D
class_name DragonBonesSprite
## DragonBones 骨骼动画回放节点（Godot 4）
## 数据来自官方 DragonBones 核心烘焙出的矩阵（<hero>_bake.json），
## 回放时直接按官方矩阵设置贴图变换 → 与龙骨编辑器 100% 一致。
## 数据：res://assets/db/<hero>_bake.json + <hero>_tex.png
## 用法：设 hero；站桩=第一帧；放技能调 play_animation() 播一次，播完回站桩。

@export var hero := "剑舞"
@export var speed := 0.5

## 个别英雄的播放速度覆盖（帧数多的适当加速）
const SPEED_BY_HERO := {"流萤": 1.5}

var _sprites: Dictionary = {}   # 贴图名 -> Sprite2D
var _root: Node2D               # 内部容器：负责居中缩放，自身 position 由外部定位到格子
var _frames: Array = []         # 每帧 items 数组
var _frame_count := 1
var _duration := 1.0            # 帧
var _fps := 24.0
var _t := 0.0                   # 秒
var _animating := false
var _fit_done := false
var _bbox := {}                 # 第一帧视觉包围盒 {cx, cy, w, h}

func _ready() -> void:
	if SPEED_BY_HERO.has(hero):
		speed = float(SPEED_BY_HERO[hero])
	_build()

func _build() -> void:
	var base := "res://assets/db/"
	var data = _load_json(base + hero + "_bake.json")
	if data.is_empty():
		push_error("无法加载烘焙数据 " + base + hero + "_bake.json")
		return
	_fps = float(data.get("fps", 24.0))
	_duration = float(data.get("duration", 1.0))
	_frames = data.get("frames", [])
	_frame_count = _frames.size()
	var atlas: Texture2D = load(base + hero + "_tex.png")
	_root = Node2D.new()
	_root.name = "Root"
	add_child(_root)
	# 用第一帧建立贴图集合（每张贴图一个 Sprite2D，复用）
	if _frames.size() > 0:
		var seen := {}
		for it in _frames[0].get("items", []):
			var tex: String = it.get("tex", "")
			if tex == "" or seen.has(tex):
				continue
			seen[tex] = true
			var sp := Sprite2D.new()
			sp.name = tex
			sp.texture = atlas
			sp.region_enabled = true
			sp.region_rect = Rect2(it.get("x", 0), it.get("y", 0), it.get("w", 0), it.get("h", 0))
			sp.centered = false   # 左上角对齐（矩阵已把 pivot 折进偏移）
			_root.add_child(sp)
			_sprites[tex] = sp
		_compute_bbox()
		_apply_frame(0)

func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())

func _compute_bbox() -> void:
	if _frames.is_empty():
		return
	var minx := 1e9
	var miny := 1e9
	var maxx := -1e9
	var maxy := -1e9
	for it in _frames[0].get("items", []):
		var a: float = it.get("a", 1.0)
		var b: float = it.get("b", 0.0)
		var c: float = it.get("c", 0.0)
		var d: float = it.get("d", 1.0)
		var px: float = it.get("px", 0.0)
		var py: float = it.get("py", 0.0)
		var tx: float = it.get("tx", 0.0) - (a * px + c * py)
		var ty: float = it.get("ty", 0.0) - (b * px + d * py)
		var w: float = it.get("w", 0.0)
		var h: float = it.get("h", 0.0)
		for uv in [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]:
			var wx: float = a * uv.x + c * uv.y + tx
			var wy: float = b * uv.x + d * uv.y + ty
			minx = min(minx, wx)
			maxx = max(maxx, wx)
			miny = min(miny, wy)
			maxy = max(maxy, wy)
	_bbox = {"cx": (minx + maxx) * 0.5, "cy": (miny + maxy) * 0.5,
		"w": maxx - minx, "h": maxy - miny}

## 把角色居中并缩放到目标尺寸（格子大小）。只缩放/偏移内部容器，
## 自身 position 由外部（unit_token）定位到格子中心，绝不在这里覆盖。
func fit(target: Vector2) -> void:
	if _root == null or _bbox.is_empty() or _bbox.get("w", 0.0) <= 0.0 or _bbox.get("h", 0.0) <= 0.0:
		return
	var s: float = minf(target.x / _bbox["w"], target.y / _bbox["h"])
	_root.scale = Vector2(s, s)
	_root.position = -Vector2(_bbox["cx"], _bbox["cy"]) * s
	_fit_done = true

## 播放一次动作动画，播完自动回站桩
func play_animation() -> void:
	_animating = true
	_t = 0.0

func _process(delta: float) -> void:
	if _frame_count <= 0:
		return
	if _animating:
		_t += delta * speed
		if _t * _fps >= _duration:
			_animating = false
			_t = 0.0
	var f := clampf(_t * _fps / _duration * (_frame_count - 1), 0.0, float(_frame_count - 1))
	_apply_frame(int(round(f)))

func _apply_frame(idx: int) -> void:
	if idx < 0 or idx >= _frames.size():
		return
	var items: Array = _frames[idx].get("items", [])
	# 先隐藏所有，再按帧显示
	for k in _sprites:
		_sprites[k].visible = false
	for it in items:
		var tex: String = it.get("tex", "")
		if not _sprites.has(tex):
			continue
		var sp: Sprite2D = _sprites[tex]
		var a: float = it.get("a", 1.0)
		var b: float = it.get("b", 0.0)
		var c: float = it.get("c", 0.0)
		var d: float = it.get("d", 1.0)
		var px: float = it.get("px", 0.0)
		var py: float = it.get("py", 0.0)
		var tx: float = it.get("tx", 0.0) - (a * px + c * py)
		var ty: float = it.get("ty", 0.0) - (b * px + d * py)
		sp.visible = true
		sp.transform = Transform2D(Vector2(a, b), Vector2(c, d), Vector2(tx, ty))
		sp.z_index = int(it.get("z", 0))
