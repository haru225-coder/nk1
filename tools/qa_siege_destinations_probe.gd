extends SceneTree
## V0928-1「被围港被开成委办目的地」复现探针（lane w36-k2 · 拍板清单 2026-09-28 §八之四 P8）。
## 摆场：按章解锁（chapter 6 全开）× 战况档（Calendar 走到数据行月份，Economy.war_status 现读）直调
## GameState._contract_destinations(port, good)、contract_offer(port) 两份真输出，断言「被围港不在出队」。
## 态 A：被围港（兴化 1276-11 / 1277-09，福州 1276-10，广州 1276-11——数据行 war 表现表）不掺进任何一份
##   出队目的地，委办报价的目的亦不落被围港——现网 _contract_destinations 不排被围港，报价优选针路已知池
##   （数据行 connections 相连即熟路，Voyage.is_known_route 现读）更易撞中，此格为设计内红
##   （归于 GATES.md §三 lane 档附注；红 = 复现出 §八之四 P8 指的缺陷，不是探针没做实）；
## 态 B：未被围月（1275-03）诸港互开目的地——泉州发香药兴化上队、泉州委办报价非空——反向基，
##   防探针写死「永假」。另有态 C 变基：香药不受任一被围港牵连，切面任何月都须全绿。
## 另附 192 月窗扫描：逐月逐港逐代表货直调 _contract_destinations 真输出，记被围港进队行（供拍板摘录）。
## 变异对照（M1）：附加参 `--mutate-siege-always` 把「被围」判值倒成恒真（只动本探针读口，不改游戏源码），
##   态 A 诸案与态 B 必红——判据防断言提前为真 / 读口作废。
## 用法：godot --headless --path . -s res://tools/qa_siege_destinations_probe.gd [-- --mutate-siege-always]

## w53-11（二轮）：此前本支对 SCRIPT ERROR 只有「末行 QA_SIEGE_DEST_END 缺 = 中断」一道人眼兜——子函数里出的错
## 照样跑到底、印末行（态 A 设计内红一盖，红因换了也看不出）；_run 自己出错则 quit 不执行、空转到超时。
## 现接共用件 tools/script_err_tally.gd：本进程脚本错另立 S 档计红（态 A / B / C 判据不动），_run_guarded 包一层
## 兜中止形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 代表货六种，产地 / 收货港分布拉开（茶走南洋东洋、香药回福建路，生丝销日本广州路）
const REPORT_GOODS := ["fujian_porcelain", "raw_silk", "tea", "sea_salt", "aromatic_medicine", "silk_fabric"]
## 被围档面（与数据行 war 表逐一对：兴化两围、福州 1276-10、广州 1276-11）
const SIEGE_CASES := [
	{"ym": [1276, 11], "port": "xinghua"},
	{"ym": [1277, 9], "port": "xinghua"},
	{"ym": [1276, 10], "port": "fuzhou"},
	{"ym": [1276, 11], "port": "guangzhou"},
]

