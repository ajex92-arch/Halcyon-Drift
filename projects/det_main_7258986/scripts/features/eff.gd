class_name EffFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "eff" rule variant: weapon-aware
## target choice for AI pilots (docs/FUN_PLAN.md section 5, endgame_closure
## fork, an optional carry-over from docs/AI_DEEP_DIVE.md section 5 item 3).
## REQ-CHANGE: none. It shortens sieges, so it changes how matches end: in
## the deep dive the matches ended 30-170 s earlier.
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "on"   when an AI pilot scores the enemies in range (PilotTargeting.
##          pick_target), the score also contains how well the pilot's main
##          gun hurts that kind of target: Rules.DAMAGE[weapon kind][target
##          size]. A target the gun does full damage to (1.0) changes
##          nothing; one it does only a quarter to (0.25) scores 450 worse
##          (a world unit of distance counts one point); one it does 1.8
##          times damage to scores 480 better. The most the term moves a
##          score is 500 either way. The "main gun" is the aimed (not
##          automatic) gun with the highest damage per second. With the
##          damage modifiers removed there is no damage table: every gun does
##          full damage to every target, so the term is always 0, "on"
##          changes nothing (the value is still accepted) and "eff_picks"
##          in Game.usage stays 0.
## The AI uses it by itself: the term is part of every think of every AI
## pilot while the variant is on. Counted in Game.usage as "eff_picks": the
## number of target picks whose chosen target had a term of 100 or more
## (better or worse) in its score. The module draws no random numbers and has
## no state.
##
## WHO USES IT: FeatureRegistry installs it for --variant=eff:on (nothing to
## set up); PilotTargeting.pick_target() calls adjust() when
## World.features has "eff".

## The variant key this module belongs to.
const KEY := "eff"
## Score points for each 1.0 of damage-table difference from 1.0.
const POINTS := 600.0
## The most the term moves a score (either way).
const LIMIT := 500.0
## A pick counts as an "eff pick" when the term was at least this big.
const MATERIAL := 100.0


## Nothing to set up: the AI asks adjust() by itself. Only an unknown value
## gets a warning. FeatureRegistry calls this once at match start.
static func install(_world: World) -> void:
	if Game.variant(KEY) != "on":
		push_warning("eff: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))


## The score change for pilot `ship` looking at enemy `u`: negative (better)
## when its main gun does more than normal damage to `u`'s size class,
## positive (worse) when less. 0 for a ship with no aimed gun, when the
## variant is not "on", and always when the damage modifiers are removed
## (there is no damage table to read then).
static func adjust(ship: Ship, u: Unit) -> float:
	if Game.variant(KEY) != "on" or Rules.damage_modifiers_removed():
		return 0.0
	# Step 1: the main gun: the aimed gun with the highest damage per second.
	var best_dps := -1.0
	var kind := -1
	for m: WeaponMount in ship.mounts:
		if m.mount_type == WeaponMount.AUTO:
			continue
		var dps: float = float(m.def.get("dps", 0.0)) if m.is_beam else float(m.def.get("dmg", 0.0)) * float(m.def.get("rate", 1.0))
		if dps > best_dps:
			best_dps = dps
			kind = m.kind
	if kind < 0:
		return 0.0
	# Step 2: how much that gun's damage-table cell differs from 1.0.
	var mult := Rules.damage_mult(kind, clampi(u.size_class, 0, 6))
	return clampf((1.0 - mult) * POINTS, -LIMIT, LIMIT)
