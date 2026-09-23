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

## 剧情 choice 早已写出、此前 apply_effects 丢掉的账本字段。
## 不改买卖公式，只供酒馆追问、结局分支与存档对照。
var network: int = 0
var merchant_credit: int = 0
var sea_tendency: int = 0
var scholar_tendency: int = 0
var ledger_notes: Array = []

## 已了结的结局 id。空字符串表示尚未了结。
var ending_id: String = ""

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
	return maxi(0, DEBT_CEILING + title_loan_bonus() - debt)


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
	var fame_res := add_fame(fame_gain)
	return {
		"gold": gold,
		"fame": fame_gain,
		"name": d.get("name", "所见"),
		"promoted": fame_res.get("promoted", false),
		"title": fame_res.get("title", {}),
	}


func visit_port(port_id: String) -> void:
	if port_id != "" and not (port_id in visited_ports):
		visited_ports.append(port_id)


func chapter_def(n: int = -1) -> Dictionary:
	var target: int = chapter if n < 0 else n
	for c in GameManager.chapters_data.get("chapters", []):
		if int(c.get("id", 0)) == target:
			return c
	return {}


func _requirement_items(req: Dictionary) -> Array:
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
			"label": "亲至　" + GameManager.get_port_name(str(pid)),
			"current": 1 if pid in visited_ports else 0, "need": 1,
			"done": pid in visited_ports,
		})
	return items


func _requirements_ready(req) -> bool:
	if req == null or typeof(req) != TYPE_DICTIONARY:
		return false
	for it in _requirement_items(req):
		if not it["done"]:
			return false
	return true


## 当前章节晋升或结局进度。
## 返回 {ready, items, hint, final, ended}
func chapter_progress() -> Dictionary:
	if ending_id != "":
		var ended := ending_def()
		return {
			"ready": false, "items": [], "hint": "", "final": true,
			"ended": true, "ending_title": ended.get("title", ending_id),
		}

	var nxt = chapter_def().get("next_requires", null)
	if nxt != null and typeof(nxt) == TYPE_DICTIONARY:
		return {
			"ready": _requirements_ready(nxt),
			"items": _requirement_items(nxt),
			"hint": nxt.get("hint", ""),
			"final": false,
			"ended": false,
		}

	var end_req = chapter_def().get("ending_requires", null)
	if end_req != null and typeof(end_req) == TYPE_DICTIONARY:
		return {
			"ready": _requirements_ready(end_req),
			"items": _requirement_items(end_req),
			"hint": end_req.get("hint", ""),
			"final": true,
			"ended": false,
		}

	return {"ready": false, "items": [], "hint": "", "final": true, "ended": false}


## 条件达成则进下一章或了结。返回 {advanced, resolved, title, text, scene}
func try_advance_chapter() -> Dictionary:
	if ending_id != "":
		return {"advanced": false, "resolved": false}
	var prog := chapter_progress()
	if not prog.get("ready", false):
		return {"advanced": false, "resolved": false}
	if prog.get("final", false):
		return try_resolve_ending()
	var cur := chapter_def()
	chapter += 1
	return {
		"advanced": true,
		"resolved": false,
		"title": cur.get("advance_title", "新的一章"),
		"text": cur.get("advance_text", ""),
		"scene": str(cur.get("advance_scene", "")),
	}


func ending_list() -> Array:
	return chapter_def().get("endings", [])


func ending_def(eid: String = "") -> Dictionary:
	var target: String = ending_id if eid == "" else eid
	for e in ending_list():
		if str(e.get("id", "")) == target:
			return e
	return {}


func has_ended() -> bool:
	return ending_id != ""


func ending_title() -> String:
	return str(ending_def().get("title", ending_id))


## 按 endings 数组顺序取第一条旗标条件成立的结局；最后一条无旗标要求作沙盒兜底。
func pick_ending() -> Dictionary:
	for e in ending_list():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if flag_requirement_met(e):
			return e
	return {}


## 终章条件达成则按旗标了结。返回 {advanced, resolved, title, text, scene}
func try_resolve_ending() -> Dictionary:
	if ending_id != "" or not chapter_progress().get("ready", false):
		return {"advanced": false, "resolved": false}
	var picked := pick_ending()
	if picked.is_empty():
		return {"advanced": false, "resolved": false}
	ending_id = str(picked.get("id", ""))
	return {
		"advanced": false,
		"resolved": true,
		"title": picked.get("title", "了结"),
		"text": picked.get("text", ""),
		"scene": str(picked.get("scene", "")),
	}


