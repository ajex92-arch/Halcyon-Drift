class_name MothershipHull
extends RefCounted
## WHAT THIS IS: the shape maths of the mothership's long hull (a part of
## Mothership, kept in its own file): "how far is this point from the
## hull?" and "does this shot hit it?".
##
## HOW IT WORKS: the hull is a capsule: picture a thick line with round
## ends. The line down its middle is the keel. It runs `half_len` world
## units ahead of and behind the ship's centre, and the hull's surface is
## beam / 2 (half the width) away from the keel all round. So the distance
## from any point to the hull is the distance to the nearest point of the
## keel, minus beam / 2. (1 world unit is about one pixel at normal zoom.)
## This is a "static library": it keeps no memory of its own and is handed
## the mothership each time.
##
## WHO USES IT: Mothership.hull_dist() and Mothership.hit_t() forward here.
## Many files call those two: AI pilots, minions, drones, Combat,
## Projectiles, WorldHangar, TeamState and more.


## How far point `p` is from the surface of `ms`'s hull, in world units
## (negative when `p` is inside the hull).
static func dist(ms: Mothership, p: Vector2) -> float:
	# `a` and `b` are the two ends of the keel line.
	var f := ms.keel_arrow()
	var c := ms.global_position
	var a := c + f
	var b := c - f
	return p.distance_to(Util.closest_on_segment(p, a, b)) - ms.beam * 0.5


## Hit test for a round or a beam that travels from `a` to `b` in one
## step. Returns where along that line it first touches `ms`'s hull, as a
## 0..1 fraction (0 = at a, 1 = at b), or -1 for a miss. `pad` (world
## units) makes the hull a little fatter.
static func hit_t(ms: Mothership, a: Vector2, b: Vector2, pad: float) -> float:
	# Already touching at the start point.
	if dist(ms, a) <= pad:
		return 0.0
	# Sample the segment against the keel capsule every <= 60 u (beams are
	# 1,600-2,600 long and the hull only 340 thick, so a fixed few samples
	# could step right over it), then bisect the entry point.
	var length := a.distance_to(b)
	var steps := maxi(2, int(ceil(length / 60.0)))
	var prev := 0.0
	for i in range(1, steps + 1):
		# a.lerp(b, t) is the point a fraction t of the way from a to b.
		var t := float(i) / float(steps)
		if dist(ms, a.lerp(b, t)) <= pad:
			# This sample is inside and the previous one was outside, so the
			# entry is between them. "Bisect": halve that gap 6 times, each
			# time keeping the half where the entry is, and return the first
			# spot known to be inside.
			var lo := prev
			var hi := t
			for _k in 6:
				var mid := (lo + hi) * 0.5
				if dist(ms, a.lerp(b, mid)) <= pad:
					hi = mid
				else:
					lo = mid
			return hi
		prev = t
	return -1.0
