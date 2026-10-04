extends SceneTree
## lane w53-6：港页「今日只开三处」发牌端到端探针（headless、不截图、不开窗）。
## 起因（闸漏判）：岸上三扇门的发牌规矩（设计 §11.2–11.3）在必跑档里只有 smoke 测纯函数 ShoreDraft.deal()、
## check_symbols 认字样与 deal 调用点；港页那一头没人按「再候一日」看门换没换、也没人在船开不出去时看船屋开没开——
## 「再候一日」不加盐位（门永远不换，日志照写「门又换了几处」）、_shore_pin_shipyard 恒 false（缺人缺粮时船屋照样
## 可能不开门，只能干候日子）两处一并改坏，一键全绿（lane w53-6 变异实测）。
## 本探针在真场景树（Main 港页 ShoreBand）上读门：开着的门读 ShoreDoors 的门卡题字，没开的读 ShoreShut 的暗字钮：
##   H1 泉州（船齐粮足、盐位 0）：开三扇、牙行头一扇；开 + 未开 = 九处各一、不重不漏；
##   H2 进开着的一处再「离开」回港：还是原来那三扇（同一日同一盐位，设计「这一手还是原来的三扇门」）；
##   H3 「再候一日」：日子 +1，三扇里至少换了一扇，牙行仍头一扇，记事「门又换了几处」；
##   H4 再候一日连按八回：九处每处都开过门（港页这一头的「盐位转一圈，九处都会开门」）；
##   H5 缺人（二号水手不到最低）：盐位 0–7 每一位船屋都在开着的三扇里，门卡带「船还开不出去」；
##   H6 缺粮（水粮撑不过两日）：同 H5；
##   H7 对照：船齐粮足时盐位 0–7 里船屋至少有一位不开（钉船屋只在开不出去时）。
## 回退即红：_on_shore_wait 去掉 GameState.shore_salt += 1 → H3 / H4；_shore_pin_shipyard 恒 false → H5 / H6；
## _refresh_shore 发牌不传盐位（传 0）→ H3 / H4。
## 用法：godot --headless --path . -s res://tools/qa_w53_6_shore_hand_probe.gd
## 输出末行 QA_W53_6_SHORE_HAND cases=N fails=M；M>0 时 exit 1。

const Clock := preload("res://tools/probe_clock.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 港页九处（Main.GENERIC_FACILITIES / scenes.json 泉州港页同序）的门题
const ALL_DOORS := ["船屋", "行会", "酒馆", "牙行", "旅店", "贡院", "住宅", "寺观", "市舶司"]

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


func _run() -> void:
	print("QA_W53_6_SHORE_HAND_BEGIN")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	var boot_fails: Array = []
	ShotGate.frame_pressure(self)
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", boot_fails, "W53-6 ShoreHand Main")
	if _main == null:
		_check(false, "Main.tscn 挂不出：%s" % str(boot_fails))
		_finish()
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, boot_fails, "W53-6 ShoreHand Main"):
		_check(false, str(boot_fails))
		_finish()
		return

	# ── H1 盐位 0 三扇门、九处不重不漏 ──
	_stage(0, "ok")
	await _open_port()
	var hand0 := _open_doors()
	var shut0 := _shut_doors()
	var all := hand0 + shut0
	var dup := all.filter(func(d) -> bool: return all.count(d) > 1)
	var missing := ALL_DOORS.filter(func(d) -> bool: return not (d in all))
	_check(hand0.size() == 3 and str(hand0[0]) == "牙行" and dup.is_empty() and missing.is_empty() and all.size() == 9,
		"H1 泉州盐位 0：开 %s、未开 %s（三扇、牙行头一扇；九处各一，重 %s 缺 %s）" % [hand0, shut0, dup, missing])

	# ── H2 进一处再离开：还是这三扇 ──
	var dest := _facility_page(str(hand0[1]) if hand0.size() > 1 else "")
	if dest != "":
		_main.load_scene(dest)
		await _settle(4)
		var leave := _find_button(_main.investigation_mode, "离开")
		if leave != null:
			leave.pressed.emit()
			await _settle(4)
	var hand_back := _open_doors()
	_check(dest != "" and str(_main.current_scene_id) == "quanzhou" and hand_back == hand0,
		"H2 进「%s」再离开回港：开着的门 %s → %s（同一日同一盐位不换）" % [dest, hand0, hand_back])

	# ── H3 再候一日：日子 +1，门换了至少一扇 ──
	var d0: int = cal.absolute_day()
	var wait := _find_button(_main.port_mode, "再候一日")
	var has_wait := wait != null	# 按下后岸带重排、这颗钮随之释放，判在按之前记下
	var hand1: Array = []
	if has_wait:
		wait.pressed.emit()
		await _settle(4)
		hand1 = _open_doors()
	var changed := hand1.filter(func(d) -> bool: return not (d in hand0))
	var said := _log_has("门又换了几处")
	_check(has_wait and cal.absolute_day() == d0 + 1 and hand1.size() == 3 and str(hand1[0]) == "牙行" and not changed.is_empty() and said,
		"H3 再候一日：日子 +%d（应 +1），门 %s → %s（换上 %s），记事说「门又换了几处」%s" % [cal.absolute_day() - d0, hand0, hand1, changed, "有" if said else "无"])

	# ── H4 连按八回：九处都开过门 ──
	var seen := {}
	for d in hand0 + hand1:
		seen[str(d)] = true
	for i in 8:
		wait = _find_button(_main.port_mode, "再候一日")
		if wait == null:
			break
		wait.pressed.emit()
		await _settle(3)
		for d in _open_doors():
			seen[str(d)] = true
	var never := ALL_DOORS.filter(func(d) -> bool: return not seen.has(d))
	_check(never.is_empty(), "H4 再候一日连按八回，九处都开过门（没开过：%s）" % [never])

	# ── H5 / H6 缺人、缺粮：每个盐位船屋都开、门卡写「船还开不出去」 ──
	for kind in ["crew", "food"]:
		var bad: Array = []
		for salt in 8:
			_stage(salt, kind)
			await _open_port()
			var hand := _open_doors()
			if not ("船屋" in hand) or _find_label(_main.port_mode, "船还开不出去") == "":
				bad.append("盐位 %d 开 %s" % [salt, hand])
		_check(bad.is_empty(), "%s %s：盐位 0–7 船屋都开、门卡写「船还开不出去」（不合的：%s）" % [
			"H5" if kind == "crew" else "H6", "二号缺人" if kind == "crew" else "水粮撑不过两日", bad])

	# ── H7 对照：船齐粮足时船屋不是每个盐位都开 ──
	var shut_salts: Array = []
	for salt in 8:
		_stage(salt, "ok")
		await _open_port()
		if not ("船屋" in _open_doors()):
			shut_salts.append(salt)
	_check(not shut_salts.is_empty() and _find_label(_main.port_mode, "船还开不出去") == "",
		"H7 对照 船齐粮足：船屋在盐位 %s 不开门、门卡不写「船还开不出去」（钉船屋只在开不出去时）" % [shut_salts])
	_finish()


