extends Node2D

## 俯视图船体渲染 — 按 hull_id 切换轮廓，按 sail_type 绘制帆装。

const SAIL_COLOR := Color(0.92, 0.86, 0.68, 0.94)
const SAIL_SHADOW := Color(0.68, 0.62, 0.46, 0.78)
const SAIL_STITCH := Color(0.55, 0.48, 0.34, 0.55)
const MAST_COLOR := Color(0.32, 0.2, 0.11, 1.0)

var hull_id: String = "fujian_merchant"
var sail_type: String = "square"
var sail_gear: int = 0
var roll_angle: float = 0.0
var speed_ratio: float = 0.0
var wind_efficiency: float = 1.0
var hp_ratio: float = 1.0

var _model: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("fujian_merchant")


func set_hull(p_hull_id: String, p_sail_type: String = "") -> void:
	var resolved_sail := p_sail_type
	if resolved_sail.is_empty():
		var hull_data := ShipSystem.get_hull(p_hull_id)
		resolved_sail = hull_data.get("sail_type", "square")
	if hull_id == p_hull_id and sail_type == resolved_sail:
		return
	hull_id = p_hull_id
	sail_type = resolved_sail
	_model = ShipModelLibrary.get_model(hull_id)
	scale = Vector2.ONE * _model.display_scale
	queue_redraw()


func get_wake_offset() -> Vector2:
	return _model.wake_offset * _model.display_scale


func get_bow_wave_offsets() -> Array:
	return _model.bow_wave_offsets


func get_collision_radius() -> float:
	return _model.collision_radius * _model.display_scale


func set_hp_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(hp_ratio, clamped):
		return
	hp_ratio = clamped
	queue_redraw()


func update_motion(
	p_sail_gear: int,
	current_speed: float,
	max_speed: float,
	ship_rotation: float,
	wind_vector: Vector2,
	wind_strength: float,
	turn_input: float,
	delta: float,
	p_wind_efficiency: float = 1.0
) -> void:
	sail_gear = p_sail_gear
	speed_ratio = clampf(current_speed / maxf(max_speed, 1.0), 0.0, 1.2)
	wind_efficiency = clampf(p_wind_efficiency, 0.0, 1.2)

	var cross_wind := Vector2.RIGHT.rotated(ship_rotation).dot(wind_vector)
	var target_roll := cross_wind * wind_strength * 0.0018 * float(sail_gear)
	target_roll -= turn_input * speed_ratio * 0.28
	target_roll = clampf(target_roll, -0.22, 0.22)
	roll_angle = lerp_angle(roll_angle, target_roll, 5.0 * delta)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, roll_angle, Vector2.ONE)
	_draw_water_shadow()
	_draw_hull_body()
	_draw_sails()
	_draw_flag()
	_draw_bow_marker()


func _draw_water_shadow() -> void:
	var shadow := _model.hull_shadow_color
	draw_circle(Vector2(0, 8), 26.0 * _model.display_scale, shadow)
	var faint := Color(shadow.r, shadow.g, shadow.b, shadow.a * 0.65)
	draw_circle(Vector2(0, 14), 20.0 * _model.display_scale, faint)


func _draw_hull_body() -> void:
	var wear := (1.0 - hp_ratio) * 0.4
	var hull_col := _model.hull_color.darkened(wear)
	var deck_col := _model.deck_color.darkened(wear * 0.6)
	draw_colored_polygon(_model.hull_points, hull_col)
	if not _model.keel_band.is_empty():
		draw_colored_polygon(_model.keel_band, _model.keel_color.darkened(wear * 0.5))
	if not _model.armor_band.is_empty():
		draw_colored_polygon(_model.armor_band, Color(0.38, 0.36, 0.34, 0.75))
	draw_colored_polygon(_model.deck_points, deck_col)
	if hp_ratio < 0.45:
		var crack_alpha := clampf((0.45 - hp_ratio) * 1.6, 0.0, 0.55)
		draw_line(Vector2(-6, 4), Vector2(4, 14), Color(0.12, 0.08, 0.05, crack_alpha), 1.2)
		draw_line(Vector2(5, 8), Vector2(-3, 18), Color(0.12, 0.08, 0.05, crack_alpha * 0.8), 1.0)
	for line in _model.plank_lines:
		if line.size() >= 2:
			draw_line(line[0], line[1], Color(0.3, 0.2, 0.12, 0.35), 1.0)
	draw_polyline(_model.rail_points, _model.rail_color, 2.0, true)
	for port in _model.gun_ports:
		draw_circle(port, 2.2, Color(0.08, 0.08, 0.1, 0.9))
		draw_circle(port, 1.2, Color(0.22, 0.2, 0.18, 0.8))


