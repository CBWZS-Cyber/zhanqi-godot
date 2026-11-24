class_name AICfg
extends RefCounted
## 困难难度「战术模型」的配置（2026-10-04 改）
##
## ⚠️ **这里已经没有任何 API Key 了。**
##    原先 Key 以「XOR + base64 混淆」打包在 res://scripts/ai/ai_key.bin 里 ——
##    那种做法只能防"一眼抄走"，任何拿到客户端的人都能把 Key 提取出来。
##    现在改成**云端代调**：客户端只把战局卷子发上去、拿回答案，
##    Key 只存在服务器上（/opt/zhanqi-cloud/llm.json，权限 600）。
##    服务端实现见 tools/cloud-service/server.js 的 `POST /llm`。
##
## 失败一律回退本地 AI（`battle_base._maybe_llm_plan` 已经处理得很干净）：
##    云端没部署、网络不通、被限流 429、模型抽风 —— 都只是"这一回合不请模型"，
##    绝不阻断开局，玩家最多觉得这局对手没那么聪明。

## 云端战术模型端点（兜底值）。
## 正常路径：进对局前由调用方设成 `Global.cloud_service + "/llm"`。
## 2026-11-24：裸 IP:端口 → 域名 + HTTPS。IP 直连的 http:// 端点已不再需要：
##   game.learnest.cn 由 nginx 终结 TLS 后反代到 127.0.0.1:8789。
const DEFAULT_ENDPOINT := "https://game.learnest.cn/llm"

## ⚠️ 本文件**不引用 `Global` 或任何 autoload** —— `-s 脚本`模式下 autoload 名解析不了，
##    依赖链上出现它，那个测试就整个编不过（NetRoomCode / CloudApi 同一条教训）。
static var endpoint := DEFAULT_ENDPOINT

## 已登录时的 token（空 = 未登录 / 选了"离线玩"）。**由主菜单在会话变化时写入**
## （`main_ui` 的登录成功 / 恢复会话 / 登出三处）。
##
## 用途：服务端据此把每日额度从未登录的 **3 次/设备** 提到登录后的 **10 次/账号**
## （见 server.js 的 GAME_QUOTA）。留空就等于未登录 —— 不会报错，只是额度是 3 次。
static var auth_token := ""

## 卷子字符上限（与云端 server.js 的 LLM_MAX_PROMPT 对齐）。
## 超了就不发 —— 省一次白跑的往返，直接回退本地 AI。
const MAX_PROMPT := 60000


## 战术模型是否"看起来可用"：只判断有没有配端点。
##
## ⚠️ 真正的可用性（网络 / 额度 / 限流）只有实际调用才知道，所以这里**乐观返回 true**。
##    失败路径由 `LLMDecider.plan_round()` 返回空字典表达 → 调用方回退本地 AI。
##    这比"进来先探一次网"好：不用为一次失败多付一次往返延迟。
static func ready() -> bool:
	return endpoint != ""


## 回到兜底端点（测试用）
static func reset_endpoint() -> void:
	endpoint = DEFAULT_ENDPOINT


## 轻量探测地址：设置面板的"检测云端"按钮用它。
## 服务端只回一个 ready 标志，**不调模型、不烧额度**（见 server.js 的 GET /llm/ping）。
static func ping_url() -> String:
	return endpoint.rstrip("/") + "/ping"
