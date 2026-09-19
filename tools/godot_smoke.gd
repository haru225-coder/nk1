extends SceneTree
## 无显示器时的引擎冒烟：确认 autoload 能起来、旗标门槛与结局选择按数据工作。
## godot --headless --path . -s res://tools/godot_smoke.gd


func _init() -> void:
	var fails: Array = []
	_check(GameManager.chapters_data.get("chapters", []).size() == 4, "chapters 四章", fails)
	_check(GameManager.scenes_data.get("scenes", []).size() >= 98, "scenes 不少于 98", fails)
	_check(GameState.chapter == 1, "开局第 1 章", fails)
	_check(not GameState.has_ended(), "开局未了结", fails)
	_check(not GameState.scene_unlocked(GameManager.get_scene_by_id("chapter2_letter")),
		"无旗标时 chapter2_letter 锁住", fails)

	GameState.set_flag("chen_line_open")
	_check(GameState.scene_unlocked(GameManager.get_scene_by_id("chapter2_letter")),
		"chen_line_open 打开 chapter2_letter", fails)

	var hooks: Array = GameState.story_hooks_at("quanzhou")
	_check(hooks.size() >= 1, "泉州酒馆能看到兴化旧事", fails)

	GameState.chapter = 4
	GameState.peak_money = 80000
	GameState.visited_ports = [
		"quanzhou", "xinghua", "fuzhou", "wenzhou", "zhangzhou",
		"penghu", "ryukyu", "mingzhou", "hakata", "jeju",
		"kagoshima", "guangzhou", "champa",
	]
	var prog: Dictionary = GameState.chapter_progress()
	_check(prog.get("final", false) and prog.get("ready", false), "终章条件可达成", fails)
	_check(GameState.pick_ending().get("id", "") == "sea_letter", "旗标选中海口信路", fails)

	var res: Dictionary = GameState.try_resolve_ending()
	_check(res.get("resolved", false) and GameState.ending_id == "sea_letter", "了结写入 ending_id", fails)
	_check(GameState.has_ended(), "has_ended 为真", fails)
	_check(not GameState.try_advance_chapter().get("resolved", false), "了结后不再重复触发", fails)

	var cand_ok := false
	for c in GameManager.crew_data.get("candidates", []):
		if c.get("id") == "jinghai_shami":
			GameState.flags.erase("japan_temple_network")
			_check(not GameState.flag_requirement_met(c), "无寺社旗标雇不到记名沙弥", fails)
			GameState.set_flag("japan_temple_network")
			_check(GameState.flag_requirement_met(c), "有寺社旗标可雇记名沙弥", fails)
			cand_ok = true
	_check(cand_ok, "crew.json 含 jinghai_shami", fails)

	if fails.is_empty():
		print("GODOT SMOKE PASS")
		quit(0)
	else:
		print("GODOT SMOKE FAIL")
		for f in fails:
			print("  ✗ ", f)
		quit(1)


func _check(cond: bool, msg: String, fails: Array) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		fails.append(msg)
