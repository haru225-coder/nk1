extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run_ship_system() -> void:
	_test_ship_system()

func run_map_layout() -> void:
	_test_map_layout()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _assert_gt(actual: float, threshold: float, msg: String) -> void:
	_runner._assert_gt(actual, threshold, msg)

func _assert_lt(actual: float, threshold: float, msg: String) -> void:
	_runner._assert_lt(actual, threshold, msg)

func _assert_not_null(value, msg: String) -> void:
	_runner._assert_not_null(value, msg)

func _test_ship_system() -> void:
	print("[ShipSystem]")

	var ship: ShipState = ShipSystem.create_ship_state("fujian_merchant")
	_assert_eq(ship.hull_id, "fujian_merchant", "create_ship_state hull_id")
	_assert_eq(ship.name, "福船", "create_ship_state name")
	_assert_eq(ship.sail_type, "square", "福船 sail_type")

	var perf: Dictionary = ShipSystem.compute_performance(ship)
	_assert_eq(perf.max_speed, 280.0, "福船 base max_speed")
	_assert_eq(perf.max_gear, 2, "福船 max_gear")

	ship.sail_level = 2
	perf = ShipSystem.compute_performance(ship)
	_assert_eq(perf.max_speed, 330.0, "sail_level 2 adds speed")

	var lateen: ShipState = ShipSystem.create_ship_state("guangzhou_trader")
	_assert_eq(lateen.sail_type, "lateen", "广船 lateen sail")
	_assert_gt(float(ShipSystem.compute_performance(lateen).base_turn_speed), 2.0, "广船 turn speed")

	_assert_true(ShipSystem.should_storm_damage(160.0, 2), "storm damage when full sail")
	_assert_true(not ShipSystem.should_storm_damage(120.0, 2), "no storm damage calm wind")

	var flagship: ShipState = ShipSystem.create_ship_state("fujian_merchant")
	flagship.hp = 50.0
	flagship.crew = 25
	_assert_true(ShipSystem.apply_hull_to_flagship(flagship, "guangzhou_trader"), "apply_hull_to_flagship")
	_assert_eq(flagship.hull_id, "guangzhou_trader", "hull changed to guangzhou_trader")
	_assert_eq(flagship.name, "广船", "hull name updated")
	_assert_eq(flagship.sail_type, "lateen", "广船 sail_type applied")
	_assert_eq(flagship.max_hp, 110.0, "广船 max_hp")
	_assert_eq(flagship.hp, 55.0, "hp ratio preserved")
	_assert_eq(flagship.crew, 28, "crew ratio preserved")

	var options: Array = ShipSystem.list_shipyard_hulls("fujian_merchant", 0)
	_assert_eq(options.size(), 1, "one shipyard hull from 福船")
	_assert_eq(str(options[0].get("id", "")), "guangzhou_trader", "shipyard offers 广船")

	var fujian: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("fujian_merchant")
	var guang: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("guangzhou_trader")
	var warship: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("warship_patrol")
	_assert_eq(fujian.sail_type, "square", "福船 model sail_type")
	_assert_eq(guang.sail_type, "lateen", "广船 model sail_type")
	_assert_gt(guang.hull_points.size(), 4, "广船 hull polygon")
	_assert_gt(warship.gun_ports.size(), 0, "巡防舰 gun ports")

	var fujian_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("fujian_merchant")
	var guang_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("guangzhou_trader")
	var warship_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("warship_patrol")
	_assert_gt(fujian_spawn.y, 100.0, "福船出港偏移 > 旧固定 100")
	_assert_gt(warship_spawn.y, fujian_spawn.y, "巡防舰出港偏移大于福船")
	_assert_gt(guang_spawn.y, 90.0, "广船出港偏移合理")

	var summary: String = ShipSystem.format_ship_summary(ship)
	_assert_true(summary.contains("福船"), "format_ship_summary name")
	_assert_true(summary.contains("横帆"), "format_ship_summary sail")

	var delta: String = ShipSystem.format_hull_change_delta(ship, "guangzhou_trader")
	_assert_true(delta.contains("耐久+10"), "hull delta max_hp")
	_assert_true(delta.contains("帆→纵帆"), "hull delta sail change")

	var mini_hull: PackedVector2Array = ShipModelLibrary.get_minimap_hull("fujian_merchant")
	_assert_gt(mini_hull.size(), 4, "minimap hull points")

	var patrol_hull := ShipSystem.get_hull("warship_patrol")
	var no_flags := func(_flag: String) -> bool: return false
	_assert_true(not ShipSystem.is_hull_unlocked(patrol_hull, 0, no_flags), "warship locked by default")
	var hull_offers: Array = ShipSystem.list_shipyard_hull_offers("fujian_merchant", 0, no_flags)
	var has_locked_warship := false
	for offer in hull_offers:
		if str(offer.get("hull", {}).get("id", "")) == "warship_patrol":
			has_locked_warship = true
			_assert_true(offer.get("locked", false), "warship offer shown locked")
	_assert_true(has_locked_warship, "warship in shipyard offers")

	var has_ch1 := func(flag: String) -> bool: return flag == "chapter1_complete"
	_assert_true(ShipSystem.is_hull_unlocked(patrol_hull, 30, has_ch1), "warship unlocked with fame+flag")

	var fujian_hull: Dictionary = ShipSystem.get_hull("fujian_merchant")
	_assert_true(not fujian_hull.get("visual", {}).is_empty(), "福船 visual block in ships.json")
	_assert_eq(fujian.hull_id, "fujian_merchant", "JSON model hull_id")
	_assert_eq(fujian.hull_points.size(), 6, "JSON 福船 hull_points count")

	var combat_detail: String = ShipSystem.format_combat_ship_detail(ship)
	_assert_true(combat_detail.contains("福船"), "combat detail hull name")
	_assert_true(combat_detail.contains("横帆"), "combat detail sail")
	_assert_true(combat_detail.contains("炮2"), "combat detail artillery")
	_assert_true(combat_detail.contains("机动5"), "combat detail maneuver")

	var nav := NavigationState.new()
	nav.save_world_map_pose(Vector2(1200.5, -800.25), 1.57)
	_assert_true(nav.world_map_pose_saved, "nav pose saved flag")
	_assert_eq(nav.world_map_position, Vector2(1200.5, -800.25), "nav pose position")
	var nav_dict: Dictionary = nav.to_dict()
	var nav2 := NavigationState.new()
	nav2.from_dict(nav_dict)
	_assert_true(nav2.world_map_pose_saved, "nav pose round-trip saved")
	_assert_eq(nav2.world_map_position, Vector2(1200.5, -800.25), "nav pose round-trip position")
	_assert_lt(absf(nav2.world_map_rotation - 1.57), 0.001, "nav pose round-trip rotation")
	nav2.clear_world_map_pose()
	_assert_true(not nav2.world_map_pose_saved, "nav pose cleared")
	_assert_true(nav2.set_voyage_destination("guangzhou"), "voyage destination set accepts valid port")
	_assert_eq(nav2.voyage_destination_id, "guangzhou", "voyage destination stored")
	_assert_true(not nav2.set_voyage_destination("not_a_port"), "voyage destination rejects invalid port")
	_assert_eq(nav2.voyage_destination_id, "guangzhou", "voyage destination unchanged after reject")
	var nav3 := NavigationState.new()
	nav3.from_dict(nav2.to_dict())
	_assert_eq(nav3.voyage_destination_id, "guangzhou", "voyage destination round-trip")
	nav3.clear_voyage_destination()
	_assert_eq(nav3.voyage_destination_id, "", "voyage destination cleared")

	var weather_map := Node2D.new()
	var weather_canvas := CanvasModulate.new()
	var weather_rain := CPUParticles2D.new()
	var weather_flash := ColorRect.new()
	var weather_label := Label.new()
	var weather_ship := Node2D.new()
	var weather := WorldWeatherTime.new(weather_map, weather_canvas, weather_rain, weather_flash, weather_label, weather_ship)
	weather.paused = true
	var before_time := weather.time_of_day
	weather._process(100.0)
	_assert_eq(weather.time_of_day, before_time, "WorldWeatherTime paused does not advance time")
	weather.free()
	weather_map.free()
	weather_canvas.free()
	weather_rain.free()
	weather_flash.free()
	weather_label.free()
	weather_ship.free()
	print("")

