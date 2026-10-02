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
	# 人物志「已识」（lane fx6）：酒馆里看过画像、没雇的职事蔡七星，守城页当面见过的林华（没雇过他）——都随存档
	var Art = load("res://scripts/ui/CharacterArt.gd")
	var cai: Dictionary = GM.get_character("cai_qixing")
	var wu: Dictionary = GM.get_character("wu_zhen")
	Art.note_met("cai_qixing")
	Art.note_met("lin_hua")
	_check(not cai.is_empty() and not wu.is_empty() and Art.crew_id_of(cai) != "" and not Art.ever_hired(Art.crew_id_of(cai)),
		"蔡七星是职事、此档没雇过（已识只能靠见过）")
	var troops_before: int = GS.siege_get("troops")
	_check(SL.save_game(9, "xinghua"), "守城中途可存档")
	_check(SL.save_label(9).find("终") < 0, "未终局的档不带终局标记")
	# 打乱现场：另一局里见过吴真、没见过蔡七星
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	Art.note_met("wu_zhen")
	_check(not Art.is_known(cai) and Art.is_known(wu), "打乱现场：蔡七星未识、吴真已识")
	_check(SL.load_game(9), "读回守城档")
	_check(Art.is_known(cai) and GS.has_met("lin_hua") and not ("lin_hua" in GS.crew_history),
		"读档复原人物志已识：酒馆见过没雇的蔡七星、守城页见过没雇过的林华（met_ids %s）" % [GS.met_ids])
	_check(not Art.is_known(wu) and not GS.has_met("wu_zhen"), "读档后不串上一局的「见过」：吴真回到未识")
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
	_process_c6_init_hook()
	# 抵港路由一节要实例化 Main，@onready 节点须等树 ready——留到首帧 _process 再跑，那里再收尾


## 首帧：树与 autoload 都已 ready，才能实例化 Main 并让其 @onready 节点就位
func _process(_delta: float) -> bool:
	if not _route_pending:
		return false
	_route_pending = false
	_route_check()
	_script_error_check()
	print("STORY_CHECK TOTAL asserts run=", GateReport._checks.size(), "；lane w20-c6 补白新增 c6_asserts=", _c6_added)
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
	# 月份从战况表推，不写死：起股那年、首守城破当月（那是陈文龙的城）、再陷前一月「陈瓒还活着」；再陷当月、次年、1285 已死。
	# 09-28 起船股另只在兴化第一段 besieged 起点之前出（围城起陈瓒在城里募兵守城）：活着但已过起点的几格期望「没有」（细则见 _v0928_hanjiang_check）
	var zan_cases: Array = [[main.CHEN_ZAN_FROM_YEAR, 6, true], [1285, 5, false]]
	var zan_stake_until := "9999-99"
	var zan_war_keys: Array = GM.get_port_by_id("xinghua").get("war", {}).keys()
	zan_war_keys.sort()
	for zk in zan_war_keys:
		if str(GM.get_port_by_id("xinghua")["war"][zk]) == "besieged":
			zan_stake_until = str(zk)
			break
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
		var zan_want: bool = bool(zc[2]) and ("%04d-%02d" % [zc[0], zc[1]]) < zan_stake_until
		_check(zan_btn == zan_want,
			"玉湖陈宅 %d-%02d%s「陈瓒愿入船股」（再陷 %s，陈瓒%s；船股只到围城起点 %s 前）" % [zc[0], zc[1], "有" if zan_want else "没有", zan_falls[1] if zan_falls.size() >= 2 else "?", "在" if zc[2] else "已死", zan_stake_until])
		# 死期边界单独钉住：船股按钮已按围城起点收口，再陷前一月活着、再陷当月已死这条只剩 _chen_zan_alive 管（09-29 复核）
		_check(main._chen_zan_alive() == bool(zc[2]),
			"陈瓒 %d-%02d %s（再陷 %s）" % [zc[0], zc[1], "还活着" if zc[2] else "已死", zan_falls[1] if zan_falls.size() >= 2 else "?"])
	_lin_hua_check(main)
	_v0928_siege_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	# 旅店路由：city_inn 必须落到 {港}_inn，不能是 city_inn
	# 先记账：泉州链五针账上全演过（w20-c2 拍板 E-10 后抵泉州的旧行为不再回来，
	# 这两个旧断言钉的「开局港页」口径须从「新档」换成「泉州链已演完的同月档」）
	GS.loaded_with_beats = true
	for _m in ["monk", "merchant", "dock", "prepare", "return_quanzhou"]:
		GS.beat_mark(_m)
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
	_v0928_visual_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_v0928_crew_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_v0928_hanjiang_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_fx7_notice_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_g9_log_fold_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_g13_chart_zoom_check()
	_w20b9_spawn_bbox_check()
	_b1_worldmap_coast_check()
	_w20c2_port_beats_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	await _w20a4_notice_fold_height_check(main)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)
	_a5_sea_here_check()
	main.queue_free()
	_process_c6_main_hook(main)


## lane fx7（todo「小毛病」两条）：
## 一、月初【战况】里玩家当前所在港页那条排最上（状态条那一格也是它），其余照 ports 原序——
##     1277-11-01 站兴化城页，最上是「兴化城破」，不是 ports 里排在后面的海口那条；站海口页反过来。
## 二、月初通告多到会把候日那句顶出 LOG_KEEP 时，整串折成一行；候日句留在记事栏，折起的原文一则不少，点开就地看全。
func _fx7_notice_check(main: Node) -> void:
	var city_line := "兴化城破。元兵入城，巷战终日。市舶司换了旗，抽解加倍，缉私加严。"
	var harbor_line := "兴化海口也换了旗，抽解加倍，缉私加严。"
	var wait_line := "在岸上又候了一日，门又换了几处。"
	for here in ["xinghua", "xinghua_harbor"]:
		_fx7_wait_into(main, here, 1277, 11, true)
		var wl: Array = main._log_lines
		var top_want: String = city_line if here == "xinghua" else harbor_line
		var next_want: String = harbor_line if here == "xinghua" else city_line
		_check(wl.size() == 3 and str(wl[0]) == top_want and str(wl[1]) == next_want and str(wl[2]) == wait_line,
			"1277-11-01 站 %s 页候日跨月：记事栏最上是本港那条战况、另一条在下、候日句垫底（%s）" % [here, wl])
		var strip: String = main._status_note.text if main._status_note != null else ""
		_check(strip == top_want and main._latest_log() == top_want,
			"1277-11-01 站 %s 页：状态条那一格是本港战况「%s」（实得「%s」）" % [here, top_want, strip])
		_check(main._log_folds.is_empty(), "通告两则不折（%s）" % [main._log_folds.keys()])
	# 与所在港无关的照 ports 原序：站泉州 1276-11，四条战况按兴化 / 兴化海口 / 福州 / 广州发（记事栏新的在上，故倒着排）
	_fx7_wait_into(main, "quanzhou", 1276, 11, true)
	var war_q := _fx7_war_order(main._log_lines)
	_check(war_q == ["广州", "福州", "兴化海口", "兴化"],
		"站泉州 1276-11：战况照 ports 原序（记事栏自上而下 %s）" % [war_q])
	# 站福州：福州那条挪到最上，其余三条相对次序不变
	_fx7_wait_into(main, "fuzhou", 1276, 11, true)
	var war_f := _fx7_war_order(main._log_lines)
	_check(war_f == ["福州", "广州", "兴化海口", "兴化"],
		"站福州 1276-11：福州那条最上，其余照原序（记事栏自上而下 %s）" % [war_f])
	# 二、通告一连二十余则（新闻一条未读的局面，与 v0928 候日段同）：候日句仍在、折起的一则不少
	_fx7_wait_into(main, "quanzhou", 1276, 11, false)
	var bl: Array = main._log_lines
	var fresh: Array = _notices.slice(int(main.get_meta(&"fx7_n0", 0)))
	var keep: int = main.LOG_KEEP
	_check(fresh.size() >= keep, "1276-11 月初通告够多、会顶出 LOG_KEEP（%d 则 / LOG_KEEP %d）" % [fresh.size(), keep])
	_check(bl.size() == 2 and str(bl[1]) == wait_line and main._log_folds.has(str(bl[0])),
		"1276-11 候一日：月初通告折成一行在上、候日句仍在记事栏（%s）" % [bl])
	var fold: Dictionary = main._log_folds.get(str(bl[0]) if not bl.is_empty() else "", {})
	var got: Array = fold.get("lines", [])
	var want: Array = []
	for t in fresh:
		want.push_front(UiTheme.plain_log(str(t)))
	_check(got == want, "折起的原文与本批通告逐则相同、新的在前（折 %d 则 / 发 %d 则）" % [got.size(), want.size()])
	_check(not bl.is_empty() and str(bl[0]) == "冬月初一，月初通告一连 %d 则" % want.size(),
		"折起那一行写「冬月初一，月初通告一连 %d 则」（「%s」）" % [want.size(), bl[0] if not bl.is_empty() else ""])
	_check(not want.is_empty() and main._latest_log() == str(want[0]).strip_edges(),
		"折起后状态条那一格仍是最上那则通告（「%s」）" % [main._latest_log()])
	var ml: RichTextLabel = main.message_label
	var shut_text := ml.text
	_check(shut_text.find("[url=fold:0]") >= 0 and shut_text.find("点开") >= 0 and shut_text.find(wait_line) >= 0 and (want.is_empty() or shut_text.find(str(want[-1])) < 0),
		"记事栏收着时只一行可点的「点开」，候日句在，原文不铺开（%s）" % [shut_text.left(80)])
	main._on_log_meta("fold:0")
	var open_text := ml.text
	var missing := 0
	for t in want:
		if open_text.find(str(t)) < 0:
			missing += 1
	_check(main._log_fold_open == str(bl[0]) and missing == 0 and open_text.find("收起") >= 0 and open_text.find(wait_line) >= 0,
		"点开折起那一行：本批 %d 则全铺在记事栏里（缺 %d 则），候日句仍在" % [want.size(), missing])
	main._on_log_meta("fold:0")
	_check(main._log_fold_open == "" and ml.text == shut_text, "再点一下收起，记事栏回到一行")
	# 折起那一行照常随 LOG_KEEP 滚出去，折叠一并清掉
	for i in keep:
		main.log_msg("第 %d 句。" % i)
	_check(main._log_folds.is_empty() and main._log_lines.size() == keep, "折起那一行滚出 LOG_KEEP 后折叠清掉（剩 %d 折）" % main._log_folds.size())


## lane w19-g9：记事栏折叠抽成公共件 scripts/core/LogFold.gd，港页船籍簿与海图船况札记同一份——
## 一、海上跨进 1276-11（通告一连二十余则）：札记里收成一行，起锚 / 启程句仍在，折起的原文一则不少、点开就地看全；
##     「所在位置」那港的战况排最上（行程过半船标贴着福州 → 福州那条；未过半贴着泉州 → 不挑，照 ports 原序广州那条在上）；
## 二、港页跳两年（一次几十则、跨十来个月）：仍折成一行，点开先列各月一行（各月则数与原文逐月对得上），再点哪月铺哪月；
## 三、两边都走 LogFold，不各写一份。
func _g9_log_fold_check(main: Node) -> void:
	var Flt: Node = root.get_node("Fleet")
	var Eco: Node = root.get_node("Economy")
	var fz_line := "福州已降元。市舶司换了旗，抽解加倍，缉私加严。"
	var gz_line := "广州被围。城中米价腾贵，牙行闭门。"
	for near_dest in [true, false]:
		GS.from_dict({})
		GS.set_flag("renamed_wenlong")
		GS.identity = "scholar"
		GS.money = 20000
		GS.last_port = "quanzhou"
		Cal.from_dict({"year": 1276, "month": 10, "day": 30})
		var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
		root.add_child(sc)
		sc.set("selected_port", "fuzhou")
		sc.set("total_li", 400.0)
		sc.set("remaining_li", 120.0 if near_dest else 320.0)
		sc.set("days_elapsed", 3)
		sc.set("sailing", true)
		Flt.at_sea = true
		sc.call("_refresh_status")
		var here_want := "fuzhou" if near_dest else "quanzhou"
		_check(str(Eco.get("sea_here")) == here_want,
			"海上「所在位置」按船标最近港取：行程%s船标贴着 %s（实得 %s）" % ["过半" if near_dest else "未过半", here_want, Eco.get("sea_here")])
		sc.call("_log", "启程往 福州，航程 400 里。")
		var n0 := _notices.size()
		GM.advance_days(1)
		var fresh: Array = _notices.slice(n0)
		var want: Array = []
		for t in fresh:
			want.push_front(UiTheme.plain_log(str(t)))
		var sl: PackedStringArray = sc.get("_log_lines")
		var folds: Dictionary = sc.get("_log_folds")
		var fold: Dictionary = folds.get(sl[0] if not sl.is_empty() else "", {})
		_check(fresh.size() >= LogFold.FOLD_AT and sl.size() == 3 and not fold.is_empty()
			and str(sl[1]) == "启程往 福州，航程 400 里。" and str(sl[2]).begins_with("自 泉州 起锚。"),
			"海上跨进 1276-11：%d 则通告在札记里收成一行，启程 / 起锚两句仍在（%s）" % [fresh.size(), sl])
		_check(fold.get("lines", []) == want and str(sl[0] if not sl.is_empty() else "") == "冬月初一，月初通告一连 %d 则" % want.size(),
			"海上折起的原文与本批通告逐则相同、新的在前，行字写「冬月初一，月初通告一连 %d 则」（折 %d 则，「%s」）" % [want.size(), (fold.get("lines", []) as Array).size(), sl[0] if not sl.is_empty() else ""])
		var top_want := fz_line if near_dest else gz_line
		_check(not want.is_empty() and str(want[0]) == top_want and str(sc.get("_latest_note")) == top_want,
			"海上%s：折里最上、顶匾那一格是「%s」（折首「%s」，匾「%s」）" % ["近福州" if near_dest else "近泉州", top_want, want[0] if not want.is_empty() else "", sc.get("_latest_note")])
		if near_dest:
			var ll: RichTextLabel = sc.get("log_label")
			var shut := ll.text
			_check(shut.find("[url=fold:0]") >= 0 and shut.find("点开") >= 0 and (want.is_empty() or shut.find(str(want[-1])) < 0),
				"札记收着时只一行可点的「点开」，原文不铺开（%s）" % shut.left(60))
			sc.call("_on_log_meta", "fold:0")
			var opened := ll.text
			var missing := 0
			for t in want:
				if opened.find(str(t)) < 0:
					missing += 1
			_check(sc.get("_log_fold_open") == str(sl[0]) and missing == 0 and opened.find("收起") >= 0 and opened.find("启程往 福州") >= 0,
				"札记点开：本批 %d 则全铺开（缺 %d 则），启程句仍在" % [want.size(), missing])
			sc.call("_on_log_meta", "fold:0")
			_check(sc.get("_log_fold_open") == "" and ll.text == shut, "札记再点一下收起，回到一行")
			sc.call("_log", "第 4 日・风顺。")
			var sl2: PackedStringArray = sc.get("_log_lines")
			_check(sl2.size() == 4 and str(sl2[0]) == "第 4 日・风顺。" and folds.has(str(sl2[1])),
				"札记里折起那一行随后照常压到下面、不再收新记事（%s）" % [sl2])
		root.remove_child(sc)
		sc.free()
		_check(str(Eco.get("sea_here")) == "", "海图退场后 Economy.sea_here 清空（实得「%s」）" % Eco.get("sea_here"))
		Flt.at_sea = false
	# 二、港页跳两年：自 1275 正月起，泉州海商线
	GS.from_dict({})
	GS.identity = "merchant"
	GS.money = 5000
	GS.last_port = "quanzhou"
	Cal.from_dict({"year": 1275, "month": 1, "day": 1})
	main.load_scene("quanzhou")
	main._log_lines.clear()
	main._log_folds.clear()
	main._log_fold_open = ""
	main.log_msg("升了一章。")
	var by_month: Dictionary = {}
	var order: Array = []
	var dates: Dictionary = {}
	var tap := func(t: String) -> void:
		var ym := "%04d-%02d" % [int(Cal.year), int(Cal.month)]
		if not by_month.has(ym):
			by_month[ym] = []
			order.push_front(ym)
			dates[ym] = str(Cal.get_date_string())
		(by_month[ym] as Array).push_front(UiTheme.plain_log(t))
	GM.monthly_notice.connect(tap)
	var from_d := ""
	var n1 := _notices.size()
	GM.skip_years(2)
	GM.monthly_notice.disconnect(tap)
	var total: int = _notices.size() - n1
	var ml: PackedStringArray = main._log_lines
	var mfold: Dictionary = main._log_folds.get(ml[0] if not ml.is_empty() else "", {})
	var groups: Array = mfold.get("groups", [])
	_check(total >= LogFold.FOLD_AT and order.size() >= 2 and ml.size() == 2 and str(ml[1]) == "升了一章。" and not mfold.is_empty(),
		"跳两年：%d 则通告跨 %d 个月，仍折成一行，下面那句还在（%s）" % [total, order.size(), ml])
	var got_order: Array = []
	var bad_month := 0
	for g in groups:
		got_order.append(str(g["ym"]))
		if g["lines"] != by_month.get(str(g["ym"]), []) or str(g["date"]) != str(dates.get(str(g["ym"]), "")):
			bad_month += 1
	_check(got_order == order and bad_month == 0 and (mfold.get("lines", []) as Array).size() == total,
		"跳两年按月分组：%d 组、新的月在前，各月原文与当月通告逐则相同（对不上 %d 组；组序 %s）" % [groups.size(), bad_month, got_order])
	if not order.is_empty():
		from_d = str(dates[order[-1]])
	var head_want := "自%s至于%s，通告一连 %d 则，凡 %d 月" % [from_d, Cal.get_date_string(), total, order.size()]
	_check(not ml.is_empty() and str(ml[0]) == head_want, "跳两年折起那一行写「%s」（「%s」）" % [head_want, ml[0] if not ml.is_empty() else ""])
	var lbl: RichTextLabel = main.message_label
	main._on_log_meta("fold:0")
	var open_t := lbl.text
	var heads := 0
	var leaked := 0
	for ym in order:
		if open_t.find("[url=fold:0:%s]" % ym) >= 0 and open_t.find("%s，通告 %d 则（点开）" % [dates[ym], (by_month[ym] as Array).size()]) >= 0:
			heads += 1
		for t in by_month[ym]:
			if open_t.find("　　" + str(t)) >= 0:
				leaked += 1
	_check(heads == order.size() and leaked == 0 and open_t.find("升了一章。") >= 0,
		"跳两年点开：先列 %d 月各一行（列出 %d 行），原文不整串铺开（漏出 %d 则）" % [order.size(), heads, leaked])
	var pick: String = order[order.size() / 2] if not order.is_empty() else ""
	main._on_log_meta("fold:0:" + pick)
	var month_t := lbl.text
	var shown := 0
	var others := 0
	for ym in order:
		for t in by_month[ym]:
			if month_t.find("　　" + str(t)) >= 0:
				if ym == pick:
					shown += 1
				else:
					others += 1
	_check(shown == (by_month.get(pick, []) as Array).size() and others == 0 and month_t.find("%s，通告 %d 则（收起）" % [dates.get(pick, ""), shown]) >= 0,
		"跳两年再点 %s 那一月：只铺这一月 %d 则（铺出 %d，别月漏出 %d）" % [pick, (by_month.get(pick, []) as Array).size(), shown, others])
	main._on_log_meta("fold:0:" + pick)
	main._on_log_meta("fold:0")
	_check(main._log_fold_open == "" and lbl.text.find("fold:0:") < 0, "跳两年那一折收起后各月行也收起")
	# 三、两边同一份：Main / SeaChart 都经 LogFold 记通告、画记事，不各写一份折叠
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	var sea_src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	var ledger_src := FileAccess.get_file_as_string("res://scripts/ui/LedgerPage.gd")
	_check(main_src.find("LogFold.push_notice(") >= 0 and sea_src.find("LogFold.push_notice(") >= 0
		and ledger_src.find("LogFold.render(") >= 0 and sea_src.find("LogFold.render(") >= 0
		and main_src.find("func _fold_head") < 0 and sea_src.find("func _fold_head") < 0 and sea_src.find("\"groups\"") < 0,
		"港页记事栏与海图札记同走 LogFold（push_notice / render），不各写一份折叠")
	main._log_lines.clear()
	main._log_folds.clear()
	main._log_fold_open = ""


## 海商线站 port_id 港页，在 year-month 的前一日候一日跨月；seen_old：之前的新闻都当已读（只剩当月战况）
func _fx7_wait_into(main: Node, port_id: String, year: int, month: int, seen_old: bool) -> void:
	GS.from_dict({})
	GS.identity = "merchant"
	GS.money = 5000
	GS.last_port = port_id
	var ym := "%04d-%02d" % [year, month]
	if seen_old:
		for n in GM.news_data.get("news", []):
			if str(n.get("date", "9999-99")) < ym:
				GS.mark_news_seen(str(n.get("id", "")))
	var prev: Dictionary = {"year": year, "month": month - 1, "day": Cal.DAYS_PER_MONTH} if month > 1 else {"year": year - 1, "month": Cal.MONTHS_PER_YEAR, "day": Cal.DAYS_PER_MONTH}
	Cal.from_dict(prev)
	main.load_scene(port_id)
	main._log_lines.clear()
	main._log_folds.clear()
	main._log_fold_open = ""
	main.set_meta(&"fx7_n0", _notices.size())
	main._on_shore_wait()


