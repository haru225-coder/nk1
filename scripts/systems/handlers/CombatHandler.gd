class_name CombatHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	print("\n[STUB] CombatHandler executed.")
	print("       Intent ID: ", intent.id)
	print("       Target: ", intent.target)
	print("       Context: ", intent.context)
	print("       # TODO: 移交 CombatSystem 进行战斗逻辑计算\n")
	return IntentResult.new(true, "combat_request", "intent.combat.started")
