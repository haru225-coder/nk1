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
	_check(wm_tscn.find("按 Enter 停靠") < 0, "海战港名不再写停靠教程", fails)
	var chart_src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_check(chart_src.find("style_heading(head)") >= 0 and chart_src.find("UiTheme.panel()") >= 0,
		"海图标题与遭遇弹层走绢本", fails)
	_check(chart_src.find("CenterContainer") >= 0 and chart_src.find("Vector2(360, 200)") < 0,
		"海图遭遇弹层居中", fails)
	_check(chart_src.find("func _draw_ink_label") >= 0
		and chart_src.find("draw_string(font, v + Vector2(8, 5)") < 0,
		"海图港名走墨底签", fails)
	_check(chart_src.find("func _draw_chart_leaf") >= 0
		and chart_src.find("Color(0.11, 0.08, 0.05, 0.55)") < 0,
		"海图中栏是绢纸", fails)
	_check(chart_src.find("event_actions = VBoxContainer") >= 0
		and chart_src.find("style_choice_button(b)") >= 0,
		"海图遭遇选项走竖排挑签", fails)
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

	_check(gm.titles_data.get("ranks", []).size() == 5, "titles 五档职衔", fails)
	_check(gs.title_name() == "籍外散商", "开局籍外散商", fails)
	var promo: Dictionary = gs.add_fame(10)
	_check(promo.get("promoted", false) and str(gs.title_name()) == "在册舶牙",
		"名声 10 升在册舶牙", fails)
	_check(int(gs.title_loan_bonus()) == 500, "舶牙赊贷 +500", fails)
	_check(int(gs.borrow_limit()) == int(gs.DEBT_CEILING) + 500, "赊贷上限含职衔", fails)
	var eco: Node = root.get_node_or_null("Economy")
	_check(eco != null, "autoload Economy 在 /root", fails)
	if eco != null:
		var invs = eco.get("investments")
		_check(typeof(invs) == TYPE_DICTIONARY, "Economy.investments 是字典", fails)
		if eco.has_method("invest") and eco.has_method("investment_level"):
			var money0: int = int(gs.money)
			var inv0: Dictionary = eco.invest("quanzhou")
			_check(inv0.get("ok", false) and int(eco.investment_level("quanzhou")) == 1,
				"泉州可修一等埠", fails)
			_check(int(gs.money) == money0 - 800, "一等修埠扣 800 钱", fails)
			var saved: Dictionary = eco.to_dict()
			_check(saved.has("investments") and int(saved["investments"].get("quanzhou", 0)) == 1,
				"Economy 存档含修埠", fails)
	if gm.has_method("load_texture"):
		var yamen_tex: Texture2D = gm.load_texture("res://assets/icon_yamen.png")
		_check(yamen_tex != null, "icon_yamen 按文件头能加载（不依赖 valid=false 的 .import）", fails)
		var academy_tex: Texture2D = gm.load_texture("res://assets/icon_academy.png")
		_check(academy_tex != null, "icon_academy（JPEG 冒充 png）按文件头能加载", fails)
		_check(gm.load_texture("res://assets/icon_guild.png") != null, "icon_guild 按文件头能加载", fails)
		_check(gm.load_texture("res://assets/icon_exam.png") != null, "icon_exam 按文件头能加载", fails)
		_check(gm.load_texture("res://assets/icon_residence.png") != null, "icon_residence 按文件头能加载", fails)
		_check(gm.load_texture("res://assets/icon_temple.png") != null, "icon_temple 按文件头能加载", fails)
	if gm.has_method("discoveries_near"):
		var near: Array = gm.discoveries_near("fuzhou")
		var near_ids: Array = []
		for d in near:
			near_ids.append(str(d.get("id", "")))
		_check(near_ids.has("beacon_ruin"), "福州近侧含废烽堠", fails)
	else:
		_check(false, "GameManager.discoveries_near 已定义", fails)
	var fame_before_look: int = int(gs.fame)
	_check(gs.record_discovery("beacon_ruin"), "上陆勘见把废烽堠记入册", fails)
	_check(int(gs.fame) == fame_before_look, "勘见不给名声", fails)
	_check("beacon_ruin" in gs.discoveries_found, "废烽堠在 discoveries_found", fails)
	var rpt: Dictionary = gs.report_discovery("beacon_ruin")
	_check(not rpt.is_empty() and int(rpt.get("fame", 0)) > 0, "市舶司呈报才给名声", fails)
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check(main_src.find("ChapterSheet") >= 0 and main_src.find("AcceptDialog.new()") < 0,
		"升章了结走居中册页，主场景不再弹系统对话框", fails)
	_check(main_src.find("OptionButton.new()") < 0 and main_src.find("_select_market_ship") >= 0,
		"牙行选船走账条小钮，不再用系统下拉", fails)
	_check(main_src.find("func _skill_rank") >= 0 and main_src.find("★") < 0,
		"职事品级写成初习/谙熟/老练，不再用星号", fails)
	_check(main_src.find("func _fit_rank") >= 0 and main_src.find("帆Lv") < 0
		and main_src.find("Lv%d") < 0,
		"船壳改装写成一等二等三等", fails)
	_check(main_src.find("func _interior_title") >= 0 and main_src.find("未命名设施") < 0,
		"序章内页改写成港名去处，港卡不写未命名设施", fails)
	_check(main_src.find("请选择") < 0 and main_src.find("区域施工中") < 0,
		"调查页用决断，缺页不再写施工中", fails)
	var main_tscn := FileAccess.get_file_as_string("res://scenes/Main.tscn")
	_check(main_tscn.find("副标题") < 0 and main_tscn.find("地点标题") < 0
		and main_tscn.find("环境描述文本") < 0 and main_tscn.find("NPC Dialog") < 0
		and main_tscn.find("NPC Name") < 0 and main_tscn.find("情报与状态") < 0
		and main_tscn.find("港口名称") < 0,
		"开场场景不再写原型占位", fails)
	var inv_at := main_tscn.find("[node name=\"InvestigationMode\"")
	var inv_end := main_tscn.find("\n[node ", inv_at + 10)
	var inv_block := main_tscn.substr(inv_at, inv_end - inv_at) if inv_at >= 0 and inv_end > inv_at else ""
	_check(inv_block.find("visible = false") >= 0, "调查页默认收起，开场不闪占位", fails)
	var left_at := main_tscn.find("[node name=\"LeftPanel\"")
	var left_end := main_tscn.find("\n[node ", left_at + 10)
	var left_block := main_tscn.substr(left_at, left_end - left_at) if left_at >= 0 and left_end > left_at else ""
	_check(left_block.find("visible = false") >= 0, "船籍簿默认收起，开场不闪旧栏", fails)
	var port_src := FileAccess.get_file_as_string("res://scripts/PortZone.gd")
	_check(port_src.find("name_lbl.text = port_name") >= 0, "港区名牌写港口名", fails)
	_check(main_src.find("city_inn") >= 0 and main_src.find("REMAPPED_FACILITIES") >= 0,
		"旅店列入港卡改写", fails)
	_check(main_src.find("PROLOGUE_ONLY_FACILITIES") >= 0,
		"序章设施与游戏港切开", fails)
	_check(main_src.find("visited_ports") >= 0 and main_src.find('current_scene_id == "xinghua"') >= 0,
		"兴化回访看是否已到泉州", fails)
	var gen_i := main_src.find("const GENERIC_FACILITIES")
	var gen_j := main_src.find("]", gen_i) if gen_i >= 0 else -1
	var gen_body := main_src.substr(gen_i, gen_j - gen_i) if gen_i >= 0 and gen_j > gen_i else ""
	_check(gen_body.find("city_guild") >= 0 and gen_body.find("city_exam") >= 0
		and gen_body.find("city_residence") >= 0 and gen_body.find("city_temple") >= 0,
		"通用港含行会/贡院/住宅/寺观", fails)
	_check(main_src.find('begins_with("city_")') >= 0,
		"load_scene 跳过 city_ 前缀", fails)
	_check(main_src.find("func _setup_guild") >= 0 and main_src.find("func _setup_exam") >= 0
		and main_src.find("func _setup_residence") >= 0 and main_src.find("func _setup_temple") >= 0,
		"行会/贡院/住宅/寺观有动态页", fails)
	_check(main_src.find("HOME_RATE") >= 0 and main_src.find("INN_RATE") >= 0,
		"住处与旅店房价分开", fails)
	var exam_i := main_src.find("func _on_exam_copy")
	var exam_j := main_src.find("\nfunc ", exam_i + 1) if exam_i >= 0 else -1
	var exam_body := main_src.substr(exam_i, exam_j - exam_i) if exam_i >= 0 and exam_j > exam_i else ""
	_check(exam_body.find("scholar_tendency") >= 0 and exam_body.find("add_fame") < 0,
		"贡院誊录只加学者倾向、不给名声", fails)
	var look_i := main_src.find("func _on_temple_look")
	var look_j := main_src.find("\nfunc ", look_i + 1) if look_i >= 0 else -1
	var look_body := main_src.substr(look_i, look_j - look_i) if look_i >= 0 and look_j > look_i else ""
	_check(look_body.find("record_discovery") >= 0 and look_body.find("add_fame") < 0
		and look_body.find("report_discovery") < 0,
		"寺观细看只记入册、不给名声", fails)
	var rub_i := main_src.find("func _on_temple_rub")
	var rub_j := main_src.find("\nfunc ", rub_i + 1) if rub_i >= 0 else -1
	var rub_body := main_src.substr(rub_i, rub_j - rub_i) if rub_i >= 0 and rub_j > rub_i else ""
	_check(rub_body.find("add_ledger_note") >= 0 and rub_body.find("add_fame") < 0
		and rub_body.find("report_discovery") < 0,
		"寺观拓碑只写入边记、不给名声", fails)
	var fame_before_rub: int = int(gs.fame)
	var notes0: int = gs.ledger_notes.size()
	gs.add_ledger_note("拓「废烽堠」：旧时守海的烽堠，如今无人执守，却仍是夜航辨岸的好记认。")
	_check(gs.ledger_notes.size() == notes0 + 1, "拓碑边记可写入 ledger_notes", fails)
	_check(int(gs.fame) == fame_before_rub, "写入边记不给名声", fails)
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
