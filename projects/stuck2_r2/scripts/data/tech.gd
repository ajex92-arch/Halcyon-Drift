class_name Tech
extends RefCounted
## WHAT THIS IS: the tech tree, in the style of the game Homeworld 2: the
## list of everything a team's admiral can build onto the mothership or
## research, with what it costs, how long it takes, what it needs first and
## what it gives. DESIGN.md A13.
##
## HOW IT WORKS: there are two kinds of tech.
##   FACILITIES  modules built onto the mothership (one builds at a time, 2
##               may be queued). They unlock ships and open research
##               columns.
##   TECHS       research items (one researches at a time, 3 may be
##               queued). Each needs the Research Module plus the facility
##               of its column.
## Both are paid in full from the team treasury when they are queued, and
## the queues themselves are run by TeamTech (team_tech.gd). The research
## board shows TECHS in columns (COLUMNS), and the helper functions at the
## bottom answer "may we queue this?" and "may our pilots buy this hull?".
##
## A facility's fields:
##   label     its name for players
##   cost      its price [credits, from the team treasury]
##   time      how long it takes to build [seconds]
##   req_fac   facilities that must be built first (a list of ids)
##   req_tech  research that must be finished first (a list of ids)
##   blurb     what it does, in words for players; read it through
##             facility_blurb(), which fills in "{fleet_cap}" (the Fleet
##             Command limit of this match) and "{spool}" (the seconds a
##             hyperspace launch spools up in this match)
## A research item's fields:
##   label, cost [credits], time [seconds] and blurb, as above
##   column    the board column it sits in (one of COLUMNS)
##   req       research that must be finished OR already queued first, so
##             a whole chain can be queued in one go (a list of ids)
##   req_fac   (only a few items) extra facilities it needs
##   effect    what it gives once finished (see below)
##
## A tech's `effect` dictionary is applied by TeamState.apply_effect():
##   unlock_ship:id  drive:tier  armor:tier  torp_dmg  scout_emp  repair_bays
##   bay_drones  bay_defenses  drone_armor  mining_capacity  stipend
##   turret_torp  turret_armor  team_range  ward_upgrade
##   ms_hull  ms_shield  ms_pd  ms_flak  ms_heavy  ms_ion
##   minion_buff  wave_corvette
## Tiers: "small", "medium", "large", "capital".
## (The real code is TeamTech.apply_effect(). Bonuses add up when two
## research items give the same key.) What each key means:
##   unlock_ship      lets pilots buy that hull (ship_unlocked() below
##                    checks the finished research; no field is changed)
##   drive            +1 drive level for that tier: +8% top speed and +6%
##                    engine push per level (ShipStats)
##   armor            +1 armor level for that tier: +15% hull per level
##   torp_dmg         extra torpedo damage for pilot ships (0.25 = +25%)
##   scout_emp        the Scout's Ping also stalls enemy engines
##   repair_bays      the admiral may build repair bays
##   bay_drones       more repair drones in every repair bay (+1 each)
##   bay_defenses     repair bays get a shield and a point-defense gun
##   drone_armor      extra mining drone hull (0.4 = +40%)
##   mining_capacity  extra ore per mining drone trip (0.2 = +20%)
##   stipend          credits every pilot gets each time they respawn
##   turret_torp      torpedo turrets may be built
##   turret_armor     extra turret hull (0.25 = +25%)
##   team_range       extra weapon range for our ships, turrets and
##                    mothership (0.08 = +8%)
##   ward_upgrade     wards see 40% farther
##   ms_hull          extra mothership hull (0.15 = +15%; it also adds a
##                    fifth of that to its damage resistance, so +3%)
##   ms_shield        extra mothership shield and shield refill (0.25 = +25%)
##   ms_pd / ms_flak / ms_heavy / ms_ion   more mothership guns of that sort
##                    (the gun spots are listed in Structures.MOTHERSHIP)
##   minion_buff      extra minion hull, shield and damage (0.15 = +15%)
##   wave_corvette    one more Patrol Leader (minion type "corvette") per
##                    lane in every free minion wave (with
##                    --variant=escort_wing:upgrade the first Patrol Leader
##                    of each lane's wave is upgraded instead; see
##                    EscortWingFeature)
##
## A research item's description for players is read through blurb(), so
## a feature module may replace it for one match (as escort_wing does).
##
## WHO USES IT: TeamState and its part TeamTech (queues, blockers, effects,
## unlocks); AdmiralCommand queues things and the AI admiral (AdmiralPlan)
## plans them; the admiral board (AdmiralBoardResearch,
## AdmiralBoardMothership) draws the tree; ShipStats reads TIERS; the hangar
## and the HUD show unlock labels and names; some tests research everything.
##
## To add research: add an entry to TECHS and to the column's ORDER list.

