extends SceneTree
## lane w20-b1 人工截图：海战战术场岸线层——zoom 远 / 中 / 近三档，before（main 原画）/ after（岸线层开）。
## 只用于 lane 收尾人工验图，不入门禁；截图落 /workspace/nk1-qa-shots/wave20-b1/。
## 用法：DISPLAY=:2 godot --path . -s res://tools/tactical_coast_screens.gd -- --before   # 从 main 原画跑 before
##       DISPLAY=:2 godot --path . -s res://tools/tactical_coast_screens.gd -- --after    # 从改过树跑 after

const ShotGateRoot := preload("res://tools/shot_gate.gd")
const OUT := ShotGateRoot.out_dir("wave20-b1")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
var _side := "after"


func _init() -> void:
	for a in OS.get_cmdline_args():
		if a == "--before":
			_side = "before"


func _initialize() -> void:
	var gm: Node = root.get_node("GameManager")
	gm.load_data()
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var gm: Node = root.get_node("GameManager")
	gm.set("pending_battle", {
		"battle": true,
		"enemy": [{"type": "pirate_boat", "count": 1}],
		"power": 60.0,
		"player_power": 300.0,
		"sea_name": "泉州外海",
		"sea_seed": 7,
	})
	var sc := (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	# 冻敌炮免得抹黑
	var frozen := CombatStage.freeze_enemy_fire(sc)
	print("frozen guns:", frozen)
	await process_frame
	var cam: Camera2D = sc.get_node_or_null("Ship/Camera2D")
	var ship: Node2D = sc.get_node_or_null("Ship")
	if ship != null:
		ship.position = Vector2(150, 1000)
	if cam != null:
		cam.position = Vector2(150, 1000)
	var zooms: Array = [0.42, 0.5, 1.5]
	var names: Array = ["sail_full", "combat_rest", "close"]
	for i in zooms.size():
		if cam != null:
			cam.zoom = Vector2(float(zooms[i]), float(zooms[i]))
			cam.position = Vector2(150, 1000)
		for _f in 5:
			await process_frame
		var img := root.get_texture().get_image()
		var path := "%s/%s_tactical_coast_%s.png" % [OUT, _side, names[i]]
		img.save_png(path)
		var layer: CanvasItem = sc.get_node_or_null("CoastlineLayer")
		print("saved %s (zoom %.2f, layer %s, alive=%s)" % [path, float(zooms[i]),
			("off" if layer == null else ("ON·n=%d" % int(layer.get_meta("coast_rings", -1)))),
			str(is_instance_valid(sc))])
	CombatStage.teardown(self, sc, gm)
	await process_frame
	quit(0)
