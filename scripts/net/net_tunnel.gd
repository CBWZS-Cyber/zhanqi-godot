class_name NetTunnel
extends Node
## cpolar 隧道管理（公网建房一键化）。
## 建房（ws 模式）时自动调起 cpolar 创建 TCP 隧道，解析其 stdout 提取公网房间号。
##
## 用法：
##   tunnel.start_tunnel(3457)          # 异步，结果经信号返回
##   tunnel.tunnel_ready(room)          # room = "24.tcp.cpolar.top:10545"
##   tunnel.tunnel_failed(reason)
##   tunnel.stop_tunnel()               # 离开联机时结束游戏启动的 cpolar
##
## cpolar 查找顺序：游戏同目录 cpolar/cpolar.exe → 用户目录 cpolar_app → Program Files。
## 依赖：cpolar 已配置 authtoken（~/.cpolar/cpolar.yml）。

signal tunnel_ready(room: String)
signal tunnel_failed(reason: String)

const _RX := "tcp://([a-zA-Z0-9.]+\\.cpolar\\.top):(\\d+)"

var _pipe: FileAccess = null
var _pid: int = -1          # 游戏启动的 cpolar 进程（精确结束用，不动用户手动开的）
var _buf := ""
var _found := false
var _timer: Timer = null
var _room := ""

func _exit_tree() -> void:
	# 兜底防泄漏：无论从哪里离开（切场景/退出游戏），游戏启动的隧道都必须关闭，
	# 否则残留占用免费隧道配额，下次建房开不了
	if _pid > 0:
		stop_tunnel()

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_poll_output)
	add_child(_timer)

func is_active() -> bool:
	return _found

func room() -> String:
	return _room

## 启动隧道（异步）。重复调用会先停旧隧道。
func start_tunnel(port: int) -> void:
	stop_tunnel()
	# 免费版在线隧道配额有限：残留的 cpolar（上次游戏异常退出没关的）会占坑，
	# 导致新隧道开不了 → 建房前强制清掉全部残留。游戏场景下 cpolar 只为联机服务。
	_kill_all_cpolar()
	var exe := _find_cpolar()
	if exe == "":
		tunnel_failed.emit("未找到 cpolar.exe。请将 cpolar.exe 放在游戏同目录的 cpolar 文件夹里")
		return
	var res = OS.execute_with_pipe(exe, ["tcp", str(port), "--log=stdout"], false)
	if typeof(res) != TYPE_DICTIONARY or not (res.get("stdio") is FileAccess):
		tunnel_failed.emit("cpolar 启动失败（进程创建失败）")
		return
	_pipe = res["stdio"]
	_pid = int(res.get("pid", -1))
	_found = false
	_buf = ""
	_room = ""
	_timer.start()
	# 30 秒超时
	get_tree().create_timer(30.0).timeout.connect(func():
		if not _found and _pipe != null:
			stop_tunnel()
			tunnel_failed.emit("获取房间号超时（检查网络；或杀毒软件拦截了 cpolar——将 cpolar.exe 加入信任区后重试）"))

func _poll_output() -> void:
	if _pipe == null:
		return
	if not _pipe.is_open():
		stop_tunnel()
		tunnel_failed.emit("cpolar 进程被中止——大概率是杀毒软件（如360）拦截。请将 cpolar.exe 加入杀软信任区后重新建房")
		return
	# 持续消费 stdout（含已拿到房间号之后）：cpolar debug 日志刷得快，
	# 不排空的话管道缓冲塞满 → cpolar 写日志阻塞 → 心跳停 → 隧道悄悄断
	while _pipe.is_open() and not _pipe.eof_reached():
		var chunk := _pipe.get_line()
		if chunk == "":
			break
		if _found:
			continue   # 已拿到房间号：只排空不解析
		_buf += chunk + "\n"
		if _buf.length() > 200000:
			_buf = _buf.right(100000)   # 防内存无限增长
		var m := RegEx.create_from_string(_RX).search(chunk)
		if m != null and not m.get_string(1).begins_with("127.0.0.1"):
			_found = true
			_room = m.get_string(1) + ":" + m.get_string(2)
			tunnel_ready.emit(_room)
			return

## 停止隧道：结束游戏启动的 cpolar（按映像名；用户手动开的 cpolar 也会被结束——
## 仅在"游戏内公网建房"流程中使用，局域网/加入方不调用）
func stop_tunnel() -> void:
	_timer.stop()
	_pipe = null
	_found = false
	_buf = ""
	_room = ""
	if _pid > 0:
		OS.kill(_pid)   # 精确结束游戏启动的 cpolar（不动用户手动开的）
		_pid = -1

## 按映像名清掉所有 cpolar 残留（仅在公网建房前调用——免费配额有限，必须独占）
func _kill_all_cpolar() -> void:
	if OS.has_feature("windows"):
		OS.execute("taskkill", ["/IM", "cpolar.exe", "/F"], [])

func _find_cpolar() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var candidates: Array = [
		exe_dir.path_join("cpolar/cpolar.exe"),
		exe_dir.path_join("cpolar.exe"),
		"C:/Users/Caobo/cpolar_app/cpolar/cpolar.exe",
		"C:/Program Files/cpolar/cpolar.exe",
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""
