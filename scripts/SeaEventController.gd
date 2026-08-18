extends CanvasLayer
class_name SeaEventController

signal event_finished

const _THEME_PATH := ResourcePaths.THEME_MAIN
const _FRAME_PATH := ResourcePaths.FRAME_KOEI
const _GRADIENT_SHADER := ResourcePaths.GRADIENT_SHADER

var event_data: Dictionary = {}
var title_label: Label
var body_label: RichTextLabel
var _actions: VBoxContainer
var _root: Control
var _game_theme: Theme
var _pending_enemy_data: Dictionary = {}  ## 战斗结束后用于结算
var _pending_combat_state: CombatState = null  ## 战斗结束后用于结算
var _loot_resolved := false  ## 防止 combat_finished 连发导致战利品结算两次
var _choice_resolved := false  ## 防止连点两个选项或同一选项结算两次

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_game_theme = load(_THEME_PATH) as Theme
	var frame_tex := load(_FRAME_PATH) as Texture2D
	var gradient_shader := load(_GRADIENT_SHADER) as Shader

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gradient_shader:
		var mat := ShaderMaterial.new()
		mat.shader = gradient_shader
		mat.set_shader_parameter("top_color", GameColors.MODAL_TOP)
		mat.set_shader_parameter("bottom_color", GameColors.MODAL_BOTTOM)
		dim.material = mat
	else:
		dim.color = GameColors.MODAL_DIM
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var frame := NinePatchRect.new()
	frame.custom_minimum_size = Vector2(700, 460)
	frame.texture = frame_tex
	frame.patch_margin_left = 40
	frame.patch_margin_top = 40
	frame.patch_margin_right = 40
	frame.patch_margin_bottom = 40
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	frame.add_child(margin)

	var inner := PanelContainer.new()
	inner.theme = _game_theme
	inner.theme_type_variation = UITheme.PANEL_DIALOGUE_INNER
	margin.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	inner.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.theme = _game_theme
	title_label.theme_type_variation = UITheme.TITLE_EVENT
	vbox.add_child(title_label)

	body_label = RichTextLabel.new()
	body_label.bbcode_enabled = true
	body_label.fit_content = false
	body_label.scroll_active = true
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_label.custom_minimum_size = Vector2(580, 140)
	body_label.theme = _game_theme
	body_label.theme_type_variation = UITheme.BODY_EVENT
	vbox.add_child(body_label)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	vbox.add_child(_actions)

	_root.modulate.a = 0.0
	var enter := _root.create_tween()
	enter.tween_property(_root, "modulate:a", 1.0, 0.22)

	_populate_ui()

func _populate_ui() -> void:
	if event_data.is_empty():
		return

	title_label.text = event_data.get("title", "未知遭遇")
	body_label.text = event_data.get("body", "")
	SeaFeedback.push_shell(SeaFeedback.event_open_log(title_label.text))

	for child in _actions.get_children():
		child.queue_free()

	var choices: Array = event_data.get("choices", [])
	if choices.is_empty():
		_actions.add_child(_make_choice_button("继续", func(): _on_choice_made({})))
	else:
		for choice in choices:
			var label_text: String = choice.get("label", "...")
			var btn := _make_choice_button(label_text, _on_choice_made.bind(choice))
			if choice.has("req_flag") and not FleetArchetypes.check_req_flag(choice["req_flag"]):
				btn.disabled = true
				btn.tooltip_text = "条件不足"
			_actions.add_child(btn)

func _make_choice_button(text: String, callback: Callable) -> Button:
	var btn := UIBuilder.make_button(text, UITheme.BTN_CHOICE, 46)
	btn.theme = _game_theme
	btn.pressed.connect(callback)
	return btn

func _disable_action_buttons() -> void:
	if _actions == null:
		return
	for child in _actions.get_children():
		if child is Button:
			child.disabled = true

