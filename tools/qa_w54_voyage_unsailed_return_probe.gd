extends SceneTree
## lane w54-voyage：海图上没发舶就「回港」不挂抵港签——哪怕先「候风再发」候过几日。
##   Main「看风」出港那一下记一笔（港、日）（Cinematics.note_departure），海图回港时 Main.start_game 问 Cinematics.take_arrival：
##   「走了日子或换了港」才算真正抵港、挂抵港签（头注「海图上点『回港』原路折回不算」）。可海图上「候风再发」一回过三日，
##   候过再点「回港」，船没离岸，日子却走了——原先照样挂一张「抵泉州」。修法：SeaChart 没发舶的回港把出港那一笔改记成此刻此港。
## 断言（按真钮走：「候风再发」「回港」「下船入港」；换场前取 Main 回港时那一问的答案，headless 下挂签本身不演）：
##   U1 看风 → 候风再发两回（六日）→ 回港：不算抵港。
##   U2 对照：看风 → 当日回港：不算抵港（改前改后同）。
##   U3 对照：看风 → 候风再发 → 发舶走了日子到了福州 → 下船入港：算抵港（真抵港照挂）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_unsailed_return_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_UNSAILED_RETURN cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _gs: Node
var _gm: Node
var _cal: Node
var _fleet: Node
var _cine: GDScript
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	_cine = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if _cine != null:
		_cine.set("auto_opening", false)
		_cine.set("opening_seen", true)
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _gm == null or _cal == null or _fleet == null or _cine == null:
		_expect(false, "autoload / Cinematics 不全")
		_report()
		return
	await _frames(2)
	await _u1_wait_then_back()
	await _u2_back_same_day()
	await _u3_sailed()
	_report()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


## 白板一局，人在泉州（1262 年太平年月），照 Main._on_set_sail 记下出港（港、日），再开海图
func _depart() -> Node:
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1262, "month": 4, "day": 5})
	_fleet.set("water", 200)
	_fleet.set("food", 200)
	_fleet.set("at_sea", false)
	_cine.call("note_departure", "quanzhou", int(_cal.call("absolute_day")))
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	return sc


## Main.start_game 回港时那一问（换场前取，取完一次即清——与 Main 同一口径）
func _arrival_answer() -> bool:
	return bool(_cine.call("take_arrival", str(_gs.get("last_port")), int(_cal.call("absolute_day"))))


func _done(sc: Node) -> void:
	await _frames(8)
	sc.queue_free()
	await _frames(2)


func _u1_wait_then_back() -> void:
	print("── U1 看风 → 候风再发两回 → 回港")
	var sc := _depart()
	await _frames(3)
	var day0 := int(_cal.call("absolute_day"))
	(sc.get("redraw_button") as Button).pressed.emit()
	(sc.get("redraw_button") as Button).pressed.emit()
	var waited := int(_cal.call("absolute_day")) - day0
	var back: Button = sc.get("back_button")
	var enabled := not back.disabled
	back.pressed.emit()
	var arrived := _arrival_answer()
	_expect(waited == 6 and enabled and not bool(sc.get("voyage_started")),
		"候风再发两回过了 %d 日、没发舶、「回港」可点" % waited)
	_expect(not arrived, "船没离岸就回港：不算抵港、不挂抵港签（Main 那一问答 %s）" % str(arrived))
	await _done(sc)


func _u2_back_same_day() -> void:
	print("── U2 对照：看风当日回港")
	var sc := _depart()
	await _frames(3)
	(sc.get("back_button") as Button).pressed.emit()
	var arrived := _arrival_answer()
	_expect(not arrived and str(_gs.get("last_port")) == "quanzhou", "当日原路回港：不算抵港（Main 那一问答 %s）" % str(arrived))
	await _done(sc)


func _u3_sailed() -> void:
	print("── U3 对照：候过风再真发舶到福州")
	var sc := _depart()
	await _frames(3)
	(sc.get("redraw_button") as Button).pressed.emit()
	# 发舶后逐日推进（Voyage 抽事、船标补间）不是这里要验的：照 _on_sail_pressed 立起航行状态，走过两日、到港
	sc.set("_hand", PackedStringArray(["fuzhou"]))
	sc.set("selected_port", "fuzhou")
	sc.set("voyage_started", true)
	sc.set("sailing", true)
	sc.set("days_elapsed", 2)
	_fleet.set("at_sea", true)
	_gm.call("advance_days", 2)
	sc.call("_arrive")
	var landed := false
	for b in (sc.get("event_actions") as Node).get_children():
		if b is Button and not b.is_queued_for_deletion() and str((b as Button).text) == "下船入港":
			(b as Button).pressed.emit()
			landed = true
			break
	var arrived := _arrival_answer()
	_expect(landed and str(_gs.get("last_port")) == "fuzhou" and arrived,
		"真发舶到福州、点「下船入港」：算抵港、照挂抵港签（Main 那一问答 %s）" % str(arrived))
	await _done(sc)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_UNSAILED_RETURN cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
