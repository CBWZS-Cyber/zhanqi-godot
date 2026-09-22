class_name BattleUnit
extends RefCounted
## 剧情模式 · 英雄（棋子）运行时状态与数值操作。
## 基础属性：生命 hp / 能量 energy / 护盾 shield / 护甲 armor / 速度 speed。
## 约定：
##   - shield 初始恒为 0（构造时不从 def 读取），只有战斗中的“护盾技能/效果”才会给它加值；
##     需要特殊初始护盾时再显式调用 set_shield()。
##   - armor 是减伤属性（具体减免公式待玩法定义，占位保留字段）。
##   - 伤害结算顺序（默认）：护盾先吸收 → 剩余扣生命；护甲参与减伤（公式后续填入）。
## 英雄技能：1 个被动 passive + 4 个主动 actives（在 hero_defs 中声明）。

var def_id: String = ""     # 英雄配置 id（对应 hero_defs 里的键）
var element: String = ""     # 英雄主属性（元素）：火/冰/雷/风/土/光/暗…由 def["element"] 提供
var name: String = "单位"
var max_hp: float = 100.0
var hp: float = 100.0
var max_energy: float = 50.0
var energy: float = 50.0
var shield: float = 0.0
var shield_cap: float = 0.0      # 护盾上限：0=不限；>0 时加盾/设盾被裁剪到该值（per-hero 由 def shield_cap 提供）
var armor: float = 0.0
var speed: int = 5          # 基础速度（行动先后由战斗层按 effective_speed 排序，大者先动）
var speed_buff: int = 0     # 速度加成（增益，如“以命相搏”+200）
var _speed_mods := {}       # 速度修正多来源：来源 -> delta（可叠加求和，如 污染-15 + 断流-50）
var team: int = 0           # 阵营：0 红方 / 1 蓝方（摆放时由战斗层设置；目标过滤用）
var alive: bool = true
var cell := Vector2i.ZERO       # 单位所在棋盘格（由战斗层摆放时设置，距离判定用）
var terrain_id: int = 0         # 所在格地形 id（Terrain.*；战斗层在落位/移动后同步）
## 是否无视水域地形（2026-09-12 用户要求：魔渊「龙」可无视水域地形效果）
## 在 _init 中按 def_id 由 Terrain.water_immune_def() 判定；命中的单位站水域不扣能量、
## 也不受「水域禁止位移类技能」限制。
var water_immune := false
var equipment: Array = []       # 已装备武器 id 列表（Weapons.ALL 的键；拾取星星获得）
var flags: Dictionary = {}      # 状态标志："失神"/"被支配"/"永久支配"/"本回合均摊"…（战斗层/效果读写）

# ---- 通用计数资源池（叠层/攒资源，如“元晶”/“污染”）----
# counters_cfg : name -> {"start":n,"per_turn":n(可选),"start_round":n(可选,从第n回合起自动加,默认1),"max":n(0=不限)}
# 运行时值存 counters；每回合开始自动 +per_turn；end_turn 结算 pending 加值
var counters: Dictionary = {}              # name -> 当前值
var _counters_cfg: Dictionary = {}         # name -> 配置
var _pending_grant: Dictionary = {}        # end_turn 待发放
var _rounds: int = 0                       # 已进行的自身回合数（on_turn_start 计数，资源延迟生效用）
var _tsfx: Array = []                     # def["turn_start_effects"]：回合开始配置化效果
var _tefx: Array = []                     # def["turn_end_effects"]：回合结束配置化效果

# ---- 层数规则（声明式，def["layer_rules"] 驱动，供所有“叠层型”英雄复用）----
# 例：{ "污染": { "speed_per_layer": 15, "flag_threshold": {"失神": 3} } }
#   speed_per_layer : 每层使该单位速度 -N（自动维护 speed_mod）
#   flag_threshold  : 层数 >= 阈值时自动置状态 flag，层降后自动清除
var _layer_flags := {}                     # layer -> {threshold, flag}
var _layer_speeds := {}                    # layer -> per_layer_speed_cost
var _share_active := false                 # 一技能登记：本回合伤害分担 + 回合末吸血
var spread_used := 0                        # 蔓延类移动本回合已用次数（虞美人，每回合上限 2）
var non_solid := false                       # 非实体（虞美人/其子体）：不占格、可被叠格、仍可被攻击
var _share_targets: Array = []
var passive: Skill = null
var actives: Array[Skill] = []     # 长度 = 4（按 hero_defs 的 actives 顺序）
var _passive_cd_round: int = 0     # 被动触发节流（可选，战斗层用）

func _init(def: Dictionary) -> void:
	def_id = str(def.get("id", ""))
	element = str(def.get("element", ""))
	name = str(def.get("name", "单位"))
	max_hp = float(def.get("hp", 100))
	hp = max_hp
	max_energy = float(def.get("energy_max", float(def.get("energy", 50))))
	energy = float(def.get("energy", max_energy))
	shield = 0                                  # 初始一律 0，见文件头约定
	shield_cap = float(def.get("shield_cap", 0))  # 护盾上限（0=不限）
	armor = float(def.get("armor", 0))
	speed = int(def.get("speed", 5))
	var cc: Dictionary = def.get("counters", {})
	for k in cc:
		var cfg: Dictionary = cc[k]
		_counters_cfg[str(k)] = cfg
		counters[str(k)] = int(cfg.get("start", 0))
	# 层数规则（声明式）：层数 -> 每层减速 / 阈值状态
	var lr: Dictionary = def.get("layer_rules", {})
	for layer in lr:
		var rule: Dictionary = lr[layer]
		var spt := int(rule.get("speed_per_layer", 0))
		if spt > 0:
			watch_layer_speed(str(layer), spt)
		var ft: Dictionary = rule.get("flag_threshold", {})
		for flag in ft:
			watch_layer_flag(str(layer), int(ft[flag]), str(flag))
	for layer in counters:
		_refresh_layer(str(layer))   # 让初始层数立即生效（速度/阈值状态）
	_tsfx = (def.get("turn_start_effects", []) as Array).duplicate()
	_tefx = (def.get("turn_end_effects", []) as Array).duplicate()
	_hp_flags = (def.get("hp_threshold_flags", []) as Array).duplicate()
	_evasion_pct_default = int(def.get("evasion_pct", 0))
	evasion_pct = _evasion_pct_default
	_revive_rounds = int(def.get("death_revive", {}).get("rounds", 0))
	_revive_hp_pct = int(def.get("death_revive", {}).get("hp_pct", 50))
	_revive_uses = int(def.get("death_revive", {}).get("per_game", 1))
	sanity_cap = float(def.get("sanity_cap", 45))
	has_sanity = def.has("sanity_cap")
	non_solid = bool(def.get("non_solid", false))
	# 地形豁免：无视水域的兵种（如魔渊·龙），按 def_id 判定
	water_immune = Terrain.water_immune_def(def_id)
	# 初始状态标记（def["init_flags"]）：如 大长老"energy_guard"（能量抵消致命伤）/ 宵"lock_min_hp"（锁 1 血）
	for f in (def.get("init_flags", []) as Array):
		add_flag(str(f))
	var edb: Dictionary = def.get("element_damage_bonus", {})
	for k in edb:
		_dmg_bonus_ele[str(k)] = int(edb[k])
	var sk: Dictionary = def.get("skills", {})
	var passive_id := str(sk.get("passive", ""))
	if passive_id != "":
		passive = _make_skill(passive_id)
	var act_ids: Array = sk.get("actives", [])
	actives.clear()
	for i in range(4):
		var sid := str(act_ids[i]) if i < act_ids.size() else ""
		actives.append(_make_skill(sid) if sid != "" else null)


