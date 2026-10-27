extends SceneTree

const TAG := "QA_W57_CREW"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const NEW := [
	{"id": "liang_wangdou", "name": "梁望斗", "role": "huozhang", "level": 2, "wage": 120, "port": "guangzhou", "unlock": "ch3"},
	{"id": "gu_sanjiang", "name": "顾三江", "role": "duogong", "level": 2, "wage": 120, "port": "mingzhou", "unlock": "ch2"},
	{"id": "zhang_tiemao", "name": "张铁猫", "role": "duogong", "level": 1, "wage": 60, "port": "zhangzhou", "unlock": "ch1"},
	{"id": "chen_dayou", "name": "陈大有", "role": "zashi", "level": 2, "wage": 120, "port": "xinghua_harbor", "unlock": "ch1"},
	{"id": "wang_xin", "name": "王信", "role": "tongshi", "level": 2, "wage": 120, "port": "wenzhou", "unlock": "ch2"},
]
const LEVEL_WAGE := {1: 60, 2: 120, 3: 200}

var gs: Node
var gm: Node
var crew: Node
var cal: Node
var art: GDScript

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
	crew = root.get_node_or_null("Crew")
	cal = root.get_node_or_null("Calendar")
	art = load("res://scripts/ui/CharacterArt.gd") as GDScript
	if gs == null or gm == null or crew == null or cal == null or art == null:
		_check(false, "GameState / GameManager / Crew / Calendar / CharacterArt 没载入")
		_report()
		return
	_check_data()
	_check_characters()
	_check_offers()
	_check_hire()
	_check_save()
	_report()


func _fresh(chapter := 1, year := 1262, month := 5) -> void:
	gs.from_dict({})
	crew.from_dict({})
	gs.chapter = chapter
	gs.money = 50000
	gs.flags = {}
	gs.last_port = "quanzhou"
	cal.from_dict({"year": year, "month": month, "day": 1})


func _check_data() -> void:
	var cands: Array = gm.crew_data.get("candidates", [])
	var roles := {}
	for r in gm.crew_data.get("roles", []):
		roles[str(r.get("id", ""))] = true
	var by_id := {}
	var by_name := {}
	var new_seen := 0
	for c in cands:
		var cid := str(c.get("id", ""))
		var cname := str(c.get("name", ""))
		_check(cid != "" and not by_id.has(cid), "名册 id 不重：%s" % cid)
		_check(cname != "" and not by_name.has(cname), "名册姓名不重：%s" % cname)
		by_id[cid] = c
		by_name[cname] = cid
		if _new_spec(cid).is_empty():
			continue
		new_seen += 1
	_check(cands.size() >= 24, "名册至少二十四人（实 %d）" % cands.size())
	_check(new_seen == NEW.size(), "五名新候选各只一条（实 %d）" % new_seen)
	for spec in NEW:
		var cid := str(spec.get("id", ""))
		var c: Dictionary = by_id.get(cid, {})
		_check(not c.is_empty(), "表：候选 %s 在册" % cid)
		if c.is_empty():
			continue
		_check(str(c.get("name", "")) == str(spec.get("name", "")), "表：%s 姓名「%s」" % [cid, spec.get("name", "")])
		_check(str(c.get("role", "")) == str(spec.get("role", "")), "表：%s 职事 %s" % [cid, spec.get("role", "")])
		_check(roles.has(str(c.get("role", ""))), "表：%s 的职事在 roles 表里" % cid)
		_check(int(c.get("level", 0)) == int(spec.get("level", 0)), "表：%s 品级 %d" % [cid, spec.get("level", 0)])
		var lv := int(c.get("level", 0))
		_check(int(c.get("wage", 0)) == int(LEVEL_WAGE.get(lv, -1)), "表：%s 月俸照品级档 %d" % [cid, int(c.get("wage", 0))])
		_check(str(c.get("port", "")) == str(spec.get("port", "")), "表：%s 候雇港 %s" % [cid, spec.get("port", "")])
		var port: Dictionary = gm.get_port_by_id(str(c.get("port", "")))
		_check(not port.is_empty(), "表：%s 的候雇港在 ports.json 里" % cid)
		_check(str(c.get("unlock", "")) == str(spec.get("unlock", "")), "表：%s 章节 %s" % [cid, spec.get("unlock", "")])
		_check(str(c.get("require_flag", "")) == "" and str(c.get("leave_from", "")) == "", "表：%s 只按章节候雇，无附加旗标与辞船月" % cid)
		_check(str(c.get("bio", "")).length() >= 20, "表：%s 有一段出身白描（%d 字）" % [cid, str(c.get("bio", "")).length()])


