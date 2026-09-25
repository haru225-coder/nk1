extends Control

@onready var background: TextureRect = $Background
## 当前底图文件名（_set_background_file 写入），供门禁核对
var _bg_file := ""
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
## 牙行当前选中的船 index（多船分装用）。进牙行时重置为旗舰；
## 同页换船或买卖后刷新时保留，否则选中会被 load_scene 清掉。
var _market_ship: int = 0
var _market_hold: bool = false
## 牙行委办「细则」展开与否（会话内 UI 状态，不入存档；买卖刷新页面时保留）
var _contract_detail_open := false
## 账条暂时写入的容器。酒馆募人收进内滚，离开钮留在外面。
var _slip_host: Node = null
var _ledger_layer: Control
var _status_strip: PanelContainer
var _status_line: RichTextLabel
var _status_note: Label
## 船籍簿记事：最近 LOG_KEEP 条（会话内，不入存档）。原先整串无限拼接，空时是一块空墨框
var _log_lines: PackedStringArray = PackedStringArray()
const LOG_KEEP := 8
var _page_footer: HBoxContainer
## 内页滚动区（_split_page_footer 摘出来的 Scroll）
var _page_scroll: ScrollContainer
## 当前是序章对白条（cg_ 酒棚各页）：点画面任意处续读
var _cg_dialogue := false
## 见面册页上的话。原 RichTextLabel 在这栏里排不出行，改用能折行的 Label。
var _npc_speech: RichTextLabel
## 航海日志册页。系统对话框会把三卷撑出 1280 宽的窗口。
var _save_host: Control
## 升章 / 了结册页。同一理由，不用系统对话框。
var _chapter_host: Control
var _chapter_next_scene: String = ""
## 今日岸上开着的去处。再候一日之前这一手不变。
var shore_hand: PackedStringArray = PackedStringArray()
var _shore_facilities: Array = []
## 本港的设施表（进港时从场景数据记下；守城 / 终局页不用它，「再候一日」回寻常岸带时要用）
var _port_scene_facilities: Array = []
## 岸带页型：port 寻常 / siege 兴化守城 / ended 终局后港口。UI 状态，不入存档。
var _shore_mode := "port"
## 今日柜上的三样货。明日再看之前这一手不变。
var broker_hand: PackedStringArray = PackedStringArray()

## 过场接线（cinematics 线）：开场 / 章节卡 / 结局过场 / 抵港横幅 / 活背景 / 标题演出。
## headless（门禁）下全部旁路：Cinematics.live() 为假，当帧照原逻辑走，不延迟。会话状态在 Cinematics 静态变量里，不进存档。
const _CINE := preload("res://scripts/cutscene/Cinematics.gd")
const _CS_PLAYER := preload("res://scripts/cutscene/CutscenePlayer.gd")
const _CS_CARD := preload("res://scripts/cutscene/ChapterCard.gd")
const _CS_BANNER := preload("res://scripts/cutscene/PortBanner.gd")
const _CS_BACKDROP := preload("res://scripts/cutscene/LivingBackdrop.gd")
const _TITLE_STAGE := preload("res://scripts/cutscene/TitleStage.gd")
## 活背景幅度：比引擎默认再收一档（正文底下的画不能晃得人头晕）
const BACKDROP_OPTS := {"breath": 0.018, "period": 52.0, "pan": 0.35, "vignette": 0.26, "grain": 0.028}
## 本次 load_scene 是海图回港的真正抵港：_on_enter_port 据此出横幅（读档、设施间来回为假）
var _arrival_banner := false
## 起始标题页的「重看开场」
var _rewatch_button: Button
## 起始标题页的「续卷」（有存档才显示）
var _resume_button: Button

## 人物系统（characters 线）：立绘 / 五维 / 特技 / 人物志。只作展示，不入存档
const _CHAR_ART := preload("res://scripts/ui/CharacterArt.gd")
const _CODEX := preload("res://scripts/ui/CharacterCodex.gd")
## 酒馆人物卡上的小立绘（逻辑像素，4:5）
const HIRE_PIC := Vector2i(84, 105)
## 船籍簿职事列表的小头像
const ROSTER_HEAD := 24
var _codex: Control
var _codex_title_button: Button
var _npc_courtesy: Label
var _npc_faction: HBoxContainer
var _npc_profile: VBoxContainer
var _npc_codex_btn: Button
var _npc_codex_id := ""

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
	# 活背景：呼吸推拉 + 暗角 + 细颗粒；顺带把过场 / 章节卡 / 横幅的 shader 管线预热掉。headless 下不做事
	_CS_BACKDROP.attach(background, BACKDROP_OPTS)
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
	if UiTheme.IS_JUANBEN:
		# 大主钮：马善政 28、字间加宽，196×52 的印面不再显空（第 1 轮评审 minor 4）
		start_button.add_theme_font_size_override("font_size", 28)
		start_button.add_theme_font_override("font", UiTheme.seal_font(8))
	UiTheme.hook_buttons(choices_container, true)
	choices_container.add_theme_constant_override("separation", 6)
	UiTheme.hook_buttons(right_facilities)
	UiTheme.hook_buttons(npc_actions)
	UiTheme.style_heading(scene_title)
	UiTheme.style_body(body_text)
	UiTheme.style_body(status_label)
	UiTheme.style_body(message_label)
	message_label.add_theme_stylebox_override("normal", UiTheme.log_well())
	_render_log()
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
	_mount_status_strip()
	_lift_ledger()
	_split_page_footer()
	($HBoxContainer/CenterArea as Control).gui_input.connect(_on_stage_click)
	investigation_mode.gui_input.connect(_on_stage_click)
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
	# 绢本：抬头与「航海日志」同一字阶（SIZE_HEAD）；正文左右留 18，不贴金线（第 1 轮评审 minor 3）
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD if UiTheme.IS_JUANBEN else UiTheme.SIZE_BODY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UiTheme.IS_JUANBEN:
		var lm := $HBoxContainer/LeftPanel/MarginContainer as MarginContainer
		lm.add_theme_constant_override("margin_left", 28)
		lm.add_theme_constant_override("margin_right", 28)
		lm.add_theme_constant_override("margin_top", 18)
		lm.add_theme_constant_override("margin_bottom", 20)
	var rule := $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/HSeparator
	if rule is Separator:
		var line := StyleBoxLine.new()
		line.color = Color(UiTheme.GOLD, 0.45)
		line.thickness = 1
		rule.add_theme_stylebox_override("separator", line)


## 顶上一匾。左栏收起来之后，日期和钱留在这里。
func _mount_status_strip() -> void:
	var strip := PanelContainer.new()
	strip.name = "StatusStrip"
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_left = 16
	strip.offset_top = 8
	strip.offset_right = -16
	strip.offset_bottom = 76
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.add_theme_stylebox_override("panel", UiTheme.plaque())
	strip.visible = false
	add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(row)
	# 两行：上行日期、钱、水粮、章（富文本上色）；下行最新一条记事（Label，超长以「…」收尾、全文挂 tooltip）。
	# 原先下行也是不折行的富文本，超长直接截断，旧闻点睛那半句看不到（第 2 轮 UX M3）
	var lines := VBoxContainer.new()
	lines.name = "StatusText"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	_status_line = RichTextLabel.new()
	_status_line.bbcode_enabled = true
	_status_line.fit_content = true
	_status_line.scroll_active = false
	_status_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_line.clip_contents = true
	_status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_body(_status_line)
	lines.add_child(_status_line)
	_status_note = Label.new()
	_status_note.name = "StatusNote"
	_status_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_note.clip_text = true
	_status_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_note.custom_minimum_size = Vector2(80, 0)
	_status_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_status_note.add_theme_font_override("font", UiTheme.font())
	_status_note.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_status_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	lines.add_child(_status_note)
	var book := Button.new()
	book.text = "船籍簿"
	book.custom_minimum_size = Vector2(120, 40)
	book.pressed.connect(_toggle_ledger)
	UiTheme.style_button(book, false)
	row.add_child(book)
	_status_strip = strip


## 船籍簿从横排里摘出来，点开才盖在画面上。
func _lift_ledger() -> void:
	var layer := Control.new()
	layer.name = "LedgerLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = UiTheme.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_ledger_dim_input)
	layer.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	left_panel.get_parent().remove_child(left_panel)
	left_panel.custom_minimum_size = Vector2(480, 600)
	left_panel.visible = true
	holder.add_child(left_panel)
	status_label.scroll_active = true
	status_label.custom_minimum_size = Vector2(0, 360)
	var close := Button.new()
	close.text = "合上"
	close.custom_minimum_size = Vector2(0, 40)
	if UiTheme.IS_JUANBEN:
		# 绢本：印钮居中定宽，不拉成通栏红条
		close.custom_minimum_size = Vector2(160, 40)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_ledger)
	UiTheme.style_button(close, true)
	left_panel.get_node("MarginContainer/VBoxContainer").add_child(close)
	_ledger_layer = layer


## 内页滚动区下面留一条，离开钉在这里，不跟工席一起滚出画面。
func _split_page_footer() -> void:
	var margin: MarginContainer = investigation_mode.get_node("MarginContainer")
	var scroll: ScrollContainer = margin.get_node("Scroll")
	_page_scroll = scroll
	margin.remove_child(scroll)
	var col := VBoxContainer.new()
	col.name = "PageColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.clip_contents = true
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var inner := scroll.get_node_or_null("VBoxContainer")
	if inner is VBoxContainer:
		inner.add_theme_constant_override("separation", 6)
	col.add_theme_constant_override("separation", 8)
	# 滚动区底边 24px 渐隐：牙行货卡、酒馆第三排原先被视口底边一刀切断（第 2 轮美术 M3）
	var faded := UiTheme.fade_scroll(scroll, 24)
	faded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(faded)
	var footer := HBoxContainer.new()
	footer.name = "PageFooter"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	_page_footer = footer


func _clear_page_footer() -> void:
	if _page_footer == null:
		return
	var stale: Array = _page_footer.get_children()
	for child in stale:
		_page_footer.remove_child(child)
		child.queue_free()


func _show_strip(show: bool) -> void:
	if _status_strip == null:
		return
	_status_strip.visible = show
	var box := $HBoxContainer
	box.offset_top = 84 if show else 16


func _toggle_ledger() -> void:
	if _ledger_layer == null:
		return
	if _ledger_layer.visible:
		_close_ledger()
		return
	_dismiss_banner()
	_ledger_layer.visible = true
	move_child(_ledger_layer, get_child_count() - 1)
	UiTheme.pop_in(left_panel)


## 离开港页（进设施、开船籍簿 / 人物志 / 航海日志）时抵港横幅快速淡去，不压在内页上（第 2 轮 UX M1）
func _dismiss_banner() -> void:
	if is_inside_tree():
		_CS_BANNER.dismiss_all(get_tree(), 0.15)


## 港页工作层（岸带：工席、小笺、门排、动作行；顶上港名匾）淡去 / 回来。
## 结局册页压在港页上时工作层先退，结局最后一眼只留结局图与册页（第 2 轮美术 M2）；航海日志浮层只让开港名匾。
## 只动 modulate，不改 visible（门禁量的是排版与可见性），不入存档；headless 下直接设值。
func _show_port_layer(show: bool, dur := 0.2, plate_only := false) -> void:
	var nodes: Array = [port_mode.get_node_or_null("PortPlaqueHolder")]
	if not plate_only:
		nodes.append(port_mode.get_node_or_null("ShoreBand"))
	for n in nodes:
		if not (n is CanvasItem):
			continue
		var ci := n as CanvasItem
		var old: Variant = ci.get_meta(&"nk1_fade_tw") if ci.has_meta(&"nk1_fade_tw") else null
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		var target := 1.0 if show else 0.0
		if dur <= 0.0 or not ci.is_inside_tree() or not _CINE.live():
			ci.modulate.a = target
			continue
		var tw := ci.create_tween()
		tw.tween_property(ci, "modulate:a", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ci.set_meta(&"nk1_fade_tw", tw)


func _close_ledger() -> void:
	if _ledger_layer != null:
		_ledger_layer.visible = false


func _on_ledger_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			_close_ledger()


func _monsoon_short() -> String:
	var desc := Calendar.get_monsoon_desc()
	if desc.begins_with("东北"):
		return "东北风"
	if desc.begins_with("西南"):
		return "西南风"
	return "转换期"


func _latest_log() -> String:
	if _log_lines.is_empty():
		return ""
	return _log_lines[0].strip_edges()


func _chapter_hint() -> String:
	var prog := GameState.chapter_progress()
	if prog.get("ended", false):
		return "了结　%s" % str(prog.get("ending_title", ""))
	if prog.get("final", false) and prog.get("items", []).is_empty():
		return "终章・可了结"
	for it in prog.get("items", []):
		if it.get("done", false):
			continue
		if int(it.get("need", 1)) > 1:
			return "%s　%d / %d" % [it.get("label", ""), it.get("current", 0), it.get("need", 1)]
		return str(it.get("label", ""))
	if prog.get("final", false):
		return "终章・可了结"
	return ""


func _refresh_strip() -> void:
	if _status_line == null:
		return
	var supply_d := Fleet.supply_days()
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY
	var debt := ""
	if GameState.debt > 0:
		debt = "　[color=#%s]欠 %d[/color]" % [UiTheme.hex(UiTheme.HONEY), GameState.debt]
	var line1 := "%s　%s　钱 %d%s　[color=#%s]水粮 %d 日[/color]　第%s章・%s" % [
		Calendar.get_date_string(),
		_monsoon_short(),
		GameState.money,
		debt,
		UiTheme.hex(supply_color),
		supply_d,
		_cn_chapter(GameState.chapter),
		str(GameState.chapter_def().get("name", "")),
	]
	var note := _latest_log()
	if note == "":
		note = _chapter_hint()
	_status_line.text = line1
	if _status_note != null:
		var plain := note.replace("\n", "　")
		_status_note.text = plain
		_status_note.tooltip_text = note if note.length() > 30 else ""


func _dress_title() -> void:
	main_title.add_theme_font_override("font", UiTheme.title_font())
	main_title.add_theme_font_size_override("font_size", 52)
	main_title.add_theme_color_override("font_color", UiTheme.GOLD)
	UiTheme.style_overlay(main_title)
	sub_title.add_theme_font_override("font", UiTheme.font())
	sub_title.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	sub_title.add_theme_color_override("font_color", UiTheme.TEXT)
	sub_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_overlay(sub_title)
	# 绢本：题名是「东亚海域立志传」时换成书法（_setup_title_mode 里 sync_title_logo 切换；夜潮 title_logo() 为 null）
	var logo := UiTheme.title_logo()
	if logo != null and main_title.get_parent().get_node_or_null("TitleLogo") == null:
		main_title.get_parent().add_child(logo)
		main_title.get_parent().move_child(logo, main_title.get_index())
		logo.visible = false
	# 起始标题页的「重看开场」：墨钮，排在开卷钮下面；只在起始标题页显示（_setup_title_mode 切换）
	if _rewatch_button == null:
		_rewatch_button = Button.new()
		_rewatch_button.name = "RewatchButton"
		_rewatch_button.text = "重看开场"
		_rewatch_button.custom_minimum_size = Vector2(150, 38)
		_rewatch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_rewatch_button.visible = false
		UiTheme.style_button(_rewatch_button)
		_rewatch_button.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		_rewatch_button.pressed.connect(_on_rewatch_opening)
		# 「重看开场」与「人物志」并排一行，排在开卷钮下面（characters 线加人物志）
		var aux := HBoxContainer.new()
		aux.name = "TitleAux"
		aux.alignment = BoxContainer.ALIGNMENT_CENTER
		aux.add_theme_constant_override("separation", 16)
		aux.mouse_filter = Control.MOUSE_FILTER_IGNORE
		start_button.get_parent().add_child(aux)
		# 「续卷」：本机航海日志里记过卷才出，点开航海日志（只能翻阅，不能记录）——回头玩家不必再走一遍序章
		_resume_button = Button.new()
		_resume_button.name = "ResumeButton"
		_resume_button.text = "续卷"
		_resume_button.custom_minimum_size = Vector2(150, 38)
		_resume_button.visible = false
		UiTheme.style_button(_resume_button)
		_resume_button.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		_resume_button.pressed.connect(_show_save_dialog.bind(true))
		aux.add_child(_resume_button)
		aux.add_child(_rewatch_button)
		_codex_title_button = Button.new()
		_codex_title_button.name = "CodexTitleButton"
		_codex_title_button.text = "人物志"
		_codex_title_button.custom_minimum_size = Vector2(150, 38)
		_codex_title_button.visible = false
		UiTheme.style_button(_codex_title_button)
		_codex_title_button.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		_codex_title_button.pressed.connect(_open_codex.bind(""))
		aux.add_child(_codex_title_button)
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
	plaque.add_theme_stylebox_override("panel", UiTheme.title_plaque())
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
	plaque.add_theme_stylebox_override("panel", UiTheme.port_plaque())
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
	# 绢本：换成旧绢裱框 + 名牌（夜潮返回 false，上面的画框照旧）
	UiTheme.frame_portrait(frame, npc_portrait)


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
	# 底边距 24：「离开」钮离开面板底线与泥金框饰（原 14 时钮的下沿压在框线上）
	margin.add_theme_constant_override("margin_bottom", 24)
	sheet.add_child(margin)
	dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(dialog)
	UiTheme.style_heading(npc_name_lbl)
	npc_dialog_lbl.fit_content = true
	npc_dialog_lbl.scroll_active = false
	npc_dialog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_dialog_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_body(npc_dialog_lbl)
	npc_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_actions.add_theme_constant_override("separation", 8)
	_mount_npc_profile(dialog)


## 见面页的人物栏（characters 线）：名字一行并上字号与阵营签，下面身份、五维、特技、小传。
## 内容由 _show_npc_mode 按 characters.json 填；查无此人时整栏藏起，见面页照旧。
func _mount_npc_profile(dialog: Node) -> void:
	var head := HBoxContainer.new()
	head.name = "NPCHead"
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at := npc_name_lbl.get_index()
	dialog.remove_child(npc_name_lbl)
	head.add_child(npc_name_lbl)
	npc_name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_npc_courtesy = _CHAR_ART.label("", UiTheme.SIZE_FOOT + 2, UiTheme.TEXT_DIM)
	_npc_courtesy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_npc_courtesy)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_npc_faction = HBoxContainer.new()
	_npc_faction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_npc_faction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_npc_faction)
	# 翻到人物志里此人那一页
	_npc_codex_btn = Button.new()
	_npc_codex_btn.name = "NPCCodexButton"
	_npc_codex_btn.text = "人物志"
	_npc_codex_btn.custom_minimum_size = Vector2(88, 32)
	_npc_codex_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_npc_codex_btn.visible = false
	UiTheme.style_button(_npc_codex_btn)
	_npc_codex_btn.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT + 1)
	_npc_codex_btn.pressed.connect(func() -> void: _open_codex(_npc_codex_id))
	head.add_child(_npc_codex_btn)
	dialog.add_child(head)
	dialog.move_child(head, at)
	_npc_profile = VBoxContainer.new()
	_npc_profile.name = "NPCProfile"
	_npc_profile.add_theme_constant_override("separation", 8)
	_npc_profile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_npc_profile.visible = false
	dialog.add_child(_npc_profile)
	dialog.move_child(_npc_profile, at + 1)


func _fill_npc_profile(ch: Dictionary) -> void:
	if _npc_profile == null:
		return
	for box in [_npc_profile, _npc_faction]:
		var stale: Array = (box as Node).get_children()
		for c in stale:
			(box as Node).remove_child(c)
			c.queue_free()
	_npc_courtesy.text = _CHAR_ART.courtesy_of(ch)
	_npc_profile.visible = not ch.is_empty()
	_npc_codex_id = str(ch.get("id", ""))
	_npc_codex_btn.visible = _npc_codex_id != ""
	if ch.is_empty():
		return
	_npc_faction.add_child(_CHAR_ART.faction_chip(ch))
	var ident := _CHAR_ART.identity_line(ch)
	var life := _CHAR_ART.life_line(ch)
	if life != "":
		ident = "%s　%s" % [ident, life]
	var ident_lbl := _CHAR_ART.label(ident, UiTheme.SIZE_BODY - 1, UiTheme.TEXT_DIM)
	_npc_profile.add_child(ident_lbl)
	_npc_profile.add_child(_CHAR_ART.rule(0.40))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_npc_profile.add_child(row)
	row.add_child(_CHAR_ART.attr_block(ch, 150.0, 16))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(side)
	if not _CHAR_ART.traits_of(ch).is_empty():
		side.add_child(_CHAR_ART.trait_row(ch, 17))
	# 简介走人物志上屏文本层（按年份取可见段）；设定集原稿 bio_short 带着未来年号与结局，不上屏
	var bio := _CHAR_ART.label(_CHAR_ART.codex_short(ch), UiTheme.SIZE_BODY - 1, UiTheme.TEXT)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_constant_override("line_spacing", 6)
	bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(bio)
	_npc_profile.add_child(_CHAR_ART.rule(0.40))


