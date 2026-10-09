class_name AfterAction
## 战后取舍账（战斗系统方案 §三「战后」、§九「战后单子」，lane w53-p4-after）——纯逻辑、不进树、不触全局，
## SeaChart._on_battle_result 在札记落下后、返程收尾前拿它挂「战后收拾」小卡；数值全读 combat_phases.json
## 「after_action」节（读不到退回字面缺省，与 _spoil_by_outcome 同一退路口径）。
## 每样选择一件小账，调用方（SeaChart / 探针）照结果真动全局，再拿注记句缀进札记；开关键在 CombatSwitches
## 「waa_*」一组（after_* 前三期已用，四期换新前缀，免得开关一关把一期单子也带走）。全部关掉 = 逐字回旧。
##
## 挂卡读数：choices_for(outcome, data) —— 空数组 = 什么都不挂（旧形）。
## 抉择落账：apply(choice, outcome, data) —— 返回 {ok, note, money, fame_gained, promoted, title, crew_delta,
##   boarded_added, boarded_drifted, pursuit_roll, ship_added}。
## 战败一笔账（按下一张卡即落，不再等二择）：apply_lose(data) —— 战沉人被救一半捞回来（read 之前先核）。
##
## 追击那一掷在这里（掷完结算亦落账）：敌速取 combat_phases.json after_action.pursue.enemy_speed_ratio，
## 逃的是快船敌慢、逃的是海鹘敌快；追上比照夺船并入船队（Fleet.add_ship 原路），没追上挨一顿舷炮
## （Fleet.damage_fleet 按 data.pursue_hull_max / COMBAT_HIT_DMG 折算一舷齐射）。掷的结果写一句进札记。

const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")


## autoload 单例（Fleet）：不直接写 autoload 名字（同 CombatMorale 头注——class_name / check-only 下裸名
## 编译不过），运行期经 SceneTree.root 取节点、按方法名调（.call）；探针、SeaChart、门检定真起树后同一对象。
static func _fleet() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Fleet")
	return null


## Fleet.ship_def(type_id)；单例取不到（check-only / 未挂树）返回 {}
static func _ship_def(type_id: String) -> Dictionary:
	var f := _fleet()
	if f != null and f.has_method("ship_def"):
		var d = f.call("ship_def", type_id)
		return d if d is Dictionary else {}
	return {}


## Fleet.total_crew()；取不到返回 0
static func _total_crew() -> int:
	var f := _fleet()
	if f != null and f.has_method("total_crew"):
		return int(f.call("total_crew"))
	return 0


## Fleet.crew_max()；取不到返回 0
static func _crew_max() -> int:
	var f := _fleet()
	if f != null and f.has_method("crew_max"):
		return int(f.call("crew_max"))
	return 0


## Fleet.fleet_speed()；取不到返回 0
static func _fleet_speed() -> float:
	var f := _fleet()
	if f != null and f.has_method("fleet_speed"):
		return float(f.call("fleet_speed"))
	return 0.0

## 战败落水捞回比例（分母）：战沉的水手，半数被救上来
const LOSE_RESCUE_DIV := 2


static func _cfg() -> Dictionary:
	var d := _phases_data()
	return d.get("after_action", {}) if d is Dictionary else {}


