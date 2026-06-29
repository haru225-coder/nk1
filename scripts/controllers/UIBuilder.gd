class_name UIBuilder extends RefCounted

## NK1-P6-POLISH-002: 统一 UI 构建工具类
## 将散布各处的纯代码 UI 构建逻辑集中管理
## 减少重复代码、保证一致性、便于统一调整

## ── 按钮构建 ─────────────────────────────────────────────

## 创建带主题的按钮
## text: 按钮文字
## theme: UITheme 常量 (如 UITheme.BTN_ACTION)
## min_height: 最小高度（默认 44）
static func make_button(text: String, theme: String, min_height: int = 44) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, min_height)
	btn.theme_type_variation = theme
	apply_button_polishes(btn)
	return btn

static func apply_button_polishes(btn: Button) -> void:
	var theme = btn.theme_type_variation
	if theme == UITheme.BTN_CHOICE or theme == UITheme.BTN_SET_SAIL or theme == UITheme.BTN_TITLE_MENU or theme == UITheme.BTN_COMMAND:
		_setup_hover_breath_effect(btn)

static func _setup_hover_breath_effect(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		if btn.has_meta("hover_tween"):
			var old_tween = btn.get_meta("hover_tween")
			if old_tween and old_tween.is_valid():
				old_tween.kill()
		
		var tween := btn.create_tween()
		btn.set_meta("hover_tween", tween)
		tween.set_loops()
		tween.tween_property(btn, "modulate", Color(1.08, 1.04, 0.82, 1.0), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(btn, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	)
	
	btn.mouse_exited.connect(func():
		if btn.has_meta("hover_tween"):
			var old_tween = btn.get_meta("hover_tween")
			if old_tween and old_tween.is_valid():
				old_tween.kill()
			btn.remove_meta("hover_tween")
		
		var tween := btn.create_tween()
		tween.tween_property(btn, "modulate", Color.WHITE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)

## 创建操作按钮（ActionButton 主题，52 高度）
static func make_action_button(text: String) -> Button:
	return make_button(text, UITheme.BTN_ACTION, 52)

## 创建选择按钮（ChoiceButton 主题，40 高度）
static func make_choice_button(text: String) -> Button:
	return make_button(text, UITheme.BTN_CHOICE, 40)

## 创建升帆按钮（SetSailButton 主题，60 高度）
static func make_set_sail_button(text: String) -> Button:
	return make_button(text, UITheme.BTN_SET_SAIL, 60)

## 创建 NPC 按钮
static func make_npc_button(text: String) -> Button:
	return make_button(text, UITheme.BTN_NPC, 48)

## ── 标签构建 ─────────────────────────────────────────────

## 创建带主题的标签
static func make_label(text: String, theme: String, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = align
	lbl.theme_type_variation = theme
	return lbl

## 创建市场预览标签
static func make_market_preview(text: String, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return make_label(text, UITheme.MARKET_PREVIEW, align)

## 创建市场告警标签
static func make_market_alert(text: String) -> Label:
	return make_label(text, UITheme.MARKET_ALERT, HORIZONTAL_ALIGNMENT_CENTER)

## 创建市场标题标签
static func make_market_title(text: String) -> Label:
	return make_label(text, UITheme.MARKET_TITLE, HORIZONTAL_ALIGNMENT_CENTER)

## ── 面板构建 ─────────────────────────────────────────────

## 创建带主题的面板
static func make_panel(theme: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = theme
	return panel

## 创建市场面板
static func make_market_panel() -> PanelContainer:
	return make_panel(UITheme.MARKET_PANEL)

## 创建市场外壳
static func make_market_shell() -> PanelContainer:
	return make_panel(UITheme.MARKET_SHELL)

## 创建设施卡片面板
static func make_facility_card(is_quest: bool = false) -> PanelContainer:
	return make_panel(UITheme.CARD_FACILITY_QUEST if is_quest else UITheme.CARD_FACILITY)

## ── 港状态栏芯片构建 ─────────────────────────────────────

## 创建港状态栏芯片（背景+标题+数值三件套）
static func make_port_stat_chip(caption: String, value: String) -> PanelContainer:
	var chip := make_panel(UITheme.CHIP_PORT_STAT)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)

	var cap_lbl := make_label(caption, UITheme.LABEL_PORT_STAT)
	col.add_child(cap_lbl)

	var val_lbl := make_label(value, UITheme.VALUE_PORT_STAT)
	col.add_child(val_lbl)
	return chip

## ── 文本输入框 ───────────────────────────────────────────

## 创建带主题的 RichTextLabel
static func make_rich_text(text: String, theme: String, bbcode: bool = false) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.text = text
	rtl.theme_type_variation = theme
	rtl.bbcode_enabled = bbcode
	return rtl

## ── Section 标题 ──────────────────────────────────────────

## 创建区域标题标签
static func make_section_label(text: String) -> Label:
	return make_label(text, UITheme.SECTION_LABEL)
