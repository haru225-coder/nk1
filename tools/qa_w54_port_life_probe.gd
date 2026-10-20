extends SceneTree
## lane w54-port：岸上见闻（开关 port_life）专项探针（headless、不截图、不开窗）。
## 寻常港页行首注「今日只开三处。」那方墨底小笺里再添一行码头光景的纪实短句（scripts/core/PortLife.gd 一张表：
## 港所在一带 × 季风；港上对峙 / 降元 / 被围 / 封港时写战况那一句）。Main._build_shore 排完寻常岸带那一行调 Main._shore_life。
## 断言（真起 Main，读岸带 ShoreBand 里的 ShoreLife 与行首注）：
##   一、开关开、泉州：十一月（东北风）「北风起了，往南洋去的船在候潮装货。」、六月（西南风）「南风季，南边来的蕃舶陆续进港。」、
##       四月（风信未定）「风信未定，坞里多是修船补帆的。」；小笺里两行，行首注在上、仍是「今日只开三处。」，三扇门不少；
##   二、十四港各在三季都有一句、岸上那一行 = PortLife.line(港, 季, 战况)，句尾全角句号、不过 24 字；
##   三、战况压过季风：泉州 1276-06 对峙、明州 1276-03 降元、福州 1276-10 被围、博多唐房 1274-11 封港各写战况那一句；
##   四、再候一日三回：岸带里 ShoreLife 回回恰一枚、不叠；四月廿九候过月头进五月，那一句跟着换成西南风那句；
##   五、守城页（兴化 1276-11 士人）、终局港页：没有这一行；
##   六、开关关：岸带里没有 ShoreLife，小笺里只一枚行首注（与改前同）。
## 回退即红：_build_shore 那一行去掉 _shore_life() → 一至四红；_shore_life 不看开关 → 六红；
## 钩子挪到 _refresh_shore 末尾（守城 / 终局岸带也走它）又不看页型 → 五红。
## 用法：godot --headless --path . -s res://tools/qa_w54_port_life_probe.gd（经门锁跑）
## 输出末行 QA_W54_PORT_LIFE cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PortLifeScript := preload("res://scripts/core/PortLife.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

