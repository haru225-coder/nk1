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

	_check(not ResourceLoader.exists("res://scenes/Crate.tscn"), "Crate.tscn 已拆除", fails)
	_check(not FileAccess.file_exists("res://scripts/Crate.gd"), "Crate.gd 已拆除", fails)
	_check(not FileAccess.file_exists("res://assets/crate_barrel.png"), "crate 位图已拆除", fails)
	_check(not FileAccess.file_exists("res://assets/seagull.png"), "海鸟位图已拆除", fails)
	_check(not FileAccess.file_exists("res://assets/whale_shadow.png"), "鲸影位图已拆除", fails)
	var wm_src := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_check(wm_src.find("_process_spawns") < 0, "WorldMap 无自由航行刷怪", fails)
	var wm_tscn := FileAccess.get_file_as_string("res://scenes/WorldMap.tscn")
	_check(wm_tscn.find("ocean_tex_1234") < 0 and wm_tscn.find("uid://xnp7vjyfjnp1") >= 0,
		"WorldMap 海洋贴图用导入 UID", fails)
	var chart_src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_check(chart_src.find("style_heading(head)") >= 0 and chart_src.find("UiTheme.panel()") >= 0,
		"海图标题与遭遇弹层走绢本", fails)
	var theme_scr = load("res://scripts/core/UiTheme.gd")
	_check(theme_scr != null, "UiTheme.gd 能编译", fails)
	var dlg := AcceptDialog.new()
	UiTheme.style_dialog(dlg, true)
	_check(dlg.get_theme_stylebox("panel") != null, "UiTheme.style_dialog 给弹窗套绢本面板", fails)
	dlg.free()
	var choice := Button.new()
	UiTheme.style_choice_button(choice)
	var nor := choice.get_theme_stylebox("normal") as StyleBoxFlat
	var hov := choice.get_theme_stylebox("hover") as StyleBoxFlat
	_check(nor != null and hov != null, "挑签按钮有 normal/hover 样式", fails)
	if nor != null and hov != null:
		_check(hov.border_width_left > nor.border_width_left, "挑签 hover 左金杠加宽", fails)
		_check(hov.content_margin_left > nor.content_margin_left, "挑签 hover 正文滑出", fails)
	_check(UiTheme.SIZE_HEAD > UiTheme.SIZE_BODY and UiTheme.SIZE_BODY > UiTheme.SIZE_FOOT,
		"字阶 HEAD > BODY > FOOT", fails)
	choice.free()
	_check(load("res://scripts/Ship.gd") != null, "Ship.gd 能编译", fails)
	_check(load("res://scripts/Cannonball.gd") != null, "Cannonball.gd 能编译", fails)
	_check(load("res://scripts/PirateShip.gd") != null, "PirateShip.gd 能编译", fails)
	var wm_packed = load("res://scenes/WorldMap.tscn")
	_check(wm_packed != null, "WorldMap.tscn 能加载", fails)
	if wm_packed != null:
		var wm_inst = wm_packed.instantiate()
		_check(wm_inst != null and wm_inst.has_signal("battle_finished"), "WorldMap 实例挂上海战脚本", fails)
		if wm_inst != null:
			# --script 没有 autoload 全局名，不能 add_child 走 _ready；只测格式串占位。
			if wm_inst.has_method("_format_left_hud"):
				var hud_txt: String = wm_inst._format_left_hud(
					"敌船 2 艘　存活 2\n", "", "北风", 80, 1, "green", 100, 100, "B/Esc: 弃战逃走"
				)
				_check(
					hud_txt.find("操舵") >= 0 and hud_txt.find("齐射") >= 0 and hud_txt.find("弃战逃走") >= 0,
					"海战 HUD 格式串参数对齐",
					fails,
				)
			else:
				_check(false, "WorldMap._format_left_hud 已定义", fails)
			wm_inst.free()

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
