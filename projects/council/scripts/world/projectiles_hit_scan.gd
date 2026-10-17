class_name ProjectilesHitScan
extends RefCounted
## WHAT THIS IS: the "which unit did this round fly into?" test. A part of
## Projectiles, kept in its own file.
##
## HOW IT WORKS: a round's line this tick goes from a to b. We ask the
## spatial hash for the units near that line (World.unit_hash, plus
## World.big_hash for the big hulls), skip the ones this round can't hit
## (its own team, the dead, and neutral units when a neutral fired it),
## throw out the clearly-too-far ones with a quick distance check, and run
## the exact swept test (Unit.hit_t) on the rest.
## The motherships are not in the hash, so they are checked one by one
## (Mothership.hit_t tests their long hull). The hit closest to a wins.
##
## Places along the line are given as a fraction "t": 0 = at a, 1 = at b.
##
## Flak is generous against SMALL targets: it counts as touching them
## anywhere within half its burst radius.
##
## WHO USES IT: Projectiles makes one in setup() and calls scan() from
## _step() for every round that was not used up on a torpedo.

## The world whose units we test.
var world: World
## The unit (or mothership) hit first by the last scan(), or null for none.
var hit_unit: Unit = null
## A reusable list that World.unit_hash fills with nearby units (so we
## don't make a new list every time).
var _scratch: Array = []
## A reusable list that World.big_hash fills with nearby big units.
var _scratch_big: Array = []


## Remember the world. Projectiles makes this part once.
func _init(w: World) -> void:
	world = w


## Find the first enemy unit or mothership on the line a -> b for a round
## with radius `rad`, flak burst radius `burst_r` (0 if not flak), weapon
## kind `k`, fired by team `my_team`. Only a hit closer to a than `best_t`
## counts (the rock hit so far, or 2.0 for none). Returns the new best_t,
## and leaves the unit in hit_unit (null if nothing came before best_t).
func scan(a: Vector2, b: Vector2, rad: float, burst_r: float, k: int, my_team: int, best_t: float) -> float:
	hit_unit = null
	# Step 1: the units near the line, from both hashes. The search circle
	# sits on the line's middle and reaches past both ends.
	var mid := (a + b) * 0.5
	var half := a.distance_to(b) * 0.5
	var reach := half + rad + Projectiles.HASH_PAD + burst_r * 0.5
	world.unit_hash.query(mid, reach, _scratch)
	if world.big_count > 0:
		_scratch.append_array(world.big_hash.query(mid, reach + Projectiles.BIG_PAD, _scratch_big))
	# Step 2: test each unit this round may hit.
	for u: Unit in _scratch:
		if u.team == my_team or not u.alive:
			continue
		if my_team == Rules.NEUTRAL and u.team == Rules.NEUTRAL:
			continue
		# How much bigger the target counts as: the round's radius, plus
		# half the burst radius for flak against a SMALL target.
		var pad := rad
		if k == Rules.W_FLAK and u.size_class == Rules.SIZE_SMALL:
			pad += burst_r * 0.5
		# Cheap reject before the exact swept test (units are children of
		# the world root, so position == global position). Big units are in
		# both hashes, so they come twice; the second test changes nothing.
		var lim := half + pad + u.radius
		if mid.distance_squared_to(u.position) > lim * lim:
			continue
		var t := u.hit_t(a, b, pad)
		if t >= 0.0 and t < best_t:
			best_t = t
			hit_unit = u
	# Step 3: the enemy motherships (they are not in the hash): a quick
	# distance check against their long hull, then the exact test.
	for ms: Mothership in world.motherships:
		if ms == null or not ms.alive or ms.team == my_team:
			continue
		var reach_ms := ms.half_len + ms.beam * 0.5 + half + 40.0
		if mid.distance_squared_to(ms.position) > reach_ms * reach_ms:
			continue
		var t := ms.hit_t(a, b, rad)
		if t >= 0.0 and t < best_t:
			best_t = t
			hit_unit = ms
	return best_t
