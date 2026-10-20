extends SceneTree
## lane w54-tavern：人在海上下不了船。月初该走的人，船在海上时记着不走，靠岸那一刻再下船。
##   A 史实辞船（林华 crew.json leave_from 1276-10）：修前 Crew.history_leave 月初不看船在哪，十月初一船在半海上，
##     林华就「把缆绳盘好，辞了船，说要去兴化投军」——人在海上走不了，舵工加成当场没了，【辞船】落在航程半途。
##     a 泊港照旧：十月初一下船、通告恰一条、不扣他的十月俸（与 godot_story_check._lin_hua_check 同口径，守住不变）。
##     b 海上不走：九月末起锚、十月初一船在海上——仍在船、仍把舵（舵工品级照旧）、不发【辞船】、船籍簿不记辞船；
##       到月下船的人不扣当月俸，海上也一样：他是船上唯一的职事，十月初一不扣钱。
##     c 靠岸下船：真走 SeaChart._arrive——一靠岸人就走、【辞船】恰一条，海图札记里排在「历 N 日，抵 某港」之后（最上），
##       船籍簿淡字记的是靠岸那个月；靠岸后再过日子不重发。
## 用法：godot --headless --path . -s res://tools/qa_w54_tavern_ashore_probe.gd（经门锁跑）
## 末行 W54_TAVERN_ASHORE cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _gs: Node
var _cal: Node
var _crew: Node
var _flt: Node
var _gm: Node
var _notices: Array = []
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
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_crew = root.get_node_or_null("Crew")
	_flt = root.get_node_or_null("Fleet")
	_gm = root.get_node_or_null("GameManager")
	if _gs == null or _cal == null or _crew == null or _flt == null or _gm == null:
		_expect(false, "autoload GameState / Calendar / Crew / Fleet / GameManager 都在")
		_report()
		return
	_gm.connect("monthly_notice", func(t: String) -> void: _notices.append(t))
	_a_in_port()
	_b_at_sea()
	await _c_landfall()
	_flt.set("at_sea", false)
	_report()


## 1276-08-30 在泉州雇下林华（候雇窗末月），日历再拨到九月廿九（十月初一的前两日），钱留够雇他再多 500
func _stage_lin() -> Dictionary:
	_gs.from_dict({})
	_crew.from_dict({})
	_flt.set("at_sea", false)
	_gs.chapter = 3
	_gs.last_port = "quanzhou"
	_cal.from_dict({"year": 1276, "month": 8, "day": 30})
	var lin: Dictionary = _crew.call("candidate_def", "lin_hua")
	_gs.money = int(_crew.call("signing_fee", "lin_hua")) + 500
	var r: Dictionary = _crew.call("hire", "lin_hua")
	_expect(bool(r.get("ok", false)) and _aboard(), "摆场：1276-08-30 泉州雇下林华（%s）" % str(r.get("msg", "")))
	_cal.from_dict({"year": 1276, "month": 9, "day": 29})
	return lin


func _aboard() -> bool:
	return str((_crew.hired as Dictionary).get("duogong", "")) == "lin_hua"


func _leave_notes(from: int) -> int:
	var n := 0
	for t in _notices.slice(from):
		if str(t).begins_with("【辞船】") and str(t).find("林华") >= 0:
			n += 1
	return n


# ── a 泊港：十月初一就走（照旧） ──

func _a_in_port() -> void:
	print("── a 泊港：十月初一下船、通告恰一条、不扣他的十月俸（照旧）")
	var lin := _stage_lin()
	var n0 := _notices.size()
	var money0 := int(_gs.money)
	_gm.call("advance_days", 2)
	_expect(not _aboard() and _leave_notes(n0) == 1 and int(_gs.money) == money0,
		"泊港过到 1276-10-02：林华已下船、【辞船】%d 条、钱 %d → %d（月俸 %d 未扣）" % [
			_leave_notes(n0), money0, int(_gs.money), int(lin.get("wage", 0))])


# ── b 海上：到了月份也不走 ──

func _b_at_sea() -> void:
	print("── b 海上：十月初一船在海上，林华仍在船把舵，不发【辞船】、不记辞船、不扣十月俸")
	_stage_lin()
	_flt.set("at_sea", true)
	var n0 := _notices.size()
	var money0 := int(_gs.money)
	_gm.call("advance_days", 4)
	var lines: PackedStringArray = _crew.call("departed_lines")
	_expect(int(_cal.month) == 10 and _aboard() and int(_crew.call("level_of", "duogong")) == 2,
		"海上过到 1276-10-%02d：林华仍在船、舵工品级 %d（应 2）" % [int(_cal.day), int(_crew.call("level_of", "duogong"))])
	_expect(_leave_notes(n0) == 0 and lines.is_empty(),
		"海上没靠岸：【辞船】%d 条（应 0）、船籍簿辞船淡字 %d 行（应 0）" % [_leave_notes(n0), lines.size()])
	_expect(int(_gs.money) == money0 and int(_crew.call("monthly_wage")) == 0,
		"到月下船的人不扣当月俸，海上也一样：钱 %d → %d、本月俸 %d（应 0）" % [money0, int(_gs.money), int(_crew.call("monthly_wage"))])


# ── c 靠岸：真走 SeaChart._arrive ──

func _c_landfall() -> void:
	print("── c 靠岸：SeaChart._arrive 一靠岸林华就下船，【辞船】跟在「抵某港」之后")
	_stage_lin()
	_flt.set("at_sea", true)
	_gm.call("advance_days", 5)
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	_flt.set("at_sea", true)
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "hakata")
	sc.set("days_elapsed", 7)
	sc.set("sailing", true)
	var n0 := _notices.size()
	_expect(_aboard(), "靠岸前一刻（1276-10-%02d）林华仍在船" % int(_cal.day))
	sc.call("_arrive")
	var sl: PackedStringArray = sc.get("_log_lines")
	var note := "【辞船】" + str(_crew.call("leave_note", _crew.call("candidate_def", "lin_hua")))
	var arrive_line := "历 7 日，抵 %s。" % str(_gm.call("get_port_name", "hakata"))
	_expect(not _aboard() and _leave_notes(n0) == 1 and not bool(_flt.get("at_sea")),
		"靠岸即下船：林华已不在船、【辞船】%d 条（应 1）" % _leave_notes(n0))
	var top := [_ink_off(str(sl[0])), _ink_off(str(sl[1]))] if sl.size() >= 2 else []
	_expect(top == [note, arrive_line],
		"海图札记最上是「%s」、其下「%s」（去墨色实读：%s）" % [note, arrive_line, top])
	var lines: PackedStringArray = _crew.call("departed_lines")
	_expect(lines.size() == 1 and str(lines[0]) == "舵工　林华已于景炎元年十月辞船",
		"船籍簿辞船淡字记靠岸那个月（实读：%s）" % [lines])
	var n1 := _notices.size()
	_flt.set("at_sea", false)
	_gm.call("advance_days", 3)
	sc.call("_arrive")
	_expect(_leave_notes(n1) == 0 and (_crew.call("departed_lines") as PackedStringArray).size() == 1,
		"靠岸后再过日子、再靠一回岸：不重发【辞船】（%d 条）、淡字仍一行" % _leave_notes(n1))
	root.remove_child(sc)
	sc.free()


## 札记行带墨色标记（【辞船】上蜜色、抵港句上金色），比字先去掉
func _ink_off(line: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\[/?color[^\\]]*\\]")
	return rx.sub(line, "", true)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_TAVERN_ASHORE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
