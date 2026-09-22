class_name LLMDecider
extends RefCounted
## 豆包（火山方舟 Responses API）战术决策器 v2 ——「选择题」融合模式
## 数据流（每回合一次）：
##   1) 规则层为每个待决策单位生成 3 个候选动作：A 进攻 / B 稳守 / C 保命（均保证合法）；
##   2) 局面 + 候选清单发给豆包，请它做“选择题”并给出全队战术：{focus, posture, protect, choices};
##   3) 解析后返回：units下标 -> {"move":..., "has_move":..., "skill":{...}, "has_skill":...}（执行层 _exec_llm_plan 兼容）；
##      并把 {focus, posture, protect} 写入 battle.llm_tactics（规则 AI 第 2 步据此调权重）。
## 任何失败（无 key/网络/解析异常）返回 {} → 调用方回退本地 AI。

const TIMEOUT_MS := 30000   # 2026-09-05 实测：关思考后真实卷子 ~4s，留 30s 兜底网络波动
const POSTURES := ["aggressive", "balanced", "defensive", "kite"]
const CHOICE_KEYS := ["A", "B", "C"]

## —— 主入口：battle 提供视图；decide_list = 需要 AI 决策的单位 ——
static func plan_round(battle, decide_list: Array) -> Dictionary:
	if decide_list.is_empty():
		return {}
	if not AICfg.ready():
		return {}
	# 1) 生成本地候选（每个单位 A/B/C）
	var candidates := {}          # idx_str -> Array[候选 dict]
	for u in decide_list:
		var idx := _idx_of(battle, u)
		if idx >= 0:
			candidates[str(idx)] = _candidates_for(battle, u)
	# 2) 组装卷子
	var prompt := _build_prompt(battle, candidates)
	var body := {
		"model": AICfg.DEFAULT_MODEL,
		## 2026-09-05 实测：doubao-seed-evolving 默认深度思考 20s+，超时必挂；
		## 必须 thinking:disabled 关闭思考（真实卷子 4.3s 返回正确 JSON）
		"thinking": {"type": "disabled"},
		"input": [{"role": "user", "content": [{"type": "input_text", "text": prompt}]}],
	}
	var headers := [
		"Authorization: Bearer " + AICfg.api_key(),
		"Content-Type: application/json",
	]
	var resp: Variant = _post_json(AICfg.DEFAULT_BASE_URL, headers, JSON.stringify(body))
	if typeof(resp) != TYPE_DICTIONARY:
		return {}
	return _parse_response(battle, resp, candidates)

## ============ 候选生成（v1：A 进攻 / B 稳守 / C 保命，全部为合法动作） ============
## 候选字段：{key,label,desc, move:Vector2i|null, slot:int(0=不放技), target:int(-1=无/自身)}
static func _candidates_for(battle, u: BattleUnit) -> Array:
	var out: Array = []
	out.append(_cand_attack(battle, u))
	out.append(_cand_balance(battle, u))
	out.append(_cand_retreat(battle, u))
	return out

## A 进攻：能打到就打最脆目标（大招优先），打不到就贴近最近敌人
static func _cand_attack(battle, u: BattleUnit) -> Dictionary:
	var foes: Array = battle.alive_enemies_of(u)
	var slot := 0
	var tid := -1
	if foes.size() > 0:
		for s in [4, 3, 2, 1]:
			if not battle.base_usable(u, s) or battle.self_skill(u, s):
				continue
			var tgt := _weakest_in_range(battle, u, s)
			if tgt != null:
				slot = s
				tid = _idx_of(battle, tgt)
				break
	var cell := Vector2i(-1, -1)
	if slot == 0 and foes.size() > 0:
		cell = _approach_cell(battle, u, foes)
	var desc := "进攻"
	if slot > 0:
		desc = "对 %s 释放【%s】" % [_short(battle, tid), _slot_name(battle, u, slot)]
	elif cell.x >= 0:
		desc = "向最近敌人 %s 靠拢" % _short(battle, _idx_of(battle, _nearest_foe(u, foes)))
	return _mk_cand("A", "进攻", desc, cell, slot, tid)

