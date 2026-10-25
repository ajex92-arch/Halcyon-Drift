class_name WorldSeparation
extends RefCounted
## WHAT THIS IS: gentle shoves that stop units from sitting inside each
## other: pilot ships push apart from pilot ships, and minions from
## minions.
##
## HOW IT WORKS:
##   - Pilot ships, every tick: when two ships overlap (their centres are
##     closer than their two radii added together), both are moved apart
##     until they just touch. The bigger ship moves less: each ship's
##     "weight" is its radius x radius. If they are flying into each
##     other, half of that closing speed is taken away too (a soft bump).
##   - Minions, 20 times a second: a minion closer to another minion than
##     their two radii plus 10 world units moves itself away by half of
##     the overlap (the other minion moves on its own turn).
##
## WHO USES IT: World makes one (World.separation) and calls separate()
## every tick, after all units have moved and before the projectiles.

## The world whose ships and minions we push.
var world: World
## Seconds until the next minion push (counts down every tick).
var minion_t := 0.0
## A reusable list the spatial hash fills with nearby units.
var scratch: Array = []


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## Light shoves between overlapping pilot ships (every tick), and between
## minions (every 1/20 s). `dt` is the tick's length in seconds.
func separate(dt: float) -> void:
	for a in world.ships:
		if not a.alive:
			continue
		# Each pair is handled once: only by the ship with the lower id. The search
		# adds the biggest unit radius, so a big ship that overlaps `a` is found
		# even though its centre is far away.
		for b: Unit in world.unit_hash.query(a.global_position, a.radius + Projectiles.MAX_UNIT_RADIUS, scratch):
			if not (b is Ship) or b == a or not b.alive or b.uid < a.uid:
				continue
			# Overlapping? (Skip exact same spots: no direction to push.)
			var d := a.global_position.distance_to(b.global_position)
			var min_d := a.radius + b.radius
			if d >= min_d or d < 0.001:
				continue
			# Push both apart along the line between them, split by weight:
			# `n` is that direction, `pen` how deep they overlap.
			var n := (b.global_position - a.global_position) / d
			var ma := a.radius * a.radius
			var mb := b.radius * b.radius
			var pen := min_d - d
			a.global_position -= n * pen * mb / (ma + mb)
			b.global_position += n * pen * ma / (ma + mb)
			# If they are closing in, take away half the closing speed.
			var rel := (b.velocity - a.velocity).dot(n)
			if rel < 0.0:
				a.velocity += n * rel * 0.5 * mb / (ma + mb)
				b.velocity -= n * rel * 0.5 * ma / (ma + mb)
	# Minions: only every 1/20 s.
	minion_t -= dt
	if minion_t > 0.0:
		return
	minion_t = 1.0 / 20.0
	for a in world.minions:
		if not a.alive:
			continue
		for b: Unit in world.unit_hash.query(a.global_position, a.radius * 2.0 + 40.0, scratch):
			if b == a or not b.alive or b.kind != Unit.K_MINION:
				continue
			# Closer than both radii plus 10? Step back by half the overlap.
			var d := a.global_position.distance_to(b.global_position)
			var min_d := a.radius + b.radius + 10.0
			if d >= min_d or d < 0.001:
				continue
			a.global_position -= (b.global_position - a.global_position) / d * (min_d - d) * 0.5
