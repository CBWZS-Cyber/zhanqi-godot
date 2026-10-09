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

const BG_COLOR := UiDesign.APP_BG  # 深蓝灰
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
	UiTheme.attach(self)   # 全局墨金主题：补齐焦点环/Tooltip/菜单/滚动条；不覆盖已有 override
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	add_child(_bg)
	_setup_menu_bg_video()   # 背景视频层（可选资源：无视频文件则保持纯色背景）

	# 「新手教程」不放主按钮列（2026-10-05 用户要求）——
	# 它是**引导入口**、不是主流程，跟「图鉴 / 介绍」同属次级工具条；放一起更紧凑，
	# 也不再和「开始游戏」争视觉权重。
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
	crow.add_theme_constant_override("separation", 12)
	# 次级工具条：新手教程 + 图鉴 / 介绍。
	# ⚠️ 尺寸比主按钮**明显小一档**（原 190×48；加第 5 个后会把卡片顶到边缘，
	#    收到 158×44 —— 5 个正好一行，且一眼能看出它们是次级入口）。
	for e in [["新手教程", Callable(self, "_on_tutorial")],
			["英雄图鉴", Callable(self, "_open_codex").bind("hero")],
			["武器图鉴", Callable(self, "_open_codex").bind("weapon")],
			["地形介绍", Callable(self, "_open_codex").bind("terrain")],
			["规则介绍", Callable(self, "_open_codex").bind("rules")]]:
		var cb2 := _make_button(e[0], e[1])
		cb2.custom_minimum_size = Vector2(158, 44)
		cb2.set_meta("min_x", 158.0)
		cb2.set_meta("min_y", 44.0)
		cb2.set_meta("fz", 16.0)
		cb2.add_theme_font_size_override("font_size", 16)
		crow.add_child(cb2)
	start_vbox.add_child(crow)
	# 有视频背景时，开始界面的按钮半透明化，让视频更透出（其他界面不受影响）
	if ResourceLoader.exists(MENU_BG_VIDEO):
		_apply_start_btn_alpha(start_card)
	# 现已开放：联机（好友对战）/ 离线（PVE · 热座）/ 剧情（骑士线）/ 图鉴。
	# 仍是占位的：骑士线第二关及之后、凛黎线部分内容、武器图鉴 —— 点击弹「暂未开放」（_on_locked）。
	_build_screen("mode", "选择模式", 44, false,
		[["联机模式", Callable(self, "_show_panel").bind("online")],
		 ["单机模式", Callable(self, "_show_panel").bind("offline_type")],
		 ["剧情模式", Callable(self, "_show_panel").bind("story_sel")]], "start")
	# 2026-10-04：「选择网络（局域网 / 公网）」整个面板已删除 ——
	# 两条路的**玩家操作已经完全一样**（房主建房拿房间号 → 对方输号），
	# 底层是 ENet 直连还是 WebSocket 中继玩家看不见、也不该被要求选；
	# 且「公网对战（cpolar 内网穿透）」文案早已过时 —— 2026-10-03 起走自研反向隧道，房主无需装任何东西。
	# 现在联机固定走 `Global.net_transport`（默认 "ws" = 公网中继）。
	_build_screen("story_sel", "剧情模式 · 选择线路", 44, false,
		[["骑士线", Callable(self, "_on_story_knight")],
		 ["凛黎线", Callable(self, "_on_story_engineer")]], "start")
	_build_screen("story_knight", "骑士线 · 选择关卡", 44, false,
		[["第一关 · 白灵殿", Callable(self, "_on_story_knight_1")],
		 ["第二关（制作中）", Callable(self, "_on_locked").bind("骑士线第二关")]], "story_sel")
	_build_screen("online", "联机模式 · 好友对战", 44, false,
		[["建房（本机当主机·红方）", Callable(self, "_on_net_host")],
		 ["加入房间（蓝方）", Callable(self, "_show_panel").bind("net_join")]], "mode")
	_build_screen("net_join", "加入房间 · 输入房间号", 44, false,
		[["连接", Callable(self, "_on_net_join")]], "online")
	_build_screen("net_wait", "联机 · 等待连接", 44, false,
		[["取消并断开", Callable(self, "_on_net_cancel")]], "")
	_build_screen("online_pvp", "联机 · 选择对局（已连接）", 44, false,
		[["1V1 对战", Callable(self, "_on_net_battle").bind("1v1")],
		 ["4V4 对战", Callable(self, "_on_net_battle").bind("4v4")],
		 ["断开连接", Callable(self, "_on_net_cancel")]], "")
	_build_screen("offline_type", "单机模式 · 选择类型", 44, false,
		[["PVE · 人机对战", Callable(self, "_on_offline_type").bind("pve")],
		 ["热座模式 · 双人同机", Callable(self, "_on_offline_type").bind("hotseat")]], "mode")
	_build_screen("diff", "单机模式 · 选择难度", 44, false,
		[["简单", Callable(self, "_on_diff").bind("easy")],
		 ["普通（中等）", Callable(self, "_on_diff").bind("normal")],
		 ["困难（战术模型）", Callable(self, "_open_hard_cfg")]], "mode")
	_build_screen("offline", "单机模式 · 选择对局", 44, false,
		[["1V1", Callable(self, "_on_battle").bind("offline", "1v1")],
		 ["4V4", Callable(self, "_on_battle").bind("offline", "4v4")]], "diff")
	_build_result()
	_build_net_extras()
	_build_account_and_tutorial()
	_hook_net_signals()
	# ⚠️ 顺序要紧：**先 `_setup_cloud()` 定下登录态，再决定进哪一页**。
	#    原来 `_show_panel` 跑在它前面，账号行会读到还没置位的 `cloud_online`，
	#    于是"已登录却显示未登录"（2026-10-04 修过一次，这里彻底理顺）。
	_setup_cloud()
	_show_panel(_initial_panel())
	# 版本检查放最后：它只影响开始界面上的一个提示，失败也不阻断任何流程
	_check_update()
	get_viewport().size_changed.connect(_fit)
	call_deferred("_fit")

func _process(_delta: float) -> void:
	_fit()
	_online_poll()

## 每帧：字号/间距/最小尺寸按 _scale 真实重算（不用 Control.scale 放大，避免全屏文字发糊），
## 卡片取最新内容尺寸后绕中心居中。
##
## ⚠️⚠️ **本函数必须幂等：只在值真的变了才写控件**（2026-10-04 修「账号界面点一下输入框就卡」）。
##
## 原因（实测，不是推测）：以前每帧**无条件**调 `add_theme_constant_override` /
## `add_theme_font_size_override` / 写 `custom_minimum_size` / 写 `position`。
## 这些 API **即使写入的值与原来完全相同**，也会发通知：
##   · `add_theme_*_override` → `NOTIFICATION_THEME_CHANGED` → 容器重新排序
##   · `Control.position` setter → transform 变化通知
## 于是整棵可见面板树**每帧都被判定为"变了"**（约 30 张卡 × 5 次主题覆写 + 数百次字号覆写/帧）。
## 而面板里一旦有**获得焦点的 LineEdit**，祖先的 transform 通知会让它每帧去更新
## **输入法（IME）候选窗位置** —— 中文输入法下这是同步的 OS 调用，直接卡死。
## （headless 复现不出来：无窗口、无 IME。但 headless 能测出"值恒定而写入每帧都在发生"，
##   回归见 tests/mainui_fit_smoke.gd 的 `fit_writes` 断言。）
##
## 结论：**settled 之后本函数应当零写入**。改这里时务必保持每个写入点都有"变了才写"的判断。
var fit_writes := 0   ## 诊断计数：本帧实际写了几次控件（正常空闲时应停止增长）

func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = BASE
	_scale = clampf(min(vp.x / BASE.x, vp.y / BASE.y), 0.5, 2.4)
	if _bg.size != vp:
		_bg.size = vp
		fit_writes += 1
	if _bg.position != Vector2.ZERO:
		_bg.position = Vector2.ZERO
		fit_writes += 1

	# 各卡片 VBox 的间距/边距（走 _set_theme_int：缩放后的值没变就不写）
	for cf in _confs:
		var box: Variant = cf.get("box")
		if typeof(box) != TYPE_OBJECT or box == null or not is_instance_valid(box):
			continue
		var bc: Container = box as Container
		_set_theme_int(bc, cf, "separation", "sep")
		_set_theme_int(bc, cf, "margin_left", "ml")
		_set_theme_int(bc, cf, "margin_right", "mr")
		_set_theme_int(bc, cf, "margin_top", "mt")
		_set_theme_int(bc, cf, "margin_bottom", "mb")

	# 可见卡片：真实字号/尺寸 + 居中
	var p: Control = _panels.get(_current)
	if p != null and p.visible:
		_apply_node_sizes(p)
		var m := p.get_combined_minimum_size()
		if p.size != m:
			p.size = m
			fit_writes += 1
		if p.scale != Vector2.ONE:
			p.scale = Vector2.ONE
			fit_writes += 1
		if p.pivot_offset != Vector2.ZERO:
			p.pivot_offset = Vector2.ZERO
			fit_writes += 1
		var want := vp / 2.0 - m / 2.0
		if p.position != want:
			p.position = want
			fit_writes += 1


## 写一个主题常量，**只在缩放后的值变化时才写**。
## 缓存记在 cf 里（`_t_<key>`），所以换窗口尺寸时会自动重算，静止时零写入。
func _set_theme_int(bc: Container, cf: Dictionary, key: String, src: String) -> void:
	var want: int = int(float(cf.get(src, 0.0)) * _scale)
	var ck := "_t_" + key
	if int(cf.get(ck, -2147483647)) == want:
		return
	cf[ck] = want
	bc.add_theme_constant_override(key, want)
	fit_writes += 1


## 递归：把带 meta("fz"/"min_x"/"min_y") 的控件字号/最小尺寸乘 _scale
## ⚠️ 每个写入点都必须先判断"值变了没有" —— 理由见 _fit 的幂等说明（点输入框卡死的根因）
func _apply_node_sizes(n: Node) -> void:
	for ch in n.get_children():
		if not is_instance_valid(ch):
			continue
		if ch is Control:
			var co := ch as Control
			if co.has_meta("fz"):
				var sz: int = maxi(8, int(round(float(co.get_meta("fz")) * _scale)))
				if int(co.get_meta("_fz_applied", -1)) != sz:
					co.set_meta("_fz_applied", sz)
					if ch is Label:
						(co as Label).add_theme_font_size_override("font_size", sz)
					elif ch is Button:
						(co as Button).add_theme_font_size_override("font_size", sz)
					elif ch is LineEdit:
						# 输入框字号原先**从未被缩放**（这里只处理了 Label/Button），补上
						(co as LineEdit).add_theme_font_size_override("font_size", sz)
					fit_writes += 1
			if co.has_meta("min_x"):
				var wx := float(co.get_meta("min_x")) * _scale
				if not is_equal_approx(co.custom_minimum_size.x, wx):
					co.custom_minimum_size.x = wx
					fit_writes += 1
			if co.has_meta("min_y"):
				var hy := float(co.get_meta("min_y")) * _scale
				if not is_equal_approx(co.custom_minimum_size.y, hy):
					co.custom_minimum_size.y = hy
					fit_writes += 1
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
	# 弹层是**独立于面板叠加**的（不挂在 _panels 里），切面板时必须主动收起，
	# 否则会盖在新面板上。忘记密码弹层同理（2026-10-05 加）。
	_close_forgot_panel()
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
	# 热座没有难度页：从“选择对局”返回时应回“单机模式·选择类型”，而不是“选择难度”
	if to == "diff" and str(_config.get("offline_type", "pve")) == "hotseat":
		_show_panel("offline_type")
		return
	_show_panel(to)

