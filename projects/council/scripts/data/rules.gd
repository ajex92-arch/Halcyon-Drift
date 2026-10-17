class_name Rules
extends RefCounted
## WHAT THIS IS: the game's rule book, written as numbers. It holds the
## numbers that many different parts of the game share: the teams, how big
## things are ("size classes"), the damage table (which weapon hurts what,
## and how much), the shield and battery settings a pilot can pick, money,
## respawn times, the admiral's rally point, vision, and a few "variant"
## switches for testing. Designers tune most other numbers in the other
## files of scripts/data/; this file keeps the ones that cross many systems.
##
## HOW IT WORKS: it is only a list of constants (fixed values that never
## change while the game runs) plus a few small helper functions. Nothing
## here does anything by itself: other files read these values. Everything
## is "static", so you write Rules.SOMETHING without making a Rules object.
## Feature modules (scripts/features/, see FeatureRegistry) may change
## some of the game's numbers for one match: those numbers are read through
## tune(), and TUNABLES (at the bottom) lists every one of them. With no
## feature on, tune() simply gives back the normal number.
## Units used below:
##   seconds; world units (1 world unit is about one pixel at normal zoom);
##   credits (the game's money); multipliers (x1.0 = normal, x0.5 = half,
##   x2.0 = double); fractions (0..1, so 0.25 means 25%).
## "Size class" lists with four entries are read in the order small,
## medium, large, capital (see size_index()).
##
## WHO USES IT: almost every file. The biggest readers: CombatScaling (the
## damage table and the special damage rules), Economy (the money numbers),
## Ship, ShipStats, ShipFlight, ShieldZones and EnergyPool (size classes,
## shields, energy routing, crashes), TeamState and its parts (treasury,
## respawn strain, waypoint), MatchRules (respawn times), Vision and
## WorldVisibility (vision), Game (the variant switches, DESIGN.md A2) and
## FeatureRegistry (the variant switches and TUNABLES). Many files call
## tune(); TUNABLES names them.
##
## To add a weapon kind: add a W_* id, a row to DAMAGE, and handle it in
## WeaponMount / Projectiles if it needs new behaviour.

# --- teams -------------------------------------------------------------------
# Every unit belongs to a team, stored as a number.

## Team number 0: Halcyon, the amber team. Its mothership starts on the left
## (west) side of the map. A human player always plays for Halcyon.
const HALCYON := 0
## Team number 1: Cinder, the red team. Its mothership starts on the right
## (east) side of the map.
const CINDER := 1
## Team number 2: neutral. The derelict monsters of the jungle and their
## snub fighters belong to no side.
const NEUTRAL := 2
## Team names for messages and screens, by team number (team 2 is shown as
## "Derelict").
const TEAM_NAMES := ["Halcyon", "Cinder", "Derelict"]

## The enemy team of `team`: 0 gives 1, and 1 gives 0. The neutral team (2)
## has no enemy team, so it gives -1, which means "none".
static func enemy_of(team: int) -> int:
	return 1 - team if team < 2 else -1


# --- size / target classes (columns of the damage table) ----------------------
# Every unit has a "size class": a number for roughly how big it is. It
# picks the damage-table column when the unit is hit, and many lists below
# are read by size class.

## Size class 0: small things. Strike craft (Scout, Fighter, Lance Fighter,
## Bomber), minion fighters and bombers, drones, wards and snub fighters.
const SIZE_SMALL := 0
## Size class 1: medium. Corvettes (Logistics, Support, the escort corvette
## minion) and the derelict monsters.
const SIZE_MEDIUM := 1
## Size class 2: large. Frigates (Flak Frigate, Ion Frigate).
const SIZE_LARGE := 2
## Size class 3: capital ships (Destroyer, Battlecruiser).
const SIZE_CAPITAL := 3
## Size class 4: structures (turrets and repair bays).
const SIZE_STRUCTURE := 4
## Size class 5: the motherships.
const SIZE_MOTHERSHIP := 5
## Size class 6: torpedoes. No unit has this size. It is only used as a
## damage-table column, for shooting down torpedoes.
const SIZE_TORPEDO := 6
# --- weapon kinds (rows of the damage table) -----------------------------------
# Every weapon has a "kind" (the "kind" field in weapons.gd). It picks the
# damage-table row, and some kinds behave in their own way: flak bursts,
# torpedoes can be shot down, and bolt, flak and PD rounds can shoot them.

## Kind 0: "bolt", ordinary gun rounds (fighter guns, light turrets, minion
## guns, monster guns).
const W_BOLT := 0
## Kind 1: "lance", the Lance Fighter's beam.
const W_LANCE := 1
## Kind 2: "torp", torpedoes: slow, hard-hitting, and they can be shot down.
const W_TORP := 2
## Kind 3: "flak", rounds that burst and hurt everything in a small circle.
const W_FLAK := 3
## Kind 4: "pd", point defense: fast, weak rounds made to shoot down
## torpedoes and small craft.
const W_PD := 4
## Kind 5: "shell", heavy cannon shells (Destroyer, Battlecruiser and the
## mothership's cannons).
const W_SHELL := 5
## Kind 6: "ion", ion beams (Ion Frigate, the Battlecruiser's ion turrets,
## the mothership's Ion Lance).
const W_ION := 6
## Kind 7: "collision", the damage a ship takes when it crashes into
## something too fast (ShipFlight).
const W_COLLISION := 7
## Kind 8: "pure", damage that is x1.0 against everything. Meant for
## scripted specials; at the moment only the support_probe test uses it.
const W_PURE := 8
## The kind names written in weapons.gd ("bolt", "torp", ...) turned into
## the numbers above. Weapons.kind_id() looks them up here.
const KIND_IDS := {"bolt": W_BOLT, "lance": W_LANCE, "torp": W_TORP, "flak": W_FLAK, "pd": W_PD,
	"shell": W_SHELL, "ion": W_ION, "collision": W_COLLISION, "pure": W_PURE}

