extends SceneTree
## lane-w53-7 酒馆与人物专项。一支探针分段，每段钉一处修复（退掉那处修复，那一段就红）：
##   W 欠饷：连欠的月数随名册清空归零。修前 Crew.unpaid_months 只在发出饷、或欠满三月有人走时归零；
##     职事欠两月时辞光（或史实辞船走光），名册空了计数照留，重雇的新人一上船船籍簿就写「已欠 2 月」，
##     头一回欠饷就「工食欠满三月，X 不告而去」——他只欠了一个月。
##   T 在侧：人不在世就不在侧。林阿舶 characters.json died=1274，人物志小传自 1274 起写「咸淳十年前后病故」、
##     1275 辞官那段写「林老爹去年走了」，修前泉州酒馆照样年年摆他的「在侧」卡，点「见」他还说「你叔父那笔，我还记着」，
##     见面页抬头却写「泉州海商　卒于 1274」。
##   H 只跟到几月：林华候雇到 1276-08、1276-10 史实辞船——窗末月雇来只跟九月一个整月，入伙钱照付。这是设计（不是错位），
##     修前卡上却一字不提；现在离辞船不到一年时品级行写明「只跟到九月」（跨年「只跟到明年九月」），并核写的月份是实话。
##   N 墙上年月：酒馆墙上札记的年月旁注修前直接印 news.json 的「1276-05」，顶匾、船籍簿、辞船淡字都写年号月名
##     （跳年摘要更明说「不写阿拉伯公元年」）；现写「景炎元年五月」，与顶匾同一套，改元当年（1276 德祐→景炎）也分得开。
##   I 见面册打听：复刻设计 §8.7「见面册打听写成『某人压低声音说。』行情写成『某港　眼下缺某货，一件能多得　多少钱。』」。
##     修前见面页把酒馆那句整句搬来：「林阿舶压低声音说。⏎⏎邻座的牙人压低声音：「耽罗　眼下缺…」」——一段里两个人压低声音，
##     市舶司小吏那页也冒出「邻座的牙人」；现由见面的人自己说行情那句，酒馆长凳上的「打听」照旧是邻座牙人。
##   J 围城港见小吏打听：牙行闭门、打听不出行情时 _gather_price_intel 回的是酒馆旁白「【闲谈】几个老水手翻来覆去只讲当年的风暴，
##     没打听出新行情。」——修前照样套「市舶司小吏压低声音说。」领起，成了小吏压低声音讲「几个老水手……没打听出新行情」。
##     现由他自己说一句没有新行情；福州 1276-10、广州 1276-11 两处围城实摆。
##   C 人物志未识的职事：页上写「雇过此人，册上才有其详」，可规矩（CharacterArt.is_known）是见过即识——酒馆里看过他的候选卡
##     （TavernPage 记 note_met）就算，不必花入伙钱。现写「见过此人」，并实跑：没雇、只进了他候雇的酒馆，人物志就认得他。
##   R 人物志关系签：已识之人页上「关系」里指向未识之人的签（「未识 / 旧水手」），悬停提示修前读设定集原稿 title——
##     林阿舶页悬停即见「旧水手　水手·后为部将」（运行时截「后为……」只在 codex_title 里做，这里绕过去了），
##     度宗页「儿子」签 1270 年就写「大宋皇帝（景炎）」，海商线陈母页写「陈文龙幼子」。现写人物志上屏称谓，与名册格、未识页同一句；
##     三处钉实例，另按四个年份把名册上每位已识之人的详页翻一遍：指向未识之人的签，提示称谓都须与名册格上那人的称谓一字不差。
##   P 人物志未识职事页「据牙人说，在某港候雇」：修前只查名册里的 port，不看章节、旗标、史实辞船前夕——第一章就把第二章才到明州的
##     蔡七星指去明州（明州酒馆里没有他），没走过寺社引荐也指人去博多找记名沙弥。现与酒馆同读 Crew.on_offer：此刻真在那港候雇才写；
##     并按四个时点把每位职事候选过一遍：未识页指港 ⇔ 那港酒馆此刻列他。
## 用法：godot --headless --path . -s res://tools/qa_w53_7_tavern_crew_probe.gd
## 末行 W53_7_TAVERN_CREW cases=N fails=M；fails>0 退 1。
## 运行期脚本错只中止出错的那一段（其后断言整段跳过、fails 不涨、退出码守 0）——接共用件 tools/script_err_tally.gd：
## 本进程有 SCRIPT ERROR 即红；_run_guarded 包一层，_boot 半路被掐断（没走到 _report）也就地判红收尾。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _crew: Node
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
	_crew = root.get_node_or_null("Crew")
	if _gs == null or _cal == null or _crew == null:
		_expect(false, "autoload GameState / Calendar / Crew 都在")
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
	await _t_presence()
	await _h_leave_hint()
	await _n_wall_dates()
	await _i_npc_intel()
	await _j_npc_no_intel()
	await _c_codex_unknown_crew()
	await _r_rel_chip_tips()
	await _p_hire_port_hint()
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


