extends Control

@onready var background: TextureRect = $Background
@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var status_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var message_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel

@onready var title_mode: Control = $HBoxContainer/CenterArea/TitleMode
@onready var main_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/MainTitle
@onready var sub_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/SubTitle
@onready var start_button: Button = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/StartButton

@onready var investigation_mode: PanelContainer = $HBoxContainer/CenterArea/InvestigationMode
@onready var scene_title: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/BodyText
@onready var interactive_label: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/InteractiveLabel
@onready var interactive_container: HFlowContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/Scroll/VBoxContainer/ChoicesLabel

@onready var port_mode: Control = $HBoxContainer/CenterArea/PortMode
@onready var left_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/LeftFacilities
@onready var right_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/RightFacilities
@onready var port_title: Label = $HBoxContainer/CenterArea/PortMode/PortTitle

@onready var npc_mode: Control = $HBoxContainer/CenterArea/NPCMode
@onready var npc_name_lbl: Label = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCName
@onready var npc_dialog_lbl: RichTextLabel = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCDialog
@onready var npc_actions: VBoxContainer = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCActions
@onready var npc_portrait: TextureRect = $HBoxContainer/CenterArea/NPCMode/HBox/PortraitRect

var current_scene_id: String = ""
var previous_scene_id: String = ""  # 死胡同场景兜底用：只记一层，不做完整历史栈
var title_button_connected: bool = false
## 牙行当前选中的船 index（多船分装用），进牙行时重置为旗舰
var _market_ship: int = 0
## 账条暂时写入的容器。船屋条数多，先收进内滚，离开钮留在外面。
var _slip_host: Node = null
## 见面册页上的话。原 RichTextLabel 在这栏里排不出行，改用能折行的 Label。
var _npc_speech: Label
## 航海日志册页。AcceptDialog 会把三卷撑出 1280 宽的窗口。
var _save_host: Control

const FACILITY_SUFFIXES := [
	"_market", "_yamen", "_shipyard", "_tavern", "_inn",
	"_guild", "_exam", "_residence", "_temple",
]
## 港卡 id 是 city_*，动态设施页是 {港}_{后缀}。city_inn / city_guild
## 也会 ends_with 对应后缀，load_scene 必须跳过 city_ 前缀，否则收成
## _setup_inn("city")、并盖掉兴化序章调查页。
const REMAPPED_FACILITIES := [
	"city_market", "city_yamen", "city_shipyard", "city_tavern", "city_inn",
	"city_guild", "city_exam", "city_residence", "city_temple",
]
## 兴化序章仍进 scenes.json 调查页；游戏港改走动态设施。
const PROLOGUE_ONLY_FACILITIES := ["city_guild", "city_exam", "city_residence"]

## 无剧情场景的港口使用的通用设施。卡序与泉州/兴化港卡一致（九卡），
## 避免博多缺行会行情或寺观勘见。
const GENERIC_FACILITIES := [
	{"id": "city_shipyard", "title": "船屋", "subtitle": "修船・补给・船行"},
	{"id": "city_guild", "title": "行会", "subtitle": "行情・信用"},
	{"id": "city_tavern", "title": "酒馆", "subtitle": "打听消息"},
	{"id": "city_market", "title": "牙行", "subtitle": "货殖交易"},
	{"id": "city_inn", "title": "旅店", "subtitle": "歇息・候风"},
	{"id": "city_exam", "title": "贡院", "subtitle": "誊录・观礼"},
	{"id": "city_residence", "title": "住宅", "subtitle": "账本・歇息"},
	{"id": "city_temple", "title": "寺观", "subtitle": "勘见・拓碑"},
	{"id": "city_yamen", "title": "市舶司", "subtitle": "验引・抽解"},
]


func _ready() -> void:
	UiTheme.apply(self)
	_mount_veil()
	_inset_stage()
	message_label.text = ""
	status_label.bbcode_enabled = true
	message_label.bbcode_enabled = true
	scene_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_text.fit_content = true
	body_text.scroll_active = false
	body_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 防御：异常路径可能残留未清理的海战上下文，回港时清空
	GameManager.pending_battle = {}
	GameManager.monthly_notice.connect(_on_monthly_notice)
	# 「绢本墨笔」：面板不透底图，后加的按钮由 hook 自动带样式
	left_panel.add_theme_stylebox_override("panel", UiTheme.panel())
	investigation_mode.add_theme_stylebox_override("panel", UiTheme.panel())
	UiTheme.style_button(start_button, true)
	start_button.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	UiTheme.hook_buttons(choices_container, true)
	choices_container.add_theme_constant_override("separation", 6)
	UiTheme.hook_buttons(right_facilities)
	UiTheme.hook_buttons(npc_actions)
	UiTheme.style_heading(scene_title)
	UiTheme.style_body(body_text)
	UiTheme.style_body(status_label)
	UiTheme.style_body(message_label)
	message_label.add_theme_stylebox_override("normal", UiTheme.log_well())
	UiTheme.style_section_label(choices_label)
	UiTheme.style_section_label(interactive_label)
	UiTheme.style_heading(port_title, true)
	UiTheme.style_heading(npc_name_lbl)
	UiTheme.style_body(npc_dialog_lbl)
	_dress_ledger()
	_dress_title()
	_mount_port_plaque()
	_frame_portrait()
	_dress_npc_sheet()
	update_status_panel()
	call_deferred("start_game")


func _mount_veil() -> void:
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = UiTheme.VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	move_child(veil, background.get_index() + 1)
	background.modulate = Color(0.92, 0.86, 0.76)


func _inset_stage() -> void:
	var box := $HBoxContainer
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = -16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 14)


func _dress_ledger() -> void:
	var title := $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/TitleLabel
	title.text = "船籍簿"
	UiTheme.style_heading(title)
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/HSeparator
	if rule is Separator:
		var line := StyleBoxLine.new()
		line.color = Color(UiTheme.GOLD, 0.45)
		line.thickness = 1
		rule.add_theme_stylebox_override("separator", line)


func _dress_title() -> void:
	main_title.add_theme_font_override("font", UiTheme.font())
	main_title.add_theme_font_size_override("font_size", 52)
	main_title.add_theme_color_override("font_color", UiTheme.GOLD)
	sub_title.add_theme_font_override("font", UiTheme.font())
	sub_title.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	sub_title.add_theme_color_override("font_color", UiTheme.TEXT)
	sub_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if title_mode.get_node_or_null("TitlePlaque") != null:
		return
	var plaque := Panel.new()
	plaque.name = "TitlePlaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.set_anchors_preset(Control.PRESET_CENTER)
	plaque.offset_left = -360
	plaque.offset_top = -210
	plaque.offset_right = 360
	plaque.offset_bottom = 190
	plaque.add_theme_stylebox_override("panel", UiTheme.plaque())
	title_mode.add_child(plaque)
	title_mode.move_child(plaque, 0)