func _make_skill(sid: String) -> Skill:
	var s := Skill.new()
	s.id = sid
	var meta: Dictionary = SkillEffects.DATA.get(sid, {})
	s.display_name = str(meta.get("name", sid))
	s.element = str(meta.get("element", ""))
	s.kind = str(meta.get("kind", "active"))
	s.energy_cost = int(meta.get("energy_cost", 0))
	s.desc = str(meta.get("desc", ""))
	s.cooldown = int(meta.get("cooldown", 0))
	s.per_game = int(meta.get("per_game", 0))
	s.effect = SkillEffects.EFFECTS.get(sid, Callable(SkillEffects, "effect_stub"))
	return s

## ---------- 生命 ----------
func effective_speed() -> int:
	var total := speed + speed_buff
	for src in _speed_mods:
		total += int(_speed_mods[src])
	# 地形：沼泽 -30（实时，离格自动恢复）
	# 注：地形"是否启用"由战斗层决定（BattleStory._build_board 只把启用地形写进地形层，
	#     未启用的写空地 0），单位侧不做白名单判断 —— 否则 1V1/4V4 与单元测试会被误伤。
	total += Terrain.speed_delta(terrain_id)
	return maxi(1, total)

## 移出当前格所需额外能量（森林/沼泽 1、山地 2；0=无代价）
func exit_energy_cost() -> int:
	return Terrain.exit_energy_cost(terrain_id)

## 当前格是否禁止位移类技能（水域/沙地）
## 2026-09-12：龙的 water_immune 使其完全豁免水域（不扣能量、也不吃位移禁令）。
func dash_blocked_by_terrain() -> bool:
	if water_immune:
		return false
	return Terrain.dash_blocked(terrain_id)

## ---------- 装备（武器） ----------
## 拾取/分配武器；返回 "!..." 表示失败
func add_equipment(wid: String) -> String:
	if wid == "":
		return "!无效武器"
	if equipment.has(wid):
		return "!已装备【%s】" % Weapons.name_of(wid)
	equipment.append(wid)
	return ""

func equipment_names() -> Array:
	var out: Array = []
	for w in equipment:
		out.append(Weapons.name_of(str(w)))
	return out

func has_equipment(wid: String) -> bool:
	return equipment.has(wid)

## 速度修正（多来源求和）：src 同名覆盖，不同名叠加
func set_speed_mod_src(src: String, delta: int) -> void:
	_speed_mods[src] = delta

## 同名来源叠加（用于“每击都减速”类效果：瞬击每次 -10 → 累计）
func add_speed_mod_src(src: String, delta: int) -> void:
	_speed_mods[src] = int(_speed_mods.get(src, 0)) + delta

func remove_speed_mod_src(src: String) -> void:
	_speed_mods.erase(src)

func speed_mod_total() -> int:
	var t := 0
	for src in _speed_mods:
		t += int(_speed_mods[src])
	return t

## 兼容旧接口：写入统一来源 "legacy"
func set_speed_mod(n: int) -> void:
	set_speed_mod_src("legacy", n)

func set_speed_buff(n: int) -> void:
	speed_buff = n

## ---------- 伤害加成栈（按技能槽 1..4 / 0=全技能） ----------
## 用法：剑舞剑意“每次使用技能1后 技能1伤害+1（上限4）” → add_slot_damage(1, 1, 4)
var _dmg_slot := {}          # slot(int) -> 加成值
var _dmg_bonus_ele := {}     # 元素 -> +%（对“该主属性目标”造成伤害加成，敌我适用）
var dmg_mult := 1.0          # 伤害倍率（狂怒×2 / 天机1.5 等）
var _evasion_pct_default := 0
var evasion_pct := 0         # 闪避率%（灵虚数影90%；攻击必中技除外）
var _reflect_pct := 0        # 反伤%（阳状态50%）：把所受实际伤害按%弹回攻击者
var _mitig := {}             # 免伤栈：属性id或"all" -> pct（防守态/血狱等全局）
var _mitig_att := {}         # 针对攻击者的免伤：攻击者instance_id -> {pct, who}（孤狼锻体按“人”）
var _invuln := false         # 无敌（rapper 锁血）
var sanity: float = 0.0
var has_sanity := false     # 理智系英雄（def 声明 sanity_cap）：UI 据此把能量栏换成理智栏              # 理智（辛克莱 上限25 初始0，可为负）
var sanity_cap: float = 45.0         # 理智上限（辛克莱 def sanity_cap=25）
var _revive_rounds := 0      # 死亡复活回合数（>0 启用死亡复活；仙尊3）
var _revive_hp_pct: float = 0.0
var _revive_uses := 1
var _corpse := false         # 死亡待复活中
var _lost_skills := {}       # 被掠夺/禁用的技能 id -> true（无法使用；限时锁到期自动解除）
var stolen_skill_id := ""    # 已夺得的技能 id（空=当前无掠夺技）

