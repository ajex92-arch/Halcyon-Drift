class_name MinionShapes
extends RefCounted
## WHAT THIS IS: the Aurelian (amber) pictures of the three lane minions: the
## Snub-Fighter (type "fighter"), the Light Bomber ("bomber") and the Patrol
## Leader ("corvette"). They are pictures only: hit circles, sizes and every
## number stay as they are in minions.gd, and the match plays exactly as before.
##
## HOW IT WORKS: each outline is a list of corner points, nose pointing right
## (+x) and +y the minion's right side, about one unit long and wide: UnitVisual
## scales it by the minion's size. A minion is meant to read as the basic kind
## of ship and never to be mistaken for a pilot ship (ShipVisual.HULLS), so:
##   - each is one plain plate of 3 to 6 corners with a flat tail: no notch, no
##     swept wings, no point on the tail. A pilot hull is a dart or a hexagon
##     with a notched or pointed tail;
##   - UnitVisual fills it solid, with the team colour mixed into the hull
##     colour (FILL_MIX), where a pilot ship is a dark hull seen through its
##     outline, and draws the outline a little bolder (EDGE_PX);
##   - the Vhorr (Cinder) minions follow the same rule in their own alien style
##     (CinderShapes.MINIONS): smooth, soft shells with one engine light, no
##     horns, claws or plates, and a solid body colour.
## When the pilot ships are redrawn, keep their noses pointed and their tails
## notched or pointed, and leave these outlines as they are:
## tests/lib/gallery_checks.gd checks the corner count and the flat tail of each.
##
## WHO USES IT: UnitVisual draws them for a minion of the Aurelian team (and of
## either team inside the hull gallery's plain look); the hull gallery
## (tests/hull_gallery.gd, tests/lib/gallery_checks.gd) sizes its pictures by
## them and checks the Cinder shells against them.

## The outlines: minion type id -> corner points (nose right, unit space). The
## Snub-Fighter is a short wedge with a flat, blunt nose, the Light Bomber a
## squat box with its nose corners cut off, the Patrol Leader a plain triangle.
const AURELIAN := {
	"fighter": [Vector2(1, 0.3), Vector2(-0.6, 0.55), Vector2(-0.6, -0.55), Vector2(1, -0.3)],
	"bomber": [Vector2(0.95, 0.28), Vector2(0.6, 0.5), Vector2(-0.8, 0.5), Vector2(-0.8, -0.5), Vector2(0.6, -0.5), Vector2(0.95, -0.28)],
	"corvette": [Vector2(1, 0), Vector2(-0.9, 0.58), Vector2(-0.9, -0.58)],
}
## How much of the team colour is mixed into the dark hull colour for a minion's
## fill: 0 = a pilot ship's dark hull, 1 = the team colour itself.
const FILL_MIX := 0.32
## The width of a minion's outline in screen pixels (a pilot ship's is 1.4).
const EDGE_PX := 1.3


## The outline of minion type `type_id` ("fighter" for an unknown type).
static func aurelian(type_id: String) -> Array:
	return AURELIAN.get(type_id, AURELIAN["fighter"])
