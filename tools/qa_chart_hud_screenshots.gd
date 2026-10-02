extends SceneTree
## Lane U：海图 HUD 信息密度巡检（港名密区 / 航行中 HUD / 告警朱字）。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/chart/
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd   # 截图门禁（须出 5 张）
##       godot --headless --path . -s res://tools/qa_chart_hud_screenshots.gd -- --contract   # 只验非渲染断言，不截图
## 默认严格须出 5 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd
## 05 小地图（lane w19-g10）：WorldMap 走真海战布景（pending_battle + 冻敌炮，同 combat_probe_stage.gd），入战墨边收场后截，
##   断言罗经盘盘心朱点与外圈泥金线真画出来了；不写 pending_battle 时 WorldMap 走孤儿退出，截到的是灰底墨边。
## 注意：本脚本勿在顶层类型标注 MapView（-s SceneTree 编译期尚无 autoload，会连带 MapView 编不过）。

const VIEW := Vector2i(1280, 720)
const CHART_SCENE := "res://scenes/SeaChart.tscn"
const WM_SCENE := "res://scenes/WorldMap.tscn"
const SP := preload("res://tools/src_probe.gd")  # 按名认函数的源码探查（lane cs15：不按前缀认名）
const TAG := "QA_CHART_HUD"
const EXPECTED_SHOTS := 5
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")  # 05 真海战布景：冻敌炮 / 等墨边收场 / 按相位截（lane w19-g10）
const MINIMAP_PATH := "CanvasLayer/HUD/MinimapPanel/Margin/MinimapRect"

var _out_dir := ShotGate.out_dir("chart")
var _chart: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--out="):
			_out_dir = str(a).substr(6)
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(_out_dir)
	print("QA_CHART_HUD_BEGIN")
	ShotGate.frame_pressure(self)
	_check_wiring()

	# 先挂 Main，让 autoload / class_name 与游戏一致（与 patrol_shell 同路径）
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await _frames(6)

	var gs: Node = root.get_node("GameState")
	var fleet: Node = root.get_node("Fleet")
	var voyage: Node = root.get_node("Voyage")
	var cal: Node = root.get_node("Calendar")
	gs.chapter = 4
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou"]
	gs.money = maxi(int(gs.money), 800)

	# ── 01 港名密区 ──
	# fail-fast（lane w22-h5，接 w21-d8；wave23-a9 抬共用面）：load() / instantiate() 返回 null，或挂上了但 get_script()==null
	# 三种症状共用 shot_gate.gd start_tree_probe，秒级判红；@onready / _ready 挂的字段挪到 add_child+过帧后由 check_fields 点。
	_chart = ShotGate.start_tree_probe(CHART_SCENE, _fails, "SeaChart 01 港名密区")
	if _chart == null:
		_report()  # 原因已进 _fails（shot_gate 标语）
		return
	root.add_child(_chart)
	await _frames(8)
	if not ShotGate.check_fields(_chart, {"map": "SeaChart.gd 或 MapView Parse Error / MapView path 错", "_hand": "SeaChart.gd 里 _hand 填表 Parse Error / path 错"}, _fails, "SeaChart 01 港名密区"):
		_report()
		return
	_print_ok("%s 挂上且字段齐：map/_hand（共用自检）" % CHART_SCENE)
	var map: Node = _chart.get("map")
	map.call("frame_ports", ["quanzhou", "xinghua", "xinghua_harbor", "fuzhou", "zhangzhou", "penghu"], 0.10, 0.0)
	await _frames(6)
	await _shot("01_port_dense")

	# ── 02 航行中 HUD ──
	var hand: PackedStringArray = _chart.get("_hand")
	var far := ""
	var far_d := -1.0
	for pid in hand:
		var d: float = voyage.distance_li("quanzhou", str(pid))
		if d > far_d:
			far_d = d
			far = str(pid)
	_expect(far != "", "手牌里有去处")
	if far != "" and map:
		_chart.call("_select_heading", far)
		await _frames(4)
		_chart.set("total_li", far_d)
		_chart.set("remaining_li", far_d * 0.42)
		_chart.set("course_bearing", voyage.bearing("quanzhou", far))
		_chart.set("days_elapsed", 6)
		_chart.set("sailing", true)
		_chart.call("_lock_hand")
		var traveled := far_d * 0.58
		var at: Dictionary = voyage.point_along_track("quanzhou", far, traveled)
		var tw = map.call("move_ship_lonlat", float(at["lon"]), float(at["lat"]), voyage.bearing_at("quanzhou", far, traveled), 0.58, 0.01)
		# 裸 await finished：补间被 kill（再调 move_ship_lonlat）就永不返回；改带墙钟上界
		if tw is Tween and not await Clock.until(self, func() -> bool: return not (tw as Tween).is_running()):
			_expect(false, "船标补间 %d ms 内没走完" % Clock.WAIT_MS)
		# 取景照游戏发舶那一下（SeaChart._on_sail_pressed：起讫两港、pad 0.30，缩放受 MapView.FRAME_ZOOM_MAX 管）。
		# 原先对着船标硬设 zoom 1.4，截到的是远洋一片空海、比例尺二百里、不见岸线，不是玩家看到的航行画面（w19-g13）。
		map.call("frame_ports", ["quanzhou", far], 0.30, 0.0)
		_chart.call("_refresh_status")
		await _frames(4)
	await _shot("02_sailing_hud")

	# ── 03/04 告警朱字 ──
	_chart.set("sailing", false)
	_chart.set("days_elapsed", 0)
	fleet.water = 6
	fleet.food = 6
	gs.contract = {
		"good_id": "silk_fabric", "remaining": 30, "qty": 30,
		"dest": far if far != "" else "hakata", "from": "quanzhou",
		"due_day": cal.absolute_day() + 2, "purse": 900, "paid": 0,
	}
	_chart.call("_log", "[color=#A8322A]第 5 日・水粮已尽　舱中有人病倒[/color]")
	_chart.call("_refresh_hand")
	if far != "":
		_chart.call("_select_heading", far)
	await _frames(4)
	await _shot("03_alert_strip")
	_chart.call("_toggle_condition")
	await _frames(12)
	_expect(_condition_alpha() >= 1.0, "船况层已淡入满（a=%.2f）" % _condition_alpha())
	await _shot("04_alert_condition")

	# ── 05 小地图：卸海图、藏 Main，只留 WorldMap HUD 雷达 ──
	# lane w19-g10：WorldMap 是海战专用场景，没有 pending_battle 就走「孤儿场景立即退出」（_battle_exit("flee")：
	# 起一副出战墨边「外海・脱战」再 queue_free），原先这里截到的是灰底墨边、从来没有雷达（gd20 待议 1，一色检查也拦不住）。
	# 改走真海战同路径：先写 pending_battle、冻敌炮（combat_probe_stage.gd 一），等入战墨边收场、雷达认到本船再截，
	# 截完断言罗经盘真画出来了（盘心朱点 + 泥金外圈），跑完清场、还原 pending_battle。
	if ResourceLoader.exists(WM_SCENE):
		if is_instance_valid(_chart):
			root.remove_child(_chart)
			_chart.free()
			_chart = null
		await _frames(2)
		for c in main.get_children():
			if c is CanvasItem:
				(c as CanvasItem).visible = false
		main.visible = false
		await _shot_minimap()

	_report()


