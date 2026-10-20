extends SceneTree
## lane w54-hud：海战右上「敌情」卡的行与选中小卡在长写法下放得下，整张卡不被字撑宽、不冲出画布右缘。
## 布景：真起 WorldMap 海战（快船两艘，敌炮冻住），两艘都打到船体两成（伤沉在即）、士气簿将溃（想退），
## 再给敌船挂一个只回 state() 的水火假件（失火、进水），敌情行与小卡就是最长的写法；1280×720 与 21:9（画布 1706×720）各跑一遍。
## 证（headless 也跑——只量排版）：
##   一、没选中时：每行逐行字宽 ≤ 行宽（行字 clip_text，过宽那截直接裁掉）；行里仍写着「失火」「进水」，
##       放不下时短注折到第二行、第一行是「船种　伤情　布色」；整张卡在画布里、宽不过 INTEL_W。
##   二、选中一艘（小卡出）：小卡逐行字宽 ≤ 小卡那一格的宽、写着「失火，进水」；整张卡宽不过 INTEL_W + 4（纸底板两边）、
##       右沿在画布里，「喊话」「细看」两钮整颗在画布里。
##   三、收起小卡、火灭水排（短注没了）：行回一行，卡高收回到挂短注之前那么高（折过的行不留一截空纸）。
##   四、满血稳着的船照旧一行（「快船　稳」不折）。
##   五、贴边的写法「快船　带伤　稳　失火，进水」（十三字约 208 px，只比行宽 205 多几 px）同判一。
## 旧病（回退即红，一、二、五红）：行字照旧一行「快船　伤沉在即　想退　失火，进水」（16 号字约 256 px，行宽 205），
## 行尾「进水」被裁；小卡标签「快船 想退・失火，进水」约 166 px 没有裁边，那一格只有约 94 px——整张敌情卡被撑到 326 宽，
## 卡左沿仍按 INTEL_W 250 摆在画布右缘内，右沿冲出 1280 画布 60 px，「细看」钮只露 14 px。
## 用法：godot --headless --path . -s res://tools/qa_w54_hud_intel_fit_probe.gd（带窗口 DISPLAY=:2 同样可跑）
## 末行 QA_W54_HUD_INTEL_FIT cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const VIEWS := [Vector2i(1280, 720), Vector2i(2560, 1080)]
## 选中时整张卡比 INTEL_W 宽的那一点：小卡（IntelShipCard）最小宽 INTEL_W − 24 只扣了两边距，没扣敌情卡纸底板左右各 2 px，
## 小卡一出整张卡就是 254（改前就如此，实量）
const SHIP_CARD_EDGE := 4.0

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _stub: GDScript


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
	_stub = GDScript.new()
	_stub.source_code = "extends RefCounted\nvar st := {}\nfunc state() -> Dictionary:\n\treturn st\n"
	_stub.reload()
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}
	for v: Vector2i in VIEWS:
		root.size = v
		await _frames(2)
		await _one_view("%dx%d" % [v.x, v.y], fleet, gm)
	fleet.set("ships", saved["ships"])
	gm.set("pending_battle", saved["pb"])
	_report()


