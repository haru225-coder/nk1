class_name CombatHandler extends RefCounted

## ═══════════════════════════════════════════════════════════
## CombatHandler — 战斗意图处理器
## ═══════════════════════════════════════════════════════════
##
## 职责：
##   1. 验证战斗前置条件（舰队状态、敌方数据）
##   2. 初始化 CombatState
##   3. 返回 combat_state + enemy_data 供 UI 层启动战斗
##   4. 战斗结束后统一结算（战利品/惩罚 → LootResolver + GameState）
##
## 战斗流程：
##   IntentResolver → CombatHandler.handle() → 返回 IntentResult(combat_state, enemy_data)
##   SeaEventController 读取 result.data，启动 CombatSessionController
##   CombatSessionController 完成后 → CombatHandler.resolve_combat_result() 统一结算
##
## ═══════════════════════════════════════════════════════════

## ── 常量 ───────────────────────────────────────────────────

const FAME_PENALTY_DEFEATED := -15
const FAME_PENALTY_FLED := -5
const HP_PENALTY_SUNK := -30.0
const HP_PENALTY_CAPTURED := -15.0

## ── 意图处理入口 ───────────────────────────────────────────

func handle(intent: Intent) -> IntentResult:
	# 幂等检查已由 IntentResolver.resolve() 统一处理

	# 验证玩家舰队状态
	var fleet := GameState.fleet
	if fleet == null or fleet.ships.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_COMBAT_NO_FLEET, IntentTypes.COMBAT_REQUEST)

	var flagship := fleet.get_flagship()
	if flagship == null or flagship.hp <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_COMBAT_FLAGSHIP_DESTROYED, IntentTypes.COMBAT_REQUEST)

	# 读取敌方数据（兼容 parameters 和 context 两种来源）
	var enemy_data: Dictionary = intent.parameters.get("combat_enemy", {})
	if enemy_data.is_empty():
		enemy_data = intent.context.get("combat_enemy", {})
	if enemy_data.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_COMBAT_NO_ENEMY, IntentTypes.COMBAT_REQUEST)

	# 初始化 CombatState（纯数据模型，不涉及场景树）
	var combat_state := CombatState.new()
	combat_state.initialize(enemy_data)

	# 返回成功，data 中携带 combat_state 和 enemy_data 供 UI 层使用
	# 调用方（SeaEventController）读取 data 后启动 CombatSessionController
	var r := IntentResult.ok({
		"combat_state": combat_state,
		"enemy_data": enemy_data,
		"enemy_name": combat_state.enemy_name,
	}, TextKeys.INTENT_COMBAT_STARTED)
	r.type = IntentTypes.COMBAT_REQUEST
	return r

## ── 战斗结算 ───────────────────────────────────────────────
##
## 战斗结束后由 SeaEventController 调用。
## 统一处理：战利品分配（LootResolver）→ 资源变更（GameState）→ 惩罚。
##
## 参数：
##   combat_state — 已完成的战斗状态（含 victory_type、双方舰队状态）
##   enemy_data   — 敌方原始数据（含 loot_money、loot_cargo）

static func resolve_combat_result(combat_state: CombatState, enemy_data: Dictionary) -> Dictionary:
	var victory_type: int = combat_state.victory_type
	var is_player_win := victory_type in [
		CombatState.VictoryType.SUNK,
		CombatState.VictoryType.CAPTURED,
		CombatState.VictoryType.DUEL_VICTORY,
	]

	var result := {
		"victory_type": victory_type,
		"is_player_win": is_player_win,
		"loot": {},
		"narration": combat_state.get_victory_narration(),
	}

	if is_player_win:
		# 胜利：通过 LootResolver 统一分配战利品
		var loot := LootResolver.resolve(victory_type, enemy_data, combat_state)
		LootResolver.apply_loot(loot)
		result["loot"] = loot
	else:
		# 战败/撤退惩罚
		match victory_type:
			CombatState.VictoryType.DEFEATED_SUNK:
				GameState.modify_fame(FAME_PENALTY_DEFEATED)
				GameState.modify_hp(HP_PENALTY_SUNK)
			CombatState.VictoryType.DEFEATED_CAPTURED:
				GameState.modify_fame(FAME_PENALTY_DEFEATED)
				GameState.modify_hp(HP_PENALTY_CAPTURED)
			CombatState.VictoryType.FLED:
				GameState.modify_fame(FAME_PENALTY_FLED)

	StoryEventChainEngine.check_triggers("battle_end", {
		"victory_type": victory_type,
		"is_player_win": is_player_win,
		"battle_result": result,
		"enemy_data": enemy_data,
	})
	return result
