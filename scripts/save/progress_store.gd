class_name ProgressStore
extends RefCounted
## 本机进度（2026-10-05 新增）——**它不是账号**。
##
## 这个工程里「账号」只剩一个概念：**云端账号**（注册在服务器上，进度跟着账号走、
## 换台电脑也能接着玩）。本文件存的是**匿名本机进度**：**没有名字、没有 id、
## 没有列表、不能切换** —— 界面上只读作「离线游玩」。
##
## 为什么还需要它：客户 2026-10-05 明确要求「**离线玩 = 玩 0 进度原始账号**」，
## 且这份进度要留得住（下次启动接着玩）—— 所以既不能挂在账号上，也不能只放内存。
##
## ⚠️ 与云端的关系是**两份独立的进度**，别让它们互相污染：
##   · 登录中 → 读写的一律是**云端进度**（运行时在 `Global.player_progress`，
##     登录态缓存在 `cloud_session.json` 的 `account.progress`），**本文件不参与**；
##   · 离线玩 → 读写的一律是本文件。
##   这样「登录后进度跟着账号走」和「离线玩是 0 进度」两条同时成立。
##
## 约定（与 `CloudSession` / 原 `AccountStore` 一致）：
##   · 任何读写失败一律**降级为「没有进度」**，绝不抛错、绝不阻断启动；
##   · 不在这里写 UI —— 它只负责数据。

const PATH := "user://progress.json"
const VERSION := 1

## 水平三档（原 `AccountStore.TIER_*` 平移过来 —— 这是**玩家自评水平**，不是账号字段，
## 所以它留下来，只是换了家）。与主菜单「你的水平怎么样」一一对应。
const TIER_NEW := "new"          # 我是新手 → 完整教程
const TIER_PLAYED := "played"    # 玩过战棋 → 精简教程（只讲本作特有规则）
const TIER_VETERAN := "veteran"  # 我是老手 → 跳过教程


static func tier_label(tier: String) -> String:
	match tier:
		TIER_NEW: return "新手"
		TIER_PLAYED: return "玩过战棋"
		TIER_VETERAN: return "老手"
	return "未选择"


## 空白进度 = 「0 进度原始账号」
static func empty() -> Dictionary:
	return {"v": VERSION, "tier": "", "tutorial_done": false, "tutorial_hero": ""}


## 只认这三个字段，别的一律丢掉 —— 免得把脏数据写回文件
static func _normalize(src: Dictionary) -> Dictionary:
	var out := empty()
	out["tier"] = str(src.get("tier", ""))
	out["tutorial_done"] = bool(src.get("tutorial_done", false))
	out["tutorial_hero"] = str(src.get("tutorial_hero", ""))
	return out


static func load_progress() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return empty()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return empty()
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return empty()
	return _normalize(parsed)


static func save_progress(d: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_normalize(d), "\t"))
	f.close()
	return true


## 合并式更新（只覆盖传进来的字段），返回更新后的进度
static func update(patch: Dictionary) -> Dictionary:
	var d := load_progress()
	for k in patch.keys():
		d[str(k)] = patch[k]
	save_progress(d)
	return load_progress()


## 重置为空白 —— 回到「0 进度原始账号」
static func reset() -> void:
	save_progress(empty())


## 本机是否已有**离线进度**（启动分流用：有就直接进主菜单，没有才问登录）
static func has_any() -> bool:
	var d := load_progress()
	return str(d.get("tier", "")) != "" or bool(d.get("tutorial_done", false))
