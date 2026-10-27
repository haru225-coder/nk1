extends SceneTree
## lane w57 章二三条港岸委托线探针（headless，经门锁跑）。
##   godot --headless --path . -s res://tools/qa_w57_quest_probe.gd
## 断言：拍账三链的条件与次序、十二幕的选项与账目、真起 Main 逐港自动接演，
## 以及终局 / 非委托港不演。判词末行 QA_W57_QUEST PASS|FAIL cases=N fails=K。

const TAG := "QA_W57_QUEST"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORTS := ["quanzhou", "mingzhou", "hakata", "champa"]
const NEW_SCENES := [
	"quest_sulfur_offer", "quest_sulfur_accept", "quest_sulfur_mingzhou", "quest_sulfur_return",
	"quest_hakata_offer", "quest_hakata_letter", "quest_hakata_search", "quest_hakata_return",
	"quest_champa_offer", "quest_champa_terms", "quest_champa_grove", "quest_champa_return",
]
const NEW_BEATS := [
	"quest_sulfur_offer", "quest_sulfur_mingzhou", "quest_sulfur_return",
	"quest_hakata_offer", "quest_hakata_search", "quest_hakata_return",
	"quest_champa_offer", "quest_champa_grove", "quest_champa_return",
]
const FLAGS := ["sulfur_escort_taken", "hakata_errand_taken", "champa_agarwood_taken"]
const EFFECT_KEYS := [
	"money", "fame", "days", "flag", "chapter", "network", "merchant_credit",
	"sea_tendency", "scholar_tendency", "ledger_note", "supplies", "cargo",
	"cargo_loss", "ship", "discovery",
]

var _main: Node
var gs: Node
var gm: Node
var _book
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
	_book = load("res://scripts/core/PortBeats.gd").new()
	_book.init(gm.port_beats_data.get("beats", []))
	print("== 一、表")
	_sec_table()
	print("== 二、读账")
	_sec_graph()
	print("== 三、真起 Main")
	await _sec_main()
	_report()