## combat_phases.json 整表（与 SeaChart._phases_data 同源；读不到返回 {}）
static func _phases_data() -> Dictionary:
	var f := FileAccess.open("res://data/combat_phases.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## 读 after_action 节一节的字典；缺节返回 {}
static func _sec(name: String) -> Dictionary:
	var s = _cfg().get(name, {})
	return s if s is Dictionary else {}


# ── 输赢看数 ──────────────────────────────────────────

## 本战可押的船（夺来的、受降的）：win 时 data.fates 里 fate ∈ {boarded, struck} 的船种名单（逐艘一项）。
## WorldMap 夺船走 Fleet.add_ship 原路、收战已在册——这里的「押船」不是再夺一次，是派不派人看守：
## 人手够就留在册（什么都不动），不够就漂走（从名册摘掉）。fled 或 lose 时夺船账照旧不走这里。
static func _prize_ships(data: Dictionary) -> Array:
	var out: Array = []
	for entry in _Letterbox.fates_of(data):
		if not entry is Dictionary:
			continue
		var fate := str(entry.get("fate", ""))
		if fate != "boarded" and fate != "struck":
			continue
		var n: int = maxi(1, int(entry.get("count", 1)))
		for _i in n:
			out.append({"type": str(entry.get("type", "")), "fate": fate})
	return out


## 战后水面可救的人（win 时）：击沉 / 焚毁的敌船各泼一船人下水——按船型定员（(min+max)/2）的四分之一
## （泼下水的不死即逃、漂在海上的就这些）。读不到船型按 20 人计。
static func _rescue_pool(data: Dictionary) -> int:
	var n := 0
	for entry in _Letterbox.fates_of(data):
		if not entry is Dictionary:
			continue
		var fate := str(entry.get("fate", ""))
		if fate != "sunk" and fate != "burned":
			continue
		var cnt: int = maxi(1, int(entry.get("count", 1)))
		var d: Dictionary = _ship_def(str(entry.get("type", "")))
		var lo := int(d.get("crew_min", 8))
		var hi := int(d.get("crew_max", maxi(lo, 20)))
		n += cnt * maxi(2, int(round((lo + hi) * 0.5 * 0.25)))
	# 士气收场（struck / fled）没船沉：没有可救的人
	return n


## 战后俘虏（win 时）：受降 / 夺来的船上押着的人——按船型定员（(min+max)/2）的四分之一，
## 一船至多 cap 12（成本账：俘虏一人赎 40，一船满载赎 480 ≈ 敌逃半赏钱；不降也不翻番）。
## 读不到数据就 0（不挂俘虏行）。
const CAPTIVES_CAP := 12
static func _prisoner_count(data: Dictionary) -> int:
	var n := 0
	for entry in _Letterbox.fates_of(data):
		if not entry is Dictionary:
			continue
		var fate := str(entry.get("fate", ""))
		if fate != "struck" and fate != "boarded":
			continue
		var cnt: int = maxi(1, int(entry.get("count", 1)))
		var d: Dictionary = _ship_def(str(entry.get("type", "")))
		var lo := int(d.get("crew_min", 8))
		var hi := int(d.get("crew_max", maxi(lo, 20)))
		n += cnt * mini(CAPTIVES_CAP, maxi(2, int(round((lo + hi) * 0.5 * 0.25))))
	return n


## 遁走的敌船（win 时）：fled 下场有几艘、什么船种
static func _fled_ships(data: Dictionary) -> Array:
	var out: Array = []
	for entry in _Letterbox.fates_of(data):
		if entry is Dictionary and str(entry.get("fate", "")) == "fled":
			out.append(entry)
	return out


## 整场敌船有几艘索赎才亮：降了 / 夺了才有人可放（押船行在册 ≥ 1）。
## 赎金当场按折价兑付——方案「30 天后在对方港口兑付、再遇敌意低一档」要跨场记账，本档不改存档格式
## （COMMON 硬规矩），折成当场付讫：赎金 = 俘虏数 × ransom_each，钱匣立增，敌意那档不做（写明在此）。
static func _ransom_each() -> int:
	var s := _sec("ransom")
	return maxi(0, int(s.get("each", 40)))


static func _prize_min_crew() -> int:
	var s := _sec("prize")
	return maxi(1, int(s.get("min_crew", 6)))


## 押船走哪一边人手够（_apply_prize keep 用）：读 crew 存量判断，不改
static func _prize_keep_count(prizes: Array) -> Array:
	var need := _prize_min_crew()
	var avail := _total_crew()
	var kept: Array = []
	var drift: Array = []
	for p in prizes:
		if avail >= need:
			avail -= need
			kept.append(p)
		else:
			drift.append(p)
	return [kept, drift]


## 卖俘虏一人的价（卖 = 得钱、掉名声）
static func _sell_price() -> int:
	var s := _sec("captives")
	return maxi(0, int(s.get("sell_price", 25)))


## 救起一人可收编的人数上限（受船队总人数上限管：hire_crew 聚合语义逐船填，填不进的不补）
static func _rescue_enlist_cap() -> int:
	var s := _sec("rescue")
	return maxi(0, int(s.get("enlist_cap", 4)))


# ── 挂卡：三到五行小选择 ─────────────────────────────

## 战后单子上要挂的几行（行序 = 卡上从上往下）：每行 {key, label, options:[{id, label, default}], …}。
## 开关关了的行不挂；一行都不挂 = 旧形（回 _on_battle_result 原样）。
## 行数受 brief「三到五行」约束：押船 / 救人 / 俘虏 / 索赎 / 追击 至多五件；追击只在有船遁走时亮。
static func choices_for(outcome: String, data: Dictionary) -> Array:
	if outcome != "win":
		return []
	var rows: Array = []
	if _Switches.on("waa_prize"):
		var prizes := _prize_ships(data)
		if not prizes.is_empty():
			rows.append({
				"key": "prize",
				"label": "押船（夺来 / 受降 %d 艘，每艘至少 %d 人看守）" % [prizes.size(), _prize_min_crew()],
				"options": [
					{"id": "keep", "label": "分人押船", "default": true},
					{"id": "drift", "label": "随它漂走", "default": false},
				],
			})
	if _Switches.on("waa_rescue"):
		var pool := _rescue_pool(data)
		if pool > 0:
			rows.append({
				"key": "rescue",
				"label": "救人（落水约 %d 人）：救加名声、可收编" % pool,
				"options": [
					{"id": "save", "label": "救", "default": true},
					{"id": "leave", "label": "不救", "default": false},
				],
			})
	if _Switches.on("waa_captives"):
		var n := _prisoner_count(data)
		if n > 0:
			# 俘虏与索赎是同一批人，只落一个去处（主控复审）：索赎并进俘虏行做第四项、
			# 不再单挂索赎行——「卖掉」又「索赎」同一批人双得钱的漏洞堵死在这里。
			var opts: Array = [
				{"id": "enlist", "label": "收编", "default": true},
				{"id": "sell", "label": "卖掉", "default": false},
				{"id": "free", "label": "放走", "default": false},
			]
			var label := "俘虏（%d 人）：收编 / 卖掉 / 放走" % n
			if _Switches.on("waa_ransom"):
				opts.append({"id": "ransom", "label": "索赎", "default": false})
				label = "俘虏（%d 人）：收编 / 卖掉 / 放走 / 索赎" % n
			rows.append({"key": "captives", "label": label, "options": opts})
	if _Switches.on("waa_pursue"):
		var fled := _fled_ships(data)
		if not fled.is_empty():
			rows.append({
				"key": "pursue",
				"label": "追击（逃了 %d 艘）：可多夺一艘、也可能再挨一顿" % fled.size(),
				"options": [
					{"id": "hold", "label": "收队", "default": true},
					{"id": "chase", "label": "追", "default": false},
				],
			})
	return rows


# ── 落账 ─────────────────────────────────────────────

## 战败一笔账：战沉水手按 LOSE_RESCUE_DIV 捞回一半（进救起句）。在 SeaChart._lose_aftermath / 沉船句之前调用，
## 返回 {rescued: n, note: "…救起水手 N 人。…"}；开「waa_rescue」关 = 0 / 空串。
static func apply_lose(data: Dictionary) -> Dictionary:
	var lost := 0
	var losses = data.get("losses", {})
	if losses is Dictionary:
		lost = maxi(0, int(losses.get("crew", 0)))
	var rescued := 0
	if _Switches.on("waa_rescue"):
		rescued = int(lost / LOSE_RESCUE_DIV)
	var note := ""
	if rescued > 0:
		note = "救起水手%s人。" % _Letterbox._cn_count(rescued)
	return {"rescued": rescued, "note": note}


## 落一行选择。choice = choices_for 里那一行原样 + 玩家选的 option id（choice["chosen"]）。
## 返回账 + 注记句；调用方照 money / fame_gained / crew_delta / boarded_* 真动全局（Fleet / GameState 在这不动——
## 这里只把数算清，谁调谁落账，探针与 SeaChart 走同一条算路）。
static func apply(choice: Dictionary, outcome: String, data: Dictionary) -> Dictionary:
	var key := str(choice.get("key", ""))
	var chosen := str(choice.get("chosen", ""))
	var out := {"ok": false, "note": "", "money": 0, "fame_gained": 0, "promoted": false, "title": {},
		"crew_delta": 0, "boarded_added": 0, "boarded_drifted": 0, "pursuit_roll": "", "ship_added": ""}
	match key:
		"prize":
			return _apply_prize(chosen, data, out)
		"rescue":
			return _apply_rescue(chosen, data, out)
		"captives":
			return _apply_captives(chosen, data, out)
		"ransom":
			return _apply_ransom(chosen, data, out)
		"pursue":
			return _apply_pursue(chosen, data, out)
	return out


## 押船：分人看守（人手够，每艘 prize.min_crew 人；不够，差几艘漂几艘）。keep = 全押；drift = 全放漂。
static func _apply_prize(chosen: String, data: Dictionary, out: Dictionary) -> Dictionary:
	var prizes := _prize_ships(data)
	if prizes.is_empty():
		return out
	if chosen == "drift":
		out["boarded_drifted"] = prizes.size()
		out["note"] = "夺来的船没人看守，随水漂走了。"
		out["ok"] = true
		return out
	# keep：人手够几艘押几艘，不够的漂走（按类型逐艘走，不用重写）
	var parts2 := _prize_keep_count(prizes)
	var kept: int = (parts2[0] as Array).size()
	var drifted: int = (parts2[1] as Array).size()
	out["boarded_added"] = kept
	out["boarded_drifted"] = drifted
	var parts: PackedStringArray = []
	if kept > 0:
		parts.append("分人押定 %d 艘，并入船队。" % kept)
	if drifted > 0:
		parts.append("人手不够，%d 艘没人看守，漂走了。" % drifted)
	out["note"] = "".join(parts)
	out["ok"] = true
	return out


## 救人：救 = 加名声（add_fame rescue.fame），救上来的按 rescue.enlist_cap 收编（受船队上限）；
## 不救 = 什么都不动（旧玩法）。
static func _apply_rescue(chosen: String, data: Dictionary, out: Dictionary) -> Dictionary:
	var pool := _rescue_pool(data)
	if pool <= 0:
		return out
	if chosen != "save":
		out["note"] = "没下水救人。"
		out["ok"] = true
		return out
	var s := _sec("rescue")
	var fame_amt := maxi(0, int(s.get("fame", 2)))
	var cap := _rescue_enlist_cap()
	var saved := pool  # 全救起：战后水面这一批都捞上来（真限额在这里改）
	out["fame_gained"] = fame_amt
	out["crew_delta"] = mini(saved, cap)
	# 收编进船队（hire_crew 聚合逐船填，填到上限为止；out.crew_delta 记的是实际愿留的——
	# 满了填不下的在这里照样写「编入」但那部分调用方照 hire_crew 的返回值再校）
	out["crew_enlisted"] = int(out["crew_delta"])
	var parts: PackedStringArray = ["救起水手%s人。" % _Letterbox._cn_count(saved)]
	if int(out["crew_delta"]) > 0:
		parts.append("其中 %d 人愿意留下，编入船队。" % int(out["crew_delta"]))
	if fame_amt > 0:
		parts.append("名声加 %d。" % fame_amt)
	out["note"] = "".join(parts)
	out["ok"] = true
	return out


## 俘虏：enlist 收编（hire_crew 聚合逐船填，受上限）、sell 卖掉（得钱掉名声）、free 放走（加名声）。
static func _apply_captives(chosen: String, data: Dictionary, out: Dictionary) -> Dictionary:
	var n := _prisoner_count(data)
	if n <= 0:
		return out
	match chosen:
		"enlist":
			var took := mini(n, maxi(0, _crew_max() - _total_crew()))
			out["crew_delta"] = took
			var parts: PackedStringArray = []
			if took > 0:
				parts.append("收编俘虏 %d 人补水手。" % took)
			if took < n:
				parts.append("船队满了，余下 %d 人遣散。" % (n - took))
			if parts.is_empty():
				parts.append("俘虏遣散。")
			out["note"] = "".join(parts)
		"sell":
			var price := _sell_price()
			out["money"] = n * price
			out["fame_gained"] = -2
			out["note"] = "把俘虏卖了，得钱 %d；这事传出去不好听。" % (n * price)
		"free":
			out["fame_gained"] = 2
			out["note"] = "放俘虏各自回去，名声加 2。"
		"ransom":
			# 索赎：放船（俘虏）换赎金，当场折价兑付——方案「30 天后对方港口兑付」要跨场
			# 记账，本档不改存档（见 ransom_each 注）。这一批人在俘虏行的第四项，只落一个去处。
			var each := _ransom_each()
			out["money"] = n * each
			out["note"] = "放回 %d 人，对方当场折价兑付赎金 %d 钱。" % [n, n * each]
		_:
			out["note"] = ""
	out["ok"] = out["note"] != ""
	return out


## 索赎：放船换赎金，当场折价兑付（方案「30 天后对方港口兑付」要跨场记账，本档不改存档——见 ransom_each 注）。
## ransom = 得钱 = 俘虏数 × each，人放走（无名声增减）；skip = 作罢。
static func _apply_ransom(chosen: String, data: Dictionary, out: Dictionary) -> Dictionary:
	var n := _prisoner_count(data)
	if n <= 0:
		return out
	if chosen != "ransom":
		out["note"] = "没提赎金，人照前处置。"
		out["ok"] = true
		return out
	var each := _ransom_each()
	out["money"] = n * each
	out["note"] = ""
	out["ok"] = true
	return out


## 追击：追 = 按敌速 / 我速掷一次；追上比照夺船并入船队（out.ship_added = 船种，调用方走 Fleet.add_ship 原路），
## 没追上挨一顿舷炮（调用方照 data.pursue_hull_max / COMBAT_HIT_DMG 折算 damage_fleet）。hold = 收队（旧玩法）。
static func _apply_pursue(chosen: String, data: Dictionary, out: Dictionary) -> Dictionary:
	var fled := _fled_ships(data)
	if fled.is_empty():
		return out
	if chosen != "chase":
		out["note"] = "收队回航。"
		out["ok"] = true
		return out
	var s := _sec("pursue")
	var ratio := float(s.get("enemy_speed_ratio", 0.95))
	# 逃的船里取头一艘做追的对象（快船敌慢、海鹘敌快——按船种 base_speed 乘 ratio）
	var target: Dictionary = fled[0]
	var type_id := str(target.get("type", ""))
	var d: Dictionary = _ship_def(type_id)
	var enemy_spd := float(d.get("base_speed", 100)) * ratio
	var my_spd := _fleet_speed()
	# 掷一次：我速快必追上；都慢按比掷（海图 flee 同一路的「船速比」口径，没有再套士气）
	var p := 1.0 if my_spd >= enemy_spd else clampf(my_spd / maxf(enemy_spd, 1.0), 0.05, 0.95)
	var caught: bool = randf() < p
	if caught:
		out["ship_added"] = type_id
		out["boarded_added"] = int(out["boarded_added"]) + 1
		out["pursuit_roll"] = "caught"
		out["note"] = "追上去把逃的那艘也夺下了。"
	else:
		out["pursuit_roll"] = "missed"
		var hits := maxi(1, int(s.get("broadside_hits", 3)))
		out["note"] = "追不上，反挨了一顿舷炮（%d 门齐射）。" % hits
	out["ok"] = true
	return out


## 追击没追上的舷炮伤（调用方 Fleet.damage_fleet 的实数）：按敌船满编舷侧炮位 × COMBAT_HIT_DMG 折算。
## data.pursue_hull_max 是 WorldMap 收战前塞的敌船船体上限（没有就按船种耐久估），COMBAT_HIT_DMG 由 SeaChart 给。
static func pursuit_damage(data: Dictionary, hit_dmg: float) -> float:
	var s := _sec("pursue")
	var hits := maxi(1, int(s.get("broadside_hits", 3)))
	var hull := float(data.get("pursue_hull_max", 0.0))
	if hull <= 0.0:
		var fled := _fled_ships(data)
		if not fled.is_empty():
			var d: Dictionary = _ship_def(str(fled[0].get("type", "")))
			hull = float(d.get("durability", 300))
	return hits * hit_dmg * clampf(hull / 300.0, 0.5, 2.0)


## 战败落水捞回（apply_lose 的纯读版）：开关关 = 0
static func lose_rescue_of(data: Dictionary) -> int:
	return int(apply_lose(data).get("rescued", 0))
