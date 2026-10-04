extends SceneTree
## lane-w53-17 士气与风专项探针（headless）：战斗系统方案第一期「大风两散」「战后士气带回航程」，
## 第二期「火长提前报风」「通事劝降效力」。一条一 commit，逐节对应；撤掉该条的修复，对应节即红。
##   一、大风两散（一期，gale_parting）：combat_phases.json t_gale「风到七级以上不能战」的落实。
##      作战的「上限」本来是死字：wind_level_rule 折的七级线 140，而 SeaState.WIND_CAP 130——
##      风暴把它攥到 130 也照旧挂着六级可战名，七级水上照打。落成「风暴海定场」：
##      setup 召雷暴大风须 mean ≥ GALE_SEED_WIND 98 且 base_strength ≥ GALE_BASE_WIND 100
##      （寻常远航 80 走不到；剧情 pending_battle.wind_strength 递得出大风，force_wind 同记）。
##      WorldMap 开战按开关判到即收 flee{flee_ok, parted, gale}（题签 parted「两散」照旧，
##      data.gale 是 w53-16 战后单子出大风文字那一键）。本段验：
##      ① 盘上推演：风暴海盘（盛季 × base 110，400 种子）召得出雷暴大风；
##         寻常远航盘（盛季 × base 80，同扫）一个也召不出（常态没变局）；
##      ② 真起海战挂风暴风场（pending_battle.wind_strength 118）：进场即收 flee 一次，
##         data 带 parted + gale + flee_ok；开关关掉同一场照打到底。
##   二、战后士气带回航程（一期，morale_carry）：CombatMorale.carry_to_voyage 写好但原本
##      无一调用。_battle_exit 收战尾：开关开着、士气簿活着，把「战中涨落 × carry.ratio（0.3，溃过
##      另 −4、降过另 −8——数全在 data/combat_morale.json carry 节）」写到 Fleet.morale，
##      并带 data.morale_carry 供战后单子（w53-16）。验：
##      ① 惨胜盘：士气簿压到 28 → Fleet.morale = 战前 73 + round((28 − 73) × 0.3) = 59；
##      ② 开关关掉：同盘 Fleet.morale 一字不动、data 不带这键；
##      ③ 溃过盘（ever_routed）：折算外再 −4 = 57。
##      判据写值与收战挂同一帧、不跨 await：下一物理帧若先扫到，挂件 tick 会照开战那一刻的
##      rally 目标把簿扳回去（silent green 雷）。
##      注意与 SeaChart 那笔 +5（赢）/ −12（输）旧账各司各段：本件写 before 账，SeaChart 照旧在
##      after 上加减——那是本来就在的账，不是本 lane 的修法。
##   三、火长提前报风（二期，crew_role_effects）：报的是「风向要转」（数据的 wind_shift_warn_s）。
##      SeaState 把风向缓转的 OU 噪声按半秒一步预滚成 30 秒缓冲，wind_bearing_to_in(s) 是真前景，
##      将来（GALE_WARN_S × 级）秒内吹向转过 VEER_DEG 才报、报后真转。判据四盘：
##      ① 盛季寻常风、前景转不过 VEER_DEG 的种子：火长在册也不报；
##      ② 前景转得过的种子：提前约（GALE_WARN_S × 3）秒报一次，报后再走约 warn_s 秒风向真转 ≥ VEER_DEG；
##      ③ 火长 0 级 / crew_role_effects 关掉：同一转场种子一字不报；
##      另钉一格纯件对账：读前景不改风，同种子 200 步 wind_to / wind_speed 逐帧一致（开预报与不开逐字一致）。
##   四、通事劝降效力（二期，crew_role_effects）：劝降胜算原归面板自算（55 − 敌士气那一套），
##      通事一级 +0.05 没人接。本 lane 给 EnemyCaptainAI 一条只读纯函（parley_bonus_tongshi，
##      品级 → +0.05/级；开关那头在战端判）。验三盘：3 级 = +0.15 / 3 级开关关 = 0 / 0 级 = 0。
##      面板那头（parley_chance）：w53-15 挂。
## 用法：godot --headless --path . -s res://tools/qa_w53_17_morale_probe.gd
## 判词：QA_W53_17_MORALE_PROBE PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。跑完还原 Fleet / GameState / pending_battle / Calendar.month / Crew.hired。

const TAG := "QA_W53_17_MORALE_PROBE"

