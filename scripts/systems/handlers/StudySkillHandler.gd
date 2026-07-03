class_name StudySkillHandler extends RefCounted

const STUDY_BASE_THRESHOLD := 55
const STUDY_AFFINITY_BONUS_PER_POINT := 1

## skill_id → 学成效果
const SKILL_EFFECTS := {
	"skill_boarding_tactics": {
		"story_flag": "learned_skill_boarding_tactics",
		"swordplay": 2,
	},
	"skill_navigation_wisdom": {
		"story_flag": "learned_skill_navigation_wisdom",
		"maneuverability": 2,
	},
}

func handle(intent: Intent) -> IntentResult:
	var npc_id := str(intent.target)
	if npc_id.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_STUDY_NO_NPC, IntentTypes.STUDY_SKILL)

	var npc_data := GameManager.get_npc_data(npc_id)
	if npc_data.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_STUDY_UNKNOWN_NPC, IntentTypes.STUDY_SKILL)

	var skill_id := str(intent.parameters.get("skill_id", npc_data.get("skill_to_teach", "")))
	if skill_id.is_empty() or not SKILL_EFFECTS.has(skill_id):
		return IntentResult.error(IntentErrorCodes.VALIDATION_ERROR, TextKeys.ERROR_STUDY_INVALID_SKILL, IntentTypes.STUDY_SKILL)

	var effects: Dictionary = SKILL_EFFECTS[skill_id]
	var learned_flag := str(effects.get("story_flag", ""))
	if learned_flag != "" and GameState.has_story_flag(learned_flag):
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_STUDY_ALREADY_LEARNED, IntentTypes.STUDY_SKILL)

	var threshold: int = int(npc_data.get("affinity_threshold", 30))
	var affinity: int = GameState.story.get_npc_affinity(npc_id)
	if affinity < threshold:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_STUDY_AFFINITY_LOW, IntentTypes.STUDY_SKILL)

	var difficulty: int = int(intent.parameters.get("difficulty", 0))
	var target_score := STUDY_BASE_THRESHOLD + difficulty
	var player_score := randi() % 100 + (affinity - threshold) * STUDY_AFFINITY_BONUS_PER_POINT
	var success := player_score >= target_score

	if success:
		if learned_flag != "":
			GameState.set_story_flag(learned_flag, true)
		if effects.has("swordplay"):
			GameState.modify_swordplay(int(effects["swordplay"]))
		if effects.has("maneuverability"):
			GameState.modify_maneuverability(int(effects["maneuverability"]))

	var data := {
		"npc_id": npc_id,
		"skill_id": skill_id,
		"player_score": player_score,
		"target_score": target_score,
		"learned": success,
	}
	if success:
		var r := IntentResult.ok(data, TextKeys.INTENT_STUDY_SUCCESS)
		r.type = IntentTypes.STUDY_SKILL
		return r
	var fail := IntentResult.new(false, IntentTypes.STUDY_SKILL, TextKeys.INTENT_STUDY_FAIL, data)
	return fail
