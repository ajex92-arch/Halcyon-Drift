extends Node
## WHAT THIS IS: the change probe: a measuring tool for AI-against-AI
## matches that writes down what the lane minions, the small pilot ships and
## the turrets go through, so two builds of the game can be put side by side.
## It asserts nothing and changes nothing: it only reads the match.
##
## HOW IT WORKS: it listens to the game's events (a unit killed, a turret
## destroyed) and, every tick and every tenth of a second, looks at the match.
## At the end (--secs, or when a mothership dies) it prints one
## "CHANGE_PROBE_JSON {...}" line and quits. What it writes down:
##   minions   how many of each type were seen, how long each lived (seconds
##             from the first look at it to its death), how old the survivors
##             are, who killed them (a pilot, a turret, another minion, a
##             mothership or something else) and the pilots' last hits by type.
##   ships     pilot ship deaths (by cause), kills by pilots, and per hull:
##             ships launched, deaths, lifetimes (seconds from launch to
##             death), ages of the survivors, and the time to kill of every
##             small-ship death (the fun probe's stopwatch,
##             tests/lib/fun_probe_ttk.gd).
##   econ      what the pilots earned and what the treasuries took in and paid
##             out, in all and at 10, 20 and 30 minutes.
##   turrets   every turret seen (when, team, type, lane), every turret
##             destroyed (time, team, type, lane, node kind, when it was built,
##             the team that destroyed it), the ones still standing at the end
##             with their ages, and the hull the built turrets gained from
##             any source.
##   repair    what the Logistics Corvettes' repair drones and Emergency
##             Repair raised, by the kind of unit they raised (ship, turret,
##             repair bay, mothership), worked out from the hulls of the
##             units they work on, one tick before and after. Only the units
##             near a Logistics Corvette are followed, so it is a good
##             estimate (a hit in the very tick of a repair hides a little of
##             it), not an exact count.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --skill-jitter --sim-only --test=change_probe --secs=1800
## --secs is how many game seconds to watch (default 1800). Use the same
## options for two builds and the first minutes of the match are the same
## match. With --late the match starts at 25:00 with both sides fully teched
## (LateGame.apply, as in the fun probe) and --secs counts from 25:00.
##
## HOW TO READ THE OUTPUT: CHANGE_PROBE_JSON holds the groups above. Times are
## match seconds, lifetimes seconds, "team" 0 (Halcyon) or 1 (Cinder).
##
## WHO USES IT: main.gd loads it for --test=change_probe. It only reads the
## game and draws no random numbers, so the match plays exactly as without
## it. A small script outside the game turns the lines of two builds into the
## before/after tables.

## The fun probe's time-to-kill stopwatch, loaded by path so test code stays
## out of the game's names.
const TtkPart := preload("res://tests/lib/fun_probe_ttk.gd")
## Seconds between two looks for new minions, ships and turrets.
const LOOK_EVERY := 0.1
## The match times (seconds) at which the money is written down.
const MONEY_AT := [600.0, 1200.0, 1800.0]
## How far (world units) from a Logistics Corvette its Emergency Repair works.
const EMERGENCY_RANGE := 650.0
## How far (world units) around a Logistics Corvette its neighbours' hulls are
## followed.
const FOLLOW_RANGE := 700.0

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop.
var secs := 1800.0
## The time-to-kill stopwatch.
var ttk: TtkPart

## When each minion was first seen: uid -> [match seconds, type id].
var _m_seen := {}
## Lifetimes (seconds) of minions that died, per type id.
var _m_lives := {"fighter": [], "bomber": [], "corvette": []}
## Minions seen, per type id.
var _m_count := {"fighter": 0, "bomber": 0, "corvette": 0}
## How many minions died before they were ever seen.
var _m_unseen := 0
## How many minions left the match without a death event.
var _m_vanished := 0
## What killed the minions: cause word -> count.
var _m_killed_by := {}
## Last hits by enemy pilots, per minion type id.
var _m_last_hits := {}

