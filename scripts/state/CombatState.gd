class_name CombatState extends RefCounted

## ═══════════════════════════════════════════════════════════
## CombatState — 海战回合制状态机 (Phase 4: 多船舰队版)
## 管理战斗阶段推进、战术裁决、胜负判定。
## ═══════════════════════════════════════════════════════════

enum Phase {
	ENGAGING,    ## 远距离对峙
	CLOSE_RANGE, ## 近距离交火
	BOARDING,    ## 接舷白刃战
	DUEL,        ## 提督单挑
	RESOLVED     ## 战斗结束
}

enum Tactic {
	MANEUVER,  ## 抢占T字位 (炮战)
	BOARD,     ## 全速接舷 (白刃战)
	DUEL,      ## 发起单挑 (仅接舷可用)
	FLEE       ## 撤退
}

## 决斗阶段内的出招（与 Tactic.DUEL「进入决斗」语义分离）
enum DuelAction {
	SLASH,   ## 猛攻
	DODGE,   ## 闪避
	PARRY,   ## 招架
	SPECIAL, ## 必杀（消耗气力）
}

enum VictoryType {
	NONE,           ## 战斗未结束
	SUNK,           ## 击沉敌方旗舰
	CAPTURED,       ## 拿捕敌方旗舰
	DUEL_VICTORY,   ## 单挑获胜
	FLED,           ## 成功撤退
	DEFEATED_SUNK,  ## 己方旗舰被击沉
	DEFEATED_CAPTURED, ## 己方旗舰被拿捕
}

var phase: Phase = Phase.ENGAGING
var round_number: int = 0

var player_fleet: FleetState
var enemy_fleet: FleetState

var enemy_name: String = "未知舰队"
var enemy_faction: String = ""
var enemy_combat_pref: String = "balanced"

var victory_type: VictoryType = VictoryType.NONE

## 决斗阶段状态（交互式克制矩阵）
var ki_points: int = 0
var duel_enemy_ki: int = 0
var duel_action_round: int = 0
var duel_player_wins: int = 0
var duel_enemy_wins: int = 0

## ── 核心战斗调参常量（设计调平衡时集中于此）──────────────
const BASE_CANNON_DAMAGE_PER_ARTILLERY := 8.0  ## 每门炮基础伤害
const DODGE_PER_MANEUVER := 0.04               ## 每点机动提供的闪避系数
const SWORDPLAY_POWER_COEFF := 0.15            ## 剑术对白刃战战力加成
const DAMAGE_CREW_LOSS_RATIO := 0.05           ## 炮击伤害→水手伤亡比例

