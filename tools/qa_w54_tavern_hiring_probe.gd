extends SceneTree
## lane w54-tavern：酒馆募人题签只说实话。
##   F 「已雇之职不再列名。」：本港眼下无人可雇时，那一句修前只看船上雇没雇人——澎湖、萨摩、占城本无候雇之人
##     （crew.json 里没有一个候选在这三港），船上雇着谁，三港酒馆都写「本港眼下无人可雇　已雇之职不再列名。」，
##     像是本港有人、因职事已满被藏了起来。现只在本港真有此刻候雇、因那一职已有人而不列名的人时写（Crew.held_back_at）。
##     a 三港各雇着一人：题签照写「本港眼下无人可雇」，不写「已雇之职不再列名。」；没雇人时同样不写。
##     b 照写的两处守住：泉州第一章本港五职都雇齐（林华第二章才候雇）、博多第二章通事位上已有人（近藤三郎因职事已满不列名，
##       净海记名沙弥没走寺社引荐本就不候雇）——两处都写「已雇之职不再列名。」，不列名的人数与名册对得上。
## 用法：godot --headless --path . -s res://tools/qa_w54_tavern_hiring_probe.gd（经门锁跑）
## 末行 W54_TAVERN_HIRING cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const NOTE := "已雇之职不再列名。"
const EMPTY := "本港眼下无人可雇"
## 泉州第一章候雇的五职（林华第二章起才候雇）
const QZ_CH1 := ["wu_zhen", "wang_zhiku", "huang_zhangfang", "pu_alie", "monk_puji"]

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _crew: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_crew = root.get_node_or_null("Crew")
	if _gs == null or _cal == null or _crew == null:
		_expect(false, "autoload GameState / Calendar / Crew 都在")
		_report()
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_no_candidates_here()
	await _b_note_kept()
	_report()


func _stage(year: int, chapter: int, port: String) -> void:
	_gs.from_dict({})
	_crew.from_dict({})
	_gs.chapter = chapter
	_gs.last_port = port
	_cal.from_dict({"year": year, "month": 5, "day": 10})
	_gs.money = 50000


# ── a 本无候雇之人的港 ──

func _a_no_candidates_here() -> void:
	print("── a 澎湖 / 萨摩 / 占城本无候雇之人：雇着人也不写「已雇之职不再列名。」")
	for spec in [["penghu", 1258, 1], ["kagoshima", 1268, 3], ["champa", 1272, 4]]:
		var pid := str(spec[0])
		var listed := 0
		for c in root.get_node("GameManager").crew_data.get("candidates", []):
			if str(c.get("port", "")) == pid:
				listed += 1
		_stage(int(spec[1]), int(spec[2]), pid)
		await _goto(pid + "_tavern")
		var bare := _has(EMPTY) and not _has(NOTE)
		_crew.call("hire", "wu_zhen")
		await _goto(pid + "_tavern")
		_expect(listed == 0 and bare and _has(EMPTY) and not _has(NOTE) and _has("吴针") and _has("在船"),
			"%s（名册候选 %d 人）：雇着吴针时题签「%s」照写、不写「%s」；没雇人时同样（实读 %s）" % [
				pid, listed, EMPTY, NOTE, _hiring_texts()])


# ── b 真有人因职事已满不列名：照写 ──

func _b_note_kept() -> void:
	print("── b 真有人因职事已满不列名：照写「已雇之职不再列名。」")
	_stage(1258, 1, "quanzhou")
	for cid in QZ_CH1:
		_crew.call("hire", cid)
	await _goto("quanzhou_tavern")
	_expect((_crew.hired as Dictionary).size() == 5 and _has(EMPTY) and _has(NOTE) and int(_crew.call("held_back_at", "quanzhou")) == 5,
		"泉州第一章五职雇齐：「%s」「%s」都在，不列名 %d 人（应 5）" % [EMPTY, NOTE, int(_crew.call("held_back_at", "quanzhou"))])
	_stage(1262, 2, "hakata")
	_crew.call("hire", "pu_alie")
	await _goto("hakata_tavern")
	_expect(_has(EMPTY) and _has(NOTE) and not _has("近藤三郎") and not _has("净海记名沙弥")
		and int(_crew.call("held_back_at", "hakata")) == 1,
		"博多第二章通事位上是蒲阿烈：「%s」「%s」都在，不列名 %d 人（应 1：近藤三郎；记名沙弥没走寺社引荐不算）" % [
			EMPTY, NOTE, int(_crew.call("held_back_at", "hakata"))])
	_crew.from_dict({})


func _goto(scene_id: String) -> void:
	_main.call("load_scene", scene_id)
	for i in 6:
		await process_frame


func _has(t: String) -> bool:
	return _find(_main, func(n: Node) -> bool: return n is Label and (n as Label).is_visible_in_tree() and str((n as Label).text) == t) != null


## 募人那一截上屏的字（从「募人」题签起到页尾），断言失败时印出来看
func _hiring_texts() -> Array:
	var out: Array = []
	_collect(_main, out)
	var at := out.find("募人")
	return out.slice(at) if at >= 0 else out


func _collect(n: Node, out: Array) -> void:
	if n == null or n.is_queued_for_deletion():
		return
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and str((n as Label).text) != "":
		out.append(str((n as Label).text))
	for c in n.get_children():
		_collect(c, out)


func _find(n: Node, pred: Callable) -> Node:
	if n == null or n.is_queued_for_deletion():
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_TAVERN_HIRING cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
