class_name HireCrewHandler extends RefCounted

## ── 招募默认值常量 ───────────────────────────────────────
const DEFAULT_COST_PER_CREW := 10          ## 默认每名水手招募费用

func handle(intent: Intent) -> IntentResult:
	var cost_per_crew := DEFAULT_COST_PER_CREW
	var crew_count := int(intent.parameters.get("crew_count", 0))
	var space := GameState.max_crew - GameState.crew_count

	if crew_count <= 0 or intent.parameters.get("recruit_max", false):
		var balance := LedgerSystem.get_balance()
		if balance < cost_per_crew:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.HIRE_CREW)
		var max_affordable_cost := mini(space * cost_per_crew, balance - (balance % cost_per_crew))
		crew_count = max_affordable_cost / cost_per_crew
	else:
		crew_count = mini(crew_count, space)

	if crew_count <= 0:
		return IntentResult.error(IntentErrorCodes.CREW_LIMIT_REACHED, "", IntentTypes.HIRE_CREW)

	var total_cost := crew_count * cost_per_crew

	var tx := {
		"amount": -total_cost,
		"source": "gameplay",
		"reason": "hire_crew_%d" % crew_count,
		"actor": "HireCrewHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.HIRE_CREW)

	GameState.modify_crew(crew_count)
	var r := IntentResult.ok({
		"crew_count": crew_count,
		"cost_per_crew": cost_per_crew,
		"total_cost": total_cost,
		"crew_total": GameState.crew_count,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_HIRE_CREW_SUCCESS)
	r.type = IntentTypes.HIRE_CREW
	return r