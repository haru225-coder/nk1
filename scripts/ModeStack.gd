class_name ModeStack extends RefCounted

## ═══════════════════════════════════════════════════════════
## ModeStack — 模式栈导航（P8 首刀）
## ═══════════════════════════════════════════════════════════
## 统一查找 AppRoot 宿主，提供 go_voyage / go_narrative / start_combat。
## 无宿主时返回 false/null，调用方回退 change_scene 或本地挂载。
## ═══════════════════════════════════════════════════════════

const MODE_NARRATIVE := "narrative"
const MODE_VOYAGE := "voyage"
const MODE_COMBAT := "combat"
const MODE_CUTSCENE := "cutscene"


static func find_host(tree: SceneTree = null) -> Node:
	var st := tree
	if st == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			st = loop as SceneTree
	if st == null:
		return null
	var current := st.current_scene
	if current != null and _is_host(current):
		return current
	var root := st.root
	if root == null:
		return null
	for child in root.get_children():
		if _is_host(child):
			return child
	return null


static func _is_host(node: Node) -> bool:
	return node != null and node.has_method("show_voyage") and node.has_method("show_narrative")


static func go_voyage(tree: SceneTree = null) -> bool:
	var host := find_host(tree)
	if host == null:
		return false
	host.call("show_voyage")
	return true


static func go_narrative(tree: SceneTree = null, scene_id: String = "") -> bool:
	var host := find_host(tree)
	if host == null:
		return false
	host.call("show_narrative", scene_id)
	return true


static func current_mode(tree: SceneTree = null) -> String:
	var host := find_host(tree)
	if host == null:
		return ""
	if host.has_method("get_mode"):
		return str(host.call("get_mode"))
	return ""


## 启动海战 UI；成功返回控制器 Node，无宿主返回 null
static func start_combat(tree: SceneTree, enemy: Dictionary) -> Node:
	var host := find_host(tree)
	if host == null or not host.has_method("show_combat"):
		return null
	return host.call("show_combat", enemy)


static func is_combat(tree: SceneTree = null) -> bool:
	return current_mode(tree) == MODE_COMBAT


static func is_cutscene(tree: SceneTree = null) -> bool:
	return current_mode(tree) == MODE_CUTSCENE


## 播放过场；成功 true。无宿主或 id 无效时 false。
static func play_cutscene(tree: SceneTree, cutscene_id: String) -> bool:
	var host := find_host(tree)
	if host == null or not host.has_method("play_cutscene"):
		return false
	return bool(host.call("play_cutscene", cutscene_id))


static func get_cutscene_player(tree: SceneTree = null) -> Node:
	var host := find_host(tree)
	if host == null or not host.has_method("get_cutscene_player"):
		return null
	return host.call("get_cutscene_player")
