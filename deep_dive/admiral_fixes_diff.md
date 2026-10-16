# Admiral fixes: code diff vs the base game (copy dd_admiral, switch --afix=name,name,...)

All fixes are OFF unless named in --afix (AdmiralPlan.afix(name), a static helper added to admiral_plan.gd).

Switches and verdicts (details and numbers: deepdive/admiral_findings.md):
- lane   (AD-1)  push_lane() compares the FRACTION of the lane            KEEP
- guard  (AD-8)  guard_inner_nodes() skips a node whose turret order is blocked   KEEP
- drone  (AD-5)  recount drones before Step 4, never order into a full queue      KEEP
- def    (AD-9)  TeamDefense radius 4,000 once the ms is >2,500 from home          KEEP (small)
- defs   (AD-9)  with a siege on, only a push within 2,500 of OUR hull drops it    KEEP
- sl     (AD-10) declare the siege on the lane the enemy ms is on                  KEEP (the big one)
- bayA   (AD-7)  repair bay at 0.22 of the lane instead of 0.33                   KEEP (optional)
- mmid / mmid2 (AD-13/14) park the mothership on mid (mmid: unless a siege; mmid2: always)  see findings
- NOT kept: def2 (radius 2,500, not measured), bayB (0.15, not measured), bayC (no bay can be placed at all), bayE (fewer bays alive: 1.5 vs 2.8)

## scripts/ai/admiral_ai.gd

```diff
--- base/scripts/ai/admiral_ai.gd
+++ fixed/scripts/ai/admiral_ai.gd
@@ -124,7 +124,9 @@
 	# to the drone limit (14). A drone costs 200 credits.
 	var drones := world.mining_drone_count(team) + ts.drone_queue.size()
 	var want_drones := mini(int(Structures.MINING_DRONE["max"]), 6 + int(world.time / 75.0))
-	if drones < maxi(4, int(want_drones * 0.6)) and ts.can_afford(200.0):
+	# (Fix "drone": not when the build queue is already full: that order
+	# only failed with "Drone build queue is full", every second.)
+	if drones < maxi(4, int(want_drones * 0.6)) and ts.can_afford(200.0) and not (AdmiralPlan.afix("drone") and ts.drone_queue.size() >= 6):
 		cmd.build_drone(team)
 	# Step 2: a first turret at each of our inner nodes comes next.
 	builder.guard_inner_nodes(ts)
@@ -143,7 +145,11 @@
 	# Step 4: spend spare money (the treasury minus half the plan's reserve).
 	# Another drone if we're under the target...
 	var spare := ts.treasury - reserve * 0.5
-	if drones < want_drones and spare > 200.0:
+	# DEEP-DIVE fix "drone" (AD-5): Step 1 may just have queued a drone;
+	# count again, so one think never queues two.
+	if AdmiralPlan.afix("drone"):
+		drones = world.mining_drone_count(team) + ts.drone_queue.size()
+	if drones < want_drones and spare > 200.0 and not (AdmiralPlan.afix("drone") and ts.drone_queue.size() >= 6):
 		cmd.build_drone(team)
 		spare -= 200.0
 	# ...one more turret with over 800 spare...
```

## scripts/ai/admiral_builder.gd