## Pilot ships seen: uid -> true.
var _s_seen := {}
## Per hull id: {"launched", "deaths", "lives", "ttk"}.
var _s_hull := {}
## Pilot ship deaths in all.
var _s_deaths := 0
## What killed the pilot ships: cause word -> count.
var _s_killed_by := {}
## Pilot ship deaths that an enemy pilot caused.
var _s_pilot_kills := 0

## Each team's treasury at the last tick (credits).
var _tr_last: Array = [0.0, 0.0]
## Treasury income per team (credits).
var _income: Array = [0.0, 0.0]
## Treasury spending per team (credits).
var _spent: Array = [0.0, 0.0]
## The money written down at MONEY_AT: seconds as text -> {"earned", "income"}.
var _money := {}

## Turrets seen: uid -> [match seconds, team, type, lane, node kind].
var _t_seen := {}
## Turrets destroyed: [time, team, type, lane, node kind, built at, killed by].
var _t_lost: Array = []
## Each built turret's hull at the last tick: uid -> hull.
var _t_hull := {}
## Hull the built turrets gained, per team (any source).
var _t_gain: Array = [0.0, 0.0]
## How many turrets left the match without a destroyed event.
var _t_vanished := 0

## Hull the Logistics drones raised, per kind of unit.
var _r_drone := {}
## Hull the Logistics Emergency Repair raised, per kind of unit.
var _r_emergency := {}
## How many times a Logistics Corvette used Emergency Repair.
var _r_uses := 0
## Seconds a Logistics drone had a turret as its target.
var _r_on_turret_s := 0.0
## The hulls of the targets of Logistics drones at the last tick: uid -> hull.
var _r_target_hull := {}
## The hulls of the units near Logistics Corvettes at the last tick: uid -> hull.
var _r_near_hull := {}
## Each Logistics Corvette's special cooldown at the last tick: uid -> seconds.
var _r_cd := {}

## Seconds until the next look for new units.
var _look_t := 0.0
## Which MONEY_AT time is next.
var _money_i := 0
## A reusable list for the spatial hash search.
var _scratch: Array = []
## True once the line has been printed.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1800.0))
	# --late: the late-game setup (tests/lib/late_game.gd); --secs then counts
	# from 25:00. The money written down at 10, 20 and 30 minutes means
	# nothing in such a match.
	if Game.opt("late", false):
		LateGame.apply(world, Game.opt("symmetric") != null)
		secs += LateGame.START
	ttk = TtkPart.new()
	for t in 2:
		_tr_last[t] = world.teams[t].treasury
	Events.unit_killed.connect(_on_killed)
	Events.turret_destroyed.connect(_on_turret_destroyed)


## What killed a unit, in words: "pilot", "rock" (a crash), or the kind of
## unit that fired: "minion", "turret", "mothership", "derelict",
## "repair_bay" or "other".
static func _cause(d: DamageInfo) -> String:
	if d.source_profile != null:
		return "pilot"
	if d.kind == Rules.W_COLLISION:
		return "rock"
	if d.source != null and is_instance_valid(d.source):
		match (d.source as Unit).kind:
			Unit.K_MINION: return "minion"
			Unit.K_TURRET: return "turret"
			Unit.K_MOTHERSHIP: return "mothership"
			Unit.K_MONSTER, Unit.K_SNUB: return "derelict"
			Unit.K_BAY: return "repair_bay"
	return "other"


## The word for a kind of unit in the repair tables.
static func _kind_word(u: Unit) -> String:
	match u.kind:
		Unit.K_SHIP: return "ship"
		Unit.K_TURRET: return "turret"
		Unit.K_BAY: return "bay"
		Unit.K_MOTHERSHIP: return "mothership"
	return "other"


## Add `amount` to `d[key]` (a number, 0 when missing).
static func _add(d: Dictionary, key: String, amount: float) -> void:
	d[key] = float(d.get(key, 0.0)) + amount


