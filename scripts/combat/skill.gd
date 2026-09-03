class_name Skill
extends RefCounted
## 技能运行时对象（剧情模式）。
## 数据来源：SkillEffects.DATA[id]（元信息）+ SkillEffects.EFFECTS[id]（效果函数）。
## 主动技能：use_skill 前校验 冷却/能量，消耗 energy 后执行效果；效果函数需返回描述文本（进战斗日志用）。

var id: String = ""
var display_name: String = "技能"
var kind: String = "active"        # "passive" | "active" | "ultimate"
var element: String = ""          # 元素：火/冰/雷/风/土/光/暗/物理…（空=无属性）
var energy_cost: int = 0               # 主动技能能量消耗
var desc: String = ""
var cooldown: int = 0              # 使用后冷却回合数（被动 0）
var current_cd: int = 0            # 剩余冷却（回合制，由战斗层 tick 减 1）
var effect: Callable               # fn(user: BattleUnit, ctx: Dictionary) -> String

## 由战斗层在“回合开始/相应时机”把被动接上：fn(user: BattleUnit, ctx) -> String
func trigger_passive(user: BattleUnit, ctx: Dictionary) -> String:
	if kind != "passive" or effect.is_null():
		return ""
	return String(effect.call(user, ctx))

## 主动/终极技能：校验冷却/能量 → 扣能量 → 上冷却 → 执行效果。
## ctx 约定（由战斗层传入）：{ "targets": [BattleUnit...], "battle": 任意战斗上下文, ... }
func activate(user: BattleUnit, ctx: Dictionary) -> String:
	if kind != "active" and kind != "ultimate":
		return "这不是主动技能"
	if current_cd > 0:
		return "%s 还在冷却中（%d 回合）" % [display_name, current_cd]
	if user.energy < energy_cost:
		return "能量不足，无法释放 %s（需要 %d）" % [display_name, energy_cost]
	user.spend_energy(energy_cost)
	current_cd = cooldown
	if effect.is_null():
		return "%s 释放了 %s（效果待填写）" % [user.name, display_name]
	var log := String(effect.call(user, ctx))
	return log if log != "" else "%s 释放了 %s" % [user.name, display_name]

## 冷却推进（战斗层每回合结束调用）
func tick_cooldown() -> void:
	if current_cd > 0:
		current_cd -= 1

func to_summary() -> String:
	var head := "[%s] %s" % [kind, display_name]
	if element != "":
		head = "[%s·%s] %s" % [kind, element, display_name]
	var parts: Array[String] = [head]
	if kind == "active" or kind == "ultimate":
		parts.append("耗能 %d" % energy_cost)
		if cooldown > 0:
			parts.append("冷却 %d 回合" % cooldown)
	parts.append(desc)
	return " ".join(parts)
