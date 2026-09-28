## 引擎内剧情状态机门禁（2026-09-04 引入，随 news.json / 1268 身份结算落地）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_story_check.gd
## 只推进 GM.advance_days()，断言：新闻按月到期投放且不重复；1268-04 结算恰一次；
## 士人/海商两种倾向分别得到陈文龙/陈子龙；存档 round-trip 保留新字段。
## 首帧另实例化 Main 走真机抵港路由（2026-09-14）：与港口同名的 load_scene 必须记 visited_ports 并能晋升。任一失败 quit(1)。
extends SceneTree

const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
var _fails := 0
var _notices: Array = []
# autoload 在 SceneTree 脚本里不能当标识符用，运行时从 root 取
var GM: Node
var Cal: Node
var GS: Node


func _check(cond: bool, msg: String) -> void:
	print("STORY_CHECK ", "OK   " if cond else "FAIL ", msg)
	GateReport.check(cond, msg)
	if not cond:
		_fails += 1


func _advance_to(year: int, month: int) -> void:
	# 每次推进一天，直到历法 >= 目标年月的初一
	var guard := 0
	while (Cal.year < year or (Cal.year == year and Cal.month < month)) and guard < 20000:
		GM.advance_days(1)
		guard += 1


func _run_case(scholar: int, sea: int, first_flag: String, expect_name: String, expect_identity: String) -> void:
	# 重置到开局
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	GS.from_dict({})
	GS.scholar_tendency = scholar
	GS.sea_tendency = sea
	if first_flag != "":
		GS.set_flag(first_flag)
	_notices.clear()

	_advance_to(1256, 4)
	_check(GS.news_seen.has("n_1256_03_taixue"), "1256-03 太学新闻已投放（%s）" % expect_identity)
	_check(not GS.news_seen.has("n_1256_05_wentianxiang"), "1256-05 新闻未提前投放")
	_check(GS.identity == "undecided", "1256 年身份仍 undecided")

	var before := _notices.size()
	_advance_to(1268, 4)
	_check(GS.identity == expect_identity, "1268-04 身份 = %s（实际 %s）" % [expect_identity, GS.identity])
	_check(GS.player_name == expect_name, "1268-04 姓名 = %s（实际 %s）" % [expect_name, GS.player_name])
	var settle_count := 0
	for t in _notices.slice(before):
		if str(t).begins_with("【咸淳四年"):
			settle_count += 1
	_check(settle_count == 1, "殿试结算通知恰一次（实际 %d）" % settle_count)

	_advance_to(1268, 6)
	var again: Dictionary = GS.resolve_identity_1268()
	_check(not again.get("resolved", false), "重复结算被拒")

	# 新闻市场副作用：1273-03 蕃坊恐慌 → 泉州香药行情 ×0.6，之后按 RECOVERY 回归；别港不受波及
	var Eco0: Node = root.get_node("Economy")
	_advance_to(1273, 2)
	Eco0.initialize()
	if Eco0.rates.has("quanzhou") and Eco0.rates.has("xinghua"):
		Eco0.rates["quanzhou"]["aromatic_medicine"] = 1.0
		Eco0.rates["xinghua"]["aromatic_medicine"] = 1.0
		_advance_to(1273, 3)
		var qz: float = Eco0.get_rate("quanzhou", "aromatic_medicine")
		_check(GS.news_seen.has("n_1273_03_fanfang_panic") and qz > 0.55 and qz < 0.65, "1273-03 蕃坊恐慌：泉州香药行情砸到约六成（%.3f）" % qz)
		_check(is_equal_approx(Eco0.get_rate("xinghua", "aromatic_medicine"), 1.0), "恐慌只落在 market.ports 所列港口")
		_advance_to(1273, 6)
		qz = Eco0.get_rate("quanzhou", "aromatic_medicine")
		_check(qz > 0.95, "三个月后泉州香药行情回到 1.0 附近（%.3f）" % qz)
	else:
		_check(false, "Economy.rates 未初始化，无法验恐慌行情")

	# 新闻不重复：统计所有通知中每条 news 文本出现次数
	_advance_to(1277, 1)
	var seen_all: int = GS.news_seen.size()
	# 带 only 的短札只发给对应身份，故应投总数随身份而变
	var total_news := 0
	for item0 in GM.news_data.get("news", []):
		var only0 := str(item0.get("only", ""))
		if str(item0.get("date", "9999-99")) > "1277-01":
			continue
		if only0 == "" or only0 == GS.identity:
			total_news += 1
	_check(seen_all == total_news, "1277-01 本身份应投 %d 条新闻（实际 %d）" % [total_news, seen_all])
	var uniq := {}
	for nid in GS.news_seen:
		uniq[nid] = true
	_check(uniq.size() == seen_all, "news_seen 无重复")

	# 存档 round-trip
	var d: Dictionary = GS.to_dict()
	var snapshot_name: String = GS.player_name
	GS.from_dict({})
	_check(GS.player_name == "陈子龙" and GS.identity == "undecided", "from_dict({}) 回到开局默认")
	GS.from_dict(d)
	_check(GS.player_name == snapshot_name and GS.identity == expect_identity and GS.news_seen.size() == seen_all, "存档 round-trip 保留 player_name / identity / news_seen")


