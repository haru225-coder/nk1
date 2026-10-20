extends SceneTree
## Lane w54-saves：存档体检漏网的坏形状——load_game 报读成了、照常玩一会儿却 SCRIPT ERROR 的档。
## 来历：w54-saves 拿一份全分区好档逐叶改型 / 加坏条目（每叶 7 种型、每个容器 6 种坏条目，约一千二百档），
## 读得进的那些再逛港页与九处设施页、过 35 日、再记再读，数 SCRIPT ERROR；本探针把揪出来的那几型逐例钉住。
## 每例：好档（福州中局：两船带货、三职事、委办、传闻、修埠）改坏一处落进本卷正本，副抄放一份好档，判：
##   一、读到哪一份——坏例（_bad_cases，类型 / 取值坏）退副抄：体检判坏档，与 save_robust_probe 同口径，正本坏、副抄好 →
##       slot_source=bak、读进来的是副抄那一局；照读例（_tolerated_cases，读档本就补缺 / 清洗的那几格）读正本，另验读进来的是
##       补过 / 洗过的那一份；
##   二、读进来的那一局逛港页与九处设施页、舱里各货买一件卖一件、修船、过 35 日（跨月：发饷、结息、行情回归、月初战况）、
##       再记一卷再读回，全程本进程 SCRIPT ERROR 计数不涨。
## 修前这几例都是「正本照读、随后一串 SCRIPT ERROR」：坏例判一红在 slot_source=primary，各例判二红在错数。
## 另带 script_err_tally 的计数器自证；「运行中无 SCRIPT ERROR」改判各例之外的条数（各例的错数已逐例单判，不重复记红）。
## 只动存档位 542 / 543（w54-saves 自用段），不碰正式位 1..SLOTS。
## 用法：godot --headless --path . -s res://tools/qa_w54_saves_shape_probe.gd
## 末行 QA_W54_SAVES_SHAPE cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 542
const SLOT_AGAIN := 543
const PORT := "fuzhou"
const FACILITIES := ["_market", "_yamen", "_shipyard", "_tavern", "_inn", "_guild", "_exam", "_residence", "_temple"]
## 副抄那一局的钱数：读进来的是副抄，钱就是这个数
const BAK_MONEY := 7777

var _main: Node
var sl: Node
var gs: Node
var cal: Node
var eco: Node
var fleet: Node
var crew: Node
var gm: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _good: Dictionary = {}
## 各例走一圈里数到的 SCRIPT ERROR 合计（逐例已判过）；收尾那一判只认例外之外的
var _case_errs := 0


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时收尾不会被调到——回到这里就地判红收尾
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note(), "")
		_report()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	sl = root.get_node_or_null("SaveLoad")
	gs = root.get_node_or_null("GameState")
	cal = root.get_node_or_null("Calendar")
	eco = root.get_node_or_null("Economy")
	fleet = root.get_node_or_null("Fleet")
	crew = root.get_node_or_null("Crew")
	gm = root.get_node_or_null("GameManager")
	if sl == null or gs == null or cal == null or eco == null or fleet == null or crew == null or gm == null:
		push_error("autoload missing")
		quit(1)
		return
	_cleanup()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	_good = _make_good()

	# 对照：好档本身读得进、走一圈不出错（下面各例的「退副抄 / 0 错」才说明是那一处改坏的事）
	await _case("对照：好档原样", _good, "primary")

	for c in _bad_cases():
		await _case(str(c[0]), c[1], "bak")
	for c in _tolerated_cases():
		await _case(str(c[0]), c[1], "primary", c[2])

	_cleanup()
	_report()


## 例表：[题名, 改坏的整卷]。每例一处，余下与好档逐字同。
func _bad_cases() -> Array:
	var out: Array = []
	# economy.rates 港那一层给成非对象（字串 / 数 / 数组 / null）：体检只查货那一层是不是数，港那一层按空表放过，
	# Economy 取价 / 冲击 / 逐日回归都当字典取——修前每过一日 SCRIPT ERROR，牙行价目也取不出
	for bad in ["x", 3, [], null]:
		out.append(["economy.rates 港一层非对象（%s）" % JSON.stringify(bad), _patched(["economy", "rates", "fuzhou"], bad)])
		out.append(["economy.rates 多一港非对象（%s）" % JSON.stringify(bad), _patched(["economy", "rates", "zz_port"], bad)])
	# economy.investments 修埠等级为负：Economy.invest_cost 拿它当下标取价目——-1 悄悄取到顶等那一档的价，-7 即 SCRIPT ERROR（市舶司页一进就报）
	for bad in [-1, -7]:
		out.append(["economy.investments 修埠等级为负（%d）" % bad, _patched(["economy", "investments", PORT], bad)])
	return out


## 照读例：[题名, 改坏的整卷, 读后验一句 Callable（返回 [ok, 细节]）]。这几格读档本就清洗（与 met_ids / 勘见录同口径），
## 不判坏档；读进来的须是清洗过的那一份，且读档本身与随后走一圈都不出错。
func _tolerated_cases() -> Array:
	var out: Array = []
	return out