## 联机确定性随机源：战斗层创建单位时注入（同种子→双方随机结果一致）。
## null = 单机旧路径，回退全局 randi()/randf()（行为与旧版一致）
var rng: RandomNumberGenerator = null

func _randi_sync() -> int:
	return rng.randi() if rng != null else randi()

func _randf_sync() -> float:
	return rng.randf() if rng != null else randf()
var _stolen_pending := ""    # 掠夺所得、待“下回合开始”生效的技能 id
var _stolen_slot := 0        # 掠夺技替换掉的技能槽（1..4）
var _stolen_backup: Skill = null  # 掠夺技时效内被换下的原技能（到期归还）
var STOLEN_ROUNDS := 2       # 掠夺技可用时长（自身回合数）
var _hp_flags := []          # def["hp_threshold_flags"]：生命跨阈值自动置/清 flag
var hit_events: Array = []   # 受击回调：[Callable(attacker, element)]（锻体/防守计数等注册用）
## 致命守护日志（大长老·泉涌）：lose_hp 抵消致命伤时写入，由战斗层每步读取并清空后写进战报
var guard_note: String = ""

func add_slot_damage(slot: int, amount: float, cap: float = -1.0) -> float:
	if amount <= 0:
		return 0
	var cur := int(_dmg_slot.get(slot, 0))
	var added := amount
	if cap > 0 and cur + added > cap:
		added = cap - cur
	if added > 0:
		_dmg_slot[slot] = cur + added
	return added

func element_bonus_of(elem: String) -> int:
	return int(_dmg_bonus_ele.get(elem, 0))

func add_element_bonus(elem: String, pct: int) -> void:
	_dmg_bonus_ele[elem] = int(_dmg_bonus_ele.get(elem, 0)) + pct

func slot_damage(slot: int, base: float) -> float:
	var all := int(_dmg_slot.get(0, 0))
	var sp := int(_dmg_slot.get(slot, 0))
	return base + all + sp

## ---------- 持续回合计时器（状态/增益“持续 N 回合”统一用） ----------
## _timers: id -> {left:int, cb:Callable?}；cb 在到期时调用，可返回 String 并入日志
var _timers := {}

func add_timer(id: String, rounds: int, on_expire: Callable = Callable()) -> void:
	_timers[id] = {"left": maxi(1, rounds), "cb": on_expire}

func timer_left(id: String) -> int:
	return int(_timers.get(id, {}).get("left", 0))

func has_timer(id: String) -> bool:
	return _timers.has(id)

func remove_timer(id: String) -> void:
	_timers.erase(id)

## def["turn_start_effects"] 应用（光雨星河等被动回能/周期性回血）
func _apply_tsfx() -> String:
	var out := ""
	for fx in _tsfx:
		var f: Dictionary = fx
		var kind := str(f.get("kind", ""))
		if kind == "energy":
			out += "；%s 每回合回复 %d 能量" % [name, add_energy(int(f.get("amount", 0)))]
		elif kind == "drunk_check":
			if counter("醉意") >= 5:
				SkillEffects.apply_stun(self, 1)
				out += "；%s 醉意 %d≥5，本回合酒醉（无法行动，醉意清零）" % [name, counter("醉意")]
				set_counter("醉意", 0)
		elif kind == "every" and _rounds % int(f.get("every", 2)) == 0:
			var e := int(f.get("energy", 0))
			var h := int(f.get("hp", 0))
			var hg := heal(h)
			var eg := add_energy(e)
			out += "；%s 周期性回复 %d 生命、%d 能量" % [name, hg, eg]
	return out

## def["turn_end_effects"] 应用（药师膏腴等条件回血/盾）
func _apply_tefx() -> String:
	var out := ""
	for fx in _tefx:
		var f: Dictionary = fx
		var kind := str(f.get("kind", ""))
		if kind == "if_hp_shield":
			if hp > int(f.get("hp_max", 4)):
				continue
			var h := heal(int(f.get("hp", 1)))
			add_shield(int(f.get("shield", 1)))
			out += "；%s 膏腴：回复 %d 生命、%d 护盾" % [name, h, int(f.get("shield", 1))]
		elif kind == "hp":
			var hh := heal(int(f.get("amount", 1)))
			out += "；%s 回复 %d 生命" % [name, hh]
		elif kind == "energy":
			var ee := add_energy(int(f.get("amount", 1)))
			out += "；%s 回复 %d 能量" % [name, ee]
		elif kind == "sanity":
			if has_flag("sanity_outbreak"):
				# 本回合已失控 → 回合末理智归零（设计稿：失控后理智归 0）
				clear_flag("sanity_outbreak")
				clear_flag("sanity_break")
				sanity = 0
				out += "；%s 失控结束，理智归零" % name
			elif sanity < 0:
				# 理智为负：保留负值等下回合失控，期间不回复
				# （旧版在此直接归零并清 flag，导致战斗层 _turn_ai 永远看不到失控信号，失控机制形同虚设）
				out += "；%s 理智为负（%d），下回合将失控" % [name, sanity]
			else:
				var deficit := sanity_cap - sanity
				var gain: float = maxf(0.0, float(deficit)) * float(f.get("ratio", 0.3))
				if gain > 0:
					gain_sanity(gain)
					out += "；%s 回复 30%%缺损理智 +%d（现 %d/%d）" % [name, gain, sanity, sanity_cap]
	return out

func _tick_timers() -> String:
	var out := ""
	for id in _timers.keys():
		var entry: Dictionary = _timers[id]
		entry["left"] = int(entry["left"]) - 1
		if int(entry["left"]) <= 0:
			var cb: Callable = entry.get("cb", Callable())
			_timers.erase(id)
			if not cb.is_null():
				var r: Variant = cb.call()
				if r is String:
					out += r
	return out

func add_flag(f: String) -> void:
	flags[f] = true

func clear_flag(f: String) -> void:
	flags.erase(f)

func has_flag(f: String) -> bool:
	return flags.has(f)

func heal(amount: float) -> float:
	if not alive or amount <= 0:
		return 0
	var before := hp
	hp = minf(max_hp, hp + amount)
	return hp - before

