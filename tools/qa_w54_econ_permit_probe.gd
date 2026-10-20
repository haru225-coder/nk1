extends SceneTree
## lane w54-econ：headless 探针——货引按出港时的舱货抽解，请领之后再装的货出港前补。
## 原先货引是一面布尔，抽解按请领那一刻的舱货算（GameState.customs_duty）：空舱请领只付地板 20 钱，再去牙行装满一舱，
## 出港照样「出示了泉州货引，缴过抽解，安全放行」——按舱货抽解形同虚设。改后请领时记下所报舱货的计税基数 permit_base，
## 出港（Main._on_set_sail → GameState.depart_inspection）先补「现舱货的抽解 − 请领时舱货的抽解」，两头按现时同一税率。
##   一、空舱请领（付 20）再装青白瓷 100 件：出港补 880，合计 900 = 装好货再请领的抽解；札记那句标签后头写补了多少。
##   二、装好货再请领、没再添货：不补，验放结果与 customs_inspection 逐字相同，钱不动。
##   三、请领之后卖掉一半：不补也不退。
##   四、补不起：不放行、不没收，货引仍在手、舱货钱数都不动；凑足了钱再验即放行。
##   五、旧档里带进来的货引（档里没有 permit_base）：照旧放行，不补。
##   六、存档：to_dict 写 permit_base；读档只认数字，字符串 / 数组 / 字典读成 -1。
##   七、市舶司页：货引已在手又添了货，货引卡写「请领之后舱里又添了货，出港时补抽解 N。」；没添货仍写「本次出港可合法验放。」
##   八、真按出港（Main._on_set_sail）补不起的那一路：留在港里，记事栏写缘由与要补的数，货引、舱货、钱都不动。
## 用法：godot --headless --path . -s res://tools/qa_w54_econ_permit_probe.gd（经门锁跑）
## 输出末行 W54_ECON_PERMIT_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_rumor_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const GOOD := "qingbai_porcelain"
const QTY := 100
## 1256 年四月泉州忠宋、不雇杂事、名声 0：抽解一成；青白瓷 base 90 × 100 件 = 基数 9000、抽解 900
const WANT_BASE := 9000
const WANT_DUTY := 900

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
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
	fleet = root.get_node("/root/Fleet")
	crew = root.get_node("/root/Crew")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	cal.from_dict({"year": 1256, "month": 4, "day": 10})
	crew.hired = {}
	gs.fame = 0
	gs.last_port = "quanzhou"
	gs.pu_attention = 0
	fleet.water = 40
	fleet.food = 40
	_expect(is_equal_approx(float(root.get_node("/root/Economy").duty_rate("quanzhou")), 0.10),
		"前提：1256 年四月泉州、不雇杂事、名声 0，抽解一成（实为 %s）" % str(root.get_node("/root/Economy").duty_rate("quanzhou")))
	_expect(fleet.can_sail() and fleet.supply_days() >= 2, "前提：旗舰人手够、水粮撑得过两日（出港前两道关先过）")

	_empty_then_load()
	_load_then_apply()
	_sell_after()
	_short_of_money()
	_legacy_permit()
	_save_keys()
	await _yamen_card()
	await _set_sail_short()
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
	print("W54_ECON_PERMIT_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 舱清空、货引收回，钱给足
func _reset(money: int) -> void:
	fleet.clear_cargo()
	gs.has_customs_permit = false
	gs.permit_base = -1
	gs.pu_attention = 0
	gs.money = money


func _load_goods(n: int) -> bool:
	return bool(fleet.add_cargo(GOOD, n, 60.0, 0))


## 出港成功时 Main 随后就收回货引（consume_permit），这里照做，下一节从头摆
func _depart() -> Dictionary:
	var res: Dictionary = gs.depart_inspection()
	if bool(res.get("passed", false)):
		gs.consume_permit()
	return res


func _empty_then_load() -> void:
	print("── 一、空舱请领再装货：出港补足")
	_reset(20000)
	var applied: Dictionary = gs.apply_for_permit()
	var paid_apply: int = 20000 - int(gs.money)
	_expect(bool(applied.get("ok", false)) and paid_apply == 20 and int(gs.permit_base) == 0,
		"一、空舱请领付地板 20（实付 %d），记下所报基数 0（实为 %d）" % [paid_apply, int(gs.permit_base)])
	_expect(_load_goods(QTY), "一、请领之后装青白瓷 %d 件" % QTY)
	var duty_now: int = gs.customs_duty()
	var owed: int = gs.permit_topup()
	_expect(duty_now == WANT_DUTY and owed == WANT_DUTY - 20,
		"一、现舱货抽解 %d（应 %d），出港要补 %d（应 %d）" % [duty_now, WANT_DUTY, owed, WANT_DUTY - 20])
	var m0: int = gs.money
	var res := _depart()
	var paid_depart: int = m0 - int(gs.money)
	var msg := str(res.get("msg", ""))
	_expect(bool(res.get("passed", false)) and paid_depart == WANT_DUTY - 20,
		"一、出港放行，补抽解 %d（实扣 %d）" % [WANT_DUTY - 20, paid_depart])
	_expect(paid_apply + paid_depart == WANT_DUTY,
		"一、请领 + 补抽解合计 %d = 装好货再请领的抽解 %d" % [paid_apply + paid_depart, WANT_DUTY])
	var want_head := "【市舶司验引】请领货引之后舱里又添了货，补抽解 %d 钱。" % (WANT_DUTY - 20)
	_expect(msg.begins_with(want_head) and msg.count("【") == 1,
		"一、札记标签后头写补了多少、只一枚标签（记事栏只去第一枚）：「%s」" % msg.replace("\n", " ⏎ "))
	var plain := str(_plain_inspection_text())
	_expect(msg == want_head + plain.trim_prefix("【市舶司验引】"),
		"一、补税一句之后接 customs_inspection 原句「%s」" % plain)


## 有引无违禁、钱足时 customs_inspection 那一句（这一支不改任何账）
func _plain_inspection_text() -> String:
	var keep := {"permit": gs.has_customs_permit, "base": gs.permit_base, "att": gs.pu_attention, "money": gs.money}
	gs.has_customs_permit = true
	var res: Dictionary = gs.customs_inspection()
	gs.has_customs_permit = keep["permit"]
	gs.permit_base = keep["base"]
	gs.pu_attention = keep["att"]
	gs.money = keep["money"]
	return str(res.get("msg", ""))


func _load_then_apply() -> void:
	print("── 二、装好货再请领：不补，札记逐字照旧")
	_reset(20000)
	_load_goods(QTY)
	gs.apply_for_permit()
	var paid_apply: int = 20000 - int(gs.money)
	_expect(paid_apply == WANT_DUTY and int(gs.permit_base) == WANT_BASE,
		"二、请领付 %d（应 %d），记下基数 %d（应 %d）" % [paid_apply, WANT_DUTY, int(gs.permit_base), WANT_BASE])
	_expect(int(gs.permit_topup()) == 0, "二、没再添货，出港不补（%d）" % int(gs.permit_topup()))
	var plain := _plain_inspection_text()
	var m0: int = gs.money
	var res := _depart()
	_expect(bool(res.get("passed", false)) and str(res.get("msg", "")) == plain and int(gs.money) == m0,
		"二、验放结果与 customs_inspection 逐字相同「%s」、钱不动（%d → %d）" % [str(res.get("msg", "")), m0, int(gs.money)])


func _sell_after() -> void:
	print("── 三、请领之后卖掉一半：不补不退")
	_reset(20000)
	_load_goods(QTY)
	gs.apply_for_permit()
	fleet.remove_cargo(GOOD, QTY / 2)
	var m0: int = gs.money
	var owed: int = gs.permit_topup()
	var res := _depart()
	_expect(owed == 0 and bool(res.get("passed", false)) and int(gs.money) == m0,
		"三、舱货少了一半：要补 %d（应 0）、放行、钱不动（%d → %d）" % [owed, m0, int(gs.money)])


func _short_of_money() -> void:
	print("── 四、补不起：不放行，货引与舱货都在")
	_reset(20000)
	gs.apply_for_permit()
	_load_goods(QTY)
	gs.money = 100
	var res: Dictionary = gs.depart_inspection()
	var msg := str(res.get("msg", ""))
	_expect(not bool(res.get("passed", true)) and not bool(res.get("confiscated", true)),
		"四、现银 100 补不起 %d：不放行、不没收" % (WANT_DUTY - 20))
	_expect(bool(gs.has_customs_permit) and int(fleet.cargo_qty(GOOD)) == QTY and int(gs.money) == 100,
		"四、货引仍在手（%s）、舱货 %d 件（应 %d）、钱 %d（应 100）" % [str(gs.has_customs_permit), int(fleet.cargo_qty(GOOD)), QTY, int(gs.money)])
	_expect(msg.contains("补抽解 %d 钱" % (WANT_DUTY - 20)) and msg.contains("囊中不足"),
		"四、札记写要补的数与囊中不足：「%s」" % msg)
	gs.money = 5000
	var res2 := _depart()
	_expect(bool(res2.get("passed", false)) and int(gs.money) == 5000 - (WANT_DUTY - 20),
		"四、凑足钱再验：补 %d 放行（钱 5000 → %d）" % [WANT_DUTY - 20, int(gs.money)])


func _legacy_permit() -> void:
	print("── 五、旧档里带进来的货引：照旧放行，不补")
	_reset(20000)
	var st: Dictionary = gs.to_dict()
	st.erase("permit_base")
	st["has_customs_permit"] = true
	gs.from_dict(st)
	_expect(int(gs.permit_base) == -1 and bool(gs.has_customs_permit), "五、档里没有 permit_base：货引在手、基数读成 -1（实为 %d）" % int(gs.permit_base))
	_load_goods(QTY)
	var m0: int = gs.money
	var plain := _plain_inspection_text()
	var owed: int = gs.permit_topup()
	var res := _depart()
	_expect(owed == 0 and bool(res.get("passed", false)) and str(res.get("msg", "")) == plain and int(gs.money) == m0,
		"五、旧档的货引照旧放行：要补 %d（应 0），札记「%s」、钱不动" % [owed, str(res.get("msg", ""))])


func _save_keys() -> void:
	print("── 六、存档：permit_base 写进 to_dict，读档只认数字")
	_reset(20000)
	_load_goods(QTY)
	gs.apply_for_permit()
	var st: Dictionary = gs.to_dict()
	_expect(st.has("permit_base") and int(st["permit_base"]) == WANT_BASE, "六、to_dict 写 permit_base = %s（应 %d）" % [str(st.get("permit_base")), WANT_BASE])
	var round_trip: Variant = JSON.parse_string(JSON.stringify(st))
	gs.from_dict(round_trip as Dictionary)
	_expect(int(gs.permit_base) == WANT_BASE and bool(gs.has_customs_permit) and int(gs.permit_topup()) == 0,
		"六、过一遍 JSON 读回：基数 %d、货引在手、不补" % int(gs.permit_base))
	var bad_ok := true
	for bad in ["一千", [1], {"a": 1}, null, true]:
		var b: Dictionary = st.duplicate(true)
		b["permit_base"] = bad
		gs.from_dict(b)
		if int(gs.permit_base) != -1:
			bad_ok = false
			print("    permit_base = %s 读成 %d" % [JSON.stringify(bad), int(gs.permit_base)])
	_expect(bad_ok, "六、permit_base 给成字符串 / 数组 / 字典 / null / 布尔都读成 -1，不报错")
	gs.from_dict(st)


## 市舶司页货引卡上的那一句
func _yamen_card() -> void:
	print("── 七、市舶司页：货引卡写要补多少")
	_reset(20000)
	gs.apply_for_permit()
	_load_goods(QTY)
	_main.load_scene("quanzhou_yamen")
	await _settle(2)
	var want := "请领之后舱里又添了货，出港时补抽解 %d。" % (WANT_DUTY - 20)
	_expect(_has_label(_main, want) and not _has_label(_main, "本次出港可合法验放。"),
		"七、请领之后又添了货：货引卡写「%s」，不写「本次出港可合法验放。」" % want)
	fleet.clear_cargo()
	_main.load_scene("quanzhou_yamen")
	await _settle(2)
	_expect(_has_label(_main, "本次出港可合法验放。") and not _has_label(_main, want),
		"七、舱里没添货：货引卡照旧「本次出港可合法验放。」")


func _has_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _has_label(c, text):
			return true
	return false


## 真按出港钮的回调，走补不起那一路（放行那一路会换场景进海图）
func _set_sail_short() -> void:
	print("── 八、真按出港（Main._on_set_sail）补不起：留在港里")
	_reset(20000)
	gs.apply_for_permit()
	_load_goods(QTY)
	gs.money = 100
	_main.load_scene("quanzhou")
	await _settle(2)
	var before := str(_main.get("current_scene_id"))  # 港口节拍可能先把港页换成一段剧情页：只比按钮前后没换页
	_main.call("_on_set_sail")
	await _settle(2)
	var logs: PackedStringArray = _main.get("_log_lines")
	var line := str(logs[0]) if logs.size() > 0 else ""
	var want := "货引是按请领时的舱货开的，后装上船的货要补抽解 %d 钱，你囊中不足，小吏把货单推了回来。" % (WANT_DUTY - 20)
	_expect(line == want, "八、记事栏头一行「%s」（实为「%s」）" % [want, line])
	_expect(bool(gs.has_customs_permit) and int(fleet.cargo_qty(GOOD)) == QTY and int(gs.money) == 100 and str(_main.get("current_scene_id")) == before,
		"八、留在港里不出海（页 %s → %s）、货引仍在手、舱货 %d 件、钱 %d" % [before, str(_main.get("current_scene_id")), int(fleet.cargo_qty(GOOD)), int(gs.money)])
