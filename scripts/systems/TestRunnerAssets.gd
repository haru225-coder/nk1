extends RefCounted

var _runner = null
var root = null

func _init(runner = null) -> void:
	_runner = runner
	if _runner != null:
		root = _runner.root

func run_asset_placeholder_json() -> void:
	_test_asset_placeholder_json()

func run_text_keys() -> void:
	_test_text_keys()

func run_cutscene_player() -> void:
	_test_cutscene_player()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _assert_not_null(value, msg: String) -> void:
	_runner._assert_not_null(value, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

# ── NK1-P6-POLISH-004: AssetPlaceholder JSON 化测试 ────────

func _test_asset_placeholder_json() -> void:
	print("[AssetPlaceholder JSON]")

	# JSON 文件存在
	_assert_true(FileAccess.file_exists("res://data/asset_backgrounds.json"), "asset_backgrounds.json 文件存在")

	# 实例化 AssetPlaceholder（extends Node）
	var ap: Node = Node.new()
	var asset_placeholder_script = _load_script_or_fail("res://scripts/AssetPlaceholder.gd", "AssetPlaceholder 脚本可加载")
	if asset_placeholder_script == null:
		ap.free()
		print("")
		return
	ap.set_script(asset_placeholder_script)
	_assert_not_null(ap, "AssetPlaceholder 实例化成功")

	# 有图池的港口不再走单图别名
	var mapped_path: String = ap.get_background_path("res://assets/bg_quanzhou_port.png")
	_assert_eq(mapped_path, "res://assets/bg_quanzhou_port.png", "bg_quanzhou_port passthrough (pool)")

	mapped_path = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped_path, "res://assets/bg_northern_fortress_snow.png", "bg_byland_port -> bg_northern_fortress_snow")

	mapped_path = ap.get_background_path("res://assets/bg_xinghua_school.png")
	_assert_eq(mapped_path, "res://assets/bg_xinghua_residence.png", "bg_xinghua_school -> bg_xinghua_residence")

	# 不存在的 key 返回原值（passthrough）
	mapped_path = ap.get_background_path("res://assets/bg_nonexistent.png")
	_assert_eq(mapped_path, "res://assets/bg_nonexistent.png", "不存在 key: passthrough")

	# Legacy avatar 查询
	var avatar_path: String = ap.get_legacy_avatar_path("chen_wenlong")
	_assert_eq(avatar_path, "res://assets/portraits/portrait_chen_wenlong.png", "legacy avatar: chen_wenlong")

	avatar_path = ap.get_legacy_avatar_path("customs_official")
	_assert_eq(avatar_path, "res://assets/portraits/portrait_customs_official.png", "legacy avatar: customs_official")

	avatar_path = ap.get_legacy_avatar_path("unknown_npc")
	_assert_eq(avatar_path, "", "不存在 NPC: 空字符串")

	# 进港图池轮换
	var pick1: String = ap.pick_background_path("res://assets/bg_tunmen_port.png")
	var pick2: String = ap.pick_background_path("res://assets/bg_tunmen_port.png")
	_assert_true(pick1.begins_with("res://assets/port_pools/tunmen/"), "tunmen pool pick1")
	_assert_true(pick2.begins_with("res://assets/port_pools/tunmen/"), "tunmen pool pick2")
	_assert_true(pick1 != pick2, "tunmen pool rotates")

	# 热重载（应仍返回同样的映射）
	ap.reload_config()
	mapped_path = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped_path, "res://assets/bg_northern_fortress_snow.png", "reload 后映射仍正确")

	# 验证剩余别名都能查询（无图池港口仍走 fallback）
	var known_aliases: Array[String] = [
		"res://assets/bg_xinghua_school.png", "res://assets/bg_lin_ship.png",
		"res://assets/bg_departure.png", "res://assets/bg_black_water.png",
		"res://assets/bg_sea_route_aligned.png", "res://assets/bg_hakata_port.png",
		"res://assets/bg_qiongzhou_port.png", "res://assets/bg_sanfoqi_port.png",
		"res://assets/bg_longyamen_port.png", "res://assets/bg_jiaozhi_port.png",
		"res://assets/bg_yeshou_port.png", "res://assets/bg_byland_port.png",
		"res://assets/bg_xuwen_port.png",
	]
	var alias_hits := 0
	for key in known_aliases:
		if ap.get_background_path(key) != key:
			alias_hits += 1
	_assert_eq(alias_hits, known_aliases.size(), "fallback 别名都正确加载")

	var pool_pick: String = ap.pick_background_path("res://assets/bg_keelung_port.png")
	_assert_true(pool_pick.begins_with("res://assets/port_pools/keelung/"), "keelung pool deployed")

	# 清理
	ap.queue_free()

	print("")

