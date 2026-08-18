class_name EconomyFeel extends RefCounted

## 经济手感：把已有价格/邻港/事件差，翻译成玩家可感知的「三策」文案。
## 报价一律走成交价（买=挂牌，卖=收购，含价差），不改计价公式。

const MIN_ARBITRAGE_RATIO := 1.18   ## 邻港价比本港高出 18% 才提示搬货
const MIN_DUMP_RATIO := 0.82       ## 本港价低于邻港 18% 提示此处适合买进
const HOLD_HIGH_RATIO := 1.35      ## 相对基价很高 → 建议兑现
const HOLD_LOW_RATIO := 0.75       ## 相对基价很低 → 建议囤/转运
const SELL_PRICE_RATIO := 0.85     ## 与 EconomySystem.SELL_PRICE_RATIO 对齐


## 每月商情脉搏：经济表现层负责把事件、差价和繁荣度翻译为玩家文案。
static func monthly_pulse_message(last_port: String, market) -> String:
	var active: Array = []
	if WorldEventTracker != null and WorldEventTracker.has_method("get_active_events"):
		active = WorldEventTracker.get_active_events()
	if not active.is_empty():
		var ev = active[randi() % active.size()]
		var port_id := ""
		var ev_name := "市舶异动"
		if typeof(ev) == TYPE_OBJECT and ev != null:
			if "target_port" in ev:
				port_id = str(ev.target_port)
			if "event_id" in ev:
				ev_name = str(ev.event_id)
		var port_name := _port_name(port_id)
		if port_name != "":
			return "【月报商情】%s一带仍有「%s」余波，海商宜慎择航线。" % [port_name, ev_name]
		return "【月报商情】海域上传来「%s」的风声，市价恐有起伏。" % ev_name

	if last_port != "":
		var arb := best_arbitrage(last_port)
		if not arb.is_empty() and float(arb.get("score", 0.0)) >= 1.2:
			return "【月报商情】耳语：%s「%s」%s — 有人说走一趟就回本。" % [
				str(arb.get("direction", "跨港")),
				str(arb.get("good_name", "货物")),
				"%s挂牌↔%s收购" % [str(arb.get("pay_price", arb.get("local_price", ""))), str(arb.get("get_price", arb.get("neighbor_price", "")))],
			]

	var ports: Array = GameManager.ports_data.get("ports", []) if GameManager != null else []
	if ports.is_empty() or market == null:
		return "【月报商情】东海市舶平静，未见大的涨跌。"
	var pick: Dictionary = ports[randi() % ports.size()]
	var pid := str(pick.get("id", ""))
	var pname := str(pick.get("name", pid))
	var prosperity: float = market.get_prosperity(pid) if market.has_method("get_prosperity") else 1.0
	if prosperity > 1.08:
		return EconomyLog.make_prosperity_rise(pname)
	if prosperity < 0.92:
		return EconomyLog.make_prosperity_decline(pname)
	return "【月报商情】%s市舶平稳，货栈进出如常。" % pname


## 本港挂牌（买）/ 收购（卖）一对参考价。
## 运行时 load EconomySystem，避免 -s 首轮 class_name 绑到未编完的脚本。
static func quote(port_id: String, good_id: String, amount: int = 1) -> Dictionary:
	var qty := maxi(amount, 1)
	var buy := _trade_price(port_id, good_id, qty, true)
	var sell := _trade_price(port_id, good_id, qty, false)
	return {
		"buy": buy,
		"sell": sell,
	}


