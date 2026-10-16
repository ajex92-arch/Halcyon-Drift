class_name Sfx
extends Node
## WHAT THIS IS: the sound player. It plays the short beeps, zaps and booms
## of the match (shots, hits, explosions, button clicks). There are no
## sound files: every sound is made by maths when the game starts (ported
## from version 1 of the game).
##
## HOW IT WORKS:
##   1. _ready() makes 14 "voices" (AudioStreamPlayer nodes; each plays one
##      sound at a time) and builds ("bakes") every sound once from simple
##      tones and hiss, using SfxSynth.
##   2. The simulation sends Events.cue(name, pos) whenever something makes
##      a noise. _on_cue() plays the ones the player would hear: on or near
##      the screen, not hidden in the fog of war, and louder near the middle
##      of the view (_gain_at). Cues at Vector2.ZERO are interface sounds
##      and are always heard. Unknown cue names are ignored.
##   3. Noisy cue names have a short minimum gap between two plays
##      (MIN_GAP), so a 30-ship brawl doesn't turn into noise.
##   4. The voices take turns; when all 14 are busy, the sound that started
##      longest ago is cut off to play the new one.
##
## WHO USES IT: main.gd makes one only when there is a window (and the HUD
## scene exists) and calls setup(world). It listens to Events.cue, which
## weapons, combat, effects, ships, the mothership and the hangar send.
##
## To add a sound: bake it in _ready() under the cue name the simulation
## sends.
##
## Note: the hiss sounds and the small random pitch changes use Sfx's own
## random numbers (_rng), never the game's shared random sequence. So
## sounds can't change the match: with or without a window, the same
## --seed plays the same match.

## How loud all sounds are, as a 0..1 share of full volume.
const MASTER := 0.22
## How many sounds can play at the same time.
const VOICES := 14
## The smallest gap (seconds of real time) between two plays of the same
## cue. Cues not listed here have no gap.
const MIN_GAP := {"fire": 0.06, "pd": 0.08, "flak": 0.08, "shell": 0.1, "torp": 0.12, "hit": 0.05,
	"shield_hit": 0.05, "boom": 0.08, "bump": 0.2}

## The running match (for the camera, the fog and the viewing team). Set
## by setup().
var world: World = null
## The baked sounds: cue name -> sound (AudioStreamWAV).
var _streams := {}
## The voices (sound player nodes), used in turn.
var _players: Array[AudioStreamPlayer] = []
## Which voice plays the next sound (an index into _players).
var _next := 0
## When each cue name last played: cue name -> seconds since the game
## started (real time, not match time).
var _last := {}
## Sfx's own random numbers (hiss and pitch changes). _ready() seeds it, so
## the sounds are the same every run.
var _rng := RandomNumberGenerator.new()


