extends SceneTree
## 短信通道「请求形状」探针（2026-10-09）
##
## 目的：钉住**客户端真正发出去的请求体** —— 不是读源码猜，而是打到本地假云端上，
##      把收到的 JSON 原样读回来断言（`channel="sms"` / `phone` / `code` 等字段）。
##      服务端契约见 `docs/短信验证_接口契约.md`；服务端行为由 `selftest_sms.js` 覆盖。
##
## ⚠️ 全程**零真实短信消耗**（假云端不回真 dypns）。
## ⚠️ `-s 脚本` 模式里不能用 autoload 名 —— 本探针只用 `CloudApi`（不带 autoload 依赖）。
##
## 用法（两步，外部脚本负责拉起假云端）：
##   node fake_sms.js &
##   godot --headless --path 工程 -s res://tests/_probes/sms_channel_probe.gd
##
## 全部通过 exit 0，有失败 exit 1。

const BASE := "http://127.0.0.1:18791"
const REQS := "C:/Users/Caobo/AppData/Local/Temp/zq-sms-probe/reqs.jsonl"

var _pass := 0
var _fail := 0


func ck(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ ", name)
	else:
		_fail += 1
		print("  ✗ FAIL: ", name)


func _initialize() -> void:
	await process_frame
	print("【短信通道探针】请求形状（本地假云端，零真实短信）")

	var api := CloudApi.new()
	api.service_url = BASE
	root.add_child(api)
	await process_frame

	# ① 注册短信码
	api.send_code_sms("13800000001")
	var s1: Array = await api.send_code_done
	ck(bool(s1[0]), "send_code_sms → 成功回调")

	# ② 短信注册
	api.register_sms("联调甲", "abcdef", "13800000001", "246810")
	var r1: Array = await api.register_done
	ck(bool(r1[0]), "register_sms → 成功回调")
	ck(api.token == "tok-sms", "token 已落到实例上")
	ck(bool(api.account.get("phoneBound", false)), "account.phoneBound = true（解析到了）")
	ck(str(api.account.get("phone", "")) == "138****0001", "account.phone 是掩码（实际「%s」）" % str(api.account.get("phone", "")))

	# ③ 短信找回码
	api.send_reset_code_sms("联调甲")
	var s2: Array = await api.reset_code_done
	ck(bool(s2[0]), "send_reset_code_sms → 成功回调")
	ck(str(s2[1]) == "138****0001", "reset_code_done 带回掩码手机号（实际「%s」）" % str(s2[1]))

	# ④ 短信改密
	api.reset_password_sms("联调甲", "246810", "abcdef2")
	var r2: Array = await api.reset_password_done
	ck(bool(r2[0]), "reset_password_sms → 成功回调")

	# ⑤ 绑定手机号（老账号补绑）
	api.bind_phone_send("13900000001")
	var b1: Array = await api.bind_phone_done
	ck(bool(b1[0]), "bind_phone 发码 → 成功回调")
	api.bind_phone_commit("13900000001", "246810")
	var b2: Array = await api.bind_phone_done
	ck(bool(b2[0]), "bind_phone 提交 → 成功回调")
	ck(str(b2[1]) == "139****0001", "bind_phone_done 带回掩码（实际「%s」）" % str(b2[1]))

	# ⑥ 关键一步：把假云端收到的**真实请求体**读回来
	print("  —— 假云端实际收到的请求 ——")
	var raw := FileAccess.get_file_as_string(REQS)
	if raw == "":
		ck(false, "读不到 %s（假云端起了吗？）" % REQS)
	else:
		var reqs: Array = []
		for ln in raw.split("\n"):
			var t := ln.strip_edges()
			if t != "":
				var o: Variant = JSON.parse_string(t)
				if typeof(o) == TYPE_DICTIONARY:
					reqs.append(o)
		ck(reqs.size() >= 6, "假云端共收到 %d 个请求（应 ≥6）" % reqs.size())

		var paths: Array = []
		for q in reqs:
			paths.append(str(q.get("path", "")))
		ck(paths == ["/send-code", "/register", "/send-code", "/reset-password", "/bind-phone", "/bind-phone"],
			"请求路径顺序正确（实际 %s）" % str(paths))

		if reqs.size() >= 6:
			var q1: Dictionary = reqs[0].get("body", {})
			ck(str(q1.get("channel", "")) == "sms", "① 注册码：channel=sms")
			ck(str(q1.get("phone", "")) == "13800000001", "① 注册码：带 phone")
			ck(not q1.has("email"), "① 注册码：**不带** email（不会两路混发）")

			var q2: Dictionary = reqs[1].get("body", {})
			ck(str(q2.get("channel", "")) == "sms", "② 注册：channel=sms")
			ck(str(q2.get("name", "")) == "联调甲" and str(q2.get("phone", "")) == "13800000001"
				and str(q2.get("code", "")) == "246810", "② 注册：name/phone/code 齐全")
			ck(str(q2.get("pass", "")) == "abcdef", "② 注册：pass 字段名正确（不是 pwd）")

			var q3: Dictionary = reqs[2].get("body", {})
			ck(str(q3.get("channel", "")) == "sms", "③ 找回码：channel=sms")
			ck(str(q3.get("name", "")) == "联调甲" and str(q3.get("purpose", "")) == "reset",
				"③ 找回码：带 name + purpose=reset")

			var q4: Dictionary = reqs[3].get("body", {})
			ck(str(q4.get("channel", "")) == "sms" and str(q4.get("code", "")) == "246810"
				and str(q4.get("newpass", "")) == "abcdef2", "④ 改密：channel/name/code/newpass 齐全")

			var q5: Dictionary = reqs[4].get("body", {})
			ck(str(q5.get("action", "")) == "send" and str(q5.get("phone", "")) == "13900000001",
				"⑤ 绑定·发码：action=send + phone")

			var q6: Dictionary = reqs[5].get("body", {})
			ck(str(q6.get("action", "")) == "commit" and str(q6.get("code", "")) == "246810",
				"⑤ 绑定·提交：action=commit + code")

	print("== 短信通道探针: PASS %d / FAIL %d ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
