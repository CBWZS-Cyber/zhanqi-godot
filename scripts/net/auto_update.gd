class_name AutoUpdate
extends Node
## 战棋 · 自动更新器（2026-10-04，做法沿用《乱世五方》）
##
## 流程：UpdateCheck 探到新版 → 后台下载 zip（带进度）→ 从 zip 里抠出 exe →
##   写一个更新脚本 → 报告就绪。玩家点「重启更新」后，脚本在**主程序退出之后**
##   替换 exe 并重新启动 —— Windows 下运行中的 exe **不能覆盖自己**，
##   必须借外部脚本绕开。
##
## 🔴 铁律一：更新**永不阻塞游戏**。任何一步失败都只是"没更新成"，玩家照常能玩。
## 🔴 铁律二：桌面版是**单文件 exe**（export_presets.cfg 里 binary_format/embed_pck=true），
##    所以"更新"＝换掉那一个文件（zip 里也只有它）。
## 🔴 铁律三：更新脚本必须**纯 ASCII**。Godot 写出的文件是不带 BOM 的 UTF-8，
##    cmd 读到中文会乱码 —— 所以脚本里一律用通配符 `*.exe`，**不写死「战棋.exe」**，
##    也不写中文提示语。战棋的安装目录名是中文，这条尤其要守。
## 🔴 铁律四：更新包走 **OSS 直链**（清单里的签名 URL），不经过那台 3 Mbps 的小服务器。
## 🔴 铁律五：**编辑器 / 无头环境下绝不下载、绝不写盘**。开发时 `OS.get_executable_path()`
##    指向的是 Godot 编辑器本体，写 `_update/` 等于往 Godot 安装目录里塞垃圾。
##
## ⚠️ 本文件**不引用 `Global` 或任何 autoload**（同 NetRoomCode / UpdateCheck 的教训：
##    `-s 脚本` 模式下 autoload 名解析不了，依赖链上出现它测试就整个编不过）。

signal progress(ratio: float, text: String)      ## 下载进度（0~1）+ 人读文案
signal update_ready(version: String)             ## 已下好、解压完、脚本就绪
signal failed(reason: String)                    ## 没更新成（永不阻塞游戏）

## 小于它的一律当成"下错了"（错误页 / 半截包）
const MIN_ZIP_BYTES: int = 1048576
const ZIP_NAME := "zhanqi.zip"
const NEW_EXE := "new.exe"
const UPDATER_BAT := "apply_update.bat"
const MARKER_TXT := "version.txt"

var _http: HTTPRequest
var _latest := ""
var _url := ""
var _dir := ""
var _polling := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	set_process(false)


