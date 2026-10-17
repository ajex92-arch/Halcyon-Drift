class_name MapLayout
extends RefCounted
## WHAT THIS IS: the hand-made plan of the battlefield ("theater"): how big
## it is, where the motherships start, where the three lanes run, and where
## the ore nodes, monster camps and jungle entrances are. DESIGN.md A4.
##
## HOW IT WORKS: Aurelian's half is authored here; MapBuilder mirrors it
## across x = CX for Cinder so neither side gets a better map. ("Mirror" =
## flip left-right across the centre line, like a reflection.) Lanes are
## shared polylines from Aurelian's mothership to Cinder's (a "polyline" is
## a path of straight pieces joining the listed points in order).
## Asteroids are generated around this skeleton by MapBuilder from SEED.
## Positions are in world units (1 world unit is about one pixel at normal
## zoom). (0, 0) is the top-left corner: x grows to the right and y grows
## downward, so the "top" lane has small y values.
##
## WHO USES IT: MapBuilder and its parts (MapBuilderNodes, MapBuilderJungle,
## MapBuilderWalls, MapBuilderFill, MapBuilderRoute) build the map from it;
## MapInfo, MapDecor, the Minimap and the CameraRig read the sizes and
## lanes; WorldSetup sizes the spatial hashes (grids for finding nearby
## units) with W and H; Vision sizes its grid; ResourceNode reads the ore
## numbers; Mulberry and AsteroidField start from SEED; the AI (AdmiralLanes,
## PilotGoals, TeamSiege), MinionDirector and WorldQueries walk the lanes.
##
## To change the map: move lanes/nodes/camps here, then check that the
## jungle chokes still stop big ships and that strike craft can still reach
## every camp. (DESIGN.md names a tests/unit_checks.gd for these checks,
## but that file is not in the project at the moment.)

## The map's width (world units).
const W := 40000.0
## The map's height (world units).
const H := 26000.0
## The x of the map's centre line (W / 2). Cinder's half is Aurelian's half
## mirrored across it.
const CX := 20000.0
## The "seed" number that starts the map's random number sequence, so the
## generated asteroids come out the same in every match (MapBuilder; the
## asteroid shapes use SEED + 77).
const SEED := 4141

## Where each mothership starts, by team (0 Aurelian, 1 Cinder): its
## position and its facing, an angle in radians (0 = pointing right, PI =
## pointing left, so they face each other).
const MOTHERSHIPS := [
	{"pos": Vector2(3600, 13000), "facing": 0.0},
	{"pos": Vector2(36400, 13000), "facing": PI},
]
## No random asteroids within this distance (world units) of a mothership's
## starting spot, so each base has open space. MapDecor draws this circle
## faintly in the team colour.
const BASE_CLEAR_RADIUS := 6000.0

## Lane polylines run Aurelian -> Cinder. half = corridor half-width.
## lane id -> label (the name players see), half (half the corridor's
## width, in world units: the open lane is 3600 wide) and points (the
## polyline). All three lanes start at Aurelian's mothership and end at
## Cinder's; the middle lane has a small bend around the centre.
const LANES := {
	"top": {"label": "Top lane", "half": 1800.0, "points": [Vector2(3600, 13000), Vector2(8200, 3800), Vector2(31800, 3800), Vector2(36400, 13000)]},
	"mid": {"label": "Mid lane", "half": 1800.0, "points": [Vector2(3600, 13000), Vector2(16500, 13000), Vector2(18800, 11600), Vector2(21200, 11600), Vector2(23500, 13000), Vector2(36400, 13000)]},
	"bot": {"label": "Bottom lane", "half": 1800.0, "points": [Vector2(3600, 13000), Vector2(8200, 22200), Vector2(31800, 22200), Vector2(36400, 13000)]},
}
## The perpendicular lane down the middle joining all three.
## It runs straight down the centre line (x = 20000) from the top lane to
## the bottom lane; same fields as a lane.
const CONNECTOR := {"label": "Crossing", "half": 1600.0, "points": [Vector2(20000, 3800), Vector2(20000, 22200)]}
## The lane ids in their usual order, top to bottom.
const LANE_ORDER := ["top", "mid", "bot"]

