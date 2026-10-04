extends SceneTree
## lane w64-k1 伙伴系统三件之二：CompanionPreview 浮页「上屏文案 / 钮面 / 字段」运行时探针。
##   承 w27-k1 顶匾同工——scripts/companions/CompanionPreview.gd 此前只有截图探针（qa_companion_preview_screenshots
##   判图不判字），「草案预览」戳、合上钮、六卡名签、脚注一条运行时断言都没有。
##   判的全是上屏可见物（Label.text / Button.text / 卡数量 / PREVIEW_IDS 名单），不读内部变量。
## 断言 12 案：
##   C1  F7 打开后浮页真实挂上（_companion_preview 有效）。
##   C2  「草案预览」戳上屏（DraftStamp 含「草案预览」，防戳文案被人改没了照样绿）。
##   C3  合上钮在、字恰「合上」（钮面措辞契约）。
##   C4  题签「同舟草签」在（Title）。
##   C5  卡格恰 6 张（与 PREVIEW_IDS 对齐，防名册断链静默少卡）。
##   C6  六张卡的 Name 签逐字 = PREVIEW_IDS 对应人物的 display_name（text 层回读，不选被引文件——
##       PREVIEW_IDS 与 GameManager.get_character 都是脚本接口）。
##   C7  每卡都有 Identity 或 Note 一格（剪影注；全空 = 文本层断链）。
##   C8  每卡都有「剪影」标记（SilhouetteTag，防卡片语义漂成正式招募）。
##   C9  脚注「只读示意　不入存档　非招募系统」逐字上屏（FootNote）。
##   C10 再按 F7 合上（再开再关是设计，_closing 后 is_instance_valid 转假）。
##   C11 港页（quanzhou）再开：戳、卡数仍对（换景重进不塌）。
##   C12 关浮页后重进：PrevIDs 与六人卡名签不串档（两张同名卡须是两份 node）。
##   C13 本进程 SCRIPT ERROR 即红（script_err_tally 两格）。
## 用法：godot --headless --path . -s res://tools/qa_companion_preview_probe.gd
## 末行 COMPANION_PREVIEW cases=N fails=N；fails≥1 → quit(1)。
## 反向变异自证（lane w64-k1 Verify V3）：把 C2 的判据字面「草案预览」改成「草案预览!」（界上没有这串）
##   → C2 红、末行 fails=1 ≥ 1 → rc=1；改回 → 全绿 rc=0。记 git checkout 复原的坑见 memory「突变实验中断的还原坑」。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const PREVIEW_IDS := [
	"monk_jinghai", "merchant_lin", "pilot_ana", "lin_hua", "wu_zhen", "zhou_suanchou",
]

var _main: Node
var _fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	var gm: Node = root.get_node_or_null("GameManager")
	if gm == null:
		push_error("autoload GameManager missing")
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Main.tscn missing")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("_toggle_companion_preview"):
		_expect(false, "Main 未接 _toggle_companion_preview（Z3 浮页总闸）")
		_report()
		return

	# C1–C10：标题页开合一轮
	print("── C1–C10 标题页打开：戳 / 钮面 / 卡 / 关")
	_main.call("_toggle_companion_preview")
	await _settle(8)
	var ov: Node = _main.get("_companion_preview")
	_expect(is_instance_valid(ov), "C1 F7 打开后 _companion_preview 有效")
	if is_instance_valid(ov):
		_check_sheet(ov, "标题页")
		_main.call("_toggle_companion_preview")
		await _settle(6)
		_expect(not is_instance_valid(_main.get("_companion_preview")), "C10 再按 F7 合上浮页")

	# C11：换港页再开一轮（换景后戳与卡数不塌）
	print("── C11 港页 quanzhou 再开：戳 / 卡数不塌")
	_main.load_scene("quanzhou")
	await _settle(8)
	_main.call("_toggle_companion_preview")
	await _settle(8)
	var ov2: Node = _main.get("_companion_preview")
	_expect(is_instance_valid(ov2), "C11a 港页 F7 打开后浮页有效")
	if is_instance_valid(ov2):
		var stamp2 := _find(ov2, "DraftStamp")
		_expect(stamp2 != null and "草案预览" in str(stamp2.get("text")),
			"C11b 港页戳仍含「草案预览」（实读 %s）" % ("" if stamp2 == null else str(stamp2.get("text"))))
		var grid2 := _find(ov2, "CardGrid")
		_expect(grid2 != null and grid2.get_child_count() == 6,
			"C11c 港页卡格仍恰 6 张（实得 %d）" % (-1 if grid2 == null else grid2.get_child_count()))

	# C12：合上再开一轮，和上一轮不是同一份 node（不串档）
	print("── C12 关后重开：新一份 node、卡名签不串")
	_main.call("_toggle_companion_preview")
	await _settle(6)
	_main.call("_toggle_companion_preview")
	await _settle(8)
	var ov3: Node = _main.get("_companion_preview")
	_expect(is_instance_valid(ov3) and ov3 != ov2, "C12a 关后重开是新一份 CompanionPreview node")
	if is_instance_valid(ov3):
		var names3 := _card_names(ov3)
		_expect(names3 == _card_names_expected(), "C12b 重开后六卡名签逐字仍对（实读 %s）" % str(names3))
	_main.call("_toggle_companion_preview")
	await _settle(6)

	_report()


