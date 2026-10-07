class_name UiDesign
extends RefCounted
## 「墨金」设计令牌 —— 全工程唯一的视觉真源（single source of truth）。
##
## ============================ 为什么要有这个文件 ============================
## 2026-10-04 审计：UI 层共有 **314 处** `Color(...)` 硬编码字面量，散落在
## main_ui / duel / team_duel / tutorial / story_battle / ui_kit / hp_shield_bar 等文件里。
## 后果有三条，都是实报出来的病：
##
##   1. **同名不同值**：`COL_PANEL` 在 4 个文件各写一遍，alpha 一个是 0.94 一个是 0.9，
##      肉眼看不出来，但改一处不会影响另一处 —— 于是永远改不干净。
##   2. **语义冲突**：`COL_RED` 既当「我方阵营色」又当「血量条色」（tutorial.gd），
##      想统一血量条颜色就会连带把队伍色改掉。
##   3. **两套体系打架**：界面框架是冷调深蓝+金，棋盘是暖木+羊皮纸，
##      中间靠一行 `COL_BORDER` 硬缝，整体显得"拼"。
##
## ============================ 为什么能零视觉变化迁移 ============================
## 本文件的每个令牌，**数值都以现有硬编码值为锚点**（注释里标了「← 原 xxx」）。
## 也就是说：把 `const COL_GOLD := Color(0.941, 0.780, 0.369)` 换成
## `const COL_GOLD := UiDesign.GOLD_500` 之后，**渲染结果逐像素相同**，
## 但从此全世界只有一个地方能改这个金。
##
## 这是有意的：用户要求"结构性优化零行为变化 —— 只动结构、不改游戏效果"。
## 所以第一阶段只做**收敛**，不做**改色**；想调色，改这一个文件即可全工程生效。
##
## ============================ 用法 ============================
##     const COL_GOLD := UiDesign.GOLD_500          # 常量引用（推荐）
##     var c := UiDesign.text_on(UiDesign.INK_800)  # 需要算对比度时
##
## 禁止在任何界面文件里再写 `Color(...)` 字面量。要新颜色，先在这里加令牌。

# ============================================================================
# 一、墨（Ink）—— 中性色阶。蓝调偏移（色相约 225°），数字越大越深。
# ============================================================================

const INK_950 := Color(0.04, 0.05, 0.09)          # 最深：资源条底槽（← 原 hp_shield_bar.COL_BG / UiKit.BAR_BG_COLOR 的 RGB）
const INK_900 := Color(0.06, 0.07, 0.12)          # 弹窗/对话框**不透明**底（用户铁律：弹窗背景不许半透）
const INK_800 := Color(0.10, 0.12, 0.19)          # ★ 卡片/面板面（← 原 COL_PANEL 的 RGB，4 个文件一致）
const INK_750 := Color(0.12, 0.15, 0.24)          # 深面（← 原 0.12,0.15,0.24，5 个文件一致）
const INK_700 := Color(0.16, 0.19, 0.29)          # 面与悬停之间的过渡（← 原 0.16,0.19,0.29，6 个文件一致）
const INK_650 := Color(0.20, 0.23, 0.36)          # ★ 悬停面（← 原 UiKit hover）
const INK_600 := Color(0.23, 0.27, 0.42)          # 悬停与描边之间（← 原 0.23,0.27,0.42，5 个文件一致）
const INK_550 := Color(0.33, 0.37, 0.52)          # 次级分隔
const INK_500 := Color(0.45, 0.50, 0.64)          # ⚠️ 弱文字/**只许禁用态**（对卡片底 4.16，不足 AA 4.5）
const INK_400 := Color(0.58, 0.62, 0.72)          # 更弱文字/输入框占位符（6.14，达标）
const INK_300 := Color(0.68, 0.72, 0.80)          # 三级文字：说明（← 原 tutorial.COL_DIM；并吞并 0.66,0.71,0.79）
const INK_250 := Color(0.75, 0.80, 0.88)          # 二级半文字（← 原 0.75,0.80,0.88；并吞并 0.72,0.77,0.85）
const INK_200 := Color(0.84, 0.87, 0.92)          # 二级文字：标签（← 原 UiKit.TAG_COLOR；并吞并 5 个近似灰）
const INK_100 := Color(0.92, 0.95, 0.99)          # 一级文字：正文（← 原 UiKit.TEXT_COLOR）
const INK_050 := Color(0.97, 0.98, 1.00)          # 最亮：强调正文（并吞并 0.95,0.97,1.0）
#
# ⚠️ 编号**非等距**，这是有意的：每级的数值都锚定在迁移前的历史值上（保证迁移零视觉变化），
#    而历史值本身不等距。规矩只有一条 —— **编号必须与亮度同序**（数字越小越亮），
#    顺序错乱会让层级关系被读反（tests/ui_design_smoke.gd 的 C 段会抓住）。
#    注意 INK_800 → INK_750 是相邻亮度但编号跨 50，这是历史值造成的，不要"顺手修正"。