func _mount_port_plaque() -> void:
	var holder := CenterContainer.new()
	holder.name = "PortPlaqueHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_left = -260
	holder.offset_top = 18
	holder.offset_right = 260
	holder.offset_bottom = 78
	port_mode.add_child(holder)
	port_mode.move_child(holder, 0)
	var plaque := PanelContainer.new()
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_theme_stylebox_override("panel", UiTheme.plaque())
	holder.add_child(plaque)
	port_title.get_parent().remove_child(port_title)
	plaque.add_child(port_title)
	port_title.layout_mode = 2
	port_title.offset_left = 0
	port_title.offset_top = 0
	port_title.offset_right = 0
	port_title.offset_bottom = 0
	port_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	port_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _frame_portrait() -> void:
	var parent := npc_portrait.get_parent()
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(280, 0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	var idx := npc_portrait.get_index()
	parent.remove_child(npc_portrait)
	parent.add_child(frame)
	parent.move_child(frame, idx)
	frame.add_child(npc_portrait)
	npc_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## 见面是中栏里的一册：对话落在熟漆上，画像没有就不留空框。
func _dress_npc_sheet() -> void:
	var hbox: HBoxContainer = npc_mode.get_node("HBox")
	hbox.offset_left = 16
	hbox.offset_top = 16
	hbox.offset_right = -16
	hbox.offset_bottom = -16
	var dialog := npc_name_lbl.get_parent()
	var sheet := PanelContainer.new()
	sheet.name = "DialogSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	var idx := dialog.get_index()
	var parent := dialog.get_parent()
	parent.remove_child(dialog)
	parent.add_child(sheet)
	parent.move_child(sheet, idx)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	sheet.add_child(margin)
	dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(dialog)
	UiTheme.style_heading(npc_name_lbl)
	npc_dialog_lbl.visible = false
	npc_actions.add_theme_constant_override("separation", 6)


## 调查页平时铺满中栏；卷首 cg_ 收成居中的册页，左边船籍簿让开。
func _frame_sheet(floating: bool) -> void:
	left_panel.visible = not floating
	if floating:
		investigation_mode.anchor_left = 0.5
		investigation_mode.anchor_top = 0.5
		investigation_mode.anchor_right = 0.5
		investigation_mode.anchor_bottom = 0.5
		investigation_mode.offset_left = -430
		investigation_mode.offset_top = -268
		investigation_mode.offset_right = 430
		investigation_mode.offset_bottom = 268
	else:
		investigation_mode.anchor_left = 0.0
		investigation_mode.anchor_top = 0.0
		investigation_mode.anchor_right = 1.0
		investigation_mode.anchor_bottom = 1.0
		investigation_mode.offset_left = 0
		investigation_mode.offset_top = 0
		investigation_mode.offset_right = 0
		investigation_mode.offset_bottom = 0
	scene_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if floating else HORIZONTAL_ALIGNMENT_LEFT


func _on_monthly_notice(text: String) -> void:
	log_msg(text)
	update_status_panel()


func start_game() -> void:
	if GameState.has_flag("return_to_port"):
		GameState.flags.erase("return_to_port")
		load_scene(GameState.last_port)
	else:
		var start_id = GameManager.scenes_data.get("start_scene", "cg_title")
		load_scene(start_id)


func log_msg(text: String) -> void:
	message_label.text = text + "\n\n" + message_label.text


# ══════════════════════════════════════════════════════
#  状态面板
# ══════════════════════════════════════════════════════

func update_status_panel() -> void:
	var cargo_str := ""
	if Fleet.cargo.is_empty():
		cargo_str = "空\n"
	else:
		for gid in Fleet.cargo.keys():
			var e: Dictionary = Fleet.cargo[gid]
			cargo_str += "%s ×%d\n" % [GameManager.get_good_name(gid), e.get("qty", 0)]

	var cap_used := Fleet.used_capacity()
	var cap_total := Fleet.total_capacity()
	var supply_d := Fleet.supply_days()
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY

	var permit_str := "【有】合法" if GameState.has_customs_permit else "【无】黑市"
	var contraband := GameState.contraband_units()
	var gold := UiTheme.hex(UiTheme.GOLD)
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)

	var t := "[color=#%s][b]%s[/b][/color]\n[color=#%s]%s[/color]\n" % [
		gold, Calendar.get_date_string(), dim, Calendar.get_monsoon_desc(),
	]
	t += "金钱　[b]%d[/b]\n" % GameState.money
	if GameState.debt > 0:
		t += "[color=#%s]欠债　%d[/color]\n" % [UiTheme.hex(UiTheme.HONEY), GameState.debt]
	t += "名声　%d　%s\n" % [GameState.fame, GameState.title_name()]
	if GameState.network != 0 or GameState.merchant_credit != 0:
		t += "人脉　%d　海商信用　%d\n" % [GameState.network, GameState.merchant_credit]
	t += "[color=#%s][b]舰队[/b][/color]\n船数　%d　水手　%d\n舱位　%d / %d 料\n耐久　%d / %d\n士气　%d\n" % [
		gold,
		Fleet.ships.size(), Fleet.total_crew(),
		int(cap_used), int(cap_total),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水　%d　粮　%d　[color=#%s]足 %d 日[/color]\n" % [
		Fleet.water, Fleet.food, UiTheme.hex(supply_color), supply_d,
	]

	if not Crew.hired.is_empty():
		t += "[color=#%s][b]职事[/b][/color]\n" % gold
		for c in Crew.roster():
			t += "%s %s%s\n" % [
				Crew.role_def(c.get("role", "")).get("name", ""),
				c.get("name", ""), _stars(int(c.get("level", 1))),
			]
		var wage := Crew.monthly_wage()
		var wage_color := UiTheme.HONEY if Crew.unpaid_months > 0 else UiTheme.TEXT
		t += "[color=#%s]月俸共 %d" % [UiTheme.hex(wage_color), wage]
		if Crew.unpaid_months > 0:
			t += "　已欠 %d 月" % Crew.unpaid_months
		t += "[/color]\n"
	t += "[color=#%s][b]市舶[/b][/color]\n蒲氏关注　%d\n货引　%s\n" % [
		gold, GameState.pu_attention, permit_str,
	]
	if contraband > 0:
		t += "[color=#%s]舱底违禁　%d 件[/color]\n" % [UiTheme.hex(UiTheme.CINNABAR), contraband]
	t += "[color=#%s][b]船舱[/b][/color]\n%s" % [gold, cargo_str]

	# 多船时追加每船明细
	if Fleet.ships.size() > 1:
		for i in range(Fleet.ships.size()):
			var s: Dictionary = Fleet.ships[i]
			var per_ship := ""
			var sc: Dictionary = s.get("cargo", {})
			if sc.is_empty():
				per_ship = "空"
			else:
				for gid in sc.keys():
					per_ship += "%s ×%d　" % [GameManager.get_good_name(gid), sc[gid].get("qty", 0)]
			var crew_str := "水手 %d/%d" % [Fleet.ship_crew(i), Fleet.ship_crew_max(i)]
			var crew_color := UiTheme.hex(UiTheme.TEXT)
			if Fleet.ship_crew(i) < Fleet.ship_crew_min(i):
				crew_color = UiTheme.hex(UiTheme.CINNABAR)
				crew_str += "（缺 %d 人）" % (Fleet.ship_crew_min(i) - Fleet.ship_crew(i))
			t += "[i]└ %s（%s）%d/%d 料　帆Lv%d/甲Lv%d　[color=#%s]%s[/color]　%s[/i]\n" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_cargo_bulk(i)), int(Fleet.ship_capacity(i)),
				Fleet.sail_level(i), Fleet.armor_level(i),
				crew_color, crew_str, per_ship,
			]

	# 章节目标：不写出来玩家不会知道怎样才能开出下一片海
	var prog := GameState.chapter_progress()
	t += "[color=#%s][b]第%s章・%s[/b][/color]\n" % [
		UiTheme.hex(UiTheme.GOLD),
		_cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
	]
	if prog.get("ended", false):
		t += "[color=#%s]了结　%s[/color]\n" % [
			UiTheme.hex(UiTheme.GOLD), prog.get("ending_title", GameState.ending_title()),
		]
	elif prog.get("final", false):
		t += "[color=#%s]终章・可了结[/color]\n" % UiTheme.hex(UiTheme.TEXT_DIM)
		for it in prog.get("items", []):
			var emark: String = "[color=#%s]✓[/color]" % UiTheme.hex(UiTheme.MOSS) if it["done"] else "・"
			if int(it["need"]) > 1:
				t += "%s %s %d/%d\n" % [emark, it["label"], it["current"], it["need"]]
			else:
				t += "%s %s\n" % [emark, it["label"]]
	else:
		for it in prog.get("items", []):
			var mark: String = "[color=#%s]✓[/color]" % UiTheme.hex(UiTheme.MOSS) if it["done"] else "・"
			if int(it["need"]) > 1:
				t += "%s %s %d/%d\n" % [mark, it["label"], it["current"], it["need"]]
			else:
				t += "%s %s\n" % [mark, it["label"]]

	status_label.text = t


# ══════════════════════════════════════════════════════
#  场景加载
# ══════════════════════════════════════════════════════

func load_scene(scene_id: String) -> void:
	if current_scene_id != "" and current_scene_id != scene_id:
		previous_scene_id = current_scene_id
	current_scene_id = scene_id

	# 设施场景由代码动态生成，不走 scenes.json。
	# city_* 是序章共用 id，不能按后缀收成 _setup_*(「city」)。
	if not scene_id.begins_with("city_"):
		for suffix in FACILITY_SUFFIXES:
			if scene_id.ends_with(suffix):
				_setup_dynamic_scene(scene_id, suffix)
				return

	var scene_data = GameManager.get_scene_by_id(scene_id)
	if not scene_data.is_empty() and not GameState.scene_unlocked(scene_data):
		log_msg("这条路还没到时候。")
		var fallback := GameState.last_port
		if fallback == "" or fallback == scene_id:
			fallback = "quanzhou"
		load_scene(fallback)
		return
	if scene_data.is_empty():
		# scenes.json 只为少数港口写了剧情场景；其余按 ports.json 生成通用港口界面
		var pdef := GameManager.get_port_by_id(scene_id)
		if not pdef.is_empty():
			GameState.last_port = scene_id
			_apply_background("port", scene_id)
			_setup_port_mode({
				"title": pdef.get("name", scene_id),
				"facilities": GENERIC_FACILITIES,
			})
			_on_enter_port(scene_id)
			return
		_setup_missing_scene(scene_id)
		return

	var type = scene_data.get("type", "scene")
	var loc = scene_data.get("location", "")
	if str(scene_id).begins_with("cg_"):
		_set_background_file("bg_world_map.jpg")
	else:
		_apply_background(type, loc)

	if type == "title":
		_setup_title_mode(scene_data)
	elif type == "port":
		GameState.last_port = scene_id
		_setup_port_mode(scene_data)
		_on_enter_port(scene_id)
	else:
		_setup_investigation_mode(scene_data)


## 港口 → 背景图
const PORT_BG := {
	"quanzhou": "bg_quanzhou_harbor.jpg",
	"xinghua": "bg_xinghua_study.jpg",
	"xinghua_harbor": "bg_xinghua_harbor.jpg",
	"fuzhou": "bg_fuzhou_yamen.jpg",
	"hakata": "bg_arab_mosque.jpg",
	"ryukyu": "bg_reef_bay.jpg",
	"penghu": "bg_reef_bay.jpg",
	"kagoshima": "bg_beacon_tower.jpg",
	"champa": "bg_temple_gate.jpg",
	"guangzhou": "bg_arab_mosque.jpg",
}

## 设施后缀 → 背景图
const FACILITY_BG := {
	"_market": "bg_yahang.jpg",
	"_shipyard": "bg_shipyard.jpg",
	"_yamen": "bg_customs_room.jpg",
	"_tavern": "bg_xinghua_wine_shed.jpg",
	"_inn": "bg_relay_post.jpg",
	"_guild": "bg_quanzhou_ledger.jpg",
	"_exam": "bg_academy.jpg",
	"_residence": "bg_xinghua_study.jpg",
	"_temple": "bg_temple_library.jpg",
}


func _apply_background(type: String, loc: String) -> void:
	var file := "bg_sea_route.jpg"
	if type == "title":
		file = "bg_world_map.jpg"
	elif PORT_BG.has(loc):
		file = PORT_BG[loc]
	_set_background_file(file)


func _set_background_file(file_name: String) -> void:
	var tex := GameManager.load_texture("res://assets/" + file_name)
	if tex != null:
		background.texture = tex


func _enter_panel_mode() -> void:
	_frame_sheet(false)
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	for child in interactive_container.get_children():
		child.queue_free()
	for child in choices_container.get_children():
		child.queue_free()
	_slip_host = null
	_show_investigation_chrome(false)
	scene_title.visible = true
	choices_label.visible = false
	choices_label.text = "请选择"  # 市场会改写它，此处复位避免上一屏文字残留