## 泉州第一章，景定三年四月初十；kind：ok 船齐粮足 / crew 二号缺人 / food 水粮撑不过两日
func _stage(salt: int, kind: String) -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 3000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 4, "day": 10})
	# 水粮放足（连候九日也撑得住）：粮跌破两日会把船屋钉上，H4 量的是盐位轮转、不掺钉船屋
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("sampan", "无名小艍")
	fleet.add_ship("keel_boat", "二号")
	if kind == "crew":
		fleet.ships[1]["crew"] = 5
	elif kind == "food":
		fleet.water = 3
		fleet.food = 3
	gs.shore_salt = salt
	gs.last_port = "quanzhou"


func _open_port() -> void:
	_main.load_scene("quanzhou")
	await _settle(4)


## 开着的门（ShoreDoors 门卡上的题字，按左到右）
func _open_doors() -> Array:
	var out: Array = []
	var band: Node = _main._shore_band()
	var doors: Node = band.get_node_or_null("ShoreDoors") if band != null else null
	if doors == null:
		return out
	for card in doors.get_children():
		if card.is_queued_for_deletion():
			continue
		var t := _door_title(card)
		if t != "":
			out.append(t)
	return out


## 门卡题字：卡里第一行用 SIZE_CARD 的 Label（图标水印字只一个字，跳过）
func _door_title(n: Node) -> String:
	if n is Label and (n as Label).text in ALL_DOORS:
		return (n as Label).text
	for c in n.get_children():
		var t := _door_title(c)
		if t != "":
			return t
	return ""


## 没开的门（ShoreShut 一排暗字钮；围城时牙行那颗改写「牙行・交货」，取「・」前）
func _shut_doors() -> Array:
	var out: Array = []
	var band: Node = _main._shore_band()
	var shut: Node = band.get_node_or_null("ShoreShut") if band != null else null
	if shut == null:
		return out
	for b in shut.get_children():
		if b is Button and not b.is_queued_for_deletion():
			out.append(str((b as Button).text).split("・")[0])
	return out


## 门题 → 设施页 id（同 Main._on_facility_pressed 的改写）
func _facility_page(title: String) -> String:
	var key := {"船屋": "shipyard", "行会": "guild", "酒馆": "tavern", "牙行": "market", "旅店": "inn",
		"贡院": "exam", "住宅": "residence", "寺观": "temple", "市舶司": "yamen"}
	return "quanzhou_%s" % key[title] if key.has(title) else ""


func _log_has(needle: String) -> bool:
	for l in _main._log_lines:
		if str(l).contains(needle):
			return true
	return false


func _find_button(n: Node, text: String) -> Button:
	if n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text == text:
		return n
	for c in n.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _find_label(n: Node, needle: String) -> String:
	if n.is_queued_for_deletion():
		return ""
	if n is Label and (n as Label).is_visible_in_tree() and (n as Label).text.contains(needle):
		return (n as Label).text
	for c in n.get_children():
		var t := _find_label(c, needle)
		if t != "":
			return t
	return ""


func _settle(n: int) -> void:
	await Clock.settle(self, n)


func _check(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _finish() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("QA_W53_6_SHORE_HAND cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
