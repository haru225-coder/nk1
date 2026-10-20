extends SceneTree
## lane-w54-story：升章跳年时身上的委办免罚作罢（w53 待拍板 15 已定、未实施：「升章跳年时身上的委办作废、不扣钱不扣名声，
## 札记写一句『跳年委办作罢』。理由：跳年是剧情把几年一笔带过，玩家没机会交货，算他违约不公道」）。
## 修前：GameManager.skip_years 把这几年逐日走完，过了 due_day 那个早晨 GameState.tick_contract 照逾期作废——扣酬金一成五
## （至少 40）、名声减 1、封签发港当月的单，记事栏一条「【逾期】」；开章是进港当场自动开的，人到了交货港、牙行门都没进
## 就被判违约。
##   A 直跑 skip_years：同一局面跳两年，带委办的那份与不带的对照份钱、名声逐位相等；委办清空、签发港不封单、
##     札记有「跳年委办作罢」、跳年途中没有「【逾期】」通告；册页代价段那几行写上这单作罢。
##   B 真走开章：第一章章目全达、带一单委办进福州——册页弹出、跳两年，委办作罢不罚，册页「代价」段写明。
##   反向基：不跳年的寻常逾期照旧罚钱、减名声、记「【逾期】」。
## 用法：godot --headless --path . -s res://tools/qa_w54_story_skip_probe.gd（经门锁跑）
## 末行 W54_STORY_SKIP cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _gm: Node
var _cal: Node
var _crew: Node
var _tally: ScriptErrTally
var _reported := false
var _notices: Array = []
var _fleet: Node
var _fleet0: Dictionary = {}


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
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	_crew = root.get_node_or_null("Crew")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _gm == null or _cal == null or _crew == null or _fleet == null:
		_expect(false, "autoload GameState / GameManager / Calendar / Crew / Fleet 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	_gm.monthly_notice.connect(func(t: String): _notices.append(t))
	_fleet0 = _fleet.to_dict()
	_a_skip_direct()
	await _b_chapter_advance()
	_r_plain_overdue()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_STORY_SKIP cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 一张在身的委办：from 港签、dest 港交，due 在 days 日后
func _contract(from: String, dest: String, days: int) -> Dictionary:
	var purse := 900
	return {
		"good_id": "fujian_porcelain", "qty": 10, "remaining": 10, "dest": dest, "from": from,
		"purse": purse, "unit_purse": float(purse) / 10.0, "paid": 0,
		"due_day": _cal.absolute_day() + days, "deadline_days": days, "voyage_days": days - 3,
		"offer_month": _cal.year * 12 + _cal.month,
	}


func _base(y: int, m: int) -> void:
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_cal.from_dict({"year": y, "month": m, "day": 2})
	_fleet.from_dict(_fleet0.duplicate(true))
	_crew.hired = {}
	_crew.unpaid_months = 0
	_gs.money = 5000
	_gs.fame = 10
	for n in _gs.pending_news():
		_gs.mark_news_seen(str(n.get("id", "")))


# ── A 直跑 skip_years ────────────────────────────────────

func _a_skip_direct() -> void:
	print("── A 直跑 skip_years：带委办跳两年")
	seed(54)
	_base(1258, 3)
	var lines0: Array = _gm.skip_years(2)
	var money_ctrl: int = _gs.money
	var fame_ctrl: int = _gs.fame
	seed(54)
	_base(1258, 3)
	_gs.contract = _contract("quanzhou", "fuzhou", 12)
	_notices.clear()
	var lines: Array = _gm.skip_years(2)
	var overdue := []
	for t in _notices:
		if str(t).begins_with("【逾期】"):
			overdue.append(t)
	_expect(_gs.contract.is_empty(), "跳两年后委办清空（%s）" % str(_gs.contract))
	_expect(_gs.money == money_ctrl and _gs.fame == fame_ctrl,
		"带委办跳年不罚：钱、名声与不带委办的对照份逐位相等（钱 %d / 对照 %d，名声 %d / 对照 %d）" % [
			_gs.money, money_ctrl, _gs.fame, fame_ctrl])
	_expect(not _gs.contract_ban.has("quanzhou"), "签发港泉州不封单（contract_ban %s）" % str(_gs.contract_ban))
	_expect(overdue.is_empty(), "跳年途中没有「【逾期】」通告（%s）" % str(overdue))
	_expect("跳年委办作罢" in _gs.ledger_notes, "札记写一句「跳年委办作罢」（%s）" % str(_gs.ledger_notes))
	var said := "\n".join(lines)
	var gname: String = _gm.get_good_name("fujian_porcelain")
	_expect(said.contains(gname) and said.contains(_gm.get_port_name("fuzhou")) and said.contains("作罢")
			and not "\n".join(lines0).contains("作罢"),
		"跳年摘要写这单作罢（带委办：%s／不带：无此句）" % said.replace("\n", "／").substr(0, 160))


# ── B 真走开章 ───────────────────────────────────────────

func _b_chapter_advance() -> void:
	print("── B 真走开章：第一章章目全达、带一单委办进福州")
	_base(1258, 3)
	var req: Dictionary = _gm.chapters_data.get("chapters", [])[0].get("next_requires", {})
	_gs.chapter = 1
	_gs.peak_money = int(req.get("peak_money", 0)) + 200
	var vis: Array = []
	for pid in req.get("must_visit", []):
		vis.append(str(pid))
	for p in _gm.ports_data.get("ports", []):
		var pid := str(p.get("id", ""))
		if vis.size() < int(req.get("visited_count", 0)) and pid != "fuzhou" and not (pid in vis) and str(p.get("unlock", "ch1")) == "ch1":
			vis.append(pid)
	_gs.visited_ports = vis
	_gs.contract = _contract("quanzhou", "fuzhou", 3)
	var fame0: int = _gs.fame
	_gs.last_port = "fuzhou"
	_main.load_scene("fuzhou")
	await process_frame
	var host = _main.get("_chapter_host")
	var sheet := ""
	if host != null and is_instance_valid(host):
		for l in (host as Node).find_children("*", "Label", true, false):
			sheet += str((l as Label).text) + "\n"
	_expect(_gs.chapter == 2 and sheet != "", "第一章章目全达进福州：开第二章、弹册页（第 %d 章）" % _gs.chapter)
	_expect(_gs.contract.is_empty() and _gs.fame == fame0 and not _gs.contract_ban.has("quanzhou") and "跳年委办作罢" in _gs.ledger_notes,
		"开章跳年：委办作罢、名声不减（%d→%d）、签发港不封单、札记「跳年委办作罢」（委办 %s）" % [
			fame0, _gs.fame, str(_gs.contract)])
	var cost_at := sheet.find("代价")
	var void_at := sheet.find("委办，这几年里作罢了")
	_expect(cost_at >= 0 and void_at > cost_at, "册页「代价」段写明这单作罢（%s）" % sheet.substr(maxi(0, cost_at), 200).replace("\n", "／"))
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
		await process_frame


# ── 反向基：不跳年的寻常逾期照旧罚 ─────────────────────────

func _r_plain_overdue() -> void:
	print("── 反向基：不跳年的寻常逾期照旧罚")
	_base(1258, 3)
	_gs.contract = _contract("quanzhou", "fuzhou", 0)
	var money0: int = _gs.money
	var fame0: int = _gs.fame
	_notices.clear()
	_gm.advance_days(1)
	var overdue := false
	for t in _notices:
		if str(t).begins_with("【逾期】"):
			overdue = true
	_expect(_gs.contract.is_empty() and _gs.money < money0 and _gs.fame == fame0 - 1 and overdue
			and not ("跳年委办作罢" in _gs.ledger_notes),
		"寻常逾期：委办作废、扣钱（%d→%d）、名声减 1（%d→%d）、记「【逾期】」（%s）、不记跳年作罢" % [
			money0, _gs.money, fame0, _gs.fame, str(overdue)])
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
