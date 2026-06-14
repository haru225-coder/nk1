class_name EscapeHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	print("\n[STUB] EscapeHandler executed.")
	print("       Intent ID: ", intent.id)
	print("       Target: ", intent.target)
	print("       # TODO: 移交 CombatSystem 或 NavigationSystem 进行撤退检定\n")
	return IntentResult.new(true, "escape_attempt", "intent.escape.success")
