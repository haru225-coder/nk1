extends SceneTree
## 无界面驱动 P7 行会入行 / 贡院赴试：扣费与门槛、赴试两支、每章一次、1268 打平读 exam_sat、三月下旬跨月赴试 / 誊录、科场港正文不写「只能替人誊录」（lane w53-6）。
## 跑法：godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
## -s 入口在编译期看不到自动加载名，单例一律在 _initialize 之后从根节点取。

const JOIN_TEXT := "交会费入行"
const SIT_TEXT := "入场赴试"
const COPY_TEXT := "替人抄三日"
const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
const ScriptErrTally := preload("res://tools/script_err_tally.gd")  # 本进程 SCRIPT ERROR 即红（lane w53-11）

var _fails: Array = []
var _gs
var _gm
var _cal
## lane w53-11：本进程 SCRIPT ERROR / Parse Error 即红（同 story :3135 判闸，共用件 tools/script_err_tally.gd）。
## 此前运行期脚本错只中止出错的那个函数：子函数 / 游戏代码里出错，断言整段跳过、fails 不涨、退出码守 0；
## _run 自己的代码行出错则 quit 不再执行、进程空转到外层 timeout。_run_guarded 包一层两形都就地判红。
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_gm = root.get_node("GameManager")
	_cal = root.get_node("Calendar")
	var main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run_guarded(main)


func _run_guarded(main) -> void:
	await _run(main)
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL ", msg)
	GateReport.check(false, msg)


func _ok(msg: String) -> void:
	print("OK   ", msg)
	GateReport.check(true, msg)


func _button_with_text(root_node: Node, text: String) -> Button:
	var hits: Array = []
	_collect(root_node, text, hits, true)
	if hits.is_empty():
		return null
	return hits[0]


## 只读态卡底那枚 disabled 钮（本港已入行 / 本港无会籍 / 本章已赴 / 本港无贡院科场）。
func _has_stamp(root_node: Node, text: String) -> bool:
	var b := _button_with_text(root_node, text)
	return b != null and b.disabled


func _has_label(root_node: Node, text: String) -> bool:
	var hits: Array = []
	_collect(root_node, text, hits, false)
	return not hits.is_empty()


func _collect(n: Node, text: String, hits: Array, want_button: bool) -> void:
	# 设施页用 queue_free 换条子，同一帧里旧节点还在树上。
	if n.is_queued_for_deletion():
		return
	if want_button and n is Button and (n as Button).text == text:
		hits.append(n)
	elif not want_button and n is Label and (n as Label).text == text:
		hits.append(n)
	for c in n.get_children():
		_collect(c, text, hits, want_button)


func _clear_flag(f: String) -> void:
	_gs.flags.erase(f)


func _snap() -> Dictionary:
	return {
		"money": int(_gs.money),
		"credit": int(_gs.merchant_credit),
		"network": int(_gs.network),
		"fame": int(_gs.fame),
		"scholar": int(_gs.scholar_tendency),
		"sea": int(_gs.sea_tendency),
		"day": int(_cal.absolute_day()),
	}


## 行会页上「运往 X　多 N」的行情抄本（树序），跳过同帧待删的旧条子。
func _spread_hints(root_node: Node) -> Array:
	var out: Array = []
	if root_node.is_queued_for_deletion():
		return out
	if root_node is Label:
		var t: String = (root_node as Label).text
		if t.begins_with("运往 ") and t.contains("　多 "):
			out.append(t)
	for c in root_node.get_children():
		out.append_array(_spread_hints(c))
	return out


