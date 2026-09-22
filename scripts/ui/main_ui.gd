extends Control
## 游戏总菜单（仅 UI 导航，不含玩法）：
##   开始界面 → 选择模式（联机 / 离线 / 剧情模式）
##     联机 → 1V1 / 4V4
##     离线 → 选难度（简单/普通/困难）→ 1V1 / 4V4
##     剧情模式 → 直接进入（不再选难度）
##   最终选择进入“结果占位”页（玩法后续再接）。
## 居中：卡片显式取内容尺寸，绕自身中心缩放（pivot），
##       position 使卡片中心 = 视口中心 → 引擎布局不参与也能保证居中。
## 自适应：每帧按窗口尺寸算 _scale，放大/全屏时文字按钮等比变大且始终居中。

const BG_COLOR := Color(0.102, 0.125, 0.208)  # 深蓝灰
const BASE := Vector2(1280, 720)               # 设计基准
const BOARD_SCENE := "res://scenes/TeamDuel.tscn"   # 4V4 走可玩对局场景（原 Board.tscn 展示棋盘）

var _bg: ColorRect
var _scale := 1.0
var _panels := {}
var _current := ""
var _config := {}
var _result_label: Label
var _confs: Array[Dictionary] = []   # 各卡片 VBox 间距/边距（随 _scale 重算）

func _ready() -> void:
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	add_child(_bg)
	_setup_menu_bg_video()   # 背景视频层（可选资源：无视频文件则保持纯色背景）

	_build_screen("start", "战棋", 80, true,
		[["开始游戏", Callable(self, "_on_start")],
		 ["退出", Callable(self, "_on_quit")]], "")
	# 图鉴/介绍：横排独立一行（界面下部）
	var start_card: PanelContainer = _panels["start"]
	var clear_sb := StyleBoxFlat.new()
	clear_sb.bg_color = Color(0.145, 0.176, 0.271, 0.0)
	start_card.add_theme_stylebox_override("panel", clear_sb)
	var start_vbox: VBoxContainer = _panels["start"].get_meta("vbox")
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 16)
	for e in [["英雄图鉴", "hero"], ["武器图鉴", "weapon"], ["地形介绍", "terrain"], ["规则介绍", "rules"]]:
		var cb2 := _make_button(e[0], Callable(self, "_open_codex").bind(e[1]))
		cb2.custom_minimum_size = Vector2(190, 48)
		cb2.set_meta("min_x", 190.0)
		cb2.set_meta("min_y", 48.0)
		cb2.set_meta("fz", 17.0)
		cb2.add_theme_font_size_override("font_size", 17)
		crow.add_child(cb2)
	start_vbox.add_child(crow)
	# 有视频背景时，开始界面的按钮半透明化，让视频更透出（其他界面不受影响）
	if ResourceLoader.exists(MENU_BG_VIDEO):
		_apply_start_btn_alpha(start_card)
	# 目前仅开放：离线 → 简单 → 1V1；其余入口点击弹“暂未开放”
	_build_screen("mode", "选择模式", 44, false,
		[["联机模式", Callable(self, "_show_panel").bind("online_sel")],
		 ["离线模式", Callable(self, "_show_panel").bind("offline_type")],
		 ["剧情模式", Callable(self, "_show_panel").bind("story_sel")]], "start")
	_build_screen("online_sel", "联机模式 · 选择网络", 44, false,
		[["局域网对战（同路由器/热点）", Callable(self, "_on_net_transport").bind("enet")],
		 ["公网对战（cpolar 内网穿透）", Callable(self, "_on_net_transport").bind("ws")]], "mode")
	_build_screen("story_sel", "剧情模式 · 选择线路", 44, false,
		[["骑士线", Callable(self, "_on_story_knight")],
		 ["凛黎线", Callable(self, "_on_story_engineer")]], "start")
	_build_screen("story_knight", "骑士线 · 选择关卡", 44, false,
		[["第一关 · 白灵殿", Callable(self, "_on_story_knight_1")],
		 ["第二关（制作中）", Callable(self, "_on_locked").bind("骑士线第二关")]], "story_sel")
	_build_screen("online", "联机模式 · 好友对战", 44, false,
		[["建房（本机当主机·红方）", Callable(self, "_on_net_host")],
		 ["加入房间（蓝方）", Callable(self, "_show_panel").bind("net_join")]], "online_sel")
	_build_screen("net_join", "加入房间 · 输入主机地址", 44, false,
		[["连接", Callable(self, "_on_net_join")]], "online")
	_build_screen("net_wait", "联机 · 等待连接", 44, false,
		[["取消并断开", Callable(self, "_on_net_cancel")]], "")
	_build_screen("online_pvp", "联机 · 选择对局（已连接）", 44, false,
		[["1V1 对战", Callable(self, "_on_net_battle").bind("1v1")],
		 ["4V4 对战", Callable(self, "_on_net_battle").bind("4v4")],
		 ["断开连接", Callable(self, "_on_net_cancel")]], "")
	_build_screen("offline_type", "离线模式 · 选择类型", 44, false,
		[["PVE · 人机对战", Callable(self, "_on_offline_type").bind("pve")],
		 ["热座模式 · 双人同机", Callable(self, "_on_offline_type").bind("hotseat")]], "mode")
	_build_screen("diff", "离线模式 · 选择难度", 44, false,
		[["简单", Callable(self, "_on_diff").bind("easy")],
		 ["普通（中等）", Callable(self, "_on_diff").bind("normal")],
		 ["困难（战术模型）", Callable(self, "_open_hard_cfg")]], "mode")
	_build_screen("offline", "离线模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_battle").bind("offline", "1v1")],
		 ["4V4", Callable(self, "_on_battle").bind("offline", "4v4")]], "diff")
	_build_result()
	_build_net_extras()
	_hook_net_signals()

	_show_panel("start")
	get_viewport().size_changed.connect(_fit)
	call_deferred("_fit")

func _process(_delta: float) -> void:
	_fit()
	_online_poll()

## 每帧：字号/间距/最小尺寸按 _scale 真实重算（不用 Control.scale 放大，避免全屏文字发糊），
## 卡片取最新内容尺寸后绕中心居中。
func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = clampf(min(vp.x / BASE.x, vp.y / BASE.y), 0.5, 2.4)
	_bg.size = vp
	_bg.position = Vector2.ZERO

	# 各卡片 VBox 的间距/边距
	for cf in _confs:
		var box: Variant = cf.get("box")
		if typeof(box) != TYPE_OBJECT or box == null or not is_instance_valid(box):
			continue
		var bc: Container = box as Container
		bc.add_theme_constant_override("separation", int(cf.get("sep", 0.0) * _scale))
		bc.add_theme_constant_override("margin_left", int(cf.get("ml", 0.0) * _scale))
		bc.add_theme_constant_override("margin_right", int(cf.get("mr", 0.0) * _scale))
		bc.add_theme_constant_override("margin_top", int(cf.get("mt", 0.0) * _scale))
		bc.add_theme_constant_override("margin_bottom", int(cf.get("mb", 0.0) * _scale))

	# 可见卡片：真实字号/尺寸 + 居中
	var p: Control = _panels.get(_current)
	if p != null and p.visible:
		_apply_node_sizes(p)
		var m := p.get_combined_minimum_size()
		p.size = m
		p.scale = Vector2.ONE
		p.pivot_offset = Vector2.ZERO
		p.position = vp / 2.0 - m / 2.0

## 递归：把带 meta("fz"/"min_x"/"min_y") 的控件字号/最小尺寸乘 _scale
func _apply_node_sizes(n: Node) -> void:
	for ch in n.get_children():
		if not is_instance_valid(ch):
			continue
		if ch is Control:
			var co := ch as Control
			if co.has_meta("fz"):
				var sz: int = maxi(8, int(round(float(co.get_meta("fz")) * _scale)))
				if ch is Label:
					(co as Label).add_theme_font_size_override("font_size", sz)
				elif ch is Button:
					(co as Button).add_theme_font_size_override("font_size", sz)
			if co.has_meta("min_x"):
				co.custom_minimum_size.x = float(co.get_meta("min_x")) * _scale
			if co.has_meta("min_y"):
				co.custom_minimum_size.y = float(co.get_meta("min_y")) * _scale
		if ch.get_child_count() > 0:
			_apply_node_sizes(ch)

## F11 在 Godot 里默认没绑任何事；这里手动切换真正的全屏/窗口模式
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN
		return
	# ESC / 右键：逐层退出图鉴（英雄详情 → 英雄图鉴 → 关闭）
	if event.is_action_pressed("ui_cancel"):
		if _hero_detail_layer != null and is_instance_valid(_hero_detail_layer):
			_close_hero_detail()
		elif _codex_layer != null and is_instance_valid(_codex_layer):
			_close_codex()

