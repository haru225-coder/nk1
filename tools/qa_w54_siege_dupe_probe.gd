extends SceneTree
## lane w54-siege：衙门募兵、船屋修墙两页的钮，余量不过小档时不再出两枚一模一样的钮。
## 两页各按两档排钮（募兵 50 / 200 人，修墙加 20 / 60），每档截到余量（mini(档, 余量)）。修前余量不过小档时两档截成同一个数：
##   船屋——城墙 60 起修两回「加 60」到 180，余量 20，页上两枚「加固城墙　加 20（300 钱・上限 200）」；
##   衙门——名声 30 募兵上限 660，「募兵 200」一回、「募兵 50」三回后余量 10，两枚「募兵 10 人（100 钱）」。
## 断言（各档先开页、读该页的钮字）：
##   衙门余量 10 / 50 → 只一枚（10 人 / 50 人）；51 → 50 人、51 人两枚；160 → 50、160；360 → 50、200；募满 → 一枚不出、照旧那句「能招的都招了」；
##   船屋余量 10 / 20 → 只一枚；21 → 20、21；140 → 20、60；满 200 → 一枚不出、照旧那句「再堆料也无非是墙」；
##   每页的钮字两两不同；反向基：余量 10 那一枚点下去照旧作数（兵 / 城墙加满、钱照扣）。
## 用法：godot --headless --path . -s res://tools/qa_w54_siege_dupe_probe.gd（经门锁跑）
## 末行 W54_SIEGE_DUPE cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		_report()
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(_main)
	for i in 10:
		await process_frame
	Switches.reset()
	print("── 衙门募兵（名声 30、募兵上限 660）")
	for c in [[10, [10]], [50, [50]], [51, [50, 51]], [160, [50, 160]], [360, [50, 200]], [0, []]]:
		await _muster(int(c[0]), c[1])
	print("── 船屋修墙（上限 200）")
	for c in [[10, [10]], [20, [20]], [21, [20, 21]], [140, [20, 60]], [0, []]]:
		await _wall(int(c[0]), c[1])
	print("── 反向基：只剩一枚的那一档点下去照旧作数")
	await _clicks()
	_report()


func _report() -> void:
	_reported = true
	Switches.reset()
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SIEGE_DUPE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 士人线改名、景炎元年冬月初三进兴化城，城防开着；名声 30（募兵上限 660）、钱两万，开局小艍一条
func _stage() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main.set("_chapter_host", null)
		(host as Node).queue_free()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_gs.set_flag("renamed_wenlong")
	_gs.identity = "scholar"
	_gs.money = 20000
	_gs.fame = 30
	_gs.last_port = "xinghua"
	_cal.from_dict({"year": 1276, "month": 11, "day": 3})
	root.get_node("/root/Crew").from_dict({})
	_fleet.ships = []
	_fleet.add_ship("sampan", "无名小艍")
	_fleet.water = 60
	_fleet.food = 60
	_main.load_scene("xinghua")
	await process_frame


## 本页以 prefix 打头的钮字（排队待删的不算）
func _texts(prefix: String) -> Array:
	var out: Array = []
	for c in _main.choices_container.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion() and str((c as Button).text).begins_with(prefix):
			out.append((c as Button).text)
	return out


func _has_label(needle: String) -> bool:
	for c in _main.choices_container.get_children():
		if c is Label and not (c as Node).is_queued_for_deletion() and str((c as Label).text).find(needle) >= 0:
			return true
	return false


func _distinct(arr: Array) -> bool:
	var seen := {}
	for t in arr:
		if seen.has(t):
			return false
		seen[t] = true
	return true


func _muster(room: int, want_n: Array) -> void:
	await _stage()
	var cap: int = _gs.siege_troop_cap()
	_gs.siege_set("troops", cap - room)
	_main._on_siege_card("siege_muster")
	await process_frame
	var got := _texts("募兵")
	var want: Array = []
	for n in want_n:
		want.append("募兵 %d 人（%d 钱）" % [int(n), int(n) * 10])
	var ok: bool = got == want and _distinct(got)
	if room <= 0:
		ok = ok and _has_label("能招的都招了")
	_expect(ok, "兵 %d / 上限 %d（余量 %d）：募兵钮 %s（应 %s）" % [cap - room, cap, room, str(got), str(want)])


func _wall(room: int, want_n: Array) -> void:
	await _stage()
	_gs.siege_set("wall", 200 - room)
	_main._on_siege_card("siege_wall")
	await process_frame
	var got := _texts("加固城墙")
	var want: Array = []
	for n in want_n:
		want.append("加固城墙　加 %d（%d 钱・上限 200）" % [int(n), int(n) * 15])
	var ok: bool = got == want and _distinct(got)
	if room <= 0:
		ok = ok and _has_label("再堆料也无非是墙")
	_expect(ok, "城墙 %d / 200（余量 %d）：修墙钮 %s（应 %s）" % [200 - room, room, str(got), str(want)])


func _clicks() -> void:
	await _stage()
	var cap: int = _gs.siege_troop_cap()
	_gs.siege_set("troops", cap - 10)
	_main._on_siege_card("siege_muster")
	await process_frame
	var bs := _texts("募兵")
	var b: Button = null
	for c in _main.choices_container.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion() and str((c as Button).text).begins_with("募兵"):
			b = c
			break
	if b != null:
		b.pressed.emit()
		await process_frame
	_expect(b != null and _gs.siege_get("troops") == cap and _gs.money == 19900,
		"余量 10 点「%s」：兵 %d → %d（上限 %d）、钱 20000 → %d" % [str(bs), cap - 10, _gs.siege_get("troops"), cap, _gs.money])
	await _stage()
	_gs.siege_set("wall", 190)
	_main._on_siege_card("siege_wall")
	await process_frame
	b = null
	for c in _main.choices_container.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion() and str((c as Button).text).begins_with("加固城墙"):
			b = c
			break
	if b != null:
		b.pressed.emit()
		await process_frame
	_expect(b != null and _gs.siege_get("wall") == 200 and _gs.money == 19850,
		"城墙余量 10 点修墙：城墙 190 → %d、钱 20000 → %d" % [_gs.siege_get("wall"), _gs.money])
