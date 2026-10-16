class_name RepairBay
extends Unit
## WHAT THIS IS: a mobile repair station. The admiral launches it from the
## mothership toward a chosen spot; it flies there and anchors for good.
## Then its repair drones heal damaged friendly ships nearby. DESIGN.md A11.
##
## HOW IT WORKS:
##   - Flying: it follows the route map, and may use the small-ship links
##     (it is small enough for jungle paths), steering around asteroids.
##     Within 60 world units of its spot it anchors and stops for good.
##   - Drones: once anchored it keeps TeamState.bay_drones repair drones out
##     (1, more with research). The first comes at once; a lost drone is
##     replaced within 2 s; when several are missing, each further one
##     takes 15 s (Structures.REPAIR_BAY "drone_rebuild").
##   - Lockout: whenever its HULL takes damage it stops repairing for 5 s
##     ("lockout"). With Bay Defenses research it gets a shield and a point
##     defense gun, and hits that only drain the shield don't stop it.
##   - Pilots inside module_swap_radius (600) can swap ship modules here.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: AdmiralCommand launches it (World.spawn_bay ->
## WorldSpawner, which starts it at the mothership's launch point 2 and
## calls setup()). World calls sim_update() every tick. Its RepairDrones ask
## can_repair(). WorldQueries (best_bay, bay_at), WorldHangar and the
## hangar screen use is_anchored(), and bay_at also swap_radius(); AI
## pilots fall back to the nearest bay (World.best_bay). UnitVisual draws
## its range and the line to `anchor`; AdmiralBuilder (the AI admiral)
## reads `anchor`; Economy pays a bounty when it dies.

## "flying" (on its way) or "anchored" (arrived, for good).
var state := "flying"
## The spot it flies to and anchors at (world position).
var anchor := Vector2.ZERO
## The route to `anchor`: points in world positions.
var path := PackedVector2Array()
## Which point of `path` it is flying to (an index).
var path_i := 0
## Top speed while flying, in world units per second.
var speed := 380.0
## Its live repair drones (RepairDrone).
var drones: Array = []
## Seconds until the next missing drone is launched.
var drone_t := 0.0
## Its guns (WeaponMount): none, or one point defense gun after Bay
## Defenses research.
var mounts: Array[WeaponMount] = []
## True once it has the Bay Defenses shield and gun.
var has_defenses := false
## A reusable list for the asteroid search in Steer.avoid_rocks().
var _rocks := PackedInt32Array()


## Set up a repair bay for team `t` at `at`, flying to `target_point`.
## WorldSpawner.spawn_bay() calls this.
func setup(w: World, t: int, at: Vector2, target_point: Vector2) -> void:
	# Step 1: who and what we are.
	world = w
	team = t
	kind = Unit.K_BAY
	size_class = Rules.SIZE_STRUCTURE
	var d: Dictionary = Structures.REPAIR_BAY
	radius = float(d["radius"])
	hull_max = float(d["hull"])
	hull = hull_max
	speed = float(d["speed"])
	vision_radius = float(d["vision"])
	display_name = d["label"]
	# Step 2: where we start and where we go. Bays take no part in physics
	# bumps (layer and mask 0). The route may use small-ship links (`true`).
	position = at
	anchor = target_point
	collision_layer = 0
	collision_mask = 0
	path = w.map.route.path(at, target_point, true)
	path_i = 0
	# Step 3: the defenses, if the research is already done.
	_refresh_defenses()


## True once it has arrived and anchored.
func is_anchored() -> bool:
	return state == "anchored"


## Repairs pause while the hull has been hit recently: true when anchored
## and its hull hasn't been hit for Structures.REPAIR_BAY "lockout" (5 s).
func can_repair() -> bool:
	return is_anchored() and world.time - last_hull_damage_time >= float(Structures.REPAIR_BAY["lockout"])


## How close (world units) a pilot must be to swap modules here (600).
func swap_radius() -> float:
	return float(Structures.REPAIR_BAY["module_swap_radius"])


## Give the bay its Bay Defenses shield and gun once the team has that
## research (only once). Runs every tick, so bays built before the research
## get them too: a 400-point shield in one pool, refilling at 20 per second
## after 6 s without a hit, and an AUTO point defense gun that picks its own
## targets.
func _refresh_defenses() -> void:
	var ts: TeamState = world.teams[team]
	if ts.bay_defenses and not has_defenses:
		has_defenses = true
		shields = ShieldZones.new()
		shields.setup(float(Structures.REPAIR_BAY["defense_shield"]), 20.0, 6.0, true)
		mounts.append(WeaponMount.new(self, Structures.REPAIR_BAY["defense_weapon"], "auto", Vector2.ZERO, 180.0))


## One tick of `dt` seconds: defenses, then fly or run the drones. World
## calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: the defenses (refill the shield, let the gun shoot), even
	# while flying.
	_refresh_defenses()
	if shields != null:
		shields.tick(dt, 1.0)
	for m in mounts:
		m.update(dt, Vector2.ZERO, false, 1.0, 1.0, 1.0, null)
	if state == "flying":
		# Step 2: flying: aim at the route's next point (moving on within
		# 160 of it), or at the anchor itself on the last leg; steer there
		# (slowing within 150), sliding around asteroids.
		path_i = Steer.advance(path, path_i, global_position, 160.0)
		var goal := anchor if path.is_empty() or path_i >= path.size() - 1 else path[path_i]
		velocity = Steer.seek(global_position, velocity, goal, speed, 400.0, dt, 150.0)
		velocity += Steer.avoid_rocks(world.asteroids, global_position, radius, velocity * 0.3, _rocks) * dt
		position += velocity * dt
		# Within 60 of the anchor: anchor for good.
		if global_position.distance_to(anchor) < 60.0:
			state = "anchored"
			velocity = Vector2.ZERO
		return
	# Step 3: anchored: keep our drones out.
	_manage_drones(dt)


## Forget dead drones and launch a new one when we have fewer than the team
## allows (see "Drones" at the top for the timing).
func _manage_drones(dt: float) -> void:
	# Step 1: drop the dead ones (walking the list backwards, so removing
	# one doesn't skip the next).
	for i in range(drones.size() - 1, -1, -1):
		var d = drones[i]
		if not is_instance_valid(d) or not d.alive:
			drones.remove_at(i)
	# Step 2: one short? Count down, then launch one and wait the rebuild
	# time (15 s) before the next. With all drones out, the timer is kept at
	# 2 s or less, so a lost drone is replaced quickly.
	var want: int = world.teams[team].bay_drones
	if drones.size() < want:
		drone_t -= dt
		if drone_t <= 0.0:
			drone_t = float(Structures.REPAIR_BAY["drone_rebuild"])
			drones.append(world.spawn_repair_drone(self, team, global_position, RepairDrone.MODE_BAY))
	else:
		drone_t = minf(drone_t, 2.0)


## Combat.kill() calls this when we die: our drones vanish quietly, and an
## explosion.
func on_killed(_info: DamageInfo) -> void:
	for d in drones:
		if is_instance_valid(d) and d.alive:
			world.combat.kill_silently(d)
	drones.clear()
	world.effects.explosion(global_position, 120.0, Palette.team(team))
