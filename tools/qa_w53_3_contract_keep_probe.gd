extends SceneTree
## Lane w53-3：headless 探针——在身委办要的货不上秤：牙行卖钮只卖委办还欠那几件以外的，卡上「舱」后括注委办件数。
## 原先委办货与别的货同舱同卖：交货地博多唐房的牙行里，舱里 40 件生丝、委办要交 16 件，按卡上「全卖」40 件一并过秤卖掉，
## 页首委办栏随即写「舱里现有 0」、交货钮发灰，到期误期挨罚（扣酬金一成五、名声减 1）。卡上只写「舱 40」，看不出哪几件是委办的。
##   一、40 件、委办 16：卡上「舱 40（委办 16）」；三枚卖钮都按得下；全卖悬停写卖 24 件的实得、委办 16 件留在舱里；
##      按全卖：舱里剩 16、现银多出 = 按下前 Economy.estimate_sell_revenue(港, 生丝, 24)，记事写明委办 16 件留着；再按交货交清。
##   二、16 件、委办 16：三枚卖钮都按不下，悬停写「要卖先毁约」；直调 _on_sell（旧钮 / 回车）也一件不卖、钱不动。
##   三、21 件、委办 16：卖 1、全卖按得下，卖 10 按不下（悬停写可卖的只有 5 件）；全卖卖 5 件、剩 16。
##   四、按「毁约」之后：卡上回到「舱 16」，全卖 16 件卖光。
##   五、委办要的是别的货：生丝卡上「舱 40」，全卖 40 件卖光。
##   六、委办货分在两艘船（旗舰 10、二号 30）：全卖卖 24、全队剩 16。
##   七、没有委办、舱里 5 件：卖 10 按不下，悬停写「舱里不足 10 件。」（原先写「5 件共得…」，像是按得下）。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_contract_keep_probe.gd
## 输出末行 W53_3_CONTRACT_KEEP_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_economy_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORT := "hakata"
const GOOD := "raw_silk"
const OTHER := "tea"
const PURSE := 1600

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
	_expect(eco.get_role(PORT, GOOD) == "consumer" and eco.is_traded(PORT, GOOD),
		"博多唐房把生丝当紧缺货收（摆场前提：委办交货地）")

	await _sell_all_keeps()
	await _all_kept()
	await _partly_free()
	await _after_abandon()
	await _other_good()
	await _two_ships()
	await _short_tip()

	eco.rates = _rates0.duplicate(true)
	gs.contract = {}
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
	print("W53_3_CONTRACT_KEEP_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 一艘或两艘客舟；cargo 是各船生丝件数；委办 kind 件（kind 空则不摆委办）
func _reset(cargo: Array, kind: String, remaining: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	gs.last_port = PORT
	gs.money = 3000
	gs.debt = 0
	gs.fame = 5
	gs.broker_salt = 0
	fleet.ships = []
	for i in cargo.size():
		fleet.add_ship("keel_boat", "旗舰" if i == 0 else "二号")
	fleet.water = 60
	fleet.food = 60
	for i in cargo.size():
		if int(cargo[i]) > 0:
			fleet.add_cargo(GOOD, int(cargo[i]), 30.0, i)
	gs.contract = {}
	if kind != "":
		gs.contract = {
			"good_id": kind, "qty": remaining, "remaining": remaining, "dest": PORT, "from": "quanzhou",
			"purse": PURSE, "unit_purse": float(PURSE) / float(remaining), "paid": 0,
			"due_day": cal.absolute_day() + 10, "deadline_days": 12, "voyage_days": 8,
			"offer_month": cal.year * 12 + cal.month,
		}


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


func _card_button(text: String) -> Button:
	for c in _card(GOOD):
		if c is Button and str(c.get("text")) == text:
			return c as Button
	return null


func _card_held() -> String:
	for c in _card(GOOD):
		if c is Label and str(c.get("text")).begins_with("舱 "):
			return str(c.get("text"))
	return "（柜上不见生丝卡）"


## 页首委办栏里的钮（交货 / 毁约　扣 N）
func _panel_button(prefix: String) -> Button:
	var panel: Node = _main.get("choices_container").get_node_or_null("ContractPanel")
	if panel == null:
		return null
	var out: Array = []
	_texts_under(panel, out)
	for c in out:
		if c is Button and str(c.get("text")).begins_with(prefix):
			return c as Button
	return null


## 三枚卖钮哪些按不下
func _disabled_sells() -> PackedStringArray:
	var out := PackedStringArray()
	for t in ["卖 1", "卖 10", "全卖"]:
		var b := _card_button(t)
		if b == null or b.disabled:
			out.append(t)
	return out


## 按卡上的钮；按下后整页重排、钮随旧页释放（Godot 4 里释放了的对象与 null 比较为真），找没找到先记下
func _press(b: Button) -> bool:
	var has_btn := b != null
	if has_btn:
		b.emit_signal("pressed")
		await _settle(2)
	return has_btn


func _last_log() -> String:
	var logs: PackedStringArray = _main.get("_log_lines")
	return str(logs[0]) if logs.size() > 0 else ""


## 一、40 件、委办 16：全卖卖 24、留 16，再交货交清
func _sell_all_keeps() -> void:
	print("── 一、舱里生丝 40、委办要交 16（交货地就是博多唐房）：全卖只卖 24，委办 16 件留着交货")
	_reset([40], GOOD, 16)
	await _enter()
	var held := _card_held()
	var dis := _disabled_sells()
	_expect(held == "舱 40（委办 16）" and dis.is_empty(),
		"卡上「%s」（应「舱 40（委办 16）」），卖钮按不下的：%s" % [held, "无" if dis.is_empty() else "、".join(dis)])
	var want: int = eco.estimate_sell_revenue(PORT, GOOD, 24)
	var b := _card_button("全卖")
	var tip: String = b.tooltip_text if b != null else ""
	_expect(tip.contains("24 件共得 %d 钱" % want) and tip.contains("委办要的 16 件留在舱里"),
		"全卖悬停写卖 24 件得 %d 钱、委办 16 件留在舱里（悬停：%s）" % [want, tip.replace("\n", " ⏎ ")])
	var m0: int = gs.money
	var pressed: bool = await _press(b)
	var got: int = int(gs.money) - m0
	var line := _last_log()
	_expect(pressed and fleet.cargo_qty(GOOD) == 16 and got == want and line.contains("×24") and line.contains("委办要的 16 件留在舱里"),
		"按全卖：舱里剩 %d（应 16），得 %d 钱（应 %d），记事「%s」" % [fleet.cargo_qty(GOOD), got, want, line])
	var m1: int = gs.money
	var deliver := _panel_button("交货")
	var d_ok := deliver != null and not deliver.disabled
	await _press(deliver if d_ok else null)
	_expect(d_ok and gs.contract.is_empty() and fleet.cargo_qty(GOOD) == 0 and int(gs.money) - m1 == PURSE,
		"再按交货：委办交清（在身 %s）、舱里 %d、酬 %d 钱到手（应 %d）" % [
			"无" if gs.contract.is_empty() else "仍在", fleet.cargo_qty(GOOD), int(gs.money) - m1, PURSE])


## 二、16 件全是委办的：三枚卖钮都按不下；直调 _on_sell 也不卖
func _all_kept() -> void:
	print("── 二、舱里生丝 16、委办要交 16：卖钮全灰，直调 _on_sell 一件不卖")
	_reset([16], GOOD, 16)
	await _enter()
	var dis := _disabled_sells()
	var b := _card_button("全卖")
	var tip: String = b.tooltip_text if b != null else ""
	_expect(dis.size() == 3 and tip.contains("要卖先毁约"),
		"三枚卖钮按不下的：%s（应三枚都灰），全卖悬停「%s」写要卖先毁约" % ["、".join(dis), tip.replace("\n", " ⏎ ")])
	var m0: int = gs.money
	_main.call("_on_sell", PORT, GOOD, 16, -1)
	await _settle(2)
	_expect(fleet.cargo_qty(GOOD) == 16 and int(gs.money) == m0,
		"直调 _on_sell(全卖 16 件)：舱里仍 %d、现银 %d → %d" % [fleet.cargo_qty(GOOD), m0, gs.money])


## 三、21 件：可卖 5
func _partly_free() -> void:
	print("── 三、舱里生丝 21、委办要交 16：卖 1、全卖按得下，卖 10 按不下；全卖卖 5")
	_reset([21], GOOD, 16)
	await _enter()
	var dis := _disabled_sells()
	var b10 := _card_button("卖 10")
	var tip10: String = b10.tooltip_text if b10 != null else ""
	_expect(dis == PackedStringArray(["卖 10"]) and tip10.contains("可卖的只有 5 件"),
		"按不下的：%s（应只有卖 10），卖 10 悬停「%s」" % ["无" if dis.is_empty() else "、".join(dis), tip10.replace("\n", " ⏎ ")])
	var want: int = eco.estimate_sell_revenue(PORT, GOOD, 5)
	var m0: int = gs.money
	var pressed: bool = await _press(_card_button("全卖"))
	_expect(pressed and fleet.cargo_qty(GOOD) == 16 and int(gs.money) - m0 == want,
		"全卖：舱里剩 %d（应 16），得 %d 钱（应 %d）" % [fleet.cargo_qty(GOOD), int(gs.money) - m0, want])


## 四、毁约之后照常卖
func _after_abandon() -> void:
	print("── 四、按「毁约」之后：卡上回到「舱 16」，全卖卖光")
	_reset([16], GOOD, 16)
	await _enter()
	var drop := _panel_button("毁约")
	var dropped: bool = await _press(drop)
	var held := _card_held()
	var dis := _disabled_sells()
	_expect(dropped and gs.contract.is_empty() and held == "舱 16" and not ("全卖" in dis),
		"毁约后在身委办 %s，卡上「%s」（应「舱 16」），全卖%s" % [
			"无" if gs.contract.is_empty() else "仍在", held, "按不下" if "全卖" in dis else "按得下"])
	var pressed: bool = await _press(_card_button("全卖"))
	_expect(pressed and fleet.cargo_qty(GOOD) == 0, "全卖后舱里生丝 %d（应 0）" % fleet.cargo_qty(GOOD))


## 五、委办要的是别的货
func _other_good() -> void:
	print("── 五、委办要交的是茶叶：生丝卡照旧「舱 40」，全卖卖光")
	_reset([40], OTHER, 8)
	await _enter()
	var held := _card_held()
	var pressed: bool = await _press(_card_button("全卖"))
	_expect(held == "舱 40" and pressed and fleet.cargo_qty(GOOD) == 0,
		"卡上「%s」（应「舱 40」），全卖后舱里生丝 %d（应 0）" % [held, fleet.cargo_qty(GOOD)])


## 六、委办货分在两艘船
func _two_ships() -> void:
	print("── 六、生丝旗舰 10、二号 30，委办 16：全卖卖 24、全队剩 16")
	_reset([10, 30], GOOD, 16)
	await _enter()
	var want: int = eco.estimate_sell_revenue(PORT, GOOD, 24)
	var m0: int = gs.money
	var pressed: bool = await _press(_card_button("全卖"))
	_expect(pressed and fleet.cargo_qty(GOOD) == 16 and int(gs.money) - m0 == want,
		"全卖：全队剩 %d（旗舰 %d、二号 %d；应共 16），得 %d 钱（应 %d）" % [
			fleet.cargo_qty(GOOD), fleet.cargo_qty(GOOD, 0), fleet.cargo_qty(GOOD, 1), int(gs.money) - m0, want])


## 七、没有委办、舱里不足：按不下的卖 10 悬停写不足
func _short_tip() -> void:
	print("── 七、没有委办、舱里生丝 5：卖 10 按不下，悬停写「舱里不足 10 件。」")
	_reset([5], "", 0)
	await _enter()
	var b10 := _card_button("卖 10")
	var tip: String = b10.tooltip_text if b10 != null else ""
	_expect(b10 != null and b10.disabled and tip == "舱里不足 10 件。",
		"卖 10 %s，悬停「%s」（应「舱里不足 10 件。」）" % ["按不下" if b10 != null and b10.disabled else "按得下", tip.replace("\n", " ⏎ ")])
