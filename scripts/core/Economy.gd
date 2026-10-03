extends Node
## 港口行情。大航海时代 II 式的供需模型：
##   价格 = 基准价 × 产地/消费地系数 × 行情指数
## 玩家大量买卖会冲击行情指数，随日期推移向 1.0 回归。

## 产地便宜、消费地昂贵——差价的唯一来源。
const ROLE_MOD := {"origin": 0.65, "normal": 1.0, "consumer": 1.75}

const RATE_MIN := 0.40
const RATE_MAX := 2.20
## 每日向 1.0 回归的比例。0.045 约合 15 日回复一半——跑一趟近海回来行情已缓过大半，
## 否则同一条商路走两次就废了。
const RECOVERY := 0.045
## 围城（besieged）期间米行情每日回归的目标：与月初围城冲击 1.0 + 0.8 同档，围多久米价就撑多久
const SIEGE_GRAIN_TARGET := 1.8

## 市舶司抽解（进口税），随货物与港口可调
var tariff_rate: float = 0.10
## 牙人佣金，卖出时扣
var broker_fee: float = 0.05

## 同港价差地板。通事的议价是双向的（压买价又抬卖价），杂事又同时缩小抽解与佣金，
## 而抽解与佣金正是唯一阻止「原地买入立刻卖出」的价差——10%+5% 的毛价差撑不起满级
## 通事 ±21% 的双向议价，满编时同港卖价会高过买价，站着不动就能无限印钱，且不出港
## 故 customs_inspection 永不触发。与城墙无上限（GameState.SIEGE_WALL_MAX）是同一类错误。
## 这条不靠调参维持、靠结构维持：任何修饰组合下同港买价恒 ≥ 卖价 × 此值。
const PRICE_SPREAD_MIN := 1.08

## {port_id: {good_id: rate}}
var rates: Dictionary = {}
## {port_id: level} 市舶修埠等级，0 表示未投
var investments: Dictionary = {}

## ── 战况 ──────────────────────────────────────────────
## 港口战况是 Calendar 的纯函数：ports.json 每港 `war: {"YYYY-MM": status}`，取 ≤ 当月的最新一条。
## 不入存档；读档后按日期自然复原。状态只改参数（抽解、缉私、开市、可达），不开场景。
const WAR_STATUSES := ["loyal", "contested", "besieged", "fallen", "closed"]
const WAR_LABEL := {
	"loyal": "", "contested": "对峙", "besieged": "围城", "fallen": "已降元", "closed": "封港",
}
## 抽解倍率：降元港口抽解加倍；对峙期两边都要打点
const WAR_TARIFF := {"loyal": 1.0, "contested": 1.2, "besieged": 1.0, "fallen": 2.0, "closed": 1.0}
## 缉私倍率（GameState.customs_inspection 读）
const WAR_INSPECTION := {"loyal": 1.0, "contested": 1.3, "besieged": 1.0, "fallen": 2.0, "closed": 1.0}

var _initialized: bool = false


func _ready() -> void:
	# GameManager 是先注册的 autoload，此时 JSON 已加载
	initialize()


func initialize() -> void:
	if _initialized:
		return
	var ports: Array = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return
	for p in ports:
		var pid: String = p.get("id", "")
		var market: Dictionary = p.get("market", {})
		var port_rates := {}
		for gid in market.keys():
			# 开局给每个港口一点随机扰动，避免所有存档行情一致
			port_rates[gid] = randf_range(0.85, 1.15)
		rates[pid] = port_rates
	_initialized = true


# ── 查询 ──────────────────────────────────────────────

func _port_def(port_id: String) -> Dictionary:
	for p in GameManager.ports_data.get("ports", []):
		if p.get("id") == port_id:
			return p
	return {}


func _good_def(good_id: String) -> Dictionary:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g
	return {}


## 该港是否交易此货
func is_traded(port_id: String, good_id: String) -> bool:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.has(good_id)


## 该港交易的所有货物 id
func goods_at(port_id: String) -> Array:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.keys()


func get_role(port_id: String, good_id: String) -> String:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.get(good_id, "normal")


func get_rate(port_id: String, good_id: String) -> float:
	return rates.get(port_id, {}).get(good_id, 1.0)


