extends SceneTree
## Lane w54-saves：旧版本档迁到本版「逐项对」——按仓里真有过的三种旧结构各摆一卷满档（每个当时有的键都摆非缺省值），
## 读进本版后逐键比：没变的键原样、迁移该变的按口径变、当时还没有的键落缺省；再验回写落盘的那一份。
## 三种旧结构（git 史：SaveLoad.gd 的 VERSION / SAVE_SCHEMA 与 GameState / Crew 的 to_dict 键集逐笔对过）：
##   v1 —— e4eb4e87 之前：头 version=3、没有 save_schema；crew.hired 是「职事 → 名册整条」快照；没有 crew.departed、
##          state.ended_head / met_ids / beats_seen / loaded_with_beats；边记 ledger_notes 记的是令牌（36b08ded 起才换短句）；
##   v2 —— e4eb4e87 起：save_schema=2；多了 crew.departed（dfd367b7）、state.ended_head（744a5054）；仍无 met_ids；
##   v3 —— 8df179b7 起：save_schema=3；多了 state.met_ids，后期（855119fc）又多 beats_seen / loaded_with_beats；hired 仍是快照。
## 迁移该变的（docs/存档迁移矩阵.md §二）：hired 快照收成候选 id；v1 / v2 的 met_ids 按曾雇、在船、守城见过林华回填；
## 读档清洗照常（旗只收 true、勘见已领的胜过未报、边记令牌换短句并去重）。头与结构：回写落盘的那一份 save_schema 到本版，
## 头 version 也到本版——结构已是 v4（hired 只存 id），旧读档器只拒 version > 3，顶着旧头 3 落盘就会被旧版收下、
## 把 id 当快照读（SaveLoad.gd 头注：结构不兼容「两者同升，让旧版也拒」）。另验原件另存 .v<N> 逐字节保真、
## 迁好的档再读不再改写、读后再记再读五分区不变。另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红）。
## 只动存档位 544 / 545（w54-saves 自用段），不碰正式位 1..SLOTS。
## 用法：godot --headless --path . -s res://tools/qa_w54_saves_migrate_probe.gd
## 末行 QA_W54_SAVES_MIGRATE cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 544
const SLOT_AGAIN := 545

var sl: Node
var gs: Node
var cal: Node
var eco: Node
var fleet: Node
var crew: Node
var gm: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
## GameState.from_dict({}) 之后的 to_dict：旧档没有的 state 键读进来该是这些缺省
var _state_defaults: Dictionary = {}


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
	await process_frame
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
	gs.from_dict({})
	_state_defaults = gs.to_dict()
	_case("v1", _old(1))
	_case("v2", _old(2))
	_case("v3", _old(3))
	# 没有头的 v1（version 键缺省按 0 读、save_schema 缺省 1）：照走全链，回写也补上本版的头
	var headless := _old(1)
	headless.erase("version")
	_case("v1 无头", headless)
	_cleanup()
	_report()


# ── 旧档 ─────────────────────────────────────────────

