## 过场播放器（cutscene_engine 线）。零外部依赖：只读 data/cutscenes.json 与 assets/。
##
##   var p := CutscenePlayer.play(self, "prologue")
##   await p.finished
##
## · finished 在画面**全黑**时发出——此刻底下换场景 / 换底图 / 弹结算框都看不见；随后本层自行淡出并 queue_free。
## · headless（DisplayServer 为 headless）：call_deferred 立即 finished，不建任何节点。
## · 找不到 id / 没有镜头：push_warning 后同样立即 finished，绝不卡住游戏。
## · 操作：点击 / 空格 / 回车 = 当前字幕立即显示全 → 再按提前出下一条字幕 → 再按跳下一镜；Esc = 跳过整段。
## · 过场期间吞掉全部键盘与鼠标点击（_input + set_input_as_handled），游戏 UI 收不到。
class_name CutscenePlayer
extends CanvasLayer

signal finished

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const InkText := preload("res://scripts/cutscene/cs_ink_text.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")
const Fx := preload("res://scripts/cutscene/cs_fx.gd")

const LAYER_INDEX := 50
const PRE_ROLL := 0.45
## 全黑后多停的一小段：预热那一帧的卡顿落在这里
const PRE_HOLD := 0.12
const LETTERBOX_IN := 1.2
const LETTERBOX_FRAC := 0.118
const OUTRO_BLACK := 1.0
const OUTRO_FADE := 0.7
const SKIP_BLACK := 0.35
const SKIP_FADE := 0.45
const CAPTION_OUT := 0.55
const FX_XFADE := 1.0
const FLASH_DUR := 0.8
const TRANS := {"ink": 2.3, "fade": 1.3, "flash": 0.8, "cut": 0.0}
## 游戏名：title 样式的字幕等于它、且 UI 线横版书法 logo 在时，改画 logo（与标题画面同一版）
const GAME_TITLE := "东亚海域立志传"
const LOGO_TEX := "res://assets/ui/nk1/logo_title_h_gold.png"

## 字幕样式（1280×720 画布下的字号）
const STYLES := {
	"title": {"font_kind": "title", "size": 76, "spacing": 0.14, "gap": 0.35, "color": Color(0.914, 0.863, 0.753), "halo": 1.45, "backing": 0.58, "effect": 1, "interval": 0.24, "fade": 1.1},
	"era": {"font_kind": "body", "size": 22, "spacing": 0.45, "gap": 0.6, "color": Color(0.95, 0.86, 0.62), "halo": 1.4, "backing": 0.62, "effect": 0, "interval": 0.07, "fade": 0.6},
	"line": {"font_kind": "body", "size": 27, "spacing": 0.05, "gap": 0.55, "color": Color(0.914, 0.863, 0.753), "halo": 0.9, "effect": 0, "interval": 0.045, "fade": 0.35},
	"narration": {"font_kind": "body", "size": 24, "spacing": 0.1, "gap": 0.75, "color": Color(0.9, 0.85, 0.74), "halo": 0.85, "backing": 0.55, "effect": 0, "interval": 0.055, "fade": 0.5},
}

enum Phase { PRE, PLAY, OUTRO, FADE, DONE }


## 开场结尾的游戏名：用 UI 线的横版书法 logo（飞白、泥金描边、自带「立志」小印），由左至右「写」出来，
## 背后先垫一团柔墨托住。与 cs_ink_text 同一时间协议（advance / finish_reveal / fade_out / is_gone）。
class LogoCaption:
	extends Control
	const REVEAL := 2.2
	const BACK_IN := 0.8
	var backing := 0.8
	var _t := 0.0
	var _out_start := -1.0
	var _out_dur := 0.5
	var _logo: TextureRect
	var _back: TextureRect
	var _mat: ShaderMaterial
	var _back_color := Color.BLACK

	func setup(tex: Texture2D, width: float, back_tex: Texture2D, back_color: Color, mat: ShaderMaterial) -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		var ts := tex.get_size()
		size = Vector2(roundf(width), roundf(width * ts.y / maxf(ts.x, 1.0)))
		custom_minimum_size = size
		pivot_offset = size * 0.5
		_back_color = back_color
		if back_tex != null:
			_back = TextureRect.new()
			_back.texture = back_tex
			_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_back.stretch_mode = TextureRect.STRETCH_SCALE
			_back.mouse_filter = MOUSE_FILTER_IGNORE
			var pad := Vector2(size.x * 0.2, size.y * 0.8)
			_back.position = -pad
			_back.size = size + pad * 2.0
			add_child(_back)
		_logo = TextureRect.new()
		_logo.texture = tex
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_SCALE
		_logo.mouse_filter = MOUSE_FILTER_IGNORE
		# logo 原图 2434 宽，显示约 700：走 mipmap 缩小，飞白不闪
		_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_logo.size = size
		_mat = mat
		if _mat != null:
			_mat.set_shader_parameter("rect_px", size)
			_logo.material = _mat
		add_child(_logo)
		_apply()

	func advance(dt: float) -> void:
		_t += dt
		_apply()

	func reveal_duration() -> float:
		return REVEAL

	func is_revealed() -> bool:
		return _t >= REVEAL

	func finish_reveal() -> void:
		_t = maxf(_t, REVEAL)
		_apply()

	func fade_out(duration: float) -> void:
		if _out_start >= 0.0:
			return
		_out_start = _t
		_out_dur = maxf(duration, 0.01)

	func is_fading() -> bool:
		return _out_start >= 0.0

	func is_gone() -> bool:
		return _out_start >= 0.0 and _t >= _out_start + _out_dur

	func _apply() -> void:
		var out_a := 1.0
		if _out_start >= 0.0:
			var q := clampf((_t - _out_start) / _out_dur, 0.0, 1.0)
			out_a = 1.0 - q * q * (3.0 - 2.0 * q)
		var p := clampf(_t / REVEAL, 0.0, 1.0)
		# 前沿先快后慢：落笔有力、收笔从容
		var prog := 1.0 - pow(1.0 - p, 1.7)
		var s := 1.0 + 0.035 * pow(1.0 - p, 2.0)
		scale = Vector2(s, s)
		if _mat != null:
			_mat.set_shader_parameter("progress", prog)
			_logo.modulate.a = out_a
		else:
			_logo.modulate.a = prog * out_a
		if _back != null:
			var b := clampf(_t / BACK_IN, 0.0, 1.0)
			_back.modulate = Color(_back_color, backing * b * b * (3.0 - 2.0 * b) * out_a)

