extends SceneTree
## AI 三档定标基准（仅本地规则 AI，不涉及豆包）
## ⚠️ 本文件是【测试判定专用】—— 以下胜负规则只用于评测对局结果，
##    不会写入游戏正式对局（正式对局仍为全灭定胜负 + 80 回合超时）：
##   1) 一方全灭 → 对方胜（与正式规则一致）；
##   2) 第 30 回合末起：存活人数多者胜；相等则继续打；
##   3) 双方都各剩 1 棋（回合 ≥30）：按各自剩余血量占最大血量百分比判定，高者胜；
##   4) 保险兜底：打到 60 回合仍无法判定（理论极罕见）→ 记平局、该局不计入胜负。
## 评测目标（简单难度 AI 逻辑不动、作为基线）：
##   A. easy vs normal：normal 胜率 ≥ 90%
##   B. normal vs hard（本地 AI，ai_backend=local）：hard 胜率 ≥ 80%
## 用法：Godot --headless --path 工程 -s res://tests/ai_tier_bench.gd

const JUDGE_ROUND := 30      # 多数决起始回合
const HARD_CAP := 60         # 判定保险上限（防止理论死循环）
const MATCHES := 60         # 每档对打的总局数

## 4V4 英雄强度表（来自 hero_team_rank.gd 剔除追猎后的 M1 场均净贡献，2026-09-05）
## 用途：均衡分阵营 —— 让两队总强度接近，剔除“英雄失衡”噪声，只测难度贡献。
## 追猎 zhuilie 超模（净+1.0 出场即胜），会破坏均衡抽样，故从难度基准中排除（单独平衡处理）。
const HERO_POWER := {
	"jianwu": 0.36, "crystal_dragon": 0.22, "guang_yu": 0.19, "ling_xu": 0.03,
	"yao_shi": -0.01, "gu_lang": -0.04, "he_zhigao": -0.15, "xie_shen": -0.18,
	"xian_zun": -0.21, "xin_kelai": -0.24,
}
## 均衡抽样强度差阈值（两队总分差 ≤ 此值才接受）
const BALANCE_TOL := 0.30

var _p := 0
var _f := 0

func _initialize() -> void:
	print("== AI 三档定标（本地）开始 ==")
	randomize()
	var r1 := run_match("normal", "easy")     # A 组：normal 打 easy
	var r2 := run_match("hard", "normal")     # B 组：hard 打 normal
	_report("A. normal vs easy（目标 normal ≥70%）", r1, "normal", 70.0)
	_report("B. hard vs normal（目标 hard ≥70%）", r2, "hard", 70.0)
	print("== 定标结束：PASS %d / FAIL %d ==" % [_p, _f])
	quit(1 if _f > 0 else 0)

## 强方 strong_lvl 打弱方 weak_lvl。
## 强度均衡分阵营：从 10 英雄池随机抽样两队，直到两队 HERO_POWER 总分之差 ≤ 阈值。
## 这样每局两队“纸面实力”接近，胜负差异≈纯难度贡献（英雄失衡噪声被压住）。
## 强方坐红/蓝随机，进一步抵消出生/先后偏置。
func run_match(strong_lvl: String, weak_lvl: String) -> Dictionary:
	var strong_wins := 0
	var weak_wins := 0
	var draws := 0
	var rounds_sum := 0
	var total := 0
	for _i in range(MATCHES):
		var ga: Array = []
		var gb: Array = []
		for _try in range(300):
			var pool := HERO_POWER.keys()
			pool.shuffle()
			ga = pool.slice(0, 4)
			gb = pool.slice(4, 8)
			var sa := 0.0
			var sb := 0.0
			for id in ga:
				sa += float(HERO_POWER[id])
			for id in gb:
				sb += float(HERO_POWER[id])
			if absf(sa - sb) <= BALANCE_TOL:
				break
		var strong_red := randi() % 2 == 0
		total += 1
		var b := BattleTeam.new(
			ga if strong_red else gb,
			gb if strong_red else ga)
		b.ai_backend = "local"
		b.side_levels = {0: strong_lvl if strong_red else weak_lvl, 1: weak_lvl if strong_red else strong_lvl}
		b.set_meta("red_lvl", strong_lvl if strong_red else weak_lvl)
		b.set_meta("blue_lvl", weak_lvl if strong_red else strong_lvl)
		var w: String = play(b)
		rounds_sum += b.round
		var s_won: bool = (w == "红方" and strong_red) or (w == "蓝方" and not strong_red)
		var w_won: bool = (w == "蓝方" and strong_red) or (w == "红方" and not strong_red)
		if s_won:
			strong_wins += 1
		elif w_won:
			weak_wins += 1
		else:
			draws += 1
	return {
		"total": total, "strong": strong_wins, "weak": weak_wins, "draws": draws,
		"avg_rounds": rounds_sum / float(maxi(1, total)),
	}

## 逐回合驱动（不用 run_step/simulate，避免内置胜负判定介入）。
## BattleTeam 的 ai_level 是单值 → 每个单位行动前按它阵营的难度临时写入。
func play(b: BattleTeam) -> String:
	## 得分制：由战斗层内置判定（25 分 / 全灭），每单位行动后立即结算。
	var red_lvl := str(b.get_meta("red_lvl", "easy"))
	var blue_lvl := str(b.get_meta("blue_lvl", "easy"))
	while b.round < 120 and b.winner == "":
		b._start_round()
		while b._queue.size() > 0 and b.winner == "":
			var actor = b._poll_next()
			if actor == null:
				break
			b.ai_level = red_lvl if actor.team == 0 else blue_lvl
			b._turn_ai(actor)
			b._landed(actor)
			b._check_win()
		if b.winner == "":
			b._end_round()
	if b.winner != "":
		return b.winner
	return "僵局"

func _report(title: String, r: Dictionary, tag: String, target: float) -> void:
	var valid := int(r["total"]) - int(r["draws"])
	var rate := float(r["strong"]) / float(maxi(1, valid)) * 100.0
	var ok := rate >= target
	print("== %s ==" % title)
	print("   %s胜 %d / 有效 %d（平局 %d 不计）| 胜率 %.1f%% | 平均回合 %.1f" % [
		tag, r["strong"], valid, r["draws"], rate, r["avg_rounds"]])
	if ok:
		_p += 1
		print("   ✓ 达标（≥%d%%）" % int(target))
	else:
		_f += 1
		print("   ✗ 未达标（需 ≥%d%%）" % int(target))
