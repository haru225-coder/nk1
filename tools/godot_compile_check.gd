## Godot 引擎内编译门禁（2026-09-03 P0.5 引入）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_compile_check.gd
## 逐个 load() 下列 SCRIPTS（scripts/ 主干 + 视觉集成线新增）并检查 can_instantiate()；任一失败则 quit(1)。
## 为什么不用 --check-only：它不实例化 autoload，会把 GameManager/Fleet 等引用误报成
## 「Identifier not found」，而且它的退出码在有 SCRIPT ERROR 时仍为 0（4.6.3 实测）。
## 本脚本 extends SceneTree，Godot 会先挂好 project.godot 里的 autoload 再进 _initialize()。
extends SceneTree

const SCRIPTS := [
	"res://scripts/Cannonball.gd", "res://scripts/FloatingText.gd",
	"res://scripts/GameManager.gd", "res://scripts/GameState.gd", "res://scripts/Main.gd",
	"res://scripts/Minimap.gd", "res://scripts/PirateShip.gd", "res://scripts/PortZone.gd",
	"res://scripts/SeaChart.gd", "res://scripts/Ship.gd", "res://scripts/WorldMap.gd",
	# lane w25-j1：V0928-9 镜头让位纯算口径（WorldMap 让位常数的对账函数，钉它的断言在 story_check）
	"res://scripts/worldmap_cam_plaque.gd",
	"res://scripts/core/Calendar.gd", "res://scripts/core/Crew.gd", "res://scripts/core/Economy.gd",
	"res://scripts/core/Fleet.gd", "res://scripts/core/SaveLoad.gd", "res://scripts/core/Voyage.gd",
	# 视觉集成线（art/cloud-visual）新增：过场引擎、主题/立绘工具、巡检截帧
	"res://scripts/cutscene/CutscenePlayer.gd", "res://scripts/cutscene/ChapterCard.gd",
	"res://scripts/cutscene/PortBanner.gd", "res://scripts/cutscene/LivingBackdrop.gd",
	"res://scripts/cutscene/CutscenePreview.gd", "res://scripts/cutscene/cs_kit.gd",
	"res://scripts/cutscene/cs_ink_text.gd", "res://scripts/cutscene/cs_seal.gd",
	"res://scripts/cutscene/cs_fx.gd",
	# cinematics 线：过场接线的会话开关与标题演出
	"res://scripts/cutscene/Cinematics.gd", "res://scripts/cutscene/TitleStage.gd",
	# characters 线：人物系统的画与小件、人物志浮页
	"res://scripts/ui/CharacterArt.gd", "res://scripts/ui/CharacterCodex.gd",
	# chars 线（人物呈现竖切）：场景 scripts/chars/ + 巡检工具
	"res://scripts/chars/CharStage3D.gd", "res://scripts/chars/CharPortraitPanel.gd",
	"res://scripts/chars/CharRoster.gd", "res://scripts/chars/CharsDemo.gd",
	"res://scripts/chars/CharsShoreOverlay.gd", "res://tools/qa_chars_wire_screenshots.gd",
	"res://tools/qa_chars_screenshots.gd",
	# lane w26-k2：w20-a3 湮灭成品真身已回灌 scripts/chars/ 运行线；tools/ 双件收成 extends 薄包装（dev 入口），仍登记编译
	"res://tools/CharStage3D.gd", "res://tools/CharsDemo.gd",
	# 工席成功态过渡（淡入墨幕 + 题签）
	"res://scripts/ui/UiTransition.gd", "res://tools/qa_title_probe.gd", "res://tools/qa_siege_endgame_probe.gd", "res://tools/qa_ending_reread_probe.gd",
	"res://tools/qa_siege_destinations_probe.gd",  # lane w36-k2 V0928-1 被围委办复现探针
	"res://tools/qa_save_stale_count1_probe.gd",  # lane w38-k1 旧卷勾稽「恰 1 枚已删港名目」count==1 临界断言探针
	"res://tools/qa_w53_5_half_write_probe.gd",  # lane w53-5 半写档探针——只写 .tmp 注入，记录 / 迁移回写须读回核对后才落位
	"res://tools/qa_w53_5_load_log_probe.gd",  # lane w53-5 读档后船籍簿记事栏探针——读早一卷不留后事、勾稽一声照记、坏卷不清
	"res://tools/qa_w53_5_roundtrip_probe.gd",  # lane w53-5 存档「全字段往返」探针——to_dict→save→脏场→load→逐键对账
	"res://tools/qa_w53_5_save_sheet_probe.gd",  # lane w53-5 航海日志册页探针——标题页续卷「记录」不给按、「翻阅」按 can_load、记录写不进不报已记入、键盘焦点不漏出册页
	"res://tools/qa_drydock_probe.gd",
	"res://tools/qa_voyage_status_probe.gd",
	"res://tools/qa_market_panel_probe.gd",
	"res://tools/qa_port_doors_probe.gd",
	"res://tools/qa_crew_hire_probe.gd",
	# Lane Z3 伙伴草案预览浮页
	"res://scripts/companions/CompanionPreview.gd", "res://tools/qa_companion_preview_screenshots.gd",
	"res://tools/qa_companion_preview_probe.gd",  # lane w64-k1 浮页上屏文案 / 钮面 / 字段运行时探针（headless）
	"res://tools/art/load_en_batch.gd",  # lane portrait-wiring：英文批次 29 立绘 + 3 背景 headless load() 自证探针
	# Lane A 观感展示台（独立场景）
	"res://scripts/ui/VisionStage.gd", "res://tools/qa_wire_vision_screenshots.gd",
	"res://scripts/ui/CombatLetterbox.gd", "res://tools/qa_letterbox_copy_probe.gd",
	# Lane G/Q 酒馆设施纸笺与新闻墙
	"res://scripts/ui/TavernFacilitySlip.gd", "res://scripts/ui/TavernFacilityPreview.gd",
	"res://scripts/ui/TavernNewsWall.gd", "res://tools/qa_tavern_news_wall_screenshots.gd",
	# Lane ms Main.gd 首刀拆出的工席纸条小件
	"res://scripts/ui/SlipKit.gd",
	# Lane mz Main.gd 第二刀拆出的船籍簿整页
	"res://scripts/ui/LedgerPage.gd",
	# Lane ms2 Main.gd 第三刀拆出的升章 / 了结册页
	"res://scripts/ui/ChapterSheet.gd",
	# Lane main4 Main.gd 第四刀拆出的酒馆 / 旅店页
	"res://scripts/ui/TavernPage.gd",
	# Lane main5 Main.gd 第五刀拆出的见面页
	"res://scripts/ui/NpcPage.gd",
	# Lane main6 Main.gd 第六刀拆出的航海日志册页
	"res://scripts/ui/SaveSheet.gd",
	# Lane main7 Main.gd 第七刀拆出的行会 / 贡院页
	"res://scripts/ui/GuildExamPage.gd",
	# Lane main8 Main.gd 第八刀拆出的市舶司页
	"res://scripts/ui/MaritimeOfficePage.gd",
	# Lane main9 Main.gd 第九刀拆出的住处 / 寺观页
	"res://scripts/ui/ResidencePage.gd",
	# Lane main10 Main.gd 第十刀拆出的船屋页
	"res://scripts/ui/ShipyardPage.gd",
	# Lane main11 Main.gd 第十一刀拆出的标题页 / 开场
	"res://scripts/ui/TitlePage.gd",
	# Lane main12 Main.gd 第十二刀拆出的调试钩子（F11 跳港 / F12 预览了结）
	"res://scripts/ui/DebugHooks.gd",
	# Lane w21-d20 Main.gd 第十四刀拆出的浮页（人物志 / 名册 / 伙伴草案预览 / 市舶纪事）
	"res://scripts/ui/FloatPages.gd",
	# lane combat08 海战号令面板 / 状态条
	"res://scripts/ui/CombatOrdersPanel.gd", "res://scripts/ui/CombatStatusHud.gd",
	# lane combat07 敌将 AI（PirateShip 每帧喂局势取舵令）
	"res://scripts/combat/EnemyCaptainAI.gd",
	# lane-c 接舷/海战 VFX
	"res://scripts/combat/CombatFx.gd",
	"res://scripts/combat/ShipSeakeeping.gd",
	"res://scripts/combat/ShipLook.gd",  # lane combat12-E 海船观感（投影白浪 / 受光 / 微摇，Ship / PirateShip 场景挂）
	"res://scripts/combat/BoardingStage.gd", "res://scripts/combat/CombatShoreHook.gd",
	"res://scripts/combat/MeleeResolve.gd",  # lane combat05 接舷白刃结算（BoardingStage.play 演它）
	"res://scripts/combat/CombatMorale.gd",  # lane combat06 海战士气（崩坏 / 溃逃 / 降幡 / 拒接舷）
	"res://scripts/combat/CombatSwitches.gd",  # lane w53-ctl 海战新玩法总开关（战斗方案一、二期 DEFAULTS 键位表；内存，不进存档）
	"res://scripts/combat/SeaState.gd", "res://scripts/combat/ManeuverModel.gd",  # lane combat02 风流舷向与机动（海况 / 机动模型，WorldMap 接线）
	"res://scripts/combat/SeaAtmosphere.gd", "res://scripts/combat/SeaWake.gd", "res://scripts/combat/SeaPennant.gd",  # lane atmos 海面/航迹/旗旒
	"res://scripts/combat/DamageModel.gd", "res://scripts/combat/FloodFire.gd",  # lane combat04 分系统损伤、浸水失火（Ship.gd 挂用）
	"res://scripts/combat/EnemyFloodFire.gd",  # lane w53-p3a 敌船进水失火（PirateShip 挂用，开关 enemy_flood_fire）
	"res://scripts/combat/AfterAction.gd",  # lane w53-p4-after 战后取舍纯账（SeaChart 挂用，开关 waa_*）
	# lane combat03 舷战弹道 / 分位装填与弹药
	"res://scripts/combat/Ballistics.gd", "res://scripts/combat/ReloadAmmo.gd",
	"res://tools/art/ThemePreview.gd", "res://tools/art/build_theme.gd",
	"res://tools/art/portrait_svg/PortraitWall.gd", "res://tools/art/ShotTour.gd",
	# lane ea4 清单漂移补列：此前各 lane 各自追加、漏掉的已跟踪脚本（由下方 INVENTORY 自检兜底）
	"res://scripts/audio/AudioHooks.gd", "res://scripts/audio/SfxSynth.gd",
	"res://scripts/chart/ChartProjection.gd", "res://scripts/chart/MapView.gd", "res://scripts/chart/ShipMarker.gd",
	"res://scripts/core/BrokerSlip.gd", "res://scripts/core/DrydockBerth.gd", "res://scripts/core/HeadingDraft.gd", "res://scripts/core/LogFold.gd", "res://scripts/core/PortBeats.gd",
	"res://scripts/core/ShoreDraft.gd", "res://scripts/core/UiTheme.gd",
	# 门禁本体与共用件
	"res://tools/godot_smoke.gd", "res://tools/godot_story_check.gd", "res://tools/p7_guild_exam_smoke.gd",
	"res://tools/patrol_shell.gd", "res://tools/shot_gate.gd", "res://tools/gate_report.gd",
	"res://tools/src_probe.gd",  # 按名认函数的源码探查（lane cs15）
	"res://tools/script_err_tally.gd",  # 必跑 gate 的 SCRIPT ERROR 判红 Logger（lane w53-11）
	"res://tools/gen_builtin_list.gd",
	# 各 lane 专项探针 / 截图脚本
	"res://tools/save_robust_probe.gd", "res://tools/save_migrate_probe.gd",
	"res://tools/save_stale_refs_probe.gd",  # lane w25-j3 旧卷引用已删名目探针
	"res://tools/qa_economy_spread_probe.gd", "res://tools/qa_save_slot_tip_probe.gd",
	"res://tools/qa_discovery_probe.gd", "res://tools/qa_chapter_promote_probe.gd",
	"res://tools/qa_chart_hud_screenshots.gd", "res://tools/qa_p7_screenshots.gd",
	"res://tools/qa_patrol_pack_screenshots.gd",
	"res://tools/qa_fine_text_probe.gd",
	"res://tools/qa_money_notices_probe.gd",
	"res://tools/qa_contract_stock_probe.gd",
	"res://tools/qa_contract_destinations_probe.gd",  # 委办目的地 × 战况取证件（lane w23-a8）
	"res://tools/qa_customs_duty_probe.gd",
	"res://tools/qa_bribe_probe.gd",  # lane w23-a5 塞钱探针骨架（EA6-1 机械前置，断言先注掉只打印实测）
	"res://tools/qa_iz_skip_notice_probe.gd", "res://tools/qa_shore_wait_notice_probe.gd",  # lane w23-a7 欠债跳年 / 候一日两探针（a8 代登记——未登记会卡 inventory 门禁）
	"res://tools/qa_rest_days_probe.gd",  # lane w24-b2 旅店 / 住处歇息钮面 ←→ 实扣真断言契约（a7 遗留②一日差归因核验 + 钉边界）
	"res://tools/qa_rest_scenarios_probe.gd",  # lane w28-k1 旅店 / 住处「歇・候 N 日」钮面两贴文场景同亮 + 寺观该暗反驾断言（w26-k9 交主控 4）
	"res://tools/qa_calendar_probe.gd",  # lane w26-k9 起步日「三月初一」真推进 / 改元岁名日历探针
	"res://tools/qa_economy_panel_probe.gd",  # lane w27-k2 名声栏级别名 / 欠债跳年册页·札记折叠月息原文上屏断言（w26-k9 交主控 2/3 合一）
	"res://tools/qa_w53_3_economy_probe.gd",  # lane w53-3 牙行逐件抬价/赊贷/委办三本账守形探针
	"res://tools/qa_w53_3_hold_split_probe.gd",  # lane w53-3 分船货舱水粮摊派不越全队载重（满一艘再补水粮再装另一艘）
	"res://tools/qa_w53_3_buy_max_probe.gd",  # lane w53-3 牙行买满一趟算件数（改前逐件往下减，件数平方级卡顿）
	"res://tools/qa_w53_3_market_rerender_probe.gd",  # lane w53-3 牙行页整页重排不卡（字控件空着进树再填字，改前一按 0.8 秒）
	"res://tools/qa_w53_3_rumor_probe.gd",  # lane w53-3 海上记下的传闻写在别港同一货的牙行卡上（改前只写在被传那港自己的卡上）
	"res://tools/qa_w53_3_fleet_sell_probe.gd",  # lane w53-3 多船牙行卖出不分船（改前货在二号船、旗舰选着时柜上不见、卖钮全灰）
	"res://tools/qa_w53_3_contract_keep_probe.gd",  # lane w53-3 在身委办的货不上秤（改前交货地按全卖连委办货一起卖掉、交货钮发灰）
	"res://tools/qa_w53_7_tavern_crew_probe.gd",  # lane w53-7 酒馆与人物专项（欠饷随名册清空归零 …）
	"res://tools/qa_fold_notice_probe.gd",  # lane w28-k2 札记折叠内非月息通告（【欠饷】按月 / 欠满三月 + 改元月历一瞥）原文断言（w27-k2 交主控①补新见）
	"res://tools/qa_w53_9_cutscene_probe.gd",  # lane w53-9 过场连点与拍节奏合一拍
	"res://tools/qa_yard_transition_probe.gd",
	"res://tools/qa_w53_8_codex_cols_probe.gd",  # lane w53-8 人物志名册格列数随页宽探针（超宽画布钉死九列）
	"res://tools/qa_w53_8_font_floor_probe.gd",  # lane w53-8 字阶下限探针（各页上屏字 ≥ SIZE_FOOT，「── X ──」分节小题泥金 16）
	"res://tools/qa_w53_8_letterbox_fit_probe.gd",  # lane w53-8 海战墨边题签长副题不冲出画布右缘探针
	"res://tools/qa_w53_8_panel_seam_probe.gd",  # lane w53-8 页面面板九宫纵向接缝探针（4:3 / 竖屏面板中腰冒泥金碎钩）
	"res://tools/qa_w53_8_tooltip_wrap_probe.gd",  # lane w53-8 悬停提示超宽折行探针（顶匾记事全文提示不再宽过画布被裁）
	"res://tools/qa_w53_8_vision_layout_probe.gd",  # lane w53-8 市舶纪事 VisionStage 画布钉死 1280 实锤探针（↑INVENTORY_EXEMPT——未登记会卡 inventory 门禁）
	"res://tools/qa_pirate_boat_probe.gd",  # 海寇快船 + 船图契约（lane pirate-boat-0928）
	"res://tools/qa_w53_2_combat_probe.gd",  # lane w53-2 海战接舷 / 号令 / 收战账目专项探针
	"res://tools/qa_w53_4_story_probe.gd",  # lane w53-4 剧情 advance_text 宣港对账专项探针
	"res://tools/qa_w53_4_chapter_hint_probe.gd",  # lane w53-4 章节 hint 上屏专项探针
	"res://tools/qa_w53_4_epilogue_fit_probe.gd",  # lane w53-4 终局航海札记边记攒多不把动作行挤出画外（帧后量布局）
	"res://tools/qa_w53_6_beat_replay_probe.gd",  # lane w53-6 港口节拍不重演（新局卷首到首抵泉州 / 老档补账）回归探针
	"res://tools/qa_w53_6_port_exits_probe.gd",  # lane w53-6 港内设施页各有「离开」（玉湖陈宅补回）回归探针
	"res://tools/qa_w53_6_guild_spreads_probe.gd",  # lane w53-6 行会抄本 / 打听不荐牙行闭门（围城 / 封港）的港回归探针
	"res://tools/qa_w53_6_shore_hint_probe.gd",  # lane w53-6 岸带行首注与门数对得上（终局特殊卡追加时不再「三处」配四扇门）回归探针
	"res://tools/qa_w53_6_yard_chips_probe.gd",  # lane w53-6 船屋 / 寺观工席小钮按下去账真动（钮面 ↔ 实账对账）探针
	"res://tools/qa_w53_6_shore_hand_probe.gd",  # lane w53-6 港页今日三门发牌端到端（候一日换门 / 缺人缺粮钉船屋 / 离开回港不换）探针
	"res://tools/qa_w53_9_cutscene_input_probe.gd",  # lane w53-9 过场层输入时序探针（以场景启动，见 SCENES）
	"res://tools/qa_w53_9_chapter_year_probe.gd",  # lane w53-9 章节卡年号与历法逐月同口径探针
	"res://tools/qa_w53_13_decide_probe.gd",  # lane w53-13 待拍板逐条定下后的修复回归探针（跳年封顶等）
	"res://tools/qa_w53_16_aftermath_probe.gd",  # lane w53-16 战斗方案一、二期战后单子与赏钱专项探针
	"res://tools/qa_w53_16_aftermath_shots.gd",  # lane w53-16 战后单子 on / off 对比截图（NK1_SHOT_DIR 指路）
	"res://tools/qa_w53_17_morale_probe.gd",  # lane w53-17 士气与风专项探针（大风两散 / 士气带回 / 火长报风 / 通事劝降）
	"res://tools/qa_w53_9_chapter_card_probe.gd",  # lane w53-9 章节卡题记留读与一句一列探针（须带窗口）
	"res://tools/qa_w53_9_port_banner_probe.gd",  # lane w53-9 抵港横幅各窗口比例都挂在港名匾下探针（以场景启动，见 SCENES）
	"res://tools/qa_w53_p3b_firerot_probe.gd",  # lane w53-p3b 火攻回到装填轮换专项探针（fire_attack_load 开关两态、引火乘数上乘）
	# lane w53-15 战斗方案一、二期探针（敌情列 / 劝降挂敌船 / 砍钩 / 张湿毡 / 总管夷人）
	"res://tools/qa_w53_15_intel_probe.gd", "res://tools/qa_w53_15_parley_probe.gd", "res://tools/qa_w53_15_cut_probe.gd",
	"res://tools/qa_w53_15_wet_probe.gd", "res://tools/qa_w53_15_role_probe.gd", "res://tools/qa_w53_15_shipcard_probe.gd",
	"res://tools/combat_vfx_probe.gd", "res://tools/ship_vfx_probe.gd", "res://tools/atmos_water_probe.gd", "res://tools/combat_wire_probe.gd", "res://tools/combat_probe_stage.gd",
	"res://scripts/combat/ShipHull3D.gd", "res://tools/ship_exquisite_probe.gd",
	"res://tools/ship_dashi_probe.gd",  # 大食缝合船朝向探针（lane ship-dashi）
	"res://tools/japan_ship_probe.gd",  # 日本关船朝向探针（lane ship-japan）
	"res://tools/shot_champa_ship.gd",  # 占城船朝向探针（lane ship-champa）
	"res://tools/combat_realism_probe.gd", "res://scripts/combat/CombatDirector.gd",  # lane combat10 写实海战冒烟探针 + 装配台
	"res://tools/combat_outcomes_probe.gd",  # lane w23-a10 战果契约（OUTCOMES / STORY_KEYS 读点）独立探针
	"res://tools/vision_stage_probe.gd", "res://tools/vision_letterbox_probe.gd", "res://tools/letterbox_signal_probe.gd",
	"res://tools/probe_clock.gd", "res://tools/shot_consistency.gd",
	"res://tools/art/vision_fill_gen.gd", "res://tools/art/vision_fill_shots.gd",
	"res://tools/art/tour_sheet.gd",
	"res://tools/perf_baseline.gd",  # lane w20-c10 帧时 / 峰值内存 / 启动到可玩基线探针
	"res://tools/qa_port_beats_probe.gd",  # lane w26-k7 PortBeats.due 终局守卫下沉契约探针
	"res://tools/qa_ledger_strip_probe.gd",  # lane w27-k1 HUD 顶匾「钱 N / 水粮 D 日」随账上屏断言探针
	"res://tools/qa_debt_strip_probe.gd",  # lane w30-k2 HUD 顶匾上行「欠 %d」逐字断言探针（gs.debt = 835/100/10000 三档 + debt=0 反向）
	"res://tools/qa_seachart_advance_probe.gd",  # lane w28-k3 SeaChart 海图「航段」名号跨月推进时序断言探针
	"res://tools/qa_w53_1_plan_sail_days_probe.gd",  # lane w53-1 航段推演日数 ↔ 实航逐日走法对账探针
	"res://tools/qa_w53_1_chart_follow_ship_probe.gd",  # lane w53-1 远程航行镜头跟船探针
	"res://tools/qa_w53_1_dest_hint_probe.gd",  # lane w53-1 目的地出带箭头避让港标探针
	"res://tools/qa_w53_11_run_watch_probe.gd",  # lane w53-11 截图门禁共用件 shot_gate「_run 断气」看门自证探针
	"res://tools/qa_w53_1_battle_sea_name_probe.gd",  # lane w53-1 海上遇敌海域名按船当日所在取港探针
	"res://tools/qa_w53_1_trail_marker_probe.gd",  # lane w53-1 航线描深末端对船标探针
	"res://tools/qa_w53_1_region_label_probe.gd",  # lane w53-1 地区名避让港名探针
	"res://tools/qa_w53_1_compass_needle_probe.gd",  # lane w53-1 罗盘针名对去向牌探针
	"res://tools/qa_w53_1_hud_overlap_probe.gd",  # lane w53-1 港名地名箭头不压 HUD 探针
	"res://tools/qa_w53_1_port_name_click_probe.gd",  # lane w53-1 点港名选港探针
	"res://tools/qa_crew_fold_host.gd",  # lane w30-k3 qa_crew_fold_probe 仿作宿主（LogFold.render 直收字段件）
	"res://tools/qa_crew_fold_probe.gd",  # lane w30-k3 多雇员【欠饷】字面一览（工食合计 / 俸最高者先走）+ LogFold.render fold:i 展开字样断言探针
	"res://tools/qa_cargo_strip_probe.gd",  # lane w29-k2 船籍簿船舱段 cargo_str（品名 × 数量 / 容量 / 空舱）上屏断言探针
	"res://tools/qa_fold_dim_probe.gd",  # lane w32-k2 LogFold.render 港页记事栏 dim_rest=true 分支褪色字样断言探针（折行 / 月行裹色 + 换档相变）
	"res://tools/qa_w53_2_combat_overkill_probe.gd",  # lane w53-2 敌船击沉过量杀伤折进甲板伤亡断言探针（take_damage 击沉时超出的份不再蒸发）
	"res://tools/qa_w53_p3c_ammo_low_probe.gd",  # lane w53-p3c 敌将弹药告急回归专项探针（三期开关两态）
	"res://tools/qa_w53_p3c_intel_ff_probe.gd",  # lane w53-p3c 敌情列水火短注专项探针（鸭子型+布景+排版）
	"res://tools/qa_w53_p3c_intel_ff_shot.gd",  # lane w53-p3c 敌情列水火短注 1280×720 截图（NK1_SHOT_DIR 指路）
	"res://tools/qa_w53_p3c_winrate_probe.gd",  # lane w53-p3c 三期开关胜率工具（合并 p3b/p3c：--on/--off/--compare 两段对阵，同种子复跑自检）
	"res://tools/qa_w53_p4_after_choices_probe.gd",  # lane w53-p4-after 战后取舍专项探针（押船/救人/俘虏/索赎/追击，开关 waa_* 各节回退即红）
	"res://tools/qa_w53_p4_after_shots.gd",  # lane w53-p4-after 战后收拾小卡 1280×720 截图（NK1_SHOT_DIR 指路）
	"res://tools/qa_w53_p4_melee_probe.gd",  # lane w53-p4-melee 白刃三决断 + 追窗口专项探针（压上 / 收势账、超时默认、开关关逐字回旧、追窗 leave / 挫速）
	"res://tools/qa_w53_p4_melee_decision_shot.gd",  # lane w53-p4-melee 白刃决断拍板拍 1280×720 截图（NK1_SHOT_DIR 指路）
]

