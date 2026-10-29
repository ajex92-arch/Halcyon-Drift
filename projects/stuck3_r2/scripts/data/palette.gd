class_name Palette
extends RefCounted
## WHAT THIS IS: the game's box of colours. Colours. Team colours: Aurelian
## amber, Vhorr red, derelicts grey-teal. Every screen, ship and effect
## takes its colours from here, so the whole game looks like one piece.
##
## HOW IT WORKS: each constant is a Color(red, green, blue), where each part
## is a fraction from 0 (none) to 1 (full); Color(0, 0, 0) is black and
## Color(1, 1, 1) is white. A colour may have a fourth part, "alpha" (how
## see-through it is: 0 invisible, 1 solid); with_alpha() makes a copy with
## a chosen alpha. team() and bolt() pick a colour by team number, and
## accent() picks the menus' highlight colour for the human's team. hit_edge()
## and hit_width() give the outline of a unit that was just hit (the hit flash:
## the outline turns toward white and gets thicker, see HIT_FLASH).
##
## WHO USES IT: nearly everything that draws: the HUD and menus (UiKit,
## HudFeed, ShipStatus, Minimap, the hangar and the admiral board), the
## ship and unit pictures (ShipVisual, UnitVisual, CinderPaint, which also
## ask hit_edge() and hit_width() how a hit unit's outline flashes), the map
## (MapDecor, AsteroidField, ResourceNode, FogView) and the effects (Effects,
## ProjectilesDraw).

# --- interface colours (dark to light) -----------------------------------------

## The darkest colour, almost black: the deepest backgrounds and dark
## outlines.
const VOID := Color(0.0275, 0.0353, 0.0510)
## Very dark blue-grey: dark panel backgrounds (and the map's backdrop).
const INK := Color(0.0627, 0.0824, 0.1098)
## Dark blue-grey: the fill of panels and cards in the menus.
const PANEL := Color(0.0784, 0.1059, 0.1412)
## Muted grey-blue: thin borders and divider lines.
const LINE := Color(0.1725, 0.2196, 0.2824)
## Almost white: main text and bright highlights.
const ICE := Color(0.8941, 0.9216, 0.9529)
## Soft grey: quieter text, such as hints and small print.
const MIST := Color(0.5765, 0.6275, 0.6902)

# --- team and meaning colours ------------------------------------------------------

## Warm amber: Aurelian's team colour. It is also the menus' highlight colour
## while the human plays Aurelian (or watches); accent() picks the colour for
## the other team.
const AMBER := Color(0.8863, 0.6314, 0.2902)
## Red: Vhorr's team colour.
const CINDER := Color(0.8314, 0.3255, 0.2353)
## Teal: sensor effects, such as the Scout's Ping and the Support's Jam
## pulses.
const VEIL := Color(0.4314, 0.7216, 0.6980)
## Sandy gold: ore (resource nodes on the map and the minimap).
const ORE := Color(0.7882, 0.6431, 0.4157)
## Grey-blue: things no team holds, such as an unclaimed resource node.
const NEUTRAL := Color(0.6196, 0.6902, 0.7529)
## Grey-teal: the derelict monsters' colour (the neutral team).
const DERELICT := Color(0.55, 0.62, 0.58)

# --- world drawing colours -----------------------------------------------------------

