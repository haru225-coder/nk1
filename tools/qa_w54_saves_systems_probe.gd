extends SceneTree
## Lane w54-saves：逐系统存档往返探针——每个系统都拿真玩法函数摆出状态（雇人走 Crew.hire、委办走 contract_offer /
## accept_contract / deliver_contract、行情走买卖冲击与修埠、守城走 siege_* …，不是拿 from_dict 直摆），然后：
##   ① 记下存前五分区（calendar / economy / fleet / crew / state 的 to_dict）与该系统的读数（价目、名册、委办账、城防战力……）；
##   ② save_game 落盘；
##   ③ 同一种子续跑一段（过日子、过月、发饷、交货、结息、传闻过期……），记终态与这段里发出的月初通告；
##   ④ 脏场后 load_game 读回——读后五分区须与存前逐键相等（含字典键序；JSON 读回整数成浮点，按同值比）、读数逐条相等；
##   ⑤ 同一种子从读回的档再续跑同一段——终态五分区、读数、通告须与 ③ 逐条相等。
## ④ 抓「to_dict 落了、from_dict 没读」「读回换了型 / 换了键序」；⑤ 抓只在往后几日才露的漏——档里少记的状态、
## 读回成浮点后被拿去 match / 当键 / 判型、读回次序变了的账，存前读后当场一样、过几日才分岔。
## 末节 UI 总览：多系统合摆一场，福州港页与九处设施页（牙行 / 市舶司 / 船屋 / 酒馆 / 旅店 / 行会 / 贡院 / 住处 / 寺观）、
## 兴化守城页逐页逐行比存前读后（状态匾末行是记事栏最新一句，读档那句本就不同，不比）。
## 与 qa_w53_5_roundtrip_probe（摆一场静态全字段、逐键对账）互补：那支管「字段全不全」，本支管「各系统真玩出来的状态
## 读回去接着玩还是不是同一局」。另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红）。
## 只动存档位 541（w54-saves 自用段 541..549，不碰正式位 1..SLOTS，也不撞别的探针的 81 / 91..97）。
## 用法：godot --headless --path . -s res://tools/qa_w54_saves_systems_probe.gd
## 末行 QA_W54_SAVES_SYSTEMS cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 541
const SEED_SETUP := 20261020
const SEED_CONT := 4242
const FACILITIES := ["_market", "_yamen", "_shipyard", "_tavern", "_inn", "_guild", "_exam", "_residence", "_temple"]
const PAGE_NAME := {"port": "港", "_market": "牙行", "_yamen": "市舶司", "_shipyard": "船屋", "_tavern": "酒馆", "_inn": "旅店",
	"_guild": "行会", "_exam": "贡院", "_residence": "住处", "_temple": "寺观"}

var _main: Node
var sl: Node
var gs: Node
var cal: Node
var eco: Node
var fleet: Node
var crew: Node
var gm: Node
var notices: Array = []
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时收尾不会被调到——回到这里就地判红收尾
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note(), "")
		_report()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	sl = root.get_node_or_null("SaveLoad")
	gs = root.get_node_or_null("GameState")
	cal = root.get_node_or_null("Calendar")
	eco = root.get_node_or_null("Economy")
	fleet = root.get_node_or_null("Fleet")
	crew = root.get_node_or_null("Crew")
	gm = root.get_node_or_null("GameManager")
	if sl == null or gs == null or cal == null or eco == null or fleet == null or crew == null or gm == null:
		push_error("autoload missing")
		quit(1)
		return
	_cleanup()
	gm.monthly_notice.connect(func(t: String) -> void: notices.append(t))
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)

	for s in [
		["日历", _sys_calendar], ["行情", _sys_economy], ["船队", _sys_fleet], ["职事", _sys_crew],
		["史实辞船", _sys_crew_history], ["委办", _sys_contract], ["传闻", _sys_rumors], ["赊贷与市舶", _sys_debt_customs],
		["勘见", _sys_discoveries], ["行年", _sys_era], ["守城", _sys_siege], ["封港", _sys_port_bans],
		["身份结算", _sys_identity], ["终局", _sys_ending], ["拍账・人物志・边记・旗标", _sys_marks], ["章节", _sys_chapter],
	]:
		var d: Dictionary = (s[1] as Callable).call()
		_round_trip(str(s[0]), d)

	await _ui_case("UI 福州", _ui_fuzhou, "fuzhou", FACILITIES)
	await _ui_case("UI 兴化守城", _ui_siege, "xinghua", [])

	_cleanup()
	_report()


