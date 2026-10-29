class_name MutinyFeature
extends Node
## WHAT THIS IS: the feature module for the "mutiny" rule variant (fork
## admiral_command, idea F7 "Mutiny / admiral swap").
## REQ-CHANGE: the requirement "a player should be able to choose to be
## admiral ... not locked into" a role; this variant lets the pilots of a
## losing team vote the admiral out of the chair and take another seat. It
## only matters with a HUMAN admiral, so it is judged on paper plus the
## scripted test tests/admiral_fork_probe.gd (there is no screen for it).
##
## HOW IT WORKS:
##   - "Behind": once a second every team gets a lead number from the
##     scoreboard: (its live turrets - the enemy's) + 0.5 x (the enemy
##     ships destroyed in the last 5 minutes - ours). A team is "behind"
##     while the number is -3 or lower; the clock restarts when it climbs
##     above -1.5.
##   - A VOTE can be called after 15:00, when a team has been behind for 5
##     minutes (BEHIND_FOR), at most once per 5 minutes. Any pilot may call
##     it: the human pilot presses M; computer pilots call it by themselves
##     for a team that has no human pilot.
##   - Every pilot seat votes. A computer pilot votes yes when it has died
##     more often than it has killed, or when the team's treasury is at
##     least 2,500 (an admiral sitting on money). The human who called it
##     votes yes. With 8 of the 12 pilot seats (VOTES_NEEDED) in favour,
##     the vote passes.
##   - When it passes, the CHAIR goes to the pilot seat holding the most
##     credits and the old admiral takes that seat:
##       * a human admiral (Halcyon) becomes a pilot in that seat (same
##         lane role and seat number, and its credits), the computer pilot
##         who sat there leaves the team, and a computer admiral takes the
##         chair (the HUD follows World.human_role; the hangar opens);
##       * a computer admiral is replaced by a fresh computer admiral
##         (nothing else changes: there is no human to move).
##   - The result goes to the news feed for both teams (the "banner").
## Usage counters: mutiny_votes (votes called), mutiny_yes (yes votes cast),
## mutiny_swaps (votes that passed).
##
## WHO USES IT: FeatureRegistry installs it for --variant=mutiny:on (it is a
## Node, so it also gets the M key). The scripted test calls call_vote().

## The variant key this module belongs to.
const KEY := "mutiny"
## Match time (seconds) from which a vote may be called: 15:00.
const FROM := 900.0
## How long (seconds) a team must have been behind before a vote.
const BEHIND_FOR := 300.0
## The lead number at or below which a team is behind.
const LEAD_BEHIND := -3.0
## The lead number above which the "behind" clock restarts.
const LEAD_RECOVER := -1.5
## How far back (seconds) destroyed ships count for the lead number.
const DEATH_WINDOW := 300.0
## Seconds between two votes of one team.
const VOTE_GAP := 300.0
## Pilot seats in favour needed to pass (of 12).
const VOTES_NEEDED := 8
## A computer pilot votes yes when the treasury is at least this (credits).
const HOARD := 2500.0

## The match this module runs in.
var world: World
## Per team: the match times when its pilot ships were destroyed.
var deaths: Array = [[], []]
## Per team: the match time it became "behind" (-1 = not behind).
var behind_since: Array = [-1.0, -1.0]
## Per team: the match time of its last vote.
var last_vote: Array = [-99999.0, -99999.0]
## Per team: true once the human was told that a vote is possible.
var _told: Array = [false, false]
## Seconds until the next once-a-second look.
var _look_t := 1.0


## Plug the mutiny rules into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	Events.unit_killed.connect(_on_killed)
	tree_exiting.connect(func() -> void:
		if Events.unit_killed.is_connected(_on_killed):
			Events.unit_killed.disconnect(_on_killed))
	world.tick_hooks.append(_tick)


## The M key: the human pilot calls a mutiny vote for their team.
func _unhandled_key_input(event: InputEvent) -> void:
	if world == null or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	if (event as InputEventKey).keycode != KEY_M or world.human_role != "pilot" or world.human == null:
		return
	var why := call_vote(world.human.team, world.human)
	if why != "":
		Events.toast.emit(why)


## A unit died (Events.unit_killed): remember when a pilot ship dies.
func _on_killed(unit: Node, _info: RefCounted) -> void:
	var u := unit as Unit
	if u != null and u.kind == Unit.K_SHIP and u.team < 2:
		(deaths[u.team] as Array).append(world.time)


## The lead number of `team` (see HOW IT WORKS): turrets alive difference
## plus half the recent ship-loss difference (the enemy's losses minus ours).
func lead(team: int) -> float:
	var mine := 0
	var theirs := 0
	for tu: Turret in world.turrets:
		if tu.alive:
			if tu.team == team:
				mine += 1
			elif tu.team == 1 - team:
				theirs += 1
	var our_losses := _recent(team)
	var their_losses := _recent(1 - team)
	return float(mine - theirs) + 0.5 * float(their_losses - our_losses)


