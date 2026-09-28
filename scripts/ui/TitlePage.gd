extends RefCounted
## 标题页 / 开场（TitlePage）：卷首标题页与四方沙盘（type=title 各页）的版面、「开卷 / 翻页」路由、「重看开场」「人物志」「续卷」
## 三个副钮的显隐与标题演出（TitleStage.present）；开卷 / 入酒棚的序章纪实题签；开场过场的起播、演完重演标题演出、「重看开场」回调。
## Lane main11 从 Main.gd 原样搬出（第十一刀，_play_opening / _on_opening_finished / _on_rewatch_opening 与
## _setup_title_mode / _on_start_game_pressed 两段，5 支）。
## Main 留同名同签名的一行转发（_on_start_game_pressed 是协程，转发带 await），调用点、信号目标都不动：_load_scene_inner 仍调
## Main._setup_title_mode；「开卷」钮仍 bind 到 Main._on_start_game_pressed，「重看开场」钮仍接 Main._on_rewatch_opening，
## 开场过场的 finished 仍一次性接 Main._on_opening_finished；start_game 仍调 Main._play_opening。
## 留在 Main 的：start_game / _on_monthly_notice（开局流程，不属页面）、title_button_connected 与各标题页节点、_CS_PLAYER / _CINE /
## _TITLE_STAGE / _UI_TRANSITION、play_transition、load_scene，经 main 取；这里不存状态。
## 门禁 check_symbols 经 main_splits.txt 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


static func play_opening(main: Control, from_black := false) -> void:
	var p: Node = main._CS_PLAYER.play(main, main._CINE.OPENING, main._CINE.DATA, from_black)
	if p != null:
		p.connect("finished", main._on_opening_finished, CONNECT_ONE_SHOT)


## 开场演完（此刻全黑）：还停在标题页就把标题演出从头再来，黑幕退去时正好看见题名写出、印落下
static func on_opening_finished(main: Control) -> void:
	if not main.title_mode.visible:
		return
	var stage: Node = main.title_mode.get_node_or_null("TitleStage")
	if stage != null:
		stage.call("replay")


static func on_rewatch_opening(main: Control) -> void:
	main._play_opening(false)


static func setup_title_mode(main: Control, scene_data: Dictionary) -> void:
	main._show_strip(false)
	main._close_ledger()
	main.investigation_mode.visible = false
	main.port_mode.visible = false
	main.npc_mode.visible = false
	main.title_mode.visible = true

	main.main_title.text = scene_data.get("cg_title", "东亚海域立志传")
	# 长标题与分段副标题按宽换行居中（云端 c148/00b4）；盒宽与字号由 Main.tscn / 绢本主题定，不在此覆盖。
	main.main_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.sync_title_logo(main.main_title)
	main.sub_title.text = main._unescape_scene_text(str(scene_data.get("cg_sub", "")))
	main.sub_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if main.title_button_connected:
		for c in main.start_button.pressed.get_connections():
			main.start_button.pressed.disconnect(c.callable)

	var choices = scene_data.get("choices", [])
	var next_scene = "prologue_tabletop"
	if choices.size() > 0:
		main.start_button.text = choices[0].get("label", "开始旅程")
		next_scene = choices[0].get("next", "prologue_tabletop")

	main.start_button.pressed.connect(main._on_start_game_pressed.bind(next_scene))
	main.title_button_connected = true

	# 起始标题页：占位的「…………」换成「开卷」（路由照旧取 choices[0].next），另给「重看开场」；
	# 卷首四方沙盘的「…………」只改显示为「翻页」（数据与路由不动）。标题演出（书法写出、引首章、分段逐行洇出）见 TitleStage。
	var is_start: bool = main.current_scene_id == str(GameManager.scenes_data.get("start_scene", "cg_title"))
	if main.start_button.text.replace("…", "").strip_edges() == "":
		main.start_button.text = "开卷" if is_start else "翻页"
	main._rewatch_button.visible = is_start and main._CS_PLAYER.has_cutscene(main._CINE.OPENING, main._CINE.DATA)
	main._codex_title_button.visible = is_start and not GameManager.all_characters().is_empty()
	var has_save := false
	for slot in range(1, SaveLoad.SLOTS + 1):
		has_save = has_save or SaveLoad.has_save(slot)
	main._resume_button.visible = is_start and has_save
	main._rewatch_button.get_parent().visible = main._rewatch_button.visible or main._codex_title_button.visible or main._resume_button.visible
	main._TITLE_STAGE.present(main.title_mode, main.main_title, main.sub_title, [main.start_button, main._resume_button, main._rewatch_button, main._codex_title_button], is_start)


static func on_start_game_pressed(main: Control, next_scene: String) -> void:
	# 卷首「开卷」与沙盘末翻入酒棚：走论文纪实题签（UiTransition）；四方沙盘中间翻页仍靠 TitleStage 节奏，不加墨幕。
	# headless / 巡检下 play_transition 当帧直通，不拖门禁。
	var start_id := str(GameManager.scenes_data.get("start_scene", "cg_title"))
	var from_start: bool = main.current_scene_id == start_id
	var into_shed := str(next_scene).begins_with("cg_narrate")
	if from_start:
		await main.play_transition(main._UI_TRANSITION.prologue_open_title(), Calendar.get_date_string(),
			main.load_scene.bind(next_scene), "序")
	elif into_shed:
		await main.play_transition(main._UI_TRANSITION.prologue_shore_title(), Calendar.get_date_string(),
			main.load_scene.bind(next_scene), "序")
	else:
		main.load_scene(next_scene)