## 记事栏里的【战况】行按自上而下取港名（只认 Economy 的「X被围 / X已降元」与海口 / 城破两条自定句）
func _fx7_war_order(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		var t := str(l)
		if t.begins_with("元兵围了兴化城") or t.begins_with("兴化海口"):
			out.append("兴化海口")
		elif t.begins_with("兴化城破") or t.begins_with("兴化被围"):
			out.append("兴化")
		elif t.find("被围。") > 0 or t.find("已降元。") > 0:
			out.append(t.substr(0, maxi(t.find("被围。"), t.find("已降元。"))))
	return out


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
	# 先记账：泉州链五针账上全演过（w20-c2 拍板 E-10 后抵泉州的旧行为不再回来，
	# 这两个旧断言钉的「开局港页」口径须从「新档」换成「泉州链已演完的同月档」）
	GS.loaded_with_beats = true
	for _m in ["monk", "merchant", "dock", "prepare", "return_quanzhou"]:
		GS.beat_mark(_m)
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
	# 09-30 合并：本地线战果不带 boarded_n / enemies 两个键（那是 origin 那条注记函数的输入）；
	# 夺船艘数改按船队名册对账——刷出的敌船是不是都进了名册。
	_check(bool(d.get("boarded", false)) and names.size() == foes.size(),
		"夺船全进船队名册：%d 艘＝刷出 %d 艘（战果记 boarded=%s）" % [names.size(), foes.size(), d.get("boarded")])
	_check(absf(float(d.get("player_damage", -1.0)) - 40.0) < 0.5, "战损只算开战在场的船：旗舰掉 40 记 40（得 %s）" % d.get("player_damage"))
	# 09-30 合并：本地线夺来的船按敌船原名入列（快船），未按序号起名——序号命名是 origin 那条的做法，未随合并采用。
	var want_names: Array = []
	for __i in foes.size():
		want_names.append(str((foes[__i] as Object).get("ship_name")))
	_check(names == want_names and str(ships[ships.size() - 1].get("type", "")) == "pirate_boat",
		"夺来的快船用敌船原名入列、type 不动（%s）" % [names])
	# 夺船入册的账目口径（09-30 补回）：WorldMap._board_enemy 走 Fleet.add_ship(type_id, enemy.ship_name)，
	# add_ship 是纯 append（scripts/core/Fleet.gd:98），两艘同名在册即占两格、船籍簿各开一行（LedgerPage.gd 船队明细按册逐船画，不并名）。
	var dup_count := 0
	for sn in ships:
		if str(sn.get("name", "")) == "快船":
			dup_count += 1
	_check(foes.size() >= 2 and ships.size() == 1 + foes.size() and dup_count == foes.size(),
		"同名夺船不并格：两艘「快船」各占一格（名册 %d 格，其中 %d 格叫「快船」）" % [ships.size(), dup_count])
	main.update_status_panel()
	var sl0: RichTextLabel = main.get("status_label")
	var ledger0 := sl0.get_parsed_text().replace("⁠", "").replace(" ", " ") if sl0 != null else ""
	var dup_rows := 0
	for r in ledger0.split("\n"):
		if r.begins_with("　快船・") and r.contains("　快船　"):  # lane fx2：存名仍「快船」，上屏同名按次序加「・甲」「・乙」
			dup_rows += 1
	_check(dup_rows == foes.size() and ledger0.find("　快船・甲　快船　") >= 0 and ledger0.find("　快船・乙　快船　") >= 0,
		"同名夺船不并行：船籍簿逐船各开一行、上屏分得清（%d 行「快船・甲 / 乙　快船」，不并成一行）" % dup_rows)
	var notice: Label = wm.get("_notice")
	var last_name: String = want_names[-1] if not want_names.is_empty() else "快船"
	_check(notice != null and notice.text.find(last_name) >= 0, "headless 题签起不来：浮字兜底写夺来的船名「%s」（%s）" % [last_name, notice.text if notice != null else "无浮字"])
	GM.pending_battle = {}
	# 战果注记三式＋前缀＋顶匾截断（09-30 补回，按本地线行为成句断言）：本地线三式分开——
	# 沉一夺二按 win_kind=""/全赏走「海盗已退。」（SeaChart.gd:1491 起，fled 句仅「一艘没沉没没夺、只见遁走」时才用）；
	# 交代在句首、账目在句尾（「获财货 N 钱。船体受损 N。」），promo 接在句末。
	# 「接舷既定。」前缀是 SeaChart._on_battle_result:1497 对 boarded 胜局加盖的，实测走一遍真结算再对；
	# 海图顶匾第二行 28 字截断在 SeaChart._refresh_strip:730（_log 把注记存进 _latest_note，_refresh_strip 画匾）。
	# origin 那条的合并句式（夺来 N 船、添水手…、水粮 N 日）与 28 字截断断言属另一套文案，未随合并采用——这里补的是本地线自己的口径。
	for trio in [["沉一夺二／全炮击", FX.sea_win_note(300, 40, ""), "海盗已退。获财货 300 钱。船体受损 40。"],
		["受降", FX.sea_surrender_note(200, 30, ""), "敌船降幡，货与人一并收押。获财货 200 钱。船体受损 30。"],
		["全遁", FX.sea_fled_note(200, 30, ""), "敌船转篷遁走，只拾得些漂散的货。获财货 200 钱。船体受损 30。"]]:
		var tag: String = trio[0]
		var note: String = trio[1]
		var want: String = trio[2]
		_check(note == want and note.ends_with("。")
			and note.find("获财货") > note.find("。", 0) and note.find("获财货") < note.find("船体受损"),
			"战果注记（%s）：交代在句首、账目在句尾成句（得「%s」）" % [tag, note])
	_check(FX.sea_win_note(300, 40, "案册改题「哨官」。").ends_with("船体受损 40。案册改题「哨官」。"),
		"战果注记 promo 接在账目句末（得「%s」）" % FX.sea_win_note(300, 40, "案册改题「哨官」。"))
	# 走真结算：wm2 甫以 boarded 收战，直接喂给 SeaChart._on_battle_result，读日志与顶匾。
	# （sailing 是 instance 字段，被前面探针拉起过就一直 true——顶匾第二行会压航行行，这里清零再测。）
	var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	sc.set("sailing", false)
	sc.set("remaining_li", 50.0)  # 挡 _after_combat 的 _arrive()「历 0 日，抵 。」压日志首行
	if sc.get("log_label") != null:
		sc.get("log_label").text = ""  # 冲掉前面探针日志 _log 过的到港行
	sc.call("_refresh_strip")
	var spoil0: int = GS.money
	sc.call("_on_battle_result", "win", {"boarded": true, "player_damage": 40.0})
	var spoil_now: int = GS.money - spoil0
	var log0: String = sc.get("log_label").get_parsed_text()
	var wd := "海盗已退。获财货 %d 钱。船体受损 40。" % spoil_now
	_check(spoil_now >= 150 and spoil_now <= 600 and log0.find("接舷既定。" + wd) >= 0,
		"接舷夺船战果注记（boarded）：日志首行「接舷既定。」＋全赏注记（spoil %d，得首行「%s」）" % [spoil_now, log0.get_slice("\n", 0)])
	var strip0: RichTextLabel = sc.get("_strip_line")
	var strip_note: String = strip0.get_parsed_text().get_slice("\n", 1).strip_edges() if strip0 != null else ""
	# 钱数是 randf_range(150,600)，位数不定——超不过 28 字时不截、超过时截 27 字＋…，两路都按 _refresh_strip:730 的式子现算
	var raw_note: String = "接舷既定。" + wd
	var expect_note := raw_note
	var cut := raw_note.length() > 28
	if cut:
		expect_note = raw_note.substr(0, 27) + "…"
	_check(strip_note == expect_note and (not cut or expect_note.ends_with("…")),
		"海图顶匾第二行照 _refresh_strip 28 字收：注记实长 %d 字，%s匾上得「%s」" % [
			raw_note.length(), "截 27 字＋…，" if cut else "未超不截，", strip_note])
	# 截断定式（不随钱数位走）：写一条定长 40 字注记，匾上恒收成 27 字＋…；再写一条 20 字短注记，匾上恒原样过
	sc.set("_latest_note", "定长四十字注记甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥一二三四五六七八九零零零零零")
	sc.call("_refresh_strip")
	var strip_long: String = sc.get("_strip_line").get_parsed_text().get_slice("\n", 1).strip_edges()
	sc.set("_latest_note", "短注记不过二十字上下可以直接过")
	sc.call("_refresh_strip")
	var strip_short: String = sc.get("_strip_line").get_parsed_text().get_slice("\n", 1).strip_edges()
	_check(strip_long.length() == 28 and strip_long.ends_with("…") and strip_short == "短注记不过二十字上下可以直接过",
		"顶匾第二行截断定式：长注记收成 27 字＋…（得 %d 字「%s」），短注记原样过（「%s」）" % [strip_long.length(), strip_long, strip_short])
	sc.get("log_label").text = ""
	sc.call("_on_battle_result", "win", {"boarded": true, "player_damage": 40.0, "fates": [{"fate": "struck", "type": "sea_falcon"}]})
	var log1: String = sc.get("log_label").get_parsed_text()
	_check(log1.find("接舷既定。敌船降幡，") == 0,
		"接舷且敌降战果注记：前缀盖在受降句上（得首行「%s」）" % log1.get_slice("\n", 0))
	root.remove_child(sc)
	sc.free()
	GM.pending_battle = {}
	_v0928_prize_flee_check(Flt, FX, pirate)
	_v0928_prize_sunk_check(Flt, FX, pirate)
	var sc_scr = load("res://scripts/SeaChart.gd")
	# 三、元军哨船：先击沉一艘，再夺两艘 → 接舷既定、不说退去、交代击沉一船；夺来的叫「元哨船・一」，type 仍是海鹘
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
	# 元军哨船沉一夺二（09-30 合并）：本地线战果注记只按下场分三式（退走／受降／遁走），
	# 「击沉几船、夺来几船」的合并交代由 origin 那条的注记函数写，未随合并采用；本地线夺来的船也按敌船原名入列
	# （未按序号起名）。故这里只断言结构：夺过船、艘数记对、夺来的 type 不动。
	# 09-30 合并：同 二——本地线战果不带 boarded_n，夺船艘数按船队名册对账（沉一艘、夺两艘）。
	var got2_names: Array = []
	for i2 in range(1, ships2.size()):
		got2_names.append(str(ships2[i2].get("name", "")))
	_check(bool(d2.get("boarded", false)) and got2_names.size() >= foes2.size() - 1,
		"元军哨船沉一夺二：战果记 boarded、夺来的船进名册（名册新船 %s / 刷 %d 艘）" % [got2_names, foes2.size()])
	_check(FX.sea_win_note(100, 10, "").begins_with("海盗已退。") and FX.sea_surrender_note(100, 10, "").begins_with("敌船降幡，")
		and FX.sea_fled_note(100, 10, "").begins_with("敌船转篷遁走，"),
		"退走／受降／遁走三式注记各写各句")
	_check(ships2.size() >= 2 and str(ships2[1].get("type", "")) == "sea_falcon",
		"夺来的元军哨船 type 仍是 sea_falcon（得 %s / 名 %s）" % [ships2[1].get("type", "") if ships2.size() >= 2 else "无", ships2[1].get("name", "") if ships2.size() >= 2 else "无"])
	# 沉一夺二的分账口径（09-30 补回，对 win_kind 静态函数）：下场明细有 boarded、sunk → 全赏走「海盗已退。」式；
	# 敌降（struck）→ 受降句；一艘没沉没夺只见遁走 → 赏半（spoil 区 [75,300]）走敌遁句；不明不白（无 fates）→ ""。
	_check(sc_scr.win_kind({"boarded": true, "player_damage": 0.0}) == ""
		and sc_scr.win_kind({"fates": [{"fate": "sunk"}, {"fate": "boarded"}]}) == ""
		and sc_scr.win_kind({"fates": [{"fate": "sunk"}]}) == ""
		and sc_scr.win_kind({"fates": [{"fate": "fled"}]}) == "fled"
		and sc_scr.win_kind({"fates": [{"fate": "struck"}]}) == "surrender",
		"胜局分账口径：沉一夺二／全炮击走退走句（kind 空串），只见遁走赏半，有受降走受降句")
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
	# 09-30 合并改按本地线入口：本地线 Cannonball 按船体椭圆扫掠自判（_process → _sweep → _strike），
	# 没有 origin 那条的 Area2D _on_body_entered。这里直接打本地线的命中入口，断言的事项不变。
	cb.call("_strike", tgt, tgt.global_position)
	_check(cb.is_queued_for_deletion() and float(tgt.get("hull_hp")) < 999.0, "发炮船已释放：炮弹命中照常扣伤并自删")
	tgt.queue_free()
	# 五、海战粒子都挂柔点贴图（无贴图的 CPUParticles2D 画成硬边方块）
	var bare: Array = []
	for path in ["res://scenes/ImpactExplosion.tscn", "res://scenes/WaterSplash.tscn", "res://scenes/PirateShip.tscn", "res://scenes/Ship.tscn"]:
		var inst: Node = (load(path) as PackedScene).instantiate()
		# 进树跑 _ready → Ship._polish_wake：艏波与木屑的贴图在那一刻才写上去（本地线的做法）
		root.add_child(inst)
		for p in _crew_particles(inst):
			var cp := p as CPUParticles2D
			# 本地线把 WakeParticles 交给 CombatFx.FxLook 隐藏、尾迹另画：隐藏的节点不吃贴图
			if not cp.visible:
				continue
			if cp.texture == null:
				bare.append("%s:%s" % [path.get_file(), cp.name])
		inst.free()
	# 09-30 合并：本地线 CombatFx 的烟走 _spawn_smoke（void，不留句柄），焦烟贴图由上面四个场景的粒子断言覆盖
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
	# 七、海战难度对账（09-30 按本地线 EnemyCaptainAI 重记基线重开）：开局小艍遇 PATROL_ENEMY，
	# CREW_FIRST_SEEDS 个固定种子各推 CREW_FIRST_SECS 秒，重演一致＋首轮 0 沉＋总沉数范围断言
	# （测法、门槛出处与实测分布均见 _v0928_crew_difficulty 头注）。
	_v0928_crew_difficulty(patrol)
	# 收拾：船队、职事、战况复原，免得污染后面的检查
	Flt.set("ships", saved_ships)
	Flt.water = saved_water
	Flt.food = saved_food
	Flt.morale = saved_morale
	GS.from_dict({})
	Crw.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})


## 二之二（lane fx3）：夺船后弃战脱身——修前 flee 收战 data 不带夺船账，SeaChart 注记只写「转舵抢上风头…」，
## 夺来的船其实已在名册、水粮也没转，注记只字不提。现在：WorldMap 按引用记本场入册的那几格，flee 收战并进
## data.prizes / data.stores_moved；SeaChart 在脱战句后接 CombatFx.sea_prize_note（交代在前、账目在后，同战果注记三式，
## 不加「接舷既定。」——弃战不是接舷定局）；顶匾第二行照 _refresh_strip 28 字截断定式收。
## 名册里先放一艘同名「快船」：凭船名认夺船会多记一艘，按引用认才对得上。
func _v0928_prize_flee_check(Flt: Node, FX, pirate: Dictionary) -> void:
	var ok_note := str(FX.sea_flee_ok_note())
	var run := func(flee_data: Dictionary) -> Array:
		GS.from_dict({})
		Flt.set("ships", [])
		Flt.call("add_ship", "fu_ship_medium", "")
		Flt.call("add_ship", "pirate_boat", "快船")
		for s0 in Flt.get("ships"):
			s0["crew"] = 20
		Flt.water = 300
		Flt.food = 300
		var got_f: Array = []
		var wmf := _crew_battle(pirate, "pirate", got_f)
		var foes_f := _crew_foes(wmf)
		var taken_name := ""
		if foes_f.size() >= 2:
			foes_f[0].set("crew", 0)
			taken_name = str((foes_f[0] as Object).get("ship_name"))
			wmf.call("_board_enemy", foes_f[0])
		var still := got_f.is_empty()
		var prize_ref: Variant = (Flt.get("ships") as Array)[-1] if (Flt.get("ships") as Array).size() == 3 else null
		# 按 B 弃战的同一出口（_unhandled_input 里 flee_ok 取 randf，这里定死成败免得两支随机）
		wmf.call("_battle_exit", "flee", flee_data)
		return [got_f, taken_name, still, prize_ref, foes_f.size()]
	# ① 甩脱：data 带夺船账，名册与水粮账对得上
	var r1: Array = run.call({"flee_ok": true})
	var got1: Array = r1[0]
	var d1: Dictionary = got1[0][1] if got1.size() == 1 else {}
	var prizes1: Array = d1.get("prizes", [])
	var ships1: Array = Flt.get("ships")
	_check(bool(r1[2]) and got1.size() == 1 and got1[0][0] == "flee" and int(r1[4]) >= 2,
		"夺一艘后弃战：夺船当时不收战，按弃战收战（得 %s）" % [got1])
	_check(prizes1.size() == 1 and str(prizes1[0].get("name", "")) == r1[1] and str(prizes1[0].get("type", "")) == "pirate_boat"
		and ships1.size() == 3 and r1[3] != null and is_same(ships1[2], r1[3]),
		"夺船后脱身：data.prizes 只记本场夺来的一艘（名册先有一艘同名「快船」不算进去），与名册末格同一格（prizes %s / 名册 %d 格）" % [prizes1, ships1.size()])
	var mv1: Dictionary = d1.get("stores_moved", {})
	_check(int(mv1.get("water", -1)) == 0 and int(mv1.get("food", -1)) == 0 and Flt.water == 300 and Flt.food == 300,
		"夺船后脱身：水粮账本场未动（stores_moved %s，水 %d 粮 %d）" % [mv1, Flt.water, Flt.food])
	var want_prize := "所夺「%s」一艘已入船籍，船上水粮未及搬过。" % r1[1]
	_check(str(FX.sea_prize_note(prizes1, 0, 0)) == want_prize,
		"夺船句：「%s」（得「%s」）" % [want_prize, FX.sea_prize_note(prizes1, 0, 0)])
	# 走真结算：日志首行＝脱战句＋夺船句，不加接舷前缀；结算后夺来的船仍在册、水粮不因夺船变
	var scf = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(scf)
	scf.set("sailing", false)
	scf.set("remaining_li", 50.0)
	scf.get("log_label").text = ""
	scf.call("_on_battle_result", "flee", d1)
	var logf: String = scf.get("log_label").get_parsed_text()
	var raw_f := ok_note + want_prize
	_check(logf.find(raw_f) == 0 and logf.find("接舷既定。") < 0,
		"夺船后甩脱战后注记：「%s」（得首行「%s」）" % [raw_f, logf.get_slice("\n", 0)])
	var in_reg := false
	for s1 in Flt.get("ships"):
		if is_same(s1, r1[3]):
			in_reg = true
	_check(in_reg and (Flt.get("ships") as Array).size() == 3,
		"注记说入船籍：结算后夺来的「%s」仍在名册（%d 格）" % [r1[1], (Flt.get("ships") as Array).size()])
	var strip_f: String = scf.get("_strip_line").get_parsed_text().get_slice("\n", 1).strip_edges()
	var expect_f := raw_f if raw_f.length() <= 28 else raw_f.substr(0, 27) + "…"
	_check(strip_f == expect_f,
		"夺船后甩脱：顶匾第二行照 _refresh_strip 28 字收（实长 %d 字，匾上得「%s」）" % [raw_f.length(), strip_f])
	# 没夺船的弃战：原句一字不动
	scf.get("log_label").text = ""
	scf.call("_on_battle_result", "flee", {"flee_ok": true})
	_check(scf.get("log_label").get_parsed_text().get_slice("\n", 0) == ok_note,
		"没夺船的甩脱注记照旧（得「%s」）" % scf.get("log_label").get_parsed_text().get_slice("\n", 0))
	# ② 未能甩脱（旗舰带货，被夺货物清单后补句号再接夺船句）
	var r2: Array = run.call({"flee_ok": false})
	var d2f: Dictionary = (r2[0] as Array)[0][1] if (r2[0] as Array).size() == 1 else {}
	Flt.call("add_cargo", "pepper", 10, 10.0, 0)
	scf.get("log_label").text = ""
	scf.call("_on_battle_result", "flee", d2f)
	var log2f: String = scf.get("log_label").get_parsed_text().get_slice("\n", 0)
	_check(log2f.begins_with("未能甩脱。") and log2f.ends_with("。所夺「%s」一艘已入船籍，船上水粮未及搬过。" % r2[1])
		and log2f.find("胡椒") >= 0 and log2f.find("　。") < 0
		and (Flt.get("ships") as Array).size() == 3,
		"夺船后未能甩脱：被夺货物之后交代夺船与水粮，夺来的船仍在册（得「%s」）" % log2f)
	# ③ 限时两散
	var r3: Array = run.call({"flee_ok": true, "parted": true})
	var d3f: Dictionary = (r3[0] as Array)[0][1] if (r3[0] as Array).size() == 1 else {}
	scf.get("log_label").text = ""
	scf.call("_on_battle_result", "flee", d3f)
	var log3f: String = scf.get("log_label").get_parsed_text().get_slice("\n", 0)
	_check(log3f == str(FX.sea_parted_note()) + "所夺「%s」一艘已入船籍，船上水粮未及搬过。" % r3[1],
		"夺船后两散：收帆句后交代夺船与水粮（得「%s」）" % log3f)
	root.remove_child(scf)
	scf.free()
	GM.pending_battle = {}
	# ④ 句式：同名合计、先夺先写；水粮真转了写数；没夺船空串
	var multi := str(FX.sea_prize_note([{"name": "快船"}, {"name": "元哨船"}, {"name": "快船"}], 0, 0))
	_check(multi == "所夺「快船」二艘、「元哨船」一艘已入船籍，船上水粮未及搬过。"
		and str(FX.sea_prize_note([{"name": "快船"}], 20, 15)) == "所夺「快船」一艘已入船籍，搬过水 20、粮 15。"
		and str(FX.sea_prize_note([], 0, 0)) == "",
		"夺船句式：同名合计、水粮转了写数、没夺船不写（得「%s」）" % multi)


## 二之三（lane w19-g2）：夺船后旗舰沉没——修前 WorldMap 只在 flee 收战时并夺船账，lose{sunk} 不带 prizes，
## SeaChart 沉船句只写「旗舰沉没，该船货物随船。…余船尚在。船体受损 N。」，夺来的船已在名册、「余船」里就有它，注记不交代。
## 现在：旗舰沉没也走 _prize_ledger（按名册格认），夺船句夹在「余船尚在。」与「船体受损」之间（交代在前、账目在后），
## 顶匾第二行照 _refresh_strip 28 字截断定式收；全队俱没不写夺船句（随后 _sink 清船，写「已入船籍」反成虚账）。
## 夺船带不带走水粮水手属 V0928-7，不改：本地线夺船不转水粮，恒写「未及搬过」。名册先放一艘同名「快船」对账。
func _v0928_prize_sunk_check(Flt: Node, FX, pirate: Dictionary) -> void:
	GS.from_dict({})
	Flt.set("ships", [])
	Flt.call("add_ship", "fu_ship_medium", "")
	Flt.call("add_ship", "pirate_boat", "快船")
	for s0 in Flt.get("ships"):
		s0["crew"] = 20
	Flt.water = 300
	Flt.food = 300
	var got: Array = []
	var wm := _crew_battle(pirate, "pirate", got)
	var foes := _crew_foes(wm)
	var taken := ""
	if foes.size() >= 2:
		foes[0].set("crew", 0)
		taken = str((foes[0] as Object).get("ship_name"))
		wm.call("_board_enemy", foes[0])
	var still := got.is_empty()
	var ships0: Array = Flt.get("ships")
	var prize_ref: Variant = ships0[-1] if ships0.size() == 3 else null
	# 旗舰沉没：Ship._sink_ship 在海战里转给 WorldMap._battle_player_sunk（同一出口），船体先记到 0
	(ships0[0] as Dictionary)["durability"] = 0.0
	wm.call("_battle_player_sunk")
	var d: Dictionary = got[0][1] if got.size() == 1 else {}
	var prizes: Array = d.get("prizes", [])
	_check(still and got.size() == 1 and got[0][0] == "lose" and bool(d.get("sunk", false)) and foes.size() >= 2,
		"夺一艘后旗舰沉没：夺船当时不收战，按 lose{sunk} 收战（得 %s）" % [got])
	_check(prizes.size() == 1 and str(prizes[0].get("name", "")) == taken and str(prizes[0].get("type", "")) == "pirate_boat"
		and prize_ref != null and is_same((Flt.get("ships") as Array)[2], prize_ref),
		"夺船后旗舰沉没：data.prizes 只记本场夺来的一艘（名册先有同名「快船」不算），与名册末格同一格（prizes %s）" % [prizes])
	var mv: Dictionary = d.get("stores_moved", {})
	_check(int(mv.get("water", -1)) == 0 and int(mv.get("food", -1)) == 0,
		"夺船后旗舰沉没：水粮账本场未动（stores_moved %s）" % [mv])
	# 走真结算：旗舰带货，日志首行＝沉船句，夺船句在「余船尚在。」之后、「船体受损」之前
	Flt.call("add_cargo", "pepper", 10, 10.0, 0)
	var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	sc.set("sailing", false)
	sc.set("remaining_li", 50.0)
	sc.get("log_label").text = ""
	sc.call("_on_battle_result", "lose", d)
	var line: String = sc.get("log_label").get_parsed_text().get_slice("\n", 0)
	var want_prize := "所夺「%s」一艘已入船籍，船上水粮未及搬过。" % taken
	var at_rest := line.find("余船尚在。")
	var at_prize := line.find(want_prize)
	var at_dmg := line.find("船体受损 ")
	_check(line.begins_with("旗舰沉没，该船货物随船。") and line.find("胡椒") >= 0 and at_rest >= 0
		and at_prize == at_rest + "余船尚在。".length() and at_dmg == at_prize + want_prize.length()
		and line.ends_with("。") and line.find("接舷既定。") < 0,
		"夺船后旗舰沉没战后注记：「余船尚在。」后接「%s」再记船体受损（得「%s」）" % [want_prize, line])
	var in_reg := false
	for s1 in Flt.get("ships"):
		if is_same(s1, prize_ref):
			in_reg = true
	_check(in_reg and (Flt.get("ships") as Array).size() == 3 and Flt.water == 300 and Flt.food == 300,
		"注记说入船籍：结算后夺来的「%s」仍在名册（%d 格），水粮不因夺船变（水 %d 粮 %d）" % [taken, (Flt.get("ships") as Array).size(), Flt.water, Flt.food])
	var strip: String = sc.get("_strip_line").get_parsed_text().get_slice("\n", 1).strip_edges()
	var expect := line if line.length() <= 28 else line.substr(0, 27) + "…"
	_check(strip == expect,
		"夺船后旗舰沉没：顶匾第二行照 _refresh_strip 28 字收（实长 %d 字，匾上得「%s」）" % [line.length(), strip])
	# 没夺船的旗舰沉没：原句一字不动
	sc.get("log_label").text = ""
	sc.call("_on_battle_result", "lose", {"sunk": true, "player_damage": 0.0})
	var plain: String = sc.get("log_label").get_parsed_text().get_slice("\n", 0)
	_check(plain == "旗舰沉没，该船货物随船。余船尚在。船体受损 0。" and plain == str(FX.sea_sunk_note("", 0, false)),
		"没夺船的旗舰沉没注记照旧（得「%s」）" % plain)
	root.remove_child(sc)
	sc.free()
	GM.pending_battle = {}
	# 句式：全队俱没不写夺船句；夺船句为空时与旧句同
	_check(str(FX.sea_sunk_note("", 5, true, want_prize)) == "旗舰沉没，货舱随船。船体受损 5。"
		and str(FX.sea_sunk_note("", 5, false, "")) == "旗舰沉没，该船货物随船。余船尚在。船体受损 5。",
		"沉船句式：全队俱没不写夺船句（得「%s」），无夺船同旧句" % FX.sea_sunk_note("", 5, true, want_prize))


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


