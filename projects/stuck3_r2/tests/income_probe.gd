extends Node
## WHAT THIS IS: the "income probe": a small measuring tool that follows the
## money pilots earn in an AI-vs-AI match, source by source (added for T-25,
## assist money). It answers: how many credits did each
## team's pilots earn from last hits on minions, from helping on minions, from
## pilot kills, from helping on pilot kills, from jungle camps, turrets,
## ore and the steady trickle, and how often did a last hit have helpers?
##
## HOW IT WORKS: it listens to two events. Every payment (Events.credits_earned)
## is added up by the team of the pilot and the reason the game gave
## ("minion", "minion assist", "kill", "assist", "derelict", "turret", "ore",
## "escort" ...). Every death (Events.unit_killed) lets it check, for a minion
## or a pilot's ship that an enemy pilot finished off, whether other pilots of
## that team had helped (the same test the game uses: at least 10% of the
## damage in the last 15 seconds, Economy.contributors). The game pays the
## killer first and the helpers right after, inside one call, before the death
## message; that order tells the probe whether an "assist" payment belongs to
## a kill that a pilot made (the helpers' part) or to one that a turret, minion
## or monster made. The steady trickle sends no payment message, so it is what
## is left of the pilots' "earned" total after all the payments are taken off.
## At the end (--secs, or when a mothership dies) it prints one
## "INCOME_JSON {...}" line and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=401 --skill-jitter --sim-only --test=income_probe --secs=900
## --secs is how many game seconds to watch (default 900). With --late the
## match starts at 25:00 with both sides fully teched (LateGame.apply) and
## --secs counts from 25:00.
##
## HOW TO READ THE OUTPUT: INCOME_JSON holds
##   "seconds" / "minutes"  how long the match was watched;
##   "ended_early"          true when a mothership fell before --secs;
##   "pilots"               the number of pilot records per team;
##   "team"                 two entries (0 = Aurelian, 1 = Vhorr), each with
##     "credits"            credits paid per reason (after the pilot's gear bonus);
##     "payments"           how many payments per reason;
##     "events_total"       all the credits paid with a message;
##     "earned_total"       the pilots' "earned" totals;
##     "trickle"            earned_total - events_total: the steady trickle;
##     "assist_split"       the "assist" credits split into "on_pilot_kill"
##                          (a pilot made the killing blow) and "no_pilot"
##                          (a turret, minion or monster did);
##     "counts"             minion_kills, minion_assists, assists (pilot-kill
##                          helpers), kills, monster_kills; and the last hits
##                          "lh_total" / "lh_helped" on minions, the pilot kills
##                          "pk_total" / "pk_helped";
##   "all"                  the same sums for both teams together.
## A build without PilotProfile.minion_assists (before T-25) counts 0 there.
##
## WHO USES IT: main.gd loads it for --test=income_probe. It only reads the
## game and draws no random numbers, so the match plays exactly as without it.
## A script outside the game turns the INCOME_JSON lines of two builds into the
## before/after tables.

## Game time (seconds) to watch for when --secs is not given.
const DEFAULT_SECS := 900.0
## The counters that are added up per team (see "counts" above).
const COUNT_KEYS := ["minion_kills", "minion_assists", "assists", "kills", "monster_kills", "lh_total", "lh_helped", "pk_total", "pk_helped"]

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := DEFAULT_SECS
## Game time (seconds) when the watching began (0, or 25:00 with --late).
var t0 := 0.0
## Credits paid with a message, per team: team -> reason -> credits.
var _credits: Array = [{}, {}]
## Payments with a message, per team: team -> reason -> count.
var _payments: Array = [{}, {}]
## The "assist" credits per team, split by who made the killing blow:
## team -> {"on_pilot_kill": credits, "no_pilot": credits}.
var _assist_split: Array = [{"on_pilot_kill": 0.0, "no_pilot": 0.0}, {"on_pilot_kill": 0.0, "no_pilot": 0.0}]
## The last hits and pilot kills that had helpers, per team:
## team -> {"lh_total": n, "lh_helped": n, "pk_total": n, "pk_helped": n}.
var _helped: Array = [{"lh_total": 0, "lh_helped": 0, "pk_total": 0, "pk_helped": 0}, {"lh_total": 0, "lh_helped": 0, "pk_total": 0, "pk_helped": 0}]
## True from the "kill" payment of a pilot kill until the death message that
## follows it (the helpers' "assist" payments come in between).
var _pilot_kill_paid := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", DEFAULT_SECS))
	# --late: the late-game setup (tests/lib/late_game.gd); --secs then counts
	# from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		secs += LateGame.START
	t0 = world.time
	Events.credits_earned.connect(_on_credits)
	Events.unit_killed.connect(_on_killed)


