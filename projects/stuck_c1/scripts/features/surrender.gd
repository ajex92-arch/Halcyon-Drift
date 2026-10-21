class_name SurrenderFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "surrender" rule variant: a
## surrender vote (docs/FUN_PLAN.md section 5, endgame_closure fork, idea B6).
## REQ-CHANGE: "only destroying the mothership should end the match". It ends
## hopeless matches early, the way a MOBA team votes to give up.
##
## HOW IT WORKS: the variant has one value besides "off" (the default):
##   "vote"   from 20:00 a team that is far behind may hold a vote, at most
##            one every 5 minutes. The vote is open for 30 s, then counted.
##            There are 13 seats per team (12 pilots and the admiral); the
##            vote passes at 80% of them (11 seats). EVERY AI seat votes by
##            the SAME rule, never keyed to its skill or to the scoring
##            probe: "yes" when its team has at least 6 fewer turrets alive
##            than the enemy AND at least 15 fewer pilot kills than the
##            enemy over the last 600 s (scoreboard numbers only). A human
##            seat on that team gets a prompt (a banner; F10 = yes, F11 =
##            no) and counts as one seat; with 12 AI seats saying yes a
##            single human cannot stop a vote that passes.
##            A passed vote ends the match as a loss for that team through
##            the same end path a mothership kill uses (the winner is set,
##            MatchRules' phase becomes "end", Events.match_over is sent) but
##            the reason line says it was a surrender. The fun probe prints
##            "ended_by": "surrender" instead of "mothership" (and leaves the
##            mothership-based endgame numbers null for such a match).
## The vote is held by the module itself (a tick hook, once a second), so the
## AI admiral and the pilots need no new rule. Counted in Game.usage:
## "surrender_votes" (votes opened), "surrenders" (votes that passed) and
## "surrender_loser_halcyon" / "surrender_loser_cinder" (who gave up). The
## module draws no random numbers.
##
## WHO USES IT: FeatureRegistry installs it for --variant=surrender:vote, runs
## it through World.tick_hooks and asks it for banner(). tests/fun_probe.gd
## reads Game.usage["surrenders"] for "ended_by".

## The variant key this module belongs to.
const KEY := "surrender"
## Match time (seconds) from which votes are allowed: 20:00.
const START_TIME := 1200.0
## Seconds between votes of one team: 5 minutes.
const COOLDOWN := 300.0
## Seconds a vote stays open.
const VOTE_TIME := 30.0
## Seats per team (12 pilots and 1 admiral).
const SEATS := 13
## The share of the seats that must vote yes (0.8 = 80%).
const PASS_SHARE := 0.8
## "Far behind", turrets: at least this many fewer turrets alive.
const TURRET_GAP := 6
## "Far behind", pilot kills: at least this many fewer over the window.
const KILL_GAP := 15
## The window (seconds) the pilot kills are counted over.
const KILL_WINDOW := 600.0

## The world we belong to.
var world: World
## Match time (seconds) when each team may open its next vote.
var next_vote := [START_TIME, START_TIME]
## Match time (seconds) when each team's open vote ends (0 = none open).
var vote_end := [0.0, 0.0]
## The human seat's vote on an open vote: 1 yes, -1 no, 0 none yet.
var human_vote := [0, 0]
## How many AI seats voted yes on each team's open vote (they all vote the
## moment it opens, by the same rule).
var ai_yes := [0, 0]
## Pilot kills, newest last: each entry [match time, killing team].
var _kills: Array = []
## Seconds until the next once-a-second check.
var _t := 0.0


## Switch the surrender vote on for match `w`. FeatureRegistry calls this
## once at match start. An unknown value only gets a warning.
func install(w: World) -> void:
	if Game.variant(KEY) != "vote":
		push_warning("surrender: unknown value \"%s\" (use off or vote); nothing changed" % Game.variant(KEY))
		return
	world = w
	Events.unit_killed.connect(_on_unit_killed)
	w.tick_hooks.append(_tick)


## A unit died (Events.unit_killed): remember pilot kills (a pilot ship of
## the other team made the last hit on a pilot ship), for the vote rule.
func _on_unit_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null or unit.kind != Unit.K_SHIP or d.source_profile == null:
		return
	var killer := d.source_profile as PilotProfile
	if killer != null and killer.team != unit.team and killer.team <= 1:
		_kills.append([world.time, killer.team])


