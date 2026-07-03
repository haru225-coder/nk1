class_name StoryState extends RefCounted

## 剧情与旗标管理模块

var fame: int = 0
var flags: Dictionary = {}
var story_flags: Dictionary = {}
var story_items: Dictionary = {}
var cards: Dictionary = {}
var titles: Dictionary = {}
var npc_relationships: Dictionary = {}
var linboyuan_relationship: int = 0
var jia_relationship: int = 0
var unlocked_chapters: Array = []

signal flag_set(flag_name: String)
signal story_flag_set(key: String, value: Variant)
signal item_acquired(item_id: String)
signal chapter_unlocked(chapter_id: String)
signal card_granted(card_id: String)
signal title_granted(title_id: String)
signal npc_relationship_changed(npc_id: String, value: int)

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true
	flag_set.emit(flag_name)

func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name) and flags[flag_name] == true

func set_story_flag(key: String, value = true) -> void:
	story_flags[key] = value
	story_flag_set.emit(key, value)

func get_story_flag(key: String, default = null):
	return story_flags.get(key, default)

func has_story_flag(key: String) -> bool:
	if not story_flags.has(key):
		return false
	var v = story_flags[key]
	if v is bool:
		return v
	return v != null

func has_story_flag_value(key: String, expected) -> bool:
	return story_flags.has(key) and story_flags[key] == expected

func get_npc_affinity(npc_id: String) -> int:
	return int(story_flags.get("npc_affinity_" + npc_id, 0))

func adjust_npc_affinity(npc_id: String, delta: int) -> void:
	var key := "npc_affinity_" + npc_id
	var current := get_npc_affinity(npc_id)
	set_story_flag(key, current + delta)

func acquire_item(item_id: String) -> void:
	story_items[item_id] = true
	item_acquired.emit(item_id)

func has_item_flag(item_id: String) -> bool:
	return story_items.has(item_id) and story_items[item_id] == true

func remove_item(item_id: String) -> void:
	story_items.erase(item_id)

func grant_card(card_id: String) -> void:
	cards[card_id] = true
	card_granted.emit(card_id)

func has_card(card_id: String) -> bool:
	return cards.has(card_id) and cards[card_id] == true

func grant_title(title_id: String) -> void:
	titles[title_id] = true
	title_granted.emit(title_id)

func has_title(title_id: String) -> bool:
	return titles.has(title_id) and titles[title_id] == true

func get_npc_relationship(npc_id: String) -> int:
	return int(npc_relationships.get(npc_id, 0))

func set_npc_relationship(npc_id: String, value: int) -> void:
	npc_relationships[npc_id] = value
	npc_relationship_changed.emit(npc_id, value)

func adjust_npc_relationship(npc_id: String, delta: int) -> void:
	set_npc_relationship(npc_id, get_npc_relationship(npc_id) + delta)

func unlock_chapter(chapter_id: String) -> void:
	if chapter_id not in unlocked_chapters:
		unlocked_chapters.append(chapter_id)
		set_story_flag("chapter_unlock:" + chapter_id, true)
		chapter_unlocked.emit(chapter_id)

func to_dict() -> Dictionary:
	return {
		"fame": fame, "flags": flags, "story_flags": story_flags,
		"story_items": story_items, "cards": cards, "titles": titles,
		"npc_relationships": npc_relationships, "linboyuan_relationship": linboyuan_relationship,
		"jia_relationship": jia_relationship, "unlocked_chapters": unlocked_chapters,
	}

func from_dict(d: Dictionary) -> void:
	fame = int(d.get("fame", 0))
	flags = d.get("flags", {})
	story_flags = d.get("story_flags", {})
	story_items = d.get("story_items", {})
	cards = d.get("cards", {})
	titles = d.get("titles", {})
	npc_relationships = d.get("npc_relationships", {})
	linboyuan_relationship = int(d.get("linboyuan_relationship", 0))
	jia_relationship = int(d.get("jia_relationship", 0))
	unlocked_chapters = d.get("unlocked_chapters", [])