func _sec_table() -> void:
	var pb := _json("res://data/port_beats.json")
	var beats = pb.get("beats", [])
	_check(typeof(beats) == TYPE_ARRAY, "一、port_beats 顶层是 beats 数组")
	if typeof(beats) != TYPE_ARRAY:
		return
	var entries := {}
	var ids := {}
	var new_count := 0
	var bad := 0
	for raw in beats:
		if typeof(raw) != TYPE_DICTIONARY:
			bad += 1
			continue
		var b: Dictionary = raw
		var entry := str(b.get("entry", ""))
		var bid := str(b.get("id", ""))
		if entry == "" or bid == "" or entries.has(entry) or ids.has(bid):
			bad += 1
		entries[entry] = true
		ids[bid] = true
		if gm.get_port_by_id(str(b.get("port", ""))).is_empty() or int(b.get("order", 0)) <= 0:
			bad += 1
		if entry.begins_with("quest_"):
			new_count += 1
			if not (entry in NEW_BEATS) or gm.get_scene_by_id(entry).is_empty():
				bad += 1
	_check(bad == 0 and beats.size() == 18 and new_count == NEW_BEATS.size(),
		"一、十八针、九针新委托，entry / id 唯一，港与 order 落地（坏 %d）" % bad)
	var chain_bad := 0
	for entry in NEW_BEATS:
		var b := _beat(entry)
		if b.is_empty():
			chain_bad += 1
			continue
		for s in _arr((b.get("requires", {}) as Dictionary).get("seen", [])):
			if not entries.has(str(s)):
				chain_bad += 1
		for s in _arr(b.get("stop_before", [])):
			if not entries.has(str(s)):
				chain_bad += 1
		for f in _arr((b.get("requires", {}) as Dictionary).get("has_flag", [])):
			if str(f) == "":
				chain_bad += 1
	_check(chain_bad == 0, "一、三链的 requires / stop_before 都指得到本表（坏 %d）" % chain_bad)
	var want := {
		"quest_sulfur_offer": ["quanzhou", 110, ["chapter2_letter"], [], ["quest_sulfur_mingzhou"]],
		"quest_sulfur_mingzhou": ["mingzhou", 10, ["quest_sulfur_offer"], ["sulfur_escort_taken"], ["quest_sulfur_return"]],
		"quest_sulfur_return": ["quanzhou", 120, ["quest_sulfur_mingzhou"], ["sulfur_escort_taken"], []],
		"quest_hakata_offer": ["hakata", 20, ["hakata_ledger"], ["temple_letter"], ["quest_hakata_search"]],
		"quest_hakata_search": ["hakata", 30, ["quest_hakata_offer"], ["hakata_errand_taken"], ["quest_hakata_return"]],
		"quest_hakata_return": ["hakata", 40, ["quest_hakata_search"], ["hakata_errand_taken"], []],
		"quest_champa_offer": ["champa", 10, [], [], ["quest_champa_grove"]],
		"quest_champa_grove": ["champa", 20, ["quest_champa_offer"], ["champa_agarwood_taken"], ["quest_champa_return"]],
		"quest_champa_return": ["champa", 30, ["quest_champa_grove"], ["champa_agarwood_taken"], []],
	}
	var order_bad := 0
	for entry in want.keys():
		var b := _beat(entry)
		var w: Array = want[entry]
		var req: Dictionary = b.get("requires", {})
		if str(b.get("port", "")) != str(w[0]) or int(b.get("order", 0)) != int(w[1]):
			order_bad += 1
		if not _same(_arr(req.get("seen", [])), w[2]) or not _same(_arr(req.get("has_flag", [])), w[3]):
			order_bad += 1
		if not _same(_arr(b.get("stop_before", [])), w[4]):
			order_bad += 1
		if entry == "quest_champa_offer" and (int(req.get("chapter_at_least", 0)) != 2 or int(req.get("chapter_at_most", 0)) != 3):
			order_bad += 1
	_check(order_bad == 0, "一、三条链的港、拍序、前置与下一拍逐针对上（坏 %d）" % order_bad)
	var sulfur_req: Dictionary = _beat("quest_sulfur_offer").get("requires", {})
	_check(int(sulfur_req.get("visited_at_least", 0)) == 2,
		"一、硫黄首针候首次记港之后再记一港（visited_at_least=2）")
	var sc := _json("res://data/scenes.json")
	var scenes = sc.get("scenes", [])
	var by_id := {}
	if typeof(scenes) == TYPE_ARRAY:
		for s in scenes:
			if typeof(s) == TYPE_DICTIONARY:
				by_id[str(s.get("id", ""))] = s
	var scene_bad := 0
	var flags := {}
	var reach := {}
	for e in NEW_BEATS:
		reach[e] = true
	for sid in NEW_SCENES:
		if not by_id.has(sid):
			scene_bad += 1
			continue
		var s: Dictionary = by_id[sid]
		if str(s.get("chapter", "")) != "chapter_2" or gm.get_port_by_id(str(s.get("location", ""))).is_empty():
			scene_bad += 1
		for raw in _arr(s.get("choices", [])):
			if typeof(raw) != TYPE_DICTIONARY:
				scene_bad += 1
				continue
			var c: Dictionary = raw
			var nx := str(c.get("next", ""))
			if nx == "" or (gm.get_scene_by_id(nx).is_empty() and gm.get_port_by_id(nx).is_empty()):
				scene_bad += 1
			var eff = c.get("effects", {})
			if typeof(eff) != TYPE_DICTIONARY:
				scene_bad += 1
				continue
			for k in (eff as Dictionary).keys():
				if not (str(k) in EFFECT_KEYS):
					scene_bad += 1
				if str(k) == "ledger_note":
					scene_bad += 1
				if str(k) == "flag":
					flags[str((eff as Dictionary).get(k, ""))] = true
				if str(k) == "cargo":
					for g in _arr((eff as Dictionary).get(k, [])):
						if gm.get_good_by_id(str(g)).is_empty():
							scene_bad += 1
	var changed := true
	while changed:
		changed = false
		for sid in reach.keys():
			if not by_id.has(sid):
				continue
			for raw in _arr((by_id[sid] as Dictionary).get("choices", [])):
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var nx := str((raw as Dictionary).get("next", ""))
				if by_id.has(nx) and not reach.has(nx):
					reach[nx] = true
					changed = true
	var unreached := 0
	for sid in NEW_SCENES:
		if not reach.has(sid):
			unreached += 1
	_check(scene_bad == 0 and unreached == 0, "一、十二幕都在章二、选项落地、账目键接得住、三旗有主、从节拍走得到（坏 %d / 断 %d）" % [scene_bad, unreached])
	var bc: Dictionary = (load("res://scripts/core/PortBeats.gd") as GDScript).get_script_constant_map()
	var ports: Array = bc.get("QUEST_PORTS", [])
	var tails: Array = bc.get("QUEST_TAIL_ENTRIES", [])
	_check(_same(ports, PORTS) and not ("ryukyu" in ports) and not ("xinghua" in ports)
		and _same(tails, ["quest_sulfur_return", "quest_hakata_return", "quest_champa_return"]),
		"一、接演港只放四港、流求与兴化不演；尾针常量与三链收尾同")


