#!/usr/bin/env python3
"""探针「注册或豁免」闸（lane w27-k4，来源 k11 审计「最该补的门禁」第 2 条——
原文：「每支不被一键跑引用的探针，compile 门禁之外加一道『注册或豁免』闸——SCRIPTS 登记只管编译，
不管被跑；以 gate_json.py families / not_family 同款思路收编 tools/ 下 *_probe.gd，防『探针立了坟』式
欠账再发生（本批即有 b2 一支漏网）」。k11 抽样总表末行 qa_rest_days_probe 漏注册一支由 wave27 k3 收，
本片是普查所有同类漏网并把闸建起来）。

覆盖名单两处（探针满足其一即算在册）：
  一、gate_json.REGISTRY 里 file 恰为 tools/<探针>（qa_pirate_boat / save_robust / save_migrate 三支）；
  二、gate_json.SHOT_PROBES 截图册（16 支）——截图脚本走 shot_gate 收尾、已在批量巡检批量跑，算「被跑」。

既不在册也不在 EXEMPT 的探针，每支行首红字点名，退 1（漏网 = 探针立坟，k11 原话）。

既在册又列豁免的「双列」同格判红、点名该行（w29-k3 收尾留口 / 审计-wave29 C3.2b 实证：升格进注册表后
旧 EXEMPT 行忘删，现闸本判不出；与「漏册」行格成对偶），REGISTRY ∪ SHOT_PROBES ∩ EXEMPT 须为空集，
点名行形如「✗ 双列：tools/<探针> 同列 REGISTRY + EXEMPT——<行号>」（<行号> = EXEMPT 行序）。

EXEMPT 每行三格（形状卡死，缺格判红）：探针名 / lane 或来源 / 理由一句。
登记豁免的原则（与 rules-table 型门禁同规矩，五.3）：探针确实已在仓库里、只是「被谁跑、何时跑」还没挂上
注册表时才登记豁免；探针已删，先删名单行——名单指着不存在的探针（act 格）、名单漏格（形状格）都判红。

EXEMPT 挂账尾字样收尾闸（lane w34-k1，w31-k6 欠账复派：其原语「两候判净：EXEMPT 的 reason 栏字样原义
——闸判不出『超 N 波』形；两格都未守。何取何舍：分化 ① 首选（EXEMPT 收尾闸）」；w32-k1 SETTLED (d)
同族欠账收编）：EXEMPT reason 栏含「归后续 lane」字样的行 = 挂账缓兵，注册挂哪档归后续 lane 收编；
挂账超挂账基线窗 N 波未收编 = 逐行判红、点名该行（形如「✗ EXEMPT 收尾闸：EXEMPT[47]——qa_calendar_probe.gd
挂账基线窗 N=7 波已过未收编」）。本闸只判后收（收编动作与归口归后续 lane 条款照旧），
不改名单行本体、不替后续 lane 收编、不判同形字样「随 lane-XX 落地验过留档」（w31-k6 已查非本案）。

  挂账基线窗（N）口径（写死在本脚本头注，判据 §五.3 第 4 条同规格——断路径零节先红）：
    窗口数 = git log <BASE>..HEAD 里 commit 主题匹配「(lane-w」的落地笔数——0f217b9（w27-k4 本闸落地尖）
             起算、每片 lane 落地笔 = 一「波」；docs(ops) 与 decision_refs 跟号片主题不带 (lane-w 不计波；
             HEAD 在途 lane 合进 main 才算。
    N 阈值   = 7（w31-k6 判净时点窗已过 7 波仍只见字样不收编——超 N 即红）。
    BASE     = 0f217b9（挂账字样首现的 commit：w27-k4 本闸落地尖）。
    「超 N 波」= 现窗 - 本行字样首现挂账笔窗 > N；每行字样首现挂账笔以
               `git log -G '归后续 lane' -G <探针名> -- tools/check_probe_registry.py` 最旧一笔认定。

案例数不写死（w53 待拍板 35，lane w53-14）：gate_json.REGISTRY 各条的文字只写「cases=N fails=0」，写出 cases=<数字> 即红
（判绿本就只看退出码与 fails=0，写死的数每加一格就过期）。第四节，带一对内存样本自检。

直接用法：

  python3 tools/check_probe_registry.py          # 门禁：普查 git 已跟踪 tools/*_probe.gd，漏册漏豁免退 1
  python3 tools/check_probe_registry.py --json   # 机读（gate_json 转接，docs/GATES.md §二）

零节（GATES §五.3）每次先在内存里跑：E1 拼错一个豁免名（对不上任何探针）须红、E2 删一格豁免放一支漏网须红、
E3 移动覆盖名单把 qa_pirate_boat 挪出 REGISTRY 须红、E4 造双列（已在册探针再买一格豁免）须被双列行格点出、
E5 收尾闸断路径格（刻名 lane-w26-k9 / lane-w28-k3 账族：run_toll 断路径入参两支挂账账族——
须被断路径名指点出，探不出 = 收尾格判路瞎）、
C1 现网名单须全绿、形状格（缺 lane / 缺理由）须红。
"""
import os, re, subprocess, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)

