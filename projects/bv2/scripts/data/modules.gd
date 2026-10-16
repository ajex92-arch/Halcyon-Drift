class_name Modules
extends RefCounted
## WHAT THIS IS: the shop list of ship modules: add-on parts that make one
## ship better (more hull, faster engines, stronger guns, ...). Ship
## modules: up to 2 per ship, bought with the ship, lost when the ship
## dies, swappable while docked or inside a friendly repair bay's radius.
##
## HOW IT WORKS: MODULES is a dictionary (a lookup table): module id -> its
## facts. Stats use the same keys as pilot gear (items.gd) and are summed by
## StatBlock. Price scales with hull size (PRICE_MUL by size class).
## Unlike gear, a module belongs to the ship, not the pilot.
##
## Each module's fields:
##   label         its name for players
##   price         the base price [credits]; the real price is
##                 price_for(): base x PRICE_MUL for the hull's size
##   blurb         what it does, in words for players
##   stats         stat name -> amount (the keys are explained in items.gd)
## Extra fields some modules have:
##   grants_boost  marks the Boost Cell, which gives boost to hulls without
##                 a booster. (ShipStats checks for the id "boost_cell"
##                 itself; no script reads this flag at the moment.)
##   adds_mount    the weapon id of an extra automatic gun it bolts on
##                 (Ship and WorldHangar add the gun)
##   min_size      the smallest size class it fits (1 = corvettes and up)
##
## WHO USES IT: Ship (fitted modules, extra guns), ShipStats (the stats),
## WorldHangar (swapping modules in space), the hangar screens
## (HangarModules, HangarShips, HangarLaunch), PilotProfile and
## PilotProfileShop (buying and refunds) and the AI pilots
## (PilotShopping).

## Every module id, in the order the hangar lists them.
const ORDER := ["plating", "engines", "weapons", "shield_booster", "capacitor", "boost_cell", "pd_module", "sensor_suite"]
## The price multiplier by the hull's size class (small, medium, large,
## capital): a module costs 1.6x on a corvette and 4x on a capital ship.
const PRICE_MUL := [1.0, 1.6, 2.5, 4.0]
## The most modules one ship can carry.
const MAX_PER_SHIP := 2

## Every module: module id -> its facts (the fields are explained above).
const MODULES := {
	"plating": {"label": "Plating", "price": 120.0, "blurb": "+25% hull, -8% acceleration.", "stats": {"hull_pct": 0.25, "accel_pct": -0.08}},
	"engines": {"label": "Engines", "price": 130.0, "blurb": "+10% top speed, +8% acceleration.", "stats": {"speed_pct": 0.10, "accel_pct": 0.08}},
	"weapons": {"label": "Weapons", "price": 150.0, "blurb": "+18% weapon damage.", "stats": {"damage_pct": 0.18}},
	"shield_booster": {"label": "Shield Booster", "price": 140.0, "blurb": "+25% shields, +15% shield regeneration.", "stats": {"shield_pct": 0.25, "shield_regen_pct": 0.15}},
	"capacitor": {"label": "Capacitor", "price": 110.0, "blurb": "+40% energy pool, +20% energy recharge.", "stats": {"energy_pct": 0.40, "energy_regen_pct": 0.20}},
	"boost_cell": {"label": "Boost Cell", "price": 110.0, "blurb": "Adds boost (Shift) to ships without it; ships that have it boost harder and longer.", "stats": {"boost_pct": 0.25}, "grants_boost": true},
	"pd_module": {"label": "PD Module", "price": 200.0, "blurb": "Adds an automatic point-defense gun. Corvettes and larger only.", "stats": {}, "adds_mount": "pd_gun", "min_size": 1},
	"sensor_suite": {"label": "Sensor Suite", "price": 100.0, "blurb": "+25% vision range.", "stats": {"vision_pct": 0.25}},
}


## What module `id` costs on hull `hull_id`, in credits: the base price
## times PRICE_MUL for the hull's size, rounded down to a whole number.
## For example Plating on a Destroyer: 120 x 4.0 = 480.
static func price_for(id: String, hull_id: String) -> float:
	var size := Ships.size_of(hull_id)
	return floorf(float(MODULES[id]["price"]) * float(PRICE_MUL[size]))


## "" when the module fits this hull, else the reason.
## (The only rule today: the hull must be at least the module's min_size.)
static func fit_blocker(id: String, hull_id: String) -> String:
	var def: Dictionary = MODULES[id]
	if Ships.size_of(hull_id) < int(def.get("min_size", 0)):
		return "Corvettes and larger only"
	return ""
