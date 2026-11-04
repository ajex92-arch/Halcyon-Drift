class_name AdmiralSinksFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "admiral_sinks" rule variant
## (fork admiral_command, the optional carry-over from the AI deep dive).
## After the AI admiral has finished its plan, its treasury piles up with
## nothing left to buy (treasuries of 4,000 to 38,000 credits in late
## matches). This variant gives the COMPUTER admiral two sinks:
##   - Fleet Command: whenever the treasury exceeds the Fleet Command
##     Module's price (2,000) by 2,000 more, and the module can be built
##     (the Capital Ship Facility stands), the AI builds it. From then on the
##     free minion waves of that team stop and AdmiralFleetCommand buys
##     minions with the team's money (up to Minions.control_cap() alive: 30
##     in the old rules, 60 in the standard rules through fleet_cap). The
##     mothership is not weakened by this spending.
##   - Ward refresh: while the treasury is over 3,000 the AI places a new
##     ward at one of its jungle entrances every 45 s, even when it already
##     has the 6 wards the limit allows (placing one more quietly retires
##     the oldest). Turrets cannot be re-queued: every slot at the nodes is
##     already full by then.
## Usage counters: fleet_command_built (the module finished) and
## sink_wards (wards placed by the refresh). For measuring the Fleet Command
## limit (the fleet_cap variant) it also counts, without changing anything in
## the match: fleet_built_s_t0 / fleet_built_s_t1 (the match second each
## team's module finished) and fleet_minions_bought (minions bought with
## Fleet Command by either admiral), fleet_bought_t0 / fleet_bought_t1 (the
## same per team).
## REQ-CHANGE: none. The value of the variant is "fleet".
##
## WHO USES IT: FeatureRegistry installs it for --variant=admiral_sinks:fleet.

## The variant key this module belongs to.
const KEY := "admiral_sinks"
## How far above the module's price the treasury must be (credits).
const MARGIN := 2000.0
## The treasury above which wards are refreshed (credits).
const WARD_TREASURY := 3000.0
## Seconds between two ward refreshes.
const WARD_EVERY := 45.0

## The match this module runs in.
var world: World
## Seconds until each team's next think (once a second, half a second apart).
var _think_t: Array = [1.0, 1.5]
## Per team: seconds until the next ward refresh.
var _ward_t: Array = [WARD_EVERY, WARD_EVERY]
## Per team: which of its entrances the next refresh tries first.
var _ward_i: Array = [0, 0]


## Plug the sinks into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	world.tick_hooks.append(_tick)
	Events.facility_done.connect(_on_facility_done)
	Events.admiral_result.connect(_on_admiral_result)
	world.tree_exiting.connect(func() -> void:
		if Events.facility_done.is_connected(_on_facility_done):
			Events.facility_done.disconnect(_on_facility_done)
		if Events.admiral_result.is_connected(_on_admiral_result):
			Events.admiral_result.disconnect(_on_admiral_result))


## Fleet Command finished (Events.facility_done): count it, and note the
## match second it finished at ("fleet_built_s_t0" / "fleet_built_s_t1").
func _on_facility_done(team: int, id: String) -> void:
	if id == "fleet":
		Game.count_usage("fleet_command_built")
		Game.count_usage("fleet_built_s_t%d" % team, int(world.time))


## An admiral command finished (Events.admiral_result): count each minion
## bought with Fleet Command ("fleet_minions_bought", and "fleet_bought_t0" /
## "fleet_bought_t1" per team). Counting only.
func _on_admiral_result(team: int, action: String, ok: bool, _message: String) -> void:
	if action == "minion" and ok:
		Game.count_usage("fleet_minions_bought")
		Game.count_usage("fleet_bought_t%d" % team)


## Every tick (a World.tick_hooks entry): the computer admirals think about
## their sinks once a second.
func _tick(dt: float) -> void:
	for t in 2:
		_think_t[t] = float(_think_t[t]) - dt
		if float(_think_t[t]) > 0.0 or not AdmiralWeak.ai_acts(world, t):
			continue
		_think_t[t] = 1.0
		_think(t)


## One think of team `team`'s computer admiral (see the top).
func _think(team: int) -> void:
	var ts := world.teams[team]
	# Sink 1: Fleet Command, once the treasury is rich enough.
	var cost := float(Tech.FACILITIES["fleet"]["cost"])
	if not ts.facilities.has("fleet") and not ts.is_building("fleet") and ts.treasury >= cost + MARGIN and ts.facility_blocker("fleet") == "":
		world.command.build_facility(team, "fleet")
	# Sink 2: a fresh ward at a jungle entrance, even at the 6-ward limit.
	_ward_t[team] = float(_ward_t[team]) - 1.0
	if float(_ward_t[team]) > 0.0 or ts.treasury < WARD_TREASURY:
		return
	_ward_t[team] = WARD_EVERY
	# Our entrances (the quarters on our side of the map), taken in turn.
	var mine: Array = []
	for e: Dictionary in world.map.entrances:
		var q: String = e["quad"]
		if (q == "tl" or q == "bl") == (team == Rules.HALCYON):
			mine.append(e["lane"])
	for k in mine.size():
		var p: Vector2 = mine[(int(_ward_i[team]) + k) % mine.size()]
		if world.command.ward_blocker(team, p) == "":
			_ward_i[team] = int(_ward_i[team]) + k + 1
			world.command.place_ward(team, p)
			Game.count_usage("sink_wards")
			return
