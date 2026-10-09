## 接舷阶段覆盖层：钩索线 + 旧绢阶段题签 + 甲板四段简图。
## 两种演法：
##   一、两拍（WorldMap._board_enemy / CombatShoreHook 现用，契约不变）：begin 起「接舷」→ resolve 收「夺船 / 脱钩」。
##       不改白刃公式；只在判定前后加观感节拍。
##   二、整场（lane combat05）：play(parent, from, to, result)，result 是 MeleeResolve.resolve() 的返回。
##       按 cues_from(result) 逐拍演 抛钩 → 接舷 → 矢石 → 跳帮 → 白刃第 N 合 → 了局（夺船 / 俘获 / 击退 / 脱钩 / 落空）：
##       钩索按咬住几具画（落空的垂进水里），甲板简图跟着前线推，桅下帅旗斩落即倒。
##       WorldMap 还没接这条（归 combat02，接法见 MeleeResolve 头注「接线」）。
##   自带演示：直接跑 scenes/combat/BoardingStage.tscn（demo_on_ready）：两船随机打一场，空格再来、1–3 换局面、Esc 退出。
## headless 下静态入口一律返回 null；cues_from / title_for 是纯函数，headless 照调。
##
## finished 契约（lane gd17）：演完或被新一层顶掉（_abort）都恰好发一次——WorldMap._await_boarding_fx 裸 await 它，
## 顶掉不发的话那头永不醒。随父释放（WorldMap 结算 / 退出）不补发：唯一的等待方就是父 WorldMap，一起释放，
## 挂在本层信号上的协程随本层释放而丢弃、不泄漏；补发反倒让 WorldMap 在拆树途中接着跑 _battle_exit。
## 本层自己不 await：节拍全在 tween 回调里，被 kill / 随父释放不留挂起的协程。
## begin 之后 BEGIN_GUARD 秒内既没等到 resolve 也没被顶掉（WorldMap 钩住的船在停拍里被别船打沉，_board_enemy
## 提前 return、不再调 resolve），本层自己淡出收场、照发一次 finished，不把「接舷」题签和钩索留在海面上。
extends CanvasLayer

signal finished
## 整场演法每拍亮出时发（key：grapple / lash / volley / leap / round / outcome）；两拍演法不发
signal cue_shown(key: String, title: String)

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const MeleeResolve := preload("res://scripts/combat/MeleeResolve.gd")

const LAYER_INDEX := 55
const GROUP := "nk1_boarding_stage"
const T_HOLD := 0.55
const T_FADE := 0.28
## 两拍演法 begin 后等 resolve 的上限（秒，游戏时间）：WorldMap 停 0.42 s、岸上预览停 0.55 s
const BEGIN_GUARD := 6.0
## 整场演法每拍停留（秒，再除以 speed）：一般拍 / 白刃每合 / 了局
const T_CUE := 0.62
const T_ROUND := 0.72
const T_OUTCOME := 1.05
## 拍里没有甲板简图（抛钩 / 接舷 / 矢石）
const NO_DECK := -9
## 两拍演法 begin 画几具钩索
const LEGACY_HOOKS := 3

## 直接跑 BoardingStage.tscn 时为 true（场景里已勾上）：起自带演示。脚本 new() 出来的（WorldMap / play）恒为 false
@export var demo_on_ready := false

var _root: Control
var _shade: ColorRect
var _slip: PanelContainer
var _title: Label
var _sub: Label
var _note: Label
var _deck: DeckStrip
var _ropes: Array[Line2D] = []
var _rope_from: WeakRef = null
var _rope_to: WeakRef = null
var _seq: Tween = null
var _guard: Tween = null
var _done := false


## 接舷开场：钩索 + 「接舷」题签。返回节点；headless 返回 null。
static func begin(parent: Node, from: Node2D, to: Node2D, subtitle := "") -> CanvasLayer:
	var st := _spawn(parent)
	if st == null:
		return null
	st.call("_play_begin", from, to, subtitle)
	return st


