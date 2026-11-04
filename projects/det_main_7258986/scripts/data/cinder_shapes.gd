class_name CinderShapes
extends RefCounted
## WHAT THIS IS: the alien drawings of Cinder, the red team. Every Cinder ship
## and unit is drawn from one of the shape tables below, instead of the plain
## outlines the Aurelian (amber) team uses. The tables are only pictures: they
## change nothing in the game (sizes, hit circles and numbers stay as they
## are in ships.gd and the other data files).
##
## HOW IT WORKS: each shape is a small table with these fields (a "point" is
## a Vector2 corner, a "polygon" is a list of points; the shape is drawn
## with its nose pointing right, +x, and +y is the ship's right side):
##   "sil"    the outline of the whole shape: one polygon, made by merging its
##            plates. The fill and the red outline use it (about 40 points or
##            fewer, so a ship costs little to draw).
##   "lo"     a simpler copy of the outline, a dozen or so points, used when
##            the shape is only a few pixels long on the screen.
##   "parts"  layered plates, back to front, drawn over the fill of big
##            shapes. Each is {"shade": 0, 1 or 2 (darkest, hull, lightest),
##            "pts": polygon}. A plate that only shapes the outline is not
##            listed here; a plain hull-coloured plate underneath is not
##            either (the fill already shows it).
##   "veins"  glowing lines: a few long lines, each a list of points. One
##            line can walk a ship's whole spine and go out and back along
##            every rib, so the veins of a ship are one or two lines (every
##            line costs a drawing command).
##   "glow"   engine lights: Vector3(x, y, radius).
##   "jet"    ships only: where the engine flames come out: the main flame's
##            point, then the side flames' point (its y is the distance from
##            the middle; the other side is the mirror).
##   "body"   optional: how red the fill is at least, 0 to 1 (0 = the dark hull
##            colour). CinderPaint makes small and far shapes redder anyway; a
##            shape with a "body" stays at least that red at any size. Only the
##            lane minions have one: they read as solid bodies next to the dark
##            pilot hulls.
## Pilot hulls are drawn in the same 36-unit design space as ShipVisual.HULLS
## (nose at the right), and each Cinder hull keeps its Aurelian hull's length
## and width to within about 10%, so hits and ranges read the same. Minions,
## drones, wards, turrets and bays are drawn in "unit" space (about 1 across,
## scaled by UnitVisual the way the Aurelian outlines are). The mothership is
## in world units for a ship 1600 long and 340 wide.
## The designs are original drawings; they are inspired by predatory, bladed
## alien raiders (sweeping crescent blades, hooked prows, notched tails) but
## copy no existing ship.
##
## WHO USES IT: CinderPaint turns these tables into pictures (and keeps them
## ready in packed arrays); ShipVisual and UnitVisual ask CinderPaint for them.


