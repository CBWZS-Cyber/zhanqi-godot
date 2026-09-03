class_name SkillEffects
## 技能元信息 + 效果函数注册表（剧情模式）。
##
## 给一个英雄加技能的两步：
##   1) 在本文件 DATA 中登记技能元信息（name/kind/energy_cost/cooldown/desc）；
##   2) 在 EFFECTS 中把技能 id 指向一个效果函数，并在下方实现函数体。
##
## 效果函数签名（所有技能统一）：
##   func 效果_xxx(user: BattleUnit, ctx: Dictionary) -> String
##   - user：释放者（被动触发时 = 该英雄自己）
##   - ctx ：战斗上下文字典，至少约定：
##       ctx["targets"] : Array[BattleUnit]（主动技能的目标，被动可为空）
##       ctx["battle"]  : 战斗层对象（未来提供，目前可传 {}）
##   - 返回 String：本效果产生的一条战斗日志文本（可为空字符串）
##
## 护盾相关说明：BattleUnit.shield 初始恒为 0，战斗中的护盾只能由本文件的
## “护盾技能/效果”加出来（add_shield / set_shield）。英雄基础属性里不放护盾值。

const DATA := {
	# 被动技能示例（后续由剧情英雄数据替换/新增）
	"stub_passive": {
		"name": "模板被动",
		"element": "光",
		"kind": "passive",
		"desc": "占位被动，效果待填写。",
	},
	# 主动技能示例
	"stub_skill_1": {
		"name": "模板攻击",
		"element": "火",
		"kind": "active",
		"energy_cost": 10,
		"cooldown": 0,
		"desc": "占位主动技能，效果待填写。",
	},
	"stub_skill_2": {
		"name": "模板护盾",
		"element": "—",
		"kind": "active",
		"energy_cost": 15,
		"cooldown": 2,
		"desc": "给自己加一层护盾（示例调用 add_shield）。",
	},
	"stub_skill_3": {
		"name": "模板治疗",
		"element": "光",
		"kind": "active",
		"energy_cost": 20,
		"cooldown": 0,
		"desc": "治疗自己（示例调用 heal）。",
	},
	"stub_skill_4": {
		"name": "模板爆发",
		"element": "雷",
		"kind": "active",
		"energy_cost": 30,
		"cooldown": 3,
		"desc": "占位大招，效果待填写。",
	},

	# ===== 元晶龙王（老方案 = 英雄资料汇总 01）=====
	## 元晶：开局 3 枚，从第 2 回合起每回合初 +1（引擎 counters start_round 自动处理）
	"yuan_jing_mark": {
		"name": "元晶印记",
		"element": "元",
		"kind": "passive",
		"desc": "初始持有 3 枚元晶，从第 2 回合起每回合初获得 1 枚元晶。",
	},
	"ning_cheng_jian_ren": {
		"name": "凝元晶为刃",
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "消耗 1 枚元晶，对 1 个目标造成 3 点伤害。",
	},
	"hua_jing_kai": {
		"name": "化晶为铠",
		"element": "元",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "消耗 2 枚元晶，获得 3 点护盾并回复 2 点能量。",
	},
	"sui_jing_zhan": {
		"name": "碎晶斩",
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "自身有护盾时，清空护盾，对 1 个目标造成 3 点真实伤害（无护盾无法发动）。",
	},
	"yu_jing_wei_long": {
		"name": "御晶为龙",
		"element": "元",
		"kind": "ultimate",
		"energy_cost": 9,
		"cooldown": 0,
		"desc": "消耗 3 枚元晶，对最多 3 个目标各造成 2 点伤害，并获得 1 枚元晶。",
	},

	# ===== 剑舞（王佳欣 · 新版本表；伤害成长/减速/流血/斩杀示范）=====
	"jian_yi": {
		"name": "剑意",
		"element": "金",
		"kind": "passive",
		"desc": "每次使用技能1（瞬击）后，技能1伤害 +1（上限 4）。",
	},
	"shun_ji": {
		"name": "瞬击",
		"element": "金",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程1格，对1个目标造成1点伤害（随剑意成长），目标速度下降10。",
	},
	"duan_liu": {
		"name": "断流",
		"element": "金",
		"kind": "active",
		"energy_cost": 8,
		"cooldown": 0,
		"desc": "射程1格，对1个目标造成减速，目标速度下降50。",
	},
	"guan_chuan": {
		"name": "贯穿",
		"element": "金",
		"kind": "active",
		"energy_cost": 5,
		"cooldown": 0,
		"desc": "射程1格，对1个目标叠加2层流血。",
	},
	"zhu_xin": {
		"name": "诛心",
		"element": "金",
		"kind": "ultimate",
		"energy_cost": 10,
		"cooldown": 0,
		"desc": "射程3格位移型斩杀：只能对生命≤30%的目标使用，将其斩杀；斩杀成功回复8点能量。",
	},

	# ===== 光雨（刘星泽 · 新版本表；星矢印记/眩晕/星河回收）=====
	"xing_he": {
		"name": "星河",
		"element": "光",
		"kind": "passive",
		"desc": "每回合能量回复提升为 2 点；每两回合回复 3 点生命值、2 点能量。（引擎 turn_start_effects 自动处理）",
	},
	"guang_ru_shi": {
		"name": "光如矢",
		"element": "光",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程3格，对1个目标造成2点伤害并加1层「星矢」；目标星矢满3层时清空并眩晕1回合，自身获得1层星河。",
	},
	"shi_ru_yu": {
		"name": "矢如雨",
		"element": "光",
		"kind": "active",
		"energy_cost": 6,
		"cooldown": 0,
		"desc": "射程3格，对最多4个目标各造成2点伤害，目标速度降低2。",
	},
	"yu_ru_xing": {
		"name": "雨如星",
		"element": "光",
		"kind": "active",
		"energy_cost": 6,
		"cooldown": 0,
		"desc": "射程2格，对1个目标造成3点伤害，目标+2层「星矢」，自身+1层星河。",
	},
	"xing_ru_he": {
		"name": "星如河",
		"element": "光",
		"kind": "ultimate",
		"energy_cost": 8,
		"cooldown": 0,
		"desc": "消耗3层星河，对1个目标造成5点伤害，全体敌人+1层星矢并失明1级。",
	},

	# ===== 药师（杨鑫翰 · 新版本表；以“牺牲自身生命”为代价的辅助/输出）=====
	"gao_yu": {
		"name": "膏腴",
		"element": "木",
		"kind": "passive",
		"desc": "初始无能量，能量无上限。生命≤4时每回合末回复1点生命、获得1点护盾（引擎 turn_end_effects 处理）。",
	},
	"jian_mu_sheng_fa": {
		"name": "建木生发",
		"element": "木",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程2格：消耗等同于目标当前生命一半的生命值，造成目标已损生命一半的伤害，回复等同于消耗生命值的能量。",
	},
	"shou_wan_huo_zu": {
		"name": "寿瘟祸祖",
		"element": "木",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "消耗一半当前生命：随机清除自身一种负面状态，对附近敌人造成3点伤害。",
	},
	"shi_zhe_yi_xin": {
		"name": "莳者一心",
		"element": "木",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "回复2点生命、2点能量，获得1点护盾。",
	},
	"yao_ling": {
		"name": "药灵",
		"element": "圣灵",
		"kind": "ultimate",
		"energy_cost": 12,
		"cooldown": 0,
		"desc": "生命降至1并获得等同于消耗生命值一半的护盾，本回合内血量最低为1（锁血），并对相邻敌人造成等同于当前护盾量的伤害。",
	},


	# ===== 孤狼（叶麟）=====
	"duan_ti": {"name": "锻体", "element": "物理", "kind": "passive",
		"desc": "每次受到伤害，对该攻击者的伤害免伤 +5%（对同一人最高 20%）。"},
	"yin_yang_san_shou": {"name": "阴阳散手", "element": "物理", "kind": "active", "energy_cost": 4,
		"desc": "进入阴状态防守：获得 15% 减伤并嘲讽相邻目标；受击 3 次后转阳，阳持续 2 回合，期间 50% 反伤。"},
	"shen_suo_quan": {"name": "伸缩拳", "element": "物理", "kind": "active", "energy_cost": 6,
		"desc": "相邻目标 4 伤，或两格目标 2 伤。击中两格目标使其禁大招 2 回合（嘲讽）；击中相邻目标时自身获得对该目标的 5% 免伤（对同一人上限 30%）。"},
	"pu_tong_quan": {"name": "普通拳", "element": "物理", "kind": "active", "energy_cost": 0,
		"desc": "对目标造成 2 点伤害；对被嘲讽的目标追加 1 点真实伤害。回复 2 能量。"},
	"xue_yu": {"name": "血狱", "element": "物理", "kind": "ultimate", "energy_cost": 10,
		"desc": "对两格内一个目标造成其已损生命 15% 的伤害；范围内每有 1 个目标自身获得 5% 免伤（总上限 40%）。"},

	# ===== rapper睡神（何至高）=====
	"kuang_nu": {"name": "狂怒", "element": "神秘", "kind": "passive",
		"desc": "生命值低于 20% 时伤害翻倍（hp_threshold_flags 自动管理）。"},
	"lve_duo": {"name": "掠夺", "element": "神秘", "kind": "active", "energy_cost": 8,
		"desc": "掠夺相邻一个敌人身上的一个技能（大招除外）：该敌人本局无法再使用它，自己下回合起可使用（技能槽由战斗层替换显示）。"},
	"mei_huo": {"name": "魅惑", "element": "毒", "kind": "active", "energy_cost": 5,
		"desc": "选择两格内 2 个目标，使其本回合无法造成伤害。"},
	"suo_xue": {"name": "锁血", "element": "火", "kind": "active", "energy_cost": 0,
		"desc": "本回合内无敌，回复 1 点生命、2 点能量。"},
	"wan_li_bing_feng": {"name": "万里冰封", "element": "冰", "kind": "ultimate", "energy_cost": 12,
		"desc": "三格内所有敌人进入冻伤1级（速度-20，每回合末受1真伤，持续2回合）并受到 3 点伤害。"},

	# ===== 仙尊（陈雨晴）=====
	"nie_pan": {"name": "涅槃", "element": "圣灵", "kind": "passive",
		"desc": "死亡后复活，回复一半生命（每局一次，引擎 death_revive）。每回合末回复 4 能量。"},
	"wu_xing_zhi_li": {"name": "五行之力", "element": "五行", "kind": "active", "energy_cost": 9,
		"desc": "随机发射一道五行法力（金木水火土），对相邻格最多 3 个敌人各造成 2 点伤害。"},
	"shu_fu_zhi_ling": {"name": "束缚之灵", "element": "木", "kind": "active", "energy_cost": 13,
		"desc": "至本回合末，相邻格子内的敌人无法使用技能。"},
	"zhuan_jia_kui_lei": {"name": "转嫁傀儡", "element": "土", "kind": "active", "energy_cost": 15,
		"desc": "指定敌方一人转移到仙尊相邻空格（位移由战斗层执行），并对其造成已损生命 20% 的伤害。"},
	"wan_jian_gui_zong": {"name": "万剑归宗", "element": "金", "kind": "ultimate", "energy_cost": 18,
		"desc": "两格范围内所有敌人每回合末受 2 点真伤，持续 3 回合（剑域）。"},

	# ===== 灵虚数影（辛子祺）=====
	"shu_yu": {"name": "数域", "element": "神秘", "kind": "passive",
		"desc": "对一切攻击（必中除外）90% 闪避；相邻友军 +5% 闪避（aura 由战斗层提供）。"},
	"tian_ji": {"name": "天机", "element": "神秘", "kind": "active", "energy_cost": 6,
		"desc": "识破弱点：下回合自身（及周围棋子，aura 由战斗层）伤害 1.5 倍。"},
	"jie_xi": {"name": "解析", "element": "神秘", "kind": "active", "energy_cost": 8,
		"desc": "两格内单目标 3 点伤害，并造成破甲二级（护甲-2，持续3回合）。"},
	"ji_dian": {"name": "极点", "element": "神秘", "kind": "active", "energy_cost": 0,
		"desc": "推演极点，获得启发：回复 5 点能量、1 点护盾。"},
	"shu_hai_teng_nuo": {"name": "数海腾挪", "element": "神秘", "kind": "ultimate", "energy_cost": 24,
		"desc": "同时释放天机与解析，且本回合及下回合无法被选中。"},

	# ===== 辛克莱（新表已定稿：理智上限25 初始0，可为负）=====
	"he_bi": {"name": "何必如此", "element": "火", "kind": "passive",
		"desc": "无能量机制，专属理智值（上限25，初始0）。每回合末回复30%缺损理智；使用技能使理智变负时下回合失控（随机放技不分敌我），随后回合末理智归0。"},
	"po_bu_de_yi": {"name": "迫不得已的审判", "element": "火", "kind": "active", "energy_cost": 0,
		"desc": "向一个方向突进2格（战斗层）：穿过棋子则造成 2 点伤害，目标获得烧伤（持续中再获得则刷新时长）；理智 -7。"},
	"hei_bai": {"name": "黑白不分的执行", "element": "火", "kind": "active", "energy_cost": 0,
		"desc": "向一个方向快速突进直到碰壁（人或障碍）：对撞到的棋子造成 3 点伤害并施加 2 层重伤；理智 -10。"},
	"zi_wo_destroy": {"name": "自我毁灭的审判", "element": "物理", "kind": "active", "energy_cost": 0,
		"desc": "向周围3格内某地点传送（战斗层），对周围格子敌人造成 2 点伤害、施加 3 层重伤；自身失去 3×命中数 理智。"},
	"xuan_zhong": {"name": "因为我是被选中的", "element": "物理", "kind": "ultimate", "energy_cost": 0,
		"desc": "向前冲刺3格（战斗层）：对被穿过的棋子造成其已损生命 20% 的真伤；若其身上重伤≥4 层，再施加烧伤；理智 -15。"},
	# 状态规则（烧伤：速度-10，每回合末1真伤，持续2回合，刷新式。重伤：受击额外 0.5×层真伤，回合末层-1）


	# ===== 追猎（孙广泽 · 新版本表；创伤/流血/灼烧体系示范）=====
	"zhuilie_ymxb": {
		"name": "以命相搏",
		"element": "机械",
		"kind": "passive",
		"desc": "生命值≤3时，速度增加200点，护甲清零，每回合获得2点护盾。",
	},
	"snap_shot": {
		"name": "狙击",
		"element": "机械",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程3格，对1个目标造成1点伤害，附加「创伤」印记；积累3层时清空印记并触发「流血2级」。",
	},
	"hunt": {
		"name": "追猎",
		"element": "机械",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "位移后额外发动一次「狙击」。（位移由战斗层执行）",
	},
	"shield_up": {
		"name": "架盾",
		"element": "机械",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "获得2点护盾，护甲+1（上限3）。",
	},
	"meteor_shot": {
		"name": "流星飞弹",
		"element": "机械",
		"kind": "ultimate",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "全图射程，攻击2个目标各造成3点伤害，附加「灼烧1级」；若目标已有「流血2级」则升为「流血3级」；护甲-1。一局仅限一次。",
	},

	# ===== 邪神（王泽）· 同学设计 + 用户改版 2026-09-03 =====
	## 污染层 = 每层使目标速度 -15；层数 ≥3 → 失神
	"ji_sheng": {
		"name": "寄生",
		"element": "暗",
		"kind": "passive",
		"desc": "每回合末向附近格子内的敌人 +1 层污染。每层污染使该单位速度 -15；污染 ≥3 时进入失神状态。",
	},
	"hun_qi": {
		"name": "替死",
		"element": "暗",
		"kind": "active",
		"energy_cost": 7,
		"cooldown": 0,
		"desc": "本回合所有伤害由失神状态下的敌方棋子均摊；回合末吸取失神敌当前生命的 30%。（伤害均摊需战斗层接伤害管线）",
	},
	"zhi_pei": {
		"name": "支配",
		"element": "暗",
		"kind": "active",
		"energy_cost": 10,
		"cooldown": 0,
		"desc": "对周围敌人触发：污染 ≥5 时消耗 3 层，支配该单位 2 回合（下一回合起生效）。单挑模式：污染 ≥8 直接斩杀敌方并获胜。",
	},
	"qin_ran": {
		"name": "侵染",
		"element": "暗",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "对周围所有敌人造成 1 点伤害；60% 概率使每个目标额外 +1 污染；回复 5 点能量。",
	},
	"hei_shan": {
		"name": "黑闪",
		"element": "暗",
		"kind": "active",
		"energy_cost": 15,
		"cooldown": 0,
		"desc": "对周围所有敌人触发：消耗其全部污染层，每层使其失去 10% 最大生命；原污染 ≥6：4V4 永久支配该单位，单挑直接斩杀获胜。",
	},
}

