extends SceneTree
## 无显示器时的引擎冒烟：确认 autoload 能起来、旗标门槛与结局选择按数据工作。
## --script 没有 autoload 全局名，必须走 /root。
## godot --headless --path . -s res://tools/godot_smoke.gd

const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
const SP := preload("res://tools/src_probe.gd")  # 按名认函数的源码探查（lane cs15：不按前缀认名）


func _init() -> void:
	call_deferred("_run")


## Main.gd 拆出去的件：读 tools/main_splits.txt 第一列（lane cs13；与 tools/check_symbols.py 同读这一份，
## 清单由 tools/gen_main_splits.py 生成，check_symbols 对账）。跳过空行与 # 开头的行，取第一个制表符前的部分。
## 源码断言读 Main.gd + 这些件接在一起的全文：函数搬走后「某字样须在 / 不得在」不因 Main 里只剩一行转发而误判。
## （按 func 切函数体的断言仍切 Main 里的 func；要断言搬走的函数体，去拆出件里切。）
const MAIN_SPLITS_TXT := "res://tools/main_splits.txt"


func _main_splits() -> Array:
	var out: Array = []
	for ln in FileAccess.get_file_as_string(MAIN_SPLITS_TXT).split("\n"):
		if ln.strip_edges() == "" or ln.begins_with("#"):
			continue
		out.append("res://" + ln.split("\t")[0].strip_edges())
	return out