## The dark fill inside ship and unit shapes.
const HULL_FILL := Color(0.0784, 0.1059, 0.1412)
## The dark fill inside a mothership's shape.
const MOTHER_FILL := Color(0.0706, 0.0941, 0.1255)
## The first of two asteroid shades.
const ROCK_A := Color(0.1373, 0.1686, 0.2039)
## The second asteroid shade.
const ROCK_B := Color(0.1059, 0.1412, 0.1765)
## The edge of an asteroid (also the spark when a round hits a rock).
const ROCK_EDGE := Color(0.2353, 0.2902, 0.3490)
## An ore rock that still has ore in it.
const ORE_ROCK := Color(0.5529, 0.4745, 0.3765)
## An ore rock that is mined out ("dry").
const ORE_DRY := Color(0.1647, 0.1922, 0.2196)
## The lane corridors drawn on the map and the minimap.
const LANE := Color(0.20, 0.25, 0.32)
## Aurelian's shots (see bolt()).
const BOLT_H := Color(0.9490, 0.8431, 0.6353)
## Vhorr's shots.
const BOLT_C := Color(0.9412, 0.6275, 0.5647)
## The neutral monsters' shots.
const BOLT_N := Color(0.70, 0.85, 0.80)
## The puffs of a boosting engine (Effects).
const BOOST := Color(1.0, 0.9647, 0.8745)
## The outline of an "ace" ship (a pilot on a kill streak).
const ACE := Color(1.0, 0.9569, 0.8235)
## The small side-thruster flames (ShipVisual).
const SIDE_JET := Color(0.6235, 0.8235, 0.8078)
## Light blue: shields.
const SHIELD := Color(0.45, 0.78, 1.0)
## Green: repairs and healing (and good news in messages).
const REPAIR := Color(0.45, 0.95, 0.6)
## The colour of the fog of war: the dark cover over places a team cannot
## see (FogView).
const FOG := Color(0.02, 0.025, 0.04)

# --- Cinder's alien look (CinderPaint draws it) -----------------------------------------

## Cinder's darkest plating: the blades that lie underneath the others.
const CINDER_SHADE := Color(0.055, 0.040, 0.050)
## Cinder's hull: near-black gunmetal with a slight red tint (the fill inside a
## Cinder ship's red outline, instead of a flat red fill).
const CINDER_HULL := Color(0.098, 0.071, 0.082)
## Cinder's top plates: a little lighter than the hull.
const CINDER_PLATE := Color(0.165, 0.113, 0.125)
## The three plating shades in order, so a shape's "shade" number (0 darkest,
## 1 hull, 2 lightest) picks its colour.
const CINDER_SHADES := [CINDER_SHADE, CINDER_HULL, CINDER_PLATE]
## The glowing "veins" on a Cinder ship: hotter than the team red. It is also
## the menus' highlight colour while the human plays Vhorr (accent()): a red
## bright enough to read on the dark panels.
const CINDER_VEIN := Color(1.0, 0.38, 0.22)
## The engine glow of a Cinder ship.
const CINDER_GLOW := Color(1.0, 0.62, 0.35)
## The main engine flames of a Cinder ship (the Aurelian flame is pale yellow).
const CINDER_JET := Color(1.0, 0.5, 0.28)
## The small side-thruster flames of a Cinder ship.
const CINDER_SIDE_JET := Color(1.0, 0.55, 0.45)

# --- Aurelian's steel look (AurelianPaint draws it) -------------------------------------------

## Aurelian's darkest plating: engine housings and turret sockets.
const AUREL_SHADE := Color(0.085, 0.108, 0.140)
## Aurelian's hull core: steel blue-grey, the fill inside the amber outline.
const AUREL_HULL := Color(0.190, 0.236, 0.294)
## Aurelian's top armour plates: the lightest steel.
const AUREL_PLATE := Color(0.290, 0.350, 0.420)
## The three plating shades in order, so a piece's "shade" number (0 darkest,
## 1 hull, 2 lightest) picks its colour.
const AUREL_SHADES := [AUREL_SHADE, AUREL_HULL, AUREL_PLATE]
## The dark body of a canopy or bridge window.
const AUREL_GLASS_DARK := Color(0.100, 0.250, 0.330)
## The lighter streak inside a canopy or bridge window.
const AUREL_GLASS := Color(0.330, 0.640, 0.780)
## The thin panel seams between plates.
const AUREL_SEAM := Color(0.070, 0.090, 0.120)
## The light of an Aurelian engine nozzle (warm white, like its flames).
const AUREL_GLOW := Color(1.0, 0.88, 0.64)
## The small running lights on the hull.
const AUREL_LIGHT := Color(1.0, 0.84, 0.5)

# --- the Vhorr dress of the structures (AurelianPaint.structure() draws it) ---------------------

