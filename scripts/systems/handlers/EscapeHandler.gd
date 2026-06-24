class_name EscapeHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	return execute(intent)

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.error("error.intent.duplicate", "", "escape_attempt")
	GameState.modify_fame(-5)
	GameState.modify_hp(-20.0)
	var r := IntentResult.ok({}, "intent.escape.success")
	r.type = "escape_attempt"
	return r