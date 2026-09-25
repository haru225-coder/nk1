## 章节卡（cutscene_engine 线）：黑场 → 宣纸按噪声阈值洇进来 → 墨晕铺开露出章节油画 → 「第X章」逐字 → 章名 → 年号 → 题记竖排带出处
## → 朱印盖下（回弹 + 印泥洇开；UI 线的「立志」成品印在就用它）→ 停留 → 字印淡去、墨晕回缩、纸面按同一阈值退去露出游戏。
## 总长约 7.7 秒；点击 / 空格 / 回车先补全、再跳到退场；Esc 直接退场。
##
##   var card := ChapterCard.play(self, GameState.chapter)
##   await card.finished            # 退场淡完、底下游戏画面已完全露出时发出，随后自 queue_free
##
## 数据：cutscenes.json chapters["<n>"] 的 bg / epigraph / epigraph_src / year_text；章名读 data/chapters.json。
## 缺哪样就不演哪样（无底图时只有宣纸与墨晕），不会卡住。headless 下 call_deferred 立即 finished。
class_name ChapterCard
extends CanvasLayer

signal finished
## 纸面开始退去（T_WIPE）的那一刻发出：调用方趁卡还盖在上面，把卡后要出的画面（压暗层 + 册页）先在底下建好，
## 纸退去时揭开的就是最终画面，不再先露出没压暗的港页、再硬切出册页。headless 下与 finished 同帧发出。
signal exiting

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const InkText := preload("res://scripts/cutscene/cs_ink_text.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")

const LAYER_INDEX := 55
const T_BLACK := 0.3
const T_PAPER_IN := 0.5
## 纸洇进来 1.0 秒、ease_in_out（原 0.6 秒 ease_out_cubic：前 0.2 秒走完大半，亮度两帧打满，像闪屏；第 2 轮美术 M1）
const T_PAPER_DUR := 1.0
const T_BLOOM := 0.8
const T_BLOOM_DUR := 2.0
const T_HEAD := 1.25
const T_NAME := 1.95
const T_YEAR := 2.85
const T_EPI := 3.25
const T_SEAL := 4.6
const T_OUT := 6.3
## 退场：字与印 0.5 秒淡去、墨晕 0.6 秒回缩，纸面从 T_WIPE 起按噪声阈值从墨晕窗口往外退去 1.0 秒（露出底下的游戏，不是整层交叉淡化）
const T_WIPE := 6.7
const T_END := 7.7
const TEXT_OUT := 0.5
const BLOOM_OUT := 0.6
const PAPER_TEX := "res://assets/ui/nk1/tex_paper_xuan.png"
const SEAL_TEXT := "立志"
const INK_TEXT := Color(0.102, 0.086, 0.071)
const OCHRE_TEXT := Color(0.36, 0.205, 0.08)

var chapter := 1
var _data_path := "res://data/cutscenes.json"
var _year_override := ""
var _t := 0.0
var _done := false
var _warmed := false
var _jolt := 0.0
var _canvas := Vector2(1280, 720)
var _root: Control
var _black: ColorRect
var _paper: ColorRect
var _paper_mat: ShaderMaterial
var _bloom: ColorRect
var _bloom_mat: ShaderMaterial
var _bloom_tex_size := Vector2.ZERO
var _bloom_region := Rect2()
var _items: Array = []
var _seal: Control
var _overlay: ColorRect
var _hint: Label
var _name := ""
var _head := ""
var _year := ""
var _epi := ""
var _src := ""
var _bg_path := ""
var _focus := Vector2(0.5, 0.5)
var _zoom := 1.0
## 从全黑起（首次进港：卡跟在港页 load_scene 之后，原先先露出 0.1–0.2 秒港页再压黑起卡）
var _from_black := false


## year_override：非空时替换数据里的 year_text。数据里写的是「最早可能开场年」，玩家晚晋升时由调用方
## 按当前历法现算传入（Main 用 Cinematics.year_text(Calendar.year + 跳年, Calendar.ERAS)）。
## from_black：黑场在第 0 帧就压满（跳过 T_BLACK 的淡入），用在卡紧跟一次换页之后。
static func play(parent: Node, chapter_no: int, data_path := "res://data/cutscenes.json", year_override := "",
		from_black := false) -> ChapterCard:
	if parent == null:
		push_warning("ChapterCard.play：parent 为空")
		return null
	var c := ChapterCard.new()
	c.chapter = chapter_no
	c._data_path = data_path
	c._year_override = year_override.strip_edges()
	c._from_black = from_black
	parent.add_child(c)
	return c


