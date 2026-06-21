class_name SceneVariantResolver extends RefCounted

static func resolve(scene_data: Dictionary, scene_id: String) -> Dictionary:
	match scene_id:
		"xinghua_exam":
			return _variant_xinghua_exam(scene_data)
		"xinghua_temple":
			return _variant_xinghua_temple(scene_data)
		"scene03_lin_ship":
			return _variant_scene03_lin_ship(scene_data)
		"scene02_quanzhou_port":
			return _variant_scene02_quanzhou_port(scene_data)
		"scene08_return":
			return _variant_scene08_return(scene_data)
		"scene07_keelung_coast":
			return _variant_scene07_keelung_coast(scene_data)
		"city_shipyard":
			return _variant_city_shipyard(scene_data)
		"quanzhou_wharf":
			return _variant_quanzhou_wharf(scene_data)
		"chapter2_linan_blocked":
			return _variant_chapter2_linan_blocked(scene_data)
		"chapter2_path_select":
			return _variant_chapter2_path_select(scene_data)
		"chapter2_jia_approach":
			return _variant_chapter2_jia_approach(scene_data)
		"chapter2_lin_contact":
			return _variant_chapter2_lin_contact(scene_data)
		"chapter2_scholar_seek":
			return _variant_chapter2_scholar_seek(scene_data)
		"linan_taixue":
			return _variant_linan_taixue(scene_data)
		"linan_market":
			return _variant_linan_market(scene_data)
		"linan_canal":
			return _variant_linan_canal(scene_data)
		_:
			return scene_data.duplicate(true)

static func _dup(scene_data: Dictionary) -> Dictionary:
	return scene_data.duplicate(false)

static func _apply_tokens(body: String, tokens: Dictionary) -> String:
	var result := body
	for key in tokens.keys():
		var placeholder := "{%s}" % key
		if not result.contains(placeholder):
			if OS.is_debug_build():
				push_warning("SceneVariantResolver: 占位符 %s 未在文本中找到。" % placeholder)
		result = result.replace(placeholder, str(tokens[key]))
	return result

