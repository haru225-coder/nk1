extends SceneTree
## lane w27-k1 无门禁 sweep（二）①：HUD 顶匾上行「钱 N　水粮 D 日」在账真变了之后，印上屏的数字是否跟着变。
##   sweep 证据（承 w26-k9 交主控第 1 条）：LedgerPage.refresh_strip 每帧把 GameState.money 与
##   Fleet.supply_days() 拼进 _status_line，可此前没有一个行为探针读 _status_line——日历探针只
##   读船籍簿页（status_label），钱数 / 水粮天数的「账改了 → 屏上真改」无人断言。
##   接线之难按 k9 记的形状解：_main 挂树后 _ready 会 _mount_status_strip()（mount_strip 纯
##   代码 new 节点，不走 preload，headless 可挂），探针读 main._status_line.text 即可。
## 断言四组（每组都是「先印前值 → 动账 → 后印新值」，不是「跑起来没报错」）：
##   C1 钱数：开局顶匾含「钱 <开局值>」；spend_money(20) 扣完重排，须含「钱 <新值>」、整行与旧行不同、旧值不再印（LCD）。
##   C2 水粮天数：开局（泊港 at_sea=false）须印「水粮 20 日」（Fleet 6 水手 / water=food=60 /
##      日耗 3 → 20 日；NonAdvProbe 对 1255 三月初二与正月三十同读到这个数作锚）；泊港再 advance(1)
##      事实留 20（「泊港期间水手上岸、船上水粮不动」是设计，脚本上有据而非 bug）；此后直拨
##      fleet.at_sea = true（与 SeaChart.gd / Main.gd 出海挂点同字段，脚本接口）再 advance(1)
##      → 账上 60-3=57 → supply_days() 19 → 顶匾改印「水粮 19 日」、整行与旧行不同、旧值不再印。
##   C3 跨月面：advance_days 跨月（1/30 → 2/1），当日水粮数仍印在屏上（防「月结 / 画面切换把
##      顶匾静默清空」——advance_days 本月推进仍照常跑，是当日真实穿越）。
##   C4 直接划拨 + 形状不变量：fleet.water=10 / food=10（写 Fleet 全队池字段是脚本接口，
##      qa_voyage_status_probe 同面）后须印「水粮 3 日」；整行须同时含「钱 」「水粮 」「 日」
##      三个骨架格；再 spend_money(10) 整行与旧行不同（LCD 尾哨）。
## 用法：godot --headless --path . -s res://tools/qa_ledger_strip_probe.gd
## 输出末行 LEDGER_STRIP_PROBE cases=N fails=N；fails≥1 → quit(1)。
## 配套但未进断言面的佐证（仓外、不入仓）：NonAdvProbe 于 /tmp/w27/k1-nonadv.log
## 佐证开局泊港账面为「water=60 food=60 per_day=3 supply_days=20 at_sea=false」，且
## 同账面在 1255 三月初二 / 正月三十两个日历下 supply_days 同为 20——用来咬死「C2 变照
## 是『泊港不动是设计』、而非 advance 坏了」。

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var _fails := 0
var cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	fleet = root.get_node_or_null("Fleet")
	cal = root.get_node_or_null("Calendar")
	if gs == null or gm == null or fleet == null or cal == null:
		push_error("autoload missing")
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Main.tscn missing")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入")
		_report()
		return
	# 归位：清空存档态、钉死日历起点，保证「开局值」是 300 钱 / 现行船员的水粮天数
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_main.load_scene("xinghua")
	await _settle(6)
	if _strip_line() == null:
		_expect(false, "顶匾上行 _status_line 未挂上（_mount_status_strip 后仍为空）")
		_report()
		return

	await _c1_money_updates()
	await _c2_supply_days_decrement()
	await _c3_month_boundary_still_prints()
	_c4_shape_and_lcd()

	_report()


func _settle(n := 3) -> void:
	for _i in range(n):
		await process_frame


## 顶匾上行（RichTextLabel .text 即 bbcode 源文，数字是裸的）
func _strip_line() -> RichTextLabel:
	return _main.get("_status_line") as RichTextLabel


func _strip_text() -> String:
	var s := _strip_line()
	return s.text if s != null else ""


## 顶匾随行真重排（refresh_strip 非公用：走 Main 的公用门面，账变后册页重排会顺带刷顶匾）
func _repaint() -> void:
	if _main.has_method("update_status_panel"):
		_main.call("update_status_panel")


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what)


func _expect_money_shows(amount: int, what: String) -> void:
	var line := _strip_text()
	var pat := "钱 %d" % amount
	# 欠账若在场「钱 N　欠 X」里 N 后接全角空格；无欠则 N 后接「　[color」色标——两者都以全角空格收口
	_expect(line.contains(pat + "　"),
		"%s（实读前 80：%s）" % [what, line.substr(0, 80)])


# ── C1 钱数随账变 ──────────────────────────────────────

func _c1_money_updates() -> void:
	print("── C1 顶匾「钱 N」随实扣换值")
	_repaint()
	var m0: int = gs.money
	var before := _strip_text()
	_expect_money_shows(m0, "开局顶匾印「钱 %d」" % m0)

	var took: bool = gs.spend_money(20)
	_repaint()
	var m1: int = gs.money
	var after := _strip_text()
	_expect(took, "spend_money(20) 账上扣得动（开局钱够）")
	_expect(m1 == m0 - 20, "账上钱变 %d → %d" % [m0, m1])
	_expect_money_shows(m1, "扣完顶匾改印「钱 %d」" % m1)
	_expect(after != before, "扣钱后顶匾整行与旧行不同（LCD：账变屏不变判红）")
	_expect(not after.contains("钱 %d　" % m0), "扣完旧值「钱 %d」不再印在顶匾" % m0)


