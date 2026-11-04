class_name Items
extends RefCounted
## WHAT THIS IS: the shop list of pilot gear (flight suits, helmets, sticks
## and so on) plus the repair kit. Pilot gear: bought at the mothership with
## personal credits, kept through death, 6 inventory slots shared with
## repair-kit stacks. At most one item per category. DESIGN.md A6.
##
## HOW IT WORKS: ITEMS is a dictionary (a lookup table): item id -> its
## facts. Each item gives "stats": small bonuses with names such as
## "hull_pct". Gear is the pilot's own, not the ship's, so it stays with
## them when their ship is destroyed. The bonuses of all the pilot's gear
## (and of the ship's modules, see modules.gd) are added up in a StatBlock,
## and whoever needs a bonus reads the total.
##
## Each item's fields:
##   label     its name for players
##   category  one of CATEGORIES (a pilot may own one item per category)
##   price     what it costs [credits]
##   stats     stat name -> amount (the keys below)
##   blurb     what it does, in words for players
##
## Stat keys (summed across gear and modules by StatBlock):
##   hull_pct hull_resist shield_pct shield_resist shield_regen_pct
##   shield_delay (seconds, negative = faster) energy_pct energy_regen_pct
##   fire_rate_pct damage_pct turn_pct accel_pct speed_pct strafe_pct
##   boost_pct vision_pct income (cr/s) redirect_cd_pct special_cd_pct
##   collision_resist repair_recv_pct respawn_pct bounty_pct insurance
## What they mean ("_pct" keys are fractions: 0.10 = +10%, -0.30 = 30%
## less):
##   hull_pct, shield_pct, energy_pct  bigger hull, shield or battery
##   hull_resist, shield_resist  the share of each hit that is blocked,
##       added to the hull's own (a ship's total is capped at 0.75)
##   shield_regen_pct, energy_regen_pct  faster shield or battery refill
##   shield_delay  seconds added to the shield's wait after a hit
##       (negative = the shield starts refilling sooner)
##   fire_rate_pct, damage_pct  faster guns, harder hits
##   turn_pct, accel_pct, speed_pct, strafe_pct  turning, engine push, top
##       speed, sideways push
##   boost_pct  stronger and cheaper boosting (0.25 = +12.5% boost push for
##       a built-in booster, and 20% less boost energy; see ShipStats)
##   vision_pct  see farther
##   income  extra credits per second, on top of the passive income
##   redirect_cd_pct  shorter wait after changing shield focus or energy
##       routing (never below 20% of the normal wait)
##   special_cd_pct  shorter special-ability cooldown (never below 30%)
##   collision_resist  the share of crash damage blocked (0.5 = half;
##       capped at 0.9)
##   repair_recv_pct  more healing from repair drones
##   respawn_pct  shorter respawn wait (never below 30% of normal)
##   bounty_pct  more pay from kills, minions, monsters and other rewards
##   insurance  the share of your ship's value paid back when it is
##       destroyed
##
## WHO USES IT: PilotProfile (the inventory slots and gear_stats(), the
## gear's summed bonuses) and PilotProfileShop (buying and selling);
## Economy, MatchRules and ShipStats read those summed bonuses; the hangar
## screens (HangarGear, HangarKits) and the HUD's slot bar (HudSlots) show
## the items; AI pilots buy them (PilotShopping).
##
## To add an item: add an entry with a category from CATEGORIES.

## How many inventory slots a pilot has. Gear and repair-kit stacks share
## them.
const SLOTS := 6
## The gear categories, in the order the hangar shows them. A pilot may own
## at most one item of each.
const CATEGORIES := ["suit", "helmet", "stick", "cockpit", "chair", "implant"]
## The category names players see: category id -> name.
const CATEGORY_LABEL := {"suit": "Flight Suit", "helmet": "Helmet", "stick": "Stick", "cockpit": "Cockpit Layout", "chair": "Chair", "implant": "Implant"}

