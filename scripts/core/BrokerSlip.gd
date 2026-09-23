class_name BrokerSlip
extends RefCounted
## 柜上三样。舱里有货占第一席，最便宜的土产占下一席。
## 其余按买价从低到高轮转。本脚本不在解析期写 autoload 名。


static func deal(goods: Array, salt: int, held_id: String) -> PackedStringArray:
	var rows: Array = []
	var seen := {}
	for raw in goods:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var gid := str(row.get("id", ""))
		if gid == "" or seen.has(gid):
			continue
		seen[gid] = true
		rows.append({
			"id": gid,
			"role": str(row.get("role", "")),
			"buy": int(row.get("buy", 0)),
		})
	var seats := PackedStringArray()
	if held_id != "" and seen.has(held_id):
		seats.append(held_id)
	var origins: Array = []
	var rest: Array = []
	for raw_row in rows:
		var item: Dictionary = raw_row
		var item_id := str(item.get("id", ""))
		if item_id in seats:
			continue
		if str(item.get("role", "")) == "origin":
			origins.append(item)
		else:
			rest.append(item)
	origins.sort_custom(_before)
	if not origins.is_empty():
		var top: Dictionary = origins[0]
		var origin_id := str(top.get("id", ""))
		if origin_id != "":
			seats.append(origin_id)
		for extra in origins:
			var extra_row: Dictionary = extra
			var extra_id := str(extra_row.get("id", ""))
			if extra_id != origin_id:
				rest.append(extra_row)
	rest.sort_custom(_before)
	if rest.is_empty():
		return seats
	var start := posmod(salt, rest.size())
	var i := 0
	while seats.size() < 3 and i < rest.size():
		var pick: Dictionary = rest[(start + i) % rest.size()]
		var pick_id := str(pick.get("id", ""))
		if pick_id != "" and pick_id not in seats:
			seats.append(pick_id)
		i += 1
	return seats


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ba := int(a.get("buy", 0))
	var bb := int(b.get("buy", 0))
	if ba != bb:
		return ba < bb
	return str(a.get("id", "")) < str(b.get("id", ""))
