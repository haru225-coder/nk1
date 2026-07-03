class_name FacilityResolver extends RefCounted

static func facility_available(fac: Dictionary) -> bool:
	return _story_rule_available(fac)

static func resolve_facility_scene(fac: Dictionary, port_location: String) -> String:
	var target_scene: String = fac.get("id", "")
	if target_scene.begins_with("city_"):
		var suffix := target_scene.replace("city_", "")
		target_scene = port_location + "_" + suffix
	return target_scene

static func resolve_hotspot_scene(hotspot: Dictionary, fac: Dictionary, port_location: String) -> String:
	var explicit: String = hotspot.get("scene_id", "")
	if explicit != "":
		return explicit
	return resolve_facility_scene(fac, port_location)

static func choice_available(choice: Dictionary) -> bool:
	return _story_rule_available(choice)

static func resolve_choice_style(choice: Dictionary) -> String:
	var style: String = choice.get("choice_style", "")
	if style != "":
		return style
	if choice.get("next", "") == "world_map":
		return "sail"
	return "default"

static func resolve_facility_subtitle(fac: Dictionary) -> Dictionary:
	var subtitle = fac.get("subtitle", "点击进入")
	if subtitle is String:
		return {"text": subtitle, "state": "default"}
	if subtitle is Dictionary:
		var default_text: String = subtitle.get("default", "点击进入")
		for rule in subtitle.get("rules", []):
			if _story_rule_available(rule):
				return {
					"text": rule.get("text", default_text),
					"state": rule.get("state", "default"),
				}
		return {
			"text": default_text,
			"state": subtitle.get("state", "default"),
		}
	return {"text": str(subtitle), "state": "default"}

static func _story_rule_available(rule: Dictionary) -> bool:
	var req: String = rule.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = rule.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	return true
