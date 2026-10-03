extends Node
## lane w53-9：过场层输入时序探针。两路，钉一处修复（回退该处修复，两路即红）：
##   ending_fade_key   结局过场收尾连按空格：本层黑幕退去那一截（CutscenePlayer 的 FADE）按键照吞，底下刚建好的「了结」册页不许被合上
##   ending_fade_click 同一窗口换成鼠标：点册页上的「记下这一纲」也不许点着——册页还没露脸（与上一路同一处修复）
## 必须带窗口、且不能用 -s 跑（-s 下 Cinematics.live() 恒假，Main 不放结局过场）：
##   DISPLAY=:2 godot --path . res://tools/qa_w53_9_cutscene_input_probe.tscn
## 逐路一行 W53_9_CASE <路> OK|FAIL <细节>；末行 QA_W53_9_CUTSCENE_INPUT OK | FAIL <n>，rc 0 / 1。
## 等待一律按状态推进、上界按墙钟（CASE_MS）；撞上界判红并写明「墙钟上界先到」，不碰运气。
## 压帧自检：NK1_PROBE_SLOW_MS=150 DISPLAY=:2 godot --path . res://tools/qa_w53_9_cutscene_input_probe.tscn

const ShotGate := preload("res://tools/shot_gate.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const TAG := "QA_W53_9_CUTSCENE_INPUT"
## 探针自己发的鼠标事件打这个 device 号（与共用 X 上的真指针分开）
const PROBE_DEVICE := 1953
## 单路墙钟上界：最长一段是结局末镜连按到底再等黑幕退净（约 4 s 游戏时间），压帧下留足余量
const CASE_MS := 60000
## CutscenePlayer.Phase：PRE / PLAY / OUTRO / FADE / DONE
const PH_PLAY := 1
const PH_FADE := 3
## FADE 里只在前半截按：按下的事件下一帧才分发，留出一帧（delta 封顶 0.133 s）的余量，免得落到本层释放之后
const FADE_PRESS_UNTIL := 0.2

var _fails := 0
var _main: Node
var _cine: GDScript


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1280, 720)
	if Kit.is_headless():
		print("W53_9_CASE all FAIL headless 下过场不建节点：须 DISPLAY=:2 带窗口、以场景启动")
		print("%s FAIL 1" % TAG)
		get_tree().quit(1)
		return
	ShotGate.frame_pressure(get_tree())
	_cine = load("res://scripts/cutscene/Cinematics.gd")
	_cine.set("enabled", true)
	_cine.set("auto_opening", false)
	_cine.set("opening_seen", true)
	print("%s_BEGIN live=%s" % [TAG, _cine.call("live")])
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	for _i in 8:
		await get_tree().process_frame
	await _case_ending_fade_key()
	await _case_ending_fade_click()
	print("%s %s" % [TAG, "OK" if _fails == 0 else "FAIL %d" % _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _verdict(case_name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("W53_9_CASE %s %s %s" % [case_name, "OK" if ok else "FAIL", detail])


# ── 输入 ───────────────────────────────────────────────
func _key(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		e.device = PROBE_DEVICE
		Input.parse_input_event(e)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


# ── 过场 ───────────────────────────────────────────────
func _player() -> CutscenePlayer:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n is CutscenePlayer and not (n as Node).is_queued_for_deletion():
			return n
	return null


func _phase(p: CutscenePlayer) -> int:
	return int(p.get("_phase")) if is_instance_valid(p) else -1


## 起播镜号在压黑段走完、进第一镜那一刻才读（debug_start_shot 是静态量）：等到进镜再复位，免得串到下一段
func _until_playing(p: CutscenePlayer) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and _phase(p) < PH_PLAY and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	CutscenePlayer.debug_start_shot = 0


# ── 一、结局过场收尾的黑幕淡出窗口 ─────────────────────
## Main 真实接线：占城港上了结「海口信路」→ 结局过场（从末镜起）→ 过场全黑时 Main 建好了结册页 → 本层黑幕淡出。
func _start_ending() -> CutscenePlayer:
	GameState.chapter = 4
	_cine.set("enabled", false)
	GameState.last_port = "champa"
	_main.call("load_scene", "champa")
	_cine.set("enabled", true)
	await _frames(4)
	var picked := {}
	for e in GameState.chapter_def(4).get("endings", []):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == "sea_letter":
			picked = e
	if picked.is_empty():
		return null
	GameState.ending_id = "sea_letter"
	CutscenePlayer.debug_start_shot = 3
	_main.call("_show_chapter_dialog", {"advanced": false, "resolved": true,
		"title": picked.get("title", "了结"), "text": picked.get("text", ""), "scene": str(picked.get("scene", ""))})
	var p := _player()
	await _until_playing(p)
	return p


func _sheet_alive() -> bool:
	return is_instance_valid(_main.get("_chapter_host"))


## 本层释放后还要能合上册页：同一个键这时照常落到 Main 的 ui_accept（不然上面的「没合上」是键根本不通，不算数）
func _control_confirm(case_name: String) -> String:
	await _frames(2)
	_key(KEY_SPACE)
	await _frames(3)
	var closed := not _sheet_alive()
	if not closed:
		_fails += 1
		print("W53_9_CASE %s FAIL 对照：过场层走后按空格册页仍没合上——键根本不通，上面的判定不作数" % case_name)
	# 合上后 load_scene 回了结页 / 终局岸带，可能起墨幕：等它收场
	var t0 := Time.get_ticks_msec()
	while not get_tree().get_nodes_in_group("nk1_ui_transition").is_empty() and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	return "对照（过场层走后按空格）册页合上=%s" % closed


## 连按空格把末镜一路按完：PLAY 里每下推一步、OUTRO 里被吞；FADE 里只在前半截按（见 FADE_PRESS_UNTIL）。
## 本层释放那一刻：了结册页必须还在、页没换。
func _case_ending_fade_key() -> void:
	var p := await _start_ending()
	if p == null:
		_verdict("ending_fade_key", false, "结局过场没起来（chapters.json 第 4 章 endings 里找不到 sea_letter，或过场层没上场）")
		return
	var page := str(_main.get("current_scene_id"))
	var t0 := Time.get_ticks_msec()
	var n := 0
	var in_fade := 0
	var sheet_at_fade := false
	while is_instance_valid(p) and Time.get_ticks_msec() - t0 < CASE_MS:
		var ph := _phase(p)
		if ph == PH_FADE:
			if in_fade == 0:
				sheet_at_fade = _sheet_alive()
			if float(p.get("_phase_t")) <= FADE_PRESS_UNTIL and n % 2 == 0:
				_key(KEY_SPACE)
				in_fade += 1
		elif n % 2 == 0:
			_key(KEY_SPACE)
		n += 1
		await get_tree().process_frame
	await _frames(3)
	var alive := _sheet_alive()
	var same := str(_main.get("current_scene_id")) == page
	var ok := in_fade > 0 and sheet_at_fade and alive and same
	var note := "淡出窗口里按空格 %d 下；黑幕淡出起时册页已建=%s → 本层走后册页还在=%s 页=%s→%s" % [in_fade, sheet_at_fade, alive, page, _main.get("current_scene_id")]
	if in_fade == 0:
		note += "（一下都没按进淡出窗口：判不了）"
	elif not ok:
		note += "（黑幕还没退净，按键就把了结册页合上了）"
	if alive:
		note += "；" + await _control_confirm("ending_fade_key")
	_verdict("ending_fade_key", ok, note)


## 同一窗口换成鼠标：Esc 跳过 → 册页建好、黑幕刚开始退 → 点册页上的确认钮。本层释放后册页必须还在。
func _case_ending_fade_click() -> void:
	var p := await _start_ending()
	if p == null:
		_verdict("ending_fade_click", false, "结局过场没起来")
		return
	var page := str(_main.get("current_scene_id"))
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and _phase(p) < PH_PLAY and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	_key(KEY_ESCAPE)
	while is_instance_valid(p) and _phase(p) != PH_FADE and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	var ok_btn: Button = null
	var host: Node = _main.get("_chapter_host")
	if is_instance_valid(host):
		for b in host.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree():
				ok_btn = b
	var clicked := false
	var btn_text := "?" if ok_btn == null else ok_btn.text
	if _phase(p) == PH_FADE and ok_btn != null and float(p.get("_phase_t")) <= FADE_PRESS_UNTIL:
		_click(ok_btn.get_global_rect().get_center())
		clicked = true
	while is_instance_valid(p) and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	await _frames(3)
	var alive := _sheet_alive()
	var same := str(_main.get("current_scene_id")) == page
	var ok := clicked and alive and same
	var note := "淡出窗口里点确认钮「%s」=%s → 本层走后册页还在=%s 页=%s→%s" % [btn_text, clicked, alive, page, _main.get("current_scene_id")]
	if not clicked:
		note += "（没点进淡出窗口：判不了）"
	elif not ok:
		note += "（黑幕还没退净，点击就落到了册页的确认钮上）"
	if alive:
		note += "；" + await _control_confirm("ending_fade_click")
	_verdict("ending_fade_click", ok, note)
