extends CanvasLayer
class_name CombatSessionController

## ═══════════════════════════════════════════════════════════
## CombatSessionController — 海战多回合 UI 控制器
## 复用 SeaEventController 的视觉语言，支持战术选择多轮刷新。
## ═══════════════════════════════════════════════════════════

signal combat_finished(result: Dictionary, combat_state: CombatState)

const _THEME_PATH := ResourcePaths.THEME_MAIN
const _FRAME_PATH := ResourcePaths.FRAME_KOEI
const _GRADIENT_SHADER := ResourcePaths.GRADIENT_SHADER
const ModeStackScript := preload(ResourcePaths.SCRIPT_MODE_STACK)

var combat: CombatState
var enemy_data: Dictionary = {}

var _root: Control
var _game_theme: Theme
var _title_label: Label
var _status_label: RichTextLabel   ## 双方 HP/Crew 状态条
var _body_label: RichTextLabel     ## 战斗播报区
var _actions: VBoxContainer        ## 战术按钮区

## ── 生命周期 ─────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_game_theme = load(_THEME_PATH) as Theme
	_build_ui()
	_init_combat()

## ── UI 构建（复用 SeaEventController 视觉语言）────────────

func _build_ui() -> void:
	var frame_tex := load(_FRAME_PATH) as Texture2D
	var gradient_shader := load(_GRADIENT_SHADER) as Shader

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# 暗色遮罩
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

	# 战斗专用面板稍大：800×540
	var frame := NinePatchRect.new()
	frame.custom_minimum_size = Vector2(800, 540)
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
	vbox.add_theme_constant_override("separation", 12)
	inner.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.theme = _game_theme
	_title_label.theme_type_variation = UITheme.TITLE_EVENT
	vbox.add_child(_title_label)

	# 双方状态条（HP / Crew）
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(700, 0)
	_status_label.theme = _game_theme
	_status_label.theme_type_variation = UITheme.BODY_EVENT
	vbox.add_child(_status_label)

	# 分割线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 战斗播报区
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = false
	_body_label.scroll_active = true
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.custom_minimum_size = Vector2(700, 160)
	_body_label.theme = _game_theme
	_body_label.theme_type_variation = UITheme.BODY_EVENT
	vbox.add_child(_body_label)

	# 战术按钮区
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	vbox.add_child(_actions)

	# 淡入
	_root.modulate.a = 0.0
	var enter := _root.create_tween()
	enter.tween_property(_root, "modulate:a", 1.0, 0.22)

## ── 初始化战斗 ───────────────────────────────────────────

func _init_combat() -> void:
	combat = CombatState.new()
	combat.initialize(enemy_data)

	_title_label.text = "⚓ 海战：%s" % combat.enemy_name
	_refresh_status()
	_body_label.text = SeaFeedback.contact_engage_bbcode(combat.enemy_name)
	_show_tactic_buttons()

## ── 状态条刷新 ───────────────────────────────────────────

func _format_fleet(fleet: FleetState, show_hull_detail: bool = false) -> String:
	var lines: PackedStringArray = []
	for s in fleet.ships:
		var detail := ""
		if show_hull_detail:
			detail = ShipSystem.format_combat_ship_detail(s)
			if not detail.is_empty():
				detail += " "
		if s.hp > 0:
			lines.append(
				"  [b]%s[/b] %s耐久%d/%d (%d%%) 水手%d/%d" % [
					s.name,
					detail,
					int(s.hp),
					int(s.max_hp),
					int(s.hp / s.max_hp * 100) if s.max_hp > 0 else 0,
					s.crew,
					s.max_crew,
				]
			)
		else:
			lines.append("  [color=#ff4444][b]%s[/b] (沉没)[/color]" % s.name)
	return "\n".join(lines)

func _refresh_status() -> void:
	var extra := ""
	if combat.phase == CombatState.Phase.DUEL:
		extra = "气力 %d/%d · 决斗第 %d/%d 招" % [
			combat.ki_points,
			CombatState.DUEL_KI_MAX,
			combat.duel_action_round,
			CombatState.DUEL_ROUNDS,
		]
	var phase_line := SeaFeedback.phase_status_bbcode(combat.get_phase_label(), extra)
	_status_label.text = (
		"[color=%s]【我方舰队】[/color]\n" % SeaFeedback.COLOR_PLAYER + _format_fleet(combat.player_fleet, true) + "\n" +
		"[color=%s]【%s】[/color]\n" % [SeaFeedback.COLOR_ENEMY, combat.enemy_name] + _format_fleet(combat.enemy_fleet) +
		"\n" + phase_line
	)

## ── 战术按钮 ─────────────────────────────────────────────

func _show_tactic_buttons() -> void:
	_clear_actions()

	if combat.phase == CombatState.Phase.DUEL:
		_show_duel_action_buttons()
		return

	var tactics := combat.get_available_tactics()
	for tactic in tactics:
		var label := CombatState.get_tactic_name(tactic)
		# 接舷阶段的单挑需要高亮
		var is_highlight := tactic == CombatState.Tactic.DUEL
		var btn := _make_button(label, _on_tactic_chosen.bind(tactic), is_highlight)
		# 撤退按钮降低视觉权重
		if tactic == CombatState.Tactic.FLEE:
			btn.modulate = Color(0.7, 0.7, 0.7)
		_actions.add_child(btn)