# ── 豁免名单（每行：探针名 / lane·来源 / 理由一句；行序按探针名字典序，新行插对位置）──
EXEMPT = [
    ("atmos_water_probe.gd", "c1f0e5a feat(atmos)", "海面着色器观感探针，只判「起得来、出图」式观感，入册口径未定"),
    ("combat_outcomes_probe.gd", "98a76c9 feat(combat)", "海战胜负三维演出探针，战果接线已归 combat_realism 锚点档"),
    ("combat_realism_probe.gd", "38e4584 feat(combat10)", "写实海战冒烟探针，剧情挂钩锚点验证完即留档，尚无 when 判据"),
    ("japan_ship_probe.gd", "f7a6dc5 feat(ships)", "船近景四支之一，已接 shot_gate 压帧（gates_md 入册判据认它），截图档待挂"),
    ("letterbox_signal_probe.gd", "7a47d15 lane-gd12", "墨边收尾信号契约探针，已挂 shot_gate 压帧，不属于截图册 finish_shots 系"),
    ("qa_bribe_probe.gd", "2552fa8 lane-w23-a5", "塞钱 48 格实测表：断言全注掉的纯取证探针（现态留档，不判红绿）"),
    ("qa_contract_destinations_probe.gd", "5f41ab4 lane-w23-a8", "V0928 委办目的园取证探针（零断言纯取证，现态×A+ 豁免镜像留档）"),
    ("qa_contract_stock_probe.gd", "160c99e lane-iz2", "委办「凑得出」现货口径专项探针，断言随 lane-iz2 落地即验过"),
    ("qa_customs_duty_probe.gd", "2bbd7b7 lane-ea3", "市舶验引税率专项探针，税率公式归 verify_economy 必跑档复判"),
    ("qa_economy_spread_probe.gd", "e072e92 lane-ea", "同港价差地板专项探针，价差公式归 verify_economy 必跑档复判"),
    ("qa_fine_text_probe.gd", "9413160 lane-ae", "罚金文案夹现银专项探针，文案归 lane-ae 落地验收、无常驻 when"),
    ("qa_iz_skip_notice_probe.gd", "5207390 lane-w23-a7", "候一日压月初通告专项探针（P7 IZ2-3① 取证留档）"),
    ("qa_money_notices_probe.gd", "ebe8496 lane-fo", "买卖扣钱/出舱返回值专项探针，随 lane-fo 落地验过留档"),
    ("qa_port_beats_probe.gd", "53c0499 lane-w26-k7", "PortBeats.due 终局守卫探针，接口下沉后 when 判据未定"),
    ("qa_save_slot_tip_probe.gd", "e92d2be lane-t", "航海日志坏档/.bak 纪实提示探针与契约锁，随 lane-t 落地验过留档；本进程 SCRIPT ERROR 即红（lane w53-5 六轮接计数）"),
    ("qa_shore_wait_notice_probe.gd", "802e54d lane-w26-k5 族", "岸上等待通告专项探针，随该族落地验过留档"),
    ("qa_w53_11_run_watch_probe.gd", "lane-w53-11", "截图门禁共用件 shot_gate「_run 断气」看门自证（喂入口 _run 出错须宽限两帧判红、子函数错不响），headless 秒级，动 shot_gate.gd / script_err_tally.gd 时加跑"),
    ("qa_w53_13_decide_probe.gd", "lane-w53-13", "w53 待拍板逐条定下后的修复回归探针（跳年封顶等，一段钉一条、回退即红），headless 可跑，随 lane-w53-13 落地验过留档"),
    ("qa_w53_15_cut_probe.gd", "lane-w53-15", "战斗方案二期新号令「砍钩」（order_cut_grapple）：cut_chance / 面板 6 号开关 / WorldMap 守方借改，回退即红，headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_15_intel_probe.gd", "lane-w53-15", "战斗方案一期「敌情与号令」：敌情列（enemy_intel 开 / 关对照）、布色船种、我方士气 20/10 险档提示条，headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_15_parley_probe.gd", "lane-w53-15", "战斗方案一期「劝降钮挂敌船、三样凑齐才亮」（parley_on_ship 开 / 关对照），headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_15_role_probe.gd", "lane-w53-15", "战斗方案二期职事「总管管损」「夷人减伤」（crew_role_effects，DamageModel 一侧）：乘法 / step / 伤亡 / 接线四节，回退即红，headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_15_shipcard_probe.gd", "lane-w53-15", "战斗方案一期「点敌船或 Tab 选中出小卡」（enemy_intel）：Tab / 点行选中、喊话钮亮灭跟 parley_road、细看钮展开，回退即红，headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_15_wet_probe.gd", "lane-w53-15", "战斗方案二期新号令「张湿毡」（order_wet_felt）：DamageModel 点火折半/火账减半/伤亡×0.7、面板 7 号接线，回退即红，headless 秒级，本 lane 收尾并闸"),
    ("qa_w53_16_aftermath_probe.gd", "lane-w53-16", "战斗方案一、二期战后单子与赏钱专项探针（13c 护航接任旗、分赃、单子、大风两散、gale 键、杂事缴获；一段钉一条、回退即红），headless 可跑，随 lane-w53-16 落地验过留档"),
    ("qa_w53_17_morale_probe.gd", "lane-w53-17", "士气与风专项探针（大风两散 / 战后士气带回航程 / 火长提前报风 / 通事劝降效力，一节钉一条、回退即红），headless 可跑，随 lane-w53-17 落地验过留档"),
    ("qa_w53_1_battle_sea_name_probe.gd", "lane-w53-1", "海上遇敌的海域名按船当日所在取港探针（全港对 × 航程 5%…95% 对离船最近港；实点「迎战」海盗 / 元军哨船，验题签与海战海况海域），修恒取起锚港"),
    ("qa_w53_1_chart_follow_ship_probe.gd", "lane-w53-1", "远程航行镜头跟船探针（真游戏逐日链式推进：每日船标在图带里、拖开不拽回、航行中收展牌、按住空格快进），随本 lane 落地验过留档"),
    ("qa_w53_1_compass_needle_probe.gd", "lane-w53-1", "海图罗盘针名与去向牌一致探针（全港对现建去向牌对针名、照玩家点牌逐张对、航行中跟当日罗经），修未发舶罗盘取出港第一段"),
    ("qa_w53_1_dest_hint_probe.gd", "lane-w53-1", "目的地出带箭头不压港框 / 港名 / 船标探针（选向 / 放大 / 航行三种镜头 × 全港对），随本 lane 落地验过留档"),
    ("qa_w53_1_hud_overlap_probe.gd", "lane-w53-1", "海图港名 / 地名 / 出带箭头不压罗盘盘面 / 盘下针名 / 题记框 / 比例尺探针，港位落在 HUD 下时不写港名；修港名只避港框船标"),
    ("qa_w53_1_plan_sail_days_probe.gd", "lane-w53-1", "航段推演日数与实航逐日走法对账（Voyage.plan 逐段吃风 = SeaChart 逐日取所在段罗经），修出湾段方位套全程"),
    ("qa_w53_1_port_name_click_probe.gd", "lane-w53-1", "海图点港名即选那港探针（真输入从根视口推入：点港框 / 点港名 / 悬停港名 / 点海面，全图 + 四港选向 + 每港三档放大），修只认港位 14 px"),
    ("qa_w53_1_region_label_probe.gd", "lane-w53-1", "海图地区名（日本 / 筑前……）不压港框、港名与小字地名探针（全图 / 全港对选向 / 每港六档放大），修地区名不做避让"),
    ("qa_w53_1_trail_marker_probe.gd", "lane-w53-1", "海图走过那段航线的描深末端落在船标上探针（三条远程 + 一条近程逐日真推船标、每帧量描深末端离船标），修描深按里程比例、船标按折线弧长两套口径错开"),
    ("qa_w53_2_combat_overkill_probe.gd", "lane-w53-2", "击沉过量伤亡专项探针，随 lane-w53-2 落地验过留档"),
    ("qa_w53_2_combat_probe.gd", "lane-w53-2", "海战接舷 / 号令 / 收战账目专项探针，随 lane-w53-2 落地验过留档"),
    ("qa_w53_3_buy_max_probe.gd", "lane-w53-3", "牙行买满结算耗时与逐件推演同数专项探针，动 Economy 逐件推演或牙行买钮回调时加跑"),
    ("qa_w53_3_contract_keep_probe.gd", "lane-w53-3", "在身委办的货不上秤（卡上括注委办件数 / 卖钮只卖其余 / 全灰时要卖先毁约）专项探针，动牙行卖钮或 GameState 委办簿时加跑"),
    ("qa_w53_3_economy_probe.gd", "lane-w53-3", "牙行抬价/赊贷/委办三本账守形探针，随本 lane 落地验过留档"),
    ("qa_w53_3_fleet_sell_probe.gd", "lane-w53-3", "多船牙行卖出不分船（柜上第一席 / 卡上舱数 / 卖钮跨船 / 赚亏按卸下成本）专项探针，动牙行卖钮或 Fleet 跨船扣货时加跑"),
    ("qa_w53_3_hold_split_probe.gd", "lane-w53-3", "分船货舱水粮摊派不越全队载重专项探针，动 Fleet 舱位账或牙行/船屋装货回调时加跑"),
    ("qa_w53_3_market_rerender_probe.gd", "lane-w53-3", "牙行页整页重排带字进树计数与按买耗时专项探针，动牙行页建页或 Main._attach_quiet 时加跑"),
    ("qa_w53_3_rumor_probe.gd", "lane-w53-3", "海上记下的行情传闻写在别港同一货牙行卡上专项探针，动 GameState 传闻簿或牙行卡第二行时加跑"),
    ("qa_w53_4_chapter_hint_probe.gd", "lane-w53-4", "章节 hint 走数据上屏专项探针，随 lane-w53-4 落地验过留档"),
    ("qa_w53_4_epilogue_fit_probe.gd", "lane-w53-4", "终局航海札记边记攒多不把动作行挤出画外（帧后量岸带与动作行），动终局港页札记笺时加跑"),
    ("qa_w53_4_story_probe.gd", "lane-w53-4", "剧情 advance_text 宣港对账专项探针，随 lane-w53-4 落地验过留档"),
    ("qa_w53_5_half_write_probe.gd", "lane-w53-5", "半写档探针（只写 .tmp 注入：记录与迁移回写须核对后才落位），动存档写入路径时加跑；本进程 SCRIPT ERROR 即红"),
    ("qa_w53_5_load_log_probe.gd", "lane-w53-5", "读档后船籍簿记事栏探针（读早一卷不留后事、勾稽一声照记、坏卷不清），动读档流程时加跑"),
    ("qa_w53_5_roundtrip_probe.gd", "lane-w53-5", "存档全字段往返探针（to_dict↔from_dict 逐键等比），动存档结构时加跑；本进程 SCRIPT ERROR 即红"),
    ("qa_w53_5_save_sheet_probe.gd", "lane-w53-5", "航海日志册页钮态、记录回执与键盘焦点探针（标题页续卷「记录」不给按、新版卷不给记、「翻阅」按 can_load、港页翻阅两下才翻、记录写不进不报已记入、焦点不漏到暗幕底下、Esc / Enter 合上），动 SaveSheet / 续卷接线时加跑"),
    ("qa_w53_6_beat_replay_probe.gd", "lane-w53-6", "港口节拍不重演回归探针（新局卷首走到首抵泉州、老档补账），随 lane-w53-6 落地验过留档"),
    ("qa_w53_6_guild_spreads_probe.gd", "lane-w53-6", "行会抄本 / 打听不荐牙行闭门港回归探针（博多封港、福州围城），随 lane-w53-6 落地验过留档"),
    ("qa_w53_6_port_exits_probe.gd", "lane-w53-6", "港内设施页各有「离开」回归探针（玉湖陈宅补回），随 lane-w53-6 落地验过留档"),
    ("qa_w53_6_shore_hand_probe.gd", "lane-w53-6", "港页今日三门发牌端到端探针（候一日换门、缺人缺粮钉船屋、离开回港不换），随 lane-w53-6 落地验过留档"),
    ("qa_w53_6_shore_hint_probe.gd", "lane-w53-6", "岸带行首注与门数对得上回归探针（崖山 / 辞呈 / 纲首特殊卡追加时），随 lane-w53-6 落地验过留档"),
    ("qa_w53_6_yard_chips_probe.gd", "lane-w53-6", "船屋 / 寺观工席小钮钮面与实账对账探针（修船 / 购入 / 换坞 / 添人 / 水粮 / 赊还 / 细看 / 拓碑），随 lane-w53-6 落地验过留档"),
    ("qa_w53_7_tavern_crew_probe.gd", "lane-w53-7", "酒馆与人物专项探针（欠饷随名册清空归零等），随 lane-w53-7 落地验过留档"),
    ("qa_w53_8_codex_cols_probe.gd", "lane-w53-8", "人物志名册格列数随页宽探针（超宽画布钉死九列回退即红），带窗口或 headless 皆可跑，随 lane-w53-8 落地验过留档"),
    ("qa_w53_8_font_floor_probe.gd", "lane-w53-8", "字阶下限探针（泉州对峙「征船名册」分节小题钉 13 回退即红），headless 与带窗口皆可跑"),
    ("qa_w53_8_letterbox_fit_probe.gd", "lane-w53-8", "海战墨边题签长副题不冲出画布右缘探针（只缩题名、副题冲出 116 px 回退即红），headless 直接实例化墨边可跑"),
    ("qa_w53_8_panel_seam_probe.gd", "lane-w53-8", "页面面板九宫纵向接缝探针（800×600 / 4:3 / 竖屏面板中腰泥金碎钩回退即红），headless 纯算、带窗口另实画"),
    ("qa_w53_8_tooltip_wrap_probe.gd", "lane-w53-8", "悬停提示超宽折行探针（顶匾记事 85 字提示宽过 1280 画布被裁回退即红），headless 与带窗口皆可跑"),
    ("qa_w53_8_vision_layout_probe.gd", "lane-w53-8", "市舶纪事 VisionStage 画布适配探针（钉死 1280 实锤回退即红），when 判据未定"),
    ("qa_w53_9_chapter_card_probe.gd", "lane-w53-9", "章节卡题记留读时长、「点击继续」时机与题记一句一列专项探针（四章 × 两种窗口比例、回退即红），须带窗口（-s），随 lane-w53-9 落地验过留档"),
    ("qa_w53_9_chapter_year_probe.gd", "lane-w53-9", "章节卡年号与历法逐月同口径专项探针（改元当年认月份），headless 可跑，随 lane-w53-9 落地验过留档"),
    ("qa_w53_9_cutscene_input_probe.gd", "lane-w53-9", "过场 / 墨幕层输入时序专项探针（逐路钉一处修复、回退即红），带窗口以场景启动，随 lane-w53-9 落地验过留档"),
    ("qa_w53_9_cutscene_probe.gd", "lane-w53-9", "过场连点字幕与提前合并成一拍族，同一拍帧自检，不入截图册 finish_shots 系"),
    ("qa_w53_9_port_banner_probe.gd", "lane-w53-9", "海图回港抵港横幅（挂签式）在 16:9 / 16:10 / 4:3 / 竖屏 / 超宽下都挂在港名匾下专项探针（回退即红），带窗口以场景启动，随 lane-w53-9 落地验过留档"),
    ("qa_w53_p3b_firerot_probe.gd", "lane-w53-p3b", "战斗三期火攻回到装填轮换专项探针（fire_attack_load 开时三档轮换 / 引火乘数上乘 / 关时两档且签面提示逐字回 w53-2 账，回退即红），headless 秒级，随 lane-w53-p3b 落地验过留档"),
    ("qa_w53_p3c_ammo_low_probe.gd", "lane-w53-p3c", "敌将「弹药告急」回归专项探针（三期开关开/关两态逐格对账，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w53_p3c_intel_ff_probe.gd", "lane-w53-p3c", "敌情列「水火短注」专项探针（鸭子型 ff_note_of 阈值格——burning 按真挂件契约 PackedStringArray 段名表 + intel_line_of 开关两态 + 布景对照 + 1280/960 排版），headless 秒级，回退即红，随本 lane 落地验过留档"),
    ("qa_w53_p3c_winrate_probe.gd", "lane-w53-p3c", "三期开关胜率工具（合并 p3b/p3c 两份：同种子表 × 300 秒窗 × 敌将 live × 士气裁决早收 × 物理帧泵 × 玩家驾驶转舷齐射；--on=flood,fire / --off / 单开一档，--compare 两段对阵——现有对照 福船60对快船×2 + 逆风对照 对元军海鹘；同种子复跑逐场一致自检、hang 判红），headless 可跑（24 种子给 GLOCK_TIMEOUT 放宽），随本 lane 落地验过留档"),
    ("qa_w53_p4_after_choices_probe.gd", "lane-w53-p4-after", "战斗方案 §三「战后」战时取舍专项探针（押船分人看守 / 救落水加名声收编 / 俘虏收编卖放 / 索赎当场折价兑付 / 追击掷一次多夺一艘或再挨一顿；开关 waa_* 各节回退即红；默认项不长赚），headless 可跑，随 lane-w53-p4-after 落地验过留档"),
    ("qa_w53_p4_melee_probe.gd", "lane-w53-p4-melee", "战斗方案四期「白刃三决断 + 敌船脱离留追窗」专项探针（压上 / 收势胜负账、超时默认照自动、开关 melee_decision 关逐字回旧、追窗 pursue_window 离场线 / 挫速被咬住，一段钉一条、回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w53_p5_blockade_probe.gd", "lane-w53-p5-blockade", "战斗方案五期拦港（待拍板 20b）与闯封锁专项探针（晨潮三向不发封港 / 围城 / 对己封港的港、海图上点它只给「港已封」、剧情要去的港放行并与 Main 卡判据逐月对账；闯封锁四成撞上哨船（固定种子统计）、赢了照围城米价卖粮且一趟收量封顶、输 / 逃 / 掉头米粮没收船折回、迎战真起 WorldMap 一场；开关 port_blockade / blockade_run 关逐字回旧，一段钉一条、回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w53_p5_siege_probe.gd", "lane-w53-p5-siege", "战斗方案五期守城专项探针（陆战骰子搬进 SiegeMelee 前后同种子逐阵一致 / 行事表日子与小笺 / 外援四样增减与开关关态逐字回旧 / 仍最多三阵与外援全开全关守住概率 / 外援记账存档来回，一段钉一条、回退即红），headless 两分钟内可跑，随本 lane 落地验过留档"),
    ("qa_w53_p5_war_prices_probe.gd", "lane-w53-p5-econ", "战斗方案五期「军需涨价」专项探针（开关 war_prices 关时六个战况月全部港货价与改前原式逐字相等、被围港米 1.8 / 军械 1.5 倍且米不叠两遍、降元港奢侈贵米贱、对峙小涨、牙行卡价格旁短注、价差地板，回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w53_p6_escort_probe.gd", "lane-w53-p6-escort", "战斗方案六期「护航船上阵 + 三道将令」专项探针（上阵船数与同屏八艘封顶、列队 / 曳敌 / 夺舱各自的走法与白刃、键盘 / 鼠标 / 触屏下令、结算记账不记两遍、旗舰沉护航接任、开关 escort_battle / escort_orders 关逐字回旧，一段钉一条、回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w53_p6_landing_probe.gd", "lane-w53-p6-landing", "战斗方案六期小规模登陆战专项探针（入口四样齐才挂那一行、下船人数封顶与战力式子对守城那一路逐位相等、骰子借 SiegeMelee.clash 同种子逐位相等、五档船型固定种子 1..200 的胜率界、胜败两路的账、收队回船不动、开关关态逐字回旧、真起 SeaChart 收战扣住 source 走判据、期望收益对照 simulate_run 开局跑商两条界、真走 SeaChart 落账（胜 / 舱快满 / 败 / 收队）与札记一句，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w53_p6_perf_probe.gd", "lane-w53-p6-escort", "战斗方案六期性能探针（同屏八艘开打量 600 帧以上的平均帧时与 p95，escort_battle 开 / 关各一份，崖山突围一档有 YashanBattle 才跑、没有就跳过；另报同屏船数、粒子总数），帧时要 DISPLAY=:2 带窗口才作数、headless 只判跑通，随本 lane 落地验过留档"),
    ("qa_w53_p6_yashan_probe.gd", "lane-w53-p6-yashan", "战斗方案六期崖山突围战专项探针（崖山卡第三扇门「上船同去」开关开 / 关两态、这一场海况取港湾那一档（雾 / 窄水 / 风向风力）与数据档逐项对账、火船摆下（独立 FireShip_ 前缀不进士气簿 / 敌全灭 / 追兵、同屏不超 8 艘、开关关一艘不留）、碰上就点火的旗舰篷帆引火与撞伤并记「碰过了」不重复点、冲出 / 没冲出两式判词与结局那一句、收战写两枚旗且寻常海战不写；一段钉一条、回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w54_a11y_escape_probe.gd", "lane-w54-a11y", "Esc 有出口专项探针（九处设施页按 Esc 回港页、钱与日子不动；见面页 Esc 回设施页；只一条「离开」的剧情页 Esc 同点离开、挂 no_enter 的岔路不替人选；船籍簿开着先合船籍簿；港页不动、册页不替人落定；人物志开着只合人物志；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_a11y_focus_keep_probe.gd", "lane-w54-a11y", "页面重排后焦点不丢专项探针（牙行第三张货单「买 1」回车买进、整页重排后焦点还在新排同一颗上、再回车又买；「卖 1」同；港页「再候一日」连按两回过两日；旅店「歇 1 日」；换了页焦点空着不替人落；鼠标点「买 1」照买、不还焦点；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_a11y_focus_ring_probe.gd", "lane-w54-a11y", "焦点看得见专项探针（港页与九处设施页各从无焦点起 Tab 绕一整圈，每站都是画框的焦点、焦点样式不是空框也不同平常那个框；岸上三扇门、「今日未开」那排门、牙行「今日不在柜上」那排货名三样逐颗核；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_a11y_modal_focus_probe.gd", "lane-w54-a11y", "浮层开着焦点不走到底下专项探针（港页人物志 / 牙行页船籍簿 / 市舶纪事 / 名册 / 册页开着一路 Tab 焦点不出浮层、不落到岸门动作钮与「细则」「接下委办」；浮层开着回车不开底下的门、不按剧情页的「离开」、不接委办；人物志 Esc 合上、船籍簿「合上」后焦点回到开浮层那颗钮；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_a11y_seachart_keys_probe.gd", "lane-w54-a11y", "海图只用键盘走得通专项探针（发舶前航法三策・三张航向牌・「候风再发」「回港」收 Tab、灰着的「就这一向」与顶上三颗不收、牌上焦点框非空框；键盘选第二张牌整排重发后焦点跟到新排第二张、Tab 到「就这一向」回车起锚，起锚后九颗全退回不拿焦点、空格按不到钮、Esc 不回港；鼠标点「候风再发」点完不留焦点、空格不再候三日；C 开合船况、Esc 先合船况再回港；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_bell_probe.gd", "lane-w54-audio", "墨幕套墨幕不叠两声磬专项探针（墨幕那行入收声组 bell；两声磬隔 320 毫秒第二声响、头一声记 cut、不同组的炮声不受牵连；真起 Main 在 play_transition 全黑回调里再起一幕，同一刻只剩一声磬；带窗口那段第二声起来后根下只剩一只磬，回退即红），headless 秒级（第四段要 DISPLAY=:2 带窗口），随本 lane 落地验过留档"),
    ("qa_w54_audio_chart_probe.gd", "lane-w54-audio", "海图与港口补挂的声专项探针（启程 / 风涛 / 浅滩 / 靠港钟 / 海上沉没五行标 added、各带 gap_ms，事件名对得上 Voyage.EventKind；真起 SeaChart 发舶、遇风涛两下浪、浅滩一声、商船海寇闹舱不响、靠港钟、沉没两层；开关 sfx_cues 关同一处记 off；靠港钟与墨幕同组、后起的收前一声，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_cues_probe.gd", "lane-w54-audio", "w54 音效挂点表专项探针（表只用 SfxSynth 现成八样、dB 在 0 以下、原先七处搬进表一字不差、无头不建播放器不报错只记发声账、真起海战走入战 / 齐射 / 命中 / 接舷 / 收战各挂点；一段钉一条、回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_cutscene_probe.gd", "lane-w54-audio", "过场补挂的声专项探针（朱印落纸 / 章节卡开卷两行标 added、章节卡与墨幕同组；真起 cs_seal 触纸那一刻响一声、回弹不响、一口气补全只响一声、三方印同帧补全只响一声；ChapterCard 开卷一声磬、墨幕紧接时收掉；开关 sfx_cues 关记 off、印照样触纸，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_flee_probe.gd", "lane-w54-audio", "逃没逃掉不放撤离风声专项探针（收战认挂点 flee_ok 假 / 缺 → 败局那一声，甩脱 / 两散 / 大风两散 / 崖山冲出照放风声；真起海战真按 B 键掷输记 sea_lose、同一份战果喂真海图札记写「未能甩脱」；必脱照放 sea_flee；我方溃逃没跑掉同记 sea_lose，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_landing_probe.gd", "lane-w54-audio", "登岸剿寨补挂的声专项探针（得手 / 失手两行标 added、鼓加磬两层；真起 SeaChart 按收拾停当、按种子剿寨得手记 landing_win 两层、失手记 landing_lose 两层、不登岸不响；开关 sfx_cues 关记 off、账照旧，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_own_fire_probe.gd", "lane-w54-audio", "自家齐射不被别船炮声吞掉专项探针（旗舰齐射 sea_fire_own 与敌船开炮同声同量、节流各认一把锁；真起海战敌船真放一排后同一毫秒旗舰齐射两声都响、反过来也都响；同一把锁 90 毫秒内照旧节流，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_sea_probe.gd", "lane-w54-audio", "海战补挂的声专项探针（火船点着 / 起火 / 火药舱炸 / 桅倒 / 沉船 / 降幡 / 钩索落空 / 护航接舷 / 号令 / 重弹落水十行标 added、各带 gap_ms；开关 sfx_cues 关时十行记 off、原先那几行照响；真起海战逐处走真路各记一笔、撤令与一排矢落水不响；补挂行节流不抢原先的锁，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_siege_probe.gd", "lane-w54-audio", "守城补挂的声专项探针（城门 / 囊山胜负 / 拆船料 / 城破五行标 added、胜负两行鼓加磬两层；真起 Main 海口入城卡、旧档自动入城、关城门落闸各一声城门，囊山设伏与出海劫粮道记胜负两层，拆船料一声，城破两层；开关 sfx_cues 关同一处记 off、账照旧，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_audio_voices_probe.gd", "lane-w54-audio", "同一帧连要几声声部上限照样作数专项探针（同一刻七样不同的声前六响第七记 voices、按声长让出声部、探针钟往回拨不卡死；带窗口那段同一帧只建六个播放器、放完都释放，回退即红），headless 秒级（第四段要 DISPLAY=:2 带窗口），随本 lane 落地验过留档"),
    ("qa_w54_chartui_name_band_probe.gd", "lane-w54-chartui", "海图港名摆位专项探针（全图、选向与拖到图带四边的 743 个镜头逐港复算八处候选：港框在带里的港名出带只在带里每一处都压东西时、压东西只在八处都压时、落点是八处之一、合计出带 / 互压 / 压港框 / 压 HUD 块不比改前多；贴边港名摆到屏幕外、六处都撞时名字压名字回退即红），headless 约半分钟，随本 lane 落地验过留档"),
    ("qa_w54_combatai_spawn_probe.gd", "lane-w54-combatai", "海战敌阵摆位探针（真 WorldMap 开战那一帧读敌船落位：闯封锁海鹘一 + 快船二六个种子三艘两两相距 ≥ 600 px、崖山海鹘一 + 快船一三个种子两艘相距 ≥ 1000、只一条的阵第 k 艘落在 TAU·k/N ±0.25 rad 与改前同式，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_copy_probe.gd", "lane-w54-copy", "w54 文案一致性专项探针（门牌悬停提示的地名与门牌同字等，静态一侧是 check_w53_copy 的钉；一段钉一条、回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_econ_peak_probe.gd", "lane-w54-econ", "章节本钱按现银减欠款记专项探针（真挣两千在船屋借满三千峰值不动且不晋升、当场还清峰值不动、无欠款照旧晋升、欠着款挣钱按净值涨、花钱结息不动峰值，回退即红），headless 秒级，动 GameState.add_money / 赊贷 / 章节本钱时加跑"),
    ("qa_w54_econ_permit_probe.gd", "lane-w54-econ", "货引按出港时的舱货抽解专项探针（空舱请领再装货出港补足、装好货再请领不补且札记逐字照旧、卖掉不退、补不起不放行货引舱货都在、旧档的货引照旧放行、permit_base 存档与坏值、市舶司页货引卡、真按出港补不起留港，回退即红），headless 秒级，动货引 / 抽解 / 出港验放时加跑"),
    ("qa_w54_econ_sea_sell_probe.gd", "lane-w54-econ", "海上相逢收货只挑 tradable 的舱货、不收在身委办要交的那几件专项探针（只装账物 400 回不开价收、账物与货混装回回收货、只装账物与空舱同种子逐回一字不差、委办货不开价且多出几件至多收几件，回退即红），headless 秒级，动 Voyage 海上买卖、goods.json tradable 或委办留货时加跑"),
    ("qa_w54_ending_era_line_probe.gd", "lane-w54-ending", "升章册页「这一路」主航线写纪实句专项探针（真记四趟航行、真开第二章：写「走得最多的是泉州到<港>那一程」、整页正文不出「→」，账里的键照旧；反向基没记起讫港只写跑了几趟，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_ending_late_lines_probe.gd", "lane-w54-ending", "章节过渡页写到的人已不在世就不写他在场专项探针（林阿舶 1274 病故：1272 / 1275 真进泉州开第三章、按「承此一路」进晋升过场幕不写他在廊下等你；1272 开第二章跳年落在 1274、1275 封顶不跳，册页不写他推油布包；人物志同判已不在世；反向基 1262 / 1257 / 1271 照旧写他本人，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_ending_place_probe.gd", "lane-w54-ending", "终局港页匾与首进题签写结局收在的地方专项探针（崖山交粮 / 上船同去冲出与没冲出真开突围那一仗：匾与题签题「崖山・海上宋鬼」、副题与札记抬头即落款，重读合上不累加、存档读回照旧；涵江出海「旧避风澳・岸上的根」；反向基福州未归、泉州纲首、守城援绝「兴化军・忠肃」、落款空着的旧档照旧写港名，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_ending_yashan_cine_probe.gd", "lane-w54-ending", "「海上宋鬼」结局过场按崖山实际走的路出字专项探针（交粮三路真按崖山页的钮：写交粮、砍缆，船慢另补「砍晚了」、船快三镜逐句同原先；上船同去真开突围那一仗、真走 WorldMap._battle_exit 收战：冲出 / 没冲出各写册页里那一句、不写交粮砍缆；换句那一格只出一句、那一句在册页正文里，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_ending_years_probe.gd", "lane-w54-ending", "终局抉择页与结局页里回指开局的「N年前」按开局年算专项探针（真开士人线辞呈页：正文与三条去向册页每处「N年前」= 本年 − 宝祐三年；涵江出海册页与结局过场「二十二年前」同算，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_gates_zero_case_guard_probe.gd", "lane-w54-gates", "探针「一格断言都没跑过也照印全部通过」守卫探针（静态读 qa_w53_4_story_probe.gd：两档非空那格断言在、_check 记 cases、收尾 cases 参与判红；带反例 / 正例内存自证），回退 qa_w53_4_story_probe 那笔即红，headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hud_intel_fit_probe.gd", "lane-w54-hud", "海战右上敌情卡长写法放得下专项探针（伤沉在即・想退・失火进水的行与选中小卡逐行字宽 ≤ 栏宽、整张卡不被撑宽不出画布、两钮在画内，1280×720 与 21:9 各一遍；行尾「进水」被裁、卡撑到 326 宽右沿冲出 60 px 回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hud_intel_tide_probe.gd", "lane-w54-hud", "海战敌情卡跟着顶匾高矮挪专项探针（钱 123456、舱里六样货开打，顶匾右格折三行长到 114 高；敌情卡上沿在顶匾下沿之下、货抛光跟着上来、再进货跟着下去，1280×720 与 21:9 各一遍；敌情卡钉在 y 90 压进匾里 32 px 回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hud_orders_state_probe.gd", "lane-w54-hud", "海战号令面板签面状态栏整句放得下专项探针（劝降三样缺几样、三样齐、冷却等各档写法字宽 ≤ 栏宽 122，整句「未钩住、帆索未残、阵脚未乱」裁字回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hud_tide_cargo_probe.gd", "lane-w54-hud", "海战顶匾右格「金钱　货舱」一行放得下专项探针（空舱 / 一样货照旧逐样写、六样货与钱八位收成「6 样 165 件」一行全单进悬停、货抛光回「空」，顶匾恒 72 高、货名与件数不折开，1280×720 与 21:9 各一遍；逐样写折成三四行顶匾长到 114 回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hunt_battle_ledger_probe.gd", "lane-w54-hunt", "全游戏找 bug 之海战收尾记账探针（真 WorldMap 海战 → 真 SeaChart 收战与战后收拾 → 真存读档：士气收场受降的降船没接舷不进船籍、押船行不算它、每行拣「放」收拾停当自家船与舱货一件不少；一艘护航夺下 + 一艘降了没接舷时押船只算 1 艘、放漂只摘夺来那艘、分人押留在船籍；收拾停当后存读档船籍逐字段相等，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hunt_landing_offer_probe.gd", "lane-w54-hunt", "全游戏找 bug 之剿寨那一行挂卡判据探针（w54-polish 交本 lane 的一条：内存里现编 SeaChart 子类覆写 _after_action_offer、只记挂卡那一刻读到的来处与所在港再调回父类，真走 _on_battle_result 三仗——头一回泉州外胜海寇读到这一仗、那一行挂得上；随后胜元军哨船读到哨船、不沿用上一仗的海寇；博多外胜海寇读到博多、那一行不挂，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hunt_roster_damage_probe.gd", "lane-w54-hunt", "全游戏找 bug 之海战战损统计探针（真 WorldMap 海战：护航沉、仗接着打时战损只认开战在册的船——夺来入列的不抵不顶位；只夺一艘时战损为 0；按船认不按序号——中途摘掉一艘、夺来的船排在尾也点不错船，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hunt_run_contract_probe.gd", "lane-w54-hunt", "全游戏找 bug 之闯封锁与在身委办探针（真起 SeaChart：舱里米 20、委办要 8——闯进兴化只卖 12 件、得 12 × 围城米价、舱里留 8 件够交货，札记写「在身委办要留」；被扣 / 掉头赔进去的也只是要卖的 12 件；舱里全是委办要留的米时不算闯得、城里一件也收不到，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_hunt_stray_enter_probe.gd", "lane-w54-hunt", "全游戏找 bug 之回车误按探针（真起 Main 真按键：崖山「上船同去」开打、海战一层铺在港页上时按回车 / 空格不许按到收起的「把粮与硫黄交上去」（那一扇当场落结局、加名声、过五日），收战后结局照常只落一回；看得见的翻页页回车照旧翻过去、卷首页收起后回车不重开一局，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_perf_hull_probe.gd", "lane-w54-perf", "w54 船身视口省着画（开关 hull_view_lod）专项探针（关态逐帧满画的老路、开：阈角内不重画 / 过阈角当帧重画 / 慢转画面落后不过阈角、阈角随镜头远近、出画或藏起不画且回画当帧补画、半路拨回关、带窗口开关两路同航向贴图逐像素相同；一段钉一条、回退即红），headless 秒级（第六段要 DISPLAY=:2 带窗口），随本 lane 落地验过留档"),
    ("qa_w54_polish_notes_probe.gd", "lane-w54-polish", "w54 讲解小笺专项探针（小笺表条目与文案规矩、一到六期开关键逐个清点到一张、排队一张张出与停满 / 点掉收起、已读旗随档、总开关与各自开关关态、真起海战开场排序与九样头一回露面、poll 不碰随机流、小笺摆位让敌情列与小地图、海图收战 / 战后小卡 / 封港 / 闯封锁与守城页 / 外援 / 牙行战时价各挂点；一段钉一条、回退即红），headless 可跑，随本 lane 落地验过留档"),
    ("qa_w54_port_counter_probe.gd", "lane-w54-port", "w54 牙行「今日柜上三样」同一日里不换手探针（岸上真门进牙行、货单上的真钮：三席逐席「买 1」柜上不换货单不挪位、连点同一处两回买进同一样、卖光第一席那张货单还在写「舱 0」、出门再进同一手；「明日再看」、隔日、另起一局才现发，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_port_life_probe.gd", "lane-w54-port", "w54 岸上见闻（开关 port_life）专项探针（泉州三季那一句与行首注两行、十四港三季各有一句与表一字不差、对峙 / 降元 / 被围 / 封港压过季风、再候一日不叠且跨季跟着换、守城 / 终局岸带不添、开关关逐字回旧，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_port_rumor_probe.gd", "lane-w54-port", "w54 牙行货单别港传闻不荐牙行闭门港探针（博多封港 / 福州被围 / 广州被围时取下一家开着的、都闭着写原提示、开着照取价高的，货单那一行与 rumor_elsewhere 直调一字不差，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_port_ship_pick_probe.gd", "lane-w54-port", "w54 牙行「装至」选的那艘船接委办 / 交货 / 毁约后还是那艘探针（岸上真门进牙行、委办单与货单上的真钮：选二号按三钮后仍是二号、再买 1 货进二号；离开再进回旗舰、明日再看留着两格对照，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_rep_retitle_probe.gd", "lane-w54-rep", "名声跨过职衔门槛时札记写改题专项探针（泉州牙行页真钮：名声 9 交清升在册舶牙、名声 10 毁约降籍外散商、名声 24 逾期降在册舶牙；海图事件面真钮：征船交船 4→10、难民载人 20→24、分水粮 47→48、趁夜溜走被追上 10→6 / 26→22，那一句札记紧跟「案册改题「X」。」；不跨档、名声 0 封底不写改题，回退即红），headless 秒级，动名声 / 职衔 / 委办罚条 / 海上征船难民时加跑"),
    ("qa_w54_saves_migrate_probe.gd", "lane-w54-saves", "旧版本档迁到本版逐项对探针（v1 / v2 / v3 三种仓里真有过的旧结构各摆一卷满档、外加无头 v1：读进来逐键对、迁移该变的按口径变、当时没有的键落缺省；回写的头 version 与 save_schema 同到本版、原件 .vN 逐字节保真、迁好再读不改写、读后再记再读不变），动存档结构 / 迁移链时加跑，headless 秒级；本进程 SCRIPT ERROR 即红"),
    ("qa_w54_saves_shape_probe.gd", "lane-w54-saves", "存档体检漏网的坏形状探针（读档报成功、随后照常玩即 SCRIPT ERROR 的那几型逐例钉住：类型取值坏的退副抄、本就清洗的照读清洗后那一份，读进来逛港页九设施、买卖修船、过 35 日、再记再读 0 错），动 SaveLoad 体检 / 读档清洗时加跑，headless 约半分钟"),
    ("qa_w54_saves_systems_probe.gd", "lane-w54-saves", "逐系统存档往返探针（十六个系统各用真玩法摆状态：读后五分区逐键含键序同存前、该系统读数同、同种子续跑终态与月初通告同；末节福州港页与九处设施页、兴化守城页存前读后逐行同），动任一系统的存档字段或读档流程时加跑，headless 约一分钟；本进程 SCRIPT ERROR 即红"),
    ("qa_w54_seaevents_ledger_probe.gd", "lane-w54-seaevents", "海上遇事札记与实扣对得上探针（献上买路财拿不出钱：钱够照实扣、舱空一件没搬不说搬走、整批大货 / 零头货 / 两船各一件按札记说的规矩推出的件数 = 舱里实少件数；扬帆逃走没甩脱：被抢件数照实、「船体受损 N」= 旗舰实扣、舱空不说货舱被夺、甩脱了不扣不写；献上买路财 / 塞钱免征钮上写的钱数 = 真按下去现银实扣，钱不够写囊中不足、按下去不扣；回退即红），动 SeaChart 遇事钮与回调或 Fleet.lose_cargo_ratio / damage_fleet 时加跑，headless 秒级"),
    ("qa_w54_seaevents_rumor_probe.gd", "lane-w54-seaevents", "海上相逢只传卖得了货的港探针（直调 Voyage._pick_rumor 三千回 + 真走 _merchant_event 两千回：1276-11 围城的兴化 / 兴化海口 / 广州、1275-01 封港的博多 / 萨摩一回不传，已降而牙行照开的福州照传，1276-06 对照十四个海港个个传得到；回退即红），动 Voyage 海上相逢、Economy 战况 / 封港判定时加跑，headless 秒级"),
    ("qa_w54_seaevents_shore_probe.gd", "lane-w54-seaevents", "同一处岸影一程只露一回面探针（真走 Voyage.roll_day_event 泉州→福州傍岸 1260-06：一程两千日一处不勘每处至多露一回、下一程又露得出、四处都露过面那一档照无事过、勘见了的不再露；另印十二日一程同一处重露的回数改前 / 改后；回退即红），动 Voyage 岸影抽取或发舶清记录时加跑，headless 秒级"),
    ("qa_w54_seaevents_variants_probe.gd", "lane-w54-seaevents", "海上遇事变体（开关 sea_event_variants）专项探针（关着时十二个月逐日五处逐字原句；开着风涛按季节写风、风势重补一句，无风带夏烈日春大雾，不明船影 / 海上相逢没谈成买卖 / 迷航按日子轮句、句句守住两条快船不挂旗 / 没谈成买卖 / 白走了；风涛扣数与札记账句开关两侧一样，同种子三千日逐日遇事与收尾船队开关两侧全同；回退即红），动 Voyage 遇事文字或开关表时加跑，headless 秒级"),
    ("qa_w54_seaevents_war_once_probe.gd", "lane-w54-seaevents", "战时遭遇了结过的同一程不再来探针（真走 Voyage.roll_day_event 泉州→福州 1275-06 逐日掷两千回：征船塞钱「已征」/ 交出一条船 / 抗征被追上罚过之后同一程一回不出，溜成了照常再遇，下一程真点发舶记录清掉；明州→温州 1276-03 元军哨船落帆受检放行 / 违禁货起获罚过之后同一程一回不出，甩脱了照常再遇，征船与难民船不受牵连；回退即红），动 Voyage._war_event、SeaChart 征船 / 哨船回调或发舶时加跑，headless 秒级"),
    ("qa_w54_seaevents_war_where_probe.gd", "lane-w54-seaevents", "战时遭遇看船这一日在哪片海探针（真走 Voyage.roll_day_event、海上 sea_here 摆到航线上那一港逐日掷两千回：泉州→博多到了耽罗 / 萨摩 / 博多外、泉州→流求到了流求外、广州→占城到了占城外不再征船，明州→博多到了博多外不再撞元军哨船，泉州→博多傍过已降元的温州 / 明州撞得上；不在海上或没记位置照旧看两端；海图 _refresh_status 真记的位置同判；另印几条航线改前 / 改后能撞上的里程份额；回退即红），动 Voyage._war_event、Economy.sea_here 或 ports.json war 表时加跑，headless 秒级"),
    ("qa_w54_siege_dupe_probe.gd", "lane-w54-siege", "守城衙门募兵 / 船屋修墙两页余量不过小档时不出两枚同数钮专项探针（衙门余量 10 / 50 / 51 / 160 / 360 / 募满、船屋余量 10 / 20 / 21 / 140 / 满两页各档钮字逐字、两两不同，余量 10 那一枚点下去照旧作数；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_siege_enter_probe.gd", "lane-w54-siege", "守城各页回车不替人按专项探针（衙门募兵与石手军 / 市场屯粮 / 船屋修墙 / 两封劝降书 / 第三阵前林华请命认得与不认得两式：钮都在、真回车与直调 _activate_first_choice 都不按、账面旗札记日子不动、人还在这一页，反向基点钮照旧作数；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_siege_raid_probe.gd", "lane-w54-siege", "守城外援劫粮道必败不给劫专项探针（开局小艍 / 中福船战力 39 / 人过四十士气零三档：缘由一句、直调不动账、船屋页不挂钮、门不写四日；界上战力 41 照旧劫且骰子同 SiegeMelee.clash；两条大福船照旧开；回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_story_enter_probe.gd", "lane-w54-story", "终局抉择页与剧情幕岔路回车不替人按专项探针（崖山「把粮与硫黄交上去」/ 辞呈三条路 / 泉州征船名册三枚，及 scenes.json 可见真选项两条以上的幕逐幕挂 no_enter；港页 / 见面页按回车不按上一页藏起来的旧钮：真按一次回车再直调一次 _activate_first_choice，断终局不落、日子不走、旗 / 钱 / 名声 / 倾向不动、船与水粮不动，反向基点钮照旧作数、单路幕回车照旧往下走，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_story_signoff_probe.gd", "lane-w54-story", "结局落款写结局所在地专项探针（崖山交粮 / 上船同去冲出与没冲出三路落「海上宋鬼」落款写崖山、不写广州，航海札记终局一行同；反向基福州「未归」写福州、涵江出海写旧避风澳，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_story_skip_probe.gd", "lane-w54-story", "升章跳年时身上的委办免罚作罢专项探针（w53 待拍板 15：带委办与不带委办同一局面跳两年钱、名声逐位相等，委办清空、签发港不封单、札记「跳年委办作罢」、途中无「【逾期】」、代价段写明；真走第一章开章同断；反向基不跳年的寻常逾期照旧罚，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_story_timing_probe.gd", "lane-w54-story", "剧情事件按设计年月出场专项探针（士人线辞呈卡：逐月真走日子，1275-10 不挂、1275-11 临安短札投放立旗但不挂、1275-12 起挂、未决照挂、选过一条路不挂，反向基海商线不挂，回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_tavern_ashore_probe.gd", "lane-w54-tavern", "酒馆与同伴专项探针：人在海上下不了船（史实辞船月初船在海上时人仍在船把舵、不发【辞船】不扣当月俸；欠饷满三月海上只撂下话、人还在船；真走 SeaChart._arrive 靠岸才下船、通告跟在抵港句后，泊港照旧月初走；一段钉一条、回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_tavern_hiring_probe.gd", "lane-w54-tavern", "酒馆募人题签专项探针（澎湖 / 萨摩 / 占城本无候雇之人，雇着人也不写「已雇之职不再列名。」；泉州五职雇齐、博多通事位已满两处照写，不列名人数对名册；一段钉一条、回退即红），headless 秒级，随本 lane 落地验过留档"),
    ("qa_w54_tutorial_depart_note_probe.gd", "lane-w54-tutorial", "出港验引那句带到海图探针（真起 Main 按「看风」、等真换上海图：开局无引塞钱那句进船况札记、起锚句排其上、顶匾报它，账照旧钱 890 蒲家留意 20；凭引放行那句同样带到；传话读完即清、不经港页开的海图只有起锚句；遣返留在港里不留话），修验引那句随港页当帧换掉，回退即红，headless 秒级"),
    ("qa_w54_tutorial_notes_probe.gd", "lane-w54-tutorial", "新手上手小笺专项探针（表与文案五条、与海战小笺不重名、正文里的数钉玩法源码；谁看得到：没定过不出不写旗、本机无存档定 on、有存档定 off、旗标随档、两道开关；真起 Main：港页静下来才出「靠港」、题签盖着不出、蒲家记过一笔再出「货引」、没轮到就离页的撤下不记已读、牙行出「牙行」、终局港页不出；真按「看风」换上海图：出「看风」、遇盗让路出「遇盗」、面板收起即收、没轮到就迎战 / 发舶的撤下；老玩家与旧档一张不出），回退即红，headless 秒级"),
    ("qa_w54_tutorial_supply_line_probe.gd", "lane-w54-tutorial", "船屋「补给」那一行写明单价与日耗单位探针（真起 Main 进开局泉州船屋：「水每份 1 钱　粮每份 米价 钱　每日各耗 日耗 份」数与取数处同、一行放得下；「水粮各 30　付 N」与按下记事、钱与水粮增减对得上），修两个单价字面读作存量，回退即红，headless 秒级"),
    ("qa_w54_tutorial_unsailed_permit_probe.gd", "lane-w54-tutorial", "海图没发舶就回港货引还在手探针（真起 Main 按「看风」、真按海图「回港」：凭引出港回港后引在手、再看风凭引放行不另请领钱不少、发了舶回港钮按不动引照销；无引塞钱回港不退钱与留意；补过抽解的引回港后报过的舱货照补到的数、再看风不再补），修看风放行即销引、没走这一趟也销，回退即红，headless 秒级"),
    ("qa_w54_voyage_event_cut_probe.gd", "lane-w54-voyage", "海上遇事札记写实扣探针（征船趁夜溜走被追上名声 10 / 2 / 0 写减 4 / 减 2 / 不写、难民船不停船士气 50 / 1 / 0 写减 3 / 减 1 / 不写、罚钱半句 = 现银实扣），修名声士气封底 0 时照写满数，回退即红，headless 秒级"),
    ("qa_w54_voyage_heading_wind_probe.gd", "lane-w54-voyage", "晨潮三向顺风按全程的风排探针（十四港 × 十二月 × 初十 / 三十每一手 = 按去向牌上那个风的数排出的轮转窗口、广州七月不发全程顶头逆风的占城、真开海图三张牌风行无逆风），修原先按出港第一段方位排，回退即红，headless 约十秒"),
    ("qa_w54_voyage_sea_rumor_probe.gd", "lane-w54-voyage", "海上相逢不传闭门港行情探针（1274 冬博多萨摩封港、1276 冬兴化两处与广州被围各抽四百次不挑闭门港、陷落仍开市的福州照挑、太平年月十四港都挑得到、真走海上相逢传闻港不是闭门港），修 _pick_rumor 不看战况（w54-port 交），回退即红，headless 秒级"),
    ("qa_w54_voyage_shoal_probe.gd", "lane-w54-voyage", "傍岸擦浅滩船体伤每艘各吃一份探针（三船队各减 SHOAL_HULL、旗舰见底只扣到 0、札记写实扣之和、单船同改前、甲档减伤、真走傍岸逐日抽事抽到浅滩那一日），修原先乘船数整份压给旗舰，回退即红，headless 秒级"),
    ("qa_w54_voyage_sink_home_probe.gd", "lane-w54-voyage", "沉船捞回这一程起锚港探针（闯兴化撞上哨船点「掉头回航」起讫对调后，回程风涛沉 / 海寇一仗沉都捞回泉州、换场后 Main 港页落在泉州；寻常一程与拦港当场沉对照），修折回途中沉船被捞进围城，回退即红，headless 秒级"),
    ("qa_w54_voyage_toll_empty_probe.gd", "lane-w54-voyage", "海寇买路财空舱札记探针（拿不出钱、舱空不写「搬走了三成货」且钱船舱都不动；舱里有货照旧三成并列货单、钱够照旧付钱两对照），修空舱也说搬走三成货，回退即红，headless 秒级"),
    ("qa_w54_voyage_unsailed_return_probe.gd", "lane-w54-voyage", "海图没发舶就回港不挂抵港签探针（看风后候风再发两回过六日再点「回港」不算抵港；当日回港、候过风再真发舶到福州「下船入港」两对照），修候过风原地回港也挂「抵泉州」，回退即红，headless 秒级"),
    ("qa_w55_districts_probe.gd", "lane-w55-districts", "城中各处数据与交互探针（泉州兴化各十五处、底图与交互门、买卖入股雇人传闻公凭看榜围城送米、月初入账接线、港页进城与福州无钮、兴化守城页无钮），回退即红，headless 秒级"),
    ("qa_w56_district_sim_probe.gd", "lane-w56-district-sim", "城中各处深化探针（链 flag、大比、季节、风险、小卖入股、传闻），回退即红，headless 秒级"),
    ("qa_w56_pending_districts_probe.gd", "lane-d1-pending", "待画城区探针（pending/*.json 全扫、底图尚不存在、pending_art=true、账本不暴露），回退即红，headless 秒级"),
    ("qa_yard_transition_probe.gd", "f842d3e lane-fo", "船屋修购船过场上闸探针，已挂 shot_gate 压帧，不属于截图册 finish_shots 系"),
    ("save_stale_refs_probe.gd", "c0fcb77 lane-w25-j3", "旧卷引用已删名目读档提示探针（audit_stale_refs 五类勾稽），when 判据未定"),
    ("ship_dashi_probe.gd", "802e54d feat(ships)", "船近景四支之二，已接 shot_gate 压帧，截图档待挂"),
    ("ship_exquisite_probe.gd", "f7a6dc5 feat(ships)", "船近景四支之三，已接 shot_gate 压帧，截图档待挂"),
    ("src_probe.gd", "4ba967b lane-cs15", "子串存在性探查共用件（py+gd 一对），归 check_symbols 附属档使用、不当独立门禁"),
]

