extends Node
## 玩家身份状态：钱、名声、章节、旗标、市舶司关系。
## 船与货已迁往 Fleet，时间迁往 Calendar，行情迁往 Economy。

var money: int = 1000
var fame: int = 0
## 主角武力（陈子龙）。白刃战判定输入之一；打赢海盗、夺船等会成长。
var martial: int = 50

## 蕃商赊贷。海商借贷是宋代常态——叔父正是借贷船资、货损未结才留下这笔债。
## 它同时是破产保底：一次查扣把本钱清空后，玩家仍有翻身的路。
var debt: int = 0
const DEBT_CEILING := 3000
const DEBT_MONTHLY_RATE := 0.03

## 剧情章节，决定港口与船种解锁
var chapter: int = 1

## 走私与市舶
var pu_attention: int = 0
var has_customs_permit: bool = false
var last_port: String = "quanzhou"

## 剧情旗标
var flags: Dictionary = {}

## 已勘见但未上报的发现物 id
var discoveries_found: Array = []
## 已向市舶司上报、领过赏格的发现物 id
var discoveries_reported: Array = []

## 走通过的港口 id。章节晋升要看走过多少地方，不只是攒了多少钱。
var visited_ports: Array = []
## 资金历史峰值。用峰值而非当前值判定晋升，否则买条船就把进度买没了。
var peak_money: int = 1000


# ── 钱 ────────────────────────────────────────────────

## 金钱不落负数——罚没一律以现有资金为上限，欠款走 debt 而非负余额
func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	peak_money = maxi(peak_money, money)


# ── 赊贷 ──────────────────────────────────────────────

func borrow_limit() -> int:
	return maxi(0, DEBT_CEILING - debt)


func borrow(amount: int) -> bool:
	if amount <= 0 or amount > borrow_limit():
		return false
	debt += amount
	add_money(amount)
	return true


func repay(amount: int) -> int:
	var actual: int = mini(mini(amount, debt), money)
	if actual <= 0:
		return 0
	debt -= actual
	add_money(-actual)
	return actual


## 每月结息，由 GameManager 在月份翻页时调用
func accrue_interest() -> int:
	if debt <= 0:
		return 0
	var interest := int(ceil(debt * DEBT_MONTHLY_RATE))
	debt += interest
	return interest


func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	return true


# ── 章节 ──────────────────────────────────────────────

## unlock 形如 "ch2"
func is_chapter_reached(unlock: String) -> bool:
	if not unlock.begins_with("ch"):
		return true
	return chapter >= int(unlock.substr(2))


# ── 发现录 ────────────────────────────────────────────

func has_found(did: String) -> bool:
	return did in discoveries_found or did in discoveries_reported


func record_discovery(did: String) -> bool:
	if did == "" or has_found(did):
		return false
	discoveries_found.append(did)
	return true


## 尚可上报的发现（已勘见、未领赏）
func unreported_discoveries() -> Array:
	return discoveries_found.duplicate()


## 上报一件，返回 {gold, fame, name}
func report_discovery(did: String) -> Dictionary:
	if not (did in discoveries_found):
		return {}
	var d := GameManager.get_discovery_by_id(did)
	var value: int = int(d.get("value", 50))
	discoveries_found.erase(did)
	discoveries_reported.append(did)
	var gold := value
	var fame_gain: int = maxi(1, value / 10)
	add_money(gold)
	fame += fame_gain
	return {"gold": gold, "fame": fame_gain, "name": d.get("name", "所见")}


func visit_port(port_id: String) -> void:
	if port_id != "" and not (port_id in visited_ports):
		visited_ports.append(port_id)


func chapter_def(n: int = -1) -> Dictionary:
	var target: int = chapter if n < 0 else n
	for c in GameManager.chapters_data.get("chapters", []):
		if int(c.get("id", 0)) == target:
			return c
	return {}


## 当前章节晋升进度。返回 {ready, items:[{label, done, current, need}], hint}
func chapter_progress() -> Dictionary:
	var req = chapter_def().get("next_requires", null)
	if req == null or typeof(req) != TYPE_DICTIONARY:
		return {"ready": false, "items": [], "hint": "", "final": true}

	var items := []

	var need_money: int = int(req.get("peak_money", 0))
	if need_money > 0:
		items.append({
			"label": "本钱", "current": peak_money, "need": need_money,
			"done": peak_money >= need_money,
		})

	var need_count: int = int(req.get("visited_count", 0))
	if need_count > 0:
		items.append({
			"label": "走通港口", "current": visited_ports.size(), "need": need_count,
			"done": visited_ports.size() >= need_count,
		})

	for pid in req.get("must_visit", []):
		items.append({
			"label": "亲至 " + GameManager.get_port_name(pid),
			"current": 1 if pid in visited_ports else 0, "need": 1,
			"done": pid in visited_ports,
		})

	var ready := true
	for it in items:
		if not it["done"]:
			ready = false
			break

	return {"ready": ready, "items": items, "hint": req.get("hint", ""), "final": false}


