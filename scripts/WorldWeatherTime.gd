class_name WorldWeatherTime
extends Node

## 接管大地图的天气、光影与时间流逝逻辑，为 WorldMap.gd 瘦身减负。

var time_of_day: float = 8.0
var is_storm: bool = false
var storm_timer: float = 30.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 30.0
var paused: bool = false

var _map: Node2D
var _canvas_modulate: CanvasModulate
var _rain_particles: CPUParticles2D
var _lightning_flash: ColorRect
var _weather_status: Label
var _ship: Node2D

func _init(map: Node2D, c_mod: CanvasModulate, r_part: CPUParticles2D, l_flash: ColorRect, w_status: Label, s_node: Node2D) -> void:
	name = "WorldWeatherTime"
	_map = map
	_canvas_modulate = c_mod
	_rain_particles = r_part
	_lightning_flash = l_flash
	_weather_status = w_status
	_ship = s_node


func _process(delta: float) -> void:
	if paused:
		return
	if not is_instance_valid(_ship) or not is_instance_valid(_canvas_modulate):
		return

	time_of_day += delta * 0.2

	while time_of_day >= 24.0:
		time_of_day -= 24.0
		var old_crew = GameState.crew_count
		var advance_result: Dictionary = GameState.advance_world_day()
		GameState.process_daily_consumption()
		WorldEventTracker.process_day()
		TradeEventGenerator.try_generate()
		TradeEventGenerator.process_day()
		GameState.market.process_daily_economy()
		var tick_ctx := {
			"world_day": GameState.navigation.world_day,
			"world_month": GameState.navigation.world_month,
		}
		StoryEventChainEngine.check_triggers("day_advance", tick_ctx)
		if advance_result.get("month_advance", false):
			StoryEventChainEngine.check_triggers("month_advance", tick_ctx)
		if GameState.crew_count < old_crew:
			var ft = ResourceManager.FloatingText.instantiate()
			ft.text = "【警告】水尽粮绝！水手减少！"
			ft.modulate = GameColors.FLOATING_CREW_LOSS
			ft.global_position = _ship.global_position + FloatingTextConfig.OFFSET_CREW_LOSS
			_map.add_child(ft)
			get_tree().create_timer(FloatingTextConfig.LIFETIME_CREW_LOSS, false).timeout.connect(func():
				if is_instance_valid(ft):
					ft.queue_free()
			)
			GameState.game_log.warning(GameLog.Category.VOYAGE, "水尽粮绝，水手减少 %d 人" % (old_crew - GameState.crew_count))

	var light_color := GameColors.LIGHT_NOON
	if time_of_day < 5.0 or time_of_day > 19.0:
		light_color = GameColors.LIGHT_NIGHT
	elif time_of_day >= 5.0 and time_of_day < 7.0:
		light_color = GameColors.LIGHT_DAWN
	elif time_of_day > 17.0 and time_of_day <= 19.0:
		light_color = GameColors.LIGHT_DUSK

	storm_timer -= delta
	if storm_timer <= 0:
		is_storm = not is_storm
		if is_storm:
			storm_timer = randf_range(20.0, 40.0)
			_weather_status.text = "当前天气: 狂风骤雨 (极其危险!)"
			_weather_status.modulate = GameColors.WARNING
			_rain_particles.emitting = true
			_ship.set("wind_strength", base_wind_strength * randf_range(2.0, 3.5))
			var angle = randf() * TAU
			_ship.set("wind_vector", Vector2(cos(angle), sin(angle)))
			GameState.game_log.warning(GameLog.Category.VOYAGE, "风暴来袭！风力 %.0f" % _ship.get("wind_strength"))
		else:
			storm_timer = randf_range(40.0, 80.0)
			_weather_status.text = "当前天气: 晴朗"
			_weather_status.modulate = GameColors.INFO
			_rain_particles.emitting = false
			_ship.set("wind_strength", base_wind_strength)
			_ship.set("wind_vector", Vector2(0, 1))

	if is_storm:
		light_color = light_color.lerp(GameColors.LIGHT_STORM, 0.8)
		lightning_timer -= delta
		if lightning_timer <= 0:
			_strike_lightning()
			lightning_timer = randf_range(2.0, 8.0)

	_canvas_modulate.color = _canvas_modulate.color.lerp(light_color, 2.0 * delta)


func _strike_lightning() -> void:
	if not is_instance_valid(_lightning_flash):
		return
	_lightning_flash.visible = true
	_lightning_flash.color.a = 0.8
	var tween := create_tween()
	tween.tween_property(_lightning_flash, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): _lightning_flash.visible = false)
