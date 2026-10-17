extends RefCounted
## WHAT THIS IS: the "chokes" half of the map check (tests/map_check.gd). A
## choke is the narrow gap at every jungle entrance: it is meant to let strike
## craft in and keep corvettes and bigger ships out. This works out, for
## every entrance, the biggest ship that can still get through, and checks it
## against the ship sizes in Ships.
##
## HOW IT WORKS: a ship is a circle (its radius is in Ships.HULLS) and a rock
## is a circle. A circle of radius R fits through a gap when its centre can
## stay at least (rock radius + R) from every rock the whole way. For one
## entrance we look at a strip of space across the gate, from the open lane
## outside it to the jungle point just inside it (the entrance's `lane`,
## `edge` and `inside` points). We cut the strip into thin slices; in each
## slice every rock forbids a stretch of the slice (where a centre of radius
## R would touch it), and what is left are the free stretches. R can pass if
## free stretches of neighbouring slices overlap all the way along. Trying
## bigger and bigger R (halving the search) gives the biggest R that passes:
## the "passable radius" of that gate. A gate between two rocks whose edges
## are CHOKE_GAP apart has a passable radius of CHOKE_GAP / 2 (43 for 86).
##
## Two sets of rocks are tried, because the game keeps two sizes for a rock:
##   nominal   MapInfo's rocks at their drawn radius. This is what the plan
##             promises ("a choke 86 wide").
##   physical  the AsteroidField's collision circles in the running match
##             (smaller by 5%, and a few rocks grown by AsteroidField's gap
##             sealing). This is what a ship really bumps into.
##
## WHO USES IT: tests/map_check.gd. It uses add() and check() of
## tests/lib/map_check_layout.gd.

const Layout := preload("res://tests/lib/map_check_layout.gd")

## How far (world units) outside the corridor's edge the strip starts, in
## the open lane.
const LANE_SIDE := 250.0
## How far (world units) to each side of the entrance line the strip reaches.
const HALF_WIDTH := 300.0
## The distance between two slices of the strip (world units).
const SLICE := 2.0
## The biggest ship radius tried (world units).
const SEARCH_MAX := 160.0
## The search stops when the answer is known to this many world units.
const SEARCH_STEP := 0.05
## Only rocks this close (world units) to an entrance's edge point can matter.
const NEAR := 900.0