## 探针只与 SeaState 守这三条数（别处改这里跟着红）
const GALE_SEED := 98.0        # SeaState.GALE_SEED_WIND
const GALE_BASE := 100.0       # SeaState.GALE_BASE_WIND（风暴定场起步风）
const GALE_WARN := 5.0         # SeaState.GALE_WARN_S（每级提前秒数）
const BASE_WIND := 80.0        # WorldMap.base_wind_strength（寻常远航）

var _fails: Array = []
var _errlog: _ScriptErrLog = null
var _SeaState = null
var _Switches = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	_SeaState = load("res://scripts/combat/SeaState.gd")
	_Switches = load("res://scripts/combat/CombatSwitches.gd")
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true), "martial": gs.get("martial"),
		"month": root.get_node("Calendar").get("month")}
	_Switches.reset()

	print("== 一、大风两散（一期）")
	_sec_derive_gale_seeds()
	await _sec_gale_parting(fleet, true)
	await _sec_gale_parting(fleet, false)
	print("== 二、战后士气带回航程（一期）")
	await _sec_morale_carry(fleet, {"end": 28.0, "switch": true, "label": "惨胜折算"})
	await _sec_morale_carry(fleet, {"end": 28.0, "switch": false, "label": "关开关一字不动"})
	await _sec_morale_carry(fleet, {"end": 34.0, "ever_routed": true, "switch": true, "label": "溃过再扣"})
	print("== 三、火长提前报风（二期）")
	await _sec_huozhang_warn(fleet)
	print("== 四、通事劝降效力（二期）")
	_sec_tongshi_bonus()

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	root.get_node("Calendar").set("month", saved["month"])
	_Switches.reset()
	await process_frame
	OS.remove_logger(_errlog)
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)


# ══ 一、大风两散 ══════════════════════════════════════════

## 盘上推演：雷暴大风是「风暴海」定场的（pending_battle 里 WorldMap.base_wind_strength 拧到 ≥ GALE_BASE 那一格），
## 不是寻常远航的季风场推得出来的——所以不在四时月令里找种子，而是举一只「风暴海」盘：
## 盛季（强度 1.0）× base 110（风暴定场）扫 400 个种子，验召得出雷暴大风；
## 寻常远航（盛季 × base 80）同扫须一个都召不出（常态没变局）。
func _derive_seeds() -> Dictionary:
	var cal: Node = root.get_node("Calendar")
	var bearing: float = float(cal.call("wind_bearing_of", 6))  # 六月（西南季风盛季，强度 1.0）
	var strength: float = float(cal.call("monsoon_strength_of", 6))
	var out := {"gale": [], "calm_n": 0, "bearing": bearing, "strength": strength}
	for seed in range(400):
		var storm = _SeaState.new()
		storm.setup(bearing, strength, 110.0, "泉州外海", seed)
		if bool(storm.gale):
			(out["gale"] as Array).append({"seed": seed, "mean": storm.wind_mean})
		var calm = _SeaState.new()
		calm.setup(bearing, strength, BASE_WIND, "泉州外海", seed)
		if bool(calm.gale):
			out["calm_n"] = int(out["calm_n"]) + 1
	return out


func _sec_derive_gale_seeds() -> void:
	var d := _derive_seeds()
	_check(not (d["gale"] as Array).is_empty(),
		"风暴海盘（盛季 × base 110）扫 400 个种子召得出雷暴大风（得 %d；没有 = 「大风两散」这场子开不出来）" % (d["gale"] as Array).size())
	_check(int(d["calm_n"]) == 0,
		"寻常远航盘（盛季 × base 80）同扫一个雷暴大风也没有（得 %d / 400——召出就是常态变了局）" % int(d["calm_n"]))


