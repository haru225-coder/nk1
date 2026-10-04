## 海战号令面板：抢风 / 装填侧重 / 救火 / 备接舷 / 降幡劝降，五道号令落到「人手分派」上，折成可查询的乘数。
## 本文件只管「号令 → 人手 → 效力」这一层，不改 WorldMap / Ship / 弹道 / 损伤 / 白刃 / 士气的文件。效力交出去有四条路：
##   一、信号：order_issued(order_id, payload)；劝降另发 parley_resolved(result)
##   二、静态注册：register_handler(order_id, cb)（"*" 收全部），下令时逐个 cb.call(order_id, payload)；
##       set_parley_resolver(cb) 可把劝降判定整个交给士气模块（cb.call(ctx) -> {"result": "surrender" / "refuse" / "defy", …}）
##   三、查询：modifiers_for(host) —— host 所在场景树里第一块面板的当前乘数；没挂面板回 neutral_modifiers()（全 1.0），
##       所以接线后玩家不下令即与现行手感零差异。lane w53-2 起海战场经 WorldMap.order_mods 接上：旗舰机动（帆力 sail_drive /
##       转向 turn_rate / 贴风 pinch_delta → ManeuverModel 的 trim / helm / pinch_delta）、装填（reload_time → Ship 齐射冷却）、
##       白刃（board_bonus → 本队白刃将领系数，攻守都算）、钩距（board_range → 本船去钩的够距）、伤亡（exposure → 旗舰挨矢石的伤亡）。
##       火攻（LOAD_TABLE.fire）暂不入轮换：旗舰没挂弹药簿（ReloadAmmo），敌船也没有帆损、火势，射程、引火、伤害去向无处落，
##       下了只剩装填慢——签面与效力一行不写落不了地的数（lane w53-2 定）
##   四、落令（auto_apply，默认开）：旗舰身上有同波次的分系统就按号令改它的令（鸭子型，只调它们公开的改令口）——
##       ship.battery（ReloadAmmo）：抢风 → set_emphasis("sail")，专力装填 → "guns"，两令同下 / 都不下 → "balanced"；火攻 → set_fire_mode(true)
##       ship.damage_model（DamageModel）：救火 → set_mode 按险情取 "fire"（有火或无险）/ "flood"（只进水），令在期间随险情改（tick）；
##         没令救火而备接舷 → "fight"（迎敌，损管只留一成半人）；都没有 → "auto"
##       玩家一道令都没下过就不落，分系统保持它们自己的默认。
## 挂法：CombatOrdersPanel.mount(world)，或经 CombatShoreHook.mount_combat_ui；CanvasLayer 自加 nk1_combat_ui / nk1_combat_orders 两组供探针找。
## 键盘 1–5（小键盘同）下令，鼠标点签亦可；签不取焦点，不抢 Ship 的方向键 / W S。战斗已结算（world.resolved）后不再收键。
## headless 下照样建节点（量排版、验状态），不做淡入。不暂停、不入存档。
##
## 人手分派（宋元近海一船人手：帆索缭手、弩手与拽炮人、戽水扑火、执钩拒的甲士）——
##   平时 帆 3 成 · 弩炮 4 成 · 水火 1 成 · 甲士 2 成。下令改的是各岗权重，归一后得分派；效力按「现分派 ÷ 该令要的分派」折算：
##   抢风：帆岗 ×1.8。缭手加倍上缭，篾篷硬帆逐片收紧，船可再贴风 PINCH_TRIM 度（pinch_delta，给机动模型减 pinch）；弩炮手被抽去，装填慢。
##   装填侧重：轮换 均装 ⇄ 专力装填（LOADS；火攻暂撤，见上）。专力装填把闲手都派去递矢、拽炮（弩炮岗 ×1.6），装填快，帆索与甲士人手少；
##     火攻（LOAD_TABLE 仍留这一档）换装火箭、火球，焚帆为主、装填稍慢，火攻须居上风（fire_attack_factor）。
##   救火：水火岗 ×3.5。分人戽水扑火，扑火、排水成倍快；帆与弩炮的人手跟着少。
##   备接舷：甲士岗 ×(1 + 聚队进度)，聚齐要 MUSTER_SEC 秒（撤令 DISPERSE_SEC 秒散回）。钩距、白刃加力；聚在舷边挨矢石，伤亡加重。
##   降幡劝降：近敌（≤ HAIL_RANGE）喊话令其竖降幡。胜算 parley_chance：敌士气低、船伤重、我众敌寡、甲士聚舷、已钩住、
##     敌阵脚已乱（CombatMorale 的动摇 / 思退 / 溃逃）都加；敌已降幡则喊即成。
##     不成则 PARLEY_COOLDOWN 秒内不能再喊；「不成」里靠后的四分之一是敌愈坚（payload 带 morale_delta 建议值，由接线方落）。
extends CanvasLayer

signal order_issued(order_id: String, payload: Dictionary)
signal parley_resolved(result: Dictionary)