# ---------- 联机（阶段4 MVP：好友房直连 · 1V1）----------
var _net_ip_edit: LineEdit = null
var _net_status_lab: Label = null
var _tunnel = null   # NetTunnel（cpolar 隧道；2026-10-03 起公网建房改走 _relay，保留以便回退）
var _relay = null    # NetRelayHost（自研反向隧道桥接器；preload，避免全局类缓存问题）
var _copy_room_btn: Button = null
var _room: NetRoomCode = null   # 房间号客户端（2026-09-30）

## 给 net_join 面板加房间号输入框、net_wait 面板加状态标签
func _build_net_extras() -> void:
	_init_roomcode()
	var pj: Control = _panels.get("net_join")
	if pj != null and pj.has_meta("vbox"):
		var box: Container = pj.get_meta("vbox")
		_net_ip_edit = LineEdit.new()
		# 不预填地址：玩家该看到的是提示语（2026-09-30 改；原来预填 127.0.0.1 容易被误当"就这样连"）
		_net_ip_edit.text = ""
		_net_ip_edit.placeholder_text = "%d 位房间号（也支持直接粘贴地址）" % NetRoomCode.CODE_LEN
		_net_ip_edit.custom_minimum_size = Vector2(420, 48)
		_net_ip_edit.set_meta("min_x", 420.0)
		_net_ip_edit.set_meta("min_y", 48.0)
		_net_ip_edit.add_theme_font_size_override("font_size", 18)
		# 回车即连接：输一串数字再去找"连接"按钮是多余的一步
		_net_ip_edit.text_submitted.connect(func(_t): _on_net_join())
		box.add_child(_net_ip_edit)
	var pw: Control = _panels.get("net_wait")
	if pw != null and pw.has_meta("vbox"):
		var box2: Container = pw.get_meta("vbox")
		_net_status_lab = Label.new()
		_net_status_lab.text = "…"
		_net_status_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_status_lab.add_theme_font_size_override("font_size", 18)
		_net_status_lab.add_theme_color_override("font_color", UiDesign.INK_200)
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
	# 拿到 cpolar 公网地址后，立刻向房间服务换一个 4 位数字号 —— 玩家之间传的就是这个号
	if _net_status_lab != null:
		_net_status_lab.text = "隧道已就绪，正在申请房间号…"
	if _room != null:
		_room.register(room, "tcp")