func _draw_sails() -> void:
	if sail_gear <= 0:
		return
	if sail_type == "lateen":
		_draw_lateen_sail()
	else:
		_draw_square_sail()


func _sail_tint(base: Color) -> Color:
	if wind_efficiency >= 0.35:
		return base
	var t := clampf(1.0 - wind_efficiency / 0.35, 0.0, 1.0)
	return base.lerp(Color(0.58, 0.56, 0.5, base.a * 0.82), t)


func _draw_square_sail() -> void:
	# 横帆收在甲板宽度内，避免与船体拼成「十字」剪影
	var spread := 9.0 if sail_gear == 1 else 15.0
	var depth := 12.0 if sail_gear == 1 else 22.0
	var billow := speed_ratio * 4.0 * maxf(wind_efficiency, 0.15)
	var mast := Vector2(0, -4)
	draw_line(mast, mast + Vector2(0, depth * 0.4), MAST_COLOR, 2.5)
	var shadow_poly := PackedVector2Array([
		mast + Vector2(-spread, 1),
		mast + Vector2(spread, 1),
		mast + Vector2(spread * 0.7 + billow, depth),
		mast + Vector2(-spread * 0.7 - billow * 0.5, depth),
	])
	draw_colored_polygon(shadow_poly, _sail_tint(SAIL_SHADOW))
	var sail_poly := PackedVector2Array([
		mast + Vector2(-spread * 0.9, 2),
		mast + Vector2(spread * 0.9, 2),
		mast + Vector2(spread * 0.65 + billow * 0.8, depth * 0.92),
		mast + Vector2(-spread * 0.65 - billow * 0.4, depth * 0.92),
	])
	draw_colored_polygon(sail_poly, _sail_tint(SAIL_COLOR))
	draw_line(mast + Vector2(-spread * 0.9, 2), mast + Vector2(-spread * 0.65, depth * 0.92), SAIL_STITCH, 1.0)
	draw_line(mast + Vector2(spread * 0.9, 2), mast + Vector2(spread * 0.65, depth * 0.92), SAIL_STITCH, 1.0)


func _draw_lateen_sail() -> void:
	var length := 18.0 if sail_gear == 1 else 32.0
	var billow := speed_ratio * 6.0 * maxf(wind_efficiency, 0.15)
	var mast := Vector2(1, -6)
	draw_line(mast, mast + Vector2(0, length * 0.55), MAST_COLOR, 2.0)
	var yard_end := mast + Vector2(length * 0.85 + billow, length * 0.35)
	draw_line(mast, yard_end, MAST_COLOR, 1.5)
	var shadow_tri := PackedVector2Array([
		mast,
		yard_end + Vector2(2, 4),
		mast + Vector2(-length * 0.55, length * 0.75),
	])
	draw_colored_polygon(shadow_tri, _sail_tint(SAIL_SHADOW))
	var sail_tri := PackedVector2Array([
		mast + Vector2(0, 1),
		yard_end + Vector2(1, 2),
		mast + Vector2(-length * 0.5 - billow * 0.3, length * 0.7),
	])
	draw_colored_polygon(sail_tri, _sail_tint(SAIL_COLOR))
	draw_line(mast, yard_end, SAIL_STITCH, 1.0)


func _draw_flag() -> void:
	var base := _model.flag_pole
	draw_line(base, base + Vector2(0, -12), MAST_COLOR, 1.5)
	draw_colored_polygon(
		[
			base + Vector2(0, -12),
			base + Vector2(9, -9),
			base + Vector2(0, -6),
		],
		_model.flag_color
	)


func _draw_bow_marker() -> void:
	if speed_ratio < 0.12:
		return
	var alpha := clampf(speed_ratio, 0.2, 0.95)
	var pos := _model.bow_marker
	draw_circle(pos, 2.8, Color(1.0, 0.95, 0.72, alpha * 0.35))
	draw_circle(pos, 2.0, Color(1.0, 0.96, 0.78, alpha))