# ── 摆场底子：每个系统从同一副白板起，种子固定（Economy.initialize 的开局扰动随种子） ──

func _fresh(year := 1262, month := 6, day := 14, port := "fuzhou") -> void:
	seed(SEED_SETUP)
	notices.clear()
	cal.from_dict({"year": year, "month": month, "day": day})
	eco.from_dict({"rates": {}, "tariff": 0.10, "broker": 0.05, "investments": {}})
	eco.set("_initialized", false)
	eco.initialize()
	fleet.from_dict({"ships": [], "water": 60, "food": 60, "morale": 70, "mutiny_cooldown": 0})
	fleet.add_ship("fu_ship_medium", "安济")
	fleet.hire_to_min()
	crew.from_dict({"hired": {}, "unpaid_months": 0, "departed": {}})
	gs.from_dict({"money": 20000, "last_port": port, "chapter": 2, "fame": 20,
		"visited_ports": ["xinghua", "quanzhou", port]})


## 往返一趟：存前快照 → 存 → 续跑 → 脏场读回 → 比读后与存前 → 再续跑 → 比两回终态。
## 读数里的账本（城防账、行年路线）照容器原样比、不先 JSON.stringify：读回的整数成了浮点，串出来「2」「2.0」两样，同值不算差
func _round_trip(name: String, d: Dictionary) -> void:
	var port := str(d["port"])
	var obs: Callable = d["obs"]
	var cont: Callable = d["cont"]
	var before := _parts()
	var obs0: Array = obs.call()
	_expect(sl.save_game(SLOT, port), "%s：记入第 %d 卷" % [name, SLOT], "")
	seed(SEED_CONT)
	notices.clear()
	cont.call()
	var f1 := _parts()
	var o1: Array = obs.call()
	var n1: Array = notices.duplicate()
	_dirty()
	_expect(sl.load_game(SLOT), "%s：读回第 %d 卷" % [name, SLOT], "")
	var diff := _diff("", before, _parts(), [])
	_expect(diff.is_empty(), "%s：读后五分区 == 存前（逐键、含键序）" % name, "; ".join(diff.slice(0, 4)))
	var obs1: Array = obs.call()
	var od := _diff("读数", obs0, obs1, [])
	_expect(od.is_empty(), "%s：读后读数 == 存前（%d 条）" % [name, obs0.size()], "; ".join(od.slice(0, 3)))
	seed(SEED_CONT)
	notices.clear()
	cont.call()
	var cd := _diff("", f1, _parts(), [])
	cd.append_array(_diff("读数", o1, obs.call(), []))
	cd.append_array(_diff("通告", n1, notices, []))
	_expect(cd.is_empty(), "%s：读回后续跑的终态 == 未读档续跑（五分区、读数、通告 %d 条）" % [name, n1.size()],
		"; ".join(cd.slice(0, 4)))


## 五分区快照：to_dict 交出的是单例里的活容器（船、货舱、行情、城防账……），续跑会就地改它们——深拷一份才是「那一刻」
func _parts() -> Dictionary:
	return {"calendar": cal.to_dict(), "economy": eco.to_dict(), "fleet": fleet.to_dict(),
		"crew": crew.to_dict(), "state": gs.to_dict()}.duplicate(true)


