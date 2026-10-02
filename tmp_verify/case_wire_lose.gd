class_name NCaseWireLose
## 红E1 附加接线用例：战报失利条「脱钩」也要开场那拍。
## _cut_lose 之后「脱钩」题签应在场上。headless 下 begin 返回 null；只在有窗口时判。
extends Node

const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")

@export var worldmap_path: NodePath
@export var enemy_path: NodePath

func _red(msg: String) -> void:
	printerr("红 case_wire_lose: " + msg)

func _green(msg: String) -> void:
	print("绿 case_wire_lose: " + msg)

func _check(title: String) -> bool:
	var wm := get_node(worldmap_path)
	var was_headless := NK1CutLib.headless()
	if not was_headless:
		var layers := wm.get_tree().get_nodes_in_group(BoardingStage.GROUP)
		if layers.is_empty():
			_red("战报失利条「脱钩」没见题签层（应接 _cut_lose，begin 挂「接舷」→ resolve 出「脱钩」）")
			return false
		var top: CanvasLayer = layers[-1]
		var t = top.get("_title")
		if t != null and t.text != title:
			_red("失利后题签应为「脱钩」，实得「%s」" % t.text)
			return false
	_green("失利条「脱钩」有题签层，题签「%s」" % title)
	return true

## await 到首个「round」拍位的字数上屏。`_cut_lose` 必须在它之前安排开场（不等 resolve）。
func run() -> bool:
	return _check("脱钩")
