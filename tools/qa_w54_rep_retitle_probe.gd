extends SceneTree
## lane w54-rep：名声跨过职衔门槛时，那一句札记里写「案册改题「X」。」——回归探针（headless、不截图、不开窗）。
## 病：职衔照名声现算（GameState.title_rank：0 籍外散商 / 10 在册舶牙 / 24 远洋海贾 / 48 舶主 / 80 市舶都保），名声加减一律经
## add_fame（待拍板 29「跳级也只判在一处」），跨档时同一句札记跟一句「案册改题「X」。」——修埠、赴试、呈报、海战胜仗、战后收拾、
## 剿寨、闯封锁、剧情幕都这样写。委办两处漏了：交清时 fame += 1、毁约 / 逾期时 fame = maxi(0, fame - 1)，直接写 fame 绕过
## add_fame（check_symbols 那道闸只管 GameState 之外）：名声 9 交清一单升了在册舶牙（抽解每百 94、赊贷上限多五百），札记只写
## 「名声加 1。」；名声 10 毁约降回籍外散商，罚条只写「名声减 1。」——职衔一声不响就换了。
## 断言（泉州牙行页上的真钮；逾期走 GameManager.advance_days 过日子，罚条经月初 / 每日通告进记事栏）：
##   一、名声 9 按「交货」交清：名声 10、在册舶牙，札记「…名声加 1。案册改题「在册舶牙」。」；
##       名声 5 交清（不跨档）：札记照旧「名声加 1。」、不写改题；
##   二、名声 10 按「毁约」：名声 9、籍外散商，罚条「…名声减 1。案册改题「籍外散商」。」；
##       名声 0 毁约：不写名声减、不写改题、名声仍 0（w53-10 封底照旧）；名声 6 毁约（不跨档）：照写名声减 1、不写改题；
##   三、名声 24 逾期（过了 due_day 的那个早晨）：名声 23、在册舶牙，记事栏那条罚条写「名声减 1。案册改题「在册舶牙」。」
##   四、海图上的征船 / 难民船（SeaChart 四支钮回调接了 add_fame 却不看回执，同病）：事件面真钮——「交出一条船（名声 +6）」
##       名声 4 → 10 在册舶牙、「载人同行」20 → 24 远洋海贾、「分些水粮」47 → 48 舶主、「趁夜溜走」被哨船追上 10 → 6 籍外散商 /
##       26 → 22 在册舶牙，船况札记那一句名声增减后紧跟改题；「分些水粮」5 → 6 不跨档不写。
## 回退即红：deliver_contract / _fail_contract 改回直接写 fame → 一、二、三的跨档格红；SeaChart 四支回调不写改题 → 四的跨档格红
## （不跨档、封底格照绿）。
## 用法：godot --headless --path . -s res://tools/qa_w54_rep_retitle_probe.gd（经门锁跑）
## 输出末行 QA_W54_REP_RETITLE cases=N fails=M；M>0 时 exit 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PORT := "quanzhou"
const GOOD := "tea"

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _finish() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_check(false, "Main.gd 未载入")
		_finish()
		return
	_rates0 = eco.rates.duplicate(true)
	_check(_title_at(9) == "籍外散商" and _title_at(10) == "在册舶牙" and _title_at(23) == "在册舶牙" and _title_at(24) == "远洋海贾",
		"摆场前提：titles.json 门槛 10 / 24（9 %s・10 %s・23 %s・24 %s）" % [_title_at(9), _title_at(10), _title_at(23), _title_at(24)])

	print("── 一、委办交清（牙行页「交货」）")
	await _deliver_case(9, "在册舶牙")
	await _deliver_case(5, "")

	print("── 二、毁约（牙行页「毁约　扣 N」）")
	await _abandon_case(10, "籍外散商")
	await _abandon_case(6, "")
	await _abandon_case(0, "")

	print("── 三、逾期（过日子，罚条走通告进记事栏）")
	await _overdue_case(24, "在册舶牙")

	print("── 四、海上征船 / 难民船（海图事件面上的真钮）")
	await _sea_cases()

	eco.rates = _rates0.duplicate(true)
	_finish()


# ── 摆场 ─────────────────────────────────────────────

## 泉州第一章，景定三年五月初一；一条福船（中）、钱三万、水粮足；名声 fame；contract 为在身委办（空 = 无）
func _stage(fame: int, contract: Dictionary) -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.fame = fame
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("fu_ship_medium", "旗舰")
	gs.contract = contract.duplicate(true)
	gs.broker_salt = 0
	gs.shore_salt = 0
	gs.last_port = PORT
	# 记事栏清空：每格只认自己这一手新进的那几句，不让上一格留下的同字句顶替
	_main.set("_log_lines", PackedStringArray())
	_main.set("_log_folds", {})
	_main.set("_log_fold_open", "")
	_main.set("_notice_run", 0)
	_main.set("_notice_when", [])