## schema 那一版的满档。各键都摆非缺省值；当时还没有的键不摆。
func _old(schema: int) -> Dictionary:
	var state := {
		"money": 4321, "debt": 700, "fame": 37, "martial": 58, "chapter": 2, "pu_attention": 15,
		"has_customs_permit": true, "last_port": "fuzhou",
		# 旗：一枚 false、一枚非布尔——读档清洗只收 true（lane h1h2），这两枚读进来就没了
		"flags": {"exam_sat": true, "exam_sat_ch2": true, "guild_fuzhou": true, "chen_zan_stake": true,
			"lin_hua_reminded": true, "zz_off": false, "zz_word": "是"},
		"network": 3, "merchant_credit": 4, "sea_tendency": 2, "scholar_tendency": 1,
		# 边记：v1..v3 记令牌；令牌与它的短句同在一卷时读进来只留一条
		"ledger_notes": ["lin_cargo_defaulted", "storm_jettison_recorded", "背了林阿舶的货约", "拓「破碑」　碑文残缺。"],
		"ending_id": "",
		# 勘见：已领的胜过未报（同一枚两录都有时只算已领）
		"discoveries_found": ["beacon_ruin", "whale_route"], "discoveries_reported": ["whale_route", "coral_shoal"],
		"visited_ports": ["xinghua", "quanzhou", "fuzhou", "wenzhou", "mingzhou"],
		"peak_money": 6789, "draft_salt": 7, "shore_salt": 11, "broker_salt": 13, "berth_index": 1,
		"contract": {"good_id": "tea", "qty": 12, "remaining": 9, "dest": "mingzhou", "from": "fuzhou",
			"purse": 860, "unit_purse": 71.5, "paid": 215, "due_day": 99999, "deadline_days": 14,
			"voyage_days": 9, "offer_month": 1262 * 12 + 6},
		"contract_ban": {"wenzhou": 1262 * 12 + 6},
		"rumors": {"mingzhou": {"tea": {"rate": 1.45, "day": 2600}}},
		"player_name": "林迁徙", "hometown_tendency": 3, "identity": "undecided",
		"news_seen": ["n_1256_03_taixue", "n_1256_05_wentianxiang"],
		"era_trips": 4, "era_routes": {"泉州→博多唐房": 3, "泉州→福州": 2}, "era_profit": 999,
		"crew_history": ["pu_alie", "wu_zhen", "chen_laodao"],
		"port_bans": {"quanzhou": "1262-08"},
		"siege": {"troops": 300, "grain": 120, "wall": 60, "morale": 55, "round": 0, "shishou": "",
			"envoy_wang": false, "envoy_kin": false, "lin_hua_sent": false},
		"ended": "", "ended_at": "", "ended_text": "",
	}
	var crew_part := {"hired": {"huozhang": _snapshot("wu_zhen"), "duogong": _snapshot("chen_laodao")}, "unpaid_months": 1}
	if schema >= 2:
		crew_part["departed"] = {"pu_alie": {"role": "tongshi", "name": "蒲阿烈", "when": "景定二年三月"}}
		state["ended_head"] = "兴化・景炎元年十二月・援绝"
	if schema >= 3:
		state["met_ids"] = ["lin_hua", "pu_steward"]
		state["beats_seen"] = ["start", "monk"]
		state["loaded_with_beats"] = true
	var d := {
		"version": 3,
		"calendar": {"year": 1262, "month": 6, "day": 14},
		"economy": {"rates": {"fuzhou": {"tea": 0.73, "grain": 1.21}, "quanzhou": {"pepper": 1.3}},
			"tariff": 0.1, "broker": 0.05, "investments": {"fuzhou": 2, "quanzhou": 1}},
		"fleet": {"ships": [
			{"type": "fu_ship_medium", "name": "安济", "durability": 231.0, "max_durability": 300.0, "crew": 41,
				"sail_level": 2, "armor_level": 3,
				"cargo": {"tea": {"qty": 12, "avg_cost": 31.5}, "sulfur": {"qty": 7, "avg_cost": 60.25}}},
			{"type": "keel_boat", "name": "通济", "durability": 120.0, "max_durability": 160.0, "crew": 17,
				"sail_level": 1, "armor_level": 2, "cargo": {"grain": {"qty": 30, "avg_cost": 6.0}}}],
			"water": 47, "food": 33, "morale": 61, "mutiny_cooldown": 2},
		"crew": crew_part,
		"state": state,
		"scene": "fuzhou",
		"label": "景定三年　六月十四　福州　4321 钱",
	}
	if schema >= 2:
		d[str(sl.get("SCHEMA_KEY"))] = schema
	return d


## v1..v3 的 hired：Crew.hire 把名册那一整条（候选 def）原样存进去
func _snapshot(cand_id: String) -> Dictionary:
	return (crew.candidate_def(cand_id) as Dictionary).duplicate(true)