## Every gear item: item id -> its facts (the fields are explained above).
const ITEMS := {
	# Flight suits: survival.
	"suit_pressure": {"label": "Pressure Suit", "category": "suit", "price": 350.0, "stats": {"hull_pct": 0.10}, "blurb": "+10% hull."},
	"suit_armored": {"label": "Armored Flight Suit", "category": "suit", "price": 900.0, "stats": {"hull_resist": 0.08, "hull_pct": 0.05}, "blurb": "Hull takes 8% less damage; +5% hull."},
	"suit_reactive": {"label": "Reactive Weave", "category": "suit", "price": 1000.0, "stats": {"shield_resist": 0.10, "shield_regen_pct": 0.15}, "blurb": "Shields take 10% less damage; +15% shield regeneration."},
	"suit_courier": {"label": "Courier Suit", "category": "suit", "price": 600.0, "stats": {"income": 0.6, "speed_pct": 0.03}, "blurb": "+0.6 credits/s income; +3% top speed."},
	# Helmets: awareness and targeting.
	"helm_visor": {"label": "HUD Visor", "category": "helmet", "price": 400.0, "stats": {"vision_pct": 0.15}, "blurb": "+15% vision range."},
	"helm_target": {"label": "Targeting Helmet", "category": "helmet", "price": 950.0, "stats": {"fire_rate_pct": 0.08, "damage_pct": 0.03}, "blurb": "+8% fire rate, +3% damage."},
	"helm_neural": {"label": "Neural-Link Helmet", "category": "helmet", "price": 1100.0, "stats": {"redirect_cd_pct": -0.30, "special_cd_pct": -0.15}, "blurb": "Shield focus and energy routing recover 30% faster; ability cooldown -15%."},
	"helm_salvager": {"label": "Salvager's Helm", "category": "helmet", "price": 650.0, "stats": {"income": 0.4, "bounty_pct": 0.15}, "blurb": "+0.4 credits/s; +15% from kills, minions and monsters."},
	# Sticks: handling.
	"stick_precision": {"label": "Precision Stick", "category": "stick", "price": 450.0, "stats": {"turn_pct": 0.10}, "blurb": "+10% turn rate."},
	"stick_hotas": {"label": "Twin-Grip HOTAS", "category": "stick", "price": 900.0, "stats": {"turn_pct": 0.07, "strafe_pct": 0.12}, "blurb": "+7% turn rate, +12% lateral thrust."},
	"stick_trigger": {"label": "Boost Trigger", "category": "stick", "price": 700.0, "stats": {"boost_pct": 0.25, "accel_pct": 0.03}, "blurb": "Boost thrust +12% and boosting costs 20% less energy; +3% acceleration."},
	"stick_gunner": {"label": "Gunner's Stick", "category": "stick", "price": 1000.0, "stats": {"fire_rate_pct": 0.10}, "blurb": "+10% fire rate."},
	# Cockpit layouts: ship systems.
	"cockpit_capacitor": {"label": "Capacitor Bank Layout", "category": "cockpit", "price": 500.0, "stats": {"energy_pct": 0.25}, "blurb": "+25% energy pool."},
	"cockpit_router": {"label": "Power Router Layout", "category": "cockpit", "price": 900.0, "stats": {"energy_regen_pct": 0.20, "redirect_cd_pct": -0.20}, "blurb": "+20% energy recharge; routing and focus recover 20% faster."},
	"cockpit_shield": {"label": "Shield Console Layout", "category": "cockpit", "price": 1000.0, "stats": {"shield_pct": 0.15, "shield_regen_pct": 0.10}, "blurb": "+15% shields, +10% shield regeneration."},
	"cockpit_engine": {"label": "Engine Console Layout", "category": "cockpit", "price": 850.0, "stats": {"speed_pct": 0.06, "accel_pct": 0.08}, "blurb": "+6% top speed, +8% acceleration."},
	# Chairs: endurance and G-loads (the push a pilot feels when the ship
	# speeds up or turns hard).
	"chair_racing": {"label": "Racing Seat", "category": "chair", "price": 500.0, "stats": {"accel_pct": 0.08, "strafe_pct": 0.06}, "blurb": "+8% acceleration, +6% lateral thrust."},
	"chair_crash": {"label": "Crash Couch", "category": "chair", "price": 800.0, "stats": {"collision_resist": 0.5, "hull_pct": 0.06}, "blurb": "Collision damage halved; +6% hull."},
	"chair_eject": {"label": "Ejection Seat", "category": "chair", "price": 700.0, "stats": {"respawn_pct": -0.25, "insurance": 0.30}, "blurb": "Respawn 25% faster; get 30% of your ship's value back when it dies."},
	"chair_command": {"label": "Command Throne", "category": "chair", "price": 1200.0, "stats": {"shield_resist": 0.07, "hull_resist": 0.05}, "blurb": "Shields take 7% and hull 5% less damage."},
	# Implants: high-end.
	"impl_reflex": {"label": "Reflex Implant", "category": "implant", "price": 1100.0, "stats": {"turn_pct": 0.10, "fire_rate_pct": 0.06}, "blurb": "+10% turn rate, +6% fire rate."},
	"impl_stim": {"label": "Stim Implant", "category": "implant", "price": 900.0, "stats": {"shield_delay": -1.5, "repair_recv_pct": 0.30}, "blurb": "Shields start recharging 1.5s sooner; +30% repairs received."},
	"impl_ledger": {"label": "Ledger Implant", "category": "implant", "price": 750.0, "stats": {"income": 1.0}, "blurb": "+1 credit/s income."},
	"impl_cortex": {"label": "Combat Cortex", "category": "implant", "price": 1500.0, "stats": {"damage_pct": 0.10, "fire_rate_pct": 0.04}, "blurb": "+10% damage, +4% fire rate."},
}

## Repair kit: a consumable that lives in an inventory slot (stacks of 3).
## Its fields: id (how a slot marks a kit stack), label, price [credits
## per kit], stack (most kits in one slot) and blurb. Pressing R uses one:
## it launches a repair drone that heals the pilot's own ship (see
## Structures.KIT_DRONE).
const KIT := {"id": "repair_kit", "label": "Repair Kit", "price": 60.0, "stack": 3,
	"blurb": "R: launches a repair drone that heals your hull for 10s. The drone can be shot down."}


## The ids of every item in category `cat` (such as "suit"), in the order
## they are written in ITEMS. The hangar's gear screen (HangarGear) uses it.
static func by_category(cat: String) -> Array:
	# Walk the whole table and keep the items of this category.
	var out: Array = []
	for id: String in ITEMS:
		if ITEMS[id]["category"] == cat:
			out.append(id)
	return out