## ── NK1-P6-POLISH: 战斗阈值与倍率常量 ──────────────────────
const ROLL_NOISE_CENTER := 0.5                 ## _roll 噪声中心
const ROLL_NOISE_AMPLITUDE := 0.4              ## _roll 噪声幅度
const ROLL_DEFAULT_RESULT := 0.5               ## stat 总和 ≤0 时的默认结果
const DODGE_FACTOR_MIN := 0.3                  ## 闪避因子下限
const DAMAGE_VARIANCE_BASE := 0.85             ## 伤害随机变动基准
const DAMAGE_VARIANCE_RANGE := 0.3             ## 伤害随机变动范围
const MANEUVER_SUCCESS_THRESHOLD := 0.6        ## 抢占T字位成功阈值
const MANEUVER_PARTIAL_THRESHOLD := 0.3        ## 机动对峙（部分成功）阈值
const MANEUVER_WIN_PLAYER_MULT := 1.5          ## 机动成功时玩家伤害倍率
const MANEUVER_WIN_ENEMY_MULT := 0.5           ## 机动成功时敌方伤害倍率
const MANEUVER_FAIL_PLAYER_MULT := 0.6         ## 机动失败时玩家伤害倍率
const MANEUVER_FAIL_ENEMY_MULT := 1.3          ## 机动失败时敌方伤害倍率
const MANEUVER_DEFENDER_BONUS := 5             ## 机动判定中防御方加值
const FLEE_SUCCESS_THRESHOLD := 0.5            ## 撤退成功阈值
const FLEE_PLAYER_DEFENDER_BONUS := 3          ## 玩家撤退判定中防御方加值
const FLEE_ENEMY_DEFENDER_BONUS := 10          ## 敌方撤退判定中防御方加值
const FLEE_FAIL_PENALTY_MULT := 1.2            ## 撤退失败惩罚伤害倍率
const FLEE_ENEMY_FAIL_BONUS_MULT := 1.5        ## 敌方撤退失败时玩家追击伤害倍率
const BOARDING_MIN_CASUALTIES := 3             ## 白刃战最少伤亡数
const BOARDING_CASUALTY_RATIO := 0.04          ## 白刃战伤亡占总战力比例
const SWORDPLAY_BONUS_THRESHOLD := 5           ## 剑术加成触发阈值
const SWORDPLAY_BONUS_RATIO := 0.3             ## 剑术加成额外击杀比例
const DUEL_ROUNDS := 3                         ## 单挑回合数
const DUEL_DEFENDER_BONUS := 2                 ## 单挑判定中防御方加值
const DUEL_WIN_THRESHOLD := 0.6                ## 单挑回合获胜阈值
const DUEL_DRAW_THRESHOLD := 0.3               ## 单挑回合平局阈值
const DUEL_DRAW_CREW_LOSS_RATIO := 0.05        ## 单挑平局水手损失比例
const DUEL_KI_MAX := 3                         ## 气力上限
const DUEL_KI_SPECIAL_COST := 3                ## 必杀消耗气力
const DUEL_KI_GAIN_ON_WIN := 1                 ## 克制获胜积攒气力
const DUEL_CLASH_CREW_LOSS := 5                ## 单招落败水手损失
const ENEMY_AI_FLEE_HP_RATIO := 0.3            ## 敌方AI撤退的HP比例阈值
const ENEMY_AI_MANEUVER_CREW_RATIO := 0.3      ## 敌方AI转机动的船员比例阈值
const ENEMY_AI_RANDOM_BOARD_CHANCE := 0.4      ## 敌方AI随机接舷概率
const DEFAULT_ENEMY_DURABILITY := 80.0         ## 敌方默认耐久
const DEFAULT_ENEMY_CREW := 40                 ## 敌方默认船员
const DEFAULT_ENEMY_ARTILLERY := 3             ## 敌方默认炮数
const DEFAULT_ENEMY_SWORDPLAY := 2             ## 敌方默认剑术
const DEFAULT_ENEMY_MANEUVER := 4              ## 敌方默认机动

## ── 初始化 ───────────────────────────────────────────────

func initialize(enemy_data: Dictionary) -> void:
	player_fleet = GameState.fleet
	
	enemy_fleet = FleetState.new()
	enemy_fleet.ships.clear()
	
	enemy_name = enemy_data.get("name", "敌方舰队")
	enemy_faction = enemy_data.get("faction", "")
	enemy_combat_pref = enemy_data.get("combat_preference", "balanced")
	
	var e_ships: Array = enemy_data.get("ships", [])
	if e_ships.is_empty(): e_ships = [enemy_data.get("ship", {})]
		
	for i in range(e_ships.size()):
		var e_data = e_ships[i]
		var s = ShipState.new()
		s.name = "敌旗舰" if i == 0 else ("敌僚舰" + str(i))
		s.max_hp = e_data.get("durability", DEFAULT_ENEMY_DURABILITY)
		s.hp = s.max_hp
		s.max_crew = e_data.get("crew", DEFAULT_ENEMY_CREW)
		s.crew = s.max_crew
		s.artillery = e_data.get("artillery", DEFAULT_ENEMY_ARTILLERY)
		s.swordplay = e_data.get("swordplay", DEFAULT_ENEMY_SWORDPLAY)
		s.maneuverability = e_data.get("maneuverability", DEFAULT_ENEMY_MANEUVER)
		enemy_fleet.ships.append(s)