## THE DAMAGE TABLE: DAMAGE[kind][target class]. DESIGN.md A5.
## How to read it: take the ROW of the weapon kind that hits (bolt, lance,
## torp, ... in the W_* order above) and the COLUMN of the size class of
## what gets hit (small, medium, large, capital, structure, mothership,
## torpedo, in the SIZE_* order above). The number where they meet is a
## multiplier on the weapon's raw damage:
##   1.0 = normal damage, 0.5 = half, 2.0 = double, 0.0 = no damage at all.
## Example: a torpedo (row "torp") hitting a capital ship (column
## "capital") does x1.8, but against a small fighter only x0.35. So every
## weapon has jobs it is good at and jobs it is bad at.
## The last column ("torp") is used when a round hits an enemy torpedo.
## Only bolt, flak and PD rounds can hit torpedoes at all (Projectiles);
## the column says how much of their damage the torpedo takes.
## CombatScaling.final_amount() applies this table first, before the
## special rules below. Rules.damage_mult() reads one cell.
const DAMAGE := [
	#  small medium large capital struct  mship  torp
	[1.0, 0.85, 0.6, 0.45, 0.5, 0.4, 0.6],   # bolt
	[0.8, 1.4, 0.9, 0.7, 0.6, 0.5, 0.0],     # lance
	[0.35, 1.0, 1.6, 1.8, 2.2, 2.0, 0.0],    # torp
	[1.4, 0.9, 0.25, 0.2, 0.3, 0.3, 1.5],    # flak
	[1.0, 0.5, 0.1, 0.05, 0.2, 0.1, 1.0],    # pd
	[0.5, 1.0, 1.3, 1.4, 1.8, 1.5, 0.0],     # shell
	[0.4, 0.9, 1.5, 1.6, 1.6, 1.5, 0.0],     # ion
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0],     # collision
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],     # pure (specials, scripted)
]

## Damage to asteroids by weapon kind, as a multiplier. Only weapons marked
## "cuts" in weapons.gd (capital-class shells and ion beams) can hurt rocks
## at all; kinds missing here count as 0. DESIGN.md A5.
## Note: only cutting BEAMS read this table (CombatBeamArea.beam(): an ion
## beam does x0.6 to a rock). A cutting shell is a round, and a round that
## hits a rock deals its full raw damage to it (ProjectilesImpact.hit()),
## so the shell entry here is not read at the moment.
const ASTEROID_MULT := {W_SHELL: 1.0, W_ION: 0.6}

## The mothership is "weak to large ships": damage to a mothership is also
## multiplied by this, picked by the ATTACKER's size class (small, medium,
## large, capital, structure, mothership, torpedo). Strike craft do x0.3,
## corvettes x0.8, frigates and capital ships x2.0, anything else x1.0.
## (Minions use MOTHERSHIP_MINION_MULT instead; see CombatScaling.)
const MOTHERSHIP_ATTACKER := [0.3, 0.8, 2.0, 2.0, 1.0, 1.0, 1.0]
## Damage from minions (the small computer-flown lane ships) to a
## mothership is x0.5: half.
const MOTHERSHIP_MINION_MULT := 0.5
## Minions chip turrets slowly: their damage to turrets is x0.35.
const TURRET_MINION_MULT := 0.35
## Minions are low-skill bots: their damage to pilot ships is x0.6, less
## than a pilot does, so pilots die mostly to other pilots. (Playtest:
## minions used to be the top killer of pilots.)
const MINION_VS_SHIP_MULT := 0.6
## Minion-against-minion damage is x1.8, so two waves that meet finish
## their fight fast (about 20 s), before the next wave arrives. (Playtest:
## at x1 these fights took about 40 s and waves piled up in the middle.)
const MINION_VS_MINION_MULT := 1.8

# --- shields -------------------------------------------------------------------
# A pilot ship's shield is split into four "zones", one for each side. A
# hit drains only the zone on the side it came from (ShieldZones).

## Zone 0: the front (the nose).
const ZONE_FRONT := 0
## Zone 1: the rear (the tail).
const ZONE_REAR := 1
## Zone 2: the left side.
const ZONE_LEFT := 2
## Zone 3: the right side.
const ZONE_RIGHT := 3
# "Shield focus" is a setting the pilot picks: it moves more of the shield
# to one side of the ship.

