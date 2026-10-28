class_name SupplyDrone
extends RepairDrone
## WHAT THIS IS: a repair drone that the admiral's Supply Drop sends out
## (AdmiralAssetsFeature, order "supply"). It is the ordinary repair drone
## (it can be shot down, a pilot who shoots it gets the usual 10 credits),
## but it does not belong to a repair bay: it flies from the mothership to a
## spot the admiral picked and mends friendly pilot ships there.
##
## HOW IT WORKS: setup_supply() makes the drone and gives it the spot.
## sim_update() has two phases:
##   1. FLY: it flies to the spot at SUPPLY_SPEED (900 world units per
##      second, faster than a bay's drone at 520). When it is within 60 of
##      the spot, phase 2 starts;
##   2. WORK: for WORK_TIME (8 s) it picks, every half second, the most
##      damaged friendly PILOT SHIP within WORK_RANGE (1,200) of the spot
##      that still has room for one more drone (the bay-drone limits per
##      ship size), flies next to it and mends it at the bay-drone rate of
##      RepairDrone._heal(). When the time is up it leaves quietly.
## If the mothership (its owner) is gone, it vanishes quietly, like every
## repair drone.
##
## WHO USES IT: AdmiralAssetsFeature spawns it (from the scene
## scenes/entities/supply_drone.tscn, which is the repair drone's scene with
## this script). World calls sim_update() every tick, like for any unit.

## Top speed on the way to the spot, in world units per second.
const SUPPLY_SPEED := 900.0
## How long (seconds) the drone works once it has arrived.
const WORK_TIME := 8.0
## How far from the spot (world units) it looks for ships to mend.
const WORK_RANGE := 1200.0

## The spot the admiral picked (world position).
var point := Vector2.ZERO
## True once the drone has arrived and is working.
var arrived := false
## Seconds of work left (counts down only once `arrived`).
var work_left := WORK_TIME


## Make this drone for `team`, launched at `at`, owned by the mothership
## `ms`, bound for `spot`. AdmiralAssetsFeature calls this right after
## WorldRegistry.attach(), just as WorldSpawner does for other repair drones.
func setup_supply(w: World, ms: Unit, t: int, at: Vector2, spot: Vector2) -> void:
	setup(w, ms, t, at, MODE_BAY)
	speed = SUPPLY_SPEED
	display_name = "Supply drone"
	point = spot


## One tick of `dt` seconds: fly to the spot, then work there (see HOW IT
## WORKS). World calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: no owner any more: vanish quietly.
	if owner_unit == null or not is_instance_valid(owner_unit) or not owner_unit.alive:
		world.combat.kill_silently(self)
		return
	# Step 2: where to fly. Phase 1: the spot, each drone at its own angle.
	healing = false
	var goal := point + Vector2.from_angle(float(uid) * 2.3) * 120.0
	if not arrived:
		if global_position.distance_to(point) < 60.0 + 120.0:
			arrived = true
	else:
		# Phase 2: time is running; leave when it is up.
		work_left -= dt
		if work_left <= 0.0:
			world.combat.kill_silently(self)
			return
		retarget_t -= dt
		if retarget_t <= 0.0:
			retarget_t = 0.5
			target = _pick_supply_target()
		if target != null and is_instance_valid(target) and target.alive:
			var side := Vector2.from_angle(float(uid) * 2.3 + world.time * 0.7) * (target.radius + 18.0)
			goal = target.global_position + side
			if global_position.distance_to(target.global_position) < target.radius + 60.0:
				_heal(target, dt)
		else:
			target = null
			goal = point + Vector2.from_angle(float(uid) * 1.7 + world.time * 0.5) * 200.0
	# Step 3: fly there like every repair drone (top speed far away, slowing
	# in close, a quick change of velocity), facing the way we fly.
	var to := goal - global_position
	var d := to.length()
	var want := to.normalized() * minf(speed, d * 4.0) if d > 1.0 else Vector2.ZERO
	velocity = velocity.move_toward(want, 1800.0 * dt)
	position += velocity * dt
	if velocity.length_squared() > 100.0:
		rotation = velocity.angle()


## The most damaged friendly pilot ship within WORK_RANGE of the spot that is
## under 99.5% hull and still has room for one more drone, or null.
func _pick_supply_target() -> Unit:
	var best: Unit = null
	var best_frac := 0.995
	for s: Ship in world.ships:
		if s.team != team or not s.alive:
			continue
		if s.global_position.distance_to(point) > WORK_RANGE:
			continue
		var frac := s.hull_frac()
		if frac >= best_frac:
			continue
		if _drones_on(s) >= int(Structures.REPAIR_DRONE["per_target"][Rules.size_index(s.size_class)]):
			continue
		best_frac = frac
		best = s
	return best
