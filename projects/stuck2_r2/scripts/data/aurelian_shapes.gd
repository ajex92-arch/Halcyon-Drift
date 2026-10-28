class_name AurelianShapes
extends RefCounted
## WHAT THIS IS: the drawings of the Aurelian pilot ships, the amber team: ten
## hulls with a steel, angular look (clean armour plates, glass canopies, engine
## nozzles, round turret sockets). Each hull is a list of named PIECES (its hull
## core, its wings, its engines and nozzles, its weapon mounts, the Bomber's
## rear turret), so a part can be swapped for another one later. The tables are
## only pictures: they change nothing in the game (sizes, hit circles and every
## number stay as they are in ships.gd).
##
## HOW IT WORKS: each hull is {"pieces": [...], "jet": [...]} (a "point" is a
## Vector2 corner, a "polygon" is a list of points; every hull is drawn with its
## nose pointing right, +x, and +y is the ship's right side, starboard, in a
## design space 36 units long that ShipVisual scales to the hull's real length):
##   "pieces"  drawn in this order, one on top of the next. A piece is
##             {"id": its name,
##              "kind": core | wing | engine | mount | rear_turret | module,
##              "shade": 0, 1 or 2 (darkest, hull, lightest plating),
##              "attach": the point of the hull the piece is fixed to (its
##                        place, so it can be swapped for another piece of the
##                        same kind that fits the same point),
##              "mirror": true = the points are the starboard copy and the
##                        port copy (y flipped) is added,
##              "pts": the piece's polygon, every point measured FROM its
##                     attach point,
##              "nozzles": engine pieces: Vector3(x, y, radius) for each
##                         engine nozzle, measured from the attach point,
##              "weapon": mount pieces: the weapon id the socket is for,
##              "marks": decals that travel with the piece, each
##                       {"kind": glass | stripe | plate | dark | green | light
##                       (filled polygons: a window, an amber stripe, a lighter
##                       plate, a vent or door, a repair plus, a running light) or
##                       line (a thin panel seam), "pts"}}.
##   "jet"     where the engine flames come out: the main flame's point, then
##             the side flames' point (its y is the distance from the middle;
##             the other side is the mirror). The flames are one stream for
##             now; "nozzles" lists where each engine's own stream can start.
## AurelianPaint merges the pieces into the hull's outline when it first draws
## the hull, so the outline is never kept by hand. Pilot hulls keep the length
## and width of the plain outlines in ShipVisual.HULLS to within about a tenth,
## except where a gun mount of ships.gd sits outside the old outline: the hull is
## drawn round the mount then (the mounts themselves never move).
## The designs are original drawings, inspired by the clean, angular, panelled
## military ships of the Star Citizen universe (forward-swept wings, twin
## nacelles, layered armour decks); no existing ship is copied.
##
## WHO USES IT: AurelianPaint turns these tables into pictures (and keeps them
## ready); ShipVisual asks AurelianPaint for them. tools/api_index.py and the
## hull gallery's checks (tests/lib/gallery_checks.gd) read the tables too.