## ── 0. 行情抄本条数（lane gd19）：商誉 < 8 抄 3 条、≥ 8 抄 5 条，再高也不多抄 ──
## 条数、门槛用字面量（不读 main.GUILD_CREDIT_WIDE），改常量也判红。行情钉平（rate 1.0），
## 可抄总数须 ≥ 6，否则两档上限压不住、5→4 这类改动测不出，直接判红而不是空转。
func _check_spread_rows(main) -> void:
	var eco = root.get_node("Economy")
	var saved: Dictionary = eco.rates.duplicate(true)
	for pid in eco.rates.keys():
		for gid in eco.rates[pid].keys():
			eco.rates[pid][gid] = 1.0
	var all_rows: Array = main._collect_spreads("quanzhou", 0)
	# 期望条目取自同一 _collect_spreads，排序另由这里独立核：利润须不增，否则「前 N 条」就不是最赚的 N 条
	var sorted_ok := true
	for i in range(1, all_rows.size()):
		if int(all_rows[i]["profit"]) > int(all_rows[i - 1]["profit"]):
			sorted_ok = false
	if all_rows.size() < 6:
		_fail("行情钉平后泉州只有 %d 条可抄价差（须 ≥ 6 才测得出上限）" % all_rows.size())
	elif not sorted_ok:
		_fail("_collect_spreads 没按利润降序：%s" % str(all_rows.map(func(r): return int(r["profit"]))))
	else:
		for case in [{"credit": 7, "rows": 3}, {"credit": 8, "rows": 5}, {"credit": 30, "rows": 5}]:
			_gs.merchant_credit = int(case["credit"])
			main.load_scene("quanzhou_guild")
			if str(main.current_scene_id) != "quanzhou_guild":
				_fail("没能打开泉州行会，现为 %s" % str(main.current_scene_id))
				continue
			var want: Array = []
			for row in all_rows.slice(0, int(case["rows"])):
				want.append("运往 %s　多 %d" % [_gm.get_port_name(row["port"]), int(row["profit"])])
			var got: Array = _spread_hints(main)
			if got.size() != want.size():
				_fail("泉州行会商誉 %d 抄了 %d 条行情，应 %d 条" % [case["credit"], got.size(), want.size()])
			elif got != want:
				_fail("泉州行会商誉 %d 的行情不是利润前 %d 条：%s ≠ %s" % [case["credit"], want.size(), got, want])
			else:
				_ok("泉州行会商誉 %d：抄利润前 %d 条行情（可抄 %d 条）" % [case["credit"], want.size(), all_rows.size()])
	eco.rates = saved


