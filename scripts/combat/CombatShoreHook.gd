## 岸上薄钩子：供 Main 调试键或探针叠一层接舷题签、号令面板与状态条，不改玩法、不入存档。
## 真实接舷路径仍是 SeaChart 遇盗 → WorldMap 近敌按 G。
##
## 海战号令 UI（lane combat08）：状态条 CombatStatusHud + 号令面板 CombatOrdersPanel，两层都自加 nk1_combat_ui 组。
##   mount_combat_ui(world)：给 WorldMap 日后接线的一步入口——本钩子不改 WorldMap，也不自己去场景树里找海战场挂。
##     接线方在 _setup_combat 末尾调一次即可；world 若有 _on_combat_order(order_id, payload) 就顺手连上 order_issued。
##     号令的效力由接线方取：CombatOrdersPanel.modifiers_for(world)（没挂面板时全 1.0），或信号 / register_handler。
##   preview_orders_ui(parent)：岸上 / 探针预览，读 sample_snapshot() 样例数，不收键盘（岸上 1–5 另有用处）。
extends RefCounted

const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const CombatStatusHud := preload("res://scripts/ui/CombatStatusHud.gd")
const CombatOrdersPanel := preload("res://scripts/ui/CombatOrdersPanel.gd")

## 同 CombatStatusHud.GROUP_UI / CombatOrdersPanel.GROUP_UI
const UI_GROUP := "nk1_combat_ui"


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
		var detail := CombatFx.board_win_note("快船") if win else CombatFx.board_lose_note(3)
		BoardingStage.resolve(parent, "win" if win else "lose", detail)
		CombatFx.hitstop(parent, 0.07, 0.22)
	)
	return true


## 海战场挂状态条 + 号令面板（各一副；已挂的沿用）。返回 {"hud": CanvasLayer, "orders": CanvasLayer}；world 为空返回 {}。
static func mount_combat_ui(world: Node, ship: Node2D = null) -> Dictionary:
	if world == null or not is_instance_valid(world):
		return {}
	var hud := CombatStatusHud.mount(world, ship)
	var orders := CombatOrdersPanel.mount(world)
	if orders != null and world.has_method("_on_combat_order"):
		var cb := Callable(world, "_on_combat_order")
		if not orders.is_connected("order_issued", cb):
			orders.connect("order_issued", cb)
	return {"hud": hud, "orders": orders}


## 摘掉 parent 下的海战 UI（两层都摘）；返回摘了几层
static func unmount_combat_ui(parent: Node) -> int:
	if parent == null or not is_instance_valid(parent):
		return 0
	var n := 0
	for c in parent.get_children():
		if c.is_in_group(UI_GROUP):
			parent.remove_child(c)
			c.queue_free()
			n += 1
	return n


## 岸上预览：同一套状态条 + 号令面板挂在 parent 下，读样例数（sample 空则用 sample_snapshot()），不收键盘。
## 再调一次先摘旧的。返回 {"hud", "orders"}；parent 不在树里返回 {}。
static func preview_orders_ui(parent: Node, sample := {}) -> Dictionary:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return {}
	unmount_combat_ui(parent)
	var snap: Dictionary = sample if not sample.is_empty() else sample_snapshot()
	var hud := CombatStatusHud.new()
	hud.source = func() -> Dictionary: return snap
	parent.add_child(hud)
	var orders := CombatOrdersPanel.new()
	orders.keys_enabled = false
	orders.crew_override = int(snap.get("crew", 80))
	orders.parley_source = func() -> Dictionary: return sample_parley(snap)
	parent.add_child(orders)
	return {"hud": hud, "orders": orders}


## 调试键用：有就摘、没有就挂预览；返回挂上之后是否在
static func toggle_orders_preview(parent: Node) -> bool:
	if unmount_combat_ui(parent) > 0:
		return false
	return not preview_orders_ui(parent).is_empty()


## 岸上预览样例：东北风四级，船首东南偏东、左舷抢风，敌在右舷七十四度（入射界、我居上风），
## 箭 / 弩箭 / 石弹 / 火药存量（键同 ReloadAmmo），右舷还在装，帆八成、舵完好、浸水二成，士气尚稳；旗舰八十人
static func sample_snapshot() -> Dictionary:
	return {
		"has_ship": true, "has_target": true, "boarding": false,
		"wind_dir": Vector2(-1.0, 1.0).normalized(), "wind_force": 80.0,
		"heading": Vector2.UP.rotated(deg_to_rad(109.0)), "sail_gear": 2,
		"sail": 0.8, "rudder": 1.0, "flood": 0.2, "fire": 0.0, "morale": 64.0,
		"ammo": {"jian": 120, "nujian": 24, "shi": 18, "huoyao": 32},
		"ammo_max": {"jian": 160, "nujian": 40, "shi": 30, "huoyao": 48},
		"reload": {"port": 0.0, "starboard": 1.4},
		"target_bearing": 74.0, "target_dist": 260.0, "upwind": 1, "board_distance": 140.0,
		"crew": 80,
		"parley": {"enemy_morale": 48.0, "hull_frac": 0.55, "ratio": 1.3, "grappled": false},
	}


## 预览里劝降读的敌情：样例的 parley 段（敌士气四十八、船体余五成半、我众敌寡一成三）
static func sample_parley(snap: Dictionary) -> Dictionary:
	var p: Dictionary = snap.get("parley", {})
	var out := p.duplicate()
	out["ok"] = true
	out["dist"] = float(snap.get("target_dist", 260.0))
	return out
