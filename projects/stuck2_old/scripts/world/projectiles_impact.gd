class_name ProjectilesImpact
extends RefCounted
## WHAT THIS IS: what happens when a round hits something or runs out of
## time: the damage, the sparks and the flak bursts. A part of Projectiles,
## kept in its own file.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## Projectiles hands it itself and the round's slot number, and it reads
## that slot's facts (damage, burst radius, ...):
##   - hit(): the round touched a unit, a mothership or an asteroid.
##       * Flak that touches a unit bursts at that point: area damage to
##         every enemy inside its burst radius (Combat.area) and a burst
##         ring.
##       * Any other round damages just the unit it hit
##         (Combat.apply_damage) and makes a spark in the team's colour
##         (a bigger one for torpedoes and shells).
##       * An asteroid stops the round. Capital guns ("cuts") chip it
##         (AsteroidField.damage). Flak shows its burst ring there but deals
##         no area damage; other rounds make a small rock-coloured spark.
##   - expire(): a flak round that runs out of time bursts where it is
##     (area damage and a ring). Other rounds just vanish.
##   - info(): fills in the DamageInfo note for a hit.
## It never removes the round: Projectiles does that right after.
##
## WHO USES IT: only Projectiles._step().


## Round `i` of pool `proj` (weapon kind `k`, fired by team `my_team`) hit
## something at point `at`. `hit_unit` is the unit or mothership it hit, or
## null when it hit the asteroid described by `rock` ({"index", "t"} from
## AsteroidField.segment_hit()).
static func hit(proj: Projectiles, i: int, at: Vector2, hit_unit: Unit, rock: Dictionary, k: int, my_team: int) -> void:
	var w := proj.world
	if hit_unit != null:
		# A unit: flak bursts for area damage; anything else hurts only
		# the unit it hit.
		if k == Rules.W_FLAK:
			w.combat.area(info(proj, i, at), at, proj.burst[i], my_team)
			w.effects.flak_burst(at, proj.burst[i], Palette.bolt(my_team))
		else:
			w.combat.apply_damage(hit_unit, info(proj, i, at))
			w.effects.spark(at, Palette.bolt(my_team), k == Rules.W_TORP or k == Rules.W_SHELL)
	else:
		# An asteroid: capital guns chip it, then show a burst or a spark.
		if proj.cuts[i] == 1:
			w.asteroids.damage(int(rock["index"]), proj.dmg[i])
		if k == Rules.W_FLAK:
			w.effects.flak_burst(at, proj.burst[i], Palette.bolt(my_team))
		else:
			w.effects.spark(at, Palette.ROCK_EDGE, false)


## Round `i` of pool `proj` (weapon kind `k`, team `my_team`) ran out of
## time at point `b`. Flak bursts there; other rounds do nothing here.
static func expire(proj: Projectiles, i: int, b: Vector2, k: int, my_team: int) -> void:
	if k == Rules.W_FLAK:
		proj.world.combat.area(info(proj, i, b), b, proj.burst[i], my_team)
		proj.world.effects.flak_burst(b, proj.burst[i], Palette.bolt(my_team))


## A new DamageInfo note for a hit by round `i` of pool `proj`: its raw
## damage, weapon kind, small-target bonus and everything known about the
## shooter. The hit "comes from" where the round was one tick ago
## (prev[i]), so the shield zone facing the shot takes it. `_at` (the hit
## point) is not used.
static func info(proj: Projectiles, i: int, _at: Vector2) -> DamageInfo:
	var d := DamageInfo.new()
	# How hard, with what, and who fired it.
	d.amount = proj.dmg[i]
	d.kind = proj.kind[i]
	d.source_uid = proj.src_uid[i]
	d.source_team = proj.team[i]
	d.source_size = proj.src_size[i]
	d.source_is_minion = proj.src_minion[i] == 1
	d.source_is_pilot = proj.src_pilot[i] == 1
	d.source_profile = proj.src_profile[i]
	# The shooter itself, only if it still exists.
	var s = proj.src_ref[i]
	if s != null and is_instance_valid(s):
		d.source = s
	# Where it came from, and its bonus against small targets.
	d.from_pos = proj.prev[i]
	d.small_bonus = proj.small_bonus[i]
	return d
