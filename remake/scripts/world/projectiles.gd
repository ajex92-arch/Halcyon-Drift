class_name Projectiles
extends Node2D
## WHAT THIS IS: every bullet, torpedo, shell and flak pellet that is flying
## right now. We call each one a "round". This file moves the rounds, finds
## what they hit, and draws them.
##
## HOW IT WORKS: there is no node per round. Each round is a "slot" number,
## and every fact about it lives in its own list ("parallel arrays"):
## pos[5] is where round 5 is, vel[5] how it moves, dmg[5] how hard it hits,
## and so on. When a round is gone, its slot number goes on a free list and
## the next spawn() reuses it ("pooling": it saves making and throwing away
## thousands of objects).
##
## Every tick (one small step of game time) World calls tick():
##   1. The beam lines the units just fired are handed over for drawing.
##   2. We list the live torpedoes.
##   3. Each live round takes one step (_step):
##      a. a homing torpedo turns toward its target;
##      b. it moves. We test the whole line from where it was to where it is
##         now (a "swept" test), so a fast round can't jump over a target;
##      c. an asteroid on that line stops it;
##      d. bolts, point defense and flak can shoot down an enemy torpedo;
##      e. the first enemy unit or mothership on the line is hit
##         (ProjectilesHitScan);
##      f. a hit does its damage and makes sparks (ProjectilesImpact). Flak
##         bursts for area damage instead, also when it runs out of time;
##      g. a round that is out of time or off the map disappears.
##   4. The list of active slots is rebuilt without the dead ones.
##
## Beams (lance, ion) are not rounds: they hit instantly through
## Combat.beam(). WeaponMount then registers the beam line here with
## add_beam(), only so that it gets drawn.
##
## With --sim-only (Game.sim_only) nothing is ever drawn: the node hides
## itself, has no per-frame redraw, and add_beam() keeps no lines. The rounds
## themselves move and hit exactly as before.
##
## WHO USES IT: World owns it (the "Projectiles" child node,
## World.projectiles) and calls tick() every tick; WorldSetup calls setup()
## and sets viewer_team. WeaponMount fires rounds (spawn) and beams
## (add_beam). WeaponMountTargeting asks about torpedoes for point defense
## (nearest_enemy_torp, is_live_torp, pos, vel). WorldRegistry uses HASH_PAD
## to pick the units for World.big_hash. main.gd and the det_hash test read
## count().
##
## THE PARTS (files next to this one):
##   projectiles_hit_scan.gd  (ProjectilesHitScan)  which unit a round's line
##                            touches first
##   projectiles_impact.gd    (ProjectilesImpact)   what a hit does (damage,
##                            sparks, flak bursts)
##   projectiles_draw.gd      (ProjectilesDraw)     drawing rounds and beams
## The lists of facts stay here, and only this file changes them.
##
## Words used here: a "spatial hash" (World.unit_hash) files every unit
## under the grid square it is in, so "who is near this point?" only checks
## a few squares. A "world unit" is the game's distance unit (about one
## pixel at normal zoom).

## How far (world units) around a round's line we search the spatial hash:
## enough for units up to this radius (60). Units bigger than this also go
## into World.big_hash (WorldRegistry uses this same number), which we
## search BIG_PAD further. That keeps the main search to 1-2 hash cells.
const HASH_PAD := 60.0
## Extra search distance (world units) for World.big_hash.
const BIG_PAD := 110.0

