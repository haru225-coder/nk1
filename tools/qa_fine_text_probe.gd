extends SceneTree
## Lane ae：headless 探针——罚金文案 = 实扣。
## GameState.customs_inspection（有引查扣 / 无引严查）、SeaChart._on_requisition_flee（抗征被追上）、
## SeaChart._on_patrol_submit（哨船起获违禁）四处罚金都经 add_money(-fine) 夹 0；
## 现银低于罚金下限时，日志印的「罚钱 N」必须等于实际扣掉的钱（先夹现银、再写日志、再扣）。
## 每处两例：现银 20（低于下限 50/80/60）与现银 2000（罚金不受夹，数值须与原公式一致）。
## 用法：godot --headless --path . -s res://tools/qa_fine_text_probe.gd
## 输出末行 AE_PROBE fails=N；N>0 时 exit 1。-s 勿用 autoload 标识符。

const CHART_SCENE := "res://scenes/SeaChart.tscn"

var gs: Node
var gm: Node
var fleet: Node
var fails := 0
var _re := RegEx.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	fleet = root.get_node_or_null("Fleet")
	if gs == null or gm == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	_re.compile("罚钱 (\\d+)")
	gs.last_port = "quanzhou"
	var cgid := _contraband_gid()
	if cgid == "":
		_fail("goods.json 里找不到违禁货")
		print("AE_PROBE fails=%d" % fails)
		quit(1)
		return

	for m in [20, 2000]:
		_customs_permit(cgid, m)
		_customs_no_permit(cgid, m)

	var chart: Node = (load(CHART_SCENE) as PackedScene).instantiate()
	root.add_child(chart)
	for _i in 4:
		await process_frame
	# 不在航：_on_event_continue → _sail_next_day 立即返回，不再推日、抽事、扣别的钱
	chart.set("sailing", false)
	chart.set("remaining_li", 1000.0)
	for m in [20, 2000]:
		_flee(chart, m)
		_patrol(chart, cgid, m)
	chart.queue_free()

	print("AE_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _contraband_gid() -> String:
	for g in gm.goods_data.get("goods", []):
		if g.get("contraband", false):
			return str(g.get("id", ""))
	return ""


func _load_contraband(gid: String) -> void:
	fleet.clear_cargo()
	fleet.add_cargo(gid, 3, 10.0)


func _fail(msg: String) -> void:
	fails += 1
	print("  ✗ " + msg)


## 文案里的罚金 vs 实扣；expect_fine >= 0 时再核数值（现银充足时不得改动原公式）
func _check(tag: String, text: String, before: int, after: int, expect_fine: int) -> void:
	var m := _re.search(text)
	if m == null:
		_fail("%s：文案里没有「罚钱 N」：%s" % [tag, text.left(80)])
		return
	var shown := int(m.get_string(1))
	var taken := before - after
	var ok := shown == taken and (expect_fine < 0 or shown == expect_fine)
	print("  %s %s：现银 %d→%d，文案「罚钱 %d」，实扣 %d%s" % [
		"✓" if ok else "✗", tag, before, after, shown, taken,
		"" if expect_fine < 0 else "，原公式 %d" % expect_fine])
	if not ok:
		fails += 1


func _seed_where(pred: Callable) -> int:
	for s in range(1, 5000):
		seed(s)
		if pred.call(randf()):
			return s
	return -1


func _customs_permit(gid: String, money: int) -> void:
	_load_contraband(gid)
	gs.has_customs_permit = true
	gs.pu_attention = 400
	var risk: float = (0.25 + float(gs.pu_attention) / 400.0) * float(root.get_node("Economy").inspection_factor(gs.last_port))
	var s := _seed_where(func(r): return r < risk)
	gs.money = money
	seed(s)
	var res: Dictionary = gs.customs_inspection()
	if not res.get("confiscated", false):
		_fail("有引查扣：未走到查扣分支（seed %d）" % s)
		return
	_check("有引查扣", str(res.get("msg", "")), money, int(gs.money), -1 if money < 50 else mini(300, maxi(50, int(money * 0.4))))


func _customs_no_permit(gid: String, money: int) -> void:
	_load_contraband(gid)
	gs.has_customs_permit = false
	gs.pu_attention = 400
	gs.money = money
	var res: Dictionary = gs.customs_inspection()
	if not res.get("confiscated", false):
		_fail("无引严查：未走到查扣分支")
		return
	_check("无引严查", str(res.get("msg", "")), money, int(gs.money), -1 if money < 50 else mini(500, maxi(50, int(money * 0.4))))


func _latest_log(chart: Node) -> String:
	var label: Node = chart.get("log_label")
	return str(label.get("text")).split("\n\n")[0]


func _flee(chart: Node, money: int) -> void:
	fleet.clear_cargo()
	var chance := clampf(fleet.fleet_speed() / 240.0, 0.2, 0.85)
	var s := _seed_where(func(r): return r >= chance)
	gs.money = money
	seed(s)
	chart.call("_on_requisition_flee")
	_check("抗征被追", _latest_log(chart), money, int(gs.money), -1 if money < 80 else maxi(80, int(money * 0.25)))


func _patrol(chart: Node, gid: String, money: int) -> void:
	_load_contraband(gid)
	gs.money = money
	chart.call("_on_patrol_submit")
	_check("哨船起获", _latest_log(chart), money, int(gs.money), -1 if money < 60 else mini(400, maxi(60, int(money * 0.2))))
