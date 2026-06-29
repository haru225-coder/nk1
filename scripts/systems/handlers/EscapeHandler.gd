class_name EscapeHandler extends RefCounted

const FAME_PENALTY := -5
const HP_PENALTY := -20.0

func handle(intent: Intent) -> IntentResult:
	# 幂等检查已由 IntentResolver.resolve() 统一处理
	GameState.modify_fame(FAME_PENALTY)
	GameState.modify_hp(HP_PENALTY)
	var r := IntentResult.ok({}, TextKeys.INTENT_ESCAPE_SUCCESS)
	r.type = IntentTypes.ESCAPE_ATTEMPT
	return r