## 白刃结果题签（夺船 / 脱钩；也认 MeleeResolve 的了局键）。可在 begin / play 之后再调，或单独调。
static func resolve(parent: Node, outcome: String, detail := "") -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	var existing: CanvasLayer = null
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		# 同一帧里刚收场（已发 finished、等着释放）的那层不接着用
		if n.is_queued_for_deletion() or bool(n.get("_done")):
			continue
		existing = n as CanvasLayer
		break
	if existing != null:
		existing.call("_play_resolve", outcome, detail)
		return existing
	var st: CanvasLayer = (load("res://scripts/combat/BoardingStage.gd") as GDScript).new()
	st.add_to_group(GROUP)
	parent.add_child(st)
	st.call("_play_resolve", outcome, detail)
	return st


## 整场：按 MeleeResolve.resolve() 的结果逐拍演到了局，演完发 finished。speed 越大越快（0.25–4）。
## from / to 是两船节点（画钩索用，可空）。返回节点；headless 返回 null。
static func play(parent: Node, from: Node2D, to: Node2D, result: Dictionary, speed := 1.0) -> CanvasLayer:
	var st := _spawn(parent)
	if st == null:
		return null
	st.call("_play_sequence", from, to, cues_from(result), speed)
	return st


## 题签名：两拍的 win / board → 夺船、lose → 脱钩、overrun → 失守（敌船先钩、占了本船甲板，WorldMap 随即败局收战）；
## MeleeResolve 了局键照 MeleeResolve.TITLES；其余「白刃」。
static func title_for(outcome: String) -> String:
	match outcome:
		"win", "board":
			return "夺船"
		"lose":
			return "脱钩"
		"overrun":
			return "失守"
	return MeleeResolve.outcome_title(outcome)


## MeleeResolve 结果 → 逐拍题签（纯函数，headless 可调）。
## 每拍 {key, title, sub, note, hold, front（NO_DECK = 不画甲板）, flag（帅旗已落）, att_player, own（攻方船那格的字）,
## hooks, bit, outcome}。
static func cues_from(result: Dictionary) -> Array:
	var cues: Array = []
	var outcome := str(result.get("outcome", ""))
	if outcome == "":
		return cues
	var a := str(result.get("a_word", "我"))
	var d := str(result.get("d_word", "敌"))
	var att_player := bool(result.get("att_is_player", true))
	var base := {"note": "", "front": NO_DECK, "flag": false, "att_player": att_player, "own": "%s船" % a,
		"hooks": 0, "bit": 0, "outcome": ""}
	var g: Dictionary = result.get("grapple", {})
	var preset := bool(g.get("preset", false))
	if not preset:
		var note := "钩牢率 %d%%" % roundi(float(g.get("chance", 0.0)) * 100.0)
		for pair in [["boons", "利"], ["notes", "阻"]]:
			var why = g.get(pair[0], PackedStringArray())
			if why is PackedStringArray and not (why as PackedStringArray).is_empty():
				note += "　%s：%s" % [pair[1], "、".join(why)]
		cues.append(_cue(base, {"key": "grapple", "title": "抛钩", "sub": str(g.get("text", "钩索已抛")), "hold": T_CUE,
			"note": note, "hooks": int(g.get("hooks", 0)), "bit": int(g.get("bit", 0))}))
	if outcome != MeleeResolve.OUTCOME_HOOK_MISS:
		cues.append(_cue(base, {"key": "lash", "title": "接舷", "hold": T_CUE,
			"sub": str(g.get("text", "")) if preset else "两船并靠，钩缆绞紧"}))
		var v: Dictionary = result.get("volley", {})
		if not v.is_empty():
			cues.append(_cue(base, {"key": "volley", "title": "矢石", "sub": str(v.get("text", "")), "hold": T_CUE}))
		var lp: Dictionary = result.get("leap", {})
		if not lp.is_empty():
			cues.append(_cue(base, {"key": "leap", "title": "跳帮", "sub": str(lp.get("text", "")), "hold": T_CUE,
				"front": 0 if int(lp.get("boarders", 0)) > 0 else NO_DECK}))
			var flag := false
			# 三决断注（lane w53-p4-melee）：哪个合在第几段拍了哪一板，注在该合副题尾（择 / 超时；开战拍定的自动不注）
			var dec_by_n := {}
			for dc in result.get("decisions", []):
				if dc is Dictionary and str(dc.get("how", "")) != "" and int(dc.get("mode", -1)) >= 0:
					dec_by_n[int(dc.get("n", 0))] = dc
			for rd in result.get("rounds", []):
				if not (rd is Dictionary):
					continue
				flag = flag or int(rd.get("front", 0)) >= MeleeResolve.ZONE_FLAG
				var sub := str(rd.get("text", ""))
				var dc: Dictionary = dec_by_n.get(int(rd.get("n", 0)), {})
				if not dc.is_empty():
					sub += "（%s%s）" % [str(dc.get("via", "")), "・超时" if str(dc.get("how", "")) == "超时" else ""]
				cues.append(_cue(base, {"key": "round", "title": "白刃", "sub": sub, "hold": T_ROUND,
					"front": int(rd.get("front", 0)), "flag": flag,
					"note": "%s %d 人　士气 %d　｜　%s %d 人　士气 %d" % [a, int(rd.get("att", 0)), int(rd.get("att_morale", 0)),
						d, int(rd.get("def", 0)), int(rd.get("def_morale", 0))]}))
	# 了局：叙事一行、伤亡俘获另起一行（整句交给 autowrap 会从「我阵亡」中间折开）
	var head := str(result.get("summary_head", ""))
	var last := {"key": "outcome", "title": str(result.get("title", title_for(outcome))), "hold": T_OUTCOME,
		"sub": head if head != "" else str(result.get("summary", "")),
		"note": str(result.get("summary_tail", "")) if head != "" else "", "outcome": outcome}
	if outcome == MeleeResolve.OUTCOME_CAPTURE:
		last["front"] = MeleeResolve.ZONE_TAKEN
		last["flag"] = true
	elif not (result.get("rounds", []) as Array).is_empty():
		last["front"] = int(result.get("front", 0))
		last["flag"] = bool(result.get("flag_cut", false))
	cues.append(_cue(base, last))
	return cues


