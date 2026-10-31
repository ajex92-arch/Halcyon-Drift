class_name PilotTrail
extends RefCounted
## WHAT THIS IS: the breadcrumb trail of an AI pilot's ship (a part of
## PilotFlight): a short list of the spots where the ship recently flew free,
## touching no rock. A ship that got itself pinned in the rocks can fly back
## along it, because every crumb is a place the ship has really been.
##
## HOW IT WORKS: PilotFlight.note_position() hands the ship's position to
## note() every tick. A crumb is dropped when the ship is not touching a rock
## and is at least STEP world units from the last crumb; only the newest
## MAX_CRUMBS are kept, so the trail covers the last 1,200 units or so of
## flying (a ship wedged in one spot adds none, so the way in stays on it).
## back_from() answers the crumbs from the newest to the oldest, as the points
## of a path back out. A new launch starts a new trail.
##
## WHO USES IT: PilotFlight owns one (PilotFlight.trail) and asks it for the
## way back when the ship is stalled; PilotEscape flies the path it makes.

## How far (world units) apart the crumbs are.
const STEP := 50.0
## How many crumbs are kept.
const MAX_CRUMBS := 24

## The crumbs, the oldest first.
var _crumbs := PackedVector2Array()
## The instance id of the ship the crumbs belong to (a new launch makes a new
## ship).
var _ship_id := 0


## The ship with instance id `ship_id` is at `p`; `free` is true when it
## touches no rock now. Drop a crumb when it is free and far enough from the
## last one. A ship launched again (another id) starts a new trail.
func note(p: Vector2, free: bool, ship_id: int) -> void:
	if ship_id != _ship_id:
		_ship_id = ship_id
		_crumbs.clear()
	if not free:
		return
	if _crumbs.is_empty() or p.distance_to(_crumbs[_crumbs.size() - 1]) >= STEP:
		_crumbs.append(p)
		if _crumbs.size() > MAX_CRUMBS:
			_crumbs.remove_at(0)


## The way back from `p`: the crumbs from the newest to the oldest, leaving
## out the ones nearer than `min_d` world units to `p` (the ship is on top of
## those). Empty when the trail has none.
func back_from(p: Vector2, min_d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(_crumbs.size() - 1, -1, -1):
		if _crumbs[i].distance_to(p) >= min_d:
			out.append(_crumbs[i])
	return out


## How many crumbs the trail holds.
func size() -> int:
	return _crumbs.size()
