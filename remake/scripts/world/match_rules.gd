class_name MatchRules
extends RefCounted
## WHAT THIS IS: the referee of the match. It runs the respawn timers, the
## hyperspace launch countdowns, respawn strain, and the only way to win:
## destroying the enemy mothership. DESIGN.md A3, A12.
##
## HOW IT WORKS:
##   - When a pilot's ship dies, on_pilot_died() marks them "dead", takes
##     away the hull and modules they were flying, and starts a respawn
##     timer (respawn_time(): longer later in the match).
##   - Every tick, tick() counts down each dead pilot's timer. At zero the
##     pilot is back in the hangar ("docked"), gets the team's stipend if
##     there is one, and the respawn is counted for respawn strain (many
##     respawns in a short time slow the mothership's guns and stop its
##     shields recharging for a while; see TeamState.note_respawn). tick() also counts down hyperspace spools
##     and then launches the pilot.
##   - When a mothership is destroyed, on_mothership_destroyed() ends the
##     match: the other team wins.
##
## WHO USES IT: World makes one (World.rules) in WorldSetup and calls
## tick() every tick. WorldRegistry.remove() calls on_pilot_died() when a
## flying pilot's ship is removed; Mothership calls
## on_mothership_destroyed(). WorldHangar.hyperspace_launch() starts the
## spools that tick() finishes.

## The match we referee.
var world: World


## Remember the world. WorldSetup makes this once per match.
func _init(w: World) -> void:
	world = w


## How long (seconds) pilot `p` waits to respawn: 6 s plus 0.9 s for every
## minute of match time (Rules.RESPAWN_BASE, RESPAWN_PER_MINUTE), at most
## 50 s (RESPAWN_MAX); then multiplied by the pilot's gear "respawn_pct"
## multiplier, which counts as at least 0.3 (gear can cut the wait to 30%,
## no lower). Example: a death at 10:00 with no gear waits 6 + 9 = 15 s.
## (Playtest: late deaths cost real time so a won fight opens a push
## window; see Rules.RESPAWN_PER_MINUTE.) The three numbers are tuned
## numbers: a feature module may change them for one match
## ("respawn_base", "respawn_per_minute", "respawn_max"; Rules.tune).
func respawn_time(p: PilotProfile) -> float:
	# Step 1: the three numbers of the respawn curve (normally the Rules ones).
	var base := float(Rules.tune("respawn_base", Rules.RESPAWN_BASE))
	var per_minute := float(Rules.tune("respawn_per_minute", Rules.RESPAWN_PER_MINUTE))
	var longest := float(Rules.tune("respawn_max", Rules.RESPAWN_MAX))
	# Step 2: the wait grows with match time up to the cap, then gear cuts it.
	var t := base + per_minute * world.time / 60.0
	t = minf(t, longest)
	return t * maxf(0.3, p.gear_stats().mul("respawn_pct"))


## Called when pilot `p`'s ship dies: they are "dead", lose the hull and
## modules they flew, and start the respawn countdown.
func on_pilot_died(p: PilotProfile) -> void:
	p.state = "dead"
	p.ship = null
	p.hull_id = ""
	p.modules.clear()
	p.respawn_t = respawn_time(p)
	# An admiral shot down in their own ship is back in the chair at once.
	if p.role == "admiral":
		world.teams[p.team].admiral_docked = true


## Called by World every tick: count down hyperspace spools and respawn
## timers (see HOW IT WORKS at the top). `dt` is the tick in seconds.
func tick(dt: float) -> void:
	for p: PilotProfile in world.profiles:
		# Hyperspace spool: when it finishes, the pilot is docked for a
		# moment and launched at once, at the bay if it still lives
		# (otherwise launch() uses its normal spot).
		if p.state == "spooling":
			p.respawn_t -= dt
			if p.respawn_t <= 0.0:
				p.state = "docked"
				p.respawn_t = 0.0
				# Feature hook (Forward Redeploy): a jump to a bay or a
				# turret lands next to it (RedeployFeature.finish).
				if p.spool_site != null:
					(world.features["redeploy"] as RedeployFeature).finish(p)
					continue
				var bay := p.spool_bay
				p.spool_bay = null
				world.launch(p, bay if bay != null and is_instance_valid(bay) and bay.alive else null)
			continue
		# Only dead pilots count down; wait until the timer runs out.
		if p.state != "dead":
			continue
		p.respawn_t -= dt
		if p.respawn_t > 0.0:
			continue
		var ms: Mothership = world.mothership(p.team)
		# During a mothership outage pilots respawn at a repair bay if there
		# is one; with no bay either, check again in 1 s.
		if ms != null and not ms.available() and world.best_bay(p.team, ms.global_position) == null:
			p.respawn_t = 1.0
			continue
		# Back in the hangar: the stipend (if the team has one), the strain
		# count, and the "respawned" event for the screens.
		p.state = "docked"
		p.respawn_t = 0.0
		var ts: TeamState = world.teams[p.team]
		if ts.stipend > 0.0:
			p.earn(ts.stipend, "stipend")
		ts.note_respawn()
		Events.respawned.emit(p)


## Called by Mothership when mothership `ms` is destroyed: the other team
## wins and the match ends (only the first time; later calls do nothing).
## `_info` (the killing blow) is not used.
func on_mothership_destroyed(ms: Mothership, _info: DamageInfo) -> void:
	if world.phase != "play":
		return
	# Set the winner and stop the match (World's tick checks phase).
	var winner := Rules.enemy_of(ms.team)
	world.phase = "end"
	world.winner = winner
	# Announce it: a news-feed line and the match_over event.
	var reason := "The %s mothership was destroyed." % Rules.TEAM_NAMES[ms.team]
	Events.feed.emit(Rules.display_label(reason), "info", -1)
	Events.match_over.emit(winner, reason)
