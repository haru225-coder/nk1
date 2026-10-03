extends SceneTree
## Lane w23-a5 / P5（EA6-1 机械前置）：「港月 × 战况 × 杂事 × 职衔 → 实扣塞钱」探针骨架。
## 被测实现 scripts/GameState.gd:786 的 customs_inspection() 无引塞钱分支：
##   var bribe := 50 + contraband * 10                        ——今日唯一实扣按钮
##   遣返线  float(pu_attention) * war_mul > 50.0               ——本探针全程压住，见下「边界」
## A 案（拍板清单 §八之二 EA6-1 候选值内，未选定、不改实现）：
##   A  50 + 10×违禁（＝现行源码）
##   B0.5  max(50, round(0.5×验引)) + 10×违禁
##   B1.0  max(50, round(1.0×验引)) + 10×违禁
##   C  round(50×缉私倍率) + 40×违禁
## 断言按 A 案逐行注释（# TODO(EA6-1 拍板后开)），只打印实测对照表；开法见文末「自检」注释与
## docs/塞钱探针骨架_2026-10-03.md §四开关步骤。探针有自检：
##   NK1_BRIBE_EXPECT={A|B:0.5|B:1.0|C} godot … 对该案期望逐行断言（拍板后把断言定植进源码即收编）；
##   NK1_BRIBE_PROVE=1 只跑一组四格小循环 + 三条专项（反向自证用，配 game hack + NK1_BRIBE_EXPECT）。
## 硬约束（今日源码形，改坏任何一条本探针当场红）：
##   过关必实扣  扣后钱 = 扣前 − bribe  关注 += 20 + 2×违禁  result.passed == true
## 边界（双跑一组四角格，两组差恰好 1 钱）：
##   遣返取严格大于：关注×缉私倍率 > 50 遣返，恰好 == 50 仍走塞钱分支。
## 用法：godot --headless --path . -s res://tools/qa_bribe_probe.gd -- --contract   （契约收尾走 shot_gate）
## 输出：实测表（每行四维 + 实扣 + 出处行号）→ 专项块 → 注掉 N 条 → 末行 BRIBE_SKEL_PROBE … rc=0（无开着断言）。

const ShotGate := preload("res://tools/shot_gate.gd")

const TAG := "BRIBE_SKEL"
## 出处行号打在表头，改码挪行时人工对照（探针按行为对账，不钉行号）。
const SRC_INSP := "scripts/GameState.gd:746"
const SRC_BRIBE := "scripts/GameState.gd:786"
## 四维取值键的代码出处（brief 必做 1 的索引）：
##   港月×战况 Economy.war_status() ports.json war 表     → scripts/core/Economy.gd:37-44 / :280-281
##   杂事     Crew.trade_cost_factor() 1 − 0.12×杂事级    → scripts/core/Crew.gd:128-129
##   职衔     GameState.title_duty_factor() titles.json   → scripts/GameState.gd:679-680
## 表头角度：港(港月) 战况(倍率) 杂事 职衔 违禁 塞钱 验引 实扣=A(B0.5|B1.0|C) A−验引(逃引盈亏口径)
## 案公式照抄拍板清单 §八之四 P5 行贴交的 docs/无引贿赂定额对照表.md:76/:82/:103。
const CASES := {
	"A": "50 + 10×违禁（＝现行源码 scripts/GameState.gd:786 一行）",
	"B:0.5": "max(50, round(0.5×验引)) + 10×违禁",
	"B:1.0": "max(50, round(1.0×验引)) + 10×违禁",
	"C": "round(战争缉私倍率×50) + 40×违禁",
}
const ZASHI_LEVELS := [0, 1, 3]
const FAMES := [0, 80]  # titles.json：0=籍外散商(1.0) / 80=市舶都保(0.76)，最低与最顶两档
const CONTRABAND_UNITS := [0, 2]
## 港月取自 ports.json war 表首达月（探针跑前逐格核对，变表当场红）：
##   泉州 1276-05 对峙(1.3) / 1276-12 降元(2.0) / 1270-01 平时(1.0)；温州 1276-05 降元(2.0)。
const SPOTS: Array[Dictionary] = [
	{"port": "quanzhou", "y": 1270, "m": 1, "war": "loyal", "mul": 1.0},
	{"port": "quanzhou", "y": 1276, "m": 5, "war": "contested", "mul": 1.3},
	{"port": "quanzhou", "y": 1276, "m": 12, "war": "fallen", "mul": 2.0},
	{"port": "wenzhou", "y": 1276, "m": 5, "war": "fallen", "mul": 2.0},
]

