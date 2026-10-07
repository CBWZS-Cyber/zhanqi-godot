extends SceneTree
## 一次性探针：验证 `push_update_pkg.js` **手写的 zip**（node:zlib + 自建容器）
## 能被客户端的解压路径正确读出 —— 两边分别是 Node 和 Godot 实现，不验一遍不敢用。
##
## 用法：godot --headless --path <工程> -s res://tests/_probes/zip_roundtrip_probe.gd
## 前置：先用测试源跑过 `push_update_pkg.js <源文件> 9.9.9 --local`

const ZIP_PATH := "res://assets/heroes/zhanqi-update-v9.9.9.zip"

func _initialize() -> void:
	await process_frame
	print("【Node 手写 zip ↔ Godot 解压 · 往返验证】")

	var exists := FileAccess.file_exists(ZIP_PATH)
	print("  zip = ", ZIP_PATH, "（存在=", exists, "）")
	if not exists:
		printerr("  ✗ 找不到测试 zip —— 请先跑 push_update_pkg.js ... --local")
		quit(1)
		return

	# ① Godot 自带 ZIPReader 能不能读
	var z := ZIPReader.new()
	var e := z.open(ZIP_PATH)
	print("  ZIPReader.open → ", "OK" if e == OK else "ERR %d" % e)
	var names: PackedStringArray = PackedStringArray()
	if e == OK:
		names = z.get_files()
		print("  条目：", names)
		z.close()

	# ② 走 AutoUpdate 的真实解压路径
	var out := OS.get_temp_dir().path_join("zhanqi_zip_probe")
	DirAccess.make_dir_recursive_absolute(out)
	var au := AutoUpdate.new()
	var err: String = au._extract(ZIP_PATH, out)
	print("  AutoUpdate._extract → ", "OK" if err == "" else err)
	var got := out.path_join("new.exe")
	var size := 0
	if FileAccess.file_exists(got):
		var f := FileAccess.open(got, FileAccess.READ)
		size = f.get_length()
		f.close()
		print("  抠出 new.exe：", size, " 字节")
	au.free()

	var ok_all := e == OK and err == "" and size > 0 and names.has("zhanqi.exe")
	print("== 往返验证: ", "PASS" if ok_all else "FAIL")
	quit(0 if ok_all else 1)