## 脏场：五个单例换成另一副样子，读档若没把它们盖回来，读后比对必红
func _dirty() -> void:
	cal.from_dict({"year": 1111, "month": 1, "day": 1})
	eco.from_dict({"rates": {}, "tariff": 0.99, "broker": 0.99, "investments": {"fuzhou": 9}})
	fleet.from_dict({"ships": [], "water": 1, "food": 1, "morale": 1, "mutiny_cooldown": 9})
	crew.from_dict({"hired": {"zashi": "zhou_suanchou"}, "unpaid_months": 9, "departed": {}})
	gs.from_dict({"money": 1, "player_name": "占位", "chapter": 9, "flags": {"zz_dirty": true},
		"siege": {"troops": 1}, "contract_ban": {"zz": 1}})
	# from_dict 漏读的那一格，上面这几下也改不到它（漏读就是 from_dict 不碰它）：存档里的每一格再直接写成另一副值，
	# 读档没盖回来的那格停在毒值上，读后比对即红（只靠 from_dict 脏场，GameState.from_dict 删掉 era_profit 一行照绿，实测）
	for k in gs.to_dict():
		gs.set(k, _poison(gs.get(k)))
	for k in ["year", "month", "day"]:
		cal.set(k, _poison(cal.get(k)))
	for k in ["tariff_rate", "broker_fee", "rates", "investments"]:
		eco.set(k, _poison(eco.get(k)))
	for k in ["ships", "water", "food", "morale", "mutiny_cooldown"]:
		fleet.set(k, _poison(fleet.get(k)))
	for k in ["hired", "unpaid_months", "departed"]:
		crew.set(k, _poison(crew.get(k)))


## 同型的另一副值（读档前写进单例，读档须把它盖掉）
func _poison(v):
	match typeof(v):
		TYPE_INT:
			return int(v) + 97
		TYPE_FLOAT:
			return float(v) + 0.97
		TYPE_STRING:
			return str(v) + "・脏"
		TYPE_BOOL:
			return not bool(v)
		TYPE_ARRAY:
			return ["zz_dirty"]
		TYPE_DICTIONARY:
			return {"zz_dirty": 1}
	return v


# ── 各系统 ─────────────────────────────────────────────

func _sys_calendar() -> Dictionary:
	_fresh(1262, 6, 14)
	gm.advance_days(47)
	return {"port": "fuzhou",
		"obs": func() -> Array: return [cal.get_date_string(), cal.absolute_day(), cal.get_era_year_string()],
		"cont": func() -> void: gm.advance_days(40)}