# ---------- 导航 ----------
func _show_panel(name: String) -> void:
	for k in _panels:
		_panels[k].visible = (k == name)
	_current = name
	_fit()

func _on_start() -> void:
	_show_panel("mode")

func _on_online() -> void:
	_config["mode"] = "online"
	_show_panel("online")

func _on_offline() -> void:
	_config["mode"] = "offline"
	_show_panel("diff")

func _on_story() -> void:
	_config = {"mode": "story"}
	_show_result()

func _on_offline_type(t: String) -> void:
	_config["offline_type"] = t
	if t == "hotseat":
		# 热座双方都是玩家，无 AI 难度概念 → 直接进“选择对局”（1V1 / 4V4）
		_config["difficulty"] = "-"
		Global.difficulty = "-"
		_show_panel("offline")
	else:
		_show_panel("diff")

func _on_diff(d: String) -> void:
	_config["difficulty"] = d
	Global.difficulty = d
	_show_panel("offline")

func _on_battle(mode: String, battle: String) -> void:
	_config["mode"] = mode
	_config["battle"] = battle
	_show_result()

func _on_back(to: String) -> void:
	# 热座没有难度页：从“选择对局”返回时应回“离线模式·选择类型”，而不是“选择难度”
	if to == "diff" and str(_config.get("offline_type", "pve")) == "hotseat":
		_show_panel("offline_type")
		return
	_show_panel(to)

# ---------- 联机（阶段4 MVP：好友房直连 · 1V1）----------
var _net_ip_edit: LineEdit = null
var _net_status_lab: Label = null
var _tunnel = null   # NetTunnel（preload，避免全局类缓存问题）
var _copy_room_btn: Button = null

## 给 net_join 面板加 IP 输入框、net_wait 面板加状态标签
func _build_net_extras() -> void:
	var pj: Control = _panels.get("net_join")
	if pj != null and pj.has_meta("vbox"):
		var box: Container = pj.get_meta("vbox")
		_net_ip_edit = LineEdit.new()
		_net_ip_edit.text = "127.0.0.1"
		_net_ip_edit.placeholder_text = "输入对方主机 IP（端口 %d）" % Global.net_port
		_net_ip_edit.custom_minimum_size = Vector2(420, 48)
		_net_ip_edit.set_meta("min_x", 420.0)
		_net_ip_edit.set_meta("min_y", 48.0)
		_net_ip_edit.add_theme_font_size_override("font_size", 18)
		box.add_child(_net_ip_edit)
	var pw: Control = _panels.get("net_wait")
	if pw != null and pw.has_meta("vbox"):
		var box2: Container = pw.get_meta("vbox")
		_net_status_lab = Label.new()
		_net_status_lab.text = "…"
		_net_status_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_status_lab.add_theme_font_size_override("font_size", 18)
		_net_status_lab.add_theme_color_override("font_color", Color(0.85, 0.89, 0.95))
		box2.add_child(_net_status_lab)

func _init_tunnel() -> void:
	if _tunnel != null:
		return
	_tunnel = preload("res://scripts/net/net_tunnel.gd").new()
	add_child(_tunnel)
	_tunnel.tunnel_ready.connect(_on_tunnel_ready)
	_tunnel.tunnel_failed.connect(_on_tunnel_failed)
	# net_wait 面板加“复制房间号”按钮
	var pw: Control = _panels.get("net_wait")
	if pw != null and pw.has_meta("vbox"):
		var box: Container = pw.get_meta("vbox")
		_copy_room_btn = _make_button("复制房间号", Callable(self, "_on_copy_room"))
		_copy_room_btn.visible = false
		box.add_child(_copy_room_btn)

func _on_tunnel_ready(room: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "房间号已生成！把它发给对方即可加入：\n【 %s 】" % room
	if _copy_room_btn != null:
		_copy_room_btn.visible = true
		_copy_room_btn.set_meta("room", room)

func _on_tunnel_failed(reason: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "公网房间创建失败：%s\n（可改用「局域网对战」，或手动运行 cpolar）" % reason

func _on_copy_room() -> void:
	var room := str(_copy_room_btn.get_meta("room", "")) if _copy_room_btn != null else ""
	if room == "":
		return
	DisplayServer.clipboard_set(room)
	# 按钮原地反馈“已复制”，2 秒后恢复（勿用 _open_locked——那是“功能未开放”弹窗）
	if _copy_room_btn != null:
		_copy_room_btn.text = "✓ 已复制"
		_copy_room_btn.disabled = true
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(_copy_room_btn):
				_copy_room_btn.text = "复制房间号"
				_copy_room_btn.disabled = false)

func _hook_net_signals() -> void:
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.connected_to_host_ok.connect(_on_net_connected)
	Net.join_failed.connect(_on_net_join_failed)
	Net.peer_left.connect(_on_net_peer_left)

func _on_net_host() -> void:
	Net.transport = Global.net_transport
	var err: int = Net.host_game(Global.net_port)
	if err != OK:
		_open_locked("建房失败（端口 %d 被占用？err=%d）" % [Global.net_port, err])
		return
	Global.net_is_host = true
	if _net_status_lab != null:
		if Global.net_transport == "ws":
			_net_status_lab.text = "正在创建公网房间（自动调起 cpolar 隧道）…\n首次创建约需 5~15 秒"
		else:
			_net_status_lab.text = "已开房 [局域网 UDP %d]，等待对方加入…\n（对方选「加入房间」输入本机 IP）" % Global.net_port
	if _copy_room_btn != null:
		_copy_room_btn.visible = false
	if Global.net_transport == "ws":
		_init_tunnel()
		_tunnel.start_tunnel(Global.net_port)
	_show_panel("net_wait")

func _on_net_join() -> void:
	var ip := "127.0.0.1"
	if _net_ip_edit != null and _net_ip_edit.text.strip_edges() != "":
		ip = _net_ip_edit.text.strip_edges()
	Net.transport = Global.net_transport
	var err: int = Net.join_game(ip, Global.net_port)
	if err != OK:
		_open_locked("连接失败（地址格式错误？err=%d）" % err)
		return
	Global.net_is_host = false
	if _net_status_lab != null:
		_net_status_lab.text = "正在连接 %s …" % ip
	_show_panel("net_wait")

## 选网络类型：enet=局域网直连 / ws=公网穿透（WebSocket/TCP，配 cpolar 隧道）
## 剧情模式 · 骑士线（进入剧情地图展示器，第一关：白灵殿）
func _on_story_engineer() -> void:
	get_tree().change_scene_to_file("res://scenes/StoryVideo.tscn")

func _on_story_knight() -> void:
	_open_knight_levels()

## ================= 骑士线 · 关卡滚轮选择 =================
## 关卡数据：name / video（开场动画 ogv）/ poster（首帧 jpg）/ locked
const KNIGHT_LEVELS := [
	{"name": "第一关 · 白灵殿", "video": "res://story/video/骑士线第一关开场_10s.ogv", "poster": "res://assets/levels/knight_1.jpg", "locked": false},
	{"name": "第二关（制作中）", "video": "", "poster": "", "locked": true},
]
var _level_idx: int = 0
var _level_layer: Control = null
var _level_name: Label = null
var _level_center: Control = null
var _level_left: Control = null
var _level_right: Control = null

## 打开骑士线关卡滚轮：中间完整（播开场视频），左右半露（显示首帧）
func _open_knight_levels() -> void:
	_level_layer = _make_codex_layer("骑士线 · 选择关卡", true)
	var v: VBoxContainer = _level_layer.get_meta("vbox")
	# 关卡名
	_level_name = Label.new()
	_level_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_name.add_theme_font_size_override("font_size", 24)
	_level_name.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	v.add_child(_level_name)
	# 滚轮区
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 380)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(stage)
	_level_left = _level_card(-1)
	_level_right = _level_card(1)
	_level_center = _level_card(0)
	stage.add_child(_level_left)
	stage.add_child(_level_right)
	stage.add_child(_level_center)
	# 左右切换按钮
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 40)
	v.add_child(hb)
	var bl := _cream_btn(Button.new())
	bl.text = "◀ 上一关"
	bl.pressed.connect(_level_shift.bind(-1))
	hb.add_child(bl)
	var go := _cream_btn(Button.new())
	go.text = "进入关卡"
	go.pressed.connect(_level_enter)
	hb.add_child(go)
	var br := _cream_btn(Button.new())
	br.text = "下一关 ▶"
	br.pressed.connect(_level_shift.bind(1))
	hb.add_child(br)
	v.add_child(_codex_back_button(_close_knight_levels))
	_refresh_level_cards()