## Check every entrance of the map. Adds rows, and puts the passable radii
## into `nums["chokes"]`. `strict_physical` makes "the physical gate lets a
## corvette through" a failure; otherwise it is only a warning.
static func chokes(w: World, rows: Array, nums: Dictionary, strict_physical: bool) -> void:
	var info := w.map
	var radii := ship_radii()
	var strike: float = radii["strike"]
	var corvette: float = radii["corvette"]
	var sets := _rock_sets(w)
	var nominal: Array = []
	var physical: Array = []
	var shut: Array = []
	var narrow_ends: Array = []
	var per_gate: Array = []
	for e: Dictionary in info.entrances:
		var fr := _frame(e)
		var rn := _strip_rocks(sets["nominal"], fr)
		var rp := _strip_rocks(sets["physical"], fr)
		var pn := pass_radius(rn, fr["u0"], fr["u1"])
		var pp := pass_radius(rp, fr["u0"], fr["u1"])
		nominal.append(pn)
		physical.append(pp)
		per_gate.append([roundi((e["edge"] as Vector2).x), roundi((e["edge"] as Vector2).y), snappedf(pn, 0.1), snappedf(pp, 0.1)])
		# A gate that stops a corvette must do it at the gate, not because
		# the open space at either end of the strip is too small for one.
		if not _ends_free(rn, fr["u0"], fr["u1"], corvette) or not _ends_free(rp, fr["u0"], fr["u1"], corvette):
			narrow_ends.append("(%d,%d)" % [roundi((e["edge"] as Vector2).x), roundi((e["edge"] as Vector2).y)])
	var n := nominal.size()
	var nom_lo := _min(nominal)
	var nom_hi := _max(nominal)
	var phys_lo := _min(physical)
	var phys_hi := _max(physical)
	# The gates that break the plan, named by where they cross the corridor's
	# edge: too tight for a strike craft, or loose enough for a corvette.
	var tight: Array = []
	var loose: Array = []
	for i in n:
		var at: Array = per_gate[i]
		if nominal[i] < strike or physical[i] < strike:
			tight.append("(%d,%d)" % [at[0], at[1]])
		if nominal[i] >= corvette:
			loose.append("(%d,%d)" % [at[0], at[1]])
	# The plan: a strike craft fits, a corvette does not.
	var strike_ok := n > 0 and tight.is_empty()
	var stop_nominal := n > 0 and loose.is_empty() and narrow_ends.is_empty()
	Layout.check(rows, "gates let strike craft through", strike_ok,
		"%d gates; passable radius %.1f to %.1f (as planned), %.1f to %.1f (as built); the biggest strike craft has radius %d%s" % [n, nom_lo, nom_hi, phys_lo, phys_hi, int(strike), "" if tight.is_empty() else "; too tight: " + ", ".join(tight.slice(0, 6))])
	Layout.check(rows, "gates stop corvettes (as planned)", stop_nominal,
		"passable radius at most %.1f; the smallest corvette has radius %d%s%s" % [nom_hi, int(corvette), "" if loose.is_empty() else "; too loose: " + ", ".join(loose.slice(0, 6)),
			"" if narrow_ends.is_empty() else "; open space too narrow at the ends of " + ", ".join(narrow_ends.slice(0, 4))])
	# The game: do the rocks a ship really bumps into keep a corvette out?
	for i in n:
		if physical[i] >= corvette:
			shut.append(i)
	var detail := "as built the passable radius is %.1f to %.1f against a corvette's %d" % [phys_lo, phys_hi, int(corvette)]
	if shut.is_empty():
		Layout.add(rows, "pass", "gates stop corvettes (as built)", detail)
	else:
		detail += "; %d of %d gates would let a corvette-sized ship squeeze through" % [shut.size(), n]
		Layout.add(rows, "fail" if strict_physical else "warn", "gates stop corvettes (as built)", detail)
	nums["chokes"] = {"gates": n, "strike_radius": strike, "corvette_radius": corvette, "choke_gap": MapLayout.CHOKE_GAP,
		"nominal": {"min": snappedf(nom_lo, 0.1), "max": snappedf(nom_hi, 0.1)}, "physical": {"min": snappedf(phys_lo, 0.1), "max": snappedf(phys_hi, 0.1)},
		"corvette_fits_as_built": shut.size(), "per_gate_x_y_nominal_physical": per_gate}


## The biggest ship radius among strike craft (size class 0) and the smallest
## among corvettes (size class 1), read from Ships.HULLS: {"strike",
## "corvette"}.
static func ship_radii() -> Dictionary:
	var strike := 0.0
	var corvette := INF
	for id: String in Ships.HULLS:
		var d: Dictionary = Ships.HULLS[id]
		if int(d["size"]) == Rules.SIZE_SMALL:
			strike = maxf(strike, float(d["radius"]))
		elif int(d["size"]) == Rules.SIZE_MEDIUM:
			corvette = minf(corvette, float(d["radius"]))
	return {"strike": strike, "corvette": corvette}


## The two sets of rocks as lists of Vector3(x, y, radius): "nominal" is the
## map's own rocks (MapInfo); "physical" is the field in the running match,
## each rock at the size of its collision circle (read back from the physics
## engine, so the 5% the game takes off is not written in here).
static func _rock_sets(w: World) -> Dictionary:
	var nominal := PackedVector3Array()
	for i in w.map.rock_pos.size():
		nominal.append(Vector3(w.map.rock_pos[i].x, w.map.rock_pos[i].y, w.map.rock_r[i]))
	var physical := PackedVector3Array()
	var field := w.asteroids
	for i in field.pos.size():
		if field.alive[i] == 1:
			physical.append(Vector3(field.pos[i].x, field.pos[i].y, float(PhysicsServer2D.shape_get_data(field.shapes[i]))))
	return {"nominal": nominal, "physical": physical}


## The strip across entrance `e`, as a frame: origin `o` (where the entrance
## crosses the corridor's edge), unit vector `u` along the way in (from the
## lane towards the jungle), `v` across it, and where the strip starts and
## ends along `u`: `u0` in the open lane, `u1` at the jungle point `inside`.
static func _frame(e: Dictionary) -> Dictionary:
	var dir := ((e["inside"] as Vector2) - (e["lane"] as Vector2)).normalized()
	var edge: Vector2 = e["edge"]
	return {"o": edge, "u": dir, "v": Vector2(-dir.y, dir.x), "u0": -LANE_SIDE, "u1": ((e["inside"] as Vector2) - edge).dot(dir)}


