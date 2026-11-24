class_name UpdateCheck
extends Node
## 自动更新检查（2026-10-04）
##
## 做法沿用《乱世五方》：**只拉一份约 1 KB 的 version.json**，比对版本号，
## 有新版就提示玩家去下载 —— **不下载安装包**。检查更新的流量要比下载
## 小四个数量级，否则每次开游戏都在烧流量。
##
## 🔴 铁律：**检查失败必须放行**。断网 / 服务器挂了 / 超时 / JSON 坏了，
##    一律 ok=false 并照常进游戏 —— 绝不允许"因为检查更新失败挡住玩家"。
##
## ⚠️ 本文件**不引用 `Global` 或任何 autoload**。`-s 脚本` 模式下 autoload 名解析不了，
##    依赖链上只要出现它，那个测试就整个编不过（同 NetRoomCode 的教训）。
##    服务地址一律由调用方注入。
##
## 版本号唯一来源：`project.godot` 的 `application/config/version`。

signal finished(result: Dictionary)
## result = {
##   "ok": bool,                  # 是否成功拿到清单
##   "has_update": bool,          # 是否有新版
##   "current": String,           # 本机版本
##   "latest": String,            # 远端版本（失败时为空）
##   "url": String,               # **安装包**下载地址（手动装的 .exe；失败时为空）
##   "pkg_url": String,           # **自动更新包**地址（2026-10-04 新增：zip，内含单文件 exe）
##   "android_url": String,       # **安卓 APK** 直链（2026-10-10 加；手机端「去下载新版本」用）
##   "size_android": String,      # 安卓 APK 大小（人读）
##   "notes": PackedStringArray,  # 更新说明
##   "size": String,              # 安装包大小（人读，如 "82.4 MB"）
##   "size_pkg": String,          # 自动更新包大小（人读）
##   "reason": String,            # 失败原因（ok=false 时有值）
## }
##
## ⚠️ `url` 与 `pkg_url` 是**两个不同的东西**：前者给"手动下载安装包"，
##    后者给 `AutoUpdate` 自动替换（必须是 zip —— 里面装的是单文件 exe）。
##    清单里没有 update.win64 时 pkg_url 为空，自动更新按钮就退回"打开浏览器下载"。

const TIMEOUT_SEC := 6.0
## 兜底地址：正常路径由调用方注入 Global.cloud_service + "/version.json"
const DEFAULT_URL := "https://game.learnest.cn/version.json"

var _http: HTTPRequest = null
var _timer: Timer = null
var _done := false


func _ready() -> void:
	_build_nodes()


## 惰性建节点。**必须允许"add_child 之后立刻 check()"**：
## `-s 脚本`模式下（探针/命令行）root 的 _ready 未必已经跑过，
## 那时直接调用 check() 会拿到 null 的 _timer 而报
## "Cannot call method 'start' on a null value"（实测踩过）。
## 本函数幂等，_ready 与 check 都可调。
func _build_nodes() -> void:
	if _timer != null and is_instance_valid(_timer):
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_completed)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = TIMEOUT_SEC + 2.0
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


## 本机版本号
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## 拉清单。url 可覆盖（便于本地联调）
func check(url: String = DEFAULT_URL) -> void:
	_build_nodes()
	_done = false
	_timer.start()
	var err: int = _http.request(url)
	if err != OK:
		_finish_fail("无法发起请求（错误码 %d）" % err)


func _on_timeout() -> void:
	_finish_fail("请求超时")


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _done:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_fail("网络不可达，请检查网络后重试")
		return
	if code != 200:
		# 404 = 还没发布过版本清单，这不是错误
		_finish_fail("云端返回 %d" % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_finish_fail("清单格式无法解析")
		return
	_finish_ok(data as Dictionary)


func _finish_ok(data: Dictionary) -> void:
	var cur := current_version()
	var latest := str(data.get("latest", ""))
	var notes := PackedStringArray()
	var raw_notes: Variant = data.get("notes", [])
	if typeof(raw_notes) == TYPE_ARRAY:
		for item in (raw_notes as Array):
			notes.append(str(item))
	# 手动下载用的**安装包**地址（原有语义，指向 *.exe）
	var url := ""
	var android_url := ""
	var downloads: Variant = data.get("downloads", {})
	if typeof(downloads) == TYPE_DICTIONARY:
		var d: Dictionary = downloads
		url = str(d.get("win64", d.get("win", "")))
		# 🔴 **安卓安装包**地址（2026-10-10 加）：手机端「去下载新版本」用它打开浏览器。
		#    安卓**绝不能**用 win64 的 exe/zip —— 那是 Windows 的更新链，在手机上装不了。
		android_url = str(d.get("android", ""))
	if android_url == "":
		android_url = str(data.get("android", ""))   # 兼容：清单偶尔把地址放顶层
	# 自动更新用的**增量包**地址（2026-10-04 新增：zip，内含单文件 exe）
	# 没有 update.win64 时回退 downloads.win64 —— 但**必须是 .zip 才敢用于自动替换**，
	# 否则 AutoUpdate 会拿安装包当 zip 解，必然报"压缩包打不开"。
	var pkg_url := ""
	var upd: Variant = data.get("update", {})
	if typeof(upd) == TYPE_DICTIONARY:
		pkg_url = str((upd as Dictionary).get("win64", ""))
	if pkg_url == "" and url.get_extension().to_lower() == "zip":
		pkg_url = url
	_finish({
		"ok": true,
		"has_update": latest != "" and compare_versions(latest, cur) > 0,
		"current": cur,
		"latest": latest,
		"url": url,
		"pkg_url": pkg_url,
		"android_url": android_url,
		"size_android": str(data.get("sizeAndroid", "")),
		"notes": notes,
		"size": str(data.get("sizeWin64", "")),
		"size_pkg": str(data.get("sizeUpdateWin64", "")),
		"reason": "",
	})


func _finish_fail(reason: String) -> void:
	_finish({
		"ok": false, "has_update": false, "current": current_version(),
		"latest": "", "url": "", "pkg_url": "", "android_url": "", "size_android": "",
		"notes": PackedStringArray(),
		"size": "", "size_pkg": "", "reason": reason,
	})


func _finish(res: Dictionary) -> void:
	if _done:
		return
	_done = true
	if _timer != null:
		_timer.stop()
	finished.emit(res)


## 语义化版本比较：a > b → 1；a == b → 0；a < b → -1
## 非数字段按 0 处理（"1.0.1-beta" 的 "1-beta" 段 → 0）
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i in range(n):
		var na := _seg(pa, i)
		var nb := _seg(pb, i)
		if na != nb:
			return 1 if na > nb else -1
	return 0


static func _seg(parts: PackedStringArray, i: int) -> int:
	if i >= parts.size():
		return 0
	var s := parts[i].strip_edges()
	return s.to_int() if s.is_valid_int() else 0
