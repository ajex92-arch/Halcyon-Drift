class_name MapBuilder
extends RefCounted
## WHAT THIS IS: the map maker. At the start of a match it turns the
## hand-drawn plan of the map (MapLayout) into the whole battlefield: the
## lanes, the ore nodes, the jungle with its monster camps and winding
## paths, all the asteroids, and the "route graph" (a road map of dots and
## lines that AI ships and drones use to find their way). DESIGN.md A4.
##
## HOW IT WORKS: build() runs these steps, always in this order:
##   1. Bases and lanes: copy the two motherships, the three lanes and the
##      connector (the "Crossing", a lane straight down the middle that
##      joins the three lanes) from MapLayout.
##   2. Ore nodes (MapBuilderNodes): each node gets its ore rocks and its
##      turret slots, which sit on the side of the node facing its lane.
##   3. Jungle (MapBuilderJungle): the monster camps, the entrances from
##      the lanes into the jungle, and winding paths that link each
##      quarter's entrances and camps.
##   4. Lane walls (MapBuilderWalls): rocks packed along both edges of
##      every corridor (lane or connector) so the jungle is sealed off,
##      except at the entrances. Each entrance gets a "gate": two big rocks
##      with a gap of MapLayout.CHOKE_GAP (86 world units) between them,
##      which only strike craft can fit through.
##   5. Fill (MapBuilderFill): rocks scattered over every spot that is not
##      a lane, a base, a node, a camp or a jungle path.
##   6. Emit rocks: copy every rock into the finished map, plus its mirror
##      copy (see below).
##   7. Route graph (MapBuilderRoute): the road map for AI ships and drones.
##
## Fair for both sides: everything is made on Aurelian's half of the map
## (x < CX, the left half) and then mirrored onto Vhorr's half, so the two
## sides are exactly the same. "Mirrored" means flipped left-to-right
## across the centre line x = CX, like a reflection (MapLayout.mirror()).
##
## Same seed, same map: the random numbers come from Mulberry, a random
## number maker that always gives the same numbers in the same order when
## it starts from the same number (the "seed", MapLayout.SEED). Steps 2, 3,
## 4 and 5 all take numbers from that one shared sequence, so the steps,
## and the loops inside them, must keep their exact order. Moving anything
## would hand different numbers to different rocks, and the map would
## change.
##
## Distances are in world units (1 world unit is about one pixel at normal
## zoom). Angles are in radians (a full turn is TAU, about 6.28).
##
## WHO USES IT: WorldSetup.build() calls MapBuilder.build() once per
## match and keeps the result as World.map (a MapInfo).
##
## THE PARTS: each big step lives in its own file next to this one:
##   map_builder_nodes.gd  (MapBuilderNodes)  step 2, ore nodes
##   map_builder_jungle.gd (MapBuilderJungle) step 3, camps, entrances, paths
##   map_builder_walls.gd  (MapBuilderWalls)  step 4, lane walls and gates
##   map_builder_fill.gd   (MapBuilderFill)   step 5, filler rocks
##   map_builder_route.gd  (MapBuilderRoute)  step 7, the route graph
## This file keeps the shared lists every step adds to, the tuning numbers
## (so they can all be tweaked in one place), steps 1 and 6, and the order
## of the steps.
## (A "static" function, like build(), belongs to the class itself: it is
## called as MapBuilder.build(...) without making a MapBuilder first.)

## Smallest radius (world units) of a lane wall rock.
const EDGE_R_MIN := 110.0
## Largest radius (world units) of a lane wall rock.
const EDGE_R_MAX := 160.0
## Smallest gap (world units) between two neighbouring wall rocks.
const EDGE_GAP_MIN := 8.0
## Largest gap (world units) between two neighbouring wall rocks.
const EDGE_GAP_MAX := 40.0
## Radius (world units) of each of the two big rocks that form a jungle gate.
const GATE_R := 150.0
## The fill step tries one rock per square of a grid this wide (world units).
const FILL_SPACING := 440.0
## Each fill rock is nudged up to this far (world units) from the middle of
## its grid square, left/right and up/down, so the field doesn't look like
## a grid.
const FILL_JITTER := 120.0
## Smallest radius (world units) of a fill rock.
const FILL_R_MIN := 130.0
## Largest radius (world units) of a fill rock.
const FILL_R_MAX := 250.0
## Route dots along lanes and the connector are spread evenly, at most this
## far apart (world units).
const LANE_NODE_STEP := 1400.0
## Route dots along jungle paths are spread evenly, at most this far apart
## (world units).
const PATH_NODE_STEP := 450.0
## Base route node: this far (world units) ahead of a mothership's centre
## (half its 1,600 length plus room to manoeuvre).
const BASE_NODE_OFFSET := 1300.0

