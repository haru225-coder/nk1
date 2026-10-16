class_name YashanBattle
extends RefCounted
## 崖山突围战（战斗系统方案 §七「崖山突围」、§八「章节与结局」；lane w53-p6-yashan）。
##
## 崖山卡上多一扇门「上船同去」：宋军的船连成一片，铁索锁着，雾里顺风放来火船。这一仗不是打赢，
## 是冲出去——离场线在雾那头的港口出口，撑过时限、或把追兵甩在身后都算冲出。
## **史实不变**：祥兴二年二月宋军照旧覆灭，六个结局与九条剧情锚点一字不动；这一仗只改结局文字里
## 「你的船活没活」那一句（冲出来 / 没冲出来），没冲出来也不是游戏结束，照现有崖山后的流程走。
##
## 本件是这一场的场次配置与胜负口径，纯静态、不建节点、不读 autoload、不进存档：
##   一、场次（setup）：pending_battle 照现有海战那一套写法（同 SeaChart._on_fight_pirates 的形状），
##       敌是元军船阵（海鹘一艘、快船两艘）+ 顺风放来的火船；海况取 data/combat_sea_state.json 已有的
##       港湾那一档（雾、窄水、潮流作主），风力按那条档的雾战情形压到港湾里的软风，风向逆着玩家的出路吹。
##   二、火船（PirateShip 的 fire_ship 一态）：不摇橹、不挂钩、不开炮，只顺风漂；碰上玩家船就点火
##       （复用三期 FloodFire 的篷帆引火），点完自身了账（焚毁）。风给多少速度就漂多快。
##   三、冲出判定：WorldMap 在收战那一刻问本件判词——本船沉了 / 被跳帮 / 我方士气溃（走 lose 那一族）
##       = 没冲出来；脱战、甩脱、限时两散、敌尽降遁（win 那一族）= 冲出来了。
##   四、写法：唯一状态是两枚旗（yashan_breakout_done / yashan_broke_out），走 GameState 现有旗标存档路径
##       （SaveLoad 的旗字典本子，不新增存档字段、不动存档版本），读旧档时旗不在 = 没打过这一场。
##
## 开关：yashan_breakout 关 = 崖山卡逐字回旧（没有「上船同去」那扇门，本件一行也不跑）；
##       yashan_fire_ship 关 = 这一场里没有火船，只剩元军船阵（海况与出路照旧）。