# ── T 在侧：人不在世就不在侧 ──

func _t_presence() -> void:
	print("── T 在侧：林阿舶病故（人物志小传露出死讯）那年起，泉州酒馆不再有他的「在侧」卡")
	var art: GDScript = load("res://scripts/ui/CharacterArt.gd") as GDScript
	# 人物志小传只认 id 取文本层（不经设定集取数口，免得本探针成了 L1B 原稿读取入口）
	var lin := {"id": "merchant_lin"}
	for ym in [[1273, 12, true], [1274, 1, false], [1275, 6, false]]:
		_stage(int(ym[0]), int(ym[1]), 3)
		var told_dead := str(art.call("codex_bio", lin)).contains("病故")
		await _goto("quanzhou_tavern")
		var card := _label("林阿舶") != null
		var meet := _button("见") != null
		var alive: bool = ym[2]
		_expect(card == alive and meet == alive and told_dead == not alive,
			"%d-%02d 泉州酒馆：林阿舶「在侧」卡 %s、「见」钮 %s；人物志小传%s写病故" % [
				int(ym[0]), int(ym[1]), "在" if card else "无", "在" if meet else "无", "已" if told_dead else "未"])
	# 别的见面人照旧：阿那（无卒年）仍在南岛海道的酒馆，市舶司小吏仍在市舶司
	_stage(1275, 6, 3)
	_gs.last_port = "ryukyu"
	await _goto("ryukyu_tavern")
	_expect(_label("阿那") != null and _button("见") != null, "1275-06 南岛海道北口酒馆：阿那「在侧」照旧")
	_gs.last_port = "quanzhou"
	await _goto("quanzhou_yamen")
	_expect(_label("市舶司小吏") != null and _button("见") != null, "1275-06 泉州市舶司：市舶司小吏「在侧」照旧")


# ── H 只跟到几月：史实辞船的候选离走不到一年，酒馆卡品级后写明他在船的末一月 ──

func _h_leave_hint() -> void:
	print("── H 只跟到几月：林华候雇窗里离辞船不到一年，酒馆卡写明只跟到九月；写的月份就是他在船的末一月")
	for spec in [[1275, 9, "舵工　谙熟"], [1275, 10, "舵工　谙熟　只跟到明年九月"], [1276, 8, "舵工　谙熟　只跟到九月"]]:
		_stage(int(spec[0]), int(spec[1]), 3)
		await _goto("quanzhou_tavern")
		var got := _aside_of("林华")
		_expect(got == str(spec[2]), "%d-%02d 泉州酒馆林华卡品级行「%s」（实读：「%s」）" % [int(spec[0]), int(spec[1]), str(spec[2]), got])
	# 同一页别的候选不带这一截（无 leave_from）
	var wu := _aside_of("吴针")
	_expect(wu == "火长　初习", "1276-08 同页吴针卡品级行只写「火长　初习」（实读：「%s」）" % wu)
	# 卡上写的月份说的是实话：八月底雇来，九月末日仍在船，十月初一下船
	var said := _aside_of("林华")
	var month := said.substr(said.find("只跟到") + 3) if said.find("只跟到") >= 0 else ""
	_gs.money = 5000
	_cal.from_dict({"year": 1276, "month": 8, "day": 30})
	var hired_ok := bool((_crew.call("hire", "lin_hua") as Dictionary).get("ok", false))
	var gm: Node = root.get_node("GameManager")
	gm.call("advance_days", 30)
	var last_day := str(_cal.call("get_month_name"))
	var still := (_crew.hired as Dictionary).has("duogong")
	gm.call("advance_days", 1)
	var gone := not (_crew.hired as Dictionary).has("duogong")
	_expect(month != "" and hired_ok and still and gone and last_day == month,
		"卡上「只跟到%s」：八月三十雇入，%s末日仍在船、次日下船（实读：末日月名 %s / 在船 %s / 次日已下 %s）" % [
			month, month, last_day, still, gone])
	_crew.from_dict({})


