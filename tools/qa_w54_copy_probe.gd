extends SceneTree
## lane w54-copy 文案一致性探针（headless，不截图；一段钉一条、回退即红）。
##   一、门牌悬停提示里的地名与门牌同字：守城那天（1276-11-03）进兴化，岸带上「囊山」门的悬停提示写囊山
##       （曾误作「南山下设伏。」——门牌、战报题「囊山・第N阵」、元军行事「前锋到囊山」都写囊山）；
##       岸带上门牌是专名的门（城中通名的九门与守城借用的衙门 / 市场除外），提示都原字写出门牌（「・」不计）。
##   二、九门门牌与进门页题同名：泉州（scenes.json 港景的门）、福州（通用九门）岸带上开着的、关着的门逐扇看，
##       门牌 = 进门后的页题「<港名>・<门牌>」（住处门的门牌曾写「住宅」，进门却是「泉州・住处」）。
##   三、上屏的间隔号用全角「・」：海图港签副题（MapView._port_sub，1255–1285 逐年按 sub_by_year 换）与章节卡题辞出处
##       （ChapterCard._read_data，四章）不写半角「·」——文楷里「·」只有 0.35 字宽，曾在「興化軍·莆田」「《论语·公冶长》」
##       里挤成一粒，同一张海图的险地名、同一张章节卡的年款用的却是「・」。
## 静态一侧见 tools/check_w53_copy.py 钉 R / S 与钉 O（扩到数据）；本探针看的是岸带上真建出来的门、真进的页、真取的字。
## 用法：godot --headless --path . -s res://tools/qa_w54_copy_probe.gd（经门锁跑）
## 判词：逐条「  ✓ / ✗ 判词」，末行 QA_W54_COPY_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W54_COPY_PROBE"
const VIEW := Vector2i(1280, 720)
## 守城借用的城中通名门：与九门一样，提示不必复述门牌（同 check_w53_copy 钉 R 的 TIP_COMMON_TITLES）
const COMMON_TITLES := ["衙门", "市场"]

var _fails: Array = []
var _main: Node
var gs: Node
var cal: Node
var fleet: Node
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时不会走到 _report——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	print("%s_BEGIN" % TAG)
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	cal = root.get_node("/root/Calendar")
	fleet = root.get_node("/root/Fleet")
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	_main = packed.instantiate() if packed != null else null
	if _main == null or _main.get_script() == null:
		_check(false, "Main.tscn 挂得出（根脚本无 Parse Error）")
		_report()
		return
	root.size = VIEW
	root.add_child(_main)
	for i in 6:
		await process_frame

	print("== 一、门牌悬停提示里的地名与门牌同字（守城那天的兴化岸带）")
	await _sec_door_tips()
	print("== 二、九门门牌与进门页题同名（泉州走 scenes.json 港景的门，福州走通用九门）")
	await _sec_door_pages()
	print("== 三、上屏的间隔号用全角「・」（海图港签副题、章节卡题辞出处）")
	_sec_interpunct()
	_report()


func _sec_door_tips() -> void:
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	await process_frame
	var common: Array = COMMON_TITLES.duplicate()
	for fac in _main.get("GENERIC_FACILITIES"):
		common.append(str((fac as Dictionary).get("title", "")))
	var doors := _doors()
	var titles := []
	var nangshan := ""
	for d in doors:
		var title := str(d[0])
		var tip := str(d[1])
		titles.append(title)
		if title == "囊山":
			nangshan = tip
		if title in common:
			continue
		_check(tip.replace("・", "").find(title.replace("・", "")) >= 0,
			"「%s」门的悬停提示写出门牌（「%s」）" % [title, tip])
	_check(nangshan != "", "守城那天兴化岸带上有「囊山」门（岸带上的门 %s）" % [titles])
	_check(nangshan.find("囊山") >= 0 and nangshan.find("南山") < 0,
		"「囊山」门的悬停提示写囊山、不写南山（「%s」）" % nangshan)


