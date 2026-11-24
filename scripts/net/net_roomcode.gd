class_name NetRoomCode
extends Node
## 房间号客户端（2026-09-30 新增）
##
## 作用：把「4 位数字房间号」翻译成「房主的可达地址」，让玩家**不用输 IP/端口**就能加入。
##
## 分工（这条线一层都没碰游戏同步）：
##   房主：NetSession.host_game() 开房 →（ws 模式）NetTunnel 起 cpolar 隧道 拿到公网地址
##         → 向房间服务 POST /room 上报地址 → 换回 4 位房间号 → 报给朋友
##   加入：输房间号 → GET /room?code=… → 换回地址 → NetSession.join_game() 直连
##   之后的对局数据仍然走 Godot 自己的 ENet / cpolar —— 房间服务只交换一次地址。
##
## 服务端：`tools/room-service/server.js`（零依赖 Node，自带 selftest.js）
##
## ⚠️ 一律走**异步** HTTPRequest。不要照 `llm_decider._post_json` 那样用同步 HTTPClient ——
##    那是阻塞主线程的（它自己的注释都写着"第 4 步将换为异步"），菜单里绝不能再塞一个。
##
## ⚠️ **本文件不许引用 `Global`（或任何 autoload）**。原因不是洁癖：
##    `-s 脚本` 模式下 autoload 名解析不了，**只要依赖链上出现它，那个测试就整个编不过**
##    （实测：tests/room_code_smoke.gd 因此直接 SCRIPT ERROR 起不来）。
##    服务地址一律由调用方注入（main_ui 从 Global.net_room_service 传进来）。

signal registered(code: String)          ## 拿到房间号
signal resolved(addr: String, kind: String)  ## 用号换到了地址

signal failed(reason: String)

## 兜底服务地址（正常路径是由调用方注入 `Global.net_room_service`，见 main_ui._init_roomcode）。
## 2026-10-03 起指向**自有云服务器**上的部署 —— 原先默认 127.0.0.1 等于要求房主在自己电脑上起服务。
## 2026-11-24：换成域名 + HTTPS（不走裸 IP:8787 了），与 Global.net_room_service 保持一致。
const DEFAULT_SERVICE := "https://game.learnest.cn/room-service"
const TIMEOUT_SEC := 6.0
const CODE_LEN := 4

var service_url := DEFAULT_SERVICE
var _http: HTTPRequest = null
var _req := ""            ## "register" | "resolve"
var busy := false

func _ready() -> void:
	_ensure_http()


## 归一化玩家输入：去掉空格/连字符/全角字符，只留数字（方便直接粘贴"482 9103 7562"）
static func clean_code(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if c >= "0" and c <= "9":
			out += c
	return out


## 本机局域网 IPv4（局域网房上报用；跳过 IPv6 / 回环，优先私有段）
static func lan_ip() -> String:
	var fallback := ""
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.find(":") >= 0 or s.begins_with("127."):
			continue
		if s.begins_with("192.168.") or s.begins_with("10."):
			return s
		if s.begins_with("172."):
			var p := s.split(".")
			if p.size() == 4 and int(p[1]) >= 16 and int(p[1]) <= 31:
				return s
		if fallback == "":
			fallback = s
	return fallback


## 上报房主地址，换一个房间号。kind: "tcp"（cpolar 公网）| "lan"（同一路由器）
func register(addr: String, kind := "tcp") -> void:
	if busy:
		failed.emit("上一个请求还没回来，稍等")
		return
	busy = true
	_req = "register"
	var h := _ensure_http()
	var body := JSON.stringify({"addr": addr, "kind": kind})
	var err := h.request(service_url + "/room",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		busy = false
		failed.emit("连不上房间服务（%s）" % service_url)


## 用房间号换地址
func resolve(code: String) -> void:
	var c := clean_code(code)
	if c.length() != CODE_LEN:
		failed.emit("房间号应该是 %d 位数字（现在 %d 位）" % [CODE_LEN, c.length()])
		return
	if busy:
		failed.emit("上一个请求还没回来，稍等")
		return
	busy = true
	_req = "resolve"
	var h := _ensure_http()
	var err := h.request("%s/room?code=%s" % [service_url, c], [], HTTPClient.METHOD_GET)
	if err != OK:
		busy = false
		failed.emit("连不上房间服务（%s）" % service_url)


func _ensure_http() -> HTTPRequest:
	if _http != null and is_instance_valid(_http):
		return _http
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_done)
	return _http


func _on_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var txt := body.get_string_from_utf8()
	var d = JSON.parse_string(txt)
	if code == 404:
		failed.emit("房间号不存在或已过期 —— 让对方重新建房、把新号码发你")
		return
	if typeof(d) != TYPE_DICTIONARY or code != 200:
		failed.emit("房间服务返回异常（HTTP %d）" % code)
		return
	if _req == "register":
		var rc := str(d.get("code", ""))
		if rc == "":
			failed.emit("房间服务没给号码")
			return
		registered.emit(rc)
	else:
		var addr := str(d.get("addr", ""))
		if addr == "":
			failed.emit("房间号对应的地址是空的")
			return
		resolved.emit(addr, str(d.get("kind", "tcp")))
