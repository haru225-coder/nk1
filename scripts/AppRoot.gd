extends Node

## ═══════════════════════════════════════════════════════════
## AppRoot — 单根壳（P8）
## ═══════════════════════════════════════════════════════════
## Narrative(Main) / Voyage(WorldMap) 子树切换。
## ChromeLayer：出海时抬升 PortStatusBar，与港内共用同一状态条。
## CutscenePlayer：从 Main 抬升到壳层，出海/禁用 Main 时仍可播。
## ═══════════════════════════════════════════════════════════

const MAIN_PACKED := preload(ResourcePaths.SCENE_MAIN)
const WORLD_MAP_PACKED := preload(ResourcePaths.SCENE_WORLD_MAP)
const CUTSCENE_PACKED := preload(ResourcePaths.SCENE_CUTSCENE_PLAYER)
const ModeStackScript := preload(ResourcePaths.SCRIPT_MODE_STACK)
const EndingSettlementScript := preload(ResourcePaths.SCRIPT_ENDING_SETTLEMENT)

var _narrative: Node = null
var _voyage: Node = null
var _combat: Node = null
var _combat_active: bool = false
var _cutscene: Node = null
var _cutscene_active: bool = false
var _mode: String = "narrative"
var _mode_before_combat: String = ""
var _mode_before_cutscene: String = ""

var _chrome_layer: CanvasLayer = null
var _lifted_status: Control = null
var _status_home: Node = null

var _ending_settlement: CanvasLayer = null
var _ending_settlement_shown: bool = false


func _ready() -> void:
	_ensure_chrome_layer()
	_ensure_narrative()
	call_deferred("_adopt_cutscene_from_narrative")
	if not GameState.ending_resolved.is_connected(_on_ending_resolved):
		GameState.ending_resolved.connect(_on_ending_resolved)
	var cutscene_cb := Callable(self, "_on_game_state_cutscene_requested")
	if not GameState.cutscene_requested.is_connected(cutscene_cb):
		GameState.cutscene_requested.connect(cutscene_cb)


func get_mode() -> String:
	return _mode


func get_narrative() -> Node:
	return _narrative


func get_voyage() -> Node:
	return _voyage


func get_combat() -> Node:
	return _combat


func get_cutscene_player() -> Node:
	_ensure_cutscene()
	return _cutscene


func get_status_bar() -> Control:
	if _lifted_status != null and is_instance_valid(_lifted_status):
		return _lifted_status
	return _find_status_bar()


func refresh_chrome() -> void:
	var bar := get_status_bar()
	if bar != null and bar.has_method("refresh"):
		bar.call("refresh")


func log_event(msg: String) -> void:
	if msg == "":
		return
	if _narrative != null and is_instance_valid(_narrative) and _narrative.has_method("append_shell_log"):
		_narrative.call("append_shell_log", msg)


func show_voyage() -> void:
	_dismiss_combat_if_any()
	_ensure_narrative()
	_ensure_cutscene()
	_lift_status_bar()
	_set_status_sea_mode(true)
	if _narrative != null and is_instance_valid(_narrative):
		_narrative.visible = false
		_narrative.process_mode = Node.PROCESS_MODE_DISABLED
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.queue_free()
		_voyage = null
	_voyage = WORLD_MAP_PACKED.instantiate()
	_voyage.name = "VoyageWorldMap"
	add_child(_voyage)
	# 保证状态条 / 过场在 WorldMap 之上
	_raise_shell_overlays()
	_mode = ModeStackScript.MODE_VOYAGE
	SaveManager.set_current_scene_id("world_map")
	refresh_chrome()


func show_narrative(scene_id: String = "") -> void:
	_dismiss_combat_if_any()
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.queue_free()
		_voyage = null
	_set_status_sea_mode(false)
	_restore_status_bar()
	_ensure_narrative()
	_ensure_cutscene()
	if _narrative != null and is_instance_valid(_narrative):
		_narrative.process_mode = Node.PROCESS_MODE_INHERIT
		_narrative.visible = true
		var target := scene_id
		if target == "":
			if GameState.has_flag("return_to_port"):
				GameState.clear_flag("return_to_port")
				target = GameManager.get_port_scene_id(GameState.last_port)
		if target != "" and _narrative.has_method("load_scene"):
			_narrative.call("load_scene", target)
	_mode = ModeStackScript.MODE_NARRATIVE
	refresh_chrome()


