class_name MothershipDrive
extends RefCounted
## WHAT THIS IS: the mothership's engines (a part of Mothership, kept in its
## own file): whether it may move, taking a move order, and creeping along
## its route.
##
## HOW IT WORKS: from 20:00 (Rules.MOTHERSHIP_MOVE_UNLOCK, 1200 s of match
## time) the admiral may order the mothership to a point. It follows the
## route's points one by one: it turns slowly toward the next point (def
## "turn", 0.05 radians per second; a radian is about 57 degrees) and moves
## at move_speed (80 world units per second), but only at 30% of that until
## its nose is within 0.6 radians (about 34 degrees) of the way it wants to
## go. It stops within 60 world units of the final point. (1 world unit is
## about one pixel at normal zoom.) This is a "static library": it keeps no
## memory of its own; the state (move_target, move_path, move_i) lives on
## the Mothership.
##
## WHO USES IT: Mothership forwards can_move() and order_move() here
## (AdmiralCommand calls those) and calls move() every tick.


## True when the admiral may move `ms`: from 20:00 on
## (Rules.move_unlock_time(), which a feature module may tune).
static func can_move(ms: Mothership) -> bool:
	return ms.world.time >= Rules.move_unlock_time()


## Start moving `ms` to `p` along the route points `path`.
static func order_move(ms: Mothership, p: Vector2, path: PackedVector2Array) -> void:
	ms.move_target = p
	ms.move_path = path
	ms.move_i = 0


## Move `ms` for one tick of `dt` seconds, if it has somewhere to go.
static func move(ms: Mothership, dt: float) -> void:
	if ms.move_target == Vector2.INF:
		return
	# Step 1: skip the route points we are already within 250 of; head for
	# the next one, or for the final point once the route is used up.
	var goal := ms.move_target
	while ms.move_i < ms.move_path.size() and ms.global_position.distance_to(ms.move_path[ms.move_i]) < 250.0:
		ms.move_i += 1
	if ms.move_i < ms.move_path.size():
		goal = ms.move_path[ms.move_i]
	# Step 2: arrived (within 60 of the final point)? Stop and forget the
	# order.
	var to := goal - ms.global_position
	if goal == ms.move_target and to.length() < 60.0:
		ms.move_target = Vector2.INF
		ms.move_path = PackedVector2Array()
		return
	# Step 3: turn toward the goal, at most def "turn" radians per second.
	var want := to.angle()
	ms.rotation = Util.wrap_angle(ms.rotation + clampf(Util.ang_diff(ms.rotation, want), -float(ms.def["turn"]) * dt, float(ms.def["turn"]) * dt))
	# Step 4: move straight toward the goal: full speed when roughly lined
	# up (within 0.6 radians), 30% otherwise, and never past the goal.
	var aligned := absf(Util.ang_diff(ms.rotation, want)) < 0.6
	var step := ms.move_speed * dt * (1.0 if aligned else 0.3)
	ms.position += to.normalized() * minf(step, to.length())
