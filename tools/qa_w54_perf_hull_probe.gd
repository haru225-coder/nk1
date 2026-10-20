extends SceneTree
## lane w54-perf 船身视口省着画（开关 CombatSwitches.hull_view_lod，ShipHull3D）专项探针：一段钉一条、回退即红。
##   布景：一条 PirateShip.tscn（真船身 HullRig + ShipLook + CombatFx 那一套）摆在镜头正中，物理帧关掉，探针亲手转船。
##   一、开关关 = 老路：视口 UPDATE_ALWAYS、每帧把航向摆进视口（再小的转角也跟），省着画一回不记。
##   二、开关开：拨开那一帧补画一张；转不到阈角不重画（视口里的航向停在画过那张）、转过阈角当帧重画；
##       每帧转 0.37 个阈角慢转 120 帧，画出来那张与真航向之差始终不过阈角、约每三帧画一回。
##   三、阈角随屏上大小：镜头拉近一倍阈角减半（船首在屏上挪 YAW_EPS_PX 个窗口像素的角）；镜头拉到极远封顶 YAW_EPS_MAX。
##   四、藏起来 / 出了画（连 CULL_MARGIN 边距）不画；离画边不到边距照画；回到画里那一帧当帧补画、航向对上。
##   五、半路拨回关：当帧回 UPDATE_ALWAYS、不再记省着画，航向逐帧跟（不到阈角的转动也跟）。
##   六、带窗口才跑（DISPLAY=:2）：五个航向上开 / 关两路画出来的船身贴图逐像素精确比（容差 0）——省着画只少画、不改画法，
##       差只出在去重网格的法线上（实测原网格逐帧画两回 0 差、换去重网格同航向几十个像素差 1/255）：读出来的法线是
##       16 位八面体码解成的浮点，写回去引擎再编一遍（截断取整、不复原），末位挪一格。判：最大通道差 ≤ 1/255、差的像素 ≤ 0.05%。
##       另报（仅诊断）转 0.9 个阈角沿用上一张与满画那张的差，和同一条船满画着转 0.5°（快船 / 护航转向一帧常见的转角）的差作对照。
##       headless 印一行跳过。
##   末两案：本进程 SCRIPT ERROR / Parse Error 即红（script_err_tally）。
## 用法：godot --headless --path . -s res://tools/qa_w54_perf_hull_probe.gd（六要去掉 --headless、DISPLAY=:2；w53 本机经门锁跑）
## 末行 QA_W54_PERF_HULL PASS|FAIL cases=N fails=K；有失败退 1。

const TAG := "QA_W54_PERF_HULL"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Hull := preload("res://scripts/combat/ShipHull3D.gd")
const KEY := "hull_view_lod"

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _world: Node2D
var _cam: Camera2D
var _ship: Node2D
var _rig: Node
var _vp: SubViewport
var _yaw3d: Node3D


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _run() -> void:
	_Switches.reset()
	_check(_Switches.DEFAULTS.has(KEY) and _Switches.on(KEY), "开关 %s 在表里、默认开" % KEY)
	await _stage()
	_check(_rig != null and _vp != null and _yaw3d != null and _rig.has_method("lod_state"),
		"船身 HullRig 挂上、视口与三维航向节点在、有 lod_state")
	if _rig == null or _vp == null or _yaw3d == null:
		_report()
		return
	await _sec_off()
	await _sec_on()
	await _sec_eps()
	await _sec_cull()
	await _sec_back_off()
	await _sec_pixels()
	_Switches.reset()
	if is_instance_valid(_world):
		_world.queue_free()
	await process_frame
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(0 if _fails == 0 else 1)


# ── 布景 ──────────────────────────────────────────────

func _stage() -> void:
	_Switches.set_on(KEY, false)
	_world = Node2D.new()
	_world.name = "Sea"
	root.add_child(_world)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(0.5, 0.5)
	_world.add_child(_cam)
	_cam.make_current()
	_ship = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate() as Node2D
	_ship.set_physics_process(false)
	_world.add_child(_ship)
	_rig = _ship.get_node_or_null("HullRig")
	_vp = _rig.get_node_or_null("View") as SubViewport if _rig != null else null
	_yaw3d = _rig.get("_yaw") as Node3D if _rig != null else null
	var spr := _ship.get_node_or_null("Sprite2D") as Sprite2D
	for _i in 120:
		await process_frame
		if spr != null and _vp != null and spr.texture == _vp.get_texture():
			break
	await _frames(2)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _st() -> Dictionary:
	return _rig.call("lod_state") as Dictionary


