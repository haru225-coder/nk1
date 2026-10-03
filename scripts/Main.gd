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
## 船屋升级 / 修船 / 购船过场未落时挡住二次点按（会话内 UI 状态，不入存档）
var _upgrade_busy := false
## 账条暂时写入的容器。酒馆募人收进内滚，离开钮留在外面。
var _slip_host: Node = null
var _ledger_layer: Control
var _status_strip: PanelContainer
var _status_line: RichTextLabel
var _status_note: Label
## 船籍簿记事：最近 LOG_KEEP 条（会话内，不入存档）。原先整串无限拼接，空时是一块空墨框
var _log_lines: PackedStringArray = PackedStringArray()
const LOG_KEEP := 8
## 月初通告连着进来、多到要把下面那句（候一日之类的结果句）顶出 LOG_KEEP 时，整串收成一行（lane fx7）；
## 折叠的写法与海图船况札记共用 scripts/core/LogFold.gd（lane w19-g9），下面四个字段的口径见那边头注。会话内，不入存档
var _log_folds: Dictionary = {}
var _log_fold_open := ""
var _notice_run := 0
var _notice_when: Array = []
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
## 本次册页是否晋升（非了结/结局）。UI 态，不入存档；确认「承此一路」时走翻页题签。
var _chapter_advanced := false
## 本次晋升跳年数（展示题签用）；确认后清零。不改 skip_years 数值。
var _chapter_years := 0
## 今日岸上开着的去处。再候一日之前这一手不变。
var shore_hand: PackedStringArray = PackedStringArray()
var _shore_facilities: Array = []
## 本港的设施表（进港时从场景数据记下；守城 / 终局页不用它，「再候一日」回寻常岸带时要用）
var _port_scene_facilities: Array = []
## 岸带页型：port 寻常 / siege 兴化守城 / ended 终局后港口。UI 状态，不入存档。
var _shore_mode := "port"
## 守城 / 终局岸带的纪实题签本会话已演过哪几种（siege / ended）：只首次进岸带时演一次，「再候一日」、
## 进出设施、重读结局都不重播。UI 状态，不入存档；headless 下 play_transition 当帧直通。
var _shore_title_seen := {}
## 今日柜上的三样货。明日再看之前这一手不变。
var broker_hand: PackedStringArray = PackedStringArray()

## 过场接线（cinematics 线）：开场 / 章节卡 / 结局过场 / 抵港横幅 / 活背景 / 标题演出。
## headless（门禁）下全部旁路：Cinematics.live() 为假，当帧照原逻辑走，不延迟。会话状态在 Cinematics 静态变量里，不进存档。
const _CINE := preload("res://scripts/cutscene/Cinematics.gd")
## 港口节拍（E-10 / G1014，lane w20-c2）：进港节拍演出账。开关 nk1/port_beats_runtime 关 = 留档不读
const _BEATS := preload("res://scripts/core/PortBeats.gd")
const _CS_PLAYER := preload("res://scripts/cutscene/CutscenePlayer.gd")
const _CS_CARD := preload("res://scripts/cutscene/ChapterCard.gd")
const _CS_BANNER := preload("res://scripts/cutscene/PortBanner.gd")
const _CS_BACKDROP := preload("res://scripts/cutscene/LivingBackdrop.gd")
const _TITLE_STAGE := preload("res://scripts/cutscene/TitleStage.gd")
## 工席成功态的短过渡（淡入墨幕 + 题签 + 淡出），见 play_transition
const _UI_TRANSITION := preload("res://scripts/ui/UiTransition.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
## 工席纸条小件（卡身 / 题签 / 旁注 / 钮行 / chip）；Main 里 _slip_* 同名转发到这里
const _SLIP := preload("res://scripts/ui/SlipKit.gd")
## 船籍簿整页（顶上状态匾 + 浮层 + 正文 / 记事栏）的实现在 scripts/ui/LedgerPage.gd（Lane mz 第二刀拆出）；
## 这里的 _dress_ledger / _mount_status_strip / _lift_ledger / _show_strip / _toggle_ledger / _close_ledger /
## _on_ledger_dim_input / _refresh_strip / _render_log / update_status_panel / _roster_head / _set_status_text /
## _append_progress_line 都是同名同签名一行转发，调用点与信号目标不变。
const _LEDGER := preload("res://scripts/ui/LedgerPage.gd")
## 升章 / 了结册页（晋升摘要 + 跳年代价 + 翻页题签、了结 / 结局册页、册页前过场、正文估高）的实现在 scripts/ui/ChapterSheet.gd
## （Lane ms2 第三刀拆出）；这里的 _era_summary_lines / _show_chapter_dialog / _chapter_body_height / _cinema_before_sheet /
## _ending_cinema_key / _confirm_chapter_sheet 都是同名同签名一行转发，调用点与信号目标不变。
const _CHAPTER := preload("res://scripts/ui/ChapterSheet.gd")
## 酒馆 / 旅店页（酒馆工席、旧事挑签、募人人物卡、人物卡小件、旅店歇息）的实现在 scripts/ui/TavernPage.gd
## （Lane main4 第四刀拆出）；这里的 _setup_tavern / _setup_story_hooks / _on_story_hook / _on_gather_intel / _setup_hiring /
## _person_slip / _person_foot / _seal_chip / _setup_inn 都是同名同签名一行转发，调用点与信号目标不变。
const _TAVERN := preload("res://scripts/ui/TavernPage.gd")
## 见面页（_ready 装的见面册页版面、设施页「在侧」人物卡与「见」钮、见面页本身与打听 / 疏通 / 离开回调）的实现在
## scripts/ui/NpcPage.gd（Lane main5 第五刀拆出）；这里的 _frame_portrait / _dress_npc_sheet / _mount_npc_profile / _fill_npc_profile /
## _add_npc_button / _on_meet_npc / _show_npc_mode / _set_npc_speech / _on_npc_intel / _on_npc_bribe / _on_npc_leave 都是同名同签名
## 一行转发，调用点与信号目标不变；招呼常量 NPC_GREETING 随簇搬走。
const _NPC := preload("res://scripts/ui/NpcPage.gd")
## 航海日志册页（三卷工席 + 合上、暗幕点下即合、港名匾让开、记录 / 翻阅两个回调）的实现在 scripts/ui/SaveSheet.gd
## （Lane main6 第六刀拆出）；Main 保留同名一行转发，调用点与信号目标不变，状态 _save_host 仍在这里。
const _SAVE := preload("res://scripts/ui/SaveSheet.gd")
## 行会 / 贡院页（行会行情抄本 + 会籍 / 入行工席与入行回调、贡院誊录 / 赴试工席与两个回调）的实现在 scripts/ui/GuildExamPage.gd
## （Lane main7 第七刀拆出）；这里的 _guild_port_id / _setup_guild / _add_guild_join_slip / _guild_join_block / _on_guild_join / _setup_exam /
## _exam_slip / _on_exam_copy / _exam_sat_flag / _on_exam_sit 都是同名同签名一行转发，调用点与信号目标不变；GUILD_* / EXAM_* 常量与
## play_transition 仍在这里。
const _GUILD := preload("res://scripts/ui/GuildExamPage.gd")
## 市舶司页（货引 / 抽解 / 违禁 / 蒲家留意工席与请领回调、未呈报发现的「呈报」工席与呈报回调、职衔与修埠工席和投钱回调、蒲家留意档位）
## 的实现在 scripts/ui/MaritimeOfficePage.gd（Lane main8 第八刀拆出）；这里的 _setup_yamen / _on_apply_permit / _setup_reporting /
## _on_report_discovery / _setup_title_and_invest / _on_invest_port / _attention_desc 都是同名同签名一行转发，调用点与信号目标不变；
## _setup_quanzhou_standoff、_duty_per_hundred 仍在这里。
const _MARITIME := preload("res://scripts/ui/MaritimeOfficePage.gd")
## 住处 / 寺观页（住处边记 / 歇息工席、寺观近侧旧迹工席与细看 / 拓碑回调、拓记字样小件、玉湖陈宅）的实现在 scripts/ui/ResidencePage.gd
## （Lane main9 第九刀拆出；玉湖陈宅 _setup_residence_chen 是 lane w20-a9 第十三刀二追加搬入）；这里的 _setup_residence / _setup_temple /
## _setup_residence_chen / _temple_rub_note / _has_temple_rub / _on_temple_look / _on_temple_rub 都是同名同签名一行转发，调用点与信号目标不变；
## HOME_RATE / TEMPLE_* / CHEN_ZAN_* 常量、_on_rest 仍在这里。
const _RESIDENCE := preload("res://scripts/ui/ResidencePage.gd")
## 船屋页（坞位 / 补给 / 蕃商赊贷 / 坞外待售四张工席与各钮回调、船屋成功题签，外加酒馆「雇入」「辞退」两支回调）的实现在
## scripts/ui/ShipyardPage.gd（Lane main10 第十刀拆出）；这里的 _yard_port_name / _yard_success_transition / _setup_shipyard / _yard_offer /
## _on_berth_switch / _on_repair_hull / _on_hire_to_min / _on_borrow / _on_repay / _on_buy_ship / _on_dismiss_crew / _on_hire_candidate /
## _on_hire_crew / _on_upgrade / _on_buy_supplies 都是同名同签名一行转发，调用点与信号目标不变；_upgrade_busy、_fit_rank /
## _sail_fit_phrase / _armor_fit_phrase 仍在这里。
const _YARD := preload("res://scripts/ui/ShipyardPage.gd")
## 标题页 / 开场（卷首标题页与四方沙盘的版面、「开卷 / 翻页」路由与序章题签、三个副钮显隐、开场过场起播与演完重演标题演出）的实现在
## scripts/ui/TitlePage.gd（Lane main11 第十一刀拆出）；这里的 _play_opening / _on_opening_finished / _on_rewatch_opening /
## _setup_title_mode / _on_start_game_pressed 都是同名同签名一行转发，调用点与信号目标不变；start_game、title_button_connected 仍在这里。
const _TITLE := preload("res://scripts/ui/TitlePage.gd")
## 调试钩子（F11 跳港、F12 预览了结册页）的实现在 scripts/ui/DebugHooks.gd（Lane main12 第十二刀拆出）；这里的 _debug_jump_port /
## _debug_preview_ending 都是同名同签名一行转发，F11 / F12 键位判断仍在 _unhandled_input。
const _DEBUG := preload("res://scripts/ui/DebugHooks.gd")
## 浮页（人物志 / 名册 / 伙伴草案预览 / 市舶纪事）的实现在 scripts/ui/FloatPages.gd（Lane w21-d20 第十四刀拆出）；这里的
## _open_codex … _close_vision_stage 八支都是同名同签名一行转发，四个浮页句柄仍在这里。
const _FLOAT_PAGES := preload("res://scripts/ui/FloatPages.gd")
## 活背景幅度：比引擎默认再收一档（正文底下的画不能晃得人头晕）
const BACKDROP_OPTS := {"breath": 0.018, "period": 52.0, "pan": 0.35, "vignette": 0.26, "grain": 0.028}
## 本次 load_scene 是海图回港的真正抵港：_on_enter_port 据此出横幅（读档、设施间来回为假）
var _arrival_banner := false
## 本局节拍演出账（入档在 GameState.beats_seen）。开关关掉时本表留空、行为照旧
var _beats = null
## 本次进港排的岸带页型（port / siege / ended，_build_shore 当帧定）：守城 / 终局页不出太平时节的抵港挂签。UI 状态，不入存档
var _shore_kind_now := ""
## 本次进港在排岸带之前就按城破结算了（_settle_siege_before_shore）：_on_enter_port 不再记港、不再出横幅。UI 状态，不入存档
var _siege_fell_on_entry := false
## 起始标题页的「重看开场」
var _rewatch_button: Button
## 起始标题页的「续卷」（有存档才显示）
var _resume_button: Button

## 人物系统（characters 线）：立绘 / 五维 / 特技 / 人物志。只作展示，不入存档
const _CHAR_ART := preload("res://scripts/ui/CharacterArt.gd")
const _CODEX := preload("res://scripts/ui/CharacterCodex.gd")
## chars 线薄接入：岸上「名册」浮页（CharRoster + CharPortraitPanel）
const _CHARS_WIRE := preload("res://scripts/chars/CharsShoreOverlay.gd")
## Lane N：接舷题签岸上预览（调试 F9；真实路径仍是海图遇盗→WorldMap 按 G）
const _COMBAT_SHORE := preload("res://scripts/combat/CombatShoreHook.gd")
## Lane L：市舶纪事册页薄接入（岸带「市舶纪事」/ 调试 F8；叠层，不入存档）
const _VISION_STAGE := preload("res://scenes/vision/VisionStage.tscn")
## Lane Q：酒馆墙上市井札薄（宣纸条；无新闻不上墙）
const _TAVERN_NEWS_WALL := preload("res://scripts/ui/TavernNewsWall.gd")
## Lane Z3：伙伴草案预览浮页（调试 F7；只读剪影卡，不接招募）
const _COMPANION_PREVIEW := preload("res://scripts/companions/CompanionPreview.gd")
## 酒馆人物卡上的小立绘（逻辑像素，4:5）
const HIRE_PIC := Vector2i(84, 105)
## 船籍簿职事列表的小头像
const ROSTER_HEAD := 24
var _codex: Control
var _chars_wire: Control
var _vision_stage: Control
var _companion_preview: Control
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
	{"id": "city_shipyard", "title": "船屋", "subtitle": "修舱・上水・雇手"},
	{"id": "city_guild", "title": "行会", "subtitle": "议价・立籍"},
	{"id": "city_tavern", "title": "酒馆", "subtitle": "闻讯・募人"},
	{"id": "city_market", "title": "牙行", "subtitle": "过秤・买卖"},
	{"id": "city_inn", "title": "旅店", "subtitle": "歇息・候风"},
	{"id": "city_exam", "title": "贡院", "subtitle": "誊录・观礼"},
	{"id": "city_residence", "title": "住宅", "subtitle": "账本・歇息"},
	{"id": "city_temple", "title": "寺观", "subtitle": "勘见・拓碑"},
	{"id": "city_yamen", "title": "市舶司", "subtitle": "验引・抽解"},
]