## ── 战术选择入口 ─────────────────────────────────────────

func get_available_tactics() -> Array[Tactic]:
	var tactics: Array[Tactic] = []
	match phase:
		Phase.ENGAGING:
			tactics.append(Tactic.MANEUVER)
			tactics.append(Tactic.FLEE)
			tactics.append(Tactic.BOARD)
		Phase.CLOSE_RANGE:
			tactics.append(Tactic.MANEUVER)
			tactics.append(Tactic.BOARD)
			tactics.append(Tactic.FLEE)
		Phase.BOARDING:
			tactics.append(Tactic.BOARD)
			tactics.append(Tactic.DUEL)
			tactics.append(Tactic.FLEE)
	return tactics

## ── 战术裁决 ─────────────────────────────────────────────

func execute_round(player_tactic: Tactic, enemy_tactic: Tactic = Tactic.MANEUVER) -> Dictionary:
	round_number += 1
	var narration_parts: PackedStringArray = []

	if player_tactic == Tactic.DUEL and phase == Phase.BOARDING:
		return _enter_duel_from_boarding()

	if player_tactic == Tactic.FLEE:
		return _resolve_flee()
	if enemy_tactic == Tactic.FLEE:
		narration_parts.append("【%s】试图撤退……" % enemy_name)
		var flee_roll = _roll(enemy_fleet.get_avg_maneuverability(), FLEE_ENEMY_DEFENDER_BONUS)
		if flee_roll >= FLEE_SUCCESS_THRESHOLD:
			narration_parts.append("敌方借风势脱离了战场。")
			victory_type = VictoryType.FLED
			phase = Phase.RESOLVED
			return _build_round_result(narration_parts, true)
		else:
			narration_parts.append("但未能逃脱，暴露了侧翼！")
			var bonus_dmg = _calc_cannon_damage(player_fleet.get_total_artillery(), enemy_fleet.get_avg_maneuverability(), FLEE_ENEMY_FAIL_BONUS_MULT)
			var target = _get_random_living_ship(enemy_fleet)
			if target:
				target.hp -= bonus_dmg
				narration_parts.append("你抓住机会齐射，对[%s]造成 %.0f 伤害。" % [target.name, bonus_dmg])

	_advance_phase(player_tactic, enemy_tactic)

	match phase:
		Phase.ENGAGING, Phase.CLOSE_RANGE:
			var r = _resolve_ranged_round(player_tactic, enemy_tactic)
			narration_parts.append(r)
		Phase.BOARDING:
			var r = _resolve_boarding_round(player_tactic, enemy_tactic)
			narration_parts.append(r)
		Phase.DUEL:
			var r = _resolve_duel()
			narration_parts.append(r)

	_check_victory()
	return _build_round_result(narration_parts, phase == Phase.RESOLVED)

func _advance_phase(player_tactic: Tactic, enemy_tactic: Tactic) -> void:
	match phase:
		Phase.ENGAGING:
			if player_tactic in [Tactic.MANEUVER, Tactic.BOARD]:
				phase = Phase.CLOSE_RANGE
		Phase.CLOSE_RANGE:
			if player_tactic == Tactic.BOARD or enemy_tactic == Tactic.BOARD:
				phase = Phase.BOARDING

## ── 炮战结算 ─────────────────────────────────────────────

