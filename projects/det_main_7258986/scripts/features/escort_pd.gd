class_name EscortPdFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "escort_pd" rule variant (idea
## E2 of the combat_roles fork): escorts make big ships deadly. A big ship
## (a LARGE frigate or a CAPITAL destroyer / battlecruiser) with friends
## around it shoots strike craft down faster; a big ship all alone is easy
## prey. So a frigate that flies with its wave is a wall, and one that
## wanders off dies to a pair of bombers.
##
## HOW IT WORKS: install() adds one function to the match's tick hooks.
## Every 0.5 s it goes over the live pilot ships and, for each LARGE or
## CAPITAL one, works out its "support":
##   support = friendly pilot ships within 2,500 world units (not itself)
##             + (friendly minions within 2,500) / 3, rounded down;
##   and never more than 3.
## Then it applies two rules:
##   1. The anti-strike-craft guns fire at x(0.6 + 0.2 x support): every
##      point-defense gun (pd_gun, also the PD Module), the destroyer's and
##      battlecruiser's flak mounts (flak_auto) and the Flak Frigate's
##      aimed flak battery. So alone it fires at 60% speed, with 3 friends
##      at 120%. The main batteries (heavy cannons, ion beams, torpedoes)
##      are not touched. The rate is changed by giving each such gun its own
##      copy of the weapon data (the shared table never changes) and writing
##      the new "rate" into it.
##   2. With support 0 the shield refills at x0.7 (the shield's own refill
##      number, ShieldZones.regen, is set; gear and routing still multiply
##      on top as before).
## The ship status panel shows ESCORTED or ISOLATED (RoleHud). The AI needs
## no new rule: pilots already fly their wave, and the rule makes their
## flying matter. Every pass adds 0.5 s per big ship to Game.usage
## "big_escorted_seconds" (support 1 or more) or "big_isolated_seconds"
## (support 0). Other features of this fork may ask support_n() (the
## Lance hunts ships that are isolated).
##
## WHO USES IT: FeatureRegistry installs it for --variant=escort_pd:on.
## RoleHud reads status(); LanceRoleFeature reads support_n().

## The variant key this module belongs to.
const KEY := "escort_pd"
## Seconds between two passes over the big ships.
const SCAN_EVERY := 0.5
## How close (world units) a friend must be to count as support.
const RADIUS := 2500.0
## This many friendly minions count as one friend.
const MINIONS_PER_FRIEND := 3
## The most support that counts.
const MAX_SUPPORT := 3
## Fire rate of the anti-strike-craft guns with no support (0.6 = 60%).
const BASE_MULT := 0.6
## Extra fire rate for every point of support (0.2 = +20%).
const STEP_MULT := 0.2
## Shield refill multiplier of a big ship with no support.
const ISOLATED_REGEN := 0.7
## The guns that are slowed or sped up: weapon ids in Weapons.
const GUNS := ["pd_gun", "flak_auto", "flak_battery"]

## The match.
var world: World
## Seconds since the last pass.
var _t := 0.0
## Each big ship's support from the last pass: ship uid -> 0..3.
var _support := {}
## The guns of each big ship: ship uid -> [[mount, normal rate], ...].
var _guns := {}
## How many mounts the ship had when its guns were listed: uid -> count (a
## module bought in a repair bay adds a mount, and then the list is made
## again).
var _mount_count := {}
## Seconds of isolated big ships not yet counted in Game.usage.
var _acc_isolated := 0.0
## Seconds of escorted big ships not yet counted in Game.usage.
var _acc_escorted := 0.0
## A reusable list for spatial-hash searches.
var _scratch: Array = []


## Plug the feature into match `w`: one tick hook. FeatureRegistry calls it
## once at match start.
func install(w: World) -> void:
	world = w
	w.tick_hooks.append(Callable(self, "_tick"))


## Every tick (a hook): every SCAN_EVERY seconds go over the big ships.
func _tick(dt: float) -> void:
	_t += dt
	if _t < SCAN_EVERY:
		return
	_t -= SCAN_EVERY
	var live := {}
	for s: Ship in world.ships:
		# Step 1: only live LARGE and CAPITAL pilot ships.
		if not s.alive or s.size_class < Rules.SIZE_LARGE:
			continue
		live[s.uid] = true
		# Step 2: the support now, and the two rules.
		var n := _count_support(s)
		_support[s.uid] = n
		_apply_guns(s, n)
		s.shields.regen = float(s.def["shield_regen"]) * (ISOLATED_REGEN if n == 0 else 1.0)
		# Step 3: the usage counts (whole seconds are passed on).
		if n == 0:
			_acc_isolated += SCAN_EVERY
		else:
			_acc_escorted += SCAN_EVERY
	# Step 4: forget ships that are gone (dead or docked).
	for uid in _support.keys():
		if not live.has(uid):
			_support.erase(uid)
			_guns.erase(uid)
			_mount_count.erase(uid)
	_flush("big_isolated_seconds", true)
	_flush("big_escorted_seconds", false)


## Pass the whole seconds collected so far on to Game.usage. `isolated`
## picks which pile.
func _flush(name: String, isolated: bool) -> void:
	var whole := int(_acc_isolated if isolated else _acc_escorted)
	if whole <= 0:
		return
	Game.count_usage(name, whole)
	if isolated:
		_acc_isolated -= float(whole)
	else:
		_acc_escorted -= float(whole)


## The support of big ship `s` now: friendly pilot ships and a third of the
## friendly minions within RADIUS, at most MAX_SUPPORT.
func _count_support(s: Ship) -> int:
	var p := s.global_position
	var ships := 0
	var minions := 0
	for u: Unit in world.unit_hash.query(p, RADIUS, _scratch):
		if u == s or not u.alive or u.team != s.team:
			continue
		if u.global_position.distance_squared_to(p) > RADIUS * RADIUS:
			continue
		if u.kind == Unit.K_SHIP:
			ships += 1
		elif u.kind == Unit.K_MINION:
			minions += 1
	return mini(MAX_SUPPORT, ships + floori(float(minions) / float(MINIONS_PER_FRIEND)))


## Set the rate of fire of ship `s`'s anti-strike-craft guns for support `n`
## (see HOW IT WORKS, rule 1).
func _apply_guns(s: Ship, n: int) -> void:
	# Step 1: list the guns again if this is a new ship or its mounts changed.
	if not _guns.has(s.uid) or int(_mount_count.get(s.uid, -1)) != s.mounts.size():
		var list: Array = []
		for m: WeaponMount in s.mounts:
			if GUNS.has(m.weapon_id):
				# The gun gets its own copy of the weapon data, and we remember
				# the normal rate from the shared table.
				m.def = m.def.duplicate()
				list.append([m, float(Weapons.get_def(m.weapon_id)["rate"])])
		_guns[s.uid] = list
		_mount_count[s.uid] = s.mounts.size()
	# Step 2: write the new rate into every gun's own data.
	var mult := BASE_MULT + STEP_MULT * float(n)
	for g: Array in _guns[s.uid]:
		(g[0] as WeaponMount).def["rate"] = float(g[1]) * mult


## The support (0..3) that big ship `s` had at the last pass, or -1 when it
## is not a big ship or has not been looked at yet.
func support_n(s: Ship) -> int:
	return int(_support.get(s.uid, -1))


## The words for the ship status panel: "ESCORTED x2" (support 1 or more),
## "ISOLATED" (support 0), or "" for a ship that is not big (or not yet
## looked at).
func status(s: Ship) -> String:
	var n := support_n(s)
	if n < 0:
		return ""
	return "ISOLATED" if n == 0 else "ESCORTED x%d" % n
