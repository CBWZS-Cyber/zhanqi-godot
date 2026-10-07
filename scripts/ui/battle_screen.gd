class_name BattleScreen
extends Control
## 对局界面公共基类（2026-09-30 抽出）。
##
## 背景：duel.gd（1V1）与 team_duel.gd（4V4）原先各自复制了一份
## 「阵营判定 / 输入门禁 / 三个操作入口」共 5 个函数。其中
## `_my_team` / `_can_input` / `_op_move` / `_op_done` 逐字相同，
## `_op_cast` 只差 `human_cast()` 的调用参数 —— 而那个差异是有原因的：
## 三个战斗模式的 `human_cast` 签名本就不同（各子类自己实现，不是覆写关系）：
##
##   - Battle      : human_cast(slot, enemy, landing)
##   - BattleTeam  : human_cast(slot, enemy, landing, extra_targets)
##   - BattleStory : human_cast(slot, target, extra_targets)
##
## 所以把签名差异收进一个 `_cast_via()` 覆写点，其余逻辑留在基类。
##
## 子类职责：
##   - 必须覆写 `_cast_via()`（默认实现返回失败串，避免基类静态调不到方法）
##   - 必须自行赋值 `_battle`、`_hint`、`_over_lab`
##   - `_phase` 初值由基类给 "select"，各模式的 `_ready()` 会显式改写

const _NP := preload("res://scripts/net/net_protocol.gd")

var _phase := "select"           # select / play / over
var _battle: BattleBase = null   # 各模式注入 Battle / BattleTeam / BattleStory
var _focus: BattleUnit = null
var _cast_slot := 0
var _multi_targets: Array = []   # 多目标技已点选的目标（1V1 恒为空）
var _hint: Label
var _over_lab: Label
var _autonet_role := ""


## 本机在联机中的阵营：host = 0（红） / joiner = 1（蓝）
func _my_team() -> int:
	return 0 if Global.net_is_host else 1


## 当前是否允许本机输入（单机恒允许；联机时必须是自己的回合）
func _can_input() -> bool:
	if _battle == null or _phase != "play" or not _battle.waiting():
		return false
	if Global.net_mode and _battle.current().team != _my_team():
		return false
	return true


## 各模式 human_cast 的签名差异唯一收口处（子类覆写）。
func _cast_via(_slot: int, _enemy: BattleUnit, _landing: Vector2i) -> String:
	return "!该模式未实现 _cast_via"


## 本方移动 → 本地执行 + 成功才广播（失败仅本地提示，与单机一致）
func _op_move(cell: Vector2i) -> String:
	var idx := _battle.units.find(_battle.current())
	var r: String = _battle.human_move(cell)
	if r.begins_with("!"):
		Sfx.play("error")
	else:
		Sfx.play("footstep")
	if not r.begins_with("!") and Global.net_mode:
		Net.send_cmd(_NP.make_move(idx, cell))
	return r


## 本方释放技能 → 本地执行 + 按结果播反馈音 + 成功才广播
func _op_cast(slot: int, enemy: BattleUnit = null, landing := Vector2i(-1, -1)) -> String:
	var idx := _battle.units.find(_battle.current())
	var me_u: BattleUnit = _battle.current()
	var old_cell: Vector2i = me_u.cell if me_u != null else Vector2i(-9, -9)
	var was_dash: bool = me_u != null and _battle.is_charge(me_u, slot)
	var r: String = _cast_via(slot, enemy, landing)
	if r.begins_with("!"):
		Sfx.play("error")
	elif me_u != null:
		if me_u.cell != old_cell:
			Sfx.play("dash" if was_dash else "teleport")
		elif _battle.land_aoe(me_u, slot):
			Sfx.play("explosion")
		elif _battle.self_skill(me_u, slot):
			Sfx.play("powerup")
		else:
			Sfx.play("hit")
	if not r.begins_with("!") and Global.net_mode:
		Net.send_cmd(_NP.make_cast(idx, slot, enemy, _battle, landing))
	return r


func _op_done() -> void:
	var idx := _battle.units.find(_battle.current())
	_battle.human_done()
	if Global.net_mode:
		Net.send_cmd(_NP.make_done(idx))
