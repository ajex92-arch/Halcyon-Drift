class_name TurretShapes
extends RefCounted
## WHAT THIS IS: the drawings of the rotating turrets on pilot ships. Every gun
## that swings (a turret or an automatic mount) is drawn as a small turret with
## a silhouette that tells its weapon apart from the others at a glance:
## point defense has two thin barrels, flak a boxy block with three barrels,
## the light turret one short barrel, the heavy cannon one long thick barrel
## with a muzzle brake, the ion turret a forked emitter dish with a glowing
## lens, the tail gun (the Bomber's rear gunner) a round ball with two short
## stubs, and the torpedo turret two fat tubes. Both teams use the same
## silhouettes, so a player learns them once; each team dresses them its own
## way (Aurelian: octagonal armoured bases and straight barrels; Vhorr: thorned
## bases and tapered fangs). A small coloured tip or lens also says which gun it
## is. The tables are only pictures: they change nothing in the game.
##
## HOW IT WORKS: a turret is drawn with its barrel along +x and its base disc
## in the middle, in "turret units" (the base disc of a class has the radius
## given in "r"). Each class has, for each team style, these polygons (lists of
## Vector2 points):
##   "base"     the base (the disc, or the block of the flak and torpedo turrets)
##   "cap"      the lighter cap on top of the base
##   "barrels"  the barrels, the muzzle brake and the dish
##   "accent"   the coloured tips and lens (the colour comes from ACCENT)
##   "extent"   how far the class reaches from the middle, in turret units
## TurretPaint scales a turret to its hull with HULL_TU (design units of the hull
## per turret unit; AurelianShapes draws a socket of the same size under each
## mount) and turns it to the mount's live angle.
## The class of a gun is read from its weapon id (CLASS_BY_WEAPON), or else from
## its weapon kind (CLASS_BY_KIND).
##
## WHO USES IT: TurretPaint reads the tables; AurelianShapes' mount pieces use
## HULL_TU's numbers; the hull gallery's turret sheet shows every silhouette.


## The weapon classes in the order the gallery shows them.
const CLASSES := ["pd", "flak", "light", "heavy", "ion", "tail", "torp"]

## The class of a weapon, from its id in Weapons.
const CLASS_BY_WEAPON := {
	"pd_gun": "pd", "m_pd": "pd", "turret_pd_gun": "pd", "bay_pd": "pd", "ms_pd": "pd",
	"flak_battery": "flak", "flak_auto": "flak", "ms_flak": "flak",
	"light_turret": "light", "m_cannon": "light", "monster_gun": "light", "battleship_gun": "light", "dreadnought_gun": "light",
	"heavy_cannon": "heavy", "ms_cannon": "heavy", "ms_heavy": "heavy",
	"ion_turret": "ion", "ms_ion": "ion",
	"tail_gun": "tail",
	"turret_torp": "torp",
}

## The class of a weapon whose id is not listed above, from its kind (Rules.W_*).
const CLASS_BY_KIND := {
	Rules.W_BOLT: "light", Rules.W_LANCE: "light", Rules.W_PD: "pd", Rules.W_FLAK: "flak",
	Rules.W_SHELL: "heavy", Rules.W_ION: "ion", Rules.W_TORP: "torp",
}

## The tip and lens colour of each class, so the guns can also be told apart by
## colour: point defense pale cyan, flak orange, the light turret yellow, the
## heavy cannon warm white, the ion turret violet, the tail gun light grey, the
## torpedo turret red-orange.
const ACCENT := {
	"pd": Color(0.55, 0.95, 0.95), "flak": Color(1.0, 0.62, 0.2), "light": Color(1.0, 0.9, 0.5),
	"heavy": Color(1.0, 0.96, 0.8), "ion": Color(0.6, 0.62, 1.0), "tail": Color(0.92, 0.92, 0.92),
	"torp": Color(1.0, 0.45, 0.25),
}

