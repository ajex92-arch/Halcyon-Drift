class_name AdmiralSiege
extends RefCounted
## WHAT THIS IS: the AI admiral's late-game attack plan. A "siege" sends
## our big ships (frigates and capital ships) and bombers together down one
## lane to attack the enemy mothership. Destroying the enemy mothership
## wins the match.
##
## HOW IT WORKS: after 20:00 (1200 s of match time), if we have at least 2
## healthy big ships and the upper hand, it picks the lane whose enemy inner
## node (the ore field on that lane nearest their mothership) has the
## fewest turrets and declares a siege there (unless the enemy mothership is
## parked up a lane, more than PARKED_DIST (2,500) from its home spot: then
## the siege goes to the lane it is on). A siege has two phases, stored in
## TeamState.siege_phase:
##   "gather":  big ships meet at a staging point part-way down the lane,
##              so the slow capital ships arrive together.
##   "assault": everyone closes on the enemy mothership.
## It calls the siege off when no big ships are left, or when the assault
## stalls (_run_siege() explains how it decides that). After a call-off it
## waits 60 s before it may declare another siege.
## (Playtest: 50-minute matches never touched a mothership while the big
## ships kept to their separate lane posts; sieges fixed that.)
## Every number of the plan (PARKED_DIST aside) is a constant below and also
## a "tuned number": it is read through Rules.tune(name, constant), so a
## feature module may change it for one match (the names are in
## Rules.TUNABLES, all starting with "siege_"). With no feature on, the
## constants are used as they are.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.siege) and calls update()
## once a second (through AdmiralAI._siege). PilotAI reads
## TeamState.siege_lane and siege_phase to send big ships and bombers.
## AdmiralWaypoint puts the team waypoint on the siege lane while one runs.
## TeamState can also call our siege off when the enemy attacks our own
## base.

## Match time (seconds) before which no siege is declared: 1200 s = 20:00
## (tuned "siege_start").
const START_TIME := 1200.0
## Healthy big ships (over half their hull) needed to declare a siege
## (tuned "siege_min_healthy").
const MIN_HEALTHY := 2
## To declare a siege our fleet strength (AdmiralLanes.fleet_power) must
## be at least this many times the enemy's (tuned "siege_power_edge")...
const POWER_EDGE := 1.2
## ...unless the enemy mothership's hull fraction is already this low or
## lower (0.6 = 60%; tuned "siege_ms_hurt").
const MS_HURT := 0.6
## Big ships massed at the staging point that start the assault (tuned
## "siege_gather_count").
const GATHER_COUNT := 2
## Seconds of gathering after which whoever is there attacks (tuned
## "siege_gather_time").
const GATHER_TIME := 45.0
## How close (world units) to the staging point a big ship must be to
## count as massed (tuned "siege_gather_radius").
const GATHER_RADIUS := 3000.0
## How close (world units) to the enemy mothership's hull a big ship must
## get to count as "contact" (tuned "siege_contact_dist").
const CONTACT_DIST := 3000.0
## Seconds after contact at which the stall check is made (tuned
## "siege_stall_time")...
const STALL_TIME := 120.0
## ...by then the enemy mothership must have lost this hull fraction (0.15
## = 15%), or the assault has stalled (tuned "siege_stall_frac").
const STALL_FRAC := 0.15
## Seconds of assault with no contact at all after which it has stalled
## (tuned "siege_no_contact_time").
const NO_CONTACT_TIME := 300.0
## Seconds after a call-off before another siege may be declared (tuned
## "siege_cooldown").
const COOLDOWN := 60.0
## How far (world units) the enemy mothership may be off the siege lane
## before the siege follows it to the lane it is on now (tuned
## "siege_follow_dist").
const FOLLOW_DIST := 4000.0
## How far (world units) the enemy mothership must be from its home spot to
## count as "parked up a lane": a new siege then goes to the lane it is on.
## (Not a tuned number.)
const PARKED_DIST := 2500.0

