class_name MothershipRetreat
extends RefCounted
## WHAT THIS IS: the mothership's once-per-match emergency (DESIGN.md C11),
## a part of Mothership kept in its own file.
##
## HOW IT WORKS: the first time the hull is at or below 35% of its maximum
## (def "retreat_threshold"), the "retreat" game option decides what
## happens:
##   - "systems_failure" (the default): the hull is first raised back up to
##     35% if it fell lower; then for 45 s (def "retreat_time") pilots can't
##     launch, respawn or shop at the mothership, and its guns fire at half
##     speed. Mothership.failure_t counts down. The news feed says what
##     happened and a warning sound plays.
##   - "none": nothing happens (tests/ms_duel.gd uses it to measure the
##     mothership's raw strength; tests/endgame.gd can compare the two).
## It can never happen twice (Mothership.retreat_used). This is a "static
## library": it keeps no memory of its own; the timer lives on the
## Mothership.
##
## WHO USES IT: Mothership.sim_update() calls update() every tick. The HUD,
## the admiral's board, MinionDirector and TeamState read the timer
## (failure_t) on the Mothership; Mothership.available() turns it into
## "can pilots use the mothership now?".


## One tick of `dt` seconds of the emergency for `ms`: count down a systems
## failure, then check whether the emergency should start now.
static func update(ms: Mothership, dt: float) -> void:
	# Step 1: a systems failure counts down; say so when it ends.
	if ms.failure_t > 0.0:
		ms.failure_t = maxf(0.0, ms.failure_t - dt)
		if ms.failure_t == 0.0:
			Events.feed.emit("The %s mothership's systems are back online." % Rules.TEAM_DISPLAY[ms.team], "info", ms.team)
	# Step 2: should the emergency start now?
	check(ms)


## Start `ms`'s emergency if it hasn't been used yet and the hull is at or
## below the threshold (35%). See HOW IT WORKS above.
static func check(ms: Mothership) -> void:
	if ms.retreat_used:
		return
	if ms.hull > ms.hull_max * float(ms.def["retreat_threshold"]):
		return
	# Step 1: the "retreat" game option. "none" just uses it up.
	ms.retreat_used = true
	if Game.variant("retreat") == "none":
		return
	# Step 2: raise the hull back to the threshold and fail systems for a
	# while.
	ms.hull = maxf(ms.hull, ms.hull_max * float(ms.def["retreat_threshold"]))
	ms.failure_t = float(ms.def["retreat_time"])
	Events.feed.emit("The %s mothership's systems are failing: no launches or respawns there for %ds." % [Rules.TEAM_DISPLAY[ms.team], int(ms.failure_t)], "info", ms.team)
	# Step 3: a warning sound at the mothership.
	Events.cue.emit("warn", ms.global_position)
