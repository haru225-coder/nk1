## lane-v2 VisionStage 补齐项截屏：静帧 / 炮焰出膛 / 水花柱顶 / 烟散。有窗口跑：
##   DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd            # 截图门禁（须出 4 张）
##   godot --headless --path . -s res://tools/art/vision_fill_shots.gd -- --contract   # 只验序列帧与角花节点
## headless 下不加 --contract 立即判红（旧写法会卡在 frame_post_draw 等到超时）。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/vision-fill/（绝对路径，不进仓库）。另验序列帧与角花节点都在场，
## 02–04 按序列帧进度取景并复核截到的是哪一帧（出膛 / 柱顶 / 塌落）；在画完的那一帧上判、当帧截，上界按墙钟（lane gd18）。
## 压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd（见 shot_gate.gd）
extends SceneTree

var OUT_DIR := ShotGate.out_dir("vision-fill")
const STAGE := "res://scenes/vision/VisionStage.tscn"
const TAG := "vision_fill_shots"
const EXPECTED_SHOTS := 4
const ShotGate := preload("res://tools/shot_gate.gd")
## 等待记账与「压帧过重 / 卡住」的分法（lane gd24，见 probe_clock 头注释「三」）
const Clock := preload("res://tools/probe_clock.gd")
## 取景帧（序列帧见 tools/art/vision_fill_gen.gd）：炮焰第 1 帧出膛、水花第 3 帧柱顶最高、第 6 帧塌落烟散
const MUZZLE_PEAK := 1
const SPLASH_PEAK := 3
const SPLASH_FALL := 6
## 等序列帧走到取景格的墙钟上界（lane gd18；原 240 帧，快机 1 s、压帧 3 fps 下 72 s，与演出时长对不上）。
## 齐射后最晚一格（水花第 6 格）约 0.42 + 0.5 s 游戏时间；每帧 delta 封顶约 0.133 s，1 fps 下也只要约 7 s
const WAIT_MS := 15000

var _fails: Array = []
var _saved: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var stage: Control = (load(STAGE) as PackedScene).instantiate()
	ShotGate.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（lane gd18）；未设不挂
	# 被测树自检（lane w26-k6 接 wave23-a9 共用面）：VisionStage 挂不出 / 挂空壳秒级判红；
	# 子层 CombatFreeze/Muzzle/Splash 在 _ready 才建（check_fields 只能勾脚本字段，勾不了节点），勾 _embers 这类 _ready 建的对象
	stage = ShotGate.start_tree_probe(STAGE, _fails, "vision_fill_shots") as Control
	if stage == null:
		_finish()
		return
	root.add_child(stage)
	for _i in 3:
		await process_frame
	if not ShotGate.check_fields(stage, {"_embers": "VisionStage.gd Parse Error / _ready 建粒子前断线"}, _fails, "vision_fill_shots"):
		_finish()
		return
	var host := stage.get_node_or_null("CombatFreeze")
	_expect(host != null, "缺 CombatFreeze")
	if host == null:
		_finish()
		return
	_expect(host.get_node_or_null("ChartFragment") != null, "海战底图未换成宋绢海图残片")
	for n in ["Muzzle0", "Muzzle1", "Muzzle2", "Splash0", "Splash1"]:
		var a := host.get_node_or_null(n) as AnimatedSprite2D
		_expect(a != null, "缺序列帧节点 %s" % n)
		if a:
			_expect(a.sprite_frames.get_frame_count("seq") == 8, "%s 帧数不是 8" % n)
	var corners := stage.get_node_or_null("PortraitPane/GiltCorners")
	_expect(corners != null and corners.get_child_count() == 4, "大裱框泥金角花不是四角")
	if _contract:
		_finish()
		return
	# 停掉自动节拍，由探针控制齐射时刻
	stage.auto_volley = false
	for _i in 60:
		await process_frame
	await _shot("01_hold")
	stage.volley()
	var fired_at: int = stage.volley_count
	# 按序列帧进度取景，不按固定帧数：帧率随负载变，数帧会拍到水花第 0 帧（lane vs1）
	var mz := host.get_node_or_null("Muzzle0") as AnimatedSprite2D
	var sp := host.get_node_or_null("Splash0") as AnimatedSprite2D
	await _shot_at("02_muzzle", func() -> bool: return mz.visible and mz.frame >= MUZZLE_PEAK, mz, MUZZLE_PEAK)
	await _shot_at("03_splash", func() -> bool: return sp.visible and sp.frame >= SPLASH_PEAK, sp, SPLASH_PEAK)
	await _shot_at("04_smoke", func() -> bool: return sp.visible and sp.frame >= SPLASH_FALL, sp, SPLASH_FALL)
	_expect(fired_at == 1 and stage.volley_count == 1, "关了自动节拍仍多放了齐射：%d" % stage.volley_count)
	_finish()


## 截「画出序列帧走到 want」的那一帧（lane gd18，照 combat_probe_stage.shot_when）：每帧画完（frame_post_draw）后
## 在已画出的状态上查 cond，成立就当帧截 root——截到的正是满足 cond 的那一帧。原先在 process 里判成立、再等下一帧
## 画完才截：压帧 300 ms 下序列帧一帧跳约 1.6 格，04_smoke 截到时 Splash0 已播完隐去（gd18 全支压帧实测红一次）。
## 相位已过（这一段一格也没画到就播完 / 越过取景段）判「错过」、满 WAIT_MS 判「超时」，两种都照截一张再判红，不挂死。
## 超时记进 probe_clock 的账（lane gd24）：红话带「压帧过重 / 卡住」那句，--json 按账填 error=wall_clock。
func _shot_at(name: String, cond: Callable, seq: AnimatedSprite2D, want: int) -> void:
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	var game_s := 0.0
	var deadline := t0 + WAIT_MS
	var seen := false
	var why := ""
	while true:
		await RenderingServer.frame_post_draw
		game_s += root.get_process_delta_time()
		if cond.call():
			break
		seen = seen or seq.visible
		if seen and (not seq.visible or seq.frame > want + 2):
			why = "%s：错过——%s 没画到第 %d–%d 格就过了（现第 %d 格 visible=%s）" % [name, seq.name, want, want + 2, seq.frame, seq.visible]
			break
		if Time.get_ticks_msec() >= deadline:
			Clock.mark(true, t0, f0, game_s, WAIT_MS)
			why = "%s：超时——%d ms 内 %s 没走到第 %d 格（现第 %d 格 visible=%s；%s）" % [
				name, WAIT_MS, seq.name, want, seq.frame, seq.visible, Clock.overrun()]
			break
	_expect(why == "", why)
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)
	if why == "":
		_expect(seq.visible and seq.frame <= want + 2, "%s：截到时 %s 已过第 %d 帧（现第 %d 帧 visible=%s）" % [name, seq.name, want + 2, seq.frame, seq.visible])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)


func _finish() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
