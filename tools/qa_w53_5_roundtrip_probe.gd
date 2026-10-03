extends SceneTree
## Lane w53-5：存档「全字段往返」探针——摆一份覆盖四分区全量键的场，
## save_game 落盘 → 把单例脏成另一副样子 → load_game 读回 → 逐键与摆的场对账。
## 目标：任何「to_dict 落了、from_dict 没读」或「from_dict 读了、to_dict 没落」的非缺省字段
## 都会在本探针里出 ✗。只动存档位 94，不碰正式位 1..SLOTS。
##   headless 下 SCRIPT ERROR 不自非零退出：判绿须 rc=0 且末行 `QA_W53_5_ROUNDTRIP_END` 在——
##   缺末行 = 中途错误空转，按中断重跑。
## 用法：godot --headless --path . -s res://tools/qa_w53_5_roundtrip_probe.gd

const SLOT := 94

var sl: Node
var gs: Node
var cal: Node
var eco: Node
var fleet: Node
var crew_n: Node
var fails := 0
var cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	sl = root.get_node_or_null("SaveLoad")
	if sl == null:
		push_error("SaveLoad autoload missing")
		quit(1)
		return
	gs = root.get_node("GameState")
	cal = root.get_node("Calendar")
	eco = root.get_node("Economy")
	fleet = root.get_node("Fleet")
	crew_n = root.get_node("Crew")
	_cleanup()

	# ── 1 摆场：四分区各带一批非缺省值 ──
	# calendar
	cal.from_dict({"year": 1256, "month": 7, "day": 18})
	# economy
	eco.from_dict({"rates": {"quanzhou": {"rice": 1.35}, "hakata": {"silk": 0.62}},
		"tariff": 0.10, "broker": 0.05, "investments": {"quanzhou": 2, "mingzhou": 1}})
	# fleet（两艘船：耐久不满 + 货舱各有账）
	fleet.from_dict({
		"ships": [
			{"type": "fuchuan", "name": "安济", "durability": 62.0, "max_durability": 100.0,
				"crew": 18, "sail_level": 2, "armor_level": 1,
				"cargo": {"rice": {"qty": 14, "avg_cost": 12.5}, "pepper": {"qty": 3, "avg_cost": 90.0}}},
			{"type": "cangshan", "name": "通济", "durability": 100.0, "max_durability": 100.0,
				"crew": 8, "sail_level": 1, "armor_level": 2,
				"cargo": {"silk": {"qty": 5, "avg_cost": 150.0}}},
		],
		"water": 47, "food": 33, "morale": 61, "mutiny_cooldown": 2,
	})
	# crew（在职 1 + 辞船 1 + 欠薪；candidate_def 名册键为实测可雇）
	crew_n.from_dict({"hired": {"duogong": "lin_hua"}, "unpaid_months": 1,
		"departed": {"xu_shi": {"role": "通事", "name": "许氏", "when": "景炎元年十月"}}})
	# state（非缺省主线 + 剧情字段 + discover/传闻/委办/封港/围城 + beats 账）
	var scene_state := {
		"money": 4321, "debt": 700, "fame": 12, "martial": 58, "chapter": 2,
		"pu_attention": 5, "peak_money": 6789,
		"network": 3, "merchant_credit": 4, "sea_tendency": 2, "scholar_tendency": -1,
		"hometown_tendency": 1,
		"draft_salt": 7, "shore_salt": 11, "broker_salt": 13, "berth_index": 1,
		"era_trips": 4, "era_profit": 999,
		"era_routes": {"泉州→博多": 3, "泉州→兴化": 2},
		"last_port": "quanzhou", "has_customs_permit": true,
		"identity": "merchant", "player_name": "林往返",
		"news_seen": ["v1255_04", "v1255_07"],
		"crew_history": ["lin_hua"], "met_ids": ["lin_hua", "xu_shi"],
		"visited_ports": ["quanzhou", "hakata", "mingzhou"],
		"flags": {"exam_sat": true, "exam_sat_ch2": true, "guild_quanzhou": true},
		"ledger_notes": ["里正的旧账"],
		"discoveries_found": ["d_reef_east"], "discoveries_reported": ["d_shoal_south"],
		"ending_id": "", "ended": "", "ended_at": "", "ended_text": "", "ended_head": "",
		"contract": {"good_id": "pepper", "qty": 8, "remaining": 5, "dest": "mingzhou",
			"from": "quanzhou", "purse": 800, "unit_purse": 100.0, "paid": 300,
			"due_day": 99999, "deadline_days": 10, "voyage_days": 7, "offer_month": 15076},
		"contract_ban": {"hakata": 15088}, "port_bans": {"hakata": "1271-09"},
		"rumors": {"quanzhou": {"pepper": {"rate": 1.3, "day": 480}}},
		"siege": {"troops": 300, "grain": 120, "wall": 60, "morale": 55, "round": 2,
			"shishou": "kept", "envoy_wang": true, "envoy_kin": false, "lin_hua_sent": true},
		"beats_seen": ["start", "monk"], "loaded_with_beats": true,
	}
	gs.from_dict(scene_state)

	# 快照摆的场（存档前逐分区的 to_dict；label/scene 不入校验——那是存档头不是状态）
	var want_cal: Dictionary = cal.to_dict()
	var want_eco: Dictionary = eco.to_dict()
	var want_fleet: Dictionary = fleet.to_dict()
	var want_crew: Dictionary = crew_n.to_dict()
	var want_state: Dictionary = gs.to_dict()

	# ── 2 落盘 ──
	var saved: bool = sl.call("save_game", SLOT, "quanzhou")
	_report("save_game 落盘", saved, "saved=%s" % str(saved))

	# ── 3 脏场：换个形状，验证读档不是「本来就没变」 ──
	cal.from_dict({"year": 1111, "month": 1, "day": 1})
	eco.from_dict({"rates": {}, "tariff": 0.99, "broker": 0.99, "investments": {}})
	fleet.from_dict({"ships": [], "water": 0, "food": 0, "morale": 1, "mutiny_cooldown": 9})
	crew_n.from_dict({"hired": {}, "unpaid_months": 0, "departed": {}})
	gs.from_dict({"money": 1, "player_name": "占位", "chapter": 9, "visited_ports": ["nowhere"],
		"beats_seen": [], "loaded_with_beats": false})

	# ── 4 读回 ──
	var loaded: bool = sl.call("load_game", SLOT)
	_report("load_game 读回", loaded, "loaded=%s" % str(loaded))

	# ── 5 逐分区对账 ──
	var got_cal: Dictionary = cal.to_dict()
	var got_eco: Dictionary = eco.to_dict()
	var got_fleet: Dictionary = fleet.to_dict()
	var got_crew: Dictionary = crew_n.to_dict()
	var got_state: Dictionary = gs.to_dict()

	_report("calendar 逐键", got_cal == want_cal, "want=%s got=%s" % [JSON.stringify(want_cal), JSON.stringify(got_cal)])
	# economy：Economy.initialize 会给「没进 rates 的 market 港」randf_range 补值（开局随机扰动），
	# 摆进存档的港不该被补值盖——只比「摆了的那几港/货/等级」与「玩家改的 tariff/broker」
	var want_rates: Dictionary = want_eco.get("rates", {})
	var got_rates: Dictionary = got_eco.get("rates", {})
	var rates_ok := true
	for pid in want_rates:
		for gid in (want_rates[pid] as Dictionary):
			var w: float = want_rates[pid][gid]
			var g = float((got_rates.get(pid, {}) as Dictionary).get(gid, -999.0))
			if absf(w - g) > 0.001:
				rates_ok = false
				print("    ✗ economy.rates.%s.%s want=%s got=%s" % [pid, gid, w, g])
	var inv_ok := true
	for pid in (want_eco.get("investments", {}) as Dictionary):
		var w: int = (want_eco["investments"] as Dictionary)[pid]
		var g: int = int((got_eco.get("investments", {}) as Dictionary).get(pid, -999))
		if w != g:
			inv_ok = false
			print("    ✗ economy.investments.%s want=%d got=%d" % [pid, w, g])
	var tb_ok: bool = is_equal_approx(float(got_eco.get("tariff", -1.0)), float(want_eco.get("tariff", -2.0))) \
			and is_equal_approx(float(got_eco.get("broker", -1.0)), float(want_eco.get("broker", -2.0)))
	_report("economy 摆场键", rates_ok and inv_ok and tb_ok,
		"rates=%s investments=%s tariff/broker=%s" % [rates_ok, inv_ok, tb_ok])
	# fleet：逐键等比（int/float 语义同级差按 dobeq 挑平）——甲板、船名、货舱、水量都要原样回
	var fleet_ok := true
	for k in ["water", "food", "morale", "mutiny_cooldown"]:
		if int(got_fleet.get(k, -1)) != int(want_fleet.get(k, -2)):
			fleet_ok = false
			print("    ✗ fleet.%s want=%s got=%s" % [k, want_fleet.get(k), got_fleet.get(k)])
	var want_ships: Array = want_fleet.get("ships", [])
	var got_ships: Array = got_fleet.get("ships", [])
	if want_ships.size() != got_ships.size():
		fleet_ok = false
		print("    ✗ fleet.ships 艘数 want=%d got=%d" % [want_ships.size(), got_ships.size()])
	else:
		for i in range(want_ships.size()):
			if not _dict_semieq(want_ships[i], got_ships[i]):
				fleet_ok = false
				print("    ✗ fleet.ships[%d] want=%s got=%s" % [i, JSON.stringify(want_ships[i]), JSON.stringify(got_ships[i])])
	_report("fleet 逐键（漏水粮、船、货舱）", fleet_ok, "艘数=%d/%d" % [got_ships.size(), want_ships.size()])
	var crew_same: bool = JSON.stringify(_sort_dict(got_crew)) == JSON.stringify(_sort_dict(want_crew))
	_report("crew 逐键", crew_same, "want=%s got=%s" % [JSON.stringify(want_crew), JSON.stringify(got_crew)])

	# state 逐键对——这是主战场（存档瑞丽面）：flags 由 _harden_state 归并型，剩余全键应等（数同等比）
	var state_fail := []
	for k in want_state:
		var w = want_state[k]
		var g = got_state.get(k)
		if not _val_semieq(w, g):
			state_fail.append("%s(want=%s got=%s)" % [k, JSON.stringify(w), JSON.stringify(g)])
	_report("state 逐键（%d 键）" % want_state.size(), state_fail.is_empty(),
		"差键：%s" % "; ".join(state_fail.slice(0, 4)))

	# ── 6 剧情运行时复核（读完后真调一次，证明不是账面绿） ──
	_report("siege_open", bool(gs.call("siege_open")), "围城账读回应开")
	_report("siege_power 数", float(gs.call("siege_power")) > 0.0, "siege_power=%s" % str(gs.call("siege_power")))
	_report("contract 剩余", int((gs.call("contract_status") as Dictionary).get("remaining", -1)) == 5,
		"contract=%s" % JSON.stringify(gs.call("contract_status")))
	_report("拍账带档", gs.get("beats_seen") == ["start", "monk"] and bool(gs.get("loaded_with_beats")),
		"beats=%s loaded=%s" % [JSON.stringify(gs.get("beats_seen")), str(gs.get("loaded_with_beats"))])
	_report("visited_ports", gs.get("visited_ports") == ["quanzhou", "hakata", "mingzhou"],
		"visited=%s" % JSON.stringify(gs.get("visited_ports")))
	_report("met_ids", gs.get("met_ids") == ["lin_hua", "xu_shi"],
		"met_ids=%s" % JSON.stringify(gs.get("met_ids")))
	_report("loaded_with_beats 入档", bool(gs.get("loaded_with_beats")),
		"v20-c2 《（都入存档）》钉——读回 true 方不再重 seed")
	_report("fleet 两艘+货舱", (got_fleet.get("ships", []) as Array).size() == 2
		and int((((got_fleet["ships"] as Array)[0] as Dictionary).get("cargo", {}) as Dictionary).get("rice", {}).get("qty", -1)) == 14,
		"ships=%s" % JSON.stringify(got_fleet.get("ships", [])))

	_cleanup()
	if fails == 0:
		print("QA_W53_5_ROUNDTRIP cases=%d fails=0" % cases)
		print("QA_W53_5_ROUNDTRIP_END")
		quit(0)
	else:
		print("QA_W53_5_ROUNDTRIP cases=%d fails=%d" % [cases, fails])
		quit(1)