## 始终返回三条策略路径（稳 / 赌 / 搬）
static func strategy_triad(port_id: String) -> Array[String]:
	var port_name := _port_name(port_id)
	var spread := _sample_spread(port_id)
	var stable := "【稳】本港买卖不同价：收购低于挂牌，同货当日倒手必亏。兑现来货，或收本地特产再走。"
	if not spread.is_empty():
		stable = "【稳】本港「%s」挂牌 %d / 收购 %d（约按挂牌 %d%% 收）。同货当日倒手必亏；兑现来货或收特产再走。" % [
			str(spread.get("good_name", "")),
			int(spread.get("buy", 0)),
			int(spread.get("sell", 0)),
			int(spread.get("pct", 0)),
		]
	var risk := "【赌】盯事件与库存窗口：短缺未尽时可再等一潮，也可能错过高点。"
	var move := "【搬】利润来自邻港收购价减去本港挂牌与航程，不来自本港对倒。"

	# 事件 / 已购情报：强化「赌」（信息差）
	var intel_line := _player_intel_tip(port_id)
	var event_line := _active_event_tip(port_id)
	if intel_line != "":
		risk = "【赌】%s — 你已付费得知，可布局或观望。" % intel_line
	elif event_line != "":
		risk = "【赌】%s — 可等余波再涨，或立刻出手避风险。" % event_line

	# 邻港差价：强化「搬」（买卖各用成交价，避免虚高差价）
	var arb := best_arbitrage(port_id)
	if not arb.is_empty():
		move = "【搬】「%s」%s 挂牌 %d → %s 收购 %d（%s）— 扣航程后仍值得走。" % [
			str(arb.get("good_name", "")),
			str(arb.get("from_name", "")),
			int(arb.get("pay_price", 0)),
			str(arb.get("to_name", "")),
			int(arb.get("get_price", 0)),
			str(arb.get("direction", "")),
		]

	# 繁荣/萧条：叠在价差事实上，不改写成「本地循环可对倒」
	var market = _market()
	if market != null and market.has_method("get_prosperity"):
		var p: float = float(market.get_prosperity(port_id))
		if p < 0.9:
			stable = "【稳】%s市面萧条，收购更苛。少囤现货，同货倒手更亏。" % port_name
		elif p > 1.1:
			stable = "【稳】%s市面繁荣：可收特产待出航，但买卖仍有价差，勿本港对倒。" % port_name

	return [stable, risk, move]


## 找本港 vs 邻港差价最大的货物（买用挂牌、卖用收购，方向均可）
static func best_arbitrage(port_id: String) -> Dictionary:
	if port_id == "" or GameManager == null:
		return {}
	var port: Dictionary = GameManager.get_port_data(port_id)
	var conns: Array = port.get("connections", [])
	if conns.is_empty():
		return {}
	var goods: Array = GameManager.goods_data.get("goods", [])
	var best: Dictionary = {}
	var best_score := 0.0
	var local_name := _port_name(port_id)
	for g in goods:
		if not g is Dictionary:
			continue
		var gd: Dictionary = g
		if str(gd.get("category", "")) != "货物":
			continue
		var gid := str(gd.get("id", ""))
		if gid == "":
			continue
		var local_q := quote(port_id, gid)
		var local_buy: int = int(local_q.get("buy", 0))
		var local_sell: int = int(local_q.get("sell", 0))
		if local_buy <= 0 or local_sell <= 0:
			continue
		for nid in conns:
			var neighbor_id := str(nid)
			var nq := quote(neighbor_id, gid)
			var n_buy: int = int(nq.get("buy", 0))
			var n_sell: int = int(nq.get("sell", 0))
			if n_buy <= 0 or n_sell <= 0:
				continue
			var ratio_out := float(n_sell) / float(local_buy)
			var ratio_in := float(local_sell) / float(n_buy)
			var score := 0.0
			var direction := ""
			var pay_price := 0
			var get_price := 0
			var from_name := ""
			var to_name := ""
			var shown_local := 0
			var shown_neighbor := 0
			if ratio_out >= MIN_ARBITRAGE_RATIO and ratio_out >= ratio_in:
				score = ratio_out
				direction = "本港买→邻港卖"
				pay_price = local_buy
				get_price = n_sell
				from_name = local_name
				to_name = _port_name(neighbor_id)
				shown_local = local_buy
				shown_neighbor = n_sell
			elif ratio_in >= MIN_ARBITRAGE_RATIO:
				score = ratio_in
				direction = "邻港买→本港卖"
				pay_price = n_buy
				get_price = local_sell
				from_name = _port_name(neighbor_id)
				to_name = local_name
				shown_local = local_sell
				shown_neighbor = n_buy
			else:
				continue
			if score > best_score:
				best_score = score
				best = {
					"good_id": gid,
					"good_name": str(gd.get("name", gid)),
					"local_price": shown_local,
					"neighbor_id": neighbor_id,
					"neighbor_name": _port_name(neighbor_id),
					"neighbor_price": shown_neighbor,
					"from_name": from_name,
					"to_name": to_name,
					"pay_price": pay_price,
					"get_price": get_price,
					"direction": direction,
					"score": score,
				}
	return best


