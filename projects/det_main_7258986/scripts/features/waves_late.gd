class_name WavesLateFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "waves_late" rule variant: fewer
## free minion waves late in the match (docs/FUN_PLAN.md section 5,
## endgame_closure fork, idea B9). REQ-CHANGE: the minions "spawn from the
## mothership regularly" (free waves). The paid minion control (Fleet
## Command) is not touched.
##
## HOW IT WORKS: the variant has two values besides "off" (the default):
##   "slow"   from 30:00 the gap between free waves doubles (35 s -> 70 s).
##   "none"   from 35:00 no new free wave is launched. Waves already out live
##            on and the ones already waiting in the launch queue still leave.
## It uses the tuned number "wave_interval" (MinionDirector reads it with
## Rules.tune each time a wave is queued) for "slow", and for "none" it
## pushes the director's next wave time out of reach. A tick hook (once per
## tick, cheap) starts it at the right moment. The AI needs no rule: waves
## are minions, and the pilots and the admiral play on with fewer of them.
## Every free wave that would have launched on the normal 35-second clock but
## did not is counted in Game.usage as "waves_skipped". The module draws no
## random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=waves_late:slow or
## waves_late:none and runs it through World.tick_hooks.

## The variant key this module belongs to.
const KEY := "waves_late"
## Match time (seconds) when "slow" starts: 30:00.
const SLOW_START := 1800.0
## Match time (seconds) when "none" starts: 35:00.
const NONE_START := 2100.0
## The slowed gap between waves (seconds): double the normal 35.
const SLOW_INTERVAL := 70.0

## The world we belong to.
var world: World
## True for "none", false for "slow".
var none := false
## True once the change has started.
var started := false
## The match time (seconds) when the change started.
var _t0 := 0.0
## Test-only: seconds the start times are moved EARLIER by the command-line
## option --feature-time-shift=N (0 = off), so a short late-game test run can
## reach 30:00 or 35:00.
var _shift := 0.0
## The director's next_wave at the last tick, to see when a real wave left.
var _seen_next := 0.0
## Waves that really launched since the change started.
var _real := 0
## Skipped waves already counted in Game.usage.
var _counted := 0


## Switch the wave change on for match `w`. FeatureRegistry calls this once
## at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	var value := Game.variant(KEY)
	if value != "slow" and value != "none":
		push_warning("waves_late: unknown value \"%s\" (use off, slow or none); nothing changed" % value)
		return
	world = w
	none = value == "none"
	_shift = float(Game.opt("feature-time-shift", 0.0))
	w.tick_hooks.append(_tick)


## One tick (World.tick_hooks): start the change when its time comes, then
## count the waves the normal clock would have sent.
func _tick(_dt: float) -> void:
	var director := world.minion_director
	# Step 1: the moment it starts.
	if not started:
		if world.time < (NONE_START if none else SLOW_START) - _shift:
			return
		started = true
		_t0 = world.time
		_seen_next = director.next_wave
		if none:
			# No further wave is ever due.
			director.next_wave = INF
			_seen_next = INF
		else:
			Game.tunables["wave_interval"] = SLOW_INTERVAL
		Events.feed.emit("Reinforcements are thinning out: the mothership launches %s." % ("no more minion waves" if none else "minion waves half as often"), "info", -1)
		return
	# Step 2: a real wave left (the director moved its next_wave on).
	if director.next_wave != _seen_next:
		_seen_next = director.next_wave
		_real += 1
	# Step 3: on the normal clock a wave was due every 35 s since the start;
	# the ones that did not really launch are skipped (counted once).
	var expected := int(floor((world.time - _t0) / Minions.WAVE_INTERVAL))
	var missing := expected - _real - _counted
	if missing > 0:
		_counted += missing
		Game.count_usage("waves_skipped", missing)