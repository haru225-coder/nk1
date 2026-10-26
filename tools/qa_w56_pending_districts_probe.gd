extends SceneTree
## lane d1 城中各处待画探针（headless，经门锁跑）。
##   godot --headless --path . -s res://tools/qa_w56_pending_districts_probe.gd
## 断言：
##   一、data/districts_pending/*.json 每处字段、货、传闻、入股、公凭、大比都说得通；
##       底图尚不存在；pending_art 为 true；id 在 districts.json 与全部 pending 里唯一。
##   二、游戏账本 Districts 只读 districts.json，不暴露任何 pending id。
## 判词：末行 QA_W56_PENDING_DISTRICTS PASS|FAIL cases=N fails=K。

const TAG := "QA_W56_PENDING_DISTRICTS"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var Book
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	Book = load("res://scripts/core/Districts.gd")
	if Book == null:
		_check(false, "城区账本没载入")
		_report()
		return
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	Book.wipe()
	_sec_pending()
	_report()


func _sec_pending() -> void:
	var base_txt := FileAccess.get_file_as_string("res://data/districts.json")
	var base_parsed = JSON.parse_string(base_txt)
	_check(typeof(base_parsed) == TYPE_DICTIONARY, "一、districts.json 可读")
	if typeof(base_parsed) != TYPE_DICTIONARY:
		return
	var base_rows: Array = base_parsed.get("districts", [])
	var base_count := base_rows.size()
	var seen_d := {}
	var seen_i := {}
	var bad := 0
	var banned := 0
	for row in base_rows:
		if typeof(row) == TYPE_DICTIONARY:
			seen_d[str(row.get("id", ""))] = true
	_walk_ids(base_parsed, seen_d)
	# collect pending files
	var dir := DirAccess.open("res://data/districts_pending")
	_check(dir != null, "一、pending 目录存在")
	if dir == null:
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	_check(files.size() > 0, "一、至少一个 pending 文件")
	var pending_ids: Array = []
	for f in files:
		var txt := FileAccess.get_file_as_string("res://data/districts_pending/" + f)
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			bad += 1
			continue
		var rows = parsed.get("districts", [])
		if typeof(rows) != TYPE_ARRAY:
			bad += 1
			continue
		for row in rows:
			if typeof(row) != TYPE_DICTIONARY:
				bad += 1
				continue
			var id := str(row.get("id", ""))
			var port := str(row.get("port", ""))
			var bg := str(row.get("bg", ""))
			if id == "" or seen_d.has(id):
				bad += 1
			else:
				seen_d[id] = true
			pending_ids.append(id)
			if gm.get_port_by_id(port).is_empty():
				bad += 1
			if str(row.get("name", "")) == "" or str(row.get("kind", "")) == "" or str(row.get("description", "")) == "":
				bad += 1
			if row.get("pending_art", false) != true:
				bad += 1
			if not bg.begins_with("bg_dist_") or not bg.ends_with(".jpg") or FileAccess.file_exists("res://assets/" + bg):
				bad += 1
			var bag: Array = []
			_walk(row, bag)
			for s in bag:
				var line := str(s)
				if line.contains("石像") or line.contains("雕像") or line.contains("牌坊"):
					banned += 1
			var ixs = row.get("interactions", [])
			if typeof(ixs) != TYPE_ARRAY or ixs.is_empty():
				bad += 1
				continue
			for ix in ixs:
				if typeof(ix) != TYPE_DICTIONARY:
					bad += 1
					continue
				var iid := str(ix.get("id", ""))
				var typ := str(ix.get("type", ""))
				if iid == "" or iid == id or seen_i.has(iid) or not Book.TYPES.has(typ):
					bad += 1
				seen_i[iid] = true
				if str(ix.get("label", "")) == "" or str(ix.get("text", "")) == "":
					bad += 1
				if typ == "buy" or typ == "sell":
					if gm.get_good_by_id(str(ix.get("good", ""))).is_empty() or int(ix.get("qty", 0)) <= 0:
						bad += 1
					var port_market: Dictionary = gm.get_port_by_id(port).get("market", {})
					if not port_market.has(str(ix.get("good", ""))):
						bad += 1
				if typ == "rumor" and not _rumor_shape(ix):
					bad += 1
				if typ == "invest" and not _invest_shape(ix):
					bad += 1
				if typ == "licence":
					if not str(ix.get("licence", "")).begins_with("lic_"):
						bad += 1
				if typ == "hire" and (str(ix.get("who", "")) == "" or int(ix.get("wage", 0)) <= 0):
					bad += 1
				if typ == "choice":
					var opts = ix.get("options", [])
					if typeof(opts) != TYPE_ARRAY or opts.is_empty():
						bad += 1
					else:
						for opt in opts:
							if typeof(opt) != TYPE_DICTIONARY or str(opt.get("id", "")) == "":
								bad += 1
							elif opt.has("rumor") and not _rumor_shape(opt.get("rumor", {})):
								bad += 1
				if bool(ix.get("exam", false)):
					var gate: Dictionary = ix.get("unlock", {})
					if not _same_ints(gate.get("years", []), Book.EXAM_YEARS) or not _same_ints(gate.get("months", []), Book.EXAM_MONTHS):
						bad += 1
				var unlock = ix.get("unlock", {})
				if typeof(unlock) == TYPE_DICTIONARY:
					for k in unlock.keys():
						if not _allowed_unlock_key(str(k)):
							bad += 1
				var row_unlock = row.get("unlock", {})
				if typeof(row_unlock) == TYPE_DICTIONARY:
					for k in row_unlock.keys():
						if not _allowed_unlock_key(str(k)):
							bad += 1
	_check(bad == 0, "一、pending 处的字段、货、传闻、入股、公凭、大比都说得通（坏 %d）" % bad)
	_check(banned == 0, "一、pending 全文没有石像、雕像、牌坊（撞上 %d 处）" % banned)
	_check(int(pending_ids.size()) > 0, "一、pending 至少一处")
	# ledger does not expose pending ids
	var ledger_bad := 0
	for pid in pending_ids:
		if not Book.district(str(pid)).is_empty():
			ledger_bad += 1
	_check(ledger_bad == 0, "二、账本不暴露任何 pending id（漏 %d）" % ledger_bad)
	_check(Book.rows().size() == base_count, "二、账本只读 districts.json（%d 处）" % base_count)


