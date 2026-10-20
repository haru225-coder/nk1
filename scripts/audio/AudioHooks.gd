## Thin sound-effect seam for the game loop.
##
## Each cue plays a short procedural sound from SfxSynth (no audio files, no
## third-party samples).  A stream registered via register_stream() wins over
## the synthesized default, so a later audio pass can drop in real assets
## without touching call sites.  Gameplay code does not call this file
## directly: every place that makes a sound goes through the hook table in
## SfxCues.gd (lane w54-audio), which names the cue and its volume.
##
## Mute: `AudioHooks.enabled = false` (runtime), or launch with the environment
## variable NK1_SFX=0.  `volume_db` offsets every cue.  Headless runs never
## create players (the synth still builds), so smoke/tool scripts stay silent
## and deterministic; the decision is still written to `journal`, so probes can
## tell whether a hook fired and why it stayed quiet.
extends RefCounted

const _SYNTH := preload("res://scripts/audio/SfxSynth.gd")

const CUE_TRANSITION: StringName = &"transition"
const CUE_COMBAT_START: StringName = &"combat_start"
const CUE_COMBAT_FIRE: StringName = &"combat_fire"
const CUE_COMBAT_HIT: StringName = &"combat_hit"
const CUE_COMBAT_BOARD: StringName = &"combat_board"
const CUE_COMBAT_WIN: StringName = &"combat_win"
const CUE_COMBAT_LOSE: StringName = &"combat_lose"
const CUE_COMBAT_FLEE: StringName = &"combat_flee"

## Per-cue minimum spacing (ms) so a broadside or a hail of hits reads as one
## beat instead of stacking into noise.
const _MIN_GAP_MS := {
	&"combat_fire": 90,
	&"combat_hit": 60,
}
const _MAX_VOICES := 6
const _META := &"nk1_sfx"
## How many recent decisions `journal` keeps (oldest dropped first).
const JOURNAL_MAX := 64

## On by default; set false (or NK1_SFX=0) for a silent accessibility mode.
static var enabled := OS.get_environment("NK1_SFX") != "0"
## Global offset added to every cue's volume.
static var volume_db := 0.0
## Recent play_cue decisions, newest last: {ms, cue, hook, db, why}.  why "" =
## the cue sounded (headless counts as sounded: only the player is skipped);
## otherwise muted / no_tree / no_stream / gap / voices.  Read by probes only.
static var journal: Array = []
static var _streams: Dictionary = {}
static var _last_ms: Dictionary = {}
static var _warming := false


## Register an override stream.  Passing null restores the synthesized default.
static func register_stream(cue: StringName, stream: AudioStream) -> void:
	if stream == null:
		_streams.erase(cue)
		return
	_streams[cue] = stream


static func clear_streams() -> void:
	_streams.clear()


static func has_stream(cue: StringName) -> bool:
	return stream_for(cue) != null


## Override stream if registered, else the procedural default (null if unknown).
static func stream_for(cue: StringName) -> AudioStream:
	var stream := _streams.get(cue) as AudioStream
	if stream == null:
		stream = _SYNTH.stream_for(cue)
	return stream


## Play one cue.  The transient player hangs off the scene tree root so it
## outlives the caller (WorldMap frees itself right after the result cue, Main
## swaps pages under the transition); it frees itself when finished.  Returns
## null when muted, headless, rate-limited or over the voice cap.
## opts.hook names the SfxCues hook that asked (kept in the journal).
static func play_cue(parent: Node, cue: StringName, cue_db := 0.0, opts := {}) -> AudioStreamPlayer:
	var hook: StringName = StringName(opts.get("hook", &""))
	var db := cue_db + volume_db
	if not enabled:
		return _refuse(cue, hook, db, "muted")
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return _refuse(cue, hook, db, "no_tree")
	var stream := stream_for(cue)
	if stream == null:
		return _refuse(cue, hook, db, "no_stream")
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(cue, -100000)) < int(_MIN_GAP_MS.get(cue, 0)):
		return _refuse(cue, hook, db, "gap")
	var root := parent.get_tree().root
	var voices := 0
	for child in root.get_children():
		if child.has_meta(_META):
			voices += 1
	if voices >= _MAX_VOICES:
		return _refuse(cue, hook, db, "voices")
	_last_ms[cue] = now
	_note(cue, hook, db, "")
	if DisplayServer.get_name() == "headless":
		return null
	var player := AudioStreamPlayer.new()
	player.set_meta(_META, cue)
	player.stream = stream
	player.volume_db = db
	player.autoplay = true
	player.finished.connect(player.queue_free)
	# Deferred: callers include _ready chains where root is busy adding children.
	root.add_child.call_deferred(player)
	if not _warming:
		_warming = true
		_warm_step(parent.get_tree())
	return player


static func _refuse(cue: StringName, hook: StringName, db: float, why: String) -> AudioStreamPlayer:
	_note(cue, hook, db, why)
	return null


static func _note(cue: StringName, hook: StringName, db: float, why: String) -> void:
	journal.append({"ms": Time.get_ticks_msec(), "cue": cue, "hook": hook, "db": db, "why": why})
	if journal.size() > JOURNAL_MAX:
		journal.pop_front()


## After the first audible cue, synthesize the remaining defaults one per frame
## so later cues (result chimes are the costliest) never hitch on first use.
static func _warm_step(tree: SceneTree) -> void:
	if tree == null:
		return
	for cue in [CUE_COMBAT_START, CUE_COMBAT_FIRE, CUE_COMBAT_HIT, CUE_COMBAT_BOARD,
			CUE_COMBAT_WIN, CUE_COMBAT_LOSE, CUE_COMBAT_FLEE, CUE_TRANSITION]:
		if not _SYNTH.is_cached(cue):
			tree.process_frame.connect(func():
				_SYNTH.stream_for(cue)
				_warm_step(tree), CONNECT_ONE_SHOT)
			return