## 一张关卡卡：pos=-1 左半露 / 0 中间完整 / 1 右半露
func _level_card(pos: int) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	var size := Vector2(360, 330) if pos == 0 else Vector2(300, 280)
	c.custom_minimum_size = size
	c.size = size
	c.pivot_offset = size / 2.0
	# 偏移：中间 0；左右卡中心推到屏幕边缘（只露一半）
	var off := Vector2(0, 0)
	if pos != 0:
		off = Vector2(pos * 470.0, 40.0)
	c.position = -size / 2.0 + off
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.99, 0.975, 0.945, 1.0) if pos == 0 else Color(0.94, 0.92, 0.88, 0.85)
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = Color(0.65, 0.55, 0.40)
	c.add_child(bg)
	c.set_meta("pos", pos)
	c.set_meta("holder", bg)
	return c

## 刷新三张卡内容（中间播视频 / 两侧首帧）
func _refresh_level_cards() -> void:
	if _level_layer == null:
		return
	var n := KNIGHT_LEVELS.size()
	_level_idx = wrapi(_level_idx, 0, n)
	var cur: Dictionary = KNIGHT_LEVELS[_level_idx]
	_level_name.text = "%s（%d/%d）" % [str(cur.get("name", "")), _level_idx + 1, n]
	for c in [_level_left, _level_right, _level_center]:
		if c == null:
			continue
		var pos: int = int(c.get_meta("pos"))
		var idx := wrapi(_level_idx + pos, 0, n)
		var lv: Dictionary = KNIGHT_LEVELS[idx]
		var holder: Control = c.get_meta("holder")
		# 清旧内容
		for ch in holder.get_children():
			ch.queue_free()
		if pos == 0:
			_build_center_card(holder, lv, idx)
		else:
			_build_side_card(holder, lv, c)

## 中间卡：有视频就播放，否则显示首帧
func _build_center_card(holder: Control, lv: Dictionary, idx: int) -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	holder.add_child(vb)
	var vid := str(lv.get("video", ""))
	var played := false
	if vid != "" and FileAccess.file_exists(vid):
		var s := VideoStreamTheora.new()
		s.file = vid
		var vp := VideoStreamPlayer.new()
		vp.custom_minimum_size = Vector2(320, 240)
		vp.expand = true
		vp.stream = s
		vp.autoplay = true
		vp.finished.connect(vp.play)
		vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(vp)
		played = true
	if not played:
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(320, 240)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var p := str(lv.get("poster", ""))
		if p != "" and ResourceLoader.exists(p):
			tex.texture = load(p) as Texture2D
		vb.add_child(tex)
	var nm := Label.new()
	nm.text = str(lv.get("name", ""))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	vb.add_child(nm)
	if bool(lv.get("locked", false)):
		var lk := Label.new()
		lk.text = "（制作中）"
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
		vb.add_child(lk)

## 两侧卡：只显示首帧（半露）
func _build_side_card(holder: Control, lv: Dictionary, card: Control) -> void:
	var tex := TextureRect.new()
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var p := str(lv.get("poster", ""))
	if p != "" and ResourceLoader.exists(p):
		tex.texture = load(p) as Texture2D
	holder.add_child(tex)
	card.modulate = Color(1.0, 1.0, 1.0, 0.75)

## 切换关卡（滚轮 / 按钮）
func _level_shift(d: int) -> void:
	_level_idx += d
	_refresh_level_cards()

func _level_enter() -> void:
	var cur: Dictionary = KNIGHT_LEVELS[_level_idx]
	if bool(cur.get("locked", false)):
		return
	get_tree().change_scene_to_file("res://scenes/StoryVideoKnight.tscn")

func _close_knight_levels() -> void:
	if _level_layer != null and is_instance_valid(_level_layer):
		_level_layer.queue_free()
	_level_layer = null
	_level_center = null
	_level_left = null
	_level_right = null

## 滚轮切换关卡（鼠标滚轮 / 触屏滑动）
func _gui_input(event: InputEvent) -> void:
	if _level_layer == null or not is_instance_valid(_level_layer):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_level_shift(1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if absf(d.relative.x) > 40.0:
			_level_shift(-1 if d.relative.x > 0 else 1)

func _on_story_knight_1() -> void:
	get_tree().change_scene_to_file("res://scenes/StoryVideoKnight.tscn")

func _on_net_transport(t: String) -> void:
	Global.net_transport = t
	if _net_ip_edit != null:
		if t == "ws":
			_net_ip_edit.text = ""
			_net_ip_edit.placeholder_text = "输入房间号（cpolar 地址，如 6.tcp.cpolar.top:12345）"
		else:
			_net_ip_edit.text = "127.0.0.1"
			_net_ip_edit.placeholder_text = "输入对方主机 IP（端口 %d）" % Global.net_port
	_show_panel("online")   # 跳到建房/加入页

func _on_net_peer_joined() -> void:
	# host 收到：对方已连上 → 进入选对局
	if Global.net_is_host:
		_show_panel("online_pvp")

func _on_net_connected() -> void:
	# joiner 连上 → 进入选对局
	_show_panel("online_pvp")

func _on_net_join_failed(_err: int) -> void:
	_open_locked("连接失败：对方不在线或 IP 错误")
	_show_panel("online")

## 取消等待/断开连接 → 回联机菜单
func _on_net_cancel() -> void:
	Global.net_mode = false
	Global.net_is_host = false
	if Net.active:
		Net.leave_game()
	if _tunnel != null:
		_tunnel.stop_tunnel()
	_show_panel("online")

func _on_net_peer_left() -> void:
	if Global.net_mode:
		# 对局中对方掉线 = 我方胜（MVP：提示后回菜单，由对局场景处理）
		return
	_open_locked("对方已断开连接")
	Net.leave_game()
	_show_panel("online")

## 选对局（联机版）：net_wait 面板上动态插入的对局按钮容器
func _open_locked(msg: String) -> void:
	_on_locked(msg)

## 联机 1V1：写 Global 联机上下文 → result → 进 Duel（选英雄交换在 Duel 内完成）
func _on_net_battle(battle: String) -> void:
	Global.net_mode = true
	Global.net_is_host = Global.net_is_host   # 建房/加入时已写
	Global.net_seed = randi() % 1000000000 if Global.net_is_host else 0
	Global.battle_mode = battle
	Global.offline_type = "pve"   # 联机不吃 PVE/热座分支
	_config["mode"] = "online"
	_config["battle"] = battle
	_show_result()

func _on_to_menu() -> void:
	_config = {}
	# 回主菜单：清理联机会话（若有）
	Global.net_mode = false
	if Net.active:
		Net.leave_game()
	if _tunnel != null:
		_tunnel.stop_tunnel()
	_show_panel("start")

func _on_quit() -> void:
	get_tree().quit()

func _on_enter_board() -> void:
	var battle: String = _config.get("battle", "")
	Global.battle_mode = battle if battle == "4v4" else "1v1"
	Global.offline_type = str(_config.get("offline_type", "pve"))
	# 1V1 = 可玩对局（选英雄 + 人机操作）；4V4 暂用展示棋盘
	if battle == "1v1":
		get_tree().change_scene_to_file("res://scenes/Duel.tscn")
	else:
		get_tree().change_scene_to_file(BOARD_SCENE)

func _show_result() -> void:
	var mode: String = _config.get("mode", "")
	var diff: String = _config.get("difficulty", "")
	var battle: String = _config.get("battle", "")
	var parts: Array[String] = []
	if mode == "story":
		parts.append("剧情模式")
	else:
		parts.append("联机模式" if mode == "online" else "离线模式")
		if mode == "offline" and diff != "":
			var dn := _diff_name(diff)
			if dn != "":
				parts.append(dn)
		match battle:
			"1v1":
				parts.append("1V1")
			"4v4":
				parts.append("4V4")
	_result_label.text = " · ".join(parts)
	_show_panel("result")

func _diff_name(d: String) -> String:
	if d == "" or d == "-":
		return ""
	match d:
		"easy":
			return "简单"
		"normal":
			return "普通"
		_:
			return "困难"

# ---------- 构建界面 ----------
func _build_screen(key: String, title: String, title_size: int, with_shadow: bool,
		specs: Array, back_to: String) -> void:
	var card := _make_card(title, title_size, with_shadow)
	var vbox: VBoxContainer = card.get_meta("vbox")
	for i in range(specs.size()):
		var entry: Array = specs[i]
		var text: String = entry[0]
		var cb: Callable = entry[1]
		vbox.add_child(_make_button(text, cb))
	if back_to != "":
		vbox.add_child(_make_button("返回", Callable(self, "_on_back").bind(back_to)))
	add_child(card)
	card.visible = false
	_panels[key] = card

func _build_result() -> void:
	var card := _make_card("准备开始", 44, false)
	var vbox: VBoxContainer = card.get_meta("vbox")
	_result_label = Label.new()
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 30)
	_result_label.set_meta("fz", 30.0)
	_result_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96))
	vbox.add_child(_result_label)
	vbox.add_child(_make_button("进入棋盘（占位）", Callable(self, "_on_enter_board")))
	vbox.add_child(_make_button("返回菜单", Callable(self, "_on_to_menu")))
	add_child(card)
	card.visible = false
	_panels["result"] = card

