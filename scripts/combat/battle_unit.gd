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
var max_hp: int = 100
var hp: int = 100
var max_energy: int = 50
var energy: int = 50
var shield: int = 0
var armor: int = 0
var speed: int = 5          # 基础速度（行动先后由战斗层按 effective_speed 排序，大者先动）
var speed_buff: int = 0     # 速度加成（增益，如“以命相搏”+200）
var _speed_mods := {}       # 速度修正多来源：来源 -> delta（可叠加求和，如 污染-15 + 断流-50）
var team: int = 0           # 阵营：0 红方 / 1 蓝方（摆放时由战斗层设置；目标过滤用）
var alive: bool = true
var cell := Vector2i.ZERO       # 单位所在棋盘格（由战斗层摆放时设置，距离判定用）
var flags: Dictionary = {}      # 状态标志："失神"/"被支配"/"永久支配"/"本回合均摊"…（战斗层/效果读写）

# ---- 通用计数资源池（叠层/攒资源，如“元晶”/“污染”）----
# counters_cfg : name -> {"start":n,"per_turn":n(可选),"start_round":n(可选,从第n回合起自动加,默认1),"max":n(0=不限)}
# 运行时值存 counters；每回合开始自动 +per_turn；end_turn 结算 pending 加值
var counters: Dictionary = {}              # name -> 当前值
var _counters_cfg: Dictionary = {}         # name -> 配置
var _pending_grant: Dictionary = {}        # end_turn 待发放
var _rounds: int = 0                       # 已进行的自身回合数（on_turn_start 计数，资源延迟生效用）

# ---- 层数规则（声明式，def["layer_rules"] 驱动，供所有“叠层型”英雄复用）----
# 例：{ "污染": { "speed_per_layer": 15, "flag_threshold": {"失神": 3} } }
#   speed_per_layer : 每层使该单位速度 -N（自动维护 speed_mod）
#   flag_threshold  : 层数 >= 阈值时自动置状态 flag，层降后自动清除
var _layer_flags := {}                     # layer -> {threshold, flag}
var _layer_speeds := {}                    # layer -> per_layer_speed_cost
var _share_active := false                 # 一技能登记：本回合伤害分担 + 回合末吸血
var _share_targets: Array = []
var passive: Skill = null
var actives: Array[Skill] = []     # 长度 = 4（按 hero_defs 的 actives 顺序）
var _passive_cd_round: int = 0     # 被动触发节流（可选，战斗层用）

func _init(def: Dictionary) -> void:
	def_id = str(def.get("id", ""))
	element = str(def.get("element", ""))
	name = str(def.get("name", "单位"))
	max_hp = int(def.get("hp", 100))
	hp = max_hp
	max_energy = int(def.get("energy_max", int(def.get("energy", 50))))
	energy = int(def.get("energy", max_energy))
	shield = 0                                  # 初始一律 0，见文件头约定
	armor = int(def.get("armor", 0))
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
	s.effect = SkillEffects.EFFECTS.get(sid, Callable(SkillEffects, "effect_stub"))
	return s

## ---------- 生命 ----------
func effective_speed() -> int:
	var total := speed + speed_buff
	for src in _speed_mods:
		total += int(_speed_mods[src])
	return maxi(1, total)

## 速度修正（多来源求和）：src 同名覆盖，不同名叠加
func set_speed_mod_src(src: String, delta: int) -> void:
	_speed_mods[src] = delta

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

func add_slot_damage(slot: int, amount: int, cap: int = -1) -> int:
	if amount <= 0:
		return 0
	var cur := int(_dmg_slot.get(slot, 0))
	var added := amount
	if cap > 0 and cur + added > cap:
		added = cap - cur
	if added > 0:
		_dmg_slot[slot] = cur + added
	return added

func slot_damage(slot: int, base: int) -> int:
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

func heal(amount: int) -> int:
	if not alive or amount <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before