## Every facility id, in the order the research board shows them.
const FACILITY_ORDER := ["fighter", "research", "corvette", "frigate", "capital", "platform", "sensors", "hyperspace", "fleet"]

## The facilities: facility id -> its facts (fields explained at the top).
## The Fighter Facility is free and owned from the start (START_FACILITIES).
const FACILITIES := {
	"fighter": {"label": "Fighter Facility", "cost": 0.0, "time": 0.0, "req_fac": [], "req_tech": [],
		"blurb": "Builds Scouts and Fighters; opens fighter research. Ready from the start."},
	"research": {"label": "Research Module", "cost": 600.0, "time": 40.0, "req_fac": [], "req_tech": [],
		"blurb": "Required for all research. Opens the General and Flagship columns."},
	"corvette": {"label": "Corvette Facility", "cost": 900.0, "time": 60.0, "req_fac": ["research"], "req_tech": ["corvetteChassis"],
		"blurb": "Builds Logistics Corvettes; opens corvette research."},
	"frigate": {"label": "Frigate Facility", "cost": 1400.0, "time": 75.0, "req_fac": ["research"], "req_tech": ["frigateChassis"],
		"blurb": "Builds Flak Frigates; opens frigate research."},
	"capital": {"label": "Capital Ship Facility", "cost": 2200.0, "time": 90.0, "req_fac": ["frigate"], "req_tech": [],
		"blurb": "Opens capital research (Destroyer, Battlecruiser)."},
	"platform": {"label": "Platform Control Module", "cost": 600.0, "time": 25.0, "req_fac": ["research"], "req_tech": [],
		"blurb": "Opens turret research: torpedo turrets and turret armor."},
	"sensors": {"label": "Advanced Sensors Array", "cost": 700.0, "time": 30.0, "req_fac": ["research"], "req_tech": [],
		"blurb": "+20% vision for every friendly unit; opens sensor research."},
	"hyperspace": {"label": "Hyperspace Module", "cost": 1200.0, "time": 40.0, "req_fac": ["research", "corvette"], "req_tech": [],
		"blurb": "Pilots can launch straight to any friendly repair bay ({spool}s spool-up)."},
	"fleet": {"label": "Fleet Command Module", "cost": 2000.0, "time": 60.0, "req_fac": ["capital"], "req_tech": [],
		"blurb": "Direct minion control. Free minion waves stop; buy up to {fleet_cap} minions and order them."},
}

## Research columns, in board order. "research" = General, "flagship" =
## mothership upgrades (needs the Research Module).
## Every other column needs the facility with the same id.
const COLUMNS := ["fighter", "research", "corvette", "frigate", "capital", "platform", "sensors", "flagship"]
## The heading shown above each column on the board: column id -> text.
const COLUMN_LABEL := {"fighter": "Fighter", "research": "General", "corvette": "Corvette", "frigate": "Frigate",
	"capital": "Capital", "platform": "Platform", "sensors": "Sensors", "flagship": "Flagship"}