## The game world (ships, nodes, motherships, the map, match time).
var world: World
## Our team: 0 = Aurelian, 1 = Vhorr.
var team := 0
## The admiral's lane helper (we use its fleet strength measure).
var lanes: AdmiralLanes
## Match time (seconds) before which we won't declare a new siege: set to
## COOLDOWN (60 s) after a siege is called off.
var cooldown_until := 0.0
## Match time (seconds) when our first big ship got within CONTACT_DIST
## (3,000 units) of the enemy mothership's hull in this assault. 0 =
## nobody has got there yet.
var contact_t := 0.0
## The enemy mothership's hull fraction (how much hull it has left: 1.0 =
## full, 0.0 = destroyed) when our first big ship got there. It is also set
## when the assault starts, then measured again on contact. The stall check
## compares against it.
var contact_ms_hp := 1.0


## Remember the world, our team and the lane helper. AdmiralAI makes this
## part once.
func _init(w: World, t: int, l: AdmiralLanes) -> void:
	world = w
	team = t
	lanes = l


## Run the siege plan for one admiral think (once a second). With a siege on,
## it checks whether to call it off, follows the enemy mothership if it has
## moved to another lane, and moves "gather" on to "assault". With no siege,
## it decides whether to start one. `ts` is our team's shared state.
## Returns true when the siege started, changed or ended, so the admiral
## should move the team waypoint at its next think.
func update(ts: TeamState) -> bool:
	# Step 1: count our big ships, and how many have over half their hull.
	var bigs := 0
	var healthy := 0
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.size_class >= Rules.SIZE_LARGE:
			bigs += 1
			if s.hull_frac() > 0.5:
				healthy += 1
	if ts.siege_lane != "":
		return _run_siege(ts, bigs)
	# Step 2: no siege yet. Only after 20:00 (START_TIME), with 2+ healthy
	# big ships (MIN_HEALTHY), while our base isn't under attack, and not
	# right after a call-off.
	var start := float(Rules.tune("siege_start", START_TIME))
	var min_healthy := int(Rules.tune("siege_min_healthy", MIN_HEALTHY))
	if world.time < start or healthy < min_healthy or ts.defending(world.time) or world.time < cooldown_until:
		return false
	# Step 3: only go when we have the edge (we won a fight: their ships are
	# dead or out of position), like a MOBA team going for the base after a
	# teamfight, or when the enemy mothership is already hurt. Our fleet must
	# be at least 1.2 times theirs (POWER_EDGE; AdmiralLanes.fleet_power), or
	# their mothership down to 60% hull or less (MS_HURT). (Playtest: sieges
	# at even strength always met the whole defending fleet at its own guns.)
	var ems2 := world.mothership(1 - team)
	var edge := float(Rules.tune("siege_power_edge", POWER_EDGE))
	var hurt := float(Rules.tune("siege_ms_hurt", MS_HURT))
	if lanes.fleet_power(team) < lanes.fleet_power(1 - team) * edge and (ems2 == null or ems2.hull_frac() > hurt):
		return false
	# Step 4: pick the lane whose enemy inner node has the fewest turrets
	# (on a tie, the first in top, mid, bot order).
	var best := ""
	var fewest := 99
	for lane: String in MapLayout.LANE_ORDER:
		var n := 0
		for node in world.nodes:
			if node.lane == lane and node.node_kind == "inner" and node.side == 1 - team:
				n += node.turret_count(1 - team)
		if n < fewest:
			fewest = n
			best = lane
	# The enemy mothership is parked up a lane (it is, from 20:00 on): siege
	# that lane at once. With the fewest-turret lane the siege would be
	# re-aimed a second later at the lane the enemy mothership is on (step 3
	# of _run_siege).
	if ems2 != null and ems2.global_position.distance_to(world.map.mothership_pos[1 - team]) > PARKED_DIST:
		best = world.map.lane_for(ems2.global_position)
	# Step 5: declare it and start gathering. (We return true below, so the
	# waypoint moves at once.)
	ts.siege_lane = best
	ts.siege_phase = "gather"
	ts.siege_t = world.time
	# "team" tone: only our side's HUD shows this, so the enemy doesn't get
	# our plan.
	Events.feed.emit("The %s fleet is massing to assault the %s mothership (%s)." % [Rules.TEAM_DISPLAY[team], Rules.TEAM_DISPLAY[1 - team], MapLayout.LANES[best]["label"].to_lower()], "team", team)
	return true


