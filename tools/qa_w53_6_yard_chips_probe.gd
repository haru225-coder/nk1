extends SceneTree
## lane w53-6：港内工席小钮「钮面 ↔ 实账」对账探针（headless、不截图、不开窗）。
## 起因（闸漏判）：船屋的修船 / 购入 / 换上 / 升帆 / 升甲 / 添人 / 补齐 / 水粮 / 赊 / 还，寺观的细看 / 拓碑，
## 必跑档里船屋只有 check_symbols / verify_economy 的源码排序判（连点闸 → 扣钱 → 上闸 → 过场 → 放闸）与 smoke 的钮面字样，
## 没有一道真按钮、看账动没动：修船回调删掉 Fleet.repair_all()（钱照扣、船不修）、水粮不入舱、添人添到旗舰、换上不写坞位、
## 赊了不记债，五处一并改坏一键全绿（lane w53-6 变异实测）。购入不 add_ship、拓碑不入边记、细看不记册已有 check_symbols /
## smoke 的源码判，这里按真钮再对一遍账。
## 本探针在真场景树上按页面里的真钮（Button.pressed，连钮到回调的线一起验），按钮面印的数对账：
##   船屋（泉州，第二章，两船：无名小艍半伤居坞 + 二号缺员带伤，钱三万、欠五百）：
##     Y1 修船 N：钱少 N，两船耐久都满；
##     Y2 水粮各 30 付 P：钱少 P，水、粮各多 30；
##     Y3 赊 500：钱多 500、欠多 500；Y4 还 P：钱少 P、欠少 P；
##     Y5 补齐 N 人 C：钱少 C，各船补到最低人手、全队多 N 人；
##     Y7 升帆 C / Y8 升甲 C：钱少 C，坞上那艘帆 / 甲升一等，别的船不动；
##     Y9 换上 二号：坞位换成二号（坞位卡题写二号），钱不动；
##     Y6 换坞后「二号　添 N 人」C：钱少 C，二号多 N 人，旗舰不动（坞上不是旗舰时才分得出添到哪艘）；
##     Y10 换坞后再升帆：升的是二号；
##     Y11 客舟 购入 P：钱少 P，船队多一条客舟，坞位不动（新船泊坞外、不自动占坞）；
##   寺观 / 住处（泉州）：
##     T1 细看一日：日子过一日，近侧旧迹多记一处，页上那处改「已入册」；
##     T2 拓碑一日：日子过一日，边记多一条「拓「…」」；T3 住处边记里翻得到这一条（寺观说的「回住处可翻」）。
## 回退即红（变异逐条实测）：删 repair_all → Y1；删 add_ship → Y11；水粮不入舱 → Y2；添人添到旗舰（hire_crew(…, 0)）→ Y6；
## 换上不写 berth_index → Y9 起；赊不记债（if GameState.borrow → if true）→ Y3；拓碑不入边记 → T2/T3；细看不记册 → T1。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_yard_chips_probe.gd
## 输出末行 QA_W53_6_YARD_CHIPS cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
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
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


func _run() -> void:
	print("QA_W53_6_YARD_CHIPS_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	var boot_fails: Array = []
	ShotGate.frame_pressure(self)
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", boot_fails, "W53-6 YardChips Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(boot_fails))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, boot_fails, "W53-6 YardChips Main"):
		_check(false, str(boot_fails))
		_finish()
		return

	_stage()
	await _yard()
	await _temple()
	_finish()


## 泉州第二章：无名小艍（小艍船）半伤居坞，二号（客舟）缺员五人、带伤；钱三万、欠五百
func _stage() -> void:
	gs.from_dict({})
	gs.chapter = 2
	gs.money = 30000
	gs.debt = 500
	gs.merchant_credit = 9
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 4, "day": 10})
	fleet.from_dict({"ships": [], "water": 60, "food": 60})
	fleet.add_ship("sampan", "无名小艍")
	fleet.add_ship("keel_boat", "二号")
	fleet.ships[0]["durability"] = 60.0
	fleet.ships[1]["durability"] = 200.0
	fleet.ships[1]["crew"] = 10
	gs.berth_index = 0
	gs.last_port = "quanzhou"


