extends Node
## WHAT THIS IS: the "difficulty probe": a measuring tool for a match where one
## human sits in a seat against the AI. It follows the money both teams earn,
## source by source, and the ships both teams field, so the effect of the
## difficulty setting (a multiplier on the enemy team's income) can be read off
## and checked. It answers: how many credits did each team's pilots earn from
## each source (minion last hits, kills, assists, jungle monsters, turrets, ore,
## the steady trickle ...), how much did each treasury earn (the mothership's
## own income, the ore share, destroyed turrets and repair bays), which ships
## did each team have in space at minutes 5 to 30, and when did each team's
## first destroyer and first battlecruiser appear?
##
## HOW IT WORKS: it listens to the game's own messages and reads the match. Every
## payment to a pilot (Events.credits_earned) is added up by the pilot's team and
## the reason the game gave. The steady trickle sends no message, so it is
## checked tick by tick instead: what a pilot's "earned" total grew by, minus
## the payments of that tick, must equal the trickle the rules promise times the
## multiplier the probe expects for that team. A treasury is checked as a whole:
## what it earned is its balance change plus everything spent from it
## (TeamState.spend_hook), and that is compared with the income worked out from
## the rules at the normal rate (the mothership's income for every tick it lives,
## the treasury's share of the ore delivered, a tuned amount for each enemy turret
## and repair bay destroyed). That comparison is the multiplier the treasury got:
## 1.0 for the human's team, the difficulty's number for the enemy. The probe
## counts the ships in space every tick (the first time each hull appears) and at
## the snapshot minutes, and prints one "DIFFICULTY_PROBE_JSON {...}" line at the end
## (--secs, or when a mothership dies) and quits.
##
## It only reads the game and draws no random numbers, so the match plays exactly
## as without it. The one exception is the option --bank, which gives everybody a
## huge purse on purpose: see below.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/; --auto --role=pilot puts a human in the pilot seat, who
## launches a Fighter and then sits still; a plain all-AI run has no human, so no
## difficulty applies):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --seed=7 --skill-jitter --sim-only --test=difficulty_probe --secs=1800
## Options of the probe:
##   --secs=N         how many game seconds to watch (default 1800).
##   --difficulty=X   read by the game (a build without it ignores the word).
##   --bank[=N]       before the match starts, add N credits (default 1,000,000)
##                    to every pilot and to both treasuries. With that much money
##                    the AI's buying decisions (all "can I afford it" tests)
##                    come out the same at every difficulty, so the five levels
##                    play the same match and their payments can be compared one
##                    by one. The bank is not earned money, so it stays out of
##                    the "earned" totals.
##   --events=<file>  also write every pilot payment to this file, one line each:
##                    time, team, seat, reason, amount (tab separated).
##
## HOW TO READ THE OUTPUT: DIFFICULTY_PROBE_JSON holds "level" (the difficulty the game
## reports), "expect" (the enemy multiplier the probe expects), "human_team" (-1
## = no human), "seconds", "ended_early", "winner", and "team": two entries
## (0 = Aurelian, 1 = Vhorr) each with
##   "pilots"        "credits" and "payments" per reason, "events_total",
##                   "earned_total", "trickle" (earned_total - events_total);
##   "trickle_check" "ticks" checked, "bad" ticks off by more than the tolerance,
##                   "max_err" (credits) and "expected" (credits of trickle);
##   "treasury"      "start", "end", "spent", "income" (end - start + spent),
##                   "base" (the income at the normal rate, per source),
##                   "base_total" and "ratio" (income / base_total);
##   "credits_by_minute"  the payments per reason, one number per match minute;
##   "series"        one point per match minute: the treasury, the pilots' average
##                   purse, the credits spent from the treasury, the ships in space
##                   and how many of them are capital ships;
##   "snapshots"     at minutes 5, 10 ... the ships by hull and by size class, the
##                   treasury, the pilots' credits and the facilities and research
##                   done so far;
##   "first_seen" and "peak"  per hull: when the first one flew, and the most at once;
##   "unlocks"       when each facility and research finished (seconds);
##   "game_mult"     the multipliers the game itself holds for the team's pilots
##                   and treasury (null in a build without them).
##
## WHO USES IT: main.gd loads it for --test=difficulty_probe. A script outside the
## game (the lead's tools) turns the DIFFICULTY_PROBE_JSON lines of several builds and levels
## into the comparison tables.

