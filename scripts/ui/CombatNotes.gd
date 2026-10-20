## 一到六期海战新概念的旁注小笺（lane w54-polish）：第一次遇到某样新玩法时，页边出一张宣纸小笺，
## 用「纸本纪录片」的口吻一两句讲清它是什么；看过就记进存档旗标，再遇不出。
##
## 文案在 data/combat_notes.json，一条一样：id（旗标尾名）、title 小题、text 正文、switch 那一样玩法自己的开关键
## （字串或字串表，全开才出；空串 = 底子玩法，只看总开关）。
## 总开关 CombatSwitches.combat_notes（默认开）：关 = 一张都不出、旗标一枚不写，逐字回旧。
##
## 已读记在 GameState.flags（键 combat_note_<id>）：旗标字典本就随档存取（SaveLoad._harden_state 只收 true 布尔），
## 不另立存档字段、不升 SAVE_SCHEMA、不加迁移；旧档没有这几枚旗 = 都没看过，照常出。已读跟着这一卷存档走（读档换成那一卷的旗标）。
##
## 挂法：CombatNotes.offer(host, id)——host 是当前这一页的根（WorldMap / SeaChart / Main），小笺层挂在它下面、随页释放。
## 同一页里排队：一张停够 hold_s 秒（或被点掉）再空 BETWEEN 秒出下一张；排着还没出的不记已读，下回再遇照出。
## 海战里谁先「第一次」由 CombatNoteWatch 盯着（WorldMap._setup_combat 挂一个）；海图、牙行、守城在各自那一处调 offer。
## 不暂停、不吞键盘；鼠标 / 触屏点小笺即收起。脚本里不写 autoload 标识符（-s 工具 preload 进来也编得过），GameState 按路径取。
extends CanvasLayer

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

const DATA_PATH := "res://data/combat_notes.json"
## 总开关（CombatSwitches 表末那一行）
const SWITCH := "combat_notes"
## 已读旗标：combat_note_<id>
const FLAG_PREFIX := "combat_note_"
const NODE_NAME := "CombatNotes"
const GROUP := "nk1_combat_notes"
## 层号：在接舷题签（BoardingStage 55）、白刃拍板层（56）之上，出战墨边（CombatLetterbox 58）之下——
## 接舷时压暗的海面上也看得见，进出战的墨边照旧盖住它
const LAYER_INDEX := 57
## 小笺宽：同敌情列（CombatStatusHud.INTEL_W），海战里正好接在它下面一溜
const SLIP_W := 250.0
const MARGIN := 16.0
const GAP := 10.0
## 找不到顶匾时的顶边
const TOP_FALLBACK := 88.0
## 一张停多久：起 HOLD_BASE 秒、每字加 HOLD_PER_CHAR，夹在 HOLD_MIN–HOLD_MAX（六十来字约十一秒，够慢读一遍）
const HOLD_BASE := 3.0
const HOLD_PER_CHAR := 0.12
const HOLD_MIN := 6.0
const HOLD_MAX := 11.0
const T_IN := 0.25
const T_OUT := 0.4
## 两张之间空这么久
const BETWEEN := 0.6
## 出着时多久重摆一次（敌情列伸缩、选中小卡开合都会挪它的落点）：十分之一秒一次足够，逐帧重排白费
## （同 CombatStatusHud.REFRESH_SEC；出卡那一拍当场摆一次）
const LAYOUT_EVERY := 0.1

var _queue: PackedStringArray = []
var _slip: PanelContainer = null
var _cur := ""
var _left := 0.0
var _wait := 0.0
var _closing := false
var _lay_acc := 0.0


# ── 表与已读（纯函数，探针可不建节点直接验）──────────────

## 整张表：id → 条目（读不到文件返回空表，一张都不出）。海战观察件每秒问好几回，读一遍记下
static var _tab: Dictionary = {}
static func table() -> Dictionary:
	if _tab.is_empty():
		var d: Dictionary = Kit.load_json(DATA_PATH)
		for e in d.get("notes", []):
			if e is Dictionary and str(e.get("id", "")) != "":
				_tab[str(e["id"])] = e
	return _tab