func _yard() -> void:
	await _open("quanzhou_shipyard")
	# Y1 修船
	var b := _chip("修船　")
	if _need(b, "Y1 船屋有「修船」钮"):
		var n := _num(b.text, 0)
		var m0: int = gs.money
		await _press(b)
		var full := true
		for s in fleet.ships:
			full = full and is_equal_approx(float(s["durability"]), float(s["max_durability"]))
		_check(gs.money == m0 - n and full, "Y1 修船　%d：钱 %d→%d（应少 %d），两船耐久 %s" % [n, m0, gs.money, n, _hulls()])
	# Y2 水粮
	b = _chip("水粮各 30")
	if _need(b, "Y2 船屋有「水粮各 30」钮"):
		var face := b.text
		var pay := _num(face, 1)
		var m0: int = gs.money
		var w0: int = fleet.water
		var f0: int = fleet.food
		await _press(b)
		_check(gs.money == m0 - pay and fleet.water == w0 + 30 and fleet.food == f0 + 30,
			"Y2 %s：钱少 %d（实 %d），水 %d→%d、粮 %d→%d（应各多 30）" % [face, pay, m0 - gs.money, w0, fleet.water, f0, fleet.food])
	# Y3 赊 500
	b = _chip("赊 500")
	if _need(b, "Y3 船屋有「赊 500」钮"):
		var m0: int = gs.money
		var d0: int = gs.debt
		await _press(b)
		_check(gs.money == m0 + 500 and gs.debt == d0 + 500, "Y3 赊 500：钱 %d→%d、欠 %d→%d（应各多 500）" % [m0, gs.money, d0, gs.debt])
	# Y4 还
	b = _chip("还 ")
	if _need(b, "Y4 船屋有「还」钮"):
		var pay := _num(b.text, 0)
		var m0: int = gs.money
		var d0: int = gs.debt
		await _press(b)
		_check(pay > 0 and gs.money == m0 - pay and gs.debt == d0 - pay, "Y4 还 %d：钱 %d→%d、欠 %d→%d（应各少 %d）" % [pay, m0, gs.money, d0, gs.debt, pay])
	# Y5 补齐
	b = _chip("补齐 ")
	if _need(b, "Y5 船屋有「补齐」钮（二号缺员）"):
		var n := _num(b.text, 0)
		var cost := _num(b.text, 1)
		var m0: int = gs.money
		var c0: int = fleet.total_crew()
		await _press(b)
		_check(gs.money == m0 - cost and fleet.total_crew() == c0 + n and fleet.crew_to_min_needed() == 0,
			"Y5 补齐 %d 人　%d：钱少 %d（实 %d），全队 %d→%d 人，缺员 %d" % [n, cost, cost, m0 - gs.money, c0, fleet.total_crew(), fleet.crew_to_min_needed()])
	# Y7 升帆 / Y8 升甲（坞上无名小艍）
	await _upgrade("Y7", "升帆　", "sail_level", 0)
	await _upgrade("Y8", "升甲　", "armor_level", 0)
	# Y9 换上二号
	b = _chip("换上　二号")
	if _need(b, "Y9 坞位卡有「换上　二号」钮"):
		var m0: int = gs.money
		await _press(b)
		var head := _find_label(_main.investigation_mode, "坞位　")
		_check(int(gs.berth_index) == 1 and head.contains("二号") and gs.money == m0,
			"Y9 换上二号：坞位 %d（应 1），坞位卡「%s」，钱 %d→%d（不花钱）" % [int(gs.berth_index), head, m0, gs.money])
	# Y6 换坞后添人：坞上是二号、不是旗舰
	b = _chip("二号　添 ")
	if _need(b, "Y6 换坞后坞位卡有「二号　添 N 人」钮"):
		var n := _num(b.text, 0)
		var cost := _num(b.text, 1)
		var m0: int = gs.money
		var a0 := int(fleet.ships[0]["crew"])
		var b0 := int(fleet.ships[1]["crew"])
		await _press(b)
		_check(gs.money == m0 - cost and int(fleet.ships[1]["crew"]) == b0 + n and int(fleet.ships[0]["crew"]) == a0,
			"Y6 二号　添 %d 人　%d：钱少 %d（实 %d），二号 %d→%d、无名小艍 %d→%d（只添坞上那艘）" % [n, cost, cost, m0 - gs.money, b0, int(fleet.ships[1]["crew"]), a0, int(fleet.ships[0]["crew"])])
	# Y10 换坞后再升帆：升的是二号
	await _upgrade("Y10", "升帆　", "sail_level", 1)
	# Y11 购入客舟：泊坞外、不占坞
	b = _chip("客舟　购入")
	if _need(b, "Y11 坞外待售有「客舟　购入」钮"):
		var price := _num(b.text, 0)
		var m0: int = gs.money
		var n0: int = fleet.ships.size()
		var berth0 := int(gs.berth_index)
		await _press(b)
		var last: Dictionary = fleet.ships[fleet.ships.size() - 1] if fleet.ships.size() > n0 else {}
		_check(gs.money == m0 - price and fleet.ships.size() == n0 + 1 and str(last.get("type", "")) == "keel_boat" and int(gs.berth_index) == berth0,
			"Y11 客舟　购入　%d：钱少 %d（实 %d），船 %d→%d 条（新船 %s），坞位 %d→%d（不自动占坞）" % [price, price, m0 - gs.money, n0, fleet.ships.size(), str(last.get("type", "无")), berth0, int(gs.berth_index)])


