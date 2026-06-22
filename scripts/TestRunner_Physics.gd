extends SceneTree

func _init() -> void:
	print("--- Running SailPhysicsEngine Tests ---")
	
	# 公共参数
	var base_speed := 100.0
	var zero_vel := Vector2.ZERO
	var delta := 1.0
	var wind_vec := Vector2(0, -1) # 南风，向北吹
	var wind_str := 100.0

	# Test 1: Square Sail Tailwind (顺风)
	var res1 = SailPhysicsEngine.calculate(zero_vel, Vector2(0, -1), wind_vec, wind_str, 2, base_speed, "square", delta)
	assert(res1.efficiency > 1.0, "Tailwind efficiency should be > 1.0 for square sail")
	assert(not res1.is_dead_wind, "Tailwind is not dead wind")
	print("Test 1 PASS: Square Sail Tailwind -> Speed %.2f" % res1.new_velocity.length())
	
	# Test 2: Square Sail Headwind (逆风)
	var res2 = SailPhysicsEngine.calculate(zero_vel, Vector2(0, 1), wind_vec, wind_str, 2, base_speed, "square", delta)
	assert(res2.is_dead_wind, "Headwind should be dead wind for square sail")
	print("Test 2 PASS: Square Sail Headwind -> Speed %.2f" % res2.new_velocity.length())
	
	# Test 3: Lateen Sail Crosswind (侧风，90度)
	var res3 = SailPhysicsEngine.calculate(zero_vel, Vector2(1, 0), wind_vec, wind_str, 2, base_speed, "lateen", delta)
	assert(res3.efficiency > 0.4, "Lateen crosswind efficiency should be > 0.4")
	print("Test 3 PASS: Lateen Crosswind -> Speed %.2f" % res3.new_velocity.length())
	
	print("ALL PHYSICS CHECKS PASSED.")
	quit(0)
