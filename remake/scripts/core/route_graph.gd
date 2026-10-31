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
## A pilot's ship asks with its radius (path(from, to, small, radius)). The
## way onto the road map is then not the nearest dot but the cheapest one the
## ship can really fly to (entry()): of the dots within ENTRY_RANGE, the one
## with the smallest "distance to it + cost of the rest of the route" whose
## straight line is clear of every rock by the ship's radius plus
## ENTRY_MARGIN. When there is none, path() answers an empty route and sets
## no_entry, so the pilot gets out of the rocks first instead of flying at a
## dot that rocks hide. costs_to() gives the "cost of the rest of the route".
## A pilot also passes the dots it was stalled at (`banned`): the route goes
## round them for a while, for example through another jungle gate.
##
## WHO USES IT: MapBuilderRoute builds it (add_node(), connect_nodes()); it
## is kept as World.map.route. WorldSetup sets clear_fn and clear_pad_fn.
## path() is asked by AI pilots (PilotFlight, through JungleBigFeature
## .plan_route(), with the ship's radius; and PilotEscape.follow() when an
## escape ends: it plans the rest of the trip from the dot the escape led
## to), minions (World.lane_path_from() joins the lane through it, see
## WorldQueries), mining drones, repair bays, wards and the admiral's command
## desk (AdmiralCommand), these without a radius. PilotEscape also reads pos
## and jungle to choose the dots it aims at. main.gd prints node_count().
## The search's to-do list is a "heap" (RouteGraphHeap, next to this file).

## How far (world units) from a ship a dot may be and still serve as its way
## onto the road map (see entry()).
const ENTRY_RANGE := 2500.0
## The most dots entry() tests for a clear flight, cheapest first. A test is
## one asteroid line query, so this keeps a ship that sits in a pocket from
## costing much.
const ENTRY_TRIES := 12
## How far (world units) beyond its own radius a ship's flight to an entry dot
## must stay from every rock.
const ENTRY_MARGIN := 6.0
## The flight to an entry dot is tested from this far (world units) along the
## line, not from the ship itself: a ship pressed against a rock is inside the
## rock's margin, and its first few units would call every line blocked by
## the very rock it is leaving.
const ENTRY_START := 12.0

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
## Optional func(a: Vector2, b: Vector2, pad: float) -> bool: true if a ship
## can fly straight from a to b keeping `pad` world units from every rock
## (World sets it to an asteroid segment test). Used to pick the dot a ship
## enters the graph at (entry()).
var clear_pad_fn: Callable = Callable()
## True when the last path() call that was given a ship radius found no dot
## the ship can fly to (so its route is empty), as opposed to an empty route
## for want of any way between the dots. PilotFlight reads it right after
## asking.
var no_entry := false
## Remembered node_path() answers: key (from, to, small) -> the dot list.
var _cache := {}
## Remembered costs_to() answers: key (to, small) -> the cost table.
var _cost_cache := {}


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
	_cost_cache.clear()


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
## use small-only links or jungle dots. Answers are remembered, except when
## some dots are `banned`: the route then goes round them (a ban never applies
## to the dots `a` and `b`) and is not remembered.
func node_path(a: int, b: int, small: bool, banned := PackedInt32Array()) -> PackedInt32Array:
	if a < 0 or b < 0:
		return PackedInt32Array()
	# Asked before? (The key packs a, b and small into one number.)
	var key := (a * 65536 + b) * 2 + (1 if small else 0)
	var use_cache := banned.is_empty()
	if use_cache and _cache.has(key):
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
			if nb != b and banned.has(nb):
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
		if use_cache:
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
	if use_cache:
		_cache[key] = out
	return out