## Every research item: tech id -> its facts (fields explained at the top).
## The ids are written in "camelCase" (words joined, each new word with a
## capital letter), and other files refer to them by these exact ids.
const TECHS := {
	# Fighter column.
	"fusionBombs": {"label": "Fusion Bombs", "column": "fighter", "req": [], "cost": 500.0, "time": 45.0, "effect": {"unlock_ship": "bomber"}, "blurb": "Unlocks the Bomber."},
	"lanceBeams": {"label": "Lance Beams", "column": "fighter", "req": [], "cost": 550.0, "time": 45.0, "effect": {"unlock_ship": "lance"}, "blurb": "Unlocks the Lance Fighter."},
	"scoutEmp": {"label": "Scout EMP", "column": "fighter", "req": [], "cost": 300.0, "time": 15.0, "effect": {"scout_emp": true}, "blurb": "Scout Ping also stalls enemy engines within 900 for 3s."},
	"improvedBombs": {"label": "Improved Bombs", "column": "fighter", "req": ["fusionBombs"], "cost": 500.0, "time": 25.0, "effect": {"torp_dmg": 0.25}, "blurb": "Bomber torpedoes deal +25% damage."},
	"fighterDrive1": {"label": "Fighter Drive 1", "column": "fighter", "req": [], "cost": 350.0, "time": 20.0, "effect": {"drive": "small"}, "blurb": "Strike craft: +8% top speed, +6% acceleration."},
	"fighterDrive2": {"label": "Fighter Drive 2", "column": "fighter", "req": ["fighterDrive1"], "cost": 600.0, "time": 30.0, "effect": {"drive": "small"}, "blurb": "Strike craft: another +8% top speed, +6% acceleration."},
	# General column (Research Module).
	"corvetteChassis": {"label": "Corvette Chassis", "column": "research", "req": [], "cost": 600.0, "time": 45.0, "effect": {}, "blurb": "Lets the mothership build the Corvette Facility."},
	"frigateChassis": {"label": "Frigate Chassis", "column": "research", "req": ["corvetteChassis"], "cost": 900.0, "time": 60.0, "effect": {}, "blurb": "Lets the mothership build the Frigate Facility."},
	"repairBays": {"label": "Repair Bays", "column": "research", "req": [], "cost": 300.0, "time": 15.0, "effect": {"repair_bays": true}, "blurb": "The admiral can launch repair bays that anchor anywhere."},
	"repairDrones2": {"label": "Repair Drones II", "column": "research", "req": ["repairBays"], "cost": 300.0, "time": 20.0, "effect": {"bay_drones": 1}, "blurb": "Repair bays carry 2 repair drones."},
	"repairDrones3": {"label": "Repair Drones III", "column": "research", "req": ["repairDrones2"], "cost": 450.0, "time": 25.0, "effect": {"bay_drones": 1}, "blurb": "Repair bays carry 3 repair drones."},
	"repairDrones4": {"label": "Repair Drones IV", "column": "research", "req": ["repairDrones3"], "cost": 600.0, "time": 30.0, "effect": {"bay_drones": 1}, "blurb": "Repair bays carry 4 repair drones."},
	"bayDefenses": {"label": "Bay Defenses", "column": "research", "req": ["repairBays"], "cost": 550.0, "time": 30.0, "effect": {"bay_defenses": true}, "blurb": "Repair bays get a shield and a point-defense gun. They keep repairing while only the shield is hit."},
	"droneArmor1": {"label": "Drone Armor 1", "column": "research", "req": [], "cost": 350.0, "time": 18.0, "effect": {"drone_armor": 0.4}, "blurb": "Mining drones: +40% hull."},
	"droneArmor2": {"label": "Drone Armor 2", "column": "research", "req": ["droneArmor1"], "cost": 550.0, "time": 26.0, "effect": {"drone_armor": 0.4}, "blurb": "Mining drones: another +40% hull."},
	"improvedMining": {"label": "Improved Mining", "column": "research", "req": [], "cost": 400.0, "time": 20.0, "effect": {"mining_capacity": 0.2}, "blurb": "Mining drones carry 20% more ore per trip."},
	"pilotStipend": {"label": "Pilot Stipend", "column": "research", "req": [], "cost": 500.0, "time": 25.0, "effect": {"stipend": 250.0}, "blurb": "Every pilot gets 250 credits each time they respawn."},
	# Corvette column.
	"commandSystems": {"label": "Command Systems", "column": "corvette", "req": [], "cost": 600.0, "time": 45.0, "effect": {"unlock_ship": "support"}, "blurb": "Unlocks the Support Corvette."},
	"corvetteDrive1": {"label": "Corvette Drive 1", "column": "corvette", "req": [], "cost": 350.0, "time": 20.0, "effect": {"drive": "medium"}, "blurb": "Corvettes: +8% top speed, +6% acceleration."},
	"corvetteDrive2": {"label": "Corvette Drive 2", "column": "corvette", "req": ["corvetteDrive1"], "cost": 550.0, "time": 28.0, "effect": {"drive": "medium"}, "blurb": "Corvettes: another +8% top speed, +6% acceleration."},
	"corvetteArmor1": {"label": "Corvette Armor 1", "column": "corvette", "req": [], "cost": 400.0, "time": 22.0, "effect": {"armor": "medium"}, "blurb": "Corvettes: +15% hull."},
	"corvetteArmor2": {"label": "Corvette Armor 2", "column": "corvette", "req": ["corvetteArmor1"], "cost": 600.0, "time": 30.0, "effect": {"armor": "medium"}, "blurb": "Corvettes: another +15% hull."},
	# Frigate column.
	"ionCannons": {"label": "Ion Cannons", "column": "frigate", "req": [], "cost": 900.0, "time": 60.0, "effect": {"unlock_ship": "ion"}, "blurb": "Unlocks the Ion Frigate."},
	"frigateDrive1": {"label": "Frigate Drive 1", "column": "frigate", "req": [], "cost": 400.0, "time": 22.0, "effect": {"drive": "large"}, "blurb": "Frigates: +8% top speed, +6% acceleration."},
	"frigateDrive2": {"label": "Frigate Drive 2", "column": "frigate", "req": ["frigateDrive1"], "cost": 650.0, "time": 30.0, "effect": {"drive": "large"}, "blurb": "Frigates: another +8% top speed, +6% acceleration."},
	"frigateArmor1": {"label": "Frigate Armor 1", "column": "frigate", "req": [], "cost": 450.0, "time": 24.0, "effect": {"armor": "large"}, "blurb": "Frigates: +15% hull."},
	"frigateArmor2": {"label": "Frigate Armor 2", "column": "frigate", "req": ["frigateArmor1"], "cost": 700.0, "time": 32.0, "effect": {"armor": "large"}, "blurb": "Frigates: another +15% hull."},
	# Capital column.
	"destroyerChassis": {"label": "Destroyer Chassis", "column": "capital", "req": [], "cost": 1500.0, "time": 90.0, "effect": {"unlock_ship": "destroyer"}, "blurb": "Unlocks the Destroyer."},
	"battlecruiserChassis": {"label": "Battlecruiser Chassis", "column": "capital", "req": ["destroyerChassis"], "cost": 2400.0, "time": 120.0, "effect": {"unlock_ship": "battlecruiser"}, "blurb": "Unlocks the Battlecruiser."},
	"capitalDrive1": {"label": "Capital Drive 1", "column": "capital", "req": [], "cost": 500.0, "time": 26.0, "effect": {"drive": "capital"}, "blurb": "Capital ships: +8% top speed, +6% acceleration."},
	"capitalDrive2": {"label": "Capital Drive 2", "column": "capital", "req": ["capitalDrive1"], "cost": 800.0, "time": 34.0, "effect": {"drive": "capital"}, "blurb": "Capital ships: another +8% top speed, +6% acceleration."},
	"capitalArmor1": {"label": "Capital Armor 1", "column": "capital", "req": [], "cost": 550.0, "time": 28.0, "effect": {"armor": "capital"}, "blurb": "Capital ships: +15% hull."},
	"capitalArmor2": {"label": "Capital Armor 2", "column": "capital", "req": ["capitalArmor1"], "cost": 850.0, "time": 36.0, "effect": {"armor": "capital"}, "blurb": "Capital ships: another +15% hull."},
	# Platform column.
	"platformMissiles": {"label": "Platform Missiles", "column": "platform", "req": [], "cost": 600.0, "time": 30.0, "effect": {"turret_torp": true}, "blurb": "Torpedo turrets can be built at nodes near our mothership."},
	"platformArmor1": {"label": "Platform Armor 1", "column": "platform", "req": [], "cost": 450.0, "time": 25.0, "effect": {"turret_armor": 0.25}, "blurb": "Turrets: +25% hull."},
	"platformArmor2": {"label": "Platform Armor 2", "column": "platform", "req": ["platformArmor1"], "cost": 700.0, "time": 35.0, "effect": {"turret_armor": 0.25}, "blurb": "Turrets: another +25% hull."},
	# Sensors column.
	"fireControl": {"label": "Fire Control", "column": "sensors", "req": [], "cost": 600.0, "time": 30.0, "effect": {"team_range": 0.08}, "blurb": "+8% weapon range for every friendly ship and turret."},
	"wardUpgrades": {"label": "Sensor Probes", "column": "sensors", "req": [], "cost": 400.0, "time": 20.0, "effect": {"ward_upgrade": true}, "blurb": "Wards see 40% farther."},
	# Flagship column (mothership upgrades).
	"msHull1": {"label": "Hull Reinforcement I", "column": "flagship", "req": [], "cost": 800.0, "time": 30.0, "effect": {"ms_hull": 0.15}, "blurb": "Mothership: +15% hull, +3% damage resistance."},
	"msHull2": {"label": "Hull Reinforcement II", "column": "flagship", "req": ["msHull1"], "cost": 1200.0, "time": 40.0, "effect": {"ms_hull": 0.15}, "blurb": "Mothership: another +15% hull and +3% resistance."},
	"msHull3": {"label": "Hull Reinforcement III", "column": "flagship", "req": ["msHull2"], "cost": 1600.0, "time": 50.0, "effect": {"ms_hull": 0.15}, "blurb": "Mothership: another +15% hull and +3% resistance."},
	"msShield1": {"label": "Shield Generator I", "column": "flagship", "req": [], "cost": 900.0, "time": 35.0, "effect": {"ms_shield": 0.25}, "blurb": "Mothership: +25% shields and shield regeneration."},
	"msShield2": {"label": "Shield Generator II", "column": "flagship", "req": ["msShield1"], "cost": 1400.0, "time": 45.0, "effect": {"ms_shield": 0.25}, "blurb": "Mothership: another +25% shields and regeneration."},
	"msPd2": {"label": "PD Grid II", "column": "flagship", "req": [], "cost": 700.0, "time": 30.0, "effect": {"ms_pd": 4}, "blurb": "Mothership: 4 more point-defense guns."},
	"msFlak": {"label": "Flak Batteries", "column": "flagship", "req": [], "cost": 1000.0, "time": 40.0, "effect": {"ms_flak": 4}, "blurb": "Mothership: 4 flak batteries against strike craft."},
	"msHeavy1": {"label": "Heavy Batteries I", "column": "flagship", "req": [], "cost": 1200.0, "time": 45.0, "effect": {"ms_heavy": 2}, "blurb": "Mothership: 2 heavy cannon turrets against frigates and capitals."},
	"msHeavy2": {"label": "Heavy Batteries II", "column": "flagship", "req": ["msHeavy1"], "cost": 1800.0, "time": 55.0, "effect": {"ms_heavy": 2}, "blurb": "Mothership: 2 more heavy cannon turrets."},
	"msIon": {"label": "Ion Lance", "column": "flagship", "req": ["msHeavy1"], "req_fac": ["capital"], "cost": 2500.0, "time": 70.0, "effect": {"ms_ion": 1}, "blurb": "Mothership: a huge ion beam that carves through capital ships."},
	# Launch bays: late-game ways to spend team money that make our minion
	# waves stronger. (Playtest: late in the game, treasuries piled up to
	# 19,000 credits with nothing left to buy, and no base was ever
	# destroyed.)
	"waveArmor1": {"label": "Reinforced Waves I", "column": "flagship", "req": [], "cost": 1000.0, "time": 40.0, "effect": {"minion_buff": 0.15}, "blurb": "Our minions: +15% hull and damage."},
	"waveArmor2": {"label": "Reinforced Waves II", "column": "flagship", "req": ["waveArmor1"], "cost": 1500.0, "time": 50.0, "effect": {"minion_buff": 0.15}, "blurb": "Our minions: another +15% hull and damage."},
	"waveArmor3": {"label": "Reinforced Waves III", "column": "flagship", "req": ["waveArmor2"], "req_fac": ["capital"], "cost": 2000.0, "time": 60.0, "effect": {"minion_buff": 0.15}, "blurb": "Our minions: another +15% hull and damage."},
	"escortWing": {"label": "Escort Wing", "column": "flagship", "req": ["waveArmor1"], "req_fac": ["frigate"], "cost": 2500.0, "time": 60.0, "effect": {"wave_corvette": 1}, "blurb": "Every free minion wave launches one more Patrol Leader per lane."},
}

