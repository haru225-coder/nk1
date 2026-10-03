extends SceneTree
## lane w53-6：岸带行首注与门数对得上——回归探针（headless、不截图、不开窗）。
## 病：港页行首注一律写「今日只开三处。」，可终局特殊卡（崖山 / 临安・辞呈批语 / 市舶司・新册 / 涵江海口 / 入城）
## 不进「今日只开三处」的发牌，来了就追加在三扇门后面——1279 年二月的广州、1285 年以后的各港、辞呈未决的士人
## 到哪一港，岸上都是四扇一样的纸门，旁边却写「今日只开三处。」。
## 断言（门数读岸带 ShoreDoors 的门卡，行首注读岸带里那一行）：
##   C0 对照：1262 年三月泉州，三扇门，行首注照旧「今日只开三处。」；
##   S1 1279 年二月广州（海商）：岸上有崖山卡，四扇门，行首注「今日只开三处，另有一事。」；
##   S2 1285 年三月泉州（海商）：「市舶司・新册」，同上；
##   S3 1276 年二月福州（士人、辞呈已批未决）：「临安・辞呈批语」，同上；
##   S4 摆场两张特殊卡同在（辞呈未决 + 1285 年以后非士人）：五扇门，行首注「另有两事」；
##   每案另判：门数 = 三 + 特殊卡张数（特殊卡追加、不挤掉寻常三处）。
## 回退即红：Main._refresh_shore 行首注改回只写「今日只开三处。」→ S1–S4 红。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_shore_hint_probe.gd
## 输出末行 QA_W53_6_SHORE_HINT cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var cases := 0
var fails := 0
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
		_finish()


func _run() -> void:
	print("QA_W53_6_SHORE_HINT_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	var boot_fails: Array = []
	ShotGate.frame_pressure(self)
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", boot_fails, "W53-6 ShoreHint Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(boot_fails))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, boot_fails, "W53-6 ShoreHint Main"):
		_check(false, str(boot_fails))
		_finish()
		return

	await _case("C0 对照 1262-03 泉州", "quanzhou", 1262, 3, "undecided", [], [], "今日只开三处。")
	await _case("S1 1279-02 广州（海商）", "guangzhou", 1279, 2, "merchant", [], ["special_yashan"], "今日只开三处，另有一事。")
	await _case("S2 1285-03 泉州（海商）", "quanzhou", 1285, 3, "merchant", [], ["special_gangshou_end"], "今日只开三处，另有一事。")
	await _case("S3 1276-02 福州（士人、辞呈未决）", "fuzhou", 1276, 2, "scholar", ["renamed_wenlong", "vice_councillor"],
		["special_resign_1275"], "今日只开三处，另有一事。")
	await _case("S4 摆场 1285-03 泉州（辞呈未决 + 非士人）", "quanzhou", 1285, 3, "merchant", ["vice_councillor"],
		["special_resign_1275", "special_gangshou_end"], "今日只开三处，另有两事。")
	_finish()


## 摆一档局面进港，读岸带：特殊卡在不在、门数、行首注
func _case(tag: String, port_id: String, year: int, month: int, identity: String, flags: Array, want_specials: Array, want_hint: String) -> void:
	gs.from_dict({})
	gs.chapter = 4
	gs.money = 9000
	gs.identity = identity
	for f in flags:
		gs.set_flag(str(f))
	gs.visited_ports = ["xinghua", "quanzhou", port_id]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": year, "month": month, "day": 3})
	gs.last_port = port_id
	_main.load_scene(port_id)
	await _settle(6)
	var hand: Array = Array(_main.shore_hand)
	var specials: Array = hand.filter(func(f) -> bool: return str(f).begins_with("special_") or str(f).begins_with("siege_"))
	var doors := _door_count()
	var hint := _hint_text()
	var on_port: bool = str(_main.current_scene_id) == port_id and bool(_main.port_mode.visible) and str(_main._shore_kind_now) == "port"
	_check(on_port and specials == want_specials,
		"%s：寻常港页，特殊卡 %s（应 %s）" % [tag, specials, want_specials])
	_check(doors == 3 + specials.size(),
		"%s：岸上 %d 扇门 = 三处 + 特殊卡 %d 张" % [tag, doors, specials.size()])
	_check(hint == want_hint, "%s：行首注「%s」（应「%s」）" % [tag, hint, want_hint])


func _door_count() -> int:
	var band: Node = _main._shore_band()
	var doors: Node = band.get_node_or_null("ShoreDoors") if band != null else null
	if doors == null:
		return -1
	var n := 0
	for c in doors.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


func _hint_text() -> String:
	var band: Node = _main._shore_band()
	return _find_label(band, "今日只开") if band != null else ""


func _find_label(n: Node, needle: String) -> String:
	if n.is_queued_for_deletion():
		return ""
	if n is Label and (n as Label).text.begins_with(needle):
		return (n as Label).text
	for c in n.get_children():
		var t := _find_label(c, needle)
		if t != "":
			return t
	return ""


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
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("QA_W53_6_SHORE_HINT cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
