extends RefCounted

var _runner = null

class CalendarFakeState:
	var story_flags: Dictionary = {}
	var fame: int = 0

	func set_story_flag(flag: String, value: bool) -> void:
		story_flags[flag] = value

	func has_story_flag(flag: String) -> bool:
		return bool(story_flags.get(flag, false))

	func apply_effects(effects: Dictionary) -> void:
		if effects.has("fame"):
			fame += int(effects["fame"])

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	_test_calendar_state()
	_test_calendar_event_scheduler()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _assert_lt(actual: float, threshold: float, msg: String) -> void:
	_runner._assert_lt(actual, threshold, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

func _tree_root():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null

func _test_calendar_state() -> void:
	print("[CalendarState]")

	var calendar_script = _load_script_or_fail("res://scripts/state/CalendarState.gd", "CalendarState 脚本可加载")
	if calendar_script == null:
		print("")
		return

	var calendar = calendar_script.new()
	_assert_eq(calendar.year, 1255, "CalendarState: 初始年=1255")
	_assert_eq(calendar.month, 1, "CalendarState: 初始月=1")
	_assert_eq(calendar.day, 1, "CalendarState: 初始日=1")
	_assert_eq(calendar.date_key(), "宝祐3年1月", "CalendarState: 宝祐三年 date_key")
	_assert_eq(calendar.months_elapsed(), 0, "CalendarState: 初始 months_elapsed=0")

	var signal_months: Array = []
	calendar.month_changed.connect(func(month_key: String): signal_months.append(month_key))
	var r1: Dictionary = calendar.advance_days(29)
	_assert_eq(calendar.day, 30, "CalendarState: 推进29日至本月30日")
	_assert_eq(r1.get("months_crossed", []).size(), 0, "CalendarState: 未跨月时 months_crossed 为空")
	var r2: Dictionary = calendar.advance_days(1)
	_assert_eq(calendar.month, 2, "CalendarState: 第30日后跨至2月")
	_assert_eq(calendar.day, 1, "CalendarState: 跨月后 day=1")
	_assert_eq(r2.get("months_crossed", [])[0], "宝祐3年2月", "CalendarState: months_crossed 记录新月份")
	_assert_eq(signal_months.size(), 1, "CalendarState: 跨月发 month_changed")

	calendar.from_dict({"year": 1255, "month": 4, "day": 10})
	_assert_eq(calendar.date_key(), "宝祐3年4月", "CalendarState: 任意月份 date_key")
	_assert_eq(calendar.months_elapsed(), 3, "CalendarState: months_elapsed 0-indexed")
	var rest_days: int = calendar.advance_to_next_month()
	_assert_eq(rest_days, 21, "CalendarState: 4月10日休整至下月消耗21天")
	_assert_eq(calendar.month, 5, "CalendarState: 休整后进入5月")
	_assert_eq(calendar.day, 1, "CalendarState: 休整后为1日")

	calendar.from_dict({"year": 1300, "month": 99, "day": -5})
	_assert_eq(calendar.month, 12, "CalendarState: from_dict clamp month")
	_assert_eq(calendar.day, 1, "CalendarState: from_dict clamp day")
	_assert_eq(calendar.date_key(), "Y1300M12", "CalendarState: 年号越界降级")

	var tree_root = _tree_root()
	var game_state = tree_root.get_node_or_null("/root/GameState") if tree_root != null else null
	_assert_true(game_state != null, "GameState autoload 可取得")
	var gs_calendar = game_state.get("calendar") if game_state != null else null
	_assert_true(gs_calendar != null, "GameState: calendar 模块已挂接")
	if gs_calendar != null and game_state != null:
		gs_calendar.from_dict({"year": 1255, "month": 1, "day": 29})
		game_state.process_daily_consumption()
		game_state.process_daily_consumption()
		_assert_eq(gs_calendar.month, 2, "GameState.process_daily_consumption 同步推进日历月份")
		_assert_eq(gs_calendar.day, 1, "GameState.process_daily_consumption 同步推进日历日期")
		var saved_state: Dictionary = game_state.to_save_dict()
		_assert_true(saved_state.has("calendar"), "GameState: 存档包含 calendar")
		gs_calendar.from_dict({"year": 1255, "month": 1, "day": 1})
		game_state.from_save_dict(saved_state)
		_assert_eq(gs_calendar.month, 2, "GameState: calendar 存档恢复月份")
		_assert_eq(gs_calendar.day, 1, "GameState: calendar 存档恢复日期")
		_assert_true(calendar.has_method("days_until_next_month"), "CalendarState: 暴露 days_until_next_month")
		if calendar.has_method("days_until_next_month"):
			calendar.from_dict({"year": 1255, "month": 4, "day": 10})
			_assert_eq(calendar.days_until_next_month(), 21, "CalendarState: days_until_next_month=21")
		_assert_true(game_state.has_method("rest_to_next_month"), "GameState: 暴露 rest_to_next_month 玩家动词")
		if game_state.has_method("rest_to_next_month"):
			var before_rest_state: Dictionary = game_state.to_save_dict()
			game_state.food = 100.0
			game_state.water = 100.0
			gs_calendar.from_dict({"year": 1255, "month": 6, "day": 10})
			var rest_days_game: int = int(game_state.rest_to_next_month())
			_assert_eq(rest_days_game, 21, "GameState.rest_to_next_month 返回消耗天数")
			_assert_eq(gs_calendar.month, 7, "GameState.rest_to_next_month 推进至下月")
			_assert_eq(gs_calendar.day, 1, "GameState.rest_to_next_month 推进至1日")
			_assert_lt(game_state.food, 100.0, "GameState.rest_to_next_month 复用每日生存消耗")
			game_state.from_save_dict(before_rest_state)

	var status_scene: PackedScene = load(ResourcePaths.SCENE_PORT_STATUS_BAR) as PackedScene
	_assert_true(status_scene != null, "CalendarState UI: PortStatusBar 可加载")
	if status_scene != null and game_state != null and tree_root != null:
		var status_bar = status_scene.instantiate()
		tree_root.add_child(status_bar)
		var status_calendar = game_state.get("calendar")
		if status_calendar != null:
			status_calendar.from_dict({"year": 1255, "month": 8, "day": 1})
		status_bar.refresh()
		var location_label: Label = status_bar.get_node("Panel/Body/VBox/PrimaryRow/Location/Margin/Row/VBox/Value") as Label
		_assert_true(location_label.text.contains("宝祐3年8月"), "PortStatusBar: 所在 chip 显示日期")
		status_bar.queue_free()

	print("")

func _test_calendar_event_scheduler() -> void:
	print("[Calendar Scheduler]")

	var scheduler_script = _load_script_or_fail(ResourcePaths.SCRIPT_CALENDAR_EVENT_SCHEDULER, "CalendarEventScheduler 脚本可加载")
	if scheduler_script == null:
		print("")
		return

	var scheduler = scheduler_script.new()
	_assert_true(scheduler.has_method("load_from_data"), "CalendarScheduler: 支持测试数据加载")
	_assert_true(scheduler.has_method("check_and_fire"), "CalendarScheduler: 暴露 check_and_fire")
	_assert_true(scheduler.has_method("bind_calendar"), "CalendarScheduler: 可监听 CalendarState.month_changed")
	_assert_true(ResourcePaths.DATA_CALENDAR_EVENTS != "", "ResourcePaths.DATA_CALENDAR_EVENTS")

	var calendar_script = _load_script_or_fail("res://scripts/state/CalendarState.gd", "CalendarState 脚本可加载")
	if calendar_script == null:
		print("")
		return
	var calendar = calendar_script.new()
	var fixture := {
		"version": 1,
		"events": [
			{
				"id": "low_scene",
				"fire": {"month_offset": 2},
				"condition": {"flag": "chapter2_complete"},
				"action": {"type": "scene", "target": "low_scene_target"},
				"priority": 1,
				"once": true,
			},
			{
				"id": "high_scene",
				"fire": {"month_offset": 2},
				"condition": {"flag": "chapter2_complete", "rank_gte": 4},
				"action": {"type": "scene", "target": "high_scene_target"},
				"priority": 10,
				"once": true,
			},
			{
				"id": "absolute_effect",
				"fire": {"date": {"year": 1255, "month": 4}},
				"condition": {},
				"action": {"type": "effect", "effects": {"fame": 2}},
				"priority": 5,
				"once": true,
			},
		]
	}
	scheduler.load_from_data(fixture)
	_assert_eq(scheduler.get_event_count(), 3, "CalendarScheduler: 载入3条事件")

	var fake_state := CalendarFakeState.new()
	fake_state.set_story_flag("chapter2_complete", true)
	var fired_early: Array = scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 4})
	_assert_eq(fired_early.size(), 0, "CalendarScheduler: 未到月不触发")

	calendar.from_dict({"year": 1255, "month": 3, "day": 1})
	IdempotencyGuard.clear_all()
	var requested_scenes: Array = []
	scheduler.scene_requested.connect(func(scene_id: String): requested_scenes.append(scene_id))
	var fired_due: Array = scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 4})
	_assert_eq(fired_due.size(), 1, "CalendarScheduler: 到月只触发最高优先级事件")
	_assert_eq(fired_due[0], "high_scene", "CalendarScheduler: priority 高者先")
	_assert_eq(requested_scenes[0], "high_scene_target", "CalendarScheduler: scene action 发出目标场景")
	_assert_true(IdempotencyGuard.is_processed("calendar_event:high_scene"), "CalendarScheduler: once 事件登记幂等键")

	var replay: Array = scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 4})
	_assert_eq(replay.size(), 1, "CalendarScheduler: high once 不重放后允许同月低优先级补触发")
	_assert_eq(replay[0], "low_scene", "CalendarScheduler: once 后低优先级可继续触发")
	var replay_low: Array = scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 4})
	_assert_eq(replay_low.size(), 0, "CalendarScheduler: once:true 不重放")

	var no_rank_scheduler = scheduler_script.new()
	no_rank_scheduler.load_from_data(fixture)
	IdempotencyGuard.clear_all()
	var no_rank: Array = no_rank_scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 3})
	_assert_eq(no_rank[0], "low_scene", "CalendarScheduler: rank_gte 未满足时跳过高优先级")

	calendar.from_dict({"year": 1255, "month": 4, "day": 1})
	var before_fame := fake_state.fame
	var effect_fired: Array = no_rank_scheduler.check_and_fire({"calendar": calendar, "state": fake_state, "rank": 3})
	_assert_eq(effect_fired[0], "absolute_effect", "CalendarScheduler: date(year/month) 可触发")
	_assert_eq(fake_state.fame, before_fame + 2, "CalendarScheduler: effect action 调用 state.apply_effects")

	var bound_scheduler = scheduler_script.new()
	bound_scheduler.load_from_data({"version": 1, "events": [{"id": "bound_month", "fire": {"month_offset": 1}, "action": {"type": "scene", "target": "bound_scene"}, "priority": 1, "once": true}]})
	var bound_scenes: Array = []
	bound_scheduler.scene_requested.connect(func(scene_id: String): bound_scenes.append(scene_id))
	var bind_state := CalendarFakeState.new()
	bound_scheduler.bind_calendar(calendar_script.new(), bind_state)
	var bound_calendar = bound_scheduler.get_bound_calendar()
	IdempotencyGuard.clear_all()
	bound_calendar.advance_days(30)
	_assert_eq(bound_scenes[0], "bound_scene", "CalendarScheduler: month_changed 自动检查调度")

	var tree_root = _tree_root()
	var game_state = tree_root.get_node_or_null("/root/GameState") if tree_root != null else null
	_assert_true(game_state != null, "CalendarScheduler: GameState autoload 可取得")
	if game_state != null:
		_assert_true(game_state.get("calendar_scheduler") != null, "GameState: calendar_scheduler 模块已挂接")
		var scheduler_saved: Dictionary = game_state.to_save_dict()
		_assert_true(scheduler_saved.has("calendar_scheduler"), "GameState: 存档包含 calendar_scheduler")

	IdempotencyGuard.clear_all()
	print("")