## 清单自检（lane ea4）：INVENTORY_ROOTS 下每个 git 已跟踪的 .gd 都必须在 SCRIPTS 里，或在 INVENTORY_EXEMPT 里写明理由；
## SCRIPTS 里的路径必须真实存在。任一差集非空 → bad+1（整体算一项 inventory）。
## 「已跟踪」取 `git ls-files`：别的 lane 未提交的新脚本不会让共用工作树变红；git 不可用时退回扫盘并打 NOTE。
const INVENTORY_ROOTS := ["scripts", "tools"]
const INVENTORY_SKIP_DIRS := ["tools/legacy"]
const INVENTORY_EXEMPT := {
	"tools/tactical_coast_screens.gd": "lane w20-b1 人工验图 driver（before/after 截图，不入门禁；不接 ShotGate / 不在 SCRIPTS 体检）",
	"tools/godot_compile_check.gd": "门禁本体：它自己编不过就根本跑不到这里，列入无增益",
}

## 关键场景：脚本门禁通过后仍可能因 ext_resource 解析失败而坏档（ASTRA_AUDIT M2）。
## 4.6.3 实测：ext_resource 指向不存在的文件时 load() 仍返回 PackedScene、instantiate() 也成功，
## 只往 stderr 打一行 Parse Error——所以这里逐条核对 [ext_resource]，把解析错误算进 bad。
## 显式清单：主干 + 一切战斗/弹道场景；scenes/ 下未列入的（scenes/vision/ 除外，另有 lane 维护）也会被补查。
const SCENES := [
	"res://scenes/Main.tscn",
	"res://scenes/WorldMap.tscn",
	"res://scenes/SeaChart.tscn",
	"res://scenes/PortZone.tscn",
	"res://scenes/FloatingText.tscn",
	# 战斗 / 弹道
	"res://scenes/Ship.tscn",
	"res://scenes/PirateShip.tscn",
	"res://scenes/Cannonball.tscn",
	"res://scenes/WaterSplash.tscn",
	"res://scenes/ImpactExplosion.tscn",
	"res://scenes/combat/BoardingStage.tscn",
	# 人物 / 过场 / 酒馆
	"res://scenes/chars/CharsDemo.tscn",
	"res://scenes/chars/CharsShoreOverlay.tscn",
	"res://scenes/cutscene/CutscenePreview.tscn",
	"res://scenes/ui/TavernFacilityPreview.tscn",
	"res://scenes/ui/TavernFacilitySlip.tscn",
	# 探针场景（-s 放不出过场的探针以场景启动）
	"res://tools/qa_yard_transition_probe.tscn",
	"res://tools/qa_w53_9_cutscene_input_probe.tscn",
	"res://tools/qa_w53_9_port_banner_probe.tscn",
]

