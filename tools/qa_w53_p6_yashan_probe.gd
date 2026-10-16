extends SceneTree
## lane-w53-p6-yashan 崖山突围战专项探针（战斗系统方案 §七「崖山突围」、§八「章节与结局」，一条一节、回退即红）：
##   一、崖山卡第三扇门（开关 yashan_breakout）：开着时崖山页多一枚「上船同去」，关掉逐字回旧（只有原来那两枚）。
##   二、这一场的海况取港湾那一档（data/combat_sea_state.json waters.id = "harbor"）：水域港湾、天气雾、风力 60、
##       风向往南吹（来向正北，玩家的出路在北边）——待判据读 pending_battle.sea_state 与 SeaState 的当场读数。
##   三、火船摆下（开关 yashan_fire_ship）：开时顺风摆几艘火船、名字不带 PirateShip_ 前缀（士气簿 / 敌全灭 /
##       追兵 / 战果列都按那个前缀认敌船，火船不是敌人）；关掉这一场只剩元军船阵。
##       同屏船数（元军 + 火船）不超 8；火船不进士气簿、不算敌全灭的数。
##   四、碰上就点火（复用三期 FloodFire）：把一艘火船挪到旗舰舷边——旗舰篷帆先着（rig 火势 > 0）、
##       记一记撞伤（船体掉）；火船自己烧起来（本船四处火势 > 0）、碰过的不再点第二回（fire_spent）。
##   五、冲出 / 没冲出两式（YashanBattle.broke_out）：win / flee 脱战 / disengaged 两散都算冲出；
##       lose（沉 / 跳帮 / 我方降幡）算没冲出。两式只换结局里「船活没活」那一句，其余逐字相同。
##   六、收战那一拍把结果写进两枚旗（yashan_breakout_done / yashan_broke_out）：真起一场崖山港湾战、
##       按收战路径走一遍，旗与判词对得上；寻常海战一个字不写。
##   七、关态：yashan_breakout 关 = 崖山页那扇门根本不挂。
## 用法：godot --headless --path . -s res://tools/qa_w53_p6_yashan_probe.gd
## 判词：QA_W53_P6_YASHAN cases=N fails=M；fails>0 退 1。本进程有 SCRIPT ERROR 即红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CS := preload("res://scripts/combat/CombatSwitches.gd")

const TAG := "QA_W53_P6_YASHAN"

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false
var _main: Node = null
var _gs: Node
var _cal: Node
var _fleet: Node
var _gm: Node


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


## 包装层：_run 自己的代码行出 SCRIPT ERROR 时 GDScript 只中止这一个函数、quit() 再也不执行，
## -s 主循环空转到 timeout（rc=124 被当假红）。被包一层后照样收尾判红（见 script_err_tally 头注）。
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	var keep := _snapshot()

	print("== 一、崖山卡第三扇门（开关 yashan_breakout）")
	await _sec_card_door()
	print("== 二、这一场的海况取港湾那一档")
	await _sec_sea_state()
	print("== 三、火船摆下")
	await _sec_fire_ships()
	print("== 四、碰上就点火")
	await _sec_ignite()
	print("== 五、冲出 / 没冲出两式")
	_sec_two_endings()
	print("== 六、收战写两枚旗")
	await _sec_flags()
	print("== 七、关态")
	await _sec_off()
	print("== 八、借过船的档给元军多留位子")
	_sec_enemy_count_by_known()

	_restore(keep)
	await process_frame
	_report()


func _report() -> void:
	_reported = true
	if _tally != null:
		for v in _tally.verdicts():
			_expect(bool(v[0]), str(v[1]))
	if fails == 0:
		print("%s cases=%d fails=0" % [TAG, cases])
		quit(0)
		return
	print("%s cases=%d fails=%d" % [TAG, cases, fails])
	quit(1)


func _snapshot() -> Dictionary:
	return {"ships": (_fleet.get("ships") as Array).duplicate(true),
		"morale": _fleet.get("morale"), "money": _gs.get("money"), "fame": _gs.get("fame"),
		"flags": (_gs.get("flags") as Dictionary).duplicate(true),
		"cal": _cal.to_dict(), "pb": (_gm.get("pending_battle") as Dictionary).duplicate(true),
		"scene": _main.current_scene_id if _main != null else ""}


