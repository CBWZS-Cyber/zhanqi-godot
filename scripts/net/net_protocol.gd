class_name NetProtocol
extends RefCounted
## 联机指令协议（阶段2）：人类操作 ↔ JSON 指令包 编码/解码/镜像重放。
##
## 同步模型（指令重放式）：
##   开局双方各自构建同一 battle（同英雄/同种子），之后所有"人类操作"
##   以指令包形式广播，对方在镜像 battle 上重放 → 引擎确定性保证状态一致。
##
## 指令格式（JSON）：
##   {"op":"move",  "actor":<units下标>, "cell":[x,y]}
##   {"op":"cast",  "actor":<units下标>, "slot":<1-4>, "target":<units下标或-1>, "landing":[x,y](-1,-1=默认)}
##   {"op":"done",  "actor":<units下标>}
##
## 一致性护栏：重放时校验 battle.current() == units[actor]，不一致=状态漂移 → 返回错误（上层应断线判负）。

const OP_MOVE := "move"
const OP_CAST := "cast"
const OP_DONE := "done"
const OP_PICK := "pick"   # 联机选英雄：{"op":"pick","side":0/1,"hero":"id"}

## ---------- 构造 ----------
static func make_move(actor_idx: int, cell: Vector2i) -> Dictionary:
	return {"op": OP_MOVE, "actor": actor_idx, "cell": [cell.x, cell.y]}

static func make_cast(actor_idx: int, slot: int, enemy: BattleUnit, battle, landing := Vector2i(-1, -1)) -> Dictionary:
	var t := -1
	if enemy != null:
		t = battle.units.find(enemy)
	return {"op": OP_CAST, "actor": actor_idx, "slot": slot, "target": t, "landing": [landing.x, landing.y]}

static func make_done(actor_idx: int) -> Dictionary:
	return {"op": OP_DONE, "actor": actor_idx}

static func make_pick(side: int, hero_id: String, seq := -1) -> Dictionary:
	var cmd := {"op": OP_PICK, "side": side, "hero": hero_id}
	if seq >= 0:
		cmd["seq"] = seq   # 4V4 选秀：该次选择前的全局已选数（接收端校验防错位）
	return cmd

## ---------- 编解码 ----------
static func encode(cmd: Dictionary) -> String:
	return JSON.stringify(cmd)

## 返回 {} 表示解析失败
static func decode(s: String) -> Dictionary:
	var p = JSON.parse_string(s)
	if typeof(p) != TYPE_DICTIONARY:
		return {}
	var cmd: Dictionary = p
	var op := str(cmd.get("op", ""))
	if op == OP_PICK:   # 选英雄：无 actor，side+hero
		if int(cmd.get("side", -1)) < 0 or str(cmd.get("hero", "")) == "":
			return {}
		return cmd
	if op != OP_MOVE and op != OP_CAST and op != OP_DONE:
		return {}
	if not cmd.has("actor") or int(cmd.get("actor", -1)) < 0:
		return {}
	if op == OP_MOVE and not (cmd.get("cell") is Array):
		return {}
	if op == OP_CAST:
		if int(cmd.get("slot", 0)) < 1 or int(cmd.get("slot", 0)) > 4:
			return {}
		if not (cmd.get("landing") is Array):
			return {}
	return cmd

## ---------- 镜像重放 ----------
## 在 battle 上重放一条指令，返回结果文本；"!REPLAY_" 前缀 = 同步护栏失败（上层应判负）
static func apply_cmd(battle, cmd: Dictionary) -> String:
	if battle == null or cmd.is_empty():
		return "!REPLAY_空指令"
	var actor_idx := int(cmd.get("actor", -1))
	if actor_idx < 0 or actor_idx >= battle.units.size():
		return "!REPLAY_actor下标非法"
	var expected = battle.units[actor_idx]
	if battle.current() != expected:
		return "!REPLAY_状态漂移(current != actor)"
	var op := str(cmd.get("op", ""))
	match op:
		OP_MOVE:
			var arr: Array = cmd.get("cell", [])
			if arr.size() != 2:
				return "!REPLAY_cell非法"
			var cell := Vector2i(int(arr[0]), int(arr[1]))
			return str(battle.human_move(cell))
		OP_CAST:
			var slot := int(cmd.get("slot", 0))
			var t := int(cmd.get("target", -1))
			var enemy: BattleUnit = null
			if t >= 0:
				if t >= battle.units.size():
					return "!REPLAY_target下标非法"
				enemy = battle.units[t]
			var la: Array = cmd.get("landing", [-1, -1])
			var landing := Vector2i(int(la[0]), int(la[1]))
			return str(battle.human_cast(slot, enemy, landing))
		OP_DONE:
			battle.human_done()
			return ""
		_:
			return "!REPLAY_未知op"