## ── crew 线 09-30 合并：海战难度对账按本地线 EnemyCaptainAI 重记基线（lane cov1）──
## origin 那条 09-29 的对账是给它自己的操船记的账：pre 杆（orbit_radius=0、见 PirateShip 旧兜圈法）在本地线上
## 无处可挂——09-30 本地线操船已整体换成 EnemyCaptainAI（tick → _orders → _steer/_process_firing），「修前 vs 现行」
## 的比例口径无从谈起。这里作废旧四条常量与 pre 模拟，把对账重记为本地线自身的范围断言。
##
## 测法（Verify 段同述）：开局小艍（耐久照 ships.json）遇三艘元军哨船（PATROL_ENEMY），走真实引擎栈
## （instantiate → add_child → _ready → _ensure_captain，敌将／分离推力／开炮全走本地线真码），每物理帧手推进度
## （position += velocity*dt；本船收帆不动、不还炮）推 CREW_FIRST_SECS 秒，CREW_FIRST_SEEDS 个固定种子。
## 确定性：每场 _ready 里 randomize()/_rng.randomize() 从全局序列取值，而序列受节点顺序扰动——
## 同 tick 顺序多次重演在同进程内逐位一致（本函数内 REPLAY 轮自证），不是跨进程保证；所以断言只写范围。
## 基线（2026-09-30 重记，n=50 见 lane brief Verify）：首轮几乎打不沉小艍（EnemyCaptainAI 开炮要正横±FIRE_ARC、
## spawn 极角随机，3.5 s 时只有少数局恰好横舷齐射）、满 12 s 大半局数小艍未沉、全灭不超半。
## 范围断言取实测分布的外推上限（不编一个看起来合理的数字，边界都出自实测）：
##   ①首轮（COMBAT_FIRE_DELAY + FIRE_INTERVAL 前）沉 0 局——实测全 0，写死 0 是结构断言（火力×减伤 < 耐久，变难必破）；
##   ②正向命中：12 s 受伤中位 > 0（AI 真的在开炮；打不还手的靶 60 局零伤必是探针断了，不是难度变了）；
##   ③12 s 内沉船数 ≤ CREW_FIRST_SUNK_MAX（实测分布峰值远低于半）——防止难度陡增静默落地；
##   ④run-to-run 发散有界：同 seed 重跑受引擎 RNG 存量影响（randomize() 射程不一），但首轮 0 沉是逐位结构断言，
##     总沉数不越上限。sail 期数（同一 seed 两轮伤/沉不必逐位等）。
const CREW_FIRST_SEEDS := 60
const CREW_FIRST_SECS := 12.0
const CREW_FIRST_SUNK_MAX := 25
# 09-29 origin 那条的「修前 vs 现行」比例口径（本船 30 s 受伤比 CREW_DIFF_* / CREW_SECS）已随操船换代作废，
# pre 无处可挂（PirateShip 上已无 orbit_radius 挂点），四条常量不再定义，历史值留在 09-29 归档行。


func _v0928_crew_difficulty(patrol: Dictionary) -> void:
	var Flt: Node = root.get_node("Fleet")
	var wm_const: Dictionary = (load("res://scripts/WorldMap.gd") as GDScript).get_script_constant_map()
	var ps_const: Dictionary = (load("res://scripts/PirateShip.gd") as GDScript).get_script_constant_map()
	var first_end: float = float(wm_const.get("COMBAT_FIRE_DELAY", 0.0)) + float(ps_const.get("FIRE_INTERVAL", 0.0))
	var t0 := Time.get_ticks_msec()
	# 开局小艍（耐久照 ships.json）遇三艘哨船，推到沉船为止（至多 CREW_FIRST_SECS，没沉记作无穷）
	var hull := float((Flt.call("ship_def", "sampan") as Dictionary).get("durability", 0.0))
	var first_round := 0
	var sunk_n := 0
	var sink_times: Array = []
	var dmgs: Array = []
	for k in CREW_FIRST_SEEDS:
		var res: Array = _crew_sim(patrol, "yuan_patrol", "sampan", hull, 9000 + k, CREW_FIRST_SECS)
		var at := float(res[2])
		sink_times.append(at)
		dmgs.append(float(res[0]))
		if at >= 0.0:
			sunk_n += 1
			if at < first_end:
				first_round += 1
	_check(int(patrol.get("count", 0)) >= 3 and hull > 0.0 and first_round == 0,
		"首轮打不沉开局小艍：%.1f s 内 0 局沉（%d 局；EnemyCaptainAI 开炮要正横±FIRE_ARC＋首轮装填 %.1f s）" % [
			first_end, CREW_FIRST_SEEDS, first_end])
	_check(_median(dmgs) > 0.0,
		"对账正向命中哨兵：%d 局受伤中位 %.0f > 0（打不还手的靶全零伤必是探针断了，不是难度变了）" % [
			CREW_FIRST_SEEDS, _median(dmgs)])
	_check(sunk_n <= CREW_FIRST_SUNK_MAX,
		"小艍 %.0f 耐久遇 %d 艘哨船推 %.0f s：沉 %d / %d 局，不越上限 %d（基线分布见头注；中位受伤 %.0f）" % [
			hull, int(patrol.get("count", 0)), CREW_FIRST_SECS, sunk_n, CREW_FIRST_SEEDS, CREW_FIRST_SUNK_MAX, _median(dmgs)])
	print("STORY_CHECK note 海战难度对账 %d 局用时 %d ms（沉 %d，首轮 %d，伤位 %s）" % [
		CREW_FIRST_SEEDS, Time.get_ticks_msec() - t0, sunk_n, first_round, _dist_line(dmgs)])
	GM.pending_battle = {}
	randomize()


## 中位数（难度对账日志用）；空组返回 0
func _median(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	return float(s[s.size() / 2])


## 一行分布（难度对账日志用）：最小—最大、中位、各档局数
func _dist_line(vals: Array) -> String:
	if vals.is_empty():
		return "空"
	var s := vals.duplicate()
	s.sort()
	return "%.0f—%.0f，中位 %.0f，零伤 %d 局，≥120 %d 局" % [
		float(s[0]), float(s[s.size() - 1]), float(s[s.size() / 2]),
		s.filter(func(x): return float(x) < 0.5).size(), s.filter(func(x): return float(x) >= 120.0).size()]


## 同步推一场海战 secs 秒（每步一个物理帧），本地线 EnemyCaptainAI 版（lane cov1 09-30 重写）：
## 敌船操作原样复刻 PirateShip._physics_process 的次序（captain.tick → 分离推力偏航向 → _steer → 手动平移 →
## _process_firing），不调 move_and_slide（它在物理帧外用错 delta；敌船彼此、与本船都隔着百余 px，平移即可）；
## 炮弹走真 _process；命中按两圆心距 < 两碰撞圆半径和（不打发炮船自己），扣真 take_damage（敌船版会掉水手、掉士气，
## 本船乘甲减伤），不走命中烟火（一场几十发，延迟入树的粒子会堆到帧末）；炮弹满 lifetime 放掉。
## 本船收帆不动、不还炮（不调 Ship._physics_process，velocity 置零只挡 wind_push）。
## 固定种子：WorldMap._ready 里 randomize() 过，放掉已刷的敌船后按 seed_v 照 _setup_combat 的刷船一步经 _spawn_enemy 重刷。
## 返回 [本船受伤, 0, 本船沉船时刻或 -1]。
func _crew_sim(entry: Dictionary, event: String, ship_type: String, hull: float, seed_v: int, secs: float) -> Array:
	var Flt: Node = root.get_node("Fleet")
	GS.from_dict({})
	Flt.set("ships", [])
	Flt.call("add_ship", ship_type, "")
	var fs: Dictionary = (Flt.get("ships") as Array)[0]
	fs["durability"] = hull
	fs["max_durability"] = hull
	var got: Array = []
	var wm := _crew_battle(entry, event, got)
	for f in _crew_foes(wm):
		wm.remove_child(f)
		f.free()
	wm.set("total_enemies", 0)
	seed(seed_v)
	# 同 WorldMap._setup_combat 的刷船一步：逐条刷（本地线没有兜圈方向的 _orbit_sense）
	for e in (GM.pending_battle.get("enemy", []) as Array):
		wm.call("_spawn_enemy", str(e.get("type", "pirate_boat")), int(e.get("count", 1)), GM.pending_battle,
			str(e.get("sprite", "")))
	var own: Node2D = wm.get("ship")
	var foes := _crew_foes(wm)
	var balls: Array = []
	var on_child := func(c: Node) -> void:
		if "shooter" in c and "lifetime" in c:
			balls.append([c, 0.0, c.get("shooter"), float(c.get("lifetime")), float(c.get("damage"))])
	wm.child_entered_tree.connect(on_child)
	var bodies: Array = [own]
	bodies.append_array(foes)
	var radius := {}
	for b in bodies:
		radius[b] = float(((b as Node).get_node("CollisionShape2D") as CollisionShape2D).shape.get("radius"))
	var ps_scr = load("res://scripts/PirateShip.gd")
	var sep_weight := float(ps_scr.get("SEPARATION_WEIGHT"))
	var cb_probe: Node = (load("res://scenes/Cannonball.tscn") as PackedScene).instantiate()
	var cb_r := float((cb_probe.get_node("CollisionShape2D") as CollisionShape2D).shape.get("radius"))
	cb_probe.free()
	var armor := float(Flt.call("armor_damage_reduction"))
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var d0 := float(fs.get("durability", 0.0))
	var sunk_at := -1.0
	for k in int(secs / dt):
		for f in foes:
			if not is_instance_valid(f) or f.is_queued_for_deletion() or float(f.get("hull_hp")) <= 0.0:
				continue
			if float(f.position.distance_to(own.position)) > 2500.0:
				continue  # 照 _physics_process 远距休眠
			var captain = f.get("captain")
			var orders: Dictionary = captain.call("tick", f.call("_situation"), dt)
			var push: Vector2 = f.call("_separation_push")
			if push != Vector2.ZERO:
				var heading: Vector2 = orders.get("heading", Vector2.UP.rotated(f.rotation))
				orders["heading"] = (heading + push * sep_weight).normalized()
			f.set("enemy_morale", int(orders.get("morale", f.get("enemy_morale"))))
			f.call("_steer", orders, dt)
			var ship_dir := Vector2.UP.rotated(f.rotation)
			var rel: Vector2 = (own.position - f.position).normalized()
			f.call("_process_firing", dt, ship_dir.angle_to(rel), f.position.distance_to(own.position))
			f.position += f.velocity * dt
		if own.get("velocity") != Vector2.ZERO:
			own.set("velocity", Vector2.ZERO)  # 本船收帆：只挡 wind_push，不还炮不走位
		var live: Array = []
		for e in balls:
			var cb: Node2D = e[0]
			if not is_instance_valid(cb):
				continue  # 命中沉船 → CombatFx 爆烟或清掉了
			var hit_body: Node2D = null
			for b in bodies:
				if b == e[2] or not is_instance_valid(b) or (b as Node).is_queued_for_deletion():
					continue
				if float(b.get("hull_hp")) <= 0.0:
					continue
				if (b as Node2D).position.distance_to(cb.position) < cb_r + float(radius[b]):
					hit_body = b
					break
			if hit_body != null:
				hit_body.call("take_damage", float(e[4]) * (armor if hit_body == own else 1.0))
				cb.free()
				continue
			cb.call("_process", dt)
			e[1] = float(e[1]) + dt
			if float(e[1]) >= float(e[3]):
				cb.free()
				continue
			live.append(e)
		# 原地换内容：on_child 捕获的是这个数组本身，重新赋值后新炮弹会记到旧数组里
		balls.clear()
		balls.append_array(live)
		if float(fs.get("durability", 0.0)) <= 0.0:
			sunk_at = float(k + 1) * dt
			break
	var dmg_total := d0 - float(fs.get("durability", 0.0))
	for e in balls:
		if is_instance_valid(e[0]):
			(e[0] as Node).free()
	if is_instance_valid(wm):
		wm.free()
	return [dmg_total, 0, sunk_at]


## ── visual 线 09-28 修复：人物志防剧透与世界线门控、林华按日期换画、立绘册页签 ──
## 可见条件扩了 "YYYY-MM"（按月）、"end:结局|结局"、"id:身份"、"flag:旗标"、「&」连写与「!」取反（CharacterArt.segment_visible）。
## 断言只钉「该露 / 不该露」的字，不钉整段文案；每条剧透都配一条「到时候确实露了」的对照，免得全藏也绿。
func _v0928_visual_check(_main: Node) -> void:
	var Art = load("res://scripts/ui/CharacterArt.gd")
	var zan: Dictionary = GM.get_character("chen_zan")
	var lu: Dictionary = GM.get_character("lu_xiufu")
	var zhang: Dictionary = GM.get_character("zhang_shijie")
	var lin: Dictionary = GM.get_character("lin_hua")
	var pc: Dictionary = GM.get_character("chen_wenlong")
	# 条件解析：月份键、残了一截的组合、认不得的键
	GS.from_dict({})
	Cal.from_dict({"year": 1277, "month": 10, "day": 5})
	_check(not Art.segment_visible("1277-11") and Art.segment_visible("1277-10") and Art.segment_visible("1276-12"),
		"月份键：1277-10 时 \"1277-10\" 已到、\"1277-11\" 未到")
	_check(not Art.segment_visible("1268&") and not Art.segment_visible("lately") and not Art.segment_visible("end:忠肃"),
		"残缺组合「1268&」、认不得的键、未了结时的 end:… 一律不可见")
	# 陈瓒：再陷（1277-11）之前不露「就死在这里」与车裂；复城（1277-02）之前不露复城
	var zan_lines_10 := "".join(Art.codex_lines(zan))
	Cal.from_dict({"year": 1277, "month": 11, "day": 5})
	var zan_lines_11 := "".join(Art.codex_lines(zan))
	_check(zan_lines_10.find("死在这里") < 0 and zan_lines_11.find("死在这里") >= 0,
		"陈瓒其言：1277-10 不含「死在这里」、1277-11 起才有（10 月 %d 句）" % Art.codex_lines(zan).size())
	Cal.from_dict({"year": 1277, "month": 1, "day": 5})
	var zan_bio_01: String = Art.codex_bio(zan) + Art.codex_short(zan)
	Cal.from_dict({"year": 1277, "month": 6, "day": 5})
	var zan_bio_06: String = Art.codex_bio(zan) + Art.codex_short(zan)
	Cal.from_dict({"year": 1277, "month": 12, "day": 5})
	var zan_bio_12: String = Art.codex_bio(zan)
	_check(zan_bio_01.find("复") < 0 and zan_bio_06.find("复了兴化城") >= 0 and zan_bio_06.find("车裂") < 0 and zan_bio_12.find("车裂") >= 0,
		"陈瓒小传：1277-01 未复城不写复城，1277-06 写复城不写车裂，1277-12 写车裂")
	# 陆秀夫、张世杰：崖山卡开到 1279-03，1279-04 起才露投海、覆舟
	Cal.from_dict({"year": 1279, "month": 2, "day": 5})
	var lu_02: String = Art.codex_bio(lu) + Art.codex_short(lu) + "".join(Art.codex_lines(lu))
	var zhang_02: String = Art.codex_bio(zhang) + Art.codex_short(zhang)
	Cal.from_dict({"year": 1279, "month": 4, "day": 5})
	var lu_04: String = Art.codex_bio(lu)
	_check(lu_02.find("投海") < 0 and lu_02.find("为国死") < 0 and zhang_02.find("覆舟") < 0 and lu_04.find("投海") >= 0,
		"陆秀夫 1279-02 小传、简介、其言不含「投海」「为国死」，张世杰不含「覆舟」；1279-04 起露")
	# 林华：1276-08 还在船上当舵工，小传不写降、称谓不是部将；1277-01 城破后写
	Cal.from_dict({"year": 1276, "month": 8, "day": 5})
	var lin_08: String = Art.codex_bio(lin) + Art.codex_short(lin) + "".join(Art.codex_lines(lin))
	var lin_title_08: String = Art.codex_title(lin)
	Cal.from_dict({"year": 1277, "month": 1, "day": 5})
	var lin_01: String = Art.codex_bio(lin)
	_check(lin_08.find("降") < 0 and lin_08.find("元兵") < 0 and lin_title_08.find("部将") < 0 and lin_01.find("降") >= 0,
		"林华 1276-08 小传 / 简介 / 其言不含「降」「元兵」，称谓「%s」不是部将；1277-01 起写降" % lin_title_08)
	# 林华立绘按日期换：辞船（1276-10）之前挂剪影墨卡，之后与了结后挂甲胄正图
	Cal.from_dict({"year": 1276, "month": 8, "day": 5})
	var lin_pic_08: String = Art.portrait_path(lin)
	Cal.from_dict({"year": 1276, "month": 10, "day": 5})
	var lin_pic_10: String = Art.portrait_path(lin)
	_check(lin_pic_08 != str(lin.get("portrait", "")) and ResourceLoader.exists(lin_pic_08) and Art.portrait_is_card(lin) == false
			and lin_pic_10 == str(lin.get("portrait", "")),
		"林华立绘 1276-08 挂 %s（在库）、1276-10 起挂正图 %s" % [lin_pic_08.get_file(), lin_pic_10.get_file()])
	Cal.from_dict({"year": 1276, "month": 8, "day": 5})
	_check(Art.portrait_is_card(lin) and Art.thumb(lin, Vector2i(34, 34), true) != null,
		"林华 1276-08 立绘面板记作剪影卡，缩略图取得到")
	# 主角世界线：[身份, 改名, 年, 月, 结局]
	var lines_of := func() -> String: return "".join(Art.codex_lines(pc))
	# 纲首（海商）了结：字号无君贲，其言无节义文章，又称不重名、有陈纲首，史载有引子，称谓是纲首
	GS.from_dict({})
	GS.identity = "merchant"
	Cal.from_dict({"year": 1285, "month": 5, "day": 5})
	GS.finish("纲首", "正文")
	var gs_alts: PackedStringArray = Art.codex_alts(pc)
	var gs_annal := "".join(Art.codex_annal(pc))
	_check(Art.courtesy_of(pc).find("君贲") < 0 and str(lines_of.call()).find("节义文章") < 0,
		"纲首线了结：主角字号「%s」不含君贲，其言不含「此皆节义文章也」" % Art.courtesy_of(pc))
	_check(not (Art.display_name(pc) in gs_alts) and "陈纲首" in gs_alts and Art.codex_title(pc).find("纲首") >= 0,
		"纲首线了结：又称 %s 不含大名、有陈纲首；称谓「%s」" % [gs_alts, Art.codex_title(pc)])
	_check(gs_annal.find("另一条路") >= 0 and gs_annal.find("岳王庙") >= 0 and Art.codex_bio(pc).find("岳王庙") < 0,
		"纲首线了结：岳王庙那段只在「史载」一节（带「此世他走了另一条路」引子），不在小传里")
	_check(not Art.rel_visible("庙前殉节者") and not Art.rel_visible("后世齐名") and not Art.rel_visible("赐名状元"),
		"纲首线了结：关系签「庙前殉节者」「后世齐名」「赐名状元」不露")
	# 岸上的根（乡土）了结：同样不露君贲、节义文章，没有陈纲首
	GS.from_dict({})
	GS.identity = "hometown"
	Cal.from_dict({"year": 1277, "month": 10, "day": 20})
	GS.finish("岸上的根", "正文")
	_check(Art.courtesy_of(pc).find("君贲") < 0 and str(lines_of.call()).find("节义文章") < 0 and not ("陈纲首" in Art.codex_alts(pc))
			and "".join(Art.codex_annal(pc)).find("另一条路") >= 0,
		"岸上的根了结：无君贲、无节义文章、无陈纲首，史载有引子")
	# 未归（士人）：史载一节有本世界的史书「不知所终」，引子写明城破时他不在城里（未归 = 没打守城，Main._check_absent_from_xinghua），
	# 不重述小传里已有的殿试改名；其言仍无「节义文章」；君贲照露
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	GS.player_name = "陈文龙"
	Cal.from_dict({"year": 1277, "month": 1, "day": 5})
	GS.finish("未归", "正文")
	var wg_annal := "".join(Art.codex_annal(pc))
	_check(wg_annal.find("不知所终") >= 0 and wg_annal.find("不在城里") >= 0 and str(lines_of.call()).find("节义文章") < 0
			and Art.courtesy_of(pc).find("君贲") >= 0 and not Art.rel_visible("庙前殉节者") and Art.rel_visible("赐名状元"),
		"未归线：史载有「不知所终」与「城破时他不在城里」引子，其言无节义文章，字号有君贲，「赐名状元」露、「庙前殉节者」不露")
	_check(wg_annal.find("殿试") < 0 and wg_annal.find("不呈稿") < 0 and wg_annal.find("岳王庙") >= 0 and Art.codex_bio(pc).find("殿试") >= 0,
		"未归线：史载不再重述小传里的殿试改名、不呈稿，只接城破以后；小传仍有殿试")
	# 人物志详页实建：未归线「史载」一节真的上屏
	var cx_scr = load("res://scripts/ui/CharacterCodex.gd")
	var cx: Control = cx_scr.new()
	root.add_child(cx)
	cx.call("begin", "chen_wenlong")
	_check(_find_label_text(cx, "史载") != "" and _find_label_text(cx, "不知所终") != "",
		"未归线人物志详页有「史载」一节、上屏「不知所终」")
	cx.queue_free()
	# 忠肃：其言有节义文章，史载没有引子，三枚关系签都露
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	GS.player_name = "陈文龙"
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	GS.finish("忠肃", "正文")
	var zs_annal := "".join(Art.codex_annal(pc))
	_check(str(lines_of.call()).find("节义文章") >= 0 and zs_annal.find("岳王庙") >= 0 and zs_annal.find("另一条路") < 0
			and Art.rel_visible("庙前殉节者") and Art.rel_visible("后世齐名") and Art.rel_visible("赐名状元"),
		"忠肃线：其言有「此皆节义文章也」，史载无引子，三枚关系签都露")
	_check(zs_annal.find("殿试") < 0 and zs_annal.find("不知所终") < 0,
		"忠肃线：史载不重述小传里的殿试改名，也没有未归线的「不知所终」")
	# 士人线守城中（1276-11，未了结）：字号有君贲，称谓是知兴化军，小传补了殿试改名与知兴化军，没有陈纲首
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	GS.player_name = "陈文龙"
	GS.chapter = 4
	Cal.from_dict({"year": 1276, "month": 11, "day": 5})
	GS.siege_begin()
	var sc_bio: String = Art.codex_bio(pc)
	_check(Art.courtesy_of(pc).find("君贲") >= 0 and Art.codex_title(pc).find("知兴化军") >= 0 and sc_bio.find("殿试") >= 0
			and sc_bio.find("知兴化军") >= 0 and not ("陈纲首" in Art.codex_alts(pc)) and sc_bio.find("岳王庙") < 0
			and Art.codex_look(pc).find("宝祐三年") >= 0,
		"士人线守城中：字号有君贲，称谓「%s」，小传有殿试改名、知兴化军，无陈纲首、无死法，形貌标宝祐三年" % Art.codex_title(pc))
	# 海商线第三章（1270-06）：有陈纲首；士人线同年没有
	GS.from_dict({})
	GS.identity = "merchant"
	GS.chapter = 3
	GS.visited_ports.append("quanzhou")
	Cal.from_dict({"year": 1270, "month": 6, "day": 5})
	var m_alts: PackedStringArray = Art.codex_alts(pc)
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	GS.player_name = "陈文龙"
	var s_alts: PackedStringArray = Art.codex_alts(pc)
	_check("陈纲首" in m_alts and not ("陈纲首" in s_alts) and not ("陈文龙" in s_alts),
		"又称按身份：海商 1270-06 %s 有陈纲首，士人同年 %s 没有、也不重列大名" % [m_alts, s_alts])
	# 立绘册：从人物志点进史实人物，左栏翻到他所在的页签并选中他（原先停在「主」页签高亮陈子龙）
	GS.from_dict({})
	Cal.from_dict({"year": 1280, "month": 1, "day": 5})
	var roster: Node = load("res://scripts/chars/CharRoster.gd").new()
	root.add_child(roster)
	roster.call("select_id", "lu_xiufu")
	var tab_now := str(roster.get("tab"))
	_check(tab_now == "史实" and str(roster.call("selected_id")) == "lu_xiufu",
		"立绘册 select_id(陆秀夫)：翻到「%s」页签并选中（%s）" % [tab_now, roster.call("selected_id")])
	roster.call("select_id", "chen_wenlong")
	_check(str(roster.get("tab")) == "主" and str(roster.call("selected_id")) == "chen_wenlong",
		"立绘册 select_id(主角)：翻回「主」页签并选中")
	roster.queue_free()
	var roster2: Node = load("res://scripts/chars/CharRoster.gd").new()
	roster2.call("select_id", "sodu")
	root.add_child(roster2)
	_check(str(roster2.get("tab")) == "史实" and str(roster2.call("selected_id")) == "sodu",
		"立绘册未进树先 select_id(唆都)：进树后停在「史实」页签选中唆都（%s / %s）" % [roster2.get("tab"), roster2.call("selected_id")])
	roster2.queue_free()
	_v0928_visual_recheck(Art, pc, zan, lu, zhang)
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})


