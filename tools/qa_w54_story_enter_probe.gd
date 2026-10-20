extends SceneTree
## lane-w54-story：终局抉择页回车不替人按（拍板 20g 同口径：花日子花钱、改身份倾向的钮挂 no_enter，回车跳过）。
## 港页回车走 Main._unhandled_input → _activate_first_choice：choices_container 里第一枚可按、没挂 no_enter 的钮当场按下。
## 修前三页的第一枚都是终身抉择，读完正文顺手一按回车（册页、过场、序章对白都是回车往下走）就替人选了：
##   A 崖山页「把粮与硫黄交上去」：走五日、名声 +12、海商信用 −30，当场落「海上宋鬼」——一局就此了结；
##     掉头那枚也一样（名声 −6、士气 −10、崖山卡不再挂），「上船同去」则直接开打崖山一仗。
##   B 辞呈页「回头。再上一疏求还。」：走七日、立 petitioned_return、士人倾向 +4，辞呈三条路就此定了。
##   C 泉州征船名册（对峙期市舶司页）「船借张世杰」：交出最小一条船（只一条船时水粮减半）、立 sided_zhang——
##     蒲家那条路（泉州抽解八折、「泉州蒲氏的船」结局）从此走不了。
##   D 剧情幕岔路（data/scenes.json 一幕可见的真选项两条以上，翻页「…………」不算）：序章「拿起货引，跟阿那走泉州船场 /
##     接过策问题目，跟家丁回祠堂」、林阿舶账房、兴化来的信……选项都带身份倾向、旗标或钱。酒棚对白页一路回车往下翻，
##     翻到抉择页再一按就替人选了第一条（1268 殿试结算打平时还按 chose_sea_first / chose_land_first 定身份）。
## 每页先断那几枚钮都在（不空判），再按一次真回车（root.push_input）、再直调一次 _activate_first_choice，
## 断日子不走、旗不立、终局不落、船与水粮不动；反向基：点钮本身照旧作数（崖山落「海上宋鬼」、辞呈立旗、名册立旗）。
## D 按数据逐幕跑（新幕自动入验），断页不动、旗 / 钱 / 名声 / 倾向 / 人脉 / 信用不动；反向基：只有一条路的幕
## （对白翻页、「继续」带旗那种）回车照旧往下走、效果照记——回车仍是「下一步」。
##   E 藏起来的旧钮：choices_container 只在 _enter_panel_mode 换页时清，港页（_setup_port_mode）与见面页只把它所在的
##     剧情面板藏起来，上一页的钮还挂在里面。回车照「第一枚可按」去按，按的是看不见的旧钮：晋升过场「第三章：册上的纲首」
##     点「收下这个称呼…回港上」回到泉州港页，再按回车就把那一钮再按一遍——名声 +8 一按一次；酒馆「旧事」追问在港页 /
##     见面页上被回车替人问掉。断：港页与见面页按回车，旧钮一枚不按（名声、旗、日志、页都不动）；反向基：过场页本身回车照旧
##     按下「回港上」、效果只记一次。
## 用法：godot --headless --path . -s res://tools/qa_w54_story_enter_probe.gd（经门锁跑）
## 末行 W54_STORY_ENTER cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_yashan()
	await _b_resign()
	await _c_standoff()
	await _d_scene_forks()
	await _e_hidden_stale()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_STORY_ENTER cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 一按回车：真按键走一遍 Main._unhandled_input，再直调一次 _activate_first_choice（按键在 headless 下若没落到
## _unhandled_input，直调照样把「回车会按哪一枚」测到）
func _enter() -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ENTER
		k.physical_keycode = KEY_ENTER
		k.pressed = pressed
		root.push_input(k)
	await process_frame
	_main._activate_first_choice()
	await process_frame


func _button(prefix: String) -> Button:
	for c in _main.choices_container.get_children():
		if c is Button and str((c as Button).text).begins_with(prefix):
			return c
	return null


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame


func _fresh(y: int, m: int, port: String) -> void:
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_cal.from_dict({"year": y, "month": m, "day": 2})
	_gs.last_port = port
	_gs.fame = 20
	_gs.money = 3000
	_fleet.water = 120
	_fleet.food = 120


# ── A 崖山页 ─────────────────────────────────────────────

