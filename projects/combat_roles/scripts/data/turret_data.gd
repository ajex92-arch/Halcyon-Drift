class_name TurretData
extends RefCounted
## WHAT THIS IS: the numbers for the defence turrets. Admiral-built turrets
## at resource node slots. DESIGN.md A9.
##
## HOW IT WORKS: the admiral pays from the team treasury to build a turret
## in a free slot next to a resource node (ResourceNode decides where
## building is allowed). TURRETS holds the two turret types; the constants
## below are the special turret rules: pilots must bring minions to hurt a
## turret properly ("backdoor protection"), turrets punish whoever attacks
## a friendly ship nearby, and their damage climbs while they keep shooting
## the same ship.
##
## WHO USES IT: Turret reads its type and the turret rules; AdmiralCommand
## and the AI admiral (AdmiralBuilder) build turrets; the admiral board
## (AdmiralBoardBuild) shows prices; ResourceNode uses BUILD_CLEAR_RADIUS
## and REBUILD_LOCK; CombatScaling applies the backdoor rule; the AI pilots
## (PilotTargeting) know about BACKDOOR_RADIUS.

## The turret types: type id -> its facts. Fields:
##   label    the name players see
##   cost     price [credits, from the team treasury]
##   build    how long it takes to build [seconds]; it can't shoot until
##            it is finished
##   hull     hit points (more with Platform Armor research)
##   shield   shield points (one shared pool, no zones)
##   radius   size, a circle [world units]
##   weapons  its guns (weapon ids from weapons.gd)
##   range    how far away it picks targets [world units] (more with Fire
##            Control research)
##   vision   how far it sees [world units]
##   where    "any" node or only "inner" nodes (near our own mothership).
##            The rule itself is written in ResourceNode.build_blocker();
##            no script reads this field at the moment.
##   blurb    what it does, in words for players
## (Torpedo turrets also need Platform Missiles research.)
const TURRETS := {
	"pd": {"label": "PD Turret", "cost": 450.0, "build": 25.0, "hull": 2500.0, "shield": 600.0, "radius": 60.0,
		"weapons": ["turret_pd_gun"], "range": 1500.0, "vision": 1800.0, "where": "any",
		"blurb": "Rapid point-defense fire. Shreds strike craft and shoots down torpedoes; weak against big hulls."},
	"torp": {"label": "Torpedo Turret", "cost": 750.0, "build": 35.0, "hull": 3000.0, "shield": 700.0, "radius": 70.0,
		"weapons": ["turret_torp"], "range": 2300.0, "vision": 2000.0, "where": "inner",
		"blurb": "Homing torpedoes that punish frigates and capital ships. Only at nodes near our mothership."},
}
## Player damage to a turret is multiplied by this when no minion of the
## attacker's team is within BACKDOOR_RADIUS of the turret.
## (x0.3, so a pilot alone does less than a third of the damage. This is
## "backdoor protection": turrets must be attacked together with a minion
## wave.)
const BACKDOOR_MULT := 0.3
## The distance (world units) around a turret in which a friendly minion
## lifts the backdoor protection.
const BACKDOOR_RADIUS := 1800.0
## An enemy ship that damages one of our ships inside turret range becomes
## the turret's priority target for this long.
## (In seconds.)
const AGGRO_WINDOW := 3.0
## Consecutive shots on the same ship ramp damage by this much, up to max.
## (+0.2 = +20% damage for every shot already fired at that ship; the count
## starts again when the turret switches target.)
const TURRET_RAMP := 0.2
## The most the ramp can add: +1.0 = +100%, so at most double damage.
const TURRET_RAMP_MAX := 1.0
## No enemy ships within this of a node to start building there.
## (In world units.)
const BUILD_CLEAR_RADIUS := 1500.0
## After a turret dies, nothing can be built at that node for this long, so
## a successful push has a window (playtest: rich late-game admirals rebuilt
## every lost turret at once and no base ever fell).
## (In seconds. In plain words: a team that breaks a turret gets 60 seconds
## to push on before the admiral can put a new one there.)
const REBUILD_LOCK := 60.0
