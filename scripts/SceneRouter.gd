class_name SceneRouter extends RefCounted

## ═══════════════════════════════════════════════════════════
## SceneRouter — 场景路由（P7-B / 阶段 B）
## ═══════════════════════════════════════════════════════════
## 职责：
##   1. 分类 scene_id → world_map / market / narrative
##   2. 解析 narrative 的 scene_data（含 city_* 后缀回退）
##   3. 解析市场港口 id
##
## 不做：
##   - 不持有 UI 节点 / 不 change_scene
##   - 不改 GameState / 不发 Intent
##
## 新交互形态：先在此加 Kind，再在 Main 接线；禁止回写 if 链到 Main.load_scene。
## ═══════════════════════════════════════════════════════════

const KIND_WORLD_MAP := "world_map"
const KIND_MARKET := "market"
const KIND_NARRATIVE := "narrative"

const FACILITY_SUFFIXES: Array[String] = [
	"_guild", "_residence", "_inn", "_exam",
	"_tavern", "_yamen", "_shipyard", "_temple",
]


static func classify(scene_id: String) -> String:
	if scene_id == "world_map":
		return KIND_WORLD_MAP
	if scene_id.ends_with("_market"):
		return KIND_MARKET
	return KIND_NARRATIVE


static func is_market(scene_id: String) -> bool:
	return classify(scene_id) == KIND_MARKET


static func is_world_map(scene_id: String) -> bool:
	return classify(scene_id) == KIND_WORLD_MAP


static func resolve_scene_data(scene_id: String) -> Dictionary:
	var scene_data: Dictionary = GameManager.get_scene_by_id(scene_id)
	if not scene_data.is_empty():
		return scene_data
	for suffix: String in FACILITY_SUFFIXES:
		if scene_id.ends_with(suffix):
			var generic_id: String = "city" + suffix
			scene_data = GameManager.get_scene_by_id(generic_id)
			if not scene_data.is_empty():
				return scene_data
	return {}


static func market_port_id(scene_id: String) -> String:
	var port_to_open := str(GameState.last_port)
	if port_to_open == "":
		port_to_open = scene_id.replace("_market", "")
	return port_to_open
