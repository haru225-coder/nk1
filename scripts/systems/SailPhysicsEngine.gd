class_name SailPhysicsEngine extends RefCounted

## ═══════════════════════════════════════════════════════════
## SailPhysicsEngine — 风帆动力与洋流计算引擎
## [纯数学域] 不触碰任何 Godot Node 状态，仅作公式结算。
## ═══════════════════════════════════════════════════════════

static func calculate(current_velocity: Vector2, heading: Vector2, wind_vector: Vector2, wind_strength: float, sail_gear: int, base_speed: float, sail_type: String, delta: float) -> Dictionary:
	if sail_gear <= 0:
		return {
			"new_velocity": current_velocity.lerp(Vector2.ZERO, 2.0 * delta),
			"is_dead_wind": false,
			"efficiency": 0.0
		}

	# wind_vector 表示风的去向，heading 表示船的朝向
	var angle_diff = abs(wind_vector.angle_to(heading))
	
	# ponytail: 极简极坐标风阻拟合，用三角函数近似真实风力场
	var efficiency := 0.0
	match sail_type:
		"square":
			# 横帆：顺风极快，侧风减半，逆风完全没动力
			efficiency = maxf(0.0, cos(angle_diff) + 0.1)
		"lateen", _:
			# 纵帆：顺风不如横帆，但侧逆风仍可行驶（Z字打戗）
			var penalty = 0.2 if angle_diff < PI/4.0 else 0.0 # 纯顺风不如横帆
			efficiency = maxf(0.0, cos(angle_diff) + 0.6 - penalty)
			
	var is_dead_wind = efficiency <= 0.05
	var gear_mult := float(sail_gear) / 2.0
	var wind_mult := wind_strength / 100.0
	
	var final_speed = base_speed * efficiency * gear_mult * wind_mult
	
	# 逆风阻断器：完全无法吃风时，允许极慢的“水手划桨”速度，防止彻底卡死
	if is_dead_wind:
		final_speed = base_speed * 0.15 * gear_mult
		
	var target_velocity = heading * final_speed
	
	# 惯性平滑（船的质量极大，加速慢，停船也慢）
	# NK1-P6: 提升响应感 — 加速更跟手，减速更干脆
	var lerp_weight = 1.5 * delta if not is_dead_wind else 0.8 * delta
	var new_velocity = current_velocity.lerp(target_velocity, lerp_weight)
	
	return {
		"new_velocity": new_velocity,
		"is_dead_wind": is_dead_wind,
		"efficiency": efficiency
	}