func _check_characters() -> void:
	var trait_defs: Dictionary = gm.character_meta().get("trait_def", {})
	for spec in NEW:
		var cid := str(spec.get("id", ""))
		var c: Dictionary = gm.character_for_crew(cid)
		_check(not c.is_empty(), "设定集：%s 在册" % cid)
		if c.is_empty():
			continue
		_check(str(c.get("id", "")) == cid, "设定集：%s 条目 id 对得上" % cid)
		_check(str(c.get("name", "")) == str(spec.get("name", "")), "设定集：%s 姓名「%s」" % [cid, spec.get("name", "")])
		_check(str(c.get("tier", "")) == "crew", "设定集：%s 归职事档" % cid)
		_check(c.get("historical", true) == false, "设定集：%s 非史实人物" % cid)
		var src = c.get("sources", {})
		_check(typeof(src) == TYPE_DICTIONARY and str(src.get("crew_id", "")) == cid, "设定集：%s 挂回候选名册" % cid)
		_check(str(c.get("title", "")) != "", "设定集：%s 有称谓" % cid)
		_check(str(c.get("origin", "")) != "", "设定集：%s 有籍贯" % cid)
		var attrs = c.get("attrs", {})
		var attrs_ok := typeof(attrs) == TYPE_DICTIONARY
		if attrs_ok:
			for k in ["hang", "shang", "wu", "xue", "wang"]:
				var v = attrs.get(k)
				attrs_ok = attrs_ok and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT)
		_check(attrs_ok, "设定集：%s 五维齐" % cid)
		var traits = c.get("traits", [])
		var traits_ok := typeof(traits) == TYPE_ARRAY and not (traits as Array).is_empty()
		if traits_ok:
			for t in traits:
				traits_ok = traits_ok and trait_defs.has(str(t))
		_check(traits_ok, "设定集：%s 特技在定义表里" % cid)
		_check(str(c.get("personality", "")) != "", "设定集：%s 有性情" % cid)
		_check(str(c.get("bio_short", "")).length() >= 20, "设定集：%s 有短白描" % cid)
		_check(str(c.get("bio", "")).length() >= 60, "设定集：%s 有长篇出身" % cid)
		var cand: Dictionary = crew.candidate_def(cid)
		_check(str(c.get("bio", "")) != str(cand.get("bio", "")), "设定集：%s 长文不与候选白描照抄" % cid)
		var lines = c.get("lines", [])
		_check(typeof(lines) == TYPE_ARRAY and (lines as Array).size() == 3, "设定集：%s 恰好三句话" % cid)
		_check(str(c.get("look", "")) != "", "设定集：%s 有画像白描" % cid)
		var portrait := str(c.get("portrait", ""))
		_check(portrait.begins_with("res://assets/portraits/") and ResourceLoader.exists(portrait), "设定集：%s 立绘在库" % cid)
		_check(art.codex_short(c) != "" and art.codex_bio(c) != "", "设定集：%s 上屏文案齐" % cid)


func _new_spec(cid: String) -> Dictionary:
	for spec in NEW:
		if str(spec.get("id", "")) == cid:
			return spec
	return {}


func _has_id(arr: Array, cid: String) -> bool:
	for c in arr:
		if str(c.get("id", "")) == cid:
			return true
	return false


func _check_offers() -> void:
	_fresh(1, 1262, 5)
	_check(_has_id(crew.candidates_at("zhangzhou"), "zhang_tiemao"), "第一章漳州酒馆列张铁猫")
	_check(_has_id(crew.candidates_at("xinghua_harbor"), "chen_dayou"), "第一章兴化海口酒馆列陈大有")
	_check(not _has_id(crew.candidates_at("mingzhou"), "gu_sanjiang"), "第一章明州酒馆不列顾三江")
	_check(not _has_id(crew.candidates_at("wenzhou"), "wang_xin"), "第一章温州酒馆不列王信")
	_check(not _has_id(crew.candidates_at("guangzhou"), "liang_wangdou"), "第一章广州酒馆不列梁望斗")
	_check(crew.candidates_at("quanzhou").size() == 5, "第一章泉州候雇仍是五职（实 %d）" % crew.candidates_at("quanzhou").size())
	_check(_hire_port_name("wang_xin") == "", "第一章王信未到章节：人物志未识页不指温州")
	_fresh(2, 1262, 5)
	_check(_has_id(crew.candidates_at("mingzhou"), "gu_sanjiang"), "第二章明州酒馆列顾三江")
	_check(_has_id(crew.candidates_at("wenzhou"), "wang_xin"), "第二章温州酒馆列王信")
	_check(_hire_port_name("wang_xin") == "温州", "第二章王信人物志未识页指温州（实「%s」）" % _hire_port_name("wang_xin"))
	_check(not _has_id(crew.candidates_at("guangzhou"), "liang_wangdou"), "第二章广州酒馆不列梁望斗")
	_fresh(3, 1266, 5)
	for spec in NEW:
		var pid := str(spec.get("port", ""))
		var cid := str(spec.get("id", ""))
		_check(_has_id(crew.candidates_at(pid), cid), "第三章%s酒馆列%s" % [gm.get_port_name(pid), spec.get("name", "")])
	_check(_hire_port_name("liang_wangdou") == "广州", "第三章梁望斗人物志未识页指广州")
	_check(crew.candidates_at("quanzhou").size() == 6, "第三章泉州候雇仍是原六人（实 %d）" % crew.candidates_at("quanzhou").size())