## The world this belongs to (set by setup()).
var world: World
## How many slots exist so far, live and free. Grows by one when spawn()
## finds no free slot.
var cap := 0
## Per slot: where the round is now (world position).
var pos := PackedVector2Array()
## Per slot: where it was one tick ago. Its line this tick is prev -> pos.
var prev := PackedVector2Array()
## Per slot: its velocity: direction and speed (world units per second).
var vel := PackedVector2Array()
## Per slot: seconds left before it runs out and disappears.
var life := PackedFloat32Array()
## Per slot: raw damage of a hit, before the damage table.
var dmg := PackedFloat32Array()
## Per slot: weapon kind, one of Rules.W_* (bolt, torpedo, flak, ...).
var kind := PackedInt32Array()
## Per slot: the team that fired it (0, 1 or Rules.NEUTRAL).
var team := PackedInt32Array()
## Per slot: the round's own radius for hit tests (world units).
var radius := PackedFloat32Array()
## Per slot: flak burst radius (world units); 0 for other weapons.
var burst := PackedFloat32Array()
## Per slot: a torpedo's hit points (0 for other rounds). Bolts, point
## defense and flak wear them down.
var hp := PackedFloat32Array()
## Per slot: how fast a homing torpedo turns (radians per second); 0 means
## it flies straight.
var homing := PackedFloat32Array()
## Per slot: extra damage multiplier against SMALL targets (1.0 = none).
var small_bonus := PackedFloat32Array()
## Per slot: 1 if the round chips destructible asteroids (capital guns),
## else 0.
var cuts := PackedByteArray()
## Per slot: 1 while the round flies, 0 once it is gone (slot is free).
var live := PackedByteArray()
## Per slot: 1 if the round can never hit an asteroid, so _step() skips its
## rock check (a speed-up; see spawn(), Step 4).
var rock_free := PackedByteArray()
## Per slot: the shooter's uid (its id number), or -1 for none.
var src_uid := PackedInt32Array()
## Per slot: the shooter's size class (Rules.SIZE_*).
var src_size := PackedInt32Array()
## Per slot: 1 if a minion fired it.
var src_minion := PackedByteArray()
## Per slot: 1 if a pilot ship fired it.
var src_pilot := PackedByteArray()
## Per slot: the shooting pilot's PilotProfile, or null. (Objects can't go
## into the packed lists above, so this one and the next two are plain
## Arrays.)
var src_profile: Array = []
## Per slot: the shooting unit itself, or null. It may die and be freed
## while the round flies, so check is_instance_valid() before using it.
var src_ref: Array = []
## Per slot: the unit a homing torpedo chases, or null.
var target_ref: Array = []
## Slot numbers that are free to reuse; spawn() takes the last one first.
var free_list := PackedInt32Array()
## Slot numbers of the rounds in flight (spawn() adds to it). Dead ones are
## dropped at the end of every tick().
var active := PackedInt32Array()
## Slot numbers of the live torpedoes this tick (for point defense and for
## shooting torpedoes down). Rebuilt at the start of every tick().
var torps := PackedInt32Array()
## Beam lines fired this tick, each [a, b, team, width, kind]. tick() moves
## them to beams_draw. (Headless runs never draw, so nothing piles up.)
var beams: Array = []
## The beam lines of the last tick, kept for drawing.
var beams_draw: Array = []
## The team whose fog the screen shows (-1 = see everything). Enemy rounds
## in fog are not drawn. WorldSetup sets it.
var viewer_team := -1
## The "which unit did it hit?" part (projectiles_hit_scan.gd), made by
## setup().
var hit_scan: ProjectilesHitScan
## An empty "no rock was hit" answer, shared so _step() doesn't make a new
## one for every round on every tick. Nothing ever writes into it.
var _no_rock := {}


## Remember the world, draw above most things (z_index 5) and make the
## hit-scan part. WorldSetup calls this once, before the match starts. With
## --sim-only (Game.sim_only) nothing is ever drawn, so we hide ourselves and
## stop the per-frame redraw; the rounds themselves are not affected.
func setup(w: World) -> void:
	world = w
	z_index = 5
	hit_scan = ProjectilesHitScan.new(w)
	if Game.sim_only:
		visible = false
		set_process(false)


## How many slots are in use (rounds in flight).
func count() -> int:
	return active.size()


## Add one more slot at the end of every list, filled with "empty" values,
## and return its number. spawn() uses it when no free slot is left.
func _grow() -> int:
	var i := cap
	cap += 1
	# One new entry in every list, in the same order as the lists above.
	pos.append(Vector2.ZERO)
	prev.append(Vector2.ZERO)
	vel.append(Vector2.ZERO)
	life.append(0.0)
	dmg.append(0.0)
	kind.append(0)
	team.append(0)
	radius.append(0.0)
	burst.append(0.0)
	hp.append(0.0)
	homing.append(0.0)
	small_bonus.append(1.0)
	cuts.append(0)
	live.append(0)
	rock_free.append(0)
	# Who fired it: nobody yet.
	src_uid.append(-1)
	src_size.append(0)
	src_minion.append(0)
	src_pilot.append(0)
	src_profile.append(null)
	src_ref.append(null)
	target_ref.append(null)
	return i