func _on_tunnel_failed(reason: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "公网房间创建失败：%s\n（中继服务器不可达？可稍后重试，或改用「直接填地址」）" % reason

## ================= 反向隧道（2026-10-03，替代 cpolar）=================
## 房主不用装任何东西：桥接器主动连中继 → 换回一个公网端口 → 用那个地址去换房间号。
## 于是**任何网络环境下，对方只要输房间号就能加入**。

func _init_relay() -> void:
	if _relay != null:
		return
	_relay = preload("res://scripts/net/net_relay_host.gd").new()
	_relay.relay_host = str(Global.net_relay_host)
	_relay.relay_port = int(Global.net_relay_port)
	add_child(_relay)
	_relay.ready_with_addr.connect(_on_relay_addr)
	_relay.failed.connect(_on_relay_failed)
	_relay.closed.connect(_on_relay_closed)
	_relay.peer_arrived.connect(_on_relay_peer_arrived)
	# net_wait 面板的「复制房间号」按钮（与 cpolar 路径共用）
	var pw: Control = _panels.get("net_wait")
	if pw != null and pw.has_meta("vbox") and _copy_room_btn == null:
		var box: Container = pw.get_meta("vbox")
		_copy_room_btn = _make_button("复制房间号", Callable(self, "_on_copy_room"))
		_copy_room_btn.visible = false
		box.add_child(_copy_room_btn)


func _on_relay_addr(addr: String) -> void:
	# 中继给了公网端口 → 立刻换 4 位房间号（玩家之间传的就是这个号）
	if _net_status_lab != null:
		_net_status_lab.text = "公网通道已就绪，正在申请房间号…"
	if _room != null:
		_room.register(addr, "tcp")


func _on_relay_failed(reason: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "公网房间创建失败：%s\n\n（中继服务器不可达？可稍后重试；房主也可改用「直接填地址」把地址发给你）" % reason


func _on_relay_closed() -> void:
	if _net_status_lab != null and Global.net_is_host:
		_net_status_lab.text = "公网通道已断开，房间失效 —— 请重新建房"


func _on_relay_peer_arrived() -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "有人进来了，正在建立连接…"

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
	if _copy_room_btn != null:
		_copy_room_btn.visible = false
	if Global.net_transport == "ws":
		if _net_status_lab != null:
			_net_status_lab.text = "正在创建公网房间（连接中继服务器）…"
		# 公网房（2026-10-03 起）：走**自研反向隧道** —— 房主主动连中继，换回一个公网端口，
		# 再用该地址去换房间号（见 _on_relay_addr）。**不再依赖 cpolar**，房主无需装任何东西。
		_init_relay()
		_relay.start(Global.net_port)
	else:
		# 局域网直连（ENet）。⚠️ 2026-10-04 起**没有 UI 入口**（「选择网络」面板已删），
		#   但**保留此分支**：它不依赖任何服务器，中继/房间服务全挂时仍是唯一的兜底路径。
		# 局域网房：把本机内网地址报给房间服务，对方**只输房间号**就能连（同一个路由器/热点下）
		if _net_status_lab != null:
			_net_status_lab.text = "已开房 [局域网 UDP %d]…\n正在申请房间号" % Global.net_port
		var lip := NetRoomCode.lan_ip()
		if lip == "":
			_on_room_failed("取不到本机局域网地址（没连 WiFi/网线？）")
		elif _room != null:
			_room.register("%s:%d" % [lip, Global.net_port], "lan")
	_show_panel("net_wait")

func _on_net_join() -> void:
	var raw := "" if _net_ip_edit == null else _net_ip_edit.text.strip_edges()
	if raw == "":
		_open_locked("请先输入房间号（让对方建房后把他屏幕上那串数字发你）")
		return
	Net.transport = Global.net_transport
	Global.net_is_host = false
	# 归一化：去掉空格/连字符（方便直接粘贴"482 9103 7562"）
	var compact := raw.replace(" ", "").replace("-", "").replace("－", "")
	var digits := NetRoomCode.clean_code(raw)
	if compact == digits and digits.length() == NetRoomCode.CODE_LEN:
		# 4 位纯数字 → 当房间号，去目录服务换地址
		if _net_status_lab != null:
			_net_status_lab.text = "正在查询房间号 %s …" % digits
		if _room == null:
			_on_room_failed("房间号组件没初始化（内部错误）")
			return
		_show_panel("net_wait")
		_room.resolve(digits)
		return
	# 不是房间号 → 按"直接给地址"的老路子连（房间服务不可用时的兜底，也方便本机测试）
	_join_address(raw)


## 把地址交给 NetSession 直连。ws 模式 addr 可带端口（内部会拼 ws://）；
## enet 模式要拆成 host + port 分开传（见 net_session.join_game 的两条分支）
func _join_address(addr: String) -> void:
	var err: int = OK
	if Global.net_transport == "ws":
		err = Net.join_game(addr, Global.net_port)
	else:
		var parts := addr.split(":")
		var host := str(parts[0])
		var port := Global.net_port
		if parts.size() > 1 and str(parts[1]).is_valid_int():
			port = int(parts[1])
		err = Net.join_game(host, port)
	if err != OK:
		_open_locked("连接失败（地址格式错误？err=%d）" % err)
		return
	if _net_status_lab != null:
		_net_status_lab.text = "正在连接 %s …" % addr
	_show_panel("net_wait")


## ================= 房间号（2026-09-30）=================

## 建房方：拿到房间号 → 大字显示 + 可复制
func _on_room_registered(code: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = ("房间号已生成，把它发给朋友：\n\n"
			+ "【 %s 】\n\n对方选「加入房间」输入这串数字即可。" % code)
	if _copy_room_btn != null:
		_copy_room_btn.visible = true
		_copy_room_btn.set_meta("room", code)      # _on_copy_room 直接复制这个


## 加入方：用房间号换到地址 → 直连
func _on_room_resolved(addr: String, kind: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = "房间号有效，正在连接…"
	_join_address(addr)


func _on_room_failed(reason: String) -> void:
	if _net_status_lab != null:
		_net_status_lab.text = ("房间号服务连不上：%s\n\n"
			+ "房主可以把「房间号」换成对方能直接访问的地址发给你（同一 WiFi 下填内网 IP）。\n"
			+ "（服务地址：%s）" % [reason, str(Global.net_room_service)])


func _init_roomcode() -> void:
	if _room != null and is_instance_valid(_room):
		return
	_room = NetRoomCode.new()
	# 服务地址在这里注入 —— NetRoomCode 刻意不引用 Global（否则 tests 里的 -s 模式编不过）
	var svc := str(Global.net_room_service)
	_room.service_url = svc if svc != "" else NetRoomCode.DEFAULT_SERVICE
	add_child(_room)
	_room.registered.connect(_on_room_registered)
	_room.resolved.connect(_on_room_resolved)
	_room.failed.connect(_on_room_failed)

## 传输方式取值：`Global.net_transport` —— "ws" = 公网中继（默认，输房间号即连）
## / "enet" = 局域网直连（2026-10-04 起暂无 UI 入口，代码保留作兜底，见 _on_net_host 注释）
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
	UiTheme.style_title(_level_name, 24)   # 关卡名：宋体档
	_level_name.add_theme_color_override("font_color", UiDesign.GOLD_400)
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
	st.bg_color = UiDesign.SURFACE_CARD if pos == 0 else UiDesign.SURFACE_CARD_DIM
	st.set_corner_radius_all(12)
	st.set_border_width_all(2)
	st.border_color = UiDesign.BORDER_STRONG
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
	nm.add_theme_color_override("font_color", UiDesign.INK_100)
	vb.add_child(nm)
	if bool(lv.get("locked", false)):
		var lk := Label.new()
		lk.text = "（制作中）"
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.add_theme_color_override("font_color", UiDesign.INK_400)
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
	card.modulate = UiDesign.MODULATE_SOFT

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

## （2026-10-04 删除）原 `_on_net_transport(t)`：设置 `Global.net_transport` 并改输入框占位符。
## 删因：入口面板（局域网 / 公网二选一）已整体移除，它再无调用点；
## 且它内部的占位符文案带 cpolar，还会**覆盖** `_build_net_extras()` 设好的干净占位符。
## 传输方式现在固定取 `Global.net_transport` 的默认值（"ws" = 公网中继）。

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
		parts.append("联机模式" if mode == "online" else "单机模式")
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
	_result_label.add_theme_color_override("font_color", UiDesign.INK_200)
	vbox.add_child(_result_label)
	vbox.add_child(_make_button("进入棋盘（占位）", Callable(self, "_on_enter_board")))
	vbox.add_child(_make_button("返回菜单", Callable(self, "_on_to_menu")))
	add_child(card)
	card.visible = false
	_panels["result"] = card

func _make_card(title: String, title_size: int, with_shadow: bool) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiDesign.SURFACE_CARD_GLASS   # 半透明卡片：透出背景视频
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
	t.add_theme_color_override("font_color", UiDesign.GOLD_500)  # 金色
	UiTheme.style_title(t, title_size)   # ≥30 走毛笔楷书（含字距），小字回落正文字体
	if with_shadow:
		t.add_theme_color_override("font_shadow_color", UiDesign.TEXT_SHADOW)
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
	# 主 CTA：金底深字 + 描边 + 焦点环，统一走组件库（原先手写 3 组金色 + 3 个深字色）
	UiTheme.style_button(btn, UiTheme.KIND_PRIMARY)
	btn.add_theme_font_size_override("font_size", UiDesign.FS_2XL)
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
const MENU_BG_DIM := UiDesign.OVERLAY_DIM   # 压暗遮罩：保证金色标题与按钮可读

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
	# 置顶：弹层必须压住一切（主菜单虽然没棋子，但保持一致、防以后复用踩坑）
	layer.z_index = UiDesign.Z_OVERLAY
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiDesign.SURFACE_GLASS if not opaque else UiDesign.SURFACE_GLASS_DEEP
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
	title.add_theme_color_override("font_color", UiDesign.GOLD_500)
	UiTheme.style_title(title, 32)   # 纸面标题也用毛笔楷书
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
	# 2026-10-04：原先是"奶油色"浅色皮肤（米白底 + 暖棕描边 + 深墨字）。
	# 面板整体转深色后，它改走组件库的**次级按钮** —— 工程里的「浅色子主题」至此彻底消失。
	UiTheme.style_button(b, UiTheme.KIND_SECONDARY)
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
		return """[color=#FFE08C][b]地形效果一览[/b][/color]

[color=#5EBF73]0 空地[/color]：无特殊效果
[color=#949EB8]1 障碍（可破坏）[/color]：不可通行
[color=#949EB8]2 障碍（不可破坏）[/color]：不可通行

[color=#5EBF73]3 森林[/color]：格内免伤 20%；移出时额外消耗 [b]1[/b] 点能量
[color=#5EBF73]4 沼泽[/color]：格内速度 -30；移出时额外消耗 [b]1[/b] 点能量
[color=#5EBF73]8 山地[/color]：格内伤害 +30%；移出时额外消耗 [b]2[/b] 点能量
[color=#5EBF73]5 水域[/color]：禁止使用位移类技能；格内每回合末损失 1 点能量
[color=#5EBF73]7 沙漠[/color]：禁止使用位移类技能；格内每回合末损失 0.5 点生命
[color=#5EBF73]9 冰面[/color]：进入后沿移动方向持续滑行，直到离开冰面
[color=#5EBF73]6 雪地[/color]：无特殊效果（待设计）

[color=#ADB8CC]说明：能量不足时无法从森林/沼泽/山地移出；地形增减伤与元素加成按乘法叠加。[/color]

[color=#ffd95a]当前棋盘[/color]
1V1：3×3 主对局区 + 双方各 1 个出生格
4V4 / 标准：8×8 主对局区 + 左右翼各 4 格"""
	if key == "rules":
		return RulesText.text()
	# 武器图鉴：读取 Weapons.ALL 按档位展示
	var W = preload("res://scripts/combat/weapons.gd")
	var out := "[color=#FFE08C][b]武器图鉴[/b][/color]\n"
	for tier in W.tier_order():
		var ids: Array = W.ids_of_tier(tier)
		if ids.is_empty():
			continue
		out += "\n[color=#5EBF73]━━ %s ━━[/color]\n" % tier
		for wid in ids:
			var d: Dictionary = W.get_def(str(wid))
			out += "[color=#EB7866][b]%s[/b][/color]（%s）\n" % [str(d.get("name", "")), str(d.get("element", ""))]
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
	card_style.bg_color = UiDesign.SURFACE_CARD
	card_style.border_color = UiDesign.BORDER_STRONG
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
	nm.add_theme_color_override("font_color", UiDesign.INK_100)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	var el := Label.new()
	el.text = "〔%s〕" % str(d.get("element", ""))
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.add_theme_font_size_override("font_size", 13)
	el.add_theme_color_override("font_color", UiDesign.INFO)
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(el)

	if bool(d.get("wip", false)):
		var w := Label.new()
		w.text = "开发中"
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.add_theme_font_size_override("font_size", 12)
		w.add_theme_color_override("font_color", UiDesign.INK_400)
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
	rt.add_theme_color_override("default_color", UiDesign.INK_100)
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
		b1.modulate = UiDesign.MODULATE_DIM
	hb.add_child(b1)
	var b2 := _cream_btn(Button.new())
	b2.text = "英雄故事"
	if _has_story(id):
		b2.pressed.connect(_open_story_popup.bind(id))
	else:
		b2.disabled = true
		b2.tooltip_text = "该英雄的故事尚未撰写"
		b2.modulate = UiDesign.MODULATE_DIM
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
	rt.add_theme_color_override("default_color", UiDesign.INK_100)
	rt.custom_minimum_size = Vector2(560, 0)
	var txt := "[color=#5EBF73]技能与数值制作中[/color]\n本英雄正在开发：立绘已就位、机制打磨中。点下方「背景」了解角色身世。\n"
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
	out += "[color=#FFE08C]基础属性[/color]\n"
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
		out += "\n[color=#4F8FD6]被动 · %s[/color]\n  %s\n" % [pm.get("name", pid), pm.get("desc", "")]
	var acts: Array = sk.get("actives", [])
	for i in range(acts.size()):
		var aid := str(acts[i])
		if aid == "":
			continue
		var am: Dictionary = SE.DATA.get(aid, {})
		var cost: int = int(am.get("energy_cost", 0))
		var kind_cn := "大招" if str(am.get("kind", "")) == "ultimate" else "技能"
		out += "\n[color=#5EBF73]%s %d · %s[/color]（耗能 %d）\n  %s\n" % [kind_cn, i + 1, am.get("name", aid), cost, am.get("desc", "")]
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
					out += "[color=#FFE08C]「%s」[/color]\n" % qq.trim_prefix('"').trim_suffix('"')
		else:
			out += "[color=#949EB8]%s[/color]\n\n" % body
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
	layer.z_index = UiDesign.Z_OVERLAY
	add_child(layer)
	# 遮罩（点击关闭）
	var mask := ColorRect.new()
	mask.color = UiDesign.OVERLAY_DIM
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
	style.bg_color = UiDesign.SURFACE_GLASS_DEEP   # 深色玻璃面板
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = UiDesign.BORDER_STRONG   # 暖棕边框
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
	name_lab.add_theme_color_override("font_color", UiDesign.INK_100)
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
		tag_lab.add_theme_color_override("font_color", UiDesign.GOLD_400)
		tag_lab.add_theme_constant_override("outline_size", 4)
		tag_lab.add_theme_color_override("font_outline_color", UiDesign.OVERLAY_SCRIM)
		vb.add_child(tag_lab)
	# 分隔线
	var sep := HSeparator.new()
	vb.add_child(sep)
	# 正文：RichTextLabel 直接撑满剩余空间（自身带滚动，避免 ScrollContainer 内高度塌陷）
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", UiDesign.INK_100)
	rt.add_theme_font_size_override("normal_font_size", 16)
	var body := _bio_bbcode(parsed)
	if body == "":
		body = "[color=#ADB8CC]（小传整理中）[/color]"
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
	layer.z_index = UiDesign.Z_OVERLAY
	add_child(layer)
	var mask := ColorRect.new()
	mask.color = UiDesign.OVERLAY_DIM
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_story_popup())
	layer.add_child(mask)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = UiDesign.SURFACE_GLASS_DEEP
	st.set_corner_radius_all(14)
	st.set_border_width_all(2)
	st.border_color = UiDesign.BORDER_STRONG
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
	UiTheme.style_title(h, 22)   # 故事列表标题：宋体档
	h.add_theme_color_override("font_color", UiDesign.GOLD_400)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(h)
	var sep := HSeparator.new()
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
	layer.z_index = UiDesign.Z_OVERLAY
	add_child(layer)
	var mask := ColorRect.new()
	mask.color = UiDesign.OVERLAY_DIM
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
	style.bg_color = UiDesign.SURFACE_GLASS_DEEP
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = UiDesign.BORDER_STRONG
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
	UiTheme.style_title(h_lab, 24)   # 故事详情标题：宋体档
	h_lab.add_theme_color_override("font_color", UiDesign.GOLD_400)
	h_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h_lab)
	var close_btn := _cream_btn(Button.new())
	close_btn.text = "✕ 关闭"
	close_btn.pressed.connect(_close_story_popup)
	head.add_child(close_btn)
	var t_lab := Label.new()
	t_lab.text = "「 %s 」" % stitle
	t_lab.add_theme_font_size_override("font_size", 20)
	t_lab.add_theme_color_override("font_color", UiDesign.GOLD_400)
	vb.add_child(t_lab)
	var sep := HSeparator.new()
	vb.add_child(sep)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", UiDesign.INK_100)
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
	layer.z_index = UiDesign.Z_OVERLAY
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiDesign.SURFACE_PANEL   # 半透明：透出背景视频（未开放提示层）
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
	cs.bg_color = UiDesign.INK_700
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
	t.add_theme_color_override("font_color", UiDesign.GOLD_500)
	box.add_child(t)
	var d := Label.new()
	d.text = "「%s」暂未开放，敬请期待。" % name
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 17)
	d.add_theme_color_override("font_color", UiDesign.INK_200)
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
	sb.bg_color = UiDesign.SURFACE_PANEL   # 半透明：透出背景视频（难度配置层）
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
	cs.bg_color = UiDesign.INK_700
	cs.set_corner_radius_all(16)
	cs.border_color = UiDesign.GOLD_DIM
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
	t.add_theme_color_override("font_color", UiDesign.GOLD_500)
	box.add_child(t)
	var sub := Label.new()
	sub.text = "战术模型更聪明多变（需要联网）；本地进阶 AI 离线也能打。"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", UiDesign.INK_200)
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
	_online_lab.add_theme_color_override("font_color", UiDesign.INK_250)
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
		st.bg_color = UiDesign.INK_700
		st.border_color = UiDesign.BTN_BORDER
		st.set_border_width_all(1)
		st.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_color_override("font_color", UiDesign.INK_100)
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

## 异步联网检测：问自家云服务要一个 ready 标志。
## 2026-10-04 改：不再直连火山方舟 —— 客户端已经没有 Key 了，战术模型改由云端代调。
## 这个 ping **不消耗模型额度**（服务端只查配置就绪，不调模型）。
## 把当前会话的 token 同步给战术模型客户端 —— 服务端据此把每日额度
## 从"未登录 3 次/设备"提到"登录后 10 次/账号"（见 server.js 的 GAME_QUOTA）。
## ⚠️ 三处会话变化都必须调：恢复会话 / 登录成功 / 登出。漏一处就会出现
##    "明明登录了却按 3 次算"（或反之），而且**只在额度用完时才看得出来**，很难查。
func _sync_ai_token() -> void:
	AICfg.auth_token = "" if _cloud == null else _cloud.token


## 把服务端回执的额度拼成一句人话（空串 = 老服务端没这个字段，文案保持不变）。
## ⚠️ 额度是**服务端**算的，这里只负责显示 —— 客户端改时间/改这串都没用。
func _quota_suffix(q: Dictionary) -> String:
	match str(q.get("tier", "")):
		"exempt":                       # 开发豁免（在服务器 quota_exempt.json 里的 IP）
			return "（本机不限次数）"
		"member":                       # 已登录
			return "（今日剩余 %d/%d 次）" % [int(q.get("left", 0)), int(q.get("limit", 0))]
		"guest":                        # 未登录
			var left := int(q.get("left", 0))
			if left <= 0:
				return "｜今日免费次数已用完，登录后每天 10 次"
			return "（今日剩余 %d 次，登录后每天 10 次）" % left
	return ""


func _check_online_async() -> void:
	if _llm_btn == null:
		return
	_llm_btn.disabled = true
	_online_lab.text = "正在检测云端…"
	_online_t0 = Time.get_ticks_msec()
	_online_done = false
	if _online_http != null and is_instance_valid(_online_http):
		_online_http.queue_free()
	var http := HTTPRequest.new()
	_online_http = http
	add_child(http)
	# 带上设备标识与 token：服务端据此回答"**你**今天还剩几次"。
	# 不带也能用（退化成按 IP 池算），只是数字不贴合本机。
	var hdrs: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if AICfg.auth_token != "":
		hdrs.append("Authorization: Bearer " + AICfg.auth_token)
	var err := http.request(AICfg.ping_url() + "?device_id=" + DeviceId.get_id().uri_encode(),
		hdrs, HTTPClient.METHOD_GET)
	if err != OK:
		_set_online(false, "无法发起请求")
		return
	http.request_completed.connect(_online_done_cb)

func _online_done_cb(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _online_done:
		return
	_online_done = true
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_online(false, "网络不可达")
		return
	if code != 200:
		_set_online(false, "云端返回 %d" % code)
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or not bool((d as Dictionary).get("ready", false)):
		_set_online(false, "云端还没配好战术模型")
		return
	var quota: Dictionary = {}
	var qv: Variant = (d as Dictionary).get("quota", {})
	if typeof(qv) == TYPE_DICTIONARY:
		quota = qv
	_set_online(true, _quota_suffix(quota))

func _set_online(ok: bool, why: String) -> void:
	_online_done = true
	if _llm_btn == null:
		return
	if ok:
		_llm_btn.disabled = false
		_llm_btn.button_pressed = true
		_choose_llm()
		_online_lab.text = "云端就绪：可选用豆包战术模型" + why
	else:
		_llm_btn.disabled = true
		_llm_btn.button_pressed = false
		_choose_local()
		_online_lab.text = "云端不可用（%s）：已用本地 AI" % why

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


# ======================================================================
# 新手教程 / 进度流程（2026-09-28 建；2026-10-04 账号上云；2026-10-05 删「本地账号」）
#
# 流程：谁在玩 → 你的水平怎么样（三档）→ 走教程则选角色 → 进 Tutorial 场景
#   · 「谁在玩」给两条路：
#       ① 云端登录 / 注册（zhanqi-cloud，进度跟账号走，换电脑能接着玩）
#       ② **离线玩**：不登录，直接用**本机匿名进度**（`ProgressStore`）——
#          没有名字、没有 id、不出现在任何列表；本机首次玩就是「0 进度原始账号」
#   **启动分流**（`_initial_panel()`，**只有下面三个分支**）：
#     · 有登录态（勾了「记住我」）→ `start`（主菜单，已登录）
#     · 没登录但**本机有离线进度** → `start`（接着上次的离线进度）
#     · 全新（什么都没有）→ `tut_login`（「谁在玩」页）
#   ⚠️ **`tut_level`（水平页）不由启动分流决定** —— 它是「谁在玩」**选完之后**才进：
#     · 点「离线玩」（`_on_offline_mode`）：本机进度 `tier` 为空 → `tut_level`，否则 `start`；
#     · 登录 / 注册成功（`_enter_cloud_account`）：云端进度 `tier` 为空 → `tut_level`，否则 `start`；
#     · 主菜单点「新手教程」（`_on_tutorial`）：`tier` 空 → `tut_level`；老手 → 提示后 `tut_level`；
#       其余 → `tut_hero`（选角色）。
#   ⇒ 所以**全新机器看到的第一屏是 `tut_login`，不是 `tut_level`**。
#   （2026-10-05 更正：原文写"进度还没选过水平 → 落到 tut_level"，把它错记成了启动分流的一支。）
#
# 数据流向：**「账号」只剩云端账号一种**（2026-10-05 按客户要求删掉了整套本地账号 ——
#   原 `AccountStore` / `user://accounts.json` / 登录页的「选择已有账号」全部作废）。
#   · 登录中 → 进度真源是**云端**：运行时在 `Global.player_progress`，
#     缓存于 `cloud_session.json` 的 `account.progress`（断网时靠它兜底）；
#   · 离线玩 → 进度真源是 `ProgressStore`（`user://progress.json`）。
#   **两份互不污染** —— 登出后点「离线玩」还是接着上次的离线进度。
# 写入统一走 `_save_progress()`；token 由 `CloudSession` 缓存在
# user://cloud_session.json（**不存密码**）。
# ======================================================================
const TUT_SCENE := "res://scenes/Tutorial.tscn"

var _acct_label: Label = null
var _login_edit: LineEdit = null
var _tier_note: Label = null
var _hero_note: Label = null
## 云端账号（2026-10-04）
var _login_name: LineEdit = null
var _login_pass: LineEdit = null
var _login_msg: Label = null
var _login_remember: CheckBox = null   # 「记住我（下次自动登录）」：不勾则下次启动不自动登录
var _sign_btn: Button = null           # start 面板的「退出登录 / 登录云端」（二合一，文案动态）
var _acct_row: HBoxContainer = null    # 账号信息 + 上面那个按钮，同处一行（紧跟标题）
## 注册才需要的几项（联系方式 + 验证码 + 渠道切换）：默认收起 —— 登录的人不必看它们
var _reg_box: VBoxContainer = null
## 联系方式输入框：**按渠道换语义**（短信 → 手机号；邮箱 → 邮件地址）。
## 名字用 contact 而不是 email，就是为了不再暗示"注册只能填邮箱"（2026-10-09 双通道）。
var _login_contact: LineEdit = null
var _login_code: LineEdit = null
var _code_btn: Button = null
var _btn_register: Button = null
## 注册渠道：默认**短信**（2026-10-09 用户定的"主用短信、邮箱作备选"）。
## `_reg_pending_ch` 记"码是从哪个渠道发出的" —— 回调文案必须跟发出时一致，
## 否则玩家在等码期间切了渠道，会看到"验证码已发到你的手机"但其实发的是邮箱。
var _reg_ch := CloudApi.CH_SMS
var _reg_pending_ch := ""
var _reg_btn_sms: Button = null
var _reg_btn_mail: Button = null
var _cloud: CloudApi = null
## 自动更新（2026-10-04）：UpdateCheck 只查清单，AutoUpdate 负责下载与替换
var _upd: UpdateCheck = null
var _auto: AutoUpdate = null
var _update_info: Dictionary = {}
var _update_note: Label = null
var _update_btn: Button = null
var _update_body: Label = null
var _update_bar: ProgressBar = null
var _update_apply: Button = null

func _build_account_and_tutorial() -> void:
	_build_acct_label()
	_build_login_panel()
	_build_tier_panel()
	_build_hero_panel()
	_build_update_panel()
	_build_update_widgets()
	_refresh_account_label()

## 开始界面标题下加一行「当前账号」
func _build_acct_label() -> void:
	var start_card: Control = _panels.get("start")
	if start_card == null or not start_card.has_meta("vbox"):
		return
	var vbox: VBoxContainer = start_card.get_meta("vbox")
	# 账号信息 + 账号操作做成**同一行**，紧跟标题。
	# ⚠️ 别让登出按钮单独占一行：它夹在「标题」和「开始游戏」之间会把主视觉流程切断
	#    （2026-10-04 用户截图实报："搞的什么呀"）。
	_acct_row = HBoxContainer.new()
	_acct_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_acct_row.add_theme_constant_override("separation", 18)

	_acct_label = Label.new()
	_acct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_acct_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_acct_label.set_meta("fz", 17.0)
	_acct_label.add_theme_font_size_override("font_size", 17)
	# ⚠️ 菜单背后是**视频**，浅灰字会被浅色画面吃掉（用户截图里那行几乎读不出来）
	#    → 用更亮的墨阶 + 深色描边，保证在任何画面上都可读。
	_acct_label.add_theme_color_override("font_color", UiDesign.INK_100)
	_acct_label.add_theme_color_override("font_outline_color", UiDesign.INK_950)
	_acct_label.add_theme_constant_override("outline_size", 6)
	_acct_row.add_child(_acct_label)

	# 退出/登录做成**文字按钮**（GHOST = 无底色，低频操作），并排在同一行右侧。
	# 原来用次级样式（深色底）会变成"三个金按钮中间夹一个深蓝块"，很突兀。
	_sign_btn = Button.new()
	_sign_btn.text = "退出登录"
	_sign_btn.set_meta("fz", 16.0)
	_sign_btn.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(_sign_btn, UiTheme.KIND_GHOST)
	# ⚠️ GHOST 按钮**没有底色**，压在浅色视频画面上几乎看不见（2026-10-05 用户截图证实
	#    "登录云端"四个字基本融入背景）→ 给它加**文字描边**，与同一行的账号文字用同一套
	#    可读性处理。这里**不换 KIND_SECONDARY**：换深色底会又变成"文字旁边杵一个深色块"，
	#    而这颗按钮是低频操作，轻是对的 —— 只要保证看得见。
	_sign_btn.add_theme_color_override("font_outline_color", UiDesign.INK_950)
	_sign_btn.add_theme_constant_override("outline_size", 6)
	_sign_btn.pressed.connect(_on_sign_action)
	_acct_row.add_child(_sign_btn)

	vbox.add_child(_acct_row)
	vbox.move_child(_acct_row, 1)   # 紧跟标题

## ① 谁在玩 —— 云端登录 / 注册 / **离线玩**（2026-10-04 账号上云）
func _build_login_panel() -> void:
	var card := _make_card("谁在玩？", 44, false)
	var vb: VBoxContainer = card.get_meta("vbox")

	var cached := CloudSession.cached_name(Global.cloud_service)
	var tip := "登录后进度跟着账号走，换台电脑也能接着玩。\n不想登录就点最下面的「离线玩」：直接开始，只是进度只留在这台电脑。\n（注册新账号要填手机号或邮箱来收验证码）"
	if cached != "":
		tip = "上次登录过「%s」，输密码就能继续。\n%s" % [cached, tip]
	vb.add_child(_small_label(tip, 16))

	_login_name = _make_edit("昵称", 420, 48, 20)
	if cached != "":
		_login_name.text = cached
	vb.add_child(_login_name)

	_login_pass = _make_edit("密码（至少 6 位）", 420, 48, 20)
	_login_pass.secret = true
	vb.add_child(_login_pass)

	_login_msg = _small_label("", 16)
	vb.add_child(_login_msg)

	# 「记住我」（2026-10-04 加）：不勾 → 下次启动**不自动登录**（昵称仍会预填，只需再输密码）。
	# 默认勾上 = 保持原来省事的行为；想让每台设备都必须输密码，就取消勾选。
	_login_remember = CheckBox.new()
	_login_remember.text = "记住我（下次自动登录）"
	_login_remember.button_pressed = true
	_login_remember.set_meta("fz", 17.0)
	_login_remember.add_theme_font_size_override("font_size", 17)
	_login_remember.add_theme_color_override("font_color", UiDesign.INK_200)
	var rrow := CenterContainer.new()
	rrow.add_child(_login_remember)
	vb.add_child(rrow)

	# —— 注册专用字段（默认收起；点「注册新账号」才展开，并把按钮改成「确认注册」）——
	# 为什么收起：登录只需昵称+密码，邮箱和验证码对登录的人是纯噪音。
	_reg_box = VBoxContainer.new()
	_reg_box.add_theme_constant_override("separation", 12)
	_reg_box.visible = false
	vb.add_child(_reg_box)

	# 渠道切换（2026-10-09）：两个**横排小按钮**互斥（用户点名要的形态）。
	# 为什么不做下拉框：只有两个选项，横排一眼看全，且少一次展开动作。
	var chrow := HBoxContainer.new()
	chrow.alignment = BoxContainer.ALIGNMENT_CENTER
	chrow.add_theme_constant_override("separation", 10)
	_reg_box.add_child(chrow)
	var chgrp := ButtonGroup.new()
	_reg_btn_sms = _make_channel_btn("短信验证", chgrp, Callable(self, "_on_reg_channel").bind(CloudApi.CH_SMS))
	_reg_btn_mail = _make_channel_btn("邮箱验证", chgrp, Callable(self, "_on_reg_channel").bind(CloudApi.CH_EMAIL))
	chrow.add_child(_reg_btn_sms)
	chrow.add_child(_reg_btn_mail)

	_login_contact = _make_edit("", 420, 48, 20)
	_reg_box.add_child(_login_contact)

	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 10)
	_reg_box.add_child(code_row)
	_login_code = _make_edit("6 位验证码", 250, 48, 20)
	_login_code.max_length = 6
	code_row.add_child(_login_code)
	_code_btn = _make_button("获取验证码", Callable(self, "_on_send_code"))
	code_row.add_child(_code_btn)
	_sync_reg_channel_ui()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	row.add_child(_make_button("登录", Callable(self, "_on_cloud_login")))
	_btn_register = _make_button("注册新账号", Callable(self, "_on_cloud_register"))
	row.add_child(_btn_register)

	# ⚠️ 这里**故意不叫「离线模式」**（2026-10-05 用户实报"未登录怎么会有账号？"）：
	#    登录页这个是**账号**维度；主菜单那个（现已改名「单机模式」）是**玩法**维度
	#    （vs 联机模式 / 剧情模式）。同名会把两件事搅到一起 —— 玩家点它时以为"我不要账号了"，
	#    进主菜单却看到「本机账号：曹博文」，于是觉得自相矛盾。
	#    改叫「离线玩」并把"不登录的是**云端**"写进去，歧义就没了。
	#    （2026-10-05 稍后：主菜单那个从「离线模式」再改名为「单机模式」—— 彻底没有同名词了。）
	vb.add_child(_make_button("离线玩（不登录云端）", Callable(self, "_on_offline_mode")))

	# 「忘记密码？」（2026-10-05 加）—— 走**次级**按钮、不抢主流程的视觉权重：
	# 它只在「这个昵称绑过邮箱」时才有用，不该和「登录」并列成两个大金块。
	var frow := CenterContainer.new()
	var forgot := _cream_btn(Button.new())
	forgot.text = "忘记密码？"
	forgot.custom_minimum_size = Vector2(200, 44)
	forgot.set_meta("min_x", 200.0)
	forgot.set_meta("min_y", 44.0)
	forgot.set_meta("fz", 17.0)
	forgot.add_theme_font_size_override("font_size", 17)
	forgot.focus_mode = Control.FOCUS_NONE
	forgot.pressed.connect(_open_forgot_panel)
	frow.add_child(forgot)
	vb.add_child(frow)

	add_child(card)
	card.visible = false
	_panels["tut_login"] = card

## ================= 忘记密码（2026-10-05 加）=================
## 两步：① 输昵称 → 服务端把 6 位重置码发到**该账号自己绑定的**邮箱
##       ② 输码 + 新密码 → 换掉密码，服务端直接下发新 token（= 已登录，不用再输一遍）
##
## ⚠️ 为什么按**昵称**找账号，而不是让玩家填邮箱：
##    服务端只按昵称建索引（`uid = sha256(小写昵称)`），邮箱没有索引；
##    更关键的是「码发到该账号**绑定的**邮箱」才是安全的 —— 谁也拿不到别人账号的重置码。
##    这条能成立，靠的是服务端那条设计：**只绑定验证过的邮箱**
##    （过渡档里"填了邮箱但没走验证码"一律存空），否则谁填上受害者的邮箱就能重置他密码。
## ⚠️ 老账号确实可能**没绑邮箱** → 服务端回 `masked=""`，这里必须给出明确出路，
##    不能让玩家对着"发送成功"干等一封永远不来的邮件。

var _forgot_layer: Control = null
var _forgot_name: LineEdit = null
var _forgot_code: LineEdit = null
var _forgot_pass: LineEdit = null
var _forgot_send_btn: Button = null
var _forgot_apply_btn: Button = null
var _forgot_msg: Label = null
var _forgot_step := 0        # 0 = 还没发码；1 = 已发码
var _forgot_lock_name := ""  # 发码后锁定的昵称（中途改掉会让第二步对不上账号）
## 找回渠道（2026-10-09）：默认短信。⚠️ 找回**不需要填联系方式** —— 码永远发到
## "该账号自己绑定的"那个号/邮箱，这是防"拿别人邮箱重置别人账号"的核心设计。
var _forgot_ch := CloudApi.CH_SMS
var _forgot_btn_sms: Button = null
var _forgot_btn_mail: Button = null

func _open_forgot_panel() -> void:
	_close_forgot_panel()
	_forgot_step = 0
	_forgot_lock_name = ""
	_forgot_ch = CloudApi.CH_SMS   # 每次打开都回到默认（短信优先），免得沿用上次留下的渠道

	var layer := Control.new()
	layer.name = "ForgotPopup"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = UiDesign.Z_OVERLAY          # 弹层必须压住一切（注意点 34）
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var mask := ColorRect.new()
	mask.color = UiDesign.OVERLAY_DIM
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_forgot_panel())
	layer.add_child(mask)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # 点卡片内部不误关
	var cs := StyleBoxFlat.new()
	cs.bg_color = UiDesign.SURFACE_MODAL            # **不透明**弹窗底（用户铁律）
	# ⚠️ 别用 SURFACE_GLASS_DEEP —— 那个是 0.96 半透的"详情页玻璃"，是给图鉴那种要透背景视频的
	#    页面用的；弹窗一律 SURFACE_MODAL（= INK_900，alpha 1.0）。这条被 F 段回归钉着。
	cs.set_corner_radius_all(16)
	cs.border_color = UiDesign.BORDER_STRONG
	cs.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", cs)
	layer.add_child(card)
	var mg := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(k, 28)
	card.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mg.add_child(vb)

	var ti := Label.new()
	ti.text = "找回密码"
	ti.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ti.add_theme_font_size_override("font_size", 30)
	ti.add_theme_color_override("font_color", UiDesign.GOLD_500)
	UiTheme.style_title(ti, 30)
	vb.add_child(ti)

	_forgot_msg = _small_label("填你的昵称，我们把 6 位验证码发到该账号绑定的手机号。", 15)
	vb.add_child(_forgot_msg)

	_forgot_name = _make_edit("你的昵称", 400, 48, 20)
	vb.add_child(_forgot_name)

	# 找回渠道（2026-10-09）：同样两个横排小按钮。
	var fchrow := HBoxContainer.new()
	fchrow.alignment = BoxContainer.ALIGNMENT_CENTER
	fchrow.add_theme_constant_override("separation", 10)
	vb.add_child(fchrow)
	var fchgrp := ButtonGroup.new()
	_forgot_btn_sms = _make_channel_btn("短信验证", fchgrp, Callable(self, "_on_forgot_channel").bind(CloudApi.CH_SMS))
	_forgot_btn_mail = _make_channel_btn("邮箱验证", fchgrp, Callable(self, "_on_forgot_channel").bind(CloudApi.CH_EMAIL))
	fchrow.add_child(_forgot_btn_sms)
	fchrow.add_child(_forgot_btn_mail)
	_sync_forgot_channel_ui()

	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 10)
	vb.add_child(crow)
	_forgot_code = _make_edit("6 位验证码", 240, 48, 20)
	_forgot_code.max_length = 6
	crow.add_child(_forgot_code)
	_forgot_send_btn = _make_button("发送验证码", Callable(self, "_on_forgot_send"))
	_forgot_send_btn.custom_minimum_size = Vector2(150, 48)
	_forgot_send_btn.set_meta("min_x", 150.0)
	_forgot_send_btn.set_meta("min_y", 48.0)
	_forgot_send_btn.set_meta("fz", 18.0)
	_forgot_send_btn.add_theme_font_size_override("font_size", 18)
	crow.add_child(_forgot_send_btn)

	_forgot_pass = _make_edit("新密码（至少 6 位）", 400, 48, 20)
	_forgot_pass.secret = true
	vb.add_child(_forgot_pass)

	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
	vb.add_child(brow)
	_forgot_apply_btn = _make_button("重置密码", Callable(self, "_on_forgot_apply"))
	brow.add_child(_forgot_apply_btn)
	var cancel := _cream_btn(Button.new())
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(140, 52)
	cancel.pressed.connect(_close_forgot_panel)
	brow.add_child(cancel)

	add_child(layer)
	_forgot_layer = layer
	_refresh_forgot_ui()
	if _forgot_name != null:
		# 顺手带上登录页已填的昵称（省一次输入）
		if _login_name != null and _login_name.text.strip_edges() != "":
			_forgot_name.text = _login_name.text.strip_edges()
		_forgot_name.grab_focus()