func _hire_port_name(cid: String) -> String:
	return str(art.hire_port_name({"sources": {"crew_id": cid}}))


func _check_hire() -> void:
	for spec in NEW:
		_fresh(3, 1266, 5)
		var cid := str(spec.get("id", ""))
		var before := int(gs.money)
		var c: Dictionary = crew.candidate_def(cid)
		var fee := int(c.get("wage", 0)) * 2
		var r: Dictionary = crew.hire(cid)
		_check(bool(r.get("ok", false)) and str(crew.hired.get(str(c.get("role", "")), "")) == cid, "雇入 %s 成功" % cid)
		_check(int(gs.money) == before - fee, "雇入 %s 扣入伙钱 %d" % [cid, fee])
		_check(cid in gs.crew_history, "雇入 %s 记进 crew_history" % cid)
	_fresh(3, 1266, 5)
	_check(bool(crew.hire("liang_wangdou").get("ok", false)), "满编测试：先雇梁望斗")
	_check(bool(crew.hire("gu_sanjiang").get("ok", false)), "满编测试：再雇顾三江")
	_check(bool(crew.hire("chen_dayou").get("ok", false)), "满编测试：再雇陈大有")
	_check(bool(crew.hire("wang_xin").get("ok", false)), "满编测试：再雇王信")
	_check(crew.monthly_wage() == 480, "四职满编月俸四百八十（实 %d）" % crew.monthly_wage())
	var m0 := int(gs.money)
	var h0: Array = gs.crew_history.duplicate()
	var r: Dictionary = crew.hire("zhang_tiemao")
	_check(not bool(r.get("ok", false)) and str(r.get("msg", "")) == "船上已有舵工。一职只容一人。", "舵工位满：张铁猫不能入伙")
	_check(int(gs.money) == m0 and JSON.stringify(gs.crew_history) == JSON.stringify(h0), "舵工位满：钱与 crew_history 不动")
	crew.dismiss("duogong")
	_check(bool(crew.hire("zhang_tiemao").get("ok", false)), "辞去顾三江后可雇张铁猫")
	_check(str(crew.hired.get("duogong", "")) == "zhang_tiemao" and crew.monthly_wage() == 420, "换舵工后月俸四百二十（实 %d）" % crew.monthly_wage())


func _check_save() -> void:
	_fresh(3, 1266, 5)
	for cid in ["liang_wangdou", "gu_sanjiang", "chen_dayou", "wang_xin"]:
		_check(bool(crew.hire(str(cid)).get("ok", false)), "存档测试：雇入 %s" % cid)
	crew.unpaid_months = 2
	var hired0 := JSON.stringify(crew.hired)
	var hist0 := JSON.stringify(gs.crew_history)
	var wage0: int = int(crew.monthly_wage())
	var raw := JSON.stringify({"crew": crew.to_dict(), "state": gs.to_dict()})
	crew.from_dict({})
	gs.from_dict({})
	_check(crew.hired.is_empty() and gs.crew_history.is_empty(), "存档测试：清空职事与曾雇名录")
	var back = JSON.parse_string(raw)
	crew.from_dict(back.get("crew", {}))
	gs.from_dict(back.get("state", {}))
	_check(JSON.stringify(crew.hired) == hired0 and int(crew.unpaid_months) == 2, "存档：职事名册与欠饷月数来回不丢")
	_check(crew.monthly_wage() == wage0 and wage0 == 480, "存档：回读后月俸仍四百八十")
	_check(JSON.stringify(gs.crew_history) == hist0 and int(gs.chapter) == 3, "存档：crew_history 与章节来回不丢")
