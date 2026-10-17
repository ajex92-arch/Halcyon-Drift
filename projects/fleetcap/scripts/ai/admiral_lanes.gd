class_name AdmiralLanes
extends RefCounted
## WHAT THIS IS: the AI admiral's "eyes on the map". It answers questions
## about the lanes and the fleets: which lane are we pushing, how far down
## a lane our minions have got, where a point part-way down a lane is, and
## how strong each side's pilot fleet is right now.
##
## HOW IT WORKS: a lane is a path made of straight pieces joined end to end
## (a "polyline", see MapLayout.LANES). It runs from one mothership's spot
## to the other's. To see how far along a lane a ship is, we find the
## closest point on that path and measure the distance along the path to it
## (Util.project_on_polyline gives this as "s", in world units). Nothing in
## this file changes the game: it only looks.
##
## WHO USES IT: AdmiralAI makes one (AdmiralAI.lanes) and hands it to its
## other parts, which call it: AdmiralWaypoint, AdmiralSiege,
## AdmiralMothershipMover, AdmiralBuilder and AdmiralFleetCommand.

## The game world (we read its minions and ships).
var world: World
## Our team: 0 = Halcyon, 1 = Cinder.
var team := 0


## Remember the world and our team. AdmiralAI makes this part once.
func _init(w: World, t: int) -> void:
	world = w
	team = t


## The lane we are "pushing": the one where one of our minions has got
## furthest from our base, as a fraction of the lane's length (the lanes are
## not equally long: top and bottom about 44,200 units, mid about 33,600, so
## comparing distances would hardly ever pick mid). Returns the lane id
## ("top", "mid" or "bot"), or "" when we have no living minions in any lane.
func push_lane() -> String:
	var best := ""
	# Fraction along its lane (0..1) of the furthest minion so far.
	var best_s := -1.0
	for lane: String in MapLayout.LANE_ORDER:
		# The lane's path as our team walks it: from our base outwards.
		var pts := MapLayout.lane_points(lane, team)
		var lane_len := Util.polyline_length(pts)
		# Measure every living minion of ours that is on this lane.
		for m in world.minions:
			if m.team == team and m.alive and m.lane == lane:
				var s: float = float(Util.project_on_polyline(m.global_position, pts)["s"]) / lane_len
				if s > best_s:
					best_s = s
					best = lane
	return best


## How far along `lane` our furthest minion is, as a fraction from 0.0 (our
## end of the lane) to 1.0 (the enemy's end). 0.0 when none of our minions
## are on that lane.
func front_frac(lane: String) -> float:
	var pts := MapLayout.lane_points(lane, team)
	# Furthest distance along the lane (world units) found so far.
	var best := 0.0
	for m in world.minions:
		if m.team == team and m.alive and m.lane == lane:
			best = maxf(best, float(Util.project_on_polyline(m.global_position, pts)["s"]))
	# Turn the distance into a fraction of the whole lane's length.
	return best / Util.polyline_length(pts)


## The point `frac` of the way along `lane`, counted from our end (0.0 =
## where our mothership starts, 1.0 = where the enemy's starts). For
## example lane_point("mid", 0.5) is the middle of the mid lane.
func lane_point(lane: String, frac: float) -> Vector2:
	var pts := MapLayout.lane_points(lane, team)
	return Util.polyline_at(pts, Util.polyline_length(pts) * frac)


## How strong team `t`'s flying pilot ships are, as one number. A ship
## counts by size: 1 for strike craft, 2 for corvettes, 3 for frigates, 4
## for capital ships. That is multiplied by 0.4 + 0.6 x its hull fraction
## (how much hull it has left, 0..1), so a badly damaged ship counts for
## less, but never under 0.4 of its size. Minions and turrets don't count.
func fleet_power(t: int) -> float:
	var p := 0.0
	for s: Ship in world.ships:
		if s.team == t and s.alive:
			p += float(1 + Rules.size_index(s.size_class)) * (0.4 + 0.6 * s.hull_frac())
	return p