## 二：港里每扇门（今日开着的三扇与关着的几扇），门牌 = 进门后的页题「<港名>・<门牌>」
func _sec_door_pages() -> void:
	var gm: Node = root.get_node("/root/GameManager")
	gs.from_dict({})
	cal.from_dict({"year": 1262, "month": 5, "day": 10})
	gs.money = 5000
	# 走过序章的档：节拍幕都记过名，空档首抵泉州会演节拍幕、岸带不在屏上（同 qa_port_doors_probe）
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	for port in ["quanzhou", "fuzhou"]:
		gs.last_port = port
		_main.load_scene(port)
		await process_frame
		var port_name := str(gm.get_port_name(port))
		var shown := []
		for d in _doors():
			shown.append(str(d[0]))
		var facs: Array = _main.get("_shore_facilities")
		_check(facs.size() == 9 and shown.size() == 9, "%s岸带上九扇门都在（开着的与关着的共 %d：%s）" % [port_name, shown.size(), shown])
		for fac in facs:
			var fid := str((fac as Dictionary).get("id", ""))
			var title := str((fac as Dictionary).get("title", ""))
			_main.load_scene("%s_%s" % [port, fid.trim_prefix("city_")])
			await process_frame
			var page := str(_main.scene_title.text)
			_check(title in shown and page == "%s・%s" % [port_name, title],
				"%s「%s」门（%s）进门页题「%s」" % [port_name, title, fid, page])
		_main.load_scene(port)
		await process_frame


## 三：海图港签副题与章节卡题辞出处里没有半角「·」（U+00B7）
func _sec_interpunct() -> void:
	var half := "·"
	var map: Node = (load("res://scripts/chart/MapView.gd") as GDScript).new()
	var subs := {}
	for p in root.get_node("/root/GameManager").ports_data.get("ports", []):
		var chart: Dictionary = (p as Dictionary).get("chart", {})
		for y in range(1255, 1286):
			map.set("cal_year", y)
			subs[str(map.call("_port_sub", chart))] = true
	map.free()
	var bad := []
	for s in subs:
		if str(s).find(half) >= 0:
			bad.append(s)
	_check(subs.size() >= 14 and bad.is_empty(),
		"海图港签副题 1255–1285 逐年 %d 种，无半角「·」（有的：%s）" % [subs.size(), bad])
	_check(subs.has("興化軍・莆田") and subs.has("刺桐・泉州路（元）"), "港签副题的间隔号是全角「・」（興化軍・莆田、刺桐・泉州路（元））")
	for n in range(1, 5):
		var card: Node = (load("res://scripts/cutscene/ChapterCard.gd") as GDScript).new()
		card.set("chapter", n)
		card.call("_read_data")
		var src := str(card.get("_src"))
		var year := str(card.get("_year"))
		card.free()
		_check(src != "" and src.find(half) < 0 and year.find(half) < 0,
			"第%d章章节卡 出处「%s」、年款「%s」无半角「·」" % [n, src, year])


## 岸带上的门：[门牌, 悬停提示]，今日开着的（ShoreDoors）在前、关着的（ShoreShut）在后，各按树序
func _doors() -> Array:
	var out := []
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	for row_name in ["ShoreDoors", "ShoreShut"]:
		var row: Node = band.get_node_or_null(row_name) if band != null else null
		if row == null:
			continue
		for d in row.get_children():
			if (d as Node).is_queued_for_deletion():
				continue
			if d is Button:  # 关着的门（_make_shore_shut）：钮字即门牌
				out.append([(d as Button).text, (d as Button).tooltip_text])
				continue
			var cols := (d as Node).find_children("*", "VBoxContainer", true, false)
			var head: Node = (cols[0] as Node).get_child(0) if not cols.is_empty() and (cols[0] as Node).get_child_count() > 0 else null
			var btns := (d as Node).find_children("*", "Button", true, false)
			var tip: String = (btns[0] as Button).tooltip_text if not btns.is_empty() else ""
			out.append([(head as Label).text if head is Label else "", tip])
	return out


## 守城那天：士人线改名文龙、在兴化、一条小艍（同 qa_w53_p5_siege_probe 的布景）
func _stage_siege(y: int, m: int, d: int) -> void:
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	gs.money = 20000
	gs.fame = 30
	gs.last_port = "xinghua"
	cal.from_dict({"year": y, "month": m, "day": d})
	root.get_node("/root/Crew").from_dict({})
	fleet.ships = []
	fleet.add_ship("sampan", "无名小艍")
	fleet.water = 60
	fleet.food = 60
	fleet.morale = 70


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)
