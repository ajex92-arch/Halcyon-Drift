class_name PilotMiningFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C7, pilots mining (variants
## pilot_mining:hold and pilot_mining:extractor). REQ-CHANGE: it breaks two
## of the user's requirements - "resource nodes should not be able to be
## mined by players at hardpoints" and "remove pilot independent
## extractors". It is built as an opt-in variant so it can be measured. FLAG
## for the user: the extractor is a repeatable money sink (500 credits each
## time it is rebuilt).
##
## HOW IT WORKS: two values.
##   hold      A pilot ship that is slower than 40 world units per second,
##             within 400 of an ore node, with no enemy pilot ship within
##             2,500, earns 5 credits per second. After 600 credits from one
##             visit the node is dry for that pilot for 120 s.
##   extractor A pilot within 600 of a node that has no extractor pays 500
##             credits to anchor a personal extractor there (PilotExtractor;
##             at most one per pilot; 600 hull; it pays its owner 3 credits
##             per second; the enemy pilot who destroys it gets 150).
## The AI uses both. A flying AI pilot in the lane or jungle state that is
## idle (not fighting, no enemy within 2,500, flying slowly) and within
## 3,000 of a node flies to it. With "hold" it goes to a node that is not
## dry for it and waits there. With "extractor" it goes only when its
## credits minus its 120-credit shopping reserve exceed 800 and it has no
## extractor, builds one at the node and goes back to work. It gives up
## the trip when an enemy shows up (and with "extractor" a healthy pilot with
## nothing but minions to shoot attacks any enemy extractor its team can see
## within 3,000, for the 150-credit bounty), its hull falls under 50%, its team
## is defending or besieging, or the node runs dry. Counted in Game.usage
## as "pilot_mining_seconds" (hold), "extractors_built", "extractor_credits",
## "extractor_hunts" (AI pilots that set out to destroy an enemy extractor) and
## "extractors_killed". A human flying onto a node earns the same hold
## pay; a human has no button for the extractor (not wired).
##
## WHO USES IT: FeatureRegistry installs it for --variant=pilot_mining:hold
## or pilot_mining:extractor.

## The variant key.
const KEY := "pilot_mining"
## A holding ship must be slower than this (world units per second).
const HOLD_SPEED := 40.0
## ...and within this many world units of a node.
const HOLD_RANGE := 400.0
## ...with no enemy pilot ship within this many world units.
const ENEMY_RANGE := 2500.0
## Credits per second while holding.
const HOLD_PAY := 5.0
## Credits one visit pays before the node is dry for that pilot.
const VISIT_CAP := 600.0
## Seconds the node stays dry for that pilot.
const DRY_TIME := 120.0
## What an extractor costs, in credits.
const EXTRACTOR_COST := 500.0
## A pilot must be within this many world units of the node to build one.
const BUILD_RANGE := 600.0
## The AI builds when credits minus the reserve exceed this.
const AI_BUILD_MARGIN := 800.0
## The AI's shopping reserve (PilotShopping.shop), in credits.
const AI_RESERVE := 120.0
## An idle AI pilot looks for a node this near, in world units.
const AI_SEEK := 3000.0
## The pay is worked out in steps of this many seconds.
const STEP := 0.25
## The bounty for destroying an extractor, in credits.
const EXTRACTOR_BOUNTY := 150.0
## An AI pilot's trip to a node is given up after this many seconds.
const AI_TRIP_MAX := 150.0

## The match.
var world: World
## True for pilot_mining:hold, false for pilot_mining:extractor.
var hold := true
## What each pilot has earned on the current visit: PilotProfile ->
## {node id -> credits}.
var visit := {}
## Until when each node is dry for each pilot: PilotProfile -> {node id ->
## match time}.
var dry := {}
## Each pilot's live extractor: PilotProfile -> PilotExtractor.
var extractors := {}
## The AI pilots now on a trip to a node: PilotProfile -> [node id, match
## time the trip began].
var trips := {}
## The AI pilots now attacking an enemy extractor: PilotProfile -> true (so
## each attack is counted once).
var hunting := {}
## Seconds until the next pay step.
var _t := 0.0
## Holding seconds not yet counted in Game.usage.
var _carry := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	if value != "hold" and value != "extractor":
		push_warning("pilot_mining: unknown value \"%s\" (use off, hold or extractor); nothing changed" % value)
		return
	hold = value == "hold"
	w.pilot_think_hooks.append(_ai_think)
	if hold:
		w.tick_hooks.append(_tick)
	else:
		Events.unit_killed.connect(_on_unit_killed)


# --- hold ------------------------------------------------------------------------------

## World tick hook (hold): every STEP seconds pay each ship that is holding
## on a node.
func _tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t += STEP
	for s: Ship in world.ships:
		if not s.alive or s.profile == null or s.velocity.length() >= HOLD_SPEED:
			continue
		var n := node_under(s)
		if n == null or is_dry(s.profile, n.node_id) or enemy_pilot_near(s):
			continue
		# Pay, count the visit, and run the node dry for this pilot at 600.
		var p := s.profile
		p.earn_quietly(HOLD_PAY * STEP)
		_carry += STEP
		var v: Dictionary = visit.get(p, {})
		v[n.node_id] = float(v.get(n.node_id, 0.0)) + HOLD_PAY * STEP
		visit[p] = v
		if float(v[n.node_id]) >= VISIT_CAP:
			v[n.node_id] = 0.0
			var d: Dictionary = dry.get(p, {})
			d[n.node_id] = world.time + DRY_TIME
			dry[p] = d
	if _carry >= 1.0:
		Game.count_usage("pilot_mining_seconds", int(_carry))
		_carry -= floorf(_carry)


## The ore node within 400 of ship `s`, or null.
func node_under(s: Ship) -> ResourceNode:
	for n: ResourceNode in world.nodes:
		if n.global_position.distance_to(s.global_position) < HOLD_RANGE:
			return n
	return null


## Is node `node_id` dry for pilot `p` (they took 600 there lately)?
func is_dry(p: PilotProfile, node_id: String) -> bool:
	var d: Dictionary = dry.get(p, {})
	return world.time < float(d.get(node_id, -1.0))


## Is a live enemy pilot ship within 2,500 of ship `s`?
func enemy_pilot_near(s: Ship) -> bool:
	for o: Ship in world.ships:
		if o.alive and o.team != s.team and o.global_position.distance_to(s.global_position) < ENEMY_RANGE:
			return true
	return false


# --- extractor -------------------------------------------------------------------------

## Why pilot `p` cannot anchor an extractor at node `n` now, or "" if they
## can: a flying ship within 600, no extractor of theirs standing, no
## extractor on the node, and 500 credits.
func build_blocker(p: PilotProfile, n: ResourceNode) -> String:
	if p.ship == null or not is_instance_valid(p.ship) or not p.ship.alive:
		return "You must be flying to anchor an extractor"
	if p.ship.global_position.distance_to(n.global_position) > BUILD_RANGE:
		return "Fly closer to the ore node"
	if extractors.has(p) and is_instance_valid(extractors[p]) and (extractors[p] as PilotExtractor).alive:
		return "You already have an extractor"
	if node_taken(n):
		return "That node already has an extractor"
	if p.credits < EXTRACTOR_COST:
		return "Not enough credits (%d short)" % int(ceil(EXTRACTOR_COST - p.credits))
	return ""


## Does node `n` already carry a live extractor (anyone's)?
func node_taken(n: ResourceNode) -> bool:
	for e in extractors.values():
		if is_instance_valid(e) and (e as PilotExtractor).alive and (e as PilotExtractor).node == n:
			return true
	return false


## Pilot `p` pays 500 credits and anchors an extractor at node `n`. Returns
## "" or why not.
func build_extractor(p: PilotProfile, n: ResourceNode) -> String:
	var b := build_blocker(p, n)
	if b != "":
		return b
	p.credits -= EXTRACTOR_COST
	var e := PilotExtractor.new()
	world.registry.attach(e)
	e.setup(world, p, n)
	world.registry.index(e)
	extractors[p] = e
	Game.count_usage("extractors_built")
	return ""


## A unit died (extractor mode): the enemy pilot who destroyed an extractor
## gets 150 credits.
func _on_unit_killed(unit: Node, info: RefCounted) -> void:
	var e := unit as PilotExtractor
	if e == null:
		return
	var killer := (info as DamageInfo).source_profile as PilotProfile
	if killer != null and killer.team != e.team:
		killer.earn(EXTRACTOR_BOUNTY, "extractor")
		Game.count_usage("extractors_killed")


# --- the AI ----------------------------------------------------------------------------

## World.pilot_think_hooks entry: an idle AI pilot flies to a node near it
## (see HOW IT WORKS), and with "extractor" builds there.
func _ai_think(ship: Ship, brain: PilotAI) -> void:
	var p := brain.profile
	var ts: TeamState = world.teams[ship.team]
	# Step 0 (extractor): an enemy extractor in sight is worth 150 credits, so
	# a healthy pilot with nothing better to shoot attacks it.
	if not hold and _hunt_extractor(ship, brain):
		return
	# Step 1: a trip already under way: keep going unless something is wrong.
	if trips.has(p):
		var trip: Array = trips[p]
		var n := world.node_by_id(String(trip[0]))
		if n == null or not _trip_ok(ship, brain, ts, p, n) or world.time - float(trip[1]) > AI_TRIP_MAX:
			trips.erase(p)
			return
		_go(ship, brain, p, n)
		return
	# Step 2: start a trip only when idle: in the lane or jungle state,
	# nothing to shoot, nothing near, flying slowly.
	if (brain.state != "lane" and brain.state != "jungle") or brain.target != null:
		return
	if ship.velocity.length() >= 0.4 * ship.f_max or ship.hull_frac() < 0.5 or brain.fallback_t > 0.0 or brain.evade_t > 0.0:
		return
	if ts.defending(world.time) or (ts.siege_lane != "" and (not ship.is_small() or ship.hull_id == "bomber")):
		return
	if world.any_enemy_ship_near(ship.global_position, ENEMY_RANGE, ship.team):
		return
	# Step 3: the nearest node that suits the mode, within 3,000.
	var best: ResourceNode = null
	var best_d := AI_SEEK
	for n: ResourceNode in world.nodes:
		var d := n.global_position.distance_to(ship.global_position)
		if d >= best_d or not _node_wanted(p, n):
			continue
		best_d = d
		best = n
	if best != null:
		trips[p] = [best.node_id, world.time]
		_go(ship, brain, p, best)


## An AI pilot in the lane or jungle state, with at least 60% hull and
## nothing to shoot but minions (or nothing), attacks the nearest enemy
## extractor that its team can see within 3,000. Returns true when it set
## the target (then its goal is the usual standoff point).
func _hunt_extractor(ship: Ship, brain: PilotAI) -> bool:
	if (brain.state != "lane" and brain.state != "jungle") or ship.hull_frac() < 0.6:
		return false
	if brain.target != null and brain.target.kind != Unit.K_MINION and brain.target.kind != Unit.K_EXTRACTOR:
		return false
	var best: PilotExtractor = null
	var best_d := AI_SEEK
	for e in extractors.values():
		if not is_instance_valid(e):
			continue
		var x := e as PilotExtractor
		if x == null or not x.alive or x.team == ship.team or not x.visible_to(ship.team):
			continue
		var d := x.global_position.distance_to(ship.global_position)
		if d < best_d:
			best_d = d
			best = x
	if best == null:
		hunting.erase(brain.profile)
		return false
	brain.target = best
	brain.lock_target = best
	brain.intent = "push"
	brain.goal = PilotTargeting.standoff(ship, best, ship.global_position)
	if not hunting.has(brain.profile):
		hunting[brain.profile] = true
		Game.count_usage("extractor_hunts")
	return true


## Is node `n` worth a trip for AI pilot `p`? Hold: not dry for them.
## Extractor: free, and they hold more than 800 over the reserve and have
## no extractor.
func _node_wanted(p: PilotProfile, n: ResourceNode) -> bool:
	if hold:
		return not is_dry(p, n.node_id)
	if extractors.has(p) and is_instance_valid(extractors[p]) and (extractors[p] as PilotExtractor).alive:
		return false
	return p.credits - AI_RESERVE > AI_BUILD_MARGIN and not node_taken(n)


## Can the trip of `p` to node `n` go on?
func _trip_ok(ship: Ship, brain: PilotAI, ts: TeamState, p: PilotProfile, n: ResourceNode) -> bool:
	if (brain.state != "lane" and brain.state != "jungle") or ship.hull_frac() < 0.5 or ts.defending(world.time):
		return false
	if world.any_enemy_ship_near(ship.global_position, ENEMY_RANGE, ship.team):
		return false
	return _node_wanted(p, n)


## Fly AI pilot `p` to node `n` and, with "extractor", build when there.
func _go(ship: Ship, brain: PilotAI, p: PilotProfile, n: ResourceNode) -> void:
	brain.goal = n.global_position
	brain.target = null
	brain.lock_target = null
	brain.intent = ""
	if not hold and ship.global_position.distance_to(n.global_position) <= BUILD_RANGE * 0.8:
		if build_extractor(p, n) == "":
			trips.erase(p)
