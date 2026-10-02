extends SceneTree
## 巡检：把主场景挂上，走开局、三港、九个设施页，再量海图。
## 非滚动区的按钮必须落在 1280×720 里；珊瑚主钮聚焦时仍是深字。
## 海图三张航向牌必须整张在画面内，水粮不够时牌上写着告警，账条变高时海图不低于自己的最小高度。
## （合并时按 7f92 晨潮三向改写：原版量的是已拆掉的港口列表。）
## 截图旁证（lane pg）：存盘前按像素种类数 / 直方图熵判一色，一色或拿不到图打 ⚠（不改退出码，--json 记 warn）；
## headless 不截，打一行 ⚠ 说明未判——不再静默跳过；白刃两支（夺船 / 不利）门禁在 _no_render 下打 ⚠ 跳过。
## 接舷题签相位判据（lane w20-a2）：按游戏时比停拍满窗（不看墙钟秒数），最少 3 帧（不按帧率）——
## ——235 fps 实测：真等满停拍的 hold 比约 1.00，没等满题签停在半路收场的约 0.79，判线八成居中两边都不沾
## （改前 0.44 s/T_HOLD 0.55 墙钟边界，w19-g13 遗留④ 偶发一次红、重跑两次都绿）。压帧 / 慢机下相位不变、不随机器飘。
## `DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd -- --bench <N>`：
##   连演 N 场海战（白刃夺船 + 白刃失利各一遍为一场；N 缺省 1、<1 按 1），前场断言与 --json 判词与单跑同口径。
##   bench 只走用户参数、不进注册表命令、不进门禁判词——5/5 连跑照注册表命令 shell 循环（bench 是手工复跑便利，不是口径）。

const VIEW := Vector2(1280, 720)
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
## 截图旁证目录：默认 /tmp/patrol-shots；设 NK1_SHOT_DIR 则落 <该目录>/patrol（与 ShotGate.out_dir 同口径，lane pg3；
## 不 preload shot_gate.gd——gates_md 会把 preload 它的脚本当截图探针要求入册）。
var SHOT_DIR := _shot_dir()
## 一色判据：每 4px 取一点、每通道量化到 16 级，种类 ≤ 2 或香农熵 < 0.1 bit 即判一色（种类 2 兜住纯色恰落量化格边界）。
## 实测：巡检正常页 150–283 种 / 4.2–5.6 bit；最稀的正当画面（墨幕题签帧）41 种 / 0.25 bit；纯色 1 种 / 0 bit。
const FLAT_MAX_KINDS := 2
const FLAT_MIN_ENTROPY := 0.1
const PORTS := ["quanzhou", "fuzhou", "xinghua"]
const FACILITIES := [
	"market", "yamen", "shipyard", "tavern", "inn",
	"guild", "exam", "residence", "temple",
]

var _main: Node
var _fails: Array = []
var _no_render := false
var _shots := 0
var _shot_warns: Array = []


func _init() -> void:
	# 巡检只看界面，不听声音：关掉程序音。本机跑巡检时音频服务器不混音，停下的播放对象收不回，
	# 收尾恰好有声在响就会在退出时报 AudioStreamWAV / AudioStreamPlaybackWAV 泄漏
	_AUDIO.enabled = false
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	# 与 shot_gate.no_render_reason 同判据；不 preload 它，patrol 不是按张数判红的截图门禁（gates_md 按 preload 认册）
	_no_render = DisplayServer.get_name() == "headless" \
		or RenderingServer.get_current_rendering_driver_name() in ["", "dummy"]
	_check_flat_selftest()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for _i in 6:
		await process_frame

	_check_accent_focus()
	_check_screen("开局", true)

	for port in PORTS:
		_main.load_scene(port)
		for _i in 3:
			await process_frame
		_check_screen(port, true)
		var title := ""
		if _main.get("port_title") != null:
			title = str(_main.port_title.text)
		_check(title != "", "%s 港匾有字" % port)
		for fac in FACILITIES:
			var sid := "%s_%s" % [port, fac]
			_main.load_scene(sid)
			for _i in 3:
				await process_frame
			_check_screen(sid, false)
			var head := ""
			if _main.get("scene_title") != null and _main.scene_title.visible:
				head = str(_main.scene_title.text).strip_edges()
			_check(head != "" and head != "未命名设施" and head != "无人应门",
				"%s 标题是「%s」" % [sid, head])

	await _check_sea_chart()
	await _check_market_fold()
	await _check_endgame_pages()
	var bench := _bench_times()
	for i in bench:
		if bench > 1:
			print("  … bench 第 %d/%d 场（白刃夺船 + 白刃失利各一遍）" % [i + 1, bench])
		await _v0928_crew_board_check()
		await _w20a2_melee_lose_check()
	_finish()


## -- --bench <N>：连演 N 场海战（lane w20-a2）。不带 / N < 1 一律 1；参数串坏了（不是整数）当没带。
func _bench_times() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--bench":
			if i + 1 < args.size() and str(args[i + 1]).is_valid_int():
				return maxi(1, int(args[i + 1]))
			return 1
	return 1


