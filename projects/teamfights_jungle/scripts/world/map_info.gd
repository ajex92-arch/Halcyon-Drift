class_name MapInfo
extends RefCounted
## WHAT THIS IS: the finished map, as plain data: lanes, ore nodes, monster
## camps, jungle paths and entrances, every rock, and the route graph (the
## road map AI ships follow). MapBuilder fills it in once at the start of a
## match; after that nobody changes it, everyone just reads it.
##
## HOW IT WORKS: it is mostly lists. It also answers two common questions:
##   - lane_for(p): which lane is nearest to a point?
##   - in_open_lane(p): is a point in open space (a lane, the connector or
##     a base clearing) rather than in the asteroid jungle? To answer fast,
##     it looks the point up in a grid of yes/no answers worked out once
##     (warm_up()), one per square of OPEN_CELL by OPEN_CELL world units.
##
## Distances are in world units (1 world unit is about one pixel at normal
## zoom). Team 0 is Halcyon (the left side), team 1 is Cinder (the right).
##
## WHO USES IT: World keeps it as World.map (WorldSetup.build() makes it
## with MapBuilder.build() and calls warm_up()). AsteroidField.build() turns
## the rock lists into real rocks; WorldSetup makes the ore nodes from
## `nodes`; JungleDirector reads `camps`; AdmiralBuilder reads `entrances`;
## MapDecor and the minimap draw the lanes and the connector. lane_for()
## and in_open_lane() are asked by AI pilots (PilotGoals, PilotFlight), the
## AI admiral (AdmiralBuilder, AdmiralSiege, AdmiralMothershipMover), the
## command desk (AdmiralCommand), the command overlay, World.place_name()
## and some tests. Mining drones, repair bays, wards, AI pilots and the
## command desk ask `route` for paths.

## The three lanes: lane id ("top", "mid", "bot") -> the points of its
## centre line (a PackedVector2Array), running from Halcyon to Cinder.
var lanes := {}
## Lane id -> half the lane's width (world units).
var lane_half := {}
## The points of the connector's centre line (the "Crossing", the lane
## straight down the middle that joins the three lanes).
var connector := PackedVector2Array()
## Half the connector's width (world units). MapBuilder sets it from
## MapLayout.CONNECTOR.
var connector_half := 1600.0
## The ore nodes, as [{id, name, pos, kind, side, lane, value, slot_pos,
## ore: [{pos, r}]}]: kind = "inner" (near a mothership) or "middle" (on
## the centre line); side = owning team, or -1 for a shared middle node;
## lane = the lane it faces; value = how rich it is; slot_pos = its turret
## spots; ore = its ore rocks (centre and radius).
var nodes: Array = []
## The monster camps, as [{id, type, pos, quad}]: type = "gunship" or
## "carrier"; quad = the map quarter ("tl", "bl", "tr" or "br").
var camps: Array = []
## The jungle paths, each a PackedVector2Array of points (2 points for the
## short paths through the gates, 3 for the winding ones), both halves.
var jungle_paths: Array = []
## The jungle entrances (both halves), as [{quad, lane, inside, edge}]:
## lane = a point on the corridor's centre line, inside = a point just
## inside the jungle, edge = where the line between them crosses the
## corridor's edge.
var entrances: Array = []
## The centre of every rock. rock_pos, rock_r and rock_node are read
## together: the same index in each is the same rock.
var rock_pos := PackedVector2Array()
## The radius of every rock (world units).
var rock_r := PackedFloat32Array()
## 1 if the rock is an ore rock (it belongs to a node and can't be
## destroyed), 0 for an ordinary rock.
var rock_node := PackedByteArray()
## The road map that AI ships and drones follow (made by MapBuilderRoute).
var route := RouteGraph.new()
## Where each team's mothership starts (index = team).
var mothership_pos: Array = []
## Which way each team's mothership starts facing (radians; index = team).
var mothership_facing: Array = []

## The size (world units) of one square of the open-space grid. The exact
## test is _open_exact().
const OPEN_CELL := 200.0
## The open-space grid: one entry per square, 1 = open, 0 = not. Row by
## row from the top; square (cx, cy) is entry cx + cy * _open_cols. Empty
## until _build_open() runs.
var _open := PackedByteArray()
## How many squares the open-space grid has across.
var _open_cols := 0
## How many squares the open-space grid has down.
var _open_rows := 0


## The id of the lane whose centre line is nearest to `p` ("top", "mid" or
## "bot"; the connector doesn't count). "mid" if there are no lanes.
func lane_for(p: Vector2) -> String:
	var best := "mid"
	var bd := INF
	for id: String in lanes:
		var d := Util.dist_to_polyline(p, lanes[id])
		if d < bd:
			bd = d
			best = id
	return best


## Build lookup tables now (World.setup), not mid-match on first use.
func warm_up() -> void:
	if _open.is_empty():
		_build_open()


## True inside a lane corridor, the connector or a base clearing. It looks
## up the grid square `p` falls in, so near an edge the answer is the one
## for that square's middle. Points off the map use the nearest edge
## square. Builds the grid first if warm_up() hasn't.
func in_open_lane(p: Vector2) -> bool:
	if _open.is_empty():
		_build_open()
	var cx := clampi(int(p.x / OPEN_CELL), 0, _open_cols - 1)
	var cy := clampi(int(p.y / OPEN_CELL), 0, _open_rows - 1)
	return _open[cx + cy * _open_cols] == 1


## Work out the open-space grid: for every square, run the exact test on
## its middle point.
func _build_open() -> void:
	# Enough squares to cover the whole map.
	_open_cols = int(ceil(MapLayout.W / OPEN_CELL))
	_open_rows = int(ceil(MapLayout.H / OPEN_CELL))
	_open.resize(_open_cols * _open_rows)
	# One exact test per square.
	for cy in _open_rows:
		for cx in _open_cols:
			var c := Vector2((float(cx) + 0.5) * OPEN_CELL, (float(cy) + 0.5) * OPEN_CELL)
			_open[cx + cy * _open_cols] = 1 if _open_exact(c) else 0


## The exact (slower) open-space test: is `p` closer to a lane's or the
## connector's centre line than half its width, or inside a base clearing
## (MapLayout.BASE_CLEAR_RADIUS around a mothership's starting spot)?
func _open_exact(p: Vector2) -> bool:
	for id: String in lanes:
		if Util.dist_to_polyline(p, lanes[id]) < float(lane_half[id]):
			return true
	if Util.dist_to_polyline(p, connector) < connector_half:
		return true
	for mp: Vector2 in mothership_pos:
		if p.distance_to(mp) < MapLayout.BASE_CLEAR_RADIUS:
			return true
	return false