## 09-28 visual 线复核返修：全表扫漏网的整年键、晚投海商那一支的戏、称谓与小传同月、关系签拆签、卒年按月。
func _v0928_visual_recheck(Art, pc: Dictionary, zan: Dictionary, lu: Dictionary, zhang: Dictionary) -> void:
	var ws: Dictionary = GM.get_character("wang_shiqiang")
	var ws_text := func() -> String: return Art.codex_short(ws) + Art.codex_bio(ws)
	# 王世强：福州降在景炎元年十一月、泉州蒲寿庚降在十二月；年初不露，也不在建元（1276-05）前写「景炎」
	GS.from_dict({})
	GS.identity = "merchant"
	GS.chapter = 4
	GS.visited_ports.append("quanzhou")
	Cal.from_dict({"year": 1276, "month": 1, "day": 5})
	var ws_01: String = ws_text.call()
	Cal.from_dict({"year": 1276, "month": 10, "day": 5})
	var ws_10: String = ws_text.call()
	Cal.from_dict({"year": 1276, "month": 11, "day": 5})
	var ws_11: String = ws_text.call()
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	var ws_12: String = ws_text.call()
	_check(ws_01.find("景炎") < 0 and ws_10.find("泉州") < 0 and ws_10.find("福州") < 0 and ws_11.find("福州") >= 0
			and ws_11.find("泉州") < 0 and ws_12.find("泉州") >= 0,
		"王世强简介+小传：1276-01 无「景炎」，1276-10 无泉州、福州，1276-11 起有福州，1276-12 起有泉州")
	# 同月两页一个说法：端宗页的「张世杰与蒲寿庚决裂」、陈瓒页的「渡海助张世杰」与张、蒲本人页同在 1276-12 露
	var duan: Dictionary = GM.get_character("song_duanzong")
	Cal.from_dict({"year": 1276, "month": 11, "day": 5})
	var duan_11: String = Art.codex_bio(duan)
	var zan_11: String = Art.codex_bio(zan)
	var zhang_11: String = Art.codex_bio(zhang)
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	_check(duan_11.find("决裂") < 0 and zhang_11.find("蒲寿庚") < 0 and Art.codex_bio(duan).find("决裂") >= 0 and zan_11.find("三百万缗") < 0
			and Art.codex_bio(zan).find("三百万缗") >= 0,
		"端宗页决裂、陈瓒页输财与张世杰页同在 1276-12 露（1276-11 都不露）")
	# 陈宜中、王爚：焦山兵败后（1275-07）的那场朝议，年初不露；王爚七月已罢，不写成十月
	var cyz: Dictionary = GM.get_character("chen_yizhong")
	var wy: Dictionary = GM.get_character("wang_yue")
	Cal.from_dict({"year": 1275, "month": 6, "day": 5})
	var yi_06: String = Art.codex_bio(cyz) + Art.codex_bio(wy)
	Cal.from_dict({"year": 1275, "month": 7, "day": 5})
	var yi_07: String = Art.codex_bio(cyz) + Art.codex_bio(wy)
	_check(yi_06.find("该走") < 0 and yi_07.find("该走") >= 0 and yi_07.find("十月") < 0,
		"陈宜中、王爚：1275-06 小传无「该走」那场朝议，1275-07 起有，且不写「十月」")
	# 陆秀夫、张世杰卒年跟文本层同月（died_ym）：1279-03 生卒不写卒年，1279-04 起写
	Cal.from_dict({"year": 1279, "month": 3, "day": 5})
	var lu_l3: String = Art.life_line(lu)
	var zh_l3: String = Art.life_line(zhang)
	Cal.from_dict({"year": 1279, "month": 4, "day": 5})
	var lu_l4: String = Art.life_line(lu)
	var zh_l4: String = Art.life_line(zhang)
	var lu_died := str(int(lu.get("died", 0)))
	_check(lu_died != "0" and lu_l3.find(lu_died) < 0 and zh_l3.find(lu_died) < 0 and lu_l4.find(lu_died) >= 0 and zh_l4.find(lu_died) >= 0
			and Art.codex_bio(lu).find("投海") >= 0,
		"陆、张生卒：1279-03「%s」「%s」不写卒年，1279-04「%s」「%s」起写，与小传投海同月" % [lu_l3, zh_l3, lu_l4, zh_l4])
	# 林家后人：「陈大人……姓陈的读书人……船股一分」是晚投海商那一支的戏，别的世界线了结后也不露
	var heir: Dictionary = GM.get_character("lin_heir")
	var heir_text := func() -> String: return Art.codex_bio(heir) + "".join(Art.codex_lines(heir))
	GS.from_dict({})
	GS.identity = "merchant"
	Cal.from_dict({"year": 1285, "month": 5, "day": 5})
	GS.finish("纲首", "正文")
	var heir_gs: String = heir_text.call()
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	GS.finish("忠肃", "正文")
	var heir_zs: String = heir_text.call()
	GS.from_dict({})
	GS.identity = "merchant"
	GS.set_flag("renamed_wenlong")
	GS.set_flag("late_defection")
	Cal.from_dict({"year": 1276, "month": 1, "day": 5})
	var heir_ld: String = heir_text.call()
	_check(heir_gs.find("船股") < 0 and heir_gs.find("陈大人") < 0 and heir_zs.find("船股") < 0 and heir_zs.find("一铺之地") < 0
			and heir_ld.find("船股") >= 0 and heir_ld.find("一铺之地") >= 0,
		"林家后人：纲首、忠肃了结后无「陈大人」「船股一分」，晚投海商那一支 1276-01 未了结就有")
	# 市舶小吏「添纲首二字」与主角称谓同一口径（c3 且身份是海商 / 未定）：士人线第三章不露
	var cust: Dictionary = GM.get_character("customs_official")
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	GS.chapter = 3
	GS.visited_ports.append("quanzhou")
	Cal.from_dict({"year": 1272, "month": 6, "day": 5})
	var cust_sc: String = Art.codex_bio(cust)
	var pc_title_sc: String = Art.codex_title(pc)
	GS.from_dict({})
	GS.identity = "merchant"
	GS.chapter = 3
	GS.visited_ports.append("quanzhou")
	var cust_m: String = Art.codex_bio(cust)
	_check(cust_sc.find("纲首") < 0 and pc_title_sc.find("纲首") < 0 and cust_m.find("纲首") >= 0 and Art.codex_title(pc).find("纲首") >= 0,
		"市舶小吏「添纲首二字」：士人线 1272-06 第三章不露（主角称谓「%s」），海商线同月露" % pc_title_sc)
	# 蒲寿庚那句「非不忠义」点谁的名跟着世界线：士人线挂在主角页（点其名者），别的线挂在陈瓒页（点名之人）
	var pc_rel := ""
	for r in pc.get("relations", []):
		if str(r.get("id", "")) == "pu_shougeng":
			pc_rel = str(r.get("rel", ""))
	var zan_rel := ""
	for r in zan.get("relations", []):
		if str(r.get("id", "")) == "pu_shougeng":
			zan_rel = str(r.get("rel", ""))
	GS.from_dict({})
	GS.identity = "merchant"
	Cal.from_dict({"year": 1285, "month": 5, "day": 5})
	GS.finish("纲首", "正文")
	var m_pc: bool = Art.rel_visible(pc_rel)
	var m_zan: bool = Art.rel_visible(zan_rel)
	GS.from_dict({})
	GS.identity = "scholar"
	GS.set_flag("renamed_wenlong")
	Cal.from_dict({"year": 1276, "month": 12, "day": 5})
	GS.finish("忠肃", "正文")
	var s_pc: bool = Art.rel_visible(pc_rel)
	var s_zan: bool = Art.rel_visible(zan_rel)
	_check(pc_rel != "" and zan_rel != "" and pc_rel != zan_rel and not m_pc and m_zan and s_pc and not s_zan,
		"蒲寿庚点名签：主角页「%s」只在士人线露、陈瓒页「%s」只在未改名的线露（纲首 %s/%s，忠肃 %s/%s）" % [pc_rel, zan_rel, m_pc, m_zan, s_pc, s_zan])
	# 士人线称谓与小传同月：知抚州要等襄阳陷（1273-02）；侍御史、参知政事、辞官、复参政、知兴化军各在其月
	var scholar_at := func(y: int, m: int) -> void:
		GS.from_dict({})
		GS.identity = "scholar"
		GS.set_flag("renamed_wenlong")
		GS.player_name = "陈文龙"
		GS.chapter = 4
		Cal.from_dict({"year": y, "month": m, "day": 5})
	scholar_at.call(1273, 1)
	var t_7301: String = Art.codex_title(pc)
	var b_7301: String = Art.codex_bio(pc)
	scholar_at.call(1273, 2)
	var t_7302: String = Art.codex_title(pc)
	var b_7302: String = Art.codex_bio(pc)
	scholar_at.call(1274, 6)
	var t_7406: String = Art.codex_title(pc)
	_check(t_7301 == "监察御史" and b_7301.find("抚州") < 0 and b_7301.find("不呈稿") >= 0 and t_7302.find("知抚州") >= 0
			and b_7302.find("抚州") >= 0 and t_7406 == t_7302,
		"士人线 1273-01 称谓「%s」、小传未写贬抚州；1273-02 起称谓「%s」、小传写贬抚州；1274-06 仍「%s」" % [t_7301, t_7302, t_7406])
	scholar_at.call(1275, 6)
	var t_7506: String = Art.codex_title(pc)
	var b_7506: String = Art.codex_bio(pc)
	scholar_at.call(1275, 12)
	var t_7512: String = Art.codex_title(pc)
	scholar_at.call(1276, 5)
	var t_7605: String = Art.codex_title(pc)
	var b_7605: String = Art.codex_bio(pc)
	scholar_at.call(1276, 8)
	var t_7608: String = Art.codex_title(pc)
	var id_7608: String = Art.identity_line(pc)
	_check(t_7506 == "侍御史" and b_7506.find("侍御史") >= 0 and b_7506.find("参知政事") < 0 and t_7512.begins_with("前")
			and t_7605 == "参知政事" and b_7605.find("复以他为参知政事") >= 0 and b_7605.find("知兴化军") < 0
			and t_7608.find("知兴化军") >= 0 and id_7608.count("・") == 1,
		"士人线 1275-06「%s」、1275-12「%s」、1276-05「%s」、1276-08 身份行「%s」（称谓与籍贯之间只一个分隔点）" % [t_7506, t_7512, t_7605, id_7608])
	# 立绘面板身份行：籍贯逐字垫了字连接符，窄栏折行只折在「・」之后，不从「兴化军莆田／县玉湖」中间折；去掉连接符与原串一字不差
	var wj := String.chr(0x2060)
	var pp: Node = load("res://scripts/chars/CharPortraitPanel.gd").new()
	root.add_child(pp)
	pp.call("show_character", pc)
	var shown := _find_label_text(pp, "・")
	var origin_at := id_7608.rfind("・") + 1
	var para := TextParagraph.new()
	para.add_string(shown, UiTheme.font(), UiTheme.SIZE_FOOT + 1)
	para.width = UiTheme.font().get_string_size(id_7608, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT + 1).x * 0.8
	var breaks_ok := para.get_line_count() >= 2
	for i in range(1, para.get_line_count()):
		var start := shown.substr(0, para.get_line_range(i).x).replace(wj, "").length()
		if start > origin_at:
			breaks_ok = false
	_check(shown.replace(wj, "") == id_7608 and shown.find(wj) > 0 and breaks_ok,
		"立绘面板身份行垫字连接符：去掉后与原串相同，按八成宽折成 %d 行、只在「・」之后折" % para.get_line_count())
	pp.queue_free()
	GS.from_dict({})


