extends Node

# [C2-STABLE] -> [C3-STABLE]
# ECONOMIC CORE IS FROZEN. NO ARCHITECTURAL CHANGES ALLOWED.
# DO NOT MODIFY WITHOUT PHASE UPGRADE

var _balance: int = 1000

func _ready() -> void:
	# 过渡期：如果 GameState 还活着且有 money，从中初始化
	if GameState.get("money") != null:
		_balance = GameState.get("money")

func get_balance() -> int:
	return _balance

func apply(transaction: Dictionary, intent_id: String = "") -> bool:
	if not IdempotencyGuard.check_and_record(intent_id):
		push_error("[LedgerSystem] 幂等性拦截: 拒绝重复执行 -> intent_id: " + intent_id)
		return false

	if transaction.size() != 4 or not transaction.has("amount") or not transaction.has("source") or not transaction.has("reason") or not transaction.has("actor"):
		push_error("[LedgerSystem] 交易拒绝: 必须且只能包含(amount, source, reason, actor)四个字段。交易内容: " + str(transaction))
		return false
		
	var amount = transaction.get("amount", 0)
	var source = transaction.get("source")
	var reason = transaction.get("reason")
	var actor = transaction.get("actor")
	
	if amount < 0 and _balance + amount < 0:
		print("[LedgerSystem] 交易失败: 余额不足。 需要: ", -amount, " 只有: ", _balance)
		return false
		
	_balance += amount
	
	# Audit Log
	print("[Ledger] amount=%+d source=%s reason=%s actor=%s balance=%d" % [
		amount, source, reason, actor, _balance
	])
	
	return true
