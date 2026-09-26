## 市舶纪事册页：旧绢墨边 + 题签擦出 + 立像裱框 + 海战定格示意。
## 独立场景，不改海战物理与人物志深逻辑。玩家可见文案用论文纪实文法。
## Snow 后续：油画立绘替换绢本墨影；舷侧炮焰/烟雾手绘序列帧。
extends Control

const Art := preload("res://scripts/ui/CharacterArt.gd")

signal stage_ready

const PORTRAIT_ID := "chen_wenlong"
const PORTRAIT_LOGICAL := Vector2(220, 275)
const SHIP_FU := "res://assets/ship_fu.png"
const SHIP_FALCON := "res://assets/ship_falcon.png"
const FRAME_TEX := "res://assets/ui/nk1/portrait_frame.png"
const FX_EMBER := "res://assets/fx/ember.png"
const FX_DOT := "res://assets/fx/soft_dot.png"
const FX_SPRAY := "res://assets/fx/spray_drop.png"

const SLIP_TITLE := "市舶纪事"
const SLIP_SEAL := "舷"
const SLIP_SUB := "外洋遇劫　福船对海鹘"
const NOTE_COMBAT := "左舷齐射　烟未散"
const NOTE_PORTRAIT := "绢本立像　名册可核"
const HINT_ESC := "B　合上纪事"

var _built := false
var _ready_emitted := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# 先发 ready，探针不依赖 timer（-s 下 create_timer 可能不推进）
	if not _ready_emitted:
		_ready_emitted = true
		stage_ready.emit()
	_run_intro()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_B:
			_leave()
			get_viewport().set_input_as_handled()


func _leave() -> void:
	if get_tree() == null:
		return
	if ResourceLoader.exists("res://scenes/Main.tscn") and get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	else:
		queue_free()


func _build() -> void:
	if _built:
		return
	_built = true
	var cv := Vector2(1280, 720)

	var sea := ColorRect.new()
	sea.set_anchors_preset(Control.PRESET_FULL_RECT)
	sea.color = Color(0.06, 0.10, 0.14, 1.0)
	sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sea)

	var sea_hi := ColorRect.new()
	sea_hi.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sea_hi.offset_bottom = cv.y * 0.55
	sea_hi.color = Color(0.12, 0.22, 0.28, 0.55)
	sea_hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sea_hi)

	if ResourceLoader.exists("res://assets/fx/mist_puff.png"):
		var mist := TextureRect.new()
		mist.texture = load("res://assets/fx/mist_puff.png")
		mist.set_anchors_preset(Control.PRESET_FULL_RECT)
		mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mist.stretch_mode = TextureRect.STRETCH_SCALE
		mist.modulate = Color(0.75, 0.82, 0.88, 0.18)
		mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mist)

	_build_combat_pane(cv)
	_build_portrait_pane(cv)
	_build_letterbox(cv)
	_build_slip(cv)
	_build_hint(cv)


func _build_letterbox(cv: Vector2) -> void:
	var bar_h := 64.0
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = UiTheme.INK_SOLID
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(cv.x, bar_h)
		bar.position = Vector2(0, 0 if top else cv.y - bar_h)
		bar.name = "LetterTop" if top else "LetterBot"
		var line := ColorRect.new()
		line.color = Color(UiTheme.GOLD, 0.75)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.size = Vector2(cv.x, 2)
		line.position = Vector2(0, bar_h - 2 if top else 0)
		bar.add_child(line)
		add_child(bar)


