extends SceneTree
## lane w54-audio：守城补挂的声（SfxCues 表里守城五行）。一段钉一条，回退即红。
##   原先兴化守城一声不出：入城（札记「你从海口进了城。城门在身后合上。」）、关城门（「城门落了闸」）、囊山每一阵、
##   出海劫粮道、拆船料修墙、城破都只有字。
##   一、表：五行都在、标 added、各带 gap_ms；囊山 / 劫粮道胜负两行都是「一阵鼓、随后磬音」两层。
##   二、真起 Main（headless）逐处走真路：海口「入城」卡（_on_siege_card siege_enter）、旧档读回海口自动入城
##       （_load_scene_inner xinghua_harbor）各记一声城门；林华请命页按「不去。关城门」记一声落闸；
##       囊山设伏（_siege_nangshan）记胜或负那一行两层；出海劫粮道（_siege_relief_raid）同；拆船料修墙（_siege_relief_timber）
##       记一声；城破（_siege_fall）记两层。
##   三、开关 sfx_cues 关：入城、囊山同一处真路记 off、不响；账照旧（囊山照打、round 照加）。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_siege_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_SIEGE PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_SIEGE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

const SIEGE := [&"siege_gate", &"siege_win", &"siege_lose", &"siege_timber", &"siege_fall"]

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _main: Node = null
var gs: Node = null
var cal: Node = null
var fleet: Node = null
var _clock := 7_000_000


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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	cal = root.get_node("/root/Calendar")
	fleet = root.get_node("/root/Fleet")
	_Switches.reset()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for _i in 6:
		await process_frame
	print("== 一、表")
	_sec_table()
	print("== 二、真起 Main 逐处走真路")
	await _sec_main()
	print("== 三、开关 sfx_cues 关")
	await _sec_off()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


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
	await create_timer(1.0).timeout


func _sec_table() -> void:
	var bad: PackedStringArray = []
	for hook in SIEGE:
		var row: Dictionary = _SFX.HOOKS.get(hook, {})
		if row.is_empty() or not bool(row.get("added", false)) or int(row.get("gap_ms", 0)) <= 0:
			bad.append(String(hook))
	_check(bad.is_empty(), "守城五行都在、标 added、各带 gap_ms（不对的 %s）" % ",".join(bad))
	var two := true
	for hook in [&"siege_win", &"siege_lose"]:
		var layers: Array = _SFX.HOOKS.get(hook, {}).get("layers", [])
		two = two and layers.size() == 2 and StringName(layers[0][0]) == &"combat_start" and float(layers[1][2]) > 0.0
	_check(two, "胜负两行都是「一阵鼓、随后磬音」两层（鼓当下、磬晚出）")


func _close_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main.set("_chapter_host", null)
		(host as Node).queue_free()


## 兴化围城：1276-11-03，士人线、改名文龙；open = 进城开城防记录（否则人停在海口，城防还没开）
func _stage_siege(open := true) -> void:
	_close_sheet()
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	gs.money = 20000
	gs.fame = 30
	gs.last_port = "xinghua"
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	root.get_node("/root/Crew").from_dict({})
	fleet.ships = []
	fleet.add_ship("fu_ship_large", "安济")
	fleet.add_ship("fu_ship_large", "通济")
	for s in fleet.ships:
		s["crew"] = 75
		s["sail_level"] = 3
	fleet.water = 400
	fleet.food = 400
	fleet.morale = 80
	_main.load_scene("xinghua" if open else "xinghua_harbor")
	await process_frame