# ── C2 水粮天数随日减 / 泊港水粮不动是设计 ─────────────────

func _c2_supply_days_decrement() -> void:
	print("── C2 顶匾「水粮 D 日」：泊港不动（设计）→ 出海 advance 扣一日")
	_repaint()
	var d0: int = fleet.supply_days()
	var before := _strip_text()
	_expect(d0 > 1 and d0 < 990, "开局水粮天数在可减区间（实读 %d）" % d0)
	_expect(before.contains("水粮 %d 日" % d0), "开局顶匾印「水粮 %d 日」（实读前 80：%s）" % [d0, before.substr(0, 80)])

	# 泊港变照：advance(1) 后水粮天数依法不动——反向钉「不是 bug」这条设计注释
	gm.advance_days(1)
	_repaint()
	var d_dock: int = fleet.supply_days()
	var dock_line := _strip_text()
	_expect(d_dock == d0, "泊港 advance(1) 账上水粮天数仍 %d（泊港水手上岸，船上水粮不动是设计）" % d_dock)
	_expect(dock_line.contains("水粮 %d 日" % d0), "泊港当天顶匾仍印「水粮 %d 日」（实读前 80：%s）" % [d0, dock_line.substr(0, 80)])

	# 直拨出海闸门（脚本接口：SeaChart.gd:1147/1178、Main.gd:3604 三个在线挂点同字段），再 advance(1) 扣一日
	var water0: int = fleet.water
	fleet.at_sea = true
	gm.advance_days(1)
	_repaint()
	var d1: int = fleet.supply_days()
	var after := _strip_text()
	_expect(fleet.water == water0 - fleet.daily_supply_use(),
		"出海 advance(1) 水账真扣 %d → %d" % [water0, fleet.water])
	_expect(d1 == d0 - 1, "账上水粮天数 %d → %d" % [d0, d1])
	_expect(after.contains("水粮 %d 日" % d1),
		"出海 advance(1) 后顶匾改印「水粮 %d 日」（实读前 80：%s）" % [d1, after.substr(0, 80)])
	_expect(after != before, "出海扣水粮后整行与旧行不同（LCD）")
	_expect(not after.contains("水粮 %d 日" % d0), "旧值「水粮 %d 日」不再印在顶匾" % d0)
	fleet.at_sea = false  # 复位：不留状态给下一 case


# ── C3 跨月后水粮仍印（当日真实穿越；泊港剧本因水粮不动而搬到同一天）────────

func _c3_month_boundary_still_prints() -> void:
	print("── C3 跨月当天顶匾仍印水粮数（防月结 / 切换静默清空）")
	fleet.at_sea = true  # 保证跨月那天水粮真走：泊港水粮不动是设计，用它反证不了「静默清空」
	cal.from_dict({"year": 1255, "month": 1, "day": 30})
	var d0: int = fleet.supply_days()
	gm.advance_days(1)  # 正月三十 + 1 → 二月初一（跨月，水粮也扣——等效在线出海跨月）
	_repaint()
	var d1: int = fleet.supply_days()
	var line := _strip_text()
	fleet.at_sea = false
	_expect(str(cal.get_date_string()).contains("二月初一"),
		"历法实读：正月三十 +1 = 二月初一（实读：%s）" % str(cal.get_date_string()))
	_expect(d1 == d0 - 1, "跨月那天水粮真走：%d → %d" % [d0, d1])
	_expect(line.contains("水粮 %d 日" % d1),
		"跨月当天顶匾印新值「水粮 %d 日」（实读前 80：%s）" % [d1, line.substr(0, 80)])
	_expect(line.contains("钱 "), "跨月当天顶匾仍含「钱 」格（实读前 80：%s）" % line.substr(0, 80))


# ── C4 直接划拨水账 + 形状不变量 + LCD 尾哨 ─────────────

func _c4_shape_and_lcd() -> void:
	print("── C4 直划水粮池 + 整行骨架 + 再扣钱的 LCD 尾哨")
	# 全网公共账口：qa_voyage_status_probe 同面地直写 Fleet 水粮池
	fleet.water = 10
	fleet.food = 10
	_repaint()
	var line := _strip_text()
	_expect(line.contains("水粮 %d 日" % fleet.supply_days()),
		"water=food=10 后顶匾印「水粮 %d 日」" % fleet.supply_days())
	_expect(line.contains("钱 "), "顶匾含「钱 」格")
	_expect(line.contains("水粮 "), "顶匾含「水粮 」格")
	_expect(line.contains(" 日"), "水粮天数以「 日」收尾")

	var m0: int = gs.money
	var before := _strip_text()
	gs.spend_money(10)
	_repaint()
	var after := _strip_text()
	_expect(after != before,
		"再扣 10 钱后整行与旧行不同（LCD：同一坏账口连着两次，哪次不变都判红；旧行前 40：%s）" % before.substr(0, 40))
	_expect_money_shows(m0 - 10, "再扣 10 钱：顶匾印「钱 %d」" % (m0 - 10))


func _report() -> void:
	print("LEDGER_STRIP_PROBE cases=%d fails=%d" % [cases, _fails])
	quit(1 if _fails > 0 else 0)