const StatusHud := preload("res://scripts/ui/CombatStatusHud.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const SELF_PATH := "res://scripts/ui/CombatOrdersPanel.gd"

const GROUP_UI := "nk1_combat_ui"
const GROUP := "nk1_combat_orders"
## 状态条（20）之上、BoardingStage（55）/ CombatLetterbox（58）之下
const LAYER_INDEX := 21
const REFRESH_SEC := 0.2
const MARGIN := 16.0
## WorldMap 顶匾（TideBar）找不到时，面板顶边落在这里
const TOP_FALLBACK := 96.0
const PANEL_W := 288.0

const ORDER_WINDWARD := "windward"
const ORDER_LOAD := "load"
const ORDER_DAMAGE := "damage"
const ORDER_BOARD := "board"
const ORDER_PARLEY := "parley"
## 二期号令（战斗方案 new 接两令）：砍钩 = 敌船把我们钩住时留斧手斫缆脱开；张湿毡 = 舷边张过水的厚毡压火伤
const ORDER_CUT := "cut"
const ORDER_WET := "wet"
const ORDERS := ["windward", "load", "damage", "board", "parley", "cut", "wet"]
const ORDER_NAMES := {
	"windward": "抢风", "load": "装填侧重", "damage": "救火", "board": "备接舷", "parley": "降幡劝降",
	"cut": "砍钩", "wet": "张湿毡",
}
const ORDER_KEYS := {
	"windward": [KEY_1, KEY_KP_1], "load": [KEY_2, KEY_KP_2], "damage": [KEY_3, KEY_KP_3],
	"board": [KEY_4, KEY_KP_4], "parley": [KEY_5, KEY_KP_5], "cut": [KEY_6, KEY_KP_6], "wet": [KEY_7, KEY_KP_7],
}
const ORDER_TIPS := {
	"windward": "缭手加倍上缭，篾篷逐片收紧，船可再贴风几度；弩炮手被抽去，装填慢。再按撤令。",
	"load": "轮换：均装、专力装填。专力装填闲手都去递矢拽炮，装填快、帆索人少。",
	"damage": "分人戽水扑火，扑火排水快数倍；帆与弩炮的人手跟着少。再按撤令。",
	"board": "甲士执钩拒聚到舷边，六秒聚齐：钩距远、白刃有力，聚在舷边挨矢石伤亡也多。再按撤令。",
	"parley": "近敌喊话，令其竖降幡。敌士气低、船伤重、我众敌寡、已钩住、敌阵脚已乱时易成；不成二十秒内不能再喊。",
	"cut": "敌船先抛的钩挂上时斧手斫缆脱开：每合砍断钩索的机会多一半；本船去钩的不济，签了也无用。",
	"wet": "舷边张过水的厚毡压火伤、防火箭：火着一半、受矢石轻三成；舷边人手脚局促，齐射慢两成、白刃减力一成。",
}

const STATIONS := ["sail", "guns", "damage", "board"]
const STATION_NAMES := {"sail": "帆", "guns": "弩炮", "damage": "水火", "board": "甲士"}
## 平时人手分派（和为 1）
const BASE_ALLOC := {"sail": 0.30, "guns": 0.40, "damage": 0.10, "board": 0.20}
const WINDWARD_SAIL_W := 1.8
const DAMAGE_W := 3.5
## 甲士岗权重 = 1 + BOARD_MUSTER_W × 聚队进度
const BOARD_MUSTER_W := 1.0
const MUSTER_SEC := 6.0
const DISPERSE_SEC := 2.0
## 帆岗满配（抢风）时能再贴风的度数（机动模型 pinch 减去它）
const PINCH_TRIM := 6.0

## 号令轮换的几档：火攻暂撤（见头注「三」：旗舰没挂弹药簿、敌船没有帆损火势，引火无处落）；LOAD_TABLE 仍留 fire 这一档
const LOADS := ["mixed", "rapid"]
## 装填侧重：name 签上写法；hull / sail / crew = 命中后伤害落在船壳 / 帆索 / 人手的份额（和为 1）；
## reload = 该令人手给足时的装填时长乘数；range = 射程乘数；ignite = 引火乘数；guns_w = 弩炮岗权重；
## emphasis / fire_mode = 落到 ReloadAmmo 的令
const LOAD_TABLE := {
	"mixed": {"name": "均装", "hull": 0.40, "sail": 0.30, "crew": 0.30, "reload": 1.00, "range": 1.00, "ignite": 1.0, "guns_w": 1.0},
	"rapid": {"name": "专力装填", "hull": 0.40, "sail": 0.30, "crew": 0.30, "reload": 0.70, "range": 1.00, "ignite": 1.0, "guns_w": 1.6},
	"fire": {"name": "火攻", "hull": 0.25, "sail": 0.50, "crew": 0.25, "reload": 1.15, "range": 0.90, "ignite": 3.0, "guns_w": 1.0},
}
## 火攻：居上风引火 ×1.5，居下风 ×0.6（火借风势，逆风火箭多坠于水）
const FIRE_UPWIND := 1.5
const FIRE_DOWNWIND := 0.6

const HAIL_RANGE := 360.0
const PARLEY_COOLDOWN := 20.0
const PARLEY_MIN := 0.02
const PARLEY_MAX := 0.85
## 砍钩（combat_phases.json orders.cut_hooks.cut_chance_mul）：守方吃紧抢砍钩缆的每合基率乘数
const CUT_CHANCE_MUL := 1.5
## 战斗方案一期：劝降钮挂到敌船身上、三样凑齐才亮（parley_on_ship 开时）；敌船「帆索残」按船体伤过这成折算
## （敌船不挂损伤簿，帆跟壳一处受创），凑齐的说法与签字面在 parley_road
const PARLEY_SAIL_BROKEN_FRAC := 0.55
## 「不成」里靠后的这一截算敌愈坚
const PARLEY_DEFY_TAIL := 0.25
const PARLEY_RESULTS := {"surrender": "敌竖降幡", "refuse": "敌不应", "defy": "敌愈坚"}
## 敌船阵脚（CombatMorale 的 state）给劝降加的胜算；struck（已降幡）喊即成
const PARLEY_STATE_BONUS := {"shaken": 0.04, "wavering": 0.10, "routing": 0.18}

## 下令回调：order_id → Array[Callable]；"*" 收全部
static var _handlers: Dictionary = {}
static var _parley_resolver := Callable()

## 号令状态
var windward := false
var load_mode := "mixed"
var damage_control := false
var board_ready := false
## 砍钩（只读态：敌对来钩时才有用、钩着时挥斧断索的加权）与张湿毡（火伤半、矢石轻、齐射慢、白刃减）
var cut_hooks := false
var wet_felt := false
## 聚队进度 0–1（备接舷令下后涨，撤令后落）
var muster := 0.0
var parley_cd := 0.0
var last_parley: Dictionary = {}
## 海战场（WorldMap）弱引用；岸上预览为 null
var world_ref: WeakRef = null
## 收键盘：海战场里开，岸上预览关（岸上 1–5 另有用处）
var keys_enabled := true
## 落令到旗舰分系统（battery / damage_model）；接线方自己落令时关掉
var auto_apply := true
## 人手总数覆盖（预览用；-1 = 读 Fleet 旗舰）
var crew_override := -1
## 劝降上下文覆盖（预览用：Callable() -> Dictionary，同 parley_context 的键）
var parley_source := Callable()

## 下过令没有（没下过就不落令，分系统保持自己的默认）
var _touched := false
## instance_id → 见过的最大船体（估敌船伤比例；面板随开战挂上，首见即满）
var _hull_seen: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _root: Control
var _card: PanelContainer
var _rows: Dictionary = {}
var _alloc_lbl: Label
var _effect_lbl: Label
var _note_lbl: Label
var _acc := 0.0
var _built := false
var _chip_accent: Dictionary = {}


# ── 挂载与注册 ───────────────────────────────────────────

## 挂到海战场 world 下（同一 world 只挂一块，已挂返回原节点）。world 为空返回 null。
static func mount(world: Node) -> CanvasLayer:
	if world == null or not is_instance_valid(world):
		return null
	for n in world.get_children():
		if n.is_in_group(GROUP):
			return n as CanvasLayer
	var panel: CanvasLayer = (load(SELF_PATH) as GDScript).new()
	panel.call("bind", world)
	world.add_child(panel)
	return panel


static func register_handler(order_id: String, cb: Callable) -> void:
	if not cb.is_valid():
		return
	var list: Array = _handlers.get(order_id, [])
	if not list.has(cb):
		list.append(cb)
	_handlers[order_id] = list


static func set_parley_resolver(cb: Callable) -> void:
	_parley_resolver = cb


## 下令那一刻海战场中央的浮字（WorldMap._on_combat_order 用，payload 即 order_issued 的那份）：写号令的中文名，不写内部 id——
## 「号令：抢风」；开关令再按一下撤了写「撤令：抢风」；装填侧重写轮到的那一档（「号令：专力装填」，轮回均装写「号令：均装」）。
## 认不得的令返回 ""（不上屏）
static func notice_for(order_id: String, payload := {}) -> String:
	var nm := str(ORDER_NAMES.get(order_id, ""))
	if nm == "":
		return ""
	if order_id == ORDER_LOAD:
		var ld = LOAD_TABLE.get(str(payload.get("load", "")))
		if ld is Dictionary:
			nm = str(ld.get("name", nm))
	elif payload.get("on") == false:
		return "撤令：%s" % nm
	return "号令：%s" % nm


## host 所在场景树里第一块号令面板；没有返回 null
static func panel_of(host: Node) -> Node:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	for n in host.get_tree().get_nodes_in_group(GROUP):
		if is_instance_valid(n):
			return n
	return null


## 查询入口（风流 / 弹道 / 损伤 / 白刃模块接线时用）：有面板取它的乘数，没有回中性表
static func modifiers_for(host: Node) -> Dictionary:
	var p := panel_of(host)
	if p != null and p.has_method("current_modifiers"):
		return p.call("current_modifiers")
	return neutral_modifiers()


func _init() -> void:
	add_to_group(GROUP_UI)
	add_to_group(GROUP)
	_rng.randomize()


func bind(world: Node) -> void:
	world_ref = weakref(world) if world != null else null


func _ready() -> void:
	layer = LAYER_INDEX
	_build()
	refresh()
	# 职事（总管 / 医人）不靠号令：挂上战场就写 DamageModel（开关 crew_role_effects）
	prime_role_effects.call_deferred()
	if not get_viewport().size_changed.is_connected(_layout):
		get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _process(delta: float) -> void:
	tick(delta)
	_acc += delta
	if _acc >= REFRESH_SEC:
		_acc = 0.0
		refresh()


# ── 纯函数：人手与效力 ──────────────────────────────────

## 中性乘数：不下令时的效力（乘数全 1.0，pinch_delta 为 0）
static func neutral_modifiers() -> Dictionary:
	return modifiers({})


## 号令状态 → 各岗分派（和为 1）。st 键：windward / damage / board（bool）/ load（LOADS）/ muster（0–1）
static func allocation(st: Dictionary) -> Dictionary:
	var w := {}
	for k in STATIONS:
		w[k] = float(BASE_ALLOC[k])
	if bool(st.get("windward", false)):
		w["sail"] *= WINDWARD_SAIL_W
	var ld: Dictionary = LOAD_TABLE.get(String(st.get("load", "mixed")), LOAD_TABLE["mixed"])
	w["guns"] *= float(ld["guns_w"])
	if bool(st.get("damage", false)):
		w["damage"] *= DAMAGE_W
	w["board"] *= 1.0 + BOARD_MUSTER_W * clampf(float(st.get("muster", 0.0)), 0.0, 1.0)
	var total := 0.0
	for k in STATIONS:
		total += float(w[k])
	var out := {}
	for k in STATIONS:
		out[k] = float(w[k]) / total
	return out


## 号令状态 → 效力乘数（交给接线方的全部口径；不下令时全 1.0）：
##   sail_drive 帆力 · turn_rate 转向 · pinch_delta 贴风（度，负 = 更贴，给机动模型加到 pinch 上）
##   reload_time 装填时长 · range 射程 · hit_hull / hit_sail / hit_crew 伤害去向份额 · ignite 引火 · fire_fight 扑火 · pump 排水
##   board_bonus 白刃 · board_range 钩距 · exposure 甲板人手挨矢石的伤亡
##   fire_taken 受火攻真头（张湿毡 0.5）· casualty_taken 受矢石伤亡（张湿毡 0.7）
##   cut_mul 守方吃紧抢砍钩缆的每合基率乘数（砍钩 1.5，combat_phases.json orders.cut_hooks.cut_chance_mul）
## STATION_KEYS：本面板管的四岗；outer 外键（属别 lane / 自家分系统管）不在这里斧头
static func modifiers(st: Dictionary) -> Dictionary:
	var a := allocation(st)
	var sail_r := float(a["sail"]) / float(BASE_ALLOC["sail"])
	# 弩炮岗按该令要的人手比：专力装填要的人给足了就是 LOAD_TABLE 的装填时长，别的号令抽走人手才再慢
	var ld_id := String(st.get("load", "mixed"))
	var guns_need := float(allocation({"load": ld_id})["guns"])
	var guns_r := float(a["guns"]) / guns_need
	var dmg_r := float(a["damage"]) / float(BASE_ALLOC["damage"])
	var board_r := float(a["board"]) / float(BASE_ALLOC["board"])
	var m := clampf(float(st.get("muster", 0.0)), 0.0, 1.0)
	var ld: Dictionary = LOAD_TABLE.get(ld_id, LOAD_TABLE["mixed"])
	var trim := clampf((sail_r - 1.0) / 0.45, 0.0, 1.0)
	var wet := bool(st.get("wet", false))
	return {
		"sail_drive": clampf(0.8 + 0.2 * sail_r, 0.7, 1.15),
		"turn_rate": clampf(0.85 + 0.15 * sail_r, 0.8, 1.1),
		"pinch_delta": -PINCH_TRIM * trim,
		"reload_time": float(ld["reload"]) / maxf(0.2, guns_r) * (1.15 if wet else 1.0),
		"range": float(ld["range"]),
		"hit_hull": float(ld["hull"]),
		"hit_sail": float(ld["sail"]),
		"hit_crew": float(ld["crew"]),
		"ignite": float(ld["ignite"]) * (0.5 if wet else 1.0),
		"fire_fight": clampf(dmg_r, 0.5, 4.0),
		"pump": clampf(dmg_r, 0.5, 4.0),
		"board_bonus": (1.0 + 0.35 * (board_r - 1.0) + 0.10 * m) * (0.9 if wet else 1.0),
		"board_range": 1.0 + 0.25 * m,
		"exposure": (1.0 + 0.5 * maxf(0.0, board_r - 1.0) * m + 0.1 * maxf(0.0, sail_r - 1.0)) * (0.7 if wet else 1.0),
		"cut_mul": CUT_CHANCE_MUL if bool(st.get("cut", false)) else 1.0,
	}


## 火攻风位：upwind 1 我居上风 / -1 敌居上风 / 0 相平（同 CombatStatusHud.weather_gauge）
static func fire_attack_factor(upwind: int) -> float:
	if upwind > 0:
		return FIRE_UPWIND
	if upwind < 0:
		return FIRE_DOWNWIND
	return 1.0


## 落到 ReloadAmmo 的两道令：{"emphasis": "balanced" / "sail" / "guns", "fire_mode": bool}
static func battery_orders(st: Dictionary) -> Dictionary:
	var ww := bool(st.get("windward", false))
	var ld := String(st.get("load", "mixed"))
	var emph := "balanced"
	if ww and ld != "rapid":
		emph = "sail"
	elif ld == "rapid" and not ww:
		emph = "guns"
	return {"emphasis": emph, "fire_mode": ld == "fire"}


## 落到 DamageModel 的损管令：救火按险情（有火或无险 → fire，只进水 → flood）；没令救火而备接舷 → fight；都没有 → auto
static func damage_mode_for(damage_on: bool, board_on: bool, fire: float, flood: float) -> String:
	if damage_on:
		return "flood" if fire <= 0.0 and flood >= 0.02 else "fire"
	return "fight" if board_on else "auto"


## 最大余数法把 total 人按分派取整（和恰为 total）
static func crew_split(total: int, alloc: Dictionary) -> Dictionary:
	var out := {}
	var rest: Array = []
	var used := 0
	for k in STATIONS:
		var exact := float(maxi(0, total)) * float(alloc.get(k, 0.0))
		var n := int(floor(exact))
		out[k] = n
		used += n
		rest.append([exact - float(n), k])
	rest.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var i := 0
	while used < total and i < rest.size():
		out[rest[i][1]] = int(out[rest[i][1]]) + 1
		used += 1
		i += 1
	return out


## 劝降胜算。ctx 键：enemy_morale（0–100）/ hull_frac（敌船体余比 0–1）/ ratio（我白刃战力 ÷ 敌）/ muster（0–1）/
## grappled（bool）/ enemy_state（CombatMorale 的 state，可缺）
static func parley_chance(ctx: Dictionary) -> float:
	var est := String(ctx.get("enemy_state", ""))
	if est == "struck":
		return 1.0
	var morale := float(ctx.get("enemy_morale", 60.0))
	var hull_frac := clampf(float(ctx.get("hull_frac", 1.0)), 0.0, 1.0)
	var ratio := maxf(0.0, float(ctx.get("ratio", 1.0)))
	var m := clampf(float(ctx.get("muster", 0.0)), 0.0, 1.0)
	var p := 0.03
	p += 0.9 * maxf(0.0, 55.0 - morale) / 100.0
	p += 0.35 * (1.0 - hull_frac)
	p += clampf(0.12 * (ratio - 1.0), -0.10, 0.20)
	p += 0.10 * m
	if bool(ctx.get("grappled", false)):
		p += 0.12
	p += float(PARLEY_STATE_BONUS.get(est, 0.0))
	return clampf(p, PARLEY_MIN, PARLEY_MAX)


## roll ∈ [0, 1)：小于胜算即降；不成里靠后的 PARLEY_DEFY_TAIL 一截是敌愈坚
static func parley_outcome(chance: float, roll: float) -> String:
	if roll < chance:
		return "surrender"
	if roll >= chance + (1.0 - chance) * (1.0 - PARLEY_DEFY_TAIL):
		return "defy"
	return "refuse"


static func _cn_tenths(p: float) -> String:
	if p >= 1.0:
		return "敌已降"
	if p < 0.05:
		return "难成"
	return "约%s成" % StatusHud.cn_num(clampi(roundi(p * 10.0), 1, 9), true)


# ── 号令 ──────────────────────────────────────────────

func state() -> Dictionary:
	# 二期两令开关关掉时旧玩法影像一道；读状态比问下没下要险：state() 里把不活的档位捏回 false，
	# modifiers / battery_orders / dispatch 都走这招，下不出也、下了也、半道开关倒都保关那条道
	return {"windward": windward, "load": load_mode, "damage": damage_control, "board": board_ready, "muster": muster,
		"cut": cut_hooks and Switches.on("order_cut_grapple"),
		"wet": wet_felt and Switches.on("order_wet_felt")}


func current_modifiers() -> Dictionary:
	return modifiers(state())


func current_allocation() -> Dictionary:
	return allocation(state())


func _world() -> Node:
	if world_ref == null:
		return null
	var w = world_ref.get_ref()
	return w if w is Node else null


func _ship() -> Node2D:
	return StatusHud.ship_of(_world())


## 旗舰人手（crew_override > -1 时用它）
func crew_total() -> int:
	if crew_override >= 0:
		return crew_override
	var fleet := StatusHud.autoload_node("Fleet")
	if fleet != null and fleet.has_method("flagship"):
		var fs = fleet.call("flagship")
		if fs is Dictionary:
			return int(fs.get("crew", 0))
	return 0


func _battle_over() -> bool:
	var w := _world()
	return w != null and w.get("resolved") == true


## 推进聚队与劝降冷却；_process 调，探针可直接调
func tick(delta: float) -> void:
	if board_ready:
		muster = minf(1.0, muster + delta / MUSTER_SEC)
	else:
		muster = maxf(0.0, muster - delta / DISPERSE_SEC)
	parley_cd = maxf(0.0, parley_cd - delta)
	for e in StatusHud.live_enemies(_world()):
		var id := (e as Object).get_instance_id()
		_hull_seen[id] = maxf(float(_hull_seen.get(id, 0.0)), StatusHud.prop_f(e, "hull_hp", 0.0))
	# 救火令按险情取损管令（只进水 → 戽水，有火或无险 → 救火），险情是会变的（lane w53-2）：只在下令那一刻取一次的话，
	# 只进水时下的令后来起了火仍按戽水派人，救火手封在两成——比不下令（均衡四成五）还少。令在就照现时险情重落（令同不改、不重派）
	if damage_control and not _battle_over():
		apply_to_ship()


## 落令：把号令落到旗舰身上现成的分系统（见头注「四」）。返回这次真改了哪些令（探针看）
func apply_to_ship() -> Dictionary:
	var done := {}
	if not auto_apply or not _touched:
		return done
	var ship := _ship()
	var bat := StatusHud.battery_of(ship)
	if bat != null:
		var bo := battery_orders(state())
		if bat.has_method("set_emphasis") and bat.get("emphasis") != bo["emphasis"]:
			bat.call("set_emphasis", bo["emphasis"])
			done["emphasis"] = bo["emphasis"]
		if bat.has_method("set_fire_mode") and bat.get("fire_mode") != bo["fire_mode"]:
			bat.call("set_fire_mode", bo["fire_mode"])
			done["fire_mode"] = bo["fire_mode"]
	var dm := StatusHud.damage_of(ship)
	if dm != null and dm.has_method("set_mode"):
		var fire := float(dm.call("fire_total")) if dm.has_method("fire_total") else 0.0
		var flood := float(dm.call("flood_frac")) if dm.has_method("flood_frac") else 0.0
		var want := damage_mode_for(damage_control, board_ready, fire, flood)
		if dm.get("mode") != want and dm.call("set_mode", want) == true:
			done["damage_mode"] = want
	# 张湿毡落到损伤簿：开关 order_wet_felt 开时按令写DamageModel.set_wet_felt（state() 已把开关 nibble 合关），
	# 关掉开关照 default false——不动DamageModel. 增伤与火线逐项导致减不 advance net
	if Switches.on("order_wet_felt") and dm != null and dm.has_method("set_wet_felt"):
		var want_wet := bool(state()["wet"])
		if dm.get("wet_felt") != want_wet:
			dm.call("set_wet_felt", want_wet)
			done["wet_felt"] = want_wet
	# 职事（开关 crew_role_effects）：总管 / 医人照 Crew.level_of 写到簿上；开关关掉时依旧写 0 级，照 wave53 开工前
	if dm != null and dm.has_method("set_steward") and dm.has_method("set_medic"):
		var want_s := _role_levels()
		if dm.get("steward_level") != int(want_s["steward"]):
			dm.call("set_steward", int(want_s["steward"]))
			done["steward"] = want_s["steward"]
		if dm.get("medic_level") != int(want_s["medic"]):
			dm.call("set_medic", int(want_s["medic"]))
			done["medic"] = want_s["medic"]
	return done


## 总管 / 医人 此刻的品级（开关 crew_role_effects；关掉一律 0 级）——mount 完 / apply_to_ship 共用
func _role_levels() -> Dictionary:
	var steward := 0
	var medic := 0
	if Switches.on("crew_role_effects"):
		var crew_node := StatusHud.autoload_node("Crew")
		if crew_node != null and crew_node.has_method("level_of"):
			steward = int(crew_node.call("level_of", "zongguan"))
			medic = int(crew_node.call("level_of", "yiren"))
	return {"steward": steward, "medic": medic}


## 挂上战场第一步就把职事写进 DamageModel（与 _touched 无关：开关开时 ring死带到）、
## 开没下令也立即生效，同 w53-16/_13 用 Mount 时一次亦就行
func prime_role_effects() -> Dictionary:
	var done := {}
	var dm := StatusHud.damage_of(_ship())
	if dm == null:
		return done
	var want := _role_levels()
	if dm.has_method("set_steward") and dm.get("steward_level") != int(want["steward"]):
		dm.call("set_steward", int(want["steward"]))
		done["steward"] = want["steward"]
	if dm.has_method("set_medic") and dm.get("medic_level") != int(want["medic"]):
		dm.call("set_medic", int(want["medic"]))
		done["medic"] = want["medic"]
	return done


## 劝降上下文：{"ok", "why"（不可喊的缘由）, "target", "dist", "enemy_morale", "hull_frac", "ratio", "muster", "grappled", "enemy_state"}
func parley_context() -> Dictionary:
	if parley_source.is_valid():
		var r = parley_source.call()
		if r is Dictionary:
			var ctx: Dictionary = r.duplicate()
			ctx["muster"] = muster
			if not ctx.has("ok"):
				ctx["ok"] = true
			return ctx
	var w := _world()
	var ship := StatusHud.ship_of(w)
	var ne := StatusHud.nearest_enemy(w, ship)
	if ne.is_empty():
		return {"ok": false, "why": "无敌可喊"}
	var enemy: Node = ne["node"]
	var dist := float(ne["dist"])
	if dist > HAIL_RANGE:
		return {"ok": false, "why": "相距过远", "target": enemy, "dist": dist}
	var hull := StatusHud.prop_f(enemy, "hull_hp", 0.0)
	var seen := maxf(float(_hull_seen.get(enemy.get_instance_id(), hull)), hull)
	var enemy_state := "struck" if enemy.get("struck") == true else String(StatusHud.morale_meta(enemy).get("state", ""))
	var ctx := {
		"ok": true, "target": enemy, "dist": dist,
		"enemy_morale": StatusHud.prop_f(enemy, "enemy_morale", 60.0),
		"hull_frac": hull / seen if seen > 0.0 else 1.0,
		"ratio": _own_board_power() / maxf(1.0, float(enemy.call("combat_strength"))) if enemy.has_method("combat_strength") else _own_board_power(),
		"muster": muster,
		"grappled": enemy.get("grappled") == true,
		# 敌将自己降了（喊话劝降得手、船节点 struck）而士气簿没降：照簿上降幡算，签面写「敌已降」，不再写「可喊 约 N 成」（lane w53-2）
		"enemy_state": enemy_state,
	}
	# 战斗方案一期：劝降挂到敌船身上、三样凑齐才亮（开关 parley_on_ship 开时）；关掉照旧的距离一尺
	if Switches.on("parley_on_ship") and enemy_state != "struck":
		var road := parley_road(ctx)
		if not bool(road["lit"]):
			ctx["ok"] = false
			ctx["why"] = String(road["road"])
			ctx["road"] = road
			return ctx
		ctx["road"] = road
	return ctx


## 劝降三样（开关 parley_on_ship）：①被钩住（敌船先钩上我们不算）；②帆索残——敌船不挂损伤簿，帆跟壳一处受创，
## 船体伤过 PARLEY_SAIL_BROKEN_FRAC 折成帆被打坏；③已动摇（士气簿的 shaken / wavering / routing）。
## 返回 {"lit", "road", "have"（三样的真值表）}；敌已 struck 由 parley_context 提前走「敌已降」。
static func parley_road(ctx: Dictionary) -> Dictionary:
	var have := {
		"grappled": bool(ctx.get("grappled", false)),
		"sail_broken": float(ctx.get("hull_frac", 1.0)) <= PARLEY_SAIL_BROKEN_FRAC,
		"shaken": String(ctx.get("enemy_state", "")) in ["shaken", "wavering", "routing"],
	}
	var need := PackedStringArray()
	if not have["grappled"]:
		need.append("未钩住")
	if not have["sail_broken"]:
		need.append("帆尚在")
	if not have["shaken"]:
		need.append("阵脚未乱")
	return {"lit": need.is_empty(), "road": "可喊话" if need.is_empty() else "、".join(need), "have": have}


## 我方白刃战力：同 WorldMap._board_enemy 的口径（水手 × 士气系数 × 将领系数），读 Fleet
func _own_board_power() -> float:
	var fleet := StatusHud.autoload_node("Fleet")
	if fleet == null:
		return 1.0
	var crew := float(fleet.call("total_crew")) if fleet.has_method("total_crew") else 0.0
	var mf := float(fleet.call("morale_factor")) if fleet.has_method("morale_factor") else 1.0
	var cp := float(fleet.call("captain_power")) if fleet.has_method("captain_power") else 1.0
	return maxf(1.0, crew * mf * cp)


## 二期两令的总开关：关掉时旧玩法没有这两道，签面写「未接」也不收。
## 期2接国用的是 combat_phases.json 的 cut_hooks / wet_screens；data 没这两行的版本也收
static func order_switch_for(order_id: String) -> String:
	match order_id:
		"cut":
			return "order_cut_grapple"
		"wet":
			return "order_wet_felt"
	return ""


func order_enabled(order_id: String) -> bool:
	if _battle_over():
		return false
	var sw := order_switch_for(order_id)
	if sw != "" and not Switches.on(sw):
		return false
	if order_id == ORDER_PARLEY:
		return parley_cd <= 0.0 and bool(parley_context().get("ok", false))
	return order_id in ORDERS


func order_active(order_id: String) -> bool:
	match order_id:
		ORDER_WINDWARD:
			return windward
		ORDER_LOAD:
			return load_mode != "mixed"
		ORDER_DAMAGE:
			return damage_control
		ORDER_BOARD:
			return board_ready
		ORDER_CUT:
			return cut_hooks
		ORDER_WET:
			return wet_felt
	return false


## 下令入口（键盘 / 点签 / 接线方都走这里）。返回 payload；不可下的令返回 {}
func issue(order_id: String, roll := -1.0) -> Dictionary:
	if not order_id in ORDERS or _battle_over():
		return {}
	var sw := order_switch_for(order_id)
	if sw != "" and not Switches.on(sw):
		return {}
	var payload := {}
	match order_id:
		ORDER_WINDWARD:
			windward = not windward
			payload = {"on": windward}
			_note("已令抢风：缭手上缭，贴风走。" if windward else "撤抢风：缭手回岗。")
		ORDER_LOAD:
			load_mode = LOADS[(LOADS.find(load_mode) + 1) % LOADS.size()]
			payload = {"load": load_mode, "table": LOAD_TABLE[load_mode].duplicate()}
			match load_mode:
				"rapid":
					_note("已令专力装填：闲手递矢拽炮。")
				"fire":
					_note("已令火攻：换装火箭火球。")
				_:
					_note("装填复归均装。")
		ORDER_DAMAGE:
			damage_control = not damage_control
			payload = {"on": damage_control}
			_note("已令救火：分人戽水扑火。" if damage_control else "撤救火：水火岗回岗。")
		ORDER_BOARD:
			board_ready = not board_ready
			payload = {"on": board_ready, "muster": muster}
			_note("已令备接舷：甲士执钩拒聚舷边。" if board_ready else "撤备接舷：甲士散回。")
		ORDER_CUT:
			cut_hooks = not cut_hooks
			payload = {"on": cut_hooks}
			_note("已令砍钩：斧手握定，见钩索即斫。" if cut_hooks else "撤砍钩：斧手回舷。")
		ORDER_WET:
			wet_felt = not wet_felt
			payload = {"on": wet_felt}
			_note("已令张湿毡：舷边张起过水的厚毡。" if wet_felt else "撤湿毡：舷边收起。")
		ORDER_PARLEY:
			payload = _parley(roll)
			if payload.is_empty():
				return {}
	_touched = true
	payload["order"] = order_id
	payload["name"] = ORDER_NAMES[order_id]
	payload["state"] = state()
	payload["modifiers"] = current_modifiers()
	payload["alloc"] = current_allocation()
	payload["battery"] = battery_orders(state())
	payload["applied"] = apply_to_ship()
	refresh()
	order_issued.emit(order_id, payload)
	_dispatch(order_id, payload)
	if order_id == ORDER_PARLEY:
		parley_resolved.emit(payload)
	return payload


func _dispatch(order_id: String, payload: Dictionary) -> void:
	for key in [order_id, "*"]:
		for cb in _handlers.get(key, []).duplicate():
			if (cb as Callable).is_valid():
				(cb as Callable).call(order_id, payload)


## 喊话劝降：可喊才喊，喊了就进冷却。roll ∈ [0, 1) 由调用方给（探针定数），缺省随机
func _parley(roll: float) -> Dictionary:
	if parley_cd > 0.0:
		_note("劝降候 %d 秒。" % ceili(parley_cd))
		return {}
	var ctx := parley_context()
	if not bool(ctx.get("ok", false)):
		_note("%s，喊话不及。" % String(ctx.get("why", "无敌可喊")))
		return {}
	var chance := parley_chance(ctx)
	var r := roll if roll >= 0.0 else _rng.randf()
	var result := parley_outcome(chance, r)
	var out := {"attempted": true, "chance": chance, "roll": r, "result": result, "context": ctx,
		"target": ctx.get("target", null)}
	if _parley_resolver.is_valid():
		var ext = _parley_resolver.call(ctx)
		if ext is Dictionary and String(ext.get("result", "")) in PARLEY_RESULTS:
			for k in ext.keys():
				out[k] = ext[k]
			result = String(out["result"])
	# 建议的士气增减（接线方落到 Fleet / 敌船）：敌愈坚则敌 +4、我 -2
	out["morale_delta"] = {"enemy": 4, "own": -2} if result == "defy" else {"enemy": 0, "own": 0}
	parley_cd = PARLEY_COOLDOWN
	last_parley = out
	match result:
		"surrender":
			_note("喊话劝降，敌竖降幡。")
		"defy":
			_note("喊话劝降，敌愈坚，反放矢石。")
		_:
			_note("喊话劝降，敌不应。")
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not keys_enabled or _battle_over():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: Key = (event as InputEventKey).keycode
	for id in ORDERS:
		if code in ORDER_KEYS[id]:
			get_viewport().set_input_as_handled()
			issue(id)
			return


# ── 签面文案 ────────────────────────────────────────────

func state_text(order_id: String) -> String:
	match order_id:
		ORDER_WINDWARD:
			return "已令" if windward else "未令"
		ORDER_LOAD:
			return String(LOAD_TABLE[load_mode]["name"])
		ORDER_DAMAGE:
			return "已令" if damage_control else "未令"
		ORDER_BOARD:
			if board_ready:
				return "已聚" if muster >= 1.0 else "聚队 %.1f秒" % ((1.0 - muster) * MUSTER_SEC)
			return "散队中" if muster > 0.0 else "未令"
		ORDER_PARLEY:
			if _battle_over():
				return "战毕"
			if parley_cd > 0.0:
				return "候 %d秒" % ceili(parley_cd)
			var ctx := parley_context()
			if not bool(ctx.get("ok", false)):
				return String(ctx.get("why", "无敌可喊"))
			var road = ctx.get("road", null)
			if road is Dictionary and bool((road as Dictionary).get("lit", false)):
				return "可喊 %s（钩住・帆残・敌乱）" % _cn_tenths(parley_chance(ctx))
			return "可喊 " + _cn_tenths(parley_chance(ctx))
		ORDER_CUT:
			return "未接" if not Switches.on("order_cut_grapple") else ("已令" if cut_hooks else "未令")
		ORDER_WET:
			return "未接" if not Switches.on("order_wet_felt") else ("已令" if wet_felt else "未令")
	return ""


## 人手一行。旗舰有损伤簿（DamageModel）就写它此刻的实派：「人手 帆12 弩炮24 水火6 余38」；
## 没有就按本面板的分派：「人手 帆24 弩炮32 水火8 甲士16」
func alloc_text() -> String:
	var dm := StatusHud.damage_of(_ship())
	if dm != null and dm.has_method("crew_split"):
		var sp = dm.call("crew_split")
		if sp is Dictionary:
			var water := int(sp.get("fire", 0)) + int(sp.get("flood", 0)) + int(sp.get("jury", 0))
			return "人手 帆%d 弩炮%d 水火%d 余%d" % [int(sp.get("sail", 0)), int(sp.get("weapons", 0)), water, int(sp.get("spare", 0))]
	var total := crew_total()
	var a := current_allocation()
	var bits := PackedStringArray()
	if total > 0:
		var split := crew_split(total, a)
		for k in STATIONS:
			bits.append("%s%d" % [STATION_NAMES[k], int(split[k])])
	else:
		for k in STATIONS:
			bits.append("%s%s成" % [STATION_NAMES[k], StatusHud.cn_num(clampi(roundi(float(a[k]) * 10.0), 0, 10), true)])
	return "人手 " + " ".join(bits)


## 效力一行：只写偏离平时 3% 以上的几项；排进面板时按条折行（wrap_items），不在一条中间断开
func effect_text() -> String:
	var m := current_modifiers()
	var bits := PackedStringArray()
	_pct(bits, "帆力", float(m["sail_drive"]), "增", "减")
	if float(m["pinch_delta"]) <= -0.5:
		bits.append("贴风%d°" % roundi(-float(m["pinch_delta"])))
	_pct(bits, "装填", float(m["reload_time"]), "慢", "快")
	_pct(bits, "射程", float(m["range"]), "远", "近")
	if float(m["ignite"]) > 1.03:
		bits.append("引火%.0f倍" % float(m["ignite"]))
	if float(m["fire_fight"]) > 1.03:
		bits.append("扑火%.1f倍" % float(m["fire_fight"]))
	_pct(bits, "白刃", float(m["board_bonus"]), "增", "减")
	_pct(bits, "钩距", float(m["board_range"]), "增", "减")
	_pct(bits, "伤亡", float(m["exposure"]), "增", "减")
	if load_mode == "fire":
		bits.append("火攻须居上风")
	if bool(state().get("wet", false)):
		bits.append("毡罩火")
	if bool(state().get("cut", false)):
		bits.append("斧候钩")
	if bits.is_empty():
		bits.append("平时")
	bits.insert(0, "效力")
	return "　".join(bits)


## 按条折行：items 用全角空格接成一行，量到 width 就换行（每条整块，不从中间断）
static func wrap_items(items: PackedStringArray, font: Font, font_size: int, width: float) -> String:
	var lines := PackedStringArray()
	var cur := ""
	for it in items:
		var trial := it if cur == "" else cur + "　" + it
		if cur != "" and font != null and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(cur)
			cur = it
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return "\n".join(lines)


static func _pct(bits: PackedStringArray, label: String, v: float, up: String, down: String) -> void:
	var d := v - 1.0
	if absf(d) < 0.03:
		return
	bits.append("%s%s%d%%" % [label, up if d > 0.0 else down, roundi(absf(d) * 100.0)])


func _note(text: String) -> void:
	if _note_lbl != null:
		_note_lbl.text = text


# ── 节点 ──────────────────────────────────────────────

func refresh() -> void:
	if not _built:
		return
	for id in ORDERS:
		var row: Dictionary = _rows[id]
		# 二期两令的开关关掉时：签行直接不出，与 wave53 开工前的五道签逐字一致（issue / order_enabled 同一闸也照过）
		var sw := order_switch_for(id)
		(row["row"] as Control).visible = (sw == "" or Switches.on(sw))
		var chip := row["chip"] as Button
		var active := order_active(id)
		if _chip_accent.get(id, null) != active:
			_chip_accent[id] = active
			UiTheme.style_chip(chip, active)
		chip.disabled = not order_enabled(id)
		var st := row["state"] as Label
		st.text = state_text(id)
		st.add_theme_color_override("font_color", UiTheme.PAPER_CINNABAR if active else UiTheme.PAPER_DIM)
	_alloc_lbl.text = alloc_text()
	_effect_lbl.text = wrap_items(effect_text().split("　"), UiTheme.font(), 16, PANEL_W - 24.0)
	# 救火令在时，火与水此消彼长，损管令跟着险情换
	apply_to_ship()


func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_card = PanelContainer.new()
	_card.name = "OrdersCard"
	UiTheme.paper_card(_card)
	_card.self_modulate = UiTheme.DOOR_PAPER_TINT
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(PANEL_W, 0)
	_root.add_child(_card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	_card.add_child(margin)

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 5)
	margin.add_child(body)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)
	var title := Label.new()
	title.text = "号令"
	title.add_theme_font_override("font", UiTheme.title_font())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.PAPER_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var keys := Label.new()
	keys.text = "按 1–7 下令"
	keys.add_theme_font_override("font", UiTheme.font())
	keys.add_theme_font_size_override("font_size", 16)
	keys.add_theme_color_override("font_color", UiTheme.PAPER_DIM)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(keys)
	body.add_child(_rule())

	for i in range(ORDERS.size()):
		var id: String = ORDERS[i]
		var row := HBoxContainer.new()
		row.name = "Order_" + id
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		var chip := Button.new()
		chip.text = "%d %s" % [i + 1, ORDER_NAMES[id]]
		chip.focus_mode = Control.FOCUS_NONE
		chip.tooltip_text = ORDER_TIPS[id]
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiTheme.style_chip(chip, false)
		_chip_accent[id] = false
		chip.custom_minimum_size = Vector2(132, 32)
		chip.pressed.connect(issue.bind(id))
		row.add_child(chip)
		var st := Label.new()
		st.add_theme_font_override("font", UiTheme.font())
		st.add_theme_font_size_override("font_size", 16)
		st.add_theme_color_override("font_color", UiTheme.PAPER_DIM)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		st.clip_text = true
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(st)
		body.add_child(row)
		_rows[id] = {"row": row, "chip": chip, "state": st}

	body.add_child(_rule())
	_alloc_lbl = _foot(UiTheme.PAPER_TEXT)
	body.add_child(_alloc_lbl)
	_effect_lbl = _foot(UiTheme.PAPER_TIDE)
	_effect_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.add_child(_effect_lbl)
	_note_lbl = _foot(UiTheme.PAPER_GOLD)
	_note_lbl.text = "号令未下，人手照平时分派。"
	body.add_child(_note_lbl)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.PAPER_GOLD, 0.45)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _foot(color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiTheme.font())
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 左侧，顶边落在 WorldMap 顶匾（TideBar）下沿之下；找不到顶匾用 TOP_FALLBACK
func _layout() -> void:
	if _card == null or not is_inside_tree():
		return
	var top := TOP_FALLBACK
	var w := _world()
	if w != null:
		var tide := w.get_node_or_null("CanvasLayer/HUD/TideBar") as Control
		if tide != null and tide.is_visible_in_tree() and tide.size.y > 0.0:
			top = tide.get_global_rect().end.y + 12.0
			if not tide.item_rect_changed.is_connected(_layout):
				tide.item_rect_changed.connect(_layout)
	_card.position = Vector2(MARGIN, top)
	_card.reset_size()