## 坞上那艘升一等：钱照钮面扣，只动 berth 那艘
func _upgrade(tag: String, prefix: String, key: String, berth: int) -> void:
	var b := _chip(prefix)
	if not _need(b, "%s 坞位卡有「%s」钮" % [tag, prefix.strip_edges()]):
		return
	var cost := _num(b.text, 0)
	var m0: int = gs.money
	var lv0: Array = []
	for s in fleet.ships:
		lv0.append(int(s.get(key, 1)))
	await _press(b)
	var ok: bool = gs.money == m0 - cost
	var lv1: Array = []
	for i in fleet.ships.size():
		var lv := int(fleet.ships[i].get(key, 1))
		lv1.append(lv)
		ok = ok and lv == int(lv0[i]) + (1 if i == berth else 0)
	_check(ok, "%s %s%d：钱少 %d（实 %d），各船 %s %s→%s（只升坞上第 %d 艘）" % [tag, prefix, cost, cost, m0 - gs.money, key, lv0, lv1, berth])


func _temple() -> void:
	await _open("quanzhou_temple")
	var near: Array = gm.discoveries_near("quanzhou")
	var found0 := _found_near(near)
	var d0: int = cal.absolute_day()
	var b := _chip("细看一日")
	if _need(b, "T1 泉州寺观有「细看一日」钮"):
		await _press(b)
		var found1 := _found_near(near)
		var newly: Array = found1.filter(func(x) -> bool: return not (x in found0))
		var name := ""
		for d in near:
			if newly.size() == 1 and str(d.get("id", "")) == str(newly[0]):
				name = str(d.get("name", ""))
		_check(cal.absolute_day() == d0 + 1 and newly.size() == 1 and _slip_aside(name) == "已入册",
			"T1 细看一日：日子 +%d（应 +1），新记 %s，页上「%s」%s" % [cal.absolute_day() - d0, newly, name, _slip_aside(name)])
	var notes0: int = gs.ledger_notes.size()
	d0 = cal.absolute_day()
	b = _chip("拓碑一日")
	var rub := ""
	if _need(b, "T2 已勘之处有「拓碑一日」钮"):
		await _press(b)
		for nt in gs.ledger_notes:
			if str(nt).begins_with("拓「"):
				rub = str(nt)
		_check(cal.absolute_day() == d0 + 1 and gs.ledger_notes.size() == notes0 + 1 and rub != "",
			"T2 拓碑一日：日子 +%d（应 +1），边记 %d→%d 条（拓记「%s」）" % [cal.absolute_day() - d0, notes0, gs.ledger_notes.size(), rub.left(16)])
	await _open("quanzhou_residence")
	var shown := _find_label(_main.investigation_mode, "拓「") if rub != "" else ""
	_check(rub != "" and shown == rub, "T3 住处边记翻得到拓记（%s）" % shown.left(16))


func _found_near(near: Array) -> Array:
	var out: Array = []
	for d in near:
		if bool(gs.has_found(str(d.get("id", "")))):
			out.append(str(d.get("id", "")))
	return out


## 寺观工席上某处旧迹标题旁的那行字（未勘 / 已入册 / 已呈案）
func _slip_aside(name: String) -> String:
	if name == "":
		return ""
	var labels: Array = []
	_labels(_main.investigation_mode, labels)
	for i in labels.size() - 1:
		if str(labels[i]) == name:
			return str(labels[i + 1])
	return ""


func _labels(n: Node, out: Array) -> void:
	if n.is_queued_for_deletion():
		return
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		_labels(c, out)


func _open(scene_id: String) -> void:
	_main.load_scene(scene_id)
	await _settle(4)


## 按页上那颗真钮；回调里的过场（headless 当帧落黑）重开本页，等排版稳
func _press(b: Button) -> void:
	b.pressed.emit()
	await _settle(4)


## 页上可按的、字样以 prefix 起头的第一颗钮
func _chip(prefix: String) -> Button:
	return _find_button(_main.investigation_mode, prefix)


func _find_button(n: Node, prefix: String) -> Button:
	if n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
		if (n as Button).text.begins_with(prefix):
			return n
	for c in n.get_children():
		var hit := _find_button(c, prefix)
		if hit != null:
			return hit
	return null


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


## 钮面上第 idx 个整数（「修船　144」→ 144；「补齐 5 人　100」idx 1 → 100）
func _num(text: String, idx: int) -> int:
	var re := RegEx.new()
	re.compile("\\d+")
	var all := re.search_all(text)
	return int(all[idx].get_string()) if idx < all.size() else -1


func _hulls() -> String:
	var out: Array = []
	for s in fleet.ships:
		out.append("%s %d/%d" % [s.get("name", ""), int(s["durability"]), int(s["max_durability"])])
	return ", ".join(out)


func _need(b: Button, what: String) -> bool:
	if b == null:
		_check(false, what)
		return false
	return true


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
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("QA_W53_6_YARD_CHIPS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
