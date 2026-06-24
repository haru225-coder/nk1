class_name PaymentHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	return execute(intent)

func execute(intent: Intent) -> IntentResult:
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		var r := IntentResult.ok({}, "intent.payment.success")
		r.type = "payment"
		return r

	var tx := {
		"amount": -amount,
		"source": "encounter",
		"reason": "payment_" + intent.target,
		"actor": "PaymentHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", "payment")

	if intent.parameters.get("confiscate", false):
		for good_id in CargoSystem.get_contraband_keys():
			CargoSystem.remove_all_of(good_id)

	var ok := IntentResult.ok({"amount": amount, "balance": LedgerSystem.get_balance()}, "intent.payment.success")
	ok.type = "payment"
	return ok