## The ten pilot hulls: hull id -> shape (see the top of this file).
const HULLS := {

	"scout": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(17, 0), Vector2(11, 1.1), Vector2(1, 3.2), Vector2(-8, 5.5), Vector2(-12, 6.4), Vector2(-13.5, 6.4),
					Vector2(-10, 2.6), Vector2(-10, 0), Vector2(-10, -2.6), Vector2(-13.5, -6.4), Vector2(-12, -6.4), Vector2(-8, -5.5),
					Vector2(1, -3.2), Vector2(11, -1.1),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(13, 0), Vector2(11, 1.2), Vector2(4, 1.5), Vector2(2, 0), Vector2(4, -1.5), Vector2(11, -1.2)]},
					{"kind": "plate", "pts": [Vector2(1, 1.6), Vector2(-7, 3.6), Vector2(-9, 4.8), Vector2(-9, 1.6)]},
					{"kind": "plate", "pts": [Vector2(1, -1.6), Vector2(-9, -1.6), Vector2(-9, -4.8), Vector2(-7, -3.6)]},
					{"kind": "line", "pts": [Vector2(9, -0.7), Vector2(-11.5, -5.6)]},
					{"kind": "line", "pts": [Vector2(9, 0.7), Vector2(-11.5, 5.6)]},
					{"kind": "dark", "pts": [Vector2(-12.95, 6.25), Vector2(-12.1, 6.25), Vector2(-12.1, 5.4), Vector2(-12.45, 5.4)]},
					{"kind": "dark", "pts": [Vector2(-12.95, -6.25), Vector2(-12.45, -5.4), Vector2(-12.1, -5.4), Vector2(-12.1, -6.25)]},
					{"kind": "dark", "pts": [Vector2(-1.8, 2), Vector2(-1, 2), Vector2(-1, 3.4), Vector2(-1.8, 3.4)]},
					{"kind": "dark", "pts": [Vector2(-3.3, 2), Vector2(-2.5, 2), Vector2(-2.5, 3.4), Vector2(-3.3, 3.4)]},
					{"kind": "dark", "pts": [Vector2(-4.8, 2), Vector2(-4, 2), Vector2(-4, 3.4), Vector2(-4.8, 3.4)]},
					{"kind": "dark", "pts": [Vector2(-1.8, -3.4), Vector2(-1, -3.4), Vector2(-1, -2), Vector2(-1.8, -2)]},
					{"kind": "dark", "pts": [Vector2(-3.3, -3.4), Vector2(-2.5, -3.4), Vector2(-2.5, -2), Vector2(-3.3, -2)]},
					{"kind": "dark", "pts": [Vector2(-4.8, -3.4), Vector2(-4, -3.4), Vector2(-4, -2), Vector2(-4.8, -2)]},
					{"kind": "light", "pts": [Vector2(-12.72, 5.73), Vector2(-12.28, 5.73), Vector2(-12.28, 6.17), Vector2(-12.72, 6.17)]},
					{"kind": "light", "pts": [Vector2(-12.72, -6.17), Vector2(-12.28, -6.17), Vector2(-12.28, -5.73), Vector2(-12.72, -5.73)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-13.6, 0), "mirror": false,
				"pts": [
					Vector2(4.1, -2.8), Vector2(-4.2, -2.2), Vector2(-4.2, 2.2), Vector2(4.1, 2.8),
				],
				"nozzles": [Vector3(-3.6, 1.1, 0.9), Vector3(-3.6, -1.1, 0.9)],
				"marks": [
					{"kind": "line", "pts": [Vector2(3.6, -2.7), Vector2(3.6, 2.7)]},
				],
			},
			{"id": "gun", "kind": "mount", "shade": 0, "attach": Vector2(18, 0), "mirror": false,
				"weapon": "scout_gun",
				"pts": [
					Vector2(0.4, 0), Vector2(-0.6, 0.55), Vector2(-3.4, 0.55), Vector2(-3.4, -0.55), Vector2(-0.6, -0.55),
				],
			},
		],
		"jet": [Vector2(-17.8, 0), Vector2(-12.2, 5.4)],
	},
	"fighter": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(18, 0), Vector2(14.4, 1.5), Vector2(9, 2.4), Vector2(0, 2.7), Vector2(-4.5, 2.7), Vector2(-5, 0),
					Vector2(-4.5, -2.7), Vector2(0, -2.7), Vector2(9, -2.4), Vector2(14.4, -1.5),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(14, 0), Vector2(11.4, 1.3), Vector2(7.6, 1.6), Vector2(6.4, 0), Vector2(7.6, -1.6), Vector2(11.4, -1.3)]},
					{"kind": "plate", "pts": [Vector2(4.6, -1.9), Vector2(4.6, 1.9), Vector2(1.6, 2.4), Vector2(1.6, -2.4)]},
					{"kind": "line", "pts": [Vector2(-1, -2.7), Vector2(-1, 2.7)]},
				],
			},
			{"id": "wing", "kind": "wing", "shade": 2, "attach": Vector2(0, 4.5), "mirror": true,
				"pts": [
					Vector2(2.9, -2.7), Vector2(10.4, 4.3), Vector2(7, 4.3), Vector2(-3.4, -2.7),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(3.4, -1.9), Vector2(9.9, 3.9), Vector2(9.2, 3.9), Vector2(2.6, -1.8)]},
					{"kind": "line", "pts": [Vector2(1, -1.4), Vector2(8.7, 4)]},
					{"kind": "light", "pts": [Vector2(9.18, 3.78), Vector2(9.62, 3.78), Vector2(9.62, 4.22), Vector2(9.18, 4.22)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-6.4, 0), "mirror": false,
				"pts": [
					Vector2(1.9, -3), Vector2(-2, -2.6), Vector2(-2, 2.6), Vector2(1.9, 3),
				],
				"nozzles": [Vector3(-1.5, 1.5, 0.95), Vector3(-1.5, -1.5, 0.95)],
			},
			{"id": "guns", "kind": "mount", "shade": 0, "attach": Vector2(16.6, 0.7), "mirror": true,
				"weapon": "fighter_cannon",
				"pts": [
					Vector2(1.4, -0.25), Vector2(1.4, 0.25), Vector2(-4.1, 0.25), Vector2(-4.1, -0.25),
				],
			},
		],
		"jet": [Vector2(-8.4, 0), Vector2(3.4, 6.4)],
	},
	"lance": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(20, 0), Vector2(17, 0.5), Vector2(14, 1.5), Vector2(10, 2.8), Vector2(4, 3.4), Vector2(-3, 3.5),
					Vector2(-7, 2.9), Vector2(-8.5, 1.6), Vector2(-8.5, 0), Vector2(-8.5, -1.6), Vector2(-7, -2.9), Vector2(-3, -3.5),
					Vector2(4, -3.4), Vector2(10, -2.8), Vector2(14, -1.5), Vector2(17, -0.5),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(12.5, 0), Vector2(9.5, 1.5), Vector2(5.5, 1.7), Vector2(4.5, 0), Vector2(5.5, -1.7), Vector2(9.5, -1.5)]},
					{"kind": "line", "pts": [Vector2(1, -3.4), Vector2(1, 3.4)]},
					{"kind": "line", "pts": [Vector2(-4.5, -3.2), Vector2(-4.5, 3.2)]},
				],
			},
			{"id": "wing", "kind": "wing", "shade": 2, "attach": Vector2(0, 4), "mirror": true,
				"pts": [
					Vector2(4.5, -1), Vector2(6, 4), Vector2(2.5, 4), Vector2(-3.5, 1.2), Vector2(-4.5, -1),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(4.3, -0.6), Vector2(5.7, 3.7), Vector2(4.8, 3.7), Vector2(3.6, -0.6)]},
					{"kind": "light", "pts": [Vector2(5.28, 3.58), Vector2(5.72, 3.58), Vector2(5.72, 4.02), Vector2(5.28, 4.02)]},
					{"kind": "light", "pts": [Vector2(-9.82, 0.58), Vector2(-9.38, 0.58), Vector2(-9.38, 1.02), Vector2(-9.82, 1.02)]},
				],
			},
			{"id": "nacelle", "kind": "engine", "shade": 0, "attach": Vector2(0, 4.9), "mirror": true,
				"pts": [
					Vector2(8.5, 0), Vector2(7.2, -2), Vector2(-10, -2), Vector2(-10, 1.2), Vector2(7.2, 1.2),
				],
				"nozzles": [Vector3(-10, 0.1, 1.2)],
				"marks": [
					{"kind": "plate", "pts": [Vector2(5.5, -0.6), Vector2(-6, -0.6), Vector2(-6, 0.8), Vector2(5.5, 0.8)]},
				],
			},
			{"id": "tail", "kind": "wing", "shade": 1, "attach": Vector2(-8.4, 0), "mirror": false,
				"pts": [
					Vector2(1.6, -5), Vector2(-1.6, -5), Vector2(-1.6, 5), Vector2(1.6, 5),
				],
			},
			{"id": "emitter", "kind": "mount", "shade": 0, "attach": Vector2(18, 0), "mirror": false,
				"weapon": "lance_beam",
				"pts": [
					Vector2(2, 0), Vector2(-0.5, 0.6), Vector2(-5, 0.6), Vector2(-5, -0.6), Vector2(-0.5, -0.6),
				],
			},
		],
		"jet": [Vector2(-10, 0), Vector2(-4, 7)],
	},
	"bomber": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(16.5, 0), Vector2(14, 2), Vector2(9, 3.5), Vector2(2, 4.1), Vector2(-6, 4.1), Vector2(-10, 3.4),
					Vector2(-11.5, 2), Vector2(-11.5, 0), Vector2(-11.5, -2), Vector2(-10, -3.4), Vector2(-6, -4.1), Vector2(2, -4.1),
					Vector2(9, -3.5), Vector2(14, -2),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(15, -1.2), Vector2(15, 1.2), Vector2(6.5, 1.6), Vector2(6.5, -1.6)]},
					{"kind": "glass", "pts": [Vector2(5, 0), Vector2(3, 1.2), Vector2(-1, 1.5), Vector2(-2, 0), Vector2(-1, -1.5), Vector2(3, -1.2)]},
					{"kind": "line", "pts": [Vector2(-4, -4), Vector2(-4, 4)]},
				],
			},
			{"id": "wing", "kind": "wing", "shade": 2, "attach": Vector2(0, 5.5), "mirror": true,
				"pts": [
					Vector2(8, -1.9), Vector2(6, 2.5), Vector2(0.5, 2.5), Vector2(-7, 0), Vector2(-7, -1.9),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(7.6, -1.3), Vector2(5.8, 2.1), Vector2(4.9, 2.1), Vector2(6.6, -1.3)]},
					{"kind": "light", "pts": [Vector2(5.48, 2.08), Vector2(5.92, 2.08), Vector2(5.92, 2.52), Vector2(5.48, 2.52)]},
				],
			},
			{"id": "nacelle", "kind": "engine", "shade": 0, "attach": Vector2(0, 5.4), "mirror": true,
				"pts": [
					Vector2(9.5, 0), Vector2(8.5, -1), Vector2(-10.5, -1), Vector2(-11, -0.4), Vector2(-11, 0.4), Vector2(-10.5, 1),
					Vector2(8.5, 1),
				],
				"nozzles": [Vector3(-11, 0, 1.25)],
			},
			{"id": "torpedo", "kind": "mount", "shade": 2, "attach": Vector2(18.8, 0), "mirror": false,
				"weapon": "torpedo",
				"pts": [
					Vector2(1, 0), Vector2(0.2, 0.65), Vector2(-4.8, 0.85), Vector2(-4.8, -0.85), Vector2(0.2, -0.65),
				],
			},
			{"id": "rear_turret", "kind": "rear_turret", "shade": 0, "attach": Vector2(-8.5, 0), "mirror": false,
				"weapon": "tail_gun",
				"pts": [
					Vector2(1.617, 0.67), Vector2(0.67, 1.617), Vector2(-0.67, 1.617), Vector2(-1.617, 0.67), Vector2(-1.617, -0.67), Vector2(-0.67, -1.617),
					Vector2(0.67, -1.617), Vector2(1.617, -0.67),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.247, 0.517), Vector2(0.517, 1.247), Vector2(-0.517, 1.247), Vector2(-1.247, 0.517), Vector2(-1.247, -0.517), Vector2(-0.517, -1.247), Vector2(0.517, -1.247), Vector2(1.247, -0.517)]},
				],
			},
		],
		"jet": [Vector2(-11, 0), Vector2(-3, 5.5)],
	},
	"logistics": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(14, -1.8), Vector2(14, 1.8), Vector2(11, 4.2), Vector2(-8, 4.6), Vector2(-11, 3.8), Vector2(-11, -3.8),
					Vector2(-8, -4.6), Vector2(11, -4.2),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(12.2, -1.3), Vector2(12.2, 1.3), Vector2(9.8, 1.8), Vector2(9.8, -1.8)]},
					{"kind": "line", "pts": [Vector2(5, -4.4), Vector2(5, 4.4)]},
					{"kind": "line", "pts": [Vector2(-3, -4.5), Vector2(-3, 4.5)]},
				],
			},
			{"id": "bay", "kind": "module", "shade": 2, "attach": Vector2(2.5, 6.5), "mirror": true,
				"pts": [
					Vector2(9.5, -2.5), Vector2(10, -0.3), Vector2(8.5, 2.5), Vector2(-7.5, 2.5), Vector2(-9.5, 1), Vector2(-9.5, -2.3),
				],
				"marks": [
					{"kind": "green", "pts": [Vector2(0.3, -1.7), Vector2(1.7, -1.7), Vector2(1.7, -0.6), Vector2(2.8, -0.6), Vector2(2.8, 0.8), Vector2(1.7, 0.8), Vector2(1.7, 1.9), Vector2(0.3, 1.9), Vector2(0.3, 0.8), Vector2(-0.8, 0.8), Vector2(-0.8, -0.6), Vector2(0.3, -0.6)]},
					{"kind": "line", "pts": [Vector2(7, -2.1), Vector2(7, 2.3)]},
					{"kind": "dark", "pts": [Vector2(-4.3, 0.9), Vector2(-3.5, 0.9), Vector2(-3.5, 1.4), Vector2(-4.3, 1.4)]},
					{"kind": "dark", "pts": [Vector2(-5.4, 0.9), Vector2(-4.6, 0.9), Vector2(-4.6, 1.4), Vector2(-5.4, 1.4)]},
					{"kind": "dark", "pts": [Vector2(-6.5, 0.9), Vector2(-5.7, 0.9), Vector2(-5.7, 1.4), Vector2(-6.5, 1.4)]},
					{"kind": "light", "pts": [Vector2(8.68, 1.88), Vector2(9.12, 1.88), Vector2(9.12, 2.32), Vector2(8.68, 2.32)]},
					{"kind": "light", "pts": [Vector2(-9.12, 1.88), Vector2(-8.68, 1.88), Vector2(-8.68, 2.32), Vector2(-9.12, 2.32)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-12.5, 0), "mirror": false,
				"pts": [
					Vector2(1.5, -3.4), Vector2(-1.5, -2.6), Vector2(-1.5, 2.6), Vector2(1.5, 3.4),
				],
				"nozzles": [Vector3(-1.5, 1.5, 1), Vector3(-1.5, -1.5, 1)],
			},
			{"id": "mount_turret", "kind": "mount", "shade": 0, "attach": Vector2(7.6, 0), "mirror": false,
				"weapon": "light_turret",
				"pts": [
					Vector2(1.475, 0.611), Vector2(0.611, 1.475), Vector2(-0.611, 1.475), Vector2(-1.475, 0.611), Vector2(-1.475, -0.611), Vector2(-0.611, -1.475),
					Vector2(0.611, -1.475), Vector2(1.475, -0.611),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.15, 0.476), Vector2(0.476, 1.15), Vector2(-0.476, 1.15), Vector2(-1.15, 0.476), Vector2(-1.15, -0.476), Vector2(-0.476, -1.15), Vector2(0.476, -1.15), Vector2(1.15, -0.476)]},
				],
			},
		],
		"jet": [Vector2(-14, 0), Vector2(-2, 7.8)],
	},
	"support": {
		"pieces": [
			{"id": "ring", "kind": "module", "shade": 2, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(6.27, 0), Vector2(4.434, 4.434), Vector2(0, 6.27), Vector2(-4.434, 4.434), Vector2(-6.27, 0), Vector2(-4.434, -4.434),
					Vector2(0, -6.27), Vector2(4.434, -4.434),
				],
				"marks": [
					{"kind": "light", "pts": [Vector2(5.78, -0.22), Vector2(6.22, -0.22), Vector2(6.22, 0.22), Vector2(5.78, 0.22)]},
					{"kind": "light", "pts": [Vector2(-0.22, 5.78), Vector2(0.22, 5.78), Vector2(0.22, 6.22), Vector2(-0.22, 6.22)]},
					{"kind": "light", "pts": [Vector2(-0.22, -6.22), Vector2(0.22, -6.22), Vector2(0.22, -5.78), Vector2(-0.22, -5.78)]},
					{"kind": "light", "pts": [Vector2(-6.22, -0.22), Vector2(-5.78, -0.22), Vector2(-5.78, 0.22), Vector2(-6.22, 0.22)]},
					{"kind": "line", "pts": [Vector2(4.4, -4.4), Vector2(4.4, 4.4)]},
					{"kind": "line", "pts": [Vector2(-4.4, -4.4), Vector2(-4.4, 4.4)]},
				],
			},
			{"id": "floor", "kind": "module", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(4.75, 0), Vector2(3.359, 3.359), Vector2(0, 4.75), Vector2(-3.359, 3.359), Vector2(-4.75, 0), Vector2(-3.359, -3.359),
					Vector2(0, -4.75), Vector2(3.359, -3.359),
				],
			},
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(11.4, 0), Vector2(10.4, 1), Vector2(8.6, 1.5), Vector2(4.9, 1.4), Vector2(-6.3, 1.4), Vector2(-6.7, 2.7),
					Vector2(-10.3, 2.7), Vector2(-11.2, 2), Vector2(-11.2, 0), Vector2(-11.2, -2), Vector2(-10.3, -2.7), Vector2(-6.7, -2.7),
					Vector2(-6.3, -1.4), Vector2(4.9, -1.4), Vector2(8.6, -1.5), Vector2(10.4, -1),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(10.2, 0), Vector2(9.4, 0.7), Vector2(8.2, 0.7), Vector2(7.8, 0)]},
					{"kind": "line", "pts": [Vector2(-8, -2.6), Vector2(-8, 2.6)]},
					{"kind": "line", "pts": [Vector2(-3, -1.4), Vector2(-3, 1.4)]},
				],
			},
			{"id": "spoke", "kind": "wing", "shade": 1, "attach": Vector2(0, 3), "mirror": true,
				"pts": [
					Vector2(-0.6, -2), Vector2(0.6, -2), Vector2(0.6, 1.9), Vector2(-0.6, 1.9),
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-10.7, 0), "mirror": false,
				"pts": [
					Vector2(0.8, -2.7), Vector2(-0.8, -2.2), Vector2(-0.8, 2.2), Vector2(0.8, 2.7),
				],
				"nozzles": [Vector3(-0.3, 0, 0.95), Vector3(-0.3, 1.75, 0.75), Vector3(-0.3, -1.75, 0.75)],
			},
			{"id": "mount_turret", "kind": "mount", "shade": 0, "attach": Vector2(6.4, 0), "mirror": false,
				"weapon": "light_turret",
				"pts": [
					Vector2(1.319, 0.546), Vector2(0.546, 1.319), Vector2(-0.546, 1.319), Vector2(-1.319, 0.546), Vector2(-1.319, -0.546), Vector2(-0.546, -1.319),
					Vector2(0.546, -1.319), Vector2(1.319, -0.546),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.029, 0.426), Vector2(0.426, 1.029), Vector2(-0.426, 1.029), Vector2(-1.029, 0.426), Vector2(-1.029, -0.426), Vector2(-0.426, -1.029), Vector2(0.426, -1.029), Vector2(1.029, -0.426)]},
				],
			},
		],
		"jet": [Vector2(-11.5, 0), Vector2(0, 6.2)],
	},
	"flak": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(16, 0), Vector2(13.5, 2), Vector2(9, 3.8), Vector2(3, 4.8), Vector2(-5, 5.2), Vector2(-12, 5),
					Vector2(-16, 3.8), Vector2(-16, 0), Vector2(-16, -3.8), Vector2(-12, -5), Vector2(-5, -5.2), Vector2(3, -4.8),
					Vector2(9, -3.8), Vector2(13.5, -2),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(11.5, 0), Vector2(9, 2), Vector2(4.3, 3.2), Vector2(4.3, -3.2), Vector2(9, -2)]},
					{"kind": "plate", "pts": [Vector2(-1.5, -2.4), Vector2(-1.5, 2.4), Vector2(-8.5, 2.8), Vector2(-8.5, -2.8)]},
					{"kind": "glass", "pts": [Vector2(-3.2, -1.2), Vector2(-3.2, 1.2), Vector2(-6.5, 1.5), Vector2(-6.5, -1.5)]},
					{"kind": "line", "pts": [Vector2(10.5, -3.2), Vector2(10.5, 3.2)]},
					{"kind": "line", "pts": [Vector2(-10, -4.9), Vector2(-10, 4.9)]},
				],
			},
			{"id": "sponson", "kind": "wing", "shade": 2, "attach": Vector2(-1.5, 7.2), "mirror": true,
				"pts": [
					Vector2(11, -3.8), Vector2(8.7, 0.8), Vector2(6.1, 2.8), Vector2(0, 2.8), Vector2(-7.5, 2), Vector2(-11.5, -0.4),
					Vector2(-11.5, -2.6), Vector2(-3.5, -2.6),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(10.3, -2.9), Vector2(8.5, 0.8), Vector2(6.5, 2.2), Vector2(5.9, 2), Vector2(7.9, 0.6), Vector2(9.5, -2.9)]},
					{"kind": "line", "pts": [Vector2(-1.5, -1.8), Vector2(-1.5, 2.6)]},
					{"kind": "dark", "pts": [Vector2(3.2, -1.2), Vector2(4.1, -1.2), Vector2(4.1, -0.7), Vector2(3.2, -0.7)]},
					{"kind": "dark", "pts": [Vector2(1.95, -1.2), Vector2(2.85, -1.2), Vector2(2.85, -0.7), Vector2(1.95, -0.7)]},
					{"kind": "dark", "pts": [Vector2(0.7, -1.2), Vector2(1.6, -1.2), Vector2(1.6, -0.7), Vector2(0.7, -0.7)]},
					{"kind": "dark", "pts": [Vector2(3.2, 0), Vector2(4.1, 0), Vector2(4.1, 0.5), Vector2(3.2, 0.5)]},
					{"kind": "dark", "pts": [Vector2(1.95, 0), Vector2(2.85, 0), Vector2(2.85, 0.5), Vector2(1.95, 0.5)]},
					{"kind": "dark", "pts": [Vector2(0.7, 0), Vector2(1.6, 0), Vector2(1.6, 0.5), Vector2(0.7, 0.5)]},
					{"kind": "light", "pts": [Vector2(5.88, 2.28), Vector2(6.32, 2.28), Vector2(6.32, 2.72), Vector2(5.88, 2.72)]},
					{"kind": "light", "pts": [Vector2(-11.32, -0.82), Vector2(-10.88, -0.82), Vector2(-10.88, -0.38), Vector2(-11.32, -0.38)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-14.5, 0), "mirror": false,
				"pts": [
					Vector2(1.5, -4.6), Vector2(-2.3, -4), Vector2(-2.3, 4), Vector2(1.5, 4.6),
				],
				"nozzles": [Vector3(-2.3, 0, 1.35), Vector3(-2.3, 3.2, 1.05), Vector3(-2.3, -3.2, 1.05)],
			},
			{"id": "deck_flak", "kind": "module", "shade": 2, "attach": Vector2(6.86, 0), "mirror": false,
				"pts": [
					Vector2(2.772, 1.148), Vector2(1.148, 2.772), Vector2(-1.148, 2.772), Vector2(-2.772, 1.148), Vector2(-2.772, -1.148), Vector2(-1.148, -2.772),
					Vector2(1.148, -2.772), Vector2(2.772, -1.148),
				],
			},
			{"id": "mount_flak", "kind": "mount", "shade": 0, "attach": Vector2(6.86, 0), "mirror": false,
				"weapon": "flak_battery",
				"pts": [
					Vector2(1.885, 0.781), Vector2(0.781, 1.885), Vector2(-0.781, 1.885), Vector2(-1.885, 0.781), Vector2(-1.885, -0.781), Vector2(-0.781, -1.885),
					Vector2(0.781, -1.885), Vector2(1.885, -0.781),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.47, 0.609), Vector2(0.609, 1.47), Vector2(-0.609, 1.47), Vector2(-1.47, 0.609), Vector2(-1.47, -0.609), Vector2(-0.609, -1.47), Vector2(0.609, -1.47), Vector2(1.47, -0.609)]},
				],
			},
			{"id": "mount_pd", "kind": "mount", "shade": 0, "attach": Vector2(-8.57, 6.86), "mirror": true,
				"weapon": "pd_gun",
				"pts": [
					Vector2(1.22, 0.505), Vector2(0.505, 1.22), Vector2(-0.505, 1.22), Vector2(-1.22, 0.505), Vector2(-1.22, -0.505), Vector2(-0.505, -1.22),
					Vector2(0.505, -1.22), Vector2(1.22, -0.505),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.951, 0.394), Vector2(0.394, 0.951), Vector2(-0.394, 0.951), Vector2(-0.951, 0.394), Vector2(-0.951, -0.394), Vector2(-0.394, -0.951), Vector2(0.394, -0.951), Vector2(0.951, -0.394)]},
				],
			},
		],
		"jet": [Vector2(-16.8, 0), Vector2(-4, 8)],
	},
	"ion": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(18, 0), Vector2(15.5, 1), Vector2(12, 2), Vector2(6, 3), Vector2(-4, 3.6), Vector2(-12, 3.6),
					Vector2(-15, 3), Vector2(-15, 0), Vector2(-15, -3), Vector2(-12, -3.6), Vector2(-4, -3.6), Vector2(6, -3),
					Vector2(12, -2), Vector2(15.5, -1),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(8.5, 0), Vector2(6.2, 1), Vector2(2.5, 1.3), Vector2(1.5, 0), Vector2(2.5, -1.3), Vector2(6.2, -1)]},
					{"kind": "plate", "pts": [Vector2(-1, -2.4), Vector2(-1, 2.4), Vector2(-10, 2.6), Vector2(-10, -2.6)]},
					{"kind": "line", "pts": [Vector2(4, -3), Vector2(4, 3)]},
					{"kind": "line", "pts": [Vector2(-12, -3.5), Vector2(-12, 3.5)]},
				],
			},
			{"id": "emitter", "kind": "mount", "shade": 0, "attach": Vector2(16.4, 0), "mirror": false,
				"weapon": "ion_cannon",
				"pts": [
					Vector2(1.6, 0), Vector2(0.1, 0.9), Vector2(-6.4, 1.2), Vector2(-6.4, -1.2), Vector2(0.1, -0.9),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(-0.2, 0), Vector2(-1.2, 0.45), Vector2(-2.2, 0), Vector2(-1.2, -0.45)]},
					{"kind": "line", "pts": [Vector2(-3.4, -1), Vector2(-3.4, 1)]},
					{"kind": "line", "pts": [Vector2(-4.9, -1.1), Vector2(-4.9, 1.1)]},
				],
			},
			{"id": "nacelle", "kind": "engine", "shade": 1, "attach": Vector2(-8, 5.2), "mirror": true,
				"pts": [
					Vector2(7, -2.2), Vector2(6, 1.4), Vector2(-8, 1.8), Vector2(-8, -0.3), Vector2(1.5, -0.3), Vector2(2, -2.2),
				],
				"nozzles": [Vector3(-8, 0.7, 1.1)],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(4.5, 1.3), Vector2(-6.5, 1.4), Vector2(-6.5, 1), Vector2(5, 0.9)]},
					{"kind": "light", "pts": [Vector2(-7.82, 1.38), Vector2(-7.38, 1.38), Vector2(-7.38, 1.82), Vector2(-7.82, 1.82)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-14.5, 0), "mirror": false,
				"pts": [
					Vector2(1.5, -2.4), Vector2(-1.5, -2), Vector2(-1.5, 2), Vector2(1.5, 2.4),
				],
				"nozzles": [Vector3(-1.5, 0, 0.95)],
			},
			{"id": "fin", "kind": "wing", "shade": 2, "attach": Vector2(4, 5), "mirror": true,
				"pts": [
					Vector2(4, -2.2), Vector2(6.5, 0.8), Vector2(0, 1.6), Vector2(-5, -1.7),
				],
				"marks": [
					{"kind": "light", "pts": [Vector2(5.98, 0.48), Vector2(6.42, 0.48), Vector2(6.42, 0.92), Vector2(5.98, 0.92)]},
				],
			},
			{"id": "mount_pd", "kind": "mount", "shade": 0, "attach": Vector2(-6.5, 0), "mirror": false,
				"weapon": "pd_gun",
				"pts": [
					Vector2(1.159, 0.48), Vector2(0.48, 1.159), Vector2(-0.48, 1.159), Vector2(-1.159, 0.48), Vector2(-1.159, -0.48), Vector2(-0.48, -1.159),
					Vector2(0.48, -1.159), Vector2(1.159, -0.48),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.904, 0.374), Vector2(0.374, 0.904), Vector2(-0.374, 0.904), Vector2(-0.904, 0.374), Vector2(-0.904, -0.374), Vector2(-0.374, -0.904), Vector2(0.374, -0.904), Vector2(0.904, -0.374)]},
				],
			},
		],
		"jet": [Vector2(-16, 0), Vector2(-4, 6.5)],
	},
	"destroyer": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(18, 0), Vector2(16, 0.9), Vector2(13.5, 1.7), Vector2(10, 2.3), Vector2(5, 3), Vector2(-3, 3.5),
					Vector2(-11, 3.7), Vector2(-17, 3.4), Vector2(-18, 3), Vector2(-18, 0), Vector2(-18, -3), Vector2(-17, -3.4),
					Vector2(-11, -3.7), Vector2(-3, -3.5), Vector2(5, -3), Vector2(10, -2.3), Vector2(13.5, -1.7), Vector2(16, -0.9),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(17, 0), Vector2(13, 1.2), Vector2(8, 1.7), Vector2(8, -1.7), Vector2(13, -1.2)]},
					{"kind": "plate", "pts": [Vector2(6.5, -1.9), Vector2(6.5, 1.9), Vector2(2.5, 2.2), Vector2(2.5, -2.2)]},
					{"kind": "plate", "pts": [Vector2(-7, -1.9), Vector2(-7, 1.9), Vector2(-14.5, 2.4), Vector2(-14.5, -2.4)]},
					{"kind": "glass", "pts": [Vector2(-8.4, -1.2), Vector2(-8.4, 1.2), Vector2(-11.5, 1.5), Vector2(-11.5, -1.5)]},
					{"kind": "dark", "pts": [Vector2(-2.8, 2.3), Vector2(-8.6, 2.3), Vector2(-8.6, 3.3), Vector2(-2.8, 3.3)]},
					{"kind": "dark", "pts": [Vector2(-2.8, -3.3), Vector2(-8.6, -3.3), Vector2(-8.6, -2.3), Vector2(-2.8, -2.3)]},
					{"kind": "line", "pts": [Vector2(8, -3), Vector2(8, 3)]},
					{"kind": "line", "pts": [Vector2(-1, -3.4), Vector2(-1, 3.4)]},
					{"kind": "line", "pts": [Vector2(-13, 0), Vector2(-17.4, 0)]},
				],
			},
			{"id": "sponson", "kind": "wing", "shade": 2, "attach": Vector2(4.1, 5), "mirror": true,
				"pts": [
					Vector2(4.7, -2.6), Vector2(4.1, 0.2), Vector2(2.9, 2), Vector2(0.9, 2.5), Vector2(-2.5, 2.5), Vector2(-3.9, 1.2),
					Vector2(-3.9, -2.4),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(4.1, -2), Vector2(3.7, 0), Vector2(2.7, 1.6), Vector2(2.1, 1.4), Vector2(2.9, 0), Vector2(3.3, -2)]},
					{"kind": "dark", "pts": [Vector2(-1.3, -1.8), Vector2(-0.5, -1.8), Vector2(-0.5, -1.3), Vector2(-1.3, -1.3)]},
					{"kind": "dark", "pts": [Vector2(-2.4, -1.8), Vector2(-1.6, -1.8), Vector2(-1.6, -1.3), Vector2(-2.4, -1.3)]},
					{"kind": "dark", "pts": [Vector2(-3.5, -1.8), Vector2(-2.7, -1.8), Vector2(-2.7, -1.3), Vector2(-3.5, -1.3)]},
					{"kind": "light", "pts": [Vector2(0.68, 2.08), Vector2(1.12, 2.08), Vector2(1.12, 2.52), Vector2(0.68, 2.52)]},
				],
			},
			{"id": "aft", "kind": "wing", "shade": 2, "attach": Vector2(-13, 4.3), "mirror": true,
				"pts": [
					Vector2(6, -1.3), Vector2(4.5, 0.9), Vector2(2, 1.7), Vector2(-5, 1.7), Vector2(-5, -1.3),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(3, -0.9), Vector2(3, 1.6)]},
					{"kind": "line", "pts": [Vector2(-1, -0.9), Vector2(-1, 1.6)]},
					{"kind": "light", "pts": [Vector2(-4.82, 1.28), Vector2(-4.38, 1.28), Vector2(-4.38, 1.72), Vector2(-4.82, 1.72)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-16.4, 0), "mirror": false,
				"pts": [
					Vector2(2.4, -4.2), Vector2(-2.4, -3.6), Vector2(-2.4, 3.6), Vector2(2.4, 4.2),
				],
				"nozzles": [Vector3(-2.4, 1.3, 0.95), Vector3(-2.4, -1.3, 0.95), Vector3(-2.4, 3.4, 0.8), Vector3(-2.4, -3.4, 0.8)],
			},
			{"id": "mount_heavy_fore", "kind": "mount", "shade": 0, "attach": Vector2(10.29, 0), "mirror": false,
				"weapon": "heavy_cannon",
				"pts": [
					Vector2(1.663, 0.689), Vector2(0.689, 1.663), Vector2(-0.689, 1.663), Vector2(-1.663, 0.689), Vector2(-1.663, -0.689), Vector2(-0.689, -1.663),
					Vector2(0.689, -1.663), Vector2(1.663, -0.689),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.297, 0.537), Vector2(0.537, 1.297), Vector2(-0.537, 1.297), Vector2(-1.297, 0.537), Vector2(-1.297, -0.537), Vector2(-0.537, -1.297), Vector2(0.537, -1.297), Vector2(1.297, -0.537)]},
				],
			},
			{"id": "mount_heavy_aft", "kind": "mount", "shade": 0, "attach": Vector2(-5.14, 0), "mirror": false,
				"weapon": "heavy_cannon",
				"pts": [
					Vector2(1.663, 0.689), Vector2(0.689, 1.663), Vector2(-0.689, 1.663), Vector2(-1.663, 0.689), Vector2(-1.663, -0.689), Vector2(-0.689, -1.663),
					Vector2(0.689, -1.663), Vector2(1.663, -0.689),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.297, 0.537), Vector2(0.537, 1.297), Vector2(-0.537, 1.297), Vector2(-1.297, 0.537), Vector2(-1.297, -0.537), Vector2(-0.537, -1.297), Vector2(0.537, -1.297), Vector2(1.297, -0.537)]},
				],
			},
			{"id": "mount_flak", "kind": "mount", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"weapon": "flak_auto",
				"pts": [
					Vector2(1.414, 0.586), Vector2(0.586, 1.414), Vector2(-0.586, 1.414), Vector2(-1.414, 0.586), Vector2(-1.414, -0.586), Vector2(-0.586, -1.414),
					Vector2(0.586, -1.414), Vector2(1.414, -0.586),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.103, 0.457), Vector2(0.457, 1.103), Vector2(-0.457, 1.103), Vector2(-1.103, 0.457), Vector2(-1.103, -0.457), Vector2(-0.457, -1.103), Vector2(0.457, -1.103), Vector2(1.103, -0.457)]},
				],
			},
			{"id": "mount_pd_fore", "kind": "mount", "shade": 0, "attach": Vector2(5.14, 6), "mirror": true,
				"weapon": "pd_gun",
				"pts": [
					Vector2(0.915, 0.379), Vector2(0.379, 0.915), Vector2(-0.379, 0.915), Vector2(-0.915, 0.379), Vector2(-0.915, -0.379), Vector2(-0.379, -0.915),
					Vector2(0.379, -0.915), Vector2(0.915, -0.379),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.713, 0.296), Vector2(0.296, 0.713), Vector2(-0.296, 0.713), Vector2(-0.713, 0.296), Vector2(-0.713, -0.296), Vector2(-0.296, -0.713), Vector2(0.296, -0.713), Vector2(0.713, -0.296)]},
				],
			},
			{"id": "mount_pd_aft", "kind": "mount", "shade": 0, "attach": Vector2(-12, 0), "mirror": false,
				"weapon": "pd_gun",
				"pts": [
					Vector2(0.915, 0.379), Vector2(0.379, 0.915), Vector2(-0.379, 0.915), Vector2(-0.915, 0.379), Vector2(-0.915, -0.379), Vector2(-0.379, -0.915),
					Vector2(0.379, -0.915), Vector2(0.915, -0.379),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.713, 0.296), Vector2(0.296, 0.713), Vector2(-0.296, 0.713), Vector2(-0.713, 0.296), Vector2(-0.713, -0.296), Vector2(-0.296, -0.713), Vector2(0.296, -0.713), Vector2(0.713, -0.296)]},
				],
			},
		],
		"jet": [Vector2(-18.8, 0), Vector2(-6, 4.6)],
	},
	"battlecruiser": {
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(18, 0), Vector2(15.5, 1.4), Vector2(11, 2.8), Vector2(6, 3.4), Vector2(0, 3.6), Vector2(-8, 3.8),
					Vector2(-14, 3.8), Vector2(-18, 3.2), Vector2(-18, 0), Vector2(-18, -3.2), Vector2(-14, -3.8), Vector2(-8, -3.8),
					Vector2(0, -3.6), Vector2(6, -3.4), Vector2(11, -2.8), Vector2(15.5, -1.4),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(16.5, 0), Vector2(13, 1.3), Vector2(9, 2), Vector2(9, -2), Vector2(13, -1.3)]},
					{"kind": "plate", "pts": [Vector2(-3, -2), Vector2(-3, 2), Vector2(-12.5, 2.6), Vector2(-12.5, -2.6)]},
					{"kind": "glass", "pts": [Vector2(-5.4, -1.3), Vector2(-5.4, 1.3), Vector2(-9.8, 1.6), Vector2(-9.8, -1.6)]},
					{"kind": "line", "pts": [Vector2(8, -3.2), Vector2(8, 3.2)]},
					{"kind": "line", "pts": [Vector2(-1.5, -3.6), Vector2(-1.5, 3.6)]},
					{"kind": "line", "pts": [Vector2(-12.8, 0), Vector2(-17.4, 0)]},
				],
			},
			{"id": "shoulder", "kind": "wing", "shade": 2, "attach": Vector2(6.6, 5), "mirror": true,
				"pts": [
					Vector2(2.9, -2.2), Vector2(2.4, 1), Vector2(1.2, 2.3), Vector2(-1.4, 2.3), Vector2(-2.8, 1), Vector2(-2.8, -2.2),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(2.2, -1.6), Vector2(1.8, 1), Vector2(0.8, 1.9), Vector2(0.2, 1.7), Vector2(1.2, 0.9), Vector2(1.6, -1.6)]},
					{"kind": "light", "pts": [Vector2(-1.22, 1.88), Vector2(-0.78, 1.88), Vector2(-0.78, 2.32), Vector2(-1.22, 2.32)]},
				],
			},
			{"id": "deck", "kind": "wing", "shade": 1, "attach": Vector2(-1.3, 4.4), "mirror": true,
				"pts": [
					Vector2(4.3, -1.4), Vector2(4.3, 0.8), Vector2(2.5, 1.4), Vector2(-2.7, 1.4), Vector2(-4.3, 0.4), Vector2(-4.3, -1.4),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(2.7, -0.4), Vector2(3.5, -0.4), Vector2(3.5, 0.05), Vector2(2.7, 0.05)]},
					{"kind": "dark", "pts": [Vector2(1.6, -0.4), Vector2(2.4, -0.4), Vector2(2.4, 0.05), Vector2(1.6, 0.05)]},
					{"kind": "dark", "pts": [Vector2(0.5, -0.4), Vector2(1.3, -0.4), Vector2(1.3, 0.05), Vector2(0.5, 0.05)]},
					{"kind": "dark", "pts": [Vector2(-0.6, -0.4), Vector2(0.2, -0.4), Vector2(0.2, 0.05), Vector2(-0.6, 0.05)]},
					{"kind": "dark", "pts": [Vector2(0.8, 0.6), Vector2(-3.5, 0.6), Vector2(-3.5, 1.2), Vector2(0.8, 1.2)]},
				],
			},
			{"id": "aft", "kind": "wing", "shade": 2, "attach": Vector2(-12, 5), "mirror": true,
				"pts": [
					Vector2(7, -1.6), Vector2(5, 1.2), Vector2(1, 2), Vector2(-3, 1.8), Vector2(-6, 0.4), Vector2(-6, -1.6),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(3, -1.2), Vector2(3, 1.8)]},
					{"kind": "line", "pts": [Vector2(-1.5, -1.2), Vector2(-1.5, 1.6)]},
					{"kind": "light", "pts": [Vector2(-5.82, 0.08), Vector2(-5.38, 0.08), Vector2(-5.38, 0.52), Vector2(-5.82, 0.52)]},
					{"kind": "light", "pts": [Vector2(3.38, 1.58), Vector2(3.82, 1.58), Vector2(3.82, 2.02), Vector2(3.38, 2.02)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-16.4, 0), "mirror": false,
				"pts": [
					Vector2(2.4, -4.8), Vector2(-2.4, -4.4), Vector2(-2.4, 4.4), Vector2(2.4, 4.8),
				],
				"nozzles": [Vector3(-2.4, 0, 1.05), Vector3(-2.4, 2.3, 0.95), Vector3(-2.4, -2.3, 0.95), Vector3(-2.4, 4.2, 0.6), Vector3(-2.4, -4.2, 0.6)],
			},
			{"id": "mount_ion_fore", "kind": "mount", "shade": 0, "attach": Vector2(10.93, 0), "mirror": false,
				"weapon": "ion_turret",
				"pts": [
					Vector2(1.053, 0.436), Vector2(0.436, 1.053), Vector2(-0.436, 1.053), Vector2(-1.053, 0.436), Vector2(-1.053, -0.436), Vector2(-0.436, -1.053),
					Vector2(0.436, -1.053), Vector2(1.053, -0.436),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.822, 0.34), Vector2(0.34, 0.822), Vector2(-0.34, 0.822), Vector2(-0.822, 0.34), Vector2(-0.822, -0.34), Vector2(-0.34, -0.822), Vector2(0.34, -0.822), Vector2(0.822, -0.34)]},
				],
			},
			{"id": "mount_ion_aft", "kind": "mount", "shade": 0, "attach": Vector2(-8.36, 0), "mirror": false,
				"weapon": "ion_turret",
				"pts": [
					Vector2(1.053, 0.436), Vector2(0.436, 1.053), Vector2(-0.436, 1.053), Vector2(-1.053, 0.436), Vector2(-1.053, -0.436), Vector2(-0.436, -1.053),
					Vector2(0.436, -1.053), Vector2(1.053, -0.436),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.822, 0.34), Vector2(0.34, 0.822), Vector2(-0.34, 0.822), Vector2(-0.822, 0.34), Vector2(-0.822, -0.34), Vector2(-0.34, -0.822), Vector2(0.34, -0.822), Vector2(0.822, -0.34)]},
				],
			},
			{"id": "mount_heavy", "kind": "mount", "shade": 0, "attach": Vector2(1.93, 0), "mirror": false,
				"weapon": "heavy_cannon",
				"pts": [
					Vector2(1.053, 0.436), Vector2(0.436, 1.053), Vector2(-0.436, 1.053), Vector2(-1.053, 0.436), Vector2(-1.053, -0.436), Vector2(-0.436, -1.053),
					Vector2(0.436, -1.053), Vector2(1.053, -0.436),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.822, 0.34), Vector2(0.34, 0.822), Vector2(-0.34, 0.822), Vector2(-0.822, 0.34), Vector2(-0.822, -0.34), Vector2(-0.34, -0.822), Vector2(0.34, -0.822), Vector2(0.822, -0.34)]},
				],
			},
			{"id": "mount_flak_fore", "kind": "mount", "shade": 0, "attach": Vector2(3.86, 0), "mirror": false,
				"weapon": "flak_auto",
				"pts": [
					Vector2(0.783, 0.324), Vector2(0.324, 0.783), Vector2(-0.324, 0.783), Vector2(-0.783, 0.324), Vector2(-0.783, -0.324), Vector2(-0.324, -0.783),
					Vector2(0.324, -0.783), Vector2(0.783, -0.324),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.611, 0.253), Vector2(0.253, 0.611), Vector2(-0.253, 0.611), Vector2(-0.611, 0.253), Vector2(-0.611, -0.253), Vector2(-0.253, -0.611), Vector2(0.253, -0.611), Vector2(0.611, -0.253)]},
				],
			},
			{"id": "mount_flak_aft", "kind": "mount", "shade": 0, "attach": Vector2(-5.14, 0), "mirror": false,
				"weapon": "flak_auto",
				"pts": [
					Vector2(0.783, 0.324), Vector2(0.324, 0.783), Vector2(-0.324, 0.783), Vector2(-0.783, 0.324), Vector2(-0.783, -0.324), Vector2(-0.324, -0.783),
					Vector2(0.324, -0.783), Vector2(0.783, -0.324),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.611, 0.253), Vector2(0.253, 0.611), Vector2(-0.253, 0.611), Vector2(-0.611, 0.253), Vector2(-0.611, -0.253), Vector2(-0.253, -0.611), Vector2(0.253, -0.611), Vector2(0.611, -0.253)]},
				],
			},
			{"id": "mount_pd_fore", "kind": "mount", "shade": 0, "attach": Vector2(7.71, 5.79), "mirror": true,
				"weapon": "pd_gun",
				"pts": [
					Vector2(0.579, 0.24), Vector2(0.24, 0.579), Vector2(-0.24, 0.579), Vector2(-0.579, 0.24), Vector2(-0.579, -0.24), Vector2(-0.24, -0.579),
					Vector2(0.24, -0.579), Vector2(0.579, -0.24),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.452, 0.187), Vector2(0.187, 0.452), Vector2(-0.187, 0.452), Vector2(-0.452, 0.187), Vector2(-0.452, -0.187), Vector2(-0.187, -0.452), Vector2(0.187, -0.452), Vector2(0.452, -0.187)]},
				],
			},
			{"id": "mount_pd_aft", "kind": "mount", "shade": 0, "attach": Vector2(-11.57, 5.14), "mirror": true,
				"weapon": "pd_gun",
				"pts": [
					Vector2(0.579, 0.24), Vector2(0.24, 0.579), Vector2(-0.24, 0.579), Vector2(-0.579, 0.24), Vector2(-0.579, -0.24), Vector2(-0.24, -0.579),
					Vector2(0.24, -0.579), Vector2(0.579, -0.24),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.452, 0.187), Vector2(0.187, 0.452), Vector2(-0.187, 0.452), Vector2(-0.452, 0.187), Vector2(-0.452, -0.187), Vector2(-0.187, -0.452), Vector2(0.187, -0.452), Vector2(0.452, -0.187)]},
				],
			},
		],
		"jet": [Vector2(-18.8, 0), Vector2(-6, 5.5)],
	},
}