func _one_view(tag: String, fleet: Node, gm: Node) -> void:
	var wm := await _battle(fleet, gm)
	var hud: Node = null
	for c in wm.get_children():
		if c.is_in_group(Hud.GROUP):
			hud = c
	var foes: Array = wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip"))
	_expect(hud != null and hud.get("_intel") != null and foes.size() == 2, "%s 海战挂着敌情卡、两艘敌船（%d）" % [tag, foes.size()])
	if hud == null or hud.get("_intel") == null or foes.size() != 2:
		await _close(wm)
		return
	var card := hud.get("_intel") as Control
	var rows := hud.get("_intel_rows") as Node
	var cv := root.get_visible_rect()
	# 四、开局满血：簿钉稳，行一行
	for f in foes:
		f.set_meta(&"nk1_combat_morale", {"state": "steady", "value": 70})
	await _refresh(hud)
	var t0 := (rows.get_child(0).get_child(1) as Label).text
	_expect(not t0.contains("\n") and t0.begins_with("快船"), "%s 四 满血稳着的船照旧一行（「%s」）" % [tag, t0.replace("\n", "⏎")])
	# 打到船体两成、将溃：行仍一行（还没挂水火）——记下这时的卡高
	var seen: Dictionary = hud.get("_hull_seen")
	for f in foes:
		f.set_physics_process(false)
		var h0 := maxf(float(seen.get((f as Object).get_instance_id(), 0.0)), float(f.get("hull_hp")))
		seen[(f as Object).get_instance_id()] = h0
		f.set("hull_hp", h0 * 0.2)
		f.set_meta(&"nk1_combat_morale", {"state": "routing", "value": 20})
	await _refresh(hud)
	var h_plain := card.size.y
	# 挂水火：失火、进水
	for f in foes:
		var s = _stub.new()
		s.set("st", {"fire": 0.6, "flood": 0.4, "burning": true, "list_deg": 0.0, "sinking": false})
		f.set("flood_fire", s)
	await _refresh(hud)
	# 一、没选中
	for i in rows.get_child_count():
		var lbl := rows.get_child(i).get_child(1) as Label
		_fits(lbl, "%s 一 第 %d 行" % [tag, i + 1])
		var lines := lbl.text.split("\n")
		_expect(lbl.text.contains("失火") and lbl.text.contains("进水") and (lines.size() == 1 or lines[1] == "失火，进水"),
			"%s 一 第 %d 行写着水火短注，折行时第二行恰是短注（「%s」）" % [tag, i + 1, lbl.text.replace("\n", "⏎")])
	_card_inside(card, cv, Hud.INTEL_W, "%s 一 没选中" % tag)
	# 二、选中第一艘
	hud.call("_select_enemy", (foes[0] as Object).get_instance_id())
	await _refresh(hud)
	var sl := hud.get("_ship_card_lbl") as Label
	_expect(sl != null and sl.is_visible_in_tree() and sl.text.contains("失火，进水"), "%s 二 选中后小卡写着「失火，进水」（「%s」）" % [
		tag, sl.text.replace("\n", "⏎") if sl != null else "无"])
	if sl != null:
		_fits(sl, "%s 二 小卡" % tag)
	_card_inside(card, cv, Hud.INTEL_W + SHIP_CARD_EDGE, "%s 二 选中" % tag)
	var hail := hud.get("_ship_hail_btn") as Control
	var btns: Array = (hail.get_parent() as Node).get_children() if hail != null else []
	_expect(btns.filter(func(b): return b is Button).size() == 2, "%s 二 小卡上两颗钮（喊话、细看）" % tag)
	for b in btns:
		if b is Button:
			var r := (b as Control).get_global_rect()
			_expect(cv.encloses(r) and card.get_global_rect().grow(0.5).encloses(r),
				"%s 二 「%s」钮整颗在画布里、在敌情卡里（钮 %s，卡 %s）" % [tag, (b as Button).text, r, card.get_global_rect()])
	# 三、收起小卡、火灭水排
	hud.call("_select_enemy", (foes[0] as Object).get_instance_id())
	for f in foes:
		(f.get("flood_fire") as Object).set("st", {})
	await _refresh(hud)
	var one_line := true
	for i in rows.get_child_count():
		one_line = one_line and not (rows.get_child(i).get_child(1) as Label).text.contains("\n")
	_expect(one_line and card.size.y <= h_plain + 0.5, "%s 三 短注没了行回一行、卡高收回（%.0f → %.0f，挂水火前 %.0f）" % [
		tag, h_plain, card.size.y, h_plain])
	# 五、贴边的写法：「快船　带伤　稳　失火，进水」十三字约 208 px，比行宽 205 只多几 px——照样不许裁
	var f2: Node = foes[1]
	f2.set("hull_hp", float(seen.get((f2 as Object).get_instance_id(), 0.0)) * 0.6)
	f2.set_meta(&"nk1_combat_morale", {"state": "steady", "value": 70})
	(f2.get("flood_fire") as Object).set("st", {"fire": 0.6, "flood": 0.4, "burning": true, "list_deg": 0.0, "sinking": false})
	await _refresh(hud)
	var lbl5 := rows.get_child(1).get_child(1) as Label
	_expect(lbl5.text.replace("\n", "　") == "快船　带伤　稳　失火，进水", "%s 五 布景得的是贴边那一句（「%s」）" % [tag, lbl5.text.replace("\n", "⏎")])
	_fits(lbl5, "%s 五 贴边一句" % tag)
	await _close(wm)


func _refresh(hud: Node) -> void:
	hud.call("refresh")
	await _frames(4)
	hud.call("refresh")
	await _frames(2)


## 标签逐行字宽 ≤ 标签宽
func _fits(lbl: Label, tag: String) -> void:
	var f := lbl.get_theme_font("font")
	var fs := lbl.get_theme_font_size("font_size")
	var widest := 0.0
	for line in lbl.text.split("\n"):
		widest = maxf(widest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	_expect(lbl.text != "" and widest <= lbl.size.x + 0.5, "%s：「%s」最宽一行 %.0f ≤ 栏宽 %.0f（%d 号字）" % [
		tag, lbl.text.replace("\n", "⏎"), widest, lbl.size.x, fs])


func _card_inside(card: Control, cv: Rect2, max_w: float, tag: String) -> void:
	var r := card.get_global_rect()
	_expect(cv.encloses(r) and r.size.x <= max_w + 0.5, "%s：敌情卡整张在画布里、宽不过 %.0f（卡 %s，画布 %s）" % [tag, max_w, r, cv.size])


## 一场冻住敌炮的海战：广船对快船两艘
func _battle(fleet: Node, gm: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海", "source": {"scene": "qa_w54_hud"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	# 士气挂件逐物理帧按船伤改写敌船簿上的状态：停掉它，簿由探针钉（同 patrol_shell 白刃布景）
	var tracker = wm.get("_morale")
	if tracker is Node:
		(tracker as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(6)
	return wm


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
	print("QA_W54_HUD_INTEL_FIT cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
