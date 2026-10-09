## 白刃三决断拍板层（lane w53-p4-melee，战斗方案四期 §五 第 5 条）：舷边 / 舷腰 / 桅下各停一拍，
## 亮出当前两船人数与士气，玩家选「压上」（推进快、伤亡多）或「收势」（稳、慢，可能被反推）。
## 输入三路：Enter = 收势（题签下注的默认）、Space = 压上；点两钮；触屏同点两钮。
## 超时 DECISION_TIMEOUT 秒没拍自动走自动口径（本层的 res 带 timed_out=true，白刃不卡死）。
## M = 本场切回自动 / 切回拍板（只活在本场内存，不进存档、不动 CombatSwitches）。
##
## 契约（WorldMap._board_enemy 分段调度的半边 – 「有没有玩家要拍」由 WorldMap 定，本层只管拍）：
##   offer(parent, site) → 亮一拍，返回本层（headless / 不在树返 null）；
##   await layer.decided → 一拍落定（1 压上 / 0 收势 / -1 自动 == 超时 / abort / set_auto(true)）；
##   decided 契齐恰好发一次：timer 到点、玩家按键 / 点钮、abort 殊途同归 _answer；本层不随父补发——
##   唯一的等待方就是父 WorldMap，一起释放时挂在本层信号上的协程随本层释放而丢弃、不泄漏（同 BoardingStage 头注）。
extends CanvasLayer

## 玩家拍定一拍（1 压上 / 0 收势 / -1 自动）：WorldMap 的 _await_decision 只 await 它
signal decided(mode: int)

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const MeleeResolve := preload("res://scripts/combat/MeleeResolve.gd")

const LAYER_INDEX := 56
const GROUP := "nk1_melee_decision"
## 决断时限（秒）：过了它照自动口径走；白刃六合约四秒一拍，不给玩家白等一整场
const DECISION_TIMEOUT := 5.0
const T_FADE := 0.18

var _slip: PanelContainer
var _title: Label
var _sub: Label
var _note: Label
var _buttons: Array[Button] = []
var _count_bar: ProgressBar = null
var _ask := false
## 本场切回自动（M 切）：开关开在、玩家 M 关本场拍板时 true；只活在这一场内存里
var battle_auto := false
var _timeout_left := 0.0


## 本层此刻在等吗：WorldMap 每合只问一次（offer 直下）；探针摆拍看 waiting + battle_auto 两条
func waiting() -> bool:
	return _ask


## 本场切回自动 / 切回拍板（M）：切自动挂着的这一拍照自动放掉
func set_battle_auto(v: bool) -> void:
	if battle_auto == v:
		return
	battle_auto = v
	if battle_auto and _ask:
		_answer(-1)
	elif not battle_auto:
		_note_refresh()


## 敌船换了 / 本船失守等：挂着的拍子放掉（照自动，不记作玩家选的）
func abort() -> void:
	if _ask:
		_answer(-1)


## 探针按下判定路径（与 _unhandled_input 同一条 _answer）：Enter = 收势、Space = 压上、M = 切自动
func q_press(key: int) -> void:
	match key:
		KEY_ENTER, KEY_KP_ENTER:
			_answer(0)
		KEY_SPACE:
			_answer(1)
		KEY_M:
			set_battle_auto(true)


## 亮一拍（site = MeleeResolve 写进结果里的 decisions_site）；headless / 不在树返回 null
static func offer(parent: Node, site: Dictionary) -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	var st: CanvasLayer = null
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		if n.is_queued_for_deletion():
			continue
		st = n as CanvasLayer
		break
	if st == null:
		st = (load("res://scripts/ui/MeleeDecisionPanel.gd") as GDScript).new()
		st.add_to_group(GROUP)
		parent.add_child(st)
	st.call("_present", site)
	return st


func _ready() -> void:
	layer = LAYER_INDEX
	_build()
	set_process(false)


func _build() -> void:
	_slip = PanelContainer.new()
	_slip.add_theme_stylebox_override("panel", UiTheme.plaque())
	_slip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_slip.offset_top = -96.0
	_slip.offset_bottom = -96.0
	_slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_slip)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_slip.add_child(vb)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiTheme.font())
	_title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_title)

	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", UiTheme.font())
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(460, 0)
	vb.add_child(_sub)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_override("font", UiTheme.font())
	_note.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	vb.add_child(_note)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vb.add_child(btn_row)

	var push := _make_button("压上（Space）")
	push.pressed.connect(_answer.bind(1))
	btn_row.add_child(push)
	_buttons.append(push)

	var hold := _make_button("收势（Enter）")
	hold.pressed.connect(_answer.bind(0))
	btn_row.add_child(hold)
	_buttons.append(hold)

	var auto := _make_button("本场自动（M）")
	auto.pressed.connect(set_battle_auto.bind(true))
	btn_row.add_child(auto)
	_buttons.append(auto)

	_count_bar = ProgressBar.new()
	_count_bar.min_value = 0.0
	_count_bar.max_value = 1.0
	_count_bar.value = 1.0
	_count_bar.show_percentage = false
	_count_bar.custom_minimum_size = Vector2(220, 5)
	_count_bar.modulate.a = 0.55
	vb.add_child(_count_bar)

	_slip.modulate.a = 0.0
	visible = false


static func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", UiTheme.font())
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	b.focus_mode = Control.FOCUS_NONE
	return b


## 亮一拍：site 是 MeleeResolve 写进结果的 decisions_site（front / n / a_word / d_word / 双方人数士气）
func _present(site: Dictionary) -> void:
	if battle_auto:
		# 已切自动：WorldMap 本不会再 offer；探针直接 offer 的按自动放掉（不等玩家）
		_answer.call_deferred(-1)
		return
	visible = true
	_ask = true
	_timeout_left = DECISION_TIMEOUT
	_title.text = "白刃・%s" % MeleeResolve.zone_name(int(site.get("front", 0)))
	_sub.text = "%s %d 人　士气 %d　｜　%s %d 人　士气 %d" % [
		str(site.get("a_word", "我")), int(site.get("att", 0)), int(site.get("att_morale", 0)),
		str(site.get("d_word", "敌")), int(site.get("def", 0)), int(site.get("def_morale", 0))]
	for b in _buttons:
		b.disabled = false
	_note_refresh()
	_count_bar.value = 1.0
	_slip.modulate.a = 1.0
	set_process(true)


func _note_refresh() -> void:
	_note.text = "压上：推进快、伤亡多　｜　收势：稳、慢，可能被反推　｜　%ds 不动自动" % int(DECISION_TIMEOUT)


func _process(delta: float) -> void:
	if not _ask:
		set_process(false)
		return
	_timeout_left -= delta
	_count_bar.value = clampf(_timeout_left / DECISION_TIMEOUT, 0.0, 1.0)
	if _timeout_left <= 0.0:
		_answer(-1)


func _answer(mode: int) -> void:
	if not _ask:
		return
	_ask = false
	for b in _buttons:
		b.disabled = true
	var tw := create_tween()
	tw.tween_property(_slip, "modulate:a", 0.0, T_FADE)
	tw.tween_callback(func() -> void: visible = false)
	decided.emit(mode)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not _ask or battle_auto:
		# 没在被问时只吃 M（切回拍板）；其余不挡海战键
		if key.keycode == KEY_M:
			set_battle_auto(false)
			get_viewport().set_input_as_handled()
		return
	q_press(key.keycode)
	get_viewport().set_input_as_handled()
