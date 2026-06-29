class_name InvestigationController extends Node

## 调查模式子控制器（领域编排者）
## 负责设施内对话流程、调查点、NPC 遭遇、城市导航。
## 选择支逻辑委托给 ChoiceHandler。
## 市场/船坞/酒馆场景由本控制器直接挂载对应领域子控制器。
## 由 FacilityController（场景节点拥有者）创建并注入 UI 引用。

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)
signal show_npc_requested(npc_id: String, fallback_name: String)

var dialogue_box: Control
var _pending_scene_data: Dictionary = {}
var _pending_scene_id: String = ""
var _dialogue_done: bool = false

var _choice_handler: ChoiceHandler
var _market_ctrl: PortMarketController
var _shipyard_ctrl: ShipyardController
var _tavern_ctrl: TavernController

## ── 容器引用（由父控制器传入）────────────────────────────

var _scene_title: Label
var _body_text: RichTextLabel
var _interactive_container: HFlowContainer
var _interactive_label: Label
var _choices_container: VBoxContainer
var _choices_label: Label
var _city_nav_panel: PanelContainer
var _city_nav_label: Label
var _city_nav_flow: HFlowContainer
var _content_root: MarginContainer

func bind_ui(
	scene_title: Label,
	body_text: RichTextLabel,
	interactive_container: HFlowContainer,
	interactive_label: Label,
	choices_container: VBoxContainer,
	choices_label: Label,
	city_nav_panel: PanelContainer,
	city_nav_label: Label,
	city_nav_flow: HFlowContainer,
	content_root: MarginContainer,
) -> void:
	_scene_title = scene_title
	_body_text = body_text
	_interactive_container = interactive_container
	_interactive_label = interactive_label
	_choices_container = choices_container
	_choices_label = choices_label
	_city_nav_panel = city_nav_panel
	_city_nav_label = city_nav_label
	_city_nav_flow = city_nav_flow
	_content_root = content_root
	# 初始化 ChoiceHandler（挂载到场景树）
	_choice_handler = ChoiceHandler.new()
	_choice_handler.name = "ChoiceHandler"
	add_child(_choice_handler)
	_choice_handler.bind_ui(choices_container, choices_label)
	_choice_handler.scene_requested.connect(scene_requested.emit)
	_choice_handler.status_updated.connect(status_updated.emit)
	_choice_handler.message_logged.connect(message_logged.emit)
	_choice_handler.set_callbacks(apply_effects, set_interaction_locked)

func bind_dialogue_box(box: Control) -> void:
	dialogue_box = box
	if dialogue_box == null:
		return
	if not dialogue_box.sequence_finished.is_connected(_on_dialogue_sequence_finished):
		dialogue_box.sequence_finished.connect(_on_dialogue_sequence_finished)
	if dialogue_box.has_signal("active_changed") and not dialogue_box.active_changed.is_connected(_on_dialogue_active_changed):
		dialogue_box.active_changed.connect(_on_dialogue_active_changed)
	if _choice_handler:
		_choice_handler.bind_dialogue_box(box)

func _on_dialogue_active_changed(is_active: bool) -> void:
	var content_target := Color(0.72, 0.72, 0.72, 1.0) if is_active else GameColors.LIGHT_NOON
	var title_alpha := 0.3 if is_active else 1.0
	var bottom_margin := int(GameUILayout.DIALOGUE_BAR_HEIGHT) if is_active else 12
	_content_root.add_theme_constant_override("margin_bottom", bottom_margin)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_content_root, "modulate", content_target, 0.2)
	tween.tween_property(_scene_title, "modulate:a", title_alpha, 0.2)

## ── Investigation 入口 ────────────────────────────────────

func setup_investigation(scene_data: Dictionary, scene_id: String) -> void:
	scene_data = SceneVariantResolver.resolve(scene_data, scene_id)
	_pending_scene_data = scene_data
	_pending_scene_id = scene_id
	_dialogue_done = false
	_scene_title.text = scene_data.get("title", "未命名地点")
	_body_text.text = ""
	hide_post_dialogue_ui()
	clear_containers()
	var beats: Array = DialogueParser.parse_body(scene_data.get("body", ""))
	if beats.is_empty():
		_on_dialogue_sequence_finished()
	else:
		dialogue_box.start_sequence(beats)

func _on_dialogue_sequence_finished() -> void:
	if _dialogue_done or _pending_scene_data.is_empty():
		return
	_dialogue_done = true
	_setup_post_dialogue_content()

## ── 对话后内容构建 ────────────────────────────────────────

func _setup_post_dialogue_content() -> void:
	var scene_data: Dictionary = _pending_scene_data
	clear_containers()
	_setup_city_nav()

	# 调查点
	var investigations = scene_data.get("investigations", [])
	var added_inv := 0
	for inv in investigations:
		if not _investigation_available(inv):
			continue
		if added_inv == 0:
			_interactive_label.visible = true
		var btn = UIBuilder.make_button("★ " + inv.get("label", "互动"), UITheme.BTN_ACTION, 40)
		btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
		_interactive_container.add_child(btn)
		added_inv += 1
	if added_inv == 0:
		_interactive_label.visible = false

	# 挂载领域子控制器（市场/船坞/酒馆）
	_mount_domain_controllers(scene_data)

	# NPC 遭遇
	_add_npc_button_if_needed(scene_data)

	# 选择支（委托给 ChoiceHandler）
	_choice_handler.show_choices(scene_data.get("choices", []))

## ── 领域子控制器挂载 ──────────────────────────────────────
## 根据场景 ID 直接创建对应领域控制器，连接信号，调用 setup。
## 切换场景时由 clear_containers() → _clear_domain_controllers() 清理旧实例。

