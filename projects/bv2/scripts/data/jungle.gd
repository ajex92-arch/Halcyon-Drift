class_name Jungle
extends RefCounted
## WHAT THIS IS: the numbers for the jungle monsters. The "jungle" is the
## rocky space between the lanes; its monsters are derelict hulls (old,
## abandoned ships) with automated turrets and, for the bigger camp,
## automated snub fighters. Killing one pays the pilots who fought it.
## DESIGN.md A10.
##
## HOW IT WORKS: CAMPS describes the two kinds of monster camp, SNUB the
## small fighters a Carrier launches. Monsters are neutral (team 2): they
## fight whoever attacks them or comes too close, and reset when attackers
## leave the leash (the circle around their home spot that they never leave
## to chase). A reset monster stops shooting and heals back up. Where the
## camps are on the map is written in MapLayout.CAMPS.
##
## Tuning target (playtest 2026-10-13): a lone Fighter should beat a
## Gunship in about 20 seconds, finishing with its shield used up; a
## Carrier (with its snubs) should need two pilots or a well-flown Lance
## Fighter. The first numbers (900 hull, 32 damage per second) simply
## killed pilots who went into the jungle alone ("junglers").
##
## WHO USES IT: JungleDirector spawns the camps and brings them back after
## "respawn" seconds; World makes the units (WorldSpawner); Derelict (the
## monster) and SnubFighter read their numbers; Economy pays the reward.

## The two kinds of camp: camp type -> its facts. Fields:
##   label       the name players see
##   hull        hit points
##   radius      size, a circle [world units]
##   turrets     how many guns it has
##   weapon      the weapon id of each gun (weapons.gd)
##   aggro       it attacks enemies this close [world units]; anyone who
##               hurt it in the last 8 s is attacked from farther away too
##   leash       it never targets anything farther than this from its home
##               spot [world units]
##   reward      credits shared by the pilots who helped kill it (Economy)
##   respawn     seconds after its death before the camp comes back
##   snubs       how many snub fighters it keeps out at once
##   snub_every  (Carrier only) seconds between snub launches (12 if
##               missing)
const CAMPS := {
	"gunship": {"label": "Derelict Gunship", "hull": 600.0, "radius": 50.0, "turrets": 2, "weapon": "monster_gun",
		"aggro": 700.0, "leash": 2500.0, "reward": 110.0, "respawn": 80.0, "snubs": 0},
	"carrier": {"label": "Derelict Carrier", "hull": 1000.0, "radius": 70.0, "turrets": 1, "weapon": "monster_gun",
		"aggro": 700.0, "leash": 2500.0, "reward": 200.0, "respawn": 120.0, "snubs": 2, "snub_every": 12.0},
}

## The snub fighter a Carrier launches. Fields: label, hull, speed [world
## units per second], accel [world units per second, per second], turn
## [radians per second], radius [world units], weapon (weapon id).
## Its "vision" and "leash" are not read at the moment: a snub follows its
## carrier's fight and flies home when that fight ends (SnubFighter).
const SNUB := {"label": "Snub Fighter", "hull": 45.0, "speed": 520.0, "accel": 520.0, "turn": 3.2, "radius": 8.0,
	"weapon": "snub_gun", "vision": 900.0, "leash": 2200.0}

## Last hit earns this much extra on top of the damage split.
## (0.25 = 25% of the monster's reward, for the pilot who made the killing
## blow, if they are one of the helpers who share the reward.)
const LAST_HIT_BONUS := 0.25
## Monsters regenerate this fraction of hull per second once reset.
## (0.2 = 20% of their full hull per second. A monster resets after 6
## seconds without a fight.)
const RESET_REGEN := 0.2
