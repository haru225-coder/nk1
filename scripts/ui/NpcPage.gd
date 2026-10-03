extends RefCounted
## 见面页（NpcPage）：_ready 里装好的见面册页版面（立绘框、对话熟漆册、人物栏：名 + 字号 + 阵营签 + 人物志钮 + 身份 / 五维 / 特技 / 小传）、
## 设施页上的「在侧」人物卡与「见」钮、见面页本身（立绘先认 characters.json、招呼、行情「打听」、市舶司「疏通」、离开）与三个回调。
## Lane main5 从 Main.gd 原样搬出（第五刀，两段：_frame_portrait … _fill_npc_profile 与 _add_npc_button … _on_npc_leave）。
## Main 留同名同签名的一行转发（_frame_portrait / _dress_npc_sheet / _mount_npc_profile / _fill_npc_profile / _add_npc_button /
## _on_meet_npc / _show_npc_mode / _set_npc_speech / _on_npc_intel / _on_npc_bribe / _on_npc_leave），调用点、节点路径、信号目标都不动：
## 「见」「打听」「塞　50」「离开」仍 connect 到 Main 的同名方法；人物志钮仍是一个 lambda，按下时读 Main 的 _npc_codex_id。
## 状态（npc_mode / npc_portrait / npc_name_lbl / npc_dialog_lbl / npc_actions 与 _npc_speech / _npc_courtesy / _npc_faction /
## _npc_profile / _npc_codex_btn / _npc_codex_id）和 _CHAR_ART 仍归 Main，经 main 取；随簇搬来的只有招呼常量 NPC_GREETING。这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


static func frame_portrait(main: Control) -> void:
	var parent: Node = main.npc_portrait.get_parent()
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(280, 0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	var idx: int = main.npc_portrait.get_index()
	parent.remove_child(main.npc_portrait)
	parent.add_child(frame)
	parent.move_child(frame, idx)
	frame.add_child(main.npc_portrait)
	main.npc_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.npc_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 绢本：换成旧绢裱框 + 名牌（夜潮返回 false，上面的画框照旧）
	UiTheme.frame_portrait(frame, main.npc_portrait)


## 见面是中栏里的一册：对话落在熟漆上，画像没有就不留空框。
static func dress_npc_sheet(main: Control) -> void:
	var hbox: HBoxContainer = main.npc_mode.get_node("HBox")
	hbox.offset_left = 16
	hbox.offset_top = 16
	hbox.offset_right = -16
	hbox.offset_bottom = -16
	var dialog: Node = main.npc_name_lbl.get_parent()
	var sheet := PanelContainer.new()
	sheet.name = "DialogSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	var idx := dialog.get_index()
	var parent := dialog.get_parent()
	parent.remove_child(dialog)
	parent.add_child(sheet)
	parent.move_child(sheet, idx)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	# 底边距 24：「离开」钮离开面板底线与泥金框饰（原 14 时钮的下沿压在框线上）
	margin.add_theme_constant_override("margin_bottom", 24)
	sheet.add_child(margin)
	dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(dialog)
	UiTheme.style_heading(main.npc_name_lbl)
	main.npc_dialog_lbl.fit_content = true
	main.npc_dialog_lbl.scroll_active = false
	main.npc_dialog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.npc_dialog_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	UiTheme.style_body(main.npc_dialog_lbl)
	main.npc_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.npc_actions.add_theme_constant_override("separation", 8)
	main._mount_npc_profile(dialog)


## 见面页的人物栏（characters 线）：名字一行并上字号与阵营签，下面身份、五维、特技、小传。
## 内容由 _show_npc_mode 按 characters.json 填；查无此人时整栏藏起，见面页照旧。
static func mount_npc_profile(main: Control, dialog: Node) -> void:
	var head := HBoxContainer.new()
	head.name = "NPCHead"
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at: int = main.npc_name_lbl.get_index()
	dialog.remove_child(main.npc_name_lbl)
	head.add_child(main.npc_name_lbl)
	main.npc_name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main._npc_courtesy = main._CHAR_ART.label("", UiTheme.SIZE_FOOT + 2, UiTheme.TEXT_DIM)
	main._npc_courtesy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(main._npc_courtesy)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	main._npc_faction = HBoxContainer.new()
	main._npc_faction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._npc_faction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(main._npc_faction)
	# 翻到人物志里此人那一页
	main._npc_codex_btn = Button.new()
	main._npc_codex_btn.name = "NPCCodexButton"
	main._npc_codex_btn.text = "人物志"
	main._npc_codex_btn.custom_minimum_size = Vector2(88, 32)
	main._npc_codex_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main._npc_codex_btn.visible = false
	UiTheme.style_button(main._npc_codex_btn)
	main._npc_codex_btn.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT + 1)
	main._npc_codex_btn.pressed.connect(func() -> void: main._open_codex(main._npc_codex_id))
	head.add_child(main._npc_codex_btn)
	dialog.add_child(head)
	dialog.move_child(head, at)
	main._npc_profile = VBoxContainer.new()
	main._npc_profile.name = "NPCProfile"
	main._npc_profile.add_theme_constant_override("separation", 8)
	main._npc_profile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._npc_profile.visible = false
	dialog.add_child(main._npc_profile)
	dialog.move_child(main._npc_profile, at + 1)


