extends SceneTree
## 过场播放器（scripts/cutscene/CutscenePlayer.gd）字幕推进探针（lane w53-9 立；w54-base 改回「补全 → 下一句」分两拍）：
## 进第一镜后直接调 _advance_input 两拍，逐拍记镜号与 _shot_dur——
##   拍一：第一条正在写，只补全它，_shot_dur 与镜号不动（补全与提前并成一拍即红：刚补全的那句来不及读）；
##   拍二：没有句子在写了，才把第二条提前，_shot_dur 缩短、仍不跳镜（推进丢一拍即红）。
## 真输入三路（鼠标 / 触屏 / 空格）走同一函数，见 qa_w53_9_cutscene_input_probe 的 touch_one_step。
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

	# 三、镜头旗标换底：weigui 用了 bg_alt，条件命中即换（里头要等一帧：不 await 的话 _report 先退进程，这一节一行判词都不出）
	await _probe_bg_alt()

	_report()


## 进第一镜（_phase 到 PLAY）的头一醒就入拍：进镜那一帧第一条（t=0.0，硬切镜无转场垫底）已起笔、还没写完。
## 不先空等若干帧——压帧档下空等那几帧的游戏时间够把第一条写完，拍一就没有「正在写」的句子可补，两档结论不同。
func _await_path_advance() -> void:
	var p := Player.play(root, "qap_w53_9_path", "res://tools/qa_w53_9_cutscene_fixture.json")
	if p == null:
		_fails.append("探针过场未建：fixture/FIXTURE 未起")
		return
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(p) and (p as Node).is_inside_tree() and int(p.get("_phase")) < 1 and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	if not is_instance_valid(p) or not (p as Node).is_inside_tree():
		_fails.append("探针过场没到 PLAY 就退场（Play→Outro 空镜）：_shots/FIXTURE 未接住")
		return
	var phase := int(p.get("_phase"))
	if phase != 1: # Phase.PLAY == 1
		_check(false, "输入推进走通：_phase == PLAY", "过场 20 s 墙钟内没到 PLAY（phase=%d）" % phase)
		return
	# 拍一：第一条正在写、第二条（t=4.5）未出，_shot_dur=5.0——只补全第一条，_shot_dur 与镜号都不动
	var writing := _writing(p)
	if writing.is_empty():
		_check(false, "拍一前第一条字幕正在写", "进镜后头一醒没有正在写的字幕：拍一判不了")
		return
	var idx: int = p.get("_idx")
	var dur0: float = p.get("_shot_dur")
	p._advance_input()
	var dur1: float = p.get("_shot_dur")
	var done: bool = writing["node"].is_revealed()
	_check(int(p.get("_idx")) == idx and done,
		"第一拍补全正在写的第一条、不跳镜",
		"第一拍没补全第一条或走了镜（补全=%s 镜 %d → %d）" % [done, idx, int(p.get("_idx"))])
	_check(dur1 == dur0,
		"第一拍只补全、不提前下一句 _shot_dur %.2f → %.2f" % [dur0, dur1],
		"第一拍连带提前了下一句 _shot_dur %.2f → %.2f：补全与提前并成一拍，刚补全的那句来不及读" % [dur0, dur1])
	# 拍二：已没有句子在写，这一拍才把第二条提前（_shot_dur 缩短），仍不跳镜
	p._advance_input()
	var dur2: float = p.get("_shot_dur")
	_check(int(p.get("_idx")) == idx and dur2 < dur1,
		"第二拍才提前下一句 _shot_dur %.2f → %.2f、不跳镜" % [dur1, dur2],
		"第二拍没提前下一句 _shot_dur %.2f → %.2f 镜 %d → %d：推进丢了一拍" % [dur1, dur2, idx, int(p.get("_idx"))])


## 正在逐字写的那句（已出场、没写完）；没有返回 {}
func _writing(p: Node) -> Dictionary:
	for e in (p.get("_cap_live") as Array):
		if bool(e["started"]) and not e["node"].is_revealed():
			return e
	return {}


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
