extends SceneTree
## 战果契约探针（lane w23-a10）：CombatDirector.OUTCOMES / STORY_KEYS 的两条读点钉成一件可独立跑的事。
## 判据同 combat_realism_probe 六节的 story.outcome.*（那支探针未入册，见 GATES §一「不算门禁」表末行）——
##   本件出「单跑即红绿」这一面，并自带末梢自检：内存里清空两表喂同一条判路，必须恰好红在「接线在册」，
##   另一支「键注不合式」变体须恰好红在「战果契约在册」——本探针哪天被改成永远绿 / 永远红，这里先红
##   （GATES §五.3 口径，内存变体不落盘）。
## 用法：godot --headless --path . -s res://tools/combat_outcomes_probe.gd
## 判词：COMBAT_OUTCOMES_PROBE PASS / FAIL k …；契约全文见 docs/combat_realism_verify.md §五；
## 反向自证（临时摘掉 Director 两常量 → 编译即红 + 本探针红）登记在 docs/工程遗留收束_2026-10-03.md 第 2 件。

const Director := preload("res://scripts/combat/CombatDirector.gd")
const TAG := "COMBAT_OUTCOMES_PROBE"

var _fails: Array = []


func _initialize() -> void:
	_末梢自检()
	_judge(Director.OUTCOMES.duplicate(), (Director.STORY_KEYS as Dictionary).duplicate(), true)
	if _fails.is_empty():
		print("%s PASS（3 条全绿：末梢自检 + 接线在 + 契约齐）" % TAG)
		quit(0)
		return  # quit() 只在本帧末退出、不中断本函数：不 return 会接着打「FAIL 0」再 quit(1)，全绿也退 1（lane w53-2）
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + f)
	quit(1)


## 末梢自检：空两表恰红「接线在册」一条；键注不合式恰红「战果契约在册」一条——判路空转或走样这里先报
func _末梢自检() -> void:
	var empty_bad := _judge([], {})
	var fmt_bad := _judge(["win", "lose", "flee"], {"boarded": "不合式", "sunk": "lose：b", "flee_ok": "flee：c"})
	if empty_bad == ["接线在册"] and fmt_bad == ["战果契约在册"]:
		_emit(true, "末梢自检", "空两表恰红「接线在册」、键注不合式恰红「战果契约在册」各一条")
	else:
		_emit(false, "末梢自检", "变体须分别恰红「接线在册」/「战果契约在册」各一条",
			"空表得 %s；不合式得 %s" % [empty_bad, fmt_bad])


## 同一本账喂两侧：report=false 时只回红类名（自检对账），true 时打印并入 _fails（真表）
func _judge(outcomes: Array, keys: Dictionary, report := false) -> Array:
	var detached: Array = []
	var rest: Array = []
	if outcomes.is_empty() and keys.is_empty():
		detached.append("OUTCOMES 0 员、STORY_KEYS 0 枚（读不到 Director 两表，常量被删回死码）")
		if not report:
			return ["接线在册"]  # 空表只红接线一条，契约那条不再叠红（同 realism_probe 口径）
		_emit(false, "接线在册", detached[0])
		return detached
	var bad: Array = []
	var missing: Array = []
	for o in ["win", "lose", "flee"]:
		if not (o in outcomes):
			missing.append(o)
	if not missing.is_empty():
		bad.append("outcome 漏 %s（WorldMap / 探针发过的收法）" % [missing])
	var extra: Array = []
	for o in outcomes:
		if not (o in ["win", "lose", "flee"]):
			extra.append(o)
	if not extra.is_empty():
		bad.append("outcome 多出 %s（谁发的？）" % [extra])
	var want_keys := {}
	if "win" in outcomes:
		want_keys["boarded"] = "win"
	if "lose" in outcomes:
		want_keys["sunk"] = "lose"
	if "flee" in outcomes:
		want_keys["flee_ok"] = "flee"
	var lack: Array = []
	for k in want_keys:
		if not keys.has(k):
			lack.append(k)
	if not lack.is_empty():
		bad.append("剧情键漏 %s（海图回写与探针认的）" % [lack])
	var odd: Array = []
	for k in keys:
		if not want_keys.has(k):
			odd.append(k)
	if not odd.is_empty():
		bad.append("剧情键多出 %s（没人发也没人认）" % [odd])
	var vague: Array = []
	for k in keys:
		if not (k in odd):
			var note := str(keys[k]).strip_edges()
			if note == "" or not note.begins_with(str(want_keys[k]) + "："):
				vague.append(k)
	if not vague.is_empty():
		bad.append("键注 %s 空了或没按「结局：」写" % [vague])
	if not report:
		return [] if bad.is_empty() else ["战果契约在册"]
	_emit(true, "接线在册", "OUTCOMES %d 员、STORY_KEYS %d 枚" % [outcomes.size(), keys.size()])
	if bad.is_empty():
		_emit(true, "战果契约在册", "outcome %d 员齐、剧情键 %d 枚恰好（%s）" % [
			outcomes.size(), keys.size(), ", ".join(keys.keys())])
		return []
	_emit(false, "战果契约在册", "; ".join(bad))
	return bad


func _emit(ok: bool, key: String, name: String, detail := "") -> void:
	print("%s %s %s%s" % ["✓" if ok else "✗", key, name, "" if detail == "" else " —— " + detail])
	if not ok:
		_fails.append("%s：%s" % [key, name])
