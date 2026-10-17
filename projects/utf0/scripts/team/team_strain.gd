class_name TeamStrain
extends RefCounted
## WHAT THIS IS: the "respawn strain" rule. Bringing pilots back is hard
## work for a mothership: if Rules.STRAIN_RESPAWNS (4) pilots respawn
## within Rules.STRAIN_WINDOW (30 seconds), the mothership is strained for
## Rules.STRAIN_TIME (20 seconds). While strained, its guns are slowed and
## its shields stop recharging.
##
## HOW IT WORKS: note_respawn() writes down the match time of each pilot
## respawn (minions don't count) and forgets the ones older than 30 s.
## When 4 or more are left, strain is set to 20 s (or kept, if more than
## that is left). tick() counts it down to 0. The start is posted in the
## message feed. The Mothership reads TeamState.strain_t to slow its guns
## (Rules.STRAIN_WEAPON_MULT) and stop its shield regeneration.
##
## WHO USES IT: TeamState makes one (TeamState.strain), runs tick() every
## tick and forwards note_respawn() here. MatchRules calls
## TeamState.note_respawn() when a dead pilot is back in the hangar. The
## admiral board and the HUD top bar show TeamState.strain_t.

## The team this part belongs to (we read and set respawn_log and
## strain_t). It is reached through a weak link: see `_ts_ref`.
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A "weak" link to the team. TeamState holds this part with a normal
## (strong) link. If the part held the team strongly too, each would keep
## the other alive forever and Godot could never free them (a memory
## leak). A weak link points at the team without keeping it alive.
var _ts_ref: WeakRef


## Remember our team (through a weak link). TeamState makes this part once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)


## A pilot of ours just respawned. Write down the time, forget respawns
## older than the window, and start (or top up) strain if too many are
## left.
func note_respawn() -> void:
	# Step 1: add this respawn and keep only the ones inside the window.
	var now := ts.world.time
	ts.respawn_log.append(now)
	var keep: Array[float] = []
	for t: float in ts.respawn_log:
		if now - t < Rules.STRAIN_WINDOW:
			keep.append(t)
	ts.respawn_log = keep
	# Step 2: too many? Strain for at least STRAIN_TIME seconds, and
	# announce it only if we weren't strained already.
	if ts.respawn_log.size() >= Rules.STRAIN_RESPAWNS:
		var was := ts.strain_t > 0.0
		ts.strain_t = maxf(ts.strain_t, Rules.STRAIN_TIME)
		if not was:
			Events.feed.emit("Respawn strain: the %s mothership's guns are slowed and its shields stop recharging for %ds." % [Rules.TEAM_DISPLAY[ts.team], int(Rules.STRAIN_TIME)], "info", ts.team)


## Count strain down by one tick of `dt` seconds (never below 0).
func tick(dt: float) -> void:
	if ts.strain_t > 0.0:
		ts.strain_t = maxf(0.0, ts.strain_t - dt)
