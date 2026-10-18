class_name ComebackDirector
extends RefCounted
## WHAT THIS IS: the "who is behind?" scorekeeper of the fork
## economy_comebacks. It keeps its OWN deficit number D for each team, built
## only from things on the scoreboard (turrets standing and pilot kills),
## and says when a team counts as "behind". The comeback bounties
## (ComebackBountiesFeature, idea C2) and the catch-up income (CatchupFeature,
## idea C6) both ask it, so they agree. It never looks at the fun probe's
## statistics.
##
## HOW IT WORKS: once a second update() works out, for each team:
##   D = (enemy turrets alive - our turrets alive)
##       + (enemy pilot kills - our pilot kills over the last 300 s) / 4
## A big D means that team is losing. From 14:00 (START_TIME), a team whose
## D stays at 3 or more (BEHIND_D) for 60 s (HOLD_TIME) is "behind", and it
## stays behind for 30 s (LINGER) after D falls under 3 again. Only one
## team can be behind at a time (D of one team is minus D of the other).
## The director is made once per match by ensure(), which also hooks it
## into the World's tick; it is kept in the World's meta "comeback_director".
## When `banner` is true, it also tells both teams in the news feed and on
## the gold banner when a team becomes behind, and draws a gold ring around
## the structures that pay extra (BountyRing).
##
## WHO USES IT: ComebackBountiesFeature and CatchupFeature call ensure().
## They read d[team], is_behind() and bounty_structures().

## Match time (seconds) before which nobody counts as behind: 14:00.
const START_TIME := 840.0
## A team's D must be at least this to start counting as behind.
const BEHIND_D := 3.0
## Seconds D must stay at BEHIND_D or more before the team is "behind".
const HOLD_TIME := 60.0
## Seconds a team stays "behind" after D drops under BEHIND_D.
const LINGER := 30.0
## Seconds of pilot kills that count in D.
const KILL_WINDOW := 300.0
## Pilot kills count this much (1 / 4) in D next to one turret.
const KILL_WEIGHT := 0.25

## The match.
var world: World
## The deficit D of each team (index = team). Updated once a second.
var d := [0.0, 0.0]
## Match time (seconds) since which a team's D has been at BEHIND_D or
## more without a break, or -1 when it is under.
var d_since := [-1.0, -1.0]
## Match time (seconds) until which a team counts as behind (-1 = not).
var behind_until := [-1.0, -1.0]
## Match times of the pilot kills BY each team (index = the killer's team),
## for the last KILL_WINDOW seconds.
var kill_log: Array = [[], []]
## True = tell the players (news line, banner, gold rings). Set by the
## bounty feature; the catch-up feature leaves it off.
var banner := false
## Seconds until the next once-a-second update.
var _timer := 0.0
## The gold rings (a BountyRing node), or null when there is no window or
## the banner is off.
var _ring: Node2D = null


## Get the match's director, making and installing it the first time.
## `w` is the match.
static func ensure(w: World) -> ComebackDirector:
	if w.has_meta("comeback_director"):
		return w.get_meta("comeback_director") as ComebackDirector
	var c := ComebackDirector.new()
	c.world = w
	w.set_meta("comeback_director", c)
	Events.unit_killed.connect(c._on_unit_killed)
	w.tick_hooks.append(c._tick)
	return c


## Turn on the news line, the banner and the gold rings (the bounty feature
## calls this).
func enable_banner() -> void:
	banner = true
	if _ring == null and DisplayServer.get_name() != "headless":
		var r := BountyRing.new()
		r.director = self
		_ring = r
		world.add_child(r)


## Is `team` behind right now (see HOW IT WORKS)?
func is_behind(team: int) -> bool:
	return team >= 0 and team < 2 and world.time < float(behind_until[team])


## The enemy structures (turrets and repair bays that are alive) that team
## `team` earns the comeback bounty for destroying: all of them while `team`
## is behind, none otherwise.
func bounty_structures(team: int) -> Array:
	var out: Array = []
	if not is_behind(team):
		return out
	for t: Turret in world.turrets:
		if t.alive and t.team == 1 - team:
			out.append(t)
	for b: RepairBay in world.bays:
		if b.alive and b.team == 1 - team:
			out.append(b)
	return out


## A unit died: if it was a pilot's ship killed by the other team's pilot,
## write down the kill time for that team.
func _on_unit_killed(unit: Node, info: RefCounted) -> void:
	var u := unit as Unit
	if u == null or u.kind != Unit.K_SHIP:
		return
	var killer := (info as DamageInfo).source_profile as PilotProfile
	if killer != null and killer.team != u.team and killer.team < 2:
		(kill_log[killer.team] as Array).append(world.time)


## World tick hook: run update() once a second.
func _tick(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 1.0
	update()


## Once a second: work out D for both teams and move the "behind" state on
## (see HOW IT WORKS).
func update() -> void:
	# Step 1: turrets standing, per team.
	var turrets := [0, 0]
	for t: Turret in world.turrets:
		if t.alive and t.team < 2:
			turrets[t.team] += 1
	# Step 2: forget kills older than the window.
	for team in 2:
		var times: Array = kill_log[team]
		while not times.is_empty() and world.time - float(times[0]) > KILL_WINDOW:
			times.pop_front()
	# Step 3: D, and the behind state, for each team.
	var was_behind := [is_behind(0), is_behind(1)]
	for team in 2:
		var e := 1 - team
		d[team] = float(int(turrets[e]) - int(turrets[team])) + float((kill_log[e] as Array).size() - (kill_log[team] as Array).size()) * KILL_WEIGHT
		if world.time >= START_TIME and float(d[team]) >= BEHIND_D:
			if float(d_since[team]) < 0.0:
				d_since[team] = world.time
			if world.time - float(d_since[team]) >= HOLD_TIME:
				behind_until[team] = world.time + LINGER
		else:
			d_since[team] = -1.0
	# Step 4: news line, banner and rings, when asked for. The news line is
	# sent when a team has just become behind.
	if banner:
		var text := ""
		var changed := false
		for team in 2:
			if is_behind(team):
				text = "COMEBACK BOUNTIES: %s are behind (D %.1f). Destroying enemy turrets and repair bays pays big." % [Rules.TEAM_NAMES[team], float(d[team])]
			if is_behind(team) != bool(was_behind[team]):
				changed = true
				if is_behind(team):
					Events.feed.emit("COMEBACK BOUNTY: the %s are far behind. Every enemy turret or repair bay they destroy now pays %d+ credits to the whole team." % [Rules.TEAM_NAMES[team], 600], "info", -1)
		EconBanner.set_line(world, "comeback", text)
		if changed and _ring != null:
			_ring.queue_redraw()