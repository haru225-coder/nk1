extends SceneTree
## lane w54-siege：劫粮道（守城外援，开关 siege_relief）船上战力连押粮兵最少的那一档都不到，就不给劫。
## 劫一次 = SiegeMelee.raid：我方战力（船上人手 × 将领系数 × 船上士气系数）对押粮兵一枚骰 RAID_LO～RAID_HI（40～400），
## 战力不低于骰才算得手。修前只拦「人手不够开不出去」，战力不到 40 照样给按：开局小艍六人（武略 50、士气 70）战力约 6.6，
## 一枚骰也赢不了，按下去必败——白过四日、耗四日水粮、城中士气减 6；船屋页那一节只写「船上 6 人，劫得手…；失手…」，看不出必败。
## 断言：
##   A 必败的三档——开局小艍；中福船 39 人、武略 0、船上士气满（战力 39）；中福船 50 人、武略 0、船上士气 0（人比 40 多、战力 30）：
##     _siege_raid_block 给一句「打不过押粮的兵船」；直调 _siege_relief_raid 不动账（城中士气、日子、水粮、raid 记号）；
##     船屋页劫粮道一节写这句、不挂「出海劫粮道」钮；船屋门不写「多则四日」。
##   B 界上：中福船 41 人、武略 0、船上士气满（战力 41）照旧给劫——缘由空、钮在，直调照 SiegeMelee.clash(41, 40, 400) 同种子同骰、过四日。
##   C 照旧：两条大福船各 75 人（qa_w53_p5_siege_probe 那一档）劫粮道照旧开，船屋门「少则当日・多则四日」。
## 用法：godot --headless --path . -s res://tools/qa_w54_siege_raid_probe.gd（经门锁跑）
## 末行 W54_SIEGE_RAID cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const SiegeMelee := preload("res://scripts/combat/SiegeMelee.gd")
const NEEDLE := "打不过押粮的兵船"

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
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


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		_report()
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(_main)
	for i in 10:
		await process_frame
	Switches.reset()
	print("── A 必败的三档：不给劫")
	await _doomed("开局小艍六人（武略 50、船上士气 70）", "sampan", 6, 50, 70)
	await _doomed("中福船 39 人（武略 0、船上士气满）", "fu_ship_medium", 39, 0, 100)
	await _doomed("中福船 50 人（武略 0、船上士气 0）", "fu_ship_medium", 50, 0, 0)
	print("── B 界上：战力 41 照旧给劫")
	await _edge()
	print("── C 照旧：两条大福船各 75 人")
	await _big()
	_report()


func _report() -> void:
	_reported = true
	Switches.reset()
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SIEGE_RAID cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 士人线改名、景炎元年冬月初三进兴化城：城防开着（士气 55、第一阵未打），水粮各 400；船队按 ships 摆（[船型, 人手]…）、
## 武略 martial、船上士气 morale
func _stage(ships: Array, martial: int, morale: int) -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main.set("_chapter_host", null)
		(host as Node).queue_free()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_gs.set_flag("renamed_wenlong")
	_gs.identity = "scholar"
	_gs.money = 20000
	_gs.fame = 30
	_gs.martial = martial
	_gs.last_port = "xinghua"
	_cal.from_dict({"year": 1276, "month": 11, "day": 3})
	root.get_node("/root/Crew").from_dict({})
	_fleet.ships = []
	for s in ships:
		_fleet.add_ship(str(s[0]), "试%d" % _fleet.ships.size())
		_fleet.ships[_fleet.ships.size() - 1]["crew"] = int(s[1])
	_fleet.water = 400
	_fleet.food = 400
	_fleet.morale = morale
	_main.load_scene("xinghua")
	await process_frame


func _power() -> float:
	return SiegeMelee.raid_power(_fleet.total_crew(), _fleet.captain_power(), _fleet.morale_factor())


