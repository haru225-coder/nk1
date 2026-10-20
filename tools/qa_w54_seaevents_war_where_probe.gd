extends SceneTree
## lane w54-seaevents：战时遭遇看船这一日在哪片海，不看航段两端。
##   Voyage._war_event 原先只看航段两端的战况：泉州往博多走到博多唐房外、广州往占城到了占城港外，照样「朝廷用船。按册征调」；
##   明州（1276-01 降元）往博多到了博多港外照样「大元巡海，落帆受检」；泉州往博多一路傍过已降元的温州、明州，
##   两端都没降，反倒一条元军哨船也撞不上。现在海上取「所在位置」那一港（Economy.sea_here，海图逐日记）。
## 断言（真走 Voyage.roll_day_event，海上、sea_here 摆到航线上那一港，逐日掷两千回数三样战时遭遇）：
##   W1 泉州→博多 1275-06：船在泉州 / 福州 / 温州 / 明州外照常抽到征船，到了耽罗 / 萨摩 / 博多外一回不出；泉州→流求到了流求外同此。
##   W2 明州→博多 1276-06：船在明州 / 耽罗外（已降元）照常抽到元军哨船，到了博多外哨船、难民船、征船都一回不出。
##   W3 泉州→博多 1276-06（两端都没降）：船过温州、明州外（已降元）抽得到元军哨船；在泉州外只有征船、没有哨船。
##   W4 广州→占城 1275-06：广州外照常征船，到了占城外一回不出。
##   W5 不在海上（探针直调、海图没起）或 sea_here 没记：照旧看两端（泉州→福州 1277-01 抽得到哨船 / 难民船，澎湖→流求一回不出）。
##   W6 海图真记的位置：SeaChart._refresh_status 记下船标最近的港，船到博多外抽不到征船、刚出泉州抽得到。
##   另印「数」：几条航线全程能撞上各样遭遇的里程份额，改前（看两端）/ 改后（看所在）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_war_where_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_WAR_WHERE cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const ROLLS := 2000

var _gs: Node
var _cal: Node
var _fleet: Node
var _voy: Node
var _eco: Node
var _req := 0
var _patrol := 0
var _refugee := 0
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
	if _gs == null or _cal == null or _fleet == null or _voy == null or _eco == null:
		_expect(false, "autoload 不全")
		_report()
		return
	var ek: Dictionary = _voy.get("EventKind")
	_req = int(ek["REQUISITION"])
	_patrol = int(ek["YUAN_PATROL"])
	_refugee = int(ek["REFUGEE"])
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_fleet.set("ships", [])
	_fleet.call("add_ship", "keel_boat", "探针客舟")
	_fleet.set("water", 60)
	_fleet.set("food", 60)

	print("── W1 泉州→博多 / 泉州→流求 1275-06：征船")
	_ym(1275, 6)
	for here in ["quanzhou", "fuzhou", "wenzhou", "mingzhou"]:
		var c := _count("quanzhou", "hakata", here)
		_expect(int(c[_req]) > 0, "W1 泉州→博多，船在%s外：征船 %d 回" % [here, int(c[_req])])
	for here in ["jeju", "kagoshima", "hakata"]:
		var c := _count("quanzhou", "hakata", here)
		_expect(int(c[_req]) == 0, "W1 泉州→博多，船在%s外：征船 %d 回" % [here, int(c[_req])])
	var cr := _count("quanzhou", "ryukyu", "ryukyu")
	_expect(int(cr[_req]) == 0, "W1 泉州→流求，船在流求外：征船 %d 回" % int(cr[_req]))

	print("── W2 明州→博多 1276-06：元军哨船")
	_ym(1276, 6)
	for here in ["mingzhou", "jeju"]:
		var c := _count("mingzhou", "hakata", here)
		_expect(int(c[_patrol]) > 0, "W2 明州→博多，船在%s外（已降元）：元军哨船 %d 回" % [here, int(c[_patrol])])
	var ch := _count("mingzhou", "hakata", "hakata")
	_expect(int(ch[_patrol]) == 0 and int(ch[_refugee]) == 0 and int(ch[_req]) == 0,
		"W2 明州→博多，船在博多外：哨船 %d、难民船 %d、征船 %d 回" % [int(ch[_patrol]), int(ch[_refugee]), int(ch[_req])])

	print("── W3 泉州→博多 1276-06（两端都没降）")
	for here in ["wenzhou", "mingzhou"]:
		var c := _count("quanzhou", "hakata", here)
		_expect(int(c[_patrol]) > 0, "W3 泉州→博多，船过%s外（已降元）：元军哨船 %d 回" % [here, int(c[_patrol])])
	var cq := _count("quanzhou", "hakata", "quanzhou")
	_expect(int(cq[_req]) > 0 and int(cq[_patrol]) == 0,
		"W3 泉州→博多，船在泉州外（对峙未降）：征船 %d 回、哨船 %d 回" % [int(cq[_req]), int(cq[_patrol])])

	print("── W4 广州→占城 1275-06：征船")
	_ym(1275, 6)
	var cg := _count("guangzhou", "champa", "guangzhou")
	var cc := _count("guangzhou", "champa", "champa")
	_expect(int(cg[_req]) > 0 and int(cc[_req]) == 0, "W4 广州→占城：广州外征船 %d 回，占城外 %d 回" % [int(cg[_req]), int(cc[_req])])

	print("── W5 不在海上 / 没记位置：照旧看两端")
	_ym(1277, 1)
	var e1 := _count("quanzhou", "fuzhou", "")
	var e2 := _count("penghu", "ryukyu", "")
	_expect(int(e1[_patrol]) + int(e1[_refugee]) > 0 and int(e2[_req]) + int(e2[_patrol]) + int(e2[_refugee]) == 0,
		"W5 不在海上：泉州→福州 1277-01 哨船 %d、难民船 %d；澎湖→流求 %d" % [int(e1[_patrol]), int(e1[_refugee]),
			int(e2[_req]) + int(e2[_patrol]) + int(e2[_refugee])])
	_eco.set("sea_here", "")
	_fleet.set("at_sea", true)
	var e3 := _count_raw("quanzhou", "fuzhou")
	_fleet.set("at_sea", false)
	_expect(int(e3[_patrol]) + int(e3[_refugee]) > 0, "W5 在海上但没记位置：泉州→福州 1277-01 哨船 %d、难民船 %d" % [int(e3[_patrol]), int(e3[_refugee])])

	print("── W6 海图真记的位置")
	_ym(1275, 6)
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(4)
	chart.set("sailing", false)
	chart.set("origin_port", "quanzhou")
	chart.set("selected_port", "hakata")
	var total := float(_voy.call("distance_li", "quanzhou", "hakata"))
	chart.set("total_li", total)
	chart.set("remaining_li", total * 0.04)
	chart.call("_refresh_status")
	var far_here := str(_eco.get("sea_here"))
	_fleet.set("at_sea", true)
	var w_far := _count_raw("quanzhou", "hakata")
	chart.set("remaining_li", total * 0.99)
	chart.call("_refresh_status")
	var near_here := str(_eco.get("sea_here"))
	var w_near := _count_raw("quanzhou", "hakata")
	_fleet.set("at_sea", false)
	_expect(far_here == "hakata" and int(w_far[_req]) == 0 and near_here == "quanzhou" and int(w_near[_req]) > 0,
		"W6 海图记下船到%s外：征船 %d 回；刚出%s：征船 %d 回" % [far_here, int(w_far[_req]), near_here, int(w_near[_req])])
	chart.queue_free()
	await _frames(2)
	_eco.set("sea_here", "")

	print("── 数：全程能撞上的里程份额（改前看两端 / 改后看所在）")
	_share("泉州→博多", "quanzhou", "hakata", 1275, 6)
	_share("泉州→博多", "quanzhou", "hakata", 1276, 6)
	_share("泉州→流求", "quanzhou", "ryukyu", 1275, 6)
	_share("明州→博多", "mingzhou", "hakata", 1276, 6)
	_share("广州→占城", "guangzhou", "champa", 1275, 6)
	_share("泉州→福州", "quanzhou", "fuzhou", 1276, 6)
	_share("泉州→广州", "quanzhou", "guangzhou", 1277, 1)
	_report()


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _ym(y: int, m: int) -> void:
	_cal.call("from_dict", {"year": y, "month": m, "day": 5})


