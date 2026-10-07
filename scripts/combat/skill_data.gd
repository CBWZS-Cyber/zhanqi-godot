class_name SkillData
extends RefCounted
## 技能元信息数据表 —— 原 skill_effects.gd 的 `const DATA`，2026-09-30 拆出。
##
## 只放数据、不放逻辑：加技能先在这里登记元信息，效果函数仍写 skill_effects.gd。
## SkillEffects.DATA 转发到本表的 DATA，因此全工程调用点无需改动。

const DATA := {
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
		"name": "凝晶为刃", "crystal_cost": 1,
		"range": 1,
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "消耗 1 枚元晶，对 1 个目标造成 3 点伤害。",
	},

	"hua_jing_kai": {
		"name": "化晶为铠", "crystal_cost": 2, "element": "元", "kind": "active", "energy_cost": 0,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "shield"},
		"desc": "消耗 2 枚元晶，获得 3 点护盾并回复 2 点能量。",
	},

	"sui_jing_zhan": {
		"name": "碎晶斩", "need_shield": true,
		"range": 1,
		"element": "元",
		"kind": "active",
		"energy_cost": 3,
		"cooldown": 0,
		"desc": "自身有护盾时，清空护盾，对 1 个目标造成 3 点真实伤害（无护盾无法发动）。",
	},

	"yu_jing_wei_long": {
		"name": "御晶为龙", "crystal_cost": 3,
		"range": 2,
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
		"range": 1,
		"element": "金",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程1格，对1个目标造成1点伤害（随剑意成长），目标速度下降10。",
	},

	"duan_liu": {
		"name": "断流",
		"range": 1,
		"element": "金",
		"kind": "active",
		"energy_cost": 8,
		"cooldown": 0,
		"desc": "射程1格，对1个目标造成减速，目标速度下降50。",
	},

	"guan_chuan": {
		"name": "贯穿",
		"range": 1,
		"element": "金",
		"kind": "active",
		"energy_cost": 5,
		"cooldown": 0,
		"desc": "射程1格，对1个目标施加 5 层重伤（受击额外 0.5×层数真伤）。",
	},

	"zhu_xin": {
		"name": "诛心", "element": "金", "kind": "ultimate", "energy_cost": 10,
		"range": 2,
		"dash_dist": 2,
		"ai": {"dash": true},
		"desc": "射程3格位移型斩杀：只能对生命≤30%的目标使用，将其斩杀；斩杀成功回复8点能量。",
	},
	"xing_he": {
		"name": "星河",
		"element": "光",
		"kind": "passive",
		"desc": "每回合能量回复提升为 2 点；每两回合回复 3 点生命值、2 点能量。（引擎 turn_start_effects 自动处理）",
	},

	"guang_ru_shi": {
		"name": "光如矢",
		"range": 3,
		"element": "光",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程3格，对1个目标造成2点伤害并加1层「星矢」；目标星矢满3层时清空并眩晕1回合，自身获得1层星河。",
	},

	"shi_ru_yu": {
		"name": "矢如雨",
		"range": 3,
		"element": "光",
		"kind": "active",
		"energy_cost": 6,
		"cooldown": 0,
		"desc": "射程3格，对最多4个目标各造成2点伤害，目标速度降低2。",
	},

	"yu_ru_xing": {
		"name": "雨如星",
		"range": 2,
		"element": "光",
		"kind": "active",
		"energy_cost": 6,
		"cooldown": 0,
		"desc": "射程2格，对1个目标造成3点伤害，目标+2层「星矢」，自身+1层星河。",
	},

	"xing_ru_he": {
		"name": "星如河",
		"range": 2,
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
		"range": 2,
		"element": "木",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "射程2格：消耗等同于目标当前生命一半的生命值，造成目标已损生命一半的伤害，回复等同于消耗生命值的能量。",
	},

	"shou_wan_huo_zu": {
		"name": "寿瘟祸祖",
		"range": 1,
		"element": "木",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		# land_aoe：描述为“附近敌人”，故作用于射程内全体敌人而非单个
		"ai": {"land_aoe": true},
		"desc": "消耗一半当前生命：随机清除自身一种负面状态，对附近敌人造成3点伤害。",
	},

	"shi_zhe_yi_xin": {
		"name": "莳者一心", "element": "木", "kind": "active", "energy_cost": 0,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "heal"},
		"desc": "回复2点生命、2点能量，获得1点护盾。",
	},

	"yao_ling": {
		"name": "药灵", "element": "圣灵", "kind": "ultimate", "energy_cost": 12,
		"range": 1,
		# 注意：本技是“攻击型大招”，不可标 self_buff —— 否则战斗层 self_skill() 为真，
		# 目标列表恒为空，大招将永远打不到人（AI 也不会把它当攻击技使用）。
		# land_aoe：描述为“相邻敌人”，故作用于相邻全体敌人。
		# 不标 self_kind=heal：避免 AI 把它当保命技（会把生命压到 1），应作为攻击大招使用。
		"ai": {"land_aoe": true},
		"desc": "生命降至1并获得等同于消耗生命值一半的护盾，本回合内血量最低为1（锁血），并对相邻敌人造成等同于当前护盾量的伤害。",
	},

	"duan_ti": {"name": "锻体", "element": "物理", "kind": "passive",
		"desc": "每次受到伤害，对该攻击者的伤害免伤 +5%（对同一人最高 20%）。"},

	"yin_yang_san_shou": {
		"name": "阴阳散手", "element": "物理", "kind": "active", "energy_cost": 4,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "buff"},
		"desc": "进入阴状态防守：获得 15% 减伤并嘲讽相邻目标；受击 3 次后转阳，阳持续 2 回合，期间 50% 反伤。",
	},

	"shen_suo_quan": {"name": "伸缩拳", "element": "物理", "kind": "active", "energy_cost": 6,
		"range": 2,
		"desc": "相邻目标 4 伤，或两格目标 2 伤。击中两格目标使其禁大招 2 回合（嘲讽）；击中相邻目标时自身获得对该目标的 5% 免伤（对同一人上限 30%）。"},

	"pu_tong_quan": {"name": "普通拳", "element": "物理", "kind": "active", "energy_cost": 0,
		"range": 1,
		"desc": "对目标造成 2 点伤害；对被嘲讽的目标追加 1 点真实伤害。回复 2 能量。"},

	"xue_yu": {"name": "血狱", "element": "物理", "kind": "ultimate", "energy_cost": 10,
		"range": 2,
		"desc": "对两格内一个目标造成其已损生命 15% 的伤害；范围内每有 1 个目标自身获得 5% 免伤（总上限 40%）。"},

	# ===== rapper睡神（何至高）=====

	"kuang_nu": {"name": "狂怒", "element": "神秘", "kind": "passive",
		"desc": "生命值低于 20% 时伤害翻倍（hp_threshold_flags 自动管理）。"},

	"lve_duo": {"name": "掠夺", "element": "神秘", "kind": "active", "energy_cost": 8,
		"range": 1,
		"desc": "掠夺相邻一个敌人身上的一个技能（大招除外）：该敌人直到下个对方回合无法使用它，自己直到下两个自己回合可以在第 1 技能槽使用它（原第 1 槽技能暂被替换，时效结束归还）。"},

	"mei_huo": {"name": "魅惑", "element": "毒", "kind": "active", "energy_cost": 5,
		"range": 2,
		"desc": "选择两格内 2 个目标，使其本回合无法造成伤害。"},

	"suo_xue": {
		"name": "锁血", "element": "火", "kind": "active", "energy_cost": 0,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "heal"},
		"desc": "本回合内无敌，回复 1 点生命、2 点能量。",
	},

	"wan_li_bing_feng": {"name": "万里冰封", "element": "冰", "kind": "ultimate", "energy_cost": 12,
		"range": 3,
		"desc": "三格内所有敌人进入冻伤1级（速度-20，每回合末受1真伤，持续2回合）并受到 3 点伤害。"},

	# ===== 仙尊（陈雨晴）=====

	"nie_pan": {"name": "涅槃", "element": "圣灵", "kind": "passive",
		"desc": "死亡后复活，回复一半生命（每局一次，引擎 death_revive）。每回合末回复 4 能量。"},

	"wu_xing_zhi_li": {"name": "五行之力", "element": "五行", "kind": "active", "energy_cost": 9,
		"range": 1,
		"desc": "随机发射一道五行法力（金木水火土），对相邻格最多 3 个敌人各造成 2 点伤害。"},

	"shu_fu_zhi_ling": {"name": "束缚之灵", "element": "木", "kind": "active", "energy_cost": 13,
		"range": 1,
		"desc": "至本回合末，相邻格子内的敌人无法使用技能。"},

	"zhuan_jia_kui_lei": {"name": "转嫁傀儡", "element": "土", "kind": "active", "energy_cost": 15,
		"range": 3,
		"desc": "指定敌方一人转移到仙尊相邻空格（位移由战斗层执行），并对其造成已损生命 20% 的伤害。"},

	"wan_jian_gui_zong": {"name": "万剑归宗", "element": "金", "kind": "ultimate", "energy_cost": 18,
		"range": 2,
		"desc": "两格范围内所有敌人每回合末受 2 点真伤，持续 3 回合（剑域）。"},

	# ===== 灵虚数影（辛子祺）=====

	"shu_yu": {"name": "数域", "element": "神秘", "kind": "passive",
		"desc": "对一切攻击（必中除外）90% 闪避；相邻友军 +5% 闪避（aura 由战斗层提供）。"},

	"tian_ji": {
		"name": "天机", "element": "神秘", "kind": "active", "energy_cost": 6,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "buff"},
		"desc": "识破弱点：下回合自身（及周围棋子，aura 由战斗层）伤害 1.5 倍。",
	},

	"jie_xi": {"name": "解析", "element": "神秘", "kind": "active", "energy_cost": 8,
		"range": 2,
		"desc": "两格内单目标 3 点伤害，并造成破甲二级（护甲-2，持续3回合）。"},

	"ji_dian": {
		"name": "极点", "element": "神秘", "kind": "active", "energy_cost": 0,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "buff"},
		"desc": "推演极点，获得启发：回复 5 点能量、1 点护盾。",
	},

	"shu_hai_teng_nuo": {"name": "数海腾挪", "element": "神秘", "kind": "ultimate", "energy_cost": 24,
		"range": 2,
		"desc": "同时释放天机与解析，且本回合及下回合无法被选中。"},

	# ===== 辛克莱（新表已定稿：理智上限25 初始0，可为负）=====

	# ===== 辛克莱（新表已定稿：理智上限25 初始0，可为负）=====
	"he_bi": {
		"name": "何必如此", "element": "火", "kind": "passive",
		"desc": "无能量机制，专属理智值（上限25，初始0）。每回合末回复30%缺损理智；使用技能使理智变负时下回合失控（随机放技不分敌我），随后回合末理智归0。对主属性为机械的目标（不论敌友）造成的伤害 +10%。",
	},
	"po_bu_de_yi": {
		"name": "迫不得已的审判", "element": "火", "kind": "active", "energy_cost": 0,
		"range": 1, "dash_dist": 1,
		"ai": {"dash": true, "dash_kind": "charge"},
		"desc": "向一个方向突进1格（冲刺落格）：穿过棋子则造成 2 点伤害，目标获得烧伤（持续中再获得则刷新时长）；理智 -7。",
	},
	"hei_bai": {
		"name": "黑白不分的执行", "element": "火", "kind": "active", "energy_cost": 0,
		"range": 2, "dash_dist": 3,
		"ai": {"dash": true, "dash_kind": "charge"},
		"desc": "向一个方向快速突进直到碰壁（人或障碍）：对撞到的棋子造成 3 点伤害并施加 2 层重伤；理智 -10。",
	},
	"zi_wo_destroy": {
		"name": "自我毁灭的进化", "element": "物理", "kind": "active", "energy_cost": 0,
		"range": 1, "dash_dist": 3,
		"ai": {"dash": true, "land_aoe": true},
		"desc": "向周围3格内某地点传送（跃迁落格），对周围格子敌人造成 2 点伤害、施加 3 层重伤；自身失去 3×命中数 理智。",
	},
	"xuan_zhong": {
		"name": "因为我是被选中的", "element": "物理", "kind": "ultimate", "energy_cost": 0,
		"range": 2, "dash_dist": 2,
		"ai": {"dash": true, "dash_kind": "charge"},
		"desc": "向前冲刺2格（冲刺落格）：对被穿过的棋子造成其已损生命 20% 的真伤；若其身上重伤≥3 层，再施加烧伤；理智 -15。",
	},
	# 状态规则（烧伤：速度-10，每回合末1真伤，持续2回合，刷新式。重伤：受击额外 0.5×层真伤，回合末层-1）

	"zhuilie_ymxb": {
		"name": "以命相搏",
		"element": "机械",
		"kind": "passive",
		"desc": "生命值≤3时，速度增加200点，护甲清零，每回合获得2点护盾。",
	},

	"snap_shot": {
		"name": "狙击", "element": "机械", "kind": "active", "energy_cost": 0,
		"range": 3,
		"desc": "射程3格，对1个目标造成1点伤害，附加「创伤」印记；积累3层时清空印记并触发「流血1级」。",
	},
	"hunt": {
		"name": "追猎", "element": "机械", "kind": "active", "energy_cost": 3,
		"range": 2, "dash_dist": 1,
		"ai": {"dash": true},
		"desc": "跃迁落格后额外发动一次「狙击」（落点由玩家选择）。",
	},
	"shield_up": {
		"name": "架盾", "element": "机械", "kind": "active", "energy_cost": 0,
		"range": 0,
		"ai": {"self_buff": true, "self_kind": "shield"},
		"desc": "获得2点护盾，护甲+1（上限3）。",
	},

	"meteor_shot": {
		"name": "流炎飞弹",
		"range": 99,
		"max_targets": 2,
		"element": "机械",
		"kind": "ultimate",
		"energy_cost": 0,
		"cooldown": 0,
		"per_game": 1,
		"desc": "全图射程，攻击2个目标各造成3点伤害，附加「灼烧」（2 回合）；若目标已有「流血1级」则升为「流血2级」；护甲-1。一局仅限一次。",
	},

	# ===== 流萤（【火萤IV型】SAM战略强袭装甲）=====
	"ying_huo_zhong_shu": {
		"name": "茧式源火中枢", "element": "火", "kind": "passive",
		"desc": "初始处于【次级燃烧】：仅可用【天火】。使用天火后进入【完全燃烧】：速度+80，40%概率免疫控制类负面，技能组替换为【底火斩击】【死星过载】【超新星过载】；完全燃烧下累计释放 3 次技能后退回【次级燃烧】，释放超新星后立即退回。",
	},
	"tian_huo": {
		"name": "天火", "element": "火", "kind": "active", "energy_cost": 0,
		"range": 3,
		"desc": "消耗自身 50% 当前生命（保留至少 1 点），对一个目标造成 1 点伤害，若目标有护盾则额外烧毁 1 点护盾。释放后进入【完全燃烧】。",
	},
	"di_huo_zhan_ji": {
		"name": "底火斩击", "element": "火", "kind": "active", "energy_cost": 0,
		"range": 2,
		"desc": "对一个目标造成 1 点真实伤害，若其持有护盾则额外烧毁 2 点护盾，并回复 3 点能量。【完全燃烧】限定。",
	},
	"si_xing_guo_zai": {
		"name": "死星过载", "element": "火", "kind": "active", "energy_cost": 4,
		"range": 2, "dash_dist": 1,
		"ai": {"dash": true, "land_aoe": true},
		"desc": "向目标方向突进 1 格，对落点相邻格内至多 3 名单位各造成 2 点伤害；持有护盾的目标被额外烧毁 2 点护盾并追加 2 点真实伤害。【完全燃烧】限定。",
	},
	"chao_xin_xing": {
		"name": "超新星过载", "element": "火", "kind": "ultimate", "energy_cost": 12,
		"range": 2, "range_shape": "diamond", "max_targets": 3,
		"desc": "以自身为中心菱形两格（13 格：九宫格+两轴外扩）内至多 3 个单位造成 2 点真实伤害；持有护盾的目标被烧毁 3 点护盾且真伤提高至 4 点。释放后强制退出【完全燃烧】。",
	},

	# ===== 李太白（诗仙）=====
	"mei_jiu": {
		"name": "美酒", "element": "金", "kind": "passive",
		"desc": "每回合开始喝一杯小酒，醉意 +1（初始 0）。回合开始时若醉意 ≥5，本回合陷入酒醉（无法行动），醉意清零。",
	},
	"jiang_jin_jiu": {
		"name": "将进酒，杯莫停", "element": "金", "kind": "active", "energy_cost": 0,
		"range": 0, "ai": {"self_buff": true, "self_kind": "buff"},
		"desc": "痛饮一杯，醉意 +2。",
	},
	"bi_mo_hui_sa": {
		"name": "笔墨挥洒", "element": "金", "kind": "active", "energy_cost": 10,
		"range": 99,
		"desc": "诗兴大发，随手写下与醉意层数相同行小诗，随机攻击敌方单位，每行 1 点伤害。使用后醉意 -2。",
	},
	"si_yi": {
		"name": "肆意", "element": "金", "kind": "active", "energy_cost": 15,
		"range": 3, "dash_dist": 3,
		"ai": {"dash": true, "dash_kind": "charge"},
		"desc": "消耗全部醉意写成一诗，向一个方向突进，对撞到的目标造成等同于消耗醉意层数的伤害。",
	},
	"yu_jun_tong_zui": {
		"name": "与君同醉", "element": "金", "kind": "ultimate", "energy_cost": 15,
		"range": 2, "range_shape": "diamond",
		"desc": "自身周围菱形两格（13 格）内所有敌方单位与李太白自己全部陷入酒醉（本回合无法行动）。",
	},

	# ===== 虞美人（怀恨）=====
	"ku_chu": {
		"name": "苦楚", "element": "木", "kind": "passive",
		"desc": "初始带有 2 层「愤恨」；每回合末，周围 3×3 内的友方单位回复 20% 最大生命；虞美人阵亡时其所有子体瞬间枯萎。",
	},
	"man_yan": {
		"name": "蔓延", "element": "木", "kind": "active", "energy_cost": 0,
		"range": 1, "ai": {"spread": true},
		"desc": "【蔓延】在周围相邻的空格（且没有子体的格子）各生成 1 个子体，最多 2 格由你点选；周围只剩 1 个可蔓延格则自动蔓延，没有可蔓延格则按钮不可用。不占用行动次数，也不影响虞美人正常移动（移动与蔓延相互独立）。",
	},
	"qing_su": {
		"name": "情愫", "element": "木", "kind": "active", "energy_cost": 10,
		"range": 1, "ai": {"land_aoe": true},
		"desc": "使周围 3×3 内的友方单位各回复 1 点生命（含自己）。",
	},
	"ni_bu_zai_ai_wo": {
		"name": "你不再爱我", "element": "暗", "kind": "passive",
		"desc": "虞美人 3×3 范围内的友方被攻击时，攻击者 +1 层恐惧（战斗层回合末刷新庇佑标记）。",
	},
	"hui_hen": {
		"name": "悔恨", "element": "暗", "kind": "ultimate", "energy_cost": 15,
		"range": 1, "ai": {"land_aoe": true},
		"desc": "使周围相邻的敌方单位各增加 3 层「恐惧」（最多 6 层）。",
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
		"range": 0,
		"element": "暗",
		"kind": "active",
		"energy_cost": 7,
		"cooldown": 0,
		"desc": "本回合所有伤害由失神状态下的敌方棋子均摊；回合末吸取失神敌当前生命的 30%。（伤害均摊需战斗层接伤害管线）",
	},

	"zhi_pei": {
		"name": "支配",
		"range": 1,
		"element": "暗",
		"kind": "active",
		"energy_cost": 10,
		"cooldown": 0,
		"desc": "对周围敌人触发：污染 ≥5 时消耗 3 层，支配该单位 2 回合（下一回合起生效）。单挑模式：污染 ≥8 直接斩杀敌方并获胜。",
	},

	"qin_ran": {
		"name": "侵染",
		"range": 1,
		"element": "暗",
		"kind": "active",
		"energy_cost": 0,
		"cooldown": 0,
		"desc": "对周围所有敌人造成 1 点伤害；60% 概率使每个目标额外 +1 污染；回复 5 点能量。",
	},

	"hei_shan": {
		"name": "黑闪",
		"range": 1,
		"element": "暗",
		"kind": "active",
		"energy_cost": 15,
		"cooldown": 0,
		"desc": "对周围所有敌人触发：消耗其全部污染层，每层使其失去 10% 最大生命；原污染 ≥6：4V4 永久支配该单位，单挑直接斩杀获胜。",
	},
	# ===== 骑士线第一关 · 白灵殿 剧情兵种（数值源自《角色属性与技能表.xlsx》2026-09-10）=====
	# 被动只登记展示信息（战斗层不 trigger_passive）；实际效果由 story_defs 的
	# turn_end_effects / hp_threshold_flags / init_flags 声明式实现，或由战斗层特判。
	"s1_hao_aura": {
		"name": "主角光环", "element": "灵", "kind": "passive",
		"desc": "每回合末回复 1 点生命。",
	},
	"s1_qi_partner": {
		"name": "伙伴", "element": "灵", "kind": "passive",
		"desc": "每回合末回复 1 点生命。",
	},
	"s1_quan_yong": {
		"name": "泉涌", "element": "灵", "kind": "passive",
		"desc": "每回合末回复 4 点能量。受到致命伤害时用能量抵消溢出伤害（每抵消 1 点伤害损失 2 点能量，血量最低保留 1 点）。",
	},
	"s1_du_xin": {
		"name": "笃信", "element": "灵", "kind": "passive",
		"desc": "每回合末回复 3 点能量。",
	},
	"s1_qian_cheng": {
		"name": "虔诚", "element": "灵", "kind": "passive",
		"desc": "每回合末回复 4 点能量。",
	},
	"s1_bu_mie": {
		"name": "不灭", "element": "火", "kind": "passive",
		"desc": "每回合末回复 1 点生命和 5 点能量；无法被杀死（生命最低 1 点）。生命低于 10% 时无法行动。",
	},
	"s1_long_yan": {
		"name": "龙炎", "element": "火", "kind": "passive",
		"desc": "攻击附带 10% 真伤（按本次造成的伤害结算）；每回合末回复 2 点能量。",
	},
	"s1_xiong_xin": {
		"name": "熊心", "element": "火", "kind": "passive",
		"desc": "生命低于 30% 时获得 60% 免伤。",
	},

	# —— 大长老 ——
	"s1_jie_yu_lv": {
		"name": "戒与律", "element": "灵", "kind": "active", "energy_cost": 4, "cooldown": 0,
		"range": 5, "max_targets": 1, "any_target": true,
		"desc": "射程 5 格：使除宵以外的任意单位无法使用技能二，持续一回合。",
	},
	"s1_zhi_yu_ze": {
		"name": "职与责", "element": "灵", "kind": "active", "energy_cost": 10, "cooldown": 2,
		"range": 5, "max_targets": 3,
		"desc": "使己方全体获得 30% 免伤两回合，并对最多三个敌方单位各造成 1 点伤害；释放后两回合内不可重复释放。",
	},
	"s1_qiang_quan": {
		"name": "强权", "element": "灵", "kind": "active", "energy_cost": 5, "cooldown": 0,
		"range": 5, "max_targets": 2,
		"desc": "射程 5 格：对最多两个单位各造成 2 点真伤，并附加两层【畏惧】（每层速度 -5，每回合减少一层）。",
	},
	"s1_ling_zhen": {
		"name": "灵震", "element": "灵", "kind": "ultimate", "energy_cost": 12, "cooldown": 0,
		"range": 3, "max_targets": 2,
		"desc": "大招：对距离 3 格内的 2 个目标各造成 4 点伤害，清空其护甲值，使其眩晕 1 回合。",
	},

	# —— 战士 ——
	"s1_jian_gu": {
		"name": "坚固", "element": "灵", "kind": "active", "energy_cost": 2, "cooldown": 0, "range": 0,
		"ai": {"self_buff": true, "self_kind": "shield"},
		"desc": "使自身获得 20% 免伤，持续 2 回合。",
	},
	"s1_jue_xin": {
		"name": "决心", "element": "灵", "kind": "active", "energy_cost": 0, "cooldown": 0,
		"range": 1, "max_targets": 1,
		"desc": "射程 1 格：对任意一个单位造成 1 点伤害。",
	},
	"s1_yin_lei": {
		"name": "引雷", "element": "灵", "kind": "ultimate", "energy_cost": 8, "cooldown": 0,
		"range": 3, "max_targets": 2,
		"desc": "大招：射程 3 格，对最多 2 个单位各造成 1.5 真伤。",
	},

	# —— 法师 ——
	"s1_guan_huai": {
		"name": "关怀", "element": "灵", "kind": "active", "energy_cost": 3, "cooldown": 0, "range": 4,
		"max_targets": 2, "ally_target": true,
		# 不标 self_buff：关怀需要点选友方目标，标了会被当成无目标自增益而空放
		"ai": {"heal": true, "self_kind": "heal"},
		"desc": "射程 4 格：使最多两个己方单位各回复 1 点生命。",
	},
	"s1_ling_dong": {
		"name": "灵动", "element": "灵", "kind": "active", "energy_cost": 2, "cooldown": 0,
		"range": 3, "max_targets": 2,
		"desc": "射程 3 格：对最多两个角色各造成 1 点真伤。",
	},
	"s1_chi_cheng": {
		"name": "赤诚", "element": "灵", "kind": "ultimate", "energy_cost": 9, "cooldown": 0,
		"range": 4, "max_targets": 2,
		"desc": "大招：射程 4 格，对最多 2 个单位各造成 2 真伤。",
	},

	# —— 宵（魔渊首领） ——
	"s1_ke_ran_dian": {
		"name": "可燃点", "element": "火", "kind": "active", "energy_cost": 4, "cooldown": 0, "range": 0,
		"ai": {"self_buff": true, "self_kind": "buff"},
		"desc": "使自身伤害提升 30%，持续两回合；回复 10 点能量。",
	},
	"s1_yan_quan": {
		"name": "炎拳", "element": "火", "kind": "active", "energy_cost": 6, "cooldown": 0,
		"range": 1, "max_targets": 1,
		"desc": "射程 1 格：对一个单位造成 5 点伤害，并附加 1 层【烧伤】。",
	},
	"s1_bu_zhi_huo": {
		"name": "不知火", "element": "火", "kind": "active", "energy_cost": 5, "cooldown": 0,
		"range": 5, "max_targets": 2,
		"desc": "射程 5 格：对最多两个单位各造成 1 点伤害，并附加 2 层【烧伤】。",
	},
	"s1_lian_yu": {
		"name": "炼狱", "element": "火", "kind": "ultimate", "energy_cost": 10, "cooldown": 0, "range": 0,
		"ai": {"self_buff": true},
		"desc": "大招：使全体单位【烧伤】清零并造成 1 点真伤；任意单位每 1 层烧伤，清零时额外受到 0.2 真伤。",
	},

	# —— 龙 ——
	"s1_jiao_zuan": {
		"name": "角钻", "element": "火", "kind": "active", "energy_cost": 0, "cooldown": 0,
		"range": 4, "max_targets": 2,
		"desc": "射程 4 格：对最多两个单位各造成 2 点伤害（龙炎：附带 10% 真伤）。",
	},
	"s1_long_xi2": {
		"name": "龙息", "element": "火", "kind": "active", "energy_cost": 3, "cooldown": 0,
		"range": 4, "max_targets": 2,
		"desc": "射程 4 格：对最多两个角色各造成 2 点真伤，并附加 1 层【烧伤】。",
	},

	# —— 熊 ——
	"s1_yan_zhua": {
		"name": "炎爪", "element": "火", "kind": "active", "energy_cost": 0, "cooldown": 0,
		"range": 2, "max_targets": 1,
		"desc": "射程 2 格：对一个单位造成 2 点伤害，并附加 1 层【烧伤】。",
	},
	"s1_yan_ya": {
		"name": "炎牙", "element": "火", "kind": "active", "energy_cost": 0, "cooldown": 0,
		"range": 2, "max_targets": 1,
		"desc": "射程 2 格：对一个单位造成 3 点伤害，并附加 1 层【烧伤】，使其速度减 10。",
	},

}