# ── 旗标 ──────────────────────────────────────────────

func set_flag(flag_name: String) -> void:
	if flag_name != "":
		flags[flag_name] = true


func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false) == true


## 场景 / 选项 / 结局 / 酒馆钩子共用的旗标门槛。
## 认 require_flag、require_any、hide_if_flag、require_chapter。缺省为通过。
func flag_requirement_met(req: Dictionary) -> bool:
	var need := str(req.get("require_flag", ""))
	if need != "" and not has_flag(need):
		return false
	var any_flags = req.get("require_any", [])
	if typeof(any_flags) == TYPE_ARRAY and any_flags.size() > 0:
		var ok := false
		for f in any_flags:
			if has_flag(str(f)):
				ok = true
				break
		if not ok:
			return false
	var hide := str(req.get("hide_if_flag", ""))
	if hide != "" and has_flag(hide):
		return false
	var need_ch: int = int(req.get("require_chapter", 0))
	if need_ch > 0 and chapter < need_ch:
		return false
	return true


func choice_visible(choice: Dictionary) -> bool:
	return flag_requirement_met(choice)


func scene_unlocked(scene_data: Dictionary) -> bool:
	return flag_requirement_met(scene_data)


func add_ledger_note(note: String) -> void:
	if note != "" and not (note in ledger_notes):
		ledger_notes.append(note)


## 当前港口可出现的一次性剧情追问（data/chapters.json 的 story_hooks）
func story_hooks_at(port_id: String) -> Array:
	var out := []
	for h in GameManager.chapters_data.get("story_hooks", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if str(h.get("port", "")) != port_id:
			continue
		if flag_requirement_met(h):
			out.append(h)
	return out


# ── 名声换爵 ──────────────────────────────────────────

func title_ranks() -> Array:
	var out := []
	for r in GameManager.titles_data.get("ranks", []):
		if typeof(r) == TYPE_DICTIONARY:
			out.append(r)
	out.sort_custom(func(a, b): return int(a.get("min_fame", 0)) < int(b.get("min_fame", 0)))
	return out


func title_rank() -> Dictionary:
	var best := {
		"id": "san_shang", "name": "籍外散商",
		"min_fame": 0, "duty_factor": 1.0, "loan_bonus": 0,
	}
	for r in title_ranks():
		if fame >= int(r.get("min_fame", 0)):
			best = r
	return best


func next_title() -> Dictionary:
	var cur_id := str(title_rank().get("id", ""))
	var seen := false
	for r in title_ranks():
		if seen:
			return r
		if str(r.get("id", "")) == cur_id:
			seen = true
	return {}


func title_duty_factor() -> float:
	return float(title_rank().get("duty_factor", 1.0))


func title_loan_bonus() -> int:
	return int(title_rank().get("loan_bonus", 0))


func title_name() -> String:
	return str(title_rank().get("name", "籍外散商"))


## 名声可负（剧情罚没）。返回 {gained, fame, promoted, title, prev}
func add_fame(amount: int) -> Dictionary:
	var prev := title_rank()
	fame = maxi(0, fame + amount)
	var now := title_rank()
	return {
		"gained": amount,
		"fame": fame,
		"promoted": str(prev.get("id", "")) != str(now.get("id", "")),
		"title": now,
		"prev": prev,
	}


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
		total += float(g.get("base_value", 0)) * qty * Economy.tariff_rate * title_duty_factor()
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
		"martial": martial,
		"chapter": chapter,
		"pu_attention": pu_attention,
		"has_customs_permit": has_customs_permit,
		"last_port": last_port,
		"flags": flags,
		"network": network,
		"merchant_credit": merchant_credit,
		"sea_tendency": sea_tendency,
		"scholar_tendency": scholar_tendency,
		"ledger_notes": ledger_notes,
		"ending_id": ending_id,
		"discoveries_found": discoveries_found,
		"discoveries_reported": discoveries_reported,
		"visited_ports": visited_ports,
		"peak_money": peak_money,
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
	network = int(d.get("network", 0))
	merchant_credit = int(d.get("merchant_credit", 0))
	sea_tendency = int(d.get("sea_tendency", 0))
	scholar_tendency = int(d.get("scholar_tendency", 0))
	ledger_notes = d.get("ledger_notes", [])
	ending_id = str(d.get("ending_id", ""))
	discoveries_found = d.get("discoveries_found", [])
	discoveries_reported = d.get("discoveries_reported", [])
	visited_ports = d.get("visited_ports", [])
	peak_money = d.get("peak_money", money)