func _report(name: String, ok: bool, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1


## 字典按键排序（序不敏感对账；Godot Dictionary 键序不定）
func _sort_dict(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		var v = d[k]
		if typeof(v) == TYPE_DICTIONARY:
			out[k] = _sort_dict(v)
		else:
			out[k] = v
	return out


func _sort_val(v):
	if typeof(v) == TYPE_DICTIONARY:
		return _sort_dict(v)
	return v


## 语义等比：int 与 float 同级（存档 JSON 反序列化后 int 会成 float）；
## 字典与数组深比、其余 ==。
func _val_semieq(a, b) -> bool:
	if (typeof(a) == TYPE_INT and typeof(b) == TYPE_FLOAT) \
			or (typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_INT):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		return _dict_semieq(a, b)
	if typeof(a) == TYPE_ARRAY:
		var aa: Array = a
		var bb: Array = b
		if aa.size() != bb.size():
			return false
		for i in range(aa.size()):
			if not _val_semieq(aa[i], bb[i]):
				return false
		return true
	if typeof(a) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


func _dict_semieq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or not _val_semieq(a[k], b.get(k)):
			return false
	return true


func _cleanup() -> void:
	var base := str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT
	for suffix in ["", ".bak", ".tmp", ".v1", ".v2", ".v3", ".bak.v1"]:
		var p: String = base + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