# ── MapLayout / 战略地图坐标 ─────────────────────────────

func _test_map_layout() -> void:
	print("--- MapLayout ---")
	var bounds := MapLayout.get_world_bounds()
	_assert_eq(bounds.size, Vector2(26000.0, 32200.0), "world_bounds size")
	_assert_lt(absf(MapLayout.world_bounds_aspect() - (26000.0 / 32200.0)), 0.0001, "world_bounds aspect")

	var tex := MapLayout.get_map_texture()
	_assert_not_null(tex, "map texture loads")
	if tex != null:
		var tex_size := Vector2(tex.get_width(), tex.get_height())
		_assert_true(
			MapLayout.texture_matches_world_bounds(tex_size),
			"map texture aspect matches world_bounds"
		)
		var xform := MapLayout.map_sprite_transform(tex_size)
		_assert_eq(xform.origin, bounds.get_center(), "map sprite transform origin")
		_assert_eq(tex_size, Vector2(8192.0, 10145.0), "map texture size matches world_bounds aspect")

	var mask := MapLayout.get_sea_mask_texture()
	_assert_not_null(mask, "sea mask texture loads")
	if tex != null and mask != null:
		var mask_size := Vector2(mask.get_width(), mask.get_height())
		_assert_eq(mask_size, Vector2(tex.get_width(), tex.get_height()), "sea mask size matches map texture")
		_assert_true(
			MapLayout.texture_matches_world_bounds(mask_size),
			"sea mask aspect matches world_bounds"
		)
	_assert_eq(
		MapLayout.get_sea_mask_path(),
		"res://assets/map_east_asia_sea_mask.png",
		"sea_mask path from ports.json meta"
	)

	var ports: Array = MapLayout.get_ports_data()
	var with_map_pos := 0
	for port_data in ports:
		var port_id: String = port_data.get("id", "")
		_assert_true(MapLayout.has_map_pos(port_id), "port has map_pos: %s" % port_id)
		with_map_pos += 1
		for conn_id in port_data.get("connections", []):
			var conn_str := str(conn_id)
			_assert_true(
				MapLayout.has_map_pos(conn_str),
				"connection target exists: %s -> %s" % [port_id, conn_str]
			)

		var uv := MapLayout.get_map_pos(port_id)
		var world_from_uv := MapLayout.map_to_world(uv)
		var world_from_port := MapLayout.port_world_position(port_data)
		_assert_eq(world_from_uv, world_from_port, "map_pos uv matches port world position: %s" % port_id)

		var roundtrip := MapLayout.world_to_map(world_from_uv)
		_assert_lt((roundtrip - uv).length(), 0.0001, "world/map uv roundtrip: %s" % port_id)

		_assert_true(bounds.has_point(world_from_uv), "port inside world_bounds: %s" % port_id)

		var pos_data: Dictionary = port_data.get("position", {})
		if pos_data.has("x") and pos_data.has("y"):
			var json_pos := Vector2(float(pos_data.x), float(pos_data.y))
			_assert_lt(
				json_pos.distance_to(world_from_uv),
				1.0,
				"ports.json position synced with map_pos: %s" % port_id
			)

	_assert_eq(with_map_pos, ports.size(), "all ports have map_pos")
	_assert_true(
		MapRoutePainter.river_route_keys().has(MapRoutePainter.route_key("bugan", "bassein")),
		"bugan-bassein river route suppresses plain route"
	)

	var minimap_rect := Rect2(Vector2.ZERO, Vector2(240.0, 180.0))
	var minimap_inset := 6.0
	var inner := Rect2(
		Vector2(minimap_inset, minimap_inset),
		minimap_rect.size - Vector2(minimap_inset * 2.0, minimap_inset * 2.0)
	)
	for port_data in ports:
		var port_id: String = port_data.get("id", "")
		var uv: Vector2 = MapLayout.get_map_pos(port_id)
		var px := MapLayout.uv_to_pixel(uv, inner.size) + inner.position
		_assert_true(inner.has_point(px), "minimap pixel inside inner rect: %s" % port_id)
	print("")

# ═══════════════════════════════════════════════════════════
# Mock 事件 — 用于测试 PriceEngine 事件修正逻辑
