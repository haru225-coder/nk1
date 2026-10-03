extends SceneTree
## lane w53-6：港口节拍「重复触发」回归探针（headless、不截图、不开窗）。
## 病：PortBeats 只给「抵港演出」的那一拍记名。新局从卷首一路点下来，净海 / 林阿舶 / 船场 / 备航 / 回泉州 / 兴化信
## 这几幕在序章沿途已演过（start 三项同指 monk，各幕选项一路链到章二信，再回泉州港），拍账上却只有 seed 的 start；
## 头一回抵泉州港，节拍又从 monk 起演，选项链把整段第一章再走一遍、回港再接下一针——最多四遍，每遍钱、名声、货、旗再发一次。
## 没有拍账的老档（beats_seen 键缺）同病：seed 只记 start。
## 修法两处：Main._load_scene_inner 演到节拍幕即记名（拍账记「这幕演过没有」）；Main._on_enter_port 抵泉州按节拍幕的
## 选项旗补账（旧档没记过演幕的，选过其一即是演过）。
## 断言：
##   A 新局从卷首（scenes.json start_scene）一路点下去（每页取第一项 / 末一项各走一遍）：
##     A1 头一回记港那一步停的就是泉州港页（不被节拍截去重演）；A2 沿途没有一幕演两遍；
##     A3 沿途演过的节拍幕全记了名；A4 再抵泉州仍停港页、拍账不动。
##   B 老档（A 走完的档去掉 beats_seen / loaded_with_beats 两键，同读旧版存档）：抵泉州停港页、拍账按选项旗补齐。
##   C 对照：空档直跳泉州（序章一幕没演、一枚选项旗也没有）照旧演 monk——节拍本身没被关掉。
##   D 演幕即记名：节拍幕不经抵港、直接演到（上一幕的选项点进来）当下记名；非节拍幕不记；开关关掉不记（老行为）。
## 回退即红：删 _load_scene_inner 演幕记名那一行 → D1 红；删 _on_enter_port 老档补账 → B1/B2 红；两处都删（原病）→ A、B、D 全红。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_beat_replay_probe.gd
## 输出末行 QA_W53_6_BEATS cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
## 卷首到头一个港页的页数上限（现走 44 / 45 页，含卷首）：超了即判「没走到港」
const MAX_STEPS := 140

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var eco: Node
var crew: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
## 本趟头一回记港时停的页（_walk_to_port 写）
var _first_arrival := ""


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run")


func _run() -> void:
	print("QA_W53_6_BEATS_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	eco = root.get_node_or_null("Economy")
	crew = root.get_node_or_null("Crew")
	var boot := {
		"gs": gs.to_dict().duplicate(true), "cal": cal.to_dict().duplicate(true),
		"fleet": fleet.to_dict().duplicate(true), "eco": eco.to_dict().duplicate(true),
		"crew": crew.to_dict().duplicate(true),
	}
	var fails_boot: Array = []
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", fails_boot, "W53-6 Beats Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(fails_boot))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, fails_boot, "W53-6 Beats Main"):
		_check(false, str(fails_boot))
		_finish()
		return
	var bm = load("res://scripts/core/PortBeats.gd")
	_check(bool(bm.call("enabled")) and not (gm.port_beats_data.get("beats", []) as Array).is_empty(),
		"节拍开关默认开、port_beats.json 已读进（%d 拍）" % (gm.port_beats_data.get("beats", []) as Array).size())
	var entries: Array = []
	for b in gm.port_beats_data.get("beats", []):
		entries.append(str((b as Dictionary).get("entry", "")))

	var start_id := str(gm.scenes_data.get("start_scene", "cg_title"))
	var finished_state := {}
	for pick in ["first", "last"]:
		_restore(boot)
		_main._beats = null
		_main.load_scene(start_id)
		await _settle(6)
		var walk: Array = await _walk_to_port(pick)
		var where := "（%s：%s）" % [pick, " → ".join(walk.slice(maxi(0, walk.size() - 6)))]
		_check(_first_arrival == "quanzhou",
			"A1 新局卷首一路点下来，头一回记港那一步就停在泉州港页、不被节拍截去重演（停在 %s）%s" % [
				_first_arrival, where])
		var dup: Array = []
		var seen_once := {}
		for sid in walk:
			if seen_once.has(sid) and not (sid in dup):
				dup.append(sid)
			seen_once[sid] = true
		_check(dup.is_empty(), "A2 沿途没有一幕演两遍（重演 %s，共走 %d 页）" % [dup, walk.size()])
		var unmarked: Array = []
		for sid in seen_once.keys():
			if str(sid) in entries and not (str(sid) in gs.beats_seen):
				unmarked.append(sid)
		_check(unmarked.is_empty(), "A3 沿途演过的节拍幕全记了名（漏记 %s；账 %s）" % [unmarked, gs.beats_seen])
		var before: Array = (gs.beats_seen as Array).duplicate()
		_close_dialogs()
		_main.load_scene("quanzhou")
		await _settle(6)
		_check(str(_main.current_scene_id) == "quanzhou" and _main.port_mode.visible and gs.beats_seen == before,
			"A4 再抵泉州仍停港页、拍账不动（%s；账 %s）" % [_main.current_scene_id, gs.beats_seen])
		if pick == "first":
			finished_state = {
				"gs": gs.to_dict().duplicate(true), "cal": cal.to_dict().duplicate(true),
				"fleet": fleet.to_dict().duplicate(true), "eco": eco.to_dict().duplicate(true),
				"crew": crew.to_dict().duplicate(true),
			}

	# ── B 老档：同一份走完序章的档，去掉拍账两键（旧版存档没有这两键）──
	if not finished_state.is_empty():
		_restore(finished_state)
		var legacy: Dictionary = gs.to_dict().duplicate(true)
		legacy.erase("beats_seen")
		legacy.erase("loaded_with_beats")
		gs.from_dict(legacy)
		_main._beats = null
		_check(gs.beats_seen.is_empty() and not gs.loaded_with_beats, "B0 老档读回：拍账空、seed 记号未下")
		gs.last_port = "quanzhou"
		_close_dialogs()
		_main.load_scene("quanzhou")
		await _settle(6)
		_check(str(_main.current_scene_id) == "quanzhou" and _main.port_mode.visible,
			"B1 老档抵泉州停港页、不从净海重演（停在 %s）" % _main.current_scene_id)
		var missing: Array = []
		for e in ["monk", "merchant", "dock", "prepare", "return_quanzhou", "chapter2_letter"]:
			if not (e in gs.beats_seen):
				missing.append(e)
		_check(missing.is_empty(), "B2 老档拍账按选项旗补齐泉州链（缺 %s；账 %s）" % [missing, gs.beats_seen])

	# ── C 对照：空档直跳泉州（没演过序章、没有选项旗）——节拍照演第一针 ──
	_restore(boot)
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main._beats = null
	_close_dialogs()
	_main.load_scene("quanzhou")
	await _settle(6)
	_check(str(_main.current_scene_id) == "monk" and gs.beats_seen == ["start", "monk"],
		"C 对照：空档直跳泉州照演第一针 monk（停在 %s；账 %s）" % [_main.current_scene_id, gs.beats_seen])

	# ── D 演幕即记名：不经抵港、直接演到节拍幕（上一幕的选项点进来的那条路）当下就记名 ──
	gs.from_dict({})
	_main._beats = null
	_main.load_scene("merchant")
	await _settle(4)
	_check(str(_main.current_scene_id) == "merchant" and gs.beats_seen == ["merchant"],
		"D1 节拍幕 merchant 不经抵港演到即记名（停在 %s；账 %s）" % [_main.current_scene_id, gs.beats_seen])
	_main.load_scene("sail")
	await _settle(4)
	_check(str(_main.current_scene_id) == "sail" and not ("sail" in gs.beats_seen),
		"D2 非节拍幕 sail 演到不记名（停在 %s；账 %s）" % [_main.current_scene_id, gs.beats_seen])
	ProjectSettings.set_setting(str(bm.SETTING), false)
	gm.load_data()
	_main._beats = null
	gs.from_dict({})
	_main.load_scene("monk")
	await _settle(4)
	_check(str(_main.current_scene_id) == "monk" and gs.beats_seen.is_empty(),
		"D3 开关关掉：monk 照演、拍账不动（老行为；停在 %s；账 %s）" % [_main.current_scene_id, gs.beats_seen])
	ProjectSettings.set_setting(str(bm.SETTING), true)
	gm.load_data()
	_main._beats = null

	_finish()


