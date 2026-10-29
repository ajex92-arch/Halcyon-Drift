class_name OptionHulls
extends RefCounted
## WHAT THIS IS: the Aurelian hull drawings that are NOT used in the game: the
## other direction of the Scout and of the Support Corvette, kept so the hull
## gallery's options sheet can show them next to the drawings the game uses.
## Nothing in the game reads this file; only the hull gallery test does.
##
## HOW IT WORKS: the same shape as AurelianShapes.HULLS (a list of named pieces
## and the flame points, see AurelianShapes), with two more keys on each entry:
##   "for"    the hull of ships.gd this drawing is an option for (its mounts and
##            its plain outline are the reference of the gallery's checks),
##   "label"  the name the options sheet writes under it.
## AurelianPaint.prepare() turns an entry into a drawing, like it does for the
## drawings the game uses.
##
## WHO USES IT: tests/lib/gallery_options.gd (the options sheet) and
## tests/lib/gallery_aurelian.gd (the same checks as for the game's hulls).


## The option hulls: id -> shape.
const HULLS := {

	"scout_pin": {
		"for": "scout",
		"label": "Scout A: Pin",
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(7.2, 0), Vector2(2.9, 2), Vector2(-4.3, 3.1), Vector2(-10.8, 3.6), Vector2(-10.8, 0), Vector2(-10.8, -3.6),
					Vector2(-4.3, -3.1), Vector2(2.9, -2),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(4.4, 0), Vector2(2.4, 1.3), Vector2(-1.4, 1.5), Vector2(-2.9, 0), Vector2(-1.4, -1.5), Vector2(2.4, -1.3)]},
					{"kind": "line", "pts": [Vector2(-4.5, -3.1), Vector2(-4.5, 3.1)]},
					{"kind": "line", "pts": [Vector2(-8.5, -3.5), Vector2(-8.5, 3.5)]},
				],
			},
			{"id": "whisker", "kind": "module", "shade": 0, "attach": Vector2(10.4, 0), "mirror": false,
				"pts": [
					Vector2(4, -0.45), Vector2(4, 0.45), Vector2(-3.9, 1.2), Vector2(-3.9, -1.2),
				],
			},
			{"id": "block", "kind": "engine", "shade": 2, "attach": Vector2(-14, 0), "mirror": false,
				"pts": [
					Vector2(4, 3.6), Vector2(1.8, 6.4), Vector2(-3.8, 6.4), Vector2(-3.8, -6.4), Vector2(1.8, -6.4), Vector2(4, -3.6),
				],
				"nozzles": [Vector3(-3.2, 2.4, 1.1), Vector3(-3.2, -2.4, 1.1)],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(3.4, 4), Vector2(1.6, 6), Vector2(0.7, 6), Vector2(2.5, 3.9)]},
					{"kind": "stripe", "pts": [Vector2(3.4, -3.9), Vector2(2.5, -3.9), Vector2(0.7, -6), Vector2(1.6, -6)]},
					{"kind": "line", "pts": [Vector2(1.8, -6.3), Vector2(1.8, 6.3)]},
					{"kind": "light", "pts": [Vector2(-3.02, 5.58), Vector2(-2.58, 5.58), Vector2(-2.58, 6.02), Vector2(-3.02, 6.02)]},
					{"kind": "light", "pts": [Vector2(-3.02, -6.02), Vector2(-2.58, -6.02), Vector2(-2.58, -5.58), Vector2(-3.02, -5.58)]},
				],
			},
			{"id": "gun", "kind": "mount", "shade": 1, "attach": Vector2(18, 0), "mirror": false,
				"weapon": "scout_gun",
				"pts": [
					Vector2(0.4, 0), Vector2(-2.2, 1.7), Vector2(-4.5, 0), Vector2(-2.2, -1.7),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(-0.4, 0), Vector2(-2.2, 0.9), Vector2(-3.4, 0), Vector2(-2.2, -0.9)]},
				],
			},
		],
		"jet": [Vector2(-17.8, 0), Vector2(-12, 5.6)],
	},
	"scout_comet": {
		"for": "scout",
		"label": "Scout B: Comet",
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(16.8, 0), Vector2(15.6, 2.6), Vector2(13.2, 5), Vector2(10.2, 6.4), Vector2(6.6, 6.4), Vector2(4, 4.8),
					Vector2(2.6, 2.2), Vector2(2, 1.5), Vector2(-12.5, 1.5), Vector2(-12.5, 0), Vector2(-12.5, -1.5), Vector2(2, -1.5),
					Vector2(2.6, -2.2), Vector2(4, -4.8), Vector2(6.6, -6.4), Vector2(10.2, -6.4), Vector2(13.2, -5), Vector2(15.6, -2.6),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(14.4, 0), Vector2(12, 2.3), Vector2(8.6, 2.7), Vector2(7.2, 0), Vector2(8.6, -2.7), Vector2(12, -2.3)]},
					{"kind": "plate", "pts": [Vector2(6.2, -3.6), Vector2(6.2, 3.6), Vector2(3.8, 2.6), Vector2(3.8, -2.6)]},
					{"kind": "plate", "pts": [Vector2(12.4, 3.4), Vector2(10.4, 5.3), Vector2(7.8, 5.3), Vector2(7.4, 3.5)]},
					{"kind": "plate", "pts": [Vector2(12.4, -3.4), Vector2(7.4, -3.5), Vector2(7.8, -5.3), Vector2(10.4, -5.3)]},
					{"kind": "line", "pts": [Vector2(5.4, -5.6), Vector2(5.4, 5.6)]},
					{"kind": "line", "pts": [Vector2(-3, -1.5), Vector2(-3, 1.5)]},
					{"kind": "line", "pts": [Vector2(-8, -1.5), Vector2(-8, 1.5)]},
					{"kind": "light", "pts": [Vector2(9.98, 5.68), Vector2(10.42, 5.68), Vector2(10.42, 6.12), Vector2(9.98, 6.12)]},
					{"kind": "light", "pts": [Vector2(9.98, -6.12), Vector2(10.42, -6.12), Vector2(10.42, -5.68), Vector2(9.98, -5.68)]},
				],
			},
			{"id": "fins", "kind": "wing", "shade": 2, "attach": Vector2(-8, 3), "mirror": true,
				"pts": [
					Vector2(4, -1.6), Vector2(-2.6, 2), Vector2(-5, 2), Vector2(-4.2, -1.6),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(3, -1.2), Vector2(-2.3, 1.6), Vector2(-3, 1.6), Vector2(1.4, -1.2)]},
					{"kind": "light", "pts": [Vector2(-4.42, 1.48), Vector2(-3.98, 1.48), Vector2(-3.98, 1.92), Vector2(-4.42, 1.92)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-14.6, 0), "mirror": false,
				"pts": [
					Vector2(3.1, -1.6), Vector2(-3.2, -3.2), Vector2(-3.2, 3.2), Vector2(3.1, 1.6),
				],
				"nozzles": [Vector3(-2.6, 0, 1.3)],
			},
			{"id": "gun", "kind": "mount", "shade": 0, "attach": Vector2(18, 0), "mirror": false,
				"weapon": "scout_gun",
				"pts": [
					Vector2(0.4, 0), Vector2(-0.6, 0.55), Vector2(-3.4, 0.55), Vector2(-3.4, -0.55), Vector2(-0.6, -0.55),
				],
			},
		],
		"jet": [Vector2(-17.8, 0), Vector2(-12, 4.4)],
	},
	"support_box": {
		"for": "support",
		"label": "Support A: Box with dish",
		"pieces": [
			{"id": "core", "kind": "core", "shade": 1, "attach": Vector2(0, 0), "mirror": false,
				"pts": [
					Vector2(11.4, 0), Vector2(11.4, 1.6), Vector2(8.1, 4.5), Vector2(-9.9, 4.5), Vector2(-11.2, 3.1), Vector2(-11.2, 0),
					Vector2(-11.2, -3.1), Vector2(-9.9, -4.5), Vector2(8.1, -4.5), Vector2(11.4, -1.6),
				],
				"marks": [
					{"kind": "glass", "pts": [Vector2(10.8, 0), Vector2(9.8, 0.9), Vector2(8.2, 0.9), Vector2(7.6, 0)]},
					{"kind": "line", "pts": [Vector2(4.5, -4.4), Vector2(4.5, 4.4)]},
					{"kind": "line", "pts": [Vector2(-5, -4.4), Vector2(-5, 4.4)]},
				],
			},
			{"id": "block", "kind": "wing", "shade": 2, "attach": Vector2(-2.2, 5.3), "mirror": true,
				"pts": [
					Vector2(4.4, -1.1), Vector2(3.8, 1.1), Vector2(-3.8, 1.1), Vector2(-4.5, -1.1),
				],
				"marks": [
					{"kind": "stripe", "pts": [Vector2(3.6, -0.7), Vector2(3.2, 0.7), Vector2(2.6, 0.7), Vector2(3, -0.7)]},
					{"kind": "dark", "pts": [Vector2(0.4, -0.4), Vector2(1.2, -0.4), Vector2(1.2, 0.1), Vector2(0.4, 0.1)]},
					{"kind": "dark", "pts": [Vector2(-0.7, -0.4), Vector2(0.1, -0.4), Vector2(0.1, 0.1), Vector2(-0.7, 0.1)]},
					{"kind": "dark", "pts": [Vector2(-1.8, -0.4), Vector2(-1, -0.4), Vector2(-1, 0.1), Vector2(-1.8, 0.1)]},
					{"kind": "dark", "pts": [Vector2(-2.9, -0.4), Vector2(-2.1, -0.4), Vector2(-2.1, 0.1), Vector2(-2.9, 0.1)]},
					{"kind": "light", "pts": [Vector2(3.18, 0.58), Vector2(3.62, 0.58), Vector2(3.62, 1.02), Vector2(3.18, 1.02)]},
					{"kind": "light", "pts": [Vector2(-3.82, 0.58), Vector2(-3.38, 0.58), Vector2(-3.38, 1.02), Vector2(-3.82, 1.02)]},
				],
			},
			{"id": "dish", "kind": "module", "shade": 2, "attach": Vector2(-0.5, 0), "mirror": false,
				"pts": [
					Vector2(2.679, 1.11), Vector2(1.11, 2.679), Vector2(-1.11, 2.679), Vector2(-2.679, 1.11), Vector2(-2.679, -1.11), Vector2(-1.11, -2.679),
					Vector2(1.11, -2.679), Vector2(2.679, -1.11),
				],
				"marks": [
					{"kind": "dark", "pts": [Vector2(1.571, 0.651), Vector2(0.651, 1.571), Vector2(-0.651, 1.571), Vector2(-1.571, 0.651), Vector2(-1.571, -0.651), Vector2(-0.651, -1.571), Vector2(0.651, -1.571), Vector2(1.571, -0.651)]},
					{"kind": "light", "pts": [Vector2(0.462, 0.191), Vector2(0.191, 0.462), Vector2(-0.191, 0.462), Vector2(-0.462, 0.191), Vector2(-0.462, -0.191), Vector2(-0.191, -0.462), Vector2(0.191, -0.462), Vector2(0.462, -0.191)]},
				],
			},
			{"id": "engine", "kind": "engine", "shade": 0, "attach": Vector2(-10.9, 0), "mirror": false,
				"pts": [
					Vector2(0.9, -4), Vector2(-0.9, -3.4), Vector2(-0.9, 3.4), Vector2(0.9, 4),
				],
				"nozzles": [Vector3(-0.3, 0, 0.9), Vector3(-0.3, 2.3, 0.75), Vector3(-0.3, -2.3, 0.75)],
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
		"jet": [Vector2(-11.8, 0), Vector2(-6, 4.4)],
	},
}
