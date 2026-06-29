class_name EncounterResolver extends RefCounted

static func get_encounter_data(context: Dictionary) -> Dictionary:
	var encounters = GameManager.events_data.get("encounters", [])
	var candidates = []
	
	# Find all candidates that match the conditions
	for enc in encounters:
		var conditions = enc.get("conditions", {})
		var match_ok = true
		
		# check behavior
		if conditions.has("behavior"):
			if not conditions["behavior"] in context.get("behaviors", []):
				match_ok = false
				
		# check violation
		if conditions.has("violation"):
			if conditions["violation"] != context.get("violation", "legal"):
				match_ok = false
				
		if match_ok:
			candidates.append(enc)
			
	# fallback to default if no matches
	if candidates.is_empty():
		for enc in encounters:
			if enc.get("id") == "default_encounter":
				return _build_event_data(enc, context)
		return {}
		
	# for now, just return the first valid candidate
	# later, can sort by weight or priority
	return _build_event_data(candidates[0], context)

static func _build_event_data(enc: Dictionary, context: Dictionary) -> Dictionary:
	var presentation = enc.get("presentation", {})
	var title_key = presentation.get("title_key", "")
	var body_key = presentation.get("body_key", "")
	
	var event_data = {
		"title": GameManager.get_text(title_key),
		"body": GameManager.get_text(body_key),
		"choices": []
	}
	
	var choices = enc.get("choices", [])
	for c in choices:
		var intent_data = c.get("intent", {})
		event_data["choices"].append({
			"label": GameManager.get_text(c.get("label_key", "")),
			"intent_struct": {
				"type": intent_data.get("type", IntentTypes.IGNORE),
				"source": "player_fleet",
				"target": context.get("aggressor_id", ""),
				"parameters": intent_data.get("parameters", {}),
				"context": context
			}
		})
		
	return event_data