var eco: Node
var crew: Node
var gs: Node
var cal: Node
var fleet: Node
var fails: Array = []

var _cases := 0
var _skips := 0
var _saved: Dictionary = {}
var _expect_env := ""  # NK1_BRIBE_EXPECT：环境注入期望案（自检通道）；空串 = 今日骨架常态（全注掉）


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	ShotGate.frame_pressure(self)
	eco = root.get_node_or_null("Economy")
	crew = root.get_node_or_null("Crew")
	gs = root.get_node_or_null("GameState")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	if eco == null or crew == null or gs == null or cal == null or fleet == null:
		_fail("autoload 缺席（Economy/Crew/GameState/Calendar/Fleet 有 null）")
		quit(ShotGate.finish_contract(TAG, fails, "autoload"))
		return
	eco.initialize()
	_expect_env = OS.get_environment("NK1_BRIBE_EXPECT").strip_edges()
	if _expect_env != "" and not CASES.has(_expect_env):
		_fail("NK1_BRIBE_EXPECT=%s 不是已立案（可选：%s）" % [_expect_env, ", ".join(CASES.keys())])

	_save_state()
	print("[塞钱探针骨架] lane w23-a5 · 被测 %s customs_inspection()，塞钱行 %s" % [SRC_INSP, SRC_BRIBE])
	print("[口径] 港月×战况×杂事×职衔四维取自：Economy.war_status / Crew.trade_cost_factor / GameState.title_duty_factor")
	print("[格局] 全程无引、违禁货 0 或 2 件（押舱必中）、关注羊角 < 50÷缉私倍率 平安角（不触遣返）")
	_grid()
	_focused()
	_boundary()

	_restore_state()
	print("[骨架] 注掉 %d 条断言（# TODO(EA6-1 拍板后开)：拍 B/C 后照 §四开关步骤开，或临时用 NK1_BRIBE_EXPECT 自验收）" % _skips)
	var tail := "%s_PROBE 案=%d 跑=%d 注=%d 红=%d" % [TAG, CASES.size(), _cases, _skips, fails.size()]
	print(tail)
	quit(ShotGate.finish_contract(TAG, fails))


func _grid() -> void:
	var prove := OS.get_environment("NK1_BRIBE_PROVE") == "1"
	print("[实测表] 港:月 战况(缉私倍率) | 杂事 职衔 违禁 | 塞钱 验引 实扣 | A B0.5 B1.0 C | A−验引")
	for s in SPOTS:
		cal.year = s["y"]
		cal.month = s["m"]
		cal.day = 1
		var war: String = eco.war_status(s["port"])
		if war != s["war"]:
			_fail("%s %d-%02d 战况 %s，预期 %s（ports.json war 表变了？）" % [s["port"], s["y"], s["m"], war, s["war"]])
		var mul: float = eco.inspection_factor(s["port"])
		if absf(mul - s["mul"]) > 0.001:
			_fail("%s %d-%02d 缉私倍率 %.2f，预期 %.2f（Economy.WAR_INSPECTION 变了？）" % [s["port"], s["y"], s["m"], mul, s["mul"]])
		gs.pu_attention = mini(10, int(50.0 / mul) - 1)  # 平安角：关注×倍率 恒 < 50，塞钱分支必达
		gs.last_port = s["port"]
		for z in (ZASHI_LEVELS.slice(0, 2) if prove else ZASHI_LEVELS):
			for fame in FAMES:
				for units in (CONTRABAND_UNITS.slice(0, 1) if prove else CONTRABAND_UNITS):
					_row(s, z, fame, units, mul)