## 效果注册表：id -> Callable
const EFFECTS := {
	"stub_passive": Callable(SkillEffects, "_ef_stub_passive"),
	"stub_skill_1": Callable(SkillEffects, "_ef_stub_attack"),
	"stub_skill_2": Callable(SkillEffects, "_ef_stub_shield"),
	"stub_skill_3": Callable(SkillEffects, "_ef_stub_heal"),
	"stub_skill_4": Callable(SkillEffects, "_ef_stub_burst"),
	# 元晶龙王（老方案）
	"yuan_jing_mark": Callable(SkillEffects, "_ef_yuan_jing_mark"),
	"ning_cheng_jian_ren": Callable(SkillEffects, "_ef_ning_cheng_jian_ren"),
	"hua_jing_kai": Callable(SkillEffects, "_ef_hua_jing_kai"),
	"sui_jing_zhan": Callable(SkillEffects, "_ef_sui_jing_zhan"),
	"yu_jing_wei_long": Callable(SkillEffects, "_ef_yu_jing_wei_long"),
	# 剑舞（王佳欣）
	"jian_yi": Callable(SkillEffects, "_ef_jian_yi"),
	"shun_ji": Callable(SkillEffects, "_ef_shun_ji"),
	"duan_liu": Callable(SkillEffects, "_ef_duan_liu"),
	"guan_chuan": Callable(SkillEffects, "_ef_guan_chuan"),
	"zhu_xin": Callable(SkillEffects, "_ef_zhu_xin"),
	# 光雨（刘星泽）
	"xing_he": Callable(SkillEffects, "_ef_xing_he"),
	"guang_ru_shi": Callable(SkillEffects, "_ef_guang_ru_shi"),
	"shi_ru_yu": Callable(SkillEffects, "_ef_shi_ru_yu"),
	"yu_ru_xing": Callable(SkillEffects, "_ef_yu_ru_xing"),
	"xing_ru_he": Callable(SkillEffects, "_ef_xing_ru_he"),
	# 药师（杨鑫翰）
	"gao_yu": Callable(SkillEffects, "_ef_gao_yu"),
	"jian_mu_sheng_fa": Callable(SkillEffects, "_ef_jian_mu_sheng_fa"),
	"shou_wan_huo_zu": Callable(SkillEffects, "_ef_shou_wan_huo_zu"),
	"shi_zhe_yi_xin": Callable(SkillEffects, "_ef_shi_zhe_yi_xin"),
	"yao_ling": Callable(SkillEffects, "_ef_yao_ling"),

	# 孤狼（叶麟）
	"duan_ti": Callable(SkillEffects, "_ef_duan_ti"), "yin_yang_san_shou": Callable(SkillEffects, "_ef_yyss"),
	"shen_suo_quan": Callable(SkillEffects, "_ef_ssq"), "pu_tong_quan": Callable(SkillEffects, "_ef_ptq"),
	"xue_yu": Callable(SkillEffects, "_ef_xue_yu"),
	# rapper睡神（何至高）
	"kuang_nu": Callable(SkillEffects, "_ef_kn"), "lve_duo": Callable(SkillEffects, "_ef_lve"),
	"mei_huo": Callable(SkillEffects, "_ef_meihuo"), "suo_xue": Callable(SkillEffects, "_ef_suoxue"),
	"wan_li_bing_feng": Callable(SkillEffects, "_ef_wanli"),
	# 仙尊（陈雨晴）
	"nie_pan": Callable(SkillEffects, "_ef_niepan"), "wu_xing_zhi_li": Callable(SkillEffects, "_ef_wuxing"),
	"shu_fu_zhi_ling": Callable(SkillEffects, "_ef_shufu"), "zhuan_jia_kui_lei": Callable(SkillEffects, "_ef_zhuanjia"),
	"wan_jian_gui_zong": Callable(SkillEffects, "_ef_wanjian"),
	# 灵虚数影
	"shu_yu": Callable(SkillEffects, "_ef_shuyu"), "tian_ji": Callable(SkillEffects, "_ef_tianji"),
	"jie_xi": Callable(SkillEffects, "_ef_jiexi"), "ji_dian": Callable(SkillEffects, "_ef_jidian"),
	"shu_hai_teng_nuo": Callable(SkillEffects, "_ef_shuhai"),
	# 辛克莱
	"he_bi": Callable(SkillEffects, "_ef_hebi"), "po_bu_de_yi": Callable(SkillEffects, "_ef_pbdy"),
	"hei_bai": Callable(SkillEffects, "_ef_heibai"), "zi_wo_destroy": Callable(SkillEffects, "_ef_zishu"),
	"xuan_zhong": Callable(SkillEffects, "_ef_xuanzhong"),

	# 追猎（孙广泽）
	"zhuilie_ymxb": Callable(SkillEffects, "_ef_zl_ymxb"),
	"snap_shot": Callable(SkillEffects, "_ef_snap_shot"),
	"hunt": Callable(SkillEffects, "_ef_hunt"),
	"shield_up": Callable(SkillEffects, "_ef_shield_up"),
	"meteor_shot": Callable(SkillEffects, "_ef_meteor_shot"),
	# 邪神（王泽）
	"ji_sheng": Callable(SkillEffects, "_ef_ji_sheng"),
	"hun_qi": Callable(SkillEffects, "_ef_hun_qi"),
	"zhi_pei": Callable(SkillEffects, "_ef_zhi_pei"),
	"qin_ran": Callable(SkillEffects, "_ef_qin_ran"),
	"hei_shan": Callable(SkillEffects, "_ef_hei_shan"),
}

