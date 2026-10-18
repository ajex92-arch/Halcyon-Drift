extends Node
## WHAT THIS IS: a "fun meter" for AI-vs-AI matches (version 2). It watches
## a whole match and measures the things that make a match like this fun
## (or not) for real players: how long matches last and how they end, how
## much time pilots spend fighting versus waiting, who kills whom, whether
## skirmishes grow into big team fights, whether the lead changes hands,
## whether skill and both ship sizes matter, where the money goes, and how
## busy the admiral is. docs/FUN_RESEARCH.md ("Fun model") defines every
## number; docs/FUN_PLAN.md says how the fun experiments use them.
##
## HOW IT WORKS: the work is split into parts in tests/lib/, one job each:
##   fun_probe_time.gd        each pilot's second: dead, docked, fighting,
##                            near, commuting or idle; return to action
##   fun_probe_kills.gd       every kill: cause, helpers, ship sizes, assets
##   fun_probe_ttk.gd         time to kill (how long a ship was under fire)
##   fun_probe_fights.gd      team fights (clusters of pilots fighting)
##   fun_probe_motherships.gd the endgame: hull pressure, sieges, limbo
##   fun_probe_lead.gd        who is ahead (worth, and adv_index.gd)
##   fun_probe_economy.gd     money: pay for play, spending, admiral orders
##   fun_stats.gd             small maths helpers (median, correlation)
## This file starts them, feeds them the game's events and runs their
## timers: every tick (TTK hits, treasury changes), every second, every
## 2 s (fights), every 5 s (mothership hulls), every 30 s (the lead) and
## every minute. At the end it prints one line, FUN_JSON {...}, with every
## number, and quits. Version 1's numbers are all still there, with the
## same names and meaning (docs/FUN_METRICS.md).
##   The 30:00 snapshot: in a normal (not --late) match, the first time the
## match clock reaches 30:00 (1,800 s) it also prints one extra line,
## FUN_JSON30 {...}: exactly the same fields as FUN_JSON, worked out as if
## the watch had ended right then (so the fun experiments that cap their
## matches at 30:00 with --secs=1800 can be compared with the same moment of
## a full 60-minute baseline match). It only READS: the parts that change
## when they finish (the mothership watcher closes its running assaults) are
## finished on a copy, so everything measured afterwards, and the final
## FUN_JSON, are byte for byte what they are without the snapshot. Its
## "secs_cap" is the snapshot time (1800), as in a --secs=1800 run. A match
## that ends or is stopped before 30:00 prints no FUN_JSON30 line (its
## FUN_JSON already is the result). A run with --secs=1800 prints both lines
## (the same numbers).
##   The per-hit event Events.damage_applied (and the switch that turns it
##   on, world.combat.emit_damage_events) only exist in builds that have
##   them: setup() checks first, and "damage_hook" in FUN_JSON says whether
##   it was on. Without it, only the "who damaged the mothership" numbers
##   are missing (null). Game.usage (counters of how often the AI used each
##   new mechanic) is copied into FUN_JSON as "usage" when it exists.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=101 --skill-jitter --test=fun_probe --secs=3600
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second, so a run with
## the same --seed (the starting number for the random rolls) repeats.
## --secs is how many game seconds to watch at most (default 3600 = one
## hour); the probe also stops when a mothership dies. --skill-jitter
## (read by the game, where the build has it) gives each AI seat a random
## skill, the same seat for both teams.
## --late starts at 25:00 with both sides fully teched (LateGame.apply, the
## same setup as tests/det_hash.gd --late and tests/endgame.gd); --secs
## then counts from 25:00. Add --symmetric to also keep Cinder's mid inner
## turrets (LateGame normally starts Cinder without them).
## --fun-snapshot=<secs> (a test-only option) changes the time of the extra
## FUN_JSON30 line (default 1800 = 30:00); --fun-snapshot=0 turns it off. A
## --late run never prints it. The line is still called FUN_JSON30 whatever
## the time, so use another time only for quick tests of the snapshot itself.
##
## HOW TO READ THE OUTPUT: the one line that matters is "FUN_JSON {...}": a
## JSON text (a standard way to write a dictionary as text). Times in
## "..._min" are in minutes, "..._secs"/"..._s" in seconds, "-1" means
## "never happened" and null means "could not be measured in this run"
## (for example the late numbers of a 20-minute run). tools/fun_score.py
## turns a folder of these lines into the FUN score; its --at30 option reads
## the FUN_JSON30 lines instead.
##
## WHO USES IT: main.gd loads it for --test=fun_probe (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). The
## fun experiments (forks of the game compared by a council, see
## docs/FUN_PLAN.md) compare FUN_JSON lines with tools/fun_score.py; the
## ones screened in matches capped at 30:00 are compared with the
## FUN_JSON30 line of baseline v2's 60-minute matches (fun_score --at30).