func _initialize() -> void:
	GM = root.get_node("GameManager")
	Cal = root.get_node("Calendar")
	GS = root.get_node("GameState")
	# SceneTree._initialize 先于 autoload._ready 执行，数据要在这里手动加载
	GM.load_data()
	GM.monthly_notice.connect(func(t: String): _notices.append(t))
	_check(not GM.news_data.is_empty(), "news.json 已加载")

	# 用例 1：士人倾向高 → 陈文龙
	_run_case(7, 3, "chose_land_first", "陈文龙", "scholar")
	# 用例 2：海商倾向高 → 陈子龙
	_run_case(3, 7, "chose_sea_first", "陈子龙", "merchant")
	# 用例 3：打平，按开局第一选择破平（陆路优先 → 士人）
	_run_case(4, 4, "chose_land_first", "陈文龙", "scholar")
	# 用例 4：打平且开局选海 → 海商
	_run_case(4, 4, "chose_sea_first", "陈子龙", "merchant")

	# S/M 文案切换
	GS.from_dict({})
	GS.identity = "scholar"
	var n: Dictionary = GM.get_news_by_id("n_1273_02_xiangyang_falls")
	_check(GS.news_text(n).find("六年") >= 0, "S 版文案取 text_S")
	GS.identity = "merchant"
	_check(GS.news_text(n).find("大食人") >= 0, "M 版文案取 text_M")

	# ── 战况状态机（Calendar 纯函数） ──
	var Eco: Node = root.get_node("Economy")
	var Voy: Node = root.get_node("Voyage")
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_check(Eco.war_status("quanzhou") == "loyal", "1255 泉州 loyal")
	_check(Eco.war_status("penghu") == "loyal", "无 war 表的港口恒 loyal")
	Cal.from_dict({"year": 1274, "month": 10, "day": 1})
	_check(Eco.war_status("hakata") == "closed" and not Eco.is_port_reachable("hakata"), "1274-10 博多封港不可达")
	Cal.from_dict({"year": 1275, "month": 5, "day": 1})
	_check(Eco.war_status("hakata") == "loyal", "1275-05 博多复通")
	Cal.from_dict({"year": 1276, "month": 5, "day": 1})
	_check(Eco.war_status("quanzhou") == "contested", "1276-05 泉州对峙")
	_check(Eco.war_status("fuzhou") == "loyal", "1276-05 福州仍宋土")
	Cal.from_dict({"year": 1276, "month": 11, "day": 1})
	_check(Eco.war_status("fuzhou") == "fallen" and Eco.war_status("xinghua") == "besieged", "1276-11 福州降、兴化围")
	_check(not Eco.is_market_open("xinghua"), "围城牙行闭门")
	Cal.from_dict({"year": 1276, "month": 12, "day": 1})
	_check(Eco.war_status("quanzhou") == "fallen", "1276-12 泉州降元")
	var p_loyal: int = Eco.price_at_rate("quanzhou", "grain", 1.0, true)
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	var p_before: int = Eco.price_at_rate("quanzhou", "grain", 1.0, true)
	_check(p_loyal > p_before, "降元后泉州买价含加倍抽解（%d > %d）" % [p_loyal, p_before])
	_check(Eco.inspection_factor("quanzhou") == 1.0, "1255 缉私倍率 1.0")
	Cal.from_dict({"year": 1277, "month": 2, "day": 1})
	_check(Eco.war_status("xinghua") == "loyal", "1277-02 陈瓒复兴化")
	Cal.from_dict({"year": 1277, "month": 5, "day": 1})
	_check(Eco.war_status("xinghua") == "loyal", "1277-05 兴化仍在宋方手里（史实：三月至十月）")
	Cal.from_dict({"year": 1277, "month": 9, "day": 1})
	_check(Eco.war_status("xinghua") == "besieged", "1277-09 唆都再围兴化")
	Cal.from_dict({"year": 1277, "month": 11, "day": 1})
	_check(Eco.war_status("xinghua") == "fallen", "1277-11 兴化再陷（十月城破，月初翻牌）")

	# 月初战况通告：推进跨过 1276-12 应有泉州降元通告，且 grain 行情被抬
	Cal.from_dict({"year": 1276, "month": 11, "day": 28})
	Eco.initialize()
	var r0: float = Eco.get_rate("quanzhou", "grain")
	_notices.clear()
	GM.advance_days(3)
	var got := false
	for t in _notices:
		if str(t).find("泉州已降元") >= 0:
			got = true
	_check(got, "跨入 1276-12 收到泉州降元通告")
	_check(Eco.get_rate("quanzhou", "grain") > r0, "降元冲击抬高泉州米价")

	# 战时遭遇：1255 年任何航段不出战时事件；1277 年降元港航段 200 次抽样应至少出现一次元哨/难民
	Cal.from_dict({"year": 1255, "month": 6, "day": 1})
	var bad := 0
	for i in range(200):
		var ev: Dictionary = Voy.roll_day_event(90.0, "quanzhou", "penghu")
		if ev.get("kind", 0) in [Voy.EventKind.REQUISITION, Voy.EventKind.YUAN_PATROL, Voy.EventKind.REFUGEE]:
			bad += 1
	_check(bad == 0, "1255 年无战时遭遇")
	Cal.from_dict({"year": 1277, "month": 1, "day": 1})
	var hits := 0
	for i in range(200):
		var ev: Dictionary = Voy.roll_day_event(90.0, "quanzhou", "fuzhou")
		if ev.get("kind", 0) in [Voy.EventKind.YUAN_PATROL, Voy.EventKind.REFUGEE]:
			hits += 1
	_check(hits > 0, "1277 年降元航段出现战时遭遇（200 次中 %d 次）" % hits)
	var far := 0
	for i in range(200):
		var ev: Dictionary = Voy.roll_day_event(90.0, "penghu", "ryukyu")
		if ev.get("kind", 0) in [Voy.EventKind.REQUISITION, Voy.EventKind.YUAN_PATROL, Voy.EventKind.REFUGEE]:
			far += 1
	_check(far == 0, "1277 年澎湖—流求外海无战时遭遇")

	# ── 蒲寿庚那句话点谁的名 ──
	GS.from_dict({})
	var pu: Dictionary = GM.get_news_by_id("n_1276_12_quanzhou_falls")
	_check(not pu.is_empty(), "泉州降元新闻存在")
	_check(GS.news_text(pu).find("兴化陈瓒非不忠义") >= 0, "无陈文龙的世界：点名陈瓒")
	GS.set_flag("renamed_wenlong")
	GS.player_name = "陈文龙"
	_check(GS.news_text(pu).find("陈文龙非不忠义") >= 0, "有陈文龙的世界：点名玩家")
	_check(GS.news_text(pu).find("{") < 0, "占位符全部替换")

	# ── 泉州对峙期个人封港与蒲家折扣 ──
	GS.from_dict({})
	Cal.from_dict({"year": 1276, "month": 6, "day": 1})
	GS.ban_port("quanzhou", "1276-11")
	_check(GS.is_port_banned("quanzhou") and not Eco.is_port_reachable("quanzhou"), "1276-06 连夜出港后泉州对己封港")
	Cal.from_dict({"year": 1276, "month": 12, "day": 1})
	_check(not GS.is_port_banned("quanzhou"), "1276-12 封港到期自动解除")
	_check(GS.port_bans.is_empty(), "到期后 port_bans 清理")
	Cal.from_dict({"year": 1277, "month": 1, "day": 1})
	var p_plain: int = Eco.price_at_rate("quanzhou", "grain", 1.0, true)
	GS.set_flag("sided_pu")
	var p_pu: int = Eco.price_at_rate("quanzhou", "grain", 1.0, true)
	_check(p_pu < p_plain, "站蒲家后泉州买价更低（%d < %d）" % [p_pu, p_plain])
	var p_other: int = Eco.price_at_rate("fuzhou", "grain", 1.0, true)
	GS.flags.erase("sided_pu")
	_check(Eco.price_at_rate("fuzhou", "grain", 1.0, true) == p_other, "蒲家折扣不外溢到福州")

	# ── 终局态 ──
	GS.from_dict({})
	Cal.from_dict({"year": 1277, "month": 3, "day": 1})
	_check(not GS.is_ended(), "开局非终局态")
	_check(GS.finish("岸上的根"), "finish() 首次落定")
	_check(GS.is_ended() and GS.ended == "岸上的根", "终局名已记")
	_check(GS.ended_at.find("兴化") >= 0 or GS.ended_at.find("泉州") >= 0, "终局记下日期与地点（%s）" % GS.ended_at)
	_check(not GS.finish("忠肃"), "重复 finish() 被拒——历史只走一遍")
	_check(GS.ended == "岸上的根", "重复 finish() 不覆盖")
	_check(GS.epilogue_lines().size() >= 5, "札记至少五行")
	# 终局后历史不再推进
	var seen_before: int = GS.news_seen.size()
	var id_before: String = GS.identity
	GM.advance_days(400)
	_check(GS.news_seen.size() == seen_before, "终局后不再投放新闻")
	_check(GS.identity == id_before, "终局后不再结算身份")
	# 存档 round-trip 带 ended
	var ed: Dictionary = GS.to_dict()
	GS.from_dict({})
	_check(not GS.is_ended(), "from_dict({}) 清空终局")
	GS.from_dict(ed)
	_check(GS.is_ended() and GS.ended == "岸上的根", "存档 round-trip 保留终局")

	# ── 守城 ──
	GS.from_dict({})
	_check(not GS.siege_open(), "开局无城防")
	GS.siege_begin()
	_check(GS.siege_open() and GS.siege_get("troops") == 300, "siege_begin 初始兵 300")
	var t0: int = GS.siege_get("troops")
	GS.siege_begin()
	_check(GS.siege_get("troops") == t0, "重复 siege_begin 不重置")
	GS.fame = 0
	_check(GS.siege_troop_cap() == 300, "名声 0 时募兵上限 300")
	GS.fame = 100
	_check(GS.siege_troop_cap() == 1000, "名声足时上限封顶 1000（城中兵不满千）")
	GS.fame = 20
	_check(GS.siege_troop_cap() == 540, "上限随名声（20 → 540）")
	# 石手军 ×1.5
	GS.siege_set("shishou", "")
	var sp_plain: float = GS.siege_power()
	GS.siege_set("shishou", "kept")
	var sp_keep: float = GS.siege_power()
	_check(sp_keep > sp_plain, "石手军抬高战力（%.0f > %.0f）" % [sp_keep, sp_plain])
	GS.siege_set("shishou", "disbanded")
	_check(abs(GS.siege_power() - sp_plain) < 0.01, "遣散后战力回落")
	# siege_add 不落负
	GS.siege_set("grain", 10)
	GS.siege_add("grain", -999)
	_check(GS.siege_get("grain") == 0, "守城资源不落负数")
	# 存档带 siege
	GS.siege_set("round", 2)
	var sd: Dictionary = GS.to_dict()
	GS.from_dict({})
	_check(not GS.siege_open(), "from_dict({}) 清空城防")
	GS.from_dict(sd)
	_check(GS.siege_get("round") == 2, "存档 round-trip 保留城防轮次")

	# ── only 过滤：士人短札海商永远收不到 ──
	GS.from_dict({})
	GS.identity = "scholar"
	Cal.from_dict({"year": 1273, "month": 6, "day": 1})
	var s_ids := []
	for item in GS.pending_news():
		s_ids.append(item.get("id", ""))
	_check(s_ids.has("n_1272_03_no_draft"), "士人线收到 1272 不呈稿短札")
	_check(s_ids.has("n_1273_02_dismissed"), "士人线收到 1273 罢归短札")
	GS.from_dict({})
	GS.identity = "merchant"
	Cal.from_dict({"year": 1273, "month": 6, "day": 1})
	var m_ids := []
	for item2 in GS.pending_news():
		m_ids.append(item2.get("id", ""))
	_check(not m_ids.has("n_1272_03_no_draft"), "海商线收不到士人短札")
	_check(m_ids.has("n_1273_02_xiangyang_falls"), "海商线仍收公共新闻")
	# flag 随投放写入
	GS.from_dict({})
	GS.identity = "scholar"
	Cal.from_dict({"year": 1273, "month": 1, "day": 28})
	GM.advance_days(40)
	_check(GS.has_flag("dismissed_1273"), "投放 1273 短札写入 dismissed_1273 旗标")
	_check(GS.has_flag("jia_offended"), "1272 短札旗标补投")

	# ── 结局正文回看 ──
	GS.from_dict({})
	_check(GS.finish("纲首", "正文若干"), "finish 带正文")
	_check(GS.ended_text == "正文若干", "ended_text 已存")
	var fd: Dictionary = GS.to_dict()
	GS.from_dict({})
	GS.from_dict(fd)
	_check(GS.ended_text == "正文若干", "存档 round-trip 保留结局正文")

	# ── 结局可发现性：每条线在窗口前都有预告 ──
	# 陈瓒两条预告不设 only：丙线的主角是乡土身份，only=merchant 时乡土线收不到
	var hints := {"n_1276_10_xinghua_muster": "scholar", "n_1277_01_chenzan_raises": "", "n_1277_07_xinghua_again": "", "n_1278_12_yashan": "merchant"}
	for hid in hints:
		var hn: Dictionary = GM.get_news_by_id(hid)
		_check(not hn.is_empty(), "预告新闻 %s 存在" % hid)
		_check(str(hn.get("only", "")) == hints[hid], "预告 %s 发给 %s" % [hid, hints[hid]])
	# 预告必须早于对应窗口
	_check(str(GM.get_news_by_id("n_1276_10_xinghua_muster").get("date", "")) < "1276-11", "守城预告早于 1276-11 围城")
	_check(str(GM.get_news_by_id("n_1277_01_chenzan_raises").get("date", "")) < "1277-02", "陈瓒预告早于 1277-02 复城")
	_check(str(GM.get_news_by_id("n_1277_07_xinghua_again").get("date", "")) < "1277-09", "再围预告早于 1277-09 涵江窗口")
	_check(str(GM.get_news_by_id("n_1278_12_yashan").get("date", "")) < "1279-01", "崖山预告早于 1279 正月")

	# ── 守城粮尽口径与卡面一致 ──
	GS.from_dict({})
	GS.siege_begin()
	GS.siege_set("grain", GS.SIEGE_GRAIN_PER_ROUND - 1)
	_check(GS.siege_get("grain") / GS.SIEGE_GRAIN_PER_ROUND == 0, "粮不足一阵时余阵数为 0")
	GS.siege_set("grain", GS.SIEGE_GRAIN_PER_ROUND * 3)
	_check(GS.siege_get("grain") / GS.SIEGE_GRAIN_PER_ROUND == 3, "粮够三阵")

	# ── 乡土身份可达（此前是死分支） ──
	GS.from_dict({})
	GS.hometown_tendency = 9
	GS.scholar_tendency = 4
	GS.sea_tendency = 3
	var hr: Dictionary = GS.resolve_identity_1268()
	_check(hr.get("resolved", false) and GS.identity == "hometown", "乡土压过两头 → identity=hometown（实际 %s）" % GS.identity)
	_check(GS.player_name == "陈子龙" and GS.has_flag("name_unchanged"), "乡土线不改名")
	# 乡土不足则仍按士人/海商二分
	GS.from_dict({})
	GS.hometown_tendency = 4
	GS.scholar_tendency = 4
	GS.sea_tendency = 6
	GS.resolve_identity_1268()
	_check(GS.identity == "merchant", "乡土未压过时不抢身份")
	# 乡土线能收到自己的短札通道（only=hometown 合法）
	GS.from_dict({})
	GS.identity = "hometown"
	_check(GS.news_variant() == "M", "乡土线取 M 版文案")

	# ── 陈文龙不能从海上逃走（涵江卡身份门） ──
	# 卡面条件在 Main._special_cards，此处校验旗标语义：renamed_wenlong 与 ending_root_sea 不可共存
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	_check(GS.has_flag("renamed_wenlong") and not GS.has_flag("ending_root_sea"), "改名后未持涵江结局旗标")

	# ── 「未归」：士人线错过守城仍有结局 ──
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	_check(Eco.war_status("xinghua") == "fallen", "1276-12 兴化已陷")
	_check(not GS.siege_open() and not GS.has_flag("siege_fought"), "未开城防、未打过囊山")
	_check(GS.finish("未归", "正文"), "未归可落定")
	_check(GS.ended == "未归", "未归结局名")
	# 打过囊山的不算「未归」
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.set_flag("siege_fought")
	_check(GS.has_flag("siege_fought"), "打过囊山即留痕，未归判据可排除")

	# ── 「未归」不得被陈瓒复城的那几个月钻空子 ──
	# 兴化 war 表：1277-02 loyal / 1277-09 besieged / 1277-11 fallen。若判据只看当前 war_status，
	# 士人线玩家在 1277-02 至 08 复城期间入港就躲过了结局。
	Cal.from_dict({"year": 1277, "month": 2, "day": 10})
	_check(Eco.war_status("xinghua") == "loyal", "1277-02 兴化确实回 loyal（复城）")
	var past_fall: bool = (Cal.year > 1276) or (Cal.year == 1276 and Cal.month >= 12)
	_check(past_fall, "1277-02 已过 1276-12 陷落点——判据须按日期而非当前战况")

	# ── 存档 round-trip：整局状态（不只 GameState） ──
	var SL: Node = root.get_node("SaveLoad")
	var Flt: Node = root.get_node("Fleet")
	GS.from_dict({})
	Cal.from_dict({"year": 1276, "month": 11, "day": 3})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	GS.player_name = "陈文龙"
	GS.money = 4321
	GS.siege_begin()
	GS.siege_set("round", 1)
	GS.siege_set("shishou", "kept")
	GS.siege_add("troops", 150)
	GS.ban_port("quanzhou", "1277-01")
	GS.add_ledger_note("斩王刚中使")
	var troops_before: int = GS.siege_get("troops")
	_check(SL.save_game(9, "xinghua"), "守城中途可存档")
	_check(SL.save_label(9).find("终") < 0, "未终局的档不带终局标记")
	# 打乱现场
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_check(SL.load_game(9), "读回守城档")
	_check(Cal.year == 1276 and Cal.month == 11, "读档复原历法")
	_check(GS.player_name == "陈文龙" and GS.identity == "scholar", "读档复原身份与姓名")
	_check(GS.siege_open() and GS.siege_get("round") == 1, "读档复原城防轮次")
	_check(GS.siege_get("troops") == troops_before, "读档复原兵力")
	_check(str(GS.siege.get("shishou", "")) == "kept", "读档复原石手军")
	_check(GS.is_port_banned("quanzhou"), "读档复原个人封港")
	_check("斩王刚中使" in GS.ledger_notes, "读档复原札记")
	_check(GS.money == 4321, "读档复原钱")
	# 战况是 Calendar 纯函数，读档后自然复原
	_check(Eco.war_status("xinghua") == "besieged", "读档后战况随历法复原（不入存档）")
	# 终局档带标记
	GS.finish("忠肃", "正文")
	_check(SL.save_game(9, "xinghua"), "终局可存档")
	_check(SL.save_label(9).find("终：忠肃") >= 0, "终局档标签带结局名（%s）" % SL.save_label(9))
	_check(SL.load_game(9) and GS.is_ended() and GS.ended == "忠肃", "读回终局档仍是终局态")
	# 用完清掉第 9 槽：云端 godot_smoke 断言第 9 槽是空卷（两道门禁共用同一 user:// 目录）
	for p in ["user://saves/save_9.json", "user://saves/save_9.json.bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# ── 跳年（P1 时间脊柱） ──
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	Flt.from_dict({})
	Eco.initialize()
	# 行为累计
	GS.record_trip("quanzhou", "hakata")
	GS.record_trip("quanzhou", "hakata")
	GS.record_trip("quanzhou", "penghu")
	_check(GS.era_trips == 3, "记满三趟")
	_check(GS.era_main_route().find("博多") >= 0, "主航线取次数最多者（%s）" % GS.era_main_route())
	# 跳年：历法真的走、行情重置、船况折旧
	if not Flt.ships.is_empty():
		Flt.ships[0]["durability"] = float(Flt.ships[0].get("max_durability", 120))
	var hull0: float = float(Flt.ships[0].get("durability", 0)) if not Flt.ships.is_empty() else 0.0
	Eco.rates["quanzhou"]["grain"] = 1.8
	var lines: Array = GM.skip_years(3)
	_check(Cal.year == 1258, "跳 3 年后历法到 1258（实际 %d）" % Cal.year)
	_check(not lines.is_empty(), "跳年返回摘要行")
	_check(abs(float(Eco.get_rate("quanzhou", "grain")) - 1.0) < 0.001, "跳年后行情重置为 1.0")
	if not Flt.ships.is_empty():
		var hull1: float = float(Flt.ships[0].get("durability", 0))
		_check(hull1 < hull0, "跳年后船况折旧（%.0f → %.0f）" % [hull0, hull1])
		_check(hull1 >= float(Flt.ships[0].get("max_durability", 120)) * GM.SKIP_HULL_FLOOR - 0.5, "折旧不低于下限")
	_check(Flt.morale <= GM.SKIP_MORALE_AFTER, "跳年后士气不高于 %d" % GM.SKIP_MORALE_AFTER)
	# 跳年期间新闻照常投放（1255→1258 应收到 1256 太学等）
	# 1255-03 跳 3 年 → 1258-03，期间到期的只有 1256 的两条（1258-09 尚未到）
	_check(GS.news_seen.size() == 2, "跳年期间新闻照常按月投放，且不越期（%d 条）" % GS.news_seen.size())
	_check(GS.news_seen.has("n_1256_03_taixue"), "跳年不吞掉途中的新闻")
	# 清段
	GS.clear_era()
	_check(GS.era_trips == 0 and GS.era_routes.is_empty(), "clear_era 清零")
	# 跳 0 年不动
	var y_before: int = Cal.year
	_check(GM.skip_years(0).is_empty(), "跳 0 年返回空")
	_check(Cal.year == y_before, "跳 0 年历法不动")
	# 晋升带 years 字段
	GS.from_dict({})
	GS.chapter = 1
	var cdef: Dictionary = GS.chapter_def()
	_check(int(cdef.get("advance_years", 0)) > 0, "第一章带 advance_years")
	# 抵港路由一节要实例化 Main，@onready 节点须等树 ready——留到首帧 _process 再跑，那里再收尾


## 首帧：树与 autoload 都已 ready，才能实例化 Main 并让其 @onready 节点就位
func _process(_delta: float) -> bool:
	if not _route_pending:
		return false
	_route_pending = false
	_route_check()
	print("STORY_CHECK SUMMARY fails=", _fails)
	GateReport.finish("godot_story_check", 1 if _fails > 0 else 0, "STORY_CHECK SUMMARY fails=%d" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


var _route_pending := true


## ── 抵港路由（2026-09-14 审计 P0）──
## 海图抵港走 SeaChart._arrive → last_port → Main.start_game → load_scene(last_port)。
## 此前 scenes.json 有与港口同名的剧情幕（ryukyu / hakata）且无 type=port，load_scene 命中剧情表
## 走调查页、不调 _on_enter_port，visited_ports 永不记录——章一 / 章二 must_visit 在真机上不可完成。
## 这里真的实例化 Main，按真机路由逐港 load_scene，断言 visited_ports 与章节晋升。
func _route_check() -> void:
	var Eco: Node = root.get_node("Economy")
	var Flt: Node = root.get_node("Fleet")
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 6, "day": 1})
	Flt.from_dict({})
	Eco.initialize()
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	_check(main_scene != null, "Main.tscn 可加载")
	if main_scene == null:
		return
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	_check(main.get("background") != null, "Main 实例 @onready 节点已就位（background 非 Nil）")
	var route_ports := ["ryukyu", "hakata", "penghu", "quanzhou", "zhangzhou", "xinghua", "champa"]
	for pid in route_ports:
		GS.last_port = pid
		main.load_scene(pid)
		_check(pid in GS.visited_ports, "抵港 load_scene(%s) 记入 visited_ports" % pid)
	_check(GS.visited_ports.size() == route_ports.size(), "七港各记一次（实际 %d）" % GS.visited_ports.size())
	# 剧情幕不冒充港口
	GS.visited_ports.clear()
	main.load_scene("ryukyu_bay")
	main.load_scene("hakata_ledger")
	_check(GS.visited_ports.is_empty(), "剧情幕 ryukyu_bay / hakata_ledger 不记港")
	# 章一 must_visit=ryukyu 在真机路由下可完成：够钱 + 五港含流求 → 晋升第二章
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 6, "day": 1})
	GS.chapter = 1
	GS.money = 6000
	GS.peak_money = 6000
	for pid in ["quanzhou", "xinghua", "penghu", "fuzhou"]:
		GS.last_port = pid
		main.load_scene(pid)
	_check(GS.chapter == 1, "四港未含流求，章一不晋升")
	GS.last_port = "ryukyu"
	main.load_scene("ryukyu")
	_check(GS.chapter == 2, "第五港抵流求 → 章一晋升第二章（实际第 %d 章）" % GS.chapter)
	_check(Cal.year >= 1257, "晋升已跳年（实际 %d 年）" % Cal.year)
	_close_dialogs(main)  # 真机上玩家会按「承此一路」；不关掉，下一个 exclusive 对话框会报错
	# 章二 must_visit=hakata 同理可完成
	GS.money = 25000
	GS.peak_money = 25000
	for pid in ["zhangzhou", "wenzhou", "mingzhou", "jeju"]:
		GS.last_port = pid
		main.load_scene(pid)
	_check(GS.chapter == 2, "九港未含博多，章二不晋升")
	GS.last_port = "hakata"
	main.load_scene("hakata")
	_check(GS.chapter == 3, "抵博多 → 章二晋升第三章（实际第 %d 章）" % GS.chapter)
	_close_dialogs(main)
	# ── 终局特殊卡必须进岸开名单：云端「今日只开三处」只在寻常设施里发牌，special_* 一律追加 ──
	GS.from_dict({})
	GS.identity = "merchant"
	Cal.from_dict({"year": 1279, "month": 2, "day": 1})
	GS.last_port = "guangzhou"
	main.load_scene("guangzhou")
	_check("special_yashan" in main.shore_hand, "1279-02 广州岸上有崖山卡（不受今日只开三处限制；名单 %s）" % [main.shore_hand])
	_check(main.shore_hand.size() >= 4, "崖山卡是第四扇门，不挤掉三处寻常门（现 %d 扇）" % main.shore_hand.size())
	GS.from_dict({})
	GS.record_discovery("nameless_shelter_bay")
	Cal.from_dict({"year": 1277, "month": 2, "day": 10})
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	_check(not ("special_hanjiang_escape" in main.shore_hand), "1277-02 复城之初兴化岸上没有涵江卡（名单 %s）" % [main.shore_hand])
	Cal.from_dict({"year": 1277, "month": 9, "day": 10})
	main.load_scene("xinghua")
	_check(Eco.war_status("xinghua") == "besieged", "1277-09 唆都再围（涵江卡前提）")
	_check("special_hanjiang_escape" in main.shore_hand, "1277-09 兴化岸上有涵江海口卡（名单 %s）" % [main.shore_hand])
	# S3 不得误触发：1277 秋再围不是陈文龙的城。没改名的玩家在兴化候过 1277-11 再陷，不得冒出城防记录或城破结算
	Cal.from_dict({"year": 1277, "month": 10, "day": 25})
	main.load_scene("xinghua")
	var waited_root := 0
	while Eco.war_status("xinghua") == "besieged" and waited_root < 45:
		main._on_shore_wait()
		waited_root += 1
	_check(Eco.war_status("xinghua") == "fallen" and not GS.is_ended() and not GS.siege_open(),
		"没改名的玩家候过 1277 再围（候 %d 日到 %s）不冒城防、不结算（结局「%s」）" % [waited_root, Cal.get_date_string(), GS.ended])
	Cal.from_dict({"year": 1277, "month": 9, "day": 10})
	main.load_scene("xinghua")
	# 涵江出海：结算标题的年号跟出海后的日历走、与终局落款同年（原先硬写「景炎三年三月」，卡却只在景炎二年出现，门禁一直绿）
	var fleet: Node = root.get_node("Fleet")
	fleet.water = maxi(fleet.water, 999)
	fleet.food = maxi(fleet.food, 999)
	main._on_hanjiang_escape()
	var era_year: String = Cal.get_era_year_string()
	var sheet_head := _find_label_text(main.get("_chapter_host"), "旧避风澳・")
	_check(era_year == "景炎二年" and sheet_head.find("旧避风澳・" + era_year) >= 0 and GS.ended_at.begins_with(era_year),
		"涵江出海结算标题与终局落款同为景炎二年（标题「%s」／落款「%s」）" % [sheet_head, GS.ended_at])
	# 标题只写到年：卡在九、十两月都开，写死哪一月都会和落款错月（09-28 Snow 定 B 方案时一并定的，合并时别冲回「三月」）
	_check(sheet_head.ends_with("旧避风澳・" + era_year),
		"涵江出海结算标题不写月份（标题「%s」／落款「%s」）" % [sheet_head, GS.ended_at])
	main._confirm_chapter_sheet()
	# 守城页走岸带：五张 siege_* 卡全上岸，尼寺不占门，动作行无「看风」
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	Cal.from_dict({"year": 1276, "month": 11, "day": 3})
	GS.siege_begin()
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	_check("siege_muster" in main.shore_hand and "siege_nangshan" in main.shore_hand and "siege_nunnery" not in main.shore_hand,
		"守城页五张卡在岸带、尼寺只作一行字（名单 %s）" % [main.shore_hand])
	_check(main.shore_hand.size() == 5, "守城岸带恰五扇门（现 %d）" % main.shore_hand.size())
	var siege_sail := false
	var sa: Node = main._shore_band().get_node_or_null("ShoreActions")
	if sa != null:
		for b in sa.get_children():
			if b is Button and (b as Button).text == "看风":
				siege_sail = true
	_check(not siege_sail, "围城中动作行没有「看风」")
	# 1277 秋唆都再围时，陈文龙的守城页不得重开（城防没了结的旧档也一样）
	Cal.from_dict({"year": 1277, "month": 9, "day": 3})
	main.load_scene("xinghua")
	_check(not ("siege_muster" in main.shore_hand), "1277-09 再围不重开 1276 的守城页（名单 %s）" % [main.shore_hand])
	# S3：城防没了结的旧档，日历已过首守城破时点 → 进港即按城破结算，不当作 1277 的再围、也不回寻常港页接着跑商
	_check(GS.ended == "忠肃" and not GS.siege_open(),
		"城防没了结的旧档 1277-09 进兴化 → 按首守城破结算「忠肃」（结局「%s」）" % GS.ended)
	_close_dialogs(main)
	# S3：守城页「再候一日」候过首守城破时点（兴化战况表第一段 besieged 的尽头，不写死月份），城防还开着 → 走城破结算
	var fall_ym: String = main._first_siege_fall_ym()
	_check(fall_ym.begins_with("1276-"),
		"首守城破时点取战况表第一段 besieged 的尽头、落在陈文龙守城那一年（%s），不取 1277 秋再围" % fall_ym)
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	Cal.from_dict({"year": 1276, "month": 11, "day": 3})
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	_check(GS.siege_open() and main._shore_mode == "siege", "1276-11 进兴化开守城页（页型 %s）" % main._shore_mode)
	main._on_shore_wait()
	_check(not GS.is_ended() and main._shore_mode == "siege", "围城中候一日仍是守城页、不结算（%s）" % Cal.get_date_string())
	var waited_siege := 1
	while not GS.is_ended() and Eco.war_status("xinghua") == "besieged" and waited_siege < 45:
		main._on_shore_wait()
		waited_siege += 1
	var now_ym := "%04d-%02d" % [Cal.year, Cal.month]
	var wait_sail := false
	var wa: Node = main._shore_band().get_node_or_null("ShoreActions")
	if wa != null:
		for b in wa.get_children():
			if b is Button and (b as Button).text == "看风":
				wait_sail = true
	_check(GS.ended == "忠肃" and not GS.siege_open() and now_ym >= fall_ym and not wait_sail,
		"守城页候 %d 日到 %s（城破时点 %s）→ 按城破结算「%s」，不回寻常港页、没有「看风」" % [waited_siege, Cal.get_date_string(), fall_ym, GS.ended])
	_close_dialogs(main)
	_life_line_check(main)
	# S4：玉湖陈宅「族叔陈瓒愿入船股」——陈瓒死于兴化再陷（战况表第二段 besieged 的尽头），死后不再出现
	var zan_falls: Array = main._xinghua_fall_yms()
	_check(zan_falls.size() >= 2, "兴化战况表有首守城破与再陷两个城破时点（%s）" % [zan_falls])
	# 月份从战况表推，不写死：起股那年、首守城破当月（那是陈文龙的城）、再陷前一月该有；再陷当月、次年、1285 该没有
	var zan_cases: Array = [[main.CHEN_ZAN_FROM_YEAR, 6, true], [1285, 5, false]]
	if zan_falls.size() >= 2:
		var fp: PackedStringArray = str(zan_falls[0]).split("-")
		zan_cases.append([int(fp[0]), int(fp[1]), true])
		var zp: PackedStringArray = str(zan_falls[1]).split("-")
		var zy := int(zp[0])
		var zm := int(zp[1])
		zan_cases.append([zy if zm > 1 else zy - 1, zm - 1 if zm > 1 else 12, true])
		zan_cases.append([zy, zm, false])
		zan_cases.append([zy + 1, 3, false])
	for zc in zan_cases:
		GS.from_dict({})
		GS.identity = "hometown"
		GS.fame = 40
		Cal.from_dict({"year": zc[0], "month": zc[1], "day": 5})
		main.load_scene("xinghua_residence")
		var zan_btn := false
		for zb in main.choices_container.get_children():
			if zb is Button and (zb as Button).text.find("陈瓒愿入船股") >= 0:
				zan_btn = true
		_check(zan_btn == bool(zc[2]),
			"玉湖陈宅 %d-%02d%s「陈瓒愿入船股」（再陷 %s）" % [zc[0], zc[1], "有" if zc[2] else "没有", zan_falls[1] if zan_falls.size() >= 2 else "?"])
	_lin_hua_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	# 旅店路由：city_inn 必须落到 {港}_inn，不能是 city_inn
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	# 云端「今日只开三处」：不在当日岸开名单里的门会被挡；这里把旅店放进名单再点
	if not ("city_inn" in main.shore_hand):
		main.shore_hand.append("city_inn")
	main._on_facility_pressed({"id": "city_inn"})
	_check(main.current_scene_id == "quanzhou_inn", "旅店按钮落到 quanzhou_inn（实际 %s）" % main.current_scene_id)
	# 背景回落：缺图不黑屏（拿一个肯定不存在的名字试）
	main._set_background_file("bg_definitely_missing.jpg")
	_check(main.background.texture != null, "缺失背景图回落到 FALLBACK_BG，texture 非 Nil")
	# 标题屏 / 海图底图 bg_world_map.jpg 已落地
	main._apply_background("title", "")
	_check(main._bg_file == "bg_world_map.jpg", "标题屏用 bg_world_map.jpg（实际 %s）" % main._bg_file)
	# 终局：结算图压在结局对话框后，之后的港页也持续压着
	GS.from_dict({})
	GS.finish("忠肃", "正文")
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	_check(main._bg_file == "bg_end_temple.jpg", "终局「忠肃」港页压 bg_end_temple.jpg（实际 %s）" % main._bg_file)
	GS.from_dict({})
	_close_dialogs(main)
	_hooks_bg_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_v0928_crew_check(main)
	main.queue_free()