## 一笔在身委办：茶叶 8 件、酬 900，交货地 dest、签发港 from，due 日后到期（0 = 今日到期）
func _contract(dest: String, from: String, due: int) -> Dictionary:
	return {
		"good_id": GOOD, "qty": 8, "remaining": 8, "dest": dest, "from": from,
		"purse": 900, "unit_purse": 112.5, "paid": 0,
		"due_day": int(cal.absolute_day()) + due, "deadline_days": 10, "voyage_days": 6,
		"offer_month": int(cal.year) * 12 + int(cal.month),
	}


func _title_at(fame: int) -> String:
	var keep: int = gs.fame
	gs.fame = fame
	var t := str(gs.title_name())
	gs.fame = keep
	return t


# ── 三类案 ───────────────────────────────────────────

## 名声 fame0 时在泉州牙行按「交货」把一单交清；want_title 非空 = 应跨档改题为它，空 = 不跨档、不写改题
func _deliver_case(fame0: int, want_title: String) -> void:
	_stage(fame0, {})
	gs.contract = _contract(PORT, "fuzhou", 5)
	fleet.add_cargo(GOOD, 8, 20.0, 0)
	_main.load_scene(PORT + "_market")
	await _settle(3)
	var give := _find_button(_panel(), "交货")
	var pressed := give != null and not give.disabled
	if pressed:
		give.pressed.emit()
		await _settle(2)
	var line := _new_line("委办交清")
	_judge("名声 %d 按「交货」交清" % fame0, pressed and gs.contract.is_empty(), fame0, fame0 + 1, "名声加 1。", want_title, line)


## 名声 fame0 时在泉州牙行按「毁约　扣 N」；want_title 同上
func _abandon_case(fame0: int, want_title: String) -> void:
	_stage(fame0, {})
	gs.contract = _contract("fuzhou", PORT, 5)
	_main.load_scene(PORT + "_market")
	await _settle(3)
	var drop := _find_prefix(_panel(), "毁约")
	var pressed := drop != null
	if pressed:
		drop.pressed.emit()
		await _settle(2)
	var line := _new_line("委办作废")
	_judge("名声 %d 按「毁约」" % fame0, pressed and gs.contract.is_empty(), fame0, maxi(0, fame0 - 1),
		"名声减 1。" if fame0 > 0 else "", want_title, line)


## 名声 fame0、委办今日到期，在泉州港页上过一日：次晨作废，罚条经通告进记事栏
func _overdue_case(fame0: int, want_title: String) -> void:
	_stage(fame0, {})
	gs.contract = _contract("fuzhou", PORT, 0)
	_main.load_scene(PORT)
	await _settle(3)
	gm.advance_days(1)
	await _settle(2)
	var line := _new_line("没能送到")
	_judge("名声 %d 委办逾期" % fame0, gs.contract.is_empty(), fame0, fame0 - 1, "名声减 1。", want_title, line)


## 海图上四样改名声的事：征船「交出一条船（名声 +6）」「趁夜溜走」被追上（名声 −4）、难民「载人同行」（+4）「分些水粮」（+1）。
## 起一张海图停在海上半途（不在航行、余程未尽：钮回调末尾的 _on_event_continue 不往下走），照 Voyage 的真事件挂事件面、按真钮，
## 札记取海图船况札记最上一条。
func _sea_cases() -> void:
	var voy: Node = root.get_node("Voyage")
	_stage(0, {})
	gs.chapter = 4
	cal.from_dict({"year": 1275, "month": 6, "day": 5})
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("fu_ship_medium", "旗舰")
	fleet.add_ship("keel_boat", "二号")
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _settle(4)
	chart.set("sailing", false)
	chart.set("remaining_li", 500.0)
	var req: Dictionary = voy.call("_requisition_event")
	var ref: Dictionary = voy.call("_refugee_event")
	# 交出一条船：名声 4 → 10 升在册舶牙（交出的是小的那条，旗舰留下）
	await _sea_case(chart, req, "交出一条船（名声 +6）", 4, 10, "名声加 6。", "在册舶牙", "编入官军")
	# 载人同行：名声 20 → 24 升远洋海贾；分些水粮：名声 47 → 48 升舶主、名声 5 → 6 不跨档不写改题
	await _sea_case(chart, ref, "载人同行（水粮 −2 成）", 20, 24, "名声加 4。", "远洋海贾", "把人接上船")
	await _sea_case(chart, ref, "分些水粮，不载人（水粮 −1 成）", 47, 48, "名声加 1。", "舶主", "递过去几桶水")
	await _sea_case(chart, ref, "分些水粮，不载人（水粮 −1 成）", 5, 6, "名声加 1。", "", "递过去几桶水")
	# 趁夜溜走被哨船追上（种子挑到掷输那一手）：名声 10 → 6 降籍外散商；名声 26 → 22 降在册舶牙
	var chance := clampf(float(fleet.call("fleet_speed")) / 240.0, 0.2, 0.85)
	var lose := -1
	for k in range(1, 5000):
		seed(k)
		if randf() >= chance:
			lose = k
			break
	for f in [[10, "籍外散商"], [26, "在册舶牙"]]:
		await _sea_case(chart, req, "趁夜溜走", int(f[0]), int(f[0]) - 4, "名声减 4", str(f[1]), "被哨船追上", lose)
	chart.queue_free()
	await _settle(2)


