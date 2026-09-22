extends SceneTree
## 阶段2验证：指令重放同步。
## A/B 两个镜像 battle（同种子）。A 侧随机驱动"人类操作"→ 每步编码成指令 → B 侧 apply_cmd 重放。
## 校验：重放后双方 log/状态/winner 一致。
func _initialize() -> void:
	var BT := load("res://scripts/combat/battle_team.gd")
	var NP := load("res://scripts/net/net_protocol.gd")
	var red: Array = ["crystal_dragon", "jianwu", "guang_yu", "yao_shi"]
	var blue: Array = ["xie_shen", "gu_lang", "xian_zun", "he_zhigao"]
	# human_mode 关闭（双方都由测试脚本直接驱动 current 单位）。
	# 用法：测试脚本作为"两个玩家"的代理，分别向 A/B 发指令。
	var a = BT.new(red.duplicate(), blue.duplicate())
	a.ai_level = "easy"
	a.enable_lookahead = false
	a.set_rng_seed(555)
	var b = BT.new(red.duplicate(), blue.duplicate())
	b.ai_level = "easy"
	b.enable_lookahead = false
	b.set_rng_seed(555)
	# 注意：镜像必须不用 AI 自动跑 —— 但 run_step 会走 AI。改用双方都是"人类代理"：
	# 这里直接手动调用 _turn_ai 驱动 A 的 AI 单位，并把对应的"AI 决策结果"作为指令发给 B？
	# 不行——AI 决策是引擎内部行为（确定性随机已保证一致），不需要指令传输。
	# 指令只针对"人类操作"。所以验证方案：A 全程 human_mode 走人类代理，
	# B 镜像只重放人类指令；AI 单位行动由各自引擎确定性独立执行（不传指令）。
	# —— 但 B 的 AI 行动必须与 A 严格同步：靠 run_step 驱动到"轮到人类"即可。
	# 更简单的端到端模型：两边都 human_mode 且热座(全人类) → 所有操作都是指令 → 双边重放。
	a.human_mode = true
	a.human_teams = [0, 1]
	a.ai_level = "easy"   # 热座无 AI
	b.human_mode = true
	b.human_teams = [0, 1]
	b.ai_level = "easy"
	# A 为操作源：驱动 a 跑完一整局（代理人类），每条操作同步到 b
	var guard := 0
	var errs: Array = []
	var sent := 0
	while guard < 3000 and a.winner == "":
		guard += 1
		var st: Dictionary = a.run_step()
		if st.has("wait"):
			var me = a.current()
			if me == null:
				errs.append("A 无 current")
				break
			var idx: int = a.units.find(me)
			# 代理决策：能放技能就放（slot1 平A），否则走一步，然后 done
			var cmd := {}
			var castable: bool = false
			for slot in range(1, 5):
				if a.base_usable(me, slot):
					var foes: Array = a.alive_enemies_of(me)
					if foes.size() > 0 and slot <= 2:
						cmd = NP.make_cast(idx, slot, foes[0], a)
						castable = true
						break
			if not castable:
				if not a.human_moved() and a.move_cells_of(me).size() > 0:
					var cells: Array = a.move_cells_of(me)
					var c: Vector2i = cells[0]
					cmd = NP.make_move(idx, c)
				else:
					cmd = NP.make_done(idx)
			# A 本地执行
			var ra: String = str(NP.apply_cmd(a, cmd))
			if ra.begins_with("!REPLAY_"):
				errs.append("A 本地执行护栏: " + ra)
				break
			# 编码 → 网络传输 → B 重放（B 先 run_step 推进到同一等待点）
			var wire: String = NP.encode(cmd)
			var cmd2: Dictionary = NP.decode(wire)
			if cmd2.is_empty():
				errs.append("解码失败: " + wire)
				break
			var sb: Dictionary = b.run_step()
			if not sb.has("wait"):
				errs.append("B 未进入等待: " + str(sb))
				break
			var bme = b.current()
			if bme != b.units[idx]:
				errs.append("B actor 不同步: 期望 units[%d], 实际 %s" % [idx, str(bme)])
				break
			var rb: String = str(NP.apply_cmd(b, cmd2))
			if rb.begins_with("!REPLAY_"):
				errs.append("B 重放护栏: " + rb + " (cmd=" + wire + ")")
				break
			sent += 1
			# 一致性抽查：log 长度
			if a.log.size() != b.log.size():
				errs.append("log 长度漂移 @%d: %d vs %d" % [sent, a.log.size(), b.log.size()])
				break
		elif st.has("over"):
			break
	# 收尾：A 已 over，B 还需推进到最后（差一条"僵局"终局 log）
	var tail := 0
	while tail < 50 and b.winner == "":
		tail += 1
		if b.run_step().has("wait"):
			errs.append("收尾时 B 意外等待操作")
			break
	var same_log: bool = (a.log == b.log)
	var same_winner: bool = (a.winner == b.winner and a.winner != "")
	print("发送指令数=", sent, " log一致=", same_log, " (", a.log.size(), "/", b.log.size(), ") winner一致=", same_winner, " (", a.winner, "/", b.winner, ")")
	if not same_log:
		for i in range(mini(a.log.size(), b.log.size())):
			if a.log[i] != b.log[i]:
				print("首个差异@", i, ": [", a.log[i], "] vs [", b.log[i], "]")
				break
	for e in errs:
		print("ERR: ", e)
	var ok := same_log and same_winner and errs.is_empty() and sent > 20
	print("==== 结果:", "PASS ✅" if ok else "FAIL ❌", "====")
	quit(0 if ok else 1)