static func _variant_xinghua_exam(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("spring_autumn_scroll"):
		data["body"] = "乡学已静。先生咳疾在床，只让你把《春秋》藏好，早些上路。"
		data["investigations"] = []
		data["choices"] = [{"label": "回城", "next": "port_xinghua"}]
	elif not GameState.has_story_flag("xianghua_morning_done"):
		data["body"] = "乡学门户紧闭。门房说：「晨课未散，闲人莫入。」"
		data["investigations"] = []
		data["choices"] = [{"label": "回城", "next": "port_xinghua"}]
	elif GameState.has_story_flag("jia_faction_met"):
		data["investigations"] = data.get("investigations", []).duplicate(true)
		data["investigations"].append({
			"label": "禀报城隍庙冲突",
			"text": "先生眼神一沉：「贾府盯的是有书名的人。林伯渊能护你一阵，护不了一世。」",
			"once_flag": "warned_jia_after_temple",
			"effects": {"story_flag": "warned_jia_after_temple", "fame": 1},
		})
	return data

static func _variant_xinghua_temple(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("jia_faction_met"):
		data["body"] = "城隍庙雨檐滴水。贾府门生早已离去，只余一炷将尽的香。"
		data["investigations"] = []
		data["choices"] = [{"label": "回城", "next": "port_xinghua"}]
	elif not GameState.has_story_flag("xianghua_morning_done"):
		data["body"] = "城隍庙尚未开门。你只得在街角避雨。"
		data["investigations"] = []
		data["choices"] = [{"label": "回城", "next": "port_xinghua"}]
	elif GameState.has_story_flag("teacher_health_asked"):
		data["body"] = (
			"先生昨夜的话还在耳边：「贾府眼生得很。」\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_scene03_lin_ship(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("warned_jia_after_temple"):
		data["body"] = (
			"林伯渊听完城隍庙之事，只道：「蒲氏与贾府，一条绳上的蚂蚱。」\n\n"
			+ data.get("body", "")
		)
	elif GameState.has_story_flag("jia_faction_met"):
		data["body"] = (
			"你报上城隍庙遇贾府门生一事。林伯渊冷笑：「他们先踩场，后伸手。」\n\n"
			+ data.get("body", "")
		)
	if GameState.has_story_flag("lin_dock_hint"):
		data["body"] = (
			"你按夹页所示摸到东坞三号泊位，省去半个时辰问话。\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_scene02_quanzhou_port(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	var arrival := "两日后抵刺桐港。"
	if GameState.has_story_flag("quanzhou_travel_prepared"):
		arrival = "抵达刺桐港。"
		data["body"] = (
			"脚夫说的时辰不差。午后入刺桐港——\n\n"
			+ _apply_tokens(data.get("body", ""), {"quanzhou_arrival": arrival})
		)
	else:
		data["body"] = _apply_tokens(data.get("body", ""), {"quanzhou_arrival": arrival})
	if GameState.has_story_flag("quanzhou_market_rumor"):
		data["body"] = (
			"市集听来的话应验了：没货引，寸步难行。\n\n" + data.get("body", "")
		)
	return data

static func _variant_scene08_return(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	var pu_reason := (
		"你在城隍庙捡起那枚碎银"
		if GameState.has_story_flag("jia_silver_taken")
		else "你在码头多停那一眼"
	)
	var pu_tail_intensity := (
		"——这次靠得更近，像是等你靠岸"
		if GameState.pu_attention > 10
		else ""
	)
	data["body"] = _apply_tokens(data.get("body", ""), {
		"pu_reason": pu_reason,
		"pu_tail_intensity": pu_tail_intensity,
	})
	if GameState.pu_attention > 10:
		var choices: Array = data.get("choices", []).duplicate(true)
		if not GameState.has_story_flag("chapter1_pu_bribed"):
			choices.insert(0, {
				"label": "花八十贯雇快船甩开尾巴",
				"next": "port_quanzhou",
				"effects": {
					"story_flag": "chapter1_complete",
					"story_flag2": {
						"linboyuan_relationship": "neutral_positive",
						"chapter1_pu_bribed": true,
					},
					"chapter_unlock": "chapter2_linan",
					"money": -80,
					"pu_attention": -8,
					"fame": 1,
				},
				"narration": "船家在雾中绕了一个时辰。尾随的旗号没再出现。",
			})
			for choice in choices:
				var label: String = choice.get("label", "")
				if label == "立刻北上，不等尾巴" or label == "先绕蕃坊甩掉跟踪":
					var eff: Dictionary = choice.get("effects", {}).duplicate(true)
					eff["money"] = int(eff.get("money", 0)) - 40
					eff["fame"] = int(eff.get("fame", 0)) - 3
					choice["effects"] = eff
					choice["narration"] = (
						"湾口有人截船索例。你掏空部分货银，才换回一条活路。"
					)
		data["choices"] = choices
	return data

static func _variant_scene07_keelung_coast(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("prayed_at_black_water"):
		data["body"] = (
			"黑水沟里求过天的人，踏上陌生海岸时，掌心仍在发烫。\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_city_shipyard(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("lin_dock_hint"):
		data["body"] = "船坞嘈杂。你认得夹页笔迹：东坞三号泊位在最里侧。"
	elif GameState.has_story_flag("ghost_ship_rumor"):
		data["body"] = (
			"工头仍在争那艘漂回来的福船。舱底烧焦的朝廷旗，已传遍码头。\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_quanzhou_wharf(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("quanzhou_arrived"):
		data["body"] = "码头仍旧喧嚣。瓷粉嵌在青石缝里，褐衣汉子已不见踪影。"
	elif GameState.has_story_flag("saw_smuggling"):
		data["body"] = "你认得这处验引棚——碎瓷下的私盐，就是从这里开始。"
	return data

static func _variant_chapter2_linan_blocked(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.pu_attention > 10:
		data["body"] = (
			"【守门卒】：「你不是泉州那个到处打听蒲帅的生面孔吗？」\n\n"
			+ data.get("body", "")
		)
		var blocked_choices: Array = data.get("choices", []).duplicate(true)
		if not GameState.has_story_flag("linan_gate_pu_shakedown"):
			blocked_choices.insert(0, {
				"label": "掏五十贯，买一句「没看见」",
				"next": "chapter2_path_select",
				"effects": {
					"money": -50,
					"pu_attention": -5,
					"story_flag": "linan_gate_pu_shakedown",
				},
				"narration": "卒子掂了掂钱袋，眼皮都没抬：「进去打听。别说是我放的。」",
			})
		data["choices"] = blocked_choices
	return data

static func _variant_chapter2_path_select(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	var preface := ""
	if GameState.pu_attention > 10 and not GameState.has_story_flag("linan_gate_pu_shakedown"):
		preface = "河西绸缎铺的门帘在风里晃。你伸手要掀，卒子在身后咳了一声：「蒲帅点名的人，贾府不收。」\n\n"
		var path_choices: Array = []
		for choice in data.get("choices", []):
			if choice.get("next", "") == "chapter2_jia_approach":
				continue
			path_choices.append(choice)
		data["choices"] = path_choices
	data["body"] = _apply_tokens(data.get("body", ""), {
		"jia_blocked_preface": preface,
	})
	return data

static func _variant_chapter2_jia_approach(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("jia_silver_taken"):
		data["body"] = (
			"你袖中碎银贴着皮肉，烫得像一枚未冷的印。\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_chapter2_lin_contact(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("penghu_night"):
		data["body"] = (
			"澎湖的风还在骨头里响。\n\n"
			+ data.get("body", "")
		)
	if GameState.linboyuan_relationship >= 8:
		data["body"] = (
			"老汉见你第一眼便道：「林老大说过，你会来。」\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_chapter2_scholar_seek(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	if GameState.has_story_flag("heard_exam_gossip"):
		data["body"] = (
			"客栈里那句「不如出海去」，到义庄门口，竟成了另一句话。\n\n"
			+ data.get("body", "")
		)
	return data

static func _variant_linan_taixue(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	var route: String = str(GameState.get_story_flag("chapter2_route", ""))
	var name_suffix := ""
	var exam_suffix := ""
	var sea_suffix := ""
	match route:
		"jia":
			name_suffix = "——贾府作保的墨迹，比盐还刺眼"
		"lin":
			sea_suffix = "。断眉老汉说：别信榜文，信潮信"
		"scholar":
			exam_suffix = "——你发过誓，这笔怎么落，是你的命"
	data["body"] = _apply_tokens(data.get("body", ""), {
		"taixue_name_suffix": name_suffix,
		"taixue_exam_suffix": exam_suffix,
		"taixue_sea_suffix": sea_suffix,
	})
	return data

static func _variant_linan_market(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	data["body"] = _apply_tokens(data.get("body", ""), {
		"market_gossip": "读书人的肚子，靠太学膳银填；膳银发不下来，就靠借。",
		"pu_shop_warning": "",
	})
	return data

static func _variant_linan_canal(scene_data: Dictionary) -> Dictionary:
	var data := _dup(scene_data)
	data["body"] = (
		"漕船排队过闸。禁军挎刀立在桥头，目光像秤——称的不是货，是人。\n\n"
		+ data.get("body", "")
	)
	return data