func _show_investigation_chrome(show: bool) -> void:
	interactive_label.visible = show
	interactive_container.visible = show
	interactive_container.custom_minimum_size = Vector2(0, 100) if show else Vector2.ZERO


func _unescape_scene_text(s: String) -> String:
	return s.replace("\\A", "\n\n").replace("\\n", "\n")


## 剧情设施尚未实装时的占位文案，比「施工中」更不出戏
const FACILITY_PLACEHOLDER := {
	"city_exam": {
		"title": "贡院",
		"body": "贡院朱门紧闭。今科未开，阶下只有几个背着书箧的士子在张望。\n你想起叔父留下的那笔债，又摸了摸袖中那份还没押字的货单——科举与海路，眼下还容不得你两头都要。",
	},
	"city_guild": {
		"title": "行会",
		"body": "行首正与几名蕃商核对舱位与脚钱。墙上钉着一张抄来的远港价目。",
	},
	"city_residence": {
		"title": "住处",
		"body": "一间租来的下处，屋角堆着几卷未拆的旧账。",
	},
}


func _setup_missing_scene(scene_id: String) -> void:
	_enter_panel_mode()
	if FACILITY_PLACEHOLDER.has(scene_id):
		var ph: Dictionary = FACILITY_PLACEHOLDER[scene_id]
		scene_title.text = ph.get("title", scene_id)
		body_text.text = ph.get("body", "")
	else:
		scene_title.text = "区域施工中..."
		body_text.text = "该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"

	var base_loc = GameState.last_port
	if base_loc == "" or base_loc == scene_id:
		base_loc = "quanzhou" if scene_id.begins_with("quanzhou") else "xinghua"
	_add_leave_button(base_loc)
	update_status_panel()


# ══════════════════════════════════════════════════════
#  设施：牙行 / 市舶司 / 船屋 / 酒馆 / 旅店 / 行会 / 贡院 / 住宅 / 寺观
# ══════════════════════════════════════════════════════

func _setup_dynamic_scene(scene_id: String, suffix: String) -> void:
	_enter_panel_mode()
	var base_loc := scene_id.trim_suffix(suffix)
	if FACILITY_BG.has(suffix):
		_set_background_file(FACILITY_BG[suffix])

	match suffix:
		"_market":
			_setup_market(base_loc)
		"_tavern":
			_setup_tavern(base_loc)
		"_yamen":
			_setup_yamen(base_loc)
		"_shipyard":
			_setup_shipyard(base_loc)
		"_inn":
			_setup_inn(base_loc)
		"_guild":
			_setup_guild(base_loc)
		"_exam":
			_setup_exam(base_loc)
		"_residence":
			_setup_residence(base_loc)
		"_temple":
			_setup_temple(base_loc)
	update_status_panel()


# ── 牙行（市场）─────────────────────────────────────

func _setup_market(port_id: String) -> void:
	scene_title.text = "%s・牙行" % GameManager.get_port_name(port_id)
	body_text.text = "牙行里没人说官话，只用算筹和价目说话。"

	var goods_ids: Array = Economy.goods_at(port_id)
	if goods_ids.is_empty():
		body_text.text += "\n\n此地并无正经牙行，只有几个渔妇在晒网。"
		_add_leave_button(port_id)
		return

	# 按买价排序，便宜的在前
	goods_ids.sort_custom(func(a, b): return Economy.buy_price(port_id, a) < Economy.buy_price(port_id, b))

	# 多船时选船装货；重置到旗舰
	_market_ship = 0
	if Fleet.ships.size() > 1:
		var sel := HBoxContainer.new()
		sel.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = "装至"
		lbl.custom_minimum_size = Vector2(44, 0)
		UiTheme.style_footnote(lbl)
		lbl.add_theme_color_override("font_color", UiTheme.TEXT)
		sel.add_child(lbl)
		var opt := OptionButton.new()
		for i in range(Fleet.ships.size()):
			var s: Dictionary = Fleet.ships[i]
			opt.add_item("%s（%s）　空 %d 料" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_free_capacity(i)),
			])
			opt.set_item_metadata(i, i)
		opt.selected = _market_ship
		UiTheme.style_button(opt)
		opt.item_selected.connect(func(idx: int):
			_market_ship = int(opt.get_item_metadata(idx))
			load_scene(current_scene_id))
		sel.add_child(opt)
		choices_container.add_child(sel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	choices_container.add_child(scroll)

	for gid in goods_ids:
		rows.add_child(_make_market_row(port_id, gid))

	choices_label.visible = true
	choices_label.text = "舱位 %d / %d 料" % [int(Fleet.used_capacity()), int(Fleet.total_capacity())]
	_add_leave_button(port_id)


func _make_market_row(port_id: String, good_id: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiTheme.card())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)

	var g := GameManager.get_good_by_id(good_id)
	var buy_p := Economy.buy_price(port_id, good_id)
	var sell_p := Economy.sell_price(port_id, good_id)
	var held := Fleet.cargo_qty(good_id, _market_ship)
	var role := Economy.get_role(port_id, good_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)

	var name_lbl := Label.new()
	name_lbl.text = g.get("name", good_id)
	name_lbl.custom_minimum_size = Vector2(96, 0)
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	if g.get("contraband", false):
		name_lbl.add_theme_color_override("font_color", UiTheme.CINNABAR)
		name_lbl.tooltip_text = "违禁：宋法不许出海，验引护不住"
	head.add_child(name_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = Economy.price_hint(port_id, good_id)
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_lbl.clip_text = true
	UiTheme.style_footnote(hint_lbl)
	if role == "origin":
		hint_lbl.add_theme_color_override("font_color", UiTheme.MOSS)
	elif role == "consumer":
		hint_lbl.add_theme_color_override("font_color", UiTheme.HONEY)
	head.add_child(hint_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "买 %d　卖 %d" % [buy_p, sell_p]
	price_lbl.custom_minimum_size = Vector2(120, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_footnote(price_lbl)
	price_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(price_lbl)

	var held_lbl := Label.new()
	held_lbl.text = "舱 %d" % held
	held_lbl.custom_minimum_size = Vector2(56, 0)
	held_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.style_footnote(held_lbl)
	head.add_child(held_lbl)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)

	for n in [1, 10]:
		var b := Button.new()
		b.text = "买%d" % n
		b.pressed.connect(_on_buy.bind(port_id, good_id, n, _market_ship))
		actions.add_child(b)
		UiTheme.style_chip(b)

	var bmax := Button.new()
	bmax.text = "买满"
	bmax.pressed.connect(_on_buy_max.bind(port_id, good_id, _market_ship))
	actions.add_child(bmax)
	UiTheme.style_chip(bmax, true)

	for n in [1, 10]:
		var s := Button.new()
		s.text = "卖%d" % n
		s.disabled = held < n
		s.pressed.connect(_on_sell.bind(port_id, good_id, n, _market_ship))
		actions.add_child(s)
		UiTheme.style_chip(s)

	var sall := Button.new()
	sall.text = "全卖"
	sall.disabled = held <= 0
	sall.pressed.connect(_on_sell.bind(port_id, good_id, held, _market_ship))
	actions.add_child(sall)
	UiTheme.style_chip(sall)

	return card


func _on_buy(port_id: String, good_id: String, amount: int, ship_index: int) -> void:
	if amount <= 0:
		return
	var loadable := Fleet.max_loadable(good_id, ship_index)
	if loadable <= 0:
		log_msg("【舱满】这艘船塞不下了。换一艘船，或先卖掉些货。")
		return
	var actual := mini(amount, loadable)
	var cost := Economy.estimate_buy_cost(port_id, good_id, actual)
	if GameState.money < cost:
		# 按现有钱数尽量买
		var affordable := actual
		while affordable > 0 and Economy.estimate_buy_cost(port_id, good_id, affordable) > GameState.money:
			affordable -= 1
		if affordable <= 0:
			log_msg("【钱不够】牙人翻了翻眼皮，把货单收了回去。")
			return
		actual = affordable
		cost = Economy.estimate_buy_cost(port_id, good_id, actual)

	GameState.spend_money(cost)
	Fleet.add_cargo(good_id, actual, float(cost) / float(actual), ship_index)
	Economy.apply_buy_impact(port_id, good_id, actual)

	var note := ""
	if actual < amount:
		note = "（只购得 %d）" % actual
	log_msg("买入 %s ×%d，付 %d 钱。%s" % [GameManager.get_good_name(good_id), actual, cost, note])
	load_scene(current_scene_id)


func _on_buy_max(port_id: String, good_id: String, ship_index: int) -> void:
	var by_hold := Fleet.max_loadable(good_id, ship_index)
	if by_hold <= 0:
		log_msg("【舱满】这艘船塞不下了。换一艘船，或先卖掉些货。")
		return
	var n := by_hold
	while n > 0 and Economy.estimate_buy_cost(port_id, good_id, n) > GameState.money:
		n -= 1
	if n <= 0:
		log_msg("【钱不够】连一件也买不起。")
		return
	_on_buy(port_id, good_id, n, ship_index)


func _on_sell(port_id: String, good_id: String, amount: int, ship_index: int) -> void:
	var held := Fleet.cargo_qty(good_id, ship_index)
	var actual := mini(amount, held)
	if actual <= 0:
		return
	var revenue := Economy.estimate_sell_revenue(port_id, good_id, actual)
	var cost_basis := Fleet.cargo_cost(good_id, ship_index) * actual

	Fleet.remove_cargo(good_id, actual, ship_index)
	GameState.add_money(revenue)
	Economy.apply_sell_impact(port_id, good_id, actual)

	var profit := revenue - int(round(cost_basis))
	var profit_str := "赚 %d" % profit if profit >= 0 else "亏 %d" % (-profit)
	log_msg("卖出 %s ×%d，得 %d 钱（%s）。" % [GameManager.get_good_name(good_id), actual, revenue, profit_str])
	load_scene(current_scene_id)


# ── 市舶司 ──────────────────────────────────────────

func _setup_yamen(port_id: String) -> void:
	scene_title.text = "%s・市舶司" % GameManager.get_port_name(port_id)
	body_text.text = "案上压着未批的货单。验引、呈报、修埠都在这里。"

	_add_npc_button("customs_official", "市舶司小吏")

	var permit := _slip_body()
	var duty := GameState.customs_duty()
	var contraband := GameState.contraband_units()
	if GameState.has_customs_permit:
		_slip_title(permit, "货引", "已在手")
		_slip_note(permit, "本次出港可合法验放。", UiTheme.MOSS)
	else:
		_slip_title(permit, "货引", "按舱货抽解")
		_slip_chip(_slip_row(permit), "请领　%d" % duty, _on_apply_permit, true)
	if contraband > 0:
		_slip_note(permit, "舱底尚有违禁 %d 件。报不进明账，验引也遮不住。" % contraband, UiTheme.CINNABAR)
	_slip_note(permit, "蒲氏关注度 %d　%s" % [GameState.pu_attention, _attention_desc()])

	_setup_reporting()
	_setup_title_and_invest(port_id)

	_add_leave_button(port_id)
	choices_label.visible = false


func _on_apply_permit() -> void:
	var res: Dictionary = GameState.apply_for_permit()
	log_msg(str(res.get("msg", "")))
	load_scene(current_scene_id)


## 上报发现：航中或寺观记下的东西要回市舶司呈报才换得赏格与名声
func _setup_reporting() -> void:
	var pending := GameState.unreported_discoveries()
	if pending.is_empty():
		return

	for did in pending:
		var d := GameManager.get_discovery_by_id(did)
		if d.is_empty():
			continue
		var value: int = int(d.get("value", 50))
		var slip := _slip_body()
		_slip_title(slip, str(d.get("name", did)), "赏格 %d　名声 +%d" % [value, maxi(1, value / 10)])
		var chip := _slip_chip(_slip_row(slip), "呈报", _on_report_discovery.bind(str(did)), true)
		chip.tooltip_text = "%s\n%s" % [d.get("location", ""), d.get("historical_hook", "")]


func _on_report_discovery(did: String) -> void:
	var res: Dictionary = GameState.report_discovery(did)
	if not res.is_empty():
		var extra := ""
		if res.get("promoted", false):
			extra = "市舶司案册改题「%s」。" % str(res.get("title", {}).get("name", ""))
		log_msg("【呈报】%s 录入案册，赏钱 %d，名声 +%d。%s" % [
			res["name"], res["gold"], res["fame"], extra,
		])
	load_scene(current_scene_id)


func _setup_title_and_invest(port_id: String) -> void:
	var rank: Dictionary = GameState.title_rank()
	var nxt: Dictionary = GameState.next_title()
	var rank_slip := _slip_body()
	_slip_title(rank_slip, "职衔", str(rank.get("name", "")))
	if nxt.is_empty():
		_slip_note(rank_slip, "抽解按职衔折至 %d%%，赊贷上限 %d。" % [
			int(round(float(rank.get("duty_factor", 1.0)) * 100.0)),
			GameState.DEBT_CEILING + GameState.title_loan_bonus(),
		])
	else:
		var need: int = maxi(0, int(nxt.get("min_fame", 0)) - GameState.fame)
		_slip_note(rank_slip, "再记 %d 声名可题「%s」。抽解折至 %d%%，赊贷上限 %d。" % [
			need, nxt.get("name", ""),
			int(round(float(rank.get("duty_factor", 1.0)) * 100.0)),
			GameState.DEBT_CEILING + GameState.title_loan_bonus(),
		])

	var lv: int = Economy.investment_level(port_id)
	var cost: int = Economy.invest_cost(port_id)
	var inv := _slip_body()
	var inv_aside := "尚未修埠"
	if lv > 0:
		inv_aside = "已修至 %d 等" % lv
	_slip_title(inv, "修埠", inv_aside)
	if cost <= 0:
		_slip_note(inv, "本港埠头已修至 %d 等。产地更廉、紧缺更好卖，市场也更深。" % lv)
	elif lv <= 0:
		_slip_note(inv, "向本港投钱修埠，可加深市场、让本地所产更廉、紧缺货更好卖。")
	else:
		_slip_note(inv, "向本港投钱修埠，再升一等：产地买入更廉、紧缺货更好卖、市场更深。")
	if cost > 0:
		var chip := _slip_chip(_slip_row(inv), "投钱　%d" % cost, _on_invest_port.bind(port_id), true)
		chip.tooltip_text = "向本港投钱修埠"


func _on_invest_port(port_id: String) -> void:
	var res: Dictionary = Economy.invest(port_id)
	log_msg(str(res.get("msg", "")))
	load_scene(current_scene_id)


func _attention_desc() -> String:
	var a := GameState.pu_attention
	if a >= 70:
		return "（暗桩已盯死，出港必查）"
	elif a >= 50:
		return "（蒲氏起了疑心）"
	elif a >= 25:
		return "（偶有闲话传出）"
	return "（尚无人留意）"


# ── 账条 ────────────────────────────────────────────
## 设施页里一桩事一张熟漆卡。标题在上，小钮在下，和牙行价目同一套。

func _slip_body() -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiTheme.card())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)
	var parent: Node = _slip_host if _slip_host != null else choices_container
	parent.add_child(card)
	return body


