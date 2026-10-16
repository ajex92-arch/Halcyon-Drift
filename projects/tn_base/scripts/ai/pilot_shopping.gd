class_name PilotShopping
extends RefCounted
## WHAT THIS IS: the "shopping brain" of an AI pilot (a part of PilotAI). It
## decides what to buy at the mothership (a hull, repair kits, modules and
## pilot gear), and whether something is worth flying home for in the
## middle of a match.
##
## HOW IT WORKS: every temperament has a wish list of hulls, best first
## (HULL_PREF). When docked, shop() buys the first hull on the list that is
## unlocked and affordable while keeping 120 credits spare, then repair kits
## (up to two), then the modules that suit the hull (MOD_PREF), then as much
## pilot gear as it can afford (GEAR_SMALL or GEAR_BIG). While flying,
## wants_shopping() says whether a better hull (or, with lots of credits, a
## piece of gear) is worth the trip home.
##
## WHO USES IT: PilotAI owns one (PilotAI.shopping). PilotAI.update_docked()
## calls shop(); PilotAI._think() calls wants_shopping(). Purchases go
## through PilotProfile (buy_hull, buy_kit, toggle_module, buy_gear).
##
## Words used here:
##   hull    the ship type a pilot flies (scout, fighter, destroyer...).
##   module  an upgrade bolted onto a hull (at most 2 per ship); it is sold
##           back when the hull is traded in.
##   gear    pilot equipment (helmet, suit, stick...) that the pilot keeps
##           through death; 6 inventory slots, at most one item per
##           category. Repair kits share those slots.

## Wish lists of hulls by temperament, best first. Heavies fly fighters
## until frigates unlock (playtest: with three Logistics corvettes per team,
## every fight was healed into a draw, so heavies don't buy them).
const HULL_PREF := {
	"heavy": ["battlecruiser", "destroyer", "flak", "ion", "fighter"],
	"heavy_ion": ["battlecruiser", "destroyer", "ion", "flak", "fighter"],
	"striker": ["bomber", "lance", "fighter"],
	"support": ["support", "logistics", "fighter"],
	# Lances melt corvettes but lose dogfights to Fighters (arena test: 3
	# Fighters beat 3 Lances 3-0), so only one laner per side flies them.
	"dog": ["fighter"],
	"lancer": ["lance", "fighter"],
	"jungle": ["lance", "fighter"],
}
## The modules we buy for each hull, in buying order (a hull holds 2).
const MOD_PREF := {
	"scout": ["engines"], "fighter": ["weapons", "engines"], "lance": ["capacitor", "weapons"],
	"bomber": ["weapons", "shield_booster"], "logistics": ["shield_booster", "plating"],
	"support": ["sensor_suite", "shield_booster"], "flak": ["plating", "shield_booster"],
	"ion": ["capacitor", "plating"], "destroyer": ["plating", "weapons"], "battlecruiser": ["plating", "shield_booster"],
}
## Pilot gear for small ships (and for a pilot with no hull yet), in buying
## order: mostly agility and firepower (turning, fire rate, energy), with
## extra hull last. Item ids are from Items.ITEMS.
const GEAR_SMALL := ["stick_precision", "helm_target", "cockpit_capacitor", "impl_reflex", "chair_racing", "suit_pressure"]
## Pilot gear for bigger ships (corvettes and up), in buying order: mostly
## toughness (armor, shields, damage resistance), then quicker systems and
## faster firing.
const GEAR_BIG := ["suit_armored", "cockpit_shield", "chair_command", "helm_neural", "impl_stim", "stick_gunner"]

## The pilot brain this part belongs to (we read its profile, temperament
## and the clock). It is reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## Spend credits while docked: hull first, then repair kits (cheap
## survival), then modules, then gear. We try to keep `reserve` (120
## credits) unspent.
func shop() -> void:
	var brain := ai
	var profile := brain.profile
	var ts := brain.world.teams[profile.team]
	var reserve := 120.0
	# Step 1: the hull. Take the first hull on our wish list that is
	# unlocked and that we can afford (counting the trade-in value of the
	# hull we own now) with the reserve left over.
	var want := ""
	for h: String in wish_list():
		if h == profile.hull_id:
			# Our current hull is the best we'd want right now: keep it.
			want = h
			break
		if not ts.ship_unlocked(h):
			continue
		var price: float = float(Ships.HULLS[h]["price"])
		var trade := profile.hull_value() * Rules.HULL_TRADE_IN if profile.hull_id != "" else 0.0
		if profile.credits + trade >= price + reserve:
			want = h
			break
	# Step 2: nothing on the list fits: keep our hull, or (with none) buy a
	# fighter if we have 150 credits plus the reserve, else a free scout.
	if want == "":
		want = profile.hull_id if profile.hull_id != "" else ("fighter" if profile.credits >= 150.0 + reserve else "scout")
	if profile.hull_id != want:
		profile.buy_hull(want, ts)
	if profile.hull_id == "":
		profile.buy_hull("scout", ts)
	# Step 3: repair kits, until we carry 2 (only while we have more than
	# 200 credits and room for them).
	while profile.kit_count() < 2 and profile.kit_blocker() == "" and profile.credits > 200.0:
		profile.buy_kit()
	# Step 4: the modules that suit our hull, if they still leave the
	# reserve.
	for m: String in MOD_PREF.get(profile.hull_id, []):
		if not profile.modules.has(m) and profile.module_blocker(m) == "" and profile.credits - Modules.price_for(m, profile.hull_id) > reserve:
			profile.toggle_module(m)
	# Step 5: then as much gear as we can afford (one slot stays free for
	# the kit stack; see next_gear).
	var g := next_gear()
	while g != "" and profile.credits - float(Items.ITEMS[g]["price"]) > reserve:
		if profile.buy_gear(g) != "":
			break
		g = next_gear()


