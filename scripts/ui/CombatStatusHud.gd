## 海战状态条：风、受风、敌舷角、风位、弹药、装填、帆、舵、浸水、士气——一条宣纸横笺压在海面左下，
## 只写读得到、可核对的数；哪一格没有来源就写「未计」，不拿船体血量去编帆、舵、浸水。
##
## 数从哪来（snapshot_of 逐层合并，后来的盖前面的）：
##   一、战场现有字段：旗舰 Ship 的 wind_vector / wind_strength / sail_gear / rotation / fire_cooldown，
##       Fleet 的 morale，场上 PirateShip*（hull_hp > 0，与 WorldMap._is_live_pirate 同口径）里最近一艘算舷角、风位、距离；
##   二、同波次各模块的现成读数（module_snapshot；在就读、不在就跳过，只读、鸭子型，不 preload 它们）：
##       world.sea_state() / SeaState.active()（风流）、world.maneuver_snapshot()（帆向与 pinch）、
##       world.fire_arc_of / boarding_approach_of（射界、能否接舷）、ship.battery（ReloadAmmo：弹药、两舷装填）、
##       ship.damage_model.summary()（DamageModel：帆、舵、浸水、火）、船节点 meta nk1_combat_morale（CombatMorale：战中士气）；
##   三、鸭子型：world / ship 若有 combat_status() -> Dictionary，并进来（接线方自己汇总时用）；
##   四、静态注册：register_source(key, cb)，cb.call(world, ship) -> Dictionary，同 key 再注册即替换；
##   另：节点上的 source（Callable）有值时只用它（岸上预览 CombatShoreHook 给样例数据）。
## 快照的键见 SNAPSHOT_KEYS。格子文案由 format_cells 纯函数出（探针可不建节点直接验）。
##
## 挂法：CombatStatusHud.mount(world)（WorldMap 日后接线用；本文件不改 WorldMap），或经 CombatShoreHook.mount_combat_ui。
## CanvasLayer 自加 nk1_combat_ui / nk1_combat_status 两组供探针找；层号在 WorldMap 的 HUD（1）之上、
## BoardingStage（55）/ CombatLetterbox（58）之下——入战、出战墨边照旧盖在它上面，不取代墨边。
## headless 下照样建节点（量排版、验文案），不做淡入。不暂停、不吞输入、不入存档。
extends CanvasLayer

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const SELF_PATH := "res://scripts/ui/CombatStatusHud.gd"

const GROUP_UI := "nk1_combat_ui"
const GROUP := "nk1_combat_status"
const LAYER_INDEX := 20
## 读数刷新间隔（秒）：十分之一秒一次足够，逐帧拼字白费
const REFRESH_SEC := 0.1
## 左下留边；右侧让出 WorldMap 的小地图（找不到小地图节点时按 MINIMAP_FALLBACK_W 让）
const MARGIN := 16.0
const MINIMAP_FALLBACK_W := 170.0
const GAP := 12.0

## 同波次模块（lane combat02 风流 / 机动）的脚本路径：只按路径探、在才 load，不 preload（它们不在也照常编译）
const SEA_STATE_PATH := "res://scripts/combat/SeaState.gd"
## CombatMorale（lane combat06）挂件写在船节点上的 meta 键
const MORALE_META := &"nk1_combat_morale"

## 快照键（数值 -1 / 空字典 = 未计）
const SNAPSHOT_KEYS := {
	"wind_dir": "Vector2 下风向单位向量，同 Ship.wind_vector / SeaState.wind_to：(0, 1) 是北风",
	"wind_force": "float 风力，WorldMap / Ship.wind_strength 口径（平时 80）；÷20 取级",
	"wind_name": "String 来风名（「东北风」）；缺省按 wind_dir 取八方",
	"heading": "Vector2 船首向单位向量（Vector2.UP 转船角）",
	"sail_gear": "int 0 收帆 / 1 半帆 / 2 满帆",
	"pinch": "float 顶风区半角（度，船首进到来风两侧这么近帆就不吃风；ManeuverModel.pinch_deg），缺省 PINCH_DEFAULT",
	"sail_state": "String 帆向（顶风 / 抢风 / 侧风 / 顺风；ManeuverModel.sail_state），缺省按 heading 与 pinch 算",
	"sail": "float 帆完好 0–1",
	"rudder": "float 舵完好 0–1",
	"mast_down": "bool 桅折",
	"flood": "float 浸水 0–1（全船各舱灌了几成）",
	"fire": "float 火势（各处火势之和，0 = 无火；满一处及以上写大火）",
	"morale": "float 士气 0–100；morale_label 有则照写（CombatMorale 的状态名）",
	"ammo": "Dictionary 弹药存量 {弹种: 数}；键认 AMMO_NAMES",
	"ammo_max": "Dictionary 定额（可缺；定额 0 的弹种本船不带、不写，低于 AMMO_LOW 写朱）",
	"reload": "Dictionary {\"port\": 秒, \"starboard\": 秒} 两舷剩余装填秒数（INF = 该舷无位）；或 reload_left: float 两舷同",
	"has_target": "bool 有无敌踪；target_bearing（度，正 = 右舷）/ target_dist / upwind（1 我居上风，-1 敌居上风，0 相平）",
	"in_arc": "bool 敌在射界（缺省按舷角 60°–120°）",
	"can_board": "bool 此刻能接舷（缺省按 target_dist ≤ board_distance）",
	"boarding": "bool 已钩住敌船（WorldMap.boarding）",
}