## 条件达成则进下一章。返回 {advanced, title, text}
func try_advance_chapter() -> Dictionary:
	var prog := chapter_progress()
	if prog.get("final", false) or not prog.get("ready", false):
		return {"advanced": false}
	var cur := chapter_def()
	chapter += 1
	return {
		"advanced": true,
		"title": cur.get("advance_title", "新的一章"),
		"text": cur.get("advance_text", ""),
	}


# ── 旗标 ──────────────────────────────────────────────

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true


func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false) == true


# ── 市舶司 ────────────────────────────────────────────

## 舱内违禁货（宋钱、铁器等）总量
func contraband_units() -> int:
	var n := 0
	for gid in Fleet.cargo.keys():
		if GameManager.get_good_by_id(gid).get("contraband", false):
			n += Fleet.cargo[gid].get("qty", 0)
	return n


## 按当前舱货估算抽解税额（办正规货引的花费）
func customs_duty() -> int:
	var total := 0.0
	for gid in Fleet.cargo.keys():
		var g := GameManager.get_good_by_id(gid)
		if g.get("contraband", false):
			continue  # 违禁货无法报关，不计入
		var qty: int = Fleet.cargo[gid].get("qty", 0)
		total += float(g.get("base_value", 0)) * qty * Economy.tariff_rate
	return maxi(20, int(round(total)))


## 办理正规货引。返回 {ok, msg}
func apply_for_permit() -> Dictionary:
	var duty := customs_duty()
	if not spend_money(duty):
		return {"ok": false, "msg": "【市舶司】抽解需 %d 钱，你囊中不足，小吏把货单推了回来。" % duty}
	has_customs_permit = true
	# 走正门会稍微降低蒲氏的疑心
	pu_attention = maxi(0, pu_attention - 5)
	var msg := "【市舶司验引】按舱货抽解 %d 钱，货引到手。" % duty
	if contraband_units() > 0:
		msg += "\n只是舱底那批违禁货并未报入明账——验引护得了正货，护不了它。"
	return {"ok": true, "msg": msg}


## 出港查验。返回 {passed, msg, confiscated}
func customs_inspection() -> Dictionary:
	var result := {"passed": true, "msg": "", "confiscated": false}
	var contraband := contraband_units()

	if has_customs_permit:
		if contraband > 0:
			# 有引也压不住违禁货，只是查出的概率低一些
			var risk := 0.25 + float(pu_attention) / 400.0
			if randf() < risk:
				result["passed"] = false
				result["confiscated"] = true
				# 罚金以现有资金为比例，不把玩家一次罚到无法翻身
				var fine: int = mini(300, maxi(50, int(money * 0.4)))
				result["msg"] = "【查扣】货引虽全，抽查却翻到了舱底。%d 件违禁之物当场起获，罚钱 %d，货引作废。" % [contraband, fine]
				_confiscate_contraband()
				add_money(-fine)
				pu_attention += 30
				has_customs_permit = false
				return result
			result["msg"] = "【市舶司验引】货引齐备，小吏草草点过舱面便放行。舱底那批东西没人去翻。"
			pu_attention += 8
			return result
		result["msg"] = "【市舶司验引】出示了泉州货引，缴过抽解，安全放行。"
		return result

	# 无引
	if pu_attention > 50:
		var fine: int = mini(500, maxi(50, int(money * 0.4)))
		result["passed"] = false
		result["confiscated"] = true
		result["msg"] = "【严重警告】蒲氏暗桩早已盯上你。市舶司当场查扣所有无证货物，罚钱 %d。" % fine
		Fleet.clear_cargo()
		add_money(-fine)
		return result

	var bribe := 50 + contraband * 10
	if money >= bribe:
		result["passed"] = true
		result["msg"] = "【惊险过关】没有货引，蒲氏眼下还未留意到你。塞了 %d 钱给小吏，强行出港。" % bribe
		add_money(-bribe)
		pu_attention += 20 + contraband * 2
	else:
		result["passed"] = false
		result["msg"] = "【遣返】没有货引，连塞给小吏的 %d 钱都拿不出。小吏毫不客气地把你轰回港内。" % bribe
	return result