## 调试：为真时每镜开始打印一行（预览场景打开）
static var verbose := false
## 调试：从第几镜开始播（预览场景 --from=<n>；游戏里恒为 0）
static var debug_start_shot := 0

var cutscene_id := ""
var _data_path := "res://data/cutscenes.json"
var _from_black := false
var _shots: Array = []
var _letterbox := true
var _phase := Phase.PRE
var _clock := 0.0
var _phase_t := 0.0
var _idx := -1
var _shot_t := 0.0
var _shot_dur := 1.0
var _emitted := false
var _fast := false
var _jolt := 0.0
var _canvas := Vector2(1280, 720)

var _root: Control
var _base: ColorRect
var _layers: Array = []
var _front := -1
var _fx_root: Control
var _fx_cur: Node2D
var _fx_t := 0.0
var _fx_in_dur := 1.0
var _fx_old: Array = []
var _overlay: ColorRect
var _flash: ColorRect
var _captions: Control
var _cap_live: Array = []
var _cap_old: Array = []
var _groups: Dictionary = {}
var _lb_top: ColorRect
var _lb_bot: ColorRect
var _dimmer: ColorRect
var _hint: Label
var _warmed := false
## 预建的印章：键 "镜号:字幕序号"
var _seal_pool: Dictionary = {}


## from_black：从全黑起播（开机即演开场时用：第一帧就是黑的，底下场景在黑幕后就位，不会先闪一下再压黑）
static func play(parent: Node, id: String, data_path := "res://data/cutscenes.json", from_black := false) -> CutscenePlayer:
	if parent == null:
		push_warning("CutscenePlayer.play：parent 为空，过场 %s 未播放" % id)
		return null
	var p := CutscenePlayer.new()
	p.cutscene_id = id
	p._data_path = data_path
	p._from_black = from_black
	parent.add_child(p)
	return p


## 该 id 在数据里是否存在（调用方可据此决定要不要等 finished）
static func has_cutscene(id: String, data_path := "res://data/cutscenes.json") -> bool:
	var d := Kit.load_json(data_path)
	var all: Variant = d.get("cutscenes", {})
	return typeof(all) == TYPE_DICTIONARY and (all as Dictionary).has(id)


## 结局名（= Main.gd ENDING_BG 的键）→ 过场 id；数据里没配返回 ""
static func ending_id(ending: String, data_path := "res://data/cutscenes.json") -> String:
	var d := Kit.load_json(data_path)
	var m: Variant = d.get("endings", {})
	if typeof(m) != TYPE_DICTIONARY:
		return ""
	return str((m as Dictionary).get(ending, ""))


## 播结局过场；该结局没配过场或 parent 为空时返回 null（调用方直接走原流程，不必 await）
static func play_ending(parent: Node, ending: String, data_path := "res://data/cutscenes.json") -> CutscenePlayer:
	var id := ending_id(ending, data_path)
	if id == "" or not has_cutscene(id, data_path):
		return null
	return play(parent, id, data_path)


func is_playing() -> bool:
	return _phase == Phase.PRE or _phase == Phase.PLAY


## 跳过整段（Esc 同效）
func skip() -> void:
	if _phase == Phase.FADE or _phase == Phase.DONE or (_phase == Phase.OUTRO and _fast):
		return
	_begin_outro(true)


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Kit.is_headless():
		_finish_now.call_deferred()
		return
	var data := Kit.load_json(_data_path)
	var all: Variant = data.get("cutscenes", {})
	if typeof(all) != TYPE_DICTIONARY or not (all as Dictionary).has(cutscene_id):
		push_warning("过场 %s 不在 %s 里，跳过" % [cutscene_id, _data_path])
		_finish_now.call_deferred()
		return
	var cs: Variant = (all as Dictionary)[cutscene_id]
	if typeof(cs) != TYPE_DICTIONARY or typeof((cs as Dictionary).get("shots")) != TYPE_ARRAY or ((cs as Dictionary)["shots"] as Array).is_empty():
		push_warning("过场 %s 没有镜头，跳过" % cutscene_id)
		_finish_now.call_deferred()
		return
	_shots = (cs as Dictionary)["shots"]
	_letterbox = bool((cs as Dictionary).get("letterbox", true))
	for s in _shots:
		if typeof(s) == TYPE_DICTIONARY:
			Kit.preload_background(str((s as Dictionary).get("bg", "")))
	_canvas = Kit.canvas_size(self)
	_build()


