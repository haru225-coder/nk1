extends SceneTree
## Lane ship2：捻缝改装探针——捻缝三等、花费、系数、存档兜底。
## 用法：godot --headless --path . -s res://tools/qa_w57_ship_probe.gd
## 输出末行 SHIP_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fleet: Node
var saveload: Node
var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	fleet = root.get_node_or_null("Fleet")
	saveload = root.get_node_or_null("SaveLoad")
	if fleet == null:
		push_error("autoload missing")
		quit(1)
		return

	# 1. 新船捻缝 1 等
	fleet.ships.clear()
	var ok: bool = fleet.add_ship("sampan", "探船")
	_expect(ok, "add_ship 成功")
	_expect(fleet.ships.size() == 1, "船队 1 艘")
	_expect(fleet.seam_level(0) == 1, "新船捻缝 1 等")
	_expect(fleet.is_seam_max(0) == false, "新船捻缝未满")

	# 2. 花费 > 0
	var c1: int = fleet.upgrade_cost(0, "seam")
	_expect(c1 > 0, "捻缝升级花费 %d > 0" % c1)

	# 3. 升级
	var up: bool = fleet.upgrade_seam(0)
	_expect(up, "upgrade_seam 成功")
	_expect(fleet.seam_level(0) == 2, "捻缝升至 2 等")

	# 4. 系数默认/升级
	var r0: float = fleet.seam_damage_reduction()
	_expect(r0 < 1.0 and r0 > 0.0, "捻缝系数 %.2f" % r0)

	# 5. 满级
	fleet.upgrade_seam(0)
	fleet.upgrade_seam(0)
	_expect(fleet.seam_level(0) == 3, "捻缝满 3 等")
	_expect(fleet.is_seam_max(0), "捻缝满级")
	_expect(fleet.upgrade_seam(0) == false, "满级再升 false")

	# 6. 存档兜底：缺 seam_level 补 1
	if saveload != null and saveload.has_method("_harden_fleet"):
		var raw := {"ships": [{"type": "sampan", "durability": 10.0, "max_durability": 10.0, "crew": 2, "cargo": {}}]}
		var hardened = saveload._harden_fleet(raw)
		var sh: Dictionary = (hardened as Dictionary).get("ships", [])[0]
		_expect(int(sh.get("seam_level", 0)) == 1, "缺 seam_level 兜底为 1")

	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("SHIP_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
