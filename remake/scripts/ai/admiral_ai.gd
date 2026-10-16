class_name AdmiralAI
extends RefCounted
## WHAT THIS IS: the computer "admiral" for one team. The admiral is the
## player who doesn't fly a ship: they spend the team's shared money (the
## "treasury") and give the big orders. DESIGN.md A14 describes the AI one.
## Everything it does goes through AdmiralCommand, so it plays by exactly
## the same rules as a human admiral.
##
## HOW IT WORKS: once a second it "thinks" and works down a to-do list, in
## this order (the order matters, because money spent early is gone for
## the later steps):
##   1. Mining drones come first. They mine ore, and delivered ore pays the
##      treasury and the pilots (Economy.deliver_ore), so a thin drone line
##      jumps every queue. The number it wants grows with match time.
##   2. A PD turret (point defence: a fast-firing defence gun) at each of
##      our inner nodes (the ore fields nearest our mothership) that has
##      none yet (AdmiralBuilder.guard_inner_nodes).
##   3. The next step of the build PLAN: facilities (modules built onto the
##      mothership) and research, bought as soon as we can afford them
##      (AdmiralPlan).
##   4. With money to spare: more drones, more turrets, repair bays behind
##      the lanes and wards (small watch drones) at jungle entrances
##      (AdmiralBuilder).
##   5. The team waypoint, a rally point on the lane we are pushing or on
##      the siege lane (AdmiralWaypoint).
##   6. After 20:00, sieges: attacks on the enemy mothership with our big
##      ships, the frigates and capital ships (AdmiralSiege).
##   7. After 20:00, moving our mothership up behind a winning push
##      (AdmiralMothershipMover).
##   8. Buying minions (small computer-flown lane ships), if we own the
##      Fleet Command Module (AdmiralFleetCommand).
##
## WHO USES IT: World makes one for each team whose admiral is the computer
## (World.admiral_ai, in World.setup) and calls tick() every physics frame
## while the match is being played.
## Its parts live next to it in scripts/ai/: admiral_plan.gd,
## admiral_lanes.gd, admiral_builder.gd, admiral_waypoint.gd,
## admiral_siege.gd, admiral_mothership_mover.gd and
## admiral_fleet_command.gd. (A "part" is a helper object that does one job
## for this admiral.) This file keeps the timers and the order of the to-do
## list; the parts do the work.
##
## Note for programmers: the parts are given the world, our team number and
## the shared AdmiralLanes helper, not a link back to this admiral. Two
## RefCounted objects that hold each other are never freed (a "reference
## cycle"), so a back-link would leak every admiral and its parts when a
## match ends.

## The build order, kept here under its old name. The real list (and the
## explanation) lives in AdmiralPlan.PLAN.
const PLAN := AdmiralPlan.PLAN
## How far ahead the plan may skip blocked steps; see AdmiralPlan.LOOKAHEAD.
const LOOKAHEAD := AdmiralPlan.LOOKAHEAD
## The minion buying order for Fleet Command; see
## AdmiralFleetCommand.FLEET_MIX.
const FLEET_MIX := AdmiralFleetCommand.FLEET_MIX

## The game world (all ships, nodes, teams and the AdmiralCommand).
var world: World
## Which team this admiral runs: 0 = Halcyon, 1 = Cinder.
var team := 0
## Seconds until the next think. The two teams start half a second apart
## (0.5 s and 1.0 s) so they don't think on the same frame, then each
## thinks once every 1.0 s.
var think_t := 1.0
## Seconds until we may try to place another ward (the first try after
## 30 s, then at most one try every 45 s).
var ward_t := 30.0
## Seconds until we re-place the team waypoint (first after 60 s, then
## every Rules.WAYPOINT_TIME = 75 s). Set to 0 when the siege starts,
## changes or ends (see _siege), to move the waypoint at the next think.
var waypoint_t := 60.0
## Seconds until we may try to launch another repair bay (at most one try
## every 40 s).
var bay_t := 0.0

## Our parts (see the list at the top), made once in _init().
## Questions about lanes and fleet strength (the other parts share it).
var lanes: AdmiralLanes
## Where turrets, repair bays and wards go.
var builder: AdmiralBuilder
## Where the team waypoint goes.
var waypoint: AdmiralWaypoint
## Late-game attacks on the enemy mothership.
var siege: AdmiralSiege
## Moving our own mothership after 20:00.
var mothership_mover: AdmiralMothershipMover
## Buying minions when we own Fleet Command.
var fleet: AdmiralFleetCommand