## Board order inside each column (dependencies read top-down).
## Every research id, in the order the board lists them (the board then
## sorts them into their columns), so an item sits below what it needs.
const ORDER := [
	"fusionBombs", "improvedBombs", "lanceBeams", "scoutEmp", "fighterDrive1", "fighterDrive2",
	"corvetteChassis", "frigateChassis", "repairBays", "repairDrones2", "repairDrones3", "repairDrones4", "bayDefenses",
	"droneArmor1", "droneArmor2", "improvedMining", "pilotStipend",
	"commandSystems", "corvetteDrive1", "corvetteDrive2", "corvetteArmor1", "corvetteArmor2",
	"ionCannons", "frigateDrive1", "frigateDrive2", "frigateArmor1", "frigateArmor2",
	"destroyerChassis", "battlecruiserChassis", "capitalDrive1", "capitalDrive2", "capitalArmor1", "capitalArmor2",
	"platformMissiles", "platformArmor1", "platformArmor2",
	"fireControl", "wardUpgrades",
	"msHull1", "msHull2", "msHull3", "msShield1", "msShield2", "msPd2", "msFlak", "msHeavy1", "msHeavy2", "msIon",
	"waveArmor1", "waveArmor2", "waveArmor3", "escortWing",
]

## The facilities every team owns from the start (TeamState sets them up).
const START_FACILITIES := ["fighter"]
## The four ship tiers, by size class (small, medium, large, capital). The
## "drive" and "armor" effects name a tier; ShipStats reads
## TIERS[size class] to find a ship's tier.
const TIERS := ["small", "medium", "large", "capital"]