## 1280×720 牙行：委办收成一行摘要后，第一张货卡的「卖 1」整颗在滚动视口里（第 2 轮 UX M2：原先在折线下）
func _check_market_fold() -> void:
	var state: Node = root.get_node("GameState")
	state.last_port = "quanzhou"
	_main.load_scene("quanzhou_market")
	for _i in 4:
		await process_frame
	var slips: Node = _main.find_child("BrokerSlips", true, false)
	_check(slips != null and slips.get_child_count() > 0, "牙行有柜上货卡")
	if slips == null or slips.get_child_count() == 0:
		return
	var sell: Button = _find_button(slips.get_child(0), "卖 1")
	var scroll := _scroll_of(slips)
	_check(sell != null and scroll != null, "第一张货卡有「卖 1」且在滚动区里")
	if sell == null or scroll == null:
		return
	var view := scroll.get_global_rect().grow(0.5)
	_check(view.encloses(sell.get_global_rect()), "1280×720 第一张货卡的「卖 1」整颗在视口内（钮 %s，视口 %s）" % [
		sell.get_global_rect(), scroll.get_global_rect()])


## 守城页 / 终局后港口页（第 2 轮 UX B1）：先进泉州港页再进，旧岸门不残留；进出设施一次、重读一次结局，门与账不翻倍，匾不累加
func _check_endgame_pages() -> void:
	var gs: Node = root.get_node("GameState")
	var cal: Node = root.get_node("Calendar")
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	gs.siege_begin()
	gs.chapter = 4
	gs.last_port = "xinghua"
	_main.load_scene("xinghua")
	for _i in 3:
		await process_frame
	_check_siege_band("守城页（先进过泉州）")
	_check_screen("守城页", true)
	_main._on_facility_pressed({"id": "siege_grain", "title": "市场"})
	for _i in 2:
		await process_frame
	_main.load_scene("xinghua")
	for _i in 3:
		await process_frame
	_check_siege_band("守城页（进出市场一次）")
	_check_screen("守城页-回", false)

	gs.from_dict({})
	cal.from_dict({"year": 1285, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	gs.set_flag("sided_pu")
	gs.finish("泉州蒲氏的船", "巡检")
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	var want := "泉州・泉州蒲氏的船"
	_check(str(_main.port_title.text) == want, "终局港名匾「%s」（现「%s」）" % [want, _main.port_title.text])
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	var acts0 := _count_buttons(band.get_node_or_null("ShoreActions")) if band != null else -1
	_check(_count_named(band, "EpilogueSlip") == 1 and _visible_button(band, "重读结局"),
		"终局港口页有一方航海札记与「重读结局」（札记 %d）" % _count_named(band, "EpilogueSlip"))
	_check(not _visible_button(band, "看风") and _count_named(band, "ShoreDoors") <= 1,
		"终局港口页没有「看风」，也没有残留的岸门")
	_check_screen("终局港口页", true)
	_main._on_reread_ending()
	for _i in 2:
		await process_frame
	_main._confirm_chapter_sheet()
	for _i in 3:
		await process_frame
	band = _main.port_mode.get_node_or_null("ShoreBand")
	_check(str(_main.port_title.text) == want, "重读结局后港名匾不累加（现「%s」）" % _main.port_title.text)
	_check(_count_named(band, "EpilogueSlip") == 1, "重读结局后札记仍一方（现 %d）" % _count_named(band, "EpilogueSlip"))
	_check(_count_buttons(band.get_node_or_null("ShoreActions")) == acts0, "重读结局后动作行钮数不变（%d → %d）" % [
		acts0, _count_buttons(band.get_node_or_null("ShoreActions"))])
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _check_siege_band(tag: String) -> void:
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	_check(band != null, "%s 有岸带" % tag)
	if band == null:
		return
	var doors: Node = band.get_node_or_null("ShoreDoors")
	var n_doors := doors.get_child_count() if doors != null else -1
	var hand: PackedStringArray = _main.shore_hand
	_check(n_doors == hand.size() and hand.size() == 5, "%s 门排恰五扇、与手上的卡同数（门 %d，卡 %d）" % [tag, n_doors, hand.size()])
	_check(_visible_label(doors, "囊山"), "%s「囊山」卡看得见" % tag)
	_check(_count_named(band, "SiegeStat") == 1, "%s 城防账一方（现 %d）" % [tag, _count_named(band, "SiegeStat")])
	_check(not _visible_button(band, "看风"), "%s 没有「看风」" % tag)
	_check(not _visible_label(band, "牙行") and not _visible_label(band, "贡院"), "%s 没有残留泉州的岸门" % tag)
	var lf: Control = _main.left_facilities
	var rf: Control = _main.right_facilities
	_check(lf.get_child_count() == 0 and rf.get_child_count() == 0, "%s 旧左右栏清空（%d / %d）" % [
		tag, lf.get_child_count(), rf.get_child_count()])


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _scroll_of(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _count_named(node: Node, n: String) -> int:
	if node == null:
		return 0
	var k := 0
	for c in node.get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		if c.name == n or str(c.name).begins_with(n + "@"):
			k += 1
		k += _count_named(c, n)
	return k


func _count_buttons(node: Node) -> int:
	if node == null:
		return -1
	var k := 0
	for c in node.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion():
			k += 1
	return k


func _visible_button(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Button and (node as Button).text == text and (node as CanvasItem).is_visible_in_tree() \
			and not (node as Node).is_queued_for_deletion():
		return true
	for c in node.get_children():
		if _visible_button(c, text):
			return true
	return false


func _visible_label(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Label and (node as Label).text == text and (node as CanvasItem).is_visible_in_tree() \
			and not (node as Node).is_queued_for_deletion():
		return true
	for c in node.get_children():
		if _visible_label(c, text):
			return true
	return false


func _check_sea_chart() -> void:
	var state: Node = root.get_node("GameState")
	state.last_port = "quanzhou"
	var chart: Node = load("res://scenes/SeaChart.tscn").instantiate()
	root.add_child(chart)
	for _i in 4:
		await process_frame
	_check_heading_cards(chart, "海图未选")
	var hand: PackedStringArray = chart.get("_hand")
	_check(hand.size() == 3, "海图晨潮发三向（现 %d）" % hand.size())
	if hand.size() > 0:
		chart._select_heading(hand[0])
		for _i in 4:
			await process_frame
		_check_heading_cards(chart, "海图选牌")
		_check_chart_floor(chart, "海图选牌")
		var sail: Button = chart.get("sail_button")
		_check(sail != null and not sail.disabled, "海图选牌后「就这一向」可按")
	_shot_chart(chart, "seachart-quanzhou")

	var fleet: Node = root.get_node("Fleet")
	var water0 = fleet.water
	var food0 = fleet.food
	fleet.water = 0
	fleet.food = 0
	chart._refresh_hand()
	for _i in 4:
		await process_frame
	_check_heading_cards(chart, "海图水粮告警")
	_check_chart_floor(chart, "海图水粮告警")
	_check_warn_lines(chart, "海图水粮告警")
	_shot_chart(chart, "seachart-warning")
	# 海图挂在 root 上、压在主场景之上；量完不拆，后面守城页 / 终局港口页的截图就全是海图（09-26 截图点验发现）。
	# 水粮也要归位，免得后面几页的账条写着「水粮 0 日」。
	fleet.water = water0
	fleet.food = food0
	root.remove_child(chart)
	chart.free()
	for _i in 2:
		await process_frame


func _check_heading_cards(chart: Node, tag: String) -> void:
	var row: HBoxContainer = chart.get("heading_row")
	_check(row != null, "%s 有航向牌栏" % tag)
	if row == null:
		return
	var cards := 0
	var stray := 0
	for c in row.get_children():
		if not (c is Control) or (c as CanvasItem).is_queued_for_deletion():
			continue
		var r := (c as Control).get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		cards += 1
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > VIEW.x + 0.5 or r.end.y > VIEW.y + 0.5:
			stray += 1
	_check(cards == 3 and stray == 0, "%s 三张航向牌整张在画面内（牌 %d，越界 %d）" % [tag, cards, stray])


func _check_chart_floor(chart: Node, tag: String) -> void:
	# 海图重制（a6b5a25）后 SeaChart 没有 chart 成员了，海图画面是全屏的 map_container（SubViewportContainer）。
	# 原先 chart.get("chart") 取回 null，函数在第一条 _check 之前就崩掉，下面三条一次都没跑（第 1 轮工程评审）。
	# 取不到就记一条 ✗，不让函数崩；底线取「自身最小高度」与「画面高一半」的大者（全屏海图最小高度是 0，只比它等于恒真）。
	var ch := chart.get("map_container") as Control
	if ch == null:
		_check(false, "%s 海图画面节点 map_container 取得到" % tag)
		return
	var floor_y := maxf(ch.custom_minimum_size.y, VIEW.y * 0.5)
	_check(ch.size.y + 0.5 >= floor_y, "%s 海图不低于 %d（现 %.0f）" % [
		tag, int(floor_y), ch.size.y,
	])
	var sail := chart.get("sail_button") as Button
	if sail == null:
		_check(false, "%s 发舶钮取得到" % tag)
		return
	_check(sail.get_global_rect().end.y <= VIEW.y + 0.5, "%s 发舶在画面内" % tag)
	var back_end := _named_button_end(chart, "回")
	_check(back_end > 0.0 and back_end <= VIEW.y + 0.5, "%s 回港在画面内（底 %.0f）" % [tag, back_end])


func _named_button_end(node: Node, prefix: String) -> float:
	if node is Button and (node as CanvasItem).is_visible_in_tree() and not _inside_scroll(node):
		var btn := node as Button
		if btn.text.begins_with(prefix):
			return btn.get_global_rect().end.y
	for child in node.get_children():
		var found := _named_button_end(child, prefix)
		if found > 0.0:
			return found
	return 0.0


func _check_warn_lines(chart: Node, tag: String) -> void:
	var row: Node = chart.get("heading_row")
	var warn := 0
	var lost := 0
	var labels: Array = []
	_collect_labels(row, labels)
	for l in labels:
		var lbl := l as Label
		if lbl.text != "水粮不够":
			continue
		warn += 1
		if not _color_near(lbl.get_theme_color("font_color", "Label"), UiTheme.CINNABAR):
			lost += 1
	_check(warn > 0 and lost == 0, "%s 牌上写着朱色「水粮不够」（写 %d，失色 %d）" % [tag, warn, lost])


func _collect_labels(node: Node, out: Array) -> void:
	if node == null:
		return
	if node is Label and (node as CanvasItem).is_visible_in_tree():
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)


func _color_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.05 and absf(a.g - b.g) < 0.05 and absf(a.b - b.b) < 0.05


func _shot_chart(_chart: Node, name: String) -> void:
	_save_shot(name)


## 同 ShotGate.out_dir：NK1_SHOT_DIR 为空取默认；相对路径按启动时的 $PWD 展开。
static func _shot_dir() -> String:
	var root := OS.get_environment("NK1_SHOT_DIR").strip_edges()
	if root == "":
		return "/tmp/patrol-shots"
	if not root.is_absolute_path():
		root = OS.get_environment("PWD").path_join(root)
	return root.path_join("patrol")


## 截一张旁证：一色 / 拿不到图记 warn（一色图照存，便于人看）；headless 只计数，收尾统一说明。
func _save_shot(tag: String) -> void:
	_shots += 1
	if _no_render:
		return
	var img := root.get_texture().get_image()
	var bad := _flat_reason(img)
	if bad != "":
		_shot_warns.append("截图旁证 %s %s" % [tag, bad])
	if img == null or img.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])


## 一色返回原因（含种类数与熵），正常返回 ""。
func _flat_reason(img: Image) -> String:
	if img == null or img.is_empty():
		return "拿不到图（视口纹理为空）"
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_RGB8)
	var d := im.get_data()
	var w := im.get_width()
	var hist := {}
	var n := 0
	for y in range(0, im.get_height(), 4):
		for x in range(0, w, 4):
			var i := (y * w + x) * 3
			var k := ((d[i] >> 4) << 8) | ((d[i + 1] >> 4) << 4) | (d[i + 2] >> 4)
			hist[k] = int(hist.get(k, 0)) + 1
			n += 1
	var e := 0.0
	for c in hist.values():
		var p := float(c) / n
		e -= p * log(p) / log(2.0)
	if hist.size() <= FLAT_MAX_KINDS or e < FLAT_MIN_ENTROPY:
		return "画面一色（种类 %d · 熵 %.3f bit）：窗口未绘制或空视口" % [hist.size(), e]
	return ""


## 判据自证：纯色、纯色落在量化格边界的两色抖动都必须判一色，杂色图必须不判。
func _check_flat_selftest() -> void:
	var solid := Image.create(128, 72, false, Image.FORMAT_RGB8)
	solid.fill(Color(0.3, 0.3, 0.3))
	var dither := Image.create(128, 72, false, Image.FORMAT_RGB8)
	var busy := Image.create(128, 72, false, Image.FORMAT_RGB8)
	for y in 72:
		for x in 128:
			var v := 127 + ((x + y) & 1)
			dither.set_pixel(x, y, Color8(v, v, v))
			busy.set_pixel(x, y, Color8((x * 37 + y * 11) & 255, (x * 5 + y * 53) & 255, (x * y) & 255))
	_check(_flat_reason(solid) != "", "截图判据自检：纯色图判一色")
	_check(_flat_reason(dither) != "", "截图判据自检：量化格边界两色抖动判一色")
	_check(_flat_reason(busy) == "", "截图判据自检：杂色图不判一色")
	_check(_flat_reason(null) != "", "截图判据自检：空图判拿不到图")


func _check_accent_focus() -> void:
	var start: Button = _main.start_button
	_check(start != null, "开局有主钮")
	if start == null:
		return
	var focus_col: Color = start.get_theme_color("font_focus_color", "Button")
	var normal_col: Color = start.get_theme_color("font_color", "Button")
	var chip := Button.new()
	UiTheme.style_chip(chip, true)
	if UiTheme.SKIN == "yechao":
		# 夜潮原断言：珊瑚底上深字。
		_check(_is_dark(normal_col), "珊瑚主钮常态是深字")
		_check(_is_dark(focus_col), "珊瑚主钮聚焦仍是深字")
		_check(_is_dark(chip.get_theme_color("font_color", "Button")), "珊瑚小钮常态是深字")
		_check(_is_dark(chip.get_theme_color("font_focus_color", "Button")), "珊瑚小钮聚焦仍是深字")
		_check(_is_dark(chip.get_theme_color("font_pressed_color", "Button")), "珊瑚小钮按下仍是深字")
	else:
		# 绢本：朱砂底上印面浅字，且对朱砂实测 ≥4.5:1。
		_check(_is_seal_text(normal_col), "朱砂主钮常态是印面浅字")
		_check(_is_seal_text(focus_col), "朱砂主钮聚焦仍是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_color", "Button")), "朱砂小钮常态是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_focus_color", "Button")), "朱砂小钮聚焦仍是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_pressed_color", "Button")), "朱砂小钮按下仍是印面浅字")
	chip.free()


