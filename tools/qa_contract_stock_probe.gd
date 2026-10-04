extends SceneTree
## Lane iz2：headless 探针——委办「凑得出 N 件」按今日柜上现货算。
##   一、货不在柜上：单上凑得出 = 舱里现有，照单去买（不动 broker_hand）一件也买不到；单上写明不在柜上，摘要挂「凑不齐」。
##   二、货在柜上：凑得出 = 逐船照买件数（lane iz 口径不退）。
##   三、「明日再看」换上柜后，单上件数随柜更新，仍 = 照买件数。
## 用法：godot --headless --path . -s res://tools/qa_contract_stock_probe.gd
## 输出末行 IZ2_PROBE fails=N；N>0 时 exit 1。

## lane w53-3（四轮）：本进程 SCRIPT ERROR 即红——接共用件 tools/script_err_tally.gd（某段函数里出脚本错只中止那一个函数，
## 断言整段跳过、fails 不涨、headless -s 退出码守 0）；_run_guarded 包一层兜「_run 自己的代码行出错即中止、
## quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
var _ships0: Array = []
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
	eco = root.get_node("/root/Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	_rates0 = eco.rates.duplicate(true)
	_ships0 = fleet.ships.duplicate(true)

	var off := await _find_case(false)
	var on := await _find_case(true)
	_expect(not off.is_empty(), "找到一处委办货不在今日柜上的港（ch1 各港 × 柜序 0..11）")
	_expect(not on.is_empty(), "找到一处委办货在今日柜上、现银买不满的港")
	if not off.is_empty():
		await _off_counter(off)
		await _rotate_in(off)
	if not on.is_empty():
		await _on_counter(on)

	_report()


func _reset(port_id: String, money: int, salt: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	fleet.ships = _ships0.duplicate(true)
	gs.last_port = port_id
	gs.money = money
	gs.debt = 0
	gs.broker_salt = salt


## 找一处委办：want_on=false 找货不在柜上，true 找在柜上；两种都要 1000 现银买不满、舱里都不带这货。
func _find_case(want_on: bool) -> Dictionary:
	for p in gm.unlocked_ports():
		var pid := str(p.get("id", ""))
		for salt in 12:
			_reset(pid, 1000, salt)
			var offer: Dictionary = gs.contract_offer(pid)
			if offer.is_empty():
				continue
			var gid := str(offer.get("good_id", ""))
			if fleet.cargo_qty(gid) > 0:
				continue
			_main.load_scene(pid + "_market")
			await _settle(3)
			var hand: PackedStringArray = _main.get("broker_hand")
			var on_counter := gid in hand
			if on_counter != want_on:
				continue
			# 两种都要现银买不满：不在柜上那一处，三节等它上柜后要读单上「凑得出 N 件」，买得满时那句不出（读成 -1）。
			# 原先只给在柜上那一处设这道，开局行情随机抽到便宜货时三节就红（lane w53-3：四回红两回）
			if _afford(pid, gid, 1000, _room(gid)) >= int(offer.get("qty", 0)):
				continue
			return {"port": pid, "salt": salt, "gid": gid, "need": int(offer.get("qty", 0)), "hand": hand}
	return {}


# ── 一、货不在柜上 ────────────────────────────────────

func _off_counter(c: Dictionary) -> void:
	var port := str(c["port"])
	var gid := str(c["gid"])
	print("── 一、货不在柜上：%s 柜序 %d，委办 %s ×%d，柜上 %s" % [
		port, int(c["salt"]), gm.get_good_name(gid), int(c["need"]), _names(c["hand"])])
	_reset(port, 1000, int(c["salt"]))
	_main.load_scene(port + "_market")
	await _settle(3)
	var lbl := _label_containing("凑得出")
	var shown := _shown_qty(lbl)
	var held0: int = fleet.cargo_qty(gid)
	var would := _afford(port, gid, 1000, _room(gid))
	print("   单上写「%s」" % lbl)
	print("   若在柜上本可买 %d 件；舱里现有 %d 件" % [would, held0])
	var bought := await _buy_through(port, gid, int(c["need"]))
	print("   逐船照单去买（不动柜）得 %d 件，现银仍 %d" % [bought, gs.money])
	_expect(bought == 0, "货不在柜上，今日一件也买不到（_on_buy 拦下）")
	_expect(shown == held0 + bought, "单上凑得出 %d 件 = 舱里现有 %d + 今日实买 %d" % [shown, held0, bought])
	_expect(lbl.contains("不在柜上"), "单上写明此货今日不在柜上")
	_expect(_flag_text().contains("凑不齐"), "摘要行挂「凑不齐」（%s）" % _flag_text())
	# 现银足够买满时，旧口径连缺口句都不出，只看单子会以为今日就凑得齐
	_reset(port, 20000, int(c["salt"]))
	_main.load_scene(port + "_market")
	await _settle(3)
	var rich := _label_containing("凑得出")
	var rich_would := _afford(port, gid, 20000, _room(gid))
	print("   现银 20000（若在柜上本可买 %d 件，单须 %d）：单上写「%s」，摘要「%s」" % [
		rich_would, int(c["need"]), rich, _flag_text()])
	_expect(_shown_qty(rich) == 0 and rich.contains("不在柜上") and _flag_text().contains("凑不齐"),
		"钱足也照实写：凑得出 0 件、不在柜上、挂「凑不齐」")


# ── 三、明日再看换上柜 ────────────────────────────────

func _rotate_in(c: Dictionary) -> void:
	var port := str(c["port"])
	var gid := str(c["gid"])
	print("── 三、明日再看，等 %s 换上柜" % gm.get_good_name(gid))
	_reset(port, 1000, int(c["salt"]))
	_main.load_scene(port + "_market")
	await _settle(3)
	var month0: int = cal.month
	var waited := 0
	while waited < 12 and gid not in _main.get("broker_hand"):
		_main.call("_on_broker_wait")
		await _settle(3)
		waited += 1
	var hand: PackedStringArray = _main.get("broker_hand")
	_expect(gid in hand and cal.month == month0, "等 %d 日换上柜，仍在当月（柜上 %s）" % [waited, _names(hand)])
	if gid not in hand:
		return
	var offer: Dictionary = gs.contract_offer(port)
	_expect(str(offer.get("good_id", "")) == gid, "当月委办货未变")
	var lbl := _label_containing("凑得出")
	var shown := _shown_qty(lbl)
	var money0: int = gs.money
	var want := _afford(port, gid, money0, _room(gid))
	print("   单上写「%s」" % lbl)
	var bought := await _buy_through(port, gid, int(c["need"]))
	print("   现银 %d，逐船照买得 %d 件（探针自算 %d）" % [money0, bought, want])
	_expect(not lbl.contains("不在柜上"), "上柜后不再写不在柜上")
	_expect(shown == bought and bought == want and bought > 0, "单上凑得出 %d = 照买 %d = 自算 %d" % [shown, bought, want])


# ── 二、货在柜上 ──────────────────────────────────────

func _on_counter(c: Dictionary) -> void:
	var port := str(c["port"])
	var gid := str(c["gid"])
	print("── 二、货在柜上：%s 柜序 %d，委办 %s ×%d，柜上 %s" % [
		port, int(c["salt"]), gm.get_good_name(gid), int(c["need"]), _names(c["hand"])])
	_reset(port, 1000, int(c["salt"]))
	_main.load_scene(port + "_market")
	await _settle(3)
	var lbl := _label_containing("凑得出")
	var shown := _shown_qty(lbl)
	var want := _afford(port, gid, 1000, _room(gid))
	print("   单上写「%s」" % lbl)
	var bought := await _buy_through(port, gid, int(c["need"]))
	print("   逐船照买得 %d 件（探针自算 %d），余钱 %d，再一件要 %d" % [
		bought, want, gs.money, int(eco.estimate_buy_cost(port, gid, 1))])
	_expect(lbl.contains("首件") and not lbl.contains("不在柜上"), "在柜上仍按首件逐件加价写")
	_expect(shown == bought and bought == want, "单上凑得出 %d = 照买 %d = 自算 %d" % [shown, bought, want])


# ── 小件 ──────────────────────────────────────────────

## 逐船照单去买，走真 _on_buy（它自己查 broker_hand），返回实买件数。
func _buy_through(port: String, gid: String, need: int) -> int:
	var before: int = fleet.cargo_qty(gid)
	for si in fleet.ships.size():
		_main.call("_on_buy", port, gid, need, si)
		await _settle(1)
	return int(fleet.cargo_qty(gid)) - before


func _room(gid: String) -> int:
	var room := 0
	for si in fleet.ships.size():
		room += int(fleet.max_loadable(gid, si))
	return room


## 探针自带的实买件数：逐件加一，直到 estimate_buy_cost 超过现银或舱位（不借 Main 的算法，免得自证）
func _afford(pid: String, gid: String, money: int, cap: int) -> int:
	var n := 0
	while n < cap and int(eco.estimate_buy_cost(pid, gid, n + 1)) <= money:
		n += 1
	return n


func _shown_qty(t: String) -> int:
	var re := RegEx.new()
	re.compile("凑得出 (\\d+) 件")
	var m := re.search(t)
	return int(m.get_string(1)) if m != null else -1


func _names(hand) -> String:
	var out := PackedStringArray()
	for gid in hand:
		out.append(gm.get_good_name(str(gid)))
	return "、".join(out)


func _flag_text() -> String:
	var n := _find(_main, func(x: Node) -> bool: return x is Label and x.name == "ContractFlag")
	return str((n as Label).text) if n != null and (n as Label).visible else ""


func _label_containing(t: String) -> String:
	var n := _find(_main, func(x: Node) -> bool: return x is Label and str((x as Label).text).contains(t))
	return str((n as Label).text) if n != null else ""


func _find(n: Node, pred: Callable) -> Node:
	if n == null:
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("IZ2_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame
