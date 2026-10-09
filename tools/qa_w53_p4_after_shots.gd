extends SceneTree
## lane-w53-p4-after 战后取舍截图：真起 SeaChart 布景、造一场胜局（夺一降一 + 落水可救），挂出
## 「战后收拾」小卡（1280×720）与卡按下「收拾停当」之后的札记一行。存 ${NK1_SHOT_DIR}/wave53-p4/。
## 修前（after_action 开关关）札记一行「获财货 N 钱…」；修后（waa_* 开关开）札记同一句照旧，
## 屏底浮出三到五行小选择（押船 / 救人 / 俘虏 / 索赎 / 追击——本局有夺有降，无遁走故追击不挂）。
## 用法：DISPLAY=:2 NK1_SHOT_DIR=<qa-shots 根> godot --path . -s res://tools/qa_w53_p4_after_shots.gd -- --shot-dir "<qa-shots 根>/wave53-p4"

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
	var pd: Dictionary = fleet.call("ship_def", "pirate_boat")
	fleet.set("ships", [
		{"type": "fu_ship_medium", "name": "旗舰", "crew": 40, "sail_level": 1, "armor_level": 1,
			"cargo": {}, "durability": float(d.get("durability", 300)),
			"max_durability": float(d.get("durability", 300))},
		{"type": "pirate_boat", "name": "快船", "crew": 15, "sail_level": 1, "armor_level": 1,
			"cargo": {}, "durability": float(pd.get("durability", 120)),
			"max_durability": float(pd.get("durability", 120))},
	])
	fleet.set("morale", 70)
	root.get_node("Crew").set("hired", {})

	# 夺一（pirate_boat）+ 降一（sea_falcon）+ 击沉一（sea_falcon）的胜局——可押两艘、可救一船落水、有俘虏可索赎
	var wins := {"player_damage": 14.0, "boarded": true,
		"fates": [{"type": "pirate_boat", "fate": "boarded", "count": 1},
			{"type": "sea_falcon", "fate": "struck", "count": 1},
			{"type": "sea_falcon", "fate": "sunk", "count": 1}]}

	var cases := [
		# 关（after_action 一三期开关关）：旧形一行钱数，无卡
		["aftermath-after-off", false],
		# 开：札记照旧，屏底浮出战后收拾卡
		["aftermath-after-on", true],
	]
	for c in cases:
		var slug: String = c[0]
		CS.set_on("after_action", bool(c[1]))
		var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
		root.add_child(chart)
		for _i in 8:
			await process_frame
		chart.set("remaining_li", 50.0)
		chart.call("_on_battle_result", "win", wins)
		# 卡片挂出后等它量完尺寸落位
		for _i in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s-1280x720.png" % [_dir, slug])
		print("SHOT %s/%s-1280x720.png" % [_dir, slug])
		chart.free()
		await process_frame
	CS.reset()
	quit(0)
