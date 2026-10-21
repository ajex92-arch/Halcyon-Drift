class_name GroupLateFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "group_late" rule variant (fork
## teamfights_jungle, idea D1). After 25:00 the whole team gathers on ONE
## lane, the "push lane" P, so the late game is one big fight instead of
## three small ones. Junglers are pulled in too. REQ-CHANGE: none.
##
## HOW IT WORKS: every half second, for each team, it works out the push
## lane P: the lane of the team's siege if there is one, otherwise the lane
## the team's minions have pushed furthest (AdmiralLanes.push_lane; without a
## siege a chosen lane is kept for at least 45 seconds, so the pilots are not
## sent back and forth across the map). It also
## finds the middle of the friendly big ships (medium ships and up) that fly
## on P. Then the AI rules (PilotGoals._pick_station calls active() and
## plan_for(), PilotAI calls pilot_think(), PilotGoals.think_jungle calls
## allow_camp()):
##   - Seats already on P stay (so do the two lowest-numbered seats of every
##     other lane).
##   - The third laner of every other lane (seats 8, 9 and 10) and the flex
##     pilot (seat 7) move to P and take station 800 world units behind the
##     middle of the friendly big ships on P, or 800 behind the wave front
##     when there are none. While this is on it replaces the old rally of
##     seats 4, 5, 6 and the flex pilot on the admiral's waypoint.
##   - The junglers (seats 3 and 11) fly the lane job on P whenever their
##     team has a siege or a defence call going; otherwise they only clear
##     camps within 6,000 of P.
##   - It all stops (everyone goes back to normal) when P has had no friendly
##     big ship for 60 seconds.
## Nothing is read about the skill of a pilot. No random numbers are drawn.
## Usage count: "grouped_seconds" (pilot-seconds spent grouped).
##
## WHO USES IT: FeatureRegistry installs it for --variant=group_late:on.
## PilotGoals._pick_station() asks active() and plan_for(); PilotAI's feature
## hook asks pilot_think(); PilotGoals.think_jungle asks allow_camp().

## The variant key this module belongs to.
const KEY := "group_late"
## Match time (seconds) from which the grouping starts: 25:00.
const START_TIME := 1500.0
## How far (world units) behind the friendly big ships' middle (or behind the
## wave front) the grouped seats take station.
const BEHIND := 800.0
## A big ship counts as "on P" when it is within this many world units of the
## lane's centre line.
const ON_LANE := 2500.0
## The grouping ends after this many seconds with no friendly big ship on P.
const GIVE_UP := 60.0
## Junglers only clear camps within this many world units of P.
const CAMP_RANGE := 6000.0
## Seconds between two updates of the plan.
const STEP := 0.5
## A push lane (when there is no siege) is kept at least this many seconds
## before the team may switch to another one.
const KEEP := 45.0

## The match.
var world: World
## One AdmiralLanes helper per team (to ask for the team's push lane).
var lanes: Array = []
## The plan of each team (index = team): {} when the grouping is off for it,
## else {"lane": P, "s_goal": the station's distance along P in world units,
## counted from that team's end}.
var plans: Array = [{}, {}]
## The match time at which each team last had a big ship on P (index = team).
var last_big: Array = [START_TIME, START_TIME]
## The push lane each team chose last (index = team; "" = none yet) and the
## match time it chose it.
var held: Array = ["", ""]
## See `held`.
var held_since: Array = [0.0, 0.0]
## Seconds until the next plan update.
var _t := 0.0
## Pilot-seconds not yet added to the usage count.
var _acc := 0.0


## Hook the module into match `w`: make the lane helpers and the tick hook.
func install(w: World) -> void:
	world = w
	lanes = [AdmiralLanes.new(w, 0), AdmiralLanes.new(w, 1)]
	w.tick_hooks.append(Callable(self, "tick"))


## Called by World every tick: every STEP seconds, update both teams' plans
## and count the grouped pilot-seconds.
func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = STEP
	if world.time < START_TIME:
		return
	# Step 1: the plans.
	for t in 2:
		plans[t] = _plan_for_team(t)
	# Step 2: count the AI seats that are grouped right now.
	var n := 0
	for s: Ship in world.ships:
		if s.alive and s.profile != null and not s.profile.is_human and not (plan_for(s, s.profile) as Dictionary).is_empty():
			n += 1
	_acc += float(n) * STEP
	var whole := int(_acc)
	if whole > 0:
		Game.count_usage("grouped_seconds", whole)
		_acc -= float(whole)


## Work out team `t`'s plan (see HOW IT WORKS): {} when there is no push lane
## or P has had no big ship for GIVE_UP seconds.
func _plan_for_team(t: int) -> Dictionary:
	var ts: TeamState = world.teams[t]
	var p_lane: String = ts.siege_lane if ts.siege_lane != "" else (lanes[t] as AdmiralLanes).push_lane()
	# A push lane that is not a siege lane is kept for at least KEEP seconds
	# (the furthest minion can jump between lanes, and the pilots need time
	# to fly across the map).
	if ts.siege_lane == "" and str(held[t]) != "" and world.time - float(held_since[t]) < KEEP:
		p_lane = str(held[t])
	if p_lane != str(held[t]):
		held[t] = p_lane
		held_since[t] = world.time
	if p_lane == "":
		return {}
	# Step 1: where the friendly big ships on P are (average distance along
	# the lane, counted from this team's end).
	var pts := MapLayout.lane_points(p_lane, t)
	var sum_s := 0.0
	var n := 0
	for s: Ship in world.ships:
		if s.team == t and s.alive and not s.is_small():
			var pr := Util.project_on_polyline(s.global_position, pts)
			if float(pr["dist"]) < ON_LANE:
				sum_s += float(pr["s"])
				n += 1
	if n > 0:
		last_big[t] = world.time
	if world.time - float(last_big[t]) > GIVE_UP:
		return {}
	# Step 2: the station: BEHIND short of their middle, or short of the wave
	# front when there are none.
	var s_goal := 0.0
	if n > 0:
		s_goal = sum_s / float(n) - BEHIND
	else:
		s_goal = (lanes[t] as AdmiralLanes).front_frac(p_lane) * Util.polyline_length(pts) - BEHIND
	return {"lane": p_lane, "s_goal": maxf(0.0, s_goal)}


## Is the grouping on for team `team` right now? PilotGoals._pick_station()
## asks this to switch the old waypoint rally off.
func active(team: int) -> bool:
	return not (plans[team] as Dictionary).is_empty()


## Must pilot `profile` (flying `ship`) move to the push lane? Returns the
## team's plan ({"lane", "s_goal"}) for seats that move, {} for the others
## (seats that stay, and junglers unless their team has a siege or defence
## call). PilotGoals._pick_station() uses the plan as the station.
func plan_for(_ship: Ship, profile: PilotProfile) -> Dictionary:
	var plan: Dictionary = plans[profile.team]
	if plan.is_empty():
		return plan
	match profile.role:
		"flex":
			return plan
		"top", "mid", "bot":
			# Only the third laner (seat 8 or higher) of a lane other than P.
			if profile.slot >= 8 and profile.role != str(plan["lane"]):
				return plan
		"jungle":
			if _forced(profile.team):
				return plan
	return {}


## Does team `team` have a siege or a defence call going? Then its junglers
## fly the lane job on P.
func _forced(team: int) -> bool:
	var ts: TeamState = world.teams[team]
	return ts.siege_lane != "" or ts.defending(world.time)


## Feature hook (PilotAI._feature_takes_over): a jungler in the jungle state
## whose team has a siege or defence call flies the lane job (PilotGoals.
## think_lane, whose station comes from plan_for). Returns true when it did.
func pilot_think(brain: PilotAI, ship: Ship) -> bool:
	if brain.state != "jungle" or brain.profile.role != "jungle":
		return false
	if not active(brain.profile.team) or not _forced(brain.profile.team):
		return false
	brain.goals.think_lane(ship)
	return true


## Feature hook (PilotGoals.think_jungle): may jungler `ship` clear camp `d`?
## While the grouping is on for its team, only camps within CAMP_RANGE of P.
func allow_camp(brain: PilotAI, _ship: Ship, d: Derelict) -> bool:
	var team := brain.profile.team
	if not active(team):
		return true
	var pts := MapLayout.lane_points(str((plans[team] as Dictionary)["lane"]), team)
	return Util.dist_to_polyline(d.global_position, pts) < CAMP_RANGE