func skip() -> void:
	if _t < T_OUT:
		_step(T_OUT - _t)


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Kit.is_headless():
		_finish.call_deferred()
		return
	_read_data()
	_canvas = Kit.canvas_size(self)
	_build()


func _finish() -> void:
	if _done:
		return
	_done = true
	_emit_exiting()
	finished.emit()
	queue_free()


var _exited := false


func _emit_exiting() -> void:
	if _exited:
		return
	_exited = true
	exiting.emit()


func _read_data() -> void:
	var d := Kit.load_json(_data_path)
	var chs: Variant = d.get("chapters", {})
	var entry: Dictionary = {}
	if typeof(chs) == TYPE_DICTIONARY and typeof((chs as Dictionary).get(str(chapter))) == TYPE_DICTIONARY:
		entry = (chs as Dictionary)[str(chapter)]
	elif not d.is_empty():
		push_warning("ChapterCard：%s 没有 chapters[\"%d\"]，只演章名" % [_data_path, chapter])
	_bg_path = str(entry.get("bg", ""))
	# 可选取景：focus（画内中心 0–1）、zoom（在 cover 之上再推近）。墨晕窗是圆的，画里要紧的东西（人）
	# 不该被窗边截一半——要么整个收进窗，要么整个让出去（第 1 轮评审 minor 13，卡 2）
	var fv: Variant = entry.get("focus", [])
	if typeof(fv) == TYPE_ARRAY and (fv as Array).size() == 2:
		_focus = Vector2(float(fv[0]), float(fv[1]))
	_zoom = maxf(1.0, float(entry.get("zoom", 1.0)))
	_epi = str(entry.get("epigraph", ""))
	_src = str(entry.get("epigraph_src", ""))
	_year = _year_override if _year_override != "" else str(entry.get("year_text", ""))
	_head ="第%s章" % Kit.cn_number(chapter)
	var cd := Kit.load_json(Kit.CHAPTERS_DATA)
	var list: Variant = cd.get("chapters", [])
	if typeof(list) == TYPE_ARRAY:
		for c in list:
			if typeof(c) == TYPE_DICTIONARY and int((c as Dictionary).get("id", -1)) == chapter:
				_name = str((c as Dictionary).get("name", ""))
	if _src != "" and not _src.begins_with("—"):
		_src = "——" + _src


