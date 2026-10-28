class_name RedeployFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "redeploy" rule variant (idea A2
## of the pacing_downtime fork): "Forward Redeploy". It owns the game's
## hyperspace-timing lever. A pilot who has just respawned can jump straight
## to a friendly repair bay or turret near the fight, instead of flying the
## whole way from the mothership. Only the AI pilots choose a turret: a
## human's hangar offers repair bays only (HangarLaunch.refresh_bay_row).
##
## HOW IT WORKS: with --variant=redeploy:on, install() changes four things:
##   1. The AI admiral builds the Hyperspace Module much earlier: its plan
##      (AdmiralPlan.PLAN) is copied into TeamState.plan_override with the
##      "hyperspace" step moved to directly after the Frigate Facility (it
##      costs 1,200 credits and its prerequisites are met by then).
##   2. A hyperspace launch (WorldHangar.hyperspace_launch) may go to an
##      anchored friendly repair bay OR a finished friendly turret, and the
##      "spool-up" wait is 4 s (SPOOL), not 6. WorldHangar hands the launch
##      to start(); when the spool ends MatchRules calls finish(), which
##      launches the ship and puts it LANDING_DIST (300) world units from the
##      site, on the side toward its own mothership (LandingSpot). install()
##      also sets the tuned number "hyperspace_spool" to SPOOL; only the
##      Hyperspace Module's card on the admiral board reads it (the text says
##      "4s spool-up", not "6s"; Tech.facility_blurb()).
##   3. AI pilots use it. After shopping, PilotAI.update_docked asks
##      pick_site(): the pilot picks a destination (the siege staging or
##      assault point for big ships and bombers during a siege, the defend
##      point while the base is defended, a jungle camp for a jungler, else
##      the front of its lane) and then the friendly bay or turret nearest
##      that destination, provided it is at least MIN_GAIN (6,000) closer to
##      it than the launch point at the mothership and no enemy pilot that
##      the team can see is within 2,500 of the site. Otherwise it launches
##      the normal way.
##   4. The AI admiral places its next repair bay (once the team has the
##      Hyperspace Module) at HALF way down its push or siege lane (0.5)
##      instead of one third (bay_spots(), called by AdmiralBuilder.place_bay).
## Usage counters in Game.usage: "hyperspace_launches" (all), and
## "hyperspace_launches_team0" / "_team1"; "redeploy_turret_landings" (landings
## at a turret), "redeploy_site_lost" (the site died during the spool, so the
## ship launched at the mothership). REQ-CHANGE: none. Watch dead_late: a
## spooling pilot counts as dead in the fun probe.
##
## WHO USES IT: FeatureRegistry installs it. WorldHangar.hyperspace_launch()
## calls start(); MatchRules.tick() calls finish(); PilotAI._hyperspace_bay()
## calls pick_site(); AdmiralBuilder.place_bay() calls bay_spots().

## The variant key this module belongs to.
const KEY := "redeploy"
## Seconds a redeploy jump "spools up" before the ship appears (the normal
## hyperspace launch takes World.HYPERSPACE_SPOOL, 6).
const SPOOL := 4.0
## How far (world units) from the site the ship appears.
const LANDING_DIST := 300.0
## A site must be at least this much (world units) closer to the pilot's
## destination than the launch point at the mothership.
const MIN_GAIN := 6000.0
## A visible enemy pilot ship within this distance (world units) of a site
## makes the site unsafe.
const SAFE_RADIUS := 2500.0
## The place along the push or siege lane (0..1) where the AI admiral puts
## its next repair bay once the team owns the Hyperspace Module.
const BAY_FRAC := 0.5

## The running match.
var world: World


## Plug the feature into match `w` (see HOW IT WORKS, steps 1).
func install(w: World) -> void:
	world = w
	# Step 1: each team's admiral plan with the Hyperspace Module right after
	# the Frigate Facility.
	var plan := plan_with_early_hyperspace()
	for t in 2:
		w.teams[t].plan_override = plan.duplicate()
	# Text only: the Hyperspace Module's card shows this spool-up time.
	Game.tunables["hyperspace_spool"] = SPOOL


## AdmiralPlan.PLAN with ["f", "hyperspace"] taken out of its last place and
## put directly after ["f", "frigate"].
static func plan_with_early_hyperspace() -> Array:
	var plan: Array = []
	for step: Array in AdmiralPlan.PLAN:
		if step[0] == "f" and step[1] == "hyperspace":
			continue
		plan.append(step)
		if step[0] == "f" and step[1] == "frigate":
			plan.append(["f", "hyperspace"])
	return plan


# --- the launch itself ---------------------------------------------------------------------

## Start a redeploy jump of docked pilot `p` to `site` (an anchored friendly
## RepairBay or a finished friendly Turret). Returns "" or why not (shown to
## a human player). WorldHangar.hyperspace_launch() calls it when this
## feature is on. The pilot spools for SPOOL seconds as a "spooling" pilot.
func start(p: PilotProfile, site: Unit) -> String:
	if p.state != "docked":
		return "You must be docked at the mothership"
	if not world.teams[p.team].facilities.has("hyperspace"):
		return "Needs the Hyperspace Module"
	if not site_ok(site, p.team):
		return "That repair bay or turret is gone"
	if p.hull_id == "":
		return "Pick a ship first"
	# The spool: respawn_t doubles as the countdown (see MatchRules.tick).
	p.state = "spooling"
	p.respawn_t = SPOOL
	p.spool_bay = null
	p.spool_site = site
	return ""


## Finish the jump of pilot `p` (its spool ran out; MatchRules.tick calls
## this). Launch the ship and put it next to the site, or at the mothership
## if the site died meanwhile.
func finish(p: PilotProfile) -> void:
	# Step 1: remember and forget the site, and launch the normal way.
	var site := p.spool_site
	p.spool_site = null
	var ship := world.launch(p)
	if ship == null:
		return
	# Step 2: the site may have been destroyed during the spool.
	if site == null or not site_ok(site, p.team):
		Game.count_usage("redeploy_site_lost")
		return
	# Step 3: move the ship to a free spot LANDING_DIST from the site, on the
	# side facing our mothership, nose toward where the enemy mothership
	# started (like any other hyperspace launch).
	var ms := world.mothership(p.team)
	var toward: Vector2 = ms.global_position if ms != null else world.map.mothership_pos[p.team]
	var pos := LandingSpot.find(world, site.global_position, toward, LANDING_DIST, ship.radius + 30.0)
	ship.global_position = pos
	ship.rotation = (world.map.mothership_pos[1 - p.team] - pos).angle()
	ship.velocity = Vector2.from_angle(ship.rotation) * 120.0
	ship.controls.aim_point = pos + Vector2.from_angle(ship.rotation) * 2000.0
	ship.controls.face_point = ship.controls.aim_point
	# Step 4: count it.
	Game.count_usage("hyperspace_launches")
	Game.count_usage("hyperspace_launches_team%d" % p.team)
	if site is Turret:
		Game.count_usage("redeploy_turret_landings")


## Is `site` a place team `team` may jump to right now: an alive anchored
## repair bay of the team, or an alive finished turret of the team?
func site_ok(site: Unit, team: int) -> bool:
	if site == null or not is_instance_valid(site) or not site.alive or site.team != team:
		return false
	if site is RepairBay:
		return (site as RepairBay).is_anchored()
	if site is Turret:
		return (site as Turret).is_built()
	return false


# --- the AI's choice --------------------------------------------------------------------------

## The site the AI pilot `brain` (docked, with a hull picked) should jump to,
## or null for "launch the normal way". See HOW IT WORKS, step 3. It draws no
## random numbers and uses no skill value.
func pick_site(brain: PilotAI) -> Unit:
	var p := brain.profile
	var ts := world.teams[p.team]
	var ms := world.mothership(p.team)
	if ms == null or not ts.facilities.has("hyperspace"):
		return null
	# Step 1: where this pilot wants to be.
	var dest := destination(brain)
	if dest == Vector2.INF:
		return null
	# Step 2: how far the normal launch is from there, and whether this hull
	# can only fly in the open lanes (anything above a strike craft).
	var from_ms := ms.launch_point(p.slot).distance_to(dest)
	var lanes_only := Ships.size_of(p.hull_id) != Rules.SIZE_SMALL
	# Step 3: the nearest safe friendly bay or turret that saves enough.
	var best: Unit = null
	var best_d := INF
	for b in world.bays:
		if b.team == p.team and site_ok(b, p.team):
			var d := _candidate_distance(b, dest, from_ms, lanes_only)
			if d < best_d:
				best_d = d
				best = b
	for t in world.turrets:
		if t.team == p.team and site_ok(t, p.team):
			var d2 := _candidate_distance(t, dest, from_ms, lanes_only)
			if d2 < best_d:
				best_d = d2
				best = t
	return best


## How far candidate `site` is from `dest`, or INF when it is not a good
## choice: it saves less than MIN_GAIN against the launch distance `from_ms`,
## a hull that needs the open lanes could not reach it, or a visible enemy
## pilot ship is near it.
func _candidate_distance(site: Unit, dest: Vector2, from_ms: float, lanes_only: bool) -> float:
	var d := site.global_position.distance_to(dest)
	if from_ms - d < MIN_GAIN:
		return INF
	if lanes_only and not world.map.in_open_lane(site.global_position):
		return INF
	for e: Ship in world.ships:
		if e.team != site.team and e.alive and e.visible_to(site.team) and e.global_position.distance_to(site.global_position) < SAFE_RADIUS:
			return INF
	return d


## Where the AI pilot `brain` is heading after a launch: the siege staging
## point (while gathering) or the assault point for big ships and bombers
## during a siege; the defend point while the base is defended; the nearest
## camp for a jungler; else the front of its lane. Vector2.INF when none.
func destination(brain: PilotAI) -> Vector2:
	var p := brain.profile
	var ts := world.teams[p.team]
	# Step 1: a siege, for big ships and bombers.
	if ts.siege_lane != "" and (Ships.size_of(p.hull_id) != Rules.SIZE_SMALL or p.hull_id == "bomber"):
		if ts.siege_phase == "gather":
			return ts.siege_stage_point(ts.siege_lane)
		return ts.siege_assault_point(ts.siege_lane)
	# Step 2: the base is under attack.
	if ts.defending(world.time) and ts.defend_point != Vector2.INF:
		return ts.defend_point
	# Step 3: a jungler goes to the nearest live camp (its own side first).
	if p.role == "jungle":
		var best := Vector2.INF
		var best_d := INF
		for c: Unit in world.jungle_director.live_camps():
			var mine := (c.global_position.x < MapLayout.CX) == (p.team == Rules.HALCYON)
			var d := c.global_position.distance_to(world.mothership(p.team).global_position) + (0.0 if mine else 6000.0)
			if d < best_d:
				best_d = d
				best = c.global_position
		return best
	# Step 4: the front of our lane's minion wave.
	return brain.goals.lane_front(brain.goals.lane_id(), p.team)


# --- the AI admiral's repair bays -----------------------------------------------------------------

## Change the list of places where the AI admiral of `team` may put its next
## repair bay. `spots` is a list of [lane id, fraction of the lane from the
## admiral's own end] in the order they are tried (normally mid, top, bot, all
## at 0.33). Once the team owns the Hyperspace Module its push lane (or siege
## lane) comes first, at BAY_FRAC; the rest are unchanged. AdmiralBuilder.
## place_bay() asks every feature that has this function.
func bay_spots(w: World, team: int, spots: Array, lanes: AdmiralLanes) -> Array:
	var ts := w.teams[team]
	if not ts.facilities.has("hyperspace"):
		return spots
	# The siege lane if there is a siege, else the lane we are pushing.
	var lane := ts.siege_lane if ts.siege_lane != "" else lanes.push_lane()
	if lane == "":
		return spots
	var out: Array = [[lane, BAY_FRAC]]
	for s: Array in spots:
		if s[0] != lane:
			out.append(s)
	return out
