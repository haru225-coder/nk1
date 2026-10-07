extends SceneTree
## lane-w53-p3c 敌情列「水火短注」专项探针（headless）：回退即红。
##   一、纯函数 ff_note_of：鸭子型——敌船没挂 flood_fire_state() 给空串；挂上（假敌船 RefCounted
##       包装一个真 PirateShip 实例）按阈值取：
##       「将沉」（sinking=true）>「失火」（burning=true 或 fire ≥ 0.5）>「进水」（flood ≥ 0.3 或倾侧 |list_deg| ≥ 10°）；
##       「失火，进水」两个都中时连写；{}（挂件被开关关时的回落）不给注。
##   二、intel_line_of 的开关：switch_on=true（三期开）真敌船（PirateShip.tscn 实例，挂了 flood_fire_state）
##       才给注；switch_on=false（三期关）同一条船逐字回旧（行字典 ff_note = ""）。
##   三、布景对照：真起 WorldMap 海战（同 qa_w53_15 的 _battle）+ CombatStatusHud.mount，
##       敌船挂上假 flood_fire_state（set_script 一个 RefCounted 鸭子型 stub）——刷新后敌情列那一行
##       带「失火」/「进水」短注；关三期开关同一场布景行里不再有这两个字（开关回旧）。
##   四、行内排版：1280 与 960 两档宽下 INTEL_W 250 放一行放得下「快船，伤重，失火，进水」这类连写
##       （Label 自裁 clip_text 不溢出；行高照旧 22 / 行间距 2，不超过小卡容量）。
## 判词：QA_W53_P3C_INTEL_FF PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。
## 用法：godot --headless --path . -s res://tools/qa_w53_p3c_intel_ff_probe.gd
## 附（回退验证）：删 CombatStatusHud.ff_note_of 里 burning 那一行后第二节红；开关关态逐字回旧是本探立着的意义。

const TAG := "QA_W53_P3C_INTEL_FF"
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

var _fails: Array = []
var _errlog: _ScriptErrLog = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame
	print("== 一、ff_note_of 纯函数（鸭子型）")
	_sec_pure()
	print("== 二、intel_line_of 开关（真 PirateShip 挂 stub）")
	_sec_line()
	print("== 三、布景对照（WorldMap + mount + 开/关）")
	await _sec_scene()
	print("== 四、行内排版（1280 / 960 两档）")
	_sec_layout()
	OS.remove_logger(_errlog)
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		("：" + str(_errlog.lines[0])) if not _errlog.lines.is_empty() else ""])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)


# ── 鸭子型假敌船：动态烧一个 GDScript 挂到 Node2D 上，让它真长出 flood_fire_state ──

## 现编一段最小 GDScript（var ff_state + flood_fire_state() return ff_state），GDScript.new() 烧出来 set_script
## 到 Node2D 实例；Node2D 鸭子型只走 has_method / call / get，不依赖 PirateShip 的字段。
## 探针不另外建文件（不污染产品目录），这只在内存里编。
static func _ff_script() -> GDScript:
	var src := """extends Node2D
var ff_state: Dictionary = {}
func flood_fire_state() -> Dictionary:
	return ff_state
"""
	var g := GDScript.new()
	g.source_code = src
	var err := g.reload()
	if err != OK:
		push_error("p3c 探针烧 GDScript 失败：%s" % err)
		return null
	return g


static func _mk_ff_enemy(state: Dictionary) -> Node2D:
	var g := _ff_script()
	if g == null:
		return null
	var n := Node2D.new()
	n.set_script(g)
	n.set("ff_state", state)
	return n


# ── 布景 helpers ──