## B 稳守：打得着就低成本输出/小走位；打不着微调站位，避免冒进
static func _cand_balance(battle, u: BattleUnit) -> Dictionary:
	var cell := Vector2i(-1, -1)
	var slot := 0
	var tid := -1
	# 优先射程内目标打一发（找能耗最低可打技）
	for s in [1, 2, 3, 4]:
		if not battle.base_usable(u, s) or battle.self_skill(u, s):
			continue
		var tgt := _weakest_in_range(battle, u, s)
		if tgt != null:
			slot = s
			tid = _idx_of(battle, tgt)
			break
	if slot == 0:
		# 无目标可打：若有治疗/护盾自保技先备着；否则保持位置小走位
		for s in [1, 2, 3, 4]:
			if battle.base_usable(u, s) and battle.self_skill(u, s):
				var k := _self_kind(battle, u, s)
				if k == "heal" or k == "shield":
					slot = s
					break
	var desc := "稳守"
	if slot > 0:
		desc = "对 %s 释放【%s】" % [_short(battle, tid), _slot_name(battle, u, slot)]
	else:
		desc = "按兵不动保存能量"
	return _mk_cand("B", "稳守", desc, cell, slot, tid)

## C 保命：优先自疗/护盾；否则后撤远离贴身敌人
static func _cand_retreat(battle, u: BattleUnit) -> Dictionary:
	var cell := Vector2i(-1, -1)
	var slot := 0
	var tid := -1
	for s in [3, 2, 4, 1]:
		if battle.base_usable(u, s) and battle.self_skill(u, s):
			var k := _self_kind(battle, u, s)
			if k == "heal" or k == "shield":
				slot = s
				break
	var foes: Array = battle.alive_enemies_of(u)
	if slot == 0:
		cell = _retreat_cell(battle, u, foes)
	var desc := "保命"
	if slot > 0:
		desc = "给自己【%s】自保" % _slot_name(battle, u, slot)
	elif cell.x >= 0:
		desc = "后撤一步远离敌人"
	return _mk_cand("C", "保命", desc, cell, slot, tid)

static func _mk_cand(key: String, label: String, desc: String, cell: Vector2i, slot: int, tid: int) -> Dictionary:
	return {"key": key, "label": label, "desc": desc, "move": cell, "slot": slot, "target": tid}

## ============ 候选/查询辅助 ============
static func _idx_of(battle, u: BattleUnit) -> int:
	if u == null:
		return -1
	for i in range(battle.units.size()):
		if battle.units[i] == u:
			return i
	return -1

static func _short(battle, idx: int) -> String:
	if idx < 0 or idx >= battle.units.size():
		return "?"
	return "%s(%d)" % [str(battle.units[idx].name), idx]

static func _slot_name(battle, u: BattleUnit, slot: int) -> String:
	var sk := u.get_skill(slot)
	return sk.display_name if sk != null else ("技%d" % slot)

static func _weakest_in_range(battle, u: BattleUnit, slot: int) -> BattleUnit:
	var best: BattleUnit = null
	var bs := 1.0e18
	for t in battle.targets_in_range(u, slot):
		var tu: BattleUnit = t
		var sc := float(tu.hp + tu.shield)
		if sc < bs:
			bs = sc
			best = tu
	return best

static func _nearest_foe(u: BattleUnit, foes: Array) -> BattleUnit:
	var best: BattleUnit = null
	var bd := 99999
	for f in foes:
		var ff: BattleUnit = f
		var d := absi(ff.cell.x - u.cell.x) + absi(ff.cell.y - u.cell.y)
		if d < bd:
			bd = d
			best = ff
	return best

