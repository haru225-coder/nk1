extends SceneTree
## lane-w53-p6-landing 小规模登陆战专项探针（战斗系统方案 §十 第六期「小规模登陆战（复用陆战骰子）」，
## 一条一节、回退即红）：
##   一、入口出现的条件（开关 landing_raid）：要四样齐——胜局 + 敌是海寇（source.event=="pirate"）+
##       船在宋土沿海 + 开关开。缺一样都不挂那一行：败局不挂、元军哨船（yuan_patrol）不挂、
##       拦港哨船（blockade）不挂、异国港（博多 / 萨摩 / 耽罗 / 占城）与流求海面（南岛海道北口）岸外不挂；
##       外海无港不挂。
##   二、登岸人数与战力：水手数封顶 LandingRaid.LAND_MAX（30）；战力 = 下船人数 × 将领系数 ×
##       船上士气系数——与守城那一路（SiegeMelee.raid_power）同一个式子，同一组入参逐位相等。
##   三、骰子借的是守城那一路：LandingRaid.roll 与 SiegeMelee.clash(power, RAID_LO, RAID_HI, 1.0)
##       同种子逐位相等（同一次序、同一枚 randf_range），胜负相同；改守城那一路的常量不动本件。
##       LandingRaid.roll 的上下限就是 SiegeMelee.clash 收到的上下限（本件不另起一套掷法）。
##   四、胜率（固定种子 1..200，各档 200 次）：小艍十来人的一档压在低位（< 0.25），满编大船的一档
##       够得着但也赢不满（< 0.75）——不让剿寨成了十来人的稳赚、也不让满编必胜。
##   五、胜的账：钱落在 80～220 之间掷一次进钱匣、名声 +3（走 add_fame）、士气 +6（封顶 MORALE_MAX）、
##       寨里三样老实货真搬进舱（件数 = WIN_CARGO 的上限，舱装不下就少装）、水手不动。
##   六、败的账：下船的人折 LOSE_LOSS_RATE 一成半（跨船摊扣、每船至少留一人）、士气 −8、名声 +1（去打了一场）、
##       钱不动、舱货不动。
##   七、收队回船 = 什么都不动（选了 hold 那一项）：钱 / 名声 / 士气 / 水手 / 舱货逐样不变。
##   八、关态 = 逐字回旧（开关 landing_raid 关）：战后单子上没有那一行，落账那条路也不动全局。
##   九、真走 SeaChart 收战：起一张海图、摆一场海寇仗走 _on_battle_result，清空 pending_battle 之前扣住的
##       source 与所在港照那两样走挂卡判据，那一行挂；换成元军哨船那一仗、败局，不挂。
##   十、不成摇钱树：一次剿寨的期望净收益（各档胜率 × 胜局实得 − 败率 × 折人 × 船屋添人价 20）印数，
##       对照 simulate_run 开局一段「小艍半舱最佳前五笔生意净赚 1076～1191」判两条界——胜局实得低于
##       第五笔的 1076（赢一回也挣不过跑一趟寻常买卖）、各档期望净低于头一笔 1191 的两成。
##   十一、真走 SeaChart 落账：_on_after_action_done 收到「登岸剿寨」那一项，经 _landing_settle 真动全局——
##       胜（钱 / 名声 / 士气 / 三样货进舱、水手不动）、舱快满时少装（留在岸上的件数写进札记）、
##       败（折人 / 士气 / 名声、钱与货不动）、收队回船（一样不动）；札记一句逐样核对，钱与货各只说一遍。
## 用法：godot --headless --path . -s res://tools/qa_w53_p6_landing_probe.gd
## 判词：QA_W53_P6_LANDING cases=N fails=M；fails>0 退 1。本进程有 SCRIPT ERROR 即红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CS := preload("res://scripts/combat/CombatSwitches.gd")
const LR := preload("res://scripts/combat/LandingRaid.gd")
const SM := preload("res://scripts/combat/SiegeMelee.gd")

const TAG := "QA_W53_P6_LANDING"
## 胜率量数：每档 200 次（brief 要 ≥200）
const ODDS_N := 200
## 正常跑商的对照：simulate_run 开局一段「从泉州出发、本金 1000 钱、小艍船半舱的最佳前 5 笔生意」
## 净赚 1191 / 1126 / 1126 / 1076 / 1076（是净利，已扣本钱）——剿寨一回的账要远在它下面，才不是摇钱树
const TRADE_TRIP_BEST := 1191
const TRADE_TRIP_FIFTH := 1076
## 折一个水手的钱：船屋添人一人 20 钱（ShipyardPage「添 N 人」钮的 hire_cost = N × 20）
const SAILOR_COST := 20
## 各处胜率界的档位（水手数 / 将领系数 / 士气系数）；头一档是最小的船、末一档是最大的船
const PROFILES := [
	{"name": "小艍 15 人", "crew": 15, "cap": 1.0, "mf": 0.88, "hi": 0.25},
	{"name": "客舟 40 人", "crew": 40, "cap": 1.0, "mf": 0.88, "hi": 0.75},
	{"name": "福船（中）50 人", "crew": 50, "cap": 1.15, "mf": 0.88, "hi": 0.75},
	{"name": "广船 90 人", "crew": 90, "cap": 1.25, "mf": 0.92, "hi": 0.75},
	{"name": "福船（大）110 人", "crew": 110, "cap": 1.4, "mf": 0.96, "hi": 0.75},
]

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


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