static func _cue(base: Dictionary, over: Dictionary) -> Dictionary:
	var c := base.duplicate()
	for k in over:
		c[k] = over[k]
	return c


## 新起一层：先顶掉 parent 树里正在演的（发 finished），再挂到 parent 下。headless / parent 不在树里返回 null。
static func _spawn(parent: Node) -> CanvasLayer:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return null
	for n in parent.get_tree().get_nodes_in_group(GROUP):
		n.call("_abort")
	var st: CanvasLayer = (load("res://scripts/combat/BoardingStage.gd") as GDScript).new()
	st.add_to_group(GROUP)
	parent.add_child(st)
	return st


func _ready() -> void:
	layer = LAYER_INDEX
	_build()
	set_process(false)
	set_process_unhandled_input(demo_on_ready)
	if demo_on_ready:
		_demo_setup.call_deferred()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(UiTheme.INK_SOLID.r, UiTheme.INK_SOLID.g, UiTheme.INK_SOLID.b, 0.18)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	_root.add_child(_shade)

	_slip = PanelContainer.new()
	_slip.add_theme_stylebox_override("panel", UiTheme.plaque())
	_slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slip.offset_top = 96.0
	_slip.offset_bottom = 96.0
	_slip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_slip)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_slip.add_child(vb)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiTheme.font())
	_title.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
	_title.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_title)

	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", UiTheme.font())
	_sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_sub.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_sub)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_override("font", UiTheme.font())
	_note.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_note.visible = false
	vb.add_child(_note)

	_deck = DeckStrip.new()
	_deck.visible = false
	vb.add_child(_deck)

	_slip.modulate.a = 0.0


func _play_begin(from: Node2D, to: Node2D, subtitle: String) -> void:
	_title.text = "接舷"
	_sub.text = subtitle if subtitle != "" else "钩索已抛"
	_draw_ropes(from, to, LEGACY_HOOKS, LEGACY_HOOKS)
	# 两拍演法的钩索照旧自己淡掉（resolve 可能不来，见头注 BEGIN_GUARD）
	var fade := create_tween()
	fade.tween_interval(T_HOLD)
	fade.tween_callback(_fade_ropes.bind(T_FADE))
	var tw := create_tween()
	tw.tween_property(_shade, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_slip, "modulate:a", 1.0, 0.22)
	_guard = create_tween()
	_guard.tween_interval(BEGIN_GUARD)
	_guard.tween_callback(_fade_out)
	CombatFx.hitstop(self, 0.06, 0.25)