## A unit died (Events.unit_killed): a minion or a pilot ship counts here.
func _on_killed(u: Node, info: RefCounted) -> void:
	var unit := u as Unit
	var d := info as DamageInfo
	if unit == null or d == null:
		return
	if unit.kind == Unit.K_MINION:
		_minion_died(unit as Minion, d)
	elif unit.kind == Unit.K_SHIP:
		_ship_died(unit as Ship, d)


## Minion `m` died of blow `d`: note how long it lived and who killed it.
func _minion_died(m: Minion, d: DamageInfo) -> void:
	var cause := _cause(d)
	_m_killed_by[cause] = int(_m_killed_by.get(cause, 0)) + 1
	if cause == "pilot" and (d.source_profile as PilotProfile).team != m.team:
		_m_last_hits[m.mtype] = int(_m_last_hits.get(m.mtype, 0)) + 1
	if _m_seen.has(m.uid):
		(_m_lives[m.mtype] as Array).append(snappedf(world.time - float((_m_seen[m.uid] as Array)[0]), 0.1))
		_m_seen.erase(m.uid)
	else:
		_m_unseen += 1


## Pilot ship `s` died of blow `d`: count it, note its life and its time to
## kill.
func _ship_died(s: Ship, d: DamageInfo) -> void:
	_s_deaths += 1
	var cause := _cause(d)
	_s_killed_by[cause] = int(_s_killed_by.get(cause, 0)) + 1
	var killer := d.source_profile as PilotProfile
	if killer != null and killer.team != s.team:
		_s_pilot_kills += 1
	var row := _hull_row(s.hull_id)
	row["deaths"] = int(row["deaths"]) + 1
	(row["lives"] as Array).append(snappedf(world.time - s.launched_at, 0.1))
	(row["ttk"] as Array).append(snappedf(ttk.on_death(world, s), 0.1))
	_s_seen.erase(s.uid)


## The record of hull `hid`, made when first needed.
func _hull_row(hid: String) -> Dictionary:
	if not _s_hull.has(hid):
		_s_hull[hid] = {"launched": 0, "deaths": 0, "lives": [], "ttk": []}
	return _s_hull[hid]


## A turret was destroyed (Events.turret_destroyed) by team `by_team`.
func _on_turret_destroyed(t: Node, by_team: int) -> void:
	var tu := t as Turret
	if tu == null:
		return
	var lane := "?"
	var node_kind := "?"
	if tu.node != null:
		lane = tu.node.lane
		node_kind = tu.node.node_kind
	var built := -1.0
	if _t_seen.has(tu.uid):
		built = float((_t_seen[tu.uid] as Array)[0])
	_t_lost.append([snappedf(world.time, 0.1), tu.team, tu.ttype, lane, node_kind, snappedf(built, 0.1), by_team])
	_t_seen.erase(tu.uid)
	_t_hull.erase(tu.uid)


## Every tick: the stopwatch, the treasuries, the built turrets' hulls and
## the Logistics Corvettes' repairs; every tenth of a second a look for new
## units; at the end print the line.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	ttk.tick(world)
	_watch_treasuries()
	_watch_turret_hulls()
	_watch_repairs(dt)
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		_look()
	while _money_i < MONEY_AT.size() and world.time >= float(MONEY_AT[_money_i]):
		_write_money(float(MONEY_AT[_money_i]))
		_money_i += 1
	if world.time >= secs or world.phase != "play":
		_finish()


## Each team's treasury change this tick: a rise is income, a fall spending.
func _watch_treasuries() -> void:
	for t in 2:
		var now_tr := world.teams[t].treasury
		var delta := now_tr - float(_tr_last[t])
		_tr_last[t] = now_tr
		if delta > 0.0:
			_income[t] = float(_income[t]) + delta
		elif delta < 0.0:
			_spent[t] = float(_spent[t]) - delta