## 杂事压低抽解与佣金；通事在异国港口另有议价之利；职衔再折一层抽解；
## 战况（本地 main）：降元港抽解加倍、站蒲家后泉州八折——走 _base_tariff(port_id)
func _effective_tariff(port_id: String = "") -> float:
	return _base_tariff(port_id) * Crew.trade_cost_factor() * GameState.title_duty_factor()


## 市舶抽解的实际税率（战况 × 站蒲家 × 杂事 × 职衔），给 GameState.customs_duty 办引用。
## 买价里的抽解与验引抽解是同一个市舶司的税，吃同一套倍率；两处只在计税基数上分工：
## 买价按本港成交价（产地/消费地 × 行情 × 修埠）随单付，验引按 base_value 定额报舱货。
## 牙人佣金是 broker_fee，只在卖价里扣，不是抽解。见 docs/市舶验引与牙行抽解.md。
func duty_rate(port_id: String = "") -> float:
	return _effective_tariff(port_id)


func _effective_broker() -> float:
	return broker_fee * Crew.trade_cost_factor() * GameState.title_duty_factor()


func _invest_cfg() -> Dictionary:
	var cfg = GameManager.titles_data.get("invest", {})
	return cfg if typeof(cfg) == TYPE_DICTIONARY else {}


func investment_level(port_id: String) -> int:
	return int(investments.get(port_id, 0))


func invest_max_level() -> int:
	return int(_invest_cfg().get("max_level", 5))


func invest_cost(port_id: String) -> int:
	var lv := investment_level(port_id)
	var costs = _invest_cfg().get("costs", [])
	if typeof(costs) != TYPE_ARRAY or lv >= costs.size() or lv >= invest_max_level():
		return 0
	return int(costs[lv])


func invest_edge(port_id: String) -> float:
	return float(_invest_cfg().get("edge_per_level", 0.025)) * float(investment_level(port_id))


func invest_fame_gain(new_level: int) -> int:
	return int(_invest_cfg().get("fame_base", 3)) + new_level


## 向本港投钱修埠。返回 {ok, msg, level, cost, fame, promoted, title}
func invest(port_id: String) -> Dictionary:
	if port_id == "" or _port_def(port_id).is_empty():
		return {"ok": false, "msg": "【修埠】查无此港。"}
	var cost := invest_cost(port_id)
	if cost <= 0:
		return {"ok": false, "msg": "【修埠】本港埠头已修至顶等。"}
	if not GameState.spend_money(cost):
		return {"ok": false, "msg": "【修埠】动工须 %d 钱，囊中不足。" % cost}
	var lv := investment_level(port_id) + 1
	investments[port_id] = lv
	var fame_res: Dictionary = GameState.add_fame(invest_fame_gain(lv))
	var title_name := str(fame_res.get("title", {}).get("name", GameState.title_name()))
	var msg := "【修埠】向%s投下 %d 钱，埠头升为 %d 等。名声加 %d。" % [
		GameManager.get_port_name(port_id), cost, lv, fame_res.get("gained", 0),
	]
	if fame_res.get("promoted", false):
		msg += "市舶司案册改题「%s」。" % title_name
	return {
		"ok": true, "msg": msg, "level": lv, "cost": cost,
		"fame": fame_res.get("gained", 0),
		"promoted": fame_res.get("promoted", false),
		"title": fame_res.get("title", {}),
	}


