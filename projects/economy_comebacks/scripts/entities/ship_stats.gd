class_name ShipStats
extends RefCounted
## WHAT THIS IS: the "calculator" of a pilot ship (a part of Ship, kept in
## its own file). It works out the ship's real numbers right now: top speed,
## engine push, turning, boost, rate of fire, damage, reach, hull, shields,
## battery and vision.
##
## HOW IT WORKS: this is a "static library": it keeps no memory of its own.
## recompute() is handed the ship and writes the results into the ship's
## own variables (f_max, f_accel, fire_mult, hull_max, ...). It starts from
## the hull's base numbers (Ships.HULLS, the ship's `def`) and multiplies in,
## in this order:
##   1. the pilot's gear and the fitted modules, added up in a StatBlock
##      (percent bonuses are fractions: 0.10 means +10%);
##   2. the team's tech upgrades for this size of ship (drive: +8% top speed
##      and +6% engine push per level; armour: +15% hull per level);
##   3. the energy routing setting (EnergyPool.m());
##   4. buffs: ace (Rules.ACE_SPEED, Rules.ACE_DAMAGE), standing in the
##      team's waypoint (Rules.WAYPOINT_*), a friendly Support ship's aura
##      (+6% turning, +6% damage, +8% reach), being EMP'd (engines at 35%,
##      no boost), and the hull's special while it is active.
## When the hull, shield or battery size changes, the ship keeps the same
## fraction it had (half full stays half full).
##
## WHO USES IT: only Ship.recompute_stats(), which forwards here. Ship runs
## it at launch (with a full repair), every 0.25 s, and on the next tick
## whenever `stats_dirty` is set (gear or module changes, ace, auras, EMP,
## routing changes, specials starting or ending).


