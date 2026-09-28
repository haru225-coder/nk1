## 接舷阶段覆盖层：钩索线 + 旧绢阶段题签（接舷 / 白刃 / 夺船 / 脱钩）。
## 不改白刃公式；只在判定前后加观感节拍。headless 下静态入口返回 null。
##
## finished 契约（lane gd17）：演完或被新一层顶掉（_abort）都恰好发一次——WorldMap._await_boarding_fx 裸 await 它，
## 顶掉不发的话那头永不醒。随父释放（WorldMap 结算 / 退出）不补发：唯一的等待方就是父 WorldMap，一起释放，
## 挂在本层信号上的协程随本层释放而丢弃、不泄漏；补发反倒让 WorldMap 在拆树途中接着跑 _battle_exit。
## 本层自己不 await：节拍全在 tween 回调里，被 kill / 随父释放不留挂起的协程。
extends CanvasLayer

signal finished

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")

const LAYER_INDEX := 55
const GROUP := "nk1_boarding_stage"
const T_HOLD := 0.55
const T_FADE := 0.28

var _root: Control
var _shade: ColorRect
var _slip: PanelContainer
var _title: Label
var _sub: Label
var _rope: Line2D
var _done := false


## 接舷开场：钩索 + 「接舷」题签。返回节点；headless 返回 null。
static func begin(parent: Node, from: Node2D, to: Node2D, subtitle := "") -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		n.call("_abort")
	var st: CanvasLayer = (load("res://scripts/combat/BoardingStage.gd") as GDScript).new()
	st.add_to_group(GROUP)
	parent.add_child(st)
	st.call("_play_begin", from, to, subtitle)
	return st


## 白刃结果题签（夺船 / 脱钩）。可在 begin 之后再调，或单独调。
static func resolve(parent: Node, outcome: String, detail := "") -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	var existing: CanvasLayer = null
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		existing = n as CanvasLayer
		break
	if existing != null:
		existing.call("_play_resolve", outcome, detail)
		return existing
	var st: CanvasLayer = (load("res://scripts/combat/BoardingStage.gd") as GDScript).new()
	st.add_to_group(GROUP)
	parent.add_child(st)
	st.call("_play_resolve", outcome, detail)
	return st


func _ready() -> void:
	layer = LAYER_INDEX
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(UiTheme.INK_SOLID.r, UiTheme.INK_SOLID.g, UiTheme.INK_SOLID.b, 0.18)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	_root.add_child(_shade)

	_slip = PanelContainer.new()
	_slip.add_theme_stylebox_override("panel", UiTheme.plaque())
	_slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slip.offset_top = 96.0
	_slip.offset_bottom = 96.0
	_slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_slip)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
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
	vb.add_child(_sub)

	_slip.modulate.a = 0.0


func _play_begin(from: Node2D, to: Node2D, subtitle: String) -> void:
	_title.text = "接舷"
	_sub.text = subtitle if subtitle != "" else "钩索已抛"
	_draw_rope(from, to)
	var tw := create_tween()
	tw.tween_property(_shade, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_slip, "modulate:a", 1.0, 0.22)
	CombatFx.hitstop(self, 0.06, 0.25)


func _play_resolve(outcome: String, detail: String) -> void:
	match outcome:
		"win", "board":
			_title.text = "夺船"
		"lose":
			_title.text = "脱钩"
		_:
			_title.text = "白刃"
	_sub.text = detail
	_slip.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(T_HOLD)
	tw.tween_property(_slip, "modulate:a", 0.0, T_FADE)
	tw.parallel().tween_property(_shade, "modulate:a", 0.0, T_FADE)
	tw.tween_callback(_finish)


func _draw_rope(from: Node2D, to: Node2D) -> void:
	if from == null or to == null or not is_instance_valid(from) or not is_instance_valid(to):
		return
	# 钩索画在战场父节点（WorldMap）上，随船移动一帧足够
	var host := get_parent()
	if host == null:
		return
	_rope = Line2D.new()
	_rope.width = 2.0
	_rope.default_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.85)
	_rope.z_index = 30
	_rope.points = PackedVector2Array([from.global_position, to.global_position])
	host.add_child(_rope)
	var tw := create_tween()
	tw.tween_property(_rope, "modulate:a", 0.0, T_HOLD + T_FADE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_rope):
			_rope.queue_free()
	)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _abort() -> void:
	if is_instance_valid(_rope):
		_rope.queue_free()
	_finish()