func _sys_economy() -> Dictionary:
	_fresh()
	eco.apply_buy_impact("fuzhou", "tea", 40)
	eco.apply_sell_impact("mingzhou", "tea", 30)
	eco.apply_buy_impact("quanzhou", "pepper", 25)
	eco.invest("fuzhou")
	eco.invest("fuzhou")
	eco.invest("quanzhou")
	eco.apply_news_market({"good_id": "sulfur", "mul": 1.4})
	gm.advance_days(3)
	var obs := func() -> Array:
		var out: Array = []
		for pid in ["fuzhou", "mingzhou", "quanzhou", "hakata"]:
			var row := PackedStringArray()
			for g in eco.goods_at(pid):
				row.append("%s %d/%d" % [g, eco.buy_price(pid, g), eco.sell_price(pid, g)])
			out.append("%s 修埠 %d 下一等 %d 抽解 %.6f｜%s" % [pid, eco.investment_level(pid), eco.invest_cost(pid),
				eco.duty_rate(pid), "，".join(row)])
		return out
	var cont := func() -> void:
		gm.advance_days(45)
		eco.apply_buy_impact("fuzhou", "tea", 20)
		eco.apply_sell_impact("quanzhou", "pepper", 10)
		eco.invest("mingzhou")
		gm.advance_days(5)
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_fleet() -> Dictionary:
	_fresh()
	fleet.add_ship("keel_boat", "通济")
	fleet.add_ship("pirate_boat", "快船")
	fleet.settle_prize(fleet.ships.size() - 1, 0.42)
	fleet.upgrade_sail(0)
	fleet.upgrade_armor(1)
	fleet.upgrade_armor(1)
	fleet.damage_each_ship(37.5)
	fleet.add_cargo("tea", 15, 31.5, 0)
	fleet.add_cargo("grain", 20, 6.0, 1)
	fleet.add_cargo("tea", 5, 40.0, 1)
	fleet.add_cargo("sulfur", 3, 61.25, 2)
	fleet.hire_crew(3, 1)
	fleet.add_supply_pair(-13)
	fleet.morale = 44
	var obs := func() -> Array:
		var out: Array = ["全队 人 %d 舱 %s/%s 速 %.6f 补给 %d 日 缺人 %d 修 %d 甲 %.6f 士气 %d 冷却 %d" % [
			fleet.total_crew(), str(fleet.used_capacity()), str(fleet.total_capacity()), fleet.fleet_speed(),
			fleet.supply_days(), fleet.crew_shortfall(), fleet.repair_cost(), fleet.armor_damage_reduction(),
			fleet.morale, fleet.mutiny_cooldown], "舱货 " + JSON.stringify(fleet.cargo)]
		for i in fleet.ships.size():
			out.append("%s 舱 %s 余 %s 人 %d/%d-%d 帆 %d 甲 %d 升帆 %d 升甲 %d 茶 %d 均价 %.6f" % [fleet.display_name(i),
				str(fleet.ship_capacity(i)), str(fleet.ship_free_capacity(i)), fleet.ship_crew(i), fleet.ship_crew_min(i),
				fleet.ship_crew_max(i), fleet.sail_level(i), fleet.armor_level(i), fleet.upgrade_cost(i, "sail"),
				fleet.upgrade_cost(i, "armor"), fleet.cargo_qty("tea", i), fleet.cargo_cost("tea", i)])
		return out
	var cont := func() -> void:
		fleet.at_sea = true
		for i in 15:
			gm.advance_days(1)
			if fleet.mutiny_ready():
				notices.append("哗变：" + JSON.stringify(fleet.resolve_mutiny("bribe")))
		fleet.at_sea = false
		notices.append("货损：" + JSON.stringify(fleet.lose_cargo_ratio(0.1)))
		fleet.remove_cargo("tea", 7)
		fleet.repair_all()
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_crew() -> Dictionary:
	_fresh()
	for cid in ["wu_zhen", "chen_laodao", "huang_zhangfang", "monk_puji"]:
		crew.hire(cid)
	crew.dismiss("zashi")
	crew.hire("zhou_suanchou")
	gs.money = 30
	gm.advance_days(20)
	var obs := func() -> Array:
		var out: Array = []
		for c in crew.roster():
			out.append("%s %s" % [c.get("id"), c.get("name")])
		out.append("月俸 %d 欠饷 %d 月 火长 %d 舵工 %d 杂事 %d" % [crew.monthly_wage(), crew.unpaid_months,
			crew.level_of("huozhang"), crew.level_of("duogong"), crew.level_of("zashi")])
		out.append("速 %.6f 价差 %.6f 减员 %.6f 士气 %d 逆风 %.6f" % [crew.speed_factor(), crew.trade_cost_factor(),
			crew.crew_loss_factor(), crew.morale_bonus(), crew.wind_floor()])
		var here: Array = []
		for c in crew.candidates_at("quanzhou"):
			here.append(c.get("id"))
		out.append("泉州候雇 " + JSON.stringify(here))
		out.append("曾雇 " + JSON.stringify(gs.crew_history))
		return out
	var cont := func() -> void:
		gm.advance_days(70)
		gs.add_money(5000)
		gm.advance_days(31)
	return {"port": "fuzhou", "obs": obs, "cont": cont}


