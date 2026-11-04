extends RefCounted
## WHAT THIS IS: the fun probe's "time to kill" stopwatch. For every pilot
## ship that dies it measures how long the ship was under fire before it
## died, so we can tell readable fights (several seconds, time to react)
## from sudden "burst" deaths. docs/FUN_RESEARCH.md, fun model ingredients
## 7 (small ships) and 8 (big ships out of position).
##
## HOW IT WORKS: a ship's "damage chain" starts with a hit that comes more
## than 4 s after its previous hit. When the ship dies, its TTK (time to
## kill) = time of death - start of its current chain. A ship killed by the
## first hit after a quiet spell has a TTK of 0.
##   How hits are seen: every tick (1/60 s) tick() looks at each pilot
##   ship's last_damage_time (Unit.take_hit() sets it to the match time on
##   every hit, shields or hull). A new value means a hit landed during that
##   tick. This is the same as listening to every hit (FUN_RESEARCH.md says
##   "from the damage hook"), because all hits in one tick share one time;
##   it also works in builds without the hook.
##   on_death() is called from the kill event, which comes during the tick
##   of the killing hit (before tick() has seen it), so it checks that hit
##   itself.
##   Big ships (large and capital, Rules.SIZE_LARGE and up): when a chain
##   starts we note whether the ship was ISOLATED: no friendly pilot ship
##   and fewer than 3 friendly minions within 3,000 world units. Their TTKs
##   go into two lists, isolated and supported; big_pos_gap compares their
##   medians (a well-placed big ship should survive much longer).
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom.)
##
## WHO USES IT: tests/fun_probe.gd calls tick() every tick, on_death() for
## every pilot ship death, and merges results() into FUN_JSON.

## Helper maths (median, ratio).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## A hit more than this many seconds after the previous one starts a new
## chain.
const CHAIN_GAP := 4.0
## A small-ship death with a TTK under this (seconds) is a "burst" death.
const BURST := 1.5
## The "is anyone with me?" radius for big ships (world units).
const SUPPORT_RANGE := 3000.0
## Fewer friendly minions than this within SUPPORT_RANGE (and no friendly
## pilot ship) = isolated.
const SUPPORT_MINIONS := 3

## Each live ship's last hit seen (ship uid -> match seconds).
var _last_hit := {}
## Each live ship's current chain start (ship uid -> match seconds).
var _chain := {}
## Big ships: isolated at the start of the current chain (uid -> bool).
var _isolated := {}
## TTKs (seconds) of small pilot ships (scouts, fighters, lances, bombers).
var ttk_small: Array = []
## TTKs (seconds) of big pilot ships that were isolated at chain start.
var ttk_big_iso: Array = []
## TTKs (seconds) of big pilot ships that had support at chain start.
var ttk_big_sup: Array = []


## Every tick: for each live pilot ship, did a hit land since we last
## looked? If so, and the previous hit is more than 4 s old, a new chain
## starts (and a big ship's isolation is noted).
func tick(world: World) -> void:
	for s: Ship in world.ships:
		if not s.alive:
			continue
		var lt := s.last_damage_time
		var prev := float(_last_hit.get(s.uid, -999.0))
		if lt > prev:
			if lt - prev > CHAIN_GAP:
				_start_chain(world, s, lt)
			_last_hit[s.uid] = lt


## Start a new damage chain for ship `s` at time `t` (seconds); a big ship
## also notes whether it is isolated right now.
func _start_chain(world: World, s: Ship, t: float) -> void:
	_chain[s.uid] = t
	if s.size_class >= Rules.SIZE_LARGE:
		_isolated[s.uid] = _is_isolated(world, s)


## Is big ship `s` alone: no friendly pilot ship and fewer than 3 friendly
## minions within 3,000 world units?
func _is_isolated(world: World, s: Ship) -> bool:
	# Step 1: any friendly pilot ship close by means support.
	for o: Ship in world.ships:
		if o != s and o.alive and o.team == s.team and o.global_position.distance_to(s.global_position) <= SUPPORT_RANGE:
			return false
	# Step 2: count friendly minions close by.
	var n := 0
	for m: Minion in world.minions:
		if m.alive and m.team == s.team and m.global_position.distance_to(s.global_position) <= SUPPORT_RANGE:
			n += 1
			if n >= SUPPORT_MINIONS:
				return false
	return true


## Pilot ship `s` just died (called from the kill event). Work out its TTK
## (seconds), file it by size, forget the ship, and return the TTK.
func on_death(world: World, s: Ship) -> float:
	var now := world.time
	# Step 1: the killing hit landed this tick, so tick() hasn't seen it:
	# if it came more than 4 s after the last hit we saw, it starts (and
	# ends) a chain of its own.
	var lt := s.last_damage_time
	var prev := float(_last_hit.get(s.uid, -999.0))
	if lt > prev and lt - prev > CHAIN_GAP:
		_start_chain(world, s, lt)
	var start := float(_chain.get(s.uid, now))
	var ttk := maxf(0.0, now - start)
	# Step 2: file the TTK by the ship's size.
	if s.size_class == Rules.SIZE_SMALL:
		ttk_small.append(ttk)
	elif s.size_class >= Rules.SIZE_LARGE:
		if bool(_isolated.get(s.uid, false)):
			ttk_big_iso.append(ttk)
		else:
			ttk_big_sup.append(ttk)
	# Step 3: forget the dead ship.
	_last_hit.erase(s.uid)
	_chain.erase(s.uid)
	_isolated.erase(s.uid)
	return ttk


## Everything this part measured, for FUN_JSON.
func results() -> Dictionary:
	# The share of small-ship deaths that were "bursts" (TTK under 1.5 s).
	var bursts := 0
	for t: float in ttk_small:
		if t < BURST:
			bursts += 1
	# big_pos_gap: isolated median / supported median (needs both).
	var mi: Variant = FunStats.median(ttk_big_iso)
	var ms: Variant = FunStats.median(ttk_big_sup)
	var gap: Variant = null
	if typeof(mi) != TYPE_NIL and typeof(ms) != TYPE_NIL and float(ms) > 0.0:
		gap = float(mi) / float(ms)
	return {
		"ttk_small_med_s": FunStats.snap(FunStats.median(ttk_small), 0.01),
		"burst_death_share_small": FunStats.snap(FunStats.ratio(float(bursts), float(ttk_small.size())), 0.001),
		"ttk_small_n": ttk_small.size(),
		"ttk_big_isolated": FunStats.snap_all(ttk_big_iso, 0.1),
		"ttk_big_supported": FunStats.snap_all(ttk_big_sup, 0.1),
		"big_pos_gap": FunStats.snap(gap, 0.001),
	}
