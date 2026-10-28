class_name StructureShapes
extends RefCounted
## WHAT THIS IS: the drawings of the Aurelian mothership and of the structures both
## teams build: the lane point-defense tower, the lane torpedo tower and the
## Admiral's Repair Bay. Each is a list of named PIECES, like the Aurelian pilot
## hulls in AurelianShapes (same piece shape, same decal kinds). The tables are only
## pictures: they change nothing in the game (hit circles, guns and every number stay
## as they are in turret_data.gd and structures.gd).
##
## HOW IT WORKS: each entry is
##   "size"    how many world units the structure's 36 design units are: the
##             mothership's length, and the hit diameter (twice the radius) of the
##             towers and the bay. The structure's own hit shape does not change;
##             the drawing may reach up to 15% of the radius past it.
##   "pieces"  the pieces, drawn in this order, as in AurelianShapes ("kind" is
##             core | wing | engine | mount | module; a "mount" piece is the round
##             socket under a gun and carries the gun's weapon id). Besides the
##             decal kinds of AurelianShapes there is "warhead" (the red-orange tip
##             of a fixed torpedo, the same colour for both teams) and "green" is the
##             repair colour of both teams.
##   "vhorr"   optional: more pieces (thorns) that only the Vhorr dress adds. The
##             Vhorr dress is the same pieces in the Cinder colours.
##   "jet"     the mothership's engine points (nothing flies out of them yet).
## Design space: +x is forward (a tower's +x points away from the resource node it
## stands on, the Repair Bay's the way it flew in), +y is starboard. A gun sits at
## the middle of a tower or bay; the mothership's 21 gun spots are the "mount"
## pieces. TurretShapes.HULL_TU gives the size of the gun heads drawn on them.
##
## WHO USES IT: AurelianPaint.structure() turns these tables into pictures for
## UnitVisual; the hull gallery's checks (tests/lib/gallery_structures.gd) read them.


