extends SceneTree
## lane w53-6：港内设施页「离开」回归探针（headless、不截图、不开窗）。
## 病：兴化住宅门进的是玉湖陈宅（ResidencePage.setup_residence_chen）。lane w20-a9 第十三刀二把它从 Main 搬进
## ResidencePage 时，搬前最后一行 _add_leave_button(port_id) 没跟过来——页上没有「离开」，回不了港：
## 身份未定时只剩「替族里跑一趟事」（回车即按它，费 6 日・30 钱），身份定了又不到 1270 年连一枚钮都没有，只能读档。
## 断言：
##   E1 十四港 × 九种设施页（{港}_market / _yamen / _shipyard / _tavern / _inn / _guild / _exam / _residence / _temple）
##      各有一枚看得见、按得动的「离开」；
##   E2 玉湖陈宅四种账况（身份未定跑腿 / 身份已定无钮 / 1271 陈瓒入股 / 已立股）都有「离开」，按下回兴化港页。
## 回退即红：删 ResidencePage.setup_residence_chen 末尾的 main._add_leave_button(port_id) → E1 兴化住宅一格 + E2 四格红。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_port_exits_probe.gd
## 输出末行 QA_W53_6_EXITS cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SUFFIXES := ["_market", "_yamen", "_shipyard", "_tavern", "_inn", "_guild", "_exam", "_residence", "_temple"]

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run")


func _run() -> void:
	print("QA_W53_6_EXITS_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	var boot_fails: Array = []
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", boot_fails, "W53-6 Exits Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(boot_fails))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, boot_fails, "W53-6 Exits Main"):
		_check(false, str(boot_fails))
		_finish()
		return

	# ── E1 十四港 × 九种设施页：各有「离开」──
	var ports: Array = gm.ports_data.get("ports", [])
	var missing: Array = []
	var total := 0
	for p in ports:
		var pid := str((p as Dictionary).get("id", ""))
		for suf in SUFFIXES:
			_reset(1262, 3)
			gs.last_port = pid
			var sid: String = pid + str(suf)
			_main.load_scene(sid)
			await _settle(2)
			total += 1
			if _leave_button() == null:
				missing.append("%s（%s）" % [sid, _main.scene_title.text])
	_check(total == ports.size() * SUFFIXES.size() and missing.is_empty(),
		"E1 %d 港 × %d 种设施页（%d 页）各有一枚「离开」（缺 %d 页：%s）" % [
			ports.size(), SUFFIXES.size(), total, missing.size(), missing])

	# ── E2 玉湖陈宅四种账况：有「离开」、按下回兴化港页 ──
	var cases_chen := [
		["身份未定・1262（只有跑腿一钮）", 1262, 3, "undecided", 0, false],
		["身份已定・1269（陈宅一枚钮都没有）", 1269, 3, "merchant", 0, false],
		["1271・名声够（陈瓒入股）", 1271, 3, "undecided", 20, false],
		["已立股・1272", 1272, 3, "merchant", 20, true],
	]
	for c in cases_chen:
		_reset(int(c[1]), int(c[2]))
		gs.identity = str(c[3])
		gs.fame = int(c[4])
		if bool(c[5]):
			gs.set_flag("chen_zan_stake")
		gs.last_port = "xinghua"
		_main.load_scene("xinghua_residence")
		await _settle(2)
		var title := str(_main.scene_title.text)
		var leave := _leave_button()
		_check(title.contains("玉湖陈宅") and leave != null,
			"E2 %s：「%s」页有「离开」（钮：%s）" % [c[0], title, _button_texts()])
		if leave == null:
			continue
		leave.pressed.emit()
		await _settle(4)
		_check(str(_main.current_scene_id) == "xinghua" and _main.port_mode.visible,
			"E2 %s：按「离开」回兴化港页（停在 %s，港页%s）" % [c[0], _main.current_scene_id, "开" if _main.port_mode.visible else "未开"])

	_finish()


## 设施页的账况：去过兴化、泉州（兴化住宅门进玉湖陈宅、不进序章调查页），节拍链记齐（抵泉州不演戏）
func _reset(year: int, month: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": year, "month": month, "day": 1})
	gs.money = 5000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for e in ["start", "monk", "merchant", "dock", "prepare", "return_quanzhou", "chapter2_letter"]:
		gs.beat_mark(e)


## 页上看得见、按得动的「离开」（页脚或正文按钮列）
func _leave_button() -> Button:
	for b in _all_buttons(_main):
		if (b as Button).text == "离开" and (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b
	return null


func _button_texts() -> Array:
	var out: Array = []
	for b in _all_buttons(_main):
		if (b as Button).is_visible_in_tree():
			out.append((b as Button).text)
	return out


func _all_buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


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
	print("QA_W53_6_EXITS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