## _run 被脚本错半路掐断时不会走到 _report——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _report() -> void:
	if _reported:
		return
	_reported = true
	await process_frame
	OS.remove_logger(_tally)
	_expect(_tally.lines.is_empty(), "本进程无 SCRIPT ERROR（%s）" % [
		"0 行" if _tally.lines.is_empty() else "%d 行：%s" % [_tally.lines.size(), str(_tally.lines[0])]])
	if fails == 0:
		print("%s cases=%d fails=0" % [TAG, cases])
		quit(0)
		return
	print("%s cases=%d fails=%d" % [TAG, cases, fails])
	quit(1)


func _run() -> void:
	# 计数器在 _init 里挂上（这里不再起第二只：两只都挂着、只摘一只，余下那只一直挂到进程退）
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	var saved := {
		"ships": (fleet.get("ships") as Array).duplicate(true),
		"morale": fleet.get("morale"),
		"water": fleet.get("water"),
		"food": fleet.get("food"),
		"money": gs.get("money"),
		"fame": gs.get("fame"),
		"martial": gs.get("martial"),
	}

	print("== 一、入口出现的条件（四样齐 / 缺一样都不挂）")
	_sec_gate()
	print("== 二、下船人数与战力（与守城那一路同一个式子）")
	_sec_power()
	print("== 三、骰子借的是守城那一路（同种子逐位相等）")
	_sec_dice()
	print("== 四、胜率（固定种子 1..%d）" % ODDS_N)
	_sec_odds()
	print("== 五、胜的账")
	_sec_win(fleet, gs, saved)
	print("== 六、败的账")
	_sec_lose(fleet, gs, saved)
	print("== 七、收队回船 = 什么都不动")
	_sec_hold(fleet, gs, saved)
	print("== 八、关态 = 逐字回旧")
	_sec_off(fleet, gs, saved)
	print("== 九、真走 SeaChart：海寇仗收战后那一行挂得出来")
	await _sec_chart()
	print("== 十、期望收益对照 simulate_run 开局跑商（印数 + 两条界）")
	_sec_ev()
	print("== 十一、真走 SeaChart 落账（_on_after_action_done → _landing_settle）")
	await _sec_settle(fleet, gs)

	# 还原这一局（探针不动盘面）
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	fleet.set("water", saved["water"])
	fleet.set("food", saved["food"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	gs.set("martial", saved["martial"])
	CS.reset()
	_report()


# ── 一、入口条件 ──────────────────────────────────────

func _sec_gate() -> void:
	var pirate := {"scene": "SeaChart", "event": "pirate"}
	var patrol := {"scene": "SeaChart", "event": "yuan_patrol"}
	var blockade := {"scene": "SeaChart", "event": "blockade", "port": "xinghua"}
	# 四样齐
	_expect(LR.offerable("win", pirate, "quanzhou"), "齐：胜 + 海寇 + 泉州岸外 + 开关开 → 挂")
	_expect(LR.choices_for("win", pirate, "quanzhou").size() == 1, "齐：挂出来的是一行")
	var row: Dictionary = LR.choices_for("win", pirate, "quanzhou")[0]
	_expect(str(row.get("key", "")) == "landing", "那一行的 key 是 landing（得「%s」）" % str(row.get("key", "")))
	var opts: Array = row.get("options", [])
	_expect(opts.size() == 2, "两择（登岸剿寨 / 收队回船，得 %d）" % opts.size())
	_expect(str(opts[0].get("id", "")) == "raid" and str(opts[1].get("id", "")) == "hold", "两择的 id 是 raid / hold")
	_expect(bool(opts[1].get("default", false)) and not bool(opts[0].get("default", false)),
		"默认项是收队回船（不替玩家按下剿寨）")

	# 缺一：败局
	_expect(not LR.offerable("lose", pirate, "quanzhou"), "缺「胜」：败局不挂")
	_expect(not LR.offerable("flee", pirate, "quanzhou"), "缺「胜」：脱战不挂")
	_expect(not LR.offerable("disengaged", pirate, "quanzhou"), "缺「胜」：两散不挂")
	# 缺二：不是海寇
	_expect(not LR.offerable("win", patrol, "quanzhou"), "缺「海寇」：元军哨船不挂")
	_expect(not LR.offerable("win", blockade, "xinghua"), "缺「海寇」：拦港哨船不挂")
	_expect(not LR.offerable("win", {}, "quanzhou"), "缺「海寇」：没有 source 不挂")
	_expect(LR.from_pirate(pirate) and not LR.from_pirate(patrol) and not LR.from_pirate(blockade),
		"from_pirate 只认 source.event==pirate")
	# 缺三：不在宋土沿海
	for pid in ["hakata", "kagoshima", "jeju", "champa"]:
		_expect(not LR.offerable("win", pirate, pid), "缺「宋土沿海」：异国港 %s 岸外不挂" % pid)
	_expect(not LR.offerable("win", pirate, ""), "缺「宋土沿海」：外海（无港）不挂")
	_expect(not LR.offerable("win", pirate, "nowhere"), "缺「宋土沿海」：认不得的港不挂")
	_expect(not LR.offerable("win", pirate, "ryukyu"), "缺「宋土沿海」：南岛海道北口（流求海面北缘，不是宋土）岸外不挂")
	_expect(LR.on_song_shore("quanzhou") and LR.on_song_shore("penghu"), "宋土沿海认泉州、澎湖（澎湖属泉州晋江县）")
	_expect(LR.SONG_SHORE.size() == 9, "宋土沿海九港（得 %d）" % LR.SONG_SHORE.size())
	# 缺四：开关关
	CS.set_on("landing_raid", false)
	_expect(not LR.offerable("win", pirate, "quanzhou"), "缺「开关开」：关掉不挂")
	_expect(LR.choices_for("win", pirate, "quanzhou").is_empty(), "关掉：一行都不挂")
	CS.set_on("landing_raid", true)
	_expect(LR.choices_for("win", pirate, "quanzhou").size() == 1, "开回来：那一行又挂上")


# ── 二、下船人数与战力 ────────────────────────────────

func _sec_power() -> void:
	_expect(LR.LAND_MAX == 30, "下船人数上限 30（得 %d）" % LR.LAND_MAX)
	_expect(LR.landing_party(6) == 6, "6 人的小艍：6 个都下船")
	_expect(LR.landing_party(30) == 30, "30 人：刚好全下")
	_expect(LR.landing_party(50) == 30, "50 人的福船（中）：只放 30 人下船（留人看守）")
	_expect(LR.landing_party(110) == 30, "110 人的福船（大）：只放 30 人下船")
	_expect(LR.landing_party(0) == 0 and LR.landing_party(-5) == 0, "没人 / 负数：0 人下船")
	# 战力式子与守城那一路逐位同源：同入参逐位相等
	var bad := 0
	for crew in [6, 15, 30, 50, 110]:
		for cap in [1.0, 1.15, 1.25, 1.4]:
			for mf in [0.6, 0.88, 1.0]:
				var a := LR.raid_power(crew, cap, mf)
				var b := SM.raid_power(crew, cap, mf)
				if a != b:
					bad += 1
	_expect(bad == 0, "战力式子与 SiegeMelee.raid_power 逐位相等（差 %d 处）" % bad)
	_expect(LR.raid_power(30, 1.0, 0.88) == SM.raid_power(30, 1.0, 0.88),
		"30 人 × 1.0 × 0.88 = %s（与守城那边同）" % str(LR.raid_power(30, 1.0, 0.88)))


# ── 三、骰子借守城那一路 ──────────────────────────────

func _sec_dice() -> void:
	var rng := LR.raid_range()
	_expect(rng.size() == 2 and float(rng[0]) == LR.RAID_LO and float(rng[1]) == LR.RAID_HI,
		"本件的骰子上下限就是 RAID_LO / RAID_HI（%s / %s）" % [str(LR.RAID_LO), str(LR.RAID_HI)])
	# 同种子：LandingRaid.roll 与直接调 SiegeMelee.clash(同上下限) 逐位相等（同一次序、同一枚 randf_range）
	var bad := 0
	for k in range(1, 121):
		var power := float(k) * 0.4
		seed(k)
		var a := LR.roll(power)
		seed(k)
		var b := SM.clash(power, LR.RAID_LO, LR.RAID_HI, 1.0)
		if float(a["enemy"]) != float(b["enemy"]) or bool(a["won"]) != bool(b["won"]):
			bad += 1
	_expect(bad == 0, "120 个种子：LandingRaid.roll 与 SiegeMelee.clash 逐位相等（差 %d 处）" % bad)
	# 掷完下一枚 randf() 也同（掷骰次数没变）
	seed(99)
	var r1 := LR.roll(30.0)
	var n1 := randf_range(0.0, 1.0)
	seed(99)
	var r2 := SM.clash(30.0, LR.RAID_LO, LR.RAID_HI, 1.0)
	var n2 := randf_range(0.0, 1.0)
	_expect(n1 == n2, "掷完下一枚 randf() 相同（%s / %s）——掷骰次数不变" % [str(n1), str(n2)])
	# 胜负判据仍是「战力不低于敌军即胜」
	var won_hi := 0
	var won_lo := 0
	for k in range(1, 200):
		seed(k)
		if bool(LR.roll(1000.0)["won"]):
			won_hi += 1
		seed(k)
		if bool(LR.roll(0.0)["won"]):
			won_lo += 1
	_expect(won_hi == 199, "战力 1000（远高于上限 68）：199 个种子全胜（得 %d）" % won_hi)
	_expect(won_lo == 0, "战力 0：199 个种子全负（得 %d）" % won_lo)


# ── 四、胜率 ──────────────────────────────────────────

func _sec_odds() -> void:
	for prof in PROFILES:
		var crew := int(prof["crew"])
		var cap := float(prof["cap"])
		var mf := float(prof["mf"])
		var land := LR.landing_party(crew)
		var power := LR.raid_power(land, cap, mf)
		var won := 0
		for k in range(1, ODDS_N + 1):
			seed(k)
			if bool(LR.roll(power)["won"]):
				won += 1
		var rate := float(won) / float(ODDS_N)
		print("     QA_W53_P6_LANDING_ODDS %s：下船 %d 人・战力 %.1f → %d/%d = %.3f" % [
			str(prof["name"]), land, power, won, ODDS_N, rate])
		_expect(rate < float(prof["hi"]), "%s 胜率 %.3f < %.2f（不让这一档通吃）" % [
			str(prof["name"]), rate, float(prof["hi"])])
		_expect(rate > 0.0, "%s 胜率 %.3f > 0（也不是全负，留了指望）" % [str(prof["name"]), rate])
	var small: Dictionary = PROFILES[0]
	var big: Dictionary = PROFILES[PROFILES.size() - 1]
	var r_small := _rate_of(small)
	var r_big := _rate_of(big)
	_expect(r_big > r_small, "船越大胜率越高：%s %.3f > %s %.3f" % [
		str(big["name"]), r_big, str(small["name"]), r_small])
	_expect(r_small < 0.25, "十来人的小艍胜率 %.3f < 0.25——小本钱来剿寨是送人" % r_small)
	_expect(r_big < 0.75, "满编大船胜率 %.3f < 0.75——剿寨不是必胜" % r_big)


func _rate_of(prof: Dictionary) -> float:
	var power := LR.raid_power(LR.landing_party(int(prof["crew"])), float(prof["cap"]), float(prof["mf"]))
	var won := 0
	for k in range(1, ODDS_N + 1):
		seed(k)
		if bool(LR.roll(power)["won"]):
			won += 1
	return float(won) / float(ODDS_N)


# ── 五、胜的账 ────────────────────────────────────────

## 一个必赢的种子（战力拉满，掷多少次都赢的那一枚）：先找一个
func _win_seed() -> int:
	for k in range(1, 4000):
		seed(k)
		if bool(LR.roll(1000.0)["won"]):
			return k
	return -1


## 一个必输的种子
func _lose_seed() -> int:
	for k in range(1, 4000):
		seed(k)
		if not bool(LR.roll(0.0)["won"]):
			return k
	return -1


func _row(chosen: String) -> Dictionary:
	var r: Dictionary = LR.choices_for("win", {"event": "pirate"}, "quanzhou")[0]
	var c := r.duplicate()
	c["chosen"] = chosen
	return c


func _sec_win(fleet: Node, gs: Node, saved: Dictionary) -> void:
	fleet.set("ships", (saved["ships"] as Array).duplicate(true))
	# 摆一条 50 人的福船（中）：下船 30 人、舱里空着，好数寨里搬回的货
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "durability": 300.0,
		"max_durability": 300.0, "crew": 50, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	fleet.set("morale", 60)
	gs.set("money", 1000)
	gs.set("fame", 0)
	var k := _win_seed()
	seed(k)
	var res: Dictionary = LR.layout(_row("raid"), 50, 1.0, 0.88)
	_expect(bool(res.get("won", false)), "必赢种子 %d：这一仗胜了" % k)
	_expect(int(res.get("landing", 0)) == 30, "下船 30 人（得 %d）" % int(res.get("landing", 0)))
	var money := int(res.get("money", 0))
	_expect(money >= int(LR.WIN_LOOT_LO) and money <= int(LR.WIN_LOOT_HI),
		"胜局的钱落在 %d～%d（得 %d）" % [int(LR.WIN_LOOT_LO), int(LR.WIN_LOOT_HI), money])
	_expect(int(res.get("fame_gained", 0)) == LR.WIN_FAME, "名声 +%d（得 %d）" % [LR.WIN_FAME, int(res.get("fame_gained", 0))])
	_expect(int(res.get("morale_delta", 0)) == LR.WIN_MORALE, "士气 +%d（得 %d）" % [LR.WIN_MORALE, int(res.get("morale_delta", 0))])
	_expect(int(res.get("crew_lost", 0)) == 0, "胜局不折人（得 %d）" % int(res.get("crew_lost", 0)))
	var cargo: Dictionary = res.get("cargo", {})
	_expect(int(cargo.get("grain", 0)) == 12 and int(cargo.get("sea_salt", 0)) == 6 and int(cargo.get("deer_hide", 0)) == 2,
		"寨里三样东西按上限给：米 12・盐 6・鹿皮 2（得 %s）" % str(cargo))
	_expect(LR.cargo_units(cargo) == 20, "三样合计 20 件（得 %d）" % LR.cargo_units(cargo))
	# 真落账：钱 / 名声 / 士气 各动一笔，货真进舱
	var money0 := int(gs.get("money"))
	var fame0 := int(gs.get("fame"))
	var morale0 := int(fleet.get("morale"))
	gs.add_money(int(res.get("money", 0)))
	gs.add_fame(int(res.get("fame_gained", 0)))
	fleet.set("morale", mini(fleet.MORALE_MAX, morale0 + int(res.get("morale_delta", 0))))
	for gid in cargo.keys():
		fleet.add_cargo(str(gid), int(cargo[gid]), LR.WIN_CARGO_COST)
	_expect(int(gs.get("money")) == money0 + money, "钱匣真增 %d（得 %d）" % [money, int(gs.get("money")) - money0])
	_expect(int(gs.get("fame")) == fame0 + LR.WIN_FAME, "名声真增 %d（得 %d）" % [LR.WIN_FAME, int(gs.get("fame")) - fame0])
	_expect(int(fleet.get("morale")) == morale0 + LR.WIN_MORALE, "士气真增 %d（得 %d）" % [LR.WIN_MORALE, int(fleet.get("morale")) - morale0])
	_expect(fleet.cargo_qty("grain") == 12 and fleet.cargo_qty("sea_salt") == 6 and fleet.cargo_qty("deer_hide") == 2,
		"三样货真在舱里（米 %d・盐 %d・鹿皮 %d）" % [fleet.cargo_qty("grain"), fleet.cargo_qty("sea_salt"), fleet.cargo_qty("deer_hide")])
	_expect(fleet.cargo_cost("deer_hide") == 0.0, "剿来的货记 0 成本（得 %s）——不是买来的" % str(fleet.cargo_cost("deer_hide")))
	_expect(fleet.total_crew() == 50, "胜局水手不动（得 %d）" % fleet.total_crew())


func _sec_lose(fleet: Node, gs: Node, saved: Dictionary) -> void:
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "durability": 300.0,
		"max_durability": 300.0, "crew": 50, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	fleet.set("morale", 60)
	gs.set("money", 1000)
	gs.set("fame", 0)
	fleet.add_cargo("grain", 5, 8.0)
	var k := _lose_seed()
	seed(k)
	var res: Dictionary = LR.layout(_row("raid"), 50, 0.0, 0.6)
	_expect(not bool(res.get("won", false)), "必输种子 %d：这一仗败了" % k)
	_expect(int(res.get("money", 0)) == 0, "败局不得钱（得 %d）" % int(res.get("money", 0)))
	_expect(int(res.get("fame_gained", 0)) == LR.LOSE_FAME, "败局名声 +%d（去打了一场，得 %d）" % [LR.LOSE_FAME, int(res.get("fame_gained", 0))])
	_expect(int(res.get("morale_delta", 0)) == LR.LOSE_MORALE, "败局士气 %d（得 %d）" % [LR.LOSE_MORALE, int(res.get("morale_delta", 0))])
	var want_lost := int(round(float(res.get("landing", 0)) * LR.LOSE_LOSS_RATE))
	_expect(int(res.get("crew_lost", 0)) == want_lost,
		"折人 = 下船 %d × 一成半 = %d（得 %d）" % [int(res.get("landing", 0)), want_lost, int(res.get("crew_lost", 0))])
	_expect((res.get("cargo", {}) as Dictionary).is_empty(), "败局不搬货回舱")
	# 真落账：水手真折、每船至少留一人；钱与舱货不动
	var crew0: int = fleet.total_crew()
	var money0 := int(gs.get("money"))
	var grain0: int = fleet.cargo_qty("grain")
	var lost: int = fleet.lose_crew_random(int(res.get("crew_lost", 0)))
	_expect(lost == want_lost, "水手真折 %d（得 %d）" % [want_lost, lost])
	_expect(fleet.total_crew() == crew0 - want_lost, "船队人数 %d → %d" % [crew0, fleet.total_crew()])
	_expect(fleet.ship_crew(0) >= 1, "每船至少留一人（旗舰剩 %d）" % fleet.ship_crew(0))
	_expect(int(gs.get("money")) == money0, "败局钱匣不动")
	_expect(fleet.cargo_qty("grain") == grain0, "败局舱货不动（米 %d）" % fleet.cargo_qty("grain"))
	# 小舰队：折人不超过船上的人（每船留一人）
	fleet.set("ships", [{"type": "sampan", "name": "小艍", "durability": 120.0,
		"max_durability": 120.0, "crew": 7, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	seed(11)
	var r2: Dictionary = LR.layout(_row("raid"), 7, 0.0, 0.2)
	_expect(int(r2.get("landing", 0)) == 7, "小艍 7 人全下船（得 %d）" % int(r2.get("landing", 0)))
	_expect(not bool(r2.get("won", false)), "小艍战力 0：必败")
	var l2: int = fleet.lose_crew_random(int(r2.get("crew_lost", 0)))
	_expect(fleet.ship_crew(0) >= 1, "小艍折人后仍留一人（剩 %d，实际折 %d）" % [fleet.ship_crew(0), l2])


# ── 七、收队回船 ──────────────────────────────────────

func _sec_hold(fleet: Node, gs: Node, saved: Dictionary) -> void:
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "durability": 300.0,
		"max_durability": 300.0, "crew": 50, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	fleet.set("morale", 60)
	gs.set("money", 1000)
	gs.set("fame", 0)
	fleet.add_cargo("grain", 5, 8.0)
	var money0 := int(gs.get("money"))
	var fame0 := int(gs.get("fame"))
	var morale0 := int(fleet.get("morale"))
	var crew0: int = fleet.total_crew()
	var grain0: int = fleet.cargo_qty("grain")
	seed(5)
	var res: Dictionary = LR.layout(_row("hold"), 50, 1.0, 0.88)
	_expect(bool(res.get("ok", false)), "收队回船：落账 ok")
	_expect(not bool(res.get("won", false)) and int(res.get("money", 0)) == 0 and int(res.get("crew_lost", 0)) == 0
		and int(res.get("morale_delta", 0)) == 0 and int(res.get("fame_gained", 0)) == 0
		and (res.get("cargo", {}) as Dictionary).is_empty(), "收队回船：账上什么都不动")
	_expect(str(res.get("note", "")).contains("收队回船"), "注记句写收队回船（得「%s」）" % str(res.get("note", "")))
	_expect(int(gs.get("money")) == money0 and int(gs.get("fame")) == fame0
		and int(fleet.get("morale")) == morale0 and fleet.total_crew() == crew0
		and fleet.cargo_qty("grain") == grain0, "收队回船：钱 / 名声 / 士气 / 水手 / 舱货逐样不变")
	# 人不够：一个都下不去
	seed(5)
	var res2: Dictionary = LR.layout(_row("raid"), 0, 1.0, 0.88)
	_expect(int(res2.get("landing", 0)) == 0 and int(res2.get("money", 0)) == 0,
		"船上没人可下：什么都不动（得 %d 人）" % int(res2.get("landing", 0)))


# ── 八、关态 ──────────────────────────────────────────

func _sec_off(fleet: Node, gs: Node, saved: Dictionary) -> void:
	CS.set_on("landing_raid", false)
	_expect(LR.choices_for("win", {"event": "pirate"}, "quanzhou").is_empty(), "关：战后单子上没有那一行")
	_expect(not LR.offerable("win", {"event": "pirate"}, "quanzhou"), "关：offerable 判否")
	CS.set_on("landing_raid", true)
	_expect(LR.choices_for("win", {"event": "pirate"}, "quanzhou").size() == 1, "开回来：那一行挂上")


# ── 九、真走 SeaChart ─────────────────────────────────

## 起一张海图（headless 也起得来：attach_after_action 返回 null，本探针直接看 choices）
func _chart() -> Node:
	var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	return sc


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _sec_chart() -> void:
	var sc := _chart()
	await _frames(3)
	_expect(sc != null, "海图起得来（SeaChart.tscn）")
	# 真走 _on_battle_result：收战那一刻 SeaChart 得在清空 pending_battle 之前把两样扣住——
	# 本探针摆一场海寇仗，看扣下来的 source 与所在港，再照那两样走一遍挂卡判据。
	var pirate := {"scene": "SeaChart", "event": "pirate"}
	var patrol := {"scene": "SeaChart", "event": "yuan_patrol"}
	var gm: Node = root.get_node("GameManager")
	sc.set("remaining_li", 50.0)
	sc.set("selected_port", "quanzhou")
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海", "source": pirate})
	sc.call("_on_battle_result", "win", {"player_damage": 5.0})
	await _frames(2)
	_expect(str((sc.get("_landing_src") as Dictionary).get("event", "")) == "pirate",
		"收战后扣住 source：是海寇（得「%s」）" % str((sc.get("_landing_src") as Dictionary).get("event", "")))
	_expect(str(sc.get("_landing_port")) != "", "收战后扣住所在港（得「%s」）" % str(sc.get("_landing_port")))
	_expect(gm.get("pending_battle") is Dictionary and (gm.get("pending_battle") as Dictionary).is_empty(),
		"pending_battle 照旧在收战后清空（扣下来的那两样不动它）")
	_expect(LR.choices_for("win", sc.get("_landing_src"), str(sc.get("_landing_port"))).size() == 1,
		"照扣下来的那两样：那一行挂（%s + %s）" % [str((sc.get("_landing_src") as Dictionary).get("event", "")), str(sc.get("_landing_port"))])
	# 换一场元军哨船的：同一条路扣下来，那一行不挂
	gm.set("pending_battle", {"battle": true, "power": 500.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": patrol})
	sc.call("_on_battle_result", "win", {"player_damage": 5.0})
	await _frames(2)
	_expect(str((sc.get("_landing_src") as Dictionary).get("event", "")) == "yuan_patrol", "第二场：扣住的是元军哨船")
	_expect(LR.choices_for("win", sc.get("_landing_src"), str(sc.get("_landing_port"))).is_empty(),
		"元军哨船那一仗：那一行不挂")
	# 败局：同一条路也不挂
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海", "source": pirate})
	sc.call("_on_battle_result", "lose", {"player_damage": 300.0})
	await _frames(2)
	_expect(LR.choices_for("lose", sc.get("_landing_src"), str(sc.get("_landing_port"))).is_empty(), "败局：那一行不挂")
	# 读数：收战（没打过剿寨）后清空，不残留上一场
	_expect((sc.call("last_landing_report") as Dictionary).is_empty(), "没打过剿寨：读数是空的")
	sc.queue_free()
	await _frames(2)


# ── 十、期望收益 ──────────────────────────────────────

func _sec_ev() -> void:
	# 胜局实得：钱取两档中数 + 寨里那几样货按 base_value 计面值（现读 goods.json，WIN_CARGO 改了这里跟着变）
	var gm: Node = root.get_node("GameManager")
	var cargo_val := 0
	for entry in LR.WIN_CARGO:
		var g: Dictionary = gm.call("get_good_by_id", str(entry["good"]))
		cargo_val += int(entry["qty"]) * int(g.get("base_value", 0))
	var money_mid := (LR.WIN_LOOT_LO + LR.WIN_LOOT_HI) * 0.5
	var win_take := money_mid + float(cargo_val)
	print("     QA_W53_P6_LANDING_EV 胜局实得 %.0f（钱 %.0f + 货面值 %d）；对照 simulate_run 小艍开局一趟净赚 %d～%d" % [
		win_take, money_mid, cargo_val, TRADE_TRIP_FIFTH, TRADE_TRIP_BEST])
	_expect(win_take < float(TRADE_TRIP_FIFTH),
		"胜局实得 %.0f < 小艍开局第五好的一趟净赚 %d——赢一回也挣不过跑一趟寻常买卖" % [win_take, TRADE_TRIP_FIFTH])
	var ev_cap := float(TRADE_TRIP_BEST) * 0.2
	for prof in PROFILES:
		var rate := _rate_of(prof)
		var lost := int(round(float(LR.landing_party(int(prof["crew"]))) * LR.LOSE_LOSS_RATE))
		var ev := rate * win_take - (1.0 - rate) * float(lost * SAILOR_COST)
		print("     QA_W53_P6_LANDING_EV %s：胜率 %.3f・败折 %d 人（%d 钱）→ 期望净 %+.1f 钱（开局一趟的 %.1f%%）" % [
			str(prof["name"]), rate, lost, lost * SAILOR_COST, ev, ev / float(TRADE_TRIP_BEST) * 100.0])
		_expect(ev < ev_cap, "%s 期望净 %+.1f < 开局一趟净赚 %d 的两成（%.0f）——不成摇钱树" % [
			str(prof["name"]), ev, TRADE_TRIP_BEST, ev_cap])


# ── 十一、真走 SeaChart 落账 ──────────────────────────

## 摆一条福船（中）50 人：水粮记 0（舱位好数）、士气 60、武力 0（将领系数 1.0）、钱 1000、名声 0；
## grain > 0 时先往舱里装这么些米
func _settle_fleet(fleet: Node, gs: Node, grain := 0) -> void:
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "durability": 300.0,
		"max_durability": 300.0, "crew": 50, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	fleet.set("water", 0)
	fleet.set("food", 0)
	fleet.set("morale", 60)
	gs.set("money", 1000)
	gs.set("fame", 0)
	gs.set("martial", 0)
	if grain > 0:
		fleet.call("add_cargo", "grain", grain, 8.0)


## SeaChart 下船那一刻算的战力（与 _on_after_action_done 同一组现读：水手数、将领系数、士气系数）
func _fleet_raid_power(fleet: Node) -> float:
	return LR.raid_power(LR.landing_party(int(fleet.call("total_crew"))),
		float(fleet.call("captain_power")), float(fleet.call("morale_factor")))


## 头一个让这一战力赢（won = true）/ 输（won = false）的种子
func _seed_for(power: float, won: bool) -> int:
	for k in range(1, 4000):
		seed(k)
		if bool(LR.roll(power)["won"]) == won:
			return k
	return -1


## 按一次「收拾停当」：卡上只挂剿寨那一行、选 chosen。落账前 seed(k)——_on_after_action_done 里
## 剿寨那一掷之前不掷别的骰，SeaChart 里头一枚骰就是它
func _press(sc: Node, chosen: String, k: int) -> void:
	var choices := LR.choices_for("win", {"event": "pirate"}, "quanzhou")
	seed(k)
	sc.call("_on_after_action_done", {"landing": chosen}, choices, {})


func _sec_settle(fleet: Node, gs: Node) -> void:
	var sc := _chart()
	await _frames(3)
	# 收尾的 _after_combat 见 remaining_li ≤ 0 当是到港（到港换场景）：留一段航程，船又没在走，_sail_next_day 当即返回
	sc.set("remaining_li", 50.0)

	# ── 胜：同一个种子先在探针里掷一遍，预知钱数
	_settle_fleet(fleet, gs)
	var power := _fleet_raid_power(fleet)
	var kw := _seed_for(power, true)
	seed(kw)
	LR.roll(power)
	var want_money := int(round(randf_range(LR.WIN_LOOT_LO, LR.WIN_LOOT_HI)))
	_press(sc, "raid", kw)
	await _frames(1)
	var rep: Dictionary = sc.call("last_landing_report")
	_expect(bool(rep.get("won", false)), "胜（种子 %d、战力 %.1f）：读数记胜" % [kw, power])
	_expect(int(gs.get("money")) == 1000 + want_money, "胜：钱匣 1000 → %d（这一掷 %d）" % [int(gs.get("money")), want_money])
	_expect(int(gs.get("fame")) == LR.WIN_FAME, "胜：名声 0 → %d（走 add_fame）" % int(gs.get("fame")))
	_expect(int(fleet.get("morale")) == 60 + LR.WIN_MORALE, "胜：士气 60 → %d" % int(fleet.get("morale")))
	_expect(int(fleet.call("total_crew")) == 50, "胜：水手不动（%d）" % int(fleet.call("total_crew")))
	var g := int(fleet.call("cargo_qty", "grain"))
	var s := int(fleet.call("cargo_qty", "sea_salt"))
	var d := int(fleet.call("cargo_qty", "deer_hide"))
	_expect(g == 12 and s == 6 and d == 2, "胜：三样货真进舱（米 %d・盐 %d・鹿皮 %d）" % [g, s, d])
	var note := str(sc.get("_latest_note"))
	_expect(note.contains("寨子烧了") and note.contains("搜出 %d 钱" % want_money),
		"胜：札记写寨子烧了、搜出的钱数（「%s」）" % note)
	_expect(note.count("搬回舱里") == 1, "胜：「搬回舱里」只说一遍（%d 遍）" % note.count("搬回舱里"))
	_expect(note.contains("米粮 12 件") and note.contains("鹿皮 2 件") and note.contains("名声加 %d。" % LR.WIN_FAME),
		"胜：札记写货的件数与名声")
	_expect(not note.contains("留在岸上") and not note.contains("折了"), "胜：舱装得下，不写留在岸上、不写折人")

	# ── 胜、舱快满：福船（中）舱 800 料，先装 790 件米，剩 10 料——米再装 10 件，盐、鹿皮装不下
	_settle_fleet(fleet, gs, 790)
	power = _fleet_raid_power(fleet)
	kw = _seed_for(power, true)
	_press(sc, "raid", kw)
	await _frames(1)
	rep = sc.call("last_landing_report")
	var loaded: Dictionary = rep.get("loaded", {})
	_expect(LR.cargo_units(loaded) == 10 and int(loaded.get("grain", 0)) == 10, "舱快满：只装下米 10 件（%s）" % str(loaded))
	_expect(int(fleet.call("cargo_qty", "grain")) == 800 and int(fleet.call("cargo_qty", "deer_hide")) == 0,
		"舱快满：舱里米 790 → %d、鹿皮没进舱" % int(fleet.call("cargo_qty", "grain")))
	note = str(sc.get("_latest_note"))
	_expect(note.contains("米粮 10 件搬回舱里") and note.contains("舱里塞不下，10 件留在岸上。"),
		"舱快满：札记写装下的与留在岸上的件数（「%s」）" % note)

	# ── 败
	_settle_fleet(fleet, gs, 5)
	power = _fleet_raid_power(fleet)
	var kl := _seed_for(power, false)
	_press(sc, "raid", kl)
	await _frames(1)
	rep = sc.call("last_landing_report")
	var want_lost := int(round(float(LR.landing_party(50)) * LR.LOSE_LOSS_RATE))
	_expect(not bool(rep.get("won", true)), "败（种子 %d、战力 %.1f）：读数记败" % [kl, power])
	_expect(int(gs.get("money")) == 1000, "败：钱匣不动（%d）" % int(gs.get("money")))
	_expect(int(gs.get("fame")) == LR.LOSE_FAME, "败：名声 0 → %d" % int(gs.get("fame")))
	_expect(int(fleet.get("morale")) == 60 + LR.LOSE_MORALE, "败：士气 60 → %d" % int(fleet.get("morale")))
	_expect(int(fleet.call("total_crew")) == 50 - want_lost,
		"败：水手 50 → %d（折 %d）" % [int(fleet.call("total_crew")), want_lost])
	_expect(int(fleet.call("cargo_qty", "grain")) == 5 and int(fleet.call("cargo_qty", "deer_hide")) == 0, "败：舱货不动")
	note = str(sc.get("_latest_note"))
	_expect(note.contains("寨门没打开") and note.contains("折了 %d 人。" % want_lost) and note.contains("名声加 %d。" % LR.LOSE_FAME),
		"败：札记写寨门没打开、折了几人、名声（「%s」）" % note)
	_expect(not note.contains("搬回舱里") and not note.contains("一成半"), "败：不写搬货，折人只报人数")

	# ── 收队回船
	_settle_fleet(fleet, gs, 5)
	_press(sc, "hold", 1)
	await _frames(1)
	_expect(int(gs.get("money")) == 1000 and int(gs.get("fame")) == 0 and int(fleet.get("morale")) == 60
		and int(fleet.call("total_crew")) == 50 and int(fleet.call("cargo_qty", "grain")) == 5,
		"收队回船：钱 / 名声 / 士气 / 水手 / 舱货一样不动")
	note = str(sc.get("_latest_note"))
	_expect(note.contains("收队回船"), "收队回船：札记一句（「%s」）" % note)
	sc.queue_free()
	await _frames(2)