func _finish_now() -> void:
	_emit_finished()
	_phase = Phase.DONE
	queue_free()


func _exit_tree() -> void:
	var paths: Array = []
	for s in _shots:
		if typeof(s) == TYPE_DICTIONARY:
			paths.append(str((s as Dictionary).get("bg", "")))
	Kit.drop_preloads(paths)


func _emit_finished() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit()


# ── 节点搭建 ───────────────────────────────────────────
func _full_rect(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(r)
	return r


func _build() -> void:
	_root = Control.new()
	_root.name = "CutsceneRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_base = _full_rect(Kit.C_JIAOMO)
	_base.modulate.a = 0.0
	if _from_black:
		# 跳过压黑段：本帧起就是全黑，下一帧预热、再停 PRE_HOLD 进第一镜
		_base.modulate.a = 1.0
		_phase_t = PRE_ROLL
	for i in range(2):
		var r := _full_rect(Color.BLACK)
		r.name = "Shot%d" % i
		r.visible = false
		var m := Kit.material("cs_shot.gdshader")
		if m != null:
			m.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
			m.set_shader_parameter("ink_color", Kit.C_JIAOMO)
			r.material = m
		_layers.append({"rect": r, "mat": m, "t": 0.0, "dur": 1.0, "tex_size": Vector2(1672, 941),
			"from": Vector3(0.5, 0.5, 1.0), "to": Vector3(0.5, 0.5, 1.0), "shake": 0.0,
			"trans": "cut", "trans_dur": 0.0, "has_back": false, "done": true})

	_fx_root = Control.new()
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_fx_root)

	_overlay = _full_rect(Color(0, 0, 0, 0))
	var om := Kit.material("cs_overlay.gdshader")
	if om != null:
		om.set_shader_parameter("grain_tex", Kit.fx_texture("noise_grain.png"))
		om.set_shader_parameter("vignette", 0.5)
		om.set_shader_parameter("grain", 0.04)
		_overlay.material = om
		_overlay.color = Color.WHITE  # shader 用顶点色 alpha 承接 modulate；无 shader 时保持透明

	# 闪白用加色混合：像一道光打过来，而不是蒙一层灰；压在画幅黑边之下
	_flash = _full_rect(Color(1.0, 0.9, 0.74))
	var fm := CanvasItemMaterial.new()
	fm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = fm
	_flash.modulate.a = 0.0

	_lb_top = _full_rect(Kit.C_JIAOMO)
	_lb_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lb_bot = _full_rect(Kit.C_JIAOMO)
	_lb_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lb_top.visible = _letterbox
	_lb_bot.visible = _letterbox

	_captions = Control.new()
	_captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_captions.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_captions)

	_hint = Label.new()
	_hint.text = "跳过 ›　Esc ／ 右键"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_override("font", Kit.body_font())
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Kit.C_XUAN)
	_hint.add_theme_color_override("font_shadow_color", Color(Kit.C_JIAOMO, 0.8))
	_hint.add_theme_constant_override("shadow_offset_x", 0)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.modulate.a = 0.0
	_root.add_child(_hint)

	_dimmer = _full_rect(Kit.C_JIAOMO)
	_dimmer.modulate.a = 0.0
	_update_letterbox()
	_sync_canvas_uniforms()


func _sync_canvas_uniforms() -> void:
	var om := _overlay.material as ShaderMaterial
	if om != null:
		om.set_shader_parameter("canvas_size", _canvas)
	for L in _layers:
		if L["mat"] != null:
			L["mat"].set_shader_parameter("aspect", _canvas.x / maxf(_canvas.y, 1.0))


# ── 主循环 ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if _phase == Phase.DONE or _root == null:
		return
	_clock += delta
	_phase_t += delta
	var cv := Kit.canvas_size(self)
	if cv != _canvas:
		_canvas = cv
		_place_captions()
		_sync_canvas_uniforms()
	match _phase:
		Phase.PRE:
			_base.modulate.a = Kit.ease_in_out(_phase_t / PRE_ROLL)
			if _phase_t >= PRE_ROLL and not _warmed:
				# 画面刚压到全黑：这一帧预热管线、预建全片的印章（字形光栅化 + SubViewport），卡也卡在黑场里
				_base.modulate.a = 1.0
				_warmed = true
				_prewarm()
			elif _phase_t >= PRE_ROLL + PRE_HOLD:
				_base.modulate.a = 1.0
				_phase = Phase.PLAY
				_phase_t = 0.0
				_begin_shot(clampi(debug_start_shot, 0, _shots.size() - 1))
		Phase.PLAY:
			_shot_t += delta
			if _shot_t >= _shot_dur:
				if _idx + 1 < _shots.size():
					_begin_shot(_idx + 1)
				else:
					_begin_outro(false)
		Phase.OUTRO:
			var bd := SKIP_BLACK if _fast else OUTRO_BLACK
			_dimmer.modulate.a = Kit.ease_in_out(_phase_t / bd)
			if _phase_t >= bd:
				_dimmer.modulate.a = 1.0
				_emit_finished()
				_phase = Phase.FADE
				_phase_t = 0.0
				_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# modulate 不是整组合成：只留黑幕自己淡出，其余全部藏掉，免得底下的画面半透明回光
				for c in _root.get_children():
					if c != _dimmer:
						(c as CanvasItem).visible = false
		Phase.FADE:
			var fd := SKIP_FADE if _fast else OUTRO_FADE
			_dimmer.modulate.a = 1.0 - Kit.ease_in_out(_phase_t / fd)
			if _phase_t >= fd:
				_phase = Phase.DONE
				queue_free()
			return
	_jolt = maxf(0.0, _jolt - delta * 2.2)
	var om := _overlay.material as ShaderMaterial
	if om != null:
		om.set_shader_parameter("time_s", _clock)
	_update_letterbox()
	_update_layers(delta)
	_update_captions(delta)
	_update_fx(delta)
	_update_hint()


