extends Node
## 全局对战状态（autoload: Global）
## 由主菜单进入棋盘前写入，棋盘/对局 HUD 据此区分布局模式。

var battle_mode := "1v1"    # "1v1" | "4v4"（剧情等其它模式后续扩展）
var offline_type := "pve"   # "pve"（人机）| "hotseat"（开房间·双人同机）
var difficulty := "easy"   # 单机 PVE 难度：easy / normal / hard（由主菜单写入）
var ai_backend := "llm"    # 困难难度后端："llm"（豆包战术模型）| "local"（本地进阶 AI）

# ---------- 联机（Net autoload 配合使用）----------
var net_mode := false       # true = 本局为联机对局（duel/team_duel 按此分支）
var net_is_host := false    # host=红方 / joiner=蓝方
var net_port := 3457
var net_seed := 0           # host 生成的确定性随机种子（开局包下发）
var net_red_hero := ""      # 开局包同步的红方英雄 id
var net_blue_hero := ""     # 开局包同步的蓝方英雄 id
var net_transport := "ws"   # "ws"=公网（走自研反向隧道，**输房间号即连，不分网络环境**）
                            # "enet"=局域网 UDP 直连（同一 WiFi 下更快，作为可选的进阶用法）
## 房间号目录服务地址（2026-09-30 新增；2026-10-03 上云）。
## 已部署到自有阿里云 ECS（/opt/room-service，systemd 单元 `room-service`，端口 8787）——
## 玩家不再需要在自己电脑上跑服务，房间号全局可用。
## 换部署点只改这一处；留空则回落到 NetRoomCode.DEFAULT_SERVICE。
## ⚠️ 本地自测想用本机实例时，临时改成 "http://127.0.0.1:8787"。
## 参见 tools/room-service/server.js
var net_room_service := "http://39.105.223.8:8787"

## 反向隧道中继地址（2026-10-03 新增）—— 与房间服务同一台机器，但走 TCP 长连接。
## 房主建房时主动连它（NAT 无关），换回一个公网端口，再把「公网地址」拿去换房间号。
## 这样**任何网络环境下，对方只要有房间号就能加入**，房主不用装 cpolar 之类的东西。
## 参见 tools/relay-service/relay-service.js
var net_relay_host := "39.105.223.8"
var net_relay_port := 19001

# ---------- 云端服务（2026-10-04 新增）----------
## 自有云服务器上的 zhanqi-cloud：**版本清单 + 账号 + 进度**三合一。
## 部署在 /opt/zhanqi-cloud（systemd 单元 `zhanqi-cloud`，端口 8789）。
## 换部署点只改这一处。参见 tools/cloud-service/server.js
##
## ⚠️ 明文 HTTP（没有域名就签不了证书）。密码在链路上是明文，
##    内测/朋友之间可接受，公开运营前必须上 HTTPS。
var cloud_service := "http://39.105.223.8:8789"
## 本局是否处于"已登录云端"状态。false = **离线游玩**（进度只在这台电脑，见 `ProgressStore`）。
var cloud_online := false

# ---------- 账号与进度（2026-09-28 建，2026-10-05 重构）----------
## ⚠️ **「账号」在本工程只剩一个概念：云端账号。**
## 2026-10-05 按客户要求删掉了「本地账号」整套（原 `AccountStore` / `accounts.json` /
## 登录页的「选择已有账号」）—— 本机不再有账号、也不再有账号列表。
## 离线玩 = 玩一份**匿名本机进度**（无名字/无 id/不可切换，见 `ProgressStore`）。
##
## 已登录时的**云端账号**信息（服务端返回的字典：name / uid / progress…）；离线时为空字典。
var cloud_account: Dictionary = {}
## 当前这一局的**进度**（`tier` / `tutorial_done` / `tutorial_hero`）。
## 真源分两种：登录中 → **云端**（权威）；离线玩 → `ProgressStore`（本机匿名进度）。
## 只用于显示与记录进度，**不参与任何战斗计算**。
var player_progress: Dictionary = {}
## 本次教程选用的英雄 id（主菜单选角色时写入，Tutorial 场景读取）
var tutorial_hero := ""
## 本次教程的档位（new=完整篇 / played=精简篇；veteran 不进教程）。
## 精简篇会直接跳到「看懂左边三条」，不再教基本操作。
var tutorial_tier := "new"
