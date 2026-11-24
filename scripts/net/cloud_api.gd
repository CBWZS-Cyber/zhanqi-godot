class_name CloudApi
extends Node
## 云端账号 API 客户端（2026-10-04）
##
## 对接自有云服务器上的 `zhanqi-cloud`（见 tools/cloud-service/server.js）：
##   POST /send-code {email}                     → {ok, ttl}      （注册验证码，2026-10-04 加）
##   POST /register  {name, pass, email, code}   → {ok, token, account}
##   POST /login     {name, pass}                → {ok, token, account}
##   POST /progress  {tier, tutorial_done, ...}  → {ok, account}   （需 Bearer token）
##   POST /bug-report {title, detail, ...}       → {ok, id}        （服务端直投 AgentMail）
##   POST /send-code {name, purpose:"reset"}     → {ok, masked, ttl}  （忘记密码·重置码，2026-10-05 加）
##   POST /reset-password {name, code, newpass}  → {ok, token, account}（忘记密码·换新密码，同上）
##   POST /bind-phone {action, phone[, code]}    → {ok, account}   （老账号补绑手机号，需登录）
##
## 🔀 **双通道（2026-10-09）**：上面的接口都可加 `channel:"sms"` 走**短信**（把 `email` 换成 `phone`）——
##    **缺省 channel = 邮箱老路**（已发布客户端不传该字段，语义逐字节不变）。
##    短信验证码由阿里云生成与校验（服务端不存码），每条计费 ⇒ 服务端限流更严。
##    契约见 docs/短信验证_接口契约.md。
##
## 账号本体存在服务器上（默认一人一个 JSON 小文件，见 store.js），密码是 scrypt
## 加盐哈希 —— **任何响应都不会带 salt/hash**，客户端也永远不存密码明文。
##
## 🔴 **本客户端不接触任何邮件凭据**：验证码与 Bug 上报都只调 8789，
##    发信由服务器上的 mail-gateway（8791）完成（授权码只在那一台机器上）。
##
## ⚠️ 一律走**异步** HTTPRequest。不要用同步 HTTPClient —— 那会阻塞主线程，
##    登录界面会直接卡住（NetRoomCode 文件头也记着同一条）。
##
## ⚠️ 本文件**不引用 `Global` 或任何 autoload**（`-s 脚本`模式下解析不了 autoload，
##    会让依赖它的测试整个编不过）。服务地址由调用方注入。

signal register_done(ok: bool, account: Dictionary, error: String)
signal login_done(ok: bool, account: Dictionary, error: String)
signal progress_done(ok: bool, error: String)
## 验证码是否发出（失败时 msg 是给人看的中文原因，如"验证码刚发过，请 42 秒后再试"）
signal send_code_done(ok: bool, msg: String)
## Bug 上报结果：成功时 msg 是上报编号（如 Rmutxc14jf908），失败时是原因
signal report_done(ok: bool, msg: String)
## 忘记密码·重置码是否发出。成功时 msg 是**掩码邮箱**（如 `c***g@qq.com`）；
## **空字符串 = 该账号没有绑定邮箱**（老账号或过渡档里没走验证码注册的）→ 无法自助找回。
signal reset_code_done(ok: bool, msg: String)
## 忘记密码·重置结果：成功时已带上新 token（= 直接登录了），失败时 error 是中文原因
signal reset_password_done(ok: bool, account: Dictionary, error: String)
## 绑定手机号（老账号补绑，`/bind-phone`）：成功时 msg 是掩码手机号，失败时是中文原因
signal bind_phone_done(ok: bool, msg: String)

## 渠道标识（2026-10-09 短信通道）—— 与服务端 `channel` 字段同字面量
## ⚠️ 故意做成"不同渠道调不同方法"而不是给一个默认参数：调用点漏传时不会静默退回邮箱，
##    否则"该发短信却发了邮件"这种问题极难查（服务端缺省 = 邮箱老路）。
const CH_EMAIL := "email"
const CH_SMS := "sms"

