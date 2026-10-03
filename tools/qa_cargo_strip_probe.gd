extends SceneTree
## lane w29-k2 无门禁 sweep（w27-k1 交主控 ①）：船籍簿页「船舱」段（LedgerPage.update_panel 的 cargo_str）
##   上屏原文断言——货舱容量与货品条目逐字钉（品名 / 「×数量」），不是查见「船舱」子串。
##   缺口（w27-k1 Verify 交主控 ①原文）：顶匾 line1 只写「钱 N欠X　水粮 D 日」与日期 / 季风 / 章名，
##   无货舱容量 / 货舱条目本身；真正单货舱上屏断言位在船舱段、`LedgerPage.update_panel` `cargo_str`，
##   位在船籍簿页不是顶匾——改前 grep tools/ 零探针提 cargo_str。
## 接线：照 w27-k1 同工——_main 挂树后 _ready 会挂 strip；船籍簿页 status_label 是
##   Main.gd:7 的 @onready，挂 Main.tscn 即有；主线回购器 Main.update_status_panel（Main.gd:740）
##   即 LedgerPage.update_panel(self)，账变后 call 一次即整串重排。
## 锚点（开局面，全部来自现行数据帧）：gs.from_dict({}) 不清船（Fleet 是另一个 autoload），
##   开局船保持 sampan「小艍船」capacity 200 料；water=60 / food=60 水粮占舱 0.25/单位 →
##   已用 200×0.25=30 → 「舱位　30 / 200 料」；空舱时船舱段印「空\n」。
## 断言六组（status_label.text 是 bbcode 源文，条目里的数字与乘号是裸的——品名旁无色标，
##   乘法用半角 ×，空格是半角一个、数量紧跟「×」）：
##   C1 空舱形态：开局船舱段含「[b]船舱[/b][/color]\n空\n」，且「舱位　30 / 200 料」「足 20 日」同屏。
##   C2 进货上屏：add_cargo 茶叶 10 / 苏木 12（账上验真）→ 逐字含「茶叶 ×10\n」「苏木 ×12\n」；
##      「舱位　47 / 200 料」（10×0.7+12×1.4=16.8 料，30→46.8 截整 47）；「足 20 日」不随货变；空字不再印。
##   C3 再加即变：茶叶 +5 → 「茶叶 ×15\n」上屏、旧值「茶叶 ×10\n」不再印、「苏木 ×12\n」稳住。
##   C4 出货清空：remove_cargo 茶叶 15 / 苏木 12 → 两行条目都不再印、舱段回到「空\n」、「舱位　30 / 200 料」。
##   C5 反向哨：先刷上「茶叶 ×5」当前页，账上再 +5 但**不**重排，旧页仍印「茶叶 ×5\n」、
##      不得自行变出「茶叶 ×10\n」——严防探针读缓存页认不出「账变屏未刷」。
##   C6 形状不变量：重排后整页须过空仓变化（LCD）、仍含「[b]船舱[/b]」格，且「船舱」不得漏进顶匾 line1。
## 用法：godot --headless --path . -s res://tools/qa_cargo_strip_probe.gd
## 输出末行 CARGO_STRIP cases=N fails=N；fails≥1 → quit(1)。

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
	# 归位：清空玩家态、归正日历，保证开局面是水粮 60/60 的 sampan 空舱
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_main.load_scene("xinghua")
	await _settle(6)
	if fleet.ships.size() != 1:
		_expect(false, "开局船数应为 1（实读 %d：摆场前提不成立，后面对空断言全是空转）" % fleet.ships.size())
		_report()
		return
	if _page_label() == null:
		_expect(false, "船籍簿页 status_label 未挂上（Main.tscn @onready 应已有）")
		_report()
		return

	await _c1_empty_hold()
	await _c2_stock_two_goods()
	_c3_top_up_changes_line()
	_c4_sell_off_returns_empty()
	_c5_stale_page_sentinel()
	_c6_shape_invariants()

	_report()


func _settle(n := 3) -> void:
	for _i in range(n):
		await process_frame


## 船籍簿正文（RichTextLabel .text 即 bbcode 源文；条目行品名旁无色标，数字与乘号裸排）
func _page_label() -> RichTextLabel:
	return _main.get("status_label") as RichTextLabel


