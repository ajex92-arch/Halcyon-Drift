class_name BomberRoleTargeting
extends PilotTargeting
## WHAT THIS IS: a version of the AI pilot's "what to shoot" part
## (PilotTargeting) used by the bomber_role:torp variant. A Bomber on its
## lane normally leaves every small craft alone, because its torpedoes did
## only x0.35 to them and mostly missed. With the torpedo change they do
## x0.6, so a Bomber that has nothing else to shoot may now fire at a small
## enemy PILOT ship (never at small minions or drones).
##
## HOW IT WORKS: pick_target() asks the original first. If a Bomber on the
## lane gets "nothing" (null), it looks for the nearest visible small enemy
## pilot ship within the range it was asked about and, if there is one,
## makes it the target. Everything else is unchanged.
##
## WHO USES IT: RoleBrains (installed by BomberRoleFeature); PilotGoals calls
## pick_target() through brain.targeting.


## The best enemy within `r` of `ship` to shoot, or null: the original
## answer, and for a lane Bomber with no target, the nearest small enemy
## pilot ship in sight.
func pick_target(ship: Ship, r: float) -> Unit:
	var best := super.pick_target(ship, r)
	var brain := ai
	if best != null or ship.hull_id != "bomber" or brain.state != "lane":
		return best
	# Step 1: the nearest visible small enemy pilot ship within r.
	var foe := brain.world.nearest_enemy(ship.global_position, r, ship.team,
		func(u: Unit) -> bool: return u.kind == Unit.K_SHIP and u.size_class == Rules.SIZE_SMALL and u.visible_to(ship.team))
	if foe == null:
		return null
	# Step 2: the usual hand-over to the torpedoes.
	brain.lock_target = foe
	return foe