static func fill_npc_profile(main: Control, ch: Dictionary) -> void:
	if main._npc_profile == null:
		return
	for box in [main._npc_profile, main._npc_faction]:
		var stale: Array = (box as Node).get_children()
		for c in stale:
			(box as Node).remove_child(c)
			c.queue_free()
	main._npc_courtesy.text = main._CHAR_ART.courtesy_of(ch)
	main._npc_profile.visible = not ch.is_empty()
	main._npc_codex_id = str(ch.get("id", ""))
	main._npc_codex_btn.visible = main._npc_codex_id != ""
	if ch.is_empty():
		return
	main._npc_faction.add_child(main._CHAR_ART.faction_chip(ch))
	var ident: String = main._CHAR_ART.identity_line(ch)
	var life: String = main._CHAR_ART.life_line(ch)
	if life != "":
		ident = "%s　%s" % [ident, life]
	var ident_lbl: Label = main._CHAR_ART.label(ident, UiTheme.SIZE_BODY - 1, UiTheme.TEXT_DIM)
	main._npc_profile.add_child(ident_lbl)
	main._npc_profile.add_child(main._CHAR_ART.rule(0.40))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main._npc_profile.add_child(row)
	row.add_child(main._CHAR_ART.attr_block(ch, 150.0, 16))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(side)
	if not main._CHAR_ART.traits_of(ch).is_empty():
		side.add_child(main._CHAR_ART.trait_row(ch, 17))
	# 简介走人物志上屏文本层（按年份取可见段）；设定集原稿 bio_short 带着未来年号与结局，不上屏
	var bio: Label = main._CHAR_ART.label(main._CHAR_ART.codex_short(ch), UiTheme.SIZE_BODY - 1, UiTheme.TEXT)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_constant_override("line_spacing", 6)
	bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(bio)
	main._npc_profile.add_child(main._CHAR_ART.rule(0.40))


static func add_npc_button(main: Control, npc_id: String, fallback_name: String) -> void:
	# characters 线：设定集里有此人就排成人物卡（小立绘 + 五维迷你条，底行写身份），文案「在侧」「见」照旧
	var ch: Dictionary = GameManager.character_for_npc(npc_id) if main._CHAR_ART.present_here(npc_id) else {}
	# 人不在世就不在侧：林阿舶 1274 病故，此后泉州酒馆不再摆他（修前照摆，见面页抬头却写「卒于 1274」）
	if main._CHAR_ART.deceased(ch):
		return
	if not ch.is_empty():
		var info: VBoxContainer = main._person_slip(ch, fallback_name, "在侧")
		var foot: HBoxContainer = main._person_foot(info, main._CHAR_ART.codex_title(ch))
		main._slip_whole(main._slip_chip(foot, "见", main._on_meet_npc.bind(npc_id, fallback_name)))
		return
	var slip: VBoxContainer = main._slip_body()
	main._slip_title(slip, fallback_name, "在侧")
	main._slip_whole(main._slip_chip(main._slip_row(slip), "见", main._on_meet_npc.bind(npc_id, fallback_name)))


static func on_meet_npc(main: Control, npc_id: String, fallback_name: String) -> void:
	main._show_npc_mode(npc_id, fallback_name)


