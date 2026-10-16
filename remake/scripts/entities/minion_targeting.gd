class_name MinionTargeting
extends RefCounted
## WHAT THIS IS: the "who do I shoot?" rules of a lane minion (a part of
## Minion, kept in its own file).
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Each function is handed the minion and reads or changes the minion's own
## fields (target, position, order...).
##   - pick_target() runs 4 times a second. It keeps the current target
##     while that is still close, visible, near our lane and not hidden
##     behind a rock. Otherwise it gives every enemy in reach (that no rock
##     hides) a score: its distance plus a penalty by
##     kind. The LOWEST score wins:
##        enemy ship that just hurt one of our ships nearby   distance - 1200
##        enemy minion                                        distance
##        enemy structure (turret, repair bay)                distance + 600
##        anything else (mining or repair drones, wards)      distance + 900
##        any other enemy ship                                distance + 1200
##     Bombers take 1500 off for structures and medium-or-bigger hulls.
##     The enemy mothership is checked on its own at the end (it isn't in
##     the spatial hash) and scored like a structure, by the distance to
##     its hull.
##   - lane_anchor() is the point the leash (Minion.LEASH) is measured from.
##   - target_point() is the spot on the target we aim at and measure to.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: only Minion: _think() calls pick_target(), and sim_update()
## calls target_point().


## Choose what minion `m` fights: sets m.target (null for nobody). Keeps
## the current target if it is still worth it; otherwise scores every enemy
## in aggro range (see HOW IT WORKS above).
static func pick_target(m: Minion) -> void:
	var anchor := lane_anchor(m)
	# Step 1: stay on the current target while it is alive, can be shot, is
	# within 1.15x our aggro range, can be seen by our team, is within
	# LEASH of our anchor, and no rock hides it (a rock stops the rounds).
	if m.target != null and is_instance_valid(m.target) and m.target.alive:
		var tp := target_point(m)
		if m.position.distance_to(tp) < m.aggro * 1.15 and m.target.visible_to(m.team) and tp.distance_to(anchor) < Minion.LEASH \
				and not m.world.asteroids.segment_blocked(m.position, tp):
			return
	# Step 2: start fresh and look at every unit near us. The spatial hash
	# (World.unit_hash, a grid of the map) finds them quickly.
	m.target = null
	var best: Unit = null
	var best_score := INF
	var now := m.world.time
	for u: Unit in m.world.unit_hash.query(m.position, m.aggro, m._scratch):
		# Skip the dead, the unshootable, friends and neutrals (derelicts).
		if not u.alive or u.team == m.team or u.team == Rules.NEUTRAL:
			continue
		# Only fighters bother with repair drones.
		if u.kind == Unit.K_REPAIR_DRONE and m.mtype != "fighter":
			continue
		# Our team must see it, and it must be in aggro range (measured to
		# its edge) and within LEASH of our anchor.
		if not u.visible_to(m.team):
			continue
		var d := m.position.distance_to(u.position)
		if d > m.aggro + u.radius or u.position.distance_to(anchor) > Minion.LEASH:
			continue
		# No targets behind asteroids (turrets pick theirs the same way).
		if m.world.asteroids.segment_blocked(m.position, u.position):
			continue
		# Step 3: the score (lower is better). A ship that hurt one of our
		# pilot ships in the last 2 s, where that victim was within 1.5x
		# our aggro range of us, gets 2400 off ("aggro_time" is stamped by
		# Combat).
		var score := d
		if u.kind == Unit.K_SHIP:
			score += 1200.0
			if now - u.aggro_time < 2.0 and u.aggro_victim_pos.distance_to(m.position) < m.aggro * 1.5:
				score -= 2400.0
		elif u.kind == Unit.K_MINION:
			score += 0.0
		elif u.is_structure():
			score += 600.0
		else:
			score += 900.0
		# Bombers go for structures and big hulls.
		if m.mtype == "bomber":
			if u.is_structure() or u.size_class >= Rules.SIZE_MEDIUM:
				score -= 1500.0
		if score < best_score:
			best_score = score
			best = u
	# Step 4: the enemy mothership isn't in the spatial hash (its hull is
	# too long), so check it here: in aggro range of its hull, it scores
	# like a structure (bombers take 1500 off). This check does not look at
	# visibility or the leash.
	var ems := m.world.mothership(1 - m.team)
	if ems != null and ems.alive:
		var hd := ems.hull_dist(m.position)
		if hd < m.aggro:
			var score := hd + 600.0 - (1500.0 if m.mtype == "bomber" else 0.0)
			if score < best_score:
				best = ems
	m.target = best


## The point minion `m`'s leash is measured from: its ordered spot for a
## "move" or "hold" order; otherwise the closest point of its lane line
## (the lane's points joined by straight pieces), so long straight lanes
## work. With fewer than 2 lane points it is the minion's own position.
static func lane_anchor(m: Minion) -> Vector2:
	if str(m.order.get("type", "lane")) != "lane":
		return m.order.get("pos", m.position)
	if m.path.size() < 2:
		return m.position
	return Util.project_on_polyline(m.position, m.path)["point"]


## Where minion `m` aims at and measures to on its target: the target's
## centre, or for a mothership the closest point of its keel (the line down
## the middle of its long hull).
static func target_point(m: Minion) -> Vector2:
	if m.target is Mothership:
		var ms := m.target as Mothership
		var f := Vector2.from_angle(ms.rotation) * ms.half_len
		return Util.closest_on_segment(m.position, ms.position + f, ms.position - f)
	return m.target.position