# ── NK1-P6-POLISH-004: TextKeys 常量类测试 ─────────────────

func _test_text_keys() -> void:
	print("[TextKeys]")

	# Intent 成功消息
	_assert_eq(TextKeys.INTENT_OK, "intent.ok", "TextKeys.INTENT_OK")
	_assert_eq(TextKeys.INTENT_PAYMENT_SUCCESS, "intent.payment.success", "TextKeys.INTENT_PAYMENT_SUCCESS")
	_assert_eq(TextKeys.INTENT_MARKET_BUY_SUCCESS, "intent.market_buy.success", "TextKeys.INTENT_MARKET_BUY_SUCCESS")
	_assert_eq(TextKeys.INTENT_MARKET_SELL_SUCCESS, "intent.market_sell.success", "TextKeys.INTENT_MARKET_SELL_SUCCESS")
	_assert_eq(TextKeys.INTENT_REPAIR_SUCCESS, "intent.repair.success", "TextKeys.INTENT_REPAIR_SUCCESS")
	_assert_eq(TextKeys.INTENT_BRIBE_SUCCESS, "intent.bribe.success", "TextKeys.INTENT_BRIBE_SUCCESS")
	_assert_eq(TextKeys.INTENT_COMBAT_STARTED, "intent.combat.started", "TextKeys.INTENT_COMBAT_STARTED")

	# Error 消息
	_assert_eq(TextKeys.ERROR_INTENT_MISSING_TYPE, "error.intent.missing_type", "TextKeys.ERROR_INTENT_MISSING_TYPE")
	_assert_eq(TextKeys.ERROR_MARKET_NO_PORT, "error.market.no_port", "TextKeys.ERROR_MARKET_NO_PORT")
	_assert_eq(TextKeys.ERROR_MARKET_NO_STOCK, "error.market.no_stock", "TextKeys.ERROR_MARKET_NO_STOCK")
	_assert_eq(TextKeys.ERROR_PAYMENT_INSUFFICIENT_FUNDS, "error.payment.insufficient_funds", "TextKeys.ERROR_PAYMENT_INSUFFICIENT_FUNDS")
	_assert_eq(TextKeys.ERROR_BRIBE_CUSTOMS_BLOCKED, "error.bribe.customs_blocked", "TextKeys.ERROR_BRIBE_CUSTOMS_BLOCKED")
	_assert_eq(TextKeys.ERROR_COMBAT_NO_FLEET, "error.combat.no_fleet", "TextKeys.ERROR_COMBAT_NO_FLEET")
	_assert_eq(TextKeys.ERROR_INSPECTION_NO_FUNDS, "error.inspection.no_funds", "TextKeys.ERROR_INSPECTION_NO_FUNDS")

	# is_intent_success 验证
	_assert_true(TextKeys.is_intent_success("intent.payment.success"), "is_intent_success: payment")
	_assert_true(TextKeys.is_intent_success("intent.bribe.success"), "is_intent_success: bribe")
	_assert_true(not TextKeys.is_intent_success("unknown.key"), "is_intent_success: unknown 不存在")

	# is_error 验证
	_assert_true(TextKeys.is_error("error.intent.missing_type"), "is_error: missing_type")
	_assert_true(TextKeys.is_error("error.combat.no_fleet"), "is_error: combat")
	_assert_true(TextKeys.is_error("error.market.no_stock"), "is_error: market.no_stock")
	_assert_true(not TextKeys.is_error("intent.payment.success"), "is_error: intent.* 不属于 error")

	# all_intent_success_keys 返回 20 个
	_assert_eq(TextKeys.all_intent_success_keys().size(), 20, "all_intent_success_keys: 20 个")

	# all_error_keys 返回 50+ 个
	var err_count: int = TextKeys.all_error_keys().size()
	_assert_true(err_count >= 50, "all_error_keys: >= 50 个")

	print("")