func _input(event: InputEvent) -> void:
	if _root == null or _phase == Phase.FADE or _phase == Phase.DONE:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE:
				skip()
			elif k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				_advance_input()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键即跳过：只用鼠标的玩家不必逐镜点 20 下（第 1 轮评审 minor）
			skip()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# 点角上的「跳过」提示 = 跳过；点别处照旧「补全 → 下一句 → 下一镜」
			if _hint != null and _hint.modulate.a > 0.05 and _hint.get_global_rect().grow(10.0).has_point(mb.position):
				skip()
			else:
				_advance_input()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_advance_input()
		get_viewport().set_input_as_handled()


func _advance_input() -> void:
	if verbose:
		print("CUTSCENE %s advance-input at clock=%.2f shot=%d t=%.2f" % [cutscene_id, _clock, _idx, _shot_t])
	if _phase == Phase.PRE:
		if _phase_t < PRE_ROLL:
			_phase_t = PRE_ROLL
		return
	if _phase != Phase.PLAY:
		return
	# 第一下：转场没走完就先把转场补完（新画面整张露出），不去挪字幕——免得印章字幕提前亮在黑场上
	if _complete_transition():
		return
	var revealing := false
	for e in _cap_live:
		if e["started"] and not e["node"].is_revealed():
			e["node"].finish_reveal()
			revealing = true
	if revealing:
		return
	var next_t := INF
	for e in _cap_live:
		if not e["started"]:
			next_t = minf(next_t, float(e["t"]))
	if next_t < INF:
		var shift := maxf(next_t - _shot_t, 0.0)
		for e in _cap_live:
			if not e["started"]:
				e["t"] = float(e["t"]) - shift
		_shot_dur = maxf(_shot_dur - shift, _shot_t + 1.5)
		return
	if _idx + 1 < _shots.size():
		_begin_shot(_idx + 1)
	else:
		_begin_outro(false)


# ── 镜头 ───────────────────────────────────────────────
## 前层转场若还没走完：立刻补完（新画面整张显示、旧画面藏起、旧粒子速退、新粒子 0.3 秒内到位）。补了返回 true。
func _complete_transition() -> bool:
	if _front < 0:
		return false
	var F: Dictionary = _layers[_front]
	if bool(F["done"]) or float(F["trans_dur"]) <= 0.0:
		return false
	F["done"] = true
	_set_mode(F, 0, 1.0)
	var B: Dictionary = _layers[1 - _front]
	(B["rect"] as ColorRect).visible = false
	if B["mat"] != null:
		B["mat"].set_shader_parameter("dim", 0.0)
	for f in _fx_old:
		f["a0"] = (f["node"] as Node2D).modulate.a
		f["kind"] = "flash"
		f["t"] = 0.0
	if _fx_cur != null and _fx_in_dur > 0.0:
		var a := _fx_cur.modulate.a
		_fx_in_dur = 0.3
		_fx_t = a * _fx_in_dur
	if verbose:
		print("CUTSCENE %s transition completed by input at shot t=%.2f" % [cutscene_id, _shot_t])
	return true


func _begin_shot(i: int) -> void:
	var shot: Dictionary = _shots[i] if typeof(_shots[i]) == TYPE_DICTIONARY else {}
	if verbose:
		print("CUTSCENE %s shot %d at clock=%.2f" % [cutscene_id, i, _clock])
	_idx = i
	_shot_t = 0.0
	_shot_dur = maxf(Kit.float_of(shot.get("duration"), 5.0), 0.5)
	var prev := _front
	var nf := 0 if prev < 0 else 1 - prev
	if prev >= 0:
		# 上一镜若被点击打断在转场中途，先让它完整显示，免得新镜头底下露黑
		var pl: Dictionary = _layers[prev]
		pl["done"] = true
		_set_mode(pl, 0, 1.0)
		if pl["mat"] != null:
			pl["mat"].set_shader_parameter("dim", 0.0)
	var L: Dictionary = _layers[nf]
	var tex := Kit.background(str(shot.get("bg", "")))
	var grade := str(shot.get("grade", "neutral"))
	L["tex_size"] = tex.get_size() if tex != null else Vector2(1672, 941)
	L["from"] = Kit.cam_of(shot.get("cam_from"))
	L["to"] = Kit.cam_of(shot.get("cam_to", shot.get("cam_from")))
	L["t"] = 0.0
	L["dur"] = _shot_dur
	L["shake"] = clampf(Kit.float_of(shot.get("shake"), 0.0), 0.0, 1.0)
	var kind := str(shot.get("transition_in", "fade" if i == 0 else "ink"))
	if not TRANS.has(kind):
		push_warning("过场 %s 第 %d 镜：未知转场 %s，按 fade" % [cutscene_id, i, kind])
		kind = "fade"
	L["trans"] = kind
	L["trans_dur"] = minf(float(TRANS[kind]), _shot_dur * 0.8)
	L["has_back"] = prev >= 0
	L["done"] = float(L["trans_dur"]) <= 0.0
	var m: ShaderMaterial = L["mat"]
	if m != null:
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("aspect", _canvas.x / maxf(_canvas.y, 1.0))
		m.set_shader_parameter("seed", fmod(float(i) * 0.1731 + 0.29, 1.0))
		m.set_shader_parameter("ink_origin", Vector2(0.5 + 0.14 * sin(float(i) * 2.3 + 0.6), 0.55 + 0.1 * cos(float(i) * 1.7)))
		m.set_shader_parameter("dim", 0.0)
		Kit.apply_grade(m, grade)
	var r: ColorRect = L["rect"]
	r.visible = true
	if prev >= 0:
		_root.move_child(_layers[prev]["rect"], _base.get_index() + 1)
	_root.move_child(r, _base.get_index() + 2)
	_front = nf
	_update_layers(0.0)
	# 字幕：上一镜的全部退场——硬切当帧清掉（一刀切干净）；闪白 0.15 秒速退；其余随转场淡出
	if kind == "cut":
		for e in _cap_old:
			e["node"].queue_free()
		_cap_old = []
	for e in _cap_live:
		if e["started"] and kind != "cut":
			e["node"].fade_out(0.15 if kind == "flash" else CAPTION_OUT)
			_cap_old.append(e)
		else:
			e["node"].queue_free()
	_cap_live = []
	_build_captions(shot)
	_swap_fx(shot, grade)