## 每页取第一项 / 末一项往下点，直到港页开出；返回沿途页序（含起始页）。
## 头一回记港（visited_ports 由空变非空 = Main._on_enter_port 头一回结算）那一步停在哪页，记进 _first_arrival。
func _walk_to_port(pick: String) -> Array:
	var walk: Array = [str(_main.current_scene_id)]
	_first_arrival = ""
	for _i in MAX_STEPS:
		if _first_arrival == "" and not (gs.visited_ports as Array).is_empty():
			_first_arrival = "%s%s" % [_main.current_scene_id, "" if _main.port_mode.visible else "（不是港页）"]
		if _main.port_mode.visible:
			return walk
		if _main.title_mode.visible and _main.start_button.visible and not _main.start_button.disabled:
			_main.start_button.pressed.emit()
		else:
			var btns: Array = []
			for child in _main.choices_container.get_children():
				if child is Button and (child as Button).is_visible_in_tree() and not (child as Button).disabled:
					btns.append(child)
			if btns.is_empty():
				_check(false, "卷首往下点到 %s 没有可点的项（%s）" % [_main.current_scene_id, pick])
				return walk
			var use: Button = btns[0] if pick == "first" else btns[btns.size() - 1]
			use.pressed.emit()
		await _settle(4)
		walk.append(str(_main.current_scene_id))
	_check(false, "卷首点了 %d 页还没到港页（%s，停在 %s）" % [MAX_STEPS, pick, _main.current_scene_id])
	return walk


func _restore(snap: Dictionary) -> void:
	gs.from_dict((snap["gs"] as Dictionary).duplicate(true))
	cal.from_dict((snap["cal"] as Dictionary).duplicate(true))
	fleet.from_dict((snap["fleet"] as Dictionary).duplicate(true))
	eco.from_dict((snap["eco"] as Dictionary).duplicate(true))
	crew.from_dict((snap["crew"] as Dictionary).duplicate(true))


## 章节册页（头一回到港若晋章会弹）叠在港页上：真机上玩家按掉，这里直接收掉
func _close_dialogs() -> void:
	var host = _main.get("_chapter_host")
	if host is Node and is_instance_valid(host):
		(host as Node).queue_free()
		_main.set("_chapter_host", null)


func _settle(n: int) -> void:
	await Clock.settle(self, n)


func _check(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _finish() -> void:
	OS.remove_logger(_tally)
	var errs: Array = _tally.lines
	_check(errs.is_empty(), "运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
		"" if errs.is_empty() else "，首条：" + str(errs[0])])
	print("QA_W53_6_BEATS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
