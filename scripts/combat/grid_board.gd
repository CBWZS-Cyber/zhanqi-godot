class_name GridBoard
extends RefCounted
## 格图距离 / 可达模块（战斗层使用）。
## 用法：
##   var board := GridBoard.new()                # 空板
##   board.add_cell(Vector2i(0,0)); board.add_cell(...)
##   board.set_obstacle(cell) / remove_obstacle(cell)   # 障碍（不可通行）
##   board.distance(a, b)                        # 两格最短格距（BFS），-1=不可达
##   board.reachable(origin, cost)               # 移动可达 { "x,y": 耗费 }
##   board.cells_in_range(origin, r)             # 以 origin 为中心、移动距离 <= r 的格（含 origin）
## 邻接：默认 4 向（上下左右），可用 8 向（含斜角）。
## 注：单位占格是否阻挡由战斗层决定——目前 obstacle 只含地图障碍，
##     敌方单位阻挡移动/技能穿透等规则后续在战斗层接入。

const DIRS_4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS_8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var walkable: Dictionary = {}      # "x,y" -> true（可通行格）
var obstacles: Dictionary = {}     # "x,y" -> true（障碍覆盖在可通行格上，判不可通行）
var terrain: Dictionary = {}       # "x,y" -> 地形 id（Terrain.*；缺省视为空地 0）
var connect_8: bool = false        # true=8 向邻接

func _init(cells: Array = [], use_8way := false) -> void:
	connect_8 = use_8way
	for c in cells:
		if c is Vector2i:
			add_cell(c)
		elif c is Vector2:
			add_cell(Vector2i(int(c.x), int(c.y)))

func _key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

func has_cell(c: Vector2i) -> bool:
	return walkable.has(_key(c))

func add_cell(c: Vector2i) -> void:
	walkable[_key(c)] = true

## 按地形 id 同步障碍状态（障碍类地形 → obstacles）
func set_cell_terrain(c: Vector2i, id: int) -> void:
	set_terrain(c, id)
	set_obstacle(c, Terrain.is_blocking(id))

func set_obstacle(c: Vector2i, on: bool) -> void:
	if on:
		obstacles[_key(c)] = true
	else:
		obstacles.erase(_key(c))

func passable(c: Vector2i) -> bool:
	var k := _key(c)
	return walkable.has(k) and not obstacles.has(k)

## ---------- 地形层 ----------
func set_terrain(c: Vector2i, id: int) -> void:
	terrain[_key(c)] = id

func terrain_at(c: Vector2i) -> int:
	return int(terrain.get(_key(c), 0))      # 缺省 = 空地

func clear_terrain() -> void:
	terrain.clear()

## 冰面滑行：从 from 沿 dir 方向持续前进，直到下一格不再是冰面（或不可通行/被占）
## occupy(c) 由战斗层提供：该格是否被单位占用（默认无占用）
func slide_end(from: Vector2i, dir: Vector2i, occupy: Callable = Callable()) -> Vector2i:
	if dir == Vector2i.ZERO:
		return from
	var cur := from
	var guard := 0
	while guard < 64:
		guard += 1
		var nxt := cur + dir
		if not passable(nxt):
			break
		if occupy.is_valid() and bool(occupy.call(nxt)):
			break
		if not Terrain.is_sliding(terrain_at(nxt)):
			# 下一格不是冰面：滑行到它（滑出冰面即停）
			if passable(nxt) and (not occupy.is_valid() or not bool(occupy.call(nxt))):
				cur = nxt
			break
		cur = nxt
	return cur

func _neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dirs: Array = DIRS_8 if connect_8 else DIRS_4
	for d in dirs:
		var nb: Vector2i = c + (d as Vector2i)
		if passable(nb):
			out.append(nb)
	return out

## 两格间最短格距（走可通行格），不可达/不可通行返回 -1
func distance(a: Vector2i, b: Vector2i) -> int:
	if a == b:
		return 0
	if not passable(a) or not passable(b):
		return -1
	var seen := {_key(a): 0}
	var frontier: Array = [a]
	var step := 0
	while frontier.size() > 0:
		step += 1
		var next: Array = []
		for c in frontier:
			for nb in _neighbors(c):
				if nb == b:
					return step
				var nk := _key(nb)
				if not seen.has(nk):
					seen[nk] = step
					next.append(nb)
		frontier = next
	return -1

## 从 origin 出发、耗费 <= max_cost 的可达格 → { "x,y": 最短耗费 }
func reachable(origin: Vector2i, max_cost: int) -> Dictionary:
	var out := {}
	if not passable(origin) or max_cost < 0:
		return out
	out[_key(origin)] = 0
	var frontier: Array = [origin]
	while frontier.size() > 0:
		var next: Array = []
		for c in frontier:
			var cost := int(out[_key(c)])
			if cost >= max_cost:
				continue
			for nb in _neighbors(c):
				var nk := _key(nb)
				if not out.has(nk):
					out[nk] = cost + 1
					next.append(nb)
		frontier = next
	return out

## 以 origin 为中心、最短格距 <= radius 的所有格（含 origin；含 radius=0）
func cells_in_range(origin: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not passable(origin):
		return out
	var reach := reachable(origin, radius)
	for k in reach:
		var parts := (k as String).split(",")
		out.append(Vector2i(int(parts[0]), int(parts[1])))
	return out