## 兜底：未注册效果的技能
static func effect_stub(_user: BattleUnit, _ctx: Dictionary) -> String:
	return "（效果未实现）"

## ---------- 下方是各技能效果的“填写区” ----------
## 用户之后逐个把函数体替换成真正的效果逻辑，并在 EFFECTS 中保持映射即可。
## 常用数值操作速查（battle_unit.gd）：
##   user.take_damage(x) -> 扣血（护盾吸收→护甲减免）
##   user.lose_hp(x)      -> 无视护盾直接扣血
##   user.heal(x)         -> 回血
##   user.add_shield(x) / set_shield(x) / remove_shield(x) / clear_shield()
##   user.add_energy(x) / user.spend_energy(x)
##   ctx.get("targets", []) 可取目标数组（BattleUnit）

static func _ef_stub_passive(user: BattleUnit, _ctx: Dictionary) -> String:
	# TODO: 被动效果（例如“每回合开始回 X 血/加 X 盾”等）
	return "%s 的【模板被动】触发（效果待填写）" % user.name

static func _ef_stub_attack(user: BattleUnit, ctx: Dictionary) -> String:
	# TODO: 主动技能效果
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【模板攻击】" % user.name
	for t in targets:
		var r: Dictionary = t.take_damage(20)
		out += "，对 %s 造成 %d 伤害" % [t.name, r["hp_lost"] + r["absorbed"]]
	return out

static func _ef_stub_shield(user: BattleUnit, _ctx: Dictionary) -> String:
	# 示例：护盾函数用法 —— 给 30 护盾
	var before := user.shield
	user.add_shield(30)
	return "%s 获得护盾 %d → %d" % [user.name, 30, user.shield]