## What the pilots earned and the treasuries took in so far, filed under
## `at` (seconds).
func _write_money(at: float) -> void:
	var earned: Array = [0.0, 0.0]
	for p: PilotProfile in world.profiles:
		earned[p.team] = float(earned[p.team]) + p.earned
	_money[str(int(at))] = {"earned": [roundi(float(earned[0])), roundi(float(earned[1]))],
		"income": [roundi(float(_income[0])), roundi(float(_income[1]))], "spent": [roundi(float(_spent[0])), roundi(float(_spent[1]))]}


## The hull each built turret gained since the last tick (from any source).
func _watch_turret_hulls() -> void:
	for tu: Turret in world.turrets:
		if not tu.alive or not tu.is_built():
			_t_hull.erase(tu.uid)
			continue
		if _t_hull.has(tu.uid):
			var gain := tu.hull - float(_t_hull[tu.uid])
			if gain > 0.0:
				_t_gain[tu.team] = float(_t_gain[tu.team]) + gain
		_t_hull[tu.uid] = tu.hull


## The Logistics Corvettes' repairs this tick (see "repair" at the top).
func _watch_repairs(dt: float) -> void:
	# Step 1: the targets of the Logistics drones. A target that a drone healed
	# this tick gained (its hull now less its hull a tick ago); count each
	# target once however many drones heal it.
	var targets := {}
	var healed := {}
	for d: RepairDrone in world.repair_drones:
		if not d.alive or d.mode != RepairDrone.MODE_LOGISTICS or d.target == null or not is_instance_valid(d.target):
			continue
		var tg := d.target
		targets[tg.uid] = tg
		if tg.kind == Unit.K_TURRET:
			_r_on_turret_s += dt
		if d.healing:
			healed[tg.uid] = tg
	for uid: int in healed:
		var tg: Unit = healed[uid]
		var gain := tg.hull - float(_r_target_hull.get(uid, tg.hull))
		if gain > 0.0:
			_add(_r_drone, _kind_word(tg), gain)
	_r_target_hull.clear()
	for uid: int in targets:
		_r_target_hull[uid] = (targets[uid] as Unit).hull
	# Step 2: the Logistics Corvettes' Emergency Repair. A special cooldown that
	# jumps up means the special was used this tick: the friendly ships and
	# structures within its range gained (hull now less hull a tick ago).
	var near := {}
	for s: Ship in world.ships:
		if not s.alive or s.hull_id != "logistics":
			continue
		var cd_before := float(_r_cd.get(s.uid, 0.0))
		_r_cd[s.uid] = s.special_cd
		var used := s.special_cd > cd_before + 1.0
		if used:
			_r_uses += 1
		for u: Unit in world.unit_hash.query(s.global_position, FOLLOW_RANGE, _scratch):
			if u.team != s.team or not u.alive or not (u.kind == Unit.K_SHIP or u.is_structure()):
				continue
			if used and u.global_position.distance_to(s.global_position) < EMERGENCY_RANGE:
				var gain := u.hull - float(_r_near_hull.get(u.uid, u.hull))
				if gain > 0.0:
					_add(_r_emergency, _kind_word(u), gain)
			near[u.uid] = u.hull
	_r_near_hull = near


## Look for minions, ships and turrets that were not there before and write
## down when they appeared.
func _look() -> void:
	var here := {}
	for m: Minion in world.minions:
		if not m.alive:
			continue
		here[m.uid] = true
		if not _m_seen.has(m.uid):
			_m_seen[m.uid] = [world.time, m.mtype]
			_m_count[m.mtype] = int(_m_count[m.mtype]) + 1
	# A minion we saw earlier that is gone without a death event.
	for uid: int in _m_seen.keys():
		if not here.has(uid):
			_m_vanished += 1
			_m_seen.erase(uid)
	for s: Ship in world.ships:
		if s.alive and not _s_seen.has(s.uid):
			_s_seen[s.uid] = true
			var row := _hull_row(s.hull_id)
			row["launched"] = int(row["launched"]) + 1
	var standing := {}
	for tu: Turret in world.turrets:
		if not tu.alive:
			continue
		standing[tu.uid] = true
		if not _t_seen.has(tu.uid):
			var lane := "?"
			var node_kind := "?"
			if tu.node != null:
				lane = tu.node.lane
				node_kind = tu.node.node_kind
			_t_seen[tu.uid] = [world.time, tu.team, tu.ttype, lane, node_kind]
	# A turret we saw earlier that is gone without a destroyed event.
	for uid: int in _t_seen.keys():
		if not standing.has(uid):
			_t_vanished += 1
			_t_seen.erase(uid)
			_t_hull.erase(uid)


