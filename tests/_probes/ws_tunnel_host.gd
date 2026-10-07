extends SceneTree
## 一次性探针（2026-10-03 联机上云 · 阶段2 可行性验证）：
##   Godot 起一个 WebSocketMultiplayerPeer **server**，等一个 peer 连上来。
##   配合 /tmp/tunnel.js（裸 TCP 转发）一起用，验证「字节级 TCP 隧道对 Godot 的
##   WS 握手与 MultiplayerPeer 是否透明」—— 这是"反向隧道替代 cpolar"方案的前提。
##
## 用法：godot --headless --path <工程> -s res://tests/_probes/ws_tunnel_host.gd
##
## 判定：客户端经隧道连上时，应打印 ★ PEER_CONNECTED。

const PORT := 13457
const WAIT_SEC := 14.0

func _initialize() -> void:
	await process_frame
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_server(PORT)
	print("[host] create_server(%d) err=%d" % [PORT, err])
	if err != OK:
		quit(1)
		return
	# ⚠️ SceneTree 本身没有 multiplayer 属性 —— 要取 root（Window 是 Node）上那份 MultiplayerAPI
	var mp := root.multiplayer
	mp.multiplayer_peer = ws
	mp.peer_connected.connect(func(id: int) -> void:
		print("★ PEER_CONNECTED id=%d  ← 隧道透传成功" % id))
	mp.peer_disconnected.connect(func(id: int) -> void:
		print("★ PEER_DISCONNECTED id=%d" % id))
	print("[host] 就绪，监听 %d，等 %.0fs…" % [PORT, WAIT_SEC])
	await create_timer(WAIT_SEC).timeout
	print("[host] 超时退出，peers=%d" % mp.get_peers().size())
	quit(0)
