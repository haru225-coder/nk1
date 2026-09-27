## lane-v2 VisionStage 补齐项截屏：静帧 / 炮焰出膛 / 水花柱顶 / 烟散。有窗口跑：
##   DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd            # 截图门禁（须出 4 张）
##   godot --headless --path . -s res://tools/art/vision_fill_shots.gd -- --contract   # 只验序列帧与角花节点
## headless 下不加 --contract 立即判红（旧写法会卡在 frame_post_draw 等到超时）。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/vision-fill/（绝对路径，不进仓库）。另验序列帧与角花节点都在场，
## 02–04 按序列帧进度取景并复核截到的是哪一帧（出膛 / 柱顶 / 塌落）。
extends SceneTree

var OUT_DIR := ShotGate.out_dir("vision-fill")
const STAGE := "res://scenes/vision/VisionStage.tscn"
const TAG := "vision_fill_shots"
const EXPECTED_SHOTS := 4
const ShotGate := preload("res://tools/shot_gate.gd")
## 取景帧（序列帧见 tools/art/vision_fill_gen.gd）：炮焰第 1 帧出膛、水花第 3 帧柱顶最高、第 6 帧塌落烟散
const MUZZLE_PEAK := 1
const SPLASH_PEAK := 3
const SPLASH_FALL := 6
const WAIT_CAP := 240

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
	root.add_child(stage)
	for _i in 3:
		await process_frame
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


## 等到序列帧走到 want 再截；上限 WAIT_CAP 帧，没等到照截并判红，不挂死。截完复核当帧仍在该段。
func _shot_at(name: String, cond: Callable, seq: AnimatedSprite2D, want: int) -> void:
	var n := 0
	while not cond.call() and n < WAIT_CAP:
		await process_frame
		n += 1
	var met: bool = cond.call()
	_expect(met, "%s：%d 帧内 %s 没走到第 %d 帧（现第 %d 帧 visible=%s）" % [name, WAIT_CAP, seq.name, want, seq.frame, seq.visible])
	await _shot(name)
	if met:
		_expect(seq.visible and seq.frame <= want + 2, "%s：截到时 %s 已过第 %d 帧（现第 %d 帧 visible=%s）" % [name, seq.name, want + 2, seq.frame, seq.visible])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)


func _finish() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
