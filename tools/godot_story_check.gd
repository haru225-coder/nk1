## 引擎内剧情状态机门禁（2026-09-04 引入，随 news.json / 1268 身份结算落地）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_story_check.gd
## 只推进 GM.advance_days()，断言：新闻按月到期投放且不重复；1268-04 结算恰一次；
## 士人/海商两种倾向分别得到陈文龙/陈子龙；存档 round-trip 保留新字段。任一失败 quit(1)。
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
	var total_news: int = GM.news_data.get("news", []).size()
	_check(seen_all == total_news, "1277-01 全部 %d 条新闻已投放（实际 %d）" % [total_news, seen_all])
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

	print("STORY_CHECK SUMMARY fails=", _fails)
	quit(1 if _fails > 0 else 0)