func _resolve_ranged_round(player_tactic: Tactic, enemy_tactic: Tactic) -> String:
	var lines: PackedStringArray = []
	var p_maneuver = player_fleet.get_avg_maneuverability()
	var e_maneuver = enemy_fleet.get_avg_maneuverability()

	if player_tactic == Tactic.MANEUVER:
		var maneuver_success = _roll(p_maneuver, e_maneuver + MANEUVER_DEFENDER_BONUS)
		var player_dmg_mult: float = 1.0
		var enemy_dmg_mult: float = 1.0

		if maneuver_success >= MANEUVER_SUCCESS_THRESHOLD:
			lines.append("【抢占T字位成功！】舰队切入敌军航线前方，获得有利炮击角度。")
			player_dmg_mult = MANEUVER_WIN_PLAYER_MULT
			enemy_dmg_mult = MANEUVER_WIN_ENEMY_MULT
		elif maneuver_success >= MANEUVER_PARTIAL_THRESHOLD:
			lines.append("【机动对峙】双方舰队在海面周旋。")
		else:
			lines.append("【机动失败】敌舰抢占了有利位置！")
			player_dmg_mult = MANEUVER_FAIL_PLAYER_MULT
			enemy_dmg_mult = MANEUVER_FAIL_ENEMY_MULT

		var p_dmg = _calc_cannon_damage(player_fleet.get_total_artillery(), e_maneuver, player_dmg_mult)
		var e_dmg = _calc_cannon_damage(enemy_fleet.get_total_artillery(), p_maneuver, enemy_dmg_mult)
		
		var e_target = _get_random_living_ship(enemy_fleet)
		if e_target:
			e_target.hp -= p_dmg
			lines.append("我方齐射命中了[%s]，造成 %.0f 耐久伤害。" % [e_target.name, p_dmg])
			var crew_loss = maxi(0, int(p_dmg * DAMAGE_CREW_LOSS_RATIO))
			if crew_loss > 0:
				e_target.crew = maxi(0, e_target.crew - crew_loss)
				lines.append("敌方 %d 名水手伤亡。" % crew_loss)

		var p_target = _get_random_living_ship(player_fleet)
		if p_target:
			p_target.hp -= e_dmg
			lines.append("敌方炮击命中了[%s]，造成 %.0f 耐久伤害。" % [p_target.name, e_dmg])
			var crew_loss = maxi(0, int(e_dmg * DAMAGE_CREW_LOSS_RATIO))
			if crew_loss > 0:
				p_target.crew = maxi(0, p_target.crew - crew_loss)
				lines.append("己方 %d 名水手负伤。" % crew_loss)

	elif player_tactic == Tactic.BOARD:
		lines.append("【强行接舷】舰队全速冲向敌阵！")
		var incoming = _calc_cannon_damage(enemy_fleet.get_total_artillery(), p_maneuver, 1.0)
		var p_target = _get_random_living_ship(player_fleet)
		if p_target:
			p_target.hp -= incoming
			lines.append("冲锋途中[%s]遭受敌方炮击，耐久损失 %.0f。" % [p_target.name, incoming])

	return "\n".join(lines)

## ── 白刃战结算 ─────────────────────────────────────────────

func _resolve_boarding_round(player_tactic: Tactic, enemy_tactic: Tactic) -> String:
	var lines: PackedStringArray = []
	lines.append("【接舷白刃战！】双方旗舰靠帮，水手们刀兵相见！")

	var p_flag = player_fleet.get_flagship()
	var e_flag = enemy_fleet.get_flagship()

	var player_power := float(p_flag.crew) * (1.0 + float(p_flag.swordplay) * SWORDPLAY_POWER_COEFF)
	var enemy_power := float(e_flag.crew) * (1.0 + float(e_flag.swordplay) * SWORDPLAY_POWER_COEFF)
	var total_power := player_power + enemy_power

	if total_power <= 0:
		return "双方都已无力战斗……"

	var base_casualties := maxi(BOARDING_MIN_CASUALTIES, int(total_power * BOARDING_CASUALTY_RATIO))
	var player_loss := maxi(1, int(base_casualties * (enemy_power / total_power)))
	var enemy_loss := maxi(1, int(base_casualties * (player_power / total_power)))

	lines.append("我方水手勇猛冲杀，敌旗舰损失 %d 人。" % enemy_loss)
	lines.append("但己方旗舰也有 %d 名水手倒下。" % player_loss)

	if p_flag.swordplay >= SWORDPLAY_BONUS_THRESHOLD:
		var bonus := maxi(1, int(float(enemy_loss) * SWORDPLAY_BONUS_RATIO))
		enemy_loss += bonus
		lines.append("你的剑术精湛，额外击杀 %d 名敌兵！" % bonus)
	if e_flag.swordplay >= SWORDPLAY_BONUS_THRESHOLD:
		var bonus := maxi(1, int(float(player_loss) * SWORDPLAY_BONUS_RATIO))
		player_loss += bonus
		lines.append("敌方将领武艺高强，己方多损 %d 人。" % bonus)

	p_flag.crew = maxi(0, p_flag.crew - player_loss)
	e_flag.crew = maxi(0, e_flag.crew - enemy_loss)

	return "\n".join(lines)

