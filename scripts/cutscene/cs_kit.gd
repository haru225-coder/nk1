## 过场引擎共用工具（cutscene_engine 线）：色板、字体、贴图、JSON、取景、调色预设。
## 不依赖任何 autoload；所有资源缺失都有兜底，绝不让过场卡死游戏。
extends RefCounted

const DEFAULT_DATA := "res://data/cutscenes.json"
const FIXTURE_DATA := "res://tools/art/cutscenes_fixture.json"
const CHAPTERS_DATA := "res://data/chapters.json"
const PORTS_DATA := "res://data/ports.json"
const FONT_TITLE := "res://assets/fonts/MaShanZheng-Regular.ttf"
const FONT_BODY := "res://assets/fonts/LXGWWenKai-Medium.ttf"
const FALLBACK_BG := "res://assets/bg_sea_route.jpg"
const FX_DIR := "res://assets/fx/"
const SHADER_DIR := "res://assets/shaders/"

# 色板（美术规范）
const C_JIAOMO := Color(0.051, 0.043, 0.035)      # 焦墨 #0d0b09
const C_MO := Color(0.102, 0.086, 0.071)          # 墨 #1a1612
const C_XUAN := Color(0.914, 0.863, 0.753)        # 宣纸 #e9dcc0
const C_JUAN := Color(0.804, 0.722, 0.561)        # 旧绢 #cdb88f
const C_GOLD := Color(0.788, 0.631, 0.29)         # 泥金 #c9a14a
const C_CINNABAR := Color(0.69, 0.188, 0.165)     # 朱砂 #b0302a
const C_INDIGO := Color(0.122, 0.227, 0.302)      # 靛青 #1f3a4d
const C_STONE := Color(0.231, 0.431, 0.478)       # 石青 #3b6e7a
const C_OCHRE := Color(0.541, 0.353, 0.169)       # 赭石 #8a5a2b
const C_MOON := Color(0.839, 0.894, 0.91)         # 月白 #d6e4e8

## 调色预设：lift / gain / gamma / sat / contrast / sepia（cs_shot 与 cs_living_backdrop 共用）
const GRADES := {
	"neutral": {"lift": Vector3(0.0, 0.0, 0.0), "gain": Vector3(1.0, 1.0, 1.0), "gamma": 1.0, "sat": 1.0, "contrast": 1.02, "sepia": 0.0},
	"dusk": {"lift": Vector3(0.025, 0.012, 0.03), "gain": Vector3(1.07, 0.96, 0.84), "gamma": 0.97, "sat": 0.94, "contrast": 1.06, "sepia": 0.08},
	"dawn": {"lift": Vector3(0.03, 0.028, 0.045), "gain": Vector3(1.03, 1.0, 1.02), "gamma": 1.06, "sat": 0.86, "contrast": 0.97, "sepia": 0.0},
	"night": {"lift": Vector3(0.0, 0.012, 0.035), "gain": Vector3(0.66, 0.76, 0.93), "gamma": 0.9, "sat": 0.58, "contrast": 1.1, "sepia": 0.0},
	"fire": {"lift": Vector3(0.02, 0.0, 0.0), "gain": Vector3(1.14, 0.9, 0.7), "gamma": 0.95, "sat": 1.1, "contrast": 1.13, "sepia": 0.0},
	"cold": {"lift": Vector3(0.012, 0.022, 0.035), "gain": Vector3(0.9, 0.97, 1.05), "gamma": 1.0, "sat": 0.66, "contrast": 1.04, "sepia": 0.0},
	"sepia": {"lift": Vector3(0.03, 0.022, 0.012), "gain": Vector3(1.0, 0.96, 0.88), "gamma": 1.0, "sat": 0.75, "contrast": 1.05, "sepia": 0.72},
}

static var _json_cache: Dictionary = {}
static var _font_cache: Dictionary = {}
static var _small_cache: Dictionary = {}
static var _threaded: Dictionary = {}
static var _warmed := false