## 候选卡（人物卡）品级行：名字那行的上一级 Head 下的 Aside
func _aside_of(person: String) -> String:
	var nm := _label(person)
	if nm == null:
		return "<无此卡>"
	var head := nm.get_parent().get_parent()
	var aside := head.get_node_or_null("Aside") as Label if head != null else null
	return str(aside.text) if aside != null else "<无品级行>"


# ── N 墙上年月：札记旁注写年号月名，与顶匾同一套 ──

func _n_wall_dates() -> void:
	print("── N 墙上札记的年月旁注写年号月名（与顶匾、船籍簿同一套），不印「1276-05」这类公元年月")
	_stage(1276, 6, 4)
	_gs.identity = "merchant"
	for n in _gs.pending_news():
		_gs.mark_news_seen(str(n.get("id", "")))
	var before: Dictionary = _cal.call("to_dict")
	await _goto("quanzhou_tavern")
	var dates := _wall_dates()
	_expect(dates == ["景炎元年五月", "德祐二年正月", "德祐元年四月"],
		"1276-06 泉州酒馆墙上三条（1276-05 / 1276-01 / 1275-04）年月旁注写年号月名、改元前后分得开（实读：%s）" % [dates])
	_expect(_cal.call("to_dict") == before, "札记上墙后历法仍停在 %s（取年号月名临时拨月，取完拨回）" % [_cal.call("to_dict")])


## 「墙上」分区题之后连着的札记卡，每张抬头一行的第二格是年月旁注
func _wall_dates() -> Array:
	var out := []
	var sep := _label("墙上")
	if sep == null:
		return out
	var host := sep.get_parent()
	for i in range(sep.get_index() + 1, host.get_child_count()):
		var card := host.get_child(i)
		if not (card is PanelContainer) or card.is_queued_for_deletion():
			break
		var head := card.get_child(0).get_child(0).get_child(0) as HBoxContainer
		if head != null and head.get_child_count() >= 2:
			out.append(str((head.get_child(1) as Label).text))
	return out


# ── I 见面册打听：见面的人自己说行情那句 ──

func _i_npc_intel() -> void:
	print("── I 见面册「打听」由见面的人自己说行情（复刻设计 §8.7），不再一段里两个人压低声音")
	for spec in [["quanzhou_tavern", "林阿舶"], ["quanzhou_yamen", "市舶司小吏"]]:
		_stage(1260, 4, 2)
		await _goto(str(spec[0]))
		var meet := _button("见")
		if meet == null:
			_expect(false, "%s 没有「见」钮，见面页无从摆" % spec[0])
			continue
		meet.pressed.emit()
		for i in 4:
			await process_frame
		var ask := _button("打听")
		if ask == null:
			_expect(false, "%s 见面页没有「打听」钮" % spec[1])
			continue
		ask.pressed.emit()
		for i in 2:
			await process_frame
		var said := str(_main.get("npc_dialog_lbl").text)
		var lead := "%s压低声音说。" % spec[1]
		_expect(said.begins_with(lead) and said.count("压低声音") == 1 and not said.contains("邻座") and said.contains("眼下缺"),
			"%s 见面页打听：「%s」领起、行情一句由他说，不再夹「邻座的牙人压低声音」（实读：%s）" % [spec[1], lead, said.replace("\n", "⏎")])
		_main.call("_on_npc_leave")
	# 酒馆长凳上的「打听」不动：那里本来就是邻座牙人卖的行情（角色设定集「酒馆邻座压低声音卖你一条行情」）
	var bench := str(_main.call("_gather_price_intel", "quanzhou"))
	_expect(bench.contains("邻座的牙人压低声音：") and bench.contains("眼下缺"), "酒馆长凳打听照旧是邻座牙人那句（实读：%s）" % bench)


