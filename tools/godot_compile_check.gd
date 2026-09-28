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
	"res://tools/qa_market_panel_probe.gd",
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
	# Lane ms Main.gd 首刀拆出的工席纸条小件
	"res://scripts/ui/SlipKit.gd",
	# Lane mz Main.gd 第二刀拆出的船籍簿整页
	"res://scripts/ui/LedgerPage.gd",
	# Lane ms2 Main.gd 第三刀拆出的升章 / 了结册页
	"res://scripts/ui/ChapterSheet.gd",
	# Lane main4 Main.gd 第四刀拆出的酒馆 / 旅店页
	"res://scripts/ui/TavernPage.gd",
	# Lane main5 Main.gd 第五刀拆出的见面页
	"res://scripts/ui/NpcPage.gd",
	# Lane main6 Main.gd 第六刀拆出的航海日志册页
	"res://scripts/ui/SaveSheet.gd",
	# Lane main7 Main.gd 第七刀拆出的行会 / 贡院页
	"res://scripts/ui/GuildExamPage.gd",
	# Lane main8 Main.gd 第八刀拆出的市舶司页
	"res://scripts/ui/MaritimeOfficePage.gd",
	# Lane main9 Main.gd 第九刀拆出的住处 / 寺观页
	"res://scripts/ui/ResidencePage.gd",
	# Lane main10 Main.gd 第十刀拆出的船屋页
	"res://scripts/ui/ShipyardPage.gd",
	# Lane main11 Main.gd 第十一刀拆出的标题页 / 开场
	"res://scripts/ui/TitlePage.gd",
	# Lane main12 Main.gd 第十二刀拆出的调试钩子（F11 跳港 / F12 预览了结）
	"res://scripts/ui/DebugHooks.gd",
	# lane-c 接舷/海战 VFX
	"res://scripts/combat/CombatFx.gd", "res://scripts/combat/BoardingStage.gd", "res://scripts/combat/CombatShoreHook.gd",
	"res://scripts/combat/MeleeResolve.gd",  # lane combat05 接舷白刃结算（BoardingStage.play 演它）
	"res://scripts/combat/CombatMorale.gd",  # lane combat06 海战士气（崩坏 / 溃逃 / 降幡 / 拒接舷）
	"res://tools/art/ThemePreview.gd", "res://tools/art/build_theme.gd",
	"res://tools/art/portrait_svg/PortraitWall.gd", "res://tools/art/ShotTour.gd",
	# lane ea4 清单漂移补列：此前各 lane 各自追加、漏掉的已跟踪脚本（由下方 INVENTORY 自检兜底）
	"res://scripts/audio/AudioHooks.gd", "res://scripts/audio/SfxSynth.gd",
	"res://scripts/chart/ChartProjection.gd", "res://scripts/chart/MapView.gd", "res://scripts/chart/ShipMarker.gd",
	"res://scripts/core/BrokerSlip.gd", "res://scripts/core/DrydockBerth.gd", "res://scripts/core/HeadingDraft.gd",
	"res://scripts/core/ShoreDraft.gd", "res://scripts/core/UiTheme.gd",
	# 门禁本体与共用件
	"res://tools/godot_smoke.gd", "res://tools/godot_story_check.gd", "res://tools/p7_guild_exam_smoke.gd",
	"res://tools/patrol_shell.gd", "res://tools/shot_gate.gd", "res://tools/gate_report.gd",
	"res://tools/src_probe.gd",  # 按名认函数的源码探查（lane cs15）
	"res://tools/gen_builtin_list.gd",
	# 各 lane 专项探针 / 截图脚本
	"res://tools/save_robust_probe.gd", "res://tools/save_migrate_probe.gd",
	"res://tools/qa_economy_spread_probe.gd", "res://tools/qa_save_slot_tip_probe.gd",
	"res://tools/qa_discovery_probe.gd", "res://tools/qa_chapter_promote_probe.gd",
	"res://tools/qa_chart_hud_screenshots.gd", "res://tools/qa_p7_screenshots.gd",
	"res://tools/qa_patrol_pack_screenshots.gd",
	"res://tools/qa_fine_text_probe.gd",
	"res://tools/qa_money_notices_probe.gd",
	"res://tools/qa_contract_stock_probe.gd",
	"res://tools/qa_customs_duty_probe.gd",
	"res://tools/qa_yard_transition_probe.gd",
	"res://tools/qa_pirate_boat_probe.gd",  # 海寇快船 + 船图契约（lane pirate-boat-0928）
	"res://tools/combat_vfx_probe.gd", "res://tools/combat_wire_probe.gd", "res://tools/combat_probe_stage.gd",
	"res://tools/vision_stage_probe.gd", "res://tools/vision_letterbox_probe.gd", "res://tools/letterbox_signal_probe.gd",
	"res://tools/probe_clock.gd", "res://tools/shot_consistency.gd",
	"res://tools/art/vision_fill_gen.gd", "res://tools/art/vision_fill_shots.gd",
	"res://tools/art/tour_sheet.gd",
]

## 清单自检（lane ea4）：INVENTORY_ROOTS 下每个 git 已跟踪的 .gd 都必须在 SCRIPTS 里，或在 INVENTORY_EXEMPT 里写明理由；
## SCRIPTS 里的路径必须真实存在。任一差集非空 → bad+1（整体算一项 inventory）。
## 「已跟踪」取 `git ls-files`：别的 lane 未提交的新脚本不会让共用工作树变红；git 不可用时退回扫盘并打 NOTE。
const INVENTORY_ROOTS := ["scripts", "tools"]
const INVENTORY_SKIP_DIRS := ["tools/legacy"]
const INVENTORY_EXEMPT := {
	"tools/godot_compile_check.gd": "门禁本体：它自己编不过就根本跑不到这里，列入无增益",
}

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
	# 探针场景（-s 放不出过场的探针以场景启动）
	"res://tools/qa_yard_transition_probe.tscn",
]