## The rocks that can matter for a strip, in the strip's own coordinates:
## Vector3(along, across, radius).
static func _strip_rocks(rocks: PackedVector3Array, fr: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var o: Vector2 = fr["o"]
	var u: Vector2 = fr["u"]
	var v: Vector2 = fr["v"]
	for r: Vector3 in rocks:
		var d := Vector2(r.x, r.y) - o
		if d.length() < NEAR:
			out.append(Vector3(d.dot(u), d.dot(v), r.z))
	return out


## The biggest circle radius that can travel from the start of the strip
## (u = `u0`) to its end (`u1`) among `rocks` (strip coordinates). Searches
## between 0 and SEARCH_MAX by halving; a strip that even a point cannot
## cross gives 0, and one that SEARCH_MAX crosses gives SEARCH_MAX.
static func pass_radius(rocks: PackedVector3Array, u0: float, u1: float) -> float:
	if not crosses(rocks, u0, u1, 0.0):
		return 0.0
	if crosses(rocks, u0, u1, SEARCH_MAX):
		return SEARCH_MAX
	var lo := 0.0
	var hi := SEARCH_MAX
	while hi - lo > SEARCH_STEP:
		var mid := (lo + hi) * 0.5
		if crosses(rocks, u0, u1, mid):
			lo = mid
		else:
			hi = mid
	return lo


## Can a circle of radius `radius` get from the start of the strip to its
## end? Walk the slices: keep the free stretches that join up with a free
## stretch of the slice before.
static func crosses(rocks: PackedVector3Array, u0: float, u1: float, radius: float) -> bool:
	var slices := int(ceil((u1 - u0) / SLICE)) + 1
	var reach: Array = []
	for k in slices:
		var free := _free_stretches(rocks, minf(u0 + float(k) * SLICE, u1), radius)
		var now: Array = []
		if k == 0:
			now = free
		else:
			for f: Vector2 in free:
				for p: Vector2 in reach:
					if minf(f.y, p.y) - maxf(f.x, p.x) > 0.000001:
						now.append(f)
						break
		if now.is_empty():
			return false
		reach = now
	return true


## Is there free space for a circle of radius `radius` at both ends of the
## strip (so that a failure to cross is the gate's doing)?
static func _ends_free(rocks: PackedVector3Array, u0: float, u1: float, radius: float) -> bool:
	return not _free_stretches(rocks, u0, radius).is_empty() and not _free_stretches(rocks, u1, radius).is_empty()


## The stretches (Vector2(from, to), across the strip) of the slice at `u`
## where the centre of a circle of radius `radius` touches no rock. Every
## rock forbids the stretch where its distance is under (its radius + radius);
## what remains of -HALF_WIDTH..HALF_WIDTH is free.
static func _free_stretches(rocks: PackedVector3Array, u: float, radius: float) -> Array:
	var forbidden: Array = []
	for r: Vector3 in rocks:
		var reach := r.z + radius
		var du := absf(u - r.x)
		if du < reach:
			var half := sqrt(reach * reach - du * du)
			forbidden.append(Vector2(r.y - half, r.y + half))
	forbidden.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var free: Array = []
	var cursor := -HALF_WIDTH
	for f: Vector2 in forbidden:
		if f.x > cursor:
			free.append(Vector2(cursor, minf(f.x, HALF_WIDTH)))
		cursor = maxf(cursor, f.y)
		if cursor >= HALF_WIDTH:
			break
	if cursor < HALF_WIDTH:
		free.append(Vector2(cursor, HALF_WIDTH))
	return free.filter(func(s: Vector2) -> bool: return s.y - s.x > 0.000001)


## The smallest number in `xs` (0 for an empty list).
static func _min(xs: Array) -> float:
	var m := INF
	for x in xs:
		m = minf(m, float(x))
	return 0.0 if xs.is_empty() else m


## The largest number in `xs` (0 for an empty list).
static func _max(xs: Array) -> float:
	var m := -INF
	for x in xs:
		m = maxf(m, float(x))
	return 0.0 if xs.is_empty() else m