## The ten pilot hulls: hull id -> shape (see the top of this file).
const HULLS := {
	# Stinger: a needle dart with two hooked barbs swept back from the shoulders and a split tail.
	"scout": {
		"sil": [
			Vector2(18, 0), Vector2(5.4, 1.6), Vector2(5.9, 2), Vector2(2.4, 4), Vector2(-2, 4.8), Vector2(-7, 4.6),
			Vector2(-12.5, 3.4), Vector2(-7, 4.1), Vector2(-2.1, 3.7), Vector2(1.7, 2.3), Vector2(2.2, 1.9), Vector2(-4, 2.2),
			Vector2(-9, 1.9), Vector2(-14, 1.5), Vector2(-10.5, 0), Vector2(-14, -1.5), Vector2(-9, -1.9), Vector2(-4, -2.2),
			Vector2(2.2, -1.9), Vector2(1.7, -2.3), Vector2(-2.1, -3.7), Vector2(-7, -4.1), Vector2(-12.5, -3.4), Vector2(-7, -4.6),
			Vector2(-2, -4.8), Vector2(2.4, -4), Vector2(5.9, -2), Vector2(5.4, -1.6), Vector2(11, -0.9),
		],
		"lo": [
			Vector2(18, 0), Vector2(5.4, 1.6), Vector2(2.4, 4), Vector2(-2, 4.8), Vector2(-12.5, 3.4), Vector2(-2.1, 3.7),
			Vector2(2.2, 1.9), Vector2(-14, 1.5), Vector2(-10.5, 0), Vector2(-14, -1.5), Vector2(2.2, -1.9), Vector2(-2.1, -3.7),
			Vector2(-12.5, -3.4), Vector2(-7, -4.6), Vector2(2.4, -4), Vector2(5.4, -1.6),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(4.1, 0.4), Vector2(1.7, 2.3), Vector2(-2.1, 3.7), Vector2(-7, 4.1), Vector2(-12.5, 3.4), Vector2(-7, 4.6),
				Vector2(-2, 4.8), Vector2(2.4, 4), Vector2(5.9, 2),
			]},
			{"shade": 2, "pts": [
				Vector2(5.9, -2), Vector2(2.4, -4), Vector2(-2, -4.8), Vector2(-7, -4.6), Vector2(-12.5, -3.4), Vector2(-7, -4.1),
				Vector2(-2.1, -3.7), Vector2(1.7, -2.3), Vector2(4.1, -0.4),
			]},
			{"shade": 1, "pts": [
				Vector2(18, 0), Vector2(11, 0.9), Vector2(6, 1.5), Vector2(2, 1.9), Vector2(-4, 2.2), Vector2(-9, 1.9),
				Vector2(-14, 1.5), Vector2(-10.5, 0), Vector2(-14, -1.5), Vector2(-9, -1.9), Vector2(-4, -2.2), Vector2(2, -1.9),
				Vector2(6, -1.5), Vector2(11, -0.9),
			]},
		],
		"veins": [
			[Vector2(13, 0), Vector2(-7, 0)],
		],
		"glow": [Vector3(-12, 0, 0.9)],
		"jet": [Vector2(-14, 0), Vector2(-3, 4.5)],
	},
	# Mantis: a beaked insect body with two big claws that sweep out and then forward.
	"fighter": {
		"sil": [
			Vector2(18, 0), Vector2(13.5, 0.9), Vector2(11, 1.7), Vector2(8.5, 1.4), Vector2(5, 2.2), Vector2(0, 2.6),
			Vector2(-2.3, 2.5), Vector2(-2.2, 2.7), Vector2(0.6, 4.4), Vector2(4.5, 5.6), Vector2(9.2, 6.3), Vector2(14, 6.6),
			Vector2(9.1, 7), Vector2(4.3, 7), Vector2(-0.1, 6.4), Vector2(-3.9, 4.9), Vector2(-6.4, 2), Vector2(-8, 1.6),
			Vector2(-6, 0), Vector2(-8, -1.6), Vector2(-6.4, -2), Vector2(-3.9, -4.9), Vector2(-0.1, -6.4), Vector2(4.3, -7),
			Vector2(9.1, -7), Vector2(14, -6.6), Vector2(9.2, -6.3), Vector2(4.5, -5.6), Vector2(0.6, -4.4), Vector2(-2.2, -2.7),
			Vector2(-2.3, -2.5), Vector2(0, -2.6), Vector2(5, -2.2), Vector2(8.5, -1.4), Vector2(11, -1.7), Vector2(13.5, -0.9),
		],
		"lo": [
			Vector2(18, 0), Vector2(11, 1.7), Vector2(-2.3, 2.5), Vector2(4.5, 5.6), Vector2(14, 6.6), Vector2(9.1, 7),
			Vector2(-0.1, 6.4), Vector2(-8, 1.6), Vector2(-6, 0), Vector2(-8, -1.6), Vector2(-3.9, -4.9), Vector2(4.3, -7),
			Vector2(14, -6.6), Vector2(4.5, -5.6), Vector2(-2.3, -2.5), Vector2(11, -1.7),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(-6.6, 1.8), Vector2(-3.9, 4.9), Vector2(-0.1, 6.4), Vector2(4.3, 7), Vector2(9.1, 7), Vector2(14, 6.6),
				Vector2(9.2, 6.3), Vector2(4.5, 5.6), Vector2(0.6, 4.4), Vector2(-2.2, 2.7), Vector2(-3.4, 0.6),
			]},
			{"shade": 2, "pts": [
				Vector2(-3.4, -0.6), Vector2(-2.2, -2.7), Vector2(0.6, -4.4), Vector2(4.5, -5.6), Vector2(9.2, -6.3), Vector2(14, -6.6),
				Vector2(9.1, -7), Vector2(4.3, -7), Vector2(-0.1, -6.4), Vector2(-3.9, -4.9), Vector2(-6.6, -1.8),
			]},
			{"shade": 1, "pts": [
				Vector2(18, 0), Vector2(13.5, 0.9), Vector2(11, 1.7), Vector2(8.5, 1.4), Vector2(5, 2.2), Vector2(0, 2.6),
				Vector2(-5, 2.4), Vector2(-8, 1.6), Vector2(-6, 0), Vector2(-8, -1.6), Vector2(-5, -2.4), Vector2(0, -2.6),
				Vector2(5, -2.2), Vector2(8.5, -1.4), Vector2(11, -1.7), Vector2(13.5, -0.9),
			]},
		],
		"veins": [
			[Vector2(14, 0), Vector2(-4, 0)],
		],
		"glow": [Vector3(-7, 0, 0.9)],
		"jet": [Vector2(-8, 0), Vector2(-3, 6)],
	},
	# Needle: a very long spike with long curved fins swept back like arrow feathers.
	"lance": {
		"sil": [
			Vector2(20, 0), Vector2(15, 0.5), Vector2(5.1, 1.2), Vector2(5.4, 1.9), Vector2(1.6, 3.4), Vector2(-2.2, 5.2),
			Vector2(-6.1, 6.8), Vector2(-10, 8), Vector2(-6.4, 6.3), Vector2(2, 1.4), Vector2(-1.8, 1.6), Vector2(-1.7, 1.8),
			Vector2(-4.8, 3), Vector2(-7.6, 3.9), Vector2(-10, 4.4), Vector2(-5.1, 2.2), Vector2(-4.4, 1.8), Vector2(-6, 1.9),
			Vector2(-10, 1.6), Vector2(-8.5, 0), Vector2(-10, -1.6), Vector2(-6, -1.9), Vector2(-4.4, -1.8), Vector2(-5.1, -2.2),
			Vector2(-10, -4.4), Vector2(-7.6, -3.9), Vector2(-4.8, -3), Vector2(-1.7, -1.8), Vector2(-1.8, -1.6), Vector2(2, -1.4),
			Vector2(-6.4, -6.3), Vector2(-10, -8), Vector2(-6.1, -6.8), Vector2(-2.2, -5.2), Vector2(1.6, -3.4), Vector2(5.4, -1.9),
			Vector2(5.1, -1.2), Vector2(15, -0.5),
		],
		"lo": [
			Vector2(20, 0), Vector2(5.1, 1.2), Vector2(-10, 8), Vector2(2, 1.4), Vector2(-10, 4.4), Vector2(-4.4, 1.8),
			Vector2(-10, 1.6), Vector2(-8.5, 0), Vector2(-10, -1.6), Vector2(-4.4, -1.8), Vector2(-10, -4.4), Vector2(2, -1.4),
			Vector2(-10, -8), Vector2(5.1, -1.2),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(4.6, -0.1), Vector2(0.9, 2), Vector2(-2.8, 4.2), Vector2(-6.4, 6.3), Vector2(-10, 8), Vector2(-6.1, 6.8),
				Vector2(-2.2, 5.2), Vector2(1.6, 3.4), Vector2(5.4, 1.9),
			]},
			{"shade": 2, "pts": [
				Vector2(5.4, -1.9), Vector2(1.6, -3.4), Vector2(-2.2, -5.2), Vector2(-6.1, -6.8), Vector2(-10, -8), Vector2(-6.4, -6.3),
				Vector2(-2.8, -4.2), Vector2(0.9, -2), Vector2(4.6, 0.1),
			]},
			{"shade": 1, "pts": [
				Vector2(-2.3, 0.6), Vector2(-5.1, 2.2), Vector2(-7.8, 3.4), Vector2(-10, 4.4), Vector2(-7.6, 3.9), Vector2(-4.8, 3),
				Vector2(-1.7, 1.8),
			]},
			{"shade": 1, "pts": [
				Vector2(-1.7, -1.8), Vector2(-4.8, -3), Vector2(-7.6, -3.9), Vector2(-10, -4.4), Vector2(-7.8, -3.4), Vector2(-5.1, -2.2),
				Vector2(-2.3, -0.6),
			]},
			{"shade": 1, "pts": [
				Vector2(20, 0), Vector2(15, 0.5), Vector2(8, 1), Vector2(0, 1.5), Vector2(-6, 1.9), Vector2(-10, 1.6),
				Vector2(-8.5, 0), Vector2(-10, -1.6), Vector2(-6, -1.9), Vector2(0, -1.5), Vector2(8, -1), Vector2(15, -0.5),
			]},
		],
		"veins": [
			[Vector2(18, 0), Vector2(-6, 0)],
		],
		"glow": [Vector3(-9, 0, 1)],
		"jet": [Vector2(-10, 0), Vector2(-1, 5)],
	},
	# Beetle: a heavy armoured body whose two jaws close round the torpedo bay, with thick flank plates.
	"bomber": {
		"sil": [
			Vector2(16.8, 3.2), Vector2(12.5, 5), Vector2(7, 5.8), Vector2(2.9, 6), Vector2(4.1, 6.2), Vector2(10, 7.6),
			Vector2(3.8, 8.2), Vector2(-2.2, 7.5), Vector2(-6.3, 6), Vector2(-7, 6), Vector2(-11, 5), Vector2(-12, 3.2),
			Vector2(-12, 1.8), Vector2(-9, 0), Vector2(-12, -1.8), Vector2(-12, -3.2), Vector2(-11, -5), Vector2(-7, -6),
			Vector2(-6.3, -6), Vector2(-2.2, -7.5), Vector2(3.8, -8.2), Vector2(10, -7.6), Vector2(4.1, -6.2), Vector2(2.9, -6),
			Vector2(7, -5.8), Vector2(12.5, -5), Vector2(16.8, -3.2), Vector2(16.5, -1.6), Vector2(10.5, 0), Vector2(16.5, 1.6),
		],
		"lo": [
			Vector2(16.8, 3.2), Vector2(2.9, 6), Vector2(10, 7.6), Vector2(-2.2, 7.5), Vector2(-11, 5), Vector2(-12, 1.8),
			Vector2(-9, 0), Vector2(-12, -3.2), Vector2(-11, -5), Vector2(-2.2, -7.5), Vector2(10, -7.6), Vector2(2.9, -6),
			Vector2(16.8, -3.2), Vector2(16.5, -1.6), Vector2(10.5, 0), Vector2(16.5, 1.6),
		],
		"parts": [
			{"shade": 2, "pts": [Vector2(-8, 5.4), Vector2(-2.2, 7.5), Vector2(3.8, 8.2), Vector2(10, 7.6), Vector2(4.1, 6.2), Vector2(-1.9, 5.4)]},
			{"shade": 2, "pts": [Vector2(-1.9, -5.4), Vector2(4.1, -6.2), Vector2(10, -7.6), Vector2(3.8, -8.2), Vector2(-2.2, -7.5), Vector2(-8, -5.4)]},
			{"shade": 2, "pts": [
				Vector2(8, 0), Vector2(5, 2), Vector2(0, 3.4), Vector2(-6, 3.6), Vector2(-9, 2), Vector2(-6, 0),
				Vector2(-9, -2), Vector2(-6, -3.6), Vector2(0, -3.4), Vector2(5, -2),
			]},
		],
		"veins": [
			[
				Vector2(10.5, 0), Vector2(9, 0), Vector2(6, 2.6), Vector2(0, 4.4), Vector2(-4, 4.6), Vector2(-8, 4), Vector2(-4, 4.6), Vector2(0, 4.4),
				Vector2(6, 2.6), Vector2(9, 0), Vector2(6, -2.6), Vector2(0, -4.4), Vector2(-4, -4.6), Vector2(-8, -4), Vector2(-4, -4.6), Vector2(0, -4.4),
				Vector2(6, -2.6), Vector2(9, 0), Vector2(-9, 0),
			],
		],
		"glow": [Vector3(-11, 2.2, 0.8), Vector3(-11, -2.2, 0.8)],
		"jet": [Vector2(-12, 0), Vector2(0, 6.5)],
	},
	# Hive: a broad ridged shell with a short beak, two curved nest-horns and a saw-tooth stern.
	"logistics": {
		"sil": [
			Vector2(14, 0), Vector2(12, 1.8), Vector2(8.5, 4.6), Vector2(5, 6.4), Vector2(2.4, 6.1), Vector2(3.2, 6.7),
			Vector2(6.1, 7.8), Vector2(9.4, 8.1), Vector2(12.5, 7.4), Vector2(9.6, 9), Vector2(6, 9.5), Vector2(2.3, 9.1),
			Vector2(-1.2, 7.4), Vector2(-4, 7), Vector2(-7, 8), Vector2(-10, 6.6), Vector2(-14, 5), Vector2(-11.5, 3.8),
			Vector2(-14, 2.6), Vector2(-11, 1.4), Vector2(-12.5, 0), Vector2(-11, -1.4), Vector2(-14, -2.6), Vector2(-11.5, -3.8),
			Vector2(-14, -5), Vector2(-10, -6.6), Vector2(-7, -8), Vector2(-4, -7), Vector2(-1.2, -7.4), Vector2(2.3, -9.1),
			Vector2(6, -9.5), Vector2(9.6, -9), Vector2(12.5, -7.4), Vector2(9.4, -8.1), Vector2(6.1, -7.8), Vector2(3.2, -6.7),
			Vector2(2.4, -6.1), Vector2(5, -6.4), Vector2(8.5, -4.6), Vector2(12, -1.8),
		],
		"lo": [
			Vector2(14, 0), Vector2(2.4, 6.1), Vector2(12.5, 7.4), Vector2(9.6, 9), Vector2(-7, 8), Vector2(-14, 5),
			Vector2(-11, 1.4), Vector2(-14, -5), Vector2(-7, -8), Vector2(9.6, -9), Vector2(12.5, -7.4), Vector2(2.4, -6.1),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(-1.2, 7.4), Vector2(2.3, 9.1), Vector2(6, 9.5), Vector2(9.6, 9), Vector2(12.5, 7.4), Vector2(9.4, 8.1),
				Vector2(6.1, 7.8), Vector2(3.2, 6.7), Vector2(1.2, 5),
			]},
			{"shade": 2, "pts": [
				Vector2(1.2, -5), Vector2(3.2, -6.7), Vector2(6.1, -7.8), Vector2(9.4, -8.1), Vector2(12.5, -7.4), Vector2(9.6, -9),
				Vector2(6, -9.5), Vector2(2.3, -9.1), Vector2(-1.2, -7.4),
			]},
			{"shade": 1, "pts": [
				Vector2(14, 0), Vector2(12, 1.8), Vector2(8.5, 4.6), Vector2(5, 6.4), Vector2(2, 6), Vector2(-1, 7.4),
				Vector2(-4, 7), Vector2(-7, 8), Vector2(-10, 6.6), Vector2(-14, 5), Vector2(-11.5, 3.8), Vector2(-14, 2.6),
				Vector2(-11, 1.4), Vector2(-12.5, 0), Vector2(-11, -1.4), Vector2(-14, -2.6), Vector2(-11.5, -3.8), Vector2(-14, -5),
				Vector2(-10, -6.6), Vector2(-7, -8), Vector2(-4, -7), Vector2(-1, -7.4), Vector2(2, -6), Vector2(5, -6.4),
				Vector2(8.5, -4.6), Vector2(12, -1.8),
			]},
		],
		"veins": [
			[
				Vector2(10, 0), Vector2(9, 0), Vector2(5, 2.6), Vector2(0, 4.8), Vector2(-4, 5.6), Vector2(-9, 5), Vector2(-4, 5.6), Vector2(0, 4.8),
				Vector2(5, 2.6), Vector2(9, 0), Vector2(5, -2.6), Vector2(0, -4.8), Vector2(-4, -5.6), Vector2(-9, -5), Vector2(-4, -5.6), Vector2(0, -4.8),
				Vector2(5, -2.6), Vector2(9, 0), Vector2(-8, 0),
			],
		],
		"glow": [Vector3(-12.5, 2.2, 0.8), Vector3(-12.5, -2.2, 0.8)],
		"jet": [Vector2(-13, 0), Vector2(0, 7.5)],
	},
	# Lyre: a slim body with two tall curved horns, like sensor antennae.
	"support": {
		"sil": [
			Vector2(12, 0), Vector2(8, 0.9), Vector2(2, 1.9), Vector2(-0.8, 2.1), Vector2(-0.4, 3), Vector2(2.3, 4.2),
			Vector2(6.4, 4.7), Vector2(11, 4.6), Vector2(6.4, 5.2), Vector2(2.2, 5.2), Vector2(-1.2, 4.2), Vector2(-2.5, 2.3),
			Vector2(-4, 2.4), Vector2(-9, 2), Vector2(-10, 1), Vector2(-8, 0), Vector2(-10, -1), Vector2(-9, -2),
			Vector2(-4, -2.4), Vector2(-2.5, -2.3), Vector2(-1.2, -4.2), Vector2(2.2, -5.2), Vector2(6.4, -5.2), Vector2(11, -4.6),
			Vector2(6.4, -4.7), Vector2(2.3, -4.2), Vector2(-0.4, -3), Vector2(-0.8, -2.1), Vector2(2, -1.9), Vector2(8, -0.9),
		],
		"lo": [
			Vector2(12, 0), Vector2(-0.8, 2.1), Vector2(11, 4.6), Vector2(6.4, 5.2), Vector2(-10, 1), Vector2(-8, 0),
			Vector2(-9, -2), Vector2(-2.5, -2.3), Vector2(2.2, -5.2), Vector2(11, -4.6), Vector2(-0.8, -2.1),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(-3, 1.6), Vector2(-1.2, 4.2), Vector2(2.2, 5.2), Vector2(6.4, 5.2), Vector2(11, 4.6), Vector2(6.4, 4.7),
				Vector2(2.3, 4.2), Vector2(-0.4, 3), Vector2(-1, 1.6),
			]},
			{"shade": 2, "pts": [
				Vector2(-1, -1.6), Vector2(-0.4, -3), Vector2(2.3, -4.2), Vector2(6.4, -4.7), Vector2(11, -4.6), Vector2(6.4, -5.2),
				Vector2(2.2, -5.2), Vector2(-1.2, -4.2), Vector2(-3, -1.6),
			]},
			{"shade": 1, "pts": [
				Vector2(12, 0), Vector2(8, 0.9), Vector2(2, 1.9), Vector2(-4, 2.4), Vector2(-9, 2), Vector2(-10, 1),
				Vector2(-8, 0), Vector2(-10, -1), Vector2(-9, -2), Vector2(-4, -2.4), Vector2(2, -1.9), Vector2(8, -0.9),
			]},
		],
		"veins": [
			[Vector2(9, 0), Vector2(-6, 0)],
		],
		"glow": [Vector3(-9, 0, 0.9)],
		"jet": [Vector2(-10, 0), Vector2(-2, 3.8)],
	},
	# Thornback: a broad shell with rows of back-swept thorns along both flanks.
	"flak": {
		"sil": [
			Vector2(16, 0), Vector2(13, 2.4), Vector2(8.1, 8.4), Vector2(4.3, 10), Vector2(5.1, 6.6), Vector2(4.5, 6),
			Vector2(2.6, 8.4), Vector2(-1.2, 10), Vector2(-0.4, 6.6), Vector2(-1, 6), Vector2(-2.9, 8.4), Vector2(-6.7, 10),
			Vector2(-5.9, 6.6), Vector2(-6.5, 6), Vector2(-8.4, 8.4), Vector2(-12.2, 10), Vector2(-11.4, 6.6), Vector2(-13, 5.2),
			Vector2(-16, 2.8), Vector2(-13.5, 1.4), Vector2(-11.5, 0), Vector2(-13.5, -1.4), Vector2(-16, -2.8), Vector2(-13, -5.2),
			Vector2(-11.4, -6.6), Vector2(-12.2, -10), Vector2(-8.4, -8.4), Vector2(-6.5, -6), Vector2(-5.9, -6.6), Vector2(-6.7, -10),
			Vector2(-2.9, -8.4), Vector2(-1, -6), Vector2(-0.4, -6.6), Vector2(-1.2, -10), Vector2(2.6, -8.4), Vector2(4.5, -6),
			Vector2(5.1, -6.6), Vector2(4.3, -10), Vector2(8.1, -8.4), Vector2(13, -2.4),
		],
		"lo": [
			Vector2(16, 0), Vector2(4.3, 10), Vector2(4.5, 6), Vector2(-12.2, 10), Vector2(-16, 2.8), Vector2(-11.5, 0),
			Vector2(-16, -2.8), Vector2(-12.2, -10), Vector2(-6.5, -6), Vector2(-6.7, -10), Vector2(-1, -6), Vector2(-1.2, -10),
			Vector2(4.5, -6), Vector2(4.3, -10),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(8, 0), Vector2(5, 2.4), Vector2(-2, 3.4), Vector2(-9, 3.2), Vector2(-11, 1.4), Vector2(-9, 0),
				Vector2(-11, -1.4), Vector2(-9, -3.2), Vector2(-2, -3.4), Vector2(5, -2.4),
			]},
		],
		"veins": [
			[
				Vector2(12, 0), Vector2(10, 0), Vector2(6, 2.2), Vector2(2, 3.8), Vector2(-3, 4.2), Vector2(-7, 4.2), Vector2(-3, 4.2), Vector2(2, 3.8),
				Vector2(6, 2.2), Vector2(10, 0), Vector2(6, -2.2), Vector2(2, -3.8), Vector2(-3, -4.2), Vector2(-7, -4.2), Vector2(-3, -4.2), Vector2(2, -3.8),
				Vector2(6, -2.2), Vector2(10, 0), Vector2(-8, 0),
			],
		],
		"glow": [Vector3(-14, 2.2, 0.9), Vector3(-14, -2.2, 0.9)],
		"jet": [Vector2(-15, 0), Vector2(0, 8.5)],
	},
	# Harpoon: a long lance prow between two curved barbs, with a heavy engine block.
	"ion": {
		"sil": [
			Vector2(18, 0), Vector2(12, 0.9), Vector2(6, 1.7), Vector2(0, 2.8), Vector2(-6.2, 4.2), Vector2(-6.1, 4.4),
			Vector2(-3.1, 5.5), Vector2(1.5, 6.2), Vector2(6.8, 6.2), Vector2(12, 5.8), Vector2(6.9, 6.8), Vector2(1.5, 7.3),
			Vector2(-3.4, 7.2), Vector2(-7.3, 6.3), Vector2(-8.6, 4.5), Vector2(-12, 4.8), Vector2(-16, 3.8), Vector2(-16, 2),
			Vector2(-13, 0), Vector2(-16, -2), Vector2(-16, -3.8), Vector2(-12, -4.8), Vector2(-8.6, -4.5), Vector2(-7.3, -6.3),
			Vector2(-3.4, -7.2), Vector2(1.5, -7.3), Vector2(6.9, -6.8), Vector2(12, -5.8), Vector2(6.8, -6.2), Vector2(1.5, -6.2),
			Vector2(-3.1, -5.5), Vector2(-6.1, -4.4), Vector2(-6.2, -4.2), Vector2(0, -2.8), Vector2(6, -1.7), Vector2(12, -0.9),
		],
		"lo": [
			Vector2(18, 0), Vector2(-6.2, 4.2), Vector2(1.5, 6.2), Vector2(12, 5.8), Vector2(6.9, 6.8), Vector2(-3.4, 7.2),
			Vector2(-8.6, 4.5), Vector2(-16, 3.8), Vector2(-13, 0), Vector2(-16, -3.8), Vector2(-8.6, -4.5), Vector2(-3.4, -7.2),
			Vector2(12, -5.8), Vector2(1.5, -6.2), Vector2(-6.2, -4.2),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(-9.4, 3.4), Vector2(-7.3, 6.3), Vector2(-3.4, 7.2), Vector2(1.5, 7.3), Vector2(6.9, 6.8), Vector2(12, 5.8),
				Vector2(6.8, 6.2), Vector2(1.5, 6.2), Vector2(-3.1, 5.5), Vector2(-6.1, 4.4), Vector2(-6.6, 3.4),
			]},
			{"shade": 2, "pts": [
				Vector2(-6.6, -3.4), Vector2(-6.1, -4.4), Vector2(-3.1, -5.5), Vector2(1.5, -6.2), Vector2(6.8, -6.2), Vector2(12, -5.8),
				Vector2(6.9, -6.8), Vector2(1.5, -7.3), Vector2(-3.4, -7.2), Vector2(-7.3, -6.3), Vector2(-9.4, -3.4),
			]},
			{"shade": 1, "pts": [
				Vector2(18, 0), Vector2(12, 0.9), Vector2(6, 1.7), Vector2(0, 2.8), Vector2(-6, 4.2), Vector2(-12, 4.8),
				Vector2(-16, 3.8), Vector2(-16, 2), Vector2(-13, 0), Vector2(-16, -2), Vector2(-16, -3.8), Vector2(-12, -4.8),
				Vector2(-6, -4.2), Vector2(0, -2.8), Vector2(6, -1.7), Vector2(12, -0.9),
			]},
			{"shade": 2, "pts": [
				Vector2(-6, 0), Vector2(-8, 3), Vector2(-13, 4.2), Vector2(-15, 2.8), Vector2(-15, 1.2), Vector2(-12, 0),
				Vector2(-15, -1.2), Vector2(-15, -2.8), Vector2(-13, -4.2), Vector2(-8, -3),
			]},
		],
		"veins": [
			[Vector2(16, 0), Vector2(-10, 0)],
		],
		"glow": [Vector3(-15, 2.2, 1.1), Vector3(-15, -2.2, 1.1)],
		"jet": [Vector2(-16, 0), Vector2(-2, 6.5)],
	},
	# Reaver: a long spine with layers of swept blades and a forked prow.
	"destroyer": {
		"sil": [
			Vector2(18, 0), Vector2(14.7, 1.3), Vector2(15.7, 2.2), Vector2(13, 4), Vector2(10.1, 4.5), Vector2(8.3, 4.2),
			Vector2(7, 4.8), Vector2(2.9, 5.6), Vector2(-2.4, 5.6), Vector2(-4.7, 6.2), Vector2(-9.2, 6.5), Vector2(-13.5, 6.3),
			Vector2(-17.5, 5.6), Vector2(-13.4, 5.7), Vector2(-9.3, 5.3), Vector2(-5.1, 4.4), Vector2(-0.9, 2.6), Vector2(-15, 3.2),
			Vector2(-18, 2.4), Vector2(-16, 0), Vector2(-18, -2.4), Vector2(-15, -3.2), Vector2(-0.9, -2.6), Vector2(-5.1, -4.4),
			Vector2(-9.3, -5.3), Vector2(-13.4, -5.7), Vector2(-17.5, -5.6), Vector2(-13.5, -6.3), Vector2(-9.2, -6.5), Vector2(-4.7, -6.2),
			Vector2(-2.4, -5.6), Vector2(2.9, -5.6), Vector2(7, -4.8), Vector2(8.3, -4.2), Vector2(10.1, -4.5), Vector2(13, -4),
			Vector2(15.7, -2.2), Vector2(14.7, -1.3),
		],
		"lo": [
			Vector2(18, 0), Vector2(13, 4), Vector2(-4.7, 6.2), Vector2(-17.5, 5.6), Vector2(-9.3, 5.3), Vector2(-0.9, 2.6),
			Vector2(-18, 2.4), Vector2(-16, 0), Vector2(-18, -2.4), Vector2(-0.9, -2.6), Vector2(-9.3, -5.3), Vector2(-17.5, -5.6),
			Vector2(-13.5, -6.3), Vector2(13, -4),
		],
		"parts": [
			{"shade": 0, "pts": [
				Vector2(2.2, 0.8), Vector2(-1.3, 2.9), Vector2(-5.1, 4.4), Vector2(-9.3, 5.3), Vector2(-13.4, 5.7), Vector2(-17.5, 5.6),
				Vector2(-13.5, 6.3), Vector2(-9.2, 6.5), Vector2(-4.7, 6.2), Vector2(-0.4, 5.1), Vector2(3.8, 3.2),
			]},
			{"shade": 0, "pts": [
				Vector2(3.8, -3.2), Vector2(-0.4, -5.1), Vector2(-4.7, -6.2), Vector2(-9.2, -6.5), Vector2(-13.5, -6.3), Vector2(-17.5, -5.6),
				Vector2(-13.4, -5.7), Vector2(-9.3, -5.3), Vector2(-5.1, -4.4), Vector2(-1.3, -2.9), Vector2(2.2, -0.8),
			]},
			{"shade": 1, "pts": [
				Vector2(18, 0), Vector2(15.5, 0.9), Vector2(13, 2.2), Vector2(10, 1.6), Vector2(6, 2), Vector2(0, 2.6),
				Vector2(-8, 3), Vector2(-15, 3.2), Vector2(-18, 2.4), Vector2(-16, 0), Vector2(-18, -2.4), Vector2(-15, -3.2),
				Vector2(-8, -3), Vector2(0, -2.6), Vector2(6, -2), Vector2(10, -1.6), Vector2(13, -2.2), Vector2(15.5, -0.9),
			]},
		],
		"veins": [
			[
				Vector2(16, 0), Vector2(10, 0), Vector2(5, 2.2), Vector2(0, 4.4), Vector2(-6, 5.4), Vector2(-10, 5.6), Vector2(-6, 5.4), Vector2(0, 4.4),
				Vector2(5, 2.2), Vector2(10, 0), Vector2(5, -2.2), Vector2(0, -4.4), Vector2(-6, -5.4), Vector2(-10, -5.6), Vector2(-6, -5.4), Vector2(0, -4.4),
				Vector2(5, -2.2), Vector2(10, 0), Vector2(9.5, 0), Vector2(12, 0.8), Vector2(9.5, 0), Vector2(12, -0.8), Vector2(9.5, 0), Vector2(2.5, 0),
				Vector2(5, 1.4), Vector2(2.5, 0), Vector2(5, -1.4), Vector2(2.5, 0), Vector2(-4.5, 0), Vector2(-2, 1.6), Vector2(-4.5, 0), Vector2(-2, -1.6),
				Vector2(-4.5, 0), Vector2(-11.5, 0), Vector2(-9, 1.8), Vector2(-11.5, 0), Vector2(-9, -1.8), Vector2(-11.5, 0), Vector2(-14, 0),
			],
		],
		"glow": [Vector3(-17, 1.3, 0.8), Vector3(-17, -1.3, 0.8)],
		"jet": [Vector2(-18, 0), Vector2(-4, 5.5)],
	},
	# Tyrant: a heavy spine with a three-pronged prow, huge forward claws and back-swept under-blades.
	"battlecruiser": {
		"sil": [
			Vector2(18, 0), Vector2(15, 1.2), Vector2(14.5, 3.4), Vector2(11, 2.6), Vector2(4.1, 3.1), Vector2(4.6, 4.3),
			Vector2(0.6, 5.6), Vector2(7, 5.5), Vector2(11, 5), Vector2(7, 6.1), Vector2(2.4, 6.8), Vector2(-2.4, 7.1),
			Vector2(-6.9, 7), Vector2(-9.5, 6.4), Vector2(-16, 6), Vector2(-11.3, 5.8), Vector2(-13.5, 4.2), Vector2(-12.8, 3.8),
			Vector2(-14, 3.8), Vector2(-18, 3), Vector2(-16, 0), Vector2(-18, -3), Vector2(-14, -3.8), Vector2(-12.8, -3.8),
			Vector2(-13.5, -4.2), Vector2(-11.3, -5.8), Vector2(-16, -6), Vector2(-9.5, -6.4), Vector2(-6.9, -7), Vector2(-2.4, -7.1),
			Vector2(2.4, -6.8), Vector2(7, -6.1), Vector2(11, -5), Vector2(7, -5.5), Vector2(0.6, -5.6), Vector2(4.6, -4.3),
			Vector2(4.1, -3.1), Vector2(11, -2.6), Vector2(14.5, -3.4), Vector2(15, -1.2),
		],
		"lo": [
			Vector2(18, 0), Vector2(14.5, 3.4), Vector2(4.1, 3.1), Vector2(0.6, 5.6), Vector2(11, 5), Vector2(2.4, 6.8),
			Vector2(-16, 6), Vector2(-11.3, 5.8), Vector2(-18, 3), Vector2(-18, -3), Vector2(-11.3, -5.8), Vector2(-16, -6),
			Vector2(-6.9, -7), Vector2(11, -5), Vector2(0.6, -5.6),
		],
		"parts": [
			{"shade": 0, "pts": [
				Vector2(3.4, 1.7), Vector2(0, 3.4), Vector2(-3.5, 4.6), Vector2(-7.3, 5.4), Vector2(-11.4, 5.8), Vector2(-16, 6),
				Vector2(-11.4, 6.4), Vector2(-7.2, 6.5), Vector2(-3.2, 6.3), Vector2(0.7, 5.6), Vector2(4.6, 4.3),
			]},
			{"shade": 0, "pts": [
				Vector2(4.6, -4.3), Vector2(0.7, -5.6), Vector2(-3.2, -6.3), Vector2(-7.2, -6.5), Vector2(-11.4, -6.4), Vector2(-16, -6),
				Vector2(-11.4, -5.8), Vector2(-7.3, -5.4), Vector2(-3.5, -4.6), Vector2(0, -3.4), Vector2(3.4, -1.7),
			]},
			{"shade": 2, "pts": [
				Vector2(-13.5, 4.2), Vector2(-10.7, 6.2), Vector2(-6.9, 7), Vector2(-2.4, 7.1), Vector2(2.4, 6.8), Vector2(7, 6.1),
				Vector2(11, 5), Vector2(7, 5.5), Vector2(2.3, 5.7), Vector2(-2.3, 5.5), Vector2(-6.5, 4.7), Vector2(-9.5, 3.6),
				Vector2(-10.5, 2.6),
			]},
			{"shade": 2, "pts": [
				Vector2(-10.5, -2.6), Vector2(-9.5, -3.6), Vector2(-6.5, -4.7), Vector2(-2.3, -5.5), Vector2(2.3, -5.7), Vector2(7, -5.5),
				Vector2(11, -5), Vector2(7, -6.1), Vector2(2.4, -6.8), Vector2(-2.4, -7.1), Vector2(-6.9, -7), Vector2(-10.7, -6.2),
				Vector2(-13.5, -4.2),
			]},
			{"shade": 1, "pts": [
				Vector2(18, 0), Vector2(15, 1.2), Vector2(14.5, 3.4), Vector2(11, 2.6), Vector2(6, 3), Vector2(0, 3.4),
				Vector2(-8, 3.8), Vector2(-14, 3.8), Vector2(-18, 3), Vector2(-16, 0), Vector2(-18, -3), Vector2(-14, -3.8),
				Vector2(-8, -3.8), Vector2(0, -3.4), Vector2(6, -3), Vector2(11, -2.6), Vector2(14.5, -3.4), Vector2(15, -1.2),
			]},
		],
		"veins": [
			[
				Vector2(16, 0), Vector2(9, 0), Vector2(5, 2.6), Vector2(0, 4.8), Vector2(-5, 5.8), Vector2(-9, 5), Vector2(-5, 5.8), Vector2(0, 4.8),
				Vector2(5, 2.6), Vector2(9, 0), Vector2(5, -2.6), Vector2(0, -4.8), Vector2(-5, -5.8), Vector2(-9, -5), Vector2(-5, -5.8), Vector2(0, -4.8),
				Vector2(5, -2.6), Vector2(9, 0), Vector2(8, 0), Vector2(11, 1.2), Vector2(8, 0), Vector2(11, -1.2), Vector2(8, 0), Vector2(1, 0),
				Vector2(4, 1.6), Vector2(1, 0), Vector2(4, -1.6), Vector2(1, 0), Vector2(-6, 0), Vector2(-3, 2), Vector2(-6, 0), Vector2(-3, -2),
				Vector2(-6, 0), Vector2(-13, 0), Vector2(-10, 2.2), Vector2(-13, 0), Vector2(-10, -2.2), Vector2(-13, 0), Vector2(-14, 0),
			],
		],
		"glow": [Vector3(-17, 1.8, 0.9), Vector3(-17, -1.8, 0.9)],
		"jet": [Vector2(-18, 0), Vector2(-6, 6.5)],
	},
}