## The parts (see HOW IT WORKS). Loaded with preload() rather than by a
## global class name, so test code stays out of the game's names.
const TimePart := preload("res://tests/lib/fun_probe_time.gd")
## Kills: causes, helpers, ship sizes, assets.
const KillsPart := preload("res://tests/lib/fun_probe_kills.gd")
## Time to kill.
const TtkPart := preload("res://tests/lib/fun_probe_ttk.gd")
## Team fights.
const FightsPart := preload("res://tests/lib/fun_probe_fights.gd")
## Motherships and sieges.
const MsPart := preload("res://tests/lib/fun_probe_motherships.gd")
## Who is ahead.
const LeadPart := preload("res://tests/lib/fun_probe_lead.gd")
## Money and admiral orders.
const EconomyPart := preload("res://tests/lib/fun_probe_economy.gd")
## The FUN_JSON format version (v1 had no such field).
const VERSION := 2
## The default match time (seconds) of the FUN_JSON30 snapshot: 30:00.
const SNAPSHOT_DEFAULT := 1800.0

## How long to watch: the match time (seconds) at which to stop, if no
## mothership dies first.
var secs := 3600.0
## The match time (seconds) at which to print the FUN_JSON30 snapshot line;
## 0 = no snapshot (set by --fun-snapshot, and always 0 with --late).
var snap_secs := SNAPSHOT_DEFAULT
## The running match (set by setup()).
var world: World
## The match clock (seconds) when watching began: 0, or 1,500 with --late.
var start_t := 0.0
## True when the match started at 25:00 (--late).
var late := false
## True when the per-hit event (Events.damage_applied) is on.
var hook := false
## The parts (made in setup()).
var time_part: TimePart
## The kill book.
var kills: KillsPart
## The time-to-kill stopwatch.
var ttk: TtkPart
## The team-fight spotter.
var fights: FightsPart
## The mothership watcher.
var ms: MsPart
## The "who is ahead?" part.
var lead: LeadPart
## The accountant.
var economy: EconomyPart

## Seconds since the last once-a-second sample.
var _t_sec := 0.0
## Seconds since the last fight check (every 2 s).
var _t_fight := 0.0
## Seconds since the last mothership hull sample (every 5 s).
var _t_hull := 0.0
## Seconds since the last "who is ahead" check (every 30 s).
var _t_lead := 0.0
## Seconds since the last once-a-minute sample.
var _t_min := 0.0
## True once FUN_JSON has been printed (stop doing anything).
var _done := false
## True once the FUN_JSON30 snapshot line has been printed (only once).
var _snapped := false


## main.gd calls this once, right after the World is built. Read the
## options, set up --late, make the parts and start listening to the
## game's events.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 3600.0))
	# Step 1: --late: the late-game setup (tests/lib/late_game.gd); --secs
	# then counts from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		late = true
		secs += LateGame.START
	# The snapshot time (--fun-snapshot, default 30:00); none in a --late
	# match, which starts at 25:00 and has its own scoring.
	var snap_opt = Game.opt("fun-snapshot", SNAPSHOT_DEFAULT)
	snap_secs = SNAPSHOT_DEFAULT if snap_opt is bool else float(snap_opt)
	if late:
		snap_secs = 0.0
	start_t = world.time
	# Step 2: the parts.
	time_part = TimePart.new()
	kills = KillsPart.new(time_part)
	ttk = TtkPart.new()
	fights = FightsPart.new()
	ms = MsPart.new()
	lead = LeadPart.new(start_t)
	economy = EconomyPart.new()
	economy.start(world)
	# Step 3: the game's events. (A "signal" is a message the game sends;
	# Godot calls each connected function with its values.)
	Events.unit_killed.connect(_on_unit_killed)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	Events.credits_earned.connect(_on_credits_earned)
	Events.admiral_result.connect(_on_admiral_result)
	# Step 4: the per-hit event, only in builds that have it. We connect by
	# name, so this file still loads in builds without it.
	if Events.has_signal("damage_applied") and world.combat.get("emit_damage_events") != null:
		world.combat.set("emit_damage_events", true)
		Events.connect("damage_applied", _on_damage_applied)
		hook = true