# ── J 围城港见小吏打听：没有行情，他自己说没有，不把旁白塞进他嘴里 ──

func _j_npc_no_intel() -> void:
	print("── J 围城港（牙行闭门，打听不出行情）见小吏打听：他自己说没有新行情，不把酒馆旁白「几个老水手……」塞进他嘴里")
	for spec in [["fuzhou", 1276, 10], ["guangzhou", 1276, 11]]:
		_stage(int(spec[1]), int(spec[2]), 4)
		_gs.last_port = str(spec[0])
		await _goto(str(spec[0]) + "_yamen")
		var meet := _button("见")
		if meet == null:
			_expect(false, "%s 市舶司没有「见」钮，见面页无从摆" % spec[0])
			continue
		meet.pressed.emit()
		for i in 4:
			await process_frame
		var ask := _button("打听")
		if ask == null:
			_expect(false, "%s 见面页没有「打听」钮" % spec[0])
			continue
		ask.pressed.emit()
		for i in 2:
			await process_frame
		var said := str(_main.get("npc_dialog_lbl").text)
		var bench := str(_main.call("_gather_price_intel", str(spec[0])))
		_expect(bench.begins_with("【闲谈】") and said.begins_with("市舶司小吏") and said.contains("没什么新行情")
				and not said.contains("老水手") and not said.contains("压低声音"),
			"%s %d-%02d 围城：长凳打听是旁白闲谈（%s），见面页小吏自己说没有新行情（实读：%s）" % [
				spec[0], spec[1], spec[2], bench, said.replace("\n", "⏎")])
		_main.call("_on_npc_leave")


# ── C 人物志未识的职事：见过即识，页上就写见过 ──

func _c_codex_unknown_crew() -> void:
	print("── C 人物志未识职事页的提示与「已识」规矩一致：酒馆里见过即识，不必雇")
	_stage(1258, 3, 1)
	var hint := await _codex_unknown_hint("chen_laodao")
	_expect(hint.contains("见过此人，册上才有其详") and not hint.contains("雇过此人") and hint.contains("福州"),
		"没见过陈老舵：人物志未识页写「见过此人，册上才有其详」、指福州候雇，不写「雇过此人」（实读：%s）" % hint)
	# 实跑规矩：不雇，只进福州酒馆看一眼候选卡，人物志就认得他
	_gs.last_port = "fuzhou"
	await _goto("fuzhou_tavern")
	_main.call("_on_npc_leave")
	var seen_card := _label("陈老舵") != null
	var after := await _codex_unknown_hint("chen_laodao")
	_expect(seen_card and (_crew.hired as Dictionary).is_empty() and after == "",
		"进福州酒馆见过陈老舵的候选卡、一文未付：人物志认得他（卡在 %s / 在船 %d 人 / 未识页提示「%s」）" % [
			seen_card, (_crew.hired as Dictionary).size(), after])


## 人物志直开此人详页：未识页那一句提示（「……册上才有其详……」）；已识（页上没有这句）返回空串
func _codex_unknown_hint(id: String) -> String:
	var cx: Control = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
	root.add_child(cx)
	cx.call("begin", id)
	await process_frame
	var lbl := _find(cx, func(n: Node) -> bool: return n is Label and str((n as Label).text).contains("册上才有其详")) as Label
	var got := str(lbl.text) if lbl != null else ""
	cx.queue_free()
	await process_frame
	return got


# ── P 人物志未识职事页的候雇提示：此刻真在那港候雇才指港 ──