## 迁好、读进来以后该是什么样（五分区 to_dict 的期望）
func _want(old: Dictionary) -> Dictionary:
	var st: Dictionary = (old["state"] as Dictionary).duplicate(true)
	st["flags"] = {"exam_sat": true, "exam_sat_ch2": true, "guild_fuzhou": true, "chen_zan_stake": true, "lin_hua_reminded": true}
	st["ledger_notes"] = [gs.ledger_note_text("lin_cargo_defaulted"), gs.ledger_note_text("storm_jettison_recorded"),
		"拓「破碑」　碑文残缺。"]
	st["discoveries_found"] = ["beacon_ruin"]
	st["discoveries_reported"] = ["whale_route", "coral_shoal"]
	if not st.has("met_ids"):
		# v2→v3 回填：曾雇（按 crew_history 先后）、此刻在船（按 hired 键序），再守城见过林华（旗 lin_hua_reminded）
		var met: Array = []
		for cid in ["pu_alie", "wu_zhen", "chen_laodao", "wu_zhen", "chen_laodao"]:
			var who := str(gm.character_for_crew(cid).get("id", ""))
			if who != "" and not (who in met):
				met.append(who)
		met.append("lin_hua")
		st["met_ids"] = met
	for k in ["ended_head"]:
		if not st.has(k):
			st[k] = ""
	if not st.has("beats_seen"):
		st["beats_seen"] = []
		st["loaded_with_beats"] = false
	var cr: Dictionary = (old["crew"] as Dictionary).duplicate(true)
	cr["hired"] = {"huozhang": "wu_zhen", "duogong": "chen_laodao"}
	if not cr.has("departed"):
		cr["departed"] = {}
	return {"calendar": old["calendar"], "economy": old["economy"], "fleet": old["fleet"], "crew": cr, "state": st}


# ── 一卷 ─────────────────────────────────────────────

func _case(name: String, old: Dictionary) -> void:
	_cleanup()
	var from_schema := int(old.get(str(sl.get("SCHEMA_KEY")), 1))
	var text := JSON.stringify(old, "\t", false)
	_write(_path(SLOT), text)
	_dirty()
	var e0: int = _tally.lines.size()
	_expect(sl.load_game(SLOT), "%s：读得进" % name, "")
	var want := _want(old)
	var got := _parts()
	for part in ["calendar", "economy", "fleet", "crew", "state"]:
		var w: Dictionary = want[part]
		var g: Dictionary = got[part]
		var d := _subset("", w, g, [])
		_expect(d.is_empty(), "%s：%s 逐键对（%d 键）" % [name, part, w.size()], "; ".join(d.slice(0, 4)))
	# 本版 state 里上面没逐项对到的键（日后别的 lane 新加、带缺省的字段）：旧档里没有，读进来须是 from_dict 的缺省
	var extra: Array = []
	for k in got["state"]:
		if not (want["state"] as Dictionary).has(k):
			_diff("state.%s" % k, _state_defaults.get(k), got["state"][k], extra)
	_expect(extra.is_empty(), "%s：其余 state 键（旧档里没有）读进来是缺省" % name, "; ".join(extra.slice(0, 3)))

	# 回写落盘的那一份
	var back := _read(_path(SLOT))
	_expect(int(back.get(str(sl.get("SCHEMA_KEY")), 0)) == int(sl.get("SAVE_SCHEMA")),
		"%s：回写正本 save_schema 到本版 %d" % [name, int(sl.get("SAVE_SCHEMA"))],
		"save_schema=%s" % str(back.get(str(sl.get("SCHEMA_KEY")))))
	_expect(int(back.get("version", 0)) == int(sl.get("VERSION")),
		"%s：回写正本头 version 跟着到本版 %d（旧读档器只拒 version > 3，顶着旧头落盘的 v4 结构会被旧版收下）" % [name, int(sl.get("VERSION"))],
		"回写后 version=%s（原件 %s）" % [str(back.get("version")), str(old.get("version", "缺"))])
	var hired: Dictionary = (back.get("crew", {}) as Dictionary).get("hired", {})
	_expect(JSON.stringify(hired) == JSON.stringify({"huozhang": "wu_zhen", "duogong": "chen_laodao"}),
		"%s：回写正本 crew.hired 已收成 id" % name, JSON.stringify(hired))
	_expect(str(back.get("label", "")) == str(old["label"]) and str(back.get("scene", "")) == "fuzhou",
		"%s：回写正本题签、场景原样" % name, "label=%s scene=%s" % [str(back.get("label")), str(back.get("scene"))])
	var keep := _path(SLOT) + ".v%d" % from_schema
	_expect(FileAccess.file_exists(keep) and _text(keep) == text, "%s：原件另存 %s 逐字节保真" % [name, keep.get_file()], "")

	# 迁好的档再读：不再迁、不改写、读进来同一局
	var migrated := _text(_path(SLOT))
	_dirty()
	_expect(sl.load_game(SLOT), "%s：迁好的档再读得进" % name, "")
	var d2 := _diff("", got, _parts(), [])
	_expect(d2.is_empty() and _text(_path(SLOT)) == migrated and _text(keep) == text,
		"%s：迁好的档再读——不再改写、原件不动、读进来同一局" % name, "; ".join(d2.slice(0, 3)))

	# 读后记一卷（本版 save_game）再读：五分区不变
	_expect(sl.save_game(SLOT_AGAIN, "fuzhou"), "%s：读后再记一卷" % name, "")
	var fresh := _read(_path(SLOT_AGAIN))
	_expect(int(fresh.get("version", 0)) == int(sl.get("VERSION")) and int(fresh.get(str(sl.get("SCHEMA_KEY")), 0)) == int(sl.get("SAVE_SCHEMA")),
		"%s：再记的一卷头与结构版都是本版" % name, "")
	_dirty()
	_expect(sl.load_game(SLOT_AGAIN), "%s：再记的一卷读得进" % name, "")
	var d3 := _diff("", got, _parts(), [])
	_expect(d3.is_empty(), "%s：再记再读五分区不变" % name, "; ".join(d3.slice(0, 3)))
	var n: int = _tally.lines.size() - e0
	_expect(n == 0, "%s：全程 SCRIPT ERROR 0 条" % name, "%d 条，首条：%s" % [n, str(_tally.lines[e0]) if n > 0 else ""])


