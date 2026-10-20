extends SceneTree
## lane w54-hud：海战右上「敌情」卡跟着顶匾（TideBar）的高矮挪，不压进顶匾。
## 顶匾右格「金钱　货舱」是按 280 宽自动折行的 Label：钱数五六位、舱里两三样货就折成两三行，顶匾从 72 长到 88–114。
## 布景：真起 WorldMap 海战（快船两艘，敌炮冻住），钱 123456、舱里六样货开打；1280×720 与 21:9（画布 1706×720）各跑一遍。
## 证（headless 也跑——只量排版）：
##   一、开打时顶匾确实长高了（布景成立：右格折成三行以上、顶匾高过 72）；敌情卡上沿在顶匾下沿之下，
##       号令卡同判（对照：号令卡本就跟着顶匾挪）。
##   二、战中货抛光（Fleet.clear_cargo，顶匾缩回一行）：敌情卡跟着上来，上沿 = 顶匾下沿 + 10，不留一截空。
##   三、战中又进货（六样再装上，顶匾再长高）：敌情卡再跟着下去，仍不压匾。
## 旧病（回退即红，一、三红）：CombatStatusHud._layout_intel 只在开场与画布改尺寸时排一次，不挂顶匾的 item_rect_changed
## （号令面板 CombatOrdersPanel._layout 挂了）——开场那一刻顶匾还是 72 高，敌情卡钉在 y 90；顶匾随后长到 114，
## 敌情卡上沿压进匾里 32 px，盖住右格末行「海战　潮向」。
## 用法：godot --headless --path . -s res://tools/qa_w54_hud_intel_tide_probe.gd（带窗口 DISPLAY=:2 同样可跑）
## 末行 QA_W54_HUD_INTEL_TIDE cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const VIEWS := [Vector2i(1280, 720), Vector2i(2560, 1080)]
const GOODS := ["qingbai_porcelain", "raw_silk", "pepper", "aromatic_medicine", "sappanwood", "lacquerware"]
## 顶匾只有一行右格时的高（WorldMap.tscn：左栏两行 56 + 边 16）
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
	_load(fleet)
	gs.set("money", 123456)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海", "source": {"scene": "qa_w54_hud"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	await _frames(8)
	var tide := wm.get_node_or_null("CanvasLayer/HUD/TideBar") as Control
	var fleet_lbl := wm.get_node_or_null("CanvasLayer/HUD/TideBar/Margin/Row/VBox/FleetStatus") as Label
	var hud: Node = null
	var orders: Node = null
	for c in wm.get_children():
		if c.is_in_group(Hud.GROUP):
			hud = c
		elif c.is_in_group("nk1_combat_orders"):
			orders = c
	var card: Control = hud.get("_intel") if hud != null else null
	var ocard: Control = orders.get("_card") if orders != null else null
	_expect(tide != null and fleet_lbl != null and card != null and ocard != null, "%s 顶匾、右格、敌情卡、号令卡都在" % tag)
	if tide == null or fleet_lbl == null or card == null or ocard == null:
		await _close(wm)
		return
	# 一、开打
	_expect(fleet_lbl.get_line_count() >= 3 and tide.size.y > TIDE_PLAIN_H + 20.0,
		"%s 一 布景成立：右格折成 %d 行、顶匾高 %.0f（一行时 %.0f）" % [tag, fleet_lbl.get_line_count(), tide.size.y, TIDE_PLAIN_H])
	_below(card, tide, "%s 一 开打 敌情卡" % tag)
	_below(ocard, tide, "%s 一 开打 号令卡（对照）" % tag)
	# 二、货抛光
	fleet.call("clear_cargo")
	await _frames(6)
	_expect(tide.size.y <= TIDE_PLAIN_H + 0.5, "%s 二 货抛光后顶匾缩回一行高（%.0f）" % [tag, tide.size.y])
	var gap := card.get_global_rect().position.y - tide.get_global_rect().end.y
	_expect(absf(gap - 10.0) <= 0.5, "%s 二 敌情卡跟着上来：上沿离顶匾下沿 %.0f（应 10）" % [tag, gap])
	# 三、又进货
	_load(fleet)
	await _frames(6)
	_expect(tide.size.y > TIDE_PLAIN_H + 20.0, "%s 三 又进货顶匾再长高（%.0f）" % [tag, tide.size.y])
	_below(card, tide, "%s 三 又进货 敌情卡" % tag)
	await _close(wm)


func _load(fleet: Node) -> void:
	for i in GOODS.size():
		fleet.call("add_cargo", GOODS[i], 10 + i * 7, 10.0, 0)


## c 的上沿在顶匾下沿之下（不压匾）
func _below(c: Control, tide: Control, tag: String) -> void:
	var top := c.get_global_rect().position.y
	var tide_end := tide.get_global_rect().end.y
	_expect(top >= tide_end, "%s 上沿 %.0f 在顶匾下沿 %.0f 之下" % [tag, top, tide_end])


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
	print("QA_W54_HUD_INTEL_TIDE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
