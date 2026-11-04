class_name Structures
extends RefCounted
## WHAT THIS IS: the numbers for the team's support units. Support units:
## repair bays, repair drones, wards, mining drones and the mothership.
## DESIGN.md A11, A12. Turrets live in turret_data.gd.
##
## HOW IT WORKS: one dictionary (a lookup table of named facts) per kind of
## unit. Each unit's script reads its dictionary when it is made. Most of
## these units are bought by the admiral from the team treasury.
## Units: distances and sizes in world units (1 world unit is about one
## pixel at normal zoom), speeds in world units per second, times in
## seconds, prices in credits.
##
## WHO USES IT: RepairBay, RepairDrone, Ward, MiningDrone and Mothership
## read their own entries; AdmiralCommand and the AI admiral (AdmiralAI,
## AdmiralBuilder) check prices and limits; TeamState and TeamDrones run
## the mining-drone factory; WorldSetup makes the starting drones;
## WorldResearch updates drones after research; WorldVisibility uses the
## ward's stealth radius; the admiral board (AdmiralBoardBuild,
## AdmiralBoardMothership), the command overlay (CommandOverlayDraw) and
## UnitVisual show these numbers.

## The repair bay: a small station the admiral launches. It flies to the
## chosen spot, anchors there for good, and its repair drones heal nearby
## friendly ships. Fields:
##   label, cost (from the treasury), hull, radius, vision, blurb
##   speed               how fast it flies to its spot
##   range               its drones heal ships within this distance of the
##                       bay
##   drones              1. (Not read: the number of drones per bay is
##                       TeamState.bay_drones, which also starts at 1 and
##                       grows with Repair Drones research.)
##   drone_rebuild       seconds to replace a lost drone
##   lockout             after the bay's own hull is hit, its drones stop
##                       healing for this many seconds
##   max_per_team        the most living bays a team may have
##   defense_shield      with Bay Defenses research: its shield points
##   defense_weapon      with Bay Defenses research: its gun (weapon id)
##   module_swap_radius  pilots this close to the bay may swap modules
const REPAIR_BAY := {"label": "Repair Bay", "cost": 450.0, "hull": 600.0, "radius": 40.0, "speed": 380.0,
	"range": 1400.0, "vision": 1200.0, "drones": 1, "drone_rebuild": 15.0, "lockout": 5.0, "max_per_team": 3,
	"defense_shield": 400.0, "defense_weapon": "bay_pd", "module_swap_radius": 600.0,
	"blurb": "Flies to the spot you pick and anchors there for good. Its repair drones heal nearby friendly ships."}

## Repair drones (from bays, Logistics corvettes and repair kits).
## Indexed by target size class: small, medium, large, capital.
## Fields: hp (its hit points), speed, radius, heal (hull points per second
## that one drone gives a ship of each size) and per_target (the most
## drones that may work on one ship of each size). So big ships take more
## drones but heal slowly for their size. Logistics drones repair
## structures (turrets, bays, the mothership) at half the medium rate.
const REPAIR_DRONE := {"hp": 40.0, "speed": 520.0, "radius": 6.0,
	"heal": [8.0, 14.0, 18.0, 22.0], "per_target": [1, 2, 3, 4]}
## The weaker drone from a repair kit: it heals only its owner's ship and
## disappears after `duration` seconds. hp and heal (per size class, hull
## points per second) as above; it flies like a normal repair drone.
const KIT_DRONE := {"hp": 25.0, "heal": [5.0, 8.0, 10.0, 12.0], "duration": 10.0}
## Logistics corvette drones heal like bay drones and also repair structures.
## They work within this distance (world units) of their corvette.
const LOGISTICS_DRONE_RANGE := 1200.0

