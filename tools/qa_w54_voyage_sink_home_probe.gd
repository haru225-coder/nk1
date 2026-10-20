extends SceneTree
## lane w54-voyage：沉船被渔船捞回这一程的起锚港——闯封锁没闯过去、折回途中再沉，也回起锚港，不进那座围城。
##   闯封锁到了港外撞上哨船，输了 / 逃了 / 掉头，SeaChart._run_seize 把起讫对调（origin_port 换成围城那港，从港外往回走）。
##   回程再沉（风涛、海寇），SeaChart._sink 的「……」原先写 GameState.last_port = origin_port——人被捞进闯不进去的围城
##   （兴化 1276 年冬被围：掉头回泉州的路上沉了，醒来人在兴化城里）。起锚港整程都在 GameState.last_port。
## 断言（固定种子让到港外那一掷撞上哨船；按真钮走：「掉头回航」「……」）：
##   R1 闯兴化撞上哨船、点「掉头回航」：起讫对调成兴化 → 泉州（前提，与 qa_w53_p5_blockade_probe 同一路）。
##   R2 折回途中风涛沉船（走 _sink，与 _sail_next_day 沉船那一路同一个函数）：点「……」后 last_port 是泉州；
##      换场后 Main.start_game 收了回港旗、港页排在泉州。
##   R3 折回途中海寇一仗全队沉了（_on_battle_result lose + sunk → _after_combat → _sink）：同样捞回泉州、港页是泉州。
##   R4 对照：寻常一程（泉州 → 福州）半路沉船，照旧捞回泉州；拦港那一仗当场全队沉了（不对调）也回泉州。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_sink_home_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_SINK_HOME cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const GRAIN := 150

var _gs: Node
var _gm: Node
var _cal: Node
var _voy: Node
var _fleet: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	_voy = root.get_node_or_null("Voyage")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _gm == null or _cal == null or _voy == null or _fleet == null:
		_expect(false, "autoload 不全")
		_report()
		return
	await _frames(2)
	await _r1_r2_storm_on_way_home()
	await _r3_battle_on_way_home()
	await _r4_controls()
	_report()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


## 白板一局：第四章、人在泉州、1276 年十一月初五（兴化被围）；一条福船（中）舱里 GRAIN 件米粮
func _stage(grain: int) -> Node:
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1276, "month": 11, "day": 5})
	var d: Dictionary = _fleet.call("ship_def", "fu_ship_medium")
	var cargo := {}
	if grain > 0:
		cargo["grain"] = {"qty": grain, "avg_cost": 8.0}
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": cargo, "durability": float(d.get("durability", 300)), "max_durability": float(d.get("durability", 300))}])
	_fleet.set("morale", 70)
	_fleet.set("water", 200)
	_fleet.set("food", 200)
	_fleet.set("at_sea", false)
	_gm.set("pending_battle", {})
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	return sc


## 船已到兴化港外（与 qa_w53_p5_blockade_probe 的 _at_port_mouth 同一摆法）
func _at_port_mouth(sc: Node, port: String) -> void:
	sc.call("_choose_run", port)
	sc.set("total_li", float(_voy.call("distance_li", "quanzhou", port)))
	sc.set("remaining_li", 0.0)
	sc.set("days_elapsed", 4)
	sc.set("sailing", true)
	sc.set("voyage_started", true)
	_fleet.set("at_sea", true)


## 头一发 blockade_patrol_met 撞上哨船的种子
func _seed_met() -> int:
	for k in range(1, 500):
		seed(k)
		if bool(_voy.call("blockade_patrol_met")):
			return k
	return -1


func _press(sc: Node, label: String) -> bool:
	for b in (sc.get("event_actions") as Node).get_children():
		if b is Button and not b.is_queued_for_deletion() and str((b as Button).text) == label:
			(b as Button).pressed.emit()
			return true
	return false