## Game time (seconds) to watch for when --secs is not given.
const DEFAULT_SECS := 1800.0
## The multiplier the probe expects for the enemy team at each difficulty level
## (Difficulty in the game). It is written out again here on purpose, so the probe
## checks the game's numbers instead of copying them.
const EXPECTED := {"easy": 0.75, "medium": 1.0, "hard": 1.25, "very_hard": 1.5, "extreme": 2.0}
## The match minutes at which the fleets and the treasuries are written down.
const SNAP_MINUTES := [5, 10, 15, 20, 25, 30]
## The names of the four size classes of Ships.HULLS (its "size" field, 0 to 3).
const SIZE_NAMES := ["small", "medium", "large", "capital"]
## A trickle error smaller than this many credits in one tick is float noise,
## not a wrong multiplier.
const TOLERANCE := 1e-7
## The purse --bank gives when no number is given, in credits.
const DEFAULT_BANK := 1000000.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := DEFAULT_SECS
## The difficulty the game reports ("" when the build has none).
var level := ""
## The income multiplier the probe expects for the enemy team (1.0 with no human).
var expect := 1.0
## The team of the human seat (0 = Aurelian), or -1 when nobody is human.
var human_team := -1
## Credits added to every pilot and both treasuries at the start (--bank).
var bank := 0.0
## The open --events file, or null.
var _events: FileAccess = null
## True once the final line is printed, so it is printed only once.
var _done := false
## The match clock (seconds) at the last tick that was counted.
var _last_time := 0.0
## The next match minute at which a point of the series is written.
var _next_point := 1
## Per team: one point per match minute, {"m": minute, "treasury": credits,
## "avg_credits": the pilots' average, "spent": credits spent from the treasury
## so far, "ships": ships in space, "capital": capital ships in space}.
var _series: Array = [[], []]
## Credits paid with a message, per team: team -> reason -> credits.
var _credits: Array = [{}, {}]
## Payments with a message, per team: team -> reason -> count.
var _payments: Array = [{}, {}]
## The payments per match minute, per team: team -> reason -> [credits in
## minute 0, minute 1 ...].
var _by_minute: Array = [{}, {}]
## What the payments of the current tick add up to, per pilot: PilotProfile ->
## credits. Emptied at the end of each tick.
var _tick_events := {}
## Each pilot's "earned" total at the end of the previous tick: PilotProfile -> credits.
var _prev_earned := {}
## Per team: how many pilot-ticks of the trickle were checked.
var _trickle_ticks: Array = [0, 0]
## Per team: how many of them were off by more than TOLERANCE.
var _trickle_bad: Array = [0, 0]
## Per team: the largest error found, in credits.
var _trickle_err: Array = [0.0, 0.0]
## Per team: the trickle the rules promise in all, in credits.
var _trickle_want: Array = [0.0, 0.0]
## Credits spent from each treasury (counted by TeamState.spend_hook).
var _spent: Array = [0.0, 0.0]
## Whether the spend counter of each treasury is ours (false when a feature
## module already holds the hook; the treasury income is then not worked out).
var _spend_tracked: Array = [false, false]
## Each treasury's balance when the watching began.
var _treasury_start: Array = [0.0, 0.0]
## Each treasury's income at the normal rate, per source: team -> {"skim", "ore",
## "turret", "bay"} -> credits.
var _base: Array = [{"skim": 0.0, "ore": 0.0, "turret": 0.0, "bay": 0.0}, {"skim": 0.0, "ore": 0.0, "turret": 0.0, "bay": 0.0}]
## How many enemy turrets each team destroyed (each pays that team's treasury).
var _turrets_by: Array = [0, 0]
## How many enemy repair bays each team destroyed (each pays that team's treasury).
var _bays_by: Array = [0, 0]
## Each team's ore delivered at the end of the previous tick.
var _ore_prev: Array = [0.0, 0.0]
## Whether each team's mothership was alive at the end of the previous tick.
var _ms_alive: Array = [true, true]
## The snapshots, by minute (as text): minute -> [team 0's, team 1's].
var _snaps := {}
## Which of SNAP_MINUTES comes next.
var _next_snap := 0
## Per team: hull id -> game time (seconds) when the first ship of that hull flew.
var _first_seen: Array = [{}, {}]
## Per team: hull id -> the most ships of that hull in space at once.
var _peak: Array = [{}, {}]


