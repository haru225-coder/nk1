extends SceneTree
## Lane w53-3：headless 探针——牙行页一按买卖整页重排不卡。
## 带汉字的 Label / Button 带着字进树，Godot 4.6 下一枚要多耗 5～15 毫秒；空着进树、挂上再填字只要几十微秒，挂好的字与尺寸
## 一样。牙行页每按一次买 / 卖都整页重排（柜上三张卡、委办栏、闭柜货钮、页脚两钮，约六十枚），改前一按卡 0.8 秒。
## 改后 Main._attach_quiet 把建好的一块先摘字、挂上再填回。
##   一、整页重排时，牙行页里（choices_container 与页脚）进树那一刻带着字的 Label / Button 为 0 枚（SceneTree.node_added
##      当场看 text；改前约六十枚）。委办未接（细则展开）、委办在身、两艘船（装至选船钮）三种页面各重排一遍。
##   二、按「买 1」（Main._on_buy 真回调，含其后整页重排）三回取最快不过 PRESS_LIMIT_MS（改前约 0.8 秒、改后约 0.09 秒）。
##   三、重排完页上的字一样不缺：柜上三张卡「买 N　卖 M」= Economy 现价、「舱 N」= 本船舱货；委办栏摘要行；
##      闭柜货钮 = 柜外货名；页脚「明日再看」「离开」；页里看得见的 Label / Button 没有空字。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_market_rerender_probe.gd
## 输出末行 W53_3_RERENDER_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_economy_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 按「买 1」到整页重排完的耗时上限（三回取最快）。改前约 800 毫秒，改后约 90 毫秒
const PRESS_LIMIT_MS := 400
const PRESS_TRIES := 3

