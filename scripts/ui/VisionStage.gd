## 市舶纪事册页：旧绢墨边 + 题签擦出 + 立像裱框 + 海战定格示意。
## 独立场景，不改海战物理与人物志深逻辑。玩家可见文案用论文纪实文法。
## 炮焰 / 水花序列帧、泥金角花、宋绢海图残片由 tools/art/vision_fill_gen.gd 程序生成（scenes/vision/fill/）；
## 贴图缺失时回落旧的粒子点与程序椭圆。四张都是程序仿绘：序列帧不是手绘、海图不是绢本实物；
## 待出图替换见 docs/VisionStage待补工单.md（lane vs1）。Snow 后续：油画立绘替换绢本墨影。
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
# lane-v2 程序补齐（产物尺寸见 tools/art/vision_fill_gen.gd 文件头）
const FILL_MUZZLE := "res://scenes/vision/fill/vs_muzzle_strip.png"
const FILL_SPLASH := "res://scenes/vision/fill/vs_splash_strip.png"
const FILL_CORNER := "res://scenes/vision/fill/vs_corner_gilt.png"
const FILL_CHART := "res://scenes/vision/fill/vs_chart_fragment.png"
const MUZZLE_FRAMES := 8
const MUZZLE_CELL := Vector2(128, 64)
const MUZZLE_ORIGIN := Vector2(6, 32)
const SPLASH_FRAMES := 8
const SPLASH_CELL := Vector2(96, 128)
const SPLASH_ORIGIN := Vector2(48, 112)
const SEQ_FPS := 12.0
## 一轮齐射的节拍（秒）：三门炮错开出焰，弹落海鹘近旁起两柱水花
const VOLLEY_PERIOD := 2.8
const VOLLEY_FIRST := 0.6
const GUN_STAGGER := 0.12
const SPLASH_DELAY := 0.42
const CORNER_PX := 58.0

const SLIP_TITLE := "市舶纪事"
const SLIP_SEAL := "舷"
const SLIP_SUB := "外洋遇劫　福船对海鹘"
const NOTE_COMBAT := "左舷齐射　烟未散"
const NOTE_PORTRAIT := "绢本立像　名册可核"
const HINT_ESC := "B　合上纪事"

var _built := false
var _ready_emitted := false
var _guns: Array = []      # AnimatedSprite2D：舷侧三门炮的焰
var _splashes: Array = []  # AnimatedSprite2D：落弹水花
var _embers: CPUParticles2D
var _spray: CPUParticles2D
var _cues: Array = []      # [剩余秒, Callable]；不用 create_timer（-s 下未必推进）
var _volley_clock := VOLLEY_PERIOD - VOLLEY_FIRST
var volley_count := 0
## false 时不按节拍自动齐射，只响应 volley()（截屏探针定时刻用）
var auto_volley := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# 先发 ready，探针不依赖 timer（-s 下 create_timer 可能不推进）
	if not _ready_emitted:
		_ready_emitted = true
		stage_ready.emit()
	_run_intro()


func _process(delta: float) -> void:
	if _guns.is_empty():
		return
	if auto_volley:
		_volley_clock += delta
	if _volley_clock >= VOLLEY_PERIOD:
		_volley_clock -= VOLLEY_PERIOD
		volley()
	var i := 0
	while i < _cues.size():
		_cues[i][0] -= delta
		if _cues[i][0] <= 0.0:
			var cb: Callable = _cues[i][1]
			_cues.remove_at(i)
			cb.call()
		else:
			i += 1


## 放一轮舷侧齐射：炮焰按门错开，火星随第一门迸出；稍后海鹘近旁起水花。探针可直接调用。
func volley() -> void:
	volley_count += 1
	for gi in _guns.size():
		_cues.append([GUN_STAGGER * gi, _play_seq.bind(_guns[gi])])
	if _embers:
		_cues.append([0.0, _embers.restart])
	for si in _splashes.size():
		_cues.append([SPLASH_DELAY + 0.16 * si, _play_seq.bind(_splashes[si])])
	if _spray:
		_cues.append([SPLASH_DELAY, _spray.restart])