## 条数放不下 720 高时，账条在里面滚，离开钮钉在下面。
func _begin_slip_scroll(max_h: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, max_h)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	choices_container.add_child(scroll)
	_slip_host = box


func _end_slip_scroll() -> void:
	_slip_host = null


func _slip_title(body: VBoxContainer, title: String, aside := "") -> Label:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(name_lbl)
	var hint := Label.new()
	hint.text = aside
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	UiTheme.style_footnote(hint)
	head.add_child(hint)
	return hint


func _slip_note(body: VBoxContainer, text: String, color: Color = UiTheme.TEXT_DIM) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", color)
	body.add_child(lbl)
	return lbl


func _slip_row(body: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	return row


func _slip_chip(row: Node, text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	row.add_child(b)
	UiTheme.style_chip(b, accent)
	return b


# ── 船屋 ────────────────────────────────────────────

func _setup_shipyard(port_id: String) -> void:
	scene_title.text = "%s・船屋" % GameManager.get_port_name(port_id)
	body_text.text = "桐油和潮气。修船、补员、装水粮。"
	# 补给、改装、购船叠在一起会把离开裁出 720 高的画面。
	_begin_slip_scroll(412)

	var grain_price := Economy.buy_price(port_id, "grain") if Economy.is_traded(port_id, "grain") else 12
	var water_price := 1
	var supply := _slip_body()
	_slip_title(supply, "补给", "水 %d　粮 %d　每日耗 %d" % [
		water_price, grain_price, Fleet.daily_supply_use(),
	])
	var supply_row := _slip_row(supply)
	for n in [30, 100]:
		var packs := int(n)
		_slip_chip(
			supply_row,
			"各 %d　%d" % [packs, packs * (water_price + grain_price)],
			_on_buy_supplies.bind(packs, water_price, grain_price)
		)
	var rc := Fleet.repair_cost()
	if rc > 0:
		_slip_chip(supply_row, "修船　%d" % rc, _on_repair_hull.bind(rc))

	var hands := _slip_body()
	_slip_title(hands, "人手", "码头上按船招")
	var hand_row := _slip_row(hands)
	var below_min: int = Fleet.crew_to_min_needed()
	if below_min > 0:
		var top_cost := below_min * 20
		_slip_chip(
			hand_row,
			"补齐 %d 人　%d" % [below_min, top_cost],
			_on_hire_to_min.bind(top_cost)
		)
	var any_room := false
	for i in range(Fleet.ships.size()):
		var room: int = Fleet.ship_crew_room(i)
		if room <= 0:
			continue
		any_room = true
		var s: Dictionary = Fleet.ships[i]
		var hire_n: int = mini(10, room)
		var hire_cost := hire_n * 20
		var chip := _slip_chip(
			hand_row,
			"%s　+%d　%d" % [s.get("name", "船"), hire_n, hire_cost],
			_on_hire_crew.bind(i, hire_n, hire_cost)
		)
		chip.tooltip_text = "该船可容 %d，现有 %d" % [room, Fleet.ship_crew(i)]
	if below_min <= 0 and not any_room:
		_slip_note(hands, "各船人手已满。")

	var loan := _slip_body()
	_slip_title(loan, "蕃商赊贷", "月息 %d%%　上限 %d" % [
		int(GameState.DEBT_MONTHLY_RATE * 100),
		GameState.DEBT_CEILING + GameState.title_loan_bonus(),
	])
	if GameState.debt > 0:
		_slip_note(loan, "现欠 %d，每月生息 %d。" % [
			GameState.debt, int(ceil(GameState.debt * GameState.DEBT_MONTHLY_RATE)),
		], UiTheme.HONEY)
	var loan_row := _slip_row(loan)
	var borrow_cap := GameState.borrow_limit()
	for amt in [500, 2000]:
		if amt > borrow_cap:
			continue
		var borrowed := int(amt)
		_slip_chip(loan_row, "赊 %d" % borrowed, _on_borrow.bind(borrowed))
	if GameState.debt > 0 and GameState.money > 0:
		var pay: int = mini(GameState.debt, GameState.money)
		_slip_chip(loan_row, "还 %d" % pay, _on_repay.bind(pay), true)

	for i in range(Fleet.ships.size()):
		var sname: String = Fleet.ships[i].get("name", "船")
		var slv: int = Fleet.sail_level(i)
		var alv: int = Fleet.armor_level(i)
		var fit := _slip_body()
		_slip_title(fit, sname, "帆 Lv%d　甲 Lv%d" % [slv, alv])
		var fit_row := _slip_row(fit)
		if Fleet.is_sail_max(i):
			_slip_note(fit, "帆已满级。")
		else:
			var scost: int = Fleet.upgrade_cost(i, "sail")
			var sail_chip := _slip_chip(fit_row, "升帆　%d" % scost, _on_upgrade.bind(i, "sail", scost))
			sail_chip.tooltip_text = "航速 ×%.2f" % (1.0 + 0.12 * slv)
		if Fleet.is_armor_max(i):
			_slip_note(fit, "甲已满级。")
		else:
			var acost: int = Fleet.upgrade_cost(i, "armor")
			var armor_chip := _slip_chip(fit_row, "升甲　%d" % acost, _on_upgrade.bind(i, "armor", acost))
			armor_chip.tooltip_text = "船体伤 ×%.2f" % (1.0 - 0.10 * alv)

	for s in GameManager.ships_data.get("ships", []):
		if not GameState.is_chapter_reached(s.get("unlock", "ch1")):
			continue
		var price: int = int(s.get("price", 0))
		var tid: String = str(s.get("id", ""))
		var offer := _slip_body()
		_slip_title(offer, str(s.get("name", "?")), "载 %d 料　水手 %d–%d　耐久 %d" % [
			int(s.get("capacity", 0)), int(s.get("crew_min", 0)),
			int(s.get("crew_max", 0)), int(s.get("durability", 0)),
		])
		var buy := _slip_chip(_slip_row(offer), "购入　%d" % price, _on_buy_ship.bind(tid, price), true)
		buy.tooltip_text = str(s.get("historical_note", ""))

	_end_slip_scroll()
	_add_leave_button(port_id)
	choices_label.visible = false


func _on_repair_hull(cost: int) -> void:
	if GameState.spend_money(cost):
		Fleet.repair_all()
		log_msg("船匠敲打了整整一日，船体修复如初。")
	else:
		log_msg("【钱不够】船匠摇摇头，把凿子收了。")
	load_scene(current_scene_id)


func _on_hire_to_min(cost: int) -> void:
	if GameState.spend_money(cost):
		var got: int = Fleet.hire_to_min()
		log_msg("码头上凑齐了 %d 个水手，各船补至最低人手。" % got)
	else:
		log_msg("【钱不够】没人肯赊帐上船。")
	load_scene(current_scene_id)


func _on_borrow(amt: int) -> void:
	if GameState.borrow(amt):
		log_msg("蕃商掂了掂你的船和名声，点了头。赊得 %d 钱，月息 %d%%。" % [
			amt, int(GameState.DEBT_MONTHLY_RATE * 100),
		])
	load_scene(current_scene_id)


func _on_repay(pay: int) -> void:
	var paid: int = GameState.repay(pay)
	log_msg("还了 %d 钱，尚欠 %d。" % [paid, GameState.debt])
	load_scene(current_scene_id)


func _on_buy_ship(type_id: String, price: int) -> void:
	if GameState.spend_money(price):
		Fleet.add_ship(type_id)
		log_msg("买下一条%s，泊在船坞外侧。记得雇足水手才好出海。" % Fleet.ship_def(type_id).get("name", "船"))
	else:
		log_msg("【钱不够】船行掌柜笑而不语。")
	load_scene(current_scene_id)


func _on_dismiss_crew(role_id: String) -> void:
	var res: Dictionary = Crew.dismiss(role_id)
	if res.get("ok", false):
		log_msg(str(res.get("msg", "")))
	load_scene(current_scene_id)


func _on_hire_candidate(crew_id: String) -> void:
	var res: Dictionary = Crew.hire(crew_id)
	log_msg(str(res.get("msg", "")))
	load_scene(current_scene_id)


func _on_hire_crew(ship_index: int, hire_n: int, hire_cost: int) -> void:
	if GameState.spend_money(hire_cost):
		var got: int = Fleet.hire_crew(hire_n, ship_index)
		var s: Dictionary = Fleet.ships[ship_index]
		log_msg("码头上招了 %d 个水手，上了「%s」。" % [got, s.get("name", "")])
	else:
		log_msg("【钱不够】没人肯赊帐上船。")
	load_scene(current_scene_id)


func _on_upgrade(ship_index: int, kind: String, cost: int) -> void:
	if not GameState.spend_money(cost):
		log_msg("【钱不够】船匠掂了掂银袋，摇了摇头。")
	elif kind == "armor":
		Fleet.upgrade_armor(ship_index)
		var s: Dictionary = Fleet.ships[ship_index]
		log_msg("「%s」加厚了船壳，甲升至 Lv%d。" % [s.get("name", "船"), Fleet.armor_level(ship_index)])
	else:
		Fleet.upgrade_sail(ship_index)
		var s2: Dictionary = Fleet.ships[ship_index]
		log_msg("「%s」换了新帆，帆升至 Lv%d。" % [s2.get("name", "船"), Fleet.sail_level(ship_index)])
	load_scene(current_scene_id)


func _on_buy_supplies(n: int, wp: int, gp: int) -> void:
	var cost := n * (wp + gp)
	var need_space := float(n * 2) * Fleet.SUPPLY_BULK
	if Fleet.free_capacity() < need_space:
		log_msg("【舱满】水粮也要占舱位，还差 %d 料。" % int(ceil(need_space - Fleet.free_capacity())))
		return
	if not GameState.spend_money(cost):
		log_msg("【钱不够】买不起这许多水粮。")
		return
	Fleet.water += n
	Fleet.food += n
	log_msg("补入水 %d 份、粮 %d 份，付 %d 钱。现可支撑 %d 日。" % [n, n, cost, Fleet.supply_days()])
	load_scene(current_scene_id)


# ── 酒馆 ────────────────────────────────────────────

func _setup_tavern(port_id: String) -> void:
	scene_title.text = "%s・酒馆" % GameManager.get_port_name(port_id)
	body_text.text = "劣酒和喧哗。消息与人手都从这儿来。月俸按月，欠饷三月则去。"

	# 旧事放最前，仍走挑签：泉州候选五人时，钩子否则会被挤出 720p 窗口。
	_setup_story_hooks(port_id)

	if port_id.begins_with("quanzhou"):
		_add_npc_button("merchant_lin", "林阿舶")
	elif port_id.begins_with("ryukyu"):
		_add_npc_button("pilot_ana", "阿那")

	var intel := _slip_body()
	_slip_title(intel, "行情", "费 1 日")
	_slip_chip(_slip_row(intel), "打听", _on_gather_intel.bind(port_id))

	_setup_hiring(port_id)

	_add_leave_button(port_id)
	choices_label.visible = false


func _setup_story_hooks(port_id: String) -> void:
	var hooks: Array = GameState.story_hooks_at(port_id)
	if hooks.is_empty():
		return
	var sep := Label.new()
	sep.text = "旧事"
	UiTheme.style_section_label(sep)
	choices_container.add_child(sep)
	for h in hooks:
		var btn := Button.new()
		btn.text = str(h.get("label", "追问"))
		btn.pressed.connect(_on_story_hook.bind(h, port_id))
		choices_container.add_child(btn)
		UiTheme.style_choice_button(btn)


func _on_story_hook(hook: Dictionary, port_id: String) -> void:
	var flag_name := str(hook.get("flag", ""))
	if flag_name != "":
		GameState.set_flag(flag_name)
	var msg := str(hook.get("text", ""))
	if msg != "":
		log_msg(msg)
	update_status_panel()
	load_scene(current_scene_id if current_scene_id != "" else port_id + "_tavern")


func _on_gather_intel(port_id: String) -> void:
	GameManager.advance_days(1)
	log_msg(_gather_price_intel(port_id))
	load_scene(current_scene_id)


## 酒馆募人。每种职事至多一人，故已雇之职不再列出候选。
func _setup_hiring(port_id: String) -> void:
	# 在船的人
	if not Crew.hired.is_empty():
		for c in Crew.roster():
			var aboard := _slip_body()
			var rname: String = Crew.role_def(c.get("role", "")).get("name", "")
			var aboard_hint := _slip_title(aboard, str(c.get("name", "")), "%s %s　月俸 %d" % [
				rname, _stars(int(c.get("level", 1))), int(c.get("wage", 0)),
			])
			aboard_hint.add_theme_color_override("font_color", UiTheme.MOSS)
			var rid: String = str(c.get("role", ""))
			_slip_chip(_slip_row(aboard), "辞退", _on_dismiss_crew.bind(rid))

	var cands := Crew.candidates_at(port_id)
	if cands.is_empty():
		var none := _slip_body()
		_slip_title(none, "募人", "此处无人可用")
		return

	for c in cands:
		var cid: String = str(c.get("id", ""))
		var role: Dictionary = Crew.role_def(c.get("role", ""))
		var card := _slip_body()
		_slip_title(card, str(c.get("name", "")), "%s %s" % [
			role.get("name", ""), _stars(int(c.get("level", 1))),
		])
		_slip_note(card, "入伙 %d　月俸 %d" % [Crew.signing_fee(cid), int(c.get("wage", 0))])
		var hire := _slip_chip(_slip_row(card), "雇入", _on_hire_candidate.bind(cid), true)
		hire.tooltip_text = "%s\n\n%s\n%s" % [
			c.get("bio", ""), role.get("desc", ""), role.get("effect_hint", ""),
		]


func _stars(n: int) -> String:
	return "★".repeat(maxi(0, n))


## 旅店：候风。季风按月转向，等到对的月份再发舶是这个游戏最要紧的判断之一。
func _setup_inn(port_id: String) -> void:
	scene_title.text = "%s・旅店" % GameManager.get_port_name(port_id)
	body_text.text = "通铺草席还潮着。风信不对时，海商在这儿候着。"

	var rest := _slip_body()
	_slip_title(rest, "歇息", "%s　%s" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()])
	_slip_note(rest, _monsoon_forecast(), UiTheme.HONEY)
	var rest_row := _slip_row(rest)
	for n in [1, 10]:
		var nights := int(n)
		_slip_chip(rest_row, "歇 %d 日　%d" % [nights, nights * INN_RATE], _on_rest.bind(nights, port_id))
	var to_next: int = Calendar.DAYS_PER_MONTH - Calendar.day + 1
	_slip_chip(
		rest_row,
		"候 %d 日　%d" % [to_next, to_next * INN_RATE],
		_on_rest.bind(to_next, port_id),
		true
	)

	_add_leave_button(port_id)
	choices_label.visible = false


const INN_RATE := 15
const HOME_RATE := 5
const EXAM_COPY_DAYS := 3
const EXAM_STIPEND := 30
const GUILD_CREDIT_WIDE := 8


## 行会：出港行情抄本。酒馆打听仍费一日只吐一条；这里钉在墙上，不耗日。
func _setup_guild(port_id: String) -> void:
	scene_title.text = "%s・行会" % GameManager.get_port_name(port_id)
	body_text.text = "墙上钉着远港价目，墨迹有的还潮着。海商信用 %d，足的人会里肯多抄几条远路。" % GameState.merchant_credit

	var limit: int = 5 if GameState.merchant_credit >= GUILD_CREDIT_WIDE else 3
	var rows: Array = _collect_spreads(port_id, limit)
	if rows.is_empty():
		var empty := _slip_body()
		_slip_title(empty, "出港行情", "眼下抄不出能赚的路")
		_slip_note(empty, "过几日行情回一回再来。")
	else:
		for row in rows:
			var slip := _slip_body()
			var hint := _slip_title(
				slip,
				GameManager.get_good_name(row["good"]),
				"→ %s　+%d" % [GameManager.get_port_name(row["port"]), int(row["profit"])]
			)
			hint.add_theme_color_override("font_color", UiTheme.MOSS)
			_slip_note(slip, "买 %d　卖 %d" % [int(row["buy"]), int(row["sell"])])

	_add_leave_button(port_id)
	choices_label.visible = false


## 贡院：今科未开，只能替人誊录。耗日换工钱与学者倾向，不给名声、不另开章门。
func _setup_exam(port_id: String) -> void:
	scene_title.text = "%s・贡院" % GameManager.get_port_name(port_id)
	body_text.text = "今科未开。只能替人誊录，笔墨钱现结。"

	var copy := _slip_body()
	_slip_title(copy, "誊录", "学者 %d　海路 %d" % [GameState.scholar_tendency, GameState.sea_tendency])
	_slip_note(copy, "工钱 %d　费 %d 日。不记名声。" % [EXAM_STIPEND, EXAM_COPY_DAYS])
	_slip_chip(_slip_row(copy), "替人抄三日", _on_exam_copy.bind(port_id), true)

	_add_leave_button(port_id)
	choices_label.visible = false


func _on_exam_copy(_port_id: String) -> void:
	GameManager.advance_days(EXAM_COPY_DAYS)
	GameState.add_money(EXAM_STIPEND)
	GameState.scholar_tendency += 1
	log_msg("【誊录】在贡院廊下抄了 %d 日试卷，得工钱 %d。学者倾向 %d。如今是 %s。" % [
		EXAM_COPY_DAYS, EXAM_STIPEND, GameState.scholar_tendency, Calendar.get_date_string(),
	])
	load_scene(current_scene_id)


## 住宅：看边记、便宜歇息。候风仍去旅店——下处等不到风向。
func _setup_residence(port_id: String) -> void:
	scene_title.text = "%s・住处" % GameManager.get_port_name(port_id)
	body_text.text = "租来的下处。比旅店便宜，听不见风信。"

	var book := _slip_body()
	_slip_title(book, "边记", "学者 %d　海路 %d" % [GameState.scholar_tendency, GameState.sea_tendency])
	if GameState.ledger_notes.is_empty():
		_slip_note(book, "案上只有叔父那几卷未清的旧账。")
	else:
		for note in GameState.ledger_notes:
			_slip_note(book, str(note))

	var home := _slip_body()
	_slip_title(home, "歇息", "候风仍去旅店")
	var home_row := _slip_row(home)
	for n in [1, 3]:
		var nights := int(n)
		_slip_chip(
			home_row,
			"歇 %d 日　%d" % [nights, nights * HOME_RATE],
			_on_rest.bind(nights, port_id, HOME_RATE, "下处")
		)

	_add_leave_button(port_id)
	choices_label.visible = false


const TEMPLE_LOOK_DAYS := 1
const TEMPLE_RUB_DAYS := 1


## 寺观：上陆勘见近侧旧迹。记入册子，拓纸入边记；赏格仍回市舶司呈报——不在这里发名声。
func _setup_temple(port_id: String) -> void:
	scene_title.text = "%s・寺观" % GameManager.get_port_name(port_id)
	body_text.text = "住持不谈功名。细看记入册子，拓纸带回住处，赏格回市舶司。"
	if GameState.has_flag("japan_temple_network"):
		body_text.text += "\n袖底那张寺社短札，这里的沙弥看过一眼就不再多问。"

	var near: Array = GameManager.discoveries_near(port_id)
	if near.is_empty():
		var empty := _slip_body()
		_slip_title(empty, "近侧旧迹", "没有可勘的")
		_slip_note(empty, "海上撞见的，回市舶司呈报即可。")
	else:
		for d in near:
			var did := str(d.get("id", ""))
			var name := str(d.get("name", did))
			var hook := str(d.get("historical_hook", ""))
			var slip := _slip_body()
			if not GameState.has_found(did):
				_slip_title(slip, name, "未勘")
				var look := _slip_chip(_slip_row(slip), "细看一日", _on_temple_look.bind(did, name), true)
				look.tooltip_text = "%s\n%s" % [d.get("location", ""), hook]
				continue
			if did in GameState.discoveries_found:
				_slip_title(slip, name, "已记入册")
				_slip_note(slip, "赏格回市舶司呈报。")
			else:
				_slip_title(slip, name, "已呈报")
			if _has_temple_rub(name):
				_slip_note(slip, "拓纸已入边记，回住处可翻。", UiTheme.MOSS)
			else:
				var rub := _slip_chip(_slip_row(slip), "拓碑一日", _on_temple_rub.bind(did, name, hook))
				rub.tooltip_text = hook

	_add_leave_button(port_id)
	choices_label.visible = false


func _temple_rub_note(name: String, hook: String) -> String:
	var body := hook.strip_edges()
	if body == "":
		return "拓「%s」。" % name
	return "拓「%s」：%s" % [name, body]


func _has_temple_rub(name: String) -> bool:
	var needle := "拓「%s」" % name
	for note in GameState.ledger_notes:
		if str(note).begins_with(needle):
			return true
	return false


func _on_temple_look(did: String, name: String) -> void:
	GameManager.advance_days(TEMPLE_LOOK_DAYS)
	if GameState.record_discovery(did):
		log_msg("【勘见】在寺观廊下细看了 %d 日，把「%s」记入册子。赏格须回市舶司呈报。如今是 %s。" % [
			TEMPLE_LOOK_DAYS, name, Calendar.get_date_string(),
		])
	else:
		log_msg("沿廊走了一圈，「%s」与册上所记并无出入。" % name)
	load_scene(current_scene_id)


func _on_temple_rub(did: String, name: String, hook: String) -> void:
	if did == "" or not GameState.has_found(did):
		log_msg("还没细看过，「%s」纸上拓不出字。" % name)
		load_scene(current_scene_id)
		return
	GameManager.advance_days(TEMPLE_RUB_DAYS)
	if _has_temple_rub(name):
		log_msg("纸上墨迹未干，「%s」已经拓过了。" % name)
	else:
		GameState.add_ledger_note(_temple_rub_note(name, hook))
		log_msg("【拓碑】在寺观廊下拓了 %d 日，把「%s」写入边记。回住处可翻。如今是 %s。" % [
			TEMPLE_RUB_DAYS, name, Calendar.get_date_string(),
		])
	load_scene(current_scene_id)


## 提示下一次季风转向还有多久
func _monsoon_forecast() -> String:
	var cur := Calendar.get_monsoon()
	var m: int = Calendar.month
	var d: int = Calendar.day
	var days := 0
	for i in range(1, 366):
		var mm: int = m
		var dd: int = d + i
		while dd > Calendar.DAYS_PER_MONTH:
			dd -= Calendar.DAYS_PER_MONTH
			mm += 1
			if mm > Calendar.MONTHS_PER_YEAR:
				mm = 1
		var next_monsoon: int
		if mm >= 10 or mm <= 2:
			next_monsoon = Calendar.Monsoon.NORTHEAST
		elif mm >= 5 and mm <= 8:
			next_monsoon = Calendar.Monsoon.SOUTHWEST
		else:
			next_monsoon = Calendar.Monsoon.TRANSITION
		if next_monsoon != cur:
			days = i
			break
	if days == 0:
		return ""
	return "掌柜掐指算了算：约 %d 日后风信要转。北上博多、高丽须候西南风（五至八月），南下流求、南洋须候东北风（十月至次年二月）。" % days


func _on_rest(days: int, port_id: String, rate: int = INN_RATE, place: String = "店中") -> void:
	var cost := days * rate
	if not GameState.spend_money(cost):
		log_msg("【钱不够】掌柜把算盘一推：「客官，先结了前帐罢。」")
		return
	GameManager.advance_days(days)
	Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + days * 2)
	log_msg("在%s歇了 %d 日，付房钱 %d。如今是 %s，%s。" % [
		place, days, cost, Calendar.get_date_string(), Calendar.get_monsoon_desc(),
	])
	load_scene(current_scene_id)