const TIMEOUT_SEC := 8.0
## 兜底地址；正常路径由 main_ui 注入 Global.cloud_service
const DEFAULT_SERVICE := "https://game.learnest.cn"

var service_url := DEFAULT_SERVICE
var token := ""
var account: Dictionary = {}

var _http: HTTPRequest = null
var _busy := false
var _req := ""


func _ready() -> void:
	_ensure_http()


func _ensure_http() -> HTTPRequest:
	if _http != null and is_instance_valid(_http):
		return _http
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_done)
	return _http


func busy() -> bool:
	return _busy


func reset() -> void:
	token = ""
	account = {}


## 注册新账号。昵称重复时服务端返回 409（OSS/文件系统的原子写保证不会重复）
## 注意：参数名不能叫 `pass` —— 那是 GDScript 的保留关键字（空语句），会直接解析失败。
##
## `email` / `code` 是 2026-10-04 加的注册验证码。两者留空时仍按老协议提交
## （服务端过渡档 `REQUIRE_EMAIL_CODE=0` 下能注册成功）—— 但**新客户端一律带上**。
func register(name: String, pwd: String, email := "", code := "") -> void:
	var body: Dictionary = {"name": name, "pass": pwd}
	if email != "":
		body["email"] = email
	if code != "":
		body["code"] = code
	_post("register", "/register", body)


## 注册新账号 · **短信通道**（2026-10-09）。`code` 是阿里云下发的短信验证码。
## 服务端会校验"该手机号没绑过别的账号"，成功后账号的 `phone` 即被绑定。
func register_sms(name: String, pwd: String, phone: String, code: String) -> void:
	_post("register", "/register", {
		"channel": CH_SMS, "name": name, "pass": pwd, "phone": phone, "code": code,
	})


## 给邮箱发注册验证码（6 位，5 分钟有效）。服务端有 60 秒重发间隔与每日上限。
func send_code(email: String) -> void:
	_post("send_code", "/send-code", {"email": email})


## 给手机号发注册验证码 · **短信通道**（2026-10-09）。**每次调用都计费**，
## 服务端限流比邮箱更严（同号 60 秒 / 5 条每日，同 IP 10 条每小时 / 20 条每日，全局日 200）。
func send_code_sms(phone: String) -> void:
	_post("send_code", "/send-code", {"channel": CH_SMS, "phone": phone})


## 绑定手机号 · 发码（需登录；老账号补绑用）。模板 `100004`。
func bind_phone_send(phone: String) -> void:
	_post("bind_phone", "/bind-phone", {"action": "send", "phone": phone})


## 绑定手机号 · 提交（需登录）。成功后 `account.phoneBound` 变 true、`account.phone` 是掩码。
func bind_phone_commit(phone: String, code: String) -> void:
	_post("bind_phone", "/bind-phone", {"action": "commit", "phone": phone, "code": code})


## 提交 Bug 上报 —— **服务端直接把邮件投到 AI 邮箱**，玩家不用自己发信。
## payload 常用字段：title / detail / contact / category / version / platform / name / uid
func submit_bug_report(payload: Dictionary) -> void:
	_post("bug_report", "/bug-report", payload)


## 忘记密码 · 第一步：按昵称请求重置码。
##
## ⚠️ 服务端把码发到**该账号自己绑定的**邮箱（不是调用方传进来的任何地址），
## 所以谁也拿不到别人账号的重置码。这就是服务端「只绑定验证过的邮箱」那条设计的兑现
## —— 若是过渡档里填了邮箱却没走验证码的账号，服务端存的是空邮箱，这一步会明确拒绝。
##
## 成功时 `reset_code_done` 带回**掩码**（如 `c***g@qq.com`）；**空串 = 该账号没绑这个联系方式**
## （老账号，或绑的是另一种渠道）⇒ 界面据此提示"改用另一种验证方式"。
func send_reset_code(name: String) -> void:
	_post("reset_code", "/send-code", {"name": name, "purpose": "reset"})