func _play_seq(seq: AnimatedSprite2D) -> void:
	seq.visible = true
	seq.frame = 0
	seq.play("seq")


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
	# 整幅须落在上下墨边之间（64..656），四角泥金才看得全
	pane.position = Vector2(48, 84)
	pane.custom_minimum_size = Vector2(300, 430)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.88)
	st.border_color = Color(UiTheme.GOLD, 0.55)
	st.set_border_width_all(1)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 22
	st.content_margin_bottom = 20
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
	bio.max_lines_visible = 3
	bio.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(bio)

	var cap := Label.new()
	cap.text = NOTE_PORTRAIT
	cap.add_theme_font_override("font", UiTheme.font())
	cap.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	cap.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.85))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	_add_gilt_corners(pane, st)


## 大裱框四角泥金角花：一张左上角纹样，flip 出其余三角。挂在一层铺满裱框的 Control 上，
## 用负偏移抵掉 PanelContainer 的内边距，角花便压在外框金线上。
func _add_gilt_corners(pane: PanelContainer, st: StyleBox) -> void:
	var tex := _fill_tex(FILL_CORNER)
	if tex == null:
		return
	var layer := Control.new()
	layer.name = "GiltCorners"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(layer)
	var ml := st.get_margin(SIDE_LEFT)
	var mr := st.get_margin(SIDE_RIGHT)
	var mt := st.get_margin(SIDE_TOP)
	var mb := st.get_margin(SIDE_BOTTOM)
	var inset := 3.0
	for corner in [[0, 0], [1, 0], [0, 1], [1, 1]]:
		var right: bool = corner[0] == 1
		var bottom: bool = corner[1] == 1
		var tr := TextureRect.new()
		tr.name = "Corner%s%s" % ["B" if bottom else "T", "R" if right else "L"]
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.flip_h = right
		tr.flip_v = bottom
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.anchor_left = 1.0 if right else 0.0
		tr.anchor_right = tr.anchor_left
		tr.anchor_top = 1.0 if bottom else 0.0
		tr.anchor_bottom = tr.anchor_top
		# 右/下两角锚在内容区右下，偏移要把整张贴图放回裱框内
		var x0 := (mr - inset - CORNER_PX) if right else (-ml + inset)
		var y0 := (mb - inset - CORNER_PX) if bottom else (-mt + inset)
		tr.offset_left = x0
		tr.offset_top = y0
		tr.offset_right = x0 + CORNER_PX
		tr.offset_bottom = y0 + CORNER_PX
		layer.add_child(tr)


func _build_combat_pane(_cv: Vector2) -> void:
	var host := Node2D.new()
	host.name = "CombatFreeze"
	host.position = Vector2(720, 360)
	add_child(host)

	var chart_tex := _fill_tex(FILL_CHART)
	if chart_tex != null:
		# 仿宋绢海图残片（程序绘，非绢本实物）作定格底图；夜色里压暗一层，旧绢不抢船
		var chart := Sprite2D.new()
		chart.name = "ChartFragment"
		chart.texture = chart_tex
		chart.position = Vector2(120, 30)
		chart.scale = Vector2(0.94, 0.94)
		chart.rotation = -0.025
		chart.modulate = Color(0.70, 0.66, 0.60, 1.0)
		host.add_child(chart)
	else:
		var water := Polygon2D.new()
		water.color = Color(0.07, 0.14, 0.20, 0.7)
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			pts.append(Vector2(cos(a) * 260.0, sin(a) * 110.0 + 70.0))
		water.polygon = pts
		host.add_child(water)

	var fu_pos := Vector2(40, 20)
	var fu_rot := -0.35
	var falcon_pos := Vector2(280, -30)
	host.add_child(_ship_shadow(fu_pos, Vector2(0.9, 2.3), fu_rot))
	host.add_child(_ship_shadow(falcon_pos, Vector2(0.7, 1.8), 0.55))
	host.add_child(_ship_sprite(SHIP_FU, fu_pos, 0.42, fu_rot))
	var falcon := _ship_sprite(SHIP_FALCON, falcon_pos, 0.32, 0.55)
	falcon.modulate = Color(0.85, 0.75, 0.7, 1.0)
	host.add_child(falcon)

	var muzzle_frames := _strip_frames(FILL_MUZZLE, MUZZLE_FRAMES, MUZZLE_CELL)
	var splash_frames := _strip_frames(FILL_SPLASH, SPLASH_FRAMES, SPLASH_CELL)
	var seq_ok := muzzle_frames != null and splash_frames != null
	# 右舷炮位：沿船身轴向排开，炮口朝海鹘
	var axis := Vector2(0, -1).rotated(fu_rot)
	var side := Vector2(1, 0).rotated(fu_rot)
	if seq_ok:
		for gi in 3:
			var port := fu_pos + side * 26.0 + axis * (30.0 - 26.0 * gi)
			var aim := (falcon_pos - port).angle()
			var g := _seq_sprite(muzzle_frames, MUZZLE_CELL, MUZZLE_ORIGIN, port, aim, 0.95 - 0.08 * gi)
			g.name = "Muzzle%d" % gi
			host.add_child(g)
			_guns.append(g)
		for si in 2:
			var at: Vector2 = [Vector2(225, 20), Vector2(318, 2)][si]
			var sp := _seq_sprite(splash_frames, SPLASH_CELL, SPLASH_ORIGIN, at, 0.0, [0.9, 0.7][si])
			sp.name = "Splash%d" % si
			host.add_child(sp)
			_splashes.append(sp)
	var first_port := fu_pos + side * 26.0 + axis * 30.0
	_embers = _muzzle_particles(first_port + (falcon_pos - first_port).normalized() * 18.0, seq_ok)
	host.add_child(_embers)
	_spray = _spray_particles(Vector2(225, 20), seq_ok)
	host.add_child(_spray)

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


