## Optional sound-effect seam for the game loop.
##
## The repository intentionally ships without audio assets.  Callers can use the
## cue helpers now; they are silent until a stream is registered for that cue.
## This keeps transition/combat behavior deterministic in headless runs while
## leaving one small seam for a future audio pass.
extends RefCounted

const CUE_TRANSITION: StringName = &"transition"
const CUE_COMBAT_START: StringName = &"combat_start"
const CUE_COMBAT_FIRE: StringName = &"combat_fire"
const CUE_COMBAT_HIT: StringName = &"combat_hit"
const CUE_COMBAT_BOARD: StringName = &"combat_board"
const CUE_COMBAT_WIN: StringName = &"combat_win"
const CUE_COMBAT_LOSE: StringName = &"combat_lose"
const CUE_COMBAT_FLEE: StringName = &"combat_flee"

## Kept on by default so a caller can opt into registered streams without
## changing any gameplay code.  Set false for a silent accessibility mode.
static var enabled := true
static var _streams: Dictionary = {}


## Register an optional stream.  No call site needs to know whether a stream
## exists; missing cues are a deliberate no-op.
static func register_stream(cue: StringName, stream: AudioStream) -> void:
	if stream == null:
		_streams.erase(cue)
		return
	_streams[cue] = stream


static func clear_streams() -> void:
	_streams.clear()


static func has_stream(cue: StringName) -> bool:
	return _streams.get(cue) is AudioStream


## Play one registered cue under parent.  Returns null for the normal silent
## stub path, or the transient player when an asset has been registered.
static func play_cue(parent: Node, cue: StringName, volume_db := 0.0) -> AudioStreamPlayer:
	if not enabled or parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var stream := _streams.get(cue) as AudioStream
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


## Named seams keep gameplay call sites readable and make future SFX mapping
## explicit.  All seven helpers are silent until their cue is registered.
static func transition(parent: Node) -> AudioStreamPlayer:
	return play_cue(parent, CUE_TRANSITION, -5.0)


static func combat_start(parent: Node) -> AudioStreamPlayer:
	return play_cue(parent, CUE_COMBAT_START, -4.0)


static func combat_fire(parent: Node) -> AudioStreamPlayer:
	return play_cue(parent, CUE_COMBAT_FIRE, -7.0)


static func combat_hit(parent: Node) -> AudioStreamPlayer:
	return play_cue(parent, CUE_COMBAT_HIT, -8.0)


static func combat_board(parent: Node) -> AudioStreamPlayer:
	return play_cue(parent, CUE_COMBAT_BOARD, -4.0)


static func combat_result(parent: Node, outcome: String) -> AudioStreamPlayer:
	var cue := CUE_COMBAT_FLEE
	if outcome == "win":
		cue = CUE_COMBAT_WIN
	elif outcome == "lose":
		cue = CUE_COMBAT_LOSE
	return play_cue(parent, cue, -4.0)
