extends RefCounted
## 航海日志册页（SaveSheet）：居中绢本浮层，三卷工席（卷号 / 题签 / 坏档脚注 / 「记录」「翻阅」小钮）+「合上」；
## 暗幕点下即合上；打开时港名匾先淡去、合上时回来（升章册页还压着就不回）；记录 / 翻阅两个回调。
## Lane main6 从 Main.gd 原样搬出（第六刀：_show_save_dialog … _on_load_slot）。
## Main 留同名同签名的一行转发（_show_save_dialog / _on_save_dim_input / _close_save_sheet / _on_save_slot / _on_load_slot），
## 调用点、节点名、信号目标都不动：「续卷」「航海日志」钮仍 connect 到 Main._show_save_dialog；
## 暗幕 gui_input、「记录」「翻阅」「合上」仍 connect 到 Main 的同名方法；ShotTour 仍 call Main._show_save_dialog；_unhandled_input 仍在 Main。
## 状态 _save_host 仍归 Main，经 main 取；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


## read_only：从标题页「续卷」进来——还没开局，「记录」不可用，只留「翻阅」。
static func show_save_dialog(main: Control, read_only := false) -> void:
	if is_instance_valid(main._save_host):
		main._save_host.queue_free()
	main._dismiss_banner()
	# 日志册页上沿正落在港名匾字脚上：匾先淡去，合上时回来（第 2 轮美术 minor 2）
	if main.port_mode.visible:
		main._show_port_layer(false, 0.15, true)
	var host := Control.new()
	host.name = "SaveSheet"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(host)
	main._save_host = host

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = UiTheme.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(main._on_save_dim_input)
	host.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var sheet := PanelContainer.new()
	# 两张 480 工席并排，间距 12，左右边距各 22。
	sheet.custom_minimum_size = Vector2(1016, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	center.add_child(sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := Label.new()
	head.text = "航海日志"
	UiTheme.style_heading(head)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	main._begin_benches(col)
	for slot in range(1, SaveLoad.SLOTS + 1):
		var n := int(slot)
		var slip: VBoxContainer = main._slip_body()
		# 卷号写中文数字：马善政的「1」像小写 l（第 1 轮评审 minor 12）
		main._slip_title(slip, "第%s卷" % main._cn_chapter(n), SaveLoad.save_label(n))
		var tip := SaveLoad.save_tip(n)
		if tip != "":
			var tip_color := UiTheme.CINNABAR if SaveLoad.slot_source(n) in ["corrupt", "future"] else UiTheme.TEXT_DIM
			main._slip_note(slip, tip, tip_color)
		var row: HFlowContainer = main._slip_row(slip)
		var write: Button = main._slip_chip(row, "记录", main._on_save_slot.bind(n), true)
		# 新版所记的卷也不给记（脚注许了「卷页未动」，一记就把新版进度退成副抄，见 SaveLoad.can_save）
		write.disabled = read_only or not SaveLoad.can_save(n)
		var read: Button = main._slip_chip(row, "翻阅", main._on_load_slot.bind(n))
		# 翻不开的卷（坏档 / 新版所记）不给按：按下去的失败句只进记事栏，标题页那里看不见（脚注已写明缘由）
		read.disabled = not SaveLoad.can_load(n)
	var benches := col.get_node("Benches") as HFlowContainer
	var row_h := 0.0
	for child in benches.get_children():
		if child is Control:
			row_h = maxf(row_h, (child as Control).get_combined_minimum_size().y)
	benches.custom_minimum_size = Vector2(972, row_h * 2.0 + 8.0)
	main._end_benches()
	# 最小留边（lane w25-j4）：册页左右离可见画边各至少 24 px。aspect=expand 下可见画布宽恒 ≥ 1280，
	# 现行各档窗口一律仍走 1016 原样（逐像素不变）；可见宽不足 1016 + 48 时册页收到「可见宽 − 48」，
	# 两张工席流成单列、字号不动。跟窗口改尺寸实时重算（host 撑满画布，resized 即视口变了）。
	var fit := func() -> void:
		var room: float = host.get_viewport_rect().size.x - 2.0 * 24.0 - 2.0  # 册页底板描边比 min 宽多 2 px
		var w: float = minf(1016.0, maxf(room, 480.0 + 44.0))
		var two: bool = w >= 1016.0
		sheet.custom_minimum_size = Vector2(w, 0)
		benches.custom_minimum_size = Vector2(w - 44.0, row_h * (2.0 if two else 3.0) + (8.0 if two else 16.0))
	fit.call()
	host.resized.connect(fit)

	var close := Button.new()
	close.text = "合上"
	close.custom_minimum_size = Vector2(160, 42)
	close.pressed.connect(main._close_save_sheet)
	col.add_child(close)
	UiTheme.style_button(close, true)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# 键盘焦点收进册页（lane w53-5 五轮）。鼠标点「航海日志」/「续卷」开册页，焦点原留在暗幕底下那颗钮上：Enter 把它
	# 再按一遍（册页拆了重开，Main._unhandled_input 的「Enter 合上」到不了）；Tab / 方向键走到暗幕底下的「名册」「看风」
	# 「再候一日」、工席门，Enter 就在册页底下开浮页、出海、候日。现在：焦点先交给册页底座（Control 不画焦点框，鼠标玩家
	# 看不出变化），Enter 落到 Main 合上；Tab / Shift+Tab / 方向键只在册页里按得动的钮之间轮转（不给按的钮不收焦点，
	# 照 SlipKit 只读钮的口径）；Esc 是「合上」的快捷键，焦点在哪都合上。拆出件不另立函数（只装从 Main 搬出的），就地写。
	var ring: Array = []
	for b in host.find_children("*", "Button", true, false):
		if (b as Button).disabled:
			(b as Button).focus_mode = Control.FOCUS_NONE
		elif (b as Button).focus_mode != Control.FOCUS_NONE:
			ring.append(b)
	for i in ring.size():
		var b: Button = ring[i]
		var nxt: NodePath = b.get_path_to(ring[(i + 1) % ring.size()])
		var prv: NodePath = b.get_path_to(ring[(i + ring.size() - 1) % ring.size()])
		b.focus_next = nxt
		b.focus_neighbor_right = nxt
		b.focus_neighbor_bottom = nxt
		b.focus_previous = prv
		b.focus_neighbor_left = prv
		b.focus_neighbor_top = prv
	host.focus_mode = Control.FOCUS_ALL
	if not ring.is_empty():
		host.focus_next = host.get_path_to(ring[0])
		host.focus_neighbor_right = host.focus_next
		host.focus_neighbor_bottom = host.focus_next
		host.focus_previous = host.get_path_to(ring[ring.size() - 1])
		host.focus_neighbor_left = host.focus_previous
		host.focus_neighbor_top = host.focus_previous
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	var cut := Shortcut.new()
	cut.events = [esc]
	close.shortcut = cut
	close.shortcut_in_tooltip = false
	host.grab_focus()
	UiTheme.pop_in(sheet)


static func on_save_dim_input(main: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			main._close_save_sheet()


static func close_save_sheet(main: Control) -> void:
	if is_instance_valid(main._save_host):
		main._save_host.queue_free()
	main._save_host = null
	if main.port_mode.visible and not is_instance_valid(main._chapter_host):
		main._show_port_layer(true, 0.15, true)


static func on_save_slot(main: Control, slot: int) -> void:
	if not SaveLoad.can_save(slot) or not SaveLoad.save_game(slot, main.current_scene_id):
		main.log_msg("第 %d 卷誊写未成，笔墨未落定。" % slot)
		return
	main._close_save_sheet()
	main.log_msg("已记入航海日志第 %d 卷。" % slot)


static func on_load_slot(main: Control, slot: int) -> void:
	var scene_id := SaveLoad.saved_scene(slot)
	var from_bak := SaveLoad.slot_source(slot) == "bak"
	if SaveLoad.can_load(slot):
		# 读档即回到那一卷的日子：船籍簿记事栏里这一局后来的事（歇了几日、买卖、逾期……）在那一卷里都没发生过，
		# 留着就冒充前情——「如今是三月十三」压在刚翻开的三月初九那一卷下面。记事从空起，与海图回港 Main 重建、
		# 记事栏从空起同口径；五格即 LogFold 头注所列宿主字段。在 load_game 之前清：读档时的旧卷勾稽一声
		# （stale_notice）照记；读不开的卷不清，失败句记进原记事。
		main._log_lines = PackedStringArray()
		main._log_folds = {}
		main._log_fold_open = ""
		main._notice_run = 0
		main._notice_when = []
	if not SaveLoad.load_game(slot):
		main.log_msg("第 %d 卷%s" % [slot, SaveLoad.load_fail_note(slot)])
		return
	main._close_save_sheet()
	main.update_status_panel()
	main.load_scene(scene_id if scene_id != "" else GameState.last_port)
	main.log_msg("翻开日志第 %d 卷，回到 %s。" % [slot, Calendar.get_date_string()])
	if from_bak:
		main.log_msg("第 %d 卷正本卷页损了，已从副抄翻出。" % slot)