func _make_card(title: String, title_size: int, with_shadow: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.176, 0.271, 0.75)   # 半透明卡片：透出背景视频
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style["corner_radius_" + r] = 18
	card.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.add_theme_constant_override("margin_left", 56)
	vbox.add_theme_constant_override("margin_right", 56)
	vbox.add_theme_constant_override("margin_top", 44)
	vbox.add_theme_constant_override("margin_bottom", 44)
	_confs.append({"box": vbox, "sep": 24.0, "ml": 56.0, "mr": 56.0, "mt": 44.0, "mb": 44.0})
	card.add_child(vbox)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", title_size)
	t.set_meta("fz", float(title_size))
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))  # 金色
	if with_shadow:
		t.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.55))
		t.add_theme_constant_override("shadow_offset_x", 3)
		t.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(t)
	card.set_meta("vbox", vbox)
	return card

func _make_button(text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.set_meta("min_x", 300.0)
	btn.set_meta("min_y", 60.0)
	btn.set_meta("fz", 24.0)
	btn.custom_minimum_size = Vector2(300, 60)
	btn.add_theme_stylebox_override("normal", _btn_style(Color(0.941, 0.780, 0.369)))
	btn.add_theme_stylebox_override("hover", _btn_style(Color(1.0, 0.88, 0.55)))
	btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.78, 0.62, 0.22)))
	btn.add_theme_color_override("font_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.09, 0.05))
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(func() -> void:
		Sfx.play("click")
		cb.call())
	return btn

func _btn_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s["corner_radius_" + r] = 10
	return s


## ================= 主菜单背景视频（可选资源） =================
## 有 res://assets/video/menu_bg.ogv 就循环播放并压暗；没有则退回纯色背景。
## 以后换背景视频只需替换该文件，无需改代码。
const MENU_BG_VIDEO := "res://assets/video/menu_bg.ogv"
const MENU_BG_DIM := Color(0.05, 0.07, 0.12, 0.45)   # 压暗遮罩：保证金色标题与按钮可读

func _setup_menu_bg_video() -> void:
	if not ResourceLoader.exists(MENU_BG_VIDEO):
		return
	var stream: VideoStream = load(MENU_BG_VIDEO)
	if stream == null:
		push_warning("背景视频加载失败：%s" % MENU_BG_VIDEO)
		return
	var vsp := VideoStreamPlayer.new()
	vsp.stream = stream
	vsp.expand = true                       # 拉伸铺满控件
	vsp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vsp)
	vsp.finished.connect(vsp.play)          # 播完自动重播（循环）
	vsp.play()
	# 压暗遮罩盖在视频上、UI 之下
	var dim := ColorRect.new()
	dim.color = MENU_BG_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

## 开始界面按钮半透明化：金色底降到约 80% 不透明度、字降到 85%，
## 让背景视频更透出；hover/pressed 略高一点保留交互反馈。
func _apply_start_btn_alpha(panel: Node, bg_a: float = 0.8, txt_a: float = 0.85) -> void:
	var stack: Array[Node] = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			var b := n as Button
			for st in ["normal", "hover", "pressed"]:
				var sb := b.get_theme_stylebox(st)
				if sb is StyleBoxFlat:
					var clone := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
					clone.bg_color.a = bg_a if st == "normal" else minf(bg_a + 0.06, 1.0)
					b.add_theme_stylebox_override(st, clone)
			for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
				var col: Color = b.get_theme_color(fc)
				col.a = txt_a
				b.add_theme_color_override(fc, col)
		for c in n.get_children():
			stack.append(c)

## ================= 图鉴/介绍（开始界面入口） =================
var _codex_layer: Control = null
var _hero_detail_layer: Control = null

## 英雄海报资源目录：res://assets/heroes/{英雄id}.jpg
const HERO_PORTRAIT_DIR := "res://assets/heroes/"

## 取英雄海报贴图；无对应资源时安静返回 null（不报错、不中断）
const _BIO_DIR := "res://story/bios/"
const _HERO_VIDEO_DIR := "res://assets/heroes/videos/"
const _STORY_DIR := "res://story/stories/"
## 动态海报视频源宽高比（新视频转码进 videos/ 时在此登记，否则会拉伸变形）
const _VIDEO_AR := {"jianwu": 0.75, "gu_lang": 0.75, "yao_shi": 0.75, "he_zhigao": 0.75, "crystal_dragon": 0.75, "yu_mei_ren": 0.5625, "liu_ying": 0.5625, "li_taibai": 1.0}

func _hero_portrait(id: String) -> Texture2D:
	var p := HERO_PORTRAIT_DIR + id + ".jpg"
	if not ResourceLoader.exists(p):
		return null
	return load(p) as Texture2D

## 动态海报流：assets/heroes/videos/{id}.ogv 存在则返回，否则 null
func _hero_video_stream(id: String) -> VideoStream:
	if not FileAccess.file_exists(_HERO_VIDEO_DIR + id + ".ogv"):
		return null
	var s := VideoStreamTheora.new()
	s.file = _HERO_VIDEO_DIR + id + ".ogv"
	return s

## ---------- 动态海报播放限流：同一时刻最多 3 张在播，防卡顿 ----------
const _MAX_VIDEO_PLAYERS := 3
var _video_nodes: Array = []          # [{node: VideoStreamPlayer, prio: int}]
var _video_timer: Timer = null        # 周期轮询可见性并重排播放名额

## 注册一个动态海报播放器（priority 越大越优先播放；详情页海报 > 卡片）
func _register_video(vp: VideoStreamPlayer, priority: int = 0) -> void:
	_video_nodes.append({"node": vp, "prio": priority})
	if _video_timer == null:
		_video_timer = Timer.new()
		_video_timer.wait_time = 0.35
		_video_timer.timeout.connect(_update_video_slots)
		add_child(_video_timer)
		_video_timer.start()
	_update_video_slots()

## 清理失效/已销毁的播放器引用（层关闭时调用）
func _prune_videos() -> void:
	_video_nodes = _video_nodes.filter(func(e: Dictionary) -> bool:
		var n = e.get("node")
		return is_instance_valid(n) and n.is_inside_tree())
	_update_video_slots()

## 按「可见 + 优先级」分配播放名额：前 3 名播放，其余暂停
func _update_video_slots() -> void:
	var vis: Array = []
	var vpr := get_viewport_rect()
	var check_rect := vpr.size.x > 1.0 and vpr.size.y > 1.0   # 视口尺寸无效（如无头）时不做矩形剔除
	var vr := Rect2(Vector2.ZERO, Vector2(vpr.size))
	for e in _video_nodes:
		var n = e.get("node")
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if check_rect and not n.get_global_rect().intersects(vr):
			continue      # 滚动到视口外的卡片不占名额
		vis.append(e)
	vis.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("prio", 0)) > int(b.get("prio", 0)))
	for i in range(vis.size()):
		var n = vis[i].get("node")
		if i < _MAX_VIDEO_PLAYERS:
			n.visible = true
			if not n.is_playing():
				n.play()
		else:
			if n.is_playing():
				n.paused = true
			n.visible = false       # 露出底下的静态立绘，避免空白

## 有动态海报则生成「槽位容器 + 等比播放器」（按视频比例缩放居中，不拉伸），否则 null
func _make_dynamic_poster(id: String, slot: Vector2, priority: int = 0) -> Control:
	var v := _hero_video_stream(id)
	if v == null:
		return null
	var ar: float = float(_VIDEO_AR.get(id, 0.75))
	var s := Vector2(slot.y * ar, slot.y)   # 以槽高为基准等比
	if s.x > slot.x:
		s = Vector2(slot.x, slot.x / ar)
	var cc := CenterContainer.new()
	cc.custom_minimum_size = slot
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 容器不吃点击，否则卡片按钮点不动
	var holder := Control.new()
	holder.custom_minimum_size = s
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 底图：静态立绘（未获得播放名额时显示，避免播放器空白）
	var t := _hero_portrait(id)
	if t != null:
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture = t
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tex)
	var vp := VideoStreamPlayer.new()
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.custom_minimum_size = s
	vp.expand = true
	vp.stream = v
	vp.autoplay = false            # 由限流调度器决定是否播放
	vp.visible = false             # 获得名额才显示，否则露出底图
	vp.finished.connect(func() -> void:
		vp.play()                   # 无缝循环（video 无声）
		_update_video_slots())
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(vp)
	cc.add_child(holder)
	_register_video(vp, priority)
	return cc

