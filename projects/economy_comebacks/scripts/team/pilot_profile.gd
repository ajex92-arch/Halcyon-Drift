class_name PilotProfile
extends RefCounted
## WHAT THIS IS: one pilot's record for the whole match, human or AI. It
## outlives their ships: when a ship is destroyed, the pilot (and this
## record) carries on and respawns. It holds the pilot's credits (their own
## money, separate from the team treasury), their 6 gear slots (gear and
## repair kits), the hull and modules they will launch in next, what they
## are doing right now (docked, spooling, flying or dead), and their scores
## (kills, deaths, assists, streaks). DESIGN.md A3, A6.
##
## HOW IT WORKS: the record mostly holds numbers that other files change.
## It also answers questions about the gear slots (gear_stats(),
## free_slots(), kit_count() ...) and pays the pilot through earn(), which
## announces the payment so the screens can show "+45 minion". The shop
## rules (what may be bought or sold, and the paying) live in a part,
## PilotProfileShop (pilot_profile_shop.gd); the shop functions here only
## forward to it.
##
## WHO USES IT: WorldSetup makes one per pilot (and one for a human
## admiral). Economy pays pilots; MatchRules runs deaths and respawns;
## WorldHangar launches and docks them; the hangar screen and the AI
## pilots (PilotShopping) buy and sell; Ship and ShipStats read the gear
## stats; ShipAbilities uses up repair kits; the HUD, scoreboard and end
## screen show the scores.

# --- who and where ---------------------------------------------------------------

## The pilot's name, shown on the screens.
var callsign := ""
## Which side they fly for: 0 = Halcyon, 1 = Cinder.
var team := 0
## Their seat number in the team (0, 1, 2 ...). AI pilots use it, for
## example, to spread out around a shared point.
var slot := 0
## True for a human (the player, or a human admiral), false for AI pilots.
var is_human := false
## The pilot's own money, in credits. Starts at Rules.START_CREDITS (700).
var credits := Rules.START_CREDITS
## The 6 gear slots (Items.SLOTS). Each is {} (empty) or
## {"id": a gear item id or "repair_kit", "count": how many}. Only repair
## kits stack (up to 3 in a slot).
var inventory: Array = []
## The hull bought for the next launch ("" = none; Scouts are free).
var hull_id := ""
## The modules fitted to that hull (at most 2, Modules.MAX_PER_SHIP).
var modules: Array[String] = []
## What the pilot is doing: "docked" (in the hangar), "spooling" (waiting
## for a hyperspace launch), "flying" or "dead".
var state := "docked"
## The ship they are flying now (null when they have none).
var ship: Ship = null
## Seconds left: the respawn countdown while dead, or the hyperspace spool
## countdown while spooling.
var respawn_t := 0.0
## The repair bay a hyperspace launch will arrive at (null = none).
var spool_bay: RepairBay = null
## An AI pilot's job: "top", "mid" or "bot" (a lane), "jungle" or "flex".
## A human admiral's own record says "admiral".
var role := "mid"

# --- scores -----------------------------------------------------------------------

## Pilot ships of the other team this pilot destroyed (the last hit).
var kills := 0
## How many times their ship was destroyed.
var deaths := 0
## Enemy ship kills they helped with, without the last hit.
var assists := 0
## Enemy minions they finished off ("last hits").
var minion_kills := 0
## Derelict monsters they helped destroy.
var monster_kills := 0
## Kills in a row without dying (back to 0 when their ship is destroyed).
var streak := 0
## Their longest streak this match.
var best_streak := 0
## All credits earned this match: pay through earn() and the passive
## trickle (not refunds, sales or insurance).
var earned := 0.0
## All the damage they dealt this match (Combat adds to it).
var damage_done := 0.0

# --- inner workings ---------------------------------------------------------------

## The stats of all their gear added together. It is worked out again only
## after the gear changes (see gear_stats()).
var _gear_stats := StatBlock.new()
## True = the gear changed, so _gear_stats must be added up again.
var _gear_dirty := true
## The shop part (pilot_profile_shop.gd): buying and selling.
var shop: PilotProfileShop


## Make a pilot record: name `name_value`, team `t`, seat `slot_index`, and
## whether it is a human (`human`). All 6 gear slots start empty.
func _init(name_value: String, t: int, slot_index: int, human: bool) -> void:
	callsign = name_value
	team = t
	slot = slot_index
	is_human = human
	# Six empty slots.
	inventory.resize(Items.SLOTS)
	for i in Items.SLOTS:
		inventory[i] = {}
	# Make the shop part (it keeps a link back to this record).
	shop = PilotProfileShop.new(self)


## Pay the pilot `amount` credits for `reason` ("kill", "minion", "ore"
## ...). Nothing happens for 0 or less. It also adds to `earned` and
## announces the payment on Events (the game's message board:
## credits_earned), so the screens can show "+45 minion".
func earn(amount: float, reason: String) -> void:
	if amount <= 0.0:
		return
	credits += amount
	earned += amount
	Events.credits_earned.emit(self, amount, reason)


