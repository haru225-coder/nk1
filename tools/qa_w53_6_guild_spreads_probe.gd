extends SceneTree
## lane w53-6：行会「出港行情」/ 酒馆·见面「打听」不荐开不了秤的港——回归探针（headless、不截图、不开窗）。
## 病：Main._collect_spreads 只看「已解锁港」，不看那港牙行开没开。文永之役后博多唐房、萨摩封港（1274-10 至 1275-04），
## 泉州行会抄本头一条就是「运往 博多唐房」、第三条「运往 萨摩」，酒馆打听也照这一条吐给玩家；可到了那边
## 「牙行上了门闸。封港，无人开秤」，货卖不出去。围城的福州（1276-10）、广州 / 兴化（1276-11）同病；
## 本港自己上了门闸时，抄本还照「买 X」列，可柜上根本买不到。
## 断言：
##   G1 1274-11 泉州可抄价差非空，且没有一条运往牙行闭门的港；
##   G2 同月泉州行会页上的「运往 …」各条都不是闭门港；
##   G3 同月酒馆打听吐的是【行情】、且不提闭门港；
##   G4 1276-10 福州围城：福州本港不抄（_collect_spreads 空），行会页「出港行情」写门闸那一句、不列「运往」；泉州抄本不荐福州；
##   G5 对照 1262-03 太平：泉州抄本照荐博多唐房、福州行会照列「运往」——没把开着的港一并滤掉。
## 回退即红：_collect_spreads 去掉两处 Economy.is_market_open 判 → G1/G2/G3/G4 红；行会空抄本那句改回只写
## 「过几日行情回一回再来。」→ G4 门闸那格红。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_guild_spreads_probe.gd
## 输出末行 QA_W53_6_SPREADS cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run")


func _run() -> void:
	print("QA_W53_6_SPREADS_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	eco = root.get_node_or_null("Economy")
	var boot_fails: Array = []
	ShotGate.frame_pressure(self)
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", boot_fails, "W53-6 Spreads Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(boot_fails))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, boot_fails, "W53-6 Spreads Main"):
		_check(false, str(boot_fails))
		_finish()
		return

	# ── 1274-11：博多唐房、萨摩封港 ──
	_reset(1274, 11)
	var shut := _shut_ports()
	_check("hakata" in shut and "kagoshima" in shut, "前提：1274-11 博多唐房、萨摩牙行闭门（闭门港 %s）" % [shut])
	var rows: Array = _main._collect_spreads("quanzhou", 0)
	var to_shut := _rows_to(rows, shut)
	_check(not rows.is_empty() and to_shut.is_empty(),
		"G1 1274-11 泉州可抄价差 %d 条，没有一条运往闭门港（运往闭门港 %d 条：%s）" % [rows.size(), to_shut.size(), to_shut.slice(0, 4)])
	_main.load_scene("quanzhou_guild")
	await _settle(4)
	var hints := _spread_hints(_main)
	var bad_hints: Array = []
	for h in hints:
		for pid in shut:
			if str(h).contains(str(gm.get_port_name(pid))):
				bad_hints.append(h)
	_check(str(_main.current_scene_id) == "quanzhou_guild" and not hints.is_empty() and bad_hints.is_empty(),
		"G2 1274-11 泉州行会抄本 %d 条都不是闭门港（%s）" % [hints.size(), hints if bad_hints.is_empty() else bad_hints])
	var intel := str(_main._gather_price_intel("quanzhou"))
	var intel_bad := false
	for pid in shut:
		if intel.contains(str(gm.get_port_name(pid))):
			intel_bad = true
	_check(intel.begins_with("【行情】") and not intel_bad, "G3 1274-11 泉州打听不荐闭门港（%s）" % intel)

	# ── 1276-10：福州围城 ──
	_reset(1276, 10)
	shut = _shut_ports()
	_check("fuzhou" in shut, "前提：1276-10 福州牙行闭门（闭门港 %s）" % [shut])
	var fz: Array = _main._collect_spreads("fuzhou", 0)
	_check(fz.is_empty(), "G4 福州围城：本港柜上买不到，抄本不抄（%d 条）" % fz.size())
	_main.load_scene("fuzhou_guild")
	await _settle(4)
	var fz_hints := _spread_hints(_main)
	var gate_note := _find_label(_main, "牙行上了门闸")
	_check(fz_hints.is_empty() and gate_note != "",
		"G4 福州围城：行会「出港行情」写门闸那一句、不列「运往」（门闸句「%s」，运往 %s）" % [gate_note, fz_hints])
	var qz_fz := _rows_to(_main._collect_spreads("quanzhou", 0), ["fuzhou"])
	_check(qz_fz.is_empty(), "G4 1276-10 泉州抄本不荐围城的福州（%s）" % [qz_fz.slice(0, 4)])

	# ── 1262-03 对照：太平时节博多、福州照常 ──
	_reset(1262, 3)
	_check(_shut_ports().is_empty(), "前提：1262-03 无闭门港")
	var calm := _rows_to(_main._collect_spreads("quanzhou", 0), ["hakata"])
	_check(not calm.is_empty(), "G5 对照 1262-03 泉州抄本照荐博多唐房（%d 条）" % calm.size())
	_main.load_scene("fuzhou_guild")
	await _settle(4)
	_check(not _spread_hints(_main).is_empty() and _find_label(_main, "牙行上了门闸") == "",
		"G5 对照 1262-03 福州行会照列「运往」、不写门闸（%s）" % [_spread_hints(_main)])

	_finish()


## 章四全港解锁、商誉够抄五条
func _reset(year: int, month: int) -> void:
	gs.from_dict({})
	gs.chapter = 4
	cal.from_dict({"year": year, "month": month, "day": 1})
	gs.money = 5000
	gs.merchant_credit = 30
	gs.visited_ports = ["xinghua", "quanzhou"]


## 当月牙行闭门（围城 / 封港）的港
func _shut_ports() -> Array:
	var out: Array = []
	for p in gm.ports_data.get("ports", []):
		var pid := str((p as Dictionary).get("id", ""))
		if not bool(eco.is_market_open(pid)):
			out.append(pid)
	return out


func _rows_to(rows: Array, ports: Array) -> Array:
	var out: Array = []
	for r in rows:
		if str(r["port"]) in ports:
			out.append("%s %s +%d" % [r["port"], r["good"], int(r["profit"])])
	return out


## 行会页上「运往 X　多 N」的行情条（同 p7_guild_exam_smoke._spread_hints）
func _spread_hints(n: Node) -> Array:
	var out: Array = []
	if n.is_queued_for_deletion():
		return out
	if n is Label:
		var t: String = (n as Label).text
		if t.begins_with("运往 ") and t.contains("　多 "):
			out.append(t)
	for c in n.get_children():
		out.append_array(_spread_hints(c))
	return out


func _find_label(n: Node, needle: String) -> String:
	if n.is_queued_for_deletion():
		return ""
	if n is Label and (n as Label).is_visible_in_tree() and (n as Label).text.contains(needle):
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
	OS.remove_logger(_tally)
	var errs: Array = _tally.lines
	_check(errs.is_empty(), "运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
		"" if errs.is_empty() else "，首条：" + str(errs[0])])
	print("QA_W53_6_SPREADS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
