extends Node
## lane w53-9：过场层输入时序探针。五路，钉四处修复（回退哪一处修复，对应那几路即红）：
##   ending_fade_key   结局过场收尾连按空格：本层黑幕退去那一截（CutscenePlayer 的 FADE）按键照吞，底下刚建好的「了结」册页不许被合上
##   ending_fade_click 同一窗口换成鼠标：点册页上的「记下这一纲」也不许点着——册页还没露脸（与上一路同一处修复）
##   outro_esc_curtain 自然收尾压黑途中按 Esc：黑幕从当前黑度接着压，不许先退回透明、画面亮回来再重新压黑（CutscenePlayer.skip）
##   touch_one_step    触屏点一下只推一步：补全正在写的那句，不连带把下一句提上来（引擎另把触点模拟成一次左键）
##   ut_click_scope    墨幕题签停拍时点一下只收本幕：底下刚换好的四方沙盘页，标题演出不被同一下点击补全（UiTransition._input）
## 必须带窗口、且不能用 -s 跑（-s 下 Cinematics.live() 恒假，Main 不放结局过场、不起墨幕）：
##   DISPLAY=:2 godot --path . res://tools/qa_w53_9_cutscene_input_probe.tscn
## 逐路一行 W53_9_CASE <路> OK|FAIL <细节>；末行 QA_W53_9_CUTSCENE_INPUT OK | FAIL <n>，rc 0 / 1。
## 等待一律按状态推进、上界按墙钟（CASE_MS）；撞上界判红并写明「墙钟上界先到」，不碰运气。
## 压帧自检：NK1_PROBE_SLOW_MS=150 DISPLAY=:2 godot --path . res://tools/qa_w53_9_cutscene_input_probe.tscn

