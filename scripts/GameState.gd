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

## 纪事。序章选项与沙盒事件写在这里。
## 这些数不进 Economy.price_at_rate：物价已经由产地差和职事加成锁过。
var network: int = 0
var merchant_credit: int = 0
var sea_tendency: int = 0
var scholar_tendency: int = 0
## 账册条目 id。重复的不二次追加。
var ledger: Array = []
## 选定的结局 id。空字符串表示账还开着。选定后不可改。
var ending_id: String = ""
## 海路入港后为真。与剧情场景同名的港口（博多、流求）靠这个区分「重播正文」和「港口界面」。
var docked: bool = false

const CHRONICLE_MIN := -100
const CHRONICLE_MAX := 200
const TENDENCY_MAX := 20

## [名声门槛, 赊贷上限]。称谓与行对齐，见 FAME_RANK_TITLES。
const FAME_RANK_TABLE := [
	[0, 3000],
	[40, 3800],
	[100, 4600],
	[180, 5400],
]
const FAME_RANK_TITLES := ["散商", "客纲", "记名", "簿有名"]

const GUILD_PORTS := ["quanzhou", "hakata", "guangzhou"]
const EXAM_PORTS := ["xinghua", "quanzhou"]
const GUILD_FEE := 2000
const GUILD_CREDIT_NEED := 8
const EXAM_DAYS := 15


# ── 钱 ────────────────────────────────────────────────

## 金钱不落负数——罚没一律以现有资金为上限，欠款走 debt 而非负余额
func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	peak_money = maxi(peak_money, money)


## 名声不低于 0。剧情可以扣，扣完停在零。
func add_fame(amount: int) -> void:
	fame = maxi(0, fame + amount)


func add_network(amount: int) -> void:
	network = clampi(network + amount, CHRONICLE_MIN, CHRONICLE_MAX)


func add_merchant_credit(amount: int) -> void:
	merchant_credit = clampi(merchant_credit + amount, CHRONICLE_MIN, CHRONICLE_MAX)


func add_sea_tendency(amount: int) -> void:
	sea_tendency = clampi(sea_tendency + amount, 0, TENDENCY_MAX)


func add_scholar_tendency(amount: int) -> void:
	scholar_tendency = clampi(scholar_tendency + amount, 0, TENDENCY_MAX)


func append_ledger(note: String) -> void:
	if note == "" or note in ledger:
		return
	ledger.append(note)


func ledger_recent_text(n: int) -> String:
	if ledger.is_empty():
		return "（尚无）"
	var start := maxi(0, ledger.size() - n)
	var lines: PackedStringArray = []
	for i in range(start, ledger.size()):
		lines.append(str(ledger[i]))
	return "\n".join(lines)


func fame_title() -> String:
	var idx := 0
	for i in range(FAME_RANK_TABLE.size()):
		if fame >= int(FAME_RANK_TABLE[i][0]):
			idx = i
	if idx < FAME_RANK_TITLES.size():
		return FAME_RANK_TITLES[idx]
	return FAME_RANK_TITLES[0]


## 声望阶只改这一处上限。月息与还款不变。
func debt_ceiling() -> int:
	var ceiling := DEBT_CEILING
	for row in FAME_RANK_TABLE:
		if fame >= int(row[0]):
			ceiling = int(row[1])
	return ceiling


# ── 赊贷 ──────────────────────────────────────────────

func borrow_limit() -> int:
	return maxi(0, debt_ceiling() - debt)


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
	add_fame(fame_gain)
	add_merchant_credit(1)
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
	add_merchant_credit(3)
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


func discovery_id_by_name(discovery_name: String) -> String:
	for d in GameManager.discoveries_data.get("discoveries", []):
		if str(d.get("name", "")) == discovery_name:
			return str(d.get("id", ""))
	return ""


# ── 行会 / 贡院 / 终章 ────────────────────────────────

func join_guild(port_id: String) -> Dictionary:
	if not (port_id in GUILD_PORTS):
		return {"ok": false, "msg": "此地没有行会。"}
	var flag_name := "guild_" + port_id
	if has_flag(flag_name):
		return {"ok": false, "already": true, "msg": "你已是此港行会中人。"}
	if merchant_credit < GUILD_CREDIT_NEED:
		return {"ok": false, "msg": "行首看了看你的名帖，摇头。商誉还差一截，眼下不收。"}
	if not spend_money(GUILD_FEE):
		return {"ok": false, "msg": "入行要 %d 钱。你囊中不够。" % GUILD_FEE}
	add_merchant_credit(4)
	add_network(2)
	set_flag(flag_name)
	append_ledger(flag_name)
	return {"ok": true, "msg": "行首收下 %d 钱，在册上添了你的名字。" % GUILD_FEE}


