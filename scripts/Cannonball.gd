extends Area2D
## 舷战一发（lane combat03）：弓弩一排矢、床子弩一枝大箭、砲一颗石或一包火砲——不是近代铁弹。
## 两种起法：
##   新：Ballistics.fire_volley 生出后 configure(shot)：出膛点、落点、飞时、杀伤都已按射距 / 舷角 / 散布算好；
##   旧：Ship / PirateShip 只写 position / direction / shooter（speed / damage / lifetime 用默认值），
##       _ready 里按床子弩补成一发（Ballistics.legacy_shot）：照样飞得有时、飞到最远处落水、远了杀伤衰减。
## 命中按船体椭圆判（Ballistics.hull_footprint，按船图量），不再只认船心 24 px 的碰撞圆：
##   平射逐帧扫这一帧走过的线段，先碰到哪条船算哪条（远射前段在半空越顶，见 Ballistics.direct_low_from），落近船舷一点也算；
##   抛射越顶而过，只在落点判（溅及半径 splash）。
## 杀伤交给目标：目标有 take_ballistic_hit(hit) / take_hit(Dictionary) 的（DamageModel 接线后）整份交过去，hit 见 _strike，
##   带 combat04 DamageModel.apply_hit 认的 kind / amount / local；否则船体伤 ≥ 1 才 take_damage（一排矢钉不穿船板，
##   也就不去颠舱面货），玩家船照旧乘甲。命中观感走 CombatFx.on_missile_hit(弹种)，落水出 WaterSplash（一排矢只溅小花）。

@export var speed: float = 640.0
@export var damage: float = 25.0
@export var lifetime: float = 2.0
var direction: Vector2 = Vector2.ZERO
var shooter: Node2D = null
## 这一发（Ballistics.plan_shot / legacy_shot 的字典）。add_child 前 configure 进来；空则 _ready 按旧口径补
var shot: Dictionary = {}

var water_splash = preload("res://scenes/WaterSplash.tscn")
var impact_explosion = preload("res://scenes/ImpactExplosion.tscn")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
const _Ballistics := preload("res://scripts/combat/Ballistics.gd")
var floating_text = preload("res://scenes/FloatingText.tscn")

## 平射弹体半径：扫线段时船体椭圆外扩这么多
const DIRECT_MARGIN := 3.0
## 一排矢落水只溅小花
const LIGHT_SPLASH_AMOUNT := 12
## 焰尾留几帧
const TRAIL_LEN := 6
## 抛射的样子：石弹、压舱石、抛石画成不规则石块（半径 px、棱角参差、石色）；
## 场景里那张 shot_iron.png 铁子只给火砲——铁壳火药弹，带引信焰尾。平射一律画矢，不用贴图。
const STONE_LOOK := {
	"pao": {"r": 6.5, "jag": 0.14, "color": Color(0.62, 0.58, 0.52)},
	"pao_ballast": {"r": 5.0, "jag": 0.28, "color": Color(0.50, 0.47, 0.43)},
	"paoshi": {"r": 3.0, "jag": 0.22, "color": Color(0.66, 0.62, 0.56)},
}
const BOMB_SCALE := 0.34
const STONE_EDGES := 9
const SHAFT := Color(0.24, 0.16, 0.09)
const HEAD := Color(0.20, 0.20, 0.22)
const FLETCH := Color(0.86, 0.82, 0.72)
const EMBER := Color(1.0, 0.56, 0.16)

var _age := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _prev := Vector2.ZERO
var _flight := 0.0
var _low_from := 0.0
var _lob := false
var _fiery := false
var _done := false
var _shooter_id := 0
var _height := 0.0
var _hk := 0.0
var _stone_r := 6.5
var _stone_color := Color(0.62, 0.58, 0.52)
var _stone_poly := PackedVector2Array()
var _bomb := false
var _trail: Array = []


## 新起法：Ballistics.fire_volley 在 add_child 之前调。
func configure(s: Dictionary) -> void:
	shot = s.duplicate()