## 建一个通用图鉴层（标题已加好），内容区 VBox 存在 meta["vbox"] 里供调用方填内容
func _make_codex_layer(title_txt: String, opaque: bool = false) -> Control:
	var layer := Panel.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.965, 0.948, 0.905, 0.78) if not opaque else Color(0.985, 0.97, 0.93, 1.0)
	# 半透：图鉴列表页透背景视频；不透明：详情/弹窗页保证文字清晰
	layer.add_theme_stylebox_override("panel", sb)
	add_child(layer)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 60)
	m.add_theme_constant_override("margin_right", 60)
	m.add_theme_constant_override("margin_top", 30)
	m.add_theme_constant_override("margin_bottom", 30)
	layer.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var title := Label.new()
	title.text = title_txt
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	layer.set_meta("vbox", v)
	# 右上角固定 ✕：不参与 VBox 内容流。
	# 修复：英雄详情页竖向总高 ~793px 超过 720px 窗口，底部"返 回"按钮被挤出屏幕外，导致无法退出。
	var close_btn := _cream_btn(Button.new())
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(48, 48)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.offset_left = -64.0
	close_btn.offset_right = -14.0
	close_btn.offset_top = 12.0
	close_btn.offset_bottom = 62.0
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(func():
		if _hero_detail_layer != null and is_instance_valid(_hero_detail_layer):
			_close_hero_detail()
		else:
			_close_codex())
	layer.add_child(close_btn)
	return layer

## 底部居中的“返回”按钮
## 米白主题按钮统一样式（深棕字 + 暖白底 + 棕描边圆角）
func _cream_btn(b: Button) -> Button:
	b.add_theme_color_override("font_color", Color(0.24, 0.19, 0.12))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.99, 0.975, 0.945)
	n.border_color = Color(0.65, 0.55, 0.40)
	n.set_border_width_all(2)
	n.set_corner_radius_all(8)
	n.content_margin_top = 8
	n.content_margin_bottom = 8
	var h := n.duplicate()
	(h as StyleBoxFlat).bg_color = Color(1.0, 0.94, 0.85)
	var pd := n.duplicate()
	(pd as StyleBoxFlat).bg_color = Color(0.93, 0.88, 0.80)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pd)
	return b

func _codex_back_button(cb: Callable) -> Control:
	var back := _cream_btn(Button.new())
	back.text = "返 回"
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(cb)
	var bc := CenterContainer.new()
	bc.add_child(back)
	return bc

func _open_codex(key: String) -> void:
	_close_codex()
	if key == "hero":
		_open_hero_codex()
		return
	var titles := {"weapon": "武器图鉴", "terrain": "地形介绍", "rules": "规则介绍"}
	var layer := _make_codex_layer(str(titles.get(key, "图鉴")))
	var v: VBoxContainer = layer.get_meta("vbox")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.text = _codex_content(key)
	v.add_child(rt)
	v.add_child(_codex_back_button(_close_codex))
	_codex_layer = layer

func _close_codex() -> void:
	_close_hero_detail()
	if _codex_layer != null and is_instance_valid(_codex_layer):
		_codex_layer.queue_free()
	_codex_layer = null
	_prune_videos()

func _codex_content(key: String) -> String:
	if key == "terrain":
		return """[color=#7a5a10][b]地形效果一览[/b][/color]

[color=#2e6b3c]0 空地[/color]：无特殊效果
[color=#55504a]1 障碍（可破坏）[/color]：不可通行
[color=#55504a]2 障碍（不可破坏）[/color]：不可通行

[color=#2e6b3c]3 森林[/color]：格内免伤 20%；移出时额外消耗 [b]1[/b] 点能量
[color=#2e6b3c]4 沼泽[/color]：格内速度 -30；移出时额外消耗 [b]1[/b] 点能量
[color=#2e6b3c]8 山地[/color]：格内伤害 +30%；移出时额外消耗 [b]2[/b] 点能量
[color=#2e6b3c]5 水域[/color]：禁止使用位移类技能；格内每回合末损失 1 点能量
[color=#2e6b3c]7 沙漠[/color]：禁止使用位移类技能；格内每回合末损失 0.5 点生命
[color=#2e6b3c]9 冰面[/color]：进入后沿移动方向持续滑行，直到离开冰面
[color=#2e6b3c]6 雪地[/color]：无特殊效果（待设计）

[color=#8a8578]说明：能量不足时无法从森林/沼泽/山地移出；地形增减伤与元素加成按乘法叠加。[/color]

[color=#ffd95a]当前棋盘[/color]
1V1：3×3 主对局区 + 双方各 1 个出生格
4V4 / 标准：8×8 主对局区 + 左右翼各 4 格"""
	if key == "rules":
		return Global.rules_text()
	# 武器图鉴：读取 Weapons.ALL 按档位展示
	var W = preload("res://scripts/combat/weapons.gd")
	var out := "[color=#7a5a10][b]武器图鉴[/b][/color]\n"
	for tier in W.tier_order():
		var ids: Array = W.ids_of_tier(tier)
		if ids.is_empty():
			continue
		out += "\n[color=#2e6b3c]━━ %s ━━[/color]\n" % tier
		for wid in ids:
			var d: Dictionary = W.get_def(str(wid))
			out += "[color=#b54a28][b]%s[/b][/color]（%s）\n" % [str(d.get("name", "")), str(d.get("element", ""))]
			var aff := str(d.get("affinity", ""))
			if aff != "":
				out += "　契合：%s\n" % aff
			var rt := W.recipe_text(str(wid))
			if rt != "—":
				out += "　合成：%s\n" % rt
			out += W.skills_text(str(wid))
	return out

## ---------- 英雄图鉴：卡片网格 ----------
func _open_hero_codex() -> void:
	var HD = preload("res://scripts/combat/hero_defs.gd")
	var layer := _make_codex_layer("英雄图鉴")
	var v: VBoxContainer = layer.get_meta("vbox")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for id in HD.ALL:
		if id == "demo_hero":
			continue   # 演示占位英雄不进图鉴
		grid.add_child(_hero_card(id, HD.ALL[id]))
	v.add_child(_codex_back_button(_close_codex))
	_codex_layer = layer

## 单张英雄卡片：头像 + 名字 + 元素（整块可点击）
func _hero_card(id: String, d: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(172, 252)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.98, 0.96, 0.92, 1.0)
	card_style.border_color = Color(0.65, 0.55, 0.40)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", card_style)
	btn.add_theme_stylebox_override("hover", card_style)
	btn.add_theme_stylebox_override("pressed", card_style)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vb)

	# 动态海报优先（视频），无视频才用静态立绘
	var vp := _make_dynamic_poster(id, Vector2(150, 188))
	if vp != null:
		vb.add_child(vp)
	else:
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(150, 188)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := _hero_portrait(id)
		if t != null:
			tex.texture = t
		vb.add_child(tex)

	var nm := Label.new()
	nm.text = str(d.get("name", id))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(0.55, 0.40, 0.10))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	var el := Label.new()
	el.text = "〔%s〕" % str(d.get("element", ""))
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.add_theme_font_size_override("font_size", 13)
	el.add_theme_color_override("font_color", Color(0.30, 0.45, 0.65))
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(el)

	if bool(d.get("wip", false)):
		var w := Label.new()
		w.text = "开发中"
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.add_theme_font_size_override("font_size", 12)
		w.add_theme_color_override("font_color", Color(0.55, 0.42, 0.20))
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(w)

	btn.pressed.connect(_open_hero_detail.bind(id))
	return btn