## 调查页平时铺满中栏；卷首 cg_ 收成居中的册页，顶栏让开。
## dialogue=true（序章酒棚各页）：收成画面下三分之一的对白条，高度随内容往上长，正文 20px，名牌写说话人。
func _frame_sheet(floating: bool, dialogue := false) -> void:
	_show_strip(not floating)
	var sheet_margin: MarginContainer = investigation_mode.get_node("MarginContainer")
	_cg_dialogue = floating and dialogue
	if _page_scroll != null:
		# 对白条不滚动：滚动区关掉竖向滚动后按内容给最小高，面板随之长高
		_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _cg_dialogue else ScrollContainer.SCROLL_MODE_AUTO
	body_text.add_theme_font_size_override("normal_font_size", 20 if _cg_dialogue else UiTheme.SIZE_BODY)
	if _cg_dialogue:
		_close_ledger()
		sheet_margin.add_theme_constant_override("margin_top", 20)
		sheet_margin.add_theme_constant_override("margin_bottom", 16)
		investigation_mode.anchor_left = 0.0
		investigation_mode.anchor_top = 1.0
		investigation_mode.anchor_right = 1.0
		investigation_mode.anchor_bottom = 1.0
		investigation_mode.offset_left = 72
		investigation_mode.offset_top = -196
		investigation_mode.offset_right = -72
		investigation_mode.offset_bottom = -12
		investigation_mode.grow_vertical = Control.GROW_DIRECTION_BEGIN
		scene_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_fit_dialogue.call_deferred()
		return
	investigation_mode.grow_vertical = Control.GROW_DIRECTION_BOTH
	if floating:
		_close_ledger()
		sheet_margin.add_theme_constant_override("margin_top", 22)
		sheet_margin.add_theme_constant_override("margin_bottom", 18)
		investigation_mode.anchor_left = 0.5
		investigation_mode.anchor_top = 0.5
		investigation_mode.anchor_right = 0.5
		investigation_mode.anchor_bottom = 0.5
		investigation_mode.offset_left = -430
		investigation_mode.offset_top = -268
		investigation_mode.offset_right = 430
		investigation_mode.offset_bottom = 268
	else:
		# 顶栏已经占了 68。内页上下再留 22 会把船屋第四排压进离开。
		# 底边留 22：面板泥金内线在内容区里约 10px 处，页脚的离开 / 明日再看要离开它与框饰 ≥12（第 1 轮评审 M3），滚动区少 14px。
		sheet_margin.add_theme_constant_override("margin_top", 8)
		sheet_margin.add_theme_constant_override("margin_bottom", 22)
		investigation_mode.anchor_left = 0.0
		investigation_mode.anchor_top = 0.0
		investigation_mode.anchor_right = 1.0
		investigation_mode.anchor_bottom = 1.0
		investigation_mode.offset_left = 0
		investigation_mode.offset_top = 0
		investigation_mode.offset_right = 0
		investigation_mode.offset_bottom = 0
	scene_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if floating else HORIZONTAL_ALIGNMENT_LEFT


## 对白条的高度随内容：滚动区外包的渐隐层是普通 Control，不往上报最小高，这里按内页 VBox 的最小高直接定面板上沿。
func _fit_dialogue() -> void:
	if not _cg_dialogue or _page_scroll == null:
		return
	var inner := _page_scroll.get_node_or_null("VBoxContainer") as Control
	if inner == null:
		return
	if not inner.minimum_size_changed.is_connected(_fit_dialogue):
		inner.minimum_size_changed.connect(_fit_dialogue)
	var h := inner.get_combined_minimum_size().y + 20.0 + 16.0 + 8.0 + 6.0
	h = clampf(h, 150.0, get_viewport_rect().size.y - 80.0 if is_inside_tree() else 560.0)
	investigation_mode.offset_top = -12.0 - h


func _on_monthly_notice(text: String) -> void:
	log_msg(text)
	update_status_panel()


func start_game() -> void:
	if GameState.has_flag("return_to_port"):
		GameState.flags.erase("return_to_port")
		# 海图回港：出过港且走了日子 / 换了港才算真正抵港，入港时出抵港横幅（原路折回、读档、设施间来回都不出）
		_arrival_banner = _CINE.take_arrival(GameState.last_port, Calendar.absolute_day())
		load_scene(GameState.last_port)
		_arrival_banner = false
	else:
		var start_id = GameManager.scenes_data.get("start_scene", "cg_title")
		# 新开一局：先演开场（从全黑起播，起始场景在黑幕底下就位，演完揭开）。本会话只自动演一次；headless 不演
		if _CINE.want_opening():
			_CINE.opening_seen = true
			_play_opening(true)
		load_scene(start_id)


func _play_opening(from_black := false) -> void:
	var p: Node = _CS_PLAYER.play(self, _CINE.OPENING, _CINE.DATA, from_black)
	if p != null:
		p.connect("finished", _on_opening_finished, CONNECT_ONE_SHOT)


## 开场演完（此刻全黑）：还停在标题页就把标题演出从头再来，黑幕退去时正好看见题名写出、印落下
func _on_opening_finished() -> void:
	if not title_mode.visible:
		return
	var stage := title_mode.get_node_or_null("TitleStage")
	if stage != null:
		stage.call("replay")


func _on_rewatch_opening() -> void:
	_play_opening(false)


## 人物志：一层浮页盖在当前画面上（港口页底、标题页进）。focus_id 非空直接开此人详页。不入存档。
func _open_codex(focus_id := "") -> void:
	_close_ledger()
	_dismiss_banner()
	if is_instance_valid(_codex) and not bool(_codex.get("_closing")):
		if focus_id != "":
			_codex.call("show_detail", focus_id, false)
		return
	var cx: Control = _CODEX.new()
	add_child(cx)
	cx.call("begin", focus_id)
	_codex = cx


func log_msg(text: String) -> void:
	_log_lines.insert(0, UiTheme.plain_log(text))
	if _log_lines.size() > LOG_KEEP:
		_log_lines.resize(LOG_KEEP)
	_render_log()
	_refresh_strip()


