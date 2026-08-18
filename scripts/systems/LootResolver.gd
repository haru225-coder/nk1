class_name LootResolver extends RefCounted

## ═══════════════════════════════════════════════════════════
## LootResolver — 战利品结算系统
## 根据战斗胜利类型（击沉 vs 拿捕 vs 单挑）分配不同比例的战利品。
## ═══════════════════════════════════════════════════════════

## ── 战利品结算 ─────────────────────────────────────────────
##
## 参数：
##   victory_type  — CombatState.VictoryType 枚举值
##   enemy_data    — 敌方原始数据（来自 FleetArchetypes / encounters.json）
##   combat_state  — CombatState 实例（用于读取敌方剩余资源）
##
## 返回 Dictionary：
##   {
##     "money": int,          ## 获得的金钱
##     "cargo": Array,        ## 缴获的货物 [{id, name, amount}, ...]
##     "crew_recruited": int, ## 俘虏的水手（可转化为己方水手）
##     "narration": String,   ## 战利品播报文本
##   }

static func resolve(victory_type: int, enemy_data: Dictionary, combat: CombatState = null) -> Dictionary:
	var loot: Dictionary = {
		"money": 0,
		"cargo": [],
		"crew_recruited": 0,
		"narration": "",
	}

	match victory_type:
		CombatState.VictoryType.SUNK:
			loot = _resolve_sunk(enemy_data, combat)
		CombatState.VictoryType.CAPTURED:
			loot = _resolve_captured(enemy_data, combat)
		CombatState.VictoryType.DUEL_VICTORY:
			loot = _resolve_duel_victory(enemy_data, combat)
		_:
			loot["narration"] = "战场归于沉寂，无甚战利品可言。"

	return loot

## ── 击沉：只能捞残骸 ─────────────────────────────────────

static func _resolve_sunk(enemy_data: Dictionary, _combat: CombatState = null) -> Dictionary:
	var lines: PackedStringArray = []
	var money := 0
	var cargo: Array = []

	# 残骸资金：敌方基础的 10%~20%
	var base_money: int = enemy_data.get("loot_money", 80)
	money = int(base_money * (0.1 + randf() * 0.1))
	lines.append("船只沉没，海面漂浮着残骸……")

	if money > 0:
		lines.append("从残骸中打捞到 [color=#ffd700]%d[/color] 钱。" % money)

	# 残骸货物：概率低，量少
	var loot_cargo: Array = enemy_data.get("loot_cargo", [])
	for item in loot_cargo:
		if randf() < 0.25:  # 25% 概率捞到
			var salvage_amount := maxi(1, int(item.get("amount", 1) * 0.2))
			cargo.append({
				"id": item.get("id", ""),
				"name": item.get("name", "货物"),
				"amount": salvage_amount,
			})
			lines.append("打捞到 %s × %d。" % [item.get("name", "货物"), salvage_amount])

	if cargo.is_empty() and money <= 0:
		lines.append("什么也没捞到。")

	# 击沉无俘虏
	return {
		"money": money,
		"cargo": cargo,
		"crew_recruited": 0,
		"narration": "\n".join(lines),
	}

## ── 拿捕：完整缴获 ─────────────────────────────────────────

static func _resolve_captured(enemy_data: Dictionary, combat: CombatState = null) -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("【拿捕战利品】你接管了敌舰！搜刮船舱……")

	var money := 0
	var cargo: Array = []
	var crew_recruited := 0

	# 拿捕资金：敌方基础的 60%~80%
	var base_money: int = enemy_data.get("loot_money", 80)
	money = int(base_money * (0.6 + randf() * 0.2))
	if money > 0:
		lines.append("缴获船载资金 [color=#ffd700]%d[/color] 钱。" % money)

	# 拿捕货物：80% 概率获得完整货物
	var loot_cargo: Array = enemy_data.get("loot_cargo", [])
	for item in loot_cargo:
		if randf() < 0.8:
			var amount: int = item.get("amount", 1)
			cargo.append({
				"id": item.get("id", ""),
				"name": item.get("name", "货物"),
				"amount": amount,
			})
			lines.append("缴获 %s × %d。" % [item.get("name", "货物"), amount])

	# 俘虏水手：敌方剩余水手的 30%~50%
	if combat != null and is_instance_valid(combat.enemy_fleet):
		var enemy_max_crew: int = combat.enemy_fleet.get_max_crew()
		crew_recruited = maxi(0, int(enemy_max_crew * (0.3 + randf() * 0.2)))
		if crew_recruited > 0:
			lines.append("俘虏 %d 名敌方水手，可编入己方船队。" % crew_recruited)

	if cargo.is_empty() and money <= 0:
		lines.append("船舱空空如也。")

	return {
		"money": money,
		"cargo": cargo,
		"crew_recruited": crew_recruited,
		"narration": "\n".join(lines),
	}