## main.gd calls this once, right after the World is built. Read the options,
## note who is human, give the bank if asked, and start listening.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", DEFAULT_SECS))
	# Step 1: who is human, which difficulty the game reports (a build without a
	# difficulty has no such property: get() gives null), and what the enemy's
	# multiplier should then be.
	if world.human != null:
		human_team = world.human.team
	var shown = Game.get("difficulty")
	level = str(shown) if shown != null else ""
	expect = float(EXPECTED.get(level, 1.0)) if human_team >= 0 else 1.0
	# Step 2: --bank: the same huge purse for everybody.
	var bank_opt = Game.opt("bank")
	if bank_opt != null:
		bank = DEFAULT_BANK if bank_opt is bool else float(bank_opt)
	if bank > 0.0:
		for p: PilotProfile in world.profiles:
			p.credits += bank
		for t in 2:
			world.teams[t].treasury += bank
	# Step 3: the starting figures, and the spend counters on both treasuries.
	for p: PilotProfile in world.profiles:
		_prev_earned[p] = p.earned
	for t in 2:
		var ts: TeamState = world.teams[t]
		_treasury_start[t] = ts.treasury
		_ore_prev[t] = ts.ore_delivered
		if not ts.spend_hook.is_valid():
			var team := t
			ts.spend_hook = func(amount: float) -> void: _spent[team] += amount
			_spend_tracked[t] = true
	# Step 4: listen, and open the --events file if there is one.
	Events.credits_earned.connect(_on_credits)
	Events.unit_killed.connect(_on_killed)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	var path := str(Game.opt("events", ""))
	if path != "":
		_events = FileAccess.open(path, FileAccess.WRITE)


## A pilot was paid: add it to its team's sums by reason, to the minute column,
## to this tick's payments, and to the --events file.
func _on_credits(profile: RefCounted, amount: float, reason: String) -> void:
	var p := profile as PilotProfile
	if p == null:
		return
	var c: Dictionary = _credits[p.team]
	c[reason] = float(c.get(reason, 0.0)) + amount
	var n: Dictionary = _payments[p.team]
	n[reason] = int(n.get(reason, 0)) + 1
	var minute := int(world.time / 60.0)
	var col: Array = (_by_minute[p.team] as Dictionary).get(reason, [])
	while col.size() <= minute:
		col.append(0.0)
	col[minute] = float(col[minute]) + amount
	_by_minute[p.team][reason] = col
	_tick_events[p] = float(_tick_events.get(p, 0.0)) + amount
	if _events != null:
		_events.store_line("%.4f\t%d\t%d\t%s\t%.12f" % [world.time, p.team, p.slot, reason, amount])


## Something died. A destroyed repair bay pays the other team's treasury
## (Economy.on_unit_killed), so note the normal amount for that team.
func _on_killed(u: Node, _info: RefCounted) -> void:
	var unit := u as Unit
	if unit == null or unit.kind != Unit.K_BAY:
		return
	var by_team := Rules.enemy_of(unit.team)
	if by_team < 0:
		return
	_base[by_team]["bay"] += float(Rules.tune("bay_treasury", Rules.BAY_TREASURY))
	_bays_by[by_team] += 1


## A turret was destroyed by team `by_team`, whose treasury is paid for it:
## note the normal amount.
func _on_turret_destroyed(_turret: Node, by_team: int) -> void:
	if by_team < 0 or by_team > 1:
		return
	_base[by_team]["turret"] += float(Rules.tune("turret_treasury", Rules.TURRET_TREASURY))
	_turrets_by[by_team] += 1


## Every tick (after the World's own tick): when the World ticked this frame,
## check the trickle, the treasuries and the fleets; then stop at the end time
## or when the match is over. (The World does not tick once the match is over,
## so a frame in which the clock did not move has nothing to count.)
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	if world.time > _last_time:
		_last_time = world.time
		_check_trickle(dt)
		_track_treasury(dt)
		_track_fleets()
		_track_series()
		_tick_events.clear()
	if world.time >= secs or world.phase != "play":
		_finish()


