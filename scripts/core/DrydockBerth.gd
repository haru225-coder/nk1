class_name DrydockBerth
extends RefCounted
## 坞位一艘。帆、甲、添人只对着坞上这一艘。
## 换船不过日子。本章买得到的船全部留在坞外。
## 本脚本不在解析期写 autoload 名。


static func berth_index(count: int, index: int) -> int:
	if count <= 0:
		return 0
	if index < 0:
		return 0
	if index >= count:
		return count - 1
	return index


static func other_hulls(count: int, index: int) -> PackedInt32Array:
	var on := berth_index(count, index)
	var out := PackedInt32Array()
	for n in count:
		if n == on:
			continue
		out.append(n)
	return out


static func sale_ids(offers: Array, reached: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for raw in offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var sid := str(row.get("id", ""))
		var unlock := str(row.get("unlock", "ch1"))
		if sid == "" or bool(seen.get(sid, false)):
			continue
		if not reached.has(unlock):
			continue
		seen[sid] = true
		out.append(sid)
	return out
