extends SceneTree
## lane-w53-4：终局港页的航海札记——边记攒多了，岸带底下的动作行（重读结局、航海日志、人物志）不出画。
## 实测（排好版、过几帧后量布局；headless 也跑，带窗口 DISPLAY=:2 同样可跑）：1280×720 与 4:3 加高画布 1280×960，
## 五档边记——一条 / 剧情令牌四枚 / 剧情令牌八枚（全笺七行，修前修后都全显）/ 全部剧情令牌（不拓碑，札记折四五行）/
## 全部剧情令牌加十四处寺观拓本——在福州落「纲首」、合上结局册页后：
##   1. 动作行（ShoreActions）整排在画内，「重读结局」「航海日志」两钮在画内；
##   2. 岸带不越过定高 360；
##   3. 札记笺折后不超过七行不收滚动框（与修前同样全显），超过七行收进滚动框（EpilogueScroll）。
## 旧病（回退即红）：Main._epilogue_slip 按条数定滚不滚，「札记：」一条把全部边记串成一行、折成多行也只算一条，
## 寺观拓本还带整段拓文——1280×720 下八枚令牌岸带长到 374，十九条边记动作行底到 730，再拓两处整排出画（726–778），
## 十四处拓本札记笺底到 966。
## 用法：godot --headless --path . -s res://tools/qa_w53_4_epilogue_fit_probe.gd

const VIEWS := [Vector2i(1280, 720), Vector2i(1280, 960)]
const TIERS := ["light", "mid4", "mid8", "story", "heavy"]
const BAND_H := 360.0
const ROWS_MAX := 7

var fails := 0
var cases := 0
var done := 0
var _gs
var _gm
var _cal
var _main


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	call_deferred("_boot")


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _boot() -> void:
	var root: Window = get_root()
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	if _gs == null or _gm == null or _cal == null:
		push_error("autoload missing")
		quit(1)
		return
	var cine = load("res://scripts/cutscene/Cinematics.gd")
	cine.enabled = false
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	await _frames(8)
	for view in VIEWS:
		root.size = view
		await _frames(4)
		for tier in TIERS:
			await _case(view, tier)
	# 每档都要真跑完（某档半路出脚本错只中止那一档的函数，不能因此照报通过）
	_expect(done == VIEWS.size() * TIERS.size(), "各画布各档都跑完（%d / %d）" % [done, VIEWS.size() * TIERS.size()])
	print("QA_W53_4_EPILOGUE_FIT cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _case(view: Vector2i, tier: String) -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1285, "month": 2, "day": 2})
	_gs.loaded_with_beats = true
	_main._beats = null
	_gs.identity = "merchant"
	var toks: Array = []
	_collect(_gm.scenes_data.get("scenes", []), "ledger_note", toks)
	match tier:
		"light":
			_gs.add_ledger_note("崖山外海掉头")
		"mid4", "mid8":
			for t in toks.slice(0, 4 if tier == "mid4" else 8):
				_gs.add_ledger_note(str(t))
		"story":
			for t in toks:
				_gs.add_ledger_note(str(t))
		_:
			for t in toks:
				_gs.add_ledger_note(str(t))
			for d in _gm.discoveries_data.get("discoveries", []):
				_gs.record_discovery(str(d.get("id", "")))
				_gs.add_ledger_note(_main._temple_rub_note(str(d.get("name", "")), str(d.get("historical_hook", ""))))
	_gs.last_port = "fuzhou"
	_main.load_scene("fuzhou")
	await _frames(2)
	_main._on_gangshou_end()
	await _frames(2)
	_main._confirm_chapter_sheet()
	await _frames(6)
	var vp: Vector2 = get_root().get_visible_rect().size
	var tag := "%d×%d %s" % [view.x, view.y, tier]
	var band := _main.find_child("ShoreBand", true, false) as Control
	var acts := _main.find_child("ShoreActions", true, false) as Control
	var slip := _main.find_child("EpilogueSlip", true, false) as Control
	if band == null or acts == null or slip == null or _gs.ended != "纲首":
		_expect(false, "%s：终局港页排出岸带、动作行、札记笺（终局「%s」）" % [tag, _gs.ended])
		return
	var reread := _button(acts, "重读结局")
	var logbook := _button(acts, "航海日志")
	var ar := acts.get_global_rect()
	_expect(ar.position.y >= 0.0 and ar.end.y <= vp.y and reread != null and logbook != null
			and reread.get_global_rect().end.y <= vp.y and logbook.get_global_rect().end.y <= vp.y,
		"%s：动作行整排在画内，「重读结局」「航海日志」可点（动作行 %d–%d，画布高 %d）" % [tag, int(ar.position.y), int(ar.end.y), int(vp.y)])
	_expect(band.size.y <= BAND_H + 0.5,
		"%s：岸带不越过定高 %d（现 %d，札记笺高 %d）" % [tag, int(BAND_H), int(band.size.y), int(slip.size.y)])
	var rows := 0
	for line in _gs.epilogue_lines():
		var para := TextParagraph.new()
		para.add_string(str(line), UiTheme.font(), 16)
		para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		para.width = 724.0
		rows += maxi(1, para.get_line_count())
	var scrolled: bool = slip.find_child("EpilogueScroll", true, false) != null
	_expect(scrolled == (rows > ROWS_MAX),
		"%s：札记折后 %d 行，%s（滚动框 %s）" % [tag, rows, "超过七行收进滚动框" if rows > ROWS_MAX else "七行以内全显、不收滚动框", scrolled])
	done += 1


func _button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node as Button
	for c in node.get_children():
		var b := _button(c, text)
		if b != null:
			return b
	return null


func _collect(node, key: String, out: Array) -> void:
	if node is Dictionary:
		for k in node.keys():
			if str(k) == key and node[k] is String:
				if not (node[k] in out):
					out.append(node[k])
			else:
				_collect(node[k], key, out)
	elif node is Array:
		for v in node:
			_collect(v, key, out)
