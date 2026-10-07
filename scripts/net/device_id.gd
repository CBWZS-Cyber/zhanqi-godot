class_name DeviceId
extends RefCounted
## 本机设备标识（2026-10-05）—— 给云端的**每日额度识别**用。
##
## ⚠️ 它**不是安全凭据**：玩家删掉 `user://device_id.txt` 就能换一个新的。
##    所以服务端**不把它当唯一防线** —— 未登录的每日额度是
##        min(本设备的 3 次, 该来源 IP 的 9 次)
##    删文件只是回到"和同网其他人共用那 9 次"，刷不出无限量。
##    真正刷不动的是**登录后的账号额度**（按 uid 计，换 IP、重装都无效）。
##
## ⚠️ 本文件**不引用任何 autoload**（`-s 脚本`模式下 autoload 名解析不了，
##    依赖链上出现它那个测试就编不过 —— 见 AICfg 头注释的同一条教训）。

const PATH := "user://device_id.txt"
const MIN_LEN := 16

static var _cached := ""


## 取本机标识；没有就生成一个并落盘。
## 任何异常都返回空串（服务端会退化成"纯 IP 计数"，仍然限得住）。
static func get_id() -> String:
	if _cached != "":
		return _cached
	_read()
	if _cached == "":
		_cached = _gen()
		_write(_cached)
	return _cached


static func _read() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var s := f.get_as_text().strip_edges()
	f.close()
	if s.length() >= MIN_LEN:
		_cached = s


static func _write(s: String) -> void:
	if s == "":
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[DeviceId] 写不了 %s，本次仅内存有效" % PATH)
		return
	f.store_string(s + "\n")
	f.close()


## 时间 + 系统唯一 ID（可能为空串）+ 随机数 → md5。
## 不追求密码学强度：它只是"把不同机器区分开"的标签。
static func _gen() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var raw := "%d|%s|%d|%d" % [
		int(Time.get_unix_time_from_system()), OS.get_unique_id(), rng.randi(), rng.randi(),
	]
	return raw.md5_text()
