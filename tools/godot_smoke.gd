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
	_check(wm_tscn.find("[node name=\"TideBar\"") >= 0
		and wm_tscn.find("[node name=\"LeftPanel\"") < 0
		and wm_tscn.find("Vector2(320, 0)") < 0
		and wm_src.find("TideBar/Margin/Row/VBox/FleetStatus") >= 0
		and wm_src.find("RightPanel/Margin/VBox/FleetStatus") < 0,
		"海战左右栏收成顶匾，舰队天气仍在匾内竖排", fails)
	_check(wm_tscn.find("ocean_tex_1234") < 0 and wm_tscn.find("uid://xnp7vjyfjnp1") >= 0,
		"WorldMap 海洋贴图用导入 UID", fails)
	_check(wm_tscn.find("按 Enter 停靠") < 0, "海战港名不再写停靠教程", fails)
	var chart_src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_check(chart_src.find("style_heading(head)") >= 0 and chart_src.find("UiTheme.panel()") >= 0,
		"海图标题与遭遇弹层走绢本", fails)
	_check(chart_src.find("CenterContainer") >= 0 and chart_src.find("Vector2(360, 200)") < 0,
		"海图遭遇弹层居中", fails)
	# 2026-09-25 海图重制：港名与底图移到 scripts/chart/MapView.gd（朱砂方框蛤粉签 / 舆图纹理经绢本着色器）
	var mapview_src := FileAccess.get_file_as_string("res://scripts/chart/MapView.gd")
	_check(mapview_src.find("COL_SHELL") >= 0 and mapview_src.find("draw_rect(box") >= 0
		and chart_src.find("draw_string(font, v + Vector2(8, 5)") < 0,
		"海图港名走方框蛤粉签", fails)
	_check(mapview_src.find("ChartTerrain.gdshader") >= 0 and mapview_src.find("terrain_4096.png") >= 0
		and chart_src.find("Color(0.11, 0.08, 0.05, 0.55)") < 0,
		"海图底图是绢本着色的舆图纹理", fails)
	_check(chart_src.find("event_actions = VBoxContainer") >= 0
		and chart_src.find("style_choice_button(b)") >= 0,
		"海图遭遇选项走竖排挑签", fails)
	_check(chart_src.find("船况") >= 0
		and chart_src.find("func _mount_condition") >= 0
		and chart_src.find("Vector2(260, 0)") < 0
		and chart_src.find("Vector2(300, 0)") < 0,
		"海图左右栏收成顶匾，船况点开才占画面", fails)
	var meet_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	var meet_at := meet_src.find("func _show_npc_mode")
	var meet_end := meet_src.find("\nfunc ", meet_at + 1)
	var meet_body := meet_src.substr(meet_at, meet_end - meet_at) if meet_at >= 0 and meet_end > meet_at else ""
	_check(meet_body.find("_begin_benches(npc_actions)") >= 0
		and meet_body.find("SIZE_SHRINK_CENTER") >= 0,
		"见面行情走工席，离开不再拉满宽", fails)
	var theme_scr = load("res://scripts/core/UiTheme.gd")
	_check(theme_scr != null, "UiTheme.gd 能编译", fails)
	var dlg := AcceptDialog.new()
	UiTheme.style_dialog(dlg, true)
	_check(dlg.get_theme_stylebox("panel") != null, "UiTheme.style_dialog 给弹窗套绢本面板", fails)
	_check(UiTheme.INK.b > UiTheme.INK.r and UiTheme.INK.g > UiTheme.INK.r
		and UiTheme.TIDE.g > UiTheme.TIDE.r and UiTheme.SEAL.r > UiTheme.SEAL.b,
		"面板是夜潮青，潮光作线，主钮是珊瑚", fails)
	var facility := UiTheme.card()
	var picked := UiTheme.heading_card(true)
	var idle := UiTheme.heading_card(false)
	_check(facility.corner_radius_top_left == 16 and picked.corner_radius_top_left == 16
		and picked.border_color.g > picked.border_color.r
		and idle.border_color.b > idle.border_color.r,
		"港卡与航向牌是潮玻璃，选中边是潮光", fails)
	var ch_keep: int = gs.chapter
	var vis_keep: Array = gs.visited_ports.duplicate()
	var end_keep: String = str(gs.ending_id)
	var salt_keep: int = int(gs.draft_salt)
	gs.chapter = 1
	gs.visited_ports = ["quanzhou"]
	gs.ending_id = ""
	gs.draft_salt = 0
	var hand: PackedStringArray = HeadingDraft.deal("quanzhou", 0)
	var hand_next: PackedStringArray = HeadingDraft.deal("quanzhou", 1)
	_check(hand.size() >= 1 and hand.size() <= 3 and hand[0] == "ryukyu",
		"泉州开局这一手最多三向，南岛海道北口占第一席", fails)
	_check(hand.size() >= 2 and hand_next.size() >= 2 and hand[1] != hand_next[1],
		"盐位一转，非必须席换港", fails)
	gs.chapter = ch_keep
	gs.visited_ports = vis_keep
	gs.ending_id = end_keep
	gs.draft_salt = salt_keep
	var shore_facs: Array = [
		{"id": "city_shipyard"},
		{"id": "city_guild"},
		{"id": "city_tavern"},
		{"id": "city_market"},
		{"id": "city_inn"},
		{"id": "city_exam"},
		{"id": "city_residence"},
		{"id": "city_temple"},
		{"id": "city_yamen"},
	]
	var shore0: PackedStringArray = ShoreDraft.deal(shore_facs, 0, false)
	var shore1: PackedStringArray = ShoreDraft.deal(shore_facs, 1, false)
	var shore_pin: PackedStringArray = ShoreDraft.deal(shore_facs, 0, true)
	_check(shore0.size() == 3 and shore0[0] == "city_market" and shore0[1] != shore1[1],
		"泉州岸上最多三处，牙行占第一席，盐位一转第二席换门", fails)
	_check(shore_pin.size() == 3 and shore_pin[1] == "city_shipyard",
		"船开不出去时船屋占第二席", fails)
	var shore_seen := {}
	for salt_i in 8:
		for door_id in ShoreDraft.deal(shore_facs, salt_i, false):
			shore_seen[door_id] = true
	_check(shore_seen.size() == 9, "盐位转一圈，九处都会开门", fails)
	var door_box := UiTheme.shore_door()
	_check(door_box.corner_radius_top_left == 16 and door_box.border_color.g > door_box.border_color.r,
		"岸门是潮光边的潮玻璃", fails)
	var broker_goods: Array = [
		{"id": "a", "role": "origin", "buy": 10},
		{"id": "b", "role": "origin", "buy": 30},
		{"id": "c", "role": "normal", "buy": 5},
		{"id": "d", "role": "consumer", "buy": 40},
		{"id": "e", "role": "normal", "buy": 20},
	]
	var slip0: PackedStringArray = BrokerSlip.deal(broker_goods, 0, "")
	var slip1: PackedStringArray = BrokerSlip.deal(broker_goods, 1, "")
	var slip_held: PackedStringArray = BrokerSlip.deal(broker_goods, 0, "d")
	_check(slip0.size() == 3 and slip0[0] == "a" and slip0[1] != slip1[1],
		"柜上三样，最便宜的土产占第一席，盐位一转第二席换货", fails)
	_check(slip_held.size() == 3 and slip_held[0] == "d" and slip_held[1] == "a",
		"舱里有货占第一席，土产仍占下一席", fails)
	var slip_seen := {}
	for broker_salt_i in 4:
		for slip_id in BrokerSlip.deal(broker_goods, broker_salt_i, ""):
			slip_seen[slip_id] = true
	_check(slip_seen.size() == 5, "盐位转一圈，五样货都会上柜", fails)
	var yard_offers: Array = [
		{"id": "sampan", "unlock": "ch1"},
		{"id": "keel_boat", "unlock": "ch1"},
		{"id": "fu_ship_medium", "unlock": "ch1"},
		{"id": "canton_ship", "unlock": "ch2"},
	]
	var yard_ch1 := PackedStringArray(["ch1"])
	var yard_sale: PackedStringArray = DrydockBerth.sale_ids(yard_offers, yard_ch1)
	_check(yard_sale.size() == 3 and yard_sale[0] == "sampan" and yard_sale[2] == "fu_ship_medium",
		"第一章坞外待售三艘，广船不在", fails)
	var yard_ch2 := PackedStringArray(["ch1", "ch2"])
	var yard_sale2: PackedStringArray = DrydockBerth.sale_ids(yard_offers, yard_ch2)
	_check(yard_sale2.size() == 4 and yard_sale2[3] == "canton_ship",
		"第二章广船也在坞外", fails)
	_check(DrydockBerth.berth_index(1, 5) == 0 and DrydockBerth.berth_index(3, 5) == 2,
		"坞位夹回船队里", fails)
	var yard_others := DrydockBerth.other_hulls(3, 0)
	_check(yard_others.size() == 2 and yard_others[0] == 1 and yard_others[1] == 2,
		"坞上这一艘不进换船", fails)
	_check(UiTheme.plain_log("【钱不够】牙人摇头。") == "牙人摇头。", "日志去掉方括号标签", fails)
	_check(UiTheme.plain_log("买入瓷器 ×1。") == "买入瓷器 ×1。", "普通日志原样保留", fails)
	_check(UiTheme.plain_log("[color=#aabbcc]【欠饷】已拖欠。[/color]") == "[color=#aabbcc]已拖欠。[/color]",
		"色标里的方括号标签也去掉", fails)
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
	var accent_btn := Button.new()
	UiTheme.style_button(accent_btn, true)
	var chip := Button.new()
	UiTheme.style_chip(chip, true)
	_check(accent_btn.get_theme_color("font_color") == UiTheme.INK_SOLID
		and accent_btn.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
		and accent_btn.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
		"珊瑚主钮聚焦和按下仍是深字", fails)
	_check(chip.get_theme_color("font_color") == UiTheme.INK_SOLID
		and chip.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
		and chip.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
		"珊瑚小钮聚焦和按下仍是深字", fails)
	accent_btn.free()
	chip.free()

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
	var saveload_src := FileAccess.get_file_as_string("res://scripts/core/SaveLoad.gd")
	_check(saveload_src.find("未记") >= 0 and saveload_src.find("卷页损了") >= 0
		and saveload_src.find("未题") >= 0
		and saveload_src.find("（空）") < 0 and saveload_src.find("（损坏）") < 0
		and saveload_src.find("（无标签）") < 0
		and main_src.find("存档 / 读档") < 0 and saveload_src.find("%d 钱") >= 0,
		"航海日志空卷写成未记", fails)
	_check(str(root.get_node("SaveLoad").call("save_label", 9)) == "未记", "空卷读出来是未记", fails)
	var save_at := main_src.find("func _show_save_dialog")
	var save_end := main_src.find("\nfunc ", save_at + 1)
	var save_body := main_src.substr(save_at, save_end - save_at) if save_at >= 0 and save_end > save_at else ""
	_check(save_body.find("SaveSheet") >= 0 and save_body.find("_begin_benches(col)") >= 0
		and save_body.find("SIZE_SHRINK_CENTER") >= 0
		and save_body.find("Vector2(520, 0)") < 0
		and save_body.find("style_choice_button(close)") < 0,
		"航海日志三卷走工席，合上不再拉满宽", fails)
	_check(main_src.find("OptionButton.new()") < 0 and main_src.find("_select_market_ship") >= 0,
		"牙行选船走账条小钮，不再用系统下拉", fails)
	_check(main_src.find("买%d") < 0 and main_src.find("卖%d") < 0
		and main_src.find("只购得 %d。") >= 0 and main_src.find("钱（") < 0,
		"牙行小钮与买卖日志留出字距", fails)
	_check(main_src.find("塞　50") >= 0 and main_src.find("关注　减 15") >= 0
		and main_src.find("塞 50") < 0 and main_src.find("关注减 15") < 0
		and main_src.find("UiTheme.plain_log(_gather_price_intel") >= 0,
		"见面册疏通留出字距，行情去掉方括号", fails)
	_check(main_src.find("尚无人留意") >= 0 and main_src.find("偶有闲话传出") >= 0
		and main_src.find("起了疑心") >= 0 and main_src.find("暗桩已盯死，出港必查") >= 0
		and main_src.find("（尚无人留意）") < 0 and main_src.find("（偶有闲话传出）") < 0
		and main_src.find("（蒲氏起了疑心）") < 0 and main_src.find("（暗桩已盯死，出港必查）") < 0,
		"市舶司关注四档去掉括号", fails)
	_check(main_src.find("（缺 %d 人）") < 0 and main_src.find("缺 %d 人") >= 0
		and main_src.find("（%d/%d）") < 0 and main_src.find("水手 %d / %d") >= 0
		and main_src.find("水手 %d/%d") < 0 and main_src.find("%d/%d 料") < 0
		and main_src.find("水手不足　%s") >= 0 and main_src.find("水手不足：") < 0,
		"缺员与分船账条写成已有 / 所需，出海拦阻去掉冒号", fails)
	var cal_src := FileAccess.get_file_as_string("res://scripts/core/Calendar.gd")
	_check(cal_src.find("东北季风　利南下") >= 0 and cal_src.find("西南季风　利北上") >= 0
		and cal_src.find("季风转换期・风微而多变") >= 0
		and cal_src.find("（利南下）") < 0 and cal_src.find("（利北上）") < 0
		and cal_src.find("（风微而多变）") < 0
		and main_src.find("（五至八月）") < 0 and main_src.find("（十月至次年二月）") < 0,
		"风信写成短句", fails)
	var cal: Node = root.get_node("Calendar")
	var saved_month: int = int(cal.month)
	var saved_day: int = int(cal.day)
	cal.month = 3
	cal.day = 1
	_check(str(cal.call("get_date_string")) == "宝祐三年　三月初一", "开局日期留出字距", fails)
	_check(str(cal.call("get_monsoon_desc")) == "季风转换期・风微而多变", "三月是转换期", fails)
	cal.month = 6
	_check(str(cal.call("get_monsoon_desc")) == "西南季风　利北上", "六月利北上", fails)
	cal.month = 11
	_check(str(cal.call("get_monsoon_desc")) == "东北季风　利南下", "十一月利南下", fails)
	cal.month = saved_month
	cal.day = saved_day
	_check(main_src.find("费一日") >= 0 and main_src.find("费 1 日") < 0,
		"酒馆行情写成费一日", fails)
	var tavern_i := main_src.find("func _setup_tavern")
	var tavern_j := main_src.find("\nfunc ", tavern_i + 1)
	var tavern_body := main_src.substr(tavern_i, tavern_j - tavern_i) if tavern_i >= 0 and tavern_j > tavern_i else ""
	_check(tavern_body.find("_begin_benches") >= 0
		and tavern_body.find("_add_leave_button") > tavern_body.find("_end_benches"),
		"酒馆募人排成工席，离开留在下面", fails)
	_check(main_src.find("func _mount_status_strip") >= 0
		and main_src.find("func _lift_ledger") >= 0
		and main_src.find("func _begin_benches") >= 0,
		"船籍簿收成顶栏浮层，内页走工席", fails)
	var port_i := main_src.find("func _setup_port_mode")
	var port_j := main_src.find("\nfunc ", port_i + 1)
	var port_body := main_src.substr(port_i, port_j - port_i) if port_i >= 0 and port_j > port_i else ""
	_check(port_body.find("left_panel.visible = true") < 0 and port_body.find("_show_strip(true)") >= 0,
		"进港不再把船籍簿铺回左栏", fails)
	var accent := Button.new()
	UiTheme.style_button(accent, true)
	_check(accent.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
		and accent.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
		"珊瑚钮聚焦和按下仍是深字", fails)
	accent.free()
	_check(main_src.find("func _skill_rank") >= 0 and main_src.find("★") < 0,
		"职事品级写成初习/谙熟/老练，不再用星号", fails)
	_check(main_src.find("func _fit_rank") >= 0 and main_src.find("帆Lv") < 0
		and main_src.find("Lv%d") < 0,
		"船壳改装写成一等二等三等", fails)
	_check(main_src.find("func _interior_title") >= 0 and main_src.find("未命名设施") < 0,
		"序章内页改写成港名去处，港卡不写未命名设施", fails)
	_check(main_src.find("func _interior_lead") >= 0 and main_src.find("UiTheme.plain_log") >= 0,
		"序章内页进门有一句，日志走 plain_log", fails)
	_check(chart_src.find("【发舶】") < 0 and chart_src.find("UiTheme.plain_log") >= 0,
		"海图日志不再写发舶标签", fails)
	_check(chart_src.find("func _bearing_phrase") >= 0 and chart_src.find("UiTheme.heading_card") >= 0
		and chart_src.find("回港（不出海）") < 0 and chart_src.find("目的：") < 0
		and chart_src.find("绕过去看看（费 1 日）") < 0 and chart_src.find("%d%%") < 0
		and chart_src.find("°") < 0,
		"海图旁注收成账条，去掉冒号、度数符号和括号教程", fails)
	var voyage_src := FileAccess.get_file_as_string("res://scripts/core/Voyage.gd")
	_check(chart_src.find("绕了些路。") >= 0 and chart_src.find("（绕了些路）") < 0
		and chart_src.find("（调试）") < 0 and chart_src.find("点验　中途遭遇。") >= 0
		and voyage_src.find("损折：") < 0 and voyage_src.find("损折　") >= 0,
		"海图遭遇日志去掉括号，风涛货损去掉冒号", fails)
	var yard_node := (load("res://scripts/Main.gd") as GDScript).new() as Node
	_check(str(yard_node.call("_sail_fit_phrase", 1)) == "此帆比光船快一成二"
		and str(yard_node.call("_sail_fit_phrase", 2)) == "此帆比光船快二成四"
		and str(yard_node.call("_armor_fit_phrase", 1)) == "船体伤剩九成"
		and str(yard_node.call("_armor_fit_phrase", 2)) == "船体伤剩八成"
		and main_src.find("月息每百 %d") >= 0 and main_src.find("月息 %d%%") < 0
		and main_src.find("添 %d 人") >= 0 and main_src.find("+%d") < 0
		and main_src.find("运往 %s　多 %d") >= 0 and main_src.find("→ %s") < 0
		and main_src.find("航速 ×") < 0 and main_src.find("违禁：") < 0
		and FileAccess.get_file_as_string("res://scripts/core/Economy.gd").find("名声加 %d") >= 0
		and FileAccess.get_file_as_string("res://scripts/core/Economy.gd").find("名声 +%d") < 0
		and int(yard_node.call("_duty_per_hundred", 1.0)) == 100
		and int(yard_node.call("_duty_per_hundred", 0.94)) == 94
		and int(yard_node.call("_duty_per_hundred", 0.76)) == 76
		and main_src.find("抽解每百 %d") >= 0 and main_src.find("%d%%") < 0
		and main_src.find("水手 %d 至 %d") >= 0 and main_src.find("水粮各 %d　付 %d") >= 0,
		"船屋加成写成成数，抽解与购船去掉百分号和短横", fails)
	yard_node.free()
	var chart_script := load("res://scripts/SeaChart.gd") as GDScript
	var chart_node := chart_script.new() as Node
	_check(str(chart_node.call("_bearing_phrase", 90.0)) == "东　90 度", "正东写成东并附度数", fails)
	_check(str(chart_node.call("_bearing_phrase", 47.0)) == "东北　47 度", "四十七度归东北", fails)
	_check(str(chart_node.call("_bearing_phrase", 225.0)) == "西南　225 度", "二百二十五度归西南", fails)
	chart_node.free()
	var crew: Node = root.get_node("Crew")
	_check(str(crew.call("rank_word", 1)) == "初习" and str(crew.call("rank_word", 3)) == "老练",
		"职事品级首尾两字仍在", fails)
	_check(str(crew.call("rank_word", 2)) == "谙熟", "职事品级第二档仍是原字", fails)
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
	var note_node := (load("res://scripts/Main.gd") as GDScript).new() as Node
	var rub_fresh := str(note_node.call(
		"_temple_rub_note", "废烽堠", "旧时守海的烽堠，如今无人执守，却仍是夜航辨岸的好记认。"
	))
	_check(
		rub_fresh == "拓「废烽堠」　旧时守海的烽堠，如今无人执守，却仍是夜航辨岸的好记认。"
			and str(note_node.call("_temple_rub_note", "废烽堠", "  ")) == "拓「废烽堠」。"
			and bool(note_node.call("_has_temple_rub", "废烽堠"))
			and main_src.find("再升一等。") >= 0 and main_src.find("再升一等：") < 0,
		"拓碑边记用空格隔开，旧冒号仍算拓过，修埠注用句号",
		fails,
	)
	var money_line := str(note_node.call("_append_progress_line", "", {
		"label": "本钱", "current": 0, "need": 5000, "done": false,
	}))
	var been_line := str(note_node.call("_append_progress_line", "", {
		"label": "亲至　南岛海道北口", "current": 0, "need": 1, "done": false,
	}))
	var items: Array = gs.call("_requirement_items", {
		"peak_money": 5000, "visited_count": 5, "must_visit": ["ryukyu"],
	})
	var money_ok := false
	var ports_ok := false
	var ryukyu_ok := false
	for it_v in items:
		var it: Dictionary = it_v
		var lab := str(it.get("label", ""))
		if lab == "本钱" and int(it.get("need", 0)) == 5000:
			money_ok = true
		if lab == "走通港口" and int(it.get("need", 0)) == 5:
			ports_ok = true
		if lab == "亲至　南岛海道北口":
			ryukyu_ok = true
	_check(
		money_line == "・　本钱　0 / 5000\n" and been_line == "・　亲至　南岛海道北口\n"
			and money_ok and ports_ok and ryukyu_ok,
		"章目写成已行多少，亲至港名用空格隔开，门槛仍是五千与五港",
		fails,
	)
	var enter_i2 := main_src.find("func _on_enter_port")
	var enter_j2 := main_src.find("\nfunc ", enter_i2 + 1)
	var enter_body2 := main_src.substr(enter_i2, enter_j2 - enter_i2) if enter_i2 >= 0 and enter_j2 > enter_i2 else ""
	_check(
		enter_body2.find("visit_port") >= 0
			and enter_body2.find("update_status_panel") > enter_body2.find("visit_port"),
		"进港后船籍簿按已走通的港重写",
		fails,
	)
	_check(
		main_src.find("掐指算了算。") >= 0 and main_src.find("掐指算了算：") < 0
			and main_src.find("压低声音说。") >= 0 and main_src.find("压低声音说：") < 0
			and main_src.find("五至八月") >= 0 and main_src.find("十月至次年二月") >= 0
			and main_src.find("%s　眼下缺%s") >= 0 and main_src.find("%s 眼下缺") < 0
			and main_src.find("多得　%d") >= 0,
		"候风与打听去掉冒号，月份仍写在风名后面",
		fails,
	)
	note_node.free()
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
				var hud0: String = wm_inst._format_left_hud(
					"敌船 2 艘　存活 2\n", "", "北风", 80, 0, "green", 100, 100, "弃战　B"
				)
				var hud1: String = wm_inst._format_left_hud(
					"敌船 2 艘　存活 2\n", "", "北风", 80, 1, "green", 100, 100, "接舷　G　弃战　B"
				)
				var hud2: String = wm_inst._format_left_hud(
					"敌船 2 艘　存活 2\n", "", "北风", 80, 2, "green", 100, 100, "弃战　B"
				)
				_check(
					hud0.find("收帆") >= 0 and hud1.find("半帆") >= 0 and hud2.find("满帆") >= 0
						and hud0.find("升帆　W") >= 0 and hud0.find("落帆　S") >= 0
						and hud0.find("操舵　A　D") >= 0 and hud0.find("齐射　J　K") >= 0
						and hud0.find("100 / 100") >= 0 and hud0.find("A/D") < 0
						and hud0.find("J/K") < 0 and hud0.find("档") < 0
						and hud0.find("操舵　A　D\n") < 0 and hud0.find("齐射　J　K\n") < 0
						and hud0.find("\n") >= 0
						and hud1.find("接舷　G") >= 0,
					"海战栏写成升帆落帆与半帆，操纵横排成两行",
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