func _ready() -> void:
	# 命中改按船体椭圆自判（见头注），物理重叠不用
	monitoring = false
	monitorable = false
	if shooter != null and is_instance_valid(shooter):
		_shooter_id = shooter.get_instance_id()
	if shot.is_empty():
		shot = _Ballistics.legacy_shot(global_position, direction, speed, damage, lifetime)
	_from = shot.get("origin", global_position)
	_to = shot.get("landing", _from)
	_flight = maxf(0.0, float(shot.get("flight_time", 0.0)))
	_low_from = maxf(0.0, float(shot.get("low_from", 0.0)))
	_lob = str(shot.get("path", "")) == _Ballistics.PATH_LOB
	var wid := weapon_id()
	_fiery = float(shot.get("fire", 0.0)) > 0.0
	if _to.distance_squared_to(_from) > 0.0001:
		direction = (_to - _from).normalized()
	global_position = _from
	_prev = _from
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	_bomb = _lob and wid == "huopao"
	if spr != null:
		spr.visible = _bomb
		spr.modulate = Color.WHITE
		spr.scale = Vector2.ONE * BOMB_SCALE
	if _lob:
		rotation = 0.0
		if not _bomb:
			_make_stone(STONE_LOOK.get(wid, STONE_LOOK["pao"]))
	else:
		rotation = direction.angle()
	queue_redraw()


## 石块轮廓：按实例号定参差，同一颗石头飞一路形状不变
func _make_stone(look: Dictionary) -> void:
	_stone_r = float(look["r"])
	_stone_color = look["color"]
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id()
	var jag := float(look["jag"])
	var spin := rng.randf() * TAU
	_stone_poly = PackedVector2Array()
	for i in range(STONE_EDGES):
		var ang := spin + TAU * float(i) / float(STONE_EDGES)
		_stone_poly.append(Vector2.from_angle(ang) * (1.0 + rng.randf_range(-jag, jag)))