## 另一本：新手上手小笺（lane w54-tutorial，data/tutorial_notes.json）。同格式，同一页里与本表排一个队、用同一张纸出；
## 已读旗另起前缀 tutorial_note_。谁看得到、几时排归 scripts/ui/TutorialNotes.gd，这里只认条目；table() 仍只是本表
const TUTORIAL_PATH := "res://data/tutorial_notes.json"
const TUTORIAL_FLAG_PREFIX := "tutorial_note_"
static var _tut: Dictionary = {}
static func tutorial_table() -> Dictionary:
	if _tut.is_empty():
		var d: Dictionary = Kit.load_json(TUTORIAL_PATH)
		for e in d.get("notes", []):
			if e is Dictionary and str(e.get("id", "")) != "":
				_tut[str(e["id"])] = e
	return _tut


static func entry(id: String) -> Dictionary:
	return table().get(id, tutorial_table().get(id, {}))


## 这一条挂的开关：switch 字串或字串表，空串 / 缺 = 只看总开关
static func switch_keys(e: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var sw = e.get("switch", "")
	if sw is String:
		if sw != "":
			out.append(sw)
	elif sw is Array:
		for k in sw:
			if str(k) != "":
				out.append(str(k))
	return out


## 总开关与这一条自己的开关都开着
static func switches_on(id: String) -> bool:
	if not Switches.on(SWITCH):
		return false
	var e := entry(id)
	if e.is_empty():
		return false
	for k in switch_keys(e):
		if not Switches.on(k):
			return false
	return true


static func flag_of(id: String) -> String:
	return (TUTORIAL_FLAG_PREFIX if not table().has(id) and tutorial_table().has(id) else FLAG_PREFIX) + id


## GameState（autoload 按路径取；探针里没挂就当一张没看过、也记不下）
static func _state() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("GameState")
	return null


static func is_read(id: String) -> bool:
	var gs := _state()
	return gs != null and gs.has_method("has_flag") and bool(gs.call("has_flag", flag_of(id)))


static func mark_read(id: String) -> void:
	var gs := _state()
	if gs != null and gs.has_method("set_flag"):
		gs.call("set_flag", flag_of(id))


## 这一条该不该出：开关全开、还没看过
static func want(id: String) -> bool:
	return switches_on(id) and not is_read(id)


## 停多久（秒）：按正文字数
static func hold_s(text: String) -> float:
	return clampf(HOLD_BASE + HOLD_PER_CHAR * float(text.length()), HOLD_MIN, HOLD_MAX)


## 排一张：该出（want）且这一页还没排过才排，返回排上没有。host 下没有小笺层就挂一层
static func offer(host: Node, id: String) -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return false
	if not want(id):
		return false
	var lay := layer_of(host, true)
	return lay != null and bool(lay.call("push", id))


## host 下的小笺层；make 为真时没有就挂一层
static func layer_of(host: Node, make := false) -> CanvasLayer:
	if host == null or not is_instance_valid(host):
		return null
	var n := host.get_node_or_null(NODE_NAME)
	if n is CanvasLayer and not n.is_queued_for_deletion():
		return n as CanvasLayer
	if not make:
		return null
	var lay: CanvasLayer = (load("res://scripts/ui/CombatNotes.gd") as GDScript).new()
	lay.name = NODE_NAME
	host.add_child(lay)
	return lay


# ── 小笺层 ──────────────────────────────────────────

func _ready() -> void:
	layer = LAYER_INDEX
	add_to_group(GROUP)


## 排进队尾；正出着的、已排着的不重排
func push(id: String) -> bool:
	if id == "" or id == _cur or _queue.has(id):
		return false
	_queue.append(id)
	return true


## 正出着的那一张（空 = 没有）与还排着的（探针看）
func current() -> String:
	return _cur


func pending() -> PackedStringArray:
	return _queue.duplicate()


## 正出着的小笺节点（探针量排版、读字）
func slip() -> PanelContainer:
	return _slip


## 收起正出着的那一张（点小笺、探针）；下一张照空 BETWEEN 秒再出
func dismiss() -> void:
	if _slip != null and not _closing:
		_close()


## 撤下一张（lane w54-tutorial：随事件面板的那张，面板收起就撤）：正出着就收起，还排着就从队里拿掉（没出的不记已读）
func withdraw(id: String) -> void:
	if id != "" and id == _cur:
		dismiss()
	elif _queue.has(id):
		_queue.remove_at(_queue.find(id))


func _process(delta: float) -> void:
	if _slip != null:
		_lay_acc += delta
		if _lay_acc >= LAYOUT_EVERY:
			_lay_acc = 0.0
			_layout()
		if not _closing:
			_left -= delta
			if _left <= 0.0:
				_close()
		return
	if _wait > 0.0:
		_wait -= delta
		return
	while not _queue.is_empty():
		var id := _queue[0]
		_queue.remove_at(0)
		# 排上以后开关关了、或别处已出过：跳过不出
		if want(id):
			_show(id)
			return


func _show(id: String) -> void:
	var e := entry(id)
	mark_read(id)
	_cur = id
	_closing = false
	_left = hold_s(str(e.get("text", "")))
	_slip = _build(e)
	add_child(_slip)
	_lay_acc = 0.0
	_layout()
	_slip.modulate.a = 0.0
	var tw := _slip.create_tween()
	tw.tween_property(_slip, "modulate:a", 1.0, T_IN)


func _close() -> void:
	_closing = true
	var s := _slip
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, T_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s):
			s.queue_free()
		if _slip == s:
			_slip = null
			_cur = ""
			_closing = false
			_wait = BETWEEN)


