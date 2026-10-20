extends SceneTree
## lane w54-tutorial 新手上手小笺专项探针（headless，经门锁跑）：
##   godot --headless --path . -s res://tools/qa_w54_tutorial_notes_probe.gd
## 一段钉一条、回退即红：
##   一、表与文案：data/tutorial_notes.json 六条（靠港 / 货引 / 牙行 / 看风 / 遇盗 / 航海日志）齐、不多不少，与海战小笺不重名；小题两到五字、
##       正文二十到八十字、句号收尾、不夹半角标点与叹号、括号配对、不写「你」，都挂开关 tutorial_notes（表里有、默认开）；
##       小笺层认得这一本（条目、已读旗前缀 tutorial_note_），海战那本照旧（table() 只是 combat_notes.json、旗前缀 combat_note_）；
##       正文里的数对得上玩法：买路财一成五、至少一百，「候风再发」候三日。
##   二、谁看得到：没定过的（旧档、工具里）不出、不写旗；本机没有存档 → 定 tutorial_on、出；有存档 → 定 tutorial_off、一张不出；
##       定下的旗与已读旗过 SaveLoad 旗标清洗与 JSON 来回仍在；开关 tutorial_notes 关、讲解小笺总开关 combat_notes 关都不出；看过的不再出。
##   三、港页与牙行（真起 Main）：进寻常港页挂候场，页面静下来才出「靠港」、记已读；换页题签盖着时不出、揭开就出；
##       蒲家记过一笔再出「货引」、排在后面；没轮到就离了港页的撤下、不记已读；进牙行出「牙行」，没轮到就出门的撤下；终局港页不出；
##       头一回进市舶司也出「货引」（与被蒲家记上一笔后的港页先到哪处在哪处出），没轮到就出门的撤下，看过了港页不再出；
##       到过两港、本机还没有存档的港页出「航海日志」，只到过一港、或已记过一卷的不出。
##   四、海图与遇盗（真按「看风」换上海图）：开海图出「看风」；海上遇盗先让路（「看风」收起）再出「遇盗」；选了「扬帆逃走」面板收起，
##       「遇盗」当场收起；没轮到就「迎战」的撤下、不记已读、海图那一层不留它（不压到海战小笺上）；没轮到就发了舶的「看风」撤下。
##   五、不打断老玩家：tutorial_off 的一局，港页、牙行、海图、遇盗都不挂候场、不排、不写已读旗。
## 判词：末行 QA_W54_TUTORIAL_NOTES PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_TUTORIAL_NOTES"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
## 小笺件与新手件不读 autoload 标识符，可 preload；Main / SeaChart 直读 autoload，_run 里现 load
const N := preload("res://scripts/ui/CombatNotes.gd")
const T := preload("res://scripts/ui/TutorialNotes.gd")
const CHART_PATH := "res://scenes/SeaChart.tscn"

const EXPECT_IDS := ["port", "permit", "market", "chart", "pirate", "logbook"]
const EXPECT_TITLES := {"port": "靠港", "permit": "货引", "market": "牙行", "chart": "看风", "pirate": "遇盗", "logbook": "航海日志"}

var _gs: Node = null
var _gm: Node = null
var _fleet: Node = null
var _cal: Node = null
var _crew: Node = null
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
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	cine.set("auto_opening", false)
	cine.set("opening_seen", true)
	_gs = root.get_node("GameState")
	_gm = root.get_node("GameManager")
	_fleet = root.get_node("Fleet")
	_cal = root.get_node("Calendar")
	_crew = root.get_node("Crew")
	var keep := {"gs": _gs.call("to_dict"), "fleet": _fleet.call("to_dict"), "cal": _cal.call("to_dict"), "crew": _crew.call("to_dict")}
	_Switches.reset()
	print("== 一、表与文案")
	await _sec_table()
	print("== 二、谁看得到")
	await _sec_who()
	print("== 三、港页与牙行")
	await _sec_shore()
	print("== 四、海图与遇盗")
	await _sec_chart()
	print("== 五、不打断老玩家")
	await _sec_veteran()
	_Switches.reset()
	_gs.call("from_dict", keep["gs"])
	_fleet.call("from_dict", keep["fleet"])
	_cal.call("from_dict", keep["cal"])
	_crew.call("from_dict", keep["crew"])
	_gm.set("depart_note", "")
	await process_frame
	_report()