## The three lane minion types: type id -> shape (unit space). They are the
## simple shapes of this file: one smooth outline of 16 to 22 points, no plates,
## one engine light and a "body" tint, so they read as basic and are never taken
## for the bladed pilot hulls (the Aurelian minions, MinionShapes, follow the
## same rule in their own plain way).
const MINIONS := {
	# Spore: a smooth teardrop seed with one glowing eye: no horns, claws or plates.
	"fighter": {
		"sil": [
			Vector2(1, 0), Vector2(0.898, 0.132), Vector2(0.55, 0.355), Vector2(0.261, 0.47), Vector2(-0.037, 0.52), Vector2(-0.252, 0.491),
			Vector2(-0.432, 0.4), Vector2(-0.551, 0.218), Vector2(-0.6, 0), Vector2(-0.551, -0.218), Vector2(-0.432, -0.4), Vector2(-0.252, -0.491),
			Vector2(-0.037, -0.52), Vector2(0.261, -0.47), Vector2(0.55, -0.355), Vector2(0.898, -0.132),
		],
		"lo": [
			Vector2(1, 0), Vector2(0.55, 0.355), Vector2(-0.037, 0.52), Vector2(-0.432, 0.4), Vector2(-0.6, 0), Vector2(-0.432, -0.4),
			Vector2(-0.037, -0.52), Vector2(0.55, -0.355),
		],
		"parts": [],
		"veins": [],
		"glow": [Vector3(-0.42, 0, 0.12)],
		"body": 0.35,
	},
	# Bloat: a short, broad pod, blunt at both ends with a dimple in its nose (never mistaken for the pointed Spore): no jaws, wings or plates.
	"bomber": {
		"sil": [
			Vector2(0.845, 0), Vector2(0.906, 0.17), Vector2(0.868, 0.335), Vector2(0.79, 0.43), Vector2(0.6, 0.51), Vector2(0.25, 0.54),
			Vector2(-0.25, 0.53), Vector2(-0.54, 0.485), Vector2(-0.665, 0.39), Vector2(-0.705, 0.22), Vector2(-0.71, 0), Vector2(-0.705, -0.22),
			Vector2(-0.665, -0.39), Vector2(-0.54, -0.485), Vector2(-0.25, -0.53), Vector2(0.25, -0.54), Vector2(0.6, -0.51), Vector2(0.79, -0.43),
			Vector2(0.868, -0.335), Vector2(0.906, -0.17),
		],
		"lo": [
			Vector2(0.906, 0.2), Vector2(0.79, 0.43), Vector2(0.25, 0.54), Vector2(-0.54, 0.485), Vector2(-0.69, 0.3), Vector2(-0.69, -0.3),
			Vector2(-0.54, -0.485), Vector2(0.25, -0.54), Vector2(0.79, -0.43), Vector2(0.906, -0.2),
		],
		"parts": [],
		"veins": [],
		"glow": [Vector3(-0.5, 0, 0.13)],
		"body": 0.35,
	},
	# Cocoon: a long smooth gourd of two soft lobes with one spine: no horns or plates.
	"corvette": {
		"sil": [
			Vector2(1, 0), Vector2(0.983, 0.086), Vector2(0.908, 0.21), Vector2(0.739, 0.323), Vector2(0.535, 0.363), Vector2(0.293, 0.304),
			Vector2(-0.256, 0.529), Vector2(-0.447, 0.56), Vector2(-0.627, 0.532), Vector2(-0.762, 0.454), Vector2(-0.879, 0.223), Vector2(-0.899, 0),
			Vector2(-0.879, -0.223), Vector2(-0.762, -0.454), Vector2(-0.627, -0.532), Vector2(-0.447, -0.56), Vector2(-0.256, -0.529), Vector2(0.293, -0.304),
			Vector2(0.535, -0.363), Vector2(0.739, -0.323), Vector2(0.908, -0.21), Vector2(0.983, -0.086),
		],
		"lo": [
			Vector2(1, 0), Vector2(0.739, 0.323), Vector2(0.293, 0.304), Vector2(-0.447, 0.56), Vector2(-0.762, 0.454), Vector2(-0.899, 0),
			Vector2(-0.762, -0.454), Vector2(-0.447, -0.56), Vector2(0.293, -0.304), Vector2(0.739, -0.323),
		],
		"parts": [],
		"veins": [
			[Vector2(0.7, 0), Vector2(-0.55, 0)],
		],
		"glow": [Vector3(-0.8, 0, 0.12)],
		"body": 0.35,
	},
}

