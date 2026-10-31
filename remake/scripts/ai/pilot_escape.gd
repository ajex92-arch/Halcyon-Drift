class_name PilotEscape
extends RefCounted
## WHAT THIS IS: how an AI pilot's ship gets out of a pocket in the rocks (a
## part of PilotFlight). A strike craft sometimes ends up pressed into a
## notch of a rock wall or between rocks. The plain "stuck" handling (back
## off for a second, then plan the same route again) flies it straight back
## into the notch, again and again, for the rest of the match (playtest:
## 96 to 140 unsticks and 260 to 650 s of rock contact for one trapped ship,
## about one ship in every one or two 15-minute matches).
##
## HOW IT WORKS:
##   - note_unstick(): PilotFlight calls it every time the ship is stalled
##     (PilotFlight.stall()). The first stall retraces the ship's own track
##     (its breadcrumb trail, PilotTrail) back to a spot where it can join the
##     route graph again; the second within 25 seconds and 300 units of the
##     first means that did not help, so it plans an escape.
##   - plan_now(): PilotFlight calls it at once when the ship has no dot of
##     the route graph it can fly to (the route's first leg would end at a dot
##     that rocks hide), so the ship leaves the rocks first.
##   - _plan_escape(): lays a grid of small cells over the rocks around the
##     ship, floods it from the ship's cell, and finds the nearest cell with
##     a clear line to one of the route graph's dots (the cheapest ones to
##     join on the way to the goal). If that coarse try sees no dot at all, a
##     second try with a finer grid looks again, so that a narrow gap a ship
##     really passes is not missed. The path to the cell is pulled tight into
##     a few waypoints, and the brain's route is set to those waypoints and the
##     route on from their dot while the escape flies. The search has a work
##     budget (WORK_MAX), so one plan never holds up the game for much more
##     than 50 milliseconds.
##   - follow(): PilotFlight.travel() hands the controls to it while an
##     escape is on. It flies the waypoints slowly and exactly, then plans
##     the normal route again from the dot it was led to.
## An escape that makes no progress for 2 seconds is given up (and no new
## one is planned for 15 seconds); the plain unstick then carries on.
##
## WHO USES IT: PilotFlight (it makes one part per brain, asks is_active()
## and follow() at the top of travel(), calls note_unstick() when the ship is
## stalled and plan_now() when the ship has no way onto the route graph).
## It reads PilotFlight.trail and asks PilotFlight.can_join_route(). It reads the rocks (world.asteroids) and the route
## graph (world.map.route), and when an escape ends it sets the brain's
## route (PilotAI.path, path_i, path_goal).
##
## Words used here:
##   cell      one square of the search grid (about the ship's size).
##   dot       one stepping-stone point of the route graph (a "node").
##   flood     a breadth-first search: visit the nearest cells first, then
##             the cells next to those, and so on.
##   work unit how the planner counts its effort: about one microsecond on
##             the development PC. Counting work instead of reading the
##             clock makes a plan do the same thing on every PC (a match
##             with the same seed stays the same match).