# ── 共用 ──────────────────────────────────────────────

func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## 开局光景：泉州、宝祐三年三月初一、小艍一条六人、钱 940、无货引、蒲家留意 0；港口节拍全记过（港页不演戏）；flags 只留给的那几枚
func _opening(flags: Array = []) -> void:
	_gs.call("from_dict", {})
	_gs.set("chapter", 1)
	_gs.set("money", 940)
	_gs.set("last_port", "quanzhou")
	_gs.set("visited_ports", ["quanzhou"])
	_gs.set("has_customs_permit", false)
	_gs.set("pu_attention", 0)
	_gs.set("loaded_with_beats", true)
	for b in _gm.get("port_beats_data").get("beats", []):
		_gs.call("beat_mark", str((b as Dictionary).get("entry", "")))
	for f in flags:
		_gs.call("set_flag", str(f))
	_cal.call("from_dict", {"year": 1255, "month": 3, "day": 1})
	_crew.call("from_dict", {})
	_fleet.call("from_dict", {"ships": [{"type": "sampan", "name": "无名小艍", "durability": 120.0, "max_durability": 120.0,
		"crew": 6, "sail_level": 1, "armor_level": 1, "cargo": {}}], "water": 80, "food": 80, "morale": 70})
	_gm.set("depart_note", "")


func _has(flag: String) -> bool:
	return bool(_gs.call("has_flag", flag))


func _read(id: String) -> bool:
	return _has(N.flag_of(id))


## host 下小笺层：正出着的 + 排着的
func _seen(host: Node) -> Array:
	var lay = N.layer_of(host)
	if lay == null:
		return []
	var out: Array = []
	if str(lay.call("current")) != "":
		out.append(str(lay.call("current")))
	for id in lay.call("pending"):
		out.append(str(id))
	return out


func _current(host: Node) -> String:
	var lay = N.layer_of(host)
	return str(lay.call("current")) if lay != null else ""


## 小笺层正在收起（淡出那 0.4 秒里 current 还是那一张）
func _closing(host: Node) -> bool:
	var lay = N.layer_of(host)
	return lay != null and bool(lay.get("_closing"))


func _waiters(host: Node) -> Array:
	var out: Array = []
	for c in host.get_children():
		if String(c.name).begins_with(T.WAIT_PREFIX):
			out.append(String(c.name).trim_prefix(T.WAIT_PREFIX))
	return out


