class_name Minions
extends RefCounted
## WHAT THIS IS: the numbers for the lane minions. Lane minions. DESIGN.md
## A8. Low-skill bots that spawn at the mothership in waves and push down
## each lane. (A "minion" is a small computer-flown ship; it is not a
## pilot.)
##
## HOW IT WORKS: TYPES holds the three minion types. WAVE says which
## minions make up one wave, and FIRST_WAVE and WAVE_INTERVAL say when the
## waves leave. Minions get a little tougher as the match goes on
## (scaling()). Late in the match an admiral who builds the Fleet Command
## Module stops the free waves and buys minions instead (buy_cost,
## CONTROL_CAP).
##
## WHO USES IT: MinionDirector sends the waves and sells minions; Minion
## reads its type's numbers; WorldSpawner applies scaling(); the AI admiral
## (AdmiralFleetCommand), AdmiralCommand and the admiral board
## (AdmiralBoardFleet) use the Fleet Command numbers; Economy pays the
## bounty.

## The minion types: type id -> its facts. Fields:
##   label      the name players see
##   size       size class (0 small, 1 medium; see Rules.SIZE_*)
##   hull       hit points
##   shield     shield points: one shared pool (no zones). After 4 s
##              without a hit it refills by a tenth of this number per
##              second
##   speed      top speed [world units per second]; on the lane the whole
##              wave moves at FORMATION_SPEED instead, if that is slower
##   accel      how fast it speeds up [world units per second, per second]
##   turn       turning speed [radians per second]
##   radius     size, a circle [world units]
##   vision     how far it sees [world units]
##   aggro      enemies this close [world units] make it stop and fight
##   weapons    its guns (weapon ids from weapons.gd)
##   bounty     credits for the enemy pilot who makes the killing blow
##              (grows over the match: Rules.MINION_BOUNTY_GROWTH)
##   aim_error  `aim_error` is the random aiming error (radians) that makes
##              them low skill. (Each aim lands up to this much x the
##              distance away from the target; bigger = worse aim.)
##   buy_cost   price in Fleet Command mode [credits, from the treasury]
## Hull, shield and damage are multiplied by scaling() (and by the team's
## Reinforced Waves research) when a minion is made.
const TYPES := {
	"fighter": {"label": "Minion Fighter", "size": 0, "hull": 55.0, "shield": 30.0, "speed": 480.0, "accel": 500.0,
		"turn": 3.0, "radius": 10.0, "vision": 1100.0, "aggro": 1000.0, "weapons": ["m_bolt"], "bounty": 14.0,
		"aim_error": 0.035, "buy_cost": 35.0},
	"bomber": {"label": "Minion Bomber", "size": 0, "hull": 85.0, "shield": 30.0, "speed": 380.0, "accel": 320.0,
		"turn": 1.6, "radius": 15.0, "vision": 1100.0, "aggro": 1200.0, "weapons": ["m_torp"], "bounty": 18.0,
		"aim_error": 0.02, "buy_cost": 50.0},
	"corvette": {"label": "Escort Corvette", "size": 1, "hull": 480.0, "shield": 160.0, "speed": 340.0, "accel": 220.0,
		"turn": 1.0, "radius": 40.0, "vision": 1300.0, "aggro": 1350.0, "weapons": ["m_cannon", "m_pd"], "bounty": 45.0,
		"aim_error": 0.015, "buy_cost": 140.0},
}
## Lane travel pace: the wave moves together at the escort corvette's speed.
## (World units per second. A minion walking its lane never goes faster
## than this, so the faster fighters stay with the corvette.)
const FORMATION_SPEED := 330.0

## The minion types of one lane's wave, in launch order: 1 escort
## corvette, 5 fighters and 4 bombers.
const WAVE := ["corvette", "fighter", "fighter", "fighter", "fighter", "fighter", "bomber", "bomber", "bomber", "bomber"]
## Match time (seconds) when the first free wave leaves: 45 s = 0:45.
const FIRST_WAVE := 45.0
## Seconds between free waves after the first.
const WAVE_INTERVAL := 35.0
## Hull and damage growth per 5 minutes of match time.
## (0.07 = +7% for every full 5 minutes; it also grows their shield.)
const SCALING_PER_5MIN := 0.07
## Fleet Command module: max alive and costs live in TYPES.buy_cost.
## This is the most bought minions a team may have alive at once. Read it
## through control_cap(), which lets the fleet_cap rule variant change it.
const CONTROL_CAP := 30


## The most bought minions a team may have alive at once in this match:
## CONTROL_CAP (30), unless the fleet_cap variant tuned it (FleetCapFeature
## sets the tuned number "fleet_cap"). It is one rule for the whole match,
## so the AI admiral (AdmiralFleetCommand) and a human admiral (the board's
## buy buttons) both end up at MinionDirector.buy(), which asks this, and
## both teams share the same limit.
static func control_cap() -> int:
	return int(Rules.tune("fleet_cap", CONTROL_CAP))


## How much tougher minions made at match time `match_time` (seconds) are:
## 1.0 at the start, then +0.07 for every full 5 minutes (300 s). For
## example 1.14 at 10:00. WorldSpawner multiplies new minions by it.
static func scaling(match_time: float) -> float:
	return 1.0 + SCALING_PER_5MIN * floorf(match_time / 300.0)