## 直接扣血（已算护盾吸收后）；由 take_damage 调用，也可用于无视护盾的伤害
func lose_hp(amount: int) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		alive = false

## 受击总入口：护盾先吸收 → 剩余按护甲减免 → 扣生命。
## 返回 { "absorbed": 盾吸收量, "reduced": 护甲减免量, "hp_lost": 最终掉血, "killed": bool }
func take_damage(amount: int, _dmg_type := "physical") -> Dictionary:
	var result := {
		"absorbed": 0, "reduced": 0, "hp_lost": 0, "killed": false,
	}
	if not alive or amount <= 0:
		return result
	var rest := amount
	# 1) 护盾吸收
	if shield > 0:
		var absorb := mini(shield, rest)
		shield -= absorb
		rest -= absorb
		result["absorbed"] = absorb
	# 2) 护甲减免（占位公式：减固定值；正式公式待定义）
	var reduced := mini(armor, rest)
	rest -= reduced
	result["reduced"] = reduced
	# 3) 剩余扣血
	if rest > 0:
		var before := hp
		lose_hp(rest)
		result["hp_lost"] = before - hp
	result["killed"] = not alive
	return result

## ---------- 护盾（默认初始为 0；只由效果加） ----------
func add_shield(amount: int) -> void:
	if amount > 0:
		shield += amount

func remove_shield(amount: int) -> void:
	shield = maxi(0, shield - amount)

func clear_shield() -> void:
	shield = 0

func set_shield(amount: int) -> void:
	shield = maxi(0, amount)

## ---------- 护甲增减（支持上限封顶，如“架盾护甲+1，上限3”） ----------
func add_armor(amount: int, max_cap: int = 0) -> int:
	if amount <= 0:
		return 0
	var before := armor
	armor += amount
	if max_cap > 0 and armor > max_cap:
		armor = max_cap
	return armor - before

func remove_armor(amount: int) -> void:
	armor = maxi(0, armor - amount)

func set_armor(amount: int) -> void:
	armor = maxi(0, amount)

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

func to_status_summary() -> String:
	if statuses.is_empty():
		return ""
	var parts: Array[String] = []
	for k in statuses:
		var cn := SkillEffects.status_cn(str(k))
		parts.append("%s%d" % [cn, int(statuses[k])])
	return " 状态[%s]" % "、".join(parts)

## ---------- 能量 ----------
func add_energy(amount: int) -> int:
	var before := energy
	energy = clampi(energy + amount, 0, max_energy)
	return energy - before

func spend_energy(amount: int) -> bool:
	if amount < 0 or energy < amount:
		return false
	energy -= amount
	return true

## ---------- 技能 ----------
## 槽位约定：主动技能一律按 1..4（与 use_active 一致）
func get_skill(i: int) -> Skill:
	return actives[i - 1] if i >= 1 and i <= actives.size() else null

## 使用第 i 个主动技能（1..4）
func use_active(i: int, ctx: Dictionary) -> String:
	if i < 1 or i > 4:
		return "技能槽位无效（1-4）"
	var sk := actives[i - 1]
	if sk == null:
		return "%s 第 %d 个技能未配置" % [name, i]
	# 行动前结算自身“流血”（移动/施放技能时触发），流血可能致死
	var action_log := SkillEffects.tick_action_statuses(self)
	if not alive:
		return action_log + "%s 因流血倒下了" % name
	var out := sk.activate(self, ctx)
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
	out += _tick_timers()
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
		var loss := ceili(float(tu.hp) * 0.3)
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
	for k in _counters_cfg:
		var cfg: Dictionary = _counters_cfg[k]
		if int(cfg.get("per_turn", 0)) <= 0:
			continue
		if _rounds < int(cfg.get("start_round", 1)):
			continue
		grant_counter(str(k), int(cfg["per_turn"]))
	out += SkillEffects.tick_start_of_turn_statuses(self)
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