## After plan_now() planned nothing, this many seconds pass before it tries
## again (a plan can cost a few milliseconds, and a ship in a closed pocket
## would ask once a second).
const PLAN_RETRY := 3.0
## A retrace flies back along the breadcrumb trail (PilotTrail), starting at
## the newest crumb that is at least this far (world units) from the ship.
const RETRACE_MIN := 40.0
## Seconds a retrace may take, besides 0.012 s per world unit of its length.
const RETRACE_TIME := 10.0
## An escape to a "farthest cell" (no route dot in sight from any cell the
## ship can reach) must lead at least this far (world units) from the ship; a
## ship in a smaller closed space stays where it is.
const FAR_MIN := 120.0
## Cells nearer than this (world units) to the ship are not tested for a clear
## line to a dot: the ship's own spot has none.
const TEST_MIN := 30.0
## The coarse try searches a square this wide on each side of the ship (world
## units) with cells of the ship's size...
const COARSE_HALF := 1100.0
## ...and a rock blocks the cells whose centre is within its radius plus the
## ship's radius plus this many world units.
const COARSE_MARGIN := 4.0
## The fine try (for a tight notch) searches a smaller square, this far (world
## units) from the ship on each side...
const FINE_HALF := 800.0
## ...with cells this small (world units)...
const FINE_CELL := 6.0
## ...and almost no margin around the rocks (world units).
const FINE_MARGIN := 0.4
## How many route dots a search tries to see from the cells of its flood (the
## cheapest ones to join on the way to the goal), besides the goal itself.
const CANDIDATE_DOTS := 8
## The most work (units) one plan may spend, both tries together (about 50
## milliseconds). Playtest: without a limit one plan took up to 0.4 s in a
## match (0.6 s in a test) when no cell saw a dot early, a freeze of 6 to 25
## frames. When the work is used up the search stops and the escape leads to the
## farthest cell reached, as when no cell sees a dot at all.
const WORK_MAX := 50000
## The least work units for laying out one grid (see WORK_MAX); a grid with
## many cells costs one unit for every 12 of them instead (see _search()).
const WORK_GRID := 4000
## Work units for each cell the flood visits (see WORK_MAX).
const WORK_CELL := 3
## Work units for each cheap look along the grid toward a dot (see
## _ray_free() and WORK_MAX).
const WORK_RAY := 3
## Work units for each exact rock-line test, AsteroidField.segment_hit()
## (see WORK_MAX).
const WORK_LINE := 25
## Roughly how far apart (world units) the tested cells are along the
## flood: one cell in every few is tested for a clear line, the number of
## cells being this distance divided by the cell size. Neighbouring cells
## see almost the same dots, so a denser test only costs more.
const TEST_GAP := 45.0
## How far (world units) the cheap look along the grid goes at most.
const RAY_LEN := 1100.0
## The distance (world units) between two spots the cheap look checks.
const RAY_STEP := 28.0

## The pilot brain this part belongs to (we read its route and world). It is
## reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so
## each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part (through its
## PilotFlight) with a normal (strong) link. If the part held the brain
## strongly too, each would keep the other alive forever and Godot could
## never free them (a memory leak). A weak link points at the brain without
## keeping it alive.
var _ai_ref: WeakRef
## The escape waypoints (world positions), in the order we fly them. Empty
## = no escape planned.
var _path := PackedVector2Array()
## Which waypoint of `_path` we are flying toward (a position in the list).
var _path_i := 0
## Seconds left to follow the escape path (0 = no escape is on).
var _time_left := 0.0
## True while `_path` is a retrace (the ship's own breadcrumb trail flown
## backwards) and not a planned escape: it ends as soon as the ship can join
## the route graph again (see follow()).
var _retrace := false
## The route dot the escape leads to (Vector2.INF = it leads to no dot, only
## to the farthest free cell). The normal route is planned from it.
var _dot := Vector2.INF
## The final goal of the trip, for planning the route after the escape.
var _goal := Vector2.INF
## The closest we have come to the current waypoint (world units; INF =
## none yet).
var _best := INF
## Seconds without real progress toward the current waypoint.
var _no_progress := 0.0
## Game time (seconds) before which no new escape is planned (it is set
## after an escape had to be given up).
var _cool_until := 0.0
## Game time (seconds) before which plan_now() does not try again (it is set
## after a plan that found nothing).
var _retry_at := 0.0
## How many times in a row the stuck timer fired close together in time and
## place.
var _fires := 0
## Where the stuck timer last fired (world position).
var _fire_pos := Vector2.INF
## Game time (seconds) when the stuck timer last fired.
var _fire_at := -999.0
## A reusable list that the asteroid field fills with nearby rock numbers.
var _rocks := PackedInt32Array()


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## Is an escape path on right now? (PilotFlight then calls follow().)
func is_active() -> bool:
	return _time_left > 0.0


## The ship is stalled (PilotFlight.stall()). Count stalls that happen close
## together in time (25 s) and place (300 units). The first one retraces the
## ship's own track back to a spot where it can join the route graph again
## (_start_retrace()); the second plans a way out of the pocket. `to` is the
## final goal of the trip.
func note_unstick(ship: Ship, to: Vector2) -> void:
	var now := ai.world.time
	var p := ship.global_position
	if now - _fire_at < 25.0 and p.distance_to(_fire_pos) < 300.0:
		_fires += 1
	else:
		_fires = 1
	_fire_at = now
	_fire_pos = p
	if _fires >= 2 and now >= _cool_until:
		_plan_escape(ship, to)
	elif _fires == 1:
		_start_retrace(ship, to)


