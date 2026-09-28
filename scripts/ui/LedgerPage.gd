extends RefCounted
## 船籍簿整页：顶上状态匾（StatusStrip）+ 点开才盖上的船籍簿浮层（LedgerLayer）+ 船籍簿正文与记事栏。
## Lane mz 从 Main.gd 原样搬出（第二刀，整页 + 回调）。Main 留同名同签名的一行转发（_mount_status_strip / _toggle_ledger /
## update_status_panel …），调用点、节点路径、信号目标都不动：浮层与匾上的钮仍 connect 到 Main 的同名方法。
## 状态（_status_strip / _ledger_layer / _log_lines …）与 left_panel、status_label 仍归 Main，经 main 传进来；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


static func dress(main: Control) -> void:
	var title := main.get_node("HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/TitleLabel")
	title.text = "船籍簿"
	UiTheme.style_heading(title)
	# 绢本：抬头与「航海日志」同一字阶（SIZE_HEAD）；正文左右留 18，不贴金线（第 1 轮评审 minor 3）
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD if UiTheme.IS_JUANBEN else UiTheme.SIZE_BODY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UiTheme.IS_JUANBEN:
		var lm := main.get_node("HBoxContainer/LeftPanel/MarginContainer") as MarginContainer
		lm.add_theme_constant_override("margin_left", 28)
		lm.add_theme_constant_override("margin_right", 28)
		lm.add_theme_constant_override("margin_top", 18)
		lm.add_theme_constant_override("margin_bottom", 20)
	var rule := main.get_node("HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/HSeparator")
	if rule is Separator:
		var line := StyleBoxLine.new()
		line.color = Color(UiTheme.GOLD, 0.45)
		line.thickness = 1
		rule.add_theme_stylebox_override("separator", line)


## 顶上一匾。左栏收起来之后，日期和钱留在这里。
static func mount_strip(main: Control) -> void:
	var strip := PanelContainer.new()
	strip.name = "StatusStrip"
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_left = 16
	strip.offset_top = 8
	strip.offset_right = -16
	strip.offset_bottom = 76
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.add_theme_stylebox_override("panel", UiTheme.plaque())
	strip.visible = false
	main.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(row)
	# 两行：上行日期、钱、水粮、章（富文本上色）；下行最新一条记事（Label，超长以「…」收尾、全文挂 tooltip）。
	# 原先下行也是不折行的富文本，超长直接截断，旧闻点睛那半句看不到（第 2 轮 UX M3）
	var lines := VBoxContainer.new()
	lines.name = "StatusText"
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	main._status_line = RichTextLabel.new()
	main._status_line.bbcode_enabled = true
	main._status_line.fit_content = true
	main._status_line.scroll_active = false
	main._status_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	main._status_line.clip_contents = true
	main._status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._status_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_body(main._status_line)
	lines.add_child(main._status_line)
	main._status_note = Label.new()
	main._status_note.name = "StatusNote"
	main._status_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main._status_note.clip_text = true
	main._status_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	main._status_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main._status_note.custom_minimum_size = Vector2(80, 0)
	main._status_note.mouse_filter = Control.MOUSE_FILTER_PASS
	main._status_note.add_theme_font_override("font", UiTheme.font())
	main._status_note.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	main._status_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	lines.add_child(main._status_note)
	var book := Button.new()
	book.text = "船籍簿"
	book.custom_minimum_size = Vector2(120, 40)
	book.pressed.connect(main._toggle_ledger)
	UiTheme.style_button(book, false)
	row.add_child(book)
	main._status_strip = strip


