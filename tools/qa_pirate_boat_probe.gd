extends SceneTree
## 海寇快船（备忘 #7）+ 船图契约探针（lane pirate-boat-0928；lane w19-g3 跟现行代码、入册 lane 档）：真走 SeaChart 的两条敌船条目 →
## WorldMap 开战 → _spawn_enemy 生成 → 接舷夺船（两艘都夺下、末艘收战）→ Fleet 入列；再验缺图回落、有图就用、旧档里夺来的海鹘照读。
## 用法：godot --headless --path . -s res://tools/qa_pirate_boat_probe.gd            # 门禁（docs/GATES.md §一，lane 档）
##      godot --headless --quiet --path . -s res://tools/qa_pirate_boat_probe.gd -- --json   # 机读（tools/gate_report.gd）
##      DISPLAY=:2 godot --path . -s res://tools/qa_pirate_boat_probe.gd -- --shots <目录>   # 有窗口另截海战 5 张（不接 shot_gate、不入截图册）
## 只动存档位 93（不碰正式位 1..SLOTS），跑完删掉；Fleet / pending_battle 跑完还原。本进程出 SCRIPT ERROR 即判红（自挂 Logger 数）。
## `_run` 自己的代码行出脚本错时 GDScript 只中止 `_run`、末尾 quit 永不执行，原先空转到外层超时；现由 _run_guarded 包装
## 就地判红收尾、退 1（lane w53-11 四轮；gates_md「一之三」判注册门禁不许裸排 `_run` 起跑）。
## lane w19-g3 跟现行代码改的四处（原期望写在 origin 那条 / 09-28 crew 线上，09-30 合并按本地线落地后过时）：
##   · 夺船存名：本地线 WorldMap 以敌船名入列（Fleet.add_ship(type, ship_name)），存名仍「快船」，不按序号起名——
##     V0928-10 定 B（lane w53-14）：Fleet.prize_name 不接；同名两艘上屏靠 Fleet.display_name 加「・甲」「・乙」（lane fx2）。
##     元军哨船条目不挂 prize_name，夺来名是 ships.json 的「海鹘」。
##   · 白刃必胜：清零敌船水手前先停士气挂件（同 lane fx8 在 patrol_shell 的做法）——本地线 combat06 士气挂件逐物理帧读 crew，
##     清零记成伤亡过半 + 被钩，窗口下接舷停拍 0.42 s 里敌船降幡、走受降一路（下场 struck），不是白刃夺船。
##   · 海战船身：Ship / PirateShip 下挂 ShipHull3D（HullRig），Sprite2D 贴的是 3D 宋船的 SubViewport 视口，不是 ship_<id>.png；
##     战中改验「船身接到 3D 视口、敌红帆我素帆」，船图契约（ship_<id>.png 有就用、缺图回落）照旧在三节拿未进树的实例验。
##   · 有窗口时夺船句：「夺船」题签副题写白刃经过（MeleeResolve.summary，如「敌船上无人拒守，登船即得。」），lane w53-14 起另起一行
##     写「「快船」并入本队。」（拍板「抓捕副题船名」）；有题签就不出浮字（crew 线 9e35254，09-30 合并丢了、lane w19-g1 ae27f4b 补回）。
##     headless 题签起不来，夺船句走浮字兜底。

const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（同 p7 / smoke 的接法）
const HULL3D := "res://scripts/combat/ShipHull3D.gd"
const SLOT := 93
const TAG := "QA_PIRATE_BOAT_PROBE"
const VIEW := Vector2i(1280, 720)
## 保证不在库的精灵 id：验「缺图回落」只拿它。真 type（pirate_boat / sampan / yuan_patrol …）美术按契约会交图，
## 它们的期望值由 _want 按图在不在算——收一张生效一张，探针不随收图变红。
const ABSENT := "__nk1_absent__"

var _fails: Array = []
var _shots: Array = []
var _errlog: _ScriptErrLog = null
var _reported := false