## 史实辞船（crew.json leave_from）：林华景炎元年十月下船，departed 入档
func _sys_crew_history() -> Dictionary:
	_fresh(1276, 8, 20)
	gs.chapter = 4
	crew.hire("lin_hua")
	crew.hire("wu_zhen")
	gm.advance_days(45)
	var obs := func() -> Array:
		var ids: Array = []
		for c in crew.roster():
			ids.append(c.get("id"))
		return [JSON.stringify(ids), JSON.stringify(crew.departed_lines()), JSON.stringify(crew.departed)]
	var cont := func() -> void:
		gm.advance_days(40)
		crew.hire("cai_qixing")
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_contract() -> Dictionary:
	_fresh()
	gs.last_port = "wenzhou"
	var first: Dictionary = gs.contract_offer("wenzhou")
	gs.accept_contract(first)
	gs.abandon_contract()
	gs.last_port = "fuzhou"
	var offer: Dictionary = gs.contract_offer("fuzhou")
	gs.accept_contract(offer)
	_expect(not gs.contract.is_empty() and gs.contract_port_closed("wenzhou"), "委办：摆场接下福州的单、温州那单毁约停单（往返才有账可比）",
		"contract=%s 温州 %s" % [JSON.stringify(gs.contract), JSON.stringify(first)])
	var gid := str(gs.contract.get("good_id", ""))
	var dest := str(gs.contract.get("dest", ""))
	var qty := int(gs.contract.get("qty", 0))
	fleet.add_cargo(gid, qty - 3, 10.0, 0)
	gm.advance_days(2)
	gs.last_port = dest
	gs.deliver_contract(dest)
	var obs := func() -> Array:
		return [JSON.stringify(gs.contract_status()), "罚 %d 留货 %d 温州停单 %s 福州新单 %s" % [gs.contract_fine(),
			gs.contract_kept(gid), str(gs.contract_port_closed("wenzhou")), JSON.stringify(gs.contract_offer("fuzhou"))],
			"钱 %d 名声 %d" % [gs.money, gs.fame]]
	var cont := func() -> void:
		fleet.add_cargo(gid, 3, 10.0, 0)
		notices.append("交货：" + JSON.stringify(gs.deliver_contract(dest)))
		gs.last_port = "fuzhou"
		gm.advance_days(35)
		var again: Dictionary = gs.contract_offer("wenzhou")
		notices.append("温州新单：" + JSON.stringify(again))
		gs.accept_contract(again)
		gm.advance_days(40)
	return {"port": dest, "obs": obs, "cont": cont}


func _sys_rumors() -> Dictionary:
	_fresh()
	gs.note_rumor("mingzhou", "tea", 1.37)
	gm.advance_days(5)
	gs.note_rumor("wenzhou", "sulfur", 1.6)
	gs.note_rumor("fuzhou", "tea", 0.81)
	var obs := func() -> Array:
		return [gs.rumor_tip("fuzhou", "tea", "提示"), gs.rumor_tip("quanzhou", "sulfur", ""), gs.rumor_label("mingzhou", "tea"),
			gs.rumor_elsewhere("quanzhou", "tea")]
	var cont := func() -> void:
		gm.advance_days(41)
		gs.note_rumor("hakata", "tea", 1.9)
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_debt_customs() -> Dictionary:
	_fresh()
	fleet.add_cargo("tea", 12, 31.5, 0)
	gs.borrow(2200)
	gs.repay(300)
	notices.append(str(gs.customs_inspection().get("msg", "")))
	gs.apply_for_permit()
	var obs := func() -> Array:
		return ["欠 %d 可借 %d 引 %s 留意 %d 抽解 %d 职衔 %s 钱 %d" % [gs.debt, gs.borrow_limit(), str(gs.has_customs_permit),
			gs.pu_attention, gs.customs_duty(), gs.title_name(), gs.money]]
	var cont := func() -> void:
		gm.advance_days(62)
		notices.append(str(gs.customs_inspection().get("msg", "")))
		gs.consume_permit()
		gs.repay(1000)
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_discoveries() -> Dictionary:
	_fresh()
	for did in ["beacon_ruin", "whale_route", "coral_shoal"]:
		gs.record_discovery(did)
	gs.report_discovery("whale_route")
	var obs := func() -> Array:
		return [JSON.stringify(gs.unreported_discoveries()), JSON.stringify(gs.discoveries_reported),
			str(gs.has_found("whale_route")), "钱 %d 名声 %d" % [gs.money, gs.fame]]
	var cont := func() -> void:
		gs.report_discovery("coral_shoal")
		gs.record_discovery("monsoon_marker")
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_era() -> Dictionary:
	_fresh()
	# 并列两条（博多唐房先到）：读回换了次序，主线就换成后到的那条
	for r in [["quanzhou", "hakata"], ["quanzhou", "ryukyu"], ["quanzhou", "hakata"], ["quanzhou", "ryukyu"], ["fuzhou", "wenzhou"]]:
		gs.record_trip(r[0], r[1])
	gs.era_profit = 777
	var obs := func() -> Array:
		return [gs.era_main_route(), gs.era_trips, gs.era_profit, gs.era_routes.duplicate(true)]
	var cont := func() -> void:
		gs.record_trip("quanzhou", "ryukyu")
		gs.record_trip("quanzhou", "hakata")
	return {"port": "fuzhou", "obs": obs, "cont": cont}