# --- gear slots ---------------------------------------------------------------------

## All the pilot's gear stats added together (repair kits have none), as a
## StatBlock: a bag of named numbers such as "income" or "bounty_pct". The
## sum is remembered and only worked out again after the gear changed.
func gear_stats() -> StatBlock:
	if _gear_dirty:
		_gear_dirty = false
		# Start from zero and add every gear item's stats.
		_gear_stats.clear()
		for s: Dictionary in inventory:
			if s.is_empty() or s["id"] == Items.KIT["id"]:
				continue
			# A Mk II item (GearMk2Feature; its slot entry has an "mk" key)
			# counts GearMk2Feature.STAT_MULT times as much.
			if s.has("mk"):
				var st: Dictionary = Items.ITEMS[s["id"]]["stats"]
				for k: String in st:
					_gear_stats.add(k, float(st[k]) * GearMk2Feature.STAT_MULT)
			else:
				_gear_stats.add_dict(Items.ITEMS[s["id"]]["stats"])
	return _gear_stats


## The gear changed: add up the gear stats again next time, and make the
## ship (if they are flying one) rebuild its stats. PilotProfileShop calls
## this after buying or selling.
func gear_changed() -> void:
	_gear_dirty = true
	if ship != null:
		ship.stats_dirty = true


## Does a slot hold item `id`?
func has_item(id: String) -> bool:
	for s: Dictionary in inventory:
		if not s.is_empty() and s["id"] == id:
			return true
	return false


## Does a slot hold a gear item of category `cat` (such as "helmet")?
## Repair kits have no category.
func has_category(cat: String) -> bool:
	for s: Dictionary in inventory:
		if not s.is_empty() and s["id"] != Items.KIT["id"] and Items.ITEMS[s["id"]]["category"] == cat:
			return true
	return false


## How many of the 6 slots are empty.
func free_slots() -> int:
	var n := 0
	for s: Dictionary in inventory:
		if s.is_empty():
			n += 1
	return n


## How many repair kits the pilot has, over all slots.
func kit_count() -> int:
	var n := 0
	for s: Dictionary in inventory:
		if not s.is_empty() and s["id"] == Items.KIT["id"]:
			n += int(s["count"])
	return n


## Use up one repair kit from the first slot that holds kits; a slot left
## with none becomes empty. Returns false if there are none.
## ShipAbilities calls this when the pilot launches a repair drone.
func consume_kit() -> bool:
	for i in inventory.size():
		var s: Dictionary = inventory[i]
		if not s.is_empty() and s["id"] == Items.KIT["id"]:
			s["count"] = int(s["count"]) - 1
			if int(s["count"]) <= 0:
				inventory[i] = {}
			return true
	return false


# --- shop (each of these forwards to PilotProfileShop) ------------------------------

## "" if gear item `id` can be bought now, else why not. The real code is
## PilotProfileShop.gear_blocker().
func gear_blocker(id: String) -> String:
	return shop.gear_blocker(id)


## Buy gear item `id` into an empty slot. Returns "" or why not. The real
## code is PilotProfileShop.buy_gear().
func buy_gear(id: String) -> String:
	return shop.buy_gear(id)


## "" if a repair kit can be bought now, else why not. The real code is
## PilotProfileShop.kit_blocker().
func kit_blocker() -> String:
	return shop.kit_blocker()


## Buy one repair kit. Returns "" or why not. The real code is
## PilotProfileShop.buy_kit().
func buy_kit() -> String:
	return shop.buy_kit()


## Sell slot `i` (or throw away its kits) for Rules.SELL_BACK (half) of
## its price. The real code is PilotProfileShop.sell_slot().
func sell_slot(i: int) -> void:
	shop.sell_slot(i)


# --- hull and modules for the next launch --------------------------------------------

## What the next-launch hull and its modules cost in all, in credits (0
## with no hull). PilotShopping uses it to work out a trade-in.
func hull_value() -> float:
	if hull_id == "":
		return 0.0
	var v := float(Ships.HULLS[hull_id]["price"])
	for m: String in modules:
		v += Modules.price_for(m, hull_id)
	return v


## Buy hull `id` (our team's state is `ts`); the old hull trades in for
## half, its modules for 40%. Returns "" or why not. The real code is
## PilotProfileShop.buy_hull().
func buy_hull(id: String, ts: TeamState) -> String:
	return shop.buy_hull(id, ts)


## "" if module `id` can be fitted now, else why not. The real code is
## PilotProfileShop.module_blocker().
func module_blocker(id: String) -> String:
	return shop.module_blocker(id)


## Fit module `id`, or sell it back for 40% if it is already fitted.
## Returns "" or why not. The real code is PilotProfileShop.toggle_module().
func toggle_module(id: String) -> String:
	return shop.toggle_module(id)


## Kills / deaths / assists as text, such as "3 / 1 / 4".
func kda() -> String:
	return "%d / %d / %d" % [kills, deaths, assists]