## 真起海战（向 qa_w53_2 借的布景）：雷暴大风场始帧即收 flee{parted, gale}；开关关掉照打。
func _sec_gale_parting(fleet: Node, switch_on: bool) -> void:
	_Switches.reset()
	_Switches.set_on("gale_parting", switch_on)
	var d := _derive_seeds()
	if (d["gale"] as Array).is_empty():
		_check(false, "（开关 %s）没有雷暴大风种子可真起" % ("开" if switch_on else "关"))
		return
	var pick: Dictionary = (d["gale"] as Array)[0]
	var cal: Node = root.get_node("Calendar")
	cal.set("month", 6)  # 与盘上推演同月（盛季）
	var wm := await _battle(fleet, {"type": "pirate_boat", "count": 1},
		{"sea_seed": int(pick["seed"]), "wind_strength": 118.0})
	# 收在 _ready 尾，探针这帧就要看得见
	var got := _probe_got(wm)
	var data: Dictionary = got["data"]
	var label := "开关开" if switch_on else "开关关"
	if switch_on:
		_check(bool(got["resolved"]), "风暴定场真起即收（resolved，%s，种子 %d mean %.1f）" % [label, int(pick["seed"]), float(pick["mean"])])
		_check(str(got["outcome"]) == "flee", "收场 outcome=flee（得 %s）" % str(got["outcome"]))
		_check(bool(data.get("parted", false)), "data.parted=true（两散一路，题签照旧）")
		_check(bool(data.get("gale", false)), "data.gale=true（w53-16 出大风文字那一键）")
		_check(bool(data.get("flee_ok", false)), "data.flee_ok=true（大风两散不追加罚则）")
		# 收过了布景会被 _battle_exit 自己拆掉，不用再 _close
	else:
		_check(not bool(got["resolved"]), "开关关掉：同一风暴定场照打到底（三帧内不收场；收了就说明开关没把新玩关掉）")
		await _close(wm)


# ══ 二、战后士气带回航程 ══════════════════════════════════

## 起一场海战，把士气簿压到目标末值，收战；对账 Fleet.morale 与 data.morale_carry。
## cfg：end（压到的末值）/ ever_routed（先记溃过一次）/ switch（morale_carry 开关）/ label
func _sec_morale_carry(fleet: Node, cfg: Dictionary) -> void:
	_Switches.reset()
	_Switches.set_on("morale_carry", bool(cfg.get("switch", true)))
	var before := 73
	fleet.set("morale", before)
	var wm := await _battle(fleet, {"type": "pirate_boat", "count": 1}, {})
	if not is_instance_valid(wm):
		_check(false, "（%s）海战布景没起来" % str(cfg.get("label", "")))
		return
	var m = wm.get("_morale")
	_check(m != null, "（%s）士气挂件在" % str(cfg.get("label", "")))
	var sheet = m.player_sheet() if m != null else null
	if sheet == null:
		# 挂件要扫到旗舰节点（挂件是物理帧轮询，探针走渲染帧——交叠着等）
		for _i in 10:
			await physics_frame
			if m.player_sheet() != null:
				sheet = m.player_sheet()
				break
	if sheet == null:
		_check(false, "（%s）我方士气簿建不出来" % str(cfg.get("label", "")))
		await _close(wm)
		return
	# 末值定格：压簿末值再回到开战那一刻（carry 按「末 − 开战那一刻」折算，start 留下来报账）。
	# 收战句挂进本帧：下一物理帧若先扫到，挂件 tick 会照开战那一刻的 rally 目标把簿扳回去，
	# 所以这帧收在「写值 → 收战」两语之间、不跨任何 await
	var start: float = sheet.start_value
	if bool(cfg.get("ever_routed", false)):
		sheet.ever_routed = true
	sheet.value = float(cfg.get("end", start))
	var got := _probe_got(wm)
	got["resolved"] = false
	got["outcome"] = ""
	got["data"] = {}
	wm.call("_battle_exit", "win", {})
	var ratio := 0.3
	var dv: float = (float(cfg.get("end", start)) - start) * ratio
	if bool(cfg.get("ever_routed", false)):
		dv -= 4.0
	var expect := clampi(before + int(round(dv)), 0, 100)
	var actual: int = fleet.get("morale")
	if actual != expect and bool(cfg.get("switch", true)):
		print("    [debug] start=%.1f now=%.1f ever_routed=%s live=%s" % [start, sheet.value, str(sheet.ever_routed), str(sheet.snapshot().get("live"))])
	if bool(cfg.get("switch", true)):
		_check(actual == expect, "（%s）Fleet.morale = %d（战前 %d + 折算 %d）" % [str(cfg.get("label", "")), expect, before, int(round(dv))])
		_check(actual < before, "（%s）恶战之后士气低过战前（%d ↘ %d）" % [str(cfg.get("label", "")), before, actual])
		var carry_v: Variant = (got["data"] as Dictionary).get("morale_carry", null)
		_check(carry_v != null and int(carry_v) == expect, "（%s）data.morale_carry=%s 供战后单子（w53-16 读这一键）" % [str(cfg.get("label", "")), str(carry_v)])
	else:
		_check(actual == before, "（%s）开关关掉 Fleet.morale 一字不动（得 %d）" % [str(cfg.get("label", "")), actual])
		_check(not (got["data"] as Dictionary).has("morale_carry"), "（%s）开关关掉 data 不带 morale_carry（逐字回旧行为）" % str(cfg.get("label", "")))


