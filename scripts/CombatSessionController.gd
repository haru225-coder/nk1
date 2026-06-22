extends CanvasLayer
class_name CombatSessionController

## ═══════════════════════════════════════════════════════════
## CombatSessionController — 海战多回合 UI 控制器
## 复用 SeaEventController 的视觉语言，支持战术选择多轮刷新。
## ═══════════════════════════════════════════════════════════

signal combat_finished(result: Dictionary)

const _THEME_PATH := "res://assets/main_theme.tres"
const _FRAME_PATH := "res://assets/ui_frame_koei.png"
const _GRADIENT_SHADER := "res://assets/ui_bottom_gradient.gdshader"

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
		mat.set_shader_parameter("top_color", Color(0.02, 0.02, 0.03, 0.72))
		mat.set_shader_parameter("bottom_color", Color(0.01, 0.01, 0.02, 0.88))
		dim.material = mat
	else:
		dim.color = Color(0.02, 0.02, 0.02, 0.82)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	# 战斗专用面板稍大：800×540
	var frame := NinePatchRect.new()
	frame.custom_minimum_size = Vector2(800, 540)
	frame.texture = frame_tex
	frame.patch_margin_left = 100
	frame.patch_margin_top = 56
	frame.patch_margin_right = 100
	frame.patch_margin_bottom = 56
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
	inner.theme_type_variation = "DialoguePanelInner"
	margin.add_child(inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	inner.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.theme = _game_theme
	_title_label.theme_type_variation = "EventTitle"
	vbox.add_child(_title_label)

	# 双方状态条（HP / Crew）
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(700, 0)
	_status_label.theme = _game_theme
	_status_label.theme_type_variation = "EventBody"
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
	_body_label.theme_type_variation = "EventBody"
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
	_body_label.text = "[color=#c0a060]【接敌！】%s 出现在视野中，距离尚远。[/color]" % combat.enemy_name
	_show_tactic_buttons()

## ── 状态条刷新 ───────────────────────────────────────────

func _format_fleet(fleet: FleetState) -> String:
	var lines: PackedStringArray = []
	for s in fleet.ships:
		if s.hp > 0:
			lines.append("  [b]%s[/b] 耐久%d/%d (%d%%) 水手%d/%d" % [s.name, int(s.hp), int(s.max_hp), int(s.hp / s.max_hp * 100) if s.max_hp > 0 else 0, s.crew, s.max_crew])
		else:
			lines.append("  [color=#ff4444][b]%s[/b] (沉没)[/color]" % s.name)
	return "\n".join(lines)

func _refresh_status() -> void:
	_status_label.text = (
		"[color=#66ccff]【我方舰队】[/color]\n" + _format_fleet(combat.player_fleet) + "\n" +
		"[color=#ff6666]【%s】[/color]\n" % combat.enemy_name + _format_fleet(combat.enemy_fleet) +
		"\n[color=#808080]当前阶段：%s[/color]" % combat.get_phase_label()
	)

## ── 战术按钮 ─────────────────────────────────────────────

func _show_tactic_buttons() -> void:
	_clear_actions()

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

	# 追加播报
	var narration: String = result.get("narration", "")
	if narration != "":
		_body_label.text += "\n\n[color=#e0d0a0]── 第 %d 回合 ──[/color]\n%s" % [
			result.get("round", 0), narration
		]
	# 自动滚动到底部
	_body_label.scroll_to_line(_body_label.get_line_count())

	_refresh_status()

	# 判断是否结束
	if result.get("is_over", false):
		_on_combat_over(result)
	else:
		# 延迟一小段时间后刷新按钮，避免太快
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(_root):
			_show_tactic_buttons()

## ── 战斗结束 ─────────────────────────────────────────────

func _on_combat_over(result: Dictionary) -> void:
	_clear_actions()

	var victory_narration := combat.get_victory_narration()
	_body_label.text += "\n\n[color=#ffd700]%s[/color]" % victory_narration
	_body_label.scroll_to_line(_body_label.get_line_count())

	# 决定按钮文字
	var button_text := "确认"
	var victory_type: int = result.get("victory_type", 0)
	if victory_type == CombatState.VictoryType.SUNK or victory_type == CombatState.VictoryType.CAPTURED or victory_type == CombatState.VictoryType.DUEL_VICTORY:
		button_text = "搜刮战利品"

	var btn := _make_button(button_text, func():
		combat_finished.emit(result)
		_close_modal()
	, false)
	_actions.add_child(btn)

## ── 工具方法 ─────────────────────────────────────────────

func _make_button(text: String, callback: Callable, highlight: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 46)
	btn.theme = _game_theme
	btn.theme_type_variation = "SetSailButton" if highlight else "ChoiceButton"
	btn.pressed.connect(callback)
	return btn

func _clear_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()

func _close_modal() -> void:
	if not is_instance_valid(_root):
		combat_finished.emit({})
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func():
		queue_free()
	)

## ── 静态入口（与 SeaEventController.trigger_event 对齐）──

static func start_combat(parent_node: Node, enemy: Dictionary) -> CombatSessionController:
	var ctrl := CombatSessionController.new()
	ctrl.enemy_data = enemy
	parent_node.add_child(ctrl)
	return ctrl
