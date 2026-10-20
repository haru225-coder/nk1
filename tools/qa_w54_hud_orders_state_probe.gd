extends SceneTree
## lane w54-hud：海战号令面板每道签右边那一栏状态字整句放得下（那一栏 clip_text，多出的字直接裁掉）。
## 状态栏宽 = PANEL_W 288 − 两边距 24 − 签宽 132 − 间距 10 = 122 px，16 号文楷一行放七个半字。
## 证（1280×720，真起一场 WorldMap 海战、按真面板量；headless 也跑——只量排版，不截图）：
##   一、「5 降幡劝降」那一栏把会出现的写法逐个摆一遍：劝降三样（钩住・帆残・敌乱）缺一 / 缺二 / 缺三共七种、
##       三样齐、开关 parley_on_ship 关时距内可喊、敌已降、相距过远、无敌可喊、冷却中——每种写法字宽 ≤ 栏的实宽；
##       三样缺几样就写几样（钩 / 帆 / 乱各一字，缺的都在、不缺的不写）。
##   二、其余六栏的各档写法（抢风 / 救火 / 砍钩 / 张湿毡的已令未令、装填侧重各档名、备接舷的聚队 N 秒 / 已聚 / 散队中）同判。
## 旧病（回退即红）：劝降那一栏照搬 parley_road 的整句「未钩住、帆索未残、阵脚未乱」（约 208 px），三样齐时写
## 「可喊 约三成（钩住・帆残・敌乱）」（约 250 px）；1280×720 实截只露出「未钩住、帆索未」和半个「残」。
## 用法：godot --headless --path . -s res://tools/qa_w54_hud_orders_state_probe.gd（带窗口 DISPLAY=:2 同样可跑）
## 末行 QA_W54_HUD_ORDERS_STATE cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Orders := preload("res://scripts/ui/CombatOrdersPanel.gd")
## 三样各自的短写（与面板 PARLEY_SHORT 同值；探针自带一份，回退修法时面板里没有这个名也照样跑到断言）
const SHORT := {"grappled": "钩", "sail_broken": "帆", "shaken": "乱"}

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
	root.size = Vector2i(1280, 720)
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}
	var wm := await _battle(fleet, gm)
	var panel: Node = _panel_of(wm)
	_expect(panel != null, "号令面板在场")
	if panel != null:
		await _sec_parley(panel)
		await _sec_others(panel)
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	fleet.set("ships", saved["ships"])
	gm.set("pending_battle", saved["pb"])
	_report()


## 一、劝降那一栏：外接 parley_source 把各种上下文逐个喂给面板，真刷一遍签面再量
func _sec_parley(panel: Node) -> void:
	var lbl := _state_label(panel, "parley")
	_expect(lbl != null, "劝降签有状态栏")
	if lbl == null:
		return
	panel.set("parley_cd", 0.0)
	for g in [false, true]:
		for s in [false, true]:
			for k in [false, true]:
				var road: Dictionary = Orders.parley_road({"grappled": g, "hull_frac": 0.4 if s else 0.95,
					"enemy_state": "shaken" if k else "steady"})
				var ctx := {"ok": bool(road["lit"]), "why": str(road["road"]), "road": road, "target": null, "dist": 120.0,
					"enemy_morale": 40.0, "hull_frac": 0.4 if s else 0.95, "ratio": 1.2, "grappled": g,
					"enemy_state": "shaken" if k else "steady"}
				var text := await _show(panel, lbl, ctx)
				var tag := "三样齐" if bool(road["lit"]) else "缺「%s」" % str(road["road"])
				_fits(lbl, text, "劝降 " + tag)
				if not bool(road["lit"]):
					var have: Dictionary = road["have"]
					var lost := PackedStringArray()
					var extra := PackedStringArray()
					for key in SHORT:
						if not bool(have[key]) and not text.contains(SHORT[key]):
							lost.append(SHORT[key])
						if bool(have[key]) and text.contains(SHORT[key]):
							extra.append(SHORT[key])
					_expect(lost.is_empty() and extra.is_empty(),
						"劝降 %s：缺的几样都写上、不缺的不写（「%s」；漏 %s、多 %s）" % [tag, text, ",".join(lost), ",".join(extra)])
				else:
					_expect(text.begins_with("可喊"), "劝降三样齐写「可喊 …」（「%s」）" % text)
	for c in [
		["开关关时距内可喊", {"ok": true, "enemy_morale": 60.0, "hull_frac": 1.0, "ratio": 1.0, "grappled": false, "enemy_state": "steady"}],
		["敌已降", {"ok": true, "enemy_state": "struck"}],
		["相距过远", {"ok": false, "why": "相距过远", "dist": 900.0}],
		["无敌可喊", {"ok": false, "why": "无敌可喊"}],
	]:
		var t2 := await _show(panel, lbl, c[1])
		_fits(lbl, t2, "劝降 " + str(c[0]))
	panel.set("parley_cd", float(Orders.PARLEY_COOLDOWN))
	var t3 := await _show(panel, lbl, {"ok": true})
	_fits(lbl, t3, "劝降 冷却中")
	panel.set("parley_cd", 0.0)
	panel.set("parley_source", Callable())


