extends SceneTree
## lane w54-port：牙行「装至」选的那艘船，接委办 / 交货 / 毁约之后还是那艘——回归探针（headless、不截图、不开窗）。
## 病：多船时牙行页上「装至」一排小钮选买进装哪艘（Main._market_ship）。头注写明「进牙行时重置为旗舰；同页换船或买卖后
## 刷新时保留」：买 / 卖 / 换船 / 明日再看四支回调重排页面前都记 _market_hold = true。委办单上的「接下委办」「交货」
## 「毁约」三支（_on_accept_contract / _on_deliver_contract / _on_abandon_contract）同在这一页、同样整页重排，却没记这一笔：
## 选着二号船按「接下委办」，页面一重排就跳回旗舰，紧接着按「买 10」，货进了旗舰——装货的船一声不响换了。
## 修后三支与买卖同一写法，重排前记 _market_hold，选着的船留着。
## 断言（泉州牙行，两艘客舟，岸上走真门进牙行，钮都按页上的真钮）：
##   一、「装至」点二号，按「接下委办」：委办接下了、选着的仍是二号；再按第一张货单「买 1」，货进二号、旗舰不动；
##   二、在身委办交货地就是泉州（舱里有委办货），选二号，按「交货」：交了、仍是二号，「买 1」进二号；
##   三、在身委办（交货地在别港），选二号，按「毁约　扣 N」：委办作废、仍是二号，「买 1」进二号；
##   四、对照：离开回港再从岸上牙行门进来，回到旗舰（「进牙行时重置为旗舰」照旧）；
##   五、对照：选二号按「明日再看」，仍是二号（原就留着）。
## 回退即红：三支回调里去掉记 _market_hold 的那一笔 → 一、二、三红（四、五照绿）。
## 用法：godot --headless --path . -s res://tools/qa_w54_port_ship_pick_probe.gd（经门锁跑）
## 输出末行 QA_W54_PORT_SHIP_PICK cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORT := "quanzhou"

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

	print("── 一、选二号按「接下委办」")
	_stage({})
	var offer: Dictionary = gs.contract_offer(PORT)
	_check(not offer.is_empty(), "摆场前提：泉州本月有外埠委办（%s）" % ("有" if not offer.is_empty() else "无"))
	await _enter_by_door()
	await _pick_ship(1)
	var take := _find_button(_panel(), "接下委办")
	var has_take := take != null
	if has_take:
		take.pressed.emit()
		await _settle(2)
	await _after("一", "接下委办", has_take and not gs.contract.is_empty())

	print("── 二、在身委办交货地是泉州，选二号按「交货」")
	var due_good := _pick_good_on_counter()
	_stage({"good_id": due_good, "qty": 12, "remaining": 12, "dest": PORT, "from": "fuzhou", "purse": 900,
		"unit_purse": 75.0, "paid": 0, "due_day": 0, "deadline_days": 10, "voyage_days": 7, "offer_month": 0})
	gs.contract["due_day"] = int(cal.absolute_day()) + 5
	gs.contract["offer_month"] = int(cal.year) * 12 + int(cal.month)
	fleet.add_cargo(due_good, 5, 20.0, 0)
	await _enter_by_door()
	await _pick_ship(1)
	var give := _find_button(_panel(), "交货")
	var has_give := give != null and not give.disabled
	var rem0 := int(gs.contract.get("remaining", 0))
	if has_give:
		give.pressed.emit()
		await _settle(2)
	await _after("二", "交货", has_give and int(gs.contract.get("remaining", 0)) == rem0 - 5)

	print("── 三、在身委办交货地在别港，选二号按「毁约」")
	_stage({"good_id": due_good, "qty": 12, "remaining": 12, "dest": "fuzhou", "from": PORT, "purse": 900,
		"unit_purse": 75.0, "paid": 0, "due_day": 0, "deadline_days": 10, "voyage_days": 7, "offer_month": 0})
	gs.contract["due_day"] = int(cal.absolute_day()) + 5
	gs.contract["offer_month"] = int(cal.year) * 12 + int(cal.month)
	await _enter_by_door()
	await _pick_ship(1)
	var drop := _find_prefix(_panel(), "毁约")
	var has_drop := drop != null
	if has_drop:
		drop.pressed.emit()
		await _settle(2)
	await _after("三", "毁约", has_drop and gs.contract.is_empty())

	print("── 四、对照：离开回港再从岸门进来，回到旗舰")
	_stage({})
	await _enter_by_door()
	await _pick_ship(1)
	var leave := _find_button(_main.get("investigation_mode"), "离开")
	if leave != null:
		leave.pressed.emit()
		await _settle(3)
	var back := await _enter_by_door()
	_check(back and int(_main.get("_market_ship")) == 0, "四：选二号后离开回港、岸门再进，选着的是 %s（应回旗舰）" % _ship_name(int(_main.get("_market_ship"))))

	print("── 五、对照：选二号按「明日再看」，仍是二号")
	_stage({})
	await _enter_by_door()
	await _pick_ship(1)
	var wait := _find_button(_main.get("investigation_mode"), "明日再看")
	var has_wait := wait != null
	if has_wait:
		wait.pressed.emit()
		await _settle(2)
	_check(has_wait and int(_main.get("_market_ship")) == 1, "五：选二号按「明日再看」，选着的是 %s（应仍是二号）" % _ship_name(int(_main.get("_market_ship"))))

	eco.rates = _rates0.duplicate(true)
	_finish()


