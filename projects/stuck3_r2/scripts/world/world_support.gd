class_name WorldSupport
extends RefCounted
## WHAT THIS IS: the aura of support corvettes. A support corvette (a ship
## whose hull has "aura" in its data) helps friendly ships around it and
## "paints" enemy ships so that torpedoes hurt them more (while the damage
## modifiers are kept; with them removed the mark is still made but changes no
## damage).
##
## HOW IT WORKS: every 0.25 s, for each live aura ship:
##   - every other friendly pilot ship within 900 world units gets the
##     support buff for the next 0.6 s (Ship.support_t). If the buff had
##     run out, the ship is told to recompute its stats.
##   - every enemy pilot ship within 1800 world units is painted for the
##     next 1.5 s (Ship.paint_t; CombatScaling checks it for torpedo hits
##     while the damage modifiers are kept).
## The buff (0.6 s) lasts longer than the gap between checks (0.25 s), so
## it doesn't flicker while a ship stays in range.
##
## WHO USES IT: World makes one (World.support) and calls tick() every
## tick, right after the vision update.

## The world whose ships we check.
var world: World
## Seconds until the next aura check (counts down every tick).
var pass_t := 0.0
## A reusable list the spatial hash fills with nearby units.
var scratch: Array = []


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## Called by World every tick: count down, and run the aura check every
## 0.25 s.
func tick(dt: float) -> void:
	pass_t -= dt
	if pass_t <= 0.0:
		pass_t = 0.25
		support_pass()


## Support corvettes: buff nearby allies, paint enemies for bombers (see
## HOW IT WORKS at the top).
func support_pass() -> void:
	for s in world.ships:
		# Only live ships with an aura.
		if not s.alive or not s.def.get("aura", false):
			continue
		# Look at every pilot ship within 1800 world units (except itself).
		for u: Unit in world.unit_hash.query(s.global_position, 1800.0, scratch):
			if not (u is Ship) or not u.alive or u == s:
				continue
			var d := u.global_position.distance_to(s.global_position)
			# A friend within 900: support buff (restat if it had run out).
			if u.team == s.team and d < 900.0:
				if (u as Ship).support_t <= 0.0:
					(u as Ship).stats_dirty = true
				(u as Ship).support_t = 0.6
			# An enemy within 1800: painted.
			elif u.team != s.team and d < 1800.0:
				(u as Ship).paint_t = 1.5