## ---------- 英雄详情：海报 + 详细数据 ----------
func _open_hero_detail(id: String) -> void:
	var HD = preload("res://scripts/combat/hero_defs.gd")
	if not HD.ALL.has(id):
		return
	var d: Dictionary = HD.ALL[id]
	if bool(d.get("wip", false)):
		_open_wip_detail(id, d)
		return
	_close_hero_detail()
	var layer := _make_codex_layer("%s 〔%s〕" % [str(d.get("name", id)), str(d.get("element", ""))], true)
	var v: VBoxContainer = layer.get_meta("vbox")

	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 30)
	v.add_child(hb)

	# 左：海报大图（动态海报优先）
	var dyn := _make_dynamic_poster(id, Vector2(420, 500), 10)
	if dyn != null:
		hb.add_child(dyn)
	else:
		var poster := TextureRect.new()
		poster.custom_minimum_size = Vector2(420, 480)
		poster.size_flags_vertical = Control.SIZE_EXPAND_FILL
		poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var t := _hero_portrait(id)
		if t != null:
			poster.texture = t
		hb.add_child(poster)

	# 右：详细数据（可滚动）
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(560, 0)
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
	rt.text = _hero_detail_bbcode(id)
	sc.add_child(rt)

	v.add_child(_make_hero_detail_buttons(id))
	_hero_detail_layer = layer

## 图鉴底部按钮行：若干按钮横排
func _make_codex_button_row(btns: Array) -> Control:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	for b in btns:
		var t: String = str(b[0])
		var cb: Callable = b[1]
		var btn := _cream_btn(Button.new())
		btn.text = t
		btn.pressed.connect(cb)
		hb.add_child(btn)
	return hb

## 详情页底部按钮行：[查看小传] [英雄故事] [返回]（无故事时英雄故事按钮不可点）
func _make_hero_detail_buttons(id: String) -> Control:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	var b1 := _cream_btn(Button.new())
	b1.text = "背景"
	if _has_bio(id):
		b1.pressed.connect(_open_bio_popup.bind(id))
	else:
		b1.disabled = true
		b1.tooltip_text = "该英雄的背景尚未撰写"
		b1.modulate = Color(1.0, 1.0, 1.0, 0.55)
	hb.add_child(b1)
	var b2 := _cream_btn(Button.new())
	b2.text = "英雄故事"
	if _has_story(id):
		b2.pressed.connect(_open_story_popup.bind(id))
	else:
		b2.disabled = true
		b2.tooltip_text = "该英雄的故事尚未撰写"
		b2.modulate = Color(1.0, 1.0, 1.0, 0.55)
	hb.add_child(b2)
	var b3 := _cream_btn(Button.new())
	b3.text = "返回"
	b3.pressed.connect(_close_hero_detail)
	hb.add_child(b3)
	return hb

## 开发中英雄详情：海报 + 制作状态 + 小传（数值/技能由制作者填充后并入正式详情）
func _open_wip_detail(id: String, d: Dictionary) -> void:
	_close_hero_detail()
	var layer := _make_codex_layer("%s 〔%s〕" % [str(d.get("name", id)), str(d.get("element", ""))], true)
	var v: VBoxContainer = layer.get_meta("vbox")
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 30)
	v.add_child(hb)
	var dyn := _make_dynamic_poster(id, Vector2(420, 500), 10)
	if dyn != null:
		hb.add_child(dyn)
	else:
		var poster := TextureRect.new()
		poster.custom_minimum_size = Vector2(420, 500)
		poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var t := _hero_portrait(id)
		if t != null:
			poster.texture = t
		hb.add_child(poster)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
	rt.custom_minimum_size = Vector2(560, 0)
	var txt := "[color=#2e6b3c]技能与数值制作中[/color]\n本英雄正在开发：立绘已就位、机制打磨中。点下方「背景」了解角色身世。\n"
	rt.text = txt
	sc.add_child(rt)
	v.add_child(_make_hero_detail_buttons(id))
	_hero_detail_layer = layer

func _close_hero_detail() -> void:
	if _hero_detail_layer != null and is_instance_valid(_hero_detail_layer):
		_hero_detail_layer.queue_free()
	_hero_detail_layer = null
	_prune_videos()

## 单个英雄的详细信息（BBCode）
func _hero_detail_bbcode(id: String) -> String:
	var HD = preload("res://scripts/combat/hero_defs.gd")
	var SE = preload("res://scripts/combat/skill_effects.gd")
	var d: Dictionary = HD.ALL.get(id, {})
	if d.is_empty():
		return ""
	var out := ""
	var emax: int = int(d.get("energy_max", int(d.get("energy", 0))))
	var en_txt := "%d / %d" % [int(d.get("energy", 0)), emax] if emax >= 0 else "%d（无上限）" % int(d.get("energy", 0))
	out += "[color=#7a5a10]基础属性[/color]\n"
	out += "  生命 %d　·　能量 %s　·　护甲 %d　·　速度 %d\n" % [int(d.get("hp", 0)), en_txt, int(d.get("armor", 0)), int(d.get("speed", 0))]
	# 特殊字段（有才显示）
	if d.has("shield_cap"):
		out += "  护盾上限 %d\n" % int(d["shield_cap"])
	if d.has("evasion_pct"):
		out += "  闪避 %d%%\n" % int(d["evasion_pct"])
	if d.has("sanity_cap"):
		out += "  理智上限 %d\n" % int(d["sanity_cap"])
	if d.has("element_damage_bonus"):
		var eb: Dictionary = d["element_damage_bonus"]
		for k in eb:
			out += "  对〔%s〕目标伤害 +%s%%\n" % [str(k), str(eb[k])]
	if d.has("counters"):
		var cs: Dictionary = d["counters"]
		for k in cs:
			var cv: Dictionary = cs[k]
			out += "  资源·%s：初始 %d" % [str(k), int(cv.get("start", 0))]
			if int(cv.get("per_turn", 0)) != 0:
				out += "，每回合 +%d" % int(cv["per_turn"])
			out += "\n"
	if d.has("death_revive"):
		var dr: Dictionary = d["death_revive"]
		out += "  复活：%d 回合后以 %s%% 生命复活（每局 %d 次）\n" % [int(dr.get("rounds", 0)), str(dr.get("hp_pct", 0)), int(dr.get("per_game", 1))]

	var sk: Dictionary = d.get("skills", {})
	var pid := str(sk.get("passive", ""))
	if pid != "":
		var pm: Dictionary = SE.DATA.get(pid, {})
		out += "\n[color=#2e5d9e]被动 · %s[/color]\n  %s\n" % [pm.get("name", pid), pm.get("desc", "")]
	var acts: Array = sk.get("actives", [])
	for i in range(acts.size()):
		var aid := str(acts[i])
		if aid == "":
			continue
		var am: Dictionary = SE.DATA.get(aid, {})
		var cost: int = int(am.get("energy_cost", 0))
		var kind_cn := "大招" if str(am.get("kind", "")) == "ultimate" else "技能"
		out += "\n[color=#2e6b3c]%s %d · %s[/color]（耗能 %d）\n  %s\n" % [kind_cn, i + 1, am.get("name", aid), cost, am.get("desc", "")]
	return out

## 读取英雄小传原文（story/bios/{id}.txt）；无文件返回空串
## 是否有背景资料（story/bios/{id}.txt）
func _has_bio(id: String) -> bool:
	return FileAccess.file_exists(_BIO_DIR + id + ".txt")