func _set_mode(L: Dictionary, mode: int, reveal: float) -> void:
	var m: ShaderMaterial = L["mat"]
	if m == null:
		return
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("reveal", reveal)


func _update_layers(dt: float) -> void:
	for k in range(_layers.size()):
		var L: Dictionary = _layers[k]
		var r: ColorRect = L["rect"]
		if not r.visible:
			continue
		L["t"] = float(L["t"]) + dt
		_apply_cam(L, k == _front)
	if _front < 0:
		return
	var F: Dictionary = _layers[_front]
	var B: Dictionary = _layers[1 - _front]
	var td: float = F["trans_dur"]
	var rr := 1.0 if (bool(F["done"]) or td <= 0.0) else clampf(float(F["t"]) / td, 0.0, 1.0)
	var kind: String = F["trans"]
	var flash_a := 0.0
	if rr < 1.0:
		match kind:
			"ink":
				_set_mode(F, 1, 0.55 * rr + 0.45 * Kit.ease_in_out_sine(rr))
			"fade":
				if bool(F["has_back"]):
					_set_mode(F, 2, smoothstep(0.45, 1.0, rr))
					if B["mat"] != null:
						B["mat"].set_shader_parameter("dim", smoothstep(0.0, 0.5, rr))
				else:
					_set_mode(F, 2, Kit.ease_in_out(rr))
			_:
				_set_mode(F, 0, 1.0)
	elif not bool(F["done"]):
		F["done"] = true
		_set_mode(F, 0, 1.0)
	if bool(F["done"]):
		var br: ColorRect = B["rect"]
		if br.visible:
			br.visible = false
			if B["mat"] != null:
				B["mat"].set_shader_parameter("dim", 0.0)
	if kind == "flash" and float(F["t"]) < FLASH_DUR:
		flash_a = 0.85 * exp(-float(F["t"]) * 5.0)
	_flash.modulate.a = maxf(flash_a, 0.0)


func _apply_cam(L: Dictionary, front: bool) -> void:
	var m: ShaderMaterial = L["mat"]
	if m == null:
		return
	var t: float = L["t"]
	var u := t / maxf(float(L["dur"]), 0.01)
	# 一半线性一半正弦缓动：起止都不停死；镜头结束后按末速度的一半继续漂（转场期间不冻结）
	var e := 0.5 * u + 0.5 * Kit.ease_in_out_sine(u) if u <= 1.0 else 1.0 + 0.5 * (u - 1.0)
	var a: Vector3 = L["from"]
	var b: Vector3 = L["to"]
	var ctr := Vector2(lerpf(a.x, b.x, e), lerpf(a.y, b.y, e))
	var z := exp(lerpf(log(a.z), log(b.z), e))
	var sh: float = L["shake"]
	if front:
		sh += _jolt
	var off := Vector2.ZERO
	if sh > 0.001:
		z *= 1.0 + 0.05 * minf(sh, 1.0)
		off = _shake_offset(t, sh)
	var v := Kit.cover_view(L["tex_size"], _canvas, ctr, maxf(z, 1.0))
	v.position += Vector2(off.x / _canvas.x * v.size.x, off.y / _canvas.y * v.size.y)
	v.position = v.position.clamp(Vector2.ZERO, Vector2.ONE - v.size)
	m.set_shader_parameter("view", Vector4(v.position.x, v.position.y, v.size.x, v.size.y))


func _shake_offset(t: float, s: float) -> Vector2:
	var env := 0.55 + 0.45 * exp(-t * 1.6)
	var amp := s * 15.0 * env
	return Vector2(
		sin(t * 21.0) * 0.55 + sin(t * 33.7 + 1.3) * 0.3 + sin(t * 57.1 + 0.7) * 0.15,
		sin(t * 24.3 + 2.0) * 0.55 + sin(t * 39.1 + 0.4) * 0.3 + sin(t * 61.7 + 1.1) * 0.15) * amp