## The other small units, by name (unit space; the turrets are two types).
const UNITS := {
	# Scarab: an oval body with two grabbing claws in front.
	"mining_drone": {
		"sil": [
			Vector2(1, 0.17), Vector2(0.92, 0.47), Vector2(0.74, 0.66), Vector2(0.47, 0.75), Vector2(0.17, 0.66), Vector2(-0.05, 0.41),
			Vector2(-0.4, 0.43), Vector2(-0.8, 0.26), Vector2(-0.72, 0), Vector2(-0.8, -0.26), Vector2(-0.4, -0.43), Vector2(-0.05, -0.41),
			Vector2(0.17, -0.66), Vector2(0.47, -0.75), Vector2(0.74, -0.66), Vector2(0.92, -0.47), Vector2(1, -0.17), Vector2(0.87, -0.43),
			Vector2(0.67, -0.56), Vector2(0.49, -0.57), Vector2(0.35, -0.48), Vector2(0.27, -0.31), Vector2(0.5, -0.19), Vector2(0.62, 0),
			Vector2(0.5, 0.19), Vector2(0.27, 0.31), Vector2(0.35, 0.48), Vector2(0.49, 0.57), Vector2(0.67, 0.56), Vector2(0.87, 0.43),
		],
		"lo": [
			Vector2(1, 0.17), Vector2(0.47, 0.75), Vector2(-0.8, 0.26), Vector2(-0.8, -0.26), Vector2(0.47, -0.75), Vector2(1, -0.17),
			Vector2(0.35, -0.48), Vector2(0.62, 0), Vector2(0.35, 0.48),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(-0.06, 0.4), Vector2(0.17, 0.66), Vector2(0.47, 0.75), Vector2(0.74, 0.66), Vector2(0.92, 0.47), Vector2(1, 0.17),
				Vector2(0.87, 0.43), Vector2(0.67, 0.56), Vector2(0.49, 0.57), Vector2(0.35, 0.48), Vector2(0.26, 0.29),
			]},
			{"shade": 2, "pts": [
				Vector2(0.26, -0.29), Vector2(0.35, -0.48), Vector2(0.49, -0.57), Vector2(0.67, -0.56), Vector2(0.87, -0.43), Vector2(1, -0.17),
				Vector2(0.92, -0.47), Vector2(0.74, -0.66), Vector2(0.47, -0.75), Vector2(0.17, -0.66), Vector2(-0.06, -0.4),
			]},
			{"shade": 1, "pts": [
				Vector2(0.62, 0), Vector2(0.5, 0.19), Vector2(0.1, 0.4), Vector2(-0.4, 0.43), Vector2(-0.8, 0.26), Vector2(-0.72, 0),
				Vector2(-0.8, -0.26), Vector2(-0.4, -0.43), Vector2(0.1, -0.4), Vector2(0.5, -0.19),
			]},
		],
		"veins": [],
		"glow": [Vector3(-0.72, 0.129, 0.093), Vector3(-0.72, -0.129, 0.093)],
	},
	# Pinwheel: four curved blades round a hub, like a spinning thorn star.
	"repair_drone": {
		"sil": [
			Vector2(1, 0.65), Vector2(0.76, 0.33), Vector2(0.47, 0.13), Vector2(0.21, 0.15), Vector2(0.15, 0.25), Vector2(0.12, 0.25),
			Vector2(0.06, 0.57), Vector2(-0.26, 0.84), Vector2(-0.65, 1), Vector2(-0.33, 0.76), Vector2(-0.13, 0.47), Vector2(-0.14, 0.25),
			Vector2(-0.15, 0.25), Vector2(-0.22, 0.13), Vector2(-0.57, 0.06), Vector2(-0.84, -0.26), Vector2(-1, -0.65), Vector2(-0.76, -0.33),
			Vector2(-0.47, -0.13), Vector2(-0.21, -0.15), Vector2(-0.15, -0.25), Vector2(-0.12, -0.25), Vector2(-0.06, -0.57), Vector2(0.26, -0.84),
			Vector2(0.65, -1), Vector2(0.33, -0.76), Vector2(0.13, -0.47), Vector2(0.14, -0.25), Vector2(0.15, -0.25), Vector2(0.22, -0.13),
			Vector2(0.57, -0.06), Vector2(0.84, 0.26),
		],
		"lo": [
			Vector2(1, 0.65), Vector2(0.47, 0.13), Vector2(0.21, 0.15), Vector2(0.06, 0.57), Vector2(-0.65, 1), Vector2(-0.14, 0.25),
			Vector2(-0.57, 0.06), Vector2(-1, -0.65), Vector2(-0.47, -0.13), Vector2(-0.21, -0.15), Vector2(-0.06, -0.57), Vector2(0.65, -1),
			Vector2(0.14, -0.25), Vector2(0.57, -0.06),
		],
		"parts": [
			{"shade": 1, "pts": [
				Vector2(-0.15, 0.17), Vector2(-0.13, 0.47), Vector2(-0.33, 0.76), Vector2(-0.65, 1), Vector2(-0.26, 0.84), Vector2(0.06, 0.57),
				Vector2(0.15, 0.08),
			]},
			{"shade": 1, "pts": [
				Vector2(-0.17, -0.15), Vector2(-0.47, -0.13), Vector2(-0.76, -0.33), Vector2(-1, -0.65), Vector2(-0.84, -0.26), Vector2(-0.57, 0.06),
				Vector2(-0.08, 0.15),
			]},
			{"shade": 1, "pts": [
				Vector2(0.15, -0.17), Vector2(0.13, -0.47), Vector2(0.33, -0.76), Vector2(0.65, -1), Vector2(0.26, -0.84), Vector2(-0.06, -0.57),
				Vector2(-0.15, -0.08),
			]},
			{"shade": 2, "pts": [Vector2(0.29, 0), Vector2(0.15, 0.25), Vector2(-0.15, 0.25), Vector2(-0.29, 0), Vector2(-0.15, -0.25), Vector2(0.15, -0.25)]},
		],
		"veins": [],
		"glow": [],
	},
	# Eye: a four-point thorn star with small diagonal thorns and a glowing pupil.
	"ward": {
		"sil": [
			Vector2(1, 0), Vector2(0.28, 0.11), Vector2(0.44, 0.44), Vector2(0.11, 0.28), Vector2(0, 1), Vector2(-0.11, 0.28),
			Vector2(-0.44, 0.44), Vector2(-0.28, 0.11), Vector2(-1, 0), Vector2(-0.28, -0.11), Vector2(-0.44, -0.44), Vector2(-0.11, -0.28),
			Vector2(0, -1), Vector2(0.11, -0.28), Vector2(0.44, -0.44), Vector2(0.28, -0.11),
		],
		"lo": [
			Vector2(1, 0), Vector2(0.28, 0.11), Vector2(0, 1), Vector2(-0.11, 0.28), Vector2(-1, 0), Vector2(-0.28, -0.11),
			Vector2(0, -1), Vector2(0.11, -0.28),
		],
		"parts": [
		],
		"veins": [],
		"glow": [Vector3(0, 0, 0.22)],
	},
	# Claw pod: a dark dome ringed by four curved claws.
	"pd": {
		"sil": [
			Vector2(1, -0.18), Vector2(0.82, -0.26), Vector2(0.64, -0.31), Vector2(0.5, -0.32), Vector2(0.42, -0.29), Vector2(0.45, -0.26),
			Vector2(0.52, 0), Vector2(0.46, 0.23), Vector2(0.51, 0.34), Vector2(0.49, 0.52), Vector2(0.43, 0.68), Vector2(0.32, 0.84),
			Vector2(0.18, 1), Vector2(0.26, 0.82), Vector2(0.31, 0.64), Vector2(0.32, 0.5), Vector2(0.29, 0.42), Vector2(0.26, 0.45),
			Vector2(0, 0.52), Vector2(-0.22, 0.46), Vector2(-0.34, 0.51), Vector2(-0.52, 0.49), Vector2(-0.68, 0.43), Vector2(-0.84, 0.32),
			Vector2(-1, 0.18), Vector2(-0.82, 0.26), Vector2(-0.64, 0.31), Vector2(-0.5, 0.32), Vector2(-0.42, 0.29), Vector2(-0.45, 0.26),
			Vector2(-0.52, 0), Vector2(-0.46, -0.23), Vector2(-0.51, -0.34), Vector2(-0.49, -0.52), Vector2(-0.43, -0.68), Vector2(-0.32, -0.84),
			Vector2(-0.17, -1), Vector2(-0.26, -0.82), Vector2(-0.31, -0.64), Vector2(-0.32, -0.5), Vector2(-0.29, -0.42), Vector2(-0.26, -0.45),
			Vector2(0, -0.52), Vector2(0.23, -0.46), Vector2(0.34, -0.51), Vector2(0.52, -0.49), Vector2(0.68, -0.43), Vector2(0.84, -0.32),
		],
		"lo": [
			Vector2(1, -0.18), Vector2(0.42, -0.29), Vector2(0.49, 0.52), Vector2(0.18, 1), Vector2(0.29, 0.42), Vector2(-0.52, 0.49),
			Vector2(-1, 0.18), Vector2(-0.42, 0.29), Vector2(-0.49, -0.52), Vector2(-0.17, -1), Vector2(-0.29, -0.42), Vector2(0.52, -0.49),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(0.16, 0.38), Vector2(0.23, 0.38), Vector2(0.28, 0.41), Vector2(0.32, 0.5), Vector2(0.31, 0.64), Vector2(0.26, 0.82),
				Vector2(0.18, 1), Vector2(0.32, 0.84), Vector2(0.43, 0.68), Vector2(0.49, 0.52), Vector2(0.51, 0.34), Vector2(0.43, 0.17),
				Vector2(0.25, 0.03),
			]},
			{"shade": 2, "pts": [
				Vector2(-0.38, 0.16), Vector2(-0.38, 0.23), Vector2(-0.41, 0.28), Vector2(-0.5, 0.32), Vector2(-0.64, 0.31), Vector2(-0.82, 0.26),
				Vector2(-1, 0.18), Vector2(-0.84, 0.32), Vector2(-0.68, 0.43), Vector2(-0.52, 0.49), Vector2(-0.34, 0.51), Vector2(-0.17, 0.43),
				Vector2(-0.03, 0.25),
			]},
			{"shade": 2, "pts": [
				Vector2(-0.16, -0.38), Vector2(-0.23, -0.38), Vector2(-0.28, -0.41), Vector2(-0.32, -0.5), Vector2(-0.31, -0.64), Vector2(-0.26, -0.82),
				Vector2(-0.17, -1), Vector2(-0.32, -0.84), Vector2(-0.43, -0.68), Vector2(-0.49, -0.52), Vector2(-0.51, -0.34), Vector2(-0.43, -0.17),
				Vector2(-0.25, -0.03),
			]},
			{"shade": 2, "pts": [
				Vector2(0.38, -0.16), Vector2(0.38, -0.23), Vector2(0.41, -0.28), Vector2(0.5, -0.32), Vector2(0.64, -0.31), Vector2(0.82, -0.26),
				Vector2(1, -0.18), Vector2(0.84, -0.32), Vector2(0.68, -0.43), Vector2(0.52, -0.49), Vector2(0.34, -0.51), Vector2(0.17, -0.43),
				Vector2(0.03, -0.25),
			]},
		],
		"veins": [],
		"glow": [Vector3(0, 0, 0.133)],
	},
	# Maw: a long four-pointed star with a toothed core.
	"torp": {
		"sil": [
			Vector2(1.2, 0), Vector2(0.36, 0.33), Vector2(0.35, 0.35), Vector2(0.33, 0.36), Vector2(0, 1.2), Vector2(-0.33, 0.36),
			Vector2(-0.35, 0.35), Vector2(-0.36, 0.33), Vector2(-1.2, 0), Vector2(-0.36, -0.33), Vector2(-0.35, -0.35), Vector2(-0.33, -0.36),
			Vector2(0, -1.2), Vector2(0.33, -0.36), Vector2(0.35, -0.35), Vector2(0.36, -0.33),
		],
		"lo": [
			Vector2(1.2, 0), Vector2(0.36, 0.33), Vector2(0.33, 0.36), Vector2(0, 1.2), Vector2(-0.33, 0.36), Vector2(-0.36, 0.33),
			Vector2(-1.2, 0), Vector2(-0.36, -0.33), Vector2(-0.33, -0.36), Vector2(0, -1.2), Vector2(0.33, -0.36), Vector2(0.36, -0.33),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(0.5, 0), Vector2(0.35, 0.35), Vector2(0, 0.5), Vector2(-0.35, 0.35), Vector2(-0.5, 0), Vector2(-0.35, -0.35),
				Vector2(0, -0.5), Vector2(0.35, -0.35),
			]},
		],
		"veins": [],
		"glow": [Vector3(0, 0, 0.16)],
	},
	# Pod: a serrated seed-pod shell with two front horns.
	"repair_bay": {
		"sil": [
			Vector2(1.05, 0.32), Vector2(0.92, 0.62), Vector2(0.62, 0.68), Vector2(0.43, 0.52), Vector2(0.3, 0.7), Vector2(-0.05, 0.52),
			Vector2(-0.4, 0.7), Vector2(-0.7, 0.46), Vector2(-0.95, 0.3), Vector2(-1, 0), Vector2(-0.95, -0.3), Vector2(-0.7, -0.46),
			Vector2(-0.4, -0.7), Vector2(-0.05, -0.52), Vector2(0.3, -0.7), Vector2(0.43, -0.52), Vector2(0.62, -0.68), Vector2(0.92, -0.62),
			Vector2(1.05, -0.32), Vector2(0.88, -0.56), Vector2(0.67, -0.56), Vector2(0.55, -0.41), Vector2(0.8, -0.34), Vector2(1, 0),
			Vector2(0.8, 0.34), Vector2(0.55, 0.41), Vector2(0.67, 0.56), Vector2(0.88, 0.56),
		],
		"lo": [
			Vector2(1.05, 0.32), Vector2(0.92, 0.62), Vector2(-0.4, 0.7), Vector2(-0.95, 0.3), Vector2(-0.95, -0.3), Vector2(-0.4, -0.7),
			Vector2(0.92, -0.62), Vector2(1.05, -0.32), Vector2(0.88, -0.56), Vector2(0.55, -0.41), Vector2(1, 0), Vector2(0.55, 0.41),
			Vector2(0.88, 0.56),
		],
		"parts": [
			{"shade": 2, "pts": [
				Vector2(0.31, 0.43), Vector2(0.62, 0.68), Vector2(0.92, 0.62), Vector2(1.05, 0.32), Vector2(0.88, 0.56), Vector2(0.67, 0.56),
				Vector2(0.49, 0.33),
			]},
			{"shade": 2, "pts": [
				Vector2(0.49, -0.33), Vector2(0.67, -0.56), Vector2(0.88, -0.56), Vector2(1.05, -0.32), Vector2(0.92, -0.62), Vector2(0.62, -0.68),
				Vector2(0.31, -0.43),
			]},
			{"shade": 1, "pts": [
				Vector2(1, 0), Vector2(0.8, 0.34), Vector2(0.5, 0.42), Vector2(0.3, 0.7), Vector2(-0.05, 0.52), Vector2(-0.4, 0.7),
				Vector2(-0.7, 0.46), Vector2(-0.95, 0.3), Vector2(-1, 0), Vector2(-0.95, -0.3), Vector2(-0.7, -0.46), Vector2(-0.4, -0.7),
				Vector2(-0.05, -0.52), Vector2(0.3, -0.7), Vector2(0.5, -0.42), Vector2(0.8, -0.34),
			]},
		],
		"veins": [],
		"glow": [],
	},
}

