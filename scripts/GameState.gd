extends Node
## 玩家身份状态：钱、名声、章节、旗标、市舶司关系。
## 船与货已迁往 Fleet，时间迁往 Calendar，行情迁往 Economy。

var money: int = 1000
var fame: int = 0

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


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"money": money,
		"debt": debt,
		"fame": fame,
		"chapter": chapter,
		"pu_attention": pu_attention,
		"has_customs_permit": has_customs_permit,
		"last_port": last_port,
		"flags": flags,
		"discoveries_found": discoveries_found,
		"discoveries_reported": discoveries_reported,
		"visited_ports": visited_ports,
		"peak_money": peak_money,
	}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", 1000)
	debt = d.get("debt", 0)
	fame = d.get("fame", 0)
	chapter = d.get("chapter", 1)
	pu_attention = d.get("pu_attention", 0)
	has_customs_permit = d.get("has_customs_permit", false)
	last_port = d.get("last_port", "quanzhou")
	flags = d.get("flags", {})
	discoveries_found = d.get("discoveries_found", [])
	discoveries_reported = d.get("discoveries_reported", [])
	visited_ports = d.get("visited_ports", [])
	peak_money = d.get("peak_money", money)
