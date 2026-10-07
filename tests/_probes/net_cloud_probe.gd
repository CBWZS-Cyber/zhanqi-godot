extends SceneTree
## 一次性探针（2026-10-03 联机上云）：验证「Godot 客户端 → 云端房间服务」真实链路。
## 用法：godot --headless --path <工程> -s res://tests/_probes/net_cloud_probe.gd
##
## 与 tests/room_code_smoke.gd 的分工：
##   room_code_smoke  → 对**本机临时实例**测客户端逻辑（可离线、进正式回归）
##   本探针           → 对**云端部署**测真实公网链路（要联网，故不进正式回归）
##
## NetRoomCode 刻意不引用 autoload，所以 -s 模式下可直接 new 出来用。

const SVC := "http://39.105.223.8:8787"

var _got := {}

func _initialize() -> void:
	await process_frame     # 等 root 就绪，否则 HTTPRequest 不在 tree 里（!is_inside_tree）
	await _run()

func _run() -> void:
	print("== 云端链路探针 ==")
	print("service = ", SVC)

	var room := NetRoomCode.new()
	room.service_url = SVC
	root.add_child(room)

	room.registered.connect(func(c: String) -> void: _got["code"] = c)
	room.resolved.connect(func(a: String, k: String) -> void: _got["addr"] = a; _got["kind"] = k)
	room.failed.connect(func(r: String) -> void: _got["err"] = r)

	# ⚠️ GDScript 的 lambda 按**值**捕获 —— int 累加不出去，必须用 Dictionary（引用类型）承载计数
	var stat := {"ok": 0, "bad": 0}
	var ck := func(cond: bool, name: String) -> void:
		if cond:
			stat["ok"] = int(stat["ok"]) + 1
			print("  ✓ ", name)
		else:
			stat["bad"] = int(stat["bad"]) + 1
			print("  ✗ FAIL: ", name)

	# 1) 建房：上报一个假地址，换房间号
	var addr_in := "203.0.113.9:3457"
	room.register(addr_in, "tcp")
	if not await _wait(room):
		ck.call(false, "云端 register 在 10s 内返回")
	else:
		ck.call(_got.get("err", "") == "", "云端 register 无错误（err=%s）" % str(_got.get("err", "")))
		var code := str(_got.get("code", ""))
		ck.call(code.length() == 4, "拿到 4 位房间号（%s）" % code)

		# 2) 用号换地址（重新 new 一个客户端，模拟另一台机器）
		_got.clear()
		var joiner := NetRoomCode.new()
		joiner.service_url = SVC
		root.add_child(joiner)
		joiner.resolved.connect(func(a: String, k: String) -> void: _got["addr"] = a; _got["kind"] = k)
		joiner.failed.connect(func(r: String) -> void: _got["err"] = r)
		joiner.resolve(code)
		if not await _wait(joiner):
			ck.call(false, "云端 resolve 在 10s 内返回")
		else:
			ck.call(str(_got.get("addr", "")) == addr_in,
				"用房间号换回同一个地址（%s）" % str(_got.get("addr", "")))
			ck.call(str(_got.get("kind", "")) == "tcp", "kind 一起带回来")

		# 3) 不存在的号码 → 明确失败
		_got.clear()
		var ghost := NetRoomCode.new()
		ghost.service_url = SVC
		root.add_child(ghost)
		ghost.failed.connect(func(r: String) -> void: _got["err"] = r)
		ghost.resolve("0000")   # 4 位合法但没开过的号 —— 必须走**云端 404**；用 11 位会被本地长度校验先挡下，覆盖就名存实亡
		if not await _wait(ghost):
			ck.call(false, "不存在的号在 10s 内返回失败")
		else:
			var e := str(_got.get("err", ""))
			ck.call(e != "", "不存在的号 → failed（%s）" % e)
			ck.call(e.find("不存在") >= 0 or e.find("过期") >= 0,
				"失败原因来自云端 404，而非本地长度校验")

	print("\n=== 云端链路探针: PASS %d / FAIL %d ===" % [stat["ok"], stat["bad"]])
	quit(1 if int(stat["bad"]) > 0 else 0)

## 等一次请求结束（room.busy 落回 false），带 10s 超时
func _wait(room: NetRoomCode) -> bool:
	var t0 := Time.get_ticks_msec()
	while room.busy and Time.get_ticks_msec() - t0 < 10_000:
		await process_frame
	return not room.busy