## 视口里那条三维船的航向（弧度）与船节点真航向折成的应值 -rotation 之差
func _lag() -> float:
	return absf(angle_difference(_yaw3d.rotation.y, -_ship.rotation))


# ── 一、关 = 老路 ─────────────────────────────────────

func _sec_off() -> void:
	print("一、开关关 = 老路")
	_ship.rotation = 0.30
	await _frames(1)
	_check(_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "关：视口 UPDATE_ALWAYS（每帧满幅重画）")
	_check(_lag() < 1e-5, "关：视口里的航向当帧跟上船（差 %.6f rad）" % _lag())
	_ship.rotation = 0.30 + 0.0002
	await _frames(1)
	_check(_lag() < 1e-6, "关：转 0.0002 rad 也当帧跟（差 %.7f rad）" % _lag())
	var st := _st()
	_check(not bool(st["on"]) and int(st["renders"]) == 0, "关：不走省着画、一回不记（on=%s renders=%d）" % [st["on"], st["renders"]])


# ── 二、开 ────────────────────────────────────────────

func _sec_on() -> void:
	print("二、开关开：补画一张、阈角内不画、过阈角当帧画、慢转不落后过阈角")
	_ship.rotation = 0.30
	_Switches.set_on(KEY, true)
	await _frames(1)
	var st := _st()
	_check(bool(st["on"]) and int(st["renders"]) == 1 and bool(st["drawn"]),
		"开：拨开那一帧补画一张（on=%s renders=%d drawn=%s）" % [st["on"], st["renders"], st["drawn"]])
	_check(_vp.render_target_update_mode == SubViewport.UPDATE_ONCE, "开：视口只请画这一回（UPDATE_ONCE）")
	_check(_lag() < 1e-5, "开：补画那张就是这一刻的航向（差 %.6f rad）" % _lag())
	var eps := float(st["eps"])
	_check(eps > 0.0 and eps <= _Hull.YAW_EPS_MAX + 1e-9, "阈角 %.4f° 在 (0, %.2f°]" % [rad_to_deg(eps), rad_to_deg(_Hull.YAW_EPS_MAX)])
	_ship.rotation = 0.30 + eps * 0.5
	await _frames(1)
	_check(int(_st()["renders"]) == 1 and absf(angle_difference(_yaw3d.rotation.y, -0.30)) < 1e-6,
		"转 0.5 个阈角：不重画，视口航向停在画过那张（renders=%d）" % int(_st()["renders"]))
	_ship.rotation = 0.30 + eps * 0.9
	await _frames(1)
	_check(int(_st()["renders"]) == 1, "转 0.9 个阈角：仍不重画（renders=%d）" % int(_st()["renders"]))
	_ship.rotation = 0.30 + eps * 1.1
	await _frames(1)
	_check(int(_st()["renders"]) == 2 and _lag() < 1e-5, "转过阈角（1.1 个）：当帧重画、航向对上（renders=%d 差 %.6f）" % [int(_st()["renders"]), _lag()])
	var r0 := int(_st()["renders"])
	var worst := 0.0
	for _k in 120:
		_ship.rotation += eps * 0.37
		await process_frame
		worst = maxf(worst, _lag())
	var drawn := int(_st()["renders"]) - r0
	_check(worst < eps, "慢转 120 帧（每帧 0.37 个阈角）：画面落后真航向至多 %.4f°，不过阈角 %.4f°" % [rad_to_deg(worst), rad_to_deg(eps)])
	_check(drawn >= 38 and drawn <= 42, "慢转 120 帧约每三帧画一回（画了 %d 回，应 38–42）" % drawn)


# ── 三、阈角随屏上大小 ────────────────────────────────

