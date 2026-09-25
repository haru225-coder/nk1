## 标题屏演出（cinematics 线）：书法题名由左至右「写」出 → 引首朱印落下回弹 → 引言分段、逐行洇出 → 按钮浮现。
## 卷首四方沙盘（cg_world_*，同为 title 模式）同一套：抬头淡入，长文按「小标：正文」拆段，逐段逐行洇出；
## 字号按 1280×720 下的可用高度实测取（Font.get_multiline_string_size），保证不溢出。
## 演出中点击 / 按键 = 立即补全（这次输入被吃掉，不会误触「开卷」）；补全后不再拦输入。
## headless 下直接落到终态、不建材质。挂在 TitleMode 下（节点名 TitleStage），由 Main 调 present()。
extends Node

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")
const Cine := preload("res://scripts/cutscene/Cinematics.gd")
const SELF_PATH := "res://scripts/cutscene/TitleStage.gd"
const NODE_NAME := "TitleStage"
const LINES_NAME := "TitleLines"
const DIVIDER_TEX := "res://assets/ui/nk1/divider_gold.png"
## 引首章：与题名末尾自带的「立志」名章一首一尾（UI 线成品白文印）
const LEAD_SEAL := "海商"
## 卷首四方沙盘的抬头「北方：……」拆成方位朱印 + 题句（与开场过场四方位印同一套印文；东方用繁简同形的「扶桑」）
const DIR_SEALS := {"北方": "北", "东方": "扶桑", "南方": "南", "西方": "西"}
const HEAD_NAME := "TitleHead"
const T_DIR_SEAL := 0.55

const T_LOGO := 0.25
const LOGO_DUR := 1.75
const T_SEAL := 2.05
const T_HEAD := 0.1
const HEAD_DUR := 0.6
## 每行洇出用时；段与段之间的衔接（下一段在上一段走到这个比例时起）
const LINE_T := 0.55
const OVERLAP := 0.8
const BTN_FADE := 0.6
const BTN_STAGGER := 0.18
## 可用区：TitleMode 下 VBox 的设计尺寸（Main.tscn 960×600）
const BOX_H := 600.0
const LEAD_W := 860.0
const PLAIN_W := 880.0
const LINE_SPACING := 5

var _host: Control
var _vbox: VBoxContainer
var _title: Label
var _logo: TextureRect
var _logo_mat: ShaderMaterial
var _seal: Control
var _want_seal := false
## 四方沙盘抬头：方位印 + 题句（没有就是 null，抬头用原 main_title）
var _head_label: Label
var _head_seal: Control
var _head_seal_text := ""
var _plaque: Control
## 逐项揭开：{"node", "start", "dur", "kind": "wipe"|"fade", "center": bool, "mat"}
var _items: Array = []
var _buttons: Array = []
var _t := 0.0
var _end := 0.0
var _t_btn := 0.0
var _done := true
var _fit_frames := 0


## 进标题模式（换过 main_title / sub_title 文本之后）调用。buttons：按顺序浮现的钮（隐藏的跳过）。
## with_seal：题名是书法 logo 时落引首章（只在起始标题页）。
static func present(host: Control, main_title: Label, sub_title: Label, buttons: Array, with_seal := false) -> Node:
	if host == null or main_title == null or sub_title == null:
		return null
	var stage: Node = host.get_node_or_null(NODE_NAME)
	if stage == null:
		stage = (load(SELF_PATH) as GDScript).new()
		stage.name = NODE_NAME
		host.add_child(stage)
	stage.call("_setup", host, main_title, sub_title, buttons, with_seal)
	return stage


## 从头再演一遍（开机开场过场播完、揭开标题屏时）
func replay() -> void:
	if _host != null:
		_restart()


func is_revealing() -> bool:
	return not _done


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _setup(host: Control, main_title: Label, sub_title: Label, buttons: Array, with_seal: bool) -> void:
	_host = host
	_title = main_title
	_vbox = sub_title.get_parent() as VBoxContainer
	_plaque = host.get_node_or_null("TitlePlaque") as Control
	_logo = null
	if _vbox != null:
		var lg := _vbox.get_node_or_null("TitleLogo") as TextureRect
		if lg != null and lg.visible:
			_logo = lg
	_build_lines(sub_title)
	_build_head(main_title)
	_want_seal = with_seal and _logo != null
	_buttons.clear()
	for b in buttons:
		if b is Control and (b as Control).visible:
			_buttons.append(b)
	_restart()