## 这一发的武器 id（Ballistics.WEAPONS 的键）。
func weapon_id() -> String:
	return str(shot.get("weapon", _Ballistics.LEGACY_WEAPON))


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	var k := 1.0 if _flight <= 0.0 else clampf(_age / _flight, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	if not _lob:
		# 飞过 low_from 之前在半空，越过中间的船；之后逐帧扫线段
		var s1 := _from.distance_to(p)
		if s1 >= _low_from:
			var s0 := _from.distance_to(_prev)
			var a := _prev if s0 >= _low_from else _from + direction * _low_from
			var hit := _sweep(a, p)
			if not hit.is_empty():
				_strike(hit["body"], hit["at"])
				return
	global_position = p
	_prev = p
	if _lob:
		_hk = 4.0 * k * (1.0 - k)
		_height = float(shot.get("apex", 0.0)) * _hk
		var spr := get_node_or_null("Sprite2D") as Sprite2D
		if spr != null and _bomb:
			spr.position = Vector2(0.0, -_height)
			spr.scale = Vector2.ONE * BOMB_SCALE * (1.0 + 0.35 * _hk)
	if _fiery:
		_trail.push_front(p + Vector2(0.0, -_height))
		if _trail.size() > TRAIL_LEN:
			_trail.pop_back()
	if _lob or _fiery:
		queue_redraw()
	if k >= 1.0:
		# 抛射在落点判（外扩溅及半径）；平射一路没碰到船，落近 FREEBOARD 以内照样钉在船舷上
		var b := _body_at(_to, float(shot.get("splash", 0.0)) if _lob else _Ballistics.FREEBOARD)
		if b != null:
			_strike(b, _to)
			return
		_splash_and_die()


## 场上还能挨打的船（同一父节点下、有 take_damage / take_ballistic_hit / take_hit、船体未归零、不是放这一发的船）。
func _targets() -> Array:
	var out: Array = []
	var world := get_parent()
	if world == null:
		return out
	for c in world.get_children():
		var n2 := c as Node2D
		if n2 == null or n2 == self or n2.is_queued_for_deletion() or n2.get_instance_id() == _shooter_id:
			continue
		if not (n2.has_method("take_damage") or n2.has_method("take_ballistic_hit") or n2.has_method("take_hit")):
			continue
		var hp = n2.get("hull_hp")
		if hp != null and float(hp) <= 0.0:
			continue
		out.append(n2)
	return out


## 平射：这一帧走过的线段先碰到哪条船。
func _sweep(a: Vector2, b: Vector2) -> Dictionary:
	var best_t := 2.0
	var best: Node2D = null
	for c in _targets():
		var t := _Ballistics.segment_hits_hull(c, a, b, DIRECT_MARGIN)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = c
	if best == null:
		return {}
	return {"body": best, "at": a.lerp(b, best_t)}


## 抛射：落点（外扩溅及半径）落在哪条船上；叠着的取船心最近的。
func _body_at(p: Vector2, splash: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for c in _targets():
		if _Ballistics.point_in_hull(c, p, splash):
			var d: float = (c as Node2D).global_position.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = c
	return best


func _shooter_or_null() -> Node2D:
	return shooter if shooter != null and is_instance_valid(shooter) else null


func _local(at: Vector2) -> Vector2:
	var world := get_parent() as Node2D
	return world.to_local(at) if world != null else at


## 中了：按落距衰减、按品质（代用弹）打折，玩家船乘甲；交给目标，再出声、出焰、飘字。
## hit = {weapon, name, hull, crew（期望伤亡人数）, sail, fire（引火几率）, at, from（全局坐标）, range, heavy, armored, shooter,
##        kind / amount / local（combat04 DamageModel.apply_hit 的口径：弹种、命中点数（已乘甲）、目标船体坐标里的命中处）}
## 交法：目标有 take_ballistic_hit(hit) 用它；否则有收一个 Dictionary 的 take_hit(hit) 用它；再不然船体伤 ≥ 1 才 take_damage(船体伤)。
func _strike(body: Node2D, at: Vector2) -> void:
	_done = true
	global_position = at
	var wid := weapon_id()
	var dist := _from.distance_to(at)
	var fall := _Ballistics.falloff(wid, dist)
	var q := float(shot.get("quality", 1.0))
	# 张湿毡的代价（w53-15 own_missile_mul）：我方旗舰张着湿毡时，舷边施展不开，打出去的平射矢石照八折。
	# 只对我方（shooter 是玩家 Ship、且是本发平射）生效；敌船无此号令、抛射不摊（代价只写在平射矢石上）。
	var _sh := _shooter_or_null()
	if not _lob and _sh is Ship and is_instance_valid(_sh):
		var _dm = (_sh as Ship).get_damage_model()
		if _dm != null and _dm.has_method("own_missile_mul"):
			q *= float(_dm.call("own_missile_mul"))
	var hull := float(shot.get("hull", 0.0)) * fall * q
	var amount := float(shot.get("amount", shot.get("hull", 0.0))) * fall * q
	var armored := false
	# P4-3：玩家船（Ship）受击乘甲减伤；敌船（PirateShip）保持原伤害
	if body is Ship:
		var armor := Fleet.armor_damage_reduction()
		hull *= armor
		amount *= armor
		armored = true
	var heavy := bool(shot.get("heavy", true))
	var hit := {
		"weapon": wid, "name": str(shot.get("name", _Ballistics.weapon_name(wid))),
		"hull": hull, "crew": float(shot.get("crew", 0.0)) * fall * q,
		"sail": float(shot.get("sail", 0.0)) * fall * q, "fire": float(shot.get("fire", 0.0)) * q,
		"at": at, "from": _from, "range": dist, "heavy": heavy, "armored": armored,
		"shooter": _shooter_or_null(),
		"kind": str(shot.get("kind", "bolt")), "amount": amount,
		"local": (at - body.global_position).rotated(-body.global_rotation),
	}
	var how := _hit_method(body)
	if how != "":
		# 船体、伤亡、飘字归目标自己的损伤模型算
		body.call(how, hit)
	elif hull >= 1.0:
		body.take_damage(hull)
		_spawn_floating_text("-" + str(int(hull)), Color.RED)
	var world := get_parent()
	_AUDIO.combat_hit(world)
	# 命中观感按弹种（combat09 CombatFx.on_missile_hit）；挨打的是本船（玩家旗舰）才震镜头。砲石另加 ImpactExplosion（木屑尘烟一闪）
	var fx_kind := str(shot.get("fx", "bolt" if heavy else ""))
	if fx_kind != "":
		_CombatFx.on_missile_hit(world, _local(at), fx_kind, body is Ship)
		# 挨打的船自己一闪、顺来力一颤、留焦痕（敌我同一支；按命中点数定轻重）
		_CombatFx.hull_impact(body, at, _from, fx_kind, amount)
		if fx_kind == "stone":
			_spawn_fx(impact_explosion, at)
	queue_free()


## 目标收整份 hit 的方法名：take_ballistic_hit（本 lane 约定），或形参恰为一个 Dictionary 的 take_hit；都没有返回 ""。
static func _hit_method(body: Object) -> String:
	if body.has_method("take_ballistic_hit"):
		return "take_ballistic_hit"
	if not body.has_method("take_hit"):
		return ""
	var scr = body.get_script()
	if scr is Script:
		for m in (scr as Script).get_script_method_list():
			if str(m.get("name", "")) == "take_hit":
				var args: Array = m.get("args", [])
				if args.size() == 1 and int(args[0].get("type", TYPE_NIL)) == TYPE_DICTIONARY:
					return "take_hit"
	return ""


func _splash_and_die() -> void:
	_done = true
	_spawn_fx(water_splash, global_position, -1 if bool(shot.get("heavy", true)) else LIGHT_SPLASH_AMOUNT)
	queue_free()


func _spawn_fx(scene: PackedScene, at: Vector2, amount := -1) -> void:
	var world := get_parent()
	if world == null:
		return
	var fx = scene.instantiate()
	fx.position = _local(at)
	if amount > 0 and fx is CPUParticles2D:
		fx.amount = amount
	world.call_deferred("add_child", fx)
	fx.emitting = true


func _spawn_floating_text(text: String, color: Color) -> void:
	var ft = floating_text.instantiate()
	ft.position = _local(global_position)
	ft.text = text
	ft.add_theme_color_override("font_color", color)
	get_parent().call_deferred("add_child", ft)


# ── 画 ────────────────────────────────────────────────

func _draw() -> void:
	if _fiery:
		for i in range(_trail.size()):
			var a := 0.55 * (1.0 - float(i) / float(TRAIL_LEN))
			draw_circle(to_local(_trail[i]), 2.6 - 0.3 * float(i), Color(EMBER.r, EMBER.g, EMBER.b, a))
	if _lob:
		# 落影：飞得越高越小越淡；石块画在影子上方（拱高），越高显得越大
		var base_r := 8.0 if _bomb else _stone_r
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, base_r * 1.1 * (1.0 - 0.35 * _hk), Color(0.0, 0.0, 0.0, 0.30 * (1.0 - 0.5 * _hk)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not _bomb and _stone_poly.size() >= 3:
			var r := _stone_r * (1.0 + 0.35 * _hk)
			var lift := Vector2(0.0, -_height)
			var pts := PackedVector2Array()
			for v in _stone_poly:
				pts.append(lift + v * r)
			draw_colored_polygon(pts, _stone_color)
			var rim := pts.duplicate()
			rim.append(pts[0])
			draw_polyline(rim, _stone_color.darkened(0.45), 1.0)
			draw_circle(lift + Vector2(-0.3, -0.35) * r, r * 0.3, _stone_color.lightened(0.3))
		return
	match weapon_id():
		"gongnu", "huojian":
			for o in [Vector2(0, -5), Vector2(-5, -1), Vector2(3, 3), Vector2(-2, 6)]:
				_draw_arrow(o, 11.0, 1.2)
		"hanya":
			for o in [Vector2(0, -7), Vector2(-6, -3), Vector2(4, -2), Vector2(-3, 2), Vector2(5, 4), Vector2(-7, 6), Vector2(1, 8)]:
				_draw_arrow(o, 9.0, 1.1)
		_:
			_draw_bolt()


func _draw_arrow(o: Vector2, length: float, width: float) -> void:
	var tip := o + Vector2(length * 0.5, 0.0)
	var tail := o - Vector2(length * 0.5, 0.0)
	draw_line(tail, tip, SHAFT, width)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-2.6, -1.6), tip + Vector2(1.4, 0.0), tip + Vector2(-2.6, 1.6)]), HEAD)
	draw_line(tail, tail + Vector2(-2.2, -1.6), FLETCH, 0.9)
	draw_line(tail, tail + Vector2(-2.2, 1.6), FLETCH, 0.9)
	if _fiery:
		draw_circle(tip + Vector2(-3.5, 0.0), 1.8, EMBER)


## 床子弩大箭：粗杆、铁镞、三翎
func _draw_bolt() -> void:
	draw_line(Vector2(-15.0, 0.0), Vector2(10.0, 0.0), SHAFT, 2.6)
	draw_colored_polygon(PackedVector2Array([Vector2(9.0, -3.2), Vector2(17.0, 0.0), Vector2(9.0, 3.2)]), HEAD)
	draw_line(Vector2(-15.0, 0.0), Vector2(-20.0, -3.4), FLETCH, 1.3)
	draw_line(Vector2(-15.0, 0.0), Vector2(-20.0, 3.4), FLETCH, 1.3)
	draw_line(Vector2(-12.0, 0.0), Vector2(-17.0, 0.0), FLETCH, 1.3)