## Launch a round and return its slot number. `at` is where it starts,
## `velocity` its direction and speed (world units per second), `life_s`
## how many seconds it may fly, `damage` its raw damage and `kind_id` its
## weapon kind (Rules.W_*). `def` is the weapon's data entry: radius,
## burst, torp_hp, homing, cuts and small_bonus are read from it (with
## defaults when missing). `src` is the shooter and `target` the unit a
## homing torpedo chases; both may be null.
func spawn(at: Vector2, velocity: Vector2, life_s: float, damage: float, kind_id: int, def: Dictionary, src: Unit, target: Unit) -> int:
	# Step 1: reuse the last free slot, or make a new one.
	var i: int
	if free_list.size() > 0:
		i = free_list[free_list.size() - 1]
		free_list.resize(free_list.size() - 1)
	else:
		i = _grow()
	# Step 2: where it starts, how it moves, how long it lives, how hard it
	# hits, and whose it is (no shooter counts as neutral).
	pos[i] = at
	prev[i] = at
	vel[i] = velocity
	life[i] = life_s
	dmg[i] = damage
	kind[i] = kind_id
	team[i] = src.team if src != null else Rules.NEUTRAL
	# Step 3: the numbers that come from the weapon's data entry.
	radius[i] = float(def.get("radius", 3.0))
	burst[i] = float(def.get("burst", 0.0))
	hp[i] = float(def.get("torp_hp", 0.0))
	homing[i] = float(def.get("homing", 0.0))
	small_bonus[i] = float(def.get("small_bonus", 1.0))
	cuts[i] = 1 if def.get("cuts", false) else 0
	# Step 4 (a speed-up that changes nothing): can this round ever hit a
	# rock? Rocks only ever disappear, never appear, and a round that doesn't
	# home flies in a straight line. So if its whole flight (its life plus a
	# little) is clear of rocks right now, it never hits one, and _step() can
	# skip the rock check on every tick. The check is 4 world units wider
	# than the round, far more than the tiny rounding drift of its stored
	# position. Homing torpedoes curve, so they always check.
	rock_free[i] = 0
	if homing[i] <= 0.0:
		var end := at + velocity * (life_s + 0.05)
		if world.asteroids.segment_hit(at, end, radius[i] + 4.0).is_empty():
			rock_free[i] = 1
	# Step 5: mark it as flying, and remember who fired it (for kill credit
	# and the damage rules). No shooter counts as a small non-pilot.
	live[i] = 1
	src_uid[i] = src.uid if src != null else -1
	src_size[i] = src.size_class if src != null else Rules.SIZE_SMALL
	src_minion[i] = 1 if (src != null and src.kind == Unit.K_MINION) else 0
	src_pilot[i] = 1 if (src != null and src.kind == Unit.K_SHIP) else 0
	src_profile[i] = (src as Ship).profile if src is Ship else null
	src_ref[i] = src
	target_ref[i] = target
	active.append(i)
	return i


## True if slot `i` holds a live torpedo that does not belong to team
## `not_team` (when given). Slots are reused, so a point-defense gun that
## locked onto a torpedo must re-check whose torpedo is in that slot now.
func is_live_torp(i: int, not_team: int = -1) -> bool:
	return i >= 0 and i < cap and live[i] == 1 and kind[i] == Rules.W_TORP and team[i] != not_team


## The nearest live enemy torpedo within `r` world units of point `p` (for
## point defense), as a slot number, or -1 if there is none. "Enemy" means
## not on team `my_team`.
func nearest_enemy_torp(p: Vector2, r: float, my_team: int) -> int:
	var best := -1
	var bd := r * r
	# Compare squared distances (quicker than real distances, same order).
	for i in torps:
		if live[i] == 0 or team[i] == my_team or kind[i] != Rules.W_TORP:
			continue
		var d := p.distance_squared_to(pos[i])
		if d < bd:
			bd = d
			best = i
	return best


## Remember a beam line from `a` to `b` (team `t`, `width` world units,
## weapon kind `k`) so it is drawn. WeaponMount calls this after
## Combat.beam() has done the beam's damage.
func add_beam(a: Vector2, b: Vector2, t: int, width: float, k: int) -> void:
	# --sim-only: the lines are only ever drawn, so keep none.
	if Game.sim_only:
		return
	beams.append([a, b, t, width, k])


## Remove round `i`: mark it dead, forget the units it pointed at, and put
## its slot on the free list.
func _kill(i: int) -> void:
	live[i] = 0
	src_ref[i] = null
	target_ref[i] = null
	src_profile[i] = null
	free_list.append(i)


## Move every round one step. World calls this once per tick (`dt` seconds
## long), after the units have moved and fired.
func tick(dt: float) -> void:
	# Step 1: the beam lines the units just fired become the ones to draw;
	# start an empty list for the next tick.
	beams_draw = beams
	beams = []
	# Step 2: list the live torpedoes.
	torps.clear()
	for i in active:
		if live[i] == 1 and kind[i] == Rules.W_TORP:
			torps.append(i)
	# Step 3: move every live round and handle what it hits.
	for i in active:
		if live[i] == 1:
			_step(i, dt)
	# Step 4: rebuild the active list without the dead rounds. This waits
	# until ALL rounds have stepped: a round can remove another one that
	# already stepped this tick (shooting down a torpedo), and keeping that
	# dead slot would step it twice once spawn() reuses it.
	var still := PackedInt32Array()
	for i in active:
		if live[i] == 1:
			still.append(i)
	active = still


