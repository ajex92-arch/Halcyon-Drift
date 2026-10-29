class_name MinionFlight
extends RefCounted
## WHAT THIS IS: how a lane minion flies (a part of Minion, kept in its own
## file): its fighting pattern near a target, and its trip down the lane.
##
## HOW IT WORKS: this is a "static library" with no memory of its own: each
## function is handed the minion and changes its velocity and rotation;
## Minion.sim_update() then moves it by its velocity on every tick. Velocity
## changes go through steer(), which limits them by the minion's `accel`
## (world units per second, per second) differently along and across the way
## it flies, and turning is limited by its `turn` (radians per second; a
## radian is about 57 degrees). The rock push found at the last think
## (Minion._rock_push) is added on top, so minions slide around asteroids.
##   - steer(): move the velocity toward a wanted one: speeding up and
##     slowing down are held to 0.9 of accel, bending the path to 0.8 of it,
##     and a mix of the two to the ellipse between them (so never more than
##     accel in any direction).
##   - combat_move(): each type fights its own way:
##       fighter   flies at the target, then circles it ("circle-strafing")
##       bomber    straight attack runs; peels off sideways when close
##       corvette  holds at range and lets its cannon work
##     Fighters and bombers have fixed guns, so their nose follows the aim
##     point (the lead point, Minion.aim_pt); the corvette's turret aims by
##     itself, so its nose follows the target.
##   - lane_move(): with no target, fly down the lane (or to the ordered
##     spot) at the wave's shared pace.
##   - face(): turn the nose toward an angle, no faster than `turn`.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: only Minion.sim_update(), on every second tick.


## Turn minion `m`'s nose toward angle `dir_angle` (radians), at most
## m.turn x `dt` radians this step.
static func face(m: Minion, dir_angle: float, dt: float) -> void:
	m.rotation = Util.wrap_angle(m.rotation + clampf(Util.ang_diff(m.rotation, dir_angle), -m.turn * dt, m.turn * dt))


## Change minion `m`'s velocity toward the wanted velocity `want` for one step
## of `dt` seconds. The change wanted, `want` less the velocity, is measured
## against the way the minion flies now: `along` is the part in that direction
## (speeding up or slowing down) and `side` the part across it (bending the
## path). In one step the change may be at most
## Minions.ALONG_ACCEL_MUL x accel x dt along and Minions.SIDE_ACCEL_MUL x
## accel x dt across, and a change that is partly both is held to the ellipse
## those two limits make: if it fits inside, the whole change is taken (the
## velocity becomes the wanted one); if not, it is shrunk, keeping its
## direction, until it just touches the ellipse. (Two separate limits would
## let a half-and-half change use both at once, more than accel in all, so the
## minion would turn faster than before.) A minion that is nearly standing
## still (Minions.MIN_HEADING_SPEED or slower) has no way of flying yet, so
## the whole change counts as along.
static func steer(m: Minion, want: Vector2, dt: float) -> void:
	var along_max := m.accel * Minions.ALONG_ACCEL_MUL * dt
	# Step 1: too slow to have a direction: the whole change is "along".
	var speed_sq := m.velocity.length_squared()
	if speed_sq <= Minions.MIN_HEADING_SPEED * Minions.MIN_HEADING_SPEED:
		m.velocity = m.velocity.move_toward(want, along_max)
		return
	# Step 2: split the change wanted into along and across the way we fly.
	var dv := want - m.velocity
	var heading := m.velocity / sqrt(speed_sq)
	var along := dv.dot(heading)
	var side := dv.dot(heading.orthogonal())
	var side_max := m.accel * Minions.SIDE_ACCEL_MUL * dt
	# Step 3: how far outside the ellipse the change is (1 = just on it).
	var reach := (along * along) / (along_max * along_max) + (side * side) / (side_max * side_max)
	if reach <= 1.0:
		m.velocity = want
	else:
		m.velocity += dv / sqrt(reach)


