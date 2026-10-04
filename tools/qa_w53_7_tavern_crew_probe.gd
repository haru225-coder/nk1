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
##   M 名册只露认得的人：岸上「名册」（人物志「立绘册」同一件）修前把七十五人的名字、画像、生卒、登场、小传、五维全摆出来——
##     宝祐年间翻「史实」就是伯颜、宋恭帝，翻「主」就是第二章才登场的林华。现与人物志同一条「已识」规矩：未识之人行上写「未识」、
##     短注只写人物志称谓，立绘面板只出墨影、「未识之人」、称谓与一句提示。按两个时点四个页签逐行与人物志名册格对照。
##   Q 小吏只在泉州是那位：人物志里的市舶司小吏是泉州验引棚那一位（称谓「泉州市舶司小吏」），修前博多、占城的市舶司也挂他的
##     人物卡、画像、小传，见一面还记作见过。别港的市舶司要么没有小吏（w53-13 定 #24：见面钮只摆在泉州），要么是本地无名小吏
##     （照样见、打听、疏通，不挂人物卡与人物志钮、不记见过）——两种都不许露出泉州那一位；泉州照旧。
##   K 见面页的字对上页上的动作：行情签旁注修前写「邻座牙人」——说话的是林阿舶、小吏本人。见面页打听与酒馆长凳一样费一日
##     （w53-13 定 #25「统一为都费一日」）：旁注「费一日」、实跑核日历走一日、顶匾跟着换日子，花时间的钮同长凳不做整卡可点；
##     阿那招呼修前说「要问航路，就问」，他页上却没有问航路的签。离开见面页回到设施页按此刻重排：塞过钱，市舶司页的「蒲家留意」是塞后的数。
##   L 墙上只贴市井听得到的：士人身份收到的临安短札（只发给士人、没有说话人：「短札：……贬你知抚州」）修前题「酒馆传闻」
##     贴在酒馆墙上，最近三条里能占两条。现不贴；小瘸子当面说兴化募兵（有说话人）、海商的崖山传闻照贴。
##   S 人物志「性情」不透底：修前直读原稿 personality，不按年份——吕文焕 1269 年小传还写「他坚守孤城」「此后之事，尚在将来」，
##     性情却已是「援绝之后，降得也彻底」；丁大全开局就「终为更大的权臣所除」；仲子在没有忠肃的那几条线也是「父亲绝笔的收信人」。
##     现走文本层分段（取最后一段可见的），按年份 / 世界线 / 了结换句；称谓同理：姻家使者开局不叫「持书招降的姻亲」、王世强不叫「宋降将」。
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
	await _m_roster_gate()
	await _q_clerk_home()
	await _k_meet_page_words()
	await _l_wall_letters()
	await _s_codex_traits()
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
	_expect(dates == ["景炎元年五月", "德祐二年正月", "德祐元年十月"],
		"1276-06 泉州酒馆墙上三条（1276-05 / 1276-01 / 1275-10「贾似道死了」 w53-13 加）年月旁注写年号月名、改元前后分得开（实读：%s）" % [dates])
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

func _j_npc_no_INTEL_ALT() -> void:
	return  # 站位正式案以此间那句林影对实——— alive 记载.双STATEMENT
