class_name SfxSynth
extends RefCounted
## WHAT THIS IS: a tiny synthesizer: the maths that makes the game's sound
## effects out of simple tones and hiss, so the game needs no sound files.
##
## HOW IT WORKS: a digital sound is a long list of numbers between -1 and 1
## ("samples"), RATE of them for every second. Played one after another,
## they push the speaker back and forth.
##   - tone() makes one note: a wave shape (sine, square, saw or triangle)
##     at a pitch (a frequency in Hz: waves per second) that can slide up
##     or down while it plays.
##   - noise() makes a burst of hiss from random numbers, with the deep
##     rumble filtered out.
##   - envelope() shapes the loudness: a very fast rise (12 ms) and then a
##     smooth fade to silence, so a sound starts without a click and dies
##     away.
##   - bake() adds the layers together and packs them into a sound Godot
##     can play (16-bit, mono).
##
## WHO USES IT: Sfx._ready() calls bake(), tone() and noise() to make every
## sound once at startup. All functions are "static": they belong to the
## class itself and are called as SfxSynth.tone(...), without making an
## object first.
##
## noise() takes its random numbers from the RandomNumberGenerator it is
## given (Sfx passes its own), never from the game's shared sequence.

## Samples per second: how finely the sounds are cut into numbers (22,050
## is half of CD quality, plenty for short beeps).
const RATE := 22050


## How loud a sound is at time `t` (seconds from its start), for a sound
## `dur` seconds long whose top loudness is `peak` (0..1). It rises from
## almost nothing (0.0001) to the peak in the first 12 ms, then falls back
## to 0.0001 at `dur`; after `dur` it is silent (0). Both the rise and the
## fall are "exponential": every moment multiplies the loudness by the
## same amount, which sounds even to our ears. A peak below 0.001 counts
## as 0.001.
static func envelope(t: float, dur: float, peak: float) -> float:
	var floor_v := 0.0001
	var top := maxf(0.001, peak)
	# The rise: the first 12 ms.
	if t < 0.012:
		return floor_v * pow(top / floor_v, t / 0.012)
	# Past the end: silence.
	if t >= dur:
		return 0.0
	# The fall: from the top down to almost nothing at `dur`.
	return top * pow(floor_v / top, (t - 0.012) / maxf(0.001, dur - 0.012))


## One note, `dur` seconds long plus 20 ms of silence at the end. `freq` is
## the starting pitch (Hz). `slide` (Hz) bends the pitch smoothly to
## freq + slide by the end of the note (never below 40 Hz); 0 keeps it
## steady. `wave` is "sine" (soft), "square" (buzzy), "saw" (raspy) or
## anything else for a triangle (in between). `peak` is the top loudness
## (0..1). Returns the samples.
static func tone(freq: float, dur: float, wave: String, peak: float, slide: float) -> PackedFloat32Array:
	# Step 1: room for every sample, and the pitch at the end of the slide.
	var n := int(RATE * (dur + 0.02))
	var out := PackedFloat32Array()
	out.resize(n)
	var end_freq := maxf(40.0, freq + slide)
	# `phase` is how far along the current wave we are, from 0 to 1.
	var phase := 0.0
	for i in n:
		# Step 2: the pitch right now. A slide multiplies the pitch by the
		# same amount every moment until `dur`, then it stays put.
		var t := float(i) / RATE
		var f := freq if slide == 0.0 else freq * pow(end_freq / freq, minf(1.0, t / dur))
		# Step 3: move along the wave; after 1 it starts again from 0.
		phase += f / RATE
		phase -= floorf(phase)
		# Step 4: the wave's height (-1..1) at this point of its shape.
		var v := 0.0
		match wave:
			"sine":
				v = sin(phase * TAU)
			"square":
				v = 1.0 if phase < 0.5 else -1.0
			"saw":
				v = phase * 2.0 - 1.0
			_:
				v = 1.0 - 4.0 * absf(phase - 0.5)
		# Step 5: times the loudness shape.
		out[i] = v * envelope(t, dur, peak)
	return out


## A burst of hiss `dur` seconds long whose top loudness is `peak` (0..1).
## The random values also fade out evenly over the length. A "high-pass"
## filter at 400 Hz (it lets high sounds through and holds back low ones)
## removes the deep rumble, so only the bright hiss is left. Takes one
## random number from `rng` per sample. Returns the samples.
static func noise(dur: float, peak: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Step 1: room for every sample.
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	# Step 2: the filter's strength. This is the simplest high-pass, copied
	# from an electric circuit with a resistor and a capacitor ("RC"); it
	# remembers the last input and output sample.
	var rc := 1.0 / (TAU * 400.0)
	var dt := 1.0 / RATE
	var alpha := rc / (rc + dt)
	var prev_x := 0.0
	var prev_y := 0.0
	for i in n:
		# Step 3: a random value from -1 to 1, fading out over the length.
		var x := (rng.randf() * 2.0 - 1.0) * (1.0 - float(i) / float(n))
		# Step 4: filter it, then apply the loudness shape.
		var y := alpha * (prev_y + x - prev_x)
		prev_x = x
		prev_y = y
		out[i] = y * envelope(float(i) / RATE, dur, peak)
	return out


## Mix `layers` (lists of samples from tone() and noise()) into one sound
## Godot can play. It lasts `dur` seconds or as long as the longest layer,
## whichever is longer. The layers are added together, cut off at -1..1,
## and stored as 16-bit whole numbers (-32767..32767, two bytes each) at
## RATE samples per second, mono (one channel).
static func bake(dur: float, layers: Array) -> AudioStreamWAV:
	# Step 1: how many samples the sound needs.
	var n := int(RATE * dur)
	for layer: PackedFloat32Array in layers:
		n = maxi(n, layer.size())
	# Step 2: add the layers up, sample by sample, and pack each sum into
	# two bytes.
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := 0.0
		for layer: PackedFloat32Array in layers:
			if i < layer.size():
				v += layer[i]
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	# Step 3: wrap the bytes as a sound Godot can play.
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s