func _a_yashan() -> void:
	print("── A 崖山页：回车不替人交粮、掉头、上船")
	_fresh(1279, 2, "guangzhou")
	_gs.identity = "merchant"
	_main.load_scene("guangzhou")
	await process_frame
	_expect("special_yashan" in _main.shore_hand, "祥兴二年二月海商在广州：岸上挂崖山卡（名单 %s）" % [_main.shore_hand])
	_main._on_facility_pressed({"id": "special_yashan"})
	await process_frame
	var join := _button("把粮与硫黄交上去")
	var turn := _button("不上前")
	_expect(join != null and turn != null, "崖山页有「把粮与硫黄交上去」「不上前…」两枚钮")
	var day0: int = _cal.absolute_day()
	var fame0: int = _gs.fame
	var kids0: int = _main.get_child_count()
	await _enter()
	_expect(_gs.ended == "" and _cal.absolute_day() == day0 and _gs.fame == fame0
			and not _gs.has_flag("yashan_turned_back") and _main.get_child_count() == kids0
			and _main.current_scene_id == "guangzhou" and _button("把粮与硫黄交上去") != null,
		"崖山页按回车：不落终局、日子不走、名声不动、不掉头、不开打（终局「%s」、走了 %d 日、名声 %d→%d、掉头旗 %s、子节点 %d→%d）" % [
			_gs.ended, _cal.absolute_day() - day0, fame0, _gs.fame, str(_gs.has_flag("yashan_turned_back")),
			kids0, _main.get_child_count()])
	# 反向基：重开一页，点钮本身照旧作数
	await _drop_sheet()
	_fresh(1279, 2, "guangzhou")
	_gs.identity = "merchant"
	_main.load_scene("guangzhou")
	_main._on_facility_pressed({"id": "special_yashan"})
	await process_frame
	join = _button("把粮与硫黄交上去")
	if join != null:
		join.pressed.emit()
		await process_frame
	_expect(_gs.ended == "海上宋鬼", "反向基：点「把粮与硫黄交上去」照旧落「海上宋鬼」（实得「%s」）" % _gs.ended)
	await _drop_sheet()


# ── B 辞呈页 ─────────────────────────────────────────────

func _b_resign() -> void:
	print("── B 辞呈页：回车不替人定辞呈三条路")
	_fresh(1275, 12, "fuzhou")
	_gs.identity = "scholar"
	_gs.player_name = "陈文龙"
	_gs.set_flag("renamed_wenlong")
	_gs.set_flag("vice_councillor")
	_main.load_scene("fuzhou")
	await process_frame
	_expect("special_resign_1275" in _main.shore_hand, "德祐元年腊月士人线：岸上挂辞呈卡（名单 %s）" % [_main.shore_hand])
	_main._on_facility_pressed({"id": "special_resign_1275"})
	await process_frame
	_expect(_button("回头。") != null and _button("不回头。") != null and _button("车转向南") != null,
		"辞呈页有「回头」「不回头」「车转向南」三枚钮")
	var day0: int = _cal.absolute_day()
	var tend0: int = _gs.scholar_tendency
	await _enter()
	var picked := []
	for f in ["petitioned_return", "quiet_return", "late_defection"]:
		if _gs.has_flag(f):
			picked.append(f)
	var host = _main.get("_chapter_host")
	_expect(picked.is_empty() and _cal.absolute_day() == day0 and _gs.scholar_tendency == tend0
			and _gs.identity == "scholar" and _gs.money == 3000 and (host == null or not is_instance_valid(host)),
		"辞呈页按回车：三条路一条没定（立旗 %s）、日子不走（走了 %d 日）、士人倾向不动（%d→%d）、身份仍士人（%s）、钱不动（%d）" % [
			str(picked), _cal.absolute_day() - day0, tend0, _gs.scholar_tendency, _gs.identity, _gs.money])
	# 反向基：重开一页（修前回车已替人定了一条路、弹了册页，先收掉），点钮本身照旧作数
	await _drop_sheet()
	for f in ["petitioned_return", "quiet_return", "late_defection"]:
		_gs.flags.erase(f)
	_main.load_scene("fuzhou")
	_main._on_facility_pressed({"id": "special_resign_1275"})
	await process_frame
	var quiet := _button("不回头。")
	if quiet != null:
		quiet.pressed.emit()
		await process_frame
	_expect(_gs.has_flag("quiet_return"), "反向基：点「不回头。走海路回兴化。」照旧立 quiet_return")
	await _drop_sheet()


# ── C 泉州征船名册 ───────────────────────────────────────