## A unit died (`u`; `info` is the DamageInfo of the killing blow). The
## kill book reads every death; a pilot ship's death also stops its TTK
## stopwatch, starts its return-to-action stopwatch and, for a pilot kill,
## counts for the killers' "recent kills".
func _on_unit_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null:
		return
	kills.on_unit_killed(world, unit, d)
	if unit.kind == Unit.K_SHIP:
		var s := unit as Ship
		ttk.on_death(world, s)
		time_part.note_death(s.profile, world.time)
		var killer := d.source_profile as PilotProfile
		if killer != null and killer.team != s.team:
			lead.note_pilot_kill(killer.team, world.time)


## A turret was destroyed by team `by_team` (Events.turret_destroyed).
func _on_turret_destroyed(t: Node, by_team: int) -> void:
	var n := t as Node2D
	if n != null:
		kills.on_turret_destroyed(world, n, by_team)


## A pilot was paid (Events.credits_earned).
func _on_credits_earned(p: RefCounted, amount: float, reason: String) -> void:
	var pp := p as PilotProfile
	if pp == null:
		return
	economy.on_credits(pp, amount, reason)
	kills.on_credits(pp, reason)


## An admiral order finished (Events.admiral_result).
func _on_admiral_result(team: int, action: String, ok: bool, _message: String) -> void:
	economy.on_admiral_result(world, team, action, ok)


## One hit (Events.damage_applied, only in builds that have it): `target`
## was hit by `info` for `amount` damage, `hull_dmg` of it to the hull.
func _on_damage_applied(target: Node, info: RefCounted, _amount: float, hull_dmg: float) -> void:
	ms.on_damage(target, info, hull_dmg)


## Godot calls this every tick; `dt` is the tick's length in seconds. Run
## each sampler on its own timer, and print FUN_JSON at the end.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	# Every tick: hits for the TTK stopwatch, and treasury changes.
	ttk.tick(world)
	economy.tick(world)
	# Once a second: every pilot's bucket, strain, the motherships' first
	# hull damage and the sieges.
	_t_sec += dt
	if _t_sec >= 1.0:
		_t_sec -= 1.0
		time_part.sample_pilots(world)
		time_part.sample_strain(world)
		ms.sample_first_hit(world)
		ms.sample_siege(world)
	# Every 2 seconds: team fights.
	_t_fight += dt
	if _t_fight >= 2.0:
		_t_fight -= 2.0
		fights.sample(world)
	# Every 5 seconds: both motherships' hulls.
	_t_hull += dt
	if _t_hull >= 5.0:
		_t_hull -= 5.0
		ms.sample_hull(world)
	# Every 30 seconds: who is ahead, and the late treasuries.
	_t_lead += dt
	if _t_lead >= 30.0:
		_t_lead -= 30.0
		lead.sample(world)
		economy.sample_30s(world)
	# Every minute: hull use and the money at 30:00.
	_t_min += dt
	if _t_min >= 60.0:
		_t_min -= 60.0
		time_part.sample_minute(world)
		economy.sample_minute(world)
	# The snapshot: the first time the clock reaches the snapshot time, print
	# what FUN_JSON would be if the watch ended now. It only reads: the
	# mothership watcher is finished on a copy (finish() changes it), so the
	# real parts and the final FUN_JSON are not affected.
	if snap_secs > 0.0 and not _snapped and world.time >= snap_secs:
		_snapped = true
		var ms_copy := ms.duplicate_state() as MsPart
		ms_copy.finish(world, world.phase != "play")
		print("FUN_JSON30 " + JSON.stringify(_results(ms_copy, snap_secs)))
	# The end: time is up, or a mothership died.
	if world.time >= secs or world.phase != "play":
		_done = true
		ms.finish(world, world.phase != "play")
		print("FUN_JSON " + JSON.stringify(_results(ms, secs)))
		get_tree().quit()


## Minutes watched between match times `from_t` and `to_t` (seconds),
## within the watch (start_t to now). 0 if the watch never covered them.
func _watched_min(from_t: float, to_t: float) -> float:
	return maxf(0.0, minf(to_t, world.time) - maxf(from_t, start_t)) / 60.0