```diff
--- base/scripts/ai/admiral_builder.gd
+++ fixed/scripts/ai/admiral_builder.gd
@@ -46,6 +46,11 @@
 	var cmd := world.command
 	for n in world.nodes:
 		if n.node_kind == "inner" and n.side == team and n.turret_count(team) == 0:
+			# DEEP-DIVE fix "guard" (AD-8): a node whose turret was just
+			# destroyed is locked for 25-30 s (or enemy ships are close); the
+			# order failed every second. Skip the node while it is blocked.
+			if AdmiralPlan.afix("guard") and cmd.turret_blocker(team, n.node_id, "pd") != "":
+				continue
 			if ts.can_afford(450.0):
 				cmd.build_turret(team, n.node_id, "pd")
 
@@ -90,16 +95,42 @@
 	# lane whose spot has no bay of ours yet. The spot is 900 units off the
 	# lane line (up for mid and top, down for bot) so minions don't fight
 	# over it.
+	# DEEP-DIVE fix "bayA/bayB/bayC" (AD-7): 20 of 23 bays that died in the late
+	# runs were shot by enemy MINIONS (10-29 of them near, none of ours): the
+	# spot 0.33 down the lane, 900 off the line, is inside the corridor
+	# (half width 1,800) and inside minion aggro (1,000-1,350). bayA puts the
+	# bay at 0.22 of the lane, bayB at 0.15, bayC keeps 0.33 but 1,800 off the
+	# line (the corridor edge). With any of them, a spot the command would
+	# refuse (rock, no route) is skipped and the next lane is tried, instead
+	# of giving up after the first spot.
+	var frac := 0.33
+	var off := 900.0
+	var variant := AdmiralPlan.afix("bayA") or AdmiralPlan.afix("bayB") or AdmiralPlan.afix("bayC")
+	if AdmiralPlan.afix("bayA"):
+		frac = 0.22
+	elif AdmiralPlan.afix("bayB"):
+		frac = 0.15
+	if AdmiralPlan.afix("bayC"):
+		off = 1800.0
 	for lane: String in ["mid", "top", "bot"]:
-		var p := lanes.lane_point(lane, 0.33)
-		p += Vector2(0, -900.0 if lane != "bot" else 900.0)
+		var p := lanes.lane_point(lane, frac)
+		p += Vector2(0, -off if lane != "bot" else off)
 		# A bay of ours within 1,500 units already covers this spot.
 		var covered := false
 		for b in world.bays:
 			if b.team == team and b.alive and b.anchor.distance_to(p) < 1500.0:
 				covered = true
+		# bayE: only where our own wave is already past the spot (its furthest
+		# minion at least 0.1 of the lane beyond it). A bay behind our front
+		# is covered by the wave; on a lane we are losing it dies in ~40 s.
+		if AdmiralPlan.afix("bayE") and lanes.front_frac(lane) < frac + 0.1:
+			continue
+		if variant or AdmiralPlan.afix("bayE"):
+			# The command's own checks (rock, route) decide.
+			if covered or world.command.bay_blocker(team, p) != "":
+				continue
 		# Bays only go in open space (a lane, the crossing or a base).
-		if covered or not world.map.in_open_lane(p):
+		elif covered or not world.map.in_open_lane(p):
 			continue
 		world.command.deploy_bay(team, p)
 		return
```

## scripts/ai/admiral_lanes.gd

```diff
--- base/scripts/ai/admiral_lanes.gd
+++ fixed/scripts/ai/admiral_lanes.gd
@@ -38,10 +38,14 @@
 	for lane: String in MapLayout.LANE_ORDER:
 		# The lane's path as our team walks it: from our base outwards.
 		var pts := MapLayout.lane_points(lane, team)
+		# DEEP-DIVE fix "lane" (AD-1): top and bottom are ~44,200 long and mid
+		# ~33,600, so comparing distances in world units picked mid only 5-13%
+		# of the time; compare the fraction of the lane instead.
+		var lane_len := Util.polyline_length(pts) if AdmiralPlan.afix("lane") else 1.0
 		# Measure every living minion of ours that is on this lane.
 		for m in world.minions:
 			if m.team == team and m.alive and m.lane == lane:
-				var s: float = Util.project_on_polyline(m.global_position, pts)["s"]
+				var s: float = float(Util.project_on_polyline(m.global_position, pts)["s"]) / lane_len
 				if s > best_s:
 					best_s = s
 					best = lane
```

## scripts/ai/admiral_mothership_mover.gd

```diff
--- base/scripts/ai/admiral_mothership_mover.gd
+++ fixed/scripts/ai/admiral_mothership_mover.gd
@@ -63,6 +63,21 @@
 	if lanes.fleet_power(team) < lanes.fleet_power(1 - team):
 		return
 	var lane := ts.siege_lane if ts.siege_lane != "" else lanes.push_lane()
+	# DEEP-DIVE option "mmid": no siege, so park on the mid lane (the shortest,
+	# 33,600 against 44,200), not on the push lane. With the push lane both
+	# motherships were parked on different lanes (top against bottom, 30,000
+	# apart) in a normal match, so no siege ever met anything (seed 7: 341 s
+	# of assault, 4% hull damage).
+	if AdmiralPlan.afix("mmid") and ts.siege_lane == "":
+		lane = "mid"
+	# "mmid2": always mid, also during a siege. A siege on another lane (the
+	# enemy mothership still at home: fewest-turret lane; or it moved) sent
+	# our mothership 13,400 units to that lane, while the enemy's did the
+	# same towards ours: seed 7 (--afix=def,defs,sl,lane,guard,drone), team 0
+	# top->bot at 1201, bot->top at 1420, team 1 bot->top 1310, top->bot 1630,
+	# the two crossed and chased each other all match (contact 46 s).
+	if AdmiralPlan.afix("mmid2"):
+		lane = "mid"
 	if lane == "":
 		return
 	# Step 4: once it is up a lane (over 2,500 from home), only a siege moves
```

## scripts/ai/admiral_plan.gd

