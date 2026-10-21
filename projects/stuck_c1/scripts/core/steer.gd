class_name Steer
extends RefCounted
## WHAT THIS IS: simple steering helpers for the light units that don't use
## the full flight model: minions, mining drones, repair bays and wards in
## flight, and snub fighters. Pilot ships fly with the full flight model
## (ShipFlight) instead, but their AI (PilotFlight) still uses advance() to
## tick off route waypoints.
##
## HOW IT WORKS: three small "static" functions (called as Steer.seek(...)
## without making a Steer first; they keep no memory):
##   - seek(): turn the velocity towards a target, slowing down on arrival.
##   - avoid_rocks(): a push away from asteroids just ahead.
##   - advance(): move on to the next waypoint of a route once close enough.
## A "velocity" is a speed with a direction (an arrow, in world units per
## second). Distances are in world units.
##
## WHO USES IT: seek() is used by minions, mining drones, repair bays and
## wards; avoid_rocks() by those and snub fighters; advance() by minions,
## mining drones, repair bays, wards and PilotFlight.


## New velocity that seeks `target`, slowing inside `arrive` distance.
## The wanted speed is `max_speed`, scaled down evenly inside `arrive`
## world units of the target (half the distance, half the speed). Within 1
## unit of the target it just slows towards a stop. The velocity changes by
## at most `accel * dt` per call (`accel` in world units per second per
## second, `dt` the step length in seconds).
static func seek(pos: Vector2, vel: Vector2, target: Vector2, max_speed: float, accel: float, dt: float, arrive: float = 200.0) -> Vector2:
	var to := target - pos
	var d := to.length()
	if d < 1.0:
		return vel.move_toward(Vector2.ZERO, accel * dt)
	var want_speed := max_speed if d > arrive else max_speed * d / arrive
	return vel.move_toward(to / d * want_speed, accel * dt)


## Push away from asteroids overlapping a circle slightly bigger than the
## unit. Returns a velocity correction (add it to the velocity).
## The circle sits at `pos + look` (a point a little ahead, so the unit
## turns before it hits), with the unit's `radius` plus 40 world units to
## spare. Each rock it overlaps pushes straight away from its centre, 3
## times harder per unit of overlap. `scratch` is the caller's reusable
## list for the rock search (AsteroidField.nearby()). Most callers multiply
## the result by the step length (dt) before adding it.
static func avoid_rocks(field: AsteroidField, pos: Vector2, radius: float, look: Vector2, scratch: PackedInt32Array) -> Vector2:
	var push := Vector2.ZERO
	var probe := pos + look
	# In open space no rock can overlap the probe circle: skip the search
	# (the push would stay zero anyway; AsteroidField.clear_at()).
	if field.clear_at(probe, radius + 40.0):
		return push
	# Rocks near the probe point (searching 300 units wider than the unit).
	field.nearby(probe, radius + 300.0, scratch)
	for i in scratch:
		# How far the probe circle overlaps this rock, if at all.
		var c := field.pos[i]
		var r := field.rad[i] + radius + 40.0
		var d := probe.distance_to(c)
		if d < r and d > 0.001:
			push += (probe - c) / d * (r - d) * 3.0
	return push


## Advance a path index when the current waypoint is reached.
## `path` is the route's points and `idx` the waypoint we are heading for.
## While we are within `reach` world units of it (and it isn't the last
## one), move on to the next. Returns the new index.
static func advance(path: PackedVector2Array, idx: int, pos: Vector2, reach: float) -> int:
	while idx < path.size() - 1 and pos.distance_to(path[idx]) < reach:
		idx += 1
	return idx
