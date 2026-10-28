class_name AttritionFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "attrition" rule variant: fleet
## attrition, the last resort against matches that never end (docs/FUN_PLAN.md
## section 5, endgame_closure fork, idea B4). REQ-CHANGE: none. It is equal
## for both sides and touches the "a lot of health" rule only after 40:00.
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "on"   at 38:00 a message in the news feed warns that supply lines are
##          failing. From 40:00 on, damage taken by BOTH motherships and by
##          ALL turrets is multiplied by (1 + 0.04 for every full minute past
##          40:00), at most 1.8, and the motherships' shields refill more
##          slowly: their refill speed is multiplied by max(0, 1 - 0.1 for
##          every minute past 40:00) (so it stops after 50:00). Pilots and
##          minions are unaffected.
## It uses the incoming-damage hook (unit.incoming_mults["attrition"]) and
## updates it once a second (new turrets get it at the next update). The
## shield refill is set on the shield object (ShieldZones.regen); research
## that finishes after 40:00 resets it, and the next update sets it again.
## The AI needs no rule: it simply plays on a battlefield where bases fall.
## Every second the attrition is on is counted in Game.usage as
## "attrition_seconds". The module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=attrition:on and
## runs it through World.tick_hooks.

## The variant key this module belongs to.
const KEY := "attrition"
## Match time (seconds) of the warning message: 38:00.
const WARN_TIME := 2280.0
## Match time (seconds) from which attrition works: 40:00.
const START_TIME := 2400.0
## Extra damage per full minute past START_TIME (0.04 = +4%).
const DAMAGE_PER_MIN := 0.04
## The most damage multiplier attrition ever gives.
const MAX_DAMAGE := 1.8
## Shield refill lost per minute past START_TIME (0.1 = 10%).
const REGEN_LOSS_PER_MIN := 0.1

## The world we belong to.
var world: World
## Seconds until the next once-a-second update.
var _t := 0.0
## Test-only: seconds the warning and start times are moved EARLIER by the
## command-line option --feature-time-shift=N (0 = off), so a short late-game
## test run can reach 40:00.
var _shift := 0.0
## True once the warning was sent.
var _warned := false
## Each mothership's normal shield refill speed (points per second),
## remembered when attrition starts: [Halcyon's, Cinder's] (0 = not yet).
var _base_regen := [0.0, 0.0]


## Switch attrition on for match `w`. FeatureRegistry calls this once at
## match start. An unknown value only gets a warning.
func install(w: World) -> void:
	if Game.variant(KEY) != "on":
		push_warning("attrition: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	world = w
	_shift = float(Game.opt("feature-time-shift", 0.0))
	w.tick_hooks.append(_tick)


## One tick of `dt` seconds (World.tick_hooks): once a second, send the
## warning or update the multipliers.
func _tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 1.0
	# Step 1: the warning at 38:00.
	if not _warned and world.time >= WARN_TIME - _shift:
		_warned = true
		Events.feed.emit("Supply lines are failing: from 40:00 on, motherships and turrets take more damage and shields refill slower.", "info", -1)
	if world.time < START_TIME - _shift:
		return
	# Step 2: how many full minutes past 40:00, and what they give.
	var minutes := floorf((world.time - (START_TIME - _shift)) / 60.0)
	var dmg := minf(MAX_DAMAGE, 1.0 + DAMAGE_PER_MIN * minutes)
	var regen := maxf(0.0, 1.0 - REGEN_LOSS_PER_MIN * minutes)
	# Step 3: both motherships take more damage and refill their shields
	# slower; every live turret takes more damage too.
	for t in 2:
		var ms := world.mothership(t)
		if ms == null or not ms.alive:
			continue
		ms.incoming_mults[KEY] = dmg
		if float(_base_regen[t]) <= 0.0:
			_base_regen[t] = ms.shields.regen
		ms.shields.regen = float(_base_regen[t]) * regen
	for turret: Turret in world.turrets:
		if turret.alive:
			turret.incoming_mults[KEY] = dmg
	Game.count_usage("attrition_seconds")