func _is_dark(c: Color) -> bool:
	return c.r < 0.25 and c.b > c.r


func _is_seal_text(c: Color) -> bool:
	return c.is_equal_approx(UiTheme.SEAL_TEXT) and c.get_luminance() > 0.7 and _contrast(c, UiTheme.SEAL) >= 4.5


## WCAG 相对亮度对比度（sRGB 线性化，不计 alpha）。
func _contrast(a: Color, b: Color) -> float:
	var la := _rel_lum(a)
	var lb := _rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _rel_lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


func _check_screen(tag: String, shot: bool) -> void:
	var stray := _offscreen_buttons(_main)
	_check(stray.is_empty(), "%s 按钮都在画面里（越界 %s）" % [tag, stray])
	if shot:
		_save_shot(tag)


func _offscreen_buttons(node: Node) -> Array:
	var out: Array = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array) -> void:
	if node is Button and (node as CanvasItem).is_visible_in_tree():
		var btn := node as Button
		if btn.text.strip_edges() != "" and not _inside_scroll(btn):
			var r := btn.get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > VIEW.x + 2.0 or r.end.y > VIEW.y + 2.0:
					out.append("%s「%s」%s" % [btn.name, btn.text.substr(0, 12), r])
	for child in node.get_children():
		_walk(child, out)


