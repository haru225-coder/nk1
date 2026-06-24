class_name TradeState extends RefCounted

## 贸易与海关管理模块

var pu_attention: int = 0
var has_customs_permit: bool = false

func to_dict() -> Dictionary:
	return {"pu_attention": pu_attention, "has_customs_permit": has_customs_permit}

func from_dict(d: Dictionary) -> void:
	pu_attention = int(d.get("pu_attention", 0))
	has_customs_permit = d.get("has_customs_permit", false)

signal inspection_result(result: Dictionary)

func sell_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	if not CargoSystem.has_item(item_id, amount):
		return false
	var tx = {"amount": amount * price_per_unit, "source": "gameplay", "reason": "sell_goods", "actor": "GameState"}
	if LedgerSystem.apply(tx):
		return CargoSystem.remove_item(item_id, amount)
	return false

func sell_all_cargo(port_id: String, resolve_good_func: Callable, calc_price_func: Callable) -> Dictionary:
	if CargoSystem.is_empty():
		return {"success": false, "earned": 0, "msg": "船舱空空如也，无货可卖。"}
	var total_earned = 0
	var any_sold := false
	for key in CargoSystem.get_keys():
		var amt = CargoSystem.get_amount(key)
		if amt <= 0:
			continue
		var g_data = resolve_good_func.call(key)
		if g_data.is_empty():
			continue
		var sell_price = calc_price_func.call(port_id, g_data)
		if sell_goods(key, amt, sell_price):
			total_earned += amt * sell_price
			GameManager.state.market.adjust_stock(port_id, key, amt)
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
		if pu_attention >= 15:
			result["passed"] = false
			result["confiscated"] = true
			result["msg"] = "【严重警告】蒲氏暗桩早已盯上你！市舶司当场查扣所有无证货物，并处以巨额罚款！"
			var b = LedgerSystem.get_balance()
			var fine = min(b, 200)
			if fine > 0:
				LedgerSystem.apply({"amount": -fine, "source": "system", "reason": "customs_fine", "actor": "GameState"})
			CargoSystem.clear_all()
		else:
			var bribe_intent := Intent.new(
				"bribe", "player", "customs_officer",
				{"amount": 50, "attention_delta": 3, "smuggling_departure": true},
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
