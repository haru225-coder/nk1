extends SceneTree
## Lane w53-3：headless 探针——海上「记下这条行情」记下的传闻，写在别港同一货的牙行卡上。
## 原先只写在被传那一港自己的卡上（GameState.rumor_label），可人到了那一港、实价就在卡上，记下的行情等于用不上；
## 改后泉州牙行柜上某货那张卡，行上写「传闻博多唐房约卖 N・d 日前」——买进之前就看得到哪里卖得起价。
##   一、别港传闻上行：记一条别港三日前的传闻，柜上那张卡第二行 = 「传闻<港>约卖 N・3 日前」，N 按
##      Economy.price_at_rate(别港, 货, 传闻行情, 卖) 现算；悬停有原提示与这条传闻，这一行收鼠标（悬停弹得出）。
##      行上与本港那条（rumor_label）一字不差、只多港名——两处各写一份字样，改一处漏一处即红（w53-10 间隔号改全角时漏过一回）。
##   二、多港都有取约卖最高的一港；把另一港的传闻抬过它，行上随之改写那一港。
##   三、过了 GameState.RUMOR_STALE_DAYS 的不算：行上回到原提示。
##   四、本港自己的传闻不上行（实价就在卡上）：行上写原提示，悬停写「本港」接 rumor_label 原句（约卖 N、d 日前），可与实价对照。
##   五、没有传闻：行上写原提示，悬停空、这一行不收鼠标（与改前同）。
##   六、港名最长（南岛海道北口）、行情顶格、两位日数时这一行截成「…」不把卡撑宽：最小宽 < 全文宽。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_rumor_probe.gd
## 输出末行 W53_3_RUMOR_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_economy_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _report() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	gm = root.get_node("/root/GameManager")
	cal = root.get_node("/root/Calendar")
	eco = root.get_node("/root/Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	gs.last_port = "quanzhou"
	gs.money = 5000
	cal.from_dict({"year": 1256, "month": 4, "day": 10})
	gs.rumors = {}
	_main.load_scene("quanzhou_market")
	await _settle(2)
	await _cases()
	gs.rumors = {}
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_3_RUMOR_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _labels_under(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels_under(c, out)


## 柜上第 i 张卡的第二行（货名下面那一行：原提示或传闻）
func _hint_label(i: int) -> Label:
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	if slips == null or i >= slips.get_child_count():
		return null
	var labels: Array = []
	_labels_under(slips.get_child(i), labels)
	return labels[1] as Label if labels.size() > 1 else null


## 改完传闻簿重排牙行页，取第 i 张卡那一行
func _hint_after(i: int) -> Label:
	_main.load_scene("quanzhou_market")
	await _settle(2)
	return _hint_label(i)


func _plain_hint(gid: String) -> String:
	var h: String = eco.price_hint("quanzhou", gid)
	return h if h != "" else "寻常"


func _sell_at(pid: String, gid: String, rate: float) -> int:
	return int(eco.price_at_rate(pid, gid, rate, false))


## 卖这货的别港（不含泉州），按港 id 排
func _other_ports(gid: String) -> Array:
	var out: Array = []
	for p in gm.unlocked_ports():
		var pid := str(p.get("id", ""))
		if pid != "quanzhou" and int(p.get("depth", 0)) > 0 and eco.is_traded(pid, gid):
			out.append(pid)
	out.sort()
	return out


func _cases() -> void:
	var hand: PackedStringArray = _main.get("broker_hand")
	# 挑柜上一张卡：这货至少还有两处别港在卖（二节要比两港）
	var idx := -1
	var ports: Array = []
	for i in hand.size():
		ports = _other_ports(str(hand[i]))
		if ports.size() >= 2:
			idx = i
			break
	_expect(idx >= 0, "泉州柜上找得到一件还有两处别港在卖的货（柜上：%s）" % ", ".join(hand))
	if idx < 0:
		return
	var gid := str(hand[idx])
	var gname: String = gm.get_good_name(gid)
	var today: int = cal.absolute_day()
	var plain := _plain_hint(gid)
	var p1 := str(ports[0])
	var p2 := str(ports[1])

	# 一、别港传闻上行
	gs.rumors = {p1: {gid: {"rate": 1.3, "day": today - 3}}}
	var l1: Label = await _hint_after(idx)
	var want1 := "传闻%s约卖 %d・3 日前" % [gm.get_port_name(p1), _sell_at(p1, gid, 1.3)]
	_expect(l1 != null and l1.text == want1 and want1 in l1.tooltip_text and l1.mouse_filter == Control.MOUSE_FILTER_PASS,
		"一、记下%s的%s三日前传闻，泉州柜上那张卡写「%s」（实为「%s」），悬停有这条、这一行收鼠标" % [
			gm.get_port_name(p1), gname, want1, l1.text if l1 != null else "缺"])
	var tip_ok: bool = l1 != null and (eco.price_hint("quanzhou", gid) == "" or l1.tooltip_text.begins_with(eco.price_hint("quanzhou", gid)))
	_expect(tip_ok, "一、悬停第一行是原提示「%s」（悬停：%s）" % [plain, l1.tooltip_text.replace("\n", " ⏎ ") if l1 != null else "缺"])
	# 同一条传闻放回它被传的那一港，rumor_label 的句子在「传闻」后添上港名，须与行上一字不差
	var same: String = "传闻" + gm.get_port_name(p1) + str(gs.rumor_label(p1, gid)).trim_prefix("传闻")
	_expect(l1 != null and l1.text == same,
		"一、行上与本港那条（rumor_label）同一写法、只多港名：「%s」（实为「%s」）" % [same, l1.text if l1 != null else "缺"])

	# 二、多港取最高；把另一港抬过它就改写那一港
	gs.rumors = {p1: {gid: {"rate": 1.3, "day": today - 3}}, p2: {gid: {"rate": 0.6, "day": today - 1}}}
	var s1 := _sell_at(p1, gid, 1.3)
	var s2_low := _sell_at(p2, gid, 0.6)
	var l2: Label = await _hint_after(idx)
	var want2 := want1 if s1 >= s2_low else "传闻%s约卖 %d・1 日前" % [gm.get_port_name(p2), s2_low]
	_expect(l2 != null and l2.text == want2,
		"二、%s约卖 %d、%s约卖 %d：行上写高的那一港「%s」（实为「%s」）" % [
			gm.get_port_name(p1), s1, gm.get_port_name(p2), s2_low, want2, l2.text if l2 != null else "缺"])
	gs.rumors[p2][gid]["rate"] = 2.2
	var s2_high := _sell_at(p2, gid, 2.2)
	var l2b: Label = await _hint_after(idx)
	var want2b := "传闻%s约卖 %d・1 日前" % [gm.get_port_name(p2), s2_high] if s2_high > s1 else want1
	_expect(s2_high > s1 and l2b != null and l2b.text == want2b,
		"二、%s那条抬到约卖 %d（高过 %d）：行上改写「%s」（实为「%s」）" % [
			gm.get_port_name(p2), s2_high, s1, want2b, l2b.text if l2b != null else "缺"])

	# 三、过期不算
	var stale: int = int(gs.get("RUMOR_STALE_DAYS"))
	gs.rumors = {p1: {gid: {"rate": 1.3, "day": today - stale - 1}}}
	var l3: Label = await _hint_after(idx)
	_expect(l3 != null and l3.text == plain and l3.tooltip_text == "",
		"三、%d 日前（过了保鲜 %d 日）的传闻不算：行上回到原提示「%s」（实为「%s」）" % [
			stale + 1, stale, plain, l3.text if l3 != null else "缺"])

	# 四、本港自己的传闻不上行，进悬停
	gs.rumors = {"quanzhou": {gid: {"rate": 1.1, "day": today - 5}}}
	var l4: Label = await _hint_after(idx)
	# 「本港」后接 rumor_label 原句（字样归它定，w53-10 改间隔号时随之而变）；价钱与日数仍按探针自算核
	var own := "本港" + str(gs.rumor_label("quanzhou", gid))
	var own_ok: bool = own.contains("约卖 %d" % _sell_at("quanzhou", gid, 1.1)) and own.contains("5 日前")
	_expect(l4 != null and l4.text == plain and own_ok and own in l4.tooltip_text and l4.mouse_filter == Control.MOUSE_FILTER_PASS,
		"四、只有泉州本港自己的传闻：行上仍写原提示「%s」（实为「%s」），悬停写「%s」（悬停：%s）" % [
			plain, l4.text if l4 != null else "缺", own, l4.tooltip_text.replace("\n", " ⏎ ") if l4 != null else "缺"])

	# 五、没有传闻
	gs.rumors = {}
	var l5: Label = await _hint_after(idx)
	_expect(l5 != null and l5.text == plain and l5.tooltip_text == "" and l5.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"五、没有传闻：行上写原提示「%s」，悬停空、这一行不收鼠标" % plain)

	# 六、最长一例截成「…」不撑宽
	gs.rumors = {"ryukyu": {gid: {"rate": 2.2, "day": today - 12}}}
	if not eco.is_traded("ryukyu", gid):
		gs.rumors = {p1: {gid: {"rate": 2.2, "day": today - 12}}}
	var l6: Label = await _hint_after(idx)
	var full_w := 0.0
	var min_w := 0.0
	if l6 != null:
		var font: Font = l6.get_theme_font("font")
		full_w = font.get_string_size(l6.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l6.get_theme_font_size("font_size")).x
		min_w = l6.get_minimum_size().x
	_expect(l6 != null and l6.text.begins_with("传闻") and l6.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and min_w < full_w,
		"六、最长一例「%s」：全文宽 %.0f，这一行最小宽 %.0f（截成「…」，不把卡撑宽）" % [l6.text if l6 != null else "缺", full_w, min_w])
