extends SceneTree
## 自动更新器 · 回归（2026-10-04）
## 用法：godot --headless --path 工程 -s res://tests/update_smoke.gd
##
## 为什么只测这些：`AutoUpdate` 的下载 / 解压 / 写盘全部依赖 `OS.get_executable_path()`，
##   而 headless 下那个路径是 **Godot 编辑器自己的目录** —— 真跑一遍就等于往 Godot
##   安装目录里写 `_update/`，属于必须避免的操作。所以本测试只覆盖两件能静态判定的事：
##     ① 「不该动盘时确实拒绝了」（can_auto 守卫）
##     ② 「更新脚本内容合规」（纯 ASCII / 通配符 / 关键动作齐全）
##   真正的下载与替换只能由**实机**（装好的 exe）验证。

var _pass := 0
var _fail := 0


func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		printerr("  ✗ FAIL: ", name)


func _initialize() -> void:
	await process_frame
	print("【自动更新器】")

	# ① 无头 / 编辑器环境必须拒绝自动更新 —— 否则会把 _update/ 写进 Godot 安装目录
	ck(not AutoUpdate.can_auto(), "无头环境下 can_auto() = false（拒绝自动更新）")

	var bat := AutoUpdate.updater_script()

	# ② 铁律三：更新脚本纯 ASCII（Godot 写的是无 BOM 的 UTF-8，cmd 读中文会乱码）
	var bad := ""
	for i in range(bat.length()):
		if bat.unicode_at(i) > 127:
			bad += bat[i]
	ck(bad == "", "更新脚本纯 ASCII（越界字符：%s）" % ("无" if bad == "" else bad))

	# ③ 用通配符定位目标，不写死「战棋.exe」（战棋目录名是中文，写死就可能乱码）
	ck(bat.find("*.exe") >= 0, "用 *.exe 通配符定位目标 exe")
	ck(bat.find("战棋") < 0, "脚本里不含中文名（含则 cmd 下会乱码）")

	# ④ 关键动作齐全：等主程序退出 → 覆盖 → 重启 → 清理解压目录 → 自删
	ck(bat.find("timeout /t 3") >= 0, "先等主程序释放 exe（3 秒）")
	ck(bat.find("copy /Y") >= 0, "覆盖 exe")
	ck(bat.find(":retry") >= 0 and bat.find(":giveup") >= 0, "有重试与放弃分支（不会无限空转）")
	ck(bat.find("if !n! gtr 60") >= 0, "重试上限 60 次")
	ck(bat.find("start \"\"") >= 0, "更新完重新启动游戏")
	ck(bat.find("rd /s /q") >= 0, "清理解压出的临时目录")
	ck(bat.find("del /f /q \"%~f0\"") >= 0, "脚本自删")
	ck(bat.find("%~dp0") >= 0, "用 %~dp0 相对路径（不依赖中文绝对路径）")

	# ⑤ 顺带回归版本号比较 —— 它错了会把旧版当新版，或漏掉真更新
	ck(UpdateCheck.compare_versions("10.4.1", "10.4.0") > 0, "10.4.1 > 10.4.0")
	ck(UpdateCheck.compare_versions("10.4.0", "10.4.0") == 0, "10.4.0 == 10.4.0")
	ck(UpdateCheck.compare_versions("9.20", "10.4.0") < 0, "9.20 < 10.4.0（按数字段比，非字符串）")
	ck(UpdateCheck.compare_versions("1.2.2", "1.2.10") < 0, "1.2.2 < 1.2.10（位数对齐，非字典序）")

	# ⑤b 错误码 → 人话（2026-10-10 加，用户点名）：**绝不把 result=N 怼给玩家**。
	#    起因：手机端显示"下载中断（result=10）"——那是 RESULT_DOWNLOAD_FILE_CANT_OPEN
	#    （安卓上 _update/ 在 APK 包内部，写不进去），玩家完全没法行动。
	ck(AutoUpdate.human_error(HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN).find("存储") >= 0,
		"result=10（写不进文件）翻成「存储写入失败」")
	ck(AutoUpdate.human_error(HTTPRequest.RESULT_TIMEOUT).find("超时") >= 0, "超时码翻成「下载超时」")
	ck(AutoUpdate.human_error(HTTPRequest.RESULT_CANT_CONNECT).find("连不上") >= 0, "连不上翻成人话")
	ck(AutoUpdate.human_error(HTTPRequest.RESULT_CONNECTION_ERROR).find("网络") >= 0, "连接中断翻成人话")
	ck(AutoUpdate.human_error(999).find("网络波动") >= 0, "未知码也有兜底人话（不输出内部码）")
	ck(AutoUpdate.human_error(HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN).find("result=") < 0
		and AutoUpdate.human_error(999).find("result=") < 0, "人话里**不含**内部错误码字样")

	# ⑤c 清单解析：安卓段（2026-10-10 加）—— 手机端「去下载新版本」靠它拿 APK 直链
	var uc := UpdateCheck.new()
	root.add_child(uc)
	var got_res: Array = []
	uc.finished.connect(func(r: Dictionary) -> void: got_res.append(r))
	uc._finish_ok({
		"latest": "10.5.4", "sizeWin64": "159.4 MB", "sizeAndroid": "300 MB",
		"downloads": {"win64": "https://x/zhanqi-install.exe", "android": "https://x/zhanqi.apk"},
		"update": {"win64": "https://x/zhanqi-update.zip"},
		"notes": ["n1"],
	})
	await process_frame
	var res: Dictionary = got_res[0] if got_res.size() > 0 else {}
	ck(str(res.get("android_url", "")) == "https://x/zhanqi.apk", "清单解析：android_url 取自 downloads.android")
	ck(str(res.get("size_android", "")) == "300 MB", "清单解析：size_android")
	ck(str(res.get("pkg_url", "")) == "https://x/zhanqi-update.zip", "清单解析：pkg_url 照旧（Windows zip）")
	ck(str(res.get("url", "")) == "https://x/zhanqi-install.exe", "清单解析：url 照旧（Windows 安装包）")
	# 顶层 android 兜底（清单偶尔把地址放顶层）
	var got_res2: Array = []
	uc.finished.connect(func(r: Dictionary) -> void: got_res2.append(r))
	uc._done = false
	uc._finish_ok({"latest": "10.5.5", "android": "https://x/top.apk"})
	await process_frame
	ck(got_res2.size() > 0 and str(got_res2[0].get("android_url", "")) == "https://x/top.apk",
		"清单解析：顶层 android 字段可兜底")
	uc.queue_free()
	await process_frame

	# ⑥ 真实解压：用 Godot 自带 ZIPPacker 现造一个 zip 再解，验证「下载下来的包能不能
	#    正确抠出 exe」这一段。写的是系统临时目录，**不碰 Godot 安装目录**。
	var tmp := OS.get_temp_dir().path_join("zhanqi_upd_test")
	DirAccess.make_dir_recursive_absolute(tmp)
	var zip_path := tmp.path_join("t.zip")
	DirAccess.remove_absolute(zip_path)
	var payload := PackedByteArray()
	payload.resize(AutoUpdate.MIN_ZIP_BYTES + 1024)   # 得先过"文件太小＝下错了"那道闸
	payload.fill(0x5A)
	var zp := ZIPPacker.new()
	zp.open(zip_path)
	zp.start_file("战棋.exe")          # 故意用中文名 —— 真实更新包里的文件名就是中文
	zp.write_file(payload)
	zp.close_file()
	zp.close()
	var au := AutoUpdate.new()
	var err := au._extract(zip_path, tmp.path_join("new"))
	ck(err == "", "能从 zip 里抠出 exe（err=%s）" % ("无" if err == "" else err))
	var got := tmp.path_join("new").path_join("new.exe")
	if FileAccess.file_exists(got):
		var f := FileAccess.open(got, FileAccess.READ)
		ck(f.get_length() == payload.size(), "抠出的 exe 字节数与源一致（%d）" % payload.size())
		f.close()
	else:
		ck(false, "抠出的文件叫 new.exe")

	# 坏包必须被挡住（半截下载 / 错误页 / 拿安装包当 zip）
	var bad_zip := tmp.path_join("bad.zip")
	var fbad := FileAccess.open(bad_zip, FileAccess.WRITE)
	fbad.store_string("this is not a zip file, just text")
	fbad.close()
	ck(au._extract(bad_zip, tmp.path_join("new2")) != "", "非 zip 内容会被拒绝（不会静默当成成功）")

	# 清理（测试不留垃圾）
	DirAccess.remove_absolute(zip_path)
	DirAccess.remove_absolute(bad_zip)
	au.free()

	print("== 自动更新器结果: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
