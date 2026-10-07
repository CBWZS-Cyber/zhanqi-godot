extends SceneTree
## 端到端探针（2026-10-03）：本机模拟完整建房链路，用的都是**生产代码**。
##   「房主的 Godot server + NetRelayHost 桥接器」 → 中继分配公网端口 → 玩家从该端口连入。
## 用法：godot --headless --path <工程> -s res://tests/_probes/relay_e2e_host.gd
##
## 需要先起 tools/relay-service/relay-service.js（CONTROL_PORT=19001, POOL=20000-20010）。
## 判定：打印 ★ RELAY ADDR 与 ★ PEER_CONNECTED 即为通过。

const LOCAL_PORT := 13457
const WAIT_SEC := 20.0

func _initialize() -> void:
	await process_frame

	# ① 房主的 Godot server（就是平时建房时 NetSession 做的那件事）
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_server(LOCAL_PORT)
	print("[e2e] 房主 server 监听 %d err=%d" % [LOCAL_PORT, err])
	var mp := root.multiplayer
	mp.multiplayer_peer = ws
	mp.peer_connected.connect(func(id: int) -> void:
		print("★ PEER_CONNECTED id=%d  ← 玩家经中继连入成功" % id))
	mp.peer_disconnected.connect(func(id: int) -> void:
		print("· 玩家断开 id=%d" % id))

	# ② 生产桥接器 NetRelayHost
	# 中继地址可用 `++ <host>` 覆盖：默认 127.0.0.1（本机自测，需先起本机 relay-service）；
	# 传 39.105.223.8 即走云端部署。
	var relay_host := "127.0.0.1"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		relay_host = str(uargs[0])
	var relay := NetRelayHost.new()
	relay.relay_host = relay_host
	relay.relay_port = 19001
	print("[e2e] 目标中继 = %s:19001" % relay_host)
	root.add_child(relay)
	relay.ready_with_addr.connect(func(a: String) -> void:
		print("★ RELAY ADDR = %s  ← 这就是要拿去换房间号的公网地址" % a)
		# 走真实流程：拿这个地址去房间服务换一个 4 位房间号
		var room := NetRoomCode.new()
		room.service_url = "http://39.105.223.8:8787"
		root.add_child(room)
		room.registered.connect(func(c: String) -> void:
			print("★ ROOM CODE = %s   ← 玩家只需输这串数字即可加入" % c))
		room.failed.connect(func(r: String) -> void:
			print("✗ 换房间号失败: %s" % r))
		room.register(a, "tcp"))
	relay.failed.connect(func(r: String) -> void:
		print("✗ relay failed: %s" % r))
	relay.closed.connect(func() -> void:
		print("· relay closed"))
	relay.peer_arrived.connect(func() -> void:
		print("· 中继通知：有人进来了"))
	relay.start(LOCAL_PORT)

	await create_timer(WAIT_SEC).timeout
	print("[e2e] 结束：peers=%d 已转发 %d 字节" % [mp.get_peers().size(), relay.forwarded_bytes()])
	quit(0)
