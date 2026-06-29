extends Node

func _ready() -> void:
	var ok := true
	StoryEventChainEngine.reload()

	var saved_flags: Dictionary = GameState.story_flags.duplicate(true)

	GameState.set_story_flag("chapter1_complete", true)
	GameState.set_story_flag("met_lin_boyuan", true)
	GameState.story_flags.erase("met_lin_boyuan_formal")
	GameState.story_flags.erase("chain_ev_lin_boyuan_formal_fired")
	GameState.story.adjust_npc_affinity("lin_boyuan", -GameState.story.get_npc_affinity("lin_boyuan"))

	var fired: Array = StoryEventChainEngine.check_triggers("enter_port", {"port_id": "quanzhou"})
	ok = ok and fired.size() == 1
	ok = ok and GameState.has_story_flag("met_lin_boyuan_formal")
	ok = ok and GameState.has_story_flag("lin_dock_hint")
	ok = ok and GameState.story.get_npc_affinity("lin_boyuan") >= 5

	var fired_again: Array = StoryEventChainEngine.check_triggers("enter_port", {"port_id": "quanzhou"})
	ok = ok and fired_again.is_empty()

	GameState.story_flags.erase("heard_pu_rumor")
	GameState.story_flags.erase("chain_ev_pu_rumor_fired")
	GameState.set_story_flag("chapter1_complete", true)

	var day_fired: Array = StoryEventChainEngine.check_triggers("day_advance", {})
	ok = ok and day_fired.size() == 1
	ok = ok and GameState.has_story_flag("heard_pu_rumor")

	var day_again: Array = StoryEventChainEngine.check_triggers("day_advance", {})
	ok = ok and day_again.is_empty()

	GameState.story_flags = saved_flags

	print("[StoryEventChainSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)