## 名声 fame0 时挂事件 ev、按钮 btn_text：名声应到 fame1、札记含 key 那一句写 fame_bit，跨档（want_title 非空）紧跟改题；
## rng_seed ≥ 0 时按下前播种（趁夜溜走那一掷）
func _sea_case(chart: Node, ev: Dictionary, btn_text: String, fame0: int, fame1: int, fame_bit: String, want_title: String, key: String, rng_seed := -1) -> void:
	gs.fame = fame0
	gs.money = 1000
	fleet.water = 600
	fleet.food = 600
	chart.set("_log_lines", PackedStringArray())
	chart.call("_show_event", ev)
	await _settle(1)
	var btn := _find_button(chart.get("event_actions"), btn_text)
	var pressed := btn != null
	if pressed:
		if rng_seed >= 0:
			seed(rng_seed)  # 按下那一刻才播种：挂事件面、等帧都不吃掉这一掷
		btn.pressed.emit()
		await _settle(2)
	var line := ""
	for l in (chart.get("_log_lines") as PackedStringArray):
		if str(l).contains(key):
			line = str(l)
			break
	var bit := fame_bit + ("。" if not fame_bit.ends_with("。") else "")
	_judge("海图「%s」名声 %d" % [btn_text, fame0], pressed, fame0, fame1, bit, want_title, line)


## 一格判：账（名声、职衔）与札记那一句（名声增减照旧；跨档时紧跟「案册改题「X」。」，不跨档时不写改题）
func _judge(what: String, acted: bool, fame0: int, fame1: int, fame_bit: String, want_title: String, line: String) -> void:
	var title_now := str(gs.title_name())
	var ok := acted and int(gs.fame) == fame1 and line != ""
	if fame_bit != "":
		ok = ok and line.contains(fame_bit)
	else:
		ok = ok and not line.contains("名声减") and not line.contains("名声加")
	if want_title != "":
		ok = ok and title_now == want_title and line.contains(fame_bit + "案册改题「%s」。" % want_title)
	else:
		ok = ok and title_now == _title_at(fame0) and not line.contains("改题")
	_check(ok, "%s：名声 %d → %d（应 %d）、职衔「%s」；札记「%s」%s" % [
		what, fame0, int(gs.fame), fame1, title_now, line,
		"应跟「案册改题「%s」。」" % want_title if want_title != "" else "不跨档、不该写改题"])


# ── 记事栏 ───────────────────────────────────────────

## 本格动手之后进记事栏、含 key 的那一句（_stage 已清空记事栏；新的在前，折起的通告也翻进去找）；找不到给 ""
func _new_line(key: String) -> String:
	var lines: PackedStringArray = _main.get("_log_lines")
	var folds: Dictionary = _main.get("_log_folds")
	for l in lines:
		if str(l).contains(key):
			return str(l)
		if folds.has(l):
			for inner in (folds[l] as Dictionary).get("lines", []):
				if str(inner).contains(key):
					return str(inner)
	return ""


# ── 小件 ─────────────────────────────────────────────

func _panel() -> Node:
	return _main.get("choices_container").get_node_or_null("ContractPanel")


func _find_button(n: Node, text: String) -> Button:
	if n == null or n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _find_prefix(n: Node, prefix: String) -> Button:
	if n == null or n.is_queued_for_deletion():
		return null
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text.begins_with(prefix):
		return n as Button
	for c in n.get_children():
		var b := _find_prefix(c, prefix)
		if b != null:
			return b
	return null


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _finish() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("QA_W54_REP_RETITLE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
