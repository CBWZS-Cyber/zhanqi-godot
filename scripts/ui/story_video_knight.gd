extends Control
## 骑士线第一关 · 开场动画：全屏播放视频 + 底部字幕（按时间轴）
## 播完 / 跳过 → 进入白灵殿可玩关卡（StoryBattle · 7V10 护送）
## 旧沙盒场景 StoryMap.tscn（只能看、只能走位，无技能/AI/胜负）保留，但不再是主入口。

const VIDEO := "res://story/video/骑士线第一关开场_10s.ogv"
const NEXT := "res://scenes/StoryBattle.tscn"

## 字幕时间轴 [开始秒, 结束秒, 文案]（改文案只动这里）
const SUBS := [
	[0.0, 2.5, "白灵核心在手，昊便成了这片大陆最危险的人。"],
	[2.5, 5.0, "魔渊的追杀，从不问缘由，只问结果。"],
	[5.0, 7.5, "大长老率法师与战士死守殿门，只为换他一线生机。"],
	[7.5, 10.3, "第一关 · 白灵殿——护送昊抵达殿东的逃生区，让他活着离开。"],
]

var _player: VideoStreamPlayer
var _label: Label
var _t0_ms: int = 0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	var stream := VideoStreamTheora.new()
	stream.file = VIDEO
	_player.stream = stream
	_player.finished.connect(_goto_map)
	add_child(_player)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -110.0
	_label.offset_bottom = -50.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_label.add_theme_color_override("font_shadow_color", UiDesign.BAR_NUM_SHADOW)
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)

	var skip := Button.new()
	skip.text = "跳过 >>"
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -130.0
	skip.offset_top = 16.0
	skip.offset_right = -20.0
	skip.offset_bottom = 56.0
	skip.pressed.connect(_goto_map)
	add_child(skip)

	_t0_ms = Time.get_ticks_msec()
	_player.play()

func _process(_d: float) -> void:
	if _player == null or not _player.is_playing():
		return
	var t: float = float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	for s in SUBS:
		if t >= float(s[0]) and t < float(s[1]):
			_label.text = s[2]
			return
	_label.text = ""

func _goto_map() -> void:
	get_tree().change_scene_to_file(NEXT)
