extends SceneTree
## lane w54-audio：海图与港口补挂的声（SfxCues 表里海图五行）。一段钉一条，回退即红。
##   原先海图上一声不出：启程、风涛（札记「浪头一个高过一个」）、浅滩（「船底忽然擦过一片沙脊」）、靠港（「岸线终于在雾里显出来」）、
##   海上沉没（「船身裂开，海水灌进货舱」）都只有字。
##   一、表：五行都在、标 added、各带 gap_ms；靠港钟在收声组 bell（与墨幕那声同组）。
##   二、真起 SeaChart（headless）逐处走真路：选港点「发舶」（_on_sail_pressed）记 chart_depart；_show_event 风涛记两下浪、
##       浅滩记一声，商船 / 海寇 / 闹舱不响；_arrive 记靠港钟；_sink 记两层（船身裂开 + 下行磬音）。
##   三、开关 sfx_cues 关：靠港、风涛同一处真路记 off、不响。
##   四、靠港钟与墨幕同组：靠港钟还在响时起墨幕（下船入港那一幕），靠港钟收掉、只剩墨幕那声。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_chart_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_CHART PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_CHART"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

const CHART := [&"chart_depart", &"chart_storm", &"chart_shoal", &"chart_arrive", &"chart_sink"]

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _fleet: Node = null
var _gs: Node = null
var _voy: Node = null
var _clock := 6_000_000


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_fleet = root.get_node("Fleet")
	_gs = root.get_node("GameState")
	_voy = root.get_node("Voyage")
	_Switches.reset()
	print("== 一、表")
	_sec_table()
	print("== 二、真起海图逐处走真路")
	await _sec_chart()
	print("== 三、开关 sfx_cues 关")
	await _sec_off()
	print("== 四、靠港钟与墨幕同组")
	await _sec_bell()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


## Voyage.EventKind（-s 探针在 autoload 挂上之前编，不能直写 Voyage.EventKind：从脚本常量表取）
func _kinds() -> Dictionary:
	var m: Dictionary = (_voy.get_script() as Script).get_script_constant_map()
	return m.get("EventKind", {})


func _fresh() -> void:
	_clock += 10_000
	_AUDIO.clock_ms = _clock
	_AUDIO.journal.clear()


static func _whys(hook: StringName) -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if StringName(r.get("hook", &"")) == hook:
			out.append(str(r.get("why", "?")))
	return out


static func _sounded(hook: StringName) -> int:
	return _whys(hook).count("")


func _settle() -> void:
	await create_timer(0.5).timeout


func _sec_table() -> void:
	var bad: PackedStringArray = []
	for hook in CHART:
		var row: Dictionary = _SFX.HOOKS.get(hook, {})
		if row.is_empty() or not bool(row.get("added", false)) or int(row.get("gap_ms", 0)) <= 0:
			bad.append(String(hook))
	_check(bad.is_empty(), "海图五行都在、标 added、各带 gap_ms（不对的 %s）" % ",".join(bad))
	_check(StringName(_SFX.HOOKS[&"chart_arrive"].get("group", &"")) == &"bell"
		and StringName(_SFX.HOOKS[&"transition"].get("group", &"")) == &"bell", "靠港钟与墨幕那声同在收声组 bell")
	# 表里的名字要与 Voyage.EventKind 对得上（改了枚举名这里先红）
	var kinds: Dictionary = _kinds()
	_check(kinds.has("STORM") and kinds.has("SHOAL"), "Voyage.EventKind 里有 STORM / SHOAL（%s）" % str(kinds.keys()))


func _stage_fleet() -> void:
	var d: Dictionary = _fleet.call("ship_def", "fu_ship_medium")
	var dur := float(d.get("durability", 300))
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "旗舰", "crew": 40, "sail_level": 1, "armor_level": 1,
		"cargo": {"tea": {"qty": 4, "avg_cost": 20.0}}, "durability": dur, "max_durability": dur}])
	_fleet.set("water", 60)
	_fleet.set("food", 60)
	_fleet.set("morale", 60)
	_fleet.set("at_sea", false)
	_gs.set("last_port", "quanzhou")


func _new_chart() -> Node:
	_stage_fleet()
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	return sc


func _drop(sc: Node) -> void:
	sc.set("sailing", false)
	sc.set("_sail_serial", int(sc.get("_sail_serial")) + 1)
	_fleet.set("at_sea", false)
	sc.queue_free()
	await process_frame
	await process_frame


