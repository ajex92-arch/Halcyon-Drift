class_name RepairDrone
extends Unit
## WHAT THIS IS: a tiny flying repair robot. It flies to a damaged friendly
## unit, hovers next to it and mends its hull. DESIGN.md A11.
##
## HOW IT WORKS: every drone works for an owner (`owner_unit`), in one of
## three modes:
##   MODE_BAY        belongs to a RepairBay; serves ships within the bay's
##                   range (1,400) and pauses while the bay is locked out
##                   (its hull was hit in the last 5 s).
##   MODE_LOGISTICS  belongs to a Logistics corvette (a support pilot
##                   ship); serves ships within 1,200 of it, and also
##                   repairs friendly repair bays and the mothership (at
##                   half the medium-ship rate). Never turrets: nothing
##                   can repair a turret.
##   MODE_KIT        launched by a repair kit; heals only its owner, more
##                   weakly, flies along with the owner's speed, and shuts
##                   down after 10 s.
## Bay and logistics drones look for work every 0.5 s: the most damaged
## friendly in range that still has room. A ship takes at most
## Structures.REPAIR_DRONE "per_target" drones at once, by size (small 1,
## medium 2, large 3, capital 4), and each drone heals per second by size
## too (8 / 14 / 18 / 22 hull points; kit drones 5 / 8 / 10 / 12), so big
## ships repair relatively slowly. Drones can be shot down, which stops the
## repair. If the owner dies (or a pilot ship docks), its drones vanish.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: RepairBay (bay drones) and Ship's ShipAbilities (kit and
## logistics drones) launch them through World.spawn_repair_drone ->
## WorldSpawner, which calls setup(). World calls sim_update() every tick.
## UnitVisual draws the repair beam while `healing`; the support_probe test
## counts drones per target.

## Mode number: a repair bay's drone.
const MODE_BAY := 0
## Mode number: a repair kit's drone.
const MODE_KIT := 1
## Mode number: a Logistics corvette's drone.
const MODE_LOGISTICS := 2

## Which job it has: MODE_BAY, MODE_KIT or MODE_LOGISTICS.
var mode := MODE_BAY
## The unit it works for: a repair bay or a pilot ship.
var owner_unit: Unit = null
## The unit it is repairing (or flying to), or null.
var target: Unit = null
## Seconds before it shuts down: 10 for kit drones, INF (forever) for the
## others.
var life_left := INF
## Top speed, in world units per second.
var speed := 520.0
## True on ticks when it actually repaired something (UnitVisual draws the
## repair beam).
var healing := false
## Seconds until it next checks its target (every 0.5 s).
var retarget_t := 0.0
## A reusable list for searching the spatial hash (World.unit_hash, a grid
## that quickly finds the units near a point).
var _scratch: Array = []


## Set up a repair drone for team `t` at `at`, working for `owner` in mode
## `m`. WorldSpawner.spawn_repair_drone() calls this.
func setup(w: World, owner: Unit, t: int, at: Vector2, m: int) -> void:
	world = w
	owner_unit = owner
	team = t
	mode = m
	kind = Unit.K_REPAIR_DRONE
	size_class = Rules.SIZE_SMALL
	radius = float(Structures.REPAIR_DRONE["radius"])
	speed = float(Structures.REPAIR_DRONE["speed"])
	# Kit drones are frailer (25 hull instead of 40) and only last 10 s.
	hull_max = float(Structures.KIT_DRONE["hp"]) if m == MODE_KIT else float(Structures.REPAIR_DRONE["hp"])
	hull = hull_max
	# Drones take no part in physics bumps (layer and mask 0).
	position = at
	collision_layer = 0
	collision_mask = 0
	display_name = "Repair drone"
	if m == MODE_KIT:
		life_left = float(Structures.KIT_DRONE["duration"])


## Repair `u` (a kit drone's owner). ShipAbilities.use_repair_kit() calls
## this right after launching a kit drone; kit drones never pick a target
## themselves.
func lock_target(u: Unit) -> void:
	target = u


