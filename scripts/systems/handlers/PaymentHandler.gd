class_name PaymentHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		var r := IntentResult.ok({}, TextKeys.INTENT_PAYMENT_SUCCESS)
		r.type = IntentTypes.PAYMENT
		return r

	var tx := {
		"amount": -amount,
		"source": "encounter",
		"reason": "payment_" + intent.target,
		"actor": "PaymentHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", IntentTypes.PAYMENT)

	if intent.parameters.get("confiscate", false):
		for good_id in CargoSystem.get_contraband_keys():
			CargoSystem.remove_all_of(good_id)

	var ok := IntentResult.ok({"amount": amount, "balance": LedgerSystem.get_balance()}, TextKeys.INTENT_PAYMENT_SUCCESS)
	ok.type = IntentTypes.PAYMENT
	return ok