## Focus 0: Balanced, every zone gets the same share.
const FOCUS_BALANCED := 0
## Focus 1: most of the shield on the front.
const FOCUS_FRONT := 1
## Focus 2: most of the shield on the rear.
const FOCUS_REAR := 2
## Focus 3: most of the shield on the left side.
const FOCUS_LEFT := 3
## Focus 4: most of the shield on the right side.
const FOCUS_RIGHT := 4
## The focus names shown on screen, by focus number.
const FOCUS_NAMES := ["Balanced", "Front", "Rear", "Left", "Right"]
## FOCUS_WEIGHTS[focus] = [front, rear, left, right]
## How each focus setting shares out the shield: each number is the
## fraction (0..1) of the ship's total shield that the zone may hold, and
## every row adds up to 1.0. Example: Front focus gives the front zone 50%,
## the rear 10% and each side 20% (ShieldZones).
const FOCUS_WEIGHTS := [
	[0.25, 0.25, 0.25, 0.25],
	[0.50, 0.10, 0.20, 0.20],
	[0.10, 0.50, 0.20, 0.20],
	[0.20, 0.20, 0.50, 0.10],
	[0.20, 0.20, 0.10, 0.50],
]
## Seconds, indexed by size class (small, medium, large, capital).
## After the pilot changes shield focus, they must wait this long before
## they can change it again (Ship). Big ships are slower. "Redirect" gear
## shortens it.
const FOCUS_COOLDOWN := [1.0, 2.0, 3.5, 5.0]
## How long (seconds) a pilot ship's shield waits after its last hit before
## it starts to refill, by size class (small, medium, large, capital). Stim
## Implant gear shortens the wait.
const SHIELD_DELAY := [3.5, 5.0, 6.0, 8.0]

# --- energy routing --------------------------------------------------------------
# "Energy routing" is a setting the pilot picks: where the ship's spare
# power goes. Each setting makes some things better and others worse
# (EnergyPool stores it; ShipStats and Ship use it).

## Routing 0: Balanced, everything normal.
const ENERGY_BALANCED := 0
## Routing 1: Weapons. Guns fire faster; shields refill slower; the ship is
## a little slower.
const ENERGY_WEAPONS := 1
## Routing 2: Shields. Shields refill twice as fast and block more; guns
## fire slower; the ship is a little slower.
const ENERGY_SHIELDS := 2
## Routing 3: Thrusters. Faster, nimbler and cheaper boosting; guns fire
## slower and shields refill slower.
const ENERGY_THRUSTERS := 3
## The routing names shown on screen, by routing number.
const ENERGY_NAMES := ["Balanced", "Weapons", "Shields", "Thrusters"]
## What each routing setting does. One entry per routing number, holding
## these values (1.0 = normal):
##   fire        rate of fire multiplier (1.25 = 25% faster)
##   regen       shield refill speed multiplier
##   sresist     EXTRA shield resistance, a 0..1 fraction that is ADDED to
##               the shield's own resistance on every hit (0.15 = the
##               shield blocks 15% more of each hit)
##   thrust      engine push and top speed multiplier
##   turn        turning speed multiplier
##   boost_cost  boost energy cost multiplier (0.6 = 40% cheaper)
## EnergyPool.m() reads one of these values.
const ENERGY_MODES := [
	{"fire": 1.0, "regen": 1.0, "sresist": 0.0, "thrust": 1.0, "turn": 1.0, "boost_cost": 1.0},
	{"fire": 1.25, "regen": 0.6, "sresist": 0.0, "thrust": 0.92, "turn": 0.96, "boost_cost": 1.0},
	{"fire": 0.85, "regen": 2.0, "sresist": 0.15, "thrust": 0.92, "turn": 0.96, "boost_cost": 1.0},
	{"fire": 0.85, "regen": 0.6, "sresist": 0.0, "thrust": 1.12, "turn": 1.08, "boost_cost": 0.6},
]
## After the pilot changes energy routing, they must wait this long
## (seconds) before they can change it again, by size class (small,
## medium, large, capital). "Redirect" gear shortens it (Ship).
const ENERGY_COOLDOWN := [1.5, 3.0, 5.0, 7.0]

# --- flight / collisions ----------------------------------------------------------
# ShipFlight uses these when a pilot ship bumps into something solid.

## Impacts slower than this do no damage; above it, damage scales gently.
## The speed is in world units per second.
const COLLISION_SAFE_SPEED := 220.0
## Crash damage for each world unit per second of speed above the safe
## speed: damage = (impact speed - 220) x 0.07, then times the size
## multiplier below (and lowered by crash gear such as the Crash Couch).
const COLLISION_DAMAGE_PER_SPEED := 0.07
## Bigger hulls hit harder (and have more hull to lose).
## Crash damage multiplier by size class (small, medium, large, capital).
const COLLISION_SIZE_MULT := [1.0, 2.5, 6.0, 12.0]
## Fraction of impact speed returned as a bounce (0.35 = 35%).
const COLLISION_BOUNCE := 0.35

# --- economy (DESIGN.md A7) -------------------------------------------------------
# There are two kinds of money, both counted in credits: each pilot's own
# credits (to buy ships and gear) and each team's shared treasury (for the
# admiral). Economy (economy.gd) pays most of these out. A feature module
# may change most of them for one match (see TUNABLES at the bottom).

