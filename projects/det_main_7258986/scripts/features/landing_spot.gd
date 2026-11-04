class_name LandingSpot
extends RefCounted
## WHAT THIS IS: a tiny helper for the features that put a ship down away
## from the mothership (Forward Redeploy and Respawn at a forward site): it
## finds a free spot at a given distance from a site.
##
## HOW IT WORKS: a "site" is a repair bay, a turret or a waypoint. We want
## the ship to appear `dist` world units from it, on the side that faces a
## point `toward` (the team's own mothership). A rock may be in the way, so
## find() tries that direction first and then turns away in steps of 40
## degrees (both ways) until the ship's circle fits between the rocks. If no
## direction fits, the first one is used anyway. It draws no random numbers.
##
## WHO USES IT: RedeployFeature.finish() and RespawnSiteFeature.

## The turn between two tried directions, in radians (40 degrees).
const STEP := 0.698
## How many directions are tried in all (the wanted one and then its
## neighbours on both sides, wrapping round the whole circle).
const TRIES := 9


## A free spot `dist` world units from `site` on the side facing `toward`,
## big enough for a ship of radius `radius` (world units). `world` is the
## match (it knows the rocks).
static func find(world: World, site: Vector2, toward: Vector2, dist: float, radius: float) -> Vector2:
	# Step 1: the wanted direction, then alternately 40 degrees to each side
	# of it (+40, -40, +80, -80, ...).
	var base := (toward - site).angle()
	var first := site + Vector2.from_angle(base) * dist
	for i in TRIES:
		var turn := STEP * float((i + 1) >> 1) * (1.0 if i % 2 == 1 else -1.0)
		var p := site + Vector2.from_angle(base + turn) * dist
		# Step 2: inside the map, and not touching a rock.
		if p.x < 200.0 or p.y < 200.0 or p.x > MapLayout.W - 200.0 or p.y > MapLayout.H - 200.0:
			continue
		if not world.asteroids.blocked(p, radius):
			return p
	return first