## 管线预热用到的全部 shader（首次绘制时编译，Metal/Vulkan 下单个 30–100 ms）
const WARM_SHADERS := ["cs_shot.gdshader", "cs_seal.gdshader", "cs_paper.gdshader", "cs_ink_bloom.gdshader",
	"cs_silk_band.gdshader", "cs_overlay.gdshader", "cs_wipe.gdshader", "cs_living_backdrop.gdshader"]


## 管线预热：把过场 / 章节卡 / 横幅用到的全部 shader、加色混合、粒子（multimesh）各画一帧——
## 屏幕左上角 2×2 像素、1.2% 不透明度，肉眼不可见；0.2 秒后自删。让首次编译落在调用方挑的时机
## （画面全黑时 / 进游戏时），而不是第一次盖印、第一次出章节卡时在画面上卡一下。
## 整个会话只做一次（shader 资源在 _small_cache 里常驻，编译结果不丢）；headless 下什么都不做。
static func prewarm(host: Node) -> void:
	if _warmed or host == null or not host.is_inside_tree() or is_headless():
		return
	_warmed = true
	var layer := CanvasLayer.new()
	layer.name = "CsPrewarm"
	layer.layer = 127
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate.a = 0.012
	layer.add_child(root)
	for sh: String in WARM_SHADERS:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = Vector2(2, 2)
		r.material = material(sh)
		root.add_child(r)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var ar := ColorRect.new()
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ar.size = Vector2(2, 2)
	ar.material = add_mat
	root.add_child(ar)
	for additive: bool in [false, true]:
		var p := CPUParticles2D.new()
		p.texture = fx_texture("soft_dot.png")
		p.amount = 1
		p.lifetime = 1.0
		p.preprocess = 0.5
		p.scale_amount_min = 0.02
		p.scale_amount_max = 0.02
		p.gravity = Vector2.ZERO
		p.position = Vector2(1, 1)
		if additive:
			p.material = add_mat
		root.add_child(p)
	host.add_child(layer)
	host.get_tree().create_timer(0.2, true).timeout.connect(layer.queue_free)


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func load_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("过场数据解析失败：%s" % path)
		return {}
	_json_cache[path] = parsed
	return parsed


## 预览 / 调试用：换了数据文件后让缓存失效
static func forget_json(path: String) -> void:
	_json_cache.erase(path)


static func load_font(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			f = ff
	if f == null:
		push_warning("过场字体缺失：%s，用引擎默认字体" % path)
		f = ThemeDB.fallback_font
	_font_cache[path] = f
	return f


## 马善政（书法标题）。它缺的字（如「・」「祐」）走文楷兜底：包一层 FontVariation，不改共享资源。
static func title_font() -> Font:
	if _font_cache.has("::title"):
		return _font_cache["::title"]
	var fv := FontVariation.new()
	fv.base_font = load_font(FONT_TITLE)
	fv.fallbacks = [load_font(FONT_BODY)]
	_font_cache["::title"] = fv
	return fv


static func body_font() -> Font:
	return load_font(FONT_BODY)


## 读贴图：资源系统优先；未导入 / 伪装扩展名时按文件头解码。缺失返回 null。
static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path, "Texture2D"):
		var t := load(path) as Texture2D
		if t != null:
			return t
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


## 背景图：先查后台预读，再同步读；都失败回落通用航海图，再失败返回 null（调用方画黑底）。
static func background(path: String) -> Texture2D:
	var t: Texture2D = null
	if _threaded.has(path):
		_threaded.erase(path)
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_FAILED:
			t = ResourceLoader.load_threaded_get(path) as Texture2D
	if t == null:
		t = load_texture(path)
	if t == null and path != FALLBACK_BG:
		push_warning("过场底图缺失：%s，回落 %s" % [path, FALLBACK_BG])
		t = load_texture(FALLBACK_BG)
	return t