## 定价的唯一出处。estimate_* 逐单位推演时也走这里，避免公式分叉。
##
## 价差地板的裁法（改公式时 tools/verify_economy.py 的 price_with_crew 必须同步）：
## 卖价先封顶在「光杆买价 ÷ 地板」，超出的部分改从买价折扣里扣回来；且买、卖两侧
## 都不得劣于光杆——只压卖价的话，雇齐 400 钱/月的杂事通事反而比光杆赚得少。
func price_at_rate(port_id: String, good_id: String, rate: float, is_buy: bool) -> int:
	var base: float = float(_good_def(good_id).get("base_value", 0))
	var role := get_role(port_id, good_id)
	var mod: float = ROLE_MOD.get(role, 1.0)
	var edge := Crew.interpreter_edge(port_id)
	var v := base * mod * rate
	var ie := invest_edge(port_id)
	if role == "origin":
		v *= (1.0 - ie)
	elif role == "consumer":
		v *= (1.0 + ie)
	var bare_buy := v * (1.0 + _base_tariff(port_id))
	var bare_sell := v * (1.0 - broker_fee)
	var cap := bare_buy / PRICE_SPREAD_MIN
	var sell_v := minf(v * (1.0 - _effective_broker()) * (1.0 + edge), cap)
	sell_v = maxf(sell_v, minf(bare_sell, cap))
	if not is_buy:
		return int(round(sell_v))
	var buy_v := maxf(v * (1.0 + _effective_tariff(port_id)) * (1.0 - edge), sell_v * PRICE_SPREAD_MIN)
	return int(round(minf(buy_v, maxf(bare_buy, sell_v * PRICE_SPREAD_MIN))))


## 玩家买入单价（含抽解）
func buy_price(port_id: String, good_id: String) -> int:
	return price_at_rate(port_id, good_id, get_rate(port_id, good_id), true)


## 玩家卖出单价（扣牙人佣金）
func sell_price(port_id: String, good_id: String) -> int:
	return price_at_rate(port_id, good_id, get_rate(port_id, good_id), false)


## 给玩家看的行情标签
func price_hint(port_id: String, good_id: String) -> String:
	var role: String = get_role(port_id, good_id)
	var rate: float = get_rate(port_id, good_id)
	var base_hint := ""
	match role:
		"origin":
			base_hint = "本地所产"
		"consumer":
			base_hint = "此地紧缺"
		_:
			base_hint = ""
	var rate_hint := ""
	if rate >= 1.35:
		rate_hint = "价腾"
	elif rate >= 1.12:
		rate_hint = "价昂"
	elif rate <= 0.65:
		rate_hint = "价贱"
	elif rate <= 0.88:
		rate_hint = "价略平"
	if base_hint != "" and rate_hint != "":
		return base_hint + "・" + rate_hint
	return base_hint + rate_hint


# ── 战况 ──────────────────────────────────────────────

func _ym_now() -> String:
	return "%04d-%02d" % [Calendar.year, Calendar.month]


## 当前战况。无 war 表或尚未到任何节点则 loyal。
func war_status(port_id: String) -> String:
	var war: Dictionary = _port_def(port_id).get("war", {})
	if war.is_empty():
		return "loyal"
	var now := _ym_now()
	var best_date := ""
	var best := "loyal"
	for ym in war.keys():
		var k := str(ym)
		if k <= now and k > best_date:
			best_date = k
			best = str(war[ym])
	return best


func war_label(port_id: String) -> String:
	return WAR_LABEL.get(war_status(port_id), "")


## 围城 / 封港时牙行闭门
func is_market_open(port_id: String) -> bool:
	return not (war_status(port_id) in ["besieged", "closed"])


## 封港不可抵达（文永之役后的博多等）
func is_port_reachable(port_id: String) -> bool:
	return war_status(port_id) != "closed" and not GameState.is_port_banned(port_id)


func inspection_factor(port_id: String) -> float:
	return WAR_INSPECTION.get(war_status(port_id), 1.0)


## 海上时玩家「所在位置」那一港（SeaChart._refresh_status 随船况写：按船标当前坐标取最近的港；海图退场清空）。
## on_month_changed 在海上按它挑本批最后发的那条战况，与港页按 last_port 挑同一条规矩（lane w19-g9）；空串即不挑
var sea_here := ""


## 「所在位置」取港入口：按船标当前经纬度取离得最近的港（lane w20-a5，修 w19-g9 遗留的里程过半判法），
## 沿途中间港（航线折线傍过的他港）也在候选里。实现放 Voyage（港位真坐标 ports.json lat/lon、大圆距离那一套在那边）。
## 等远先报到的那港——GDScript Dictionary 循序即 ports.json 数据序，「约定熟路排在先」。
func nearest_sea_port(origin_id: String, dest_id: String, traveled_li: float) -> String:
	return Voyage.nearest_sea_port(origin_id, dest_id, traveled_li)