## 直接扣血（已算护盾吸收后）；由 take_damage 调用，也可用于无视护盾的伤害
func lose_hp(amount: float) -> void:
	if not alive and not _corpse:
		return
	var _hp_before := hp
	hp -= amount
	if hp <= 0:
		# 溢出伤害（超出当前生命的那一截）：供「以能量抵消致命伤」类被动结算
		var overflow := maxf(1.0, -hp)
		hp = 0
		if has_flag("lock_min_hp"):
			hp = 1
		elif has_flag("energy_guard") and energy >= 2.0 * overflow:
			# 泉涌（大长老）：受致命伤时用能量抵消，血量保底 1，每抵消 1 点伤害损失 2 点能量
			hp = 1
			energy = maxf(0.0, energy - 2.0 * overflow)
			guard_note = "【泉涌】%s 以能量抵消致命伤：保留 1 点生命，消耗 %.0f 能量（剩余 %.0f）" % [name, 2.0 * overflow, energy]
		elif _revive_rounds > 0 and _revive_uses > 0 and not _corpse:
			_corpse = true
			_revive_uses -= 1
			alive = false
			add_flag("corpse")
			add_timer("revive", _revive_rounds, Callable(func(): _do_revive()))
		else:
			alive = false
	_update_hp_flags()
	# 2026-09-13：绕过 take_damage 的直接掉血也要通知 UI（真伤/自损/回合末地形扣血）。
	# 在 take_damage 内部结算时 _in_damage>0 → 交给 take_damage 统一发 damaged，避免重复飘字。
	if _in_damage <= 0 and hp < _hp_before:
		hp_drained.emit(self, _hp_before - hp)

func _do_revive() -> void:
	if not _corpse:
		return
	_corpse = false
	clear_flag("corpse")
	alive = true
	hp = max_hp * (_revive_hp_pct / 100.0)
	clear_statuses()
	_speed_mods = {}
	flags.clear()
	speed_buff = 0
	shield = 0

func _update_hp_flags() -> void:
	for rule in _hp_flags:
		var pct := int(rule.get("pct", 20))
		var f := str(rule.get("flag", ""))
		if max_hp <= 0:
			continue
		var on := hp * 100 <= max_hp * pct
		if on:
			add_flag(f)
		else:
			clear_flag(f)
		if rule.has("dmg_mult"):
			set_dmg_mult(float(rule["dmg_mult"]) if on else 1.0)

## ---------- 掉血特效通知（2026-09-13）----------
## 纯表现层订阅，不参与任何战斗计算；无订阅者时零开销。
## damaged：一次「挨打」的完整结算（含盾吸/减免/真掉血/击杀/闪避/免疫），由 take_damage 发出。
## hp_drained：绕过 take_damage 的直接掉血（真伤/自损/回合末地形扣血），只带实际掉了多少。
signal damaged(unit: BattleUnit, result: Dictionary)
signal hp_drained(unit: BattleUnit, amount: float)

## >0 表示当前正在 take_damage 内部结算（此时 lose_hp 不单独通知，避免重复飘字）
var _in_damage := 0

## 受击总入口：护盾先吸收 → 剩余按护甲减免 → 扣生命。
## 返回 { "absorbed", "reduced", "hp_lost", "killed", "missed", "reflected", "invuln" }
## info: { "attacker": BattleUnit, "element": "物理/火/…", "sure_hit": bool }（可省）
##
## 2026-09-13（掉血特效）：外面包一层，保证「一次挨打」只发一次 damaged 信号。
## 内部结算仍走 _take_damage_impl；它调用的 lose_hp 在这个计数 >0 时不会重复通知。
func take_damage(amount: float, info := {}) -> Dictionary:
	_in_damage += 1
	var result := _take_damage_impl(amount, info)
	_in_damage -= 1
	if amount > 0.0:
		damaged.emit(self, result)
	return result

func _take_damage_impl(amount: float, info := {}) -> Dictionary:
	var result := {
		"absorbed": 0, "reduced": 0, "hp_lost": 0, "killed": false,
		"missed": false, "reflected": 0, "invuln": false,
	}
	if not alive or amount <= 0:
		return result
	if has_flag("invuln"):
		result["invuln"] = true
		result["absorbed"] = amount
		return result
	var sure := bool(info.get("sure_hit", false))
	if not sure and evasion_pct > 0 and _randi_sync() % 100 < evasion_pct:
		result["missed"] = true
		return result
	var attacker := info.get("attacker", null) as BattleUnit if info.has("attacker") else null
	# 「你不再爱我」：受虞美人庇佑的单位被攻击 → 攻击者 +1 恐惧
	if attacker != null and attacker != self and has_flag("yumeiren_protect"):
		attacker.add_status("fear", 1)
		result["feared"] = true
	var element := str(info.get("element", ""))
	var rest := amount
	# 增伤按“攻击者对受击者主属性(self.element)”加成（辛克莱：机械目标+10%，敌我适用）
	var el_boost := 0
	if attacker != null:
		el_boost = attacker.element_bonus_of(element if self.element == "" else self.element)
	if el_boost > 0:
		amount = maxf(1.0, amount * float(100 + el_boost) / 100.0)
		rest = amount
	# 流血（设计表 Z4）：带流血单位被攻击时，按本次攻击伤害的 20%/30% 受额外真伤（无视甲盾）
	# 1 级 20% / 2 级 30% —— 设计表只有两档；持续时间与等级解耦，见 SkillEffects.apply_bleed
	var blv := status_stacks("bleed")
	if blv > 0:
		var bpct := 0.3 if blv >= 2 else 0.2
		var bx := amount * bpct
		if bx > 0:
			var b0 := hp
			lose_hp(bx)
			result["hp_lost"] += b0 - hp
			result["bleed_bonus"] = b0 - hp
			result["killed"] = not alive
