## 进出海战的上下墨边（letterbox）：焦墨宽边自上下合拢 → 下边里一行题签自左擦出（小朱印 + 题名 + 泥金竖线 + 副题）→
## 停一拍 → 题签淡去、墨边退开。底下的海面始终看得见，不是 UiTransition 那种全黑墨幕。
## 题签写法与 UiTransition 同一路：只写可核对的事实——「海名・事由」，副题是历法日期与敌船数，不写评语。
##
##   var lb := CombatLetterbox.enter(self, CombatLetterbox.sea_title("刺桐外海", "接舷"), "咸淳三年六月十二　海鹘二艘")
##   var lb := CombatLetterbox.exit(self, CombatLetterbox.outcome_title("win", "刺桐外海"), sub, on_black)
##   if lb != null: await lb.finished
##
## 出战带 on_black 时墨边一直合到中线（全黑）再调它，调用方趁黑换场景，墨边随后退开；不带就和入战一样只留边。
## headless 与 -s 工具脚本（门禁、smoke）下静态入口不建节点、返回 null——调用方自己当帧调 on_black（同 Main.play_transition）。
## 入战不吞输入（开炮倒计时照走，题签只盖在上下边里）；出战合拢时吞键盘和鼠标，防止连按。不暂停游戏、不入存档。
extends CanvasLayer

signal caption_shown
signal covered
signal finished

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

## 海战 HUD（WorldMap 的 CanvasLayer 1）之上、UiTransition 墨幕 60 之下
const LAYER_INDEX := 58
const GROUP := "nk1_combat_letterbox"
## 单边墨边占画布高度的比例：720 高时 90px，HUD 顶匾与底栏各让出一条
const BAR_FRAC := 0.125
const T_BAR_IN := 0.46
const T_WIPE := 0.40
const T_SUB := 0.26
const T_HOLD := 1.3
const T_CAPTION_OUT := 0.24
const T_BAR_OUT := 0.50
const T_SHUT := 0.36
## 题签离画布左缘
const CAPTION_X := 64.0
const TITLE_SIZE := 34
const SEAL_ENTER := "战"
const SEAL_EXIT := "毕"

## 出战结局 → 事由。结局键与 WorldMap._battle_exit 同名（win / lose / flee），board 为白刃夺船
const OUTCOME_ACT := {
	"win": "战罢",
	"board": "夺船",
	"flee": "脱战",
	"lose": "败退",
}

var title := ""
var subtitle := ""
var seal_text := ""

var _root: Control
var _top: ColorRect
var _bottom: ColorRect
var _top_line: ColorRect
var _bottom_line: ColorRect
var _clip: Control
var _caption: HBoxContainer
var _head: Label
var _seal: Label
var _rule: ColorRect
var _sub: Label
var _built := false
var _run_id := 0
var _tween: Tween
var _swallow := false
var _black_done := false
var _on_black := Callable()


## 「海名・事由」。海名空着就只写事由，不在这里补地名。
static func sea_title(sea_name: String, act: String) -> String:
	var sea := sea_name.strip_edges()
	var a := act.strip_edges()
	if sea == "":
		return a
	return sea if a == "" else "%s・%s" % [sea, a]


static func outcome_title(outcome: String, sea_name := "") -> String:
	return sea_title(sea_name, OUTCOME_ACT.get(outcome, "战罢"))


## 敌船数副题：「海鹘二艘・铁子一艘」。entry 形同 pending_battle.enemy（type / count），船名取 Fleet 船种表。
static func enemy_note(enemy_list: Array) -> String:
	var parts: PackedStringArray = []
	for entry in enemy_list:
		if not entry is Dictionary:
			continue
		var count := int(entry.get("count", 1))
		if count <= 0:
			continue
		var type_id := String(entry.get("type", ""))
		var ship_name := String(Fleet.ship_def(type_id).get("name", "敌船"))
		parts.append("%s%s艘" % [ship_name, _cn_count(count)])
	return "・".join(parts)


static func _cn_count(n: int) -> String:
	var digits := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if n < 10:
		return digits[n]
	if n < 20:
		return "十" + (digits[n - 10] if n > 10 else "")
	if n < 100:
		return digits[int(n / 10)] + "十" + (digits[n % 10] if n % 10 else "")
	return str(n)