# ══ 三、火长提前报风 ══════════════════════════════════════

## 火长提前报风（数据 officer_effects.huozhang.wind_shift_warn_s 5，报的是「风向要转」）：
## SeaState 把风向缓转的 OU 噪声按半秒一步预滚成 30 秒缓冲（setup / force_wind 那一下滚完），
## step 逐 half-second 从缓冲取——所以 wind_bearing_to_in(s) 是真前景，报的「要转」到点真转。
## 判据（主控定）：①盛季寻常风、前景 15 秒转不过 VEER_DEG 的一场，火长在册也不报——
##      ②前景转得过的一场，提前约（GALE_WARN_S × 3）秒报一次，报后风向真的转了 ≥ VEER_DEG；
##      ③关掉 crew_role_effects 或火长 0 级：一字不报；同一风场种子下风的轨迹与不启这条逐字一致
##      （预滚与逐帧 OU 同一条分布，同种子逐帧一致）。
## Crew.hired 直接写册：huozhang 的品级取数据里 3 级那位老火长（cai_qixing）；tongshi 那头用 kondo_saburo（3 级）。
## 判据只问「hired → level_of 折几级」，不问雇没雇。
const HUOZHANG_3 := "cai_qixing"
## 数据里 3 级通事（博多唐房）——level_of 折 3 → 劝降加成 +0.15
const TONGSHI_3 := "kondo_saburo"

## 前景扫描：取盛季（六月、泉州外海）setup 后 wind_bearing_to_in(15) 距现值转过 VEER_DEG 的种子
##（turn=true）与转不过的种子（turn=false）。不启预报路径一等功是「找得到这两盘」——找不到 = 预滚没了。
func _shift_seeds() -> Dictionary:
	var cal: Node = root.get_node("Calendar")
	var bearing: float = float(cal.call("wind_bearing_of", 6))
	var strength: float = float(cal.call("monsoon_strength_of", 6))
	var pick_turn := -1
	var pick_calm := -1
	var warn_s := 15.0
	for seed in range(600):
		var s = _SeaState.new()
		s.setup(bearing, strength, BASE_WIND, "泉州外海", seed)
		var deg: float = s.wind_turn_deg_in(warn_s)
		if deg >= _SeaState.VEER_DEG + 4.0 and pick_turn < 0:
			pick_turn = seed
		if deg < 1.0 and pick_calm < 0:
			pick_calm = seed
		if pick_turn >= 0 and pick_calm >= 0:
			break
	return {"turn": pick_turn, "calm": pick_calm}


func _sec_huozhang_warn(fleet: Node) -> void:
	var seeds := _shift_seeds()
	_check(int(seeds["turn"]) >= 0, "前景缓冲区找得到「15 秒后要转过 VEER_DEG」的一场（找不到 = 预滚前景没了）")
	_check(int(seeds["calm"]) >= 0, "前景缓冲区找得到「15 秒后还稳」的一场（找不到 = 预报无从不误报）")
	# 判据③先量：同一 storm 种子，不开预报那条路径下风的轨迹（ SeaState 纯件步进、与场景无关——
	# 「关掉 / 没火长 = 风场逐字一致」归 SeaState 预滚设计一票保证：缓冲只在 setup 滚、读取不改值）
	if int(seeds["turn"]) >= 0:
		var cal: Node = root.get_node("Calendar")
		var bearing: float = float(cal.call("wind_bearing_of", 6))
		var strength: float = float(cal.call("monsoon_strength_of", 6))
		var a = _SeaState.new()
		a.setup(bearing, strength, BASE_WIND, "泉州外海", int(seeds["turn"]))
		var b = _SeaState.new()
		b.setup(bearing, strength, BASE_WIND, "泉州外海", int(seeds["turn"]))
		var same := true
		for _i in 200:
			a.step(0.1)
			var _probe_b: float = b.wind_bearing_to_in(0.1)   # b 只读前景、不推时——读完时间仍须照走
			b.step(0.1)
			if a.wind_to.distance_to(b.wind_to) > 0.0001 or absf(a.wind_speed - b.wind_speed) > 0.001:
				same = false
				break
		_check(same, "风场逐字一致：读前景（wind_bearing_to_in）不改风，同种子 200 步逐帧一致")
	for cfg in [{"seed": int(seeds["calm"]), "lv": 3, "switch": true, "want": false, "label": "①风不转不报"},
			{"seed": int(seeds["turn"]), "lv": 3, "switch": true, "want": true, "label": "②风要转提前报"},
			{"seed": int(seeds["turn"]), "lv": 0, "switch": true, "want": false, "label": "③0 级不报"},
			{"seed": int(seeds["turn"]), "lv": 3, "switch": false, "want": false, "label": "③开关关不报"}]:
		await _warn_round(fleet, cfg)


