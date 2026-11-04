class_name MoraleFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C9, the push/morale meter
## (variant morale:on). DESIGN note for the user: the research rejected it,
## because stronger minions are the opposite of the minion-dominance fix;
## it is built so it can be measured, and it stays switchable.
##
## HOW IT WORKS: each team has a morale meter from 0 to 15. It goes up by 1
## for every enemy pilot ship destroyed and by 3 for every enemy turret
## destroyed, whoever did it, and falls by 1 every 20 s. Every minion a team
## launches gets hull and damage x(1 + 0.01 x meter) - up to +15% - against
## every target (as in Squadrons). The multiplier is fixed when the minion
## launches (a launch is noticed the tick it appears), so it is the meter at
## the start of the wave that counts. The damage part works through
## Combat.minion_scale_hook. The banner at the top of the screen shows both
## meters. The AI needs to do nothing: the meters follow the fights.
## Counted in Game.usage as "morale_waves" (waves launched with a meter
## above 0, one per team and 10 s) and "morale_minions" (minions
## strengthened).
##
## WHO USES IT: FeatureRegistry installs it for --variant=morale:on.

## The variant key.
const KEY := "morale"
## The meter never goes above this.
const CAP := 15.0
## Meter points for an enemy pilot ship destroyed.
const PILOT_KILL := 1.0
## Meter points for an enemy turret destroyed.
const TURRET_KILL := 3.0
## Seconds for the meter to fall by 1.
const DECAY_SECONDS := 20.0
## Each meter point adds this much hull and damage (0.01 = 1%).
const PER_POINT := 0.01
## Launches of one team within this many seconds count as one wave.
const WAVE_GAP := 10.0

## The match.
var world: World
## The meter of each team (index = team).
var meter := [0.0, 0.0]
## The highest minion id already looked at (new minions have a higher one).
var _last_uid := 0
## The match time of the last wave counted for each team.
var _wave_t := [-999.0, -999.0]
## Seconds until the banner is rewritten.
var _banner_t := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	if Game.variant(KEY) != "on":
		push_warning("morale: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	_last_uid = w.registry.last_uid
	Events.unit_killed.connect(_on_unit_killed)
	w.tick_hooks.append(_tick)
	MinionHookChain.add(w, _scale_hook)


## A unit died: pilot ships and turrets raise the OTHER team's meter.
func _on_unit_killed(unit: Node, _info: RefCounted) -> void:
	var u := unit as Unit
	if u == null or u.team > 1:
		return
	var enemy := 1 - u.team
	if u.kind == Unit.K_SHIP:
		meter[enemy] = minf(CAP, float(meter[enemy]) + PILOT_KILL)
	elif u.kind == Unit.K_TURRET:
		meter[enemy] = minf(CAP, float(meter[enemy]) + TURRET_KILL)


## World tick hook: let the meters fall, strengthen the minions that have
## just launched, and rewrite the banner.
func _tick(dt: float) -> void:
	# Step 1: the meters fall.
	for team in 2:
		meter[team] = maxf(0.0, float(meter[team]) - dt / DECAY_SECONDS)
	# Step 2: the new minions (ids above the last one seen).
	var top := _last_uid
	for m: Minion in world.minions:
		if m.uid <= _last_uid or not m.alive:
			continue
		top = maxi(top, m.uid)
		var mult := 1.0 + PER_POINT * float(meter[m.team])
		if mult <= 1.0:
			continue
		m.hull_max *= mult
		m.hull *= mult
		m.set_meta("morale_mult", mult)
		Game.count_usage("morale_minions")
		if world.time - float(_wave_t[m.team]) > WAVE_GAP:
			_wave_t[m.team] = world.time
			Game.count_usage("morale_waves")
	_last_uid = top
	# Step 3: the banner, twice a second.
	_banner_t -= dt
	if _banner_t <= 0.0:
		_banner_t = 0.5
		EconBanner.set_line(world, "morale", "MORALE   Halcyon %.0f   Cinder %.0f   (new waves +1%% hull and damage per point)" % [float(meter[0]), float(meter[1])])


## Combat.minion_scale_hook: a morale minion hits with its marked multiplier
## on top of its own strength. `scale` is the minion's own strength
## multiplier; `target` is not used (it counts against every target).
func _scale_hook(m: Minion, _target: Unit, scale: float) -> float:
	return scale * float(m.get_meta("morale_mult", 1.0))
