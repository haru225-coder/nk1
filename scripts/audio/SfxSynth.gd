## Tiny procedural SFX bank for AudioHooks.
##
## Every cue is synthesized once into a short mono 16-bit AudioStreamWAV
## (22.05 kHz, < 1 s) from sines, fixed-seed noise and one-pole filters, so the
## repository still ships no audio files and no third-party samples.  Output is
## deterministic: the same cue always yields the same bytes.
extends RefCounted

const MIX_RATE := 22050
const _PEAK := 0.82  # headroom below full scale after normalization

static var _cache: Dictionary = {}


## Cached stream for cue, or null when the cue has no recipe.
static func stream_for(cue: StringName) -> AudioStreamWAV:
	if _cache.has(cue):
		return _cache[cue]
	var pcm := _render(cue)
	if pcm.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = _to_s16(pcm)
	_cache[cue] = wav
	return wav


static func is_cached(cue: StringName) -> bool:
	return _cache.has(cue)


static func clear_cache() -> void:
	_cache.clear()


static func _render(cue: StringName) -> PackedFloat32Array:
	match String(cue):
		"transition":
			return _transition()
		"combat_start":
			return _war_drum()
		"combat_fire":
			return _cannon()
		"combat_hit":
			return _timber_crack()
		"combat_board":
			return _grapple_clash()
		"combat_win":
			return _chime([392.0, 440.0, 587.33], 0.16, 0.55)  # G4 A4 D5，徵→羽→商
		"combat_lose":
			return _chime([293.66, 220.0], 0.26, 0.6)  # D4 → A3 下行
		"combat_flee":
			return _flee_swish()
	return PackedFloat32Array()


# ── recipes ─────────────────────────────────────────────

## 墨幕过渡：一声轻磬（带非谐泛音的衰减正弦）叠一缕低通风声。
static func _transition() -> PackedFloat32Array:
	var buf := _buffer(0.9)
	_add_bell(buf, 0.0, 523.25, 0.85, 0.5)
	var wind := _noise(buf.size(), 11)
	_lowpass(wind, 900.0)
	for i in buf.size():
		var t := float(i) / MIX_RATE
		buf[i] += wind[i] * 0.35 * _swell(t, 0.9)
	return _finish(buf)


## 入战：两记战鼓（下滑低频 + 起音噪声）。
static func _war_drum() -> PackedFloat32Array:
	var buf := _buffer(0.8)
	_add_drum(buf, 0.0, 1.0)
	_add_drum(buf, 0.3, 0.85)
	return _finish(buf)


## 开炮：低频闷响 + 低通爆裂噪声。
static func _cannon() -> PackedFloat32Array:
	var buf := _buffer(0.55)
	var burst := _noise(buf.size(), 23)
	_lowpass(burst, 1400.0)
	var phase := 0.0
	for i in buf.size():
		var t := float(i) / MIX_RATE
		var f := lerpf(38.0, 85.0, exp(-t * 14.0))
		phase += TAU * f / MIX_RATE
		buf[i] = sin(phase) * exp(-t * 7.0) + burst[i] * 1.4 * exp(-t * 16.0)
	return _finish(buf)


## 命中：船板碎裂，短促带通噪声 + 一记木质低鸣。
static func _timber_crack() -> PackedFloat32Array:
	var buf := _buffer(0.2)
	var n := _noise(buf.size(), 37)
	var low := n.duplicate()
	_lowpass(low, 2600.0)
	_lowpass(n, 700.0)
	for i in buf.size():
		var t := float(i) / MIX_RATE
		buf[i] = (low[i] - n[i]) * 1.6 * exp(-t * 38.0) + sin(TAU * 180.0 * t) * 0.4 * exp(-t * 30.0)
	return _finish(buf)


## 接舷：钩索落舷的一声闷撞，随后两下金铁相击。
static func _grapple_clash() -> PackedFloat32Array:
	var buf := _buffer(0.7)
	var thud := _noise(buf.size(), 41)
	_lowpass(thud, 500.0)
	for i in buf.size():
		var t := float(i) / MIX_RATE
		buf[i] = thud[i] * 1.5 * exp(-t * 20.0)
	_add_bell(buf, 0.12, 1320.0, 0.3, 0.35)
	_add_bell(buf, 0.26, 1580.0, 0.25, 0.3)
	return _finish(buf)