func _page() -> String:
	var s := _page_label()
	return s.text if s != null else ""


func _strip_text() -> String:
	var s: RichTextLabel = _main.get("_status_line") as RichTextLabel
	return s.text if s != null else ""


## 整册重排：Main 的公用门面即 LedgerPage.update_panel(self)，同一口会把顶匾也顺带刷掉
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


## 从「船舱」段头往后截展示窗（报错用，免得整页糊进日志）
func _hold_snip(page: String) -> String:
	var i := page.find("[b]船舱[/b]")
	if i < 0:
		return page.substr(0, 60)
	return page.substr(i, 48)


# ── C1 空舱形态：船舱段「空」+ 容量随帧定 ──────────────────

func _c1_empty_hold() -> void:
	print("── C1 开局空舱：船舱段印「空」、舱位水粮随现行帧")
	_repaint()
	var supply_d: int = fleet.supply_days()
	var cap_used := int(fleet.used_capacity())
	var cap_total := int(fleet.total_capacity())
	var page := _page()
	_expect(fleet.cargo.is_empty(), "开局全队货舱为空（Fleet.cargo 聚合实读）")
	_expect(page.contains("[b]船舱[/b][/color]\n空\n"),
		"空舱形态：船舱段印「[b]船舱[/b][/color]\\n空\\n」（实读船舱段：%s）" % _hold_snip(page))
	_expect(page.contains("舱位　%d / %d 料" % [cap_used, cap_total]),
		"容量上屏：含「舱位　%d / %d 料」（sampan 200 料 − 水粮 30 料；实读：%s）" % [cap_used, cap_total, _hold_snip(page)])
	_expect(page.contains("足 %d 日" % supply_d),
		"水粮天数随行印「足 %d 日」（水粮 60/60、水手 6 → 20 日）" % supply_d)


# ── C2 装两宗货：品名 / 数量 / 单位逐字上屏，容量跟着变 ──────

func _c2_stock_two_goods() -> void:
	print("── C2 进货：茶叶 ×10 / 苏木 ×12 逐字上屏、舱位 30 → 47 料")
	var ok1: bool = fleet.add_cargo("tea", 10, 25.0)
	var ok2: bool = fleet.add_cargo("sappanwood", 12, 30.0)
	_expect(ok1 and ok2, "账上装得进：add_cargo 茶叶 10 / 苏木 12 均成真（空舱 170 料够 16.8 料）")
	_repaint()
	var cap_used := int(fleet.used_capacity())  # 30 + 10×0.7 + 12×1.4 = 46.8 → 截整 46 或 47 以实读为准
	var supply_d: int = fleet.supply_days()
	var page := _page()
	_expect(page.contains("茶叶 ×10\n"),
		"茶叶条目逐字上屏「茶叶 ×10\\n」（品名 × 数量，实读船舱段：%s）" % _hold_snip(page))
	_expect(page.contains("苏木 ×12\n"),
		"苏木条目逐字上屏「苏木 ×12\\n」（实读船舱段：%s）" % _hold_snip(page))
	_expect(page.contains("舱位　%d / 200 料" % cap_used),
		"容量随货变：含「舱位　%d / 200 料」（30 + 16.8 料截整；实读：%s）" % [cap_used, _hold_snip(page)])
	_expect(page.contains("足 %d 日" % supply_d),
		"装货不动水粮账：仍印「足 %d 日」" % supply_d)
	_expect(not page.contains("[b]船舱[/b][/color]\n空\n"),
		"已有货：船舱段「空」字不再印")


# ── C3 同一宗再加：数量改印、另一宗稳住 ──────────────────

func _c3_top_up_changes_line() -> void:
	print("── C3 茶叶再加 5：「茶叶 ×15」上屏、旧值与「茶叶 ×10」不再印、苏木稳住")
	var ok: bool = fleet.add_cargo("tea", 5, 25.0)
	_expect(ok, "账上加得进：茶叶再 +5 成真")
	_repaint()
	var page := _page()
	_expect(page.contains("茶叶 ×15\n"),
		"加货后逐字改印「茶叶 ×15\\n」（实读船舱段：%s）" % _hold_snip(page))
	_expect(not page.contains("茶叶 ×10\n"),
		"旧值「茶叶 ×10\\n」不再印在页上（LCD：串变旧字必退）")
	_expect(page.contains("苏木 ×12\n"),
		"另一宗不因加货漂移：仍印「苏木 ×12\\n」")