## 已解锁港口中、从此港买出能正赚的价差，按利润降序。
func _collect_spreads(port_id: String, limit: int = 3) -> Array:
	var rows: Array = []
	for p in GameManager.unlocked_ports():
		var pid: String = p.get("id", "")
		if pid == port_id or pid.ends_with("_harbor"):
			continue
		for gid in Economy.goods_at(port_id):
			if not Economy.is_traded(pid, gid):
				continue
			var buy_p: int = Economy.buy_price(port_id, gid)
			var sell_p: int = Economy.sell_price(pid, gid)
			var profit: int = sell_p - buy_p
			if profit > 0:
				rows.append({
					"profit": profit, "port": pid, "good": gid,
					"buy": buy_p, "sell": sell_p,
				})
	rows.sort_custom(func(a, b): return int(a["profit"]) > int(b["profit"]))
	if limit > 0 and rows.size() > limit:
		return rows.slice(0, limit)
	return rows


## 在已解锁港口中找一条真实存在的价差，作为情报吐给玩家
func _gather_price_intel(port_id: String) -> String:
	var rows: Array = _collect_spreads(port_id, 1)
	if rows.is_empty():
		return "【闲谈】几个老水手翻来覆去只讲当年的风暴，没打听出什么有用的。"
	var best: Dictionary = rows[0]
	return "【行情】邻座的牙人压低声音：「%s 眼下缺%s，此地买了运过去，一件能多得 %d 钱。」" % [
		GameManager.get_port_name(best["port"]),
		GameManager.get_good_name(best["good"]),
		int(best["profit"]),
	]