## Fly back along the ship's breadcrumb trail (PilotFlight.trail) instead of
## backing off a second and planning the same route again: the ship has been
## on every crumb, so the way back is free. The retrace is the escape path
## (follow() flies it slowly and exactly) and ends at the first crumb where
## the ship can join the route graph again. Nothing happens when the ship can
## join it right here (the plain unstick is enough) or the trail is empty.
func _start_retrace(ship: Ship, to: Vector2) -> void:
	var flight := ai.flight
	if flight.can_join_route(ship, to):
		return
	var back := flight.trail.back_from(ship.global_position, RETRACE_MIN)
	if back.is_empty():
		return
	var length := ship.global_position.distance_to(back[0])
	for i in range(1, back.size()):
		length += back[i - 1].distance_to(back[i])
	_path = back
	_path_i = 0
	_time_left = RETRACE_TIME + 0.012 * length
	_dot = Vector2.INF
	_goal = to
	_best = INF
	_no_progress = 0.0
	_retrace = true
	_publish_route(ship)


## Plan an escape now, without waiting for the stuck timer to fire twice.
## PilotFlight asks for it when the ship has no dot it can fly to (RouteGraph
## .entry() found none): flying at a dot that rocks hide only presses the ship
## against them. `to` is the final goal of the trip. Returns true when an
## escape path is on. Not while the cool-down after a given-up escape runs, nor
## within PLAN_RETRY seconds of a plan that found nothing.
func plan_now(ship: Ship, to: Vector2) -> bool:
	var now := ai.world.time
	if now < _cool_until or now < _retry_at:
		return false
	_plan_escape(ship, to)
	if not is_active():
		_retry_at = now + PLAN_RETRY
		return false
	return true


## Plan a way out of the rocks around the ship (see HOW IT WORKS at the top),
## in up to two tries. The first (a coarse grid over a square 2,200 wide)
## searches for a cell with a clear straight line to one of the dots the
## route would use. When it finds no such cell anywhere it can reach (it cannot
## see narrow gaps: a cell is blocked when a rock, grown by the ship's radius
## and COARSE_MARGIN, covers its centre), the second try looks again with a fine
## grid (small cells and almost no margin around the rocks, FINE_CELL and
## FINE_MARGIN) over a smaller square, before the ship settles for the farthest
## cell of either try. Any exit to a dot is taken, however near (a ship wedged
## in a notch often has its way out 100 units away); a farthest cell must be
## FAR_MIN away to be worth flying to. When it plans a way, the escape path and
## the route that goes on from its dot are set (_start()).
func _plan_escape(ship: Ship, to: Vector2) -> void:
	var best := _search(ship, to, false, 0)
	if best["dot"] == Vector2.INF:
		var fine := _search(ship, to, true, int(best["work"]))
		if fine["dot"] != Vector2.INF or float(fine["dist"]) > float(best["dist"]):
			best = fine
	var pts: PackedVector2Array = best["pts"]
	if pts.is_empty() or (best["dot"] == Vector2.INF and float(best["dist"]) < FAR_MIN):
		return
	_start(ship, to, pts, best["dot"], float(best["dist"]))