# ============================================================================
# 二、金（Gold）—— 唯一强调色。数字越大越深。
#     全工程只允许"金"承担强调/焦点/主 CTA，不允许出现第二个强调色。
# ============================================================================

const GOLD_700 := Color(0.62, 0.48, 0.16)         # 最深：凹陷/按下阴影
const GOLD_600 := Color(0.78, 0.62, 0.22)         # 按下态（← 原 main_ui 主按钮 pressed）
const GOLD_500 := Color(0.941, 0.780, 0.369)      # ★ 主强调（← 原 COL_GOLD，3 个文件一致）
const GOLD_400 := Color(1.0, 0.88, 0.55)          # 悬停态（← 原 main_ui 主按钮 hover）
const GOLD_300 := Color(1.0, 0.95, 0.80)          # 高亮文字（← 原 UiKit.TEXT_HOVER_COLOR）
const GOLD_200 := Color(1.0, 0.97, 0.88)          # 极浅：字号最小的金色说明
const GOLD_100 := Color(1.0, 0.99, 0.95)          # 近白偏暖
## 高亮黄 —— 教程 / 对局 / 图鉴里统一用的"看这里"色（← 原 30 处 bbcode 的 `#ffd95a`，
## 2026-10-04 收编成令牌）。比 GOLD_400 更亮更饱和，专用于正文内联高亮。
const GOLD_HL := Color(1.0, 0.851, 0.353)

# ============================================================================
# 三、反馈色（语义化）。用于「成功/警告/危险/信息」以及任何状态提示。
# ============================================================================

const OK := Color(0.37, 0.75, 0.45)
const WARN := Color(0.88, 0.63, 0.19)
const DANGER := Color(0.85, 0.28, 0.23)
const INFO := Color(0.31, 0.56, 0.84)

## 伤害飘字（`unit_token._spawn_float`）—— 1V1 / 4V4 / 剧情关共用同一套，
## 原先全写在那一个文件里，收上来是为了以后换配色只改一处。
const FX_DODGE := Color(0.72, 0.86, 1.00)   # 闪避（← 原字面量）
const FX_IMMUNE := Color(0.72, 0.95, 1.00)  # 免疫（← 原字面量）
const FX_DAMAGE := Color(1.00, 0.38, 0.32)  # 普通伤害（← 原字面量）
const FX_BLOCK := Color(0.66, 0.78, 0.90)   # 被格挡（← 原字面量）
const FX_BREAK := Color(1.00, 0.84, 0.28)   # 击破（← 原字面量）
const FX_TRUE := Color(1.00, 0.52, 0.30)    # 真伤（← 原字面量）

# ============================================================================
# 四、阵营色。中国习惯：**红 = 我方（红方）**，蓝 = 敌方。与工程现状一致。
#     注意：阵营色 ≠ 血量条色，两者从此分家（旧代码里它们撞过）。
# ============================================================================

const ALLY := Color(0.78, 0.25, 0.18)             # ← 原 COL_RED（3 个文件一致）
const ALLY_SOFT := Color(0.92, 0.47, 0.40)        # 我方：浅态（高亮/描边）
const ENEMY := Color(0.24, 0.42, 0.75)            # ← 原 COL_BLUE（3 个文件一致）
const ENEMY_SOFT := Color(0.50, 0.68, 0.95)       # 敌方：浅态
const ALLY_PIECE := Color(0.80, 0.27, 0.20)       # 棋子实心圆：我方（← 原 unit_token 的 0.80,0.27,0.20，比条色略亮）
const ENEMY_PIECE := Color(0.26, 0.45, 0.80)      # 棋子实心圆：敌方（← 原 unit_token 的 0.26,0.45,0.80）

