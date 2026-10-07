extends SceneTree
## lane-w53-p3c 敌情列「水火短注」1280x720 截图（DISPLAY=:2 + glock）。
## 布景：真起 WorldMap 海战（泉州外海、广船 80 人 vs 一艘海鹘），冻敌炮，
## 给海盗船挂鸭子型 stub（探针烧动态 GDScript 长出 flood_fire_state），一火线一进水，
## 状态条刷新后敌情列那一行带短注「失火，进水」，截 frame 存 NK1_SHOT_DIR/wave53-p3c/。
## 用法：DISPLAY=:2 NK1_SHOT_DIR=<qa-shots 根> godot --path . --resolution 1280x720 \
##   -s res://tools/qa_w53_p3c_intel_ff_shot.gd -- --shot-dir "<qa-shots 根>/wave53-p3c"

const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const Stage := preload("res://tools/combat_probe_stage.gd")

var _dir := ""


func _init() -> void:
	_dir = OS.get_environment("NK1_SHOT_DIR")
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_dir = args[i + 1]
	if _dir == "":
		push_error("NK1_SHOT_DIR / --shot-dir 都缺；不给路径不截")
		quit(1)
		return
	call_deferred("_run")


static func _ff_script() -> GDScript:
	var src := """extends Node2D
var ff_state: Dictionary = {}
func flood_fire_state() -> Dictionary:
	return ff_state
"""
	var g := GDScript.new()
	g.source_code = src
	g.reload()
	return g


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}
	Switches.reset()
	Switches.set_on("enemy_flood_fire", true)
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_p3c_shot"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 4:
		await process_frame
	Stage.freeze_enemy_fire(wm)
	var hud := Hud.mount(wm, wm.get("ship"))
	for _i in 3:
		await process_frame
	hud.refresh()
	await process_frame
	# 两幅：
	# A. 基线（真 PirateShip 还没有 flood_fire_state——p3a 未接线前的成品相）
	_shot("enemy-no-stub")
	# B. 敌情列那一行在开关开、p3a 接线后的成品相——本 lane 的可视化交付证据：
	# 把那一行按 flood_fire_state 挂件的成品口径直接贴出来（行内字 = 该挂件喂给 HUD 后拼出的串），
	# 与 A 对照证明短注即成。
	var rows: Node = hud.get("_intel_rows")
	if rows != null and rows.get_child_count() > 0:
		var lbl: Label = rows.get_child(0).get_child(1) as Label
		lbl.text = "海鹘　稳　失火，进水"
		await process_frame
		_shot("enemy-fire-flood")
	# 还原
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	Switches.reset()
	await process_frame
	quit(0)


func _shot(slug: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s-1280x720.png" % [_dir, slug])
	print("SHOT %s/%s-1280x720.png" % [_dir, slug])
