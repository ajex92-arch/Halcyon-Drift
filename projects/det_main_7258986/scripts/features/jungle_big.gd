class_name JungleBigFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "jungle_big" rule variant (idea
## E5 of the combat_roles fork). REQ-CHANGE: the requirements say the jungle
## is "a jungle ... that only small ships can travel through". With this
## variant bigger ships may fly through it too: "medium" lets the MEDIUM
## corvettes in, "all" also the LARGE frigates and the CAPITAL ships. (They
## keep the game's gentle asteroid-crash damage, so a bad turn hurts a
## little and does not kill.) With the variant off the map and the AI are
## exactly the ordinary game.
##
## HOW IT WORKS: "only small ships fit" is enforced in three places, and this
## module relaxes each one only while the variant is on:
##   1. The map. Each jungle entrance is a gate of two big rocks with a gap
##      of MapLayout.CHOKE_GAP (86 world units; 101 once the rocks' solid
##      shapes are counted) and the winding jungle paths are kept clear of
##      filler rocks to a half-width of MapLayout.PATH_HALF (150). The map
##      maker asks choke_gap() and path_half() here instead. "medium" opens
##      the gate to 130 (a corvette is 88 wide); "all" opens it to 400 (a
##      battlecruiser is 320 wide) and widens the clear paths to 260. The
##      map is built before any feature is installed, so these two
##      functions read the variant themselves (Game.variant). Random numbers
##      are drawn in the same order, so only the rocks next to the gates
##      and paths differ from the ordinary map.
##   2. The route graph. Jungle dots and the links into the jungle are
##      "small only". PilotFlight and PilotEscape ask route_small() /
##      plan_route() here instead of ship.is_small(): for a ship that is
##      allowed in, plan_route() works out the cheapest route through the
##      lanes only and the cheapest route that may use the jungle, and takes
##      the jungle one when its flying TIME is lower (a leg in the jungle
##      counts as JUNGLE_SPEED, 62%, of top speed, because the pilots slow
##      down there; a leg on the open lanes at full speed). Pilots who
##      are already small, and the jungle pilots, behave as before.
##   3. The human's flying: the gates are real rocks, so a wider gate lets a
##      human corvette or frigate through with no further change.
## Usage counters in Game.usage: "big_jungle_seconds" (seconds that
## MEDIUM-or-bigger pilot ships spend inside the jungle), "big_jungle_routes"
## (routes planned through the jungle for them), "big_route_choices" (routes
## planned for them where the jungle-allowed route differed from the
## lane-only one, so picks / choices says how often the jungle won) and, to see who farms the
## camps, "camp_kills_small", "camp_kills_medium" and "camp_kills_big"
## (jungle camps destroyed, by the size of the ship that made the last hit).
##
## WHO USES IT: FeatureRegistry installs it for --variant=jungle_big:medium
## or :all. MapBuilderWalls and MapBuilderFill call choke_gap() and
## path_half(); PilotFlight and PilotEscape call route_small() and
## plan_route().

## The variant key this module belongs to.
const KEY := "jungle_big"
## Gate opening for "medium" (world units between the two gate rocks).
const GAP_MEDIUM := 130.0
## Gate opening for "all" (world units).
const GAP_ALL := 400.0
## Half-width of the filler-free jungle paths for "all" (world units).
const PATH_HALF_ALL := 260.0
## How fast ships fly in the jungle compared with the open lanes (0.62 =
## 62%): the pilots hold back to make the turns (PilotFlight, step 7).
const JUNGLE_SPEED := 0.62
## Seconds between two looks at where the big ships are.
const LOOK_EVERY := 0.25

## The match.
var world: World
## Seconds since the last look.
var _t := 0.0
## Seconds of big ships in the jungle not yet counted in Game.usage.
var _acc := 0.0


## Which setting is on: 0 = off, 1 = "medium", 2 = "all".
static func level() -> int:
	match Game.variant(KEY):
		"medium":
			return 1
		"all":
			return 2
	return 0


## The gate opening the map maker uses (world units): the ordinary 86
## unless the variant is on. MapBuilderWalls calls it.
static func choke_gap() -> float:
	match level():
		1:
			return GAP_MEDIUM
		2:
			return GAP_ALL
	return MapLayout.CHOKE_GAP


## The half-width of the filler-free jungle paths the map maker uses
## (world units): the ordinary 150 unless the variant is "all".
## MapBuilderFill calls it.
static func path_half() -> float:
	return PATH_HALF_ALL if level() == 2 else MapLayout.PATH_HALF


## May this ship use the jungle: a small ship always, a bigger one only up
## to the size the variant lets in ("medium": MEDIUM; "all": CAPITAL).
static func allows(ship: Ship) -> bool:
	if ship.is_small():
		return true
	var lv := level()
	return lv == 2 or (lv == 1 and ship.size_class <= Rules.SIZE_MEDIUM)


## The `small` answer for the route graph (RouteGraph.path / nearest): true
## when the ship may use jungle dots and links. Same as ship.is_small()
## with the variant off. PilotEscape calls it.
static func route_small(ship: Ship) -> bool:
	return ship.is_small() or (level() > 0 and allows(ship))


## The route a pilot ship should fly from `from` to `to` (the same list of
## points as RouteGraph.path). Small ships, and every ship with the variant
## off, get RouteGraph.path(from, to, ship.is_small()) as always. A bigger
## ship that is allowed in gets the lane-only route or the jungle route,
## whichever takes less flying time. The way onto the road map is the cheapest
## dot the ship can fly to (RouteGraph.entry()), and the route is empty with
## RouteGraph.no_entry set when there is none; `strict` false asks for the old
## way, the nearest dot, even when rocks hide it. The dots in `banned` are not
## used as the way onto the map. PilotFlight calls it.
static func plan_route(route: RouteGraph, ship: Ship, from: Vector2, to: Vector2, strict := true, banned := PackedInt32Array()) -> PackedVector2Array:
	var radius := ship.radius if strict else 0.0
	# Step 1: the ordinary answer for ships that are not affected.
	if ship.is_small() or level() == 0 or not allows(ship):
		return route.path(from, to, ship.is_small(), radius, banned)
	# Step 2: the two candidates.
	var lanes := route.path(from, to, false, radius, banned)
	var jungle := route.path(from, to, true, radius, banned)
	if jungle.is_empty():
		return lanes
	# A real choice exists when the jungle-allowed route differs from the
	# lane-only one (count it, so a report can compare choices and picks).
	if jungle != lanes:
		Game.count_usage("big_route_choices")
	if lanes.is_empty() or _flying_time(jungle, ship) < _flying_time(lanes, ship):
		# Count the jungle routes a big ship really takes.
		if _touches_jungle(jungle, ship):
			Game.count_usage("big_jungle_routes")
		return jungle
	return lanes


## Flying time (seconds, rough) of the route `pts` for `ship`: each leg's
## length over the ship's top speed, slower inside the jungle.
static func _flying_time(pts: PackedVector2Array, ship: Ship) -> float:
	var speed := maxf(30.0, ship.f_max)
	var t := 0.0
	var map: MapInfo = ship.world.map
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var in_jungle := not map.in_open_lane((a + b) * 0.5)
		t += a.distance_to(b) / (speed * (JUNGLE_SPEED if in_jungle else 1.0))
	return t


## Does route `pts` pass through the jungle (some point is off the open
## lanes)?
static func _touches_jungle(pts: PackedVector2Array, ship: Ship) -> bool:
	for p in pts:
		if not ship.world.map.in_open_lane(p):
			return true
	return false


## Plug the feature into match `w`: a tick hook for the counters and a
## listener for destroyed camps. FeatureRegistry calls it once at match
## start.
func install(w: World) -> void:
	world = w
	w.tick_hooks.append(Callable(self, "_tick"))
	Events.unit_killed.connect(_on_killed)


## Every tick (a hook): every LOOK_EVERY seconds add up the time that
## MEDIUM-or-bigger pilot ships spend in the jungle.
func _tick(dt: float) -> void:
	_t += dt
	if _t < LOOK_EVERY:
		return
	_t -= LOOK_EVERY
	for s: Ship in world.ships:
		if s.alive and not s.is_small() and not world.map.in_open_lane(s.global_position):
			_acc += LOOK_EVERY
	var whole := int(_acc)
	if whole > 0:
		Game.count_usage("big_jungle_seconds", whole)
		_acc -= float(whole)


## A unit was destroyed: if it was a jungle camp, count who made the last
## hit, by size of the ship.
func _on_killed(u: Node, info: RefCounted) -> void:
	if world == null or Game.world != world:
		return
	if (u as Unit).kind != Unit.K_MONSTER:
		return
	var di := info as DamageInfo
	if di == null or not di.source_is_pilot:
		return
	if di.source_size >= Rules.SIZE_MEDIUM + 1:
		Game.count_usage("camp_kills_big")
	elif di.source_size == Rules.SIZE_MEDIUM:
		Game.count_usage("camp_kills_medium")
	else:
		Game.count_usage("camp_kills_small")
