extends SceneTree
## lane w54-seaevents：海上相逢传的行情只传卖得了货的港。
##   Voyage._pick_rumor 原先从已解锁的海港里随手挑一港：围城牙行闭门的兴化、广州（1276-11），文永之役后封港的博多、萨摩
##   （1274-10 至 1275-04）也照传——「对方说兴化的米粮，眼下大约能卖到 N 钱一件」；记下来写到别港同一货的牙行卡上
##   （GameState.rumor_elsewhere 取约卖最高的一港），围城米价正高，卡上就挂着「传闻兴化约卖 N」，那里却一件也卖不出去。
## 断言（直调 _pick_rumor 三千回 + 真走 _merchant_event 两千回，seed 固定，看传的是哪几港）：
##   U1 1276-11：兴化、兴化海口、广州（围城）一回不传；泉州、福州（已降，牙行照开）照传。
##   U2 1275-01：博多、萨摩（封港）一回不传。
##   U3 1276-06 对照：闭门的港没有，海港个个传得到（兴化、博多也在）。
##   U4 1276-11 真走海上相逢：传闻那一句、记下行情的港都开着牙行。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_rumor_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_RUMOR cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _gs: Node
var _cal: Node
var _fleet: Node
var _voy: Node
var _eco: Node
var _gm: Node
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
	_eco = root.get_node_or_null("Economy")
	_gm = root.get_node_or_null("GameManager")
	if _gs == null or _cal == null or _fleet == null or _voy == null or _eco == null or _gm == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_fleet.set("ships", [])
	_fleet.call("add_ship", "keel_boat", "探针客舟")
	_fleet.set("water", 60)
	_fleet.set("food", 60)

	print("── U1 1276-11 围城")
	_ym(1276, 11)
	var got := _picked(3000)
	_expect(not got.has("xinghua") and not got.has("xinghua_harbor") and not got.has("guangzhou")
		and got.has("quanzhou") and got.has("fuzhou"),
		"U1 兴化 / 兴化海口 / 广州围城不传，泉州、福州照传：%s" % str(got))
	print("── U2 1275-01 封港")
	_ym(1275, 1)
	got = _picked(3000)
	_expect(not got.has("hakata") and not got.has("kagoshima") and got.has("quanzhou"),
		"U2 博多、萨摩封港不传：%s" % str(got))
	print("── U3 1276-06 对照")
	_ym(1276, 6)
	got = _picked(3000)
	var sea_ports: Array = []
	for p in _gm.call("unlocked_ports"):
		if int((p as Dictionary).get("depth", 0)) > 0:
			sea_ports.append(str((p as Dictionary).get("id", "")))
	var all_in := true
	for pid in sea_ports:
		if not got.has(pid):
			all_in = false
	_expect(all_in and got.has("xinghua") and got.has("hakata"), "U3 闭门的港没有：%d 个海港个个传得到（%s）" % [sea_ports.size(), str(got)])
	print("── U4 1276-11 真走海上相逢")
	_ym(1276, 11)
	var shut := 0
	var told := 0
	seed(5404)
	for _i in 2000:
		var ev: Dictionary = _voy.call("_merchant_event", "quanzhou")
		var pid := str(ev.get("rumor_port", ""))
		if pid == "":
			continue
		told += 1
		var pname := str(_gm.call("get_port_name", pid))
		if not bool(_eco.call("is_market_open", pid)) or not str(ev.get("text", "")).contains("对方说%s的" % pname):
			shut += 1
	_expect(told > 0 and shut == 0, "U4 海上相逢传了 %d 回行情，传的港闭着门（或句子对不上港）%d 回" % [told, shut])
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _ym(y: int, m: int) -> void:
	_cal.call("from_dict", {"year": y, "month": m, "day": 5})


## _pick_rumor 掷 n 回，返回 {港: 回数}
func _picked(n: int) -> Dictionary:
	seed(5403)
	var out := {}
	for _i in n:
		var r: Dictionary = _voy.call("_pick_rumor")
		var pid := str(r.get("port", ""))
		if pid != "":
			out[pid] = int(out.get(pid, 0)) + 1
	return out


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_RUMOR cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
