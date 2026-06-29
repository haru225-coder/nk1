class_name CityNavBuilder extends RefCounted

## 城市导航面板构建器
## 从 InvestigationController 提取的纯 UI 构建逻辑。

static func build(
	city_nav_panel: PanelContainer,
	city_nav_label: Label,
	city_nav_flow: HFlowContainer,
	scene_title: Label,
	pending_scene_id: String,
	on_navigate: Callable,
) -> void:
	for child in city_nav_flow.get_children():
		child.queue_free()
	var port_id: String = GameState.last_port
	if port_id == "":
		city_nav_panel.visible = false
		return
	if pending_scene_id.begins_with("scene0") or pending_scene_id.begins_with("port_") or pending_scene_id.begins_with("chapter2_") or pending_scene_id == "cg_title":
		city_nav_panel.visible = false
		return
	var port_scene: Dictionary = GameManager.get_scene_by_id(GameManager.get_port_scene_id(port_id))
	var facilities: Array = port_scene.get("facilities", [])
	if facilities.is_empty():
		city_nav_panel.visible = false
		return
	city_nav_panel.visible = true
	city_nav_label.text = "▸ 当前：%s · 可前往" % scene_title.text
	var hub_btn = UIBuilder.make_action_button("🏠 回城关")
	hub_btn.custom_minimum_size = Vector2(128, 44)
	hub_btn.pressed.connect(func():
		on_navigate.call(GameManager.get_port_scene_id(port_id))
	)
	city_nav_flow.add_child(hub_btn)
	for fac in facilities:
		if not GameManager.facility_available(fac):
			continue
		var target: String = GameManager.resolve_facility_scene(fac, port_id)
		if target == pending_scene_id:
			continue
		var nav_btn = UIBuilder.make_choice_button(fac.get("title", "地点"))
		nav_btn.custom_minimum_size = Vector2(112, 44)
		nav_btn.pressed.connect(func():
			on_navigate.call(target)
		)
		city_nav_flow.add_child(nav_btn)
