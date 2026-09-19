extends Control
class_name HpShieldBar
## 生命条 + 护盾条（同一条里分段显示）—— 2026-09-13
##
## 规则（用户定）：
##   ① hp + shield ≤ max_hp → 护盾按点数等比占位，血条不满，剩余留空
##   ② hp + shield >  max_hp → 两段按 hp:shield 比例铺满整条
## 换算式在 DamageFx.hp_shield_layout()，两式在 total == max_hp 处连续。
##
## 画法（从左到右）：[绿色 hp][蓝色 shield][空]
##   - hp 段掉血时平滑滑落，并短暂露出白色「残影段」= 这一下掉了多少
##   - 护盾段**不做动态特效**（用户 2026-09-13 明确要求）
##
## 数字标签由外部（各 UI 的 _make_bar）作为本节点子节点加入，用锚点铺满 → 自动居中。

const COL_BG := Color(0.04, 0.05, 0.09, 0.9)
const COL_HP := Color(0.42, 0.78, 0.36)
const COL_SHIELD := Color(0.33, 0.68, 0.95)
const COL_GHOST := Color(0.97, 0.96, 0.92, 0.85)

const DROP_SPEED := 1.6      # hp 段滑落速度（每秒多少倍 max_hp）
const GHOST_HOLD := 0.20     # 白条残影停留（秒）
const GHOST_SPEED := 0.9     # 白条残影追平速度

var hp := 0.0
var shield := 0.0
var max_hp := 1.0

var _shown := 0.0            # 当前显示的 hp（掉血缓动用）
var _ghost := 0.0            # 白条残影（= 掉血前的 hp）
var _ghost_hold := 0.0
var _primed := false

var _sb_bg := StyleBoxFlat.new()
var _sb_hp := StyleBoxFlat.new()
var _sb_sh := StyleBoxFlat.new()
var _sb_gh := StyleBoxFlat.new()

func _ready() -> void:
	for sb in [_sb_bg, _sb_hp, _sb_sh, _sb_gh]:
		sb.set_corner_radius_all(5)
	_sb_bg.bg_color = COL_BG
	_sb_hp.bg_color = COL_HP
	_sb_sh.bg_color = COL_SHIELD
	_sb_gh.bg_color = COL_GHOST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 外部每次刷新调一次。注意：护盾变化不触发任何残影/缓动。
func set_values(h: float, s: float, m: float) -> void:
	max_hp = maxf(1.0, m)
	hp = maxf(0.0, h)
	shield = maxf(0.0, s)
	if not _primed:
		_shown = hp
		_ghost = hp
		_primed = true
	else:
		if hp >= _shown:
			_shown = hp          # 回血：立即到位（迟了像卡顿）
		else:
			_ghost = maxf(_ghost, _shown)   # 掉血：先把残影冻在旧值
			_ghost_hold = GHOST_HOLD
	if _ghost < hp:
		_ghost = hp
	if not is_processing():
		set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var busy := false
	var scale_ref := maxf(1.0, max_hp)
	if _shown > hp + 0.005:
		_shown = maxf(hp, _shown - scale_ref * DROP_SPEED * delta)
		busy = true
	elif _shown < hp:
		_shown = hp
		busy = true
	if _ghost > hp + 0.005:
		if _ghost_hold > 0.0:
			_ghost_hold = maxf(0.0, _ghost_hold - delta)
		else:
			_ghost = maxf(hp, _ghost - scale_ref * GHOST_SPEED * delta)
		busy = true
	elif _ghost < hp:
		_ghost = hp
		busy = true
	if busy:
		queue_redraw()
	else:
		_shown = hp
		_ghost = hp
		set_process(false)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return
	draw_style_box(_sb_bg, Rect2(0.0, 0.0, w, h))
	var lay := DamageFx.hp_shield_layout(hp, shield, max_hp)
	var denom: float = lay.x
	var hp_w := w * clampf(_shown / denom, 0.0, 1.0)
	var sh_w := w * clampf(lay.z, 0.0, 1.0)
	if hp_w > 0.5:
		draw_style_box(_sb_hp, Rect2(0.0, 0.0, hp_w, h))
	if sh_w > 0.5:
		draw_style_box(_sb_sh, Rect2(hp_w, 0.0, sh_w, h))
	# 白条残影：只反映「hp 掉了多少」，画在最上层盖住护盾一小会儿
	var ghost_w := w * clampf(_ghost / denom, 0.0, 1.0)
	if ghost_w > hp_w + 0.5:
		draw_style_box(_sb_gh, Rect2(hp_w, 0.0, ghost_w - hp_w, h))