func _inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _check(cond: bool, msg: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	GateReport.check(cond, msg)
	if not cond:
		_fails.append(msg)


func _report_shots() -> void:
	if _no_render:
		var why := "截图旁证未判（%d 张跳过）：无渲染环境（DisplayServer=%s），带窗口请 DISPLAY=:2 跑" % [_shots, DisplayServer.get_name()]
		print("  ⚠ ", why)
		GateReport.warn(why)
		return
	for w in _shot_warns:
		print("  ⚠ ", w)
		GateReport.warn(str(w))
	if _shot_warns.is_empty():
		var ok_line := "截图旁证 %d/%d 张非一色 -> %s" % [_shots, _shots, SHOT_DIR]
		print("  ✓ ", ok_line)
		GateReport.check(true, ok_line)
	else:
		var warn_line := "截图旁证 %d/%d 张一色或拿不到图 -> %s" % [_shot_warns.size(), _shots, SHOT_DIR]
		print("  ⚠ ", warn_line)
		GateReport.warn(warn_line)


func _finish() -> void:
	_report_shots()
	if _fails.is_empty():
		print("PATROL SHELL PASS")
		GateReport.finish("patrol_shell", 0, "PATROL SHELL PASS")
		quit(0)
	else:
		print("PATROL SHELL FAIL")
		for f in _fails:
			print("  ✗ ", f)
		GateReport.finish("patrol_shell", 1, "PATROL SHELL FAIL")
		quit(1)


## 白刃两条窗口支路（w20-a2 一并立 / 稳，共用 _blade_battle 布景）：胜路 crew 线 09-29 返修（复核 4），败路 g1 遗留②。
## 09-28 修前末艘夺下当帧就出战：题签只留 1 帧、墨边写「战罢」。这两条原先只在 git 忽略的验收探针里，合并后没门禁拦，这里进巡检。
## 真起一场海战（海寇只刷一艘：首艘即末艘），冻住敌炮；胜路敌船水手清零保证白刃必胜，败路旗舰水手压到 1、敌船水手 / 披甲
## 抬高保证白刃必不利（落空 / 击退 / 脱钩都走同一支：解开钩缆、题签「脱钩」、不收战、敌船仍在场）。主场景先藏起、演完还原，船队与战况复原。
## lane fx8：本地线 combat06 士气挂件逐物理帧读敌船 crew，清零会记成伤亡过半、再加被钩——接舷停拍 0.42 s 里敌船降幡，
## 士气簿裁决 enemy_struck 当场收战（墨边「受降」、夺船题签一帧不画），走的是受降一路。清零前先停掉挂件轮询（降幡 / 裁决
## 都在它的物理帧里），两条路都先停挂件：胜路确定地走「白刃夺下末艘」、败路确定地走「白刃判负」，收战 / 不收战按路断言。
## 题签全显判据（lane w20-a2，g13 遗留④ 0.44 s 墙钟边界偶发红改相位帧）：对战时按 process delta 封顶 8/60 s 折算「窗口帧数」，
## 全显窗口 = T_HOLD + T_FADE（_play_resolve 先停 T_HOLD 再淡 T_FADE，全显帧 = 模 1）；全显帧数 ≥ 折算 × 0.8 才算停满，
## 不看墙钟秒数、不按帧率——压帧 / 慢机下相位不变，快机 235 fps 也不因 delta 偏大少记帧。败路题签「脱钩」同口径。
## lane w19-g1：有题签就不出浮字（crew 线 9e35254 定，09-30 合并丢了）——题签在屏的每一帧，WorldMap 中央浮字不许亮着同一件事
## 那句（胜路「……并入本队。」 / 败路题签副题同句）；修前浮字与题签同屏，这条红。败路同判据、不许空转成绿。
const _CrewStage := preload("res://tools/combat_probe_stage.gd")
const _CrewBoarding := preload("res://scripts/combat/BoardingStage.gd")


## 题签全显这一帧：WorldMap 中央浮字（_notice）若亮着同一件事那句（「并入本队」或与题签副题同句）返回描述，否则空串。
## key 传"capture"只认并入本队（胜路），传其余值只认与副题同句（败路不利，副题 = MeleeResolve 的 summary 头句）。
func _crew_capture_dup(wm, key := "capture") -> String:
	if wm == null or not is_instance_valid(wm):
		return ""
	var nt = wm.get("_notice")
	if not (nt is Label) or not is_instance_valid(nt):
		return ""
	var lab := nt as Label
	if not lab.is_visible_in_tree() or lab.modulate.a <= 0.01:
		return ""
	var st: Node = _CrewStage.boarding_stage(self, wm)
	var sub = st.get("_sub") if st != null else null
	var sub_txt := str((sub as Label).text) if sub is Label else ""
	var same := sub_txt != "" and lab.text == sub_txt
	if (key == "capture" and lab.text.find("并入本队") >= 0) or same:
		return "浮字「%s」与题签副题「%s」同屏" % [lab.text, sub_txt]
	return ""


## 白刃布景 + 金创（w20-a2：胜 / 败两路共用；setup 闭包在刷出敌船之后、接舷之前调，各配本路的必胜 / 必败形）。
## 返回 {"ref", "result", "foe", "saved_ships", "saved_battle", "saved_morale", "main_vis"}；_no_render / 中途空转由调用方收尾。
func _blade_battle(setup: Callable) -> Dictionary:
	var gm: Node = root.get_node("GameManager")
	var fleet: Node = root.get_node("Fleet")
	var saved_ships: Array = (fleet.get("ships") as Array).duplicate(true)
	var saved_battle: Dictionary = (gm.get("pending_battle") as Dictionary).duplicate(true)
	var saved_morale: int = int(fleet.get("morale"))
	var consts: Dictionary = (load("res://scripts/SeaChart.gd") as GDScript).get_script_constant_map()
	var entry: Dictionary = (consts.get("PIRATE_ENEMY", {}) as Dictionary).duplicate()
	entry["count"] = 1
	fleet.set("ships", [])
	fleet.call("add_ship", "fu_ship_medium", "")
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 400.0, "enemy": [entry],
		"sea_name": "泉州外海", "source": {"scene": "patrol_shell", "event": "pirate"}})
	var main_vis: bool = _main is CanvasItem and (_main as CanvasItem).visible
	if _main is CanvasItem:
		(_main as CanvasItem).visible = false
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var ref: WeakRef = weakref(wm)
	_CrewStage.freeze_enemy_fire(wm)
	var result: Array = []
	wm.connect("battle_finished", func(o: String, d: Dictionary) -> void: result.append([o, d]))
	# 入战墨边（挂在 wm 下）收了再接舷
	await _CrewStage.wait_until(self, func() -> bool:
		return ref.get_ref() == null or _CrewStage.letterbox_under(self, ref.get_ref()) == null)
	var foe: Node2D = null
	if ref.get_ref() != null:
		for c in wm.get_children():
			if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion():
				foe = c
	if foe != null:
		var tracker = wm.get("_morale")
		if tracker is Node:
			(tracker as Node).process_mode = Node.PROCESS_MODE_DISABLED
		setup.call(foe, wm)
		foe.set_physics_process(false)
		foe.position = (wm.get("ship") as Node2D).position + Vector2(95, 0)
	return {"ref": ref, "result": result, "foe": foe,
		"saved_ships": saved_ships, "saved_battle": saved_battle,
		"saved_morale": saved_morale, "main_vis": main_vis}


