extends Node
## 全局对战状态（autoload: Global）
## 由主菜单进入棋盘前写入，棋盘/对局 HUD 据此区分布局模式。

var battle_mode := "1v1"    # "1v1" | "4v4"（剧情等其它模式后续扩展）