## Check the steady trickle of this tick for every pilot: the growth of "earned"
## minus this tick's payments must be (trickle rate + the pilot's gear income)
## x dt x the multiplier the probe expects for the pilot's team.
func _check_trickle(dt: float) -> void:
	var rate := float(Rules.tune("passive_income", Rules.PASSIVE_INCOME))
	for p: PilotProfile in world.profiles:
		if not _prev_earned.has(p):
			_prev_earned[p] = p.earned
			continue
		var mult := expect if (human_team >= 0 and p.team != human_team) else 1.0
		var got: float = p.earned - float(_prev_earned[p]) - float(_tick_events.get(p, 0.0))
		var want: float = (rate + p.gear_stats().g("income")) * dt * mult
		_prev_earned[p] = p.earned
		var t := p.team
		_trickle_ticks[t] += 1
		_trickle_want[t] += want
		var err := absf(got - want)
		_trickle_err[t] = maxf(float(_trickle_err[t]), err)
		if err > TOLERANCE:
			_trickle_bad[t] += 1


## Work out each treasury's income at the normal rate for this tick: the
## mothership's income if it was alive, and the treasury's share of the ore
## delivered since the last tick. (Turrets and repair bays are added by the
## death messages.)
func _track_treasury(dt: float) -> void:
	var skim := float(Rules.tune("mothership_skim", Rules.MOTHERSHIP_SKIM))
	var share := float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))
	for t in 2:
		var ts: TeamState = world.teams[t]
		if _ms_alive[t]:
			_base[t]["skim"] += skim * dt
		var ore: float = ts.ore_delivered
		_base[t]["ore"] += (ore - float(_ore_prev[t])) * share
		_ore_prev[t] = ore
		var ms := world.mothership(t)
		_ms_alive[t] = ms != null and ms.alive


## Count the ships in space: note the first time each hull flew for a team and
## the most of it at once, and write the snapshot when a snapshot minute comes.
func _track_fleets() -> void:
	var counts: Array = [{}, {}]
	for s: Ship in world.ships:
		if not s.alive or s.team > 1:
			continue
		var d: Dictionary = counts[s.team]
		d[s.hull_id] = int(d.get(s.hull_id, 0)) + 1
	for t in 2:
		var d: Dictionary = counts[t]
		for h: String in d:
			if not (_first_seen[t] as Dictionary).has(h):
				_first_seen[t][h] = snappedf(world.time, 0.01)
			if int(d[h]) > int((_peak[t] as Dictionary).get(h, 0)):
				_peak[t][h] = int(d[h])
	if _next_snap < SNAP_MINUTES.size() and world.time >= float(SNAP_MINUTES[_next_snap]) * 60.0:
		_snapshot(int(SNAP_MINUTES[_next_snap]))
		_next_snap += 1


## Once per match minute, add a point to each team's series (see _series): how
## the treasury, the pilots' purse and the fleet grow. It shows whether a team
## spends its money or lets it pile up.
func _track_series() -> void:
	if world.time < float(_next_point) * 60.0:
		return
	for t in 2:
		var ts: TeamState = world.teams[t]
		var purse := 0.0
		var seats := 0
		for p: PilotProfile in world.profiles:
			if p.team == t:
				purse += p.credits
				seats += 1
		var ships := 0
		var capital := 0
		for s: Ship in world.ships:
			if s.team == t and s.alive:
				ships += 1
				if int(Ships.HULLS[s.hull_id]["size"]) == 3:
					capital += 1
		(_series[t] as Array).append({"m": _next_point, "treasury": snappedf(ts.treasury, 0.01), "avg_credits": snappedf(purse / float(maxi(1, seats)), 0.01),
				"spent": snappedf(float(_spent[t]), 0.01), "ships": ships, "capital": capital})
	_next_point += 1


## Write down both teams' fleets (ships in space by hull and by size class),
## treasuries, pilot credits and tech progress at match minute `minute`.
func _snapshot(minute: int) -> void:
	var snap := []
	for t in 2:
		var ts: TeamState = world.teams[t]
		var ships := {}
		var sizes := {}
		for s: Ship in world.ships:
			if s.team != t or not s.alive:
				continue
			ships[s.hull_id] = int(ships.get(s.hull_id, 0)) + 1
			var cls := str(SIZE_NAMES[int(Ships.HULLS[s.hull_id]["size"])])
			sizes[cls] = int(sizes.get(cls, 0)) + 1
		var purse := 0.0
		for p: PilotProfile in world.profiles:
			if p.team == t:
				purse += p.credits
		var turrets := 0
		for tu: Turret in world.turrets:
			if tu.team == t and tu.alive:
				turrets += 1
		snap.append({"ships": ships, "sizes": sizes, "treasury": snappedf(ts.treasury, 0.01), "pilot_credits": snappedf(purse, 0.01),
				"spent": snappedf(float(_spent[t]), 0.01), "facilities": ts.facilities.size(), "research": ts.done.size(), "turrets": turrets})
	_snaps[str(minute)] = snap