## 一格格跑：走真结算路径，对实测额与各案候选值并行对账。
func _row(s: Dictionary, z: int, fame: int, units: int, mul: float) -> void:
	gs.fame = fame
	crew.hired = {} if z == 0 else {"zashi": {"id": "probe_zashi", "role": "zashi", "level": z, "wage": 0}}
	var duty: int = gs.customs_duty()
	_setup_cargo(units)
	# 每次过手关注 +20+2×违禁（sentinel 分支外），逐格重置回平安角，免得格子越走越兴师问罪。
	gs.pu_attention = mini(10, int(50.0 / mul) - 1)
	var m0: int = gs.money
	var a0: int = gs.pu_attention
	var res: Dictionary = gs.customs_inspection()
	_cases += 1
	if not bool(res.get("passed", false)):
		_fail("%s %s 塞钱案未过关（关注=%d×%.1f=%.1f 应 <50）：%s" % [
			s["port"], s["war"], a0, mul, a0 * mul, str(res.get("msg", ""))])
		return
	var paid: int = m0 - gs.money
	var predicts := _predict_all(duty, units, mul)
	# TODO(EA6-1 拍板后开) 断言 1（每注掉 1 条 _skips += 1 计教）：
	#   拍定案 PICKED 后，下两条去注释、填案号，让逐行实扣钉在案值上——今日按下只打印。
	# _expect(paid == _predict_for(PICKED, duty, units, mul),
	#     "塞钱 %d 不合拍定案 %s（案值 %d）" % [paid, PICKED, _predict_for(PICKED, duty, units, mul)])
	_skips += 1
	if _expect_env != "":
		_expect(paid == _predict_for(_expect_env, duty, units, mul),
			"注入案 %s 实测 %d ≠ 案值 %d（%s %s 杂事%d 职衔档 fame=%d 违禁%d）" % [
				_expect_env, paid, _predict_for(_expect_env, duty, units, mul),
				s["port"], s["war"], z, fame, units])
	var c: int = predicts["C"]
	var bc: String = "A" if paid == predicts["A"] else "-"
	bc += ("|" + "0.5") if paid == predicts["B:0.5"] else "|-"
	bc += ("|" + "1.0") if paid == predicts["B:1.0"] else "|-"
	bc += ("|" + "C") if paid == c else "|-"
	var title: String = gs.title_name()
	print("  %s:%04d-%02d %s(×%.1f) | 杂事%d %s 违禁%d | 塞钱=%d 验引=%d 实扣=%s | A=%d B0.5=%d B1.0=%d C=%d | %+d" % [
		s["port"], s["y"], s["m"], s["war"], mul, z, title, units,
		50 + units * 10, duty, bc, predicts["A"], predicts["B:0.5"], predicts["B:1.0"], c,
		predicts["A"] - duty])


## 专项三条：钱差恒等于塞钱额 / 关注 20+2×违禁 / 文案「塞了 N 钱」数字与实扣一致。
func _focused() -> void:
	print("[专项] 固定格（泉州 1276-05 对峙，违禁 2 件，杂事 0 职衔散商）")
	var s: Dictionary = SPOTS[1]
	cal.year = s["y"]
	cal.month = s["m"]
	cal.day = 1
	gs.last_port = s["port"]
	gs.fame = 0
	gs.pu_attention = 10
	crew.hired = {}
	_setup_cargo(2)
	var bribe := 50 + 2 * 10
	var a0: int = gs.pu_attention
	var m0: int = gs.money
	var res: Dictionary = gs.customs_inspection()
	var m1: int = gs.money
	var a1: int = gs.pu_attention
	_cases += 1
	_expect(m0 - m1 == bribe, "钱差 %d ≠ 塞钱额 %d（实扣与文案须同源）" % [m0 - m1, bribe])
	_expect(a1 - a0 == 24, "关注 +%d，预期 20 + 2×2 = 24" % (a1 - a0))
	_expect(str(res.get("msg", "")).contains("塞了 %d 钱" % bribe),
		"过关文案未写「塞了 %d 钱」：%s" % [bribe, str(res.get("msg", ""))])