## P8-4: 壳层播放过场（暂停航海；Main 禁用时仍可用）
func play_cutscene(cutscene_id: String) -> bool:
	if cutscene_id.strip_edges() == "":
		return false
	_ensure_cutscene()
	if _cutscene == null or not _cutscene.has_method("play"):
		return false
	return bool(_cutscene.call("play", cutscene_id))


func _on_game_state_cutscene_requested(cutscene_id: String) -> void:
	play_cutscene(cutscene_id)


## P8-3: 海战挂到壳层（不挂 WorldMap 子树，避免与航海 process 耦合）
func show_combat(enemy: Dictionary) -> Node:
	if _combat != null and is_instance_valid(_combat):
		return _combat
	_mode_before_combat = _mode if _mode != ModeStackScript.MODE_COMBAT else _mode_before_combat
	if _mode_before_combat == "" or _mode_before_combat == ModeStackScript.MODE_COMBAT:
		_mode_before_combat = ModeStackScript.MODE_VOYAGE if (_voyage != null and is_instance_valid(_voyage)) else ModeStackScript.MODE_NARRATIVE
	# 暂停航海模拟（事件/战斗 UI 使用 PROCESS_MODE_ALWAYS）
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.process_mode = Node.PROCESS_MODE_DISABLED
	var ctrl := CombatSessionController.new()
	ctrl.enemy_data = enemy
	ctrl.name = "CombatSession"
	add_child(ctrl)
	_combat = ctrl
	_combat_active = true
	_mode = ModeStackScript.MODE_COMBAT
	if not ctrl.combat_finished.is_connected(_on_shell_combat_finished):
		ctrl.combat_finished.connect(_on_shell_combat_finished)
	if not ctrl.tree_exited.is_connected(_on_combat_tree_exited):
		ctrl.tree_exited.connect(_on_combat_tree_exited)
	var enemy_name := str(enemy.get("name", enemy.get("id", "未知敌舰")))
	log_event(SeaFeedback.combat_start_log(enemy_name))
	refresh_chrome()
	return ctrl


func _on_shell_combat_finished(result: Dictionary, combat_state = null) -> void:
	if not _combat_active:
		return
	log_event(SeaFeedback.combat_end_log(result if result is Dictionary else {}, combat_state))
	_restore_after_combat()


func _on_combat_tree_exited() -> void:
	_restore_after_combat()


func _restore_after_combat() -> void:
	if not _combat_active and _combat == null:
		return
	_combat_active = false
	_combat = null
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.process_mode = Node.PROCESS_MODE_INHERIT
	if _mode_before_combat != "":
		_mode = _mode_before_combat
	elif _voyage != null and is_instance_valid(_voyage):
		_mode = ModeStackScript.MODE_VOYAGE
	else:
		_mode = ModeStackScript.MODE_NARRATIVE
	_mode_before_combat = ""
	refresh_chrome()


func _dismiss_combat_if_any() -> void:
	if _combat != null and is_instance_valid(_combat):
		_combat_active = false
		_combat.queue_free()
	_combat = null
	_mode_before_combat = ""
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.process_mode = Node.PROCESS_MODE_INHERIT


func _ensure_narrative() -> void:
	if _narrative != null and is_instance_valid(_narrative):
		return
	_narrative = MAIN_PACKED.instantiate()
	_narrative.name = "NarrativeMain"
	add_child(_narrative)
	_mode = ModeStackScript.MODE_NARRATIVE
	call_deferred("_adopt_cutscene_from_narrative")


func _ensure_cutscene() -> void:
	if _cutscene != null and is_instance_valid(_cutscene):
		return
	_adopt_cutscene_from_narrative()
	if _cutscene != null and is_instance_valid(_cutscene):
		return
	# 无 Main 实例时直接创建壳层播放器
	_cutscene = CUTSCENE_PACKED.instantiate()
	_cutscene.name = "ShellCutscenePlayer"
	_cutscene.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_cutscene)
	_wire_cutscene_signals()
	_rebind_cutscene_consumers()


