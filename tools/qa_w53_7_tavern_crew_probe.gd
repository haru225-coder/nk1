extends SceneTree
## lane-w53-7 酒馆与人物专项。一支探针分段，每段钉一处修复（退掉那处修复，那一段就红）：
##   W 欠饷：连欠的月数随名册清空归零。修前 Crew.unpaid_months 只在发出饷、或欠满三月有人走时归零；
##     职事欠两月时辞光（或史实辞船走光），名册空了计数照留，重雇的新人一上船船籍簿就写「已欠 2 月」，
##     头一回欠饷就「工食欠满三月，X 不告而去」——他只欠了一个月。
## 用法：godot --headless --path . -s res://tools/qa_w53_7_tavern_crew_probe.gd
## 末行 W53_7_TAVERN_CREW cases=N fails=M；fails>0 退 1。

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _crew: Node


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_crew = root.get_node_or_null("Crew")
	if _gs == null or _cal == null or _crew == null:
		push_error("autoload missing")
		quit(1)
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	_w_wages()
	_report()


func _stage(year: int, month: int, chapter: int) -> void:
	_gs.from_dict({})
	_crew.from_dict({})
	_gs.chapter = chapter
	_gs.last_port = "quanzhou"
	_cal.from_dict({"year": year, "month": month, "day": 10})


## 船籍簿职事栏那一行「月俸共 N　已欠 M 月」（headless 下无小头像，status_label.text 就是整串）
func _ledger_text() -> String:
	_main.call("update_status_panel")
	return str(_main.get("status_label").text)


# ── W 欠饷：名册清空，连欠的月数跟着归零 ──

func _w_wages() -> void:
	print("── W 欠饷：辞光欠饷的职事再雇新人，新人不背前一拨的欠饷月数")
	var wu: Dictionary = _crew.call("candidate_def", "wu_zhen")
	var wage := int(wu.get("wage", 0))
	_stage(1258, 3, 1)
	_gs.money = int(_crew.call("signing_fee", "wu_zhen"))
	_crew.call("hire", "wu_zhen")
	_gs.money = 0
	_crew.call("pay_wages")
	_crew.call("pay_wages")
	_expect(int(_crew.unpaid_months) == 2, "摆场：雇吴针后囊空，连欠两月（unpaid=%d）" % int(_crew.unpaid_months))
	_crew.call("dismiss", "huozhang")
	_gs.money = 2000
	var r: Dictionary = _crew.call("hire", "wu_zhen")
	_expect(bool(r.get("ok", false)) and int(_crew.unpaid_months) == 0,
		"欠两月辞退、当月重雇：新人上船欠月数归零（unpaid=%d）" % int(_crew.unpaid_months))
	var led := _ledger_text()
	_expect(led.contains("月俸共 %d" % wage) and not led.contains("已欠"),
		"重雇当月船籍簿职事栏只写「月俸共 %d」、不写「已欠」（实读：%s）" % [wage, _ledger_line(led)])
	_gs.money = 0
	var note := str(_crew.call("pay_wages"))
	_expect(note == "【欠饷】本月工食 %d 未发。船上人心浮动。" % wage and (_crew.hired as Dictionary).has("huozhang")
		and int(_crew.unpaid_months) == 1,
		"重雇后头一回欠饷：通告「本月工食 %d 未发」、吴针仍在船、欠一月（实读：%s / unpaid=%d）" % [wage, note, int(_crew.unpaid_months)])

	# 月结时名册已空（辞光 / 史实辞船走光 / 跳年散尽）：欠月数在月结里归零，不留到下一拨人
	_stage(1258, 3, 1)
	_gs.money = int(_crew.call("signing_fee", "wu_zhen"))
	_crew.call("hire", "wu_zhen")
	_gs.money = 0
	_crew.call("pay_wages")
	_crew.call("pay_wages")
	_crew.call("dismiss", "huozhang")
	var empty_note := str(_crew.call("pay_wages"))
	_expect(empty_note == "" and int(_crew.unpaid_months) == 0,
		"欠两月辞光后的月结：无人领俸、无通告，欠月数归零（实读：「%s」/ unpaid=%d）" % [empty_note, int(_crew.unpaid_months)])

	# 守住原规矩：人一直在船、连欠三月，俸最高者走、欠月数归零
	_stage(1258, 3, 1)
	_gs.money = int(_crew.call("signing_fee", "wu_zhen"))
	_crew.call("hire", "wu_zhen")
	_gs.money = 0
	_crew.call("pay_wages")
	_crew.call("pay_wages")
	var quit_note := str(_crew.call("pay_wages"))
	_expect(quit_note == "【欠饷】工食欠满三月，吴针 不告而去。" and (_crew.hired as Dictionary).is_empty()
		and int(_crew.unpaid_months) == 0,
		"原规矩照旧：在船连欠三月，吴针不告而去、欠月数归零（实读：%s）" % quit_note)

	# 船上的账不因添人而清：有人欠着两月时再雇一人，欠月数照留（只在名册空了才归零）
	_stage(1258, 3, 1)
	_gs.money = int(_crew.call("signing_fee", "wu_zhen"))
	_crew.call("hire", "wu_zhen")
	_gs.money = 0
	_crew.call("pay_wages")
	_crew.call("pay_wages")
	_gs.money = 2000
	_crew.call("hire", "wang_zhiku")
	_expect(int(_crew.unpaid_months) == 2 and (_crew.hired as Dictionary).size() == 2,
		"船上有人欠两月时添雇一人：欠月数仍 2（unpaid=%d / 在船 %d 人）" % [int(_crew.unpaid_months), (_crew.hired as Dictionary).size()])
	_crew.from_dict({})


func _ledger_line(t: String) -> String:
	for ln in t.split("\n"):
		if ln.contains("月俸共"):
			return ln
	return "<无月俸行>"


func _report() -> void:
	print("W53_7_TAVERN_CREW cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