## ============================ 资源条色 ============================
## ⚠️ 这四种颜色**必须互相可区分**（tests/ui_design_smoke.gd 的 H 段会断言两两间距）。
## 用户 2026-10-04 实报「生命/盾/能量要能区分」——根因是当时同一个「能量」有三种颜色：
##   侧栏用 COL_BLUE(= 敌方阵营蓝 0.24,0.42,0.75)
##   教程用蓝色 (0.35,0.62,0.90)
##   棋子头顶迷你条用琥珀 (0.85,0.65,0.25)
## 而且 `SHIELD` 与旧的 `ENERGY` 都是蓝、几乎同色 → 盾和能量根本分不出。
## 现在统一为**四色四义**：生命=绿 / 护盾=蓝 / 能量=琥珀 / 理智=紫。

const HP := Color(0.42, 0.78, 0.36)               # ← 原 hp_shield_bar.COL_HP　　　绿
const SHIELD := Color(0.33, 0.68, 0.95)           # ← 原 hp_shield_bar.COL_SHIELD　蓝
const ENERGY := Color(0.85, 0.65, 0.25)           # ← 原**棋子迷你条**的琥珀；由蓝改琥珀以与护盾区分
const SANITY := Color(0.62, 0.48, 0.82)           # ← 原 tutorial.COL_SANITY　　　 紫
const BAR_TRACK := Color(0.04, 0.05, 0.09, 0.9)   # ← 原 UiKit.BAR_BG_COLOR
const BAR_EDGE := Color(0.02, 0.02, 0.04, 0.85)   # 条的深色描边（浅色地形上也能看清边界）
const BAR_NUM := Color(1, 1, 1)                   # ← 原 UiKit.BAR_NUM_COLOR
const BAR_NUM_SHADOW := Color(0, 0, 0, 0.85)      # ← 原 UiKit.BAR_NUM_SHADOW_COLOR
const GHOST := Color(0.97, 0.96, 0.92, 0.85)      # 掉血白条残影（← 原 hp_shield_bar.COL_GHOST）
## ⚠️ `CanvasItem.modulate` 的「无效果」值必须是**纯白**（modulate 是乘法，纯白 = 不变）。
##    不要拿 INK_050(0.97,0.98,1.00) 或 BAR_NUM 代替 —— 前者会整体偏色，后者是语义错位。
const MODULATE_RESET := Color(1, 1, 1, 1)

# ============================================================================
## ============================ RichText(bbcode) 调色板 ============================
## bbcode 只能吃 `#RRGGBB` 字符串，没法直接引用上面的 Color 令牌，所以这里单独放一组。
## 值都由同义 Color 令牌派生 —— **改令牌时这里必须同步**，
## `tests/ui_design_smoke.gd` 的 J 段会逐个校验一致。
##
## ⚠️ 这一组是**给深色底**用的。原先图鉴 / 关卡选择 / 英雄故事 / 右键详情面板是米白纸面，
##    配了一批**深色** hex（`#2e6b3c` `#7a5a10` `#55504a` …）。2026-10-04 面板转深色后
##    那些会变成「深底深字」完全看不见，已全部换到下面这一组（48 处）。
##    J 段还会扫描所有界面脚本，断言**没有**任何对比度不足 3.0 的 bbcode 颜色残留。
const MD_OK := "#5EBF73"      # 地形 / 技能名 / 加成（= OK）
const MD_GOLD := "#FFE08C"    # 标题 / 武器名 / 小标题（= GOLD_400）
const MD_HL := "#FFD95A"      # 正文内联高亮（= GOLD_HL）
const MD_DIM := "#ADB8CC"     # 次要说明（= INK_300）
const MD_MUTED := "#949EB8"   # 更弱 / 障碍 / 分隔（= INK_400）
const MD_INFO := "#4F8FD6"    # 被动（= INFO）
const MD_WARN := "#EB7866"    # 警告 / 被掠夺 / 禁用（= ALLY_SOFT）