## 船籍簿记事栏：最近 8 条，新的在上（宣纸色），旧的淡一档；一条没有时写一行淡字，不留空墨框
func _render_log() -> void:
	if _log_lines.is_empty():
		message_label.text = "[color=#%s]（尚无记事）[/color]" % UiTheme.hex(UiTheme.TEXT_DIM)
		return
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	var parts := PackedStringArray()
	for i in _log_lines.size():
		var line := _log_lines[i]
		parts.append(line if i == 0 else "[color=#%s]%s[/color]" % [dim, line])
	message_label.text = "\n".join(parts)


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

	var permit_str := "在手" if GameState.has_customs_permit else "未领"
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
	t += "[color=#%s][b]船队[/b][/color]\n船数　%d　水手　%d\n舱位　%d / %d 料\n耐久　%d / %d\n士气　%d\n" % [
		gold,
		Fleet.ships.size(), Fleet.total_crew(),
		int(cap_used), int(cap_total),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水　%d　粮　%d　[color=#%s]足 %d 日[/color]\n" % [
		Fleet.water, Fleet.food, UiTheme.hex(supply_color), supply_d,
	]

	# 职事行前的小头像（characters 线）：富文本里只能 add_image，先在串里留记号，末尾 _set_status_text 换图
	var heads: Array = []
	if not Crew.hired.is_empty():
		t += "[color=#%s][b]职事[/b][/color]\n" % gold
		for c in Crew.roster():
			var head_tex := _roster_head(str(c.get("id", "")))
			if head_tex != null:
				t += "%s%d%s" % [HEAD_MARK, heads.size(), HEAD_MARK]
				heads.append(head_tex)
			t += "%s　%s　%s\n" % [
				Crew.role_def(c.get("role", "")).get("name", ""),
				c.get("name", ""), _skill_rank(int(c.get("level", 1))),
			]
		var wage := Crew.monthly_wage()
		var wage_color := UiTheme.HONEY if Crew.unpaid_months > 0 else UiTheme.TEXT
		t += "[color=#%s]月俸共 %d" % [UiTheme.hex(wage_color), wage]
		if Crew.unpaid_months > 0:
			t += "　已欠 %d 月" % Crew.unpaid_months
		t += "[/color]\n"
	t += "[color=#%s][b]市舶[/b][/color]\n蒲家留意　%d\n货引　%s\n" % [
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
			var crew_str := "水手 %d / %d" % [Fleet.ship_crew(i), Fleet.ship_crew_max(i)]
			var crew_color := UiTheme.hex(UiTheme.TEXT)
			if Fleet.ship_crew(i) < Fleet.ship_crew_min(i):
				crew_color = UiTheme.hex(UiTheme.CINNABAR)
				crew_str += "　缺 %d 人" % (Fleet.ship_crew_min(i) - Fleet.ship_crew(i))
			t += "　%s　%s　%d / %d 料　帆%s　甲%s　[color=#%s]%s[/color]　%s\n" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_cargo_bulk(i)), int(Fleet.ship_capacity(i)),
				_fit_rank(Fleet.sail_level(i)), _fit_rank(Fleet.armor_level(i)),
				crew_color, crew_str, per_ship,
			]

	var cst := GameState.contract_status()
	if not cst.is_empty():
		var left: int = int(cst.get("days_left", 0))
		var left_s := "今日截止" if left == 0 else ("%d 日后截止" % left if left > 0 else "已逾期")
		var col := "yellow" if left <= 2 else "white"
		if left < 0:
			col = "red"
		t += "\n[u]委办[/u]\n[color=%s]%s ×%d 运往 %s（%s）酬 %d[/color]\n" % [
			col,
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("remaining", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			left_s,
			int(cst.get("pay_left", 0)),
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
			t = _append_progress_line(t, it)
	else:
		for it in prog.get("items", []):
			t = _append_progress_line(t, it)

	if heads.is_empty():
		status_label.text = t
	else:
		_set_status_text(t, heads)
	_refresh_strip()


## 富文本里的小头像记号（控制符，正文里不会出现）
const HEAD_MARK := "\u0001"


## 职事的小头像：头面方块、烤一道泥金边。headless 或查无立绘时返回 null，这一行照旧只有字。
func _roster_head(crew_id: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var ch: Dictionary = GameManager.character_for_crew(crew_id)
	if ch.is_empty():
		return null
	return _CHAR_ART.thumb(ch, Vector2i(ROSTER_HEAD, ROSTER_HEAD), true, Color(UiTheme.GOLD, 0.9))


## 船籍簿正文：按记号切开，字段照 bbcode 追加，记号处插小头像（与文字行垂直居中）。
func _set_status_text(t: String, heads: Array) -> void:
	# 先置空（text 属性归零，下回整串赋值一定重排），再逐段追加
	status_label.text = ""
	var parts := t.split(HEAD_MARK)
	for i in parts.size():
		if i % 2 == 1:
			var k := int(parts[i])
			if k >= 0 and k < heads.size():
				status_label.add_image(heads[k], ROSTER_HEAD, ROSTER_HEAD, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				status_label.append_text(" ")
		elif parts[i] != "":
			status_label.append_text(parts[i])


func _append_progress_line(text: String, it: Dictionary) -> String:
	var mark := "・"
	if it.get("done", false):
		mark = "[color=#%s]已[/color]" % UiTheme.hex(UiTheme.MOSS)
	if int(it.get("need", 1)) > 1:
		return text + "%s　%s　%d / %d\n" % [mark, it.get("label", ""), it.get("current", 0), it.get("need", 1)]
	return text + "%s　%s\n" % [mark, it.get("label", "")]


## 船体改装是一等、二等、三等。职事品级另用初习 / 谙熟 / 老练，两套词不混。
func _fit_rank(n: int) -> String:
	if n >= 3:
		return "三等"
	if n == 2:
		return "二等"
	if n <= 0:
		return "未装"
	return "一等"


## 船屋悬停用的成数。12 是一成二，90 是九成。只换说法，不改加成。
func _cheng_phrase(percent: int) -> String:
	if percent <= 0:
		return ""
	var digits := PackedStringArray(["", "一", "二", "三", "四", "五", "六", "七", "八", "九"])
	var cheng := int(percent / 10)
	var rest := int(percent % 10)
	var s := ""
	if cheng >= 10:
		s = "十成"
	elif cheng > 0:
		s = digits[cheng] + "成"
	if rest > 0:
		s += digits[rest]
	return s


func _sail_fit_phrase(level: int) -> String:
	var extra := int(round(12.0 * float(level)))
	if extra <= 0:
		return "此帆比光船并不更快"
	return "此帆比光船快%s" % _cheng_phrase(extra)


func _armor_fit_phrase(level: int) -> String:
	var left := int(round((1.0 - 0.10 * float(level)) * 100.0))
	if left >= 100:
		return "船体伤并不减轻"
	return "船体伤剩%s" % _cheng_phrase(left)


## 职衔抽解写成每百剩多少。1 是 100，0.94 是 94。只换说法。
func _duty_per_hundred(factor: float) -> int:
	return int(round(factor * 100.0))


## scenes.json 里四张兴化序章内页标题写成「内景」。画面上改成港名・去处，正文不动。
func _interior_title(scene_id: String) -> String:
	var names := {
		"city_guild": "行会",
		"city_residence": "住处",
		"city_exam": "贡院",
		"city_tavern": "酒馆",
		"city_shipyard": "船屋",
	}
	var place := str(names.get(scene_id, ""))
	if place == "":
		return "内室"
	var port_id := str(GameState.last_port)
	var port_name := ""
	if port_id != "":
		port_name = GameManager.get_port_name(port_id)
	if port_name == "" or port_name == port_id:
		port_name = "兴化"
	return "%s・%s" % [port_name, place]


## 内景页的 JSON 正文是空的。进门补一句屋子说明，点调查项才展开原文。
func _interior_lead(scene_id: String) -> String:
	match scene_id:
		"city_guild":
			return "行首正与几名蕃商核对舱位。墙上钉着一张抄来的远港价目。"
		"city_residence":
			return "一间租来的下处，屋角堆着几卷未拆的旧账。"
		"city_exam":
			return "贡院朱门紧闭。今科未开，阶下只有几个背着书箧的士子在张望。"
		"city_tavern":
			return "劣酒和喧哗。邻桌有人压低了声音。"
		"city_shipyard":
			return "桐油和潮气。坞里还停着没漆完的船板。"
		_:
			return ""


# ══════════════════════════════════════════════════════
#  场景加载
# ══════════════════════════════════════════════════════

func load_scene(scene_id: String) -> void:
	var overdue := GameState.tick_contract()
	_load_scene_inner(scene_id)
	if overdue != "":
		log_msg(overdue)
	update_status_panel()


func _load_scene_inner(scene_id: String) -> void:
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
		# scenes.json 只为少数港口写了剧情场景；其余按 ports.json 生成通用港口界面。
		# 流求、博多的正文不占用港口 id（ryukyu_bay / hakata_ledger，按云端 00b4 定名），
		# 否则海图回港进剧情、不记 visited_ports，牙行也进不去。
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
		# 卷首题名与四方沙盘（title 型）压在世界图上；其余 cg_ 序章页的戏都在兴化海口那间漏风的酒棚里（雨夜、惊雷），
		# 换成酒棚油画并压成夜色——原先一律世界地图，酒棚、老兵的戏也压在标题同款地图上（第 2 轮 UX M6）
		if type == "title":
			_set_background_file("bg_world_map.jpg")
		else:
			_set_background_file(PROLOGUE_BG)
			_CS_BACKDROP.set_grade(background, "night")
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


## 港口 → 背景图（2026-09-14 起 ports.json 十四港全部有专属图；check_assets.py 会查漏）
const PORT_BG := {
	"quanzhou": "bg_quanzhou_harbor.jpg",
	"xinghua": "bg_xinghua_study.jpg",
	"xinghua_harbor": "bg_xinghua_harbor.jpg",
	"fuzhou": "bg_fuzhou_yamen.jpg",
	"zhangzhou": "bg_zhangzhou.jpg",
	"wenzhou": "bg_wenzhou.jpg",
	"mingzhou": "bg_mingzhou.jpg",
	"jeju": "bg_jeju.jpg",
	"hakata": "bg_hakata.jpg",
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


## 兜底底图：任何背景文件缺失时都回落到它，不让画面黑屏
const FALLBACK_BG := "bg_sea_route.jpg"
## 序章酒棚（cg_narrate / veteran / wine_shed / ana / servant / decision / choice 各页）
const PROLOGUE_BG := "bg_xinghua_wine_shed.jpg"

## 结局名 → 结算底图。结局对话框弹出时换上，之后的终局港页也一直压着它——游戏已经结束了，
## 港口不再是港口，是尾声。键必须与 GameState.finish() 收到的结局名一字不差。
const ENDING_BG := {
	"忠肃": "bg_end_temple.jpg",
	"未归": "bg_end_siege.jpg",
	"海上宋鬼": "bg_end_yashan.jpg",
	"泉州蒲氏的船": "bg_end_pu.jpg",
	"纲首": "bg_end_pu.jpg",
	"岸上的根": "bg_end_root.jpg",
}


func _apply_background(type: String, loc: String) -> void:
	var file := FALLBACK_BG
	if GameState.is_ended() and ENDING_BG.has(GameState.ended):
		file = ENDING_BG[GameState.ended]
	elif type == "title":
		file = "bg_world_map.jpg"
	elif PORT_BG.has(loc):
		file = PORT_BG[loc]
	_set_background_file(file)


func _set_background_file(file_name: String) -> void:
	var tex := GameManager.load_texture("res://assets/" + file_name)
	if tex == null and file_name != FALLBACK_BG:
		# bg_world_map.jpg 等尚未落地的资产：宁可显示通用航海图，也不留上一屏或黑底
		push_warning("背景图缺失：%s，回落 %s" % [file_name, FALLBACK_BG])
		tex = GameManager.load_texture("res://assets/" + FALLBACK_BG)
		file_name = FALLBACK_BG
	if tex != null:
		background.texture = tex
		_bg_file = file_name  # 云端 load_texture 按字节解码，纹理没有 resource_path，门禁靠这个名字核对
		_grade_backdrop(file_name)


## 活背景随底图换调（未挂活背景时是空操作）：结局图压暮色，港页转成尾声；其余中性。
## 标题海图不开 shimmer：这张水墨海图的海面偏灰褐，过 shader 海面蒙版的像素只有约 4%，开了只会零星闪，只用呼吸推拉 + 暗角。
func _grade_backdrop(file_name: String) -> void:
	_CS_BACKDROP.set_grade(background, "dusk" if ENDING_BG.values().has(file_name) else "neutral")


func _drop_children(box: Node) -> void:
	var stale: Array = box.get_children()
	for child in stale:
		box.remove_child(child)
		child.queue_free()


func _enter_panel_mode() -> void:
	_dismiss_banner()
	_frame_sheet(false)
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	_drop_children(interactive_container)
	_drop_children(choices_container)
	_clear_page_footer()
	_slip_host = null
	_show_investigation_chrome(false)
	scene_title.visible = true
	var title_rule := scene_title.get_parent().get_node_or_null("HSeparator") as Control
	if title_rule != null:
		title_rule.visible = true
	choices_label.visible = false
	choices_label.text = "决断"  # 市场会改写它，此处复位避免上一屏文字残留
	update_status_panel()


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
		scene_title.text = "无人应门"
		body_text.text = "这条路眼下还走不通。先回港口去。"

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
	body_text.text = "柜上只摆三样。要看别的，明日再来。"

	_add_contract_panel(port_id)

	if not Economy.is_market_open(port_id):
		body_text.text += "\n\n牙行的门板上了闸。%s，城里只剩米价在动，没人敢开秤。" % Economy.war_label(port_id)
		_add_leave_button(port_id)
		return

	var goods_ids: Array = Economy.goods_at(port_id)
	if goods_ids.is_empty():
		body_text.text = "此地并无正经牙行，只有几个渔妇在晒网。"
		_add_leave_button(port_id)
		return

	# 多船时选船装货。从别的页进来回到旗舰；本页刷新则留下刚才那艘。
	if not _market_hold or _market_ship < 0 or _market_ship >= Fleet.ships.size():
		_market_ship = 0
	_market_hold = false
	if Fleet.ships.size() > 1:
		var sel := HFlowContainer.new()
		sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sel.add_theme_constant_override("h_separation", 6)
		sel.add_theme_constant_override("v_separation", 6)
		var lbl := Label.new()
		lbl.text = "装至"
		lbl.custom_minimum_size = Vector2(44, 0)
		UiTheme.style_footnote(lbl)
		lbl.add_theme_color_override("font_color", UiTheme.TEXT)
		sel.add_child(lbl)
		for i in range(Fleet.ships.size()):
			var idx := int(i)
			var s: Dictionary = Fleet.ships[idx]
			var chip := Button.new()
			chip.text = "%s　空 %d" % [s.get("name", "船"), int(Fleet.ship_free_capacity(idx))]
			chip.pressed.connect(_select_market_ship.bind(idx))
			sel.add_child(chip)
			UiTheme.style_chip(chip, idx == _market_ship)
		choices_container.add_child(sel)

	var catalog: Array = []
	for raw_gid in goods_ids:
		var gid := str(raw_gid)
		catalog.append({
			"id": gid,
			"role": str(Economy.get_role(port_id, gid)),
			"buy": Economy.buy_price(port_id, gid),
		})
	broker_hand = BrokerSlip.deal(catalog, GameState.broker_salt, _broker_held_id(port_id))

	var slips := HBoxContainer.new()
	slips.name = "BrokerSlips"
	slips.add_theme_constant_override("separation", 12)
	slips.alignment = BoxContainer.ALIGNMENT_CENTER
	slips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_container.add_child(slips)
	for slip_id in broker_hand:
		slips.add_child(_make_market_row(port_id, slip_id))

	# 「明日再看 / 离开」钉在页脚（与 _add_leave_button 同一处），不跟柜上三样一起滚出画面：
	# 1280×720 下这一行原先挂在滚动区里，静止时只露出上半截（第 1 轮评审 M2 / M8）
	var actions: HBoxContainer = _page_footer if _page_footer != null else HBoxContainer.new()
	var tomorrow := Button.new()
	tomorrow.text = "明日再看"
	tomorrow.custom_minimum_size = Vector2(160, 42)
	tomorrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tomorrow.pressed.connect(_on_broker_wait)
	UiTheme.style_button(tomorrow, false)
	actions.add_child(tomorrow)
	var leave := Button.new()
	leave.text = "离开"
	leave.custom_minimum_size = Vector2(120, 42)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func(): load_scene(port_id))
	UiTheme.style_leave_button(leave)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	actions.add_child(leave)
	if actions != _page_footer:
		actions.add_theme_constant_override("separation", 12)
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		choices_container.add_child(actions)

	var shut := HFlowContainer.new()
	shut.name = "BrokerShut"
	shut.add_theme_constant_override("h_separation", 8)
	shut.add_theme_constant_override("v_separation", 6)
	shut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_container.add_child(shut)
	for raw_shut in goods_ids:
		var shut_id := str(raw_shut)
		if shut_id in broker_hand:
			continue
		var shut_btn := Button.new()
		shut_btn.text = GameManager.get_good_name(shut_id)
		shut_btn.custom_minimum_size = Vector2(96, 34)
		shut_btn.set_meta("broker_shut", true)
		shut_btn.pressed.connect(_on_broker_shut)
		UiTheme.style_button(shut_btn, false)
		var shut_box := UiTheme.shore_shut()
		shut_btn.add_theme_stylebox_override("normal", shut_box)
		shut_btn.add_theme_stylebox_override("hover", shut_box)
		shut_btn.add_theme_stylebox_override("pressed", shut_box)
		shut_btn.add_theme_stylebox_override("focus", shut_box)
		shut_btn.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		shut_btn.add_theme_color_override("font_hover_color", UiTheme.TEXT_DIM)
		shut.add_child(shut_btn)

	choices_label.visible = true
	choices_label.text = "舱位 %d / %d 料" % [int(Fleet.used_capacity()), int(Fleet.total_capacity())]


func _broker_held_id(port_id: String) -> String:
	var best_id := ""
	var best_qty := 0
	for raw_gid in Economy.goods_at(port_id):
		var gid := str(raw_gid)
		var qty := Fleet.cargo_qty(gid, _market_ship)
		if qty > best_qty or (qty == best_qty and qty > 0 and (best_id == "" or gid < best_id)):
			best_qty = qty
			best_id = gid
	if best_qty <= 0:
		return ""
	return best_id


func _on_broker_wait() -> void:
	GameState.broker_salt += 1
	GameManager.advance_days(1)
	log_msg("柜上换了一手，日子过了一天。")
	_market_hold = true
	load_scene(current_scene_id)


func _on_broker_shut() -> void:
	log_msg("这件今日不在柜上。")
	update_status_panel()


func _add_contract_panel(port_id: String) -> void:
	var box := VBoxContainer.new()
	box.name = "ContractPanel"
	box.add_theme_constant_override("separation", 4)
	var cst := GameState.contract_status()
	if not cst.is_empty():
		var left: int = int(cst.get("days_left", 0))
		var left_s := "今日截止" if left == 0 else ("%d 日后截止" % left if left > 0 else "已逾期")
		# 一行：在身委办 + 交货 / 毁约（原先文字一行、钮另起一行）
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var head := Label.new()
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.text = "在身委办：%s ×%d（共 %d）送往 %s，%s。交清尚可得 %d 钱。舱里现有 %d。" % [
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("remaining", 0)),
			int(cst.get("qty", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			left_s,
			int(cst.get("pay_left", 0)),
			Fleet.cargo_qty(str(cst.get("good_id", ""))),
		]
		row.add_child(head)
		if str(cst.get("dest", "")) == port_id:
			var deliver := Button.new()
			deliver.text = "交货"
			deliver.disabled = Fleet.cargo_qty(str(cst.get("good_id", ""))) <= 0 or left < 0
			deliver.pressed.connect(_on_deliver_contract.bind(port_id))
			row.add_child(deliver)
		var drop := Button.new()
		drop.text = "毁约"
		drop.pressed.connect(_on_abandon_contract)
		row.add_child(drop)
		box.add_child(row)
	else:
		var offer := GameState.contract_offer(port_id)
		# 只在要写一句话时才建这枚 Label：委办摘要走自己的一行，旧的 head 不进树就成了孤儿节点，退出时报字体 RID 泄漏
		if GameState.contract_port_closed(port_id) or offer.is_empty():
			var head := Label.new()
			head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			head.text = "这个月已经毁约或误期，牙行不再委办。下个月再来。" if GameState.contract_port_closed(port_id) else "本月牙行没有外埠委办。"
			box.add_child(head)
		else:
			var dest := str(offer.get("dest", ""))
			var gid := str(offer.get("good_id", ""))
			var plan_r := Voyage.plan(port_id, dest, Voyage.CourseOrder.RUMB)
			var plan_o := Voyage.plan(port_id, dest, Voyage.CourseOrder.OFFSHORE)
			var plan_c := Voyage.plan(port_id, dest, Voyage.CourseOrder.COAST)
			var rumb: int = int(plan_r.get("days", 0))
			var off: int = int(plan_o.get("days", 0))
			var coast: int = int(plan_c.get("days", 0))
			var deadline: int = int(offer.get("deadline_days", 0))
			var route := "熟路" if Voyage.is_known_route(port_id, dest) else "生路"
			# 720p 下委办细则原先占去半页，把货卡的买卖钮挤出折线（第 2 轮美术 M3 / UX M2）：
			# 收成一行摘要 +「细则」钮；细则（航期、八成、保货、受潮、告警）展开才见，同文也挂在摘要的 tooltip 上。数值与回调不动。
			var summary_row := HBoxContainer.new()
			summary_row.name = "ContractSummary"
			summary_row.add_theme_constant_override("separation", 8)
			box.add_child(summary_row)
			var summary := Label.new()
			summary.name = "ContractLine"
			summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			summary.text = "委办　送 %s×%d 到%s（%s）・酬 %d・限 %d 日" % [
				GameManager.get_good_name(gid), int(offer.get("qty", 0)),
				GameManager.get_port_name(dest), route, int(offer.get("purse", 0)), deadline,
			]
			summary.mouse_filter = Control.MOUSE_FILTER_PASS
			summary_row.add_child(summary)
			var detail := VBoxContainer.new()
			detail.name = "ContractDetail"
			detail.add_theme_constant_override("separation", 2)
			detail.visible = _contract_detail_open
			var flag := Label.new()
			flag.name = "ContractFlag"
			flag.visible = false
			flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			flag.add_theme_font_size_override("font_size", 16)
			flag.add_theme_color_override("font_color", UiTheme.HONEY)
			summary_row.add_child(flag)
			var more := Button.new()
			more.name = "ContractMore"
			more.text = "收起" if _contract_detail_open else "细则"
			more.custom_minimum_size = Vector2(76, 32)
			more.pressed.connect(func() -> void:
				_contract_detail_open = not detail.visible
				detail.visible = _contract_detail_open
				more.text = "收起" if _contract_detail_open else "细则")
			summary_row.add_child(more)
			UiTheme.style_chip(more)
			var take_btn := Button.new()
			take_btn.text = "接下委办"
			take_btn.custom_minimum_size = Vector2(120, 32)
			take_btn.pressed.connect(_on_accept_contract.bind(offer.duplicate(true)))
			summary_row.add_child(take_btn)
			UiTheme.style_chip(take_btn, true)
			box.add_child(detail)
			var note_col := UiTheme.TEXT_DIM
			var warn_col := UiTheme.HONEY
			var lead := Label.new()
			lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lead.text = "酬 %d 钱，其中溢价 %d，交货不砸盘。静风针路 %d 日 / 外洋 %d 日 / 傍岸 %d 日，期限 %d 日。" % [
				int(offer.get("purse", 0)), int(offer.get("premium", 0)),
				rumb, off, coast, deadline,
			]
			lead.add_theme_font_size_override("font_size", 16)
			lead.add_theme_color_override("font_color", UiTheme.TEXT)
			detail.add_child(lead)
			var calm_note := Label.new()
			calm_note.text = "遇事约：针路 %d 日 / 外洋 %d 日 / 傍岸 %d 日。期限按静风针路加余量。" % [
				int(plan_r.get("expected_days", 0)), int(plan_o.get("expected_days", 0)), int(plan_c.get("expected_days", 0)),
			]
			if bool(plan_r.get("wind_changes", false)) or bool(plan_o.get("wind_changes", false)) or bool(plan_c.get("wind_changes", false)) or bool(plan_r.get("departs_on_new_wind", false)):
				calm_note.text += " 启航后的风和今天不一定相同，日数已按逐日累加。"
			calm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			calm_note.add_theme_font_size_override("font_size", 16)
			calm_note.add_theme_color_override("font_color", note_col)
			detail.add_child(calm_note)
			var safe_note := Label.new()
			safe_note.text = "八成：针路 %d 日 / 外洋 %d 日 / 傍岸 %d 日。十次里大约八次不迟于这个数。" % [
				int(plan_r.get("safe_days", 0)), int(plan_o.get("safe_days", 0)), int(plan_c.get("safe_days", 0)),
			]
			var rumb_thin := int(plan_r.get("expected_days", 0)) <= deadline and int(plan_r.get("safe_days", 0)) > deadline
			var off_thin := int(plan_o.get("expected_days", 0)) <= deadline and int(plan_o.get("safe_days", 0)) > deadline
			var coast_thin := int(plan_c.get("expected_days", 0)) <= deadline and int(plan_c.get("safe_days", 0)) > deadline
			if rumb_thin or off_thin or coast_thin:
				safe_note.text += " 有航法平均数赶得上，八成日数超过期限，不算稳。"
			safe_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			safe_note.add_theme_font_size_override("font_size", 16)
			safe_note.add_theme_color_override("font_color", note_col)
			detail.add_child(safe_note)
			var hold_note := Label.new()
			hold_note.text = "保货：针路 %d / 外洋 %d / 傍岸 %d。十次里至少有这么多次，逃走没被抢走货。" % [
				int(plan_r.get("hold_tenths", 0)), int(plan_o.get("hold_tenths", 0)), int(plan_c.get("hold_tenths", 0)),
			]
			var cargo_bits := ""
			if int(plan_r.get("safe_days", 0)) <= deadline and int(plan_r.get("hold_tenths", 0)) < 8:
				cargo_bits += "针路"
			if int(plan_o.get("safe_days", 0)) <= deadline and int(plan_o.get("hold_tenths", 0)) < 8:
				cargo_bits += ("、" if cargo_bits != "" else "") + "外洋"
			if int(plan_c.get("safe_days", 0)) <= deadline and int(plan_c.get("hold_tenths", 0)) < 8:
				cargo_bits += ("、" if cargo_bits != "" else "") + "傍岸"
			var risks := PackedStringArray()
			if cargo_bits != "":
				hold_note.text += " %s按八成日数赶得上，保货不到八成。小船打不赢，这数不含买路。" % cargo_bits
				hold_note.add_theme_color_override("font_color", warn_col)
				risks.append("保货")
			else:
				hold_note.add_theme_color_override("font_color", note_col)
			hold_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hold_note.add_theme_font_size_override("font_size", 16)
			detail.add_child(hold_note)
			var need_qty := int(offer.get("qty", 0))
			var unit_cost := Economy.buy_price(port_id, gid)
			var held_qty := Fleet.cargo_qty(gid)
			var can_buy := 0
			if unit_cost > 0:
				can_buy = int(float(GameState.money) / float(unit_cost))
			var can_carry := held_qty + mini(can_buy, Fleet.max_loadable(gid))
			if can_carry < need_qty:
				var purse_lbl := Label.new()
				purse_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				purse_lbl.text = "这里一件 %d 钱。钱和舱里现有的，凑得出 %d 件，单子要 %d 件。不够也能接，交不齐就拿不满酬，也没有名声。" % [
					unit_cost, can_carry, need_qty,
				]
				purse_lbl.add_theme_font_size_override("font_size", 16)
				purse_lbl.add_theme_color_override("font_color", warn_col)
				detail.add_child(purse_lbl)
				risks.append("凑不齐")
			var spoil_rate := Voyage.good_perish_rate(gid)
			if spoil_rate > 0.0 and can_carry > 0:
				var spoil_note := Label.new()
				var sr := Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(spoil_rate, can_carry, int(plan_r.get("safe_days", 0))))
				var so := Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(spoil_rate, can_carry, int(plan_o.get("safe_days", 0))))
				var sc := Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(spoil_rate, can_carry, int(plan_c.get("safe_days", 0))))
				spoil_note.text = "受潮：针路 %d / 外洋 %d / 傍岸 %d。按八成日数，十次里至少有这么多次一件没潮。这数不含海盗。" % [sr, so, sc]
				if can_carry < need_qty:
					spoil_note.text += " 按眼下凑得出的 %d 件算。" % can_carry
				var spoil_bits := ""
				if int(plan_r.get("safe_days", 0)) <= deadline and sr < 8:
					spoil_bits += "针路"
				if int(plan_o.get("safe_days", 0)) <= deadline and so < 8:
					spoil_bits += ("、" if spoil_bits != "" else "") + "外洋"
				if int(plan_c.get("safe_days", 0)) <= deadline and sc < 8:
					spoil_bits += ("、" if spoil_bits != "" else "") + "傍岸"
				if spoil_bits != "":
					spoil_note.text += " %s按八成日数赶得上，受潮不到八成。" % spoil_bits
					spoil_note.add_theme_color_override("font_color", warn_col)
					risks.append("受潮")
				else:
					spoil_note.add_theme_color_override("font_color", note_col)
				spoil_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				spoil_note.add_theme_font_size_override("font_size", 16)
				detail.add_child(spoil_note)
			if int(plan_c.get("expected_days", 0)) > deadline:
				var warn := Label.new()
				warn.text = "傍岸遇事约 %d 日，超过期限 %d 日。" % [int(plan_c.get("expected_days", 0)), deadline]
				warn.add_theme_font_size_override("font_size", 16)
				warn.add_theme_color_override("font_color", warn_col)
				detail.add_child(warn)
				risks.append("傍岸误期")
			elif coast > deadline:
				var warn_calm := Label.new()
				warn_calm.text = "傍岸静风就要 %d 日，赶不上。" % coast
				warn_calm.add_theme_font_size_override("font_size", 16)
				warn_calm.add_theme_color_override("font_color", warn_col)
				detail.add_child(warn_calm)
				risks.append("傍岸赶不上")
			# 细则收起时摘要行尾挂一句风险提要（藤黄），整段细则也挂在摘要 tooltip 上
			if not risks.is_empty():
				flag.text = "・".join(risks)
				flag.visible = true
			var tip := PackedStringArray()
			for c in detail.get_children():
				if c is Label:
					tip.append((c as Label).text)
			summary.tooltip_text = "\n".join(tip)
	choices_container.add_child(box)


func _on_accept_contract(offer: Dictionary) -> void:
	if GameState.accept_contract(offer):
		var cst := GameState.contract_status()
		log_msg("接下委办：%s ×%d，%d 日内送到%s。酬 %d 钱，误期要赔。" % [
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("qty", 0)),
			int(GameState.contract.get("deadline_days", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			int(GameState.contract.get("purse", 0)),
		])
	elif not GameState.contract_status().is_empty():
		log_msg("牙行摇头：你身上已经有一笔没了结的。")
	else:
		log_msg("牙行把单子收了回去。这月的委办对不上。")
	load_scene(current_scene_id)


func _on_deliver_contract(port_id: String) -> void:
	var res := GameState.deliver_contract(port_id)
	log_msg(str(res.get("msg", "")))
	load_scene(current_scene_id)


func _on_abandon_contract() -> void:
	var msg := GameState.abandon_contract()
	if msg != "":
		log_msg(msg)
	load_scene(current_scene_id)


func _make_market_row(port_id: String, good_id: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(200, 188)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.paper_card(card)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)

	var g := GameManager.get_good_by_id(good_id)
	var buy_p := Economy.buy_price(port_id, good_id)
	var sell_p := Economy.sell_price(port_id, good_id)
	var held := Fleet.cargo_qty(good_id, _market_ship)
	var role := Economy.get_role(port_id, good_id)

	var name_lbl := Label.new()
	name_lbl.text = str(g.get("name", good_id))
	name_lbl.add_theme_font_override("font", UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	name_lbl.add_theme_color_override("font_color", UiTheme.TIDE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if g.get("contraband", false):
		name_lbl.add_theme_color_override("font_color", UiTheme.CINNABAR)
		name_lbl.tooltip_text = "违禁　宋法不许出海，验引护不住"
	body.add_child(name_lbl)

	var hint_lbl := Label.new()
	var hint := Economy.price_hint(port_id, good_id)
	# 行情传闻（云端 bed9）：有传闻时行上写传闻，原提示进 tooltip
	var rumor := GameState.rumor_label(port_id, good_id)
	hint_lbl.text = hint if hint != "" else "寻常"
	if rumor != "":
		hint_lbl.text = rumor
		hint_lbl.tooltip_text = (hint + "\n" + rumor) if hint != "" else rumor
	UiTheme.style_footnote(hint_lbl)
	hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if role == "origin":
		hint_lbl.add_theme_color_override("font_color", UiTheme.MOSS)
	elif role == "consumer":
		hint_lbl.add_theme_color_override("font_color", UiTheme.HONEY)
	body.add_child(hint_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "买 %d　卖 %d" % [buy_p, sell_p]
	price_lbl.add_theme_font_override("font", UiTheme.font())
	price_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	price_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(price_lbl)

	var held_lbl := Label.new()
	held_lbl.text = "舱 %d" % held
	UiTheme.style_footnote(held_lbl)
	held_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(held_lbl)

	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 6)
	buy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(buy_row)
	for n in [1, 10]:
		var b := Button.new()
		b.text = "买 %d" % n
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 28)
		b.pressed.connect(_on_buy.bind(port_id, good_id, n, _market_ship))
		buy_row.add_child(b)
		UiTheme.style_chip(b)
	var bmax := Button.new()
	bmax.text = "买满"
	bmax.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bmax.custom_minimum_size = Vector2(0, 28)
	bmax.pressed.connect(_on_buy_max.bind(port_id, good_id, _market_ship))
	buy_row.add_child(bmax)
	UiTheme.style_chip(bmax, true)

	var sell_row := HBoxContainer.new()
	sell_row.add_theme_constant_override("separation", 6)
	sell_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sell_row)
	for n2 in [1, 10]:
		var s := Button.new()
		s.text = "卖 %d" % n2
		s.disabled = held < n2
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(0, 28)
		s.pressed.connect(_on_sell.bind(port_id, good_id, n2, _market_ship))
		sell_row.add_child(s)
		UiTheme.style_chip(s)
	var sall := Button.new()
	sall.text = "全卖"
	sall.disabled = held <= 0
	sall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sall.custom_minimum_size = Vector2(0, 28)
	sall.pressed.connect(_on_sell.bind(port_id, good_id, held, _market_ship))
	sell_row.add_child(sall)
	UiTheme.style_chip(sall)

	return card


func _on_buy(port_id: String, good_id: String, amount: int, ship_index: int) -> void:
	if good_id not in broker_hand:
		log_msg("这件今日不在柜上。")
		return
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
		note = "只购得 %d。" % actual
	log_msg("买入 %s ×%d，付 %d 钱。%s" % [GameManager.get_good_name(good_id), actual, cost, note])
	_market_hold = true
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
	if good_id not in broker_hand:
		log_msg("这件今日不在柜上。")
		return
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
	log_msg("卖出 %s ×%d，得 %d 钱，%s。" % [GameManager.get_good_name(good_id), actual, revenue, profit_str])
	_market_hold = true
	load_scene(current_scene_id)


# ── 市舶司 ──────────────────────────────────────────

func _setup_yamen(port_id: String) -> void:
	scene_title.text = "%s・市舶司" % GameManager.get_port_name(port_id)
	body_text.text = "案上压着未批的货单。验引、呈报、修埠都在这里。"
	_begin_benches()

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
	_slip_note(permit, "蒲家留意 %d　%s" % [GameState.pu_attention, _attention_desc()])

	_setup_reporting()
	# 本地 main：泉州对峙期（1276-77）征船名册三选一，非对峙期内部自行返回
	_setup_quanzhou_standoff(port_id)
	_setup_title_and_invest(port_id)

	_end_benches()
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
		_slip_title(slip, str(d.get("name", did)), "赏格 %d　名声加 %d" % [value, maxi(1, value / 10)])
		var chip := _slip_chip(_slip_row(slip), "呈报", _on_report_discovery.bind(str(did)), true)
		chip.tooltip_text = "%s\n%s" % [d.get("location", ""), d.get("historical_hook", "")]


func _on_report_discovery(did: String) -> void:
	var res: Dictionary = GameState.report_discovery(did)
	if not res.is_empty():
		var extra := ""
		if res.get("promoted", false):
			extra = "市舶司案册改题「%s」。" % str(res.get("title", {}).get("name", ""))
		log_msg("【呈报】%s 录入案册，赏钱 %d，名声加 %d。%s" % [
			res["name"], res["gold"], res["fame"], extra,
		])
	load_scene(current_scene_id)


func _setup_title_and_invest(port_id: String) -> void:
	var rank: Dictionary = GameState.title_rank()
	var nxt: Dictionary = GameState.next_title()
	var rank_slip := _slip_body()
	_slip_title(rank_slip, "职衔", str(rank.get("name", "")))
	var duty_line := "抽解每百 %d　赊贷上限 %d" % [
		_duty_per_hundred(float(rank.get("duty_factor", 1.0))),
		GameState.DEBT_CEILING + GameState.title_loan_bonus(),
	]
	if nxt.is_empty():
		_slip_note(rank_slip, duty_line + "。")
	else:
		var need: int = maxi(0, int(nxt.get("min_fame", 0)) - GameState.fame)
		_slip_note(rank_slip, "再记 %d 声名可题「%s」。%s。" % [
			need, str(nxt.get("name", "")), duty_line,
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
		_slip_note(inv, "向本港投钱修埠，再升一等。产地买入更廉、紧缺货更好卖、市场更深。")
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
		return "暗桩已盯死，出港必查"
	elif a >= 50:
		return "起了疑心"
	elif a >= 25:
		return "偶有闲话传出"
	return "尚无人留意"


# ── 工席 ────────────────────────────────────────────
## 设施页里一桩事一张潮玻璃。和岸门同一块材料，横排放，放不下就换行。

func _begin_benches(host: Node = null) -> void:
	var flow := HFlowContainer.new()
	flow.name = "Benches"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 8)
	var parent: Node = host if host != null else choices_container
	parent.add_child(flow)
	_slip_host = flow


func _end_benches() -> void:
	_slip_host = null


## 工席宽 480，扣掉潮光边和内边距后字宽 448。
## Label 打开 autowrap 后最小高度仍按一行算，长旁注会被裁成半句。
func _lock_slip_wrap(lbl: Label) -> void:
	if not (_slip_host is HFlowContainer):
		return
	var width := 448.0
	var font := lbl.get_theme_font("font")
	if font == null:
		font = UiTheme.font()
	var fsize := lbl.get_theme_font_size("font_size")
	if fsize <= 0:
		fsize = UiTheme.SIZE_FOOT
	var measured := font.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, width, fsize)
	var h := measured.y
	if h < float(fsize):
		h = float(fsize)
	lbl.custom_minimum_size = Vector2(width, ceil(h))


func _slip_body() -> VBoxContainer:
	var card := PanelContainer.new()
	UiTheme.paper_card(card)
	var in_flow := _slip_host is HFlowContainer
	if in_flow:
		card.custom_minimum_size = Vector2(480, 0)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	margin.add_child(body)
	var parent: Node = _slip_host if _slip_host != null else choices_container
	parent.add_child(card)
	return body


func _slip_title(body: VBoxContainer, title: String, aside := "") -> Label:
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_override("font", UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_lbl.add_theme_color_override("font_color", UiTheme.TIDE)
	_lock_slip_wrap(name_lbl)
	body.add_child(name_lbl)
	var hint := Label.new()
	hint.text = aside
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_footnote(hint)
	if aside != "":
		_lock_slip_wrap(hint)
		body.add_child(hint)
	return hint


func _slip_note(body: VBoxContainer, text: String, color: Color = UiTheme.TEXT_DIM) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", color)
	_lock_slip_wrap(lbl)
	body.add_child(lbl)
	return lbl


func _slip_row(body: VBoxContainer) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	return row


func _slip_chip(row: Node, text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	row.add_child(b)
	UiTheme.style_chip(b, accent)
	return b


## 工席上只有这一个动作时，整张卡都可点（照 _make_shore_door：卡底下铺一层扁平钮，悬停时纸被照亮）。
## 卡里的容器让开鼠标；小钮本身仍在最上面，点它照旧。第 1 轮评审 UX M6：玩家会去点卡，卡原先没有反应。
func _slip_whole(btn: Button) -> void:
	var card: Node = btn.get_parent()
	while card != null and not (card is PanelContainer):
		card = card.get_parent()
	if card == null or card.get_node_or_null("WholeHit") != null:
		return
	var panel := card as PanelContainer
	for c in panel.find_children("*", "Container", true, false):
		if (c as Control).tooltip_text == "":
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.name = "WholeHit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(s, empty)
	hit.tooltip_text = btn.tooltip_text
	hit.pressed.connect(func() -> void:
		if is_instance_valid(btn) and not btn.disabled:
			btn.pressed.emit())
	hit.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			panel.add_theme_stylebox_override("panel", UiTheme.shore_door_hover()))
	hit.mouse_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", UiTheme.shore_door()))
	panel.add_child(hit)
	panel.move_child(hit, 0)


# ── 船屋 ────────────────────────────────────────────

func _setup_shipyard(port_id: String) -> void:
	scene_title.text = "%s・船屋" % GameManager.get_port_name(port_id)
	body_text.text = "坞上只搁一艘。帆和甲对着这一艘。水粮和赊贷仍在码头上。"
	var on := DrydockBerth.berth_index(Fleet.ships.size(), GameState.berth_index)
	if GameState.berth_index != on:
		GameState.berth_index = on
	_begin_benches()

	# 坞位：一张工席，帆、甲、添人只对着坞上这一艘（云端 5588 坞位一艘，嵌进 c8fb/7f92 的工席壳）
	if Fleet.ships.is_empty():
		var empty := _slip_body()
		_slip_title(empty, "坞位", "眼下没有船")
	else:
		var hull: Dictionary = Fleet.ships[on]
		var sname := str(hull.get("name", "船"))
		var slv := Fleet.sail_level(on)
		var alv := Fleet.armor_level(on)
		var berth := _slip_body()
		_slip_title(berth, "坞位　%s" % sname, "帆　%s　甲　%s" % [_fit_rank(slv), _fit_rank(alv)])
		_slip_note(berth, "水手 %d / %d　耐久 %d / %d　载 %d 料" % [
			Fleet.ship_crew(on),
			Fleet.ship_crew_max(on),
			int(hull.get("durability", 0)),
			int(hull.get("max_durability", 0)),
			int(Fleet.ship_capacity(on)),
		], UiTheme.TEXT)
		var fit_row := _slip_row(berth)
		if Fleet.is_sail_max(on):
			_slip_note(berth, "帆已是三等。")
		else:
			var scost: int = Fleet.upgrade_cost(on, "sail")
			var sail_chip := _slip_chip(fit_row, "升帆　%d" % scost, _on_upgrade.bind(on, "sail", scost))
			var sail_phrase := _sail_fit_phrase(slv)
			sail_chip.tooltip_text = sail_phrase
			_slip_note(berth, sail_phrase)
		if Fleet.is_armor_max(on):
			_slip_note(berth, "甲已是三等。")
		else:
			var acost: int = Fleet.upgrade_cost(on, "armor")
			var armor_chip := _slip_chip(fit_row, "升甲　%d" % acost, _on_upgrade.bind(on, "armor", acost))
			var armor_phrase := _armor_fit_phrase(alv)
			armor_chip.tooltip_text = armor_phrase
			_slip_note(berth, armor_phrase)
		var room: int = Fleet.ship_crew_room(on)
		if room > 0:
			var hire_n: int = mini(10, room)
			var hire_cost := hire_n * 20
			var hire_chip := _slip_chip(
				fit_row,
				"%s　添 %d 人　%d" % [sname, hire_n, hire_cost],
				_on_hire_crew.bind(on, hire_n, hire_cost)
			)
			hire_chip.tooltip_text = "尚可添 %d　现有 %d" % [room, Fleet.ship_crew(on)]
		var fleet_full := true
		for j in Fleet.ships.size():
			if Fleet.ship_crew_room(j) > 0:
				fleet_full = false
				break
		if fleet_full:
			_slip_note(berth, "各船人手已满。")

		var others := DrydockBerth.other_hulls(Fleet.ships.size(), on)
		if others.size() > 0:
			var swap_row := _slip_row(berth)
			for idx in others:
				var other: Dictionary = Fleet.ships[idx]
				_slip_chip(swap_row, "换上　%s" % str(other.get("name", "船")), _on_berth_switch.bind(int(idx)))

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
			"水粮各 %d　付 %d" % [packs, packs * (water_price + grain_price)],
			_on_buy_supplies.bind(packs, water_price, grain_price)
		)
	var rc := Fleet.repair_cost()
	if rc > 0:
		_slip_chip(supply_row, "修船　%d" % rc, _on_repair_hull.bind(rc))
	var below_min: int = Fleet.crew_to_min_needed()
	if below_min > 0:
		var top_cost := below_min * 20
		_slip_chip(
			supply_row,
			"补齐 %d 人　%d" % [below_min, top_cost],
			_on_hire_to_min.bind(top_cost)
		)

	var loan := _slip_body()
	_slip_title(loan, "蕃商赊贷", "月息每百 %d　上限 %d" % [
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
	# 坞外待售：本章够到的船全部排在坞外，一艘一个购入小钮
	var reached := PackedStringArray()
	for mark in ["ch1", "ch2", "ch3", "ch4"]:
		if GameState.is_chapter_reached(mark):
			reached.append(mark)
	var catalog: Array = GameManager.ships_data.get("ships", [])
	var for_sale := DrydockBerth.sale_ids(catalog, reached)
	if for_sale.size() > 0:
		var sale := _slip_body()
		_slip_title(sale, "坞外待售", "新买的船泊在外侧，不自动占坞位")
		var sale_row := _slip_row(sale)
		for sid in for_sale:
			var offer := _yard_offer(catalog, sid)
			if offer.is_empty():
				continue
			var price: int = int(offer.get("price", 0))
			var tid := str(offer.get("id", ""))
			var buy := _slip_chip(sale_row, "%s　购入　%d" % [str(offer.get("name", "船")), price], _on_buy_ship.bind(tid, price), true)
			buy.tooltip_text = "载 %d 料　水手 %d 至 %d　耐久 %d" % [
				int(offer.get("capacity", 0)), int(offer.get("crew_min", 0)),
				int(offer.get("crew_max", 0)), int(offer.get("durability", 0)),
			]
			var hist := str(offer.get("historical_note", ""))
			if hist != "":
				buy.tooltip_text += "\n" + hist

	_end_benches()
	_add_leave_button(port_id)
	choices_label.visible = false


func _yard_offer(catalog: Array, sid: String) -> Dictionary:
	for raw_ship in catalog:
		if typeof(raw_ship) != TYPE_DICTIONARY:
			continue
		var ship_row: Dictionary = raw_ship
		if str(ship_row.get("id", "")) == sid:
			return ship_row
	return {}


func _on_berth_switch(ship_index: int) -> void:
	var on := DrydockBerth.berth_index(Fleet.ships.size(), ship_index)
	if on == GameState.berth_index:
		return
	GameState.berth_index = on
	var hull: Dictionary = Fleet.ships[on]
	log_msg("把「%s」拖上坞位。帆和甲对着这一艘。" % str(hull.get("name", "船")))
	load_scene(current_scene_id)


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
		log_msg("蕃商掂了掂你的船和名声，点了头。赊得 %d 钱，月息每百 %d。" % [
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
		log_msg("「%s」加厚了船壳，甲升至%s。" % [s.get("name", "船"), _fit_rank(Fleet.armor_level(ship_index))])
	else:
		Fleet.upgrade_sail(ship_index)
		var s2: Dictionary = Fleet.ships[ship_index]
		log_msg("「%s」换了新帆，帆升至%s。" % [s2.get("name", "船"), _fit_rank(Fleet.sail_level(ship_index))])
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


# ── 玉湖陈宅（兴化住宅）────────────────────────────

const CHEN_ZAN_STAKE := 3000
const CHEN_ZAN_FROM_YEAR := 1270
const CHEN_ZAN_MIN_FAME := 15

## 本地 main 的兴化玉湖陈宅（1268 殿试前的乡土写入点、陈瓒船股）；云端 7f92 的通用「住处」在下面。
## 合并时按云端为准保留通用住处，兴化一港改走陈宅（陈文龙的家在兴化玉湖）。
func _setup_residence_chen(port_id: String) -> void:
	scene_title.text = "%s・玉湖陈宅" % GameManager.get_port_name(port_id)
	var mother := "母亲黄氏在隔壁厢房摇着织机，一声声像是催你动笔。" if Calendar.year < 1270 else "母亲黄氏的织机停了，她的手已经摇不动。她坐在织机旁边看你。"
	body_text.text = "祠堂的灯还是二十年前那盏。%s\n案上压着一叠策论草稿，纸边微硬。" % mother

	# 1268 殿试前：替族里跑事。这是「乡土」这条身份唯一的早期写入点。
	if GameState.identity == "undecided":
		var errand := Button.new()
		errand.text = "替族里跑一趟事（费 6 日・30 钱，乡土 +3）"
		errand.disabled = GameState.money < 30
		errand.pressed.connect(func():
			if not GameState.spend_money(30):
				return
			GameState.hometown_tendency += 3
			GameManager.advance_days(6)
			log_msg("修祠堂的木料、外姓那桩田讼、三房的婚事——都不是你的事，可族里只找得到你。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(errand)

	if GameState.has_flag("chen_zan_stake"):
		var l := Label.new()
		l.text = "族叔陈瓒的船股一分，记在账上。他说过：「几时回，走哪条水，要先说。」"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
		choices_container.add_child(l)
	elif Calendar.year >= CHEN_ZAN_FROM_YEAR:
		var b := Button.new()
		if GameState.fame >= CHEN_ZAN_MIN_FAME:
			b.text = "族叔陈瓒愿入船股一分（得 %d 钱，乡土 +5）" % CHEN_ZAN_STAKE
			b.pressed.connect(func():
				GameState.add_money(CHEN_ZAN_STAKE)
				GameState.hometown_tendency += 5
				GameState.set_flag("chen_zan_stake")
				GameState.add_ledger_note("陈瓒船股一分")
				log_msg("陈瓒把三千钱推过案来，没数。「要多少、走哪条水、几时回——这三句先说清，钱就是你的。」")
				load_scene(current_scene_id)
			)
		else:
			b.text = "族叔陈瓒——「名声不到 %d，钱不能给你」" % CHEN_ZAN_MIN_FAME
			b.disabled = true
		choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button(port_id)


# ── 酒馆 ────────────────────────────────────────────

func _setup_tavern(port_id: String) -> void:
	scene_title.text = "%s・酒馆" % GameManager.get_port_name(port_id)
	body_text.text = "劣酒和喧哗。消息与人手都从这儿来。月俸按月，欠饷三月则去。"

	# 旧事放最前，仍走挑签。打听和募人进工席。
	_setup_story_hooks(port_id)
	_begin_benches()

	if port_id.begins_with("quanzhou"):
		_add_npc_button("merchant_lin", "林阿舶")
	elif port_id.begins_with("ryukyu"):
		_add_npc_button("pilot_ana", "阿那")

	var intel := _slip_body()
	_slip_title(intel, "行情", "费一日")
	# 「打听」费一日（advance_days：耗水粮、推逐日结算）：花时间的动作和花钱的一样不做整卡可点，免得点卡误过一天（第 2 轮工程 m5）
	_slip_chip(_slip_row(intel), "打听", _on_gather_intel.bind(port_id))

	_setup_hiring(port_id)
	_end_benches()

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
## characters 线：候选人与在船人员都排成横向人物卡（小立绘 + 名 + 职事品级 + 五维迷你条 + 钱数 + 钮）；
## 卡上文案与数值照旧（「火长　初习」「入伙 120　月俸 60」「雇入」「辞退」），钮的回调不变。
func _setup_hiring(port_id: String) -> void:
	# 在船的人
	if not Crew.hired.is_empty():
		for c in Crew.roster():
			var rname: String = Crew.role_def(c.get("role", "")).get("name", "")
			var aboard := _person_slip(GameManager.character_for_crew(str(c.get("id", ""))), str(c.get("name", "")),
				"%s　%s　月俸 %d" % [rname, _skill_rank(int(c.get("level", 1))), int(c.get("wage", 0))],
				int(c.get("level", 1)))
			var aboard_hint := aboard.get_node("Head/Aside") as Label
			aboard_hint.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.MOSS))
			var rid: String = str(c.get("role", ""))
			var foot := _person_foot(aboard, "在船")
			_slip_chip(foot, "辞退", _on_dismiss_crew.bind(rid))

	var cands := Crew.candidates_at(port_id)
	if cands.is_empty():
		var none := _slip_body()
		_slip_title(none, "募人", "此处无人可用")
		return

	for c in cands:
		var cid: String = str(c.get("id", ""))
		var role: Dictionary = Crew.role_def(c.get("role", ""))
		var cch: Dictionary = GameManager.character_for_crew(cid)
		var card := _person_slip(cch, str(c.get("name", "")), "%s　%s" % [
			role.get("name", ""), _skill_rank(int(c.get("level", 1))),
		], int(c.get("level", 1)))
		# 职事真正管用的是这一句（航程、价差、减员……），写在品级下面；五维只作展示，压淡（第 1 轮评审 UX M5）
		var eff := str(role.get("effect_hint", ""))
		if eff != "":
			var eff_lbl := Label.new()
			eff_lbl.name = "EffectHint"
			eff_lbl.text = eff
			eff_lbl.add_theme_font_override("font", UiTheme.font())
			eff_lbl.add_theme_font_size_override("font_size", 16)
			eff_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT))
			eff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(eff_lbl)
			card.move_child(eff_lbl, 1)
		# 只压淡细条，字不压：整条 modulate 0.55 时纸上 16px 字实渲染只剩 2.2–3.2:1（返工自查，cap3 rend 实测）
		var strip := card.get_node_or_null("AttrStrip") as Control
		if strip != null:
			for col in strip.get_children():
				for part in col.get_children():
					if not (part is HBoxContainer):
						(part as CanvasItem).modulate = Color(1, 1, 1, 0.55)
		# 在酒馆里见过画像与五维的候选，人物志里记作已识（本会话，不入存档）
		_CHAR_ART.note_met(str(cch.get("id", "")))
		var foot := _person_foot(card, "入伙 %d　月俸 %d" % [Crew.signing_fee(cid), int(c.get("wage", 0))])
		var hire := _slip_chip(foot, "雇入", _on_hire_candidate.bind(cid), true)
		_seal_chip(hire)
		hire.tooltip_text = "%s\n\n%s\n%s" % [
			c.get("bio", ""), role.get("desc", ""), role.get("effect_hint", ""),
		]


## 人物卡的右栏：名（绢本马善政）+ 品级点 / 旁注 / 五维迷你条。返回右栏，调用方再往下接 _person_foot。
## ch 为空（设定集里查无此人）时画框里是一方墨，五维条不出，文案照旧。
func _person_slip(ch: Dictionary, title: String, aside: String, level := 0) -> VBoxContainer:
	var body := _slip_body()
	var row := HBoxContainer.new()
	row.name = "PersonRow"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(row)
	var tex: Texture2D = _CHAR_ART.thumb(ch, HIRE_PIC) if not ch.is_empty() else null
	row.add_child(_CHAR_ART.framed(tex, Vector2(HIRE_PIC), true))
	var info := VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 与其它工席抬头同一写法：绢本宣纸上是马善政靛青（大四号），夜潮是石青正文字。这里直接写定，不等卡片换色
	name_lbl.add_theme_font_override("font", UiTheme.title_font() if UiTheme.IS_JUANBEN else UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY + (4 if UiTheme.IS_JUANBEN else 0))
	name_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TIDE))
	name_lbl.set_meta(&"nk1_title", true)
	name_row.add_child(name_lbl)
	if level > 0:
		name_row.add_child(_CHAR_ART.pips(level, true))
	var hint := Label.new()
	hint.name = "Aside"
	hint.text = aside
	UiTheme.style_footnote(hint)
	hint.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
	head.add_child(hint)
	if not ch.is_empty():
		var strip := _CHAR_ART.attr_strip(ch, 56.0, true)
		info.add_child(strip)
	return info


## 人物卡底行：左边一句钱数 / 在船，右边钮。返回放钮的那一格。
func _person_foot(info: VBoxContainer, note: String) -> HBoxContainer:
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(foot)
	var lbl := Label.new()
	lbl.text = note
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(lbl)
	return foot


## 募人钮放大成一方朱印：马善政、四周留足，一眼看得见（仍是 style_chip 的朱砂四态与印面字）。
func _seal_chip(btn: Button) -> void:
	if not UiTheme.IS_JUANBEN:
		return
	btn.add_theme_font_override("font", UiTheme.title_font())
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(78, 34)


## 职事品级。数据里只有 1–3，不再用星号。
func _skill_rank(n: int) -> String:
	return Crew.rank_word(n)


## 旅店：候风。季风按月转向，等到对的月份再发舶是这个游戏最要紧的判断之一。
func _setup_inn(port_id: String) -> void:
	scene_title.text = "%s・旅店" % GameManager.get_port_name(port_id)
	body_text.text = "通铺草席还潮着。风信不对时，海商在这儿候着。"
	_begin_benches()

	var rest := _slip_body()
	_slip_title(rest, "歇息", "%s　%s" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()])
	_slip_note(rest, _monsoon_forecast(), UiTheme.HONEY)
	# 在身委办的期限提醒（云端 bed9），嵌进主干的歇息工席
	var rest_cst := GameState.contract_status()
	if not rest_cst.is_empty():
		var rest_left := int(rest_cst.get("days_left", 0))
		if rest_left < 0:
			_slip_note(rest, "在身委办已经逾期，歇着也会被牙行扣钱。", UiTheme.CINNABAR)
		else:
			_slip_note(rest, "在身委办还剩 %d 日。歇过这个数，牙行要扣钱、掉名声。" % rest_left, UiTheme.CINNABAR)
	var rest_row := _slip_row(rest)
	for n in [1, 10]:
		var nights := int(n)
		_slip_chip(rest_row, "歇 %d 日　%d%s" % [nights, nights * INN_RATE, _contract_rest_mark(nights)], _on_rest.bind(nights, port_id))
	var to_next: int = Calendar.DAYS_PER_MONTH - Calendar.day + 1
	_slip_chip(
		rest_row,
		"候 %d 日　%d%s" % [to_next, to_next * INN_RATE, _contract_rest_mark(to_next)],
		_on_rest.bind(to_next, port_id),
		true
	)

	_end_benches()
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
	_begin_benches()

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
				"运往 %s　多 %d" % [GameManager.get_port_name(row["port"]), int(row["profit"])]
			)
			hint.add_theme_color_override("font_color", UiTheme.MOSS)
			_slip_note(slip, "买 %d　卖 %d" % [int(row["buy"]), int(row["sell"])])

	_end_benches()
	_add_leave_button(port_id)
	choices_label.visible = false


## 贡院：今科未开，只能替人誊录。耗日换工钱与学者倾向，不给名声、不另开章门。
func _setup_exam(port_id: String) -> void:
	scene_title.text = "%s・贡院" % GameManager.get_port_name(port_id)
	body_text.text = "今科未开。只能替人誊录，笔墨钱现结。"
	_begin_benches()

	var copy := _slip_body()
	_slip_title(copy, "誊录", "学者 %d　海路 %d" % [GameState.scholar_tendency, GameState.sea_tendency])
	_slip_note(copy, "工钱 %d　费 %d 日。不记名声。" % [EXAM_STIPEND, EXAM_COPY_DAYS])
	_slip_chip(_slip_row(copy), "替人抄三日", _on_exam_copy.bind(port_id), true)

	_end_benches()
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
	if port_id == "xinghua":
		_setup_residence_chen(port_id)
		return
	scene_title.text = "%s・住处" % GameManager.get_port_name(port_id)
	body_text.text = "租来的下处。比旅店便宜，听不见风信。"
	_begin_benches()

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

	_end_benches()
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
	_begin_benches()

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

	_end_benches()
	_add_leave_button(port_id)
	choices_label.visible = false


func _temple_rub_note(name: String, hook: String) -> String:
	var body := hook.strip_edges()
	if body == "":
		return "拓「%s」。" % name
	return "拓「%s」　%s" % [name, body]


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
	return "掌柜掐指算了算。约 %d 日后风信要转。北上博多、高丽须候西南风　五至八月。南下流求、南洋须候东北风　十月至次年二月。" % days


func _contract_rest_mark(days: int) -> String:
	var cst := GameState.contract_status()
	if cst.is_empty():
		return ""
	if days > int(cst.get("days_left", 0)):
		return "·误期"
	return ""


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
	GameState.note_rumor(str(best["port"]), str(best["good"]), Economy.get_rate(str(best["port"]), str(best["good"])))
	return "【行情】邻座的牙人压低声音：「%s　眼下缺%s，此地买了运过去，一件能多得　%d 钱。」" % [
		GameManager.get_port_name(best["port"]),
		GameManager.get_good_name(best["good"]),
		int(best["profit"]),
	]


# ══════════════════════════════════════════════════════
#  NPC
# ══════════════════════════════════════════════════════

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	# characters 线：设定集里有此人就排成人物卡（小立绘 + 五维迷你条，底行写身份），文案「在侧」「见」照旧
	var ch: Dictionary = GameManager.character_for_npc(npc_id)
	if not ch.is_empty():
		var info := _person_slip(ch, fallback_name, "在侧")
		var foot := _person_foot(info, _CHAR_ART.codex_title(ch))
		_slip_whole(_slip_chip(foot, "见", _on_meet_npc.bind(npc_id, fallback_name)))
		return
	var slip := _slip_body()
	_slip_title(slip, fallback_name, "在侧")
	_slip_whole(_slip_chip(_slip_row(slip), "见", _on_meet_npc.bind(npc_id, fallback_name)))


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
	# 立绘以 characters.json 的 portrait 为准（缩到框里的尺寸、带 mipmap）；查无此人或缺图时回落旧的 sprite_ 图
	var ch: Dictionary = GameManager.character_for_npc(npc_id)
	var tex: Texture2D = _CHAR_ART.thumb(ch, Vector2i(256, 320)) if not ch.is_empty() else null
	if tex == null:
		var tex_path := "res://assets/sprite_" + npc_id.replace("pilot_", "").replace("merchant_", "") + ".png"
		tex = GameManager.load_texture(tex_path)
	npc_portrait.texture = tex
	npc_portrait.get_parent().visible = npc_portrait.texture != null
	var plate_name := npc_portrait.get_parent().get_node_or_null("NamePlate/Name") as Label
	if plate_name != null:
		plate_name.text = n_name
		plate_name.add_theme_font_override("font", _CHAR_ART.title_font_for(n_name))
	_fill_npc_profile(ch)
	_CHAR_ART.note_met(str(ch.get("id", "")))

	for child in npc_actions.get_children():
		child.queue_free()

	npc_dialog_lbl.text = spoken
	_npc_speech = npc_dialog_lbl
	# 纸笺左齐，与正文、五维栏同一条左轴（原先居中，见面页两套对齐轴；第 2 轮美术 minor 11）
	_begin_benches(npc_actions)
	if _slip_host is HFlowContainer:
		(_slip_host as HFlowContainer).alignment = FlowContainer.ALIGNMENT_BEGIN
	var intel := _slip_body()
	_slip_title(intel, "行情", "邻座牙人")
	_slip_whole(_slip_chip(_slip_row(intel), "打听", _on_npc_intel.bind(n_name)))
	if npc_id == "customs_official":
		var bribe := _slip_body()
		_slip_title(bribe, "疏通", "关注　减 15")
		# 花钱的动作不做整卡可点，免得点卡误塞了钱
		_slip_chip(_slip_row(bribe), "塞　50", _on_npc_bribe.bind(n_name), true)
	_end_benches()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc_actions.add_child(spacer)
	var leave_btn := Button.new()
	leave_btn.text = "离开"
	leave_btn.custom_minimum_size = Vector2(160, 42)
	leave_btn.pressed.connect(_on_npc_leave)
	npc_actions.add_child(leave_btn)
	UiTheme.style_leave_button(leave_btn)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


const NPC_GREETING := {
	"customs_official": "小吏把册子掀开一条缝，眼皮都没抬。「验引、呈报、修埠，都在这案上。有话就说。」",
	"merchant_lin": "林阿舶用指甲敲了敲账簿。「舱位、脚钱、货损，一样一样算。你叔父那笔，我还记着。」",
	"pilot_ana": "阿那望了一眼外海的水色。「潮声不对就别嘴硬。要问航路，就问。」",
}


func _set_npc_speech(text: String) -> void:
	if _npc_speech != null:
		_npc_speech.text = text


func _on_npc_intel(n_name: String) -> void:
	var heard := UiTheme.plain_log(_gather_price_intel(GameState.last_port))
	_set_npc_speech("%s压低声音说。\n\n%s" % [n_name, heard])


func _on_npc_bribe(n_name: String) -> void:
	if GameState.spend_money(50):
		GameState.pu_attention = maxi(0, GameState.pu_attention - 15)
		update_status_panel()
		_set_npc_speech("%s颠了颠手里的碎银：「算你懂事。近来风声紧，自己当心。」" % n_name)
	else:
		_set_npc_speech("%s满脸鄙夷：「就这点钱也想打通关节？」" % n_name)


func _on_npc_leave() -> void:
	npc_mode.visible = false
	investigation_mode.visible = true


# ══════════════════════════════════════════════════════
#  标题 / 港口 / 调查
# ══════════════════════════════════════════════════════

func _setup_title_mode(scene_data: Dictionary) -> void:
	_show_strip(false)
	_close_ledger()
	investigation_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	title_mode.visible = true

	main_title.text = scene_data.get("cg_title", "东亚海域立志传")
	# 长标题与分段副标题按宽换行居中（云端 c148/00b4）；盒宽与字号由 Main.tscn / 绢本主题定，不在此覆盖。
	main_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.sync_title_logo(main_title)
	sub_title.text = _unescape_scene_text(str(scene_data.get("cg_sub", "")))
	sub_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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

	# 起始标题页：占位的「…………」换成「开卷」（路由照旧取 choices[0].next），另给「重看开场」；
	# 卷首四方沙盘的「…………」只改显示为「翻页」（数据与路由不动）。标题演出（书法写出、引首章、分段逐行洇出）见 TitleStage。
	var is_start := current_scene_id == str(GameManager.scenes_data.get("start_scene", "cg_title"))
	if start_button.text.replace("…", "").strip_edges() == "":
		start_button.text = "开卷" if is_start else "翻页"
	_rewatch_button.visible = is_start and _CS_PLAYER.has_cutscene(_CINE.OPENING, _CINE.DATA)
	_codex_title_button.visible = is_start and not GameManager.all_characters().is_empty()
	var has_save := false
	for slot in range(1, SaveLoad.SLOTS + 1):
		has_save = has_save or SaveLoad.has_save(slot)
	_resume_button.visible = is_start and has_save
	_rewatch_button.get_parent().visible = _rewatch_button.visible or _codex_title_button.visible or _resume_button.visible
	_TITLE_STAGE.present(title_mode, main_title, sub_title, [start_button, _resume_button, _rewatch_button, _codex_title_button], is_start)


func _on_start_game_pressed(next_scene: String) -> void:
	load_scene(next_scene)


func _setup_port_mode(scene_data: Dictionary) -> void:
	_show_strip(true)
	_close_ledger()
	title_mode.visible = false
	investigation_mode.visible = false
	npc_mode.visible = false
	port_mode.visible = true
	_show_port_layer(true, 0.0)
	# 港名先写上，再分终局 / 守城：原先两条分支在赋值前就 return，匾上留着上一港的名字，
	# 终局匾再拿旧字拼「・结局名」，进出一次设施就累加一截（第 2 轮 UX B1）
	port_title.text = str(scene_data.get("title", "未知港口"))
	_port_scene_facilities = scene_data.get("facilities", []).duplicate()
	_build_shore()
	update_status_panel()


## 按页型重排岸带：终局后港口页 / 兴化守城页 / 寻常港页三选一。进港与「再候一日」都走这里，
## 每次先 _clear_shore() 把岸带与旧左右栏清空，旧节点不会残留，也不会翻倍。只是 UI 状态，不入存档。
func _build_shore() -> void:
	_clear_shore()
	# 本地 main 的终局线入口：终局后港口页 / 兴化守城页（函数在文件末尾补回段）
	if GameState.is_ended():
		_setup_ended_port()
		return
	if _siege_active():
		_setup_siege_port()
		return
	_shore_mode = "port"
	_fit_port_title()
	var shore_list: Array = _port_scene_facilities.duplicate()
	shore_list.append_array(_special_cards())
	_shore_facilities = shore_list
	_refresh_shore()


## 清岸带：岸门带、旧左右栏（云端港页已不用，守城 / 终局旧代码往里塞过卡）一律清空并按页型设可见。
func _clear_shore() -> void:
	for col in [left_facilities, right_facilities]:
		var stale_col: Array = (col as Node).get_children()
		for child in stale_col:
			(col as Node).remove_child(child)
			child.queue_free()
		(col as Control).visible = false
	var band := port_mode.get_node_or_null("ShoreBand")
	if band != null:
		var stale: Array = band.get_children()
		for child in stale:
			band.remove_child(child)
			child.queue_free()
	shore_hand = PackedStringArray()


## 港名匾字号：长题（终局「泉州・泉州蒲氏的船」、守城「兴化军・围城」）按字数收小，不冲出墨刷
func _fit_port_title() -> void:
	var n := port_title.text.length()
	var px := UiTheme.SIZE_PORT
	if UiTheme.IS_JUANBEN and n > 5:
		px = clampi(int(round(float(UiTheme.SIZE_PORT) * 5.0 / float(n))), 34, UiTheme.SIZE_PORT)
	port_title.add_theme_font_size_override("font_size", px)


func _shore_pin_shipyard() -> bool:
	return (not Fleet.can_sail()) or Fleet.supply_days() < 2


func _refresh_shore() -> void:
	for col in [left_facilities, right_facilities]:
		var stale_col: Array = (col as Node).get_children()
		for child in stale_col:
			(col as Node).remove_child(child)
			child.queue_free()
		(col as Control).visible = false
	# 「今日只开三处」只在寻常设施里发牌；本地 main 的终局特殊卡（special_* / siege_*）是历史节点，来了就一定在岸上
	var regular: Array = []
	var specials: PackedStringArray = PackedStringArray()
	for raw_fac in _shore_facilities:
		if typeof(raw_fac) != TYPE_DICTIONARY:
			continue
		var fid_raw := str(raw_fac.get("id", ""))
		if fid_raw.begins_with("special_") or fid_raw.begins_with("siege_"):
			if fid_raw not in specials:
				specials.append(fid_raw)
		else:
			regular.append(raw_fac)
	shore_hand = ShoreDraft.deal(regular, GameState.shore_salt, _shore_pin_shipyard())
	for fid_sp in specials:
		if fid_sp not in shore_hand:
			shore_hand.append(fid_sp)
	var band := _shore_band()
	# 发信号的钮还在这排里。先摘下来再排新门，否则新节点会被改名。
	var stale: Array = band.get_children()
	for child in stale:
		band.remove_child(child)
		child.queue_free()

	if _shore_mode == "siege":
		band.add_child(_siege_stat_slip())
	elif _shore_mode == "ended":
		band.add_child(_epilogue_slip())
	else:
		var hint := Label.new()
		hint.text = "今日只开三处。"
		UiTheme.style_footnote(hint)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 行首注：左齐第一扇岸门（门排铺满整行，第一扇门就从行首起）。原先是 14px 悬在画面正中的一行，
		# 像漏掉的调试字（第 1 轮评审 minor 7）。绢本下注文落在一方墨底小笺上，16px。
		if UiTheme.IS_JUANBEN:
			hint.add_theme_font_size_override("font_size", 16)
			var note := PanelContainer.new()
			note.name = "ShoreNote"
			note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			note.add_theme_stylebox_override("panel", UiTheme.log_well())
			note.add_child(hint)
			band.add_child(note)
		else:
			UiTheme.style_overlay(hint)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			band.add_child(hint)

	var doors := HBoxContainer.new()
	doors.name = "ShoreDoors"
	doors.add_theme_constant_override("separation", 12)
	doors.alignment = BoxContainer.ALIGNMENT_CENTER
	doors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(doors)
	var by_id := {}
	for raw in _shore_facilities:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var fac: Dictionary = raw
		by_id[str(fac.get("id", ""))] = fac
	var pin_yard := _shore_pin_shipyard()
	for fid in shore_hand:
		if not by_id.has(fid):
			continue
		var open_fac: Dictionary = by_id[fid]
		doors.add_child(_make_shore_door(open_fac, fid == "city_shipyard" and pin_yard))

	var shut := HBoxContainer.new()
	shut.name = "ShoreShut"
	shut.add_theme_constant_override("separation", 8)
	shut.alignment = BoxContainer.ALIGNMENT_CENTER
	shut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(shut)
	for raw_shut in _shore_facilities:
		if typeof(raw_shut) != TYPE_DICTIONARY:
			continue
		var shut_fac: Dictionary = raw_shut
		var shut_id := str(shut_fac.get("id", ""))
		if shut_id != "" and shut_id not in shore_hand:
			shut.add_child(_make_shore_shut(shut_fac))

	var actions := HBoxContainer.new()
	actions.name = "ShoreActions"
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(actions)
	if _shore_mode == "ended":
		# 终局：不出海、不候日，只留重读与读档
		if GameState.ended_text != "":
			actions.add_child(_shore_action("重读结局", Vector2(220, 48), true, _on_reread_ending))
	elif _shore_mode == "siege":
		# 围城中不出海：动作行去掉「看风」
		actions.add_child(_shore_action("再候一日", Vector2(160, 42), false, _on_shore_wait))
	else:
		actions.add_child(_shore_action("看风", Vector2(220, 48), true, _on_set_sail))
		actions.add_child(_shore_action("再候一日", Vector2(160, 42), false, _on_shore_wait))
	actions.add_child(_shore_action("航海日志", Vector2(140, 42), false, _show_save_dialog))
	# characters 线：人物志（浮页，不过日子、不入存档）
	if not GameManager.all_characters().is_empty():
		actions.add_child(_shore_action("人物志", Vector2(120, 42), false, _open_codex.bind("")))


func _on_reread_ending() -> void:
	_show_notice_dialog(GameState.ended, GameState.ended_at, GameState.ended_text)


## 岸带上方的墨底小笺（守城城防账、终局航海札记共用）：log_well 暗墨底、泥金淡边，16px 起。
func _band_slip(slip_name: String) -> Array:
	var slip := PanelContainer.new()
	slip.name = slip_name
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := UiTheme.log_well()
	if box is StyleBoxFlat:
		var well := (box as StyleBoxFlat).duplicate() as StyleBoxFlat
		well.bg_color = Color(UiTheme.INK_SOLID, 0.86) if UiTheme.IS_JUANBEN else well.bg_color
		well.content_margin_left = 18
		well.content_margin_right = 18
		well.content_margin_top = 10
		well.content_margin_bottom = 12
		box = well
	slip.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	slip.add_child(col)
	return [slip, col]


func _band_line(col: Node, text: String, color: Color, px := 16, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiTheme.title_font() if title else UiTheme.font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	col.add_child(l)
	return l


func _shore_band() -> VBoxContainer:
	var existing := port_mode.get_node_or_null("ShoreBand")
	if existing is VBoxContainer:
		return existing
	var band := VBoxContainer.new()
	band.name = "ShoreBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_left = 16
	band.offset_top = -372
	band.offset_right = -16
	band.offset_bottom = -12
	band.add_theme_constant_override("separation", 8)
	band.alignment = BoxContainer.ALIGNMENT_END
	port_mode.add_child(band)
	return band


func _shore_action(label: String, size: Vector2, accent: bool, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = size
	btn.pressed.connect(callback)
	UiTheme.style_button(btn, accent)
	return btn


func _make_shore_door(fac: Dictionary, pinned_yard: bool) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 104 if UiTheme.IS_JUANBEN else 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.paper_card(card)
	if UiTheme.IS_JUANBEN:
		# 工席是港画上最亮的一块（宣纸 v≈0.85，港画均值 0.21–0.29）：纸面压到旧绢调，字不压（self_modulate 只染面板自身）
		card.self_modulate = UiTheme.DOOR_PAPER_TINT
		card.add_child(_door_watermark(fac))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12 if not UiTheme.IS_JUANBEN else 8)
	margin.add_theme_constant_override("margin_bottom", 10 if not UiTheme.IS_JUANBEN else 8)
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var icon_id := str(fac.get("id", "")).replace("city_", "")
	# 本地终局线的守城卡 / 特殊卡没有自己的图标文件，借同性质设施的图标，别留空框
	const SPECIAL_ICON := {
		"siege_muster": "yamen", "siege_grain": "market", "siege_wall": "shipyard",
		"siege_envoy": "tavern", "siege_nangshan": "yamen", "siege_nunnery": "temple",
		"special_hanjiang_escape": "shipyard", "special_resign_1275": "exam",
		"special_yashan": "shipyard", "special_gangshou_end": "yamen",
	}
	if SPECIAL_ICON.has(icon_id):
		icon_id = SPECIAL_ICON[icon_id]
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(46, 46)
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(40, 40)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_tex := GameManager.load_texture("res://assets/icon_%s.png" % icon_id)
	if icon_tex != null:
		tex_rect.texture = icon_tex
	frame.add_child(tex_rect)
	hbox.add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = str(fac.get("title", "去处"))
	title_lbl.add_theme_font_override("font", UiTheme.font())
	title_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	title_lbl.add_theme_color_override("font_color", UiTheme.TIDE)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = str(fac.get("subtitle", ""))
	UiTheme.style_footnote(sub_lbl)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_lbl)

	if pinned_yard:
		var why := Label.new()
		why.text = "船还开不出去"
		why.add_theme_font_override("font", UiTheme.font())
		why.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
		why.add_theme_color_override("font_color", UiTheme.CINNABAR)
		why.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(why)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.pressed.connect(_on_facility_pressed.bind(fac))
	btn.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", UiTheme.shore_door_hover()))
	btn.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", UiTheme.shore_door()))
	card.add_child(btn)
	return card


## 工席右半的淡墨大字水印（牙 / 贡 / 会…，马善政 90px，α0.07）：卡右半原先空着，14 港同一构图（第 2 轮美术 minor 1）
const DOOR_MARK := {
	"market": "牙", "exam": "贡", "guild": "会", "shipyard": "船", "tavern": "酒", "inn": "店",
	"residence": "宅", "temple": "寺", "yamen": "舶",
	"siege_muster": "兵", "siege_grain": "粮", "siege_wall": "城", "siege_envoy": "使", "siege_nangshan": "伏",
	"special_hanjiang_escape": "帆", "special_resign_1275": "辞", "special_yashan": "崖", "special_gangshou_end": "纲",
}


func _door_watermark(fac: Dictionary) -> Control:
	var holder := Control.new()
	holder.name = "DoorMark"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	var key := str(fac.get("id", "")).replace("city_", "")
	var ch := str(DOOR_MARK.get(key, str(fac.get("title", "")).left(1)))
	var mark := Label.new()
	mark.text = ch
	mark.set_meta(&"nk1_title", true)  # 纸上换色 / 换字体只做一次的记号：水印自带字体与色，不再改
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_override("font", UiTheme.title_font())
	mark.add_theme_font_size_override("font_size", 90)
	mark.add_theme_color_override("font_color", Color(UiTheme.PAPER_TEXT, 0.08))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	mark.offset_left = -130
	mark.offset_right = -14
	mark.offset_top = -10
	mark.offset_bottom = 14
	holder.add_child(mark)
	return holder


func _make_shore_shut(fac: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = str(fac.get("title", "去处"))
	btn.custom_minimum_size = Vector2(108, 36)
	btn.set_meta("shore_shut", true)
	btn.pressed.connect(_on_shore_shut)
	UiTheme.style_button(btn, false)
	var shut_box := UiTheme.shore_shut()
	btn.add_theme_stylebox_override("normal", shut_box)
	btn.add_theme_stylebox_override("hover", shut_box)
	btn.add_theme_stylebox_override("pressed", shut_box)
	btn.add_theme_stylebox_override("focus", shut_box)
	btn.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", UiTheme.TEXT_DIM)
	btn.add_theme_color_override("font_pressed_color", UiTheme.TEXT_DIM)
	return btn


func _on_shore_shut() -> void:
	log_msg("今日这处没开门。")
	update_status_panel()


func _on_shore_wait() -> void:
	GameState.shore_salt += 1
	GameManager.advance_days(1)
	log_msg("在岸上又候了一日，门又换了几处。")
	# 按页型重排（守城页候一日仍是守城页，不会退回寻常岸带多出「看风」）
	_build_shore()
	update_status_panel()



func _on_set_sail() -> void:
	if GameState.is_ended():
		log_msg("【此局已终】%s。船不再出港了。" % GameState.ended)
		return
	if not Fleet.can_sail():
		var bad := Fleet.crew_shortfall()
		if bad.is_empty():
			log_msg("【无法出海】水手不足，船开不动。先去船屋雇人。")
		else:
			var parts := PackedStringArray()
			for b in bad:
				parts.append("%s　水手 %d / %d" % [b["name"], b["crew"], b["crew_min"]])
			log_msg("【无法出海】水手不足　%s。先去船屋雇人。" % "、".join(parts))
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
		# 记下出港（港、日）：回港时据此判断是不是真正抵港，决定出不出抵港横幅（会话内，不进存档）
		_CINE.note_departure(GameState.last_port, Calendar.absolute_day())
		get_tree().change_scene_to_file("res://scenes/SeaChart.tscn")



## read_only：从标题页「续卷」进来——还没开局，「记录」不可用，只留「翻阅」。
func _show_save_dialog(read_only := false) -> void:
	if is_instance_valid(_save_host):
		_save_host.queue_free()
	_dismiss_banner()
	# 日志册页上沿正落在港名匾字脚上：匾先淡去，合上时回来（第 2 轮美术 minor 2）
	if port_mode.visible:
		_show_port_layer(false, 0.15, true)
	var host := Control.new()
	host.name = "SaveSheet"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	_save_host = host

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = UiTheme.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_save_dim_input)
	host.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var sheet := PanelContainer.new()
	# 两张 480 工席并排，间距 12，左右边距各 22。
	sheet.custom_minimum_size = Vector2(1016, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	center.add_child(sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := Label.new()
	head.text = "航海日志"
	UiTheme.style_heading(head)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	_begin_benches(col)
	for slot in range(1, SaveLoad.SLOTS + 1):
		var n := int(slot)
		var slip := _slip_body()
		# 卷号写中文数字：马善政的「1」像小写 l（第 1 轮评审 minor 12）
		_slip_title(slip, "第%s卷" % _cn_chapter(n), SaveLoad.save_label(n))
		var row := _slip_row(slip)
		var write := _slip_chip(row, "记录", _on_save_slot.bind(n), true)
		write.disabled = read_only
		var read := _slip_chip(row, "翻阅", _on_load_slot.bind(n))
		read.disabled = not SaveLoad.has_save(n)
	var benches := col.get_node("Benches") as HFlowContainer
	var row_h := 0.0
	for child in benches.get_children():
		if child is Control:
			row_h = maxf(row_h, (child as Control).get_combined_minimum_size().y)
	benches.custom_minimum_size = Vector2(972, row_h * 2.0 + 8.0)
	_end_benches()

	var close := Button.new()
	close.text = "合上"
	close.custom_minimum_size = Vector2(160, 42)
	close.pressed.connect(_close_save_sheet)
	col.add_child(close)
	UiTheme.style_button(close, true)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.pop_in(sheet)


func _on_save_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			_close_save_sheet()


func _close_save_sheet() -> void:
	if is_instance_valid(_save_host):
		_save_host.queue_free()
	_save_host = null
	if port_mode.visible and not is_instance_valid(_chapter_host):
		_show_port_layer(true, 0.15, true)


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
	if _check_absent_from_xinghua():
		return
	var first_port := GameState.visited_ports.is_empty()
	GameState.visit_port(port_id)
	var res := GameState.try_advance_chapter()
	if res.get("advanced", false) or res.get("resolved", false):
		_show_chapter_dialog(res)
	elif first_port and GameState.chapter == 1 and _CINE.live():
		# 序章走完、第一次踏上港口（岸页开张）：第一章开卷。只演卡，不弹册页。
		# 卡紧跟在港页 load_scene 之后：黑场第 0 帧就压满，不先露出港页再压黑（第 2 轮美术 M1）
		_CS_CARD.play(self, 1, _CINE.DATA, _CINE.year_text(Calendar.year, Calendar.ERAS), true)
	elif _arrival_banner and _CINE.live():
		# 海图回港的真正抵港：旧绢挂签报副题（港名已在顶上的墨刷匾里，同屏不写第二遍），居中挂在匾下；
		# 不拦输入、2.65 秒自退；开章 / 了结时让位给章节卡与结局过场。
		_CS_BANNER.show_banner(self, port_id, _CINE.DATA, 0.285, false)
	update_status_panel()


## 「数年后」：把这一段的行为结成几行，再加上跳年的代价。
## 这是全作唯一一处让玩家看见「时间过去了」的地方——不能只写一句「三年后」。
func _era_summary_lines(years: int) -> Array:
	var lines := []
	var trips: int = GameState.era_trips
	var route: String = GameState.era_main_route()
	if trips > 0:
		if route != "":
			lines.append("这%s，你的船跑了%s趟，走得最多的是%s。" % [
				"几年" if years > 0 else "一段日子", _cn_num(trips, true), route,
			])
		else:
			lines.append("这%s，你的船跑了%s趟。" % ["几年" if years > 0 else "一段日子", _cn_num(trips, true)])
	if GameState.merchant_credit >= 20:
		lines.append("牙行里提起你的名字，不必再加「泉州那个姓陈的」。")
	elif GameState.merchant_credit <= -10:
		lines.append("有几家牙行不再接你的单子，理由都说得很客气。")
	if not Crew.hired.is_empty():
		var names := []
		for c in Crew.roster():
			names.append(str(c.get("name", "")))
		lines.append("还在船上的：%s。" % "、".join(names))
	return lines


func _show_chapter_dialog(res: Dictionary) -> void:
	# 过场先演（晋升 → 章节卡，了结 / 结局 → 结局过场），演完带标记回到这里；headless 下当帧直接往下走
	if _cinema_before_sheet(res):
		return
	# 结算底图随册页一起换（有结局过场时正是过场全黑的那一刻，画面上看不见切换）
	var ending := str(res.get("ending", ""))
	if ending != "" and ENDING_BG.has(ending):
		_set_background_file(ENDING_BG[ending])  # 结算画面：台词压在结局图上
	var resolved_sheet: bool = bool(res.get("resolved", false))
	if resolved_sheet:
		# 结局 / 了结册页：港页工作层（工席、小笺、门排、动作行、港名匾）0.2 秒退去；崖山外海这类调查页的正文与选项整页隐去，
		# 结局最后一眼只留结局图与册页（第 2 轮美术 M2）。关册页走 load_scene，版面整页重建，自然回来。不入存档。
		_dismiss_banner()
		_show_port_layer(false, 0.2)
		investigation_mode.visible = false
		npc_mode.visible = false
	if is_instance_valid(_chapter_host):
		_chapter_host.queue_free()
	_chapter_next_scene = str(res.get("scene", ""))

	var host := Control.new()
	host.name = "ChapterSheet"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(host)
	_chapter_host = host

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 结局册页压得更深（宣纸工席退了之后仍有港画高光）；升章册页照旧 0.55
	dim.color = Color(0.05, 0.03, 0.02, 0.72 if resolved_sheet and UiTheme.IS_JUANBEN else 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var sheet := PanelContainer.new()
	# 结局册页的长文加宽到 820；升章册页 640（第 1 轮评审 UX M8）
	var wide: bool = bool(res.get("resolved", false)) or str(res.get("ending", "")) != ""
	var sheet_w := 820 if wide and UiTheme.IS_JUANBEN else 640
	sheet.custom_minimum_size = Vector2(sheet_w, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	center.add_child(sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(sheet_w - 44, 0)
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var kicker := Label.new()
	var ok_text := "承此一路"
	if res.get("resolved", false):
		kicker.text = "了结"
		ok_text = "记下这一纲"
	else:
		# 中文数字不留空格（「第 二 章」是给阿拉伯数字留的格式，第 2 轮美术 minor 3）
		kicker.text = "第%s章・%s" % [
			_cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
		]
	UiTheme.style_section_label(kicker)
	if UiTheme.IS_JUANBEN:
		kicker.add_theme_font_size_override("font_size", 16)
		kicker.add_theme_font_override("font", UiTheme.body_spaced(2))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kicker)

	var head := Label.new()
	head.text = str(res.get("title", ""))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_heading(head)
	col.add_child(head)

	var raw := str(res.get("text", ""))
	# 本地 main P1 时间脊柱：晋升跳年。这些年不是空白，摘要（跑了几趟 / 主航线 / 信用）与代价（船旧人走）写在正文前。
	var years: int = int(res.get("years", 0))
	if years > 0:
		var era := _era_summary_lines(years)
		var costs: Array = GameManager.skip_years(years)
		var block := "【%s年后・%s】\n" % [_cn_num(years, true), Calendar.get_date_string()]
		if not era.is_empty():
			block += "\n".join(era) + "\n"
		if not costs.is_empty():
			block += "\n".join(costs) + "\n"
		raw = block + "\n" + raw
		GameState.clear_era()
		update_status_panel()
	var body_w := sheet_w - 80
	# 正文区高：按画布高度放（720 下约 420，16:10 下多出来的高度也用上），按行高取整，底行不再裁半行
	var body_h := _chapter_body_height(raw, body_w)
	var scroll := ScrollContainer.new()
	scroll.name = "SheetScroll"
	scroll.custom_minimum_size = Vector2(body_w, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body := Label.new()
	body.text = raw
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(body_w, 0)
	body.add_theme_font_override("font", UiTheme.font())
	body.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	body.add_theme_color_override("font_color", UiTheme.TEXT)
	body.add_theme_constant_override("line_spacing", UiTheme.LINE_BODY)
	scroll.add_child(body)
	# 滚动区底边 24px 渐隐：还有下文时底行淡进墨里，而不是被一刀裁掉半行（第 1 轮评审 minor 2）
	col.add_child(UiTheme.fade_scroll(scroll, 24))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var ok := Button.new()
	ok.text = ok_text
	ok.pressed.connect(_confirm_chapter_sheet)
	col.add_child(ok)
	UiTheme.style_button(ok, true)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 绢本：印钮居中、定宽，不拉成一条通栏红条（夜潮照旧通栏）
	if UiTheme.IS_JUANBEN:
		ok.custom_minimum_size = Vector2(240, 44)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	update_status_panel()
	# 不是由章节卡揭开的（没有过场、或结局过场全黑之后）：册页淡入 + 微缩放，不再一帧弹出
	if not res.get("_cinema", false) or not res.get("advanced", false):
		UiTheme.pop_in(sheet)


## 正文区高：按行估高（每行 body_w / 字号 个字），上限按画布高度（画布高 − 300，720 下 420），
## 并取整到整行高，免得底行裁出半行。
func _chapter_body_height(text: String, body_w := 560) -> int:
	var per_line := maxi(12, int(floor(float(body_w) / float(UiTheme.SIZE_BODY + 1))))
	var line_h := int(ceil(UiTheme.font().get_height(UiTheme.SIZE_BODY))) + UiTheme.LINE_BODY
	var lines := 0
	for raw_line in text.split("\n"):
		var n := raw_line.length()
		lines += 1 if n == 0 else maxi(1, int(ceil(float(n) / float(per_line))))
	var cap_h := 340
	if is_inside_tree():
		cap_h = clampi(int(get_viewport_rect().size.y) - 300, 300, 560)
	var want := clampi(lines * line_h + 8, 88, cap_h)
	return int(floor(float(want - 8) / float(line_h))) * line_h + 8


## 过场先于册页（cinematics 线）：晋升先演章节卡（年号按当前历法 + 跳年现算），了结 / 结局先演 data/cutscenes.json
## endings 映射里的结局过场；演完带 _cinema 标记回到 _show_chapter_dialog 弹原册页。
## headless / 巡检关闭 / 映射缺失时返回 false，调用方当帧照原逻辑走。
func _cinema_before_sheet(res: Dictionary) -> bool:
	if res.get("_cinema", false) or not _CINE.live():
		return false
	var node: Node = null
	if res.get("advanced", false):
		var year: int = Calendar.year + int(res.get("years", 0))
		node = _CS_CARD.play(self, GameState.chapter, _CINE.DATA, _CINE.year_text(year, Calendar.ERAS))
	elif res.get("resolved", false):
		var key := _ending_cinema_key(res)
		if key != "":
			node = _CS_PLAYER.play_ending(self, key, _CINE.DATA)
	if node == null:
		return false
	var after := res.duplicate()
	after["_cinema"] = true
	# 章节卡：纸面开始退去时就在卡底下建好压暗层与册页（连同跳年后的状态匾），纸退去揭开的就是最终画面；
	# 结局过场在全黑时发 finished，照旧接 finished
	var sig := "exiting" if node.has_signal("exiting") else "finished"
	node.connect(sig, _show_chapter_dialog.bind(after), CONNECT_ONE_SHOT)
	return true


## 结局过场的键：_show_notice_dialog 带来的结局名（忠肃…）；章末了结（res.scene 是 ending_* 场景）取 GameState.ending_id
func _ending_cinema_key(res: Dictionary) -> String:
	var key := str(res.get("ending", ""))
	if key == "" and str(res.get("scene", "")) != "" and GameState.ending_id != "":
		key = GameState.ending_id
	return key


func _confirm_chapter_sheet() -> void:
	if _chapter_host == null:
		return
	var next_scene := _chapter_next_scene
	_chapter_next_scene = ""
	var host := _chapter_host
	_chapter_host = null
	host.visible = false
	host.queue_free()
	if next_scene != "" and not GameManager.get_scene_by_id(next_scene).is_empty():
		load_scene(next_scene)
	else:
		load_scene(current_scene_id)


func _select_market_ship(idx: int) -> void:
	if idx == _market_ship:
		return
	_market_ship = idx
	_market_hold = true
	load_scene(current_scene_id)


func _cn_chapter(n: int) -> String:
	var cn := ["", "一", "二", "三", "四", "五", "六"]
	return cn[n] if n < cn.size() else str(n)


func _on_facility_pressed(fac: Dictionary) -> void:
	var raw_id := str(fac.get("id", ""))
	# 本地 main 的终局特殊卡（涵江 / 辞呈 / 崖山 / 纲首 / 守城 siege_*）不走「今日只开三处」，先分发
	if GameState.is_ended():
		return
	if raw_id == CARD_HANJIANG:
		_on_hanjiang_escape()
		return
	if raw_id == CARD_RESIGN:
		_on_resign_1275()
		return
	if raw_id == CARD_YASHAN:
		_on_yashan()
		return
	if raw_id == CARD_GANGSHOU:
		_on_gangshou_end()
		return
	if raw_id.begins_with("siege_"):
		_on_siege_card(raw_id)
		return
	if raw_id.begins_with("city_") and raw_id not in shore_hand:
		log_msg("今日这处没开门。")
		update_status_panel()
		return
	var target_scene = raw_id
	# 兴化序章三张卡仍进调查页；已经踏足泉州之后再回兴化，改走动态页。
	if (
		current_scene_id == "xinghua"
		and target_scene in PROLOGUE_ONLY_FACILITIES
		and not ("quanzhou" in GameState.visited_ports)
	):
		load_scene(target_scene)
		return
	# 旅店 city_inn 与牙行一样在 REMAPPED_FACILITIES 里，随当前港口改写（云端 be04/c148/00b4）。
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
		# 序章酒棚各页：下三分之一对白条（type=title 的卷首四页走 _setup_title_mode，不到这里）
		_frame_sheet(true, true)
		scene_title.add_theme_font_size_override("font_size", 24)
	else:
		scene_title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)

	var shown_title := str(scene_data.get("title", "")).strip_edges()
	if shown_title == "":
		shown_title = str(scene_data.get("cg_title", "")).strip_edges()
	if shown_title == "":
		var speaker := str(scene_data.get("speaker", "")).strip_edges()
		if speaker != "" and speaker != "——":
			shown_title = speaker
	if shown_title == "内景":
		shown_title = _interior_title(str(scene_data.get("id", "")))
	scene_title.visible = shown_title != ""
	scene_title.text = shown_title
	var title_rule := scene_title.get_parent().get_node_or_null("HSeparator") as Control
	if title_rule != null:
		# 对白条的旁白页（说话人「——」）没有名牌，名牌下那道金线也收起
		title_rule.visible = scene_title.visible or not cinematic
	var shown_body := str(scene_data.get("body", "")).strip_edges()
	if shown_body == "":
		shown_body = str(scene_data.get("cg_sub", "")).strip_edges()
	if shown_body == "" and str(scene_data.get("title", "")).strip_edges() == "内景":
		shown_body = _interior_lead(str(scene_data.get("id", "")))
	body_text.text = _unescape_scene_text(shown_body)

	var investigations = scene_data.get("investigations", [])
	_show_investigation_chrome(investigations.size() > 0)
	for inv in investigations:
		var btn = Button.new()
		btn.text = str(inv.get("label", "互动"))
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
	UiTheme.style_leave_button(btn)
	choices_label.visible = true


func _add_leave_button(port_id: String) -> void:
	var btn = Button.new()
	btn.text = "离开"
	btn.custom_minimum_size = Vector2(160, 42)
	btn.pressed.connect(func(): load_scene(port_id))
	var host: Node = _page_footer if _page_footer != null else choices_container
	host.add_child(btn)
	UiTheme.style_leave_button(btn)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	choices_label.visible = false


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
			if _cg_dialogue:
				# 对白条：翻页只是一枚靠右的小「续 ▼」墨钮（点画面任意处也续读）；路由照旧取这条 choice。
				# ▾（U+25BE）文楷子集里没有，用 ▼
				btn.text = "续 ▼"
				btn.set_meta(&"page_turn", true)
				UiTheme.style_button(btn, false)
				btn.add_theme_font_size_override("font_size", 16)
				btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
				btn.custom_minimum_size = Vector2(88, 34)
				btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			else:
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
			# 以下五键取自云端 21ce（此前写入即丢弃）：补给、货物、船体、货损、发现
			"supplies":
				var want := int(val)
				var got := Fleet.add_supply_pair(want)
				if want > 0 and got < want:
					push_warning("补给装不下 %d 份，实装 %d @ %s" % [want, got, current_scene_id])
			"cargo":
				var ids: Array = val if val is Array else [val]
				for gid in ids:
					var good := GameManager.get_good_by_id(str(gid))
					if good.is_empty():
						push_warning("未知货物 %s @ %s" % [gid, current_scene_id])
						continue
					if not Fleet.add_cargo(str(gid), 1, 0.0):
						push_warning("舱位不足，未装入 %s @ %s" % [gid, current_scene_id])
			"ship":
				Fleet.adjust_flagship_durability(int(val))
			"cargo_loss":
				_apply_cargo_loss(str(val))
			"discovery":
				var did := _discovery_id_for(str(val))
				if did == "":
					push_warning("未知发现 %s @ %s" % [val, current_scene_id])
				else:
					GameState.record_discovery(did)
	update_status_panel()


## 序章货损令牌（云端 21ce）：青白瓷三成、唐坊寄物水渍一件；其余令牌只记入账册。
func _apply_cargo_loss(token: String) -> void:
	if token == "qingbai_porcelain_partial_loss":
		var q := Fleet.cargo_qty("qingbai_porcelain")
		if q > 0:
			var loss := mini(q, maxi(1, int(round(float(q) * 0.3))))
			Fleet.remove_cargo("qingbai_porcelain", loss)
	elif token == "tangfang_parcel_water_stain":
		if Fleet.cargo_qty("tangfang_parcel") > 0:
			Fleet.remove_cargo("tangfang_parcel", 1)
			GameState.add_ledger_note("parcel_stained")
	else:
		GameState.add_ledger_note(token)


## 剧情效果里的发现可以写中文名或 id（云端 21ce）。
func _discovery_id_for(token: String) -> String:
	var want := token.strip_edges()
	for d in GameManager.discoveries_data.get("discoveries", []):
		if str(d.get("name", "")) == want or str(d.get("id", "")) == want:
			return str(d.get("id", ""))
	return ""


## 序章对白条：点画面任意处续读（只在这一页全是翻页、没有真岔路时；浮层开着时点不到这里）
func _on_stage_click(event: InputEvent) -> void:
	if not _cg_dialogue or not investigation_mode.visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var first: Button = null
	for c in choices_container.get_children():
		if not (c is Button):
			continue
		if not (c as Button).has_meta(&"page_turn"):
			return
		if first == null and not (c as Button).disabled:
			first = c
	if first != null:
		accept_event()
		first.pressed.emit()


func _gui_input(event: InputEvent) -> void:
	_on_stage_click(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if is_instance_valid(_chapter_host):
			_confirm_chapter_sheet()
			get_viewport().set_input_as_handled()
		elif is_instance_valid(_save_host):
			_close_save_sheet()
			get_viewport().set_input_as_handled()
		elif _activate_first_choice():
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


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══
const CARD_HANJIANG := "special_hanjiang_escape"
const CARD_SIEGE_MUSTER := "siege_muster"      # 衙门・募兵 / 石手军
const CARD_SIEGE_GRAIN := "siege_grain"        # 市场・屯粮
const CARD_SIEGE_WALL := "siege_wall"          # 船厂・修城墙
const CARD_SIEGE_ENVOY := "siege_envoy"        # 酒馆・使者
const CARD_SIEGE_NANGSHAN := "siege_nangshan"  # 囊山设伏
const CARD_SIEGE_NUNNERY := "siege_nunnery"    # 福州尼寺（不可操作）
const CARD_RESIGN := "special_resign_1275"
const CARD_YASHAN := "special_yashan"
const CARD_GANGSHOU := "special_gangshou_end"


func _add_save_button() -> void:
	var btn = Button.new()
	btn.text = "航海日志"
	btn.custom_minimum_size = Vector2(250, 44)
	btn.pressed.connect(_show_save_dialog)
	right_facilities.add_child(btn)



func _check_absent_from_xinghua() -> bool:
	if GameState.is_ended() or not GameState.has_flag("renamed_wenlong"):
		return false
	if GameState.siege_open() or GameState.has_flag("siege_fought"):
		return false
	# 按日期判，不按当前战况：1277-02/03 陈瓒复城时兴化会回 loyal，
	# 若看当前战况，士人线玩家在那两个月入港就躲过了这个结局。城破发生过就是发生过。
	if not (Calendar.year > 1276 or (Calendar.year == 1276 and Calendar.month >= 12)):
		return false

	_show_notice_dialog(
		"未归", "兴化・景炎元年十二月",
		"消息是在别处听到的。

兴化城破了。城中兵不满千，守了四十天。城头上挂过一幅白布，八个字，来往的人都说见过。
部将林华出去侦敌，回来时后面跟着一万人。通判曹澄孙开的东门。

母亲黄氏和幼子璥被扣在福州一座尼寺里。有人说，只要城里那个人肯出来，当天就放。
城里那个人没有出来——因为城里没有那个人。

你姓陈，名文龙，字君贲，咸淳四年殿试第一，御笔改的名。这些年你走的是另一条路。
史书上后来写：是年，兴化陷，守臣不知所终。

——
一百多年后，福州台江，泗洲。江边没有庙。
渔民出海前拜妈祖，只拜妈祖。官船出洋，二号封舟空着。

这个世界少了一位海神。也没有多出几条回来的船。",
		"未归"
	)
	return true


## 终局后的港口页：不出海、不交易、不推进时间，只回顾与读档。

func _make_facility_card(fac: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 90)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	card.add_child(hbox)

	var icon_id = fac.get("id", "").replace("city_", "")
	var icon_path = "res://assets/icon_" + icon_id + ".png"
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(80, 80)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var icon_tex := GameManager.load_texture(icon_path)
	if icon_tex != null:
		tex_rect.texture = icon_tex

	var icon_margin = MarginContainer.new()
	icon_margin.add_theme_constant_override("margin_left", 5)
	icon_margin.add_theme_constant_override("margin_right", 5)
	icon_margin.add_child(tex_rect)
	hbox.add_child(icon_margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = fac.get("title", "无名之处")
	title_lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = fac.get("subtitle", "")
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	sub_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(sub_lbl)

	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_facility_pressed.bind(fac))
	btn.mouse_entered.connect(func(): style.bg_color = Color(0.25, 0.25, 0.3, 0.8))
	btn.mouse_exited.connect(func(): style.bg_color = Color(0.1, 0.1, 0.1, 0.6))
	card.add_child(btn)

	return card



func _on_gangshou_end() -> void:
	var pu := GameState.has_flag("sided_pu")
	var head := "泉州・至元二十二年"
	var text := ""
	if pu:
		text = "市舶司的册子换了封面。你的名字还在，「纲首」两字旁边加了一个蒙古官名，你不认得。
蒲家的账房说，明年起船去占城不用再走暗关了——「都是一家人」。

"
	else:
		text = "市舶司的册子换了封面。你的名字还在，只是排在很后面。
那些当年站错队的，名字已经不在册上了。你还在。

"
	text += "你活到了至元二十年代。泉州比从前更大，港里有波斯人、大食人、高丽人，还有从前不敢来的北方人。
有一年你雇的一个兴化水手在船上说：他们村口有一座小祠，供一个叫陈瓒的。
你问，有没有一个叫陈文龙的。
他说没听过。

——
一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。
这个世界少了一位海神，多了几条回来的船。"
	_show_notice_dialog("纲首" if not pu else "泉州蒲氏的船", head, text, "泉州蒲氏的船" if pu else "纲首")





## 「岸上的根」：陈瓒守城，你带族人出海。第一章那次复核在二十二年后变现。

func _on_hanjiang_escape() -> void:
	if Fleet.supply_days() < 7:
		log_msg("【水粮不足】四条船的人，至少要撑七日。先去船屋补齐。")
		update_status_panel()
		return
	GameManager.advance_days(7)
	GameState.set_flag("ending_root_sea")
	GameState.fame += 10
	GameState.hometown_tendency += 10
	GameState.add_ledger_note("北礁可泊")
	var stake_line := "陈瓒没有上船。他说他姓陈，在这里出生，就死在这里。" if GameState.has_flag("chen_zan_stake") else "陈瓒没有上船。"
	_show_notice_dialog(
		"岸上的根",
		"旧避风澳・景炎三年三月",
		"四条船。族里能走的都在船上，老夫人也在，她把箧底那叠策论草稿带上了船，说是「%s的东西」。\n%s\n\n出海口的时候元兵已经进城了。海上没有人追。你看水色。北礁可泊。二十二年前，一个舵手教过你。\n\n船在旧避风澳泊了六天，避了一场风。第七天早晨，老夫人把那叠草稿拿出来晒。纸都黄了，字还在。她一张一张看，看完了放回去。\n「%s，」她说，「往南走吧。」\n\n——\n一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。\n这个世界少了一位海神，多了几条回来的船。" % [
			"子龙", stake_line, "子龙",
		],
		"岸上的根"
	)


## 通用结算对话框（章节晋升以外的历史节点与结局用）。
## ending 非空则落定终局：关掉对话框后港口页只剩回顾札记。

func _on_resign_1275() -> void:
	_enter_panel_mode()
	_set_background_file("bg_linan.jpg")  # 1275 冬临安：终局抉择节点专属底图
	scene_title.text = "临安・嘉会门"
	body_text.text = "辞呈是三天前批的。批语只有两个字：「依奏。」
车出嘉会门时是卯时，守门的兵在跺脚取暖。车里放着一只书箧，箧里是十三年前那本夹着货引的《论语》。

车过江头。钱塘江的水是灰的，和兴化海口一个颜色。车夫问：过了江往南，走陆路还是走海路？"

	var again := Button.new()
	again.text = "回头。再上一疏求还。"
	again.pressed.connect(func():
		GameState.set_flag("petitioned_return")
		GameState.scholar_tendency += 4
		GameState.add_ledger_note("复上疏不报")
		GameManager.advance_days(7)
		_show_notice_dialog("出国门而悔", "钱塘江畔",
			"你在江边客店里写了一夜。天亮时奏疏送进城去。
等了六天。没有回音。第七天，客店掌柜小心地问你还住不住。
你付了钱，上了去明州的船。奏疏后来有没有人拆过，你一辈子不知道。")
	)
	choices_container.add_child(again)

	var quiet := Button.new()
	quiet.text = "不回头。走海路回兴化。"
	quiet.pressed.connect(func():
		GameState.set_flag("quiet_return")
		GameState.set_flag("no_official_title")
		GameState.sea_tendency += 2
		GameState.hometown_tendency += 4
		GameManager.advance_days(11)
		_show_notice_dialog("不回头", "海上十一日",
			"船在明州换了一次，在温州又换了一次。海上十一天，你大部分时候在看水色。
二十年前阿那教过你怎么看，你以为早忘了。
没忘。")
	)
	choices_container.add_child(quiet)

	var defect := Button.new()
	defect.text = "车转向南，去泉州找林阿舶（清算士人三锚）"
	defect.disabled = GameState.money < 500
	defect.tooltip_text = "县学籍册、名流举荐信、宗祠联名担保——撕这三张纸要钱，也要名声。"
	defect.pressed.connect(func():
		if not GameState.spend_money(500):
			return
		GameState.set_flag("late_defection")
		GameState.fame -= 10
		GameState.sea_tendency += 6
		GameState.identity = "merchant"
		GameState.merchant_credit += 10
		GameState.add_ledger_note("一铺之地")
		GameManager.advance_days(9)
		_show_notice_dialog("一铺之地", "泉州・城南账房",
			"泉州。二十年。
码头比你记得的大了一倍，桅杆密得像一片死掉的林子。你问林阿舶的账房在哪，被问的人看了看你的官袍，指了指城南。

账房里坐着的不是林阿舶。是一个和你差不多年纪的人，算盘打得比林阿舶还快。他抬头：「陈大人？林老爹去年走了。他说过要是有个姓陈的读书人来，账上给留了一铺之地。」

他推过来一张纸。上面是二十年前你叔父那笔债的余数——早清了，用红笔划掉的。红笔底下另起一行：「陈子龙，船股一分。」

你还叫陈文龙。可这张纸上写的是另一个名字。")
	)
	choices_container.add_child(defect)

	choices_label.visible = true
	_add_leave_button(current_scene_id)


## 崖山：把粮与硫黄交上去，然后砍断自己的缆。

func _on_siege_card(card_id: String) -> void:
	match card_id:
		CARD_SIEGE_MUSTER:
			_siege_muster()
		CARD_SIEGE_GRAIN:
			_siege_buy_grain()
		CARD_SIEGE_WALL:
			_siege_repair_wall()
		CARD_SIEGE_ENVOY:
			_siege_envoy()
		CARD_SIEGE_NANGSHAN:
			_siege_nangshan()
		CARD_SIEGE_NUNNERY:
			_show_notice_dialog(
				"福州尼寺", "你什么也做不了",
				"母亲黄氏和幼子璥被扣在福州一座尼寺里。
城里有人说，只要开门，当天就放回来。

你在城头上站了很久。这件事没有选项。"
			)



func _on_yashan() -> void:
	_enter_panel_mode()
	scene_title.text = "崖山外海"
	var known_here := GameState.has_flag("sided_zhang")
	body_text.text = "祥兴二年二月。张世杰的船连成一片，船和船之间用铁索。
陈瓒的船不在——他回兴化了，听说起了兵，要把兴化夺回来。
"
	if known_here:
		body_text.text += "书吏翻册子翻到一半停住了：「泉州借船的那位。少保记着。」
他没有再问你叫什么。"
	else:
		body_text.text += "一个书吏在册子上记你的名字。他问：「哪个陈？」"

	var join := Button.new()
	join.text = "把粮与硫黄交上去，船留在外围"
	join.pressed.connect(func():
		GameState.fame += 12
		GameState.merchant_credit -= 30
		GameManager.advance_days(5)
		# 泉州借过船的，崖山有人替你留了外围的位置——砍缆的门槛低一截
		var speed_ok := Fleet.fleet_speed() > (70.0 if known_here else 90.0)
		var tail := ""
		if speed_ok and known_here:
			tail = "有人在铁索那头替你留了一道口子。你砍断自己的缆，从那道口子出去。
阿那要是还活着，会告诉你这时候该往哪边走。你自己看了水色。往南。"
		elif speed_ok:
			tail = "你砍断了自己的缆。阿那要是还活着，会告诉你这时候该往哪边走。你自己看了水色。往南。"
		else:
			tail = "你砍缆砍晚了。火从上风头卷过来，烧了半条船。人捞上来一半。往南走的时候，船比来时轻得多。"
		if not speed_ok:
			Fleet.damage_fleet(60.0)
			Fleet.lose_cargo_ratio(0.5)
		_show_notice_dialog("海上宋鬼", "崖山・祥兴二年二月",
			"战到午后，铁索连着的船开始烧。
%s

——
一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。
这个世界少了一位海神，多了几条回来的船。" % tail,
			"海上宋鬼")
	)
	choices_container.add_child(join)

	var pass_by := Button.new()
	pass_by.text = "不上前。远远看着，掉头往南"
	pass_by.pressed.connect(func():
		GameState.fame -= 6
		Fleet.morale = maxi(0, Fleet.morale - 10)
		GameState.add_ledger_note("崖山外海掉头")
		GameManager.advance_days(3)
		log_msg("你在十里外看着那片火。水手们没有说话。掉头往南的时候，风是顺的。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(pass_by)

	choices_label.visible = true
	_add_leave_button(current_scene_id)


## 海商线收官：至元年间，泉州更大了。

func _resign_decided() -> bool:
	return GameState.has_flag("petitioned_return") \
		or GameState.has_flag("quiet_return") \
		or GameState.has_flag("late_defection")


## 1275 年十二月：辞呈已批，出了嘉会门又后悔。三条路，用航向选，不用按钮选。

func _setup_ended_port() -> void:
	# 港名已由 _setup_port_mode 写好；这里只拼一次结局名（不再拿旧匾文字累加）
	var base := port_title.text
	if base.find("・") >= 0 and base.ends_with(GameState.ended):
		base = base.trim_suffix("・" + GameState.ended)
	port_title.text = "%s・%s" % [base, GameState.ended]
	_fit_port_title()
	# 云端港口页没有左右栏：札记是岸带上方一方墨笺，动作行只留「重读结局」「航海日志」「人物志」
	_shore_mode = "ended"
	_shore_facilities = []
	_refresh_shore()
	update_status_panel()


## 终局后港口页的航海札记：墨底小笺，标题马善政泥金，逐行 16px；行多时在 220 高里滚动、底边渐隐
func _epilogue_slip() -> Control:
	var parts := _band_slip("EpilogueSlip")
	var slip: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]
	slip.custom_minimum_size = Vector2(760, 0)
	_band_line(col, "航海札记", UiTheme.GOLD_HI, 24, true)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	var lines_box := VBoxContainer.new()
	lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines_box.add_theme_constant_override("separation", 4)
	lines_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := 0
	for line in GameState.epilogue_lines():
		var l := _band_line(lines_box, str(line), UiTheme.TEXT, 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(724, 0)
		n += 1
	if n <= 6:
		col.add_child(lines_box)
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "EpilogueScroll"
		scroll.custom_minimum_size = Vector2(724, 170)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(lines_box)
		col.add_child(UiTheme.fade_scroll(scroll, 24))
	return slip



func _setup_quanzhou_standoff(port_id: String) -> void:
	if port_id != "quanzhou" or Economy.war_status("quanzhou") != "contested":
		return
	if GameState.has_flag("sided_zhang") or GameState.has_flag("sided_pu") or GameState.has_flag("fled_quanzhou"):
		return

	var sep := Label.new()
	sep.text = "── 征船名册 ──"
	sep.add_theme_font_size_override("font_size", 13)
	choices_container.add_child(sep)

	var info := Label.new()
	var who: String = GameState.player_name if GameState.has_flag("renamed_wenlong") else "陈纲首"
	info.text = "牙行门口钉着一张纸，第四行是你的船。小吏低声说：「%s。张少保要船，蒲提举说泉州的船蒲家说了算。您站哪边？」" % who
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	choices_container.add_child(info)

	var zhang := Button.new()
	if Fleet.ships.size() > 1:
		zhang.text = "船借张世杰——编出最小一条船（名声 +8，海商信用 −15）"
	else:
		zhang.text = "船借张世杰——只此一条，出人出粮（名声 +8，海商信用 −15，水粮减半）"
	zhang.pressed.connect(func():
		if Fleet.ships.size() > 1:
			var idx := 0
			for i in range(Fleet.ships.size()):
				if Fleet.ship_capacity(i) < Fleet.ship_capacity(idx):
					idx = i
			var sname: String = Fleet.ships[idx].get("name", "一船")
			Fleet.ships.remove_at(idx)
			log_msg("「%s」挂了宋旗，编进张少保的船队。蒲家的人在码头上看着，没说话。" % sname)
		else:
			Fleet.water = Fleet.water / 2
			Fleet.food = Fleet.food / 2
			log_msg("船没给，人和粮给了一半。蒲家的人在码头上看着，没说话。")
		GameState.fame += 8
		GameState.merchant_credit -= 15
		GameState.pu_attention = 0
		GameState.set_flag("sided_zhang")
		GameState.add_ledger_note("借船张世杰")
		load_scene(current_scene_id)
	)
	choices_container.add_child(zhang)

	var pu := Button.new()
	pu.text = "跟蒲家——泉州抽解永久八折（海商信用 +10，名声 −8）"
	pu.pressed.connect(func():
		GameState.merchant_credit += 10
		GameState.fame -= 8
		GameState.set_flag("sided_pu")
		GameState.add_ledger_note("蒲家账房的茶")
		log_msg("蒲家的账房请你喝了茶。茶很好。他说泉州不会有事，「提举心里有数」。你问有数是什么数。他笑，没答。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(pu)

	var flee := Button.new()
	flee.text = "今夜出港，谁也不给——泉州对你封港至降元"
	flee.pressed.connect(func():
		GameState.set_flag("fled_quanzhou")
		GameState.ban_port("quanzhou", "1276-11")
		GameState.add_ledger_note("澎湖避祸")
		log_msg("夜潮。港外张世杰的船队像一座漂着的城。没有人拦你——他们不知道你是谁，这时候这是好事。泉州的门，年内不要再敲。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(flee)


## 港口页特殊卡：只在特定年月与旗标下出现。

func _setup_siege_port() -> void:
	port_title.text = "兴化军・围城"
	_fit_port_title()
	# 云端港口页没有左右栏，守城的账与五张卡都走岸带：卡以 siege_* 身份全部上岸（不受「今日只开三处」），
	# 城防账是岸带上方一方墨笺；福州尼寺本就不可操作，岸带一行也放不下六扇门，写成账里一行
	var cards: Array = []
	for fac in _siege_cards():
		if str(fac.get("id", "")) != CARD_SIEGE_NUNNERY:
			cards.append(fac)
	_shore_mode = "siege"
	_shore_facilities = cards
	_refresh_shore()
	update_status_panel()


## 守城城防账：马善政泥金题「城头白布八字」，一行 16px 兵粮城墙士气，缺粮时一枚朱砂「急」字小印领朱字告警
func _siege_stat_slip() -> Control:
	var parts := _band_slip("SiegeStat")
	var slip: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]
	var grain: int = GameState.siege_get("grain")
	var rounds_left: int = grain / GameState.SIEGE_GRAIN_PER_ROUND
	var fought: int = GameState.siege_get("round")
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	_band_line(head, "城头白布八字　生为宋臣　死为宋鬼", UiTheme.GOLD_HI, 22, true)
	var rounds := _band_line(head, "三阵・尚未接战" if fought <= 0 else "三阵・已守%s阵" % _cn_num(fought), UiTheme.TEXT, 18, true)
	rounds.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_band_line(col, "兵 %d（上限 %d）　粮 %d・够打%s阵　城墙 %d / %d　士气 %d%s" % [
		GameState.siege_get("troops"), GameState.siege_troop_cap(),
		grain, _cn_num(rounds_left), GameState.siege_get("wall"), GameState.SIEGE_WALL_MAX,
		GameState.siege_get("morale"),
		"　石手军在城" if str(GameState.siege.get("shishou", "")) == "kept" else "",
	], UiTheme.TEXT, 16)
	var warn := ""
	if rounds_left < 1:
		warn = "粮已不够打下一阵。此时出战即城破。"
	elif rounds_left == 1 and fought < GameState.SIEGE_ROUNDS_MAX - 1:
		warn = "粮只够再打一阵。要守满三阵，还得屯粮。"
	if warn != "":
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		row.add_child(_seal_mark("急"))
		var wl := _band_line(row, warn, UiTheme.CINNABAR if rounds_left < 1 else UiTheme.HONEY, 16)
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for fac in _siege_cards():
		if str(fac.get("id", "")) == CARD_SIEGE_NUNNERY:
			_band_line(col, "%s：%s。这件事没有选项。" % [str(fac.get("title", "福州尼寺")), str(fac.get("subtitle", ""))], UiTheme.TEXT_DIM, 16)
	return slip


## 一枚朱砂小印（方 26，马善政印面字）：代替告警前的「⚠」
func _seal_mark(ch: String) -> Control:
	var seal := PanelContainer.new()
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.custom_minimum_size = Vector2(26, 26)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.SEAL if UiTheme.IS_JUANBEN else UiTheme.CINNABAR
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 2
	seal.add_theme_stylebox_override("panel", box)
	var l := Label.new()
	l.text = ch
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UiTheme.SEAL_TEXT)
	seal.add_child(l)
	return seal


## 小数目写中文（零 至 九十九）：册页、城防账等上屏文字用，钱数这类账目仍写阿拉伯数字
func _cn_num(n: int, liang := false) -> String:
	return GameManager.cn_num(n, liang)



func _show_notice_dialog(title: String, head: String, text: String, ending: String = "") -> void:
	if ending != "":
		GameState.finish(ending, text)
	# 云端 7f92 起主场景不再弹系统对话框；本地 main 的终局通知改走同一张居中册页（ChapterSheet），
	# 「记下这一纲」后回到当前场景（终局后港口页由 _setup_ended_port 接管）。
	# ending 随 res 交给册页：有结局过场先演过场，册页弹出时再换结算底图（ENDING_BG）。
	var shown_head := head if title == "" else "%s　%s" % [title, head]
	_show_chapter_dialog({"title": shown_head, "text": text, "resolved": true, "scene": "", "ending": ending})


## 上报发现：航中勘见的东西要回衙门报了才换得赏格与名声

func _siege_active() -> bool:
	if not (current_scene_id in ["xinghua", "xinghua_harbor"]):
		return false
	if not GameState.has_flag("renamed_wenlong"):
		return false
	if Economy.war_status("xinghua") != "besieged":
		return false
	GameState.siege_begin()
	return true



func _siege_buy_grain() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・市场"
	body_text.text = "牙行闭着，只有米在动。价一天一个样。
粮就是守城的日子：每打一阵，耗粮 %d。" % GameState.SIEGE_GRAIN_PER_ROUND

	# 围城米价：随已打轮次上涨
	var unit: int = 12 + GameState.siege_get("round") * 8
	for n in [40, 120]:
		var cost: int = n * unit
		var b := Button.new()
		b.text = "屯粮 %d（%d 钱・每石 %d）" % [n, cost, unit]
		b.disabled = GameState.money < cost
		b.pressed.connect(func():
			if GameState.spend_money(cost):
				GameState.siege_add("grain", n)
				log_msg("买进粮 %d。米价一天一个样，明日只会更贵。" % n)
			load_scene(current_scene_id)
		)
		choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button("xinghua")



func _siege_cards() -> Array:
	var out := []
	out.append({"id": CARD_SIEGE_MUSTER, "title": "衙门", "subtitle": "募兵・石手军"})
	out.append({"id": CARD_SIEGE_GRAIN, "title": "市场", "subtitle": "屯粮（粮即守城日）"})
	out.append({"id": CARD_SIEGE_WALL, "title": "船屋", "subtitle": "把修船的料改修城墙"})
	if not (GameState.siege.get("envoy_wang", false) and GameState.siege.get("envoy_kin", false)):
		out.append({"id": CARD_SIEGE_ENVOY, "title": "酒馆", "subtitle": "城下有使者求见"})
	var short_of_grain: bool = GameState.siege_get("grain") < GameState.SIEGE_GRAIN_PER_ROUND
	out.append({
		"id": CARD_SIEGE_NANGSHAN, "title": "囊山",
		"subtitle": "粮尽・出战即城破" if short_of_grain else "设伏迎敌・第%s阵" % _cn_num(GameState.siege_get("round") + 1),
	})
	out.append({"id": CARD_SIEGE_NUNNERY, "title": "福州尼寺", "subtitle": "母亲与璥儿在那里"})
	return out



func _siege_envoy() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・城下使者"

	if not GameState.siege.get("envoy_wang", false):
		body_text.text = "福州知军王刚中派了两个使者来，带着一封劝降书。正使在城下念。念到第三句时，你让人开了城门。"
		var kill := Button.new()
		kill.text = "斩正使，放副使回去，带一封信给王刚中"
		kill.pressed.connect(func():
			GameState.siege_set("envoy_wang", true)
			GameState.siege_add("morale", 10)
			GameState.fame += 5
			GameState.add_ledger_note("斩王刚中使")
			log_msg("信只有一句：「世强、刚中负国，文龙不负。」副使走的时候没敢回头。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(kill)
		var keep := Button.new()
		keep.text = "收下书信，不回话"
		keep.pressed.connect(func():
			GameState.siege_set("envoy_wang", true)
			GameState.siege_add("morale", -8)
			GameState.scholar_tendency -= 3
			GameState.set_flag("hesitated_once")
			log_msg("书信放在案上三天。第三天你把它烧了。城里有人看见你收信，也有人看见你烧信。两种人都在。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(keep)
	elif not GameState.siege.get("envoy_kin", false):
		body_text.text = "第二封劝降书是你的姻家送来的。他跪在城下，说福州那边答应了：只要你出城，老夫人和璥儿当天放回。
城头上有人在看你。"
		var burn := Button.new()
		burn.text = "焚书，斩使"
		burn.pressed.connect(func():
			GameState.siege_set("envoy_kin", true)
			GameState.siege_add("morale", 12)
			GameState.fame += 8
			GameState.hometown_tendency -= 5
			GameState.add_ledger_note("焚姻家书")
			log_msg("火盆里那封信烧得很快。城头上没有人说话。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(burn)
		var spare := Button.new()
		spare.text = "焚书，放他走"
		spare.pressed.connect(func():
			GameState.siege_set("envoy_kin", true)
			GameState.siege_add("morale", 6)
			GameState.fame += 4
			GameState.add_ledger_note("焚姻家书")
			log_msg("信烧了，人放了。他走出三十步又回头看了一眼，你没有再看他。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(spare)
	else:
		body_text.text = "城下没有人了。"

	choices_label.visible = true
	_add_leave_button("xinghua")


## 囊山设伏：数值判定，最多三阵。粮尽或三阵毕即城破。

func _siege_fall(reason: String) -> void:
	var betrayal := ""
	if GameState.has_flag("cao_opened"):
		betrayal = "通判曹澄孙开了东门。"
	elif GameState.has_flag("lin_hua_reminded"):
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。他在城下抬头看了你一眼，很快低下去。那个结松了。"
	else:
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。"

	var text := "%s（%s）
城破的时候你在城楼上。白布还挂着。

他们没有动手，把你和家人押去了福州。董文炳的军帐里点着很多灯。他们让你跪，你不跪。有人来扯你的胳膊，有人骂，有人试着往你脸上打。

你用手指着自己的肚子：「此皆节义文章也。可相逼邪？」

从兴化出来那天起，你就没有吃东西。合沙渡口，你要了纸笔——

斗垒孤危势不支，书生守志定难移。
自经沟渎非吾事，臣死封疆是此时。
须信累囚堪衅鼓，未闻烈士竖降旗。
一门百指沦胥尽，唯有丹衷天地知。

杭州是正月到的。你说想去一个地方，他们允了。西湖边，岳飞的庙，庙门前的石阶有二十几级。你走到第十几级的时候，腿停了。
不是跌倒。是坐下来，然后靠着石阶。

福州的尼寺里，老夫人听完杭州的消息，很久没有说话。然后说：「吾与吾儿同死，又何恨哉。」
寺里的人后来说：有斯母，宜有是儿。

——
一百多年后，福州台江，泗洲。江边起了一座庙，匾上四个字：水部尚书。
渔民不知道尚书是什么官。他们只知道出海前拜一拜，海上会平安。
官船出洋，头号船请妈祖，二号船请尚书公。

供在里面的那个人，一辈子没出过海。" % [betrayal, reason]

	GameState.siege = {}
	_show_notice_dialog("忠肃", "兴化・景炎元年十二月", text, "忠肃")


## 士人线错过守城：1276 年兴化陷落时你不在城里。
## 这不是漏判，是这一局的答案——所以它必须有结局，而不是让陈文龙继续跑商到老。

func _siege_lin_hua() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・城头"
	var known := "lin_hua" in GameState.crew_history
	body_text.text = "部将林华上来请命：「大人，元兵在江口。我带五十人出去看看虚实。」"
	if known:
		body_text.text += "

你认得这张脸。二十年前他在林阿舶的船上系过缆，缆绳系得很好。"

	if known:
		var remind := Button.new()
		remind.text = "「你的缆绳系得好。你系的结，从来不松。」让他去"
		remind.pressed.connect(func():
			GameState.siege_set("lin_hua_sent", true)
			GameState.siege_add("morale", 5)
			GameState.set_flag("lin_hua_reminded")
			log_msg("他愣了一下，说大人还记得。城里人看见你认得出一个水手的名字，士气 +5。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(remind)

	var go := Button.new()
	go.text = "让他去"
	go.pressed.connect(func():
		GameState.siege_set("lin_hua_sent", true)
		log_msg("林华带着五十人出了北门。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(go)

	var stay := Button.new()
	stay.text = "不去。关城门，谁也不出"
	stay.pressed.connect(func():
		GameState.siege_set("lin_hua_sent", true)
		GameState.siege_add("grain", -30)
		GameState.set_flag("cao_opened")
		log_msg("城门关了七天。第八天夜里，通判曹澄孙开了东门。他后来说，是城里的人求他开的。这话可能是真的。")
		load_scene(current_scene_id)
	)
	choices_container.add_child(stay)

	choices_label.visible = true
	_add_leave_button("xinghua")


## 城破 → 甲线结局「忠肃」

func _siege_muster() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・衙门"
	body_text.text = "案上摊着户籍。能拿动东西的都登了记，登完还是不满千。"

	var cap := GameState.siege_troop_cap()
	var room := cap - GameState.siege_get("troops")
	if room > 0:
		for n in [50, 200]:
			var take: int = mini(n, room)
			if take <= 0:
				continue
			var cost: int = take * GameState.SIEGE_TROOP_COST
			var b := Button.new()
			b.text = "募兵 %d 人（%d 钱）" % [take, cost]
			b.disabled = GameState.money < cost
			b.pressed.connect(func():
				if GameState.spend_money(cost):
					GameState.siege_add("troops", take)
					log_msg("募得 %d 人。倾家所有，招的是义兵，不是官军。" % take)
				load_scene(current_scene_id)
			)
			choices_container.add_child(b)
	else:
		var l := Label.new()
		l.text = "名声所及，能招的都招了。城中兵不满千。"
		choices_container.add_child(l)

	# 石手军一次性抉择
	if str(GameState.siege.get("shishou", "")) == "":
		var sep := Label.new()
		sep.text = "── 石手军 ──"
		sep.add_theme_font_size_override("font_size", 13)
		choices_container.add_child(sep)
		var info := Label.new()
		info.text = "两百个能把石头掷中人头的乡兵站在木兰陂上。朝廷议者说「不足用」，把他们裁了。他们说：不是反朝廷，是朝廷不要我们。"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
		choices_container.add_child(info)

		var keep := Button.new()
		keep.text = "重编石手军，归你麾下（兵 +200，囊山战力 ×1.5）"
		keep.pressed.connect(func():
			GameState.siege_set("shishou", "kept")
			GameState.siege_add("troops", 200)
			GameState.siege_add("morale", 8)
			GameState.hometown_tendency += 5
			log_msg("他们把石头放下了，没有走。以后五个月，城头上多了两百个不领饷的人。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(keep)

		var disband := Button.new()
		disband.text = "按律解散，不追究"
		disband.pressed.connect(func():
			GameState.siege_set("shishou", "disbanded")
			GameState.scholar_tendency += 2
			log_msg("他们把石头放下了，走了。有些人后来在囊山又出现过一次，不是站在你这边。")
			load_scene(current_scene_id)
		)
		choices_container.add_child(disband)

	choices_label.visible = true
	_add_leave_button("xinghua")



func _siege_nangshan() -> void:
	if GameState.siege_get("grain") < GameState.SIEGE_GRAIN_PER_ROUND:
		_siege_fall("粮尽")
		return

	var rd := GameState.siege_get("round") + 1

	# 第三阵前的林华事件
	if rd == GameState.SIEGE_ROUNDS_MAX and not GameState.siege.get("lin_hua_sent", false):
		_siege_lin_hua()
		return

	GameState.siege_set("round", rd)
	GameState.set_flag("siege_fought")
	GameState.siege_add("grain", -GameState.SIEGE_GRAIN_PER_ROUND)

	var power := GameState.siege_power()
	var enemy := randf_range(600.0, 1400.0) * (1.0 + 0.25 * (rd - 1))
	var won := power >= enemy

	var txt := ""
	if won:
		GameState.siege_add("morale", 8)
		GameState.fame += 4
		var killed: int = int(GameState.siege_get("troops") * 0.08)
		GameState.siege_add("troops", -killed)
		txt = "山道两边全是石头。%s元兵退了。
城里有人开始说：也许能守。

折损 %d 人。" % [
			"石手军在山上，石头落下去的时候不用弓。" if str(GameState.siege.get("shishou", "")) == "kept" else "",
			killed,
		]
	else:
		GameState.siege_add("morale", -12)
		var killed2: int = int(GameState.siege_get("troops") * 0.22)
		GameState.siege_add("troops", -killed2)
		GameState.siege_add("wall", -20)
		txt = "伏没设成。元兵从背面上了山脊，石头砸下去砸的是自己人。
退回城里的时候少了 %d 人。" % killed2

	if GameState.siege_get("round") >= GameState.SIEGE_ROUNDS_MAX:
		_show_notice_dialog("囊山・第 %d 阵" % rd, "囊山" if won else "囊山失利", txt + "

粮快尽了。这是最后一阵。")
		_siege_fall("三阵毕")
		return

	_show_notice_dialog("囊山・第 %d 阵" % rd, "囊山" if won else "囊山失利", txt)


## 部将林华请出侦。史实不变——他仍然降。

func _siege_repair_wall() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・船屋"
	body_text.text = "船料还剩一些。修船是为了走，修墙是为了不走。"

	var room: int = GameState.siege_wall_room()
	if room <= 0:
		var done := Label.new()
		done.text = "城墙已加到 %d——再堆料也无非是墙。守城守的是人。" % GameState.SIEGE_WALL_MAX
		done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		done.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
		choices_container.add_child(done)
	else:
		for n in [20, 60]:
			var add: int = mini(n, room)
			if add <= 0:
				continue
			var cost: int = add * 15
			var b := Button.new()
			b.text = "加固城墙　加 %d（%d 钱・上限 %d）" % [add, cost, GameState.SIEGE_WALL_MAX]
			b.disabled = GameState.money < cost
			b.pressed.connect(func():
				if GameState.spend_money(cost):
					GameState.siege_add("wall", add)
					log_msg("把修船的料改了修墙。木匠没问为什么。")
				load_scene(current_scene_id)
			)
			choices_container.add_child(b)

	choices_label.visible = true
	_add_leave_button("xinghua")


## 两封劝降书，各一次

func _special_cards() -> Array:
	var out := []
	# 涵江海口 → 旧避风澳：1277 年二三月陈瓒复兴化的那四十天，且第一章复核过旧泊地
	if current_scene_id in ["xinghua", "xinghua_harbor"] \
			and Calendar.year == 1277 and Calendar.month in [2, 3] \
			and Economy.war_status("xinghua") == "loyal" \
			and not GameState.has_flag("renamed_wenlong") \
			and GameState.has_found("nameless_shelter_bay") \
			and not GameState.has_flag("ending_root_sea"):
		out.append({"id": CARD_HANJIANG, "title": "涵江海口", "subtitle": "带族人走旧避风澳"})

	# 士人线：辞呈已批，出不出国门（1275-12 起，未决则一直挂着）
	if GameState.has_flag("vice_councillor") and not _resign_decided():
		out.append({"id": CARD_RESIGN, "title": "临安・辞呈批语", "subtitle": "依奏。车已备在门外"})

	# 海商线：崖山（1279 正月至三月，须在广州）
	if current_scene_id == "guangzhou" and GameState.identity == "merchant" \
			and Calendar.year == 1279 and Calendar.month <= 3:
		out.append({"id": CARD_YASHAN, "title": "崖山", "subtitle": "宋军的船连成一片"})

	# 海商线收官：1285 年后，一局跑到底（乡土线同样收在这里）
	if GameState.identity != "scholar" and Calendar.year >= 1285:
		out.append({"id": CARD_GANGSHOU, "title": "市舶司・新册", "subtitle": "封面换了，名字还在"})

	return out



