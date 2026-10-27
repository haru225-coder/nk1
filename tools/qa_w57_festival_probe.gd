extends SceneTree
## lane fest1 岁时节令探针（headless，经门锁跑）。
## 断言：十一条节令事都在册，落在原港原处；月门只开本月，别的月份办不成；
##      一年只办一回，次年同月还能再办。

const TAG := "QA_W57_FESTIVAL"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const EXPECTED := [
	{"id": "qz_jubao_lantern", "port": "quanzhou", "district": "qz_jubao", "month": 1, "type": "choice"},
	{"id": "gz_nanhai_birth", "port": "guangzhou", "district": "gz_nanhai", "month": 2, "type": "sell"},
	{"id": "wz_huagai_qingming", "port": "wenzhou", "district": "wz_huagai", "month": 3, "type": "choice"},
	{"id": "qz_kaiyuan_buddha", "port": "quanzhou", "district": "qz_kaiyuan", "month": 4, "type": "favour"},
	{"id": "wz_jiangxin_duanwu", "port": "wenzhou", "district": "wz_jiangxin", "month": 5, "type": "rumor"},
	{"id": "gz_liurong_ullambana", "port": "guangzhou", "district": "gz_liurong", "month": 7, "type": "favour"},
	{"id": "gz_haishan_moon", "port": "guangzhou", "district": "gz_haishan", "month": 8, "type": "favour"},
	{"id": "hk_hako_release", "port": "hakata", "district": "hk_hako", "month": 8, "type": "favour"},
	{"id": "qz_jiuri_chongyang", "port": "quanzhou", "district": "qz_jiuri", "month": 9, "type": "favour"},
	{"id": "qz_citong_dongzhi", "port": "quanzhou", "district": "qz_citong", "month": 11, "type": "sell"},
	{"id": "hk_tobo_suichu", "port": "hakata", "district": "hk_tobo", "month": 12, "type": "favour"},
]

var Book
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var eco: Node

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	eco = root.get_node_or_null("Economy")
	Book = load("res://scripts/core/Districts.gd")
	if gs == null or gm == null or cal == null or fleet == null or eco == null or Book == null:
		_check(false, "GameState / GameManager / Calendar / Fleet / Economy / Districts 没载入")
		_report()
		return
	eco.initialize()
	_check_table()
	_check_gates()
	_check_once_year()
	_report()