## 05：真海战布景（pending_battle + 冻敌炮）上截右下罗经盘小地图，并断言雷达画出来了（lane w19-g10）
func _shot_minimap() -> void:
	var gm: Node = root.get_node("GameManager")
	var saved_battle: Dictionary = (gm.get("pending_battle") as Dictionary).duplicate(true)
	gm.set("pending_battle", {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "source": {"scene": "qa_chart_hud"},
	})
	var wm: Node = (load(WM_SCENE) as PackedScene).instantiate()
	root.add_child(wm)
	var wm_ref: WeakRef = weakref(wm)  # 条件 lambda 只捕获弱引用（combat_probe_stage.gd 六）
	_expect(CombatStage.freeze_enemy_fire(wm) >= 1, "05 布景敌船开炮已冻住")
	_expect(not bool(wm.get("resolved")) and bool(wm.get("combat_mode")), "05 布景 WorldMap 进了海战（未走孤儿退出）")
	var mini: Control = wm.get_node_or_null(MINIMAP_PATH) as Control
	_expect(mini != null, "05 WorldMap HUD 有小地图 %s" % MINIMAP_PATH)
	if mini == null:
		CombatStage.teardown(self, wm, null)
		await _frames(2)
		gm.set("pending_battle", saved_battle)
		return
	var mini_ref: WeakRef = weakref(mini)
	var radar_ready := func() -> bool:
		var w = wm_ref.get_ref()
		var m = mini_ref.get_ref()
		return (CombatStage.standing_fail(w) == "" and CombatStage.letterbox_under(self, w) == null
				and _radar_live(m))
	var gone := func() -> bool: return CombatStage.standing_fail(wm_ref.get_ref()) != ""
	if _contract:
		# 不截图也验接线：入战墨边收场后雷达认到本船、在树上可见（headless 零延迟旁路下墨边不上场）
		await CombatStage.wait_until(self, func() -> bool: return radar_ready.call() or gone.call())
		var live: bool = radar_ready.call()
		_expect(live, "05 雷达认到本船且可见" if live else "05 雷达没认到本船或不可见：%s" % CombatStage.why_not("等入战墨边收场", "布景已结算或墨边未收"))
	else:
		var path := "%s/05_minimap_hud.png" % _out_dir
		var img_box := [null]
		var ok := await CombatStage.shot_when(self, path.get_file(), _fails,
				func() -> void: img_box[0] = ShotGate.shot(root, path, _saved, _fails), radar_ready, gone)
		if ok and img_box[0] != null and is_instance_valid(mini):
			_check_radar_pixels(img_box[0] as Image, mini)
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "05 布景海战在截图前未自行结算")
	CombatStage.teardown(self, wm, null)
	await _frames(2)
	gm.set("pending_battle", saved_battle)