const PORTS := ["quanzhou", "xinghua", "xinghua_harbor", "fuzhou", "zhangzhou", "wenzhou", "penghu", "ryukyu",
	"mingzhou", "jeju", "hakata", "guangzhou", "kagoshima", "champa"]

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _finish() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


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
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_check(false, "Main.gd 未载入")
		_finish()
		return
	Switches.reset()

	print("── 一、泉州三季")
	for row in [[11, "北风起了，往南洋去的船在候潮装货。"], [6, "南风季，南边来的蕃舶陆续进港。"], [4, "风信未定，坞里多是修船补帆的。"]]:
		_stage("quanzhou", 1262, int(row[0]), 10)
		await _open("quanzhou")
		var lines := _note_lines()
		_check(_life() == str(row[1]) and lines.size() == 2 and lines[0] == "今日只开三处。" and lines[1] == str(row[1]) and _door_count() == 3,
			"泉州 1262-%02d：见闻「%s」（应「%s」），小笺两行 [%s]，门 %d 扇" % [int(row[0]), _life(), str(row[1]), " / ".join(lines), _door_count()])

	print("── 二、十四港三季")
	var bad := PackedStringArray()
	for pid in PORTS:
		for row in [[1, "ne"], [7, "sw"], [3, "calm"]]:
			# 1262 年各港都太平（战况表最早 1273），只看季风
			_stage(pid, 1262, int(row[0]), 10)
			await _open(pid)
			var want := str(PortLifeScript.line(pid, str(row[1]), str(eco.war_status(pid))))
			var got := _life()
			if want == "" or got != want or not want.ends_with("。") or want.length() > 24:
				bad.append("%s %s「%s」（表「%s」）" % [pid, row[1], got, want])
	_check(bad.is_empty(), "十四港 × 三季各有一句、岸上那一行与表一字不差%s" % ("" if bad.is_empty() else "（不合：%s）" % "；".join(bad)))

	print("── 三、战况压过季风")
	for row in [["quanzhou", 1276, 6, "码头上兵船多了，商船泊得靠外。"], ["mingzhou", 1276, 3, "港里换了旗号。"],
			["fuzhou", 1276, 10, "城门闭着，码头上冷清。"], ["hakata", 1274, 11, "港口封着，泊着的船都不许出。"]]:
		_stage(str(row[0]), int(row[1]), int(row[2]), 10)
		await _open(str(row[0]))
		_check(_life() == str(row[3]), "%s %d-%02d（%s）：见闻「%s」（应「%s」）" % [
			gm.get_port_name(str(row[0])), int(row[1]), int(row[2]), eco.war_status(str(row[0])), _life(), str(row[3])])

	print("── 四、再候一日：不叠、跨季跟着换")
	_stage("quanzhou", 1262, 4, 29)
	await _open("quanzhou")
	var seen := PackedStringArray()
	var counts := PackedInt32Array()
	seen.append(_life())
	counts.append(_life_count())
	for k in 3:
		var wait := _find_button(_main.get("port_mode"), "再候一日")
		if wait == null:
			break
		wait.pressed.emit()
		await _settle(3)
		seen.append(_life())
		counts.append(_life_count())
	var once := true
	for c in counts:
		if c != 1:
			once = false
	_check(counts.size() == 4 and once and seen[0] == "风信未定，坞里多是修船补帆的。" and seen[3] == "南风季，南边来的蕃舶陆续进港。",
		"四月廿九起再候一日三回：每回 ShoreLife %s 枚，见闻 %s（应先风信未定、进五月换西南风那句）" % [
			", ".join(Array(counts).map(func(x): return str(x))), " → ".join(seen)])

	print("── 五、守城页、终局港页没有这一行")
	_stage("xinghua", 1276, 11, 2)
	gs.identity = "scholar"
	gs.player_name = "陈文龙"
	gs.set_flag("renamed_wenlong")
	await _open("xinghua")
	_check(str(_main.get("_shore_mode")) == "siege" and _life_count() == 0,
		"兴化 1276-11 士人守城页（岸带页型 %s）：ShoreLife %d 枚（应 0）" % [_main.get("_shore_mode"), _life_count()])
	_stage("quanzhou", 1280, 3, 2)
	gs.finish("纲首", "一纸收场。")
	await _open("quanzhou")
	_check(str(_main.get("_shore_mode")) == "ended" and _life_count() == 0,
		"终局后泉州港页（岸带页型 %s）：ShoreLife %d 枚（应 0）" % [_main.get("_shore_mode"), _life_count()])

	print("── 六、开关关：逐字回旧")
	Switches.set_on("port_life", false)
	_stage("quanzhou", 1262, 11, 10)
	await _open("quanzhou")
	var note: Node = _main.call("_shore_band").get_node_or_null("ShoreNote")
	var only_hint: bool = note != null and note.get_child_count() == 1 and note.get_child(0) is Label and (note.get_child(0) as Label).text == "今日只开三处。"
	_check(_life_count() == 0 and only_hint and _door_count() == 3,
		"开关关、泉州 1262-11：ShoreLife %d 枚（应 0），小笺里只一枚行首注 %s，门 %d 扇" % [_life_count(), "是" if only_hint else "否", _door_count()])
	Switches.reset()
	_finish()


## pid 港 y 年 m 月 d 日，第四章（各港都解锁）、海商、一艘客舟，水粮足；节拍全记过、不在港页演戏
func _stage(pid: String, y: int, m: int, d: int) -> void:
	gs.from_dict({})
	gs.chapter = 4
	gs.money = 5000
	gs.identity = "merchant"
	gs.visited_ports = ["xinghua", "quanzhou", pid]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": y, "month": m, "day": d})
	crew.from_dict({})
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.shore_salt = 0
	gs.last_port = pid


func _open(pid: String) -> void:
	_main.load_scene(pid)
	await _settle(3)


func _band() -> Node:
	return _main.call("_shore_band")


func _life() -> String:
	var lbl := _find_named(_band(), "ShoreLife")
	return (lbl as Label).text if lbl != null else ""


func _life_count() -> int:
	var n := [0]
	_count_named(_band(), "ShoreLife", n)
	return int(n[0])


## 墨底小笺里的几行字（上到下）
func _note_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var note: Node = _band().get_node_or_null("ShoreNote")
	if note != null:
		_label_texts(note, out)
	return out


func _door_count() -> int:
	var doors: Node = _band().get_node_or_null("ShoreDoors")
	if doors == null:
		return 0
	var n := 0
	for c in doors.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


func _label_texts(n: Node, out: PackedStringArray) -> void:
	if n.is_queued_for_deletion():
		return
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_label_texts(c, out)


func _find_named(n: Node, nm: String) -> Node:
	if n == null or n.is_queued_for_deletion():
		return null
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var hit := _find_named(c, nm)
		if hit != null:
			return hit
	return null


func _count_named(n: Node, nm: String, acc: Array) -> void:
	if n == null or n.is_queued_for_deletion():
		return
	if String(n.name) == nm:
		acc[0] = int(acc[0]) + 1
	for c in n.get_children():
		_count_named(c, nm, acc)


func _find_button(n: Node, text: String) -> Button:
	if n == null or n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


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
	print("QA_W54_PORT_LIFE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