## 闯兴化、到港外撞上哨船、点「掉头回航」：起讫对调
func _yield_at_xinghua() -> Node:
	var sc := _stage(GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	seed(_seed_met())
	sc.call("_arrive")
	var title := str((sc.get("event_title") as Label).text)
	var pressed := _press(sc, "掉头回航（米粮扣下）")
	_expect(title.ends_with("哨船拦港") and pressed and str(sc.get("origin_port")) == "xinghua"
		and str(sc.get("selected_port")) == "quanzhou" and bool(sc.get("sailing")),
		"闯兴化撞上哨船（%s）、点「掉头回航」：起讫对调成兴化 → 泉州（起 %s、讫 %s）" % [
			title, str(sc.get("origin_port")), str(sc.get("selected_port"))])
	return sc


## 点「……」，读 last_port；换场后 Main.start_game 收了回港旗、按 last_port 排了港页，再读一遍它落在哪港
## （港页本身可能先演泉州节拍那一幕，current_scene_id 不一定是港 id，所以认 Main 排港页时写下的 last_port）
func _rescue(sc: Node) -> Array:
	var title := str((sc.get("event_title") as Label).text)
	var pressed := _press(sc, "……")
	var port := str(_gs.get("last_port"))
	await _frames(12)
	var landed := ""
	if current_scene != null and current_scene.has_method("load_scene") and not bool(_gs.call("has_flag", "return_to_port")):
		landed = str(_gs.get("last_port"))
	sc.queue_free()
	await _frames(2)
	return [title, pressed, port, landed]


func _r1_r2_storm_on_way_home() -> void:
	print("── R1 / R2 闯兴化掉头、折回途中风涛沉船")
	var sc: Node = await _yield_at_xinghua()
	# 回程风涛把船打沉：_sail_next_day 见耐久归零走 _sink(当日事件正文)，这里直调同一个函数
	sc.call("_sink", "浪头一个高过一个。")
	var r: Array = await _rescue(sc)
	_expect(str(r[0]) == "沉　没" and bool(r[1]), "回程沉船挂「沉　没」一面、点得到「……」（%s）" % str(r[0]))
	_expect(str(r[2]) == "quanzhou", "捞回起锚港泉州，不进围城兴化（last_port = %s）" % str(r[2]))
	_expect(str(r[3]) == "quanzhou", "换场后 Main 排的港页在泉州（落在 %s）" % str(r[3]))


func _r3_battle_on_way_home() -> void:
	print("── R3 闯兴化掉头、折回途中海寇一仗全队沉了")
	var sc: Node = await _yield_at_xinghua()
	(_fleet.get("ships")[0] as Dictionary)["durability"] = 0.0
	_gm.set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "pirate"}})
	sc.call("_on_battle_result", "lose", {"sunk": true, "player_damage": 300.0})
	var r: Array = await _rescue(sc)
	_expect(str(r[0]) == "沉　没" and str(r[2]) == "quanzhou" and str(r[3]) == "quanzhou",
		"海寇一仗沉了：%s、捞回泉州（last_port = %s，Main 港页落在 %s）" % [str(r[0]), str(r[2]), str(r[3])])


func _r4_controls() -> void:
	print("── R4 对照：寻常一程沉船、拦港当场沉船，都回泉州")
	var sc := _stage(0)
	await _frames(3)
	sc.set("_hand", PackedStringArray(["fuzhou"]))
	sc.set("selected_port", "fuzhou")
	sc.set("total_li", float(_voy.call("distance_li", "quanzhou", "fuzhou")))
	sc.set("remaining_li", 120.0)
	sc.set("days_elapsed", 3)
	sc.set("sailing", true)
	sc.set("voyage_started", true)
	_fleet.set("at_sea", true)
	sc.call("_sink", "")
	var r: Array = await _rescue(sc)
	_expect(str(r[2]) == "quanzhou" and str(r[3]) == "quanzhou",
		"泉州往福州半路沉船：捞回泉州（last_port = %s，Main 港页落在 %s）" % [str(r[2]), str(r[3])])
	sc = _stage(GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	(_fleet.get("ships")[0] as Dictionary)["durability"] = 0.0
	_gm.set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "blockade"}})
	sc.call("_on_battle_result", "lose", {"sunk": true, "player_damage": 300.0})
	var origin := str(sc.get("origin_port"))
	r = await _rescue(sc)
	_expect(origin == "quanzhou" and str(r[2]) == "quanzhou" and str(r[3]) == "quanzhou",
		"拦港那一仗当场全队沉了（不对调，起 %s）：捞回泉州（last_port = %s，Main 港页落在 %s）" % [origin, str(r[2]), str(r[3])])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_SINK_HOME cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
