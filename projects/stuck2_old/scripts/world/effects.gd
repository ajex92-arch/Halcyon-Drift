class_name Effects
extends Node2D
## WHAT THIS IS: the eye candy: sparks, puffs of particles, explosions,
## flak bursts and growing rings ("pulses"). Looks only: the
## game's rules never read anything here.
##
## HOW IT WORKS: other code asks for an effect (puff, spark, explosion,
## flak_burst, pulse). Each effect adds entries to two lists: particles
## (little squares that fly outward and fade) and pulses (rings that grow and
## fade). Every frame,
## _process() ages them, moves them and drops the finished ones, and
## _draw() paints what is left. Each list has a cap so big fights stay
## cheap: when a list is full, its oldest entry is dropped. Particles and
## pulses at places the viewing team can't see (in the fog) are not made
## at all.
##
## Effects has its own random numbers (`rng`), apart from the shared
## sequence the game rules use. So making or skipping effects (for example
## in the fog) never changes the match: each viewer sees different effects,
## but the match plays out the same.
##
## With --sim-only (Game.sim_only) nothing is ever drawn, so Effects does
## nothing: it hides itself, stops its per-frame work, and puff(), spark(),
## explosion(), flak_burst() and pulse() return at once (explosion() also
## sends no sound cue). Because of the separate random numbers, the match is
## exactly the same.
##
## WHO USES IT: World owns it (the "Effects" child node, World.effects);
## WorldSetup calls setup() and sets viewer_team. Projectiles (with its
## part ProjectilesImpact) makes sparks, flak bursts and the puff of a
## torpedo shot down. Units call explosion()
## when they die (Ship, Minion, Turret, Mothership, RepairBay, Derelict,
## MiningDrone). Ward, SnubFighter and RepairDrone make puffs, and
## ShipAbilities makes pulses for specials (Scout Ping, Jam, ...).

## The most particles alive at once (900).
const MAX_PARTICLES := 900
## The most rings (pulses) at once (60).
const MAX_PULSES := 60

## The world (we ask its Vision what the viewer can see).
var world: World
## Particles, each [position, velocity (world units per second), seconds
## left, seconds at the start, colour, size (screen pixels)].
var parts: Array = []
## Pulses (growing rings), each [centre, final radius (world units),
## seconds left, total seconds, colour].
var pulses: Array = []
## The team whose fog the screen shows (-1 = see everything). WorldSetup
## sets it.
var viewer_team := -1
## Effects' own random numbers: the directions, speeds, lives and sizes of
## particles. setup() seeds it, so effects look the same every run.
var rng := RandomNumberGenerator.new()


## Remember the world, draw above the projectiles (z_index 6) and seed our
## random numbers. WorldSetup calls this once. With --sim-only
## (Game.sim_only) nothing is ever drawn: we hide ourselves, stop the
## per-frame work, and every effect function below returns at once.
func setup(w: World) -> void:
	world = w
	z_index = 6
	rng.seed = 1
	if Game.sim_only:
		visible = false
		set_process(false)


## True if the viewer may see point `p`: a spectator (viewer_team -1) sees
## everything, a team only what is not in its fog.
func _seen(p: Vector2) -> bool:
	return viewer_team < 0 or world.vision.is_visible(viewer_team, p)


## Throw `n` particles of `color` out from point `p` in random directions,
## each at 0.3 to 1.3 times `speed` (world units per second). Each lives
## 0.4 to 0.9 s and is 2 to 4 screen pixels big. Skipped in the viewer's
## fog. Uses `rng` four times per particle.
func puff(p: Vector2, color: Color, n: int, speed: float = 120.0) -> void:
	# --sim-only: nothing is drawn, so make nothing (the effects have their
	# own random numbers, so this changes nothing in the match).
	if Game.sim_only or not _seen(p):
		return
	for i in n:
		# Make room: drop the oldest particle when the list is full.
		if parts.size() >= MAX_PARTICLES:
			parts.pop_front()
		# A random direction and speed, a random life and a random size.
		var v := Vector2.from_angle(rng.randf() * TAU) * speed * (0.3 + rng.randf())
		var life := 0.4 + rng.randf() * 0.5
		parts.append([p, v, life, life, color, 2.0 + rng.randf() * 2.0])