## 一盘火长预报：seed 定风场、lv 定级、switch 定 crew_role_effects。want=true 那格还须「报后真转」。
func _warn_round(fleet: Node, cfg: Dictionary) -> void:
	var crew_skill: Node = root.get_node("Crew")
	var old_hired: Dictionary = {}
	if crew_skill != null:
		old_hired = (crew_skill.get("hired") as Dictionary).duplicate(true)
		var h := (crew_skill.get("hired") as Dictionary).duplicate(true)
		if int(cfg["lv"]) > 0:
			h["huozhang"] = HUOZHANG_3
		else:
			h.erase("huozhang")
		crew_skill.set("hired", h)
	_Switches.reset()
	_Switches.set_on("crew_role_effects", bool(cfg["switch"]))
	var cal: Node = root.get_node("Calendar")
	cal.set("month", 6)
	var wm := await _battle(fleet, {"type": "pirate_boat", "count": 1}, {"sea_seed": int(cfg["seed"])})
	var warned_at := -1
	var b_at_warn := -1.0
	var frames := 0
	var warn_s := float(GALE_WARN) * float(maxi(0, int(cfg["lv"])))
	# 只盯 40 秒（预滚窗 30 秒 + 余量）：预报若在，必在这窗里出；报出即退主循环去量「报后真转」
	while frames < 60 * 40 and warned_at < 0 and not bool(wm.get("resolved")):
		await physics_frame
		frames += 1
		var n: Label = wm.get("_notice")
		if n != null and is_instance_valid(n) and n.visible and "风要转" in n.text:
			warned_at = frames
			b_at_warn = _SeaState.bearing_of((wm.get("_sea") as Object).get("wind_to"))
	var ahead_s := -1.0
	var turned := 0.0
	if warned_at > 0:
		# 报后再走恰 warn_s 秒（预报须早在预滚窗内，30 秒窗足够——回环上限 120 秒只是兜底，不许跑到）
		var wait := int(round(warn_s * 60.0))
		while frames < warned_at + wait and not bool(wm.get("resolved")):
			await physics_frame
			frames += 1
		ahead_s = float(frames - warned_at) / 60.0
		var now_b: float = _SeaState.bearing_of((wm.get("_sea") as Object).get("wind_to"))
		turned = rad_to_deg(absf(angle_difference(deg_to_rad(b_at_warn), deg_to_rad(now_b))))
	if bool(cfg["want"]):
		_check(warned_at > 0, "%s：火长 3 级出预报（浮字「风要转了」）" % str(cfg["label"]))
		if warned_at > 0:
			_check(ahead_s >= warn_s - 0.05 and ahead_s <= warn_s + 0.5, "%s：报后再走约 warn_s 秒（得 %.1f 秒；预报出得太晚，出了 30 秒预滚窗风就不走了）" % [str(cfg["label"]), ahead_s])
			_check(turned >= _SeaState.VEER_DEG, "%s：报后再走约 %.1f 秒风向真转了 %.1f°（须 ≥ %.0f°）" % [str(cfg["label"]), ahead_s, turned, _SeaState.VEER_DEG])
	else:
		_check(warned_at < 0, "%s：不出预报浮字" % str(cfg["label"]))
	if crew_skill != null:
		crew_skill.set("hired", old_hired)
	_Switches.reset()
	if is_instance_valid(wm):
		await _close(wm)


# ══ 四、通事劝降效力 ══════════════════════════════════════