func _begin_outro(fast: bool) -> void:
	_fast = fast
	_phase = Phase.OUTRO
	_phase_t = 0.0
	for e in _cap_live:
		if e["started"]:
			e["node"].fade_out(0.35 if fast else CAPTION_OUT)
			_cap_old.append(e)
		else:
			e["node"].queue_free()
	_cap_live = []


# ── 画幅 / 提示 ───────────────────────────────────────
func _bar_full() -> float:
	return roundf(_canvas.y * LETTERBOX_FRAC) if _letterbox else 0.0


func _update_letterbox() -> void:
	if not _letterbox or _lb_top == null:
		return
	var h := roundf(_bar_full() * Kit.ease_out_cubic(_clock / LETTERBOX_IN))
	_lb_top.offset_top = 0.0
	_lb_top.offset_bottom = h
	_lb_bot.offset_top = -h
	_lb_bot.offset_bottom = 0.0


func _update_hint() -> void:
	if _hint == null:
		return
	var a := 0.74 * Kit.ease_in_out((_clock - 0.6) / 1.0)
	if _phase == Phase.OUTRO:
		a *= 1.0 - _dimmer.modulate.a
	_hint.modulate.a = a
	var hs := _hint.get_minimum_size()
	var bar := _bar_full()
	var y := _canvas.y - bar * 0.5 - hs.y * 0.5 if bar > hs.y + 8.0 else _canvas.y - hs.y - 14.0
	_hint.position = Vector2(_canvas.x - hs.x - 28.0, y)


# ── 字幕 ───────────────────────────────────────────────
func _default_pos(style: String) -> String:
	match style:
		"title", "era", "seal":
			return "center"
		"narration":
			return "lower_left"
	return "bottom"


func _make_caption(txt: String, style: String, pos: String, n: int) -> Control:
	if txt.strip_edges() == "":
		return null
	var vert := pos == "right_vertical" or pos == "left_vertical"
	if style == "seal":
		var key := "%d:%d" % [_idx, n]
		if _seal_pool.has(key):
			var pooled: Control = _seal_pool[key]
			_seal_pool.erase(key)
			return pooled
		return _new_seal(txt, n, _idx)
	if not STYLES.has(style):
		push_warning("过场 %s：未知字幕样式 %s，按 line" % [cutscene_id, style])
	if style == "title" and txt.strip_edges() == GAME_TITLE and ResourceLoader.exists(LOGO_TEX):
		var logo_tex := Kit.load_texture(LOGO_TEX)
		if logo_tex != null:
			var lc := LogoCaption.new()
			var wm := Kit.material("cs_wipe.gdshader")
			if wm != null:
				wm.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
				wm.set_shader_parameter("seed", fmod(float(_idx) * 0.29, 1.0))
			lc.setup(logo_tex, minf(_canvas.x * 0.55, _canvas.y * 1.1), Kit.fx_texture("soft_dot.png"), Kit.C_JIAOMO, wm)
			return lc
	var opts: Dictionary = (STYLES.get(style, STYLES["line"]) as Dictionary).duplicate()
	opts["vertical"] = vert
	opts["align"] = 1 if (pos == "center" or pos == "bottom") else 0
	# 压在画面上（不在黑边里）的浅字，背后都垫一团柔墨，亮天空上也读得清
	if not opts.has("backing") and not (pos == "bottom" and _letterbox):
		opts["backing"] = 0.55
		opts["halo"] = maxf(float(opts.get("halo", 0.0)), 1.3)
	var bar := _bar_full()
	if vert:
		opts["max_extent"] = maxf(_canvas.y - bar * 2.0 - 110.0, 200.0)
	elif pos == "lower_left":
		opts["max_extent"] = _canvas.x * 0.46
	else:
		opts["max_extent"] = _canvas.x * 0.72
	var t := InkText.new()
	t.configure(txt, opts)
	return t


## 字幕印章（白文、字口填宣纸色，压在暗画上也读得清）。
## 与书法题名同镜的年号印（开场末镜「乙卯」）缩成与题名末「立志」名章相当的一方，挂在名章下面（见 _place_captions）
func _new_seal(txt: String, n: int, i: int) -> Control:
	var s := Seal.new()
	var cell := 58.0 if txt.length() == 1 else 44.0
	if _shot_has_logo(i):
		cell = 26.0 if txt.length() > 1 else 34.0
	s.configure(txt, {"cell": cell, "style": "baiwen", "hollow_alpha": 0.9,
		"seed": fmod(float(n) * 0.37 + float(i) * 0.11, 1.0), "tilt": -0.05 + 0.03 * sin(float(n + i))})
	s.impacted.connect(_on_seal_impact)
	return s


## 第 i 镜有没有书法题名（LOGO_TEX 那一幅）
func _shot_has_logo(i: int) -> bool:
	if i < 0 or i >= _shots.size() or typeof(_shots[i]) != TYPE_DICTIONARY:
		return false
	var caps: Variant = (_shots[i] as Dictionary).get("captions", [])
	if typeof(caps) != TYPE_ARRAY:
		return false
	for c in caps:
		if typeof(c) == TYPE_DICTIONARY and str((c as Dictionary).get("style", "")) == "title" \
				and str((c as Dictionary).get("text", "")).strip_edges() == GAME_TITLE:
			return ResourceLoader.exists(LOGO_TEX)
	return false