## 按步骤启用/禁用：没发码之前验证码与新密码是灰的 —— 免得玩家对着空框干点、点了没反应
func _refresh_forgot_ui() -> void:
	var sent := _forgot_step >= 1
	if _forgot_name != null:
		_forgot_name.editable = not sent     # 发码后锁住昵称，保证第二步对得上同一个账号
	if _forgot_code != null:
		_forgot_code.editable = sent
	if _forgot_pass != null:
		_forgot_pass.editable = sent
	if _forgot_send_btn != null:
		_forgot_send_btn.disabled = sent
	if _forgot_apply_btn != null:
		_forgot_apply_btn.disabled = not sent
	# 发码后锁渠道：否则玩家可能切到另一种渠道，然后拿"另一个渠道的码"去撞
	if _forgot_btn_sms != null:
		_forgot_btn_sms.disabled = sent
	if _forgot_btn_mail != null:
		_forgot_btn_mail.disabled = sent


## 把找回面板的渠道按钮与提示文案同步成当前渠道
func _sync_forgot_channel_ui() -> void:
	var sms := _forgot_ch == CloudApi.CH_SMS
	for pair in [[_forgot_btn_sms, sms], [_forgot_btn_mail, not sms]]:
		var b: Button = pair[0]
		if b != null:
			b.button_pressed = bool(pair[1])
			b.text = ("● " if bool(pair[1]) else "○ ") + str(b.get_meta("ch_label"))
	if _forgot_msg != null and _forgot_step == 0:
		_forgot_msg.text = "填你的昵称，我们把 6 位验证码发到该账号绑定的手机号。" if sms \
			else "填你的昵称，我们把 6 位验证码发到该账号绑定的邮箱。"