## 岸门悬停提示：论文纪实短注，不写「点击进入」类 UI 腔。key 去 city_ 前缀。
const DOOR_TIP := {
	# 买价已含市舶抽解（同页脚注「含抽解・扣佣」）；出港验引另按舱货纳一次（GameState.customs_duty）
	"market": "牙人过秤开票。买价含抽解，出港验引另纳。",
	"guild": "会馆议价、立会籍。入行另有会费。",
	"tavern": "酒桌边听市井动静，也可雇水手。",
	"shipyard": "坞上修舱、上水、雇手。船开不出去时必开此门。",
	"inn": "借宿候风。日数照过。",
	"exam": "贡院誊录与观礼。兴化、泉州可赴试。",
	"residence": "下处歇息，翻看账册。",
	"temple": "寺观细看遗迹，可拓碑。",
	"yamen": "市舶司验引、抽解。违禁货过不了关。",
	"siege_muster": "衙门募兵。石手军听调。",
	"siege_grain": "市集屯粮。粮即守城日。",
	"siege_wall": "船屋料改修城墙。",
	"siege_envoy": "城下使者求见。",
	"siege_nangshan": "南山下设伏。",
	"siege_nunnery": "福州尼寺。母亲与璥儿在那里。",
	"special_hanjiang_escape": "涵江海口旧避风澳。",
	"special_resign_1275": "临安辞呈批语。",
	"special_yashan": "崖山。宋军船阵相连。",
	"special_gangshou_end": "市舶司新册。封面换了，名字还在。",
}


func _ready() -> void:
	UiTheme.apply(self)
	_mount_veil()
	# 活背景：呼吸推拉 + 暗角 + 细颗粒；顺带把过场 / 章节卡 / 横幅的 shader 管线预热掉。headless 下不做事
	_CS_BACKDROP.attach(background, BACKDROP_OPTS)
	_inset_stage()
	message_label.text = ""
	status_label.bbcode_enabled = true
	message_label.bbcode_enabled = true
	message_label.meta_clicked.connect(_on_log_meta)
	scene_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_text.fit_content = true
	body_text.scroll_active = false
	body_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 防御：异常路径可能残留未清理的海战上下文，回港时清空
	GameManager.pending_battle = {}
	GameManager.monthly_notice.connect(_on_monthly_notice)
	SaveLoad.stale_notice.connect(_on_stale_notice)
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
	_LEDGER.dress(self)


func _mount_status_strip() -> void:
	_LEDGER.mount_strip(self)


func _lift_ledger() -> void:
	_LEDGER.lift(self)


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
	_LEDGER.show_strip(self, show)


func _toggle_ledger() -> void:
	_LEDGER.toggle(self)


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
	_LEDGER.close(self)


func _on_ledger_dim_input(event: InputEvent) -> void:
	_LEDGER.on_dim_input(self, event)


func _monsoon_short() -> String:
	var desc := Calendar.get_monsoon_desc()
	if desc.begins_with("东北"):
		return "东北风"
	if desc.begins_with("西南"):
		return "西南风"
	return "转换期"


## 状态条那一格：记事最上那条；折起的一串仍取其中最上那则（与没折时同一则，LogFold.latest）
func _latest_log() -> String:
	return LogFold.latest(self)


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
	# 章目全部走完 = 下一回入港即开章 / 了结：终章报「终章・可了结」，非终章留空。
	# 不在这里回 chapters.json 的 hint——那句是本章「要办哪几件」的总述，全办完了再上顶匾
	# 就成了催玩家去办已办完的事（泉州节拍抢在开章之前演时顶匾正是这一支），终章还会被它
	# 盖掉「终章・可了结」（lane w53-12 审计 b68de41）。hint 要给玩家看，得放在章目还没走完时
	# 看得到的地方（船籍簿章节段 / 顶匾悬停）——落点待拍板；tools/qa_w53_4_chapter_hint_probe.gd
	# 钉着这一支不回 hint。
	if prog.get("final", false):
		return "终章・可了结"
	return ""


func _refresh_strip() -> void:
	_LEDGER.refresh_strip(self)


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
	_NPC.frame_portrait(self)


func _dress_npc_sheet() -> void:
	_NPC.dress_npc_sheet(self)


func _mount_npc_profile(dialog: Node) -> void:
	_NPC.mount_npc_profile(self, dialog)


func _fill_npc_profile(ch: Dictionary) -> void:
	_NPC.fill_npc_profile(self, ch)


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
		# 上边留 18（lane fx4，原 8）：面板泥金内线在上沿下约 12px，28px 题头字顶原先压在线上，现离线约 7px；多出的 10px 由题头金线收窄抵回（Main.tscn 该 HSeparator separation 6）：滚动区少 10px、内页同少 10px，各页溢出量与原先相同。
		# 底边留 22：面板泥金内线在内容区里约 10px 处，页脚的离开 / 明日再看要离开它与框饰 ≥12（第 1 轮评审 M3），滚动区少 14px。
		sheet_margin.add_theme_constant_override("margin_top", 18)
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
	LogFold.push_notice(self, UiTheme.plain_log(text), LOG_KEEP, LOG_KEEP)
	_render_log()
	_refresh_strip()
	update_status_panel()


## 读档勾稽的一声（lane w25-j3）：旧卷里没法再往本版名册图籍对上的口径（港 / 船式 / 勘见 / 名姓 / 行年）
## 由 SaveLoad.stale_notice 一线递来；只用 log_msg，与「翻开日志……」同格。未落空不出（SaveLoad 已拦）。
func _on_stale_notice(line: String, slot: int) -> void:
	log_msg("第 %d 卷%s" % [slot, line])


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
	_TITLE.play_opening(self, from_black)


## 开场演完（此刻全黑）：还停在标题页就把标题演出从头再来，黑幕退去时正好看见题名写出、印落下
func _on_opening_finished() -> void:
	_TITLE.on_opening_finished(self)


func _on_rewatch_opening() -> void:
	_TITLE.on_rewatch_opening(self)


## 人物志：一层浮页盖在当前画面上（港口页底、标题页进）。focus_id 非空直接开此人详页。不入存档。
func _open_codex(focus_id := "") -> void:
	_FLOAT_PAGES.open_codex(self, focus_id)


## chars 线：岸上名册浮页（CharRoster + CharPortraitPanel）。与人物志互斥；不入存档。
func _open_chars_wire(focus_id := "") -> void:
	_FLOAT_PAGES.open_chars_wire(self, focus_id)


func _close_chars_wire() -> void:
	_FLOAT_PAGES.close_chars_wire(self)


## Lane Z3：伙伴草案预览浮页（只读剪影六卡）。F7 开关；不入存档、不接招募。
func _toggle_companion_preview() -> void:
	_FLOAT_PAGES.toggle_companion_preview(self)


func _open_companion_preview() -> void:
	_FLOAT_PAGES.open_companion_preview(self)


func _close_companion_preview() -> void:
	_FLOAT_PAGES.close_companion_preview(self)


## Lane L：叠一层 VisionStage（立像裱框 + 海战定格）。B/Esc 合上；不入存档、不过日子。
func _open_vision_stage() -> void:
	_FLOAT_PAGES.open_vision_stage(self)


func _close_vision_stage() -> void:
	_FLOAT_PAGES.close_vision_stage(self)


func log_msg(text: String) -> void:
	LogFold.push_line(self, UiTheme.plain_log(text), LOG_KEEP)
	_render_log()
	_refresh_strip()


func _render_log() -> void:
	_LEDGER.render_log(self)


## 记事栏里点折起的月初通告那一行（或点开后按月分组的某月）：就地展开 / 收起（LogFold.toggle）
func _on_log_meta(meta: Variant) -> void:
	if LogFold.toggle(self, meta):
		_render_log()


# ══════════════════════════════════════════════════════
#  状态面板
# ══════════════════════════════════════════════════════

func update_status_panel() -> void:
	_LEDGER.update_panel(self)


## 富文本里的小头像记号（控制符，正文里不会出现）
const HEAD_MARK := "\u0001"


func _roster_head(crew_id: String) -> Texture2D:
	return _LEDGER.roster_head(self, crew_id)


func _set_status_text(t: String, heads: Array) -> void:
	_LEDGER.set_status_text(self, t, heads)


func _append_progress_line(text: String, it: Dictionary) -> String:
	return _LEDGER.append_progress_line(text, it)


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
			return "劣酒与喧哗。邻桌有人压低了声音。"
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
	# 旧档：兴化海口从前也开守城页，在海口开过城防的档读回海口，直接入城（城防没了结，不给带「看风」的寻常港页）
	if scene_id == "xinghua_harbor" and GameState.siege_open() and not GameState.is_ended():
		log_msg(SIEGE_ENTER_LOG)
		scene_id = "xinghua"
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
		# H4：PROLOGUE_PAGE_BG 里登记了、文件也在的页换专属底图；缺图照旧回落这两张，不走 _set_background_file 的海路图兜底
		var page_bg := _prologue_page_bg(scene_id)
		if page_bg != "":
			_set_background_file(page_bg)
		elif type == "title":
			_set_background_file("bg_world_map.jpg")
		else:
			_set_background_file(PROLOGUE_BG)
		if type != "title":
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
		# 节拍幕不论从哪条路演到（抵港节拍 / 上一幕的选项 / 序章一路点下来）都记名，演过的不再重演（lane w53-6）
		_note_beat_scene(scene_id)
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