## 月初由 GameManager 调用：本月进入新战况的港口，给一次行情冲击，并返回通告文本。
## 冲击是一次性的，之后仍按 RECOVERY 回归——战争抬高的米价会慢慢落，但税不会。
## 通告按节点覆写：ports.json 每港可选 war_notice {"YYYY-MM": 文案}（不带【战况】头），当月有就用它，
## 没有才用下面按战况写的通用句（通用「已降元」对开城降的港口是对的，破城巷战的节点另写）。冲击照战况值给，与文案无关。
func on_month_changed() -> Array:
	var notices := []
	# 玩家当前所在港页的那条排到本批最后发：记事栏新的在上、状态条取最上一条，站兴化城页时
	# 冬月初一最上是「兴化城破」，不是 ports 次序排在后面的海口那条（lane fx7）；其余照 ports 原序。
	# 海上挑 sea_here（海图札记最上是近处那港的战况，lane w19-g9）；海图没起（涵江七日航程）时为空、不挑
	var here: String = sea_here if Fleet.at_sea else str(GameState.last_port)
	var here_lines := []
	var now := _ym_now()
	for p in GameManager.ports_data.get("ports", []):
		var war: Dictionary = p.get("war", {})
		if not war.has(now):
			continue
		var pid: String = p.get("id", "")
		var status := str(war[now])
		var line := ""
		match status:
			"besieged":
				_shift_rate(pid, "grain", 0.8)
				line = "【战况】%s被围。城中米价腾贵，牙行闭门。" % p.get("name", pid)
			"fallen":
				_shift_rate(pid, "grain", 0.5)
				for gid in goods_at(pid):
					if gid != "grain":
						_shift_rate(pid, gid, -0.15)
				line = "【战况】%s已降元。市舶司换了旗，抽解加倍，缉私加严。" % p.get("name", pid)
			"contested":
				line = "【战况】%s两军对峙，港内船只都在名册上。" % p.get("name", pid)
			"closed":
				line = "【战况】%s封港，海路不通。" % p.get("name", pid)
			"loyal":
				line = "【战况】%s复归宋土。" % p.get("name", pid)
		var custom := str((p.get("war_notice", {}) as Dictionary).get(now, ""))
		if custom != "":
			line = "【战况】" + custom
		if line != "":
			(here_lines if pid == here else notices).append(line)
	notices.append_array(here_lines)
	return notices


## 新闻市场副作用（data/news.json 可选 `market: {good_id, mul, ports?}`）。
## 投放当月把该货行情乘以 mul 一次，之后仍按 RECOVERY 回归 1.0——恐慌是一阵风，不是价带。
## ports 省略则凡交易此货的港口皆受波及。返回实际受冲击的港口 id。
func apply_news_market(m: Dictionary) -> Array:
	var hit := []
	var gid := str(m.get("good_id", ""))
	var mul := float(m.get("mul", 1.0))
	if gid == "" or mul <= 0.0 or is_equal_approx(mul, 1.0):
		return hit
	var pids: Array = m.get("ports", rates.keys())
	for pid in pids:
		if not rates.has(pid) or not rates[pid].has(gid):
			continue
		rates[pid][gid] = clampf(float(rates[pid][gid]) * mul, RATE_MIN, RATE_MAX)
		hit.append(pid)
	return hit


# ── 交易冲击 ──────────────────────────────────────────

func _depth(port_id: String) -> float:
	var base := float(_port_def(port_id).get("depth", 100))
	return base * (1.0 + float(_invest_cfg().get("depth_per_level", 0.12)) * float(investment_level(port_id)))


func _shift_rate(port_id: String, good_id: String, delta: float) -> void:
	if not rates.has(port_id):
		return
	var r: float = rates[port_id].get(good_id, 1.0)
	rates[port_id][good_id] = clampf(r + delta, RATE_MIN, RATE_MAX)


## 玩家买入 amount 单位后推高价格
func apply_buy_impact(port_id: String, good_id: String, amount: int) -> void:
	_shift_rate(port_id, good_id, float(amount) / _depth(port_id))


