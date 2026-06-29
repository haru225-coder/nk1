class_name ShipModelLibrary
extends RefCounted

## 俯视图船型轮廓与配色 — 由 hull_id 查表，供 ShipVisual 绘制。

class ShipModel:
	var hull_id: String = ""
	var display_scale: float = 1.0
	var hull_points: PackedVector2Array = PackedVector2Array()
	var deck_points: PackedVector2Array = PackedVector2Array()
	var rail_points: PackedVector2Array = PackedVector2Array()
	var keel_band: PackedVector2Array = PackedVector2Array()
	var plank_lines: Array = []
	var hull_color: Color = Color.WHITE
	var hull_shadow_color: Color = Color.WHITE
	var deck_color: Color = Color.WHITE
	var rail_color: Color = Color.WHITE
	var keel_color: Color = Color.WHITE
	var sail_type: String = "square"
	var flag_color: Color = Color.WHITE
	var flag_pole: Vector2 = Vector2.ZERO
	var bow_marker: Vector2 = Vector2.ZERO
	var wake_offset: Vector2 = Vector2(0, 42)
	var bow_wave_offsets: Array = [Vector2(-18, -38), Vector2(18, -38)]
	var gun_ports: PackedVector2Array = PackedVector2Array()
	var armor_band: PackedVector2Array = PackedVector2Array()
	var collision_radius: float = 28.0


static func get_model(hull_id: String) -> ShipModel:
	match hull_id:
		"guangzhou_trader":
			return _guangzhou_trader()
		"warship_patrol":
			return _warship_patrol()
		_:
			return _fujian_merchant()


static func get_minimap_hull(hull_id: String, scale: float = 0.11) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for p in get_model(hull_id).hull_points:
		pts.append(p * scale)
	return pts


## 出港出生点：港口多边形半径 + 船体碰撞半径 + 安全间距
static func get_port_spawn_offset(hull_id: String) -> Vector2:
	var m := get_model(hull_id)
	var clearance := 72.0 + m.collision_radius * m.display_scale + 18.0
	return Vector2(0, clearance)


static func _fujian_merchant() -> ShipModel:
	var m := ShipModel.new()
	m.hull_id = "fujian_merchant"
	m.display_scale = 1.0
	m.sail_type = "square"
	m.hull_points = PackedVector2Array([
		Vector2(0, -36), Vector2(-22, 4), Vector2(-24, 30),
		Vector2(0, 34), Vector2(24, 30), Vector2(22, 4),
	])
	m.deck_points = PackedVector2Array([
		Vector2(-12, -10), Vector2(12, -10), Vector2(10, 20), Vector2(-10, 20),
	])
	m.rail_points = PackedVector2Array([
		Vector2(-22, -2), Vector2(-24, 30), Vector2(24, 30), Vector2(22, -2), Vector2(-22, -2),
	])
	m.keel_band = PackedVector2Array([
		Vector2(-8, 24), Vector2(8, 24), Vector2(6, 32), Vector2(-6, 32),
	])
	m.plank_lines = [
		[Vector2(-9, -2), Vector2(9, -2)],
		[Vector2(-9, 6), Vector2(9, 6)],
		[Vector2(-8, 14), Vector2(8, 14)],
	]
	m.hull_color = Color(0.42, 0.26, 0.13, 1.0)
	m.hull_shadow_color = Color(0.22, 0.14, 0.08, 0.45)
	m.deck_color = Color(0.56, 0.38, 0.22, 1.0)
	m.rail_color = Color(0.74, 0.56, 0.32, 1.0)
	m.keel_color = Color(0.28, 0.18, 0.1, 0.85)
	m.flag_color = Color(0.78, 0.18, 0.12, 1.0)
	m.flag_pole = Vector2(0, -20)
	m.bow_marker = Vector2(0, -38)
	m.collision_radius = 28.0
	return m