## 选中商品时的决策提示（买/卖各有三种读法）
static func trade_decision_hint(port_id: String, good_id: String, action: String, amount: int = 0) -> String:
	if port_id == "" or good_id == "":
		return ""
	var g_data: Dictionary = GameManager.get_good_data(good_id) if GameManager else {}
	var g_name := str(g_data.get("name", good_id))
	var base := int(g_data.get("base_value", g_data.get("base_price", 0)))
	var qty := maxi(amount, 1)
	var q := quote(port_id, good_id, qty)
	var buy_p: int = int(q.get("buy", 0))
	var sell_p: int = int(q.get("sell", 0))
	var is_buy := action == "buy"
	var price: int = buy_p if is_buy else sell_p
	if price <= 0:
		return ""
	var ratio := float(price) / float(base) if base > 0 else 1.0
	var bits: PackedStringArray = []
	bits.append("本港挂牌 %d / 收购 %d" % [buy_p, sell_p])

	if is_buy:
		if ratio <= HOLD_LOW_RATIO:
			bits.append("挂牌偏低，适合进货囤转（赌窗口或搬邻港）")
		elif ratio >= HOLD_HIGH_RATIO:
			bits.append("挂牌偏高，进货压力大，宜少买或改卖货")
		else:
			bits.append("挂牌中性；同货当场卖出会亏价差")
		var sell_elsewhere := _best_neighbor_sell(port_id, good_id, buy_p)
		if not sell_elsewhere.is_empty() and float(sell_elsewhere.get("price", 0)) > float(buy_p) * MIN_ARBITRAGE_RATIO:
			bits.append("若起航：%s 收购约 %d（%s）" % [
				str(sell_elsewhere.get("name", "")),
				int(sell_elsewhere.get("price", 0)),
				str(sell_elsewhere.get("edge", "")),
			])
	else:
		if ratio >= HOLD_HIGH_RATIO:
			bits.append("收购偏高，兑现更稳妥（稳）")
		elif ratio <= HOLD_LOW_RATIO:
			bits.append("收购偏低，可考虑继续压舱等窗口（赌）")
		else:
			bits.append("收购平常，卖出即回笼，亦可留货待变")
		var better := _best_neighbor_sell(port_id, good_id, sell_p)
		if not better.is_empty() and float(better.get("price", 0)) > float(sell_p) * MIN_ARBITRAGE_RATIO:
			bits.append("邻港收购更高：%s %d — 搬过去可能更赚（搬）" % [
				str(better.get("name", "")),
				int(better.get("price", 0)),
			])
		elif better.is_empty() or int(better.get("price", 0)) <= sell_p:
			bits.append("邻港未见明显更高收购价，本港出手更省航程")

	if amount > 0 and price > 0:
		bits.append("此笔约 %d 钱" % (price * amount))
	if bits.is_empty():
		return ""
	return "商策：%s「%s」— %s" % [
		"买入" if is_buy else "卖出",
		g_name,
		" · ".join(bits),
	]


## 格式化三策为市集信息栏用
static func format_triad_block(port_id: String) -> String:
	var lines := strategy_triad(port_id)
	return "\n".join(lines)