## The facility a column needs ("flagship" lives on the Research Module).
## Every other column needs the facility with the column's own id.
static func column_facility(column: String) -> String:
	return "research" if column == "flagship" else column


## The description of research `id` for players: its "blurb", unless a
## feature module replaced it for this match by setting the tuned text
## "tech_blurb:<id>" (Rules.tune; escort_wing "upgrade" does this). The
## admiral board's research cards show it.
static func blurb(id: String) -> String:
	return str(Rules.tune("tech_blurb:" + id, TECHS[id]["blurb"]))


## The description of mothership module (facility) `id` for players: its
## "blurb", with "{fleet_cap}" replaced by the most bought minions a team may
## have alive in this match (Minions.control_cap(): 30 in the old rules, 60 in
## the standard rules through the fleet_cap variant) and "{spool}" by the seconds a
## hyperspace launch spools up (World.HYPERSPACE_SPOOL, 6, unless the redeploy
## variant tuned "hyperspace_spool" to 4), so the Fleet Command and Hyperspace
## Module cards never show a stale number. The admiral board's module cards
## show it.
static func facility_blurb(id: String) -> String:
	var spool := int(Rules.tune("hyperspace_spool", World.HYPERSPACE_SPOOL))
	return String(FACILITIES[id]["blurb"]).format({"fleet_cap": Minions.control_cap(), "spool": spool})


