extends Control

## ═══════════════════════════════════════════════════════════
## FacilityController — InvestigationMode 场景节点拥有者（门面）
## ═══════════════════════════════════════════════════════════
## 仅保留场景节点绑定、信号声明、对话框绑定。
## 所有调查/市场/船坞/酒馆/选择支逻辑委托给 InvestigationController。
## Main.gd 连接本节点的信号，无需改动。

signal scene_requested(scene_id: String)
signal status_updated
signal show_npc_requested(npc_id: String, fallback_name: String)
signal message_logged(msg: String)

@onready var scene_title: Label = $MarginContainer/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $MarginContainer/VBoxContainer/BodyText
@onready var interactive_container: HFlowContainer = $MarginContainer/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $MarginContainer/VBoxContainer/ChoicesLabel
@onready var interactive_label: Label = $MarginContainer/VBoxContainer/InteractiveLabel
@onready var city_nav_panel: PanelContainer = $MarginContainer/VBoxContainer/CityNavPanel
@onready var city_nav_label: Label = $MarginContainer/VBoxContainer/CityNavPanel/CityNavMargin/CityNavVBox/CityNavLabel
@onready var city_nav_flow: HFlowContainer = $MarginContainer/VBoxContainer/CityNavPanel/CityNavMargin/CityNavVBox/CityNavFlow
@onready var content_root: MarginContainer = $MarginContainer

var _investigation: InvestigationController

func _ready() -> void:
	body_text.visible = false
	_investigation = InvestigationController.new()
	add_child(_investigation)
	_investigation.bind_ui(
		scene_title, body_text,
		interactive_container, interactive_label,
		choices_container, choices_label,
		city_nav_panel, city_nav_label, city_nav_flow,
		content_root,
	)
	_investigation.scene_requested.connect(scene_requested.emit)
	_investigation.status_updated.connect(status_updated.emit)
	_investigation.message_logged.connect(message_logged.emit)
	_investigation.show_npc_requested.connect(show_npc_requested.emit)

func bind_dialogue_box(box: Control) -> void:
	_investigation.bind_dialogue_box(box)

func setup_investigation(scene_data: Dictionary, scene_id: String) -> void:
	_investigation.setup_investigation(scene_data, scene_id)

func setup_missing(scene_id: String) -> void:
	_investigation.setup_missing(scene_id)
