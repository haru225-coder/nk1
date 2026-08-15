class_name EconomyFeel extends RefCounted

## 经济手感：把已有价格/邻港/事件差，翻译成玩家可感知的「三策」文案。
## 不改计价公式；只增加策略分支的可读性。

const MIN_ARBITRAGE_RATIO := 1.18   ## 邻港价比本港高出 18% 才提示搬货
const MIN_DUMP_RATIO := 0.82       ## 本港价低于邻港 18% 提示此处适合买进
const HOLD_HIGH_RATIO := 1.35      ## 相对基价很高 → 建议兑现
const HOLD_LOW_RATIO := 0.75       ## 相对基价很低 → 建议囤/转运


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
				"%s↔%s" % [str(arb.get("local_price", "")), str(arb.get("neighbor_price", ""))],
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


## 始终返回三条策略路径（稳 / 赌 / 搬）
static func strategy_triad(port_id: String) -> Array[String]:
	var port_name := _port_name(port_id)
	var stable := "【稳】本港即买即卖：锁定当前价，周转最快，利润薄但稳。"
	var risk := "【赌】盯事件与库存窗口：短缺未尽时可再等一潮，也可能错过高点。"
	var move := "【搬】走邻港差价：利润来自航线，代价是航程、海损与时间。"

	# 事件 / 已购情报：强化「赌」（信息差）
	var intel_line := _player_intel_tip(port_id)
	var event_line := _active_event_tip(port_id)
	if intel_line != "":
		risk = "【赌】%s — 你已付费得知，可布局或观望。" % intel_line
	elif event_line != "":
		risk = "【赌】%s — 可等余波再涨，或立刻出手避风险。" % event_line

	# 邻港差价：强化「搬」
	var arb := best_arbitrage(port_id)
	if not arb.is_empty():
		move = "【搬】「%s」本港 %d ↔ %s %d（约 %s）— 差价值得起航。" % [
			str(arb.get("good_name", "")),
			int(arb.get("local_price", 0)),
			str(arb.get("neighbor_name", "")),
			int(arb.get("neighbor_price", 0)),
			str(arb.get("direction", "")),
		]

	# 繁荣/萧条：强化「稳」或「赌」
	var market = _market()
	if market != null and market.has_method("get_prosperity"):
		var p: float = float(market.get_prosperity(port_id))
		if p < 0.9:
			stable = "【稳】%s市面萧条：少囤多走现货，避免压舱。" % port_name
		elif p > 1.1:
			stable = "【稳】%s市面繁荣：本地循环也可，不必硬闯远航。" % port_name

	return [stable, risk, move]


## 找本港 vs 邻港差价最大的货物（买卖方向均可）
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
	for g in goods:
		if not g is Dictionary:
			continue
		var gd: Dictionary = g
		if str(gd.get("category", "")) != "货物":
			continue
		var gid := str(gd.get("id", ""))
		if gid == "":
			continue
		var local_p := EconomySystem.get_price(port_id, gid)
		if local_p <= 0:
			continue
		for nid in conns:
			var np := EconomySystem.get_price(str(nid), gid)
			if np <= 0:
				continue
			var ratio_up := float(np) / float(local_p)
			var ratio_down := float(local_p) / float(np)
			var score := 0.0
			var direction := ""
			if ratio_up >= MIN_ARBITRAGE_RATIO:
				score = ratio_up
				direction = "本港买→邻港卖"
			elif ratio_down >= MIN_ARBITRAGE_RATIO:
				score = ratio_down
				direction = "邻港买→本港卖"
			else:
				continue
			if score > best_score:
				best_score = score
				best = {
					"good_id": gid,
					"good_name": str(gd.get("name", gid)),
					"local_price": local_p,
					"neighbor_id": str(nid),
					"neighbor_name": _port_name(str(nid)),
					"neighbor_price": np,
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
	var price := EconomySystem.get_price(port_id, good_id)
	if price <= 0:
		return ""
	var ratio := float(price) / float(base) if base > 0 else 1.0
	var bits: PackedStringArray = []

	if action == "buy":
		if ratio <= HOLD_LOW_RATIO:
			bits.append("价位偏低，适合进货囤转（赌窗口或搬邻港）")
		elif ratio >= HOLD_HIGH_RATIO:
			bits.append("价位偏高，进货压力大，宜少买或改卖货")
		else:
			bits.append("价位中性，可小量进货做本地周转")
		var sell_elsewhere := _best_neighbor_sell(port_id, good_id, price)
		if not sell_elsewhere.is_empty():
			bits.append("若起航：%s 约 %d（%s）" % [
				str(sell_elsewhere.get("name", "")),
				int(sell_elsewhere.get("price", 0)),
				str(sell_elsewhere.get("edge", "")),
			])
	else:
		# sell
		if ratio >= HOLD_HIGH_RATIO:
			bits.append("价位偏高，兑现更稳妥（稳）")
		elif ratio <= HOLD_LOW_RATIO:
			bits.append("价位偏低，可考虑继续压舱等窗口（赌）")
		else:
			bits.append("价位平常，卖出即回笼，亦可留货待变")
		var better := _best_neighbor_sell(port_id, good_id, price)
		if not better.is_empty() and float(better.get("price", 0)) > float(price) * MIN_ARBITRAGE_RATIO:
			bits.append("邻港更高：%s %d — 搬过去可能更赚（搬）" % [
				str(better.get("name", "")),
				int(better.get("price", 0)),
			])
		elif better.is_empty() or int(better.get("price", 0)) <= price:
			bits.append("邻港未见明显更高价，本港出手更省航程")

	if amount > 0 and price > 0:
		bits.append("此笔约 %d 钱" % (price * amount))
	if bits.is_empty():
		return ""
	return "商策：%s「%s」— %s" % [
		"买入" if action == "buy" else "卖出",
		g_name,
		" · ".join(bits),
	]


## 格式化三策为市集信息栏用
static func format_triad_block(port_id: String) -> String:
	var lines := strategy_triad(port_id)
	return "\n".join(lines)


static func _best_neighbor_sell(port_id: String, good_id: String, local_price: int) -> Dictionary:
	var port: Dictionary = GameManager.get_port_data(port_id) if GameManager else {}
	var best: Dictionary = {}
	var best_p := local_price
	for nid in port.get("connections", []):
		var np := EconomySystem.get_price(str(nid), good_id)
		if np > best_p:
			best_p = np
			var edge := ""
			if local_price > 0:
				var pct := int(round((float(np) / float(local_price) - 1.0) * 100.0))
				edge = "+%d%%" % pct
			best = {"id": str(nid), "name": _port_name(str(nid)), "price": np, "edge": edge}
	return best


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
