extends SceneTree
## lane w30-k2 无门禁 sweep：HUD 顶匾上行「欠 %d」四字逐字断言（摆 gs.debt = 835 / 100 / 10000 三档）。
##   来源：w29-k4 Verify 交主控 #3 + w27-k1 交主控④——qa_ledger_strip_probe 只钉了「钱 N」数字与
##   「欠账若在场『钱 N　欠 X』里 N 后接全角空格」的注释式钉死（tools/qa_ledger_strip_probe.gd:116-117），
##   没有把 `gs.debt = 835` 后 line1 里「欠 835」四字逐字钉。经济数据源
##   scripts/ui/LedgerPage.gd:165-168：`debt := ""; if GameState.debt > 0: debt = "　[color=#…]欠 %d[/color]" % GameState.debt`。
##   先查后做证据（2026-10-03）：grep "欠 835\|欠 %d" tools/ scripts/ 除 LedgerPage.gd:167 数据源外零断言；
##   qa_iz_skip_notice_probe.gd:53 虽摆 gs.debt = 835 但只读通告序列，不读顶匾。
## 断言三组：
##   D1-D3 欠债档：gs.debt = 835 / 100 / 10000 各摆一场，顶匾上行 line1 须含「欠 835」「欠 100」
##      「欠 10000」逐字（bbcode 源文里 [color=#…]欠 N[/color]，数字裸排）。
##   D0 反向断言：gs.debt = 0 后顶匾上行不印「欠 」（含「欠」字但无「欠 」即判过——LedgerPage.gd:167
##      的 debt 变量在 debt<=0 时为空串，顶匾不该再有欠字样格）。
## 用法：godot --headless --path . -s res://tools/qa_debt_strip_probe.gd
## 输出末行 DEBT_STRIP cases=N fails=N；fails≥1 → quit(1)。
## w53-11：`cases` 计数里含 `SCRIPT ERROR 自证 / 真路判 0` 两帐（story :3156 同款）——
## `cases` 比场面断言多 2，与前历位一一对应（DEBT_STRIP 现网 = 旧 4 + 2 = 6）。
## 判闸挂收编件 tools/script_err_tally.gd（收编 story :3131 _ScriptErrTally 的唯一入账规则）。

## w53-11：注册表判词「本进程 SCRIPT ERROR 即红」此前空转（探针没装 Logger，headless -s
## 运行期脚本错跳成零部断言 fails=0、退出码守 0）——收编 story :3131 同款判闸
## （tools/script_err_tally.gd，ERROR_TYPE_SCRIPT 唯一入账）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var _fails := 0
var cases := 0
var _tally: ScriptErrTally


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	var gm: Node = root.get_node_or_null("GameManager")
	var cal: Node = root.get_node_or_null("Calendar")
	if gs == null or gm == null or cal == null:
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
	# 归位：清空存档态、钉死日历起点，与 qa_ledger_strip_probe 同形状
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_main.load_scene("xinghua")
	await _settle(6)
	if _strip_line() == null:
		_expect(false, "顶匾上行 _status_line 未挂上（_mount_status_strip 后仍为空）")
		_report()
		return

	_d0_no_debt_omits()
	_d1_debt_835()
	_d2_debt_100()
	_d3_debt_10000()

	_report()


func _settle(n := 3) -> void:
	for _i in range(n):
		await process_frame


func _strip_line() -> RichTextLabel:
	return _main.get("_status_line") as RichTextLabel


func _strip_text() -> String:
	var s := _strip_line()
	return s.text if s != null else ""


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


func _expect_debt_shows(amount: int, what: String) -> void:
	var line := _strip_text()
	var pat := "欠 %d" % amount
	_expect(line.contains(pat),
		"%s（实读前 110：%s）" % [what, line.substr(0, 110)])


# ── D0 反向：debt=0 时顶匾不印「欠 」格 ──────────────────

func _d0_no_debt_omits() -> void:
	print("── D0 开局 debt=0 顶匾上行不印「欠 」字样")
	_repaint()
	var line := _strip_text()
	_expect(not line.contains("欠 "),
		"debt=0：顶匾上行无「欠 」格（实读前 110：%s）" % line.substr(0, 110))


# ── D1 欠债 835 ─────────────────────────────────────────

func _d1_debt_835() -> void:
	print("── D1 摆 gs.debt = 835，顶匾上行印「欠 835」")
	gs.debt = 835
	_repaint()
	_expect_debt_shows(835, "debt=835：顶匾上行含「欠 835」")


# ── D2 欠债 100 ──────────────────────────────────────────

func _d2_debt_100() -> void:
	print("── D2 摆 gs.debt = 100，顶匾上行印「欠 100」")
	gs.debt = 100
	_repaint()
	_expect_debt_shows(100, "debt=100：顶匾上行含「欠 100」")


# ── D3 欠债 10000 ─────────────────────────────────────────

func _d3_debt_10000() -> void:
	print("── D3 摆 gs.debt = 10000，顶匾上行印「欠 10000」")
	gs.debt = 10000
	_repaint()
	_expect_debt_shows(10000, "debt=10000：顶匾上行含「欠 10000」")
	gs.debt = 0  # 复位：不留状态


func _report() -> void:
	## w53-11：先自证计数器只认 SCRIPT 类（story :3156 同款），再判真路 0 条并入末行 fails
	## （无论此前场面断言全过还是想带红走，本判的路都过一遍——先前调用点的提前 _report()
	## 也会漏到 SCRIPT ERROR，一并兜住）。
	var probe := ScriptErrTally.new()
	probe._log_error("f", "res://x.gd", 1, "", "自证 SCRIPT", false, Logger.ERROR_TYPE_SCRIPT, [])
	probe._log_error("f", "res://x.gd", 2, "", "自证 ERROR", false, Logger.ERROR_TYPE_ERROR, [])
	probe._log_error("f", "res://x.gd", 3, "", "自证 WARNING", false, Logger.ERROR_TYPE_WARNING, [])
	_expect(probe.lines.size() == 1,
		"SCRIPT ERROR 计数器自证：只数脚本类（喂 SCRIPT / ERROR / WARNING 各一，数到 %d）" % probe.lines.size())
	OS.remove_logger(_tally)
	var errs: Array = _tally.lines
	_expect(errs.is_empty(),
		"运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
		"" if errs.is_empty() else "，首条：" + str(errs[0])])
	print("DEBT_STRIP cases=%d fails=%d" % [cases, _fails])
	quit(1 if _fails > 0 else 0)