func _on_choice_made(choice: Dictionary) -> void:
	if _choice_resolved:
		return
	if choice.has("req_flag") and not FleetArchetypes.check_req_flag(choice["req_flag"]):
		_show_result(choice.get("msg_fail", "条件不足，无法执行此选项。"))
		return
	_choice_resolved = true
	_disable_action_buttons()

	# ── FleetArchetypes 战斗路由：通过 Intent 管道 ──
	if choice.has("launch_combat") and choice["launch_combat"]:
		var enemy_data: Dictionary = choice.get("combat_enemy", {})
		var intent := Intent.new(IntentTypes.COMBAT_REQUEST, "player_fleet", "enemy_fleet",
			{"combat_enemy": enemy_data})
		var result := IntentResolver.resolve(intent)
		if result.success:
			_launch_combat_from_result(result)
		else:
			_show_result("战斗启动失败：" + result.message)
		return

	if choice.has("success_chance"):
		var success := randf() < float(choice.get("success_chance", 1.0))
		var msg: String = choice.get("msg_ok", "") if success else choice.get("msg_fail", "")
		var effects: Dictionary = choice.get("effects_ok", {}) if success else choice.get("effects_fail", {})
		_apply_choice_effects(effects)
		_show_result(msg if msg != "" else ("行动成功。" if success else "行动失败。"))
		return

	if choice.has("intent_struct"):
		var istruct: Dictionary = choice["intent_struct"]
		var intent_type: String = istruct.get("type", IntentTypes.IGNORE)

		# ── 战斗请求：通过 Intent 管道 → CombatHandler ──
		if intent_type == IntentTypes.COMBAT_REQUEST:
			var combat_intent := Intent.new(
				intent_type,
				istruct.get("source", "player_fleet"),
				istruct.get("target", "unknown_fleet"),
				istruct.get("parameters", {}),
				istruct.get("context", {})
			)
			var combat_result := IntentResolver.resolve(combat_intent)
			if combat_result.success:
				_launch_combat_from_result(combat_result)
			else:
				_show_result("战斗启动失败：" + combat_result.message)
			return

		var intent := Intent.new(
			intent_type,
			istruct.get("source", "player_fleet"),
			istruct.get("target", "unknown_fleet"),
			istruct.get("parameters", {}),
			istruct.get("context", {})
		)
		var result = IntentResolver.process(intent)
		if result == null:
			_show_result("意图解析失败：未知行为。")
			return
		_show_result(_format_intent_result(intent_type, result, istruct))
		return
	elif choice.has("effects"):
		_apply_choice_effects(choice["effects"])
		var msg: String = str(choice.get("msg_ok", choice.get("msg", "")))
		if msg != "":
			_show_result(msg)
			return
	elif choice.has("special_action"):
		var res := GameState.handle_special_action(choice.get("special_action", ""))
		if not res.get("msg", "").is_empty():
			_show_result(res["msg"])
			return

	_close_modal()

func _apply_choice_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	if effects.has("special_action"):
		GameState.handle_special_action(str(effects["special_action"]))
	var stat_effects := effects.duplicate()
	stat_effects.erase("special_action")
	if not stat_effects.is_empty():
		GameState.apply_effects(stat_effects)

func _format_intent_result(intent_type: String, result: IntentResult, istruct: Dictionary) -> String:
	if intent_type == IntentTypes.TRADE_REQUEST:
		if result.success:
			var params: Dictionary = istruct.get("parameters", {})
			return "交易成功！花费 %d 钱，获得食物 %d、淡水 %d。" % [
				int(params.get("cost", 0)), int(params.get("food", 0)), int(params.get("water", 0))
			]
		return "金钱不足，无法交易。"
	var txt := GameManager.get_text(result.message_key, "")
	if txt != "":
		return txt
	return "行动完成。" if result.success else "行动失败，条件不足。"

func _show_result(msg: String) -> void:
	body_label.text += "\n\n" + msg
	SeaFeedback.push_shell(SeaFeedback.event_result_log(title_label.text if title_label else "", msg))
	for child in _actions.get_children():
		if child is Button:
			child.queue_free()
	_actions.add_child(_make_choice_button("确认", _close_modal))

## ── 战斗移交 ─────────────────────────────────────────────
## 从 IntentResult 中读取 combat_state + enemy_data，启动 CombatSessionController。
func _launch_combat_from_result(result: IntentResult) -> void:
	var parent := get_parent()
	var data: Dictionary = result.data
	_pending_enemy_data = data.get("enemy_data", {})
	_pending_combat_state = data.get("combat_state", null)
	var enemy_name := str(_pending_enemy_data.get("name", _pending_enemy_data.get("id", "敌舰")))
	SeaFeedback.push_shell(SeaFeedback.event_to_combat_log(enemy_name))

	# 立即隐藏当前模态，避免叠影
	if is_instance_valid(_root):
		_root.visible = false

	var ctrl := CombatSessionController.start_combat(parent, _pending_enemy_data)
	ctrl.combat_finished.connect(_on_combat_over)

func _on_combat_over(result: Dictionary, combat_state: CombatState = null) -> void:
	if _loot_resolved:
		return
	_loot_resolved = true
	if result.is_empty():
		# 战斗被取消（如 UI 关闭）
		event_finished.emit()
		queue_free()
		return
	# 使用 CombatHandler 统一结算（战利品 + 惩罚）
	var actual_state := combat_state if combat_state != null else _pending_combat_state
	if actual_state != null:
		CombatHandler.resolve_combat_result(actual_state, _pending_enemy_data)
	# 关闭本 SeaEvent
	event_finished.emit()
	queue_free()

func _close_modal() -> void:
	if not is_instance_valid(_root):
		event_finished.emit()
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func():
		event_finished.emit()
		queue_free()
	)

static func trigger_event(parent_node: Node, data: Dictionary) -> SeaEventController:
	var controller := SeaEventController.new()
	controller.event_data = data
	parent_node.add_child(controller)
	return controller