## ── 09-28 涵江线修复（实机验收 digest「hanjiang」节 + visual 节「设施页题头字号」）──
## 涵江卡水粮不足直进本港船屋、船屋「离开」回带卡的港页；七日航程真吃水粮、状态条最上面是出海一句、落款旧避风澳；
## 10 月下旬点卡跨进冬月，册页与终局港页不挂「降元」；再陷前一月下旬副题催促；陈瓒船股只到兴化第一段 besieged 起点前；
## 围城米价撑在围城目标、城破后回落；战况通告按节点覆写（海口只说海口换旗）；牙行闭门不占三门、闭门页不写柜上三样不开新委办，
## 交货地是本港的在身委办照旧能交；
## 设施页题头统一 SIZE_HEAD；n_1277_07 传闻不把泉州围城写成已落地。月份一律从战况表推，数字只写门槛。
func _v0928_hanjiang_check(main: Node) -> void:
	var Eco: Node = root.get_node("Economy")
	var Flt: Node = root.get_node("Fleet")
	var card := "special_hanjiang_escape"
	var out_line := "四条船出了涵江海口，没有回头。"
	var war_x: Dictionary = GM.get_port_by_id("xinghua").get("war", {})
	var wkeys: Array = war_x.keys()
	wkeys.sort()
	var siege0 := ""
	for k in wkeys:
		if str(war_x[k]) == "besieged":
			siege0 = str(k)
			break
	var falls: Array = main._xinghua_fall_yms()
	_check(siege0 != "" and falls.size() >= 2, "兴化战况表有第一段围城起点（%s）与再陷（%s）" % [siege0, falls])
	if siege0 == "" or falls.size() < 2:
		return
	var zan_fall := str(falls[1])
	var zfy := int(zan_fall.split("-")[0])
	var zfm := int(zan_fall.split("-")[1])
	# 再陷前一月（涵江卡窗口的最后一月）
	var last_y := zfy if zfm > 1 else zfy - 1
	var last_m := zfm - 1 if zfm > 1 else 12
	var reset_root := func(y: int, m: int, d: int) -> void:
		GS.from_dict({})
		GS.identity = "merchant"
		GS.record_discovery("nameless_shelter_bay")
		Cal.from_dict({"year": y, "month": m, "day": d})
		var ym := "%04d-%02d" % [y, m]
		for nw in GM.news_data.get("news", []):
			if str(nw.get("date", "9999-99")) < ym:
				GS.mark_news_seen(str(nw.get("id", "")))
		Flt.at_sea = false
		GS.last_port = "xinghua"
		main.load_scene("xinghua")
	# 前面各段用 Fleet.from_dict({}) 清过船队：这里给一条开局船，才有船员吃水粮
	if Flt.ships.is_empty():
		Flt._grant_starter_ship()
	var use: int = Flt.daily_supply_use()
	_check(use > 0, "船队每日耗水粮 > 0（%d），七日航程才有得吃" % use)

	# ① 水粮不足：直进本港船屋；船屋「离开」回到带卡的港页，卡还在
	reset_root.call(last_y, last_m, 10)
	Flt.water = use * 3
	Flt.food = use * 3
	_check(card in main.shore_hand, "再陷前一月兴化岸上有涵江卡（名单 %s）" % [main.shore_hand])
	main._on_facility_pressed({"id": card})
	_check(main.current_scene_id == "xinghua_shipyard" and not GS.is_ended(),
		"水粮不足七日点涵江卡 → 直进本港船屋（页 %s，结局「%s」）" % [main.current_scene_id, GS.ended])
	# 门槛只按自家船队日耗算七日，提示不说族人吃你船上的粮（09-29 复核：原句与机制对不上）
	var short_log: String = main._latest_log()
	_check(short_log.find("族里四条船") >= 0 and short_log.find("七日") >= 0 and short_log.find("吃你船上") < 0,
		"水粮不足的提示点到族里四条船、你船上的要够七日，不说族人吃你的水粮（「%s」）" % short_log)
	var leave: Button = null
	for b in main.find_children("*", "Button", true, false):
		if (b as Button).text == "离开":
			leave = b as Button
	_check(leave != null, "船屋页有「离开」")
	if leave != null:
		leave.pressed.emit()
	_check(main.current_scene_id == "xinghua" and card in main.shore_hand,
		"船屋「离开」回到兴化港页、涵江卡还在（页 %s，名单 %s）" % [main.current_scene_id, main.shore_hand])

	# ② 水粮够：七日按海上日子吃水粮、推完 at_sea 复位；状态条最上面是出海一句；落款旧避风澳
	reset_root.call(last_y, last_m, 10)
	Flt.water = use * 20
	Flt.food = use * 20
	var w0: int = Flt.water
	var f0: int = Flt.food
	main._on_facility_pressed({"id": card})
	var days: int = main.HANJIANG_DAYS
	_check(GS.ended == "岸上的根" and w0 - int(Flt.water) >= days * use and f0 - int(Flt.food) >= days * use and not Flt.at_sea,
		"涵江七日航程吃掉 ≥%d 日水粮、推完仍泊港（水 %d→%d，粮 %d→%d，日耗 %d，at_sea=%s）" % [days, w0, Flt.water, f0, Flt.food, use, Flt.at_sea])
	_check(main._latest_log() == out_line, "结局册页弹出时状态条最上面是「%s」（实为「%s」）" % [out_line, main._latest_log()])
	_check(GS.ended_at.ends_with("・" + main.HANJIANG_END_PLACE) and GS.ended_at.find("兴化") < 0,
		"岸上的根落款写到岸的旧避风澳、不写兴化（「%s」）" % GS.ended_at)
	main._confirm_chapter_sheet()
	_close_dialogs(main)

	# ③ 再陷前一月下旬点卡，七日跨进再陷月：路上翻牌的城破通告照记，册页与终局港页不挂「降元」，状态条仍是出海一句
	reset_root.call(last_y, last_m, 28)
	Flt.water = use * 20
	Flt.food = use * 20
	_check(card in main.shore_hand, "%d-%02d-28 兴化岸上仍有涵江卡" % [last_y, last_m])
	var n0 := _notices.size()
	main._on_facility_pressed({"id": card})
	var crossed := "%04d-%02d" % [Cal.year, Cal.month] >= zan_fall
	var saw_fall := false
	var saw_jiang := false
	for t in _notices.slice(n0):
		var s := str(t)
		if s.find("兴化城破") >= 0:
			saw_fall = true
		if s.find("兴化") >= 0 and s.find("降元") >= 0:
			saw_jiang = true
	_check(crossed and GS.ended == "岸上的根" and GS.ended_at.ends_with("・" + main.HANJIANG_END_PLACE),
		"%d-%02d-28 点卡七日跨进再陷月 %s（现 %s，落款「%s」）" % [last_y, last_m, zan_fall, Cal.get_date_string(), GS.ended_at])
	_check(saw_fall and not saw_jiang, "跨月时路上发的是「兴化城破」覆写通告、没有「兴化已降元」（城破 %s，降元 %s）" % [saw_fall, saw_jiang])
	var sheet_jiang := _find_label_text(main.get("_chapter_host"), "降元")
	_check(main._latest_log() == out_line and sheet_jiang == "",
		"跨月结局册页：状态条最上面是出海一句（「%s」），册页不挂降元（「%s」）" % [main._latest_log(), sheet_jiang])
	main._confirm_chapter_sheet()
	_close_dialogs(main)
	var port_jiang := _find_label_text(main.port_mode, "降元")
	var port_fall := _find_label_text(main.port_mode, "城破")
	_check(main._shore_mode == "ended" and main._latest_log() == out_line and port_jiang == "" and port_fall == "",
		"跨月终局港页：状态条是出海一句、不挂降元或城破通告（页型 %s，「%s」／%s／%s）" % [main._shore_mode, main._latest_log(), port_jiang, port_fall])

	# ④ 副题：再陷前一月 HANJIANG_URGENT_DAY 起催促，此前、再前一月都写去处
	var urgent_day: int = main.HANJIANG_URGENT_DAY
	var sub_cases := [[last_y, last_m, urgent_day - 1, false], [last_y, last_m, urgent_day, true], [last_y, last_m, 30, true]]
	if last_m > 1:
		sub_cases.append([last_y, last_m - 1, 25, false])
	for sc in sub_cases:
		reset_root.call(sc[0], sc[1], sc[2])
		var sub := ""
		for c in main._special_cards():
			if str(c.get("id", "")) == card:
				sub = str(c.get("subtitle", ""))
		var urgent := sub.find("撑不过这个月") >= 0
		_check(sub != "" and urgent == bool(sc[3]),
			"涵江卡 %d-%02d-%02d 副题%s（「%s」）" % [sc[0], sc[1], sc[2], "催促" if sc[3] else "写去处", sub])
	# 卡的图标借「宅」（带族人走），不再和船屋门撞同一张大船。撞图对象换成了「住宅」门（同日可并排），待美术出涵江卡专用图标
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check(main_src.find("\"special_hanjiang_escape\": \"residence\"") >= 0, "SPECIAL_ICON 里涵江卡借 residence 图标")

	# ⑤ 陈瓒船股：围城起点前一月有；起点当月、再陷前一月（陈瓒仍活着）没有；已立股那行照旧显示
	var s0y := int(siege0.split("-")[0])
	var s0m := int(siege0.split("-")[1])
	var pre_y := s0y if s0m > 1 else s0y - 1
	var pre_m := s0m - 1 if s0m > 1 else 12
	var stake_cases := [[pre_y, pre_m, true, false], [s0y, s0m, false, false], [last_y, last_m, false, false], [last_y, last_m, false, true]]
	for zc in stake_cases:
		GS.from_dict({})
		GS.identity = "hometown"
		GS.fame = 40
		if bool(zc[3]):
			GS.set_flag("chen_zan_stake")
		Cal.from_dict({"year": zc[0], "month": zc[1], "day": 5})
		main.load_scene("xinghua_residence")
		var has_btn := false
		var has_line := false
		for node in main.choices_container.get_children():
			if node is Button and (node as Button).text.find("陈瓒愿入船股") >= 0:
				has_btn = true
			if node is Label and (node as Label).text.find("族叔陈瓒的船股一分") >= 0:
				has_line = true
		_check(main._chen_zan_alive() and has_btn == bool(zc[2]) and has_line == bool(zc[3]),
			"玉湖陈宅 %d-%02d（围城起点 %s）%s「陈瓒愿入船股」%s" % [zc[0], zc[1], siege0, "有" if zc[2] else "没有", "，已立股那行照旧" if zc[3] else ""])

	# ⑥ 围城米价 + ⑦ 战况通告：1276-12 开门降（通用句不改、海口不写市舶司）；再围两月米价撑住；再陷写城破、之后回落
	var fall0 := str(falls[0])
	var f0y := int(fall0.split("-")[0])
	var f0m := int(fall0.split("-")[1])
	var mark_seen := func() -> void:
		var ym_now := "%04d-%02d" % [Cal.year, Cal.month]
		for nw in GM.news_data.get("news", []):
			if str(nw.get("date", "9999-99")) <= ym_now:
				GS.mark_news_seen(str(nw.get("id", "")))
	GS.from_dict({})
	Cal.from_dict({"year": f0y if f0m > 1 else f0y - 1, "month": f0m - 1 if f0m > 1 else 12, "day": 28})
	mark_seen.call()
	var n1 := _notices.size()
	_advance_to(f0y, f0m)
	var first_fall := ""
	var harbor_first := ""
	for t in _notices.slice(n1):
		var s := str(t)
		if s.begins_with("【战况】兴化已降元"):
			first_fall = s
		if s.begins_with("【战况】") and s.find("海口") >= 0:
			harbor_first = s
	_check(first_fall != "", "首次城破 %s 兴化是开门降，通用「已降元」句不改（「%s」）" % [fall0, first_fall])
	# 海口通告只说海口换旗：同一天城那条已写了降元，海口不再把城降写一遍（09-29 复核）
	var harbor_first_ok := harbor_first.find("换了旗") >= 0 and harbor_first.find("降") < 0
	_check(harbor_first_ok,
		"首次城破 %s 兴化海口通告只说海口换旗、不把城降再写一遍（「%s」）" % [fall0, harbor_first])
	# 再围起点：再陷之前最后一个 besieged 键
	var siege1 := ""
	for k in wkeys:
		if str(war_x[k]) == "besieged" and str(k) < zan_fall:
			siege1 = str(k)
	var s1y := int(siege1.split("-")[0])
	var s1m := int(siege1.split("-")[1])
	GS.from_dict({})
	Cal.from_dict({"year": s1y if s1m > 1 else s1y - 1, "month": s1m - 1 if s1m > 1 else 12, "day": 28})
	mark_seen.call()
	for pid in ["xinghua", "xinghua_harbor", "quanzhou"]:
		if Eco.rates.has(pid) and Eco.rates[pid].has("grain"):
			Eco.rates[pid]["grain"] = 1.0
	var n2 := _notices.size()
	var p_before: int = Eco.buy_price("xinghua", "grain")
	var guard := 0
	while not (Cal.year == last_y and Cal.month == last_m and Cal.day >= 28) and guard < 400:
		GM.advance_days(1)
		guard += 1
	var r_siege: float = Eco.get_rate("xinghua", "grain")
	var r_peace: float = Eco.get_rate("quanzhou", "grain")
	var p_siege: int = Eco.buy_price("xinghua", "grain")
	_check(r_siege >= 1.7 and absf(r_peace - 1.0) < 0.05 and p_siege > p_before,
		"再围到 %d-%02d-28 兴化米行情仍撑在围城目标（%.3f ≥ 1.7，买价 %d→%d），不在围城的泉州回到平年（%.3f）" % [last_y, last_m, r_siege, p_before, p_siege, r_peace])
	_advance_to(zfy, zfm)
	var harbor_siege := ""
	var fall_xh := ""
	var fall_xhh := ""
	var bad_jiang := []
	for t in _notices.slice(n2):
		var s := str(t)
		if s.begins_with("【战况】") and s.find("海口的船还走得动") >= 0:
			harbor_siege = s
		if s.begins_with("【战况】兴化城破"):
			fall_xh = s
		if s.begins_with("【战况】兴化海口"):
			fall_xhh = s
		if s.begins_with("【战况】") and s.find("兴化") >= 0 and s.find("降元") >= 0:
			bad_jiang.append(s)
	_check(bad_jiang.is_empty(), "再围到再陷之间不发「兴化…降元」战况通告（%s）" % [bad_jiang])
	_check(harbor_siege != "", "再围 %s 兴化海口通告写城被围、海口的船还走得动（「%s」）" % [siege1, harbor_siege])
	# 再陷当天两条连发：城写城破巷战；海口只说海口换旗，不重抄城里的「兴化城破」「巷战」（09-29 复核）
	_check(fall_xh.find("巷战") >= 0 and fall_xhh.find("换了旗") >= 0 and fall_xhh.find("城破") < 0 and fall_xhh.find("巷战") < 0,
		"再陷 %s 兴化写城破巷战、海口只说海口换旗（「%s」／「%s」）" % [zan_fall, fall_xh, fall_xhh])
	var after_guard := 0
	while after_guard < 60:
		GM.advance_days(1)
		after_guard += 1
	var r_after: float = Eco.get_rate("xinghua", "grain")
	_check(r_after < 1.2, "城破后两个月兴化米行情按平年回落（%.3f < 1.2），不再按围城目标撑着" % r_after)

	# ⑨ 牙行闭门：不占今日三门、落进「未开」一排；闭门页只一句门闸，不写柜上三样、不开新委办（交货地是本港的在身委办另见下）
	var facs := [{"id": "city_market"}, {"id": "city_shipyard"}, {"id": "city_guild"}, {"id": "city_tavern"}, {"id": "city_inn"}]
	var dealt_shut: PackedStringArray = ShoreDraft.deal(facs, 0, false, false)
	var dealt_open: PackedStringArray = ShoreDraft.deal(facs, 0, false, true)
	_check(dealt_shut.size() == 3 and not ("city_market" in dealt_shut) and dealt_open[0] == "city_market",
		"ShoreDraft.deal：闭门的牙行不占席（%s），开门照旧占第一席（%s）" % [dealt_shut, dealt_open])
	reset_root.call(last_y, last_m, 10)
	var shut_btn := false
	var shut_row: Node = main._shore_band().get_node_or_null("ShoreShut")
	if shut_row != null:
		for b in shut_row.get_children():
			if b is Button and (b as Button).text == "牙行":
				shut_btn = true
	var regular_n := 0
	for fid in main.shore_hand:
		if str(fid).begins_with("city_"):
			regular_n += 1
	_check(not Eco.is_market_open("xinghua") and not ("city_market" in main.shore_hand) and shut_btn and regular_n >= 3,
		"兴化围城：牙行不在今日三门、在「未开」一排，三扇寻常门都给别处（名单 %s）" % [main.shore_hand])
	main.load_scene("xinghua_market")
	var body: String = main.body_text.text
	_check(body.find("门闸") >= 0 and body.find("柜上只摆三样") < 0 and main.find_child("ContractPanel", true, false) == null,
		"围城牙行页只写门闸一句、不写柜上三样、不出委办（「%s」）" % body.replace("\n", "⏎"))
	# 围城时交货地是本港的在身委办：委办 due_day 不停表，必须能交货，否则送兴化的委办撞上围城月就必逾期（09-29 复核 major）。
	# 「未开」一排的牙行点得进闭门页，页上只有在身委办那一行（交货 / 毁约），不开新委办、不写柜上三样；交得出货、钱到手
	var shut_market := func() -> Button:
		var row: Node = main._shore_band().get_node_or_null("ShoreShut")
		if row != null:
			for b in row.get_children():
				if b is Button and (b as Button).text.begins_with("牙行"):
					return b as Button
		return null
	var c_good := "lacquerware"
	for raw_g in GM.get_port_by_id("xinghua").get("market", {}).keys():
		if Eco.get_role("xinghua", str(raw_g)) == "consumer":
			c_good = str(raw_g)
			break
	reset_root.call(last_y, last_m, 10)
	var c_qty := 6
	GS.contract = {
		"good_id": c_good, "qty": c_qty, "remaining": c_qty, "dest": "xinghua", "from": "quanzhou",
		"purse": 600, "unit_purse": 100.0, "paid": 0, "due_day": Cal.absolute_day() + 5, "deadline_days": 12,
		"voyage_days": 5, "offer_month": Cal.year * 12 + Cal.month,
	}
	var c_have0: int = Flt.cargo_qty(c_good)
	Flt.add_cargo(c_good, c_qty, 10.0)
	main.load_scene("xinghua")
	var side: Button = shut_market.call()
	_check(side != null and not ("city_market" in main.shore_hand) and side.text.find("交货") >= 0 and side.tooltip_text.find("委办") >= 0,
		"围城 + 在身委办送兴化：牙行仍在「未开」一排、不占三门，门字写交货、悬停写明收委办货（「%s」／「%s」）" % [side.text if side != null else "无钮", side.tooltip_text.replace("\n", "⏎") if side != null else ""])
	if side != null:
		side.pressed.emit()
	var c_panel: Node = main.find_child("ContractPanel", true, false)
	var c_deliver: Button = null
	var c_take := false
	for b in main.find_children("*", "Button", true, false):
		if (b as Button).text == "交货":
			c_deliver = b as Button
		if (b as Button).text == "接下委办":
			c_take = true
	var c_body: String = main.body_text.text
	_check(main.current_scene_id == "xinghua_market" and c_panel != null and c_deliver != null and not c_deliver.disabled and not c_take
		and c_body.find("门闸") >= 0 and c_body.find("柜上只摆三样") < 0,
		"围城闭门页补出在身委办那一行、交货钮可按、不开新委办（页 %s，「%s」）" % [main.current_scene_id, c_body.replace("\n", "⏎")])
	var c_money0: int = GS.money
	if c_deliver != null:
		c_deliver.pressed.emit()
	_check(GS.contract.is_empty() and GS.money > c_money0 and Flt.cargo_qty(c_good) == c_have0,
		"围城时在兴化交清委办：委办结清、钱到手（%d→%d）、货卸下（舱里 %d），不逾期" % [c_money0, GS.money, Flt.cargo_qty(c_good)])
	# 在身委办送别处：闭门的牙行照旧点不进，只记门闸一句
	reset_root.call(last_y, last_m, 10)
	GS.contract = {
		"good_id": c_good, "qty": c_qty, "remaining": c_qty, "dest": "quanzhou", "from": "fuzhou",
		"purse": 600, "unit_purse": 100.0, "paid": 0, "due_day": Cal.absolute_day() + 5, "deadline_days": 12,
		"voyage_days": 5, "offer_month": Cal.year * 12 + Cal.month,
	}
	main.load_scene("xinghua")
	var other: Button = shut_market.call()
	if other != null:
		other.pressed.emit()
	_check(other != null and other.text == "牙行" and main.current_scene_id == "xinghua" and main._latest_log().find("门闸") >= 0,
		"委办交货地不在兴化：闭门的牙行门字照旧、点不进，只记门闸一句（页 %s，「%s」）" % [main.current_scene_id, main._latest_log()])
	GS.contract = {}
	# 海口不是城：海口牙行闭门页不写「城中」（09-29 复核）
	GS.last_port = "xinghua_harbor"
	main.load_scene("xinghua_harbor_market")
	var h_body: String = main.body_text.text
	_check(not Eco.is_market_open("xinghua_harbor") and h_body.find("门闸") >= 0 and h_body.find("海口") >= 0 and h_body.find("城中") < 0,
		"兴化海口牙行闭门页写海口的门闸，不写城中（「%s」）" % h_body.replace("\n", "⏎"))
	GS.last_port = "xinghua"
	GS.from_dict({})
	Cal.from_dict({"year": s1y if s1m > 1 else s1y - 1, "month": s1m - 1 if s1m > 1 else 12, "day": 10})
	GS.last_port = "xinghua"
	main.load_scene("xinghua_market")
	_check(Eco.is_market_open("xinghua") and main.body_text.text.find("柜上只摆三样") >= 0 and main.find_child("ContractPanel", true, false) != null,
		"开秤的兴化牙行照旧写柜上三样、出委办")

	# ⑪ 设施页题头字号：先走序章 cg_ 对白页（24），再进设施页，题头回到 SIZE_HEAD
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	main.load_scene("cg_veteran")
	var cg_px: int = main.scene_title.get_theme_font_size("font_size")
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou_market")
	var fac_px: int = main.scene_title.get_theme_font_size("font_size")
	_check(cg_px == 24 and fac_px == UiTheme.SIZE_HEAD,
		"序章 cg_ 页题头 24 照旧（%d），之后进牙行题头是 SIZE_HEAD（%d，应 %d）" % [cg_px, fac_px, UiTheme.SIZE_HEAD])

	# ⑧ n_1277_07 传闻：泉州当时照常开市（战况表不改），传闻不把张世杰围泉州写成已落地
	var rumor: Dictionary = GM.get_news_by_id("n_1277_07_xinghua_again")
	var rumor_ym := str(rumor.get("date", ""))
	var rty := int(rumor_ym.split("-")[0]) if rumor_ym != "" else 0
	var rtm := int(rumor_ym.split("-")[1]) if rumor_ym != "" else 0
	Cal.from_dict({"year": rty, "month": rtm, "day": 5})
	var qz_open: bool = Eco.is_market_open("quanzhou") and not (Eco.war_status("quanzhou") in ["besieged", "contested"])
	var rt := str(rumor.get("text", ""))
	_check(not qz_open or (rt.find("围了泉州") < 0 and rt.find("闭城") < 0 and rt.find("泉州") >= 0),
		"%s 泉州照常开市（%s）时，传闻只写张世杰要去打泉州、不写已围城闭城（「%s」）" % [rumor_ym, Eco.war_status("quanzhou"), rt])
	# ⑩ 过场 ending_root：泊澳那句字幕从出现到镜末 ≥3.5 秒（修前 2.6，实录在屏 2.3 秒读不完）
	var cs_all: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes.json"))
	var moor_left := -1.0
	if cs_all is Dictionary:
		for shot in ((cs_all as Dictionary).get("cutscenes", {}).get("ending_root", {}).get("shots", []) as Array):
			for cap in (shot as Dictionary).get("captions", []):
				if str(cap.get("text", "")).find("旧避风澳泊了六天") >= 0:
					moor_left = float(shot.get("duration", 0.0)) - float(cap.get("t", 0.0))
	_check(moor_left >= 3.5, "ending_root「船在旧避风澳泊了六天」字幕到镜末 %.1f 秒（≥3.5）" % moor_left)
	GS.from_dict({})
	Flt.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_close_dialogs(main)