static func _ef_stub_heal(user: BattleUnit, _ctx: Dictionary) -> String:
	var amount := user.heal(25)
	return "%s 恢复 %d 生命（%d/%d）" % [user.name, amount, user.hp, user.max_hp]

static func _ef_stub_burst(user: BattleUnit, _ctx: Dictionary) -> String:
	# TODO: 大招效果
	return "%s 释放【模板爆发】（效果待填写）" % user.name

## ========== 元晶龙王（老方案）效果 ==========
## 元晶 = 计数资源池（BattleUnit.counter / grant_counter / consume_counter）；
## 自动增长由 counters{"元晶": start3, per_turn1, start_round2} 引擎维护（第 2 回合起 +1）。

## 被动（展示；增长由引擎处理）
static func _ef_yuan_jing_mark(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【元晶印记】生效：当前元晶 %d 枚（第 2 回合起每回合 +1）" % [user.name, user.counter("元晶")]

## 凝元晶为刃：耗 1 元晶 → 单体 3 伤
static func _ef_ning_cheng_jian_ren(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("元晶") < 1:
		return "%s 元晶不足，【凝元晶为刃】无法发动" % user.name
	user.consume_counter("元晶", 1)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【凝元晶为刃】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
	if targets.is_empty():
		out += "（无目标）"
	return out

## 化晶为铠：耗 2 元晶 → 3 盾 + 回 2 能
static func _ef_hua_jing_kai(user: BattleUnit, _ctx: Dictionary) -> String:
	if user.counter("元晶") < 2:
		return "%s 元晶不足 2 枚，【化晶为铠】无法发动" % user.name
	user.consume_counter("元晶", 2)
	user.add_shield(3)
	var got := user.add_energy(2)
	return "%s 消耗 2 枚元晶：护盾 +3（现 %d），回复 %d 能量（%d/%d）" % [user.name, user.shield, got, user.energy, user.max_energy]

## 碎晶斩：自身有盾 → 清空护盾，单体 3 真伤（无盾无法发动）
static func _ef_sui_jing_zhan(user: BattleUnit, ctx: Dictionary) -> String:
	if user.shield <= 0:
		return "%s 没有护盾，【碎晶斩】无法发动（先用化晶为铠等获取护盾）" % user.name
	var before_shield := user.shield
	user.clear_shield()
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【碎晶斩】（清空 %d 点护盾）" % [user.name, before_shield]
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var before := tu.hp
		tu.lose_hp(3)
		out += "；%s 受 %d 真伤" % [tu.name, before - tu.hp]
	if targets.is_empty():
		out += "（无目标）"
	return out

## 御晶为龙（终极）：耗 3 元晶 → 至多 3 目标各 2 伤 + 回 1 元晶
static func _ef_yu_jing_wei_long(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("元晶") < 3:
		return "%s 元晶不足 3 枚，【御晶为龙】无法发动" % user.name
	user.consume_counter("元晶", 3)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【御晶为龙】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		hit += 1
	user.grant_counter("元晶", 1)
	out += "；收回 1 枚元晶（现 %d）" % user.counter("元晶")
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 邪神（王泽）效果 ==========
## 污染层：挂在每个目标自己身上（target.counter("污染")），每层速度 -15，≥3 层失神。
## 同步速度惩罚/失神标志的公共维护：
static func _pollute(t: BattleUnit, n: int) -> void:
	# 施加端注册污染规则（幂等）：每层 -15 速、≥3 层失神。敌方单位无需自带配置。
	t.watch_layer_speed("污染", 15)
	t.watch_layer_flag("污染", 3, "失神")
	t.grant_counter("污染", n)

## 被动寄生：回合末对“附近敌人”（ctx.targets）各 +1 污染
static func _ef_ji_sheng(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 的【寄生】回合末发动" % user.name
	if targets.is_empty():
		return out + "（附近无敌人）"
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		_pollute(tu, 1)
		out += "；%s 污染 +1（共 %d，速度 %d）" % [tu.name, tu.counter("污染"), tu.effective_speed()]
	return out

## 一技能·替死：登记本回合分担/回合末吸血（伤害均摊需战斗层拦截伤害管线）
static func _ef_hun_qi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	user.begin_share_round(targets)
	return "%s 立下【替死】：本回合伤害由失神敌人均摊，回合末吸取失神敌当前生命的 30%%" % user.name

## 二技能·支配：周围敌人触发；目标污染≥5 → 耗 3 层，支配 2 回合（下回合起）；
## 单挑模式：目标污染 ≥8 → 斩杀获胜
static func _ef_zhi_pei(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var mode := str(ctx.get("mode", "4v4"))
	var out := "%s 释放【支配】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if mode == "1v1":
			if tu.counter("污染") >= 8:
				tu.lose_hp(tu.hp)
				out += "；单挑斩杀 %s（污染 %d ≥ 8）→ 邪神获胜" % [tu.name, tu.counter("污染")]
				_call_win(ctx)
			else:
				out += "；%s 污染 %d 不足 8，无法斩杀" % [tu.name, tu.counter("污染")]
			continue
		if tu.counter("污染") < 5:
			out += "；%s 污染 %d 不足 5" % [tu.name, tu.counter("污染")]
			continue
		tu.consume_counter("污染", 3)
		tu.add_flag("将被支配")            # 下一回合起生效（战斗层读）
		tu.set_meta("dominate_rounds", 2)  # 持续 2 回合
		out += "；%s 被支配 2 回合（污染≥5，耗3层，现 %d）" % [tu.name, tu.counter("污染")]
	return out

## 三技能·侵染：周围所有敌人 2 伤；60% 概率额外 +1 污染；回 5 能量 + 回 2 生命
static func _ef_qin_ran(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【侵染】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(1)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		if randf() < 0.6:
			_pollute(tu, 1)
			out += "，污染+1（共 %d）" % tu.counter("污染")
	user.add_energy(5)
	out += "；回复 5 能量（%d/%d）" % [user.energy, user.max_energy]
	return out

## 大招·黑闪：周围敌人——耗其全部污染层，每层失去 10% 最大生命；
## 原污染 ≥6：4V4 永久支配；单挑改为斩杀获胜
static func _ef_hei_shan(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var mode := str(ctx.get("mode", "4v4"))
	var out := "%s 释放【黑闪】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var layers := tu.counter("污染")
		if layers > 0:
			tu.consume_counter("污染", layers)
			var loss := ceili(float(tu.max_hp) * 0.1 * float(layers))
			var r: Dictionary = tu.take_damage(loss)
			out += "；%s 失去 %d 点生命（%d 层×10%%）" % [tu.name, r["hp_lost"] + r["absorbed"], layers]
		if layers >= 6:
			if mode == "1v1":
				tu.lose_hp(tu.hp)
				out += "，单挑斩杀 %s → 邪神获胜" % tu.name
				_call_win(ctx)
			else:
				tu.add_flag("永久支配")
				out += "，%s 被永久支配" % tu.name
	return out

static func _call_win(ctx: Dictionary) -> void:
	var hook: Variant = ctx.get("on_win", null)
	if hook is Callable:
		(hook as Callable).call()

## ========== 通用工具（写新英雄效果时直接调用，避免重复循环） ==========

## 对一组目标造成伤害（true_dmg=true 走真伤 lose_hp）。返回追加的日志片段。
static func hit_group(targets: Array, dmg: int, true_dmg := false) -> String:
	var out := ""
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if true_dmg:
			var before := tu.hp
			tu.lose_hp(dmg)
			out += "，%s 受 %d 真伤" % [tu.name, before - tu.hp]
		else:
			var r: Dictionary = tu.take_damage(dmg)
			out += "，%s 受 %d 伤害" % [tu.name, r["hp_lost"] + r["absorbed"]]
	return out

## 目标失去“最大生命 N%”（每层×pct 的百分比扣血用），返回实际损失量
static func lose_pct_max_hp(t: BattleUnit, pct_per: int, times: int) -> int:
	var loss := ceili(float(t.max_hp) * 0.01 * float(pct_per) * float(times))
	if loss > 0:
		t.lose_hp(loss)
	return loss

## 给一组目标各 +n 层资源（自动触发 layer_rules）
static func grant_layer_each(targets: Array, layer: String, n: int) -> String:
	var out := ""
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.grant_counter(layer, n)
		out += "，%s %s +%d（共 %d）" % [tu.name, layer, n, tu.counter(layer)]
	return out

## ========== 状态/印记公共基元（通用，勿为单个英雄复制） ==========
## 层数制：bleed 流血 / burn 灼烧 / wound 创伤 / freeze 冻伤… 存 unit.statuses
## 结算时机：行动时(施放技能/移动)看 bleed；回合开始时看 burn；回合末 bleed 衰减 1。

static func status_cn(id: String) -> String:
	var m := {
		"bleed": "流血", "burn": "灼烧", "wound": "创伤", "freeze": "冻伤",
		"poison": "中毒", "burn2": "灼烧2",
	}
	return String(m.get(id, id))

## 行动触发（施放技能/移动）：结算自身流血 —— 每层 1 点伤害（未标真伤=普伤），层数不变（回合末才减）
static func tick_action_statuses(u: BattleUnit) -> String:
	var b := u.status_stacks("bleed")
	if b <= 0:
		return ""
	var before := u.hp
	u.take_damage(b)
	return "%s 行动触发流血：失去 %d 点生命（%d/%d）" % [u.name, before - u.hp, u.hp, u.max_hp]

## 回合开始触发：原灼烧逻辑改为回合末结算（新表备注：每回合末1真伤，持续2回合）
static func tick_start_of_turn_statuses(u: BattleUnit) -> String:
	return ""

## 回合末触发：流血层数 -1；冻伤每回合末 1 真伤
static func tick_end_of_turn_statuses(u: BattleUnit) -> String:
	var out := ""
	var b := u.status_stacks("bleed")
	if b > 0:
		u.set_status("bleed", b - 1)
		out += "%s 流血衰减：%d→%d 层" % [u.name, b, u.status_stacks("bleed")]
	var fz := u.status_stacks("freeze")
	if fz > 0:
		var before := u.hp
		u.lose_hp(fz)
		out += "；%s 受冻伤 %d 真伤" % [u.name, before - u.hp]
	var bn := u.status_stacks("burn")
	if bn > 0:
		var bbefore := u.hp
		u.lose_hp(1)
		u.set_status("burn", bn - 1)
		out += "；%s 被烧伤失去 %d 生命（余 %d 回合）" % [u.name, bbefore - u.hp, bn - 1]
		if bn - 1 <= 0:
			u.remove_speed_mod_src("灼烧")
	var hw := u.status_stacks("heavy_wound")
	if hw > 0:
		u.set_status("heavy_wound", hw - 1)
		out += "；%s 重伤衰减 %d→%d 层" % [u.name, hw, hw - 1]
	if u.status_stacks("sword_field") > 0:
		var b2 := u.hp
		u.lose_hp(2)
		out += "；%s 受剑域 2 真伤" % u.name
	return out

## 施加烧伤/灼烧（新表备注：速度-10，每回合末1真伤，持续2回合；再次施加刷新时长）
static func apply_burn(t: BattleUnit, _stacks := 2) -> void:
	t.set_speed_mod_src("灼烧", -10)
	if t.status_stacks("burn") <= 0:
		t.set_status("burn", _stacks)
	else:
		t.set_status("burn", maxi(t.status_stacks("burn"), _stacks))  # 刷新/重置

## 施加重伤（heavy_wound）：受击额外 0.5×层真伤，回合末层-1
static func apply_heavy_wound(t: BattleUnit, stacks: int) -> void:
	t.add_status("heavy_wound", stacks)

## 施加创伤印记（wound）：满 3 层清空并触发「流血2级」
static func add_wound(t: BattleUnit, n: int) -> String:
	t.add_status("wound", n)
	if t.status_stacks("wound") >= 3:
		t.set_status("wound", 0)
		t.add_status("bleed", 2)
		return "，%s 创伤满 3 层 → 触发流血2级" % t.name
	return "，%s 创伤 +%d（共 %d）" % [t.name, n, t.status_stacks("wound")]

## 对目标打一发“狙击”（1 伤 + 创伤）
static func _fire_snap(user: BattleUnit, t: BattleUnit, extra: String) -> String:
	var r: Dictionary = t.take_damage(1)
	var out := "%s%s：%s 受 %d 伤" % [user.name, extra, t.name, r["hp_lost"] + r["absorbed"]]
	out += add_wound(t, 1)
	return out

## ========== 追猎（孙广泽）效果 ==========
## 被动·以命相搏：生命≤3 → 速+200、护甲清零、每回合+2盾（战斗层每回合开始调用 trigger_passive）
static func _ef_zl_ymxb(user: BattleUnit, _ctx: Dictionary) -> String:
	if user.hp <= 3:
		if not user.has_flag("zl_lowhp"):
			user.add_flag("zl_lowhp")
			user.set_speed_buff(200)
			user.set_armor(0)
		user.add_shield(2)
		return "%s 触发【以命相搏】：速度 +200（现 %d）、护甲清零、获得 2 点护盾" % [user.name, user.effective_speed()]
	if user.has_flag("zl_lowhp"):
		user.clear_flag("zl_lowhp")
		user.set_speed_buff(0)
	return "%s 生命 %d/3 以上，【以命相搏】未触发" % [user.name, user.hp]

## 主动1·狙击：单体 1 伤 + 创伤
static func _ef_snap_shot(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【狙击】（无目标）" % user.name
	return _fire_snap(user, targets[0] as BattleUnit, " 释放【狙击】")

## 主动2·追猎：位移后额外发动一次狙击（位移本体由战斗层执行）
static func _ef_hunt(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【追猎】（位移后无目标）" % user.name
	return _fire_snap(user, targets[0] as BattleUnit, " 释放【追猎】位移后额外狙击")

## 主动3·架盾：2 盾 + 护甲+1（上限3）
static func _ef_shield_up(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_shield(2)
	var ag := user.add_armor(1, 3)
	return "%s 释放【架盾】：护盾 +2（现 %d），护甲 +%d（现 %d）" % [user.name, user.shield, ag, user.armor]

## 终极·流星飞弹：至多2目标各3伤 + 灼烧1；已有流血2级→升3级；护甲-1（一局一次由战斗层限制）
static func _ef_meteor_shot(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【流星飞弹】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 2:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		if tu.status_stacks("bleed") >= 2:
			tu.set_status("bleed", 3)
			out += "，流血升级为3级"
		else:
			apply_burn(tu, 2)
			out += "，附加灼烧"
		tu.remove_armor(1)
		out += "，护甲-1"
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 重灾区防护基元（目标/阵营/加成/斩杀/先手） ==========

## 按关系过滤目标：rel = "enemy"(敌对) / "ally"(同队,含自己可选) / "any"
static func filter_by_relation(targets: Array, me: BattleUnit, rel: String, include_self := false) -> Array:
	var out: Array = []
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if not include_self and tu == me:
			continue
		var enemy := tu.team != me.team
		var hit_ok := false
		if rel == "any":
			hit_ok = true
		elif rel == "enemy":
			hit_ok = enemy
		elif rel == "ally":
			hit_ok = not enemy
		if hit_ok:
			out.append(tu)
	return out

## 目标当前生命百分比（0..100，按最大生命）
static func hp_pct(t: BattleUnit) -> int:
	if t.max_hp <= 0:
		return 100
	return int(round(float(t.hp) / float(t.max_hp) * 100.0))

## 条件斩杀：目标当前生命 ≤ 最大生命的 pct% 时直接斩杀（返回真）
static func cut_if_under_pct(t: BattleUnit, pct: int) -> bool:
	if hp_pct(t) <= pct:
		t.lose_hp(t.hp)
		return true
	return false

## 伤害结算走“技能槽伤害加成”：user.slot_damage(slot, base) 后统一打
static func hit_group_slot(user: BattleUnit, slot: int, targets: Array, base: int, true_dmg := false) -> String:
	var dmg := user.slot_damage(slot, base)
	if absf(user.dmg_mult - 1.0) > 0.001:
		dmg = maxi(1, ceili(float(dmg) * user.dmg_mult))
	return hit_group(targets, dmg, true_dmg)

## 按当前 effective_speed 降序（同速保持数组原顺序）。用于：每轮初始排列，
## 以及战斗中任意时刻的“动态重排”。注意：速度变化会立即影响后续行动顺序。
static func speed_order(units: Array) -> Array:
	var lst: Array = []
	for u in units:
		if u is BattleUnit:
			lst.append(u)
	# 冒泡降序（严格大于才交换 → 同速保持原顺序，作为先手快照稳定）
	for i in range(lst.size()):
		for j in range(i + 1, lst.size()):
			var ai: BattleUnit = lst[i]
			var aj: BattleUnit = lst[j]
			if aj.effective_speed() > ai.effective_speed():
				lst[i] = aj
				lst[j] = ai
	return lst


## —— 动态行动判定（Battle 采用）——
## 模型：不冻结“轮内顺序”。每次需要决定下一位行动者时，对所有本轮回合尚未行动
## （或按规则可行动）的单位实时取 effective_speed 最高者；任何减速/加速都立即
## 参与下一次比较。requeue_by_speed 用于在一次行动结算后重排剩余单位。

## 重新按当前速度降序排列（传入剩余待行动单位）
static func requeue_by_speed(remaining: Array) -> Array:
	return speed_order(remaining)

## 取当前“应行动”的单位（速度最高者），无则 null
static func next_actor(units: Array) -> BattleUnit:
	var lst := speed_order(units)
	return lst[0] as BattleUnit if lst.size() > 0 else null

## ========== 剑舞（王佳欣）效果 ==========
## 被动·剑意：成长由瞬击施放后 add_slot_damage(1,1,4) 维护（这里仅展示说明）
static func _ef_jian_yi(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【剑意】生效：瞬击伤害加成 %d（上限4）" % [user.name, int(user.slot_damage(1, 1)) - 1]

## 主动1·瞬击：单体基础1伤（吃剑意成长）+ 目标减速10；施放后剑意+1（封顶4）
static func _ef_shun_ji(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【瞬击】" % user.name
	if targets.is_empty():
		return out + "（无目标）"
	var tu := targets[0] as BattleUnit
	out += hit_group_slot(user, 1, [tu], 1)
	tu.add_speed_mod_src("剑舞:瞬击", -10)
	out += "；%s 速度 -10（现 %d）" % [tu.name, tu.effective_speed()]
	var gained := user.add_slot_damage(1, 1, 4)
	if gained > 0:
		out += "；剑意 +1（伤害加成 %d/4）" % (int(user.slot_damage(1, 1)) - 1)
	return out

## 主动2·断流：单体减速 50
static func _ef_duan_liu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【断流】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	tu.add_speed_mod_src("剑舞:断流", -50)
	return "%s 释放【断流】：%s 速度 -50（现 %d）" % [user.name, tu.name, tu.effective_speed()]

## 主动3·贯穿：目标叠 2 层流血
static func _ef_guan_chuan(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【贯穿】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	tu.add_status("bleed", 2)
	return "%s 释放【贯穿】：%s 流血 +2（现 %d 层）" % [user.name, tu.name, tu.status_stacks("bleed")]

## 终极·诛心：仅对生命≤30%目标生效，斩杀成功回8能量（战斗层应只允许此类目标被选中）
static func _ef_zhu_xin(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【诛心】" % user.name
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if not cut_if_under_pct(tu, 30):
			out += "；%s 生命高于30%%（%d%%），无法斩杀" % [tu.name, hp_pct(tu)]
			continue
		out += "；斩杀 %s" % tu.name
		if not tu.alive:
			var got := user.add_energy(8)
			out += "，回 %d 能量（%d/%d）" % [got, user.energy, user.max_energy]
	if targets.is_empty():
		out += "（无目标）"
	return out

## ========== 光雨（刘星泽）效果 ==========
## 星河 = 自身计数器（counters["星河"]，攒3层给大招）；星矢 = 目标 status "star"
## 眩晕/失明：flag + 持续回合 timer（执行由战斗层看 flag：眩晕跳过回合/失明按概率）

## 眩晕辅助（通用）：施加 flag + N 回合后自动清除
static func apply_stun(t: BattleUnit, rounds: int) -> void:
	t.add_flag("stun")
	t.remove_timer("stun_clear")
	t.add_timer("stun_clear", rounds, Callable(func(): t.clear_flag("stun")))

## 光雨被动（展示；每回合回能/每2回合回血能由 def turn_start_effects 自动处理）
static func _ef_xing_he(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【星河】生效：星河 %d 层" % [user.name, user.counter("星河")]

## 施加星矢：满3 → 清空 + 眩晕1（目标）；返回追加文本
static func _add_star(user: BattleUnit, t: BattleUnit, n: int) -> String:
	t.add_status("star", n)
	if t.status_stacks("star") >= 3:
		t.set_status("star", 0)
		apply_stun(t, 1)
		user.grant_counter("星河", 1)
		return "，%s 星矢满3层→眩晕1回合，%s 星河+1（共%d）" % [t.name, user.name, user.counter("星河")]
	return "，%s 星矢+%d（共%d）" % [t.name, n, t.status_stacks("star")]

## 主动1·光如矢
static func _ef_guang_ru_shi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【光如矢】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(2)
	var out := "%s 释放【光如矢】：%s 受 %d 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	out += _add_star(user, tu, 1)
	return out

## 主动2·矢如雨（≤4目标各2伤+减速2）
static func _ef_shi_ru_yu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【矢如雨】" % user.name
	var hit := 0
	for t in targets:
		if hit >= 4:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2)
		tu.add_speed_mod_src("光雨:矢如雨", -2)
		out += "；%s 受 %d 伤，速度-2（现%d）" % [tu.name, r["hp_lost"] + r["absorbed"], tu.effective_speed()]
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## 主动3·雨如星：3伤 + 星矢2 + 星河1
static func _ef_yu_ru_xing(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【雨如星】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(3)
	var out := "%s 释放【雨如星】：%s 受 %d 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	out += _add_star(user, tu, 2)
	user.grant_counter("星河", 1)
	out += "，%s 星河+1（共%d）" % [user.name, user.counter("星河")]
	return out

## 终极·星如河：消耗3星河 → 单体5伤 + 全体敌人星矢+1/失明1
static func _ef_xing_ru_he(user: BattleUnit, ctx: Dictionary) -> String:
	if user.counter("星河") < 3:
		return "%s 星河不足 3 层，【星如河】无法发动" % user.name
	user.consume_counter("星河", 3)
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【星如河】" % user.name
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		if hit == 0:
			var r: Dictionary = tu.take_damage(5)
			out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		tu.add_status("star", 1)
		tu.add_status("blind", 1)
		hit += 1
	out += "；全体敌人星矢+1、失明1级（%d 目标）" % hit
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 药师（杨鑫翰）效果 ==========
## 负面状态定义（用于“清除负面”类技能）：bleed/burn/wound/star/blind/stun 及减速
static func _clear_random_debuff(t: BattleUnit) -> String:
	var pool := ["bleed", "burn", "wound", "blind"]
	for k in pool:
		if t.status_stacks(k) > 0:
			t.set_status(k, 0)
			return "%s（清除）" % status_cn(k)
	if t.speed_mod_total() < 0:
		t.set_speed_mod_src("药师:负面", 0)
		return "减速（清除）"
	if t.has_flag("stun"):
		t.clear_flag("stun")
		return "眩晕（清除）"
	return "无负面可清"

static func _ef_gao_yu(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【膏腴】生效：能量无上限（当前 %d）" % [user.name, user.energy]

## 主动1·建木生发：耗自身血=目标当前血一半 → 目标受“已损生命一半”伤害 → 回能=消耗量
static func _ef_jian_mu_sheng_fa(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【建木生发】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var cost := ceili(float(tu.hp) * 0.5)
	if user.hp <= cost:
		return "%s 生命不足（%d/%d），【建木生发】无法发动（需要 %d）" % [user.name, user.hp, user.max_hp, cost]
	user.lose_hp(cost)
	var lost := tu.max_hp - tu.hp
	var dmg := ceili(float(maxi(0, lost)) * 0.5)
	var r: Dictionary = tu.take_damage(dmg)
	user.add_energy(cost)
	return "%s 释放【建木生发】：消耗自身 %d 生命，%s 受 %d 伤，回复 %d 能量" % [user.name, cost, tu.name, r["hp_lost"] + r["absorbed"], cost]

## 主动2·寿瘟祸祖：耗一半当前生命 → 清一负面 → 附近敌人3伤
static func _ef_shou_wan_huo_zu(user: BattleUnit, ctx: Dictionary) -> String:
	var cost := ceili(float(user.hp) * 0.5)
	if user.hp <= cost:
		return "%s 生命不足，【寿瘟祸祖】无法发动" % user.name
	user.lose_hp(cost)
	var clean := _clear_random_debuff(user)
	var out := "%s 释放【寿瘟祸祖】：消耗 %d 生命，自身%s" % [user.name, cost, clean]
	var targets: Array = ctx.get("targets", [])
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3)
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
	if targets.is_empty():
		out += "（附近无敌人）"
	return out

## 主动3·莳者一心：回2血2能 + 1盾
static func _ef_shi_zhe_yi_xin(user: BattleUnit, _ctx: Dictionary) -> String:
	var h := user.heal(2)
	var e := user.add_energy(2)
	user.add_shield(1)
	return "%s 释放【莳者一心】：回复 %d 生命、%d 能量，+1 护盾（现 %d）" % [user.name, h, e, user.shield]

## 终极·药灵：生命降至1 → 盾=消耗量一半；锁血本回合；相邻敌人受当前盾量伤害
static func _ef_yao_ling(user: BattleUnit, ctx: Dictionary) -> String:
	var spend := user.hp - 1
	if spend <= 0:
		return "%s 生命过低，【药灵】无法发动" % user.name
	user.lose_hp(spend)
	var gained := ceili(float(spend) * 0.5)
	user.add_shield(gained)
	user.add_flag("lock_min_hp")
	user.remove_timer("yaoling_lock")
	user.add_timer("yaoling_lock", 1, Callable(func(): user.clear_flag("lock_min_hp")))
	var out := "%s 释放【药灵】：生命降至 1，获得 %d 护盾（现 %d），本回合锁血" % [user.name, gained, user.shield]
	var targets: Array = ctx.get("targets", [])
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var before := tu.hp
		tu.lose_hp(user.shield)
		out += "；%s 受 %d 真伤" % [tu.name, before - tu.hp]
	if targets.is_empty():
		out += "（相邻无敌人）"
	return out

## ========== 孤狼（叶麟）效果 ==========
static func _ef_duan_ti(user: BattleUnit, _ctx: Dictionary) -> String:
	if not user.has_flag("duanti_reg"):
		user.add_flag("duanti_reg")
		var u := user
		user.hit_events.append(Callable(func(atk, _el): u.add_mitigation_att(atk, 5, 20)))
	return "%s 的【锻体】生效：每次受击，对该攻击者的伤害免伤 +5%%（对同一人上限20%%）" % user.name

## 阴阳散手：进入防守阴态（15%减伤），受击3次转阳（2回合50%反伤）
static func _ef_yyss(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_flag("yin")
	user.set_mitigation("all", 15)
	user.set_counter("受击", 0)
	if not user.has_flag("yyss_reg"):
		user.add_flag("yyss_reg")
		var u := user
		user.hit_events.append(Callable(func(_atk, _el): _yyss_on_hit(u)))
	return "%s 释放【阴阳散手】：进入阴状态（减伤15%%），受击3次后转阳" % user.name

static func _yyss_on_hit(u: BattleUnit) -> void:
	if not u.has_flag("yin"):
		return
	u.grant_counter("受击", 1)
	if u.counter("受击") >= 3:
		u.clear_flag("yin")
		u.set_mitigation("all", 0)
		u.add_flag("yang")
		u.set_reflect(50)
		u.remove_timer("yang_end")
		u.add_timer("yang_end", 2, Callable(func():
			u.clear_flag("yang")
			u.set_reflect(0)))

## 伸缩拳：相邻4伤 / 两格2伤；远击嘲讽禁大2回合，近击获得对方属性免伤5%(上限30%)
static func _ef_ssq(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【伸缩拳】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var dist := int(ctx.get("dist", 1))
	var dmg := 4 if dist <= 1 else 2
	var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": user.element})
	var out := "%s 释放【伸缩拳】%s：%s 受 %d 伤" % [user.name, "（远击）" if dist >= 2 else "（近击）", tu.name, r["hp_lost"] + r["absorbed"]]
	if dist >= 2:
		tu.add_flag("taunted")
		tu.add_flag("no_ult")
		tu.remove_timer("taunt_end")
		tu.add_timer("taunt_end", 2, Callable(func():
			tu.clear_flag("taunted")
			tu.clear_flag("no_ult")))
		out += "；%s 被嘲讽：大招封印2回合" % tu.name
	else:
		user.add_mitigation_att(tu, 5, 30)
		out += "；习得对 %s 的免伤+5%%（对 %s 共 %d%%）" % [tu.name, tu.name, user.mitigation_att(tu)]
	return out

## 普通拳：2伤 + 对被嘲讽目标1真伤；回2能
static func _ef_ptq(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【普通拳】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": user.element})
	var out := "%s 释放【普通拳】：%s 受 %d 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]
	if tu.has_flag("taunted"):
		var before := tu.hp
		tu.lose_hp(1)
		out += "，嘲讽目标额外 %d 真伤" % (before - tu.hp)
	user.add_energy(2)
	return out

## 血狱：首个目标已损15%伤害；范围内每目标 +5%免伤(总40)
static func _ef_xue_yu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【血狱】" % user.name
	if not targets.is_empty():
		var tu := targets[0] as BattleUnit
		var dmg := ceili(float(maxi(0, tu.max_hp - tu.hp)) * 0.15)
		var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": user.element})
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
	for t in targets:
		user.add_mitigation("all", 5, 40)
	out += "；免伤 +%d%%（总 %d%%）" % [targets.size() * 5, user.mitigation_of("all")]
	return out

## ========== rapper睡神（何至高）效果 ==========
static func _ef_kn(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【狂怒】生效：生命≤20%% 时伤害翻倍（当前倍率 %.1f）" % [user.name, user.dmg_mult]

## 掠夺：目标失去一个主动技能（本局）；自身获得其 id（技能栏替换由战斗层）
static func _ef_lve(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【掠夺】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	for s in tu.actives:
		if s == null:
			continue
		var slot_i := tu.actives.find(s) + 1
		if slot_i >= 4:
			continue
		if not tu.is_skill_lost(s.id):
			tu.mark_skill_lost(s.id)
			user.set_meta("stolen_skill", s.id)
			user.add_flag("has_stolen")
			return "%s 掠夺了 %s 的【%s】（目标本局无法再用；下回合起可释放掠夺技）" % [user.name, tu.name, s.display_name]
	return "%s 释放【掠夺】：%s 没有可掠夺的技能（大招除外）" % [user.name, tu.name]

## 魅惑：≤2 目标本回合无法造成伤害
static func _ef_meihuo(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【魅惑】" % user.name
	var n := 0
	for t in targets:
		if n >= 2:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.add_flag("no_damage")
		tu.remove_timer("meihuo_end")
		tu.add_timer("meihuo_end", 1, Callable(func(): tu.clear_flag("no_damage")))
		out += "；%s 本回合无法造成伤害" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 锁血：本回合无敌 + 回1血2能
static func _ef_suoxue(user: BattleUnit, _ctx: Dictionary) -> String:
	user.add_flag("invuln")
	user.remove_timer("invuln_end")
	user.add_timer("invuln_end", 1, Callable(func(): user.clear_flag("invuln")))
	var h := user.heal(1)
	var e := user.add_energy(2)
	return "%s 释放【锁血】：本回合无敌，回复 %d 生命、%d 能量" % [user.name, h, e]

## 万里冰封：三格内敌人 冻伤1（减速20·回合末1真伤·2回合）+3伤
static func _ef_wanli(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【万里冰封】" % user.name
	var hit := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": "冰"})
		out += "；%s 受 %d 伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		tu.add_status("freeze", 1)
		tu.set_speed_mod_src("冰封", -20)
		tu.remove_timer("freeze_end")
		tu.add_timer("freeze_end", 2, Callable(func():
			tu.remove_speed_mod_src("冰封")
			tu.set_status("freeze", 0)))
		out += "，冻伤1级（速-20，2回合）"
		hit += 1
	if hit == 0:
		out += "（无目标）"
	return out

## ========== 仙尊（陈雨晴）效果 ==========
static func _ef_niepan(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【涅槃】生效：死亡复活回一半生命（每局1次）；回合末自动回4能量" % user.name

## 五行之力：随机一道五行法力，相邻≤3敌人各2伤
static func _ef_wuxing(user: BattleUnit, ctx: Dictionary) -> String:
	var elems := ["金", "木", "水", "火", "土"]
	var pick: String = elems[randi() % elems.size()]
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【五行之力】（%s）：" % [user.name, pick]
	var hit := 0
	for t in targets:
		if hit >= 3:
			break
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": pick})
		out += "%s 受 %d 伤；" % [tu.name, r["hp_lost"] + r["absorbed"]]
		hit += 1
	if hit == 0:
		out += "无目标"
	return out

## 束缚之灵：相邻敌人本回合无法使用技能
static func _ef_shufu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【束缚之灵】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.add_flag("no_skill")
		tu.remove_timer("shufu_end")
		tu.add_timer("shufu_end", 1, Callable(func(): tu.clear_flag("no_skill")))
		out += "；%s 本回合沉默" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## 转嫁傀儡：目标位移由战斗层执行；造成已损生命20%伤害
static func _ef_zhuanjia(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【转嫁傀儡】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var dmg := ceili(float(maxi(0, tu.max_hp - tu.hp)) * 0.2)
	var r: Dictionary = tu.take_damage(dmg, {"attacker": user, "element": "土"})
	return "%s 释放【转嫁傀儡】：%s 被转移到仙尊相邻空格（战斗层执行），受 %d 伤" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]

## 万剑归宗：两格内敌人每回合末2真伤，持续3回合
static func _ef_wanjian(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【万剑归宗】" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		tu.add_status("sword_field", 1)
		tu.remove_timer("sword_end")
		tu.add_timer("sword_end", 3, Callable(func(): tu.set_status("sword_field", 0)))
		out += "；%s 剑域3回合" % tu.name
		n += 1
	if n == 0:
		out += "（无目标）"
	return out

## ========== 灵虚数影（辛子祺）效果 ==========
static func _ef_shuyu(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【数域】生效：对非必中攻击 90%% 闪避" % user.name

static func _ef_tianji(user: BattleUnit, _ctx: Dictionary) -> String:
	user.set_dmg_mult(1.5)
	user.remove_timer("tianji_end")
	user.add_timer("tianji_end", 1, Callable(func(): user.set_dmg_mult(1.0)))
	return "%s 释放【天机】：下回合伤害 1.5 倍" % user.name

## 解析：单体3伤 + 破甲2（护甲-2，3回合后恢复）
static func _ef_jiexi(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	if targets.is_empty():
		return "%s 释放【解析】（无目标）" % user.name
	var tu := targets[0] as BattleUnit
	var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": user.element, "sure_hit": true})
	tu.remove_armor(2)
	tu.remove_timer("pojia_restore")
	tu.add_timer("pojia_restore", 3, Callable(func(): tu.add_armor(2)))
	return "%s 释放【解析】：%s 受 %d 伤，破甲二级（甲-2，3回合）" % [user.name, tu.name, r["hp_lost"] + r["absorbed"]]

static func _ef_jidian(user: BattleUnit, _ctx: Dictionary) -> String:
	var e := user.add_energy(5)
	user.add_shield(1)
	return "%s 释放【极点】：回复 %d 能量、1 护盾（现 %d）" % [user.name, e, user.shield]

## 数海腾挪：天机+解析+本回合及下回合无法被选中
static func _ef_shuhai(user: BattleUnit, ctx: Dictionary) -> String:
	var out := "%s 释放【数海腾挪】" % user.name
	user.set_dmg_mult(1.5)
	user.remove_timer("tianji_end")
	user.add_timer("tianji_end", 1, Callable(func(): user.set_dmg_mult(1.0)))
	var targets: Array = ctx.get("targets", [])
	if not targets.is_empty():
		var tu := targets[0] as BattleUnit
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": user.element, "sure_hit": true})
		tu.remove_armor(2)
		tu.remove_timer("pojia_restore")
		tu.add_timer("pojia_restore", 3, Callable(func(): tu.add_armor(2)))
		out += "；%s 受 %d 伤、破甲二级" % [tu.name, r["hp_lost"] + r["absorbed"]]
	user.add_flag("untargetable")
	user.remove_timer("untargetable_end")
	user.add_timer("untargetable_end", 2, Callable(func(): user.clear_flag("untargetable")))
	out += "；本回合及下回合无法被选中"
	return out

## ========== 辛克莱（新表）效果 ==========
static func _ef_hebi(user: BattleUnit, _ctx: Dictionary) -> String:
	return "%s 的【何必如此】生效：理智 %d/%d（可为负；失控下回合自动行动）" % [user.name, user.sanity, user.sanity_cap]

## 迫不得已的审判：突进2格穿过目标 → 2伤 + 烧伤（刷新）；理智-7
static func _ef_pbdy(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【迫不得已的审判】（突进2格）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": "火"})
		apply_burn(tu)
		out += "；%s 受 %d 伤、获烧伤" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(7)
	out += "；理智 -7（现 %d）" % user.sanity
	if n == 0:
		out += "（未穿过棋子）"
	return out

## 黑白不分的执行：突进撞墙/撞人 → 撞到棋子3伤 + 2层重伤；理智-10
static func _ef_heibai(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【黑白不分的执行】（快速突进）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(3, {"attacker": user, "element": "火"})
		apply_heavy_wound(tu, 2)
		out += "；撞到 %s：受 %d 伤、重伤+2" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(10)
	out += "；理智 -10（现 %d）" % user.sanity
	if n == 0:
		out += "（未撞到棋子）"
	return out

## 自我毁灭的审判：传送后对周围敌人 2伤+3重伤；理智 -3×命中数
static func _ef_zishu(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【自我毁灭的审判】（传送）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var r: Dictionary = tu.take_damage(2, {"attacker": user, "element": "物理"})
		apply_heavy_wound(tu, 3)
		out += "；%s 受 %d 伤、重伤+3" % [tu.name, r["hp_lost"] + r["absorbed"]]
		n += 1
	user.lose_sanity(3 * n)
	out += "；理智 -%d（现 %d）" % [3 * n, user.sanity]
	if n == 0:
		out += "（周围无敌人）"
	return out

## 因为我是被选中的：冲刺3格穿过 → 已损生命20%真伤；重伤≥4再获烧伤；理智-15
static func _ef_xuanzhong(user: BattleUnit, ctx: Dictionary) -> String:
	var targets: Array = ctx.get("targets", [])
	var out := "%s 释放【因为我是被选中的】（冲刺3格）" % user.name
	var n := 0
	for t in targets:
		var tu := t as BattleUnit
		if tu == null:
			continue
		var dmg := ceili(float(maxi(0, tu.max_hp - tu.hp)) * 0.2)
		var before := tu.hp
		tu.lose_hp(dmg)
		out += "；%s 失去 %d 真伤（已损生命20%%）" % [tu.name, before - tu.hp]
		if tu.status_stacks("heavy_wound") >= 4:
			apply_burn(tu)
			out += "，重伤≥4层 → 获烧伤"
		n += 1
	user.lose_sanity(15)
	out += "；理智 -15（现 %d）" % user.sanity
	if n == 0:
		out += "（未穿过棋子）"
	return out