func _confiscate_contraband() -> void:
	for gid in Fleet.cargo.keys().duplicate():
		if GameManager.get_good_by_id(gid).get("contraband", false):
			Fleet.remove_cargo(gid, Fleet.cargo_qty(gid))


## 出港后消耗货引（一引一航次）
func consume_permit() -> void:
	has_customs_permit = false


# ── 行情传闻 ──────────────────────────────────────────

## 传闻超过这么多日就作废。一趟近海来回大约这个量级。
const RUMOR_STALE_DAYS := 45

## {port_id: {good_id: {rate, day}}}
var rumors: Dictionary = {}


func note_rumor(port_id: String, good_id: String, rate: float) -> void:
	if port_id == "" or good_id == "":
		return
	if not rumors.has(port_id) or typeof(rumors[port_id]) != TYPE_DICTIONARY:
		rumors[port_id] = {}
	rumors[port_id][good_id] = {
		"rate": clampf(rate, Economy.RATE_MIN, Economy.RATE_MAX),
		"day": Calendar.absolute_day(),
	}


func rumor_of(port_id: String, good_id: String) -> Dictionary:
	var book = rumors.get(port_id, {})
	if typeof(book) != TYPE_DICTIONARY:
		return {}
	var rec = book.get(good_id, {})
	if typeof(rec) != TYPE_DICTIONARY or rec.is_empty():
		return {}
	var age := Calendar.absolute_day() - int(rec.get("day", 0))
	if age > RUMOR_STALE_DAYS:
		return {}
	return rec


func rumor_label(port_id: String, good_id: String) -> String:
	var rec := rumor_of(port_id, good_id)
	if rec.is_empty():
		return ""
	var sell := Economy.price_at_rate(port_id, good_id, float(rec.get("rate", 1.0)), false)
	var age := Calendar.absolute_day() - int(rec.get("day", 0))
	if age <= 0:
		return "传闻卖%d" % sell
	return "传闻卖%d·%d日前" % [sell, age]


# ── 牙行委办 ──────────────────────────────────────────

## 酬金 = 目的港逐件卖价（含砸盘推演）+ 基准价的一成二。交货本身不砸盘。
const CONTRACT_PREMIUM := 0.12
## 期限 = 针路预计日数 + 这几天余量。长航次傍岸会赶不上，短航次赶得上。
const CONTRACT_SLACK_DAYS := 3
const CONTRACT_QTY_BUDGET := 36.0
const CONTRACT_QTY_MIN := 4
const CONTRACT_QTY_MAX := 16
const CONTRACT_FINE_RATE := 0.15
const CONTRACT_FINE_MIN := 40
const CONTRACT_BASE_MIN := 15

## 空，或 {good_id, qty, remaining, dest, from, purse, unit_purse, due_day, deadline_days, voyage_days, offer_month}
var contract: Dictionary = {}
## 签发港 -> 被拒的年月序号（year * 12 + month）。只挡住签发当月再接，下个月的新单照开。
var contract_ban: Dictionary = {}


func _stable_hash(s: String) -> int:
	var h := 0
	for i in s.length():
		h = int((h * 33 + s.unicode_at(i)) % 1000003)
	return h


func _contract_seed(port_id: String) -> int:
	return _stable_hash(port_id) + Calendar.year * 12 + Calendar.month


## 当前章节能靠岸、且把这货当紧缺货收的港口。按 id 排序，月份种子才稳定。
func _contract_destinations(port_id: String, good_id: String) -> Array:
	var dests: Array = []
	for p in GameManager.unlocked_ports():
		var pid: String = p.get("id", "")
		if pid == port_id or int(p.get("depth", 0)) <= 0:
			continue
		if Economy.get_role(pid, good_id) != "consumer":
			continue
		if not Economy.is_traded(pid, good_id):
			continue
		dests.append(pid)
	dests.sort()
	return dests


## 签发当月已毁约或逾期，则本月此港不再开单。
func contract_port_closed(port_id: String) -> bool:
	return int(contract_ban.get(port_id, -1)) == Calendar.year * 12 + Calendar.month