# ── EXEMPT 挂账尾字样收尾闸·基线（口径见头注；拨参数=拨颁，只允许后续 lane 真收编后拨小事数）──
TOLL_WORD = "归后续 lane"           # 挂账字样（reason 栏原义；同形字样「随 lane-XX 落地验过留档」不涉案）
TOLL_BASE = "0f217b9"                # 挂账基线尖（字样首现 commit：w27-k4 本闸落地）
TOLL_N = 7                           # 挂账窗 N 波（w31-k6 判净时点窗已 7）——窗口 8 波起才红
TOLL_LANE_RE = re.compile(r"(?:feature|feat|docs|chore|fix|refactor|test)\(lane-w\d+")
TOLL_RE = re.compile(r"归后续\s*lane")  # 挂账识别格（§五.3 第 3 条块形状卡死，该变字不随现网漂）

fails = []

def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def _git(args):
    out = subprocess.run(["git"] + args, cwd=ROOT, capture_output=True, text=True)
    return out

def wave_count(base=TOLL_BASE):
    """挂账基线窗数：<base>..HEAD 里落地过 lane-w 名 commit 的「波」数（docs ops / decision_refs 跟号片不算）。"""
    out = _git(["log", "--format=%s", f"{base}..HEAD"])
    if out.returncode != 0:
        return -1  # git 不可用 = 整道跑不了（tracked_probes 已退 2 覆盖：同路兜底，不另判红绿）
    return sum(1 for s in out.stdout.splitlines() if TOLL_LANE_RE.search(s))