func _sec_eps() -> void:
	print("三、阈角随屏上大小")
	# 镜头取到屏上一个视口像素合 0.25 / 0.5 窗口像素（headless 根窗口缩放 0.05、带窗口 1.0，两边都落在封顶以下）
	var spr := _ship.get_node("Sprite2D") as Sprite2D
	var fin := root.get_final_transform().x.length()
	var z1 := 0.25 / maxf(0.001, absf(spr.global_scale.x) * fin)
	_cam.zoom = Vector2(z1, z1)
	_ship.rotation += 0.05
	await _frames(2)
	var e1 := float(_st()["eps"])
	_cam.zoom = Vector2(z1 * 2.0, z1 * 2.0)
	_ship.rotation += 0.05
	await _frames(2)
	var e2 := float(_st()["eps"])
	var want := _Hull.YAW_EPS_PX / (_Hull.HULL_REACH_PX * 0.25)
	_check(absf(e1 - want) < want * 0.03, "一个视口像素合 0.25 窗口像素：阈角 %.4f°（应 %.4f°，船首挪 %.1f 像素）" % [rad_to_deg(e1), rad_to_deg(want), _Hull.YAW_EPS_PX])
	_check(absf(e1 / maxf(1e-9, e2) - 2.0) < 0.06, "镜头拉近一倍阈角减半（%.4f° → %.4f°）" % [rad_to_deg(e1), rad_to_deg(e2)])
	_cam.zoom = Vector2(z1 * 0.02, z1 * 0.02)
	_ship.rotation += 0.05
	await _frames(2)
	var e3 := float(_st()["eps"])
	_check(absf(e3 - _Hull.YAW_EPS_MAX) < 1e-9, "镜头拉到极远阈角封顶 %.2f°（得 %.4f°）" % [rad_to_deg(_Hull.YAW_EPS_MAX), rad_to_deg(e3)])
	_cam.zoom = Vector2(0.5, 0.5)
	await _frames(2)


# ── 四、藏起来 / 出画不画，回画当帧补 ─────────────────

func _sec_cull() -> void:
	print("四、藏起来 / 出画不画，回到画里当帧补画")
	await _frames(1)
	var r0 := int(_st()["renders"])
	_ship.visible = false
	_ship.rotation += 0.2
	await _frames(2)
	_check(int(_st()["renders"]) == r0 and _lag() > 0.19, "船藏着转 0.2 rad：不画（renders %d → %d）" % [r0, int(_st()["renders"])])
	_ship.visible = true
	await _frames(1)
	_check(int(_st()["renders"]) == r0 + 1 and _lag() < 1e-5, "露出来那一帧补画、航向对上（renders=%d 差 %.6f）" % [int(_st()["renders"]), _lag()])
	# 离画右缘多远：按船图（整张视口贴图）在画布上的左缘量，镜头在 (0, 0)
	var home := _ship.position
	_ship.position = _beyond_right(_Hull.CULL_MARGIN * 2.0)
	_ship.rotation += 0.2
	await _frames(2)
	r0 = int(_st()["renders"])
	_ship.rotation += 0.2
	await _frames(2)
	_check(int(_st()["renders"]) == r0 and _lag() > 0.19, "船图离画右缘两倍边距：转了也不画（renders %d → %d）" % [r0, int(_st()["renders"])])
	_ship.position = _beyond_right(_Hull.CULL_MARGIN * 0.5)
	await _frames(1)
	_check(int(_st()["renders"]) == r0 + 1 and _lag() < 1e-5, "挪到离画右缘半个边距（还没进画）：当帧补画、航向对上（renders=%d）" % int(_st()["renders"]))
	_ship.position = _beyond_right(_Hull.CULL_MARGIN * 2.0)
	_ship.rotation += 0.2
	await _frames(2)
	r0 = int(_st()["renders"])
	_ship.position = home
	await _frames(1)
	_check(int(_st()["renders"]) == r0 + 1 and _lag() < 1e-5, "从画外一步回到画中：那一帧补画、航向对上（renders=%d 差 %.6f）" % [int(_st()["renders"]), _lag()])


## 船摆到这个位置时，船图（整张视口贴图）在画布上的左缘恰在可见矩形右缘外 gap 个画布像素
func _beyond_right(gap: float) -> Vector2:
	var spr := _ship.get_node("Sprite2D") as Sprite2D
	var z := _cam.zoom.x
	var half := float(_Hull.VIEW) * 0.5 * absf(spr.global_scale.x) * z
	var vis := root.get_visible_rect()
	var cx := vis.end.x + gap + half
	var c := _cam.get_screen_center_position()
	return Vector2(c.x + (cx - vis.get_center().x) / z, c.y)