## The four structures: id -> shape (see the top of this file).
const SHAPES := {

	"mothership": {
		"size": 1600,
		"pieces": [
			{"id": "slip", "kind": "core", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(15, 0), Vector2(15, 2), Vector2(-13.8, 2), Vector2(-13.8, 0), Vector2(-13.8, -2), Vector2(15, -2),
				],
			},
			{"id": "hull", "kind": "core", "shade": 1, "attach": Vector2(0, 2.9), "mirror": true,
				"pts": [
					Vector2(14.6, -1.5), Vector2(15.6, -0.5), Vector2(15.6, 0.5), Vector2(14.4, 1.4), Vector2(-16.8, 1.4), Vector2(-18, 0.5),
					Vector2(-18, -0.7), Vector2(-16.6, -1.5),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(-2.4, -1), Vector2(13.8, -1), Vector2(13.8, 1), Vector2(-2.4, 1)]},
					{"kind": "plate", "pts": [Vector2(-16, -1), Vector2(-3.4, -1), Vector2(-3.4, 1), Vector2(-16, 1)]},
					{"kind": "stripe", "pts": [Vector2(-16.6, -1.48), Vector2(14.6, -1.48), Vector2(14.6, -1.3), Vector2(-16.6, -1.3)]},
					{"kind": "line", "pts": [Vector2(8.2, -1.5), Vector2(8.2, 1.4)]},
					{"kind": "line", "pts": [Vector2(-2.9, -1.5), Vector2(-2.9, 1.4)]},
					{"kind": "line", "pts": [Vector2(-11.6, -1.5), Vector2(-11.6, 1.4)]},
					{"kind": "dark", "pts": [Vector2(-13.5, -0.6), Vector2(-13, -0.6), Vector2(-13, 0.2), Vector2(-13.5, 0.2)]},
					{"kind": "dark", "pts": [Vector2(-14.4, -0.6), Vector2(-13.9, -0.6), Vector2(-13.9, 0.2), Vector2(-14.4, 0.2)]},
					{"kind": "dark", "pts": [Vector2(-15.3, -0.6), Vector2(-14.8, -0.6), Vector2(-14.8, 0.2), Vector2(-15.3, 0.2)]},
					{"kind": "light", "pts": [Vector2(15.08, -0.22), Vector2(15.52, -0.22), Vector2(15.52, 0.22), Vector2(15.08, 0.22)]},
					{"kind": "light", "pts": [Vector2(-16.42, 0.93), Vector2(-15.98, 0.93), Vector2(-15.98, 1.37), Vector2(-16.42, 1.37)]},
				],
			},
			{"id": "cross_fore", "kind": "module", "shade": 2, "attach": Vector2(4.5, 0), "mirror": false,
				"pts": [
					Vector2(-1.7, -2.1), Vector2(1.7, -2.1), Vector2(1.7, 2.1), Vector2(-1.7, 2.1),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(1.5, 0), Vector2(1.1, 0.6), Vector2(-1.1, 0.6), Vector2(-1.5, 0), Vector2(-1.1, -0.6), Vector2(1.1, -0.6)]},
				],
			},
			{"id": "cross_aft", "kind": "module", "shade": 2, "attach": Vector2(-6.7, 0), "mirror": false,
				"pts": [
					Vector2(-1.7, -2.1), Vector2(1.7, -2.1), Vector2(1.7, 2.1), Vector2(-1.7, 2.1),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(-0.4, -0.5), Vector2(0.4, -0.5), Vector2(0.4, 0.5), Vector2(-0.4, 0.5)]},
				],
			},
			{"id": "prow", "kind": "module", "shade": 2, "attach": Vector2(15.9, 0), "mirror": false,
				"pts": [
					Vector2(2.5, 0), Vector2(1.5, 1.3), Vector2(-2.5, 2.6), Vector2(-2.5, 0), Vector2(-2.5, -2.6), Vector2(1.5, -1.3),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(1.1, 0.35), Vector2(-1.9, 2.25), Vector2(-1.9, 1.85), Vector2(0.7, 0.15)]},
					{"kind": "stripe", "pts": [Vector2(1.1, -0.35), Vector2(0.7, -0.15), Vector2(-1.9, -1.85), Vector2(-1.9, -2.25)]},
				],
			},
			{"id": "brace", "kind": "module", "shade": 2, "attach": Vector2(-14.5, 0), "mirror": false,
				"pts": [
					Vector2(-1.1, -1.8), Vector2(1.1, -1.8), Vector2(1.1, 1.8), Vector2(-1.1, 1.8),
				],
				"marks": [
					{"kind": "light", "pts": [Vector2(-1.02, 1.18), Vector2(-0.58, 1.18), Vector2(-0.58, 1.62), Vector2(-1.02, 1.62)]},
					{"kind": "light", "pts": [Vector2(-1.02, -1.62), Vector2(-0.58, -1.62), Vector2(-0.58, -1.18), Vector2(-1.02, -1.18)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-16.6, 2.85), "mirror": true,
				"pts": [
					Vector2(1.6, -0.95), Vector2(-1.6, -0.95), Vector2(-1.6, 0.95), Vector2(1.6, 0.95),
				],
				"nozzles": [Vector3(-0.9, 0, 0.75)],
				"marks": [
					{"kind": "line", "pts": [Vector2(0.8, -0.95), Vector2(0.8, 0.95)]},
				],
			},
			{"id": "pd_bow", "kind": "mount", "shade": 0, "attach": Vector2(12.6, 2.7), "mirror": true,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "pd_mid", "kind": "mount", "shade": 0, "attach": Vector2(2.25, 3.375), "mirror": true,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "pd_aft", "kind": "mount", "shade": 0, "attach": Vector2(-9, 2.925), "mirror": true,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "cannon", "kind": "mount", "shade": 0, "attach": Vector2(6.75, 2.25), "mirror": true,
				"weapon": "ms_cannon",
				"pts": [
					Vector2(0.554, 0.23), Vector2(0.23, 0.554), Vector2(-0.23, 0.554), Vector2(-0.554, 0.23), Vector2(-0.554, -0.23), Vector2(-0.23, -0.554),
					Vector2(0.23, -0.554), Vector2(0.554, -0.23),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.432, 0.179), Vector2(0.179, 0.432), Vector2(-0.179, 0.432), Vector2(-0.432, 0.179), Vector2(-0.432, -0.179), Vector2(-0.179, -0.432), Vector2(0.179, -0.432), Vector2(0.432, -0.179)]},
				],
			},
			{"id": "pd_prow", "kind": "mount", "shade": 0, "attach": Vector2(15.75, 0), "mirror": false,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "pd_x_mid", "kind": "mount", "shade": 0, "attach": Vector2(-3.375, 3.6), "mirror": true,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "pd_stern", "kind": "mount", "shade": 0, "attach": Vector2(-14.625, 0), "mirror": false,
				"weapon": "ms_pd",
				"pts": [
					Vector2(0.305, 0.126), Vector2(0.126, 0.305), Vector2(-0.126, 0.305), Vector2(-0.305, 0.126), Vector2(-0.305, -0.126), Vector2(-0.126, -0.305),
					Vector2(0.126, -0.305), Vector2(0.305, -0.126),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.238, 0.099), Vector2(0.099, 0.238), Vector2(-0.099, 0.238), Vector2(-0.238, 0.099), Vector2(-0.238, -0.099), Vector2(-0.099, -0.238), Vector2(0.099, -0.238), Vector2(0.238, -0.099)]},
				],
			},
			{"id": "flak_bow", "kind": "mount", "shade": 0, "attach": Vector2(10.125, 3.15), "mirror": true,
				"weapon": "ms_flak",
				"pts": [
					Vector2(0.471, 0.195), Vector2(0.195, 0.471), Vector2(-0.195, 0.471), Vector2(-0.471, 0.195), Vector2(-0.471, -0.195), Vector2(-0.195, -0.471),
					Vector2(0.195, -0.471), Vector2(0.471, -0.195),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.368, 0.152), Vector2(0.152, 0.368), Vector2(-0.152, 0.368), Vector2(-0.368, 0.152), Vector2(-0.368, -0.152), Vector2(-0.152, -0.368), Vector2(0.152, -0.368), Vector2(0.368, -0.152)]},
				],
			},
			{"id": "flak_aft", "kind": "mount", "shade": 0, "attach": Vector2(-5.625, 3.375), "mirror": true,
				"weapon": "ms_flak",
				"pts": [
					Vector2(0.471, 0.195), Vector2(0.195, 0.471), Vector2(-0.195, 0.471), Vector2(-0.471, 0.195), Vector2(-0.471, -0.195), Vector2(-0.195, -0.471),
					Vector2(0.195, -0.471), Vector2(0.471, -0.195),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.368, 0.152), Vector2(0.152, 0.368), Vector2(-0.152, 0.368), Vector2(-0.368, 0.152), Vector2(-0.368, -0.152), Vector2(-0.152, -0.368), Vector2(0.152, -0.368), Vector2(0.368, -0.152)]},
				],
			},
			{"id": "heavy_fore", "kind": "mount", "shade": 0, "attach": Vector2(4.5, 1.35), "mirror": true,
				"weapon": "ms_heavy",
				"pts": [
					Vector2(0.554, 0.23), Vector2(0.23, 0.554), Vector2(-0.23, 0.554), Vector2(-0.554, 0.23), Vector2(-0.554, -0.23), Vector2(-0.23, -0.554),
					Vector2(0.23, -0.554), Vector2(0.554, -0.23),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.432, 0.179), Vector2(0.179, 0.432), Vector2(-0.179, 0.432), Vector2(-0.432, 0.179), Vector2(-0.432, -0.179), Vector2(-0.179, -0.432), Vector2(0.179, -0.432), Vector2(0.432, -0.179)]},
				],
			},
			{"id": "heavy_aft", "kind": "mount", "shade": 0, "attach": Vector2(-6.75, 1.35), "mirror": true,
				"weapon": "ms_heavy",
				"pts": [
					Vector2(0.554, 0.23), Vector2(0.23, 0.554), Vector2(-0.23, 0.554), Vector2(-0.554, 0.23), Vector2(-0.554, -0.23), Vector2(-0.23, -0.554),
					Vector2(0.23, -0.554), Vector2(0.554, -0.23),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.432, 0.179), Vector2(0.179, 0.432), Vector2(-0.179, 0.432), Vector2(-0.432, 0.179), Vector2(-0.432, -0.179), Vector2(-0.179, -0.432), Vector2(0.179, -0.432), Vector2(0.432, -0.179)]},
				],
			},
			{"id": "ion", "kind": "mount", "shade": 0, "attach": Vector2(14.625, 0), "mirror": false,
				"weapon": "ms_ion",
				"pts": [
					Vector2(0.554, 0.23), Vector2(0.23, 0.554), Vector2(-0.23, 0.554), Vector2(-0.554, 0.23), Vector2(-0.554, -0.23), Vector2(-0.23, -0.554),
					Vector2(0.23, -0.554), Vector2(0.554, -0.23),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(0.432, 0.179), Vector2(0.179, 0.432), Vector2(-0.179, 0.432), Vector2(-0.432, 0.179), Vector2(-0.432, -0.179), Vector2(-0.179, -0.432), Vector2(0.179, -0.432), Vector2(0.432, -0.179)]},
				],
			},
		],
		"jet": [Vector2(-18.2, 2.85), Vector2(-14, 4)],
	},
	"pd_tower": {
		"size": 120,
		"pieces": [
			{"id": "leg_fwd", "kind": "wing", "shade": 2, "attach": Vector2(6.5, 11.26), "mirror": true,
				"pts": [
					Vector2(-1.59, -7.16), Vector2(4.16, 2.8), Vector2(6.23, 1.6), Vector2(7.18, 3.24), Vector2(6.64, 4.71), Vector2(5.26, 5.51),
					Vector2(2.95, 5.11), Vector2(2.14, 7.31), Vector2(0.76, 8.11), Vector2(-0.78, 7.84), Vector2(-1.73, 6.2), Vector2(0.34, 5),
					Vector2(-5.41, -4.96),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(-1.8, -5.31), Vector2(2.95, 2.91)]},
					{"kind": "line", "pts": [Vector2(-3.7, -4.21), Vector2(1.05, 4.01)]},
					{"kind": "glass", "pts": [Vector2(5.47, 2.27), Vector2(5.97, 3.13), Vector2(-0.27, 6.73), Vector2(-0.77, 5.87)]},
					{"kind": "light", "pts": [Vector2(1.28, 6.97), Vector2(1.5, 7.35), Vector2(1.12, 7.57), Vector2(0.9, 7.19)]},
					{"kind": "light", "pts": [Vector2(5.78, 4.37), Vector2(6, 4.75), Vector2(5.62, 4.97), Vector2(5.4, 4.59)]},
				],
			},
			{"id": "leg_aft", "kind": "wing", "shade": 2, "attach": Vector2(-13, 0), "mirror": false,
				"pts": [
					Vector2(7, 2.2), Vector2(-4.5, 2.2), Vector2(-4.5, 4.6), Vector2(-6.4, 4.6), Vector2(-7.4, 3.4), Vector2(-7.4, 1.8),
					Vector2(-5.9, 0), Vector2(-7.4, -1.8), Vector2(-7.4, -3.4), Vector2(-6.4, -4.6), Vector2(-4.5, -4.6), Vector2(-4.5, -2.2),
					Vector2(7, -2.2),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(5.5, 1.1), Vector2(-4, 1.1)]},
					{"kind": "line", "pts": [Vector2(5.5, -1.1), Vector2(-4, -1.1)]},
					{"kind": "glass", "pts": [Vector2(-4.7, 3.6), Vector2(-5.7, 3.6), Vector2(-5.7, -3.6), Vector2(-4.7, -3.6)]},
					{"kind": "light", "pts": [Vector2(-6.68, -2.38), Vector2(-7.12, -2.38), Vector2(-7.12, -2.82), Vector2(-6.68, -2.82)]},
					{"kind": "light", "pts": [Vector2(-6.68, 2.82), Vector2(-7.12, 2.82), Vector2(-7.12, 2.38), Vector2(-6.68, 2.38)]},
				],
			},
			{"id": "hub", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(10, 0), Vector2(5, 8.66), Vector2(-5, 8.66), Vector2(-10, 0), Vector2(-5, -8.66), Vector2(5, -8.66),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(9.2, 0), Vector2(7.6, 1.6), Vector2(7.6, -1.6)]},
					{"kind": "line", "pts": [Vector2(2.5, 8), Vector2(-2.5, 8)]},
					{"kind": "line", "pts": [Vector2(2.5, -8), Vector2(-2.5, -8)]},
					{"kind": "dark", "pts": [Vector2(-7, -1), Vector2(-8.6, -1), Vector2(-8.6, 1), Vector2(-7, 1)]},
				],
			},
			{"id": "socket", "kind": "mount", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"weapon": "turret_pd_gun",
				"pts": [
					Vector2(6.74, 2.79), Vector2(2.79, 6.74), Vector2(-2.79, 6.74), Vector2(-6.74, 2.79), Vector2(-6.74, -2.79), Vector2(-2.79, -6.74),
					Vector2(2.79, -6.74), Vector2(6.74, -2.79),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(5.26, 2.18), Vector2(2.18, 5.26), Vector2(-2.18, 5.26), Vector2(-5.26, 2.18), Vector2(-5.26, -2.18), Vector2(-2.18, -5.26), Vector2(2.18, -5.26), Vector2(5.26, -2.18)]},
				],
			},
		],
		"vhorr": [
			{"id": "thorn_0", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(9, -1.4), Vector2(9, 1.4), Vector2(13, 0),
				],
			},
			{"id": "thorn_1", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(7.37, 8.455), Vector2(8.37, 10.185), Vector2(10.31, 8.25),
				],
			},
			{"id": "thorn_2", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(4.633, 12.335), Vector2(3.633, 10.605), Vector2(1.99, 13.05),
				],
			},
			{"id": "thorn_3", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(3.633, -10.605), Vector2(4.633, -12.335), Vector2(1.99, -13.05),
				],
			},
			{"id": "thorn_4", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(8.37, -10.185), Vector2(7.37, -8.455), Vector2(10.31, -8.25),
				],
			},
			{"id": "thorn_5", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(-11, 2.15), Vector2(-13, 2.15), Vector2(-12.3, 4.8),
				],
			},
			{"id": "thorn_6", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(-13, -2.15), Vector2(-11, -2.15), Vector2(-12.3, -4.8),
				],
			},
		],
	},
	"torp_tower": {
		"size": 140,
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(8.5, 0), Vector2(8.5, 6), Vector2(6, 8.5), Vector2(-6, 8.5), Vector2(-8.5, 6), Vector2(-8.5, 0),
					Vector2(-8.5, -6), Vector2(-6, -8.5), Vector2(6, -8.5), Vector2(8.5, -6),
				],
				"marks": [
					{"kind": "plate", "pts": [Vector2(6.5, -4.5), Vector2(6.5, 4.5), Vector2(4.5, 6.5), Vector2(-4.5, 6.5), Vector2(-6.5, 4.5), Vector2(-6.5, -4.5), Vector2(-4.5, -6.5), Vector2(4.5, -6.5)]},
					{"kind": "glass", "pts": [Vector2(-8.2, -2.6), Vector2(-7, -2.6), Vector2(-7, 2.6), Vector2(-8.2, 2.6)]},
					{"kind": "line", "pts": [Vector2(-3, -8.4), Vector2(-3, 8.4)]},
				],
			},
			{"id": "wing", "kind": "wing", "shade": 2, "attach": Vector2(0, 12), "mirror": true,
				"pts": [
					Vector2(6, -8), Vector2(6, 4.6), Vector2(3.4, 7.6), Vector2(-3.4, 7.6), Vector2(-6, 4.6), Vector2(-6, -8),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(-2.5, -3.8), Vector2(4.4, -3.8), Vector2(4.4, -2.2), Vector2(-2.5, -2.2)]},
					{"kind": "warhead", "pts": [Vector2(4.4, -3.8), Vector2(5.6, -3.8), Vector2(5.6, -2.2), Vector2(4.4, -2.2)]},
					{"kind": "dark", "pts": [Vector2(-2.5, -0.8), Vector2(4.4, -0.8), Vector2(4.4, 0.8), Vector2(-2.5, 0.8)]},
					{"kind": "warhead", "pts": [Vector2(4.4, -0.8), Vector2(5.6, -0.8), Vector2(5.6, 0.8), Vector2(4.4, 0.8)]},
					{"kind": "dark", "pts": [Vector2(-2.5, 2.2), Vector2(4.4, 2.2), Vector2(4.4, 3.8), Vector2(-2.5, 3.8)]},
					{"kind": "warhead", "pts": [Vector2(4.4, 2.2), Vector2(5.6, 2.2), Vector2(5.6, 3.8), Vector2(4.4, 3.8)]},
					{"kind": "dark", "pts": [Vector2(-5.4, -7.4), Vector2(-4.2, -7.4), Vector2(-4.2, 4.2), Vector2(-5.4, 4.2)]},
					{"kind": "line", "pts": [Vector2(-4.5, 5.9), Vector2(4.5, 5.9)]},
					{"kind": "light", "pts": [Vector2(-0.22, 6.48), Vector2(0.22, 6.48), Vector2(0.22, 6.92), Vector2(-0.22, 6.92)]},
				],
			},
			{"id": "socket", "kind": "mount", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"weapon": "turret_torp",
				"pts": [
					Vector2(4.989, 2.066), Vector2(2.066, 4.989), Vector2(-2.066, 4.989), Vector2(-4.989, 2.066), Vector2(-4.989, -2.066), Vector2(-2.066, -4.989),
					Vector2(2.066, -4.989), Vector2(4.989, -2.066),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(3.88, 1.607), Vector2(1.607, 3.88), Vector2(-1.607, 3.88), Vector2(-3.88, 1.607), Vector2(-3.88, -1.607), Vector2(-1.607, -3.88), Vector2(1.607, -3.88), Vector2(3.88, -1.607)]},
				],
			},
		],
		"vhorr": [
			{"id": "thorn_tip", "kind": "core", "shade": 1, "attach": Vector2(0, 19.55), "mirror": true,
				"pts": [
					Vector2(-1.5, 0), Vector2(0, 1.05), Vector2(1.5, 0),
				],
			},
			{"id": "thorn_front", "kind": "core", "shade": 1, "attach": Vector2(6, 13), "mirror": true,
				"pts": [
					Vector2(-0.05, -1.2), Vector2(1.2, 0), Vector2(-0.05, 1.2),
				],
			},
		],
	},
	"repair_bay": {
		"size": 80,
		"pieces": [
			{"id": "pad_fore", "kind": "module", "shade": 2, "attach": Vector2(13, 0), "mirror": false,
				"pts": [
					Vector2(-8.5, 5.5), Vector2(4.3, 5.5), Vector2(6.5, 3.3), Vector2(6.5, -3.3), Vector2(4.3, -5.5), Vector2(-8.5, -5.5),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(-5.2, -5.3), Vector2(-5.2, 5.3)]},
					{"kind": "dark", "pts": [Vector2(-4, -3.3), Vector2(1.5, -3.3), Vector2(1.5, 3.3), Vector2(-4, 3.3)]},
					{"kind": "green", "pts": [Vector2(4.2, -3.4), Vector2(5.8, -3.4), Vector2(5.8, 3.4), Vector2(4.2, 3.4)]},
					{"kind": "light", "pts": [Vector2(3.78, 4.38), Vector2(4.22, 4.38), Vector2(4.22, 4.82), Vector2(3.78, 4.82)]},
					{"kind": "light", "pts": [Vector2(3.78, -4.82), Vector2(4.22, -4.82), Vector2(4.22, -4.38), Vector2(3.78, -4.38)]},
				],
			},
			{"id": "pad_aft", "kind": "module", "shade": 2, "attach": Vector2(-13, 0), "mirror": false,
				"pts": [
					Vector2(8.5, -5.5), Vector2(-4.3, -5.5), Vector2(-6.5, -3.3), Vector2(-6.5, 3.3), Vector2(-4.3, 5.5), Vector2(8.5, 5.5),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(5.2, -5.3), Vector2(5.2, 5.3)]},
					{"kind": "dark", "pts": [Vector2(-1.5, -3.3), Vector2(4, -3.3), Vector2(4, 3.3), Vector2(-1.5, 3.3)]},
					{"kind": "green", "pts": [Vector2(-5.8, -3.4), Vector2(-4.2, -3.4), Vector2(-4.2, 3.4), Vector2(-5.8, 3.4)]},
					{"kind": "light", "pts": [Vector2(-4.22, 4.38), Vector2(-3.78, 4.38), Vector2(-3.78, 4.82), Vector2(-4.22, 4.82)]},
					{"kind": "light", "pts": [Vector2(-4.22, -4.82), Vector2(-3.78, -4.82), Vector2(-3.78, -4.38), Vector2(-4.22, -4.38)]},
				],
			},
			{"id": "pad_side", "kind": "module", "shade": 2, "attach": Vector2(0, 13), "mirror": true,
				"pts": [
					Vector2(5.5, -8.5), Vector2(5.5, 4.3), Vector2(3.3, 6.5), Vector2(-3.3, 6.5), Vector2(-5.5, 4.3), Vector2(-5.5, -8.5),
				],
				"marks": [
					{"kind": "line", "pts": [Vector2(-5.3, -5.2), Vector2(5.3, -5.2)]},
					{"kind": "dark", "pts": [Vector2(-3.3, -4), Vector2(3.3, -4), Vector2(3.3, 1.5), Vector2(-3.3, 1.5)]},
					{"kind": "green", "pts": [Vector2(-3.4, 4.2), Vector2(3.4, 4.2), Vector2(3.4, 5.8), Vector2(-3.4, 5.8)]},
					{"kind": "light", "pts": [Vector2(4.38, 3.78), Vector2(4.82, 3.78), Vector2(4.82, 4.22), Vector2(4.38, 4.22)]},
					{"kind": "light", "pts": [Vector2(-4.82, 3.78), Vector2(-4.38, 3.78), Vector2(-4.38, 4.22), Vector2(-4.82, 4.22)]},
				],
			},
			{"id": "hub", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(7.391, 3.061), Vector2(3.061, 7.391), Vector2(-3.061, 7.391), Vector2(-7.391, 3.061), Vector2(-7.391, -3.061), Vector2(-3.061, -7.391),
					Vector2(3.061, -7.391), Vector2(7.391, -3.061),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(3.65, 3.65), Vector2(5.15, 3.65), Vector2(5.15, 5.15), Vector2(3.65, 5.15)]},
					{"kind": "glass", "pts": [Vector2(-5.15, 3.65), Vector2(-3.65, 3.65), Vector2(-3.65, 5.15), Vector2(-5.15, 5.15)]},
					{"kind": "glass", "pts": [Vector2(-5.15, -5.15), Vector2(-3.65, -5.15), Vector2(-3.65, -3.65), Vector2(-5.15, -3.65)]},
					{"kind": "glass", "pts": [Vector2(3.65, -5.15), Vector2(5.15, -5.15), Vector2(5.15, -3.65), Vector2(3.65, -3.65)]},
				],
			},
			{"id": "socket", "kind": "mount", "shade": 0, "attach": Vector2(0, 0), "mirror": false,
				"weapon": "bay_pd",
				"pts": [
					Vector2(4.573, 1.894), Vector2(1.894, 4.573), Vector2(-1.894, 4.573), Vector2(-4.573, 1.894), Vector2(-4.573, -1.894), Vector2(-1.894, -4.573),
					Vector2(1.894, -4.573), Vector2(4.573, -1.894),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(3.566, 1.477), Vector2(1.477, 3.566), Vector2(-1.477, 3.566), Vector2(-3.566, 1.477), Vector2(-3.566, -1.477), Vector2(-1.477, -3.566), Vector2(1.477, -3.566), Vector2(3.566, -1.477)]},
				],
			},
		],
		"vhorr": [
			{"id": "thorn_fore", "kind": "core", "shade": 1, "attach": Vector2(5.5, 5.5), "mirror": true,
				"pts": [
					Vector2(-0.3, -1.7), Vector2(-1.7, -0.3), Vector2(2.3, 2.3),
				],
			},
			{"id": "thorn_aft", "kind": "core", "shade": 1, "attach": Vector2(-5.5, 5.5), "mirror": true,
				"pts": [
					Vector2(1.7, -0.3), Vector2(0.3, -1.7), Vector2(-2.3, 2.3),
				],
			},
		],
	},
}