func _on_slip_input(event: InputEvent) -> void:
	var tap := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	tap = tap or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tap:
		get_viewport().set_input_as_handled()
		dismiss()


## 一张小笺：宣纸卡（同敌情列的纸色）上一行小题（泥金马善政，右边淡字「旁注」），底下正文文楷 16 号折行
func _build(e: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "NoteSlip"
	UiTheme.paper_card(card)
	card.self_modulate = UiTheme.DOOR_PAPER_TINT
	card.custom_minimum_size = Vector2(SLIP_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "点一下收起"
	card.gui_input.connect(_on_slip_input)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)
	var title := Label.new()
	title.name = "NoteTitle"
	title.text = str(e.get("title", ""))
	title.add_theme_font_override("font", UiTheme.title_font())
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.PAPER_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var aside := Label.new()
	aside.text = "旁注"
	aside.add_theme_font_override("font", UiTheme.font())
	aside.add_theme_font_size_override("font_size", UiTheme.PAPER_MIN_PX)
	aside.add_theme_color_override("font_color", UiTheme.PAPER_DIM)
	aside.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(aside)
	var text := Label.new()
	text.name = "NoteText"
	text.text = str(e.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(SLIP_W - 24.0, 0)
	text.add_theme_font_override("font", UiTheme.font())
	text.add_theme_font_size_override("font_size", UiTheme.PAPER_MIN_PX)
	text.add_theme_color_override("font_color", UiTheme.PAPER_TEXT)
	body.add_child(text)
	return card


## 摆位：贴画布右缘（按卡的实宽——纸卡样式自带几 px 边，比 SLIP_W 宽），顶匾之下；海战里再让到敌情列
## （连选中小卡）之下、右缘与它对齐，小地图之上；海图上让到罗盘之下。挤不下往上让（宁可压一角敌情列，不压小地图）
func _layout() -> void:
	if _slip == null:
		return
	var cv := Kit.canvas_size(self)
	var host := get_parent()
	var top := TOP_FALLBACK
	var bottom := cv.y - MARGIN
	var right := cv.x - MARGIN
	if host != null:
		for c in _above(host):
			var r := (c as Control).get_global_rect()
			top = maxf(top, r.end.y + GAP)
			if c.name == "IntelCard":
				right = minf(r.end.x, cv.x)
		var mini := host.get_node_or_null("CanvasLayer/HUD/MinimapPanel") as Control
		if mini != null and mini.is_visible_in_tree() and mini.size.y > 0.0:
			bottom = minf(bottom, mini.get_global_rect().position.y - GAP)
	_slip.reset_size()
	var h := _slip.size.y
	if top + h > bottom:
		top = maxf(TOP_FALLBACK, bottom - h)
	_slip.position = Vector2(right - _slip.size.x, top)


## 小笺要让在下面的几块（在才算）：海战顶匾与敌情列、海图罗盘、港页顶匾
func _above(host: Node) -> Array:
	var out: Array = []
	var cands: Array = [host.get_node_or_null("CanvasLayer/HUD/TideBar"), host.get("_status_strip"), host.get("compass")]
	for n in host.get_children():
		if n.is_in_group("nk1_combat_status"):
			cands.append(n.get("_intel"))
	for c in cands:
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).size.y > 0.0:
			out.append(c)
	return out
