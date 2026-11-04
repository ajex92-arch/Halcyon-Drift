class_name LanceRoleCombat
extends PilotCombat
## WHAT THIS IS: a version of the AI pilot's "fight the target" part
## (PilotCombat) used by the lance_role variant. A Lance Fighter that is
## hunting an isolated enemy big ship flies round to its tail before it
## fires (LanceRoleFeature.steer_behind).
##
## HOW IT WORKS: fight() does what the original does, then calls
## LanceRoleFeature.steer_behind(), which changes the controls only for a
## Lance whose intent is "prey" and whose target is a big ship that it is not
## behind yet. For everyone else it changes nothing. RoleBrains puts this
## part into the pilots' brains while the variant is on.
##
## WHO USES IT: RoleBrains (installed by LanceRoleFeature); PilotCombat.steer()
## calls fight() through brain.combat.


## Fight the brain's target: the original steering, then the Lance's
## approach to the tail.
func fight(ship: Ship) -> void:
	super.fight(ship)
	LanceRoleFeature.steer_behind(ai, ship)
