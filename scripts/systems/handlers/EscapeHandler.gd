class_name EscapeHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	GameState.modify_fame(-5)
	GameState.modify_hp(-20.0)
	return IntentResult.new(true, "escape_attempt", "intent.escape.success")