func _run(main) -> void:
	# Main._ready 里 call_deferred(start_game)，空等几帧直到开场场景写上。
	for _i in 8:
		if str(main.current_scene_id) != "":
			break
		await process_frame

	_gs.chapter = 1
	_gs.last_port = "quanzhou"
	for port in ["quanzhou", "hakata", "guangzhou"]:
		_clear_flag("guild_%s" % port)

	_check_spread_rows(main)

	# ── 1. 泉州入行成功 ──
	_gs.money = 5000
	_gs.merchant_credit = 8
	_gs.network = 1
	main.load_scene("quanzhou_guild")
	# lane w53-10：正文写「海商信用 N」，同页入行工席也叫海商信用，不再并出「商誉 N」
	if not _has_label(main, "海商信用 8　人脉 1"):
		_fail("泉州入行工席副题不是「海商信用 8　人脉 1」（与行会正文、船籍簿同名）")
	elif not _has_label(main, "会费 2000　海商信用须 8。"):
		_fail("泉州入行门槛行不是「会费 2000　海商信用须 8。」")
	else:
		_ok("泉州入行工席与正文同叫海商信用")
	var join := _button_with_text(main, JOIN_TEXT)
	if join == null:
		_fail("泉州行会没有「%s」" % JOIN_TEXT)
	else:
		var b := _snap()
		join.pressed.emit()
		var a := _snap()
		if a["money"] != b["money"] - 2000:
			_fail("入行钱 %d→%d，应减 2000" % [b["money"], a["money"]])
		elif a["credit"] != b["credit"] + 4:
			_fail("入行商誉 %d→%d，应加 4" % [b["credit"], a["credit"]])
		elif a["network"] != b["network"] + 2:
			_fail("入行人脉 %d→%d，应加 2" % [b["network"], a["network"]])
		elif not _gs.has_flag("guild_quanzhou"):
			_fail("入行后未写 guild_quanzhou")
		else:
			_ok("泉州入行：钱 -2000、商誉 +4、人脉 +2、写 guild_quanzhou")
		if str(main.current_scene_id) != "quanzhou_guild":
			_fail("入行后没停在泉州行会，而是 %s" % str(main.current_scene_id))
		elif _button_with_text(main, JOIN_TEXT) != null:
			_fail("入行后刷新仍有「%s」" % JOIN_TEXT)
		elif not _has_stamp(main, "本港已入行"):
			_fail("入行后卡底没有 disabled「本港已入行」")
		else:
			_ok("刷新后为已入行态，无再次扣费按钮")
		var again := _snap()
		main._on_guild_join("quanzhou")
		var after := _snap()
		if after["money"] != again["money"] or after["credit"] != again["credit"] or after["network"] != again["network"]:
			_fail("已入行再调入行仍改账 %s→%s" % [again, after])
		else:
			_ok("已入行再调入行不扣钱")

	# ── 2. 入行门槛拦截：商誉 7 / 现钱 1999 ──
	for case in [
		{"port": "hakata", "money": 5000, "credit": 7, "why": "商誉 7"},
		{"port": "guangzhou", "money": 1999, "credit": 8, "why": "现钱 1999"},
	]:
		var port: String = case["port"]
		_clear_flag("guild_%s" % port)
		_gs.money = int(case["money"])
		_gs.merchant_credit = int(case["credit"])
		main.load_scene("%s_guild" % port)
		var chip := _button_with_text(main, JOIN_TEXT)
		if chip == null:
			_fail("%s 行会门槛不足时按钮不在（应在，按下只说缘由）" % port)
			continue
		var b2 := _snap()
		chip.pressed.emit()
		var a2 := _snap()
		var why_text := str(main._guild_join_block(port))
		if port == "hakata" and why_text != "海商信用不足（7，须 8）":
			_fail("博多信用不足的缘由不是「海商信用不足（7，须 8）」：%s" % why_text)
		if a2["money"] != b2["money"] or a2["credit"] != b2["credit"] or a2["network"] != b2["network"]:
			_fail("%s %s 被拦时仍改账 %s→%s" % [port, case["why"], b2, a2])
		elif _gs.has_flag("guild_%s" % port):
			_fail("%s %s 被拦时仍写了旗标" % [port, case["why"]])
		else:
			_ok("%s %s：入行被拦，钱/商誉/人脉/旗标不变" % [port, case["why"]])

	# ── 非入行港：明州行会无会籍、无按钮 ──
	_gs.money = 5000
	_gs.merchant_credit = 8
	main.load_scene("mingzhou_guild")
	if str(main.current_scene_id) != "mingzhou_guild":
		_fail("没能打开明州行会，现为 %s" % str(main.current_scene_id))
	elif _button_with_text(main, JOIN_TEXT) != null:
		_fail("明州行会出现了「%s」" % JOIN_TEXT)
	elif not _has_stamp(main, "本港无会籍"):
		_fail("明州行会卡底没有 disabled「本港无会籍」")
	else:
		_ok("明州行会：本港无会籍，无入行按钮")

	# ── 2b. 港卡 remap：从港页按 city_guild 进实际页 {港}_guild；带后缀直调也认港、只扣一次 ──
	for port in ["hakata", "guangzhou"]:
		_clear_flag("guild_%s" % port)
		_gs.money = 5000
		_gs.merchant_credit = 8
		_gs.last_port = port
		main.load_scene(port)
		if not ("city_guild" in main.shore_hand):
			main.shore_hand.append("city_guild")
		main._on_facility_pressed({"id": "city_guild"})
		var page := "%s_guild" % port
		if str(main.current_scene_id) != page:
			_fail("%s 港卡 city_guild 没进 %s，而是 %s" % [port, page, str(main.current_scene_id)])
			continue
		var chip := _button_with_text(main, JOIN_TEXT)
		if chip == null:
			_fail("%s 实际页 %s 认不出入行港（无「%s」）" % [port, page, JOIN_TEXT])
			continue
		var b := _snap()
		chip.pressed.emit()
		main._on_guild_join(page)
		main._on_guild_join("%s_guild" % page)
		main._on_guild_join(port)
		var a := _snap()
		if a["money"] != b["money"] - 2000 or a["credit"] != b["credit"] + 4 or a["network"] != b["network"] + 2:
			_fail("%s 经 %s 入行后再按带后缀 / 基港 id 直调，账 %s→%s（应只扣一次）" % [port, page, b, a])
		elif not _gs.has_flag("guild_%s" % port) or _gs.has_flag("guild_%s" % page):
			_fail("%s 入行旗标没记在基港 guild_%s 上" % [port, port])
		elif not _has_stamp(main, "本港已入行"):
			_fail("%s 入行后 %s 卡底没有 disabled「本港已入行」" % [port, page])
		else:
			_ok("%s：港卡进 %s 入行，带后缀 / 基港直调都不再扣，旗标 guild_%s" % [port, page, port])

	# ── 3. 赴试士人支（第一章） ──
	_gs.chapter = 1
	_clear_flag("exam_sat_ch1")
	_clear_flag("exam_sat")
	_gs.scholar_tendency = 5
	_gs.sea_tendency = 5
	main.load_scene("quanzhou_exam")
	# 科场港正文不写「今科未开 / 只能替人誊录」：底下就是「入场赴试」（lane w53-6；明州对照见 5c）
	var sit_body := str(main.body_text.text)
	if sit_body.contains("今科未开") or sit_body.contains("只能替人誊录"):
		_fail("泉州贡院有「%s」，正文却写「%s」" % [SIT_TEXT, sit_body])
	else:
		_ok("泉州贡院正文不说只能誊录：%s" % sit_body)
	var sit := _button_with_text(main, SIT_TEXT)
	if sit == null:
		_fail("泉州贡院没有「%s」" % SIT_TEXT)
	else:
		var b3 := _snap()
		sit.pressed.emit()
		var a3 := _snap()
		if a3["day"] - b3["day"] != 15:
			_fail("赴试推进 %d 日，应为 15" % (a3["day"] - b3["day"]))
		elif not _gs.has_flag("exam_sat_ch1"):
			_fail("赴试后未写 exam_sat_ch1")
		elif not _gs.has_flag("exam_sat"):
			_fail("学者不输海路却未写 exam_sat")
		elif a3["fame"] != b3["fame"] + 4:
			_fail("士人支名声 %d→%d，应加 4" % [b3["fame"], a3["fame"]])
		elif a3["scholar"] != b3["scholar"] + 2 or a3["sea"] != b3["sea"]:
			_fail("士人支倾向 学者 %d→%d 海路 %d→%d" % [b3["scholar"], a3["scholar"], b3["sea"], a3["sea"]])
		else:
			_ok("赴试士人支：15 日、写 exam_sat_ch1 与 exam_sat、名声 +4、学者 +2")

	# ── 5a. 第一章已赴：不再出按钮 ──
	main.load_scene("quanzhou_exam")
	if _button_with_text(main, SIT_TEXT) != null:
		_fail("第一章已赴过仍有「%s」" % SIT_TEXT)
	elif not _has_stamp(main, "本章已赴"):
		_fail("第一章已赴过卡底没有 disabled「本章已赴」")
	else:
		_ok("第一章已赴：贡院只显示本章已赴过")

	# ── 4. 赴试海路支（第二章，新章旗标） ──
	_gs.chapter = 2
	_clear_flag("exam_sat_ch2")
	_clear_flag("exam_sat")
	_gs.scholar_tendency = 3
	_gs.sea_tendency = 6
	main.load_scene("quanzhou_exam")
	var sit2 := _button_with_text(main, SIT_TEXT)
	if sit2 == null:
		_fail("第二章泉州贡院没有「%s」" % SIT_TEXT)
	else:
		var b4 := _snap()
		sit2.pressed.emit()
		var a4 := _snap()
		if a4["day"] - b4["day"] != 15:
			_fail("海路支推进 %d 日，应为 15" % (a4["day"] - b4["day"]))
		elif not _gs.has_flag("exam_sat_ch2"):
			_fail("海路支未写 exam_sat_ch2")
		elif _gs.has_flag("exam_sat"):
			_fail("海路支写了 exam_sat")
		elif a4["fame"] != b4["fame"] + 1:
			_fail("海路支名声 %d→%d，应加 1" % [b4["fame"], a4["fame"]])
		elif a4["sea"] != b4["sea"] + 1 or a4["scholar"] != b4["scholar"]:
			_fail("海路支倾向 学者 %d→%d 海路 %d→%d" % [b4["scholar"], a4["scholar"], b4["sea"], a4["sea"]])
		else:
			_ok("赴试海路支：15 日、写 exam_sat_ch2、不写 exam_sat、名声 +1、海路 +1")

	# ── 5b. 第二章已赴：无按钮，直调也不动日数/名声/旗标 ──
	main.load_scene("quanzhou_exam")
	if _button_with_text(main, SIT_TEXT) != null:
		_fail("第二章已赴过仍有「%s」" % SIT_TEXT)
	elif not _has_stamp(main, "本章已赴"):
		_fail("第二章已赴过卡底没有 disabled「本章已赴」")
	else:
		var b5 := _snap()
		main._on_exam_sit("quanzhou")
		var a5 := _snap()
		if a5 != b5:
			_fail("本章已赴再调赴试仍改账 %s→%s" % [b5, a5])
		elif _gs.has_flag("exam_sat"):
			_fail("本章已赴再调赴试写了 exam_sat")
		else:
			_ok("每章一次：本章已赴无按钮，直调不动日数/名声/倾向")

	# ── 5c. 非科场港：明州贡院只誊录，赴试卡给 disabled「本港无贡院科场」 ──
	main.load_scene("mingzhou_exam")
	if str(main.current_scene_id) != "mingzhou_exam":
		_fail("没能打开明州贡院，现为 %s" % str(main.current_scene_id))
	elif _button_with_text(main, SIT_TEXT) != null:
		_fail("明州贡院出现了「%s」" % SIT_TEXT)
	elif not _has_stamp(main, "本港无贡院科场"):
		_fail("明州贡院卡底没有 disabled「本港无贡院科场」")
	elif not str(main.body_text.text).contains("只能替人誊录"):
		_fail("明州贡院只誊录，正文却没写只能誊录：%s" % str(main.body_text.text))
	else:
		_ok("明州贡院：本港无贡院科场，无赴试按钮，正文写只能替人誊录")

	# ── 6. 1268 打平：exam_sat 定士人；无旗标则海商 ──
	_gs.chapter = 1
	_gs.hometown_tendency = 0
	_gs.scholar_tendency = 4
	_gs.sea_tendency = 4
	_clear_flag("chose_land_first")
	_clear_flag("renamed_wenlong")
	_clear_flag("name_unchanged")
	_gs.set_flag("exam_sat")
	_gs.identity = "undecided"
	_gs.player_name = "陈子龙"
	var r1: Dictionary = _gs.resolve_identity_1268()
	if not bool(r1.get("resolved", false)):
		_fail("1268 打平未结算")
	elif str(_gs.identity) != "scholar" or str(_gs.player_name) != "陈文龙" or not _gs.has_flag("renamed_wenlong"):
		_fail("1268 打平有 exam_sat 应士人，现 identity=%s name=%s" % [str(_gs.identity), str(_gs.player_name)])
	else:
		_ok("1268 打平 + exam_sat → 士人，改名陈文龙")

	_clear_flag("exam_sat")
	_clear_flag("renamed_wenlong")
	_gs.identity = "undecided"
	_gs.player_name = "陈子龙"
	_gs.resolve_identity_1268()
	if str(_gs.identity) != "merchant" or str(_gs.player_name) != "陈子龙":
		_fail("1268 打平无旗标应海商，现 identity=%s name=%s" % [str(_gs.identity), str(_gs.player_name)])
	else:
		_ok("1268 打平无 exam_sat / chose_land_first → 海商（对照）")

	# ── 7. 1268 三月二十赴试跨入四月：身份结算须读到本趟 exam_sat ──
	_gs.chapter = 3
	_clear_flag("exam_sat_ch3")
	_clear_flag("exam_sat")
	_clear_flag("chose_land_first")
	_clear_flag("renamed_wenlong")
	_clear_flag("name_unchanged")
	_gs.hometown_tendency = 0
	_gs.scholar_tendency = 4
	_gs.sea_tendency = 4
	_gs.identity = "undecided"
	_gs.player_name = "陈子龙"
	_cal.year = 1268
	_cal.month = 3
	_cal.day = 20
	main.load_scene("quanzhou_exam")
	var sit_late := _button_with_text(main, SIT_TEXT)
	if sit_late == null:
		_fail("1268 三月下旬泉州贡院没有「%s」" % SIT_TEXT)
	else:
		var b7 := _snap()
		sit_late.pressed.emit()
		var a7 := _snap()
		if a7["day"] - b7["day"] != 15:
			_fail("三月下旬赴试推进 %d 日，应为 15" % (a7["day"] - b7["day"]))
		elif int(_cal.year) != 1268 or int(_cal.month) != 4:
			_fail("三月二十 +15 日应到 1268 四月，现 %d年%d月%d日" % [int(_cal.year), int(_cal.month), int(_cal.day)])
		elif not _gs.has_flag("exam_sat") or not _gs.has_flag("exam_sat_ch3"):
			_fail("跨月赴试后未写 exam_sat / exam_sat_ch3")
		elif str(_gs.identity) != "scholar" or str(_gs.player_name) != "陈文龙":
			_fail("跨月赴试应先写 exam_sat 再结算为士人，现 identity=%s name=%s" % [str(_gs.identity), str(_gs.player_name)])
		elif not _gs.has_flag("renamed_wenlong"):
			_fail("跨月赴试士人结算未写 renamed_wenlong")
		else:
			_ok("1268 三月下旬赴试跨四月：exam_sat 先于身份结算 → 士人陈文龙")

	# ── 8. 1268 三月廿九誊录跨入四月：身份结算须读到本趟学者 +1（与 7 同型） ──
	_clear_flag("exam_sat")
	_clear_flag("chose_land_first")
	_clear_flag("renamed_wenlong")
	_clear_flag("name_unchanged")
	_gs.hometown_tendency = 0
	_gs.scholar_tendency = 4
	_gs.sea_tendency = 4
	_gs.identity = "undecided"
	_gs.player_name = "陈子龙"
	_cal.year = 1268
	_cal.month = 3
	_cal.day = 29
	main.load_scene("mingzhou_exam")
	var copy_late := _button_with_text(main, COPY_TEXT)
	if copy_late == null:
		_fail("1268 三月下旬明州贡院没有「%s」" % COPY_TEXT)
	else:
		var b8 := _snap()
		copy_late.pressed.emit()
		var a8 := _snap()
		if a8["day"] - b8["day"] != 3:
			_fail("三月下旬誊录推进 %d 日，应为 3" % (a8["day"] - b8["day"]))
		elif int(_cal.year) != 1268 or int(_cal.month) != 4:
			_fail("三月廿九 +3 日应到 1268 四月，现 %d年%d月%d日" % [int(_cal.year), int(_cal.month), int(_cal.day)])
		elif a8["scholar"] != b8["scholar"] + 1 or a8["fame"] != b8["fame"]:
			_fail("誊录应学者 +1、不记名声，现学者 %d→%d 名声 %d→%d" % [b8["scholar"], a8["scholar"], b8["fame"], a8["fame"]])
		elif str(_gs.identity) != "scholar" or str(_gs.player_name) != "陈文龙":
			_fail("跨月誊录应先记学者 +1 再结算为士人，现 identity=%s name=%s" % [str(_gs.identity), str(_gs.player_name)])
		else:
			_ok("1268 三月下旬誊录跨四月：学者 +1 先于身份结算 → 士人陈文龙")

	_finish()


func _finish() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			_ok(v[1])
		else:
			_fail(v[1])
	if _fails.is_empty():
		print("P7_GUILD_EXAM_SMOKE_OK")
		GateReport.finish("p7_guild_exam_smoke", 0, "P7_GUILD_EXAM_SMOKE_OK")
		quit(0)
	else:
		print("P7_GUILD_EXAM_SMOKE_FAIL %d" % _fails.size())
		GateReport.finish("p7_guild_exam_smoke", 1, "P7_GUILD_EXAM_SMOKE_FAIL %d" % _fails.size())
		quit(1)
