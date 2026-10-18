class_name PilotProfileShop
extends RefCounted
## WHAT THIS IS: the shop counter of one pilot's record (PilotProfile). It
## knows the rules for buying and selling with the pilot's own credits:
## gear, repair kits, a hull for the next launch, and modules for it.
##
## HOW IT WORKS: every purchase has a "blocker" check that returns "" when
## it is allowed, or a short reason the player can read ("Not enough
## credits (40 short)"). The buy function runs that check first, and
## changes nothing if it says no. The rules:
##   gear     one item per category (one helmet, one chair ...), a free
##            slot (6 in all), and enough credits.
##   kits     repair kits (60 credits) stack 3 to a slot: top up a stack
##            with room, or start one in a free slot.
##   selling  a slot sells for Rules.SELL_BACK (half) of its price; a kit
##            stack sells all its kits.
##   hull     must be unlocked for our team. The current hull trades in for
##            Rules.HULL_TRADE_IN (half) and its modules for
##            Rules.MODULE_TRADE_IN (40%); the new hull starts with none.
##   modules  need a hull they fit, a free module space (2 per ship) and
##            enough credits. Taking one off gives 40% back (rounded down
##            to whole credits).
## After gear changes, PilotProfile.gear_changed() makes the gear stats
## (and the flying ship's stats) get worked out again.
##
## WHO USES IT: PilotProfile makes one (PilotProfile.shop) and forwards
## gear_blocker(), buy_gear(), kit_blocker(), buy_kit(), sell_slot(),
## buy_hull(), module_blocker() and toggle_module() here. Callers use those
## on PilotProfile: the hangar screen (hangar.gd), the AI pilots
## (PilotShopping, PilotAI), WorldHangar (module swaps in a repair bay)
## and main.gd.

## The pilot record this part belongs to (we read and change its credits,
## slots, hull and modules). It is reached through a weak link: see
## `_profile_ref`.
var profile: PilotProfile:
	get:
		return _profile_ref.get_ref() as PilotProfile

## A "weak" link to the pilot record. PilotProfile holds this part with a
## normal (strong) link. If the part held the record strongly too, each
## would keep the other alive forever and Godot could never free them (a
## memory leak). A weak link points at the record without keeping it
## alive.
var _profile_ref: WeakRef


## Remember the pilot record (through a weak link). PilotProfile makes this
## part once.
func _init(owner: PilotProfile) -> void:
	_profile_ref = weakref(owner)


# --- gear ---------------------------------------------------------------------------

## Why gear item `id` can't be bought now, or "" if it can. Checked in this
## order: one item per category, a free slot, enough credits.
func gear_blocker(id: String) -> String:
	var def: Dictionary = Items.ITEMS[id]
	if profile.has_category(def["category"]):
		return "You already have a %s; sell it first" % Items.CATEGORY_LABEL[def["category"]]
	if profile.free_slots() == 0:
		return "All 6 slots are full; sell something first"
	if profile.credits < float(def["price"]):
		return "Not enough credits (%d short)" % int(ceil(float(def["price"]) - profile.credits))
	return ""


## Buy gear item `id` into the first empty slot. Returns "" when it worked,
## or why not (nothing changes then).
func buy_gear(id: String) -> String:
	var b := gear_blocker(id)
	if b != "":
		return b
	# Pay, and put it in the first empty slot.
	profile.credits -= float(Items.ITEMS[id]["price"])
	for i in profile.inventory.size():
		if (profile.inventory[i] as Dictionary).is_empty():
			profile.inventory[i] = {"id": id, "count": 1}
			break
	profile.gear_changed()
	return ""


# --- repair kits --------------------------------------------------------------------

## Why a repair kit can't be bought now, or "" if it can: enough credits,
## and either a kit stack with room (under Items.KIT "stack", 3) or a free
## slot.
func kit_blocker() -> String:
	var price: float = float(Items.KIT["price"])
	if profile.credits < price:
		return "Not enough credits (%d short)" % int(ceil(price - profile.credits))
	# A stack with room is enough...
	for s: Dictionary in profile.inventory:
		if not s.is_empty() and s["id"] == Items.KIT["id"] and int(s["count"]) < int(Items.KIT["stack"]):
			return ""
	# ...otherwise we need an empty slot.
	if profile.free_slots() == 0:
		return "All 6 slots are full; sell something first"
	return ""