func _restore(k: Dictionary) -> void:
	_fleet.set("ships", k["ships"])
	_fleet.set("morale", k["morale"])
	_gs.set("money", k["money"])
	_gs.set("fame", k["fame"])
	_gs.set("flags", k["flags"])
	_cal.from_dict(k["cal"])
	_gm.set("pending_battle", k["pb"])
	CS.reset()
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		_main = null


# ══ 一、崖山卡第三扇门 ═══════════════════════════════════════════

## 崖山页（_on_yashan）上有没有「上船同去」这一枚；开关关掉须逐字回旧（只有原来那两枚）
func _sec_card_door() -> void:
	await _open_yashan_page()
	var on_doors := _choice_texts()
	_expect(_has_text(on_doors, "上船同去"), "开关开：崖山页有「上船同去」（现有的 %d 扇门 %s）" % [on_doors.size(), str(on_doors)])
	_expect(on_doors.size() == 3,
		"开关开：崖山页三扇门（交付 / 上船同去 / 不上前），实际 %d 扇" % on_doors.size())
	_expect(_has_text(on_doors, "把粮与硫黄交上去"), "开关开：原来那扇「把粮与硫黄交上去」照旧在")
	_expect(_has_text(on_doors, "不上前"), "开关开：原来那扇「不上前」照旧在")
	await _close_yashan_page()

	CS.set_on("yashan_breakout", false)
	await _open_yashan_page()
	var off_doors := _choice_texts()
	_expect(not _has_text(off_doors, "上船同去"), "开关关：崖山页没有「上船同去」（%d 扇门）" % off_doors.size())
	_expect(off_doors.size() == 2, "开关关：逐字回旧，只有原来那两扇门（实际 %d 扇）" % off_doors.size())
	await _close_yashan_page()
	CS.reset()


## 打开崖山页（真起 Main、走广州岸上的崖山卡那条路：先让卡挂上，再点进去）
func _open_yashan_page() -> void:
	_gs.set("identity", "merchant")
	_gs.set("ended", "")
	_cal.from_dict({"year": 1279, "month": 2, "day": 1})
	_gs.set("last_port", "guangzhou")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for _i in 3:
		await process_frame
	_main.call("load_scene", "guangzhou")
	await process_frame
	_main.call("_on_yashan")
	await process_frame


func _close_yashan_page() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		_main = null
	await process_frame


func _choice_texts() -> Array:
	var out: Array = []
	if _main == null or not is_instance_valid(_main):
		return out
	var box: Node = _main.get("choices_container")
	if box == null:
		return out
	for c in box.get_children():
		if c is Button:
			out.append(str((c as Button).text))
	return out


static func _has_text(list: Array, needle: String) -> bool:
	for t in list:
		if str(t).find(needle) >= 0:
			return true
	return false


# ══ 二、这一场的海况取港湾那一档 ═══════════════════════════════

