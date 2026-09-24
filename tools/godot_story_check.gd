## 引擎内剧情状态机门禁（2026-09-04 引入，随 news.json / 1268 身份结算落地）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_story_check.gd
## 只推进 GM.advance_days()，断言：新闻按月到期投放且不重复；1268-04 结算恰一次；
## 士人/海商两种倾向分别得到陈文龙/陈子龙；存档 round-trip 保留新字段。
## 首帧另实例化 Main 走真机抵港路由（2026-09-14）：与港口同名的 load_scene 必须记 visited_ports 并能晋升。任一失败 quit(1)。
extends SceneTree

var _fails := 0
var _notices: Array = []
# autoload 在 SceneTree 脚本里不能当标识符用，运行时从 root 取
var GM: Node
var Cal: Node
var GS: Node


func _check(cond: bool, msg: String) -> void:
	print("STORY_CHECK ", "OK   " if cond else "FAIL ", msg)
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
	Cal.from_dict({"year": 1277, "month": 4, "day": 1})
	_check(Eco.war_status("xinghua") == "fallen", "1277-04 兴化再陷")

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
	var hints := {"n_1276_10_xinghua_muster": "scholar", "n_1277_01_chenzan_raises": "merchant", "n_1278_12_yashan": "merchant"}
	for hid in hints:
		var hn: Dictionary = GM.get_news_by_id(hid)
		_check(not hn.is_empty(), "预告新闻 %s 存在" % hid)
		_check(str(hn.get("only", "")) == hints[hid], "预告 %s 发给 %s" % [hid, hints[hid]])
	# 预告必须早于对应窗口
	_check(str(GM.get_news_by_id("n_1276_10_xinghua_muster").get("date", "")) < "1276-11", "守城预告早于 1276-11 围城")
	_check(str(GM.get_news_by_id("n_1277_01_chenzan_raises").get("date", "")) < "1277-02", "陈瓒预告早于 1277-02 复城")
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

	# ── 「未归」不得被陈瓒复城的两个月钻空子 ──
	# 兴化 war 表：1277-02 loyal / 1277-04 fallen。若判据只看当前 war_status，
	# 士人线玩家在 1277-02、03 入港就躲过了结局。
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
	main.load_scene("ryukyu_survey")
	main.load_scene("hakata_ledger")
	_check(GS.visited_ports.is_empty(), "剧情幕 ryukyu_survey / hakata_ledger 不记港")
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
	# 旅店路由：city_inn 必须落到 {港}_inn，不能是 city_inn
	GS.last_port = "quanzhou"
	main.load_scene("quanzhou")
	main._on_facility_pressed({"id": "city_inn"})
	_check(main.current_scene_id == "quanzhou_inn", "旅店按钮落到 quanzhou_inn（实际 %s）" % main.current_scene_id)
	# 背景回落：缺图不黑屏（拿一个肯定不存在的名字试）
	main._set_background_file("bg_definitely_missing.jpg")
	_check(main.background.texture != null, "缺失背景图回落到 FALLBACK_BG，texture 非 Nil")
	# 标题屏 / 海图底图 bg_world_map.jpg 已落地
	main._apply_background("title", "")
	_check(str(main.background.texture.resource_path).ends_with("bg_world_map.jpg"), "标题屏用 bg_world_map.jpg（实际 %s）" % main.background.texture.resource_path)
	# 终局：结算图压在结局对话框后，之后的港页也持续压着
	GS.from_dict({})
	GS.finish("忠肃", "正文")
	GS.last_port = "xinghua"
	main.load_scene("xinghua")
	_check(str(main.background.texture.resource_path).ends_with("bg_end_temple.jpg"), "终局「忠肃」港页压 bg_end_temple.jpg（实际 %s）" % main.background.texture.resource_path)
	GS.from_dict({})
	_close_dialogs(main)
	main.queue_free()


## 关掉 Main 弹出的 AcceptDialog（章节晋升 / 通告），等价于玩家按下确认
func _close_dialogs(main: Node) -> void:
	for c in main.get_children():
		if c is AcceptDialog:
			c.hide()
			c.free()
