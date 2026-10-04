extends SceneTree
## lane w53-1：海图罗盘的朱针与盘下针名，未发舶时与去向牌上写的针位一致；航行中跟当日所在那一段。
## 原先未发舶也取出港第一段（Voyage.bearing）：广州三向头一段都是出珠江口的「乙针」，牌上往占城写「南　丁未针」、
## 往漳州泉州写「东　寅甲针」，罗盘一律指「乙针」；明州往福州牌上写「西南　未针」，罗盘指「丑针」，差 179 度——
## 第四章全港对 182 对里 113 对两处针名对不上。
## 断言：
##   K1 全港对（第四章已解锁港两两成对、未发舶）：罗盘针名 = 真建出来的那张去向牌（SeaChart._make_heading_card）上写的针名；
##   K2 照玩家点牌（_refresh_hand 发三向、_select_heading 逐张点）：泉州 / 明州 / 广州起锚，每点一张，罗盘针名 = 那张牌的针名，
##      去向不同针也不同（广州三向原先罗盘三张同针）；
##   K3 航行中罗盘跟当日罗经（course_bearing）——不因未发舶的改法连航行中的针也换成两港直连。
## 罗盘方位取 SeaChart._compass_bearing（_draw_compass 画朱针与盘下针名都用它）；没有它的旧版照原先的取法复算。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_compass_needle_probe.gd
## 末行 COMPASS_NEEDLE cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _chart: Node
var _voy: Node


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
	root.size = Vector2i(1280, 720)
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	var gs: Node = root.get_node_or_null("GameState")
	var gm: Node = root.get_node_or_null("GameManager")
	var cal: Node = root.get_node_or_null("Calendar")
	_voy = root.get_node_or_null("Voyage")
	if gs == null or gm == null or cal == null or _voy == null:
		_expect(false, "autoload 不全")
		_report()
		return
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	gs.chapter = 4
	gs.last_port = "quanzhou"
	cal.from_dict({"year": 1260, "month": 3, "day": 1})
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(12)
	if not _chart.has_method("_make_heading_card") or not _chart.has_method("needle_name"):
		_expect(false, "SeaChart 挂上了但没有 _make_heading_card / needle_name（SeaChart.gd 编不过？）")
		_report()
		return
	if not _chart.has_method("_compass_bearing"):
		print("  （SeaChart 无 _compass_bearing：照原先 _draw_compass 的取法复算）")
	var ids: Array = []
	for p in gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	# K1：全港对，罗盘针名 = 真建出来的去向牌上的针名
	_chart.set("sailing", false)
	var n_pairs := 0
	var off: Array = []
	for a in ids:
		_chart.set("origin_port", a)
		for b in ids:
			if a == b:
				continue
			n_pairs += 1
			_chart.set("selected_port", b)
			var card_needle := _card_needle(b)
			var compass := _compass_needle()
			if card_needle == "" or compass != card_needle:
				off.append([absf(angle_difference(deg_to_rad(_compass_deg()), deg_to_rad(float(_voy.overall_bearing(a, b))))),
					"%s→%s 罗盘「%s」/ 牌「%s」" % [a, b, compass, card_needle]])
	off.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var worst: Array = []
	for o in off.slice(0, 5):
		worst.append(o[1])
	_expect(n_pairs >= 150 and off.is_empty(), "K1 全港对 %d 对：未发舶时罗盘针名与去向牌一致（不合 %d 对：%s）" % [n_pairs, off.size(), "; ".join(worst)])
	# K2：照玩家点牌
	for a in ["quanzhou", "mingzhou", "guangzhou"]:
		_chart.set("origin_port", a)
		_chart.set("selected_port", "")
		_chart.call("_refresh_hand")
		await _frames(2)
		var hand: PackedStringArray = _chart.get("_hand")
		var seen := {}
		var bad: Array = []
		for pid in hand:
			_chart.call("_select_heading", pid)
			await _frames(1)
			var compass := _compass_needle()
			seen[compass] = true
			var on_card := _row_card_needle(pid)
			if on_card == "" or compass != on_card:
				bad.append("%s 罗盘「%s」/ 牌「%s」" % [pid, compass, on_card])
		_expect(hand.size() >= 2 and bad.is_empty() and seen.size() >= mini(2, hand.size()),
			"K2 %s 起锚点牌 %s：罗盘针名逐张与牌一致、不同去向不同针（%d 种；不合：%s）" % [a, str(hand), seen.size(), "; ".join(bad)])
	# K3：航行中罗盘跟当日所在那一段
	var drift: Array = []
	for pair in [["mingzhou", "fuzhou"], ["quanzhou", "guangzhou"], ["champa", "hakata"]]:
		var a2: String = pair[0]
		var b2: String = pair[1]
		var total: float = _voy.distance_li(a2, b2)
		_chart.set("origin_port", a2)
		_chart.set("selected_port", b2)
		_chart.set("sailing", true)
		for f in [0.0, 0.25, 0.5, 0.75]:
			var leg: float = _voy.bearing_at(a2, b2, total * f)
			_chart.set("course_bearing", leg)
			if absf(_compass_deg() - leg) > 0.001:
				drift.append("%s→%s@%d%% 罗盘 %.1f° / 当日罗经 %.1f°" % [a2, b2, int(f * 100), _compass_deg(), leg])
		_chart.set("sailing", false)
	_expect(drift.is_empty(), "K3 航行中罗盘跟当日所在那一段的罗经（不合 %d 处：%s）" % [drift.size(), "; ".join(drift.slice(0, 4))])
	_report()


## 罗盘这一刻指的方位（度）：SeaChart._compass_bearing；旧版照原先 _draw_compass 的取法
func _compass_deg() -> float:
	if _chart.has_method("_compass_bearing"):
		return float(_chart.call("_compass_bearing"))
	if bool(_chart.get("sailing")):
		return float(_chart.get("course_bearing"))
	return float(_voy.bearing(str(_chart.get("origin_port")), str(_chart.get("selected_port"))))


func _compass_needle() -> String:
	return str(_chart.call("needle_name", _compass_deg()))


## 现建一张去向牌，读它「N 里　方位　X针」那一行的针名，读完拆掉
func _card_needle(pid: String) -> String:
	var card: Control = _chart.call("_make_heading_card", pid)
	var s := _needle_in(card)
	card.free()
	return s


## 牌区里已发的那张牌（_refresh_hand 建的）上的针名
func _row_card_needle(pid: String) -> String:
	var row: Node = _chart.get("heading_row")
	var pname := str(root.get_node("GameManager").get_port_name(pid))
	for wrap in row.get_children():
		if wrap.is_queued_for_deletion():
			continue
		var labels := _labels_in(wrap)
		if not labels.is_empty() and (labels[0] as Label).text == pname:
			return _needle_in(wrap)
	return ""


func _needle_in(n: Node) -> String:
	for l in _labels_in(n):
		var t := (l as Label).text
		if t.contains("里　"):
			# 「N 里　方位　X针」按全角空格切开取末一截（RegEx 的非空白类不认全角空格为空白）
			var last := t.split("　")[-1]
			if last.ends_with("针"):
				return last
	return ""


func _labels_in(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels_in(c))
	return out


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


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("COMPASS_NEEDLE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