func _adopt_cutscene_from_narrative() -> void:
	if _cutscene != null and is_instance_valid(_cutscene):
		return
	if _narrative == null or not is_instance_valid(_narrative):
		return
	var player := _narrative.get_node_or_null("CutsceneLayer/CutscenePlayer") as Node
	if player == null:
		return
	var home := player.get_parent()
	if home == null:
		return
	home.remove_child(player)
	player.name = "ShellCutscenePlayer"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	_cutscene = player
	_wire_cutscene_signals()
	_rebind_cutscene_consumers()
	_raise_shell_overlays()


func _wire_cutscene_signals() -> void:
	if _cutscene == null or not is_instance_valid(_cutscene):
		return
	if _cutscene.has_signal("started"):
		var start_cb := Callable(self, "_on_cutscene_started")
		if not _cutscene.is_connected("started", start_cb):
			_cutscene.connect("started", start_cb)
	if _cutscene.has_signal("finished"):
		var cb := Callable(self, "_on_cutscene_finished")
		if not _cutscene.is_connected("finished", cb):
			_cutscene.connect("finished", cb)


func _on_cutscene_started(cutscene_id: String) -> void:
	# 任意入口（rank_up / ending / port / ModeStack）直接 play 时也进入壳模式
	if not _cutscene_active:
		_enter_cutscene_mode()
		if str(cutscene_id) != "":
			log_event("【过场】%s\n" % cutscene_id)


func _rebind_cutscene_consumers() -> void:
	if _cutscene == null or not is_instance_valid(_cutscene):
		return
	if GameState.has_method("bind_ending_resolver"):
		GameState.bind_ending_resolver(_cutscene)
	var scheduler = GameState.get("calendar_scheduler")
	if scheduler != null and scheduler.has_method("bind_calendar"):
		scheduler.bind_calendar(GameState.calendar, GameState, {
			"cutscene_player": _cutscene,
		})


func _enter_cutscene_mode() -> void:
	if _mode == ModeStackScript.MODE_CUTSCENE:
		return
	_mode_before_cutscene = _mode
	if _mode_before_cutscene == "" or _mode_before_cutscene == ModeStackScript.MODE_CUTSCENE:
		if _voyage != null and is_instance_valid(_voyage):
			_mode_before_cutscene = ModeStackScript.MODE_VOYAGE
		else:
			_mode_before_cutscene = ModeStackScript.MODE_NARRATIVE
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.process_mode = Node.PROCESS_MODE_DISABLED
	_cutscene_active = true
	_mode = ModeStackScript.MODE_CUTSCENE
	_raise_shell_overlays()


func _on_cutscene_finished(cutscene_id: String) -> void:
	if not _cutscene_active:
		# 仍可能串播下一段；若已通关且空闲则尝试结算
		call_deferred("_maybe_show_ending_settlement")
		return
	if str(cutscene_id) != "":
		log_event("【过场】结束：%s\n" % cutscene_id)
	else:
		log_event("【过场】结束。\n")
	_restore_after_cutscene()
	# 结局 CG 结束（或章三+结局队列清空）→ 结算屏
	call_deferred("_maybe_show_ending_settlement")


func _on_ending_resolved(result: Dictionary) -> void:
	if result is Dictionary and not result.is_empty():
		log_event("【终章】%s\n" % str(result.get("title", result.get("ending_id", "通关"))))
	# 无过场或过场未入队时直接尝试结算
	call_deferred("_maybe_show_ending_settlement")


func _maybe_show_ending_settlement() -> void:
	if _ending_settlement_shown:
		return
	if not GameState.has_story_flag("game_completed"):
		return
	# 过场仍在播（章三收束 → 结局串播）则等
	if _cutscene != null and is_instance_valid(_cutscene) and _cutscene.has_method("is_playing"):
		if bool(_cutscene.call("is_playing")):
			return
	show_ending_settlement()


