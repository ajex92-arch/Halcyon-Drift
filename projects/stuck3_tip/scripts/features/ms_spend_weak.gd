class_name MsSpendWeakFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C8, "the mothership weakens
## after big spends" (variant ms_spend_weak:on). REQ-CHANGE: the user's
## requirement "the mothership should no longer become weaker after large
## treasury spends" is reversed here, because this was the original brief's
## rule. It is built so it can be measured, and it stays switchable.
##
## HOW IT WORKS: it keeps a list of every spend from a team's treasury
## (TeamState.spend_hook). When 2,000 credits or more were spent in the
## last 60 s, that team's mothership takes MORE damage: it gets an
## incoming-damage multiplier (Unit.incoming_mults["spend"]) of
## 1 + 0.15 x (spent / 2,000), at most 1.45. The multiplier fades away in
## a straight line over 90 s; a new big spend starts it again at the new
## (higher) strength. The respawn strain rule is not changed. The AI
## admiral is NOT told about the rule (so the penalty really bites): its
## spending is unchanged. Counted in Game.usage as "weak_windows" (times the
## penalty started from nothing) and "weak_seconds" (seconds a mothership
## spent weakened, both teams added).
##
## WHO USES IT: FeatureRegistry installs it for --variant=ms_spend_weak:on.

## The variant key.
const KEY := "ms_spend_weak"
## The rolling window, in seconds.
const WINDOW := 60.0
## Spending this much (credits) in the window starts the penalty.
const THRESHOLD := 2000.0
## The multiplier grows this much per THRESHOLD of spending.
const PER_THRESHOLD := 0.15
## The multiplier never goes above this.
const MAX_MULT := 1.45
## The penalty fades over this many seconds.
const FADE := 90.0

## The match.
var world: World
## Recent spends per team: lists of [match time, credits].
var spends: Array = [[], []]
## The multiplier each team's penalty started at (1 = none).
var peak := [1.0, 1.0]
## The match time each team's penalty started.
var started := [0.0, 0.0]
## Seconds not yet counted in Game.usage (it counts whole seconds).
var _carry := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	if Game.variant(KEY) != "on":
		push_warning("ms_spend_weak: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	for team in 2:
		var t := team
		w.teams[team].spend_hook = func(amount: float) -> void: _on_spend(t, amount)
	w.tick_hooks.append(_tick)


## Team `team` spent `amount` credits: write it down and, if the last 60 s
## of spending reach 2,000, start (or strengthen) the penalty.
func _on_spend(team: int, amount: float) -> void:
	var list: Array = spends[team]
	list.append([world.time, amount])
	# Add up the window.
	var total := 0.0
	var keep: Array = []
	for e: Array in list:
		if world.time - float(e[0]) <= WINDOW:
			total += float(e[1])
			keep.append(e)
	spends[team] = keep
	if total < THRESHOLD:
		return
	# A new penalty: a count when none was running, and the new peak.
	var now_mult := _mult(team)
	if now_mult <= 1.0:
		Game.count_usage("weak_windows")
	var new_peak := minf(MAX_MULT, 1.0 + PER_THRESHOLD * total / THRESHOLD)
	if new_peak > now_mult:
		peak[team] = new_peak
		started[team] = world.time


## The multiplier team `team`'s mothership has now (1 = none): the peak,
## fading in a straight line to 1 over FADE seconds.
func _mult(team: int) -> float:
	var k := 1.0 - (world.time - float(started[team])) / FADE
	if k <= 0.0:
		return 1.0
	return 1.0 + (float(peak[team]) - 1.0) * k


## World tick hook: put each mothership's multiplier on it, and count the
## weakened seconds.
func _tick(dt: float) -> void:
	for team in 2:
		var ms := world.mothership(team)
		if ms == null or not ms.alive:
			continue
		var m := _mult(team)
		if m > 1.0:
			ms.incoming_mults["spend"] = m
			_carry += dt
		else:
			ms.incoming_mults.erase("spend")
	if _carry >= 1.0:
		Game.count_usage("weak_seconds", int(_carry))
		_carry -= floorf(_carry)