## 忘记密码 · 第一步（**短信通道**，2026-10-09）：码发到该账号**自己绑定的**手机号。
## 收不到码的三种情形**故意回同一形状**（`masked:""`），不区分"昵称不存在/没绑手机号"——防枚举。
func send_reset_code_sms(name: String) -> void:
	_post("reset_code", "/send-code", {"channel": CH_SMS, "name": name, "purpose": "reset"})


## 忘记密码 · 第二步：用重置码换新密码。
## 成功后服务端直接下发新 token（= 已登录），不要求再输一次密码。
func reset_password(name: String, code: String, newpass: String) -> void:
	_post("reset_password", "/reset-password", {"name": name, "code": code, "newpass": newpass})


## 忘记密码 · 第二步（**短信通道**）：`code` 是阿里云短信验证码。
func reset_password_sms(name: String, code: String, newpass: String) -> void:
	_post("reset_password", "/reset-password", {
		"channel": CH_SMS, "name": name, "code": code, "newpass": newpass,
	})


func login(name: String, pwd: String) -> void:
	_post("login", "/login", {"name": name, "pass": pwd})


## 上传进度。未登录（无 token）时静默忽略 —— 没连云端不该因此报错
func upload_progress(tier: String, tutorial_done: bool, tutorial_hero: String) -> void:
	if token == "":
		progress_done.emit(false, "未登录")
		return
	_post("progress", "/progress", {
		"tier": tier, "tutorial_done": tutorial_done, "tutorial_hero": tutorial_hero,
	})


func _post(req: String, path: String, body: Dictionary) -> void:
	if _busy:
		_fail(req, "上一个请求还没回来，稍等")
		return
	_busy = true
	_req = req
	var h := _ensure_http()
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := h.request(service_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		_fail(req, "连不上云端服务（%s）" % service_url)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var req := _req
	_req = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(req, "连不上云端服务，检查一下网络")
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		_fail(req, "云端返回了看不懂的内容（HTTP %d）" % code)
		return
	var data: Dictionary = d

	# 服务端约定：成功 2xx 且 ok=true；失败带 error 文案（已经是给人看的中文）
	var ok := bool(data.get("ok", false)) and code >= 200 and code < 300
	var err := str(data.get("error", ""))

	if not ok:
		_fail(req, err if err != "" else "云端返回异常（HTTP %d）" % code)
		return

	if data.has("token"):
		token = str(data["token"])
	if data.has("account") and typeof(data["account"]) == TYPE_DICTIONARY:
		account = data["account"]

	match req:
		"register":
			register_done.emit(true, account, "")
		"login":
			login_done.emit(true, account, "")
		"progress":
			progress_done.emit(true, "")
		"send_code":
			send_code_done.emit(true, "")
		"bug_report":
			report_done.emit(true, str(data.get("id", "")))
		"reset_code":
			# masked 为空 = 该账号没绑邮箱（服务端不报错，把判断交回界面 —— 界面才知道怎么措辞）
			reset_code_done.emit(true, str(data.get("masked", "")))
		"reset_password":
			reset_password_done.emit(true, account, "")
		"bind_phone":
			# 掩码手机号由服务端回在 account.phone 里（成功即已写入账号）
			bind_phone_done.emit(true, str(account.get("phone", "")))
		_:
			pass


func _fail(req: String, reason: String) -> void:
	match req:
		"register":
			register_done.emit(false, {}, reason)
		"login":
			login_done.emit(false, {}, reason)
		"progress":
			progress_done.emit(false, reason)
		"send_code":
			send_code_done.emit(false, reason)
		"bug_report":
			report_done.emit(false, reason)
		"reset_code":
			reset_code_done.emit(false, reason)
		"reset_password":
			reset_password_done.emit(false, {}, reason)
		"bind_phone":
			bind_phone_done.emit(false, reason)
		_:
			pass