static func show_npc_mode(main: Control, npc_id: String, fallback_name: String) -> void:
	main.investigation_mode.visible = false
	main.npc_mode.visible = true

	var npc_data := {}
	for n in GameManager.npcs_data.get("npcs", []):
		if n.get("id") == npc_id:
			npc_data = n
			break

	var n_name := str(npc_data.get("name", fallback_name))
	main.npc_name_lbl.text = n_name
	var spoken := str(NPC_GREETING.get(npc_id, ""))
	if spoken == "":
		spoken = str(npc_data.get("function", "这人看了你一眼，没先开口。"))
	# 立绘以 characters.json 的 portrait 为准（缩到框里的尺寸、带 mipmap）；查无此人或缺图时回落旧的 sprite_ 图
	var ch: Dictionary = GameManager.character_for_npc(npc_id) if main._CHAR_ART.present_here(npc_id) else {}
	var tex: Texture2D = main._CHAR_ART.thumb(ch, Vector2i(256, 320)) if not ch.is_empty() else null
	if tex == null:
		var tex_path := "res://assets/sprite_" + npc_id.replace("pilot_", "").replace("merchant_", "") + ".png"
		tex = GameManager.load_texture(tex_path)
	main.npc_portrait.texture = tex
	main.npc_portrait.get_parent().visible = main.npc_portrait.texture != null
	var plate_name := main.npc_portrait.get_parent().get_node_or_null("NamePlate/Name") as Label
	if plate_name != null:
		plate_name.text = n_name
		plate_name.add_theme_font_override("font", main._CHAR_ART.title_font_for(n_name))
	main._fill_npc_profile(ch)
	main._CHAR_ART.note_met(str(ch.get("id", "")))

	for child in main.npc_actions.get_children():
		child.queue_free()

	main.npc_dialog_lbl.text = spoken
	main._npc_speech = main.npc_dialog_lbl
	# 纸笺左齐，与正文、五维栏同一条左轴（原先居中，见面页两套对齐轴；第 2 轮美术 minor 11）
	main._begin_benches(main.npc_actions)
	if main._slip_host is HFlowContainer:
		(main._slip_host as HFlowContainer).alignment = FlowContainer.ALIGNMENT_BEGIN
	var intel: VBoxContainer = main._slip_body()
	main._slip_title(intel, "行情", "邻座牙人")
	main._slip_whole(main._slip_chip(main._slip_row(intel), "打听", main._on_npc_intel.bind(n_name)))
	if npc_id == "customs_official":
		var bribe: VBoxContainer = main._slip_body()
		main._slip_title(bribe, "疏通", "蒲家留意　减 15")
		# 花钱的动作不做整卡可点，免得点卡误塞了钱
		main._slip_chip(main._slip_row(bribe), "塞　50", main._on_npc_bribe.bind(n_name), true)
	main._end_benches()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.npc_actions.add_child(spacer)
	var leave_btn := Button.new()
	leave_btn.text = "离开"
	leave_btn.custom_minimum_size = Vector2(160, 42)
	leave_btn.pressed.connect(main._on_npc_leave)
	main.npc_actions.add_child(leave_btn)
	UiTheme.style_leave_button(leave_btn)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


static func set_npc_speech(main: Control, text: String) -> void:
	if main._npc_speech != null:
		main._npc_speech.text = text


static func on_npc_intel(main: Control, n_name: String) -> void:
	var heard := UiTheme.plain_log(main._gather_price_intel(GameState.last_port))
	main._set_npc_speech("%s压低声音说。\n\n%s" % [n_name, heard.trim_prefix(BENCH_LEAD)] if heard.begins_with(BENCH_LEAD) else NO_INTEL % n_name)


static func on_npc_bribe(main: Control, n_name: String) -> void:
	if GameState.spend_money(50):
		GameState.pu_attention = maxi(0, GameState.pu_attention - 15)
		main.update_status_panel()
		main._set_npc_speech("%s颠了颠手里的碎银：「算你懂事。近来风声紧，自己当心。」" % n_name)
	else:
		main._set_npc_speech("%s满脸鄙夷：「就这点钱也想打通关节？」" % n_name)


static func on_npc_leave(main: Control) -> void:
	main.npc_mode.visible = false
	main.investigation_mode.visible = true


const NPC_GREETING := {
	"customs_official": "小吏把册子掀开一条缝，眼皮都没抬。「验引、呈报、修埠，都在这案上。有话就说。」",
	"merchant_lin": "林阿舶用指甲敲了敲账簿。「舱位、脚钱、货损，一样一样算。你叔父那笔，我还记着。」",
	"pilot_ana": "阿那望了一眼外海的水色。「潮声不对就别嘴硬。要问航路，就问。」",
}


## 见面册打听由见面的人自己说（复刻设计 §8.7：「某人压低声音说。」下面是行情那一句）。_gather_price_intel 回的是酒馆长凳那句，
## 带着「邻座的牙人压低声音：」领起——原样搬来就成了「林阿舶压低声音说。」下面又一个牙人压低声音，市舶司里也冒出邻座。
## on_npc_intel 去掉这截领起；酒馆长凳上的「打听」照旧是邻座牙人那句。
const BENCH_LEAD := "邻座的牙人压低声音："

## 打听不出行情（围城港牙行闭门、各港都没有价差）时 _gather_price_intel 回的是酒馆旁白「【闲谈】几个老水手翻来覆去只讲当年的风暴，
## 没打听出新行情。」——那是长凳上听来的，不是见面这人的话。修前照样套「某人压低声音说。」，福州 1276-10 围城时
## 市舶司小吏就压低声音讲「几个老水手……」；现由他自己说一句没有。
const NO_INTEL := "%s摇了摇头：「眼下没什么新行情。」"
