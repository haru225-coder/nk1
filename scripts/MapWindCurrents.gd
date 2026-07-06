extends Node2D
class_name MapWindCurrents

## 渲染大地图范围内的季风流向粒子。
## 使用一个覆盖全图的 CPUParticles2D，并根据玩家船的实时风向调整流向。

var _particles: CPUParticles2D
var wind_source: Node2D

func _ready() -> void:
	z_index = 5 # 位于底层地图之上，但在 UI 之下
	_setup_particles()

	# 初始化方向
	_update_wind_direction()

func _setup_particles() -> void:
	_particles = CPUParticles2D.new()
	add_child(_particles)

	_particles.amount = 3000
	_particles.lifetime = 15.0
	_particles.preprocess = 10.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# 覆盖整个海图 (以 0,0 为中心，范围大概是 -13000 到 13000)
	_particles.emission_rect_extents = Vector2(13000, 16000)
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 100.0
	_particles.initial_velocity_max = 200.0
	_particles.scale_amount_min = 1.0
	_particles.scale_amount_max = 3.0
	_particles.color = Color(0.1, 0.1, 0.1, 0.15) # 极淡的墨迹颜色
	_particles.spread = 5.0 # 流动非常平稳

	# 为流体粒子增加一点淡入淡出效果
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 0.0))
	gradient.add_point(0.2, Color(1, 1, 1, 1.0))
	gradient.add_point(0.8, Color(1, 1, 1, 1.0))
	gradient.add_point(1.0, Color(1, 1, 1, 0.0))
	_particles.color_ramp = gradient

func _process(_delta: float) -> void:
	# 在后台定时或者每帧检查（或者靠信号，这里用每帧安全且消耗极小）
	_update_wind_direction()

func _update_wind_direction() -> void:
	var wind_dir := Vector2(0, 1)
	if is_instance_valid(wind_source):
		var source_wind: Variant = wind_source.get("wind_vector")
		if source_wind is Vector2:
			wind_dir = source_wind
	if _particles.direction != wind_dir:
		_particles.direction = wind_dir
