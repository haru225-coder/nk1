class_name IntelNotes extends RefCounted

## 玩家已购情报账本（信息差）：付费得知的预告事件，供市集/三策读取。

const MAX_NOTES := 12

## notes: {port_id, port_name, event_type, event_label, days_left, tier, summary, source}
var notes: Array = []


func record(note: Dictionary) -> void:
	if note.is_empty():
		return
	# 同 port+type 升级覆盖
	var port_id := str(note.get("port_id", ""))
	var etype := str(note.get("event_type", ""))
	var replaced := false
	for i in notes.size():
		var n: Dictionary = notes[i]
		if str(n.get("port_id", "")) == port_id and str(n.get("event_type", "")) == etype:
			if int(note.get("tier", 0)) >= int(n.get("tier", 0)):
				notes[i] = note.duplicate(true)
			replaced = true
			break
	if not replaced:
		notes.append(note.duplicate(true))
	while notes.size() > MAX_NOTES:
		notes.pop_front()


func clear() -> void:
	notes.clear()


func list_recent(limit: int = 5) -> Array:
	if notes.is_empty():
		return []
	var start := maxi(0, notes.size() - limit)
	return notes.slice(start)


func for_port(port_id: String) -> Array:
	var out: Array = []
	for n in notes:
		if str(n.get("port_id", "")) == port_id:
			out.append(n)
	return out


func has_any() -> bool:
	return not notes.is_empty()


func to_dict() -> Dictionary:
	return {"notes": notes.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	notes.clear()
	if d == null or not (d is Dictionary):
		return
	for raw in d.get("notes", []):
		if raw is Dictionary:
			notes.append((raw as Dictionary).duplicate(true))


## 从酒馆传闻 + 档位生成可读情报
static func build_from_rumor(rumor: Dictionary, tier: int) -> Dictionary:
	var days_left: int = int(rumor.get("days_left", 7))
	var port_name := str(rumor.get("port_name", "某港"))
	var etype := str(rumor.get("type", "unknown"))
	var event = rumor.get("event")
	var port_id := ""
	var event_id := ""
	if event != null:
		if typeof(event) == TYPE_OBJECT:
			if "target_port" in event:
				port_id = str(event.target_port)
			if "event_id" in event:
				event_id = str(event.event_id)
		elif event is Dictionary:
			port_id = str(event.get("target_port", ""))
			event_id = str(event.get("event_id", ""))
	var label := event_type_label(etype if etype != "" else event_id)
	var summary := ""
	match clampi(tier, 1, 3):
		1:
			summary = "风闻某处港口将有变故，方向未明，约数日之内。"
			port_name = "未知港口"
			port_id = ""
		2:
			var lo := maxi(1, days_left - 2)
			var hi := days_left + 3
			summary = "南边某港大约 %d～%d 日内或有「%s」类动静。" % [lo, hi, label]
			# 仍不点名港口
			port_name = "某港（未点名）"
			port_id = ""
		3:
			var lo := maxi(1, days_left - 1)
			var hi := days_left + 2
			summary = "【确报】%s 约 %d～%d 日内恐有「%s」。宜决定：立刻布局、观望，或改航。" % [
				port_name, lo, hi, label
			]
		_:
			summary = "零碎耳语，难成定论。"
	return {
		"port_id": port_id,
		"port_name": port_name,
		"event_type": etype if etype != "" else event_id,
		"event_label": label,
		"days_left": days_left,
		"tier": tier,
		"summary": summary,
		"source": "tavern",
	}


static func event_type_label(etype: String) -> String:
	match etype:
		"disaster", "trade_disaster":
			return "市舶灾变"
		"recovery", "trade_recovery":
			return "市舶回暖"
		"pirate", "pirate_attack":
			return "海寇侵扰"
		"shortage", "supply_shortage":
			return "货源紧缺"
		"boom", "trade_boom":
			return "贸易繁荣"
		"ripple", "economic_ripple":
			return "商情涟漪"
		_:
			return "市舶异动"


static func format_notes_block(notes_arr: Array, limit: int = 3) -> String:
	if notes_arr.is_empty():
		return ""
	var lines: PackedStringArray = ["【已知情报】"]
	var start := maxi(0, notes_arr.size() - limit)
	for i in range(start, notes_arr.size()):
		var n: Dictionary = notes_arr[i]
		var star := "★".repeat(clampi(int(n.get("tier", 1)), 1, 3))
		lines.append("%s %s" % [star, str(n.get("summary", ""))])
	return "\n".join(lines)
