extends Node
## 海船观感（lane combat12-E）：船下投影与贴舷白浪、受光、轻微摇曳。挂 Ship.tscn / PirateShip.tscn 的 ShipLook 节点。
## 只写画面，不碰机动、碰撞、命中：
##   · 摇曳只走 Sprite2D.offset（贴图像素，别处没人写）：横摇左右挪、纵摇前后起落。Ship.gd 的 rotation（转向侧倾）、
##     scale / position.x（损伤倾侧）、CombatFx.hull_shudder 的 scale / rotation（中弹一震）、dress_ship 的材质都叠在外面照旧。
##   · HullWater（场景里排在 Sprite2D 之前，画在船下）：hull_water 画投影与白浪；
##     HullLight（排在 Sprite2D 之后）：hull_lit 薄薄盖一层受光 / 背光。两层逐帧抄 Sprite2D 的变换、offset 与贴图，
##     CombatFx.apply_ship_sprite 换了船图，下一帧跟着换。补间（hull_shudder）在节点 _process 之后才走，
##     所以出图前（RenderingServer.frame_pre_draw）再抄一遍变换，中弹那一震两层不慢一帧。
##   · 读船节点的 velocity / max_speed / wind_strength / struck（敌船读它 target 的风），都只读。
## 日照固定在世界左上方，投影落右下；船转向时受光面跟着转。

## 世界里「朝日」方向与投影落出的距离（世界像素）
const SUN_DIR := Vector2(-0.55, -0.83)
const SHADOW_DIST := 17.0
## 横摇两个周期（秒）、纵摇周期；横摇左右挪、纵摇起落的幅度（贴图像素，×0.62 上屏约 2 px / 1.2 px）
const ROLL_T1 := 6.2
const ROLL_T2 := 3.7
const PITCH_T := 4.4
const ROLL_PX := 3.4
const PITCH_PX := 2.0
## 海况倍率：风力 80 为 1，夹在这两头之间；降了帆的船摇得轻些
const SEA_MIN := 0.55
const SEA_MAX := 1.6
const STRUCK_SEA := 0.7
## 航速多少算白浪满（相对 max_speed）
const FOAM_FULL := 0.8

var _host: Node2D = null
var _sprite: Sprite2D = null
var _layers: Array[Sprite2D] = []
var _lit: ShaderMaterial = null
var _wet: ShaderMaterial = null
var _t := 0.0
var _phase := 0.0
var _base_offset := Vector2.ZERO
var _roll := 0.0
var _pitch := 0.0
var _speed := 0.0


func _ready() -> void:
	_host = get_parent() as Node2D
	if _host == null:
		return
	_sprite = _host.get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	_base_offset = _sprite.offset
	# 每条船自己一份材质（场景里已是 local_to_scene，这里再保一道：探针手搭的节点也不串参数）
	_wet = _own_material(_host.get_node_or_null("HullWater") as Sprite2D)
	_lit = _own_material(_host.get_node_or_null("HullLight") as Sprite2D)
	# 相位按节点实例错开：同场几条船不齐步摇
	var salt := absi(int(_host.get_instance_id())) % 10007
	_phase = float(salt) * 0.6180339 * TAU
	if _wet != null:
		_wet.set_shader_parameter("phase", fmod(float(salt) * 0.37, 50.0))
	_sync(0.0)
	RenderingServer.frame_pre_draw.connect(_follow_sprite)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_follow_sprite):
		RenderingServer.frame_pre_draw.disconnect(_follow_sprite)


func _enter_tree() -> void:
	if _sprite != null and not RenderingServer.frame_pre_draw.is_connected(_follow_sprite):
		RenderingServer.frame_pre_draw.connect(_follow_sprite)


func _own_material(layer: Sprite2D) -> ShaderMaterial:
	if layer == null or not (layer.material is ShaderMaterial):
		return null
	var mat := (layer.material as ShaderMaterial).duplicate() as ShaderMaterial
	layer.material = mat
	_layers.append(layer)
	return mat


func _process(delta: float) -> void:
	_sync(delta)


func _sync(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite) or not is_instance_valid(_host):
		return
	_t += delta
	var sea := _sea_factor()
	_roll = sea * (0.6 * sin(TAU * _t / ROLL_T1 + _phase) + 0.4 * sin(TAU * _t / ROLL_T2 + _phase * 1.3))
	_pitch = sea * sin(TAU * _t / PITCH_T + _phase * 0.7)
	_speed = _speed_ratio()
	_sprite.offset = _base_offset + Vector2(_roll * ROLL_PX, _pitch * PITCH_PX)
	var fade := _sprite.modulate.a * _sprite.self_modulate.a
	_follow_sprite()
	var g := _sprite.global_rotation
	if _lit != null:
		_lit.set_shader_parameter("light_dir", SUN_DIR.normalized().rotated(-g))
		_lit.set_shader_parameter("roll", clampf(_roll, -1.0, 1.0))
		_lit.set_shader_parameter("fade", fade)
	if _wet == null or _sprite.texture == null:
		return
	# 投影偏移：世界里朝背日一侧 SHADOW_DIST，换进贴图 UV；横摇时桅帆的影子跟着左右多挪一点
	var gs := _sprite.global_scale.abs()
	var tex := _sprite.texture.get_size()
	var drop := (-SUN_DIR.normalized() * SHADOW_DIST).rotated(-g)
	drop.x += _roll * 2.5
	_wet.set_shader_parameter("shadow_uv",
		Vector2(drop.x / maxf(0.001, gs.x * tex.x), drop.y / maxf(0.001, gs.y * tex.y)))
	_wet.set_shader_parameter("speed", _speed)
	_wet.set_shader_parameter("fade", fade)


## 两层跟船图：贴图、变换、offset、翻转、显隐
func _follow_sprite() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	for layer in _layers:
		if not is_instance_valid(layer):
			continue
		if layer.texture != _sprite.texture:
			layer.texture = _sprite.texture
		layer.transform = _sprite.transform
		layer.offset = _sprite.offset
		layer.centered = _sprite.centered
		layer.flip_h = _sprite.flip_h
		layer.flip_v = _sprite.flip_v
		layer.visible = _sprite.visible


## 海况倍率：风力 80 为 1，夹在 SEA_MIN..SEA_MAX；敌船自己没风就读它 target（旗舰）的风；降了的船落帆、摇得轻
func _sea_factor() -> float:
	var ws = _host.get("wind_strength")
	if ws == null:
		var tgt = _host.get("target")
		if tgt is Object and is_instance_valid(tgt):
			ws = (tgt as Object).get("wind_strength")
	var k := clampf((float(ws) if ws != null else 80.0) / 80.0, SEA_MIN, SEA_MAX)
	if _host.get("struck") == true:
		k *= STRUCK_SEA
	return k


func _speed_ratio() -> float:
	var body := _host as CharacterBody2D
	if body == null:
		return 0.0
	var ms = _host.get("max_speed")
	var top := float(ms) if ms != null and float(ms) > 1.0 else 300.0
	return clampf(body.velocity.length() / (top * FOAM_FULL), 0.0, 1.0)


## 探针 / 验收读：当前横摇、纵摇、航速比、船图 offset，两层画面在不在
func look_state() -> Dictionary:
	return {"roll": _roll, "pitch": _pitch, "speed": _speed,
		"offset": _sprite.offset if _sprite != null else Vector2.ZERO, "lit": _lit != null, "water": _wet != null}
