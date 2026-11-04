class_name LanceRoleGoals
extends PilotGoals
## WHAT THIS IS: a version of the AI pilot's "where to fly" part
## (PilotGoals) used by the lance_role variant. It thinks exactly like the
## original, and then lets a Lance Fighter pick an isolated enemy big ship
## as prey (LanceRoleFeature.hunt).
##
## HOW IT WORKS: think_lane() and think_jungle() call the original through
## super, then LanceRoleFeature.hunt(). For every pilot who does not fly a
## Lance, hunt() returns at once, so they play as before. RoleBrains puts
## this part into the brains of the pilots while the variant is on.
##
## WHO USES IT: RoleBrains (installed by LanceRoleFeature); PilotAI._think()
## calls the two functions below through brain.goals.


## Lane state: the original thinking, then the Lance hunt.
func think_lane(ship: Ship) -> void:
	super.think_lane(ship)
	LanceRoleFeature.hunt(ai, ship)


## Jungle state: the original thinking, then the Lance hunt.
func think_jungle(ship: Ship) -> void:
	super.think_jungle(ship)
	LanceRoleFeature.hunt(ai, ship)
