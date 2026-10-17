class_name MinionBuffs
extends RefCounted
## WHAT THIS IS: the one place where the fork "teamfights_jungle" boosts
## minions. The Salvage Core (SalvageCoreFeature), the Dreadnought Boon
## (EpicNeutralFeature) and the Vanguard reward (FeatsFeature) all give
## friendly minions more hull and, against buildings, more damage. The game
## has only ONE minion damage hook (Combat.minion_scale_hook), so this object
## owns it and the three modules just add "sources" to it.
##
## HOW IT WORKS: a source is one buff: which team's minions it helps, when it
## ends, how much extra hull it gives (1.2 = +20%), how much harder those
## minions hit buildings and the mothership (1.4 = x1.4; ships are never
## hit harder), and optionally a carrier ship and a radius (then only
## minions within the radius of the carrier are helped).
##   - The damage part is the hook _scale(): for a minion's hit on a
##     structure (a turret, a repair bay or a mothership) it returns the
##     minion's strength times the best matching source's multiplier (the
##     best one, not a product, so two buffs never exceed x1.4 together).
##     This happens "after the minion multipliers" because Combat has already
##     applied the damage table and the minion rules when it calls the hook.
##   - The hull part runs every HALF_SECOND in tick(): each helped minion
##     gets its hull and maximum hull multiplied (its hull keeps the same
##     fraction), and gets them divided again when the buff stops covering
##     it, so a damaged minion is never healed for free.
## It makes no random numbers, and it is only made when one of the modules
## above is on (ensure()).
##
## WHO USES IT: SalvageCoreFeature, EpicNeutralFeature and FeatsFeature call
## ensure(world) and add_source() / remove_source(). Combat calls _scale()
## through minion_scale_hook; World calls tick() through tick_hooks.

## The key under which the one MinionBuffs of a match hangs on the World
## (World.set_meta).
const META := "tfj_minion_buffs"
## Seconds between two hull passes.
const HALF_SECOND := 0.5

## The match this belongs to.
var world: World
## The live buffs: dictionaries with keys key (text), team (0 or 1), until
## (match time in seconds), hull (hull multiplier), structs (damage
## multiplier against buildings), carrier (a Unit or null), radius (world
## units, used with a carrier), usage (the Game.usage name that counts
## minion-seconds, or ""), acc (minion-seconds not yet counted).
var sources: Array = []
## Minion uid -> the hull multiplier currently applied to that minion.
var applied := {}
## Seconds until the next hull pass.
var _t := 0.0


## The MinionBuffs of match `w`: made (and hooked in) on the first call.
static func ensure(w: World) -> MinionBuffs:
	if w.has_meta(META):
		return w.get_meta(META) as MinionBuffs
	var mb := MinionBuffs.new()
	mb.world = w
	w.set_meta(META, mb)
	MinionHookChain.add(w, Callable(mb, "_scale"))
	w.tick_hooks.append(Callable(mb, "tick"))
	return mb


## Add (or replace) the buff `key` for team `team`'s minions until match time
## `until`. `hull` and `structs` are the multipliers (1.0 = none). With a
## `carrier` unit only minions within `radius` of it are helped. `usage` is
## the Game.usage name that counts the minion-seconds (or "").
func add_source(key: String, team: int, until: float, hull: float, structs: float, carrier: Unit = null, radius: float = INF, usage: String = "") -> void:
	remove_source(key)
	sources.append({"key": key, "team": team, "until": until, "hull": hull, "structs": structs,
		"carrier": carrier, "radius": radius, "usage": usage, "acc": 0.0})


## End the buff `key` now (if it is running). The hull pass takes the extra
## hull back within half a second.
func remove_source(key: String) -> void:
	for i in range(sources.size() - 1, -1, -1):
		if sources[i]["key"] == key:
			sources.remove_at(i)


## True if buff `s` helps minion `m` right now (right team, and near the
## carrier when it has one).
func _covers(s: Dictionary, m: Minion) -> bool:
	if int(s["team"]) != m.team:
		return false
	var c: Variant = s["carrier"]
	if c == null:
		return true
	return is_instance_valid(c) and (c as Unit).global_position.distance_to(m.global_position) <= float(s["radius"])


## Combat's minion_scale_hook: the strength minion `m` should use against
## `target`. Against buildings (turrets, repair bays, motherships) it is the
## minion's own strength times the best matching buff; against anything else
## it is the minion's own strength (no change).
func _scale(m: Minion, target: Unit, scale: float) -> float:
	if sources.is_empty() or not target.is_structure():
		return scale
	var best := 1.0
	for s: Dictionary in sources:
		if float(s["structs"]) > best and _covers(s, m):
			best = float(s["structs"])
	return scale * best


## Called by World every tick: every HALF_SECOND, drop ended buffs and
## correct the hull of the minions (see HOW IT WORKS).
func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = HALF_SECOND
	# Step 1: drop buffs that ended, or whose carrier is gone.
	for i in range(sources.size() - 1, -1, -1):
		var s: Dictionary = sources[i]
		var c: Variant = s["carrier"]
		var carrier_lost := c != null and (not is_instance_valid(c) or not (c as Unit).alive)
		if world.time >= float(s["until"]) or carrier_lost:
			sources.remove_at(i)
	if sources.is_empty() and applied.is_empty():
		return
	# Step 2: every live minion gets the product of the hull multipliers that
	# cover it. Remember who is alive, to forget the dead afterwards.
	var alive_ids := {}
	for m: Minion in world.minions:
		if not m.alive:
			continue
		alive_ids[m.uid] = true
		var want := 1.0
		for s: Dictionary in sources:
			if float(s["hull"]) != 1.0 and _covers(s, m):
				want *= float(s["hull"])
		var had := float(applied.get(m.uid, 1.0))
		if absf(want - had) > 0.0001:
			var ratio := want / had
			m.hull_max *= ratio
			m.hull *= ratio
			if absf(want - 1.0) < 0.0001:
				applied.erase(m.uid)
			else:
				applied[m.uid] = want
	# Step 3: forget dead minions, and count the minion-seconds each buff
	# with a usage name has helped.
	for uid in applied.keys():
		if not alive_ids.has(uid):
			applied.erase(uid)
	for s: Dictionary in sources:
		if str(s["usage"]) == "":
			continue
		var helped := 0
		for m: Minion in world.minions:
			if m.alive and _covers(s, m):
				helped += 1
		s["acc"] = float(s["acc"]) + float(helped) * HALF_SECOND
		var whole := int(s["acc"])
		if whole > 0:
			Game.count_usage(str(s["usage"]), whole)
			s["acc"] = float(s["acc"]) - float(whole)
