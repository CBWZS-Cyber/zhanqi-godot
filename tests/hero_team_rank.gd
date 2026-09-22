extends SceneTree
## 英雄 4V4 强度锦标赛（多模块）
## M1 团队净贡献：随机 4v4 混战，胜方每棋 +1 / 负方 -1 → 场均净贡献（定位价值）
## M2 单核携带力：每英雄固定带队 vs 全随机敌方 → 带队胜率（carry 能力）
## 统一使用 easy 本地 AI（无前瞻、双方同水准），简单快速 → 结果≈英雄在随机队中的相对强度
## 裁决沿用测试规则：全灭 → 30回合多数决 → 1v1 血量百分比
const M1_N := 240          # M1 混战场次
const M2_N := 26           # M2 每英雄带队场次
const HEROES := [
	["crystal_dragon", "元晶龙王"], ["jianwu", "剑舞"], ["xie_shen", "邪神"],
	["guang_yu", "光雨"], ["yao_shi", "药师"], ["zhuilie", "追猎"],
	["gu_lang", "孤狼"], ["he_zhigao", "rapper睡神"], ["xian_zun", "仙尊"],
	["ling_xu", "灵虚数影"], ["xin_kelai", "辛克莱"],
]
var _ids: Array = []
var _names := {}

func _initialize() -> void:
	randomize()
	var exclude := ""
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--exclude="):
			exclude = a.trim_prefix("--exclude=")
	for h in HEROES:
		if h[0] == exclude:
			continue
		_ids.append(h[0])
		_names[h[0]] = h[1]
	var tag := "（剔除 %s）" % _names.get(exclude, exclude) if exclude != "" else "（全英雄）"
	# —— M1 ——
	var score := {}
	var games := {}
	for id in _ids:
		score[id] = 0
		games[id] = 0
	var t0 := Time.get_ticks_msec()
	for _i in range(M1_N):
		var pool := _ids.duplicate()
		pool.shuffle()
		var red: Array = pool.slice(0, 4)
		var blue: Array = pool.slice(4, 8)
		var w := _match(red, blue)
		for id in red:
			games[id] += 1
			score[id] += 1 if w == "红方" else (-1 if w == "蓝方" else 0)
		for id in blue:
			games[id] += 1
			score[id] += 1 if w == "蓝方" else (-1 if w == "红方" else 0)
	# —— M2 ——
	var carry := {}
	for id in _ids:
		carry[id] = [0, 0]   # [带队胜, 场次]
	for i in range(M2_N):
		for id in _ids:
			var rest := _ids.duplicate()
			rest.erase(id)
			rest.shuffle()
			var red: Array = [id]
			red.append_array(rest.slice(0, 3))
			var blue: Array = rest.slice(3, 7)
			var w := _match(red, blue)
			carry[id][1] += 1
			if w == "红方":
				carry[id][0] += 1
	var el: float = (Time.get_ticks_msec() - t0) / 1000.0
	print("== 4V4 英雄锦标赛 %s（%d+%d 局 · %.0fs · 双方 easy AI）==" % [tag, M1_N, M2_N * _ids.size(), el])
	var rows: Array = []
	for id in _ids:
		var g: int = games[id]
		var net := float(score[id]) / float(maxi(1, g))          # -1..1
		var wr := (net + 1.0) / 2.0 * 100.0                        # 折合胜率
		var cg: int = carry[id][1]
		var cw := float(carry[id][0]) / float(maxi(1, cg)) * 100.0
		rows.append({"id": id, "name": _names[id], "g": g, "net": net, "wr": wr, "cw": cw})
	rows.sort_custom(func(a, b): return a["net"] > b["net"])
	for r in rows:
		print("  %-10s %-6s M1净%.2f(折合%2.0f%%) 出场%d | M2带队胜率%2.0f%%(%d/%d)" % [
			r["id"], r["name"], r["net"], r["wr"], r["g"], r["cw"], carry[r["id"]][0], carry[r["id"]][1]])
	print("== done ==")
	quit(0)

## 随机一局 4v4：red/blue 各 4 英雄，返回胜方 "红方"/"蓝方"/"平局"
func _match(red: Array, blue: Array) -> String:
	## 得分制：全自动跑到战斗层内置判定（双方同难度 normal）
	var b := BattleTeam.new(red, blue)
	b.ai_backend = "local"
	b.enable_lookahead = false   # 强度测试不需要前瞻（双方同水准即可），关掉提速
	b.ai_level = "easy"
	return b.simulate()