## The cost of the cheapest chain of links from every dot to dot `b` (index =
## dot number, INF = no way; the cost is the sum of the link lengths, in world
## units). A search from `b` outwards that follows the same rules as
## node_path() (big ships may not use small-only links or jungle dots). It is
## what lets entry() weigh every possible first dot at once. Answers are
## remembered until a link is added. An empty table for no dot (`b` below 0).
func costs_to(b: int, small: bool) -> PackedFloat32Array:
	if b < 0:
		return PackedFloat32Array()
	var key := b * 2 + (1 if small else 0)
	if _cost_cache.has(key):
		return _cost_cache[key]
	# g = cheapest known cost to b (INF = not reached yet); closed = 1 once final.
	var n := pos.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap: Array = []
	g[b] = 0.0
	RouteGraphHeap.push(heap, 0.0, b)
	while not heap.is_empty():
		var cur: int = RouteGraphHeap.pop(heap)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		for e: Array in adj[cur]:
			var nb: int = e[0]
			if closed[nb] == 1:
				continue
			if e[1] and not small:
				continue
			if not small and jungle[nb] == 1:
				continue
			var ng: float = g[cur] + float(e[2])
			if ng < g[nb]:
				g[nb] = ng
				RouteGraphHeap.push(heap, ng, nb)
	_cost_cache[key] = g
	return g


## The dot a ship of radius `radius` at `p` should fly to first to join the
## road map on its way to dot `b`, or -1 when there is none. Of the usable
## dots within ENTRY_RANGE, the cheapest first ("distance to the dot" + "cost
## of the rest of the way to b", see costs_to()), the first whose straight
## line is clear of every rock by the radius plus ENTRY_MARGIN (at most
## ENTRY_TRIES are tested). Big ships (`small` false) skip jungle dots, and no
## dot in `banned` is used (PilotFlight bans a dot it was flying to when the
## ship got stalled on the way). Without a clear_pad_fn it is just nearest().
func entry(p: Vector2, b: int, small: bool, radius: float, banned := PackedInt32Array()) -> int:
	if b < 0:
		return -1
	if not clear_pad_fn.is_valid():
		return nearest(p, small)
	# Step 1: every usable dot in range that has a way on to b, with its total
	# cost, cheapest first (equal costs: the lower dot number).
	var costs := costs_to(b, small)
	var cands: Array = []
	for i in pos.size():
		if (not small and jungle[i] == 1) or costs[i] == INF or banned.has(i):
			continue
		var d := p.distance_to(pos[i])
		if d <= ENTRY_RANGE:
			cands.append([d + costs[i], i])
	cands.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	# Step 2: the first one the ship can fly to. The line is tested from
	# ENTRY_START along it (see there).
	var pad := radius + ENTRY_MARGIN
	for k in mini(ENTRY_TRIES, cands.size()):
		var i: int = cands[k][1]
		var d := p.distance_to(pos[i])
		if d <= ENTRY_START or clear_pad_fn.call(p + (pos[i] - p) * (ENTRY_START / d), pos[i], pad):
			return i
	return -1


## The number of the dot at world position `p` (the position of a route
## waypoint), or -1 when no dot is within a unit of it.
func dot_at(p: Vector2) -> int:
	for i in pos.size():
		if pos[i].distance_squared_to(p) < 1.0:
			return i
	return -1


## World-space route from `from` to `to`. Empty if no route exists.
## Otherwise [from, ...the dots' positions..., to]. With a ship `radius` above 0
## the way onto the map is entry() (the cheapest dot the ship can fly to), and
## when there is none the route is empty and no_entry is true; with 0 it is the
## nearest dot, as for minions and drones. The dots in `banned` are not used: not as the way onto the map and not on the
## way (the route goes round them; with every route cut it is empty).
func path(from: Vector2, to: Vector2, small: bool, radius: float = 0.0, banned := PackedInt32Array()) -> PackedVector2Array:
	var b := nearest(to, small)
	var a: int
	no_entry = false
	if radius > 0.0:
		a = entry(from, b, small, radius, banned)
		no_entry = a < 0 and b >= 0
	else:
		a = nearest(from, small)
	var ids := node_path(a, b, small, banned)
	var out := PackedVector2Array()
	if ids.is_empty():
		return out
	out.append(from)
	for i in ids:
		out.append(pos[i])
	out.append(to)
	return out