func _j_npc_no_intel() -> void:
	print("── J 围城港：市舶司页本无小吏；见面页打听不出行情就由他自己说没有，不把旁白塞进他嘴里")

	# a) ead0cb5 后：兴化 1276-11 围城的市舶司页本无「见」钮。
	_stage(1276, 11, 4)
	_gs.visited_ports = ["quanzhou", "xinghua"]
	_gs.last_port = "xinghua"
	await _goto("xinghua_yamen")
	_expect(_button("见") == null, "兴化 1276-11 围城：市舶司页本无小吏的「见」钮（修前本摆）")
	# b) 泉州：把 ports.json 里每港的 market 暂改成空表（全港无货可交易）：_collect_spreads rows=0，长凳打听只能回「【闲谈】」，
	#    见面页 NO_INTEL 由他自己说；打完照原样放回。
	_stage(1262, 5, 2)
	_gs.visited_ports = ["quanzhou"]
	_gs.last_port = "quanzhou"
	var gm: Node = root.get_node("GameManager")
	var kept: Array = []
	var pistes: Array = gm.ports_data.get("ports", [])
	for x in pistes:
		kept.append(x.get("market", {}).duplicate())
	for i in pistes.size():
		pistes[i]["market"] = {}
	await _goto("quanzhou_yamen")
	var meet := _button("见")
	_expect(meet != null, "泉州市舶司：小吏的「见」钮好端端摆着（本人在港）")
	if meet != null:
		meet.pressed.emit()
		for i in 4:
			await process_frame
		var ask := _button("打听")
		if ask == null:
			_expect(false, "泉州市舶司见面页无「打听」钮")
		else:
			var bench := str(_main.call("_gather_price_intel", "quanzhou"))
			ask.pressed.emit()
			for i in 2:
				await process_frame
			var said := str(_main.get("npc_dialog_lbl").text)
			_expect(bench.begins_with("【闲谈】") and said.begins_with("市舶司小吏") and said.contains("没什么新行情")
					and not said.contains("老水手") and not said.contains("压低声音"),
				"泉州 1262-05、全港无货：长凳打听是旁白闲谈（%s），见面页小吏自己说没有新行情（实读：%s）" % [
					bench.replace("\n", "⏎"), said.replace("\n", "⏎")])
			_main.call("_on_npc_leave")
	# 恢放每港的 market
	for i in pistes.size():
		pistes[i]["market"] = kept[i]
	var after_dirty := false
	for x in pistes:
		if typeof(x.get("market", null)) != TYPE_DICTIONARY or (x.get("market", {}) as Dictionary).size() < 2:
			after_dirty = true
	_expect(not after_dirty, "每港 market 已复原（%d 港，还能照常交易）" % pistes.size())


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


# ── M 名册只露人物志认得的人 ──

func _m_roster_gate() -> void:
	print("── M 岸上「名册」只露人物志认得的人：未识之人行上写「未识」、只写人物志称谓，立绘面板不出名字、生卒、小传、五维")
	for st in [[1258, 3, 1], [1270, 5, 3]]:
		_stage(int(st[0]), int(st[1]), int(st[2]))
		_gs.visited_ports = ["quanzhou"]
		var grid: Dictionary = await _codex_grid()
		_main.call("_open_chars_wire", "")
		for i in 4:
			await process_frame
		var ov: Node = _main.get("_chars_wire")
		var roster: Node = ov.get("_roster") if ov != null else null
		if roster == null:
			_expect(false, "岸上名册浮页起不来（_chars_wire / _roster 为空）")
			return
		var checked := 0
		var unknown := 0
		var bad: Array = []
		for tab in ["主", "职事", "市井", "史实"]:
			roster.call("_on_tab", tab)
			await process_frame
			for row in roster.find_children("Row_*", "PanelContainer", true, false):
				var id := str(row.name).trim_prefix("Row_")
				if not grid.has(id):
					bad.append("%s 不在人物志名册里" % id)
					continue
				var g: Array = grid[id]
				var shown := str((row.find_child("Name", true, false) as Label).text)
				var note := str((row.find_child("Note", true, false) as Label).text)
				checked += 1
				if str(g[0]) == "未识":
					unknown += 1
					var want_note := "来历未详" if str(g[1]) == "未详" else str(g[1])
					var face_q := false
					for l in row.find_children("*", "Label", true, false):
						face_q = face_q or str((l as Label).text) == "？"
					if shown != "未识" or note != want_note or not face_q:
						bad.append("%s 名格「%s」短注「%s」（人物志：未识 / %s）头面「？」%s" % [id, shown, note, want_note, face_q])
				elif shown != str(g[0]):
					bad.append("%s 名格「%s」≠ 人物志「%s」" % [id, shown, g[0]])
		_expect(checked >= 70 and unknown >= 20 and bad.is_empty(),
			"%d-%02d 第%d段：名册四页 %d 行（未识 %d）逐行与人物志名册格一致（不一致：%s）" % [
				st[0], st[1], st[2], checked, unknown, "无" if bad.is_empty() else "；".join(bad.slice(0, 6))])
		if int(st[0]) == 1258:
			# 林华第二章才登场：立绘面板只出「未识」名牌、「未识之人」、称谓与提示；林阿舶认得，照出五维
			ov.call("focus_id", "lin_hua")
			await process_frame
			var lin := _panel_texts(ov)
			_expect(lin.has("未识") and lin.has("未识之人") and lin.has("泉州码头水手") and lin.has("其人其事，尚未传到你耳中。")
					and not lin.has("林华") and not lin.has("航术") and not lin.has("生卒") and not lin.has("登场") and not lin.has("画像"),
				"1258 名册点林华（未识）：面板只有「未识」名牌、「未识之人」、称谓与一句提示，名字 / 五维 / 生卒 / 登场 / 画像都不出（实读：%s）" % " | ".join(lin))
			ov.call("focus_id", "merchant_lin")
			await process_frame
			var abo := _panel_texts(ov)
			_expect(abo.has("林阿舶") and abo.has("航术") and not abo.has("未识之人"),
				"1258 名册点林阿舶（已识）：面板照出名字与五维（实读：%s）" % " | ".join(abo.slice(0, 8)))
		_main.call("_close_chars_wire")
		for i in 3:
			await process_frame