func _sec_graph() -> void:
	var seen := ["monk", "merchant", "dock", "prepare", "return_quanzhou", "chapter2_letter"]
	var flags := []
	var visited := ["quanzhou", "mingzhou", "ryukyu"]
	_check(_book.due("quanzhou", seen, flags, ["quanzhou"], 2, false).is_empty(),
		"二、硫黄链：首次记港当页不接契（只记泉州一港）")
	_check(_entry(_book.due("quanzhou", seen, flags, ["quanzhou", "mingzhou"], 2, false)) == "quest_sulfur_offer",
		"二、硫黄链：记过首港再记一港，回泉州接契")
	_check(_entry(_book.due("quanzhou", seen, flags, visited, 2, false)) == "quest_sulfur_offer",
		"二、硫黄链：章二信已演，泉州该演接契")
	seen.append("quest_sulfur_offer")
	_check(_entry(_book.due("mingzhou", seen, flags, visited, 2, false)).is_empty(),
		"二、硫黄链：没接契，明州不演抽解")
	flags.append("sulfur_escort_taken")
	_check(_entry(_book.due("mingzhou", seen, flags, visited, 2, false)) == "quest_sulfur_mingzhou",
		"二、硫黄链：接契后明州演抽解")
	seen.append("quest_sulfur_mingzhou")
	_check(_entry(_book.due("quanzhou", seen, flags, visited, 2, false)) == "quest_sulfur_return",
		"二、硫黄链：抽解演过，回泉州演收尾")
	seen.append("quest_sulfur_return")
	_check(_book.due("quanzhou", seen, flags, visited, 2, false).is_empty(),
		"二、硫黄链：收尾演过即收束")
	var hk_seen := ["hakata_ledger"]
	var hk_flags := ["cargo_hakata"]
	_check(_entry(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false)).is_empty(),
		"二、博多链：没有承天寺短札不演寻人")
	hk_flags.append("temple_letter")
	_check(_entry(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false)) == "quest_hakata_offer",
		"二、博多链：旧账与短札都在，演接信")
	hk_seen.append("quest_hakata_offer")
	_check(_entry(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false)).is_empty(),
		"二、博多链：没应下寻人，不跳下一幕")
	hk_flags.append("hakata_errand_taken")
	_check(_entry(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false)) == "quest_hakata_search",
		"二、博多链：应下寻人后演箱崎宫")
	hk_seen.append("quest_hakata_search")
	_check(_entry(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false)) == "quest_hakata_return",
		"二、博多链：寻到人后演回唐房")
	hk_seen.append("quest_hakata_return")
	_check(_book.due("hakata", hk_seen, hk_flags, ["hakata"], 2, false).is_empty(),
		"二、博多链：谢礼演过即收束")
	var cp_seen := []
	var cp_flags := []
	_check(_book.due("champa", cp_seen, cp_flags, ["champa"], 1, false).is_empty(),
		"二、占城链：章一不演香约")
	_check(_entry(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false)) == "quest_champa_offer",
		"二、占城链：章二演香约")
	_check(_book.due("champa", cp_seen, cp_flags, ["champa"], 4, false).is_empty(),
		"二、占城链：章四让位终章、不演香约")
	cp_seen.append("quest_champa_offer")
	_check(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false).is_empty(),
		"二、占城链：没应下香约不演香库")
	cp_flags.append("champa_agarwood_taken")
	_check(_entry(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false)) == "quest_champa_grove",
		"二、占城链：应下香约后演香库")
	cp_seen.append("quest_champa_grove")
	_check(_entry(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false)) == "quest_champa_return",
		"二、占城链：验货后演回账")
	cp_seen.append("quest_champa_return")
	_check(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false).is_empty(),
		"二、占城链：回账演过即收束")
	var ended_bad := 0
	for port_id in PORTS:
		if not _book.due(port_id, [], [], [], 9, true).is_empty():
			ended_bad += 1
	_check(ended_bad == 0, "二、终局后四港都不演")
	ProjectSettings.set_setting("nk1/port_beats_runtime", false)
	_check(_book.due("champa", cp_seen, cp_flags, ["champa"], 2, false).is_empty(),
		"二、开关关掉不演")
	ProjectSettings.set_setting("nk1/port_beats_runtime", true)


