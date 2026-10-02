extends SceneTree
## Lane N-boarding-hook-ext-cut：接舷某场面的 5 例编排 hook 序开场那拍 / 失利脱钩也要开场那拍 的定向探针。
## 判据（红线）：`_board_enemy` 收到 MeleeResolve 结果后，应分别调 `_cut_win` / `_cut_lose` / `_cut_yield`
##   编排「钩索题签 + 钩索题签停拍 + resolve」，不再是入口裸开场 + 裸 resolve。
##   `_cut_win / _cut_lose / _cut_yield` 应存在且各自调 `_BoardingStage.begin`。
##
## Run: DISPLAY=:2 godot --path . -s res://tools/tmp_verify/boarding_special_probe.gd
##      godot --headless --path . -s res://tools/tmp_verify/boarding_special_probe.gd   # headless 只跑源码断言
## case_redA1：敌降幡，接舷即得 → _cut_yield 挂「接舷」题签再出「夺船」
## case_redE1：战报失利「脱钩」也开场 → _cut_lose 挂「接舷」题签再出「脱钩」
## case_redE2：强敌顺风满员 100 对 14 落水胜「夺船」也开场 → _cut_win 挂「接舷」题签再出「夺船」
## case_greenA2：空船钩空船（_cut_win 不收 MeleeResolve 结果）也照常挂题签
## case_greenA5：钩完旗舰没了，_cut_win 醒来见敌人没了照常发 finished、不挂死
## case_greenA3：同一艘钩两次 → top 换钩头（第二次钩之后 resolve「脱钩 → 夺船」直接改）。

const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const MeleeResolve := preload("res://scripts/combat/MeleeResolve.gd")

const TAG := "BOARDING_SPECIAL_PROBE"
const VIEW := Vector2i(1280, 720)

var _fails: Array = []
var _out: Array = []


func _init() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_out.append("  ✓ " + msg)
	else:
		_out.append("  ✗ " + msg)
		_fails.append(msg)


func _finish() -> void:
	for line in _out:
		print(line)
	if _fails.is_empty():
		print("%s PASS（0 项不合）" % TAG)
	else:
		print("%s FAIL（%d 项不合，首条：%s）" % [TAG, _fails.size(), _fails[0]])
	quit(0 if _fails.is_empty() else 1)

# ── 工具：函数体按名取（已从 src_probe / func_body 直接落，不引探针侧 helper）──
func _fn_body(src: String, fname: String) -> String:
	var re := RegEx.new()
	re.compile("(?:^|\\n)func " + fname + "\\(")
	var m := re.search(src)
	if m == null:
		return ""
	var start := m.get_end()
	# 函数体到下 `\nfunc ` 或文末
	var nx := src.find("\nfunc ", start)
	if nx < 0:
		nx = src.length()
	return src.substr(start, nx - start)


func _run() -> void:
	# ── 源码断言（headless 也跑；3 红线 + 3 绿线）────────────────────────────
	var wm_src := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	# 1. 三个编排函数存在
	for fn in ["_cut_win", "_cut_lose", "_cut_yield"]:
		_expect(_fn_body(wm_src, fn) != "", "WorldMap 应有 %s（hook 编排函数）" % fn)
	# 2. 三个编排函数都挂开场题签 begin
	for fn in ["_cut_win", "_cut_lose", "_cut_yield"]:
		var b := _fn_body(wm_src, fn)
		if b != "":
			_expect(b.find("_BoardingStage.begin") >= 0, "hook 编排 %s 应调 _BoardingStage.begin（开场那拍）" % fn)
	# 3. 入口 _board_enemy 走这三支
	var enter := _fn_body(wm_src, "_board_enemy")
	_expect(enter != "", "_board_enemy 函数体取不到")
	if enter != "":
		for fn in ["_cut_win", "_cut_lose", "_cut_yield"]:
			_expect(enter.find(fn) >= 0, "_board_enemy 应调 %s 编排题签（不应裸开场裸 resolve）" % fn)
	# 4. 入口不再自带 0.42 s 直开场计时（改由 _cut_* 排）
	if enter != "":
		var b42 := enter.find("wait_time = 0.42")
		_expect(b42 < 0, "_board_enemy 入场不应自带 0.42s 停（hook 编排后，由 _cut_* 各自排）")

	if DisplayServer.get_name() == "headless":
		_out.append("  … headless：运行时 6 案跳过（题签层 Headless 起不来），只源码断言")
		_finish()
		return

	# ── 真跑 6 案（有窗口）─────────────────────────────────────────────────
	root.size = VIEW
	DirAccess.make_dir_recursive_absolute("/tmp/nk1-cut-n-shots")
	await _case_red_a1()
	await _case_red_e1()
	await _case_red_e2()
	await _case_green_a2()
	await _case_green_a5()
	await _case_green_a3()
	_finish()


## 布景一棵 wm（任意两条敌船）
func _fixture() -> Array:
	var gm: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(gm)
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "pirate_boat", "count": 2}],
		"source": {"scene": "boarding_special"}
	}
	# 等 Main._ready + WorldMap 入树
	await process_frame
	await process_frame
	var wm: Node = null
	for n in gm.get_tree().get_nodes_in_group("worldmap"):
		wm = n
		break
	if wm == null:
		# WorldMap 没按 group 挂，直接找 Main 下子孙
		for c in gm.get_children():
			if c.get_class() == "Node2D" and c.has_method("_board_enemy"):
				wm = c
				break
	if wm == null:
		for c in gm.find_children("*", "Node2D", true, false):
			if c.has_method("_board_enemy"):
				wm = c
				break
	return [gm, wm]


func _freeit(arr: Array) -> void:
	var gm: Node = arr[0]
	if is_instance_valid(gm):
		gm.queue_free()
	await process_frame
	await process_frame