func _play_resolve(outcome: String, detail: String) -> void:
	_kill(_guard)
	_kill(_seq)
	_title.text = title_for(outcome)
	_sub.text = detail
	_slip.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(T_HOLD)
	tw.tween_property(_slip, "modulate:a", 0.0, T_FADE)
	tw.parallel().tween_property(_shade, "modulate:a", 0.0, T_FADE)
	tw.tween_callback(_finish)


func _play_sequence(from: Node2D, to: Node2D, cues: Array, speed: float) -> void:
	if cues.is_empty():
		_finish()
		return
	var k := 1.0 / clampf(speed, 0.25, 4.0)
	_rope_from = weakref(from) if from != null else null
	_rope_to = weakref(to) if to != null else null
	# 整场的副题较长：定宽折行，题签不随每拍字数忽宽忽窄
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(520, 0)
	var tw := create_tween()
	_seq = tw
	tw.tween_callback(_show_cue.bind(cues[0]))
	tw.tween_property(_shade, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_slip, "modulate:a", 1.0, 0.22)
	tw.tween_interval(maxf(0.05, float(cues[0].get("hold", T_CUE)) * k - 0.22))
	for i in range(1, cues.size()):
		tw.tween_callback(_show_cue.bind(cues[i]))
		tw.tween_interval(float(cues[i].get("hold", T_CUE)) * k)
	tw.tween_property(_slip, "modulate:a", 0.0, T_FADE)
	tw.parallel().tween_property(_shade, "modulate:a", 0.0, T_FADE)
	tw.tween_callback(_finish)


func _show_cue(c: Dictionary) -> void:
	if _done:
		return
	var key := str(c.get("key", ""))
	_title.text = str(c.get("title", ""))
	_sub.text = str(c.get("sub", ""))
	_note.text = str(c.get("note", ""))
	_note.visible = _note.text != ""
	var f := int(c.get("front", NO_DECK))
	_deck.visible = f != NO_DECK
	if f != NO_DECK:
		_deck.set_state(f, bool(c.get("flag", false)), bool(c.get("att_player", true)), str(c.get("own", "我船")))
	match key:
		"grapple":
			_draw_ropes(_ref(_rope_from), _ref(_rope_to), int(c.get("hooks", 0)), int(c.get("bit", 0)))
		"lash":
			if _ropes.is_empty():
				_draw_ropes(_ref(_rope_from), _ref(_rope_to), LEGACY_HOOKS, LEGACY_HOOKS)
			_tighten_ropes()
		"leap":
			CombatFx.hitstop(self, 0.05, 0.3)
		"outcome":
			var o := str(c.get("outcome", ""))
			if o == MeleeResolve.OUTCOME_CAPTURE or o == MeleeResolve.OUTCOME_SURRENDER:
				CombatFx.hitstop(self, 0.08, 0.2)
			else:
				_fade_ropes(T_FADE)
	cue_shown.emit(key, _title.text)


# ── 钩索 ──

## hooks 具从 from 甩向 to：咬住的 bit 具（匀着分）画到对舷、微垂，其余短一截垂进水里。
func _draw_ropes(from: Node2D, to: Node2D, hooks: int, bit: int) -> void:
	_clear_ropes()
	if from == null or to == null or not is_instance_valid(from) or not is_instance_valid(to):
		return
	var host := get_parent()
	if host == null:
		return
	_rope_from = weakref(from)
	_rope_to = weakref(to)
	var n := clampi(hooks, 1, MeleeResolve.HOOKS_MAX)
	var held := clampi(bit, 0, n)
	for i in range(n):
		var ok := floori(float(i + 1) * held / n) > floori(float(i) * held / n)
		var line := Line2D.new()
		line.width = 2.0 if ok else 1.5
		line.default_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.88 if ok else 0.4)
		line.z_index = 30
		line.set_meta("reach", 1.0 if ok else 0.52 + 0.06 * float(i % 4))
		line.set_meta("spread", (float(i) - float(n - 1) * 0.5) * 9.0)
		line.set_meta("sag", 4.0)
		host.add_child(line)
		_ropes.append(line)
	_update_ropes()
	set_process(true)