## One try of the search for a way out (see _plan_escape()): `fine` picks the
## fine grid, `spent` is the work units the first try already used (this try
## gets what is left). A grid of cells is laid over a square around the ship; a
## cell is blocked when a rock, grown by the ship's radius plus a margin,
## covers its centre. A flood search visits the free cells from the ship's
## cell, nearest first, until it reaches a cell with a clear straight line to
## one of the wanted dots (_candidates()) or to the goal itself. Only about
## one cell in every few (TEST_GAP) is tested, and a cheap look along the grid
## (_ray_free()) rules out most lines before the exact rock test. The path to
## that cell is pulled tight into a few waypoints. With no such cell, or when
## the work budget (WORK_MAX) is used up, the path goes to the farthest cell
## reached. Answers a Dictionary: "pts" (the waypoints, empty when the ship has
## no room to move), "dot" (the dot the path leads to, Vector2.INF when it leads
## only to the farthest cell), "dist" (from the ship to the end of the path,
## world units) and "work" (the work units used so far).
func _search(ship: Ship, to: Vector2, fine: bool, spent: int) -> Dictionary:
	var half := COARSE_HALF
	var cs := clampf(maxf(ship.radius * 1.2, half / 100.0), 12.0, 40.0)
	var grow := ship.radius + COARSE_MARGIN
	if fine:
		half = FINE_HALF
		cs = FINE_CELL
		grow = ship.radius + FINE_MARGIN
	var n := int(2.0 * half / cs)
	# The work of laying out the grid grows with its cells.
	var grid := maxi(WORK_GRID, n * n / 12)
	var none := {"pts": PackedVector2Array(), "dot": Vector2.INF, "dist": 0.0, "work": spent}
	if spent + grid >= WORK_MAX:
		return none
	var field := ai.world.asteroids
	var p := ship.global_position
	# Step 1: the dots we want to see: the cheapest ones to join, then the goal.
	var cands := _candidates(ship, to)
	var o := p - Vector2(half, half)
	# Step 2: the blocked cells.
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	field.nearby(p, half * 1.5, _rocks)
	for r in _rocks:
		var rc := field.pos[r]
		var rr := field.rad[r] * 0.95 + grow
		if absf(rc.x - p.x) > half + rr or absf(rc.y - p.y) > half + rr:
			continue
		var j0 := maxi(0, int((rc.y - rr - o.y) / cs))
		var j1 := mini(n - 1, int((rc.y + rr - o.y) / cs))
		for j in range(j0, j1 + 1):
			var dy := o.y + (float(j) + 0.5) * cs - rc.y
			var rem := rr * rr - dy * dy
			if rem <= 0.0:
				continue
			var dx := sqrt(rem)
			var ia := maxi(0, int(ceil((rc.x - dx - o.x) / cs - 0.5)))
			var ib := mini(n - 1, int(floor((rc.x + dx - o.x) / cs - 0.5)))
			for i in range(ia, ib + 1):
				blocked[j * n + i] = 1
	# Step 3: the start cell, and a free disc around it (a ship pressed
	# against a rock sits inside the grown rock by a few units).
	var si := clampi(int((p.x - o.x) / cs), 0, n - 1)
	var sj := clampi(int((p.y - o.y) / cs), 0, n - 1)
	for j in range(maxi(0, sj - 3), mini(n, sj + 4)):
		for i in range(maxi(0, si - 3), mini(n, si + 4)):
			blocked[j * n + i] = 0
	# Step 4: flood the free cells, nearest first, and test about one cell in
	# every few for a clear line to a wanted point, until the work is used up
	# (`looks` and `tests` count the cheap looks and the exact line tests).
	var came := PackedInt32Array()
	came.resize(n * n)
	came.fill(-2)
	var queue := PackedInt32Array()
	queue.resize(n * n)
	var s_idx := sj * n + si
	var head := 0
	var tail := 1
	queue[0] = s_idx
	came[s_idx] = -1
	var found := -1
	var found_dot := Vector2.INF
	var last := s_idx
	var k_test := 0
	var stride := maxi(1, roundi(TEST_GAP / cs))
	var looks := 0
	var tests := 0
	var dxs := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
	var dys := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])
	while head < tail and found < 0:
		var cur := queue[head]
		head += 1
		last = cur
		var ci := cur % n
		var cj := cur / n
		var cc := o + Vector2((float(ci) + 0.5) * cs, (float(cj) + 0.5) * cs)
		if cur != s_idx and cc.distance_squared_to(p) > TEST_MIN * TEST_MIN:
			k_test += 1
			if k_test % stride == 0:
				# Out of work: stop here, the farthest cell reached will do.
				if _work_used(spent + grid, head, looks, tests) > WORK_MAX:
					break
				for q in cands:
					looks += 1
					if not _ray_free(blocked, n, o, cs, cc, q):
						continue
					tests += 1
					if field.segment_hit(cc, q, ship.radius + 10.0).is_empty():
						found = cur
						found_dot = q
						break
				if found >= 0:
					break
		for k in 8:
			var ni := ci + dxs[k]
			var nj := cj + dys[k]
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nb := nj * n + ni
			if came[nb] != -2 or blocked[nb] == 1:
				continue
			# No cutting corners on a diagonal step.
			if k >= 4 and (blocked[cj * n + ni] == 1 or blocked[nj * n + ci] == 1):
				continue
			came[nb] = cur
			queue[tail] = nb
			tail += 1
	var work := _work_used(spent + grid, head, looks, tests)
	if found < 0:
		found = last
	# Step 5: no room to move (the ship is wedged tighter than a cell).
	if found == s_idx:
		none["work"] = work
		return none
	# Step 6: walk back from the goal cell to the start, then pull the cell
	# path tight: from each point jump to the farthest later cell that can be
	# reached in a straight line over free cells.
	var cells := PackedInt32Array()
	var cur2 := found
	while cur2 != -1:
		cells.append(cur2)
		cur2 = came[cur2]
	cells.reverse()
	var pts := PackedVector2Array()
	var a := 0
	while a < cells.size() - 1:
		var b := cells.size() - 1
		while b > a + 1 and not _grid_line_free(blocked, n, cells[a], cells[b]):
			b -= 1
		pts.append(o + Vector2((float(cells[b] % n) + 0.5) * cs, (float(cells[b] / n) + 0.5) * cs))
		a = b
	var fc := o + Vector2((float(found % n) + 0.5) * cs, (float(found / n) + 0.5) * cs)
	return {"pts": pts, "dot": found_dot, "dist": fc.distance_to(p), "work": work}


