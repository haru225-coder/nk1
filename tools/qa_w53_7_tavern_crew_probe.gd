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
	await _t_presence()
	await _h_leave_hint()
	await _n_wall_dates()
	await _i_npc_intel()
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
	print("W53_7_TAVERN_CREW cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
