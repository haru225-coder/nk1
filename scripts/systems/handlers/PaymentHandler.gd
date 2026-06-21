class_name PaymentHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	var amount = int(intent.parameters.get("amount", 0))
	if amount <= 0:
		return IntentResult.new(true, "payment", "intent.payment.success")
	
	var tx = {
		"amount": -amount,
		"source": "encounter",
		"reason": "payment_" + intent.target,
		"actor": "PaymentHandler"
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.new(false, "payment", "error.payment.insufficient_funds")
	
	if intent.parameters.get("confiscate", false):
		var contraband_ids := CargoSystem.get_contraband_keys()
		for good_id in contraband_ids:
			CargoSystem.remove_all_of(good_id)
	
	return IntentResult.new(true, "payment", "intent.payment.success")