## lane-z4 把 Ship/PirateShip 的炮弹场景改成 lazy load() 后，这几个弹道场景已确认无解析错误；
## 它们必须留在 SCENES 里且保持 OK，被删出清单也算一次失败。
const MUST_STAY_CLEAN := [
	"res://scenes/Cannonball.tscn",
	"res://scenes/WaterSplash.tscn",
	"res://scenes/ImpactExplosion.tscn",
]

const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
const SCENE_ROOT := "res://scenes"
const SCENE_SKIP_DIRS := ["res://scenes/vision"]


func _initialize() -> void:
	print("COMPILE_CHECK autoload GameManager present: ", root.get_node_or_null("GameManager") != null)
	var bad := 0
	var total := 0
	for p in SCRIPTS:
		total += 1
		var s = load(p)
		if s == null:
			print("COMPILE_CHECK FAIL load-null ", p)
			GateReport.check(false, p, "load-null")
			bad += 1
			continue
		var ok: bool = s.can_instantiate()
		print("COMPILE_CHECK ", "OK   " if ok else "FAIL ", p)
		GateReport.check(ok, p, "" if ok else "can_instantiate=false")
		if not ok:
			bad += 1
	total += 1
	var inv_why := _check_inventory()
	if inv_why.is_empty():
		print("COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under ", "/".join(INVENTORY_ROOTS), " (exempt ", INVENTORY_EXEMPT.size(), ")")
		GateReport.check(true, "inventory SCRIPTS == tracked *.gd under %s (exempt %d)" % ["/".join(INVENTORY_ROOTS), INVENTORY_EXEMPT.size()])
	else:
		bad += 1
		for w in inv_why:
			print("COMPILE_CHECK FAIL inventory ", w)
			GateReport.check(false, "inventory " + w)
	for gp in MUST_STAY_CLEAN:
		if not SCENES.has(gp):
			total += 1
			bad += 1
			print("COMPILE_CHECK FAIL guard-unlisted ", gp)
			GateReport.check(false, gp, "guard-unlisted")
	var scenes: Array = SCENES.duplicate()
	for extra in _discover_scenes(SCENE_ROOT):
		if not scenes.has(extra):
			print("COMPILE_CHECK NOTE unlisted scene, checking anyway ", extra)
			GateReport.warn(extra, "unlisted scene, checking anyway")
			scenes.append(extra)
	for sp in scenes:
		total += 1
		var why := _check_scene(sp)
		if why.is_empty():
			print("COMPILE_CHECK OK   ", sp)
			GateReport.check(true, sp)
		else:
			bad += 1
			var tag := "FAIL guard " if MUST_STAY_CLEAN.has(sp) else "FAIL "
			print("COMPILE_CHECK ", tag, sp, " :: ", "; ".join(why))
			GateReport.check(false, sp, ("guard：" if MUST_STAY_CLEAN.has(sp) else "") + "; ".join(why))
	print("COMPILE_CHECK SUMMARY bad=", bad, "/", total)
	GateReport.finish("godot_compile_check", 1 if bad > 0 else 0, "COMPILE_CHECK SUMMARY bad=%d/%d" % [bad, total])
	quit(1 if bad > 0 else 0)