## 相位判据（w20-a2，g13 遗留④）。棋检（title 题签 alpha ≥ 0.99）逐帧累积游戏时：真等满停拍的 hold 比（实测全显游戏时
## ÷ _play_resolve 满窗 T_HOLD + 淡出首帧一格 8/60）在 235 fps 下约 1.00，没等满题签半路收场的约 0.79；按游戏时不看墙钟
## 秒数、看 full_frames 下限不按帧率（压帧下相位不变）。235 fps 高帧下 delta 多半格吃亏，判线取八成居中，两边都不沾。
## 返回 [达标, "注记", 全显帧数, 浮字红因, 判没判上浮字]。
func _blade_hold_frames(ref: WeakRef, title: String, dup_key: String) -> Array:
	var why: String = await _CrewStage.wait_drawn(self, func() -> bool:
		var cap: Array = _CrewStage.board_caption(self, ref.get_ref())
		return cap[0] == title and float(cap[1]) >= 0.99, func() -> bool: return ref.get_ref() == null, 8000)
	if why != "":
		return [false, why, 0, "", false]
	var full_frames := 1
	var dup_note := _crew_capture_dup(ref.get_ref(), dup_key)
	var dup_measured := true
	var game_hold := root.get_process_delta_time()
	while ref.get_ref() != null:
		await process_frame
		await RenderingServer.frame_post_draw
		var cap: Array = _CrewStage.board_caption(self, ref.get_ref())
		if cap[0] == title and float(cap[1]) >= 0.99:
			game_hold += root.get_process_delta_time()
			full_frames += 1
			if dup_note == "":
				dup_note = _crew_capture_dup(ref.get_ref(), dup_key)
		elif cap[0] == "" or float(cap[1]) < 0.99:
			# 淡出起步的那一帧：这一帧的 delta 里前一段题签仍全显（题签换了 title 也一样——演示过错位则判红）
			game_hold += root.get_process_delta_time()
			break
		# 演示中换了 title（脱钩题签被顶 / 又翻了面）：按错位判红（相位会跟着窗口变，不为墙钟飘）
	var full_window := _CrewBoarding.T_HOLD + 8.0 / 60.0
	var hold_ratio := game_hold / full_window
	var ok := hold_ratio >= 0.8 and full_frames >= 3
	var note := "全显 %d 帧、游戏时 %.2f s ÷ 满窗 %.2f s = %.2f（T_HOLD %.2f + 淡出首帧一格 8-60）" % [
		full_frames, game_hold, full_window, hold_ratio, _CrewBoarding.T_HOLD]
	return [ok, note, full_frames, dup_note, dup_measured]


