extends SceneTree

const FAIL := 1
const PASS := 0

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== R1/R3 UI Verification ===")
	_verify_r3_theme()
	_verify_r3_status_bar_scene()
	_verify_r1_main_scene_nodes()
	await _verify_r1_port_grid_runtime()
	_print_summary()
	quit(PASS if _failures.is_empty() else FAIL)

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL: ", msg)

func _pass(msg: String) -> void:
	print("PASS: ", msg)

func _verify_r3_theme() -> void:
	var theme: Theme = load(ResourcePaths.THEME_MAIN)
	if theme == null:
		_fail("main_theme.tres failed to load")
		return

	var panel_style: StyleBox = theme.get_stylebox("panel", "StatusBarPanel")
	if panel_style == null:
		_fail("StatusBarPanel has no panel style")
		return
	if not panel_style is StyleBoxFlat:
		_fail("StatusBarPanel style is not StyleBoxFlat (got %s)" % panel_style.get_class())
		return

	var flat := panel_style as StyleBoxFlat
	var bg := flat.bg_color
	if not _color_close(bg, Color(0.10, 0.07, 0.04, 0.97)):
		_fail("StatusBarPanel bg_color mismatch: %s" % bg)
	else:
		_pass("StatusBarPanel uses wood bg_color")

	if flat.border_width_top != 4:
		_fail("StatusBarPanel border_width_top expected 4, got %d" % flat.border_width_top)
	else:
		_pass("StatusBarPanel has 4px top border")

	var border := flat.border_color
	if not _color_close(border, Color(0.82, 0.62, 0.24, 1.0)):
		_fail("StatusBarPanel border_color mismatch: %s" % border)
	else:
		_pass("StatusBarPanel has gold top border color")

func _verify_r3_status_bar_scene() -> void:
	var scene: PackedScene = load(ResourcePaths.SCENE_PORT_STATUS_BAR)
	if scene == null:
		_fail("PortStatusBar.tscn failed to load")
		return

	var bar: Control = scene.instantiate()
	root.add_child(bar)
	await process_frame
	await process_frame

	if bar.offset_bottom < 88.0:
		_fail("PortStatusBar offset_bottom %.1f < 88" % bar.offset_bottom)
	else:
		_pass("PortStatusBar height %.1f >= 88" % bar.offset_bottom)

	var panel: PanelContainer = bar.get_node_or_null("Panel")
	if panel == null:
		_fail("PortStatusBar missing Panel node")
	elif panel.theme_type_variation != &"StatusBarPanel":
		_fail("PortStatusBar Panel theme_type_variation is %s" % panel.theme_type_variation)
	else:
		_pass("PortStatusBar Panel uses StatusBarPanel variation")

	bar.queue_free()

func _verify_r1_main_scene_nodes() -> void:
	var main_scene: PackedScene = load(ResourcePaths.SCENE_MAIN)
	if main_scene == null:
		_fail("Main.tscn failed to load")
		return

	var main: Node = main_scene.instantiate()
	var grid: Node = main.get_node_or_null(
		"GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode/FacilityHub/Margin/VBox/FacilityGrid"
	)
	if grid == null:
		_fail("FacilityGrid node missing in Main.tscn")
	else:
		_pass("FacilityGrid exists in Main.tscn")

	var scroll: Node = main.get_node_or_null(
		"GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode/FacilityHub/Margin/VBox/Scroll"
	)
	if scroll != null:
		_fail("Legacy Scroll node still present in Main.tscn")

	var flow: Node = main.get_node_or_null(
		"GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode/FacilityHub/Margin/VBox/FacilityGrid/FacilityFlow"
	)
	if flow != null:
		_fail("Legacy FacilityFlow node still present")

	var left: Node = main.get_node_or_null(
		"GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode/FacilityHub/Margin/VBox/FacilityGrid/LeftColumn"
	)
	var right: Node = main.get_node_or_null(
		"GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode/FacilityHub/Margin/VBox/FacilityGrid/RightColumn"
	)
	if left == null or right == null:
		_fail("LeftColumn or RightColumn missing")
	else:
		_pass("LeftColumn and RightColumn exist")

	main.free()