## 接舷：咬住的钩缆绞紧（不垂、加粗）。
func _tighten_ropes() -> void:
	for r in _ropes:
		if is_instance_valid(r) and float(r.get_meta("reach", 0.0)) >= 0.99:
			r.set_meta("sag", 0.0)
			r.width = 2.6
	_update_ropes()


func _fade_ropes(t: float) -> void:
	for r in _ropes:
		if is_instance_valid(r):
			var tw := r.create_tween()
			tw.tween_property(r, "modulate:a", 0.0, t)


func _update_ropes() -> void:
	var a := _ref(_rope_from)
	var b := _ref(_rope_to)
	if a == null or b == null:
		return
	for r in _ropes:
		if is_instance_valid(r):
			r.points = rope_points(a.global_position, b.global_position,
				float(r.get_meta("reach", 1.0)), float(r.get_meta("spread", 0.0)), float(r.get_meta("sag", 4.0)))


## 一具钩索的折线：reach < 1 是落空的，停在半道、尾巴垂下去。
static func rope_points(a: Vector2, b: Vector2, reach: float, spread: float, sag := 4.0) -> PackedVector2Array:
	var dir := b - a
	var dist := dir.length()
	if dist < 1.0:
		return PackedVector2Array([a, b])
	var side := Vector2(-dir.y, dir.x) / dist * spread
	var start := a + side * 0.5
	var end := a + side + dir * clampf(reach, 0.1, 1.0)
	if reach >= 0.99:
		return PackedVector2Array([start, start.lerp(end, 0.5) + Vector2(0, sag), end])
	return PackedVector2Array([start, start.lerp(end, 0.6) + Vector2(0, 10), end + Vector2(0, 18)])


func _clear_ropes() -> void:
	for r in _ropes:
		if is_instance_valid(r):
			r.queue_free()
	_ropes.clear()
	set_process(false)


func _process(_delta: float) -> void:
	_update_ropes()


# ── 收场 ──

func _fade_out() -> void:
	if _done:
		return
	_kill(_seq)
	var tw := create_tween()
	tw.tween_property(_slip, "modulate:a", 0.0, T_FADE)
	tw.parallel().tween_property(_shade, "modulate:a", 0.0, T_FADE)
	tw.tween_callback(_finish)


func _finish() -> void:
	if _done:
		return
	_done = true
	_clear_ropes()
	finished.emit()
	queue_free()


func _abort() -> void:
	_finish()


static func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()


static func _ref(w: WeakRef) -> Node2D:
	if w == null:
		return null
	var n = w.get_ref()
	return n as Node2D if n != null and is_instance_valid(n) else null


# ── 自带演示（直接跑 BoardingStage.tscn）──

## 三个局面：us / foe = [船型, 水手, 士气, 将领系数, 船名]；we_attack = 我方抛钩（否则敌来接舷，攻守换位）；
## ctx 同 MeleeResolve.resolve（windward 按攻方算）
const DEMO_CASES := [
	{"label": "福船（中）钩快船　并舷、居上风", "we_attack": true,
		"us": ["fu_ship_medium", 80, 70, 1.15, "福船"], "foe": ["pirate_boat", 70, 62, 0.95, "快船"],
		"ctx": {"rel_speed": 40.0, "distance": 70.0, "windward": 1, "sea": 1}},
	{"label": "快船来劫小艍船　敌居上风、中浪", "we_attack": false,
		"us": ["sampan", 14, 65, 1.1, "小艍船"], "foe": ["pirate_boat", 60, 60, 1.0, "快船"],
		"ctx": {"rel_speed": 60.0, "distance": 80.0, "windward": 1, "sea": 2}},
	{"label": "海鹘接福船（大）　横风、微浪", "we_attack": true,
		"us": ["sea_falcon", 95, 75, 1.2, "海鹘"], "foe": ["fu_ship_large", 90, 55, 1.0, "福船（大）"],
		"ctx": {"rel_speed": 90.0, "distance": 90.0, "windward": 0, "sea": 1}},
]
const DEMO_SEA := Color(0.16, 0.25, 0.31)

