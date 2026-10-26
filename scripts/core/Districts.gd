extends RefCounted
## 城中各处（data/districts.json）。
## 读表、开闭、成交、月初铺面入账与雇人月俸。不挂 autoload：GameState 只归一存档形状，
## Economy 月初用 load 调 month_tick，Main 经 DistrictPage 进来。
## 行情只动「这港牙行本来就有、rates 里已有键」的货，免得 _shift_rate 凭空长出一格。

const PATH := "res://data/districts.json"
const TYPES := ["buy", "sell", "invest", "hire", "rumor", "favour", "licence", "choice"]
const BUCKETS := ["once", "year", "month", "cool", "invest", "hire", "licence", "favour"]
const EXAM_YEARS := [1256, 1259, 1262, 1265, 1268, 1271, 1274]
const EXAM_MONTHS := [8, 9, 10]
const KIND_LABEL := {
	"dock": "码头", "office": "衙廊", "street": "坊巷", "temple": "寺观",
	"hill": "山亭", "bridge": "石桥", "market": "坊市", "workshop": "作坊",
	"warehouse": "塌房", "exam": "贡院", "teahouse": "茶坊", "academy": "军学",
	"grove": "果林", "ferry": "渡口", "gate": "城门", "dam": "陂塘",
}

static var _rows: Array = []
static var _loaded := false
static var _by_dist: Dictionary = {}
static var _by_ix: Dictionary = {}
static var _ix_port: Dictionary = {}
static var _ix_dist: Dictionary = {}


static func book() -> Array:
	if _loaded:
		return _rows
	_loaded = true
	_rows = []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return _rows
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _rows
	var list = parsed.get("districts", [])
	if typeof(list) != TYPE_ARRAY:
		return _rows
	for row in list:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id := str(row.get("id", ""))
		if id == "":
			continue
		_rows.append(row)
		_by_dist[id] = row
		var port := str(row.get("port", ""))
		for ix in row.get("interactions", []):
			if typeof(ix) != TYPE_DICTIONARY:
				continue
			var iid := str(ix.get("id", ""))
			if iid == "":
				continue
			_by_ix[iid] = ix
			_ix_port[iid] = port
			_ix_dist[iid] = id
	return _rows


static func rows() -> Array:
	return book()


static func has_port(port_id: String) -> bool:
	for row in book():
		if str(row.get("port", "")) == port_id:
			return true
	return false


static func districts_of(port_id: String) -> Array:
	var out: Array = []
	for row in book():
		if str(row.get("port", "")) == port_id:
			out.append(row)
	return out