func _sec_main() -> void:
	# 海口「入城」卡：人在海口、城防还没开
	await _stage_siege(false)
	_check(not gs.siege_open() and str(_main.get("current_scene_id")) == "xinghua_harbor", "1276-11 停在兴化海口、城防还没开")
	_fresh()
	_main.call("_on_siege_card", "siege_enter")
	_check(_sounded(&"siege_gate") == 1 and str(_main.get("current_scene_id")) == "xinghua" and gs.siege_open(),
		"海口「入城」卡（_on_siege_card siege_enter）：进了城、开了守城页、记一声城门（%s）" % str(_whys(&"siege_gate")))
	# 旧档读回海口：城防开着，自动入城
	_fresh()
	_main.load_scene("xinghua_harbor")
	_check(_sounded(&"siege_gate") == 1 and str(_main.get("current_scene_id")) == "xinghua",
		"旧档读回海口自动入城（_load_scene_inner）：记一声城门（%s）" % str(_whys(&"siege_gate")))
	# 林华请命：不去，关城门
	gs.siege_set("grain", 120)
	gs.siege_set("round", 2)
	_main.call("_siege_lin_hua")
	var stay: Button = null
	for c in (_main.get("choices_container") as Node).get_children():
		if c is Button and (c as Button).text == "不去。关城门":
			stay = c
	_check(stay != null, "林华请命页有「不去。关城门」钮")
	if stay != null:
		_fresh()
		stay.pressed.emit()
		_check(_sounded(&"siege_gate") == 1 and gs.has_flag("cao_opened"), "按「不去。关城门」：落闸、记一声城门（%s）" % str(_whys(&"siege_gate")))
	# 囊山设伏一阵
	await _stage_siege()
	gs.siege = {"troops": 2000, "grain": 120, "wall": 100, "morale": 60, "round": 0, "shishou": "kept",
		"envoy_wang": true, "envoy_kin": true, "lin_hua_sent": true}
	_fresh()
	seed(4242)
	_main.call("_siege_nangshan")
	await _settle()
	var won := int(gs.siege_get("morale")) > 60
	var hook: StringName = &"siege_win" if won else &"siege_lose"
	_check(int(gs.siege_get("round")) == 1 and _sounded(hook) == 2 and _whys(&"siege_win" if not won else &"siege_lose").is_empty(),
		"囊山第一阵（%s）：记 %s 两层——一阵鼓、随后磬音（%s）" % ["退敌" if won else "失利", hook, str(_whys(hook))])
	_close_sheet()
	# 出海劫粮道
	await _stage_siege()
	_fresh()
	var r: Dictionary = _main.call("_siege_relief_raid")
	await _settle()
	var rhook: StringName = &"siege_win" if bool(r.get("won", false)) else &"siege_lose"
	_check(not r.is_empty() and _sounded(rhook) == 2, "出海劫粮道（_siege_relief_raid，%s）：记 %s 两层（%s）" % [
		"得手" if bool(r.get("won", false)) else "失手", rhook, str(_whys(rhook))])
	# 拆船料修墙
	await _stage_siege()
	gs.siege_set("wall", 60)
	_fresh()
	var add: int = _main.call("_siege_relief_timber", 0)
	_check(add > 0 and _sounded(&"siege_timber") == 1, "拆船料修墙（_siege_relief_timber）：墙加 %d、记一声（%s）" % [add, str(_whys(&"siege_timber"))])
	# 城破（放最后：落定结局）
	await _stage_siege()
	_fresh()
	_main.call("_siege_fall", "粮尽")
	await _settle()
	_check(str(gs.get("ended")) == "忠肃" and _sounded(&"siege_fall") == 2, "城破（_siege_fall 粮尽）：落「忠肃」、记两层（%s）" % str(_whys(&"siege_fall")))
	_close_sheet()


func _sec_off() -> void:
	await _stage_siege()
	_main.load_scene("xinghua_harbor")
	gs.siege = {"troops": 2000, "grain": 120, "wall": 100, "morale": 60, "round": 0, "shishou": "kept",
		"envoy_wang": true, "envoy_kin": true, "lin_hua_sent": true}
	_Switches.set_on(_SFX.SWITCH, false)
	_fresh()
	_main.call("_on_siege_card", "siege_enter")
	_main.call("_siege_nangshan")
	await _settle()
	_Switches.reset()
	var off := _whys(&"siege_gate") == ["off"] and (_whys(&"siege_win") + _whys(&"siege_lose")) == ["off"]
	_check(off, "开关关：入城、囊山同一处真路记 off、不响（城门 %s / 胜负 %s）" % [_whys(&"siege_gate"), _whys(&"siege_win") + _whys(&"siege_lose")])
	_check(int(gs.siege_get("round")) == 1, "开关关时账照旧：囊山照打、round 加到 1")
	_close_sheet()
