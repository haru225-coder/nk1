## Godot 引擎内编译门禁（2026-09-03 P0.5 引入）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_compile_check.gd
## 逐个 load() 下列 SCRIPTS（scripts/ 主干 + 视觉集成线新增）并检查 can_instantiate()；任一失败则 quit(1)。
## 为什么不用 --check-only：它不实例化 autoload，会把 GameManager/Fleet 等引用误报成
## 「Identifier not found」，而且它的退出码在有 SCRIPT ERROR 时仍为 0（4.6.3 实测）。
## 本脚本 extends SceneTree，Godot 会先挂好 project.godot 里的 autoload 再进 _initialize()。
extends SceneTree

const SCRIPTS := [
	"res://scripts/Cannonball.gd", "res://scripts/FloatingText.gd",
	"res://scripts/GameManager.gd", "res://scripts/GameState.gd", "res://scripts/Main.gd",
	"res://scripts/Minimap.gd", "res://scripts/PirateShip.gd", "res://scripts/PortZone.gd",
	"res://scripts/SeaChart.gd", "res://scripts/Ship.gd", "res://scripts/WorldMap.gd",
	"res://scripts/core/Calendar.gd", "res://scripts/core/Crew.gd", "res://scripts/core/Economy.gd",
	"res://scripts/core/Fleet.gd", "res://scripts/core/SaveLoad.gd", "res://scripts/core/Voyage.gd",
	# 视觉集成线（art/cloud-visual）新增：过场引擎、主题/立绘工具、巡检截帧
	"res://scripts/cutscene/CutscenePlayer.gd", "res://scripts/cutscene/ChapterCard.gd",
	"res://scripts/cutscene/PortBanner.gd", "res://scripts/cutscene/LivingBackdrop.gd",
	"res://scripts/cutscene/CutscenePreview.gd", "res://scripts/cutscene/cs_kit.gd",
	"res://scripts/cutscene/cs_ink_text.gd", "res://scripts/cutscene/cs_seal.gd",
	"res://scripts/cutscene/cs_fx.gd",
	# cinematics 线：过场接线的会话开关与标题演出
	"res://scripts/cutscene/Cinematics.gd", "res://scripts/cutscene/TitleStage.gd",
	# characters 线：人物系统的画与小件、人物志浮页
	"res://scripts/ui/CharacterArt.gd", "res://scripts/ui/CharacterCodex.gd",
	# chars 线（人物呈现竖切）：场景 scripts/chars/ + 巡检工具
	"res://scripts/chars/CharStage3D.gd", "res://scripts/chars/CharPortraitPanel.gd",
	"res://scripts/chars/CharRoster.gd", "res://scripts/chars/CharsDemo.gd",
	"res://scripts/chars/CharsShoreOverlay.gd", "res://tools/qa_chars_wire_screenshots.gd",
	"res://tools/qa_chars_screenshots.gd",
	# 工席成功态过渡（淡入墨幕 + 题签）
	"res://scripts/ui/UiTransition.gd", "res://tools/qa_title_probe.gd", "res://tools/qa_siege_endgame_probe.gd", "res://tools/qa_ending_reread_probe.gd",
	"res://tools/qa_drydock_probe.gd",
	"res://tools/qa_voyage_status_probe.gd",
	"res://tools/qa_port_doors_probe.gd",
	"res://tools/qa_crew_hire_probe.gd",
	# Lane Z3 伙伴草案预览浮页
	"res://scripts/companions/CompanionPreview.gd", "res://tools/qa_companion_preview_screenshots.gd",
	# Lane A 观感展示台（独立场景）
	"res://scripts/ui/VisionStage.gd", "res://tools/qa_wire_vision_screenshots.gd",
	"res://scripts/ui/CombatLetterbox.gd", "res://tools/qa_letterbox_copy_probe.gd",
	# Lane G/Q 酒馆设施纸笺与新闻墙
	"res://scripts/ui/TavernFacilitySlip.gd", "res://scripts/ui/TavernFacilityPreview.gd",
	"res://scripts/ui/TavernNewsWall.gd", "res://tools/qa_tavern_news_wall_screenshots.gd",
	# lane-c 接舷/海战 VFX
	"res://scripts/combat/CombatFx.gd", "res://scripts/combat/BoardingStage.gd", "res://scripts/combat/CombatShoreHook.gd",
	"res://tools/art/ThemePreview.gd", "res://tools/art/build_theme.gd",
	"res://tools/art/portrait_svg/PortraitWall.gd", "res://tools/art/ShotTour.gd",
]

