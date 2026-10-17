class_name Weapons
extends RefCounted
## WHAT THIS IS: the table of every gun and beam in the game, with its
## numbers: how often it fires, how hard it hits, how far it reaches and so
## on. Weapon definitions. Mounted on hulls (ships.gd), minions, turrets,
## monsters and the mothership.
##
## HOW IT WORKS: WEAPONS is a dictionary (a lookup table): weapon id, such
## as "pd_gun" -> its facts. The other data files name these ids (for
## example a hull's "mounts" list in ships.gd). In the game, each gun on a
## unit is a WeaponMount that reads its facts from here. There are two
## sorts of weapon:
##   - Projectile weapons fire "rounds" (small moving shots) that fly
##     straight (or home in) and hit what they touch.
##   - Beams ("beam": true) are rays that hurt the first thing on their
##     line a little every tick (one small step of the game clock).
##
## Fields:
##   label     the weapon's name (for people reading this table; no script
##             reads it at the moment)
##   kind      bolt | lance | torp | flak | pd | shell | ion  (Rules.KIND_IDS)
##             The kind picks the damage-table row (Rules.DAMAGE) and some
##             behaviour: flak bursts, torpedoes can be shot down.
##   rate      shots per second (projectile weapons)
##   dmg       damage per projectile/pellet before the damage table
##   speed     projectile speed (u/s); life seconds; range = speed * life
##             ("u/s" = world units per second; "life" = how many seconds
##             a round flies before it disappears; flak bursts then)
##   spread    random cone (radians); pellets per shot
##             (each round is turned by a random angle between -spread/2
##             and +spread/2, twice that for guns with more than 2
##             pellets; "pellets" = rounds fired at once, like a shotgun;
##             missing = 1)
##   radius    projectile hit radius (world units; missing = 3)
##   burst     flak burst radius (area damage on proximity / end of life)
##             (world units: full damage within half of it, half damage at
##             the edge; see Combat.area())
##   torp_hp   torpedo hit points (PD/flak/bolts can shoot it down)
##   homing    torpedo turn rate toward its target (rad/s), 0 = straight
##             ("rad/s" = radians per second; a full turn is about 6.28)
##   energy    energy per shot (beams: per second while firing)
##             (taken from a pilot ship's battery; minions, turrets,
##             monsters and the mothership shoot for free)
##   turn      turret slew rate (rad/s) for turret/auto mounts
##             (how fast the gun swings round; missing = 3.0)
##   cuts      true = damages asteroids (capital-class guns only)
##   small_bonus  extra multiplier vs SMALL targets
##             (1.25 = +25% damage against size class 0; missing = 1.0)
##   beam      true for continuous beams: dps, range, on (s), off (s), width
##             dps   damage per second while it hits, before the damage
##                   table
##             range how long the beam is (world units)
##             on    how long one burst lasts (seconds); 0 = it fires for
##                   as long as the trigger is held
##             off   the rest between bursts (seconds)
##             width how thick the beam is drawn (world units; only looks)
##   prefer    for auto mounts: "torp_small" (PD), "small" (flak), "large"
##             (what an automatic gun shoots first: "torp_small" = enemy
##             torpedoes and small craft, "small" = small craft, "large" =
##             big targets; see WeaponMountTargeting)
##
## WHO USES IT: WeaponMount reads the firing fields (rate, dmg, speed,
## life, spread, pellets, energy, turn and the beam fields) when it aims
## and fires; Projectiles copies radius, burst, torp_hp, homing,
## small_bonus and cuts into each round it spawns;
## WeaponMountTargeting reads "prefer" and "speed" (to aim ahead of a
## moving target); Minion and Derelict read a few numbers too. Ships,
## Minions, TurretData, Jungle and Structures name the weapon ids.