# 0) 免伤百分比（全局/该属性；来自锻体/防守态/血狱等）
	var mit := int(_mitig.get("all", 0)) + int(_mitig.get(element, 0))
	if attacker != null:
		mit += int(_mitig_att.get(attacker.get_instance_id(), {}).get("pct", 0))
	if has_flag("免伤60"):
		mit += 60   # 锁血：本回合 60% 免伤
	if mit > 0:
		var cut: float = rest * float(mit) / 100.0
		cut = minf(cut, rest)
		rest -= cut
		result["reduced"] += cut
	# 1) 护盾吸收
	if shield > 0:
		var absorb: float = minf(shield, rest)
		shield -= absorb
		rest -= absorb
		result["absorbed"] = absorb
	# 2) 护甲减免（减固定值）
	var reduced: float = minf(armor, rest)
	rest -= reduced
	result["reduced"] += reduced
	# 2b) 地形乘算（2026-09-10）：作用于最终伤害——
	#     攻击方在【山地】造成伤害 ×1.3；受击方在【森林】受到伤害 ×0.8（乘法叠加）
	# 注：地形"是否启用"由战斗层决定（未启用地形不会被写进地形层），单位侧不做白名单判断。
	if rest > 0:
		var t_mult := 1.0
		if attacker != null and attacker != self:
			t_mult *= Terrain.damage_dealt_mult(attacker.terrain_id)
		t_mult *= Terrain.damage_taken_mult(terrain_id)
		if t_mult != 1.0:
			rest = maxf(0.0, rest * t_mult)   # 免伤可把小伤害压到 1 以下（真实 20% 减免）
	# 3) 剩余扣血
	if rest > 0:
		var before := hp
		lose_hp(rest)
		result["hp_lost"] = before - hp
	result["killed"] = not alive
	# 4) 反伤弹回攻击者（实际造成伤害按比例）
	if attacker != null and _reflect_pct > 0 and result["hp_lost"] > 0:
		var back: float = float(result["hp_lost"]) * (float(_reflect_pct) / 100.0)
		if back > 0:
			attacker.lose_hp(back)
			result["reflected"] = back
	# 4b) 重伤：受击后额外受 0.5×层 真伤（每回合末层数-1，见 tick_end）
	if result["hp_lost"] > 0 and status_stacks("heavy_wound") > 0:
		var extra: float = float(status_stacks("heavy_wound")) * 0.5
		var b3 := hp
		lose_hp(extra)
		result["hp_lost"] += b3 - hp
		result["killed"] = not alive
	# 5) 受击事件（锻体/防守状态机等监听）
	for ev in hit_events:
		var cb: Callable = ev
		if not cb.is_null():
			cb.call(attacker, element)
	# 6) 互助反击：虞美人/子体（非实体）被敌方攻击实际命中 → 攻击者受 1 点精神真伤
	if non_solid and attacker != null and attacker != self and attacker.team != team and attacker.alive:
		if result["hp_lost"] > 0 or result["absorbed"] > 0:
			attacker.lose_hp(1)
			result["countered"] = true
	return result

## ---------- 护盾（默认初始为 0；只由效果加） ----------
func add_shield(amount: float) -> void:
	if amount > 0:
		shield += amount
		if shield_cap > 0 and shield > shield_cap:
			shield = shield_cap

func remove_shield(amount: float) -> void:
	shield = maxf(0.0, shield - amount)

func clear_shield() -> void:
	shield = 0

func set_shield(amount: float) -> void:
	shield = maxf(0.0, amount)
	if shield_cap > 0 and shield > shield_cap:
		shield = shield_cap

## ---------- 护甲增减（支持上限封顶，如“架盾护甲+1，上限3”） ----------
func add_armor(amount: float, max_cap: float = 0.0) -> float:
	if amount <= 0:
		return 0
	var before := armor
	armor += amount
	if max_cap > 0 and armor > max_cap:
		armor = max_cap
	return armor - before

func remove_armor(amount: float) -> void:
	armor = maxf(0.0, armor - amount)

func set_armor(amount: float) -> void:
	armor = maxf(0.0, amount)

## 免伤栈：element "all" 或具体属性（火/物理…）；每来源调 add（自动按 cap 封顶）
func set_mitigation(element: String, pct: int) -> void:
	_mitig[element] = clampi(pct, 0, 100)

func add_mitigation(element: String, pct: int, cap: int = -1) -> void:
	var cur := int(_mitig.get(element, 0))
	var added := pct
	if cap > 0 and cur + added > cap:
		added = cap - cur
	if added > 0:
		_mitig[element] = cur + added

func mitigation_of(element: String) -> int:
	return int(_mitig.get("all", 0)) + int(_mitig.get(element, 0))

## 针对“某攻击者”的免伤（孤狼锻体：同一个人打你越多次越抗）
func add_mitigation_att(attacker: BattleUnit, pct: int, cap: int = -1) -> int:
	if attacker == null or pct <= 0:
		return 0
	var id := attacker.get_instance_id()
	var entry: Dictionary = _mitig_att.get(id, {"pct": 0, "who": attacker.name})
	var cur := int(entry["pct"])
	var added := pct
	if cap > 0 and cur + added > cap:
		added = cap - cur
	if added > 0:
		entry["pct"] = cur + added
		entry["who"] = attacker.name
		_mitig_att[id] = entry
	return added

func mitigation_att(attacker: BattleUnit) -> int:
	if attacker == null:
		return 0
	return int(_mitig_att.get(attacker.get_instance_id(), {}).get("pct", 0))

func reset_mitigation_att() -> void:
	_mitig_att = {}

func set_reflect(pct: int) -> void:
	_reflect_pct = clampi(pct, 0, 100)

func set_evasion(pct: int) -> void:
	evasion_pct = clampi(pct, 0, 100)

func set_dmg_mult(v: float) -> void:
	dmg_mult = v

## 控制类负面统一入口：【完全燃烧】状态下 40% 概率免疫；返回日志（空串=已正常施加）
func try_control(flag: String) -> String:
	if has_status("full_burn") and _randi_sync() % 100 < 40:
		return "；%s【完全燃烧】免疫了控制效果" % name
	add_flag(flag)
	return ""

func lose_sanity(amount: float) -> float:
	sanity = clampf(sanity - amount, -200.0, sanity_cap)
	if sanity < 0:
		add_flag("sanity_break")   # 使用技能把理智打成负 → 下回合失控（随机放技，由战斗层）
	return sanity

func gain_sanity(amount: float) -> float:
	sanity = clampf(sanity + amount, -200.0, sanity_cap)
	return sanity

func mark_skill_lost(skill_id: String) -> void:
	_lost_skills[skill_id] = true

func is_skill_lost(skill_id: String) -> bool:
	return _lost_skills.has(skill_id)

## 限时锁技（掠夺用）：rounds 个自身回合内无法使用该技，到期自动解除
func lock_skill(skill_id: String, rounds: int = 1) -> void:
	if skill_id == "":
		return
	_lost_skills[skill_id] = true
	remove_timer("skill_lock:" + skill_id)
	add_timer("skill_lock:" + skill_id, maxi(1, rounds), Callable(self, "_unlock_skill").bind(skill_id))