## 弹种短名（ReloadAmmo 的 jian / nujian / shi / yacang（石弹尽后拆的压舱石）/ huoyao 与常见英文键都认；认不出的键原样写）
const AMMO_NAMES := {
	"jian": "箭", "nujian": "弩", "shi": "石", "yacang": "舱石", "huoyao": "药",
	"arrow": "箭", "arrows": "箭", "bolt": "弩", "bolts": "弩", "stone": "石", "stones": "石",
	"fire": "火", "fire_pot": "火", "gunpowder": "药", "powder": "药", "shot": "弹",
}
const AMMO_ORDER := ["jian", "arrow", "arrows", "nujian", "bolt", "bolts", "shi", "yacang", "stone", "stones",
	"fire", "fire_pot", "huoyao", "gunpowder", "powder", "shot"]
## 存量低于定额这一比例写朱（同 ReloadAmmo.LOW_RATIO 告急线）
const AMMO_LOW := 0.25

## 格子：键、题
const CELLS := [
	["wind", "风"], ["trim", "受风"], ["bearing", "敌舷角"], ["gauge", "风位"],
	["ammo", "弹药"], ["reload", "装填"], ["sail", "帆"], ["rudder", "舵"],
	["flood", "浸水"], ["morale", "士气"],
]

## 帆向分档（θ = 船首与来风夹角，度）：θ < pinch 顶风 · < BEAM_FROM 抢风 · < RUN_FROM 侧风 · 其余顺风
## （与 ManeuverModel.sail_word 同一口径；那边在就直接用它给的 sail_state 与 pinch）
const PINCH_DEFAULT := 50.0
const BEAM_FROM := 80.0
const RUN_FROM := 135.0
## 舷弩 / 舷炮射界：舷角 60°–120°（正横前后各 30°，同 WorldMap.fire_arc_of 的默认半角）
const ARC_MIN := 60.0
const ARC_MAX := 120.0
## 风位判定：敌在我下风向这一侧的余弦阈
const GAUGE_COS := 0.3
## 能接舷的距离：读 WorldMap.BOARD_DISTANCE（按 G 接舷的距离），读不到用这个
const BOARD_DISTANCE_FALLBACK := 140.0
const COMPASS8 := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
const CN_DIGITS := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

## 静态注册的数据源：key → Callable(world, ship) -> Dictionary
static var _sources: Dictionary = {}

## 数据来源：world（海战场）/ ship（旗舰）弱引用；source 有值时只用 source
var world_ref: WeakRef = null
var ship_ref: WeakRef = null
var source := Callable()

var _root: Control
var _strip: PanelContainer
var _row: HBoxContainer
var _cells: Dictionary = {}
var _last: Dictionary = {}
var _acc := 0.0
var _built := false


# ── 挂载与注册 ───────────────────────────────────────────

## 挂到海战场 world 下（同一 world 只挂一副，已挂返回原节点）。world 为空返回 null。
static func mount(world: Node, ship: Node = null) -> CanvasLayer:
	if world == null or not is_instance_valid(world):
		return null
	for n in world.get_children():
		if n.is_in_group(GROUP):
			return n as CanvasLayer
	var hud: CanvasLayer = (load(SELF_PATH) as GDScript).new()
	hud.call("bind", world, ship)
	world.add_child(hud)
	return hud


static func register_source(key: String, cb: Callable) -> void:
	if key.strip_edges() == "" or not cb.is_valid():
		return
	_sources[key] = cb


func _init() -> void:
	add_to_group(GROUP_UI)
	add_to_group(GROUP)


func bind(world: Node, ship: Node = null) -> void:
	world_ref = weakref(world) if world != null else null
	ship_ref = weakref(ship) if ship != null else null


