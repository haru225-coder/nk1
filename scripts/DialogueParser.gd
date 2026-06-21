class_name DialogueParser extends RefCounted

const SPEAKER_TO_NPC: Dictionary = {
	"先生": "teacher",
	"陈子龙": "chen_wenlong",
	"林伯渊": "lin_boyuan",
	"贾府门生": "jia_disciple",
	"市舶司小吏": "customs_official",
	"阿巴斯": "abbas",
	"凯达格兰老人": "ketagalan_elder",
	"凯达格兰孩子": "ketagalan_child",
}

static var _npc_by_id: Dictionary = {}
static var _npc_by_name: Dictionary = {}
static var _npc_cache_generation: int = -1

static func parse_body(body: String) -> Array:
	var beats: Array = []
	if body.strip_edges() == "":
		return beats
	var paragraphs: PackedStringArray = body.split("\n\n", false)
	for raw in paragraphs:
		var p: String = raw.strip_edges()
		if p.is_empty():
			continue
		for line in p.split("\n", false):
			var chunk: String = line.strip_edges()
			if chunk.is_empty():
				continue
			beats.append_array(_parse_chunk(chunk))
	return beats

static func _parse_chunk(chunk: String) -> Array:
	if chunk.begins_with("【"):
		return _parse_speaker_line(chunk)
	if _is_pause_line(chunk):
		return [_pause_beat()]
	return [_narration_beat(chunk)]

static func _is_pause_line(text: String) -> bool:
	var t := text.strip_edges()
	if t in ["……", "...", "—", "——", "―"]:
		return true
	return t.replace("…", "").replace(".", "").strip_edges() == ""

static func _pause_beat() -> Dictionary:
	return _narration_beat("……")

static func _narration_beat(text: String) -> Dictionary:
	var t := text.strip_edges()
	if not t.begins_with("　") and t != "……":
		t = "　　" + t
	return {
		"speaker": "",
		"display_name": "",
		"text": t,
		"is_narration": true,
		"npc_id": "",
		"stage_direction": "",
	}

static func _parse_speaker_line(line: String) -> Array:
	var colon_idx := line.find("：")
	if colon_idx < 0:
		colon_idx = line.find(":")
	if colon_idx < 2:
		return []
	var speaker: String = line.substr(1, colon_idx - 2).strip_edges()
	var remainder: String = line.substr(colon_idx + 1).strip_edges()
	var stage_direction := ""
	if remainder.begins_with("（"):
		var close_idx := remainder.find("）")
		if close_idx > 0:
			stage_direction = remainder.substr(1, close_idx - 1).strip_edges()
			remainder = remainder.substr(close_idx + 1).strip_edges()
	elif remainder.begins_with("("):
		var close_idx := remainder.find(")")
		if close_idx > 0:
			stage_direction = remainder.substr(1, close_idx - 1).strip_edges()
			remainder = remainder.substr(close_idx + 1).strip_edges()
	var npc_id: String = SPEAKER_TO_NPC.get(speaker, "")
	var clauses := _split_speech_clauses(remainder)
	if clauses.is_empty():
		clauses = [format_speech(remainder)]
	var beats: Array = []
	for clause in clauses:
		beats.append({
			"speaker": speaker,
			"display_name": speaker,
			"text": clause,
			"is_narration": false,
			"npc_id": npc_id,
			"stage_direction": stage_direction if beats.is_empty() else "",
		})
	return beats

static func _split_speech_clauses(text: String) -> Array:
	var t := text.strip_edges()
	if t.is_empty():
		return []
	var inner := t
	if inner.begins_with("「") and inner.ends_with("」"):
		inner = inner.substr(1, inner.length() - 2).strip_edges()
	elif inner.begins_with("『") and inner.ends_with("』"):
		inner = inner.substr(1, inner.length() - 2).strip_edges()
	var sentences := _split_sentences(inner)
	if sentences.is_empty():
		return [format_speech(t)]
	var out: Array = []
	for sentence in sentences:
		out.append(format_speech(sentence))
	return out

static func format_speech(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return t
	if t.begins_with("「") or t.begins_with("『"):
		return t
	return "「" + t + "」"

static func _split_sentences(text: String) -> Array:
	var sentences: Array = []
	var buf := ""
	var i := 0
	while i < text.length():
		var ch: String = text[i]
		buf += ch
		if ch in "。！？":
			sentences.append(buf.strip_edges())
			buf = ""
		elif ch == "…":
			if i + 1 < text.length() and text[i + 1] == "…":
				buf += "…"
				i += 1
				sentences.append(buf.strip_edges())
				buf = ""
		i += 1
	if buf.strip_edges() != "":
		sentences.append(buf.strip_edges())
	return sentences

static func beat_from_text(text: String, speaker: String = "", npc_id: String = "") -> Dictionary:
	if speaker == "":
		return _narration_beat(text)
	return {
		"speaker": speaker,
		"display_name": speaker,
		"text": format_speech(text),
		"is_narration": false,
		"npc_id": npc_id,
		"stage_direction": "",
	}

static func _ensure_npc_cache() -> void:
	var gen := GameManager.npcs_data.hash()
	if gen == _npc_cache_generation and not _npc_by_id.is_empty():
		return
	_npc_by_id.clear()
	_npc_by_name.clear()
	for n in GameManager.npcs_data.get("npcs", []):
		var id: String = n.get("id", "")
		var name: String = n.get("name", "")
		if id != "":
			_npc_by_id[id] = n
		if name != "":
			_npc_by_name[name] = n
	_npc_cache_generation = gen

static func resolve_avatar(beat: Dictionary) -> String:
	_ensure_npc_cache()
	var npc_id: String = beat.get("npc_id", "")
	if npc_id != "" and _npc_by_id.has(npc_id):
		var n: Dictionary = _npc_by_id[npc_id]
		return AssetPlaceholder.resolve_avatar(npc_id, n.get("avatar", ""))
	var speaker: String = beat.get("speaker", "")
	if speaker != "" and _npc_by_name.has(speaker):
		var n: Dictionary = _npc_by_name[speaker]
		return AssetPlaceholder.resolve_avatar(n.get("id", ""), n.get("avatar", ""))
	return AssetPlaceholder.resolve_avatar(npc_id, "")