## ── 单挑结算 ─────────────────────────────────────────────

func _resolve_duel() -> String:
	var lines: PackedStringArray = []
	lines.append("【单挑！】你拔刀跃上敌舰甲板，与敌将正面对峙！")

	var p_flag = player_fleet.get_flagship()
	var e_flag = enemy_fleet.get_flagship()

	var player_wins := 0
	var enemy_wins := 0
	var duel_rounds: Array[String] = []

	var duel_phrases_win := ["你侧身闪过横斩，反手一剑划破对手臂膀。", "刀光一闪，你的刀锋抵在敌将喉前。", "你以迅雷之势劈出一击，敌将踉跄后退。"]
	var duel_phrases_lose := ["敌将挥刀凶猛，你被迫后退一步。", "一记重劈逼得你连退三步。", "敌将刀法凌厉，你的手臂被划出一道血痕。"]
	var duel_phrases_draw := ["双刀相交，火花四溅，两人势均力敌。", "你和敌将缠斗数合，不分胜负。"]

	for i in range(DUEL_ROUNDS):
		var roll := _roll(p_flag.swordplay, e_flag.swordplay + DUEL_DEFENDER_BONUS)
		if roll >= DUEL_WIN_THRESHOLD:
			player_wins += 1
			duel_rounds.append(duel_phrases_win[i % duel_phrases_win.size()])
		elif roll >= DUEL_DRAW_THRESHOLD:
			duel_rounds.append(duel_phrases_draw[i % duel_phrases_draw.size()])
		else:
			enemy_wins += 1
			duel_rounds.append(duel_phrases_lose[i % duel_phrases_lose.size()])

	for j in range(duel_rounds.size()):
		lines.append("  第%d回合：%s" % [j + 1, duel_rounds[j]])

	lines.append("  战绩：你 %d — %d 敌将" % [player_wins, enemy_wins])

	if player_wins > enemy_wins:
		lines.append("\n【单挑获胜！】敌将落败，敌方舰队群龙无首，全线崩溃！")
		victory_type = VictoryType.DUEL_VICTORY
		phase = Phase.RESOLVED
		e_flag.hp = 0
		e_flag.crew = 0
	elif enemy_wins > player_wins:
		lines.append("\n【单挑落败！】你被击倒，己方舰队士气崩溃！")
		victory_type = VictoryType.DEFEATED_CAPTURED
		phase = Phase.RESOLVED
		p_flag.hp = 0
		p_flag.crew = 0
	else:
		lines.append("\n单挑平局！双方退回各自甲板，继续战斗。")
		p_flag.crew = maxi(0, p_flag.crew - maxi(1, int(p_flag.crew * DUEL_DRAW_CREW_LOSS_RATIO)))
		e_flag.crew = maxi(0, e_flag.crew - maxi(1, int(e_flag.crew * DUEL_DRAW_CREW_LOSS_RATIO)))

	return "\n".join(lines)

## ── 交互式决斗（太阁式克制矩阵）────────────────────────────

func _enter_duel_from_boarding() -> Dictionary:
	phase = Phase.DUEL
	ki_points = 0
	duel_enemy_ki = 0
	duel_action_round = 0
	duel_player_wins = 0
	duel_enemy_wins = 0
	var lines: PackedStringArray = [
		"【单挑！】你拔刀跃上敌舰甲板，与敌将正面对峙！",
		"猛攻克闪避，闪避克招架，招架克猛攻。积攒气力后可放必杀。",
	]
	return _build_round_result(lines, false)