func _c_standoff() -> void:
	print("── C 泉州征船名册：回车不替人借船、站队、出港")
	_fresh(1276, 6, "quanzhou")
	_gs.identity = "merchant"
	_main.load_scene("quanzhou_yamen")
	await process_frame
	var zhang := _button("船借张世杰")
	_expect(zhang != null and _button("跟蒲家") != null and _button("今夜出港") != null,
		"景炎元年六月泉州市舶司页挂征船名册三枚钮（借船 %s）" % str(zhang != null))
	var ships0: int = _fleet.ships.size()
	var water0: int = _fleet.water
	var food0: int = _fleet.food
	await _enter()
	var sided := []
	for f in ["sided_zhang", "sided_pu", "fled_quanzhou"]:
		if _gs.has_flag(f):
			sided.append(f)
	_expect(sided.is_empty() and _fleet.ships.size() == ships0 and _fleet.water == water0 and _fleet.food == food0,
		"征船名册按回车：不站队（立旗 %s）、船不交出（%d→%d 条）、水粮不分（水 %d→%d、粮 %d→%d）" % [
			str(sided), ships0, _fleet.ships.size(), water0, _fleet.water, food0, _fleet.food])
	# 反向基：重开一页（修前回车已替人站了队、名册三枚不再挂，先摘旗），点钮本身照旧作数
	for f in ["sided_zhang", "sided_pu", "fled_quanzhou"]:
		_gs.flags.erase(f)
	_main.load_scene("quanzhou_yamen")
	await process_frame
	var pu := _button("跟蒲家")
	if pu != null:
		pu.pressed.emit()
		await process_frame
	_expect(_gs.has_flag("sided_pu"), "反向基：点「跟蒲家」照旧立 sided_pu")
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})


# ── D 剧情幕岔路 ─────────────────────────────────────────

## 一幕可见的真选项（翻页不算）有几条：照 Main.show_choices 的可见口径
func _forks(sc: Dictionary) -> int:
	var n := 0
	for c in sc.get("choices", []):
		if typeof(c) != TYPE_DICTIONARY or not _gs.choice_visible(c):
			continue
		if not _main._is_page_turn(str((c as Dictionary).get("label", "继续"))):
			n += 1
	return n


func _story_snap() -> Dictionary:
	return {
		"page": _main.current_scene_id, "flags": _gs.flags.duplicate(), "money": _gs.money, "fame": _gs.fame,
		"sea": _gs.sea_tendency, "scholar": _gs.scholar_tendency, "home": _gs.hometown_tendency,
		"network": _gs.network, "credit": _gs.merchant_credit, "day": _cal.absolute_day(),
	}


func _fresh_story() -> void:
	_fresh(1255, 3, "quanzhou")
	_gs.money = 1000
	_gs.fame = 0


func _d_scene_forks() -> void:
	print("── D 剧情幕岔路：回车不替人选第一条")
	var gm: Node = root.get_node_or_null("GameManager")
	var tried: Array = []
	var bad: Array = []
	for raw in gm.scenes_data.get("scenes", []):
		var sc: Dictionary = raw
		var sid := str(sc.get("id", ""))
		if str(sc.get("type", "")) in ["title", "port"]:
			continue
		_fresh_story()
		if not _gs.scene_unlocked(sc) or _forks(sc) < 2:
			continue
		_main.load_scene(sid)
		await process_frame
		var shown := 0
		for c in _main.choices_container.get_children():
			if c is Button and not (c as Button).disabled:
				shown += 1
		if _main.current_scene_id != sid or shown < 2:
			bad.append("%s（没摆出岔路：页 %s、钮 %d）" % [sid, _main.current_scene_id, shown])
			continue
		tried.append(sid)
		var before := _story_snap()
		await _enter()
		var after := _story_snap()
		if after != before:
			var moved: Array = []
			for k in before.keys():
				if str(before[k]) != str(after[k]):
					moved.append("%s %s→%s" % [k, str(before[k]), str(after[k])])
			bad.append("%s：%s" % [sid, "、".join(moved)])
	_expect(tried.size() >= 10 and "cg_decision" in tried,
		"岔路幕逐幕入验 %d 幕（含序章抉择 cg_decision）：%s" % [tried.size(), str(tried)])
	_expect(bad.is_empty(), "岔路幕按回车：页不动、旗 / 钱 / 名声 / 倾向 / 人脉 / 信用 / 日子都不动（%d 幕不合：%s）" % [bad.size(), str(bad)])
	# 反向基：只有一条路的幕回车照旧往下走、效果照记
	_fresh_story()
	_main.load_scene("cg_servant_speak")
	await process_frame
	await _enter_key()
	_expect(_main.current_scene_id == "cg_decision", "反向基：对白翻页「…………」回车照旧翻到抉择页（现页 %s）" % _main.current_scene_id)
	_fresh_story()
	_main.load_scene("sea_path_start")
	await process_frame
	var sea0: int = _gs.sea_tendency
	await _enter_key()
	_expect(_main.current_scene_id == "sea_path_ledger" and _gs.sea_tendency == sea0 + 3 and _gs.has_flag("lin_sea_route_open"),
		"反向基：只一条路的「泉州码头，夜潮将至」回车照旧往下走、效果照记（现页 %s、下海倾向 %d→%d、旗 %s）" % [
			_main.current_scene_id, sea0, _gs.sea_tendency, str(_gs.has_flag("lin_sea_route_open"))])
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})


