extends SceneTree
## 无界面驱动 P7：开局落港、节拍不连播、流求入港不演正文、效果进账、旅店、终局。
## 跑法：godot --headless --path . -s res://tools/p7_smoke.gd
## -s 入口在编译期看不到自动加载名，单例一律在 _initialize 之后从根节点取。

var _fails: Array = []
var _gs
var _fleet
var _gm


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	var main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("FAIL ", msg)


func _ok(msg: String) -> void:
	print("OK   ", msg)


func _button_with_text(root_node: Node, text: String) -> Button:
	var hits: Array = []
	_collect_buttons(root_node, text, hits)
	if hits.is_empty():
		return null
	return hits[0]


func _collect_buttons(n: Node, text: String, hits: Array) -> void:
	# 港口面板用 queue_free 换按钮，同一帧里旧按钮还在树上。玩家要等这一帧画完才看不见它。
	if n.is_queued_for_deletion():
		return
	if n is Button and (n as Button).text == text:
		hits.append(n)
	for c in n.get_children():
		_collect_buttons(c, text, hits)


func _run(main) -> void:
	# Main._ready 里 call_deferred(start_game)，空等几帧直到开场场景写上。
	for _i in 8:
		if str(main.current_scene_id) != "":
			break
		await process_frame

	if str(main.current_scene_id) != "cg_title":
		_fail("开局场景不是 cg_title，而是 %s" % str(main.current_scene_id))
	else:
		_ok("开局停在 cg_title")

	main.load_scene("sea_path_start")
	var sail_btn := _button_with_text(main, "去林阿舶账房打点出港")
	if sail_btn == null:
		_fail("海路开场没有出港选项")
	else:
		sail_btn.pressed.emit()
		if str(main.current_scene_id) != "quanzhou":
			_fail("海路选项没有进入泉州，而是 %s" % str(main.current_scene_id))
		elif not main.get_node("HBoxContainer/CenterArea/PortMode").visible:
			_fail("泉州不是港口界面")
		else:
			_ok("海路落入泉州港口")
		if int(_gs.sea_tendency) < 3:
			_fail("海路倾向没有加上，现为 %d" % int(_gs.sea_tendency))
		else:
			_ok("海路倾向 %d" % int(_gs.sea_tendency))

	var beat := _button_with_text(main, "有人找你")
	if beat == null:
		_fail("泉州没有「有人找你」")
	else:
		beat.pressed.emit()
		if str(main.current_scene_id) != "monk":
			_fail("节拍没有进入 monk，而是 %s" % str(main.current_scene_id))
		else:
			_ok("节拍进入开元寺")
		if not ("monk" in _gs.seen_scenes):
			_fail("monk 未记入 seen_scenes")
		var choice := _button_with_text(main, "收下旧纸和拓包，答应复核残碑")
		if choice == null:
			_fail("寺里没有第一个选项")
		else:
			choice.pressed.emit()
			if str(main.current_scene_id) != "quanzhou":
				_fail("寺里的选项连进了下一场，现为 %s" % str(main.current_scene_id))
			elif _button_with_text(main, "有人找你") != null:
				_fail("同一次回港又弹出了下一条节拍")
			else:
				_ok("节拍在 merchant 前停下，回港不连播")

	main.load_scene("ryukyu")
	if str(main.current_scene_id) != "ryukyu":
		_fail("没能进入流求")
	elif not main.get_node("HBoxContainer/CenterArea/PortMode").visible:
		_fail("流求入港演成了正文")
	else:
		_ok("流求入港是港口界面")
	var reef := _button_with_text(main, "有人找你")
	if reef == null:
		_fail("流求没有礁口节拍")
	else:
		reef.pressed.emit()
		var title := ""
		var title_node: Node = main.get_node_or_null("HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/SceneTitle")
		if title_node != null:
			title = title_node.text
		if title != "流求海面北缘":
			_fail("礁口节拍标题不是流求海面北缘，而是 %s" % title)
		else:
			_ok("礁口节拍才演正文")

	main.load_scene("quanzhou_inn")
	var inn_title := ""
	var inn_node: Node = main.get_node_or_null("HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/SceneTitle")
	if inn_node != null:
		inn_title = inn_node.text
	if "旅店" not in inn_title:
		_fail("旅店没有打开，标题为 %s" % inn_title)
	else:
		_ok("旅店可进：%s" % inn_title)

	var guild = _gm.load_texture("res://assets/icon_guild.png")
	var temple = _gm.load_texture("res://assets/icon_temple.png")
	var academy = _gm.load_texture("res://assets/icon_academy.png")
	var residence = _gm.load_texture("res://assets/icon_residence.png")
	if guild == null or temple == null or academy == null or residence == null:
		_fail("JPEG 改名的图标加载失败 guild=%s temple=%s academy=%s residence=%s" % [guild, temple, academy, residence])
	else:
		_ok("四张 JPEG 内容的图标能加载")

	_gs.merchant_credit = 0
	if int(_gs.borrow_ceiling()) != 3000:
		_fail("信用 0 时天花板 %d" % int(_gs.borrow_ceiling()))
	_gs.merchant_credit = 100
	if int(_gs.borrow_ceiling()) != 5000:
		_fail("信用 100 时天花板 %d" % int(_gs.borrow_ceiling()))
	_gs.merchant_credit = -100
	if int(_gs.borrow_ceiling()) != 2000:
		_fail("信用 -100 时天花板 %d" % int(_gs.borrow_ceiling()))
	else:
		_ok("赊贷天花板 0/100/-100 → 3000/5000/2000")
	_gs.merchant_credit = 0

	var before_w := int(_fleet.water)
	var before_f := int(_fleet.food)
	var unknown: Array = main.apply_effects({"supplies": 3, "discovery": "旧避风澳", "chapter": 9, "flag": "smoke_flag"})
	if int(_fleet.water) != before_w + 3 or int(_fleet.food) != before_f + 3:
		_fail("补给没有各加 3，水 %d→%d 粮 %d→%d" % [before_w, int(_fleet.water), before_f, int(_fleet.food)])
	elif not _gs.has_found("nameless_shelter_bay"):
		_fail("旧避风澳没有记入发现录")
	elif int(_gs.chapter) != 1:
		_fail("chapter 效果仍能跳章，现为 %d" % int(_gs.chapter))
	elif not ("chapter" in unknown):
		_fail("未知键 chapter 没有返回")
	elif not _gs.has_flag("smoke_flag"):
		_fail("旗标没有写下")
	else:
		_ok("补给、发现、旗标落地，chapter 被拒绝")

	_gs.chapter = 4
	_gs.visit_port("champa")
	_gs.record_discovery("heishui_gou")
	_gs.record_discovery("penghu_stone_wall")
	_gs.discoveries_reported = ["nameless_shelter_bay", "heishui_gou", "penghu_stone_wall"]
	_gs.sea_tendency = 8
	_gs.scholar_tendency = 1
	main.load_scene("champa")
	if not _gs.has_flag("chronicle_closed"):
		_fail("占城入港没有触发终局")
	elif int(_gs.chapter) != 4:
		_fail("终局把章节推进了")
	elif str(_gs.chronicle_branch()) != "sea":
		_fail("终局分流不是海路，而是 %s" % str(_gs.chronicle_branch()))
	else:
		_ok("终局触发且停在第四章·海路")

	if _fails.is_empty():
		print("P7_SMOKE_OK")
		quit(0)
	else:
		print("P7_SMOKE_FAIL %d" % _fails.size())
		quit(1)