## 玩家卖出 amount 单位后压低价格——一次性倾销会砸盘
func apply_sell_impact(port_id: String, good_id: String, amount: int) -> void:
	_shift_rate(port_id, good_id, -float(amount) / _depth(port_id))


## 预估卖出总收入，逐单位结算以体现砸盘效应。行情砸到 RATE_MIN 之后单价不再变，余下件数一次乘完
## （与逐件累加同数；大舱轻货一次卖上千件也不逐件推）。
func estimate_sell_revenue(port_id: String, good_id: String, amount: int) -> int:
	var total := 0
	var depth := _depth(port_id)
	var r := get_rate(port_id, good_id)
	for i in range(amount):
		if r == RATE_MIN:
			return total + price_at_rate(port_id, good_id, r, false) * (amount - i)
		total += price_at_rate(port_id, good_id, r, false)
		r = clampf(r - 1.0 / depth, RATE_MIN, RATE_MAX)
	return total


## 预估买入总支出（逐件加价；与 affordable_qty 走同一条序列 _walk_buy）
func estimate_buy_cost(port_id: String, good_id: String, amount: int) -> int:
	return int(_walk_buy(port_id, good_id, amount, -1)[1])


## 现银 money 按逐件加价最多买得起几件（不超过 cap），与 estimate_buy_cost 同一条序列，一趟走完。
## 牙行「买满」原先从舱位件数起逐件往下减、每减一件把总价从头推一遍，件数平方级：开局小艍买经卷
## 卡 2 秒，客舟、大船买轻货卡几十秒到几分钟（lane w53-3）。
func affordable_qty(port_id: String, good_id: String, money: int, cap: int) -> int:
	return int(_walk_buy(port_id, good_id, cap, maxi(0, money))[0])


## 逐件买入推演：从现行情起每件报价，报完行情加 1/depth（封顶 RATE_MAX）。买满 cap 件即停；budget ≥ 0 时
## 付不起下一件也停。行情顶到 RATE_MAX 之后单价不再变，余下件数一次算完。返回 [件数, 总价]。
func _walk_buy(port_id: String, good_id: String, cap: int, budget: int) -> Array:
	var qty := 0
	var total := 0
	var depth := _depth(port_id)
	var r := get_rate(port_id, good_id)
	while qty < cap:
		var p := price_at_rate(port_id, good_id, r, true)
		if r == RATE_MAX:
			var n := cap - qty
			if budget >= 0 and p > 0:
				n = mini(n, (budget - total) / p)
			return [qty + n, total + p * n]
		if budget >= 0 and total + p > budget:
			break
		total += p
		qty += 1
		r = clampf(r + 1.0 / depth, RATE_MIN, RATE_MAX)
	return [qty, total]


# ── 日推进 ────────────────────────────────────────────

func on_day_passed() -> void:
	for pid in rates.keys():
		var port_rates: Dictionary = rates[pid]
		# 围城期间米价回归的目标抬到 SIEGE_GRAIN_TARGET：月初那一冲之后不再逐日落回平年价（验收 09-28：围得越久粮越便宜）
		var besieged := war_status(str(pid)) == "besieged"
		for gid in port_rates.keys():
			var r: float = port_rates[gid]
			if besieged and gid == "grain":
				port_rates[gid] = r + (SIEGE_GRAIN_TARGET - r) * RECOVERY
			else:
				port_rates[gid] = r + (1.0 - r) * RECOVERY


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"rates": rates, "tariff": tariff_rate, "broker": broker_fee,
		"investments": investments,
	}


func from_dict(d: Dictionary) -> void:
	rates = d.get("rates", {})
	tariff_rate = d.get("tariff", 0.10)
	broker_fee = d.get("broker", 0.05)
	investments = d.get("investments", {})
	_initialized = true


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══

func _base_tariff(port_id: String = "") -> float:
	var war_mul: float = WAR_TARIFF.get(war_status(port_id), 1.0) if port_id != "" else 1.0
	# 对峙期站了蒲家：泉州抽解永久八折——「都是一家人」
	if port_id == "quanzhou" and GameState.has_flag("sided_pu"):
		war_mul *= 0.8
	return tariff_rate * war_mul


## 杂事压低抽解与佣金；通事在异国港口另有议价之利；降元港口抽解加倍
