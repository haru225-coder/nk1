class_name DrydockBerth
extends RefCounted
## 坞位一艘。帆、甲、添人只对着坞上这一艘。
## 换船不过日子、不花钱、不加名声。本章买得到的船全部留在坞外，不自动占坞。
## 本脚本不读钱、不推进日历；成功题签见 UiTransition.drydock_*。
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


## offers 是 ships.json 全表（ShipyardPage 原样交进来）。缺 unlock 视为第一章；for_sale 为 false 的船型
## （海寇快船 pirate_boat，只能夺船得来）哪一章都不上架——不在这里滤掉，第一章船屋就会把它摆出来。
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
		if not bool(row.get("for_sale", true)):
			continue
		if not reached.has(unlock):
			continue
		seen[sid] = true
		out.append(sid)
	return out
