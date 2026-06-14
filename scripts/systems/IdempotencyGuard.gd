class_name IdempotencyGuard extends RefCounted

# [C3-STABLE]
# INTERFACE FROZEN. DO NOT ADD MORE GUARD LAYERS OR MODIFY SIGNATURE.

static var processed_intents: Dictionary = {}

static func check_and_record(intent_id: String) -> bool:
	if intent_id.is_empty():
		return true # 忽略无 ID 的请求（非意图驱动的交易，如系统初始化等）
		
	if processed_intents.has(intent_id):
		return false
		
	processed_intents[intent_id] = true
	return true