## 人物志名册格：{id: [名格（未识写「未识」）, 称谓格]}——名册页对照的底账（只读界面，不碰人物取数口）
func _codex_grid() -> Dictionary:
	var cx: Control = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
	root.add_child(cx)
	cx.call("begin", "")
	cx.call("_on_tab", "all")
	await process_frame
	var out := {}
	for cell in cx.find_children("Cell_*", "Button", true, false):
		var col: Node = cell.get_child(0)
		out[str(cell.name).trim_prefix("Cell_")] = [str((col.get_node("Name") as Label).text), str((col.get_child(2) as Label).text)]
	cx.queue_free()
	await process_frame
	return out


## 名册浮页右栏立绘面板上看得见的字（含名牌）
func _panel_texts(ov: Node) -> Array:
	var out: Array = []
	var panel: Node = ov.get("_panel")
	for l in panel.find_children("*", "Label", true, false):
		if not (l as Label).is_queued_for_deletion():
			out.append(str((l as Label).text))
	return out


# ── Q 市舶司小吏这条人物只在泉州 ──

func _q_clerk_home() -> void:
	print("── Q 人物志里的市舶司小吏是泉州那一位：别港市舶司没有小吏、或是本地无名小吏，都不挂他的人物卡、不记见过；泉州照旧")
	for spec in [["hakata", false], ["champa", false], ["quanzhou", true]]:
		_stage(1262, 5, 2)
		_gs.visited_ports = ["quanzhou", "xinghua", str(spec[0])]
		_gs.last_port = str(spec[0])
		await _goto(str(spec[0]) + "_yamen")
		var card := _label("泉州市舶司小吏") != null
		var meet := _button("见")
		if meet == null:
			# w53-13 #24 的做法：别港市舶司页不摆小吏的见面钮——泉州那一位自然不露；泉州则必须有
			_expect(not bool(spec[1]) and not card and not (_gs.get("met_ids") as Array).has("customs_official"),
				"%s 市舶司没有「见」钮：%s（人物卡 %s）" % [spec[0], "泉州必须有小吏可见" if bool(spec[1]) else "别港不摆小吏，泉州那一位不露", card])
			continue
		meet.pressed.emit()
		for i in 4:
			await process_frame
		var profile := bool((_main.get("_npc_profile") as Control).visible)
		var codex_btn := bool((_main.get("_npc_codex_btn") as Control).visible)
		var title_shown := _label("泉州市舶司小吏") != null
		var met := (_gs.get("met_ids") as Array).has("customs_official")
		var acts := _button("打听") != null and _button("塞　50") != null
		var name_ok := str(_main.get("npc_name_lbl").text) == "市舶司小吏"
		_main.call("_on_npc_leave")
		if bool(spec[1]):
			_expect(card and profile and codex_btn and title_shown and met and acts and name_ok,
				"泉州市舶司：照旧是那位小吏——人物卡 %s、人物栏 %s、人物志钮 %s、称谓 %s、记见过 %s、打听 / 疏通 %s" % [card, profile, codex_btn, title_shown, met, acts])
		else:
			_expect(not card and not profile and not codex_btn and not title_shown and not met and name_ok,
				"%s 市舶司：本地无名小吏——不挂人物卡（%s）、人物栏（%s）、人物志钮（%s）、「泉州市舶司小吏」（%s），不记见过（%s）" % [
					spec[0], card, profile, codex_btn, title_shown, met])


