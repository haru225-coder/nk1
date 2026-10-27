extends SceneTree
## Lane end2：第四章终局判定探针——列清六条结局的 id / 标题 / 场景 / 条件，验崖山以南与蒲家册上的次序、
## 互斥和结局幕接线。旗标全部用 Main.gd 已有的 set_flag，不新造旗。
## 用法：godot --headless --path . -s res://tools/qa_w57_endings_probe.gd
## 判词：QA_W57_ENDINGS cases=N fails=M；M>0 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W57_ENDINGS"
const WANT_IDS := ["yashan_south", "pu_register", "sea_letter", "history_wind", "ledger_distance", "south_sea"]

var _gs: Node
var _gm: Node
var _tally: ScriptErrTally
var _reported := false
var fails := 0
var cases := 0


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	if _gs == null or _gm == null:
		_expect(false, "autoload GameState / GameManager 在")
		_report()
		return

	var ch4: Dictionary = _gs.call("chapter_def", 4)
	var ends: Array = ch4.get("endings", [])
	_expect(ends.size() == WANT_IDS.size(), "第四章结局数 %d（现 %d）" % [WANT_IDS.size(), ends.size()])
	var ids: Array = []
	for e in ends:
		ids.append(str(e.get("id", "")))
	_expect(ids == WANT_IDS, "结局次序 %s" % str(ids))

	var scene_by_id := {}
	for s in _gm.get("scenes_data").get("scenes", []):
		scene_by_id[str(s.get("id", ""))] = s
	var texts := {}
	for e in ends:
		var eid := str(e.get("id", ""))
		var title := str(e.get("title", ""))
		var sid := str(e.get("scene", ""))
		var text := str(e.get("text", ""))
		_expect(eid != "" and title != "" and sid != "", "「%s」id / 标题 / 场景齐" % eid)
		_expect(not texts.has(text), "「%s」册页文字不与前面重复" % eid)
		texts[text] = eid
		var sc: Dictionary = scene_by_id.get(sid, {})
		_expect(not sc.is_empty(), "结局幕 %s 在 scenes.json" % sid)
		_expect(str(sc.get("chapter", "")) == "chapter_4", "%s 归第四章" % sid)
		_expect(str(sc.get("location", "")) == "champa", "%s 落在占城" % sid)
		_expect(str(sc.get("title", "")) == "了结：" + title, "%s 幕题与结局标题对得上" % sid)
		var back := false
		for c in sc.get("choices", []):
			if str(c.get("next", "")) == "champa":
				back = true
		_expect(back, "%s 选项回占城港上" % sid)

	var yashan: Dictionary = _ending_by_id(ends, "yashan_south")
	var pu: Dictionary = _ending_by_id(ends, "pu_register")
	_expect(str(yashan.get("require_flag", "")) == "yashan_turned_back", "崖山以南只认 yashan_turned_back")
	_expect(str(pu.get("require_flag", "")) == "sided_pu", "蒲家册上认 sided_pu")
	_expect(str(pu.get("hide_if_flag", "")) == "yashan_turned_back", "蒲家册上被崖山掉头压住")

	_expect(str(_pick(["sided_pu"]).get("id", "")) == "pu_register", "只立 sided_pu → 蒲家册上")
	_expect(str(_pick(["yashan_turned_back"]).get("id", "")) == "yashan_south", "只立崖山掉头 → 崖山以南")
	_expect(str(_pick(["sided_pu", "yashan_turned_back"]).get("id", "")) == "yashan_south",
		"两旗同立 → 崖山以南优先，不落蒲家册上")
	_expect(str(_pick([]).get("id", "")) == "south_sea", "无剧情旗 → 南海一纲兜底")

	for e in ends:
		var eid := str(e.get("id", ""))
		if eid == "south_sea":
			continue
		var flags: Array = []
		if str(e.get("require_flag", "")) != "":
			flags.append(str(e.get("require_flag", "")))
		elif (e.get("require_any", []) as Array).size() > 0:
			flags.append(str((e.get("require_any", []) as Array)[0]))
		if flags.is_empty():
			continue
		var got: Dictionary = _pick(flags)
		_expect(str(got.get("id", "")) == eid, "「%s」按表内旗标就位（实得 %s）" % [eid, str(got.get("id", ""))])

	var resolved: Dictionary = _resolve(["yashan_turned_back"])
	_expect(bool(resolved.get("resolved", false)) and str(_gs.get("ending_id")) == "yashan_south",
		"try_resolve：崖山掉头落 yashan_south")
	_expect(str(resolved.get("title", "")) == str(yashan.get("title", "")) and
		str(resolved.get("scene", "")) == "ending_yashan_south", "try_resolve 回崖山以南标题与结局幕")
	resolved = _resolve(["sided_pu"])
	_expect(bool(resolved.get("resolved", false)) and str(_gs.get("ending_id")) == "pu_register",
		"try_resolve：跟蒲落 pu_register")
	_expect(str(resolved.get("title", "")) == str(pu.get("title", "")) and
		str(resolved.get("scene", "")) == "ending_pu_register", "try_resolve 回蒲家册上标题与结局幕")
	resolved = _resolve(["sided_pu", "yashan_turned_back"])
	_expect(bool(resolved.get("resolved", false)) and str(_gs.get("ending_id")) == "yashan_south",
		"try_resolve：两旗同立仍落崖山以南")

	var cs: Dictionary = _read_json("res://data/cutscenes.json")
	for eid in ["yashan_south", "pu_register"]:
		var sid := str((cs.get("endings", {}) as Dictionary).get(eid, ""))
		_expect(sid != "", "cutscenes.endings 有 %s" % eid)
		var shots: Array = ((cs.get("cutscenes", {}) as Dictionary).get(sid, {}) as Dictionary).get("shots", [])
		_expect(shots.size() >= 3 and shots.size() <= 5, "%s 过场 %d 镜（3–5）" % [sid, shots.size()])
		var total := 0.0
		for sh in shots:
			total += float((sh as Dictionary).get("duration", 0.0))
		_expect(total >= 20.0 and total <= 35.0, "%s 过场 %.1f 秒（20–35）" % [sid, total])

	_gs.call("from_dict", {})
	_report()


func _ending_by_id(ends: Array, eid: String) -> Dictionary:
	for e in ends:
		if str((e as Dictionary).get("id", "")) == eid:
			return e
	return {}


func _pick(flags: Array) -> Dictionary:
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	for f in flags:
		_gs.call("set_flag", str(f))
	return _gs.call("pick_ending")


func _resolve(flags: Array) -> Dictionary:
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("money", 80000)
	_gs.set("peak_money", 80000)
	var ports: Array = []
	for p in _gm.get("ports_data").get("ports", []):
		ports.append(str((p as Dictionary).get("id", "")))
	_gs.set("visited_ports", ports)
	_gs.set("last_port", "champa")
	for f in flags:
		_gs.call("set_flag", str(f))
	return _gs.call("try_resolve_ending")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(bool(v[0]), str(v[1]))
	if fails == 0:
		print("%s cases=%d fails=0" % [TAG, cases])
		quit(0)
		return
	print("%s cases=%d fails=%d" % [TAG, cases, fails])
	quit(1)