## Credits every pilot has at the start of the match (PilotProfile).
const START_CREDITS := 700.0
## Credits in each team's treasury at the start of the match (TeamState).
const START_TREASURY := 1500.0
## Credits per second that every pilot always earns, even while dead or
## docked.
const PASSIVE_INCOME := 1.5
## The share of delivered ore that goes to the team treasury (0.6 = 60%;
## 1 ore is worth 1 credit). The other 40% is split evenly among the
## team's pilots who are not dead.
const ORE_TREASURY_SHARE := 0.6
## Extra pay for pilots who escorted a mining drone home: 0.2 = 20% of the
## ore it delivers, split among its escorts.
const ESCORT_BONUS := 0.2
## How close (world units) a friendly pilot ship must fly to a mining drone
## to count as one of its escorts (MiningDrone).
const ESCORT_RANGE := 1100.0
## Credits per second that each mothership always adds to its team's
## treasury (TeamState).
const MOTHERSHIP_SKIM := 3.0
## The base bounty (credits) for destroying an enemy pilot's ship.
const KILL_BASE := 100.0
## The bounty also includes this share of what the destroyed ship was worth
## (its hull and module prices): 0.12 = 12%.
const KILL_VALUE_SHARE := 0.12
## Helpers ("assists") share this part of the bounty, paid on top of the
## killer's bounty: 0.5 = half. When no pilot made the killing blow (a
## turret, minion or monster did), the helpers share the whole bounty.
const ASSIST_SHARE := 0.5
## To count as a helper on a ship or monster kill, a pilot must have done
## at least this share of the recent damage (0.1 = 10%).
const ASSIST_MIN_FRACTION := 0.1
## "Recent" damage for ship kills and turret kills means hits in the last
## this many seconds. (Monster kills use 30 seconds.)
const ASSIST_WINDOW := 15.0
## Extra bounty (credits) for ending a kill streak: this much for every
## kill in the victim's streak after the first.
const SHUTDOWN_PER_STREAK := 50.0
## Credits shared by the enemy pilots who hit a turret in the last
## ASSIST_WINDOW seconds, when it is destroyed.
const TURRET_BOUNTY := 350.0
## Credits added to the destroying team's treasury for a turret.
const TURRET_TREASURY := 400.0
## Credits for the pilot who makes the killing blow on a repair bay.
const BAY_BOUNTY := 200.0
## Credits added to the other team's treasury for a repair bay.
const BAY_TREASURY := 250.0
## Credits for the enemy pilot who makes the killing blow on a mining drone.
const MINING_DRONE_BOUNTY := 35.0
## Credits for the pilot who makes the killing blow on a ward.
const WARD_BOUNTY := 30.0
## Credits for the enemy pilot who makes the killing blow on a repair drone
## (gear does not raise this one).
const REPAIR_DRONE_BOUNTY := 10.0
## Minion last-hit pay grows this much per 5 minutes.
## (0.05 = +5% of the minion's bounty for every full 5 minutes of match
## time.)
const MINION_BOUNTY_GROWTH := 0.05
## Selling gear or repair kits gives back this share of the price (0.5 =
## half).
const SELL_BACK := 0.5
## When you buy a different hull while docked, the old one trades in at this.
## (A share of its price: 0.5 = half.)
const HULL_TRADE_IN := 0.5
## Selling a module, or trading in a hull that has modules on it, gives back
## this share of each module's price (0.4 = 40%).
const MODULE_TRADE_IN := 0.4

# --- ace streaks -------------------------------------------------------------------
# A pilot who keeps scoring kills without dying becomes an "ace" for a
# while: a little faster and harder-hitting (Economy starts it, ShipStats
# applies it).

## Kills in a row (without dying in between) needed to become an ace.
const ACE_KILLS := 3
## How long (seconds) the ace bonus lasts. Every further kill starts it
## again.
const ACE_TIME := 25.0
## The ace's damage multiplier (1.12 = +12% damage).
const ACE_DAMAGE := 1.12
## The ace's top-speed multiplier (1.08 = +8% top speed).
const ACE_SPEED := 1.08

# --- respawn and strain --------------------------------------------------------------

## The respawn wait (seconds) at the very start of the match (MatchRules).
const RESPAWN_BASE := 6.0
## The extra respawn wait, in seconds, for every minute of match time. Late
## deaths cost real time, so winning a fight opens a window to attack.
## (Playtest: at 0.3 s per minute with a 20 s cap, the defenders were back
## before any attack arrived.)
const RESPAWN_PER_MINUTE := 0.9
## The respawn wait never grows past this (seconds). Gear such as the
## Ejection Seat then shortens it.
const RESPAWN_MAX := 50.0
## Respawn strain (TeamStrain): when many pilots of a team respawn in a
## short time, their mothership is overworked for a while. This is that
## time window, in seconds.
const STRAIN_WINDOW := 30.0
## This many respawns inside STRAIN_WINDOW start the strain.
const STRAIN_RESPAWNS := 4
## How long (seconds) the strain lasts.
const STRAIN_TIME := 20.0
## While strained, the mothership's guns fire at this speed (0.6 = 60%),
## and its shield does not refill (Mothership).
const STRAIN_WEAPON_MULT := 0.6

# --- waypoint (admiral) ---------------------------------------------------------------
# The admiral can place a rally marker called the "waypoint". Friendly
# pilot ships inside its circle get small bonuses (ShipStats), and AI
# pilots gather there.

## The radius (world units) of the waypoint circle.
const WAYPOINT_RADIUS := 1200.0
## How long (seconds) a waypoint lasts once placed.
const WAYPOINT_TIME := 75.0
## Top-speed multiplier inside the circle (1.08 = +8%).
const WAYPOINT_SPEED := 1.08
## Shield refill multiplier inside the circle (1.25 = +25%).
const WAYPOINT_SHIELD_REGEN := 1.25
## Vision multiplier inside the circle (1.15 = +15%).
const WAYPOINT_VISION := 1.15

# --- vision ---------------------------------------------------------------------------
# "Fog of war": each team only sees what its own units can see (Vision,
# WorldVisibility).