# ── K 见面页的字对上页上的动作 ──

func _k_meet_page_words() -> void:
	print("── K 见面页打听同酒馆长凳费一日（w53-13 定 #25）：旁注「费一日」、日历与顶匾走一日、钮不整卡可点；不许诺没有的问航路；离开后设施页按此刻重排")
	for spec in [["quanzhou_tavern", "quanzhou"], ["ryukyu_tavern", "ryukyu"], ["quanzhou_yamen", "quanzhou"]]:
		_stage(1262, 5, 2)
		_gs.visited_ports = ["quanzhou", "xinghua", "ryukyu"]
		_gs.last_port = str(spec[1])
		await _goto(str(spec[0]))
		var meet := _button("见")
		if meet == null:
			_expect(false, "%s 没有「见」钮" % spec[0])
			continue
		meet.pressed.emit()
		for i in 4:
			await process_frame
		var who := str(_main.get("npc_name_lbl").text)
		var greet := str(_main.get("npc_dialog_lbl").text)
		var aside_ok := _label("费一日") != null and _label("邻座牙人") == null and _label("不费时日") == null
		var day0 := int(_cal.call("absolute_day"))
		var ask := _button("打听")
		var whole := false
		if ask != null:
			var card: Node = ask
			while card != null and not (card is PanelContainer):
				card = card.get_parent()
			whole = card != null and card.get_node_or_null("WholeHit") != null
			ask.pressed.emit()
			for i in 2:
				await process_frame
		var day1 := int(_cal.call("absolute_day"))
		var top_ok := str(_main.get("_status_line").text).contains(str(_cal.call("get_date_string")))
		var route_promise := greet.contains("航路") and _button("问航路") == null
		_main.call("_on_npc_leave")
		_expect(aside_ok and ask != null and not whole and day1 == day0 + 1 and top_ok and not route_promise,
			"%s 见%s：旁注「费一日」、无「邻座牙人」（%s）；打听不整卡可点（整卡 %s）、日历走 %d 日、顶匾换成新日子（%s）；招呼不许诺问航路（%s）" % [
				spec[0], who, aside_ok, whole, day1 - day0, top_ok, greet])
	# 酒馆长凳那张行情签照旧写「费一日」
	_stage(1262, 5, 2)
	await _goto("quanzhou_tavern")
	_expect(_label("费一日") != null, "泉州酒馆长凳行情签照旧写「费一日」")
	# 离开见面页回到设施页按此刻重排：泉州市舶司塞过钱，页上「蒲家留意」写塞后的数（修前留着见面之前那一页的旧数）
	_stage(1262, 5, 2)
	_gs.visited_ports = ["quanzhou", "xinghua"]
	_gs.money = 500
	_gs.pu_attention = 40
	await _goto("quanzhou_yamen")
	var before_text := "蒲家留意 40　%s" % str(_main.call("_attention_desc"))
	var before_note := _label(before_text) != null
	var meet2 := _button("见")
	if meet2 == null:
		_expect(false, "泉州市舶司没有「见」钮")
		return
	meet2.pressed.emit()
	for i in 4:
		await process_frame
	var bribe := _button("塞　50")
	if bribe != null:
		bribe.pressed.emit()
		for i in 2:
			await process_frame
	_main.call("_on_npc_leave")
	for i in 4:
		await process_frame
	var after_text := "蒲家留意 %d　%s" % [int(_gs.pu_attention), str(_main.call("_attention_desc"))]
	var after_note := _label(after_text) != null
	var stale := _label(before_text) != null
	_expect(before_note and bribe != null and int(_gs.pu_attention) == 25 and after_note and not stale,
		"泉州市舶司塞过钱再离开：页上写塞后的「%s」（%s），不留塞前的「%s」（%s）" % [after_text, after_note, before_text, stale])