## 五分区快照：to_dict 交出的是单例里的活容器（船、货舱、行情、城防账……），续跑会就地改它们——深拷一份才是「那一刻」
func _parts() -> Dictionary:
	return {"calendar": cal.to_dict(), "economy": eco.to_dict(), "fleet": fleet.to_dict(),
		"crew": crew.to_dict(), "state": gs.to_dict()}.duplicate(true)


## 脏场：读档若没把五个单例盖回来，逐键对必红
func _dirty() -> void:
	cal.from_dict({"year": 1111, "month": 1, "day": 1})
	eco.from_dict({"rates": {}, "tariff": 0.99, "broker": 0.99, "investments": {"wenzhou": 9}})
	fleet.from_dict({"ships": [], "water": 1, "food": 1, "morale": 1, "mutiny_cooldown": 9})
	crew.from_dict({"hired": {"zashi": "zhou_suanchou"}, "unpaid_months": 9, "departed": {"zz": {}}})
	gs.from_dict({"money": 1, "player_name": "占位", "chapter": 9, "met_ids": ["zz"], "ended_head": "占位",
		"beats_seen": ["zz"], "loaded_with_beats": true, "flags": {"zz_dirty": true}})


## 期望 want 的每个键都得在 got 里同值（int / float 同值算同；下层字典连键序一起比）；got 多出的键另由调用方判
func _subset(path: String, want: Dictionary, got: Dictionary, out: Array) -> Array:
	for k in want:
		var p := "%s%s" % [path, k]
		if not got.has(k):
			out.append("%s 缺键" % p)
			continue
		_diff(p, want[k], got[k], out)
	return out


## 语义逐键比：int / float 同值算同；字典比键集与键序；数组按序
func _diff(path: String, a, b, out: Array) -> Array:
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		if not is_equal_approx(float(a), float(b)):
			out.append("%s：%s ≠ %s" % [path, str(a), str(b)])
		return out
	if typeof(a) != typeof(b):
		out.append("%s：型 %s ≠ %s（%s / %s）" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a).left(60), str(b).left(60)])
		return out
	if a is Dictionary:
		if (a as Dictionary).keys() != (b as Dictionary).keys():
			out.append("%s：键 %s ≠ %s" % [path, str((a as Dictionary).keys()).left(120), str((b as Dictionary).keys()).left(120)])
		for k in a:
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
		out.append("%s：%s ≠ %s" % [path, str(a).left(120), str(b).left(120)])
	return out


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], "")
	print("QA_W54_SAVES_MIGRATE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail if not ok else ""])
	if not ok:
		fails += 1


func _path(slot: int) -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % slot


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	return t


func _read(path: String) -> Dictionary:
	var d = JSON.parse_string(_text(path))
	return d if d is Dictionary else {}


func _cleanup() -> void:
	for slot in [SLOT, SLOT_AGAIN]:
		for suffix in ["", ".bak", ".tmp", ".v1", ".v2", ".v3"]:
			if FileAccess.file_exists(_path(slot) + suffix):
				DirAccess.remove_absolute(_path(slot) + suffix)
