## 岸上薄钩子：供 Main 调试键或探针叠一层接舷题签，不改玩法、不入存档。
## 真实接舷路径仍是 SeaChart 遇盗 → WorldMap 近敌按 G。
extends RefCounted

const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")


## 在 parent（通常 Main）上播「接舷→夺船」两拍题签。headless 返回 false。
static func preview_boarding(parent: Node, win := true) -> bool:
	if parent == null or not parent.is_inside_tree() or Kit.is_headless():
		return false
	var st: CanvasLayer = BoardingStage.begin(parent, null, null, CombatFx.board_begin_subtitle())
	if st == null:
		return false
	# 短停后再结算题签，便于截 wire 帧
	var tree := parent.get_tree()
	if tree == null:
		return true
	var t := tree.create_timer(0.55, true, false, true)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(parent):
			return
		var detail := CombatFx.board_win_note("海鹘") if win else CombatFx.board_lose_note(3)
		BoardingStage.resolve(parent, "win" if win else "lose", detail)
		CombatFx.hitstop(parent, 0.07, 0.22)
	)
	return true