## A hit spark at `p`: 2 slow particles, or 6 faster ones when `heavy`
## (torpedo and shell hits).
func spark(p: Vector2, color: Color, heavy: bool) -> void:
	if Game.sim_only:
		return
	puff(p, color, 6 if heavy else 2, 160.0 if heavy else 90.0)


## An explosion of `size` (world units, about the dying unit's size) at
## `p`: 8-40 particles in `color` (more for bigger explosions), 4-16 in the
## warm white BOOST colour, a ring that grows to 2.2 times `size` over
## 0.6 s, and the "boom" sound cue. The cue is sent even in fog (Sfx
## decides itself whether it can be heard).
func explosion(p: Vector2, size: float, color: Color) -> void:
	# --sim-only: neither the picture nor the sound cue is needed.
	if Game.sim_only:
		return
	puff(p, color, clampi(int(size / 6.0), 8, 40), 120.0 + size * 0.8)
	puff(p, Palette.BOOST, clampi(int(size / 12.0), 4, 16), 80.0 + size * 0.4)
	pulse(p, size * 2.2, 0.6, color)
	Events.cue.emit("boom", p)


## A flak burst at `p`: a quick ring of radius `r` (world units, 0.25 s)
## and 3 particles. Skipped in the viewer's fog.
func flak_burst(p: Vector2, r: float, color: Color) -> void:
	if Game.sim_only or not _seen(p):
		return
	pulse(p, r, 0.25, color)
	puff(p, color, 3, 90.0)


## A ring at `p` that grows from nothing to radius `r` (world units) over
## `life` seconds while it fades. Skipped in the viewer's fog; drops the
## oldest ring when the list is full.
func pulse(p: Vector2, r: float, life: float, color: Color) -> void:
	if Game.sim_only or not _seen(p):
		return
	if pulses.size() >= MAX_PULSES:
		pulses.pop_front()
	pulses.append([p, r, life, life, color])


## Every frame (`dt` seconds): age everything, move the particles and the
## texts, drop what has run out, and ask for a redraw.
func _process(dt: float) -> void:
	# Particles: still alive? Then move along their velocity and keep them.
	var keep: Array = []
	for pt: Array in parts:
		pt[2] = float(pt[2]) - dt
		if float(pt[2]) > 0.0:
			pt[0] = (pt[0] as Vector2) + (pt[1] as Vector2) * dt
			keep.append(pt)
	parts = keep
	# Pulses: keep the ones with time left.
	var kp: Array = []
	for pl: Array in pulses:
		pl[2] = float(pl[2]) - dt
		if float(pl[2]) > 0.0:
			kp.append(pl)
	pulses = kp
	queue_redraw()


## Paint everything. Sizes are multiplied by "px" (one screen pixel in
## world units at the current camera zoom), so effects keep their size on
## screen at any zoom.
func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(0.02, zoom)
	# Particles: small squares that fade as their time runs out.
	for pt: Array in parts:
		var c: Color = pt[4]
		var a := clampf(float(pt[2]) / float(pt[3]), 0.0, 1.0)
		var s := float(pt[5]) * px
		draw_rect(Rect2((pt[0] as Vector2) - Vector2(s, s) * 0.5, Vector2(s, s)), Palette.with_alpha(c, a))
	# Pulses: k goes from 0 to 1 over the ring's life; the ring grows with
	# k and fades out (starting at 60% opacity).
	for pl: Array in pulses:
		var k := 1.0 - float(pl[2]) / float(pl[3])
		var c: Color = pl[4]
		draw_arc(pl[0], float(pl[1]) * k, 0.0, TAU, 64, Palette.with_alpha(c, (1.0 - k) * 0.6), 2.0 * px, true)
