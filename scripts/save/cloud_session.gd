class_name CloudSession
extends RefCounted
## 云端登录态本地缓存（2026-10-04）
##
## 记住「上次登录的是谁」，让玩家不必每次开游戏都输密码：
##   user://cloud_session.json —— {v, service, token, account, remember, saved}
##   （`remember` = 登录页「记住我」勾选状态；false 时启动不自动登录，但昵称仍预填）
##
## 这里**只存 token，绝不存密码**。token 是服务端签发的无状态 HMAC 凭证
## （有效期 30 天），丢了最多重新登录一次。
##
## 约定（与 AccountStore 一致）：
##   · 任何读写失败一律**降级为「没有缓存」**，绝不抛错、绝不阻断游戏启动；
##   · 服务地址不匹配时视为无效缓存（换了部署点，旧 token 也没用了）；
##   · 不在本文件里写 UI——它只负责数据。

const PATH := "user://cloud_session.json"
const VERSION := 1


static func _read() -> Dictionary:
	var empty := {"v": VERSION, "service": "", "token": "", "account": {}, "remember": true, "saved": ""}
	if not FileAccess.file_exists(PATH):
		return empty
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return empty
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return empty
	var d: Dictionary = parsed
	if typeof(d.get("token", null)) != TYPE_STRING:
		return empty
	if typeof(d.get("account", null)) != TYPE_DICTIONARY:
		d["account"] = {}
	return d


## 保存登录态
##
## [param remember] = **下次启动是否自动登录**（登录页的「记住我」勾选状态，2026-10-04 加）。
## 传 false 时 token **照存不误**（本次会话照常联云、照常同步进度），只是下次启动
## `load_session()` 会忽略它 —— 效果是「记住昵称，但不记住登录状态」，昵称仍会预填。
static func save(service: String, token: String, account: Dictionary, remember: bool = true) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"v": VERSION,
		"service": service,
		"token": token,
		"account": account,
		"remember": remember,
		"saved": Time.get_datetime_string_from_system(false, true),
	}, "\t"))
	f.close()
	return true


## 读出登录态；service 传入时会校验地址是否一致（换部署点 → 旧缓存作废）
static func load_session(service: String = "") -> Dictionary:
	var d := _read()
	if str(d.get("token", "")) == "":
		return {}
	# 「我不想被自动登录」—— 上次登录时没勾「记住我」就写下了 remember=false（2026-10-04 加）
	if not bool(d.get("remember", true)):
		return {}
	if service != "" and str(d.get("service", "")) != service:
		return {}
	return d


static func has_session(service: String = "") -> bool:
	return not load_session(service).is_empty()


static func clear() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": VERSION, "service": "", "token": "", "account": {}, "remember": true, "saved": ""}))
	f.close()


## 缓存里记的昵称（UI 显示"上次登录：xxx"用）
## ⚠️ 故意**不**走 `load_session()` —— 那个会被「不自动登录」挡掉，
##    但昵称预填与"是否自动登录"无关：没勾记住我也希望昵称还在框里（2026-10-04）。
static func cached_name(service: String = "") -> String:
	var d := _read()
	if service != "" and str(d.get("service", "")) != service:
		return ""
	var a: Dictionary = d.get("account", {})
	return str(a.get("name", ""))
