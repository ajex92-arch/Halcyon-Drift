class_name BayBackFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "bayA" rule variant (the
## deep-dive option "bayA": repair bays placed further back). The AI admiral
## puts its repair bays 0.22 of the way down a lane instead of 0.33, where
## the first minion clash does not pass. In the AI deep dive the bays died
## after 154-189 s (20 of 23 killed by enemy minions); further back they
## lived about 300 s. Forward Redeploy (A2) and Bay shop (A6) both depend on
## bays that survive, so this is built as its own switch to screen them with
## and without it. REQ-CHANGE: none.
##
## HOW IT WORKS: --variant=bayA:on. AdmiralBuilder.place_bay() asks every
## feature that has a bay_spots() function for the list of places to try;
## this one answers with the same lanes at 0.22. Each repair bay launched
## while it is on is counted in Game.usage as "bays_placed_back" (a World
## tick hook watches the list of bays). When Forward Redeploy is also on and
## the team owns the Hyperspace Module, that feature (installed after this
## one) moves the push lane's bay to 0.5.
##
## WHO USES IT: FeatureRegistry installs it. AdmiralBuilder.place_bay() calls
## bay_spots(). World's tick_hooks call tick().

## The variant key this module belongs to.
const KEY := "bayA"
## Where along the lane (0..1, from the admiral's own end) bays go.
const BAY_FRAC := 0.22

## The running match.
var world: World
## The ids of the bays already counted: unit id -> true.
var _seen := {}


## Plug the feature into match `w`: only the counting hook is needed, the
## bay places are asked for on demand (bay_spots).
func install(w: World) -> void:
	world = w
	w.tick_hooks.append(tick)


## The tick hook (World.tick_hooks): count each new repair bay once.
func tick(_dt: float) -> void:
	for b in world.bays:
		if not _seen.has(b.uid):
			_seen[b.uid] = true
			Game.count_usage("bays_placed_back")


## The places to try for the next repair bay: the lanes of `spots`
## ([lane id, fraction] pairs) with every fraction changed to BAY_FRAC.
## The world, team and lane helper that the caller passes are not needed.
func bay_spots(_w: World, _team: int, spots: Array, _lanes: AdmiralLanes) -> Array:
	var out: Array = []
	for s: Array in spots:
		out.append([s[0], BAY_FRAC])
	return out
