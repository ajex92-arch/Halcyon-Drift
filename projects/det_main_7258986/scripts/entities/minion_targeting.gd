class_name MinionTargeting
extends RefCounted
## WHAT THIS IS: the "who do I shoot?" rules of a lane minion (a part of
## Minion, kept in its own file).
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Each function is handed the minion and reads or changes the minion's own
## fields (target, position, order...).
##   - pick_target() runs 4 times a second. It gives every enemy in reach
##     (that no rock hides) a score (score_of()): its distance plus a
##     penalty by kind. The LOWEST score wins:
##        enemy ship that just hurt one of our ships nearby   distance - 1200
##        enemy minion                                        distance
##        enemy structure (turret, repair bay)                distance + 600
##        anything else (mining or repair drones, wards)      distance + 900
##        any other enemy ship                                distance + 1200
##     Bombers take 1500 off for structures and medium-or-bigger hulls.
##     The enemy mothership is checked on its own at the end (it isn't in
##     the spatial hash) and scored like a structure, by the distance to
##     its hull.
##     (Speed: the rock check is the costly part, so it is asked only of an
##     enemy that would become the best one so far; a hidden enemy never wins
##     and one that would not win anyway changes nothing, so the answer is the
##     same as checking every enemy.)
##     The current target is not dropped just because the scores changed: it
##     stays while it is still close, visible, near our lane and not hidden
##     behind a rock, unless something else scores at least RETARGET_MARGIN
##     (600) better. (Without that, a minion that had picked a pilot ship
##     kept chasing it when a whole enemy wave arrived.)
##   - score_of() is the score table itself, for one minion and one enemy.
##   - lane_anchor() is the point the leash (Minion.LEASH) is measured from.
##   - target_point() is the spot on the target we aim at and measure to.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: only Minion: _think() calls pick_target(), and sim_update()
## calls target_point().

## How much better (lower, in score points, which are world units of
## distance) a new target must score than the current one before a minion
## gives the current one up. This is a tuning knob: 600 is the head start a
## structure has over a minion in the score table, so a clearly better kind
## wins, while two near-equal targets don't make the minion swap back and
## forth. A bigger number makes minions stick to a target longer.
const RETARGET_MARGIN := 600.0


## Choose what minion `m` fights: sets m.target (null for nobody). Scores
## every enemy in aggro range (score_of(), see HOW IT WORKS above) and keeps
## the current target, if it is still worth keeping, unless the best new one
## scores at least RETARGET_MARGIN (600) better.
static func pick_target(m: Minion) -> void:
	var anchor := lane_anchor(m)
	# Step 1: the current target is worth keeping while it is alive, can be
	# shot, is within 1.15x our aggro range, can be seen by our team, is
	# within LEASH of our anchor, and no rock hides it (a rock stops the
	# rounds). `keep` is it, or null. We still look around below.
	var keep: Unit = null
	if m.target != null and is_instance_valid(m.target) and m.target.alive:
		var tp := target_point(m)
		if m.position.distance_to(tp) < m.aggro * 1.15 and m.target.visible_to(m.team) and tp.distance_to(anchor) < Minion.LEASH \
				and not m.world.asteroids.segment_blocked(m.position, tp):
			keep = m.target
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
		# Step 3: the score (lower is better), see score_of().
		var score := score_of(m, u, now)
		# No targets behind asteroids (turrets pick theirs the same way). The
		# rock check is the costly part, so it is asked only of an enemy that
		# would become the best one: a hidden enemy never wins, and one that
		# would not win anyway changes nothing whether it is hidden or not. The
		# target we keep (step 1) was already found clear along this very
		# line (same two points, rocks only ever disappear), so it is not
		# asked again.
		if score < best_score and (u == keep or not m.world.asteroids.segment_blocked(m.position, u.position)):
			best_score = score
			best = u
	# Step 4: the enemy mothership isn't in the spatial hash (its hull is
	# too long), so check it here: in aggro range of its hull, it scores
	# like a structure (bombers take 1500 off). This check does not look at
	# visibility or the leash.
	var ems := m.world.mothership(1 - m.team)
	if ems != null and ems.alive:
		if ems.hull_dist(m.position) < m.aggro:
			var score := score_of(m, ems, now)
			if score < best_score:
				best = ems
				best_score = score
	# Step 5: the current target (if it was worth keeping) stays unless the
	# best new one scores at least RETARGET_MARGIN better. With nobody else in
	# reach it stays too.
	if keep != null and best != keep and (best == null or best_score > score_of(m, keep, now) - RETARGET_MARGIN):
		best = keep
	m.target = best


## The score (lower is better) that minion `m` gives enemy `u` when it
## chooses a target: the distance (to the hull, for a mothership) plus a
## penalty by kind (the table in HOW IT WORKS at the top). `now` is the match
## time in seconds (World.time).
static func score_of(m: Minion, u: Unit, now: float) -> float:
	# The mothership is scored like a structure, by the distance to its hull.
	if u is Mothership:
		return (u as Mothership).hull_dist(m.position) + 600.0 - (1500.0 if m.mtype == "bomber" else 0.0)
	# A ship that hurt one of our pilot ships in the last 2 s, where that
	# victim was within 1.5x our aggro range of us, gets 2400 off
	# ("aggro_time" is stamped by Combat).
	var score := m.position.distance_to(u.position)
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
	return score


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
