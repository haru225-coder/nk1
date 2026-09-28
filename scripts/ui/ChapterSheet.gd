extends RefCounted
## 升章 / 了结册页（ChapterSheet）：晋升册页（「这一路」摘要 + 跳年代价 +「承此一路」翻页题签）、了结 / 结局册页、
## 册页前的过场（章节卡 / 结局过场）与正文区估高。Lane ms2 从 Main.gd 原样搬出（第三刀，整页 + 回调）。
## Main 留同名同签名的一行转发（_era_summary_lines / _show_chapter_dialog / _chapter_body_height / _cinema_before_sheet /
## _ending_cinema_key / _confirm_chapter_sheet），调用点、节点路径、信号目标都不动：「承此一路」钮与章节卡 exiting / 结局过场
## finished 仍 connect 到 Main 的同名方法。
## 状态（_chapter_host / _chapter_next_scene / _chapter_advanced / _chapter_years）与 ENDING_BG、过场 preload 仍归 Main，经 main 传进来；
## 这里不存状态。门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


## 「数年后」：把这一段的行为结成几行，再加上跳年的代价。
## 这是全作唯一一处让玩家看见「时间过去了」的地方——不能只写一句「三年后」。
static func era_summary_lines(main: Control, years: int) -> Array:
	var lines := []
	var trips: int = GameState.era_trips
	var route: String = GameState.era_main_route()
	var span := ("%s年" % main._cn_num(years, true)) if years > 0 else "一段日子"
	if trips > 0:
		if route != "":
			lines.append("这%s，你的船跑了%s趟，走得最多的是%s。" % [
				span, main._cn_num(trips, true), route,
			])
		else:
			lines.append("这%s，你的船跑了%s趟。" % [span, main._cn_num(trips, true)])
	if GameState.merchant_credit >= 20:
		lines.append("牙行里提起你的名字，不必再加「泉州那个姓陈的」。")
	elif GameState.merchant_credit <= -10:
		lines.append("有几家牙行不再接你的单子，理由都说得很客气。")
	if not Crew.hired.is_empty():
		var names := []
		for c in Crew.roster():
			names.append(str(c.get("name", "")))
		lines.append("还在船上的：%s。" % "、".join(names))
	return lines