## To work out what each team can see, the map is cut into square cells
## this many world units wide.
const VISION_CELL := 200.0
## Units this close to any friendly unit are always visible.
## (In world units. Wards have their own, smaller distance: Structures.WARD
## "stealth_radius".)
const VISION_TOUCH := 350.0
## How many times per second each team's vision is worked out again.
const VISION_HZ := 5.0

# --- match ------------------------------------------------------------------------------

## Pilots on each team (WorldSetup makes this many for each side).
const PILOTS_PER_TEAM := 12
## Match time (seconds) from which a mothership may move: 1200 s = 20:00.
## Read it through move_unlock_time(), which lets a feature tune it.
const MOTHERSHIP_MOVE_UNLOCK := 1200.0

# --- variants (DESIGN.md A2: unclear conflicts are tested) ----------------------------
# Where the design left a choice open, the game can run either way. Each
# "variant" switch picks one of the options. The "C.." codes point at the
# matching entries in DESIGN.md.

## The default variant switches: switch name -> chosen option. Game copies
## them when it starts and answers Game.variant("name") from its copy. The
## command line can change them (for the game and the tests), for example
## --variant=retreat:none. (The options that lost their tests, C11 "jump",
## C12 "nodes_7", C13 "split" and C19 "siege" / "home", were taken out
## of the code; DESIGN.md keeps the results.) A switch that has a feature
## module (scripts/features/) installs it whenever its value is not the
## default here (FeatureRegistry); every default keeps today's game.
const VARIANT_DEFAULTS := {
	## C11: what a mothership does the first time its hull drops to 35%
	## (see MothershipRetreat): "systems_failure" | "none" | "last_stand"
	## (LastStandFeature: shields refill and guns fire x1.5 for 45 s, then the
	## ship is "breached" and takes x1.25 damage for the rest of the match)
	"retreat": "systems_failure",
	## What the Escort Wing research does (docs/FUN_PLAN.md section 5;
	## EscortWingFeature): "extra" (today's game: one more escort corvette
	## per lane in every free wave, 11 minions) | "upgrade" (each wave keeps
	## its 10 minions; its single corvette gets +40% hull and +15% weapon
	## range instead)
	"escort_wing": "extra",
	## endgame_closure fork (docs/FUN_PLAN.md section 5; every key is "off" by
	## default, so a match is today's game). Each value is listed in the
	## header of its feature module in scripts/features/.
	## Sieges that land (SiegeFixFeature): "off" | "gather3" | "full" | "stall"
	"siege_fix": "off",
	## Lane breach corvette (BreachFeature): "off" | "on" | "fulldmg"
	"breach": "off",
	## Mothership damage-rate cap (MsCapFeature): "off" | "on" | "full"
	"ms_cap": "off",
	## Fleet attrition after 40:00 (AttritionFeature): "off" | "on"
	"attrition": "off",
	## Surrender vote (SurrenderFeature): "off" | "vote"
	"surrender": "off",
	## Extra super minion in a breached lane's waves (BreachExtraFeature):
	## "off" | "on"
	"breach_extra": "off",
	## Softer mothership (MsSoftFeature): "off" | "hull" | "shield" | "mult"
	"ms_soft": "off",
	## Fewer free minion waves late (WavesLateFeature): "off" | "slow" | "none"
	"waves_late": "off",
	## Late minions launch from the lane ends (LanespawnFeature): "off" | "on"
	"lanespawn": "off",
	## Weapon-aware target choice (EffFeature): "off" | "on"
	"eff": "off",
	## Mothership siege rule (MsNosmallFeature): "off" | "nosmall" (small
	## non-bomber ships stop sieging the mothership)
	"ms": "off",
	## combat_roles fork (docs/FORK_MANIFEST.md). Every key below defaults to
	## "off", today's game.
	## E1, MinionCapFeature: "on" = a minion's hit on a pilot ship counts as
	## at most +15% strong (Reinforced Waves ignored for that hit)
	"minion_cap": "off",
	## E2, EscortPdFeature: "on" = big ships' anti-strike-craft guns fire at
	## x(0.6 + 0.2 x support), shields x0.7 when alone; ESCORTED / ISOLATED
	"escort_pd": "off",
	## E3, LanceRoleFeature: "on" = Lance beam x1.35 on a big ship's rear
	## shield zone; Lance pilots hunt isolated big ships
	"lance_role": "off",
	## E4, RoutingPayoffFeature: "on" = holding Weapons / Shields / Thrusters
	## long enough charges a one-shot bonus
	"routing_payoff": "off",
	## E5, JungleBigFeature, REQ-CHANGE ("a jungle ... only small ships can
	## travel through"): "medium" = MEDIUM ships may use the jungle, "all" =
	## LARGE and CAPITAL too (wider gates and paths)
	"jungle_big": "off",
	## E6, ZoomMaxFeature, REQ-CHANGE (zoom lock close to the ship): "wide" =
	## the human camera may zoom out 1.5x further, "xwide" = 2x
	"zoom_max": "off",
	## Carry-overs, BomberRoleFeature: "seats" = seats 6 and 10 fly Fighters,
	## "torp" = pilot torpedoes x0.6 (not x0.35) to small craft, "both"
	"bomber_role": "off",
	## A1 Lane Slipstream (SlipstreamFeature, docs: FORK_MANIFEST.md): "off"
	## (today's game) | "on" (pilots behind their own team's front run up to
	## twice as fast on the lane, at most 1,000 u/s) | "flat" (every hull
	## runs at 1,100 u/s; REQ-CHANGE: heavier ships travel slower) | "probe"
	## (nobody slips; only the arrival times of big ships are measured)
	"slipstream": "off",
	## A2 Forward Redeploy (RedeployFeature): "off" | "on" (hyperspace comes
	## right after the Frigate Facility in the admiral's plan, jumps may land
	## at a bay or a turret, 4 s spool, AI pilots jump to the front)
	"redeploy": "off",
	## A3 Recall (RecallFeature): "off" | "on" (key T: a 8-12 s channel that
	## docks the ship from anywhere; AI pilots recall when far from home)
	"recall": "off",
	## A4 Size-scaled respawn (SizeRespawnFeature): "off" | "size" (the wait
	## is x0.6 / 0.85 / 1.1 / 1.3 for a small / medium / large / capital hull)
	"respawn": "off",
	## A5 Respawn at a forward site (RespawnSiteFeature): "off" | "bay" (the
	## new ship appears at a safe forward repair bay) | "waypoint" (at the
	## admiral's waypoint ring); REQ-CHANGE: kits are bought at the mothership
	"respawn_site": "off",
	## A6 Kits and gear sold at repair bays (BayShopFeature): "off" | "on";
	## REQ-CHANGE: kits are bought at the mothership
	"bay_shop": "off",
	## A7 Steeper late respawn curve (SteepRespawnFeature): "off" | "steep"
	## (6 s + 0.9 s per minute, at most 50 s  ->  8 s + 1.8 s per minute, at
	## most 90 s); DESIGN: the research rejected it
	"respawn_curve": "off",
	## Deep-dive option bayA (BayBackFeature): "off" | "on" (the AI admiral
	## places its repair bays 0.22 of the way down the lane, not 0.33)
	"bayA": "off",
	## Economy and comeback ideas (fork economy_comebacks; every one is off by
	## default and has its own feature module in scripts/features/).
	## C1 income from play (EconPlayFeature): "off" | "play" (slower passive
	## income, more pay for kills, turrets and minions, a bonus for pilots
	## near a destroyed turret)
	"econ": "off",
	## C2 accrued pilot bounties and comeback structure bounties
	## (ComebackBountiesFeature): "off" | "on" | "equal" (the same, but the
	## structure payout is split equally among all 12 pilots)
	"bounties": "off",
	## C3 Mk II gear tier (GearMk2Feature): "off" | "on"
	"gear_mk2": "off",
	## C4 buyback: pay to respawn at once (BuybackFeature): "off" | "on"
	"buyback": "off",
	## C5 Fleet Doctrine, a repeatable admiral research (DoctrineFeature):
	## "off" | "on"
	"doctrine": "off",
	## C6 catch-up income or shared team income (CatchupFeature): "off" |
	## "income" | "share"
	"catchup": "off",
	## C7 pilots mining (PilotMiningFeature): "off" | "hold" | "extractor"
	"pilot_mining": "off",
	## C8 the mothership weakens after big treasury spends
	## (MsSpendWeakFeature): "off" | "on"
	"ms_spend_weak": "off",
	## C9 push/morale meter that strengthens new minion waves
	## (MoraleFeature): "off" | "on"
	"morale": "off",
	## Fork teamfights_jungle (docs/FUN_PLAN.md section 5, fork D). Every key
	## defaults to "off" (today's game); "on" switches the idea on.
	## D1, GroupLateFeature: after 25:00 the third laners and the flex pilot
	## group on the push lane; junglers join sieges and defence. "off" | "on"
	"group_late": "off",
	## D2, SalvageCoreFeature: the carrier camp nearest the connector in each
	## quarter becomes a Derelict Battleship; its last-hitter carries a
	## Salvage Core that strengthens friendly minions. "off" | "on"
	"salvage_core": "off",
	## D3, JungleScaleFeature: camp rewards and derelict strength grow with
	## match time; AI junglers gank hurt pilots after 20:00. "off" | "on"
	"jungle_scale": "off",
	## D4, NodePersistFeature (owns the turret rebuild-lock lever): rebuild
	## lock 60 -> 150 s, rebuilt turrets start at 50% hull and repair 1% per
	## second. "off" | "on"
	"node_persist": "off",
	## D5, EpicNeutralFeature (REQ-CHANGE: no timed events): a timed Derelict
	## Dreadnought at the Crossing. "off" | "dreadnought" (a team boon) |
	## "elder" (as dreadnought, but the first kill after 30:00 grants the
	## Elder Core instead)
	"epic": "off",
	## D6, BeaconsFeature (REQ-CHANGE: no timed events / capture points):
	## two salvage beacons with a sensor-blackout reward. "off" | "on"
	"beacons": "off",
	## D7, Camp4Feature + MapBuilderJungle (DESIGN, map-generation change):
	## a fourth derelict camp per quarter. "off" | "on"
	"camp4": "off",
	## D8, FeatsFeature (DESIGN): early feats of strength and the 14:00
	## Vanguard reward. "off" | "on"
	"feats": "off",
	## Admiral command assets (fork admiral_command, F1, AdmiralAssetsFeature):
	## "off" | "on" (Sensor Sweep + Supply Drop) | "full" (also Mothership
	## Barrage) | "xray" (like "on", but the Sweep sees through asteroids:
	## REQ-CHANGE "players cannot see through asteroids")
	"assets": "off",
	## Bounty orders (F2, AdmiralOrdersFeature): "off" | "on" (the admiral pays
	## a bounty on an enemy turret or repair bay)
	"orders": "off",
	## Fortify (F3, FortifyFeature): "off" | "on" (a free admiral button that
	## makes our turrets and mothership take x0.2 damage for 4 s)
	"fortify": "off",
	## Reactive AI admiral and fleet-composition calls (F4, AdmiralSmartFeature):
	## "off" | "on" (AI-only: the build plan reacts to the enemy fleet and
	## the pilots' shopping lists follow a composition call)
	"admiral_smart": "off",
	## Mothership move rules (F5, MsMoveFeature): "off" | "early" (engines online
	## at 12:00 instead of 20:00) | "flying" (an admiral who flies their own
	## ship may order the move; REQ-CHANGE "moved by a docked admiral")
	"ms_move": "off",
	## Defenders' home-field vision (F6, HomeVisionFeature, DESIGN): "off" | "on"
	"home_vision": "off",
	## Mutiny / admiral swap (F7, MutinyFeature, REQ-CHANGE "locked into not
	## being the admiral"): "off" | "on"
	"mutiny": "off",
	## Extra treasury sinks for the AI admiral (deep-dive carry-over,
	## AdmiralSinksFeature): "off" | "fleet" (build Fleet Command, refresh wards)
	"admiral_sinks": "off",
}