## Hulls we want, best first. After 20:00 (1,200 seconds of game time) the
## dogfighters move up to flak frigates and the lancer to an ion frigate,
## so late fleets field about 5 big ships per side (a major engagement, and
## enough weight to siege).
func wish_list() -> Array:
	var brain := ai
	var base: Array = HULL_PREF[brain.temperament]
	if brain.world.time > 1200.0:
		if brain.temperament == "dog":
			return ["flak"] + base
		if brain.temperament == "lancer":
			return ["ion"] + base
	return base


## The next pilot gear item on our wish list (one we don't own, in a
## category we haven't filled), or "" for none. With no repair kits, one
## free slot is kept for them, so "" also means "no room".
func next_gear() -> String:
	var brain := ai
	var profile := brain.profile
	if profile.free_slots() <= (1 if profile.kit_count() == 0 else 0):
		return ""
	# Small ships (or no hull yet) use the small-ship list.
	var gear: Array = GEAR_SMALL if profile.hull_id == "" or Ships.size_of(profile.hull_id) == Rules.SIZE_SMALL else GEAR_BIG
	for g: String in gear:
		if not profile.has_item(g) and not profile.has_category(Items.ITEMS[g]["category"]):
			return g
	return ""


## Worth a trip home? Returns why ("hull:destroyer" = to buy a destroyer,
## "gear:suit_armored" = to buy that gear), or "" for "no, keep fighting".
## Only when something specific is affordable, not right after launching,
## and not with enemies close.
func wants_shopping(ship: Ship) -> String:
	var brain := ai
	var world := brain.world
	var profile := brain.profile
	# Step 1: not in the first 150 seconds after a launch. (Playtest: with
	# 60 s, 4-6 pilots per team were always flying home.)
	if world.time - brain.launched_at < 150.0:
		return ""
	# Step 2: not with an enemy ship or minion within 2,500.
	if world.any_enemy_ship_near(ship.global_position, 2500.0, ship.team):
		return ""
	var ts := world.teams[ship.team]
	# Step 3: big ships and bombers never leave in the middle of our siege
	# (playtest: three destroyers at full hull left an assault together to
	# buy battlecruisers the moment they unlocked).
	if ts.siege_lane != "" and (not ship.is_small() or ship.hull_id == "bomber"):
		return ""
	# "Far" = more than 9,000 from our mothership's hull (or no mothership).
	var ms := world.mothership(ship.team)
	var far := ms == null or ms.hull_dist(ship.global_position) > 9000.0
	# Step 4: a better hull from our wish list that we can afford (credits
	# plus half our ship's value as trade-in, with 200 to spare).
	for h: String in wish_list():
		if h == ship.hull_id:
			break
		if ts.ship_unlocked(h) and profile.credits + ship.bounty_value() * Rules.HULL_TRADE_IN >= float(Ships.HULLS[h]["price"]) + 200.0:
			return "hull:" + h
	# Step 5: gear alone is worth the flight only with a good pile of
	# credits (or when we'd want the repair anyway).
	var g := next_gear()
	# Gear isn't worth a trip across the map (playtest: two frigates spent a
	# whole siege flying home for gear, 25,000 away).
	if g == "" or far:
		return ""
	# Pilots shop every time they respawn anyway, so a gear-only trip needs
	# a big bank: at least 2,500 credits and twice the price plus 400, or
	# (below half hull) the price plus 100. (Playtest: 3-4 per team were
	# always flying home for gear.)
	var price := float(Items.ITEMS[g]["price"])
	if profile.credits >= maxf(2500.0, price * 2.0 + 400.0) or (ship.hull_frac() < 0.5 and profile.credits >= price + 100.0):
		return "gear:" + g
	return ""
