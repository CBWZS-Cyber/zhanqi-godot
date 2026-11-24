class_name NetRelayHost
extends Node
## 房主侧「反向隧道」桥接器（2026-10-03 新增，用来替代 cpolar）
##
## 为什么需要它：房主在自己家/宿舍的路由器后面，公网**连不进来** —— 只能主动连出。
## 本节点做三件事：
##   ① 主动连云端中继的「房主入口」（NAT 后也能连出）
##   ② 收下中继分配的「公网端口」，拼成公网地址交给 UI 去换房间号
##   ③ 有玩家进来时，连本机 Godot server 的端口，双向字节转发
##
## 对 Godot 的 MultiplayerPeer 完全透明：server 以为自己只是被一个本地客户端连上了
## （2026-10-03 已用 `tests/_probes/relay_host_bridge.gd` 实测跑通：WS 握手 + ★ PEER_CONNECTED）。
##
## 用法：
##   var relay := NetRelayHost.new()
##   add_child(relay)
##   relay.ready_with_addr.connect(func(addr: String) -> void: _room.register(addr, "tcp"))
##   relay.failed.connect(func(r: String) -> void: _on_room_failed(r))
##   relay.start(Global.net_port)
##
## ⚠️ 与 NetRoomCode 一样：**本文件不许引用任何 autoload**（`-s` 模式下 autoload 解析不了，
##    依赖链上出现它测试就整个编不过）。中继地址由调用方注入。

signal ready_with_addr(addr: String)   ## 已挂上公网端口，addr 形如 "39.105.223.8:20001"
signal peer_arrived                    ## 有玩家连进来了（UI 可以据此更新文案）
signal failed(reason: String)          ## 建隧道失败（中继不可达 / 端口池满 / 本机 server 没开）
signal closed                          ## 隧道断开（房主关房或中继断了）

const DEFAULT_RELAY_HOST := "game.learnest.cn"
const DEFAULT_RELAY_PORT := 19001
const CONNECT_TIMEOUT_MS := 12000
const LOCAL_CONNECT_TIMEOUT_MS := 8000
const NEWLINE := 10                    ## '\n'

var relay_host := DEFAULT_RELAY_HOST
var relay_port := DEFAULT_RELAY_PORT

var _up: StreamPeerTCP = null          ## 到中继（房主入口）
var _local: StreamPeerTCP = null       ## 到本机 Godot server
var _local_port := 0
var _phase := "idle"                   ## idle/connecting/handshake/wait_go/connect_local/bridging
var _ctrl := PackedByteArray()         ## 控制行缓冲（按字节找 \n，不碰 UTF-8）
var _addr := ""
var _deadline := 0
var _forwarded := 0


## 开始建隧道。local_port = 本机 Godot server 监听的端口。
func start(local_port: int) -> void:
	stop()
	_local_port = local_port
	_ctrl = PackedByteArray()
	_addr = ""
	_forwarded = 0
	_phase = "connecting"
	_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	_up = StreamPeerTCP.new()
	var err := _up.connect_to_host(relay_host, relay_port)
	if err != OK:
		_phase = "idle"
		failed.emit("无法连接中继 %s:%d（err=%d）" % [relay_host, relay_port, err])


func stop() -> void:
	if _up != null:
		_up.disconnect_from_host()
		_up = null
	if _local != null:
		_local.disconnect_from_host()
		_local = null
	_phase = "idle"


func public_addr() -> String:
	return _addr


func forwarded_bytes() -> int:
	return _forwarded


func _process(_delta: float) -> void:
	match _phase:
		"connecting":
			_up.poll()
			var st := _up.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				_phase = "handshake"
				_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
			elif st == StreamPeerTCP.STATUS_ERROR or Time.get_ticks_msec() > _deadline:
				_phase = "idle"
				failed.emit("连不上中继 %s:%d（网络不通？）" % [relay_host, relay_port])

		"handshake":
			_up.poll()
			_read_into_ctrl()
			var host_ip := ""
			var port := -1
			while true:
				var line := _next_line()
				if line == "":
					break
				if line.begins_with("PORT "):
					port = int(line.substr(5))
				elif line.begins_with("HOST "):
					host_ip = line.substr(5)
				elif line == "BUSY":
					_phase = "idle"
					failed.emit("服务器端口池满了，稍后再试")
					return
				elif line == "GO":
					# 理论上不会（还没报端口就被配对），保守处理
					_begin_bridge()
					return
			if port > 0:
				if host_ip == "":
					host_ip = relay_host
				_addr = "%s:%d" % [host_ip, port]
				_phase = "wait_go"
				ready_with_addr.emit(_addr)
			elif Time.get_ticks_msec() > _deadline:
				_phase = "idle"
				failed.emit("中继没给端口（协议不符？）")

		"wait_go":
			_up.poll()
			_read_into_ctrl()
			while true:
				var line := _next_line()
				if line == "":
					break
				if line == "GO":
					peer_arrived.emit()
					_begin_bridge()
					return
			if _up.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_phase = "idle"
				closed.emit()

		"connect_local":
			_local.poll()
			var st2 := _local.get_status()
			if st2 == StreamPeerTCP.STATUS_CONNECTED:
				_phase = "bridging"
				_flush_leftover()   # 控制行之后可能已经跟着玩家的字节，先交给本地
			elif st2 == StreamPeerTCP.STATUS_ERROR or Time.get_ticks_msec() > _deadline:
				_phase = "idle"
				failed.emit("连不上本机对局端口 %d（房是不是没开成？）" % _local_port)

		"bridging":
			_up.poll()
			_local.poll()
			if _up.get_status() != StreamPeerTCP.STATUS_CONNECTED \
					or _local.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_phase = "idle"
				closed.emit()
				return
			_pump(_up, _local)
			_pump(_local, _up)


## 玩家已进来：把控制缓冲里剩下的字节（可能已含玩家数据）交给本地，然后开始桥接
func _begin_bridge() -> void:
	_local = StreamPeerTCP.new()
	var err := _local.connect_to_host("127.0.0.1", _local_port)
	if err != OK:
		_phase = "idle"
		failed.emit("无法连接本机端口 %d（err=%d）" % [_local_port, err])
		return
	_phase = "connect_local"
	_deadline = Time.get_ticks_msec() + LOCAL_CONNECT_TIMEOUT_MS


func _read_into_ctrl() -> void:
	var n := _up.get_available_bytes()
	if n <= 0:
		return
	var res: Array = _up.get_data(n)
	if int(res[0]) != OK:
		return
	_ctrl.append_array(res[1])


## 从控制缓冲里取一行（不含 \n）；取不到返回空串。二进制安全。
func _next_line() -> String:
	var idx := _ctrl.find(NEWLINE)
	if idx < 0:
		return ""
	var line := _ctrl.slice(0, idx).get_string_from_utf8().strip_edges()
	_ctrl = _ctrl.slice(idx + 1)
	return line


## 桥接期开始时，控制缓冲里可能已经攒了玩家的字节 —— 先冲刷给本地
func _flush_leftover() -> void:
	if _ctrl.size() > 0:
		_local.put_data(_ctrl)
		_forwarded += _ctrl.size()
		_ctrl = PackedByteArray()


func _pump(src: StreamPeerTCP, dst: StreamPeerTCP) -> void:
	var n := src.get_available_bytes()
	if n <= 0:
		return
	var res: Array = src.get_data(n)
	if int(res[0]) != OK:
		return
	var bytes: PackedByteArray = res[1]
	dst.put_data(bytes)
	_forwarded += bytes.size()