## 船籍簿从横排里摘出来，点开才盖在画面上。
static func lift(main: Control) -> void:
	var layer := Control.new()
	layer.name = "LedgerLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = UiTheme.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(main._on_ledger_dim_input)
	layer.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	main.left_panel.get_parent().remove_child(main.left_panel)
	main.left_panel.custom_minimum_size = Vector2(480, 600)
	main.left_panel.visible = true
	holder.add_child(main.left_panel)
	main.status_label.scroll_active = true
	main.status_label.custom_minimum_size = Vector2(0, 360)
	var close := Button.new()
	close.text = "合上"
	close.custom_minimum_size = Vector2(0, 40)
	if UiTheme.IS_JUANBEN:
		# 绢本：印钮居中定宽，不拉成通栏红条
		close.custom_minimum_size = Vector2(160, 40)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(main._close_ledger)
	UiTheme.style_button(close, true)
	main.left_panel.get_node("MarginContainer/VBoxContainer").add_child(close)
	main._ledger_layer = layer


static func show_strip(main: Control, show: bool) -> void:
	if main._status_strip == null:
		return
	main._status_strip.visible = show
	var box := main.get_node("HBoxContainer")
	box.offset_top = 84 if show else 16


static func toggle(main: Control) -> void:
	if main._ledger_layer == null:
		return
	if main._ledger_layer.visible:
		main._close_ledger()
		return
	main._dismiss_banner()
	main._ledger_layer.visible = true
	main.move_child(main._ledger_layer, main.get_child_count() - 1)
	UiTheme.pop_in(main.left_panel)


static func close(main: Control) -> void:
	if main._ledger_layer != null:
		main._ledger_layer.visible = false


