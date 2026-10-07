extends SceneTree
## 云端客户端探针（2026-10-04）
##
## 验证 scripts/net/update_check.gd 与 scripts/net/cloud_api.gd 打**真实云服务**（公网）。
## 不进正式回归 —— 它要联网、还会真的建账号（跑完用 ssh 清理）。
##
## 跑：godot --headless --path . -s res://tests/_probes/cloud_client_probe.gd

const SERVICE := "http://39.105.223.8:8789"

var _ok := 0
var _bad := 0
var _created_name := ""


func _initialize() -> void:
	_run()


func ck(cond: bool, name: String, extra := "") -> void:
	if cond:
		_ok += 1
		print("  ✓ ", name)
	else:
		_bad += 1
		print("  ✗ FAIL: ", name, ("  → " + extra) if extra != "" else "")


func _run() -> void:
	# ⚠️ 必须先等一帧。`-s 脚本`模式下 SceneTree 的 root 在 _initialize() 阶段
	#    还没真正激活 —— 这时 add_child 出来的节点 is_inside_tree() 仍是 false，
	#    紧接着 start() Timer / HTTPRequest.request() 会报
	#    "not inside the scene tree"（实测踩过，比 net_cloud_probe 那个坑更深一层）。
	await process_frame
	print("=== 云端客户端探针（真实公网 %s）===\n" % SERVICE)

	# ── ① 自动更新检查 ────────────────────────────────────────────
	print("[1] UpdateCheck")
	var upd := UpdateCheck.new()
	root.add_child(upd)
	print("    本机版本 = ", UpdateCheck.current_version())
	upd.check(SERVICE + "/version.json")
	var ures: Dictionary = await upd.finished
	ck(bool(ures.get("ok", false)), "拉到版本清单", str(ures.get("reason", "")))
	if bool(ures.get("ok", false)):
		# 不写死远端版本号（清单会随发版变），改成"自洽校验"：
		# has_update 必须等于 compare_versions(latest, current) > 0
		var latest := str(ures.get("latest", ""))
		var cur := str(ures.get("current", ""))
		ck(latest != "", "清单带 latest", latest)
		ck(bool(ures.get("has_update", false)) == (UpdateCheck.compare_versions(latest, cur) > 0),
			"has_update 与版本比较自洽（远端 %s vs 本机 %s）" % [latest, cur])
		ck(str(ures.get("size", "")) != "", "带安装包大小", str(ures.get("size", "")))
		ck(str(ures.get("url", "")) != "", "带下载地址（签名 URL）")
		var notes: Array = ures.get("notes", [])
		ck(notes.size() > 0, "带玩家可读的更新说明", str(notes.size()))
	upd.queue_free()

	# 版本比较函数（纯逻辑，不依赖网络）
	ck(UpdateCheck.compare_versions("10.5.0", "10.4.0") == 1, "compare_versions 新版 > 旧版")
	ck(UpdateCheck.compare_versions("10.4.0", "10.4.0") == 0, "compare_versions 相同 = 0")
	ck(UpdateCheck.compare_versions("9.20", "10.4.0") == -1, "compare_versions 跨位数比较正确")
	ck(UpdateCheck.compare_versions("10.4.1", "10.4") == 1, "compare_versions 缺段按 0 处理")

	# ── ② 账号：注册 → 登录 → 进度 ──────────────────────────────
	print("\n[2] CloudApi")
	var api := CloudApi.new()
	api.service_url = SERVICE
	root.add_child(api)

	var stamp := str(int(Time.get_unix_time_from_system()))
	var nm := "探针" + stamp
	var pw := "pw" + stamp
	_created_name = nm
	print("    测试账号 ", nm)

	api.register(nm, pw)
	var r1: Array = await api.register_done
	ck(bool(r1[0]), "注册成功", str(r1[2]))
	var token_after_reg: String = api.token
	ck(token_after_reg != "", "拿到 token")

	# 重名
	var api2 := CloudApi.new()
	api2.service_url = SERVICE
	root.add_child(api2)
	api2.register(nm, pw)
	var r2: Array = await api2.register_done
	ck(not bool(r2[0]) and str(r2[2]) != "", "重名注册被拒且有中文提示", str(r2[2]))
	api2.queue_free()

	# 登录
	var api3 := CloudApi.new()
	api3.service_url = SERVICE
	root.add_child(api3)
	api3.login(nm, pw)
	var r3: Array = await api3.login_done
	ck(bool(r3[0]), "登录成功", str(r3[2]))
	var acct: Dictionary = r3[1]
	ck(str(acct.get("name", "")) == nm, "返回账号昵称正确")
	ck(not acct.has("hash") and not acct.has("salt"), "响应不含 hash/salt")

	# 错密码
	api3.login(nm, "definitely-wrong-pw")
	var r4: Array = await api3.login_done
	ck(not bool(r4[0]), "错密码被拒")
	ck(str(r4[2]).find("昵称或密码") >= 0 or str(r4[2]) != "", "错密码有提示文案", str(r4[2]))

	# 进度上传（用 api3 的 token）
	api3.upload_progress("veteran", true, "jianwu")
	var r5: Array = await api3.progress_done
	ck(bool(r5[0]), "进度上传成功", str(r5[1]))
	var prog: Dictionary = api3.account.get("progress", {})
	ck(str(prog.get("tier", "")) == "veteran"
		and bool(prog.get("tutorial_done", false))
		and str(prog.get("tutorial_hero", "")) == "jianwu", "进度回包正确", str(prog))

	# 换个客户端重新登录，验证进度**真的存到云端了**（不是本地缓存）
	var api4 := CloudApi.new()
	api4.service_url = SERVICE
	root.add_child(api4)
	api4.login(nm, pw)
	var r6: Array = await api4.login_done
	ck(bool(r6[0]), "新客户端重新登录")
	var acct2: Dictionary = r6[1]
	var prog2: Dictionary = acct2.get("progress", {})
	ck(str(prog2.get("tier", "")) == "veteran" and str(prog2.get("tutorial_hero", "")) == "jianwu",
		"★ 另一个客户端读到同样的进度（云端持久化生效）", str(prog2))

	# ── ③ 连不上时必须优雅失败，不能崩 ──────────────────────────
	print("\n[3] 容错")
	var api5 := CloudApi.new()
	api5.service_url = "http://127.0.0.1:1"      # 必然连不上
	root.add_child(api5)
	api5.login("x", "yyyyyy")
	var r7: Array = await api5.login_done
	ck(not bool(r7[0]) and str(r7[2]) != "", "连不上时优雅失败并给提示", str(r7[2]))

	var upd2 := UpdateCheck.new()
	root.add_child(upd2)
	upd2.check("http://127.0.0.1:1/version.json")
	var ures2: Dictionary = await upd2.finished
	ck(not bool(ures2.get("ok", false)), "更新检查失败时 ok=false（放行，不拦玩家）")
	ck(bool(ures2.get("has_update", false)) == false, "失败时不误报有新版本")

	print("\n=== 云端客户端探针：PASS %d / FAIL %d ===" % [_ok, _bad])
	print("CLEANUP_NAME=%s" % _created_name)
	quit(1 if _bad > 0 else 0)