func _sec_chart() -> void:
	var kinds: Dictionary = _kinds()
	# 发舶
	var sc := await _new_chart()
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "zhangzhou")
	_fresh()
	sc.call("_on_sail_pressed")
	_check(bool(sc.get("sailing")), "海图发舶起得来（泉州 → 漳州）")
	_check(_sounded(&"chart_depart") == 1, "发舶（SeaChart._on_sail_pressed）记 chart_depart（%s）" % str(_whys(&"chart_depart")))
	await _drop(sc)
	# 遇事：风涛两下、浅滩一声，别的事不响
	sc = await _new_chart()
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "zhangzhou")
	sc.set("days_elapsed", 2)
	_fresh()
	sc.call("_show_event", {"kind": int(kinds["STORM"]), "title": "风涛", "text": "风起于西北，浪头一个高过一个。", "severity": 1})
	await _settle()
	_check(_sounded(&"chart_storm") == 2, "风涛（SeaChart._show_event STORM）记两下浪（%s）" % str(_whys(&"chart_storm")))
	_fresh()
	sc.call("_show_event", {"kind": int(kinds["SHOAL"]), "title": "浅滩", "text": "船底忽然擦过一片沙脊。"})
	_check(_sounded(&"chart_shoal") == 1, "浅滩（SeaChart._show_event SHOAL）记 chart_shoal（%s）" % str(_whys(&"chart_shoal")))
	var quiet := []
	for k in ["MERCHANT", "PIRATE", "MUTINY", "DISCOVERY", "REFUGEE"]:
		_fresh()
		sc.call("_show_event", {"kind": int(kinds[k]), "title": k, "text": "探针"})
		if not _AUDIO.journal.is_empty():
			quiet.append("%s→%s" % [k, str(_AUDIO.journal)])
	_check(quiet.is_empty(), "商船 / 海寇 / 闹舱 / 勘见 / 难民船不响（响了的 %s）" % str(quiet))
	# 靠港
	sc.set("sailing", true)
	_fleet.set("at_sea", true)
	_fresh()
	sc.call("_arrive")
	_check(_sounded(&"chart_arrive") == 1 and str(sc.get("event_title").get("text")) == "到　港",
		"靠港（SeaChart._arrive，到港那一面）记靠港钟 chart_arrive（%s）" % str(_whys(&"chart_arrive")))
	await _drop(sc)
	# 海上沉没
	sc = await _new_chart()
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "zhangzhou")
	sc.set("sailing", true)
	_fresh()
	sc.call("_sink", "")
	await _settle()
	_check(_sounded(&"chart_sink") == 2 and str(sc.get("event_title").get("text")) == "沉　没",
		"海上沉没（SeaChart._sink）记两层：船身裂开 + 下行磬音（%s）" % str(_whys(&"chart_sink")))
	await _drop(sc)


func _sec_off() -> void:
	var kinds: Dictionary = _kinds()
	var sc := await _new_chart()
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "zhangzhou")
	sc.set("sailing", true)
	_Switches.set_on(_SFX.SWITCH, false)
	_fresh()
	sc.call("_show_event", {"kind": int(kinds["STORM"]), "title": "风涛", "text": "探针", "severity": 1})
	sc.call("_arrive")
	await _settle()
	_Switches.reset()
	_check(_whys(&"chart_storm") == ["off"] and _whys(&"chart_arrive") == ["off"],
		"开关关：风涛、靠港同一处真路记 off、不响（%s / %s）" % [_whys(&"chart_storm"), _whys(&"chart_arrive")])
	await _drop(sc)


func _sec_bell() -> void:
	var host := Node.new()
	root.add_child(host)
	await process_frame
	_fresh()
	_SFX.play(host, &"chart_arrive")
	_AUDIO.clock_ms = _clock + 400
	_SFX.play(host, &"transition")
	var rows: Array = []
	for r in _AUDIO.journal:
		rows.append([String(r.get("hook", &"")), str(r.get("why", "?"))])
	_check(rows == [["chart_arrive", ""], ["chart_arrive", "cut"], ["transition", ""]],
		"靠港钟响着时起墨幕：靠港钟收掉、只剩墨幕那声（%s）" % str(rows))
	host.queue_free()
	await process_frame