## Every weapon: weapon id -> its facts (the fields are explained above).
const WEAPONS := {
	# --- pilot ships ---------------------------------------------------------------
	# scout_gun: Scout. fighter_cannon: Fighter. lance_beam: Lance Fighter.
	# torpedo: Bomber. light_turret: Logistics and Support Corvettes.
	# flak_battery: Flak Frigate. flak_auto: Destroyer and Battlecruiser.
	# pd_gun: Flak Frigate, Ion Frigate, Destroyer, Battlecruiser and the PD
	# Module. ion_cannon: Ion Frigate (it fires in bursts: 2 s on, 4 s off).
	# heavy_cannon: Destroyer and Battlecruiser. ion_turret: Battlecruiser.
	"scout_gun": {"label": "Pulse gun", "kind": "bolt", "rate": 4.0, "dmg": 4.0, "speed": 1150.0, "life": 0.6, "spread": 0.05, "radius": 2.6, "pellets": 1, "energy": 2.5},
	"fighter_cannon": {"label": "Twin autocannon", "kind": "bolt", "rate": 6.5, "dmg": 5.5, "speed": 1200.0, "life": 0.65, "spread": 0.035, "radius": 3.2, "pellets": 1, "energy": 2.0, "small_bonus": 1.25},
	"lance_beam": {"label": "Lance beam", "kind": "lance", "beam": true, "dps": 34.0, "range": 640.0, "on": 0.0, "off": 0.0, "width": 3.0, "energy": 14.0},
	"torpedo": {"label": "Fusion torpedo", "kind": "torp", "rate": 0.75, "dmg": 70.0, "speed": 520.0, "life": 2.3, "spread": 0.012, "radius": 7.0, "pellets": 1, "energy": 14.0, "torp_hp": 24.0, "homing": 0.0},
	"light_turret": {"label": "Light turret", "kind": "bolt", "rate": 3.0, "dmg": 7.0, "speed": 1050.0, "life": 0.7, "spread": 0.04, "radius": 3.0, "pellets": 1, "energy": 3.0, "turn": 3.0},
	"flak_battery": {"label": "Flak battery", "kind": "flak", "rate": 1.3, "dmg": 8.0, "speed": 900.0, "life": 0.8, "spread": 0.22, "radius": 3.4, "pellets": 6, "burst": 75.0, "energy": 6.0, "turn": 1.6},
	"flak_auto": {"label": "Flak mount", "kind": "flak", "rate": 0.9, "dmg": 7.0, "speed": 900.0, "life": 0.75, "spread": 0.22, "radius": 3.4, "pellets": 5, "burst": 70.0, "energy": 0.0, "turn": 2.0, "prefer": "small"},
	"pd_gun": {"label": "Point defense", "kind": "pd", "rate": 7.0, "dmg": 3.5, "speed": 1600.0, "life": 0.32, "spread": 0.05, "radius": 2.5, "pellets": 1, "energy": 0.0, "turn": 5.0, "prefer": "torp_small"},
	"ion_cannon": {"label": "Ion cannon", "kind": "ion", "beam": true, "dps": 95.0, "range": 1700.0, "on": 2.0, "off": 4.0, "width": 6.0, "energy": 15.0},
	"heavy_cannon": {"label": "Heavy cannon", "kind": "shell", "rate": 0.7, "dmg": 50.0, "speed": 820.0, "life": 1.65, "spread": 0.015, "radius": 6.0, "pellets": 1, "energy": 8.0, "turn": 0.9, "cuts": true},
	"ion_turret": {"label": "Ion turret", "kind": "ion", "beam": true, "dps": 80.0, "range": 1600.0, "on": 2.5, "off": 4.5, "width": 6.0, "energy": 12.0, "turn": 0.8, "cuts": true},

	# --- minions ------------------------------------------------------------------------
	# m_bolt: minion fighter. m_torp: minion bomber. m_cannon and m_pd: the
	# escort corvette.
	"m_bolt": {"label": "Minion gun", "kind": "bolt", "rate": 1.75, "dmg": 12.0, "speed": 1050.0, "life": 0.6, "spread": 0.1, "radius": 2.6, "pellets": 1, "energy": 0.0},
	"m_torp": {"label": "Minion torpedo", "kind": "torp", "rate": 0.4, "dmg": 28.0, "speed": 480.0, "life": 2.2, "spread": 0.02, "radius": 6.0, "pellets": 1, "energy": 0.0, "torp_hp": 12.0},
	"m_cannon": {"label": "Escort cannon", "kind": "bolt", "rate": 1.0, "dmg": 18.0, "speed": 1000.0, "life": 1.25, "spread": 0.03, "radius": 4.0, "pellets": 1, "energy": 0.0, "turn": 1.5},
	"m_pd": {"label": "Escort PD", "kind": "pd", "rate": 5.0, "dmg": 3.0, "speed": 1600.0, "life": 0.3, "spread": 0.06, "radius": 2.5, "pellets": 1, "energy": 0.0, "turn": 5.0, "prefer": "torp_small"},

	# --- turrets, bays, monsters ------------------------------------------------------------
	# turret_pd_gun: PD turret. turret_torp: torpedo turret (its torpedoes
	# home in at 0.6 rad/s). bay_pd: a repair bay with Bay Defenses.
	# monster_gun: the derelict monsters. snub_gun: snub fighters.
	"turret_pd_gun": {"label": "PD turret", "kind": "pd", "rate": 6.0, "dmg": 9.0, "speed": 1700.0, "life": 0.9, "spread": 0.03, "radius": 3.0, "pellets": 1, "energy": 0.0, "turn": 3.0, "prefer": "torp_small"},
	"turret_torp": {"label": "Torpedo turret", "kind": "torp", "rate": 0.45, "dmg": 110.0, "speed": 560.0, "life": 4.2, "spread": 0.0, "radius": 8.0, "pellets": 1, "energy": 0.0, "torp_hp": 40.0, "homing": 0.6, "turn": 2.0},
	"bay_pd": {"label": "Bay PD", "kind": "pd", "rate": 6.0, "dmg": 4.0, "speed": 1600.0, "life": 0.44, "spread": 0.05, "radius": 2.5, "pellets": 1, "energy": 0.0, "turn": 5.0, "prefer": "torp_small"},
	"monster_gun": {"label": "Derelict gun", "kind": "bolt", "rate": 1.2, "dmg": 6.0, "speed": 1000.0, "life": 0.9, "spread": 0.05, "radius": 3.5, "pellets": 1, "energy": 0.0, "turn": 2.0},
	"snub_gun": {"label": "Snub gun", "kind": "bolt", "rate": 2.5, "dmg": 4.0, "speed": 1050.0, "life": 0.6, "spread": 0.08, "radius": 2.6, "pellets": 1, "energy": 0.0},

	# --- mothership ---------------------------------------------------------------------------
	# ms_pd and ms_cannon: the mothership's starting guns. ms_heavy, ms_flak
	# and ms_ion (the Ion Lance) are added by Flagship research; PD Grid II
	# adds more ms_pd (the gun spots are in Structures.MOTHERSHIP).
	"ms_pd": {"label": "Mothership PD", "kind": "pd", "rate": 6.0, "dmg": 8.5, "speed": 1600.0, "life": 1.0, "spread": 0.04, "radius": 2.8, "pellets": 1, "energy": 0.0, "turn": 4.0, "prefer": "torp_small"},
	"ms_cannon": {"label": "Mothership cannon", "kind": "shell", "rate": 0.5, "dmg": 10.0, "speed": 900.0, "life": 2.2, "spread": 0.01, "radius": 5.0, "pellets": 1, "energy": 0.0, "turn": 1.0, "cuts": true, "prefer": "large"},
	"ms_heavy": {"label": "Heavy battery", "kind": "shell", "rate": 0.5, "dmg": 10.0, "speed": 900.0, "life": 2.5, "spread": 0.01, "radius": 7.0, "pellets": 1, "energy": 0.0, "turn": 0.8, "cuts": true, "prefer": "large"},
	"ms_flak": {"label": "Flak battery", "kind": "flak", "rate": 1.0, "dmg": 6.0, "speed": 900.0, "life": 1.5, "spread": 0.22, "radius": 3.4, "pellets": 6, "burst": 80.0, "energy": 0.0, "turn": 2.0, "prefer": "small"},
	"ms_ion": {"label": "Ion lance", "kind": "ion", "beam": true, "dps": 30.0, "range": 2600.0, "on": 3.0, "off": 5.0, "width": 10.0, "energy": 0.0, "turn": 0.5, "cuts": true, "prefer": "large"},
}


## The facts of weapon `id` (its entry in WEAPONS). WeaponMount and Minion
## use it.
static func get_def(id: String) -> Dictionary:
	return WEAPONS[id]


## The weapon kind of `def` as a number (Rules.W_BOLT, W_TORP, ...), looked
## up from its "kind" name. WeaponMount uses it.
static func kind_id(def: Dictionary) -> int:
	return int(Rules.KIND_IDS[def["kind"]])


## Effective reach of a weapon (projectiles: speed * life).
## In world units: a beam's "range", or how far a round flies before it
## disappears. (Range bonuses are applied later, by WeaponMount.)
static func reach(def: Dictionary) -> float:
	if def.get("beam", false):
		return float(def["range"])
	return float(def["speed"]) * float(def["life"])