func _ready() -> void:
	layer = LAYER_INDEX
	_build()
	refresh()
	if not get_viewport().size_changed.is_connected(_layout):
		get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


func _process(delta: float) -> void:
	_acc += delta
	if _acc < REFRESH_SEC:
		return
	_acc = 0.0
	refresh()


# ── 取数 ──────────────────────────────────────────────

## Godot 4.6 的 Object.get 只收属性名，缺属性返回 null（带默认值的写法编不过）；取属性一律走这几个判空封装。
static func prop_f(o: Object, prop: String, fallback: float) -> float:
	if o == null or not is_instance_valid(o):
		return fallback
	var v = o.get(prop)
	if v is float or v is int:
		return float(v)
	return fallback


static func prop_v2(o: Object, prop: String, fallback: Vector2) -> Vector2:
	if o == null or not is_instance_valid(o):
		return fallback
	var v = o.get(prop)
	return v if v is Vector2 else fallback


static func autoload_node(node_name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(node_name)
	return null


## 海战场上的旗舰：WorldMap 的 ship 成员，没有就找名叫 Ship 的子节点
static func ship_of(world: Node) -> Node2D:
	if world == null or not is_instance_valid(world):
		return null
	var s = world.get("ship")
	if s is Node2D and is_instance_valid(s):
		return s
	return world.get_node_or_null("Ship") as Node2D


## 场上活着的敌船（节点名 PirateShip 前缀、hull_hp > 0；与 WorldMap._is_live_pirate 同口径）
static func live_enemies(world: Node) -> Array:
	var out: Array = []
	if world == null or not is_instance_valid(world):
		return out
	for c in world.get_children():
		if c is Node2D and String(c.name).begins_with("PirateShip") and prop_f(c, "hull_hp", 0.0) > 0.0:
			out.append(c)
	return out


## 最近一艘活敌：{"node", "dist", "bearing"（度，正 = 右舷）, "to"（我→敌向量）}；没有返回 {}
static func nearest_enemy(world: Node, ship: Node2D) -> Dictionary:
	if ship == null or not is_instance_valid(ship):
		return {}
	var best: Node2D = null
	var best_d := INF
	for e in live_enemies(world):
		var d := (e as Node2D).global_position.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return {}
	var to := best.global_position - ship.global_position
	var heading := Vector2.UP.rotated(ship.global_rotation)
	return {"node": best, "dist": best_d, "bearing": relative_bearing(heading, to), "to": to}


## 可按 G 接舷的距离：读 world 脚本常量 BOARD_DISTANCE，读不到用 BOARD_DISTANCE_FALLBACK
static func board_distance(world: Node) -> float:
	if world != null and is_instance_valid(world) and world.get_script() is Script:
		var consts: Dictionary = (world.get_script() as Script).get_script_constant_map()
		var v = consts.get("BOARD_DISTANCE", null)
		if v is float or v is int:
			return float(v)
	return BOARD_DISTANCE_FALLBACK


## 第一层：战场现有字段
static func base_snapshot(world: Node, ship: Node2D) -> Dictionary:
	var snap := {
		"has_ship": false, "has_target": false, "boarding": false,
		"wind_dir": Vector2(0, 1), "wind_force": -1.0, "heading": Vector2.UP, "sail_gear": -1,
		"sail": -1.0, "rudder": -1.0, "flood": -1.0, "fire": -1.0, "morale": -1.0,
		"ammo": {}, "ammo_max": {},
	}
	if ship != null and is_instance_valid(ship):
		snap["has_ship"] = true
		var wd := prop_v2(ship, "wind_vector", Vector2(0, 1))
		snap["wind_dir"] = wd.normalized() if wd.length() > 0.001 else Vector2.ZERO
		snap["wind_force"] = prop_f(ship, "wind_strength", -1.0)
		snap["heading"] = Vector2.UP.rotated(ship.global_rotation)
		snap["sail_gear"] = int(prop_f(ship, "sail_gear", -1.0))
		snap["reload_left"] = maxf(0.0, prop_f(ship, "fire_cooldown", 0.0))
	var fleet := autoload_node("Fleet")
	if fleet != null:
		snap["morale"] = prop_f(fleet, "morale", -1.0)
	if world != null and is_instance_valid(world):
		snap["boarding"] = world.get("boarding") == true
		snap["board_distance"] = board_distance(world)
	var ne := nearest_enemy(world, ship)
	if not ne.is_empty():
		snap["has_target"] = true
		snap["target"] = ne["node"]
		snap["target_dist"] = ne["dist"]
		snap["target_bearing"] = ne["bearing"]
		snap["upwind"] = weather_gauge(snap["wind_dir"], ne["to"])
	return snap


## 第二层：同波次各模块的现成读数（风流 / 机动 / 弹药 / 损伤 / 士气）。模块不在、接口对不上，就什么也不给。
static func module_snapshot(world: Node, ship: Node2D, target: Node2D = null) -> Dictionary:
	var out := {}
	var sea = sea_of(world)
	if sea is Object and is_instance_valid(sea):
		var wt = sea.get("wind_to")
		if wt is Vector2 and (wt as Vector2).length() > 0.001:
			out["wind_dir"] = (wt as Vector2).normalized()
		var ws = sea.get("wind_speed")
		if ws is float or ws is int:
			out["wind_force"] = float(ws)
		if sea.has_method("wind_name"):
			out["wind_name"] = str(sea.call("wind_name"))
	var man := _duck(world, "maneuver_snapshot")
	for k in ["pinch", "sail_state"]:
		if man.has(k):
			out[k] = man[k]
	if target != null and is_instance_valid(target) and ship != null and is_instance_valid(ship):
		if world.has_method("fire_arc_of"):
			var arc = world.call("fire_arc_of", ship, target)
			if arc is Dictionary and arc.has("in_arc"):
				out["in_arc"] = arc["in_arc"] == true
		if world.has_method("boarding_approach_of"):
			var ap = world.call("boarding_approach_of", ship, target)
			if ap is Dictionary and ap.has("ok"):
				out["can_board"] = ap["ok"] == true
	if ship == null or not is_instance_valid(ship):
		return out
	var bat = battery_of(ship)
	if bat != null:
		var am = bat.get("ammo")
		var mx = bat.get("ammo_max")
		if am is Dictionary:
			out["ammo"] = (am as Dictionary).duplicate()
			out["ammo_max"] = (mx as Dictionary).duplicate() if mx is Dictionary else {}
		out["reload"] = {"port": float(bat.call("reload_left", -1)), "starboard": float(bat.call("reload_left", 1))}
	var dm = damage_of(ship)
	if dm != null:
		var s = dm.call("summary")
		if s is Dictionary:
			var sm: Dictionary = s
			for k in ["sail", "rudder", "flood", "fire"]:
				if sm.get(k) is float or sm.get(k) is int:
					out[k] = float(sm[k])
			if sm.has("mast_down"):
				out["mast_down"] = sm["mast_down"] == true
	var mm := morale_meta(ship)
	if mm.get("value") is float or mm.get("value") is int:
		out["morale"] = float(mm["value"])
		if String(mm.get("label", "")) != "":
			out["morale_label"] = String(mm["label"])
	return out


## 本场海况：world.sea_state()（WorldMap 接了风流的查询口）→ SeaState.active()（静态登记口）→ null
static func sea_of(world: Node) -> Object:
	if world != null and is_instance_valid(world) and world.has_method("sea_state"):
		var s = world.call("sea_state")
		if s is Object and is_instance_valid(s):
			return s
	if ResourceLoader.exists(SEA_STATE_PATH):
		var sc = load(SEA_STATE_PATH)
		if sc is Script and (sc as Script).has_method("active"):
			var a = (sc as Script).call("active")
			if a is Object and is_instance_valid(a):
				return a
	return null


## 船上的装填弹药簿（ReloadAmmo 实例约定挂在 battery）；没有 / 不像返回 null
static func battery_of(ship: Object) -> Object:
	if ship == null or not is_instance_valid(ship):
		return null
	var b = ship.get("battery")
	if b is Object and is_instance_valid(b) and (b as Object).has_method("reload_left"):
		return b
	return null


## 船上的损伤簿（DamageModel 实例约定挂在 damage_model）；没有 / 不像返回 null
static func damage_of(ship: Object) -> Object:
	if ship == null or not is_instance_valid(ship):
		return null
	var d = ship.get("damage_model")
	if d is Object and is_instance_valid(d) and (d as Object).has_method("summary"):
		return d
	return null


## CombatMorale 挂件写在船节点上的士气快照（没有返回 {}）
static func morale_meta(node: Object) -> Dictionary:
	if node == null or not is_instance_valid(node) or not node.has_meta(MORALE_META):
		return {}
	var m = node.get_meta(MORALE_META)
	return m if m is Dictionary else {}


## 合并四层来源后的快照
static func snapshot_of(world: Node, ship: Node2D = null) -> Dictionary:
	if ship == null:
		ship = ship_of(world)
	var snap := base_snapshot(world, ship)
	_merge(snap, module_snapshot(world, ship, snap.get("target", null) as Node2D))
	if snap.has("target") and snap.get("wind_dir") is Vector2:
		# 风向换成模块的读数后，风位按新风向重算
		var t: Node2D = snap["target"]
		if is_instance_valid(t) and ship != null:
			snap["upwind"] = weather_gauge(snap["wind_dir"], t.global_position - ship.global_position)
	_merge(snap, _duck(world, "combat_status"))
	_merge(snap, _duck(ship, "combat_status"))
	for key in _sources.keys():
		var cb: Callable = _sources[key]
		if cb.is_valid():
			var r = cb.call(world, ship)
			if r is Dictionary:
				_merge(snap, r)
	return snap


static func _duck(o: Object, method: String) -> Dictionary:
	if o == null or not is_instance_valid(o) or not o.has_method(method):
		return {}
	var r = o.call(method)
	return r if r is Dictionary else {}


static func _merge(into: Dictionary, part: Dictionary) -> void:
	for k in part.keys():
		into[k] = part[k]


## 快照取值带型别防护：来源写错型（比如把向量写成数）时回落，不在 HUD 里抛错
static func snap_f(snap: Dictionary, key: String, fallback: float) -> float:
	var v = snap.get(key, fallback)
	return float(v) if (v is float or v is int) else fallback


static func snap_v2(snap: Dictionary, key: String, fallback: Vector2) -> Vector2:
	var v = snap.get(key, fallback)
	return v if v is Vector2 else fallback


static func snap_b(snap: Dictionary, key: String) -> bool:
	return snap.get(key, false) == true


# ── 纯函数：几何与文案 ──────────────────────────────────

## 舷角：船首向 heading 到目标方向 to 的夹角（度，-180–180），正 = 右舷（屏幕 y 向下，angle_to 顺时针为正）
static func relative_bearing(heading: Vector2, to: Vector2) -> float:
	if heading.length() < 0.001 or to.length() < 0.001:
		return 0.0
	return rad_to_deg(heading.angle_to(to))


## 来风方位（八方）。wind_dir 是下风向，来风 = -wind_dir；屏幕上方为北
static func wind_from_name(wind_dir: Vector2) -> String:
	if wind_dir.length() < 0.001:
		return ""
	var from := -wind_dir
	var deg := fposmod(rad_to_deg(atan2(from.x, -from.y)), 360.0)
	return COMPASS8[int(roundf(deg / 45.0)) % 8]


## 风级：WorldMap 平时 80 = 四级，160 = 八级，封顶十二
static func wind_level(force: float) -> int:
	return clampi(roundi(force / 20.0), 0, 12)


## 受风：{"angle"（θ，船首与来风夹角，度）, "side"（左 / 右，风从哪舷来）, "name"（顶风 / 抢风 / 侧风 / 顺风）}
static func point_of_sail(heading: Vector2, wind_dir: Vector2, pinch := PINCH_DEFAULT) -> Dictionary:
	if heading.length() < 0.001 or wind_dir.length() < 0.001:
		return {"angle": -1.0, "side": "", "name": ""}
	var rel := rad_to_deg(heading.angle_to(-wind_dir))
	var ang := absf(rel)
	var nm := "顺风"
	if ang < pinch:
		nm = "顶风"
	elif ang < BEAM_FROM:
		nm = "抢风"
	elif ang < RUN_FROM:
		nm = "侧风"
	var side := ""
	if ang > 4.0 and ang < 176.0:
		side = "右" if rel > 0.0 else "左"
	return {"angle": ang, "side": side, "name": nm}


## 舷角写法：艏 / 艉 / 左舷 / 右舷 + 度数
static func bearing_text(deg: float) -> String:
	var a := absf(deg)
	var d := int(roundf(a))
	if a < 20.0:
		return "艏 %d°" % d
	if a > 160.0:
		return "艉 %d°" % d
	return "%s舷 %d°" % ["右" if deg > 0.0 else "左", d]


static func in_broadside_arc(deg: float) -> bool:
	var a := absf(deg)
	return a >= ARC_MIN and a <= ARC_MAX


## 风位：敌在我下风向一侧 → 我居上风（1）；在上风向一侧 → 敌居上风（-1）；否则相平（0）
static func weather_gauge(wind_dir: Vector2, to_enemy: Vector2) -> int:
	if wind_dir.length() < 0.001 or to_enemy.length() < 0.001:
		return 0
	var c := to_enemy.normalized().dot(wind_dir.normalized())
	if c > GAUGE_COS:
		return 1
	if c < -GAUGE_COS:
		return -1
	return 0


static func cn_num(n: int) -> String:
	if n < 0:
		return str(n)
	if n < 10:
		return CN_DIGITS[n]
	if n < 20:
		return "十" + (CN_DIGITS[n - 10] if n > 10 else "")
	if n < 100:
		return CN_DIGITS[int(n / 10)] + "十" + (CN_DIGITS[n % 10] if n % 10 else "")
	return str(n)


## 完好程度：≥0.95 完好，≤0.05 毁，其间按成（八成）
static func tenths_text(f: float) -> String:
	if f >= 0.95:
		return "完好"
	if f <= 0.05:
		return "毁"
	return "%s成" % cn_num(clampi(roundi(f * 10.0), 1, 9))


static func morale_word(m: float) -> String:
	if m >= 75.0:
		return "高昂"
	if m >= 50.0:
		return "尚稳"
	if m >= 30.0:
		return "动摇"
	return "将溃"


static func sail_word(gear: int) -> String:
	match gear:
		0:
			return "收帆"
		1:
			return "半帆"
		2:
			return "满帆"
	return ""


## 装填秒数：十秒内带一位小数，十秒以上写整数（一行放得下）；该舷无位（INF）写「无」
static func _secs(s: float) -> String:
	if s > 9999.0:
		return "无"
	var v := maxf(0.0, s)
	return ("%.1f秒" % v) if v < 10.0 else ("%d秒" % ceili(v))


## 格子文案（纯函数）：key → {"title", "text", "tone"}；tone ∈ norm / dim / ok / warn / bad
static func format_cells(snap: Dictionary) -> Dictionary:
	var out := {}
	for c in CELLS:
		out[c[0]] = {"title": c[1], "text": "未计", "tone": "dim"}

	var wind_dir := snap_v2(snap, "wind_dir", Vector2.ZERO)
	var force := snap_f(snap, "wind_force", -1.0)
	if force >= 0.0:
		var lv := wind_level(force)
		var nm := String(snap.get("wind_name", ""))
		if nm == "":
			var n8 := wind_from_name(wind_dir)
			nm = (n8 + "风") if n8 != "" else ""
		if lv == 0 or nm == "":
			out["wind"] = {"title": "风", "text": "无风", "tone": "warn"}
		else:
			out["wind"] = {"title": "风", "text": "%s %s级" % [nm, cn_num(lv)], "tone": "bad" if lv >= 8 else "norm"}

	if snap_b(snap, "has_ship") and force > 0.0:
		var pos := point_of_sail(snap_v2(snap, "heading", Vector2.UP), wind_dir, snap_f(snap, "pinch", PINCH_DEFAULT))
		var nm2 := String(snap.get("sail_state", pos["name"]))
		if nm2 != "":
			var side := String(pos["side"])
			var tone := "norm"
			if nm2 == "顶风" and int(snap_f(snap, "sail_gear", 1.0)) != 0:
				tone = "warn"
			out["trim"] = {"title": "受风", "text": ("%s舷 %s" % [side, nm2]) if side != "" else nm2, "tone": tone}

	if snap_b(snap, "boarding"):
		out["bearing"] = {"title": "敌舷角", "text": "已钩住", "tone": "warn"}
	elif snap_b(snap, "has_target"):
		var deg := snap_f(snap, "target_bearing", 0.0)
		var txt2 := bearing_text(deg)
		var can_board := snap_b(snap, "can_board") if snap.has("can_board") \
			else snap_f(snap, "target_dist", INF) <= snap_f(snap, "board_distance", BOARD_DISTANCE_FALLBACK)
		if can_board:
			txt2 += "·可接"
		var arc := snap_b(snap, "in_arc") if snap.has("in_arc") else in_broadside_arc(deg)
		out["bearing"] = {"title": "敌舷角", "text": txt2, "tone": "ok" if arc else "norm"}
		match int(snap_f(snap, "upwind", 0.0)):
			1:
				out["gauge"] = {"title": "风位", "text": "我居上风", "tone": "ok"}
			-1:
				out["gauge"] = {"title": "风位", "text": "敌居上风", "tone": "warn"}
			_:
				out["gauge"] = {"title": "风位", "text": "相平", "tone": "norm"}
	elif snap_b(snap, "has_ship"):
		out["bearing"] = {"title": "敌舷角", "text": "无敌踪", "tone": "dim"}
		out["gauge"] = {"title": "风位", "text": "无敌踪", "tone": "dim"}

	var ammo = snap.get("ammo", {})
	if ammo is Dictionary and not (ammo as Dictionary).is_empty():
		var ac := _ammo_cell(ammo, snap.get("ammo_max", {}))
		if String(ac["text"]) != "":
			out["ammo"] = ac

	var reload = snap.get("reload", null)
	if reload is Dictionary and (reload.has("port") or reload.has("starboard")):
		var lp := snap_f(reload, "port", 0.0)
		var rp := snap_f(reload, "starboard", 0.0)
		var txt3 := ""
		if lp <= 0.0 and rp <= 0.0:
			txt3 = "两舷已装"
		elif is_equal_approx(lp, rp):
			txt3 = "两舷 " + _secs(lp)
		else:
			txt3 = "左%s 右%s" % ["已装" if lp <= 0.0 else _secs(lp), "已装" if rp <= 0.0 else _secs(rp)]
		out["reload"] = {"title": "装填", "text": txt3, "tone": "ok" if lp <= 0.0 or rp <= 0.0 else "norm"}
	elif snap.has("reload_left"):
		var left := snap_f(snap, "reload_left", 0.0)
		out["reload"] = {"title": "装填", "text": "两舷已装" if left <= 0.0 else "两舷 " + _secs(left),
			"tone": "ok" if left <= 0.0 else "norm"}

	var gear := int(snap_f(snap, "sail_gear", -1.0))
	var sail := snap_f(snap, "sail", -1.0)
	if gear >= 0 or sail >= 0.0:
		var bits := PackedStringArray()
		if gear >= 0:
			bits.append(sail_word(gear))
		if snap_b(snap, "mast_down"):
			bits.append("桅折")
		elif sail >= 0.0:
			bits.append("帆毁" if sail <= 0.05 else tenths_text(sail))
		out["sail"] = {"title": "帆", "text": " ".join(bits), "tone": "bad" if snap_b(snap, "mast_down") else _hp_tone(sail)}

	var rudder := snap_f(snap, "rudder", -1.0)
	if rudder >= 0.0:
		out["rudder"] = {"title": "舵", "text": "舵毁" if rudder <= 0.05 else tenths_text(rudder), "tone": _hp_tone(rudder)}

	var flood := snap_f(snap, "flood", -1.0)
	var fire := snap_f(snap, "fire", -1.0)
	if flood >= 0.0 or fire >= 0.0:
		var bits2 := PackedStringArray()
		var tone2 := "norm"
		if flood >= 0.0:
			if flood < 0.02:
				bits2.append("无")
			else:
				bits2.append("%s成" % cn_num(clampi(roundi(flood * 10.0), 1, 10)))
				tone2 = "bad" if flood >= 0.5 else "warn"
		if fire > 0.0:
			if fire < 0.1:
				bits2.append("火起")
			elif fire >= 1.0:
				bits2.append("大火")
			else:
				bits2.append("火%s成" % cn_num(clampi(roundi(fire * 10.0), 1, 9)))
			tone2 = "bad"
		elif fire == 0.0 and flood < 0.0:
			bits2.append("无火")
		out["flood"] = {"title": "浸水", "text": " ".join(bits2), "tone": tone2}

	var morale := snap_f(snap, "morale", -1.0)
	if morale >= 0.0:
		var tone3 := "ok" if morale >= 75.0 else ("norm" if morale >= 50.0 else ("warn" if morale >= 30.0 else "bad"))
		var word := String(snap.get("morale_label", ""))
		out["morale"] = {"title": "士气", "text": "%d %s" % [roundi(morale), word if word != "" else morale_word(morale)], "tone": tone3}
	return out


static func _hp_tone(f: float) -> String:
	if f < 0.0:
		return "norm"
	if f < 0.3:
		return "bad"
	if f < 0.6:
		return "warn"
	return "norm"


## 弹药格：按 AMMO_ORDER 排，定额为 0 的弹种（本船不带）不写；用尽写「尽」，低于告急线写朱
static func _ammo_cell(ammo: Dictionary, ammo_max) -> Dictionary:
	var keys: Array = []
	for k in AMMO_ORDER:
		if ammo.has(k):
			keys.append(k)
	for k in ammo.keys():
		if not keys.has(k):
			keys.append(k)
	var bits := PackedStringArray()
	var tone := "norm"
	for k in keys:
		var raw = ammo[k]
		if raw is Dictionary:
			raw = (raw as Dictionary).get("count", (raw as Dictionary).get("n", 0))
		var n := int(raw) if (raw is int or raw is float) else 0
		var cap := snap_f(ammo_max, String(k), -1.0) if ammo_max is Dictionary else -1.0
		if cap == 0.0 and n <= 0:
			continue
		var nm := String(AMMO_NAMES.get(String(k), String(k)))
		if n <= 0:
			bits.append(nm + "尽")
			tone = "bad"
			continue
		bits.append("%s%d" % [nm, n])
		if cap > 0.0 and float(n) / cap < AMMO_LOW:
			tone = "bad"
	return {"title": "弹药", "text": " ".join(bits), "tone": tone}


# ── 节点 ──────────────────────────────────────────────

func _world() -> Node:
	if world_ref == null:
		return null
	var w = world_ref.get_ref()
	return w if w is Node else null


func _ship() -> Node2D:
	if ship_ref != null:
		var s = ship_ref.get_ref()
		if s is Node2D:
			return s
	return ship_of(_world())


## 当前快照：有 source 用 source，否则按 snapshot_of 四层取
func snapshot() -> Dictionary:
	if source.is_valid():
		var r = source.call()
		return r if r is Dictionary else {}
	return snapshot_of(_world(), _ship())


func refresh() -> void:
	if not _built:
		return
	var cells := format_cells(snapshot())
	for key in cells.keys():
		if not _cells.has(key):
			continue
		var c: Dictionary = cells[key]
		var sig := "%s|%s|%s" % [c["title"], c["text"], c["tone"]]
		if _last.get(key, "") == sig:
			continue
		_last[key] = sig
		var ui: Dictionary = _cells[key]
		(ui["title"] as Label).text = String(c["title"])
		var v := ui["value"] as Label
		v.text = String(c["text"])
		v.add_theme_color_override("font_color", tone_color(String(c["tone"])))


static func tone_color(tone: String) -> Color:
	match tone:
		"dim":
			return UiTheme.PAPER_DIM
		"ok":
			return UiTheme.PAPER_MOSS
		"warn":
			return UiTheme.PAPER_HONEY
		"bad":
			return UiTheme.PAPER_CINNABAR
	return UiTheme.PAPER_TEXT


func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_strip = PanelContainer.new()
	_strip.name = "StatusStrip"
	UiTheme.paper_card(_strip)
	# 宣纸是海面上最亮的一块，压一档到旧绢调（同港页岸门）；self_modulate 只染纸不染字
	_strip.self_modulate = UiTheme.DOOR_PAPER_TINT
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_strip)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_strip.add_child(margin)

	_row = HBoxContainer.new()
	_row.name = "Cells"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 6)
	margin.add_child(_row)

	for i in range(CELLS.size()):
		var key: String = CELLS[i][0]
		if i > 0:
			var rule := ColorRect.new()
			rule.color = Color(UiTheme.PAPER_GOLD, 0.45)
			rule.custom_minimum_size = Vector2(1, 34)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_row.add_child(rule)
		var box := VBoxContainer.new()
		box.name = "Cell_" + key
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 0)
		var t := Label.new()
		t.text = CELLS[i][1]
		t.add_theme_font_override("font", UiTheme.title_font())
		t.add_theme_font_size_override("font_size", 16)
		t.add_theme_color_override("font_color", UiTheme.PAPER_GOLD)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(t)
		var v := Label.new()
		v.text = "未计"
		v.add_theme_font_override("font", UiTheme.font())
		v.add_theme_font_size_override("font_size", 16)
		v.add_theme_color_override("font_color", UiTheme.PAPER_DIM)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(v)
		_row.add_child(box)
		_cells[key] = {"box": box, "title": t, "value": v}


