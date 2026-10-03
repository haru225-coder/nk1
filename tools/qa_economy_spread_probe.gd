extends SceneTree
## Lane ea：headless 探针——同港价差地板（Economy.PRICE_SPREAD_MIN）在真实 price_at_rate 上成立。
## verify_economy.py / simulate_run.py 只验 Python 镜像；这里直接调 GDScript 的 Economy，
## 扫 杂事 0..3 × 通事 0..3 × 职衔（光杆/都保）× 修埠（0/满）× 行情（地板/1.0/顶）× 全部（港, 货）。
## 用法：godot --headless --path . -s res://tools/qa_economy_spread_probe.gd
## 输出末行 EA_PROBE fails=N；N>0 时 exit 1。
## Lane ea2：加 `-- --dump-out <path>` 时先把生产报价逐格落盘，供 Python 镜像逐格对账：
##   python3 tools/verify_economy.py --prod-dump <path>

var eco: Node
var crew: Node
var gs: Node
var gm: Node
var fails := 0

## ea2 dump 的行情取点：两端 + 1.0 + 几处非整数（让 int(round) 的 .5 边界有机会露面）
const DUMP_RATES := [0.4, 0.515, 0.73, 0.815, 1.0, 1.045, 1.37, 1.625, 2.2]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	eco = root.get_node_or_null("Economy")
	crew = root.get_node_or_null("Crew")
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	if eco == null or crew == null or gs == null or gm == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()
	var saved_hired: Dictionary = crew.hired.duplicate(true)
	var saved_fame: int = gs.fame
	var saved_inv: Dictionary = eco.investments.duplicate(true)
	var saved_rates: Dictionary = eco.rates.duplicate(true)

	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--dump-out":
			_dump(args[i + 1])
	_bare_unchanged()
	_scan_floor()
	_round_trip()
	_crew_monotone()

	crew.hired = saved_hired
	gs.fame = saved_fame
	eco.investments = saved_inv
	eco.rates = saved_rates
	print("EA_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


## Crew.hired 只存名册 id、品级回查 crew.json（lane w23-a1 起）。原先这里塞整条 {id, role, level} 快照，
## w23-a1 之后 Crew.level_of 一律读成 0：杂事 / 通事各档实际全按光杆扫，地板、满编买卖、单调几条静默绿（lane w53-3）。
## 现按职与品级取名册里的真候选，摆完核一遍 level_of，摆不上即判红。
func _set_crew(z: int, t: int) -> void:
	var h := {}
	if z > 0:
		h["zashi"] = _cand("zashi", z)
	if t > 0:
		h["tongshi"] = _cand("tongshi", t)
	crew.hired = h
	if crew.level_of("zashi") != z or crew.level_of("tongshi") != t:
		_fail("职事没摆上：要杂事 %d 通事 %d，Crew.level_of 读出 %d / %d（hired 写法与 Crew 对不上）" % [
			z, t, crew.level_of("zashi"), crew.level_of("tongshi")])


## 名册里该职该品级的第一位候选 id；没有这一级给个查不到的名，交 _set_crew 判红
func _cand(role: String, level: int) -> String:
	for c in gm.crew_data.get("candidates", []):
		if str(c.get("role", "")) == role and int(c.get("level", 0)) == level:
			return str(c.get("id", ""))
	return "no_%s_%d" % [role, level]


func _max_fame() -> int:
	var top := 0
	for r in gs.title_ranks():
		top = maxi(top, int(r.get("min_fame", 0)))
	return top


func _ports() -> Array:
	var out := []
	for p in gm.ports_data.get("ports", []):
		var pid := str(p.get("id", ""))
		if pid != "" and not eco.goods_at(pid).is_empty():
			out.append(pid)
	return out


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


## 光杆（无职事、散商、未修埠）价格不因地板而变：地板只裁职事/职衔叠出来的倒挂
func _bare_unchanged() -> void:
	_set_crew(0, 0)
	gs.fame = 0
	eco.investments = {}
	var n := 0
	var bad := 0
	for pid in _ports():
		for gid in eco.goods_at(pid):
			var base := float(eco._good_def(gid).get("base_value", 0))
			var v: float = base * float(eco.ROLE_MOD.get(eco.get_role(pid, gid), 1.0)) * eco.get_rate(pid, gid)
			var want_b := int(round(v * (1.0 + eco._base_tariff(pid))))
			var want_s := int(round(v * (1.0 - eco.broker_fee)))
			n += 1
			if eco.buy_price(pid, gid) != want_b or eco.sell_price(pid, gid) != want_s:
				bad += 1
				_fail("光杆价被改动 %s/%s 买 %d(应 %d) 卖 %d(应 %d)" % [
					pid, gid, eco.buy_price(pid, gid), want_b, eco.sell_price(pid, gid), want_s])
	print("  %s 光杆价与无地板公式一致（%d 组，偏差 %d）" % ["✓" if bad == 0 else "✗", n, bad])


func _scan_floor() -> void:
	var inverted := 0
	var thin := 0
	var n := 0
	var worst := ""
	var worst_gain := 0.0
	var max_inv: int = eco.invest_max_level()
	for z in range(4):
		for t in range(4):
			_set_crew(z, t)
			for fame in [0, _max_fame()]:
				gs.fame = fame
				for inv in [0, max_inv]:
					for pid in _ports():
						eco.investments = {pid: inv} if inv > 0 else {}
						for gid in eco.goods_at(pid):
							if float(eco._good_def(gid).get("base_value", 0)) <= 0.0:
								continue
							for rate in [eco.RATE_MIN, 1.0, eco.RATE_MAX]:
								var b: int = eco.price_at_rate(pid, gid, rate, true)
								var s: int = eco.price_at_rate(pid, gid, rate, false)
								n += 1
								if s > b:
									inverted += 1
									var gain := float(s - b) / float(maxi(b, 1))
									if gain > worst_gain:
										worst_gain = gain
										worst = "%s/%s 杂事%d 通事%d 名声%d 修埠%d 行情%.2f 买 %d 卖 %d" % [
											pid, gid, z, t, fame, inv, rate, b, s]
								# 整数取整容 1 文（与 simulate_run 同一容差）
								if float(b) < float(s) * eco.PRICE_SPREAD_MIN - 1.0:
									thin += 1
	eco.investments = {}
	if inverted > 0:
		_fail("同港卖价高于买价 %d 组；最坏 %s（原地买卖每轮 +%.1f%%）" % [inverted, worst, worst_gain * 100.0])
	print("  %s 同港卖价不高于买价（%d 组，倒挂 %d）" % ["✓" if inverted == 0 else "✗", n, inverted])
	if thin > 0:
		_fail("同港买价 < 卖价 × %.2f − 1 共 %d 组" % [eco.PRICE_SPREAD_MIN, thin])
	print("  %s 同港买价 ≥ 卖价 × %.2f（容 1 文，越界 %d）" % ["✓" if thin == 0 else "✗", eco.PRICE_SPREAD_MIN, thin])


## 满编在博多原地买 10 立刻卖 10：走 estimate_* 与 apply_*_impact，与 Main._on_buy/_on_sell 同路
func _round_trip() -> void:
	_set_crew(3, 3)
	gs.fame = _max_fame()
	var worst := ""
	var bad := 0
	for gid in eco.goods_at("hakata"):
		if float(eco._good_def(gid).get("base_value", 0)) <= 0.0:
			continue
		var saved: Dictionary = eco.rates.duplicate(true)
		var cost: int = eco.estimate_buy_cost("hakata", gid, 10)
		eco.apply_buy_impact("hakata", gid, 10)
		var rev: int = eco.estimate_sell_revenue("hakata", gid, 10)
		eco.rates = saved
		if rev > cost:
			bad += 1
			worst = "%s 付 %d 得 %d（净 +%d）" % [gid, cost, rev, rev - cost]
	if bad > 0:
		_fail("博多满编原地买十卖十净赚 %d 种货；如 %s" % [bad, worst])
	print("  %s 博多满编原地买十卖十不赚钱（净赚 %d 种）" % ["✓" if bad == 0 else "✗", bad])


## 雇人不能反而更亏：泉州→博多青白瓷单件利润随职事等级不降（地板只裁倒挂，不罚雇人）
func _crew_monotone() -> void:
	gs.fame = 0
	var gid := "qingbai_porcelain"
	var prev := -999999
	var ladder := []
	var ok := true
	for zt in [[0, 0], [1, 1], [2, 2], [3, 3]]:
		_set_crew(zt[0], zt[1])
		var p: int = eco.price_at_rate("hakata", gid, 1.0, false) - eco.price_at_rate("quanzhou", gid, 1.0, true)
		ladder.append(p)
		if p < prev:
			ok = false
		prev = p
	if not ok:
		_fail("泉州→博多青白瓷利润随职事下降 %s" % str(ladder))
	print("  %s 泉州→博多青白瓷单件利润随职事不降 %s" % ["✓" if ok else "✗", str(ladder)])


## Lane ea2：生产报价逐格落盘。扫 杂事 0..3 × 通事 0..3 × 职衔（光杆/顶档）× 修埠（0/满）× DUMP_RATES × 全部（港, 货）。
## 每行：pid gid 杂事 通事 职衔档(0|顶=名册末位) 修埠 行情 买价 卖价 抽解基率；打印 EA2_MIRROR_DUMP rows=N。
func _dump(out_path: String) -> void:
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		_fail("dump 打不开 " + out_path)
		return
	var ranks: Array = gs.title_ranks()
	var top := ranks.size() - 1
	var max_inv: int = eco.invest_max_level()
	var rows := 0
	for z in range(4):
		for t in range(4):
			_set_crew(z, t)
			for rank in [0, top]:
				gs.fame = int(ranks[rank].get("min_fame", 0))
				for inv in [0, max_inv]:
					for pid in _ports():
						eco.investments = {pid: inv} if inv > 0 else {}
						for gid in eco.goods_at(pid):
							for rate in DUMP_RATES:
								f.store_line("%s\t%s\t%d\t%d\t%d\t%d\t%.3f\t%d\t%d\t%.4f" % [
									pid, gid, z, t, rank, inv, rate,
									eco.price_at_rate(pid, gid, rate, true),
									eco.price_at_rate(pid, gid, rate, false),
									eco._base_tariff(pid)])
								rows += 1
	f.close()
	eco.investments = {}
	print("EA2_MIRROR_DUMP rows=%d -> %s" % [rows, out_path])
