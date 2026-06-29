class_name ChoiceHandler extends Node

## 选择支子控制器
## 负责 choice 选项生成、分支跳转、随机骰子、特殊动作。
## 从 InvestigationController 提取，通过信号通信。

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)

var dialogue_box: Control
var _choices_container: VBoxContainer
var _choices_label: Label

func bind_ui(choices_container: VBoxContainer, choices_label: Label) -> void:
	_choices_container = choices_container
	_choices_label = choices_label

func bind_dialogue_box(box: Control) -> void:
	dialogue_box = box

## ── 选择支可用性 ──────────────────────────────────────────

func _choice_available(choice: Dictionary) -> bool:
	var req: String = choice.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = choice.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	var req_item: String = choice.get("requires_item", "")
	if req_item != "" and not GameState.has_item_flag(req_item):
		return false
	return true

## ── 选择支显示 ────────────────────────────────────────────

func show_choices(choices: Array) -> void:
	var added := 0
	for choice in choices:
		if not _choice_available(choice):
			continue
		if added == 0:
			_choices_label.visible = true
		var btn = UIBuilder.make_choice_button(choice.get("label", "继续"))
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		_choices_container.add_child(btn)
		added += 1
	if added == 0:
		_choices_label.visible = false

## ── 选择支处理 ────────────────────────────────────────────

func _on_choice_pressed(choice_data: Dictionary) -> void:
	if GameManager.input_locked:
		return
	_lock_cb.call(true)
	if choice_data.has("random_roll"):
		await _resolve_random_roll_choice(choice_data)
		_lock_cb.call(false)
		return
	_apply_effects_cb.call(choice_data.get("effects", {}))
	if choice_data.has("narration") and choice_data.get("narration", "") != "":
		var beat := DialogueParser.beat_from_text(choice_data.get("narration", ""))
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not _is_valid():
			return

	if choice_data.has("special_action"):
		_handle_special_action(choice_data.get("special_action"))
		_lock_cb.call(false)
		return

	var next_scene = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameManager.get_port_scene_id(GameState.last_port)
	if next_scene != "":
		_lock_cb.call(false)
		scene_requested.emit(next_scene)
	else:
		_lock_cb.call(false)

## ── 特殊动作 ──────────────────────────────────────────────

func _handle_special_action(action: String) -> void:
	if action == "sail_world_map":
		scene_requested.emit("world_map")
		return
	if action == "bribe_customs":
		var res = GameState.customs_inspection()
		message_logged.emit(res["msg"] + "\n\n")
		status_updated.emit()
		return
	if action == "recruit_crew":
		var result := IntentResolver.resolve(Intent.new(
			IntentTypes.HIRE_CREW, "player", "shipyard",
			{"cost_per_crew": 10, "recruit_max": true},
			{"port_id": GameState.last_port}
		))
		if result.success:
			message_logged.emit("招募了 %d 名水手！\n\n" % int(result.data.get("crew_count", 0)))
			status_updated.emit()
		else:
			message_logged.emit("无法招募！钱不够或船只已满员。\n\n")
		return
	if action == "supply_ship":
		var result := IntentResolver.resolve(Intent.new(
			IntentTypes.BUY_SUPPLIES, "player", "shipyard",
			{"supply_type": "food_water", "total_cost": 20, "fill_to_max": true},
			{"port_id": GameState.last_port}
		))
		if result.success:
			message_logged.emit("水粮已全部补满！\n\n")
			status_updated.emit()
		else:
			message_logged.emit("【补充失败】金钱不足 20！\n\n")
		return
	var res = GameState.handle_special_action(action)
	message_logged.emit(res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()

## ── 随机骰子 ──────────────────────────────────────────────

func _resolve_random_roll_choice(choice_data: Dictionary) -> void:
	var roll_cfg: Dictionary = choice_data.get("random_roll", {})
	var chance: float = float(roll_cfg.get("chance", 0.1))
	_apply_effects_cb.call(choice_data.get("effects", {}))
	var success := randf() < chance
	var branch_key := "success" if success else "fail"
	var branch: Dictionary = roll_cfg.get(branch_key, {})
	_apply_effects_cb.call(branch.get("effects", {}))
	var narr: String = branch.get("narration", "")
	if narr == "":
		narr = choice_data.get("narration", "")
	if narr != "":
		var beat := DialogueParser.beat_from_text(narr)
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not _is_valid():
			return
	var next_scene: String = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameManager.get_port_scene_id(GameState.last_port)
	if next_scene != "":
		scene_requested.emit(next_scene)

## ── 回调注入（由 InvestigationController 设置）────────────

var _apply_effects_cb: Callable
var _lock_cb: Callable

func set_callbacks(apply_effects: Callable, lock: Callable) -> void:
	_apply_effects_cb = apply_effects
	_lock_cb = lock

func _is_valid() -> bool:
	return is_instance_valid(self) and dialogue_box != null and is_instance_valid(dialogue_box)