func get_available_duel_actions() -> Array[DuelAction]:
	return [
		DuelAction.SLASH,
		DuelAction.DODGE,
		DuelAction.PARRY,
		DuelAction.SPECIAL,
	]

func can_use_duel_special(for_player: bool = true) -> bool:
	if for_player:
		return ki_points >= DUEL_KI_SPECIAL_COST
	return duel_enemy_ki >= DUEL_KI_SPECIAL_COST

func execute_duel_action(player_action: DuelAction, enemy_action: DuelAction) -> Dictionary:
	duel_action_round += 1
	var lines: PackedStringArray = []
	lines.append("  第%d招：你使出【%s】，敌将回以【%s】。" % [
		duel_action_round,
		get_duel_action_name(player_action),
		get_duel_action_name(enemy_action),
	])

	var effective_player := player_action
	var effective_enemy := enemy_action
	if player_action == DuelAction.SPECIAL:
		ki_points -= DUEL_KI_SPECIAL_COST
	if enemy_action == DuelAction.SPECIAL:
		duel_enemy_ki -= DUEL_KI_SPECIAL_COST

	var winner := resolve_duel_clash(effective_player, effective_enemy)
	lines.append(_duel_clash_narration(winner))

	var p_flag := player_fleet.get_flagship()
	var e_flag := enemy_fleet.get_flagship()

	if winner == 1:
		duel_player_wins += 1
		ki_points = mini(DUEL_KI_MAX, ki_points + DUEL_KI_GAIN_ON_WIN)
		if e_flag:
			e_flag.crew = maxi(0, e_flag.crew - DUEL_CLASH_CREW_LOSS)
			lines.append("克制成功！敌方旗舰损失 %d 名水手。" % DUEL_CLASH_CREW_LOSS)
	elif winner == -1:
		duel_enemy_wins += 1
		duel_enemy_ki = mini(DUEL_KI_MAX, duel_enemy_ki + DUEL_KI_GAIN_ON_WIN)
		if p_flag:
			p_flag.crew = maxi(0, p_flag.crew - DUEL_CLASH_CREW_LOSS)
			lines.append("被对方识破！己方旗舰损失 %d 名水手。" % DUEL_CLASH_CREW_LOSS)
	else:
		lines.append("双方过招，不分高下。")

	var is_over := false
	if duel_action_round >= DUEL_ROUNDS:
		is_over = _finalize_interactive_duel(lines)

	_check_victory()
	if phase == Phase.RESOLVED:
		is_over = true

	return {
		"round": duel_action_round,
		"narration": "\n".join(lines),
		"phase": phase,
		"is_over": is_over,
		"victory_type": victory_type,
		"clash_winner": winner,
		"player_action": player_action,
		"enemy_action": enemy_action,
		"ki_points": ki_points,
	}

func _finalize_interactive_duel(lines: PackedStringArray) -> bool:
	lines.append("  战绩：你 %d — %d 敌将" % [duel_player_wins, duel_enemy_wins])
	var p_flag := player_fleet.get_flagship()
	var e_flag := enemy_fleet.get_flagship()

	if duel_player_wins > duel_enemy_wins:
		lines.append("\n【单挑获胜！】敌将落败，敌方舰队群龙无首，全线崩溃！")
		victory_type = VictoryType.DUEL_VICTORY
		phase = Phase.RESOLVED
		if e_flag:
			e_flag.hp = 0
			e_flag.crew = 0
		return true
	if duel_enemy_wins > duel_player_wins:
		lines.append("\n【单挑落败！】你被击倒，己方舰队士气崩溃！")
		victory_type = VictoryType.DEFEATED_CAPTURED
		phase = Phase.RESOLVED
		if p_flag:
			p_flag.hp = 0
			p_flag.crew = 0
		return true

	lines.append("\n单挑平局！双方退回各自甲板，继续战斗。")
	phase = Phase.BOARDING
	duel_action_round = 0
	ki_points = 0
	duel_enemy_ki = 0
	if p_flag:
		p_flag.crew = maxi(0, p_flag.crew - maxi(1, int(p_flag.crew * DUEL_DRAW_CREW_LOSS_RATIO)))
	if e_flag:
		e_flag.crew = maxi(0, e_flag.crew - maxi(1, int(e_flag.crew * DUEL_DRAW_CREW_LOSS_RATIO)))
	return false

