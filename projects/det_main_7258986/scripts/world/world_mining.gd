class_name WorldMining
extends RefCounted
## WHAT THIS IS: the map knowledge mining drones need: which ore node is
## the best one to work, and where to unload the ore at home.
##
## HOW IT WORKS: best_node_for_drone() gives every ore node a score (lots
## of ore is good; a long trip home, crowding, enemy turrets and recent
## drone losses are bad) and picks the highest. Ore is unloaded beside the
## mothership (refineries are not in this build), at drop_off_point().
##
## WHO USES IT: World.best_node_for_drone(), World.drop_off_point() and
## World.drop_off_dist() forward here. MiningDrone calls them while it
## works (it picks a node when it sets off without orders, and flies home
## to the drop-off point); TeamState also calls best_node_for_drone().
## (These are "static" functions: they belong to the class itself and are
## called as WorldMining.something(world, ...), without making an object.)


## The ore node (its id) a mining drone of `team` at `from` should work,
## or "" if no node qualifies. Every node gets a score:
##   + its ore (counted up to 2000) x 0.06 x the node's value
##   - the haul (node to drop-off point, world units) x 0.012
##   - 22 for each of our drones already working there
##   - 120 if the enemy holds the node (has a live turret there)
##   - 45 for each of our drones lost there in the last 150 s
##   - the distance from the drone x 0.001 (a tiny tie-breaker)
## Enemy inner nodes and nodes with under 80 ore left are skipped.
static func best_node_for_drone(w: World, team: int, from: Vector2) -> String:
	var best := ""
	var score := -INF
	for n in w.nodes:
		# Skip the enemy's inner nodes and nearly empty nodes.
		if n.node_kind == "inner" and n.side != team:
			continue
		var ore := n.total_ore()
		if ore < 80.0:
			continue
		# Is it enemy-held, and how many of our drones already work it?
		var holder := n.owner_team()
		var hostile := 1.0 if holder == Rules.enemy_of(team) else 0.0
		var working := 0
		for d in w.mining_drones:
			if d.team == team and d.node_id == n.node_id:
				working += 1
		# How far each load has to travel home.
		var haul := drop_off_point(w, team, n.global_position).distance_to(n.global_position)
		# Recent drone losses there count heavily (playtest: one team lost 30
		# drones by feeding them one at a time into the contested Crossing).
		var danger := float(w.teams[team].drone_danger(n.node_id, w.time))
		# Add it all up and keep the best.
		var s := minf(ore, 2000.0) * 0.06 * n.value - haul * 0.012 - float(working) * 22.0 - hostile * 120.0 - danger * 45.0 - from.distance_to(n.global_position) * 0.001
		if s > score:
			score = s
			best = n.node_id
	return best


## Where drones of `team` unload ore: the mothership (refineries are not
## in this build). The spot is a little behind the middle of the hull
## (30% of its half-length towards the back) and out to its right-hand
## (starboard) side: half the hull's width plus 80 world units. `_from`
## is not used.
static func drop_off_point(w: World, team: int, _from: Vector2) -> Vector2:
	var ms := w.mothership(team)
	var back := ms.global_position - Vector2.from_angle(ms.rotation) * (ms.half_len * 0.3)
	return back + Util.starboard_of(ms.rotation) * (ms.beam * 0.5 + 80.0)


## How far `from` is from the surface of `team`'s mothership hull (world
## units; negative when inside). A drone unloads once this is under 140
## (see MiningDrone). `from` is the drone's position.
static func drop_off_dist(w: World, team: int, from: Vector2) -> float:
	var ms := w.mothership(team)
	return ms.hull_dist(from)