static func show_dialog(main: Control, res: Dictionary) -> void:
	# 过场先演（晋升 → 章节卡，了结 / 结局 → 结局过场），演完带标记回到这里；headless 下当帧直接往下走
	if main._cinema_before_sheet(res):
		return
	# 结算底图随册页一起换（有结局过场时正是过场全黑的那一刻，画面上看不见切换）
	var ending := str(res.get("ending", ""))
	if ending != "" and main.ENDING_BG.has(ending):
		main._set_background_file(main.ENDING_BG[ending])  # 结算画面：台词压在结局图上
	var resolved_sheet: bool = bool(res.get("resolved", false))
	if resolved_sheet:
		# 结局 / 了结册页：港页工作层（工席、小笺、门排、动作行、港名匾）0.2 秒退去；崖山外海这类调查页的正文与选项整页隐去，
		# 结局最后一眼只留结局图与册页（第 2 轮美术 M2）。关册页走 load_scene，版面整页重建，自然回来。不入存档。
		main._dismiss_banner()
		main._show_port_layer(false, 0.2)
		main.investigation_mode.visible = false
		main.npc_mode.visible = false
	if is_instance_valid(main._chapter_host):
		main._chapter_host.queue_free()
	main._chapter_next_scene = str(res.get("scene", ""))
	# 晋升册页记住 advanced / years，供「承此一路」翻页题签；了结/结局不走晋印。
	main._chapter_advanced = bool(res.get("advanced", false)) and not resolved_sheet
	main._chapter_years = int(res.get("years", 0)) if main._chapter_advanced else 0

	var host := Control.new()
	host.name = "ChapterSheet"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(host)
	main._chapter_host = host

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 结局册页压得更深（宣纸工席退了之后仍有港画高光）；升章册页照旧 0.55
	dim.color = Color(0.05, 0.03, 0.02, 0.72 if resolved_sheet and UiTheme.IS_JUANBEN else 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)

	var sheet := PanelContainer.new()
	# 结局册页的长文加宽到 820；升章册页 640（第 1 轮评审 UX M8）
	var wide: bool = bool(res.get("resolved", false)) or str(res.get("ending", "")) != ""
	var sheet_w := 820 if wide and UiTheme.IS_JUANBEN else 640
	sheet.custom_minimum_size = Vector2(sheet_w, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	center.add_child(sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(sheet_w - 44, 0)
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var kicker := Label.new()
	var ok_text := "承此一路"
	if res.get("resolved", false):
		# 重读结局传自己的眉题与钮字（见 _on_reread_ending）；初读仍是「了结 / 记下这一纲」
		kicker.text = str(res.get("kicker", "了结"))
		ok_text = str(res.get("ok_text", "记下这一纲"))
	else:
		# 中文数字不留空格（「第 二 章」是给阿拉伯数字留的格式，第 2 轮美术 minor 3）
		kicker.text = "第%s章・%s" % [
			main._cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
		]
	UiTheme.style_section_label(kicker)
	if UiTheme.IS_JUANBEN:
		kicker.add_theme_font_size_override("font_size", 16)
		kicker.add_theme_font_override("font", UiTheme.body_spaced(2))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kicker)

	var head := Label.new()
	head.text = str(res.get("title", ""))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.style_heading(head)
	col.add_child(head)

	var raw := str(res.get("text", ""))
	# 本地 main P1 时间脊柱：晋升跳年。这些年不是空白，摘要（跑了几趟 / 主航线 / 信用）与代价（船旧人走）写在正文前。
	var years: int = int(res.get("years", 0))
	if years > 0:
		var era: Array = main._era_summary_lines(years)
		var costs: Array = GameManager.skip_years(years)
		var block := "【%s年后・%s】\n" % [main._cn_num(years, true), Calendar.get_date_string()]
		# 摘要与代价分两截：纪实短标，不混成一段现代 UI 状态词。
		if not era.is_empty():
			block += "这一路\n" + "\n".join(era) + "\n"
		if not costs.is_empty():
			block += "代价\n" + "\n".join(costs) + "\n"
		raw = block + "\n" + raw
		GameState.clear_era()
		main.update_status_panel()
	var body_w := sheet_w - 80
	# 正文区高：按画布高度放（720 下约 420，16:10 下多出来的高度也用上），按行高取整，底行不再裁半行
	var body_h: int = main._chapter_body_height(raw, body_w)
	var scroll := ScrollContainer.new()
	scroll.name = "SheetScroll"
	scroll.custom_minimum_size = Vector2(body_w, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body := Label.new()
	body.text = raw
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(body_w, 0)
	body.add_theme_font_override("font", UiTheme.font())
	body.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	body.add_theme_color_override("font_color", UiTheme.TEXT)
	body.add_theme_constant_override("line_spacing", UiTheme.LINE_BODY)
	scroll.add_child(body)
	# 滚动区底边 24px 渐隐：还有下文时底行淡进墨里，而不是被一刀裁掉半行（第 1 轮评审 minor 2）
	col.add_child(UiTheme.fade_scroll(scroll, 24))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var ok := Button.new()
	ok.text = ok_text
	ok.pressed.connect(main._confirm_chapter_sheet)
	col.add_child(ok)
	UiTheme.style_button(ok, true)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 绢本：印钮居中、定宽，不拉成一条通栏红条（夜潮照旧通栏）
	if UiTheme.IS_JUANBEN:
		ok.custom_minimum_size = Vector2(240, 44)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	main.update_status_panel()
	# 不是由章节卡揭开的（没有过场、或结局过场全黑之后）：册页淡入 + 微缩放，不再一帧弹出
	if not res.get("_cinema", false) or not res.get("advanced", false):
		UiTheme.pop_in(sheet)


## 正文区高：按行估高（每行 body_w / 字号 个字），上限按画布高度（画布高 − 300，720 下 420），
## 并取整到整行高，免得底行裁出半行。
static func body_height(main: Control, text: String, body_w := 560) -> int:
	var per_line := maxi(12, int(floor(float(body_w) / float(UiTheme.SIZE_BODY + 1))))
	var line_h := int(ceil(UiTheme.font().get_height(UiTheme.SIZE_BODY))) + UiTheme.LINE_BODY
	var lines := 0
	for raw_line in text.split("\n"):
		var n := raw_line.length()
		lines += 1 if n == 0 else maxi(1, int(ceil(float(n) / float(per_line))))
	var cap_h := 340
	if main.is_inside_tree():
		cap_h = clampi(int(main.get_viewport_rect().size.y) - 300, 300, 560)
	var want := clampi(lines * line_h + 8, 88, cap_h)
	return int(floor(float(want - 8) / float(line_h))) * line_h + 8


## 过场先于册页（cinematics 线）：晋升先演章节卡（年号按当前历法 + 跳年现算），了结 / 结局先演 data/cutscenes.json
## endings 映射里的结局过场；演完带 _cinema 标记回到 _show_chapter_dialog 弹原册页。
## headless / 巡检关闭 / 映射缺失时返回 false，调用方当帧照原逻辑走。
static func cinema_before_sheet(main: Control, res: Dictionary) -> bool:
	if res.get("_cinema", false) or not main._CINE.live():
		return false
	var node: Node = null
	if res.get("advanced", false):
		var year: int = Calendar.year + int(res.get("years", 0))
		node = main._CS_CARD.play(main, GameState.chapter, main._CINE.DATA, main._CINE.year_text(year, Calendar.ERAS))
	elif res.get("resolved", false):
		var key: String = main._ending_cinema_key(res)
		if key != "":
			node = main._CS_PLAYER.play_ending(main, key, main._CINE.DATA)
	if node == null:
		return false
	var after := res.duplicate()
	after["_cinema"] = true
	# 章节卡：纸面开始退去时就在卡底下建好压暗层与册页（连同跳年后的状态匾），纸退去揭开的就是最终画面；
	# 结局过场在全黑时发 finished，照旧接 finished
	var sig := "exiting" if node.has_signal("exiting") else "finished"
	node.connect(sig, main._show_chapter_dialog.bind(after), CONNECT_ONE_SHOT)
	return true


## 结局过场的键：_show_notice_dialog 带来的结局名（忠肃…）；章末了结（res.scene 是 ending_* 场景）取 GameState.ending_id
static func ending_cinema_key(res: Dictionary) -> String:
	var key := str(res.get("ending", ""))
	if key == "" and str(res.get("scene", "")) != "" and GameState.ending_id != "":
		key = GameState.ending_id
	return key


static func confirm_sheet(main: Control) -> void:
	if main._chapter_host == null:
		return
	var next_scene: String = main._chapter_next_scene
	var was_advanced: bool = main._chapter_advanced
	var years: int = main._chapter_years
	main._chapter_next_scene = ""
	main._chapter_advanced = false
	main._chapter_years = 0
	var host: Control = main._chapter_host
	main._chapter_host = null
	host.visible = false
	host.queue_free()
	var go := func() -> void:
		if next_scene != "" and not GameManager.get_scene_by_id(next_scene).is_empty():
			main.load_scene(next_scene)
		else:
			main.load_scene(main.current_scene_id)
	# 晋升翻页：墨幕题签「两年后・章名」印「晋」，全黑时换页；了结/结局直通。
	if was_advanced:
		var ch_name := str(GameState.chapter_def().get("name", ""))
		await main.play_transition(
			main._UI_TRANSITION.promote_title(years, ch_name),
			Calendar.get_date_string(),
			go,
			"晋"
		)
	else:
		go.call()