## 守城（士人线 1276 冬月）连同外援四样（押米 / 乡兵 / 拆船料 / 劫粮道得手，lane w53-p5-siege 记在 siege 字典里）
func _sys_siege() -> Dictionary:
	_fresh(1276, 11, 3, "xinghua")
	gs.chapter = 4
	gs.identity = "scholar"
	gs.player_name = "陈文龙"
	gs.set_flag("renamed_wenlong")
	gs.set_flag("chen_zan_stake")
	gs.siege_begin()
	gs.siege_add("troops", 340)
	gs.siege_add("grain", 80)
	gs.siege_set("convoy", 80)
	gs.siege_add("troops", 120)
	gs.siege_set("levy", 120)
	gs.siege_add("wall", 40)
	gs.siege_add("timber", 40)
	gs.siege_set("raid", "won")
	gs.siege_set("raid_round", 2)
	gs.siege_set("shishou", "kept")
	gs.siege_set("envoy_wang", true)
	gs.siege_set("round", 1)
	var obs := func() -> Array:
		return [gs.siege.duplicate(true), "战力 %.6f 募兵上限 %d 墙余 %d 开 %s 阵 %d" % [gs.siege_power(), gs.siege_troop_cap(),
			gs.siege_wall_room(), str(gs.siege_open()), gs.siege_get("round")]]
	var cont := func() -> void:
		for i in 2:
			gs.siege_add("grain", -gs.SIEGE_GRAIN_PER_ROUND)
			gs.siege_add("morale", -5)
			gs.siege_set("round", gs.siege_get("round") + 1)
			notices.append("第 %d 阵 战力 %.6f" % [gs.siege_get("round"), gs.siege_power()])
		gm.advance_days(10)
	return {"port": "xinghua", "obs": obs, "cont": cont}


func _sys_port_bans() -> Dictionary:
	_fresh()
	gs.ban_port("quanzhou", "1262-08")
	gs.ban_port("hakata", "1263-01")
	var obs := func() -> Array:
		return [str(gs.is_port_banned("quanzhou")), str(eco.is_port_reachable("hakata")), JSON.stringify(gs.port_bans)]
	var cont := func() -> void:
		gm.advance_days(75)
		notices.append("泉州封否 %s" % str(gs.is_port_banned("quanzhou")))
	return {"port": "fuzhou", "obs": obs, "cont": cont}


## 1268 年四月身份结算（只结一次）：存在二月末，续跑过四月
func _sys_identity() -> Dictionary:
	_fresh(1268, 2, 25)
	gs.scholar_tendency = 4
	gs.sea_tendency = 4
	gs.hometown_tendency = 2
	gs.set_flag("exam_sat")
	var obs := func() -> Array:
		return [gs.identity, gs.player_name, gs.news_variant(), JSON.stringify(gs.flags), gs.pending_news().size()]
	return {"port": "fuzhou", "obs": obs, "cont": func() -> void: gm.advance_days(70)}