static func district(dist_id: String) -> Dictionary:
	book()
	var row = _by_dist.get(dist_id, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func interaction(ix_id: String) -> Dictionary:
	book()
	var ix = _by_ix.get(ix_id, {})
	return ix if typeof(ix) == TYPE_DICTIONARY else {}


static func kind_label(kind: String) -> String:
	return str(KIND_LABEL.get(kind, "城中"))


static func ensure() -> Dictionary:
	var d = GameState.districts
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
		GameState.districts = d
	for k in BUCKETS:
		if typeof(d.get(k, null)) != TYPE_DICTIONARY:
			d[k] = {}
	return d


static func wipe() -> void:
	GameState.districts = {
		"once": {}, "year": {}, "month": {}, "cool": {},
		"invest": {}, "hire": {}, "licence": {}, "favour": {},
	}


static func favour_of(port_id: String) -> int:
	return int(ensure().favour.get(port_id, 0))


static func has_licence(lic_id: String) -> bool:
	return ensure().licence.get(lic_id, false) == true


static func is_hired(ix_id: String) -> bool:
	return ensure().hire.get(ix_id, false) == true


static func level_of(ix_id: String) -> int:
	return int(ensure().invest.get(ix_id, 0))


static func dismiss(ix_id: String) -> void:
	ensure().hire.erase(ix_id)


static func district_reason(row: Dictionary) -> String:
	var why := gate_reason(_as_dict(row.get("unlock", {})), str(row.get("port", "")), false)
	if why == "":
		return ""
	var custom := str(row.get("lock_reason", ""))
	return custom if custom != "" else why


static func gate_reason(unlock: Dictionary, port_id: String, exam: bool) -> String:
	if unlock.is_empty():
		return ""
	var y := Calendar.year
	var m := Calendar.month
	if unlock.has("year_min") and y < int(unlock.year_min):
		return "年份未到"
	if unlock.has("year_max") and y > int(unlock.year_max):
		return "时节已过"
	if unlock.has("years") and not _has_int(unlock.years, y):
		return "不是大比之年" if exam else "今年不开"
	if unlock.has("months") and not _has_int(unlock.months, m):
		return "还不是这个月的事"
	if unlock.has("chapter_min") and GameState.chapter < int(unlock.chapter_min):
		return "这事还轮不到"
	var war := Economy.war_status(port_id)
	if unlock.has("war_in") and not _has_str(unlock.war_in, war):
		return "眼下的战况不对"
	if unlock.has("war_not") and _has_str(unlock.war_not, war):
		return "这时候去不得"
	var flag := str(unlock.get("require_flag", ""))
	if flag != "" and not GameState.has_flag(flag):
		return "还没到那一步"
	if int(unlock.get("favour_min", 0)) > favour_of(port_id):
		return "人情还不够"
	var lic := str(unlock.get("needs_licence", ""))
	if lic != "" and not has_licence(lic):
		return "没有这张公凭"
	var hire := str(unlock.get("needs_hire", ""))
	if hire != "" and not is_hired(hire):
		return "没有这位帮手"
	if bool(unlock.get("siege", false)) and not GameState.siege_open():
		return "城防的账还没开"
	return ""


static func hidden(ix: Dictionary) -> bool:
	var flag := str(_as_dict(ix.get("unlock", {})).get("hide_if_flag", ""))
	return flag != "" and GameState.has_flag(flag)


static func unit_price(port_id: String, ix: Dictionary) -> int:
	var good := str(ix.get("good", ""))
	var buying := str(ix.get("type", "")) == "buy"
	var base := Economy.buy_price(port_id, good) if buying else Economy.sell_price(port_id, good)
	var mul := float(ix.get("price_mul", 1.0)) * _licence_mul(ix) * _hire_mul(ix)
	return maxi(1, int(round(float(base) * mul)))


static func button_label(port_id: String, ix: Dictionary) -> String:
	var label := str(ix.get("label", "办理"))
	var n := _shown_money(port_id, ix)
	if n > 0:
		return "%s　%d钱" % [label, n]
	return label


static func view(port_id: String, ix: Dictionary) -> Dictionary:
	var out := {
		"hidden": hidden(ix), "mode": "stamp", "open": false, "affordable": false,
		"reason": "", "label": button_label(port_id, ix), "note": "", "aside": "",
	}
	if out.hidden:
		return out
	var t := str(ix.get("type", ""))
	var why := _block_reason(port_id, ix, ix)
	if t == "hire" and is_hired(str(ix.get("id", ""))):
		out.mode = "dismiss"
		out.open = true
		out.affordable = true
		out.note = "人在身边，月俸 %d 钱。" % int(ix.get("wage", 0))
		out.aside = "在身边"
		return out
	if t == "choice" and why == "":
		out.mode = "choice"
		out.open = true
		out.affordable = true
		out.aside = "两条路" if _options(ix).size() > 1 else ""
		return out
	if why != "":
		out.reason = why
		out.note = why
		out.aside = why
		return out
	var need := _spend_need(port_id, ix)
	out.mode = "chip"
	out.open = true
	out.affordable = GameState.money >= need
	if not out.affordable:
		out.note = "囊中不足"
		out.aside = "囊中不足"
	elif t == "invest":
		out.note = _invest_note(ix)
		out.aside = "铺面"
	elif t == "buy" or t == "sell":
		out.aside = "%d件" % int(ix.get("qty", 0))
	return out


static func view_option(port_id: String, parent: Dictionary, opt: Dictionary) -> Dictionary:
	var spec := _merge_choice(parent, opt)
	var why := _block_reason(port_id, parent, spec)
	var label := str(opt.get("label", "就这样"))
	var cost := int(opt.get("cost", 0))
	if cost > 0:
		label = "%s　%d钱" % [label, cost]
	var open := why == "" and GameState.money >= _spend_need(port_id, spec)
	return {"open": open, "label": label, "reason": why if why != "" else ("" if open else "囊中不足")}


static func apply(ix_id: String, opt_id: String = "") -> Dictionary:
	book()
	var ix = _by_ix.get(ix_id, null)
	if typeof(ix) != TYPE_DICTIONARY:
		return _fail("没有这桩事")
	if not TYPES.has(str(ix.get("type", ""))):
		return _fail("没有这桩事")
	var port := str(_ix_port.get(ix_id, ""))
	var spec: Dictionary = ix
	if str(ix.get("type", "")) == "choice":
		var opt := _option(ix, opt_id)
		if opt.is_empty():
			return _fail("没有这条路")
		spec = _merge_choice(ix, opt)
	var why := _block_reason(port, ix, spec)
	if why != "":
		return _fail(why)
	var money0 := int(GameState.money)
	var need := _spend_need(port, spec)
	if need > 0 and not GameState.spend_money(need):
		return _fail("囊中不足")
	var taken := _take_cargo(spec)
	if str(taken.get("err", "")) != "":
		GameState.money = money0
		return _fail(str(taken.err))
	var add_err := _give_cargo(port, spec)
	if add_err != "":
		_refund(money0, taken.get("qty", {}))
		return _fail(add_err)
	# 传闻先成，再动行情；卖价按成交前的行情算，成交后再砸盘；与牙行 _on_sell 同一口径
	var gain := _sell_income(port, spec)
	if not _do_rumor(spec):
		_refund(money0, taken.get("qty", {}))
		return _fail("那处牙行不做这门货")
	_do_impact(port, spec)
	var bits: Array = _apply_effects(_as_dict(spec.get("effects", {})), port)
	_finish_type(port, ix, spec)
	_mark(ix_id, ix)
	if gain > 0:
		GameState.add_money(gain)
	var msg := _success_msg(ix, spec, port, bits, need, gain)
	return {"ok": true, "msg": msg, "money_delta": int(GameState.money) - money0}


static func month_tick() -> String:
	book()
	var st := ensure()
	var bits: Array = []
	var ids: Array = st.invest.keys()
	ids.sort()
	for id in ids:
		var level := int(st.invest[id])
		if level <= 0:
			continue
		var ix = _by_ix.get(str(id), {})
		if typeof(ix) != TYPE_DICTIONARY:
			continue
		var monthly: Array = ix.get("monthly", [])
		if level > monthly.size():
			continue
		var pay := int(monthly[level - 1])
		if pay <= 0:
			continue
		GameState.add_money(pay)
		bits.append("%s入账 %d 钱" % [str(ix.get("shop", ix.get("label", "铺子"))), pay])
	var wages: Array = []
	var left: Array = []
	var hids: Array = st.hire.keys()
	hids.sort()
	for id in hids:
		if st.hire[id] != true:
			continue
		var ix = _by_ix.get(str(id), {})
		if typeof(ix) != TYPE_DICTIONARY:
			dismiss(str(id))
			continue
		var wage := int(ix.get("wage", 0))
		var who := str(ix.get("who", "帮手"))
		if wage > 0 and not GameState.spend_money(wage):
			dismiss(str(id))
			left.append("%s月俸未发，人走了" % who)
			continue
		if wage > 0:
			wages.append("%s月俸 %d 钱" % [who, wage])
		var ease := int(ix.get("attention_ease", 0))
		if ease > 0:
			GameState.pu_attention = maxi(0, int(GameState.pu_attention) - ease)
		_apply_effects(_as_dict(ix.get("monthly_effects", {})), str(_ix_port.get(str(id), "")))
	if bits.is_empty() and wages.is_empty() and left.is_empty():
		return ""
	var parts: Array = []
	if not bits.is_empty():
		parts.append("、".join(bits) + "。")
	if not wages.is_empty():
		parts.append("、".join(wages) + "。")
	if not left.is_empty():
		parts.append("、".join(left) + "。")
	return "【城中】" + "".join(parts)


# ── 开闭 ──────────────────────────────────────────────

static func _block_reason(port_id: String, ix: Dictionary, spec: Dictionary) -> String:
	var own := str(ix.get("needs_licence", ""))
	if own != "" and not has_licence(own):
		return "未有公凭"
	var why := gate_reason(_as_dict(ix.get("unlock", {})), port_id, bool(ix.get("exam", false)))
	if why != "":
		return why
	var id := str(ix.get("id", ""))
	var st := ensure()
	if bool(ix.get("once", false)) and st.once.has(id):
		return "已经办过"
	var per := str(ix.get("once_per", ""))
	if per == "year" and int(st.year.get(id, -1)) == Calendar.year:
		return "已经办过"
	if per == "month" and int(st.month.get(id, -1)) == Calendar.year * 12 + Calendar.month:
		return "已经办过"
	if int(st.cool.get(id, 0)) > Calendar.absolute_day():
		return "过些日子再来"
	var t := str(spec.get("type", ix.get("type", "")))
	if t == "invest":
		var costs: Array = ix.get("costs", [])
		var monthly: Array = ix.get("monthly", [])
		if costs.is_empty() or costs.size() != monthly.size():
			return "这铺的账还没理清"
		if level_of(id) >= costs.size():
			return "已到顶"
	if t == "licence" and has_licence(str(ix.get("licence", ""))):
		return "已经办过"
	if t == "hire" and is_hired(id):
		return "人已在身边"
	if t == "buy" or (_cargo_spec(spec, "cargo_add").size() > 0):
		var pack := _cargo_spec(spec, "cargo_add") if t != "buy" else {"good": spec.get("good", ""), "qty": spec.get("qty", 0)}
		var room := Fleet.max_loadable(str(pack.get("good", "")))
		if room < int(pack.get("qty", 0)):
			return "舱里装不下"
	if t == "sell" or _cargo_spec(spec, "cargo_take").size() > 0:
		var pack2 := _cargo_spec(spec, "cargo_take") if t != "sell" else {"good": spec.get("good", ""), "qty": spec.get("qty", 0)}
		var held := _free_qty(str(pack2.get("good", "")))
		if held < int(pack2.get("qty", 0)):
			if GameState.contract_kept(str(pack2.get("good", ""))) > 0:
				return "委办货不上秤"
			return "舱里没有这么多"
	if t == "buy" or t == "sell":
		if GameManager.get_good_by_id(str(spec.get("good", ""))).is_empty():
			return "牙行没有这门货"
	if str(ix.get("type", "")) == "licence" and not str(ix.get("licence", "")).begins_with("lic_"):
		return "这张公凭没有字号"
	var rumor = spec.get("rumor", null)
	if t == "rumor":
		rumor = spec
	if typeof(rumor) == TYPE_DICTIONARY and not rumor.is_empty():
		if not _rumor_ok(rumor):
			return "那处牙行不做这门货"
	return ""


static func _spend_need(port_id: String, spec: Dictionary) -> int:
	var t := str(spec.get("type", ""))
	var extra := _negative_money(_as_dict(spec.get("effects", {})))
	if t == "buy":
		return unit_price(port_id, spec) * maxi(1, int(spec.get("qty", 1))) + int(spec.get("cost", 0)) + extra
	if t == "sell":
		return int(spec.get("cost", 0)) + extra
	if t == "invest":
		var costs: Array = spec.get("costs", [])
		var level := level_of(str(spec.get("id", "")))
		if level < 0 or level >= costs.size():
			return extra
		return int(costs[level]) + extra
	return int(spec.get("cost", 0)) + extra


static func _shown_money(port_id: String, ix: Dictionary) -> int:
	var t := str(ix.get("type", ""))
	if t == "sell" or t == "buy":
		return unit_price(port_id, ix) * maxi(1, int(ix.get("qty", 1)))
	if t == "invest":
		var costs: Array = ix.get("costs", [])
		var level := level_of(str(ix.get("id", "")))
		if level < 0 or level >= costs.size():
			return 0
		return int(costs[level])
	return int(ix.get("cost", 0))


static func _invest_note(ix: Dictionary) -> String:
	var id := str(ix.get("id", ""))
	var level := level_of(id)
	var monthly: Array = ix.get("monthly", [])
	var costs: Array = ix.get("costs", [])
	if level <= 0:
		return "还没入本。入 %d 钱，每月入账 %d 钱。" % [int(costs[0]) if not costs.is_empty() else 0, int(monthly[0]) if not monthly.is_empty() else 0]
	var now := int(monthly[level - 1]) if level <= monthly.size() else 0
	if level >= costs.size():
		return "已到顶，每月入账 %d 钱。" % now
	return "每月入账 %d 钱。再入 %d 钱，每月入账 %d 钱。" % [now, int(costs[level]), int(monthly[level])]


# ── 成交 ──────────────────────────────────────────────

static func _take_cargo(spec: Dictionary) -> Dictionary:
	var t := str(spec.get("type", ""))
	var pack := {"good": spec.get("good", ""), "qty": spec.get("qty", 0)} if t == "sell" else _cargo_spec(spec, "cargo_take")
	if pack.is_empty():
		return {"err": "", "qty": {}}
	var good := str(pack.get("good", ""))
	var qty := int(pack.get("qty", 0))
	if qty <= 0:
		return {"err": "", "qty": {}}
	if not Fleet.remove_cargo(good, qty):
		if GameState.contract_kept(good) > 0:
			return {"err": "委办货不上秤", "qty": {}}
		return {"err": "舱里没有这么多", "qty": {}}
	return {"err": "", "qty": {good: qty}}


static func _give_cargo(port_id: String, spec: Dictionary) -> String:
	var t := str(spec.get("type", ""))
	var pack := {"good": spec.get("good", ""), "qty": spec.get("qty", 0)} if t == "buy" else _cargo_spec(spec, "cargo_add")
	if pack.is_empty():
		return ""
	var good := str(pack.get("good", ""))
	var qty := int(pack.get("qty", 0))
	if qty <= 0:
		return ""
	var unit := float(unit_price(port_id, spec)) if t == "buy" else 0.0
	if not Fleet.add_cargo(good, qty, unit):
		return "舱里装不下"
	return ""


static func _do_impact(port_id: String, spec: Dictionary) -> void:
	var t := str(spec.get("type", ""))
	if t != "buy" and t != "sell":
		return
	if not bool(spec.get("impact", true)):
		return
	var good := str(spec.get("good", ""))
	if not _may_shift(port_id, good):
		return
	var qty := int(spec.get("qty", 0))
	if t == "buy":
		Economy.apply_buy_impact(port_id, good, qty)
	else:
		Economy.apply_sell_impact(port_id, good, qty)


static func _do_rumor(spec: Dictionary) -> bool:
	var rumor = spec.get("rumor", null)
	if str(spec.get("type", "")) == "rumor":
		rumor = spec
	if typeof(rumor) != TYPE_DICTIONARY or rumor.is_empty():
		return true
	if not _rumor_ok(rumor):
		return false
	var port := str(rumor.get("port", ""))
	var good := str(rumor.get("good", ""))
	var mul := float(rumor.get("mul", 1.0))
	var hit: Array = Economy.apply_news_market({"good_id": good, "mul": mul, "ports": [port]})
	if hit.is_empty():
		return false
	GameState.note_rumor(port, good, float(Economy.rates[port][good]))
	return true


static func _finish_type(port_id: String, ix: Dictionary, spec: Dictionary) -> void:
	var t := str(ix.get("type", ""))
	var id := str(ix.get("id", ""))
	var st := ensure()
	if t == "invest":
		st.invest[id] = level_of(id) + 1
	elif t == "hire":
		st.hire[id] = true
	elif t == "licence":
		st.licence[str(ix.get("licence", ""))] = true
	elif t == "buy" or t == "sell":
		var att := _attention_delta(spec)
		if att != 0:
			GameState.pu_attention = maxi(0, int(GameState.pu_attention) + att)


static func _mark(ix_id: String, ix: Dictionary) -> void:
	var st := ensure()
	var day := Calendar.absolute_day()
	if bool(ix.get("once", false)):
		st.once[ix_id] = day
	var per := str(ix.get("once_per", ""))
	if per == "year":
		st.year[ix_id] = Calendar.year
	elif per == "month":
		st.month[ix_id] = Calendar.year * 12 + Calendar.month
	var cd := int(ix.get("cooldown_days", 0))
	if cd > 0:
		st.cool[ix_id] = day + cd


static func _sell_income(port_id: String, spec: Dictionary) -> int:
	if str(spec.get("type", "")) != "sell":
		return 0
	return unit_price(port_id, spec) * maxi(1, int(spec.get("qty", 1)))


static func _success_msg(ix: Dictionary, spec: Dictionary, port_id: String, bits: Array, spent: int, gain: int) -> String:
	var where := _dist_name(str(ix.get("id", "")))
	var t := str(ix.get("type", ""))
	var msg := ""
	if t == "buy":
		msg = "【%s】收下%s %d 件，付了 %d 钱。" % [where, GameManager.get_good_name(str(spec.get("good", ""))), int(spec.get("qty", 0)), spent]
	elif t == "sell":
		msg = "【%s】卖出%s %d 件，收了 %d 钱。" % [where, GameManager.get_good_name(str(spec.get("good", ""))), int(spec.get("qty", 0)), gain]
	elif t == "invest":
		var level := level_of(str(ix.get("id", "")))
		var monthly: Array = ix.get("monthly", [])
		var pay := int(monthly[level - 1]) if level > 0 and level <= monthly.size() else 0
		msg = "【%s】入了本钱 %d 钱。往后每月入账 %d 钱。" % [where, spent, pay]
	elif t == "hire":
		msg = "【%s】%s应了。月俸 %d 钱。" % [where, str(ix.get("who", "帮手")), int(ix.get("wage", 0))]
	else:
		msg = "【%s】%s" % [where, str(spec.get("text", ix.get("text", "")))]
		if not msg.ends_with("。"):
			msg += "。"
	var att := _attention_delta(spec) if t == "buy" or t == "sell" else 0
	if att > 0:
		bits.append("蒲家留意加 %d" % att)
	elif att < 0:
		bits.append("蒲家留意减 %d" % -att)
	for b in bits:
		var s := str(b)
		if s == "":
			continue
		msg += s if s.ends_with("。") else s + "。"
	msg += _scholar_line(ix)
	return msg


static func _scholar_line(ix: Dictionary) -> String:
	if not bool(ix.get("scholar_1268", false)) or Calendar.year != 1268:
		return ""
	if GameState.identity != "scholar" and not GameState.has_flag("renamed_wenlong"):
		return ""
	if GameState.player_name == "陈文龙" or GameState.has_flag("renamed_wenlong"):
		return "榜上第一是兴化陈文龙。你在廊下站了一会儿。那是你的名字。"
	return "榜上第一是兴化陈文龙。你在廊下站了一会儿。"


static func _apply_effects(eff: Dictionary, port_id: String) -> Array:
	var bits: Array = []
	if eff.is_empty():
		return bits
	var fame_n := int(eff.get("fame", 0))
	if fame_n != 0:
		var res := GameState.add_fame(fame_n)
		bits.append("名声加 %d" % fame_n if fame_n > 0 else "名声减 %d" % -fame_n)
		var ret := str(GameState.retitle_note(res))
		if ret != "":
			bits.append(ret)
	_add_field(eff, "merchant_credit", "海商信用", bits)
	_add_field(eff, "network", "人脉", bits)
	_add_field(eff, "scholar_tendency", "学者", bits)
	_add_field(eff, "sea_tendency", "海路", bits)
	_add_field(eff, "hometown_tendency", "乡土", bits)
	var pu := int(eff.get("pu_attention", 0))
	if pu != 0:
		GameState.pu_attention = maxi(0, int(GameState.pu_attention) + pu)
		bits.append("蒲家留意加 %d" % pu if pu > 0 else "蒲家留意减 %d" % -pu)
	var martial_n := int(eff.get("martial", 0))
	if martial_n != 0:
		GameState.martial = clampi(int(GameState.martial) + martial_n, 0, 100)
	var money_n := int(eff.get("money", 0))
	if money_n > 0:
		GameState.add_money(money_n)
		bits.append("入账 %d 钱" % money_n)
	elif money_n < 0:
		GameState.spend_money(-money_n)
	var flag := str(eff.get("flag", ""))
	if flag != "":
		GameState.set_flag(flag)
	var note := str(eff.get("note", ""))
	if note != "":
		GameState.add_ledger_note(note)
	var siege = eff.get("siege", {})
	if typeof(siege) == TYPE_DICTIONARY and GameState.siege_open():
		for k in siege:
			GameState.siege_add(str(k), int(siege[k]))
	var fav := int(eff.get("favour", 0))
	if fav != 0 and port_id != "":
		var st := ensure()
		st.favour[port_id] = int(st.favour.get(port_id, 0)) + fav
	return bits


static func _add_field(eff: Dictionary, key: String, word: String, bits: Array) -> void:
	var n := int(eff.get(key, 0))
	if n == 0:
		return
	GameState.set(key, int(GameState.get(key)) + n)
	bits.append("%s加 %d" % [word, n] if n > 0 else "%s减 %d" % [word, -n])


# ── 小件 ──────────────────────────────────────────────

static func _refund(money0: int, taken) -> void:
	GameState.money = money0
	if typeof(taken) != TYPE_DICTIONARY:
		return
	for gid in taken:
		Fleet.add_cargo(str(gid), int(taken[gid]), 0.0)


static func _attention_delta(ix: Dictionary) -> int:
	var hid := str(ix.get("attention_hire", ""))
	if hid != "" and is_hired(hid) and ix.has("attention_hired"):
		return int(ix.get("attention_hired"))
	if ix.has("attention"):
		return int(ix.get("attention"))
	if str(ix.get("type", "")) == "buy":
		var g := GameManager.get_good_by_id(str(ix.get("good", "")))
		if bool(g.get("contraband", false)):
			return 2
	return 0


static func _licence_mul(ix: Dictionary) -> float:
	var m := 1.0
	var need := str(ix.get("needs_licence", ""))
	if need != "" and has_licence(need):
		m *= float(ix.get("licence_mul", 0.9))
	var bonus := str(ix.get("licence_bonus", ""))
	if bonus != "" and has_licence(bonus):
		m *= float(ix.get("bonus_mul", 0.9))
	return m


static func _hire_mul(ix: Dictionary) -> float:
	var hid := str(ix.get("hire_bonus", ""))
	if hid != "" and is_hired(hid):
		return float(ix.get("hire_mul", 0.9))
	return 1.0


static func _may_shift(port_id: String, good: String) -> bool:
	return Economy.is_traded(port_id, good) and Economy.rates.get(port_id, {}).has(good)


static func _rumor_ok(spec: Dictionary) -> bool:
	var port := str(spec.get("port", ""))
	var good := str(spec.get("good", ""))
	var mul := float(spec.get("mul", 1.0))
	if port == "" or good == "" or mul <= 0.0 or is_equal_approx(mul, 1.0):
		return false
	if GameManager.get_port_by_id(port).is_empty() or GameManager.get_good_by_id(good).is_empty():
		return false
	return _may_shift(port, good)


static func _free_qty(good: String) -> int:
	return Fleet.cargo_qty(good) - GameState.contract_kept(good)


static func _cargo_spec(spec: Dictionary, key: String) -> Dictionary:
	var pack = _as_dict(spec.get("effects", {})).get(key, {})
	if typeof(pack) != TYPE_DICTIONARY or str(pack.get("good", "")) == "" or int(pack.get("qty", 0)) <= 0:
		return {}
	return pack


static func _negative_money(eff: Dictionary) -> int:
	var n := int(eff.get("money", 0))
	return -n if n < 0 else 0


static func _dist_name(ix_id: String) -> String:
	var row := district(str(_ix_dist.get(ix_id, "")))
	var name := str(row.get("name", ""))
	return name if name != "" else "城中"


static func _options(ix: Dictionary) -> Array:
	var opts = ix.get("options", [])
	return opts if typeof(opts) == TYPE_ARRAY else []


static func _option(ix: Dictionary, opt_id: String) -> Dictionary:
	for opt in _options(ix):
		if typeof(opt) == TYPE_DICTIONARY and str(opt.get("id", "")) == opt_id:
			return opt
	return {}


static func _merge_choice(ix: Dictionary, opt: Dictionary) -> Dictionary:
	var spec := ix.duplicate(true)
	spec["cost"] = int(opt.get("cost", 0))
	spec["effects"] = opt.get("effects", {}) if typeof(opt.get("effects", {})) == TYPE_DICTIONARY else {}
	spec["text"] = str(opt.get("text", ix.get("text", "")))
	spec["label"] = str(opt.get("label", ix.get("label", "")))
	if typeof(opt.get("rumor", null)) == TYPE_DICTIONARY:
		spec["rumor"] = opt.rumor
	else:
		spec.erase("rumor")
	return spec


static func _as_dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _has_int(arr, n: int) -> bool:
	if typeof(arr) != TYPE_ARRAY:
		return false
	for v in arr:
		if int(v) == n:
			return true
	return false


static func _has_str(arr, s: String) -> bool:
	if typeof(arr) != TYPE_ARRAY:
		return false
	for v in arr:
		if str(v) == s:
			return true
	return false


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg, "money_delta": 0}