static func _guangzhou_trader() -> ShipModel:
	var m := ShipModel.new()
	m.hull_id = "guangzhou_trader"
	m.display_scale = 1.06
	m.sail_type = "lateen"
	m.hull_points = PackedVector2Array([
		Vector2(0, -40), Vector2(-14, -8), Vector2(-16, 18),
		Vector2(-10, 34), Vector2(10, 34), Vector2(16, 18), Vector2(14, -8),
	])
	m.deck_points = PackedVector2Array([
		Vector2(-7, -12), Vector2(7, -12), Vector2(6, 22), Vector2(-6, 22),
	])
	m.rail_points = PackedVector2Array([
		Vector2(-14, -4), Vector2(-16, 18), Vector2(-10, 34),
		Vector2(10, 34), Vector2(16, 18), Vector2(14, -4), Vector2(-14, -4),
	])
	m.keel_band = PackedVector2Array([
		Vector2(-5, 26), Vector2(5, 26), Vector2(4, 34), Vector2(-4, 34),
	])
	m.plank_lines = [
		[Vector2(-5, -4), Vector2(5, -4)],
		[Vector2(-5, 4), Vector2(5, 4)],
		[Vector2(-5, 12), Vector2(5, 12)],
		[Vector2(-4, 20), Vector2(4, 20)],
	]
	m.hull_color = Color(0.34, 0.28, 0.16, 1.0)
	m.hull_shadow_color = Color(0.16, 0.14, 0.08, 0.5)
	m.deck_color = Color(0.48, 0.4, 0.24, 1.0)
	m.rail_color = Color(0.62, 0.52, 0.3, 1.0)
	m.keel_color = Color(0.2, 0.16, 0.1, 0.9)
	m.flag_color = Color(0.2, 0.55, 0.35, 1.0)
	m.flag_pole = Vector2(2, -22)
	m.bow_marker = Vector2(0, -42)
	m.wake_offset = Vector2(0, 44)
	m.bow_wave_offsets = [Vector2(-14, -42), Vector2(14, -42)]
	m.collision_radius = 26.0
	return m


static func _warship_patrol() -> ShipModel:
	var m := ShipModel.new()
	m.hull_id = "warship_patrol"
	m.display_scale = 1.14
	m.sail_type = "square"
	m.hull_points = PackedVector2Array([
		Vector2(0, -34), Vector2(-26, 2), Vector2(-28, 28),
		Vector2(0, 36), Vector2(28, 28), Vector2(26, 2),
	])
	m.deck_points = PackedVector2Array([
		Vector2(-14, -8), Vector2(14, -8), Vector2(12, 18), Vector2(-12, 18),
	])
	m.rail_points = PackedVector2Array([
		Vector2(-26, -2), Vector2(-28, 28), Vector2(28, 28), Vector2(26, -2), Vector2(-26, -2),
	])
	m.keel_band = PackedVector2Array([
		Vector2(-10, 24), Vector2(10, 24), Vector2(8, 34), Vector2(-8, 34),
	])
	m.armor_band = PackedVector2Array([
		Vector2(-24, 6), Vector2(24, 6), Vector2(22, 14), Vector2(-22, 14),
	])
	m.plank_lines = [
		[Vector2(-11, 0), Vector2(11, 0)],
		[Vector2(-11, 8), Vector2(11, 8)],
	]
	m.hull_color = Color(0.3, 0.28, 0.26, 1.0)
	m.hull_shadow_color = Color(0.12, 0.12, 0.14, 0.55)
	m.deck_color = Color(0.42, 0.38, 0.34, 1.0)
	m.rail_color = Color(0.55, 0.52, 0.48, 1.0)
	m.keel_color = Color(0.18, 0.18, 0.2, 0.95)
	m.flag_color = Color(0.15, 0.35, 0.72, 1.0)
	m.flag_pole = Vector2(-4, -18)
	m.bow_marker = Vector2(0, -36)
	m.wake_offset = Vector2(0, 46)
	m.bow_wave_offsets = [Vector2(-22, -36), Vector2(22, -36)]
	m.gun_ports = PackedVector2Array([
		Vector2(-24, 10), Vector2(-24, 18),
		Vector2(24, 10), Vector2(24, 18),
		Vector2(-20, 22), Vector2(20, 22),
	])
	m.collision_radius = 32.0
	return m