func _unlock_skill(skill_id: String) -> void:
	_lost_skills.erase(skill_id)

## 掠夺登记：夺得的技能在下个回合开始时替换第 slot 槽（默认 1 槽）
func set_stolen_pending(skill_id: String, slot: int = 1) -> void:
	if skill_id == "":
		return
	_stolen_pending = skill_id
	_stolen_slot = clampi(slot, 1, 4)

## 回合开始：把待生效的掠夺技装进技能槽（原技能暂存，STOLEN_ROUNDS 个自身回合后归还）
func _apply_stolen_pending() -> String:
	if _stolen_pending == "":
		return ""
	var sid := _stolen_pending
	var slot := _stolen_slot if _stolen_slot >= 1 else 1
	_stolen_pending = ""
	if slot > actives.size():
		return ""
	if _stolen_backup == null:
		_stolen_backup = actives[slot - 1]   # 暂存原技能，到期归还
	actives[slot - 1] = _make_skill(sid)
	stolen_skill_id = sid
	remove_timer("stolen_expire")
	add_timer("stolen_expire", STOLEN_ROUNDS, Callable(self, "_expire_stolen"))
	return "；%s 掌握了掠夺来的【%s】（第 %d 技能槽，可用 %d 回合）" % [name, actives[slot - 1].display_name, slot, STOLEN_ROUNDS]

## 掠夺时效结束：归还原技能
func _expire_stolen() -> String:
	var out := ""
	if _stolen_backup != null and _stolen_slot >= 1 and _stolen_slot <= actives.size():
		actives[_stolen_slot - 1] = _stolen_backup
		out = "；%s 的掠夺时效结束，第 %d 技能槽恢复为【%s】" % [name, _stolen_slot, _stolen_backup.display_name]
	_stolen_backup = null
	stolen_skill_id = ""
	return out

## ---------- 状态/印记（层数制：bleed 流血 / burn 灼烧 / wound 创伤…） ----------
## 层数 = 等级（“流血2级”=bleed 2 层）。tick 规则见 SkillEffects.tick_* 系列。
var statuses: Dictionary = {}     # id -> 层数

func add_status(id: String, amount: int) -> void:
	statuses[id] = maxi(0, int(statuses.get(id, 0)) + amount)

func set_status(id: String, amount: int) -> void:
	if amount <= 0:
		statuses.erase(id)
	else:
		statuses[id] = amount

func status_stacks(id: String) -> int:
	return int(statuses.get(id, 0))

func has_status(id: String) -> bool:
	return statuses.has(id)

func clear_statuses() -> void:
	statuses.clear()
	# 带“持续回合”计时的状态连计时器一起清，避免残留计时器之后触发无意义回调
	for tid in ["bleed_end", "burn_end", "freeze_end"]:
		remove_timer(tid)

func to_status_summary() -> String:
	if statuses.is_empty():
		return ""
	var parts: Array[String] = []
	for k in statuses:
		var sid := str(k)
		parts.append(SkillEffects.status_label(sid, int(statuses[k]), SkillEffects.status_rounds(self, sid)))
	return " 状态[%s]" % "、".join(parts)

## ---------- 能量 ----------
func add_energy(amount: float) -> float:
	if amount < 0:
		return 0
	var before := energy
	if max_energy < 0:
		energy += amount
	else:
		energy = clampf(energy + amount, 0.0, max_energy)
	return energy - before

func spend_energy(amount: float) -> bool:
	if amount < 0 or energy < amount:
		return false
	energy -= amount
	return true

## 统计"敌方"（不同阵营）单位的 血量+护盾 总和，用于判断某次技能是否造成了伤害
func _foe_health_sum(ctx: Dictionary) -> float:
	var total := 0.0
	var arr = ctx.get("targets", [])
	if arr == null:
		return 0.0
	for t in arr:
		if t == null or t == self:
			continue
		if t is BattleUnit and t.team != team and t.alive:
			total += maxf(0.0, t.hp) + maxf(0.0, t.shield)
	return total

## ---------- 技能 ----------
## 槽位约定：主动技能一律按 1..4（与 use_active 一致）
func get_skill(i: int) -> Skill:
	return actives[i - 1] if i >= 1 and i <= actives.size() else null

## 释放主动/终极技能成功时发出（UI 层据此播放角色骨骼动作动画）
signal skill_cast(slot: int)

## 使用第 i 个主动技能（1..4 + 5=普攻）
func use_active(i: int, ctx: Dictionary) -> String:
	if i < 1 or i > 5:
		return "技能槽位无效（1-4）"
	var sk := actives[i - 1]
	if sk == null:
		return "%s 第 %d 个技能未配置" % [name, i]
	# 行动门禁：被掠夺/禁用
	if is_skill_lost(sk.id):
		return "%s 的【%s】被掠夺/禁用，无法使用" % [name, sk.display_name]
	# 行动门禁：魅惑（本回合无法造成伤害）
	if has_flag("no_damage"):
		return "%s 本回合被魅惑，无法造成伤害" % name
	# 行动门禁：无法使用技能（束缚之灵沉默）
	if has_flag("no_skill"):
		return "%s 被束缚之灵沉默，本回合无法使用技能" % name
	# 行动门禁：大招被封（伸缩拳远击嘲讽）
	if i == 4 and has_flag("no_ult"):
		return "%s 大招被封印，无法使用" % name
	# 行动门禁：失明（每层失明 20% 施放打空；战斗层可细化）
	var blind_layers := status_stacks("blind")
	if blind_layers > 0 and _randf_sync() < float(blind_layers) * 0.2:
		statuses["blind"] = maxi(0, blind_layers - 1)
		return "%s 失明打空（失明层 -1）" % name
	# 行动前结算自身“流血”（移动/施放技能时触发），流血可能致死
	var action_log := SkillEffects.tick_action_statuses(self)
	if not alive:
		return action_log + "%s 因流血倒下了" % name
	var ctx2: Dictionary = ctx.duplicate()
	ctx2["slot"] = i      # 效果函数可据此定位自身技能槽（如掠夺替换槽位）
	# 记录敌方血量+护盾，用于判断本次是否真的"打出了伤害"
	var foe_before := _foe_health_sum(ctx)
	var out := sk.activate(self, ctx2)
	# 释放成功（非校验失败）→ 通知 UI 播放动作动画
	if not (out.begins_with("这不是") or out.begins_with("本局已用尽") or out.begins_with("还在冷却中") or out.begins_with("能量不足")):
		# 仅"对敌方造成伤害"的技能才播动作动画：
		# 增益/护盾/位移/召唤类（如龙王"化晶为铠"）不触发
		if _foe_health_sum(ctx) < foe_before:
			skill_cast.emit(i)
	if action_log != "":
		out = action_log + "；" + out
	return out