# ══════════════════════════════════════════════════════
#  NPC
# ══════════════════════════════════════════════════════

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	var slip := _slip_body()
	_slip_title(slip, fallback_name, "在侧")
	_slip_chip(_slip_row(slip), "见", _on_meet_npc.bind(npc_id, fallback_name))


func _on_meet_npc(npc_id: String, fallback_name: String) -> void:
	_show_npc_mode(npc_id, fallback_name)


func _show_npc_mode(npc_id: String, fallback_name: String) -> void:
	investigation_mode.visible = false
	npc_mode.visible = true

	var npc_data := {}
	for n in GameManager.npcs_data.get("npcs", []):
		if n.get("id") == npc_id:
			npc_data = n
			break

	var n_name := str(npc_data.get("name", fallback_name))
	npc_name_lbl.text = n_name
	var spoken := str(NPC_GREETING.get(npc_id, ""))
	if spoken == "":
		spoken = str(npc_data.get("function", "这人看了你一眼，没先开口。"))
	var tex_path := "res://assets/sprite_" + npc_id.replace("pilot_", "").replace("merchant_", "") + ".png"
	npc_portrait.texture = GameManager.load_texture(tex_path)
	npc_portrait.get_parent().visible = npc_portrait.texture != null

	for child in npc_actions.get_children():
		child.queue_free()

	_slip_host = npc_actions
	var talk := _slip_body()
	_npc_speech = _slip_note(talk, spoken, UiTheme.TEXT)
	_npc_speech.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	var intel := _slip_body()
	_slip_title(intel, "行情", "邻座牙人")
	_slip_chip(_slip_row(intel), "打听", _on_npc_intel.bind(n_name))
	if npc_id == "customs_official":
		var bribe := _slip_body()
		_slip_title(bribe, "疏通", "关注减 15")
		_slip_chip(_slip_row(bribe), "塞 50", _on_npc_bribe.bind(n_name), true)
	_slip_host = null

	var leave_btn := Button.new()
	leave_btn.text = "离开"
	leave_btn.pressed.connect(_on_npc_leave)
	npc_actions.add_child(leave_btn)
	UiTheme.style_choice_button(leave_btn)