## Why a research item can't be queued, or "" if it can. `planned` = done +
## queued research (so chains can be stacked).
## `facilities` holds the facilities we own (id -> true). The checks, in
## order: the Research Module, the column's facility, any extra facilities
## (req_fac), then every earlier research (req). Cost and queue room are
## checked elsewhere (TeamTech.tech_blocker()).
static func tech_blocker(id: String, facilities: Dictionary, planned: Dictionary) -> String:
	# Step 1: all research needs the Research Module.
	var t: Dictionary = TECHS[id]
	if not facilities.has("research"):
		return "Needs the Research Module"
	# Step 2: the facility of the item's column.
	var fac := column_facility(t["column"])
	if not facilities.has(fac):
		return "Needs the %s" % FACILITIES[fac]["label"]
	# Step 3: any extra facilities this item asks for.
	for f: String in t.get("req_fac", []):
		if not facilities.has(f):
			return "Needs the %s" % FACILITIES[f]["label"]
	# Step 4: earlier research, finished or at least queued.
	for r: String in t["req"]:
		if not planned.has(r):
			return "Needs %s" % TECHS[r]["label"]
	return ""


## Why a facility can't be queued, or "" if it can.
## `facilities` holds the facilities we own and `done` the research we have
## finished (both id -> true). Cost and queue room are checked elsewhere
## (TeamTech.facility_blocker()).
static func facility_blocker(id: String, facilities: Dictionary, done: Dictionary) -> String:
	# Step 1: facilities it needs.
	var f: Dictionary = FACILITIES[id]
	for r: String in f["req_fac"]:
		if not facilities.has(r):
			return "Needs the %s" % FACILITIES[r]["label"]
	# Step 2: research it needs (finished, not just queued).
	for r: String in f["req_tech"]:
		if not done.has(r):
			return "Needs %s research" % TECHS[r]["label"]
	return ""