## 战斗层在合适时机调用：触发被动
func trigger_passive(ctx: Dictionary) -> String:
	if passive != null:
		return passive.trigger_passive(self, ctx)
	return ""

## 回合结束清理（战斗层调用）。返回产生的结算文本（如回合末吸血/流血衰减），无则空串。
func end_turn() -> String:
	var out := ""
	for s in actives:
		if s != null:
			s.tick_cooldown()
	if passive != null:
		passive.tick_cooldown()
	# 结算“回合末”待发放资源
	for k in _pending_grant:
		grant_counter(str(k), int(_pending_grant[k]))
	_pending_grant.clear()
	out += _settle_share_drain()
	out += SkillEffects.tick_end_of_turn_statuses(self)
	out += _apply_tefx()
	out += _tick_timers()
	out += _terrain_end_turn()
	return out

## 地形·回合末结算（2026-09-10 用户设计）
##   沙地：损失 0.5 点生命（直接扣血，不经过护甲/护盾）
##   水域：损失 1 点能量
## 注：地形"是否启用"由战斗层决定（未启用地形不会被写进地形层）。
##     龙的 water_immune 使其豁免水域扣能量。
func _terrain_end_turn() -> String:
	if terrain_id <= 0 or not alive:
		return ""
	if water_immune and terrain_id == Terrain.WATER:
		return ""
	var out := ""
	var hp_loss := Terrain.end_turn_hp_loss(terrain_id)
	if hp_loss > 0.0:
		var before := hp
		lose_hp(hp_loss)
		var real := before - hp
		if real > 0.0:
			out += "%s 处于【%s】，回合末损失 %.1f 生命（现 %.1f）\n" % [
				name, Terrain.name_of(terrain_id), real, hp]
	var en_loss := Terrain.end_turn_energy_loss(terrain_id)
	if en_loss > 0:
		var e0 := energy
		energy = maxf(0.0, energy - float(en_loss))
		if e0 != energy:
			out += "%s 处于【%s】，回合末损失 %d 点能量（现 %.1f）\n" % [
				name, Terrain.name_of(terrain_id), en_loss, energy]
	return out

## ---------- 一技能类“分担/回合末吸血”登记（战斗层时序） ----------
func begin_share_round(targets: Array) -> void:
	_share_active = true
	_share_targets = []
	for t in targets:
		var tu := t as BattleUnit
		if tu != null:
			_share_targets.append(tu)

## 回合末：吸取处于“失神”的登记目标当前生命 30%
func _settle_share_drain() -> String:
	if not _share_active:
		return ""
	_share_active = false
	var list := _share_targets
	_share_targets = []
	var out := ""
	for t in list:
		var tu := t as BattleUnit
		if tu == null or not tu.has_flag("失神") or not tu.alive:
			continue
		var loss: float = tu.hp * 0.3
		if loss <= 0:
			continue
		tu.lose_hp(loss)
		var got := heal(loss)
		out += "%s 回合末吸取 %s：流失 %d 生命，邪神回 %d 血" % [name, tu.name, loss, got]
	return out

## 回合开始（战斗层调用）：被动资源 per_turn 自动增长（支持 start_round 延迟生效）；
## 返回产生的结算文本（如灼烧伤害）
func on_turn_start() -> String:
	var out := ""
	_rounds += 1
	spread_used = 0
	out += _apply_stolen_pending()
	for k in _counters_cfg:
		var cfg: Dictionary = _counters_cfg[k]
		if int(cfg.get("per_turn", 0)) <= 0:
			continue
		if _rounds < int(cfg.get("start_round", 1)):
			continue
		grant_counter(str(k), int(cfg["per_turn"]))
	out += SkillEffects.tick_start_of_turn_statuses(self)
	out += _apply_tsfx()
	return out

## ---------- 计数资源池（叠层/元晶等） ----------
func counter(name: String) -> int:
	return int(counters.get(name, 0))

## 增加：超过 max 自动截断（max<=0 不限制）
func grant_counter(name: String, amount: int) -> void:
	if amount <= 0:
		return
	var cur := counter(name) + amount
	var cap := int(_counters_cfg.get(name, {}).get("max", 0))
	if cap > 0 and cur > cap:
		cur = cap
	counters[name] = cur
	_refresh_layer(name)

## 消耗：不足返回 false
func consume_counter(name: String, amount: int) -> bool:
	if amount < 0 or counter(name) < amount:
		return false
	counters[name] = counter(name) - amount
	_refresh_layer(name)
	return true

func set_counter(name: String, value: int) -> void:
	counters[name] = maxi(0, value)
	_refresh_layer(name)

## ---- 层数规则 API（任意英雄可在运行期注册，或由 def["layer_rules"] 自动注册）----
## 层数 >= threshold 时自动置 flag，降下来自动清除
func watch_layer_flag(layer: String, threshold: int, flag: String) -> void:
	if threshold <= 0:
		return
	_layer_flags[layer] = {"threshold": threshold, "flag": flag}

## 每有 1 层该资源，速度 -per（自动维护 speed_mod）
func watch_layer_speed(layer: String, per: int) -> void:
	if per <= 0:
		return
	_layer_speeds[layer] = per
	_refresh_layer(layer)

func _refresh_layer(layer: String) -> void:
	if not counters.has(layer):
		return
	var cnt := counter(layer)
	if _layer_speeds.has(layer):
		set_speed_mod_src("layer:" + layer, -int(_layer_speeds[layer]) * cnt)
	if _layer_flags.has(layer):
		var f: Dictionary = _layer_flags[layer]
		var flag := str(f["flag"])
		if cnt >= int(f["threshold"]):
			add_flag(flag)
		else:
			clear_flag(flag)

## 声明“本回合末发放”（如技能写“回合末额外 +1”）
func grant_end_of_turn(name: String, amount: int) -> void:
	_pending_grant[name] = int(_pending_grant.get(name, 0)) + amount