func _show_duel_action_buttons() -> void:
	_clear_actions()

	for action in combat.get_available_duel_actions():
		var label := CombatState.get_duel_action_name(action)
		var is_special := action == CombatState.DuelAction.SPECIAL
		if is_special:
			label = "必杀 (%d/%d 气力)" % [combat.ki_points, CombatState.DUEL_KI_SPECIAL_COST]
		var btn := _make_button(label, _on_duel_action_chosen.bind(action), is_special)
		if is_special and not combat.can_use_duel_special(true):
			btn.disabled = true
			btn.modulate = Color(0.55, 0.55, 0.55)
		_actions.add_child(btn)

func _on_duel_action_chosen(action: CombatState.DuelAction) -> void:
	if not is_instance_valid(_root):
		return
	if action == CombatState.DuelAction.SPECIAL and not combat.can_use_duel_special(true):
		return

	for child in _actions.get_children():
		if child is Button:
			child.disabled = true

	var enemy_action := combat.choose_enemy_duel_action()
	var result := combat.execute_duel_action(action, enemy_action)
	_append_round_narration(result, "决斗")

	_refresh_status()

	if result.get("is_over", false):
		_on_combat_over(result)
	else:
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(_root):
			_show_duel_action_buttons()

func _on_tactic_chosen(tactic: CombatState.Tactic) -> void:
	if not is_instance_valid(_root):
		return

	# 禁用按钮防止双击
	for child in _actions.get_children():
		if child is Button:
			child.disabled = true

	# 敌方 AI 自动选择
	var enemy_tactic := combat.choose_enemy_tactic()

	# 执行回合结算
	var result := combat.execute_round(tactic, enemy_tactic)
	_append_round_narration(result, "回合")

	_refresh_status()

	if result.get("is_over", false):
		_on_combat_over(result)
	else:
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(_root):
			_show_tactic_buttons()

func _append_round_narration(result: Dictionary, label: String) -> void:
	var narration: String = result.get("narration", "")
	if narration == "":
		return
	_body_label.text += "\n\n%s\n%s" % [
		SeaFeedback.round_header_bbcode(int(result.get("round", 0)), label),
		narration,
	]
	_body_label.scroll_to_line(_body_label.get_line_count())

## ── 战斗结束 ─────────────────────────────────────────────

func _on_combat_over(result: Dictionary) -> void:
	_clear_actions()

	var victory_narration := combat.get_victory_narration()
	_body_label.text += "\n\n" + SeaFeedback.victory_bbcode(victory_narration)
	_body_label.scroll_to_line(_body_label.get_line_count())

	# 决定按钮文字
	var button_text := "确认"
	var victory_type: int = result.get("victory_type", 0)
	if SeaFeedback.is_player_victory(victory_type) and victory_type != SeaFeedback.VT_FLED:
		button_text = "搜刮战利品"
	elif victory_type == SeaFeedback.VT_FLED:
		button_text = "收帆回航"
	elif victory_type == SeaFeedback.VT_DEFEATED_SUNK or victory_type == SeaFeedback.VT_DEFEATED_CAPTURED:
		button_text = "残局收束"

	var btn := _make_button(button_text, func():
		combat_finished.emit(result, combat)
		_close_modal()
	, false)
	_actions.add_child(btn)

## ── 工具方法 ─────────────────────────────────────────────

func _make_button(text: String, callback: Callable, highlight: bool) -> Button:
	var theme_var = UITheme.BTN_SET_SAIL if highlight else UITheme.BTN_CHOICE
	var btn := UIBuilder.make_button(text, theme_var, 46)
	btn.theme = _game_theme
	btn.pressed.connect(callback)
	return btn

func _clear_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()

func _close_modal() -> void:
	if not is_instance_valid(_root):
		combat_finished.emit({}, null)
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func():
		queue_free()
	)

## ── 静态入口（与 SeaEventController.trigger_event 对齐）──
## P8-3: 优先挂到 AppRoot（ModeStack），避免战斗 UI 挂在 WorldMap 子树。

static func start_combat(parent_node: Node, enemy: Dictionary) -> CombatSessionController:
	if parent_node != null:
		var tree := parent_node.get_tree()
		if tree != null:
			var host := ModeStackScript.find_host(tree)
			# host != parent_node：避免 AppRoot.show_combat 内递归
			if host != null and host != parent_node and host.has_method("show_combat"):
				var mounted = host.call("show_combat", enemy)
				if mounted is CombatSessionController:
					return mounted as CombatSessionController
	var ctrl := CombatSessionController.new()
	ctrl.enemy_data = enemy
	if parent_node != null:
		parent_node.add_child(ctrl)
	return ctrl
