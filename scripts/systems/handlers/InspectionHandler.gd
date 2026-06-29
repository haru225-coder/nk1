class_name InspectionHandler extends RefCounted

## 非法贸易海关罚款（验证器余额前置检查与实际扣款共享此值）
const ILLEGAL_TRADE_FINE := 30

func handle(intent: Intent) -> IntentResult:
	# 幂等检查已由 IntentResolver.resolve() 统一处理
	var violation := EncounterSystem.calculate_cargo_violation()
	match violation:
		"contraband":
			return IntentResult.error(IntentErrorCodes.INVALID_STATE, "", IntentTypes.INSPECTION_PASS)
		"illegal_trade":
			LedgerSystem.apply({
				"amount": -ILLEGAL_TRADE_FINE,
				"source": "encounter",
				"reason": "sea_patrol_fine",
				"actor": "InspectionHandler",
			}, intent.id)
			GameState.modify_fame(-2)
			var fined := IntentResult.ok({"fine": ILLEGAL_TRADE_FINE}, TextKeys.INTENT_INSPECTION_FINED)
			fined.type = IntentTypes.INSPECTION_PASS
			return fined
		_:
			GameState.modify_fame(1)
			var cleared := IntentResult.ok({}, TextKeys.INTENT_INSPECTION_CLEARED)
			cleared.type = IntentTypes.INSPECTION_PASS
			return cleared