static func on_dim_input(main: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			main._close_ledger()


static func refresh_strip(main: Control) -> void:
	if main._status_line == null:
		return
	var supply_d := Fleet.supply_days()
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY
	var debt := ""
	if GameState.debt > 0:
		debt = "　[color=#%s]欠 %d[/color]" % [UiTheme.hex(UiTheme.HONEY), GameState.debt]
	var line1 := "%s　%s　钱 %d%s　[color=#%s]水粮 %d 日[/color]　第%s章・%s" % [
		Calendar.get_date_string(),
		main._monsoon_short(),
		GameState.money,
		debt,
		UiTheme.hex(supply_color),
		supply_d,
		main._cn_chapter(GameState.chapter),
		str(GameState.chapter_def().get("name", "")),
	]
	var note: String = main._latest_log()
	if note == "":
		note = main._chapter_hint()
	# 委办在身：札记旁注前缀短标（与海图顶匾口径一致）
	var cst_note := GameState.contract_status()
	if not cst_note.is_empty():
		var left_n: int = int(cst_note.get("days_left", 0))
		var tag_n := "委办已逾" if left_n < 0 else ("委办 %d 日" % left_n)
		note = tag_n if note == "" else ("%s　%s" % [tag_n, note])
	main._status_line.text = line1
	if main._status_note != null:
		var plain := note.replace("\n", "　")
		main._status_note.text = plain
		main._status_note.tooltip_text = note if note.length() > 30 else ""


## 船籍簿记事栏：最近 8 条，新的在上（宣纸色），旧的淡一档；一条没有时写一行淡字，不留空墨框
static func render_log(main: Control) -> void:
	if main._log_lines.is_empty():
		main.message_label.text = "[color=#%s]（尚无记事）[/color]" % UiTheme.hex(UiTheme.TEXT_DIM)
		return
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	var parts := PackedStringArray()
	for i in main._log_lines.size():
		var line: String = main._log_lines[i]
		parts.append(line if i == 0 else "[color=#%s]%s[/color]" % [dim, line])
	main.message_label.text = "\n".join(parts)


static func update_panel(main: Control) -> void:
	var cargo_str := ""
	if Fleet.cargo.is_empty():
		cargo_str = "空\n"
	else:
		for gid in Fleet.cargo.keys():
			var e: Dictionary = Fleet.cargo[gid]
			cargo_str += "%s ×%d\n" % [GameManager.get_good_name(gid), e.get("qty", 0)]

	var cap_used := Fleet.used_capacity()
	var cap_total := Fleet.total_capacity()
	var supply_d := Fleet.supply_days()
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY

	var permit_str := "在手" if GameState.has_customs_permit else "未领"
	var contraband := GameState.contraband_units()
	var gold := UiTheme.hex(UiTheme.GOLD)
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)

	var t := "[color=#%s][b]%s[/b][/color]\n[color=#%s]%s[/color]\n" % [
		gold, Calendar.get_date_string(), dim, Calendar.get_monsoon_desc(),
	]
	t += "金钱　[b]%d[/b]\n" % GameState.money
	if GameState.debt > 0:
		t += "[color=#%s]欠债　%d[/color]\n" % [UiTheme.hex(UiTheme.HONEY), GameState.debt]
	t += "名声　%d　%s\n" % [GameState.fame, GameState.title_name()]
	if GameState.network != 0 or GameState.merchant_credit != 0:
		t += "人脉　%d　海商信用　%d\n" % [GameState.network, GameState.merchant_credit]
	t += "[color=#%s][b]船队[/b][/color]\n船数　%d　水手　%d\n舱位　%d / %d 料\n耐久　%d / %d\n士气　%d\n" % [
		gold,
		Fleet.ships.size(), Fleet.total_crew(),
		int(cap_used), int(cap_total),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水　%d　粮　%d　[color=#%s]足 %d 日[/color]\n" % [
		Fleet.water, Fleet.food, UiTheme.hex(supply_color), supply_d,
	]

	# 职事行前的小头像（characters 线）：富文本里只能 add_image，先在串里留记号，末尾 _set_status_text 换图
	var heads: Array = []
	if not Crew.hired.is_empty():
		t += "[color=#%s][b]职事[/b][/color]\n" % gold
		for c in Crew.roster():
			var head_tex: Texture2D = main._roster_head(str(c.get("id", "")))
			if head_tex != null:
				t += "%s%d%s" % [main.HEAD_MARK, heads.size(), main.HEAD_MARK]
				heads.append(head_tex)
			t += "%s　%s　%s\n" % [
				Crew.role_def(c.get("role", "")).get("name", ""),
				c.get("name", ""), main._skill_rank(int(c.get("level", 1))),
			]
		var wage := Crew.monthly_wage()
		var wage_color := UiTheme.HONEY if Crew.unpaid_months > 0 else UiTheme.TEXT
		t += "[color=#%s]月俸共 %d" % [UiTheme.hex(wage_color), wage]
		if Crew.unpaid_months > 0:
			t += "　已欠 %d 月" % Crew.unpaid_months
		t += "[/color]\n"
	t += "[color=#%s][b]市舶[/b][/color]\n蒲家留意　%d\n货引　%s\n" % [
		gold, GameState.pu_attention, permit_str,
	]
	if contraband > 0:
		t += "[color=#%s]舱底违禁　%d 件[/color]\n" % [UiTheme.hex(UiTheme.CINNABAR), contraband]
	t += "[color=#%s][b]船舱[/b][/color]\n%s" % [gold, cargo_str]

	# 多船时追加每船明细
	if Fleet.ships.size() > 1:
		for i in range(Fleet.ships.size()):
			var s: Dictionary = Fleet.ships[i]
			var per_ship := ""
			var sc: Dictionary = s.get("cargo", {})
			if sc.is_empty():
				per_ship = "空"
			else:
				for gid in sc.keys():
					per_ship += "%s ×%d　" % [GameManager.get_good_name(gid), sc[gid].get("qty", 0)]
			var crew_str := "水手 %d / %d" % [Fleet.ship_crew(i), Fleet.ship_crew_max(i)]
			var crew_color := UiTheme.hex(UiTheme.TEXT)
			if Fleet.ship_crew(i) < Fleet.ship_crew_min(i):
				crew_color = UiTheme.hex(UiTheme.CINNABAR)
				crew_str += "　缺 %d 人" % (Fleet.ship_crew_min(i) - Fleet.ship_crew(i))
			t += "　%s　%s　%d / %d 料　帆%s　甲%s　[color=#%s]%s[/color]　%s\n" % [
				s.get("name", ""), Fleet.ship_def(s.get("type", "")).get("name", ""),
				int(Fleet.ship_cargo_bulk(i)), int(Fleet.ship_capacity(i)),
				main._fit_rank(Fleet.sail_level(i)), main._fit_rank(Fleet.armor_level(i)),
				crew_color, crew_str, per_ship,
			]

	var cst := GameState.contract_status()
	if not cst.is_empty():
		var left: int = int(cst.get("days_left", 0))
		var left_s := "限今日" if left == 0 else ("剩 %d 日" % left if left > 0 else "已逾")
		var col := UiTheme.hex(UiTheme.HONEY) if left <= 2 else UiTheme.hex(UiTheme.TEXT)
		if left < 0:
			col = UiTheme.hex(UiTheme.CINNABAR)
		t += "\n[u]委办[/u]\n[color=#%s]%s ×%d 运往 %s（%s）酬 %d[/color]\n" % [
			col,
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("remaining", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			left_s,
			int(cst.get("pay_left", 0)),
		]

	# 章节目标：不写出来玩家不会知道怎样才能开出下一片海
	var prog := GameState.chapter_progress()
	t += "[color=#%s][b]第%s章・%s[/b][/color]\n" % [
		UiTheme.hex(UiTheme.GOLD),
		main._cn_chapter(GameState.chapter), GameState.chapter_def().get("name", ""),
	]
	if prog.get("ended", false):
		t += "[color=#%s]了结　%s[/color]\n" % [
			UiTheme.hex(UiTheme.GOLD), prog.get("ending_title", GameState.ending_title()),
		]
	elif prog.get("final", false):
		t += "[color=#%s]终章・可了结[/color]\n" % UiTheme.hex(UiTheme.TEXT_DIM)
		for it in prog.get("items", []):
			t = main._append_progress_line(t, it)
	else:
		for it in prog.get("items", []):
			t = main._append_progress_line(t, it)

	if heads.is_empty():
		main.status_label.text = t
	else:
		main._set_status_text(t, heads)
	main._refresh_strip()


## 职事的小头像：头面方块、烤一道泥金边。headless 或查无立绘时返回 null，这一行照旧只有字。
static func roster_head(main: Control, crew_id: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var ch: Dictionary = GameManager.character_for_crew(crew_id)
	if ch.is_empty():
		return null
	return main._CHAR_ART.thumb(ch, Vector2i(main.ROSTER_HEAD, main.ROSTER_HEAD), true, Color(UiTheme.GOLD, 0.9))


## 船籍簿正文：按记号切开，字段照 bbcode 追加，记号处插小头像（与文字行垂直居中）。
static func set_status_text(main: Control, t: String, heads: Array) -> void:
	# 先置空（text 属性归零，下回整串赋值一定重排），再逐段追加
	main.status_label.text = ""
	var parts := t.split(main.HEAD_MARK)
	for i in parts.size():
		if i % 2 == 1:
			var k := int(parts[i])
			if k >= 0 and k < heads.size():
				main.status_label.add_image(heads[k], main.ROSTER_HEAD, main.ROSTER_HEAD, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				main.status_label.append_text(" ")
		elif parts[i] != "":
			main.status_label.append_text(parts[i])


static func append_progress_line(text: String, it: Dictionary) -> String:
	var mark := "・"
	if it.get("done", false):
		mark = "[color=#%s]已[/color]" % UiTheme.hex(UiTheme.MOSS)
	if int(it.get("need", 1)) > 1:
		return text + "%s　%s　%d / %d\n" % [mark, it.get("label", ""), it.get("current", 0), it.get("need", 1)]
	return text + "%s　%s\n" % [mark, it.get("label", "")]
