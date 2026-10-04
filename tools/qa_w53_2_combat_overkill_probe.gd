extends SceneTree
## 击沉过量伤亡探针（lane-w53-2）：敌船被一发打沉时，超出的那份杀伤不凭空蒸发——记进甲板伤亡。
## 成因：PirateShip.take_damage 直接 hull_hp -= amount，击沉时留负数收走；超出的份既不伤人也没处记账，
##        残船重赏（5 残血挨 25）与恰好击沉（25 挨 25）的敌船，登船收尸时活人一般多——数值黑洞。
## 修法：击沉那一发把超出残余的份按与命中同口径的伤亡率折进 crew，hull 夹回 0（负数不是状态，向下游看齐）。
## 判法（回退 PirateShip.gd 的修法即红；对照两艘残余相同，「均匀杀伤」那份的 killed 期望一致，
##        唯一差 = 「过量那份额外记」——修法后 strictly 更多，回退则相等即红）：
##   一节：轻创不击沉——过量为 0，修法对普通中弹零影响（crew 同旧式）；
##   二节：恰好击沉（35 挨 35）vs 残血挨过量弹（5 挨 35，过量 30）——后者 crew 更少；
##   三节：过量期望——16 轮累计差 18 人（修法）对 0 人（回退），σ 0.95/轮×16 轮压不住、回退恰 0 即红。
## 用法：godot --headless --path . -s res://tools/qa_w53_2_combat_overkill_probe.gd
## 判词：W53_OVERKILL_PROBE PASS / FAIL k …。
const TAG := "W53_OVERKILL_PROBE"

var _fails: Array = []
var _orphans: Array = []
const ShipSceneRes := "res://scenes/PirateShip.tscn"


func _init() -> void:
	call_deferred("_run")


func _emit(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


## 孤本敌船一艘（满 crew、不进树物理、直接 take_damage）；target 只是摆设。
## 击沉会 queue_free 本体，但本帧属性仍读得到（overkill 折 crew 在 take_damage 里同步落账）。
func _shot(hull: float, amount: float, crew_n: int) -> Dictionary:
	var p := _new_stub(hull, crew_n)
	p.take_damage(amount)
	var out := {
		"hull": float(p.hull_hp) if is_instance_valid(p) else -1.0,
		"crew": int(p.crew) if is_instance_valid(p) else -1,
	}
	_orphans.append(p)
	return out


func _new_stub(hull: float, crew_n: int) -> PirateShip:
	var scene: PackedScene = load(ShipSceneRes)
	var p: PirateShip = scene.instantiate()
	p.name = "PirateShip_probe"
	p.hull_hp = hull
	p.hull_max = 100.0
	p.crew = crew_n
	p.target = Node2D.new()
	root.add_child(p.target)
	root.add_child(p)
	return p


func _run() -> void:
	# 一节：轻创不击沉——过量为 0，修法对普通中弹零影响（hull 照扣、不额外卖人）
	var stub := _new_stub(100.0, 30)
	var c0 := int(stub.get("crew"))
	stub.take_damage(20.0)
	_emit(is_equal_approx(float(stub.get("hull_hp")), 80.0),
		"轻创不击沉：hull 照扣到 80（得 %.1f）" % float(stub.get("hull_hp")))
	_emit(int(stub.get("crew")) <= c0 and int(stub.get("crew")) >= c0 - 2,
		"轻创只按式一份折人，不因为修法多死（%d → %d）" % [c0, int(stub.get("crew"))])
	stub.target.queue_free()
	stub.queue_free()

	# 二节：恰好击沉 vs 残血挨过量弹。残余 5 一致，「均匀杀伤」那份 killed 期望同，
	#        唯一差 = 「过量那份额外记」。用 amount=35：
	#   恰好（hull 35 挨 35）：均匀 35，死 ~1.33 → 期望剩 28.67。
	#   过量（hull  5 挨 35）：均匀 35 + 过量 30，死 ~1.33+1.14=2.47 → 期望剩 27.53。
	# 三节（回退笃红）：16 轮差 18 人（修法）vs 0 人（回退），σ 0.95/轮压不住。
	#        「杀伤随落距/品质衰减」不在本探针范围（喂入的 amount 是 x1 后的）；测的是「击沉过量蒸发」。
	var trials := 16
	var crew_exact := 0.0
	var crew_over := 0.0
	var hull_clamp_ok := true
	for i in range(trials):
		var k_exact := _shot(35.0, 35.0, 30)
		var k_over := _shot(5.0, 35.0, 30)
		crew_exact += float(k_exact["crew"])
		crew_over += float(k_over["crew"])
		if not is_equal_approx(float(k_over["hull"]), 0.0):
			hull_clamp_ok = false  # 击沉后 hull 要是 0.0
	crew_exact /= float(trials)
	crew_over /= float(trials)
	for p in _orphans:
		if is_instance_valid(p):
			p.queue_free()
	_emit(hull_clamp_ok, "击沉后 hull 夹回 0（不留负数以误判 / 状态一致）")
	_emit(crew_exact - crew_over > 0.6,
		"过量击沉比恰好击沉额外死人（恰好 %.2f 人 / 过量 %.2f 人，%d 轮均值超 0.6；回退恰 0）" % [crew_exact, crew_over, trials])

	if _fails.is_empty():
		print("%s PASS（3 条全绿）" % TAG)
		quit(0)
	else:
		print("%s FAIL %d" % [TAG, _fails.size()])
		quit(1)