var _demo_case := 0
var _demo_ships: Array[Node2D] = []
var _demo_info: Label = null
var _demo_last: Label = null


func _demo_setup() -> void:
	layer = 1
	var vp := get_viewport().get_visible_rect().size
	var sea := ColorRect.new()
	sea.color = DEMO_SEA
	sea.size = vp
	sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sea)
	move_child(sea, 0)
	for i in range(2):
		var ship := Node2D.new()
		var spr := Sprite2D.new()
		spr.scale = Vector2(0.62, 0.62)
		ship.add_child(spr)
		var tag := Label.new()
		tag.add_theme_font_override("font", UiTheme.font())
		tag.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		tag.add_theme_color_override("font_color", UiTheme.GOLD if i == 0 else UiTheme.CINNABAR)
		tag.position = Vector2(-60, 110)
		tag.size = Vector2(120, 30)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ship.add_child(tag)
		add_child(ship)
		_demo_ships.append(ship)
	_demo_ships[0].position = Vector2(vp.x * 0.38, vp.y * 0.66)
	_demo_ships[1].position = Vector2(vp.x * 0.62, vp.y * 0.58)
	_demo_info = _demo_label(Vector2(24, 18), UiTheme.TEXT)
	_demo_last = _demo_label(Vector2(24, vp.y - 64), UiTheme.TEXT_DIM)
	_demo_run()


