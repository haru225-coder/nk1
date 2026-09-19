extends SceneTree
## 无显示器时的引擎冒烟：确认 autoload 能起来、旗标门槛与结局选择按数据工作。
## --script 没有 autoload 全局名，必须走 /root。
## godot --headless --path . -s res://tools/godot_smoke.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fails: Array = []
	var gm: Node = root.get_node_or_null("GameManager")
	var gs: Node = root.get_node_or_null("GameState")
	_check(gm != null, "autoload GameManager 在 /root", fails)
	_check(gs != null, "autoload GameState 在 /root", fails)
	if gm == null or gs == null:
		_finish(fails)
		return

	_check(gm.chapters_data.get("chapters", []).size() == 4, "chapters 四章", fails)
	_check(gm.scenes_data.get("scenes", []).size() >= 98, "scenes 不少于 98", fails)
	_check(gs.chapter == 1, "开局第 1 章", fails)
	_check(not gs.has_ended(), "开局未了结", fails)
	_check(not gs.scene_unlocked(gm.get_scene_by_id("chapter2_letter")),
		"无旗标时 chapter2_letter 锁住", fails)

	gs.set_flag("chen_line_open")
	_check(gs.scene_unlocked(gm.get_scene_by_id("chapter2_letter")),
		"chen_line_open 打开 chapter2_letter", fails)

	var hooks: Array = gs.story_hooks_at("quanzhou")
	_check(hooks.size() >= 1, "泉州酒馆能看到兴化旧事", fails)

	gs.chapter = 4
	gs.peak_money = 80000
	gs.visited_ports = [
		"quanzhou", "xinghua", "fuzhou", "wenzhou", "zhangzhou",
		"penghu", "ryukyu", "mingzhou", "hakata", "jeju",
		"kagoshima", "guangzhou", "champa",
	]
	var prog: Dictionary = gs.chapter_progress()
	_check(prog.get("final", false) and prog.get("ready", false), "终章条件可达成", fails)
	_check(gs.pick_ending().get("id", "") == "sea_letter", "旗标选中海口信路", fails)

	var res: Dictionary = gs.try_resolve_ending()
	_check(res.get("resolved", false) and gs.ending_id == "sea_letter", "了结写入 ending_id", fails)
	_check(gs.has_ended(), "has_ended 为真", fails)
	_check(not gs.try_advance_chapter().get("resolved", false), "了结后不再重复触发", fails)

	var cand_ok := false
	for c in gm.crew_data.get("candidates", []):
		if c.get("id") == "jinghai_shami":
			gs.flags.erase("japan_temple_network")
			_check(not gs.flag_requirement_met(c), "无寺社旗标雇不到记名沙弥", fails)
			gs.set_flag("japan_temple_network")
			_check(gs.flag_requirement_met(c), "有寺社旗标可雇记名沙弥", fails)
			cand_ok = true
	_check(cand_ok, "crew.json 含 jinghai_shami", fails)

	_finish(fails)


func _check(cond: bool, msg: String, fails: Array) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		fails.append(msg)


func _finish(fails: Array) -> void:
	if fails.is_empty():
		print("GODOT SMOKE PASS")
		quit(0)
	else:
		print("GODOT SMOKE FAIL")
		for f in fails:
			print("  ✗ ", f)
		quit(1)