## One tick of `dt` seconds: check the owner and the timers, then fly to the
## target (or around the owner) and repair. World calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: no owner any more: vanish quietly (no bounty, no news).
	if owner_unit == null or not is_instance_valid(owner_unit) or not owner_unit.alive:
		world.combat.kill_silently(self)
		return
	# Step 2: a kit drone runs out after its time; the others re-check their
	# target every 0.5 s and look for a new one when it is no good.
	if mode == MODE_KIT:
		life_left -= dt
		if life_left <= 0.0:
			world.combat.kill_silently(self)
			return
	else:
		retarget_t -= dt
		if retarget_t <= 0.0:
			retarget_t = 0.5
			if not _target_still_good():
				target = _pick_target()
	# Step 3: where to fly. With a target: a spot just off its edge that
	# slowly circles it (each drone at its own angle, from its uid), and
	# repair once within 60 of its edge (if allowed). Without: a spot
	# circling our owner.
	healing = false
	var goal: Vector2
	if target != null and is_instance_valid(target) and target.alive:
		var side := Vector2.from_angle(float(uid) * 2.3 + world.time * 0.7) * (target.radius + 18.0)
		goal = target.global_position + side
		if global_position.distance_to(target.global_position) < target.radius + 60.0 and _may_heal():
			_heal(target, dt)
	else:
		target = null
		goal = owner_unit.global_position + Vector2.from_angle(float(uid) * 1.7 + world.time * 0.5) * (owner_unit.radius + 40.0)
	# Step 4: fly there: top speed far away, slowing down close in (4x the
	# distance left, per second), with a quick 900 per second per second
	# change of velocity; face the way we fly.
	var to := goal - global_position
	var d := to.length()
	var want := to.normalized() * minf(speed, d * 4.0) if d > 1.0 else Vector2.ZERO
	# A kit drone adds its moving patient's velocity to the one it wants, so it
	# stays in healing range of a ship that is flying, instead of trailing it
	# by speed/4 (playtest: a kit used at 450+ units a second, as every
	# retreating fighter does, healed about nothing).
	if mode == MODE_KIT and target != null and is_instance_valid(target) and target.alive:
		want += target.velocity
	velocity = velocity.move_toward(want, 900.0 * dt)
	position += velocity * dt
	if velocity.length_squared() > 100.0:
		rotation = velocity.angle()


## May we repair right now? Bay drones only while their bay can repair (it
## is anchored and its hull wasn't hit in the last 5 s); others always.
func _may_heal() -> bool:
	if mode == MODE_BAY and owner_unit is RepairBay:
		return (owner_unit as RepairBay).can_repair()
	return true


## Repair `u` for one tick of `dt` seconds. The rate per second depends on
## u's size (kit drones use the weaker table). Structures always get half
## the medium-ship rate. Ships multiply it by their own repair_recv
## (how well they take repairs). Sets `healing` if any hull was mended.
func _heal(u: Unit, dt: float) -> void:
	var sz := Rules.size_index(u.size_class)
	var per: float
	if mode == MODE_KIT:
		per = float(Structures.KIT_DRONE["heal"][sz])
	else:
		per = float(Structures.REPAIR_DRONE["heal"][sz])
	if u.is_structure():
		per = float(Structures.REPAIR_DRONE["heal"][1]) * 0.5
	if u is Ship:
		per *= (u as Ship).repair_recv
	if u.heal(per * dt) > 0.0:
		healing = true


## How far from our owner we look for work, in world units: 1,200 for a
## logistics drone, the repair bay's range (1,400) otherwise.
func _range() -> float:
	if mode == MODE_LOGISTICS:
		return Structures.LOGISTICS_DRONE_RANGE
	return float(Structures.REPAIR_BAY["range"])


## Is our target still worth repairing? It must be alive, not (nearly)
## fully repaired (more than 0.5 hull missing), and within our range + 200
## of our owner.
func _target_still_good() -> bool:
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	if target.hull >= target.hull_max - 0.5:
		return false
	return target.global_position.distance_to(owner_unit.global_position) < _range() + 200.0


## Most-damaged friendly ship in range that still has room for a drone.
## Logistics drones also consider structures, except turrets. Only units below
## 99.5% hull count. Returns null if there is no work.
func _pick_target() -> Unit:
	var best: Unit = null
	var best_frac := 0.995
	var r := _range()
	# Step 1: look at every unit near our owner.
	for u: Unit in world.unit_hash.query(owner_unit.global_position, r, _scratch):
		if u.team != team or not u.alive or u == owner_unit:
			continue
		# Ships always; structures only for logistics drones, and never a
		# turret (nothing can repair one, so no drone should hover over it).
		var ok := u.kind == Unit.K_SHIP
		if mode == MODE_LOGISTICS and u.is_structure() and u.kind != Unit.K_TURRET:
			ok = true
		if not ok:
			continue
		if u.global_position.distance_to(owner_unit.global_position) > r:
			continue
		# Keep the one with the lowest hull fraction (0..1)...
		var frac := u.hull_frac()
		if frac >= best_frac:
			continue
		# ...that still has room for one more drone.
		if _drones_on(u) >= int(Structures.REPAIR_DRONE["per_target"][Rules.size_index(u.size_class)]):
			continue
		best_frac = frac
		best = u
	# Step 2: the mothership isn't in the spatial hash (its hull is too
	# long), so logistics drones check it here (with no limit on drones).
	if mode == MODE_LOGISTICS:
		var ms := world.mothership(team)
		if ms != null and ms.alive and ms.hull_frac() < best_frac and ms.hull_dist(owner_unit.global_position) < r:
			best = ms
	return best


## How many other live repair drones are working on `u` right now.
func _drones_on(u: Unit) -> int:
	var n := 0
	for d: RepairDrone in world.repair_drones:
		if d != self and d.alive and d.target == u:
			n += 1
	return n


## Combat.kill() calls this when we are shot down: a small puff of repair
## coloured sparks.
func on_killed(_info: DamageInfo) -> void:
	world.effects.puff(global_position, Palette.REPAIR, 6)