func _init() -> void:
	call_deferred("_run_guarded")


## `_run` 断气回来时还没走到 _finish（头注释）：点名首条脚本错，就地判红收尾。
func _run_guarded() -> void:
	await _run()
	if not _reported:
		var note := ("_run 半路中止，首条脚本错：" + str(_errlog.lines[0])) if _errlog != null and not _errlog.lines.is_empty() \
			else "_run 提前 return、没走收尾"
		_expect(false, "主流程跑到收尾（%s）" % note)
		_finish()


func _expect(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	GateReport.check(ok, what)
	if not ok:
		_fails.append(what)


## 船图契约的期望值：assets/ship_<id>.png 在库就是它，不在是 fallback（与 CombatFx.ship_sprite_path 同规则的独立写法）
func _want(sid: String, fallback: String) -> String:
	var p := CombatFx.SHIP_SPRITE_FMT % sid
	return p if sid != "" and ResourceLoader.exists(p, "Texture2D") else fallback


## 断言文案用：有图写「有 ship_<id>.png → 用它」，缺图写「缺 ship_<id>.png → 回落 <fallback>」
func _want_note(sid: String, fallback: String) -> String:
	var w := _want(sid, fallback)
	if w == fallback:
		return "缺 ship_%s.png → 回落 %s" % [sid, fallback.get_file()]
	return "有 ship_%s.png → 用它" % sid


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame
	var gm: Node = root.get_node("GameManager")
	var fleet: Node = root.get_node("Fleet")
	var sl: Node = root.get_node("SaveLoad")
	var saved_ships: Array = (fleet.get("ships") as Array).duplicate(true)
	var saved_battle: Dictionary = (gm.get("pending_battle") as Dictionary).duplicate(true)

	var consts: Dictionary = (load("res://scripts/SeaChart.gd") as GDScript).get_script_constant_map()
	var pirate: Dictionary = consts.get("PIRATE_ENEMY", {})
	var patrol: Dictionary = consts.get("PATROL_ENEMY", {})
	_expect(str(pirate.get("type", "")) == "pirate_boat" and not pirate.has("sprite"), "SeaChart 海寇条目 type=pirate_boat，不另挂 sprite")
	_expect(str(patrol.get("type", "")) == "sea_falcon" and str(patrol.get("sprite", "")) == "yuan_patrol" and not patrol.has("prize_name"),
		"SeaChart 元军哨船条目 type 仍是 sea_falcon，sprite=yuan_patrol，不挂 prize_name（夺来名随 type 取）")

	# ── 一、海寇一战：生成、3D 船身与船图契约、两艘都夺下得两条「快船」、末艘以 boarded 收战 ──
	await _pirate_battle(gm, fleet, pirate)
	# ── 二、元军哨船一战：精灵键按 sprite 取、契约有图用图缺图回落；船名仍是海鹘 ──
	await _patrol_battle(gm, fleet, patrol)
	# ── 三、有图就用（拿仓里现成的两张默认贴图当「按船型的图」）──
	_check_lookup()
	# ── 四、存档：旧档里夺来的海鹘、新档里的快船都照读 ──
	_check_save(fleet, sl)
	# ── 五、有窗口且给了 --shots：截海战（精灵有图用图、缺图回落默认贴图；墨边副题写快船）──
	var shot_dir := _shot_dir()
	if shot_dir != "" and DisplayServer.get_name() != "headless":
		await _take_shots(gm, fleet, pirate, patrol, shot_dir)

	fleet.set("ships", saved_ships)
	gm.set("pending_battle", saved_battle)
	await process_frame
	_finish()


## 收尾（`_run` 走完与 _run_guarded 兜底共用）：判本进程脚本错、打末行、退出。
func _finish() -> void:
	_reported = true
	OS.remove_logger(_errlog)
	_expect(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	var rc := 0 if _fails.is_empty() else 1
	var summary := "%s %s（%d 项不合；截图 %d 张）" % [TAG, "PASS" if rc == 0 else "FAIL", _fails.size(), _shots.size()]
	print(summary)
	GateReport.finish("qa_pirate_boat_probe", rc, summary)
	quit(rc)


func _shot_dir() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].begins_with("--shots="):
			return args[i].substr(8)
		if args[i] == "--shots" and i + 1 < args.size():
			return args[i + 1]
	return ""


func _shoot(dir: String, name: String, want: Callable) -> bool:
	var why: String = await CombatStage.wait_drawn(self, want)
	if why != "":
		_expect(false, "截图 %s 没等到该相位：%s" % [name, why])
		return false
	var path := dir.path_join(name + ".png")
	var err := root.get_texture().get_image().save_png(path)
	_expect(err == OK, "截图 %s（%s）" % [name, path])
	if err == OK:
		_shots.append(path)
	await process_frame
	return err == OK


## 敌船停航停炮、摆进镜头：截图要固定机位（开战刷在 210—235，刷出后会绕本船兜圈）
func _pose(wm: Node, offsets: Array) -> void:
	var own: Node2D = wm.get("ship")
	CombatStage.freeze_enemy_fire(wm)
	var foes := _enemies(wm)
	for i in foes.size():
		var foe: Node2D = foes[i]
		foe.set_physics_process(false)
		foe.position = own.position + (offsets[i % offsets.size()] as Vector2)
		foe.rotation = (own.position - foe.position).angle() + PI * 0.5


func _lb_ready(wm_ref: WeakRef, needle: String) -> bool:
	var lb: Node = CombatStage.letterbox_under(self, wm_ref.get_ref())
	if lb == null:
		return false
	var sub: Label = lb.get("_sub")
	return str(lb.get("subtitle")).find(needle) >= 0 and sub != null and sub.modulate.a >= 0.99


func _take_shots(gm: Node, fleet: Node, pirate: Dictionary, patrol: Dictionary, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = VIEW
	var offsets := [Vector2(190, -70), Vector2(-170, -110), Vector2(20, -210)]
	# 海寇一战
	_battle_fleet(fleet)
	var wm := _start(gm, pirate)
	var ref: WeakRef = weakref(wm)
	_pose(wm, offsets)
	await _shoot(dir, "01_海寇入战墨边_快船二艘", func() -> bool: return _lb_ready(ref, "快船二艘"))
	await _shoot(dir, "02_海寇海战", func() -> bool:
		return ref.get_ref() != null and CombatStage.letterbox_under(self, ref.get_ref()) == null)
	var foes := _enemies(wm)
	if not foes.is_empty():
		var foe: Node2D = foes[0]
		_calm_morale(wm)
		foe.set("crew", 0)
		foe.position = (wm.get("ship") as Node2D).position + Vector2(90, 0)
		wm.call("_board_enemy", foe)
		# 「夺船」题签全显、副题写白刃经过，浮字不再说夺船那句（有题签就不出夺船浮字，lane w19-g1）
		await _shoot(dir, "03_接舷夺船_题签", func() -> bool:
			var w = ref.get_ref()
			var cap: Array = CombatStage.board_caption(self, w)
			var nt: Label = w.get("_notice") if w != null else null
			return cap[0] == "夺船" and cap[1] >= 0.99 and (nt == null or not nt.visible or nt.text.find("并入本队") < 0))
	CombatStage.teardown(self, ref.get_ref(), gm)
	await process_frame
	await process_frame
	# 元军哨船一战
	_battle_fleet(fleet)
	var wm2 := _start(gm, patrol)
	var ref2: WeakRef = weakref(wm2)
	_pose(wm2, offsets)
	await _shoot(dir, "04_元军哨船入战墨边_海鹘三艘", func() -> bool: return _lb_ready(ref2, "海鹘三艘"))
	await _shoot(dir, "05_元军哨船海战", func() -> bool:
		return ref2.get_ref() != null and CombatStage.letterbox_under(self, ref2.get_ref()) == null)
	CombatStage.teardown(self, ref2.get_ref(), gm)
	await process_frame


func _battle_fleet(fleet: Node) -> void:
	# 开局旗舰小艍船：有 assets/ship_sampan.png 就用，不在回落 ship_fu.png（断言按 _want 算）
	fleet.set("ships", [{"type": "sampan", "name": "无名小艍", "crew": 15, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": 120.0, "max_durability": 120.0}])
	fleet.set("morale", 70)


func _enemies(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _tex_path(n: Node) -> String:
	var spr := n.get_node_or_null("Sprite2D") as Sprite2D
	return spr.texture.resource_path if spr != null and spr.texture != null else ""


func _start(gm: Node, entry: Dictionary) -> Node:
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [entry.duplicate()], "sea_name": "泉州外海", "source": {"scene": TAG}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	CombatStage.freeze_enemy_fire(wm)  # 有窗口时敌炮 3.5 s 首轮齐射，接舷停拍 + 题签几秒里能把开局小艍打沉、布景自行结算
	return wm


## 停士气挂件（lane fx8 同法）：挂件逐物理帧读敌船 crew，清零记成伤亡过半 + 被钩，窗口下接舷停拍里敌船降幡、走受降一路
func _calm_morale(wm: Node) -> void:
	var tracker = wm.get("_morale")
	if tracker is Node:
		(tracker as Node).process_mode = Node.PROCESS_MODE_DISABLED


## 海战船身：HullRig 挂 ShipHull3D、船模载上、帆色合敌我、Sprite2D 贴的是它的 SubViewport 视口；合格返回 ""，否则一句不合处
func _hull_why(n: Node, crimson: bool) -> String:
	if n == null or not is_instance_valid(n):
		return "船节点不在"
	var rig: Node = n.get_node_or_null("HullRig")
	var scr: Script = rig.get_script() if rig != null else null
	if scr == null or scr.resource_path != HULL3D:
		return "没挂 HullRig（%s）" % HULL3D.get_file()
	if not bool(rig.get("_ready_visual")):
		return "船模没载上"
	if bool(rig.get("sail_crimson")) != crimson:
		return "帆色不对（sail_crimson=%s）" % rig.get("sail_crimson")
	var vp := rig.get_node_or_null("View") as SubViewport
	var spr := n.get_node_or_null("Sprite2D") as Sprite2D
	if vp == null or spr == null or spr.texture != vp.get_texture():
		return "Sprite2D 没贴 3D 视口（得 %s）" % (_tex_path(n) if spr != null and spr.texture != null and _tex_path(n) != "" else "无")
	return ""


## 等船身绑上（ShipHull3D._bind_sprite 是 call_deferred）；最多 2 s 墙钟
func _hull_ready(n: Node, crimson: bool) -> String:
	var ref: WeakRef = weakref(n)
	await CombatStage.wait_until(self, func() -> bool: return _hull_why(ref.get_ref(), crimson) == "", 2000)
	return _hull_why(ref.get_ref(), crimson)


## 白刃必胜地夺一艘：停士气挂件 → 敌船水手清零（敌战力 0 → 胜率 1）→ 贴舷 → _board_enemy；等船队多一艘（窗口下先停 0.42 s）
func _board(wm: Node, fleet: Node, foe: Node2D) -> bool:
	_calm_morale(wm)
	foe.set("crew", 0)
	foe.set_physics_process(false)
	foe.position = (wm.get("ship") as Node2D).position + Vector2(90, 0)
	var n0: int = (fleet.get("ships") as Array).size()
	wm.call("_board_enemy", foe)
	return await CombatStage.wait_until(self, func() -> bool: return (fleet.get("ships") as Array).size() > n0, 5000)


## 本场已记的敌船下场（WorldMap._enemy_fates 的值，按记录顺序）
func _fates_noted(wm: Node) -> Array:
	var out: Array = []
	var d = wm.get("_enemy_fates") if wm != null and is_instance_valid(wm) else null
	if d is Dictionary:
		for v in (d as Dictionary).values():
			out.append("%s/%s" % [v.get("type", ""), v.get("fate", "")])
	return out


func _pirate_battle(gm: Node, fleet: Node, pirate: Dictionary) -> void:
	_battle_fleet(fleet)
	var wm := _start(gm, pirate)
	var result: Array = []
	wm.connect("battle_finished", func(outcome: String, data: Dictionary) -> void: result.append([outcome, data]))
	await process_frame
	var own: Node = wm.get("ship")
	var own_why: String = await _hull_ready(own, false)
	_expect(own_why == "", "旗舰海战船身接 3D 宋船视口、素帆（%s）" % (own_why if own_why != "" else "HullRig 视口已贴上"))
	_expect(CombatFx.ship_sprite_path(str((fleet.call("flagship") as Dictionary).get("type", "")), CombatFx.SHIP_SPRITE_OWN) == _want("sampan", CombatFx.SHIP_SPRITE_OWN),
		"旗舰小艍船的船图契约：%s（船身视口接上前的底图）" % _want_note("sampan", CombatFx.SHIP_SPRITE_OWN))
	var foes := _enemies(wm)
	_expect(foes.size() == int(pirate.get("count", 0)), "海寇生成 %d 艘（条目 count=%d）" % [foes.size(), int(pirate.get("count", 0))])
	if foes.size() < 2:
		await _drop(wm)
		return
	var foe: Node2D = foes[0]
	_expect(str(foe.get("ship_type")) == "pirate_boat" and str(foe.get("ship_name")) == "快船",
		"敌船 ship_type=pirate_boat、船名「快船」（得 %s / %s）" % [foe.get("ship_type"), foe.get("ship_name")])
	_expect(str(foe.call("sprite_key")) == "pirate_boat"
			and CombatFx.ship_sprite_path(str(foe.call("sprite_key")), CombatFx.SHIP_SPRITE_ENEMY) == _want("pirate_boat", CombatFx.SHIP_SPRITE_ENEMY),
		"海寇敌船精灵键 pirate_boat，船图契约：%s" % _want_note("pirate_boat", CombatFx.SHIP_SPRITE_ENEMY))
	var foe_why: String = await _hull_ready(foe, true)
	_expect(foe_why == "", "海寇敌船海战船身接 3D 宋船视口、红帆（%s）" % (foe_why if foe_why != "" else "HullRig 视口已贴上"))

	# 夺第一艘（非末艘：不收战）；先打掉一半船体——入列耐久按战中剩余比例折（V0928-7 定 A，lane w53-14）
	var n0: int = (fleet.get("ships") as Array).size()
	var foe_hull_max: float = float(foe.get("hull_max"))
	foe.set("hull_hp", foe_hull_max * 0.5)
	var took: bool = await _board(wm, fleet, foe)
	var ships: Array = fleet.get("ships")
	var got: Dictionary = ships[ships.size() - 1] if took else {}
	_expect(took and ships.size() == n0 + 1, "接舷得胜，船队多一艘（%d → %d）" % [n0, ships.size()])
	_expect(str(got.get("type", "")) == "pirate_boat" and str(got.get("name", "")) == "快船",
		"夺来的船按 pirate_boat 入列、存名沿用敌船名「快船」（V0928-10 定 B，不按序号起名；得 %s / %s）" % [got.get("type", "无"), got.get("name", "无")])
	var d: Dictionary = fleet.call("ship_def", "pirate_boat")
	_expect(foe_hull_max > 0.0 and float(got.get("max_durability", -1.0)) == float(d.get("durability", -2))
			and float(got.get("durability", -1.0)) == roundf(float(d.get("durability", 0)) * 0.5)
			and int(got.get("crew", -1)) == int(int(d.get("crew_min", 0)) / 2),
		"入列快船：耐久上限照 ships.json（%s），耐久按敌船战中剩一半折（%s），随船水手取 crew_min 一半（%s）"
			% [got.get("max_durability", "无"), got.get("durability", "无"), got.get("crew", "无")])
	_expect(_fates_noted(wm) == ["pirate_boat/boarded"], "第一艘记下场 boarded，走的是白刃夺船、不是受降（得 %s）" % [_fates_noted(wm)])
	_expect(result.is_empty() and is_instance_valid(wm) and not bool(wm.get("resolved")), "还剩一艘，不收战")
	# headless 题签起不来，夺船句（CombatFx.board_win_note）走浮字兜底；有窗口时「夺船」题签副题写白刃经过（MeleeResolve.summary），
	# 有题签就不出浮字（crew 线 9e35254，lane w19-g1 ae27f4b 补回）
	var notice: Label = wm.get("_notice")
	if DisplayServer.get_name() == "headless":
		var note_txt := notice.text if notice != null else ""
		_expect(note_txt.find("敌船「快船」并入本队") >= 0 and note_txt.find("海鹘") < 0, "headless 夺船浮字兜底写「快船」（得「%s」）" % note_txt)
	else:
		var st: Node = CombatStage.boarding_stage(self, wm)
		var sub: Label = st.get("_sub") if st != null else null
		var cap: Array = CombatStage.board_caption(self, wm)
		var sub_txt := sub.text if sub != null else ""
		_expect(cap[0] == "夺船" and sub_txt.get_slice("\n", 0) != "" and sub_txt.ends_with("\n「快船」并入本队。") and sub_txt.find("海鹘") < 0,
			"有窗口：「夺船」题签副题写白刃经过，另起一行写「快船」并入本队（lane w53-14；题名「%s」，副题「%s」）" % [cap[0], sub_txt.replace("\n", "⏎")])
		# 浮字别的话（敌将改打法等战况注记）照出；判的是夺船这件事不在浮字上再说一遍（同 patrol 末艘夺船一节，lane w19-g1）
		var nt_txt := notice.text if notice != null and notice.visible else ""
		_expect(nt_txt.find("并入本队") < 0 and (nt_txt == "" or nt_txt != sub_txt),
			"有窗口有题签时浮字不再说夺船那句（浮字「%s」）" % nt_txt)
	# 窗口下等第一艘的题签演完再接舷第二艘（同帧再起一副会顶掉上一副）
	var wref: WeakRef = weakref(wm)
	await CombatStage.wait_until(self, func() -> bool: return CombatStage.boarding_stage(self, wref.get_ref()) == null, 5000)

	# 夺第二艘＝末艘：以 boarded 收战；两条同名「快船」存档不改名、上屏按次序加「・甲」「・乙」（lane fx2）
	var rest := _enemies(wm)
	_expect(rest.size() == 1, "夺下一艘后场上剩 1 艘海寇（得 %d）" % rest.size())
	if rest.size() == 1:
		var n1: int = (fleet.get("ships") as Array).size()
		var took2: bool = await _board(wm, fleet, rest[0])
		# headless 当帧收战；窗口下等「夺船」题签停满 T_HOLD、淡出再收（lane fx8）
		await CombatStage.wait_until(self, func() -> bool: return not result.is_empty(), 8000)
		ships = fleet.get("ships")
		_expect(took2 and ships.size() == n1 + 1, "末艘也夺下，船队 %d → %d" % [n1, ships.size()])
		var names: Array = []
		var shown: Array = []
		for i in ships.size():
			names.append(str(ships[i].get("name", "")))
			shown.append(str(fleet.call("display_name", i)))
		_expect(names.slice(n0) == ["快船", "快船"], "两艘夺来的船存名都是「快船」（存档不改名；得 %s）" % [names])
		var a1 := str(shown[n0]) if shown.size() > n0 else ""
		var a2 := str(shown[n0 + 1]) if shown.size() > n0 + 1 else ""
		_expect(a1 != a2 and a1.begins_with("快船・") and a2.begins_with("快船・"),
			"同名两艘上屏分得清：Fleet.display_name 按次序加后缀（得 %s）" % [shown])
		var outcome := str(result[0][0]) if result.size() == 1 else "未收战"
		var data: Dictionary = result[0][1] if result.size() == 1 else {}
		var fates: Array = (data.get("fates", []) as Array).map(func(f) -> String: return str((f as Dictionary).get("fate", "")))
		_expect(result.size() == 1 and outcome == "win" and bool(data.get("boarded", false)) and fates == ["boarded", "boarded"],
			"末艘夺下以 win + boarded 收战，下场两艘都记 boarded（得 %s / boarded=%s / %s）" % [outcome, data.get("boarded", false), fates])
	await _drop(wm)


## 拆场：墨边 _abort、布景 queue_free（有窗口时接舷题签 / 墨边还在演，不直接 free），空两帧让释放落地
func _drop(wm) -> void:  # 不写类型：末艘夺下后布景已自行收战释放，带类型的形参收到已释放实例当场 SCRIPT ERROR
	CombatStage.teardown(self, wm)
	await process_frame
	await process_frame


func _patrol_battle(gm: Node, fleet: Node, patrol: Dictionary) -> void:
	_battle_fleet(fleet)
	var wm := _start(gm, patrol)
	await process_frame
	var foes := _enemies(wm)
	_expect(foes.size() == int(patrol.get("count", 0)), "元军哨船生成 %d 艘" % foes.size())
	if not foes.is_empty():
		var foe: Node = foes[0]
		var falcon: String = str((fleet.call("ship_def", "sea_falcon") as Dictionary).get("name", ""))
		_expect(str(foe.get("ship_type")) == "sea_falcon" and falcon == "海鹘" and str(foe.get("ship_name")) == falcon,
			"元军哨船 type 不动（sea_falcon），船名随 type 是「海鹘」、夺来即按此名入列（得 %s / %s）" % [foe.get("ship_type"), foe.get("ship_name")])
		_expect(str(foe.get("sprite_id")) == "yuan_patrol" and str(foe.call("sprite_key")) == "yuan_patrol",
			"WorldMap 把 entry.sprite 传给敌船（sprite_id=yuan_patrol）")
		_expect(CombatFx.ship_sprite_path(str(foe.call("sprite_key")), CombatFx.SHIP_SPRITE_ENEMY) == _want("yuan_patrol", CombatFx.SHIP_SPRITE_ENEMY),
			"元军哨船船图契约：%s" % _want_note("yuan_patrol", CombatFx.SHIP_SPRITE_ENEMY))
		var why: String = await _hull_ready(foe, true)
		_expect(why == "", "元军哨船海战船身接 3D 宋船视口、红帆（%s）" % (why if why != "" else "HullRig 视口已贴上"))
	await _drop(wm)


func _check_lookup() -> void:
	# ship_fu / ship_falcon 按契约也是「ship_<id>.png」：id=fu / falcon 时取到的是它们，证明文件在就用、不回落
	_expect(CombatFx.ship_sprite_path("fu", CombatFx.SHIP_SPRITE_ENEMY) == CombatFx.SHIP_SPRITE_OWN, "文件在：id=fu 取 ship_fu.png 不回落")
	_expect(CombatFx.ship_sprite_path(ABSENT, CombatFx.SHIP_SPRITE_ENEMY) == CombatFx.SHIP_SPRITE_ENEMY, "文件不在：回落 fallback")
	_expect(CombatFx.ship_sprite_path("", CombatFx.SHIP_SPRITE_OWN) == CombatFx.SHIP_SPRITE_OWN, "id 空：回落 fallback")
	_expect(CombatFx.ship_sprite_path("../icon", CombatFx.SHIP_SPRITE_OWN) == CombatFx.SHIP_SPRITE_OWN, "id 带路径字符：不拼路径，回落")
	var foe: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	foe.set("sprite_id", "fu")
	foe.call("apply_sprite")
	_expect(_tex_path(foe) == CombatFx.SHIP_SPRITE_OWN, "敌船 sprite_id 指向在库的图就换上（得 %s）" % _tex_path(foe))
	# 先换成别的图再指向不在库的 id：回落要真把默认贴图换回来，不是原地没动
	foe.set("sprite_id", "")
	foe.set("ship_type", ABSENT)
	foe.call("apply_sprite")
	_expect(str(foe.call("sprite_key")) == ABSENT and _tex_path(foe) == CombatFx.SHIP_SPRITE_ENEMY,
		"敌船清掉 sprite_id 后按 type 取，type 缺图换回 ship_falcon（得 %s）" % _tex_path(foe))
	foe.set("ship_type", "pirate_boat")
	foe.call("apply_sprite")
	_expect(_tex_path(foe) == _want("pirate_boat", CombatFx.SHIP_SPRITE_ENEMY),
		"敌船按 type=pirate_boat：%s（得 %s）" % [_want_note("pirate_boat", CombatFx.SHIP_SPRITE_ENEMY), _tex_path(foe)])
	foe.free()
	var own: Node = (load("res://scenes/Ship.tscn") as PackedScene).instantiate()
	own.call("apply_type_sprite", "falcon")
	_expect(_tex_path(own) == CombatFx.SHIP_SPRITE_ENEMY, "旗舰 type 指向在库的图就换上（得 %s）" % _tex_path(own))
	own.call("apply_type_sprite", ABSENT)
	_expect(_tex_path(own) == CombatFx.SHIP_SPRITE_OWN, "旗舰 type 缺图换回 ship_fu.png（得 %s）" % _tex_path(own))
	for t in ["sampan", "sea_falcon", "pirate_boat", "divine_ship"]:
		own.call("apply_type_sprite", t)
		_expect(_tex_path(own) == _want(t, CombatFx.SHIP_SPRITE_OWN),
			"旗舰 %s：%s（得 %s）" % [t, _want_note(t, CombatFx.SHIP_SPRITE_OWN), _tex_path(own)])
	own.free()


func _check_save(fleet: Node, sl: Node) -> void:
	# 旧档：09-28 以前夺来的海寇船是 sea_falcon「海鹘」；新档：快船。都得照读、船型都查得到。
	fleet.set("ships", [
		{"type": "sampan", "name": "无名小艍", "crew": 15, "sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 120.0, "max_durability": 120.0},
		{"type": "sea_falcon", "name": "海鹘", "crew": 40, "sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 700.0, "max_durability": 700.0},
		{"type": "pirate_boat", "name": "快船", "crew": 40, "sail_level": 2, "armor_level": 1, "cargo": {}, "durability": 650.0, "max_durability": 700.0},
	])
	_expect(bool(sl.call("save_game", SLOT, "quanzhou")), "带海鹘与快船的船队能存档（位 %d）" % SLOT)
	fleet.set("ships", [])
	_expect(bool(sl.call("load_game", SLOT)), "读档成功（SaveLoad 不按船型拒档）")
	var ships: Array = fleet.get("ships")
	var types: Array = []
	for s in ships:
		types.append(str(s.get("type", "")))
	_expect(types == ["sampan", "sea_falcon", "pirate_boat"], "读回船型原样（得 %s）" % [types])
	var all_def := true
	for t in types:
		all_def = all_def and not (fleet.call("ship_def", t) as Dictionary).is_empty()
	_expect(all_def, "读回的三型都在 ships.json（载重 / 航速 / 改装照常查得到）")
	_expect(ships.size() == 3 and float(ships[2].get("durability", 0)) == 650.0 and int(ships[2].get("sail_level", 0)) == 2,
		"快船的耐久与帆级读回不变")
	for p in ["user://saves/save_%d.json" % SLOT, "user://saves/save_%d.json.bak" % SLOT, "user://saves/save_%d.json.tmp" % SLOT]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## 数本进程里的 SCRIPT ERROR（运行期脚本错；push_error / 引擎 ERROR 不算——坏档类探针才故意喂错）
class _ScriptErrLog extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
