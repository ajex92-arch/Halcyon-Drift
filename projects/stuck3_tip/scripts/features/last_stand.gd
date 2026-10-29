class_name LastStandFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "retreat" rule variant's new
## value "last_stand" (docs/FUN_PLAN.md section 5, endgame_closure fork, idea
## B5). It replaces the mothership's once-per-match "systems failure" at 35%
## hull with a desperate defence that makes the final push a fight. It is an
## alternative to the ms_cap variant (and to the admiral fork's F3): at most
## one of them is meant to be adopted. REQ-CHANGE: none.
##
## HOW IT WORKS: the "retreat" variant has three values (Rules.VARIANT_
## DEFAULTS): "systems_failure" (the default, today's game), "none" and
## "last_stand". FeatureRegistry installs this module for every value except
## the default, so install() does NOTHING for "none". For "last_stand",
## MothershipRetreat does nothing either, and this module watches both
## motherships. The first time a mothership's hull is at 35% or less:
##   1. its shields refill to the maximum at once;
##   2. for 45 s its guns fire 1.5 times as fast (each gun's cooldown runs
##      1.5 times faster; ion beams rest 1.5 times shorter);
##   3. launching, respawning and shopping at it stay available, with the
##      normal timers and respawn strain;
##   4. after 45 s the mothership is "breached" for the rest of the match: it
##      takes x1.25 damage (unit.incoming_mults["last_stand"]).
## A feed line and the HUD banner (shown for 45 s to the human on that team)
## say what is happening. The AI needs no rule: the defenders fight under the
## raised guns (the existing defend call) and the besiegers see the shield
## come back. Each last stand is counted in Game.usage as "last_stands". The
## x1.5 is the constant GUN_FACTOR: retune it against tests/ms_duel.gd. The
## module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=retreat:last_stand
## and asks it for banner(); it runs through World.tick_hooks.

## The variant key this module belongs to.
const KEY := "retreat"
## The hull fraction at which the last stand starts (0.35 = 35%; the same as
## the systems failure's Structures.MOTHERSHIP "retreat_threshold").
const THRESHOLD := 0.35
## How long (seconds) the raised guns last.
const DURATION := 45.0
## How much faster the guns fire during the last stand (1.5 = +50%).
const GUN_FACTOR := 1.5
## Damage factor after the last stand ends, for the rest of the match.
const BREACHED_FACTOR := 1.25

## The world we belong to.
var world: World
## Seconds of last stand left on each mothership (0 = not running).
var left := [0.0, 0.0]
## True once the mothership of that team has had its last stand.
var used := [false, false]


## Switch the last stand on for match `w`. FeatureRegistry calls this once at
## match start; it does nothing when the value is "none" (or any value but
## "last_stand").
func install(w: World) -> void:
	if Game.variant(KEY) != "last_stand":
		return
	world = w
	w.tick_hooks.append(_tick)


## One tick of `dt` seconds (World.tick_hooks): start a last stand when a hull
## reaches the threshold, speed up the guns while it lasts and breach the
## mothership when it ends.
func _tick(dt: float) -> void:
	for t in 2:
		var ms := world.mothership(t)
		if ms == null or not ms.alive:
			continue
		# Step 1: the trigger, once per mothership.
		if not used[t] and ms.hull <= ms.hull_max * THRESHOLD:
			used[t] = true
			left[t] = DURATION
			ms.shields.fill()
			Events.feed.emit("The %s mothership makes its last stand: shields restored, guns firing faster!" % Rules.TEAM_NAMES[t], "info", -1)
			Events.cue.emit("warn", ms.global_position)
			Game.count_usage("last_stands")
		if left[t] <= 0.0:
			continue
		# Step 2: while it lasts, every gun's cooldown runs 0.5 x dt extra (so
		# the guns fire 1.5 times as fast); a resting ion beam rests shorter too.
		var extra := dt * (GUN_FACTOR - 1.0)
		for m: WeaponMount in ms.mounts:
			if m.cd > 0.0:
				m.cd -= extra
			if m.beam_off > 0.0:
				m.beam_off -= extra
		left[t] = maxf(0.0, left[t] - dt)
		# Step 3: the end of the last stand: the mothership is breached.
		if left[t] <= 0.0:
			ms.incoming_mults[KEY] = BREACHED_FACTOR
			Events.feed.emit("The %s mothership's last stand is over: its plating is breached." % Rules.TEAM_NAMES[t], "info", -1)


## The HUD banner for the human on `team`: [] for none, else [title, sub,
## tone]. Shown while a last stand runs on our mothership or the one we
## attack.
func banner(_w: World, team: int) -> Array:
	if left[team] > 0.0:
		return ["Last stand", "Our mothership's shields are back and its guns fire faster for %ds." % int(ceil(left[team])), "cinder"]
	if left[1 - team] > 0.0:
		return ["Last stand", "The enemy mothership is firing at full power for %ds: hold the line." % int(ceil(left[1 - team])), "amber"]
	return []