## 撤离：由高到低掠过的风声。
static func _flee_swish() -> PackedFloat32Array:
	var buf := _buffer(0.55)
	var n := _noise(buf.size(), 53)
	var y := 0.0
	for i in buf.size():
		var t := float(i) / MIX_RATE
		var a := _alpha(lerpf(2200.0, 300.0, t / 0.55))
		y += a * (n[i] - y)
		buf[i] = y * _swell(t, 0.55)
	return _finish(buf)


## 结算：几记磬音依次敲出。
static func _chime(freqs: Array, step: float, decay: float) -> PackedFloat32Array:
	var buf := _buffer(step * (freqs.size() - 1) + decay * 1.6)
	for k in freqs.size():
		_add_bell(buf, step * k, freqs[k], decay, 0.55)
	return _finish(buf)


# ── primitives ──────────────────────────────────────────

static func _buffer(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * MIX_RATE))
	return buf


## Bell/磬-like partials (1, 2.76, 5.4) with a soft 4 ms attack.  Each partial
## is a rotating phasor with a multiplicative decay, so the inner loop needs no
## sin()/exp() calls (keeps first-play synthesis to a few ms).
static func _add_bell(buf: PackedFloat32Array, at: float, freq: float, decay: float, gain: float) -> void:
	var start := int(at * MIX_RATE)
	var ratios := [1.0, 2.76, 5.4]
	var amps := [1.0, 0.45, 0.2]
	var attack := 0.004 * MIX_RATE
	for p in ratios.size():
		var w: float = TAU * freq * ratios[p] / MIX_RATE
		var cw := cos(w)
		var sw := sin(w)
		var k := exp(-(1.0 + p) / (decay * MIX_RATE))
		var re := 0.0
		var im: float = amps[p] * gain
		for i in range(start, buf.size()):
			var n := i - start
			buf[i] += im * (minf(n / attack, 1.0) if n < attack else 1.0)
			var r2 := (re * cw - im * sw) * k
			im = (re * sw + im * cw) * k
			re = r2
			if absf(im) + absf(re) < 1e-5:
				break


static func _add_drum(buf: PackedFloat32Array, at: float, gain: float) -> void:
	var start := int(at * MIX_RATE)
	var n := _noise(buf.size() - start, 61 + start)
	_lowpass(n, 1800.0)
	var phase := 0.0
	for i in range(start, buf.size()):
		var t := float(i - start) / MIX_RATE
		phase += TAU * lerpf(52.0, 115.0, exp(-t * 22.0)) / MIX_RATE
		buf[i] += (sin(phase) * exp(-t * 9.0) + n[i - start] * 0.6 * exp(-t * 45.0)) * gain


static func _noise(count: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	out.resize(maxi(count, 0))
	for i in out.size():
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


static func _alpha(cutoff_hz: float) -> float:
	return 1.0 - exp(-TAU * cutoff_hz / MIX_RATE)


static func _lowpass(buf: PackedFloat32Array, cutoff_hz: float) -> void:
	var a := _alpha(cutoff_hz)
	var y := 0.0
	for i in buf.size():
		y += a * (buf[i] - y)
		buf[i] = y


## Rise over the first 30 % then fall to zero at length.
static func _swell(t: float, length: float) -> float:
	var u := clampf(t / length, 0.0, 1.0)
	return sin(PI * pow(u, 0.6))


## Normalize, add 5 ms fade-in/out to avoid clicks.
static func _finish(buf: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var scale := _PEAK / peak if peak > 0.0 else 0.0
	var edge := int(0.005 * MIX_RATE)
	for i in buf.size():
		var g := scale
		if i < edge:
			g *= float(i) / edge
		elif i > buf.size() - edge:
			g *= float(buf.size() - i) / edge
		buf[i] *= g
	return buf


static func _to_s16(buf: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return bytes
