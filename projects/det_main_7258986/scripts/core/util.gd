class_name Util
extends RefCounted
## WHAT THIS IS: a toolbox of small math and text helpers shared by flight,
## weapons, AI, the map and the screens: angles, aiming, "does this line
## hit that circle?", walking along a line of points, and turning numbers
## into text like "1,234" or "3:07".
##
## HOW IT WORKS: every function is "static": it belongs to the class
## itself, keeps no memory, and is called as Util.name(...) without making
## a Util first. Each one only works out an answer from what it is given.
##
## Directions match the screen: +X is east (right), +Y is south (down).
## Angles are in radians (a full turn is TAU, about 6.28; half a turn is
## PI). Angle 0 points east and angles grow clockwise on screen. A ship's
## local +Y is starboard (pilot's right); -Y is port (pilot's left).
## A "polyline" is a line made of points joined one after another (like a
## lane's centre line); a "segment" is the straight piece between two of
## them. Distances are in world units (about one pixel at normal zoom).
##
## WHO USES IT: almost everything. For example: ships, minions, turrets and
## weapon mounts (angles, aiming, segment tests), Projectiles (hit tests),
## AsteroidField (segment tests), the map makers (MapBuilder parts, MapInfo,
## MapDecor), AI pilots and admirals and TeamState (polylines), and the
## HUD, hangar, scoreboard and end screen (money(), clock()).


## The same direction as angle `a`, written between -PI and PI (at most
## half a turn either way). For example 7.0 becomes about 0.72.
static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


## The shortest turn from angle `from` to angle `to` (radians, -PI..PI).
## Positive means turn clockwise on screen, negative anticlockwise.
static func ang_diff(from: float, to: float) -> float:
	return wrap_angle(to - from)


## Port (pilot's left) unit vector for a facing.
## (A "unit vector" is an arrow of length 1 that only shows a direction.)
static func port_of(facing: float) -> Vector2:
	return Vector2(sin(facing), -cos(facing))


## Starboard (pilot's right) unit vector for a facing.
static func starboard_of(facing: float) -> Vector2:
	return Vector2(-sin(facing), cos(facing))


## Firing solution: where to aim so a round at `speed` meets a target moving
## at constant velocity. `shooter_vel` is what the round inherits.
## It guesses three times, each guess better than the last: "how long
## would a round take to reach where the target will be? Then where will
## the target be after that long?" (A speed below 1 counts as 1.)
static func lead_point(from: Vector2, shooter_vel: Vector2, target: Vector2, target_vel: Vector2, speed: float) -> Vector2:
	var rel := target_vel - shooter_vel
	var p := target
	for i in 3:
		var t := from.distance_to(p) / maxf(1.0, speed)
		p = target + rel * t
	return p


## Swept hit test: does the segment a->b pass within r of c?
## ("Swept" because it checks the whole path a fast object moved along in
## one step, not just where it ended up.) Touching counts as a hit.
static func seg_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var len2 := ab.length_squared()
	# A segment with (almost) no length: just test point a.
	if len2 < 0.0001:
		return a.distance_squared_to(c) <= r * r
	# The point on the segment closest to c, then its distance to c.
	var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c) <= r * r


## Parameter t (0..1) along a->b where it first enters the circle, or -1.
## t = 0 means at a, 1 means at b. If a is already inside the circle the
## answer is 0. It solves the "where does a line cross a circle" equation
## (a quadratic: the standard school formula with the square root).
static func seg_circle_t(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	var aa := d.dot(d)
	# A segment with (almost) no length: 0 if a is inside, else -1.
	if aa < 0.0001:
		return 0.0 if f.length_squared() <= r * r else -1.0
	var bb := 2.0 * f.dot(d)
	var cc := f.dot(f) - r * r
	# Starting inside the circle.
	if cc <= 0.0:
		return 0.0
	# The line misses the circle completely.
	var disc := bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return -1.0
	# The first crossing; it only counts if it is between a and b.
	var t := (-bb - sqrt(disc)) / (2.0 * aa)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## Closest point on segment a-b to p.
static func closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return a
	return a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0)


## Distance from p to a polyline (to its nearest segment). INF (infinity)
## if it has fewer than two points.
static func dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(closest_on_segment(p, pts[i], pts[i + 1])))
	return best


## Closest point on a polyline and the arc-length position of it.
## Returns {"point": the closest point, "s": how far along the polyline it
## is from the first point (world units), "dist": how far it is from p}.
## On a tie the earlier segment wins.
static func project_on_polyline(p: Vector2, pts: PackedVector2Array) -> Dictionary:
	var best := INF
	var best_pt := pts[0] if pts.size() > 0 else p
	var best_s := 0.0
	# `s` is the length of the polyline before segment i.
	var s := 0.0
	for i in pts.size() - 1:
		var q := closest_on_segment(p, pts[i], pts[i + 1])
		var d := p.distance_to(q)
		if d < best:
			best = d
			best_pt = q
			best_s = s + pts[i].distance_to(q)
		s += pts[i].distance_to(pts[i + 1])
	return {"point": best_pt, "s": best_s, "dist": best}


## Point at arc length s along a polyline (clamped to its ends).
## That is: walk `s` world units along the polyline from its first point.
## Past the end you get the last point. (Careful: a negative `s` is not
## clamped; it gives a point before the start, on the line through the
## first segment.) An empty polyline gives (0, 0).
static func polyline_at(pts: PackedVector2Array, s: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var left := s
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if left <= seg:
			return pts[i].lerp(pts[i + 1], left / maxf(0.001, seg))
		left -= seg
	return pts[pts.size() - 1]


## Total length of a polyline (world units).
static func polyline_length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size() - 1:
		s += pts[i].distance_to(pts[i + 1])
	return s


## "1,234" style money.
## Rounds down to a whole number first, so 1234.9 becomes "1,234" (and
## -0.5 becomes "-1").
static func money(v: float) -> String:
	var n := int(floor(v))
	var s := str(absi(n))
	# Peel off three digits at a time from the right, with a comma before.
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## "m:ss".
## Minutes and seconds from a number of seconds, rounded down, for example
## 187.6 -> "3:07". Below zero shows "0:00"; minutes can go past 59.
static func clock(seconds: float) -> String:
	var s := maxi(0, int(floor(seconds)))
	return "%d:%02d" % [s / 60, s % 60]
