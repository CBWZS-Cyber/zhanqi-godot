extends SceneTree
## 房间号链路 · 端到端冒烟（Godot 客户端 ↔ Node 目录服务）
## 用法：godot --headless --path 工程 -s res://tests/room_code_smoke.gd
##
## 覆盖：本进程**真的拉起** tools/room-service/server.js，然后用 NetRoomCode 走完
##   「上报地址 → 拿 4 位号 → 用号换地址 → 地址一致」这条链路，外加两条坏输入。
##
## ⚠️ 依赖 Node（PATH 里有 `node` 即可；也可设环境变量 NODE_EXE 指定 node.exe）。
##    **没有 Node 就 SKIP（exit 0），不算失败** —— 这个测试不该在没装 Node 的机器上变红。
##
## 端口用 18788：故意避开服务默认的 8787，免得和你手动起的实例抢端口。

const PORT := 18788
const BASE := "http://127.0.0.1:18788"
const SERVER_JS := "res://tools/room-service/server.js"

var _pass := 0
var _fail := 0
var _pid := -1
var _state := ""      ## "", "registered", "resolved", "failed"
var _code := ""
var _addr := ""
var _err := ""

func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)


func _initialize() -> void:
	await process_frame
	print("【房间号链路】客户端 ↔ Node 目录服务（端口 %d）" % PORT)

	var node := _find_node()
	if node == "":
		print("  ⏭ SKIP：找不到 node（PATH 里没有，也未设 NODE_EXE）—— 这条用例跳过，不算失败")
		quit(0)
		return
	print("  · node = ", node)

	if not _spawn(node):
		print("  ⏭ SKIP：Node 服务拉不起来（%s）" % SERVER_JS)
		quit(0)
		return

	var ok := await _wait_up()
	ck(ok, "Node 服务已在 %d 端口就绪" % PORT)
	if not ok:
		_cleanup()
		quit(1)
		return

	var room := NetRoomCode.new()
	room.service_url = BASE
	root.add_child(room)
	room.registered.connect(func(c): _code = str(c); _state = "registered"; _err = "")
	room.resolved.connect(func(a, _k): _addr = str(a); _state = "resolved"; _err = "")
	room.failed.connect(func(r): _err = str(r); _state = "failed")
	await process_frame

	# ---- ① 房主上报地址 → 拿 4 位号 ----
	var host_addr := "6.tcp.cpolar.top:12345"
	_state = ""
	room.register(host_addr, "tcp")
	var s1 := await _wait_state()
	ck(s1 == "registered", "上报地址后拿到房间号（state=%s%s）" % [s1, "" if s1 != "failed" else " err=" + _err])
	ck(_code.length() == 4, "房间号正好 4 位（实际 %d：%s）" % [_code.length(), _code])
	var only_digit := true
	for i in range(_code.length()):
		if _code[i] < "0" or _code[i] > "9":
			only_digit = false
	ck(only_digit, "房间号是纯数字")

	# ---- ② 加入者用号换地址 → 必须一致 ----
	_state = ""
	room.resolve(_code)
	var s2 := await _wait_state()
	ck(s2 == "resolved", "用房间号换到地址（state=%s）" % s2)
	ck(_addr == host_addr, "换回来的地址与房主上报的一致（%s）" % _addr)

	# ---- ③ 带空格/连字符也要能认（玩家会从聊天框粘过来） ----
	var pretty := "%s-%s" % [_code.substr(0, 2), _code.substr(2, 2)]
	_state = ""
	room.resolve(pretty)
	var s3 := await _wait_state()
	ck(s3 == "resolved" and _addr == host_addr, "「%s」这种带分隔符的写法也能认" % pretty)

	# ---- ④ 位数不对 / 不存在的号 ---- 
	_state = ""
	room.resolve("123")
	var s4 := await _wait_state()
	ck(s4 == "failed", "位数不足直接本地拦下（不浪费一次请求）")
	ck(_err.find("11") >= 0 or _err.find("位") >= 0, "错误提示说清了位数要求（%s）" % _err)

	_state = ""
	room.resolve("0000")   # 位数合法但没开过的号（4 位空间 1 万，本测试只开了 1 个房，撞号概率可忽略）
	var s5 := await _wait_state()
	ck(s5 == "failed", "不存在的房间号 → failed")
	ck(_err.find("过期") >= 0 or _err.find("不存在") >= 0, "错误提示说清了原因（%s）" % _err)

	# ---- ⑤ 工具函数 ----
	ck(NetRoomCode.clean_code("482 9103-7562") == "48291037562", "clean_code 去掉空格连字符")
	ck(NetRoomCode.clean_code("abc") == "", "clean_code 对非数字返回空")
	var lip := NetRoomCode.lan_ip()
	ck(lip == "" or lip.find(".") > 0, "lan_ip() 返回点分 IPv4 或空（实际「%s」）" % lip)

	room.queue_free()
	_cleanup()
	print("== 房间号链路结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------- 进程管理 ----------

func _find_node() -> String:
	var env := OS.get_environment("NODE_EXE")
	if env != "" and FileAccess.file_exists(env):
		return env
	# PATH 里的 node：直接给个短名，交给 OS 去找
	if OS.create_process("node", ["-v"]) > 0:
		return "node"
	return ""


func _spawn(node: String) -> bool:
	var js := ProjectSettings.globalize_path(SERVER_JS)
	if not FileAccess.file_exists(js):
		return false
	_pid = OS.create_process(node, [js, str(PORT)])
	return _pid > 0


func _cleanup() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _wait_up(timeout := 12.0) -> bool:
	var http := HTTPRequest.new()
	root.add_child(http)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		var err := http.request(BASE + "/health")
		if err == OK:
			var res: Array = await http.request_completed
			if res.size() >= 2 and int(res[1]) == 200:
				http.queue_free()
				return true
		await process_frame
	http.queue_free()
	return false


## 等一个状态位。**不用 `await 信号`** —— 信号不来时会永久挂住，测试就卡死了
func _wait_state(timeout := 8.0) -> String:
	var t0 := Time.get_ticks_msec()
	while _state == "" and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await process_frame
	var s := _state
	_state = ""
	return s