func _main_family_src() -> String:
	var src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	for p in _main_splits():
		src += "\n" + FileAccess.get_file_as_string(p)
	return src


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
	_check(SP.has_tok(chart_src, "style_heading(head)") and chart_src.find("UiTheme.panel()") >= 0,
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
		and SP.has_tok(chart_src, "style_choice_button(b)"),
		"海图遭遇选项走竖排挑签", fails)
	_check(chart_src.find("船况") >= 0
		and SP.has_func(chart_src, "_mount_condition")
		and chart_src.find("Vector2(260, 0)") < 0
		and chart_src.find("Vector2(300, 0)") < 0,
		"海图左右栏收成顶匾，船况点开才占画面", fails)
	# 见面页在 NpcPage（Lane main5 拆出），Main 里只剩一行转发：函数体去拆出件里切，去掉 main. 前缀即搬走前的原文
	var meet_src := FileAccess.get_file_as_string("res://scripts/ui/NpcPage.gd")
	var meet_at := meet_src.find("static func show_npc_mode(")
	var meet_end := meet_src.find("\nstatic func ", meet_at + 1)
	var meet_body := meet_src.substr(meet_at, meet_end - meet_at).replace("main.", "") if meet_at >= 0 and meet_end > meet_at else ""
	_check(SP.has_tok(meet_body, "_begin_benches(npc_actions)")
		and meet_body.find("SIZE_SHRINK_CENTER") >= 0,
		"见面行情走工席，离开不再拉满宽", fails)
	var theme_scr = load("res://scripts/core/UiTheme.gd")
	_check(theme_scr != null, "UiTheme.gd 能编译", fails)
	var dlg := AcceptDialog.new()
	UiTheme.style_dialog(dlg, true)
	_check(dlg.get_theme_stylebox("panel") != null, "UiTheme.style_dialog 给弹窗套绢本面板", fails)
	# 皮肤断言按 UiTheme.SKIN 分支：夜潮原断言逐字保留；绢本断言靛墨 / 泥金 / 朱砂 / 石青的色相关系与实测对比度。
	var yechao := UiTheme.SKIN == "yechao"
	if yechao:
		_check(UiTheme.INK.b > UiTheme.INK.r and UiTheme.INK.g > UiTheme.INK.r
			and UiTheme.TIDE.g > UiTheme.TIDE.r and UiTheme.SEAL.r > UiTheme.SEAL.b,
			"面板是夜潮青，潮光作线，主钮是珊瑚", fails)
	else:
		_check(UiTheme.INK.get_luminance() < 0.12 and UiTheme.INK.a >= 0.9
			and UiTheme.GOLD.r > UiTheme.GOLD.g and UiTheme.GOLD.g > UiTheme.GOLD.b
			and UiTheme.GOLD.h > 0.08 and UiTheme.GOLD.h < 0.14
			and (UiTheme.SEAL.h < 0.03 or UiTheme.SEAL.h > 0.97) and UiTheme.SEAL.s > 0.6 and UiTheme.SEAL.r > 0.6
			and UiTheme.TIDE.b > UiTheme.TIDE.r and UiTheme.TIDE.g > UiTheme.TIDE.r,
			"面板是暖墨，泥金作线，主钮是朱砂，航向是石青", fails)
		var weak := []
		for pair in [["TEXT", UiTheme.TEXT], ["TEXT_DIM", UiTheme.TEXT_DIM], ["GOLD", UiTheme.GOLD],
				["GOLD_HI", UiTheme.GOLD_HI], ["TIDE", UiTheme.TIDE], ["MOSS", UiTheme.MOSS],
				["HONEY", UiTheme.HONEY], ["CINNABAR", UiTheme.CINNABAR]]:
			if _contrast(pair[1], UiTheme.INK) < 4.5:
				weak.append(pair[0])
		var paper: Color = UiTheme.PAPER_CARD  # 未点亮的宣纸卡（比点亮时暗一成），取暗的一侧量
		for pair in [["PAPER_TEXT", UiTheme.PAPER_TEXT], ["PAPER_DIM", UiTheme.PAPER_DIM], ["PAPER_TIDE", UiTheme.PAPER_TIDE],
				["PAPER_GOLD", UiTheme.PAPER_GOLD], ["PAPER_MOSS", UiTheme.PAPER_MOSS], ["PAPER_HONEY", UiTheme.PAPER_HONEY],
				["PAPER_CINNABAR", UiTheme.PAPER_CINNABAR]]:
			if _contrast(pair[1], paper) < 4.5:
				weak.append(pair[0])
		if _contrast(UiTheme.SEAL_TEXT, UiTheme.SEAL) < 4.5:
			weak.append("SEAL_TEXT")
		# 港页岸门的纸面另压到旧绢调（Main._make_shore_door 的 self_modulate = UiTheme.DOOR_PAPER_TINT），纸上字色按压暗后的纸再量一遍
		var door_paper := paper * UiTheme.DOOR_PAPER_TINT
		for pair in [["DOOR_TEXT", UiTheme.PAPER_TEXT], ["DOOR_DIM", UiTheme.PAPER_DIM], ["DOOR_TIDE", UiTheme.PAPER_TIDE],
				["DOOR_CINNABAR", UiTheme.PAPER_CINNABAR]]:
			if _contrast(pair[1], door_paper) < 4.5:
				weak.append(pair[0])
		_check(weak.is_empty(), "绢本字色对底色实测 ≥4.5:1（不达标 %s）" % [weak], fails)
		var smudged := []
		for dark_c in [UiTheme.TEXT, UiTheme.TEXT_DIM, UiTheme.TIDE, UiTheme.MOSS, UiTheme.HONEY, UiTheme.CINNABAR,
				Color(0.75, 0.75, 0.7), Color(1.0, 0.75, 0.45), Color(0.65, 0.9, 0.7)]:
			var inked: Color = UiTheme.on_paper(dark_c)
			if _contrast(inked, paper) < 4.5 or UiTheme.on_paper(inked) != inked:
				smudged.append(dark_c)
		_check(smudged.is_empty() and UiTheme.on_paper(UiTheme.PAPER_TEXT) == UiTheme.PAPER_TEXT,
			"深底字色落到宣纸上一律换成纸上墨色（≥4.5:1），已换过的不再动（不达标 %s）" % [smudged], fails)
	var facility := UiTheme.card()
	var picked := UiTheme.heading_card(true)
	var idle := UiTheme.heading_card(false)
	if yechao:
		var facility_f := facility as StyleBoxFlat
		var picked_f := picked as StyleBoxFlat
		var idle_f := idle as StyleBoxFlat
		_check(facility_f != null and picked_f != null and idle_f != null
			and facility_f.corner_radius_top_left == 16 and picked_f.corner_radius_top_left == 16
			and picked_f.border_color.g > picked_f.border_color.r
			and idle_f.border_color.b > idle_f.border_color.r,
			"港卡与航向牌是潮玻璃，选中边是潮光", fails)
	else:
		var facility_t := facility as StyleBoxTexture
		var picked_f := picked as StyleBoxFlat
		var idle_f := idle as StyleBoxFlat
		_check(facility_t != null and facility_t.texture != null
			and facility_t.texture.resource_path.ends_with("panel_paper.res")
			and picked_f != null and idle_f != null
			and picked_f.corner_detail == 1 and picked_f.corner_radius_top_left > 0
			and picked_f.border_color.r > picked_f.border_color.b
			and picked_f.border_width_left > idle_f.border_width_left
			and picked_f.border_color.a > idle_f.border_color.a,
			"港卡是宣纸，航向牌是委角墨牌，选中边是泥金实线", fails)
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
	if yechao:
		var door_f := door_box as StyleBoxFlat
		_check(door_f != null and door_f.corner_radius_top_left == 16 and door_f.border_color.g > door_f.border_color.r,
			"岸门是潮光边的潮玻璃", fails)
	else:
		var door_t := door_box as StyleBoxTexture
		var door_hi := UiTheme.shore_door_hover() as StyleBoxTexture
		_check(door_t != null and door_hi != null and door_t.texture != null
			and door_t.texture.resource_path.ends_with("panel_paper.res")
			and door_hi.modulate_color.v > door_t.modulate_color.v,
			"岸门是宣纸卡，悬停纸面点亮", fails)
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
		{"id": "pirate_boat", "for_sale": false},
	]
	var yard_ch1 := PackedStringArray(["ch1"])
	var yard_sale: PackedStringArray = DrydockBerth.sale_ids(yard_offers, yard_ch1)
	_check(yard_sale.size() == 3 and yard_sale[0] == "sampan" and yard_sale[2] == "fu_ship_medium",
		"第一章坞外待售三艘，广船不在", fails)
	var yard_ch2 := PackedStringArray(["ch1", "ch2"])
	var yard_sale2: PackedStringArray = DrydockBerth.sale_ids(yard_offers, yard_ch2)
	_check(yard_sale2.size() == 4 and yard_sale2[3] == "canton_ship",
		"第二章广船也在坞外", fails)
	# 真表（ShipyardPage 交进来的就是这份）：快船第一到第四章都不上架；海鹘照自己的 unlock 上架
	var yard_catalog: Array = gm.ships_data.get("ships", [])
	var falcon_unlock := "ch1"
	for yard_row in yard_catalog:
		if yard_row is Dictionary and str(yard_row.get("id", "")) == "sea_falcon":
			falcon_unlock = str(yard_row.get("unlock", "ch1"))
	var yard_reached := PackedStringArray()
	for yard_n in range(1, 5):
		yard_reached.append("ch%d" % yard_n)
		var yard_sale_n: PackedStringArray = DrydockBerth.sale_ids(yard_catalog, yard_reached)
		_check(not yard_sale_n.has("pirate_boat") and yard_sale_n.has("sea_falcon") == yard_reached.has(falcon_unlock),
			"第%d章船屋不卖快船（海鹘照 unlock 上架）" % yard_n, fails)
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
	if yechao:
		_check(accent_btn.get_theme_color("font_color") == UiTheme.INK_SOLID
			and accent_btn.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
			and accent_btn.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
			"珊瑚主钮聚焦和按下仍是深字", fails)
		_check(chip.get_theme_color("font_color") == UiTheme.INK_SOLID
			and chip.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
			and chip.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
			"珊瑚小钮聚焦和按下仍是深字", fails)
	else:
		_check(_is_seal_text(accent_btn.get_theme_color("font_color"))
			and _is_seal_text(accent_btn.get_theme_color("font_focus_color"))
			and _is_seal_text(accent_btn.get_theme_color("font_pressed_color")),
			"朱砂主钮常态、聚焦和按下都是印面浅字（朱砂上 ≥4.5:1）", fails)
		_check(_is_seal_text(chip.get_theme_color("font_color"))
			and _is_seal_text(chip.get_theme_color("font_focus_color"))
			and _is_seal_text(chip.get_theme_color("font_pressed_color")),
			"朱砂小钮常态、聚焦和按下都是印面浅字（朱砂上 ≥4.5:1）", fails)
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
	_check(not ("beacon_ruin" in gs.discoveries_found) and "beacon_ruin" in gs.discoveries_reported
		and not ("beacon_ruin" in gs.unreported_discoveries()),
		"呈报后废烽堠挪入 discoveries_reported、不再挂呈报签", fails)
	_check(gs.report_discovery("beacon_ruin").is_empty() and not gs.record_discovery("beacon_ruin"),
		"已呈报的发现不能二次领赏、也不再入册", fails)
	var disc_save: Dictionary = gs.to_dict()
	_check(disc_save.has("discoveries_found") and "beacon_ruin" in disc_save.get("discoveries_reported", []),
		"存档含 discoveries_found / discoveries_reported", fails)
	var splits := _main_splits()
	var splits_missing: Array = splits.filter(func(p): return FileAccess.get_file_as_string(p).is_empty())
	_check(not splits.is_empty() and splits_missing.is_empty(),
		"Main 拆出件清单读自 tools/main_splits.txt（%d 件%s）" % [splits.size(),
		"，都读得到" if splits_missing.is_empty() else "；读不到：" + ", ".join(PackedStringArray(splits_missing))], fails)
	var main_src := _main_family_src()
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
	# 航海日志册页在 SaveSheet（Lane main6 拆出），Main 里只剩一行转发：函数体去拆出件里切，去掉 main. 前缀即搬走前的原文
	var save_src := FileAccess.get_file_as_string("res://scripts/ui/SaveSheet.gd")
	var save_at := save_src.find("static func show_save_dialog(")
	var save_end := save_src.find("\nstatic func ", save_at + 1)
	var save_body := save_src.substr(save_at, save_end - save_at).replace("main.", "") if save_at >= 0 and save_end > save_at else ""
	_check(save_body.find("SaveSheet") >= 0 and SP.has_tok(save_body, "_begin_benches(col)")
		and save_body.find("SIZE_SHRINK_CENTER") >= 0
		and save_body.find("Vector2(520, 0)") < 0
		and save_body.find("style_choice_button(close)") < 0,
		"航海日志三卷走工席，合上不再拉满宽", fails)
	_check(main_src.find("OptionButton.new()") < 0 and SP.has_tok(main_src, "_select_market_ship", true),
		"牙行选船走账条小钮，不再用系统下拉", fails)
	_check(main_src.find("买%d") < 0 and main_src.find("卖%d") < 0
		and main_src.find("只购得 %d。") >= 0 and main_src.find("钱（") < 0,
		"牙行小钮与买卖日志留出字距", fails)
	_check(main_src.find("塞　50") >= 0 and main_src.find("关注　减 15") >= 0
		and main_src.find("塞 50") < 0 and main_src.find("关注减 15") < 0
		and SP.has_tok(main_src.replace("main.", ""), "UiTheme.plain_log(_gather_price_intel"),
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
	# 酒馆整页在 TavernPage（Lane main4 拆出），Main 里只剩一行转发：函数体去拆出件里切
	var tavern_src := FileAccess.get_file_as_string("res://scripts/ui/TavernPage.gd")
	var tavern_i := tavern_src.find("static func setup_tavern(")
	var tavern_j := tavern_src.find("\nstatic func ", tavern_i + 1)
	var tavern_body := tavern_src.substr(tavern_i, tavern_j - tavern_i) if tavern_i >= 0 and tavern_j > tavern_i else ""
	_check(SP.has_tok(tavern_body, "_begin_benches", true)
		and SP.tok_find(tavern_body, "_add_leave_button", 0, true) > SP.tok_find(tavern_body, "_end_benches", 0, true),
		"酒馆募人排成工席，离开留在下面", fails)
	_check(SP.has_func(main_src, "_mount_status_strip")
		and SP.has_func(main_src, "_lift_ledger")
		and SP.has_func(main_src, "_begin_benches"),
		"船籍簿收成顶栏浮层，内页走工席", fails)
	var port_i := SP.func_at(main_src, "_setup_port_mode")
	var port_j := main_src.find("\nfunc ", port_i + 1)
	var port_body := main_src.substr(port_i, port_j - port_i) if port_i >= 0 and port_j > port_i else ""
	_check(port_body.find("left_panel.visible = true") < 0 and SP.has_tok(port_body, "_show_strip(true)"),
		"进港不再把船籍簿铺回左栏", fails)
	var accent := Button.new()
	UiTheme.style_button(accent, true)
	if UiTheme.SKIN == "yechao":
		_check(accent.get_theme_color("font_focus_color") == UiTheme.INK_SOLID
			and accent.get_theme_color("font_pressed_color") == UiTheme.INK_SOLID,
			"珊瑚钮聚焦和按下仍是深字", fails)
	else:
		_check(_is_seal_text(accent.get_theme_color("font_focus_color"))
			and _is_seal_text(accent.get_theme_color("font_pressed_color")),
			"朱砂钮聚焦和按下仍是印面浅字", fails)
	accent.free()
	_check(SP.has_func(main_src, "_skill_rank") and main_src.find("★") < 0,
		"职事品级写成初习/谙熟/老练，不再用星号", fails)
	_check(SP.has_func(main_src, "_fit_rank") and main_src.find("帆Lv") < 0
		and main_src.find("Lv%d") < 0,
		"船壳改装写成一等二等三等", fails)
	_check(SP.has_func(main_src, "_interior_title") and main_src.find("未命名设施") < 0,
		"序章内页改写成港名去处，港卡不写未命名设施", fails)
	_check(SP.has_func(main_src, "_interior_lead") and SP.calls(main_src, "UiTheme.plain_log"),
		"序章内页进门有一句，日志走 plain_log", fails)
	_check(chart_src.find("【发舶】") < 0 and SP.calls(chart_src, "UiTheme.plain_log"),
		"海图日志不再写发舶标签", fails)
	_check(SP.has_func(chart_src, "_bearing_phrase") and SP.calls(chart_src, "UiTheme.heading_card")
		and chart_src.find("回港（不出海）") < 0 and chart_src.find("目的：") < 0
		and chart_src.find("绕过去看看（费 1 日）") < 0 and chart_src.find("%d%%") < 0
		and chart_src.find("°") < 0,
		"海图旁注收成账条，去掉冒号、度数符号和括号教程", fails)
	var voyage_src := FileAccess.get_file_as_string("res://scripts/core/Voyage.gd")
	var fx_src := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	var flee_ok := chart_src.find("绕了些路。") >= 0 or (
		(fx_src.find("绕了些路。") >= 0 or fx_src.find("绕路若干") >= 0)
		and SP.has_tok(chart_src, "sea_flee_ok_note", true))
	_check(flee_ok and chart_src.find("（绕了些路）") < 0
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
	_check(str(chart_node.call("_bearing_phrase", 90.0)) == "东　卯针", "正东写成东并附卯针", fails)
	_check(str(chart_node.call("_bearing_phrase", 47.0)) == "东北　艮针", "四十七度归东北、艮针", fails)
	_check(str(chart_node.call("_bearing_phrase", 225.0)) == "西南　坤针", "二百二十五度归西南、坤针", fails)
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
	_check(SP.has_func(main_src, "_setup_guild") and SP.has_func(main_src, "_setup_exam")
		and SP.has_func(main_src, "_setup_residence") and SP.has_func(main_src, "_setup_temple"),
		"行会/贡院/住宅/寺观有动态页", fails)
	_check(main_src.find("HOME_RATE") >= 0 and main_src.find("INN_RATE") >= 0,
		"住处与旅店房价分开", fails)
	# 贡院誊录在 GuildExamPage（Lane main7 拆出），Main 里只剩一行转发：函数体去拆出件里切，去掉 main. 前缀即搬走前的原文
	var guild_src := FileAccess.get_file_as_string("res://scripts/ui/GuildExamPage.gd")
	var exam_i := guild_src.find("static func on_exam_copy(")
	var exam_j := guild_src.find("\nstatic func ", exam_i + 1) if exam_i >= 0 else -1
	var exam_body := guild_src.substr(exam_i, exam_j - exam_i).replace("main.", "") if exam_i >= 0 and exam_j > exam_i else ""
	_check(exam_body.find("scholar_tendency") >= 0 and exam_body.find("add_fame") < 0,
		"贡院誊录只加学者倾向、不给名声", fails)
	# 寺观细看 / 拓碑在 ResidencePage（Lane main9 拆出），Main 里只剩一行转发：函数体去拆出件里切，去掉 main. 前缀即搬走前的原文
	var res_src := FileAccess.get_file_as_string("res://scripts/ui/ResidencePage.gd")
	var look_i := res_src.find("static func on_temple_look(")
	var look_j := res_src.find("\nstatic func ", look_i + 1) if look_i >= 0 else -1
	var look_body := res_src.substr(look_i, look_j - look_i).replace("main.", "") if look_i >= 0 and look_j > look_i else ""
	_check(SP.has_tok(look_body, "record_discovery", true) and look_body.find("add_fame") < 0
		and look_body.find("report_discovery") < 0,
		"寺观细看只记入册、不给名声", fails)
	var rub_i := res_src.find("static func on_temple_rub(")
	var rub_j := res_src.find("\nstatic func ", rub_i + 1) if rub_i >= 0 else -1
	if rub_i >= 0 and rub_j < 0:
		rub_j = res_src.length()  # on_temple_rub 是拆出件末支，切到文件尾
	var rub_body := res_src.substr(rub_i, rub_j - rub_i).replace("main.", "") if rub_i >= 0 and rub_j > rub_i else ""
	_check(SP.has_tok(rub_body, "add_ledger_note", true) and rub_body.find("add_fame") < 0
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
			and (main_src.find("再升一等。") >= 0 or main_src.find("再修一等") >= 0) and main_src.find("再升一等：") < 0,
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
	var enter_i2 := SP.func_at(main_src, "_on_enter_port")
	var enter_j2 := main_src.find("\nfunc ", enter_i2 + 1)
	var enter_body2 := main_src.substr(enter_i2, enter_j2 - enter_i2) if enter_i2 >= 0 and enter_j2 > enter_i2 else ""
	_check(
		SP.has_tok(enter_body2, "visit_port", true)
			and SP.tok_find(enter_body2, "update_status_panel", 0, true) > SP.tok_find(enter_body2, "visit_port", 0, true),
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

	_check_pirate_boat(fails)
	_check_characters(gm, main_src, fails)
	await _check_headless_bypass(fails)
	_finish(fails)


## 海寇快船（备忘 #7）+ 船图契约（钩子第一批第 5 条）：海寇出 pirate_boat、夺来按快船入列、墨边写真实船名、
## 精灵有图就用、缺图回落两张默认贴图。WorldMap 真开战 → 接舷夺船的全流程另见 tools/qa_pirate_boat_probe.gd。
func _check_pirate_boat(fails: Array) -> void:
	var fx: GDScript = load("res://scripts/combat/CombatFx.gd")
	var lb: GDScript = load("res://scripts/ui/CombatLetterbox.gd")
	var consts: Dictionary = (load("res://scripts/SeaChart.gd") as GDScript).get_script_constant_map()
	var pirate: Dictionary = consts.get("PIRATE_ENEMY", {})
	var patrol: Dictionary = consts.get("PATROL_ENEMY", {})
	_check(str(pirate.get("type", "")) == "pirate_boat" and str(patrol.get("type", "")) == "sea_falcon"
			and str(patrol.get("sprite", "")) == "yuan_patrol",
		"海寇迎战出快船（pirate_boat）；元军哨船 type 不动、另挂 sprite=yuan_patrol", fails)
	_check(str(lb.call("enemy_note", [pirate])) == "快船二艘" and str(lb.call("enemy_note", [patrol])) == "海鹘三艘",
		"海战墨边副题按真实船名：海寇「快船二艘」、元军哨船「海鹘三艘」", fails)
	var fx_consts: Dictionary = fx.get_script_constant_map()
	var fmt: String = fx_consts.get("SHIP_SPRITE_FMT", "")
	var own_fb: String = fx_consts.get("SHIP_SPRITE_OWN", "")
	var foe_fb: String = fx_consts.get("SHIP_SPRITE_ENEMY", "")
	# 回落拿保证不在库的 id 验；真 type 的期望值按图在不在算（美术按契约交图后真 type 就不再回落，收一张生效一张，门禁不随收图变红）
	var absent_id := "__nk1_absent__"
	var absent_in := fmt != "" and not ResourceLoader.exists(fmt % absent_id)
	var foe_type := str(pirate.get("type", ""))
	var foe: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	foe.set("ship_type", absent_id)
	foe.call("apply_sprite")
	_check(absent_in and foe_fb != "" and _sprite_tex_path(foe) == foe_fb,
		"敌船精灵缺图（ship_%s.png 不在库）回落 ship_falcon.png" % absent_id, fails)
	foe.set("ship_type", foe_type)
	foe.call("apply_sprite")
	var foe_want := _ship_sprite_want(fmt, foe_type, foe_fb)
	_check(foe_type != "" and _sprite_tex_path(foe) == foe_want,
		"快船精灵：有 ship_%s.png 就用、没有回落 ship_falcon.png（应 %s，得 %s）" % [foe_type, foe_want, _sprite_tex_path(foe)], fails)
	foe.free()
	var own: Node = (load("res://scenes/Ship.tscn") as PackedScene).instantiate()
	own.call("apply_type_sprite", absent_id)
	_check(absent_in and own_fb != "" and _sprite_tex_path(own) == own_fb,
		"旗舰精灵缺图（ship_%s.png 不在库）回落 ship_fu.png" % absent_id, fails)
	own.call("apply_type_sprite", "sampan")
	var own_want := _ship_sprite_want(fmt, "sampan", own_fb)
	_check(_sprite_tex_path(own) == own_want,
		"旗舰小艍船精灵：有 ship_sampan.png 就用、没有回落 ship_fu.png（应 %s，得 %s）" % [own_want, _sprite_tex_path(own)], fails)
	own.free()
	var fleet: Node = root.get_node_or_null("Fleet")
	if fleet == null:
		_check(false, "Fleet autoload 在 /root", fails)
		return
	var saved: Array = (fleet.get("ships") as Array).duplicate(true)
	var n0: int = saved.size()
	var ok := bool(fleet.call("add_ship", "pirate_boat", "快船"))
	var ships: Array = fleet.get("ships")
	var got: Dictionary = ships[ships.size() - 1] if ships.size() > n0 else {}
	_check(ok and str(got.get("type", "")) == "pirate_boat" and str(got.get("name", "")) == "快船",
		"夺船按 ship_type=pirate_boat 调 Fleet.add_ship 能入列，船名「快船」", fails)
	_fleet_dup_names(fleet, fails)
	fleet.set("ships", saved)


## lane fx2：同型船同名，船屋「换上」钮分不清（todo「小毛病」）。旧档 / 直调 add_ship 不给名的两条福船（中）存名照旧同名，
## 上屏 display_name / ship_label 两两不同且存名不改；购入起名 hull_name 两次不同、不撞船队里已有的名；存档 round-trip 后仍去重。
## 夺来的两条「快船」只在显示层去重，存名仍是「快船」（V0928-10 夺船命名待拍板，不在此定）。
func _fleet_dup_names(fleet: Node, fails: Array) -> void:
	fleet.set("ships", [])
	fleet.call("add_ship", "sampan", "无名小艍")
	fleet.call("add_ship", "fu_ship_medium")
	fleet.call("add_ship", "fu_ship_medium")
	var rt: Dictionary = JSON.parse_string(JSON.stringify(fleet.call("to_dict")))
	fleet.call("from_dict", rt)
	var ships: Array = fleet.get("ships")
	var stored := [str(ships[1].get("name", "")), str(ships[2].get("name", ""))]
	var shown := [str(fleet.call("display_name", 1)), str(fleet.call("display_name", 2))]
	var labels := [str(fleet.call("ship_label", 1)), str(fleet.call("ship_label", 2))]
	_check(stored == ["福船（中）", "福船（中）"], "旧档两条同型福船读回存名不改（得 %s）" % [stored], fails)
	_check(shown == ["福船（中）・甲", "福船（中）・乙"] and labels == shown,
		"旧档同名两条上屏去重「福船（中）・甲」「福船（中）・乙」（得 %s / %s）" % [shown, labels], fails)
	_check(str(fleet.call("display_name", 0)) == "无名小艍" and str(fleet.call("ship_label", 0)) == "无名小艍",
		"不撞名的船上屏照旧（无名小艍，名里带船型不再后缀）", fails)
	var n1 := str(fleet.call("hull_name", "fu_ship_medium"))
	fleet.call("add_ship", "fu_ship_medium", n1)
	var n2 := str(fleet.call("hull_name", "fu_ship_medium"))
	fleet.call("add_ship", "fu_ship_medium", n2)
	ships = fleet.get("ships")
	var all_names := {}
	for i in ships.size():
		all_names[str(fleet.call("display_name", i))] = true
	_check(n1 != "" and n2 != "" and n1 != n2 and not n1.contains("福船") and not n1.contains("・")
		and all_names.size() == ships.size(),
		"购入起舟名两次不同、不带序号、上屏五条两两不同（%s / %s，%s）" % [n1, n2, all_names.keys()], fails)
	_check(str(fleet.call("ship_label", 3)) == "%s　福船（中）" % n1 and str(fleet.call("display_name", 3)) == n1,
		"舟名的船屋题头 / 换上钮后缀船型（%s）" % fleet.call("ship_label", 3), fails)
	fleet.set("ships", [])
	fleet.call("add_ship", "fu_ship_medium", "快船")
	fleet.call("add_ship", "pirate_boat", "快船")
	fleet.call("add_ship", "pirate_boat", "快船")
	ships = fleet.get("ships")
	_check(str(ships[1].get("name", "")) == "快船" and str(ships[2].get("name", "")) == "快船"
		and str(fleet.call("display_name", 1)) != str(fleet.call("display_name", 2))
		and str(fleet.call("display_name", 0)) != str(fleet.call("display_name", 1)),
		"夺来两条快船存名不改、上屏去重（%s / %s / %s）" % [fleet.call("display_name", 0), fleet.call("display_name", 1), fleet.call("display_name", 2)], fails)
	ships[1]["crew"] = 0
	ships[2]["crew"] = 0
	var short: Array = fleet.call("crew_shortfall")
	var short_names := {}
	for e in short:
		short_names[str(e.get("name", ""))] = true
	_check(short.size() == 2 and short_names.size() == 2, "出海缺员提示按上屏名，同名不混（%s）" % [short_names.keys()], fails)


## 船图契约的期望值：assets/ship_<id>.png 在库就是它，不在是 fallback。与 CombatFx.ship_sprite_path 同规则的独立写法，
## 断言跟着库里有没有图走，不写死「必须回落」。
func _ship_sprite_want(fmt: String, sid: String, fallback: String) -> String:
	if fmt == "" or sid == "":
		return fallback
	var p := fmt % sid
	return p if ResourceLoader.exists(p, "Texture2D") else fallback


func _sprite_tex_path(n: Node) -> String:
	var spr := n.get_node_or_null("Sprite2D") as Sprite2D
	return spr.texture.resource_path if spr != null and spr.texture != null else ""


## headless 零延迟旁路（第 2 轮工程 m4：原先只查源码里有没有 ChapterSheet 字样；live() 在 headless 下误判为真时，
## 章节卡会晚一帧才出册页，门禁照样全绿）。照评审探针 probe_headless：过场层关闭；升章册页与结局册页都在调用的同一帧建好，
## 跳年当帧结算；Main 底下没有章节卡 / 过场 / 横幅层。放在最后跑：会真的落定一个结局。
func _check_headless_bypass(fails: Array) -> void:
	var cine = load("res://scripts/cutscene/Cinematics.gd")
	_check(not bool(cine.call("live")) and not bool(cine.call("want_opening")),
		"headless 下过场层关闭（live / want_opening 皆假）", fails)
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	var cal: Node = root.get_node("Calendar")
	var gs: Node = root.get_node("GameState")
	gs.last_port = "quanzhou"
	main.load_scene("quanzhou")
	var y0: int = cal.year
	var f0 := Engine.get_process_frames()
	main._show_chapter_dialog({"advanced": true, "resolved": false, "title": "t", "text": "x", "scene": "", "years": 2})
	var host = main.get("_chapter_host")
	_check(host != null and is_instance_valid(host) and cal.year == y0 + 2 and Engine.get_process_frames() == f0,
		"headless 升章册页当帧出、跳年当帧结算（%d → %d）" % [y0, cal.year], fails)
	var layers := 0
	for c in main.get_children():
		if c is ChapterCard or c is CutscenePlayer or c is PortBanner:
			layers += 1
	_check(layers == 0, "headless 下 Main 底下没有章节卡 / 过场 / 横幅层（%d）" % layers, fails)
	main._confirm_chapter_sheet()
	main._show_notice_dialog("", "忠肃", "正文", "忠肃")
	host = main.get("_chapter_host")
	_check(host != null and is_instance_valid(host) and str(main.get("_bg_file")) == "bg_end_temple.jpg" and gs.is_ended(),
		"headless 结局册页当帧出、底图换成结局图（%s）" % str(main.get("_bg_file")), fails)
	main.queue_free()


## characters 线：人物设定集接进 GameManager，见面页 / 酒馆人物卡 / 人物志都从它取人取图。
func _check_characters(gm: Node, main_src: String, fails: Array) -> void:
	var all: Array = gm.call("all_characters")
	_check(all.size() > 0 and str(gm.call("get_character", "chen_wenlong").get("tier", "")) == "protagonist",
		"人物设定集载入，get_character 取得到主角", fails)
	var npc_miss: Array = []
	for nid in ["merchant_lin", "pilot_ana", "customs_official"]:
		var c: Dictionary = gm.call("character_for_npc", nid)
		if c.is_empty() or not ResourceLoader.exists(str(c.get("portrait", ""))):
			npc_miss.append(nid)
	_check(npc_miss.is_empty(), "见面三人都认得出人、取得到立绘（缺 %s）" % [npc_miss], fails)
	var crew_miss: Array = []
	for cand in gm.crew_data.get("candidates", []):
		var cid := str(cand.get("id", ""))
		var got: Dictionary = gm.call("character_for_crew", cid)
		if got.is_empty():
			crew_miss.append(cid)
	_check(crew_miss.is_empty(), "酒馆每个候选人都在设定集里（缺 %s）" % [crew_miss], fails)
	# 阵营签：16px 小字压在阵营色上，声明对比度要留出抗锯齿的余量（第 2 轮 UX M5：声明 5.0 的实渲染只剩 3.84）
	var fdefs: Dictionary = gm.characters_data.get("meta", {}).get("faction_def", {})
	var weak_f: Array = []
	for fk in fdefs.keys():
		var fe: Dictionary = fdefs[fk]
		var fc := Color.from_string(str(fe.get("color", "")), Color.BLACK)
		var ft := Color.from_string(str(fe.get("text", "")), Color.BLACK)
		var cr := _contrast(fc, ft)
		if cr < 6.0:
			weak_f.append("%s %.2f" % [fk, cr])
	_check(fdefs.size() >= 8 and weak_f.is_empty(), "阵营签每对字色 / 底色声明对比度 ≥6.0（%d 家，不达标 %s）" % [fdefs.size(), weak_f], fails)
	var npc_src := FileAccess.get_file_as_string("res://scripts/ui/NpcPage.gd")
	var meet_i := npc_src.find("static func show_npc_mode(")
	var meet_j := npc_src.find("\nstatic func ", meet_i + 1)
	var meet := npc_src.substr(meet_i, meet_j - meet_i) if meet_i >= 0 and meet_j > meet_i else ""
	_check(SP.has_tok(meet, "character_for_npc", true) and meet.find("res://assets/sprite_") > SP.tok_find(meet, "character_for_npc", 0, true),
		"见面页立绘先认 characters.json，缺了才回落 sprite_ 旧图", fails)
	var codex_scr = load("res://scripts/ui/CharacterCodex.gd")
	_check(codex_scr != null, "人物志脚本能编译", fails)
	if codex_scr == null or all.is_empty():
		return
	var cx: Control = codex_scr.new()
	root.add_child(cx)
	cx.call("begin", "")
	var cells := cx.find_children("Cell_*", "Button", true, false)
	_check(cells.size() == all.size(), "人物志名册铺满设定集全部人物（%d / %d 格）" % [cells.size(), all.size()], fails)
	cx.call("show_detail", "merchant_lin", false)
	var detail := cx.find_child("Detail", true, false)
	var rel_n := cx.find_children("Rel_*", "", true, false).size()
	_check(detail != null and str(cx.call("current_id")) == "merchant_lin" and rel_n > 0,
		"人物志点开详页，关系一一成签（%d 条）" % rel_n, fails)
	cx.call("go_back")
	_check(str(cx.call("current_id")) == "" and cx.find_child("GridScroll", true, false) != null,
		"人物志详页退回名册", fails)
	cx.call("close_codex")
	_check(cx.is_queued_for_deletion(), "人物志名册页再退就合上", fails)


func _check(cond: bool, msg: String, fails: Array) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	GateReport.check(cond, msg)
	if not cond:
		fails.append(msg)


## WCAG 相对亮度对比度（sRGB 线性化，不计 alpha）。
func _contrast(a: Color, b: Color) -> float:
	var la := _rel_lum(a)
	var lb := _rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _rel_lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## 绢本朱砂钮上的字：必须是 UiTheme.SEAL_TEXT 印面浅字，且对朱砂实测 ≥4.5:1。
func _is_seal_text(c: Color) -> bool:
	return c.is_equal_approx(UiTheme.SEAL_TEXT) and c.get_luminance() > 0.7 and _contrast(c, UiTheme.SEAL) >= 4.5


func _finish(fails: Array) -> void:
	if fails.is_empty():
		print("GODOT SMOKE PASS")
		GateReport.finish("godot_smoke", 0, "GODOT SMOKE PASS")
		quit(0)
	else:
		print("GODOT SMOKE FAIL")
		for f in fails:
			print("  ✗ ", f)
		GateReport.finish("godot_smoke", 1, "GODOT SMOKE FAIL")
		quit(1)
