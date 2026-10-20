extends SceneTree
## lane w54-siege：守城各页的钮回车不替人按（拍板 20g 同口径：花日子花钱、立旗、改身份倾向的钮挂 no_enter，回车跳过）。
## 港页回车走 Main._unhandled_input → _activate_first_choice：choices_container 里第一枚可按、没挂 no_enter 的钮当场按下。
## 修前守城六页的第一枚都是花钱或定剧情的钮，读完正文顺手一按回车（战报册页、过场、序章对白都是回车往下走）就替人按了：
##   A 衙门页「募兵 50 人」：花 500 钱募兵；石手军两枚（重编 / 解散）一样回车即定、改乡土 / 士人倾向。
##   B 市场页「屯粮 40」：花钱买米。
##   C 船屋页「加固城墙　加 20」：花钱修墙。
##   D 酒馆页第一封劝降书「斩正使…」：立斩使、士气 +10、名声 +5、札记「斩王刚中使」——收信那条路（犹疑旗）再走不了。
##   E 酒馆页第二封「焚书，斩使」：士气 +12、名声 +8、乡土倾向 −5。
##   F 第三阵前林华请命（认得他 / 不认得两式）：「你的缆绳系得好…」立 lin_hua_reminded、「让他去」，
##     第三枚「不去。关城门」立 cao_opened、丢三十石米——回车只按第一枚，但三枚都是一锤子的抉择。
## 每页先断那几枚钮都在（不空判），清掉键盘焦点（读完正文、没点过页上的钮），按一次真回车（root.push_input），
## 再直调一次 _activate_first_choice（headless 下按键若没落到 _unhandled_input，直调照样测到回车会按哪一枚）：
## 断它不按任何钮（返回假）、钱 / 名声 / 两种倾向 / 城防记录 / 旗 / 札记 / 日子一样不动、人还在这一页、钮还在。
## 反向基：重开一页点第一枚钮本身照旧作数（募兵兵加钱减、屯粮、修墙、斩使、焚书、林华出城）。
## 用法：godot --headless --path . -s res://tools/qa_w54_siege_enter_probe.gd（经门锁跑）
## 末行 W54_SIEGE_ENTER cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

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
		_report()
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(_main)
	for i in 10:
		await process_frame
	Switches.reset()
	await _page("A 衙门页：募兵、石手军", "siege_muster", ["募兵 50 人", "募兵 200 人", "重编石手军", "按律解散"], Callable(),
		_ok_muster, "募兵 50 人：兵 300 → %d、钱 20000 → %d")
	await _page("B 市场页：屯粮", "siege_grain", ["屯粮 40", "屯粮 120"], Callable(),
		_ok_grain, "屯粮 40：粮 120 → %d、钱 20000 → %d")
	await _page("C 船屋页：修墙", "siege_wall", ["加固城墙　加 20", "加固城墙　加 60"], Callable(),
		_ok_wall, "加固城墙 20：城墙 60 → %d、钱 20000 → %d")
	await _page("D 酒馆页：第一封劝降书", "siege_envoy", ["斩正使", "收下书信"], Callable(),
		_ok_wang, "斩正使：使者了结 %s、士气 55 → %d、名声 30 → %d")
	await _page("E 酒馆页：姻家的劝降书", "siege_envoy", ["焚书，斩使", "焚书，放他走"], _prep_kin,
		_ok_kin, "焚书斩使：姻家了结 %s、士气 55 → %d、名声 30 → %d")
	await _page("F 第三阵前林华请命（认得他）", "siege_nangshan", ["「你的缆绳系得好", "让他去", "不去。关城门"], _prep_lin_known,
		_ok_lin_known, "提醒缆绳：林华出城 %s、立 lin_hua_reminded %s、士气 55 → %d")
	await _page("G 第三阵前林华请命（不认得）", "siege_nangshan", ["让他去", "不去。关城门"], _prep_lin,
		_ok_lin, "让他去：林华出城 %s、不立 cao_opened %s、粮仍 %d")
	_report()


func _report() -> void:
	_reported = true
	Switches.reset()
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SIEGE_ENTER cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 士人线改名、景炎元年冬月初三进兴化城：城防开着（兵 300、粮 120、城墙 60、士气 55），名声 30、钱两万。
## 船队一条开局小艍（帆一档拆不得），舱里没米，没有陈瓒船股——各页只剩守城本身的钮与外援说明
func _stage(prep: Callable) -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main.set("_chapter_host", null)
		(host as Node).queue_free()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_gs.set_flag("renamed_wenlong")
	_gs.identity = "scholar"
	_gs.money = 20000
	_gs.fame = 30
	_gs.last_port = "xinghua"
	_cal.from_dict({"year": 1276, "month": 11, "day": 3})
	root.get_node("/root/Crew").from_dict({})
	_fleet.ships = []
	_fleet.add_ship("sampan", "无名小艍")
	_fleet.water = 60
	_fleet.food = 60
	_main.load_scene("xinghua")
	await process_frame
	if prep.is_valid():
		prep.call()


## 账面快照：回车前后逐项比
func _snap() -> Dictionary:
	return {
		"钱": _gs.money, "名声": _gs.fame, "士人倾向": _gs.scholar_tendency, "乡土倾向": _gs.hometown_tendency,
		"城防": JSON.stringify(_gs.siege, "", true), "旗": JSON.stringify(_gs.flags, "", true),
		"札记": JSON.stringify(_gs.ledger_notes), "日子": _cal.absolute_day(),
	}