func _sys_ending() -> Dictionary:
	_fresh(1277, 3, 2)
	gs.chapter = 4
	gs.finish("海上宋鬼", "海上的事，没有人记得。")
	gs.ended_head = "福州・景炎二年三月"
	var obs := func() -> Array:
		return [JSON.stringify(gs.epilogue_lines()), JSON.stringify(gs.chapter_progress()), str(gs.is_ended()), gs.ended_at]
	var cont := func() -> void:
		notices.append("再落终局 %s" % str(gs.finish("忠肃", "")))
		notices.append(JSON.stringify(gs.try_advance_chapter()))
		gm.advance_days(31)
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_marks() -> Dictionary:
	_fresh()
	gs.beat_mark("start")
	gs.beat_mark("monk")
	gs.loaded_with_beats = true
	gs.note_met("lin_hua")
	gs.note_met("pu_steward")
	gs.add_ledger_note("lin_cargo_defaulted")
	gs.add_ledger_note("拓「屿寨石垣」　往流求的航期可缩短数日。")
	gs.set_flag("guild_fuzhou")
	gs.set_flag("exam_sat_ch2")
	gs.set_flag("chose_land_first")
	var obs := func() -> Array:
		return [JSON.stringify(gs.beats_seen), str(gs.beats_touched()), str(gs.has_met("pu_steward")),
			JSON.stringify(gs.ledger_notes), JSON.stringify(gs.ledger_notes.map(Callable(gs, "epilogue_note"))),
			JSON.stringify(gs.flags.keys())]
	var cont := func() -> void:
		gs.beat_mark("ledger")
		gs.add_ledger_note("storm_jettison_recorded")
		gs.set_flag("guild_quanzhou")
	return {"port": "fuzhou", "obs": obs, "cont": cont}


func _sys_chapter() -> Dictionary:
	_fresh(1258, 9, 1, "fuzhou")
	gs.chapter = 1
	gs.money = 4800
	gs.peak_money = 4800
	gs.visited_ports = ["xinghua", "quanzhou", "fuzhou", "wenzhou"]
	var obs := func() -> Array:
		return [JSON.stringify(gs.chapter_progress()), gs.chapter]
	var cont := func() -> void:
		gs.visit_port("ryukyu")
		gs.add_money(400)
		notices.append(JSON.stringify(gs.try_advance_chapter()))
	return {"port": "fuzhou", "obs": obs, "cont": cont}


# ── UI 总览：多系统合摆一场，逛遍港页与设施页 ─────────────────

func _ui_fuzhou() -> void:
	_fresh()
	fleet.add_ship("keel_boat", "通济")
	fleet.add_cargo("tea", 12, 31.5, 0)
	fleet.add_cargo("grain", 30, 6.0, 1)
	fleet.upgrade_sail(0)
	for cid in ["wu_zhen", "chen_laodao", "huang_zhangfang"]:
		crew.hire(cid)
	var offer: Dictionary = gs.contract_offer("fuzhou")
	gs.accept_contract(offer)
	_expect(not gs.contract.is_empty(), "UI 福州：摆场接下一单委办", JSON.stringify(offer))
	gs.note_rumor("mingzhou", "tea", 1.45)
	gs.borrow(700)
	eco.invest("fuzhou")
	gs.record_discovery("beacon_ruin")
	gs.set_flag("guild_fuzhou")
	gs.set_flag("exam_sat")
	gs.add_ledger_note("lin_cargo_defaulted")
	gs.record_trip("quanzhou", "fuzhou")
	gm.advance_days(3)


func _ui_siege() -> void:
	_sys_siege()


