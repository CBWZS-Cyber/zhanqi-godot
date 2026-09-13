class_name NetSession
extends Node
## 联机会话层（阶段3）：ENet Host/Join + 可靠指令通道。
##
## 用法（UI 层持有本节点）：
##   host_game(port) -> Error          # 建房（本机为 host，红方）
##   join_game(ip, port) -> Error      # 加入（对方为 host，蓝方）
##   leave_game()                      # 断开/散局
##   send_cmd(cmd: Dictionary)         # 发一条操作指令（仅客户端/主机均可用）
##   send_opening(pkg: Dictionary)     # host 发开局包（种子/英雄/模式）
## 信号：
##   peer_joined        # 对方已连上（host 收到 / client 连上后）
##   peer_left          # 对方断线（对局中收到 → 上层判负）
##   cmd_received(cmd)  # 收到操作指令 → 镜像重放
##   opening_received(pkg)  # client 收到开局包 → 建镜像 battle
##   connected_to_host_ok / join_failed(err)
##
## 断线策略（MVP）：对局中对方断线 = 我方胜（UI 层处理 peer_left）。

signal peer_joined
signal peer_left
signal cmd_received(cmd: Dictionary)
signal opening_received(pkg: Dictionary)
signal connected_to_host_ok
signal join_failed(err: int)

const CHANNEL := 0          # ENet 可靠有序通道
const _proto := preload("res://scripts/net/net_protocol.gd")   # 用 preload，避免依赖全局类缓存

var is_host := false
var active := false
var transport := "enet"   # "enet"=局域网 UDP | "ws"=公网穿透 WebSocket(TCP，配 cpolar 等隧道)

## 双模式建房：transport=enet 用 ENetMultiplayerPeer(UDP)；ws 用 WebSocketMultiplayerPeer(TCP)
func host_game(port: int) -> Error:
	var peer: MultiplayerPeer
	if transport == "ws":
		var ws := WebSocketMultiplayerPeer.new()
		var err := ws.create_server(port)
		if err != OK:
			return err
		peer = ws
	else:
		var en := ENetMultiplayerPeer.new()
		var err2 := en.create_server(port, 1)   # 1 个客户端
		if err2 != OK:
			return err2
		peer = en
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	_hook_signals()
	return OK

## 双模式加入：ws 模式下 addr 支持 "ip:port" / "ws://host:port"（cpolar 隧道地址形如 6.tcp.cpolar.top:12345）
func join_game(ip: String, port: int) -> Error:
	var peer: MultiplayerPeer
	if transport == "ws":
		var ws := WebSocketMultiplayerPeer.new()
		var url: String
		if "://" in ip:
			url = ip
		elif ":" in ip:
			url = "ws://" + ip          # 已带端口（cpolar 地址）
		else:
			url = "ws://%s:%d" % [ip, port]
		var err := ws.create_client(url)
		if err != OK:
			return err
		peer = ws
	else:
		var en := ENetMultiplayerPeer.new()
		var err2 := en.create_client(ip, port)
		if err2 != OK:
			return err2
		peer = en
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	_hook_signals()
	return OK

func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false

## 对端是否已连上（host=有客户端 / join=已连到服务器）
func multiplayer_peer_active() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().size() > 0

func _hook_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
	if not multiplayer.connection_failed.is_connected(_on_connected_fail):
		multiplayer.connection_failed.connect(_on_connected_fail)

func _on_peer_connected(_id: int) -> void:
	peer_joined.emit()

func _on_peer_disconnected(_id: int) -> void:
	peer_left.emit()

func _on_connected_ok() -> void:
	connected_to_host_ok.emit()

func _on_connected_fail() -> void:
	join_failed.emit(ERR_CONNECTION_ERROR)
	leave_game()

## ---------- 发送 ----------
func send_cmd(cmd: Dictionary) -> void:
	_rpc_cmd.rpc(_proto.encode(cmd))

func send_opening(pkg: Dictionary) -> void:
	_rpc_opening.rpc(JSON.stringify(pkg))

## ---------- 接收（ENet RPC）----------
@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _rpc_cmd(wire: String) -> void:
	var cmd: Dictionary = _proto.decode(wire)
	if cmd.is_empty():
		push_warning("NetSession: 收到非法指令 " + wire)
		return
	cmd_received.emit(cmd)

@rpc("any_peer", "call_remote", "reliable", CHANNEL)
func _rpc_opening(wire: String) -> void:
	var p = JSON.parse_string(wire)
	if typeof(p) != TYPE_DICTIONARY:
		push_warning("NetSession: 开局包解析失败")
		return
	opening_received.emit(p)
