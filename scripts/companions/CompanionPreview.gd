extends Control
## 伙伴列表只读预览浮页（Lane Z3 / F7）。
## 从现有 characters 抽 6 人剪影卡 + 论文纪实短注；明确「草案预览」。
## 不接招募、不写数值、不入存档。Esc / 合上 / 再按 F7 / 点暗幕关闭。

signal closed

const Art := preload("res://scripts/ui/CharacterArt.gd")

## 草案预览固定六人：要人与职事各半，覆盖寺院 / 海商 / 舵手 / 水手 / 火长 / 杂事。
## 系统设计稿未拍板前只作剪影示意，勿当招募名单。
const PREVIEW_IDS: PackedStringArray = [
	"monk_jinghai",
	"merchant_lin",
	"pilot_ana",
	"lin_hua",
	"wu_zhen",
	"zhou_suanchou",
]

const SILHOUETTE := Vector2i(96, 120)

var _sheet: PanelContainer
var _closing := false
var _live := true


func _init() -> void:
	name = "CompanionPreview"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_live = DisplayServer.get_name() != "headless"


func begin() -> void:
	_build()
	if _live:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)


func close_overlay() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	if not _live or not is_inside_tree():
		queue_free()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.024, 0.018, 0.82) if UiTheme.IS_JUANBEN else Color(UiTheme.DIM, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_sheet = PanelContainer.new()
	_sheet.name = "CompanionSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = 48
	_sheet.offset_top = 36
	_sheet.offset_right = -48
	_sheet.offset_bottom = -36
	_sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	add_child(_sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	_sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_make_header())

	var stamp := Art.label("草案预览　招募未开　待拍板", UiTheme.SIZE_FOOT + 1, UiTheme.on_paper(UiTheme.CINNABAR) if UiTheme.IS_JUANBEN else UiTheme.CINNABAR)
	stamp.name = "DraftStamp"
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stamp)

	var grid := GridContainer.new()
	grid.name = "CardGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	var n := 0
	for id in PREVIEW_IDS:
		var ch := GameManager.get_character(str(id))
		if ch.is_empty():
			push_warning("CompanionPreview: 缺人物 %s" % id)
			continue
		grid.add_child(_make_card(ch))
		n += 1
	if n == 0:
		var empty := Art.label("名册未载入", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(empty)

	var foot := Art.label("只读示意　不入存档　非招募系统", UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	foot.name = "FootNote"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)


func _make_header() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 12)

	var title := Art.label("同舟草签", 36, UiTheme.GOLD_HI, true)
	title.name = "Title"
	title.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)

	var sub := Art.label("伙伴剪影　六人示意", UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM)
	sub.name = "Subtitle"
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "合上"
	close.custom_minimum_size = Vector2(112, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_overlay)
	UiTheme.style_button(close, true)
	head.add_child(close)
	return head


func _make_card(ch: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_%s" % str(ch.get("id", ""))
	UiTheme.paper_card(card)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(280, 168)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_silhouette(ch))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(body)

	var nm := Art.display_name(ch)
	var name_l := Art.label(nm, 22, UiTheme.GOLD_HI if UiTheme.IS_JUANBEN else UiTheme.GOLD, true)
	name_l.name = "Name"
	body.add_child(name_l)

	var ident := Art.identity_line(ch)
	if ident == "":
		ident = Art.codex_title(ch)
	if ident != "":
		if ident.length() > 16:
			ident = ident.substr(0, 16) + "…"
		var id_l := Art.label(ident, UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
		id_l.name = "Identity"
		id_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		id_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		body.add_child(id_l)

	var note := Art.codex_short(ch)
	if note == "":
		note = "剪影待访"
	# 短注单行优先；过长按字截，避免卡内折行失控
	if note.length() > 28:
		note = note.substr(0, 28) + "…"
	var note_l := Art.label(note, UiTheme.SIZE_FOOT + 1, UiTheme.TEXT)
	note_l.name = "Note"
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(note_l)

	var tag := Art.label("剪影", UiTheme.SIZE_FOOT, UiTheme.GOLD)
	tag.name = "SilhouetteTag"
	body.add_child(tag)
	return card


## 剪影：有立绘则压成墨影；无立绘走 unknown_face。
func _silhouette(ch: Dictionary) -> Control:
	var host := PanelContainer.new()
	host.name = "Silhouette"
	host.custom_minimum_size = Vector2(SILHOUETTE)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_theme_stylebox_override("panel", Art.mat_style(true))

	var tex: Texture2D = Art.thumb(ch, SILHOUETTE, false, Color(0, 0, 0, 0))
	if tex == null:
		host.add_child(Art.unknown_face(Vector2(SILHOUETTE), 28))
		return host

	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(SILHOUETTE)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 墨影：压暗，读作剪影而非设色立绘
	pic.modulate = Color(0.12, 0.10, 0.09, 0.88) if UiTheme.IS_JUANBEN else Color(0.10, 0.16, 0.20, 0.88)
	host.add_child(pic)
	return host


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction):
		return
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close_overlay()
	elif event is InputEventKey and (event as InputEventKey).keycode == KEY_F7:
		# 再按 F7 关闭（Main 侧 toggle 也会关；此处兜底）
		get_viewport().set_input_as_handled()
		close_overlay()