## 关键场景：脚本门禁通过后仍可能因 ext_resource 解析失败而坏档（ASTRA_AUDIT M2）。
## 4.6.3 实测：ext_resource 指向不存在的文件时 load() 仍返回 PackedScene、instantiate() 也成功，
## 只往 stderr 打一行 Parse Error——所以这里逐条核对 [ext_resource]，把解析错误算进 bad。
## 显式清单：主干 + 一切战斗/弹道场景；scenes/ 下未列入的（scenes/vision/ 除外，另有 lane 维护）也会被补查。
const SCENES := [
	"res://scenes/Main.tscn",
	"res://scenes/WorldMap.tscn",
	"res://scenes/SeaChart.tscn",
	"res://scenes/PortZone.tscn",
	"res://scenes/FloatingText.tscn",
	# 战斗 / 弹道
	"res://scenes/Ship.tscn",
	"res://scenes/PirateShip.tscn",
	"res://scenes/Cannonball.tscn",
	"res://scenes/WaterSplash.tscn",
	"res://scenes/ImpactExplosion.tscn",
	"res://scenes/combat/BoardingStage.tscn",
	# 人物 / 过场 / 酒馆
	"res://scenes/chars/CharsDemo.tscn",
	"res://scenes/chars/CharsShoreOverlay.tscn",
	"res://scenes/cutscene/CutscenePreview.tscn",
	"res://scenes/ui/TavernFacilityPreview.tscn",
	"res://scenes/ui/TavernFacilitySlip.tscn",
]

## lane-z4 把 Ship/PirateShip 的炮弹场景改成 lazy load() 后，这几个弹道场景已确认无解析错误；
## 它们必须留在 SCENES 里且保持 OK，被删出清单也算一次失败。
const MUST_STAY_CLEAN := [
	"res://scenes/Cannonball.tscn",
	"res://scenes/WaterSplash.tscn",
	"res://scenes/ImpactExplosion.tscn",
]

const SCENE_ROOT := "res://scenes"
const SCENE_SKIP_DIRS := ["res://scenes/vision"]


func _initialize() -> void:
	print("COMPILE_CHECK autoload GameManager present: ", root.get_node_or_null("GameManager") != null)
	var bad := 0
	var total := 0
	for p in SCRIPTS:
		total += 1
		var s = load(p)
		if s == null:
			print("COMPILE_CHECK FAIL load-null ", p)
			bad += 1
			continue
		var ok: bool = s.can_instantiate()
		print("COMPILE_CHECK ", "OK   " if ok else "FAIL ", p)
		if not ok:
			bad += 1
	for gp in MUST_STAY_CLEAN:
		if not SCENES.has(gp):
			total += 1
			bad += 1
			print("COMPILE_CHECK FAIL guard-unlisted ", gp)
	var scenes: Array = SCENES.duplicate()
	for extra in _discover_scenes(SCENE_ROOT):
		if not scenes.has(extra):
			print("COMPILE_CHECK NOTE unlisted scene, checking anyway ", extra)
			scenes.append(extra)
	for sp in scenes:
		total += 1
		var why := _check_scene(sp)
		if why.is_empty():
			print("COMPILE_CHECK OK   ", sp)
		else:
			bad += 1
			var tag := "FAIL guard " if MUST_STAY_CLEAN.has(sp) else "FAIL "
			print("COMPILE_CHECK ", tag, sp, " :: ", "; ".join(why))
	print("COMPILE_CHECK SUMMARY bad=", bad, "/", total)
	quit(1 if bad > 0 else 0)


## 返回失败原因列表；空 = 场景可解析、依赖齐全、可实例化。一个场景只计一次失败。
func _check_scene(sp: String) -> PackedStringArray:
	var why := PackedStringArray()
	if not FileAccess.file_exists(sp):
		why.append("scene-missing")
		return why
	var text := FileAccess.get_file_as_string(sp)
	if text.is_empty():
		why.append("scene-empty")
		return why
	# 先核 [ext_resource]：path 必须存在且能 load；脚本还须能实例化。在 load(场景) 之前做，免得坏依赖被静默吞掉。
	var attr_re := RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
	var ids := {}
	for line in text.replace("\r", "").split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var attrs := {}
		for a in attr_re.search_all(line):
			attrs[a.get_string(1)] = a.get_string(2)
		var dep: String = attrs.get("path", "")
		var id: String = attrs.get("id", "")
		if id != "":
			ids[id] = true
		if dep == "":
			var uid: String = attrs.get("uid", "")
			var uid_id := ResourceUID.text_to_id(uid) if uid != "" else ResourceUID.INVALID_ID
			if uid_id == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid_id):
				why.append("ext-unresolved id=%s" % id)
				continue
			dep = ResourceUID.get_id_path(uid_id)
		if not ResourceLoader.exists(dep):
			why.append("ext-missing %s" % dep)
			continue
		var r = load(dep)
		if r == null:
			why.append("ext-load-null %s" % dep)
		elif r is Script and not r.can_instantiate():
			why.append("ext-script-broken %s" % dep)
	# 正文里 ExtResource("x") 引用了未声明的 id，同样是 Parse Error。
	var ref_re := RegEx.create_from_string("ExtResource\\(\\s*\"([^\"]+)\"\\s*\\)")
	for m in ref_re.search_all(text):
		if not ids.has(m.get_string(1)):
			why.append("ext-undeclared id=%s" % m.get_string(1))
	if not why.is_empty():
		return why
	var packed = load(sp)
	if packed == null or not (packed is PackedScene):
		why.append("scene-load")
		return why
	if not packed.can_instantiate():
		why.append("scene-cant")
		return why
	var node = packed.instantiate()
	if node == null:
		why.append("scene-inst")
		return why
	node.free()
	return why


func _discover_scenes(dir_path: String) -> Array:
	var out: Array = []
	if SCENE_SKIP_DIRS.has(dir_path):
		return out
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_discover_scenes(dir_path.path_join(sub)))
	out.sort()
	return out