## Is this hull buyable given facilities and research done?
## Hulls with unlock "" are always open; "fac:<id>" hulls need that
## facility; research-unlocked hulls need the research AND the facility for
## the hull's size (Fighter, Corvette, Frigate or Capital Ship Facility).
static func ship_unlocked(ship_id: String, facilities: Dictionary, done: Dictionary) -> bool:
	# Step 1: open from the start, or opened by a facility.
	var u: String = Ships.HULLS[ship_id]["unlock"]
	if u == "":
		return true
	if u.begins_with("fac:"):
		return facilities.has(u.substr(4))
	# Research unlocks also need the hull's facility to exist.
	var size := Ships.size_of(ship_id)
	var fac: String = ["fighter", "corvette", "frigate", "capital"][size]
	return done.has(u) and facilities.has(fac)


## What unlocks a hull, as a player-facing phrase ("" when it starts open).
## For example "the Corvette Facility" or "Fusion Bombs research". The
## hangar (HangarShips) and PilotProfileShop show it.
static func ship_unlock_label(ship_id: String) -> String:
	var u: String = Ships.HULLS[ship_id]["unlock"]
	if u == "":
		return ""
	if u.begins_with("fac:"):
		return "the %s" % FACILITIES[u.substr(4)]["label"]
	return "%s research" % TECHS[u]["label"]