# ============================================================================
# 六、棋盘色。暖木/羊皮纸 —— 保留既有观感，但由令牌统一供给，
#     不再和冷调界面各自为政（金描边是两套体系之间的"桥"）。
# ============================================================================

const BOARD_BG := Color(0.20, 0.18, 0.16)         # ← 原 COL_BG（4 个文件一致）
const BOARD_LIGHT := Color(0.93, 0.87, 0.74)      # 浅格：羊皮纸（← 原 COL_LIGHT）
const BOARD_DARK := Color(0.55, 0.40, 0.28)       # 深格：木（← 原 COL_DARK）
const BOARD_FRAME := Color(0.15, 0.12, 0.10)      # 格线/外框（← 原 COL_BORDER）
const BOARD_TEXT := Color(0.18, 0.13, 0.09)       # 羊皮纸格上的正文（← 原 duel/team_duel 的 COL_TEXT）
const SPAWN := Color(0.40, 0.56, 0.74)            # 出生格底色（x==0 / x==4，← 原 COL_WING）
const SPAWN_EDGE := Color(0.16, 0.28, 0.44)       # 出生格描边（← 原 COL_WING_EDGE）
const CELL_HL_MOVE := Color(0.45, 0.85, 0.45)     # 可移动高亮（← 原 COL_MOVE）
const CELL_HL_CAST := Color(0.95, 0.80, 0.30)     # 技能落点高亮（← 原 COL_CAST）

# ============================================================================
# 七、表面与覆盖层。
#     ⚠️ 用户铁律：**弹窗背景必须不透明**（SURFACE_MODAL）。
#     SURFACE_PANEL 保留半透，因为它是对局 HUD 侧栏（要看得到棋盘），不是弹窗。
# ============================================================================

const APP_BG := Color(0.102, 0.125, 0.208)        # 主菜单纯色兜底底（← 原 BG_COLOR）
const SURFACE_PANEL := Color(0.10, 0.12, 0.19, 0.94)   # 对局侧栏 / 棋盘上的浮层（← 原 COL_PANEL）
const SURFACE_CARD := INK_800                      # 卡片：**不透明**
const SURFACE_MODAL := INK_900                     # 弹窗/对话框：**不透明**（铁律）
const OVERLAY_DIM := Color(0.05, 0.07, 0.12, 0.45)     # 菜单背景视频压暗（← 原 MENU_BG_DIM）
const OVERLAY_SCRIM := Color(0.0, 0.0, 0.0, 0.55)      # 模态遮罩（点外部关闭用）
## ============================ 玻璃与卡片（透出背景视频）============================
## ⚠️ 2026-10-04：原先「图鉴 / 关卡选择 / 英雄故事」是一整套**浅色羊皮纸**子主题
##   （米白底 + 奶油按钮 + 暖棕描边 + 深墨字）。那是历史遗留，和其余深色界面**是两套世界观** ——
##   在视频背景的主菜单上突然出现一大块米白，看起来像另一个产品。
##   现已全部收进深色玻璃体系；"书卷气"改由**宋体标题 + 金描边**来表达（不靠米白底色）。
const SURFACE_GLASS := Color(0.06, 0.07, 0.12, 0.88)          # 深色玻璃：图鉴/关卡列表页（透出背景视频）
const SURFACE_GLASS_DEEP := Color(0.04, 0.05, 0.09, 0.96)     # 深色详情页（更实，保证正文清晰）
const SURFACE_CARD_GLASS := Color(0.145, 0.176, 0.271, 0.75)  # 主菜单卡片（透出视频）← 原字面量
const SURFACE_CARD_DIM := Color(0.10, 0.12, 0.19, 0.62)       # 侧卡（半露、压暗）
const TEXT_SHADOW := Color(0.08, 0.06, 0.04, 0.55)            # 大标题投影 ← 原字面量
const GOLD_DIM := Color(0.941, 0.780, 0.369, 0.5)             # 半透金：装饰描边 ← 原字面量
const MODULATE_DIM := Color(1, 1, 1, 0.55)                    # 变暗（侧卡箭头/图标）← 原字面量
const MODULATE_SOFT := Color(1, 1, 1, 0.75)                   # 轻微变暗 ← 原字面量