## 全黑时调用一次：管线预热 + 预建全片所有印章（SubViewport 下一帧渲染一次、字形光栅化），各镜到时直接取用。
## 预建的印章是 _captions 的隐藏子节点，不挪父节点（SubViewport 只渲染一次，挪了会丢内容）。
func _prewarm() -> void:
	Kit.prewarm(self)
	for i in range(_shots.size()):
		if typeof(_shots[i]) != TYPE_DICTIONARY:
			continue
		var caps: Variant = (_shots[i] as Dictionary).get("captions", [])
		if typeof(caps) != TYPE_ARRAY:
			continue
		var n := 0
		for c in caps:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = c
			var txt := str(cd.get("text", ""))
			if str(cd.get("style", "line")) == "seal" and txt.strip_edges() != "":
				var s := _new_seal(txt, n, i)
				s.visible = false
				_captions.add_child(s)
				_seal_pool["%d:%d" % [i, n]] = s
			n += 1


func _build_captions(shot: Dictionary) -> void:
	var caps: Variant = shot.get("captions", [])
	if typeof(caps) != TYPE_ARRAY:
		return
	var floor_t := _caption_floor()
	var n := 0
	for c in caps:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = c
		var style := str(cd.get("style", "line"))
		var pos := str(cd.get("pos", _default_pos(style)))
		if not pos in ["center", "bottom", "lower_left", "right_vertical", "left_vertical"]:
			pos = _default_pos(style)
		var node := _make_caption(str(cd.get("text", "")), style, pos, n)
		n += 1
		if node == null:
			continue
		node.visible = false
		if node.get_parent() == null:
			_captions.add_child(node)
		# 字幕 / 印章不早于新画面露出来（数据里 t=0.4 的方位印，在 fade 转场下会先落在黑底上）
		_cap_live.append({"node": node, "t": maxf(Kit.float_of(cd.get("t"), 0.0), floor_t),
			"hold": Kit.float_of(cd.get("hold"), -1.0), "pos": pos, "started": false, "slot": 0})
	_cap_live.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	_assign_slots()
	_place_captions()


## 本镜字幕的最早出场时刻：新画面浮现到能托住字的程度。
## fade（有上一镜）：新画面 0.45×转场起才开始浮现 → 取 0.62×（约四分之一亮度，字幕自身还有淡入，落定时画面已过半）；
## fade（首镜，从黑里亮起）0.4×；ink 0.5×；flash / cut 画面当帧就在。
func _caption_floor() -> float:
	if _front < 0:
		return 0.0
	var F: Dictionary = _layers[_front]
	var td: float = F["trans_dur"]
	match str(F["trans"]):
		"fade":
			return td * (0.62 if bool(F["has_back"]) else 0.4)
		"ink":
			return td * 0.5
	return 0.0


## 同一 pos 的字幕按出现时间分「槽」：前一条 hold 到期（含淡出）后槽位可复用；整组按最大槽数一次排好，永不挪位。
func _assign_slots() -> void:
	_groups = {}
	for e in _cap_live:
		var pos: String = e["pos"]
		if not _groups.has(pos):
			_groups[pos] = []
		var slots: Array = _groups[pos]
		var t0: float = e["t"]
		var hold: float = e["hold"]
		var free_at := t0 + hold + 0.7 if hold > 0.0 else INF
		var k := -1
		for j in range(slots.size()):
			if float(slots[j]["free_at"]) <= t0:
				k = j
				break
		if k < 0:
			slots.append({"free_at": 0.0, "ext": Vector2.ZERO})
			k = slots.size() - 1
		var sz: Vector2 = (e["node"] as Control).size
		var ext: Vector2 = slots[k]["ext"]
		slots[k]["ext"] = Vector2(maxf(ext.x, sz.x), maxf(ext.y, sz.y))
		slots[k]["free_at"] = free_at
		e["slot"] = k


func _place_captions() -> void:
	var W := _canvas.x
	var H := _canvas.y
	var bar := _bar_full()
	var gap := 16.0
	for pos in _groups.keys():
		var slots: Array = _groups[pos]
		var rects: Array = []
		var total := 0.0
		var vert: bool = pos == "right_vertical" or pos == "left_vertical"
		for s in slots:
			var ext: Vector2 = s["ext"]
			total += ext.x if vert else ext.y
		total += gap * float(maxi(slots.size() - 1, 0))
		var cursor := 0.0
		match pos:
			"center":
				cursor = H * 0.5 - total * 0.5 - 6.0
			"bottom":
				cursor = H - bar * 0.5 - total * 0.5 if (bar > 0.0 and total <= bar - 12.0) else H - 18.0 - total
			"lower_left":
				cursor = H - maxf(bar, 20.0) - 40.0 - total
			"right_vertical":
				cursor = W * 0.925
			"left_vertical":
				cursor = W * 0.075 + total
		for s in slots:
			var ext: Vector2 = s["ext"]
			if vert:
				rects.append(Rect2(cursor - ext.x, bar + 54.0, ext.x, ext.y))
				cursor -= ext.x + gap
			else:
				var x := W * 0.075 if pos == "lower_left" else (W - ext.x) * 0.5
				rects.append(Rect2(x, cursor, ext.x, ext.y))
				cursor += ext.y + gap
		for e in _cap_live:
			if e["pos"] != pos:
				continue
			var node: Control = e["node"]
			var r: Rect2 = rects[int(e["slot"])]
			var sz := node.size
			var x := r.position.x + (r.size.x - sz.x) * 0.5
			var y := r.position.y + (r.size.y - sz.y) * 0.5
			if pos == "lower_left":
				x = r.position.x
			if vert:
				y = r.position.y
			node.position = Vector2(roundf(x), roundf(y))
		if pos == "center":
			_hang_seal_under_logo()