## Design units of each hull per turret unit (how big its turrets are drawn).
## A hull that is not listed (a small ship with a module gun) uses DEFAULT_TU.
const HULL_TU := {"bomber": 1.7, "logistics": 1.9, "support": 1.7, "flak": 2, "ion": 1.9, "destroyer": 1.5, "battlecruiser": 0.95, "mothership": 0.5, "pd_tower": 11, "torp_tower": 5, "repair_bay": 7.5}
## The turret size of a hull that is not in HULL_TU.
const DEFAULT_TU := 1.8

## The Aurelian turrets: clean and armoured.
const AURELIAN := {
	"pd": {"r": 0.55, "extent": 1.95,
		"base": [
			[Vector2(0.508, 0.21), Vector2(0.21, 0.508), Vector2(-0.21, 0.508), Vector2(-0.508, 0.21), Vector2(-0.508, -0.21), Vector2(-0.21, -0.508), Vector2(0.21, -0.508), Vector2(0.508, -0.21)],
		],
		"cap": [
			[Vector2(0.333, 0.138), Vector2(0.138, 0.333), Vector2(-0.138, 0.333), Vector2(-0.333, 0.138), Vector2(-0.333, -0.138), Vector2(-0.138, -0.333), Vector2(0.138, -0.333), Vector2(0.333, -0.138)],
		],
		"barrels": [
			[Vector2(0.15, 0.185), Vector2(1.9, 0.185), Vector2(1.9, 0.335), Vector2(0.15, 0.335)],
			[Vector2(0.15, -0.335), Vector2(1.9, -0.335), Vector2(1.9, -0.185), Vector2(0.15, -0.185)],
		],
		"accent": [
			[Vector2(1.7, 0.185), Vector2(1.9, 0.185), Vector2(1.9, 0.335), Vector2(1.7, 0.335)],
			[Vector2(1.7, -0.335), Vector2(1.9, -0.335), Vector2(1.9, -0.185), Vector2(1.7, -0.185)],
		],
	},
	"flak": {"r": 0.85, "extent": 2.15,
		"base": [
			[Vector2(-0.85, -0.55), Vector2(-0.55, -0.9), Vector2(0.55, -0.9), Vector2(0.85, -0.55), Vector2(0.85, 0.55), Vector2(0.55, 0.9), Vector2(-0.55, 0.9), Vector2(-0.85, 0.55)],
		],
		"cap": [
			[Vector2(-0.45, -0.5), Vector2(0.45, -0.5), Vector2(0.45, 0.5), Vector2(-0.45, 0.5)],
		],
		"barrels": [
			[Vector2(0.4, -0.14), Vector2(2.1, -0.14), Vector2(2.1, 0.14), Vector2(0.4, 0.14)],
			[Vector2(0.4, 0.48), Vector2(1.85, 0.48), Vector2(1.85, 0.72), Vector2(0.4, 0.72)],
			[Vector2(0.4, -0.72), Vector2(1.85, -0.72), Vector2(1.85, -0.48), Vector2(0.4, -0.48)],
		],
		"accent": [
			[Vector2(1.9, -0.14), Vector2(2.1, -0.14), Vector2(2.1, 0.14), Vector2(1.9, 0.14)],
			[Vector2(1.65, 0.48), Vector2(1.85, 0.48), Vector2(1.85, 0.72), Vector2(1.65, 0.72)],
			[Vector2(1.65, -0.72), Vector2(1.85, -0.72), Vector2(1.85, -0.48), Vector2(1.65, -0.48)],
		],
	},
	"light": {"r": 0.7, "extent": 2.05,
		"base": [
			[Vector2(0.7, 0), Vector2(0.495, 0.495), Vector2(0, 0.7), Vector2(-0.495, 0.495), Vector2(-0.7, 0), Vector2(-0.495, -0.495), Vector2(0, -0.7), Vector2(0.495, -0.495)],
		],
		"cap": [
			[Vector2(0.42, 0), Vector2(0.297, 0.297), Vector2(0, 0.42), Vector2(-0.297, 0.297), Vector2(-0.42, 0), Vector2(-0.297, -0.297), Vector2(0, -0.42), Vector2(0.297, -0.297)],
		],
		"barrels": [
			[Vector2(0.2, -0.11), Vector2(2, -0.11), Vector2(2, 0.11), Vector2(0.2, 0.11)],
			[Vector2(1.5, -0.2), Vector2(1.7, -0.2), Vector2(1.7, 0.2), Vector2(1.5, 0.2)],
		],
		"accent": [
			[Vector2(1.85, -0.09), Vector2(2, -0.09), Vector2(2, 0.09), Vector2(1.85, 0.09)],
		],
	},
	"heavy": {"r": 1, "extent": 3.15,
		"base": [
			[Vector2(0.924, 0.383), Vector2(0.383, 0.924), Vector2(-0.383, 0.924), Vector2(-0.924, 0.383), Vector2(-0.924, -0.383), Vector2(-0.383, -0.924), Vector2(0.383, -0.924), Vector2(0.924, -0.383)],
			[Vector2(-1.2, -0.5), Vector2(-0.6, -0.5), Vector2(-0.6, 0.5), Vector2(-1.2, 0.5)],
		],
		"cap": [
			[Vector2(0.573, 0.237), Vector2(0.237, 0.573), Vector2(-0.237, 0.573), Vector2(-0.573, 0.237), Vector2(-0.573, -0.237), Vector2(-0.237, -0.573), Vector2(0.237, -0.573), Vector2(0.573, -0.237)],
		],
		"barrels": [
			[Vector2(0.5, -0.24), Vector2(3.1, -0.24), Vector2(3.1, 0.24), Vector2(0.5, 0.24)],
			[Vector2(2.5, -0.5), Vector2(3, -0.5), Vector2(3, 0.5), Vector2(2.5, 0.5)],
		],
		"accent": [
			[Vector2(3, -0.2), Vector2(3.2, -0.2), Vector2(3.2, 0.2), Vector2(3, 0.2)],
		],
	},
	"ion": {"r": 1, "extent": 2.4,
		"base": [
			[Vector2(0.924, 0.383), Vector2(0.383, 0.924), Vector2(-0.383, 0.924), Vector2(-0.924, 0.383), Vector2(-0.924, -0.383), Vector2(-0.383, -0.924), Vector2(0.383, -0.924), Vector2(0.924, -0.383)],
		],
		"cap": [
			[Vector2(0.462, 0.191), Vector2(0.191, 0.462), Vector2(-0.191, 0.462), Vector2(-0.462, 0.191), Vector2(-0.462, -0.191), Vector2(-0.191, -0.462), Vector2(0.191, -0.462), Vector2(0.462, -0.191)],
		],
		"barrels": [
			[Vector2(0.5, -0.55), Vector2(1.9, -1.35), Vector2(2.35, -1.1), Vector2(1.4, 0), Vector2(2.35, 1.1), Vector2(1.9, 1.35), Vector2(0.5, 0.55)],
		],
		"accent": [
			[Vector2(1.464, 0.13), Vector2(1.28, 0.314), Vector2(1.02, 0.314), Vector2(0.836, 0.13), Vector2(0.836, -0.13), Vector2(1.02, -0.314), Vector2(1.28, -0.314), Vector2(1.464, -0.13)],
		],
	},
	"tail": {"r": 0.65, "extent": 1.4,
		"base": [
			[Vector2(0.65, 0), Vector2(0.46, 0.46), Vector2(0, 0.65), Vector2(-0.46, 0.46), Vector2(-0.65, 0), Vector2(-0.46, -0.46), Vector2(0, -0.65), Vector2(0.46, -0.46)],
		],
		"cap": [
			[Vector2(0.42, 0), Vector2(0.297, 0.297), Vector2(0, 0.42), Vector2(-0.297, 0.297), Vector2(-0.42, 0), Vector2(-0.297, -0.297), Vector2(0, -0.42), Vector2(0.297, -0.297)],
		],
		"barrels": [
			[Vector2(0.2, 0.16), Vector2(1.35, 0.16), Vector2(1.35, 0.3), Vector2(0.2, 0.3)],
			[Vector2(0.2, -0.3), Vector2(1.35, -0.3), Vector2(1.35, -0.16), Vector2(0.2, -0.16)],
		],
		"accent": [
			[Vector2(1.2, 0.16), Vector2(1.35, 0.16), Vector2(1.35, 0.3), Vector2(1.2, 0.3)],
			[Vector2(1.2, -0.3), Vector2(1.35, -0.3), Vector2(1.35, -0.16), Vector2(1.2, -0.16)],
		],
	},
	"torp": {"r": 0.9, "extent": 2.05,
		"base": [
			[Vector2(-0.9, -0.6), Vector2(-0.6, -0.95), Vector2(0.6, -0.95), Vector2(0.9, -0.6), Vector2(0.9, 0.6), Vector2(0.6, 0.95), Vector2(-0.6, 0.95), Vector2(-0.9, 0.6)],
		],
		"cap": [
			[Vector2(-0.5, -0.5), Vector2(0.4, -0.5), Vector2(0.4, 0.5), Vector2(-0.5, 0.5)],
		],
		"barrels": [
			[Vector2(0.2, 0.1), Vector2(2, 0.1), Vector2(2, 0.62), Vector2(0.2, 0.62)],
			[Vector2(0.2, -0.62), Vector2(2, -0.62), Vector2(2, -0.1), Vector2(0.2, -0.1)],
		],
		"accent": [
			[Vector2(1.85, 0.1), Vector2(2, 0.1), Vector2(2, 0.62), Vector2(1.85, 0.62)],
			[Vector2(1.85, -0.62), Vector2(2, -0.62), Vector2(2, -0.1), Vector2(1.85, -0.1)],
		],
	},
}