## The first enemy torpedo (in `torps` order) that round `i`'s line a -> b
## touches this tick, as a slot number, or -1. "Touches" means the line
## passes within both radii plus 4 world units of the torpedo's centre.
## It simply checks every torpedo in flight: there are rarely more than
## about 20 at once.
func _find_torp_hit(i: int, a: Vector2, b: Vector2) -> int:
	var my_team := team[i]
	# Torpedoes farther than this (a squared distance: the line's length
	# squared, plus 2500 = 50 squared) from both ends are clearly missed.
	var reject := a.distance_squared_to(b) + 2500.0
	for j: int in torps:
		# Slots freed earlier this tick can be reused by spawn(), so check
		# again that this is still a live enemy torpedo.
		if live[j] == 0 or team[j] == my_team or kind[j] != Rules.W_TORP:
			continue
		# Cheap reject: the torpedo is far from both ends of the line.
		if a.distance_squared_to(pos[j]) > reject and b.distance_squared_to(pos[j]) > reject:
			continue
		# The real test: does the line pass within both radii + 4?
		if Util.seg_hits_circle(a, b, pos[j], radius[j] + radius[i] + 4.0):
			return j
	return -1


## Move round `i` one tick (`dt` seconds) and handle whatever it hits. These
## are steps 3a to 3g at the top of this file.
func _step(i: int, dt: float) -> void:
	var k := kind[i]
	# a. A homing torpedo turns toward its live target, at most homing[i]
	#    radians per second, and keeps its speed.
	if homing[i] > 0.0:
		var t = target_ref[i]
		if t != null and is_instance_valid(t) and t.alive:
			var want: Vector2 = (t.global_position - pos[i])
			var sp := vel[i].length()
			var cur := vel[i].angle()
			var turn := clampf(Util.ang_diff(cur, want.angle()), -homing[i] * dt, homing[i] * dt)
			vel[i] = Vector2.from_angle(cur + turn) * sp
	# b. Move, and use up flight time. Its line this tick is a -> b.
	prev[i] = pos[i]
	pos[i] = pos[i] + vel[i] * dt
	life[i] -= dt
	var a := prev[i]
	var b := pos[i]
	var my_team := team[i]

	# c. Asteroids stop rounds. best_t says how far along the line the first
	#    hit is (0 = at a, 1 = at b); 2.0 means "nothing hit yet". A round
	#    whose path was clear when it was fired can't hit a rock (see
	#    spawn(), Step 4), so it skips the check.
	var rock: Dictionary = _no_rock
	var best_t := 2.0
	if rock_free[i] == 0:
		rock = world.asteroids.segment_hit(a, b, radius[i])
		if not rock.is_empty():
			best_t = float(rock["t"])

	# d. Bolts, point defense and flak can shoot down enemy torpedoes. The
	#    torpedo loses hit points by the damage table's "torpedo" column; at
	#    0 it pops in a small ice-white puff. Our round is used up either way.
	if (k == Rules.W_BOLT or k == Rules.W_PD or k == Rules.W_FLAK) and not torps.is_empty():
		var j := _find_torp_hit(i, a, b)
		if j >= 0:
			hp[j] -= dmg[i] * Rules.damage_mult(k, Rules.SIZE_TORPEDO)
			if hp[j] <= 0.0:
				world.effects.puff(pos[j], Palette.ICE, 6)
				_kill(j)
			_kill(i)
			return

	# e. Enemy units and motherships: the first one along the line counts,
	#    if it comes before the rock (ProjectilesHitScan).
	best_t = hit_scan.scan(a, b, radius[i], burst[i], k, my_team, best_t)
	var hit_unit: Unit = hit_scan.hit_unit

	# f. Something was hit on this line: put the round at the hit point,
	#    let the hit do its work (ProjectilesImpact), then remove the round.
	if best_t <= 1.0:
		var at := a.lerp(b, best_t)
		pos[i] = at
		ProjectilesImpact.hit(self, i, at, hit_unit, rock, k, my_team)
		_kill(i)
		return

	# g. Out of time: flak still bursts where it is, then the round is gone.
	#    A round that flew off the map is gone too.
	if life[i] <= 0.0:
		ProjectilesImpact.expire(self, i, b, k, my_team)
		_kill(i)
		return
	if b.x < 0.0 or b.y < 0.0 or b.x > MapLayout.W or b.y > MapLayout.H:
		_kill(i)


## Every frame: ask Godot to redraw us (Godot then calls _draw()).
func _process(_dt: float) -> void:
	queue_redraw()


## Draw the rounds and beams the viewer can see. The real code is
## ProjectilesDraw.draw_all().
func _draw() -> void:
	ProjectilesDraw.draw_all(self)