## 待判据：setup 交出去的 pending_battle.sea_state 与港湾那一档的字段逐项对上；
## 再真起一场（WorldMap）看 SeaState 的当场读数（风向往南吹、风力 60、水域认成港湾）
func _sec_sea_state() -> void:
	var pb: Dictionary = YashanBattle.setup(300.0, false)
	var sea = pb.get("sea_state", {})
	_expect(sea is Dictionary, "pending_battle 带 sea_state（%s）" % str(sea))
	var d: Dictionary = sea if sea is Dictionary else {}
	_expect(str(d.get("waters", "")) == "harbor", "水域取港湾那一档（waters=%s）" % str(d.get("waters", "")))
	_expect(str(d.get("weather", "")) == "fog", "天气取雾（weather=%s）" % str(d.get("weather", "")))
	_expect(is_equal_approx(float(d.get("wind_strength", 0.0)), YashanBattle.WIND_STRENGTH),
		"风力按港湾的软风（wind_strength=%s，应值 %s）" % [str(d.get("wind_strength", "")), str(YashanBattle.WIND_STRENGTH)])
	_expect(is_equal_approx(float(d.get("wind_bearing", -1.0)), YashanBattle.WIND_TOWARD_DEG),
		"风向往南吹（wind_bearing=%s，应值 %s）" % [str(d.get("wind_bearing", "")), str(YashanBattle.WIND_TOWARD_DEG)])
	_expect(str(pb.get("sea_name", "")) == "崖山港湾", "题签写「崖山港湾」（实际 %s）" % str(pb.get("sea_name", "")))
	var src = pb.get("source", {})
	_expect(src is Dictionary and str((src as Dictionary).get("event", "")) == YashanBattle.SOURCE,
		"source.event 认得出是这一场（%s）" % str(src))

	# 港湾那一档的读数（雾、窄水、看不出八十步）：与 data/combat_sea_state.json 里那条档一字对得上
	var wn: Dictionary = YashanBattle.waters_note()
	_expect(str(wn.get("id", "")) == "harbor" and str(wn.get("weather", "")) == "雾",
		"港湾档的读数：%s・%s" % [str(wn.get("name", "")), str(wn.get("weather", ""))])
	var data := _sea_state_json()
	var harbor := _find_row(data.get("waters", []), "harbor")
	_expect(not harbor.is_empty(), "data/combat_sea_state.json 里确有港湾那一档")
	if not harbor.is_empty():
		_expect(int(harbor.get("visibility_bu", 0)) == int(wn.get("visibility_bu", 0)),
			"本件读的能见度与数据档一致（%s 步）" % str(harbor.get("visibility_bu", "")))
	var fog := _find_row(data.get("weather", []), "fog")
	_expect(not fog.is_empty(), "数据档里确有雾这一档（fog）")


static func _find_row(rows, rid: String) -> Dictionary:
	if not (rows is Array):
		return {}
	for r in rows:
		if r is Dictionary and str((r as Dictionary).get("id", "")) == rid:
			return r
	return {}


