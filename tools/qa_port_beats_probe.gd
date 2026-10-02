extends SceneTree
## lane w26-k7：PortBeats.due() 终局守卫契约探针（headless、不截图、不开窗）。
## 守卫位置交底：w25-j2 顶在调用方 Main._on_enter_port 先截，w26-k7 已下沉进
## PortBeats.due/arrive 接口 —— 「终局后不演港口节拍」 是账口自身的早退性质，
## 不再靠调用方记得截对顺序。本探针直面账口喂真 / 假 is_ended 实参 演四例：
##   ① 未终局 + 到港（下针条件够）→ 演（due 返非空）
##   ② 未终局 + 不到港（下针条件不够）→ 不演（due 返空）
##   ③ 已终局 + 到港（条件其实够）→ 不演（本 lane 核心）
##   ④ 已终局 + 不到港 → 不演
## 反向变异（红绿自证）：scripts/core/PortBeats.gd due() 早退条件去掉 「is_ended or 」
## 四字 → 例③仍算出 monk，探针 rc=1；复原四字 → rc=0。
## fixture 是缩微泉州链（针名与 data/port_beats.json 开局两针对齐，结构同真表），
## 不进 GameManager / 不读 data —— 探针只钉接口语义。
## 用法：godot --headless --path . -s res://tools/qa_port_beats_probe.gd
## 输出末行 PORT_BEATS_PROBE rc=N（N>0 即红）。

var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("PORT_BEATS_PROBE_BEGIN")
	var BM := load("res://scripts/core/PortBeats.gd")
	var fixture: Array = [
		{"id": "quanzhou_monk", "entry": "monk", "port": "quanzhou", "order": 10, "requires": {}},
		{"id": "quanzhou_merchant", "entry": "merchant", "port": "quanzhou", "order": 20, "requires": {"seen": ["monk"]}},
	]

	# ── ① 未终局 + 到港：monk 针没记名、requires 全空 → 该演 ──
	var b1 = BM.new()
	b1.init(fixture)
	var r1: Dictionary = b1.due("quanzhou", ["start"], [], ["quanzhou"], 1, false)
	_check(str(r1.get("entry", "")) == "monk",
		"① 未终局 + 到港（条件够）：due 返 monk（实返 %s）" % JSON.stringify(r1))

	# ── ② 未终局 + 不到港：merchant 已记名、其下一针 requires.seen 不足 → 链停空账 ──
	var b2 = BM.new()
	b2.init(fixture)
	var r2: Dictionary = b2.due("quanzhou", ["start", "monk", "merchant"], [], ["quanzhou"], 1, false)
	_check(r2.is_empty(),
		"② 未终局 + 不到港（条件不够）：due 空账（实返 %s）" % JSON.stringify(r2))

	# ── ③ 已终局 + 到港：条件其实够（同①账况），守卫截空 —— 本 lane 核心 ──
	var b3 = BM.new()
	b3.init(fixture)
	var r3: Dictionary = b3.due("quanzhou", ["start"], [], ["quanzhou"], 1, true)
	_check(r3.is_empty(),
		"③ 已终局 + 到港（条件够）：due 空账、守卫自拦（实返 %s）" % JSON.stringify(r3))

	# ── ④ 已终局 + 不到港：空账 ──
	var b4 = BM.new()
	b4.init(fixture)
	var r4: Dictionary = b4.due("quanzhou", ["start", "monk", "merchant"], [], ["quanzhou"], 1, true)
	_check(r4.is_empty(),
		"④ 已终局 + 不到港：due 空账（实返 %s）" % JSON.stringify(r4))

	# ── 附：arrive 层同守卫（薄转 due、第三态 play/mark 也一起拦）──
	var b5 = BM.new()
	b5.init(fixture)
	var r5: Dictionary = b5.arrive("quanzhou", ["start"], [], ["quanzhou"], 1, true)
	_check(r5.is_empty(),
		"附 已终局 + 到港：arrive 空账、演出结算一并拦（实返 %s）" % JSON.stringify(r5))

	print("PORT_BEATS_PROBE rc=%d" % (1 if fails > 0 else 0))
	quit(1 if fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)