## Buy one repair kit: top up the first stack with room, or start a new
## stack in the first empty slot. Returns "" when it worked, or why not.
func buy_kit() -> String:
	var b := kit_blocker()
	if b != "":
		return b
	profile.credits -= float(Items.KIT["price"])
	# Step 1: a stack with room?
	for s: Dictionary in profile.inventory:
		if not s.is_empty() and s["id"] == Items.KIT["id"] and int(s["count"]) < int(Items.KIT["stack"]):
			s["count"] = int(s["count"]) + 1
			return ""
	# Step 2: otherwise a new stack in the first empty slot.
	for i in profile.inventory.size():
		if (profile.inventory[i] as Dictionary).is_empty():
			profile.inventory[i] = {"id": Items.KIT["id"], "count": 1}
			return ""
	return ""


# --- selling ------------------------------------------------------------------------

## Sell slot `i` (0..5) for Rules.SELL_BACK (half) of its price. A kit
## stack sells every kit in it. An empty slot does nothing.
func sell_slot(i: int) -> void:
	var s: Dictionary = profile.inventory[i]
	if s.is_empty():
		return
	# Kits: half price for each kit in the stack. Gear: half its price.
	if s["id"] == Items.KIT["id"]:
		profile.credits += float(Items.KIT["price"]) * Rules.SELL_BACK * float(s["count"])
	elif s.has("mk"):
		# A Mk II item (GearMk2Feature) sells for half of everything paid.
		profile.credits += GearMk2Feature.total_paid(String(s["id"])) * Rules.SELL_BACK
	else:
		profile.credits += float(Items.ITEMS[s["id"]]["price"]) * Rules.SELL_BACK
	profile.inventory[i] = {}
	profile.gear_changed()


# --- hull and modules ---------------------------------------------------------------

## Buy hull `id` for the next launch. `ts` is our team's state (it says
## which hulls are unlocked). The current hull trades in for half its
## price (Rules.HULL_TRADE_IN) and its modules for 40%
## (Rules.MODULE_TRADE_IN); the new hull starts with no modules. Choosing
## the hull we already have does nothing. Returns "" or why not.
func buy_hull(id: String, ts: TeamState) -> String:
	if not ts.ship_unlocked(id):
		return "Locked: needs %s" % Tech.ship_unlock_label(id)
	if profile.hull_id == id:
		return ""
	# Step 1: what the old hull and its modules trade in for.
	var refund := 0.0
	if profile.hull_id != "":
		refund = float(Ships.HULLS[profile.hull_id]["price"]) * Rules.HULL_TRADE_IN
		for m: String in profile.modules:
			refund += Modules.price_for(m, profile.hull_id) * Rules.MODULE_TRADE_IN
	# Step 2: can we pay the rest?
	var price := float(Ships.HULLS[id]["price"])
	if profile.credits + refund < price:
		return "Not enough credits (%d short)" % int(ceil(price - profile.credits - refund))
	# Step 3: swap hulls; the modules went with the old one.
	profile.credits = profile.credits + refund - price
	profile.hull_id = id
	profile.modules.clear()
	return ""


## Why module `id` can't be fitted now, or "" if it can. Also "" when it
## is fitted already (toggle_module would then take it off). Checked in
## this order: a hull, a module that fits it (Modules.fit_blocker), a free
## module space (Modules.MAX_PER_SHIP, 2), enough credits.
func module_blocker(id: String) -> String:
	if profile.hull_id == "":
		return "Pick a ship first"
	if profile.modules.has(id):
		return ""
	var fit := Modules.fit_blocker(id, profile.hull_id)
	if fit != "":
		return fit
	if profile.modules.size() >= Modules.MAX_PER_SHIP:
		return "Ships hold 2 modules; sell one first"
	var price := Modules.price_for(id, profile.hull_id)
	if profile.credits < price:
		return "Not enough credits (%d short)" % int(ceil(price - profile.credits))
	return ""


## Fit module `id` (paying its price for this hull), or, if it is fitted
## already, take it off and get 40% back (Rules.MODULE_TRADE_IN, rounded
## down to whole credits). Returns "" or why it can't be fitted.
func toggle_module(id: String) -> String:
	# Fitted already: sell it back.
	if profile.modules.has(id):
		profile.modules.erase(id)
		profile.credits += floorf(Modules.price_for(id, profile.hull_id) * Rules.MODULE_TRADE_IN)
		return ""
	# Not fitted: check the rules, then pay and fit it.
	var b := module_blocker(id)
	if b != "":
		return b
	profile.credits -= Modules.price_for(id, profile.hull_id)
	profile.modules.append(id)
	return ""