func _load_bio(id: String) -> String:
	var f := FileAccess.open(_BIO_DIR + id + ".txt", FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t.strip_edges()

## 解析小传：返回 {"tag": 首行八字评价, "sections": {"特质": "...", "身份": "...", "背景故事": "...", "台词": "..."}}
func _parse_bio(id: String) -> Dictionary:
	var raw := _load_bio(id)
	if raw == "":
		return {}
	var lines := raw.split("\n")
	var tag := ""
	var cur := ""
	var sections := {}
	var i := 0
	# 首非空行 = 八字评价（若无分段键则整行仍并入下一个模块）
	for l in lines:
		var s := l.strip_edges()
		if s == "":
			continue
		var is_key := false
		for k in ["特质：", "身份：", "背景故事：", "台词："]:
			if s.begins_with(k):
				is_key = true
				cur = k
				sections[cur] = ""
				# 支持「键：内容同行」——同行内容作为该模块首段
				var rem := s.substr(k.length()).strip_edges()
				if rem != "":
					sections[cur] += rem
				break
		if not is_key:
			if i == 0:
				tag = s
			else:
				sections[cur] += (("\n" if sections[cur] != "" else "") + s)
		i += 1
	return {"tag": tag, "sections": sections}

## 小传弹窗内容（BBCode 四模块美化）
func _bio_bbcode(parsed: Dictionary) -> String:
	var secs: Dictionary = parsed.get("sections", {})
	var out := ""
	var head_col := {"特质：": "#b54a28", "身份：": "#2e5d9e", "背景故事：": "#2e6b3c", "台词：": "#a06a10"}
	var order := ["特质：", "身份：", "背景故事：", "台词："]
	for k in order:
		if not secs.has(k):
			continue
		var body: String = str(secs[k])
		if body == "":
			continue
		var col: String = head_col.get(k, "#403a2e")
		out += "[color=%s][b]◆ %s[/b][/color]\n" % [col, k.trim_suffix("：")]
		# 台词模块逐句装饰；其他模块直接正文
		if k == "台词：":
			for q in body.split("\n"):
				var qq := q.strip_edges()
				if qq != "":
					out += "[color=#8a5f16]「%s」[/color]\n" % qq.trim_prefix('"').trim_suffix('"')
		else:
			out += "[color=#403a2e]%s[/color]\n\n" % body
	return out

var _bio_layer: Control = null
var _story_layer: Control = null

## 打开小传弹窗：模态遮罩 + 居中面板（标题/八字评价大字 + 滚动正文）
func _open_bio_popup(id: String) -> void:
	_close_bio_popup()
	var HD = preload("res://scripts/combat/hero_defs.gd")
	if not HD.ALL.has(id):
		return
	var d: Dictionary = HD.ALL[id]
	var parsed := _parse_bio(id)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.name = "BioPopup"
	add_child(layer)
	# 遮罩（点击关闭）
	var mask := ColorRect.new()
	mask.color = Color(0.05, 0.04, 0.02, 0.45)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_bio_popup())
	layer.add_child(mask)
	# 居中面板
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80.0
	panel.offset_top = 60.0
	panel.offset_right = -80.0
	panel.offset_bottom = -60.0
	panel.custom_minimum_size = Vector2(0, 0)
	layer.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.948, 0.905, 0.99)   # 米白面板
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.60, 0.52, 0.42)   # 暖棕边框
	panel.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(900, 640)
	panel.add_child(vb)
	# 标题行：名字（左）+ 关闭（右）
	var head := HBoxContainer.new()
	vb.add_child(head)
	var name_lab := Label.new()
	name_lab.text = "%s　〔%s〕" % [str(d.get("name", id)), str(d.get("element", ""))]
	name_lab.add_theme_font_size_override("font_size", 24)
	name_lab.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lab)
	var close_btn := _cream_btn(Button.new())
	close_btn.text = "✕ 关闭"
	close_btn.pressed.connect(_close_bio_popup)
	head.add_child(close_btn)
	# 八字评价行（装饰大字）
	var tag: String = str(parsed.get("tag", ""))
	if tag != "":
		var tag_lab := Label.new()
		tag_lab.text = "「 %s 」" % tag
		tag_lab.add_theme_font_size_override("font_size", 20)
		tag_lab.add_theme_color_override("font_color", Color(0.66, 0.46, 0.10))
		tag_lab.add_theme_constant_override("outline_size", 4)
		tag_lab.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.9, 0.75))
		vb.add_child(tag_lab)
	# 分隔线
	var sep := HSeparator.new()
	sep.modulate = Color(0.55, 0.45, 0.30, 0.5)
	vb.add_child(sep)
	# 正文：RichTextLabel 直接撑满剩余空间（自身带滚动，避免 ScrollContainer 内高度塌陷）
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
	rt.add_theme_font_size_override("normal_font_size", 16)
	var body := _bio_bbcode(parsed)
	if body == "":
		body = "[color=#8a8578]（小传整理中）[/color]"
	rt.text = body
	vb.add_child(rt)
	_bio_layer = layer

## 英雄故事数据源：
##   单篇：story/stories/{id}.txt（首行=标题，其余正文）——兼容早期写法
##   多篇：story/stories/{id}/*.txt（各自首行=标题，按文件名排序）
## 返回 [{title, text}]；无故事返回空数组
func _story_list(id: String) -> Array:
	var out: Array = []
	var single := _STORY_DIR + id + ".txt"
	if FileAccess.file_exists(single):
		var f := FileAccess.open(single, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			out.append(_split_story(raw))
	var dir := _STORY_DIR + id
	if DirAccess.dir_exists_absolute(dir):
		var d := DirAccess.open(dir)
		if d != null:
			d.list_dir_begin()
			var fn := d.get_next()
			while fn != "":
				if fn.ends_with(".txt") and not fn.begins_with("."):
					var f2 := FileAccess.open(dir + "/" + fn, FileAccess.READ)
					if f2 != null:
						var raw2 := f2.get_as_text()
						f2.close()
						out.append(_split_story(raw2))
				fn = d.get_next()
			d.list_dir_end()
	return out

## 拆成 {title, text}（首行标题，其余正文）
func _split_story(raw: String) -> Dictionary:
	var t := raw.strip_edges()
	if t == "":
		return {"title": "（无标题）", "text": ""}
	var lines := t.split("\n")
	var title := str(lines[0]).strip_edges()
	var body := ""
	for i in range(1, lines.size()):
		body += lines[i] + "\n"
	return {"title": title if title != "" else "（无标题）", "text": body}

func _load_story(id: String) -> String:
	var l := _story_list(id)
	return str(l[0].get("text", "")) if not l.is_empty() else ""

func _has_story(id: String) -> bool:
	return not _story_list(id).is_empty()

## 英雄故事入口：多篇则先弹「故事列表」，单篇直接进正文
func _open_story_popup(id: String) -> void:
	var list := _story_list(id)
	if list.is_empty():
		return
	if list.size() == 1:
		_open_story_read(id, 0)
	else:
		_open_story_index(id)

## 故事目录弹窗：列出每篇标题，点击阅读
func _open_story_index(id: String) -> void:
	_close_story_popup()
	var HD = preload("res://scripts/combat/hero_defs.gd")
	if not HD.ALL.has(id):
		return
	var d: Dictionary = HD.ALL[id]
	var list := _story_list(id)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.name = "StoryIndex"
	add_child(layer)
	var mask := ColorRect.new()
	mask.color = Color(0.05, 0.04, 0.02, 0.45)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_story_popup())
	layer.add_child(mask)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.985, 0.97, 0.93, 1.0)
	st.set_corner_radius_all(14)
	st.set_border_width_all(2)
	st.border_color = Color(0.60, 0.52, 0.42)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var h := Label.new()
	h.text = "%s · 英雄故事（共 %d 篇）" % [str(d.get("name", id)), list.size()]
	h.add_theme_font_size_override("font_size", 22)
	h.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(h)
	var sep := HSeparator.new()
	sep.modulate = Color(0.55, 0.45, 0.30, 0.5)
	vb.add_child(sep)
	for i in range(list.size()):
		var it: Dictionary = list[i]
		var b := _cream_btn(Button.new())
		b.text = "%d. %s" % [i + 1, str(it.get("title", "（无标题）"))]
		b.pressed.connect(_open_story_read.bind(id, i))
		vb.add_child(b)
	var bc := _cream_btn(Button.new())
	bc.text = "关闭"
	bc.pressed.connect(_close_story_popup)
	vb.add_child(bc)
	_story_layer = layer

## 英雄故事正文弹窗：标题大字 + 正文长文滚动
func _open_story_read(id: String, index: int) -> void:
	var list := _story_list(id)
	if index < 0 or index >= list.size():
		return
	_close_story_popup()
	var HD = preload("res://scripts/combat/hero_defs.gd")
	if not HD.ALL.has(id):
		return
	var d: Dictionary = HD.ALL[id]
	var stitle := str(list[index].get("title", "英雄故事"))
	var body := str(list[index].get("text", ""))
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.name = "StoryPopup"
	add_child(layer)
	var mask := ColorRect.new()
	mask.color = Color(0.05, 0.04, 0.02, 0.45)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_story_popup())
	layer.add_child(mask)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 100.0
	panel.offset_top = 70.0
	panel.offset_right = -100.0
	panel.offset_bottom = -70.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.985, 0.97, 0.93, 1.0)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.60, 0.52, 0.42)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var h_lab := Label.new()
	h_lab.text = "%s · 英雄故事" % str(d.get("name", id))
	h_lab.add_theme_font_size_override("font_size", 24)
	h_lab.add_theme_color_override("font_color", Color(0.36, 0.26, 0.12))
	h_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h_lab)
	var close_btn := _cream_btn(Button.new())
	close_btn.text = "✕ 关闭"
	close_btn.pressed.connect(_close_story_popup)
	head.add_child(close_btn)
	var t_lab := Label.new()
	t_lab.text = "「 %s 」" % stitle
	t_lab.add_theme_font_size_override("font_size", 20)
	t_lab.add_theme_color_override("font_color", Color(0.66, 0.46, 0.10))
	vb.add_child(t_lab)
	var sep := HSeparator.new()
	sep.modulate = Color(0.55, 0.45, 0.30, 0.5)
	vb.add_child(sep)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", Color(0.24, 0.19, 0.12))
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.text = body.replace("[", "［").replace("]", "］")
	vb.add_child(rt)
	_story_layer = layer