func _restart() -> void:
	_t = 0.0
	_done = false
	_fit_frames = 4
	# 过场层不上场（headless / -s 工具脚本 / 巡检关闭）时不演，直接落到终态
	var still := not Cine.live()
	if _logo != null and not still:
		if _logo_mat == null:
			_logo_mat = Kit.material("cs_wipe.gdshader")
			if _logo_mat != null:
				_logo_mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
				_logo_mat.set_shader_parameter("seed", 0.37)
		if _logo_mat != null:
			_logo_mat.set_shader_parameter("rect_px", _logo.custom_minimum_size)
			_logo.material = _logo_mat
	# 印每次重建：落下 / 回弹 / 洇开的状态从头来
	if _seal != null:
		_seal.queue_free()
		_seal = null
	_build_seal(_want_seal)
	_rebuild_head_seal()
	var last := 0.0
	for it in _items:
		if not still and it["kind"] == "wipe" and it["mat"] == null:
			var m := Kit.material("cs_line_reveal.gdshader")
			if m != null:
				m.set_shader_parameter("from_center", bool(it["center"]))
				m.set_shader_parameter("progress", 0.0)
				(it["node"] as CanvasItem).material = m
				it["mat"] = m
		last = maxf(last, float(it["start"]) + float(it["dur"]))
	_t_btn = maxf(last - 0.35, (T_SEAL + 0.3) if _seal != null else 0.6)
	_end = maxf(last, (T_LOGO + LOGO_DUR) if _logo != null else HEAD_DUR)
	_end = maxf(_end, _t_btn + BTN_STAGGER * maxf(float(_buttons.size() - 1), 0.0) + BTN_FADE)
	if still:
		_complete()
		return
	_apply()


# ── 段落 ─────────────────────────────────────────────
## 「小标：正文」拆段：小标 2–10 字才算（不把句中冒号当小标）
static func _split_lead(p: String) -> Array:
	var i := p.find("：")
	if i >= 2 and i <= 10:
		return [p.substr(0, i), p.substr(i + 1).strip_edges()]
	return ["", p]


func _build_lines(sub_title: Label) -> void:
	for it in _items:
		if is_instance_valid(it["node"]):
			(it["node"] as CanvasItem).material = null
	_items.clear()
	if _vbox == null:
		return
	var box := _vbox.get_node_or_null(LINES_NAME) as VBoxContainer
	if box == null:
		box = VBoxContainer.new()
		box.name = LINES_NAME
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_vbox.add_child(box)
	_vbox.move_child(box, sub_title.get_index() + 1)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var paras: Array = []
	for raw in sub_title.text.split("\n"):
		var s := str(raw).strip_edges()
		if s != "":
			paras.append(s)
	# 原副标题留着文本（别处照常能读），画面上换成分段洇出
	sub_title.visible = paras.is_empty()
	box.visible = not paras.is_empty()
	if paras.is_empty():
		return
	var leads := 0
	for p in paras:
		if str(_split_lead(p)[0]) != "":
			leads += 1
	var lead_mode := leads * 2 >= paras.size()
	var width := LEAD_W if lead_mode else PLAIN_W
	var fs := _fit_size(paras, lead_mode, width)
	box.add_theme_constant_override("separation", 14 if lead_mode else 10)
	var t := (T_LOGO + 0.9) if _logo != null else 0.45
	if _logo != null:
		var div := _divider()
		if div != null:
			box.add_child(div)
			_items.append({"node": div, "start": t - 0.25, "dur": 0.7, "kind": "fade", "center": true, "mat": null})
	var body_f := UiTheme.font()
	for p in paras:
		var parts := _split_lead(p)
		if lead_mode:
			var col := VBoxContainer.new()
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_theme_constant_override("separation", 2)
			col.custom_minimum_size = Vector2(width, 0)
			col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(col)
			if str(parts[0]) != "":
				var head := _label(str(parts[0]), UiTheme.title_font(), fs + 5, UiTheme.GOLD_HI, width, HORIZONTAL_ALIGNMENT_LEFT)
				col.add_child(head)
				_items.append({"node": head, "start": t, "dur": 0.5, "kind": "wipe", "center": false, "mat": null})
				t += 0.3
			var body := _label(str(parts[1]), body_f, fs, UiTheme.TEXT, width, HORIZONTAL_ALIGNMENT_LEFT)
			col.add_child(body)
			var d := LINE_T * _line_estimate(body_f, str(parts[1]), width, fs)
			_items.append({"node": body, "start": t, "dur": d, "kind": "wipe", "center": false, "mat": null})
			t += d * OVERLAP + 0.15
		else:
			var l := _label(p, body_f, fs, UiTheme.TEXT, width, HORIZONTAL_ALIGNMENT_CENTER)
			l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(l)
			var d2 := LINE_T * _line_estimate(body_f, p, width, fs)
			_items.append({"node": l, "start": t, "dur": d2, "kind": "wipe", "center": true, "mat": null})
			t += d2 * OVERLAP


