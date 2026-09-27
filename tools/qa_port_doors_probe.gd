extends SceneTree
## 港口三扇岸门巡检：泉州 / 福州 / 兴化截 ShoreDoors 到 /workspace/nk1-qa-shots/port-doors/。
## 断言：三扇门 title/subtitle 论文纪实；热区 Button 挂 tooltip；关着的门有「今日未开」提示。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_port_doors_probe.gd

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/port-doors"

## 与 Main.GENERIC_FACILITIES / DOOR_TIP 对齐的契约（副题短标签）
const EXPECT_SUB := {
	"city_shipyard": "修舱・上水・雇手",
	"city_guild": "议价・立籍",
	"city_tavern": "闻讯・募人",
	"city_market": "过秤・买卖",
	"city_inn": "歇息・候风",
	"city_exam": "誊录・观礼",
	"city_residence": "账本・歇息",
	"city_temple": "勘见・拓碑",
	"city_yamen": "验引・抽解",
}

var _main: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_PORT_DOORS_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.money = 5000

	var ports := [
		["quanzhou", "01_quanzhou_doors"],
		["fuzhou", "02_fuzhou_doors"],
		["xinghua", "03_xinghua_doors"],
	]
	for row in ports:
		var pid: String = row[0]
		var stem: String = row[1]
		gs.last_port = pid
		gs.shore_salt = 0
		_main.load_scene(pid)
		await _settle(12)
		_expect_doors(pid)
		await _shot(stem)

	# 再候一日：门轮换后仍有 tooltip
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	await _settle(8)
	if _main.has_method("_on_shore_wait"):
		_main.call("_on_shore_wait")
		await _settle(10)
	_expect_doors("quanzhou")
	await _shot("04_quanzhou_wait_reshuffle")

	# 关着的门：点按应出纪实日志（抽一扇 ShoreShut）
	var shut := _find_named(_main, "ShoreShut")
	if shut != null and shut.get_child_count() > 0:
		var b: Node = shut.get_child(0)
		if b is BaseButton:
			_expect(str((b as Control).tooltip_text).contains("今日未开"), "关门 tooltip 含「今日未开」")
			(b as BaseButton).pressed.emit()
			await _settle(4)
	await _shot("05_quanzhou_shut_tooltip")

	if _fails.is_empty():
		print("QA_PORT_DOORS_OK shots=%d" % _saved.size())
		quit(0)
	else:
		for f in _fails:
			print("QA_PORT_DOORS_FAIL ", f)
		quit(1)


func _expect_doors(port_id: String) -> void:
	var band := _find_named(_main, "ShoreBand")
	_expect(band != null, "%s ShoreBand" % port_id)
	var doors := _find_named(_main, "ShoreDoors")
	_expect(doors != null, "%s ShoreDoors" % port_id)
	if doors == null:
		return
	_expect(doors.get_child_count() == 3, "%s 开着三扇（得 %d）" % [port_id, doors.get_child_count()])
	var tips := 0
	for ch in doors.get_children():
		var btn := _find_button(ch)
		_expect(btn != null, "%s 岸门缺热区 Button" % port_id)
		if btn == null:
			continue
		var tip := str((btn as Control).tooltip_text)
		_expect(tip.strip_edges() != "", "%s 岸门 tooltip 空" % port_id)
		_expect(not tip.contains("点击"), "%s tooltip 含 UI 腔「点击」" % port_id)
		if tip != "":
			tips += 1
		# 副题 Label 对照契约（若该门 id 在 EXPECT_SUB）
		var sub_lbl := _find_subtitle_label(ch)
		if sub_lbl != null:
			var sub := str(sub_lbl.text)
			# 允许任一门的副题落在 EXPECT_SUB 值集合
			if sub != "" and sub not in EXPECT_SUB.values():
				_fails.append("%s 副题非纪实短标「%s」" % [port_id, sub])
	_expect(tips == 3, "%s 三扇均有 tooltip（%d）" % [port_id, tips])


func _find_named(n: Node, nm: String) -> Node:
	if n == null:
		return null
	if n.name == nm:
		return n
	for c in n.get_children():
		var hit := _find_named(c, nm)
		if hit != null:
			return hit
	return null


func _find_button(n: Node) -> BaseButton:
	if n is BaseButton:
		return n
	for c in n.get_children():
		var hit := _find_button(c)
		if hit != null:
			return hit
	return null


func _find_subtitle_label(card: Node) -> Label:
	# 岸门卡：VBox 里第二枚 Label 是 subtitle（第一枚 title）
	var labels: Array = []
	_collect_labels(card, labels)
	if labels.size() >= 2:
		return labels[1]
	return null


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label and not str(n.name).begins_with("Door"):
		# 跳过淡墨水印 DoorMark 内 Label
		var p := n.get_parent()
		if p == null or str(p.name) != "DoorMark":
			out.append(n)
	for c in n.get_children():
		_collect_labels(c, out)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(stem: String) -> void:
	await _settle(2)
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		_fails.append("空帧 %s" % stem)
		return
	var path := "%s/%s.png" % [OUT_DIR, stem]
	var err := img.save_png(path)
	if err != OK:
		_fails.append("写失败 %s (%s)" % [stem, str(err)])
		return
	_saved.append(path)
	print("QA_PORT_DOORS_SHOT ", path)
