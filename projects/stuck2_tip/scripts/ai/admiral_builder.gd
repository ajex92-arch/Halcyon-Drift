class_name AdmiralBuilder
extends RefCounted
## WHAT THIS IS: the part of the AI admiral that decides WHERE to build
## things: defence turrets at resource nodes, repair bays behind the lanes,
## and wards at jungle entrances.
##
## HOW IT WORKS: each function walks a list of spots in a fixed order and
## builds at the first good one (or, for guard_inner_nodes(), at every
## good one). The one exception: the first Crossing turret of more_turrets()
## goes to the Crossing where most of our own pilots and minions are. A few
## words:
##   - A "resource node" is an asteroid field with ore. "Inner" nodes sit
##     near one mothership (only that side may build there); "middle" nodes
##     are on the crossing in the centre of the map (either side may build).
##   - A "PD turret" (point defence) fires fast and shreds small craft. A
##     "torp turret" fires homing torpedoes at big ships; it needs the
##     Platform Missiles research and only fits at inner nodes.
##   - A "repair bay" flies out, anchors, and its drones heal our ships.
##   - A "ward" is a small drone that anchors and keeps watch, so our team
##     can see that spot.
## Every build goes through AdmiralCommand (world.command), the same checked
## orders a human admiral uses, so the AI can't cheat.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.builder) and its tick() calls
## these once a second, only when the money and timers allow it.

## How far (world units) from a Crossing a pilot ship or minion of ours still
## counts as "there" when the admiral picks the Crossing for its first turret
## (more_turrets()). The same 1,500-unit disc in which an enemy ship stops us
## from building at the node (TurretData.BUILD_CLEAR_RADIUS).
const CROSSING_PRESENCE_R := TurretData.BUILD_CLEAR_RADIUS

## The game world (nodes, bays, wards, the map and the AdmiralCommand).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (for points along a lane).
var lanes: AdmiralLanes
## A reusable list the spatial hash fills with nearby units (reusing one list
## avoids making a new one for every question; see _ours_near()).
var _scratch: Array = []


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## The ore nodes in the order the turret builders visit them: the map's own
## order (World.nodes), except under the "node_persist" variant
## (NodePersistFeature), where the node nearest our own mothership comes
## first, so a lost turret near home is rebuilt before a far one.
func _nodes_in_order() -> Array:
	if not world.features.is_empty() and world.features.has("node_persist"):
		return world.features["node_persist"].call("nodes_by_distance", team)
	return world.nodes


## Put a PD turret at each of our inner nodes that has no turret of ours
## yet, while we have 450 credits (the PD turret's price). This runs early
## in the admiral's think, before the tech plan, so the base gets its first
## defences first. It may build at several nodes in one go. A node whose
## turret was just destroyed is locked for 60 seconds
## (TurretData.REBUILD_LOCK, tuned "rebuild_lock"), and no turret may go up
## while enemy ships are close (ResourceNode.build_blocker): such a node is
## skipped until the command allows a build there again, instead of failing
## the same order every second.
func guard_inner_nodes(ts: TeamState) -> void:
	var cmd := world.command
	for n: ResourceNode in _nodes_in_order():
		if n.node_kind == "inner" and n.side == team and n.turret_count(team) == 0:
			if cmd.turret_blocker(team, n.node_id, "pd") != "":
				continue
			if ts.can_afford(450.0):
				cmd.build_turret(team, n.node_id, "pd")


## Build ONE more turret, when we have spare money. First choice: a PD
## turret at a middle node (a "Crossing") where we have none yet, if we have
## 750 credits. The Crossings hold the middle of the map, so they come before
## the extra turrets at home (user decision, 2026-10-17; before, they came
## after). The FIRST Crossing turret goes where our own ships are (user
## decision, 2026-10-18: "Where its ships are"); see _crossings_in_order().
## Second choice: a free slot at one of our inner nodes (a torp
## turret if that node already has a turret and we have the research, else a
## PD turret), keeping 300 credits left over. With `inner_only` (the weak
## admiral of the test option --admiral-ai=weak) the first choice is skipped.
func more_turrets(ts: TeamState, inner_only: bool = false) -> void:
	var cmd := world.command
	# Step 1: the middle nodes (not for a weak admiral).
	if not inner_only:
		for n in _crossings_in_order():
			# One turret per middle node: more turned the lane centres into
			# fortresses no wave could get past (playtest 2026-10-13).
			if n.node_kind == "middle" and n.turret_count(team) < 1:
				if cmd.turret_blocker(team, n.node_id, "pd") == "" and ts.can_afford(750.0):
					cmd.build_turret(team, n.node_id, "pd")
					return
	# Step 2: our inner nodes, in map order (the node_persist variant: nearest
	# our mothership first, see _nodes_in_order()).
	for n: ResourceNode in _nodes_in_order():
		if n.node_kind == "inner" and n.side == team and n.free_slot() >= 0:
			var ttype := "torp" if ts.turret_torp and n.turret_count(team) >= 1 else "pd"
			# Allowed here, and we can pay for it with 300 credits to spare?
			if cmd.turret_blocker(team, n.node_id, ttype) == "" and ts.can_afford(float(TurretData.TURRETS[ttype]["cost"]) + 300.0):
				cmd.build_turret(team, n.node_id, ttype)
				return


