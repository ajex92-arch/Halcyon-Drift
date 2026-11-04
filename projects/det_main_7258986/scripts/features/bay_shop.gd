class_name BayShopFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "bay_shop" rule variant (idea A6
## of the pacing_downtime fork): "Kits and gear sold at repair bays". A pilot
## who hovers next to a friendly repair bay can buy repair kits and pilot
## gear there, so a trip home just to shop is no longer needed.
## REQ-CHANGE: "pilots have to buy personal repair kits at the mothership"
## (swapping ship modules at bays already exists in the base game).
##
## HOW IT WORKS: --variant=bay_shop:on. A bay can serve a pilot when all of
## these are true (can_serve()):
##   - the pilot's ship is inside the bay's module-swap circle (within 600
##     world units; World.bay_at);
##   - the bay is anchored and not damaged (WorldHangar's rule for repairs:
##     RepairBay.can_repair(), no hull damage for 5 s);
##   - no enemy ship or minion is within 1,500 of the pilot.
## Prices and rules are exactly the mothership's (PilotProfile.buy_kit and
## buy_gear). Hulls and modules are NOT sold at bays: they need the mothership.
## For the human, the hangar panel (B) lets the Kits and Gear tabs buy while
## the ship is inside such a bay (Hangar.can_shop_goods asks human_can_shop()).
## For the AI:
##   1. Every BUY_EVERY (0.5) seconds each AI pilot ship that a bay can serve,
##      while its mothership is at least 6,000 further away than the bay,
##      runs the pilot's usual wish list for kits and gear (the same one it
##      runs in the hangar: up to 2 kits when it has over 200 credits, then
##      the next wanted gear item while 120 credits stay unspent).
##   2. A pilot that PilotShopping sent home only for gear ("gear:...") flies
##      to such a bay instead of the mothership when one is at least 6,000
##      closer (ai_think_home(), called by PilotGoals.think_home), shops there,
##      and goes back to its lane.
## Usage counters in Game.usage: "bay_purchases" (kits and gear bought at a
## bay), "bay_kit_purchases", "bay_gear_purchases", "bay_shop_trips" (gear
## trips sent to a bay).
##
## WHO USES IT: FeatureRegistry installs it. Hangar.can_shop_goods() calls
## human_can_shop(); PilotGoals.think_home() calls ai_think_home(); World's
## tick_hooks call tick().

## The variant key this module belongs to.
const KEY := "bay_shop"
## Seconds between two shopping checks of the AI pilots.
const BUY_EVERY := 0.5
## No enemy ship or minion may be closer than this (world units) to the pilot.
const ENEMY_CLEAR := 1500.0
## The bay must be at least this much (world units) closer to the pilot than
## the mothership, for the AI to shop there.
const MIN_GAIN := 6000.0
## Credits the AI keeps unspent (the same as PilotShopping's reserve).
const RESERVE := 120.0
## The AI buys repair kits only while it has more than this many credits and
## fewer than KITS_WANTED of them.
const KIT_CREDITS := 200.0
## How many repair kits the AI wants to carry (like PilotShopping.shop).
const KITS_WANTED := 2

## The running match.
var world: World
## Seconds until the next AI shopping check.
var _t := 0.0
## The pilots that are on a gear trip to a bay right now (so each trip is
## counted once): PilotProfile -> true.
var _tripping := {}


## Plug the feature into match `w`.
func install(w: World) -> void:
	world = w
	w.tick_hooks.append(tick)


## The repair bay that can serve `ship` now, or null (see HOW IT WORKS for
## the three conditions).
func serving_bay(ship: Ship) -> RepairBay:
	var bay := world.bay_at(ship.team, ship.global_position)
	if bay == null or not bay.can_repair():
		return null
	if world.any_enemy_ship_near(ship.global_position, ENEMY_CLEAR, ship.team):
		return null
	return bay


## May the human pilot of hangar `h` buy kits and gear now? True while the
## pilot's ship is served by a bay. Hangar.can_shop_goods() calls it.
func human_can_shop(h: Hangar) -> bool:
	var ship := h.profile.ship
	return ship != null and is_instance_valid(ship) and ship.alive and serving_bay(ship) != null


# --- the AI ---------------------------------------------------------------------------------------

## The tick hook (World.tick_hooks): every BUY_EVERY seconds let each AI
## pilot ship that a bay serves (and whose mothership is far) go shopping.
func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = BUY_EVERY
	for ship: Ship in world.ships:
		if not ship.alive or ship.profile == null or ship.profile.is_human or not (ship.controller is PilotAI):
			continue
		var bay := serving_bay(ship)
		if bay == null:
			continue
		var ms := world.mothership(ship.team)
		if ms != null and ms.hull_dist(ship.global_position) - ship.global_position.distance_to(bay.global_position) < MIN_GAIN:
			continue
		var brain := ship.controller as PilotAI
		var bought := _shop_goods(brain)
		# A gear trip that has been shopped is over: back to the job.
		if bought > 0 and brain.state == "home" and brain.home_reason.begins_with("gear:"):
			_tripping.erase(brain.profile)
			brain.home_reason = ""
			brain.state = "jungle" if ship.profile.role == "jungle" else "lane"


## Run the AI pilot's kit-and-gear wish list at a bay. Returns how many items
## it bought. No hulls or modules, and no random numbers.
func _shop_goods(brain: PilotAI) -> int:
	var p := brain.profile
	var bought := 0
	# Step 1: repair kits, until the pilot carries KITS_WANTED.
	while p.kit_count() < KITS_WANTED and p.kit_blocker() == "" and p.credits > KIT_CREDITS:
		p.buy_kit()
		bought += 1
		Game.count_usage("bay_kit_purchases")
	# Step 2: gear, while the reserve stays unspent.
	var g := brain.shopping.next_gear()
	while g != "" and p.credits - float(Items.ITEMS[g]["price"]) > RESERVE:
		if p.buy_gear(g) != "":
			break
		bought += 1
		Game.count_usage("bay_gear_purchases")
		g = brain.shopping.next_gear()
	if bought > 0:
		Game.count_usage("bay_purchases", bought)
	return bought


## Called by PilotGoals.think_home() for an AI pilot that is thinking about
## where to fly. When the pilot is on a gear-only shopping trip ("home" with
## a reason starting "gear:") and a bay that can serve it is at least 6,000
## closer than the mothership, fly to that bay instead (returns true: this
## think is done). Otherwise returns false and the pilot flies home as usual.
func ai_think_home(brain: PilotAI, ship: Ship, ms: Mothership) -> bool:
	if brain.state != "home" or not brain.home_reason.begins_with("gear:") or ms == null:
		return false
	# Step 1: the nearest anchored, undamaged bay of ours that is far enough
	# ahead of the mothership, has no visible enemy near it, and (for ships
	# bigger than a strike craft) lies in the open lanes.
	var best: RepairBay = null
	var best_d := INF
	var d_ms := ms.hull_dist(ship.global_position)
	for b in world.bays:
		if b.team != ship.team or not b.alive or not b.can_repair():
			continue
		var d := b.global_position.distance_to(ship.global_position)
		if d_ms - d < MIN_GAIN or d >= best_d:
			continue
		if not ship.is_small() and not world.map.in_open_lane(b.global_position):
			continue
		if world.any_enemy_ship_near(b.global_position, ENEMY_CLEAR, ship.team):
			continue
		best = b
		best_d = d
	if best == null:
		return false
	# Step 2: fly there (shoot only what is within 900 on the way, as when
	# flying home).
	brain.target = brain.targeting.pick_target(ship, 900.0)
	brain.goal = best.global_position
	if not _tripping.has(brain.profile):
		_tripping[brain.profile] = true
		Game.count_usage("bay_shop_trips")
	return true
