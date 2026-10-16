class_name CombatBeamArea
extends RefCounted
## WHAT THIS IS: the two kinds of damage that are not single rounds: a beam
## (a straight line that hits at once) and a blast (a circle). A part of
## Combat, kept in its own file.
##
## HOW IT WORKS:
##   - beam(): lances and ion beams fire a little every tick. We take the
##     beam's line from its start, find the first thing on it (an asteroid,
##     an enemy unit or an enemy mothership), hurt that unit through
##     Combat.apply_damage(), and return where the beam stops so it can be
##     drawn up to there. If an asteroid comes first, a cutting beam chips
##     it instead (by Rules.ASTEROID_MULT: ion beams x0.6).
##   - area(): a blast at a point hurts every enemy unit whose edge is within
##     the blast radius: full damage within half the radius, then less and
##     less, down to half damage at the very edge. An enemy mothership whose
##     hull is within the radius takes a flat half damage.
## A neutral attacker (a jungle monster) never hurts neutral units.
##
## WHO USES IT: Combat makes one; Combat.beam() and Combat.area() forward
## here. WeaponMount fires beams through Combat.beam(); ProjectilesImpact
## bursts flak through Combat.area().

## The Combat this part belongs to (every hit goes through its
## apply_damage()).
var combat: Combat
## The world (its spatial hash, asteroids and motherships).
var world: World
## A reusable list that the spatial hash fills with nearby units, shared by
## beam() and area() (so we don't make a new list every time).
var _scratch: Array = []


## Remember our Combat and its world. Combat makes this part once.
func _init(owner: Combat) -> void:
	combat = owner
	world = owner.world


## A continuous beam from `from` in direction `dir` (a unit-length vector),
## `length` world units long, fired by unit `src`, with raw damage `dmg` of
## weapon kind `kind`. It hurts the first enemy unit on its line; when an
## asteroid comes first and `cuts` is true, it chips the asteroid instead.
## Returns the point where the beam stops.
func beam(src: Unit, from: Vector2, dir: Vector2, length: float, dmg: float, kind: int, cuts: bool) -> Vector2:
	# Step 1: the beam's line, and the first asteroid on it. best_t says
	# where along the line the first hit is (0 = start, 1 = full length).
	var to := from + dir * length
	var best_t := 1.0
	var best: Unit = null
	var hit := world.asteroids.segment_hit(from, to, 0.0)
	if not hit.is_empty():
		best_t = float(hit["t"])
	# Step 2: the first enemy unit before that, searching the spatial hash
	# around the middle of the line.
	var mid := (from + to) * 0.5
	for u: Unit in world.unit_hash.query(mid, length * 0.5 + 200.0, _scratch):
		if not u.alive or u.team == src.team:
			continue
		if src.team == Rules.NEUTRAL and u.team == Rules.NEUTRAL:
			continue
		var t := u.hit_t(from, to, 2.0)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = u
	# Step 3: the enemy motherships (they are not in the hash).
	for ms: Mothership in world.motherships:
		if ms != null and ms.alive and ms.team != src.team:
			var t := ms.hit_t(from, to, 2.0)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = ms
	# Step 4: hurt what we hit, or chip the asteroid with a cutting beam.
	var end := from.lerp(to, best_t)
	if best != null:
		var info := DamageInfo.from_unit(src, dmg, kind, from)
		combat.apply_damage(best, info)
	elif not hit.is_empty() and cuts:
		world.asteroids.damage(int(hit["index"]), dmg * float(Rules.ASTEROID_MULT.get(kind, 0.0)))
	return end


## A blast at `pos` with radius `r` (world units) that hurts everyone not
## on team `exclude_team`. `src_info` describes the blast (amount = full
## damage, weapon kind, who fired). Each victim gets its own copy of the
## note with the amount scaled by distance, coming from `pos` (so the
## shield zone facing the blast takes it).
func area(src_info: DamageInfo, pos: Vector2, r: float, exclude_team: int) -> void:
	for u: Unit in world.unit_hash.query(pos, r + 200.0, _scratch):
		if not u.alive or u.team == exclude_team:
			continue
		if exclude_team == Rules.NEUTRAL and u.team == Rules.NEUTRAL:
			continue
		# How far the blast centre is from the unit's edge.
		var d := pos.distance_to(u.global_position) - u.radius
		if d > r:
			continue
		# Full damage (k = 1) up to half the radius, then sliding down to
		# half damage (k = 0.5) at the edge.
		var k := 1.0 if d <= r * 0.5 else 1.0 - 0.5 * (d - r * 0.5) / (r * 0.5)
		# This victim's own copy of the note.
		var info := DamageInfo.new()
		info.amount = src_info.amount * k
		info.kind = src_info.kind
		info.source = src_info.source if is_instance_valid(src_info.source) else null
		info.source_uid = src_info.source_uid
		info.source_team = src_info.source_team
		info.source_size = src_info.source_size
		info.source_is_minion = src_info.source_is_minion
		info.source_is_pilot = src_info.source_is_pilot
		info.source_profile = src_info.source_profile
		info.from_pos = pos
		info.small_bonus = src_info.small_bonus
		combat.apply_damage(u, info)
	# Enemy motherships (not in the hash) whose hull is within the radius
	# take a flat half damage. (Their copy of the note has no `source` unit
	# and no small bonus.)
	for ms: Mothership in world.motherships:
		if ms != null and ms.alive and ms.team != exclude_team and ms.hull_dist(pos) < r:
			var info := DamageInfo.new()
			info.amount = src_info.amount * 0.5
			info.kind = src_info.kind
			info.source_team = src_info.source_team
			info.source_size = src_info.source_size
			info.source_is_minion = src_info.source_is_minion
			info.source_is_pilot = src_info.source_is_pilot
			info.source_profile = src_info.source_profile
			info.source_uid = src_info.source_uid
			info.from_pos = pos
			combat.apply_damage(ms, info)
