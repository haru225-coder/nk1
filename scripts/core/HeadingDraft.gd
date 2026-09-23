class_name HeadingDraft
extends RefCounted
## 晨潮三向。风每一手最多发三个已解锁海港。
## 本章尚未亲至的必须港占第一席，其余按顺风、短里程轮转。
## 不在解析期写 autoload 名：class_name 登记早于 autoload，直接写会编译失败。


static func _node(node_name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(node_name)


static func pool(origin: String) -> Array:
	var gm = _node("GameManager")
	var out: Array = []
	for p in gm.unlocked_ports():
		var pid := str(p.get("id", ""))
		if pid == "" or pid == origin:
			continue
		if int(p.get("depth", 0)) <= 0:
			continue
		out.append(p)
	return out


static func deal(origin: String, salt: int) -> PackedStringArray:
	var voyage = _node("Voyage")
	var ports: Array = pool(origin)
	var ids := PackedStringArray()
	for p in ports:
		ids.append(str(p.get("id", "")))
	var pin := _pinned(ids)
	var rest: Array = []
	for p in ports:
		var pid := str(p.get("id", ""))
		if pid == pin:
			continue
		rest.append({
			"id": pid,
			"wf": voyage.wind_factor(voyage.bearing(origin, pid)),
			"dist": voyage.distance_li(origin, pid),
		})
	rest.sort_custom(_before)
	var seats := PackedStringArray()
	if pin != "":
		seats.append(pin)
	if rest.is_empty():
		return seats
	var start := posmod(salt, rest.size())
	var i := 0
	while seats.size() < 3 and i < rest.size():
		var item: Dictionary = rest[(start + i) % rest.size()]
		var pid := str(item.get("id", ""))
		if pid != "" and pid not in seats:
			seats.append(pid)
		i += 1
	return seats


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var wa := float(a.get("wf", 0.0))
	var wb := float(b.get("wf", 0.0))
	if not is_equal_approx(wa, wb):
		return wa > wb
	var da := float(a.get("dist", 0.0))
	var db := float(b.get("dist", 0.0))
	if not is_equal_approx(da, db):
		return da < db
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _pinned(ids: PackedStringArray) -> String:
	var gs = _node("GameState")
	var chapter: Dictionary = gs.chapter_def()
	var req = chapter.get("next_requires", null)
	if req == null or typeof(req) != TYPE_DICTIONARY:
		req = chapter.get("ending_requires", null)
	if req == null or typeof(req) != TYPE_DICTIONARY:
		return ""
	var must: Array = req.get("must_visit", [])
	for raw in must:
		var pid := str(raw)
		if pid in ids and not (pid in gs.visited_ports):
			return pid
	return ""