# ── 五、半路拨回关 ────────────────────────────────────

func _sec_back_off() -> void:
	print("五、半路拨回关")
	var r0 := int(_st()["renders"])
	_Switches.set_on(KEY, false)
	_ship.rotation += 0.0003
	await _frames(1)
	var st := _st()
	_check(_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not bool(st["on"]),
		"拨回关：当帧回 UPDATE_ALWAYS、不再走省着画（on=%s）" % st["on"])
	_check(_lag() < 1e-6, "拨回关：再小的转角也当帧跟（差 %.7f rad）" % _lag())
	_ship.rotation += 0.3
	await _frames(1)
	_check(int(_st()["renders"]) == r0 and _lag() < 1e-5, "拨回关后转 0.3 rad：航向跟上、省着画一回不记（renders=%d）" % int(_st()["renders"]))


# ── 六、带窗口：开 / 关同航向逐像素相同 ───────────────

func _sec_pixels() -> void:
	print("六、开 / 关两路同一航向画出来的船身贴图")
	if DisplayServer.get_name() == "headless":
		print("  · headless 不出图：六跳过（DISPLAY=:2 去掉 --headless 再跑这一段）")
		return
	_cam.zoom = Vector2(0.5, 0.5)
	var worst_n := 0
	var worst_max := 0
	var worst_at := 0.0
	for th in [0.0, 0.7, 1.9, 3.3, 4.6]:
		_Switches.set_on(KEY, false)
		_ship.rotation = th
		await _frames(3)
		var a: Image = _rig.call("grab_image")
		_ship.rotation = th + 0.5
		await _frames(2)
		_Switches.set_on(KEY, true)
		_ship.rotation = th
		await _frames(3)
		var b: Image = _rig.call("grab_image")
		var d := _diff(a, b, 0)
		if int(d[0]) < 0:
			worst_n = -1
			break
		if int(d[0]) > worst_n:
			worst_n = int(d[0])
			worst_at = th
		worst_max = maxi(worst_max, int(d[1]))
	var cap := int(832 * 832 * 0.0005)
	_check(worst_n >= 0 and worst_max <= 1 and worst_n <= cap,
		"五个航向上开 / 关两路贴图精确比：最大通道差 %d/255（应 ≤ 1）、差的像素至多 %d 个（航向 %.1f；应 ≤ %d，即 0.05%%）" % [worst_max, worst_n, worst_at, cap])
	# 诊断：转 0.9 个阈角不重画那张 vs 满画那张（视口 832² 上量；屏上还要再缩约 3 倍）
	_Switches.set_on(KEY, true)
	_ship.rotation = 1.2
	await _frames(3)
	var eps := float(_st()["eps"])
	_ship.rotation = 1.2 + eps * 0.9
	await _frames(2)
	var stale: Image = _rig.call("grab_image")
	_Switches.set_on(KEY, false)
	await _frames(3)
	var exact: Image = _rig.call("grab_image")
	_ship.rotation = 1.2 + eps * 0.9 + deg_to_rad(0.5)
	await _frames(3)
	var turned: Image = _rig.call("grab_image")
	print("  · 诊断（贴图 832² 共 %d 像素，差过 8/255 的个数）：转 0.9 个阈角（%.3f°）沿用上一张 vs 满画 %d；同一条船满画着再转 0.5° 前后 %d" % [
		832 * 832, rad_to_deg(eps * 0.9), int(_diff(stale, exact, 8)[0]), int(_diff(exact, turned, 8)[0])])


## 两张图逐像素比（RGBA8，0–255）：[任一通道差过 tol 的像素数, 最大通道差]；尺寸不合 / 取不到图给 [-1, -1]
static func _diff(a: Image, b: Image, tol: int) -> Array:
	if a == null or b == null or a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
		return [-1, -1]
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var pa := a.get_data()
	var pb := b.get_data()
	var n := 0
	var mx := 0
	var i := 0
	while i < pa.size():
		var m := maxi(maxi(absi(pa[i] - pb[i]), absi(pa[i + 1] - pb[i + 1])), maxi(absi(pa[i + 2] - pb[i + 2]), absi(pa[i + 3] - pb[i + 3])))
		if m > tol:
			n += 1
		mx = maxi(mx, m)
		i += 4
	return [n, mx]