func _build_slip(cv: Vector2) -> void:
	var clip := Control.new()
	clip.name = "SlipClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(cv.x * 0.5 - 210, 78)
	clip.size = Vector2(420, 86)
	add_child(clip)

	var slip := PanelContainer.new()
	slip.name = "Slip"
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.804, 0.722, 0.561) if UiTheme.IS_JUANBEN else UiTheme.INK_SOFT
	box.border_color = UiTheme.GOLD
	box.border_width_top = 2
	box.border_width_bottom = 2
	box.content_margin_left = 48
	box.content_margin_right = 40
	box.content_margin_top = 8
	box.content_margin_bottom = 10
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 12
	slip.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.add_child(row)

	var head := Label.new()
	head.text = SLIP_TITLE
	head.add_theme_font_override("font", UiTheme.title_font())
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", UiTheme.INK_SOLID if UiTheme.IS_JUANBEN else UiTheme.GOLD_HI)
	row.add_child(head)

	var seal := Label.new()
	seal.text = SLIP_SEAL
	seal.add_theme_font_override("font", UiTheme.title_font())
	seal.add_theme_font_size_override("font_size", 22)
	seal.add_theme_color_override("font_color", UiTheme.SEAL_TEXT)
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.custom_minimum_size = Vector2(36, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.SEAL
	sb.set_corner_radius_all(3)
	seal.add_theme_stylebox_override("normal", sb)
	seal.rotation = -0.05
	row.add_child(seal)
	clip.add_child(slip)

	var sub := Label.new()
	sub.name = "SlipSub"
	sub.text = SLIP_SUB
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UiTheme.font())
	sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	sub.position = Vector2(0, 168)
	sub.size = Vector2(cv.x, 28)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)


func _build_portrait_pane(_cv: Vector2) -> void:
	var pane := PanelContainer.new()
	pane.name = "PortraitPane"
	pane.position = Vector2(56, 175)
	pane.custom_minimum_size = Vector2(300, 430)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.88)
	st.border_color = Color(UiTheme.GOLD, 0.55)
	st.set_border_width_all(1)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 16
	st.content_margin_bottom = 16
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 10
	pane.add_theme_stylebox_override("panel", st)
	add_child(pane)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(col)

	var ch := _resolve_character(PORTRAIT_ID)
	var tex: Texture2D = null
	if not ch.is_empty():
		tex = Art.portrait(ch)
	var framed: PanelContainer = Art.framed(tex, PORTRAIT_LOGICAL, false)
	if ResourceLoader.exists(FRAME_TEX):
		var outer := PanelContainer.new()
		var fr := StyleBoxTexture.new()
		fr.texture = load(FRAME_TEX)
		fr.texture_margin_left = 28
		fr.texture_margin_right = 28
		fr.texture_margin_top = 28
		fr.texture_margin_bottom = 36
		outer.add_theme_stylebox_override("panel", fr)
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(framed)
		col.add_child(outer)
	else:
		col.add_child(framed)

	var name_l := Label.new()
	name_l.text = _display_name(ch)
	name_l.add_theme_font_override("font", UiTheme.title_font())
	name_l.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
	name_l.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)

	var id_line := Label.new()
	id_line.text = Art.identity_line(ch) if not ch.is_empty() else "人物未载"
	id_line.add_theme_font_override("font", UiTheme.font())
	id_line.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	id_line.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	id_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(id_line)

	var bio := Label.new()
	bio.text = _short_note(ch)
	bio.add_theme_font_override("font", UiTheme.font())
	bio.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	bio.add_theme_color_override("font_color", UiTheme.TEXT)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.custom_minimum_size = Vector2(260, 0)
	col.add_child(bio)

	var cap := Label.new()
	cap.text = NOTE_PORTRAIT
	cap.add_theme_font_override("font", UiTheme.font())
	cap.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	cap.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.85))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)


func _build_combat_pane(_cv: Vector2) -> void:
	var host := Node2D.new()
	host.name = "CombatFreeze"
	host.position = Vector2(720, 360)
	add_child(host)

	var water := Polygon2D.new()
	water.color = Color(0.07, 0.14, 0.20, 0.7)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 260.0, sin(a) * 110.0 + 70.0))
	water.polygon = pts
	host.add_child(water)

	host.add_child(_ship_sprite(SHIP_FU, Vector2(40, 20), 0.42, -0.35))
	var falcon := _ship_sprite(SHIP_FALCON, Vector2(280, -30), 0.32, 0.55)
	falcon.modulate = Color(0.85, 0.75, 0.7, 1.0)
	host.add_child(falcon)
	host.add_child(_muzzle_particles(Vector2(130, 0)))
	host.add_child(_spray_particles(Vector2(220, 50)))

	var tag := Label.new()
	tag.text = NOTE_COMBAT
	tag.add_theme_font_override("font", UiTheme.title_font())
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	tag.add_theme_color_override("font_outline_color", UiTheme.INK_SOLID)
	tag.add_theme_constant_override("outline_size", 4)
	tag.position = Vector2(860, 520)
	tag.name = "CombatTag"
	add_child(tag)

	var float_l := Label.new()
	float_l.text = "中板"
	float_l.add_theme_font_override("font", UiTheme.title_font())
	float_l.add_theme_font_size_override("font_size", 28)
	float_l.add_theme_color_override("font_color", UiTheme.CINNABAR)
	float_l.add_theme_color_override("font_outline_color", UiTheme.INK_SOLID)
	float_l.add_theme_constant_override("outline_size", 5)
	float_l.position = Vector2(1020, 300)
	float_l.name = "HitFloat"
	add_child(float_l)