## 雷达可画：认到了本船（Minimap._ready 沿父链找 Ship），且在树上可见、有面积
func _radar_live(m) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	var s = m.get("ship")
	return s != null and is_instance_valid(s) and (m as Control).is_visible_in_tree() and (m as Control).size.x >= 100.0


## 截下来的图里罗经盘真画出来了：盘心 3.5 px 朱点（UiTheme.CINNABAR）+ 外圈泥金线（UiTheme.GOLD），不是空板 / 灰底墨边
func _check_radar_pixels(img: Image, mini: Control) -> void:
	var vis := root.get_visible_rect().size
	var k := Vector2(float(img.get_width()) / vis.x, float(img.get_height()) / vis.y)
	var r: float = float(mini.get("radar_radius"))
	var xf := mini.get_global_transform_with_canvas()
	var c: Vector2 = xf * Vector2(r, r) * k
	var best_red := 9.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var p := Vector2i(int(round(c.x)) + dx, int(round(c.y)) + dy)
			if Rect2i(Vector2i.ZERO, img.get_size()).has_point(p):
				best_red = minf(best_red, _cdist(img.get_pixelv(p), UiTheme.CINNABAR))
	_expect(best_red < 0.12, "05 小地图盘心画出本船朱点（色差 %.3f）" % best_red)
	var gold_hits := 0
	var samples := 48
	for i in samples:
		var a := TAU * float(i) / float(samples)
		var hit := false
		for dr in [-2.5, -1.5, -0.5, 0.5]:
			var q: Vector2 = xf * (Vector2(r, r) + Vector2(cos(a), sin(a)) * (r + dr)) * k
			var p := Vector2i(int(round(q.x)), int(round(q.y)))
			if Rect2i(Vector2i.ZERO, img.get_size()).has_point(p) and _cdist(img.get_pixelv(p), UiTheme.GOLD) < 0.25:
				hit = true
				break
		if hit:
			gold_hits += 1
	_expect(gold_hits >= samples * 3 / 4, "05 小地图外圈泥金线画出（%d/%d 向命中）" % [gold_hits, samples])


func _cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func _check_wiring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_expect("AUTOWRAP_OFF" in src, "顶匾 strip 不折行")
	_expect("委办剩" in src and "半途必尽" in src, "告警朱字短标签")
	var mini := FileAccess.get_file_as_string("res://scripts/Minimap.gd")
	_expect("子" in mini and "卯" in mini, "小地图子午卯酉短标")
	var mv := FileAccess.get_file_as_string("res://scripts/chart/MapView.gd")
	_expect("size_px := 16" in mv or "size_px := 16 if" in mv, "港名字号抬升")
	_expect(SP.has_tok(mv, "_px(26.0)"), "船标避让放大")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "placeholder", "玩家", "点击"]:
		_expect(bad not in _visible_strings(src), "SeaChart 可见文案无「%s」" % bad)


func _visible_strings(src: String) -> String:
	var rx := RegEx.new()
	rx.compile("\"([^\"\\\\]|\\\\.)*\"")
	var out := PackedStringArray()
	for line in src.split("\n"):
		var code := line.get_slice("#", 0)
		for m in rx.search_all(code):
			out.append(m.get_string())
	return "\n".join(out)


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完（进海图面纱 0.55 s、船况层淡入 0.16 s）；墙钟上界见 probe_clock.gd
func _frames(n: int) -> void:
	if not await Clock.settle(self, n):
		_expect(false, "演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


## 船况层不透明度（0 = 未开）
func _condition_alpha() -> float:
	var layer = _chart.get("_condition_layer") if is_instance_valid(_chart) else null
	return float(layer.modulate.a) if layer != null and bool(layer.visible) else 0.0


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [_out_dir, name], _saved, _fails)


func _print_ok(msg: String) -> void:
	print("OK ", msg)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _report() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, _out_dir, _fails))