func _on_forgot_channel(ch: String) -> void:
	if ch == _forgot_ch or _forgot_step >= 1:
		return
	_forgot_ch = ch
	if _forgot_code != null:
		_forgot_code.text = ""
	_sync_forgot_channel_ui()


func _close_forgot_panel() -> void:
	if _forgot_layer != null and is_instance_valid(_forgot_layer):
		_forgot_layer.queue_free()
	_forgot_layer = null
	_forgot_name = null
	_forgot_code = null
	_forgot_pass = null
	_forgot_send_btn = null
	_forgot_apply_btn = null
	_forgot_msg = null
	_forgot_step = 0
	_forgot_lock_name = ""
	_forgot_btn_sms = null
	_forgot_btn_mail = null

func _fmsg(t: String) -> void:
	if _forgot_msg != null and is_instance_valid(_forgot_msg):
		_forgot_msg.text = t

func _on_forgot_send() -> void:
	var nm := "" if _forgot_name == null else _forgot_name.text.strip_edges()
	if nm == "":
		_fmsg("先填你的昵称")
		return
	if _cloud == null:
		_fmsg("云端组件没就绪，稍后再试")
		return
	_fmsg("正在发送…")
	_forgot_lock_name = nm
	if _forgot_ch == CloudApi.CH_SMS:
		_cloud.send_reset_code_sms(nm)
	else:
		_cloud.send_reset_code(nm)