## 等到 host 小笺层正出着 id（墙钟上界 sec）
func _until_current(host: Node, id: String, sec := 3.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		if is_instance_valid(host) and _current(host) == id:
			return true
		await process_frame
	return false


func _new_main(scene := "quanzhou") -> Node:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.call("load_scene", scene)
	await _frames(2)
	return main


func _drop(n: Node) -> void:
	if n != null and is_instance_valid(n):
		if current_scene == n:
			current_scene = null
		n.queue_free()
	await _frames(2)


## 港页按「看风」真换上海图（Main._on_set_sail → change_scene_to_file）
func _sail_from(main: Node) -> Node:
	main.call("_on_set_sail")
	for _i in 100:
		await process_frame
		var cs := current_scene
		if cs != null and is_instance_valid(cs) and cs.scene_file_path == CHART_PATH and cs.is_node_ready():
			await process_frame
			return cs
	return null


# ── 一、表与文案 ──────────────────────────────────────

func _sec_table() -> void:
	var tab: Dictionary = N.tutorial_table()
	var ids: Array = tab.keys()
	ids.sort()
	var want := EXPECT_IDS.duplicate()
	want.sort()
	_check(ids == want, "新手小笺 %d 条，与清点表一致（%s）" % [ids.size(), ids])
	var clash := ids.filter(func(i): return N.table().has(i))
	_check(clash.is_empty(), "与海战小笺不重名（撞名 %s）" % [clash])
	var bad := []
	var half := RegEx.create_from_string("[,.!?;:]|！")
	for id in ids:
		var e: Dictionary = tab[id]
		var t := str(e.get("title", ""))
		var x := str(e.get("text", ""))
		if t != str(EXPECT_TITLES.get(id, "")) or t.length() < 2 or t.length() > 5:
			bad.append("%s 小题「%s」" % [id, t])
		if x.length() < 20 or x.length() > 80 or not x.ends_with("。"):
			bad.append("%s 正文 %d 字、收尾「%s」" % [id, x.length(), x.right(1)])
		if half.search(t + x) != null:
			bad.append("%s 夹了半角标点或叹号" % id)
		if x.contains("你"):
			bad.append("%s 写了「你」" % id)
		for pair in [["「", "」"], ["『", "』"], ["（", "）"], ["《", "》"]]:
			if x.count(pair[0]) != x.count(pair[1]):
				bad.append("%s %s%s 不齐" % [id, pair[0], pair[1]])
		if N.switch_keys(e) != PackedStringArray([T.SWITCH]):
			bad.append("%s 开关键 %s" % [id, N.switch_keys(e)])
	_check(bad.is_empty(), "各条小题 / 正文 / 标点 / 开关键合规（%s）" % [bad])
	_check(_Switches.DEFAULTS.get(T.SWITCH) == true, "开关 %s 在 CombatSwitches 表里、默认开" % T.SWITCH)
	_check(str(N.entry("port").get("title", "")) == "靠港" and N.flag_of("port") == "tutorial_note_port",
		"小笺层认得新手那一本：条目、已读旗 %s" % N.flag_of("port"))
	_check(not N.table().has("port") and str(N.entry("sea").get("title", "")) == "风与潮" and N.flag_of("sea") == "combat_note_sea",
		"海战那一本照旧：table() 不含新手条目，「风与潮」旗 %s" % N.flag_of("sea"))
	# 正文里的数对得上玩法（钉源码：哪天改了买路财、逃不脱丢的货、候风日数，这几张小笺跟着改）
	var src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	var pirate_text := str(tab.get("pirate", {}).get("text", ""))
	var chart_text := str(tab.get("chart", {}).get("text", ""))
	_check(src.contains("maxi(100, int(GameState.money * 0.15))") and pirate_text.contains("一成五") and pirate_text.contains("至少一百"),
		"「遇盗」写买路财一成五、至少一百：SeaChart._on_pay_pirates 照此收")
	_check(src.contains("Fleet.lose_cargo_ratio(0.18)") and pirate_text.contains("一两成货"),
		"「遇盗」写逃不脱丢一两成货：SeaChart._on_flee_pirates 丢 0.18")
	var redraw := src.substr(src.find("func _on_redraw_hand"), 260)
	_check(redraw.contains("GameManager.advance_days(3)") and chart_text.contains("候三日"), "「看风」写候风再发候三日：_on_redraw_hand 过 3 日")
	await process_frame


# ── 二、谁看得到 ──────────────────────────────────────

func _sec_who() -> void:
	_opening()
	_check(not T.active() and not _has(T.FLAG_ON) and not _has(T.FLAG_OFF),
		"没定过的（旧档、工具里）：不出，也不替人定、不写旗")
	var h := Node.new()
	root.add_child(h)
	_check(not T.offer(h, "port") and h.get_child_count() == 0, "没定过的：排不上、不挂候场")
	var any := false
	var sl: Node = root.get_node("SaveLoad")
	for slot in range(1, 4):
		any = any or bool(sl.call("has_save", slot))
	_check(T.any_save() == any, "本机有没有存档与 SaveLoad.has_save 三卷一致（%s）" % str(any))
	_check(T.decide(false) and _has(T.FLAG_ON) and not _has(T.FLAG_OFF) and T.active() and T.want("port"),
		"本机没有存档：定 tutorial_on，这一局出新手小笺")
	_opening()
	_check(not T.decide(true) and _has(T.FLAG_OFF) and not T.active() and not T.want("port") and not T.offer(h, "port"),
		"本机有存档：定 tutorial_off，一张不出")
	_opening([T.FLAG_ON])
	_gs.call("set_flag", N.flag_of("port"))
	_check(not T.want("port") and T.want("market"), "看过的不再出，没看过的照出")
	var sl_state: Dictionary = sl.call("_harden_state", _gs.call("to_dict"))
	var back = JSON.parse_string(JSON.stringify(sl_state))
	_gs.call("from_dict", {})
	var gone := not _has(T.FLAG_ON)
	_gs.call("from_dict", back)
	_check(gone and _has(T.FLAG_ON) and _read("port") and not _read("market"),
		"tutorial_on 与已读旗过存档清洗与 JSON 来回仍在，没看过的仍没看过")
	_Switches.set_on(T.SWITCH, false)
	_check(not T.active() and not T.want("market") and not T.offer(h, "market"), "开关 tutorial_notes 关：一张不出")
	_Switches.reset()
	_Switches.set_on(N.SWITCH, false)
	_check(T.active() and not T.want("market"), "讲解小笺总开关 combat_notes 关：新手小笺也不出")
	_Switches.reset()
	h.queue_free()
	await _frames(2)


# ── 三、港页与牙行 ────────────────────────────────────

func _sec_shore() -> void:
	_opening([T.FLAG_ON])
	var main := await _new_main()
	_check(bool((main.get("port_mode") as CanvasItem).visible) and str(main.get("_shore_mode")) == "port", "进了寻常港页")
	_check(_waiters(main) == ["port"] and _seen(main).is_empty(), "进港页先挂候场，不当帧出（%s / %s）" % [_waiters(main), _seen(main)])
	# 换页题签盖着：等它揭开
	var veil := Node.new()
	veil.add_to_group("nk1_ui_transition")
	main.add_child(veil)
	await _wait(T.SETTLE_S + 0.5)
	_check(_seen(main).is_empty() and not _read("port"), "换页题签还盖着：不出、不记已读")
	veil.queue_free()
	var shown := await _until_current(main, "port", 1.5)
	_check(shown and _read("port"), "题签揭开就出「靠港」、记已读 %s" % N.flag_of("port"))
	var lay = N.layer_of(main)
	var slip: Control = lay.call("slip") if lay != null else null
	var txt: Label = slip.find_child("NoteText", true, false) if slip != null else null
	var ttl: Label = slip.find_child("NoteTitle", true, false) if slip != null else null
	_check(txt != null and ttl != null and ttl.text == "靠港" and txt.text == str(N.entry("port")["text"]), "小笺上是「靠港」的小题与正文")
	main.call("_on_shore_wait")  # 再候一日：岸带重排，不重排同一张
	await _frames(3)
	_check(_seen(main).count("port") == 1, "岸带重排（再候一日）不重排同一张（%s）" % [_seen(main)])
	_check(not _seen(main).has("permit") and not _waiters(main).has("permit"), "蒲家没留意过：不出「货引」")
	await _drop(main)

	# 蒲家记过一笔：「货引」排在「靠港」后面
	_opening([T.FLAG_ON])
	_gs.set("pu_attention", 20)
	main = await _new_main()
	await _wait(T.SETTLE_S + 0.4)
	_check(_seen(main) == ["port", "permit"], "蒲家留意 20：先「靠港」后「货引」（%s）" % [_seen(main)])
	lay = N.layer_of(main)
	if lay != null:
		lay.call("dismiss")
	_check(await _until_current(main, "permit", 2.5) and _read("permit"), "点掉「靠港」，接着出「货引」")
	await _drop(main)

	# 没轮到就离了港页：撤下、不记已读；进牙行出「牙行」
	_opening([T.FLAG_ON])
	main = await _new_main()
	await _frames(2)
	main.call("load_scene", "quanzhou_market")
	await _wait(T.SETTLE_S + 0.5)
	_check(not _read("port") and not _seen(main).has("port") and not _waiters(main).has("port"),
		"没轮到就进了牙行：「靠港」撤下、不记已读（%s）" % [_seen(main)])
	_check(await _until_current(main, "market", 1.0) and _read("market"), "进牙行出「牙行」、记已读")
	main.call("load_scene", "quanzhou")
	await _wait(T.SETTLE_S + 0.5)
	_check(_seen(main).has("port"), "回到港页，「靠港」照出（%s）" % [_seen(main)])
	await _drop(main)

	_opening([T.FLAG_ON])
	main = await _new_main("quanzhou_market")
	await _frames(2)
	main.call("load_scene", "quanzhou")
	await _wait(T.SETTLE_S + 0.5)
	_check(not _read("market") and not _seen(main).has("market"), "没轮到就出了牙行：「牙行」撤下、不记已读（%s）" % [_seen(main)])
	await _drop(main)

	# 头一回进市舶司出「货引」；没轮到就出门的撤下；看过了，蒲家记上一笔后的港页不再出
	_opening([T.FLAG_ON, N.flag_of("port")])
	main = await _new_main("quanzhou_yamen")
	await _frames(2)
	main.call("load_scene", "quanzhou")
	await _wait(T.SETTLE_S + 0.5)
	_check(not _read("permit") and not _seen(main).has("permit"), "没轮到就出了市舶司：「货引」撤下、不记已读（%s）" % [_seen(main)])
	main.call("load_scene", "quanzhou_yamen")
	_check(await _until_current(main, "permit", T.SETTLE_S + 1.0) and _read("permit"), "进市舶司出「货引」、记已读")
	_gs.set("pu_attention", 20)
	main.call("load_scene", "quanzhou")
	await _wait(T.SETTLE_S + 0.3)
	_check(not T.want("permit") and _seen(main).count("permit") <= 1 and not T.offer(main, "permit"),
		"看过了：蒲家记上一笔后的港页不再排「货引」（正出着的那张照出完：%s）" % [_seen(main)])
	await _drop(main)

	# 跑完一程靠港（到过两港）、本机还没有存档：出「航海日志」；只到过一港、或已记过一卷的不出
	for row in [[["quanzhou", "xinghua"], false, true], [["quanzhou"], false, false], [["quanzhou", "xinghua"], true, false]]:
		_opening([T.FLAG_ON, N.flag_of("port")])
		_gs.set("visited_ports", row[0])
		T.save_override = row[1]
		main = await _new_main()
		var shows := await _until_current(main, "logbook", T.SETTLE_S + 1.0)
		var tag := "到过 %d 港、本机%s存档" % [(row[0] as Array).size(), "有" if row[1] else "没有"]
		if row[2]:
			_check(shows and _read("logbook"), "%s：出「航海日志」、记已读" % tag)
		else:
			_check(not shows and not _read("logbook") and not _waiters(main).has("logbook"), "%s：不出「航海日志」（%s）" % [tag, _seen(main)])
		await _drop(main)
	T.save_override = null

	# 终局港页不出
	_opening([T.FLAG_ON])
	_gs.set("ended", "海上宋鬼")
	main = await _new_main()
	await _wait(T.SETTLE_S + 0.3)
	_check(str(main.get("_shore_mode")) == "ended" and _seen(main).is_empty() and _waiters(main).is_empty(),
		"终局港页：不挂候场、不出（页型 %s）" % str(main.get("_shore_mode")))
	_gs.set("ended", "")
	await _drop(main)


# ── 四、海图与遇盗 ────────────────────────────────────

func _sec_chart() -> void:
	_opening([T.FLAG_ON, N.flag_of("port")])
	var main := await _new_main()
	var chart := await _sail_from(main)
	_check(chart != null, "按「看风」换上海图")
	if chart == null:
		await _drop(main)
		return
	_check(await _until_current(chart, "chart", 2.0) and _read("chart"), "开海图出「看风」、记已读")
	chart.call("_debug_force_pirate")
	await _frames(2)
	_check(_current(chart) != "chart" or _closing(chart), "海上遇盗先让路：「看风」收起")
	_check(await _until_current(chart, "pirate", 2.5) and _read("pirate"), "接着出「遇盗」、记已读")
	chart.call("_on_flee_pirates")
	await _wait(0.4)
	_check(_current(chart) != "pirate" or _closing(chart), "选了「扬帆逃走」、面板收起：「遇盗」当场收起")
	await _drop(chart)

	# 没轮到就迎战：撤下、不记已读，海图那一层不留它
	_opening([T.FLAG_ON, N.flag_of("port"), N.flag_of("chart")])
	main = await _new_main()
	chart = await _sail_from(main)
	if chart == null:
		_check(false, "第二回换上海图")
		await _drop(main)
		return
	await _frames(2)
	chart.call("_debug_force_pirate")
	await _frames(2)
	_check(_waiters(chart).has("pirate"), "遇盗：挂上「遇盗」候场")
	chart.call("_on_fight_pirates")
	await _wait(T.SETTLE_S + 0.6)
	_check(not _read("pirate") and not _seen(chart).has("pirate") and not _waiters(chart).has("pirate"),
		"没轮到就「迎战」：「遇盗」撤下、不记已读，海图那一层不留它（%s）" % [_seen(chart)])
	for c in chart.get_children():
		if c.has_signal("battle_finished"):
			c.set("resolved", true)
	await _drop(chart)

	# 没轮到就发了舶：「看风」撤下
	_opening([T.FLAG_ON, N.flag_of("port")])
	main = await _new_main()
	chart = await _sail_from(main)
	if chart == null:
		_check(false, "第三回换上海图")
		await _drop(main)
		return
	# 挑最远的一向（一日约 0.42 秒，等的这一秒多到不了岸、不换回港页）
	var far := ""
	var vy: Node = root.get_node("Voyage")
	for pid in chart.get("_hand"):
		if far == "" or float(vy.call("distance_li", "quanzhou", pid)) > float(vy.call("distance_li", "quanzhou", far)):
			far = str(pid)
	chart.call("_select_heading", far)
	chart.call("_on_sail_pressed")
	await _wait(T.SETTLE_S + 0.5)
	_check(is_instance_valid(chart) and bool(chart.get("sailing")), "发了舶、还在海上（往 %s）" % far)
	if is_instance_valid(chart):
		_check(not _read("chart") and not _seen(chart).has("chart") and not _waiters(chart).has("chart"),
			"没轮到就发了舶：「看风」撤下、不记已读（%s）" % [_seen(chart)])
		chart.set("sailing", false)
	await _drop(chart if is_instance_valid(chart) else current_scene)


# ── 五、不打断老玩家 ──────────────────────────────────

func _sec_veteran() -> void:
	for flags in [[T.FLAG_OFF], []]:
		var tag := "tutorial_off" if not flags.is_empty() else "没定过（旧档）"
		_opening(flags)
		var main := await _new_main()
		await _wait(T.SETTLE_S + 0.3)
		var on_port := _waiters(main) + _seen(main)
		main.call("load_scene", "quanzhou_market")
		await _wait(T.SETTLE_S + 0.3)
		var on_market := _waiters(main) + _seen(main)
		var chart := await _sail_from(main)
		var on_chart: Array = []
		if chart != null:
			await _wait(T.SETTLE_S + 0.3)
			chart.call("_debug_force_pirate")
			await _wait(T.SETTLE_S + 0.3)
			on_chart = _waiters(chart) + _seen(chart)
			chart.call("_on_flee_pirates")
		var any_read := false
		for id in EXPECT_IDS:
			any_read = any_read or _read(id)
		_check(chart != null and on_port.is_empty() and on_market.is_empty() and on_chart.is_empty() and not any_read
			and _has(T.FLAG_ON) == false,
			"%s：港页 %s、牙行 %s、海图与遇盗 %s 都不挂不排，已读旗一枚不写" % [tag, on_port, on_market, on_chart])
		await _drop(chart if chart != null else main)