static func resolve_duel_clash(player: DuelAction, enemy: DuelAction) -> int:
	if player == DuelAction.SPECIAL and enemy == DuelAction.SPECIAL:
		return 0
	if player == DuelAction.SPECIAL:
		return 1
	if enemy == DuelAction.SPECIAL:
		return -1
	if player == enemy:
		return 0
	match player:
		DuelAction.SLASH:
			return 1 if enemy == DuelAction.DODGE else -1
		DuelAction.DODGE:
			return 1 if enemy == DuelAction.PARRY else -1
		DuelAction.PARRY:
			return 1 if enemy == DuelAction.SLASH else -1
	return 0

func _duel_clash_narration(winner: int) -> String:
	match winner:
		1:
			return "  [color=#88ff88]完美克制！[/color]"
		-1:
			return "  [color=#ff8888]被对方识破！[/color]"
		_:
			return "  势均力敌，难分高下。"

func choose_enemy_duel_action() -> DuelAction:
	if duel_enemy_ki >= DUEL_KI_SPECIAL_COST and randf() < 0.3:
		return DuelAction.SPECIAL
	var options: Array[DuelAction] = [DuelAction.SLASH, DuelAction.DODGE, DuelAction.PARRY]
	return options[randi() % options.size()]

## ── 撤退结算 ─────────────────────────────────────────────

func _resolve_flee() -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("【尝试撤退】你下令舰队全力脱离战场！")

	var flee_roll := _roll(player_fleet.get_avg_maneuverability(), enemy_fleet.get_avg_maneuverability() + FLEE_PLAYER_DEFENDER_BONUS)
	if flee_roll >= FLEE_SUCCESS_THRESHOLD:
		lines.append("帆满舵转，舰队成功甩开了敌军！")
		victory_type = VictoryType.FLED
		phase = Phase.RESOLVED
		return _build_round_result(lines, true)
	else:
		lines.append("撤退失败！敌舰拦截了退路，一轮炮击狠狠打来！")
		var penalty_dmg := _calc_cannon_damage(enemy_fleet.get_total_artillery(), player_fleet.get_avg_maneuverability(), FLEE_FAIL_PENALTY_MULT)
		var p_target = _get_random_living_ship(player_fleet)
		if p_target:
			p_target.hp -= penalty_dmg
			lines.append("[%s]遭受 %.0f 耐久伤害。" % [p_target.name, penalty_dmg])
		phase = Phase.CLOSE_RANGE
		return _build_round_result(lines, false)

## ── 敌方 AI ─────────────────────────────────────────────

func choose_enemy_tactic() -> Tactic:
	var e_flag = enemy_fleet.get_flagship()
	match enemy_combat_pref:
		"boarder":
			return Tactic.BOARD
		"gunner":
			if phase == Phase.BOARDING: return Tactic.BOARD
			return Tactic.MANEUVER
		_:
			if e_flag.hp < e_flag.max_hp * ENEMY_AI_FLEE_HP_RATIO: return Tactic.FLEE
			if e_flag.crew < e_flag.max_crew * ENEMY_AI_MANEUVER_CREW_RATIO: return Tactic.MANEUVER
			if phase == Phase.BOARDING: return Tactic.BOARD
			if phase == Phase.CLOSE_RANGE and randf() > ENEMY_AI_RANDOM_BOARD_CHANCE: return Tactic.BOARD
			return Tactic.MANEUVER

