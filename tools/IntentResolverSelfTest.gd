extends Node

func _ready() -> void:
	var ok := true
	IdempotencyGuard.processed_intents.clear()

	ok = ok and IntentResolver.has_handler("payment")
	ok = ok and IntentResolver.has_handler("market_buy")
	ok = ok and IntentResolver.has_handler("market_sell")
	ok = ok and IntentResolver.has_handler("bribe")
	ok = ok and IntentResolver.has_handler("trade_request")

	# PaymentHandler
	LedgerSystem.from_save_dict({"balance": 1000})
	var pay_intent := Intent.new("payment", "player", "pirate", {"amount": 100})
	var pay_result := IntentResolver.resolve(pay_intent)
	ok = ok and pay_result.success
	ok = ok and LedgerSystem.get_balance() == 900
	ok = ok and pay_result.message_key == "intent.payment.success"

	# BribeHandler
	IdempotencyGuard.processed_intents.clear()
	var bribe_intent := Intent.new("bribe", "player", "customs_officer", {"amount": 50, "attention_delta": 2})
	var bribe_result := IntentResolver.resolve(bribe_intent)
	ok = ok and bribe_result.success
	ok = ok and LedgerSystem.get_balance() == 850
	ok = ok and GameState.pu_attention == 2

	# TradeHandler market_buy
	IdempotencyGuard.processed_intents.clear()
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})
	var buy_intent := Intent.new(
		"market_buy", "player", "market",
		{"good_id": "fujian_porcelain", "amount": 1},
		{"port_id": "quanzhou"}
	)
	var buy_result := IntentResolver.resolve(buy_intent)
	ok = ok and buy_result.success
	ok = ok and CargoSystem.get_amount("fujian_porcelain") == 1
	ok = ok and LedgerSystem.get_balance() < 850

	# 未知类型走 NO_HANDLER
	var unknown := IntentResolver.resolve(Intent.new("unknown_type", "a", "b"))
	ok = ok and not unknown.success
	ok = ok and unknown.error_code == "NO_HANDLER"


	print("[IntentResolverSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)