## 入战：墨边合拢、题签、退开。返回的节点演完自删。
static func enter(parent: Node, p_title: String, p_subtitle := "") -> CanvasLayer:
	var lb := _spawn(parent)
	if lb != null:
		lb.call("play_enter", p_title, p_subtitle)
	return lb


## 出战：题签后若带 on_black，墨边合到全黑时调一次，再退开。
static func exit(parent: Node, p_title: String, p_subtitle := "", on_black := Callable()) -> CanvasLayer:
	var lb := _spawn(parent)
	if lb != null:
		lb.call("play_exit", p_title, p_subtitle, on_black)
	return lb


static func _spawn(parent: Node) -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	# 同时只留一副墨边：旧的立刻收场（没到全黑的先补调它的 on_black）
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		n.call("_abort")
	var lb: CanvasLayer = (load("res://scripts/ui/CombatLetterbox.gd") as GDScript).new()
	lb.set_meta(&"auto_free", true)
	lb.add_to_group(GROUP)
	parent.add_child(lb)
	return lb


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func play_enter(p_title: String, p_subtitle := "") -> void:
	_start(p_title, p_subtitle, SEAL_ENTER)
	var id := _run_id
	if not await _bars_in(id):
		return
	await _hold_and_open(id)


func play_exit(p_title: String, p_subtitle := "", on_black := Callable()) -> void:
	_start(p_title, p_subtitle, SEAL_EXIT)
	_on_black = on_black
	var id := _run_id
	if not await _bars_in(id):
		return
	if not _on_black.is_valid():
		await _hold_and_open(id)
		return
	if not await _hold(id):
		return
	_swallow = true
	var half := Kit.canvas_size(self).y * 0.5
	_tween = create_tween()
	_tween.tween_property(_clip, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.tween_property(_top, "size:y", half + 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_bottom, "size:y", half + 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_bottom, "position:y", half - 1.0, T_SHUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_top_line, "modulate:a", 0.0, T_SHUT)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 0.0, T_SHUT)
	await _tween.finished
	if id != _run_id:
		return
	_black()
	# 换场景那一帧常卡一下，停两帧再揭，揭开就是新页
	await get_tree().process_frame
	await get_tree().process_frame
	if id != _run_id:
		return
	_tween = create_tween()
	_tween.tween_property(_top, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", half * 2.0, T_BAR_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _tween.finished
	if id != _run_id:
		return
	_swallow = false
	_finish()


## 当前单边墨边高（探针量排版用）
func bar_height() -> float:
	return roundf(Kit.canvas_size(self).y * BAR_FRAC)


## 题签整行在画布上的矩形（探针量是否落在下边里）
func caption_rect() -> Rect2:
	return Rect2(_clip.position + _caption.position, _caption.size)


func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_top = _bar()
	_bottom = _bar()
	# 墨边内沿一道泥金细线，压在画面与墨边交界上
	_top_line = _hairline()
	_bottom_line = _hairline()

	_caption = HBoxContainer.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.alignment = BoxContainer.ALIGNMENT_BEGIN
	_caption.add_theme_constant_override("separation", 18)

	_seal = Label.new()
	_seal.add_theme_font_override("font", UiTheme.title_font())
	_seal.add_theme_font_size_override("font_size", 22)
	_seal.add_theme_color_override("font_color", UiTheme.SEAL_TEXT)
	_seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seal.custom_minimum_size = Vector2(36, 36)
	_seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.SEAL
	sb.set_corner_radius_all(3)
	_seal.add_theme_stylebox_override("normal", sb)
	_seal.rotation = -0.06
	_caption.add_child(_seal)

	_head = Label.new()
	_head.add_theme_font_override("font", UiTheme.title_font())
	_head.add_theme_font_size_override("font_size", TITLE_SIZE)
	_head.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_child(_head)

	_rule = ColorRect.new()
	_rule.color = UiTheme.GOLD
	_rule.custom_minimum_size = Vector2(1, 30)
	_rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_rule)

	_sub = Label.new()
	_sub.add_theme_font_override("font", UiTheme.font())
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_sub)

	# 擦出：题签放在裁切框里，框宽 0 → 全宽
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_clip)
	_clip.add_child(_caption)


func _bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.INK_SOLID
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _hairline() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.GOLD, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