static func _approach_cell(battle, u: BattleUnit, foes: Array) -> Vector2i:
	var foe := _nearest_foe(u, foes)
	if foe == null:
		return Vector2i(-1, -1)
	var cands: Array = battle.move_cells_of(u)
	if cands.is_empty():
		return Vector2i(-1, -1)
	var best_c := Vector2i(-1, -1)
	var bd := 99999
	for c in cands:
		var cc: Vector2i = c
		var d := absi(cc.x - foe.cell.x) + absi(cc.y - foe.cell.y)
		if d < bd:
			bd = d
			best_c = cc
	return best_c

static func _retreat_cell(battle, u: BattleUnit, foes: Array) -> Vector2i:
	var cands: Array = battle.move_cells_of(u)
	if cands.is_empty():
		return Vector2i(-1, -1)
	var best_c := Vector2i(-1, -1)
	var bd := -1
	for c in cands:
		var cc: Vector2i = c
		var near := 99999
		for f in foes:
			var ff: BattleUnit = f
			near = mini(near, absi(ff.cell.x - cc.x) + absi(ff.cell.y - cc.y))
		if near > bd:
			bd = near
			best_c = cc
	return best_c

static func _self_kind(battle, u: BattleUnit, slot: int) -> String:
	var sk := u.get_skill(slot)
	if sk == null:
		return ""
	return str(battle.skill_data(sk.id).get("ai", {}).get("self_kind", ""))

## ============ 卷子组装 ============
static func _build_prompt(battle, candidates: Dictionary) -> String:
	var l := PackedStringArray()
	l.append("你是回合制战棋《战棋》的高难度 AI 指挥官。请阅读战局，做两件事：①为每名待决策单位选择执行哪个候选方案；②给出全队战术指令。")
	l.append("")
	l.append("战场 x0..9 / y1..8（y 向上）。单位：")
	var n: int = battle.units.size()
	for i in range(n):
		var u: BattleUnit = battle.units[i]
		l.append("%d=%s(%s) 位(%d,%d) HP%d/%d 盾%d 甲%d 能%d 速%d %s" % [i, u.name, "红" if u.team == 0 else "蓝",
			u.cell.x, u.cell.y, u.hp, u.max_hp, u.shield, u.armor, u.energy, u.effective_speed(),
			("状态:" + u.to_status_summary()) if u.to_status_summary() != "" else ""])
	l.append("")
	l.append("待决策单位及其候选（每单位必须三选一：A 进攻 / B 稳守 / C 保命）：")
	for idx_str in candidates:
		var u: BattleUnit = battle.units[int(idx_str)]
		l.append("单位 %s【%s】HP%d/%d 能%d：" % [idx_str, u.name, u.hp, u.max_hp, u.energy])
		for c in candidates[idx_str]:
			l.append("  %s.%s：%s" % [c["key"], c["label"], c["desc"]])
	l.append("")
	l.append("全队战术字段说明：focus=全队应优先集火的敌方单位编号（无则 null）；posture 只能取 aggressive/balanced/defensive/kite；protect=需要重点保护的己方单位编号（无则 null）。")
	l.append("只输出一个 JSON（不要解释、不要代码块）：")
	l.append('{"focus": <敌方编号|null>, "posture": "balanced", "protect": <己方编号|null>, "choices": {"单位编号": "A"}}')
	l.append("要求：choices 必须覆盖上面列出的每个待决策单位；其余字段必须合法；不确定时 posture 用 balanced。")
	return "\n".join(l)

