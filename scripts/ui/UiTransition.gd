## 工席成功态的短过渡（JRPG 味）：画面淡入焦墨 → 中央一枚旧绢题签自左擦出（题名 + 小朱印）、副题浮起 →
## 停一拍 → 题签与墨幕一起淡去，回到玩法界面。约 2.4 秒；停顿时点一下直接收场。
## 不是分镜过场（那是 CutscenePlayer + data/cutscenes.json）；色、字全取 UiTheme，不出新图。
##
##   var t := UiTransition.play(parent, "贡院・赴试", "景定五年三月初九", on_black)
##   if t != null: await t.finished
##
## on_black 在墨幕全黑那一刻调一次（Main 在这时 load_scene，页面在黑幕底下换好，揭开就是新页）。
## headless 与 -s 工具脚本（门禁、巡检、smoke）下不建节点、返回 null——调用方自己当帧调 on_black（见 Main.play_transition）。
## 墨幕在场时吞掉鼠标，防止连点；不暂停游戏、不入存档。
##
## 协程不许挂死（lane gd17，同 CombatLetterbox gd15 写法）：_run 的等待只走 _await_tween / _await_frame 两个挂起点，
## 不直接 await tween 的 finished 或 get_tree().process_frame——被顶掉（_abort）后本节点释放、tween 随之作废不发 finished，
## 协程永不醒，栈上的 tween 与挂起的 GDScriptFunctionState 互相引住，退出报 ObjectDB 泄漏；停拍中随父释放还报
## 「after await, but class instance is gone」。收场（演完 / _abort / 离树）一律走 _cancel_waits：kill tween、当场唤醒，
## 协程醒来见 _done 就自退。随父释放 / 退出不补发 finished：唯一的等待方 Main.play_transition 就是父，一起释放
## （等在别人信号上的协程随信号源释放而丢弃，不泄漏）；补发反倒让 Main 在拆树途中接着跑调用方的后续逻辑。
extends CanvasLayer

signal covered
signal finished
## 内部：挂起点的唤醒（tween 放完 / 下一帧到 / 收场），只由 _wake 与 _cancel_waits 发
signal _woken

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

## 章节卡 55 之上、管线预热 127 之下；抵港横幅 40 被墨幕盖住
const LAYER_INDEX := 60
const GROUP := "nk1_ui_transition"
const T_FADE_IN := 0.32
const T_WIPE := 0.42
const T_SUB := 0.28
const T_HOLD := 1.0
const T_OUT := 0.42
## 题签中线在画布高度的比例（偏上，给副题留地方）
const Y_FRAC := 0.42

var title := ""
var subtitle := ""
var seal_text := ""
var _on_black := Callable()
var _root: Control
var _shade: ColorRect
var _clip: Control
var _slip: PanelContainer
var _sub: Label
var _holding := false
var _go_early := false
var _black_done := false
var _done := false
var _tween: Tween
## 挂起点序号：作废后才到的回调（已 kill 的 tween 不会再来，但 process_frame 的会）对不上就丢掉
var _wait_seq := 0


## 题签标题只写可核对的事实：章次 / 章节名 / 抵达港名；日期、年号由调用方从历法传入。
## 不在这里编剧情，也不把「到港」写成教程式提示。这样章节卡、抵港横幅和工席
## 成功态能共享同一套题签，而不会各自长出一套现代 UI 文案。
static func chapter_title(chapter_no: int, chapter_name: String) -> String:
	var name := chapter_name.strip_edges()
	var head := "第%s章" % _cn_small(maxi(chapter_no, 1))
	return head if name == "" else "%s・%s" % [head, name]


static func port_title(port_name: String) -> String:
	var name := port_name.strip_edges()
	return "抵港" if name == "" else "抵港・%s" % name


## 序章题签：只写可核对的位置——卷首（标题→四方沙盘）与兴化海口（沙盘末→酒棚）。
## 年号/日期由调用方从 Calendar 传入；朱印用「序」。不动分支图。
static func prologue_open_title() -> String:
	return "序章・卷首"


static func prologue_shore_title() -> String:
	return "序章・兴化海口"


static func prologue_open(parent: Node, subtitle := "", on_black := Callable()) -> CanvasLayer:
	return play(parent, prologue_open_title(), subtitle, on_black, "序")


static func prologue_shore(parent: Node, subtitle := "", on_black := Callable()) -> CanvasLayer:
	return play(parent, prologue_shore_title(), subtitle, on_black, "序")


## 守城 / 终局题签：同序章文法，只写可核对的地名与结局名。守城印「城」，终局印「终」。
## 副题（日期、终局时地）由调用方从 Calendar / GameState.ended_at 传入。只在首次进岸带时演，分支与数值不经此处。
static func siege_title() -> String:
	return "兴化军・围城"


