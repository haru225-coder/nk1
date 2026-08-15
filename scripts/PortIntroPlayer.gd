class_name PortIntroPlayer extends RefCounted

func show_if_needed(scene_data: Dictionary, scene_id: String, cutscene_player: Node, log_message: Callable) -> void:
	var intro := str(scene_data.get("intro", ""))
	if intro == "":
		return
	var flag := "intro_shown:" + scene_id
	if GameState.has_story_flag(flag):
		return
	GameState.set_story_flag(flag)
	if log_message.is_valid():
		log_message.call("【抵达】%s\n\n" % intro)
	if cutscene_player == null:
		return
	var port_id := str(scene_data.get("location", scene_id.replace("port_", "")))
	var cs_id: String = cutscene_player.get_cutscene_id_for("port_arrival", port_id)
	if cs_id != "":
		cutscene_player.play(cs_id)