## 开场末镜：书法题名居中，年号印不再和题名上下堆叠（原先悬在船头下方约 60px，和题名没有对位；第 2 轮美术 minor 12），
## 而是挂在题名末「立志」名章正下方 12px——两方印上下钤，书画落款的常见位置。logo 图里名章在宽 0.896–0.950、高到 0.80 处（PIL 实测）。
func _hang_seal_under_logo() -> void:
	var logo: Control = null
	var seals: Array = []
	for e in _cap_live:
		if e["pos"] != "center":
			continue
		var node: Control = e["node"]
		if node is LogoCaption:
			logo = node
		elif node is Seal:
			seals.append(node)
	if logo == null or seals.is_empty():
		return
	logo.position = Vector2(roundf((_canvas.x - logo.size.x) * 0.5), roundf(_canvas.y * 0.5 - logo.size.y * 0.5 - 6.0))
	var y := logo.position.y + logo.size.y * 0.80 + 12.0
	for s in seals:
		var sc := s as Control
		sc.position = Vector2(roundf(logo.position.x + logo.size.x * 0.923 - sc.size.x * 0.5), roundf(y))
		y += sc.size.y + 8.0


func _update_captions(dt: float) -> void:
	var keep: Array = []
	for e in _cap_live:
		var node = e["node"]
		var local := _shot_t - float(e["t"])
		if not e["started"]:
			if local >= 0.0:
				e["started"] = true
				node.visible = true
				node.advance(local)
			keep.append(e)
			continue
		node.advance(dt)
		var hold: float = e["hold"]
		if hold > 0.0 and local >= hold:
			node.fade_out(0.6)
		if node.is_gone():
			node.queue_free()
		else:
			keep.append(e)
	_cap_live = keep
	var keep_old: Array = []
	for e in _cap_old:
		var node = e["node"]
		node.advance(dt)
		if node.is_gone():
			node.queue_free()
		else:
			keep_old.append(e)
	_cap_old = keep_old


func _on_seal_impact() -> void:
	_jolt = maxf(_jolt, 0.3)


# ── 粒子 ───────────────────────────────────────────────
## 换镜时粒子层跟着转场走：
## · 旧粒子按本次转场的种类退——cut 当帧清掉；flash 0.13 秒退完（同旧字幕速退）；
##   fade 与旧画面压暗同一条曲线（1 − smoothstep(0, 0.5, rr)，画面全黑时粒子也没了）；ink 在墨染盖满前（0.55×转场）退完。
## · 新粒子等新画面露出来再进：cut 立即满、flash 0.3 秒、fade 从新画面开始浮现起、ink 从 40% 起。
func _swap_fx(shot: Dictionary, grade: String) -> void:
	var F: Dictionary = _layers[_front]
	var kind: String = F["trans"]
	var td: float = F["trans_dur"]
	var has_back: bool = F["has_back"]
	# 更早一镜遗留的旧粒子：那一镜的画面已经不在了（被点击跳过），直接清掉
	for f in _fx_old:
		(f["node"] as Node).queue_free()
	_fx_old = []
	if _fx_cur != null:
		if kind == "cut" or td <= 0.0:
			_fx_cur.queue_free()
		else:
			_fx_old.append({"node": _fx_cur, "t": 0.0, "kind": kind, "dur": td, "a0": _fx_cur.modulate.a})
		_fx_cur = null
	var kinds: Variant = shot.get("fx", [])
	if typeof(kinds) != TYPE_ARRAY or (kinds as Array).is_empty():
		return
	_fx_cur = Fx.build(kinds, _canvas, grade)
	_fx_root.add_child(_fx_cur)
	var delay := 0.0
	match kind:
		"cut":
			_fx_in_dur = 0.0
		"flash":
			_fx_in_dur = 0.3
		"fade":
			delay = td * (0.55 if has_back else 0.3)
			_fx_in_dur = td * 0.45 + 0.25 if has_back else 0.8
		_:
			delay = td * 0.4
			_fx_in_dur = FX_XFADE
	if td <= 0.0:
		_fx_in_dur = 0.0
	_fx_t = -delay
	_fx_cur.modulate.a = 1.0 if _fx_in_dur <= 0.0 else 0.0


func _fx_old_alpha(f: Dictionary) -> float:
	var t: float = f["t"]
	var td: float = f["dur"]
	match str(f["kind"]):
		"fade":
			return 1.0 - smoothstep(0.0, 0.5 * td, t)
		"ink":
			return 1.0 - smoothstep(0.0, 0.55 * td, t)
	return 1.0 - smoothstep(0.0, 0.13, t)


func _update_fx(dt: float) -> void:
	if _fx_cur != null:
		_fx_t += dt
		_fx_cur.modulate.a = 1.0 if _fx_in_dur <= 0.0 else Kit.ease_in_out(_fx_t / _fx_in_dur)
	var keep: Array = []
	for f in _fx_old:
		f["t"] = float(f["t"]) + dt
		var node: Node2D = f["node"]
		var a := float(f["a0"]) * _fx_old_alpha(f)
		node.modulate.a = a
		if a <= 0.002:
			node.queue_free()
		else:
			keep.append(f)
	_fx_old = keep