## 扩充包钩子第一批（2026-09-28）：H2 港页变体、H4 序章分页、牙行货图槽。
## 断言不钉图在不在：缺图时画面与原图一致、找图顺序用注入的「文件在不在」表测，图进库后照样绿。
func _hooks_bg_check(main: Node) -> void:
	var sweep := [[1255, 3], [1274, 10], [1274, 12], [1275, 7], [1276, 5], [1276, 7], [1276, 11], [1277, 1], [1277, 4], [1278, 3], [1290, 12]]
	# H2 缺图：注入空表（一张变体都没有）→ 各港各年月都是 PORT_BG 原图
	main._port_bg_probe = {}
	var drift := []
	for ym in sweep:
		Cal.from_dict({"year": ym[0], "month": ym[1], "day": 1})
		for pid in main.PORT_BG.keys():
			if main._port_bg(pid) != main.PORT_BG[pid]:
				drift.append("%s@%d-%d" % [pid, ym[0], ym[1]])
	_check(drift.is_empty(), "H2 缺图时 %d 港 × %d 个年月的港页底图都是 PORT_BG 原图（偏离 %s）" % [main.PORT_BG.size(), sweep.size(), drift])
	# H2 查盘：不注入时只会给出盘上真有的文件
	main._port_bg_probe = null
	var ghost := []
	for ym in sweep:
		Cal.from_dict({"year": ym[0], "month": ym[1], "day": 1})
		for pid in main.PORT_BG.keys():
			var f: String = main._port_bg(pid)
			if not FileAccess.file_exists("res://assets/" + f):
				ghost.append(f)
	_check(ghost.is_empty(), "H2 查盘时港页底图全是盘上真有的文件（缺 %s）" % [ghost])
	# H2 找图顺序：战况 > 年份 > 季节 > 原图；loyal 不找战况档；博多夏借春、冬借秋；港 id 按 ports.json（海口不吃兴化城的图）
	var cases := [
		[1276, 11, "xinghua", ["bg_xinghua_besieged.jpg", "bg_xinghua_autumn.jpg"], "bg_xinghua_autumn.jpg", "兴化 1276-11 围城、城防记录没开（寻常港页）：跳过守城专用的围城档，落到秋季档"],
		[1276, 11, "xinghua", ["bg_xinghua_autumn.jpg"], "bg_xinghua_autumn.jpg", "兴化 1276-11 缺围城图：落到秋季档"],
		[1276, 11, "xinghua_harbor", ["bg_xinghua_besieged.jpg"], main.PORT_BG["xinghua_harbor"], "兴化海口 1276-11 不借兴化城的围城图"],
		[1277, 1, "quanzhou", ["bg_quanzhou_fallen.jpg", "bg_quanzhou_contested.jpg", "bg_quanzhou_winter.jpg"], "bg_quanzhou_fallen.jpg", "泉州 1277-01 已降元：取 fallen 档"],
		[1277, 1, "quanzhou", ["bg_quanzhou_contested.jpg", "bg_quanzhou_winter.jpg"], "bg_quanzhou_winter.jpg", "泉州 1277-01 不取过期的对峙档，落到冬季档"],
		[1255, 3, "quanzhou", ["bg_quanzhou_loyal.jpg"], main.PORT_BG["quanzhou"], "loyal 不找 bg_<港>_loyal.jpg"],
		[1276, 7, "hakata", ["bg_hakata_1276.jpg", "bg_hakata_spring.jpg"], "bg_hakata_1276.jpg", "博多 1276-07：年份档压过季节档"],
		[1290, 12, "hakata", ["bg_hakata_1276.jpg", "bg_hakata_autumn.jpg"], "bg_hakata_1276.jpg", "博多 1290：取不大于当年的最大登记年份"],
		[1275, 7, "hakata", ["bg_hakata_1276.jpg", "bg_hakata_spring.jpg"], "bg_hakata_spring.jpg", "博多 1275-07 未到防塁年：夏季借春版"],
		[1276, 7, "hakata", ["bg_hakata_spring.jpg"], "bg_hakata_spring.jpg", "博多 1276-07 缺防塁图：落到夏借春"],
		[1275, 12, "hakata", ["bg_hakata_autumn.jpg", "bg_hakata_winter.jpg"], "bg_hakata_autumn.jpg", "博多冬季借秋版"],
		[1274, 12, "hakata", ["bg_hakata_closed.jpg", "bg_hakata_autumn.jpg"], "bg_hakata_closed.jpg", "博多 1274-12 封港：战况档压过季节档"],
	]
	GS.from_dict({})
	for c in cases:
		Cal.from_dict({"year": c[0], "month": c[1], "day": 1})
		var probe := {}
		for f in c[3]:
			probe[f] = true
		main._port_bg_probe = probe
		var got: String = main._port_bg(c[2])
		_check(got == c[4], "H2 %s（实际 %s）" % [c[5], got])
	# 兴化围城档只给守城页（画的是 1276 冬陈文龙守城的城头白布）：城防记录开着才取；1277 秋陈瓒那一围不取
	main._port_bg_probe = {"bg_xinghua_besieged.jpg": true, "bg_xinghua_autumn.jpg": true}
	Cal.from_dict({"year": 1276, "month": 11, "day": 1})
	GS.siege_begin()
	var got_siege: String = main._port_bg("xinghua")
	_check(got_siege == "bg_xinghua_besieged.jpg", "H2 兴化 1276-11 城防记录开着（守城页）：取围城档（实际 %s）" % got_siege)
	GS.from_dict({})
	Cal.from_dict({"year": 1277, "month": 9, "day": 1})
	var got_zan: String = main._port_bg("xinghua")
	var zan_war: String = root.get_node("Economy").war_status("xinghua")
	_check(zan_war != "besieged" or got_zan != "bg_xinghua_besieged.jpg",
		"H2 兴化 1277-09 再围、没有城防记录：不取 1276 的围城档（战况 %s，实际 %s）" % [zan_war, got_zan])
	# 接线：士人线 1276-11 进兴化开守城页，进港那一下城防记录还没开，_build_shore 要补换成围城档
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	Cal.from_dict({"year": 1276, "month": 11, "day": 3})
	GS.last_port = "xinghua"
	main._port_bg_probe = {"bg_xinghua_besieged.jpg": true}
	main.load_scene("xinghua")
	# 期望值按盘面算：图没进库时回落海路图；路径拆开拼，免得 check_assets 当成必须在库的引用
	var siege_file := "bg_xinghua_besieged.jpg"
	var siege_want: String = siege_file if FileAccess.file_exists("res://assets/" + siege_file) else main.FALLBACK_BG
	_check(main._shore_mode == "siege" and main._bg_file == siege_want,
		"H2 守城页进港即换围城档（页型 %s，应 %s，实际 %s）" % [main._shore_mode, siege_want, main._bg_file])
	GS.from_dict({})
	_close_dialogs(main)
	main._port_bg_probe = null
	# H2 接线：港页走 _port_bg；岸上候一日（真走 _on_shore_wait）跨了档换图、没跨档不重载。
	# 注入表只决定 _port_bg 挑哪一档；_set_background_file 真去盘上取图——fallen 图没进库时回落海路图，进了库就是它本身。
	# 期望值按盘面算，所以 01 批的 bg_quanzhou_fallen.jpg 进不进库都绿（2026-09-28 评审 M1）；路径拆开拼，免得 check_assets 当成必须在库的引用
	var fallen_file := "bg_quanzhou_fallen.jpg"
	var fallen_want: String = fallen_file if FileAccess.file_exists("res://assets/" + fallen_file) else main.FALLBACK_BG
	main._port_bg_probe = {fallen_file: true}
	GS.from_dict({})
	Cal.from_dict({"year": 1277, "month": 1, "day": 5})
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	_check(main._bg_file == fallen_want, "H2 泉州 1277-01 港页底图走 _port_bg：注入 fallen 档即换（应 %s，实际 %s）" % [fallen_want, main._bg_file])
	# 1276-11-29 泉州对峙：注入表里没有对峙档和秋季档 → 原图；候到 11-30 没跨月 → 同一张纹理（不重载）；再候到 12-01 降元 → 换 fallen 档
	GS.from_dict({})
	Cal.from_dict({"year": 1276, "month": 11, "day": 29})
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	_check(main._bg_file == main.PORT_BG["quanzhou"], "H2 泉州 1276-11 对峙、注入表无此档：港页压原图（实际 %s）" % main._bg_file)
	var tex_before: Texture2D = main.background.texture
	main._on_shore_wait()
	_check(Cal.month == 11 and main.background.texture == tex_before and main._bg_file == main.PORT_BG["quanzhou"],
		"H2 候一日没跨月：港页底图不重载（%d-%d，纹理同一实例 %s，%s）" % [Cal.month, Cal.day, main.background.texture == tex_before, main._bg_file])
	main._on_shore_wait()
	_check(Cal.month == 12 and main._bg_file == fallen_want and main.background.texture != tex_before,
		"H2 候一日跨到降元月：港页底图跟着换（%d-%d，应 %s，实际 %s）" % [Cal.month, Cal.day, fallen_want, main._bg_file])
	main._port_bg_probe = null
	_close_dialogs(main)

	# H4 序章分页：cg_title 不进表；每个 cg_ 页 = 表里有且文件在的专属图，否则 title 型压标题海图、其余压酒棚（不落海路图）
	_check(not main.PROLOGUE_PAGE_BG.has("cg_title"), "H4 PROLOGUE_PAGE_BG 不收 cg_title")
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	var wrong := []
	var mapped := 0
	for s in GM.scenes_data.get("scenes", []):
		var sid := str(s.get("id", ""))
		if not sid.begins_with("cg_"):
			continue
		main.load_scene(sid)
		var want: String = main.PROLOGUE_BG
		if str(s.get("type", "")) == "title":
			want = "bg_world_map.jpg"
		var own := str(main.PROLOGUE_PAGE_BG.get(sid, ""))
		if own != "" and FileAccess.file_exists("res://assets/" + own):
			want = own
			mapped += 1
		if main._bg_file != want:
			wrong.append("%s=%s（应 %s）" % [sid, main._bg_file, want])
	_check(wrong.is_empty() and mapped >= 3, "H4 序章各页底图按表取、缺图回落酒棚或标题海图（换图 %d 页，不符 %s）" % [mapped, wrong])
	_check(main._prologue_page_bg("cg_veteran", {"cg_veteran": "bg_prologue_missing_probe.jpg"}) == "",
		"H4 表里登记了但文件缺：_prologue_page_bg 给空，调用方回落酒棚")
	_close_dialogs(main)

	# 牙行货图槽：图在才挂 GoodIcon；缺图不加节点，手续脚注仍直接挂在卡的五行列里（卡面与原先一样）
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	GS.last_port = "quanzhou"
	GS.money = 5000
	main.load_scene("quanzhou_market")
	var slips: Node = main.find_child("BrokerSlips", true, false)
	var hand: PackedStringArray = main.broker_hand
	var bad := []
	if slips != null:
		for i in range(mini(slips.get_child_count(), hand.size())):
			var card: Node = slips.get_child(i)
			var has_art := FileAccess.file_exists("res://assets/goods/good_%s.png" % hand[i])
			var icon := card.find_child("GoodIcon", true, false)
			var fee := card.find_child("PriceFee", true, false)
			var body: Node = card.get_child(0).get_child(0)
			if (icon != null) != has_art:
				bad.append("%s 图%s而 GoodIcon %s" % [hand[i], "在" if has_art else "缺", "挂了" if icon != null else "没挂"])
			if not has_art and (fee == null or fee.get_parent() != body or card.find_child("GoodTop", true, false) != null):
				bad.append("%s 缺图时卡面结构变了" % hand[i])
	_check(slips != null and slips.get_child_count() > 0 and bad.is_empty(), "牙行货图槽：图在才挂、缺图卡面不变（%d 张卡，不符 %s）" % [slips.get_child_count() if slips != null else 0, bad])


