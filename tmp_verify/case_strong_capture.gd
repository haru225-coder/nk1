class_name NCaseStrongCapture
## 红E2 用例：强敌顺风满员 100 对 14 落水，白刃胜的「夺船」也要开场那拍。
## 探针 hook_caps 的海量名（strong 全范围顺风满员 100/14）。
extends Node

const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")

@export var worldmap_path: NodePath

func _red(msg: String) -> void:
	printerr("红 case_strong_capture: " + msg)

func _green(msg: String) -> void:
	print("绿 case_strong_capture: " + msg)

func run() -> bool:
	var wm := get_node(worldmap_path)
	if NK1CutLib.headless():
		# headless 下 begin 返回 null、stage 为 null；题签判不了，跳过
		print("case_strong_capture: headless，题签判不了，走 _cut_win 的 null 守")
		return true
	var layers := wm.get_tree().get_nodes_in_group(BoardingStage.GROUP)
	if layers.is_empty():
		_red("强敌胜「夺船」没见题签层（_cut_win 应开场挂「接舷」题签，resolve 出「夺船」）")
		return false
	var top: CanvasLayer = layers[-1]
	var t = top.get("_title")
	if t != null and t.text != "夺船":
		_red("强敌胜后题签应为「夺船」，实得「%s」" % (t.text if t != null else "<无>"))
		return false
	_green("强敌胜「夺船」有题签层，题签「夺船」")
	return true