func _p_hire_port_hint() -> void:
	print("── P 人物志未识职事页「据牙人说，在某港候雇」：此刻真在那港酒馆候雇才写（章节、寺社引荐都算上）")
	# 第一章：蔡七星第二章才到明州——明州酒馆里没有他，未识页也不该指去明州（先看人物志，再进酒馆：进了酒馆见过即识）
	_stage(1258, 3, 1)
	var hint := await _codex_unknown_hint("cai_qixing")
	_gs.last_port = "mingzhou"
	await _goto("mingzhou_tavern")
	var there := _label("蔡七星") != null
	_expect(not there and hint == "见过此人，册上才有其详。",
		"第一章：明州酒馆里没有蔡七星（列名 %s），未识页不指明州（实读：%s）" % [there, hint])
	_stage(1262, 5, 2)
	hint = await _codex_unknown_hint("cai_qixing")
	_gs.last_port = "mingzhou"
	await _goto("mingzhou_tavern")
	there = _label("蔡七星") != null
	_expect(there and hint.contains("据牙人说，在明州一带候雇"),
		"第二章：明州酒馆列蔡七星（%s），未识页指明州（实读：%s）" % [there, hint])
	# 记名沙弥：没走过寺社引荐，博多酒馆遇不见他，提示也不指博多；立了 japan_temple_network 才指
	_stage(1262, 5, 2)
	var no_flag := await _codex_unknown_hint("jinghai_shami")
	_gs.set_flag("japan_temple_network")
	var with_flag := await _codex_unknown_hint("jinghai_shami")
	_expect(not no_flag.contains("博多") and with_flag.contains("在博多唐房一带候雇"),
		"记名沙弥：无寺社引荐不指博多（%s）；有了才指（%s）" % [no_flag, with_flag])
	# 整册：每位挂职事的人物，四个时点里「未识页指港」与「那港酒馆此刻列他」两边一致
	var gm := root.get_node("GameManager")
	for st in [[1258, 3, 1, false], [1262, 5, 2, false], [1262, 5, 2, true], [1266, 5, 3, false]]:
		_stage(int(st[0]), int(st[1]), int(st[2]))
		if st[3]:
			_gs.set_flag("japan_temple_network")
		var checked := 0
		var bad: Array = []
		for c in gm.crew_data.get("candidates", []):
			var cid := str(c.get("id", ""))
			var h := await _codex_unknown_hint(cid)
			if h == "":
				continue  # 人物志里不挂职事 id 的（林华走要人一路），没有这一句
			var port_name := str(gm.call("get_port_name", str(c.get("port", ""))))
			var points := h.contains("在%s一带候雇" % port_name)
			var listed := false
			for x in _crew.call("candidates_at", str(c.get("port", ""))):
				listed = listed or str(x.get("id", "")) == cid
			checked += 1
			if points != listed:
				bad.append("%s 指%s=%s 酒馆列名=%s" % [cid, port_name, points, listed])
		_expect(checked >= 15 and bad.is_empty(),
			"%d-%02d 第%d段%s：%d 位职事候选，未识页指港与那港酒馆列名一致（不一致：%s）" % [
				st[0], st[1], st[2], "（有寺社引荐）" if st[3] else "", checked, "无" if bad.is_empty() else "；".join(bad)])


# ── R 人物志关系签：指向未识之人的悬停提示写人物志上屏称谓 ──

func _r_rel_chip_tips() -> void:
	print("── R 人物志关系签指向未识之人：悬停提示写人物志上屏称谓（按年份露、截「后为……」），不读设定集原稿")
	_stage_codex(1258, 3, 1, "undecided")
	var tip := await _rel_tip("merchant_lin", "lin_hua")
	_expect(tip == "旧水手　泉州码头水手",
		"第一章林阿舶页「旧水手」签（林华未识）：提示「旧水手　泉州码头水手」，不露「后为部将」（实读：%s）" % tip)
	_stage_codex(1262, 5, 2, "merchant")
	tip = await _rel_tip("chen_mother", "chen_jing")
	_expect(tip == "孙儿　陈子龙幼子",
		"海商线陈母页「孙儿」签（陈靖未识）：主角没改名，提示写「陈子龙幼子」不写「陈文龙幼子」（实读：%s）" % tip)
	_stage_codex(1270, 5, 3, "scholar")
	tip = await _rel_tip("song_duzong", "song_duanzong")
	_expect(tip == "儿子　度宗长子",
		"1270 度宗页「儿子」签（端宗未识）：提示「儿子　度宗长子」，不提前写「大宋皇帝（景炎）」（实读：%s）" % tip)
	# 整册翻：四个年份，名册上每位已识之人的详页，指向未识之人的签——提示 =「关系　名册格上那人的称谓」
	for st in [[1258, 3, 1, "undecided"], [1262, 5, 2, "merchant"], [1270, 5, 3, "scholar"], [1273, 5, 4, "scholar"]]:
		_stage_codex(int(st[0]), int(st[1]), int(st[2]), str(st[3]))
		var got: Array = await _rel_tip_sweep()
		_expect(int(got[0]) >= 8 and (got[1] as Array).is_empty(),
			"%d-%02d 第%d段（%s）：已识之人页上 %d 个指向未识之人的签，提示称谓与名册格一致（不一致：%s）" % [
				st[0], st[1], st[2], st[3], got[0], "无" if (got[1] as Array).is_empty() else "；".join(got[1])])


