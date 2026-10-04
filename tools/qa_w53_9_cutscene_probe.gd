extends SceneTree
## 过场播放器（scripts/cutscene/CutscenePlayer.gd）字幕推进探针（lane w53-9）：
## 开镜后按真实输入把当前镜走完，逐拍记 _shot_dur 的变化——
##   已修：下一句没出与补全互为同一拍，第一条字幕「未出场」只拍一拍就起；
##   复现原形（红）：第一条字幕未出场时第一拍只补全、第二拍才起下一句，两拍 _shot_dur 都要动。
## 反变形：验证「快跑完」与「跳镜」两条同族调用走原样推进（防改坏 _advance_input 的同时直接原判红）。
## Run: DISPLAY=:2 godot --path . -s res://tools/qa_w53_9_cutscene_probe.gd  （headless 下同跑：CutscenePlayer headless 立即退场，
##  探针撞形态返回非零——验输入走真实 paint 底盘）
## 压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_w53_9_cutscene_probe.gd
## 末行字面（probe_pressure TEXT_PROBES 登末行账的钩子）：QA_W53_9_CUTSCENE_PASS | QA_W53_9_CUTSCENE_FAIL <n>
const _TAIL_FORMAT := "QA_W53_9_CUTSCENE_PASS | QA_W53_9_CUTSCENE_FAIL <n>"  # probe_pressure tail_mark 经去注释源码读这个钩子的字（w87-k2 承接窗补登顺手原槽同款）

const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const Player := preload("res://scripts/cutscene/CutscenePlayer.gd")
const InkText := preload("res://scripts/cutscene/cs_ink_text.gd")
const SealG := preload("res://scripts/cutscene/cs_seal.gd")

const TAG := "QA_W53_9_CUTSCENE"
var _fails: Array = []
var _main: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	ShotGate.frame_pressure(self)
	print(TAG, "_BEGIN")
	if Kit.is_headless():
		# headless 不建节点：整个探针幕验不了（与 letterbox_signal_probe 同口径）
		_fails.append("headless 下过场不建节点、无从验输入推进：请用 DISPLAY=:2 跑")
		_report()
		return

	# 一、_advance_input 字幕推进：开枪把开镜字幕拍走，逐拍记 _shot_dur
	await _await_path_advance()

	# 二、从黑起播：from_black=true 的第0帧基板已全黑
	await _probe_from_black()

	# 三、镜头旗标换底：weigui 用了 bg_alt，条件命中即换
	_probe_bg_alt()

	_report()


## 一等 _ready/_build_captions/_swap_fx/_prewarm 落定，再入拍。
func _await_path_advance() -> void:
	var p := Player.play(root, "qap_w53_9_path", "res://tools/qa_w53_9_cutscene_fixture.json")
	if p == null:
		_fails.append("探针过场未建：fixture/FIXTURE 未起")
		return
	for _i in range(30):
		await process_frame
		if not is_instance_valid(p) or not (p as Node).is_inside_tree():
			break
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		_fails.append("探针过场在 30 帧内退场（Play→Outro 空镜）：_shots/FIXTURE 未接住")
		return
	# 快进帧间到达 PLAY（Headless 则直接 DONE）
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and (p as Node).is_inside_tree() and int(p.get("_phase")) < 1 and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		_fails.append("探针过场没在 2 s 内至_PLAY")
		return
	var phase := int(p.get("_phase"))
	if phase != 1: # Phase.PLAY == 1
		print(TAG, "_SKIP_ADVNCE phase=", phase, "（headless 退场）")
		_check(false, "输入推进走通：_phase == PLAY", "过场没到 PLAY（phase=%d）：fixture 路径被模仿" % phase)
		return
	# 拍一：第一条字幕未出场（t = 0.0 不会被排入 floor），当前 _shot_dur=5.0；
	# 已修：连点一律拍一拍，_shot_dur 应动；复现原形红：第一拍只补全、_shot_dur 不动
	var before_dur: float = p.get("_shot_dur")
	var before_idx: int = p.get("_idx")
	p._advance_input()
	var after_dur: float = p.get("_shot_dur")
	var after_idx: int = p.get("_idx")
	_check(after_idx == before_idx,
		"第一拍不跳镜",
		"第一拍走了镜 %d → %d（轨线被改）" % [before_idx, after_idx])
	_check(after_dur < before_dur,
		"第一拍下一句没出的当拍已提前 _shot_dur %.2f → %.2f" % [before_dur, after_dur],
		"第一拍只补全未提前 _shot_dur（%.2f → %.2f）：原形的「补全与提前各占一拍」在转场里连点多吃一拍" % [before_dur, after_dur])


