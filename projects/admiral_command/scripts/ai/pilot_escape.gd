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
##   - note_unstick(): PilotFlight calls it every time its stuck timer fires.
##     The second fire within 25 seconds and 300 units of the first means
##     the plain unstick did not help, so it plans an escape.
##   - _plan_escape(): lays a grid of small cells over the rocks around the
##     ship, floods it from the ship's cell, and finds the nearest cell with
##     a clear line to one of the route graph's dots. The path to that cell
##     is pulled tight into a few waypoints. The search has a work budget
##     (WORK_MAX), so one plan never holds up the game for much more than
##     50 milliseconds.
##   - follow(): PilotFlight.travel() hands the controls to it while an
##     escape is on. It flies the waypoints slowly and exactly, then plans
##     the normal route again from the dot it was led to.
## An escape that makes no progress for 2 seconds is given up (and no new
## one is planned for 15 seconds); the plain unstick then carries on.
##
## WHO USES IT: PilotFlight (it makes one part per brain, asks is_active()
## and follow() at the top of travel(), and calls note_unstick() when its
## stuck timer fires). It reads the rocks (world.asteroids) and the route
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

## The most work (units) one plan may spend, both tries together (about 50
## milliseconds). Playtest: without a limit one plan took up to 0.4 s in a
## match (0.6 s in a test) when no cell saw a dot early, a freeze of 6 to 25
## frames. When the work is used up the search stops and the escape leads to the
## farthest cell reached, as when no cell sees a dot at all.
const WORK_MAX := 50000
## Work units for laying out one grid (see WORK_MAX).
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


## The stuck timer just fired. Count fires that happen close together in
## time (25 s) and place (300 units); the second one plans a way out of the
## pocket. `to` is the final goal of the trip.
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


## Plan a way out of the rocks around the ship. A grid of small cells (about
## the ship's size) is laid over a square 2,200 wide around it (the second
## try, `fine`, uses a square 1,000 wide with 6-unit cells); a cell is
## blocked when a rock, grown by the ship's radius, covers its centre. A
## flood search visits the free cells from the ship's cell, nearest first,
## until it reaches a cell with a clear straight line to one of the 8
## nearest route dots (or to the goal itself). Only about one cell in every
## few (TEST_GAP) is tested, and a cheap look along the grid (_ray_free())
## rules out most lines before the exact rock test. The path to that cell is
## pulled tight into a few waypoints (`_path`); when it has been flown, the
## route is planned again FROM that dot (the route graph alone joins at the
## nearest dot in sight, which can lie on the far side of a rock wall: the
## ship would press against the wall for ever, or be led back into the same
## notch). With no such cell, or when the work budget (WORK_MAX) is used up,
## it goes to the farthest cell reached. A plan usually costs a few
## milliseconds and never much more than 50, and only runs when a ship is
## stuck for the second time. `fine` is the second try for a tight notch
## (small cells and almost no margin around the rocks); `spent` is the work
## units the first try already used (the second try gets what is left).
func _plan_escape(ship: Ship, to: Vector2, fine := false, spent := 0) -> void:
	if spent + WORK_GRID >= WORK_MAX:
		return
	var world := ai.world
	var field := world.asteroids
	var p := ship.global_position
	var route := world.map.route
	var small := ship.is_small()
	# Step 1: the 8 nearest dots we may use, nearest first, then the goal.
	var order: Array = []
	for k in route.pos.size():
		if small or route.jungle[k] == 0:
			order.append([p.distance_squared_to(route.pos[k]), k])
	order.sort_custom(func(x, y): return x[0] < y[0])
	var cands := PackedVector2Array()
	for k in mini(8, order.size()):
		cands.append(route.pos[order[k][1]])
	cands.append(to)
	var half := 1100.0
	var cs := clampf(maxf(ship.radius * 1.2, half / 100.0), 12.0, 40.0)
	var grow := ship.radius + 4.0
	if fine:
		# Second try, for a tight notch: small cells and almost no margin.
		half = 500.0
		cs = 6.0
		grow = ship.radius + 0.4
	var n := int(2.0 * half / cs)
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
		if cur != s_idx and cc.distance_squared_to(p) > 10000.0:
			k_test += 1
			if k_test % stride == 0:
				# Out of work: stop here, the farthest cell reached will do.
				if _work_used(spent, head, looks, tests) > WORK_MAX:
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
	if found < 0:
		found = last
	# Step 5: no room to move (the ship is wedged tighter than a cell): try
	# again with finer cells, or give up.
	var fc := o + Vector2((float(found % n) + 0.5) * cs, (float(found / n) + 0.5) * cs)
	if found == s_idx or fc.distance_to(p) < 120.0:
		if not fine:
			_plan_escape(ship, to, true, _work_used(spent, head, looks, tests))
		return
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
	_path = pts
	_path_i = 0
	_time_left = 14.0 + 0.012 * fc.distance_to(p)
	_dot = found_dot
	_goal = to
	_best = INF
	_no_progress = 0.0


## The work units (see WORK_MAX) one try of _plan_escape() has used so far:
## the grid, the `cells` the flood has visited, the cheap `looks` and the
## exact line `tests`, on top of `spent` (the work of the first try; 0 for
## the first try itself).
func _work_used(spent: int, cells: int, looks: int, tests: int) -> int:
	return spent + WORK_GRID + cells * WORK_CELL + looks * WORK_RAY + tests * WORK_LINE


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
	# Step 1: count the waypoints we have reached.
	var reach := maxf(35.0, ship.radius * 2.0)
	while _path_i < _path.size() and p.distance_to(_path[_path_i]) < reach:
		_path_i += 1
		_best = INF
		_no_progress = 0.0
	# Step 2: the escape is over (all waypoints flown, out of time, or thrown
	# far off the path). Plan the rest of the way from the dot we were led to,
	# or from scratch, and start the stuck measurement afresh.
	if _path_i >= _path.size() or _time_left <= 0.0 or p.distance_to(_path[_path_i]) > 900.0:
		var done := _path_i >= _path.size()
		_path = PackedVector2Array()
		_time_left = 0.0
		if done and _dot != Vector2.INF:
			brain.path = brain.world.map.route.path(_dot, _goal, ship.is_small())
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
	# unstick run; no new escape for 15 s.
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