## Resource nodes. "inner" = near a mothership (torpedo turrets allowed);
## "middle" = on the crossing (PD only). Aurelian inner nodes are mirrored for
## Cinder; middle nodes sit on the centre line and are shared.
## A resource node is a cluster of ore rocks that mining drones harvest,
## with turret slots next to it. Fields:
##   id, name   the node's id and the name players see. A mirrored copy
##              gets "cin" instead of "h" in its id and "Cinder" instead of
##              "Halcyon" in its name (Halcyon's own copy gets "hal").
##   pos        its centre [world units]
##   kind       "inner" or "middle" (see above)
##   lane       the lane it sits on
##   value      ore multiplier: each rock holds ORE_PER_ROCK x value and
##              regrows ORE_REGEN x value per second
##   slots      how many turrets can stand there
## So there are 3 + 3 inner nodes and 3 middle nodes: 9 in all.
const NODES := [
	{"id": "h_top", "name": "Halcyon Top", "pos": Vector2(10800, 2600), "kind": "inner", "lane": "top", "value": 1.0, "slots": 3},
	{"id": "h_mid", "name": "Halcyon Mid", "pos": Vector2(11500, 14200), "kind": "inner", "lane": "mid", "value": 1.0, "slots": 3},
	{"id": "h_bot", "name": "Halcyon Bottom", "pos": Vector2(10800, 23400), "kind": "inner", "lane": "bot", "value": 1.0, "slots": 3},
	{"id": "c_top", "name": "Top Crossing", "pos": Vector2(20000, 2600), "kind": "middle", "lane": "top", "value": 1.3, "slots": 1},
	{"id": "c_mid", "name": "The Crossing", "pos": Vector2(20000, 13000), "kind": "middle", "lane": "mid", "value": 1.6, "slots": 2},
	{"id": "c_bot", "name": "Bottom Crossing", "pos": Vector2(20000, 23400), "kind": "middle", "lane": "bot", "value": 1.3, "slots": 1},
]
## The size of a node's area (world units): its ore rocks lie inside this
## circle, normal asteroids are kept out of it, and the turret slots sit
## just outside it (140 further out).
const NODE_RADIUS := 560.0
## Ore rocks per node. (The Crossing, "c_mid", gets 6 instead; MapBuilder
## decides that.)
const ORE_ROCKS := 5
## Ore in one full rock, before the node's value multiplier (1 ore is
## worth 1 credit when a drone brings it home).
const ORE_PER_ROCK := 1600.0
## Ore each rock regrows per second (times the node's value), up to full.
const ORE_REGEN := 6.0

## Monster camps on Aurelian's side (top-left and bottom-left quadrants).
## id, type (a camp type from Jungle.CAMPS: "gunship" or "carrier"), pos
## [world units] and quad ("tl" = top-left quarter, "bl" = bottom-left).
## Mirrored copies become "tr" and "br" (ids like "tr_a").
const CAMPS := [
	{"id": "tl_a", "type": "gunship", "pos": Vector2(10200, 8400), "quad": "tl"},
	{"id": "tl_b", "type": "carrier", "pos": Vector2(13800, 7600), "quad": "tl"},
	{"id": "tl_c", "type": "gunship", "pos": Vector2(16600, 9100), "quad": "tl"},
	{"id": "bl_a", "type": "gunship", "pos": Vector2(10200, 17600), "quad": "bl"},
	{"id": "bl_b", "type": "carrier", "pos": Vector2(13800, 18400), "quad": "bl"},
	{"id": "bl_c", "type": "gunship", "pos": Vector2(16600, 16900), "quad": "bl"},
]
## Asteroids are kept at least this far (world units) from each camp's
## spot (MapBuilderJungle).
const CAMP_CLEAR_RADIUS := 650.0

## Jungle entrances on Aurelian's side: `lane` is a point on the corridor
## centreline, `inside` is just inside the jungle. The path between them
## passes a choke ~86 u wide (strike craft only).
## ("u" = world units; a "choke" is a narrow gap between rocks.) `quad`
## says which jungle quarter the entrance leads into.
const ENTRANCES := [
	{"quad": "tl", "lane": Vector2(11500, 3800), "inside": Vector2(11500, 5950)},
	{"quad": "tl", "lane": Vector2(16000, 3800), "inside": Vector2(16000, 5950)},
	{"quad": "tl", "lane": Vector2(11000, 13000), "inside": Vector2(11000, 10850)},
	{"quad": "tl", "lane": Vector2(15200, 13000), "inside": Vector2(15200, 10850)},
	{"quad": "tl", "lane": Vector2(20000, 7600), "inside": Vector2(18050, 7600)},
	{"quad": "tl", "lane": Vector2(6360, 7480), "inside": Vector2(8250, 8420)},
	{"quad": "bl", "lane": Vector2(11500, 22200), "inside": Vector2(11500, 20050)},
	{"quad": "bl", "lane": Vector2(16000, 22200), "inside": Vector2(16000, 20050)},
	{"quad": "bl", "lane": Vector2(11000, 13000), "inside": Vector2(11000, 15150)},
	{"quad": "bl", "lane": Vector2(15200, 13000), "inside": Vector2(15200, 15150)},
	{"quad": "bl", "lane": Vector2(20000, 18400), "inside": Vector2(18050, 18400)},
	{"quad": "bl", "lane": Vector2(6360, 18520), "inside": Vector2(8250, 17580)},
]
## Jungle path half-width and choke opening (gap between rock edges).
## Half the width of the jungle paths kept clear of filler asteroids
## (world units).
const PATH_HALF := 150.0
## The choke opening: the gap between the edges of the two rocks at each
## entrance (world units). Small ships (radius up to 17) pass; corvettes
## and bigger (radius 44 and more) do not.
const CHOKE_GAP := 86.0


## The mirror image of point `p` across the centre line: (W - x, y). This
## is how Aurelian's half becomes Cinder's. MapBuilder and its parts use it.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(W - p.x, p.y)


## The starting position of `team`'s mothership. (No script calls this at
## the moment.)
static func mothership_pos(team: int) -> Vector2:
	return MOTHERSHIPS[team]["pos"]


## Lane polyline as walked by `team` (Aurelian walks it as authored).
## Cinder walks it backwards, so for both teams the list starts at their
## own mothership and ends at the enemy's.
static func lane_points(lane: String, team: int) -> PackedVector2Array:
	var pts := PackedVector2Array(LANES[lane]["points"])
	if team == Rules.CINDER:
		pts.reverse()
	return pts
