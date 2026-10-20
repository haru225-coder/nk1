class_name HeadingDraft
extends RefCounted
## 晨潮三向。风每一手最多发三个已解锁海港。
## 本章尚未亲至的必须港占第一席（章目只差泊在了结之地时，那一港占第一席），其余按顺风、短里程轮转。
## 港已封的不发（待拍板 20b，开关 port_blockade）：封港、围城、对己封港的港不进三向，海图上点它只给「港已封」；
## 剧情要去的港放行（story_pass）。
## 不在解析期写 autoload 名：class_name 登记早于 autoload，直接写会编译失败。

const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
## 兴化城与城外海口：守城、涵江两段剧情都在这两处挂卡
const XINGHUA_PORTS := ["xinghua", "xinghua_harbor"]


static func _node(node_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(node_name)


static func pool(origin: String) -> Array:
	var gm = _node("GameManager")
	var out: Array = []
	for p in gm.unlocked_ports():
		var pid := str(p.get("id", ""))
		if pid == "" or pid == origin:
			continue
		if int(p.get("depth", 0)) <= 0:
			continue
		if seal_of(pid) != "":
			continue
		out.append(p)
	return out


## 港已封的封因（待拍板 20b）：closed 封港、banned 对己封港（GameState.port_bans）、besieged 围城；
## 没封、开关 port_blockade 关着、或剧情放行（story_pass）返回 ""。
## 封港与对己封港照 Economy.is_port_reachable（写了一直没人调的那一个），围城另判（它不把围城算不可达）。
## 封不封按此刻定，只拦开航：船在海上时那港才封的，照旧抵港。
static func seal_of(pid: String) -> String:
	if pid == "" or not _Switches.on("port_blockade"):
		return ""
	var eco = _node("Economy")
	var status := str(eco.war_status(pid))
	var why := ""
	if not eco.is_port_reachable(pid):
		why = "closed" if status == "closed" else "banned"
	elif status == "besieged":
		why = "besieged"
	if why == "" or story_pass(pid):
		return ""
	return why


## 已解锁的港里此刻封着的（海图打封记用）
static func sealed_ids() -> Array:
	var out: Array = []
	for p in _node("GameManager").unlocked_ports():
		var pid := str(p.get("id", ""))
		if seal_of(pid) != "":
			out.append(pid)
	return out


## 剧情要去的港放行（20b 不把剧情卡死）。判据各照游戏里那一处抄，那边改了这里同改（qa_w53_p5_blockade_probe 逐月对账）：
##   一、在身委办的交货港：委办不因围城停表，牙行上了门闸也开侧门收先前订下的货（V0928-1 定 A+，Main._setup_market）；
##       拦了它，签单时还开着的港一封就必逾期挨罚。对己封港同样放行：单子是牙行签的，不是那港的官府。
##   二、士人线守城（同 Main._siege_due）：改名文龙、1276 年、兴化被围——守城页只在兴化城里开，海口给「入城」卡；
##       拦了兴化与兴化海口，人在海上等到城破，守城整段就没了。
##   三、涵江海口（同 Main._special_cards 涵江卡）：1277 年九、十月兴化再围，没改名、复核过旧避风澳、还没走过这条路——
##       卡挂在兴化与兴化海口两处，拦了就带不走族人。
## 章目的亲至 / 泊港（must_visit / settle_at）不放行：封港、围城只一个月到七个月（博多唐房 1274-10 至 1275-04 最长），
## 解封后照常发牌、照常钉第一席，耽搁一阵不卡死；放行了，封港就形同虚设。
static func story_pass(pid: String) -> bool:
	var gs = _node("GameState")
	var contract: Dictionary = gs.contract
	if not contract.is_empty() and str(contract.get("dest", "")) == pid:
		return true
	if not (pid in XINGHUA_PORTS) or str(_node("Economy").war_status("xinghua")) != "besieged":
		return false
	var cal = _node("Calendar")
	if gs.has_flag("renamed_wenlong"):
		return not gs.is_ended() and int(cal.year) == 1276
	return int(cal.year) == 1277 and int(cal.month) in [9, 10] \
		and gs.has_found("nameless_shelter_bay") and not gs.has_flag("ending_root_sea")


static func deal(origin: String, salt: int) -> PackedStringArray:
	var voyage = _node("Voyage")
	var ports: Array = pool(origin)
	var ids := PackedStringArray()
	for p in ports:
		ids.append(str(p.get("id", "")))
	var pin := _pinned(ids)
	var rest: Array = []
	for p in ports:
		var pid := str(p.get("id", ""))
		if pid == pin:
			continue
		rest.append({
			"id": pid,
			# 顺风按全程的风排（Voyage.route_wind_factor，与去向牌上的风同一个数）；原先取出港第一段——泉州三条线出湾同是 102 度（lane w54-voyage）
			"wf": voyage.route_wind_factor(origin, pid),
			"dist": voyage.distance_li(origin, pid),
		})
	rest.sort_custom(_before)
	var seats := PackedStringArray()
	if pin != "":
		seats.append(pin)
	if rest.is_empty():
		return seats
	var start := posmod(salt, rest.size())
	var i := 0
	while seats.size() < 3 and i < rest.size():
		var item: Dictionary = rest[(start + i) % rest.size()]
		var pid := str(item.get("id", ""))
		if pid != "" and pid not in seats:
			seats.append(pid)
		i += 1
	return seats


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var wa := float(a.get("wf", 0.0))
	var wb := float(b.get("wf", 0.0))
	if not is_equal_approx(wa, wb):
		return wa > wb
	var da := float(a.get("dist", 0.0))
	var db := float(b.get("dist", 0.0))
	if not is_equal_approx(da, db):
		return da < db
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _pinned(ids: PackedStringArray) -> String:
	var gs = _node("GameState")
	var chapter: Dictionary = gs.chapter_def()
	var req = chapter.get("next_requires", null)
	if req == null or typeof(req) != TYPE_DICTIONARY:
		req = chapter.get("ending_requires", null)
	if req == null or typeof(req) != TYPE_DICTIONARY:
		return ""
	var must: Array = req.get("must_visit", [])
	for raw in must:
		var pid := str(raw)
		if pid in ids and not (pid in gs.visited_ports):
			return pid
	# 章目只差「泊在某港」（settle_at）一条时，那一港占第一席——否则够了本钱港数，还得候风等它碰巧进三向（平均十来日）
	var settle := ""
	for it in gs._requirement_items(req):
		if it.get("done", false):
			continue
		if settle != "" or str(it.get("settle", "")) == "":
			return ""
		settle = str(it.get("settle", ""))
	return settle if settle in ids else ""
