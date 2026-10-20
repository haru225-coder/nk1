extends SceneTree
## lane w54-econ：headless 探针——章节「本钱」按现银减欠款记，赊来的钱顶不高资金峰值。
## 晋升与了结看 GameState.peak_money（第一章五千、第二章两万、第三章六万、了结八万）。原先 add_money 照现银记峰值，
## 赊贷 borrow 也走 add_money：开局籍外散商可赊三千，真挣到两千、在船屋连按「赊」借满三千，峰值即到五千，
## 「攒下五千钱本」当场就够了；随手「还」清，峰值不退，同月还清连一文息都不付。改后峰值按现银减欠款记。
##   一、真挣到 2000，船屋按「赊 2000」「赊 500」「赊 500」借满 3000：现银 5000、欠 3000，峰值仍 2000，
##       章目「本钱」一格未够，其余条件摆齐也不晋升（改前峰值 5000、当场晋第二章）。
##   二、按「还」当场还清：欠款归零，峰值不动。
##   三、没有欠款时照旧：挣到五千峰值就是五千，「本钱」一格够了、晋第二章。
##   四、欠着款挣钱：峰值按现银减欠款涨（欠 3000、现银挣到 7000，峰值 4000，不是 7000）。
##   五、花钱、月息都不动峰值。
## 用法：godot --headless --path . -s res://tools/qa_w54_econ_peak_probe.gd（经门锁跑）
## 输出末行 W54_ECON_PEAK_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_rumor_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
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
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	await _borrow_no_peak()
	await _repay_no_peak()
	_no_debt_as_before()
	_earn_while_owing()
	_spend_and_interest()
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
	print("W54_ECON_PEAK_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 第一章开局：现银 1000、峰值 1000、无欠款；除「本钱」外的晋升条件（走通五处、亲至南岛海道北口）摆齐
func _fresh() -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1256, "month": 4, "day": 10})
	gs.chapter = 1
	gs.last_port = "quanzhou"
	var req: Dictionary = gs.chapter_def(1).get("next_requires", {})
	var vis: Array = []
	for pid in req.get("must_visit", []):
		vis.append(str(pid))
	for p in gm.ports_data.get("ports", []):
		var pid := str(p.get("id", ""))
		if vis.size() < int(req.get("visited_count", 0)) and not (pid in vis) and str(p.get("unlock", "ch1")) == "ch1":
			vis.append(pid)
	gs.visited_ports = vis


## 章目「本钱」那一格
func _capital_item() -> Dictionary:
	for it in (gs.chapter_progress().get("items", []) as Array):
		if str((it as Dictionary).get("label", "")) == "本钱":
			return it
	return {}


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


## 在泉州船屋按一枚钮（找不到给 false）
func _press(text: String) -> bool:
	_main.load_scene("quanzhou_shipyard")
	await _settle(2)
	var b := _find_button(_main, text)
	if b == null:
		print("    船屋页上找不到钮「%s」" % text)
		return false
	b.emit_signal("pressed")
	await _settle(2)
	return true


func _borrow_no_peak() -> void:
	print("── 一、真挣两千、借满三千：峰值不动，不晋升")
	_fresh()
	gs.add_money(1000)
	var need := int(_capital_item().get("need", 0))
	_expect(int(gs.money) == 2000 and int(gs.peak_money) == 2000 and need == 5000,
		"一、开局 1000 挣到 2000：现银 %d、峰值 %d，第一章本钱要 %d（应 5000）" % [int(gs.money), int(gs.peak_money), need])
	var pressed := 0
	for t in ["赊 2000", "赊 500", "赊 500"]:
		if await _press(t):
			pressed += 1
	_expect(pressed == 3 and int(gs.debt) == 3000 and int(gs.money) == 5000,
		"一、船屋连按「赊 2000」「赊 500」「赊 500」：欠 %d、现银 %d（应 3000 / 5000）" % [int(gs.debt), int(gs.money)])
	var it := _capital_item()
	_expect(int(gs.peak_money) == 2000 and int(it.get("current", -1)) == 2000 and not bool(it.get("done", true)),
		"一、峰值仍 %d（应 2000，改前 5000），章目「本钱 %d / %d」未够" % [int(gs.peak_money), int(it.get("current", -1)), int(it.get("need", 0))])
	var res: Dictionary = gs.try_advance_chapter()
	_expect(not bool(res.get("advanced", true)) and int(gs.chapter) == 1,
		"一、走通、亲至都摆齐，赊来的三千不顶本钱：不晋升（仍第 %d 章）" % int(gs.chapter))


func _repay_no_peak() -> void:
	print("── 二、当场还清：峰值不动")
	var pay := mini(int(gs.debt), int(gs.money))
	var ok := await _press("还 %d" % pay)
	_expect(ok and int(gs.debt) == 0 and int(gs.money) == 2000 and int(gs.peak_money) == 2000,
		"二、按「还 %d」：欠 %d、现银 %d、峰值 %d（应 0 / 2000 / 2000）" % [pay, int(gs.debt), int(gs.money), int(gs.peak_money)])


func _no_debt_as_before() -> void:
	print("── 三、没有欠款：照旧按现银记")
	_fresh()
	gs.add_money(4000)
	var it := _capital_item()
	_expect(int(gs.peak_money) == 5000 and bool(it.get("done", false)),
		"三、挣到 5000：峰值 %d、章目「本钱」够了" % int(gs.peak_money))
	var res: Dictionary = gs.try_advance_chapter()
	_expect(bool(res.get("advanced", false)) and int(gs.chapter) == 2, "三、晋第二章（实为第 %d 章）" % int(gs.chapter))


func _earn_while_owing() -> void:
	print("── 四、欠着款挣钱：峰值按现银减欠款涨")
	_fresh()
	gs.add_money(1000)
	gs.borrow(3000)
	gs.add_money(2000)
	_expect(int(gs.money) == 7000 and int(gs.peak_money) == 4000,
		"四、欠 3000、现银挣到 %d：峰值 %d（应 4000，不是 7000）" % [int(gs.money), int(gs.peak_money)])


func _spend_and_interest() -> void:
	print("── 五、花钱、月息不动峰值")
	_fresh()
	gs.add_money(2000)
	gs.borrow(1000)
	var p0: int = gs.peak_money
	gs.spend_money(2500)
	var interest: int = gs.accrue_interest()
	_expect(int(gs.peak_money) == p0 and p0 == 3000 and interest > 0,
		"五、峰值 %d 花掉 2500、结息 %d 之后仍 %d" % [p0, interest, int(gs.peak_money)])
