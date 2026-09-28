extends SceneTree
## 海寇快船（备忘 #7）+ 船图契约探针（lane pirate-boat-0928）：真走 SeaChart 的两条敌船条目 → WorldMap 开战 →
## _spawn_enemy 生成 → 接舷夺船 → Fleet 入列；再验缺图回落、有图就用、旧档里夺来的海鹘照读。
## 用法：godot --headless --path . -s res://tools/qa_pirate_boat_probe.gd
## 只动存档位 93（不碰正式位 1..SLOTS），跑完删掉；Fleet / pending_battle 跑完还原。输出含 SCRIPT ERROR 即视为失败。

const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const SLOT := 93
const TAG := "QA_PIRATE_BOAT_PROBE"

var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _expect(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
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
	_expect(str(patrol.get("type", "")) == "sea_falcon" and str(patrol.get("sprite", "")) == "yuan_patrol",
		"SeaChart 元军哨船条目 type 仍是 sea_falcon，sprite=yuan_patrol")

	# ── 一、海寇一战：生成、精灵回落、夺船得快船 ──
	await _pirate_battle(gm, fleet, pirate)
	# ── 二、元军哨船一战：精灵按 sprite 取，缺图回落；船名仍是海鹘 ──
	await _patrol_battle(gm, fleet, patrol)
	# ── 三、有图就用（拿仓里现成的两张默认贴图当「按船型的图」）──
	_check_lookup()
	# ── 四、存档：旧档里夺来的海鹘、新档里的快船都照读 ──
	_check_save(fleet, sl)

	fleet.set("ships", saved_ships)
	gm.set("pending_battle", saved_battle)
	print("%s %s（%d 项不合）" % [TAG, "PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)


func _battle_fleet(fleet: Node) -> void:
	# 开局旗舰小艍船：assets/ship_sampan.png 不在 → 己船精灵回落 ship_fu.png
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
	return wm


func _pirate_battle(gm: Node, fleet: Node, pirate: Dictionary) -> void:
	_battle_fleet(fleet)
	var wm := _start(gm, pirate)
	await process_frame
	var own: Node = wm.get("ship")
	_expect(own != null and _tex_path(own) == CombatFx.SHIP_SPRITE_OWN,
		"旗舰小艍船缺 ship_sampan.png → 己船精灵回落 ship_fu.png（得 %s）" % (_tex_path(own) if own != null else "无旗舰"))
	var foes := _enemies(wm)
	_expect(foes.size() == int(pirate.get("count", 0)), "海寇生成 %d 艘（条目 count=%d）" % [foes.size(), int(pirate.get("count", 0))])
	if foes.is_empty():
		wm.free()
		return
	var foe: Node = foes[0]
	_expect(str(foe.get("ship_type")) == "pirate_boat" and str(foe.get("ship_name")) == "快船",
		"敌船 ship_type=pirate_boat、船名「快船」（得 %s / %s）" % [foe.get("ship_type"), foe.get("ship_name")])
	_expect(str(foe.call("sprite_key")) == "pirate_boat" and _tex_path(foe) == CombatFx.SHIP_SPRITE_ENEMY,
		"海寇缺 ship_pirate_boat.png → 敌船精灵回落 ship_falcon.png（得 %s）" % _tex_path(foe))
	# 白刃必胜：敌船水手清零 → 敌战力 0 → 胜率 1
	foe.set("crew", 0)
	var n0: int = (fleet.get("ships") as Array).size()
	await wm.call("_board_enemy", foe)
	var ships: Array = fleet.get("ships")
	var got: Dictionary = ships[ships.size() - 1] if ships.size() > n0 else {}
	_expect(ships.size() == n0 + 1, "接舷得胜，船队多一艘（%d → %d）" % [n0, ships.size()])
	_expect(str(got.get("type", "")) == "pirate_boat" and str(got.get("name", "")) == "快船",
		"夺来的船按 pirate_boat 入列、名「快船」（得 %s / %s）" % [got.get("type", "无"), got.get("name", "无")])
	var d: Dictionary = fleet.call("ship_def", "pirate_boat")
	_expect(float(got.get("max_durability", -1.0)) == float(d.get("durability", -2)) and int(got.get("crew", -1)) == int(d.get("crew_min", -2)),
		"入列快船耐久、水手照 ships.json 的快船（%s / %s）" % [got.get("max_durability", "无"), got.get("crew", "无")])
	var notice: Label = wm.get("_notice")
	var note_txt := notice.text if notice != null else ""
	_expect(note_txt.find("敌船「快船」并入本队") >= 0 and note_txt.find("海鹘") < 0, "夺船浮字写快船（得「%s」）" % note_txt)
	wm.free()


func _patrol_battle(gm: Node, fleet: Node, patrol: Dictionary) -> void:
	_battle_fleet(fleet)
	var wm := _start(gm, patrol)
	await process_frame
	var foes := _enemies(wm)
	_expect(foes.size() == int(patrol.get("count", 0)), "元军哨船生成 %d 艘" % foes.size())
	if not foes.is_empty():
		var foe: Node = foes[0]
		_expect(str(foe.get("ship_type")) == "sea_falcon" and str(foe.get("ship_name")) == "海鹘",
			"元军哨船 type 不动（sea_falcon / 海鹘），夺来仍按海鹘入列")
		_expect(str(foe.get("sprite_id")) == "yuan_patrol" and str(foe.call("sprite_key")) == "yuan_patrol",
			"WorldMap 把 entry.sprite 传给敌船（sprite_id=yuan_patrol）")
		_expect(_tex_path(foe) == CombatFx.SHIP_SPRITE_ENEMY,
			"缺 ship_yuan_patrol.png → 回落 ship_falcon.png（得 %s）" % _tex_path(foe))
	wm.free()


func _check_lookup() -> void:
	# ship_fu / ship_falcon 按契约也是「ship_<id>.png」：id=fu / falcon 时取到的是它们，证明文件在就用、不回落
	_expect(CombatFx.ship_sprite_path("fu", CombatFx.SHIP_SPRITE_ENEMY) == CombatFx.SHIP_SPRITE_OWN, "文件在：id=fu 取 ship_fu.png 不回落")
	_expect(CombatFx.ship_sprite_path("no_such_ship", CombatFx.SHIP_SPRITE_ENEMY) == CombatFx.SHIP_SPRITE_ENEMY, "文件不在：回落 fallback")
	_expect(CombatFx.ship_sprite_path("", CombatFx.SHIP_SPRITE_OWN) == CombatFx.SHIP_SPRITE_OWN, "id 空：回落 fallback")
	_expect(CombatFx.ship_sprite_path("../icon", CombatFx.SHIP_SPRITE_OWN) == CombatFx.SHIP_SPRITE_OWN, "id 带路径字符：不拼路径，回落")
	var foe: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	foe.set("sprite_id", "fu")
	foe.call("apply_sprite")
	_expect(_tex_path(foe) == CombatFx.SHIP_SPRITE_OWN, "敌船 sprite_id 指向在库的图就换上（得 %s）" % _tex_path(foe))
	foe.set("sprite_id", "")
	foe.set("ship_type", "pirate_boat")
	foe.call("apply_sprite")
	_expect(_tex_path(foe) == CombatFx.SHIP_SPRITE_ENEMY, "敌船清掉 sprite_id 后按 type 取，缺图回落 ship_falcon（得 %s）" % _tex_path(foe))
	foe.free()
	var own: Node = (load("res://scenes/Ship.tscn") as PackedScene).instantiate()
	own.call("apply_type_sprite", "falcon")
	_expect(_tex_path(own) == CombatFx.SHIP_SPRITE_ENEMY, "旗舰 type 指向在库的图就换上（得 %s）" % _tex_path(own))
	for t in ["sampan", "sea_falcon", "pirate_boat", "divine_ship"]:
		own.call("apply_type_sprite", t)
		_expect(_tex_path(own) == CombatFx.SHIP_SPRITE_OWN, "旗舰 %s 缺图回落 ship_fu.png（得 %s）" % [t, _tex_path(own)])
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