## lane-z4 把 Ship/PirateShip 的炮弹场景改成 lazy load() 后，这几个弹道场景已确认无解析错误；
## 它们必须留在 SCENES 里且保持 OK，被删出清单也算一次失败。
const MUST_STAY_CLEAN := [
	"res://scenes/Cannonball.tscn",
	"res://scenes/WaterSplash.tscn",
	"res://scenes/ImpactExplosion.tscn",
]

const GateReport := preload("res://tools/gate_report.gd")  # -- --json 时只打一行 JSON（lane g2）
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
			GateReport.check(false, p, "load-null")
			bad += 1
			continue
		var ok: bool = s.can_instantiate()
		print("COMPILE_CHECK ", "OK   " if ok else "FAIL ", p)
		GateReport.check(ok, p, "" if ok else "can_instantiate=false")
		if not ok:
			bad += 1
	total += 1
	var inv_why := _check_inventory()
	if inv_why.is_empty():
		print("COMPILE_CHECK OK   inventory SCRIPTS == tracked *.gd under ", "/".join(INVENTORY_ROOTS), " (exempt ", INVENTORY_EXEMPT.size(), ")")
		GateReport.check(true, "inventory SCRIPTS == tracked *.gd under %s (exempt %d)" % ["/".join(INVENTORY_ROOTS), INVENTORY_EXEMPT.size()])
	else:
		bad += 1
		for w in inv_why:
			print("COMPILE_CHECK FAIL inventory ", w)
			GateReport.check(false, "inventory " + w)
	for gp in MUST_STAY_CLEAN:
		if not SCENES.has(gp):
			total += 1
			bad += 1
			print("COMPILE_CHECK FAIL guard-unlisted ", gp)
			GateReport.check(false, gp, "guard-unlisted")
	var scenes: Array = SCENES.duplicate()
	for extra in _discover_scenes(SCENE_ROOT):
		if not scenes.has(extra):
			print("COMPILE_CHECK NOTE unlisted scene, checking anyway ", extra)
			GateReport.warn(extra, "unlisted scene, checking anyway")
			scenes.append(extra)
	for sp in scenes:
		total += 1
		var why := _check_scene(sp)
		if why.is_empty():
			print("COMPILE_CHECK OK   ", sp)
			GateReport.check(true, sp)
		else:
			bad += 1
			var tag := "FAIL guard " if MUST_STAY_CLEAN.has(sp) else "FAIL "
			print("COMPILE_CHECK ", tag, sp, " :: ", "; ".join(why))
			GateReport.check(false, sp, ("guard：" if MUST_STAY_CLEAN.has(sp) else "") + "; ".join(why))
	print("COMPILE_CHECK SUMMARY bad=", bad, "/", total)
	GateReport.finish("godot_compile_check", 1 if bad > 0 else 0, "COMPILE_CHECK SUMMARY bad=%d/%d" % [bad, total])
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


## 返回差集条目；空 = 清单与已跟踪脚本对齐。
func _check_inventory() -> PackedStringArray:
	var why := PackedStringArray()
	var listed := {}
	for p in SCRIPTS:
		var rel: String = p.trim_prefix("res://")
		if listed.has(rel):
			why.append("dup %s" % p)
		listed[rel] = true
		if not FileAccess.file_exists(p):
			why.append("listed-missing %s" % p)
	var tracked := _tracked_gd()
	for rel in tracked:
		if listed.has(rel):
			if INVENTORY_EXEMPT.has(rel):
				why.append("exempt-but-listed res://%s" % rel)
		elif not INVENTORY_EXEMPT.has(rel):
			why.append("unlisted res://%s" % rel)
	for rel in INVENTORY_EXEMPT:
		if not tracked.has(rel):
			why.append("exempt-stale res://%s" % rel)
	return why


func _tracked_gd() -> Array:
	var out: Array = []
	var root_abs := ProjectSettings.globalize_path("res://")
	# 不用 -z：OS.execute 把输出转成 String 时会在 NUL 处截断；改关 quotepath 按行切。
	var args := PackedStringArray(["-C", root_abs, "-c", "core.quotepath=off", "ls-files", "--"])
	for r in INVENTORY_ROOTS:
		args.append("%s/*.gd" % r)
	var stdout: Array = []
	var rc := OS.execute("git", args, stdout, true)
	if rc == 0 and not stdout.is_empty():
		for rel in String(stdout[0]).split("\n", false):
			if not _inventory_skipped(rel):
				out.append(rel)
	else:
		print("COMPILE_CHECK NOTE inventory git ls-files unavailable (rc=", rc, "), falling back to disk scan")
		GateReport.warn("inventory git ls-files unavailable (rc=%d), falling back to disk scan" % rc)
		for r in INVENTORY_ROOTS:
			out.append_array(_disk_gd(r))
	out.sort()
	return out


func _disk_gd(rel_dir: String) -> Array:
	var out: Array = []
	if _inventory_skipped(rel_dir + "/"):
		return out
	var d := DirAccess.open("res://" + rel_dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(rel_dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_disk_gd(rel_dir.path_join(sub)))
	return out


func _inventory_skipped(rel: String) -> bool:
	for sd in INVENTORY_SKIP_DIRS:
		if rel.begins_with(sd + "/"):
			return true
	return false