## One team's numbers for the JSON line (see HOW TO READ THE OUTPUT).
func _team_report(t: int) -> Dictionary:
	var ts: TeamState = world.teams[t]
	# Step 1: the pilots' payments and totals.
	var credits := {}
	var events_total := 0.0
	for r: String in _credits[t]:
		credits[r] = snappedf(float(_credits[t][r]), 0.01)
		events_total += float(_credits[t][r])
	var earned_total := 0.0
	var seats := 0
	var kills := 0
	var deaths := 0
	var last_hits := 0
	var mult_seen = null
	for p: PilotProfile in world.profiles:
		if p.team != t:
			continue
		seats += 1
		earned_total += p.earned
		kills += p.kills
		deaths += p.deaths
		last_hits += p.minion_kills
		if mult_seen == null:
			mult_seen = p.get("income_mult")
	# Step 2: the treasury: income from the balance, and at the normal rate.
	var base := {}
	var base_total := 0.0
	for k: String in _base[t]:
		base[k] = snappedf(float(_base[t][k]), 0.01)
		base_total += float(_base[t][k])
	var income = null
	var ratio = null
	if _spend_tracked[t]:
		income = ts.treasury - float(_treasury_start[t]) + float(_spent[t])
		if base_total > 0.0:
			ratio = snappedf(float(income) / base_total, 0.000001)
		income = snappedf(float(income), 0.01)
	# Step 3: the payments per minute, rounded.
	var by_minute := {}
	for r: String in _by_minute[t]:
		var rounded := []
		for v in (_by_minute[t][r] as Array):
			rounded.append(snappedf(float(v), 0.01))
		by_minute[r] = rounded
	var snaps := {}
	for m: String in _snaps:
		snaps[m] = _snaps[m][t]
	return {"seats": seats, "kills": kills, "deaths": deaths, "last_hits": last_hits,
			"pilots": {"credits": credits, "payments": (_payments[t] as Dictionary).duplicate(), "events_total": snappedf(events_total, 0.01),
					"earned_total": snappedf(earned_total, 0.01), "trickle": snappedf(earned_total - events_total, 0.01)},
			"trickle_check": {"ticks": _trickle_ticks[t], "bad": _trickle_bad[t], "max_err": _trickle_err[t], "expected": snappedf(float(_trickle_want[t]), 0.01)},
			"treasury": {"start": snappedf(float(_treasury_start[t]), 0.01), "end": snappedf(ts.treasury, 0.01), "spent": snappedf(float(_spent[t]), 0.01),
					"income": income, "base": base, "base_total": snappedf(base_total, 0.01), "ratio": ratio, "turrets_destroyed": _turrets_by[t],
					"bays_destroyed": _bays_by[t], "ore_delivered": snappedf(ts.ore_delivered, 0.01)},
			"credits_by_minute": by_minute, "series": _series[t], "snapshots": snaps, "first_seen": _first_seen[t], "peak": _peak[t],
			"unlocks": ts.unlock_times.duplicate(),
			"game_mult": {"pilots": mult_seen, "treasury": ts.get("income_mult")}}


## Print the DIFFICULTY_PROBE_JSON line (see HOW TO READ THE OUTPUT) and end the run.
func _finish() -> void:
	if _done:
		return
	_done = true
	var out := {"version": 1, "level": level, "expect": expect, "human_team": human_team, "role": world.human_role, "bank": bank,
			"seconds": snappedf(world.time, 0.1), "minutes": snappedf(world.time / 60.0, 0.001), "ended_early": world.time < secs,
			"winner": world.winner, "team": [_team_report(0), _team_report(1)]}
	print("DIFFICULTY_PROBE_JSON ", JSON.stringify(out))
	if _events != null:
		_events.close()
	get_tree().quit()