## 船屋页里劫粮道那一节：[说明句, 「出海劫粮道」钮在不在]
func _wall_page() -> Array:
	_main._on_siege_card("siege_wall")
	await process_frame
	var info := ""
	var has_btn := false
	var after_head := false
	for c in _main.choices_container.get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		if c is Label and (c as Label).text == "── 出海劫粮道 ──":
			after_head = true
			continue
		if after_head and c is Label and info == "":
			info = (c as Label).text
		if c is Button and str((c as Button).text).begins_with("出海劫粮道"):
			has_btn = true
	_main.load_scene("xinghua")
	await process_frame
	return [info, has_btn]


## 船屋门的副题第二行（耗日）
func _wall_door_note() -> String:
	return str(_main._siege_door_note("siege_wall"))


func _doomed(label: String, ship_type: String, crew: int, martial: int, morale: int) -> void:
	await _stage([[ship_type, crew]], martial, morale)
	var power := _power()
	var block := str(_main._siege_raid_block())
	_expect(power < SiegeMelee.RAID_LO and block.find(NEEDLE) >= 0,
		"%s：战力 %.1f < 押粮兵下限 %.0f，劫不劫得成那一句给「%s」（实读「%s」）" % [label, power, SiegeMelee.RAID_LO, NEEDLE, block])
	# 页与门先看（直调会动账，放最后）
	var page: Array = await _wall_page()
	_expect(str(page[0]).find(NEEDLE) >= 0 and not bool(page[1]),
		"%s：船屋页劫粮道一节写缘由、不挂钮（说明「%s」、钮 %s）" % [label, str(page[0]), str(page[1])])
	var note := _wall_door_note()
	_expect(note.find("四日") < 0, "%s：船屋门不写「多则四日」（实读「%s」）" % [label, note])
	var day0: int = _cal.absolute_day()
	var m0: int = _gs.siege_get("morale")
	var w0: int = _fleet.water
	seed(7100 + crew)
	var r: Dictionary = _main._siege_relief_raid()
	_expect(r.is_empty() and _cal.absolute_day() == day0 and _gs.siege_get("morale") == m0 and _fleet.water == w0
			and str(_gs.siege.get("raid", "")) == "",
		"%s：直调劫粮道不动账（回 %s、过了 %d 日、城中士气 %d → %d、水 %d → %d、记号「%s」）" % [
			label, str(r), _cal.absolute_day() - day0, m0, _gs.siege_get("morale"), w0, _fleet.water, str(_gs.siege.get("raid", ""))])


func _edge() -> void:
	await _stage([["fu_ship_medium", 41]], 0, 100)
	var power := _power()
	var block := str(_main._siege_raid_block())
	var page: Array = await _wall_page()
	_expect(power >= SiegeMelee.RAID_LO and block == "" and bool(page[1]) and _wall_door_note().find("多则四日") >= 0,
		"中福船 41 人（武略 0、船上士气满）：战力 %.1f ≥ %.0f，缘由空（「%s」）、钮在 %s、门「%s」" % [
			power, SiegeMelee.RAID_LO, block, str(page[1]), _wall_door_note()])
	var day0: int = _cal.absolute_day()
	seed(7300)
	var r: Dictionary = _main._siege_relief_raid()
	seed(7300)
	var want: Dictionary = SiegeMelee.clash(power, SiegeMelee.RAID_LO, SiegeMelee.RAID_HI, 1.0)
	_expect(not r.is_empty() and float(r.get("enemy", -1.0)) == float(want["enemy"]) and bool(r.get("won", true)) == bool(want["won"])
			and _cal.absolute_day() == day0 + 4,
		"战力 41 照旧劫：骰子同 SiegeMelee.clash(41, 40, 400) 同种子（%s / 应 %s）、过了 %d 日" % [str(r), str(want), _cal.absolute_day() - day0])


func _big() -> void:
	await _stage([["fu_ship_large", 75], ["fu_ship_large", 75]], 50, 80)
	var block := str(_main._siege_raid_block())
	var page: Array = await _wall_page()
	_expect(block == "" and bool(page[1]) and _wall_door_note() == "少则当日・多则四日",
		"两条大福船各 75 人：战力 %.1f，劫粮道照旧开（缘由「%s」、钮 %s、门「%s」）" % [_power(), block, str(page[1]), _wall_door_note()])