## Godot calls this when Sfx is added to the game. Make the voices, bake
## every sound, and start listening for cues. The hiss layers take their
## random numbers from _rng in bake order, so keep the order to keep the
## same sounds.
func _ready() -> void:
	# Step 1: the voices.
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Step 2: bake the sounds, with our random numbers started from the same
	# seed every run. Each one is a length in seconds and a list of
	# layers that are mixed together:
	#   SfxSynth.tone(pitch in Hz, length s, wave shape, loudness 0..1,
	#                 pitch slide in Hz)
	#   SfxSynth.noise(length s, loudness 0..1, random numbers)   (hiss)
	# Weapons: "fire" (bolts, lances and every other weapon kind without a
	# sound of its own), point defence, torpedo, flak, shell.
	_rng.seed = 1
	_streams["fire"] = SfxSynth.bake(0.09, [SfxSynth.tone(560.0, 0.07, "square", 0.08, -300.0)])
	_streams["pd"] = SfxSynth.bake(0.05, [SfxSynth.tone(900.0, 0.04, "square", 0.04, -200.0)])
	_streams["torp"] = SfxSynth.bake(0.24, [SfxSynth.tone(140.0, 0.22, "saw", 0.12, -60.0), SfxSynth.noise(0.12, 0.08, _rng)])
	_streams["flak"] = SfxSynth.bake(0.1, [SfxSynth.noise(0.09, 0.12, _rng), SfxSynth.tone(220.0, 0.08, "square", 0.06, -80.0)])
	_streams["shell"] = SfxSynth.bake(0.18, [SfxSynth.tone(110.0, 0.16, "saw", 0.12, -40.0), SfxSynth.noise(0.1, 0.1, _rng)])
	# Hits and explosions: a hull hit, a shield hit, a ship blowing up.
	_streams["hit"] = SfxSynth.bake(0.06, [SfxSynth.noise(0.05, 0.1, _rng)])
	_streams["shield_hit"] = SfxSynth.bake(0.07, [SfxSynth.tone(1200.0, 0.05, "sine", 0.05, -500.0)])
	_streams["boom"] = SfxSynth.bake(0.32, [SfxSynth.noise(0.28, 0.2, _rng), SfxSynth.tone(90.0, 0.3, "sine", 0.16, -40.0)])
	# Interface: a click, a purchase (two rising notes), a warning buzz.
	_streams["ui"] = SfxSynth.bake(0.06, [SfxSynth.tone(680.0, 0.05, "square", 0.05, 0.0)])
	_streams["buy"] = SfxSynth.bake(0.12, [SfxSynth.tone(520.0, 0.06, "triangle", 0.07, 0.0), SfxSynth.tone(780.0, 0.1, "triangle", 0.06, 0.0)])
	_streams["warn"] = SfxSynth.bake(0.16, [SfxSynth.tone(320.0, 0.14, "saw", 0.07, -80.0)])
	# Ship actions: launch (rising), special ability (rising), repair (two
	# soft notes), bumping into something (a thud).
	_streams["launch"] = SfxSynth.bake(0.2, [SfxSynth.tone(200.0, 0.18, "saw", 0.08, 220.0)])
	_streams["special"] = SfxSynth.bake(0.18, [SfxSynth.tone(300.0, 0.16, "triangle", 0.08, 400.0)])
	_streams["repair"] = SfxSynth.bake(0.2, [SfxSynth.tone(440.0, 0.12, "sine", 0.06, 0.0), SfxSynth.tone(660.0, 0.18, "sine", 0.05, 0.0)])
	_streams["bump"] = SfxSynth.bake(0.1, [SfxSynth.noise(0.08, 0.14, _rng), SfxSynth.tone(70.0, 0.08, "sine", 0.1, 0.0)])
	# Step 3: listen for cues from the simulation.
	Events.cue.connect(_on_cue)


## Remember the running match `w`. main.gd calls this right after adding
## Sfx to the game.
func setup(w: World) -> void:
	world = w


## A sound cue arrived (Events.cue): play sound `cue` for world position
## `pos`, if the player would hear it. Vector2.ZERO = an interface sound.
func _on_cue(cue: String, pos: Vector2) -> void:
	# Step 1: unknown names are ignored.
	if not _streams.has(cue):
		return
	# Step 2: too soon after the same cue? Skip it (MIN_GAP).
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(cue, -1.0)) < float(MIN_GAP.get(cue, 0.0)):
		return
	# Step 3: how loud, from where it is (interface sounds: full volume).
	# Too quiet to matter (0.02 or less, such as off screen or in the fog)?
	# Skip it.
	var gain := 1.0
	if pos != Vector2.ZERO and world != null and world.camera != null:
		gain = _gain_at(pos)
		if gain <= 0.02:
			return
	# Step 4: play it on the next voice in turn. Volume is set in decibels
	# (the usual loudness scale), turned from the 0..1 loudness.
	_last[cue] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[cue]
	p.volume_db = linear_to_db(MASTER * gain)
	# Shots and hits get a small random pitch change, so a burst of the
	# same sound doesn't sound robotic.
	p.pitch_scale = _rng.randf_range(0.93, 1.07) if cue in ["fire", "pd", "hit", "flak"] else 1.0
	p.play()


## How loud (0..1) a sound at world position `pos` should be. Full volume
## (1) in the middle third of the view, falling to 0.5 at the screen's
## edge and about 0.28 at 1.3 times that distance; further away it is
## silent (0). Also silent inside the viewing team's fog of war.
func _gain_at(pos: Vector2) -> float:
	# Step 1: half the view's size, in world units (screen pixels / zoom).
	var cam := world.camera
	var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom.x
	# Step 2: how far out the point is: 0 at the centre, 1 on the edge of
	# the screen (measured across or up-down, whichever is further out).
	var off := (pos - cam.global_position).abs()
	var k := maxf(off.x / maxf(1.0, half.x), off.y / maxf(1.0, half.y))
	if k > 1.3:
		return 0.0
	# Step 3: hidden in the fog for the team on screen? Silent. (A
	# spectator, viewer_team -1, hears everything.)
	if world.viewer_team >= 0 and not world.vision.is_visible(world.viewer_team, pos):
		return 0.0
	# Step 4: fade with distance from the centre, never below 0.15.
	return clampf(1.25 - k * 0.75, 0.15, 1.0)