func _ui_case(name: String, setup: Callable, port: String, facilities: Array) -> void:
	setup.call()
	_main.load_scene(port)
	await _settle(3)
	await _walk(port, facilities)  # 头一遍暖身：发牌、记名之类首次进门才做的事先做掉
	_main.load_scene(port)
	await _settle(2)
	_expect(sl.save_game(SLOT, port), "%s：记入第 %d 卷" % [name, SLOT], "")
	var before := await _walk(port, facilities)
	_dirty()
	_main._on_load_slot(SLOT)
	await _settle(6)
	_expect(str(_main.current_scene_id) == port, "%s：读档回到 %s" % [name, port], "scene=%s" % str(_main.current_scene_id))
	var after := await _walk(port, facilities)
	for page in before:
		var d := _diff(str(page), before[page], after.get(page, []), [])
		_expect(d.is_empty(), "%s：%s页存前读后逐行同（%d 行）" % [name, PAGE_NAME.get(page, str(page)), (before[page] as Array).size()],
			"; ".join(d.slice(0, 2)))


func _walk(port: String, facilities: Array) -> Dictionary:
	var pages := {}
	_main.load_scene(port)
	await _settle(2)
	pages["port"] = _texts()
	for suf in facilities:
		_main.load_scene(port + str(suf))
		await _settle(2)
		pages[suf] = _texts()
	_main.load_scene(port)
	await _settle(2)
	return pages


func _texts() -> Array:
	var out: Array = []
	_collect(_main, out)
	return out


## 屏上看得见的字：Label / RichTextLabel / Button（连悬停）；记事栏与状态匾末行（记事最新一句）不比
func _collect(n: Node, out: Array) -> void:
	if n == _main.get("message_label") or n == _main.get("_status_note"):
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Label:
		if (n as Label).text.strip_edges() != "":
			out.append("字　" + (n as Label).text)
	elif n is RichTextLabel:
		if (n as RichTextLabel).text.strip_edges() != "":
			out.append("文　" + (n as RichTextLabel).text)
	elif n is Button:
		out.append("钮　%s%s" % [(n as Button).text, "（灰）" if (n as Button).disabled else ""])
	if n is Control and (n as Control).tooltip_text != "":
		out.append("悬　" + (n as Control).tooltip_text)
	for c in n.get_children():
		_collect(c, out)


# ── 比对 ──────────────────────────────────────────────

## 语义逐键比：int / float 同值算同（JSON 读回整数成浮点）；字典比键集与键序；数组按序。返回差处描述
func _diff(path: String, a, b, out: Array) -> Array:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		if not is_equal_approx(float(a), float(b)):
			out.append("%s：%s ≠ %s" % [path, str(a), str(b)])
		return out
	if typeof(a) != typeof(b):
		out.append("%s：型 %s ≠ %s（%s / %s）" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a).left(60), str(b).left(60)])
		return out
	if a is Dictionary:
		var ka: Array = (a as Dictionary).keys()
		var kb: Array = (b as Dictionary).keys()
		if ka != kb:
			out.append("%s：键 %s ≠ %s" % [path, str(ka).left(120), str(kb).left(120)])
		for k in ka:
			if (b as Dictionary).has(k):
				_diff("%s.%s" % [path, str(k)], a[k], b[k], out)
		return out
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			out.append("%s：长 %d ≠ %d（%s / %s）" % [path, (a as Array).size(), (b as Array).size(), str(a).left(100), str(b).left(100)])
			return out
		for i in (a as Array).size():
			_diff("%s[%d]" % [path, i], a[i], b[i], out)
		return out
	if a != b:
		out.append("%s：%s ≠ %s" % [path, str(a).left(160), str(b).left(160)])
	return out


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], "")
	print("QA_W54_SAVES_SYSTEMS cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail if not ok else ""])
	if not ok:
		fails += 1


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _cleanup() -> void:
	var base := str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT
	for suffix in ["", ".bak", ".tmp", ".v1", ".v2", ".v3"]:
		if FileAccess.file_exists(base + suffix):
			DirAccess.remove_absolute(base + suffix)