## The finished map we fill in and hand back.
var info := MapInfo.new()
## The random number maker for the whole build, started from
## MapLayout.SEED in _run().
var rng: Mulberry
## The open corridors: the three lanes and the connector, as
## [{id, pts, half}]: id = lane id or "connector", pts = the points of its
## centre line, half = half its width (world units).
var corridors: Array = []
## Circles that fill rocks must stay out of, as [{c, r}] (centre, radius in
## world units): every node (with 250 units to spare) and every camp.
var keep_out: Array = []
## Circles that lane wall rocks must stay out of, as [{c, r}]: the area of
## every ore node (MapLayout.NODE_RADIUS).
var node_keep: Array = []
## The jungle gates on Aurelian's half, as [{corridor, s, dir, edge}]:
## corridor = which corridor's wall it is in, s = how far along that
## corridor's centre line (world units), dir = the direction from the lane
## into the jungle (length 1), edge = where the entrance meets the
## corridor's edge.
var gates: Array = []
## Every rock so far, before mirroring, as [{p, r, node, mirror}]:
## p = centre, r = radius (world units), node = true for ore rocks (which
## can't be destroyed), mirror = true if step 6 should also add a mirror
## copy on Vhorr's half.
var rocks: Array = []


## Build the whole map and return it.
static func build() -> MapInfo:
	var b := MapBuilder.new()
	return b._run()


## Run every step in order (see HOW IT WORKS) and return the finished map.
func _run() -> MapInfo:
	# The random number maker. Every step that needs random numbers takes
	# them from this one, in the order the steps run.
	rng = Mulberry.new(MapLayout.SEED)
	# Step 1: bases, lanes and the connector (no random numbers).
	_bases_and_lanes()
	# Steps 2 to 5: each part is made, used once and then thrown away. They
	# all add to this builder's shared lists.
	MapBuilderNodes.new(self).run()
	MapBuilderJungle.new(self).run()
	MapBuilderWalls.new(self).run()
	MapBuilderFill.new(self).run()
	# Step 6: copy the rocks (and their mirror copies) into the map.
	_emit_rocks()
	# Step 7: the road map for AI ships and drones (no random numbers).
	MapBuilderRoute.new(self).run()
	return info


## Step 1: copy the motherships, the lanes and the connector into the map,
## and list the lanes and the connector as corridors for the later steps.
func _bases_and_lanes() -> void:
	# Where each team's mothership sits and which way it faces (team 0 is
	# Aurelian, team 1 is Vhorr).
	for t in 2:
		info.mothership_pos.append(MapLayout.MOTHERSHIPS[t]["pos"])
		info.mothership_facing.append(float(MapLayout.MOTHERSHIPS[t]["facing"]))
	# The three lanes, in MapLayout.LANE_ORDER (top, mid, bot).
	for id: String in MapLayout.LANE_ORDER:
		var l: Dictionary = MapLayout.LANES[id]
		info.lanes[id] = PackedVector2Array(l["points"])
		info.lane_half[id] = float(l["half"])
		corridors.append({"id": id, "pts": info.lanes[id], "half": float(l["half"])})
	# The connector comes last in the corridor list.
	info.connector = PackedVector2Array(MapLayout.CONNECTOR["points"])
	info.connector_half = float(MapLayout.CONNECTOR["half"])
	corridors.append({"id": "connector", "pts": info.connector, "half": info.connector_half})


## Step 6: copy every rock into the map's rock lists (rock_pos, rock_r,
## rock_node; the same index in each list is the same rock). A rock marked
## `mirror` also gets a copy on Vhorr's half, unless it sits right on the
## centre line (within 1 world unit), where its copy would land on itself.
func _emit_rocks() -> void:
	for rk: Dictionary in rocks:
		var p: Vector2 = rk["p"]
		var r: float = rk["r"]
		var node := bool(rk["node"])
		# The rock itself (1 in rock_node means an ore rock).
		info.rock_pos.append(p)
		info.rock_r.append(r)
		info.rock_node.append(1 if node else 0)
		# Its mirror copy, right after it.
		if bool(rk["mirror"]) and absf(p.x - MapLayout.CX) > 1.0:
			info.rock_pos.append(MapLayout.mirror(p))
			info.rock_r.append(r)
			info.rock_node.append(1 if node else 0)
