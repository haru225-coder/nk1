## 抵港横幅（cutscene_engine 线）：一条旧绢自左滑入，港名马善政大字 + 副题 + 小朱印「泊」，约 2.6 秒后淡出。
## 不拦输入（全部 mouse_filter = IGNORE，也不处理 _input），不暂停游戏；同时只保留一条（新的顶掉旧的）。
##
##   PortBanner.show_banner(self, port_id)
##
## 数据：cutscenes.json port_banners[port_id] 的 name / sub；缺了就用 data/ports.json 的港名、无副题。
## headless 下不建节点，返回 null。
class_name PortBanner
extends CanvasLayer

signal finished

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const InkText := preload("res://scripts/cutscene/cs_ink_text.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")

const LAYER_INDEX := 40
const GROUP := "nk1_port_banner"
const SLIDE := 0.6
const T_NAME := 0.22
const T_SUB := 0.62
const T_SEAL := 1.0
const T_OUT := 2.05
const T_END := 2.65
const SEAL_TEXT := "泊"

var port_id := ""
var _data_path := "res://data/cutscenes.json"
var _t := 0.0
var _done := false
var _canvas := Vector2(1280, 720)
var _root: Control
var _band: Control
var _silk: ColorRect
var _silk_mat: ShaderMaterial
var _shadow: TextureRect
var _items: Array = []
var _band_w := 600.0
var _band_h := 100.0


static func show_banner(parent: Node, port: String, data_path := "res://data/cutscenes.json") -> PortBanner:
	if parent == null or Kit.is_headless():
		return null
	if parent.is_inside_tree():
		for n in parent.get_tree().get_nodes_in_group(GROUP):
			n.queue_free()
	var b := PortBanner.new()
	b.port_id = port
	b._data_path = data_path
	b.add_to_group(GROUP)
	parent.add_child(b)
	return b


func _ready() -> void:
	layer = LAYER_INDEX
	# LivingBackdrop.attach 通常已在进游戏时预热过；没接活背景时这里兜底（整个会话一次）
	Kit.prewarm(self)
	_canvas = Kit.canvas_size(self)
	var nm := ""
	var sub := ""
	var d := Kit.load_json(_data_path)
	var pb: Variant = d.get("port_banners", {})
	if typeof(pb) == TYPE_DICTIONARY and typeof((pb as Dictionary).get(port_id)) == TYPE_DICTIONARY:
		var e: Dictionary = (pb as Dictionary)[port_id]
		nm = str(e.get("name", ""))
		sub = str(e.get("sub", ""))
	if nm == "":
		var pd := Kit.load_json(Kit.PORTS_DATA)
		var ports: Variant = pd.get("ports", [])
		if typeof(ports) == TYPE_ARRAY:
			for p in ports:
				if typeof(p) == TYPE_DICTIONARY and str((p as Dictionary).get("id", "")) == port_id:
					nm = str((p as Dictionary).get("name", ""))
	if nm == "":
		nm = port_id
	_build(nm, sub)


func _build(nm: String, sub: String) -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_band)

	var fs := 56 if nm.length() <= 3 else (48 if nm.length() <= 4 else 40)
	var name_t := InkText.new()
	name_t.configure(nm, {"font_kind": "title", "size": fs, "spacing": 0.1, "color": Kit.C_JIAOMO,
		"effect": 1, "interval": 0.12, "fade": 0.55})
	var sub_t: Control = null
	if sub != "":
		var st := InkText.new()
		st.configure(sub, {"font_kind": "body", "size": 18, "spacing": 0.16, "color": Kit.C_MO,
			"effect": 0, "interval": 0.035, "fade": 0.35})
		sub_t = st
	var seal := Seal.new()
	seal.configure(SEAL_TEXT, {"cell": 34.0, "style": "baiwen", "hollow_alpha": 0.0, "seed": fmod(float(port_id.hash() & 1023) / 1023.0, 1.0), "tilt": -0.06})

	_band_h = maxf(96.0, name_t.size.y + 34.0)
	var x := 58.0
	var cy := _band_h * 0.5
	name_t.position = Vector2(x, roundf(cy - name_t.size.y * 0.5))
	x += name_t.size.x + 24.0
	if sub_t != null:
		sub_t.position = Vector2(roundf(x), roundf(cy - sub_t.size.y * 0.5 + fs * 0.12))
		x += sub_t.size.x + 20.0
	seal.position = Vector2(roundf(x), roundf(cy - seal.size.y * 0.5))
	x += seal.size.x
	_band_w = x + 150.0

	_shadow = TextureRect.new()
	_shadow.texture = Kit.fx_texture("soft_dot.png")
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.position = Vector2(-_band_w * 0.25, -_band_h * 0.35)
	_shadow.size = Vector2(_band_w * 1.3, _band_h * 1.9)
	_shadow.modulate = Color(Kit.C_JIAOMO, 0.55)
	_band.add_child(_shadow)

	_silk = ColorRect.new()
	_silk.color = Kit.C_JUAN
	_silk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silk.size = Vector2(_band_w, _band_h)
	_silk_mat = Kit.material("cs_silk_band.gdshader")
	if _silk_mat != null:
		_silk_mat.set_shader_parameter("weave_tex", Kit.fx_texture("silk_weave.png"))
		_silk_mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
		_silk_mat.set_shader_parameter("band_size", Vector2(_band_w, _band_h))
		_silk_mat.set_shader_parameter("fray_start", 1.0 - 150.0 / _band_w)
		_silk_mat.set_shader_parameter("seed", fmod(float(port_id.length()) * 0.173, 1.0))
		_silk.material = _silk_mat
	_band.add_child(_silk)

	for pair in [[name_t, T_NAME], [sub_t, T_SUB], [seal, T_SEAL]]:
		var node: Control = pair[0]
		if node == null:
			continue
		node.visible = false
		_band.add_child(node)
		_items.append({"node": node, "start": float(pair[1]), "started": false})
	_band.size = Vector2(_band_w, _band_h)
	_apply()


func _process(delta: float) -> void:
	if _done or _root == null:
		return
	_t += delta
	var cv := Kit.canvas_size(self)
	if cv != _canvas:
		_canvas = cv
	_apply()
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
			node.advance(delta)
	if _t >= T_END:
		_done = true
		finished.emit()
		queue_free()


func _apply() -> void:
	var slide := Kit.ease_out_cubic(_t / SLIDE)
	var out := Kit.ease_in_out((_t - T_OUT) / (T_END - T_OUT))
	var y := roundf(_canvas.y * 0.17)
	_band.position = Vector2(roundf(-_band_w * (1.0 - slide) - 36.0 * out), y)
	_band.modulate.a = clampf(slide * 1.6, 0.0, 1.0) * (1.0 - out)