func _button(prefix: String) -> Button:
	for c in _main.choices_container.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion() and str((c as Button).text).begins_with(prefix):
			return c
	return null


## 一页：摆场 → 开门 → 钮都在 → 回车不按 → 反向基（重开一页点第一枚照旧作数）
func _page(title: String, card: String, prefixes: Array, prep: Callable, clicked_ok: Callable, clicked_msg: String) -> void:
	print("── " + title)
	await _stage(prep)
	_main._on_siege_card(card)
	await process_frame
	var missing: Array = []
	for p in prefixes:
		var b := _button(str(p))
		if b == null or b.disabled:
			missing.append(p)
	_expect(missing.is_empty() and _main.investigation_mode.visible,
		"%s：页上有可按的「%s」（缺 %s）" % [_main.scene_title.text, "」「".join(PackedStringArray(prefixes)), str(missing)])
	if not missing.is_empty():
		return
	var page_title: String = _main.scene_title.text
	var before := _snap()
	root.gui_release_focus()
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_ENTER
		k.physical_keycode = KEY_ENTER
		k.pressed = pressed
		root.push_input(k)
	await process_frame
	var pressed_any: bool = _main._activate_first_choice()
	await process_frame
	var after := _snap()
	var moved: Array = []
	for key in before:
		if str(before[key]) != str(after[key]):
			moved.append("%s %s → %s" % [key, str(before[key]), str(after[key])])
	_expect(not pressed_any, "%s：回车找不到可替人按的钮（_activate_first_choice 返回 %s）" % [page_title, str(pressed_any)])
	_expect(moved.is_empty(), "%s：按回车账面一样不动（%s）" % [page_title, "无变动" if moved.is_empty() else "；".join(PackedStringArray(moved))])
	var still: Array = []
	for p in prefixes:
		if _button(str(p)) == null:
			still.append(p)
	_expect(_main.investigation_mode.visible and _main.scene_title.text == page_title and still.is_empty(),
		"%s：按回车后人还在这一页、钮都还在（页「%s」、少了 %s）" % [page_title, _main.scene_title.text, str(still)])
	# 反向基：点钮本身照旧作数
	await _stage(prep)
	_main._on_siege_card(card)
	await process_frame
	var first := _button(str(prefixes[0]))
	if first == null:
		_expect(false, "%s：反向基重开一页找得到第一枚钮" % page_title)
		return
	first.pressed.emit()
	await process_frame
	var vals: Array = []
	match card:
		"siege_muster":
			vals = [_gs.siege_get("troops"), _gs.money]
		"siege_grain":
			vals = [_gs.siege_get("grain"), _gs.money]
		"siege_wall":
			vals = [_gs.siege_get("wall"), _gs.money]
		"siege_envoy":
			vals = [str(_gs.siege.get("envoy_kin" if title.begins_with("E") else "envoy_wang", false)), _gs.siege_get("morale"), _gs.fame]
		_:
			if title.begins_with("F"):
				vals = [str(_gs.siege.get("lin_hua_sent", false)), str(_gs.has_flag("lin_hua_reminded")), _gs.siege_get("morale")]
			else:
				vals = [str(_gs.siege.get("lin_hua_sent", false)), str(_gs.has_flag("cao_opened")), _gs.siege_get("grain")]
	_expect(bool(clicked_ok.call()), "%s 反向基——点钮照旧作数，%s" % [page_title, clicked_msg % vals])


# ── 各页摆场的补笔与反向基判据 ─────────────────────────────

## 第一封劝降书已了结（斩使或收信都算），酒馆页换成姻家那一封
func _prep_kin() -> void:
	_gs.siege_set("envoy_wang", true)


## 两阵已打、林华还没请过命：按囊山门即出第三阵前的林华请命；不认得他（没雇过）
func _prep_lin() -> void:
	_gs.siege_set("round", 2)


## 同上，认得他（雇过林华）：多一枚「你的缆绳系得好…」
func _prep_lin_known() -> void:
	_prep_lin()
	_gs.crew_history = ["lin_hua"]


func _ok_muster() -> bool:
	return _gs.siege_get("troops") == 350 and _gs.money == 19500


func _ok_grain() -> bool:
	return _gs.siege_get("grain") == 160 and _gs.money == 19520


func _ok_wall() -> bool:
	return _gs.siege_get("wall") == 80 and _gs.money == 19700


func _ok_wang() -> bool:
	return bool(_gs.siege.get("envoy_wang", false)) and _gs.siege_get("morale") == 65 and _gs.fame == 35


func _ok_kin() -> bool:
	return bool(_gs.siege.get("envoy_kin", false)) and _gs.siege_get("morale") == 67 and _gs.fame == 38


func _ok_lin_known() -> bool:
	return bool(_gs.siege.get("lin_hua_sent", false)) and _gs.has_flag("lin_hua_reminded") and _gs.siege_get("morale") == 60


func _ok_lin() -> bool:
	return bool(_gs.siege.get("lin_hua_sent", false)) and not _gs.has_flag("cao_opened") and _gs.siege_get("grain") == 120