## Set up the admiral for team `t` in world `w`, and make its parts.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	think_t = 0.5 + float(t) * 0.5
	# The lane helper first: every other part is handed it.
	lanes = AdmiralLanes.new(w, t)
	builder = AdmiralBuilder.new(w, t, lanes)
	waypoint = AdmiralWaypoint.new(w, t, lanes)
	siege = AdmiralSiege.new(w, t, lanes)
	mothership_mover = AdmiralMothershipMover.new(w, t, lanes)
	fleet = AdmiralFleetCommand.new(w, t, lanes)


## Called by World every physics frame (a "tick": one small step of game
## time, 60 a second). `dt` is the seconds since the last tick. The timers
## count down every tick; the real thinking happens once a second.
func tick(dt: float) -> void:
	# Count the timers down.
	think_t -= dt
	ward_t -= dt
	waypoint_t -= dt
	bay_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0
	var ts := world.teams[team]
	var cmd := world.command
	# Step 1: drones (counting the ones still being built). The economy
	# comes first: a thin drone line (fewer than 4, or fewer than 60% of the
	# target) jumps every queue (playtest: a team that lost its drones never
	# recovered). The target is 6, plus 1 for every 75 s of match time, up
	# to the drone limit (14). A drone costs 200 credits.
	var drones := world.mining_drone_count(team) + ts.drone_queue.size()
	var want_drones := mini(int(Structures.MINING_DRONE["max"]), 6 + int(world.time / 75.0))
	# Not while the build queue is full (6 at a time): the order would only
	# fail with "Drone build queue is full", every second.
	if drones < maxi(4, int(want_drones * 0.6)) and ts.can_afford(200.0) and ts.drone_queue.size() < 6:
		cmd.build_drone(team)
	# Step 2: a first turret at each of our inner nodes comes next.
	builder.guard_inner_nodes(ts)
	# Step 3: the tech plan. If we can't afford the next step yet, keep
	# half its price back ("reserve") so spare spending doesn't starve it.
	var step := AdmiralPlan.next_step(ts)
	var reserve := 0.0
	if not step.is_empty():
		reserve = float(step["cost"])
		if ts.can_afford(reserve):
			if step["kind"] == "f":
				cmd.build_facility(team, step["id"])
			else:
				cmd.research(team, step["id"])
			reserve = 0.0
	# Step 4: spend spare money (the treasury minus half the plan's reserve).
	# Another drone if we're under the target...
	var spare := ts.treasury - reserve * 0.5
	# Step 1 may just have queued a drone: count again, so one think never
	# queues two (and not into a full queue, as in step 1).
	drones = world.mining_drone_count(team) + ts.drone_queue.size()
	if drones < want_drones and spare > 200.0 and ts.drone_queue.size() < 6:
		cmd.build_drone(team)
		spare -= 200.0
	# ...one more turret with over 800 spare...
	if spare > 800.0:
		builder.more_turrets(ts)
	# ...a repair bay (once researched, a try at most every 40 s) with over
	# 500 spare, and a ward (a try at most every 45 s) while the treasury
	# holds over 300.
	if ts.repair_bays and bay_t <= 0.0 and spare > 500.0:
		bay_t = 40.0
		builder.place_bay()
	if ward_t <= 0.0 and ts.treasury > 300.0:
		ward_t = 45.0
		builder.place_ward()
	# Step 5: the waypoint, when its timer runs out.
	if waypoint_t <= 0.0:
		waypoint_t = Rules.WAYPOINT_TIME
		waypoint.place(ts)
	# While our base is under attack (and we aren't sieging), cap the timer
	# at 1 s, so the waypoint is re-placed every second instead of every
	# 75 s.
	if ts.defending(world.time) and ts.siege_lane == "":
		waypoint_t = minf(waypoint_t, 1.0)
	# Step 6: sieges.
	_siege(ts)
	# Step 7: moving our mothership, once its engines are online (20:00,
	# Rules.move_unlock_time(), which a feature module may tune).
	if world.time > Rules.move_unlock_time():
		mothership_mover.maybe_move()
	# Step 8: Fleet Command, only if our team owns the module.
	if world.minion_director.controlled(team):
		fleet.run(ts)


## The siege step (other files' notes, such as TeamState's, point here).
## The real code is AdmiralSiege.update(). When the siege starts, changes
## or ends, the waypoint timer is set to 0 so the waypoint moves at the
## next think.
func _siege(ts: TeamState) -> void:
	if siege.update(ts):
		waypoint_t = 0.0