## 边界：遣返线是严格大于——50 整仍塞钱，51 起遣返；两组差恰好 1 钱。
func _boundary() -> void:
	var s: Dictionary = SPOTS[0]  # 泉州平时，缉私倍率 1.0，遣返线 = 关注 50
	cal.year = s["y"]
	cal.month = s["m"]
	cal.day = 1
	gs.last_port = s["port"]
	gs.fame = 0
	crew.hired = {}
	_setup_cargo(0)
	var m0: int = gs.money
	gs.pu_attention = 50
	_cases += 1
	var res50: Dictionary = gs.customs_inspection()
	_expect(bool(res50.get("passed", false)), "关注 50×1.0 恰在线，应仍走塞钱分支（严格大于才遣返）")
	# 50 案走的是塞钱分支，钱差须恰为塞钱额 50；51 案扣的是罚锾（另一支 qa_fine_text_probe 的疆域）。
	_expect(m0 - gs.money == 50, "关注 50 案钱差 %d，预期塞钱额 50" % (m0 - gs.money))
	gs.pu_attention = 51
	_setup_cargo(0)
	_cases += 1
	var res51: Dictionary = gs.customs_inspection()
	_expect(not bool(res51.get("passed", false)) and bool(res51.get("confiscated", false)),
		"关注 51×1.0 越过线，应遣返没收（遣返线 > 50 严格大于）")


func _predict_all(duty: int, units: int, mul: float) -> Dictionary:
	return {
		"A": 50 + 10 * units,
		"B:0.5": maxi(50, int(round(0.5 * duty))) + 10 * units,
		"B:1.0": maxi(50, int(round(1.0 * duty))) + 10 * units,
		"C": int(round(50.0 * mul)) + 40 * units,
	}


func _predict_for(case_id: String, duty: int, units: int, mul: float) -> int:
	var all := _predict_all(duty, units, mul)
	return int(all.get(case_id, -1))


## 舱货布置：先清再装——合法货押底（茶 5 件）让验引非地板，违禁 0/2 件用铁器（打破 70/件，不打宋钱档）。
func _setup_cargo(units: int) -> void:
	fleet.ships = [{"cargo": {"tea": {"qty": 5, "avg_cost": 0.0}}}]
	if units > 0:
		fleet.ships[0]["cargo"]["ironware"] = {"qty": units, "avg_cost": 0.0}


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	fails.append(msg)
	print("  ✗ " + msg)


func _save_state() -> void:
	_saved = {
		"money": gs.money, "fame": gs.fame, "attention": gs.pu_attention,
		"permit": gs.has_customs_permit, "last_port": gs.last_port,
		"flags": gs.flags.duplicate(true), "hired": crew.hired.duplicate(true),
		"ships": fleet.ships.duplicate(true),
		"y": cal.year, "m": cal.month, "d": cal.day,
	}
	gs.has_customs_permit = false  # 全篇无引格局
	gs.money = 100000


func _restore_state() -> void:
	gs.money = _saved["money"]
	gs.fame = _saved["fame"]
	gs.pu_attention = _saved["attention"]
	gs.has_customs_permit = _saved["permit"]
	gs.last_port = _saved["last_port"]
	gs.flags = _saved["flags"]
	crew.hired = _saved["hired"]
	fleet.ships = _saved["ships"]
	cal.year = _saved["y"]
	cal.month = _saved["m"]
	cal.day = _saved["d"]

## 开关步骤（收编用，与 docs/塞钱探针骨架_2026-10-03.md §四同文）：
##   1) 拍板写下案号；2) 把 _row 里 _skips 上方那对注释行去注释、填案号；
##   3) 去掉 _skips += 1 一行；4) NK1_BRIBE_EXPECT 跑一遍新案全绿；5) 删掉环境通道再入库。
## 反向自证（主控 lane 手册用法）：临时把 GameState.gd:786 的 50 改 100，跑
##   NK1_BRIBE_PROVE=1 NK1_BRIBE_EXPECT=A godot --headless --path . -s res://tools/qa_bribe_probe.gd -- --contract
## 必 rc=1（小循环头一行就红）；复原后 rc=0。证据见 docs/塞钱探针骨架_2026-10-03.md §五。
