extends SceneTree
## HTTPS 连通性探针（2026-11-24 建，配合 game.learnest.cn 切域名）
##
## 为什么需要单独一个探针：**curl 通 ≠ Godot 通**。
## Godot 4 的 TLS 栈（mbedtls / 系统 CA）与 curl 不同，证书链、SNI、系统时间
## 任何一项不对都会在引擎里失败，而 curl 照样返回 200。
##
## 用法：
##   godot --headless --path <工程> -s res://tests/_probes/https_probe.gd
## 结果同时打到 stdout 和 res:// 外的一个文件（stdout 在 quit() 后可能丢）。

const URLS := [
	"https://game.learnest.cn/health",
	"https://game.learnest.cn/room-service/health",
	"https://game.learnest.cn/version.json",
	"https://game.learnest.cn/llm/ping",
]
const OUT := "user://https_probe.txt"

var _http: HTTPRequest
var _idx := 0
var _lines: PackedStringArray = []
var _started := false

## ⚠️ 不能在 `_init()` 里发请求：那时 SceneTree 的 root 还没进树，
##    HTTPRequest.request() 会返回 ERR_UNCONFIGURED（踩过一次）。
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	root.add_child(_http)
	_http.request_completed.connect(_on_done)
	_next()
	return false

func _next() -> void:
	if _idx >= URLS.size():
		var text := "\n".join(_lines)
		print(text)
		var f := FileAccess.open(OUT, FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
		var all_ok := true
		for ln in _lines:
			if not ln.contains("OK"):
				all_ok = false
		quit(0 if all_ok else 2)
		return
	var url: String = URLS[_idx]
	var err := _http.request(url)
	if err != OK:
		_lines.append("FAIL %s request_err=%d" % [url, err])
		_idx += 1
		_next()

func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var url: String = URLS[_idx]
	var head := body.get_string_from_utf8().left(60).replace("\n", " ")
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_lines.append("OK   %s  code=%d  %s" % [url, code, head])
	else:
		_lines.append("FAIL %s  result=%d code=%d  %s" % [url, result, code, head])
	_idx += 1
	_next()