static func _sea_state_json() -> Dictionary:
	var f := FileAccess.open("res://data/combat_sea_state.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


# ══ 三、火船摆下 ═════════════════════════════════════════════

## 真起一场崖山港湾战（探针布景：敌炮冻住），数火船：
##   开时 —— 火船在、名字不带 PirateShip_ 前缀、不进敌全灭的数、不进士气簿、同屏不超 8 艘；
##   关时 —— 一艘也没有，只剩元军船阵。
func _sec_fire_ships() -> void:
	var wm := await _yashan_battle(300.0, false)
	if wm == null:
		return
	var fires := _fire_nodes(wm)
	var foes := _foe_nodes(wm)
	var want := YashanBattle.fire_ship_count(300.0, false)
	_expect(fires.size() == want, "开关开：摆下 %d 艘火船（应 %d 艘）" % [fires.size(), want])
	_expect(fires.size() > 0, "开关开：火船确实摆下了")
	for n in fires:
		if String(n.name).begins_with("PirateShip"):
			_expect(false, "火船名不带 PirateShip_ 前缀（实际 %s）" % String(n.name))
			break
	_expect(_all_prefixed(fires, "FireShip"), "火船名一律 FireShip_ 前缀（%s）" % str(_names(fires)))
	_expect(_all_fire_ships(fires), "火船都摆了火船那一态（set_fire_ship）")
	_expect(int(wm.call("_enemies_alive")) == foes.size(),
		"敌全灭的数只算元军船阵（敌 %d 艘，火船不计）" % foes.size())
	var in_morale := 0
	var tracker = wm.get("_morale")
	if tracker != null and is_instance_valid(tracker):
		for n in _fire_nodes(wm):
			if tracker.call("sheet_of", n) != null:
				in_morale += 1
	_expect(in_morale == 0, "火船不进士气簿（进了 %d 艘）" % in_morale)
	_expect(foes.size() + fires.size() <= YashanBattle.SCREEN_CAP,
		"同屏船数不超 %d（元军 %d + 火船 %d）" % [YashanBattle.SCREEN_CAP, foes.size(), fires.size()])
	_expect(is_equal_approx(float(wm.get("_yashan_escape_px")), YashanBattle.ESCAPE_PX),
		"出路是港湾的尺子（离场线 %s px，应 %s）" % [str(wm.get("_yashan_escape_px")), str(YashanBattle.ESCAPE_PX)])
	_expect(float(wm.get("_yashan_escape_px")) < 1280.0 and float(wm.get("_yashan_escape_px")) > float(wm.get("_escape_px")) * 0.4,
		"出路在火船阵之外、又比外海那 1280 px 近（%s px）" % str(wm.get("_yashan_escape_px")))
	await _close(wm)

	CS.set_on("yashan_fire_ship", false)
	var wm2 := await _yashan_battle(300.0, false, "yashan_fire_ship_off")
	if wm2 == null:
		CS.reset()
		return
	_expect(_fire_nodes(wm2).is_empty(), "开关关：这一场没有火船")
	_expect(_foe_nodes(wm2).size() > 0, "开关关：元军船阵照旧在（%d 艘）" % _foe_nodes(wm2).size())
	_expect(is_equal_approx(float(wm2.get("_yashan_escape_px")), YashanBattle.ESCAPE_PX),
		"开关关：海况与出路照旧（离场线 %s px）" % str(wm2.get("_yashan_escape_px")))
	await _close(wm2)
	CS.reset()


## 泉州借过船的档：元军船阵多一艘快船（同屏仍不超 8）。
## 同屏船数上限那一格按「元军 + 火船」两档各算一遍——本场敌阵小，火船那 5 艘的定额两档都占不满，
## 所以这一格数的是「两档加起来都不超 8」，不是「哪一档火船更少」。
func _sec_enemy_count_by_known() -> void:
	var fire_a: int = YashanBattle.fire_ship_count(300.0, false)
	var fire_b: int = YashanBattle.fire_ship_count(300.0, true)
	_expect(fire_a > 0 and fire_b > 0, "两档都摆得下火船（借过船 %d 艘 / 没借过 %d 艘）" % [fire_b, fire_a])
	_expect(fire_b <= fire_a, "借过船的档元军多一艘，火船的位子只减不增（%d → %d）" % [fire_a, fire_b])
	var total_a := fire_a + _foe_planned(false)
	var total_b := fire_b + _foe_planned(true)
	_expect(total_a <= YashanBattle.SCREEN_CAP and total_b <= YashanBattle.SCREEN_CAP,
		"两档同屏（元军 + 火船）都不超 %d（%d / %d）" % [YashanBattle.SCREEN_CAP, total_a, total_b])


## 这一档元军船阵预设几艘（同 YashanBattle._enemy_list 的条数）
static func _foe_planned(known: bool) -> int:
	var n := 0
	for e in YashanBattle._enemy_list(known):
		n += int(e.get("count", 1))
	return n


# ══ 四、碰上就点火 ═══════════════════════════════════════════

## 把一艘火船挪到旗舰舷边，走一帧 WorldMap 的逐帧那一支：
##   ① 旗舰篷帆着了（rig 火势 > 0，撞上的火落篷帆先着）；
##   ② 旗舰挨了撞伤（船体掉）；
##   ③ 火船自己烧起来（四处火势 > 0）；
##   ④ 碰过的不再点第二回（fire_spent 置起，再挨着也不重复点）。
func _sec_ignite() -> void:
	var wm := await _yashan_battle(300.0, false, "yashan_ignite")
	if wm == null:
		return
	var fires := _fire_nodes(wm)
	var ship: Node2D = wm.get("ship")
	if fires.is_empty() or not is_instance_valid(ship):
		_expect(false, "布景里没有火船或没有旗舰，点火那一节判不了")
		await _close(wm)
		return
	var fire: Node2D = fires[0]
	var ship_dm_before := float(ship.get("hull_hp"))
	var rig_before := _ship_rig_fire(ship)
	fire.position = ship.position + Vector2(0, 60)
	await process_frame
	await process_frame
	var rig_after := _ship_rig_fire(ship)
	_expect(rig_after > rig_before, "碰上就点火：旗舰篷帆着了（rig %s → %s —— 火船带过来的火不看引火率）" % [str(rig_before), str(rig_after)])
	var ship_dm_after := float(ship.get("hull_hp"))
	_expect(ship_dm_after < ship_dm_before, "碰上就点火：旗舰挨了撞伤（船体 %s → %s）" % [str(ship_dm_before), str(ship_dm_after)])
	_expect(bool(fire.get("fire_spent")), "碰上就点火：这一艘已记「碰过了」")
	var fire_burning := _fire_ship_fire(fire)
	_expect(fire_burning > 0.0, "碰上就烧起来：火船自己四处起火（火势合计 %s）" % str(fire_burning))
	# 再挨着也不重复点：撞伤只记那一下（ram_hits 恒 1）——之后旗舰船体再掉是自己在烧，不是又挨了一撞
	var hits_mid := int(fire.get("ram_hits"))
	var hull_mid := float(ship.get("hull_hp"))
	fire.position = ship.position + Vector2(0, 40)
	await process_frame
	await process_frame
	_expect(int(fire.get("ram_hits")) == hits_mid and hits_mid == 1,
		"碰过的不再点第二回（撞上过的回数 %d → %d）" % [hits_mid, int(fire.get("ram_hits"))])
	_expect(float(ship.get("hull_hp")) <= hull_mid, "再挨着不再添船体伤（%s → %s）" % [str(hull_mid), str(ship.get("hull_hp"))])
	await _close(wm)


## 旗舰的篷帆火势（DamageModel 的 FloodFire 上那一段 rig）
func _ship_rig_fire(ship: Node2D) -> float:
	if ship == null or not is_instance_valid(ship):
		return 0.0
	var dm = ship.call("get_damage_model")
	if dm == null:
		return 0.0
	return float(dm.call("zone_fire", "rig"))


## 火船自己的火势合计（四处相加）
func _fire_ship_fire(n: Node2D) -> float:
	var ff = n.get("flood_fire")
	if ff == null:
		return 0.0
	var f = ff.get("ff")
	if f == null:
		return 0.0
	var total := 0.0
	for z in ["bow", "mid", "stern", "rig"]:
		total += float(f.call("zone_fire", z))
	return total


# ══ 五、冲出 / 没冲出两式 ═══════════════════════════════════

## 判词：win / flee 脱战（甩脱、弃战脱身）/ disengaged 两散都算冲出；lose 那一族（沉 / 跳帮 / 我方降幡）没冲出。
## 两式只换结局文字里「船活没活」那一句，同一场、同一个「海上宋鬼」。
func _sec_two_endings() -> void:
	_expect(YashanBattle.broke_out("win", {}), "冲出：win（敌尽降遁 / 敌全灭）算冲出")
	_expect(YashanBattle.broke_out("flee", {"flee_ok": true}), "冲出：弃战脱身算冲出")
	_expect(YashanBattle.broke_out("flee", {"flee_ok": true, "shook_off": true}), "冲出：甩开追船算冲出")
	_expect(YashanBattle.broke_out("flee", {"parted": true}), "冲出：天晚两散算冲出")
	_expect(YashanBattle.broke_out("disengaged", {}), "冲出：限时两散算冲出")
	_expect(not YashanBattle.broke_out("lose", {}), "没冲出：lose（被跳帮夺船 / 失守）算没冲出")
	_expect(not YashanBattle.broke_out("lose", {"sunk": true}), "没冲出：旗舰沉了算没冲出")
	_expect(not YashanBattle.broke_out("lose", {"struck": true}), "没冲出：我方挂降幡算没冲出")
	_expect(not YashanBattle.broke_out("lose", {"morale_verdict": "player_struck"}), "没冲出：士气簿裁决我方降幡算没冲出")
	var a: String = YashanBattle.tail_text(true)
	var b: String = YashanBattle.tail_text(false)
	_expect(a != b and a != "" and b != "", "两式的「船活没活」那一句不同（冲出 %d 字 / 没冲出 %d 字）" % [a.length(), b.length()])
	_expect(a.find("没躲开") < 0 and b.find("没躲开") >= 0, "没冲出那一式写「没躲开」那一笔，冲出那一式不写")
	_expect(a.find("出港嘴") >= 0 and b.find("出港嘴") < 0, "冲出那一式写出港嘴，没冲出那一式不写")


# ══ 六、收战写两枚旗 ═══════════════════════════════════════

## 真起一场崖山港湾战、按 WorldMap 的收战路径（_battle_exit）走一遍：
##   冲出（flee 脱身）→ 两枚旗都置起；没冲出（lose）→ 只置「打过」那枚。
##   寻常海战（source.event 不是这一场）一个字不写。
func _sec_flags() -> void:
	_gs.set("flags", {})
	var wm := await _yashan_battle(300.0, false, "yashan_flags_out")
	if wm == null:
		return
	_expect(bool(wm.get("_yashan_on")), "本场认得出是崖山突围（_yashan_on）")
	wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	await process_frame
	_expect(_gs.call("has_flag", YashanBattle.FLAG_DONE), "收战写出「打过」那枚旗（%s）" % YashanBattle.FLAG_DONE)
	_expect(_gs.call("has_flag", YashanBattle.FLAG_OUT), "冲出来了：写出「冲出来了」那枚旗（%s）" % YashanBattle.FLAG_OUT)
	_expect(YashanBattle.last_result(_gs.get("flags")) == true, "闭卷读回：上一场的结果 = 冲出来了")

	_gs.set("flags", {})
	var wm2 := await _yashan_battle(300.0, false, "yashan_flags_in")
	if wm2 != null:
		wm2.call("_battle_exit", "lose", {"sunk": true})
		await process_frame
		await process_frame
		_expect(_gs.call("has_flag", YashanBattle.FLAG_DONE), "没冲出来：也写「打过」那枚旗")
		_expect(not _gs.call("has_flag", YashanBattle.FLAG_OUT), "没冲出来：不写「冲出来了」那枚旗")
		_expect(YashanBattle.last_result(_gs.get("flags")) == false, "闭卷读回：上一场的结果 = 没冲出来")

	# 寻常海战：走同一支收战路，旗一个字不写
	_gs.set("flags", {})
	var wm3 := await _plain_battle()
	if wm3 != null:
		wm3.call("_battle_exit", "win", {})
		await process_frame
		await process_frame
		_expect(not _gs.call("has_flag", YashanBattle.FLAG_DONE), "寻常海战不写这两枚旗")
		_expect(YashanBattle.last_result(_gs.get("flags")) == null, "没打过这一场时 last_result 给 null（读档回来的旧档也走这一支）")


# ══ 七、关态 ═══════════════════════════════════════════════

## 开关关：崖山页那扇门根本不挂；场次配置也不再交火船
func _sec_off() -> void:
	CS.set_on("yashan_breakout", false)
	_expect(not YashanBattle.enabled(), "开关关：enabled() 为假")
	_expect(YashanBattle.fire_ship_count(300.0, false) == 0, "开关关：不交火船")
	CS.reset()
	_expect(YashanBattle.enabled(), "开关复位：enabled() 恢复为真")


# ══ 布景 ═══════════════════════════════════════════════════

## 真起一场崖山港湾战：pending_battle 走 YashanBattle.setup，敌炮冻住（布景不自己结算）。返回 WorldMap
func _yashan_battle(power: float, known: bool, tag := "yashan") -> Node:
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 70)
	var pb: Dictionary = YashanBattle.setup(power, known)
	pb["sea_seed"] = 20261016            # 探针定场：同一场海况
	_gm.set("pending_battle", pb)
	var wm := await _mount_world_map()
	for f in _foe_nodes(wm):
		f.set("fire_timer", INF)
	return wm