func _walk(v, bag: Array) -> void:
	match typeof(v):
		TYPE_STRING:
			bag.append(v)
		TYPE_DICTIONARY:
			for k in v:
				_walk(v[k], bag)
		TYPE_ARRAY:
			for x in v:
				_walk(x, bag)


func _walk_ids(v, seen: Dictionary) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		return
	if v.has("districts") and typeof(v.districts) == TYPE_ARRAY:
		for row in v.districts:
			if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) != "":
				seen[str(row.get("id", ""))] = true


func _rumor_shape(spec) -> bool:
	if typeof(spec) != TYPE_DICTIONARY:
		return false
	var port := str(spec.get("port", ""))
	var good := str(spec.get("good", ""))
	var mul := float(spec.get("mul", 1.0))
	if gm.get_port_by_id(port).is_empty() or gm.get_good_by_id(good).is_empty():
		return false
	if mul <= 0.0 or is_equal_approx(mul, 1.0):
		return false
	return eco.is_traded(port, good) and eco.rates.get(port, {}).has(good)


func _invest_shape(ix: Dictionary) -> bool:
	var costs = ix.get("costs", [])
	var monthly = ix.get("monthly", [])
	if typeof(costs) != TYPE_ARRAY or typeof(monthly) != TYPE_ARRAY or costs.is_empty() or costs.size() != monthly.size():
		return false
	for c in costs:
		if int(c) <= 0:
			return false
	return str(ix.get("shop", "")) != ""


func _same_ints(got, want: Array) -> bool:
	if typeof(got) != TYPE_ARRAY or got.size() != want.size():
		return false
	for i in got.size():
		if int(got[i]) != int(want[i]):
			return false
	return true


func _allowed_unlock_key(k: String) -> bool:
	return ["year_min", "year_max", "years", "months", "chapter_min", "war_in", "war_not", "require_flag", "hide_if_flag", "favour_min", "needs_licence", "needs_hire", "siege"].has(k)
