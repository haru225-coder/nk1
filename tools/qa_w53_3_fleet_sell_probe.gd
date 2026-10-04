extends SceneTree
## Lane w53-3：headless 探针——多船时牙行卖出不分船：货装在哪艘船都上柜、卡上写全队件数、卖钮跨船卖。
## 原先牙行「装至」选的那艘船（进页默认旗舰）一船定三件事：柜上第一席（舱里有货占第一席）只看这艘、卡上「舱 N」只写这艘、
## 卖 1 / 卖 10 / 全卖只卖这艘。生丝装在二号船、旗舰空着时进博多唐房牙行：十二手柜序里十手生丝不上柜（落在「今日不在柜上」
## 那一排），「明日再看」也难换上来；只有点「装至」那排的「二号」才冒出来——那枚钮写的是装货。
##   一、两艘船、生丝只在二号：选着旗舰进页，十二手柜序（broker_salt 0..11）回回生丝占第一席，卡上「舱 40」、三枚卖钮都按得下。
##   二、柜上三样不随「装至」改：切到二号船，柜与切前一字不差。
##   三、按卡上「全卖」（真钮）：全队生丝卖光、两艘船上都不剩，现银多出 = 按下前 Economy.estimate_sell_revenue(港, 生丝, 40)。
##   四、两艘船均价不同（旗舰 10 件 @50、二号 30 件 @20）：按「卖 10」先卸旗舰那 10 件，记事「赚 / 亏」= 实得 − 500
##      （卸下那几件的成本），不是按全队均价 27.5 算出的 275。
##   五、买进照旧装「装至」那艘：选二号按「买 1」，二号多 1 件、旗舰不变。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_fleet_sell_probe.gd
## 输出末行 W53_3_FLEET_SELL_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_economy_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORT := "hakata"
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