func _verify_r1_port_grid_runtime() -> void:
	var main_scene: PackedScene = load(ResourcePaths.SCENE_MAIN)
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var port_mode: Node = main.get_node_or_null("GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode")
	if port_mode == null:
		_fail("PortMode node missing at runtime")
		main.queue_free()
		return

	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		main.queue_free()
		return
	var scene_data: Dictionary = game_manager.get_scene_by_id("port_xinghua")
	if scene_data.is_empty():
		_fail("port_xinghua scene data empty")
		main.queue_free()
		return
	if not scene_data.get("town_map", {}).is_empty():
		_fail("port_xinghua unexpectedly has town_map — pick a grid-only port")
		main.queue_free()
		return

	port_mode.setup(scene_data, "port_xinghua")
	await process_frame

	var grid: HBoxContainer = port_mode.get_node_or_null("FacilityHub/Margin/VBox/FacilityGrid")
	var left: VBoxContainer = port_mode.get_node_or_null("FacilityHub/Margin/VBox/FacilityGrid/LeftColumn")
	var right: VBoxContainer = port_mode.get_node_or_null("FacilityHub/Margin/VBox/FacilityGrid/RightColumn")
	var hint: Label = port_mode.get_node_or_null("FacilityHub/Margin/VBox/FacilityHint")

	if grid == null or not grid.visible:
		_fail("FacilityGrid not visible after setup")
	else:
		_pass("FacilityGrid visible after port setup")

	if hint and hint.text != "▸ 点击建筑进入地点":
		_fail("FacilityHint text mismatch: %s" % hint.text)
	else:
		_pass("FacilityHint shows building entry text")

	var total_slots := left.get_child_count() + right.get_child_count()
	var facility_count: int = scene_data.get("facilities", []).size()
	if total_slots != facility_count:
		_fail("Grid slots %d != facilities %d" % [total_slots, facility_count])
	else:
		_pass("Grid populated with %d facility slots" % total_slots)

	var has_icon := false
	var has_title := false
	var has_hit_button := false
	for column in [left, right]:
		for child in column.get_children():
			if child is Control:
				has_hit_button = has_hit_button or _node_has_button(child)
				has_icon = has_icon or _node_has_texture_rect(child)
				has_title = has_title or _node_has_facility_title(child)

	if not has_icon:
		_fail("No TextureRect icons found in facility slots")
	else:
		_pass("Facility slots contain icon TextureRects")

	if not has_title:
		_fail("No FacilityTitle labels found in facility slots")
	else:
		_pass("Facility slots contain title labels")

	if not has_hit_button:
		_fail("No hit Button found in facility slots")
	else:
		_pass("Facility slots use hit Button overlay")

	# Verify column assignment: tavern/inn/guild/yamen lean left; market/shipyard/wharf/ruins lean right
	var left_ids: Array[String] = []
	var right_ids: Array[String] = []
	for child in left.get_children():
		left_ids.append(_slot_facility_id(child))
	for child in right.get_children():
		right_ids.append(_slot_facility_id(child))

	for fid in left_ids:
		if _is_right_category(fid):
			_fail("Right-category facility '%s' placed in left column" % fid)
	for fid in right_ids:
		if _is_left_category(fid):
			_fail("Left-category facility '%s' placed in right column" % fid)
	if _failures.is_empty() or not _has_column_assignment_failures():
		_pass("Facility column assignment looks correct (left=%d, right=%d)" % [left_ids.size(), right_ids.size()])

	await _verify_r1_town_map_runtime(port_mode, game_manager)
	main.queue_free()

func _verify_r1_town_map_runtime(port_mode: Node, game_manager: Node) -> void:
	var scene_data: Dictionary = game_manager.get_scene_by_id("port_quanzhou")
	if scene_data.is_empty() or scene_data.get("town_map", {}).is_empty():
		_fail("port_quanzhou town_map data missing")
		return

	port_mode.setup(scene_data, "port_quanzhou")
	await process_frame

	var grid: HBoxContainer = port_mode.get_node_or_null("FacilityHub/Margin/VBox/FacilityGrid")
	var town_map: Node = port_mode.get_node_or_null("FacilityHub/Margin/VBox/TownMapView")
	if grid != null and grid.visible:
		_fail("FacilityGrid visible when port_quanzhou town_map active")
	else:
		_pass("town_map mode hides FacilityGrid for port_quanzhou")
	if town_map != null and town_map.visible:
		_pass("TownMapView visible for port_quanzhou")
	else:
		_fail("TownMapView not visible for port_quanzhou town_map setup")

func _has_column_assignment_failures() -> bool:
	for f in _failures:
		if "column" in f:
			return true
	return false

func _is_left_category(fid: String) -> bool:
	const KEYS := ["tavern", "inn", "guild", "yamen"]
	for key in KEYS:
		if fid.contains(key):
			return true
	return false

func _is_right_category(fid: String) -> bool:
	const KEYS := ["market", "shipyard", "wharf", "ruins"]
	for key in KEYS:
		if fid.contains(key):
			return true
	return false

func _slot_facility_id(slot: Node) -> String:
	for btn in _collect_buttons(slot):
		for conn in btn.get_signal_connection_list("pressed"):
			var binds: Array = conn.get("binds", [])
			if binds.size() > 0 and binds[0] is Dictionary:
				return binds[0].get("id", "")
	return ""

func _collect_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_buttons(child))
	return out

func _node_has_button(node: Node) -> bool:
	if node is Button:
		return true
	for child in node.get_children():
		if _node_has_button(child):
			return true
	return false

func _node_has_texture_rect(node: Node) -> bool:
	if node is TextureRect and node.texture != null:
		return true
	for child in node.get_children():
		if _node_has_texture_rect(child):
			return true
	return false

func _node_has_facility_title(node: Node) -> bool:
	if node is Label and node.theme_type_variation == UITheme.TITLE_FACILITY:
		return true
	for child in node.get_children():
		if _node_has_facility_title(child):
			return true
	return false

func _color_close(a: Color, b: Color, eps: float = 0.001) -> bool:
	return absf(a.r - b.r) <= eps and absf(a.g - b.g) <= eps and absf(a.b - b.b) <= eps and absf(a.a - b.a) <= eps

func _print_summary() -> void:
	print("=== Summary ===")
	if _failures.is_empty():
		print("ALL CHECKS PASSED (%d)" % 8)
	else:
		print("%d FAILURE(S):" % _failures.size())
		for f in _failures:
			print("  - ", f)