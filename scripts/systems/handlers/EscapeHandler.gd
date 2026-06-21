class_name EscapeHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.new(false, "escape_attempt", "error.intent.duplicate")
	GameState.modify_fame(-5)
	GameState.modify_hp(-20.0)
	return IntentResult.new(true, "escape_attempt", "intent.escape.success")