# ── C4 出货清空：条目退屏、舱段归「空」、容量回 30 ──────────

func _c4_sell_off_returns_empty() -> void:
	print("── C4 出货：茶叶 15 / 苏木 12 全出 → 条目退屏、船舱段归「空」、舱位回 30 料")
	var r1: bool = fleet.remove_cargo("tea", 15)
	var r2: bool = fleet.remove_cargo("sappanwood", 12)
	_expect(r1 and r2, "账上出得净：remove_cargo 茶叶 15 / 苏木 12 均成真")
	_expect(fleet.cargo.is_empty(), "全队货舱聚合实读归空")
	_repaint()
	var page := _page()
	_expect(not page.contains("茶叶 ×"), "出货后「茶叶 ×」条目不再印")
	_expect(not page.contains("苏木 ×"), "出货后「苏木 ×」条目不再印")
	_expect(page.contains("[b]船舱[/b][/color]\n空\n"),
		"舱段归空形态：再印「[b]船舱[/b][/color]\\n空\\n」（实读船舱段：%s）" % _hold_snip(page))
	_expect(page.contains("舱位　%d / 200 料" % int(fleet.used_capacity())),
		"容量回水粮底价：含「舱位　%d / 200 料」（应回 30）" % int(fleet.used_capacity()))


# ── C5 反向哨：账变了不重排，旧页必须还停在旧文 ──────────

func _c5_stale_page_sentinel() -> void:
	print("── C5 反向哨：茶叶 5+5 到账不重排，页上不得自己变成「茶叶 ×10」")
	fleet.add_cargo("tea", 5, 25.0)
	_repaint()  # 先正经刷上「茶叶 ×5」的当前页
	var page_before := _page()
	_expect(page_before.contains("茶叶 ×5\n"), "摆场：重排后页上印「茶叶 ×5\\n」")
	fleet.add_cargo("tea", 5, 25.0)  # 账上 5+5=10，但故意不重排
	var page_stale := _page()
	_expect(not page_stale.contains("茶叶 ×10\n"),
		"账变未刷：页上不得自行变出「茶叶 ×10\\n」（读出的是页不是账——此格红说明断言在读缓存副本）")
	_expect(page_stale.contains("茶叶 ×5\n"),
		"账变未刷：页上仍停在旧文「茶叶 ×5\\n」")
	_repaint()  # 复位到写真页，免得 C6 的起点是陈旧文
	var page_after := _page()
	_expect(page_after.contains("茶叶 ×10\n") and page_after.contains("苏木 ×12\n") == false,
		"复位重排：页上改印「茶叶 ×10\\n」（苏木已出净，不得回魂；实读船舱段：%s）" % _hold_snip(page_after))


# ── C6 形状不变量：整页过变（LCD）、「船舱」格在页不在匾 ──────

func _c6_shape_invariants() -> void:
	print("── C6 骨架：清空后整页变、船舱格在船籍簿页而不上顶匾")
	var page_full := _page()
	fleet.remove_cargo("tea", 10)
	_repaint()
	var page_empty := _page()
	_expect(page_empty != page_full,
		"LCD 尾哨：清掉最后一宗货后整页与含货页不同（防整页冻住时上面逐字断言全空转）")
	_expect(page_empty.contains("[b]船舱[/b]"),
		"船舱段骨架格「[b]船舱[/b]」恒在（空 / 满同格）")
	_expect(not _strip_text().contains("船舱"),
		"货舱条目不上顶匾：顶匾 line1 不得含「船舱」（w27-k1 划界——顶匾只钱 / 水粮 / 日历，断言位在册页）")


func _report() -> void:
	print("CARGO_STRIP cases=%d fails=%d" % [cases, _fails])
	quit(1 if _fails > 0 else 0)
