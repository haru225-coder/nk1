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
	# 第四期 · 战后取舍（waa = wave after-action；after_* 前三期已用，四期另起前缀，开关互不带累）
	"waa_prize": true,    # 押船：夺来 / 受降的船要分人看守（至少 6 人），人手不够船漂走 —— w53-p4-after
	"waa_rescue": true,   # 救人：落水的人救不救——救了加名声，救上来的可以收编 —— w53-p4-after
	"waa_captives": true, # 俘虏：收编（补水手）/ 卖掉（得钱掉名声）/ 放走（加名声）—— w53-p4-after
	"waa_ransom": true,   # 索赎：放船换赎金，当场折价兑付（不改存档记账）—— w53-p4-after
	"waa_pursue": true,   # 追击：敌船逃了可选追——可能多夺一艘，也可能再挨一顿 —— w53-p4-after
	# 第四期 · 白刃取舍
	"melee_decision": true,    # 白刃三决断：舷边 / 舷腰 / 桅下各停一拍选「压上」或「收势」，可切回自动 —— w53-p4-melee
	"pursue_window": true,     # 敌船遁走留一段可追的窗口（脱离航速略挫、离场线拖后）—— w53-p4-melee
	"war_prices": true,        # 军需涨价：牙行价按港口战况 × 货的战时货类乘倍数（goods.json war_price）—— w53-p5-econ
	"port_blockade": true,     # 第五期 · 拦港（待拍板 20b）：封港、围城、对己封港的港不进晨潮三向，海图上点它只给「港已封」；剧情要去的港放行 —— w53-p5-blockade
	"blockade_run": true,      # 第五期 · 闯封锁：舱里带米粮可闯被围的港，四成撞上元军哨船（海鹘一艘、快船两艘），赢了按围城米价卖粮，输了 / 逃了米粮扣下、船折回 —— w53-p5-blockade
	"siege_schedule": true,    # 第五期守城行事表：城防账旁一方小笺写元军进度（围城那天前锋到囊山・使者到城下、援兵断绝、城破）与今日离城破几日，五扇门写耗几日 —— w53-p5-siege
	"siege_relief": true,      # 第五期守城外援：涵江押粮 / 押陈瓒船股换乡兵 / 拆船料修墙（那条船掉一档帆）/ 入围那月出海劫粮道（只在兵粮墙士气上开口子，仍最多三阵）—— w53-p5-siege
	"landing_raid": true,      # 第六期小规模登陆战：海战赢了、敌是海寇、船在宋土沿海——战后单子多一行「登岸剿寨」，骰子借陆战那一路（SiegeMelee.clash）—— w53-p6-landing
	"escort_battle": true,     # 第六期 · 护航船上阵：旗舰以外的船（至多三艘、连敌船同屏不过八艘）跟着进海战，船体人手照记回 Fleet —— w53-p6-escort
	"escort_orders": true,     # 第六期 · 护航三道将令：开战布置时下一道（列队 / 曳敌 / 夺舱）、整场不变；关掉不出将令、护航照列队 —— w53-p6-escort
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