static func _best_neighbor_sell(port_id: String, good_id: String, vs_price: int = 0) -> Dictionary:
	var port: Dictionary = GameManager.get_port_data(port_id) if GameManager else {}
	var best: Dictionary = {}
	var best_p := 0
	for nid in port.get("connections", []):
		var np := int(quote(str(nid), good_id).get("sell", 0))
		if np > best_p:
			best_p = np
			best = {"id": str(nid), "name": _port_name(str(nid)), "price": np, "edge": ""}
	if best_p > 0 and vs_price > 0:
		best["edge"] = "%+d%%" % int(round((float(best_p) / float(vs_price) - 1.0) * 100.0))
	return best


static func _sample_spread(port_id: String) -> Dictionary:
	if port_id == "" or GameManager == null:
		return {}
	var goods: Array = GameManager.goods_data.get("goods", [])
	for g in goods:
		if not g is Dictionary:
			continue
		if str(g.get("category", "")) != "货物":
			continue
		var gid := str(g.get("id", ""))
		if gid == "":
			continue
		var q := quote(port_id, gid)
		var buy_p: int = int(q.get("buy", 0))
		var sell_p: int = int(q.get("sell", 0))
		if buy_p <= 0 or sell_p <= 0:
			continue
		return {
			"good_id": gid,
			"good_name": str(g.get("name", gid)),
			"buy": buy_p,
			"sell": sell_p,
			"pct": int(round(float(sell_p) / float(buy_p) * 100.0)),
		}
	return {}


static func _player_intel_tip(port_id: String) -> String:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return ""
	var gs = (loop as SceneTree).root.get_node_or_null("/root/GameState")
	if gs == null or gs.get("intel_notes") == null:
		return ""
	var book = gs.intel_notes
	if book == null or not book.has_method("list_recent"):
		return ""
	# 本港确报优先
	if port_id != "" and book.has_method("for_port"):
		var local: Array = book.for_port(port_id)
		if local.size() > 0:
			var n: Dictionary = local[local.size() - 1]
			return str(n.get("summary", ""))
	var recent: Array = book.list_recent(1)
	if recent.size() > 0:
		return str(recent[0].get("summary", ""))
	return ""


static func _active_event_tip(port_id: String) -> String:
	if WorldEventTracker == null or not WorldEventTracker.has_method("get_active_events"):
		return ""
	var market = _market()
	if market == null or not market.has_method("get_active_event_reasons"):
		return ""
	var goods: Array = GameManager.goods_data.get("goods", []) if GameManager else []
	for g in goods:
		if not g is Dictionary:
			continue
		var gid := str(g.get("id", ""))
		if str(g.get("category", "")) != "货物" or gid == "":
			continue
		var reasons = market.get_active_event_reasons(port_id, gid, WorldEventTracker.get_active_events())
		if reasons is Array and reasons.size() > 0:
			return str(reasons[0])
	return ""


static var _es_cached = null

static func _econ_script():
	if _es_cached != null and _es_cached.has_method("get_price"):
		return _es_cached
	var es = load(ResourcePaths.SCRIPT_ECONOMY_SYSTEM)
	if es != null and not es.has_method("get_price") and es.has_method("reload"):
		es.reload()
	if es != null and not es.has_method("get_price"):
		es = ResourceLoader.load(ResourcePaths.SCRIPT_ECONOMY_SYSTEM, "", ResourceLoader.CACHE_MODE_REPLACE)
	if es != null and es.has_method("get_price"):
		_es_cached = es
	return es


static func _trade_price(port_id: String, good_id: String, amount: int, is_buy: bool) -> int:
	var es = _econ_script()
	if es != null and es.has_method("get_trade_price"):
		return int(es.get_trade_price(port_id, good_id, amount, is_buy))
	if es != null and es.has_method("get_price"):
		var mid := int(es.get_price(port_id, good_id, is_buy))
		if not is_buy and mid > 0:
			return maxi(1, int(round(float(mid) * SELL_PRICE_RATIO)))
		return mid
	return 0


static func _port_name(port_id: String) -> String:
	if port_id == "" or GameManager == null:
		return port_id
	var pd: Dictionary = GameManager.get_port_data(port_id)
	return str(pd.get("name", port_id))


static func _market():
	if GameManager == null:
		return null
	var st = GameManager.get("state")
	if st == null:
		return null
	return st.get("market")