## —— 同步 POST（第 4 步将换为异步 HTTPRequest） ——
static func _post_json(url: String, headers: Array, body: String) -> Variant:
	var http := HTTPClient.new()
	var host := url.replace("https://", "").replace("http://", "")
	var path := "/"
	var slash := host.find("/")
	if slash >= 0:
		path = host.substr(slash)
		host = host.substr(0, slash)
	var tls := TLSOptions.client()
	if not _connect(http, host, tls):
		http.close()
		http = HTTPClient.new()
		tls = TLSOptions.client_unsafe()
		if not _connect(http, host, tls):
			http.close()
			return null
	var t0 := Time.get_ticks_msec()
	var err := http.request(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		http.close()
		return null
	var chunks := PackedByteArray()
	var last_data := Time.get_ticks_msec()   # 最近一次读到 body 数据的时刻
	while true:
		http.poll()
		var st := http.get_status()
		if st == HTTPClient.STATUS_BODY:
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				chunks.append_array(chunk)
				last_data = Time.get_ticks_msec()
		elif st == HTTPClient.STATUS_DISCONNECTED:
			break
		# 读到过 body 后若 1.5s 无新数据：keep-alive 下服务端不主动断开，
		# 视为 body 已收完（状态可能停在 CONNECTED，独立判据不依赖状态机）
		if chunks.size() > 0 and Time.get_ticks_msec() - last_data > 1500:
			break
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS:
			break
		OS.delay_msec(2)
	var code := http.get_response_code()
	http.close()
	if code != 200:
		print("[LLM] HTTP ", code, " body: ", chunks.get_string_from_utf8().substr(0, 300))
		return null
	var parsed: Variant = JSON.parse_string(chunks.get_string_from_utf8())
	return parsed

static func _connect(http: HTTPClient, host: String, tls: TLSOptions) -> bool:
	var err := http.connect_to_host(host, -1, tls)
	if err != OK:
		return false
	var t0 := Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() - t0 > 3000:
			return false
		OS.delay_msec(2)
	return http.get_status() == HTTPClient.STATUS_CONNECTED

## ============ 答题卡解析 ============
static func _parse_response(battle, resp: Dictionary, candidates: Dictionary) -> Dictionary:
	var text := ""
	var out: Variant = resp.get("output", [])
	if out is Array:
		for item in out:
			if item is Dictionary and item.get("type", "") == "message":
				var content: Variant = item.get("content", [])
				if content is Array:
					for c in content:
						if c is Dictionary and (c.get("type", "") == "output_text" or c.has("text")):
							text += str(c.get("text", ""))
	if text.strip_edges() == "":
		return {}
	var obj: Variant = JSON.parse_string(text)
	if typeof(obj) != TYPE_DICTIONARY:
		var a := text.find("{")
		var b := text.rfind("}")
		if a >= 0 and b > a:
			obj = JSON.parse_string(text.substr(a, b - a + 1))
	if typeof(obj) != TYPE_DICTIONARY:
		return {}
	# 战术指令（第 2 步规则 AI 消费）
	var focus: Variant = obj.get("focus", null)
	var protect: Variant = obj.get("protect", null)
	var posture := str(obj.get("posture", "balanced"))
	if not POSTURES.has(posture):
		posture = "balanced"
	if battle.has_method("has") or (battle is Dictionary):
		pass
	# Battle/ BattleTeam 是对象 → 直接写属性
	battle.llm_tactics = {
		"focus": int(focus) if typeof(focus) == TYPE_FLOAT or typeof(focus) == TYPE_INT else -1,
		"posture": posture,
		"protect": int(protect) if typeof(protect) == TYPE_FLOAT or typeof(protect) == TYPE_INT else -1,
	}
	# 逐单位选择
	var plans := {}
	var choices: Variant = obj.get("choices", {})
	if typeof(choices) != TYPE_DICTIONARY:
		choices = {}
	for idx_str in candidates:
		var key := str(choices.get(idx_str, "B"))
		if not CHOICE_KEYS.has(key):
			key = "B"
		var chosen: Dictionary = {}
		for c in candidates[idx_str]:
			if c["key"] == key:
				chosen = c
				break
		plans[idx_str] = _cand_to_plan(chosen)
	return plans

## 候选 → 执行层预案（与 _exec_llm_plan 对齐）
static func _cand_to_plan(c: Dictionary) -> Dictionary:
	var cell: Vector2i = c.get("move", Vector2i(-1, -1))
	var has_move := cell.x >= 0
	var slot := int(c.get("slot", 0))
	var skill := {}
	var has_skill := slot >= 1 and slot <= 4
	if has_skill:
		skill = {"slot": slot, "target": int(c.get("target", -1))}
	return {"move": cell, "has_move": has_move, "skill": skill, "has_skill": has_skill}