# ── L 墙上只贴市井听得到的 ──

func _l_wall_letters() -> void:
	print("── L 墙上只贴市井听得到的：士人收到的临安短札（无说话人）不题「酒馆传闻」上墙；小瘸子当面的话、海商的崖山传闻照贴")
	# 底账：只发给士人、又没有说话人的新闻，全是寄给你一人的短札（墙上的规矩据此判）
	var letters := 0
	var not_letter: Array = []
	for n in root.get_node("GameManager").get("news_data").get("news", []):
		if str(n.get("only", "")) == "scholar" and str(n.get("speaker", "")).strip_edges() == "":
			letters += 1
			if not str(n.get("text", "")).contains("短札"):
				not_letter.append(str(n.get("id", "")))
	_expect(letters >= 4 and not_letter.is_empty(), "news.json 只发给士人、无说话人的 %d 条都是短札（不是的：%s）" % [letters, not_letter])
	for spec in [
		[1273, 6, "scholar", ["n_1264_11_lizong_dies", "n_1268_10_sulfur_ban", "n_1272_03_no_draft", "n_1273_02_dismissed", "n_1273_03_fanfang_panic"],
			["蕃坊人心浮动", "硫黄禁出海", "理宗崩"], "1273-06 士人：最近五条里两条短札，墙上三张是另三条市井传闻"],
		[1276, 10, "scholar", ["n_1275_04_requisition", "n_1275_11_vice", "n_1276_10_xinghua_muster"],
			["兴化城里在募人守城", "征调商船"], "1276-10 士人：小瘸子当面说兴化募兵照贴，「累迁参知政事」短札不贴"],
		[1278, 12, "merchant", ["n_1277_07_xinghua_again", "n_1278_12_yashan"],
			["崖山", "张世杰的船要回头"], "1278-12 海商：只发给海商的崖山传闻照贴"],
	]:
		_stage(int(spec[0]), int(spec[1]), 4)
		_gs.identity = str(spec[2])
		_gs.news_seen = (spec[3] as Array).duplicate()
		await _goto("quanzhou_tavern")
		var cards := _wall_cards()
		var want: Array = spec[4]
		var ok := cards.size() == want.size()
		var shown: Array = []
		for c in cards:
			shown.append("%s｜%s" % [c[0], str(c[2]).left(16)])
			ok = ok and not str(c[2]).contains("短札")
		for i in mini(cards.size(), want.size()):
			ok = ok and str(cards[i][2]).contains(str(want[i]))
		_expect(ok, "%s（墙上：%s）" % [spec[5], " / ".join(shown)])


## 「墙上」分区题之后连着的札记卡：[说话人题签, 年月旁注, 正文]，新的在前
func _wall_cards() -> Array:
	var out := []
	var sep := _label("墙上")
	if sep == null:
		return out
	var host := sep.get_parent()
	for i in range(sep.get_index() + 1, host.get_child_count()):
		var card := host.get_child(i)
		if not (card is PanelContainer) or card.is_queued_for_deletion():
			break
		var col := card.get_child(0).get_child(0)
		var head := col.get_child(0) as HBoxContainer
		out.append([str((head.get_child(0) as Label).text), str((head.get_child(1) as Label).text) if head.get_child_count() > 1 else "",
			str((col.get_child(1) as Label).text)])
	return out


# ── S 人物志「性情」与称谓不透底 ──

