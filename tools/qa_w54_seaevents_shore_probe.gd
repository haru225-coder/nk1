extends SceneTree
## lane w54-seaevents：同一处岸影一程只露一回面。
##   Voyage._discovery_event 原先每回都从「沿途未勘见的发现物」里重抽：点「不理会　继续航行」之后同一程照样再抽到同一处，
##   船已开出几百里，「左舷远处露出一线陆影……那多半就是老辈人讲的 X」又来一遍。
## 断言（真走 Voyage.roll_day_event，泉州→福州傍岸、1260-06，沿途四处未勘见：湄洲神女祠、灵山蕃客墓、废烽堠、落漈）：
##   S1 一程逐日抽两千日、一处不勘：每处至多露一回面。
##   S2 下一程（begin_voyage，即 SeaChart 发舶时那一下）：又露得出来。
##   S3 这一程四处都露过面：岸影那一档抽中的日子照无事过（kind NONE、不换成别的遭遇）。
##   S4 勘见了的（record_discovery）本就不再露。
##   另印「数」：傍岸十二日一程、一处不勘，改前（每日都像新一程）/ 改后同一处重露的回数，各掷两千程（沿途四处 / 只剩一处）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_shore_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_SHORE cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const COAST := 2
const ALONG := ["meizhou_shrine", "lingshan_tombs", "beacon_ruin", "heishui_gou"]

var _gs: Node
var _cal: Node
var _fleet: Node
var _voy: Node
var _disc := 0
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
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	_voy = root.get_node_or_null("Voyage")
	if _gs == null or _cal == null or _fleet == null or _voy == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_disc = int((_voy.get("EventKind") as Dictionary)["DISCOVERY"])
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1260, "month": 6, "day": 5})
	_fleet.set("ships", [])
	_fleet.call("add_ship", "keel_boat", "探针客舟")
	_fleet.set("water", 60)
	_fleet.set("food", 60)
	_fleet.set("at_sea", false)
	var cand: Array = []
	for d in _voy.call("_discovery_candidates", "quanzhou", "fuzhou"):
		cand.append(str((d as Dictionary).get("id", "")))
	cand.sort()
	var want := ALONG.duplicate()
	want.sort()
	_expect(cand == want, "泉州→福州沿途未勘见的发现物：%s" % str(cand))

	print("── S1 一程两千日，一处不勘")
	seed(5405)
	_voy.call("begin_voyage")
	var seen := _offers(2000, false)
	var most := 0
	for k in seen.keys():
		most = maxi(most, int(seen[k]))
	_expect(not seen.is_empty() and most == 1, "S1 每处至多露一回面：%s" % str(seen))
	print("── S2 下一程")
	_voy.call("begin_voyage")
	var again := _offers(400, false)
	_expect(not again.is_empty(), "S2 下一程又露得出来：%s" % str(again))
	print("── S3 四处都露过面")
	_voy.call("begin_voyage")
	for _i in 200:
		_voy.call("_discovery_event", "quanzhou", "fuzhou")
	var ev: Dictionary = _voy.call("_discovery_event", "quanzhou", "fuzhou")
	_expect(int(ev.get("kind", -1)) == int((_voy.get("EventKind") as Dictionary)["NONE"]),
		"S3 岸影那一档抽中的日子照无事过：kind=%d" % int(ev.get("kind", -1)))
	print("── S4 勘见了的不再露")
	_voy.call("begin_voyage")
	_gs.call("record_discovery", "beacon_ruin")
	var after := _offers(2000, false)
	_expect(not after.has("beacon_ruin") and not after.is_empty(), "S4 废烽堠勘见之后不再露：%s" % str(after))
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)

	print("── 数：傍岸十二日一程、一处不勘，同一处重露的回数（各两千程）")
	var old4: Array = _repeat_stats(true)
	var new4: Array = _repeat_stats(false)
	print("  数 沿途四处未勘：改前两千程里 %d 程撞见同一处重露、共重露 %d 回；改后 %d 程、%d 回" % [old4[0], old4[1], new4[0], new4[1]])
	for id in ["meizhou_shrine", "lingshan_tombs", "heishui_gou"]:
		_gs.call("record_discovery", id)
	var old1: Array = _repeat_stats(true)
	var new1: Array = _repeat_stats(false)
	print("  数 只剩废烽堠一处未勘：改前 %d 程、共重露 %d 回；改后 %d 程、%d 回" % [old1[0], old1[1], new1[0], new1[1]])
	_expect(int(new4[1]) == 0 and int(new1[1]) == 0, "改后同一处一程不重露（两千程重露 %d / %d 回）" % [new4[1], new1[1]])
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


## 傍岸逐日真抽 days 日，数各处露面的回数 {id: 回}；forget = 每日抽之前都 begin_voyage（像每日都是新一程，即改前没有记性的抽法）。
## 抽之前存下船队，抽完原样还回（风涛扣船体、无风扣士气）
func _offers(days: int, forget: bool) -> Dictionary:
	var keep_fleet: Dictionary = _fleet.call("to_dict")
	var out := {}
	for _i in days:
		if forget:
			_voy.call("begin_voyage")
		var ev: Dictionary = _voy.call("roll_day_event", 20.0, "quanzhou", "fuzhou", COAST)
		if int(ev.get("kind", 0)) == _disc:
			var id := str(ev.get("discovery_id", ""))
			out[id] = int(out.get(id, 0)) + 1
	_fleet.call("from_dict", keep_fleet)
	return out


## 两千程、每程傍岸十二日：[撞见同一处重露的程数, 共重露回数]
func _repeat_stats(forget: bool) -> Array:
	seed(5406)
	var rep_total := 0
	var trips := 0
	for _t in 2000:
		_voy.call("begin_voyage")
		var c := _offers(12, forget)
		var rep := 0
		for k in c.keys():
			rep += int(c[k]) - 1
		rep_total += rep
		trips += 1 if rep > 0 else 0
	return [trips, rep_total]


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_SHORE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
