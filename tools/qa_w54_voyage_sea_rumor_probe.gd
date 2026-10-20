extends SceneTree
## lane w54-voyage（w54-port 交）：海上相逢的福船不传牙行上了门闸的港的行情。
##   Voyage._pick_rumor 原先从 GameManager.unlocked_ports() 里随手挑港，不看战况：博多唐房 / 萨摩封港（1274-10 至 1275-04）、
##   兴化两处与广州被围（1276-11）时，海上照说「博多唐房的生丝，眼下大约能卖到 N 钱一件」，还能「记下这条行情」——
##   那港牙行上了门闸、船也进不去。港上的打听 / 行会抄本早就滤掉闭门港（Main._collect_spreads，lane w53-6，Economy.is_market_open）。
## 断言（固定种子各抽 400 次）：
##   R1 1274 年十一月（博多、萨摩封港）：_pick_rumor 一次也不挑这两港；其余开着的海港都挑得到。
##   R2 1276 年十一月（兴化、兴化海口、广州被围）：一次也不挑这三港；陷落的福州（牙行照开）照样挑得到。
##   R3 太平年月（1262）：十四港都挑得到（不多滤）。
##   R4 真走「海上相逢」那一面（Voyage._merchant_event）：传闻港不是闭门港，札记那句不提闭门港的港名。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_sea_rumor_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_SEA_RUMOR cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const DRAWS := 400

var _gs: Node
var _gm: Node
var _cal: Node
var _voy: Node
var _eco: Node
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
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	_voy = root.get_node_or_null("Voyage")
	_eco = root.get_node_or_null("Economy")
	if _gs == null or _gm == null or _cal == null or _voy == null or _eco == null:
		_expect(false, "autoload 不全")
		_report()
		return
	await process_frame
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_section("R1 1274 年十一月：博多、萨摩封港", 1274, 11, ["hakata", "kagoshima"], [])
	_section("R2 1276 年十一月：兴化、兴化海口、广州被围", 1276, 11, ["xinghua", "xinghua_harbor", "guangzhou"], ["fuzhou"])
	_section("R3 太平年月（1262）：十四港都挑得到", 1262, 4, [], [])
	_r4_merchant()
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


## 解锁、有行情深浅的海港
func _sea_ports() -> Array:
	var out: Array = []
	for p in _gm.call("unlocked_ports"):
		if int(p.get("depth", 0)) > 0:
			out.append(str(p.get("id", "")))
	return out


func _section(title: String, y: int, m: int, shut: Array, open_must: Array) -> void:
	print("── " + title)
	_cal.call("from_dict", {"year": y, "month": m, "day": 5})
	var closed_now: Array = []
	for pid in _sea_ports():
		if not bool(_eco.call("is_market_open", pid)):
			closed_now.append(pid)
	closed_now.sort()
	var want_shut := shut.duplicate()
	want_shut.sort()
	_expect(closed_now == want_shut, "此刻牙行上门闸的港 = %s（实 %s）" % [str(want_shut), str(closed_now)])
	seed(4242 + y)
	var hits := {}
	for _i in DRAWS:
		var r: Dictionary = _voy.call("_pick_rumor")
		var pid := str(r.get("port", ""))
		hits[pid] = int(hits.get(pid, 0)) + 1
	var bad: Array = []
	for pid in shut:
		if hits.has(pid):
			bad.append("%s×%d" % [pid, int(hits[pid])])
	_expect(bad.is_empty(), "抽 %d 次不挑闭门港（挑到 %s）" % [DRAWS, str(bad) if not bad.is_empty() else "无"])
	var missing: Array = []
	for pid in _sea_ports():
		if pid in shut:
			continue
		if not hits.has(pid):
			missing.append(pid)
	_expect(missing.is_empty(), "开着的海港都挑得到（漏 %s）%s" % [str(missing),
		("；陷落仍开市的 %s 在内" % str(open_must)) if not open_must.is_empty() else ""])


func _r4_merchant() -> void:
	print("── R4 真走「海上相逢」：传闻港不是闭门港")
	_cal.call("from_dict", {"year": 1276, "month": 11, "day": 5})
	var shut := ["xinghua", "xinghua_harbor", "guangzhou"]
	var shut_names: Array = shut.map(func(pid): return str(_gm.call("get_port_name", pid)))
	seed(777)
	var n := 0
	var bad: Array = []
	for _i in 200:
		var ev: Dictionary = _voy.call("_merchant_event", "quanzhou")
		var pid := str(ev.get("rumor_port", ""))
		if pid == "":
			continue
		n += 1
		var text := str(ev.get("text", ""))
		if pid in shut:
			bad.append(pid)
		else:
			for nm in shut_names:
				if text.contains("对方说%s的" % nm):
					bad.append(nm)
	_expect(n >= 150 and bad.is_empty(), "海上相逢 %d 回带传闻，没有一回荐闭门港（荐到 %s）" % [n, str(bad) if not bad.is_empty() else "无"])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_SEA_RUMOR cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
