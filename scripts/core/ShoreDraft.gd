class_name ShoreDraft
extends RefCounted
## 今日岸开三处。牙行占第一席。船开不出去时船屋占下一席。
## 其余去处按 id 次序轮转。本脚本不在解析期写 autoload 名。


static func deal(facilities: Array, salt: int, pin_shipyard: bool) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for raw in facilities:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var fac: Dictionary = raw
		var fid := str(fac.get("id", ""))
		if fid == "" or fid in ids:
			continue
		ids.append(fid)
	var seats := PackedStringArray()
	if "city_market" in ids:
		seats.append("city_market")
	if pin_shipyard and "city_shipyard" in ids and "city_shipyard" not in seats:
		seats.append("city_shipyard")
	var rest: PackedStringArray = PackedStringArray()
	for fid in ids:
		if fid not in seats:
			rest.append(fid)
	rest.sort()
	if rest.is_empty():
		return seats
	var start := posmod(salt, rest.size())
	var i := 0
	while seats.size() < 3 and i < rest.size():
		var pick := rest[(start + i) % rest.size()]
		if pick not in seats:
			seats.append(pick)
		i += 1
	return seats