## Turn any size class into a list position 0..3 (small, medium, large,
## capital), for the lists that have only four entries. Structures,
## motherships and torpedoes (4..6) count as capital (3).
static func size_index(size_class: int) -> int:
	return clampi(size_class, 0, 3)


## One cell of the damage table: the multiplier for weapon kind `kind` (a
## W_* number) hitting something of size class `target_class` (a SIZE_*
## number). CombatScaling and Projectiles call it.
static func damage_mult(kind: int, target_class: int) -> float:
	return float(DAMAGE[kind][target_class])


# --- tuned numbers that feature modules may change ---------------------------------------
# A feature module (scripts/features/, see FeatureRegistry) changes a number
# for its match by setting Game.tunables["name"] = value in its install().
# The code that uses the number asks tune("name", normal value). With no
# feature on, Game.tunables is empty and every number keeps its normal
# value, so the game plays exactly as before.

## Every tuned number a feature may change, by name: name -> what it is,
## its normal value and who reads it. FeatureRegistry warns about a name in
## Game.tunables that is not listed here (usually a typo). One more kind of
## entry is text, not a number: "tech_blurb:<research id>" replaces that
## research's description on the admiral board (Tech.blurb()).
const TUNABLES := {
	# Economy: pay for pilots (Economy) and the treasury (Economy, TeamState).
	"passive_income": "credits per second every pilot always earns (PASSIVE_INCOME, 1.5; Economy.passive_income)",
	"mothership_skim": "credits per second a living mothership adds to its treasury (MOTHERSHIP_SKIM, 3; TeamState.tick)",
	"ore_treasury_share": "share of delivered ore that goes to the treasury; living pilots split the rest (ORE_TREASURY_SHARE, 0.6; Economy.deliver_ore)",
	"escort_bonus": "extra share of delivered ore that a drone's escorts split (ESCORT_BONUS, 0.2; Economy.deliver_ore)",
	"kill_base": "base bounty in credits for destroying a pilot ship (KILL_BASE, 100; Economy)",
	"kill_value_share": "share of the destroyed ship's value added to its bounty (KILL_VALUE_SHARE, 0.12; Economy)",
	"shutdown_per_streak": "extra bounty in credits per kill of the victim's streak after the first (SHUTDOWN_PER_STREAK, 50; Economy)",
	"assist_share": "share of a ship bounty that the helpers split on top of the killer's pay (ASSIST_SHARE, 0.5; Economy)",
	"assist_min_fraction": "share of the recent damage a helper must have done, for ship and derelict kills (ASSIST_MIN_FRACTION, 0.1; Economy)",
	"assist_window": "seconds of recent damage that count for ship and turret kills (ASSIST_WINDOW, 15; Economy)",
	"minion_bounty_growth": "growth of the minion bounty per full 5 minutes of match time (MINION_BOUNTY_GROWTH, 0.05; Economy)",
	"turret_bounty": "credits that the attacking pilots split for a destroyed turret (TURRET_BOUNTY, 350; Economy)",
	"turret_treasury": "credits to the attacking team's treasury for a destroyed turret (TURRET_TREASURY, 400; Economy)",
	"bay_bounty": "credits to the pilot who destroys a repair bay (BAY_BOUNTY, 200; Economy)",
	"bay_treasury": "credits to the other team's treasury for a destroyed repair bay (BAY_TREASURY, 250; Economy)",
	"mining_drone_bounty": "credits to the enemy pilot who destroys a mining drone (MINING_DRONE_BOUNTY, 35; Economy)",
	"ward_bounty": "credits to the pilot who destroys a ward (WARD_BOUNTY, 30; Economy)",
	"repair_drone_bounty": "credits to the enemy pilot who destroys a repair drone (REPAIR_DRONE_BOUNTY, 10; Economy)",
	"derelict_reward_mult": "multiplier on every derelict camp's reward (1.0; Economy)",
	"derelict_assist_window": "seconds of recent damage that count for a derelict kill (30; Economy)",
	"derelict_last_hit_bonus": "extra share of a derelict's reward for the pilot who made the last hit (Jungle.LAST_HIT_BONUS, 0.25; Economy)",
	"insurance_base": "share of a destroyed ship's value paid back to its pilot, on top of insurance gear (0.0; Economy)",
	# Respawn wait (MatchRules.respawn_time).
	"respawn_base": "respawn wait in seconds at the start of the match (RESPAWN_BASE, 6; MatchRules)",
	"respawn_per_minute": "extra respawn wait in seconds per minute of match time (RESPAWN_PER_MINUTE, 0.9; MatchRules)",
	"respawn_max": "the longest respawn wait in seconds, before gear (RESPAWN_MAX, 50; MatchRules)",
	# Turrets.
	"rebuild_lock": "seconds an ore node stays locked for building after a turret there is destroyed (TurretData.REBUILD_LOCK, 60; Turret.on_killed)",
	# The AI admiral's sieges (AdmiralSiege) and their meeting points (TeamSiege).
	"siege_start": "match time in seconds before which the AI declares no siege (AdmiralSiege.START_TIME, 1200)",
	"siege_min_healthy": "big ships over half hull the AI needs to declare a siege (AdmiralSiege.MIN_HEALTHY, 2)",
	"siege_power_edge": "our fleet strength must be at least this many times theirs to declare a siege (AdmiralSiege.POWER_EDGE, 1.2)",
	"siege_ms_hurt": "...unless the enemy mothership's hull fraction is at or below this (AdmiralSiege.MS_HURT, 0.6)",
	"siege_gather_count": "big ships massed at the staging point that start the assault (AdmiralSiege.GATHER_COUNT, 2)",
	"siege_gather_time": "seconds of gathering after which whoever is there attacks (AdmiralSiege.GATHER_TIME, 45)",
	"siege_gather_radius": "world units from the staging point that count as massed (AdmiralSiege.GATHER_RADIUS, 3000)",
	"siege_contact_dist": "world units from the enemy mothership's hull that count as contact (AdmiralSiege.CONTACT_DIST, 3000)",
	"siege_stall_time": "seconds after contact at which the stall check is made (AdmiralSiege.STALL_TIME, 120)",
	"siege_stall_frac": "hull fraction the enemy mothership must have lost by then, or the assault is called off (AdmiralSiege.STALL_FRAC, 0.15)",
	"siege_no_contact_time": "seconds of assault without contact after which it is called off (AdmiralSiege.NO_CONTACT_TIME, 300)",
	"siege_cooldown": "seconds after a call-off before the AI may declare another siege (AdmiralSiege.COOLDOWN, 60)",
	"siege_follow_dist": "world units the enemy mothership may be off the siege lane before the siege follows it (AdmiralSiege.FOLLOW_DIST, 4000)",
	"siege_stage_frac": "how far along the lane the staging point is, as a fraction (TeamSiege.SIEGE_STAGE, 0.6)",
	"siege_stage_gap": "world units the staging point stays short of the enemy mothership at least (TeamSiege.SIEGE_STAGE_GAP, 7000)",
	"siege_assault_gap": "world units the assault point is short of the enemy mothership (TeamSiege.ASSAULT_GAP, 4500)",
	# Defending the base (TeamDefense).
	"defend_radius": "world units from our mothership's hull at which enemy big ships set off the defend call (TeamDefense.DEFEND_RADIUS, 7000; at most TeamDefense.FORWARD_DEFEND_RADIUS, 4000, while the mothership is parked away from home)",
	# Moving the mothership.
	"mothership_move_unlock": "match time in seconds from which motherships may move (MOTHERSHIP_MOVE_UNLOCK, 1200; move_unlock_time())",
	"mothership_move_gap": "seconds between the AI admiral's advance moves of the mothership (AdmiralMothershipMover.MOVE_GAP, 120)",
	"mothership_advance_frac": "how far up the mid lane the AI moves the mothership, as a fraction (AdmiralMothershipMover.ADVANCE_FRAC, 0.35)",
	"mothership_move_needs_dock": "true = an admiral must be docked (not flying a ship) to order a mothership move (AdmiralCommand.move_blocker; default true)",
	# Minion waves (MinionDirector).
	"wave_interval": "seconds between free minion waves (Minions.WAVE_INTERVAL, 35; MinionDirector)",
	# Damage to a mothership from large and capital pilot ships (CombatScaling).
	"mothership_attacker_large": "damage multiplier against a mothership for hits from large and capital pilot ships (MOTHERSHIP_ATTACKER, 2.0; CombatScaling)",
	# Pilot torpedoes (BomberRoleFeature, the bomber_role variant).
	"torp_small_mult": "damage multiplier of a PILOT's torpedo against small craft (the torp row of DAMAGE, 0.35; BomberRoleFeature)",
}


## Feature hook: the value of tuned number `name` for this match. Returns
## Game.tunables[name] when a feature module set it, otherwise
## `default_value`: the normal number, which the caller passes in, as in
## Rules.tune("kill_base", Rules.KILL_BASE). With no feature on, the list
## is empty and the normal number comes straight back. Callers wrap it in
## float() or int(). Read a number once before a loop rather than for every
## unit inside it. TUNABLES lists every name.
static func tune(name: String, default_value: Variant) -> Variant:
	var t: Dictionary = Game.tunables
	if t.is_empty():
		return default_value
	return t.get(name, default_value)


## Match time (seconds) from which the motherships may move:
## MOTHERSHIP_MOVE_UNLOCK (1200 s = 20:00), unless a feature tuned
## "mothership_move_unlock". AdmiralCommand, MothershipDrive and AdmiralAI
## ask this, so they always agree.
static func move_unlock_time() -> float:
	return float(tune("mothership_move_unlock", MOTHERSHIP_MOVE_UNLOCK))
