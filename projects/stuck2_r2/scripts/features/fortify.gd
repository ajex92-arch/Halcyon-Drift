class_name FortifyFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "fortify" rule variant (fork
## admiral_command, idea F3 "Fortify"). The admiral gets one free button,
## Fortify: for 4 seconds every turret of the team and the team's mothership
## take only a fifth of the damage (x0.2). It is a panic button for the
## moment a siege is about to break the base, and it shows to BOTH teams as
## a shimmering ring around each fortified structure, so attackers know to
## hold fire or push through.
## (It is the alternative to the endgame fork's ideas B3 and B5; at most
## one of the three should merge, and the mothership duel test
## tests/ms_duel.gd is its gate: the same winners as without it.)
##
## HOW IT WORKS:
##   - The order "fortify" (CommandOrders; a button for a human admiral)
##     costs nothing and recharges for 150 s. It is ready again at once
##     when the team's FIRST inner turret (a turret at one of the ore nodes
##     nearest its mothership) is destroyed, once per team and match.
##   - Using it puts the multiplier 0.2 under the key "fortify" in the
##     incoming_mults of every live turret of the team and of its
##     mothership (Unit.incoming_mults; Combat multiplies every hit by it)
##     and takes it away 4 s later. Turrets built during those 4 s are not
##     covered.
##   - The AI admiral (a computer admiral only) uses it when its mothership
##     lost 4% of its hull or more in the last 5 s, or when one of its inner
##     turrets is under 30% hull with 2 or more enemy big ships (frigates or
##     capital ships) that the team can see within 3,000 of it.
## Usage counter: fortify_uses.
##
## WHO USES IT: FeatureRegistry installs it for --variant=fortify:on.

## The variant key this module belongs to.
const KEY := "fortify"
## The damage multiplier while fortified (0.2 = a fifth).
const DAMAGE_MULT := 0.2
## How long (seconds) the shield lasts.
const DURATION := 4.0
## The order's cooldown in seconds.
const COOLDOWN := 150.0
## AI trigger 1: the hull fraction (0..1) the mothership must lose within
## AI_WINDOW seconds.
const AI_MS_LOSS := 0.04
## AI trigger 1: the look-back window in seconds.
const AI_WINDOW := 5.0
## AI trigger 2: an inner turret below this hull fraction (0..1)...
const AI_TURRET_HULL := 0.30
## ...with at least this many enemy big ships (seen by the team)...
const AI_BIGS := 2
## ...within this distance of it (world units).
const AI_TURRET_RANGE := 3000.0
## The shimmer colour.
const SHIMMER := Color(0.55, 0.85, 1.0)

## The match this module runs in.
var world: World
## Per team: the match time when its fortify ends (0 = not fortified).
var until: Array = [0.0, 0.0]
## Per team: the units now carrying the fortify multiplier.
var fortified: Array = [[], []]
## Per team: true once its first inner turret was lost (the cooldown reset
## has been given).
var _first_inner_lost: Array = [false, false]
## Per team: the mothership's hull fraction, once a second, newest last
## (the last AI_WINDOW + 1 samples).
var _hull_log: Array = [[], []]
## Seconds until the next once-a-second look.
var _look_t := 1.0


## Plug Fortify into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	CommandOrders.add(world, {
		"id": "fortify", "label": "Fortify", "cost": 0.0, "cooldown": COOLDOWN,
		"needs_point": false, "color": SHIMMER,
		"hint": "Fortify: turrets and the mothership take x0.2 damage for %d s" % int(DURATION),
		"tip": "Free, %d s cooldown (ready again when your first inner turret falls). For %d s every friendly turret and the mothership take a fifth of the damage; both teams see the shimmer." % [int(COOLDOWN), int(DURATION)],
		"help": "Fortify (free, every %d s; ready again when your first inner turret is destroyed): for %d seconds all your turrets and your mothership take only a fifth of the damage. Both teams see a shimmering ring on them. Press it when a siege is about to break your base." % [int(COOLDOWN), int(DURATION)],
		"blocker": _blocker, "run": _run, "tag": _tag,
	})
	world.tick_hooks.append(_tick)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	world.tree_exiting.connect(func() -> void:
		if Events.turret_destroyed.is_connected(_on_turret_destroyed):
			Events.turret_destroyed.disconnect(_on_turret_destroyed))


