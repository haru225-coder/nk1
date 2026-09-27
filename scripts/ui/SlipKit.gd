extends RefCounted
## 工席纸条小件：卡身 / 题签 / 旁注 / 钮行 / chip / 只读章 / 整卡可点。
## Lane ms 从 Main.gd 原样搬出（首刀试点）。Main 留同名同签名的一行转发（_slip_body / _slip_title …），
## 调用点与门禁的源码断言都不动。_slip_host、choices_container 仍归 Main，经参数传进来；这里不存状态。


## 工席宽 480，扣掉潮光边和内边距后字宽 448。
## Label 打开 autowrap 后最小高度仍按一行算，长旁注会被裁成半句。
## in_flow：Main 的 _slip_host 是否为 Benches（HFlowContainer）。
static func lock_wrap(lbl: Label, in_flow: bool) -> void:
	if not in_flow:
		return
	var width := 448.0
	var font := lbl.get_theme_font("font")
	if font == null:
		font = UiTheme.font()
	var fsize := lbl.get_theme_font_size("font_size")
	if fsize <= 0:
		fsize = UiTheme.SIZE_FOOT
	var measured := font.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, width, fsize)
	var h := measured.y
	if h < float(fsize):
		h = float(fsize)
	lbl.custom_minimum_size = Vector2(width, ceil(h))


## host：Main 的 _slip_host（可为 null）；fallback：host 为空时挂到哪（Main 传 choices_container）。
static func card_body(host: Node, fallback: Node) -> VBoxContainer:
	var card := PanelContainer.new()
	UiTheme.paper_card(card)
	var in_flow := host is HFlowContainer
	if in_flow:
		card.custom_minimum_size = Vector2(480, 0)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	margin.add_child(body)
	var parent: Node = host if host != null else fallback
	parent.add_child(card)
	return body


static func add_title(body: VBoxContainer, title: String, aside: String, in_flow: bool) -> Label:
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_override("font", UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_lbl.add_theme_color_override("font_color", UiTheme.TIDE)
	lock_wrap(name_lbl, in_flow)
	body.add_child(name_lbl)
	var hint := Label.new()
	hint.text = aside
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_footnote(hint)
	if aside != "":
		lock_wrap(hint, in_flow)
		body.add_child(hint)
	return hint


static func add_note(body: VBoxContainer, text: String, color: Color, in_flow: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", color)
	lock_wrap(lbl, in_flow)
	body.add_child(lbl)
	return lbl


## 钮行上方留一道空，旁注不贴钮。pin：空档可伸，钮行压到卡底——同排卡被拉高时两枚钮齐平。
static func add_row(body: VBoxContainer, pin := false) -> HFlowContainer:
	if body.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if pin:
			gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(gap)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	return row


static func add_chip(row: Node, text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	row.add_child(b)
	UiTheme.style_chip(b, accent)
	return b


## 只读态的钮：同一块 chip 皮，disabled、不聚焦、箭头光标。卡底仍有一行，不像坏掉的空卡。
static func add_stamp(row: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = true
	b.focus_mode = Control.FOCUS_NONE
	row.add_child(b)
	UiTheme.style_chip(b, false)
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return b


## 工席上只有这一个动作时，整张卡都可点（照 _make_shore_door：卡底下铺一层扁平钮，悬停时纸被照亮）。
## 卡里的容器让开鼠标；小钮本身仍在最上面，点它照旧。第 1 轮评审 UX M6：玩家会去点卡，卡原先没有反应。
static func whole_card(btn: Button) -> void:
	var card: Node = btn.get_parent()
	while card != null and not (card is PanelContainer):
		card = card.get_parent()
	if card == null or card.get_node_or_null("WholeHit") != null:
		return
	var panel := card as PanelContainer
	for c in panel.find_children("*", "Container", true, false):
		if (c as Control).tooltip_text == "":
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.name = "WholeHit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(s, empty)
	hit.tooltip_text = btn.tooltip_text
	hit.pressed.connect(func() -> void:
		if is_instance_valid(btn) and not btn.disabled:
			btn.pressed.emit())
	hit.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			panel.add_theme_stylebox_override("panel", UiTheme.shore_door_hover()))
	hit.mouse_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", UiTheme.shore_door()))
	panel.add_child(hit)
	panel.move_child(hit, 0)