func _full(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(r)
	return r


func _text(txt: String, opts: Dictionary, start: float) -> Control:
	var t := InkText.new()
	t.configure(txt, opts)
	t.visible = false
	_root.add_child(t)
	_items.append({"node": t, "start": start, "started": false})
	return t


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_black = _full(Kit.C_JIAOMO)
	_black.modulate.a = 1.0 if _from_black else 0.0

	_paper = _full(Kit.C_XUAN)
	_paper_mat = Kit.material("cs_paper.gdshader")
	if _paper_mat != null:
		_paper_mat.set_shader_parameter("fiber_tex", Kit.fx_texture("noise_fiber.png"))
		_paper_mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
		# UI 线的宣纸贴图（有纤维与杂点）在就用它，与界面同一张纸
		var ptex: Texture2D = Kit.load_texture(PAPER_TEX) if ResourceLoader.exists(PAPER_TEX) else null
		_paper_mat.set_shader_parameter("has_paper_tex", ptex != null)
		if ptex != null:
			_paper_mat.set_shader_parameter("paper_tex", ptex)
		_paper_mat.set_shader_parameter("seed", fmod(float(chapter) * 0.173 + 0.31, 1.0))
		_paper_mat.set_shader_parameter("reveal", 0.0)
		_paper.material = _paper_mat
		_paper.color = Color.WHITE
	else:
		_paper.modulate.a = 0.0

	_bloom = _full(Color(0, 0, 0, 0))
	_bloom_mat = Kit.material("cs_ink_bloom.gdshader")
	var tex: Texture2D = Kit.background(_bg_path) if _bg_path != "" else null
	if _bloom_mat != null:
		_bloom_mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
		_bloom_mat.set_shader_parameter("seed", fmod(float(chapter) * 0.237, 1.0))
		_bloom_mat.set_shader_parameter("progress", 0.0)
		if tex != null:
			_bloom_mat.set_shader_parameter("tex", tex)
			_bloom_tex_size = tex.get_size()
		_bloom.material = _bloom_mat
		_bloom.color = Color.WHITE  # shader 用顶点色的 alpha 承接 modulate；无 shader 时保持透明
	# 这一章没配底图：不演墨晕里的画（否则会露出一团黑），只留纸面与文字
	_bloom.visible = tex != null

	var fs_name := 136
	if _name.length() > 2:
		fs_name = int(clampf(_canvas.y * 0.6 / float(_name.length()) / 1.04, 60.0, 136.0))
	var head := _text(_head, {"font_kind": "title", "size": 50, "spacing": 0.06, "color": INK_TEXT,
		"vertical": true, "effect": 1, "interval": 0.24, "fade": 0.8}, T_HEAD)
	var nm: Control = null
	if _name != "":
		nm = _text(_name, {"font_kind": "title", "size": fs_name, "spacing": 0.04, "color": INK_TEXT,
			"vertical": true, "effect": 1, "interval": 0.38, "fade": 1.0}, T_NAME)
	var yr: Control = null
	if _year != "":
		yr = _text(_year, {"font_kind": "body", "size": 22, "spacing": 0.14, "color": OCHRE_TEXT,
			"vertical": true, "effect": 0, "interval": 0.06, "fade": 0.5}, T_YEAR)
	var ep: Control = null
	if _epi != "":
		ep = _text(_epi, {"font_kind": "body", "size": 23, "spacing": 0.12, "gap": 0.95, "color": INK_TEXT,
			"vertical": true, "max_extent": _canvas.y * 0.5, "effect": 0, "interval": 0.05, "fade": 0.5}, T_EPI)
	var sr: Control = null
	if _src != "":
		var epi_end := T_EPI + (0.05 * float(_epi.length()) + 0.3 if _epi != "" else 0.0)
		sr = _text(_src, {"font_kind": "body", "size": 19, "spacing": 0.1, "color": OCHRE_TEXT,
			"vertical": true, "max_extent": _canvas.y * 0.5, "effect": 0, "interval": 0.04, "fade": 0.4}, epi_end)
	var s := Seal.new()
	s.configure(SEAL_TEXT, {"cell": 38.0, "style": "baiwen", "hollow_alpha": 0.0, "seed": fmod(float(chapter) * 0.41, 1.0), "tilt": -0.035})
	s.visible = false
	s.impacted.connect(func() -> void: _jolt = 1.0)
	_root.add_child(s)
	_items.append({"node": s, "start": T_SEAL, "started": false})
	_seal = s

	_overlay = _full(Color(0, 0, 0, 0))
	var om := Kit.material("cs_overlay.gdshader")
	if om != null:
		om.set_shader_parameter("grain_tex", Kit.fx_texture("noise_grain.png"))
		om.set_shader_parameter("vignette", 0.3)
		om.set_shader_parameter("grain", 0.022)
		_overlay.material = om
		_overlay.color = Color.WHITE
	_overlay.modulate.a = 0.0
	# 章名写出之后，纸脚淡淡出一行「点击继续」（7.4 秒的卡全程没有提示，第 1 轮评审 minor）
	_hint = Label.new()
	_hint.text = "点击继续"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_override("font", Kit.body_font())
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", OCHRE_TEXT)
	_hint.modulate.a = 0.0
	_root.add_child(_hint)
	_layout(head, nm, yr, ep, sr)


## 竖排自右向左：「第X章」→ 章名 → 年号 → 题记 → 出处；印在「第X章」下方。油画墨晕占左侧余下的纸面。
func _layout(head: Control, nm: Control, yr: Control, ep: Control, sr: Control) -> void:
	var W := _canvas.x
	var H := _canvas.y
	var top := roundf(H * 0.15)
	var x := W - maxf(W * 0.07, 64.0)
	head.position = Vector2(roundf(x - head.size.x), top)
	var left := head.position.x
	_seal.position = Vector2(roundf(head.position.x + (head.size.x - _seal.size.x) * 0.5), roundf(top + head.size.y + 30.0))
	if nm != null:
		nm.position = Vector2(roundf(left - 22.0 - nm.size.x), top + 4.0)
		left = nm.position.x
	if yr != null:
		yr.position = Vector2(roundf(left - 24.0 - yr.size.x), top + 14.0)
		left = yr.position.x
	if ep != null:
		ep.position = Vector2(roundf(left - 34.0 - ep.size.x), top + 14.0)
		left = ep.position.x
	if sr != null:
		var sy := top + 14.0
		if ep != null and ep.size.y > sr.size.y:
			sy = ep.position.y + ep.size.y - sr.size.y
		sr.position = Vector2(roundf(left - 14.0 - sr.size.x), roundf(sy))
		left = sr.position.x
	# 墨晕区：纸面左侧到文字块左缘
	var rl := W * 0.035
	var rr := maxf(left - 44.0, W * 0.45)
	_bloom_region = Rect2(rl, H * 0.06, rr - rl, H * 0.88)
	if _bloom_mat != null:
		var cx := (_bloom_region.position.x + _bloom_region.size.x * 0.5) / W
		var rad := clampf(_bloom_region.size.x * 0.5 * 0.86 / H * 0.9, 0.25, 0.5)
		_bloom_mat.set_shader_parameter("center", Vector2(cx, 0.5))
		_bloom_mat.set_shader_parameter("radius", rad)
		_bloom_mat.set_shader_parameter("canvas_size", _canvas)
	if _paper_mat != null:
		_paper_mat.set_shader_parameter("canvas_size", _canvas)
	var om := _overlay.material as ShaderMaterial
	if om != null:
		om.set_shader_parameter("canvas_size", _canvas)


func _update_bloom_view() -> void:
	if _bloom_mat == null or _bloom_tex_size == Vector2.ZERO:
		return
	# 墨晕区内按 cover 取景，并随整张卡极慢推近
	var z := _zoom * (1.02 + 0.06 * Kit.ease_in_out_sine(_t / T_END))
	var crop := Kit.cover_view(_bloom_tex_size, _bloom_region.size, _focus, z)
	var rs := _bloom_region.size
	var vx := crop.position.x - _bloom_region.position.x / rs.x * crop.size.x
	var vy := crop.position.y - _bloom_region.position.y / rs.y * crop.size.y
	var vw := _canvas.x / rs.x * crop.size.x
	var vh := _canvas.y / rs.y * crop.size.y
	_bloom_mat.set_shader_parameter("view", Vector4(vx, vy, vw, vh))


func _process(delta: float) -> void:
	if _done or _root == null:
		return
	_step(delta)


func _step(dt: float) -> void:
	_t += dt
	var cv := Kit.canvas_size(self)
	if cv != _canvas:
		_canvas = cv
	# 黑场 → 宣纸按噪声阈值洇进来（ease_in_out 1.0 秒，没有「半透明纸压黑底」的灰褐过渡）；退场同一阈值从墨晕窗口往外退
	_black.modulate.a = 1.0 if _from_black else Kit.ease_in_out(_t / T_BLACK)
	var wipe_q := (_t - T_WIPE) / (T_END - T_WIPE)
	# 进场：线性与 ease_in_out 各半——纯 ease_in_out 时覆盖率仍有四成挤在中段 0.2 秒里（实测逐帧均亮度 35→101→153）
	var in_q := clampf((_t - T_PAPER_IN) / T_PAPER_DUR, 0.0, 1.0)
	var paper_r := minf(in_q * 0.5 + Kit.ease_in_out(in_q) * 0.5,
		1.0 - Kit.ease_in_out(wipe_q))
	if _paper_mat != null:
		_paper_mat.set_shader_parameter("reveal", paper_r)
		# 退场时阈值场以墨晕窗中心为原点反过来：纸从窗口往外退（进场仍从画面中偏右处洇开）
		var leaving := _t >= T_WIPE
		_paper_mat.set_shader_parameter("reveal_outward", leaving)
		# 外退场的阈值场分布（约 0.37–0.90）比进场（约 0.03–0.56）整体偏高，扫描区间跟着换
		_paper_mat.set_shader_parameter("thr_lo", 0.15 if leaving else -0.12)
		_paper_mat.set_shader_parameter("thr_hi", 0.98 if leaving else 0.80)
		if leaving and _bloom_region.size.x > 0.0:
			var ctr := _bloom_region.position + _bloom_region.size * 0.5
			_paper_mat.set_shader_parameter("reveal_origin", Vector2(ctr.x / maxf(_canvas.x, 1.0), ctr.y / maxf(_canvas.y, 1.0)))
	else:
		_paper.modulate.a = paper_r
	# 纸铺满后黑底就没用了；退场时纸退去的地方要直接露出游戏
	_black.visible = _t < T_PAPER_IN + T_PAPER_DUR + 0.05
	# 暗角颗粒跟纸走，但退得比纸晚：纸退到一半前暗角不减，免得正在退去的纸先「提亮」一下
	_overlay.modulate.a = clampf(paper_r * 2.0, 0.0, 1.0)
	var om := _overlay.material as ShaderMaterial
	if om != null:
		om.set_shader_parameter("time_s", _t)
	# 黑场压满的那一帧预热管线与字形：卡也卡在黑里
	if not _warmed and _t >= T_BLACK:
		_warmed = true
		_prewarm()
	# 墨晕：铺开；退场时回缩并淡去
	var prog := Kit.ease_out_cubic((_t - T_BLOOM) / T_BLOOM_DUR)
	var fade_all := 1.0
	if _t >= T_OUT:
		var q := (_t - T_OUT) / BLOOM_OUT
		prog *= 1.0 - 0.45 * Kit.ease_in_out(q)
		fade_all = 1.0 - Kit.ease_in_out(q)
	if _bloom_mat != null:
		_bloom_mat.set_shader_parameter("progress", lerpf(-0.14, 1.02, prog))
		_bloom_mat.set_shader_parameter("alpha", fade_all)
	_update_bloom_view()
	for it in _items:
		var node = it["node"]
		var local := _t - float(it["start"])
		if not it["started"]:
			if local < 0.0:
				continue
			it["started"] = true
			node.visible = true
			node.advance(local)
		else:
			node.advance(dt)
		if _t >= T_OUT:
			node.fade_out(TEXT_OUT)
	# 盖印那一下，整张纸轻轻一震
	_jolt = maxf(0.0, _jolt - dt * 6.0)
	_root.position = Vector2(0.0, 2.5 * _jolt * sin(_t * 90.0))
	if _hint != null:
		var hs := _hint.get_minimum_size()
		_hint.position = Vector2(roundf(_canvas.x - hs.x - maxf(_canvas.x * 0.07, 64.0)), roundf(_canvas.y * 0.9 - hs.y))
		# α0.62 时 16px 赭石字实测只有 2.3:1（第 2 轮 UX minor 5），提到 0.92
		_hint.modulate.a = 0.92 * Kit.ease_in_out((_t - T_NAME) / 0.6) * (1.0 - Kit.ease_in_out((_t - T_OUT) / 0.4))
	if _t >= T_WIPE - 0.05:
		_emit_exiting()
	if _t >= T_END:
		_finish()


## 管线预热 + 还没出场的字预先光栅化（章名 136px 带凝字描边，逐字首次出现时单字可达数毫秒）
func _prewarm() -> void:
	Kit.prewarm(self)
	if _t >= T_HEAD:
		return
	for it in _items:
		var node: Node = it["node"]
		if not it["started"] and node.has_method("prewarm"):
			node.call("prewarm")


func _input(event: InputEvent) -> void:
	if _done or _root == null:
		return
	var go := false
	var esc := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			esc = k.keycode == KEY_ESCAPE
			go = k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		go = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		esc = mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT
		get_viewport().set_input_as_handled()
	if esc:
		skip()
	elif go:
		if _t < T_SEAL + 0.5:
			_step(T_SEAL + 0.5 - _t)
			for it in _items:
				it["node"].finish_reveal()
		elif _t < T_OUT:
			skip()
