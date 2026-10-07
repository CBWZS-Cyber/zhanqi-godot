extends SceneTree
## 云端战术模型探针（2026-10-04）
##
## 验证「客户端 → 自有云服务 → 豆包 → 解析」整条链路，客户端侧**不带任何 Key**。
## 会真实消耗一次模型额度（一次调用约 4~6 秒），不进正式回归。
##
## 跑：godot --headless --path . -s res://tests/_probes/cloud_llm_probe.gd

const SERVICE := "http://39.105.223.8:8789"

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
	# `-s 脚本`模式下必须等一帧，否则 root 未激活、add_child 出来的节点不在树里
	await process_frame

	AICfg.endpoint = SERVICE + "/llm"
	print("=== 云端战术模型探针 ===")
	print("端点 ", AICfg.endpoint)
	print("AICfg.ready() = ", AICfg.ready())

	# ── ① 零成本探测 ──────────────────────────────────────────────
	var http := HTTPRequest.new()
	root.add_child(http)
	var err := http.request(AICfg.ping_url(), [], HTTPClient.METHOD_GET)
	ck(err == OK, "发起 ping 请求")
	var args: Array = await http.request_completed
	var code: int = args[1]
	var body: PackedByteArray = args[3]
	ck(code == 200, "ping 返回 200（实际 %d）" % code)
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	ck(typeof(d) == TYPE_DICTIONARY and bool((d as Dictionary).get("ready", false)),
		"云端报告 ready", body.get_string_from_utf8().substr(0, 120))
	var model := str((d as Dictionary).get("model", "")) if typeof(d) == TYPE_DICTIONARY else ""
	print("    模型 = ", model)
	http.queue_free()

	# ── ② 真调一次：把真实战局卷子交给云端 ────────────────────────
	# 客户端这边**没有任何 Key** —— 全靠云端；这是本次改造的核心。
	print("\n[2] 真实战局调用（会消耗一次额度，约 4~6 秒）")
	var BT := load("res://scripts/combat/battle_team.gd")
	var b = BT.new(["crystal_dragon", "jianwu", "guang_yu", "yao_shi"],
		["xie_shen", "gu_lang", "xian_zun", "he_zhigao"])
	b.ai_level = "hard"
	b.ai_backend = "llm"

	var unit: BattleUnit = null
	for x in b.units:
		if x.team == 1 and x.alive:
			unit = x
			break
	ck(unit != null, "取到一个待决策的蓝方单位")

	var t0 := Time.get_ticks_msec()
	var plans: Dictionary = LLMDecider.plan_round(b, [unit])
	var ms := Time.get_ticks_msec() - t0
	print("    耗时 %.1fs" % (ms / 1000.0))

	ck(not plans.is_empty(), "plan_round 返回非空（说明云端→豆包→解析全通）")
	if not plans.is_empty():
		var idx := str(b.units.find(unit))
		var p: Dictionary = plans.get(idx, {})
		ck(not p.is_empty(), "拿到该单位的执行预案", str(plans.keys()))
		var t: Dictionary = b.llm_tactics
		ck(t.has("posture"), "全队战术已写入 battle.llm_tactics", str(t))
		print("    战术：", str(t))
		print("    预案：", str(p))

	# ── ③ 端点不可达时必须优雅失败（回退本地 AI 的前提）──────────
	print("\n[3] 容错")
	AICfg.endpoint = "http://127.0.0.1:1/llm"
	var t1 := Time.get_ticks_msec()
	var p2: Dictionary = LLMDecider.plan_round(b, [unit])
	var ms2 := Time.get_ticks_msec() - t1
	ck(p2.is_empty(), "端点不可达时返回空字典（调用方据此回退本地 AI），耗时 %.0fms" % ms2)

	AICfg.reset_endpoint()
	ck(AICfg.endpoint == AICfg.DEFAULT_ENDPOINT, "reset_endpoint 能回到兜底")

	print("\n=== 云端战术模型探针：PASS %d / FAIL %d ===" % [_ok, _bad])
	quit(1 if _bad > 0 else 0)
