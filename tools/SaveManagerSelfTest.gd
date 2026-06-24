extends Node

func _ready() -> void:
	var ok := true
	GameState.fame = 42
	GameState.navigation.last_port = "quanzhou"
	LedgerSystem.from_save_dict({"balance": 2500})
	CargoSystem.from_save_dict({"cargo": {"silk": 5}, "total": 5})
	SaveManager.set_current_scene_id("port_quanzhou")

	ok = ok and SaveManager.save_game(0)
	var path := "user://nk1_save_0.json"
	ok = ok and FileAccess.file_exists(path)

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and raw.get("save_version") == 1
	ok = ok and raw.has("timestamp") and str(raw["timestamp"]) != ""
	ok = ok and raw.get("current_scene_id") == "port_quanzhou"
	ok = ok and raw.has("game_state") and raw.has("ledger") and raw.has("cargo")
	ok = ok and raw["game_state"].has("fleet")
	ok = ok and int(raw["ledger"].get("balance", 0)) == 2500

	GameState.fame = 0
	LedgerSystem.from_save_dict({"balance": 0})
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})
	ok = ok and SaveManager.load_game(0)
	ok = ok and GameState.fame == 42
	ok = ok and LedgerSystem.get_balance() == 2500
	ok = ok and CargoSystem.get_amount("silk") == 5
	ok = ok and SaveManager.has_save(0)

	var info0: Dictionary = SaveManager.get_save_info(0)
	ok = ok and info0.get("exists", false)
	ok = ok and info0.get("balance", -1) == 2500
	ok = ok and info0.get("current_location_name", "") == "泉州"

	# 多槽位：slot 1 存档 + get_all_saves_info
	SaveManager.set_current_scene_id("port_guangzhou")
	GameState.navigation.last_port = "guangzhou"
	LedgerSystem.from_save_dict({"balance": 9999})
	ok = ok and SaveManager.save_game(1)
	ok = ok and SaveManager.has_save(1)

	var all_saves: Array[Dictionary] = SaveManager.get_all_saves_info()
	ok = ok and all_saves.size() == 4
	ok = ok and all_saves[0].get("exists", false)
	ok = ok and all_saves[1].get("exists", false)
	ok = ok and not all_saves[2].get("exists", true)
	ok = ok and all_saves[1].get("current_location_name", "") != ""

	# 删除 slot 1
	ok = ok and SaveManager.delete_save(1)
	ok = ok and not SaveManager.has_save(1)
	all_saves = SaveManager.get_all_saves_info()
	ok = ok and not all_saves[1].get("exists", true)

	# 模拟标题页：仅 load_game(0)，靠 load_completed 跳转
	var load_hits: Array = [0]
	var load_scene: Array = [""]
	var on_load := func(_slot: int, success: bool, data: Dictionary) -> void:
		if success:
			load_hits[0] += 1
			load_scene[0] = data.get("current_scene_id", "")
	SaveManager.load_completed.connect(on_load)
	var reload_ok := SaveManager.load_game(0)
	ok = ok and reload_ok
	ok = ok and load_hits[0] == 1
	ok = ok and load_scene[0] == "port_quanzhou"
	SaveManager.load_completed.disconnect(on_load)

	# quick_save 仍写 slot 0
	ok = ok and SaveManager.quick_save()
	ok = ok and FileAccess.file_exists("user://nk1_save_0.json")

	print("[SaveManagerSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)