## 本月此港的委办。同一月内货物与目的地不变；酬金按当下行情现算，接下才冻结。
func contract_offer(port_id: String) -> Dictionary:
	if not contract.is_empty():
		return {}
	if contract_port_closed(port_id):
		return {}
	var goods_ids: Array = []
	for gid in Economy.goods_at(port_id):
		var g := GameManager.get_good_by_id(str(gid))
		if g.is_empty() or not g.get("tradable", false) or g.get("contraband", false):
			continue
		if float(g.get("base_value", 0)) < CONTRACT_BASE_MIN or float(g.get("bulk", 0)) <= 0.0:
			continue
		if Economy.get_role(port_id, str(gid)) == "consumer":
			continue
		if _contract_destinations(port_id, str(gid)).is_empty():
			continue
		goods_ids.append(str(gid))
	goods_ids.sort()
	if goods_ids.is_empty():
		return {}

	var seed := _contract_seed(port_id)
	var gid: String = goods_ids[seed % goods_ids.size()]
	var dests: Array = _contract_destinations(port_id, gid)
	if dests.is_empty():
		return {}
	var known: Array = []
	for pid in dests:
		if Voyage.is_known_route(port_id, pid):
			known.append(pid)
	var pool: Array = known if not known.is_empty() else dests
	var dest: String = pool[int(seed / 7.0) % pool.size()]

	var g := GameManager.get_good_by_id(gid)
	var bulk := float(g.get("bulk", 1.0))
	var qty := clampi(int(CONTRACT_QTY_BUDGET / bulk), CONTRACT_QTY_MIN, CONTRACT_QTY_MAX)
	var trip: Dictionary = Voyage.plan(port_id, dest, Voyage.CourseOrder.RUMB)
	var days: int = int(trip.get("days", 999))
	if days >= 900 or days <= 0:
		return {}
	var sale := Economy.estimate_sell_revenue(dest, gid, qty)
	var premium := int(round(float(qty) * float(g.get("base_value", 0)) * CONTRACT_PREMIUM))
	var purse := sale + premium
	if purse <= 0:
		return {}
	var deadline := days + CONTRACT_SLACK_DAYS
	return {
		"good_id": gid,
		"qty": qty,
		"dest": dest,
		"from": port_id,
		"purse": purse,
		"premium": premium,
		"voyage_days": days,
		"deadline_days": deadline,
		"due_day": Calendar.absolute_day() + deadline,
	}


func accept_contract(offer: Dictionary) -> bool:
	if offer.is_empty() or not contract.is_empty():
		return false
	# 以按下时的现单为准。按钮上的旧酬金、旧期限不能买到一笔新的延期。
	var port := str(offer.get("from", ""))
	var live := contract_offer(port)
	if live.is_empty():
		return false
	if str(live.get("good_id", "")) != str(offer.get("good_id", "")):
		return false
	if str(live.get("dest", "")) != str(offer.get("dest", "")):
		return false
	var qty := int(live.get("qty", 0))
	var purse := int(live.get("purse", 0))
	var dest := str(live.get("dest", ""))
	var gid := str(live.get("good_id", ""))
	if qty <= 0 or purse <= 0 or dest == "" or gid == "":
		return false
	var deadline := int(live.get("deadline_days", 0))
	contract = {
		"good_id": gid,
		"qty": qty,
		"remaining": qty,
		"dest": dest,
		"from": port,
		"purse": purse,
		"unit_purse": float(purse) / float(qty),
		"paid": 0,
		"due_day": Calendar.absolute_day() + deadline,
		"deadline_days": deadline,
		"voyage_days": int(live.get("voyage_days", 0)),
		"offer_month": Calendar.year * 12 + Calendar.month,
	}
	return true


func contract_status() -> Dictionary:
	if contract.is_empty():
		return {}
	var rem := int(contract.get("remaining", 0))
	return {
		"good_id": str(contract.get("good_id", "")),
		"remaining": rem,
		"qty": int(contract.get("qty", rem)),
		"dest": str(contract.get("dest", "")),
		"from": str(contract.get("from", "")),
		"days_left": int(contract.get("due_day", 0)) - Calendar.absolute_day(),
		"pay_left": maxi(0, int(contract.get("purse", 0)) - int(contract.get("paid", 0))),
	}