## A siege is on: call it off if it is lost or stalled, follow the enemy
## mothership to its new lane, and switch "gather" to "assault" when the
## fleet is ready. `bigs` is how many big ships we have alive. Returns true
## when any of that happened (the waypoint should move).
func _run_siege(ts: TeamState, bigs: int) -> bool:
	var move_waypoint := false
	var ems := world.mothership(1 - team)
	# Step 1: is the assault stalled? A stalled assault is called off so the
	# fleet can regroup (playtest: one ran for 15 minutes). Stalled means:
	# the enemy mothership lost less than 15% hull (STALL_FRAC) in the 120 s
	# (STALL_TIME) after our first big ship got within 3,000 (CONTACT_DIST)
	# of it, or nobody got there at all in 300 s (NO_CONTACT_TIME). (When
	# this was timed from the assault order instead, slow capital ships
	# arrived with about 30 s left, and every siege was called off right at
	# the enemy hull.)
	var stalled := false
	if ts.siege_phase == "assault" and ems != null:
		# Note the moment our first big ship gets close, and the enemy hull then.
		if contact_t <= 0.0:
			var contact_dist := float(Rules.tune("siege_contact_dist", CONTACT_DIST))
			for s: Ship in world.ships:
				if s.team == team and s.alive and s.size_class >= Rules.SIZE_LARGE and ems.hull_dist(s.global_position) < contact_dist:
					contact_t = world.time
					contact_ms_hp = ems.hull_frac()
					break
		if contact_t > 0.0:
			var stall_time := float(Rules.tune("siege_stall_time", STALL_TIME))
			var stall_frac := float(Rules.tune("siege_stall_frac", STALL_FRAC))
			stalled = world.time - contact_t > stall_time and ems.hull_frac() > contact_ms_hp - stall_frac
		else:
			stalled = world.time - ts.siege_t > float(Rules.tune("siege_no_contact_time", NO_CONTACT_TIME))
	# Step 2: call it off: no big ships left, or stalled. No new siege for
	# 60 s (COOLDOWN).
	if bigs < 1 or stalled:
		ts.siege_lane = ""
		ts.siege_phase = ""
		cooldown_until = world.time + float(Rules.tune("siege_cooldown", COOLDOWN))
		return true
	# Step 3: the enemy mothership has moved more than 4,000 units
	# (FOLLOW_DIST) off our siege lane (it can move from 20:00): siege the
	# lane it is on now.
	if ems != null and float(ts.enemy_ms_on_lane(ts.siege_lane)["dist"]) > float(Rules.tune("siege_follow_dist", FOLLOW_DIST)):
		ts.siege_lane = world.map.lane_for(ems.global_position)
		move_waypoint = true
	if ts.siege_phase == "gather":
		# Step 4: go when two big ships (GATHER_COUNT) have massed within
		# 3,000 (GATHER_RADIUS) of the staging point (or after 45 s,
		# GATHER_TIME: whoever is there goes).
		var stage := ts.siege_stage_point(ts.siege_lane)
		var radius := float(Rules.tune("siege_gather_radius", GATHER_RADIUS))
		var massed := 0
		for s: Ship in world.ships:
			if s.team == team and s.alive and s.size_class >= Rules.SIZE_LARGE and s.global_position.distance_to(stage) < radius:
				massed += 1
		if massed >= int(Rules.tune("siege_gather_count", GATHER_COUNT)) or world.time - ts.siege_t > float(Rules.tune("siege_gather_time", GATHER_TIME)):
			ts.siege_phase = "assault"
			ts.siege_t = world.time
			contact_t = 0.0
			contact_ms_hp = ems.hull_frac() if ems != null else 1.0
			move_waypoint = true
	return move_waypoint