func _ship_sprite(path: String, pos: Vector2, scale: float, rot: float) -> Sprite2D:
	var s := Sprite2D.new()
	if ResourceLoader.exists(path):
		s.texture = load(path)
	s.position = pos
	s.scale = Vector2(scale, scale)
	s.rotation = rot
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


func _muzzle_particles(pos: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 28
	p.lifetime = 0.7
	p.preprocess = 0.35
	p.emitting = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(1, -0.15)
	p.spread = 18.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 160.0
	p.gravity = Vector2(0, 40)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.1
	p.color = Color(1.0, 0.55, 0.22, 0.9)
	if ResourceLoader.exists(FX_EMBER):
		p.texture = load(FX_EMBER)
	elif ResourceLoader.exists(FX_DOT):
		p.texture = load(FX_DOT)
	return p


func _spray_particles(pos: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 20
	p.lifetime = 0.9
	p.preprocess = 0.4
	p.emitting = true
	p.direction = Vector2(0.2, -1)
	p.spread = 40.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color = Color(0.75, 0.88, 0.95, 0.7)
	if ResourceLoader.exists(FX_SPRAY):
		p.texture = load(FX_SPRAY)
	elif ResourceLoader.exists(FX_DOT):
		p.texture = load(FX_DOT)
	return p


func _build_hint(cv: Vector2) -> void:
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = HINT_ESC
	hint.add_theme_font_override("font", UiTheme.font())
	hint.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	hint.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.position = Vector2(cv.x - 280, cv.y - 42)
	hint.size = Vector2(260, 24)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func _run_intro() -> void:
	# 轻量帧动画：题签自左擦出 + 飘字上浮（process_frame，不用 create_timer）
	if get_tree() == null:
		return
	var clip := get_node_or_null("SlipClip") as Control
	if clip:
		clip.size.x = 0.0
		for i in 20:
			clip.size.x = 420.0 * float(i + 1) / 20.0
			await get_tree().process_frame
	var hit := get_node_or_null("HitFloat") as CanvasItem
	if hit:
		hit.modulate.a = 1.0
		var y0 := 330.0
		for i in 18:
			hit.position.y = y0 - 55.0 * float(i + 1) / 18.0
			await get_tree().process_frame
		for i in 12:
			hit.modulate.a = 1.0 - float(i + 1) / 12.0
			await get_tree().process_frame


func _resolve_character(id: String) -> Dictionary:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_character"):
		var ch: Dictionary = gm.get_character(id)
		if not ch.is_empty():
			return ch
	if not FileAccess.file_exists("res://data/characters.json"):
		return {}
	var raw := FileAccess.get_file_as_string("res://data/characters.json")
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var list = data.get("characters", [])
	if typeof(list) == TYPE_ARRAY:
		for c in list:
			if typeof(c) == TYPE_DICTIONARY and str(c.get("id", "")) == id:
				return c
	return {}


func _display_name(ch: Dictionary) -> String:
	if ch.is_empty():
		return "未载"
	return Art.display_name(ch)


func _short_note(ch: Dictionary) -> String:
	if ch.is_empty():
		return "人物数据未载入。"
	var s: String = Art.codex_short(ch)
	if s.strip_edges() != "":
		return Art.fill_names(s)
	var bio: String = Art.codex_bio(ch)
	if bio.strip_edges() != "":
		return Art.fill_names(bio)
	return "兴化籍海商人物。事迹见人物志。"