## 好档：福州中局，用真玩法摆（与 qa_w54_saves_systems_probe 的底子同一套），记一卷后读回文件当原件
func _make_good() -> Dictionary:
	seed(20261020)
	cal.from_dict({"year": 1262, "month": 6, "day": 14})
	eco.from_dict({"rates": {}, "tariff": 0.10, "broker": 0.05, "investments": {}})
	eco.set("_initialized", false)
	eco.initialize()
	fleet.from_dict({"ships": [], "water": 60, "food": 60, "morale": 70, "mutiny_cooldown": 0})
	fleet.add_ship("fu_ship_medium", "安济")
	fleet.add_ship("keel_boat", "通济")
	fleet.hire_to_min()
	fleet.add_cargo("tea", 12, 31.5, 0)
	fleet.add_cargo("grain", 30, 6.0, 1)
	crew.from_dict({"hired": {}, "unpaid_months": 0, "departed": {}})
	gs.from_dict({"money": 20000, "last_port": PORT, "chapter": 2, "fame": 20,
		"visited_ports": ["xinghua", "quanzhou", PORT]})
	for cid in ["wu_zhen", "chen_laodao", "huang_zhangfang"]:
		crew.hire(cid)
	gs.accept_contract(gs.contract_offer(PORT))
	gs.note_rumor("mingzhou", "tea", 1.45)
	gs.borrow(700)
	eco.invest(PORT)
	gs.record_discovery("beacon_ruin")
	gs.set_flag("guild_fuzhou")
	gs.record_trip("quanzhou", PORT)
	sl.save_game(SLOT, PORT)
	var good := _read_json(_path(SLOT))
	_cleanup()
	return good


## 好档深拷贝后在 keys 那一格放 v（末一键不存在就新添）
func _patched(keys: Array, v) -> Dictionary:
	var d: Dictionary = _good.duplicate(true)
	var cur = d
	for i in range(keys.size() - 1):
		cur = cur[keys[i]]
	cur[keys[keys.size() - 1]] = v
	return d


## 一例：正本放 data、副抄放好档（钱改成 BAK_MONEY 好认），判读到哪一份、走一圈错数；check 是照读例读后另验的一句
func _case(name: String, data: Dictionary, want_source: String, check: Callable = Callable()) -> void:
	_cleanup()
	var bak: Dictionary = _good.duplicate(true)
	bak["state"]["money"] = BAK_MONEY
	_write(_path(SLOT), data)
	_write(_path(SLOT) + ".bak", bak)
	var e0: int = _tally.lines.size()
	var source: String = sl.slot_source(SLOT)
	var loaded: bool = sl.load_game(SLOT)
	var want_money: int = BAK_MONEY if want_source == "bak" else int(data["state"]["money"])
	_expect(source == want_source and loaded and gs.money == want_money,
		"%s：读到%s" % [name, "副抄（正本判坏档）" if want_source == "bak" else "正本"],
		"slot_source=%s load=%s money=%d" % [source, str(loaded), gs.money])
	if loaded and check.is_valid():
		var r: Array = check.call()
		_expect(bool(r[0]), "%s：%s" % [name, str(r[1])], str(r[2]) if r.size() > 2 else "")
	if loaded:
		_main.load_scene(PORT)
		await _settle(1)
		for suf in FACILITIES:
			_main.load_scene(PORT + str(suf))
			await _settle(1)
		_main.load_scene(PORT)
		# 舱里各货买一件、卖一件（买进摊均价、卖出扣数是货舱两格的直取处），全队修船
		for i in fleet.ships.size():
			for gid in ((fleet.ships[i] as Dictionary).get("cargo", {}) as Dictionary).keys():
				fleet.add_cargo(str(gid), 1, 10.0, i)
				fleet.remove_cargo(str(gid), 1, i)
		fleet.repair_all()
		gm.advance_days(35)
		_main.load_scene(PORT)
		await _settle(1)
		sl.save_game(SLOT_AGAIN, PORT)
		sl.load_game(SLOT_AGAIN)
		_main.load_scene(PORT)
		await _settle(1)
	var n: int = _tally.lines.size() - e0
	_case_errs += n
	_expect(n == 0, "%s：读进来逛港页与九处设施、买卖修船、过 35 日、再记再读，SCRIPT ERROR 0 条" % name,
		"%d 条，首条：%s" % [n, str(_tally.lines[e0]) if n > 0 else ""])


func _report() -> void:
	_reported = true
	# 计数器自证照判；「运行中无 SCRIPT ERROR」那一判改判例外之外的条数——各例走一圈里的错已逐例判红，不重复记
	var verdicts: Array = _tally.verdicts()
	_expect(verdicts[0][0], verdicts[0][1], "")
	var outside: int = _tally.lines.size() - _case_errs
	_expect(outside == 0, "各例之外（摆好档、挂 Main、收尾）无 SCRIPT ERROR（%d 条）" % outside, "")
	print("QA_W54_SAVES_SHAPE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail if not ok else ""])
	if not ok:
		fails += 1


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _path(slot: int) -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % slot


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _cleanup() -> void:
	for slot in [SLOT, SLOT_AGAIN]:
		for suffix in ["", ".bak", ".tmp", ".v1", ".v2", ".v3"]:
			if FileAccess.file_exists(_path(slot) + suffix):
				DirAccess.remove_absolute(_path(slot) + suffix)
