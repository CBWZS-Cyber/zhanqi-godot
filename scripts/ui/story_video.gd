extends Control
## 凛黎线开场动画播放器：全屏播放五幕视频 + 底部字幕（按时间轴）+ 跳过按钮
## 播完/跳过 → 返回主菜单

const VIDEO := "res://story/video/凛黎线开场五幕_10s.ogv"
const MENU := "res://scenes/MainUI.tscn"

## 字幕时间轴 [开始秒, 结束秒, 文案]（改文案只动这里）
const SUBS := [
	[0.0, 2.0, "凛黎大陆——源晶驱动着一切。"],
	[2.0, 4.0, "文明的巅峰，浮空城邦俯瞰众生。"],
	[4.0, 6.0, "大灾变降临，傲慢的城市沉入深渊。"],
	[6.0, 8.0, "残晶散落，有人在废墟上重筑幻梦。"],
	[8.0, 10.1, "而猎手，行走在无人看见的暗处。"],
]

var _player: VideoStreamPlayer
var _label: Label
var _t0_ms: int = 0   # 播放起始时刻（VideoStreamPlayer 无进度 API，用场景计时驱动字幕）

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
	_player.finished.connect(_back_to_menu)
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
	skip.pressed.connect(_back_to_menu)
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

func _back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU)
