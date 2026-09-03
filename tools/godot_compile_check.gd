## Godot 引擎内编译门禁（2026-09-03 P0.5 引入）
## 用法：<godot 4.6.3> --headless --path <项目根> -s tools/godot_compile_check.gd
## 逐个 load() scripts/ 下全部 18 个脚本并检查 can_instantiate()；任一失败则 quit(1)。
## 为什么不用 --check-only：它不实例化 autoload，会把 GameManager/Fleet 等引用误报成
## 「Identifier not found」，而且它的退出码在有 SCRIPT ERROR 时仍为 0（4.6.3 实测）。
## 本脚本 extends SceneTree，Godot 会先挂好 project.godot 里的 autoload 再进 _initialize()。
extends SceneTree

const SCRIPTS := [
	"res://scripts/Cannonball.gd", "res://scripts/Crate.gd", "res://scripts/FloatingText.gd",
	"res://scripts/GameManager.gd", "res://scripts/GameState.gd", "res://scripts/Main.gd",
	"res://scripts/Minimap.gd", "res://scripts/PirateShip.gd", "res://scripts/PortZone.gd",
	"res://scripts/SeaChart.gd", "res://scripts/Ship.gd", "res://scripts/WorldMap.gd",
	"res://scripts/core/Calendar.gd", "res://scripts/core/Crew.gd", "res://scripts/core/Economy.gd",
	"res://scripts/core/Fleet.gd", "res://scripts/core/SaveLoad.gd", "res://scripts/core/Voyage.gd",
]

func _initialize() -> void:
	print("COMPILE_CHECK autoload GameManager present: ", root.get_node_or_null("GameManager") != null)
	var bad := 0
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
	print("COMPILE_CHECK SUMMARY bad=", bad, "/", SCRIPTS.size())
	quit(1 if bad > 0 else 0)
