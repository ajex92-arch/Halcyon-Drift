class_name SizeRespawnFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "respawn" rule variant (idea A4
## of the pacing_downtime fork): "Size-scaled respawn". A pilot who loses a
## small ship waits less to respawn than one who loses a battlecruiser, so
## strike-craft pilots spend less of the match dead.
##
## HOW IT WORKS: --variant=respawn:size. The normal wait (MatchRules.
## respawn_time: 6 s plus 0.9 s per match minute, at most 50 s, then the
## pilot's "respawn_pct" gear) is multiplied by SIZE_RESPAWN for the hull
## that was lost: small 0.6, medium 0.85, large 1.1, capital 1.3. The cap
## scales the same way (50 x 0.6 = 30 s for a strike craft, 65 s for a
## capital ship) and the gear still applies. A strike-craft death at 40:00
## waits about 25 s instead of 42. The respawn strain count
## (TeamState.note_respawn) is unchanged.
## MatchRules clears the pilot's hull when the ship dies, so this module
## watches the pilots on a World tick hook: while a pilot flies it
## remembers the hull's size class; the first tick the pilot is seen "dead"
## (that is the tick of its death) it multiplies `respawn_t`, the pilot's
## countdown, by the factor for the remembered size. The AI needs no rule of
## its own. Usage: "size_respawns" in Game.usage counts every scaled wait.
## REQ-CHANGE: none.
##
## WHO USES IT: FeatureRegistry installs it. World's tick_hooks call tick().

## The variant key this module belongs to.
const KEY := "respawn"
## The wait multiplier by hull size class: small, medium, large, capital.
const SIZE_RESPAWN := [0.6, 0.85, 1.1, 1.3]

## The running match.
var world: World
## The size index (0..3) of the hull each pilot flew last: PilotProfile ->
## int.
var _last_size := {}
## True for a pilot that was already dead on the previous tick (so its wait
## is scaled only once): PilotProfile -> bool.
var _was_dead := {}


## Plug the feature into match `w`.
func install(w: World) -> void:
	world = w
	w.tick_hooks.append(tick)


## The tick hook (World.tick_hooks): remember each flying pilot's hull size
## and scale the wait of each pilot that has just died.
func tick(_dt: float) -> void:
	for p: PilotProfile in world.profiles:
		if p.state == "flying" and p.ship != null and is_instance_valid(p.ship):
			_last_size[p] = Rules.size_index(p.ship.size_class)
			_was_dead[p] = false
		elif p.state == "dead":
			if not bool(_was_dead.get(p, false)):
				_was_dead[p] = true
				p.respawn_t *= float(SIZE_RESPAWN[int(_last_size.get(p, 0))])
				Game.count_usage("size_respawns")
		else:
			_was_dead[p] = false