func _check_table() -> void:
	var txt := FileAccess.get_file_as_string("res://data/districts.json")
	var parsed = JSON.parse_string(txt)
	var by_dist: Dictionary = {}
	var by_ix: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for row in parsed.get("districts", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var did := str(row.get("id", ""))
			by_dist[did] = row
			for ix in row.get("interactions", []):
				if typeof(ix) == TYPE_DICTIONARY:
					by_ix[str(ix.get("id", ""))] = {"row": row, "ix": ix}
	var bad := 0
	for e in EXPECTED:
		var iid := str(e.id)
		var hit = by_ix.get(iid, {})
		if typeof(hit) != TYPE_DICTIONARY or hit.is_empty():
			bad += 1
			print("    缺事 %s" % iid)
			continue
		var row: Dictionary = hit.row
		var ix: Dictionary = hit.ix
		if str(row.get("port", "")) != str(e.port) or str(row.get("id", "")) != str(e.district):
			bad += 1
			print("    落错港处 %s" % iid)
		if str(ix.get("type", "")) != str(e.type):
			bad += 1
			print("    事类不对 %s" % iid)
		if str(ix.get("once_per", "")) != "year":
			bad += 1
			print("    不是一年一回 %s" % iid)
		var u = ix.get("unlock", {})
		var months = u.get("months", []) if typeof(u) == TYPE_DICTIONARY else []
		if typeof(months) != TYPE_ARRAY or months.size() != 1 or int(months[0]) != int(e.month):
			bad += 1
			print("    月门不对 %s" % iid)
		if str(ix.get("label", "")) == "" or str(ix.get("text", "")) == "":
			bad += 1
			print("    文案缺 %s" % iid)
	_check(bad == 0, "表：十一条节令事都在原港原处、各只开本月、一年一回（坏 %d）" % bad)
	_check(not _in_port(by_dist, "xinghua", "qz_jubao_lantern") and not _in_port(by_dist, "xinghua", "gz_nanhai_birth"),
		"表：节令事没有落到兴化")
	var chong: Dictionary = Book.interaction("qz_jiuri_chongyang")
	var chong_text := str(chong.get("text", ""))
	_check(not chong_text.contains("祈风") and not chong_text.contains("顺风") and not chong_text.contains("归帆"),
		"表：九日山重阳不借祈风旧句")
	var release: Dictionary = Book.interaction("hk_hako_release")
	var release_text := str(release.get("text", ""))
	_check(not release_text.contains("919") and not release_text.contains("延喜") and not release_text.contains("九一九"),
		"表：箱崎放生会不写初创年份")


func _in_port(by_dist: Dictionary, port: String, iid: String) -> bool:
	for did in by_dist:
		var row: Dictionary = by_dist[did]
		if str(row.get("port", "")) != port:
			continue
		for ix in row.get("interactions", []):
			if typeof(ix) == TYPE_DICTIONARY and str(ix.get("id", "")) == iid:
				return true
	return false


func _check_gates() -> void:
	var bad := 0
	for e in EXPECTED:
		var iid := str(e.id)
		var m := int(e.month)
		for other in range(1, 13):
			if other == m:
				continue
			_fresh(1255, other)
			_prepare(iid)
			var res: Dictionary = Book.apply(iid, _opt(iid))
			if bool(res.get("ok", false)) or str(res.get("msg", "")) != "还不是这个月的事":
				bad += 1
				print("    %s 在 %d 月没有关住：%s" % [iid, other, str(res.get("msg", ""))])
		_fresh(1255, m)
		_prepare(iid)
		var opened: Dictionary = Book.apply(iid, _opt(iid))
		if not bool(opened.get("ok", false)):
			bad += 1
			print("    %s 在 %d 月办不成：%s" % [iid, m, str(opened.get("msg", ""))])
	_check(bad == 0, "月门：十一条事本月都办得成，别的十一个月都关着（坏 %d）" % bad)


func _check_once_year() -> void:
	var bad := 0
	for e in EXPECTED:
		var iid := str(e.id)
		var m := int(e.month)
		_fresh(1255, m)
		_prepare(iid)
		var first: Dictionary = Book.apply(iid, _opt(iid))
		var again: Dictionary = Book.apply(iid, _opt(iid))
		if not bool(first.get("ok", false)) or bool(again.get("ok", false)) or str(again.get("msg", "")) != "已经办过":
			bad += 1
			print("    %s 同年没有收住第二回：%s" % [iid, str(again.get("msg", ""))])
		_fresh(1256, m)
		_prepare(iid)
		var next: Dictionary = Book.apply(iid, _opt(iid))
		if not bool(next.get("ok", false)):
			bad += 1
			print("    %s 次年同月办不成：%s" % [iid, str(next.get("msg", ""))])
	_check(bad == 0, "一年一回：同年第二回挡住，次年同月再开（坏 %d）" % bad)


func _fresh(year: int, month: int) -> void:
	Book.wipe()
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.contract = {}
	gs.siege = {}
	gs.flags = {}
	gs.identity = "undecided"
	gs.player_name = "陈子龙"
	gs.pu_attention = 0
	gs.merchant_credit = 0
	gs.scholar_tendency = 0
	gs.hometown_tendency = 0
	gs.network = 0
	gs.fame = 0
	gs.sea_tendency = 0
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	cal.from_dict({"year": year, "month": month, "day": 15})


func _prepare(iid: String) -> void:
	var ix: Dictionary = Book.interaction(iid)
	var typ := str(ix.get("type", ""))
	if typ == "sell":
		fleet.add_cargo(str(ix.get("good", "")), int(ix.get("qty", 0)), 1.0)


func _opt(iid: String) -> String:
	var ix: Dictionary = Book.interaction(iid)
	if str(ix.get("type", "")) != "choice":
		return ""
	var opts = ix.get("options", [])
	if typeof(opts) == TYPE_ARRAY and not opts.is_empty() and typeof(opts[0]) == TYPE_DICTIONARY:
		return str(opts[0].get("id", ""))
	return ""