## 有序列帧时粒子只作齐射那一下的火星（one_shot，随 volley 迸出）；无帧时回落常驻喷流。
func _muzzle_particles(pos: Vector2, burst := false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 18 if burst else 28
	p.lifetime = 0.7
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	p.preprocess = 0.0 if burst else 0.35
	p.emitting = not burst
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


func _spray_particles(pos: Vector2, burst := false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = 14 if burst else 20
	p.lifetime = 0.9
	p.one_shot = burst
	p.explosiveness = 0.7 if burst else 0.0
	p.preprocess = 0.0 if burst else 0.4
	p.emitting = not burst
	p.direction = Vector2(0.2, -1)
	p.spread = 40.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	# 绢白带一点靛影，不用冷蓝
	p.color = Color(0.86, 0.87, 0.82, 0.7) if burst else Color(0.75, 0.88, 0.95, 0.7)
	if ResourceLoader.exists(FX_SPRAY):
		p.texture = load(FX_SPRAY)
	elif ResourceLoader.exists(FX_DOT):
		p.texture = load(FX_DOT)
	return p


## 船下一抹暖墨影，把船压在绢上。
func _ship_shadow(pos: Vector2, stretch: Vector2, rot: float) -> Node2D:
	var s := Sprite2D.new()
	s.name = "ShipShadow"
	if ResourceLoader.exists(FX_DOT):
		s.texture = load(FX_DOT)
	s.position = pos + Vector2(6, 8)
	s.scale = stretch
	s.rotation = rot
	s.modulate = Color(0.08, 0.06, 0.05, 0.42)
	return s


## 读 lane-v2 生成的贴图：已导入走 load()；未导入（新克隆未开编辑器）直接读 PNG。都没有返回 null。
func _fill_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## 横排序列帧 → SpriteFrames（动画名 seq，不循环）。
func _strip_frames(path: String, count: int, cell: Vector2) -> SpriteFrames:
	var tex := _fill_tex(path)
	if tex == null or tex.get_width() < int(cell.x) * count:
		return null
	var sf := SpriteFrames.new()
	sf.add_animation("seq")
	sf.set_animation_loop("seq", false)
	sf.set_animation_speed("seq", SEQ_FPS)
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(cell.x * i, 0, cell.x, cell.y)
		sf.add_frame("seq", at)
	return sf


func _seq_sprite(frames: SpriteFrames, cell: Vector2, origin: Vector2, pos: Vector2, rot: float, sc: float) -> AnimatedSprite2D:
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames
	a.animation = "seq"
	a.centered = false
	a.offset = -origin
	a.position = pos
	a.rotation = rot
	a.scale = Vector2(sc, sc)
	a.visible = false
	a.animation_finished.connect(func() -> void: a.visible = false)
	return a


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