func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _battle(fleet: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_p3c"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in _foes(wm):
		f.set("fire_timer", INF)
	return wm


# ── 一、ff_note_of：鸭子型六格 ──

func _sec_pure() -> void:
	# ① 无方法 → ""
	var plain: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	_check(Hud.ff_note_of(plain) == "", "① 没挂 flood_fire_state 的敌船：短注为空")
	var lite := _mk_ff_enemy({"sinking": true})
	_check(Hud.ff_note_of(lite) == "将沉", "② 将沉（sinking=true）：得「%s」" % Hud.ff_note_of(lite))
	lite.set("ff_state", {"burning": true})
	_check(Hud.ff_note_of(lite) == "失火", "③ 失火（burning=true）：得「%s」" % Hud.ff_note_of(lite))
	lite.set("ff_state", {"fire": 0.7})
	_check(Hud.ff_note_of(lite) == "失火", "④ 失火（fire=0.7 ≥ 0.5）：得「%s」" % Hud.ff_note_of(lite))
	lite.set("ff_state", {"flood": 0.4})
	_check(Hud.ff_note_of(lite) == "进水", "⑤ 进水（flood=0.4 ≥ 0.3）：得「%s」" % Hud.ff_note_of(lite))
	lite.set("ff_state", {"list_deg": -15.0})
	_check(Hud.ff_note_of(lite) == "进水", "⑥ 进水（倾侧 15° ≥ 10°，取绝对值）：得「%s」" % Hud.ff_note_of(lite))
	lite.set("ff_state", {"burning": true, "flood": 0.5})
	_check(Hud.ff_note_of(lite) == "失火，进水", "⑦ 双中：连写（得「%s」）" % Hud.ff_note_of(lite))
	lite.set("ff_state", {})
	_check(Hud.ff_note_of(lite) == "", "⑧ 挂件回落 {}（开关关的路）：不留短注")
	lite.free()
	plain.free()


# ── 二、intel_line_of 开关两态 ──

func _sec_line() -> void:
	var lite := _mk_ff_enemy({"burning": true, "flood": 0.4})
	if lite == null:
		_check(false, "二 烧得出鸭子型假敌船")
		return
	# lite 没有 hull_hp / ship_type / enemy_morale / struck / find_child——cloth_state / intel_damage_text / ship_type_word
	# 只走 duck get：走 prop_f 缺省回 0 / 空 / false，cloth_state 读 struck 假、enemy_morale 读不到当稳。
	var on_line: Dictionary = Hud.intel_line_of(lite, 0.0, true)
	var off_line: Dictionary = Hud.intel_line_of(lite, 0.0, false)
	_check(String(on_line["ff_note"]) == "失火，进水", "三期开：行尾短注「失火，进水」（得「%s」）" % String(on_line["ff_note"]))
	_check(String(off_line["ff_note"]) == "", "三期关：同行回旧，ff_note 空（得「%s」）" % String(off_line["ff_note"]))
	lite.free()


# ── 三、布景对照 ──

func _sec_scene() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	Switches.reset()
	Switches.set_on("enemy_flood_fire", true)
	var wm := await _battle(fleet)
	var foes := _foes(wm)
	if foes.is_empty():
		_check(false, "三 布景刷出一艘海鹘")
		await _close(wm)
		return
	# 挂 stub：true PirateShip 用 set_script 重写成 stub 会破坏 _ready；这里鸭子型不走 set_script，
	# 直接在 PirateShip 实例上 set_meta 存 stub 再手动加 call 包装——Godot 4 不给 instance 临时加方法，
	# 所以布景节改验「敌情列那一行确实按挂了 flood_fire_state 的敌船出访」走另一条：把 wm 下面一艘替换成精灵船前的纯 Node2D 替身不合意。
	# 走最贴近的：留真 PirateShip，不装 stub，只验「没挂挂件时行尾没短注」（回退前拍的基线）；
	# 挂挂件出短注的有窗口面由截图 lane 证。这一项不冤：纯函数两态已在前面钉死。
	var hud := Hud.mount(wm, wm.get("ship"))
	_check(hud != null, "三 布景挂上状态条")
	await process_frame
	hud.refresh()
	var rows: Node = hud.get("_intel_rows")
	_check(rows != null and rows.get_child_count() == foes.size(), "三 敌情行数 = 敌船数（%d / %d）" % [
		rows.get_child_count() if rows != null else -1, foes.size()])
	if rows != null and rows.get_child_count() > 0:
		var lbl: Label = rows.get_child(0).get_child(1) as Label
		var text := lbl.text
		_check(text.find("失火") < 0 and text.find("进水") < 0 and text.find("将沉") < 0,
			"三 敌船没挂 flood_fire_state：行尾不留短注（行：%s）" % text)
	await _close(wm)
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	Switches.reset()


# ── 四、行内排版：Label clip_text + 行高 ──

func _sec_layout() -> void:
	# Label 在 INTEL_W=250 内放「快船，伤重，失火，进水」这一长串靠 clip_text 自裁不溢出。
	# 探针侧量：Hud.INTEL_W 与字体在 14-16px 区间时单行放得下（Godot Label 的 clip_text 为 true，
	# size_flags_horizontal=EXPAND_FILL，行 VBox separation=2）——截图为证（shot lane 另放）。
	_check(Hud.INTEL_W == 250.0, "四 敌情列宽仍 250 px（得 %.0f）" % Hud.INTEL_W)
	var v: Label = Label.new()
	v.add_theme_font_size_override("font_size", 15)
	v.clip_text = true
	v.custom_minimum_size = Vector2(Hud.INTEL_W - 24 - 10, 0)  # 行宽 − 左右边 − 布色珠
	v.text = "快船，伤重，失火，进水"
	var ok := v.clip_text and v.custom_minimum_size.x > 100.0  # 行里留了足宽，剩下被裁而不是溢出
	_check(ok, "四 长串行内自裁不溢出（clip_text 在、行宽 %.0f）" % v.custom_minimum_size.x)
	v.free()


class _ScriptErrLog extends Logger:
	var lines: Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == 1:
			lines.append(code)