## 布景收尾 + 现场还原（两路同）。
func _blade_teardown(ctx: Dictionary) -> void:
	var gm: Node = root.get_node("GameManager")
	var fleet: Node = root.get_node("Fleet")
	_CrewStage.teardown(self, (ctx["ref"] as WeakRef).get_ref(), gm)
	await process_frame
	await process_frame
	fleet.set("ships", ctx["saved_ships"])
	fleet.set("morale", ctx["saved_morale"])
	gm.set("pending_battle", ctx["saved_battle"])
	root.canvas_transform = Transform2D()
	if _main is CanvasItem:
		(_main as CanvasItem).visible = bool(ctx["main_vis"])


func _v0928_crew_board_check() -> void:
	if _no_render:
		var why_skip := "末艘夺船题签与出战墨边未判：无渲染环境（DisplayServer=%s）" % DisplayServer.get_name()
		print("  ⚠ ", why_skip)
		GateReport.warn(why_skip)
		return
	var ctx: Dictionary = await _blade_battle(func(foe: Node, _wm: Node) -> void:
		# 胜路：水手清零，白刃必胜（士气挂件已被 _blade_battle 停掉，不会走红受降一路，来路见段头注）
		foe.set("crew", 0))
	var ref: WeakRef = ctx["ref"]
	var result: Array = ctx["result"]
	var foe: Node2D = ctx["foe"]
	_check(foe != null, "巡检海战刷出一艘海寇（首艘即末艘）")
	var hold_ok := false
	var hold_note := "未量到"
	var dup_note := ""
	var dup_measured := false  # 题签全显过、逐帧看过浮字才算判了（没画到题签不许空转成绿）
	if foe != null:
		var wm: Node = ref.get_ref()
		wm.call("_board_enemy", foe)
		var got: Array = await _blade_hold_frames(ref, "夺船", "capture")
		hold_ok = bool(got[0])
		hold_note = str(got[1])
		dup_note = str(got[3])
		dup_measured = bool(got[4])
		if hold_ok:
			_save_shot("crew_末艘夺船题签")
	_check(hold_ok, "末艘「夺船」题签停满 T_HOLD %.2f s 的八成（游戏时相位判据；%s）" % [_CrewBoarding.T_HOLD, hold_note])
	_check(dup_measured and dup_note == "",
		"末艘「夺船」题签在屏时不出同一件事的浮字（有题签就不出浮字；%s）"
			% (dup_note if dup_note != "" else ("题签全显各帧浮字未亮夺船句" if dup_measured else "题签没画到，无从判")))
	# 出战墨边挂在布景的父节点（root）下：等题签整行擦出再读题
	var lbref: Array = [null]
	var why3: String = await _CrewStage.wait_drawn(self, func() -> bool:
		var lb: Node = _CrewStage.letterbox_under(self, root)
		if lb == null:
			return false
		lbref[0] = weakref(lb)
		var sub: Label = lb.get("_sub")
		var clip: Control = lb.get("_clip")
		return sub != null and sub.modulate.a >= 0.99 and clip != null and clip.modulate.a >= 0.99, Callable(), 8000)
	var lbn: Node = (lbref[0] as WeakRef).get_ref() if lbref[0] != null else null
	var exit_title := str(lbn.get("title")) if lbn != null else ""
	if why3 == "":
		_save_shot("crew_出战墨边_夺船")
	var d: Dictionary = result[0][1] if result.size() == 1 else {}
	var fates: Array = (d.get("fates", []) as Array).map(func(f) -> String: return str((f as Dictionary).get("fate", "")))
	_check(why3 == "" and exit_title.ends_with("・夺船") and result.size() == 1 and result[0][0] == "win" and bool(d.get("boarded", false))
			and fates == ["boarded"],
		"末艘夺下以 boarded 出战、出战墨边写「%s」（以「・夺船」结尾；下场 %s；%s）" % [exit_title, fates, why3 if why3 != "" else "墨边已擦出"])
	await _blade_teardown(ctx)