```diff
--- base/scripts/ai/admiral_plan.gd
+++ fixed/scripts/ai/admiral_plan.gd
@@ -80,3 +80,18 @@
 			continue
 		return {"kind": "t", "id": id, "cost": float(Tech.TECHS[id]["cost"])}
 	return {}
+
+## DEEP-DIVE switches for the admiral fixes: --afix=name,name,... (a comma
+## list). Every fix is OFF unless its name is listed, so with no --afix the
+## game is the base game. The names are read once.
+static var _afix_set: Dictionary = {}
+static var _afix_read := false
+
+
+## Is the admiral fix `fix_name` switched on (listed in --afix)?
+static func afix(fix_name: String) -> bool:
+	if not _afix_read:
+		_afix_read = true
+		for part in str(Game.opt("afix", "")).split(",", false):
+			_afix_set[part.strip_edges()] = true
+	return _afix_set.has(fix_name)
```

## scripts/ai/admiral_siege.gd

```diff
--- base/scripts/ai/admiral_siege.gd
+++ fixed/scripts/ai/admiral_siege.gd
@@ -95,6 +95,14 @@
 		if n < fewest:
 			fewest = n
 			best = lane
+	# DEEP-DIVE fix "sl": the enemy mothership is parked up a lane (it is,
+	# from 20:00 on). Siege that lane at once. Before, the lane with the
+	# fewest inner turrets (ties: top) was declared, the mothership mover
+	# sent OUR mothership 13,000 units up that lane in the same think (80
+	# units/s: ~170 s), and one second later the siege was re-aimed at the
+	# lane the enemy mothership is on (mid).
+	if AdmiralPlan.afix("sl") and ems2 != null and ems2.global_position.distance_to(world.map.mothership_pos[1 - team]) > 2500.0:
+		best = world.map.lane_for(ems2.global_position)
 	# Step 5: declare it and start gathering. (We return true below, so the
 	# waypoint moves at once.)
 	ts.siege_lane = best
```

## scripts/team/team_defense.gd

```diff
--- base/scripts/team/team_defense.gd
+++ fixed/scripts/team/team_defense.gd
@@ -31,6 +31,13 @@
 ## be to count as attacking the base. Our inner ore nodes are about 7,200
 ## (mid) and 12,100 (top and bottom) from the hull.
 const DEFEND_RADIUS := 7000.0
+## DEEP-DIVE fix "def": the radius while our mothership is parked away from
+## its home spot (over 2,500 from it): 4,000 ("def") or 2,500 ("def2").
+const FORWARD_DEFEND_RADIUS := 4000.0
+const FORWARD_DEFEND_RADIUS_2 := 2500.0
+## DEEP-DIVE fix "defs": while our siege is on, the push must be this close
+## to our hull (world units) to drop it.
+const SIEGE_DROP_RADIUS := 2500.0
 
 ## The team this part belongs to (we read and set its defend and siege
 ## fields). It is reached through a weak link: see `_ts_ref`.
@@ -86,10 +93,19 @@
 	var seen: Array[Vector2] = []
 	var lead := Vector2.INF
 	var lead_d := INF
+	# DEEP-DIVE fix "def" (AD-9): once our mothership has moved up a lane
+	# (from 20:00 the AI parks it 35% up), 7,000 from its hull reaches the
+	# middle of the map, so any fight there counted as "the base is under
+	# attack" for both teams, most of the time, and that cancelled every
+	# siege. Away from home, "under attack" now means close to the hull.
+	var radius := DEFEND_RADIUS
+	if AdmiralPlan.afix("def") or AdmiralPlan.afix("def2"):
+		if ms.global_position.distance_to(world.map.mothership_pos[team]) > 2500.0:
+			radius = FORWARD_DEFEND_RADIUS_2 if AdmiralPlan.afix("def2") else FORWARD_DEFEND_RADIUS
 	for s: Ship in world.ships:
 		if s.team != team and s.alive and s.size_class >= Rules.SIZE_LARGE and s.visible_to(team):
 			var d := ms.hull_dist(s.global_position)
-			if d < DEFEND_RADIUS:
+			if d < radius:
 				seen.append(s.global_position)
 				if d < lead_d:
 					lead_d = d
@@ -106,6 +122,14 @@
 	if threat < 2:
 		return
 	centre /= float(threat)
+	# DEEP-DIVE fix "defs" (AD-9): with a siege on, only a push right at our
+	# hull (SIEGE_DROP_RADIUS) sounds the alarm and drops the siege. Our
+	# siege fleet gathers about 3,000 from our own mothership once both
+	# motherships are parked mid, so the enemy fleet meeting it there was
+	# "an attack on the base" and cancelled the siege (and pulled every pilot
+	# off the siege goal, PilotGoals Step 6) within seconds.
+	if AdmiralPlan.afix("defs") and ts.siege_lane != "" and ms.hull_dist(centre) > SIEGE_DROP_RADIUS:
+		return
 	# Step 3: meet them where they are, 1,500 units from the middle of the
 	# push towards our mothership. (Playtest: a point at the hull left the
 	# whole team idling there while frigates took an inner turret 8,000 to
```

## tests (probe only, no game behaviour): tests/admiral_audit2.gd, tests/bay_spot_probe.gd (in notate\dd_admiral\tests)