## The ward: a small sensor drone that flies to a spot, anchors there and
## keeps watch. Fields:
##   label, cost (from the treasury), hp, radius, blurb
##   max_per_team    the most a team may have; placing one more shuts the
##                   oldest one down
##   speed           how fast it flies to its spot
##   vision          how far it sees (x1.4 with Sensor Probes research)
##   stealth_radius  enemies see a ward only when one of their units is
##                   this close to it (or when a Scout Ping reveals it)
const WARD := {"label": "Ward", "cost": 75.0, "max_per_team": 6, "hp": 25.0, "speed": 900.0, "vision": 1400.0,
	"stealth_radius": 500.0, "radius": 8.0,
	"blurb": "A small drone that flies to a spot you can currently see, anchors there and keeps watch."}

## The mining drone: a small robot ship that flies to an ore node, mines
## ore and carries it home, which pays the team. Fields:
##   label, cost (from the treasury), hp, speed, radius, vision
##   accel       how fast it speeds up [world units per second, per second]
##   max         the most a team may have, alive plus ordered
##   start       how many each team starts with
##   capacity    ore carried per trip (more with Improved Mining research)
##   mine_rate   ore mined per second
##   build       seconds to build each ordered drone (one at a time)
##   free_floor  while a team has fewer drones than this (alive plus
##               ordered), the mothership builds free ones...
##   free_every  ...one every this many seconds
const MINING_DRONE := {"label": "Mining Drone", "cost": 200.0, "max": 14, "start": 4, "hp": 140.0, "speed": 460.0,
	"accel": 300.0, "capacity": 300.0, "mine_rate": 40.0, "radius": 14.0, "vision": 700.0, "build": 6.0,
	"free_floor": 3, "free_every": 20.0}

## The mothership: the team's huge home ship. Destroying it wins the game.
## Fields:
##   hull, shield     hit points and shield points (one shield pool)
##   shield_regen     shield points refilled per second
##   shield_delay     seconds after a hit before the shield refills
##   hull_resist      the share of each hull hit that is blocked (0.1 = 10%)
##   length, beam     the hull's length and width (the "beam" of a ship is
##                    its width); hits are tested against this long shape
##   vision           how far it sees
##   move_speed       how fast it moves once moving is allowed (only 30% of
##                    this while its nose points more than 0.6 radians,
##                    about 34 degrees, away from where it is going)
##   turn             turning speed [radians per second]
##   *_mounts         gun spots (see the notes inside)
##   dock_radius      pilots this close to the hull may dock
##   retreat_threshold, retreat_time  the one-time retreat at 35% hull
##                    (Rules.VARIANT_DEFAULTS "retreat"): a 45 s systems
##                    failure
const MOTHERSHIP := {
	"hull": 16000.0, "shield": 6000.0, "shield_regen": 40.0, "shield_delay": 10.0, "hull_resist": 0.1,
	"length": 1600.0, "beam": 340.0, "vision": 4500.0, "move_speed": 80.0, "turn": 0.05,
	## Base guns: local offsets along the keel (x forward), y starboard.
	## (Positions on the hull: x forward along the keel, the ship's
	## backbone; y to the right, "starboard".) 6 point-defense guns and 2
	## cannons from the start.
	"pd_mounts": [Vector2(560, -120), Vector2(560, 120), Vector2(100, -150), Vector2(100, 150), Vector2(-400, -130), Vector2(-400, 130)],
	"cannon_mounts": [Vector2(300, -100), Vector2(300, 100)],
	## Upgrade mounts, filled in order as research completes.
	## (PD Grid II fills the 4 extra PD spots, Flak Batteries the 4 flak
	## spots, Heavy Batteries I and II two heavy spots each, Ion Lance the
	## ion spot.)
	"extra_pd_mounts": [Vector2(700, 0), Vector2(-150, -160), Vector2(-150, 160), Vector2(-650, 0)],
	"flak_mounts": [Vector2(450, -140), Vector2(450, 140), Vector2(-250, -150), Vector2(-250, 150)],
	"heavy_mounts": [Vector2(200, -60), Vector2(200, 60), Vector2(-300, -60), Vector2(-300, 60)],
	"ion_mounts": [Vector2(650, 0)],
	"dock_radius": 520.0,
	"retreat_threshold": 0.35, "retreat_time": 45.0,
}
