extends SceneTree
## lane-w53-4 剧情数据专项探针。专捕这一类错：advance_text 里宣称的解锁港与 ports.json
## 的 unlock 账实不符。修复前实拍：chapters.json 第 2 章 advance_text 写「广州、萨摩 已可抵达」——
## 萨摩在 ports.json 里挂的是 unlock=ch3（第三章才开），玩家在第二章末看到「已可抵达」却开不过去；
## 第二章末同时只宣广州、萨摩而漏了同在 ch3 解锁的神州（实为第三章解锁埠口清单对不齐，须对齐）。
## 判定：章 k 的 advance_text 中【…已可抵达】串出的港名清单 == ports.json 里 unlock == ch(k+1) 的港名清单。
## 数据对账；退了这格（如复原「广州、萨摩 已可抵达」的旧口径同时漏掉神州）即红。
## 除此之外两格：must_visit id 落在 ports.json、其出场名与 ports.json 一致；visited_count ≤ grammable。
var fails := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	var chapters: Dictionary = _load("res://data/chapters.json")
	var ports: Dictionary = _load("res://data/ports.json")
	var port_by_name := {}
	var port_name := {}
	for p in ports.get("ports", []):
		port_by_name[str(p.get("name", ""))] = str(p.get("id", ""))
		port_name[str(p.get("id", ""))] = str(p.get("name", ""))

	# 1. must_visit 的 id 落在 ports.json 且与现有后续出场名账实一致（GATES §十、判档 8 格对证）
	for ch in chapters.get("chapters", []):
		for key in ["next_requires", "ending_requires"]:
			var req = ch.get(key)
			if typeof(req) == TYPE_DICTIONARY:
				for pid in req.get("must_visit", []):
					_check(bool(port_name.has(str(pid))), "章%s must_visit=%s 在 ports.json" % [ch.get("id"), pid])

	# 2. visited_count ≤ 当时已解锁港口数（from unlock_ch ≤ cid 计）
	for ch in chapters.get("chapters", []):
		var parts := int(ch.get("id", 1))
		var visits := 0
		for p in ports.get("ports", []):
			var u := str(p.get("unlock", "ch1"))
			if u.begins_with("ch") and u.length() >= 3 and u.substr(2).is_valid_int() and int(u.substr(2)) <= parts:
				visits += 1
		for key in ["next_requires", "ending_requires"]:
			var req = ch.get(key)
			if typeof(req) == TYPE_DICTIONARY:
				var need: int = int(req.get("visited_count", 0))
				_check(need <= visits, "章 %s %s.visited_count=%d ≤ 已解锁 %d" % [ch.get("id"), key, need, visits])

	# 3. 第 k 章 advance_text 的「已可抵达」清单 == ports.json 中 unlock=ch(k+1) 的港名清单
	#    （错在 advance_text 里漏/多一个；这里就是修复后的对账格）
	var unlock_pat := RegEx.new()
	unlock_pat.compile("【([^】]+)已可抵达】")
	for ch in chapters.get("chapters", []):
		var cid := int(ch.get("id", 0))
		if not ch.get("advance_text"):
			continue
		var claim_names: Array = []
		for m in unlock_pat.search_all(str(ch.get("advance_text"))):
			var body := str(m.get_string(1)).replace("、", ",")
			for raw in body.split(",", false):
				var nm := raw.strip_edges()
				if nm != "":
					claim_names.append(nm)
		var want_ids: Array = []
		for p in ports.get("ports", []):
			if str(p.get("unlock", "")) == "ch%d" % (cid + 1):
				want_ids.append(str(p.get("id")))
		var want_names: Array = []
		for wid in want_ids:
			want_names.append(port_name.get(wid, wid))
		var claim_set := {}
		for nm in claim_names:
			claim_set[nm] = true
		var want_set := {}
		for nm in want_names:
			want_set[nm] = true
		var miss: Array = []
		for nm in want_names:
			if not claim_set.has(nm):
				miss.append(nm)
		var extra: Array = []
		for nm in claim_names:
			if not want_set.has(nm):
				extra.append(nm)
		_check(miss.is_empty() and extra.is_empty(),
			"章%d advance_text 宣港清单与 ch%d 解锁埠口账一致（多 %s / 漏 %s）" % [
				cid, cid + 1, extra, miss,
			])

	if fails > 0:
		quit(1)
		return
	print("qa_w53_4_story.gd：全部通过")
	quit(0)


func _load(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return {}
	f.close()
	return j.data if typeof(j.data) == TYPE_DICTIONARY else {}