func show_ending_settlement(display: Dictionary = {}) -> void:
	if _ending_settlement_shown and _ending_settlement != null and is_instance_valid(_ending_settlement):
		return
	var data: Dictionary = display
	if data.is_empty() and GameState.has_method("build_ending_display"):
		data = GameState.build_ending_display()
	if data.is_empty() and GameState.ending_resolver != null and GameState.ending_resolver.has_method("get_last_result"):
		data = GameState.ending_resolver.get_last_result()
	if _ending_settlement == null or not is_instance_valid(_ending_settlement):
		_ending_settlement = EndingSettlementScript.new() as CanvasLayer
		_ending_settlement.name = "EndingSettlement"
		add_child(_ending_settlement)
		if _ending_settlement.has_signal("closed"):
			_ending_settlement.closed.connect(_on_ending_settlement_closed)
	_ending_settlement_shown = true
	if _ending_settlement.has_method("present"):
		_ending_settlement.call("present", data)
	# 结算压在最上层
	move_child(_ending_settlement, get_child_count() - 1)
	log_event("【终章】航程已结，可回标题或再启新航。\n")


func _on_ending_settlement_closed(action: String) -> void:
	match action:
		"return_title":
			_dismiss_ending_settlement()
			_return_to_title(false)
		"new_run":
			_dismiss_ending_settlement()
			if GameState.has_method("begin_new_run"):
				GameState.begin_new_run()
			_ending_settlement_shown = false
			_return_to_title(true)
		"save":
			if SaveManager.has_method("quick_save"):
				SaveManager.quick_save()
			log_event("【存档】终局进度已保存。\n")
		_:
			_dismiss_ending_settlement()


func _dismiss_ending_settlement() -> void:
	if _ending_settlement != null and is_instance_valid(_ending_settlement):
		_ending_settlement.queue_free()
		_ending_settlement = null


func _return_to_title(from_new_run: bool) -> void:
	show_narrative("cg_title")
	if from_new_run:
		_ending_settlement_shown = false


func _restore_after_cutscene() -> void:
	if not _cutscene_active:
		return
	_cutscene_active = false
	# 战斗进行中则保持 combat 暂停逻辑，不抢回 voyage process
	if _combat_active:
		_mode = ModeStackScript.MODE_COMBAT
		_mode_before_cutscene = ""
		return
	if _voyage != null and is_instance_valid(_voyage):
		_voyage.process_mode = Node.PROCESS_MODE_INHERIT
	if _mode_before_cutscene != "":
		_mode = _mode_before_cutscene
	elif _voyage != null and is_instance_valid(_voyage):
		_mode = ModeStackScript.MODE_VOYAGE
	else:
		_mode = ModeStackScript.MODE_NARRATIVE
	_mode_before_cutscene = ""
	refresh_chrome()


func _raise_shell_overlays() -> void:
	if _chrome_layer != null and is_instance_valid(_chrome_layer):
		move_child(_chrome_layer, get_child_count() - 1)
	if _cutscene != null and is_instance_valid(_cutscene):
		move_child(_cutscene, get_child_count() - 1)


func _ensure_chrome_layer() -> void:
	if _chrome_layer != null and is_instance_valid(_chrome_layer):
		return
	_chrome_layer = CanvasLayer.new()
	_chrome_layer.name = "ChromeLayer"
	_chrome_layer.layer = 90
	add_child(_chrome_layer)


func _find_status_bar() -> Control:
	if _narrative == null or not is_instance_valid(_narrative):
		return null
	return _narrative.get_node_or_null("StatusLayer/PortStatusBar") as Control


func _lift_status_bar() -> void:
	_ensure_chrome_layer()
	if _lifted_status != null and is_instance_valid(_lifted_status):
		return
	var bar := _find_status_bar()
	if bar == null:
		return
	_status_home = bar.get_parent()
	if _status_home == null:
		return
	_status_home.remove_child(bar)
	_chrome_layer.add_child(bar)
	_lifted_status = bar
	bar.visible = true


func _restore_status_bar() -> void:
	if _lifted_status == null or not is_instance_valid(_lifted_status):
		_lifted_status = null
		_status_home = null
		return
	var bar := _lifted_status
	var parent := bar.get_parent()
	if parent != null:
		parent.remove_child(bar)
	if _status_home != null and is_instance_valid(_status_home):
		_status_home.add_child(bar)
	_lifted_status = null
	_status_home = null


func _set_status_sea_mode(on: bool) -> void:
	var bar := get_status_bar()
	if bar != null and bar.has_method("set_sea_mode"):
		bar.call("set_sea_mode", on)
