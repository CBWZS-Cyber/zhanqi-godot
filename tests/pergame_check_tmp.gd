extends SceneTree
## 验证 per_game 限次：追猎(红,人类) vs 仙尊(蓝,AI)。
## 期望：流炎飞弹第1次成功 → used=1/exhausted=true → base_usable=false → 第2次被拒提示"用尽"
func _initialize() -> void:
	var B := load("res://scripts/combat/battle.gd")
	var b = B.new("zhuilie", "xian_zun")
	b.ai_level = "easy"
	b.human_mode = true
	b.human_team = 0
	b.human_teams = [0]
	# 步进到轮到人类（追猎 team0）。仙尊速131更快会先AI行动一次
	var guard := 0
	while guard < 100 and b.winner == "":
		guard += 1
		var st: Dictionary = b.run_step()
		if st.has("wait"):
			break
	var u = b.current()
	if u == null:
		print("FAIL: 未等到人类回合")
		quit(1)
		return
	print("轮到我方: ", u.name, " round=", b.round)
	var slot := -1
	for i in range(1, 5):
		var sk = u.get_skill(i)
		if sk != null and sk.id == "meteor_shot":
			slot = i
	print("meteor_shot slot = ", slot)
	if slot < 0:
		print("FAIL: 找不到流炎飞弹槽")
		quit(1)
		return
	var foes: Array = b.alive_enemies_of(u)
	print("敌方存活: ", foes.size())
	var foe = foes[0] if foes.size() > 0 else null
	if foe == null:
		print("FAIL: 无敌方目标")
		quit(1)
		return
	var pass_all := true
	var sk = u.get_skill(slot)
	# 第1次释放（先移动再放：直接 cast 即可，cast 内部做位移可达性校验）
	var r1: String = b.human_cast(slot, foe)
	print("第1次 cast → ", r1)
	print("used=%d per_game=%d exhausted=%s" % [sk.used_count, sk.per_game, str(sk.exhausted())])
	if sk.used_count != 1:
		print("FAIL: 第1次后 used_count 应为 1")
		pass_all = false
	# 同回合第2次：技能权已耗尽会被"不在你的回合"拦截（回合结构），不作为 per_game 断言
	# 跨回合才是关键：结束人类回合→新回合追猎再行动，仍应不可用（整局禁用，非冷却）
	b.human_done()
	guard = 0
	while guard < 200 and b.winner == "":
		guard += 1
		var st: Dictionary = b.run_step()
		if st.has("wait"):
			break
	var u2 = b.current()
	if u2 == null or u2 != u:
		print("u2 非追猎: ", str(u2))
	# 冷却 tick 已随回合推进，per_game 不恢复
	if b.base_usable(u2, slot):
		print("FAIL: 新回合 base_usable 仍应为 false（per_game 整局禁用）")
		pass_all = false
	else:
		print("PASS: 新回合 base_usable=false（整局限次生效）")
	if u2.get_skill(slot).used_count != 1:
		print("FAIL: used_count 应为 1（未随回合重置）")
		pass_all = false
	# 对照：狙击(slot1) 无 per_game 应仍可用
	var sk1 = u2.get_skill(1)
	print("狙击 per_game=", sk1.per_game, " exhausted=", sk1.exhausted())
	if sk1.exhausted():
		print("FAIL: 狙击不应 exhausted")
		pass_all = false
	print("==== 结果:", "PASS ✅" if pass_all else "FAIL ❌", "====")
	quit(0 if pass_all else 1)
