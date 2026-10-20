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
## beat instead of stacking into noise.  The spacing is kept per gap key
## (opts.gap_key, default the cue itself): the flagship's own broadside has its
## own key, so an enemy or escort volley a moment earlier cannot swallow it.
const _MIN_GAP_MS := {
	&"combat_fire": 90,
	&"combat_hit": 60,
}
const _MAX_VOICES := 6
## A voice whose end lies further ahead than this (ms) is stale: the probe
## clock was moved back.  No cue is anywhere near this long.
const _VOICE_STALE_MS := 60000
const _META := &"nk1_sfx"
## How many recent decisions `journal` keeps (oldest dropped first).
const JOURNAL_MAX := 64

## On by default; set false (or NK1_SFX=0) for a silent accessibility mode.
static var enabled := OS.get_environment("NK1_SFX") != "0"
## Global offset added to every cue's volume.
static var volume_db := 0.0
## Recent play_cue decisions, newest last: {ms, cue, hook, db, why}.  why "" =
## the cue sounded (headless counts as sounded: only the player is skipped);
## otherwise muted / no_tree / no_stream / gap / voices; "cut" marks an older
## voice of the same choke group stopped by a newer one.  Read by probes only.
static var journal: Array = []
## Probe clock: when >= 0, rate limits and the journal read this as "now" (ms)
## instead of Time.get_ticks_msec(), so a busy machine cannot flip a gap
## verdict.  Always -1 in the game.
static var clock_ms := -1
## Voices still sounding, oldest first: {cue, hook, group, until (ms), player}.  A cue takes
## its slot the moment it is granted and gives it back when its stream has run
## out (or its player is gone).  Players join the tree deferred, so counting
## the root's children missed every cue asked for in the same frame; headless
## keeps the same book, so the cap reads the same there.
static var _voices: Array = []
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
## opts.hook names the SfxCues hook that asked (kept in the journal);
## opts.gap_key picks whose spacing applies (default: the cue's own), and
## opts.gap_ms overrides how long that spacing is (SfxCues spaces its own hooks);
## opts.pitch plays the stream faster / slower (pitch_scale; the voice lasts
## length / pitch);
## opts.group is a choke group: a cue granted in a group stops the older voices
## of that group still ringing (a new ink-wipe bell cuts the one it replaced),
## so a bell never rings over its own echo.
static func play_cue(parent: Node, cue: StringName, cue_db := 0.0, opts := {}) -> AudioStreamPlayer:
	var hook: StringName = StringName(opts.get("hook", &""))
	var gap_key: StringName = StringName(opts.get("gap_key", cue))
	var group: StringName = StringName(opts.get("group", &""))
	var pitch := maxf(0.25, float(opts.get("pitch", 1.0)))
	var db := cue_db + volume_db
	if not enabled:
		return _refuse(cue, hook, db, "muted")
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return _refuse(cue, hook, db, "no_tree")
	var stream := stream_for(cue)
	if stream == null:
		return _refuse(cue, hook, db, "no_stream")
	var now := _now()
	var last := int(_last_ms.get(gap_key, -100000))
	if now >= last and now - last < int(opts.get("gap_ms", _MIN_GAP_MS.get(cue, 0))):  # last ahead of now: probe clock moved back
		return _refuse(cue, hook, db, "gap")
	_prune_voices(now)
	if group != &"":
		_choke(group)
	if _voices.size() >= _MAX_VOICES:
		return _refuse(cue, hook, db, "voices")
	_last_ms[gap_key] = now
	var voice := {"cue": cue, "hook": hook, "group": group,
		"until": now + int(ceil(stream.get_length() * 1000.0 / pitch)), "player": null}
	_voices.append(voice)
	_note(cue, hook, db, "")
	if DisplayServer.get_name() == "headless":
		return null
	var root := parent.get_tree().root
	var player := AudioStreamPlayer.new()
	voice["player"] = player
	player.set_meta(_META, cue)
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.autoplay = true
	player.finished.connect(player.queue_free)
	# Deferred: callers include _ready chains where root is busy adding children.
	root.add_child.call_deferred(player)
	if not _warming:
		_warming = true
		_warm_step(parent.get_tree())
	return player


## Journal a hook that SfxCues held back before any cue was asked for (switch
## off, hook-level spacing): {cue: &"", hook, why}.
static func skip(hook: StringName, why: String) -> void:
	_note(&"", hook, 0.0, why)


## "Now" in ms as the rate limits see it (the probe clock when set).
static func now_ms() -> int:
	return _now()


static func _refuse(cue: StringName, hook: StringName, db: float, why: String) -> AudioStreamPlayer:
	_note(cue, hook, db, why)
	return null


## Stop the voices of `group` still ringing; each leaves a "cut" row.
static func _choke(group: StringName) -> void:
	var keep: Array = []
	for v in _voices:
		if StringName(v["group"]) != group:
			keep.append(v)
			continue
		var p: Variant = v["player"]
		if typeof(p) == TYPE_OBJECT and is_instance_valid(p):
			var ap := p as AudioStreamPlayer
			ap.autoplay = false  # may still be waiting for its deferred add_child
			ap.stop()
			ap.queue_free()
		_note(v["cue"], v["hook"], 0.0, "cut")
	_voices = keep


## Voices still holding a slot at `now`.
static func voices_now() -> int:
	_prune_voices(_now())
	return _voices.size()


static func _prune_voices(now: int) -> void:
	var keep: Array = []
	for v in _voices:
		var until := int(v["until"])
		var p: Variant = v["player"]
		if until <= now or until - now > _VOICE_STALE_MS:
			continue
		if typeof(p) == TYPE_OBJECT and not is_instance_valid(p):
			continue  # its player finished and freed itself
		keep.append(v)
	_voices = keep


static func _now() -> int:
	return clock_ms if clock_ms >= 0 else Time.get_ticks_msec()


static func _note(cue: StringName, hook: StringName, db: float, why: String) -> void:
	journal.append({"ms": _now(), "cue": cue, "hook": hook, "db": db, "why": why})
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