## ── 士人线守城与「忠肃」（09-28 验收 siege 线 + crew 线林华几条的修复）──
## 候日日志次序与守城句；城破前告急与城破那天的日志；第三阵战报先出、按「回城」后才城破；战报眉题 / 钮 / 大题；
## 关城门一支（铺垫、林华缒城出降、过场第 2 镜按旗换句、不推日子不提天数）；忠肃题头并入原因、落款按城破时点 / 当日；
## 海口不开守城页、给「入城」卡；旧档排岸带之前先结算；守城 / 终局页不出抵港挂签；小件文案；林华守城页。
## 日期都从兴化战况表的首守城破时点倒推（main._siege_fall_point），不写死。
func _v0928_siege_check(main: Node) -> void:
	var Crw: Node = root.get_node("Crew")
	var Art = load("res://scripts/ui/CharacterArt.gd")
	var fp: Dictionary = main._siege_fall_point()
	_check(not fp.is_empty() and str(fp.get("month", "")) != "", "首守城破时点推得出历法写法（%s）" % [fp])
	if fp.is_empty():
		return
	var fall_abs: int = int(fp["abs"])
	var signoff := "%s　%s・%s" % [fp["era"], fp["month"], GM.get_port_name("xinghua")]
	var dire_days: int = main.SIEGE_DIRE_DAYS
	# 1. 寻常港页候日：候日那句先写、再推日子，跨月时当天的月初通告排在它上面
	_v0928_siege_scholar(Crw, fall_abs - 31)
	GS.identity = "merchant"
	GS.flags.erase("renamed_wenlong")
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	Cal.from_dict({"year": Cal.year, "month": Cal.month, "day": Cal.DAYS_PER_MONTH})
	main._log_lines.clear()
	var n_note := _notices.size()
	main._on_shore_wait()
	var wl: Array = main._log_lines
	var fresh: int = _notices.size() - n_note
	var wait_at := wl.find("在岸上又候了一日，门又换了几处。")
	# 候日那句必须还在、且是最下一行：通告多到会把它顶出 LOG_KEEP 时整串折成一行（lane fx7），不再许挤出去
	_check(Cal.day == 1 and fresh >= 1 and not wl.is_empty() and wait_at > 0 and wait_at == wl.size() - 1,
		"寻常港页候日跨月：月初通告 %d 条排在候日那句上面，候日句仍在记事栏（第 %d 行 / 共 %d 行，顶行「%s」）" % [fresh, wait_at, wl.size(), wl[0] if not wl.is_empty() else ""])
	# 2. 守城页候日：换守城句，不写「门又换了几处」
	_v0928_siege_scholar(Crw, fall_abs - dire_days - 5)
	main.load_scene("xinghua")
	main._log_lines.clear()
	main._on_shore_wait()
	var sl: Array = main._log_lines
	_check(main._shore_mode == "siege" and not sl.is_empty() and str(sl[0]) == "城上又守了一日。" and sl.find("在岸上又候了一日，门又换了几处。") < 0,
		"守城页候一日写「城上又守了一日。」，不写门又换了几处（%s）" % [sl])
	# 3. 城破前告急：离城破时点 SIEGE_DIRE_DAYS 日起城防账多一行，再早一日没有
	for off in [dire_days + 1, dire_days, 1]:
		Cal.from_dict(_v0928_siege_cal(fall_abs - off))
		main.load_scene("xinghua")
		var dire: String = _find_label_text(main._shore_band(), "援兵音信断绝")
		var want: bool = off <= dire_days
		_check((dire != "") == want and (dire == "" or dire.find(str(fp["month"])) >= 0),
			"城破前 %d 日（%s）城防账%s告急行（「%s」）" % [off, Cal.get_date_string(), "有" if want else "没有", dire])
		# 城是那个月初一破的：写「捱不过」那个月，不写「捱不到」
		_check(dire == "" or (dire.find("捱不过" + str(fp["month"])) >= 0 and dire.find("捱不到") < 0),
			"告急行写「捱不过%s」（「%s」）" % [fp["month"], dire])
	# 4. 候日到城破：城破那天先记一句，再按「援绝」结算；题头并入原因、正文首行不带括注、落款是城破时点
	Cal.from_dict(_v0928_siege_cal(fall_abs - 2))
	main.load_scene("xinghua")
	var waited := 0
	while not GS.is_ended() and waited < 10:
		main._on_shore_wait()
		waited += 1
	var fl: Array = main._log_lines
	var top := str(fl[0]) if not fl.is_empty() else ""
	var head := _find_label_text(main.get("_chapter_host"), "忠肃　")
	_check(GS.ended == "忠肃" and top.begins_with(str(fp["month"])) and top.ends_with("援兵没有来。"),
		"候到城破那天：日志顶行先记「%s」，再结算「%s」" % [top, GS.ended])
	_check(head.find("十二月・援绝") >= 0 and GS.ended_at == signoff,
		"候过城破时点：题头「%s」并入援绝、落款「%s」是城破时点（应 %s）" % [head, GS.ended_at, signoff])
	_v0928_siege_first_line(main, "援绝")
	main._confirm_chapter_sheet()
	_v0928_siege_epi_at(main, "援绝")
	# 5. 粮尽：当场打破，题头写到冬、落款照当日
	_v0928_siege_scholar(Crw, fall_abs - 20)
	main.load_scene("xinghua")
	GS.siege_set("grain", 0)
	main.load_scene("xinghua")
	_check(_find_label_text(main._shore_band(), "一阵也不够") != "" and _find_label_text(main._shore_band(), "零阵") == "",
		"粮 0 时城防账写「一阵也不够」，不写「够打零阵」")
	var today: String = Cal.get_date_string()
	main._on_facility_pressed({"id": "siege_nangshan"})
	head = _find_label_text(main.get("_chapter_host"), "忠肃　")
	_check(GS.ended == "忠肃" and head.find("冬・粮尽") >= 0 and head.find("十二月") < 0 and GS.ended_at.begins_with(today),
		"粮尽当场城破：题头「%s」写到冬、落款「%s」照当日" % [head, GS.ended_at])
	_v0928_siege_first_line(main, "粮尽")
	main._confirm_chapter_sheet()
	_v0928_siege_epi_at(main, "粮尽")
	# 6. 战报册页：眉题「战报」、钮「回城」、大题中文数字不重复「囊山」；第一阵按钮后仍在守城
	_v0928_siege_scholar(Crw, fall_abs - 20)
	main.load_scene("xinghua")
	main._on_facility_pressed({"id": "siege_nangshan"})
	var host: Node = main.get("_chapter_host")
	var rhead := _find_label_text(host, "囊山・")
	_check(rhead.begins_with("囊山・第一阵　") and rhead.count("囊山") == 1 and _find_label_text(host, "战报") == "战报"
			and _v0928_siege_btn(host, "回城") != null and _v0928_siege_btn(host, "记下这一纲") == null and _find_label_text(host, "了结") == "",
		"战报册页：大题「%s」、眉题「战报」、钮「回城」，不用结局口吻" % rhead)
	main._confirm_chapter_sheet()
	_check(not GS.is_ended() and main._shore_mode == "siege", "第一阵战报按「回城」后回到守城页")
	# 7. 第三阵：先出战报，按钮之前不城破；按「回城」后才走城破「力竭」
	GS.siege_set("round", GS.SIEGE_ROUNDS_MAX - 1)
	GS.siege_set("grain", GS.SIEGE_GRAIN_PER_ROUND * 2)
	GS.siege_set("lin_hua_sent", true)
	main.load_scene("xinghua")
	today = Cal.get_date_string()
	main._on_facility_pressed({"id": "siege_nangshan"})
	host = main.get("_chapter_host")
	rhead = _find_label_text(host, "囊山・")
	_check(not GS.is_ended() and rhead.begins_with("囊山・第%s阵　" % main._cn_num(GS.SIEGE_ROUNDS_MAX)) and _find_label_text(host, "这是最后一阵") != ""
			and str(GS.siege.get("pending_fall", "")) != "",
		"第三阵：战报「%s」先出，按钮之前不城破（结局「%s」）" % [rhead, GS.ended])
	main._confirm_chapter_sheet()
	head = _find_label_text(main.get("_chapter_host"), "忠肃　")
	_check(GS.ended == "忠肃" and head.find("冬・力竭") >= 0 and head.find("三阵毕") < 0 and GS.ended_at.begins_with(today),
		"第三阵战报按「回城」后才城破：题头「%s」写「力竭」、落款「%s」照当日" % [head, GS.ended_at])
	_v0928_siege_first_line(main, "力竭")
	main._confirm_chapter_sheet()
	# 7b. 重读结局：大题照初读写（「忠肃　兴化・景炎元年冬・力竭」），城破原因不只露一次；存档来回不丢；札记抬头仍旁注落款
	var saved_head: String = GS.ended_head
	GS.from_dict(GS.to_dict())
	_check(saved_head.find("力竭") >= 0 and GS.ended_head == saved_head, "忠肃大题那截存档来回不丢（「%s」→「%s」）" % [saved_head, GS.ended_head])
	main.load_scene("xinghua")
	_v0928_siege_epi_at(main, "力竭")
	main._on_reread_ending()
	var reread := _find_label_text(main.get("_chapter_host"), "忠肃　")
	_check(reread == "忠肃　%s" % saved_head and reread.find("力竭") >= 0 and _find_label_text(main.get("_chapter_host"), "重读") != "",
		"力竭一局重读结局：大题「%s」看得到城破原因" % reread)
	main._confirm_chapter_sheet()
	# 8. 关城门一支：铺垫不写门已开、不提天数不推日子；林华缒城出降；城破句与过场第 2 镜按 cao_opened 换句
	_v0928_siege_scholar(Crw, fall_abs - 20)
	main.load_scene("xinghua")
	GS.siege_set("round", GS.SIEGE_ROUNDS_MAX - 1)
	GS.siege_set("grain", GS.SIEGE_GRAIN_PER_ROUND * 3)
	main.load_scene("xinghua")
	main._on_facility_pressed({"id": "siege_nangshan"})
	var day0: int = Cal.absolute_day()
	var shut := _v0928_siege_btn(main, "不去。关城门")
	_check(shut != null and shut.text.find("谁也不出") < 0, "第三阵前林华请命页有「不去。关城门」，钮上不写「谁也不出」（囊山第三阵照样能出城）")
	var grain0: int = GS.siege_get("grain")
	if shut != null:
		shut.pressed.emit()
	var cl := str(main._log_lines[0]) if not main._log_lines.is_empty() else ""
	var grain_lost: int = grain0 - GS.siege_get("grain")
	_check(not GS.is_ended() and main._shore_mode == "siege" and Cal.absolute_day() == day0 and cl.find("缒") >= 0
			and cl.find("开了") < 0 and cl.find("七天") < 0 and cl.find("第八天") < 0,
		"关城门：城还在、日历不动，日志只作铺垫（「%s」）" % cl)
	# 同一局三处对得上：日志不说林华「再没有回来」（过场写「回来时，身后是元兵」、城破句写他领元兵回到城下），
	# 也不写还没到的「当夜」；城防账少的粮，日志照数交代
	_check(cl.find("再没有回来") < 0 and cl.find("当夜") < 0
			and (grain_lost == 0 or cl.find("丢了%s石米" % main._cn_num(grain_lost)) >= 0),
		"关城门日志不和过场、城破句打架，少的 %d 石粮有交代（「%s」）" % [grain_lost, cl])
	main._on_facility_pressed({"id": "siege_nangshan"})
	main._confirm_chapter_sheet()
	var cao_first: String = str(GS.ended_text).split("\n")[0]
	_check(GS.ended == "忠肃" and cao_first.find("缒城") >= 0 and cao_first.find("曹澄孙开了东门") >= 0,
		"关城门一支城破句写林华缒城出降、曹澄孙开东门（「%s」）" % cao_first)
	var cs: Dictionary = {}
	var f := FileAccess.open("res://data/cutscenes.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			cs = parsed
	var zs: Dictionary = cs.get("cutscenes", {}).get(str(cs.get("endings", {}).get("忠肃", "")), {})
	var shot2: Array = (zs.get("shots", []) as Array)[1].get("captions", []) if (zs.get("shots", []) as Array).size() > 1 else []
	var CP = load("res://scripts/cutscene/CutscenePlayer.gd")
	var probe: Node = CP.new()
	var seen_cao := _v0928_siege_caps(probe, shot2)
	GS.flags.erase("cao_opened")
	var seen_plain := _v0928_siege_caps(probe, shot2)
	probe.free()
	_check(seen_cao.find("缒城") >= 0 and seen_cao.find("出城侦敌") < 0 and seen_plain.find("出城侦敌") >= 0 and seen_plain.find("缒城") < 0,
		"忠肃过场第 2 镜按 cao_opened 换句（关城门「%s」／放出侦「%s」）" % [seen_cao, seen_plain])
	main._confirm_chapter_sheet()
	# 9. 林华守城页：雇过的正文与日志；没雇过的也记为已识
	_v0928_siege_scholar(Crw, fall_abs - 20)
	GS.crew_history = ["lin_hua"]
	main.load_scene("xinghua")
	main._siege_lin_hua()
	_check(str(main.body_text.text).find("后来在你的船上把过舵。缆绳系得很好。") >= 0, "雇过林华：守城页正文提他在你船上把过舵")
	var rope := _v0928_siege_btn(main, "你的缆绳系得好")
	if rope != null:
		rope.pressed.emit()
	_check(not main._log_lines.is_empty() and str(main._log_lines[0]) == "他愣了一下，说大人还记得。城头的人见你叫得出自家旧舵工的名字，士气 +5。",
		"缆绳钮后的日志用「自家旧舵工」一句（%s）" % [main._log_lines[0] if not main._log_lines.is_empty() else ""])
	_v0928_siege_scholar(Crw, fall_abs - 20)
	GS.met_ids.erase("lin_hua")
	main.load_scene("xinghua")
	main._siege_lin_hua()
	_check(GS.has_met("lin_hua") and not ("lin_hua" in GS.crew_history), "没雇过林华：守城页当面见过即记为已识（记进 GameState.met_ids，随存档）")
	# 10. 海口不开守城页：给「入城」卡，点了进兴化城开守城页；守城内页「离开」回城里
	_v0928_siege_scholar(Crw, fall_abs - 20)
	GS.last_port = "xinghua_harbor"
	main.load_scene("xinghua_harbor")
	_check(main._shore_mode == "port" and not GS.siege_open() and "siege_enter" in main.shore_hand and not ("siege_muster" in main.shore_hand),
		"围城月兴化海口是寻常港页、有「入城」卡、不开城防（页型 %s，名单 %s）" % [main._shore_mode, main.shore_hand])
	var enter_sub := _v0928_siege_card_sub(main, "siege_enter")
	_check(enter_sub.find("你该在城里") >= 0 and enter_sub.find("捱不过") < 0, "城破前 20 日海口「入城」卡副题是平日提醒（「%s」）" % enter_sub)
	main._on_facility_pressed({"id": "siege_enter"})
	_check(main.current_scene_id == "xinghua" and main._shore_mode == "siege" and GS.siege_open(),
		"点「入城」进兴化城开守城页（%s / %s）" % [main.current_scene_id, main._shore_mode])
	main._on_facility_pressed({"id": "siege_grain"})
	var leave := _v0928_siege_btn(main, "离开")
	if leave != null:
		leave.pressed.emit()
	_check(main.current_scene_id == "xinghua" and main._shore_mode == "siege", "守城内页「离开」回兴化城的守城页（%s）" % main.current_scene_id)
	for c in [[fall_abs - 50, "scholar"], [fall_abs - 20, "merchant"]]:
		_v0928_siege_scholar(Crw, int(c[0]))
		if str(c[1]) != "scholar":
			GS.identity = str(c[1])
			GS.flags.erase("renamed_wenlong")
		main.load_scene("xinghua_harbor")
		_check(not ("siege_enter" in main.shore_hand), "兴化海口 %s（%s）没有「入城」卡" % [Cal.get_date_string(), c[1]])
	# 10b. 海口城破前 SIEGE_DIRE_DAYS 日内：「入城」卡副题换告急口吻；候进城破那个月（不点「入城」）当下就结「未归」，
	# 首句按海口写（人就在城外），册页底下岸带已清，不冒出新月的寻常卡
	_v0928_siege_scholar(Crw, fall_abs - dire_days + 1)
	GS.last_port = "xinghua_harbor"
	main.load_scene("xinghua_harbor")
	enter_sub = _v0928_siege_card_sub(main, "siege_enter")
	_check(enter_sub.find("捱不过" + str(fp["month"])) >= 0, "海口城破前 %d 日内「入城」卡副题告急（%s「%s」）" % [dire_days, Cal.get_date_string(), enter_sub])
	Cal.from_dict(_v0928_siege_cal(fall_abs - 1))
	main.load_scene("xinghua_harbor")
	var sheet_before: bool = is_instance_valid(main.get("_chapter_host"))
	main._on_shore_wait()
	var wg: String = str(GS.ended_text).split("\n")[0]
	_check(not sheet_before and GS.ended == "未归" and Cal.absolute_day() == fall_abs and is_instance_valid(main.get("_chapter_host"))
			and main.shore_hand.is_empty() and wg.begins_with("消息是从城里传出来的"),
		"海口候进城破那个月：当下结「%s」、首句「%s」、岸带已清（%s）" % [GS.ended, wg, main.shore_hand])
	# 结局过场第 1 镜同句按 weigui_at_harbor 换：海口结算写「从城里传出来」，别处照旧「在别处听到」
	var wz: Dictionary = cs.get("cutscenes", {}).get(str(cs.get("endings", {}).get("未归", "")), {})
	var wshots: Array = wz.get("shots", [])
	var wcap: Array = (wshots[0] as Dictionary).get("captions", []) if not wshots.is_empty() else []
	var wprobe: Node = CP.new()
	var w_harbor := _v0928_siege_caps(wprobe, wcap)
	var had_flag: bool = GS.has_flag("weigui_at_harbor")
	# 同镜底图按同一旗换（lane fx5：bg_alt，CutscenePlayer._shot_view）：海口结算取兴化海口港页图，别处照旧本镜海上图
	var wshot0: Dictionary = wshots[0] if not wshots.is_empty() and typeof(wshots[0]) == TYPE_DICTIONARY else {}
	var wview_harbor: Dictionary = wprobe.call("_shot_view", wshot0)
	GS.flags.erase("weigui_at_harbor")
	var w_else := _v0928_siege_caps(wprobe, wcap)
	var wview_else: Dictionary = wprobe.call("_shot_view", wshot0)
	wprobe.free()
	var harbor_bg := "res://assets/" + str((main.get_script() as Script).get_script_constant_map().get("PORT_BG", {}).get("xinghua_harbor", "?"))
	_check(had_flag and str(wview_harbor["bg"]) == harbor_bg and str(wview_else["bg"]) == str(wshot0.get("bg", ""))
			and str(wview_else["bg"]).ends_with("bg_sea_route.jpg") and wview_harbor["cam_from"] != wview_else["cam_from"],
		"未归过场第 1 镜底图按海口换（海口 %s／别处 %s；港页图 %s）" % [wview_harbor["bg"], wview_else["bg"], harbor_bg])
	_check(had_flag and w_harbor.find("从城里传出来") >= 0 and w_harbor.find("在别处") < 0 and w_else.find("在别处听到") >= 0 and w_else.find("从城里") < 0,
		"未归过场第 1 镜按海口换句（海口「%s」／别处「%s」）" % [w_harbor, w_else])
	main._confirm_chapter_sheet()
	_check(main._shore_kind_now == "ended", "海口「未归」合上册页是终局港页（%s）" % main._shore_kind_now)
	# 10c. 海口旧档：城防开着、还没到城破时点，读回海口直接入城开守城页（不给带「看风」的寻常港页、不能带着城防出海）
	_v0928_siege_scholar(Crw, fall_abs - 20)
	GS.siege_begin()
	GS.last_port = "xinghua_harbor"
	main._log_lines.clear()
	main.load_scene("xinghua_harbor")
	_check(main.current_scene_id == "xinghua" and main._shore_mode == "siege" and GS.siege_open() and not GS.is_ended()
			and _v0928_siege_btn(main._shore_band(), "看风") == null and main._log_lines.has(main.SIEGE_ENTER_LOG),
		"海口旧档城防开着：读档后进的是城里的守城页（%s / %s，日志 %s）" % [main.current_scene_id, main._shore_mode, main._log_lines])
	# 11. 抵港挂签只在寻常港页出：守城 / 终局页不出
	_v0928_siege_scholar(Crw, fall_abs - 20)
	main.load_scene("xinghua")
	var kind_siege: String = main._shore_kind_now
	main.load_scene("quanzhou")
	_check(kind_siege == "siege" and main._shore_kind_now == "port", "进港页型：守城页 %s、寻常港页 %s（抵港挂签只给寻常港页）" % [kind_siege, main._shore_kind_now])
	# 12. 旧档：城防开着、日历过了城破时点，读进兴化——排岸带之前先结算，底下没有带「看风」的寻常港页
	for port in ["xinghua", "quanzhou"]:
		_v0928_siege_scholar(Crw, fall_abs - 20)
		GS.siege_begin()
		Cal.from_dict(_v0928_siege_cal(fall_abs + 9 * Cal.DAYS_PER_MONTH + 2))
		GS.last_port = port
		main.load_scene(port)
		var sail := _v0928_siege_btn(main._shore_band(), "看风")
		head = _find_label_text(main.get("_chapter_host"), "忠肃　")
		_check(GS.ended == "忠肃" and sail == null and head.find("十二月・援绝") >= 0 and GS.ended_at == signoff,
			"旧档 %s 读进%s：先结算、岸带没排寻常港页，题头「%s」、落款「%s」" % [Cal.get_date_string(), port, head, GS.ended_at])
		main._confirm_chapter_sheet()
		_check(main._shore_kind_now == "ended", "旧档结算后合上册页是终局港页（%s）" % main._shore_kind_now)
	# 13. 小件文案：石手军、使者、米价、衙门分节小题
	_v0928_siege_scholar(Crw, fall_abs - 20)
	main.load_scene("xinghua")
	main._on_facility_pressed({"id": "siege_muster"})
	var sep_fs := 0
	for ch in main.choices_container.get_children():
		if ch is Label and (ch as Label).text.find("石手军") >= 0 and (ch as Label).text.begins_with("──"):
			sep_fs = (ch as Label).get_theme_font_size("font_size")
	_check(sep_fs >= 16, "衙门页「石手军」分节小题 ≥16px（%d）" % sep_fs)
	var keep := _v0928_siege_btn(main, "重编石手军")
	if keep != null:
		keep.pressed.emit()
	var ml := str(main._log_lines[0]) if not main._log_lines.is_empty() else ""
	_check(ml.find("从这天起") >= 0 and ml.find("五个月") < 0, "重编石手军日志不写「五个月」（%s）" % ml)
	main._on_facility_pressed({"id": "siege_envoy"})
	var eb := str(main.body_text.text)
	_check(eb.find("知福州王刚中") >= 0 and eb.find("福州知军") < 0 and eb.find("开了城门") < 0 and eb.find("缒下绳去") >= 0,
		"城下使者：「知福州王刚中」、缒绳吊上来，不写开城门")
	main.load_scene("xinghua")
	main._on_facility_pressed({"id": "siege_grain"})
	var gb := str(main.body_text.text)
	_check(gb.find("米价跟着仗走，打一阵涨一截") >= 0 and gb.find("一天一个样") < 0, "市场正文：米价按阵数涨，不写一天一个样")
	_check(gb.count("每打一阵") <= 1, "市场正文相邻两行不都以「每打一阵」起（%d 处）" % gb.count("每打一阵"))
	var buy := _v0928_siege_btn(main, "屯粮")
	if buy != null:
		buy.pressed.emit()
	var bl := str(main._log_lines[0]) if not main._log_lines.is_empty() else ""
	_check(bl.find("一天一个样") < 0 and bl.find("明日") < 0 and bl.find("涨一截") >= 0, "买粮日志和米价机制对得上（%s）" % bl)
	GS.from_dict({})
	Crw.from_dict({})


## 士人线改名、守城那年、城防没开的局面；日历拨到绝对日 abs_day
func _v0928_siege_scholar(Crw: Node, abs_day: int) -> void:
	GS.from_dict({})
	Crw.from_dict({})
	GS.set_flag("renamed_wenlong")
	GS.identity = "scholar"
	GS.money = 20000
	GS.fame = 30
	GS.last_port = "xinghua"
	Cal.from_dict(_v0928_siege_cal(abs_day))


## 绝对日 → 历法（Calendar.absolute_day 的逆：每月 30 日、每年 12 月、自 1255 正月初一起）
func _v0928_siege_cal(abs_day: int) -> Dictionary:
	var dpm: int = Cal.DAYS_PER_MONTH
	var mpy: int = Cal.MONTHS_PER_YEAR
	var months: int = abs_day / dpm
	return {"year": 1255 + months / mpy, "month": months % mpy + 1, "day": abs_day % dpm + 1}


## 忠肃册页正文首行：不带括注，也不把原因写进正文；原因记进 ended_head，航海札记「终局」一行照初读大题写
func _v0928_siege_first_line(main: Node, word: String) -> void:
	var first: String = str(GS.ended_text).split("\n")[0]
	_check(first.find("（") < 0 and first.find(word) < 0, "忠肃（%s）正文首行不带括注（「%s」）" % [word, first])
	_check(GS.ended_head.find(word) >= 0 and GS.epilogue_lines().has("终局：忠肃　%s" % GS.ended_head),
		"终局札记照初读大题写城破原因（大题那截「%s」，札记 %s）" % [GS.ended_head, GS.epilogue_lines().slice(2, 3)])


## 合上忠肃册页后的终局港页：札记抬头仍旁注落款（「终局」一行不再括落款，落款只在抬头）
func _v0928_siege_epi_at(main: Node, word: String) -> void:
	_check(main._shore_kind_now == "ended" and GS.ended_at != "" and _find_label_text(main._shore_band(), GS.ended_at) != "",
		"忠肃（%s）终局港页札记抬头旁注落款「%s」" % [word, GS.ended_at])


## 岸带上某张卡的副题（按 id 从 _shore_facilities 取）
func _v0928_siege_card_sub(main: Node, card_id: String) -> String:
	for fac in main._shore_facilities:
		if typeof(fac) == TYPE_DICTIONARY and str((fac as Dictionary).get("id", "")) == card_id:
			return str((fac as Dictionary).get("subtitle", ""))
	return ""


## 递归找看得见的钮（含 needle）
func _v0928_siege_btn(node: Node, needle: String) -> Button:
	if node == null or not is_instance_valid(node):
		return null
	if node is Button and (node as Button).text.find(needle) >= 0 and (node as Button).visible:
		return node as Button
	for c in node.get_children():
		var r := _v0928_siege_btn(c, needle)
		if r != null:
			return r
	return null


## 过场一镜的字幕里，按当前旗标会出的几句，连成一串
func _v0928_siege_caps(probe: Node, caps: Array) -> String:
	var out := PackedStringArray()
	for c in caps:
		if typeof(c) == TYPE_DICTIONARY and bool(probe.call("_caption_on", c)):
			out.append(str((c as Dictionary).get("text", "")))
	return "／".join(out)


# ══ SCRIPT ERROR / Parse Error 判红（lane w19-g11）══════════════════════════
## 运行中出 SCRIPT ERROR（含 Parse Error / Compile Error）也算失败：原先被依赖脚本解析失败、检查函数中途报错跳出，
## 那一段断言整段没跑、fails 不涨，退出码照样 0（实测 BoardingStage.gd 坏一行：Parse Error 7 条、OK 483 → 440、fails=0）。
## 计数器在 _init 挂上（早于 _initialize 与首帧抵港路由），_process 收尾调 _script_error_check 判。
var _script_errs: _ScriptErrTally = null


## 只数 SCRIPT ERROR 类（引擎把 Parse Error / Compile Error / 运行期脚本报错都记成这一类）；ERROR / WARNING 不计——
## 基线收尾时的「Lambda capture … was freed」与退出时资源泄漏都是 ERROR 类，且在 SUMMARY 之后，不归本门禁判。
class _ScriptErrTally extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		lines.append("%s（%s:%d）" % [rationale if rationale != "" else code, file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	_script_errs = _ScriptErrTally.new()
	OS.add_logger(_script_errs)


## 收尾前：本进程跑到这里有没有 SCRIPT ERROR / Parse Error（lane w19-g11）。先自证计数器只认脚本类：
## 喂一条假 SCRIPT 类、一条假 ERROR 类、一条假 WARNING 类给一只新计数器，须恰数到 1 条；再判真计数为 0。
func _script_error_check() -> void:
	var probe := _ScriptErrTally.new()
	probe._log_error("f", "res://x.gd", 1, "", "自证 SCRIPT", false, Logger.ERROR_TYPE_SCRIPT, [])
	probe._log_error("f", "res://x.gd", 2, "", "自证 ERROR", false, Logger.ERROR_TYPE_ERROR, [])
	probe._log_error("f", "res://x.gd", 3, "", "自证 WARNING", false, Logger.ERROR_TYPE_WARNING, [])
	_check(probe.lines.size() == 1, "SCRIPT ERROR 计数器自证：只数脚本类（喂 SCRIPT / ERROR / WARNING 各一，数到 %d）" % probe.lines.size())
	OS.remove_logger(_script_errs)
	var errs: Array = _script_errs.lines
	_check(errs.is_empty(), "运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
		"" if errs.is_empty() else "，首条：" + str(errs[0])])


## w19-g13（用户验图「比例尺也太大了 都看不到海岸线了」）：海图自动取景的默认缩放落在合理范围。
## 一、MapView.FRAME_ZOOM_MAX 在 1.0—1.6（再大一屏只剩港湾一角、底图发糊；再小近港港名挤成一团），且低于滚轮上限 ZOOM_MAX；
## 二、近港短程照发舶取景（起讫两港、pad 0.30）：缩放不超 FRAME_ZOOM_MAX，图带里两港都在、露出一段岸线（岸线折点 ≥ 40）；
## 三、玩家滚轮照样放得到 ZOOM_MAX（只改自动取景，不收玩家的缩放）；
## 四、海战镜头（用户也可能指海战那一屏）：旗舰镜头默认 zoom 0.35—0.6、开战刷船不少于两倍船长且在镜头半高内；
## 五、海战雷达比例：开战刷船处（COMBAT_SPAWN_DIST_MIN）落在本船脉动圈 9 px 之外，敌船遁走离场距离仍在盘内且用到盘半径六成以上。
func _g13_chart_zoom_check() -> void:
	var mv_c: Dictionary = (load("res://scripts/chart/MapView.gd") as GDScript).get_script_constant_map()
	var fz := float(mv_c.get("FRAME_ZOOM_MAX", INF))
	var zmin := float(mv_c.get("ZOOM_MIN", 0.0))
	var zmax := float(mv_c.get("ZOOM_MAX", 0.0))
	_check(fz >= 1.0 and fz <= 1.6 and fz < zmax,
		"海图自动取景缩放上限 FRAME_ZOOM_MAX=%.2f 落在 1.0—1.6、低于滚轮上限 ZOOM_MAX=%.2f" % [fz, zmax])
	GS.from_dict({})
	GS.chapter = 4
	GS.last_port = "quanzhou"
	var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	var map = sc.get("map")
	var cam: Camera2D = map.get("camera") if map != null else null
	_check(map != null and cam != null, "海图 MapView 与镜头挂上")
	if map == null or cam == null:
		sc.queue_free()
		GS.from_dict({})
		return
	# headless 这一帧还没排版：照工程画布把海图子视口铺成 1280×720，顶匾压 104、牌区压 280（DISPLAY=:2 实测）直接写进去
	var mvp := map.get_viewport() as SubViewport
	mvp.size = Vector2i(1280, 720); mvp.size_2d_override = Vector2i(1280, 720)
	map.call("set_view_inset", 104.0, 280.0)
	var vp_size: Vector2 = map.get_viewport_rect().size
	_check(vp_size.is_equal_approx(Vector2(1280, 720)), "海图子视口按 1280×720 取景（实得 %s）" % vp_size)
	var pp: Dictionary = map.get("port_px")
	for pair in [["quanzhou", "xinghua"], ["xinghua", "xinghua_harbor"], ["quanzhou", "zhangzhou"], ["hakata", "kagoshima"]]:
		map.call("frame_ports", pair, 0.30, 0.0)
		var z := cam.zoom.x
		var band: Rect2 = map.call("_band_world_rect")
		var both: bool = pp.has(pair[0]) and pp.has(pair[1]) and band.has_point(pp[pair[0]]) and band.has_point(pp[pair[1]])
		var coast_n := 0
		for ring in map.get("coast_rings"):
			for v in ring:
				if band.has_point(v):
					coast_n += 1
		_check(z >= zmin and z <= fz + 0.001 and both and coast_n >= 40,
			"近港发舶取景 %s—%s：缩放 %.2f ≤ %.2f，两港在图带内（%s），图带露出岸线折点 %d（≥ 40）" % [pair[0], pair[1], z, fz, both, coast_n])
	map.call("zoom_at", cam.position, 100.0)
	_check(absf(cam.zoom.x - zmax) < 0.001, "滚轮仍放得到 ZOOM_MAX %.2f（实得 %.2f）" % [zmax, cam.zoom.x])
	sc.queue_free()
	GS.from_dict({})
	# 海战镜头（Ship.tscn 旗舰 Camera2D）：拉远到能同屏看清两船相对方位；开战刷船不少于两倍船长（船长约 280 px，Ballistics 头注）
	var ship_c: Dictionary = (load("res://scripts/Ship.gd") as GDScript).get_script_constant_map()
	var ship_n: Node = (load("res://scenes/Ship.tscn") as PackedScene).instantiate()
	var sc_cam := ship_n.get_node_or_null("Camera2D") as Camera2D
	var cz := sc_cam.zoom.x if sc_cam != null else 0.0
	ship_n.free()
	var rest := float(ship_c.get("CAM_ZOOM_REST", 0.0))
	var full := float(ship_c.get("CAM_ZOOM_FULL", 0.0))
	_check(cz >= 0.35 and cz <= 0.6 and absf(cz - rest) < 0.001 and full > 0.3 and full <= rest,
		"海战镜头默认 zoom %.2f 落在 0.35—0.6（场景 = CAM_ZOOM_REST %.2f，满帆 %.2f 不更近），一屏 %.0f×%.0f 世界 px" % [cz, rest, full, 1280.0 / maxf(cz, 0.01), 720.0 / maxf(cz, 0.01)])
	var wm_c: Dictionary = (load("res://scripts/WorldMap.gd") as GDScript).get_script_constant_map()
	var spawn_min := float(wm_c.get("COMBAT_SPAWN_DIST_MIN", 0.0))
	var spawn_max := float(wm_c.get("COMBAT_SPAWN_DIST_MAX", INF))
	var half_h := 720.0 / (2.0 * maxf(cz, 0.01))
	_check(spawn_min >= 2.0 * 280.0 and spawn_max <= half_h,
		"开战刷船 %.0f—%.0f：下限不少于两倍船长 560，上限不过镜头半高 %.0f" % [spawn_min, spawn_max, half_h])
	var mm = (load("res://scripts/Minimap.gd") as GDScript).new()
	var ms := float(mm.get("map_scale"))
	var rr := float(mm.get("radar_radius"))
	mm.free()
	var esc := float((load("res://scripts/combat/EnemyCaptainAI.gd") as GDScript).get_script_constant_map().get("ESCAPE_DIST", INF))
	_check(spawn_min * ms >= 10.0 and esc * ms <= rr - 8.0 and esc * ms >= rr * 0.6,
		"海战雷达比例 %.3f：开战刷船处落在离心 %.1f px（本船脉动圈 9 px 之外），敌船遁走离场距离 %.0f 合 %.0f px（在盘半径六成 %.0f 与盘内 %.0f 之间，整局不挤在盘心）" % [ms, spawn_min * ms, esc, esc * ms, rr * 0.6, rr - 8.0])


## lane w20-c2（拍板 E-10 / G1014）：港口节拍接回运行时。给定一条 beat 序列，跑一段模拟后
## 节拍序号 / 状态按序推进（data/port_beats.json 五港链：泉州 5 拍、流求 / 博多各 1 拍开场、
## 泉州收线 2 拍）。关断开关 nk1/port_beats_runtime 两边各跑一遍：开 = 节拍推进、关 = 旧行为
## （节拍表空、load_scene 出入照旧、拍账不动）。
func _w20c2_port_beats_check(main: Node) -> void:
	var BM := load("res://scripts/core/PortBeats.gd")
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	main._beats = null
	_check(GS.beats_seen == [], "开局节拍账空（from_dict 清拍）")
	# ── 开关：默认开、关掉 = 留档不读 ──
	_check(BM.enabled() and not GM.port_beats_data.is_empty(),
		"开关默认开：port_beats.json 已读进 GameManager（%d 拍）" % (GM.port_beats_data.get("beats", []) as Array).size())
	ProjectSettings.set_setting(BM.SETTING, false)
	GM.load_data()
	_check(not BM.enabled() and GM.port_beats_data.is_empty(),
		"开关关掉：不再读 port_beats.json（回到留档）")
	ProjectSettings.set_setting(BM.SETTING, true)
	GM.load_data()
	main._beats = null
	_check(BM.enabled() and not GM.port_beats_data.is_empty(), "开关再开：数据回读")

	# ── 新档 seed：开关开着、空档**头一回到港**（随便哪一港），序章沿途那针 start 先记账（不然开局演老戏）──
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	GS.last_port = "fuzhou"
	main._beats = null
	main.load_scene("fuzhou")
	_check(GS.beats_seen == ["start"] and main.current_scene_id == "fuzhou",
		"新档 seed 随首抵下账：序章已演的戏记账、不重播（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "monk" and GS.beats_seen == ["start", "monk"],
		"seed 后的首抵泉州：节拍接 monk（原「第一章开卷卡」让位第一针，戏一幕；页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	# ── 一条 beat 序列按序推进（泉州链：monk → merchant → dock → prepare → 守港页）──
	# 链中间几针用旗标喂（和 route 章节段一样：把「照戏点出上一幕」用旗标按针接口推进；
	# 节拍条件 requires.seen 认同样一份账，试里照针的 requires 名直接 set_flag 到节拍账上）
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	# 直接从「新档 seed 已下（from_dict 回读会带回来）、第一针还没演」起：
	# from_dict({}) 已把账与 loaded 记都清了、把首抵 quanzhou 变成实测的 seed 现场
	GS.loaded_with_beats = true  # 试里跳过 seed（账面实操）
	main._beats = null
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "monk" and GS.beats_seen == ["monk"],
		"拍序 1（跳过 seed）：抵泉州演第一针 monk（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "merchant" and GS.beats_seen == ["monk", "merchant"],
		"拍序 2：再抵泉州接第二针 merchant（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "dock" and GS.beats_seen == ["monk", "merchant", "dock"],
		"拍序 3：merchant 记过名满足 dock 的「见过 merchant」——再抵接 dock（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "prepare" and GS.beats_seen == ["monk", "merchant", "dock", "prepare"],
		"拍序 4：dock 记过名满足 prepare 的「见过 dock」——再抵接 prepare（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	# 条件守着一格：return_quanzhou 的『去过流求』没够，停港页
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "quanzhou" and GS.beats_seen.size() == 4,
		"条件守着：return_quanzhou 要『去过流求』没够、停港页不动账（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	GS.visit_port("ryukyu")
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "return_quanzhou" and GS.beats_seen.size() == 5,
		"拍序 5：账外凭据（去过流求）补到、抵港接 return_quanzhou（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	# ── 非泉州各港不开演（w20-c2 只接泉州链：跨港链接法待拍板）──
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 6, "day": 1})
	main._beats = null
	GS.last_port = "ryukyu"
	GS.loaded_with_beats = true
	main.load_scene("ryukyu")
	_check(main.current_scene_id == "ryukyu" and GS.beats_seen == [] and ("ryukyu" in GS.visited_ports),
		"非泉州港不演不动账：首抵流求进港页记港，节拍一步不动（页 %s，visited %s，账 %s）" % [main.current_scene_id, GS.visited_ports, GS.beats_seen])
	# ── 关断开关：两边各跑一遍，关掉 = 节拍一步不动、读出走到哪一幕照旧 ──
	ProjectSettings.set_setting(BM.SETTING, false)
	GM.load_data()
	main._beats = null
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
	GS.loaded_with_beats = true
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	_check(main.current_scene_id == "quanzhou" and GS.beats_seen == [],
		"开关关掉：抵港照旧停港页、不演戏不动账（页 %s，账 %s）" % [main.current_scene_id, GS.beats_seen])
	main.load_scene("monk")
	_check(main.current_scene_id == "monk",
		"开关关掉：monk 一幕愿点照点（节拍不拦走幕，页 %s）" % main.current_scene_id)
	GS.last_port = "ryukyu"
	main.load_scene("ryukyu_bay")
	_check(main.current_scene_id == "ryukyu_bay" and not ("ryukyu" in GS.visited_ports),
		"开关关掉=2026-09-14 审计后的旧行为：航路外点进 ryukyu_bay 一幕不记港（visited %s）" % [GS.visited_ports])
	main.load_scene("hakata_ledger")
	_check(not ("hakata" in GS.visited_ports) and GS.beats_seen == [],
		"开关关掉：hakata_ledger 不记港、拍账仍空（visited %s，账 %s）" % [GS.visited_ports, GS.beats_seen])
	ProjectSettings.set_setting(BM.SETTING, true)
	GM.load_data()
	main._beats = null
	GS.loaded_with_beats = false
	# ── 存档 round-trip 带拍账（开关开着）──
	GS.from_dict({})
	GS.beat_mark("monk")
	GS.beat_mark("merchant")
	var bd: Dictionary = GS.to_dict()
	GS.from_dict({})
	_check(GS.beats_seen == [], "from_dict({}) 清拍账")
	GS.from_dict(bd)
	_check(GS.beats_seen == ["monk", "merchant"], "存档 round-trip 保留节拍账（%s）" % [GS.beats_seen])
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})
## w20-a4（lane g9 遗留①）：港页记事栏那口墨框只有三行高，跳年点开一串通告后要在框里滚（fx7 遗留①同源）。
## 方案甲：点开那一折墨框按排版高度向上生长到版面（LogFold.fitness_log，上框正文 EXPAND 自行让位），
## 再点某一月把该月摊开后回到 88 高、框带滚动条可滚到末则；收起插回场景写的 88（fx7 / g9 的文字断言一字不改仍绿）。
## 这里拿真 Main 在 headless 下确认：浮层里成长「到位」（主概率不全）；一步步收口、各月行逐行像素可读；收起逐点位回来。
func _w20a4_notice_fold_height_check(main: Node) -> void:
	var ml: RichTextLabel = main.message_label
	var body: RichTextLabel = main.status_label
	var LP: GDScript = load("res://scripts/core/LogFold.gd")
	_check(absf(ml.custom_minimum_size.y - float(LP.get("LOG_WELL_REST"))) < 0.5 and body.custom_minimum_size.y >= 359.0,
		"记事栏收着：墨框 min 高 %.0f = 场景写的 88，上框正文仍顶 360（%.0f）" % [ml.custom_minimum_size.y, body.custom_minimum_size.y])
	_fx7_wait_into(main, "quanzhou", 1276, 11, false)
	main._on_log_meta("fold:0")
	var want: Array = []
	for t in _notices.slice(int(main.get_meta(&"fx7_n0", 0))):
		want.push_front(UiTheme.plain_log(str(t)))
	var h0: float = ml.custom_minimum_size.y
	main.left_panel.visible = true
	main._render_log()
	main.left_panel.size = Vector2(480, 600)
	main._render_log()
	await self
	var h1: float = ml.custom_minimum_size.y
	main._render_log()
	await self
	var h2: float = ml.custom_minimum_size.y
	# headless 零缩放：面板挂实质前墨框已是 0×88 的条，盖住滚至末列、纵居每条单字位，get_content_height 读到「卷成单字的逐行高」，
	# 不脱生成数——只判稳定区间（长高过、不超版面、下一帧不动）与面板版面扣；「从 88 真长高」交下面跳两年那一格断言（那格面板 size 还是 0、排版读数有效）
	_check(h1 > float(LP.get("LOG_WELL_REST")) and h1 <= main.left_panel.size.y - float(LP.get("LOG_WELL_REST")) + 0.5 and absf(h2 - h1) < 1.0,
		"记事栏墨框点开在版面内一档到位：%.0f→%.0f（面板高 %.0f），下一帧稳 %.0f" % [h0, h1, main.left_panel.size.y, h2])
	main.left_panel.size = Vector2.ZERO
	main.left_panel.visible = false
	main._render_log()
	var texts: PackedStringArray = []
	for i in want.size():
		texts.append(str(want[i]))
	var opened: String = ml.text
	var missing := 0
	for t in texts:
		if opened.find("　" + t) < 0:
			missing += 1
	_check(missing == 0 and opened.find("收起") >= 0,
		"单批点开：%d 则全在文字层铺开（缺 %d 则，与墨框高矮无关）" % [texts.size(), missing])
	main._on_log_meta("fold:0")
	_check(absf(ml.custom_minimum_size.y - float(LP.get("LOG_WELL_REST"))) < 0.5 and ml.text.find("点开") >= 0,
		"单批收起：墨框回 88（%.0f），折起行照旧「点开」" % ml.custom_minimum_size.y)
	# 跳两年 + 分组：点开折总览长高；点某一月摊开后回 88，滚动一路可到末则——滚动条共识、性能不占擕
	GS.from_dict({})
	GS.identity = "merchant"
	GS.money = 5000
	GS.last_port = "quanzhou"
	Cal.from_dict({"year": 1275, "month": 1, "day": 1})
	main.load_scene("quanzhou")
	main._log_lines.clear()
	main._log_folds.clear()
	main._log_fold_open = ""
	var by_month: Dictionary = {}
	var order: Array = []
	var dates: Dictionary = {}
	var tap2 := func(t: String) -> void:
		var ym := "%04d-%02d" % [int(Cal.year), int(Cal.month)]
		if not by_month.has(ym):
			by_month[ym] = []
			order.push_front(ym)
			dates[ym] = str(Cal.get_date_string())
		(by_month[ym] as Array).push_front(UiTheme.plain_log(t))
	GM.monthly_notice.connect(tap2)
	var n2 := _notices.size()
	GM.skip_years(2)
	GM.monthly_notice.disconnect(tap2)
	var total: int = _notices.size() - n2
	main._on_log_meta("fold:0")
	var g0: float = ml.custom_minimum_size.y
	main.left_panel.visible = true
	main.left_panel.size = Vector2(480, 600)
	main._render_log()
	await self
	main._render_log()
	await self
	var g2: float = ml.custom_minimum_size.y
	_check(g2 > g0 + 1.0 or g0 > float(LP.get("LOG_WELL_REST")),
		"跳两年点开折总览：墨框从 88 长高（%.0f→%.0f，月行 %d 行）" % [g0, g2, order.size()])
	var pick: String = order[order.size() / 2] if not order.is_empty() else ""
	main._on_log_meta("fold:0:" + pick)
	await self
	var month_txt: String = ml.text
	var month_lines: Array = by_month.get(pick, [])
	var v: VScrollBar = ml.get_v_scroll_bar()
	var scrollable: bool = v != null and v.max_value - v.min_value - v.page > 0.5
	var last_in_text: bool = not month_lines.is_empty() and month_txt.find(str(month_lines[month_lines.size() - 1])) >= 0
	_check(absf(ml.custom_minimum_size.y - float(LP.get("LOG_WELL_REST"))) < 0.5 and scrollable and last_in_text,
		"跳两年点 %s 那月：墨框回 88（%.0f，不吃整版面），末则在文字层（月共 %d 则）且滚动可达末则（page %.0f / max %.0f）" % [
			pick, ml.custom_minimum_size.y, month_lines.size(), v.page if v != null else -1.0, v.max_value if v != null else -1.0])
	main._on_log_meta("fold:0")
	_check(main._log_fold_open == "" and absf(ml.custom_minimum_size.y - float(LP.get("LOG_WELL_REST"))) < 0.5,
		"跳两年终收：折起收、墨框回 88（%.0f）" % ml.custom_minimum_size.y)
	main.left_panel.size = Vector2.ZERO
	main.left_panel.visible = false
	main.log_msg("复原一句。")
	_check(absf(ml.custom_minimum_size.y - float(LP.get("LOG_WELL_REST"))) < 0.5 and ml.text.find("复原一句。") >= 0,
		"浮层合上来一句新记事：墨框仍 88，新句照常最上（与近况一致）")
	var w20_ledger_src := FileAccess.get_file_as_string("res://scripts/ui/LedgerPage.gd")
	var w20_fold_src := FileAccess.get_file_as_string("res://scripts/core/LogFold.gd")
	_check(w20_ledger_src.find("LogFold.fitness_log(main, main.message_label, main.left_panel, LogFold.LOG_WELL_REST)") >= 0
		and w20_fold_src.find("static func fitness_log(host: Object") >= 0 and w20_fold_src.find("LOG_WELL_REST") >= 0
		and w20_fold_src.find("static func _log_well_space(panel: Control)") >= 0,
		"船籍簿记事栏墨框经 LogFold.fitness_log 随开合定高（render_log 末尾挂上）")
	main._log_lines.clear()
	main._log_folds.clear()
	main._log_fold_open = ""
	main._render_log()