func _settle(n := 3) -> void:
	for _i in range(n):
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what)


func _find(n: Node, nm: String) -> Node:
	return n.find_child(nm, true, false)


## C2–C9：一张浮页面上能验的九案（标题页 / 港页共用）
func _check_sheet(ov: Node, scene_name: String) -> void:
	var stamp := _find(ov, "DraftStamp")
	_expect(stamp != null and "草案预览" in str(stamp.get("text")),
		"C2 %s DraftStamp 含「草案预览」（实读 %s）" % [scene_name, "" if stamp == null else str(stamp.get("text"))])
	var close := _find(ov, "CloseButton")
	_expect(close != null and str(close.get("text")) == "合上",
		"C3 %s 合上钮存在且字恰「合上」（实读 %s）" % [scene_name, "" if close == null else str(close.get("text"))])
	var title := _find(ov, "Title")
	_expect(title != null and str(title.get("text")) == "同舟草签",
		"C4 %s Title 恰「同舟草签」（实读 %s）" % [scene_name, "" if title == null else str(title.get("text"))])
	var grid := _find(ov, "CardGrid")
	_expect(grid != null and grid.get_child_count() == 6,
		"C5 %s CardGrid 恰 6 张卡（实得 %d）" % [scene_name, -1 if grid == null else grid.get_child_count()])
	_expect(_card_names(ov) == _card_names_expected(),
		"C6 %s 六卡 Name 逐字 = PREVIEW_IDS 的 display_name（实读 %s）" % [scene_name, str(_card_names(ov))])
	var ident_ok := true
	var tag_ok := true
	if grid != null:
		for card in grid.get_children():
			var ident := _find(card, "Identity")
			var note := _find(card, "Note")
			if ident == null and note == null:
				ident_ok = false
			var tag := _find(card, "SilhouetteTag")
			if tag == null or str(tag.get("text")) != "剪影":
				tag_ok = false
	_expect(ident_ok, "C7 %s 每卡带 Identity 或 Note 签（剪影注）" % scene_name)
	_expect(tag_ok, "C8 %s 每卡 SilhouetteTag 恰「剪影」" % scene_name)
	var foot := _find(ov, "FootNote")
	_expect(foot != null and str(foot.get("text")) == "只读示意　不入存档　非招募系统",
		"C9 %s FootNote 逐字「只读示意　不入存档　非招募系统」（实读 %s）" % [scene_name, "" if foot == null else str(foot.get("text"))])


func _card_names(ov: Node) -> Array:
	var grid := _find(ov, "CardGrid")
	var out: Array = []
	if grid == null:
		return out
	for card in grid.get_children():
		var nm := _find(card, "Name")
		out.append("" if nm == null else str(nm.get("text")))
	return out


func _card_names_expected() -> Array:
	# 与 CompanionPreview._make_card 同源：Art.display_name(ch) = ch["name"]（非主角不走 player_name 支）
	var gm: Node = root.get_node_or_null("GameManager")
	var out: Array = []
	for cid in PREVIEW_IDS:
		var ch: Dictionary = gm.get_character(cid) if gm != null else {}
		out.append(str(ch.get("name", ch.get("id", ""))))
	return out


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("COMPANION_PREVIEW cases=%d fails=%d" % [cases, _fails])
	quit(1 if _fails > 0 else 0)