func to_summary() -> String:
	var tag := name
	if element != "":
		tag = "%s〔%s〕" % [name, element]
	return "%s  HP %d/%d  能量 %d/%d  盾 %d  甲 %d  速 %d" % [tag, hp, max_hp, energy, max_energy, shield, armor, speed]

## 状态图标数据（供 UI 在棋子上渲染）：
##   [{"cn": 中文名, "lv": 层数/等级, "id": 状态id, "rounds": 剩余回合, "label": UI 文本, "badge_num": 徽章数字}]
## 注：label / badge_num 由 SkillEffects 统一生成 —— 各界面**不要再各写一份拼接**（2026-09-18）
func status_icons() -> Array:
	var out: Array = []
	for k in statuses:
		var lv := int(statuses[k])
		if lv <= 0:
			continue
		var sid := str(k)
		var rds := SkillEffects.status_rounds(self, sid)
		out.append({
			"cn": SkillEffects.status_cn(sid), "lv": lv, "id": sid, "rounds": rds,
			"label": SkillEffects.status_label(sid, lv, rds),
			"badge_num": SkillEffects.status_badge_num(sid, lv, rds),
		})
	# flag 类状态（非层数）也上徽章：眩晕 → 头顶"晕"
	if has_flag("stun"):
		out.append({"cn": "眩晕", "lv": 0, "id": "stun", "rounds": 0, "label": "眩晕", "badge_num": 0})
	return out

## 技能槽 id 列表（快照用；""=空槽）
func _actives_ids() -> Array:
	var ids: Array = []
	for sk in actives:
		ids.append(sk.id if sk != null else "")
	return ids

## 按快照 id 恢复技能槽（id 一致的槽保留原对象以延续冷却）
func _restore_actives(ids: Array) -> void:
	if ids.size() != actives.size():
		return
	for i in range(actives.size()):
		var sid := str(ids[i])
		if actives[i] == null or actives[i].id != sid:
			actives[i] = _make_skill(sid) if sid != "" else null

## =============== 前瞻推演 · 快照 / 回滚 ===============
## 供战斗层做“多步推演选最优”用：记录当前全部会随战斗变化的字段，
## 推演模拟后 restore() 还原 —— 同一实例原地存取，Timer 的 Callable 直接复用。
func snapshot() -> Dictionary:
	var s := {
		"hp": hp, "energy": energy, "shield": shield, "armor": armor,
		"alive": alive, "cell": cell, "speed_buff": speed_buff,
		"_speed_mods": _speed_mods.duplicate(),
		"counters": counters.duplicate(),
		"statuses": statuses.duplicate(),
		"flags": flags.duplicate(),
		"_timers": _timers.duplicate(),
		"dmg_mult": dmg_mult,
		"evasion_pct": evasion_pct,
		"_reflect_pct": _reflect_pct,
		"_mitig": _mitig.duplicate(),
		"_mitig_att": _mitig_att.duplicate(),
		"dmg_slot": _dmg_slot.duplicate(),
		"sanity": sanity,
		"stolen_skill_id": stolen_skill_id,
		"actives_ids": _actives_ids(),
		"_lost_skills": _lost_skills.duplicate(),
		"_stolen_pending": _stolen_pending,
		"_stolen_slot": _stolen_slot,
		"_stolen_backup_id": (_stolen_backup.id if _stolen_backup != null else ""),
		"_corpse": _corpse,
		"_revive_uses": _revive_uses,
		"_share_active": _share_active,
		"_share_targets": _share_targets.duplicate(),
		"_passive_cd_round": _passive_cd_round,
		"cds": [],
	}
	if passive != null:
		s["cds"].append(passive.current_cd)
	else:
		s["cds"].append(0)
	for sk in actives:
		s["cds"].append(sk.current_cd if sk != null else 0)
	return s

func restore(s: Dictionary) -> void:
	hp = int(s.get("hp", hp))
	energy = int(s.get("energy", energy))
	shield = int(s.get("shield", shield))
	armor = int(s.get("armor", armor))
	alive = bool(s.get("alive", alive))
	cell = s.get("cell", cell) as Vector2i
	speed_buff = int(s.get("speed_buff", speed_buff))
	_speed_mods = (s.get("_speed_mods", {}) as Dictionary).duplicate()
	counters = (s.get("counters", {}) as Dictionary).duplicate()
	statuses = (s.get("statuses", {}) as Dictionary).duplicate()
	flags = (s.get("flags", {}) as Dictionary).duplicate()
	_timers = (s.get("_timers", {}) as Dictionary).duplicate()
	dmg_mult = float(s.get("dmg_mult", dmg_mult))
	evasion_pct = int(s.get("evasion_pct", evasion_pct))
	_reflect_pct = int(s.get("_reflect_pct", _reflect_pct))
	_mitig = (s.get("_mitig", {}) as Dictionary).duplicate()
	_mitig_att = (s.get("_mitig_att", {}) as Dictionary).duplicate()
	_dmg_slot = (s.get("dmg_slot", {}) as Dictionary).duplicate()
	sanity = int(s.get("sanity", sanity))
	stolen_skill_id = str(s.get("stolen_skill_id", stolen_skill_id))
	_restore_actives(s.get("actives_ids", []))
	_lost_skills = (s.get("_lost_skills", {}) as Dictionary).duplicate()
	_stolen_pending = str(s.get("_stolen_pending", ""))
	_stolen_slot = int(s.get("_stolen_slot", _stolen_slot))
	var bkid := str(s.get("_stolen_backup_id", ""))
	_stolen_backup = _make_skill(bkid) if bkid != "" else null
	_corpse = bool(s.get("_corpse", _corpse))
	_revive_uses = int(s.get("_revive_uses", _revive_uses))
	_share_active = bool(s.get("_share_active", _share_active))
	_share_targets = (s.get("_share_targets", []) as Array).duplicate()
	_passive_cd_round = int(s.get("_passive_cd_round", _passive_cd_round))
	var cds: Array = s.get("cds", [])
	var ci := 0
	if passive != null and cds.size() > 0:
		passive.current_cd = int(cds[ci]); ci += 1
	elif cds.size() > 0:
		ci += 1
	for sk in actives:
		if ci < cds.size():
			if sk != null:
				sk.current_cd = int(cds[ci])
			ci += 1