## 关掉 Main 弹出的 AcceptDialog（章节晋升 / 通告），等价于玩家按下确认
func _close_dialogs(main: Node) -> void:
	for c in main.get_children():
		if c is AcceptDialog:
			c.hide()
			c.free()


## 生卒一行：卒年到次年才写（#11）；主角只在「忠肃」这条世界线写卒年（查漏 §四.B.8）。
## 人物志详页、见面页人物栏、立绘面板三处都走 CharacterArt.life_line，逐处实建控件看上屏字。
func _life_line_check(main: Node) -> void:
	var Art = load("res://scripts/ui/CharacterArt.gd")
	var pc: Dictionary = GM.get_character("chen_wenlong")
	var pc_born := str(int(pc.get("born", 0)))
	var pc_died := str(int(pc.get("died", 0)))
	_check(pc_born != "0" and pc_died != "0", "主角原稿有生卒（%s—%s），下面才测得出卒年藏没藏" % [pc_born, pc_died])
	# [身份, 改名文龙, 年, 月, 结局, 该不该写卒年]
	var cases := [
		["merchant", false, 1278, 3, "", false],
		["hometown", false, 1277, 10, "岸上的根", false],
		["merchant", false, 1279, 2, "海上宋鬼", false],
		["merchant", false, 1285, 5, "纲首", false],
		["merchant", false, 1285, 5, "泉州蒲氏的船", false],
		["scholar", true, 1277, 1, "未归", false],
		["scholar", true, 1276, 12, "忠肃", true],
	]
	for cs in cases:
		GS.from_dict({})
		GS.identity = cs[0]
		if cs[1]:
			GS.set_flag("renamed_wenlong")
		Cal.from_dict({"year": cs[2], "month": cs[3], "day": 5})
		if str(cs[4]) != "":
			GS.finish(cs[4], "正文")
		var ll: String = Art.life_line(pc)
		_check((ll.find(pc_died) >= 0) == bool(cs[5]),
			"主角生卒「%s」（%s・%d-%02d・结局「%s」）%s" % [ll, cs[0], cs[2], cs[3], cs[4], "写卒年" if cs[5] else "不写卒年"])
	# 三处上屏：活着的世界线（海商 1278，未了结）与「忠肃」各看一遍
	var cp_scr = load("res://scripts/chars/CharPortraitPanel.gd")
	var cx_scr = load("res://scripts/ui/CharacterCodex.gd")
	for dead in [false, true]:
		GS.from_dict({})
		if dead:
			GS.identity = "scholar"
			GS.set_flag("renamed_wenlong")
			Cal.from_dict({"year": 1276, "month": 12, "day": 5})
			GS.finish("忠肃", "正文")
		else:
			GS.identity = "merchant"
			Cal.from_dict({"year": 1278, "month": 3, "day": 5})
		var tag := "忠肃" if dead else "海商 1278 未了结"
		var cx: Control = cx_scr.new()
		root.add_child(cx)
		cx.call("begin", "chen_wenlong")
		var t_codex := _find_label_text(cx, pc_born)
		var pp: Node = cp_scr.new()
		root.add_child(pp)
		pp.call("show_character", pc)
		var t_panel := _find_label_text(pp, pc_born)
		main._fill_npc_profile(pc)
		var t_npc := _find_label_text(main.get("_npc_profile"), pc_born)
		for pair in [["人物志", t_codex], ["立绘面板", t_panel], ["见面页", t_npc]]:
			var t: String = pair[1]
			_check(t != "" and (t.find(pc_died) >= 0) == dead,
				"%s主角生卒（%s）%s卒年：「%s」" % [pair[0], tag, "写" if dead else "不写", t])
		cx.queue_free()
		pp.queue_free()
	# #11 卒年到次年才写：陈瓒卒于 1277（冬），1277 年里不写，1278 年写
	var cz: Dictionary = GM.get_character("chen_zan")
	var cz_died := int(cz.get("died", 0))
	_check(cz_died > 0, "陈瓒原稿有卒年（%d）" % cz_died)
	GS.from_dict({})
	Cal.from_dict({"year": cz_died, "month": 11, "day": 5})
	var cz_same: String = Art.life_line(cz)
	Cal.from_dict({"year": cz_died + 1, "month": 1, "day": 1})
	var cz_next: String = Art.life_line(cz)
	_check(cz_same.find(str(cz_died)) < 0 and cz_next.find(str(cz_died)) >= 0,
		"卒年到次年才写：陈瓒 %d 年里「%s」，%d 年正月「%s」" % [cz_died, cz_same, cz_died + 1, cz_next])
	GS.from_dict({})