## The nodes to try for a Crossing turret, in order. Normally that is the
## map's own order (World.nodes). Only the FIRST Crossing turret differs:
## while we hold no Crossing, the allowed one (we have no turret there and
## AdmiralCommand.turret_blocker has no objection) with the most of our own
## pilots and minions within CROSSING_PRESENCE_R of it comes first, then the
## rest in map order. A tie keeps the earlier node in map order, and with none
## of our ships near any allowed Crossing the whole list stays in map order.
## Only the world as it is now decides: no random numbers.
func _crossings_in_order() -> Array:
	var first: ResourceNode = null
	var most := 0
	for n in world.nodes:
		if n.node_kind != "middle":
			continue
		if n.turret_count(team) >= 1:
			return world.nodes
		if world.command.turret_blocker(team, n.node_id, "pd") != "":
			continue
		var here := _ours_near(n.global_position)
		if here > most:
			first = n
			most = here
	if first == null:
		return world.nodes
	var order: Array = [first]
	for n in world.nodes:
		if n != first:
			order.append(n)
	return order


## How many of our live pilot ships and minions are within
## CROSSING_PRESENCE_R of point `p`. (The spatial hash may list units a little
## outside the circle, so the distance is checked.)
func _ours_near(p: Vector2) -> int:
	var count := 0
	for u: Unit in world.unit_hash.query(p, CROSSING_PRESENCE_R, _scratch):
		if u.alive and u.team == team and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(p) < CROSSING_PRESENCE_R:
			count += 1
	return count


## Launch one repair bay, if we are under the team limit
## (Structures.REPAIR_BAY "max_per_team", 3). It goes a third of the way
## down a lane from our base, beside the lane.
func place_bay() -> void:
	# Step 1: count our living bays; stop at the limit.
	var have := 0
	for b in world.bays:
		if b.team == team and b.alive:
			have += 1
	if have >= int(Structures.REPAIR_BAY["max_per_team"]):
		return
	# Step 2: try the lanes in the order mid, top, bot, and use the first
	# lane whose spot has no bay of ours yet. The spot is 900 units off the
	# lane line (up for mid and top, down for bot) so minions don't fight
	# over it.
	# The places to try: [lane, fraction of the lane]. Features that have a
	# bay_spots() function (Forward Redeploy, bayA) may change the list.
	var spots: Array = [["mid", 0.33], ["top", 0.33], ["bot", 0.33]]
	for f in world.features.values():
		if f.has_method("bay_spots"):
			spots = f.bay_spots(world, team, spots, lanes)
	for spot: Array in spots:
		var lane: String = spot[0]
		var p := lanes.lane_point(lane, float(spot[1]))
		p += Vector2(0, -900.0 if lane != "bot" else 900.0)
		# A bay of ours within 1,500 units already covers this spot.
		var covered := false
		for b in world.bays:
			if b.team == team and b.alive and b.anchor.distance_to(p) < 1500.0:
				covered = true
		# Bays only go in open space (a lane, the crossing or a base).
		if covered or not world.map.in_open_lane(p):
			continue
		world.command.deploy_bay(team, p)
		return


## Place one ward at a jungle entrance on our side of the map that has no
## ward of ours yet, if the spot is allowed (wards only go where our team
## can see right now). The ward goes on the lane end of the entrance path.
func place_ward() -> void:
	# Step 1: at the limit (Structures.WARD "max_per_team", 6), placing
	# another would just retire our oldest ward, so don't.
	var mine := 0
	for w in world.wards:
		if w.team == team and w.alive:
			mine += 1
	if mine >= int(Structures.WARD["max_per_team"]):
		return
	# Step 2: go through the jungle entrances. Which side owns an entrance
	# goes by its quarter of the map ("tl"/"bl" = Aurelian's left half,
	# "tr"/"br" = Vhorr's right half). Some entrances sit exactly on the
	# centre line, and each side has its own copy of those, so judging by
	# the x position alone would hand all of them to one team.
	for e: Dictionary in world.map.entrances:
		var p: Vector2 = e["lane"]
		var q: String = e["quad"]
		var ours := (q == "tl" or q == "bl") == (team == Rules.HALCYON)
		if not ours:
			continue
		# Step 3: skip it if one of our wards is already within 1,500 units.
		var taken := false
		for w in world.wards:
			if w.team == team and w.alive and w.anchor.distance_to(p) < 1500.0:
				taken = true
				break
		if taken:
			continue
		# Step 4: place it if the rules allow (we can see it, no asteroid).
		if world.command.ward_blocker(team, p) == "":
			world.command.place_ward(team, p)
			return