## 泉州第一章，景定三年五月初一；两艘客舟（旗舰、二号）、钱三万、水粮足；contract 为在身委办（空 = 无）
func _stage(contract: Dictionary) -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	fleet.add_ship("keel_boat", "二号")
	gs.contract = contract.duplicate(true)
	gs.broker_salt = 0
	gs.shore_salt = 0
	gs.last_port = PORT


## 今日柜上头一样（交货那一案的委办货：上了柜才凑得齐，交货不看柜，这里只为摆一样泉州有的货）
func _pick_good_on_counter() -> String:
	for raw in eco.goods_at(PORT):
		var g: Dictionary = gm.get_good_by_id(str(raw))
		if bool(g.get("tradable", false)) and not bool(g.get("contraband", false)):
			return str(raw)
	return ""


## 回港页，再走岸上「牙行」那扇门（真门钮）进牙行；没进成返回 false
func _enter_by_door() -> bool:
	_main.load_scene(PORT)
	await _settle(3)
	var door := _door_button("牙行")
	if door == null:
		return false
	door.pressed.emit()
	await _settle(3)
	return str(_main.get("current_scene_id")) == PORT + "_market"


## 按「装至」一排里第 idx 艘的小钮（钮面「船名　空 N」）
func _pick_ship(idx: int) -> void:
	var want := str(fleet.display_name(idx)) + "　空 "
	var chip := _find_prefix(_main.get("choices_container"), want)
	if chip != null:
		chip.pressed.emit()
		await _settle(2)


## 按过委办单上那枚钮之后：选着的船、再按第一张货单「买 1」货进哪艘
func _after(tag: String, what: String, acted: bool) -> void:
	var pick := int(_main.get("_market_ship"))
	var hand: PackedStringArray = PackedStringArray(_main.get("broker_hand"))
	var gid := hand[0] if hand.size() > 0 else ""
	var q0: int = fleet.cargo_qty(gid, 0) if gid != "" else 0
	var q1: int = fleet.cargo_qty(gid, 1) if gid != "" else 0
	var buy := _card_button(0, "买 1")
	var has_buy := buy != null
	if has_buy:
		buy.pressed.emit()
		await _settle(2)
	var d0: int = (fleet.cargo_qty(gid, 0) if gid != "" else 0) - q0
	var d1: int = (fleet.cargo_qty(gid, 1) if gid != "" else 0) - q1
	_check(acted and pick == 1 and has_buy and d1 == 1 and d0 == 0,
		"%s：选二号按「%s」（%s），选着的是 %s（应仍是二号）；再按「买 1」%s：二号 %+d、旗舰 %+d（应二号 +1、旗舰不动）" % [
			tag, what, "按成了" if acted else "没按成", _ship_name(pick), gm.get_good_name(gid), d1, d0])


func _ship_name(i: int) -> String:
	return str(fleet.display_name(i)) if i >= 0 and i < fleet.ships.size() else "（越界 %d）" % i


func _panel() -> Node:
	return _main.get("choices_container").get_node_or_null("ContractPanel")


## 柜上第 i 张货单的钮
func _card_button(i: int, text: String) -> Button:
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	if slips == null:
		return null
	var live: Array = []
	for c in slips.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	return _find_button(live[i], text) if i >= 0 and i < live.size() else null


## 岸上开着的那扇门（ShoreDoors 门卡题字为 title）的热区钮
func _door_button(title: String) -> Button:
	var band: Node = _main.call("_shore_band")
	var doors: Node = band.get_node_or_null("ShoreDoors") if band != null else null
	if doors == null:
		return null
	for card in doors.get_children():
		if card.is_queued_for_deletion() or not _has_label(card, title):
			continue
		for c in card.get_children():
			if c is Button:
				return c as Button
	return null


func _has_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _has_label(c, text):
			return true
	return false


func _find_button(n: Node, text: String) -> Button:
	if n == null or n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _find_prefix(n: Node, prefix: String) -> Button:
	if n == null or n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and not (n as Button).disabled and (n as Button).text.begins_with(prefix):
		return n as Button
	for c in n.get_children():
		var hit := _find_prefix(c, prefix)
		if hit != null:
			return hit
	return null


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
	print("QA_W54_PORT_SHIP_PICK cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