## Rebuild all of `ship`'s worked-out numbers (see HOW IT WORKS). With
## `full_heal`, also fill the hull, shields and battery to the top (used at
## launch).
static func recompute(ship: Ship, full_heal: bool) -> void:
	# The ship's objects we use a lot (these are shared, not copies).
	var stats := ship.stats
	var energy := ship.energy
	var shields := ship.shields
	var def := ship.def
	ship.stats_dirty = false
	ship.stats_t = 0.25

	# Step 1: add up the pilot's gear and the fitted modules.
	stats.clear()
	if ship.profile != null:
		stats.add_dict(ship.profile.gear_stats().v)
	for mid: String in ship.modules:
		stats.add_dict(Modules.MODULES[mid]["stats"])

	# Step 2: the team's tech levels for our size ("small", "medium",
	# "large" or "capital"), and whether we sit in the team's waypoint.
	var t: TeamState = ship.world.teams[ship.team] if ship.world != null else null
	var tier: String = Tech.TIERS[ship.size_class]
	var drive := t.drive_level(tier) if t != null else 0
	var armor := t.armor_level(tier) if t != null else 0
	var thrust := energy.m("thrust")
	var speed_mul := stats.mul("speed_pct") * (1.0 + 0.08 * drive) * thrust
	var accel_mul := stats.mul("accel_pct") * (1.0 + 0.06 * drive) * thrust
	var turn_mul := stats.mul("turn_pct") * energy.m("turn")
	var in_wp := t != null and t.in_waypoint(ship.global_position)
	if ship.ace_t > 0.0:
		speed_mul *= Rules.ACE_SPEED
	if in_wp:
		speed_mul *= Rules.WAYPOINT_SPEED
	if ship.support_t > 0.0:
		turn_mul *= 1.06

	# Step 3: flight numbers. (Strafe uses its own gear bonus instead of
	# the engine-push one, so we divide that one back out.)
	ship.f_max = float(def["max"]) * speed_mul
	ship.f_accel = float(def["accel"]) * accel_mul
	ship.f_reverse = float(def["reverse"]) * accel_mul
	ship.f_strafe = float(def["strafe"]) * stats.mul("strafe_pct") * accel_mul / stats.mul("accel_pct")
	ship.f_turn = float(def["turn"]) * turn_mul
	ship.f_bleed = float(def["turn_bleed"])
	ship.f_assist = float(def["assist"])
	ship.f_cap_rate = float(def["cap_rate"])

	# Step 4: boost. Hulls built with a booster use their own numbers; any
	# other hull can boost only with a Boost Cell module, which gives
	# 1.4x push (more with boost gear) and up to 12% over top speed.
	var has_boost := bool(def["has_boost"])
	var boost_cell := ship.modules.has("boost_cell")
	ship.can_boost = (has_boost or boost_cell) and ship.emp_t <= 0.0
	var boost_pct := stats.g("boost_pct")
	ship.f_boost_mul = float(def["boost_mul"]) * (1.0 + 0.5 * boost_pct) if has_boost else 1.0 + 0.4 * (1.0 + boost_pct)
	ship.f_boost_cap = float(def["boost_cap"]) if has_boost else 1.12
	ship.f_boost_drain = float(def["boost_drain"]) * energy.m("boost_cost") / (1.0 + boost_pct)
	# An EMP leaves the engines at 35%.
	if ship.emp_t > 0.0:
		ship.f_accel *= 0.35
		ship.f_reverse *= 0.35
		ship.f_strafe *= 0.35

	# Step 5: guns. Buffs, then the specials that boost them while active:
	# Overload (Lance) +60% damage, Overcharge (Destroyer) double fire
	# rate, Broadside (Battlecruiser) +50% fire rate.
	ship.fire_mult = energy.m("fire") * stats.mul("fire_rate_pct")
	ship.dmg_mult = stats.mul("damage_pct")
	if ship.ace_t > 0.0:
		ship.dmg_mult *= Rules.ACE_DAMAGE
	if ship.support_t > 0.0:
		ship.dmg_mult *= 1.06
	ship.range_mult = 1.0 + (t.team_range if t != null else 0.0) + (0.08 if ship.support_t > 0.0 else 0.0)
	if ship.hull_id == "lance" and ship.special_t > 0.0:
		ship.dmg_mult *= 1.6
	if (ship.hull_id == "destroyer" and ship.special_t > 0.0):
		ship.fire_mult *= 2.0
	if ship.hull_id == "battlecruiser" and ship.special_t > 0.0:
		ship.fire_mult *= 1.5

	# Step 6: shield refill, crash armour and how well we take repairs.
	ship.regen_mult = energy.m("regen") * stats.mul("shield_regen_pct") * (Rules.WAYPOINT_SHIELD_REGEN if in_wp else 1.0)
	ship.shield_delay_bonus = stats.g("shield_delay")
	ship.collision_resist = clampf(stats.g("collision_resist"), 0.0, 0.9)
	ship.repair_recv = stats.mul("repair_recv_pct")

	# Step 7: defence pools. A bigger or smaller hull keeps the same
	# fraction of hull points; armour resist is capped at 0.75.
	var new_hull_max := float(def["hull"]) * stats.mul("hull_pct") * (1.0 + 0.15 * armor)
	# Fleet Doctrine (DoctrineFeature): +2% max hull and +3% shield refill
	# per finished level; nothing at level 0.
	if t != null and t.doctrine_level > 0:
		new_hull_max *= 1.0 + DoctrineFeature.HULL_PER_LEVEL * float(t.doctrine_level)
		ship.regen_mult *= 1.0 + DoctrineFeature.REGEN_PER_LEVEL * float(t.doctrine_level)
	if absf(new_hull_max - ship.hull_max) > 0.01:
		var frac := ship.hull / ship.hull_max if ship.hull_max > 0.0 else 1.0
		ship.hull_max = new_hull_max
		ship.hull = ship.hull_max * frac
	if full_heal:
		ship.hull = ship.hull_max
	ship.hull_resist = clampf(float(def["hull_resist"]) + stats.g("hull_resist"), 0.0, 0.75)
	# Shields and battery: resize only when the size really changed.
	var new_shield := float(def["shield"]) * stats.mul("shield_pct")
	if absf(new_shield - shields.max_total) > 0.01:
		shields.set_max(new_shield)
	shields.resist = clampf(float(def["shield_resist"]) + stats.g("shield_resist"), 0.0, 0.75)
	var new_energy := float(def["energy"]) * stats.mul("energy_pct")
	if absf(new_energy - energy.max_value) > 0.01:
		energy.set_max(new_energy)
	energy.regen = float(def["energy_regen"]) * stats.mul("energy_regen_pct")

	# Step 8: vision (+20% with the team's Advanced Sensors facility, more
	# inside the waypoint).
	var vis := float(def["vision"]) * stats.mul("vision_pct")
	if t != null and t.facilities.has("sensors"):
		vis *= 1.2
	if in_wp:
		vis *= Rules.WAYPOINT_VISION
	ship.vision_radius = vis

	# Step 9: at launch, top everything up.
	if full_heal:
		shields.fill()
		energy.value = energy.max_value