## H2 港页变体：同港同机位的战况 / 年份 / 季节档，文件名 bg_<港 id>_<后缀>.jpg（港 id 即 ports.json 的 id，不是 PORT_BG 原图名）。
## 找图顺序见 _port_bg：战况（非 loyal）→ 年份 → 季节 → PORT_BG 原图，每档都要文件在才用——图没进库时画面与原图一样，收一张生效一张。
## 守城页就是兴化港页（_siege_active），bg_xinghua_besieged.jpg 进库即生效，不另写代码；这一档只在城防记录开着时取（PORT_STATUS_BG_SIEGE_ONLY）。
## check_assets 查拼写：assets/bg_<港 id>_<后缀>.jpg 的后缀须是非 loyal 战况（Economy.WAR_LABEL）、下面的季节，或本表登记的年份。
## 年份档：取不大于当年的最大一档；年份档压过季节档（博多 1276 年起的防塁档画了石垒，季节图里没有，季节优先会倒退回防塁以前）。
const PORT_YEAR_BG := {"hakata": [1276]}
## 季节按月（和 monsoon 的口径不同）：春 3—4、夏 5—8、秋 9—11、冬 12—2。下标 = 月 - 1
const PORT_SEASON_BY_MONTH := [
	"winter", "winter", "spring", "spring", "summer", "summer",
	"summer", "summer", "autumn", "autumn", "autumn", "winter",
]
## 某港某季借别季的图：博多原图樱花红叶同框，夏季用春版、冬季用秋版
const PORT_SEASON_BORROW := {"hakata": {"summer": "spring", "winter": "autumn"}}
## 门禁注入的「文件在不在」表：设成 Dictionary 时 _port_bg 只认表里的文件名、不查盘（godot_story_check 测找图顺序）；平时为 null
var _port_bg_probe = null
## 只给守城页用的战况档：bg_xinghua_besieged.jpg 画的是 1276 年冬陈文龙守城（城头白布八字）。寻常港页没有题签，
## 别的身份线、1277 秋陈瓒那一围进港看见整匹无字白布会读成降旗，所以城防记录没开时跳过这一档（09-28）
const PORT_STATUS_BG_SIEGE_ONLY := {"xinghua": "besieged"}

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
## H4 序章分页底图：页 id → assets/ 下的文件（可带子目录，_set_background_file 前面拼 res://assets/）。
## 不在表里的页照旧：title 型压 bg_world_map.jpg，其余压 PROLOGUE_BG 并调夜色；在表里而文件缺，也回落这两张（不回落海路图）。
## check_assets 查表值与键，所以一页一行、跟着一张图进，不写指向不存在文件的行。cg_title 不进表：godot_story_check 断言标题屏用 bg_world_map.jpg。
const PROLOGUE_PAGE_BG := {
	# 四方沙盘（title 型）：北、南、西三页借开场过场的现成图
	"cg_world_north": "cutscene/cs_north_mongol.jpg",
	"cg_world_south": "cutscene/cs_south_champa.jpg",
	"cg_world_west": "cutscene/cs_west_caravan.jpg",
	# 以下随 02 批出图一页一行补进来（文件名以扩充包为准），图没进库之前不写：
	#   东方沙盘 cg_world_east ← bg_prologue_world_east.jpg
	#   桌上三物 cg_narrate_table_2 至 _5、cg_wine_shed_2 至 _4（7 页）← bg_prologue_table.jpg
	#   老兵 cg_veteran、cg_veteran_2、_3、_3a、_4、_5、_6（7 页）← bg_prologue_veteran.jpg
	#   阿那 cg_ana_enter、cg_ana_speak、_2、_3（4 页）← bg_prologue_ana.jpg
	#   家丁 cg_servant_enter、cg_servant_speak（2 页）← bg_prologue_servant.jpg
	#   抉择 cg_decision ← bg_prologue_decision.jpg
	#   收束 cg_choice_sea ← bg_prologue_choice_sea.jpg；cg_choice_land ← bg_prologue_choice_land.jpg
	#   cg_narrate_table 首页、cg_wine_shed、cg_wine_shed_5 仍压 PROLOGUE_BG；bg_wine_shed_hd 重画后同名覆盖即生效（09-28 Snow 选重画）
}


## 序章页专属底图（H4）：表里有、文件也在才给，否则 ""（调用方回落酒棚或标题海图）。table 可注入，门禁测缺图回落用
func _prologue_page_bg(scene_id: String, table: Dictionary = PROLOGUE_PAGE_BG) -> String:
	var file := str(table.get(scene_id, ""))
	if file != "" and FileAccess.file_exists("res://assets/" + file):
		return file
	return ""

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
		file = _port_bg(loc)
	_set_background_file(file)


## 港页底图（H2）：战况档（非 loyal）→ 年份档 → 季节档 → PORT_BG 原图，每档文件在才用
func _port_bg(loc: String) -> String:
	var status := Economy.war_status(loc)
	var status_ok := status != "loyal"
	if str(PORT_STATUS_BG_SIEGE_ONLY.get(loc, "")) == status and not GameState.siege_open():
		status_ok = false
	if status_ok and _port_bg_has("bg_%s_%s.jpg" % [loc, status]):
		return "bg_%s_%s.jpg" % [loc, status]
	var year := 0
	for y in PORT_YEAR_BG.get(loc, []):
		if int(y) <= Calendar.year and int(y) > year:
			year = int(y)
	if year > 0 and _port_bg_has("bg_%s_%d.jpg" % [loc, year]):
		return "bg_%s_%d.jpg" % [loc, year]
	var season := str(PORT_SEASON_BY_MONTH[clampi(Calendar.month, 1, 12) - 1])
	season = str(PORT_SEASON_BORROW.get(loc, {}).get(season, season))
	if _port_bg_has("bg_%s_%s.jpg" % [loc, season]):
		return "bg_%s_%s.jpg" % [loc, season]
	return str(PORT_BG.get(loc, FALLBACK_BG))


func _port_bg_has(file_name: String) -> bool:
	if _port_bg_probe is Dictionary:
		return (_port_bg_probe as Dictionary).has(file_name)
	return FileAccess.file_exists("res://assets/" + file_name)


## 岸上候一日可能跨月：战况、季节换了档，港页底图跟着换；同一张不重载，终局页不动
func _refresh_port_bg() -> void:
	if GameState.is_ended() or not PORT_BG.has(current_scene_id):
		return
	var file := _port_bg(current_scene_id)
	if file != _bg_file:
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
	_uncenter_benches()
	_show_investigation_chrome(false)
	scene_title.visible = true
	# 设施页题头统一 SIZE_HEAD，不沿用上一页（序章 cg_ 对白页 24、剧情页 28 会漏到下一张设施页）；
	# 调查页 cg_ 分支在 _setup_investigation_mode 里照旧再覆盖成 24
	scene_title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
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
	var market_open := Economy.is_market_open(port_id)
	body_text.text = "柜上只摆三样。牙人过秤开票；要看别的，明日再来。"

	var goods_ids: Array = Economy.goods_at(port_id)
	# 多船时选船装货。从别的页进来回到旗舰；本页刷新则留下刚才那艘。
	if not _market_hold or _market_ship < 0 or _market_ship >= Fleet.ships.size():
		_market_ship = 0
	_market_hold = false

	# 柜上三样先发，委办单上的「凑得出」按今日柜上现货算；上了门闸或无牙行则柜上空
	broker_hand = PackedStringArray()
	if market_open and not goods_ids.is_empty():
		var catalog: Array = []
		for raw_gid in goods_ids:
			var gid := str(raw_gid)
			catalog.append({
				"id": gid,
				"role": str(Economy.get_role(port_id, gid)),
				"buy": Economy.buy_price(port_id, gid),
			})
		broker_hand = BrokerSlip.deal(catalog, GameState.broker_salt, _broker_held_id(port_id))

	# 上了门闸：正文只一句门闸（不写「柜上只摆三样」）、不开新委办（岸上三门里牙行也不占席，见 ShoreDraft.deal）。
	# 在身委办的交货地就是本港时，那一行（交货 / 毁约）照旧补出：委办 due_day 不因围城停表，
	# 不留这条路，送兴化的委办撞上围城月就必逾期（09-29 复核 major）。「未开」一排的牙行此时点得进来，见 _make_shore_shut。
	if not market_open:
		body_text.text = _market_shut_line(port_id, true)
		if _contract_due_here(port_id):
			body_text.text += "\n\n" + MARKET_SIDE_DOOR
			_add_contract_panel(port_id)
		_add_leave_button(port_id)
		return

	_add_contract_panel(port_id)

	if goods_ids.is_empty():
		body_text.text = "此地无正经牙行，只几个渔妇晒网。"
		_add_leave_button(port_id)
		return

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
			var sname := Fleet.display_name(idx)
			var chip := Button.new()
			chip.text = "%s　空 %d" % [sname, int(Fleet.ship_free_capacity(idx))]
			chip.pressed.connect(_select_market_ship.bind(idx))
			sel.add_child(chip)
			UiTheme.style_chip(chip, idx == _market_ship)
		choices_container.add_child(sel)

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


## 闭门牙行开侧门只收先前订下的委办货（交货地是本港时）
const MARKET_SIDE_DOOR := "牙人开了侧门，只收先前订下的委办货。"


## 牙行上了门闸的那一句。海口不是城，不写「城中」，也不借城里的战况名（海口跟着城一起闭门）。
## page 为真是牙行页正文，否则是岸上「未开」一排的悬停 / 点按提示。
func _market_shut_line(port_id: String, page: bool) -> String:
	if "海口" in (GameManager.get_port_by_id(port_id).get("tags", []) as Array):
		return "海口的牙行也上了门闸，无人开秤。"
	if page:
		return "牙行上了门闸。%s，城中只剩米价在动，无人开秤。" % Economy.war_label(port_id)
	return "牙行上了门闸。%s，无人开秤。" % Economy.war_label(port_id)