func _sec_main() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	_fresh(2, [], [], ["monk", "merchant", "dock", "prepare", "return_quanzhou", "chapter2_letter"])
	_main.load_scene("quanzhou")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quanzhou" and bool(_main.get("port_mode").visible)
		and not ("quest_sulfur_offer" in gs.beats_seen),
		"三、新局首记泉州停在港页、不被硫黄接契截去")
	gs.visit_port("mingzhou")
	_main.load_scene("quanzhou")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_sulfur_offer", "三、记过二港再回泉州，自动演接契")
	_fresh(2, ["quanzhou", "mingzhou", "ryukyu"], [], ["monk", "merchant", "dock", "prepare", "return_quanzhou", "chapter2_letter"])
	_main.load_scene("quanzhou")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_sulfur_offer", "三、硫黄线首抵泉州自动演接契")
	var btn := _find_button(_main, "接下契书，先验箱上的铅封与押字")
	_check(btn != null, "三、接契幕有接下钮")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(gs.has_flag("sulfur_escort_taken") and int(gs.money) == 1030
		and str(_main.get("current_scene_id")) == "quest_sulfur_accept",
		"三、接契落旗、脚钱三十、翻到验箱幕")
	btn = _find_button(_main, "把样硫与旧公凭收进随身匣，回港候风")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_main.load_scene("mingzhou")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_sulfur_mingzhou", "三、明州自动演抽解")
	btn = _find_button(_main, "照抽解旧例办，余货换小船即刻南下")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_main.load_scene("quanzhou")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_sulfur_return", "三、回泉州自动演收尾")
	var money_before := int(gs.money)
	btn = _find_button(_main, "照契收足脚钱，把抽解与博买的账一并入册")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(int(gs.money) == money_before + 180 and str(_main.get("current_scene_id")) == "quanzhou",
		"三、硫黄收尾脚钱一百八十、人回港页")
	_fresh(2, ["hakata"], ["cargo_hakata", "temple_letter"], ["hakata_ledger"])
	_main.load_scene("hakata")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_hakata_offer", "三、博多旧账与短札齐，自动演接信")
	btn = _find_button(_main, "应下寻人，先把吴小七的相貌与衣衫问清")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(gs.has_flag("hakata_errand_taken") and str(_main.get("current_scene_id")) == "quest_hakata_letter",
		"三、应下寻人落旗、翻到名册幕")
	btn = _find_button(_main, "沿松林旧路去箱崎宫，先找那间客舍")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(str(_main.get("current_scene_id")) == "quest_hakata_search", "三、回博多自动演箱崎宫")
	btn = _find_button(_main, "先替他向知客僧报平安，再扶他回唐房")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(str(_main.get("current_scene_id")) == "quest_hakata_return", "三、回博多自动演回唐房")
	_fresh(1, ["champa"], [], [])
	_main.load_scene("champa")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "champa", "三、占城章一不演香约")
	gs.chapter = 2
	_main.load_scene("champa")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "quest_champa_offer", "三、占城章二自动演香约")
	btn = _find_button(_main, "应下香约，先随通事去香库验货")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(gs.has_flag("champa_agarwood_taken") and str(_main.get("current_scene_id")) == "quest_champa_terms",
		"三、应下香约落旗、翻到验样幕")
	btn = _find_button(_main, "只按沉水与栈香分等，黄熟另记一账")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(str(_main.get("current_scene_id")) == "quest_champa_grove", "三、回占城自动演香库外的雨")
	btn = _find_button(_main, "先装沉水，栈香留待下一船")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(str(_main.get("current_scene_id")) == "quest_champa_return", "三、回占城自动演回账")
	money_before = int(gs.money)
	btn = _find_button(_main, "收下象牙，照契结清沉香账")
	if btn != null:
		btn.pressed.emit()
		await _settle(4)
	_check(int(gs.money) == money_before + 160 and str(_main.get("current_scene_id")) == "champa",
		"三、占城回账脚钱一百六十、人回港页")
	_fresh(2, ["ryukyu"], [], [])
	_main.load_scene("ryukyu")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "ryukyu" and not ("ryukyu_bay" in gs.beats_seen),
		"三、流求不在委托港里，仍走旧港页")
	_fresh(2, ["champa"], [], [])
	gs.ended = "qa_end"
	_main.load_scene("champa")
	await _settle(6)
	_check(str(_main.get("current_scene_id")) == "champa" and not ("quest_champa_offer" in gs.beats_seen),
		"三、终局后占城不演香约")
	gs.ended = ""


func _fresh(chapter: int, visited: Array, flags: Array, seen: Array) -> void:
	gs.from_dict({})
	gs.chapter = chapter
	gs.money = 1000
	gs.visited_ports = visited.duplicate()
	gs.loaded_with_beats = true
	for e in seen:
		gs.beat_mark(str(e))
	for f in flags:
		gs.set_flag(str(f))


func _beat(entry: String) -> Dictionary:
	for raw in gm.port_beats_data.get("beats", []):
		if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("entry", "")) == entry:
			return raw
	return {}


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _arr(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


func _same(got, want: Array) -> bool:
	if typeof(got) != TYPE_ARRAY or (got as Array).size() != want.size():
		return false
	for i in (got as Array).size():
		if str((got as Array)[i]) != str(want[i]):
			return false
	return true


func _entry(b: Dictionary) -> String:
	return str(b.get("entry", "")) if not b.is_empty() else ""


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null