## 人物志摆场：年月 + 第几段 + 身份（士人线连带殿试改名）；进过泉州（序章已走完）
func _stage_codex(year: int, month: int, chapter: int, identity: String) -> void:
	_stage(year, month, chapter)
	_gs.visited_ports = ["quanzhou"]
	_gs.identity = identity
	if identity == "scholar":
		_gs.set_flag("renamed_wenlong")
		_gs.player_name = "陈文龙"


## 人物志直开 page_id 详页，取「关系」里指向 other_id 那一签的悬停提示（签名 Rel_<id>）；没有这一签返回「<无签>」
func _rel_tip(page_id: String, other_id: String) -> String:
	var cx: Control = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
	root.add_child(cx)
	cx.call("begin", page_id)
	await process_frame
	var got := "<无签>"
	var chip := cx.find_child("Rel_" + other_id, true, false)
	if chip != null:
		got = _chip_tip(chip)
	cx.queue_free()
	await process_frame
	return got


## 整册翻一遍：名册格（Cell_<id>，名字一格写「未识」即未识，称谓一格是人物志上屏称谓）记下未识之人的称谓，
## 再逐个翻已识之人的详页，核每个指向未识之人的签。返回 [核过的签数, 不一致的条目]
func _rel_tip_sweep() -> Array:
	var cx: Control = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
	root.add_child(cx)
	cx.call("begin", "")
	cx.call("_on_tab", "all")
	await process_frame
	var unknown_title := {}
	var known_ids: Array = []
	for cell in cx.find_children("Cell_*", "Button", true, false):
		var id := str(cell.name).trim_prefix("Cell_")
		var col: Node = cell.get_child(0)
		var shown := str((col.get_node("Name") as Label).text)
		var title := str((col.get_child(2) as Label).text)
		if shown == "未识":
			unknown_title[id] = "来历未详" if title == "未详" else title
		else:
			known_ids.append(id)
	var checked := 0
	var bad: Array = []
	for id in known_ids:
		cx.call("show_detail", id, false)
		for chip in cx.find_children("Rel_*", "PanelContainer", true, false):
			var oid := str(chip.name).trim_prefix("Rel_")
			if not unknown_title.has(oid):
				continue
			var lines := _chip_lines(chip)
			var want := "%s　%s" % [lines[1], unknown_title[oid]]
			var tip := _chip_tip(chip)
			checked += 1
			if lines[0] != "未识" or tip != want:
				bad.append("%s→%s 提示「%s」应为「%s」" % [id, oid, tip, want])
	cx.queue_free()
	await process_frame
	return [checked, bad]


## 关系签上的两行字：[名（未识写「未识」）, 关系]——签面末两枚 Label（未识签的头像框里另有一枚「？」排在前头）
func _chip_lines(chip: Node) -> Array:
	var out: Array = []
	for l in chip.find_children("*", "Label", true, false):
		out.append(str((l as Label).text))
	return out.slice(out.size() - 2) if out.size() >= 2 else ["", ""]


## 关系签整签的点按钮（盖满签面的那只 flat Button）上的悬停提示
func _chip_tip(chip: Node) -> String:
	for c in chip.get_children():
		if c is Button:
			return str((c as Button).tooltip_text)
	return "<无钮>"


func _goto(scene_id: String) -> void:
	_main.call("load_scene", scene_id)
	for i in 6:
		await process_frame


func _label(t: String) -> Label:
	return _find(_main, func(n: Node) -> bool: return n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text) == t) as Label


func _button(t: String) -> Button:
	return _find(_main, func(n: Node) -> bool: return n is Button and (n as Button).is_visible_in_tree() and str((n as Button).text) == t) as Button


func _find(n: Node, pred: Callable) -> Node:
	if n == null or n.is_queued_for_deletion():
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _ledger_line(t: String) -> String:
	for ln in t.split("\n"):
		if ln.contains("月俸共"):
			return ln
	return "<无月俸行>"


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_7_TAVERN_CREW cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