const NPC_GREETING := {
	"customs_official": "小吏把册子掀开一条缝，眼皮都没抬。「验引、呈报、修埠，都在这案上。有话就说。」",
	"merchant_lin": "林阿舶用指甲敲了敲账簿。「舱位、脚钱、货损，一样一样算。你叔父那笔，我还记着。」",
	"pilot_ana": "阿那望了一眼外海的水色。「潮声不对就别嘴硬。要问航路，就问。」",
}


func _set_npc_speech(text: String) -> void:
	if _npc_speech != null:
		_npc_speech.text = text


func _on_npc_intel(n_name: String) -> void:
	_set_npc_speech(n_name + " 压低声音说：\n\n" + _gather_price_intel(GameState.last_port))


func _on_npc_bribe(n_name: String) -> void:
	if GameState.spend_money(50):
		GameState.pu_attention = maxi(0, GameState.pu_attention - 15)
		update_status_panel()
		_set_npc_speech(n_name + " 颠了颠手里的碎银：「算你懂事。近来风声紧，自己当心。」")
	else:
		_set_npc_speech(n_name + " 满脸鄙夷：「就这点钱也想打通关节？」")


func _on_npc_leave() -> void:
	npc_mode.visible = false
	investigation_mode.visible = true


# ══════════════════════════════════════════════════════
#  标题 / 港口 / 调查
# ══════════════════════════════════════════════════════

func _setup_title_mode(scene_data: Dictionary) -> void:
	left_panel.visible = false
	investigation_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	title_mode.visible = true

	main_title.text = scene_data.get("cg_title", "东亚海域立志传")
	sub_title.text = _unescape_scene_text(str(scene_data.get("cg_sub", "")))

	if title_button_connected:
		for c in start_button.pressed.get_connections():
			start_button.pressed.disconnect(c.callable)

	var choices = scene_data.get("choices", [])
	var next_scene = "prologue_tabletop"
	if choices.size() > 0:
		start_button.text = choices[0].get("label", "开始旅程")
		next_scene = choices[0].get("next", "prologue_tabletop")

	start_button.pressed.connect(_on_start_game_pressed.bind(next_scene))
	title_button_connected = true


func _on_start_game_pressed(next_scene: String) -> void:
	load_scene(next_scene)


func _setup_port_mode(scene_data: Dictionary) -> void:
	left_panel.visible = true
	title_mode.visible = false
	investigation_mode.visible = false
	npc_mode.visible = false
	port_mode.visible = true
	port_title.text = scene_data.get("title", "未知港口")

	for child in left_facilities.get_children():
		child.queue_free()
	for child in right_facilities.get_children():
		child.queue_free()

	var facilities = scene_data.get("facilities", [])
	for i in range(facilities.size()):
		var card := _make_facility_card(facilities[i])
		if i % 2 == 0:
			left_facilities.add_child(card)
		else:
			right_facilities.add_child(card)

	_add_sail_button()
	_add_save_button()


func _make_facility_card(fac: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 64)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiTheme.card())

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)

	var icon_id = fac.get("id", "").replace("city_", "")
	var icon_path = "res://assets/icon_" + icon_id + ".png"
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(46, 46)
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(40, 40)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_tex := GameManager.load_texture(icon_path)
	if icon_tex != null:
		tex_rect.texture = icon_tex

	frame.add_child(tex_rect)
	hbox.add_child(frame)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = fac.get("title", "未命名设施")
	title_lbl.add_theme_font_override("font", UiTheme.font())
	title_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	title_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = fac.get("subtitle", "")
	UiTheme.style_footnote(sub_lbl)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_lbl)

	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_facility_pressed.bind(fac))
	btn.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", UiTheme.card_hover()))
	btn.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", UiTheme.card()))
	card.add_child(btn)

	return card


func _add_sail_button() -> void:
	var btn = Button.new()
	btn.text = "升帆出海"
	btn.custom_minimum_size = Vector2(0, 42)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	btn.pressed.connect(_on_set_sail)
	right_facilities.add_child(btn)
	UiTheme.style_button(btn, true)


func _on_set_sail() -> void:
	if not Fleet.can_sail():
		var bad := Fleet.crew_shortfall()
		if bad.is_empty():
			log_msg("【无法出海】水手不足，船开不动。先去船屋雇人。")
		else:
			var parts := PackedStringArray()
			for b in bad:
				parts.append("%s（%d/%d）" % [b["name"], b["crew"], b["crew_min"]])
			log_msg("【无法出海】下列船水手不足：%s。先去船屋雇人。" % "、".join(parts))
		update_status_panel()
		return
	if Fleet.supply_days() < 2:
		log_msg("【补给不足】水粮撑不过两日，此时出海是拿全船人的命赌。")
		update_status_panel()
		return

	var res: Dictionary = GameState.customs_inspection()
	log_msg(res["msg"])
	update_status_panel()

	if res["passed"]:
		GameState.consume_permit()
		get_tree().change_scene_to_file("res://scenes/SeaChart.tscn")


func _add_save_button() -> void:
	var btn = Button.new()
	btn.text = "存档 / 读档"
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_show_save_dialog)
	right_facilities.add_child(btn)


