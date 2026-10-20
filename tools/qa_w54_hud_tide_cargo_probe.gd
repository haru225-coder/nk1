extends SceneTree
## lane w54-hud：海战顶匾（TideBar）右格「金钱　货舱」一行放得下——舱里货多时顶匾不长高，货名与件数不折开。
## 布景：真起 WorldMap 海战（快船一艘，敌炮冻住），钱 123456，舱里空 / 一样 / 六样货；1280×720 与 21:9（画布 1706×720）各跑一遍。
## 证（headless 也跑——只量排版）：
##   一、空舱写「货舱　空」、一样货照旧逐样写「货舱　青白瓷 ×10」（一行放得下就不收）；右格一行、顶匾一行高 72。
##   二、六样货：右格仍一行、顶匾仍 72；写「货舱　6 样 165 件」，悬停里逐样列全（六样「货名 ×件数」都在）。
##   三、钱八位（99999999）六样货：仍一行、顶匾仍 72。
##   四、战中货抛光（Fleet.clear_cargo）：右格回「货舱　空」、悬停清空。
##   每一态右格每一行都不以「×」起头（货名与件数不在中间折开）。
## 旧病（回退即红，一的一样货、二、三红）：右格最小宽 280、舱里每样货逐个写上，按宽自动折行——钱 123456 一样货就折成
## 两行「金钱　123456　　货舱　青白瓷 /×10」（顶匾 88），六样货折成三行（连下面「海战」一行共四行，顶匾 114）
## 「……青白瓷 /×10　生丝 ×17　胡椒 ×24　香药 /×31　苏木 ×38　漆器 ×45」：盖住的海面比镜头让位（worldmap_cam_plaque
## 按匾下沿 80 算）多出一截，「青白瓷」与「×10」被折在两行。
## 用法：godot --headless --path . -s res://tools/qa_w54_hud_tide_cargo_probe.gd（带窗口 DISPLAY=:2 同样可跑）
## 末行 QA_W54_HUD_TIDE_CARGO cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const VIEWS := [Vector2i(1280, 720), Vector2i(2560, 1080)]
const GOODS := ["qingbai_porcelain", "raw_silk", "pepper", "aromatic_medicine", "sappanwood", "lacquerware"]
## 顶匾右格只一行时的高（WorldMap.tscn：左格两行 56 + 上下边）
const TIDE_PLAIN_H := 72.0

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
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true),
		"money": gs.get("money")}
	for v: Vector2i in VIEWS:
		root.size = v
		await _frames(2)
		await _one_view("%dx%d" % [v.x, v.y], fleet, gm, gs)
	fleet.set("ships", saved["ships"])
	gm.set("pending_battle", saved["pb"])
	gs.set("money", saved["money"])
	_report()


func _one_view(tag: String, fleet: Node, gm: Node, gs: Node) -> void:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	gs.set("money", 123456)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w54_hud"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	await _frames(4)
	var tide := wm.get_node_or_null("CanvasLayer/HUD/TideBar") as Control
	var lbl := wm.get_node_or_null("CanvasLayer/HUD/TideBar/Margin/Row/VBox/FleetStatus") as Label
	_expect(tide != null and lbl != null, "%s 顶匾与右格都在" % tag)
	if tide == null or lbl == null:
		await _close(wm)
		return
	# 一、空舱 / 一样货
	_state(tide, lbl, "%s 一 空舱" % tag, "货舱　空", "")
	fleet.call("add_cargo", GOODS[0], 10, 10.0, 0)
	await _frames(4)
	_state(tide, lbl, "%s 一 一样货" % tag, "货舱　青白瓷 ×10", "")
	# 二、六样货
	for i in range(1, GOODS.size()):
		fleet.call("add_cargo", GOODS[i], 10 + i * 7, 10.0, 0)
	await _frames(4)
	_state(tide, lbl, "%s 二 六样货" % tag, "货舱　6 样 165 件", "货舱　青白瓷 ×10　生丝 ×17　胡椒 ×24　香药 ×31　苏木 ×38　漆器 ×45")
	# 三、钱八位
	gs.set("money", 99999999)
	await _frames(4)
	_state(tide, lbl, "%s 三 钱八位六样货" % tag, "货舱　6 样 165 件", "货舱　青白瓷 ×10")
	# 四、货抛光
	fleet.call("clear_cargo")
	await _frames(4)
	_state(tide, lbl, "%s 四 货抛光" % tag, "货舱　空", "")
	await _close(wm)


## 右格一行、顶匾一行高、写着 want；tip 非空时悬停里要有它（空串 = 悬停应清空）；没有一行以「×」起头
## （自动折行的各行首字：照右格的字体、字号、宽与 WORD_SMART 的断行旗号另排一遍段落来看）
func _state(tide: Control, lbl: Label, tag: String, want: String, tip: String) -> void:
	var para := TextParagraph.new()
	para.add_string(lbl.text, lbl.get_theme_font("font"), lbl.get_theme_font_size("font_size"))
	para.width = lbl.size.x
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var starts_x := false
	for li in para.get_line_count():
		if lbl.text.substr(para.get_line_range(li).x, 1) == "×":
			starts_x = true
	_expect(lbl.get_line_count() == 1 and tide.size.y <= TIDE_PLAIN_H + 0.5,
		"%s：右格一行（%d 行）、顶匾高 %.0f ≤ %.0f" % [tag, lbl.get_line_count(), tide.size.y, TIDE_PLAIN_H])
	_expect(lbl.text.ends_with(want) and not starts_x, "%s：右格写「…%s」、不在货名与件数中间折开（「%s」）" % [tag, want, lbl.text])
	if tip == "":
		_expect(lbl.tooltip_text == "", "%s：悬停清空（「%s」）" % [tag, lbl.tooltip_text])
	else:
		_expect(lbl.tooltip_text.begins_with(tip), "%s：悬停逐样列全（「%s」）" % [tag, lbl.tooltip_text])


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("QA_W54_HUD_TIDE_CARGO cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