## Print the CHANGE_PROBE_JSON line (see HOW TO READ THE OUTPUT) and end the
## run.
func _finish() -> void:
	_done = true
	var ended := world.phase != "play"
	# The ages of the survivors, per minion type and per hull, and the turrets
	# still standing.
	var m_alive := {"fighter": [], "bomber": [], "corvette": []}
	for uid: int in _m_seen:
		var e: Array = _m_seen[uid]
		(m_alive[str(e[1])] as Array).append(snappedf(world.time - float(e[0]), 0.1))
	var hulls := {}
	for hid: String in _s_hull:
		var row: Dictionary = (_s_hull[hid] as Dictionary).duplicate()
		row["alive_ages"] = []
		hulls[hid] = row
	for s: Ship in world.ships:
		if s.alive and hulls.has(s.hull_id):
			((hulls[s.hull_id] as Dictionary)["alive_ages"] as Array).append(snappedf(world.time - s.launched_at, 0.1))
	var standing: Array = []
	for uid: int in _t_seen:
		var e: Array = _t_seen[uid]
		standing.append([e[1], e[2], e[3], e[4], snappedf(world.time - float(e[0]), 0.1)])
	var built: Array = []
	for uid: int in _t_seen:
		var e: Array = _t_seen[uid]
		built.append([snappedf(float(e[0]), 0.1), e[1], e[2], e[3], e[4]])
	for l: Array in _t_lost:
		if float(l[5]) >= 0.0:
			built.append([l[5], l[1], l[2], l[3], l[4]])
	var earned: Array = [0.0, 0.0]
	var last_hits := 0
	for p: PilotProfile in world.profiles:
		earned[p.team] = float(earned[p.team]) + p.earned
		last_hits += p.minion_kills
	var out := {
		"probe": "change_probe", "version": 1, "seed": int(Game.opt("seed", -1)), "skill_jitter": Game.opt("skill-jitter") != null,
		"secs_cap": int(secs), "time": snappedf(world.time, 0.1), "ended": ended, "winner": world.winner if ended else -1,
		"minions": {"seen": _m_count, "lives": _m_lives, "alive_ages": m_alive, "killed_by": _m_killed_by,
			"last_hits_by_type": _m_last_hits, "unseen_deaths": _m_unseen, "vanished": _m_vanished},
		"ships": {"deaths": _s_deaths, "killed_by": _s_killed_by, "pilot_kills": _s_pilot_kills, "minion_last_hits": last_hits, "by_hull": hulls},
		"econ": {"earned": [roundi(float(earned[0])), roundi(float(earned[1]))], "income": [roundi(float(_income[0])), roundi(float(_income[1]))],
			"spent": [roundi(float(_spent[0])), roundi(float(_spent[1]))], "at": _money},
		"turrets": {"built": built, "lost": _t_lost, "standing": standing, "hull_gain": [roundi(float(_t_gain[0])), roundi(float(_t_gain[1]))]},
		"repair": {"drone_hull": _rounded(_r_drone), "emergency_hull": _rounded(_r_emergency), "emergency_uses": _r_uses,
			"drone_on_turret_s": snappedf(_r_on_turret_s, 0.1)},
	}
	print("CHANGE_PROBE_JSON ", JSON.stringify(out))
	get_tree().quit()


## A copy of the number table `d` with every number rounded to a whole one.
static func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = roundi(float(d[k]))
	return out
