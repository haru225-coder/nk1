extends SceneTree
## 酒馆募人与水手雇请工席巡检（Lane AB）：截 01..06 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/crew/。
## 摆场：泉州酒馆募人（有候选）→ 雇入一人（在船・辞退）→ 雇满本港职事（空态）
##       → 泉州船屋坞位添人 chip → 减员后补齐 chip → 船籍簿职事行。
## 断言只查文案与钮字；入伙钱、月俸、码头每人 20 的算式照旧，这里顺带核一遍数没动。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_crew_hire_probe.gd   # 截图门禁（须出 6 张）
##       godot --headless --path . -s res://tools/qa_crew_hire_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_crew_hire_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("crew")
const TAG := "QA_CREW_HIRE"
const EXPECTED_SHOTS := 6
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
## 泉州 ch1 可雇之人（data/crew.json）：火长、总管、杂事、通事、医人各一
const QZ_ALL := ["wu_zhen", "wang_zhiku", "huang_zhangfang", "pu_alie", "monk_puji"]

var _main: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_CREW_HIRE_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var fleet: Node = root.get_node("/root/Fleet")
	var crew: Node = root.get_node("/root/Crew")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	ShotGate.frame_pressure(self)
	root.add_child(_main)
	await _settle(10)

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	gs.last_port = "quanzhou"
	gs.money = 8000

	# 费用算式没动：入伙钱 = 月俸 × 2
	_expect(int(crew.get("SIGNING_MULTIPLIER")) == 2, "入伙倍数仍为 2")
	_expect(int(crew.call("signing_fee", "wu_zhen")) == 120, "吴振入伙 120")

	# 01 泉州酒馆：有候选，募人题签在前
	_main.load_scene("quanzhou_tavern")
	await _settle(10)
	var body := str(_main.body_text.text)
	_expect(body.contains("闻讯、募人"), "酒馆正文含「闻讯、募人」")
	_expect(body.contains("月俸按月；欠饷三月，则人去。"), "酒馆正文留月俸欠饷")
	_expect(_has_text("募人"), "募人题签")
	_expect(_has_text("本港可雇 5 人　一职一人"), "有候选旁注「本港可雇 5 人」")
	_expect(_has_text("入伙钱当场付清，月俸按月扣。"), "入伙月俸旁注")
	_expect(_has_text("入伙 120　月俸 60"), "钱数格式「入伙 N　月俸 N」")
	_expect(_find_button("雇入") != null, "钮字「雇入」")
	await _shot("01_quanzhou_tavern_hiring")

	# 02 雇入吴振：在船卡 + 辞退，钱数照算式扣
	var before: int = int(gs.money)
	var res: Dictionary = crew.call("hire", "wu_zhen")
	_expect(bool(res.get("ok", false)), "雇入吴振")
	_expect(int(gs.money) == before - 120, "入伙钱扣 120（得 %d）" % (before - int(gs.money)))
	_expect(str(res.get("msg", "")).contains("入伙。付入伙钱 120，月俸 60。"), "雇入日志「%s」" % res.get("msg", ""))
	_main.log_msg(str(res.get("msg", "")))
	_main.load_scene("quanzhou_tavern")
	await _settle(10)
	_expect(_has_text("在船"), "在船卡")
	var off := _find_button("辞退")
	_expect(off != null, "钮字「辞退」")
	if off != null:
		_expect(str(off.tooltip_text) == "辞退即上岸。入伙钱不退。", "辞退 tooltip")
	_expect(_has_text("本港可雇 4 人　一职一人"), "雇后旁注「本港可雇 4 人」")
	var dup: Dictionary = crew.call("hire", "wu_zhen")
	_expect(str(dup.get("msg", "")).contains("一职只容一人"), "重雇日志「%s」" % dup.get("msg", ""))
	await _shot("02_hired_aboard_dismiss")

	# 03 雇满本港各职 → 空态题签
	for cid in QZ_ALL:
		if cid != "wu_zhen":
			crew.call("hire", cid)
	_main.load_scene("quanzhou_tavern")
	await _settle(10)
	_expect(_has_text("本港眼下无人可雇"), "空态旁注「本港眼下无人可雇」")
	_expect(_has_text("已雇之职不再列名。"), "空态注「已雇之职不再列名」")
	_expect(not _has_text("此处无人可用"), "旧空态文案已去")
	var gone: Dictionary = crew.call("dismiss", "yiren")
	_expect(str(gone.get("msg", "")).contains("辞退，背铺盖上岸。"), "辞退日志「%s」" % gone.get("msg", ""))
	_main.log_msg(str(gone.get("msg", "")))
	crew.call("hire", "monk_puji")
	_main.load_scene("quanzhou_tavern")
	await _settle(10)
	await _shot("03_tavern_empty")

	# 04 船屋坞位：添人 chip（先减到不满员）
	if fleet.ships.size() > 0:
		var cmax: int = int(fleet.call("ship_crew_max", 0))
		fleet.ships[0]["crew"] = maxi(1, cmax - 6)
	_main.load_scene("quanzhou_shipyard")
	await _settle(10)
	var add := _find_button_containing("添 ")
	_expect(add != null, "坞位添人 chip")
	if add != null:
		var room: int = int(fleet.call("ship_crew_room", 0))
		var n: int = mini(10, room)
		_expect(str(add.text).ends_with("添 %d 人　%d" % [n, n * 20]), "添人钱数 = 人数 × 20「%s」" % add.text)
		_expect(str(add.tooltip_text).begins_with("码头短雇的水手，只上坞上这一艘。"), "添人 tooltip「%s」" % add.tooltip_text)
	await _shot("04_shipyard_berth_add_crew")

	# 05 减到最低人手以下：补齐 chip
	if fleet.ships.size() > 0:
		var cmin: int = int(fleet.call("ship_crew_min", 0))
		fleet.ships[0]["crew"] = maxi(0, cmin - 5)
	var need: int = int(fleet.call("crew_to_min_needed"))
	_main.load_scene("quanzhou_shipyard")
	await _settle(10)
	var top := _find_button_containing("补齐 ")
	_expect(top != null, "补齐 chip")
	if top != null:
		_expect(str(top.text) == "补齐 %d 人　%d" % [need, need * 20], "补齐钱数 = 缺额 × 20「%s」" % top.text)
		_expect(str(top.tooltip_text) == "各船缺到最低人手的，码头一并雇齐。", "补齐 tooltip")
		top.pressed.emit()
		await _settle(10)
		_expect(int(fleet.call("crew_to_min_needed")) == 0, "补齐后不缺人")
	await _shot("05_shipyard_top_up")

	# 06 船籍簿职事行 + 欠饷日志
	gs.money = 0
	var owe := str(crew.call("pay_wages"))
	_expect(owe.begins_with("【欠饷】本月工食 ") and owe.ends_with("未发。船上人心浮动。"), "欠饷日志「%s」" % owe)
	_main.log_msg(owe)
	gs.money = 8000
	_main.load_scene("quanzhou")
	await _settle(10)
	if _main.has_method("_toggle_ledger"):
		_main.call("_toggle_ledger")
		await _settle(8)
	await _shot("06_ledger_crew_roster")

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("QA_CREW_HIRE_CHECK ok ", what)
	else:
		_fails.append(what)
		print("QA_CREW_HIRE_CHECK fail ", what)


func _has_text(t: String) -> bool:
	return _find(_main, func(n: Node) -> bool: return n is Label and str((n as Label).text) == t) != null \
		or _find(_main, func(n: Node) -> bool: return n is Label and str((n as Label).text).contains(t)) != null


func _find_button(t: String) -> Button:
	return _find(_main, func(n: Node) -> bool: return n is Button and (n as Button).is_visible_in_tree() and str((n as Button).text) == t) as Button


func _find_button_containing(t: String) -> Button:
	return _find(_main, func(n: Node) -> bool: return n is Button and (n as Button).is_visible_in_tree() and str((n as Button).text).contains(t)) as Button


func _find(n: Node, pred: Callable) -> Node:
	if n == null:
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)