## One tick (World.tick_hooks): read the human's keys while a vote is open,
## and once a second open or count votes.
func _tick(dt: float) -> void:
	for t in 2:
		if float(vote_end[t]) > 0.0 and world.human != null and world.human.team == t:
			if Input.is_physical_key_pressed(KEY_F10):
				human_vote[t] = 1
			elif Input.is_physical_key_pressed(KEY_F11):
				human_vote[t] = -1
	_t -= dt
	if _t > 0.0:
		return
	_t = 1.0
	for t in 2:
		if float(vote_end[t]) > 0.0:
			if world.time >= float(vote_end[t]):
				_count(t)
		elif world.time >= float(next_vote[t]) and _far_behind(t):
			_open(t)


## Does the AI seat rule say "yes" for team `t` right now? (The same answer
## for every AI seat of the team.)
func _far_behind(t: int) -> bool:
	var n := _numbers(t)
	return int(n[1]) - int(n[0]) >= TURRET_GAP and int(n[3]) - int(n[2]) >= KILL_GAP


## The scoreboard numbers the rule looks at, for team `t`: [our turrets
## alive, their turrets alive, our pilot kills, their pilot kills] (kills
## over the last 600 s).
func _numbers(t: int) -> Array:
	# Step 1: turrets alive (finished ones), for both teams.
	var mine := 0
	var theirs := 0
	for tu: Turret in world.turrets:
		if tu.alive and tu.is_built():
			if tu.team == t:
				mine += 1
			elif tu.team == 1 - t:
				theirs += 1
	# Step 2: pilot kills in the last 600 s, for both teams (drop old entries).
	while not _kills.is_empty() and world.time - float((_kills[0] as Array)[0]) > KILL_WINDOW:
		_kills.pop_front()
	var k := [0, 0]
	for e: Array in _kills:
		k[int(e[1])] += 1
	return [mine, theirs, int(k[t]), int(k[1 - t])]


## Open team `t`'s vote.
func _open(t: int) -> void:
	vote_end[t] = world.time + VOTE_TIME
	next_vote[t] = world.time + COOLDOWN
	human_vote[t] = 0
	# Every AI seat votes now, by the same rule (the human seat, if any, is
	# not an AI seat).
	var human := world.human != null and world.human.team == t
	ai_yes[t] = (SEATS - (1 if human else 0)) if _far_behind(t) else 0
	Game.count_usage("surrender_votes")
	Events.feed.emit("The %s fleet is voting on a surrender (%d s)." % [Rules.TEAM_NAMES[t], int(VOTE_TIME)], "info", -1)


## Count team `t`'s vote when it closes: the AI seats voted when it opened,
## the human seat (if any) has voted since.
func _count(t: int) -> void:
	vote_end[t] = 0.0
	# Step 1: the AI seats' votes, cast when the vote opened.
	var yes := int(ai_yes[t])
	var human := world.human != null and world.human.team == t
	# Step 2: the human seat votes for itself.
	if human and int(human_vote[t]) > 0:
		yes += 1
	if float(yes) < PASS_SHARE * float(SEATS):
		var n := _numbers(t)
		Events.feed.emit("The %s surrender vote failed (%d of %d seats; turrets %d-%d, pilot kills %d-%d)." % [Rules.TEAM_NAMES[t], yes, SEATS, n[0], n[1], n[2], n[3]], "info", -1)
		return
	# Step 3: it passed: the match ends as a loss for team t (the same steps
	# as MatchRules.on_mothership_destroyed, with a surrender message).
	if world.phase != "play":
		return
	Game.count_usage("surrenders")
	Game.count_usage("surrender_loser_halcyon" if t == Rules.HALCYON else "surrender_loser_cinder")
	var winner := 1 - t
	world.phase = "end"
	world.winner = winner
	var reason := "The %s fleet surrendered." % Rules.TEAM_NAMES[t]
	Events.feed.emit(reason, "info", -1)
	Events.match_over.emit(winner, reason)


## The HUD banner for the human on `team`: [] for none, else [title, sub,
## tone].
func banner(_w: World, team: int) -> Array:
	if float(vote_end[team]) > 0.0:
		return ["Surrender vote", "Our fleet is voting to surrender (%d s left). F10 = yes, F11 = no." % int(ceil(float(vote_end[team]) - world.time)), "cinder"]
	if float(vote_end[1 - team]) > 0.0:
		return ["Enemy surrender vote", "The %s fleet is voting to give up (%d s left)." % [Rules.TEAM_NAMES[1 - team], int(ceil(float(vote_end[1 - team]) - world.time))], "amber"]
	return []
