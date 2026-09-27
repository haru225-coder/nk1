extends Control
## 人物演示页（chars 线）：一页把「名册 → 人物面板 → 站台」串起来，供巡检截图与人工点看。
## 入口：`godot --path . scenes/chars/CharsDemo.tscn`（或直接 F6 跑本场景）。
## 键位：↑ / ↓ 换人；Tab 切站台档（画屏 / 体量）；← / → 或拖拽转台；Esc 退出。
## 全页只读：不接玩法数值，不写存档；人物数据经 GameManager，文字经 CharacterArt 上屏层。

const Art := preload("res://scripts/ui/CharacterArt.gd")
const Roster := preload("res://scripts/chars/CharRoster.gd")
const Panel3D := preload("res://scripts/chars/CharStage3D.gd")
const PortraitPanel := preload("res://scripts/chars/CharPortraitPanel.gd")

const DEMO_ORDER := ["chen_wenlong", "chen_zan", "merchant_lin", "pilot_ana", "monk_jinghai",
	"huang_quan", "lin_hua", "chen_mother"]

var roster: VBoxContainer
var panel: PanelContainer
var stage: SubViewportContainer
var current_id := ""

var _stage_mode := "screen"
var _status: Label
var _order: Array = []


func _ready() -> void:
	name = "CharsDemo"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build_backdrop()
	_build()
	_build_order()
	_pick(_order[0] if not _order.is_empty() else "")


# ── 建页 ─────────────────────────────────────────────

func _build_backdrop() -> void:
	var bg := TextureRect.new()
	bg.name = "Backdrop"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var path := "res://assets/bg_xinghua_study.jpg"
	if ResourceLoader.exists(path):
		bg.texture = load(path)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.62)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var title := Art.label("人物呈现", 40, UiTheme.GOLD_HI, true)
	title.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var sub := Art.label("名册　面板　站台（画屏 / 体量）", UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var mode_btn := Button.new()
	mode_btn.text = "站台：画屏"
	mode_btn.name = "ModeButton"
	UiTheme.style_chip(mode_btn)
	mode_btn.pressed.connect(_toggle_mode)
	head.add_child(mode_btn)
	var turn_btn := Button.new()
	turn_btn.text = "转台"
	turn_btn.name = "TurnButton"
	UiTheme.style_chip(turn_btn)
	turn_btn.pressed.connect(_turn)
	head.add_child(turn_btn)
	var quit_btn := Button.new()
	quit_btn.text = "退出"
	quit_btn.name = "QuitButton"
	UiTheme.style_chip(quit_btn)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	head.add_child(quit_btn)

	var row := HBoxContainer.new()
	row.name = "Body"
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := PanelContainer.new()
	left.name = "RosterPanel"
	left.add_theme_stylebox_override("panel", UiTheme.panel())
	left.custom_minimum_size.x = 404
	row.add_child(left)
	var lm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		lm.add_theme_constant_override("margin_%s" % side, 12)
	left.add_child(lm)
	roster = Roster.new()
	lm.add_child(roster)
	roster.picked.connect(_pick)

	panel = PortraitPanel.new()
	# name 保留 CharPortraitPanel（_init 已设），供巡检定位
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)

	stage = Panel3D.new()
	row.add_child(stage)

	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_status = Art.label("", UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_status)
	var keys := Art.label("↑↓ 换人　Tab 站台档　←→ 转台　Esc 退出", UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(keys)


## 演示顺序：先按 DEMO_ORDER，缺人就跳过；再补上其余主角・要人，末了补到 20 人以内便于翻看。
func _build_order() -> void:
	var seen: Dictionary = {}
	for id in DEMO_ORDER:
		if not GameManager.get_character(id).is_empty():
			_order.append(id)
			seen[id] = true
	for t in [["protagonist", "major"], ["crew"]]:
		for ch in GameManager.all_characters():
			var id := str(ch.get("id", ""))
			if seen.has(id) or not (str(ch.get("tier", "")) in t):
				continue
			_order.append(id)
			seen[id] = true
	if _order.is_empty():
		for ch in GameManager.all_characters():
			_order.append(str(ch.get("id", "")))


# ── 选人 ─────────────────────────────────────────────

func _pick(id: String) -> void:
	if id == "":
		return
	var ch := GameManager.get_character(id)
	if ch.is_empty():
		return
	var changing := id != current_id
	current_id = id
	panel.show_character(ch)
	if changing:
		stage.show_character(ch)
	else:
		# 同人刷新（切站台档等）：只同步档位，不重跑换人动画
		stage.set_mode(_stage_mode)
	if changing:
		roster.select_id(id)
	_status.text = "%s　%d/%d　　站台：%s" % [
		Art.identity_line(ch), _order.find(id) + 1, _order.size(),
		"体量" if _stage_mode == "volume" else "画屏"]


func current() -> String:
	return current_id


func _step(d: int) -> void:
	if _order.is_empty():
		return
	var i := _order.find(current_id)
	var j := clampi(i + d, 0, _order.size() - 1)
	_pick(str(_order[j]))


func _toggle_mode() -> void:
	_stage_mode = "volume" if _stage_mode == "screen" else "screen"
	stage.set_mode(_stage_mode)
	var b := _find_button("ModeButton")
	if b != null:
		b.text = "站台：体量" if _stage_mode == "volume" else "站台：画屏"
	pick_current()


func _turn() -> void:
	# 巡检用：抬手把转台转到一个固定角度，帧与帧之间可比
	stage.set_yaw(stage.yaw_deg() + 30.0)


func pick_current() -> void:
	_pick(current_id)


func _find_button(node_name: String) -> Button:
	var hit: Array = []
	_collect(node_name, hit)
	return hit[0] if not hit.is_empty() else null


func _collect(node_name: String, out: Array) -> void:
	for c in get_children():
		if c.name == node_name and c is Button:
			out.append(c)
		_collect_children(c, node_name, out)


func _collect_children(n: Node, node_name: String, out: Array) -> void:
	for c in n.get_children():
		if c.name == node_name and c is Button:
			out.append(c)
		_collect_children(c, node_name, out)


# ── 输入 ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_UP:
				_step(-1)
				accept_event()
			KEY_DOWN:
				_step(1)
				accept_event()
			KEY_LEFT:
				stage.set_yaw(stage.yaw_deg() - 15.0)
				accept_event()
			KEY_RIGHT:
				stage.set_yaw(stage.yaw_deg() + 15.0)
				accept_event()
			KEY_TAB:
				_toggle_mode()
				accept_event()
			KEY_ESCAPE:
				get_tree().quit()
				accept_event()