## lane w20-a5（修 w19-g9 遗留③）：海上「所在位置」不再按里程过半判，按船标当前坐标取最近的港——
## 港位真坐标 ports.json lat/lon（与真海图同源；scripts/WorldMap.gd 「(0,1000)／(2000,-1000)」是海战布景示意位、
## 全场景仅此两个，做不了坐标基准，见 Economy / Voyage.nearest_sea_port 注）；航线折线与沿途中间港都算候选。
## 正切片三格（贴起锚港 / 贴去向港 / 折线中段贴某中间港）+ 贴边两格 + 等远先后口径；反向变异自证：
## 把源码里的判据改回「里程过半」（两格，内存副本不落盘）须都判出不合——全绿 = 门禁空转。
## 变异跑法：函数体拼成临时 GDScript 沙箱（RefCounted、GameManager 重绑 autoload）、GDScript.reload 编译后 Eval——
## 不重载 autoload（Voyage 换元会扰到别的门禁），与 sea_src 自证同道。
func _a5_sea_here_check() -> void:
	var Eco: Node = root.get_node("Economy")
	var gml: Node = root.get_node("GameManager")
	var voyage_scr: Node = root.get_node("Voyage")
	var qz := -1.0
	var xh := -1.0
	for p in gml.get("ports_data").get("ports", []):
		match str(p.get("id", "")):
			"quanzhou": qz = float(p.get("lon", 0.0))
			"xinghua_harbor": xh = float(p.get("lon", 0.0))
	var cases := [
		# [标题, 起锚港, 去向港, 已行里数, 应取, 提示]
		["贴起锚港", "quanzhou", "fuzhou", 80.0, "quanzhou", "泉州→福州绕岸 431 里，行 80 里船在泉州湾"],
		["贴去向港", "quanzhou", "fuzhou", 280.0, "fuzhou", "行 280 里船在兴化湾北侧，离福州最近"],
		["折线中段贴某中间港", "champa", "zhangzhou", 1282.7, "guangzhou",
			"占城→漳州 2579 里行约半程，船在珠江口外离广州约 776 里、行程过半判法只能报漳州"],
	]
	for c in cases:
		_check(Eco.call("nearest_sea_port", c[1], c[2], c[3]) == c[4],
			"「所在位置」%s：%s → %s 已行 %.1f 里取 %s（实得 %s；%s）" % [c[0], c[1], c[2], c[3], c[4], Eco.call("nearest_sea_port", c[1], c[2], c[3]), c[5]])
	var full_qf: float = voyage_scr.call("distance_li", "quanzhou", "fuzhou")
	_check(Eco.call("nearest_sea_port", "quanzhou", "fuzhou", full_qf) == "fuzhou",
		"贴边：走满全程 %.0f 里仍取去向港（实得 %s）" % [full_qf, Eco.call("nearest_sea_port", "quanzhou", "fuzhou", full_qf)])
	_check(Eco.call("nearest_sea_port", "quanzhou", "fuzhou", 0.0) == "quanzhou",
		"贴边：刚起锚仍取起锚港（实得 %s）" % Eco.call("nearest_sea_port", "quanzhou", "fuzhou", 0.0))
	_check(qz >= 0.0 and xh > qz,
		"等远先报到的那港即 ports 数据序在先的那港（泉州 lon %.2f 在兴化海口 %.2f 之先，ports.json 泉州也排在它之前）" % [qz, xh])
	# ── 反向变异自证：取 SeaChart._sea_here() 函数体拼成 RefCounted 沙箱（GameManager 重绑、全自含，无 autoload 函数）Eval——
	# 变异走 string.replace 原位改字，green_now 是 control（改的字没生效则三格仍全对、须红）；
	# 变异须真的把判据改回里程半程，与 Lane-brief「改回里程过半 → 必须红」对得上。
	var sea_src2 := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	var sea_i := sea_src2.find("func _sea_here()")
	var sea_j := sea_src2.find("\nfunc ", sea_i + 1)
	var sea_body := sea_src2.substr(sea_i, sea_j - sea_i)
	var sc_eval := func(body2: String, ori: String, dst: String, tot: float, rem: float) -> String:
		# body2 = 「func _sea_here() -> String:\n\t…」整段；剥签名行须找「:」之后的真换行
		#（找首个 "\n" 会先撞上 "" 空串字面量里那个裸字节，把签名行留进体、Parse Error「Unexpected Indent」）
		var sig_end := body2.find("\n", body2.find(":"))
		var inner := body2.substr(sig_end + 1)
		var src2 := ("extends RefCounted\nvar _Eco\nfunc _apply(eco: Node) -> void:\n\t_Eco = eco\n"
			+ "var origin_port := \"\"\nvar selected_port := \"\"\nvar total_li := 0.0\nvar remaining_li := 0.0\n"
			+ "var Economy: Node\n"
			+ "func _sea_here() -> String:\n"
			+ inner)
		var scr2 := GDScript.new()
		scr2.source_code = src2
		if scr2.reload() != OK:
			return "<no>"
		var inst2: RefCounted = scr2.new()
		inst2.set("origin_port", ori)
		inst2.set("selected_port", dst)
		inst2.set("total_li", tot)
		inst2.set("remaining_li", rem)
		inst2.set("Economy", Eco)
		return str(inst2.call("_sea_here"))
	var sc_cases := [
		# [标题, 起锚, 去向, 全程里, 余程, 应取]
		["贴起锚港", "quanzhou", "fuzhou", 431.0, 351.0, "quanzhou"],
		["贴去向港", "quanzhou", "fuzhou", 431.0, 151.0, "fuzhou"],
		["折线中段贴某中间港", "champa", "zhangzhou", 2579.0, 1296.3, "guangzhou"],
	]
	# control：当前判据下沙箱三格都取应在的港（沙箱编译得出、门禁不空转）
	var green_now := 0
	var miss_now := []
	for c in sc_cases:
		var g: String = sc_eval.call(sea_body, c[1], c[2], c[3], c[4])
		if g == c[5]:
			green_now += 1
		else:
			miss_now.append("%s（得 %s）" % [c[0], g])
	_check(green_now == sc_cases.size(),
		"沙箱 control：现行 _sea_here 判据 %d/%d 格全对（%s）" % [green_now, sc_cases.size(), "、".join(miss_now)])
	# 变异 A（改回「里程过半」判据）：取港行退化成「余程 > 半程算起点、否则去向港」——
	# 与 w19-g9 之前的 _sea_here 判据同心（两格应断：贴去向港 / 折线中段贴中间港）
	# 锚点 = 新判据取港行的两个特征 token（「Economy.nearest_sea_port」「total_li - remaining_li」）；换成旧判据的判定式
	var m_anchor: int = sea_body.find("Economy.nearest_sea_port")
	var m_anchor2: int = sea_body.find("total_li - remaining_li")
	var mutA := sea_body.replace(
		"return Economy.nearest_sea_port(origin_port, selected_port, total_li - remaining_li)",
		"return origin_port if remaining_li > total_li * 0.5 else selected_port")
	var a_bad := []
	for c in sc_cases:
		var ga: String = sc_eval.call(mutA, c[1], c[2], c[3], c[4])
		if ga != "<no>" and ga != c[5]:
			a_bad.append("%s 断成 %s、应在 %s" % [c[0], ga, c[5]])
	_check(m_anchor >= 0 and m_anchor2 >= 0 and mutA != sea_body and a_bad.size() >= 1,
		"变异 A（取港行退回「余程 > 半程算起点」）落空须红：%d 格退化——%s" % [a_bad.size(), "、".join(a_bad)])
	# 变异 B（改回「里程过半」判据）：未过半分支提前 return origin_port——
	# 锚点 = 「total_li <= 0.0」套上「or remaining_li > total_li * 0.5」，三格中贴去向港那格应退化成起点
	var mutB := sea_body.replace(
		"if selected_port == \"\" or total_li <= 0.0:",
		"if selected_port == \"\" or total_li <= 0.0 or remaining_li > total_li * 0.5:")
	var b_bad := []
	for c in sc_cases:
		var gb: String = sc_eval.call(mutB, c[1], c[2], c[3], c[4])
		if gb != "<no>" and gb != c[5]:
			b_bad.append("%s 断成 %s、应在 %s" % [c[0], gb, c[5]])
	_check(mutB != sea_body and b_bad.size() >= 1,
		"变异 B（未过半臂套上「remaining_li > total_li * 0.5」，未过半恒算起点）落空须红：%d 格退化——%s" % [b_bad.size(), "、".join(b_bad)])