## 在目的港交货。不走牙行砸盘——这是委办相对直接卖掉的好处。允许分批。
func deliver_contract(port_id: String) -> Dictionary:
	if contract.is_empty():
		return {"ok": false, "msg": "没有在身的委办。"}
	if str(contract.get("dest", "")) != port_id:
		return {"ok": false, "msg": "交货地不是这里。"}
	if Calendar.absolute_day() > int(contract.get("due_day", 0)):
		return {"ok": false, "msg": _fail_contract("逾期")}
	if int(contract.get("remaining", 0)) <= 0:
		contract = {}
		return {"ok": false, "msg": "这笔委办已经结了。"}
	var gid := str(contract.get("good_id", ""))
	var have := Fleet.cargo_qty(gid)
	if have <= 0:
		return {"ok": false, "msg": "舱里没有%s。" % GameManager.get_good_name(gid)}
	var n := mini(have, int(contract.get("remaining", 0)))
	var already := int(contract.get("paid", 0))
	var pay := int(round(float(contract.get("unit_purse", 0.0)) * float(n)))
	if int(contract.get("remaining", 0)) - n <= 0:
		pay = maxi(0, int(contract.get("purse", 0)) - already)
	if not Fleet.remove_cargo(gid, n):
		return {"ok": false, "msg": "货卸不下来。"}
	add_money(pay)
	contract["paid"] = already + pay
	contract["remaining"] = int(contract["remaining"]) - n
	if int(contract["remaining"]) <= 0:
		fame += 1
		contract = {}
		return {
			"ok": true, "done": true, "pay": pay, "qty": n,
			"msg": "委办交清，牙行付了 %d 钱。名声 +1。" % pay,
		}
	return {
		"ok": true, "done": false, "pay": pay, "qty": n,
		"remaining": int(contract["remaining"]),
		"msg": "先交了 %d 件，得 %d 钱。还欠 %d 件。" % [n, pay, int(contract["remaining"])],
	}


func abandon_contract() -> String:
	if contract.is_empty():
		return ""
	return _fail_contract("毁约")


## 日期越过 due_day 的那个早晨作废。due_day 当天仍可交货。
func tick_contract() -> String:
	if contract.is_empty():
		return ""
	if Calendar.absolute_day() <= int(contract.get("due_day", 0)):
		return ""
	return _fail_contract("逾期")


func _fail_contract(reason: String) -> String:
	if contract.is_empty():
		return ""
	var purse := int(contract.get("purse", 0))
	var fine := maxi(CONTRACT_FINE_MIN, int(round(float(purse) * CONTRACT_FINE_RATE)))
	fine = mini(fine, money)
	if fine > 0:
		spend_money(fine)
	fame = maxi(0, fame - 1)
	var good_name := GameManager.get_good_name(str(contract.get("good_id", "")))
	var dest_name := GameManager.get_port_name(str(contract.get("dest", "")))
	var issued := str(contract.get("from", ""))
	var offer_month := int(contract.get("offer_month", Calendar.year * 12 + Calendar.month))
	contract = {}
	if issued != "":
		contract_ban[issued] = offer_month
	if reason == "毁约":
		return "【毁约】%s的委办作废。牙行扣 %d 钱，名声 -1。" % [good_name, fine]
	return "【逾期】%s没能送到%s。牙行扣 %d 钱，名声 -1。" % [good_name, dest_name, fine]


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"money": money,
		"debt": debt,
		"fame": fame,
		"martial": martial,
		"chapter": chapter,
		"pu_attention": pu_attention,
		"has_customs_permit": has_customs_permit,
		"last_port": last_port,
		"flags": flags,
		"discoveries_found": discoveries_found,
		"discoveries_reported": discoveries_reported,
		"visited_ports": visited_ports,
		"peak_money": peak_money,
		"contract": contract,
		"contract_ban": contract_ban,
		"rumors": rumors,
	}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", 1000)
	debt = d.get("debt", 0)
	fame = d.get("fame", 0)
	martial = int(d.get("martial", 50))
	chapter = d.get("chapter", 1)
	pu_attention = d.get("pu_attention", 0)
	has_customs_permit = d.get("has_customs_permit", false)
	last_port = d.get("last_port", "quanzhou")
	flags = d.get("flags", {})
	discoveries_found = d.get("discoveries_found", [])
	discoveries_reported = d.get("discoveries_reported", [])
	visited_ports = d.get("visited_ports", [])
	peak_money = d.get("peak_money", money)
	rumors = d.get("rumors", {})
	if typeof(rumors) != TYPE_DICTIONARY:
		rumors = {}
	contract_ban = d.get("contract_ban", {})
	if typeof(contract_ban) != TYPE_DICTIONARY:
		contract_ban = {}
	var saved = d.get("contract", {})
	if typeof(saved) == TYPE_DICTIONARY and str(saved.get("good_id", "")) != "" and int(saved.get("remaining", 0)) > 0:
		contract = saved
		if float(contract.get("unit_purse", 0.0)) <= 0.0 and int(contract.get("qty", 0)) > 0:
			contract["unit_purse"] = float(contract.get("purse", 0)) / float(contract["qty"])
	else:
		contract = {}