const ShotGate := preload("res://tools/shot_gate.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const TAG := "QA_W53_9_CUTSCENE_INPUT"
## 探针自己发的鼠标 / 触屏事件打这个 device 号（与共用 X 上的真指针分开）
const PROBE_DEVICE := 1953
## 单路墙钟上界：最长一段是结局末镜连按到底再等黑幕退净（约 4 s 游戏时间），压帧下留足余量
const CASE_MS := 60000
## CutscenePlayer.Phase：PRE / PLAY / OUTRO / FADE / DONE
const PH_PLAY := 1
const PH_OUTRO := 2
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
	print("%s_BEGIN live=%s emulate_mouse_from_touch=%s" % [TAG, _cine.call("live"), Input.is_emulating_mouse_from_touch()])
	await _case_touch_one_step()
	await _case_outro_esc_curtain()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	for _i in 8:
		await get_tree().process_frame
	await _case_ut_click_scope()
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


func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.pressed = pressed
		t.position = pos
		t.device = PROBE_DEVICE
		Input.parse_input_event(t)


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


## 自己起一段过场（不经 Main），从第 shot 镜开始
func _start_cs(id: String, shot: int) -> CutscenePlayer:
	CutscenePlayer.debug_start_shot = shot
	var p := CutscenePlayer.play(self, id)
	await _until_playing(p)
	return p


## 起播镜号在压黑段走完、进第一镜那一刻才读（debug_start_shot 是静态量）：等到进镜再复位，免得串到下一段
func _until_playing(p: CutscenePlayer) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and _phase(p) < PH_PLAY and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	CutscenePlayer.debug_start_shot = 0


func _drain(p: CutscenePlayer) -> void:
	if not is_instance_valid(p):
		return
	p.skip()
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame


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


# ── 二、自然收尾压黑途中按 Esc：黑幕不退回 ──────────────
## 「海口信路」末镜：连按空格按到自然收尾（OUTRO、非快进），黑幕压到约一半时按 Esc。
## 记 Esc 生效（_fast 翻真）前一帧的黑度，此后直到黑幕压满，每帧黑度都不许低于它。
func _case_outro_esc_curtain() -> void:
	var p := await _start_cs("ending_sea_letter", 3)
	var t0 := Time.get_ticks_msec()
	var n := 0
	while is_instance_valid(p) and _phase(p) < PH_OUTRO and Time.get_ticks_msec() - t0 < CASE_MS:
		if n % 2 == 0:
			_key(KEY_SPACE)
		n += 1
		await get_tree().process_frame
	if _phase(p) != PH_OUTRO or bool(p.get("_fast")):
		_verdict("outro_esc_curtain", false, "没按到自然收尾（phase=%d fast=%s）" % [_phase(p), p.get("_fast") if is_instance_valid(p) else null])
		await _drain(p)
		return
	var dim := p.get("_dimmer") as ColorRect
	while is_instance_valid(p) and _phase(p) == PH_OUTRO and dim.modulate.a < 0.45 and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	if _phase(p) != PH_OUTRO:
		_verdict("outro_esc_curtain", false, "压黑走完了还没来得及按 Esc（压帧过重？phase=%d）" % _phase(p))
		await _drain(p)
		return
	_key(KEY_ESCAPE)
	# 按下的键下一帧开头才分发、随后本层 _process 才按新相位算黑度：协程在 process_frame 上醒来时还在本帧
	# _process 之前——头一回见到 _fast 为真的那一醒，读到的黑度正是 Esc 生效前最后一帧的
	var before := -1.0
	var low := 2.0
	var seq := PackedStringArray()
	while is_instance_valid(p) and _phase(p) == PH_OUTRO and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
		if not is_instance_valid(p):
			break
		var a := dim.modulate.a
		if before < 0.0:
			if not bool(p.get("_fast")):
				continue
			before = a
		low = minf(low, a)
		seq.append("%.2f" % a)
	var fast := is_instance_valid(p) and bool(p.get("_fast"))
	var reached := _phase(p) == PH_FADE or not is_instance_valid(p)
	var ok := before >= 0.0 and fast and reached and low >= before - 0.02
	_verdict("outro_esc_curtain", ok, "Esc 前黑度 %.2f，此后最低 %.2f（%s）快收=%s 压满=%s" % [before, low, " ".join(seq), fast, reached]
		+ ("" if ok else "（Esc 后黑幕不许退回、画面不许亮回来）"))
	await _drain(p)


# ── 三、触屏点一下只推一步 ─────────────────────────────
func _layer_done(p: CutscenePlayer) -> bool:
	var layers: Array = p.get("_layers")
	var front := int(p.get("_front"))
	return front >= 0 and bool((layers[front] as Dictionary)["done"])


## 正在逐字写的那句（已出场、没写完）；没有返回 {}
func _revealing(p: CutscenePlayer) -> Dictionary:
	for e in (p.get("_cap_live") as Array):
		if bool(e["started"]) and not e["node"].is_revealed():
			return e
	return {}


func _started(p: CutscenePlayer) -> int:
	var n := 0
	for e in (p.get("_cap_live") as Array):
		if bool(e["started"]):
			n += 1
	return n


## 等到「转场已走完、有一句正在写」；返回那一句，撞墙钟返回 {}
func _wait_mid_reveal(p: CutscenePlayer) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
		if _phase(p) == PH_PLAY and _layer_done(p):
			var e := _revealing(p)
			if not e.is_empty():
				return e
	return {}


## 「海上宋鬼」第 2 镜闪白入（0.8 秒），叙述 t=0.8 起逐字写约 1.3 秒：转场走完、字还在写，点一下应只补全这一句。
## 引擎默认 emulate_mouse_from_touch：一次触点 = 一次 ScreenTouch + 一次模拟左键，两样都进 _input。
## 先拿真鼠标左键做对照（只推一步），再换触屏点。
func _case_touch_one_step() -> void:
	Engine.time_scale = 0.5
	var rows := PackedStringArray()
	var ok := true
	for how in ["mouse", "touch"]:
		var p := await _start_cs("ending_sea_ghost", 1)
		var target := await _wait_mid_reveal(p)
		if target.is_empty():
			ok = false
			rows.append("%s: 墙钟上界先到，没等到「转场走完、有一句正在写」" % how)
			await _drain(p)
			continue
		var before := _started(p)
		var idx := int(p.get("_idx"))
		if how == "mouse":
			_click(Vector2(640, 360))
		else:
			_tap(Vector2(640, 360))
		await _frames(3)
		var revealed: bool = target["node"].is_revealed()
		var after := _started(p)
		var one := revealed and after == before and int(p.get("_idx")) == idx
		ok = ok and one
		rows.append("%s: 补全=%s 已出句 %d→%d 镜 %d→%d" % [how, revealed, before, after, idx, int(p.get("_idx"))])
		await _drain(p)
	Engine.time_scale = 1.0
	_verdict("touch_one_step", ok, "；".join(rows) + ("" if ok else "（应只补全正在写的一句，不连带提下一句）"))


# ── 四、墨幕题签停拍点一下只收本幕 ─────────────────────
## 标题页「开卷」→ 墨幕全黑时换上四方沙盘北页（TitleStage 从头演）→ 停拍时点一下：
## 墨幕收到（_go_early），底下北页的标题演出照常往下演（is_revealing 仍真），不被同一下补全。
func _case_ut_click_scope() -> void:
	var stage: Node = _main.find_child("TitleStage", true, false)
	if stage != null and bool(stage.call("is_revealing")):
		stage.call("_complete")
	await _frames(2)
	var start_btn := _main.get("start_button") as Button
	if stage == null or start_btn == null or not start_btn.is_visible_in_tree():
		_verdict("ut_click_scope", false, "标题页没就位（stage=%s 开卷钮=%s）" % [stage, start_btn])
		return
	start_btn.pressed.emit()
	var ut: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
		var g := get_tree().get_nodes_in_group("nk1_ui_transition")
		if not g.is_empty() and bool(g[0].get("_holding")):
			ut = g[0]
			break
	if ut == null:
		_verdict("ut_click_scope", false, "墙钟上界先到，没等到墨幕停拍")
		return
	var page := str(_main.get("current_scene_id"))
	var was_revealing := bool(stage.call("is_revealing"))
	_click(Vector2(640, 360))
	await _frames(2)
	var go_early := is_instance_valid(ut) and bool(ut.get("_go_early"))
	var still := bool(stage.call("is_revealing"))
	var ok := was_revealing and go_early and still
	_verdict("ut_click_scope", ok, "停拍时页=%s 北页演出中=%s → 点一下：墨幕收场=%s 北页演出仍在演=%s" % [page, was_revealing, go_early, still]
		+ ("" if ok else "（点一下只该收墨幕，不该连带把底下新页的标题演出补全）"))
	while is_instance_valid(ut) and Time.get_ticks_msec() - t0 < CASE_MS:
		await get_tree().process_frame
	stage.call("_complete")
	await _frames(2)
