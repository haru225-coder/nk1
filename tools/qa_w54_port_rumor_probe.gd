extends SceneTree
## lane w54-port：牙行货单上的别港传闻不荐牙行闭门的港——回归探针（headless、不截图、不开窗）。
## 病：货单第二行写别港传闻（GameState.rumor_elsewhere，lane w53-3）：传闻簿里取约卖最高的一港，只滤过期（45 日）。
## 可传闻是海上随手听来的（Voyage._pick_rumor 从已解锁各港里挑，不看战况）、也可能是记下之后那港才围城 / 封港：
## 文永之役后博多唐房封港（1274-10 起）、福州 1276-10 被围、广州 1276-11 被围，那港牙行上了门闸、船也进不去，
## 泉州货单上照写「传闻博多唐房约卖 N・3 日前」，而且因为那港价最高，把一条卖得掉的别港传闻顶了下去。
## 行会抄本 / 酒馆打听早已不荐闭门港（Main._collect_spreads，lane w53-6），货单这一行没跟上。
## 修后：那港牙行眼下上了门闸（Economy.is_market_open 为假）的传闻不取，取下一家开着的；都闭着就写原提示。
## 断言（泉州牙行，舱里装生丝让它占第一席；传闻都是三五日前记下的、没过期）：
##   一、1274-11 博多唐房封港：簿上博多（行情 2.0）与福州（1.3）两条——货单写福州那条「传闻福州约卖 N・5 日前」，
##       N = Economy.price_at_rate(福州, 生丝, 1.3, 卖)；悬停里有福州那条、没有博多；
##   二、1274-11 簿上只有博多一条：货单写原提示（不写「传闻」），悬停空；
##   三、对照 1274-09 博多还开着：同样两条，货单写博多那条（博多价高，修后照取）；
##   四、1276-10 福州被围、广州开着：簿上福州（2.0）与广州（1.0）——货单写广州；1276-11 福州降元开市、广州被围——货单写福州；
##   五、GameState.rumor_elsewhere 直调与货单那一行一字不差（各案都比）。
## 回退即红：rumor_elsewhere 循环里去掉「not Economy.is_market_open(pid)」→ 一、二、四红（三照绿）。
## 用法：godot --headless --path . -s res://tools/qa_w54_port_rumor_probe.gd（经门锁跑）
## 输出末行 QA_W54_PORT_RUMOR cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORT := "quanzhou"
const GOOD := "raw_silk"

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _finish() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_check(false, "Main.gd 未载入")
		_finish()
		return
	_rates0 = eco.rates.duplicate(true)
	cal.from_dict({"year": 1274, "month": 11, "day": 10})
	_check(eco.war_status("hakata") == "closed" and not eco.is_market_open("hakata") and eco.is_market_open(PORT),
		"摆场前提：1274-11 博多唐房封港（%s）、牙行闭门，泉州开着" % eco.war_status("hakata"))

	print("── 一、博多封港：两条传闻里取开着的福州")
	_stage(1274, 11)
	_rumor("hakata", 2.0, 3)
	_rumor("fuzhou", 1.3, 5)
	await _case("一", "传闻%s约卖 %d・5 日前" % [gm.get_port_name("fuzhou"), eco.price_at_rate("fuzhou", GOOD, 1.3, false)], "fuzhou", "hakata")

	print("── 二、簿上只有封港的博多：写原提示")
	_stage(1274, 11)
	_rumor("hakata", 2.0, 3)
	await _case("二", "", "", "hakata")

	print("── 三、对照：1274-09 博多开着，照取价高的博多")
	_stage(1274, 9)
	_rumor("hakata", 2.0, 3)
	_rumor("fuzhou", 1.3, 5)
	await _case("三", "传闻%s约卖 %d・3 日前" % [gm.get_port_name("hakata"), eco.price_at_rate("hakata", GOOD, 2.0, false)], "hakata", "")

	print("── 四、福州被围取广州；福州降元开市、广州被围取福州")
	_stage(1276, 10)
	_rumor("fuzhou", 2.0, 3)
	_rumor("guangzhou", 1.0, 4)
	await _case("四・1276-10", "传闻%s约卖 %d・4 日前" % [gm.get_port_name("guangzhou"), eco.price_at_rate("guangzhou", GOOD, 1.0, false)], "guangzhou", "fuzhou")
	_stage(1276, 11)
	_rumor("fuzhou", 2.0, 3)
	_rumor("guangzhou", 3.0, 4)
	await _case("四・1276-11", "传闻%s约卖 %d・3 日前" % [gm.get_port_name("fuzhou"), eco.price_at_rate("fuzhou", GOOD, 2.0, false)], "fuzhou", "guangzhou")

	eco.rates = _rates0.duplicate(true)
	_finish()


## 泉州 y 年 m 月初十，第四章（各港都解锁），一艘客舟、舱里生丝 20 件（占柜上第一席）；传闻簿清空
func _stage(y: int, m: int) -> void:
	gs.from_dict({})
	gs.chapter = 4
	gs.money = 5000
	gs.identity = "merchant"
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": y, "month": m, "day": 10})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 200, "food": 200})
	fleet.add_ship("keel_boat", "旗舰")
	fleet.add_cargo(GOOD, 20, 30.0, 0)
	gs.rumors = {}
	gs.broker_salt = 0
	gs.last_port = PORT


## 记一条 days_ago 日前的生丝传闻
func _rumor(pid: String, rate: float, days_ago: int) -> void:
	gs.note_rumor(pid, GOOD, rate)
	gs.rumors[pid][GOOD]["day"] = int(cal.absolute_day()) - days_ago


## 进泉州牙行，读生丝那张货单的第二行与悬停；want 为空 = 应写原提示（不写传闻）
func _case(tag: String, want: String, tip_has: String, tip_not: String) -> void:
	_main.set("_market_ship", 0)
	_main.set("_market_hold", false)
	_main.load_scene(PORT + "_market")
	await _settle(2)
	var hand: PackedStringArray = PackedStringArray(_main.get("broker_hand"))
	var i := hand.find(GOOD)
	var line := ""
	var tip := ""
	var card := _card(i)
	if card != null:
		var labels: Array = []
		_labels(card, labels)
		if labels.size() >= 2:
			line = (labels[1] as Label).text
			tip = (labels[1] as Label).tooltip_text
	var direct := str(gs.rumor_elsewhere(PORT, GOOD))
	var hint := str(eco.price_hint(PORT, GOOD))
	var expect := want if want != "" else (hint if hint != "" else "寻常")
	var tip_ok := (tip == "") if want == "" else (tip.contains(gm.get_port_name(tip_has)) and (tip_not == "" or not tip.contains(gm.get_port_name(tip_not))))
	_check(i >= 0 and line == expect and direct == want and tip_ok,
		"%s：生丝货单第二行「%s」（应「%s」），rumor_elsewhere「%s」，悬停「%s」%s" % [
			tag, line, expect, direct, tip.replace("\n", " / "),
			"" if want == "" else "（应有%s%s）" % [gm.get_port_name(tip_has), "" if tip_not == "" else "、无" + gm.get_port_name(tip_not)]])


## 柜上第 i 张货单
func _card(i: int) -> Node:
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	if slips == null or i < 0:
		return null
	var live: Array = []
	for c in slips.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	return live[i] if i < live.size() else null


func _labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels(c, out)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _finish() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("QA_W54_PORT_RUMOR cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
