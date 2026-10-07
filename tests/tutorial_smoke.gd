extends SceneTree
## 战棋 · 新手教程回归（tutorial smoke）
## 用法：godot --headless --path 工程 -s res://tests/tutorial_smoke.gd
## 覆盖：
##   A. 教程定义表（木桩参数铁律 / 教程角色与 HeroDefs 的隔离）
##   B. 教程战斗层（BattleTutorial）：木桩构造、摆位、玩家走原路径、木桩行为
##   C. 两个**设计不变量**（一旦被后人改坏，教程会静默卡死，所以必须钉死）：
##      ① 每个教程角色都必须**能对木桩造成伤害**（否则第 7 步无法完成）；
##      ② 木桩轻击必须走「盾→甲→血」——0 甲角色掉血、有甲角色被甲吃掉。
## 全部通过 exit 0，有失败 exit 1。

var _passes := 0
var _fails := 0

func ck(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  ✓ ", name)
	else:
		_fails += 1
		printerr("  ✗ FAIL: ", name)

var BT
var TD
var HD
## 本机匿名进度模块（2026-10-05 之前叫 AccountStore —— 客户要求删掉「本地账号」后，
## 它只剩「一份无名字的进度」，所以变量名也换掉，免得读测试的人误以为还有账号系统）。
var PS

func _initialize() -> void:
	BT = load("res://scripts/combat/battle_tutorial.gd")
	TD = load("res://scripts/combat/tutorial_defs.gd")
	HD = load("res://scripts/combat/hero_defs.gd")
	PS = load("res://scripts/save/progress_store.gd")
	var t0 := Time.get_ticks_msec()
	# 测试会读写 user://progress.json（教程完成会写进度），
	# 先备份、结束后还原 —— 测试不许动玩家真实存档。
	_save_bak = _snapshot_save()
	_test_defs()
	_test_dummy_build()
	_test_layout_and_turn_order()
	_test_hero_can_damage_dummy()
	_test_dummy_strike_pipeline()
	_test_strike_throttle()
	_test_terrain()
	_test_progress_store()
	await _test_ui_flow()
	await _test_step_tables()
	await _test_ui_flow_played_tier()
	await _test_end_turn_gate()
	await _test_practice_button()
	await _test_dash_window()
	_restore_save()
	var dt := Time.get_ticks_msec() - t0
	print("== 教程回归结果: PASS %d / FAIL %d（%d ms）==" % [_passes, _fails, dt])
	quit(1 if _fails > 0 else 0)


# ---------------- 存档快照（测试卫生） ----------------

var _save_bak := ""
var _save_existed := false

func _snapshot_save() -> String:
	_save_existed = FileAccess.file_exists(PS.PATH)
	if not _save_existed:
		return ""
	var f := FileAccess.open(PS.PATH, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s

func _restore_save() -> void:
	if _save_existed:
		var f := FileAccess.open(PS.PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_bak)
			f.close()
	elif FileAccess.file_exists(PS.PATH):
		DirAccess.remove_absolute(PS.PATH)


# ---------------- A. 定义表 ----------------

func _test_defs() -> void:
	print("【A】教程定义表")
	# 铁律：木桩护甲必须为 0。原因见 tutorial_defs.gd 文件头（剑舞/追猎只有 1 点伤害，
	# 木桩带甲会让这两个英雄恒为 0 伤害、教程卡死）。
	ck(int(TD.DUMMY["armor"]) == 0, "木桩护甲 = 0（改成 >0 会让剑舞/追猎打不动）")
	ck(float(TD.DUMMY["hp"]) >= 4.0, "木桩血量 ≥ 4（要撑得住整个教程）")
	ck(int(TD.DUMMY["speed"]) == 1, "木桩速度 = 1（永远最后行动，玩家总能先手）")
	ck(TD.DUMMY["skills"]["actives"] == ["", "", "", ""], "木桩不带任何技能（行为在 BattleTutorial 里）")
	ck(not TD.DUMMY.has("sanity_cap"), "木桩没有理智条（不写 sanity_cap）")

	# 隔离：木桩不许混进英雄表 / 选人池
	ck(not HD.ALL.has(TD.DUMMY_ID), "木桩 id 不在 HeroDefs.ALL（与正式英雄隔离）")
	# 选人池的真实构造方式 = 遍历 ALL 的 key 再按 is_pickable 过滤（duel.gd:98 / team_duel.gd:924），
	# 所以这里照同样的方式复现一遍，确认木桩进不去。
	# 注：不能只断言 is_pickable("tut_dummy") == false —— 它对"不存在的 id"也返回 true（它只是过滤器）。
	var pool: Array = []
	for k in HD.ALL:
		if HD.is_pickable(str(k)):
			pool.append(str(k))
	ck(not pool.has(TD.DUMMY_ID), "选人池（同款过滤）不含木桩（%d 个可选英雄）" % pool.size())

	# 教程角色必须都是真实可用的英雄
	var ids: Array = TD.hero_ids()
	ck(ids.size() == 4, "教程角色 = 4 个（精选，覆盖位移/远程/自益/全图）")
	for hid in ids:
		ck(HD.ALL.has(hid), "教程角色 %s 存在于 HeroDefs" % str(hid))
		ck(HD.is_pickable(str(hid)), "教程角色 %s 可选（不在 BANNED）" % str(hid))


# ---------------- B. 战斗层 ----------------

func _test_dummy_build() -> void:
	print("【B1】木桩构造（每个教程角色各建一次）")
	for hid in TD.hero_ids():
		var b = BT.new(str(hid))
		var d = b.dummy
		ck(d != null, "[%s] 木桩已生成" % str(hid))
		ck(d.def_id == TD.DUMMY_ID, "[%s] 木桩 def_id 正确" % str(hid))
		ck(is_equal_approx(d.max_hp, float(TD.DUMMY["hp"])), "[%s] 木桩血量走教程表" % str(hid))
		ck(is_equal_approx(d.armor, 0.0), "[%s] 木桩护甲 0" % str(hid))
		ck(d.speed == 1, "[%s] 木桩速度 1" % str(hid))
		var no_skill := true
		for s in d.actives:
			if s != null:
				no_skill = false
		ck(no_skill, "[%s] 木桩无可用技能" % str(hid))
		# 玩家必须仍然走 HeroDefs 原路径（数值一点没变）
		# 注：1V1 的 Battle._make 不给 def 填 id（4V4 的 BattleTeam._make 才填），
		# 所以这里用 name 认身份；def_id 的既有不一致已在文档里记为待确认项，教程不依赖它。
		var p = b.player_unit()
		ck(p.name == str(HD.ALL[str(hid)]["name"]), "[%s] 玩家身份 = HeroDefs 该英雄" % str(hid))
		ck(is_equal_approx(p.max_hp, float(HD.ALL[str(hid)]["hp"])),
			"[%s] 玩家血量与 HeroDefs 完全一致（教程不改英雄数值）" % str(hid))
		ck(is_equal_approx(p.armor, float(HD.ALL[str(hid)].get("armor", 0))),
			"[%s] 玩家护甲与 HeroDefs 一致" % str(hid))


func _test_layout_and_turn_order() -> void:
	print("【B2】摆位与行动序")
	var b = BT.new("crystal_dragon")
	ck(b.player_unit().cell == BT.PLAYER_START, "玩家摆在 %s" % str(BT.PLAYER_START))
	ck(b.dummy.cell == BT.DUMMY_START, "木桩摆在 %s" % str(BT.DUMMY_START))
	var st: Dictionary = b.run_step()
	ck(st.has("wait"), "开局 run_step 停在「轮到玩家」（木桩速度 1，抢不到先手）")
	ck(b.current() == b.player_unit(), "当前行动单位 = 玩家")
	# 玩家移动一步：8 方向相邻格，且移动后地形 id 已同步
	var p = b.player_unit()
	var dest: Vector2i = b.move_cells_of(p)[0]
	var mv: String = b.human_move(dest)
	ck(p.cell == dest, "玩家可移动一格（%s）" % mv)
	ck(b.human_moved(), "移动权已消耗")


func _test_hero_can_damage_dummy() -> void:
	print("【B3】设计不变量①：每个教程角色都能打伤木桩")
	for hid in TD.hero_ids():
		var hurt := false
		var detail := ""
		for slot in [1, 2, 3, 4]:
			var b = BT.new(str(hid))
			b.run_step()
			var p = b.player_unit()
			# 贴到木桩旁边（8 方向相邻），保证射程 1~3 的目标技都够得着
			b._put(p, BT.DUMMY_START + Vector2i(-1, 0))
			var before: float = b.dummy.hp
			var res: String = b.human_cast(slot, b.dummy)
			if b.dummy.hp < before:
				hurt = true
				detail = "技能槽 %d 造成 %.0f 伤害" % [slot, before - b.dummy.hp]
				break
		ck(hurt, "[%s] 至少有一个技能能对木桩造成伤害（%s）" % [str(hid), detail])


func _test_dummy_strike_pipeline() -> void:
	print("【B4】设计不变量②：木桩轻击走「盾→甲→血」")
	# 0 甲角色（光雨）：1 点轻击 → 掉 1 血
	var b0 = BT.new("guang_yu")
	ck(is_equal_approx(b0.player_unit().armor, 0.0), "[光雨] 玩家护甲 = 0（前提成立）")
	b0._dummy_turns = TD.DUMMY_STRIKE_EVERY - 1        # 下一次木桩行动即轻击
	b0._put(b0.dummy, BT.PLAYER_START + Vector2i(1, 0))  # 贴到射程 1 内
	var hp_before: float = b0.player_unit().hp
	b0._dummy_act(b0.dummy)
	ck(b0.strike_count == 1, "[光雨] 木桩轻击已发生")
	ck(is_equal_approx(b0.player_unit().hp, hp_before - 1.0), "[光雨] 0 甲 → 掉 1 血（%.0f→%.0f）"
		% [hp_before, b0.player_unit().hp])

	# 高甲角色（追猎，甲 3）：1 点轻击被甲**全部吃掉** → 血量不变
	var b1 = BT.new("zhuilie")
	ck(b1.player_unit().armor >= 1.0, "[追猎] 玩家护甲 ≥ 1（前提成立）")
	b1._dummy_turns = TD.DUMMY_STRIKE_EVERY - 1
	b1._put(b1.dummy, BT.PLAYER_START + Vector2i(1, 0))
	var hp1: float = b1.player_unit().hp
	b1._dummy_act(b1.dummy)
	ck(b1.strike_count == 1, "[追猎] 木桩轻击已发生")
	ck(is_equal_approx(b1.player_unit().hp, hp1), "[追猎] 甲 ≥ 1 → 轻击被甲吃满，不掉血（教「甲是平摊减伤」）")


func _test_strike_throttle() -> void:
	print("【B5】木桩轻击节流（新手最多挨 1~2 下）")
	var b = BT.new("guang_yu")
	b._put(b.dummy, BT.PLAYER_START + Vector2i(1, 0))   # 一直贴着，够得着
	for i in range(TD.DUMMY_STRIKE_EVERY):
		b._dummy_act(b.dummy)
	ck(b.strike_count == 1, "连续 %d 个木桩回合只轻击 1 次（节流生效）" % TD.DUMMY_STRIKE_EVERY)
	ck(b.player_unit().hp >= 1.0, "玩家未被磨死（光雨 6 血，全程安全）")


# ---------------- C. 本机匿名进度（不是账号！）----------------

## ⚠️ 2026-10-05：客户要求删掉整套「本地账号」，只留**一份匿名本机进度**
##    （没有名字、没有 id、没有任何账号列表）。这里钉住它的读写与降级行为，
##    尤其是「它永远不会退化成账号」这一点。
func _test_progress_store() -> void:
	print("【C】本机匿名进度（ProgressStore —— 不是账号）")
	PS.reset()
	ck(not PS.has_any(), "重置后没有任何进度（= 0 进度原始账号）")
	var d0: Dictionary = PS.load_progress()
	ck(str(d0.get("tier", "")) == "", "空白进度的水平未选（会触发「问一次水平」）")
	ck(not bool(d0.get("tutorial_done", false)), "空白进度的教程未完成")
	ck(not d0.has("name") and not d0.has("id"), "★ 进度里**没有名字、没有 id**（它不是账号）")

	PS.update({"tier": PS.TIER_NEW, "tutorial_done": true})
	var d1: Dictionary = PS.load_progress()
	ck(str(d1.get("tier", "")) == PS.TIER_NEW, "水平写进去了")
	ck(bool(d1.get("tutorial_done", false)), "教程进度写进去了")
	ck(PS.has_any(), "有进度后 has_any() 为真（启动会直接进主菜单）")

	PS.update({"tutorial_hero": "guang_yu"})
	ck(str(PS.load_progress().get("tutorial_hero", "")) == "guang_yu", "合并更新只改传进来的字段")

	ck(PS.tier_label(PS.TIER_NEW) == "新手", "档位文案：新手")
	ck(PS.tier_label(PS.TIER_PLAYED) == "玩过战棋", "档位文案：玩过战棋")
	ck(PS.tier_label(PS.TIER_VETERAN) == "老手", "档位文案：老手")
	ck(PS.tier_label("") == "未选择", "档位文案：未选择")

	# 只认三个字段：脏数据不许写回文件 —— 它永远不能变成"账号"
	PS.save_progress({"tier": "played", "name": "不该有名字", "id": "不该有id"})
	var d2: Dictionary = PS.load_progress()
	ck(not d2.has("name") and not d2.has("id"),
		"★ 脏字段（name / id）被丢掉 —— 这份进度**永远不会退化成账号**")

	# 存档损坏时必须降级为「没有进度」而不是崩
	var f := FileAccess.open(PS.PATH, FileAccess.WRITE)
	f.store_string("{ 这不是合法 JSON ")
	f.close()
	ck(not PS.has_any(), "存档损坏 → 当作没有进度（降级不崩）")
	ck(str(PS.load_progress().get("tier", "")) == "", "存档损坏 → 返回空白进度")


# ---------------- D. 引导关端到端（真建场景 + 模拟点击） ----------------

## 取 autoload Global。
## ⚠️ 不能在测试里直接写 `Global.xxx`：`-s 脚本` 模式下 autoload 名解析不了会直接
## 编译失败（README 注意点里记过这个假阳性，但它会真的挡住整个测试执行）。
func _g() -> Node:
	return root.get_node_or_null("Global")


## 当前教程界面的步骤 id 列表
func _ids(ui) -> Array:
	var out: Array = []
	for s in ui._steps:
		out.append(str(s.get("id", "")))
	return out


## 建一个教程场景并等两帧（布局 / 遮罩 / 步骤机都跑完再断言）
func _open_tutorial(hero_id: String, tier: String):
	var g := _g()
	if g == null:
		return null
	g.tutorial_hero = hero_id
	g.tutorial_tier = tier
	var ui = load("res://scenes/Tutorial.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	return ui


func _test_ui_flow() -> void:
	print("【D】引导关端到端：龙王 · 完整篇，跟着提示走完")
	PS.wipe()
	ck(_g() != null, "能取到 autoload Global")
	if _g() == null:
		return
	var ui = await _open_tutorial("crystal_dragon", PS.TIER_NEW)
	ck(ui != null and ui._phase == "play", "开局处于可操作状态")
	ck(ui._battle != null, "教程战斗层已建立")
	ck(ui._mask != null and is_instance_valid(ui._mask), "遮罩层已建立")
	var ids := _ids(ui)
	print("   龙王步骤表：", " → ".join(ids))
	ck(ids.size() >= 7, "步骤表已组装（%d 步 = 基础 4 + 机制 %d + 收尾 3）"
		% [ids.size(), ids.size() - 7])
	ck(str(ui._steps[0]["id"]) == "select", "第 1 步 = select")

	var p: BattleUnit = ui._battle.player_unit()
	ck(p != null, "玩家单位存在")

	# ① 点自己的棋子
	ui._on_cell_clicked(p.cell)
	ck(ui._idx == 1, "① 点自己棋子 → 第 2 步")

	# ② 走一格
	var dest: Vector2i = ui._battle.move_cells_of(p)[0]
	ui._on_cell_clicked(dest)
	ck(p.cell == dest, "② 棋子确实移动了一格")
	ck(ui._idx == 2, "② → 第 3 步")

	# ③④ 点技能 → 连过「挑技能 / 释放技能」
	ui._on_skill_clicked(1)
	ck(str(ui._steps[ui._idx]["id"]).begins_with("mech_"),
		"③④ 放完技能直接进入机制步（实际 %s）" % str(ui._steps[ui._idx]["id"]))
	# 关键回归：第 4 步顺手打伤木桩**不该**把后面的步骤跳过去
	ck(ui._phase == "play", "★ 提前打伤木桩不会提前判定教程完成")

	# 其余步骤由步骤表自己驱动：读到哪一步就做对应动作 —— 以后增删机制步不用改测试
	var seen: Array = []
	var guard := 0
	while ui._phase == "play" and guard < 14:
		guard += 1
		var sid := str(ui._steps[ui._idx]["id"])
		seen.append(sid)
		match sid:
			"bars", "mech_range", "mech_status", "mech_terrain":
				ui._on_next_pressed()          # 纯讲解步
			"mech_self":
				ui._on_skill_clicked(2)        # 化晶为铠：龙王唯一的自身技
			"mech_dash":
				ui._on_next_pressed()          # 龙王没有位移技，走不到这里
			"end_turn":
				ui._on_end_turn()
			"damage":
				ui._on_skill_clicked(1)        # 凝晶为刃：打伤木桩 → 完成
			_:
				break
		await process_frame
	ck(ui._phase == "over", "打伤木桩后教程完成（phase=%s）" % str(ui._phase))
	ck(seen.has("mech_range"), "走过机制步 mech_range（%s）" % str(seen))
	ck(seen.has("bars") and seen.has("end_turn") and seen.has("damage"),
		"收尾三步都走到了（%s）" % str(seen))
	ck(ui._over_layer != null and is_instance_valid(ui._over_layer), "结算页已弹出")
	ck(ui._mask != null and not ui._mask.visible, "结算后遮罩已隐藏")
	ui.queue_free()
	await process_frame


# ---------------- E. 步骤表按英雄数据组装（4 个教程角色） ----------------

## 预期机制步：依据 2026-09-28 实测的技能数据写死 —— 数据一变这里就会红，提醒有人来看一眼。
##   位移（DATA[id].ai.dash）：只有剑舞（诛心·瞬移）、追猎（追猎·瞬移）
##   自身技（range 0 或 self_buff）：龙王（化晶为铠）、追猎（架盾）
##   射程（有 r2~3 的目标技）：四个都有
##   状态关键词（流血/灼伤/眩晕/创伤/重伤…）：光雨（星矢·眩晕）、剑舞（贯穿·重伤）、
##     追猎（创伤/流血/灼烧）；**龙王四个技能描述里没有状态关键词 → 不插状态步**
const EXPECT_MECH := {
	"crystal_dragon": ["mech_range", "mech_self", "mech_terrain"],
	"guang_yu": ["mech_range", "mech_status", "mech_terrain"],
	"jianwu": ["mech_range", "mech_dash", "mech_status", "mech_terrain"],
	"zhuilie": ["mech_range", "mech_dash", "mech_self", "mech_status", "mech_terrain"],
}

func _test_step_tables() -> void:
	print("【E】按英雄数据组装步骤表（4 个教程角色）")
	if _g() == null:
		return
	for hid in TD.hero_ids():
		var ui = await _open_tutorial(str(hid), PS.TIER_NEW)
		var ids := _ids(ui)
		var mech: Array = ids.filter(func(x): return str(x).begins_with("mech_"))
		print("   %s：%s" % [ui._hero_name, " → ".join(ids)])
		ck(ids.slice(0, 4) == ["select", "move", "skill", "cast"],
			"[%s] 完整篇前 4 步 = 基础操作" % str(hid))
		ck(ids.slice(ids.size() - 3) == ["bars", "end_turn", "damage"],
			"[%s] 后 3 步 = 三条/交回合/打伤害" % str(hid))
		ck(mech == EXPECT_MECH[str(hid)],
			"[%s] 机制步与技能数据一致（期望 %s，实际 %s）"
				% [str(hid), str(EXPECT_MECH[str(hid)]), str(mech)])
		ck(ui._battle != null and ui._battle.dummy != null, "[%s] 战斗层与木桩就绪" % str(hid))
		ui.queue_free()
		await process_frame


# ---------------- E2. 精简篇 ----------------

func _test_ui_flow_played_tier() -> void:
	print("【E2】精简篇：不含基础操作 4 步，机制步打头")
	if _g() == null:
		return
	var ui = await _open_tutorial("guang_yu", PS.TIER_PLAYED)
	var ids := _ids(ui)
	print("   光雨 · 精简篇：", " → ".join(ids))
	ck(not ids.has("select") and not ids.has("move") and not ids.has("skill") and not ids.has("cast"),
		"精简篇不含基础操作 4 步")
	ck(str(ui._steps[0]["id"]).begins_with("mech_"),
		"第 1 步就是机制步（%s）" % str(ui._steps[0]["id"]))
	ck(ids.slice(ids.size() - 3) == ["bars", "end_turn", "damage"],
		"末尾仍是 三条/交回合/打伤害")
	ck(ids.size() == EXPECT_MECH["guang_yu"].size() + 3,
		"精简篇 = 机制步 + 收尾 3 步（%d 步）" % ids.size())
	ui.queue_free()
	await process_frame


# ---------------- F. 教程地形 ----------------

## 教程棋盘铺了森林/水域，本段验证「地形真的接上了」，而不只是摆了几格颜色。
func _test_terrain() -> void:
	print("【F】教程地形：接线 + 实测效果")
	var b = BT.new("crystal_dragon")
	ck(b.board != null, "教程战斗层已建地形层（board 非 null）")

	# 出生格必须是空地：新手一开局不该被地形收费，也不该让"打伤木桩"被森林减免干扰
	ck(b.player_unit().terrain_id == Terrain.EMPTY, "玩家出生格是空地")
	ck(b.dummy.terrain_id == Terrain.EMPTY, "木桩出生格是空地")

	# 地形 id 与教程表一致
	ck(b.board.terrain_at(Vector2i(1, 1)) == Terrain.FOREST, "(1,1) = 森林")
	ck(b.board.terrain_at(Vector2i(3, 1)) == Terrain.WATER, "(3,1) = 水域")
	ck(b.board.terrain_at(Vector2i(2, 2)) == Terrain.EMPTY, "(2,2) 木桩脚下 = 空地")

	# 只有白名单里的地形会被写进格图（工程既有约定，见 README 附录 A.2.3）
	for k in b.board.walkable.keys():
		var parts: Array = str(k).split(",")
		var tid: int = b.board.terrain_at(Vector2i(int(parts[0]), int(parts[1])))
		ck(tid == Terrain.EMPTY or Terrain.story_active(tid),
			"格 %s 的地形在白名单内（id=%d）" % [str(k), tid])

	# 实测①森林免伤：同一技能打空地 vs 打森林格，伤害应差 20%
	var plain := _dmg_on(BT.DUMMY_START, BT.DUMMY_START + Vector2i(-1, 0))
	var forest := _dmg_on(Vector2i(1, 3), Vector2i(2, 3))
	ck(plain > 0.0, "空地上打得动木桩（%.2f）" % plain)
	ck(is_equal_approx(forest, plain * 0.8),
		"森林格受击正好 ×0.8（空地 %.2f → 森林 %.2f）" % [plain, forest])

	# 实测②水域禁位移 / 森林移出耗能（走的是 BattleUnit 侧的地形读数）
	var b2 = BT.new("zhuilie")
	b2.run_step()
	var p2: BattleUnit = b2.player_unit()
	b2._put(p2, Vector2i(3, 1))
	ck(p2.terrain_id == Terrain.WATER, "落位后 terrain_id 同步为水域")
	ck(p2.dash_blocked_by_terrain(), "水域里位移技被禁止")
	b2._put(p2, Vector2i(1, 1))
	ck(p2.terrain_id == Terrain.FOREST, "落位后 terrain_id 同步为森林")
	ck(p2.exit_energy_cost() == 1, "从森林移出要多花 1 点能量")


## 造一局：木桩摆 dummy_cell、玩家摆 player_cell（两者相邻），放 1 号技能，返回木桩掉了多少血
func _dmg_on(dummy_cell: Vector2i, player_cell: Vector2i) -> float:
	var b = BT.new("crystal_dragon")
	b.run_step()
	b._put(b.dummy, dummy_cell)
	b._put(b.player_unit(), player_cell)
	var before: float = b.dummy.hp
	b.human_cast(1, b.dummy)
	return before - b.dummy.hp


# ---------------- G. 「结束回合」步骤的 gate 语义 ----------------

## 回归：这一步必须**玩家真的按一下按钮**才算过。
## 为什么单独立一条：`turn_ended` 在「放完技能自动结束本回合」时也会置位
## （见 Tutorial._after_player_action），早先拿它当 gate 会让这一步白给 ——
## 玩家没按过按钮、也没看懂按钮是干什么的，就自动过了。
func _test_end_turn_gate() -> void:
	print("【G】「结束回合」步骤必须真的按一下才算过")
	if _g() == null:
		return
	var ui = await _open_tutorial("crystal_dragon", PS.TIER_NEW)
	var ei := -1
	for i in range(ui._steps.size()):
		if str(ui._steps[i]["id"]) == "end_turn":
			ei = i
	ck(ei > 0, "步骤表里有 end_turn 步（第 %d 步）" % (ei + 1))

	# 造出「回合已自然交出」的局面（turn_ended=true），但不按按钮
	ui._flags["turn_ended"] = true
	ui._goto_step(ei)
	ck(ui._idx == ei, "turn_ended 已置位也**不**自动跳过这一步")
	ui._on_next_pressed()
	ck(ui._idx == ei, "按「下一步」也过不去（它不是讲解步）")

	# 真按按钮
	ui._on_end_turn()
	ck(bool(ui._flags.get("end_turn_pressed", false)), "按下后 end_turn_pressed 已置位")
	ck(ui._idx > ei, "过到下一步（%s）" % str(ui._steps[ui._idx]["id"]))
	ui.queue_free()
	await process_frame


# ---------------- H. 完成页「去实战一局」 ----------------

## 回归：完成页那颗按钮要真的把全局状态配成「离线 → 简单 → 1V1」。
## 少配一个字段就会带着上一局的残留（尤其 net_mode / difficulty）进对局。
func _test_practice_button() -> void:
	print("【H】完成页「去实战一局」配的全局状态")
	if _g() == null:
		return
	var g := _g()
	# 先弄脏，确认按钮会覆盖而不是「碰巧本来就对」
	g.battle_mode = "4v4"
	g.offline_type = "hotseat"
	g.difficulty = "hard"
	g.ai_backend = "llm"
	g.net_mode = true
	var ui = await _open_tutorial("guang_yu", PS.TIER_NEW)
	ui._to_practice()
	ck(str(g.battle_mode) == "1v1", "battle_mode → 1v1")
	ck(str(g.offline_type) == "pve", "offline_type → pve")
	ck(str(g.difficulty) == "easy", "difficulty → easy")
	ck(str(g.ai_backend) == "local", "ai_backend → local（不留战术模型残留）")
	ck(not bool(g.net_mode), "net_mode → false（关掉联机分支）")
	ui.queue_free()
	await process_frame


# ---------------- I. 位移步的残血窗口 + 胜负接管 ----------------

## 这条用例同时钉两件事，因为它们是**配套**的：
##   ① 残血窗口（`weaken_dummy`）让「斩杀类」位移技能能真正生效；
##   ② 胜负接管（`BattleTutorial._check_win` 覆写为空）保证木桩被打死也不会中断教程。
##
## ⚠️ 顺带纠正一个先前写错的判断（2026-09-30 实测）：
##   剑舞「诛心」对**满血**木桩**不是"放不出来"** —— 效果函数只是
##   `if not cut_if_under_pct(tu, 30): out += "无法斩杀"; continue`，即**不执行斩杀但释放照常成立**，
##   而且 `human_cast` 里的位移段落在该判断**之前**就执行完了。
##   所以位移本来就演示得出来；残血窗口的价值是让**斩杀真正发生**，而不是"让技能放得出"。
func _test_dash_window() -> void:
	print("【I】位移步残血窗口 + 胜负接管")
	var s30 := 0.30

	# ① 满血：释放成立、位移照常发生，但**斩杀不生效**（木桩不死）
	var b = BT.new("jianwu")
	b.run_step()
	var p: BattleUnit = b.player_unit()
	var r1: String = b.human_cast(4, b.dummy)          # 剑舞 4 号槽 = 诛心（斩杀·位移）
	ck(not r1.begins_with("!"), "满血时斩杀技**能放出去**（返回「%s」）" % r1)
	ck(p.cell != BT.PLAYER_START,
		"位移照常发生（%s → %s）—— 说明位移演示本来就不受斩杀条件影响" % [str(BT.PLAYER_START), str(p.cell)])
	ck(b.dummy.alive and b.dummy.hp > 0.0, "但斩杀条件不满足 → 木桩没死（血 %.0f）" % b.dummy.hp)

	# ② 残血窗口：压到 ≤30%，斩杀真正生效
	var b2 = BT.new("jianwu")
	b2.run_step()
	b2.weaken_dummy()
	ck(b2.dummy_weakened, "窗口已开启")
	ck(b2.dummy.hp <= b2.dummy.max_hp * s30,
		"木桩被压到 %.0f 血（≤ 满血 %.0f 的 30%%）" % [b2.dummy.hp, b2.dummy.max_hp])
	var r2: String = b2.human_cast(4, b2.dummy)
	ck(r2.find("斩杀") >= 0, "残血时斩杀真正生效（返回「%s」）" % r2)
	ck(not b2.dummy.alive, "木桩被斩杀")

	# ③ ★ 关键：木桩被打死，但教程**不判胜负**（否则会被强行结束）
	ck(str(b2.winner) == "", "★ 打死木桩后 winner 仍为空（_check_win 已被接管）")
	ck(b2.run_step().has("wait"), "★ run_step 仍停在「轮到玩家」，而不是 over")

	# ④ 离开该步时修木桩：复活 + 回满血
	b2.restore_dummy()
	ck(b2.dummy.alive, "木桩已复活")
	ck(is_equal_approx(b2.dummy.hp, b2.dummy.max_hp), "木桩回满血（%.0f）" % b2.dummy.hp)
	ck(b2.dummy_revive_count == 1, "记录了 1 次自我修复")
	ck(not b2.dummy_weakened, "窗口已关闭")

	# ⑤ 界面上确实会在进出「位移」步时开关窗口（不是只有数据层能调）
	var ui = await _open_tutorial("jianwu", PS.TIER_NEW)
	var di := -1
	for i in range(ui._steps.size()):
		if str(ui._steps[i]["id"]) == "mech_dash":
			di = i
	ck(di > 0, "剑舞的步骤表里有 mech_dash（第 %d 步）" % (di + 1))
	ck(not ui._battle.dummy_weakened, "刚进教程时窗口是关的")
	ui._goto_step(di)
	ck(ui._battle.dummy_weakened, "进这一步骤 → 窗口自动开启（木桩 %.0f 血）" % ui._battle.dummy.hp)
	ui._goto_step(di + 1)
	ck(not ui._battle.dummy_weakened, "离开这一步 → 窗口自动关闭")
	ck(is_equal_approx(ui._battle.dummy.hp, ui._battle.dummy.max_hp), "木桩已回满血")
	ui.queue_free()
	await process_frame