## 返回失败原因列表；空 = 场景可解析、依赖齐全、可实例化。一个场景只计一次失败。
func _check_scene(sp: String) -> PackedStringArray:
	var why := PackedStringArray()
	if not FileAccess.file_exists(sp):
		why.append("scene-missing")
		return why
	var text := FileAccess.get_file_as_string(sp)
	if text.is_empty():
		why.append("scene-empty")
		return why
	# 先核 [ext_resource]：path 必须存在且能 load；脚本还须能实例化。在 load(场景) 之前做，免得坏依赖被静默吞掉。
	var attr_re := RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
	var ids := {}
	for line in text.replace("\r", "").split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var attrs := {}
		for a in attr_re.search_all(line):
			attrs[a.get_string(1)] = a.get_string(2)
		var dep: String = attrs.get("path", "")
		var id: String = attrs.get("id", "")
		if id != "":
			ids[id] = true
		if dep == "":
			var uid: String = attrs.get("uid", "")
			var uid_id := ResourceUID.text_to_id(uid) if uid != "" else ResourceUID.INVALID_ID
			if uid_id == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid_id):
				why.append("ext-unresolved id=%s" % id)
				continue
			dep = ResourceUID.get_id_path(uid_id)
		if not ResourceLoader.exists(dep):
			why.append("ext-missing %s" % dep)
			continue
		var r = load(dep)
		if r == null:
			why.append("ext-load-null %s" % dep)
		elif r is Script and not r.can_instantiate():
			why.append("ext-script-broken %s" % dep)
	# 正文里 ExtResource("x") 引用了未声明的 id，同样是 Parse Error。
	var ref_re := RegEx.create_from_string("ExtResource\\(\\s*\"([^\"]+)\"\\s*\\)")
	for m in ref_re.search_all(text):
		if not ids.has(m.get_string(1)):
			why.append("ext-undeclared id=%s" % m.get_string(1))
	if not why.is_empty():
		return why
	var packed = load(sp)
	if packed == null or not (packed is PackedScene):
		why.append("scene-load")
		return why
	if not packed.can_instantiate():
		why.append("scene-cant")
		return why
	var node = packed.instantiate()
	if node == null:
		why.append("scene-inst")
		return why
	node.free()
	return why