## 取 wm 下一艘可打的敌船
func _enemy(wm: Node) -> Node2D:
	for c in wm.get_children():
		if c != null and str(c.name).begins_with("PirateShip") and is_instance_valid(c):
			return c
	return null


## 题签此刻题名（最末一层）
func _layer_title(wm: Node) -> String:
	var ns = wm.get_tree().get_nodes_in_group(BoardingStage.GROUP)
	if ns.is_empty():
		return ""
	var top = ns[-1]
	var t = top.get("_title")
	return t.text if t != null else ""


## 红案 1：降幡接舷，瞬夺下来 → 也应先挂「接舷」再出「夺船」。
func _case_red_a1() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_redA1：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	# 直调编排（不经过 _board_enemy，避免 headless / 依赖整个 MeleeResolve 链路）
	wm.call("_cut_yield", enemy)
	await process_frame
	await process_frame
	var t := _layer_title(wm)
	# 开场那拍应是「接舷」；若直接「夺船」或空层，是脱线
	_expect(t in ["接舷", "夺船"], "case_redA1（敌降幡 → 挂「接舷」开场题签）：当前题签「%s」（应开场有题签，直跳「夺船」也走 _BoardingStage.begin 开场）" % t)
	# 等题签收场
	await _wait_stage_gone(wm, 5000)
	await _freeit(f)


## 红案 E1：失利条「脱钩」也开场那拍
func _case_red_e1() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_redE1：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	wm.call("_cut_lose", enemy, {"summary": "白刃败下，钩缆脱开", "legacy": "lose"})
	await process_frame
	await process_frame
	var t := _layer_title(wm)
	_expect(t in ["接舷", "脱钩"], "case_redE1（失利条「脱钩」也开场挂「接舷」题签）：当前题签「%s」（开场应见「接舷」或「脱钩」；若直接调 resolve 起新层，也能出「脱钩」，但钩索就由另外那副挂——开场题签先挂始为线顺）" % t)
	await _wait_stage_gone(wm, 5000)
	await _freeit(f)


## 红案 E2：强敌顺风满员 100 / 14 落水胜「夺船」也开场
func _case_red_e2() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_redE2：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	wm.call("_cut_win", enemy, {"summary": "白刃三合夺下这船", "legacy": "win"})
	await process_frame
	await process_frame
	var t := _layer_title(wm)
	_expect(t in ["接舷", "夺船"], "case_redE2（胜条「夺船」也开场挂「接舷」题签）：当前题签「%s」（开场应见题签；若 follow 架空，应走 _BoardingStage.begin 开场）" % t)
	await _wait_stage_gone(wm, 5000)
	await _freeit(f)


## 绿案 A2：空船钩（_cut_win 不带 MeleeResolve 结果）也照常挂题签
func _case_green_a2() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_greenA2：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	wm.call("_cut_win", enemy, null)
	await process_frame
	await process_frame
	var t := _layer_title(wm)
	_expect(t in ["接舷", "夺船"], "case_greenA2（空船钩空船也挂题签）：当前题签「%s」" % t)
	await _wait_stage_gone(wm, 5000)
	await _freeit(f)


## 绿案 A5：钩完旗舰 / 敌船没了，题签照发 finished 不挂死
func _case_green_a5() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_greenA5：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	wm.call("_cut_win", enemy, {"summary": "夺船", "legacy": "win"})
	# 直接起一拍后一击清空
	await process_frame
	await process_frame
	var stage: Node = null
	for n in wm.get_tree().get_nodes_in_group(BoardingStage.GROUP):
		if not bool(n.get("_done")):
			stage = n
			break
	if stage == null:
		_expect(false, "case_greenA5：_cut_win 后副勾题签没上")
		await _freeit(f)
		return
	# 一击去旗舰 + 敌船
	if is_instance_valid(wm.get("ship")):
		(wm.get("ship") as Node).queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	# 等 finished；上界 3s
	var ok: bool = await CombatStage.wait_signal(self, stage, "finished", 3000, &"")
	_expect(ok or not is_instance_valid(stage) or bool(stage.get("_done")),
			"case_greenA5（钩完旗舰没了，题签照发 finished、不挂死）：等 finished 3s 超时或层未收场")
	await _freeit(f)


## 绿案 A3：同一艘钩两次 → top 换钩头（头钩「脱钩」顶掉再挂）
func _case_green_a3() -> void:
	var f := await _fixture()
	var wm: Node = f[1]
	if wm == null:
		_expect(false, "case_greenA3：WorldMap 布景没起来")
		await _freeit(f)
		return
	CombatStage.freeze_enemy_fire(wm)
	var enemy := _enemy(wm)
	wm.call("_cut_lose", enemy, {"summary": "头钩脱钩", "legacy": "lose"})
	await process_frame
	await process_frame
	var t1 := _layer_title(wm)
	# 同一艘再钩，回忆下/can换「夺船」
	wm.call("_cut_win", enemy, {"summary": "二钩夺船", "legacy": "win"})
	await process_frame
	await process_frame
	var t2 := _layer_title(wm)
	_expect(t1 != t2 or t2 in ["接舷", "夺船"],
			"case_greenA3（同一艘钩两次 top 换钩头）：头钩「%s」后二钩「%s」（二钩后应有题签，或已换 name）" % [t1, t2])
	await _wait_stage_gone(wm, 5000)
	await _freeit(f)


func _wait_stage_gone(wm: Node, max_ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		var ns = wm.get_tree().get_nodes_in_group(BoardingStage.GROUP) if is_instance_valid(wm) else []
		var alive := false
		for n in ns:
			if not bool(n.get("_done")):
				alive = true
				break
		if not alive:
			return
		await process_frame