# ============================================================================
# 八、按钮三态。对应原 UiKit.style_button —— 金色只给主 CTA，次级一律走这套墨色。
# ============================================================================

const BTN_BG := Color(0.10, 0.12, 0.19, 0.9)      # ← 原 UiKit normal
const BTN_BG_HOVER := INK_650                      # ← 原 UiKit hover
const BTN_BG_PRESSED := Color(0.08, 0.09, 0.15)   # ← 原 UiKit pressed
const BTN_BORDER := Color(0.45, 0.42, 0.30)       # ← 原 UiKit normal border
const BTN_TEXT := INK_100                          # ← 原 UiKit TEXT_COLOR
const BTN_TEXT_HOVER := GOLD_300                   # ← 原 UiKit TEXT_HOVER_COLOR
const BTN_TEXT_ON_GOLD := Color(0.12, 0.09, 0.05) # 金底上的深字（← 原 main_ui 主按钮字色）

# ============================================================================
# 九、描边 / 焦点。
#     ★ 焦点环是本工程**原本完全缺失**的一环：没有任何 focus 样式，
#       键盘/手柄操作时看不到"现在选中哪"。这里补上（WCAG 2.4.7）。
# ============================================================================

const BORDER := Color(0.35, 0.32, 0.26)           # 面板描边（← 原 UiKit.PANEL_BORDER_COLOR）
const BORDER_WARM := Color(0.40, 0.36, 0.26)      # 暖调描边 / 分隔（← 原 0.40,0.36,0.26，5 处 / 4 个文件）
const BORDER_SUBTLE := INK_650                     # 极轻分隔线
const BORDER_STRONG := GOLD_600                    # 强调描边
const FOCUS := GOLD_400                            # 焦点环颜色
const FOCUS_WIDTH := 3                             # 焦点环宽度（px，基准分辨率下）

# ============================================================================
# 十、间距（8 点网格）。布局一律从这里取，禁止再出现魔法数字。
# ============================================================================

const SPACE_NONE := 0
const SPACE_XXS := 2
const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24
const SPACE_2XL := 32
const SPACE_3XL := 48
const SPACE_4XL := 64

# ============================================================================
# 十一、圆角。
# ============================================================================

const R_XS := 4
const R_SM := 6
const R_MD := 8        # ← 原 UiKit 按钮圆角
const R_LG := 10
const R_XL := 12
const R_2XL := 16
const R_PILL := 999    # 胶囊

# ============================================================================
# 十二、字号刻度（基准分辨率 1280×720）。
#     所有界面按 _scale 乘这个刻度，不要各自写 int。
# ============================================================================

const FS_XS := 12      # 角标/极小注
const FS_SM := 14      # 紧凑口径条文字（原 compact 分支）
const FS_BASE := 16    # 正文
const FS_LG := 18      # 次级标题
const FS_XL := 20      # 小节标题
const FS_2XL := 24     # 面板标题 / 主按钮
const FS_3XL := 30     # 大标题
const FS_DISPLAY := 44 # 页面标题（原 _build_screen 的 44）
const FS_HERO := 80    # 主视觉标题（原开始界面「战棋」的 80）

# ============================================================================
# 十三、动效。统一时长与曲线，避免"每个界面各自动一下"。
# ============================================================================

const DUR_INSTANT := 0.06   # 状态反馈（颜色变化）
const DUR_FAST := 0.12      # 悬停/按下
const DUR_BASE := 0.18      # 面板出入
const DUR_SLOW := 0.32      # 页面转场
const EASE_OUT := Tween.EASE_OUT
const EASE_IN_OUT := Tween.EASE_IN_OUT
const TRANS := Tween.TRANS_CUBIC

# ============================================================================
# 十四、阴影（分层高度）。StyleBoxFlat 的 shadow_* 用它。
# ============================================================================

const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const SHADOW_SM := 4
const SHADOW_MD := 8
const SHADOW_LG := 14

