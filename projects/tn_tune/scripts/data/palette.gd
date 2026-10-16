class_name Palette
extends RefCounted
## WHAT THIS IS: the game's box of colours. Colours. Team colours: Halcyon
## amber, Cinder red, derelicts grey-teal. Every screen, ship and effect
## takes its colours from here, so the whole game looks like one piece.
##
## HOW IT WORKS: each constant is a Color(red, green, blue), where each part
## is a fraction from 0 (none) to 1 (full); Color(0, 0, 0) is black and
## Color(1, 1, 1) is white. A colour may have a fourth part, "alpha" (how
## see-through it is: 0 invisible, 1 solid); with_alpha() makes a copy with
## a chosen alpha. team() and bolt() pick a colour by team number.
##
## WHO USES IT: nearly everything that draws: the HUD and menus (UiKit,
## HudFeed, ShipStatus, Minimap, the hangar and the admiral board), the
## ship and unit pictures (ShipVisual, UnitVisual), the map (MapDecor,
## AsteroidField, ResourceNode, FogView) and the effects (Effects,
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

## Warm amber: Halcyon's team colour (also the menus' highlight colour).
const AMBER := Color(0.8863, 0.6314, 0.2902)
## Red: Cinder's team colour.
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
## Halcyon's shots (see bolt()).
const BOLT_H := Color(0.9490, 0.8431, 0.6353)
## Cinder's shots.
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


## The colour of team `t`: amber for Halcyon, red for Cinder, and the
## derelict grey-teal for anything else.
static func team(t: int) -> Color:
	if t == Rules.HALCYON:
		return AMBER
	if t == Rules.CINDER:
		return CINDER
	return DERELICT


## The colour of team `t`'s shots: BOLT_H for Halcyon, BOLT_C for Cinder,
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