## ── 单挑获胜：全胜缴获 ─────────────────────────────────────

static func _resolve_duel_victory(enemy_data: Dictionary, combat: CombatState = null) -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("【单挑全胜】敌将阵亡，敌舰群龙无首，全部缴获！")

	var money := 0
	var cargo: Array = []
	var crew_recruited := 0

	# 单挑资金：100% 敌方资金
	var base_money: int = enemy_data.get("loot_money", 80)
	money = base_money
	if money > 0:
		lines.append("缴获全部船载资金 [color=#ffd700]%d[/color] 钱。" % money)

	# 单挑货物：100% 获得全部货物
	var loot_cargo: Array = enemy_data.get("loot_cargo", [])
	for item in loot_cargo:
		var amount: int = item.get("amount", 1)
		cargo.append({
			"id": item.get("id", ""),
			"name": item.get("name", "货物"),
			"amount": amount,
		})
		lines.append("缴获 %s × %d。" % [item.get("name", "货物"), amount])

	# 单挑俘虏：更多
	if combat != null and is_instance_valid(combat.enemy_fleet):
		var enemy_max_crew: int = combat.enemy_fleet.get_max_crew()
		crew_recruited = maxi(0, int(enemy_max_crew * (0.5 + randf() * 0.2)))
		if crew_recruited > 0:
			lines.append("俘虏 %d 名敌方水手，全部编入己方。" % crew_recruited)

	return {
		"money": money,
		"cargo": cargo,
		"crew_recruited": crew_recruited,
		"narration": "\n".join(lines),
	}

## ── 应用战利品到 GameState ─────────────────────────────────
##
## 由调用方（SeaEventController 或 CombatSessionController）在播报后调用。

static func apply_loot(loot: Dictionary, intent_id: String = "") -> void:
	if loot.is_empty():
		return
	if intent_id.is_empty():
		intent_id = "loot_%s" % [Time.get_ticks_usec()]

	# 资金
	var money: int = loot.get("money", 0)
	if money > 0:
		# INTENT_DEFERRED: 战斗战利品金钱 — 战斗结算路径，暂不迁移至 Intent
		LedgerSystem.apply({
			"amount": money,
			"source": "combat_loot",
			"reason": "combat_victory",
			"actor": "LootResolver",
		}, intent_id)

	# 货物
	var cargo_items: Array = loot.get("cargo", [])
	for item in cargo_items:
		var good_id: String = item.get("id", "")
		var amount: int = item.get("amount", 0)
		if good_id == "" or amount <= 0:
			continue
		var space := CargoSystem.get_available_space()
		if space <= 0:
			break
		CargoSystem.add_item(good_id, mini(amount, space))

	# 俘虏水手
	var recruited: int = loot.get("crew_recruited", 0)
	if recruited > 0:
		GameState.modify_crew(recruited)

	# 战败惩罚：如果 loot 中有负值说明己方被拿捕
	var lost_money: int = loot.get("lost_money", 0)
	if lost_money > 0:
		# INTENT_DEFERRED: 战斗战败罚金 — 战斗结算路径，暂不迁移至 Intent
		LedgerSystem.apply({
			"amount": -lost_money,
			"source": "combat_defeat",
			"reason": "combat_defeat",
			"actor": "LootResolver",
		}, intent_id + ":defeat")

## ── 世界事件拾取（非战斗）──────────────────────────────────
##
## 海上宝箱、漂流物等非战斗世界事件的资源结算。
## 与 apply_loot 共用 LedgerSystem/CargoSystem 底层，但 source 标记为 world_event，
## 便于审计区分战斗战利品与世界拾取。

static func apply_world_pickup(money: int, cargo_good_id: String = "", cargo_amount: int = 0, intent_id: String = "") -> Dictionary:
	var result := {"money": 0, "cargo": ""}
	if intent_id.is_empty():
		intent_id = "pickup_%s" % [Time.get_ticks_usec()]
	if money > 0:
		# INTENT_DEFERRED: 世界事件拾取金钱 — 非战斗路径，暂不迁移至 Intent
		LedgerSystem.apply({
			"amount": money,
			"source": "world_event",
			"reason": "world_pickup",
			"actor": "LootResolver",
		}, intent_id)
		result["money"] = money
	if cargo_good_id != "" and cargo_amount > 0:
		if CargoSystem.add_item(cargo_good_id, cargo_amount):
			result["cargo"] = cargo_good_id
	return result
