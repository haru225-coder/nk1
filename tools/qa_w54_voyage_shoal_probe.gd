extends SceneTree
## lane w54-voyage：傍岸擦浅滩，船体伤每艘各吃一份（Voyage._shoal_event 走 Fleet.damage_each_ship，同风涛）。
##   原先 SHOAL_HULL × 船数整份压给旗舰（Fleet.damage_fleet 只扣 ships[0]）：三船队旗舰一擦 15、两艘护航一点不伤，
##   傍岸一趟擦两三回，旗舰先磨到见底、护航还是满耐久；札记照算数写，旗舰只剩几点时也写满 15。
##   风涛那边早改成各吃一份（Voyage._storm_event 头注「每艘各吃这一份，再乘船数会把整场都堆到旗舰上」），浅滩漏了这一处。
## 断言：
##   S1 三船队（甲一档）擦一回：三艘各减 SHOAL_HULL，札记「船体受损 15」= 三艘实扣之和，士气减 3、行程系数照旧。
##   S2 旗舰只剩 3：旗舰扣到 0 为止，两艘护航照扣，札记写实扣之和（13），不写 15。
##   S3 单船：扣 SHOAL_HULL，与改前同数。
##   S4 甲三档（减伤 0.8）：每艘扣 SHOAL_HULL × 0.8。
##   S5 真走抽签那一路：傍岸逐日抽事（Voyage.roll_day_event，航法傍岸）抽到浅滩的那一日，三艘各减同数、旗舰不多吃。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_shoal_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_SHOAL cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const COAST := 2  # Voyage.CourseOrder.COAST

var cal: Node
var voyage: Node
var fleet: Node
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
	cal = root.get_node_or_null("Calendar")
	voyage = root.get_node_or_null("Voyage")
	fleet = root.get_node_or_null("Fleet")
	if cal == null or voyage == null or fleet == null:
		_expect(false, "autoload 不全")
		_report()
		return
	await process_frame
	# 太平年月（1262 年无战况）：逐日抽事不先抽到征船 / 哨船 / 难民
	cal.from_dict({"year": 1262, "month": 4, "day": 10})
	var hull := float(voyage.get("SHOAL_HULL"))
	_expect(hull > 0.0, "SHOAL_HULL = %.1f" % hull)
	_s1_three_ships(hull)
	_s2_flagship_low(hull)
	_s3_single(hull)
	_s4_armor(hull)
	_s5_rolled(hull)
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


## 三船队：福船（中）300、客舟 240、小艍 120，甲一档（减伤 1.0）
func _fleet3() -> void:
	fleet.ships.clear()
	for t in ["fu_ship_medium", "keel_boat", "sampan"]:
		fleet.add_ship(t)
	fleet.morale = 70


func _dur() -> Array:
	var out: Array = []
	for s in fleet.ships:
		out.append(float((s as Dictionary).get("durability", 0.0)))
	return out


func _loss(before: Array, after: Array) -> Array:
	var out: Array = []
	for i in before.size():
		out.append(float(before[i]) - float(after[i]))
	return out


func _sum(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t


func _s1_three_ships(hull: float) -> void:
	print("── S1 三船队擦一回：三艘各吃一份")
	_fleet3()
	var b := _dur()
	var ev: Dictionary = voyage.call("_shoal_event")
	var lost := _loss(b, _dur())
	_expect(is_equal_approx(float(lost[0]), hull) and is_equal_approx(float(lost[1]), hull) and is_equal_approx(float(lost[2]), hull),
		"三艘各减 %.0f（实减 %s；原先旗舰减 %.0f、护航 0）" % [hull, str(lost), hull * 3.0])
	_expect(str(ev.get("text", "")).ends_with("船体受损 %d。" % int(_sum(lost))),
		"札记写三艘实扣之和「船体受损 %d」（实写：%s）" % [int(_sum(lost)), str(ev.get("text", "")).get_slice("\n", 1)])
	_expect(int(fleet.morale) == 67 and str(ev.get("title", "")) == "浅滩"
		and is_equal_approx(float(ev.get("progress_mult", 0.0)), float(voyage.get("SHOAL_PROGRESS"))),
		"士气减 3、题「浅滩」、当日行程系数 SHOAL_PROGRESS 照旧")


func _s2_flagship_low(hull: float) -> void:
	print("── S2 旗舰只剩 3：扣到 0 为止，札记写实扣")
	_fleet3()
	(fleet.ships[0] as Dictionary)["durability"] = 3.0
	var b := _dur()
	var ev: Dictionary = voyage.call("_shoal_event")
	var a := _dur()
	var lost := _loss(b, a)
	_expect(float(a[0]) == 0.0 and is_equal_approx(float(lost[1]), hull) and is_equal_approx(float(lost[2]), hull),
		"旗舰 3 → 0，两艘护航各减 %.0f（实减 %s）" % [hull, str(lost)])
	_expect(str(ev.get("text", "")).ends_with("船体受损 %d。" % int(3.0 + hull * 2.0)),
		"札记写实扣之和 %d、不写 %d（实写：%s）" % [int(3.0 + hull * 2.0), int(hull * 3.0), str(ev.get("text", "")).get_slice("\n", 1)])


func _s3_single(hull: float) -> void:
	print("── S3 单船：与改前同数")
	fleet.ships.clear()
	fleet.add_ship("sampan")
	var b := _dur()
	var ev: Dictionary = voyage.call("_shoal_event")
	var lost := _loss(b, _dur())
	_expect(is_equal_approx(float(lost[0]), hull) and str(ev.get("text", "")).ends_with("船体受损 %d。" % int(hull)),
		"小艍一艘擦一回减 %.0f、札记「船体受损 %d」（实减 %s）" % [hull, int(hull), str(lost)])


func _s4_armor(hull: float) -> void:
	print("── S4 甲三档：每艘按减伤吃")
	_fleet3()
	for s in fleet.ships:
		(s as Dictionary)["armor_level"] = 3
	var red: float = fleet.armor_damage_reduction()
	var b := _dur()
	voyage.call("_shoal_event")
	var lost := _loss(b, _dur())
	_expect(is_equal_approx(red, 0.8) and is_equal_approx(float(lost[0]), hull * red) and is_equal_approx(float(lost[1]), hull * red)
		and is_equal_approx(float(lost[2]), hull * red), "减伤 %.2f：三艘各减 %.1f（实减 %s）" % [red, hull * red, str(lost)])


func _s5_rolled(hull: float) -> void:
	print("── S5 傍岸逐日抽事抽到浅滩那一日")
	var hit := -1
	var lost: Array = []
	for s in range(1, 400):
		_fleet3()
		var b := _dur()
		seed(s)
		var ev: Dictionary = voyage.roll_day_event(30.0, "quanzhou", "fuzhou", COAST)
		if str(ev.get("title", "")) != "浅滩":
			continue
		hit = s
		lost = _loss(b, _dur())
		break
	_expect(hit > 0, "种子 1..399 里傍岸抽到浅滩（种子 %d）" % hit)
	if hit > 0:
		_expect(is_equal_approx(float(lost[0]), hull) and is_equal_approx(float(lost[1]), hull) and is_equal_approx(float(lost[2]), hull),
			"抽到浅滩那一日三艘各减 %.0f、旗舰不多吃（实减 %s）" % [hull, str(lost)])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_SHOAL cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
