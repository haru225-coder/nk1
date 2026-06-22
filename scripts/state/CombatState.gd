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
		s.max_hp = e_data.get("durability", 80.0)
		s.hp = s.max_hp
		s.max_crew = e_data.get("crew", 40)
		s.crew = s.max_crew
		s.artillery = e_data.get("artillery", 3)
		s.swordplay = e_data.get("swordplay", 2)
		s.maneuverability = e_data.get("maneuverability", 4)
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

	if player_tactic == Tactic.FLEE:
		return _resolve_flee()
	if enemy_tactic == Tactic.FLEE:
		narration_parts.append("【%s】试图撤退……" % enemy_name)
		var flee_roll = _roll(enemy_fleet.get_avg_maneuverability(), 10)
		if flee_roll >= 0.5:
			narration_parts.append("敌方借风势脱离了战场。")
			victory_type = VictoryType.FLED
			phase = Phase.RESOLVED
			return _build_round_result(narration_parts, true)
		else:
			narration_parts.append("但未能逃脱，暴露了侧翼！")
			var bonus_dmg = _calc_cannon_damage(player_fleet.get_total_artillery(), enemy_fleet.get_avg_maneuverability(), 1.5)
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
		var maneuver_success = _roll(p_maneuver, e_maneuver + 5)
		var player_dmg_mult: float = 1.0
		var enemy_dmg_mult: float = 1.0

		if maneuver_success >= 0.6:
			lines.append("【抢占T字位成功！】舰队切入敌军航线前方，获得有利炮击角度。")
			player_dmg_mult = 1.5
			enemy_dmg_mult = 0.5
		elif maneuver_success >= 0.3:
			lines.append("【机动对峙】双方舰队在海面周旋。")
		else:
			lines.append("【机动失败】敌舰抢占了有利位置！")
			player_dmg_mult = 0.6
			enemy_dmg_mult = 1.3

		var p_dmg = _calc_cannon_damage(player_fleet.get_total_artillery(), e_maneuver, player_dmg_mult)
		var e_dmg = _calc_cannon_damage(enemy_fleet.get_total_artillery(), p_maneuver, enemy_dmg_mult)
		
		var e_target = _get_random_living_ship(enemy_fleet)
		if e_target:
			e_target.hp -= p_dmg
			lines.append("我方齐射命中了[%s]，造成 %.0f 耐久伤害。" % [e_target.name, p_dmg])
			var crew_loss = maxi(0, int(p_dmg * 0.05))
			if crew_loss > 0:
				e_target.crew = maxi(0, e_target.crew - crew_loss)
				lines.append("敌方 %d 名水手伤亡。" % crew_loss)
				
		var p_target = _get_random_living_ship(player_fleet)
		if p_target:
			p_target.hp -= e_dmg
			lines.append("敌方炮击命中了[%s]，造成 %.0f 耐久伤害。" % [p_target.name, e_dmg])
			var crew_loss = maxi(0, int(e_dmg * 0.05))
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

	var player_power := float(p_flag.crew) * (1.0 + float(p_flag.swordplay) * 0.15)
	var enemy_power := float(e_flag.crew) * (1.0 + float(e_flag.swordplay) * 0.15)
	var total_power := player_power + enemy_power

	if total_power <= 0:
		return "双方都已无力战斗……"

	var base_casualties := maxi(3, int(total_power * 0.04))
	var player_loss := maxi(1, int(base_casualties * (enemy_power / total_power)))
	var enemy_loss := maxi(1, int(base_casualties * (player_power / total_power)))

	lines.append("我方水手勇猛冲杀，敌旗舰损失 %d 人。" % enemy_loss)
	lines.append("但己方旗舰也有 %d 名水手倒下。" % player_loss)

	if p_flag.swordplay >= 5:
		var bonus := maxi(1, int(float(enemy_loss) * 0.3))
		enemy_loss += bonus
		lines.append("你的剑术精湛，额外击杀 %d 名敌兵！" % bonus)
	if e_flag.swordplay >= 5:
		var bonus := maxi(1, int(float(player_loss) * 0.3))
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

	for i in range(3):
		var roll := _roll(p_flag.swordplay, e_flag.swordplay + 2)
		if roll >= 0.6:
			player_wins += 1
			duel_rounds.append(duel_phrases_win[i % duel_phrases_win.size()])
		elif roll >= 0.3:
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
		p_flag.crew = maxi(0, p_flag.crew - maxi(1, int(p_flag.crew * 0.05)))
		e_flag.crew = maxi(0, e_flag.crew - maxi(1, int(e_flag.crew * 0.05)))

	return "\n".join(lines)

## ── 撤退结算 ─────────────────────────────────────────────

func _resolve_flee() -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("【尝试撤退】你下令舰队全力脱离战场！")

	var flee_roll := _roll(player_fleet.get_avg_maneuverability(), enemy_fleet.get_avg_maneuverability() + 3)
	if flee_roll >= 0.5:
		lines.append("帆满舵转，舰队成功甩开了敌军！")
		victory_type = VictoryType.FLED
		phase = Phase.RESOLVED
		return _build_round_result(lines, true)
	else:
		lines.append("撤退失败！敌舰拦截了退路，一轮炮击狠狠打来！")
		var penalty_dmg := _calc_cannon_damage(enemy_fleet.get_total_artillery(), player_fleet.get_avg_maneuverability(), 1.2)
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
			if e_flag.hp < e_flag.max_hp * 0.3: return Tactic.FLEE
			if e_flag.crew < e_flag.max_crew * 0.3: return Tactic.MANEUVER
			if phase == Phase.BOARDING: return Tactic.BOARD
			if phase == Phase.CLOSE_RANGE and randf() > 0.4: return Tactic.BOARD
			return Tactic.MANEUVER

## ── 工具函数 ─────────────────────────────────────────────

func _get_random_living_ship(fleet: FleetState) -> ShipState:
	var alive = fleet.ships.filter(func(s: ShipState): return s.hp > 0)
	if alive.is_empty(): return null
	return alive.pick_random()

func _roll(attacker_stat: int, defender_stat: int) -> float:
	var total := attacker_stat + defender_stat
	if total <= 0: return 0.5
	var base := float(attacker_stat) / float(total)
	var noise := (randf() - 0.5) * 0.4
	return clampf(base + noise, 0.0, 1.0)

func _calc_cannon_damage(artillery: int, target_maneuver: int, multiplier: float) -> float:
	var base_damage := float(artillery) * 8.0
	var dodge_factor := clampf(1.0 - float(target_maneuver) * 0.04, 0.3, 1.0)
	var damage := base_damage * dodge_factor * multiplier
	damage *= (0.85 + randf() * 0.3)
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

func get_victory_narration() -> String:
	match victory_type:
		VictoryType.SUNK: return "【击沉】敌方旗舰沉没！敌舰群龙无首作鸟兽散。"
		VictoryType.CAPTURED: return "【拿捕】敌方旗舰被占领！你获得了舰队的控制权。"
		VictoryType.DUEL_VICTORY: return "【单挑获胜】敌将落败！敌方舰队全线崩溃！"
		VictoryType.FLED: return "【撤退成功】舰队成功脱离了战场。"
		VictoryType.DEFEATED_SUNK: return "【战败沉没】旗舰在炮火中沉没……"
		VictoryType.DEFEATED_CAPTURED: return "【战败拿捕】旗舰甲板失守，全军覆没……"
	return "战斗结束。"