const SeaState := preload("res://scripts/combat/SeaState.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

## 本场在 pending_battle 里的来处（WorldMap / 探针认它定场，同 SeaChart 写 source.event 的口径）
const SOURCE := "yashan_breakout"

## 旗标：这一场打过没有 / 打的结果
const FLAG_DONE := "yashan_breakout_done"
const FLAG_OUT := "yashan_broke_out"

## 离场线（px）：出雾口那道线。崖山港湾是窄水，出路比寻常两散（escape_bu 1280）近得多——
## 这条线摆在火船阵之外（火船最远摆到 SPAWN_DIST_MAX，出路在它更远处），
## 所以「冲出去」= 从雾里那片烧着的船中间穿过去、到了出口那一线；WorldMap 用它盖掉本场的 _escape_px
const ESCAPE_PX := 700.0
## 本场时限（秒）：撑到这时候宋军那一片已经烧透，两边各自收（照限时两散的收法）
const BATTLE_LIMIT_S := 150.0
## 本场刷敌距离（px）：港湾窄水，元军船阵横在雾里那道出口上（比外海那 700–720 步近得多）。
## 敌船摆得比火船远一档：玩家要穿的是先火船、后船阵这两层
const SPAWN_DIST_MIN := 420.0
const SPAWN_DIST_MAX := 470.0
## 火船摆下的距离带（px）：在玩家与出路之间横着一线，风一路把它们送到玩家面前。
## 近端比敌阵近、远端比敌阵近不到哪去——玩家从中间找缝穿过去
const FIRE_DIST_MIN := 210.0
const FIRE_DIST_MAX := 430.0
## 火船横着摊开的间距（px）：左中右三档各差这么多——几艘不叠在一条线上，玩家有缝可找
const FIRE_SPREAD_PX := 150.0
## 火船：本场放几艘、顺风漂多快（步/秒，× 8 = px/s；比玩家船速慢，追得上也躲得开）
const FIRE_SHIP_COUNT := 5
const FIRE_SHIP_DRIFT_BUS := 2.6
## 同屏船数上限（方案 §十一「第六期最多同屏 6–8 艘」）：元军三艘 + 火船，合计压在这个数里
const SCREEN_CAP := 8
## 碰上点火的判距（px）：两条船挨到舷贴舷才算碰（船身半长 122 上下，取 150 是舷边擦着的量）
const IGNITE_DIST := 150.0
## 火船点着玩家以后自己了账：焚毁（同 FloodFire 的艏部满火）
const FIRE_SHIP_IGNITE := {"bow": 1.0, "mid": 0.8, "stern": 0.6, "rig": 1.0}

## 海况（港湾那一档，见 data/combat_sea_state.json waters.id = "harbor"）：雾、窄水、潮流作主。
## 寻常海战到了不这里（那条档的 note 写着「剧情战用（守港、崖山一类）」）
const WATERS := "harbor"
const WEATHER := "fog"
## 本场风力：港湾里有山挡着，取三级・摇枝（60）——火船漂得动，玩家船也转得开。
## 风向往南吹（toward 180，来向正北），玩家的出路在北边：顺风走是往火里走，顶着风才出得去
const WIND_STRENGTH := 60.0
const WIND_TOWARD_DEG := 180.0
## 海况种子：0 = 每场随机（探针要复现就把 pb.sea_seed 定死）
const SEA_SEED := 0


## 开这一场（Main 崖山卡「上船同去」按钮调）。返回照 SeaChart 写法的 pending_battle。
## p_player_power 是玩家船队的战力（_fleet_power 同一式，调用方算好传进来）；
## p_known_here 是泉州借过船的那一档（本场只用来定敌阵多寡，冲不冲得出还是看玩家自己划）。
static func setup(p_player_power: float, p_known_here: bool) -> Dictionary:
	var power := _enemy_power(p_known_here)
	var fire_n := fire_ship_count(p_player_power, p_known_here)
	var enemy: Array = _enemy_list(p_known_here)
	return {
		"battle": true,
		"power": power,
		"player_power": maxf(1.0, p_player_power),
		"enemy": enemy,
		"sea_name": "崖山港湾",
		"source": {"scene": "Main", "event": SOURCE, "yashan": true},
		"sea_state": sea_state(),
		"yashan": {"fire_ships": fire_n, "escape_px": ESCAPE_PX, "limit_s": BATTLE_LIMIT_S,
			"spawn_min": SPAWN_DIST_MIN, "spawn_max": SPAWN_DIST_MAX},
	}


## 本场海况（照 data/combat_sea_state.json 的键名写；WorldMap 的 _setup_sea 与 SeaState 都按这些键读）：
## 港湾那一档的水域、雾天、潮流，风向风力按本件常量定死。
static func sea_state() -> Dictionary:
	return {
		"waters": WATERS,
		"weather": WEATHER,
		"wind_bearing": WIND_TOWARD_DEG,
		"wind_strength": WIND_STRENGTH,
		"sea_seed": SEA_SEED,
	}


## 港湾那一档的海况读数（HUD / 探针认它）：雾、窄水、看不出八十步，潮水作主
static func waters_note() -> Dictionary:
	return {"id": "harbor", "name": "港湾", "visibility_bu": 300, "weather": "雾",
		"note": "港口、海湾、河口。剧情战用（守港、崖山一类），寻常遇敌不落在这里"}


## 这一场打不打（开关关 = 崖山卡逐字回旧）
static func enabled() -> bool:
	return _Switches.on("yashan_breakout")


## 火船放不放（第二个开关），并压同屏船数上限：元军几艘先占，余下的位子给火船
static func fire_ship_count(p_player_power: float, p_known_here: bool) -> int:
	if not _Switches.on("yashan_breakout") or not _Switches.on("yashan_fire_ship"):
		return 0
	return mini(FIRE_SHIP_COUNT, maxi(0, SCREEN_CAP - _enemy_count(p_known_here)))


## 元军船阵：泉州借过船的档（少保记着那一位）多给一艘快船——有人认得你，追得也紧些。
## 本场同屏至多三艘元军船（方案 §十一「6–8 艘」里给火船留位子）
static func _enemy_list(p_known_here: bool) -> Array:
	var out: Array = [{"type": "sea_falcon", "count": 1, "sprite": "yuan_patrol"}]
	var boats := 2 if p_known_here else 1
	out.append({"type": "pirate_boat", "count": boats})
	return out


static func _enemy_count(p_known_here: bool) -> int:
	var n := 0
	for e in _enemy_list(p_known_here):
		n += int(e.get("count", 1))
	return n


## 元军船阵的战力（WorldMap._spawn_enemy 按 power / player_power 折敌血）。
## 本场是突围不是歼灭，敌阵照元军哨船那一档给：借过船的档再厚一点
static func _enemy_power(p_known_here: bool) -> float:
	return 420.0 if p_known_here else 320.0


## 火船的顺风漂速（px/s）：步/秒 × 8（data/combat_phases.json scale.px_per_bu 同口径）
static func drift_px_per_s() -> float:
	return FIRE_SHIP_DRIFT_BUS * 8.0


## 冲出判词：outcome 是 WorldMap 收战发的那一族，data 是它的收战账。
## 本船沉了（lose+sunk）、被我方溃逃 / 降幡收（morale 裁决）、被跳帮夺船（lose+overrun）——都没冲出来；
## 其余（win / flee 脱战 / disengaged 天晚两散）都算冲出来了。
## 照 WorldMap._battle_exit 的三种 outcome 名写；data 里几个键名同它带的那几笔。
static func broke_out(outcome: String, data: Dictionary) -> bool:
	if str(data.get("morale_verdict", "")) == "player_struck" or bool(data.get("struck", false)):
		return false
	elif outcome == "lose":
		return false
	return true


## 结局文字里那一句：冲出来了 / 没冲出来。两式都落在「海上宋鬼」这一结局里，
## 只换「船活没活」这一句，别的一句不动（史实照旧）
static func tail_text(p_out: bool) -> String:
	if p_out:
		return "你在雾里把舵压到底。火船贴着舷过去，火舌舔着你的篷，没咬住。
出港嘴的时候天还没亮。回头看，那一整片连着的船在烧，烧到天亮。
阿那要是还活着，会告诉你这时候该往哪边走。你自己看了水色。往南。"
	return "火船顺风来的时候你没躲开。火从篷上落到甲板，一路烧到舷边。
烟里分不清哪是出口，哪是自家的船。
人捞上来一半。往南走的时候，船比来时轻得多。"


## 这一场的结果该记的两枚旗（WorldMap 收战后由调用方落账：remember 返回的是「要置哪几枚」，
## 不在这里碰 GameState——本件是纯静态件，裸写 autoload 名会让 class_name 注册编不过
## （headless -s 下 autoload 名不在编译期符号表里）。旗走 GameState.set_flag，用的是现有旗标本子：
## 不新增存档字段、不动存档版本，读旧档时旗不在 = 没打过这一场。
static func flags_for(p_out: bool) -> PackedStringArray:
	return PackedStringArray([FLAG_DONE, FLAG_OUT]) if p_out else PackedStringArray([FLAG_DONE])


## 上一场的结果：flags 是 GameState.flags（本子照 GameState 的形）；没打过这一场给 null，调用方走旧那句。
## 读旧档回来的旧档没这两枚旗 = 没打过，同 null。
static func last_result(flags: Variant) -> Variant:
	if not (flags is Dictionary) or not bool((flags as Dictionary).get(FLAG_DONE, false)):
		return null
	return bool((flags as Dictionary).get(FLAG_OUT, false))
