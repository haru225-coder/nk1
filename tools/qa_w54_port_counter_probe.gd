extends SceneTree
## lane w54-port：牙行「今日柜上三样」同一日里不换手——回归探针（headless、不截图、不开窗）。
## 病：Main._setup_market 每次进页都按眼下的舱货与现价重发柜上三样（BrokerSlip.deal：舱里件数最多那样占第一席、其余按买价排）。
## 牙行页每按一次买 / 卖都整页重排，买进的那样在舱里一多就抢到第一席、价一涨也换次序：按第三张货单的「买 1」，重排后
## 那样货跑到第一张，原位上换成另一样（连点同一处「买 1」买到别的货）；卖光第一席那样，柜上当场又换一手；出门再进也重发。
## 修前实测（泉州等七港 × 盐位 0–7 × 三席 × 买 1 / 买 10 / 买满 / 买后出门再进）672 回里 644 回柜上换了样或换了次序，
## 卖光第一席 40 回 40 回换手。修后按「港・日・盐位」记下当日头一回发出的那一手（Main._broker_today），「明日再看」、隔日、
## 另起一局才重发。
## 断言（泉州，景定三年五月初一，一艘客舟、钱三万；岸上进牙行走真门、买卖走货单上的真钮）：
##   一、空舱进牙行，盐位 0–7 每一位：三席逐席按「买 1」，按后柜上与按前一字不差、三张货单还是原来的货原来的位置，买进的是按下那张；
##   二、连点同一处：盐位 0–7，第三张货单按「买 1」，重排后再按第三张货单的「买 1」——两回买进的都是同一样（那样 +2、别的不动）；
##   三、卖光第一席：舱里两样（件数多的占第一席），按第一张货单「全卖」——柜上一字不差，那张货单还在、写「舱 0」、三枚卖钮发灰，
##       钱多出 = 按前 Economy.estimate_sell_revenue；
##   四、出门再进（同一日）：第三张货单「买 10」，页脚「离开」回港，岸上「牙行」门再进——柜上与头一回一字不差；
##       再进一处不过日子的去处（行会）回港、又进牙行，还是这一手；
##   五、「明日再看」：盐位 +1、日子 +1，柜上按眼下舱货现发（= BrokerSlip.deal 现算），不留昨日那一手；
##   六、岸上「再候一日」过了一日再进：柜上按眼下舱货现发（买进那样占第一席），不留昨日那一手；
##   七、另起一局（Fleet.from_dict 换上另一副船队，同港同日同盐位、舱货不同）：柜上按新局现发，不沿用上一局那一手。
## 回退即红：_setup_market 里 broker_hand 改回直接取 BrokerSlip.deal（去掉 _broker_today）→ 一、二、三、四红；
## _broker_today 的键去掉日子 → 六红；去掉 Fleet.ships 同一副的判 → 七红。
## 用法：godot --headless --path . -s res://tools/qa_w54_port_counter_probe.gd（经门锁跑）
## 输出末行 QA_W54_PORT_COUNTER cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const BrokerSlipScript := preload("res://scripts/core/BrokerSlip.gd")

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
	print("── 一、空舱进牙行，三席逐席按「买 1」：柜上不换、货单不挪位")
	await _sec_buy_each_seat()
	print("── 二、连点同一处：第三张货单「买 1」按两回，两回买进同一样")
	await _sec_repeat_click()
	print("── 三、卖光第一席：柜上不换，那张货单写「舱 0」、卖钮发灰")
	await _sec_sell_out()
	print("── 四、出门再进（同一日）：还是这一手")
	await _sec_leave_and_back()
	print("── 五、「明日再看」：盐位 +1、过一日，柜上现发")
	await _sec_wait_tomorrow()
	print("── 六、岸上「再候一日」再进：柜上现发")
	await _sec_shore_wait()
	print("── 七、另起一局（换船队）同港同日同盐位：按新局现发")
	await _sec_new_game()
	eco.rates = _rates0.duplicate(true)
	_finish()


## 泉州第一章，景定三年五月初一；一艘客舟、钱三万、水粮足；cargo {货: 件数} 装旗舰。节拍全记过、不在港页演戏
func _stage(salt: int, cargo: Dictionary = {}) -> void:
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
	for gid in cargo.keys():
		fleet.add_cargo(str(gid), int(cargo[gid]), 10.0, 0)
	gs.broker_salt = salt
	gs.shore_salt = 0
	gs.last_port = PORT


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


func _hand() -> PackedStringArray:
	return PackedStringArray(_main.get("broker_hand"))


## 柜上第 i 张货单
func _card(i: int) -> Node:
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	if slips == null:
		return null
	var live: Array = []
	for c in slips.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	return live[i] if i >= 0 and i < live.size() else null


