class_name MothershipGuns
extends RefCounted
## WHAT THIS IS: the mothership's guns (a part of Mothership, kept in its
## own file): the guns it starts with, what Flagship research adds (more
## guns, plus a bigger hull and shield), and firing them every tick.
##
## HOW IT WORKS: all its guns are AUTO mounts (WeaponMount): each picks its
## own targets and can swing all the way round (180 degrees either side).
## Their spots on the hull come from Structures.MOTHERSHIP (x along the
## keel toward the nose, y to the right, in world units):
##   - at the start: 6 point defense guns ("ms_pd") and 2 medium cannons
##     ("ms_cannon");
##   - research (TeamState.ms_pd, ms_flak, ms_heavy, ms_ion) adds up to 4
##     more point defense guns, 4 flak guns, 4 heavy batteries and 1 ion
##     lance, filling the listed spots in order. Mothership.applied
##     remembers how many of each are already on, so nothing is added
##     twice.
## Every tick fire() sets the rate-of-fire multiplier (x0.6 during respawn
## strain, x0.5 during a systems failure, both together if both) and lets
## each gun take its turn, with the team's extra range from research
## (TeamState.team_range). This is a "static library": it keeps no memory
## of its own.
##
## WHO USES IT: Mothership: setup() calls add_base_mounts(), sim_update()
## calls fire(), and Mothership.apply_upgrades() forwards to
## apply_upgrades() (the research code calls it when research finishes).


## Bolt the starting guns onto `ms`: point defense first, then cannons.
static func add_base_mounts(ms: Mothership) -> void:
	for p: Vector2 in ms.def["pd_mounts"]:
		ms.mounts.append(WeaponMount.new(ms, "ms_pd", "auto", p, 180.0))
	for p: Vector2 in ms.def["cannon_mounts"]:
		ms.mounts.append(WeaponMount.new(ms, "ms_cannon", "auto", p, 180.0))


## Rebuild `ms`'s hull, shield and guns from team `ts`'s Flagship research.
## Safe to call again: hull and shield are set (not added to), and only
## guns it doesn't have yet are added.
static func apply_upgrades(ms: Mothership, ts: TeamState) -> void:
	# Step 1: the hull grows by ts.ms_hull (a fraction), keeping the same
	# fraction of health; armour grows by 0.2 x that fraction.
	var hull_frac_now := ms.hull_frac()
	ms.hull_max = ms.base_hull_max * (1.0 + ts.ms_hull)
	ms.hull = ms.hull_max * hull_frac_now
	ms.hull_resist = float(ms.def["hull_resist"]) + ts.ms_hull * 0.2
	# Step 2: shield size and refill speed grow by ts.ms_shield.
	ms.shields.set_max(ms.base_shield * (1.0 + ts.ms_shield))
	ms.shields.regen = ms.base_regen * (1.0 + ts.ms_shield)
	# Step 3: add any research guns we don't have yet.
	add_mounts(ms, "ms_pd", ms.def["extra_pd_mounts"], ts.ms_pd, "pd")
	add_mounts(ms, "ms_flak", ms.def["flak_mounts"], ts.ms_flak, "flak")
	add_mounts(ms, "ms_heavy", ms.def["heavy_mounts"], ts.ms_heavy, "heavy")
	add_mounts(ms, "ms_ion", ms.def["ion_mounts"], ts.ms_ion, "ion")


## Add `wid` guns on `spots` (in order) until `ms` has `want` of them or the
## spots run out. `key` is that gun kind's entry in ms.applied.
static func add_mounts(ms: Mothership, wid: String, spots: Array, want: int, key: String) -> void:
	var have: int = ms.applied[key]
	while have < want and have < spots.size():
		ms.mounts.append(WeaponMount.new(ms, wid, "auto", spots[have], 180.0))
		have += 1
	ms.applied[key] = have


## One tick of `dt` seconds for `ms`'s guns: set the rate-of-fire
## multiplier from team `ts`'s respawn strain and our systems failure, then
## let every gun pick a target and shoot. AUTO guns aim for themselves, so
## no aim point or trigger is passed; the shots are free (no battery).
static func fire(ms: Mothership, ts: TeamState, dt: float) -> void:
	ms.fire_mult = (Rules.STRAIN_WEAPON_MULT if ts.strain_t > 0.0 else 1.0) * (0.5 if ms.failure_t > 0.0 else 1.0)
	var range_mult := 1.0 + ts.team_range
	for m in ms.mounts:
		m.update(dt, Vector2.ZERO, false, ms.fire_mult, 1.0, range_mult, null)