## A pilot was paid: add it to its team's sums by reason.
func _on_credits(profile: RefCounted, amount: float, reason: String) -> void:
	var p := profile as PilotProfile
	if p == null:
		return
	var c: Dictionary = _credits[p.team]
	c[reason] = float(c.get(reason, 0.0)) + amount
	var n: Dictionary = _payments[p.team]
	n[reason] = int(n.get(reason, 0)) + 1
	# The killer of a pilot's ship is paid first, then the helpers.
	if reason == "kill":
		_pilot_kill_paid = true
	elif reason == "assist":
		var key := "on_pilot_kill" if _pilot_kill_paid else "no_pilot"
		var split: Dictionary = _assist_split[p.team]
		split[key] = float(split[key]) + amount


## Something died (the game has paid for it already). A minion or a pilot's
## ship that an enemy pilot finished off: count it, and whether pilots of the
## killer's team had helped.
func _on_killed(u: Node, info: RefCounted) -> void:
	_pilot_kill_paid = false
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null:
		return
	var killer := d.source_profile as PilotProfile
	if killer == null or killer.team == unit.team:
		return
	if unit.kind != Unit.K_MINION and unit.kind != Unit.K_SHIP:
		return
	# The same helpers test as Economy: other pilots of the killer's team with
	# at least assist_min_fraction of the damage in the last assist_window s.
	var who := Economy.contributors(world, unit, float(Rules.tune("assist_window", Rules.ASSIST_WINDOW)), float(Rules.tune("assist_min_fraction", Rules.ASSIST_MIN_FRACTION)))
	var helped := false
	for p: PilotProfile in who:
		if p != killer and p.team == killer.team:
			helped = true
	var h: Dictionary = _helped[killer.team]
	var prefix := "lh" if unit.kind == Unit.K_MINION else "pk"
	h[prefix + "_total"] = int(h[prefix + "_total"]) + 1
	if helped:
		h[prefix + "_helped"] = int(h[prefix + "_helped"]) + 1


## Every tick: stop at the end time, or when the match is over.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= secs or world.phase != "play":
		_finish()


## One team's numbers for the JSON line (see HOW TO READ THE OUTPUT).
func _team_report(team: int) -> Dictionary:
	var credits := {}
	var events_total := 0.0
	for r: String in _credits[team]:
		credits[r] = snappedf(float(_credits[team][r]), 0.01)
		events_total += float(_credits[team][r])
	var earned_total := 0.0
	var counts := {}
	for k: String in COUNT_KEYS:
		counts[k] = 0
	for p: PilotProfile in world.profiles:
		if p.team != team:
			continue
		earned_total += p.earned
		counts["minion_kills"] += p.minion_kills
		# Builds from before T-25 have no minion_assists: get() answers null.
		counts["minion_assists"] += int(p.get("minion_assists") if p.get("minion_assists") != null else 0)
		counts["assists"] += p.assists
		counts["kills"] += p.kills
		counts["monster_kills"] += p.monster_kills
	for k: String in _helped[team]:
		counts[k] = int(_helped[team][k])
	return {"credits": credits, "payments": _payments[team].duplicate(), "events_total": snappedf(events_total, 0.01),
			"earned_total": snappedf(earned_total, 0.01), "trickle": snappedf(earned_total - events_total, 0.01),
			"assist_split": {"on_pilot_kill": snappedf(float(_assist_split[team]["on_pilot_kill"]), 0.01), "no_pilot": snappedf(float(_assist_split[team]["no_pilot"]), 0.01)},
			"counts": counts}


## Add team report `b` into total report `a` (numbers, and dictionaries of
## numbers, are added up).
func _add_into(a: Dictionary, b: Dictionary) -> void:
	for k: String in b:
		if b[k] is Dictionary:
			if not a.has(k):
				a[k] = {}
			_add_into(a[k], b[k])
		else:
			a[k] = a.get(k, 0) + b[k]


## Print the INCOME_JSON line (see HOW TO READ THE OUTPUT) and end the run.
func _finish() -> void:
	var teams: Array = [_team_report(0), _team_report(1)]
	var all := {}
	_add_into(all, teams[0])
	_add_into(all, teams[1])
	# Round the sums again, so no float noise shows in the line.
	for k: String in ["events_total", "earned_total", "trickle"]:
		all[k] = snappedf(float(all[k]), 0.01)
	for r: String in all["credits"]:
		all["credits"][r] = snappedf(float(all["credits"][r]), 0.01)
	var npilots := [0, 0]
	for p: PilotProfile in world.profiles:
		npilots[p.team] += 1
	print("INCOME_JSON ", JSON.stringify({"seconds": snappedf(world.time - t0, 0.1), "minutes": snappedf((world.time - t0) / 60.0, 0.001),
			"ended_early": world.time < secs, "pilots": npilots, "team": teams, "all": all}))
	get_tree().quit()
