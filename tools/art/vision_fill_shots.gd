## lane-v2 VisionStage 补齐项截屏：静帧 / 炮焰出膛 / 水花柱顶 / 烟散。有窗口跑：
##   DISPLAY=:2 godot --path . -s res://tools/art/vision_fill_shots.gd
## 截图落 /workspace/nk1-qa-shots/vision-fill/（绝对路径，不进仓库）。另验序列帧与角花节点都在场。
extends SceneTree

const OUT_DIR := "/workspace/nk1-qa-shots/vision-fill"
const STAGE := "res://scenes/vision/VisionStage.tscn"

var _fails: Array = []
var _saved: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
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
	# 停掉自动节拍，由探针控制齐射时刻
	stage.auto_volley = false
	for _i in 60:
		await process_frame
	await _shot("01_hold")
	stage.volley()
	var fired_at: int = stage.volley_count
	for i in 5:
		await process_frame
	await _shot("02_muzzle")
	for i in 34:
		await process_frame
	await _shot("03_splash")
	for i in 16:
		await process_frame
	await _shot("04_smoke")
	_expect(fired_at == 1 and stage.volley_count == 1, "关了自动节拍仍多放了齐射：%d" % stage.volley_count)
	_finish()


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex else null
	if img == null or img.is_empty():
		_fails.append("空视口 %s（headless？请用 DISPLAY 跑）" % name)
		return
	var path := "%s/%s.png" % [OUT_DIR, name]
	if img.save_png(path) == OK:
		_saved.append(path)
		print("shot ", path)
	else:
		_fails.append("存图失败 %s" % path)


func _finish() -> void:
	for f in _fails:
		print("  ✗ ", f)
	print("vision_fill_shots %s shots=%d fails=%d" % ["OK" if _fails.is_empty() else "FAIL", _saved.size(), _fails.size()])
	quit(0 if _fails.is_empty() else 1)
