class_name WeaponMountTargeting
extends RefCounted
## WHAT THIS IS: the "eyes" of an AUTO gun mount (flak and point defense):
## it decides what the gun shoots at, and where exactly to aim. A part of
## WeaponMount, kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Each function is handed the mount it works on and reads and changes that
## mount's own fields (target, target_torp).
##   - pick_target() looks at the enemies in range and chooses the best one
##     by the weapon's "prefer" setting ("small", "large" or "torp_small").
##     Point defense ("torp_small") can also choose an enemy torpedo.
##   - target_point() gives the point to aim at this tick: where the target
##     will be when our round gets there (the "lead point"), or the target
##     itself for beams. It drops targets that died, hid or moved too far.
##
## WHO USES IT: only WeaponMount.update(), for AUTO mounts: pick_target()
## every 0.25-0.35 s and target_point() every tick.

## A reusable list that the spatial hash fills with nearby units, so we
## don't make a new list every time. (The "spatial hash", world.unit_hash,
## sorts units into a grid of cells so "who is near this point?" is quick to
## answer.) The query empties it before filling it, and nothing else uses it
## while pick_target() loops over it.
static var _scratch: Array = []


## Choose the best target within `r` world units of mount `m`, and store it
## in m.target (a unit) or m.target_torp (an enemy torpedo's slot number).
## Closest wins, but units of the wrong size count as 3000 (or 1500)
## world units farther away, so the gun prefers the right size. Enemy wards
## we can't see, neutral units and anything behind an asteroid are skipped.
static func pick_target(m: WeaponMount, r: float) -> void:
	var w := m.owner.world
	m.target = null
	m.target_torp = -1
	if w == null:
		return
	var mp := m.world_pos()
	var prefer: String = str(m.def.get("prefer", ""))
	# Point defense: torpedoes that are already close come first; otherwise
	# shoot strike craft (the bombers launching them), and only fall back to
	# far torpedoes when nothing else is in range. (Playtest: when point
	# defense always went for torpedoes, it never shot the bombers, and the
	# bombers then killed the mothership.)
	if prefer == "torp_small":
		m.target_torp = w.projectiles.nearest_enemy_torp(mp, r * 0.7, m.owner.team)
		if m.target_torp >= 0:
			return
	# Score every enemy unit in range: lower is better.
	var best: Unit = null
	var best_score := INF
	w.unit_hash.query(mp, r, _scratch)
	for u: Unit in _scratch:
		# Skip the dead, the unshootable, friends and neutrals, and enemy
		# wards we can't see.
		if not u.alive or u.team == m.owner.team or u.team == Rules.NEUTRAL:
			continue
		if u.kind == Unit.K_WARD and not u.visible_to(m.owner.team):
			continue
		var d := mp.distance_to(u.global_position)
		if d > r + u.hit_radius():
			continue
		# Start from the distance, then add a penalty for the wrong size.
		var score := d
		match prefer:
			"torp_small", "small":
				if u.size_class != Rules.SIZE_SMALL:
					score += 3000.0
			"large":
				if u.size_class == Rules.SIZE_SMALL:
					score += 3000.0
				elif u.size_class == Rules.SIZE_MEDIUM:
					score += 1500.0
		# Keep the best one we have a clear line to (no asteroid between).
		if score < best_score and not w.asteroids.segment_blocked(mp, u.global_position):
			best_score = score
			best = u
	m.target = best
	# Point defense with no small ship to shoot: try any torpedo in range.
	if prefer == "torp_small" and (best == null or best.size_class != Rules.SIZE_SMALL):
		var far := w.projectiles.nearest_enemy_torp(mp, r, m.owner.team)
		if far >= 0:
			m.target = null
			m.target_torp = far


## Where mount `m` should aim this tick, or Vector2(INF, INF) for "nothing
## to shoot". INF ("infinity") is a special number bigger than any other,
## used here as a "no answer" marker. Rounds take time to fly, so we aim at
## the "lead point" (where the target will be when the round arrives,
## Util.lead_point); beams hit instantly, so they aim straight at it.
static func target_point(m: WeaponMount) -> Vector2:
	var w := m.owner.world
	var mp := m.world_pos()
	var speed: float = float(m.def.get("speed", 1000.0))
	# A torpedo target: drop it once it is gone, else lead it.
	if m.target_torp >= 0:
		if not w.projectiles.is_live_torp(m.target_torp, m.owner.team):
			m.target_torp = -1
			return Vector2(INF, INF)
		var tp: Vector2 = w.projectiles.pos[m.target_torp]
		var tv: Vector2 = w.projectiles.vel[m.target_torp]
		if m.is_beam:
			return tp
		return Util.lead_point(mp, m.owner.velocity * 0.35, tp, tv, speed)
	# A unit target: drop it if it is gone, dead or can't be shot.
	if m.target == null or not is_instance_valid(m.target) or not m.target.alive:
		m.target = null
		return Vector2(INF, INF)
	# Drop it once it is more than 10% past our reach (plus its size).
	var reach_now := maxf(m.reach, m.range_now) * 1.1
	if mp.distance_to(m.target.global_position) > reach_now + m.target.hit_radius():
		m.target = null
		return Vector2(INF, INF)
	if m.is_beam:
		return m.target.global_position
	return Util.lead_point(mp, m.owner.velocity * 0.35, m.target.global_position, m.target.velocity, speed)
