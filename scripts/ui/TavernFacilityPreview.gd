extends Control
## 独立验收页：不改 Main，展示设施卡在绢本港画上的层次与字阶。

const SLIP := preload("res://scenes/ui/TavernFacilitySlip.tscn")

func _ready() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture = load("res://assets/bg_xinghua_wine_shed.jpg")
	background.modulate = Color(0.72, 0.65, 0.56, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = UiTheme.VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_CENTER)
	page.position = Vector2(-590, -300)
	page.size = Vector2(1180, 600)
	page.add_theme_constant_override("separation", 16)
	add_child(page)

	var kicker := Label.new()
	kicker.text = "岸带设施卡　样式记录"
	kicker.add_theme_font_override("font", UiTheme.font())
	kicker.add_theme_font_size_override("font_size", 16)
	kicker.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(kicker)

	var heading := Label.new()
	heading.text = "兴化军・酒棚"
	heading.add_theme_font_override("font", UiTheme.title_font())
	heading.add_theme_font_size_override("font_size", 38)
	heading.add_theme_color_override("font_color", UiTheme.TEXT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(heading)

	var note := Label.new()
	note.text = "卡面分列去处、记录状态与可执行动作；正文不使用宣传性形容。"
	note.add_theme_font_override("font", UiTheme.font())
	note.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(note)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cards)

	_add_card(cards, "tavern", "兴化", "酒馆", "打听消息・募人", "本日开放", "劣酒与潮气同在。邻桌有人谈远港价目。", "进入酒馆", "tavern")
	_add_card(cards, "inn", "兴化", "旅店", "歇息・候风", "本日开放", "通铺草席未干。风信不合时，海商在此候着。", "进入旅店", "inn")
	_add_card(cards, "guild", "泉州", "行会", "行情・信用", "本日开放", "行首核对舱位与脚钱。墙上钉着一张远港价目。", "查看行会", "guild")

	var footer := Label.new()
	footer.text = "预览页不写入存档；动作钮只发出 selected 信号。"
	footer.add_theme_font_override("font", UiTheme.font())
	footer.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	footer.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(footer)

func _add_card(parent: Node, id: String, port: String, title: String, subtitle: String, status: String, record: String, action: String, icon: String) -> void:
	var card := SLIP.instantiate() as TavernFacilitySlip
	card.facility_id = id
	card.port_name = port
	card.facility_name = title
	card.facility_subtitle = subtitle
	card.status_text = status
	card.record_text = record
	card.action_text = action
	card.icon_name = icon
	card.selected.connect(_on_card_selected)
	parent.add_child(card)

func _on_card_selected(id: String) -> void:
	# 预览页只记录选择，不导航；真实页面由调用方接管信号。
	var stamp := get_node_or_null("SelectionStamp") as Label
	if stamp == null:
		stamp = Label.new()
		stamp.name = "SelectionStamp"
		stamp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		stamp.offset_top = -42
		stamp.offset_bottom = -16
		stamp.add_theme_font_override("font", UiTheme.font())
		stamp.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
		stamp.add_theme_color_override("font_color", UiTheme.GOLD_HI)
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(stamp)
	stamp.text = "已选：%s　（预览页不导航）" % id