## 寻常海战（source.event 不是这一场）：同一支收战路，用来验「旗一个字不写」
func _plain_battle() -> Node:
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 70)
	_gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 1}], "sea_name": "泉州外海",
		"source": {"scene": "qa_w53_p6_yashan", "event": "pirate"}})
	var wm := await _mount_world_map()
	for f in _foe_nodes(wm):
		f.set("fire_timer", INF)
	return wm


func _mount_world_map() -> Node:
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	return wm


func _foe_nodes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _fire_nodes(wm: Node) -> Array:
	var host: Node = wm.get_node_or_null("FireShips")
	if host == null:
		return []
	return host.get_children().filter(func(c): return c is Node2D and not c.is_queued_for_deletion())


static func _all_prefixed(nodes: Array, prefix: String) -> bool:
	for n in nodes:
		if not String(n.name).begins_with(prefix):
			return false
	return true


static func _all_fire_ships(nodes: Array) -> bool:
	for n in nodes:
		if n.get("fire_ship") != true:
			return false
	return true


static func _names(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		out.append(String(n.name))
	return out


## 形参不写类型：收了战的海战场（_battle_exit 自己 queue_free）等过几帧已释放，带类型的形参收到已释放实例当场报错
func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)          # 拆布景不收战（不发 battle_finished）
		wm.queue_free()
	await process_frame
	await process_frame
