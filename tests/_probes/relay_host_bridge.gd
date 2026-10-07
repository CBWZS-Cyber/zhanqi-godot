extends SceneTree
## 【阶段2 关键验证】房主侧「反向隧道桥接器」——纯 GDScript（StreamPeerTCP）。
##
## 为什么需要它：房主在 NAT 后，云服务器连不进来，只能房主**主动连出**。
## 桥接器做三件事：
##   ① 主动连云端中继的「房主入口」（模拟 NAT 穿透）
##   ② 等到中继发来"已配对"控制字节 → 说明有玩家进来了
##   ③ 连本机 Godot server 端口，双向字节转发
##
## 对 Godot 的 MultiplayerPeer 完全透明：server 以为自己被本地客户端连上了。
##
## 用法：godot --headless --path <工程> -s res://tests/_probes/relay_host_bridge.gd

const RELAY_HOST := "127.0.0.1"
const RELAY_PORT := 19001
const LOCAL_HOST := "127.0.0.1"
const LOCAL_PORT := 13457
const TOTAL_TIMEOUT_MS := 30000

var _relay: StreamPeerTCP
var _local: StreamPeerTCP
var _phase := "connect_relay"
var _t0 := 0
var _forwarded := 0

func _initialize() -> void:
	await process_frame
	_t0 = Time.get_ticks_msec()
	_relay = StreamPeerTCP.new()
	var e := _relay.connect_to_host(RELAY_HOST, RELAY_PORT)
	print("[bridge] ① 主动连中继 %s:%d err=%d  ← 房主在 NAT 后也能连出" % [RELAY_HOST, RELAY_PORT, e])

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > TOTAL_TIMEOUT_MS:
		print("[bridge] 总超时退出（已转发 %d 字节）" % _forwarded)
		return true

	_relay.poll()

	match _phase:
		"connect_relay":
			var st := _relay.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				print("[bridge] 中继已连上，等「已配对」控制字节…")
				_phase = "wait_go"
			elif st == StreamPeerTCP.STATUS_ERROR:
				print("[bridge] ✗ 连中继失败")
				return true

		"wait_go":
			if _relay.get_available_bytes() >= 1:
				var b := _relay.get_u8()
				print("[bridge] ② 收到配对通知（控制字节=%d）→ 连本机 server %d" % [b, LOCAL_PORT])
				_local = StreamPeerTCP.new()
				var e := _local.connect_to_host(LOCAL_HOST, LOCAL_PORT)
				print("[bridge] 连本机 err=%d" % e)
				_phase = "connect_local"

		"connect_local":
			_local.poll()
			var st2 := _local.get_status()
			if st2 == StreamPeerTCP.STATUS_CONNECTED:
				print("[bridge] ③ 本机 server 已连上 → 开始双向字节转发")
				_phase = "pump"
			elif st2 == StreamPeerTCP.STATUS_ERROR:
				print("[bridge] ✗ 连本机 server 失败（房主是不是没开房？）")
				return true

		"pump":
			_pump(_relay, _local, "中继→本地")
			_pump(_local, _relay, "本地→中继")

	return false

## 把 src 里当前可读的字节全部转给 dst
func _pump(src: StreamPeerTCP, dst: StreamPeerTCP, tag: String) -> void:
	var n := src.get_available_bytes()
	if n <= 0:
		return
	var res: Array = src.get_data(n)
	if int(res[0]) != OK:
		return
	var bytes: PackedByteArray = res[1]
	dst.put_data(bytes)
	_forwarded += bytes.size()
	print("[bridge] %s 转发 %d 字节（累计 %d）" % [tag, bytes.size(), _forwarded])