## 新的一幕：旧 tween 作废、旧协程按 _run_id 自退，排版从零开始
func _start(p_title: String, p_subtitle: String, p_seal: String) -> void:
	_build()
	_run_id += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_black_done = false
	_on_black = Callable()
	_swallow = false
	title = p_title
	subtitle = p_subtitle
	if seal_text == "":
		seal_text = p_seal
	_head.text = title
	_sub.text = subtitle
	_seal.text = seal_text
	_seal.visible = seal_text != ""
	_rule.visible = subtitle != ""
	_sub.visible = subtitle != ""
	seal_text = ""
	_layout()


func _layout() -> void:
	var cv := Kit.canvas_size(self)
	var h := bar_height()
	_top.position = Vector2.ZERO
	_top.size = Vector2(cv.x, 0.0)
	_bottom.position = Vector2(0.0, cv.y)
	_bottom.size = Vector2(cv.x, 0.0)
	_top_line.size = Vector2(cv.x, 1.0)
	_bottom_line.size = Vector2(cv.x, 1.0)
	_top_line.modulate.a = 0.0
	_bottom_line.modulate.a = 0.0
	_top_line.position = Vector2(0.0, h - 1.0)
	_bottom_line.position = Vector2(0.0, cv.y - h)

	var sz := _caption.get_combined_minimum_size()
	# 过长的题名缩字，不许冲出画布右缘
	var room := cv.x - CAPTION_X * 2.0
	if sz.x > room and _head.text.length() > 0:
		_head.add_theme_font_size_override("font_size", maxi(22, int(TITLE_SIZE * room / sz.x)))
		sz = _caption.get_combined_minimum_size()
	else:
		_head.add_theme_font_size_override("font_size", TITLE_SIZE)
		sz = _caption.get_combined_minimum_size()
	_caption.size = sz
	_caption.position = Vector2.ZERO
	# 题签行在下边里垂直居中；阴影与朱印倾斜会被裁，框上下各多留 8
	var y := roundf(cv.y - h + (h - sz.y) * 0.5)
	_clip.position = Vector2(CAPTION_X, y - 8.0)
	_caption.position.y = 8.0
	_clip.size = Vector2(0.0, sz.y + 16.0)
	_clip.set_meta(&"full_w", sz.x + 8.0)
	_clip.modulate.a = 1.0


## 墨边合拢 + 题签擦出。被新一幕打断时返回 false。
func _bars_in(id: int) -> bool:
	var cv := Kit.canvas_size(self)
	var h := bar_height()
	_tween = create_tween()
	_tween.tween_property(_top, "size:y", h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", cv.y - h, T_BAR_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_top_line, "modulate:a", 1.0, 0.18)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 1.0, 0.18)
	_tween.parallel().tween_property(_clip, "size:x", float(_clip.get_meta(&"full_w")), T_WIPE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_caption, "position:x", 0.0, T_WIPE).from(-20.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _sub.visible:
		_sub.modulate.a = 0.0
		_tween.tween_property(_sub, "modulate:a", 1.0, T_SUB)
	await _tween.finished
	if id != _run_id:
		return false
	caption_shown.emit()
	return true


func _hold(id: int) -> bool:
	var left := T_HOLD
	while left > 0.0 and id == _run_id:
		await get_tree().process_frame
		left -= get_process_delta_time()
	return id == _run_id


func _hold_and_open(id: int) -> void:
	if not await _hold(id):
		return
	var cv := Kit.canvas_size(self)
	_tween = create_tween()
	_tween.tween_property(_clip, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.parallel().tween_property(_top_line, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.parallel().tween_property(_bottom_line, "modulate:a", 0.0, T_CAPTION_OUT)
	_tween.tween_property(_top, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_bottom, "size:y", 0.0, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_bottom, "position:y", cv.y, T_BAR_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	if id != _run_id:
		return
	_finish()


## 出战合拢时吞掉键盘与鼠标（B / Esc 不再穿到底下）；入战不拦。
func _input(event: InputEvent) -> void:
	if _swallow and (event is InputEventKey or event is InputEventMouseButton):
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
	_run_id += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 出战没到全黑就被顶掉：补调 on_black，调用方的换场不丢
	if _on_black.is_valid():
		_black()
	_finish()


func _finish() -> void:
	_swallow = false
	finished.emit()
	if get_meta(&"auto_free", false):
		queue_free()