## 在节点树里找第一个含 needle 的 Label 文本（册页标题等）；找不到返回空串
func _find_label_text(node: Node, needle: String) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node is Label and (node as Label).text.find(needle) >= 0:
		return (node as Label).text
	for c in node.get_children():
		var t := _find_label_text(c, needle)
		if t != "":
			return t
	return ""


## ── 林华伏笔（拍板清单 DESIGN1-8 ①，comp 线 09-28）──
## 修前 lin_hua 不在 crew.json：crew_history 只由 Crew.hire 写，hire 先查 candidate_def，查无此人即返回，
## 所以 Main._siege_lin_hua 的 known 恒假，「你的缆绳系得好」一钮和城破时 lin_hua_reminded 那句都是死分支。
## 修后：第二章起泉州酒馆可雇（舵工）；雇过即记 crew_history；景炎元年十月（1276-10，leave_from）史实辞船，
## 酒馆不再列名，crew_history 照留。守城第三阵前，雇过的多一钮，没雇过的照旧只有「让他去」「不去」。
## 评审后补（comp 线评审第 4、10 条）：离辞船不足两个月（1276-09 起）酒馆就不再列他；十月初一先下船、后发饷，不扣他的十月俸；
## 跳年跨过 1276-10，册页的跳年摘要里有他辞船那一句。
func _lin_hua_check(main: Node) -> void:
	var Crw: Node = root.get_node("Crew")
	GS.from_dict({})
	Crw.from_dict({})
	Cal.from_dict({"year": 1258, "month": 3, "day": 1})
	var lin: Dictionary = Crw.candidate_def("lin_hua")
	_check(not lin.is_empty() and str(lin.get("port", "")) == "quanzhou", "crew.json 有林华候选，在泉州候雇")
	GS.chapter = 1
	_check(not _has_id(Crw.candidates_at("quanzhou"), "lin_hua"), "第一章泉州酒馆不列林华")
	GS.chapter = 2
	_check(_has_id(Crw.candidates_at("quanzhou"), "lin_hua"), "第二章起泉州酒馆可雇林华")
	# 候雇截止：1276-08 仍列名，1276-09 起不列（离 leave_from 只剩一个月，雇进来当月就走、白付入伙钱）
	Cal.from_dict({"year": 1276, "month": 8, "day": 28})
	_check(_has_id(Crw.candidates_at("quanzhou"), "lin_hua"), "1276-08 泉州酒馆仍列林华（候雇窗口的最后一个月）")
	Cal.from_dict({"year": 1276, "month": 9, "day": 2})
	_check(not _has_id(Crw.candidates_at("quanzhou"), "lin_hua"), "1276-09 起泉州酒馆不再列林华（离辞船不足两个月即截止）")
	Cal.from_dict({"year": 1258, "month": 3, "day": 1})
	GS.money = 100000
	var res: Dictionary = Crw.hire("lin_hua")
	_check(res.get("ok", false) and "lin_hua" in GS.crew_history, "雇林华即记入 crew_history（守城认人的判据）")
	# 史实辞船：九月还在船，十月初一通告一条、下船；酒馆不再列名
	Cal.from_dict({"year": 1276, "month": 9, "day": 25})
	_check(_has_id(Crw.roster(), "lin_hua"), "1276-09 林华仍在船")
	var n0 := _notices.size()
	var money0 := int(GS.money)
	_advance_to(1276, 10)
	var leave_n := 0
	for t in _notices.slice(n0):
		if str(t).begins_with("【辞船】") and str(t).find("林华") >= 0:
			leave_n += 1
	_check(not _has_id(Crw.roster(), "lin_hua") and leave_n == 1, "1276-10 林华史实辞船，月初通告恰一条（%d 条）" % leave_n)
	# 下船先于发饷：十月初一只剩他一个职事，这个月的俸不该扣（扣了就是 money0 − 现银 ≥ 他的月俸）
	_check(money0 - int(GS.money) < int(lin.get("wage", 0)), "十月初一先下船后发饷，不扣林华的十月俸（钱 %d → %d，月俸 %d）" % [money0, int(GS.money), int(lin.get("wage", 0))])
	_check("lin_hua" in GS.crew_history, "辞船后 crew_history 仍留着林华")
	_check(not _has_id(Crw.candidates_at("quanzhou"), "lin_hua"), "辞船后泉州酒馆不再列林华")
	# 守城第三阵前的林华事件：雇过才多「缆绳」一钮；按下写 lin_hua_reminded、城防士气 +5
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	Cal.from_dict({"year": 1276, "month": 11, "day": 3})
	GS.siege_begin()
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	main._siege_lin_hua()
	var rope: Button = _find_button(main.choices_container, "你的缆绳系得好", false)
	_check(rope != null, "雇过林华：守城第三阵前多「你的缆绳系得好」一钮")
	if rope != null:
		var m0: int = GS.siege_get("morale")
		rope.pressed.emit()
		_check(GS.has_flag("lin_hua_reminded") and GS.siege_get("morale") == m0 + 5 and GS.siege.get("lin_hua_sent", false),
			"按下缆绳钮：写 lin_hua_reminded、城防士气 +5（%d → %d）" % [m0, GS.siege_get("morale")])
		# 城破册页读 lin_hua_reminded：多「那个结松了」一句（_siege_fall 的 elif 分支，修前同样走不到）
		main._siege_fall("三阵毕")
		_check(GS.ended_text.find("那个结松了") >= 0, "提醒过林华：城破册页多「那个结松了」一句")
		main._confirm_chapter_sheet()
	# 反例：没雇过林华，只有「让他去」「不去」；城破册页没有那一句
	GS.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	GS.siege_begin()
	main._siege_lin_hua()
	_check(_find_button(main.choices_container, "你的缆绳系得好", false) == null and _find_button(main.choices_container, "让他去", true) != null,
		"没雇过林华：守城第三阵前没有缆绳钮，「让他去」照旧")
	main._siege_fall("三阵毕")
	_check(GS.ended_text.find("林华出去两天") >= 0 and GS.ended_text.find("那个结松了") < 0, "没提醒过林华：城破册页只写「林华出去两天」")
	main._confirm_chapter_sheet()
	# 跳年跨过 1276-10（1273-06 跳四年）：月初【辞船】只进日志，册页的跳年摘要也要有他辞船那一句（草案 §1.4、§4.7 第 3 条）
	GS.from_dict({})
	Crw.from_dict({})
	GS.chapter = 2
	GS.money = 100000
	Cal.from_dict({"year": 1273, "month": 6, "day": 1})
	var hired_ok: bool = Crw.hire("lin_hua").get("ok", false)
	var skip_lines: Array = GM.skip_years(4)
	var note: String = Crw.leave_note(lin)
	_check(hired_ok and not _has_id(Crw.roster(), "lin_hua") and note != "" and note in skip_lines,
		"1273-06 跳四年跨过 1276-10：林华下船，跳年摘要有「%s」一行（摘要 %s）" % [note, skip_lines])
	_check(not skip_lines.is_empty() and str(skip_lines[-1]).begins_with("——自"), "跳年摘要末行仍是「——自…至于…」")
	GS.from_dict({})
	Crw.from_dict({})