## _run 被脚本错半路掐断时 _report() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


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
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	_rates0 = eco.rates.duplicate(true)
	_expect(eco.get_role(PORT, GOOD) == "consumer", "博多唐房把生丝当紧缺货收（摆场前提）")

	await _held_on_counter()
	await _sell_all()
	await _mixed_cost()
	await _buy_still_per_ship()

	eco.rates = _rates0.duplicate(true)
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_3_FLEET_SELL_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 两艘客舟；salt 是柜序。货另摆
func _reset(money: int, salt: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	gs.last_port = PORT
	gs.money = money
	gs.debt = 0
	gs.broker_salt = salt
	fleet.ships = []
	fleet.add_ship("keel_boat", "旗舰")
	fleet.add_ship("keel_boat", "二号")
	fleet.water = 60
	fleet.food = 60


## 选着旗舰（从别的页进来）进牙行
func _enter() -> void:
	_main.set("_market_ship", 0)
	_main.set("_market_hold", false)
	_main.load_scene(PORT + "_market")
	await _settle(2)


func _texts_under(n: Node, out: Array) -> void:
	if n is Label or n is Button:
		out.append(n)
	for c in n.get_children():
		_texts_under(c, out)


## 柜上 gid 那张卡里的字控件；不在柜上给 []
func _card(gid: String) -> Array:
	var hand: PackedStringArray = _main.get("broker_hand")
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	var i := hand.find(gid)
	if i < 0 or slips == null or i >= slips.get_child_count():
		return []
	var out: Array = []
	_texts_under(slips.get_child(i), out)
	return out


func _card_button(gid: String, text: String) -> Button:
	for c in _card(gid):
		if c is Button and str(c.get("text")) == text:
			return c as Button
	return null


func _card_held(gid: String) -> String:
	for c in _card(gid):
		if c is Label and str(c.get("text")).begins_with("舱 "):
			return str(c.get("text"))
	return ""


func _good(gid: String) -> String:
	return str(gm.get_good_name(gid))


## 一、二
func _held_on_counter() -> void:
	print("── 一、生丝只在二号船，选着旗舰进博多唐房牙行：十二手柜序回回占第一席；二、柜不随「装至」改")
	var first := 0
	var miss := PackedStringArray()
	for salt in 12:
		_reset(3000, salt)
		fleet.add_cargo(GOOD, 40, 30.0, 1)
		await _enter()
		var hand: PackedStringArray = _main.get("broker_hand")
		if hand.size() > 0 and hand[0] == GOOD:
			first += 1
		else:
			miss.append("柜序 %d：%s" % [salt, ", ".join(hand)])
	_expect(first == 12, "十二手柜序生丝占第一席 %d 手（不上柜的：%s）" % [first, "无" if miss.is_empty() else "；".join(miss)])

	_reset(3000, 0)
	fleet.add_cargo(GOOD, 40, 30.0, 1)
	await _enter()
	var held := _card_held(GOOD)
	var dis := PackedStringArray()
	for t in ["卖 1", "卖 10", "全卖"]:
		var b := _card_button(GOOD, t)
		if b == null or b.disabled:
			dis.append(t)
	_expect(held == "舱 40" and dis.is_empty(),
		"旗舰选着、生丝全在二号：卡上「%s」（应「舱 40」），卖钮按不下的：%s" % [held, "无" if dis.is_empty() else "、".join(dis)])
	var hand0: PackedStringArray = _main.get("broker_hand")
	_main.call("_select_market_ship", 1)
	await _settle(2)
	var hand1: PackedStringArray = _main.get("broker_hand")
	_expect(int(_main.get("_market_ship")) == 1 and hand1 == hand0,
		"切到二号船，柜上三样不变（切前 %s / 切后 %s）" % [", ".join(hand0), ", ".join(hand1)])


## 三、全卖跨船卖光，得钱 = 逐件压价的预估
func _sell_all() -> void:
	print("── 三、按卡上「全卖」：生丝旗舰 15、二号 25，全队卖光，得钱 = 按下前预估")
	_reset(3000, 0)
	fleet.add_cargo(GOOD, 15, 30.0, 0)
	fleet.add_cargo(GOOD, 25, 30.0, 1)
	await _enter()
	var btn := _card_button(GOOD, "全卖")
	var has_btn := btn != null  # 按下后整页重排、这枚钮随旧页释放（Godot 4 里释放了的对象与 null 比较为真），先记下
	var m0: int = gs.money
	var want: int = eco.estimate_sell_revenue(PORT, GOOD, 40)
	if has_btn:
		btn.emit_signal("pressed")
		await _settle(2)
	var got: int = int(gs.money) - m0
	_expect(has_btn and fleet.cargo_qty(GOOD) == 0 and fleet.cargo_qty(GOOD, 0) == 0 and fleet.cargo_qty(GOOD, 1) == 0 and got == want,
		"全卖后生丝全队 %d 件（旗舰 %d、二号 %d），得 %d 钱 = 预估 %d" % [
			fleet.cargo_qty(GOOD), fleet.cargo_qty(GOOD, 0), fleet.cargo_qty(GOOD, 1), got, want])


## 四、各船均价不同：赚亏按卸下那几件的成本
func _mixed_cost() -> void:
	print("── 四、旗舰 10 件 @50、二号 30 件 @20，按「卖 10」：赚亏按卸下那 10 件的成本 500 算")
	_reset(3000, 0)
	fleet.add_cargo(GOOD, 10, 50.0, 0)
	fleet.add_cargo(GOOD, 30, 20.0, 1)
	await _enter()
	var btn := _card_button(GOOD, "卖 10")
	var has_btn := btn != null
	var m0: int = gs.money
	if has_btn:
		btn.emit_signal("pressed")
		await _settle(2)
	var got: int = int(gs.money) - m0
	var cost := 10 * 50
	var tail := ("赚 %d" % (got - cost)) if got >= cost else ("亏 %d" % (cost - got))
	var logs: PackedStringArray = _main.get("_log_lines")
	var line := str(logs[0]) if logs.size() > 0 else ""
	_expect(has_btn and line.contains("×10") and line.contains("得 %d 钱" % got) and line.contains(tail),
		"卖 10 得 %d 钱，记事写「%s」（实为「%s」）" % [got, tail, line])
	_expect(fleet.cargo_qty(GOOD, 0) == 0 and fleet.cargo_qty(GOOD, 1) == 30,
		"先卸旗舰那 10 件：旗舰剩 %d、二号剩 %d（应 0 / 30）" % [fleet.cargo_qty(GOOD, 0), fleet.cargo_qty(GOOD, 1)])


## 五、买进照旧装「装至」选的那艘
func _buy_still_per_ship() -> void:
	print("── 五、选二号按「买 1」：二号多 1 件、旗舰不变")
	_reset(3000, 0)
	await _enter()
	var hand: PackedStringArray = _main.get("broker_hand")
	var gid := str(hand[0]) if hand.size() > 0 else ""
	_main.call("_select_market_ship", 1)
	await _settle(2)
	var q0: int = fleet.cargo_qty(gid, 0)
	var q1: int = fleet.cargo_qty(gid, 1)
	var btn := _card_button(gid, "买 1")
	var has_btn := btn != null
	if has_btn:
		btn.emit_signal("pressed")
		await _settle(2)
	_expect(gid != "" and has_btn and fleet.cargo_qty(gid, 1) == q1 + 1 and fleet.cargo_qty(gid, 0) == q0,
		"选二号买 1 件%s：二号 %d → %d、旗舰 %d → %d" % [_good(gid), q1, fleet.cargo_qty(gid, 1), q0, fleet.cargo_qty(gid, 0)])