func _on_forgot_send_done(ok: bool, msg: String) -> void:
	if _forgot_layer == null or not is_instance_valid(_forgot_layer):
		return          # 面板已被关掉，丢弃迟到的回调
	if not ok:
		_fmsg(msg)
		return
	if msg == "":
		# 空掩码 = 该账号**没绑这个联系方式**（老账号，或绑的是另一种渠道）。
		# 服务端故意不区分"昵称不存在"与"没绑"（防枚举），所以出路得由界面给出。
		var cur := "手机号" if _forgot_ch == CloudApi.CH_SMS else "邮箱"
		var other := "邮箱" if _forgot_ch == CloudApi.CH_SMS else "短信"
		_fmsg("这个账号没有绑定%s，没法用这种方式找回。\n点上面「%s验证」再试一次，或找作者帮你重置。" % [cur, other])
		return
	_forgot_step = 1
	_refresh_forgot_ui()
	_fmsg("验证码已发到 %s（5 分钟内有效）。\n填上验证码和新密码，再点「重置密码」。" % msg)
	if _forgot_code != null:
		_forgot_code.grab_focus()

func _on_forgot_apply() -> void:
	var cd := "" if _forgot_code == null else _forgot_code.text.strip_edges()
	var pw := "" if _forgot_pass == null else _forgot_pass.text
	if _forgot_lock_name == "":
		_fmsg("请先点「发送验证码」")
		return
	if cd.length() != 6 or not cd.is_valid_int():
		_fmsg("请填 6 位数字验证码")
		return
	if pw.length() < 6:
		_fmsg("新密码至少 6 位")
		return
	if _cloud == null:
		_fmsg("云端组件没就绪，稍后再试")
		return
	_fmsg("正在重置…")
	if _forgot_ch == CloudApi.CH_SMS:
		_cloud.reset_password_sms(_forgot_lock_name, cd, pw)
	else:
		_cloud.reset_password(_forgot_lock_name, cd, pw)

func _on_forgot_reset_done(ok: bool, account: Dictionary, error: String) -> void:
	if not ok:
		if _forgot_layer != null and is_instance_valid(_forgot_layer):
			_fmsg(error)
		return
	_close_forgot_panel()
	# 重置成功 = 服务端已下发新 token → 直接走**同一套登录收尾**（缓存 token / 写进度 / 刷新账号行）
	_enter_cloud_account(account)


## ② 你的水平怎么样（三档）
func _build_tier_panel() -> void:
	var card := _make_card("你的水平怎么样？", 44, false)
	var vb: VBoxContainer = card.get_meta("vbox")
	vb.add_child(_small_label("这决定教程给你讲多少 —— 老手不必再看一遍基础操作。", 16))
	vb.add_child(_make_button("我是新手，从零开始", Callable(self, "_on_tier").bind(ProgressStore.TIER_NEW)))
	vb.add_child(_make_button("玩过战棋，只讲本作规则", Callable(self, "_on_tier").bind(ProgressStore.TIER_PLAYED)))
	vb.add_child(_make_button("我是老手，直接开始", Callable(self, "_on_tier").bind(ProgressStore.TIER_VETERAN)))
	_tier_note = _small_label("", 16)
	vb.add_child(_tier_note)
	add_child(card)
	card.visible = false
	_panels["tut_level"] = card

## ③ 选教程使用的角色
func _build_hero_panel() -> void:
	var card := _make_card("教程用哪个角色？", 44, false)
	var vb: VBoxContainer = card.get_meta("vbox")
	vb.add_child(_small_label("四个角色演示的东西不同，挑一个你顺眼的就行（教程里讲的操作是通用的）。", 16))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var TD = load("res://scripts/combat/tutorial_defs.gd")
	var HD = load("res://scripts/combat/hero_defs.gd")
	for e in TD.HEROES:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		var hid := str(e["id"])
		var b := _make_button(str(HD.ALL[hid]["name"]), Callable(self, "_on_tut_hero").bind(hid))
		b.set_meta("min_x", 240.0)
		b.custom_minimum_size = Vector2(240, 60)
		col.add_child(b)
		col.add_child(_small_label(str(e["tag"]), 15))
		row.add_child(col)
	_hero_note = _small_label("", 16)
	vb.add_child(_hero_note)
	vb.add_child(_make_button("返回", Callable(self, "_show_panel").bind("start")))
	add_child(card)
	card.visible = false
	_panels["tut_hero"] = card


## ④ 发现新版本（2026-10-04）：说明页。正文在 _on_update_checked 里动态填。
##   2026-10-04 起支持**自动下载并替换**（AutoUpdate），进度条与「重启更新」都在本页。
func _build_update_panel() -> void:
	var card := _make_card("发现新版本", 44, false)
	var vb: VBoxContainer = card.get_meta("vbox")
	_update_body = _small_label("", 17)
	_update_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(_update_body)

	# 下载进度条：只在下载过程中出现（皮肤由 UiTheme 统一）
	_update_bar = ProgressBar.new()
	_update_bar.min_value = 0.0
	_update_bar.max_value = 1.0
	_update_bar.step = 0.001
	_update_bar.value = 0.0
	_update_bar.show_percentage = true
	_update_bar.custom_minimum_size = Vector2(420, 26)
	_update_bar.set_meta("min_x", 420.0)
	_update_bar.set_meta("min_y", 26.0)
	_update_bar.visible = false
	vb.add_child(_update_bar)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	row.add_child(_make_button("立即更新", Callable(self, "_on_update_download")))
	_update_apply = _make_button("重启更新", Callable(self, "_on_update_apply"))
	_update_apply.visible = false
	row.add_child(_update_apply)
	row.add_child(_make_button("以后再说", Callable(self, "_show_panel").bind("start")))
	add_child(card)
	card.visible = false
	_panels["update"] = card


## 开始界面底部挂「发现新版本」提示：默认隐藏 —— 只有真检测到新版才显示
func _build_update_widgets() -> void:
	var start_card: Control = _panels.get("start")
	if start_card == null or not start_card.has_meta("vbox"):
		return
	var vb: VBoxContainer = start_card.get_meta("vbox")
	_update_note = _small_label("", 16)
	_update_note.visible = false
	vb.add_child(_update_note)
	_update_btn = _make_button("查看更新", Callable(self, "_show_panel").bind("update"))
	_update_btn.custom_minimum_size = Vector2(190, 44)
	_update_btn.set_meta("min_x", 190.0)
	_update_btn.set_meta("min_y", 44.0)
	_update_btn.set_meta("fz", 17.0)
	_update_btn.add_theme_font_size_override("font_size", 17)
	_update_btn.visible = false
	vb.add_child(_update_btn)


## 渠道切换按钮（2026-10-09 双通道）：两个**横排小按钮**互斥（用户点名要的形态）。
## ⚠️ 选中态用**文字前缀**（● / ○）而不只靠底色 —— `style_button` 只有
##    normal/hover/pressed 三态、没有专门的 toggle 皮肤，仅靠底色在深色卡片上不够显眼。
## 原始文案存在 meta 里，切换时重新拼前缀（别在 text 上反复加）。
func _make_channel_btn(txt: String, grp: ButtonGroup, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = grp
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 44)
	b.set_meta("min_x", 150.0)
	b.set_meta("min_y", 44.0)
	b.set_meta("fz", 17.0)
	b.set_meta("ch_label", txt)
	b.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(b, UiTheme.KIND_SECONDARY)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			cb.call())
	return b


## 手机号归一化：去空格 / 横线，去 `+86`（或 13 位的 `86…`）前缀。
## 服务端也会归一，但**客户端先归**才能正确预校验，且发出去的就是干净号码。
func _norm_phone(s: String) -> String:
	var t := s.strip_edges().replace(" ", "").replace("-", "")
	if t.begins_with("+86"):
		t = t.substr(3)
	elif t.begins_with("86") and t.length() == 13:
		t = t.substr(2)
	return t


## 只做"像不像大陆手机号"的粗判（11 位、1 开头）。真正的校验在服务端。
func _looks_like_phone(s: String) -> bool:
	var t := _norm_phone(s)
	return t.length() == 11 and t.begins_with("1") and t.is_valid_int()


