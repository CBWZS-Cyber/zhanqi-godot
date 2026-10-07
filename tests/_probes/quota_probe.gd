extends SceneTree
## 战术模型「每日额度」链路探针（2026-10-05）
##
## 专门验证**新的那半**：设备标识、额度回执解析、以及"次数用完 → 提示登录"这条路径。
## 服务端那侧的逻辑由 tools 里的 Node 测试台覆盖（29 项）；这里只管**客户端**。
##
## ⚠️ 用**本地假服务器**造 429，不在生产环境上真刷爆额度。
##    配合 Node 假服务器跑（见 tools/cloud-service/quota_fake_server.js 或临时脚本）：
##      18899 → 429（额度用完）    18898 → 200（正常）
##
## 跑：godot --headless --path . -s res://tests/_probes/quota_probe.gd

const FAKE_429 := "http://127.0.0.1:18899/llm"
const FAKE_200 := "http://127.0.0.1:18898/llm"

var _ok := 0
var _bad := 0


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
	await process_frame

	print("\n[1] 设备标识 DeviceId")
	var id1 := DeviceId.get_id()
	var id2 := DeviceId.get_id()
	ck(id1.length() >= 16, "拿到设备标识（长度 %d）" % id1.length(), id1)
	ck(id1 == id2, "同一进程内稳定（不会每次调用都换一个）")
	ck(FileAccess.file_exists("user://device_id.txt"), "已落盘 user://device_id.txt（下次启动沿用）")

	# ── ② 额度用完：429 的中文原因与 need_login 必须能捞出来 ──────────
	# 这是本探针的重点：`_post_json` 在非 200 时返回 null，如果没把响应体留住，
	# 玩家看到的就是笼统的"战术模型未响应"，而不是"登录后每天 10 次"。
	print("\n[2] 次数用完（假服务器 429）")
	AICfg.endpoint = FAKE_429
	var t := LLMDecider._ask_cloud("测试卷子")
	ck(t == "", "失败时返回空串（调用方据此回退本地 AI）")
	ck(LLMDecider.last_http_code == 429, "记下了 HTTP 429", str(LLMDecider.last_http_code))
	ck(LLMDecider.last_need_login, "解析出 need_login=true（界面据此提示去登录）")
	ck(LLMDecider.last_error.find("登录") >= 0, "拿到了服务端的中文原因", LLMDecider.last_error)
	ck(int(LLMDecider.last_quota.get("limit", 0)) == 3, "拿到了额度回执 limit=3", str(LLMDecider.last_quota))
	ck(int(LLMDecider.last_quota.get("left", -1)) == 0, "回执里 left=0")

	# ── ③ 正常一次：不能残留上一轮的失败状态 ────────────────────────
	print("\n[3] 正常调用（假服务器 200）")
	AICfg.endpoint = FAKE_200
	var t2 := LLMDecider._ask_cloud("测试卷子")
	ck(t2 != "", "拿到模型文本")
	ck(LLMDecider.last_error == "", "上次的失败原因已清空（否则会误报）")
	ck(not LLMDecider.last_need_login, "need_login 已复位")

	# ── ④ 真云端：ping 必须带回 quota，且**不消耗**额度 ─────────────
	print("\n[4] 真云端 /llm/ping 带回剩余次数")
	AICfg.reset_endpoint()
	var http := HTTPRequest.new()
	root.add_child(http)
	var url := AICfg.ping_url() + "?device_id=" + DeviceId.get_id()
	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	ck(err == OK, "发起 ping 请求")
	if err == OK:
		var r: Array = await http.request_completed
		ck(int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200, "ping 返回 200", "result=%s code=%s" % [r[0], r[1]])
		var d: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			var dd: Dictionary = d
			var q: Variant = dd.get("quota", {})
			ck(typeof(q) == TYPE_DICTIONARY, "响应里有 quota 字段")
			if typeof(q) == TYPE_DICTIONARY:
				var qd: Dictionary = q
				ck(str(qd.get("tier", "")) != "", "quota.tier 非空", str(qd.get("tier")))
				ck(qd.has("left"), "quota.left 存在（界面就是拿它显示'今日剩余 N 次'）", str(qd))
				print("    回执：", JSON.stringify(qd))
		else:
			ck(false, "ping 响应能解析成字典")
	http.queue_free()

	print("\n=== 额度链路探针：PASS %d / FAIL %d ===" % [_ok, _bad])
	quit(1 if _bad > 0 else 0)
