class_name WorldQueries
extends RefCounted
## WHAT THIS IS: answers to everyday questions about the match, such as
## "which enemy is nearest to this point?", "which repair bay is
## closest?" or "what is this place called?".
##
## HOW IT WORKS: each function looks through the World's lists (ore nodes,
## mining drones, repair bays) or asks the spatial hash (a grid over the
## map that quickly finds the units near a point) and returns the answer.
## Nothing here changes the match.
##
## WHO USES IT: World makes one (World.queries), and World's question
## functions (node_by_id, nearest_enemy, best_bay, place_name, ...) forward
## here. Callers include AI pilots, minions, mining drones, ore nodes,
## the admiral's command desk and board, the hangar screen, the HUD, news
## lines and many tests.

## The world we answer questions about.
var world: World
## A reusable list the spatial hash fills with nearby units (reused so a
## new list isn't made on every question). nearest_enemy() and
## any_enemy_ship_near() share it.
var scratch: Array = []


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## The ore node with id `id`, or null if there is none.
func node_by_id(id: String) -> ResourceNode:
	for n in world.nodes:
		if n.node_id == id:
			return n
	return null


## How many live mining drones `team` has.
func mining_drone_count(team: int) -> int:
	var c := 0
	for d in world.mining_drones:
		if d.team == team and d.alive:
			c += 1
	return c


## True if a live enemy of `team` (not neutral) that is a pilot ship or a
## minion is within `r` world units of point `p`.
func any_enemy_ship_near(p: Vector2, r: float, team: int) -> bool:
	for u: Unit in world.unit_hash.query(p, r, scratch):
		if u.alive and u.team != team and u.team != Rules.NEUTRAL and (u.kind == Unit.K_SHIP or u.kind == Unit.K_MINION) and u.global_position.distance_to(p) < r:
			return true
	return false


## The nearest live enemy of `team` (any kind, not neutral)
## within `r` world units of `p`, or null. If `filter` is given, a unit
## only counts when filter.call(unit) returns true.
func nearest_enemy(p: Vector2, r: float, team: int, filter: Callable = Callable()) -> Unit:
	var best: Unit = null
	var bd := r
	for u: Unit in world.unit_hash.query(p, r, scratch):
		# Skip the dead, our own side and neutrals.
		if not u.alive or u.team == team or u.team == Rules.NEUTRAL:
			continue
		# Keep the closest one that passes the filter.
		var d := p.distance_to(u.global_position)
		if d < bd and (not filter.is_valid() or filter.call(u)):
			bd = d
			best = u
	return best


## The rest of lane `lane` (as `team` walks it) from point `from`: first
## the lane point nearest `from`, then every corner of the lane that lies
## more than 50 world units further along. Minions use it to get their
## path down the lane from where they are. From a spot outside the lane's
## corridor the path starts with the route graph's way to the lane.
func lane_path_from(lane: String, team: int, from: Vector2) -> PackedVector2Array:
	# Find the nearest point on the lane, and how far along the lane it is
	# ("s", in world units from the lane's start).
	var pts := MapLayout.lane_points(lane, team)
	var proj := Util.project_on_polyline(from, pts)
	var s: float = proj["s"]
	var out := PackedVector2Array()
	# A start outside this lane's corridor (e.g. a mothership parked up another
	# lane) flies the big-ship route graph and joins the lane where the route
	# first comes within 80% of its half width, instead of flying straight
	# through the jungle.
	var half := float(MapLayout.LANES[lane]["half"])
	if float(proj["dist"]) > half:
		var r := world.map.route.path(from, proj["point"], false)
		for i in range(1, r.size()):
			var q := Util.project_on_polyline(r[i], pts)
			if float(q["dist"]) <= half * 0.8:
				proj = q
				s = q["s"]
				break
			out.append(r[i])
	out.append(proj["point"])
	# Walk the lane, adding up its length, and keep each corner that is
	# more than 50 units past that point.
	var acc := 0.0
	for i in pts.size() - 1:
		acc += pts[i].distance_to(pts[i + 1])
		if acc > s + 50.0:
			out.append(pts[i + 1])
	return out


## The nearest working repair bay of `team` to `from` (alive and anchored,
## meaning it has arrived and set up), or null if there is none.
func best_bay(team: int, from: Vector2) -> RepairBay:
	var best: RepairBay = null
	var bd := INF
	for b in world.bays:
		if b.team == team and b.alive and b.is_anchored():
			var d := from.distance_to(b.global_position)
			if d < bd:
				bd = d
				best = b
	return best


## The friendly (team `team`), anchored repair bay whose module-swap circle
## (RepairBay.swap_radius) contains point `p`, or null.
func bay_at(team: int, p: Vector2) -> RepairBay:
	for b in world.bays:
		if b.team == team and b.alive and b.is_anchored() and p.distance_to(b.global_position) < b.swap_radius():
			return b
	return null


## A readable place name for news lines ("Top lane", "The Crossing", ...):
## the first ore node (in map order) within 2000 world units, else the
## lane's label if `p` is in an open lane, else "the jungle".
func place_name(p: Vector2) -> String:
	for n in world.nodes:
		if p.distance_to(n.global_position) < 2000.0:
			return n.node_name
	if world.map.in_open_lane(p):
		return str(MapLayout.LANES[world.map.lane_for(p)]["label"])
	return "the jungle"