## w20-b1（g13 遗留①：WorldMap 没有岸线层，镜头拉远也看不到岸）：
## 海战战术场自绘一层真岸线——海图 MapView 同一份数据（data/coastline.json + ChartProjection），
## 按泉州—兴化示意位间距定比例铺进世界坐标。
## _route_check 是同帧接力（不传 await）；布景 / 铺层全在 add_child 同一帧到位，不必等帧：
## WorldMap._ready 是严典同步，_setup_coastline / 世界坐标缓存 / CoastlineLayer 都是就地建成的。
## 一、铺层存在（CoastlineLayer 挂上，z 在海面之上 / 船标之下）；
## 二、世界坐标缓存铺上了邻近一环，环节点均在 ±_COAST_NEAR 内（整环过滤生效）。
## 三、视野 _coast_view_rect 随镜头（旗舰 camera zoom 0.5 默认→摆 0.8，视野一比收）。
## 四、形状常量没破坏：_COAST_SCALE 落在泉州—兴化真距区间；_COAST_MIN_Z 介于 0.01—0.60。
## 最后一档「必红」变异：把 _setup_coastline 里 _build_coast_rings 返回 [] 、或 _draw_coastline 成 pass
##    （任何一道「不画」的改动）——本函数报红，截图闸也看不到岸线层。
func _b1_worldmap_coast_check() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.set("pending_battle", {
		"battle": true,
		"enemy": [{"type": "pirate_boat", "count": 1}],
		"power": 60.0,
		"player_power": 300.0,
		"sea_name": "泉州外海",
		"sea_seed": 7,
	})
	var wm = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# 布景同一帧（WorldMap._ready 同步挂上 CoastlineLayer）；冻敌炮免得抹黑
	var _cs := load("res://tools/combat_probe_stage.gd") as GDScript
	var freeze_n: int = int(_cs.freeze_enemy_fire(wm))
	_check(freeze_n >= 1, "布景敌船开炮已冻住（n=%d）" % freeze_n)
	if not is_instance_valid(wm):
		_check(false, "布景后 WorldMap 还活着（闪退）")
		return
	_check(wm.has_method("_setup_coastline"), "WorldMap 有岸线铺设入口 _setup_coastline")
	_check(wm.has_method("_build_coast_rings"), "WorldMap 有世界坐标缓存 _build_coast_rings（经纬 → 场景）")
	_check(wm.has_method("_draw_coastline"), "WorldMap 有岸线层自绘 _draw_coastline")
	_check(wm.has_method("_coast_view_rect"), "WorldMap 有随镜头的视野方法 _coast_view_rect")
	var layer: CanvasItem = wm.get_node_or_null("CoastlineLayer")
	_check(layer != null and layer is Node2D, "CoastlineLayer 已挂入 WorldMap（战斗 / 自由场景都铺）")
	if layer == null:
		wm.queue_free()
		return
	_check(layer.z_index > -10 and layer.z_index < 2,
		"岸线层 z=%d：海面（Ocean z -10）之上、船 / 港标（z 2）之下" % layer.z_index)
	var rings: Array = wm.get("_coast_rings")
	_check(rings is Array and rings.size() > 0,
		"世界坐标缓存铺上了邻近一环：_coast_rings 中环 %d 个" % rings.size())
	var rings_meta := int(layer.get_meta("coast_rings", -1))
	_check(rings_meta == rings.size(), "岸线层 meta.coast_rings=%d 与 _coast_rings 实数 %d 一致" % [rings_meta, rings.size()])
	# 二、整环过滤生效：环节点全部落在 ±_COAST_NEAR 内；超出中心的环整环被弃
	var wm_c: Dictionary = (load("res://scripts/WorldMap.gd") as GDScript).get_script_constant_map()
	var c_near := float(wm_c.get("_COAST_NEAR", 0.0))
	var out_n := 0
	for r in rings:
		var b: Rect2 = r.get("box", Rect2())
		if b.position.x > c_near or b.end.x < -c_near or b.position.y > c_near or b.end.y < -c_near:
			out_n += 1
	_check(out_n == 0, "世界坐标整环过滤生效：%d 环越出 ±%.0f（应 0；陆上 / 远岛整环不入画）" % [out_n, c_near])
	# 三、视野随镜头：把旗舰 camera zoom 摆到 0.8，_coast_view_rect 应从本帧 viewport rect 按 1/zoom 收一倍半圈（0.5 → 0.8：面积比 = (1.4/0.8)²）
	var cam: Camera2D = wm.get_node_or_null("Ship/Camera2D")
	_check(cam != null, "WorldMap 有 Ship/Camera2D（镜头）")
	if cam != null:
		var vp: Vector2 = wm.get_viewport_rect().size
		cam.zoom = Vector2(0.8, 0.8)
		var vr: Rect2 = wm.call("_coast_view_rect")
		var expect := vp * 0.5 / 0.8 * 1.4 * 2.0
		# headless 下 viewport rect 是场景默认（不是 1280×720），按 vp 现算才不写死尺寸
		_check(absf(vr.size.x - expect.x) < 5.0 and absf(vr.size.y - expect.y) < 5.0,
			"视野随镜头：zoom 0.8 时视野 %.0f×%.0f（vp %.0f×%.0f ÷ 0.8 ×1.4 ×2，实得 %.0f×%.0f）" % [expect.x, expect.y, vp.x, vp.y, vr.size.x, vr.size.y])
	# 四、形状常量没破坏
	var c_scale := float(wm_c.get("_COAST_SCALE", 0.0))
	var c_min_z := float(wm_c.get("_COAST_MIN_Z", 0.0))
	_check(c_scale >= 20.0 and c_scale <= 50.0,
		"摊图比例 _COAST_SCALE=%.2f：海图 0.9 km/px 落到刷场 25.6−64 km 一圈" % c_scale)
	_check(c_min_z > 0.01 and c_min_z < 0.60,
		"缩到最小时淡出 _COAST_MIN_Z=%.2f：介于 0.01−0.60，整层低于本值不再画" % c_min_z)
	# 收：布景不 battle_exit，静走
	wm.queue_free()
	gm.set("pending_battle", {})

# ══ 断言覆盖补白（lane w20-c6）══════════════════════════════
## 盘点报告 docs/story断言覆盖.md。本节五组断言只钉现行数据下已稳定的行为（落库前逐条实证），
## 不钉未拍板的设计。两组走 _initialize 尾部（数据 / 状态层，不依赖 Main 实例化）、三组走 _route_check
## 尾部（Main tree ready 后）。子断言数随 chapters / scenes 现表长变化，故补白计数 _c6_added 进 SUMMARY 自证。
var _c6_wired := false
var _c6_added := 0


func _c6_check(cond: bool, msg: String) -> void:
	_c6_added += 1
	_check(cond, msg)


## 终章结局面（chapters.json[3].endings 为结算幕表）：ready / 各面按表内旗标就位 / 摘旗回退兜底，三层全断。
## 数据驱动读现表（旗标 / 到账港数 / 本钱门槛现查现填，不抄数值），加新面 / 改旗标这里自动跟上、只断现定式。
func _c6_endings_gate_check() -> void:
	var ch4: Dictionary = {}
	for c in GM.chapters_data.get("chapters", []):
		if int(c.get("id", 0)) == 4:
			ch4 = c
	_c6_check(not ch4.is_empty() and (ch4.get("endings", []) as Array).size() >= 3,
		"第四章结局表至少三条（现 %d）" % (ch4.get("endings", []) as Array).size())
	var lst: Array = ch4.get("endings", [])
	if lst.size() < 3:
		return
	var er: Dictionary = ch4.get("ending_requires", {})
	var port_ids: Array = []
	for p in GM.ports_data.get("ports", []):
		port_ids.append(str(p.get("id", "")))
	var fulfill := func(gs) -> void:
		var want_n: int = maxi(int(er.get("visited_count", 0)), 1)
		gs.visited_ports = port_ids.slice(0, want_n)
		for pid in er.get("must_visit", []):
			if not (str(pid) in gs.visited_ports):
				gs.visited_ports.append(str(pid))
		var pm := int(er.get("peak_money", 0))
		gs.peak_money = maxi(pm, 1)
		gs.money = pm
	# A. 未就绪：chapter 4 + 零门槛 → ready=false，try_resolve 拒，ending_id 未写
	GS.from_dict({})
	GS.chapter = 4
	GS.ending_id = ""
	GS.visited_ports = []
	GS.peak_money = 0
	GS.money = 0
	_c6_check(not bool(GS.chapter_progress().get("ready", false)), "第四章零本钱零到港：chapter_progress.ready=false")
	_c6_check(not bool(GS.try_resolve_ending().get("resolved", false)), "未就绪 try_resolve 拒了结")
	_c6_check(GS.ending_id == "", "未就绪 ending_id 未写")
	# 定式：表尾兜底不带 require_flag / require_any，首条旗标线非空
	var last_e: Dictionary = lst[-1]
	var first_e: Dictionary = lst[0]
	_c6_check(str(last_e.get("require_flag", "")) == "" and (last_e.get("require_any", []) as Array).is_empty(),
		"兜底结局面「%s」无 require_flag / require_any" % str(last_e.get("id", "?")))
	_c6_check(str(first_e.get("require_flag", "")) != "" or (first_e.get("require_any", []) as Array).size() > 0,
		"首条结局面「%s」带旗标要求（次序不兜底遮线）" % str(first_e.get("id", "?")))
	# B / C：每面按表内旗标试；落定后先摘旗再 pick_ending——须回兜底
	for i in range(lst.size()):
		var e: Dictionary = lst[i]
		var eid := str(e.get("id", ""))
		var is_fallback := (i == lst.size() - 1)
		GS.from_dict({})
		GS.chapter = 4
		GS.ending_id = ""
		fulfill.call(GS)
		var any_arr: Array = e.get("require_any", [])
		var rf := str(e.get("require_flag", ""))
		if any_arr.size() > 0:
			GS.set_flag(str(any_arr[0]))
		elif rf != "":
			GS.set_flag(rf)
		var adv: Dictionary = GS.try_resolve_ending()
		_c6_check(bool(adv.get("resolved", false)) and GS.ending_id == eid and str(adv.get("title", "")) == str(e.get("title", "")),
			"结局面「%s」按表就位（%s线，title「%s」）" % [eid, "兜底" if is_fallback else "旗标", str(e.get("title", ""))])
		_c6_check(not bool(GS.try_resolve_ending().get("resolved", false)), "落定「%s」后再试了结被拒（ending_id 已写）" % eid)
		if not is_fallback:
			GS.flags.clear()
			_c6_check(not GS.pick_ending().is_empty() and str(GS.pick_ending().get("id", "")) == str(last_e.get("id", "")),
				"摘「%s」线旗标后 pick_ending 回落兜底「%s」" % [eid, str(last_e.get("id", ""))])
	# E. 落定态随存档 round-trip
	GS.from_dict({})
	GS.chapter = 4
	GS.ending_id = ""
	fulfill.call(GS)
	if not first_e.is_empty():
		var fa: Array = first_e.get("require_any", [])
		if fa.size() > 0:
			GS.set_flag(str(fa[0]))
		elif str(first_e.get("require_flag", "")) != "":
			GS.set_flag(str(first_e.get("require_flag")))
	GS.try_resolve_ending()
	var eid_saved: String = GS.ending_id
	var snap: Dictionary = GS.to_dict()
	GS.from_dict({})
	GS.from_dict(snap)
	_c6_check(GS.ending_id == eid_saved and bool(GS.chapter_progress().get("ended", false)),
		"存档 round-trip 保留落定结局（%s，progress.ended=true）" % eid_saved)
	GS.from_dict({})
	GS.ending_id = ""
	GS.chapter = 1
	GS.visited_ports = []
	GS.peak_money = 1000
	GS.money = 1000


## 存档 round-trip 六个此前没断言的字段：met_ids / era_routes / era_trips / merchant_credit / last_port /
## hometown_tendency + ended_head。to_dict / from_dict 键与 d.get 退化默认都在 GameState.gd 对过。
func _c6_roundtrip_fields_check() -> void:
	GS.from_dict({})
	Cal.from_dict({"year": 1271, "month": 6, "day": 1})
	GS.met_ids = ["lin_hua", "cai_qixing"]
	GS.era_routes = {"quanzhou→hakata": 2, "quanzhou→penghu": 1}
	GS.era_trips = 3
	GS.merchant_credit = 66
	GS.last_port = "hakata"
	GS.hometown_tendency = 5
	GS.ended_head = "试笔"
	var snap: Dictionary = GS.to_dict()
	GS.from_dict({})
	_c6_check(GS.met_ids.is_empty() and GS.era_routes.is_empty() and GS.era_trips == 0,
		"from_dict({}) 清空 met_ids / era_routes / era_trips")
	_c6_check(GS.merchant_credit == 0 and GS.last_port == "quanzhou" and GS.hometown_tendency == 0 and GS.ended_head == "",
		"from_dict({}) 清空海商信用 / 回默认 last_port / 乡土倾向 / ended_head")
	GS.from_dict(snap)
	_c6_check(GS.met_ids == ["lin_hua", "cai_qixing"], "存档 round-trip 保留 met_ids")
	_c6_check(GS.era_routes == {"quanzhou→hakata": 2, "quanzhou→penghu": 1} and GS.era_trips == 3,
		"存档 round-trip 保留 era 段（主航线次数 + 记趟数）")
	_c6_check(GS.merchant_credit == 66 and GS.last_port == "hakata",
		"存档 round-trip 保留海商信用与最后到港")
	_c6_check(GS.hometown_tendency == 5 and GS.ended_head == "试笔",
		"存档 round-trip 保留乡土倾向与 ended_head")
	GS.from_dict({})
	Cal.from_dict({"year": 1255, "month": 3, "day": 1})


## 结局面落定 ≠ is_ended()：try_resolve_ending 后 ended 仍空，Main.finish 才写 ended（is_ended 翻面）
## ——两条路径分走、不钉谁调谁。
func _c6_endings_semantics_check() -> void:
	GS.from_dict({})
	GS.chapter = 4
	GS.ending_id = "south_sea"
	_c6_check(not GS.is_ended() and GS.ended == "",
		"落定结局面未 confirm：is_ended()=false（结局面与终局态分两条路径）")
	GS.from_dict({})
	GS.chapter = 4
	GS.ending_id = ""
	GS.finish("纲首", "正文若干")
	_c6_check(GS.is_ended() and GS.ended == "纲首", "confirm 走完 finish：is_ended()=true、ended=「纲首」")
	GS.from_dict({})
	GS.chapter = 1
	GS.ended = ""


## 场景形状枚举断言（新幕上库不接入即红）：
## 1. 调查幕五键齐（id / label / text / effects / next）；
## 2. 结算幕 result 为 String 或 PackedStringArray，且不再同时挂 choices；
## 3. discoveries.json 勘见面每座的 name / id 非空（调查幕线接续以 id == 发现名为底，
##    本座名下必有一座 scenes 的 investigation 幕接续——若日后新一座勘见漏配，这条把当前 4 座的名单拉进来逐个对到位）。
func _c6_investigation_result_enum_check() -> void:
	var scenes: Array = GM.scenes_data.get("scenes", [])
	var inv_n := 0
	var res_n := 0
	for s in scenes:
		var t := str(s.get("type", ""))
		if t == "investigation":
			inv_n += 1
			var invs: Array = s.get("investigations", [])
			_c6_check(invs.size() > 0, "调查幕「%s」带考题（现 %d 道）" % [str(s.get("id", "")), invs.size()])
			for it in invs:
				var miss: Array = []
				for k in ["id", "label", "text", "effects", "next"]:
					if not it.has(k):
						miss.append(k)
				_c6_check(miss.is_empty(), "调查幕「%s」一道考题五键齐（id/label/text/effects/next；%s缺 %s）" % [str(s.get("id", "")), str(it.get("id", "?")), str(miss)])
		elif s.has("result"):
			res_n += 1
			var r = s.get("result")
			var shape_ok: bool = typeof(r) == TYPE_STRING
			if typeof(r) == TYPE_ARRAY:
				shape_ok = not (r as Array).is_empty()
				for line in r:
					if typeof(line) != TYPE_STRING:
						shape_ok = false
			_c6_check(shape_ok,
				"结算幕「%s」result 为 String 或非空 String 数组（现 %s）" % [str(s.get("id", "")), type_string(typeof(r))])
			_c6_check((s.get("choices", []) as Array).is_empty(), "结算幕「%s」不同时挂 choices" % str(s.get("id", "")))
	_c6_check(inv_n == 4, "调查幕现 4 座（现 %d）：city_tavern / city_residence / city_shipyard / city_guild" % inv_n)
	_c6_check(res_n > 0, "结算幕非零（现 %d 座）" % res_n)
	var disc: Array = GM.discoveries_data.get("discoveries", [])
	_c6_check(disc.size() > 0, "discoveries.json 非空（现 %d 座）" % disc.size())
	for d in disc:
		_c6_check(str(d.get("name", "")) != "" and str(d.get("id", "")) != "", "勘见面「%s」name 非空" % str(d.get("id", "?")))


## 新闻表 only 枚举断言：news.json 26 条，全量断言此前只有「按月投放、1277-01 前应投 = 实投」三条总长直；
## only 字段值 ∈ {scholar, merchant, hometown, ""}——出第四个值即有人找别处的禁线（现有断言不查）。
func _c6_news_only_enum_check() -> void:
	var seen_only := {}
	for it in GM.news_data.get("news", []):
		var on := str(it.get("only", ""))
		seen_only[on] = int(seen_only.get(on, 0)) + 1
		var ok_only: bool = on == "" or on == "scholar" or on == "merchant" or on == "hometown"
		_c6_check(ok_only, "新闻 %s 的 only ∈ scholar / merchant / hometown / \"\"（现「%s」）" % [str(it.get("id", "")), on])
	_c6_check(int(seen_only.get("", 0)) > 0, "公共新闻（only 缺省）条数 > 0（现 %d）" % int(seen_only.get("", 0)))
	_c6_check(int(seen_only.get("scholar", 0)) + int(seen_only.get("merchant", 0)) > 0,
		"士人 / 海商专线新闻均有条目（现 scholar %d、merchant %d）" % [int(seen_only.get("scholar", 0)), int(seen_only.get("merchant", 0))])


## 接线（插在全部 _c6 检查函数之后——a1/a4/a6 若在文件别处加函数，本节不受影响）


func _process_c6_main_hook(_main: Node) -> void:
	# _route_check 尾部接入（queue_free 之后）——本组纯 GameState / GameManager 断言，Main 只占位
	if _c6_wired:
		return
	_c6_wired = true
	_c6_investigation_result_enum_check()
	_c6_endings_gate_check()
	_c6_endings_semantics_check()
	print("STORY_CHECK C6 main-hook asserts added=", _c6_added)


func _process_c6_init_hook() -> void:
	# _initialize 尾部接入（advance_years 断言之后、Main 实例化之前）——本组只走 GameState / GameManager 数据
	_c6_roundtrip_fields_check()
	_c6_news_only_enum_check()
	print("STORY_CHECK C6 init-hook asserts added=", _c6_added)


## lane w20-b9：开战刷船间距按 3D 船身包围盒重核——原判据 spawn_min ≥ 两倍船长 560 不扛 ShipHull3D
## 视口 832 × VIS_SCALE 0.78 ≈ 649 世界 px 贴身的包围盒（旗舰 / 敌船同型，Sprite2D / HullWater / HullLight
## 同贴 0.78）。开局镜头 zoom = CAM_ZOOM_REST 0.5（spawn 时船速还没进满航 0.42），屏上敌我不可交须
## dist × 0.5 ≥ (325+325)/2 = 325 屏 px → dist ≥ 650；抬到 700 留 50 余量。上限 ≤ 半高（zoom 0.5 = 720
## 与 zoom 0.42 = 857 取小即 720），任何角度刷出的船心仍在画内。反向变异：COMBAT_SPAWN_DIST_MIN=700
## → 560 / MAX=720 → 600，三行各红一行（间距太挤 / 屏上仍交）。
func _w20b9_spawn_bbox_check() -> void:
	var wm_c: Dictionary = (load("res://scripts/WorldMap.gd") as GDScript).get_script_constant_map()
	var smin := float(wm_c.get("COMBAT_SPAWN_DIST_MIN", 0.0))
	var smax := float(wm_c.get("COMBAT_SPAWN_DIST_MAX", INF))
	var hull_c: Dictionary = (load("res://scripts/combat/ShipHull3D.gd") as GDScript).get_script_constant_map()
	var view := float(hull_c.get("VIEW", 0.0))
	var vis := float(hull_c.get("VIS_SCALE", 0.0))
	var hull_bbox := view * vis  # 3D 船身世界 px 尺寸（约 649）
	_check(hull_bbox >= 640.0 and hull_bbox <= 660.0,
		"3D 船身包围盒 %.0f 世界 px（VIEW %.0f × VIS_SCALE %.2f），应落在 640—660" % [hull_bbox, view, vis])
	var ship_c: Dictionary = (load("res://scripts/Ship.gd") as GDScript).get_script_constant_map()
	var cam_r := float(ship_c.get("CAM_ZOOM_REST", 0.0))
	var cam_f := float(ship_c.get("CAM_ZOOM_FULL", 0.0))
	# 屏上不可交临界：dist × zoom ≥ 两船各自半垫之和 = (hull_bbox/2 + hull_bbox/2) / 2 = hull_bbox/2 = 325
	# 再 25 px 缓冲：两船真贴身没间隙、玩家看上去仍叠——按游戏观感沿那道缝再退半层
	var px_thresh: float = hull_bbox / 2.0 + 25.0
	_check(smin >= px_thresh / cam_r,
		"开战刷船下限 %.0f：按 zoom %.2f（REST）屏上 %.0f px ≥ 临界 %.0f（3D 船身 %.0f 世界 px，两船同出）" % [
			smin, cam_r, smin * cam_r, px_thresh, hull_bbox])
	# 满帆档（zoom 0.42）spawn 是在开局 zoom=0.5 时刻发生、玩家操盘后不属于开局判据；仍留一条松底线守贴势
	_check(smin * cam_f >= hull_bbox / 4.0 + 25.0,
		"开战刷船下限 %.0f 满帆 zoom %.2f 屏上 %.0f px ≥ 四分之一包围盒 %.0f（满航仍可按一条狭缝认两船）" % [
			smin, cam_f, smin * cam_f, hull_bbox / 4.0 + 25.0])
	var half_r := 720.0 / (2.0 * cam_r)
	var half_f := 720.0 / (2.0 * cam_f)
	_check(smax <= half_r and smax <= half_f,
		"开战刷船上限 %.0f：两档半高 %.0f / %.0f 同收，任何角度刷出都在画内" % [smax, half_r, half_f])
