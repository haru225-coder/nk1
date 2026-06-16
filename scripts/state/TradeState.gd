class_name TradeState extends RefCounted

## 贸易与海关管理模块

var pu_attention: int = 0
var has_customs_permit: bool = false

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
	for key in CargoSystem.get_keys():
		var amt = CargoSystem.get_amount(key)
		if amt <= 0: continue
		var g_data = resolve_good_func.call(key)
		if g_data.is_empty(): continue
		var sell_price = calc_price_func.call(port_id, g_data)
		if sell_goods(key, amt, sell_price):
			total_earned += amt * sell_price
	return {"success": true, "earned": total_earned, "msg": "全部抛售，获利 %d 钱！" % total_earned}

func customs_inspection() -> Dictionary:
	var result = {"passed": true, "msg": "", "confiscated": false, "was_smuggling": false}
	if has_customs_permit:
		result["passed"] = true
		result["msg"] = "【市舶司验引】出示了泉州货引，缴纳了正常抽解，安全放行。"
		has_customs_permit = false
	else:
		result["was_smuggling"] = true
		if pu_attention > 50:
			result["passed"] = false
			result["confiscated"] = true
			result["msg"] = "【严重警告】蒲氏暗桩早已盯上你！市舶司当场查扣所有无证货物，并处于巨额罚款！"
			var b = LedgerSystem.get_balance()
			var fine = min(b, 500)
			if fine > 0:
				LedgerSystem.apply({"amount": -fine, "source": "system", "reason": "customs_fine", "actor": "GameState"})
			CargoSystem.clear_all()
		else:
			if LedgerSystem.get_balance() >= 50:
				result["passed"] = true
				result["msg"] = "【惊险过关】没有货引，但蒲氏目前并未留意到你，你塞了 50 钱贿赂小吏，强行出港。"
				LedgerSystem.apply({"amount": -50, "source": "gameplay", "reason": "bribe", "actor": "GameState"})
				pu_attention += 20
			else:
				result["passed"] = false
				result["msg"] = "【遣返】你不仅没有货引，连塞给小吏的 50 钱都拿不出！小吏毫不客气地把你轰回了港口。"
	inspection_result.emit(result)
	return result