## 在身委办的交货地就是这里
func _contract_due_here(port_id: String) -> bool:
	var cst := GameState.contract_status()
	return not cst.is_empty() and str(cst.get("dest", "")) == port_id


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
		var left_s := "限今日" if left == 0 else ("剩 %d 日" % left if left > 0 else "已逾")
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
				calm_note.text += " 启航后风向或变，日数按逐日累加。"
			calm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			calm_note.add_theme_font_size_override("font_size", 16)
			calm_note.add_theme_color_override("font_color", note_col)
			detail.add_child(calm_note)
			var safe_note := Label.new()
			safe_note.text = "八成：针路 %d 日 / 外洋 %d 日 / 傍岸 %d 日。" % [
				int(plan_r.get("safe_days", 0)), int(plan_o.get("safe_days", 0)), int(plan_c.get("safe_days", 0)),
			]
			var rumb_thin := int(plan_r.get("expected_days", 0)) <= deadline and int(plan_r.get("safe_days", 0)) > deadline
			var off_thin := int(plan_o.get("expected_days", 0)) <= deadline and int(plan_o.get("safe_days", 0)) > deadline
			var coast_thin := int(plan_c.get("expected_days", 0)) <= deadline and int(plan_c.get("safe_days", 0)) > deadline
			if rumb_thin or off_thin or coast_thin:
				safe_note.text += " 遇事约赶得上，八成日数逾限，未稳。"
			safe_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			safe_note.add_theme_font_size_override("font_size", 16)
			safe_note.add_theme_color_override("font_color", note_col)
			detail.add_child(safe_note)
			var hold_note := Label.new()
			hold_note.text = "保货：针路 %d / 外洋 %d / 傍岸 %d。" % [
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
				hold_note.text += " %s按八成日数赶得上，保货不到八成。不含买路。" % cargo_bits
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
			# 与牙行结算同口径：舱位逐船算（一笔货只进一艘船），钱按逐件加价的总价算
			var room := 0
			for si in Fleet.ships.size():
				room += Fleet.max_loadable(gid, si)
			# 只有今日柜上的货买得到（_on_buy 查 broker_hand）；不在柜上只算舱货
			var on_counter := gid in broker_hand
			var can_carry := held_qty + (_affordable_qty(port_id, gid, room) if on_counter else 0)
			if can_carry < need_qty:
				var purse_lbl := Label.new()
				purse_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				if on_counter:
					purse_lbl.text = "此地首件 %d 钱，逐件加价。现银与舱货凑得出 %d 件，单须 %d 件。可接；交不齐则拿不满酬，不加声名。" % [
						unit_cost, can_carry, need_qty,
					]
				else:
					purse_lbl.text = "此货今日不在柜上，现银买不到一件。舱货凑得出 %d 件，单须 %d 件。明日再看，柜上或换上此货。可接；交不齐则拿不满酬，不加声名。" % [
						can_carry, need_qty,
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
				spoil_note.text = "受潮：针路 %d / 外洋 %d / 傍岸 %d。按八成日数计，不含海盗。" % [sr, so, sc]
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
	card.custom_minimum_size = Vector2(200, 208)
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
	# 货物图槽：名称到舱位五行的右边挂一枚约 96px 的货图（1280×720 下这块空着约 250×130，卡不加高）；
	# 图在 assets/goods/good_<id>.png 才挂，缺图不加节点，五行照旧直接进 body，卡面与原先一样
	var info: VBoxContainer = body
	var good_icon := _market_good_icon(good_id)
	if good_icon != null:
		var top := HBoxContainer.new()
		top.name = "GoodTop"
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 8)
		body.add_child(top)
		info = VBoxContainer.new()
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_theme_constant_override("separation", 4)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		top.add_child(good_icon)

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
	info.add_child(name_lbl)

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
	info.add_child(hint_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "买 %d　卖 %d" % [buy_p, sell_p]
	price_lbl.add_theme_font_override("font", UiTheme.font())
	price_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	price_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(price_lbl)
	# 手续脚注：买价已含市舶抽解，卖价已扣牙人佣金；只点事实，不印费率
	var fee_lbl := Label.new()
	fee_lbl.name = "PriceFee"
	fee_lbl.text = "含抽解・扣佣"
	UiTheme.style_footnote(fee_lbl)
	fee_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(fee_lbl)

	var held_lbl := Label.new()
	held_lbl.text = "舱 %d" % held
	UiTheme.style_footnote(held_lbl)
	held_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(held_lbl)

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
		b.tooltip_text = _market_buy_tip(port_id, good_id, n, _market_ship)
		buy_row.add_child(b)
		UiTheme.style_chip(b)
	var bmax := Button.new()
	bmax.text = "买满"
	bmax.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bmax.custom_minimum_size = Vector2(0, 28)
	bmax.pressed.connect(_on_buy_max.bind(port_id, good_id, _market_ship))
	bmax.tooltip_text = _market_buy_tip(port_id, good_id, -1, _market_ship)
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
		s.tooltip_text = _market_sell_tip(port_id, good_id, n2, held)
		sell_row.add_child(s)
		UiTheme.style_chip(s)
	var sall := Button.new()
	sall.text = "全卖"
	sall.disabled = held <= 0
	sall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sall.custom_minimum_size = Vector2(0, 28)
	sall.pressed.connect(_on_sell.bind(port_id, good_id, held, _market_ship))
	sall.tooltip_text = _market_sell_tip(port_id, good_id, held, held)
	sell_row.add_child(sall)
	UiTheme.style_chip(sall)

	return card


## 牙行货卡的货图（06 批，512² 透明 PNG）：缺图返回 null，调用方不加节点。
## 图先缩到 GOOD_ICON_SRC 再上卡（512 直接压到 96、又没有 mipmap 会起毛），缩好的按货 id 记在本会话里，买卖重排货卡不再解码
const GOOD_ICON_SIZE := 96
const GOOD_ICON_SRC := 192
var _good_icon_cache: Dictionary = {}


func _market_good_icon(good_id: String) -> TextureRect:
	var tex: Texture2D = _good_icon_cache.get(good_id)
	if tex == null:
		tex = GameManager.load_texture("res://assets/goods/good_%s.png" % good_id)
		if tex == null:
			return null
		var img := tex.get_image()
		if img != null and not img.is_compressed() and maxi(img.get_width(), img.get_height()) > GOOD_ICON_SRC:
			img.fix_alpha_edges()  # 抠底后透明像素还带着品红 / 绿底色，缩图会把它混进描边
			var k := float(GOOD_ICON_SRC) / float(maxi(img.get_width(), img.get_height()))
			img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
		_good_icon_cache[good_id] = tex
	var icon := TextureRect.new()
	icon.name = "GoodIcon"
	icon.texture = tex
	icon.custom_minimum_size = Vector2(GOOD_ICON_SIZE, GOOD_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## 现银按逐件加价最多买得起几件（不超过 cap）。总价随件数只增不减，二分与 _on_buy 逐件递减同解。
func _affordable_qty(port_id: String, good_id: String, cap: int) -> int:
	var lo := 0
	var hi := maxi(0, cap)
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if Economy.estimate_buy_cost(port_id, good_id, mid) <= GameState.money:
			lo = mid
		else:
			hi = mid - 1
	return lo


## 牙行买钮悬停：与 _on_buy / _on_buy_max 同一口径（舱位按本船，钱不够按逐件总价减件）。amount < 0 为买满。
func _market_buy_tip(port_id: String, good_id: String, amount: int, ship_index: int) -> String:
	var room := Fleet.max_loadable(good_id, ship_index)
	if room <= 0:
		return "舱满，这艘船装不下。"
	var want := room if amount < 0 else mini(amount, room)
	var n := _affordable_qty(port_id, good_id, want)
	if n <= 0:
		return "现银不够一件。"
	var cost := Economy.estimate_buy_cost(port_id, good_id, n)
	if n == 1:
		return "付 %d 钱。" % cost
	var head := ""
	if amount < 0:
		head = "买满 %d 件" % n
	elif n < amount and n == room:
		head = "舱只容 %d 件" % n
	elif n < amount:
		head = "现银只够 %d 件" % n
	else:
		head = "%d 件" % n
	return "%s，共付 %d 钱，均价 %d。逐件加价，首件 %d。" % [
		head, cost, int(round(float(cost) / float(n))), Economy.buy_price(port_id, good_id),
	]


## 牙行卖钮悬停：与 _on_sell 同一口径（逐件压价的实得）。
func _market_sell_tip(port_id: String, good_id: String, amount: int, held: int) -> String:
	var n := mini(amount, held)
	if n <= 0:
		return "舱里没有这件。" if held <= 0 else "舱里不足 %d 件。" % amount
	var revenue := Economy.estimate_sell_revenue(port_id, good_id, n)
	if n == 1:
		return "得 %d 钱。" % revenue
	return "%d 件共得 %d 钱，均价 %d。逐件压价，首件 %d。" % [
		n, revenue, int(round(float(revenue) / float(n))), Economy.sell_price(port_id, good_id),
	]


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
			log_msg("【钱不够】牙人翻了翻眼皮，货单收回。")
			return
		actual = affordable
		cost = Economy.estimate_buy_cost(port_id, good_id, actual)

	if not GameState.spend_money(cost):
		return
	Fleet.add_cargo(good_id, actual, float(cost) / float(actual), ship_index)
	Economy.apply_buy_impact(port_id, good_id, actual)

	var note := ""
	if actual < amount:
		note = "只购得 %d。" % actual
	log_msg("过秤买入 %s ×%d，付 %d 钱，抽解在内。%s" % [GameManager.get_good_name(good_id), actual, cost, note])
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

	if not Fleet.remove_cargo(good_id, actual, ship_index):
		return
	GameState.add_money(revenue)
	Economy.apply_sell_impact(port_id, good_id, actual)

	var profit := revenue - int(round(cost_basis))
	var profit_str := "赚 %d" % profit if profit >= 0 else "亏 %d" % (-profit)
	log_msg("过秤卖出 %s ×%d，得 %d 钱，佣已扣，%s。" % [GameManager.get_good_name(good_id), actual, revenue, profit_str])
	_market_hold = true
	load_scene(current_scene_id)


# ── 市舶司 ──────────────────────────────────────────

func _setup_yamen(port_id: String) -> void:
	_MARITIME.setup_yamen(self, port_id)


func _on_apply_permit() -> void:
	_MARITIME.on_apply_permit(self)


## 上报发现：航中或寺观记下的东西要回市舶司呈报才换得赏格与名声
func _setup_reporting() -> void:
	_MARITIME.setup_reporting(self)


func _on_report_discovery(did: String) -> void:
	_MARITIME.on_report_discovery(self, did)


func _setup_title_and_invest(port_id: String) -> void:
	_MARITIME.setup_title_and_invest(self, port_id)


func _on_invest_port(port_id: String) -> void:
	_MARITIME.on_invest_port(self, port_id)


func _attention_desc() -> String:
	return _MARITIME.attention_desc()


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


## 工席少的设施页（贡院两卡、行会几张），卡组在正文下、离开钮上那段竖直居中，不悬上半页留一片黑空。
## 内页列与 choices_container 撑满滚动视口，Benches 吃掉余高再收回自身高度居中；卡多到溢出时余高为零，照旧从上排、可滚。
## 换页时 _uncenter_benches 复位，别的页仍从上排。
func _center_benches() -> void:
	if not (_slip_host is HFlowContainer):
		return
	var inner := choices_container.get_parent() as Control
	if inner != null:
		inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_slip_host as Control).size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER


func _uncenter_benches() -> void:
	var inner := choices_container.get_parent() as Control
	if inner != null:
		inner.size_flags_vertical = Control.SIZE_FILL
	choices_container.size_flags_vertical = Control.SIZE_FILL


## 工席纸条小件的实现在 scripts/ui/SlipKit.gd（Lane ms 首刀拆出）。这里同名同签名转发，调用点不变；
## _slip_host / choices_container 仍归 Main，经参数传过去。
## 工席宽 480，字宽 448；折行 Label 按实测高度锁最小高（见 SlipKit.lock_wrap）。
func _lock_slip_wrap(lbl: Label) -> void:
	_SLIP.lock_wrap(lbl, _slip_host is HFlowContainer)


func _slip_body() -> VBoxContainer:
	return _SLIP.card_body(_slip_host, choices_container)


func _slip_title(body: VBoxContainer, title: String, aside := "") -> Label:
	return _SLIP.add_title(body, title, aside, _slip_host is HFlowContainer)


func _slip_note(body: VBoxContainer, text: String, color: Color = UiTheme.TEXT_DIM) -> Label:
	return _SLIP.add_note(body, text, color, _slip_host is HFlowContainer)


## 钮行上方留一道空，旁注不贴钮。pin：空档可伸，钮行压到卡底——同排卡被拉高时两枚钮齐平。
func _slip_row(body: VBoxContainer, pin := false) -> HFlowContainer:
	return _SLIP.add_row(body, pin)


func _slip_chip(row: Node, text: String, cb: Callable, accent := false) -> Button:
	return _SLIP.add_chip(row, text, cb, accent)


## 只读态的钮：同一块 chip 皮，disabled、不聚焦、箭头光标。
func _slip_stamp(row: Node, text: String) -> Button:
	return _SLIP.add_stamp(row, text)


## 工席上只有这一个动作时，整张卡都可点（照 _make_shore_door）。
func _slip_whole(btn: Button) -> void:
	_SLIP.whole_card(btn)


# ── 船屋 ────────────────────────────────────────────


## 船屋页港名（题签用）。scene_id 形如 quanzhou_shipyard。
func _yard_port_name() -> String:
	return _YARD.yard_port_name(self)


## 船屋成功题签：港名・事由 + 历法日期；朱印见 UiTransition.drydock_seal。失败路径不走这里。
func _yard_success_transition(act: String) -> void:
	await _YARD.yard_success_transition(self, act)


func _setup_shipyard(port_id: String) -> void:
	_YARD.setup_shipyard(self, port_id)


func _yard_offer(catalog: Array, sid: String) -> Dictionary:
	return _YARD.yard_offer(catalog, sid)


func _on_berth_switch(ship_index: int) -> void:
	await _YARD.on_berth_switch(self, ship_index)


func _on_repair_hull(cost: int) -> void:
	await _YARD.on_repair_hull(self, cost)


func _on_hire_to_min(cost: int) -> void:
	_YARD.on_hire_to_min(self, cost)


func _on_borrow(amt: int) -> void:
	_YARD.on_borrow(self, amt)


func _on_repay(pay: int) -> void:
	_YARD.on_repay(self, pay)


func _on_buy_ship(type_id: String, price: int) -> void:
	await _YARD.on_buy_ship(self, type_id, price)


func _on_dismiss_crew(role_id: String) -> void:
	_YARD.on_dismiss_crew(self, role_id)


func _on_hire_candidate(crew_id: String) -> void:
	_YARD.on_hire_candidate(self, crew_id)


func _on_hire_crew(ship_index: int, hire_n: int, hire_cost: int) -> void:
	_YARD.on_hire_crew(self, ship_index, hire_n, hire_cost)


func _on_upgrade(ship_index: int, kind: String, shown_cost: int) -> void:
	await _YARD.on_upgrade(self, ship_index, kind, shown_cost)


func _on_buy_supplies(n: int, wp: int, gp: int) -> void:
	_YARD.on_buy_supplies(self, n, wp, gp)


# ── 玉湖陈宅（兴化住宅）────────────────────────────

const CHEN_ZAN_STAKE := 3000
const CHEN_ZAN_FROM_YEAR := 1270
const CHEN_ZAN_MIN_FAME := 15

## 本地 main 的兴化玉湖陈宅（1268 殿试前的乡土写入点、陈瓒船股）；云端 7f92 的通用「住处」在下面。
## 合并时按云端为准保留通用住处，兴化一港改走陈宅（陈文龙的家在兴化玉湖）。
## （lane w20-a9 第十三刀二：本支追加进 scripts/ui/ResidencePage.gd，真身在那边；这里留同名同签名一行转发）
func _setup_residence_chen(port_id: String) -> void:
	_RESIDENCE.setup_residence_chen(self, port_id)


## 陈瓒入船股只在兴化第一段 besieged 起点之前出（从战况表推，不写死月份）：
## 围城起他在城里募兵守城、倾家财起兵，不再拿钱入你的船股。生死另归 _chen_zan_alive 管。
func _chen_zan_stake_open() -> bool:
	var war: Dictionary = GameManager.get_port_by_id("xinghua").get("war", {})
	var keys: Array = war.keys()
	keys.sort()
	for ym in keys:
		if str(war[ym]) == "besieged":
			return "%04d-%02d" % [Calendar.year, Calendar.month] < str(ym)
	return true


# ── 酒馆 ────────────────────────────────────────────

func _setup_tavern(port_id: String) -> void:
	_TAVERN.setup_tavern(self, port_id)


## 酒馆墙上：市井札薄（_TAVERN_NEWS_WALL）。最近投放新闻，新的在前；无则不上墙。
func _setup_news_wall() -> void:
	_TAVERN_NEWS_WALL.mount(choices_container, 3)


func _setup_story_hooks(port_id: String) -> void:
	_TAVERN.setup_story_hooks(self, port_id)


func _on_story_hook(hook: Dictionary, port_id: String) -> void:
	_TAVERN.on_story_hook(self, hook, port_id)


func _on_gather_intel(port_id: String) -> void:
	_TAVERN.on_gather_intel(self, port_id)


func _setup_hiring(port_id: String) -> void:
	_TAVERN.setup_hiring(self, port_id)


func _person_slip(ch: Dictionary, title: String, aside: String, level := 0) -> VBoxContainer:
	return _TAVERN.person_slip(self, ch, title, aside, level)


func _person_foot(info: VBoxContainer, note: String) -> HBoxContainer:
	return _TAVERN.person_foot(info, note)


func _seal_chip(btn: Button) -> void:
	_TAVERN.seal_chip(btn)


## 职事品级。数据里只有 1–3，不再用星号。
func _skill_rank(n: int) -> String:
	return Crew.rank_word(n)


func _setup_inn(port_id: String) -> void:
	_TAVERN.setup_inn(self, port_id)


const INN_RATE := 15
const HOME_RATE := 5
const EXAM_COPY_DAYS := 3
const EXAM_STIPEND := 30
const GUILD_CREDIT_WIDE := 8
const GUILD_JOIN_PORTS := ["quanzhou", "hakata", "guangzhou"]
const GUILD_JOIN_FEE := 2000
const GUILD_JOIN_CREDIT := 8
const GUILD_JOIN_CREDIT_GAIN := 4
const GUILD_JOIN_NETWORK_GAIN := 2
const EXAM_SIT_DAYS := 15
## 赴试只兴化、泉州（P7 §贡院）；别港贡院只剩誊录。port_id 是 {港}_exam 去后缀后的基港 id。
const EXAM_SIT_PORTS := ["xinghua", "quanzhou"]
## 贡院只两张卡，按内容高只占上半页、离开钮下一大片空；卡压到这个高，钮行压卡底。
const EXAM_SLIP_MIN_H := 220


## 行会页 id 是港卡 city_guild 按 current_scene_id 改写的 {港}_guild；入行港判定与 guild_<港> 旗标一律记在基港 id 上。
## 尾部 _guild 剥尽（{港}_guild_guild 也收回基港），否则三港在实际页 id 下认不出，或同港旗标记成两份、会费扣两次。
func _guild_port_id(page_id: String) -> String:
	return _GUILD.guild_port_id(page_id)


## 行会：出港行情抄本。酒馆打听仍费一日只吐一条；这里钉在墙上，不耗日。
func _setup_guild(port_id: String) -> void:
	_GUILD.setup_guild(self, port_id)


## 入行：只泉州 / 博多 / 广州。已入行只看账；条件不足按钮仍在，按下只说缘由。
func _add_guild_join_slip(port_id: String) -> void:
	_GUILD.add_guild_join_slip(self, port_id)


## 返回不收的缘由；空串即可入行。
func _guild_join_block(port_id: String) -> String:
	return _GUILD.guild_join_block(self, port_id)


func _on_guild_join(port_id: String) -> void:
	await _GUILD.on_guild_join(self, port_id)


## 可复用的短过渡：淡入墨幕 → 题签擦出（title + 小朱印 seal）、副题浮起 → 停一拍 → 淡出，约 2.4 秒。
## at_black 在全黑时调（通常是 load_scene，页面在黑幕底下换好）；await 到过渡结束才返回。
## headless / -s 工具脚本 / 巡检关闭（Cinematics.live() 为假）时不演：当帧调 at_black 就返回，不 await、不延迟。
func play_transition(title: String, subtitle := "", at_black := Callable(), seal := "") -> void:
	_AUDIO.transition(self)
	var node: CanvasLayer = null
	if _CINE.live():
		_dismiss_banner()
		node = _UI_TRANSITION.play(self, title, subtitle, at_black, seal)
	if node == null:
		if at_black.is_valid():
			at_black.call()
		return
	await node.finished


## 贡院：誊录耗日换工钱与学者倾向，不给名声；赴试每章一次，费 15 日，按倾向记名声。
func _setup_exam(port_id: String) -> void:
	_GUILD.setup_exam(self, port_id)


func _exam_slip() -> VBoxContainer:
	return _GUILD.exam_slip(self)


## 誊录：与赴试同一时序——工钱与学者倾向先落袋，再 advance_days。
## 三月末誊录会跨入四月，月初 _settle_history 按倾向锁 1268 身份、pay_wages 按现银发饷。
func _on_exam_copy(_port_id: String) -> void:
	_GUILD.on_exam_copy(self, _port_id)


func _exam_sat_flag() -> String:
	return _GUILD.exam_sat_flag()


## 赴试：只兴化、泉州，每章一次，费 15 日。不发钱、不跳章、不改船。
## 身份相关旗标/倾向必须写在 advance_days 之前：三月下旬赴试会跨入四月，
## 月初 _settle_history 会按 exam_sat 与倾向锁 1268 身份。
func _on_exam_sit(port_id: String) -> void:
	await _GUILD.on_exam_sit(self, port_id)


## 住宅：看边记、便宜歇息。候风仍去旅店——下处等不到风向。
func _setup_residence(port_id: String) -> void:
	_RESIDENCE.setup_residence(self, port_id)


const TEMPLE_LOOK_DAYS := 1
const TEMPLE_RUB_DAYS := 1


## 寺观：上陆勘见近侧旧迹。记入册子，拓纸入边记；赏格仍回市舶司呈报——不在这里发名声。
func _setup_temple(port_id: String) -> void:
	_RESIDENCE.setup_temple(self, port_id)


func _temple_rub_note(name: String, hook: String) -> String:
	return _RESIDENCE.temple_rub_note(name, hook)


func _has_temple_rub(name: String) -> bool:
	return _RESIDENCE.has_temple_rub(name)


func _on_temple_look(did: String, name: String) -> void:
	_RESIDENCE.on_temple_look(self, did, name)


func _on_temple_rub(did: String, name: String, hook: String) -> void:
	_RESIDENCE.on_temple_rub(self, did, name, hook)


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
		log_msg("【钱不够】掌柜把算盘一推：「客官，先结了前账罢。」")
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
		return "【闲谈】几个老水手翻来覆去只讲当年的风暴，没打听出新行情。"
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
	_NPC.add_npc_button(self, npc_id, fallback_name)


func _on_meet_npc(npc_id: String, fallback_name: String) -> void:
	_NPC.on_meet_npc(self, npc_id, fallback_name)


func _show_npc_mode(npc_id: String, fallback_name: String) -> void:
	_NPC.show_npc_mode(self, npc_id, fallback_name)


func _set_npc_speech(text: String) -> void:
	_NPC.set_npc_speech(self, text)


func _on_npc_intel(n_name: String) -> void:
	_NPC.on_npc_intel(self, n_name)


func _on_npc_bribe(n_name: String) -> void:
	_NPC.on_npc_bribe(self, n_name)


func _on_npc_leave() -> void:
	_NPC.on_npc_leave(self)


# ══════════════════════════════════════════════════════
#  标题 / 港口 / 调查
# ══════════════════════════════════════════════════════

func _setup_title_mode(scene_data: Dictionary) -> void:
	_TITLE.setup_title_mode(self, scene_data)


func _on_start_game_pressed(next_scene: String) -> void:
	await _TITLE.on_start_game_pressed(self, next_scene)


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
	_shore_kind_now = ""
	# 守城待结的城破（第三阵战报之后、旧档过了城破时点）在排岸带之前结算：底下不先排一遍寻常港页
	_siege_fell_on_entry = _settle_siege_before_shore()
	if _siege_fell_on_entry:
		update_status_panel()
		return
	_build_shore()
	update_status_panel()


## 按页型重排岸带：终局后港口页 / 兴化守城页 / 寻常港页三选一。进港与「再候一日」都走这里，
## 每次先 _clear_shore() 把岸带与旧左右栏清空，旧节点不会残留，也不会翻倍。只是 UI 状态，不入存档。
func _build_shore() -> void:
	_clear_shore()
	# 本地 main 的终局线入口：终局后港口页 / 兴化守城页（函数在文件末尾补回段）
	if GameState.is_ended():
		_shore_kind_now = "ended"
		_shore_title_once("ended", _setup_ended_port)
		return
	if _siege_active():
		_shore_kind_now = "siege"
		# 进港换底图时城防记录还没开（_siege_active 才开），守城专用的战况档在这里补换
		_refresh_port_bg()
		_shore_title_once("siege", _setup_siege_port)
		return
	_shore_kind_now = "port"
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


## 首次进守城 / 终局岸带：墨幕全黑时再排岸带（揭开就是新页），题签同序章文法——「兴化军・围城」印「城」，
## 「港名・结局名」印「终」；副题是日期或终局时地。已演过就当帧直排。全黑前若已换页，不再补排旧页。
func _shore_title_once(kind: String, build: Callable) -> void:
	if _shore_title_seen.has(kind):
		build.call()
		return
	_shore_title_seen[kind] = true
	var sid := current_scene_id
	var title := _UI_TRANSITION.siege_title()
	var sub := Calendar.get_date_string()
	var seal := "城"
	if kind == "ended":
		title = _UI_TRANSITION.endgame_title(_ended_port_base(), GameState.ended)
		sub = GameState.ended_at if GameState.ended_at != "" else sub
		seal = "终"
	play_transition(title, sub, func() -> void:
		if current_scene_id == sid and port_mode.visible:
			build.call()
	, seal)


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
	shore_hand = ShoreDraft.deal(regular, GameState.shore_salt, _shore_pin_shipyard(), Economy.is_market_open(current_scene_id))
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
			# 仍是动作行主钮，热区略大；点按只翻开既有结局册页，不重播岸带题签、不过日子、不入存档
			var reread := _shore_action("重读结局", Vector2(240, 52), true, _on_reread_ending)
			reread.name = "RereadEnding"
			reread.tooltip_text = "再翻开结局册页。不过日子，不改存档。"
			actions.add_child(reread)
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
		# chars 线薄接入：名册 / 立绘面板（CharRoster + CharPortraitPanel）
		actions.add_child(_shore_action("名册", Vector2(100, 42), false, _open_chars_wire.bind("")))
	# Lane L：市舶纪事册页（立像裱框 + 海战定格示意）；论文纪实题签，不入存档
	actions.add_child(_shore_action("市舶纪事", Vector2(140, 42), false, _open_vision_stage))


## 重读结局：只翻开既有 ChapterSheet，不传 ending（不再 finish、不演过场、不换结算底图）；
## 眉题「重读・终局时地」、大题只写结局名，钮写「合上册页」（初读「了结 / 记下这一纲」是落定那一刻的话）。
## 岸带题签已由 _shore_title_seen 记过，合上册页走 load_scene 重排岸带也不重播。册页已开时不叠第二张。
func _on_reread_ending() -> void:
	if is_instance_valid(_chapter_host) or GameState.ended_text == "":
		return
	var kicker := "重读" if GameState.ended_at == "" else "重读・%s" % GameState.ended_at
	# 初读大题里结局名后面那截（忠肃的时地与城破原因）记在 ended_head，重读照初读写，援绝 / 粮尽 / 力竭分得出来
	var title := GameState.ended if GameState.ended_head == "" else "%s　%s" % [GameState.ended, GameState.ended_head]
	_show_chapter_dialog({"title": title, "text": GameState.ended_text, "resolved": true,
		"scene": "", "ending": "", "kicker": kicker, "ok_text": "合上册页"})


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


## 小笺抬头，同序章题签文法：马善政泥金题 24 + 一枚小朱印（守城「城」、终局「终」）+ 可选 16px 淡字旁注，
## 下接一道泥金细线（主题 HSeparator），正文由调用方逐行 16px 接在线下。
func _band_head(col: Node, title: String, seal := "", aside := "") -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "BandHead"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var head_l := _band_line(head, title, UiTheme.GOLD_HI, 24, true)
	head_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if seal != "":
		head.add_child(_seal_mark(seal))
	if aside != "":
		var gap := Control.new()
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.custom_minimum_size = Vector2(6, 0)
		head.add_child(gap)
		var aside_l := _band_line(head, aside, UiTheme.TEXT_DIM, 16, true)
		aside_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	return head


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
		"special_hanjiang_escape": "residence", "special_resign_1275": "exam",
		"special_yashan": "shipyard", "special_gangshou_end": "yamen",
		"siege_enter": "yamen",
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
	var tip_key := str(fac.get("id", "")).replace("city_", "")
	var tip := str(DOOR_TIP.get(tip_key, ""))
	if tip == "":
		var sub := str(fac.get("subtitle", "")).strip_edges()
		tip = ("%s　%s" % [str(fac.get("title", "去处")), sub]).strip_edges() if sub != "" else str(fac.get("title", "去处"))
	if pinned_yard:
		tip = "船还开不出去。\n" + tip
	btn.tooltip_text = tip
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
	"siege_enter": "城",
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
	# 热区 ≥64×32（美术规范小钮）；关着的门略宽一点，字不挤
	btn.custom_minimum_size = Vector2(120, 36)
	btn.set_meta("shore_shut", true)
	var tip_key := str(fac.get("id", "")).replace("city_", "")
	var open_tip := str(DOOR_TIP.get(tip_key, str(fac.get("subtitle", ""))))
	# 围城 / 封港时牙行上了门闸：不是轮转没轮到，候一日也不开，提示照实写。
	# 在身委办的交货地就是本港：这扇门仍在「未开」一排、不占今日三门，但点得进闭门页交货 / 毁约（见 _setup_market）
	if tip_key == "market" and not Economy.is_market_open(current_scene_id):
		var shut_line := _market_shut_line(current_scene_id, false)
		if _contract_due_here(current_scene_id):
			# 门字写明「交货」：关着的门一排里只有这扇点得进，不靠悬停才知道
			btn.text = "%s・交货" % btn.text
			btn.tooltip_text = "%s\n%s" % [shut_line, MARKET_SIDE_DOOR]
			btn.set_meta("side_door", true)
			btn.pressed.connect(func() -> void:
				load_scene(current_scene_id + "_market")
			)
		else:
			btn.tooltip_text = shut_line
			btn.pressed.connect(func() -> void:
				log_msg(shut_line)
				update_status_panel()
			)
	else:
		btn.pressed.connect(_on_shore_shut)
		if open_tip != "":
			btn.tooltip_text = "今日未开。再候一日，门或另换。\n%s" % open_tip
		else:
			btn.tooltip_text = "今日未开。再候一日，门或另换。"
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
	log_msg("今日此门未开。")
	update_status_panel()


func _on_shore_wait() -> void:
	GameState.shore_salt += 1
	# 候日这句先写、再推日子：当天的月初通告（战况、月息、辞船）排在它上面，不被压住。
	# 守城页五扇门是固定的，候一日不换门，另写一句守城的
	log_msg("城上又守了一日。" if _shore_mode == "siege" else "在岸上又候了一日，门又换了几处。")
	GameManager.advance_days(1)
	# 守城页候过城破时点：先记一句城破那天，再按城破结算，不退回寻常岸带
	if _siege_overdue():
		log_msg("%s%s。援兵没有来。" % [Calendar.get_month_name(), Calendar.get_day_name()])
	if _settle_overdue_siege():
		update_status_panel()
		return
	# 士人线没进城（停在兴化海口不点「入城」、或在别港）候进城破那个月：跨月当下就结「未归」，
	# 不等下次进港；岸带先清，册页底下不留昨日的「入城」卡、也不冒出新月的寻常卡
	if _check_absent_from_xinghua():
		_clear_shore()
		update_status_panel()
		return
	_refresh_port_bg()
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
	_SAVE.show_save_dialog(self, read_only)


func _on_save_dim_input(event: InputEvent) -> void:
	_SAVE.on_save_dim_input(self, event)


func _close_save_sheet() -> void:
	_SAVE.close_save_sheet(self)


func _on_save_slot(slot: int) -> void:
	_SAVE.on_save_slot(self, slot)


func _on_load_slot(slot: int) -> void:
	_SAVE.on_load_slot(self, slot)


# ══════════════════════════════════════════════════════
#  章节推进
# ══════════════════════════════════════════════════════

## 入港结算：记下走过的港口，够条件就开下一章。
## 只有 ports.json 里登记的港口算数——剧情场景不是港口。
func _on_enter_port(port_id: String) -> void:
	if GameManager.get_port_by_id(port_id).is_empty():
		return
	# 城防没了结的旧档过了城破时点：先按城破结算（不然「未归」见城防开着会跳过，陈文龙接着跑商）。
	# 进港时已在排岸带之前结算过（_setup_port_mode）的，这里不再往下走
	if _siege_fell_on_entry or _settle_overdue_siege():
		_siege_fell_on_entry = false
		return
	if _check_absent_from_xinghua():
		return
	var first_port := GameState.visited_ports.is_empty()
	GameState.visit_port(port_id)
	# 拍板 E-10：节拍演出账——抵达这一针条件够且未记名 = 就地演那一幕（关断开关关掉 = _beats 空账、一步不动）。
	# 只接泉州链（章一开店泉州五针）：流求 / 博多链的头针与航路首抵（route 探针断言航路抵港进的是港页、
	# 记 visited_ports）相冲突，章二博多针又压着 hakata_ledger 剧情幕（route 断言 ryukyu_bay / hakata_ledger
	# 不记港）——拍板 G1014 的「跨港链怎么接到航路上」没定，非泉州各港的拍一律不演不动账
	_beats_book()
	# 新档 / 老档 seed：开关开着、拍账一笔未记过，把序章沿途已演的戏（DEFAULT_SEED）记上——
	# 每个会话只下一回（loaded_with_beats 不入存档）：读老档（没 beats_seen）开关打开头一回到港也 seed 一回，
	# seed 过的会话不再补（玩家后头清账是自己的玩法）
	if _BEATS.enabled() and GameState.beats_seen.is_empty() and not GameState.loaded_with_beats and not GameState.siege_open():
		for seed_entry in _BEATS.DEFAULT_SEED:
			GameState.beat_mark(seed_entry)
		GameState.loaded_with_beats = true
	# 老档补账（lane w53-6）：拍账接回运行时之前的档（或那以后读老档、seed 只记了 start 的档）没记演幕，
	# 序章各幕其实早已演过——节拍幕的选项各带一枚旗，档里有其一 = 那一幕点过，照记名，不再从 monk 起重演
	if _BEATS.enabled() and port_id == "quanzhou" and not GameState.siege_open() and not GameState.is_ended():
		for entry in _beats.entries():
			if _beat_scene_chosen(entry):
				GameState.beat_mark(entry)
	# 守城开着的会话不演拍不动账（城破了算、戏让位守城）；终局落定后回港也不演不动账
	# （wave22 待定项② 已准「终局后港口节拍一律不再演」：港页只剩回顾札记，「重读结局」、进出设施
	#  都不走这条路——守卫只拦节拍）。终局判定只读现量 GameState.is_ended()（b2 的
	#  GameState.gd 不加字段）。终局守卫已下沉进 PortBeats.due/arrive 接口（w26-k7）：
	#  末参传 is_ended()，达成「终局后不演」成为账口自身的性质、不再靠本处先截。
	var ar: Dictionary = {} if port_id != "quanzhou" or GameState.siege_open() else _beats.arrive(port_id, GameState.beats_seen, GameState.beat_flag_names(), GameState.visited_ports, GameState.chapter, GameState.is_ended())
	if not ar.is_empty():
		var mark := str(ar.get("mark", ""))
		var entry := str(ar.get("beat", {}).get("entry", ""))
		GameState.beat_mark(mark if mark != "" else entry)
		if bool(ar.get("play", false)) and entry != "" and GameManager.get_scene_by_id(entry) != {}:
			# 就地演出那一幕（港页已排好、戏叠上面；scene_unlocked 那道不再查——节拍 requires 就是它的开锁口）
			_load_scene_inner(entry)
			return
	var res := GameState.try_advance_chapter()
	if res.get("advanced", false) or res.get("resolved", false):
		_show_chapter_dialog(res)
	elif first_port and GameState.chapter == 1 and _CINE.live():
		# 序章走完、第一次踏上港口（岸页开张）：第一章开卷。只演卡，不弹册页。
		# 卡紧跟在港页 load_scene 之后：黑场第 0 帧就压满，不先露出港页再压黑（第 2 轮美术 M1）
		_CS_CARD.play(self, 1, _CINE.DATA, _CINE.year_text(Calendar.year, Calendar.ERAS), true)
	elif _arrival_banner and _CINE.live() and _shore_kind_now == "port":
		# 海图回港的真正抵港：旧绢挂签报副题（港名已在顶上的墨刷匾里，同屏不写第二遍），居中挂在匾下；
		# 不拦输入、2.65 秒自退；开章 / 了结时让位给章节卡与结局过场。
		# 这次进港排的是守城 / 终局岸带（要演「兴化军・围城」一类题签）：太平时节的挂签不出，不压在题签底下白演一遍
		_CS_BANNER.show_banner(self, port_id, _CINE.DATA, 0.285, false)
	update_status_panel()


## 本局节拍账口（头一回用到才按 port_beats_data 建；开关关掉时数据是空表、账口空转）
func _beats_book():
	if _beats == null:
		_beats = _BEATS.new()
		_beats.init(GameManager.port_beats_data.get("beats", []))
	return _beats


## 演到节拍幕即记名（拍板 E-10 的拍账记「这幕演过没有」，lane w53-6）。开关关掉不记（老行为）
func _note_beat_scene(scene_id: String) -> void:
	if _BEATS.enabled() and _beats_book().is_beat_scene(scene_id):
		GameState.beat_mark(scene_id)


## 这一幕的选项点过没有：data/scenes.json 该幕各选项 effects.flag 档里有其一即是（老档补账用）
func _beat_scene_chosen(scene_id: String) -> bool:
	for raw in GameManager.get_scene_by_id(scene_id).get("choices", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var eff = (raw as Dictionary).get("effects", {})
		if typeof(eff) != TYPE_DICTIONARY:
			continue
		var f := str((eff as Dictionary).get("flag", ""))
		if f != "" and GameState.has_flag(f):
			return true
	return false


func _era_summary_lines(years: int) -> Array:
	return _CHAPTER.era_summary_lines(self, years)


func _show_chapter_dialog(res: Dictionary) -> void:
	_CHAPTER.show_dialog(self, res)


func _chapter_body_height(text: String, body_w := 560) -> int:
	return _CHAPTER.body_height(self, text, body_w)


func _cinema_before_sheet(res: Dictionary) -> bool:
	return _CHAPTER.cinema_before_sheet(self, res)


func _ending_cinema_key(res: Dictionary) -> String:
	return _CHAPTER.ending_cinema_key(res)


func _confirm_chapter_sheet() -> void:
	await _CHAPTER.confirm_sheet(self)


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
		log_msg("今日此门未开。")
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
		elif event.keycode == KEY_F9:
			# Lane N：岸上预览接舷题签（不入存档、不改舰队）
			_COMBAT_SHORE.preview_boarding(self, true)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F7:
			# Lane Z3：伙伴草案预览浮页（只读剪影卡；再按关闭）
			_toggle_companion_preview()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F8:
			# Lane L：岸上叠 VisionStage（立像裱框）；B/Esc 合上
			_open_vision_stage()
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
	_DEBUG.debug_jump_port(self)


## 调试局预览了结弹窗。沙盒攒到八万+占城太慢，云电脑点验用。
func _debug_preview_ending() -> void:
	_DEBUG.debug_preview_ending(self)


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══
const CARD_HANJIANG := "special_hanjiang_escape"
const CARD_SIEGE_MUSTER := "siege_muster"      # 衙门・募兵 / 石手军
const CARD_SIEGE_GRAIN := "siege_grain"        # 市场・屯粮
const CARD_SIEGE_WALL := "siege_wall"          # 船厂・修城墙
const CARD_SIEGE_ENVOY := "siege_envoy"        # 酒馆・使者
const CARD_SIEGE_NANGSHAN := "siege_nangshan"  # 囊山设伏
const CARD_SIEGE_NUNNERY := "siege_nunnery"    # 福州尼寺（不可操作）
const CARD_SIEGE_ENTER := "siege_enter"        # 兴化海口・入城（守城页只在城里开）
## 从兴化海口进城那一句（「入城」卡与海口旧档自动入城共用）
const SIEGE_ENTER_LOG := "你从海口进了城。城门在身后合上。"
const CARD_RESIGN := "special_resign_1275"
const CARD_YASHAN := "special_yashan"
const CARD_GANGSHOU := "special_gangshou_end"


func _check_absent_from_xinghua() -> bool:
	if GameState.is_ended() or not GameState.has_flag("renamed_wenlong"):
		return false
	if GameState.siege_open() or GameState.has_flag("siege_fought"):
		return false
	# 按日期判，不按当前战况：1277-02 至 08 陈瓒复城时兴化会回 loyal（09 起唆都再围），
	# 若看当前战况，士人线玩家在那几个月入港就躲过了这个结局。城破发生过就是发生过。
	if not (Calendar.year > 1276 or (Calendar.year == 1276 and Calendar.month >= 12)):
		return false

	# 在兴化海口结算的（海口候进腊月、腊月进了海口）：人就在城外，消息不是「在别处听到的」。
	# 立 weigui_at_harbor 旗，结局过场第 1 镜同句按旗换（cutscenes.json ending_weigui 的 if_flag / unless_flag）
	var at_harbor := current_scene_id == "xinghua_harbor"
	if at_harbor:
		GameState.set_flag("weigui_at_harbor")
	var lead := "消息是从城里传出来的。你就在城外的海口。" if at_harbor else "消息是在别处听到的。"
	_show_notice_dialog(
		"未归", "兴化・景炎元年十二月",
		"%s

兴化城破了。城中兵不满千，守了一个多月。城头上挂过一幅白布，八个字，来往的人都说见过。
部将林华出去侦敌，回来时后面跟着一万人。通判曹澄孙开的东门。

母亲黄氏和幼子璥被扣在福州一座尼寺里。有人说，只要城里那个人肯出来，当天就放。
城里那个人没有出来——因为城里没有那个人。

你姓陈，名文龙，字君贲，咸淳四年殿试第一，御笔改的名。这些年你走的是另一条路。
史书上后来写：是年，兴化陷，守臣不知所终。

——
一百多年后，福州台江，泗洲。江边没有庙。
渔民出海前拜妈祖，只拜妈祖。官船出洋，二号封舟空着。

这个世界少了一位海神。也没有多出几条回来的船。" % lead,
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

## 涵江出海到旧避风澳：原地结算七日（不走海图），航程里真吃船上的水粮；落款地名写到岸的地方
const HANJIANG_DAYS := 7
const HANJIANG_END_PLACE := "旧避风澳"
## 兴化再陷前一月的这一日起，涵江卡的副题改成催促（城破月从战况表推，不写死）
const HANJIANG_URGENT_DAY := 20


func _on_hanjiang_escape() -> void:
	if Fleet.supply_days() < HANJIANG_DAYS:
		# 直接进本港船屋补水粮：船屋平时靠轮转，不一定在今日三门里；船屋页「离开」回到带卡的港页
		# 门槛只按自家船队日耗算七日（族人的四条船各带水粮，不吃你的）：文案照机制写，不说族人吃你船上的粮
		log_msg("【水粮不足】族里四条船各带了水粮；你船上的，也得够七日。")
		load_scene(current_scene_id + "_shipyard")
		return
	# 七日航程：借 at_sea 让 Fleet.on_day_passed 按海上日子扣水粮，推完复位（仍在港页上结算）
	var was_at_sea: bool = Fleet.at_sea
	Fleet.at_sea = true
	GameManager.advance_days(HANJIANG_DAYS)
	Fleet.at_sea = was_at_sea
	# 路上月初翻牌的通告（冬月初一兴化城破等）照常记进船籍簿；状态条最上面留出海这一句——城破时人已在海上
	log_msg("四条船出了涵江海口，没有回头。")
	GameState.set_flag("ending_root_sea")
	GameState.fame += 10
	GameState.hometown_tendency += 10
	GameState.add_ledger_note("北礁可泊")
	var stake_line := "陈瓒没有上船。他说他姓陈，在这里出生，就死在这里。" if GameState.has_flag("chen_zan_stake") else "陈瓒没有上船。"
	_show_notice_dialog(
		"岸上的根",
		"旧避风澳・景炎二年",
		"四条船。\n族里能走的都在船上，老夫人也在，她把箧底那叠策论草稿带上了船，说是「%s的东西」。\n%s\n\n出海口的时候元兵已经围了城。海上没有人追。你看水色。北礁可泊。\n二十二年前，一个舵手教过你。\n\n船在旧避风澳泊了六天，避了一场风。第七天早晨，老夫人把那叠草稿拿出来晒。\n纸都黄了，字还在。她一张一张看，看完了放回去。\n「%s，」她说，「往南走吧。」\n\n——\n一百多年后，福州台江，江边没有庙。渔船只拜妈祖。二号封舟，空着。\n这个世界少了一位海神，多了几条回来的船。" % [
			"子龙", stake_line, "子龙",
		],
		"岸上的根"
	)
	# finish 取 last_port 落款（兴化 / 兴化海口）；这一局是在旧避风澳收的，落款改写成到岸的地方
	if GameState.ended == "岸上的根":
		GameState.ended_at = "%s・%s" % [Calendar.get_date_string(), HANJIANG_END_PLACE]


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
		CARD_SIEGE_ENTER:
			# 兴化海口 → 兴化城：短途陆路，当天就到（同一座城的两个节点，不过海图、不走日子）
			log_msg(SIEGE_ENTER_LOG)
			load_scene("xinghua")



func _on_yashan() -> void:
	_enter_panel_mode()
	scene_title.text = "崖山外海"
	var known_here := GameState.has_flag("sided_zhang")
	body_text.text = "祥兴二年二月。张世杰的船连成一片，船和船之间用铁索。
陈瓒的船不在。前年兴化再破，他没有出城。
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
	port_title.text = _UI_TRANSITION.endgame_title(_ended_port_base(), GameState.ended)
	_fit_port_title()
	# 云端港口页没有左右栏：札记是岸带上方一方墨笺，动作行只留「重读结局」「航海日志」「人物志」
	_shore_mode = "ended"
	_shore_facilities = []
	_refresh_shore()
	update_status_panel()


## 匾上的港名（去掉已拼上的「・结局名」）：终局匾与终局题签共用
func _ended_port_base() -> String:
	var base := port_title.text
	if base.find("・") >= 0 and base.ends_with(GameState.ended):
		base = base.trim_suffix("・" + GameState.ended)
	return base


## 终局后港口页的航海札记：墨底小笺，标题马善政泥金印「终」、旁注终局时地（淡字 16px），逐行 16px；
## 行多时在 170 高里滚动、底边渐隐；笺脚一行淡字注文指向动作行「重读结局」。
func _epilogue_slip() -> Control:
	var parts := _band_slip("EpilogueSlip")
	var slip: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]
	slip.custom_minimum_size = Vector2(760, 0)
	_band_head(col, "航海札记", "终", GameState.ended_at)
	var lines_box := VBoxContainer.new()
	lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines_box.add_theme_constant_override("separation", 6)
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
	if GameState.ended_text != "":
		var foot := _band_line(col, "结局册页在岸下，「重读结局」可再翻开。", UiTheme.TEXT_DIM, 16)
		foot.name = "EpilogueFoot"
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	port_title.text = _UI_TRANSITION.siege_title()
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
	_band_head(col, "城头白布八字　生为宋臣　死为宋鬼", "城",
		"三阵・尚未接战" if fought <= 0 else "三阵・已守%s阵" % _cn_num(fought))
	_band_line(col, "兵 %d（上限 %d）　粮 %d・%s　城墙 %d / %d　士气 %d%s" % [
		GameState.siege_get("troops"), GameState.siege_troop_cap(),
		grain, "一阵也不够" if rounds_left <= 0 else "够打%s阵" % _cn_num(rounds_left),
		GameState.siege_get("wall"), GameState.SIEGE_WALL_MAX,
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
	# 城破前约十日起告急：候日这些天城防账不能一个字都不变，玩家得知道再候下去就是城破
	var dire := _siege_dire_warning()
	if dire != "":
		var drow := HBoxContainer.new()
		drow.name = "SiegeDire"
		drow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drow.add_theme_constant_override("separation", 8)
		col.add_child(drow)
		drow.add_child(_seal_mark("急"))
		var dl := _band_line(drow, dire, UiTheme.CINNABAR, 16)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for fac in _siege_cards():
		if str(fac.get("id", "")) == CARD_SIEGE_NUNNERY:
			_band_line(col, "%s：%s。这件事没有选项。" % [str(fac.get("title", "福州尼寺")), str(fac.get("subtitle", ""))], UiTheme.TEXT_DIM, 16)
	return slip


## 城破前几日起城防账告急（天数从首守城破时点倒推，不写死日期）
const SIEGE_DIRE_DAYS := 10


## 城防账的告急行：离首守城破时点不足 SIEGE_DIRE_DAYS 日时给一句，其余日子空串
func _siege_dire_warning() -> String:
	var fp := _siege_fall_point()
	if fp.is_empty():
		return ""
	var left: int = int(fp["abs"]) - Calendar.absolute_day()
	if left <= 0 or left > SIEGE_DIRE_DAYS:
		return ""
	return "援兵音信断绝。城中都说，捱不过%s。" % str(fp["month"])


## 兴化海口「入城」卡副题：平日一句提醒；城破前 SIEGE_DIRE_DAYS 日起换告急口吻（同城防账告急行一个判据，月名同样倒推）
func _siege_enter_subtitle() -> String:
	if _siege_dire_warning() == "":
		return "城被围了。你该在城里"
	return "援兵断了。城中捱不过%s" % str(_siege_fall_point()["month"])


## 首守城破时点那一天（该月初一）的历法写法：{abs 绝对日, era 「景炎元年」, month 「腊月」}；表里没有返回空表。
## 借 Calendar 自己的写法算（临时拨到那一天、算完拨回），年号月名和顶栏同一套
func _siege_fall_point() -> Dictionary:
	var ym := _first_siege_fall_ym()
	if ym == "":
		return {}
	var p := ym.split("-")
	var keep: Dictionary = Calendar.to_dict()
	Calendar.from_dict({"year": int(p[0]), "month": int(p[1]), "day": 1})
	var out := {"abs": Calendar.absolute_day(), "era": Calendar.get_era_year_string(), "month": Calendar.get_month_name()}
	Calendar.from_dict(keep)
	return out


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
	# 守城页只在兴化城里开：海口在城外（底图是商港、城破正文写「你在城楼上」），海口只给一张「入城」卡（_special_cards）
	if current_scene_id != "xinghua":
		return false
	if not _siege_due():
		return false
	GameState.siege_begin()
	return true


## 该不该守城（不看人在哪、不开城防记录）：士人线改了名、1276 年、兴化正被围。海口「入城」卡与守城页共用这一判据。
func _siege_due() -> bool:
	if GameState.is_ended() or not GameState.has_flag("renamed_wenlong"):
		return false
	# 陈文龙守的是 1276 冬那一次；1277 秋唆都再围是陈瓒的城
	if Calendar.year != 1276:
		return false
	return Economy.war_status("xinghua") == "besieged"


## 兴化战况表里每段 besieged 结束、转成别的战况的那个月（"YYYY-MM"），按时间排。
## 数据现为 [1276-12 首守城破, 1277-11 唆都再陷]。
func _xinghua_fall_yms() -> Array:
	var war: Dictionary = GameManager.get_port_by_id("xinghua").get("war", {})
	var keys: Array = war.keys()
	keys.sort()
	var out := []
	var in_siege := false
	for ym in keys:
		if str(war[ym]) == "besieged":
			in_siege = true
		elif in_siege:
			out.append(str(ym))
			in_siege = false
	return out


## 兴化首守的城破时点：第一段 besieged 的尽头。
## 只认第一段——1277 秋唆都再围是第二段 besieged，那是陈瓒的城，不是陈文龙的。表里没有就返回 ""。
func _first_siege_fall_ym() -> String:
	var falls := _xinghua_fall_yms()
	return str(falls[0]) if not falls.is_empty() else ""


## 陈瓒还在不在：他死于兴化再陷（唆都回师来攻，城破被执车裂），即第二段 besieged 的尽头。表里没有再陷就不设上限。
func _chen_zan_alive() -> bool:
	var falls := _xinghua_fall_yms()
	if falls.size() < 2:
		return true
	return "%04d-%02d" % [Calendar.year, Calendar.month] < str(falls[1])


## 城防记录还开着、日历却已过首守城破时点（守城页「再候一日」候过去，或这样留下的旧档）：
## 走城破结算，不许回寻常港页接着跑商、躲掉结局。结算了返回 true。
func _settle_overdue_siege() -> bool:
	if not _siege_overdue():
		return false
	_siege_fall("援绝")
	return true


## 城防记录还开着、日历已到首守城破时点（含当月）：该按「援绝」结算了
func _siege_overdue() -> bool:
	if GameState.is_ended() or not GameState.siege_open():
		return false
	var fall := _first_siege_fall_ym()
	return fall != "" and "%04d-%02d" % [Calendar.year, Calendar.month] >= fall


## 第三阵打完先出战报册页（城防记录里记 pending_fall），玩家按「回城」回到兴化、排岸带之前才走城破。
## 存档里留着这个记号的（战报册页开着时不能存档，保险起见也认），读进任何港都照样结算。结算了返回 true。
func _settle_pending_siege_fall() -> bool:
	if GameState.is_ended() or not GameState.siege_open():
		return false
	var pend := str(GameState.siege.get("pending_fall", ""))
	if pend == "":
		return false
	_siege_fall(pend)
	return true


## 进港排岸带之前的守城结算：第三阵战报后待结的城破、城防开着却已过城破时点的旧档。
## 先清岸带再结算，城破过场淡出前露的是空岸带，不先闪一下带「看风」的寻常港页。结算了返回 true。
func _settle_siege_before_shore() -> bool:
	if GameState.is_ended() or not GameState.siege_open():
		return false
	if str(GameState.siege.get("pending_fall", "")) == "" and not _siege_overdue():
		return false
	_clear_shore()
	if current_scene_id == "xinghua":
		port_title.text = _UI_TRANSITION.siege_title()
		_fit_port_title()
	if not _settle_pending_siege_fall():
		_settle_overdue_siege()
	return true



func _siege_buy_grain() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・市场"
	body_text.text = "牙行闭着，只有米在动。米价跟着仗走，打一阵涨一截。
粮就是守城的日子：每打一阵，耗粮 %d。" % GameState.SIEGE_GRAIN_PER_ROUND

	# 围城米价：随已打轮次上涨（候日不涨，文案照这个写）
	var unit: int = 12 + GameState.siege_get("round") * 8
	for n in [40, 120]:
		var cost: int = n * unit
		var b := Button.new()
		b.text = "屯粮 %d（%d 钱・每石 %d）" % [n, cost, unit]
		b.disabled = GameState.money < cost
		b.pressed.connect(func():
			if GameState.spend_money(cost):
				GameState.siege_add("grain", n)
				log_msg("买进粮 %d。再打一阵，米价还要涨一截。" % n)
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
		body_text.text = "知福州王刚中派了两个使者来，带着一封劝降书。正使在城下念。念到第三句时，你让人从城上缒下绳去，把两个人吊了上来。"
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


## 囊山设伏：数值判定，最多三阵。粮尽或三阵打完（力竭）即城破。

## 城破原因上屏的字：内部键不改（"三阵毕" 仍是键），题头写「援绝」「粮尽」「力竭」——成语「粮尽援绝」两半加一个「力竭」，同一路文言
const SIEGE_FALL_WORD := {"援绝": "援绝", "粮尽": "粮尽", "三阵毕": "力竭"}


func _siege_fall(reason: String) -> void:
	# 援绝是候过城破时点才结算的（S3 候日、旧档、停在别港的旧档）：题头写城破那个月，落款拉回城破时点；
	# 粮尽、力竭是当场打破的：落款照当日，题头只写到「冬」，不和同屏顶栏的冬月日期打架
	var overdue := _siege_overdue()
	var word := str(SIEGE_FALL_WORD.get(reason, reason))
	var betrayal := ""
	if GameState.has_flag("cao_opened"):
		# 第三阵前没放林华出侦、关了城门：史实照旧——林华降、曹澄孙开门，两件事都发生了（《宋史·陈文龙传》）
		betrayal = "林华是夜里缒城出去的，出去就降了。他领着元兵回到城下的那天夜里，通判曹澄孙开了东门。他后来说，是城里的人求他开的。这话可能是真的。"
	elif GameState.has_flag("lin_hua_reminded"):
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。他在城下抬头看了你一眼，很快低下去。那个结松了。"
	else:
		betrayal = "林华出去两天。第三天早上他回来了，后面跟着一万人。"

	var text := "%s
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

供在里面的那个人，一辈子没出过海。" % betrayal

	var head := "兴化・景炎元年十二月"
	if not overdue:
		head = "兴化・景炎元年冬"
	if word != "":
		head += "・" + word
	GameState.siege = {}
	# 先落定结局再改落款、记大题（finish 只认第一次，_show_notice_dialog 里那次不再改写）
	GameState.finish("忠肃", text)
	var signoff := _siege_fall_signoff() if overdue else ""
	if signoff != "":
		GameState.ended_at = signoff
	# 大题那截存档：重读结局、航海札记照它写，城破原因不只在初读册页露一次
	GameState.ended_head = head
	_show_notice_dialog("忠肃", head, text, "忠肃")


## 忠肃落款的城破时点：「景炎元年　腊月・兴化」——年号、月名从兴化战况表首守城破那个月推（_siege_fall_point），不写死
func _siege_fall_signoff() -> String:
	var fp := _siege_fall_point()
	if fp.is_empty():
		return ""
	return "%s　%s・%s" % [str(fp["era"]), str(fp["month"]), GameManager.get_port_name("xinghua")]


## 士人线错过守城：1276 年兴化陷落时你不在城里。
## 这不是漏判，是这一局的答案——所以它必须有结局，而不是让陈文龙继续跑商到老。

func _siege_lin_hua() -> void:
	_enter_panel_mode()
	scene_title.text = "兴化・城头"
	# 当面见过他：人物志里记为已识（没雇过他的士人线玩家也一样；记进 GameState.met_ids 随存档，同酒馆见卡）
	_CHAR_ART.note_met("lin_hua")
	var known := "lin_hua" in GameState.crew_history
	body_text.text = "部将林华上来请命：「大人，元兵在江口。我带五十人出去看看虚实。」"
	if known:
		body_text.text += "

你认得这张脸。二十年前他在林阿舶的船上系缆，后来在你的船上把过舵。缆绳系得很好。"

	if known:
		var remind := Button.new()
		remind.text = "「你的缆绳系得好。你系的结，从来不松。」让他去"
		remind.pressed.connect(func():
			GameState.siege_set("lin_hua_sent", true)
			GameState.siege_add("morale", 5)
			GameState.set_flag("lin_hua_reminded")
			log_msg("他愣了一下，说大人还记得。城头的人见你叫得出自家旧舵工的名字，士气 +5。")
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
	# 「谁也不出」先不写：关了城门，囊山第三阵照样能出城设伏（禁不禁第三阵待策划定）
	stay.text = "不去。关城门"
	stay.pressed.connect(func():
		# 落闸当下城里一乱，官仓丢粮：上屏照实际扣掉的数写，城防账少了多少、日志就交代多少
		# （林华请命只在囊山有粮打下一阵时出，粮总够扣；mini 只防别处调进来）
		var lost: int = mini(30, GameState.siege_get("grain"))
		GameState.siege_set("lin_hua_sent", true)
		GameState.siege_add("grain", -lost)
		GameState.set_flag("cao_opened")
		# 只作铺垫，城还在、林华也还在：缒城出降、曹澄孙开东门都是城破那夜的事（_siege_fall 按 cao_opened 写，过场第 2 镜同旗换句）。
		# 不写天数、不写「当夜」，日历没动，玩家这一天还能接着打第三阵。顶栏一行约容 57 字，这句压在 52 字内，曹澄孙那半句不被截掉
		log_msg("城门落了闸，人心一乱，官仓前挤抢，丢了%s石米。林华在垛口缒绳边站了一会儿。东门下，通判曹澄孙转了几回。" % _cn_num(lost))
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
		# 分节小题同册页眉题：泥金小题样式，字号 16（本作岸带与册页的下限）
		UiTheme.style_section_label(sep)
		sep.add_theme_font_size_override("font_size", 16)
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
			log_msg("他们把石头放下了，没有走。从这天起，城头上多了两百个不领饷的人。")
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

	# 战报册页：不是结局，眉题「战报」、钮「回城」（重读结局同一个 kicker / ok_text 口子）；大题中文数字，胜负不再重复「囊山」
	var head := "囊山・第%s阵　%s" % [_cn_num(rd), "退敌" if won else "失利"]
	if GameState.siege_get("round") >= GameState.SIEGE_ROUNDS_MAX:
		# 第三阵：先出战报，玩家按「回城」回到兴化、排岸带之前才走城破（_settle_siege_before_shore），
		# 战报停多久由玩家定，不再被结局过场当帧吞掉
		GameState.siege_set("pending_fall", "三阵毕")
		_show_siege_report(head, txt + "

粮快尽了。这是最后一阵。")
		return

	_show_siege_report(head, txt)


## 囊山一阵的战报册页（ChapterSheet 的了结版式，眉题、钮字换成战报口吻；不 finish、不演过场）
func _show_siege_report(head: String, text: String) -> void:
	_show_chapter_dialog({"title": head, "text": text, "resolved": true, "scene": "", "kicker": "战报", "ok_text": "回城"})


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
	# 涵江海口 → 旧避风澳：1277 年九十月唆都再围兴化（福建通志「九月來攻……逾月」城破），且第一章复核过旧泊地
	if current_scene_id in ["xinghua", "xinghua_harbor"] \
			and Calendar.year == 1277 and Calendar.month in [9, 10] \
			and Economy.war_status("xinghua") == "besieged" \
			and not GameState.has_flag("renamed_wenlong") \
			and GameState.has_found("nameless_shelter_bay") \
			and not GameState.has_flag("ending_root_sea"):
		out.append({"id": CARD_HANJIANG, "title": "涵江海口", "subtitle": _hanjiang_card_subtitle()})

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

	# 士人线守城：守城页只在兴化城里开，兴化海口在该守城的月份给一张「入城」卡（siege_ 前缀，走 _on_siege_card）
	if current_scene_id == "xinghua_harbor" and _siege_due():
		out.append({"id": CARD_SIEGE_ENTER, "title": "入城", "subtitle": _siege_enter_subtitle()})

	return out


## 涵江卡副题：兴化再陷前一月的下旬（HANJIANG_URGENT_DAY 起）改成催促，其余日子写去处。
## 城破月取战况表里 besieged 段的尽头（_xinghua_fall_yms），不写死十月。
func _hanjiang_card_subtitle() -> String:
	var ny := Calendar.year + (1 if Calendar.month == 12 else 0)
	var nm := 1 if Calendar.month == 12 else Calendar.month + 1
	if Calendar.day >= HANJIANG_URGENT_DAY and ("%04d-%02d" % [ny, nm]) in _xinghua_fall_yms():
		return "城撑不过这个月了"
	return "带族人走旧避风澳"