## Fly minion `m`'s fighting pattern for one step of `dt` seconds. `tp` is
## the point on the target we fight (MinionTargeting.target_point), `d` our
## distance to it and `reach` our first gun's range.
static func combat_move(m: Minion, tp: Vector2, d: float, reach: float, dt: float) -> void:
	# `dir` is the length-1 arrow pointing at the target; dir.orthogonal()
	# is the arrow at a right angle to it (straight sideways).
	var to := tp - m.position
	var dir := to / maxf(1.0, d)
	var want := Vector2.ZERO
	# Fixed-gun minions (fighters and bombers) point their nose at the aim
	# point (where the target will be when the round gets there, see
	# Minion.aim_pt), not at the target itself. (Playtest: only about a fifth
	# of the fighters' bolts were fired along a line that hit.)
	var face_to := m.aim_pt - m.position
	match m.mtype:
		"fighter":
			# Close in until 3/4 of our reach, then circle the target:
			# sideways at 55% speed, plus a little inward (15%) while
			# further than 40% of reach, or backing off (30%) when nearer.
			if d > reach * 0.75:
				want = dir * m.speed
			else:
				want = dir.orthogonal() * m.orbit * m.speed * 0.55 + dir * m.speed * (0.15 if d > reach * 0.4 else -0.3)
			face(m, face_to.angle(), dt)
		"bomber":
			# Straight attack run; closer than 380, peel off sideways at
			# full speed (facing where we fly), then come round again.
			if d < 380.0:
				want = dir.orthogonal() * m.orbit * m.speed
				face(m, want.angle(), dt)
			else:
				want = dir * m.speed
				face(m, face_to.angle(), dt)
		_:
			# Patrol Leader: stay between 55% and 85% of reach and let the
			# cannon work. Close in when further, back off at half speed
			# when nearer, otherwise stop (want stays zero).
			if d > reach * 0.85:
				want = dir * m.speed
			elif d < reach * 0.55:
				want = -dir * m.speed * 0.5
			face(m, to.angle(), dt)
	# Change our velocity toward the wanted one (steer() holds the change
	# to what our handling allows), then add the rock push.
	steer(m, want, dt)
	m.velocity += m._rock_push * dt


## With no target: fly minion `m` down its lane (or to its ordered spot)
## for one step of `dt` seconds.
static func lane_move(m: Minion, dt: float) -> void:
	var goal: Vector2
	# Step 1: where to go. A "move" or "hold" order goes to the ordered spot
	# (both work the same way here).
	match str(m.order.get("type", "lane")):
		"move", "hold":
			goal = m.order.get("pos", m.position)
		_:
			# No lane points at all: head straight for the enemy mothership.
			if m.path.is_empty():
				goal = m.world.mothership(1 - m.team).position
			else:
				# Move on to the next lane point once within 700 of this one.
				m.path_i = Steer.advance(m.path, m.path_i, m.position, 700.0)
				goal = m.path[m.path_i]
				# Lanes end at the enemy base; the mothership may have moved
				# (from 20:00), so the last leg goes to where it is now.
				if m.path_i >= m.path.size() - 1:
					var ems := m.world.mothership(1 - m.team)
					if ems != null and ems.alive:
						goal = ems.position
	# Step 2: fly there at the wave's pace (never faster than
	# Minions.FORMATION_SPEED, 330 world units per second, so the wave
	# stays together), slowing down within 300 of the goal, plus the rock
	# push. The wanted velocity is the one Steer.seek() works out for the
	# other light units: straight at the goal at that pace, and in
	# proportion to the distance left inside 300 of it (stopping within 1).
	var max_s := minf(m.speed, Minions.FORMATION_SPEED)
	var to := goal - m.position
	var d := to.length()
	var want := Vector2.ZERO
	if d >= 1.0:
		want = to / d * (max_s if d > 300.0 else max_s * d / 300.0)
	steer(m, want, dt)
	m.velocity += m._rock_push * dt
	# Step 3: face the way we fly, but only when moving faster than
	# Minions.MIN_HEADING_SPEED (10 world units per second; length_squared is
	# the speed times itself), so a nearly still minion doesn't spin on the
	# spot.
	if m.velocity.length_squared() > Minions.MIN_HEADING_SPEED * Minions.MIN_HEADING_SPEED:
		face(m, m.velocity.angle(), dt)