func _s_codex_traits() -> void:
	print("── S 人物志「性情」按年份 / 世界线 / 了结换句（不再开局就写降、写死、写绝笔）；称谓同理")
	# [id, 年, 月, 第几段, 身份, 改名, 了结, 性情里不许有 / 须有的字, 须有?]
	for c in [
		["ding_daquan", 1258, 3, 1, "undecided", false, "", "所除", false, "丁大全 1258（开局即识）"],
		["ding_daquan", 1263, 6, 3, "undecided", false, "", "终为更大的权臣所除", true, "丁大全 1263 落水死后"],
		["lv_wenhuan", 1269, 5, 4, "undecided", false, "", "降", false, "吕文焕 1269 守襄阳"],
		["lv_wenhuan", 1273, 3, 4, "undecided", false, "", "援绝之后，降得也彻底", true, "吕文焕 1273-03 襄阳降后"],
		["song_duzong", 1270, 5, 3, "merchant", false, "", "御批", false, "宋度宗 1270 海商（没有改名这回事）"],
		["song_duzong", 1270, 5, 3, "scholar", true, "", "却落下一笔好御批", true, "宋度宗 1270 士人改名后"],
		["chen_zhongzi", 1276, 3, 4, "merchant", false, "", "绝笔", false, "仲子 1276-03 海商"],
		["chen_zhongzi", 1277, 12, 4, "scholar", true, "忠肃", "父亲绝笔的收信人", true, "仲子 忠肃了结后"],
		["dong_wenbing", 1285, 5, 4, "merchant", false, "纲首", "不跪", false, "董文炳 纲首了结后"],
	]:
		_stage(int(c[1]), int(c[2]), int(c[3]))
		_gs.visited_ports = ["quanzhou"]
		_gs.identity = str(c[4])
		if c[5]:
			_gs.set_flag("renamed_wenlong")
			_gs.player_name = "陈文龙"
		if str(c[6]) != "":
			_gs.call("finish", str(c[6]), "正文")
		var trait_text := await _codex_trait(str(c[0]))
		var has := trait_text.contains(str(c[7]))
		_expect(trait_text != "" and has == bool(c[8]),
			"%s：性情%s「%s」（实读：%s）" % [c[9], "写" if c[8] else "不写", c[7], trait_text])
	# 称谓（名册格那一行，未识也露）：开局不写后来的事
	_stage(1258, 3, 1)
	_gs.visited_ports = ["quanzhou"]
	var g58: Dictionary = await _codex_grid()
	_stage(1276, 12, 4)
	_gs.visited_ports = ["quanzhou"]
	_gs.identity = "scholar"
	_gs.set_flag("renamed_wenlong")
	_gs.player_name = "陈文龙"
	var g76: Dictionary = await _codex_grid()
	_expect(str(g58["kin_envoy"][1]) == "陈家姻亲" and str(g58["wang_shiqiang"][1]) == "宋将"
			and str(g76["kin_envoy"][1]) == "持书招降的姻亲" and str(g76["wang_shiqiang"][1]) == "宋降将",
		"称谓：1258 名册格姻家使者「%s」、王世强「%s」；1276-12 士人改名后「%s」「%s」" % [
			g58["kin_envoy"][1], g58["wang_shiqiang"][1], g76["kin_envoy"][1], g76["wang_shiqiang"][1]])


## 人物志直开此人详页，读「性情」一节那一段；页上没有这一节（未识、或无性情）返回空串
func _codex_trait(id: String) -> String:
	var cx: Control = (load("res://scripts/ui/CharacterCodex.gd") as GDScript).new()
	root.add_child(cx)
	cx.call("begin", id)
	await process_frame
	var got := ""
	var sec := _find(cx, func(n: Node) -> bool: return n is Label and str((n as Label).text) == "性情") as Label
	if sec != null and sec.get_index() + 1 < sec.get_parent().get_child_count():
		got = str((sec.get_parent().get_child(sec.get_index() + 1) as Label).text)
	cx.queue_free()
	await process_frame
	return got


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