func _demo_label(pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", UiTheme.font())
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l


func _demo_run() -> void:
	var cs: Dictionary = DEMO_CASES[_demo_case]
	var us := _demo_side(cs["us"], true)
	var foe := _demo_side(cs["foe"], false)
	var we_attack := bool(cs["we_attack"])
	# 0 号船恒为我方（左下），1 号为敌；钩索从攻方甩向守方
	for i in range(2):
		var spec: Array = cs["us"] if i == 0 else cs["foe"]
		var spr := _demo_ships[i].get_child(0) as Sprite2D
		CombatFx.apply_ship_sprite(spr, CombatFx.ship_sprite_path(str(spec[0]),
			CombatFx.SHIP_SPRITE_OWN if i == 0 else CombatFx.SHIP_SPRITE_ENEMY))
		spr.rotation = PI * 0.5 if i == 0 else PI * 0.45
		(_demo_ships[i].get_child(1) as Label).text = "%s　%d 人" % [spec[4], int(spec[1])]
	var ctx: Dictionary = (cs["ctx"] as Dictionary).duplicate()
	ctx["seed"] = randi_range(1, 2147483646)
	var r: Dictionary = await MeleeResolve.resolve(us if we_attack else foe, foe if we_attack else us, ctx)
	_demo_info.text = "%s　　钩牢率 %d%%　种子 %d\n空格　再来一场　　1–3　换局面　　Esc　退出" % [
		cs["label"], roundi(float((r["grapple"] as Dictionary).get("chance", 0.0)) * 100.0), int(r["seed"])]
	_demo_last.text = ""
	var st := play(self, _demo_ships[0 if we_attack else 1], _demo_ships[1 if we_attack else 0], r)
	if st != null:
		st.connect("finished", func() -> void:
			if is_instance_valid(_demo_last):
				_demo_last.text = "上一场：%s　%s" % [r["title"], r["summary"]])


static func _demo_side(spec: Array, player: bool) -> Dictionary:
	return MeleeResolve.make_side(int(spec[1]), int(spec[2]), float(spec[3]), str(spec[0]),
		{"name": str(spec[4]), "is_player": player})


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE, KEY_ENTER:
			_demo_run()
		KEY_1, KEY_2, KEY_3:
			_demo_case = int(key.keycode - KEY_1)
			_demo_run()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()


## 甲板四段简图：守船艏左艉右，舷边 · 舷腰 · 桅下 · 舵楼，左边另一格是攻方自家的船（「我船」/「敌船」，被反推过舷才相持）。
## 前线以左归攻方、前线那段相持、以右仍在守方；攻方是玩家涂金、是敌涂朱。桅下一面帅旗，斩落即倒。
class DeckStrip extends Control:
	const LABELS: PackedStringArray = ["舷边", "舷腰", "桅下", "舵楼"]
	var front := 0
	var flag_down := false
	var att_player := true
	var own_label := "我船"

	func _init() -> void:
		custom_minimum_size = Vector2(440, 50)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(f: int, flag: bool, player_att: bool, own := "我船") -> void:
		front = f
		flag_down = flag
		att_player = player_att
		own_label = own
		queue_redraw()

	func _draw() -> void:
		var font := UiTheme.font()
		var fs := UiTheme.SIZE_FOOT
		var top := 18.0
		var cell_h := size.y - top - 2.0
		var own_w := 58.0
		var hull_x := own_w + 10.0
		var bow := 16.0
		var cells_x := hull_x + bow
		var cell_w := (size.x - cells_x) / LABELS.size()
		var att_col: Color = UiTheme.GOLD if att_player else UiTheme.CINNABAR
		var def_col: Color = UiTheme.CINNABAR if att_player else UiTheme.GOLD
		var line_col := Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.75)
		# 攻方自家那格（被反推过舷时相持）
		var own := Rect2(0, top, own_w, cell_h)
		draw_rect(own, _tint(UiTheme.HONEY if front < 0 else att_col, 0.55 if front < 0 else 0.22))
		draw_rect(own, line_col, false, 1.0)
		draw_string(font, Vector2(0, top + cell_h * 0.5 + fs * 0.35), own_label, HORIZONTAL_ALIGNMENT_CENTER, own_w, fs, UiTheme.TEXT)
		# 守船船形（艏尖、艉方）
		var y0 := top
		var y1 := top + cell_h
		var hull := PackedVector2Array([Vector2(hull_x, (y0 + y1) * 0.5), Vector2(cells_x, y0),
			Vector2(size.x, y0), Vector2(size.x, y1), Vector2(cells_x, y1)])
		draw_colored_polygon(hull, _tint(UiTheme.INK_SOLID, 0.35))
		for i in range(LABELS.size()):
			var r := Rect2(cells_x + cell_w * i, y0, cell_w, cell_h)
			var c: Color
			if front >= LABELS.size():
				c = _tint(att_col, 0.45)
			elif front < 0:
				c = _tint(def_col, 0.2)
			elif i < front:
				c = _tint(att_col, 0.45)
			elif i == front:
				c = _tint(UiTheme.HONEY, 0.55)
			else:
				c = _tint(def_col, 0.2)
			draw_rect(r.grow(-1.0), c)
			if i > 0:
				draw_line(Vector2(r.position.x, y0), Vector2(r.position.x, y1), line_col, 1.0)
			draw_string(font, Vector2(r.position.x, y0 + cell_h * 0.5 + fs * 0.35), LABELS[i],
				HORIZONTAL_ALIGNMENT_CENTER, cell_w, fs, UiTheme.TEXT)
		hull.append(hull[0])
		draw_polyline(hull, line_col, 1.5)
		# 桅下帅旗：立着一面三角旗；斩落后旗杆折、旗委地
		var mast_x := cells_x + cell_w * 2.5
		if flag_down:
			draw_line(Vector2(mast_x, y0), Vector2(mast_x + 7, y0 - 6), UiTheme.TEXT_DIM, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(mast_x + 7, y0 - 6), Vector2(mast_x + 19, y0 - 3),
				Vector2(mast_x + 9, y0 - 1)]), _tint(UiTheme.TEXT_DIM, 0.8))
		else:
			draw_line(Vector2(mast_x, y0), Vector2(mast_x, 0), line_col, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(mast_x, 0), Vector2(mast_x + 14, 4), Vector2(mast_x, 8)]),
				def_col)
		# 前线标记
		if front < LABELS.size():
			var fx := own_w * 0.5 if front < 0 else cells_x + cell_w * (front + 0.5)
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 6, top - 9), Vector2(fx + 6, top - 9), Vector2(fx, top - 2)]),
				UiTheme.HONEY)

	static func _tint(c: Color, a: float) -> Color:
		return Color(c.r, c.g, c.b, a)