## 只按一次真回车（反向基用：单路幕一按翻一页，不叠直调）
func _enter_key() -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ENTER
		k.physical_keycode = KEY_ENTER
		k.pressed = pressed
		root.push_input(k)
	await process_frame


# ── E 藏起来的旧钮 ───────────────────────────────────────

## 序章与泉州节拍都演过的局面（拍账记满）：进泉州港不再就地演节拍幕
func _fresh_past_prologue() -> void:
	_fresh(1262, 4, "quanzhou")
	for e in _main._beats_book().entries():
		_gs.beat_mark(str(e))


func _e_hidden_stale() -> void:
	print("── E 港页 / 见面页按回车：不按上一页藏起来的旧钮")
	# E1 晋升过场「回港上」之后的泉州港页
	_fresh_past_prologue()
	_gs.chapter = 3
	_main.load_scene("chapter3_gangshou")
	await process_frame
	var take := _button("收下这个称呼")
	_expect(take != null, "第三章晋升过场页有「收下这个称呼…」一钮")
	var fame0: int = _gs.fame
	if take != null:
		take.pressed.emit()
		await process_frame
	var fame1: int = _gs.fame
	_expect(_main.current_scene_id == "quanzhou" and _main.port_mode.visible and fame1 == fame0 + 8 and _gs.has_flag("chapter3_seen"),
		"点「收下这个称呼」回泉州港页、名声 +8、立 chapter3_seen（页 %s，名声 %d→%d）" % [_main.current_scene_id, fame0, fame1])
	await _enter()
	await _enter()
	_expect(_gs.fame == fame1 and _main.current_scene_id == "quanzhou" and _main.port_mode.visible,
		"泉州港页按两回回车：过场那一钮不再被按（名声 %d→%d，页 %s）" % [fame1, _gs.fame, _main.current_scene_id])
	# E2 酒馆「旧事」追问：离开酒馆回港页、见面页上按回车都不替人问掉
	_fresh_past_prologue()
	_gs.set_flag("chen_line_open")
	_main.load_scene("quanzhou_tavern")
	await process_frame
	_expect(_button("追问兴化来人的下落") != null, "泉州酒馆有「旧事」追问一钮")
	_main.load_scene("quanzhou")
	await process_frame
	var logs0: int = (_main.get("_log_lines") as PackedStringArray).size()
	await _enter()
	_expect(not _gs.has_flag("hook_xinghua_asked") and _main.current_scene_id == "quanzhou",
		"离开酒馆回到港页按回车：「追问兴化来人的下落」没被替人问掉（旗 %s，页 %s）" % [str(_gs.has_flag("hook_xinghua_asked")), _main.current_scene_id])
	_main.load_scene("quanzhou_tavern")
	await process_frame
	_main._on_meet_npc("merchant_lin", "林阿舶")
	await process_frame
	await _enter()
	_expect(not _gs.has_flag("hook_xinghua_asked") and _main.npc_mode.visible,
		"酒馆里见林阿舶（见面页）按回车：「旧事」追问没被替人问掉、见面页还在（旗 %s）" % str(_gs.has_flag("hook_xinghua_asked")))
	# 反向基：过场页本身回车照旧按「回港上」，效果只记一次
	_fresh_past_prologue()
	_gs.chapter = 3
	_main.load_scene("chapter3_gangshou")
	await process_frame
	var f0: int = _gs.fame
	await _enter_key()
	_expect(_main.current_scene_id == "quanzhou" and _gs.fame == f0 + 8,
		"反向基：晋升过场页按回车照旧「回港上」、名声只 +8 一回（页 %s，名声 %d→%d）" % [_main.current_scene_id, f0, _gs.fame])
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