## 统一样式的输入框（沿用 min_x/min_y/fz 自适应约定，_fit() 会按窗口缩放）
func _make_edit(placeholder: String, w: float, h: float, fz: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(w, h)
	e.set_meta("min_x", w)
	e.set_meta("min_y", h)
	e.set_meta("fz", fz)
	UiTheme.style_input(e, w, h)   # 补上原本完全缺失的输入框皮肤 + 聚焦金环
	return e


func _small_label(txt: String, sz: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	l.set_meta("fz", float(sz))
	l.add_theme_color_override("font_color", UiDesign.INK_250)
	return l


## 刷新开始界面那一行。
## ⚠️ 2026-10-05 起**只有两种形态**（「本地账号」整套已按客户要求删除）：
##   · 已登录 → 「云端账号：名字 · 水平 · 教程进度」+ 右侧「退出登录」
##   · 离线玩 → 「离线游玩（进度只在这台电脑）」，**不出现任何名字**（本机没有账号了）
## 连不连云端由按钮文案表达；标签既不重复说，也不写「未登录」
##（那是客户 2026-10-05 两问"未登录怎么会有账号？"之后定下的）。
func _refresh_account_label() -> void:
	if _acct_label == null:
		return
	var p: Dictionary = Global.player_progress
	var t := ProgressStore.tier_label(str(p.get("tier", "")))
	var done := "已过教程" if bool(p.get("tutorial_done", false)) else "未过教程"
	if Global.cloud_online and not Global.cloud_account.is_empty():
		_acct_label.text = "云端账号：%s　·　%s　·　%s" % [
			str(Global.cloud_account.get("name", "?")), t, done]
		if _sign_btn != null:
			_sign_btn.text = "退出登录"
			_sign_btn.visible = true
	else:
		_acct_label.text = "离线游玩（进度只在这台电脑）"
		if _sign_btn != null:
			_sign_btn.text = "登录云端"
			_sign_btn.visible = true


# ======================================================================
# 云端账号 / 自动更新（2026-10-04）
#
# 云服务：tools/cloud-service/server.js（端口 8789）—— 版本清单 + 账号 + 进度。
# 账号存服务器本地（一人一个 JSON 小文件，见 store.js 头注释），OSS 负责
# 安装包分发与账号冷备。
# ======================================================================

## 启动该进哪一页（2026-10-05）：
##   · 有登录态（勾过「记住我」）→ 主菜单，已登录
##   · 没登录但本机有**离线进度** → 主菜单，接着上次的离线进度
##   · 全新（什么都没有）→ 登录页
## ⚠️ 必须在 `_setup_cloud()` **之后**调用 —— 只有它知道这次算不算已登录。
func _initial_panel() -> String:
	if Global.cloud_online:
		return "start"
	if ProgressStore.has_any():
		Global.player_progress = ProgressStore.load_progress()   # 读进内存，主菜单才有东西显示
		return "start"
	return "tut_login"


## 把云端账号里的 `progress` 规格化成运行时进度字典。
## 集中一处做，免得各处手抄字段名（少抄一个就是"进度莫名丢失"）。
func _progress_from_cloud(account: Dictionary) -> Dictionary:
	var prog: Dictionary = account.get("progress", {})
	return {
		"v": 1,
		"tier": str(prog.get("tier", "")),
		"tutorial_done": bool(prog.get("tutorial_done", false)),
		"tutorial_hero": str(prog.get("tutorial_hero", "")),
	}


## 建好 CloudApi / UpdateCheck 并把信号接上（_ready 里调一次）
func _setup_cloud() -> void:
	_cloud = CloudApi.new()
	_cloud.service_url = Global.cloud_service
	add_child(_cloud)
	_cloud.register_done.connect(_on_cloud_register_done)
	_cloud.login_done.connect(_on_cloud_login_done)
	_cloud.progress_done.connect(_on_cloud_progress_done)
	_cloud.send_code_done.connect(_on_send_code_done)
	_cloud.reset_code_done.connect(_on_forgot_send_done)
	_cloud.reset_password_done.connect(_on_forgot_reset_done)

	# 上次登录过就直接复用 token（30 天有效），不额外验一次 ——
	# 真过期了，上传进度会被 401 拒，那时再让他重新登录即可。
	var sess := CloudSession.load_session(Global.cloud_service)
	if not sess.is_empty():
		_cloud.token = str(sess.get("token", ""))
		_cloud.account = sess.get("account", {})
		_sync_ai_token()          # 战术模型额度按"已登录 10 次/天"算
		Global.cloud_online = true
		Global.cloud_account = sess.get("account", {})
		# 进度也从会话缓存恢复 —— 断网时这就是唯一来源（云端的副本本来就存在 session 里）
		Global.player_progress = _progress_from_cloud(Global.cloud_account)
		# 回到主菜单时顺手把本地进度推一次（教程里改过的角色选择等能补上）。
		# 延迟一帧：那时 _cloud 的 _ready 已跑完，HTTPRequest 就绪。
		call_deferred("_sync_cloud_progress")

	# 困难难度的战术模型改由云端代调（客户端已经没有 API Key 了，见 AICfg 头注释）。
	# 在这里注入一次即可 —— AICfg 是静态类，全工程共用同一个端点。
	AICfg.endpoint = Global.cloud_service.rstrip("/") + "/llm"

	# ⚠️ 必须在这里**补刷一次**账号标签：`_ready` 里 `_build_account_and_tutorial()`
	#    （含它内部的首次刷新）跑在 `_setup_cloud()` **之前** —— 那一刻 cloud_online
	#    还是 false，标签会错显"未登录"，而玩家的会话其实是好的
	#    （2026-10-04 用户截图实报）。到这里"是否已登录"才最终确定。
	if _acct_label != null:
		_refresh_account_label()


## 启动时异步查一次新版本。失败一律静默 —— 绝不能因为"检查更新"挡住玩家进游戏。
func _check_update() -> void:
	_upd = UpdateCheck.new()
	add_child(_upd)
	_upd.finished.connect(_on_update_checked)
	_upd.check(Global.cloud_service + "/version.json")

	# 下载器（2026-10-04）：只管下载/解压/写更新脚本；何时启动由 _on_update_download 决定。
	_auto = AutoUpdate.new()
	add_child(_auto)
	_auto.progress.connect(_on_update_progress)
	_auto.update_ready.connect(_on_update_ready)
	_auto.failed.connect(_on_update_failed)


func _on_update_checked(res: Dictionary) -> void:
	if not bool(res.get("ok", false)) or not bool(res.get("has_update", false)):
		return
	_update_info = res
	var latest := str(res.get("latest", ""))
	if _update_note != null:
		_update_note.text = "发现新版本 v%s（本机 v%s）" % [latest, str(res.get("current", ""))]
		_update_note.visible = true
	if _update_btn != null:
		_update_btn.visible = true
	if _update_body != null:
		_update_body.text = _update_text(res)
	# 上次已下好却没重启 → 直接亮出「重启更新」，别让玩家白下第二遍（上百 MB）
	if _auto != null:
		var prepared := _auto.prepared_version()
		if prepared != "" and prepared == latest:
			_on_update_ready(prepared)


func _update_text(res: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("本机版本：v%s　　最新版本：v%s" % [str(res.get("current", "")), str(res.get("latest", ""))])
	var size := str(res.get("size", ""))
	if size != "":
		lines.append("安装包大小：%s" % size)
	var notes: Variant = res.get("notes", PackedStringArray())
	if typeof(notes) == TYPE_ARRAY and (notes as Array).size() > 0:
		lines.append("")
		lines.append("这一版更新了什么：")
		for n in (notes as Array):
			lines.append("　· " + str(n))
	lines.append("")
	if not AutoUpdate.can_auto():
		lines.append("当前环境（编辑器 / 无头模式）不支持自动更新，请用安装包手动升级。")
	elif str(res.get("pkg_url", "")) != "":
		var sz := str(res.get("size_pkg", ""))
		var sz_txt := ("（约 %s）" % sz) if sz != "" else ""
		lines.append("点「立即更新」会在后台下载新版本%s，不会打断游戏；下好后点「重启更新」即可生效。" % sz_txt)
	elif str(res.get("url", "")) != "":
		lines.append("这一版没有提供自动更新包，点「立即更新」会用浏览器打开安装包下载地址。")
	else:
		lines.append("版本清单里既没有更新包、也没有安装包地址 —— 去群里问一下最新包吧。")
	return "\n".join(lines)


## 开始下载（玩家点了「立即更新」，也用于失败后重试）
func _on_update_download() -> void:
	var pkg := str(_update_info.get("pkg_url", ""))
	if pkg == "":
		# 清单里没有自动更新包（update.win64）→ 退回"打开浏览器下载安装包"的老行为
		var url := str(_update_info.get("url", ""))
		if url == "":
			if _update_body != null:
				_update_body.text = "版本清单里既没有更新包、也没有安装包地址 —— 去群里问一下最新包吧。"
			return
		OS.shell_open(url)
		return
	if _auto == null:
		return
	if _update_bar != null:
		_update_bar.visible = true
		_update_bar.value = 0.0
	if _update_apply != null:
		_update_apply.visible = false
	if _update_body != null:
		_update_body.text = "正在下载新版本…（可以继续玩，下好会提示重启）"
	_auto.start_with(_update_info)


func _on_update_progress(ratio: float, text: String) -> void:
	if _update_bar != null:
		_update_bar.visible = true
		_update_bar.value = ratio
	if _update_body != null:
		_update_body.text = text


## 下好并解压完成 → 亮出「重启更新」
func _on_update_ready(version: String) -> void:
	if _update_bar != null:
		_update_bar.visible = false
	if _update_apply != null:
		_update_apply.visible = true
	if _update_body != null:
		_update_body.text = ("v%s 已下载完成。\n点「重启更新」会关闭游戏、替换文件并自动重新打开 —— 正在进行的对局会中断。"
			% version)


## 任何一步失败都只是"没更新成"，玩家照常能玩
func _on_update_failed(reason: String) -> void:
	if _update_bar != null:
		_update_bar.visible = false
	if _update_apply != null:
		_update_apply.visible = false
	if _update_body != null:
		_update_body.text = "自动更新没成功：%s\n\n可以点「立即更新」重试；反复失败就去群里要最新安装包手动升级。" % reason


## 应用更新：拉起更新脚本并退出主程序（上方文案已征得玩家同意）
func _on_update_apply() -> void:
	if _auto != null:
		_auto.apply_now()


# ---------- 登录 / 注册 ----------

func _on_cloud_login() -> void:
	_collapse_register()          # 改走登录 → 把注册那两项收起来（避免留在屏上误导）
	var nm := "" if _login_name == null else _login_name.text.strip_edges()
	var pw := "" if _login_pass == null else _login_pass.text
	if nm == "" or pw == "":
		_login_msg.text = "昵称和密码都要填"
		return
	_login_msg.text = "正在登录…"
	_cloud.login(nm, pw)


## 收起注册字段并复原按钮文案
func _collapse_register() -> void:
	if _reg_box != null:
		_reg_box.visible = false
	if _btn_register != null:
		_btn_register.text = "注册新账号"


## 把注册面板的控件同步成"当前渠道"的样子（输入框提示 / 渠道按钮选中态）
func _sync_reg_channel_ui() -> void:
	var sms := _reg_ch == CloudApi.CH_SMS
	if _login_contact != null:
		_login_contact.placeholder_text = "手机号（11 位，用来收短信）" if sms else "邮箱（用来收邮件）"
	for pair in [[_reg_btn_sms, sms], [_reg_btn_mail, not sms]]:
		var b: Button = pair[0]
		if b != null:
			b.button_pressed = bool(pair[1])
			b.text = ("● " if bool(pair[1]) else "○ ") + str(b.get_meta("ch_label"))


## 切渠道。**清空已填的联系方式与验证码** —— 半截手机号留在框里当邮箱发出去，
## 服务端只会回一句"格式不对"，玩家得自己猜哪里错了。
func _on_reg_channel(ch: String) -> void:
	if ch == _reg_ch:
		return
	_reg_ch = ch
	if _login_contact != null:
		_login_contact.text = ""
	if _login_code != null:
		_login_code.text = ""
	if _login_msg != null:
		_login_msg.text = ""
	_sync_reg_channel_ui()


## 展开注册字段时的步骤提示 —— 按渠道说，别写着"填好邮箱"却给个手机号输入框
func _reg_hint() -> String:
	if _reg_ch == CloudApi.CH_SMS:
		return "填好手机号 → 点「获取验证码」→ 把收到的 6 位码填上 → 点「确认注册」。"
	return "填好邮箱 → 点「获取验证码」→ 把收到的 6 位码填上 → 点「确认注册」。"


## 「获取验证码」：只负责发码，真正的校验在服务端
## ⚠️ `_cloud == null` 的检查放在**格式校验之后** —— "格式不对"比"组件没就绪"更可能是
##    用户自己的问题，先报前者更有指导性（也让回归能在摘掉 CloudApi 后照测格式分支）。
func _on_send_code() -> void:
	var c := "" if _login_contact == null else _login_contact.text.strip_edges()
	if _reg_ch == CloudApi.CH_SMS:
		if not _looks_like_phone(c):
			_login_msg.text = "先填一个大陆手机号（11 位）"
			return
		if _cloud == null:
			_login_msg.text = "云端组件没就绪，稍后再试"
			return
		_login_msg.text = "正在发送短信验证码…"
		_reg_pending_ch = CloudApi.CH_SMS
		_cloud.send_code_sms(_norm_phone(c))
	else:
		if not _looks_like_email(c):
			_login_msg.text = "先填一个能收到信的邮箱"
			return
		if _cloud == null:
			_login_msg.text = "云端组件没就绪，稍后再试"
			return
		_login_msg.text = "正在发送验证码…"
		_reg_pending_ch = CloudApi.CH_EMAIL
		_cloud.send_code(c)


func _on_send_code_done(ok: bool, msg: String) -> void:
	if not ok:
		_login_msg.text = msg          # 服务端给的是中文原因（冷却 / 超上限 / SMTP 失败 / 短信额度）
		return
	# 文案跟**发出时**的渠道走，不跟"当前选中项"——玩家可能在等码期间切了渠道
	if _reg_pending_ch == CloudApi.CH_SMS:
		_login_msg.text = "验证码已发到你的手机（5 分钟内有效）。"
	else:
		_login_msg.text = "验证码已发到你的邮箱（5 分钟内有效）。"
	_start_code_cooldown()


## 60 秒重发冷却。服务端也会拦（60 秒内重发返回 429），这里只是别让用户白点。
func _start_code_cooldown() -> void:
	if _code_btn == null:
		return
	_code_btn.disabled = true
	for i in range(60, 0, -1):
		if not is_instance_valid(_code_btn):
			return
		_code_btn.text = "重发（%d）" % i
		await get_tree().create_timer(1.0).timeout
	if is_instance_valid(_code_btn):
		_code_btn.text = "获取验证码"
		_code_btn.disabled = false


## 只做"像不像邮箱"的粗判，真正的校验在服务端（同一条 EMAIL_RE 思路）
func _looks_like_email(s: String) -> bool:
	var at := s.find("@")
	return at > 0 and s.find(".", at) > at + 1


func _on_cloud_register() -> void:
	# 第一次点：先展开联系方式/验证码（注册才需要），按钮改名再点一次才真提交
	if _reg_box != null and not _reg_box.visible:
		_reg_box.visible = true
		if _btn_register != null:
			_btn_register.text = "确认注册"
		_login_msg.text = _reg_hint()
		return
	var nm := "" if _login_name == null else _login_name.text.strip_edges()
	var pw := "" if _login_pass == null else _login_pass.text
	if nm == "":
		_login_msg.text = "先填个昵称"
		return
	if pw.length() < 6:
		_login_msg.text = "密码至少 6 位"
		return
	var c := "" if _login_contact == null else _login_contact.text.strip_edges()
	var cd := "" if _login_code == null else _login_code.text.strip_edges()
	if cd.length() != 6 or not cd.is_valid_int():
		_login_msg.text = "请填 6 位数字验证码"
		return
	# `_cloud == null` 的检查放在**格式校验之后**（理由同 `_on_send_code`）
	if _reg_ch == CloudApi.CH_SMS:
		if not _looks_like_phone(c):
			_login_msg.text = "请填一个大陆手机号（11 位）"
			return
		if _cloud == null:
			_login_msg.text = "云端组件没就绪，稍后再试"
			return
		_login_msg.text = "正在注册…"
		_cloud.register_sms(nm, pw, _norm_phone(c), cd)
	else:
		if not _looks_like_email(c):
			_login_msg.text = "请填一个能收到信的邮箱"
			return
		if _cloud == null:
			_login_msg.text = "云端组件没就绪，稍后再试"
			return
		_login_msg.text = "正在注册…"
		_cloud.register(nm, pw, c, cd)


func _on_cloud_login_done(ok: bool, account: Dictionary, error: String) -> void:
	if not ok:
		_login_msg.text = error
		return
	_enter_cloud_account(account)


func _on_cloud_register_done(ok: bool, account: Dictionary, error: String) -> void:
	if not ok:
		_login_msg.text = error
		return
	_enter_cloud_account(account)


## 登录/注册成功：缓存 token → 本地落一份镜像 → 按云端进度决定去哪一页
func _enter_cloud_account(account: Dictionary) -> void:
	Global.cloud_online = true
	Global.cloud_account = account
	# 「记住我」勾了 → 下次启动自动登录；没勾 → token 照存（本次会话可用），但下次要重新输密码
	var remember := true if _login_remember == null else _login_remember.button_pressed
	CloudSession.save(Global.cloud_service, _cloud.token, account, remember)
	_sync_ai_token()          # 额度从"未登录 3 次/天"升到"登录后 10 次/天"

	# 进度：**云端是权威** —— 直接拿它填当前进度。
	# ⚠️ 本机那份匿名离线进度（`progress.json`）**一个字节都不动**：
	#    两者互不干扰，登出后点「离线玩」还是接着上次的离线进度。
	Global.player_progress = _progress_from_cloud(account)
	if _login_msg != null:
		_login_msg.text = ""
	_refresh_account_label()
	# 云端已有档位 → 直接进游戏；新号（没档位）→ 先问一次水平
	if str(Global.player_progress.get("tier", "")) == "":
		_show_panel("tut_level")
	else:
		_show_panel("start")


## 离线玩：不登录、不联网。用的是**本机那份匿名进度**（`ProgressStore`）——
## 它没有名字、没有 id、不出现在任何列表里。本机第一次玩就是**0 进度原始账号**，
## 之后接着上次的进度走（客户 2026-10-05 定的）。
func _on_offline_mode() -> void:
	Global.cloud_online = false
	Global.cloud_account = {}
	if _cloud != null:
		_cloud.reset()
	if _login_msg != null:
		_login_msg.text = ""
	Global.player_progress = ProgressStore.load_progress()
	_refresh_account_label()
	# 这份进度还没选过水平 → 先问一次（问完就写进本机，下次启动直接接着玩）
	if str(Global.player_progress.get("tier", "")) == "":
		_show_panel("tut_level")
		return
	_show_panel("start")


## 「退出登录 / 登录云端」——同一个按钮按当前状态分派（文案见 _refresh_account_label）
func _on_sign_action() -> void:
	if Global.cloud_online:
		_sign_out_cloud()
	else:
		if _login_msg != null:
			_login_msg.text = ""
		_show_panel("tut_login")


## 退出云端登录（2026-10-04 新增）
##
## ⚠️ **本地存档一概不动** —— 退出只表示"这台机器不再联云"：本机照样能玩，
##    只是进度不再上传/下载。所以不做二次确认（重新登录即可，代价极低）。
## ⚠️ 必须同时清 `Global.cloud_online` 和 `_cloud` 的 token/account，
##    否则界面仍显示"已登录"、进度还会照推（会出现"退出后云端进度莫名更新"）。
func _sign_out_cloud() -> void:
	CloudSession.clear()
	Global.cloud_online = false
	Global.cloud_account = {}
	Global.player_progress = {}
	if _cloud != null:
		_cloud.reset()
	_sync_ai_token()          # 登出后额度回到"未登录 3 次/天"
	if _login_msg != null:
		_login_msg.text = ""
	_refresh_account_label()
	_show_panel("tut_login")


func _on_cloud_progress_done(ok: bool, error: String) -> void:
	# 进度上传是"尽力而为"：失败不打扰玩家（离线、断网、token 过期都算正常）
	if not ok and error != "未登录":
		push_warning("[cloud] 进度上传失败：%s" % error)


## 已登录时把进度推上云（**未登录时静默跳过**）
## 把当前进度推上云（登录中才真的发）。进度真源是 `Global.player_progress`。
func _sync_cloud_progress(tier_override := "") -> void:
	if _cloud == null or not Global.cloud_online or _cloud.token == "":
		return
	var p: Dictionary = Global.player_progress
	var t := tier_override if tier_override != "" else str(p.get("tier", ""))
	_cloud.upload_progress(t, bool(p.get("tutorial_done", false)), str(p.get("tutorial_hero", "")))


## 进度写入的**唯一入口**（2026-10-05 加）——按"当前真源"分流：
##   · 登录中 → 只改内存并上传云端（**不碰**本机匿名档，两份互不污染）；
##   · 离线玩 → 改内存并写本机 `progress.json`。
## 为什么要统一：`tier` / `tutorial_done` / `tutorial_hero` 有多个写入点，
## 各写各的必然漂移（原先 `tutorial.gd` 就漏过"没账号时也要记"）。
func _save_progress(patch: Dictionary) -> void:
	var p: Dictionary = Global.player_progress
	for k in patch.keys():
		p[str(k)] = patch[k]
	Global.player_progress = p
	if Global.cloud_online:
		_sync_cloud_progress()
	else:
		ProgressStore.save_progress(p)


## 开始界面的「新手教程」入口：按**进度**（不是账号）决定去哪一步
func _on_tutorial() -> void:
	var tier := str(Global.player_progress.get("tier", ""))
	if tier == "":
		_show_panel("tut_level")
		return
	if tier == ProgressStore.TIER_VETERAN:
		_tier_note.text = "你把自己标为老手，已跳过教程。想再看一遍就先选一次水平。"
		_show_panel("tut_level")
		return
	_show_panel("tut_hero")


## 选了水平：写进度（登录中 → 云端；离线玩 → 本机匿名档，见 `_save_progress`）
func _on_tier(t: String) -> void:
	_save_progress({"tier": t})
	_refresh_account_label()
	if t == ProgressStore.TIER_VETERAN:
		_tier_note.text = "好，跳过教程。以后想学再点「新手教程」。"
		_show_panel("start")
		return
	_hero_note.text = "已选：%s" % ProgressStore.tier_label(t)
	_show_panel("tut_hero")


func _on_tut_hero(hero_id: String) -> void:
	Global.tutorial_hero = hero_id
	Global.tutorial_tier = str(Global.player_progress.get("tier", ProgressStore.TIER_NEW))
	_save_progress({"tutorial_hero": hero_id})
	get_tree().change_scene_to_file(TUT_SCENE)