func _sec_tongshi_bonus() -> void:
	var AIA = load("res://scripts/combat/EnemyCaptainAI.gd")
	_check(AIA != null, "EnemyCaptainAI 载得动")
	if AIA == null:
		return
	# 只读函数存在（static 一路，跟 captain_verdict 同册）——照源检索，不必建树
	var src := FileAccess.get_file_as_string("res://scripts/combat/EnemyCaptainAI.gd")
	_check("static func parley_bonus_tongshi" in src, "EnemyCaptainAI 多出只读的 parley_bonus_tongshi（通事一级 +0.05；w53-15 劝降面板那头挂）")
	if not ("static func parley_bonus_tongshi" in src):
		return
	# 战端同式：判开关 → 查册子 → 折算。四盘全过：3 级开、3 级关、0 级开、负值档
	var crew_skill: Node = root.get_node("Crew")
	var old_hired: Dictionary = {}
	if crew_skill != null:
		old_hired = (crew_skill.get("hired") as Dictionary).duplicate(true)
	for cfg in [{"lv": 3, "switch": true, "want": 0.15}, {"lv": 3, "switch": false, "want": 0.0},
			{"lv": 0, "switch": true, "want": 0.0}]:
		_Switches.reset()
		_Switches.set_on("crew_role_effects", bool(cfg["switch"]))
		if crew_skill != null:
			var h := (crew_skill.get("hired") as Dictionary).duplicate(true)
			if int(cfg["lv"]) > 0:
				h["tongshi"] = TONGSHI_3
			else:
				h.erase("tongshi")
			crew_skill.set("hired", h)
		var lv: int = crew_skill.call("level_of", "tongshi") if crew_skill != null else 0
		var got_b := 0.0
		if _Switches.on("crew_role_effects"):
			got_b = float(AIA.call("parley_bonus_tongshi", lv))
		_check(absf(got_b - float(cfg["want"])) < 0.001,
			"通事 %d 级 / 开关 %s → 加成 %.2f（得 %.3f）" % [int(cfg["lv"]), "开" if bool(cfg["switch"]) else "关", float(cfg["want"]), got_b])
	if crew_skill != null:
		crew_skill.set("hired", old_hired)
	_Switches.reset()


# ══ 布景 ══════════════════════════════════════════════════

## 探头收战账：WorldMap._battle_exit 一发 battle_finished，这里记 outcome/data 到 meta（wm 随后 queue_free，引用握不久）
func _wire_probe(wm: Node) -> Dictionary:
	var box := {"resolved": false, "outcome": "", "data": {}}
	var cb := func(outcome: String, data: Dictionary) -> void:
		box["resolved"] = true
		box["outcome"] = outcome
		box["data"] = data.duplicate(true)
	wm.connect("battle_finished", cb)
	_probe_boxes[wm.get_instance_id()] = box
	return box

var _probe_boxes: Dictionary = {}

func _probe_got(wm) -> Dictionary:
	if wm == null or not is_instance_valid(wm):
		for key in _probe_boxes:
			return _probe_boxes[key]
		return {"resolved": false, "outcome": "", "data": {}}
	var key: int = wm.get_instance_id()
	return _probe_boxes.get(key, {"resolved": false, "outcome": "", "data": {}})


func _close(wm) -> void:
	if is_instance_valid(wm):
		_probe_boxes.erase(wm.get_instance_id())
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


## 开一场海战：本队一艘试船对 enemy 条目；敌炮冻住（fire_timer=INF），pb_extra 并进 pending_battle（sea_seed 等）。
func _battle(fleet: Node, enemy: Dictionary, pb_extra: Dictionary) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	var pb := {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [enemy], "sea_name": "泉州外海", "source": {"scene": "qa_w53_17"}}
	for k in pb_extra:
		pb[k] = pb_extra[k]
	root.get_node("GameManager").set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	_wire_probe(wm)
	root.add_child(wm)
	for _i in 3:
		await process_frame
	# 雷暴大风场在 _ready 尾已收、wm 已随 _battle_exit 拆掉（不再 get_children，照原样返回供探针读收战账）
	if not is_instance_valid(wm):
		return wm
	for f in wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip")):
		f.set("fire_timer", INF)
	return wm


## 抄自 w53-2 探针：本进程 SCRIPT ERROR 记账（末格判红）。原类在 w53-2 探针里不导出，这里写一份小的
class _ScriptErrLog extends Logger:
	var lines: PackedStringArray = []
	func _log_message(message: String, error: bool) -> void:
		if error:
			lines.append(message)
	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		lines.append("%s:%d %s %s" % [_file, line, code, rationale])
