## 活背景（cutscene_engine 线）：给任意 TextureRect 挂一层 ShaderMaterial，让静态油画「活」起来。
## · 极慢呼吸式推拉（默认周期 44 秒、幅度 3%），只放大不缩小，平移不超出放大留出的余量 → 永不露边
## · 暗角 + 细颗粒 + 可选调色（grade 同过场：neutral/dusk/dawn/night/fire/cold/sepia）
## · shimmer：只对偏蓝 / 偏青的海面像素做轻微流动扰动与零星闪光（标题海图用），陆地不动
##
##   LivingBackdrop.attach(background)                          # 默认参数
##   LivingBackdrop.attach(background, {"shimmer": true})       # 标题海图
##   LivingBackdrop.detach(background)                          # 还原原 material
##
## 轻量：一个 shader + 一个挂在 rect 下的小节点（每帧只比较尺寸 / 贴图 / 拉伸模式，变了才更新 uniform）。
## headless 下 attach 什么都不做、返回 null。
class_name LivingBackdrop
extends Node

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const NODE_NAME := "LivingBackdrop"
const META_PREV := "_living_backdrop_prev_material"

var _rect: TextureRect
var _mat: ShaderMaterial
var _last_size := Vector2(-1, -1)
var _last_tex: Texture2D
var _last_mode := -1
var _time := 0.0


## opts：breath(0.03) period(44.0) pan(0.6) vignette(0.32) grain(0.035) shimmer(false/0..1) grade("neutral") phase(0.0)
static func attach(rect: TextureRect, opts := {}) -> LivingBackdrop:
	if rect == null:
		return null
	detach(rect)
	if Kit.is_headless():
		return null
	var mat := Kit.material("cs_living_backdrop.gdshader")
	if mat == null:
		return null
	mat.set_shader_parameter("noise_tex", Kit.fx_texture("noise_ink.png"))
	mat.set_shader_parameter("grain_tex", Kit.fx_texture("noise_grain.png"))
	mat.set_shader_parameter("breath", clampf(Kit.float_of(opts.get("breath"), 0.03), 0.0, 0.12))
	mat.set_shader_parameter("period", clampf(Kit.float_of(opts.get("period"), 44.0), 4.0, 240.0))
	mat.set_shader_parameter("pan", clampf(Kit.float_of(opts.get("pan"), 0.6), 0.0, 1.0))
	mat.set_shader_parameter("vignette", clampf(Kit.float_of(opts.get("vignette"), 0.32), 0.0, 1.0))
	mat.set_shader_parameter("grain", clampf(Kit.float_of(opts.get("grain"), 0.035), 0.0, 0.2))
	mat.set_shader_parameter("phase", Kit.float_of(opts.get("phase"), 0.0))
	var sh: Variant = opts.get("shimmer", false)
	var shv := 0.0
	if typeof(sh) == TYPE_BOOL:
		shv = 1.0 if bool(sh) else 0.0
	else:
		shv = clampf(Kit.float_of(sh, 0.0), 0.0, 2.0)
	mat.set_shader_parameter("shimmer", shv)
	Kit.apply_grade(mat, str(opts.get("grade", "neutral")))
	rect.set_meta(META_PREV, rect.material)
	rect.material = mat
	var d := LivingBackdrop.new()
	d.name = NODE_NAME
	d._rect = rect
	d._mat = mat
	rect.add_child(d)
	d._sync()
	# 顺手把过场 / 章节卡 / 抵港横幅的 shader 管线预热掉（整个会话一次）：attach 通常在进游戏时，卡一下看不出来；
	# 否则第一条抵港横幅会在游戏画面上卡帧
	Kit.prewarm(rect)
	return d


static func detach(rect: TextureRect) -> void:
	if rect == null:
		return
	var d := rect.get_node_or_null(NODE_NAME)
	if d != null:
		rect.remove_child(d)
		d.queue_free()
	if rect.has_meta(META_PREV):
		rect.material = rect.get_meta(META_PREV)
		rect.remove_meta(META_PREV)


static func is_attached(rect: TextureRect) -> bool:
	return rect != null and rect.get_node_or_null(NODE_NAME) != null


## 运行中改参数（例如切到结局图时换调色）
static func set_grade(rect: TextureRect, grade: String) -> void:
	if not is_attached(rect):
		return
	Kit.apply_grade(rect.material as ShaderMaterial, grade)


## 运行中开关海面流动（标题海图开、港口图关），不重建材质
static func set_shimmer(rect: TextureRect, amount: float) -> void:
	if not is_attached(rect):
		return
	(rect.material as ShaderMaterial).set_shader_parameter("shimmer", clampf(amount, 0.0, 2.0))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _rect == null:
		return
	_time += delta
	_mat.set_shader_parameter("time_s", _time)
	if _rect.size != _last_size or _rect.texture != _last_tex or int(_rect.stretch_mode) != _last_mode:
		_sync()


func _sync() -> void:
	_last_size = _rect.size
	_last_tex = _rect.texture
	_last_mode = int(_rect.stretch_mode)
	var region := Vector2(0.5, 0.5)
	if _last_tex != null and _rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and _last_size.x > 0.0 and _last_size.y > 0.0:
		var ts := _last_tex.get_size()
		var ta := ts.x / maxf(ts.y, 1.0)
		var ra := _last_size.x / _last_size.y
		if ta > ra:
			region = Vector2(0.5 * ra / ta, 0.5)
		else:
			region = Vector2(0.5, 0.5 * ta / ra)
	_mat.set_shader_parameter("region", region)
	_mat.set_shader_parameter("rect_size", _last_size if _last_size.x > 0.0 else Vector2(1280, 720))