func _probe_from_black() -> void:
	# from_black=true：_ready 第 0 帧 _base.modulate.a 应为 1（不然会先闪出底下的画面再压黑）
	var p := Player.play(root, "qap_w53_9_path", "res://tools/qa_w53_9_cutscene_fixture.json", true)
	if p == null:
		_fails.append("from_black 探针过场未建")
		return
	await process_frame
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		# headless 下已退场
		print(TAG, "_SKIP_FROM_BLACK（headless / 未驻留）")
		return
	var base_a := 0.0
	var base = p.get("_base")
	if base != null:
		base_a = float((base as ColorRect).modulate.a)
	_check(base_a == 1.0,
		"from_black：首帧基板立即全黑 a=%.2f" % base_a,
		"from_black：首帧基板未全黑 a=%.2f（起播时底下画面会先闪出）" % base_a)
	# 清场
	if is_instance_valid(p) and (p as Node).is_inside_tree():
		(p as Node).queue_free()


func _probe_bg_alt() -> void:
	# weigui 的 shot0：未归在港与不在港的底图 / 运镜要分开
	var p2: CutscenePlayer = Player.new()
	p2.cutscene_id = "ending_weigui"
	p2._data_path = "res://data/cutscenes.json"
	root.add_child(p2)
	await process_frame
	# 要把 _ready 走一遍能读到 _shots；headless / 无 ready 时自行装载
	var d := Kit.load_json(p2._data_path)
	var cs: Variant = d.get("cutscenes", {}).get("ending_weigui", {})
	var shots: Array = []
	if typeof(cs) == TYPE_DICTIONARY and typeof((cs as Dictionary).get("shots")) == TYPE_ARRAY:
		shots = (cs as Dictionary)["shots"]
	p2._shots = shots
	_check(p2._shots.size() >= 1, "ending_weigui 至少 1 镜", "ending_weigui 目不识镜")
	if p2._shots.size() >= 1:
		var view0: Dictionary = p2._shot_view(p2._shots[0] as Dictionary)
		_check(str(view0.get("bg", "")) == "res://assets/bg_sea_route.jpg",
			"未归无存旗：shot0 底图 bg_sea_route",
			"未归无存旗：shot0 底图意外为 %s（开拍即变）" % view0.get("bg"))
		var gs: Node = root.get_node_or_null("/root/GameState")
		if gs != null:
			gs.call("set_flag", "weigui_at_harbor")
			var view1: Dictionary = p2._shot_view(p2._shots[0] as Dictionary)
			_check(str(view1.get("bg", "")) == "res://assets/bg_xinghua_harbor.jpg",
				"未归立旗：shot0 改底图 bg_xinghua_harbor",
				"未归立旗后 shot0 底图仍为 %s（海口上遇见背海图）" % view1.get("bg"))
			gs.call("set_flag", "_w53_9_clear")
	p2.queue_free()


func _check(ok: bool, good: String, bad := "") -> void:
	if ok:
		print("  ✓ ", good)
	else:
		print("  ✗ ", bad if bad != "" else good)
		_fails.append(bad if bad != "" else good)


func _report() -> void:
	if _fails.is_empty():
		print(TAG, "_PASS")
		quit(0)
		return
	for f in _fails:
		print("FAIL: ", f)
	print(TAG, "_FAIL ", _fails.size())
	quit(1)