## The points a way out of the rocks should lead the ship to see: the
## CANDIDATE_DOTS route dots it may use that are cheapest to join on the way to
## the goal ("distance from the ship to the dot" + "cost of the rest of the
## route", as RouteGraph.entry() weighs them), topped up with the nearest dots
## when fewer than that are in range; then the goal itself.
func _candidates(ship: Ship, to: Vector2) -> PackedVector2Array:
	var route := ai.world.map.route
	var p := ship.global_position
	var small := JungleBigFeature.route_small(ship)
	var costs := route.costs_to(route.nearest(to, small), small)
	var order: Array = []
	for k in route.pos.size():
		if small or route.jungle[k] == 0:
			var d := p.distance_to(route.pos[k])
			if not costs.is_empty() and costs[k] != INF and d <= RouteGraph.ENTRY_RANGE:
				order.append([d + costs[k], k])
			else:
				order.append([RouteGraph.ENTRY_RANGE * 1000.0 + d, k])
	order.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var cands := PackedVector2Array()
	for k in mini(CANDIDATE_DOTS, order.size()):
		cands.append(route.pos[order[k][1]])
	cands.append(to)
	return cands


## Start flying the planned way out: `pts` are its waypoints, `dot` the route
## dot it leads to (Vector2.INF = none), `dist` how far the end of the path is
## from the ship, `to` the final goal of the trip. The brain gets a route at
## once, the waypoints and the route that goes on from the dot, so that a ship
## that flies an escape still has a plan for whatever reads it (the audit).
func _start(ship: Ship, to: Vector2, pts: PackedVector2Array, dot: Vector2, dist: float) -> void:
	_path = pts
	_path_i = 0
	_time_left = 14.0 + 0.012 * dist
	_dot = dot
	_goal = to
	_best = INF
	_no_progress = 0.0
	_retrace = false
	_publish_route(ship)


## Put the escape's waypoints, and the route from the dot it leads to, in the
## brain's route (PilotAI.path), which travel() does not touch while the
## escape is on.
func _publish_route(ship: Ship) -> void:
	var brain := ai
	var route := PackedVector2Array(_path)
	if _dot != Vector2.INF:
		route.append_array(brain.world.map.route.path(_dot, _goal, JungleBigFeature.route_small(ship)))
	brain.path = route
	brain.path_i = 0
	brain.path_goal = _goal


## The work units (see WORK_MAX) one try of _search() has used so far: `spent`
## (the grid, and the work of the first try for the second try; 0 for the
## first try itself) plus the `cells` the flood has visited, the cheap `looks`
## and the exact line `tests`.
func _work_used(spent: int, cells: int, looks: int, tests: int) -> int:
	return spent + cells * WORK_CELL + looks * WORK_RAY + tests * WORK_LINE