## 白刃失利支（lane w20-a2，g1 遗留②）：旗舰水手压 1、敌船水手 / 披甲抬满，MeleeResolve 必出非 win 的 legacy
## （击退 / 脱钩 / 落空都走同一支：解开钩缆放走敌船、题签「脱钩」——BoardingStage.title_for("lose")、不收战、墨边不上、
## battle_finished 一帧不响）。断言该出现的那一格真出现（题签「脱钩」停满、敌仍在场、无结束），不该出现的没出现
## （没有「夺船」、没有出墨边、没有出战墨边）。没法触发 _MeleeResolve.resolve 判 lose 的反向变异：把题签判据改去等"夺船" / 改回墙钟
func _w20a2_melee_lose_check() -> void:
	if _no_render:
		var why_skip := "白刃失利题签与「不收战」未判：无渲染环境（DisplayServer=%s）" % DisplayServer.get_name()
		print("  ⚠ ", why_skip)
		GateReport.warn(why_skip)
		return
	var ctx: Dictionary = await _blade_battle(func(foe: Node, _wm: Node) -> void:
		# 败路：旗舰水手压到 1（lose_crew_random 每船至少留 1 人保火种），攻方气尽人少必被折回 lose；
		# 敌披甲 / 弓手拉满是把「落空 / 击退 / 脱钩」三种都盖住，不是只押一种
		foe.set("crew", 60)
		foe.set("melee_armor", 0.9)
		foe.set("melee_archers", 0.9))
	var ref: WeakRef = ctx["ref"]
	var result: Array = ctx["result"]
	var foe: Node2D = ctx["foe"]
	_check(foe != null, "白刃失利巡检海战刷出一艘海寇（攻方水手压 1 必不利）")
	var fleet: Node = root.get_node("Fleet")
	var crew_before := int(fleet.call("total_crew")) if foe != null else -1
	for s in fleet.get("ships"):
		s["crew"] = 1
	var hold_ok := false
	var hold_note := "未量到"
	var dup_note := ""
	var dup_measured := false
	if foe != null:
		var wm: Node = ref.get_ref()
		wm.call("_board_enemy", foe)
		var got: Array = await _blade_hold_frames(ref, "脱钩", "lose")
		hold_ok = bool(got[0])
		hold_note = str(got[1])
		dup_note = str(got[3])
		dup_measured = bool(got[4])
		if hold_ok:
			_save_shot("w20a2_白刃失利题签")
	_check(hold_ok, "白刃失利「脱钩」题签停满 T_HOLD %.2f s 的八成（游戏时相位判据；失地那格：%s）" % [_CrewBoarding.T_HOLD, hold_note])
	_check(dup_measured and dup_note == "",
		"白刃失利题签在屏时不出同一件事的浮字（脱钩句不上浮字；%s）"
			% (dup_note if dup_note != "" else ("题签全显各帧浮字未亮脱钩句" if dup_measured else "题签没画到，无从判")))
	# 不收战 / 敌船仍在 / 出战墨边不出场：等 0.9 s 游戏时（题签 T_HOLD + 淡出都过了），期间任何一条出现即红
	await _CrewStage.wait_until(self, func() -> bool:
		return ref.get_ref() == null, 900)
	var wm2: Node = ref.get_ref()
	var foe_still := wm2 != null and foe != null and is_instance_valid(foe) and not foe.is_queued_for_deletion()
	var cap2: Array = _CrewStage.board_caption(self, wm2)
	_check(wm2 != null and bool(wm2.get("resolved")) == false and result.is_empty() and foe_still,
		"白刃失利不收战：WorldMap 未结算、battle_finished 一帧不响、敌船仍在场（resolved %s · 结果 %d · 敌在场 %s）" % [
			("?" if wm2 == null else str(bool(wm2.get("resolved")))), result.size(), foe_still])
	_check(cap2[0] != "夺船", "白刃失利没有「夺船」题签（题名「%s」）" % cap2[0])
	_check(_CrewStage.letterbox_under(self, root) == null, "白刃失利不出出战墨边（只有末艘收战才上墨边）")
	await _blade_teardown(ctx)
