class_name FacilityResolver extends RefCounted

static func facility_available(fac: Dictionary) -> bool:
	return _story_rule_available(fac)

static func resolve_facility_scene(fac: Dictionary, port_location: String) -> String:
	var target_scene: String = fac.get("id", "")
	if target_scene.begins_with("city_"):
		var suffix := target_scene.replace("city_", "")
		target_scene = port_location + "_" + suffix
	return target_scene

static func resolve_hotspot_scene(hotspot: Dictionary, fac: Dictionary, port_location: String) -> String:
	var explicit: String = hotspot.get("scene_id", "")
	if explicit != "":
		return explicit
	return resolve_facility_scene(fac, port_location)

static func choice_available(choice: Dictionary) -> bool:
	return _story_rule_available(choice)

static func resolve_choice_style(choice: Dictionary) -> String:
	var style: String = choice.get("choice_style", "")
	if style != "":
		return style
	if choice.get("next", "") == "world_map":
		return "sail"
	return "default"

static func resolve_facility_subtitle(fac: Dictionary) -> Dictionary:
	var subtitle = fac.get("subtitle", "点击进入")
	if subtitle is String:
		return {"text": subtitle, "state": "default"}
	if subtitle is Dictionary:
		var default_text: String = subtitle.get("default", "点击进入")
		for rule in subtitle.get("rules", []):
			if _story_rule_available(rule):
				return {
					"text": rule.get("text", default_text),
					"state": rule.get("state", "default"),
				}
		return {
			"text": default_text,
			"state": subtitle.get("state", "default"),
		}
	return {"text": str(subtitle), "state": "default"}

static func resolve_facility_icon(fac: Dictionary) -> Texture2D:
	var configured: String = fac.get("icon", "")
	if configured != "":
		var tex := AssetPlaceholder.load_texture(configured, "texture")
		if tex:
			return tex

	var fac_id: String = fac.get("id", "")
	var title: String = str(fac.get("title", ""))
	for key in icon_keys_for(fac_id, title):
		for folder: String in ["res://assets/ui/icons/", ResourcePaths.DIR_ICONS_128, ResourcePaths.DIR_ASSETS]:
			for path: String in [
				folder + "icon_" + key + ".png",
				folder + "icon_" + key + "_koei.png",
			]:
				var tex := AssetPlaceholder.load_texture(path, "texture")
				if tex:
					return tex

	return AssetPlaceholder.load_texture(ResourcePaths.TEX_ICON_MARKET, "texture")


## 设施 id / 标题 → 图标关键字（CommandBar / 设施卡共用）
static func icon_keys_for(fac_id: String, title: String = "") -> Array[String]:
	var keys: Array[String] = []
	var blob := (fac_id + " " + title).to_lower()
	if fac_id.begins_with("city_"):
		keys.append(fac_id.replace("city_", ""))
	# 英文关键词
	if "exam" in blob or "school" in blob or "taixue" in blob or "学" in title or "考" in title:
		keys.append("exam")
	if "temple" in blob or "mosque" in blob or "寺" in title or "庙" in title or "观" in title:
		keys.append("temple")
		keys.append("residence")
	if "wharf" in blob or "pier" in blob or "anchor" in blob or "码头" in title or "埠" in title:
		keys.append("wharf")
	if "ship" in blob or "canal" in blob or "船坞" in title or "河" in title:
		keys.append("shipyard")
	if "market" in blob or "spice" in blob or "salt" in blob or "rice" in blob \
			or "smuggler" in blob or "den" in blob or "black" in blob \
			or "市" in title or "集" in title or "盐" in title or "米" in title:
		keys.append("market")
	if "inn" in blob or "hut" in blob or "shack" in blob or "馆" in title or "舍" in title:
		keys.append("inn")
	if "tavern" in blob or "tea" in blob or "酒" in title or "茶" in title:
		keys.append("tavern")
	if "guild" in blob or "会馆" in title or "行" in title:
		keys.append("guild")
	if "yamen" in blob or "衙" in title or "司" in title:
		keys.append("yamen")
	if "lookout" in blob or "beacon" in blob or "ruins" in blob or "望" in title or "烽" in title:
		keys.append("lookout")
		keys.append("ruins")
	if "residence" in blob or "宅" in title or "府" in title:
		keys.append("residence")
	keys.append(fac_id)
	# 去重保序
	var seen: Dictionary = {}
	var out: Array[String] = []
	for key in keys:
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out


## 双列设施：左=社交/情报，右=海洋/贸易（R1 KOEI 港内入口）
const COLUMN_LEFT_KEYS: Array[String] = [
	"tavern", "inn", "guild", "yamen", "exam", "temple", "residence", "school",
]
const COLUMN_RIGHT_KEYS: Array[String] = [
	"market", "shipyard", "wharf", "ruins", "lookout", "canal", "pier",
]


static func column_side_for(fac: Dictionary) -> String:
	var fac_id := str(fac.get("id", ""))
	var title := str(fac.get("title", fac.get("name", "")))
	var keys := icon_keys_for(fac_id, title)
	for key in keys:
		if key in COLUMN_LEFT_KEYS:
			return "left"
		if key in COLUMN_RIGHT_KEYS:
			return "right"
	# id 字面子串兜底
	var blob := (fac_id + " " + title).to_lower()
	for key in COLUMN_LEFT_KEYS:
		if key in blob:
			return "left"
	for key in COLUMN_RIGHT_KEYS:
		if key in blob:
			return "right"
	return "rest"


## 将设施分成左右列；rest 交错补齐；列内按关键字优先级排序
static func split_facility_columns(facilities: Array) -> Dictionary:
	var left_facs: Array = []
	var right_facs: Array = []
	var rest_facs: Array = []
	for raw in facilities:
		if not raw is Dictionary:
			continue
		var fac: Dictionary = raw
		var side := column_side_for(fac)
		match side:
			"left":
				left_facs.append(fac)
			"right":
				right_facs.append(fac)
			_:
				rest_facs.append(fac)
	for i in rest_facs.size():
		if i % 2 == 0:
			left_facs.append(rest_facs[i])
		else:
			right_facs.append(rest_facs[i])
	left_facs.sort_custom(func(a, b): return _column_sort_key(a, true) < _column_sort_key(b, true))
	right_facs.sort_custom(func(a, b): return _column_sort_key(a, false) < _column_sort_key(b, false))
	return {"left": left_facs, "right": right_facs}


static func _column_sort_key(fac: Dictionary, is_left: bool) -> int:
	var order: Array[String] = COLUMN_LEFT_KEYS if is_left else COLUMN_RIGHT_KEYS
	var keys := icon_keys_for(str(fac.get("id", "")), str(fac.get("title", fac.get("name", ""))))
	for i in order.size():
		if order[i] in keys:
			return i
	return 100


static func _story_rule_available(rule: Dictionary) -> bool:
	var req: String = rule.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = rule.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	return true
