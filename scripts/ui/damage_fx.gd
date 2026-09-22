extends RefCounted
class_name DamageFx
## 掉血特效 · 共用小工具（2026-09-13）
##
## 这里只放「三个界面都要用、又不想抄三遍」的表现层工具。
## 棋子级的特效（飘字/闪红/白条残影）在 unit_token.gd 里 —— 因为棋子是三个界面共用的。
##
## 约定：本文件是**纯表现层**，任何时候都不允许读写战斗状态、不允许用随机数
## （联机同步只认战斗层，表现层掺进去会造成状态漂移）。

## 把数字写进控件内嵌的 Label（HpShieldBar 与 ProgressBar 都把 Label 作为子节点 + 锚点铺满）
static func _set_child_label(node: Node, text: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	for cc in node.get_children():
		if cc is Label:
			(cc as Label).text = text
			return

## 更新一条侧栏条（生命 / 能量 / 理智），兼容 HpShieldBar 与 ProgressBar，并写入数字标签。
##
## 2026-09-14：抽到这里，是因为三处界面（1v1 / 4V4 / 剧情关）各写了一份 `_update_bar`，
## 2026-09-13 换生命条控件时只改了其中一部分分支 → 生命条的数字标签没人写，
## 永远停在 _make_bar 的初始值 "1.00 / 1.00"（用户实际遇到的 bug）。
## 集中到一处后：① 三处不会再走偏；② 可以在无头测试里直接覆盖。
static func update_bar(bar: HBoxContainer, value: float, max_value: float,
		num_text := "", tag_text := "", smooth := false, shield := 0.0) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	# 标签（"生命/能量/理智"）：HBox 的第一个直接子 Label
	for c in bar.get_children():
		if c is Label:
			if tag_text != "":
				(c as Label).text = tag_text
			break
	var shown_text := num_text if num_text != "" else ("%.2f / %.2f" % [value, max_value])
	for c in bar.get_children():
		if c is HpShieldBar:
			var hsb := c as HpShieldBar
			hsb.set_values(value, shield, max_value)
			_set_child_label(hsb, shown_text)
		elif c is ProgressBar:
			var pb := c as ProgressBar
			pb.max_value = max_value if max_value > 0 else 1
			# smooth=true 时走缓动（涨立即 / 跌平滑滑落）
			if smooth:
				ease_bar(pb, value)
			else:
				pb.value = clampf(value, 0.0, pb.max_value)
			_set_child_label(pb, shown_text)


## 侧栏条「缓动下降」：掉血时让条平滑滑到新值，而不是瞬间跳。
##   - 涨（回血）：立即到位，不做动画（避免"回血慢半拍"的错觉）
##   - 跌（掉血）：0.38s 缓动，玩家能看清这一下掉了多少
## 连续掉血时不会叠加 tween：后一次会杀掉前一次，直接追最新目标。
## tween 存在控件自己的 meta 上，所以不需要任何外部状态字典。
static func ease_bar(pb: ProgressBar, target: float, dur := 0.38) -> void:
	if pb == null or not is_instance_valid(pb):
		return
	var t := clampf(target, 0.0, pb.max_value)
	var cur := float(pb.value)
	var old = pb.get_meta("fx_tw", null)
	var running: bool = old is Tween and (old as Tween).is_valid()
	if t >= cur - 0.01:
		if running:
			(old as Tween).kill()
		pb.set_meta("fx_tw", null)
		pb.value = t
		return
	if running:
		(old as Tween).kill()
	var tw := pb.create_tween()
	pb.set_meta("fx_tw", tw)
	tw.tween_property(pb, "value", t, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 血条布局：把 hp / shield / max_hp 换算成 (分母, hp 占比, shield 占比)。
##
## 规则（用户 2026-09-13 定）：
##   ① hp + shield ≤ max_hp → 分母 = max_hp  → 护盾按点数等比占位，血条不满，剩余留空
##   ② hp + shield >  max_hp → 分母 = hp+shield → 两段按比例铺满整条
## 两式在 total == max_hp 处**连续**（都等于按 max_hp 等比），所以护盾刚好看满条时不会跳变。
##
## 返回值用 Vector3 是为了不每帧 new 一个 Dictionary：
##   x = 分母（调用方换算别的量，比如白条残影宽度，必须用同一个分母才对齐）
##   y = hp 占比 0..1    z = shield 占比 0..1
static func hp_shield_layout(hp: float, shield: float, max_hp: float) -> Vector3:
	var h := maxf(0.0, hp)
	var s := maxf(0.0, shield)
	var m := maxf(1.0, max_hp)
	var total := h + s
	var denom: float = m if total <= m else total
	return Vector3(denom, h / denom, s / denom)