static func endgame_title(port_name: String, ending_name: String) -> String:
	var port := port_name.strip_edges()
	var ending := ending_name.strip_edges()
	if ending == "":
		return "终局" if port == "" else "%s・终局" % port
	return ending if port == "" else "%s・%s" % [port, ending]


static func siege_open(parent: Node, subtitle := "", on_black := Callable()) -> CanvasLayer:
	return play(parent, siege_title(), subtitle, on_black, "城")


static func endgame_open(parent: Node, port_name: String, ending_name: String, subtitle := "",
		on_black := Callable()) -> CanvasLayer:
	return play(parent, endgame_title(port_name, ending_name), subtitle, on_black, "终")


## 船屋成功题签：港名・事由（修船／购入／升帆／升甲／换坞）。只写可核对事实；朱印一字。
## 副题（日期）由调用方从 Calendar 传入。费用与门槛不经此处。
static func drydock_title(port_name: String, act: String) -> String:
	var port := port_name.strip_edges()
	var action := act.strip_edges()
	if action == "":
		return "船屋" if port == "" else "%s・船屋" % port
	return action if port == "" else "%s・%s" % [port, action]


static func drydock_seal(act: String) -> String:
	match act.strip_edges():
		"修船":
			return "修"
		"购入":
			return "购"
		"升帆":
			return "帆"
		"升甲":
			return "甲"
		"换坞":
			return "坞"
		_:
			return "船"


static func drydock_open(parent: Node, port_name: String, act: String, subtitle := "",
		on_black := Callable()) -> CanvasLayer:
	return play(parent, drydock_title(port_name, act), subtitle, on_black, drydock_seal(act))


## 章晋升翻页题签：有跳年写「%s年后」或「%s年后・章名」；无跳年只写章名。朱印「晋」。
## 年数用「两/三/四」；不编剧情评语。副题（日期）由调用方从 Calendar 传入。
static func _cn_years(n: int) -> String:
	if n == 2:
		return "两"
	return _cn_small(n)


static func promote_title(years: int, chapter_name: String) -> String:
	var name := chapter_name.strip_edges()
	if years > 0:
		var head := "%s年后" % _cn_years(years)
		return head if name == "" else "%s・%s" % [head, name]
	return name if name != "" else "晋升"


static func promote_open(parent: Node, years: int, chapter_name: String, subtitle := "",
		on_black := Callable()) -> CanvasLayer:
	return play(parent, promote_title(years, chapter_name), subtitle, on_black, "晋")


static func _cn_small(n: int) -> String:
	var digits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 10:
		return digits[n]
	if n == 10:
		return "十"
	if n < 20:
		return "十" + digits[n - 10]
	var tens := int(n / 10)
	return digits[tens] + "十" + (digits[n % 10] if n % 10 > 0 else "")


## seal_text：题签末尾的小朱印（一个字，如「试」「行」）；空串不盖。
static func play(parent: Node, p_title: String, p_subtitle := "", on_black := Callable(), p_seal := "") -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	# 同时只留一幕：旧的立刻收场（没到全黑的先把它的 on_black 补调，调用方的 await 照常返回）
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		n.call("_abort")
	var t: CanvasLayer = (load("res://scripts/ui/UiTransition.gd") as GDScript).new()
	t.title = p_title
	t.subtitle = p_subtitle
	t.seal_text = p_seal
	t._on_black = on_black
	t.add_to_group(GROUP)
	parent.add_child(t)
	return t


func _ready() -> void:
	layer = LAYER_INDEX
	_build()
	_run()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = UiTheme.INK_SOLID
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	_root.add_child(_shade)

	# 题签：旧绢底、上下泥金细线、焦墨题字（马善政），末钤小朱印
	_slip = PanelContainer.new()
	_slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PAPER_CARD if UiTheme.IS_JUANBEN else UiTheme.INK_SOFT
	box.border_color = UiTheme.GOLD
	box.border_width_top = 2
	box.border_width_bottom = 2
	box.content_margin_left = 56
	box.content_margin_right = 44
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 14
	_slip.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_slip.add_child(row)

	var head := Label.new()
	head.text = title
	head.add_theme_font_override("font", UiTheme.title_font())
	head.add_theme_font_size_override("font_size", 48 if title.length() <= 5 else 40)
	head.add_theme_color_override("font_color", UiTheme.PAPER_TEXT if UiTheme.IS_JUANBEN else UiTheme.GOLD_HI)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(head)

	if seal_text != "":
		var seal := Label.new()
		seal.text = seal_text
		seal.add_theme_font_override("font", UiTheme.title_font())
		seal.add_theme_font_size_override("font_size", 24)
		seal.add_theme_color_override("font_color", UiTheme.SEAL_TEXT)
		seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal.custom_minimum_size = Vector2(40, 40)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.SEAL
		sb.set_corner_radius_all(3)
		seal.add_theme_stylebox_override("normal", sb)
		seal.rotation = -0.06
		row.add_child(seal)

	# 擦出：题签放在一个裁切框里，框宽 0 → 全宽
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_clip)
	_clip.add_child(_slip)

	_sub = Label.new()
	_sub.text = subtitle
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", UiTheme.font())
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.modulate.a = 0.0
	_sub.visible = subtitle != ""
	_root.add_child(_sub)
	_layout()