## The order's own rule: the mothership must be alive, and not already
## fortified.
func _blocker(team: int, _p: Vector2) -> String:
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return "No mothership to fortify"
	if world.time < float(until[team]):
		return "Already fortified"
	return ""


## Carry out Fortify for `team`: put the multiplier on its turrets and
## mothership, mark them for both teams, and tell everyone.
func _run(team: int, _p: Vector2, _paid: float) -> void:
	var list: Array = []
	for tu: Turret in world.turrets:
		if tu.team == team and tu.alive:
			list.append(tu)
	var ms := world.mothership(team)
	list.append(ms)
	for u: Unit in list:
		u.incoming_mults["fortify"] = DAMAGE_MULT
		CommandOrders.add_mark(world, {"pos": u.global_position, "unit": u, "r": maxf(u.radius, 90.0) + 60.0, "col": SHIMMER,
			"until": world.time + DURATION, "teams": [0, 1], "kind": "shimmer"})
	fortified[team] = list
	until[team] = world.time + DURATION
	Events.feed.emit("The %s base is FORTIFIED for %d seconds!" % [Rules.TEAM_NAMES[team], int(DURATION)], "info", -1)
	Game.count_usage("fortify_uses")


## Top-bar tag: "FORTIFIED 3s" on the fortified team's name, for both teams.
func _tag(team: int, _viewer: int) -> String:
	var left := float(until[team]) - world.time
	return "FORTIFIED %ds" % int(ceil(left)) if left > 0.0 else ""


## A turret was destroyed (Events.turret_destroyed): the first INNER turret a
## team loses makes its Fortify ready again.
func _on_turret_destroyed(turret: Node, _by_team: int) -> void:
	var tu := turret as Turret
	if tu == null or tu.node == null or tu.node.node_kind != "inner":
		return
	if not bool(_first_inner_lost[tu.team]):
		_first_inner_lost[tu.team] = true
		CommandOrders.reset_cooldown(world, "fortify", tu.team)


## Every tick (a World.tick_hooks entry): end fortifies that ran out, and
## once a second let the computer admirals decide.
func _tick(dt: float) -> void:
	# Step 1: take the multiplier away when the time is up.
	for t in 2:
		if not (fortified[t] as Array).is_empty() and world.time >= float(until[t]):
			for u in fortified[t]:
				if is_instance_valid(u):
					(u as Unit).incoming_mults.erase("fortify")
			fortified[t] = []
	# Step 2: once a second, note the motherships' hulls and let the AI think.
	_look_t -= dt
	if _look_t > 0.0:
		return
	_look_t = 1.0
	for t in 2:
		var ms := world.mothership(t)
		var hulls: Array = _hull_log[t]
		hulls.append(ms.hull_frac() if ms != null else 0.0)
		if hulls.size() > int(AI_WINDOW) + 1:
			hulls.pop_front()
		if AdmiralWeak.ai_acts(world, t):
			_ai_think(t)


## The computer admiral of `team` decides whether to Fortify (see the list
## at the top).
func _ai_think(team: int) -> void:
	if CommandOrders.ready_in(world, "fortify", team) > 0.0 or world.time < float(until[team]):
		return
	var hulls: Array = _hull_log[team]
	var go := false
	# Trigger 1: the mothership lost 4% hull or more within the last 5 s.
	if hulls.size() > int(AI_WINDOW) and float(hulls[0]) - float(hulls[hulls.size() - 1]) >= AI_MS_LOSS:
		go = true
	# Trigger 2: an inner turret under 30% hull with 2+ enemy big ships near.
	if not go:
		for tu: Turret in world.turrets:
			if tu.team != team or not tu.alive or tu.node == null or tu.node.node_kind != "inner" or tu.hull_frac() >= AI_TURRET_HULL:
				continue
			var bigs := 0
			for s: Ship in world.ships:
				if s.team == 1 - team and s.alive and s.size_class >= Rules.SIZE_LARGE and s.visible_to(team) and s.global_position.distance_to(tu.global_position) <= AI_TURRET_RANGE:
					bigs += 1
			if bigs >= AI_BIGS:
				go = true
				break
	if go:
		CommandOrders.run(world, "fortify", team, Vector2.ZERO)