func _has_id(list: Array, cid: String) -> bool:
	for c in list:
		if typeof(c) == TYPE_DICTIONARY and str(c.get("id", "")) == cid:
			return true
	return false


## 在 box 的直接子节点里找钮：exact 时全文相等，否则包含 needle 即可；找不到返回 null
func _find_button(box: Node, needle: String, exact: bool) -> Button:
	if box == null:
		return null
	for b in box.get_children():
		if b is Button:
			var t := (b as Button).text
			if (exact and t == needle) or (not exact and t.find(needle) >= 0):
				return b as Button
	return null


## ── crew 线 09-28 验收修复：海战夺船、战果注记、船籍簿、辞船显眼度 ──
## 修前：接舷夺下末艘时被夺的船还挂在树上、hull_hp>0，带 boarded 的退出永远走不到（下一帧 _process 以 {} 判胜：
## 出战墨边「战罢」、注记缺「接舷既定。」）；player_damage 被夺来船的满耐久冲成负数（注记钳成「受损 0」）；
## 发炮船已释放时炮弹命中报 SCRIPT ERROR、爆炸与 queue_free 都没走；夺来的船都叫「快船」分不清；【辞船】被 plain_log 去掉。
## 本节全在一帧里同步跑（headless 下接舷不停 0.42 s、题签起不来走浮字兜底），修前「夺下末艘当帧出战」这条就断不出 boarded。
func _v0928_crew_check(main: Node) -> void:
	var Flt: Node = root.get_node("Fleet")
	var Crw: Node = root.get_node("Crew")
	var Voy: Node = root.get_node("Voyage")
	var FX = load("res://scripts/combat/CombatFx.gd")
	var sc_const: Dictionary = (load("res://scripts/SeaChart.gd") as GDScript).get_script_constant_map()
	var saved_ships: Array = (Flt.get("ships") as Array).duplicate(true)
	var saved_water: int = Flt.water
	var saved_food: int = Flt.food
	var saved_morale: int = Flt.morale
	# 一、文案：市舶纪事右舷、哨船牌数与刷船数同数、瞭望
	var note_combat := str((load("res://scripts/ui/VisionStage.gd") as GDScript).get_script_constant_map().get("NOTE_COMBAT", ""))
	_check(note_combat.begins_with("右舷齐射") and note_combat.find("左舷") < 0, "市舶纪事注记写「右舷齐射」，与右舷炮焰同侧（得「%s」）" % note_combat)
	var patrol: Dictionary = sc_const.get("PATROL_ENEMY", {})
	var cn_n: String = GM.cn_num(int(patrol.get("count", 0)))
	var patrol_text := str(Voy.call("_yuan_patrol_event").get("text", ""))
	_check(patrol_text.begins_with(cn_n + "条船"), "元军哨船遭遇牌写「%s条船」，与 PATROL_ENEMY.count=%d 同数（得「%s」）" % [cn_n, int(patrol.get("count", 0)), patrol_text.substr(0, 8)])
	var pirate_text := str(Voy.call("pirate_sighting").get("text", ""))
	_check(pirate_text.find("瞭望") >= 0 and pirate_text.find("了望") < 0, "海寇遭遇牌写「瞭望手」")
	# 二、全靠接舷夺下两艘海寇：当帧带 boarded 出战；战损只算开战在场的船；夺来的按序号起名
	GS.from_dict({})
	Cal.from_dict({"year": 1258, "month": 4, "day": 10})
	Flt.set("ships", [])
	Flt.call("add_ship", "fu_ship_medium", "")
	var fs0: Dictionary = (Flt.get("ships") as Array)[0]
	fs0["crew"] = int(Flt.call("ship_crew_max", 0))
	Flt.water = 300
	Flt.food = 300
	Flt.morale = 80
	var pirate: Dictionary = sc_const.get("PIRATE_ENEMY", {})
	var got: Array = []
	var wm := _crew_battle(pirate, "pirate", got)
	# 开战刷船距离：DIST_MAX 不超过镜头半高（画布高 / 镜头 zoom / 2，都从工程与场景里读），任何角度刷出船心都在画内
	var cam: Camera2D = (wm.get("ship") as Node).get_node_or_null("Camera2D") as Camera2D
	var view_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var half_h := view_h / (2.0 * cam.zoom.y) if cam != null and cam.zoom.y > 0.0 else 0.0
	var spawn_max := float((wm.get_script() as GDScript).get_script_constant_map().get("COMBAT_SPAWN_DIST_MAX", INF))
	var foes := _crew_foes(wm)
	var own_pos: Vector2 = (wm.get("ship") as Node2D).position
	var far_y := 0.0
	for f in foes:
		far_y = maxf(far_y, absf((f as Node2D).position.y - own_pos.y))
	_check(half_h > 0.0 and spawn_max <= half_h and far_y <= half_h,
		"开战刷船距离上限 %.0f ≤ 镜头半高 %.0f（本局敌船离本船竖向最远 %.0f）" % [spawn_max, half_h, far_y])
	# 分离：两艘叠在一处时各自往外推
	if foes.size() >= 2:
		(foes[1] as Node2D).position = (foes[0] as Node2D).position + Vector2(40, 0)
		var push: Vector2 = foes[0].call("_separation_push")
		_check(push.x < 0.0, "两艘敌船贴在一处时分离推力朝外（%s）" % push)
	# 开战后旗舰挨了 40：战损只算这 40，夺来入列的满耐久新船不计
	var flag: Dictionary = (Flt.get("ships") as Array)[0]
	flag["durability"] = float(flag.get("durability", 0.0)) - 40.0
	for f in foes:
		f.set("crew", 0)  # 敌战力 0 → 胜率 1
		wm.call("_board_enemy", f)
	var ships: Array = Flt.get("ships")
	var names: Array = []
	for i in range(1, ships.size()):
		names.append(str(ships[i].get("name", "")))
	var d: Dictionary = got[0][1] if got.size() == 1 else {}
	_check(got.size() == 1 and got[0][0] == "win" and bool(d.get("boarded", false)),
		"全靠接舷夺下末艘：当帧带 boarded 出战（得 %s）" % [got])
	_check(int(d.get("boarded_n", 0)) == foes.size() and int(d.get("enemies", 0)) == foes.size(),
		"战果带夺船艘数 %s / 敌船 %s（刷 %d 艘）" % [d.get("boarded_n"), d.get("enemies"), foes.size()])
	_check(absf(float(d.get("player_damage", -1.0)) - 40.0) < 0.5, "战损只算开战在场的船：旗舰掉 40 记 40（得 %s）" % d.get("player_damage"))
	var want_names: Array = []
	for k in range(1, foes.size() + 1):
		want_names.append("快船・" + GM.cn_num(k))
	_check(names == want_names and str(ships[ships.size() - 1].get("type", "")) == "pirate_boat",
		"夺来的快船按序号起名、type 不动（%s）" % [names])
	var notice: Label = wm.get("_notice")
	var last_name: String = want_names[-1] if not want_names.is_empty() else "快船・一"
	_check(notice != null and notice.text.find(last_name) >= 0, "headless 题签起不来：浮字兜底写夺来的船名「%s」（%s）" % [last_name, notice.text if notice != null else "无浮字"])
	var took_crew := 0
	for i in range(1, ships.size()):
		took_crew += int(ships[i].get("crew", 0))
	var sd: int = Flt.supply_days()
	var win_note: String = FX.sea_win_note(300, int(d.get("player_damage", 0.0)), "", "pirate", FX.sea_win_taken(d, sd))
	var want_clause := "夺来%s船，添水手%s，" % [FX.cn_count(foes.size(), true), FX.cn_count(took_crew)]
	_check(win_note.begins_with("接舷既定。") and win_note.find("已退") < 0 and win_note.find(want_clause) >= 0
		and win_note.find(FX.cn_count(sd) + "日") >= 0 and win_note.find("船体受损 40") >= 0,
		"尽数夺下的注记：接舷既定开头、不说已退、交代「%s」与水粮 %d 日（得「%s」）" % [want_clause, sd, win_note])
	_check(FX.sea_win_note(100, 10, "").begins_with("海盗已退。") and FX.sea_win_note(100, 10, "", "yuan_patrol").begins_with("哨船退去。"),
		"没夺船的注记：海寇「海盗已退」、元军哨船「哨船退去」")
	GM.pending_battle = {}
	# 三、元军哨船：先击沉一艘，再夺两艘 → 接舷既定＋哨船退去；夺来的叫「元哨船・一」，type 仍是海鹘
	Flt.set("ships", [])
	Flt.call("add_ship", "fu_ship_medium", "")
	got.clear()
	var wm2 := _crew_battle(patrol, "yuan_patrol", got)
	var foes2 := _crew_foes(wm2)
	if not foes2.is_empty():
		foes2[0].call("take_damage", 99999.0)
		for i in range(1, foes2.size()):
			foes2[i].set("crew", 0)
			wm2.call("_board_enemy", foes2[i])
	var d2: Dictionary = got[0][1] if got.size() == 1 else {}
	var ships2: Array = Flt.get("ships")
	var p_note: String = FX.sea_win_note(300, 0, "", "yuan_patrol", FX.sea_win_taken(d2, Flt.supply_days()))
	_check(bool(d2.get("boarded", false)) and p_note.begins_with("接舷既定。哨船退去。夺来" + FX.cn_count(foes2.size() - 1, true) + "船") and p_note.find("海盗") < 0,
		"元军哨船沉一夺二：注记「接舷既定。哨船退去。夺来…」，不叫海盗（得「%s」）" % p_note)
	_check(ships2.size() >= 2 and str(ships2[1].get("name", "")) == str(patrol.get("prize_name", "")) + "・一" and str(ships2[1].get("type", "")) == "sea_falcon",
		"夺来的元军哨船叫「%s・一」、type 仍是 sea_falcon（得 %s / %s）" % [patrol.get("prize_name", ""), ships2[1].get("name", "") if ships2.size() >= 2 else "无", ships2[1].get("type", "") if ships2.size() >= 2 else "无"])
	GM.pending_battle = {}
	# 四、发炮的船已释放：炮弹命中照常扣伤、爆炸、自删，不报 SCRIPT ERROR（修前报错中断，炮弹留在场上）
	var tgt: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	root.add_child(tgt)
	tgt.set("hull_hp", 999.0)
	var cb: Node = (load("res://scenes/Cannonball.tscn") as PackedScene).instantiate()
	root.add_child(cb)
	var dead := Node2D.new()
	cb.set("shooter", dead)
	dead.free()
	cb.call("_on_body_entered", tgt)
	_check(cb.is_queued_for_deletion() and float(tgt.get("hull_hp")) < 999.0, "发炮船已释放：炮弹命中照常扣伤并自删")
	tgt.queue_free()
	# 五、海战粒子都挂柔点贴图（无贴图的 CPUParticles2D 画成硬边方块）
	var bare: Array = []
	for path in ["res://scenes/ImpactExplosion.tscn", "res://scenes/WaterSplash.tscn", "res://scenes/PirateShip.tscn", "res://scenes/Ship.tscn"]:
		var inst: Node = (load(path) as PackedScene).instantiate()
		for p in _crew_particles(inst):
			if (p as CPUParticles2D).texture == null and p.name != "SplinterParticles":
				bare.append("%s:%s" % [path.get_file(), p.name])
		inst.free()
	var smoke: CPUParticles2D = FX._spawn_ember_smoke(root, Vector2.ZERO)
	if smoke == null or smoke.texture == null:
		bare.append("CombatFx._spawn_ember_smoke")
	_check(bare.is_empty(), "海战粒子（爆炸、水花、尾迹、焦烟）都挂贴图（缺：%s）" % [bare])
	# 六、【辞船】放行、上蜜色墨；船籍簿职事栏留一行淡字；船队明细一艘两行、名同型只写一次
	var kept := UiTheme.plain_log("【辞船】林华把缆绳盘好，辞了船，说要去兴化投军。")
	_check(kept.begins_with("[color=#%s]" % UiTheme.hex(UiTheme.HONEY)) and kept.find("【辞船】林华") >= 0,
		"plain_log 放行【辞船】并上蜜色墨（得「%s」）" % kept)
	GS.from_dict({})
	Crw.from_dict({})
	GS.chapter = 2
	GS.money = 100000
	Cal.from_dict({"year": 1276, "month": 8, "day": 20})
	Crw.hire("lin_hua")
	_advance_to(1276, 10)
	var gone: PackedStringArray = Crw.departed_lines()
	_check(gone.size() == 1 and gone[0] == "舵工　林华已于景炎元年十月辞船", "林华辞船记入职事栏淡字（%s）" % [gone])
	var rt: Dictionary = Crw.to_dict()
	Crw.from_dict({})
	Crw.from_dict(rt)
	_check(Crw.departed_lines() == gone, "辞船记录入存档、读回不丢")
	Flt.set("ships", [])
	Flt.call("add_ship", "fu_ship_medium", "")
	Flt.call("add_ship", "pirate_boat", "快船・一")
	main.update_status_panel()
	var sl: RichTextLabel = main.get("status_label")
	var ledger := sl.get_parsed_text().replace("⁠", "").replace(" ", " ") if sl != null else ""
	var rows := ledger.split("\n")
	var row_i := -1
	for i in rows.size():
		if rows[i].begins_with("　快船・一　快船　"):
			row_i = i
	_check(ledger.find("舵工　林华已于景炎元年十月辞船") >= 0, "船籍簿职事栏有「舵工　林华已于景炎元年十月辞船」")
	_check(ledger.find("福船（中）　福船（中）") < 0 and ledger.find("　福船（中）　0 / 800 料") >= 0, "船名与船型相同只写一次（福船（中））")
	_check(row_i >= 0 and rows[row_i].ends_with("料") and row_i + 1 < rows.size() and rows[row_i + 1].begins_with("　　帆") and rows[row_i + 1].find("水手") >= 0,
		"船队明细一艘两行：「快船・一　快船　…料」／「　　帆…水手…」（%s）" % [rows.slice(maxi(row_i, 0), maxi(row_i, 0) + 2)])
	# 收拾：船队、职事、战况复原，免得污染后面的检查
	Flt.set("ships", saved_ships)
	Flt.water = saved_water
	Flt.food = saved_food
	Flt.morale = saved_morale
	GS.from_dict({})
	Crw.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})


## 起一场 WorldMap 海战（pending_battle 照 SeaChart._on_fight_* 的格式），battle_finished 记进 got
func _crew_battle(entry: Dictionary, event: String, got: Array) -> Node:
	GM.pending_battle = {"battle": true, "power": 300.0, "player_power": 400.0, "enemy": [entry.duplicate()],
		"sea_name": "泉州外海", "source": {"scene": "SeaChart", "event": event}}
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	wm.connect("battle_finished", func(o: String, d: Dictionary) -> void: got.append([o, d]))
	return wm


func _crew_foes(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _crew_particles(n: Node) -> Array:
	var out: Array = []
	if n is CPUParticles2D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_crew_particles(c))
	return out