func _close_story_popup() -> void:
	if _story_layer != null and is_instance_valid(_story_layer):
		_story_layer.queue_free()
	_story_layer = null

func _close_bio_popup() -> void:
	if _bio_layer != null and is_instance_valid(_bio_layer):
		_bio_layer.queue_free()
	_bio_layer = null


## ================= 未开放提示 =================
var _locked_layer: Control = null

func _on_locked(name: String) -> void:
	_close_locked()
	## 2026-09-05 修复：同 hard_cfg —— 裸 Panel 高塌缩为 0 + 子内容溢出乱位 → 改 PanelContainer
	var rect := get_viewport_rect().size
	var layer := Panel.new()
	layer.anchor_left = 0; layer.anchor_top = 0; layer.anchor_right = 0; layer.anchor_bottom = 0
	layer.position = Vector2.ZERO
	layer.size = rect
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.19, 0.90)   # 半透明：透出背景视频（未开放提示层）
	layer.add_theme_stylebox_override("panel", sb)
	add_child(layer)
	_locked_layer = layer
	var cc := CenterContainer.new()
	cc.anchor_left = 0; cc.anchor_top = 0; cc.anchor_right = 0; cc.anchor_bottom = 0
	cc.position = Vector2.ZERO
	cc.size = rect
	layer.add_child(cc)
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.145, 0.176, 0.271)
	cs.set_corner_radius_all(16)
	cs.content_margin_left = 30
	cs.content_margin_right = 30
	cs.content_margin_top = 26
	cs.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(520, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	var t := Label.new()
	t.text = "暂未开放"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))
	box.add_child(t)
	var d := Label.new()
	d.text = "「%s」暂未开放，敬请期待。" % name
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 17)
	d.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	box.add_child(d)
	var back := Button.new()
	back.text = "回到主菜单"
	back.custom_minimum_size = Vector2(240, 48)
	back.pressed.connect(func():
		_close_locked()
		_on_to_menu())
	var bc := CenterContainer.new()
	bc.add_child(back)
	box.add_child(bc)

func _close_locked() -> void:
	if _locked_layer != null and is_instance_valid(_locked_layer):
		_locked_layer.queue_free()
	_locked_layer = null

## ================= 困难模式 · AI 后端选择弹窗 =================
var _hard_layer: Control = null
var _llm_btn: Button
var _local_btn: Button
var _online_lab: Label
var _hard_choice := "llm"
var _online_t0 := 0
var _online_done := true
var _online_http = null

func _open_hard_cfg() -> void:
	_close_hard_cfg()
	## 2026-09-05 修复：弹窗偏左下 = 裸 Panel 高度塌缩为 0（headless 实测 S=(560,0)），
	## 子内容溢出乱位 → 改 PanelContainer 自动包裹内容；layer/cc 显式撑满视口
	var rect := get_viewport_rect().size
	var layer := Panel.new()
	layer.anchor_left = 0; layer.anchor_top = 0; layer.anchor_right = 0; layer.anchor_bottom = 0
	layer.position = Vector2.ZERO
	layer.size = rect
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.19, 0.90)   # 半透明：透出背景视频（难度配置层）
	layer.add_theme_stylebox_override("panel", sb)
	add_child(layer)
	_hard_layer = layer
	var cc := CenterContainer.new()
	cc.anchor_left = 0; cc.anchor_top = 0; cc.anchor_right = 0; cc.anchor_bottom = 0
	cc.position = Vector2.ZERO
	cc.size = rect
	layer.add_child(cc)
	## 2026-09-05 修复①：裸 Panel 高度塌缩为 0 → 子内容溢出乱位（headless 实测 card S=(560,0)）
	## → 改 PanelContainer（自动包裹内容、聚合真实高度）使 CenterContainer 正确居中
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.145, 0.176, 0.271)
	cs.set_corner_radius_all(16)
	cs.border_color = Color(0.941, 0.780, 0.369, 0.5)
	cs.set_border_width_all(1)
	cs.content_margin_left = 26
	cs.content_margin_right = 26
	cs.content_margin_top = 26
	cs.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(560, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var t := Label.new()
	t.text = "困难模式 · 选择 AI 后端"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color(0.941, 0.780, 0.369))
	box.add_child(t)
	var sub := Label.new()
	sub.text = "战术模型更聪明多变（需要联网）；本地进阶 AI 离线也能打。"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	# 单选行
	_llm_btn = Button.new()
	_llm_btn.text = "🤖 豆包战术模型（集火/姿态/守护，需联网）"
	_llm_btn.toggle_mode = true
	_llm_btn.button_pressed = true
	_llm_btn.pressed.connect(_choose_llm)
	box.add_child(_llm_btn)
	_local_btn = Button.new()
	_local_btn.text = "💻 本地进阶 AI（离线可用）"
	_local_btn.toggle_mode = true
	_local_btn.pressed.connect(_choose_local)
	box.add_child(_local_btn)
	_online_lab = Label.new()
	_online_lab.text = "正在检测网络…"
	_online_lab.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_online_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_online_lab)
	# 底部按钮
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var ok := Button.new()
	ok.text = "开始（困难）"
	ok.add_theme_font_size_override("font_size", 17)
	ok.pressed.connect(_confirm_hard)
	row.add_child(ok)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(_close_hard_cfg)
	row.add_child(back)
	# 统一深色按钮样式（normal）
	for b in [_llm_btn, _local_btn, ok, back]:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.16, 0.19, 0.29)
		st.border_color = Color(0.45, 0.42, 0.30)
		st.set_border_width_all(1)
		st.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	_choose_llm()
	_check_online_async()

func _choose_llm() -> void:
	_hard_choice = "llm"
	if _llm_btn != null and _llm_btn.button_pressed:
		if _local_btn != null and _local_btn.button_pressed:
			_local_btn.button_pressed = false

func _choose_local() -> void:
	_hard_choice = "local"
	if _local_btn != null and _local_btn.button_pressed:
		if _llm_btn != null and _llm_btn.button_pressed:
			_llm_btn.button_pressed = false

## 异步联网检测：豆包轻问一句；带超时兜底（Godot 解析受限等环境因素也不卡 UI）
func _check_online_async() -> void:
	if _llm_btn == null:
		return
	_llm_btn.disabled = true
	_online_lab.text = "正在检测网络…"
	_online_t0 = Time.get_ticks_msec()
	_online_done = false
	if _online_http != null and is_instance_valid(_online_http):
		_online_http.queue_free()
	var http := HTTPRequest.new()
	_online_http = http
	add_child(http)
	var body := JSON.stringify({
		"model": "doubao-seed-evolving",
		## 2026-09-05 实测：必须关思考，否则响应 20s+ 必然超时误判"网络不可用"
		"thinking": {"type": "disabled"},
		"input": [{"role": "user", "content": [{"type": "input_text", "text": "OK"}]}],
	})
	var err := http.request(
		"https://ark.cn-beijing.volces.com/api/v3/responses",
		["Authorization: Bearer " + AICfg.api_key(), "Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)
	if err != OK:
		_set_online(false, "无法发起请求")
		return
	http.request_completed.connect(_online_done_cb)

func _online_done_cb(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _online_done:
		return
	_online_done = true
	var why := "网络正常" if code == 200 else "请求失败(%d)" % code
	_set_online(code == 200, why)

func _set_online(ok: bool, why: String) -> void:
	_online_done = true
	if _llm_btn == null:
		return
	if ok:
		_llm_btn.disabled = false
		_llm_btn.button_pressed = true
		_choose_llm()
		_online_lab.text = "网络正常：可选用豆包战术模型"
	else:
		_llm_btn.disabled = true
		_llm_btn.button_pressed = false
		_choose_local()
		_online_lab.text = "网络不可用（%s）：已用本地 AI" % why

func _online_poll() -> void:
	if _online_done or _online_t0 == 0:
		return
	if Time.get_ticks_msec() - _online_t0 > 7000:
		_set_online(false, "超时")
		if _online_http != null and is_instance_valid(_online_http):
			_online_http.queue_free()
			_online_http = null

func _confirm_hard() -> void:
	_config["difficulty"] = "hard"
	_config["ai_backend"] = _hard_choice
	Global.difficulty = "hard"
	Global.ai_backend = _hard_choice
	_close_hard_cfg()
	_show_panel("offline")

func _close_hard_cfg() -> void:
	if _hard_layer != null and is_instance_valid(_hard_layer):
		_hard_layer.queue_free()
	_hard_layer = null
