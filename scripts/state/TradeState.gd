class_name TradeState extends RefCounted

## 贸易与海关管理模块

## ── 海关检查常量 ─────────────────────────────────────────
## 蒲氏暗桩警戒值达到此阈值时，海关查扣走私并重罚（验证器与海关检查共享）
const CUSTOMS_BLOCKED_ATTENTION := 15
const CUSTOMS_FINE_MAX := 200             ## 海关走私最大罚款金额
const CUSTOMS_BRIBE_AMOUNT := 50          ## 无货引时塞给小吏的贿赂金额
const CUSTOMS_BRIBE_ATTENTION_DELTA := 3  ## 贿赂带来的蒲氏关注度增量

var pu_attention: int = 0
var has_customs_permit: bool = false

func to_dict() -> Dictionary:
	return {"pu_attention": pu_attention, "has_customs_permit": has_customs_permit}

func from_dict(d: Dictionary) -> void:
	pu_attention = maxi(0, int(d.get("pu_attention", 0)))
	has_customs_permit = bool(d.get("has_customs_permit", false))

signal inspection_result(result: Dictionary)

func sell_goods(item_id: String, amount: int, _price_per_unit: int) -> bool:
	var result: IntentResult = IntentResolver.resolve(Intent.new(
		IntentTypes.MARKET_SELL, "player", "market",
		{"good_id": item_id, "amount": amount},
		{"port_id": GameState.last_port}
	))
	return result.success

func sell_all_cargo(port_id: String, resolve_good_func: Callable, _calc_price_func: Callable) -> Dictionary:
	if CargoSystem.is_empty():
		return {"success": false, "earned": 0, "msg": "船舱空空如也，无货可卖。"}
	var total_earned: int = 0
	var any_sold := false
	for key in CargoSystem.get_keys().duplicate():
		var amt := CargoSystem.get_amount(key)
		if amt <= 0:
			continue
		var g_data: Dictionary = resolve_good_func.call(key)
		if g_data.is_empty():
			continue
		var good_id: String = g_data.get("id", key)
		var result: IntentResult = IntentResolver.resolve(Intent.new(
			IntentTypes.MARKET_SELL, "player", "market",
			{"good_id": good_id, "amount": amt},
			{"port_id": port_id}
		))
		if result.success:
			total_earned += int(result.data.get("revenue", 0))
			any_sold = true
	if any_sold:
		return {"success": true, "earned": total_earned, "msg": "全部抛售，获利 %d 钱！" % total_earned}
	return {"success": false, "earned": 0, "msg": "抛售失败，未能完成任何交易。"}

func customs_inspection() -> Dictionary:
	var result = {"passed": true, "msg": "", "confiscated": false, "was_smuggling": false}
	if has_customs_permit:
		result["passed"] = true
		result["msg"] = "【市舶司验引】出示了泉州货引，缴纳了正常抽解，安全放行。"
		has_customs_permit = false
	else:
		result["was_smuggling"] = true
		if pu_attention >= CUSTOMS_BLOCKED_ATTENTION:
			result["passed"] = false
			result["confiscated"] = true
			result["msg"] = "【严重警告】蒲氏暗桩早已盯上你！市舶司当场查扣所有无证货物，并处以巨额罚款！"
			var b = LedgerSystem.get_balance()
			var fine = min(b, CUSTOMS_FINE_MAX)
			if fine > 0:
				# INTENT_DEFERRED: 严重走私海关罚款 — 非贿赂路径，暂不迁移至 Intent
				LedgerSystem.apply({
					"amount": -fine,
					"source": "system",
					"reason": "customs_fine",
					"actor": "GameState",
				}, "customs_fine_%s" % Time.get_ticks_usec())
			CargoSystem.clear_all()
		else:
			var bribe_intent := Intent.new(
				IntentTypes.BRIBE, "player", "customs_officer",
				{"amount": CUSTOMS_BRIBE_AMOUNT, "attention_delta": CUSTOMS_BRIBE_ATTENTION_DELTA, "smuggling_departure": true},
				{"customs_departure": true}
			)
			var bribe_result := IntentResolver.resolve(bribe_intent)
			if bribe_result.success:
				result["passed"] = true
				result["msg"] = "【惊险过关】没有货引，你塞了五十贯给小吏，趁盘查间隙摸出港。"
			else:
				result["passed"] = false
				if bribe_result.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS:
					result["msg"] = "【遣返】你不仅没有货引，连塞给小吏的五十贯都拿不出！小吏把你轰回了港口。"
				else:
					result["msg"] = "【遣返】市舶司验引未通过，无法出港。"
	inspection_result.emit(result)
	return result