## The mothership, in world units for a ship 1600 long and 340 wide
## (CinderPaint stretches it to the real length and beam).
## Citadel: a fork-headed carapace: a long spire between two curved prong-blades that carry the gun pods, a wide armoured body, thorns along one flank, a split claw tip on the other and a serrated stern with five engines.
const MOTHERSHIP := {
	"sil": [
		Vector2(816, 0), Vector2(700, 12), Vector2(770, 34), Vector2(640, 30), Vector2(500, 44), Vector2(400, 58),
		Vector2(338, 66), Vector2(334, 118), Vector2(341.5, 119), Vector2(394, 123), Vector2(450, 123.5), Vector2(508.5, 120.5),
		Vector2(544, 117), Vector2(548, 110), Vector2(572, 110), Vector2(574.5, 114.5), Vector2(627, 108.5), Vector2(685, 100.5),
		Vector2(740, 92), Vector2(687, 109.5), Vector2(634, 125.5), Vector2(682, 122), Vector2(736, 108), Vector2(683, 128.5),
		Vector2(616.5, 140), Vector2(585, 139), Vector2(578, 141), Vector2(572, 151.5), Vector2(548, 151.5), Vector2(546.5, 149),
		Vector2(514, 157), Vector2(455, 169.5), Vector2(397, 178.5), Vector2(340, 184), Vector2(285.5, 184.5), Vector2(289.5, 150.5),
		Vector2(250, 160), Vector2(100, 168), Vector2(-150, 170), Vector2(-310.5, 167.5), Vector2(-361.5, 173.5), Vector2(-436, 178.5),
		Vector2(-517, 179), Vector2(-602.5, 175.5), Vector2(-690.5, 168), Vector2(-780, 156), Vector2(-690, 159.5), Vector2(-602, 158.5),
		Vector2(-534.5, 154), Vector2(-580, 150), Vector2(-700, 124), Vector2(-770, 94), Vector2(-740, 64), Vector2(-792, 44),
		Vector2(-760, 0), Vector2(-792, -44), Vector2(-740, -64), Vector2(-770, -94), Vector2(-700, -124), Vector2(-580, -150),
		Vector2(-534.5, -154), Vector2(-602, -158.5), Vector2(-690, -159.5), Vector2(-780, -156), Vector2(-690.5, -168), Vector2(-602.5, -175.5),
		Vector2(-517, -179), Vector2(-436, -178.5), Vector2(-361.5, -173.5), Vector2(-310.5, -167.5), Vector2(-190, -169.5), Vector2(-172, -178),
		Vector2(-139.5, -170), Vector2(-70, -169.5), Vector2(-52, -178), Vector2(-15.5, -169), Vector2(48, -168.5), Vector2(68, -178),
		Vector2(110, -167.5), Vector2(160, -165), Vector2(188, -178), Vector2(244, -164), Vector2(205.5, -162.5), Vector2(250, -160),
		Vector2(289.5, -150.5), Vector2(285.5, -184.5), Vector2(340, -184), Vector2(397, -178.5), Vector2(455, -169.5), Vector2(514, -157),
		Vector2(546.5, -149), Vector2(548, -151.5), Vector2(572, -151.5), Vector2(578, -141), Vector2(631, -126.5), Vector2(687, -109.5),
		Vector2(740, -92), Vector2(685, -100.5), Vector2(627, -108.5), Vector2(574.5, -114.5), Vector2(572, -110), Vector2(548, -110),
		Vector2(544, -117), Vector2(508.5, -120.5), Vector2(450, -123.5), Vector2(394, -123), Vector2(341.5, -119), Vector2(334, -118),
		Vector2(338, -66), Vector2(400, -58), Vector2(500, -44), Vector2(640, -30), Vector2(770, -34), Vector2(700, -12),
	],
	"lo": [
		Vector2(816, 0), Vector2(700, 12), Vector2(770, 34), Vector2(338, 66), Vector2(334, 118), Vector2(394, 123),
		Vector2(740, 92), Vector2(634, 125.5), Vector2(736, 108), Vector2(683, 128.5), Vector2(340, 184), Vector2(285.5, 184.5),
		Vector2(289.5, 150.5), Vector2(-436, 178.5), Vector2(-690.5, 168), Vector2(-780, 156), Vector2(-534.5, 154), Vector2(-700, 124),
		Vector2(-770, 94), Vector2(-740, 64), Vector2(-792, 44), Vector2(-760, 0), Vector2(-792, -44), Vector2(-740, -64),
		Vector2(-770, -94), Vector2(-534.5, -154), Vector2(-780, -156), Vector2(-517, -179), Vector2(188, -178), Vector2(289.5, -150.5),
		Vector2(285.5, -184.5), Vector2(397, -178.5), Vector2(572, -151.5), Vector2(740, -92), Vector2(394, -123), Vector2(334, -118),
		Vector2(338, -66), Vector2(770, -34), Vector2(700, -12),
	],
	"parts": [
		{"shade": 0, "pts": [
			Vector2(-306, 114.5), Vector2(-368, 131), Vector2(-439.5, 144), Vector2(-518, 153), Vector2(-602, 158.5), Vector2(-690, 159.5),
			Vector2(-780, 156), Vector2(-690.5, 168), Vector2(-602.5, 175.5), Vector2(-517, 179), Vector2(-436, 178.5), Vector2(-361.5, 173.5),
			Vector2(-294, 165.5),
		]},
		{"shade": 0, "pts": [
			Vector2(-294, -165.5), Vector2(-361.5, -173.5), Vector2(-436, -178.5), Vector2(-517, -179), Vector2(-602.5, -175.5), Vector2(-690.5, -168),
			Vector2(-780, -156), Vector2(-690, -159.5), Vector2(-602, -158.5), Vector2(-518, -153), Vector2(-439.5, -144), Vector2(-368, -131),
			Vector2(-306, -114.5),
		]},
		{"shade": 1, "pts": [
			Vector2(816, 0), Vector2(700, 12), Vector2(770, 34), Vector2(640, 30), Vector2(500, 44), Vector2(400, 58),
			Vector2(338, 66), Vector2(332, 140), Vector2(250, 160), Vector2(100, 168), Vector2(-150, 170), Vector2(-400, 166),
			Vector2(-580, 150), Vector2(-700, 124), Vector2(-770, 94), Vector2(-740, 64), Vector2(-792, 44), Vector2(-760, 0),
			Vector2(-792, -44), Vector2(-740, -64), Vector2(-770, -94), Vector2(-700, -124), Vector2(-580, -150), Vector2(-400, -166),
			Vector2(-150, -170), Vector2(100, -168), Vector2(250, -160), Vector2(332, -140), Vector2(338, -66), Vector2(400, -58),
			Vector2(500, -44), Vector2(640, -30), Vector2(770, -34), Vector2(700, -12),
		]},
		{"shade": 2, "pts": [
			Vector2(285.5, 184.5), Vector2(340, 184), Vector2(397, 178.5), Vector2(455, 169.5), Vector2(514, 157), Vector2(573, 142.5),
			Vector2(631, 126.5), Vector2(687, 109.5), Vector2(740, 92), Vector2(685, 100.5), Vector2(627, 108.5), Vector2(568, 115),
			Vector2(508.5, 120.5), Vector2(450, 123.5), Vector2(394, 123), Vector2(341.5, 119), Vector2(294.5, 111.5),
		]},
		{"shade": 2, "pts": [
			Vector2(294.5, -111.5), Vector2(341.5, -119), Vector2(394, -123), Vector2(450, -123.5), Vector2(508.5, -120.5), Vector2(568, -115),
			Vector2(627, -108.5), Vector2(685, -100.5), Vector2(740, -92), Vector2(687, -109.5), Vector2(631, -126.5), Vector2(573, -142.5),
			Vector2(514, -157), Vector2(455, -169.5), Vector2(397, -178.5), Vector2(340, -184), Vector2(285.5, -184.5),
		]},
		{"shade": 2, "pts": [
			Vector2(538.5, 138), Vector2(616.5, 140), Vector2(683, 128.5), Vector2(736, 108), Vector2(682, 122), Vector2(616, 127),
			Vector2(541.5, 118),
		]},
		{"shade": 2, "pts": [
			Vector2(640, 0), Vector2(520, 16), Vector2(330, 50), Vector2(100, 58), Vector2(-100, 60), Vector2(-300, 58),
			Vector2(-460, 44), Vector2(-540, 0), Vector2(-460, -44), Vector2(-300, -58), Vector2(-100, -60), Vector2(100, -58),
			Vector2(330, -50), Vector2(520, -16),
		]},
		{"shade": 1, "pts": [
			Vector2(300, 0), Vector2(260, 30), Vector2(160, 60), Vector2(40, 64), Vector2(-60, 60), Vector2(-60, 0),
			Vector2(-60, -60), Vector2(40, -64), Vector2(160, -60), Vector2(260, -30),
		]},
		{"shade": 2, "pts": [Vector2(584, 131), Vector2(572, 151.5), Vector2(548, 151.5), Vector2(536, 131), Vector2(548, 110), Vector2(572, 110)]},
		{"shade": 2, "pts": [Vector2(572, -110), Vector2(548, -110), Vector2(536, -131), Vector2(548, -151.5), Vector2(572, -151.5), Vector2(584, -131)]},
		{"shade": 2, "pts": [Vector2(474, 146.5), Vector2(462, 167.5), Vector2(438, 167.5), Vector2(426, 146.5), Vector2(438, 126), Vector2(462, 126)]},
		{"shade": 2, "pts": [Vector2(462, -126), Vector2(438, -126), Vector2(426, -146.5), Vector2(438, -167.5), Vector2(462, -167.5), Vector2(474, -146.5)]},
		{"shade": 2, "pts": [Vector2(244, -164), Vector2(188, -178), Vector2(150, -160)]},
		{"shade": 2, "pts": [Vector2(124, -164), Vector2(68, -178), Vector2(30, -160)]},
		{"shade": 2, "pts": [Vector2(4, -164), Vector2(-52, -178), Vector2(-90, -160)]},
		{"shade": 2, "pts": [Vector2(-116, -164), Vector2(-172, -178), Vector2(-210, -160)]},
	],
	"veins": [
		[
			Vector2(740, 0), Vector2(560, 0), Vector2(586, 18), Vector2(560, 0), Vector2(586, -18), Vector2(560, 0), Vector2(420, 0), Vector2(446, 18),
			Vector2(420, 0), Vector2(446, -18), Vector2(420, 0), Vector2(380, 0), Vector2(320, 60), Vector2(280, 120), Vector2(330, 164), Vector2(440, 180),
			Vector2(620, 166), Vector2(700, 118), Vector2(620, 166), Vector2(440, 180), Vector2(330, 164), Vector2(280, 120), Vector2(240, 146), Vector2(0, 156),
			Vector2(-300, 152), Vector2(-520, 136), Vector2(-300, 152), Vector2(0, 156), Vector2(240, 146), Vector2(280, 120), Vector2(330, 164), Vector2(440, 180),
			Vector2(620, 166), Vector2(700, 118), Vector2(620, 166), Vector2(440, 180), Vector2(330, 164), Vector2(280, 120), Vector2(320, 60), Vector2(380, 0),
			Vector2(320, -60), Vector2(280, -120), Vector2(330, -164), Vector2(440, -180), Vector2(620, -166), Vector2(700, -118), Vector2(620, -166), Vector2(440, -180),
			Vector2(330, -164), Vector2(280, -120), Vector2(240, -146), Vector2(0, -156), Vector2(-300, -152), Vector2(-520, -136), Vector2(-300, -152), Vector2(0, -156),
			Vector2(240, -146), Vector2(280, -120), Vector2(330, -164), Vector2(440, -180), Vector2(620, -166), Vector2(700, -118), Vector2(620, -166), Vector2(440, -180),
			Vector2(330, -164), Vector2(280, -120), Vector2(320, -60), Vector2(380, 0), Vector2(280, 0), Vector2(306, 18), Vector2(280, 0), Vector2(306, -18),
			Vector2(280, 0), Vector2(140, 0), Vector2(166, 18), Vector2(140, 0), Vector2(166, -18), Vector2(140, 0), Vector2(0, 0), Vector2(26, 18),
			Vector2(0, 0), Vector2(26, -18), Vector2(0, 0), Vector2(-140, 0), Vector2(-114, 18), Vector2(-140, 0), Vector2(-114, -18), Vector2(-140, 0),
			Vector2(-280, 0), Vector2(-254, 18), Vector2(-280, 0), Vector2(-254, -18), Vector2(-280, 0), Vector2(-420, 0), Vector2(-394, 18), Vector2(-420, 0),
			Vector2(-394, -18), Vector2(-420, 0), Vector2(-720, 0),
		],
	],
	"glow": [Vector3(-772, 0, 34), Vector3(-752, 54, 28), Vector3(-752, -54, 28), Vector3(-726, 100, 22), Vector3(-726, -100, 22)],
}