var _main: Node
var gs: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
## node_added 计数：牙行页里进树的 Label / Button 总数、其中进树那一刻带着字的数与头几枚的字
var _seen := 0
var _loud := 0
var _loud_texts: PackedStringArray = []


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

	await _quiet_enter()
	await _press_time()

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
	print("W53_3_RERENDER_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _reset(port_id: String, money: int, ships: Array) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	gs.last_port = port_id
	gs.money = money
	gs.debt = 0
	fleet.ships = []
	for i in ships.size():
		fleet.add_ship(str(ships[i]), "试船%d" % (i + 1))
	fleet.water = 60
	fleet.food = 60


## 牙行页里：选船 / 柜上 / 委办 / 闭柜都挂在 choices_container 下，明日再看 / 离开挂在页脚
func _in_page(n: Node) -> bool:
	var cc: Node = _main.get("choices_container")
	var footer: Node = _main.get("_page_footer")
	return (cc != null and cc.is_ancestor_of(n)) or (footer != null and footer.is_ancestor_of(n))


func _on_node_added(n: Node) -> void:
	if not (n is Label or n is Button) or not _in_page(n):
		return
	_seen += 1
	var t := str(n.get("text"))
	if t != "":
		_loud += 1
		if _loud_texts.size() < 4:
			_loud_texts.append(t)


## 一次整页重排里，牙行页进树的 Label / Button 共几枚、其中带着字进树的几枚
func _count_rerender(scene_id: String) -> Array:
	_seen = 0
	_loud = 0
	_loud_texts = PackedStringArray()
	node_added.connect(_on_node_added)
	_main.load_scene(scene_id)
	node_added.disconnect(_on_node_added)
	await _settle(2)
	return [_seen, _loud, " / ".join(_loud_texts)]


func _texts_under(n: Node, out: Array) -> void:
	if n is Label or n is Button:
		out.append(n)
	for c in n.get_children():
		_texts_under(c, out)


## 三、重排完页上的字：柜上三张卡价钱行与舱货、委办栏、闭柜货钮、页脚两钮、看得见的字控件无空字
func _page_texts_ok(port_id: String, tag: String, contract_held: bool) -> void:
	var cc: Node = _main.get("choices_container")
	var hand: PackedStringArray = _main.get("broker_hand")
	var ship: int = int(_main.get("_market_ship"))
	var slips: Node = cc.get_node_or_null("BrokerSlips")
	var cards_ok := slips != null and slips.get_child_count() == hand.size() and hand.size() == 3
	var card_bad := PackedStringArray()
	if cards_ok:
		for i in hand.size():
			var gid := str(hand[i])
			var nodes: Array = []
			_texts_under(slips.get_child(i), nodes)
			var want_price := "买 %d　卖 %d" % [eco.buy_price(port_id, gid), eco.sell_price(port_id, gid)]
			var want_held := "舱 %d" % fleet.cargo_qty(gid, ship)
			var got: PackedStringArray = []
			for c in nodes:
				got.append(str(c.get("text")))
			if not (want_price in got and want_held in got and _good_name(gid) in got):
				card_bad.append("%s 缺「%s」/「%s」（卡上：%s）" % [gid, want_price, want_held, " | ".join(got)])
	_expect(cards_ok and card_bad.is_empty(),
		"%s：柜上 %d 张卡，货名 / 「买 N　卖 M」= 现价 / 「舱 N」= 本船舱货都在%s" % [
			tag, hand.size(), "" if card_bad.is_empty() else "；" + "；".join(card_bad)])

	var panel: Node = cc.get_node_or_null("ContractPanel")
	var head_txt := ""
	if panel != null:
		var pn: Array = []
		_texts_under(panel, pn)
		if not pn.is_empty():
			head_txt = str(pn[0].get("text"))
	var head_ok := head_txt.begins_with("在身委办：") if contract_held else (head_txt.begins_with("委办　送") or head_txt.begins_with("本月牙行没有外埠委办"))
	_expect(panel != null and head_ok, "%s：委办栏第一行有字「%s」" % [tag, head_txt.left(24)])

	var shut: Node = cc.get_node_or_null("BrokerShut")
	var want_shut: Array = []
	for raw in eco.goods_at(port_id):
		if not (str(raw) in hand):
			want_shut.append(_good_name(str(raw)))
	var got_shut: Array = []
	if shut != null:
		for b in shut.get_children():
			got_shut.append(str(b.get("text")))
	want_shut.sort()
	got_shut.sort()
	_expect(shut != null and got_shut == want_shut and not want_shut.is_empty(),
		"%s：闭柜货钮 %d 枚 = 柜外货名（%s）" % [tag, got_shut.size(), "、".join(got_shut)])

	var footer: Node = _main.get("_page_footer")
	var foot: PackedStringArray = []
	if footer != null:
		for b in footer.get_children():
			if b is Button:
				foot.append(str(b.get("text")))
	_expect("明日再看" in foot and "离开" in foot, "%s：页脚两钮「%s」" % [tag, "」「".join(foot)])

	var empty: PackedStringArray = []
	var all_nodes: Array = []
	_texts_under(cc, all_nodes)
	for c in all_nodes:
		if (c as Control).is_visible_in_tree() and str(c.get("text")) == "":
			empty.append(str(c.name))
	_expect(empty.is_empty() and all_nodes.size() >= 30,
		"%s：页里看得见的 %d 枚 Label / Button 都有字（空字：%s）" % [tag, all_nodes.size(), "无" if empty.is_empty() else "、".join(empty)])


func _good_name(gid: String) -> String:
	return str(root.get_node("/root/GameManager").get_good_name(gid))


## 一 + 三：三种页面各整页重排一遍，数带字进树的字控件，再核页上的字
func _quiet_enter() -> void:
	print("── 一、整页重排时牙行页里带着字进树的 Label / Button 为 0 枚；三、重排完页上的字一样不缺")
	var port := "quanzhou"
	# (a) 委办未接、细则展开：委办栏的细则行全建
	_reset(port, 5000, ["sampan"])
	_main.set("_contract_detail_open", true)
	_main.set("_market_ship", 0)
	_main.load_scene(port + "_market")
	await _settle(2)
	var a: Array = await _count_rerender(port + "_market")
	_expect(int(a[0]) >= 40 and int(a[1]) == 0,
		"委办未接（细则展开）：重排进树 %d 枚字控件，带着字进树 %d 枚%s" % [a[0], a[1], "" if a[2] == "" else "（如：%s）" % a[2]])
	_page_texts_ok(port, "委办未接", false)
	# (b) 委办在身：接下本港这月的单子
	var offer: Dictionary = gs.contract_offer(port)
	var took: bool = not offer.is_empty() and gs.accept_contract(offer)
	var b: Array = await _count_rerender(port + "_market")
	_expect(took and int(b[0]) >= 30 and int(b[1]) == 0,
		"委办在身：重排进树 %d 枚字控件，带着字进树 %d 枚%s" % [b[0], b[1], "" if b[2] == "" else "（如：%s）" % b[2]])
	_page_texts_ok(port, "委办在身", true)
	# (c) 两艘船：页首多一排「装至」选船钮
	_reset(port, 5000, ["sampan", "keel_boat"])
	_main.set("_contract_detail_open", false)
	_main.load_scene(port + "_market")
	await _settle(2)
	var c: Array = await _count_rerender(port + "_market")
	_expect(int(c[0]) >= 40 and int(c[1]) == 0,
		"两艘船（装至选船钮）：重排进树 %d 枚字控件，带着字进树 %d 枚%s" % [c[0], c[1], "" if c[2] == "" else "（如：%s）" % c[2]])
	_page_texts_ok(port, "两艘船", false)
	_main.set("_contract_detail_open", false)


## 二：按「买 1」走 Main._on_buy 真回调（扣钱、装货、整页重排），三回取最快
func _press_time() -> void:
	print("── 二、按「买 1」到整页重排完 %d 毫秒内（%d 回取最快）" % [PRESS_LIMIT_MS, PRESS_TRIES])
	var port := "quanzhou"
	var best := -1
	var gid := ""
	var bought := true
	for _t in PRESS_TRIES:
		_reset(port, 5000, ["sampan"])
		_main.set("_market_ship", 0)
		_main.load_scene(port + "_market")
		await _settle(2)
		var hand: PackedStringArray = _main.get("broker_hand")
		gid = str(hand[0])
		var q0: int = fleet.cargo_qty(gid, 0)
		var t0 := Time.get_ticks_msec()
		_main._on_buy(port, gid, 1, 0)
		var ms := Time.get_ticks_msec() - t0
		await _settle(2)
		bought = bought and fleet.cargo_qty(gid, 0) == q0 + 1
		best = ms if best < 0 else mini(best, ms)
	_expect(bought and best <= PRESS_LIMIT_MS,
		"按「买 1」（%s）到整页重排完：%d 回最快 %d 毫秒（限 %d；改前约 800）" % [_good_name(gid), PRESS_TRIES, best, PRESS_LIMIT_MS])