## Every number, in one dictionary (printed as FUN_JSON, or as FUN_JSON30
## for the snapshot). `mship` is the mothership watcher to read: the real
## one for FUN_JSON, a finished copy for the snapshot (it is only read
## here, never changed). `cap` is the value of "secs_cap": the cap of the
## run, or the snapshot time. Version 1's keys keep their names and meaning;
## see docs/FUN_RESEARCH.md for the rest.
func _results(mship: MsPart, cap: float) -> Dictionary:
	# Step 1: the match, the watch, and the AI pilots with their skills.
	var ended := world.phase != "play"
	var winner := world.winner if ended else -1
	var obs_secs := world.time - start_t
	var obs_min := obs_secs / 60.0
	var pilots: Array = []
	var skills: Array = []
	for p: PilotProfile in world.profiles:
		if not p.is_human:
			pilots.append(p)
			var ai: PilotAI = world.pilot_ai.get(p)
			skills.append(ai.skill if ai != null else 0.0)
	# Step 2: every part's numbers.
	var out := {
		"probe": "fun_probe",
		"version": VERSION,
		"seed": int(Game.opt("seed", -1)),
		"late_start": late,
		"start_min": snappedf(start_t / 60.0, 0.01),
		"secs_cap": int(cap),
		"variants": Game.variants,
		"skill_jitter": Game.opt("skill-jitter") != null,
		"damage_hook": hook,
		"ended": ended,
		"winner": winner,
		"minutes": snappedf(world.time / 60.0, 0.01),
		"obs_minutes": snappedf(obs_min, 0.01),
		"pilots": pilots.size(),
	}
	var tr := time_part.results()
	var kr := kills.results(world, pilots, skills, time_part.size_secs.map(func(x): return float(x) / 60.0), _watched_min(0.0, 600.0), _watched_min(1500.0, INF))
	out.merge(tr)
	out.merge(kr)
	out.merge(ttk.results())
	out.merge(fights.results(obs_secs, pilots.size()))
	out.merge(mship.results(winner, ended, start_t, world.time))
	# How the match ended: "mothership" (one was destroyed), "surrender" (a
	# passed surrender vote, the surrender:vote variant) or "none" (still
	# running). A surrendered match has no mothership kill, so the numbers
	# that need one (final push, close-out time, big-ship damage share and
	# the damage sums it is pooled from) are null for it and the scoring
	# leaves them out.
	var ended_by := "none"
	if ended:
		ended_by = "surrender" if int(Game.usage.get("surrenders", 0)) > 0 else "mothership"
	out["ended_by"] = ended_by
	if ended_by == "surrender":
		out["final_push_secs"] = null
		out["close_out_secs"] = null
		out["ms_big_damage_share"] = null
		out["ms_loser_big_dmg"] = null
		out["ms_loser_hull_dmg"] = null
	out.merge(lead.results(winner, ended, world.time))
	out.merge(economy.results(world, pilots, skills, _watched_min(1800.0, INF)))
	# Step 3: the v1 rates, now per minute WATCHED (the same as before for a
	# run from 0:00; right for a --late run too).
	var ship_deaths := int(kr["ship_deaths"])
	out["kills_per_min"] = snappedf(float(ship_deaths) / maxf(0.01, obs_min), 0.01)
	out["deaths_per_pilot_per_10min"] = snappedf(float(ship_deaths) / maxf(1.0, float(pilots.size())) / maxf(0.01, obs_min) * 10.0, 0.01)
	out["avg_dead_secs_per_death"] = snappedf(time_part.t_dead / maxf(1.0, float(ship_deaths)), 0.1)
	out["turrets_destroyed"] = [world.teams[0].turrets_destroyed, world.teams[1].turrets_destroyed]
	# Step 4: one row per AI pilot: callsign, team, seat, skill, credits
	# earned, kills / assists / deaths, and the same while in a small hull.
	var table: Array = []
	for i in pilots.size():
		var p: PilotProfile = pilots[i]
		var sc := kills.small_counts(p)
		table.append({"cs": p.callsign, "t": p.team, "slot": p.slot, "skill": snappedf(float(skills[i]), 0.001), "earned": int(p.earned),
			"k": p.kills, "a": p.assists, "d": p.deaths, "sk": sc[0], "sa": sc[1], "sd": sc[2]})
	out["pilot_table"] = table
	# Step 5: how often the AI used each new mechanic (Game.usage, in builds
	# that have it).
	var usage = Game.get("usage")
	if usage is Dictionary:
		out["usage"] = (usage as Dictionary).duplicate(true)
	return out