def toll_first_commit(name):
    """探针名字样挂账账族首现笔：git log -G TOLL_RE 棉花 + -G <探针名>现实基各路径带动；
    字样在但查不到首现（仓重写 / 搬仓）→ 返 ""，判路走现窗 0 波（不判红，防误判——该形不现实）。"""
    out = _git(["log", "--format=%H", "-G", TOLL_WORD, "-G", re.escape(name), "--",
                "tools/check_probe_registry.py"])
    if out.returncode != 0 or not out.stdout.strip():
        out = _git(["log", "--format=%H", "-S", TOLL_WORD, "-S", name, "--",
                    "tools/check_probe_registry.py"])
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    return lines[-1].strip() if lines else ""

def run_toll(exempt=EXEMPT, break_lanes=frozenset()):
    """挂账收尾判路：返回 [(行号, 探针名, 已过波数字符串), ...] 只收超限的。先判后收、不必红名单行。
    break_lanes = E5 断路径入参（「exempt lane 账族」 lane 名集合：现网挂账两支 = {'f3f092e lane-w26-k9',
    'lane-w28-k3'}）；None = 同 §五.3 第 3 条形状卡死，取入参的「断路径宽域账族账名」（以 toll_re ==
    TOLL_RE 走同一条判路：挂账账族话本判路）。
    「超 N 波」= HEAD 现窗 - 统一基线（TOLL_BASE）窗：逢超 N 波即红——本行字样首现挂账笔 = 用对账表
    （by `git log -G '归后续 lane' -G <探针名>`最旧一笔）验每笔字样行账族账名的「最旧挂账时点」一致；
    挂账様行首现笔于 BASE 前 = 0 波守（w31-k6 实证 qa_calendar 与 qa_seachart 两支挂账帐首现笔都 ≥ TOLL_BASE——
    挖出回归时波数基于提出名。不挖回归时一笔皆正账。"""
    hits = []
    for i, e in enumerate(exempt, 1):
        if len(e) >= 3 and TOLL_RE.search(e[2]):
            # 断路径宽域账款「挂账账族」= E5 断路径入参按 EXEMPT 来源格（字样行首现笔 e[1]）筛选；
            # break_lanes 非空 = 只认该 lane 账族账名集合内的字样行（EXEMPT 后合入名 = 断路径零节先红色块）。
            if break_lanes and e[1] not in break_lanes:
                continue
            first = toll_first_commit(e[0])
            if not first:
                continue  # 字样在现网但 git 查不到首现 → 不判红（防误判）
            # 判超 N 波 = 由字样行首现挂账笔起算：波数差 = 自 <first commit 不含>..HEAD 之间含「(lane-w」落地笔数
            # 该波数与从 TOLL_BASE 起算的现网窗同算（TOLL_LANE_RE 同格）。
            out = _git(["log", "--format=%s", f"{first}..HEAD"])
            if out.returncode != 0:
                continue
            passed = sum(1 for s in out.stdout.splitlines() if TOLL_LANE_RE.search(s))
            if passed > TOLL_N:
                hits.append((i, e[0], f"{passed}"))
    return hits