## 后台预读（只对已导入的资源有效；其余到时同步读）
static func preload_background(path: String) -> void:
	if path == "" or _threaded.has(path) or not ResourceLoader.exists(path, "Texture2D"):
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
		_threaded[path] = true


## 过场被跳过时，把没用上的后台预读取走释放（只取已读完的，不阻塞）
static func drop_preloads(paths: Array) -> void:
	for p in paths:
		var path := str(p)
		if _threaded.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_threaded.erase(path)
			ResourceLoader.load_threaded_get(path)


static func fx_texture(file_name: String) -> Texture2D:
	var key := FX_DIR + file_name
	if _small_cache.has(key):
		return _small_cache[key]
	var t := load_texture(key)
	_small_cache[key] = t
	return t


static func shader(file_name: String) -> Shader:
	var key := SHADER_DIR + file_name
	if _small_cache.has(key):
		return _small_cache[key]
	var s: Shader = null
	if ResourceLoader.exists(key):
		s = load(key) as Shader
	if s == null:
		push_warning("过场 shader 缺失：%s" % key)
	_small_cache[key] = s
	return s


## 新建 ShaderMaterial；shader 缺失时返回 null（节点退化为纯色，不报错）
static func material(file_name: String) -> ShaderMaterial:
	var s := shader(file_name)
	if s == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = s
	return m


## cover 方式取景：返回纹理 UV 里的取景窗，保证整窗落在 [0,1] 内（永不露边）。
## center 是 0..1 画面中心，zoom ≥ 1（1 = 恰好铺满画布）。
static func cover_view(tex_size: Vector2, canvas: Vector2, center: Vector2, zoom: float) -> Rect2:
	var ta := tex_size.x / maxf(tex_size.y, 1.0)
	var ca := canvas.x / maxf(canvas.y, 1.0)
	var w := 1.0
	var h := 1.0
	if ta > ca:
		w = ca / ta
	else:
		h = ta / ca
	var z := maxf(zoom, 1.0)
	w /= z
	h /= z
	var cx := clampf(center.x, w * 0.5, 1.0 - w * 0.5)
	var cy := clampf(center.y, h * 0.5, 1.0 - h * 0.5)
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


static func apply_grade(mat: ShaderMaterial, grade_name: String) -> void:
	if mat == null:
		return
	var g: Dictionary = GRADES.get(grade_name, GRADES["neutral"])
	mat.set_shader_parameter("g_lift", g["lift"])
	mat.set_shader_parameter("g_gain", g["gain"])
	mat.set_shader_parameter("g_gamma", g["gamma"])
	mat.set_shader_parameter("g_sat", g["sat"])
	mat.set_shader_parameter("g_contrast", g["contrast"])
	mat.set_shader_parameter("g_sepia", g["sepia"])


static func canvas_size(node: Node) -> Vector2:
	if node == null or not node.is_inside_tree():
		return Vector2(1280, 720)
	return node.get_viewport().get_visible_rect().size


## 缓动
static func ease_out_cubic(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func ease_in_out_sine(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * t)


## 竖排 / 横排数字转中文（章回用）
static func cn_number(n: int) -> String:
	var d := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
	if n >= 0 and n <= 10:
		return d[n]
	if n < 20:
		return "十" + d[n - 10]
	if n < 100:
		var tens: int = floori(n / 10.0)
		var ones: int = n % 10
		return d[tens] + "十" + (d[ones] if ones > 0 else "")
	return str(n)


static func float_of(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback


## [cx, cy, zoom] → Vector3；缺省 (0.5, 0.5, 1.0)
static func cam_of(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		if a.size() >= 3:
			return Vector3(float_of(a[0], 0.5), float_of(a[1], 0.5), maxf(float_of(a[2], 1.0), 1.0))
		if a.size() == 2:
			return Vector3(float_of(a[0], 0.5), float_of(a[1], 0.5), 1.0)
	return Vector3(0.5, 0.5, 1.0)
