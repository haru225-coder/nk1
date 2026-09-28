extends SceneTree
## Lane iz：headless 探针——玩家看到的钱数与实际结算一致。
##   一、月初结息通告：欠债跨月必出一条【月息】，息钱 = 船屋赊贷工席预告的「每月生息」= debt 实涨；无债不出。
##   二、牙行买十 / 买满 / 卖十 / 全卖 的悬停总价 = 按下后实扣 / 实得（首件价 × 件数 对照印出）。
##   三、委办「凑得出 N 件」= 逐船照单去买真能买到的件数，再多一件就买不起或装不下。
## 用法：godot --headless --path . -s res://tools/qa_money_notices_probe.gd
## 输出末行 IZ_PROBE fails=N；N>0 时 exit 1。

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _notices: Array = []
var _rates0: Dictionary = {}
var _ships0: Array = []
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	gm = root.get_node("/root/GameManager")
	cal = root.get_node("/root/Calendar")
	fleet = root.get_node("/root/Fleet")
	crew = root.get_node("/root/Crew")
	eco = root.get_node("/root/Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		print("  ✗ Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		print("IZ_PROBE fails=1")
		quit(1)
		return
	gm.monthly_notice.connect(func(t: String) -> void: _notices.append(t))
	_rates0 = eco.rates.duplicate(true)
	_ships0 = fleet.ships.duplicate(true)

	await _interest()
	await _market_tips()
	await _contract_purse()

	print("IZ_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _reset(port_id: String, money: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	fleet.ships = _ships0.duplicate(true)
	gs.last_port = port_id
	gs.money = money
	gs.debt = 0


# ── 一、月息 ──────────────────────────────────────────

func _interest() -> void:
	print("── 一、月初结息通告")
	_reset("quanzhou", 500)
	gs.debt = 1000
	cal.from_dict({"year": 1255, "month": 3, "day": 28})
	_notices.clear()
	gm.advance_days(1)
	_expect(_interest_lines().is_empty(), "月中走日子不出月息（3/28→3/29）")

	_main.load_scene("quanzhou_shipyard")
	await _settle(4)
	var pre := _label_containing("每月生息")
	var pre_n := _ints(pre)
	print("   船屋赊贷工席：「%s」" % pre)
	var d0: int = gs.debt
	gm.advance_days(2)
	var got := _interest_lines()
	print("   跨月 3/29→4/1 通告：%s　debt %d → %d" % [str(got), d0, gs.debt])
	_expect(got.size() == 1, "跨月恰出一条【月息】（得 %d 条）" % got.size())
	var n := _ints(got[0]) if got.size() == 1 else []
	_expect(pre_n.size() == 2 and n.size() == 2 and n[0] == pre_n[1] and n[0] == gs.debt - d0 and n[1] == gs.debt,
		"通告息钱 = 工席预告每月生息 = debt 实涨，现欠 = debt（预告 %s，通告 %s，实涨 %d）" % [str(pre_n), str(n), gs.debt - d0])
	var logged := false
	for line in _main.get("_log_lines"):
		# 记事栏按 UiTheme.plain_log 去掉句首【】签，正文照登
		if n.size() == 2 and str(line) == "蕃商结息 %d 钱，现欠 %d。" % [n[0], n[1]]:
			logged = true
	_expect(logged, "船籍簿记事栏登出「蕃商结息 %d 钱，现欠 %d。」" % [n[0] if n.size() == 2 else -1, n[1] if n.size() == 2 else -1])

	# 连欠一年：月月都出，息钱之和 = 债涨
	var d1: int = gs.debt
	_notices.clear()
	gm.advance_days(360)
	var year := _interest_lines()
	var sum := 0
	for t in year:
		sum += int(_ints(t)[0])
	print("   连欠一年：%d 条，息钱合 %d，debt %d → %d" % [year.size(), sum, d1, gs.debt])
	_expect(year.size() == 12 and sum == gs.debt - d1, "连欠十二月出十二条，息钱之和 = 债涨")

	# 还清后不再出
	gs.debt = 0
	_notices.clear()
	gm.advance_days(60)
	_expect(_interest_lines().is_empty(), "无债两月不出月息")


func _interest_lines() -> Array:
	var out: Array = []
	for t in _notices:
		if str(t).begins_with("【月息】"):
			out.append(str(t))
	return out


# ── 二、牙行悬停总价 ──────────────────────────────────

func _market_tips() -> void:
	print("── 二、牙行悬停总价（首件 × 件数 vs 悬停总价 vs 实结）")
	var port := "zhangzhou"
	_reset(port, 20000)
	_main.set("_market_ship", 0)
	_main.load_scene(port + "_market")
	await _settle(4)
	var hand: PackedStringArray = _main.get("broker_hand")
	_expect(hand.size() > 0, "漳州牙行柜上有货")
	if hand.is_empty():
		return
	var gid := str(hand[0])
	var gname := str(gm.get_good_name(gid))

	await _press_and_compare(port, gid, "买 10", true, "%s 买 10" % gname)
	await _press_and_compare(port, gid, "卖 10", false, "%s 卖 10" % gname)
	await _press_and_compare(port, gid, "买满", true, "%s 买满" % gname)
	await _press_and_compare(port, gid, "全卖", false, "%s 全卖" % gname)
	# 钱不够：只够 5 件
	gs.money = int(eco.estimate_buy_cost(port, gid, 5)) + 1
	_main.load_scene(port + "_market")
	await _settle(2)
	await _press_and_compare(port, gid, "买 10", true, "%s 现银只够 5 件时 买 10" % gname, 5)
	# 舱只容 3 件：把本船塞到只剩 3 件的空
	gs.money = 20000
	var bulk: float = fleet.call("_bulk", gid)
	if bulk > 0.0:
		var free: float = fleet.ship_free_capacity(0)
		var filler := "sea_salt" if gid != "sea_salt" else "grain"
		var fb: float = fleet.call("_bulk", filler)
		var fill := int(ceil((free - 3.5 * bulk) / fb))
		if fill > 0:
			fleet.add_cargo(filler, fill, 1.0, 0)
		var room: int = fleet.max_loadable(gid, 0)
		_main.load_scene(port + "_market")
		await _settle(2)
		if room > 0 and room < 10:
			await _press_and_compare(port, gid, "买 10", true, "%s 舱只容 %d 件时 买 10" % [gname, room], room)
		else:
			_expect(false, "舱位摆场失败（room=%d）" % room)
		_main.load_scene(port + "_market")
		await _settle(2)
		var full_tip := _card_button(gid, "买 1")
		if full_tip != null:
			print("   舱满后 买 1 悬停：「%s」" % full_tip.tooltip_text)
			_expect(full_tip.tooltip_text == "舱满，这艘船装不下。", "舱满时买钮悬停写舱满")


func _press_and_compare(port: String, gid: String, label: String, is_buy: bool, what: String, expect_n := -1) -> void:
	_main.load_scene(port + "_market")
	await _settle(2)
	var b := _card_button(gid, label)
	if b == null:
		_expect(false, "%s：找不到钮" % what)
		return
	var tip := b.tooltip_text
	var nums := _ints(tip)
	var first := int(eco.buy_price(port, gid)) if is_buy else int(eco.sell_price(port, gid))
	var m0: int = gs.money
	var q0: int = fleet.cargo_qty(gid, 0)
	b.pressed.emit()
	await _settle(2)
	var paid: int = (m0 - int(gs.money)) if is_buy else (int(gs.money) - m0)
	var moved: int = absi(int(fleet.cargo_qty(gid, 0)) - q0)
	print("   %s：首件 %d × %d = %d ｜ 悬停「%s」｜ 实结 %d 件 %d 钱" % [what, first, moved, first * moved, tip, moved, paid])
	# 悬停格式：「<头> N 件，共付/共得 T 钱，均价 A。逐件…，首件 F。」
	_expect(nums.size() >= 4 and nums[0] == moved and nums[1] == paid and nums[3] == first,
		"%s：悬停件数 / 总价 / 首件 = 实结（悬停 %s）" % [what, str(nums)])
	if expect_n >= 0:
		_expect(moved == expect_n, "%s：实结 %d 件（应 %d）" % [what, moved, expect_n])


func _card_button(gid: String, label: String) -> Button:
	var slips := _find(_main, func(n: Node) -> bool: return n.name == "BrokerSlips")
	var hand: PackedStringArray = _main.get("broker_hand")
	var i := hand.find(gid)
	if slips == null or i < 0 or i >= slips.get_child_count():
		return null
	return _find(slips.get_child(i), func(n: Node) -> bool: return n is Button and str((n as Button).text) == label) as Button


# ── 三、委办凑得出 ────────────────────────────────────

func _contract_purse() -> void:
	print("── 三、委办「凑得出 N 件」（旧口径 现银÷首件 vs 新口径 vs 逐船照买）")
	# 找一处旧口径与实买不同、且钱不够买满的委办：ch1 各港 × 现银
	var picked := {}
	for p in gm.unlocked_ports():
		var pid := str(p.get("id", ""))
		for money in [600, 1000, 1500, 2000, 3000]:
			_reset(pid, money)
			var offer: Dictionary = gs.contract_offer(pid)
			if offer.is_empty():
				continue
			var gid := str(offer.get("good_id", ""))
			var need := int(offer.get("qty", 0))
			var unit := int(eco.buy_price(pid, gid))
			var old_n: int = mini(int(float(money) / float(unit)), int(fleet.max_loadable(gid)))
			var new_n := _afford(pid, gid, money)
			if new_n < need and old_n != new_n:
				picked = {"port": pid, "money": money, "gid": gid, "need": need, "unit": unit, "old": old_n, "new": new_n}
				break
		if not picked.is_empty():
			break
	_expect(not picked.is_empty(), "找到一处旧口径偏乐观的委办")
	if picked.is_empty():
		return
	var port := str(picked["port"])
	var gid := str(picked["gid"])
	_reset(port, int(picked["money"]))
	# 只算今日柜上的货（lane iz2）：换柜序直到这件上柜，买卖走真 broker_hand
	for salt in 12:
		gs.broker_salt = salt
		_main.load_scene(port + "_market")
		await _settle(4)
		if gid in _main.get("broker_hand"):
			break
	_expect(gid in _main.get("broker_hand"), "柜序 %d 上 %s 在柜上" % [gs.broker_salt, gm.get_good_name(gid)])
	var lbl := _label_containing("凑得出")
	var shown := _ints(lbl)
	print("   %s 现银 %d 委办 %s ×%d：旧口径 %d 件；牙行现写「%s」" % [
		port, int(picked["money"]), gm.get_good_name(gid), int(picked["need"]), int(picked["old"]), lbl])
	_expect(lbl.contains("首件") and shown.size() >= 3 and shown[0] == int(picked["unit"]) and shown[1] == int(picked["new"]),
		"单上首件价与凑得出件数按新口径（%s）" % str(shown))
	# 逐船照单去买，能买到的就是单上写的件数
	for si in fleet.ships.size():
		_main.call("_on_buy", port, gid, int(picked["need"]), si)
		await _settle(1)
	var bought: int = fleet.cargo_qty(gid)
	var one_more: int = int(eco.estimate_buy_cost(port, gid, 1))
	var room_left := 0
	for si in fleet.ships.size():
		room_left += int(fleet.max_loadable(gid, si))
	print("   逐船照买得 %d 件，余钱 %d，再一件要 %d，余舱 %d 件" % [bought, gs.money, one_more, room_left])
	_expect(shown.size() >= 2 and bought == shown[1], "照买件数 %d = 单上凑得出 %d" % [bought, shown[1] if shown.size() >= 2 else -1])
	_expect(one_more > int(gs.money) or room_left <= 0, "再多一件就买不起或装不下")
	_expect(int(picked["old"]) > bought, "旧口径 %d 件高于实买 %d 件，确属偏乐观" % [int(picked["old"]), bought])


# ── 小件 ──────────────────────────────────────────────

## 探针自带的实买件数：逐件加一，直到 estimate_buy_cost 超过现银（不借 Main 的算法，免得自证）
func _afford(pid: String, gid: String, money: int) -> int:
	var n := 0
	while n < 9999 and int(eco.estimate_buy_cost(pid, gid, n + 1)) <= money:
		n += 1
	return n


func _ints(t: String) -> Array:
	var re := RegEx.new()
	re.compile("\\d+")
	var out: Array = []
	for m in re.search_all(t):
		out.append(int(m.get_string()))
	return out


func _label_containing(t: String) -> String:
	var n := _find(_main, func(x: Node) -> bool: return x is Label and str((x as Label).text).contains(t))
	return str((n as Label).text) if n != null else ""


func _find(n: Node, pred: Callable) -> Node:
	if n == null:
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame
