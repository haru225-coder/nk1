class_name IdempotencyGuard extends RefCounted

# ═══════════════════════════════════════════════════════════
# IdempotencyGuard — 幂等守卫
# ═══════════════════════════════════════════════════════════
#
# 职责：防止同一 Intent 被重复执行，避免重复扣款/状态变更。
#
# 使用规则：
#   - IntentResolver.resolve() 在验证通过后、Handler 执行前调用 is_processed()
#   - Handler 执行成功后由 IntentResolver 调用 mark_processed()
#   - LedgerSystem.apply() 作为底层安全网，也会检查 intent_id
#
# 需要幂等保护的 Handler（涉及金额/不可逆状态变更）：
#   - PaymentHandler    — 金钱交易
#   - TradeHandler      — 市场买卖（通过 LedgerSystem 间接保护）
#   - BribeHandler      — 贿赂（通过 LedgerSystem 间接保护）
#   - RepairHandler     — 修理（通过 LedgerSystem 间接保护）
#   - RefitHandler      — 改装（通过 LedgerSystem 间接保护）
#   - HireCrewHandler   — 招募（通过 LedgerSystem 间接保护）
#   - BuySuppliesHandler— 补给（通过 LedgerSystem 间接保护）
#   - BuyIntelHandler   — 购买情报（通过 LedgerSystem 间接保护）
#   - CombatHandler     — 战斗初始化（CombatState 创建）
#   - InspectionHandler — 检查（罚款 + 声望变更）
#   - EscapeHandler     — 逃跑（HP + 声望惩罚）
#
# 内存管理：
#   - GameState._process() 每 60 秒调用 cleanup_old_records()
#   - SaveManager.load_game() 调用 clear_all()
#   - MAX_AGE_SECONDS 默认 1 小时，超时记录自动清理
# ═══════════════════════════════════════════════════════════

static var processed_intents: Dictionary = {}  # {intent_id: timestamp_seconds}

const MAX_AGE_SECONDS := 3600.0  ## 1小时自动过期

## 检查 intent_id 是否已处理过（只读，不记录）
static func is_processed(intent_id: String) -> bool:
	if intent_id.is_empty():
		return false
	return processed_intents.has(intent_id)

## 标记 intent_id 为已处理
static func mark_processed(intent_id: String) -> void:
	if intent_id.is_empty():
		return
	processed_intents[intent_id] = Time.get_ticks_msec() / 1000.0

## 检查并记录（原子操作，兼容旧接口）
## 返回 true = 首次处理，false = 重复
static func check_and_record(intent_id: String) -> bool:
	if intent_id.is_empty():
		return true  # 忽略无 ID 的请求（非意图驱动的交易，如系统初始化等）
	if processed_intents.has(intent_id):
		return false
	processed_intents[intent_id] = Time.get_ticks_msec() / 1000.0
	return true

## 清理超过 max_age_seconds 的旧记录
static func cleanup_old_records(max_age_seconds: float = MAX_AGE_SECONDS) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []
	for key in processed_intents:
		if now - processed_intents[key] > max_age_seconds:
			to_remove.append(key)
	for key in to_remove:
		processed_intents.erase(key)

## 完全清空（新游戏/读档时调用）
static func clear_all() -> void:
	processed_intents.clear()