## 每章一次。士人倾向不低于海路倾向时记 exam_sat。
func sit_exam() -> Dictionary:
	var once := "exam_sat_ch%d" % chapter
	if has_flag(once):
		return {"ok": false, "msg": "这一章的贡院你已经坐过。下一章再来。"}
	set_flag(once)
	GameManager.advance_days(EXAM_DAYS)
	if scholar_tendency >= sea_tendency:
		add_fame(4)
		add_scholar_tendency(2)
		set_flag("exam_sat")
		return {"ok": true, "scholar": true, "msg": "你在号房里坐了十五日。策问写完的时候，海图还压在书箱底。"}
	add_fame(1)
	add_sea_tendency(1)
	return {"ok": true, "scholar": false, "msg": "卷子铺开，字却往水路那边斜。十五日下来，你知道自己写的不是策论。"}


func ending_matches(e: Dictionary) -> bool:
	if ending_id != "":
		return false
	var req: Dictionary = e.get("requires", {})
	if chapter < int(req.get("min_chapter", 1)):
		return false
	if discoveries_reported.size() < int(req.get("min_reported", 0)):
		return false
	if network < int(req.get("min_network", 0)):
		return false
	var any_flags: Array = req.get("any_flags", [])
	if any_flags.is_empty():
		return true
	for f in any_flags:
		if has_flag(str(f)):
			return true
	return false


func endings_at(port_id: String) -> Array:
	var out: Array = []
	for e in GameManager.endings_data.get("endings", []):
		var where: Array = e.get("where", [])
		if not (port_id in where):
			continue
		if ending_matches(e):
			out.append(e)
	return out


func ending_def() -> Dictionary:
	if ending_id == "":
		return {}
	for e in GameManager.endings_data.get("endings", []):
		if str(e.get("id", "")) == ending_id:
			return e
	return {}


func choose_ending(ending_pick: String, port_id: String) -> Dictionary:
	if ending_id != "":
		return {"ok": false, "msg": "这本账已经合上了。"}
	for e in endings_at(port_id):
		if str(e.get("id", "")) == ending_pick:
			ending_id = ending_pick
			return {"ok": true, "title": str(e.get("title", "")), "text": str(e.get("text", ""))}
	return {"ok": false, "msg": "这一页现在还合不上。"}


## 年份进入 1268 或 1276 时各一句。不改钱、不改章、不改结局资格。
func note_historical_year(year: int) -> String:
	if year == 1268 and not has_flag("heard_1268"):
		set_flag("heard_1268")
		return "临安有船带来唱第的消息。埠头上有人说，殿试头名是兴化人，名字被御笔改过一笔。"
	if year == 1276 and not has_flag("heard_1276"):
		set_flag("heard_1276")
		return "北方来的船稀了。有人在埠头压低声音说，临安已不在宋人手里，兴化的信断了几个月。"
	return ""


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
				add_merchant_credit(-4)
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
		add_merchant_credit(-4)
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
		"discoveries_found": discoveries_found,
		"discoveries_reported": discoveries_reported,
		"visited_ports": visited_ports,
		"peak_money": peak_money,
		"network": network,
		"merchant_credit": merchant_credit,
		"sea_tendency": sea_tendency,
		"scholar_tendency": scholar_tendency,
		"ledger": ledger,
		"ending_id": ending_id,
		"docked": docked,
	}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", 1000)
	debt = d.get("debt", 0)
	fame = maxi(0, int(d.get("fame", 0)))
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
	network = clampi(int(d.get("network", 0)), CHRONICLE_MIN, CHRONICLE_MAX)
	merchant_credit = clampi(int(d.get("merchant_credit", 0)), CHRONICLE_MIN, CHRONICLE_MAX)
	sea_tendency = clampi(int(d.get("sea_tendency", 0)), 0, TENDENCY_MAX)
	scholar_tendency = clampi(int(d.get("scholar_tendency", 0)), 0, TENDENCY_MAX)
	var led = d.get("ledger", [])
	ledger = led if typeof(led) == TYPE_ARRAY else []
	ending_id = str(d.get("ending_id", ""))
	docked = bool(d.get("docked", false))
