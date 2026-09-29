extends Node
## combat12：海船微摇 / 阴影——不改机动与碰撞，只动 Sprite2D 视觉。
## 挂在 Ship / PirateShip 下即可；找不到 Sprite2D 则静默。
## 阴影用 call_deferred：开战刷船时父节点还在 _ready/add_child，同步挂子会报 busy。

const BOB_AMP := 1.6
const BOB_HZ := 0.55
const ROLL_DEG := 1.8
const ROLL_HZ := 0.38

var _sprite: Sprite2D
var _shadow: Sprite2D
var _base_pos := Vector2.ZERO
var _base_rot := 0.0
var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = randf() * TAU
	call_deferred("_boot")


func _boot() -> void:
	var host := get_parent()
	if host == null or not is_instance_valid(host):
		return
	_sprite = _find_sprite(host)
	if _sprite == null:
		return
	_base_pos = _sprite.position
	_base_rot = _sprite.rotation
	_ensure_shadow()


func _process(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_t += delta
	var bob := sin((_t + _phase) * TAU * BOB_HZ) * BOB_AMP
	var roll := sin((_t + _phase * 0.7) * TAU * ROLL_HZ) * deg_to_rad(ROLL_DEG)
	_sprite.position = _base_pos + Vector2(0.0, bob)
	_sprite.rotation = _base_rot + roll
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.position = _base_pos + Vector2(3.0, 10.0 + bob * 0.35)
		_shadow.rotation = _base_rot + roll * 0.4


func _find_sprite(host: Node) -> Sprite2D:
	if host == null:
		return null
	var s := host.get_node_or_null("Sprite2D") as Sprite2D
	if s != null:
		return s
	for c in host.get_children():
		if c is Sprite2D:
			return c as Sprite2D
	return null


func _ensure_shadow() -> void:
	var host := get_parent()
	if host == null or _sprite == null or not is_instance_valid(host):
		return
	_shadow = host.get_node_or_null("HullShadow") as Sprite2D
	if _shadow != null:
		return
	_shadow = Sprite2D.new()
	_shadow.name = "HullShadow"
	_shadow.texture = _sprite.texture
	_shadow.scale = _sprite.scale * Vector2(1.02, 0.55)
	_shadow.modulate = Color(0.05, 0.08, 0.12, 0.28)
	_shadow.z_index = mini(_sprite.z_index - 1, -1)
	_shadow.centered = _sprite.centered
	_shadow.position = _base_pos + Vector2(3.0, 10.0)
	host.add_child(_shadow)
	var idx := _sprite.get_index()
	if idx >= 0 and _shadow.get_parent() == host:
		host.move_child(_shadow, maxi(0, idx))
