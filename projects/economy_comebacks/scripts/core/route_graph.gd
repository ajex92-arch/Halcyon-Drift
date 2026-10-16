class_name RouteGraph
extends RefCounted
## WHAT THIS IS: the road map that AI ships and drones use to get around
## the asteroids. It is a "graph": a set of dots ("nodes") on the lane
## centre lines, at the bases and along the jungle paths, joined by
## straight links ("edges") that are known to be clear to fly along.
##
## HOW IT WORKS: MapBuilderRoute fills it in when the map is made. Jungle
## dots, and the links into them, are marked "small only": only small
## ships may route through them. Strike craft, and the repair bays and
## wards an admiral drops, ask for small routes; corvettes and bigger
## ships, mining drones and motherships stay on lane and base dots.
## path(from, to, small) answers "how do I get from here to there?":
##   1. Find the nearest dot we may use at each end (nearest()).
##   2. Find the cheapest chain of links between those two dots
##      (node_path()), using "A*" (said "A-star"): a search that always
##      looks next at the dot with the smallest "distance flown so far +
##      straight-line distance still to go", so it heads for the goal and
##      rarely wastes time on detours. Each link costs its length.
##   3. Return the route as points: [from, ...the dots..., to].
## Answers from node_path() are remembered (cached) until a link is added.
## Steering around nearby asteroids on the way is the mover's job; the
## graph only makes sure a route exists.
##
## WHO USES IT: MapBuilderRoute builds it (add_node(), connect_nodes()); it
## is kept as World.map.route. WorldSetup sets clear_fn. path() is asked by
## AI pilots (PilotFlight, and PilotEscape.follow() when an escape ends:
## it plans the rest of the trip from the dot the escape led to), minions
## (World.lane_path_from() joins the lane through it, see WorldQueries),
## mining drones, repair bays, wards and the admiral's command desk
## (AdmiralCommand). PilotEscape also reads pos and jungle to choose the
## dots it aims at. main.gd prints node_count().
## The search's to-do list is a "heap" (RouteGraphHeap, next to this file).

## Where every dot is (index = dot number).
var pos: PackedVector2Array = PackedVector2Array()
## 1 = node lies inside the jungle (small ships only).
var jungle: PackedByteArray = PackedByteArray()
## adj[i] = Array of [neighbor:int, small_only:bool, cost:float]
## (every link from dot i: the dot at the other end, whether it is
## small-ships-only, and its length in world units).
var adj: Array = []
## Optional func(a: Vector2, b: Vector2) -> bool: true if a ship can fly
## straight from a to b (World sets it to an asteroid segment test). Used
## to enter/leave the graph at a node we can actually see.
var clear_fn: Callable = Callable()
## Remembered node_path() answers: key (from, to, small) -> the dot list.
var _cache := {}


## Add a dot at `p` (`in_jungle` = small ships only) and return its number.
func add_node(p: Vector2, in_jungle: bool) -> int:
	pos.append(p)
	jungle.append(1 if in_jungle else 0)
	adj.append([])
	return pos.size() - 1


## Link dots `a` and `b` both ways, costing the distance between them.
## `small_only` = only small ships may use this link. Linking a dot to
## itself does nothing. Forgets every remembered route (they may be
## shorter now).
func connect_nodes(a: int, b: int, small_only: bool) -> void:
	if a == b:
		return
	var cost := pos[a].distance_to(pos[b])
	(adj[a] as Array).append([b, small_only, cost])
	(adj[b] as Array).append([a, small_only, cost])
	_cache.clear()


## How many dots the graph has.
func node_count() -> int:
	return pos.size()


## Nearest node a ship of this kind may use, preferring one in clear line
## of sight. Playtest: the nearest node was often behind a rock wall, and
## ships next to the jungle pressed against it for minutes. So: of the 8
## nearest usable dots, nearest first, return the first one clear_fn says
## we can fly straight to; if none (or there is no clear_fn), the nearest.
## -1 if there are no usable dots. Big ships (`small` false) skip jungle
## dots.
func nearest(p: Vector2, small: bool) -> int:
	# Every usable dot with its (squared) distance, nearest first.
	var cands: Array = []
	for i in pos.size():
		if not small and jungle[i] == 1:
			continue
		cands.append([p.distance_squared_to(pos[i]), i])
	if cands.is_empty():
		return -1
	cands.sort_custom(func(x, y): return x[0] < y[0])
	# Prefer one we can see.
	if clear_fn.is_valid():
		for k in mini(8, cands.size()):
			var i: int = cands[k][1]
			if clear_fn.call(p, pos[i]):
				return i
	return cands[0][1]


## Node indices from a to b (inclusive), or empty if unreachable.
## The A* search described at the top. Big ships (`small` false) may not
## use small-only links or jungle dots. Answers are remembered.
func node_path(a: int, b: int, small: bool) -> PackedInt32Array:
	if a < 0 or b < 0:
		return PackedInt32Array()
	# Asked before? (The key packs a, b and small into one number.)
	var key := (a * 65536 + b) * 2 + (1 if small else 0)
	if _cache.has(key):
		return _cache[key]
	# Per dot: g = cheapest known cost from a (INF = not reached yet),
	# came = the dot we reached it from (-1 = none), closed = 1 once its
	# cheapest cost is final.
	var n := pos.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	# Binary heap of [f, node].
	# (f = cost so far + straight-line distance to b.)
	var heap: Array = []
	g[a] = 0.0
	RouteGraphHeap.push(heap, pos[a].distance_to(pos[b]), a)
	while not heap.is_empty():
		# Take the most promising dot. Skip it if it was already finished;
		# stop when we reach b.
		var cur: int = RouteGraphHeap.pop(heap)
		if closed[cur] == 1:
			continue
		if cur == b:
			break
		closed[cur] = 1
		# Try every link out of it that this ship may use.
		for e: Array in adj[cur]:
			var nb: int = e[0]
			if closed[nb] == 1:
				continue
			if e[1] and not small:
				continue
			if not small and jungle[nb] == 1:
				continue
			# A cheaper way to reach `nb`: remember it and add it to the heap.
			var ng: float = g[cur] + float(e[2])
			if ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				RouteGraphHeap.push(heap, ng + pos[nb].distance_to(pos[b]), nb)
	# Never reached b: no route (remembered too).
	var out := PackedInt32Array()
	if a != b and came[b] == -1:
		_cache[key] = out
		return out
	# Walk back from b to a along `came`, then turn the list around.
	var c := b
	while c != -1:
		out.append(c)
		if c == a:
			break
		c = came[c]
	out.reverse()
	_cache[key] = out
	return out


## World-space route from `from` to `to`. Empty if no route exists.
## Otherwise [from, ...the dots' positions..., to].
func path(from: Vector2, to: Vector2, small: bool) -> PackedVector2Array:
	var a := nearest(from, small)
	var b := nearest(to, small)
	var ids := node_path(a, b, small)
	var out := PackedVector2Array()
	if ids.is_empty():
		return out
	out.append(from)
	for i in ids:
		out.append(pos[i])
	out.append(to)
	return out
