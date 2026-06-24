class_name BuyIntelHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var event_index := int(intent.parameters.get("event_index", -1))
	var tier := int(intent.parameters.get("tier", 0))
	var total_cost := int(intent.parameters.get("total_cost", 0))

	var tx := {
		"amount": -total_cost,
		"source": "gameplay",
		"reason": "tavern_rumor_tier_%d" % tier,
		"actor": "BuyIntelHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", "buy_intel")

	if not TradeEventGenerator.mark_rumor_purchased(event_index):
		LedgerSystem.apply({
			"amount": total_cost,
			"source": "gameplay",
			"reason": "tavern_rumor_rollback",
			"actor": "BuyIntelHandler",
		}, intent.id + ":rollback")
		return IntentResult.error(IntentErrorCodes.INTEL_ALREADY_PURCHASED, "", "buy_intel")

	var rumor := TradeEventGenerator.get_event_at(event_index)
	var r := IntentResult.ok({
		"tier": tier,
		"total_cost": total_cost,
		"event_index": event_index,
		"port_name": rumor.get("port_name", ""),
		"days_left": rumor.get("days_left", 0),
		"balance": LedgerSystem.get_balance(),
	}, "intent.buy_intel.success")
	r.type = "buy_intel"
	return r