func _layout() -> void:
	var cv := Kit.canvas_size(self)
	var sz := _slip.get_combined_minimum_size()
	_slip.size = sz
	_slip.position = Vector2.ZERO
	var y := roundf(cv.y * Y_FRAC - sz.y * 0.5)
	# 阴影会被裁掉一截，框上下各多留 16
	_clip.position = Vector2(roundf((cv.x - sz.x) * 0.5), y - 16.0)
	_slip.position.y = 16.0
	_clip.size = Vector2(_clip.size.x, sz.y + 32.0)
	_clip.set_meta(&"full_w", sz.x)
	_sub.size = Vector2(cv.x, 0)
	_sub.position = Vector2(0, y + sz.y + 22.0)


func _run() -> void:
	_tween = create_tween()
	_tween.tween_property(_shade, "modulate:a", 1.0, T_FADE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if not await _await_tween():
		return
	_black()

	_clip.size.x = 0.0
	_tween = create_tween()
	_tween.tween_property(_clip, "size:x", float(_clip.get_meta(&"full_w")), T_WIPE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_slip, "position:x", 0.0, T_WIPE).from(-24.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _sub.visible:
		_tween.tween_property(_sub, "modulate:a", 1.0, T_SUB)
		_tween.parallel().tween_property(_sub, "position:y", _sub.position.y, T_SUB).from(_sub.position.y + 8.0)
	if not await _await_tween():
		return

	_holding = true
	var left := T_HOLD
	while left > 0.0 and not _go_early:
		if not await _await_frame():
			return
		left -= get_process_delta_time()
	_holding = false

	_tween = create_tween()
	_tween.tween_property(_clip, "modulate:a", 0.0, T_OUT * 0.5)
	_tween.parallel().tween_property(_sub, "modulate:a", 0.0, T_OUT * 0.5)
	_tween.tween_property(_shade, "modulate:a", 0.0, T_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not await _await_tween():
		return
	_finish()


## 挂起点一：等刚排好的 _tween 放完。醒来仍在演返回 true；中途收场返回 false，调用方自退。
func _await_tween() -> bool:
	if _done:
		return false
	_wait_seq += 1
	_tween.finished.connect(_wake.bind(_wait_seq), CONNECT_ONE_SHOT)
	await _woken
	return not _done


## 挂起点二：等下一帧（同 await get_tree().process_frame 的时机）。已离树或已收场直接返回 false。
func _await_frame() -> bool:
	if _done or not is_inside_tree():
		return false
	_wait_seq += 1
	get_tree().process_frame.connect(_wake.bind(_wait_seq), CONNECT_ONE_SHOT)
	await _woken
	return not _done


func _wake(seq: int) -> void:
	if seq == _wait_seq:
		_woken.emit()


## 收场时作废等待（调用方先置 _done）：kill tween、让还没到的回调过期，并当场唤醒挂着的协程。
func _cancel_waits() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_wait_seq += 1
	_woken.emit()


## 墨幕在场时吞掉键盘（Esc 等热键不穿到底下的页面）与鼠标按键；停顿中按键或点一下直接收场。
## 鼠标按键也在这里吞：_root 只挡得住 GUI，挡不住底下别的 _input——停拍里点一下收墨幕，同一下还会落到黑幕底下
## 刚换好的新页上（四方沙盘页 TitleStage 的标题演出当场补全；lane w53-9 实测）。
func _input(event: InputEvent) -> void:
	if _done:
		return
	var press: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed)
	if press and _holding:
		_go_early = true
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _black() -> void:
	if _black_done:
		return
	_black_done = true
	covered.emit()
	if _on_black.is_valid():
		_on_black.call()


func _abort() -> void:
	remove_from_group(GROUP)
	_black()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_cancel_waits()
	finished.emit()
	queue_free()


## 没演完就离树（随父释放 / 退出）：只唤醒协程让它自退，不补发 finished、不补调 on_black，理由见头注释。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and not _done:
		_done = true
		_cancel_waits()