func _discover_scenes(dir_path: String) -> Array:
	var out: Array = []
	if SCENE_SKIP_DIRS.has(dir_path):
		return out
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_discover_scenes(dir_path.path_join(sub)))
	out.sort()
	return out


## 返回差集条目；空 = 清单与已跟踪脚本对齐。
func _check_inventory() -> PackedStringArray:
	var why := PackedStringArray()
	var listed := {}
	for p in SCRIPTS:
		var rel: String = p.trim_prefix("res://")
		if listed.has(rel):
			why.append("dup %s" % p)
		listed[rel] = true
		if not FileAccess.file_exists(p):
			why.append("listed-missing %s" % p)
	var tracked := _tracked_gd()
	for rel in tracked:
		if listed.has(rel):
			if INVENTORY_EXEMPT.has(rel):
				why.append("exempt-but-listed res://%s" % rel)
		elif not INVENTORY_EXEMPT.has(rel):
			why.append("unlisted res://%s" % rel)
	for rel in INVENTORY_EXEMPT:
		if not tracked.has(rel):
			why.append("exempt-stale res://%s" % rel)
	return why


func _tracked_gd() -> Array:
	var out: Array = []
	var root_abs := ProjectSettings.globalize_path("res://")
	# 不用 -z：OS.execute 把输出转成 String 时会在 NUL 处截断；改关 quotepath 按行切。
	var args := PackedStringArray(["-C", root_abs, "-c", "core.quotepath=off", "ls-files", "--"])
	for r in INVENTORY_ROOTS:
		args.append("%s/*.gd" % r)
	var stdout: Array = []
	var rc := OS.execute("git", args, stdout, true)
	if rc == 0 and not stdout.is_empty():
		for rel in String(stdout[0]).split("\n", false):
			if not _inventory_skipped(rel):
				out.append(rel)
	else:
		print("COMPILE_CHECK NOTE inventory git ls-files unavailable (rc=", rc, "), falling back to disk scan")
		GateReport.warn("inventory git ls-files unavailable (rc=%d), falling back to disk scan" % rc)
		for r in INVENTORY_ROOTS:
			out.append_array(_disk_gd(r))
	out.sort()
	return out


func _disk_gd(rel_dir: String) -> Array:
	var out: Array = []
	if _inventory_skipped(rel_dir + "/"):
		return out
	var d := DirAccess.open("res://" + rel_dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(rel_dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_disk_gd(rel_dir.path_join(sub)))
	return out


func _inventory_skipped(rel: String) -> bool:
	for sd in INVENTORY_SKIP_DIRS:
		if rel.begins_with(sd + "/"):
			return true
	return false
