extends SceneTree
## 战后单子 / 分赃 截图（lane w53-16）：真起 SeaChart 布景、把 _on_battle_result 的札记贴进札记栏，
## 存两张 1280×720 上屏图（before/after 对照对应 _Switches 关 / 开）。存 ${NK1_SHOT_DIR}/wave53-16/
## （脚本里不写死路径；shot_gate 环境 NK1_SHOT_DIR 或 --shot-dir 指路）。
## 用法：DISPLAY=:2 NK1_SHOT_DIR=<qa-shots 根> godot --path . -s res://tools/qa_w53_16_aftermath_shots.gd -- --shot-dir "<qa-shots 根>/wave53-16"
## 修前札记一行「敌船已退。获财货 N 钱…」；修后第一行已写明「敌船二艘，击沉一艘、受降一艘。救起水手八人。」。

const CS := preload("res://scripts/combat/CombatSwitches.gd")

var _dir := ""


func _init() -> void:
	_dir = OS.get_environment("NK1_SHOT_DIR")
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_dir = args[i + 1]
	if _dir == "":
		push_error("NK1_SHOT_DIR / --shot-dir 都缺；不给路径不跑")
		quit(1)
		return
	call_deferred("_run")


func _ready_dir() -> void:
	if DirAccess.dir_exists_absolute(_dir):
		return
	DirAccess.make_dir_recursive_absolute(_dir)


func _run() -> void:
	_ready_dir()
	var fleet: Node = root.get_node("Fleet")
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 40, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": float(d.get("durability", 300)), "max_durability": float(d.get("durability", 300))}])
	fleet.set("morale", 70)
	root.get_node("Crew").set("hired", {})

	var wins := {"player_damage": 12.0, "rescued": 8,
		"fates": [{"type": "sea_falcon", "fate": "sunk", "count": 1},
			{"type": "pirate_boat", "fate": "struck", "count": 1}]}

	var cases := [
		# 关：旧形一行钱数
		["aftermath-win-off", false, false],
		# 开：单子垫了头一行
		["aftermath-win-on", true, true],
	]
	for c in cases:
		var slug: String = c[0]
		CS.set_on("after_action", bool(c[1]))
		CS.set_on("bounty_by_outcome", bool(c[2]))
		var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
		root.add_child(chart)
		for _i in 8:
			await process_frame
		chart.set("remaining_li", 50.0)
		chart.call("_on_battle_result", "win", wins)
		for _i in 2:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s-1280x720.png" % [_dir, slug])
		print("SHOT %s/%s-1280x720.png" % [_dir, slug])
		chart.free()
		await process_frame
	CS.reset()
	quit(0)
