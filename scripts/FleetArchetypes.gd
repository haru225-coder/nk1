extends Node

const FLEET_TEMPLATES: Array[Dictionary] = [
	{
		"id": "patrol_song",
		"name": "大宋水师巡船",
		"desc": "桅杆挂着残破的官旗，吃水极浅，像是刚缉私完。",
		"hostility": 0.2,
		"options": [
			{
				"label": "出示货引，接受盘查",
				"req_flag": "has_valid_permit",
				"success_chance": 0.9,
				"msg_ok": "校尉验明正身，挥手放行。",
				"msg_fail": "货引过期，被罚没五十贯。",
				"effects_fail": {"money": -50},
			},
			{
				"label": "强行冲关",
				"success_chance": 0.5,
				"msg_ok": "帆满风急，甩开了官船。",
				"msg_fail": "被乱箭射伤船帆，水手负伤。",
				"effects_fail": {"hull_hp": -20, "crew_count": -2},
			},
		],
	},
	{
		"id": "pirate_wokou",
		"name": "倭寇快船",
		"desc": "船身低矮，挂骷髅旗，直冲你而来。",
		"hostility": 1.0,
		"options": [
			{
				"label": "右舷齐射，准备接舷战",
				"success_chance": 0.7,
				"msg_ok": "一轮炮击逼退敌船，缴获少许银两。",
				"effects_ok": {"money": 30},
				"msg_fail": "接舷战损失惨重，勉强脱离。",
				"effects_fail": {"crew_count": -5, "hull_hp": -30},
			},
			{
				"label": "抛货逃生",
				"success_chance": 0.9,
				"msg_ok": "丢下半舱货物，倭寇只顾抢货。",
				"effects_ok": {"special_action": "drop_cargo_half"},
				"msg_fail": "货物没丢干净，船尾被火矢点燃。",
				"effects_fail": {"hull_hp": -15},
			},
		],
	},
	{
		"id": "merchant_arab",
		"name": "大食番舶",
		"desc": "巨大的三角帆破雾而出，水手多是昆仑奴。",
		"hostility": 0.0,
		"options": [
			{
				"label": "旗语交涉，交换情报",
				"success_chance": 0.8,
				"msg_ok": "得知前方有暗礁，避开了灾祸。",
				"effects_ok": {"fame": 2},
			},
			{
				"label": "无视，继续航行",
				"success_chance": 1.0,
				"msg_ok": "两船擦肩而过。",
			},
		],
	},
]


func get_random_encounter() -> Dictionary:
	return FLEET_TEMPLATES[randi() % FLEET_TEMPLATES.size()].duplicate(true)


func get_template_by_id(template_id: String) -> Dictionary:
	for tpl in FLEET_TEMPLATES:
		if tpl.get("id", "") == template_id:
			return tpl.duplicate(true)
	return FLEET_TEMPLATES[0].duplicate(true)


func to_event_data(encounter: Dictionary) -> Dictionary:
	var choices: Array = []
	for opt in encounter.get("options", []):
		choices.append(opt.duplicate(true))
	return {
		"title": encounter.get("name", "海上遭遇"),
		"body": encounter.get("desc", ""),
		"choices": choices,
	}


func check_req_flag(flag: String) -> bool:
	match flag:
		"has_valid_permit":
			return GameState.has_customs_permit or GameState.has_flag("departure_authorized")
		_:
			return GameState.has_story_flag(flag) or GameState.has_flag(flag)