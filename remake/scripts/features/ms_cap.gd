class_name MsCapFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "ms_cap" rule variant: a cap on
## how fast a mothership's hull can be taken apart (docs/FUN_PLAN.md section
## 5, endgame_closure fork, idea B3). It turns a siege into several waves of
## pressure instead of a sudden kill or a limbo, because a siege that already
## hurt the hull a lot has to wait for the plating to "hold" less.
##
## HOW IT WORKS: the variant has two values besides "off" (the default):
##   "on"     once a mothership has lost more than 12% of its maximum hull in
##            the last 60 seconds, every hit on its hull does x0.5 damage
##            until the 60-second total is back under 12%. Not gated by
##            anything else; it must pass the ms_duel gate (same winners,
##            upgraded wins end with at most 40% hull left).
##   "full"   the same, but x0.1 (an almost hard cap). Its ms_duel result is
##            reported, not blocking. REQ-CHANGE: "a lot of health" / the
##            "barely" tuning is at risk.
## It uses the incoming-damage hook: each tick it measures how much hull each
## mothership lost since the last tick, keeps the last 60 seconds of losses
## (60 one-second buckets) and, while the total is over the limit AND the
## shield is down, sets  mothership.incoming_mults["ms_cap"]  to 0.5 (or
## 0.1); otherwise it takes the entry away. (While shields are up the factor
## is not applied: shields and the point-defence stay as they are, and, while
## the damage modifiers are kept, so do the x2.0 large and capital multiplier
## and the point-defence weakness.) The AI admiral's stall rule
## scales with it: siege_stall_frac drops from 15% to 10% (the cap makes the
## hull fall slower, so a siege that still bites must not be called off),
## unless another feature already set it. For a human viewer the banner says
## "Plating holding" while the cap works on our own mothership or on the one
## we attack, and a feed line says so the first time.
## Every second the cap is working is counted in Game.usage as
## "ms_cap_seconds". The module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=ms_cap:on or
## ms_cap:full, ticks it through World.tick_hooks and asks it for banner().

## The variant key this module belongs to.
const KEY := "ms_cap"
## The share of the maximum hull that may be lost in the window before the
## cap starts (0.12 = 12%).
const LIMIT := 0.12
## The window (seconds) the losses are added up over.
const WINDOW := 60
## Damage factor while capped: "on".
const FACTOR_ON := 0.5
## Damage factor while capped: "full".
const FACTOR_FULL := 0.1
## The stall rule's hull fraction while this module is on (see
## AdmiralSiege.STALL_FRAC, normally 0.15).
const STALL_FRAC := 0.10

## The world we belong to.
var world: World
## The damage factor of the chosen value (0.5 or 0.1).
var factor := FACTOR_ON
## Hull points each mothership had at the last tick (so the loss since then
## can be measured), by team.
var _last_hull := [0.0, 0.0]
## Hull points lost in the current (unfinished) second, by team.
var _bucket := [0.0, 0.0]
## The last WINDOW seconds' losses, a ring of one-second buckets, by team.
var _ring: Array = [[], []]
## Seconds into the current bucket.
var _sec := 0.0
## True while the cap works on the mothership of that team.
var capped := [false, false]
## The message "plating holding" has been sent once per team.
var _told := [false, false]


## Switch the cap on for match `w`. FeatureRegistry calls this once at match
## start. An unknown value only gets a warning.
func install(w: World) -> void:
	var value := Game.variant(KEY)
	if value != "on" and value != "full":
		push_warning("ms_cap: unknown value \"%s\" (use off, on or full); nothing changed" % value)
		return
	world = w
	factor = FACTOR_FULL if value == "full" else FACTOR_ON
	for t in 2:
		_last_hull[t] = w.mothership(t).hull
		_ring[t] = []
	# The stall rule scales with the cap (only if nobody else set it).
	if not Game.tunables.has("siege_stall_frac"):
		Game.tunables["siege_stall_frac"] = STALL_FRAC
	w.tick_hooks.append(_tick)


## One tick of `dt` seconds (World.tick_hooks): measure each mothership's hull
## loss, keep the 60-second total and set or clear the damage factor.
func _tick(dt: float) -> void:
	# Step 1: add up this tick's hull loss (a gain, such as the old systems
	# failure's lift, counts as 0).
	for t in 2:
		var ms := world.mothership(t)
		if ms == null or not ms.alive:
			continue
		_bucket[t] += maxf(0.0, _last_hull[t] - ms.hull)
		_last_hull[t] = ms.hull
	# Step 2: every second close the bucket into the ring (60 buckets).
	_sec += dt
	var second := false
	if _sec >= 1.0:
		_sec -= 1.0
		second = true
		for t in 2:
			(_ring[t] as Array).append(_bucket[t])
			_bucket[t] = 0.0
			if (_ring[t] as Array).size() > WINDOW:
				(_ring[t] as Array).pop_front()
	# Step 3: set or clear the factor on each mothership from the total.
	for t in 2:
		var ms := world.mothership(t)
		if ms == null or not ms.alive:
			continue
		var total: float = _bucket[t]
		for x: float in _ring[t]:
			total += x
		var over := total > LIMIT * ms.hull_max and ms.shield_total() <= 0.0
		if over:
			ms.incoming_mults[KEY] = factor
			if second:
				Game.count_usage("ms_cap_seconds")
			if not _told[t]:
				_told[t] = true
				Events.feed.emit("The %s mothership's plating is holding: its hull is falling slower." % Rules.TEAM_NAMES[t], "info", -1)
		else:
			ms.incoming_mults.erase(KEY)
		capped[t] = over


## The HUD banner for the human on `team`: [] for none, else [title, sub,
## tone]. Shown while the cap works on our mothership or on the one we attack.
func banner(_w: World, team: int) -> Array:
	if capped[team]:
		return ["Plating holding", "Our mothership's hull is taking less damage for now.", "veil"]
	if capped[1 - team]:
		return ["Plating holding", "The enemy mothership's plating is absorbing the assault: keep the pressure on.", "amber"]
	return []