func _mount_domain_controllers(scene_data: Dictionary) -> void:
	var sid := _pending_scene_id
	var scene_id_val: String = scene_data.get("id", "")

	if sid.ends_with("_market") or scene_id_val == "city_market":
		_market_ctrl = PortMarketController.new()
		_market_ctrl.name = "PortMarketController"
		add_child(_market_ctrl)
		_market_ctrl.message_logged.connect(message_logged.emit)
		_market_ctrl.status_updated.connect(status_updated.emit)
		_market_ctrl.setup(GameState.last_port, _interactive_container, _choices_container, _choices_label)

	elif sid.ends_with("_shipyard") or scene_id_val == "city_shipyard":
		_shipyard_ctrl = ShipyardController.new()
		_shipyard_ctrl.name = "ShipyardController"
		add_child(_shipyard_ctrl)
		_shipyard_ctrl.message_logged.connect(message_logged.emit)
		_shipyard_ctrl.status_updated.connect(status_updated.emit)
		_shipyard_ctrl.scene_requested.connect(scene_requested.emit)
		_shipyard_ctrl.setup(_interactive_container, _choices_container, _choices_label, dialogue_box, sid)

	elif sid.ends_with("_tavern") or scene_id_val.ends_with("_tavern"):
		_tavern_ctrl = TavernController.new()
		_tavern_ctrl.name = "TavernController"
		add_child(_tavern_ctrl)
		_tavern_ctrl.message_logged.connect(message_logged.emit)
		_tavern_ctrl.status_updated.connect(status_updated.emit)
		_tavern_ctrl.setup(_interactive_container, _interactive_label, dialogue_box)

func _clear_domain_controllers() -> void:
	for ctrl in [_market_ctrl, _shipyard_ctrl, _tavern_ctrl]:
		if ctrl != null and is_instance_valid(ctrl):
			ctrl.queue_free()
	_market_ctrl = null
	_shipyard_ctrl = null
	_tavern_ctrl = null

## ── NPC 遭遇 ─────────────────────────────────────────────

func _add_npc_button_if_needed(scene_data: Dictionary) -> void:
	if not scene_data.has("npc_encounter"):
		return
	var npc_id: String = scene_data.get("npc_encounter")
	var npc_name := GameManager.get_npc_name(npc_id)
	var btn = UIBuilder.make_npc_button("【遇见人物】 " + npc_name)
	btn.pressed.connect(func(): show_npc_requested.emit(npc_id, npc_name))
	_choices_container.add_child(btn)

## ── 调查点 ────────────────────────────────────────────────

func _investigation_available(inv: Dictionary) -> bool:
	var once_flag: String = inv.get("once_flag", "")
	if once_flag != "" and GameState.has_story_flag(once_flag):
		return false
	var req: String = inv.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = inv.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	var req_item: String = inv.get("requires_item", "")
	if req_item != "" and not GameState.has_item_flag(req_item):
		return false
	return true

func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	if GameManager.input_locked:
		return
	set_interaction_locked(true)
	var msg = inv_data.get("text", "")
	if msg != "":
		var beat := DialogueParser.beat_from_text(msg)
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not _is_valid():
			return
	var once_flag: String = inv_data.get("once_flag", "")
	if once_flag != "":
		GameState.set_story_flag(once_flag)
	apply_effects(inv_data.get("effects", {}))

	var next_sc = inv_data.get("next", "")
	if next_sc == "last_port":
		next_sc = GameManager.get_port_scene_id(GameState.last_port)
	if next_sc != "":
		set_interaction_locked(false)
		scene_requested.emit(next_sc)
	else:
		btn.disabled = true
		set_interaction_locked(false)

## ── 缺失场景 ──────────────────────────────────────────────

func setup_missing(scene_id: String) -> void:
	clear_containers()
	hide_post_dialogue_ui()
	_dialogue_done = false
	_scene_title.text = "区域施工中..."
	var beat := DialogueParser.beat_from_text(
		"该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"
	)
	dialogue_box.start_sequence([beat])
	_pending_scene_data = {}
	await dialogue_box.sequence_finished
	var btn = UIBuilder.make_button("离开", UITheme.BTN_CHOICE, 44)
	btn.pressed.connect(func(): scene_requested.emit(GameManager.get_port_scene_id(GameState.last_port)))
	_choices_container.add_child(btn)
	_choices_label.visible = true

## ── 城市导航 ──────────────────────────────────────────────

func _setup_city_nav() -> void:
	CityNavBuilder.build(
		_city_nav_panel, _city_nav_label, _city_nav_flow,
		_scene_title, _pending_scene_id,
		scene_requested.emit,
	)

## ── 公共工具 ──────────────────────────────────────────────

func apply_effects(effects: Dictionary) -> void:
	GameState.apply_effects(effects)
	status_updated.emit()

func hide_post_dialogue_ui() -> void:
	_choices_label.visible = false
	_interactive_label.visible = false
	_city_nav_panel.visible = false

func clear_containers() -> void:
	_clear_domain_controllers()
	for child in _interactive_container.get_children():
		child.queue_free()
	for child in _choices_container.get_children():
		child.queue_free()

func set_interaction_locked(locked: bool) -> void:
	GameManager.set_input_locked(locked)
	for container in [_interactive_container, _choices_container]:
		for child in container.get_children():
			if child is BaseButton:
				child.disabled = locked
	for child in _city_nav_flow.get_children():
		if child is BaseButton:
			child.disabled = locked

func _is_valid() -> bool:
	return is_instance_valid(self) and dialogue_box != null and is_instance_valid(dialogue_box)