## 本环境能否**自动**下载并替换：只有独立运行的桌面版可以。
## 编辑器里跑会指向 Godot 安装目录；无头是回归测试，都不该动盘。
## 🔴 **安卓也不行**（2026-10-10 修，玩家实测）：整条链是 Windows 专属 ——
##    更新脚本是 `.bat`、拉起靠 `cmd.exe`、替换的是 exe，安卓上一个都不成立；
##    而且 `update_dir()` 取的是 `OS.get_executable_path()` 下的 `_update/`，
##    在安卓上那是 **APK 包内部（只读）**，连下载文件都写不进去 —— 玩家一开下载就
##    "下载中断 result=10"（那是 `RESULT_DOWNLOAD_FILE_CANT_OPEN`：打不开下载目标文件）。
##    安卓走「打开浏览器下载新 APK」的路径（见 main_ui 的更新面板）。
static func can_auto() -> bool:
	if OS.has_feature("editor"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("android"):
		return false
	return true


## 下载错误码 → 给玩家看的中文。
## 🔴 **绝不把 `result=N` 这种内部码怼给玩家**（2026-10-10 用户点名）：
##    玩家看到"下载中断（result=10）"完全无法行动 —— 他需要的是"下一步做什么"。
static func human_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "连不上更新服务器，请检查网络后重试"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "找不到更新服务器，请检查网络后重试"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "网络连接中断了，请稍后重试"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "安全连接建立失败，请稍后重试"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "更新服务器没有响应，请稍后重试"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "下载的数据异常，请重试"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "存储写入失败（设备空间可能不足），清理一下空间再试"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "下载写入中断，请检查设备存储空间后重试"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "下载地址跳转次数过多，请稍后重试"
		HTTPRequest.RESULT_TIMEOUT:
			return "下载超时了，请检查网络后重试"
		_:
			return "下载没有成功（可能是网络波动），请稍后重试"


## 游戏目录下的 `_update/`（新 exe 与更新脚本都放这）
func update_dir() -> String:
	if _dir == "":
		_dir = OS.get_executable_path().get_base_dir().path_join("_update")
	return _dir


## 上次已下载就绪却没重启 → 直接报就绪，**免得重复下上百 MB**
func prepared_version() -> String:
	var tag: String = update_dir().path_join(MARKER_TXT)
	if not FileAccess.file_exists(tag):
		return ""
	var f := FileAccess.open(tag, FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


## 入口：清单结论已由 `UpdateCheck` 探好，这里**只管下载**（不再自己查一遍网络）
## ⚠️ 优先取 `pkg_url`（update.win64，zip）；调用方必须先确认它非空 ——
##    回退到 `url` 会把**安装包**（.exe）当 zip 解，必然失败。
func start_with(state: Dictionary) -> void:
	if not can_auto():
		failed.emit("当前环境不支持自动更新（编辑器 / 无头模式）")
		return
	_latest = str(state.get("latest", ""))
	_url = str(state.get("pkg_url", ""))
	if _url == "":
		failed.emit("更新清单里没有自动更新包地址（update.win64）")
		return
	_download()


func _download() -> void:
	var dir: String = update_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	# 清掉上次残留，避免半截文件被当成完整的
	_http.cancel_request()
	var zip_path: String = dir.path_join(ZIP_NAME)
	DirAccess.remove_absolute(zip_path)
	_http.download_file = zip_path
	if _http.request(_url) != OK:
		failed.emit("无法开始下载")
		return
	_polling = true
	set_process(true)
	progress.emit(0.0, "正在下载 v%s…" % _latest)


## 进度轮询（HTTPRequest 不主动报进度，得每帧问一次）
func _process(_dt: float) -> void:
	if not _polling:
		return
	var got: int = _http.get_downloaded_bytes()
	var total: int = _http.get_body_size()
	if total > 0:
		progress.emit(clampf(float(got) / float(total), 0.0, 1.0),
			"正在下载 v%s（%.1f / %.1f MB）" % [_latest, got / 1048576.0, total / 1048576.0])
	else:
		progress.emit(0.0, "正在下载 v%s（已 %.1f MB）" % [_latest, got / 1048576.0])


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	_polling = false
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit(human_error(result))   # 🔴 只给人话，不暴露内部错误码（2026-10-10 用户点名）
		return
	if code != 200:
		failed.emit("下载失败：服务器暂时不可用（%d），请稍后重试" % code)
		return
	var zip_path: String = update_dir().path_join(ZIP_NAME)
	var f := FileAccess.open(zip_path, FileAccess.READ)
	var sz: int = f.get_length() if f != null else 0
	if f != null:
		f.close()
	if sz < MIN_ZIP_BYTES:
		failed.emit("下载的文件不完整（%d 字节）" % sz)
		return
	progress.emit(1.0, "正在解压…")
	var err: String = _extract(zip_path, update_dir().path_join("new"))
	if err != "":
		failed.emit(err)
		return
	_write_marker()
	_write_updater()
	update_ready.emit(_latest)


## 从 zip 里抠出 exe 写到 new/（Godot 自带 ZIPReader，不必调外部程序）
func _extract(zip_path: String, out_dir: String) -> String:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return "压缩包打不开（下载可能不完整）"
	var entry: String = ""
	for f in z.get_files():
		if f.get_extension().to_lower() == "exe":
			entry = f
			break
	if entry == "":
		z.close()
		return "压缩包里没有 exe"
	var data: PackedByteArray = z.read_file(entry)
	z.close()
	if data.size() < MIN_ZIP_BYTES:
		return "解压出的 exe 异常（%d 字节）" % data.size()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out: String = out_dir.path_join(NEW_EXE)
	var fp := FileAccess.open(out, FileAccess.WRITE)
	if fp == null:
		return "无法写入新版本文件（磁盘满或没权限？）"
	fp.store_buffer(data)
	fp.close()
	return ""


## 版本标记：下次启动据此判断"上次下好了没重启"，不必重复下载
func _write_marker() -> void:
	var fp := FileAccess.open(update_dir().path_join(MARKER_TXT), FileAccess.WRITE)
	if fp != null:
		fp.store_string(_latest)
		fp.close()


## 更新脚本：等主程序退出 → 覆盖 exe → 重新启动 → 清理 → 自删。
##   全程用通配符、**不含一个中文字**（见铁律三）；重试 60 次仍失败则停下并提示手动处理，
##   免得权限问题导致脚本无限空转。
func _write_updater() -> void:
	var fp := FileAccess.open(update_dir().path_join(UPDATER_BAT), FileAccess.WRITE)
	if fp != null:
		fp.store_string(updater_script())
		fp.close()


## 更新脚本内容。**抽成静态函数是为了能被回归测试直接验证**（见 tests/update_smoke.gd）：
## 铁律三要求它纯 ASCII 且用 `*.exe` 通配符 —— 这两条只能靠断言守住，
## 而真正的下载/替换在 headless 下没法跑（会写进 Godot 安装目录）。
static func updater_script() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"@echo off",
		"setlocal enabledelayedexpansion",
		"title Updating...",
		"cd /d \"%~dp0..\"",
		"rem wait for the game to release the exe file",
		"timeout /t 3 /nobreak >nul",
		"set /a n=0",
		":retry",
		"for %%f in (*.exe) do copy /Y \"%~dp0new\\new.exe\" \"%%~ff\" >nul 2>&1",
		"if not errorlevel 1 goto done",
		"set /a n+=1",
		"if !n! gtr 60 goto giveup",
		"timeout /t 1 /nobreak >nul",
		"goto retry",
		":giveup",
		"echo Update failed. Please copy _update\\new\\new.exe over the game exe manually.",
		"pause",
		"exit /b 1",
		":done",
		"for %%f in (*.exe) do start \"\" \"%%f\"",
		"timeout /t 2 /nobreak >nul",
		"rd /s /q \"%~dp0new\" >nul 2>&1",
		"del /f /q \"%~dp0version.txt\" >nul 2>&1",
		"(goto) 2>nul & del /f /q \"%~f0\"",
	])
	return "\r\n".join(lines) + "\r\n"


## 现在就应用：拉起更新脚本（独立进程）→ 主动退出主程序。
##   ⚠️ 调用方负责先征得玩家同意 —— 退出会中断正在进行的对局。
func apply_now() -> void:
	if not can_auto():
		return
	var bat: String = update_dir().path_join(UPDATER_BAT)
	if not FileAccess.file_exists(bat):
		return
	OS.create_process("cmd.exe", ["/c", bat])
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()