# ── P7-X: CutscenePlayer 测试 ─────────────────────────────

func _test_cutscene_player() -> void:
	print("[CutscenePlayer]")

	# 实例化 CutscenePlayer（从场景加载，确保 @onready 节点存在）
	var scene: PackedScene = load("res://scenes/CutscenePlayer.tscn") as PackedScene
	_assert_not_null(scene, "CutscenePlayer.tscn 加载成功")
	_assert_true(scene != null, "CutscenePlayer.tscn 是 PackedScene")

	var player: Node = scene.instantiate()
	_assert_not_null(player, "CutscenePlayer 实例化成功")
	root.add_child(player)

	# 数据加载
	_assert_true(player._data.size() > 0, "cutscenes.json 加载: _data.size() > 0")
	_assert_true(player._data.has("quanzhou_arrival"), "_data 含 quanzhou_arrival")
	_assert_true(player._data.has("ch3_start"), "_data 含 ch3_start (含 panels)")
	_assert_true(player._data.has("rank_up_1"), "_data 含 rank_up_1")
	_assert_true(player._data.has("ending_loyalty"), "_data 含 ending_loyalty")
	_assert_eq(player._data["quanzhou_arrival"]["hook"], "port_arrival", "quanzhou_arrival.hook=port_arrival")
	_assert_eq(player._data["quanzhou_arrival"]["port_id"], "quanzhou", "quanzhou_arrival.port_id=quanzhou")
	_assert_eq(int(player._data["rank_up_1"]["rank"]), 1, "rank_up_1.rank=1（JSON 解析为 float 但数值正确）")

	# 1. play("不存在") 静默返回，_playing 保持 false
	_assert_true(not player.play("nonexistent_id_xyz"), "play(不存在 id): 返回 false")
	_assert_true(not player._playing, "play(不存在 id): _playing 保持 false")
	_assert_true(not player.visible, "play(不存在 id): visible 保持 false")

	# 4. _find_by_hook("port_arrival","quanzhou") 返回 "quanzhou_arrival"
	_assert_eq(player._find_by_hook("port_arrival", "quanzhou"), "quanzhou_arrival", "port_arrival+quanzhou -> quanzhou_arrival")

	# 5. _find_by_hook("port_arrival","不存在的港") 返回 ""
	_assert_eq(player._find_by_hook("port_arrival", "不存在的港"), "", "port_arrival+不存在 -> ''")

	# 6. _find_by_hook("chapter_change","chapter3_pu_counter") 返回 "ch3_start"
	_assert_eq(player._find_by_hook("chapter_change", "chapter3_pu_counter"), "ch3_start", "chapter_change+chapter3_pu_counter -> ch3_start")

	# 额外：rank_up / ending 钩子覆盖
	_assert_eq(player._find_by_hook("rank_up", "1"), "rank_up_1", "rank_up+1 -> rank_up_1")
	_assert_eq(player._find_by_hook("ending", "loyalty_ending"), "ending_loyalty", "ending+loyalty_ending -> ending_loyalty")
	_assert_eq(player._find_by_hook("unknown_hook", "x"), "", "未知 hook -> ''")

	# 公开 API get_cutscene_id_for / has_cutscene
	_assert_eq(player.get_cutscene_id_for("port_arrival", "quanzhou"), "quanzhou_arrival", "get_cutscene_id_for 公共 API")
	_assert_true(player.has_cutscene("port_arrival", "quanzhou"), "has_cutscene(存在) -> true")
	_assert_true(not player.has_cutscene("port_arrival", "不存在的港"), "has_cutscene(不存在) -> false")

	# 2. play("quanzhou_arrival") 后 _playing=true，visible=true
	_assert_true(player.play("quanzhou_arrival"), "play(quanzhou_arrival): 返回 true")
	_assert_true(player._playing, "play(quanzhou_arrival): _playing=true")
	_assert_true(player.visible, "play(quanzhou_arrival): visible=true")
	_assert_eq(player._current_id, "quanzhou_arrival", "play: _current_id 正确")
	_assert_true(player.play("ending_loyalty"), "播放中请求有效过场: 成功入队")
	_assert_eq(player._queue.size(), 1, "播放中请求有效过场: 队列新增一段")
	_assert_eq(player._queue[0], "ending_loyalty", "播放中请求有效过场: 保持请求顺序")
	_assert_true(not player.play("nonexistent_id_xyz"), "播放中请求无效过场: 返回 false")
	_assert_eq(player._queue.size(), 1, "播放中请求无效过场: 不污染队列")

	# 3. skip() 后 _playing=false, visible=false, finished 信号发出
	var finished_emitted: Array = [false]
	var finished_id: Array = [""]
	player.finished.connect(func(id: String):
		finished_emitted[0] = true
		finished_id[0] = id
	)
	player.skip()
	_assert_true(not player._playing, "skip(): _playing=false")
	_assert_true(not player.visible, "skip(): visible=false")
	_assert_true(finished_emitted[0], "skip(): finished 信号发出")
	_assert_eq(finished_id[0], "quanzhou_arrival", "skip(): finished id 正确")

	# 7. _data={} 模拟 JSON 缺失：play 任何 id 静默不崩
	var player_empty: Node = scene.instantiate()
	root.add_child(player_empty)
	player_empty._data = {}
	player_empty.play("quanzhou_arrival")
	_assert_true(not player_empty._playing, "_data={} 时 play: 静默，_playing=false")
	_assert_true(not player_empty.visible, "_data={} 时 play: visible=false")
	player_empty.queue_free()

	# 8. panels 多分镜：_panel_index 推进至 size 后触发 _end
	# 注：tween 异步推进；这里直接验证状态机 + 数据。
	var player2: Node = scene.instantiate()
	root.add_child(player2)
	player2.play("ch3_start")
	_assert_eq(player2._panels.size(), 2, "ch3_start panels 数量 = 2")
	_assert_eq(player2._panel_index, 0, "_panel_index 起始 = 0")
	_assert_true(player2._playing, "play(ch3_start) _playing=true（多分镜）")
	# panels 耗尽判断：_panel_index >= _panels.size() 走 _end 分支
	player2._panel_index = player2._panels.size()
	# 直接调 _end 验证结束态（替代等待 tween）
	player2._end()
	_assert_true(not player2._playing, "_end 后 _playing=false")
	_assert_true(not player2.visible, "_end 后 visible=false")
	player2.queue_free()

	# 9. CG 路径经 AssetPlaceholder.get_background_path 解析别名（验证调用，非实际加载）
	# 实例化 AssetPlaceholder（autoload，避免编译期依赖）
	var ap: Node = Node.new()
	var asset_placeholder_script = _load_script_or_fail("res://scripts/AssetPlaceholder.gd", "AssetPlaceholder 脚本可加载")
	if asset_placeholder_script == null:
		ap.free()
		player.queue_free()
		print("")
		return
	ap.set_script(asset_placeholder_script)
	var entry: Dictionary = player._data["quanzhou_arrival"]
	var alias: String = entry.get("cg_alias", "")
	_assert_eq(alias, "res://assets/bg_quanzhou_harbor_koei.png", "cg_alias 字段正确")
	var resolved: String = ap.get_background_path(alias)
	_assert_eq(resolved, "res://assets/bg_quanzhou_harbor_koei.png", "CG 路径经 get_background_path 解析（passthrough）")
	# 验证别名映射确实会触发（无图池港口）
	var mapped: String = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped, "res://assets/bg_northern_fortress_snow.png", "get_background_path 别名映射生效")
	ap.queue_free()

	# panels 中的 cg_alias 同样走解析路径
	var panels: Array = player._data["ch3_start"].get("panels", [])
	_assert_eq(panels.size(), 2, "ch3_start panels 字段读取正确")
	_assert_eq(panels[0].get("duration", 0.0), 3.0, "panel[0].duration=3.0")
	_assert_eq(panels[1].get("duration", 0.0), 2.5, "panel[1].duration=2.5")

	player.queue_free()
	print("")

