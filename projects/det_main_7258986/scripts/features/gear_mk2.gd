class_name GearMk2Feature
extends RefCounted
## WHAT THIS IS: the feature module for idea C3, the Mk II gear tier
## (variant gear_mk2:on). Every gear item can be upgraded to a stronger
## "Mk II" version, so a rich pilot always has something worth buying late
## in the match. FLAG for the user: this is a repeatable money sink (every
## item can be upgraded once); the progress notes left sinks to the user.
##
## HOW IT WORKS: a pilot who OWNS the ordinary (Mk I) item and is docked at
## the mothership may pay 2.5 times the item's price to upgrade it. The
## inventory entry stays in the same slot and category and gets one more key,
## {"id": ..., "count": 1, "mk": 2}. Every stat of a Mk II item counts 1.6
## times as much (PilotProfile.gear_stats reads STAT_MULT). Selling a Mk II
## item gives back half of everything paid (price plus upgrade) through
## PilotProfileShop.sell_slot. The hangar's Gear tab shows an "Upgrade to Mk
## II" button under the slots (HangarGear), and the slot cards say "Mk II".
## The AI uses it as a new step 6 in PilotShopping.shop(): once its gear
## list is bought (or the slots are full), it upgrades its items in list
## order (GEAR_SMALL or GEAR_BIG), whenever the credits left after paying
## stay above its reserve. A pilot with a big bank (the same rule as for
## new gear) also flies home for an upgrade (PilotShopping.wants_shopping).
## Every upgrade is counted in Game.usage as "mk2_purchases".
##
## WHO USES IT: FeatureRegistry installs it for --variant=gear_mk2:on (it
## only marks the match as having the feature). PilotProfile, PilotProfileShop,
## PilotShopping and HangarGear call its static functions.

## The variant key.
const KEY := "gear_mk2"
## A Mk II item's stats are this many times the Mk I stats.
const STAT_MULT := 1.6
## The upgrade costs this many times the item's price.
const PRICE_MULT := 2.5


## Mark the match as having Mk II gear. Nothing else to set up: the work is
## done by the static functions below.
func install(_w: World) -> void:
	pass


## Is Mk II gear on in the running match?
static func is_on() -> bool:
	var w := Game.world as World
	return w != null and w.features.has(KEY)


## What upgrading gear item `id` to Mk II costs, in credits.
static func upgrade_price(id: String) -> float:
	return float(Items.ITEMS[id]["price"]) * PRICE_MULT


## Everything paid for a Mk II item `id` (price plus upgrade), in credits.
static func total_paid(id: String) -> float:
	return float(Items.ITEMS[id]["price"]) * (1.0 + PRICE_MULT)


## Why slot `i` of `profile` can't be upgraded now, or "" if it can: it must
## hold a gear item (not a repair kit) that is still Mk I, and the pilot
## must have the credits. (Where the pilot is - docked at the mothership - is
## checked by the caller: the hangar, or the AI while it shops.)
static func upgrade_blocker(profile: PilotProfile, i: int) -> String:
	var s: Dictionary = profile.inventory[i]
	if s.is_empty() or s["id"] == Items.KIT["id"]:
		return "Nothing to upgrade"
	if s.has("mk"):
		return "Already Mk II"
	var price := upgrade_price(String(s["id"]))
	if profile.credits < price:
		return "Not enough credits (%d short)" % int(ceil(price - profile.credits))
	return ""


## Upgrade slot `i` of `profile` to Mk II. Returns "" when it worked, or why
## not (nothing changes then).
static func upgrade(profile: PilotProfile, i: int) -> String:
	var b := upgrade_blocker(profile, i)
	if b != "":
		return b
	var s: Dictionary = profile.inventory[i]
	profile.credits -= upgrade_price(String(s["id"]))
	s["mk"] = 2
	profile.gear_changed()
	Game.count_usage("mk2_purchases")
	return ""


## The slot that holds gear item `id`, or -1.
static func slot_of(profile: PilotProfile, id: String) -> int:
	for i in profile.inventory.size():
		var s: Dictionary = profile.inventory[i]
		if not s.is_empty() and s["id"] == id:
			return i
	return -1


## The AI's shopping step 6: walk `gear_list` (GEAR_SMALL or GEAR_BIG) in
## order and upgrade each owned Mk I item whose price leaves more than
## `reserve` credits.
static func ai_upgrade(profile: PilotProfile, reserve: float, gear_list: Array) -> void:
	for g: String in gear_list:
		var i := slot_of(profile, g)
		if i < 0 or (profile.inventory[i] as Dictionary).has("mk"):
			continue
		if profile.credits - upgrade_price(g) > reserve:
			upgrade(profile, i)


## The AI's trip-home reason for an upgrade ("gear:<id>"), or "". Same bank
## rule as for new gear: at least 2,500 credits and twice the price plus 400,
## or (below half hull) the price plus 100. `ship` is the pilot's ship.
static func ai_trip_reason(profile: PilotProfile, ship: Ship, gear_list: Array) -> String:
	for g: String in gear_list:
		var i := slot_of(profile, g)
		if i < 0 or (profile.inventory[i] as Dictionary).has("mk"):
			continue
		var price := upgrade_price(g)
		if profile.credits >= maxf(2500.0, price * 2.0 + 400.0) or (ship.hull_frac() < 0.5 and profile.credits >= price + 100.0):
			return "gear:" + g
		return ""
	return ""