## The plating of the Vhorr dress, darkest to lightest (a piece's "shade" number
## picks it): dark red-black, Cinder's gunmetal a touch lighter so it shows
## against the void, and a dark red-brown for the plates.
const VHORR_SHADES := [Color(0.055, 0.040, 0.050), Color(0.125, 0.080, 0.090), Color(0.21, 0.10, 0.11)]
## A dark slot or hatch in the Vhorr dress: nearly black.
const VHORR_DARK := Color(0.025, 0.017, 0.022)
## The glass of the Vhorr dress: one violet glow (the colour of a Vhorr ion lens).
const VHORR_GLASS := Color(0.59, 0.55, 0.92)
## The small running lights of the Vhorr dress: embers.
const VHORR_LIGHT := Color(0.96, 0.52, 0.38)
## The thin panel seams of the Vhorr dress: dark red.
const VHORR_SEAM := Color(0.34, 0.13, 0.12)

# --- turrets on the ships (TurretPaint draws them) --------------------------------------------

## The base of an Aurelian turret: dark steel, like a socket.
const TURRET_AUREL_BASE := Color(0.075, 0.095, 0.125)
## The cap on top of an Aurelian turret's base.
const TURRET_AUREL_CAP := Color(0.36, 0.43, 0.52)
## An Aurelian turret's barrels: bright steel, so they stand out on the hull.
const TURRET_AUREL_BARREL := Color(0.66, 0.72, 0.80)
## A Vhorr turret's barrels (fangs): dull red-brown bone.
const TURRET_CINDER_BARREL := Color(0.30, 0.21, 0.23)

# --- the hit flash (ShipVisual, UnitVisual and CinderPaint draw it) -----------------------

## How far (0 = not at all, 1 = all the way) the outline of a unit moves toward
## ICE, almost white, in the first moments after it was hit. Only the outline
## flashes; the unit's fill and plates keep their colours.
const HIT_FLASH := 0.8
## The same for a mothership, whose very long outline would glare if it flashed
## as hard as a ship's.
const HIT_FLASH_MOTHER := 0.4
## How much thicker a flashing outline is drawn at full strength: its width is
## multiplied by 1 + HIT_WIDTH_GAIN * strength, so even a thin line is seen to
## flash.
const HIT_WIDTH_GAIN := 1.2


## The colour of team `t`: amber for Aurelian, red for Vhorr, and the
## derelict grey-teal for anything else.
static func team(t: int) -> Color:
	if t == Rules.HALCYON:
		return AMBER
	if t == Rules.CINDER:
		return CINDER
	return DERELICT


## The menus' highlight colour for a human who plays for team `t`: the first
## line of the top-left panel, the pressed and chosen buttons, the selected
## tabs, the prices and the other marks that say "this one". Amber for Aurelian
## and for anything else (a spectator has no side, and gets amber), the vein red
## CINDER_VEIN for Vhorr. This is the only place that decides it. The colours
## with a fixed meaning (team colours, good news amber and bad news red, warnings,
## the health, shield and energy bars) do not use it. UiKit.accent() asks it
## for the side the interface is built for.
static func accent(t: int) -> Color:
	if t == Rules.CINDER:
		return CINDER_VEIN
	return AMBER


## The colour of team `t`'s shots: BOLT_H for Aurelian, BOLT_C for Vhorr,
## BOLT_N for anything else.
static func bolt(t: int) -> Color:
	if t == Rules.HALCYON:
		return BOLT_H
	if t == Rules.CINDER:
		return BOLT_C
	return BOLT_N


## A copy of colour `c` with see-through amount `a` (alpha: 0 = invisible,
## 1 = solid). The colour itself stays the same.
static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## The outline colour of a unit that was just hit: `edge` moved `flash` of the
## way toward ICE (the flash strength, HIT_FLASH or HIT_FLASH_MOTHER; 0 = not
## hit just now, so the colour stays as it is). Its see-through amount stays.
static func hit_edge(edge: Color, flash: float) -> Color:
	if flash <= 0.0:
		return edge
	var lit := edge.lerp(ICE, flash)
	lit.a = edge.a
	return lit


## The outline width of a unit that was just hit: `width` made thicker by the
## flash strength `flash` (see HIT_WIDTH_GAIN); unchanged when `flash` is 0.
static func hit_width(width: float, flash: float) -> float:
	return width * (1.0 + HIT_WIDTH_GAIN * flash)
