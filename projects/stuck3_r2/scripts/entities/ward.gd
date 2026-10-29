class_name Ward
extends Unit
## WHAT THIS IS: a ward: a small, cheap spy drone the admiral sends out. It
## flies from the mothership to a spot the team can currently see, parks
## there for good and lights up the fog of war around it (blocked by
## asteroids, like all vision). DESIGN.md A11.
##
## HOW IT WORKS: it flies along the route map (small-ship links allowed),
## steering around asteroids. While flying it sees nothing; once anchored
## (within 40 world units of its spot; 1 world unit is about one pixel at
## normal zoom) it sees Structures.WARD "vision" (1,400) around it, x1.4
## with the team's ward research. It is fragile (25 hull) and stealthy:
## enemies see a ward only within Structures.WARD "stealth_radius" (500)
## of one of their units, or with a Scout Ping (WorldVisibility handles
## this). A team may have 6 wards; placing another shuts down the oldest
## (AdmiralCommand, by placed_at).
##
## WHO USES IT: AdmiralCommand places wards (World.spawn_ward ->
## WorldSpawner, which starts it at the mothership's launch point 1 and
## calls setup()). World calls sim_update() every tick. WorldVisibility
## uses its vision_radius and hides it from enemies; UnitVisual draws it
## (is_anchored()); AdmiralBuilder (the AI admiral) reads `anchor`; Economy
## pays a small bounty when it is shot down.

## "flying" (on its way) or "anchored" (arrived, for good).
var state := "flying"
## The spot it flies to and parks at (world position).
var anchor := Vector2.ZERO
## The route to `anchor`: points in world positions.
var path := PackedVector2Array()
## Which point of `path` it is flying to (an index).
var path_i := 0
## Top speed while flying, in world units per second.
var speed := 900.0
## The match time (seconds) when it was launched; the oldest ward shuts
## down first.
var placed_at := 0.0
## A reusable list for the asteroid search in Steer.avoid_rocks().
var _rocks := PackedInt32Array()


## Set up a ward for team `t` at `at`, flying to `target_point`.
## WorldSpawner.spawn_ward() calls this.
func setup(w: World, t: int, at: Vector2, target_point: Vector2) -> void:
	# Step 1: who and what we are. No sight until anchored.
	world = w
	team = t
	kind = Unit.K_WARD
	size_class = Rules.SIZE_SMALL
	var d: Dictionary = Structures.WARD
	radius = float(d["radius"])
	hull_max = float(d["hp"])
	hull = hull_max
	speed = float(d["speed"])
	vision_radius = 0.0
	display_name = d["label"]
	# Step 2: where we start and go, and when. No physics bumps (layer and
	# mask 0). The route may use small-ship links (`true`).
	position = at
	anchor = target_point
	placed_at = w.time
	collision_layer = 0
	collision_mask = 0
	path = w.map.route.path(at, target_point, true)
	path_i = 0


## True once it has arrived and parked.
func is_anchored() -> bool:
	return state == "anchored"


## One tick of `dt` seconds: keep watch, or fly to the spot. World calls it
## every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: anchored: just see. The sight range is set every tick, so
	# ward research works at once on wards already out.
	if state == "anchored":
		var ts: TeamState = world.teams[team]
		vision_radius = float(Structures.WARD["vision"]) * (1.4 if ts.ward_upgrade else 1.0)
		return
	# Step 2: flying: aim at the route's next point (moving on within 160
	# of it), or at the anchor itself on the last leg; steer there (quick
	# to speed up, slowing within 120), sliding around asteroids, and face
	# the way we fly (when faster than 10 world units per second).
	path_i = Steer.advance(path, path_i, global_position, 160.0)
	var goal := anchor if path.is_empty() or path_i >= path.size() - 1 else path[path_i]
	velocity = Steer.seek(global_position, velocity, goal, speed, 1200.0, dt, 120.0)
	velocity += Steer.avoid_rocks(world.asteroids, global_position, radius, velocity * 0.25, _rocks) * dt
	position += velocity * dt
	if velocity.length_squared() > 100.0:
		rotation = velocity.angle()
	# Step 3: within 40 of the spot: park for good.
	if global_position.distance_to(anchor) < 40.0:
		state = "anchored"
		velocity = Vector2.ZERO


## Combat.kill() calls this when we are shot down: a small puff of sparks
## in our team's colour.
func on_killed(_info: DamageInfo) -> void:
	world.effects.puff(global_position, Palette.team(team), 8)