func _show_save_dialog() -> void:
	if is_instance_valid(_save_host):
		_save_host.queue_free()
	var host := Control.new()
	host.name = "SaveSheet"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	_save_host = host

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.03, 0.02, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(520, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	center.add_child(sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(476, 0)
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := Label.new()
	head.text = "航海日志"
	UiTheme.style_heading(head)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	_slip_host = col
	for slot in range(1, SaveLoad.SLOTS + 1):
		var n := int(slot)
		var slip := _slip_body()
		_slip_title(slip, "第 %d 卷" % n, SaveLoad.save_label(n))
		var row := _slip_row(slip)
		_slip_chip(row, "记录", _on_save_slot.bind(n), true)
		var read := _slip_chip(row, "翻阅", _on_load_slot.bind(n))
		read.disabled = not SaveLoad.has_save(n)
	_slip_host = null

	var close := Button.new()
	close.text = "合上"
	close.pressed.connect(_close_save_sheet)
	col.add_child(close)
	UiTheme.style_choice_button(close)


func _close_save_sheet() -> void:
	if is_instance_valid(_save_host):
		_save_host.queue_free()
	_save_host = null


func _on_save_slot(slot: int) -> void:
	if not SaveLoad.save_game(slot, current_scene_id):
		log_msg("第 %d 卷没能记下。" % slot)
		return
	_close_save_sheet()
	log_msg("已记入航海日志第 %d 卷。" % slot)


func _on_load_slot(slot: int) -> void:
	var scene_id := SaveLoad.saved_scene(slot)
	if not SaveLoad.load_game(slot):
		log_msg("第 %d 卷翻不开。" % slot)
		return
	_close_save_sheet()
	update_status_panel()
	load_scene(scene_id if scene_id != "" else GameState.last_port)
	log_msg("翻开日志第 %d 卷，回到 %s。" % [slot, Calendar.get_date_string()])


# ══════════════════════════════════════════════════════
#  章节推进
# ══════════════════════════════════════════════════════

## 入港结算：记下走过的港口，够条件就开下一章。
## 只有 ports.json 里登记的港口算数——剧情场景不是港口。
func _on_enter_port(port_id: String) -> void:
	if GameManager.get_port_by_id(port_id).is_empty():
		return
	GameState.visit_port(port_id)
	var res := GameState.try_advance_chapter()
	if res.get("advanced", false) or res.get("resolved", false):
		_show_chapter_dialog(res)


func _show_chapter_dialog(res: Dictionary) -> void:
	var dlg := AcceptDialog.new()
	if res.get("resolved", false):
		dlg.title = "了结・%s" % res.get("title", GameState.ending_title())
		dlg.ok_button_text = "记下这一纲"
	else:
		dlg.title = "第 %s 章・%s" % [
			_cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
		]
		dlg.ok_button_text = "承此一路"

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var head := Label.new()
	head.text = res.get("title", "")
	UiTheme.style_heading(head)
	v.add_child(head)

	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.custom_minimum_size = Vector2(520, 200)
	body.text = res.get("text", "")
	UiTheme.style_body(body)
	v.add_child(body)

	dlg.add_child(m)
	add_child(dlg)
	UiTheme.style_dialog(dlg, true)
	dlg.popup_centered()
	var next_scene := str(res.get("scene", ""))
	dlg.confirmed.connect(func():
		if next_scene != "" and not GameManager.get_scene_by_id(next_scene).is_empty():
			load_scene(next_scene)
		else:
			load_scene(current_scene_id)
	)

	update_status_panel()


func _cn_chapter(n: int) -> String:
	var cn := ["", "一", "二", "三", "四", "五", "六"]
	return cn[n] if n < cn.size() else str(n)


func _on_facility_pressed(fac: Dictionary) -> void:
	var target_scene = fac.get("id", "")
	# 兴化序章三张卡仍进调查页；已经踏足泉州之后再回兴化，改走动态页。
	if (
		current_scene_id == "xinghua"
		and target_scene in PROLOGUE_ONLY_FACILITIES
		and not ("quanzhou" in GameState.visited_ports)
	):
		load_scene(target_scene)
		return
	if target_scene in REMAPPED_FACILITIES:
		target_scene = current_scene_id + "_" + target_scene.trim_prefix("city_")
		load_scene(target_scene)
		return
	if target_scene != "":
		load_scene(target_scene)


func _setup_investigation_mode(scene_data: Dictionary) -> void:
	_enter_panel_mode()
	var cinematic := str(scene_data.get("id", "")).begins_with("cg_")
	if cinematic:
		_frame_sheet(true)
		if str(scene_data.get("id", "")) == "cg_title":
			scene_title.add_theme_font_size_override("font_size", 46)
		else:
			scene_title.add_theme_font_size_override("font_size", 30)
	else:
		scene_title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)

	var shown_title := str(scene_data.get("title", "")).strip_edges()
	if shown_title == "":
		shown_title = str(scene_data.get("cg_title", "")).strip_edges()
	if shown_title == "":
		var speaker := str(scene_data.get("speaker", "")).strip_edges()
		if speaker != "" and speaker != "——":
			shown_title = speaker
	scene_title.visible = shown_title != ""
	scene_title.text = shown_title
	var shown_body := str(scene_data.get("body", "")).strip_edges()
	if shown_body == "":
		shown_body = str(scene_data.get("cg_sub", "")).strip_edges()
	body_text.text = _unescape_scene_text(shown_body)

	var investigations = scene_data.get("investigations", [])
	_show_investigation_chrome(investigations.size() > 0)
	for inv in investigations:
		var btn = Button.new()
		btn.text = "★ " + inv.get("label", "互动")
		btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
		interactive_container.add_child(btn)
		UiTheme.style_choice_button(btn)

	var choices = scene_data.get("choices", [])
	show_choices(choices)

	if investigations.size() == 0 and choices.size() == 0:
		_add_fallback_return_button()


func _add_fallback_return_button() -> void:
	var target = previous_scene_id
	if target == "":
		target = GameState.last_port
	if target == "" or target == current_scene_id:
		return
	var btn = Button.new()
	btn.text = "返回上一处"
	btn.pressed.connect(func(): load_scene(target))
	choices_container.add_child(btn)
	UiTheme.style_choice_button(btn)
	choices_label.visible = true


func _add_leave_button(port_id: String) -> void:
	var btn = Button.new()
	btn.text = "离开"
	btn.pressed.connect(func(): load_scene(port_id))
	choices_container.add_child(btn)
	UiTheme.style_choice_button(btn)
	choices_label.visible = true


func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	var msg = inv_data.get("text", "")
	if msg != "":
		body_text.text += "\n\n" + msg
	apply_effects(inv_data.get("effects", {}))

	var next_sc = inv_data.get("next", "")
	if next_sc != "":
		load_scene(next_sc)
	else:
		btn.disabled = true


func show_choices(choices: Array) -> void:
	if choices.is_empty():
		return
	choices_label.visible = true
	var cinematic := str(current_scene_id).begins_with("cg_")
	var shown := 0
	var page_turns := 0
	for choice in choices:
		if not GameState.choice_visible(choice):
			continue
		var label := str(choice.get("label", "继续"))
		var btn = Button.new()
		btn.text = label
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_container.add_child(btn)
		UiTheme.style_choice_button(btn)
		# 卷首翻页只有一串省略号，收成居中朱印，不再铺成整条。
		# 真正的岔路（货引 / 策问）留挑签。
		if cinematic and _is_page_turn(label):
			UiTheme.style_button(btn, true)
			btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.custom_minimum_size = Vector2(168, 40)
			btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			page_turns += 1
		shown += 1
	if cinematic and shown > 0 and page_turns == shown:
		choices_label.visible = false
	if shown == 0:
		_add_fallback_return_button()


## 「…………」这类翻页，不是要玩家做决断。
func _is_page_turn(label: String) -> bool:
	var t := label.strip_edges()
	if t == "":
		return true
	for i in t.length():
		var ch := t.unicode_at(i)
		if ch != 0x2026 and ch != 0x002E and ch != 0x3002 and ch != 0x00B7:
			return false
	return true


func _on_choice_pressed(choice_data: Dictionary) -> void:
	apply_effects(choice_data.get("effects", {}))
	var next_scene = choice_data.get("next", "")
	if next_scene != "":
		load_scene(next_scene)


func apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var val = effects[key]
		match key:
			"money":
				GameState.add_money(val)
			"fame":
				var fame_res: Dictionary = GameState.add_fame(int(val))
				if fame_res.get("promoted", false):
					log_msg("市舶司案册改题「%s」。" % str(fame_res.get("title", {}).get("name", "")))
			"days":
				GameManager.advance_days(val)
			"flag":
				GameState.set_flag(str(val))
			"chapter":
				GameState.chapter = maxi(GameState.chapter, int(val))
			"network":
				GameState.network += int(val)
			"merchant_credit":
				GameState.merchant_credit += int(val)
			"sea_tendency":
				GameState.sea_tendency += int(val)
			"scholar_tendency":
				GameState.scholar_tendency += int(val)
			"ledger_note":
				GameState.add_ledger_note(str(val))
	update_status_panel()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if _activate_first_choice():
			get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_debug_preview_ending()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:
			_debug_jump_port()
			get_viewport().set_input_as_handled()


func _activate_first_choice() -> bool:
	for child in choices_container.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).pressed.emit()
			return true
	if title_mode.visible and start_button.visible and not start_button.disabled:
		start_button.pressed.emit()
		return true
	return false


## 调试局跳港。第一次泉州（剧情九卡），再按福州（通用九卡），再按兴化回访。
## 设施页 current_scene_id 是 {港}_guild，要剥后缀，否则会误跳回泉州。
func _debug_jump_port() -> void:
	var here := current_scene_id
	if not here.begins_with("city_"):
		for suffix in FACILITY_SUFFIXES:
			if here.ends_with(suffix):
				here = here.trim_suffix(suffix)
				break
	if here == "quanzhou":
		GameState.last_port = "fuzhou"
		load_scene("fuzhou")
		return
	if here == "fuzhou":
		GameState.last_port = "xinghua"
		load_scene("xinghua")
		return
	GameState.last_port = "quanzhou"
	load_scene("quanzhou")


## 调试局预览了结弹窗。沙盒攒到八万+占城太慢，云电脑点验用。
func _debug_preview_ending() -> void:
	GameState.chapter = 4
	if GameState.money < 80000:
		GameState.add_money(80000 - GameState.money)
	GameState.peak_money = maxi(GameState.peak_money, 80000)
	for pid in ["quanzhou", "xinghua", "fuzhou", "wenzhou", "zhangzhou", "penghu", "ryukyu", "mingzhou", "hakata", "jeju", "kagoshima", "guangzhou", "champa"]:
		GameState.visit_port(pid)
	if not GameState.has_flag("chen_line_open") and not GameState.has_flag("merchant_distance") and not GameState.has_flag("history_pressure_seen"):
		GameState.set_flag("chen_line_open")
	GameState.last_port = "champa"
	var res := GameState.try_resolve_ending()
	if res.get("resolved", false):
		_show_chapter_dialog(res)
	else:
		log_msg("预览了结未触发。")
	update_status_panel()