## 二、其余六栏：各档开 / 关、装填各档、接舷聚队三态；每档只量它动到的那几栏
func _sec_others(panel: Node) -> void:
	var loads: Array = panel.call("loads")
	var states: Array = []
	for on in [false, true]:
		states.append([["windward", "damage", "cut", "wet"], {"windward": on, "damage_control": on, "cut_hooks": on, "wet_felt": on}])
	for mode in loads:
		states.append([["load"], {"load_mode": mode}])
	for b in [[true, 0.0], [true, 0.5], [true, 1.0], [false, 0.5], [false, 0.0]]:
		states.append([["board"], {"board_ready": b[0], "muster": b[1]}])
	for st: Array in states:
		var sets: Dictionary = st[1]
		for key in sets:
			panel.set(key, sets[key])
		panel.call("refresh")
		await process_frame
		for id in st[0]:
			var lbl := _state_label(panel, id)
			if lbl == null or not lbl.is_visible_in_tree():
				continue
			_fits(lbl, lbl.text, "%s 栏（%s）" % [id, JSON.stringify(sets)])
	for key in ["windward", "damage_control", "cut_hooks", "wet_felt", "board_ready"]:
		panel.set(key, false)
	panel.set("muster", 0.0)
	if not loads.is_empty():
		panel.set("load_mode", loads[0])
	panel.call("refresh")


func _show(panel: Node, lbl: Label, ctx: Dictionary) -> String:
	panel.set("parley_source", func() -> Dictionary: return ctx.duplicate())
	panel.call("refresh")
	await process_frame
	return lbl.text


func _fits(lbl: Label, text: String, tag: String) -> void:
	var f := lbl.get_theme_font("font")
	var fs := lbl.get_theme_font_size("font_size")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_expect(text != "" and w <= lbl.size.x + 0.5, "%s：「%s」字宽 %.0f ≤ 栏宽 %.0f" % [tag, text, w, lbl.size.x])


func _state_label(panel: Node, id: String) -> Label:
	var rows = panel.get("_rows")
	if not (rows is Dictionary) or not (rows as Dictionary).has(id):
		return null
	return (rows[id] as Dictionary).get("state", null) as Label


func _panel_of(wm: Node) -> Node:
	if wm == null:
		return null
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			return c
	return null


## 一场冻住敌炮的海战（敌船不开炮，结算不会自己发生）：广船对海鹘一艘
func _battle(fleet: Node, gm: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w54_hud"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	for _i in 3:
		await process_frame
	return wm


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
	print("QA_W54_HUD_ORDERS_STATE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
