class_name CombatSwitches
## 海战新玩法总开关（战斗系统方案第一、二、三期）。默认全开；关掉某一项，那一项就回到原来的玩法。
## 只活在内存里，不进存档；探针可以用 set_on() 临时关掉某项来比对前后。
## 各 lane 只读自己那几个键，不改别人的键；新增键请在下表末尾追加一行。

const DEFAULTS := {
	# 第一期 · 看得见
	"enemy_intel": true,       # 右上敌情列：每艘敌船一行（布色、估计伤情、船种）—— w53-15
	"parley_on_ship": true,    # 劝降挂到敌船身上，被钩住 + 帆坏 + 动摇三样凑齐才亮 —— w53-15
	"after_action": true,      # 战后单子：两三行写这一仗的下场 —— w53-16
	"bounty_by_outcome": true, # 赏钱按打法分：击沉 1/3、逼降全赏、夺船给船、敌逃一半 —— w53-16
	"flagship_handoff": true,  # 旗舰沉了由护航接任（13c）—— w53-16
	"morale_carry": true,      # 战中士气按末值带回航程 —— w53-17
	"gale_parting": true,      # 大风两散 —— w53-17
	# 第二期 · 矢石有数
	"player_gunnery": true,    # 玩家的船接上装填簿、弹药、弹道（回退开关：关掉就是原来的直线铁球）—— w53-2
	"archer_scaling": true,    # 弓弩手按人头折算威力（0.2–2.0 倍）—— w53-2
	"crew_role_effects": true, # 职事加成补齐五种（火长、总管、通事、杂事、夷人）—— w53-15/16/17 各接各的
	"order_cut_grapple": true, # 新号令「砍钩」—— w53-15
	"order_wet_felt": true,    # 新号令「张湿毡」—— w53-15
	# 第三期 · 火与水
	"enemy_flood_fire": true,  # 敌船也会进水、失火（只挂 FloodFire 这一件，不挂整套伤损模型）—— w53-p3a
	"fire_attack_load": true,  # 火攻回到装填轮换（均装 → 专力装填 → 火攻）—— w53-p3b
}

static var _over: Dictionary = {}

static func on(key: String) -> bool:
	if _over.has(key):
		return bool(_over[key])
	return bool(DEFAULTS.get(key, false))

static func set_on(key: String, v: bool) -> void:
	_over[key] = v

static func reset() -> void:
	_over.clear()