## ── 工具函数 ─────────────────────────────────────────────

func _get_random_living_ship(fleet: FleetState) -> ShipState:
	var alive = fleet.ships.filter(func(s: ShipState): return s.hp > 0)
	if alive.is_empty(): return null
	return alive.pick_random()

func _roll(attacker_stat: int, defender_stat: int) -> float:
	var total := attacker_stat + defender_stat
	if total <= 0: return ROLL_DEFAULT_RESULT
	var base := float(attacker_stat) / float(total)
	var noise := (randf() - ROLL_NOISE_CENTER) * ROLL_NOISE_AMPLITUDE
	return clampf(base + noise, 0.0, 1.0)

func _calc_cannon_damage(artillery: int, target_maneuver: int, multiplier: float) -> float:
	var base_damage := float(artillery) * BASE_CANNON_DAMAGE_PER_ARTILLERY
	var dodge_factor := clampf(1.0 - float(target_maneuver) * DODGE_PER_MANEUVER, DODGE_FACTOR_MIN, 1.0)
	var damage := base_damage * dodge_factor * multiplier
	damage *= (DAMAGE_VARIANCE_BASE + randf() * DAMAGE_VARIANCE_RANGE)
	return maxf(1.0, damage)

func _check_victory() -> void:
	if phase == Phase.RESOLVED: return
	
	var e_flag = enemy_fleet.get_flagship()
	var p_flag = player_fleet.get_flagship()
	
	if e_flag.hp <= 0:
		victory_type = VictoryType.SUNK
		phase = Phase.RESOLVED
	elif e_flag.crew <= 0:
		victory_type = VictoryType.CAPTURED
		phase = Phase.RESOLVED
	elif p_flag.hp <= 0:
		victory_type = VictoryType.DEFEATED_SUNK
		phase = Phase.RESOLVED
	elif p_flag.crew <= 0:
		victory_type = VictoryType.DEFEATED_CAPTURED
		phase = Phase.RESOLVED

func _build_round_result(narration_parts: PackedStringArray, is_over: bool) -> Dictionary:
	return {
		"round": round_number,
		"narration": "\n".join(narration_parts),
		"phase": phase,
		"is_over": is_over,
		"victory_type": victory_type,
	}

func get_phase_label() -> String:
	match phase:
		Phase.ENGAGING:    return "远距离对峙"
		Phase.CLOSE_RANGE: return "近距离交火"
		Phase.BOARDING:    return "接舷白刃战"
		Phase.DUEL:        return "提督单挑"
		Phase.RESOLVED:    return "战斗结束"
	return "未知"

static func get_tactic_name(tactic: Tactic) -> String:
	match tactic:
		Tactic.MANEUVER: return "抢占T字位"
		Tactic.BOARD:    return "全速接舷"
		Tactic.DUEL:     return "发起单挑"
		Tactic.FLEE:     return "舰队撤退"
	return "未知"

static func get_duel_action_name(action: DuelAction) -> String:
	match action:
		DuelAction.SLASH:   return "猛攻"
		DuelAction.DODGE:   return "闪避"
		DuelAction.PARRY:   return "招架"
		DuelAction.SPECIAL: return "必杀"
	return "未知"

func get_victory_narration() -> String:
	match victory_type:
		VictoryType.SUNK: return "【击沉】敌方旗舰沉没！敌舰群龙无首作鸟兽散。"
		VictoryType.CAPTURED: return "【拿捕】敌方旗舰被占领！你获得了舰队的控制权。"
		VictoryType.DUEL_VICTORY: return "【单挑获胜】敌将落败！敌方舰队全线崩溃！"
		VictoryType.FLED: return "【撤退成功】舰队成功脱离了战场。"
		VictoryType.DEFEATED_SUNK: return "【战败沉没】旗舰在炮火中沉没……"
		VictoryType.DEFEATED_CAPTURED: return "【战败拿捕】旗舰甲板失守，全军覆没……"
	return "战斗结束。"