var _fails_a: Array = []
var _fails_b: Array = []
var _fails_c: Array = []
var _a_lines := 0
var _ok := 0
var _mutate_siege_always := false
## 本进程 SCRIPT ERROR 另立 S 档（w53-11）：与态 A / B / C 分账——A 档设计内红判据不动
var _fails_s: Array = []
var _hits := 0
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
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note(), _fails_s)
		_report(false)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--mutate-siege-always":
			_mutate_siege_always = true
	print("QA_SIEGE_DEST_BEGIN mutate=%s" % _mutate_siege_always)
	var gs: Node = root.get_node("/root/GameState")
	var eco: Node = root.get_node("/root/Economy")
	var cal: Node = root.get_node("/root/Calendar")
	var gm: Node = root.get_node("/root/GameManager")

	_stage(gs, cal)

	# 口径摘录（V0928-1 机械前置①：现态口径 / 排除条件逐字记档，供 §三 小节与仓外 QA 档引用）
	print("QA_SIEGE_DEST_SCOPE _contract_destinations 排除口径：同港 / depth<=0 / 当地不收货（role!=consumer）/ 此地不做这货（!is_traded）；不排被围港")
	print("QA_SIEGE_DEST_SCOPE contract_offer 优选池：数据行 connections 相连即熟路（Voyage.is_known_route 现读），known 非空则只抡 known")

	# 192 月窗扫描：逐月逐港逐代表货直调真输出，记被围港进队行（摘录档）
	var lines_shown := 0
	cal.from_dict({"year": 1276, "month": 1, "day": 1})
	for i in range(192):
		var ctx := "%04d-%02d" % [cal.year, cal.month]
		for p in gm.unlocked_ports():
			var pid: String = String(p.get("id", ""))
			if int(p.get("depth", 0)) <= 0:
				continue
			for good_id in REPORT_GOODS:
				if not eco.is_traded(pid, good_id):
					continue
				var dests: Array = gs._contract_destinations(pid, good_id)
				for d in dests:
					if _besieged(String(d)):
						print("QA_SIEGE_DEST_HIT %s %s 发 %s → %s" % [ctx, _pname(gm, pid), _gname(gm, good_id), _pname(gm, String(d))])
						lines_shown += 1
		cal.advance_days(28)
	if lines_shown == 0:
		print("QA_SIEGE_DEST_HIT （无）")
	_stage(gs, cal)

	# 态 A：被围档面四案 —— 出队不掺该当月被围港，报价目的亦不落该被围港
	for sc in SIEGE_CASES:
		var ym: Array = sc["ym"]
		var besieged_port: String = String(sc["port"])
		cal.from_dict({"year": int(ym[0]), "month": int(ym[1]), "day": 1})
		var ctx := "%04d-%02d" % [cal.year, cal.month]
		_expect_a(_besieged(besieged_port), "%s %s 战况为「besieged」" % [ctx, _pname(gm, besieged_port)])
		for p in gm.unlocked_ports():
			var pid: String = String(p.get("id", ""))
			if int(p.get("depth", 0)) <= 0:
				continue
			for good_id in REPORT_GOODS:
				if not eco.is_traded(pid, good_id):
					continue
				var dests: Array = gs._contract_destinations(pid, good_id)
				_expect_a(not dests.has(besieged_port),
					"%s %s 发 %s 的出队不掺被围港 %s" % [ctx, _pname(gm, pid), _gname(gm, good_id), _pname(gm, besieged_port)])
		for p in gm.unlocked_ports():
			var pid: String = String(p.get("id", ""))
			if int(p.get("depth", 0)) <= 0 or pid == besieged_port or _besieged(pid) or not _has_offer_candidate(eco, gm, pid):
				continue
			gs.contract = {}
			var offer: Dictionary = gs.contract_offer(pid)
			if not offer.is_empty():
				_expect_a(String(offer.get("dest", "")) != besieged_port,
					"%s %s 报价的目的不为被围港 %s（实为 %s）" % [ctx, _pname(gm, pid), _pname(gm, besieged_port), _pname(gm, String(offer.get("dest", "")))])
	_stage(gs, cal)
	print("QA_SIEGE_DEST_A fails=%d" % _fails_a.size())

	# 态 B：未被围月 —— 出队互掺、报价非空，反向基
	cal.from_dict({"year": 1275, "month": 3, "day": 1})
	_expect_b(not _besieged("xinghua"), "1275-03 兴化未在围")
	_expect_b(not _besieged("guangzhou"), "1275-03 广州未在围")
	var dests_b: Array = gs._contract_destinations("guangzhou", "aromatic_medicine")
	_expect_b(not dests_b.is_empty(), "1275-03 广州发香药出队非空（%s）" % _pnames(gm, dests_b))
	_expect_b(dests_b.has("xinghua"), "1275-03 广州发香药出队含兴化（未被围月可开目的地）")
	gs.contract = {}
	var offer_b: Dictionary = gs.contract_offer("quanzhou")
	_expect_b(not offer_b.is_empty(), "1275-03 泉州委办报价非空（目的 %s）" % _pname(gm, String(offer_b.get("dest", ""))))
	_stage(gs, cal)
	cal.from_dict({"year": 1275, "month": 3, "day": 1})
	var dests_b2: Array = gs._contract_destinations("quanzhou", "tea")
	_expect_b(not dests_b2.is_empty(), "1275-03 泉州发茶出队非空（%s）" % _pnames(gm, dests_b2))
	_stage(gs, cal)
	print("QA_SIEGE_DEST_B fails=%d" % _fails_b.size())

	# 态 C：香药切面不受任一被围港牵连，任何月都须全绿（探针自净面）
	for ym2 in [[1276, 11], [1276, 10], [1277, 9], [1275, 3]]:
		cal.from_dict({"year": int(ym2[0]), "month": int(ym2[1]), "day": 1})
		var ctx2 := "%04d-%02d" % [cal.year, cal.month]
		var dests_c: Array = gs._contract_destinations("guangzhou", "aromatic_medicine")
		_expect_c(dests_c.has("xinghua"), "%s 广州发香药出队含兴化（香药切面不受围牵连）" % ctx2)
		_expect_c(dests_c.has("fuzhou"), "%s 广州发香药出队含福州（香药切面不受围牵连）" % ctx2)
	_stage(gs, cal)
	print("QA_SIEGE_DEST_C fails=%d" % _fails_c.size())

	_hits = lines_shown
	_report(true)