## here 非空：船在海上、海图记的所在位置是 here；空：不在海上
func _count(from_id: String, to_id: String, here: String) -> Dictionary:
	_eco.set("sea_here", here)
	_fleet.set("at_sea", here != "")
	var out := _count_raw(from_id, to_id)
	_fleet.set("at_sea", false)
	_eco.set("sea_here", "")
	return out


## 逐日真抽 ROLLS 回（船向 90°、针路），数三样战时遭遇；抽之前存下船队，抽完原样还回（风涛扣船体、无风扣士气）
func _count_raw(from_id: String, to_id: String) -> Dictionary:
	_voy.call("begin_voyage")
	var keep_fleet: Dictionary = _fleet.call("to_dict")
	var at_sea := bool(_fleet.get("at_sea"))
	seed(5402)
	var out := {_req: 0, _patrol: 0, _refugee: 0}
	for _i in ROLLS:
		var ev: Dictionary = _voy.call("roll_day_event", 90.0, from_id, to_id)
		var k := int(ev.get("kind", 0))
		if out.has(k):
			out[k] = int(out[k]) + 1
	_fleet.call("from_dict", keep_fleet)
	_fleet.set("at_sea", at_sea)
	return out


## 一港在这一月能掷出哪几样（与 _war_event 同一判据：征船 1275-04 起宋土战港、哨船 1276-01 起已降元、难民船 1276-01 起围城或已降）
func _can(pids: Array) -> Array:
	var now := "%04d-%02d" % [int(_cal.get("year")), int(_cal.get("month"))]
	var req := false
	var pat := false
	var ref := false
	for pid in pids:
		var s := str(_eco.call("war_status", pid))
		req = req or (now >= "1275-04" and bool(_voy.call("_is_song_war_port", pid, s)))
		pat = pat or (now >= "1276-01" and s == "fallen")
		ref = ref or (now >= "1276-01" and s in ["besieged", "fallen"])
	return [req, pat, ref]


func _share(label: String, from_id: String, to_id: String, y: int, m: int) -> void:
	_ym(y, m)
	var total := float(_voy.call("distance_li", from_id, to_id))
	var before: Array = _can([from_id, to_id])
	var hit := [0, 0, 0]
	var steps := 200
	for i in steps:
		var here := str(_voy.call("nearest_sea_port", from_id, to_id, total * (float(i) + 0.5) / float(steps)))
		var a: Array = _can([here])
		for j in 3:
			if bool(a[j]):
				hit[j] += 1
	var names := ["征船", "元军哨船", "难民船"]
	var parts: PackedStringArray = []
	for j in 3:
		parts.append("%s %d%% → %d%%" % [names[j], 100 if bool(before[j]) else 0, int(round(100.0 * hit[j] / steps))])
	print("  数 %s %d-%02d（%d 里）：%s" % [label, y, m, int(total), "，".join(parts)])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_WAR_WHERE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