# ============================================================================
# 十五、层级（z_index）。
#     ★ 本条是 2026-10-05 用户实报「人物显示在设置弹窗上面」后补的。
#
#     Godot 里**同层节点按 z_index 排序**（z_index 相同才按树顺序）。而棋子相关
#     节点自带 z_index（名字标签 120 / 击破特效 110 / DragonBones 骨骼部件由数据给），
#     弹层却**一个都没设**（默认 0）→ 棋子就画在弹窗上面了。
#
#     `unit_info_popup` 早就踩过这个坑、并单独写死了 4096，但 `SettingsLayer`
#     和教程的挖洞遮罩**没跟上**，所以同一个 bug 又犯了一次。
#     现在统一从这里取，并**把棋子侧的层级也收进令牌** ——
#     `ui_design_smoke` 会断言 `Z_OVERLAY > 所有棋子层级`：
#     以后谁把棋子 z 调高而忘了弹层，测试直接变红。
#
#     ⚠️ `Z_OVERLAY` 取 4096 是因为它就是 Godot `z_index` 的**上限**；
#        弹层内部子控件若也要设 z_index，注意 `z_as_relative` 默认开启，
#        父子相加会溢出被钳制（弹层内部一律保持默认 0 即可）。
# ============================================================================

const Z_UNIT_FX := 110        # 棋子击破/闪避等特效（← 原 unit_token.gd 的 z_index = 110）
const Z_UNIT_LABEL := 120     # 棋子头顶名字标签（← 原 unit_token.gd 的 lab.z_index = 120）
const Z_OVERLAY := 4096       # 全屏弹层 / 模态遮罩：**必须高于所有棋子层级**

# ============================================================================
# 十六、工具函数
# ============================================================================

## 把带 alpha 的颜色在给定底色上拍平（算对比度前必须先拍平）。
static func flatten(c: Color, bg: Color) -> Color:
	var a := c.a
	return Color(
		c.r * a + bg.r * (1.0 - a),
		c.g * a + bg.g * (1.0 - a),
		c.b * a + bg.b * (1.0 - a),
		1.0)


## 相对亮度（WCAG 2.x 定义，sRGB 线性化）。
static func luminance(c: Color) -> float:
	var out := 0.0
	var ch := [c.r, c.g, c.b]
	var w := [0.2126, 0.7152, 0.0722]
	for i in range(3):
		var v: float = ch[i]
		v = (v / 12.92) if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
		out += v * w[i]
	return out


## WCAG 对比度（1.0 ~ 21.0）。4.5 以上 = AA 正文达标，3.0 以上 = AA 大字达标。
## [param bg] 若是半透明色，会先在你给的纸上拍平再算。
static func contrast(fg: Color, bg: Color) -> float:
	var paper := Color(0, 0, 0) if bg.a >= 1.0 else INK_950
	var f := flatten(fg, paper)
	var b := flatten(bg, paper)
	var l1 := luminance(f)
	var l2 := luminance(b)
	var hi := maxf(l1, l2)
	var lo := minf(l1, l2)
	return (hi + 0.05) / (lo + 0.05)


## 在两个候选文字色里挑一个对比度更高的（用于"自动保证可读"的场景）。
static func text_on(bg: Color) -> Color:
	return INK_100 if contrast(INK_100, bg) >= contrast(INK_950, bg) else INK_950


## 颜色 → "#RRGGBB"（文档/视觉稿同步用）。
static func to_hex(c: Color) -> String:
	return "#%02X%02X%02X" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


## 面板样式工厂：(底色, 圆角, 描边色) → StyleBoxFlat。
## 这是新代码**唯一**允许的描边面板构造方式。
static func panel(bg: Color = SURFACE_CARD, radius: int = R_XL,
		border: Color = BORDER, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if radius > 0:
		sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb


## 焦点环样式：内描边不撑大尺寸（用 draw_center=false 只画框）。
static func focus_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = FOCUS
	sb.set_border_width_all(FOCUS_WIDTH)
	sb.set_corner_radius_all(R_LG)
	sb.set_expand_margin_all(1.0)
	return sb


## 给面板加一层投影（返回新 StyleBoxFlat，不改原对象）。
static func elevated(sb: StyleBoxFlat, size: int = SHADOW_MD) -> StyleBoxFlat:
	var out: StyleBoxFlat = sb.duplicate()
	out.shadow_color = SHADOW_COLOR
	out.shadow_size = size
	out.shadow_offset = Vector2(0, size * 0.35)
	return out