def tracked_probes():
    """git 已跟踪的 tools/*_probe.gd（与 check_docs_index / check_sidecars 同口径：未跟踪的不染红共用树）。"""
    out = subprocess.run(["git", "ls-files", "tools/*_probe.gd"],
                         cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:  # find: git 不可用时整道跑不了，退 2 不归红绿
        print("check_probe_registry: git ls-files 失败：" + out.stderr.strip())
        sys.exit(2)
    return sorted(os.path.basename(p) for p in out.stdout.split())


def covered(reg_module):
    """gate_json 的 REGISTRY file 列 + SHOT_PROBES 第一列（探针基名集合）。"""
    reg = {os.path.basename(g.get("file", "")) for g in reg_module.REGISTRY if g.get("file")}
    shots = {os.path.basename(p) for p, _lane in reg_module.SHOT_PROBES}
    return reg | shots


def exempt_names(exempt=EXEMPT):
    return {e[0] for e in exempt}


def run_census(probes, cov, exempt):
    """普查正路：返回 (漏网列表, 问题列表)。probes / cov / exempt 都是基名集合——零节与正路走同一函数。"""
    missing = [p for p in probes if p not in cov and p not in exempt]
    return missing


def run_dual(cov, exempt):
    """双列判路（与「漏册」行格成对偶；w29-k3 留口 / 审计-wave29 C3.2b 实证为真缺）：同列 REGISTRY
    ∪ SHOT_PROBES 与 EXEMPT 的探针基名集合——登进注册表的先删豁免行，别把一行豁免挂成双列。"""
    return sorted(set(cov) & set(exempt))


def head_exempt():
    print("一、探针普查（git 已跟踪 tools/*_probe.gd；注册 = gate_json REGISTRY file 列 ∪ SHOT_PROBES 截图册；"
          "都不沾的须登 EXEMPT 豁免名单）")
    probes = tracked_probes()
    try:
        sys.path.insert(0, TOOLS)
        import gate_json as reg
    finally:
        sys.path.remove(TOOLS)
    cov = covered(reg)
    exempt = exempt_names()
    check(bool(probes), f"git 已跟踪探针 {len(probes)} 支（0 支 = git ls-files 口径漂了）")
    stale = sorted(exempt - set(probes))
    check(not stale, "豁免名单每行都指着在仓探针"
          + (f"（{len(exempt)} 行）" if not stale else f"——{stale} 已不在仓 / 名写错：探针删了先删名单行，改名跟名单"))
    reg_probe_entries = sorted(os.path.basename(g["file"]) for g in reg.REGISTRY
                               if g.get("file", "").endswith("_probe.gd"))
    check(len(reg_probe_entries) == len(set(reg_probe_entries)),
          f"REGISTRY 里 *_probe.gd 条目不重号（{len(reg_probe_entries)} 条）")
    missing = run_census(probes, cov, exempt)
    for p in missing:
        check(False, f"探针漏册：tools/{p}——不在 REGISTRY / SHOT_PROBES，也未登豁免；"
              "修法：登进 gate_json REGISTRY（tier 按 §五.1 定），确属留档 / 取证件的登记 EXEMPT 一行带理由")
    check(not missing, f"漏注册且漏豁免 {len(missing)} 支"
          + ("（全绿）" if not missing else "（行首逐支点名如上）"))
    ok_shots = sorted({os.path.basename(p) for p, _ in reg.SHOT_PROBES} & set(probes))
    check(len(ok_shots) >= 1, f"SHOT_PROBES 截图册认到 {len(ok_shots)} 支在册探针（0 支 = SHOT_PROBES 口径漂了）")
    dual = run_dual(cov, exempt)
    for p in dual:
        check(False, f"双列：tools/{p} 同列 REGISTRY + EXEMPT——"
              + f"{[e[0] for e in EXEMPT].index(p) + 1}")
    check(not dual, f"双列 {len(dual)} 支（REGISTRY ∪ SHOT_PROBES ∩ EXEMPT 为空集）")


def head_shape():
    print("二、豁免名单形状（每行三格：探针名 / lane·来源 / 理由；缺格判红——rules-table 型门禁的表自守，§五.3）")
    for i, e in enumerate(EXEMPT):
        check(len(e) == 3 and all(isinstance(x, str) and x.strip() for x in e),
              f"EXEMPT 第 {i + 1} 行三格齐（探针 {e[0] if e else '?'}）")
        if len(e) >= 2:
            check(bool(re.search(r"[0-9a-f]{7}|lane|wave", e[1])),
                  f"EXEMPT 第 {i + 1} 行来源格带 lane 名或 commit（{e[0]}）")
    names = [e[0] for e in EXEMPT]
    check(len(names) == len(set(names)), f"豁免名单不重名（{len(names)} 行）")
    check(names == sorted(names), "豁免名单按探针名字典序排（新行插对位置，别堆尾）")


def head_toll(exempt=EXEMPT):
    print(f"三、EXEMPT 挂账尾字样收尾闸（源 w31-k6 欠账复派：reason 栏含「{TOLL_WORD}」字样 = 挂账缓兵；"
          f"挂账基线窗 N={TOLL_N} 波（现窗 {wave_count()}），超即逐行判红——先判后收，收编照后续 lane 条款）")
    hits = run_toll(exempt)
    for i, name, detail in hits:
        check(False, f"EXEMPT 收尾闸：EXEMPT[{i}]——{name} 挂账基线窗 N={TOLL_N} 波已过未收编（实过 {detail} 波）")
    check(not hits, f"挂账超 N={TOLL_N} 波未收编 0 行"
          + ("（全绿）" if not hits else "（行首逐支点名如上）"))


def overlay_mutate(kind):
    """零节变异（内存量具，不落盘）：返回 (probes, cov, exempt) 三集合的变体。"""
    probes = set(tracked_probes())
    sys.path.insert(0, TOOLS)
    try:
        import gate_json as reg
        cov = covered(reg)
    finally:
        sys.path.remove(TOOLS)
    exempt = set(exempt_names())
    if kind == "E1":  # 拼错一个豁免名——对不上任何探针，须整闸红
        exempt = {n.replace(".gd", "X.gd") if n == "qa_fine_text_probe.gd" else n for n in exempt}
    elif kind == "E2":  # 删一格豁免——现网留档探针漏网，须整闸红（w35-k1 换靶 qa_contract_destinations：
        # 原靶 qa_calendar 收编入册，删它一格不再漏网；新靶真实在 EXEMPT、零断言纯取证留档，豁免删一格即真漏网）
        exempt.discard("qa_contract_destinations_probe.gd")
    elif kind == "E3":  # 覆盖名单缺一支（k11 原罪形：REGISTRY 里没有它）——须整闸红（w35-k1 换靶 qa_fold_dim：
        # 原靶 pirate_boat 改任 E4 双列注入靶，此格换绑在册探针 fold_dim——覆盖缺一支必在漏网行点数）
        cov.discard("qa_fold_dim_probe.gd")
    elif kind == "E4":  # 造双列：已在册探针（SHOT_PROBES 截图册）再买一格豁免——须被双列行格点出
        # （w35-k1 换靶 qa_pirate_boat：原靶 qa_calendar 收编后豁免行收删；换靶后格守纯机制——
        # 覆盖 + 豁免两侧同注入，与旧版在册真实语义同构）
        cov.add("qa_pirate_boat_probe.gd")
        exempt.add("qa_pirate_boat_probe.gd")
    return sorted(probes), cov, exempt


def head_selftest():
    print("零、判据自检（GATES §五.3：内存变体走同一条判路，不落盘）")
    # 对照格：现网名单须全绿
    probes, cov, exempt = overlay_mutate("C0")
    miss0 = run_census(probes, cov, exempt)
    check(not miss0, f"C0 现网名单普查全绿（漏网 {len(miss0)} 支）")
    dual0 = run_dual(cov, exempt)
    check(not dual0, f"C0 现网名单双列为空（双列 {len(dual0)} 支）")
    # 反向格：E1 / E2 / E3 各须红且点的是那一支；E4 须点出双列那一支（0 支 = 双列判路瞎了）
    expects = {"E1": "qa_fine_text_probe.gd", "E2": "qa_contract_destinations_probe.gd",
               "E3": "qa_fold_dim_probe.gd"}
    for kind, want in expects.items():
        probes, cov, exempt = overlay_mutate(kind)
        miss = run_census(probes, cov, exempt)
        check(want in miss, f"{kind} 反向格：{want} 漏网被点出（实点 {len(miss)} 支" +
              ("" if len(miss) > 3 else f"：{miss}") + "）——探不到 = 此闸已判不出这一形")
    _probes, cov, exempt = overlay_mutate("E4")
    dual = run_dual(cov, exempt)
    check("qa_pirate_boat_probe.gd" in dual, f"E4 反向格：双列 qa_pirate_boat_probe.gd 被点出（实点 {len(dual)} 支"
          + ("" if len(dual) > 3 else f"：{dual}") + "）——探不到 = 双列判路已判不出这一形")
    # E5（收尾闸零节先红格，w34-k1 新增；w35 两支挂账先后由 k1 / k2 收编，基线拨至 0 支 / 21 行 EXEMPT）：
    # 照 §五.3 第 3/4 条断路径规格——本闸挂账识别由 TOLL_RE（§五.3 第 3 条块形状卡死）守；本格不问挂账超期
    # 的红帐——只问「挂账字样行被 TOLL_RE 认出」= 断路径关的识别；变体上拆 = TOLL_RE 识别路径被断 or 字样
    # 行被改，本格即先红（认不出就红——§五.3 断路径零节先红）。real 现盘点 0 支 = 挂账收净；格仍守「字样行
    # 再现必先被认出」之路。对照（蓝）：字样以外 21 行零不误伤。
    c5_names = sorted(e[0] for e in EXEMPT if TOLL_RE.search(e[2]))
    want_c5 = []
    check(c5_names == want_c5,
          f"E5 收尾闸断路径帐认格：TOLL_RE 认现网 {len(EXEMPT)} 行 EXEMPT 中「归后续 lane」字样行实点 {len(c5_names)} 支（{c5_names}）——打断 TOLL_RE 识别路径（字样变体）即先红")
    e5_clean = [(e[0], e[1], e[2]) for e in EXEMPT if not TOLL_RE.search(e[2])]
    check(all(not TOLL_RE.search(e[2]) for e in e5_clean),
          f"E5 蓝对照：字样外行 {len(e5_clean)} 行零不误伤（实点 0 队样）")


# ── 案例数不写死（w53 待拍板 35，lane w53-13 定、lane w53-14 落）：注册表的 judge / green / red / expect 只写
#    「cases=N fails=0」——探针每加一格案数就变，写死的数一加格就过期（落定时 4 支必跑探针 24/18/4/27 实跑已是 26/39/6/29），
#    判绿本来只看退出码与 fails=0。行内写出 `cases=<数字>` 即红，点名条目与字段。
CASES_LITERAL_RE = re.compile(r"cases=\d")


def case_count_hits(registry):
    return [f"{g.get('id', '?')}.{k}" for g in registry for k, v in g.items()
            if isinstance(v, str) and CASES_LITERAL_RE.search(v)]


def head_case_counts():
    print("四、注册表文字不写死案例数")
    sys.path.insert(0, TOOLS)
    import gate_json
    # 零节样本（§五.3）：写死的数须被认出、cases=N 不误伤
    check(case_count_hits([{"id": "x", "green": "末行 `REST_DAYS cases=24 fails=0`"}]) == ["x.green"]
          and not case_count_hits([{"id": "y", "green": "末行 `REST_DAYS cases=N fails=0`", "red": "fails=M（M>0）"}]),
          "案例数格自检：「cases=24」被认出、「cases=N」不误伤")
    hits = case_count_hits(gate_json.REGISTRY)
    check(not hits, f"REGISTRY 文字里写死 cases=<数字> 0 处（{hits or '无'}）——改写 cases=N")


def main():
    head_selftest()
    head_exempt()
    head_shape()
    head_toll()
    head_case_counts()
    if fails:
        print(f"结果：{len(fails)} 项问题")
        for m in fails:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