## The Vhorr turrets: thorned and organic.
const VHORR := {
	"pd": {"r": 0.55, "extent": 2,
		"base": [
			[Vector2(0.715, 0), Vector2(0.391, 0.225), Vector2(0.358, 0.619), Vector2(0, 0.451), Vector2(-0.357, 0.619), Vector2(-0.391, 0.225), Vector2(-0.715, 0), Vector2(-0.391, -0.226), Vector2(-0.358, -0.619), Vector2(0, -0.451), Vector2(0.358, -0.619), Vector2(0.391, -0.226)],
		],
		"cap": [
			[Vector2(0.277, 0.115), Vector2(0.115, 0.277), Vector2(-0.115, 0.277), Vector2(-0.277, 0.115), Vector2(-0.277, -0.115), Vector2(-0.115, -0.277), Vector2(0.115, -0.277), Vector2(0.277, -0.115)],
		],
		"barrels": [
			[Vector2(0.15, 0.37), Vector2(1.95, 0.275), Vector2(1.95, 0.245), Vector2(0.15, 0.15)],
			[Vector2(0.15, -0.15), Vector2(1.95, -0.245), Vector2(1.95, -0.275), Vector2(0.15, -0.37)],
		],
		"accent": [
			[Vector2(1.5, 0.22), Vector2(1.9, 0.22), Vector2(1.9, 0.3), Vector2(1.5, 0.3)],
			[Vector2(1.5, -0.3), Vector2(1.9, -0.3), Vector2(1.9, -0.22), Vector2(1.5, -0.22)],
		],
	},
	"flak": {"r": 0.85, "extent": 2.25,
		"base": [
			[Vector2(1.067, 0.212), Vector2(0.58, 0.387), Vector2(0.604, 0.905), Vector2(0.136, 0.684), Vector2(-0.212, 1.067), Vector2(-0.387, 0.58), Vector2(-0.905, 0.604), Vector2(-0.684, 0.136), Vector2(-1.067, -0.212), Vector2(-0.58, -0.387), Vector2(-0.604, -0.905), Vector2(-0.136, -0.684), Vector2(0.212, -1.067), Vector2(0.387, -0.58), Vector2(0.905, -0.604), Vector2(0.684, -0.136)],
		],
		"cap": [
			[Vector2(0.416, 0.172), Vector2(0.172, 0.416), Vector2(-0.172, 0.416), Vector2(-0.416, 0.172), Vector2(-0.416, -0.172), Vector2(-0.172, -0.416), Vector2(0.172, -0.416), Vector2(0.416, -0.172)],
		],
		"barrels": [
			[Vector2(0.4, 0.17), Vector2(2.2, 0.02), Vector2(2.2, -0.02), Vector2(0.4, -0.17)],
			[Vector2(0.4, 0.75), Vector2(1.85, 0.8), Vector2(1.85, 0.76), Vector2(0.4, 0.45)],
			[Vector2(0.4, -0.45), Vector2(1.85, -0.76), Vector2(1.85, -0.8), Vector2(0.4, -0.75)],
		],
		"accent": [
			[Vector2(1.7, -0.05), Vector2(2.1, -0.05), Vector2(2.1, 0.05), Vector2(1.7, 0.05)],
		],
	},
	"light": {"r": 0.7, "extent": 2.15,
		"base": [
			[Vector2(0.896, 0), Vector2(0.497, 0.287), Vector2(0.448, 0.776), Vector2(0, 0.574), Vector2(-0.448, 0.776), Vector2(-0.497, 0.287), Vector2(-0.896, 0), Vector2(-0.497, -0.287), Vector2(-0.448, -0.776), Vector2(0, -0.574), Vector2(0.448, -0.776), Vector2(0.497, -0.287)],
		],
		"cap": [
			[Vector2(0.351, 0.145), Vector2(0.145, 0.351), Vector2(-0.145, 0.351), Vector2(-0.351, 0.145), Vector2(-0.351, -0.145), Vector2(-0.145, -0.351), Vector2(0.145, -0.351), Vector2(0.351, -0.145)],
		],
		"barrels": [
			[Vector2(0.2, 0.17), Vector2(2.1, 0.02), Vector2(2.1, -0.02), Vector2(0.2, -0.17)],
		],
		"accent": [
			[Vector2(1.5, -0.05), Vector2(1.95, -0.05), Vector2(1.95, 0.05), Vector2(1.5, 0.05)],
		],
	},
	"heavy": {"r": 1, "extent": 3.45,
		"base": [
			[Vector2(1.22, 0.505), Vector2(0.58, 0.58), Vector2(0.505, 1.22), Vector2(0, 0.82), Vector2(-0.505, 1.22), Vector2(-0.58, 0.58), Vector2(-1.22, 0.505), Vector2(-0.82, 0), Vector2(-1.22, -0.505), Vector2(-0.58, -0.58), Vector2(-0.505, -1.22), Vector2(0, -0.82), Vector2(0.505, -1.22), Vector2(0.58, -0.58), Vector2(1.22, -0.505), Vector2(0.82, 0)],
		],
		"cap": [
			[Vector2(0.508, 0.21), Vector2(0.21, 0.508), Vector2(-0.21, 0.508), Vector2(-0.508, 0.21), Vector2(-0.508, -0.21), Vector2(-0.21, -0.508), Vector2(0.21, -0.508), Vector2(0.508, -0.21)],
		],
		"barrels": [
			[Vector2(0.5, 0.3), Vector2(3.3, 0.03), Vector2(3.3, -0.03), Vector2(0.5, -0.3)],
			[Vector2(2.4, 0.3), Vector2(3.4, 0.75), Vector2(3, 0.12)],
			[Vector2(2.4, -0.3), Vector2(3.4, -0.75), Vector2(3, -0.12)],
		],
		"accent": [
			[Vector2(2.4, -0.06), Vector2(3.2, -0.06), Vector2(3.2, 0.06), Vector2(2.4, 0.06)],
		],
	},
	"ion": {"r": 1, "extent": 2.4,
		"base": [
			[Vector2(1.201, 0.497), Vector2(0.58, 0.58), Vector2(0.497, 1.201), Vector2(0, 0.82), Vector2(-0.497, 1.201), Vector2(-0.58, 0.58), Vector2(-1.201, 0.497), Vector2(-0.82, 0), Vector2(-1.201, -0.497), Vector2(-0.58, -0.58), Vector2(-0.497, -1.201), Vector2(0, -0.82), Vector2(0.497, -1.201), Vector2(0.58, -0.58), Vector2(1.201, -0.497), Vector2(0.82, 0)],
		],
		"cap": [
			[Vector2(0.416, 0.172), Vector2(0.172, 0.416), Vector2(-0.172, 0.416), Vector2(-0.416, 0.172), Vector2(-0.416, -0.172), Vector2(-0.172, -0.416), Vector2(0.172, -0.416), Vector2(0.416, -0.172)],
		],
		"barrels": [
			[Vector2(0.5, -0.5), Vector2(1.5, -1.55), Vector2(2.35, -1.5), Vector2(1.65, -0.7), Vector2(1.35, -0.2), Vector2(1.35, 0.2), Vector2(1.65, 0.7), Vector2(2.35, 1.5), Vector2(1.5, 1.55), Vector2(0.5, 0.5)],
		],
		"accent": [
			[Vector2(1.346, 0.122), Vector2(1.172, 0.296), Vector2(0.928, 0.296), Vector2(0.754, 0.122), Vector2(0.754, -0.122), Vector2(0.928, -0.296), Vector2(1.172, -0.296), Vector2(1.346, -0.122)],
		],
	},
	"tail": {"r": 0.65, "extent": 1.45,
		"base": [
			[Vector2(0.819, 0), Vector2(0.462, 0.266), Vector2(0.41, 0.709), Vector2(0, 0.533), Vector2(-0.409, 0.709), Vector2(-0.462, 0.266), Vector2(-0.819, 0), Vector2(-0.462, -0.267), Vector2(-0.41, -0.709), Vector2(0, -0.533), Vector2(0.41, -0.709), Vector2(0.462, -0.267)],
		],
		"cap": [
			[Vector2(0.314, 0.13), Vector2(0.13, 0.314), Vector2(-0.13, 0.314), Vector2(-0.314, 0.13), Vector2(-0.314, -0.13), Vector2(-0.13, -0.314), Vector2(0.13, -0.314), Vector2(0.314, -0.13)],
		],
		"barrels": [
			[Vector2(0.2, 0.37), Vector2(1.4, 0.255), Vector2(1.4, 0.225), Vector2(0.2, 0.11)],
			[Vector2(0.2, -0.11), Vector2(1.4, -0.225), Vector2(1.4, -0.255), Vector2(0.2, -0.37)],
		],
		"accent": [
			[Vector2(1.1, 0.2), Vector2(1.38, 0.2), Vector2(1.38, 0.28), Vector2(1.1, 0.28)],
			[Vector2(1.1, -0.28), Vector2(1.38, -0.28), Vector2(1.38, -0.2), Vector2(1.1, -0.2)],
		],
	},
	"torp": {"r": 0.9, "extent": 2.05,
		"base": [
			[Vector2(1.048, 0.434), Vector2(0.522, 0.522), Vector2(0.434, 1.048), Vector2(0, 0.738), Vector2(-0.434, 1.048), Vector2(-0.522, 0.522), Vector2(-1.048, 0.434), Vector2(-0.738, 0), Vector2(-1.048, -0.434), Vector2(-0.522, -0.522), Vector2(-0.434, -1.048), Vector2(0, -0.738), Vector2(0.434, -1.048), Vector2(0.522, -0.522), Vector2(1.048, -0.434), Vector2(0.738, 0)],
		],
		"cap": [
			[Vector2(0.462, 0.191), Vector2(0.191, 0.462), Vector2(-0.191, 0.462), Vector2(-0.462, 0.191), Vector2(-0.462, -0.191), Vector2(-0.191, -0.462), Vector2(0.191, -0.462), Vector2(0.462, -0.191)],
		],
		"barrels": [
			[Vector2(0.2, 0.72), Vector2(2, 0.5), Vector2(2, 0.26), Vector2(0.2, 0.04)],
			[Vector2(0.2, -0.04), Vector2(2, -0.26), Vector2(2, -0.5), Vector2(0.2, -0.72)],
		],
		"accent": [
			[Vector2(1.8, 0.3), Vector2(2, 0.3), Vector2(2, 0.46), Vector2(1.8, 0.46)],
			[Vector2(1.8, -0.46), Vector2(2, -0.46), Vector2(2, -0.3), Vector2(1.8, -0.3)],
		],
	},
}
