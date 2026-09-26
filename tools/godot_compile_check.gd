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

## 关键场景：脚本门禁通过后仍可能因 ext_resource 解析失败而坏档。
const SCENES := [
	"res://scenes/Main.tscn",
	"res://scenes/WorldMap.tscn",
	"res://scenes/Cannonball.tscn",
]


func _initialize() -> void:
	print("COMPILE_CHECK autoload GameManager present: ", root.get_node_or_null("GameManager") != null)
	var bad := 0
	var total := SCRIPTS.size() + SCENES.size()
	for p in SCRIPTS:
		var s = load(p)
		if s == null:
			print("COMPILE_CHECK FAIL load-null ", p)
			bad += 1
			continue
		var ok: bool = s.can_instantiate()
		print("COMPILE_CHECK ", "OK   " if ok else "FAIL ", p)
		if not ok:
			bad += 1
	for sp in SCENES:
		# 场景解析错误时 load 可能仍返回 PackedScene；再 instantiate 抓坏挂接。
		var packed = load(sp)
		if packed == null or not (packed is PackedScene):
			print("COMPILE_CHECK FAIL scene-load ", sp)
			bad += 1
			continue
		if not packed.can_instantiate():
			print("COMPILE_CHECK FAIL scene-cant ", sp)
			bad += 1
			continue
		var node = packed.instantiate()
		if node == null:
			print("COMPILE_CHECK FAIL scene-inst ", sp)
			bad += 1
			continue
		print("COMPILE_CHECK OK   ", sp)
		node.free()
	print("COMPILE_CHECK SUMMARY bad=", bad, "/", total)
	quit(1 if bad > 0 else 0)