func _label(txt: String, f: Font, fs: int, col: Color, width: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = txt
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("line_spacing", LINE_SPACING)
	UiTheme.style_overlay(l)
	return l


static func _line_estimate(f: Font, txt: String, width: float, fs: int) -> float:
	var sz := f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, width - 8.0, fs)
	return maxf(1.0, roundf(sz.y / maxf(f.get_height(fs), 1.0)))


## 从 21 往下试，取放得下的最大字号：可用高 = 600 − 题名 − 按钮 − 间距（按 Font.get_multiline_string_size 实测行数）
func _fit_size(paras: Array, lead_mode: bool, width: float) -> int:
	var head_h := 174.0 if _logo != null else 74.0
	var fixed := head_h + 60.0 + 20.0 * 3.0 + (58.0 if _logo != null else 0.0)
	var budget := BOX_H - fixed - 24.0
	var body := UiTheme.font()
	var head := UiTheme.title_font()
	for fs in [21, 20, 19, 18, 17, 16]:
		var total := 0.0
		for p in paras:
			var parts := _split_lead(p)
			if lead_mode and str(parts[0]) != "":
				total += head.get_height(fs + 5) + 2.0
			var txt: String = str(parts[1]) if lead_mode else str(p)
			total += _line_estimate(body, txt, width, fs) * (body.get_height(fs) + LINE_SPACING)
			total += 14.0 if lead_mode else 10.0
		if total <= budget:
			return fs
	return 16


func _divider() -> Control:
	var tex: Texture2D = Kit.load_texture(DIVIDER_TEX) if ResourceLoader.exists(DIVIDER_TEX) else null
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.custom_minimum_size = Vector2(tex.get_width() * 0.5, tex.get_height() * 0.5)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return r


# ── 引首章 ───────────────────────────────────────────
## 四方沙盘抬头：「北方：大军压境……」→ [北] 大军压境……。原 main_title 留文本、藏起来；不是这种抬头就还原显示。
func _build_head(main_title: Label) -> void:
	_head_label = null
	_head_seal_text = ""
	if _head_seal != null:
		_head_seal.queue_free()
		_head_seal = null
	if _vbox == null:
		return
	var row := _vbox.get_node_or_null(HEAD_NAME) as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = HEAD_NAME
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 22)
		_vbox.add_child(row)
	_vbox.move_child(row, main_title.get_index())
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	row.visible = false
	# 书法 logo 在时 main_title 本就由 UiTheme.sync_title_logo 藏着；否则先还原显示（夜潮没有 logo 节点，全靠这里）
	main_title.visible = _logo == null
	if _logo != null:
		return
	var txt := main_title.text.strip_edges()
	var i := txt.find("：")
	if i < 0 or not DIR_SEALS.has(txt.substr(0, i)):
		return
	_head_seal_text = str(DIR_SEALS[txt.substr(0, i)])
	var lbl := Label.new()
	lbl.text = txt.substr(i + 1).strip_edges()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_override("font", UiTheme.title_font())
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", UiTheme.GOLD)
	UiTheme.style_overlay(lbl)
	row.add_child(lbl)
	row.visible = true
	main_title.visible = false
	_head_label = lbl


func _rebuild_head_seal() -> void:
	if _head_seal != null:
		_head_seal.queue_free()
		_head_seal = null
	if _head_seal_text == "" or _head_label == null or Kit.is_headless():
		return
	var s: Control = Seal.new()
	var one := _head_seal_text.length() == 1
	# 两字印（「扶桑」等）每格 38：原 30 时每字只有约 14px，糊（第 2 轮美术 minor 6）
	s.configure(_head_seal_text, {"cell": 44.0 if one else 38.0, "style": "baiwen", "hollow_alpha": 0.92,
		"seed": fmod(float(_head_seal_text.hash() & 1023) / 1023.0, 1.0), "tilt": -0.04, "procedural": true})
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.visible = false
	var row := _head_label.get_parent()
	row.add_child(s)
	row.move_child(s, 0)
	_head_seal = s


func _build_seal(want: bool) -> void:
	if not want or _seal != null or _logo == null or Kit.is_headless():
		return
	var s: Control = Seal.new()
	# 程序印、字口填宣纸色：与题名末尾「立志」名章同为朱底浅字（成品白文印的字口是透明的，压在暗海图上发糊）
	s.configure(LEAD_SEAL, {"cell": 34.0, "style": "baiwen", "hollow_alpha": 0.92, "seed": 0.61, "tilt": -0.05, "procedural": true})
	s.visible = false
	# 书法起笔左上方、略高于字身：引首章的位置
	s.position = Vector2(-s.size.x - 4.0, 18.0)
	_logo.add_child(s)
	_seal = s