## 收尾（w53-11 二轮从 _run 尾挪出；_run_guarded 包装层判中止时也走这里）：本进程 SCRIPT ERROR 两判记 S 档、
## 计入总 fails。QA_SIEGE_DEST_END 仍只在 _run 跑到底时印——它是「跑到底」的唯一凭证；主流程被脚本错
## 掐断的（headless -s 下 quit 不再执行、进程本会空转）由包装层判红退 1、不印末行。
func _report(ran_to_end: bool) -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], _fails_s)
	print("QA_SIEGE_DEST_S fails=%d" % _fails_s.size())
	var fails := _fails_a.size() + _fails_b.size() + _fails_c.size() + _fails_s.size()
	print("SIEGE_DEST hits=%d ok=%d fails=%d" % [_hits, _ok, fails])
	print("结果：%s" % ("全部通过" if fails == 0 else "%d 项未通过" % fails))
	if ran_to_end:
		print("QA_SIEGE_DEST_END")
	quit(0 if fails == 0 else 1)


func _besieged(port_id: String) -> bool:
	if _mutate_siege_always and _a_lines_bump() >= 0:
		return true
	return String(root.get_node("/root/Economy").war_status(port_id)) == "besieged"


## 态 A 读口被命中的计数（上报行另印，供「判值路径断没断」对账）
func _a_lines_bump() -> int:
	_a_lines += 1
	return _a_lines


## 该港当月有没有可报价的货（基价 / 体积 / 非禁售 / 本地不收 / 有出队——contract_offer 的同套前置，
## 只用来跳过必然报价为空的港，不改报价本身）
func _has_offer_candidate(eco: Node, gm: Node, pid: String) -> bool:
	for gid in eco.goods_at(pid):
		var g: Dictionary = gm.get_good_by_id(str(gid))
		if g.is_empty() or not g.get("tradable", false) or g.get("contraband", false):
			continue
		if float(g.get("base_value", 0)) < 15 or float(g.get("bulk", 0)) <= 0.0:
			continue
		if String(eco.get_role(pid, str(gid))) == "consumer":
			continue
		return true
	return false


func _pname(gm: Node, port_id: String) -> String:
	if port_id == "":
		return "（空）"
	return String(gm.get_port_name(port_id))


func _gname(gm: Node, good_id: String) -> String:
	var g: Dictionary = gm.get_good_by_id(good_id)
	return String(g.get("name", good_id))


func _pnames(gm: Node, ids: Array) -> String:
	var out: Array = []
	for pid in ids:
		out.append(_pname(gm, String(pid)))
	return ",".join(out)


func _stage(gs: Node, cal: Node) -> void:
	gs.from_dict({})
	gs.chapter = 6
	gs.identity = "scholar"
	gs.last_port = "quanzhou"
	gs.contract = {}
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _expect_a(ok: bool, what: String) -> void:
	_expect(ok, what, _fails_a)


func _expect_b(ok: bool, what: String) -> void:
	_expect(ok, what, _fails_b)


func _expect_c(ok: bool, what: String) -> void:
	_expect(ok, what, _fails_c)


func _expect(ok: bool, what: String, bucket: Array) -> void:
	if ok:
		_ok += 1
	else:
		bucket.append(what)
		print("  ✗ " + what)
