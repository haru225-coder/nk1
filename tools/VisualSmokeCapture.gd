extends SceneTree

const OUTPUT_DIR := "res://build/visual-smoke"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	root.size = Vector2i(1280, 720)
	var app_scene := load(ResourcePaths.SCENE_APP_ROOT) as PackedScene
	if app_scene == null:
		push_error("Visual smoke: AppRoot scene missing")
		quit(1)
		return
	var app := app_scene.instantiate()
	root.add_child(app)
	await _settle(8)
	if not _save("title.png"):
		quit(1)
		return

	var narrative = app.call("get_narrative")
	if narrative != null and narrative.has_method("load_scene"):
		narrative.call("load_scene", GameManager.get_port_scene_id("quanzhou"))
	await _settle(12)
	var cutscene = app.call("get_cutscene_player")
	if cutscene != null and cutscene.has_method("is_playing") and cutscene.call("is_playing"):
		cutscene.call("skip")
		await _settle(4)
	if not _save("quanzhou-port.png"):
		quit(1)
		return

	app.call("show_voyage")
	await _settle(12)
	if not _save("world-map.png"):
		quit(1)
		return
	quit(0)


func _settle(frame_count: int) -> void:
	for _i in frame_count:
		await process_frame


func _save(file_name: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Visual smoke: empty viewport image for %s" % file_name)
		return false
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("Visual smoke: save failed %s err=%d" % [path, err])
		return false
	print("Visual smoke captured: ", path)
	return true
