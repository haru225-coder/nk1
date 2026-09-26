extends SceneTree
## 无界面驱动 P7 行会入行 / 贡院赴试：扣费与门槛、赴试两支、每章一次、1268 打平读 exam_sat。
## 跑法：godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
## -s 入口在编译期看不到自动加载名，单例一律在 _initialize 之后从根节点取。

const JOIN_TEXT := "交会费入行"
const SIT_TEXT := "入场赴试"

var _fails: Array = []
var _gs
var _gm
var _cal


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_gm = root.get_node("GameManager")
	_cal = root.get_node("Calendar")
	var main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL ", msg)


func _ok(msg: String) -> void:
	print("OK   ", msg)


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

	# ── 1. 泉州入行成功 ──
	_gs.money = 5000
	_gs.merchant_credit = 8
	_gs.network = 1
	main.load_scene("quanzhou_guild")
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

	# ── 3. 赴试士人支（第一章） ──
	_gs.chapter = 1
	_clear_flag("exam_sat_ch1")
	_clear_flag("exam_sat")
	_gs.scholar_tendency = 5
	_gs.sea_tendency = 5
	main.load_scene("quanzhou_exam")
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
	else:
		_ok("明州贡院：本港无贡院科场，无赴试按钮")

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

	if _fails.is_empty():
		print("P7_GUILD_EXAM_SMOKE_OK")
		quit(0)
	else:
		print("P7_GUILD_EXAM_SMOKE_FAIL %d" % _fails.size())
		quit(1)