## 三张货单上的货名（每张卡头一枚 Label 是货名）
func _card_names() -> PackedStringArray:
	var out := PackedStringArray()
	for i in 3:
		var card := _card(i)
		if card == null:
			break
		var lbl := _first_label(card)
		out.append(lbl.text if lbl != null else "")
	return out


func _names_of(hand: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for gid in hand:
		out.append(str(gm.get_good_name(gid)))
	return out


func _card_button(i: int, text: String) -> Button:
	var card := _card(i)
	return _find_button(card, text) if card != null else null


func _card_text(i: int, prefix: String) -> String:
	var card := _card(i)
	if card == null:
		return ""
	var lbl := _find_label_prefix(card, prefix)
	return lbl.text if lbl != null else ""


## 按眼下的舱货、行情、盐位现发一手（与 Main._setup_market 同一份货单写法）
func _fresh_deal() -> PackedStringArray:
	var catalog: Array = []
	for raw_gid in eco.goods_at(PORT):
		var gid := str(raw_gid)
		catalog.append({"id": gid, "role": str(eco.get_role(PORT, gid)), "buy": eco.buy_price(PORT, gid)})
	return BrokerSlipScript.deal(catalog, int(gs.broker_salt), str(_main.call("_broker_held_id", PORT)))


func _sec_buy_each_seat() -> void:
	for salt in 8:
		_stage(salt)
		var entered := await _enter_by_door()
		var h0 := _hand()
		var names0 := _card_names()
		var bad := PackedStringArray()
		if not entered or h0.size() != 3 or names0 != _names_of(h0):
			bad.append("进页：%s 柜上 [%s] 货单 [%s]" % ["进了" if entered else "没进成", ", ".join(h0), ", ".join(names0)])
		else:
			for seat in 3:
				var gid := h0[seat]
				var q0: int = fleet.cargo_qty(gid)
				var b := _card_button(seat, "买 1")
				if b == null:
					bad.append("第%d张没有「买 1」" % (seat + 1))
					continue
				b.pressed.emit()
				await _settle(2)
				var h1 := _hand()
				var names1 := _card_names()
				if h1 != h0 or names1 != names0 or fleet.cargo_qty(gid) != q0 + 1:
					bad.append("按第%d张（%s）「买 1」后柜上 [%s] → [%s]、货单 [%s]、%s %d → %d" % [
						seat + 1, gm.get_good_name(gid), ", ".join(h0), ", ".join(h1), ", ".join(names1),
						gm.get_good_name(gid), q0, fleet.cargo_qty(gid)])
		_check(bad.is_empty(), "盐位 %d：三席逐席「买 1」，柜上 [%s] 不换、货单不挪位%s" % [
			salt, ", ".join(_names_of(h0)), "" if bad.is_empty() else "（%s）" % "；".join(bad)])


func _sec_repeat_click() -> void:
	for salt in 8:
		_stage(salt)
		var entered := await _enter_by_door()
		var h0 := _hand()
		if not entered or h0.size() != 3:
			_check(false, "盐位 %d：进牙行柜上三样（%s，柜上 [%s]）" % [salt, "进了" if entered else "没进成", ", ".join(h0)])
			continue
		var before := {}
		for raw in eco.goods_at(PORT):
			before[str(raw)] = int(fleet.cargo_qty(str(raw)))
		var got := PackedStringArray()
		for k in 2:
			var b := _card_button(2, "买 1")
			if b == null:
				got.append("（无钮）")
				continue
			var snap := {}
			for raw in eco.goods_at(PORT):
				snap[str(raw)] = int(fleet.cargo_qty(str(raw)))
			b.pressed.emit()
			await _settle(2)
			for gid in snap.keys():
				if int(fleet.cargo_qty(gid)) > int(snap[gid]):
					got.append(str(gm.get_good_name(gid)))
		var moved := PackedStringArray()
		for gid in before.keys():
			var d: int = int(fleet.cargo_qty(gid)) - int(before[gid])
			if (gid == h0[2] and d != 2) or (gid != h0[2] and d != 0):
				moved.append("%s %+d" % [gm.get_good_name(gid), d])
		var want := str(gm.get_good_name(h0[2]))
		_check(got.size() == 2 and got[0] == want and got[1] == want and moved.is_empty(),
			"盐位 %d：第三张货单（%s）「买 1」连按两回，买进 [%s]（应两回都是 %s）%s" % [
				salt, want, ", ".join(got), want, "" if moved.is_empty() else "，舱货出入不对：%s" % "、".join(moved)])


func _sec_sell_out() -> void:
	var goods: Array = eco.goods_at(PORT)
	for salt in [0, 3, 6]:
		# 件数多的那样占第一席；另一样件数少、今日不在柜上
		var a := str(goods[0])
		var b := str(goods[1])
		_stage(salt, {a: 20, b: 5})
		var entered := await _enter_by_door()
		var h0 := _hand()
		if not entered or h0.size() != 3 or h0[0] != a:
			_check(false, "盐位 %d：舱里 %s 20、%s 5，进牙行 %s 占第一席（%s，柜上 [%s]）" % [
				salt, gm.get_good_name(a), gm.get_good_name(b), gm.get_good_name(a), "进了" if entered else "没进成", ", ".join(_names_of(h0))])
			continue
		var all_btn := _card_button(0, "全卖")
		var has_btn := all_btn != null
		var m0: int = gs.money
		var want: int = eco.estimate_sell_revenue(PORT, a, 20)
		if has_btn:
			all_btn.pressed.emit()
			await _settle(2)
		var h1 := _hand()
		var held := _card_text(0, "舱 ")
		var lit := PackedStringArray()
		for t in ["卖 1", "卖 10", "全卖"]:
			var s := _card_button(0, t)
			if s == null or not s.disabled:
				lit.append(t)
		_check(has_btn and h1 == h0 and _card_names() == _names_of(h0) and held == "舱 0" and lit.is_empty()
				and int(gs.money) - m0 == want and fleet.cargo_qty(a) == 0,
			"盐位 %d：第一张货单（%s）「全卖」后柜上 [%s] → [%s]，那张货单「%s」（应「舱 0」）、卖钮没发灰的：%s，得钱 %d（应 %d）" % [
				salt, gm.get_good_name(a), ", ".join(_names_of(h0)), ", ".join(_names_of(h1)), held,
				"无" if lit.is_empty() else "、".join(lit), int(gs.money) - m0, want])


func _sec_leave_and_back() -> void:
	for salt in [0, 2, 5]:
		_stage(salt)
		var entered := await _enter_by_door()
		var h0 := _hand()
		if not entered or h0.size() != 3:
			_check(false, "盐位 %d：进牙行柜上三样（%s，柜上 [%s]）" % [salt, "进了" if entered else "没进成", ", ".join(h0)])
			continue
		var day0: int = cal.absolute_day()
		# 钮按下后整页重排、随旧页释放（Godot 4 里释放了的对象与 null 比较为真），有没有这枚钮在按之前记下
		var b := _card_button(2, "买 10")
		var has_b := b != null
		if has_b:
			b.pressed.emit()
			await _settle(2)
		var leave := _find_button(_main.get("investigation_mode"), "离开")
		var left := false
		if leave != null:
			leave.pressed.emit()
			await _settle(3)
			left = str(_main.get("current_scene_id")) == PORT
		var door := _door_button("牙行")
		var back := false
		if door != null:
			door.pressed.emit()
			await _settle(3)
			back = str(_main.get("current_scene_id")) == PORT + "_market"
		var h1 := _hand()
		_check(has_b and left and back and cal.absolute_day() == day0 and h1 == h0 and _card_names() == _names_of(h0),
			"盐位 %d：第三张货单「买 10」、离开回港（%s）、岸上牙行门再进（%s）：柜上 [%s] → [%s]（同一日应不换）" % [
				salt, "回了" if left else "没回成", "进了" if back else "没进成", ", ".join(_names_of(h0)), ", ".join(_names_of(h1))])
		# 再进一处不过日子的去处（行会）回港、又进牙行
		var via := ""
		_main.load_scene(PORT)
		await _settle(3)
		for t in ["行会", "船屋", "酒馆", "旅店", "贡院", "住处", "住宅", "寺观", "市舶司"]:
			var d := _door_button(t)
			if d != null:
				via = t
				d.pressed.emit()
				await _settle(3)
				break
		var leave2 := _find_button(_main.get("investigation_mode"), "离开")
		if leave2 != null:
			leave2.pressed.emit()
			await _settle(3)
		var door2 := _door_button("牙行")
		if door2 != null:
			door2.pressed.emit()
			await _settle(3)
		var h2 := _hand()
		_check(via != "" and str(_main.get("current_scene_id")) == PORT + "_market" and cal.absolute_day() == day0 and h2 == h0,
			"盐位 %d：再进「%s」回港、又进牙行：柜上 [%s]（应仍是 [%s]）" % [salt, via, ", ".join(_names_of(h2)), ", ".join(_names_of(h0))])


func _sec_wait_tomorrow() -> void:
	for salt in [0, 4]:
		_stage(salt)
		var entered := await _enter_by_door()
		var h0 := _hand()
		var b := _card_button(2, "买 10")
		if not entered or b == null:
			_check(false, "盐位 %d：进牙行、第三张货单有「买 10」（%s）" % [salt, "进了" if entered else "没进成"])
			continue
		b.pressed.emit()
		await _settle(2)
		var day0: int = cal.absolute_day()
		var wait := _find_button(_main.get("investigation_mode"), "明日再看")
		var has_wait := wait != null
		if has_wait:
			wait.pressed.emit()
			await _settle(2)
		var h1 := _hand()
		var fresh := _fresh_deal()
		_check(has_wait and int(gs.broker_salt) == salt + 1 and cal.absolute_day() == day0 + 1 and h1 == fresh and h1 != h0,
			"盐位 %d：买进第三席后「明日再看」——盐位 %d、日子 +%d，柜上 [%s]（现发应 [%s]，不留昨日 [%s]）" % [
				salt, int(gs.broker_salt), cal.absolute_day() - day0, ", ".join(_names_of(h1)), ", ".join(_names_of(fresh)), ", ".join(_names_of(h0))])


func _sec_shore_wait() -> void:
	for salt in [1, 5]:
		_stage(salt)
		var entered := await _enter_by_door()
		var h0 := _hand()
		var b := _card_button(2, "买 10")
		if not entered or b == null:
			_check(false, "盐位 %d：进牙行、第三张货单有「买 10」（%s）" % [salt, "进了" if entered else "没进成"])
			continue
		b.pressed.emit()
		await _settle(2)
		var day0: int = cal.absolute_day()
		_main.load_scene(PORT)
		await _settle(3)
		var wait := _find_button(_main.get("port_mode"), "再候一日")
		var has_wait := wait != null
		if has_wait:
			wait.pressed.emit()
			await _settle(3)
		var door := _door_button("牙行")
		var has_door := door != null
		if has_door:
			door.pressed.emit()
			await _settle(3)
		var h1 := _hand()
		var fresh := _fresh_deal()
		_check(has_wait and has_door and cal.absolute_day() == day0 + 1 and int(gs.broker_salt) == salt and h1 == fresh and h1 != h0,
			"盐位 %d：买进第三席、岸上再候一日（日子 +%d）再进牙行：柜上 [%s]（现发应 [%s]，不留昨日 [%s]）" % [
				salt, cal.absolute_day() - day0, ", ".join(_names_of(h1)), ", ".join(_names_of(fresh)), ", ".join(_names_of(h0))])


func _sec_new_game() -> void:
	_stage(0)
	var entered := await _enter_by_door()
	var h0 := _hand()
	# 新局舱里装一样上一局柜上没有的货：现发时它占第一席，与上一局那一手分得开
	var other := ""
	for raw in eco.goods_at(PORT):
		if not (str(raw) in h0):
			other = str(raw)
			break
	_stage(0, {other: 30} if other != "" else {})
	var back := await _enter_by_door()
	var h1 := _hand()
	var fresh := _fresh_deal()
	_check(entered and back and other != "" and h1 == fresh and h1.size() > 0 and h1[0] == other and h1 != h0,
		"另起一局（换船队、舱里 %s 30），同港同日同盐位进牙行：柜上 [%s]（现发应 [%s]，%s 占第一席；不沿用上一局 [%s]）" % [
			gm.get_good_name(other), ", ".join(_names_of(h1)), ", ".join(_names_of(fresh)), gm.get_good_name(other), ", ".join(_names_of(h0))])


## 岸上开着的那扇门（ShoreDoors 门卡题字为 title）的热区钮
func _door_button(title: String) -> Button:
	var band: Node = _main.call("_shore_band")
	var doors: Node = band.get_node_or_null("ShoreDoors") if band != null else null
	if doors == null:
		return null
	for card in doors.get_children():
		if card.is_queued_for_deletion():
			continue
		var lbl := _first_label_text(card, title)
		if lbl == null:
			continue
		for c in card.get_children():
			if c is Button:
				return c as Button
	return null


func _first_label(n: Node) -> Label:
	if n.is_queued_for_deletion():
		return null
	if n is Label:
		return n as Label
	for c in n.get_children():
		var hit := _first_label(c)
		if hit != null:
			return hit
	return null


func _first_label_text(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n as Label
	for c in n.get_children():
		var hit := _first_label_text(c, text)
		if hit != null:
			return hit
	return null


func _find_label_prefix(n: Node, prefix: String) -> Label:
	if n.is_queued_for_deletion():
		return null
	if n is Label and (n as Label).text.begins_with(prefix):
		return n as Label
	for c in n.get_children():
		var hit := _find_label_prefix(c, prefix)
		if hit != null:
			return hit
	return null


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
	print("QA_W54_PORT_COUNTER cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
