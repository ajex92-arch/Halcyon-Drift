class_name HomeVisionFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "home_vision" rule variant (fork
## admiral_command, idea F6 "Defenders' home-field vision"). DESIGN: the
## research rejected it (it makes sieges, the weakest link of the game,
## harder), but it is measured anyway. It is a high-ground idea from other
## team games: defenders see better at home, attackers see worse there.
##
## HOW IT WORKS: a team's "home zone" is everything within 8,000 world units
## of its mothership's hull (HOME_RADIUS) plus everything within 3,500 of one
## of its inner turrets (TURRET_RADIUS; an inner turret stands at one of the
## three ore nodes next to its mothership). Through a World.vision_mods entry
## the fog of war then treats the units like this:
##   - a unit of the home team standing in its own home zone sees 1.25
##     times as far (HOME_MULT);
##   - an enemy PILOT SHIP standing in a team's home zone sees only 0.75 as
##     far (ENEMY_MULT);
##   - an enemy ward standing in a team's home zone gives no vision at all.
## The AI needs no change: its pilots and admiral read the same vision lists.
## Usage counter: home_vision_seconds, one for every second that an enemy
## pilot ship spends inside a home zone (counted once a second).
## Risk to watch in the screens: sieges and stalemates (final push, limbo).
##
## WHO USES IT: FeatureRegistry installs it for --variant=home_vision:on.
## WorldVisibility.viewers() runs the hook.

## The variant key this module belongs to.
const KEY := "home_vision"
## The home zone around a mothership's hull (world units).
const HOME_RADIUS := 8000.0
## The home zone around an inner turret (world units).
const TURRET_RADIUS := 3500.0
## Sight multiplier for the home team inside its own zone.
const HOME_MULT := 1.25
## Sight multiplier for an enemy pilot ship inside a home zone.
const ENEMY_MULT := 0.75

## The match this module runs in.
var world: World
## Seconds until the next once-a-second count.
var _count_t := 1.0


## Plug the vision hook and the counter into match `w` (FeatureRegistry
## calls this once).
func install(w: World) -> void:
	world = w
	world.vision_mods.append(_mod)
	world.tick_hooks.append(_tick)


## Is point `p` inside team `owner`'s home zone (see the top)?
func in_zone(owner: int, p: Vector2) -> bool:
	var ms := world.mothership(owner)
	if ms != null and ms.alive and ms.hull_dist(p) < HOME_RADIUS:
		return true
	for tu: Turret in world.turrets:
		if tu.team == owner and tu.alive and tu.node != null and tu.node.node_kind == "inner" and tu.global_position.distance_to(p) < TURRET_RADIUS:
			return true
	return false


## The vision hook (World.vision_mods): unit `u` of `team` would see `r`
## world units far; give back the radius after the home-field rules.
func _mod(team: int, u: Unit, r: float) -> float:
	var p := u.global_position
	# A friendly unit at home sees farther.
	if in_zone(team, p):
		r *= HOME_MULT
	# An enemy pilot ship in the other team's zone sees less, and an enemy
	# ward there sees nothing.
	if u.kind == Unit.K_SHIP or u.kind == Unit.K_WARD:
		if in_zone(1 - team, p):
			if u.kind == Unit.K_WARD:
				return 0.0
			r *= ENEMY_MULT
	return r


## Every tick (a World.tick_hooks entry): once a second, count the enemy
## pilot ships that stand inside a home zone.
func _tick(dt: float) -> void:
	_count_t -= dt
	if _count_t > 0.0:
		return
	_count_t = 1.0
	for s: Ship in world.ships:
		if s.alive and in_zone(1 - s.team, s.global_position):
			Game.count_usage("home_vision_seconds")
