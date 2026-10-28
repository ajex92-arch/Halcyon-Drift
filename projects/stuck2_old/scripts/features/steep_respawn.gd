class_name SteepRespawnFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "respawn_curve" rule variant
## (idea A7 of the pacing_downtime fork): a steeper late respawn curve, like
## the long late-game death waits of League of Legends and Dota. DESIGN: the
## fun research rejected it (late dead share is already 16-25%), but it is
## built so the council can measure it anyway. Longer deaths should widen the
## push windows (S2/S3: final push, decided-to-end, lead changes), while
## the S4 "low downtime" score will fall and counts inside FUN.
##
## HOW IT WORKS: --variant=respawn_curve:steep. install() changes the three
## tuned numbers of the respawn wait (Rules.tune, read by MatchRules.
## respawn_time): "respawn_base" 6 s -> 8 s, "respawn_per_minute" 0.9 s ->
## 1.8 s per match minute, and "respawn_max" 50 s -> 90 s. A death at 10:00
## now waits 26 s (was 15); at 30:00 it waits 62 s (was 33); the cap of 90 s
## is reached at 45:00. Gear that shortens the wait still applies. The AI
## needs no rule of its own. A World tick hook counts, in Game.usage as
## "steep_respawns", every wait that is longer than the old 50 s cap.
##
## WHO USES IT: FeatureRegistry installs it. MatchRules.respawn_time() reads
## the tuned numbers through Rules.tune().

## The variant key this module belongs to.
const KEY := "respawn_curve"
## The new respawn wait at the start of the match (seconds).
const BASE := 8.0
## The new extra wait per minute of match time (seconds).
const PER_MINUTE := 1.8
## The new longest wait before gear (seconds).
const LONGEST := 90.0
## The old longest wait (seconds): a wait above it counts as a "steep respawn".
const OLD_CAP := 50.0

## The running match.
var world: World
## True for a pilot that was already dead on the previous tick (so a wait is
## counted once): PilotProfile -> bool.
var _was_dead := {}


## Change the three numbers for match `w` and start counting.
func install(w: World) -> void:
	world = w
	Game.tunables["respawn_base"] = BASE
	Game.tunables["respawn_per_minute"] = PER_MINUTE
	Game.tunables["respawn_max"] = LONGEST
	w.tick_hooks.append(tick)


## The tick hook (World.tick_hooks): count each new death whose wait is
## longer than the old cap.
func tick(_dt: float) -> void:
	for p: PilotProfile in world.profiles:
		if p.state == "dead":
			if not bool(_was_dead.get(p, false)):
				_was_dead[p] = true
				if p.respawn_t > OLD_CAP:
					Game.count_usage("steep_respawns")
		else:
			_was_dead[p] = false