## How many pilot ships of `team` were destroyed in the last DEATH_WINDOW s.
func _recent(team: int) -> int:
	var n := 0
	for t in deaths[team]:
		if world.time - float(t) <= DEATH_WINDOW:
			n += 1
	return n


## The pilot seats of `team` (their profiles): the AI pilots and a human
## pilot, but not an admiral's own profile.
func seats(team: int) -> Array:
	var out: Array = []
	for p: PilotProfile in world.profiles:
		if p.team == team and p.role != "admiral":
			out.append(p)
	return out


## Why `team` can't hold a vote now, or "" if it can.
func vote_blocker(team: int) -> String:
	if world.time < FROM:
		return "A mutiny vote is possible after %s" % Util.clock(FROM)
	if behind_since[team] < 0.0 or world.time - float(behind_since[team]) < BEHIND_FOR:
		return "The team must be behind for %d minutes first" % int(BEHIND_FOR / 60.0)
	if world.time - float(last_vote[team]) < VOTE_GAP:
		return "A vote was held a moment ago"
	return ""


## Call a mutiny vote for `team`; `caller` is the pilot who calls it (it
## votes yes). Returns "" when the vote was held (whatever the result), or
## the reason it could not be held. The result goes to the news feed.
func call_vote(team: int, caller: PilotProfile) -> String:
	var why := vote_blocker(team)
	if why != "":
		return why
	last_vote[team] = world.time
	Game.count_usage("mutiny_votes")
	# Step 1: count the yes votes of all pilot seats.
	var all := seats(team)
	var yes := 0
	for p: PilotProfile in all:
		if p == caller or (not p.is_human and _ai_votes_yes(p, team)):
			yes += 1
	Game.count_usage("mutiny_yes", yes)
	# Step 2: the result, for both teams to read.
	if yes >= VOTES_NEEDED:
		Events.feed.emit("MUTINY! %d of %d %s pilots voted the admiral out." % [yes, all.size(), Rules.TEAM_NAMES[team]], "info", -1)
		swap(team)
	else:
		Events.feed.emit("The %s mutiny vote failed (%d of %d)." % [Rules.TEAM_NAMES[team], yes, all.size()], "info", -1)
	return ""


## Does the computer pilot `p` of `team` vote yes?
func _ai_votes_yes(p: PilotProfile, team: int) -> bool:
	return p.deaths > p.kills or world.teams[team].treasury >= HOARD


## The chair passes: see HOW IT WORKS. `team` is the team that voted.
func swap(team: int) -> void:
	var ts := world.teams[team]
	Game.count_usage("mutiny_swaps")
	# Step 1: the richest computer pilot seat.
	var rich: PilotProfile = null
	for p: PilotProfile in seats(team):
		if not p.is_human and (rich == null or p.credits > rich.credits):
			rich = p
	# Step 2: a human admiral takes that seat and a computer admiral the chair.
	if ts.admiral == "human" and world.human != null and world.human.team == team and world.human.role == "admiral" and rich != null:
		var ap := world.human
		ap.role = rich.role
		ap.slot = rich.slot
		ap.credits = rich.credits
		if rich.ship != null and is_instance_valid(rich.ship) and rich.ship.alive:
			world.combat.kill_silently(rich.ship)
		world.pilot_ai.erase(rich)
		world.profiles.erase(rich)
		ts.admiral = "ai"
		ts.admiral_docked = true
		world.admiral_ai[team] = AdmiralAI.new(world, team)
		world.human_role = "pilot"
		Events.toast.emit("You are now a pilot (seat %d). A computer admiral has the chair." % (ap.slot + 1))
		# The HUD opens the hangar when the human respawns as a pilot.
		Events.respawned.emit(ap)
	elif world.admiral_ai[team] != null:
		world.admiral_ai[team] = AdmiralAI.new(world, team)
	# Step 3: a fresh start for the "behind" clock.
	behind_since[team] = -1.0


## Every tick (a World.tick_hooks entry): once a second, update who is
## behind, tell the human pilot when a vote is possible, and let computer
## pilots call it for teams without a human pilot.
func _tick(dt: float) -> void:
	_look_t -= dt
	if _look_t > 0.0:
		return
	_look_t = 1.0
	for t in 2:
		# Step 1: the behind clock.
		var l := lead(t)
		if l <= LEAD_BEHIND and float(behind_since[t]) < 0.0:
			behind_since[t] = world.time
		elif l > LEAD_RECOVER:
			behind_since[t] = -1.0
			_told[t] = false
		if vote_blocker(t) != "":
			continue
		# Step 2: a human pilot calls it with M; computer pilots call it
		# themselves otherwise.
		if world.human_role == "pilot" and world.human != null and world.human.team == t:
			if not bool(_told[t]):
				_told[t] = true
				Events.toast.emit("Your team is far behind. Press M to call a mutiny vote against the admiral.")
		else:
			var caller: PilotProfile = null
			for p: PilotProfile in seats(t):
				if not p.is_human:
					caller = p
					break
			if caller != null:
				call_vote(t, caller)