## 左下，右缘让出小地图；锚在画布底边、向上长，一行排开（样例与各格最长写法在 1280 宽下量过放得下）
func _layout() -> void:
	if _strip == null or not is_inside_tree():
		return
	var cv := Kit.canvas_size(self)
	var right := cv.x - MARGIN - MINIMAP_FALLBACK_W - GAP
	var mini := _minimap()
	if mini != null:
		if not mini.item_rect_changed.is_connected(_layout):
			mini.item_rect_changed.connect(_layout)
		var r := mini.get_global_rect()
		if r.size.x > 0.0:
			right = r.position.x - GAP
	var w := maxf(320.0, right - MARGIN)
	_strip.custom_minimum_size = Vector2(w, 0)
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_strip.grow_horizontal = Control.GROW_DIRECTION_END
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_strip.offset_left = MARGIN
	_strip.offset_right = MARGIN + w
	_strip.offset_bottom = -MARGIN
	_strip.offset_top = -MARGIN - _strip.get_combined_minimum_size().y


## WorldMap 小地图面板（只读，量它的左缘；没有返回 null）
func _minimap() -> Control:
	var w := _world()
	if w == null:
		return null
	var mini := w.get_node_or_null("CanvasLayer/HUD/MinimapPanel") as Control
	if mini == null or not mini.is_visible_in_tree():
		return null
	return mini