## A cheap look from `a` toward `b` over the grid (`n` cells wide, `o` the
## world position of its corner, `cs` the cell size, `blocked` a 1 for each
## blocked cell). False when the straight line, checked every RAY_STEP units
## for at most RAY_LEN units, runs into a blocked cell: a rock is in the
## way. True means "may be clear" (or the look left the grid); the exact
## test, AsteroidField.segment_hit(), then decides. About a tenth of the
## cost of that test, and it rules out most lines.
func _ray_free(blocked: PackedByteArray, n: int, o: Vector2, cs: float, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return true
	var steps := int(minf(dist, RAY_LEN) / RAY_STEP)
	# One step of the look, in cells.
	var u := d / dist * (RAY_STEP / cs)
	var gx := (a.x - o.x) / cs
	var gy := (a.y - o.y) / cs
	for s in steps:
		gx += u.x
		gy += u.y
		var ix := int(gx)
		var iy := int(gy)
		if ix < 0 or iy < 0 or ix >= n or iy >= n:
			return true
		if blocked[iy * n + ix] == 1:
			return false
	return true


## Are all grid cells on the straight line between cells `a` and `b` (cell
## numbers in a grid `n` cells wide; `blocked` holds a 1 for each blocked
## cell) free?
func _grid_line_free(blocked: PackedByteArray, n: int, a: int, b: int) -> bool:
	var x0 := a % n
	var y0 := a / n
	var x1 := b % n
	var y1 := b / n
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for s in range(1, steps):
		var x := x0 + int(round(float(x1 - x0) * float(s) / float(steps)))
		var y := y0 + int(round(float(y1 - y0) * float(s) / float(steps)))
		if blocked[y * n + x] == 1:
			return false
	return true


## Fly the escape path slowly and exactly. Returns true while it has the
## controls. Returns false (and plans the route again) when the path is
## finished, timed out or no longer makes sense.
func follow(ship: Ship) -> bool:
	var brain := ai
	var c := ship.controls
	var p := ship.global_position
	_time_left -= 1.0 / 60.0
	# Step 1: count the waypoints we have reached. A retrace is over at the
	# first crumb where the ship can join the route graph again.
	var reach := maxf(35.0, ship.radius * 2.0)
	var reached := false
	while _path_i < _path.size() and p.distance_to(_path[_path_i]) < reach:
		_path_i += 1
		_best = INF
		_no_progress = 0.0
		reached = true
	if reached and _retrace and _path_i < _path.size() and brain.flight.can_join_route(ship, _goal):
		_path_i = _path.size()
	# Step 2: the escape is over (all waypoints flown, out of time, or thrown
	# far off the path). Plan the rest of the way from the dot we were led to,
	# or from scratch, and start the stuck measurement afresh.
	if _path_i >= _path.size() or _time_left <= 0.0 or p.distance_to(_path[_path_i]) > 900.0:
		var done := _path_i >= _path.size()
		_path = PackedVector2Array()
		_time_left = 0.0
		if done and _dot != Vector2.INF:
			brain.path = brain.world.map.route.path(_dot, _goal, JungleBigFeature.route_small(ship))
			brain.path_i = 0
			brain.path_goal = _goal
		else:
			brain.path = PackedVector2Array()
			brain.path_goal = Vector2.INF
		brain.flight.reset_progress()
		return false
	var wp := _path[_path_i]
	# Step 3: no progress toward this waypoint for 2 s means the path cannot
	# be flown (a gap too tight for the real ship). Give up and let the plain
	# unstick run; no new planned escape for 15 s (a retrace that fails does
	# not hold the planner back).
	var dwp := p.distance_to(wp)
	if dwp < _best - 15.0:
		_best = dwp
		_no_progress = 0.0
	else:
		_no_progress += 1.0 / 60.0
		if _no_progress > 2.0:
			_path = PackedVector2Array()
			_time_left = 0.0
			_best = INF
			_no_progress = 0.0
			if not _retrace:
				_cool_until = brain.world.time + 15.0
			brain.path = PackedVector2Array()
			brain.path_goal = Vector2.INF
			return false
	# Step 4: fly to the waypoint: thrust only when lined up, never faster
	# than 170 units a second, kill sideways drift, no boost.
	var err := absf(Util.ang_diff(ship.rotation, (wp - p).angle()))
	var speed := ship.velocity.length()
	var fwd := 0.45 if err < 0.5 else (0.1 if err < 1.2 else 0.0)
	if speed > 170.0:
		fwd = minf(fwd, -0.4 if speed > 260.0 else 0.0)
	c.face_point = wp
	c.forward = fwd
	var lat := ship.velocity.dot(Util.starboard_of(ship.rotation))
	c.strafe = clampf(lat / 80.0, -1.0, 1.0) if err < 0.5 else 0.0
	c.boost = false
	return true
