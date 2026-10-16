class_name TeamSiege
extends RefCounted
## WHAT THIS IS: the map maths for a siege, when our fleet (every ship
## bigger than a strike craft, plus bombers) attacks the enemy mothership
## together. It works out where on a lane they gather first, and where
## they rally for the final attack.
##
## HOW IT WORKS: each lane is a bent line of points (a "polyline"). Our
## copy of a lane starts at our end of the map (MapLayout.lane_points). We
## measure places by how far along the lane they are, in world units (1
## world unit is about one pixel at normal zoom), counting from our end.
## First we find where the enemy mothership is along the lane
## (enemy_ms_on_lane). Then:
##   staging point  SIEGE_STAGE (60%) of the way along the lane, but at
##                  least SIEGE_STAGE_GAP (7,000) short of the enemy
##                  mothership;
##   assault point  ASSAULT_GAP (4,500) short of the enemy mothership.
## Neither point is ever before the start of the lane. Both are measured
## from where the enemy mothership is NOW, because after 20:00 it can move
## up a lane. (Playtest: fleets "assaulted" the empty end of the lane while
## the mothership sat 12,000 away.) The three numbers are tuned numbers: a
## feature module may change them for one match ("siege_stage_frac",
## "siege_stage_gap", "siege_assault_gap"; see Rules.tune).
##
## WHO USES IT: TeamState makes one (TeamState.siege) and forwards
## enemy_ms_on_lane(), siege_stage_point() and siege_assault_point() here.
## AdmiralSiege uses them to run the siege (and to notice when the enemy
## mothership has left the siege lane), AdmiralWaypoint puts the team
## waypoint on these points, and PilotGoals flies AI ships to them.

## How far along the lane the staging point is: 0.6 = 60% of the lane's
## length, counted from our end.
const SIEGE_STAGE := 0.6
## The staging point stays at least this far (world units, along the lane)
## short of the enemy mothership.
const SIEGE_STAGE_GAP := 7000.0
## The assault rally point is this far (world units, along the lane) short
## of the enemy mothership.
const ASSAULT_GAP := 4500.0

## The team this part belongs to (we read its world and team number). It
## is reached through a weak link: see `_ts_ref`.
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A "weak" link to the team. TeamState holds this part with a normal
## (strong) link. If the part held the team strongly too, each would keep
## the other alive forever and Godot could never free them (a memory
## leak). A weak link points at the team without keeping it alive.
var _ts_ref: WeakRef


## Remember our team (through a weak link). TeamState makes this part once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)


## Where the enemy mothership is now, measured against our copy of lane
## `lane`. Returns Util.project_on_polyline's dictionary: "s" (how far
## along the lane, in world units), "point" (the nearest point on the
## lane) and "dist" (how far the mothership is off the lane).
func enemy_ms_on_lane(lane: String) -> Dictionary:
	var ems: Mothership = ts.world.mothership(Rules.enemy_of(ts.team))
	return Util.project_on_polyline(ems.global_position, MapLayout.lane_points(lane, ts.team))


## The siege staging point on `lane`: SIEGE_STAGE (60%) of the way along,
## but at least SIEGE_STAGE_GAP (7,000) short of the enemy mothership.
func stage_point(lane: String) -> Vector2:
	var pts := MapLayout.lane_points(lane, ts.team)
	# The nearer of the two: 60% along, or 7,000 short of the mothership
	# (both tuned numbers, normally SIEGE_STAGE and SIEGE_STAGE_GAP).
	var frac := float(Rules.tune("siege_stage_frac", SIEGE_STAGE))
	var gap := float(Rules.tune("siege_stage_gap", SIEGE_STAGE_GAP))
	var s := minf(Util.polyline_length(pts) * frac, float(enemy_ms_on_lane(lane)["s"]) - gap)
	# Turn "how far along" into a point on the map (never before the start).
	return Util.polyline_at(pts, maxf(0.0, s))


## The siege assault rally point on `lane`: ASSAULT_GAP (4,500, tuned
## "siege_assault_gap") short of the enemy mothership, along the lane.
func assault_point(lane: String) -> Vector2:
	var pts := MapLayout.lane_points(lane, ts.team)
	var gap := float(Rules.tune("siege_assault_gap", ASSAULT_GAP))
	return Util.polyline_at(pts, maxf(0.0, float(enemy_ms_on_lane(lane)["s"]) - gap))