# ── 时间轴 ───────────────────────────────────────────
func _process(delta: float) -> void:
	if _host == null:
		return
	if _fit_frames > 0:
		_fit_frames -= 1
		_fit_plaque()
	if _done:
		return
	if not _host.is_visible_in_tree():
		_complete()
		return
	_t += delta
	_apply()


func _apply() -> void:
	var t := _t
	if _logo != null:
		var p := Kit.ease_in_out_sine((t - T_LOGO) / LOGO_DUR)
		if _logo_mat != null:
			_logo_mat.set_shader_parameter("progress", p)
			_logo.modulate.a = 1.0
		else:
			_logo.modulate.a = p
	elif _head_label != null:
		_head_label.modulate.a = Kit.ease_out_cubic((t - T_HEAD) / HEAD_DUR)
	elif _title != null and _title.visible:
		_title.modulate.a = Kit.ease_out_cubic((t - T_HEAD) / HEAD_DUR)
	_advance_seal(_head_seal, t, T_DIR_SEAL)
	if _seal != null and t >= T_SEAL:
		if not _seal.visible:
			_seal.visible = true
			_seal.call("advance", t - T_SEAL)
		else:
			_seal.call("advance", get_process_delta_time())
	for it in _items:
		var q := clampf((t - float(it["start"])) / maxf(float(it["dur"]), 0.01), 0.0, 1.0)
		var node := it["node"] as Control
		if it["kind"] == "fade" or it["mat"] == null:
			node.modulate.a = Kit.ease_out_cubic(q)
			continue
		node.modulate.a = 1.0
		var m: ShaderMaterial = it["mat"]
		var lines := float(maxi((node as Label).get_line_count(), 1))
		var f := node.get_theme_font("font")
		var fs := node.get_theme_font_size("font_size")
		m.set_shader_parameter("progress", q)
		m.set_shader_parameter("lines", lines)
		m.set_shader_parameter("line_h", f.get_height(fs) + LINE_SPACING if f != null else 30.0)
		m.set_shader_parameter("width", node.size.x)
	for i in _buttons.size():
		var b: Control = _buttons[i]
		b.modulate.a = Kit.ease_out_cubic((t - _t_btn - BTN_STAGGER * i) / BTN_FADE)
	if t >= _end:
		_complete()


func _advance_seal(s: Control, t: float, at: float) -> void:
	if s == null or t < at:
		return
	if not s.visible:
		s.visible = true
		s.call("advance", t - at)
	else:
		s.call("advance", get_process_delta_time())


func _complete() -> void:
	_t = maxf(_t, _end)
	_done = true
	if _logo != null:
		_logo.modulate.a = 1.0
		_logo.material = null
	elif _title != null:
		_title.modulate.a = 1.0
	if _head_label != null:
		_head_label.modulate.a = 1.0
	for s in [_seal, _head_seal]:
		if s == null:
			continue
		if not (s as Control).visible:
			(s as Control).visible = true
		s.call("finish_reveal")
		s.call("advance", 1.2)
	for it in _items:
		var node := it["node"] as Control
		node.modulate.a = 1.0
		node.material = null
		it["mat"] = null
	for b in _buttons:
		(b as Control).modulate.a = 1.0


## 标题衬底（淡墨晕）按实际内容撑开：四方沙盘的长文比开篇多出一倍，原定 720×400 盖不住
func _fit_plaque() -> void:
	if _plaque == null or _vbox == null or not _host.is_visible_in_tree():
		return
	var r := Rect2()
	var first := true
	for c in _vbox.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var cr := (c as Control).get_global_rect()
		if cr.size.x <= 1.0 or cr.size.y <= 1.0:
			continue
		r = cr if first else r.merge(cr)
		first = false
	if first:
		return
	var center := _host.get_global_rect().get_center()
	var half_w := maxf(360.0, r.size.x * 0.5 + 24.0)
	_plaque.offset_left = -half_w
	_plaque.offset_right = half_w
	_plaque.offset_top = minf(-210.0, r.position.y - center.y - 10.0)
	_plaque.offset_bottom = maxf(190.0, r.end.y - center.y + 6.0)


func _input(event: InputEvent) -> void:
	if _done or _host == null or not _host.is_visible_in_tree():
		return
	var hit := false
	if event is InputEventMouseButton:
		hit = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		var k := event as InputEventKey
		hit = k.pressed and not k.echo
	if hit:
		_complete()
		get_viewport().set_input_as_handled()
