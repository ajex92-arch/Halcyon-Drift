class_name StatsPilotRecord
extends RefCounted
## WHAT THIS IS: one page of the stats recorder's notebook: everything it
## has seen ONE pilot (the human or an AI pilot) do in this match. How many
## shots they fired and how many hit, how much damage they dealt and took,
## which ships they flew and for how long, and from how far away their
## shots landed.
##
## HOW IT WORKS: StatsRecorder gives each pilot a page and then feeds it:
##   - tick() once per game tick: adds the tick to the pilot's state clock
##     (flying, docked, dead or spooling), to the clock of the hull they are
##     flying, and counts the shots their guns fired. A gun has a cooldown
##     (WeaponMount.cd) that only ever goes down, except in the tick it
##     fires, when it jumps up; so a rise means one shot (one round for each
##     pellet, so a flak burst is 5 or 6). A beam counts one shot for every
##     tick it is on.
##   - on_dealt() for every hit this pilot landed (Events.damage_applied):
##     counts the hit for the weapon kind and the kind of target, adds the
##     damage, and notes how far the shooter was from the target (the mean,
##     and how many hits on enemy pilot ships landed in each 250-unit band).
##   - on_taken() for every hit this pilot's ship took.
##   - to_dict(): the page as plain data for the JSON file. It adds up the
##     weapons into a hit rate (point defence is left out of the total: it
##     mostly shoots torpedoes, which are not units, so it can hardly "hit"),
##     and divides the damage by the minutes spent flying ("per minute
##     alive" means in space with a ship; a pilot waiting in the hangar or
##     for a respawn takes no fire).
## It only reads the game. It never touches the shared random sequence or
## any game state.
##
## WHO USES IT: StatsRecorder (scripts/stats_recorder.gd) makes one per pilot.

## The weapon kind names, by number (Rules.W_BOLT -> "bolt" ...), for hits:
## the damage note only carries the number. Built once from Rules.KIND_IDS.
static var _kind_names := {}
## The width (world units) of one bucket of the hit-distance list, and how
## many buckets there are (the last one is "this far or farther").
const DIST_BUCKET := 250.0
const DIST_BUCKETS := 9

## The pilot this page is about (their record: team, seat, kills ...).
var profile: PilotProfile
## The AI brain of that pilot (for its skill and temperament), or null for
## the human.
var brain: PilotAI = null
## Seconds spent in each pilot state: "flying", "docked", "dead", "spooling".
var secs_in := {"flying": 0.0, "docked": 0.0, "dead": 0.0, "spooling": 0.0}
## How many ships they launched.
var launches := 0
## Seconds flown per hull id, and launches per hull id.
var hull_secs := {}
var hull_launches := {}
## Per weapon kind name ("bolt", "lance", "torp", "flak", "pd", "shell",
## "ion"): {"shots": rounds fired (beam: ticks on), "hits": hits landed,
## "dmg": damage dealt after every damage rule, before the shields}.
var weapons := {}
## Hits landed and damage dealt, by the kind of unit hit ("ship", "minion",
## "turret", "derelict", ...: Unit.KIND_NAMES).
var hits_by_target := {}
var dmg_by_target := {}
## Damage taken: all of it (before the shields), the part that reached the
## hull, and the part that was crashing into rocks.
var dmg_in := 0.0
var dmg_in_hull := 0.0
var dmg_in_crash := 0.0
## Distance (world units) between shooter and target when a hit landed: the
## total and the count, for hits on enemy pilot ships and for all hits.
var dist_ship_sum := 0.0
var dist_ship_n := 0
var dist_all_sum := 0.0
var dist_all_n := 0
## How many hits on enemy pilot ships landed at each distance: bucket i holds
## the distances from i x DIST_BUCKET up to (i + 1) x DIST_BUCKET, and the
## last bucket everything farther.
var dist_hist: Array = []
## The ship seen on the last tick, and the cooldown of each of its guns then.
var _ship: Ship = null
var _cds: Array = []


## Open a page for pilot `p`; `ai` is their AI brain (null for the human).
func _init(p: PilotProfile, ai: PilotAI) -> void:
	profile = p
	brain = ai
	dist_hist.resize(DIST_BUCKETS)
	dist_hist.fill(0)
	if _kind_names.is_empty():
		for k: String in Rules.KIND_IDS:
			_kind_names[int(Rules.KIND_IDS[k])] = k


## The name of weapon kind number `k` ("bolt", "torp" ...).
static func kind_name(k: int) -> String:
	return str(_kind_names.get(k, "kind%d" % k))


## One game tick of `dt` seconds has passed: advance the clocks and count
## the shots fired in it.
func tick(dt: float) -> void:
	# Step 1: the clock of the pilot's state.
	secs_in[profile.state] = float(secs_in.get(profile.state, 0.0)) + dt
	# Step 2: only a pilot in space has guns to watch.
	var ship: Ship = profile.ship if profile.state == "flying" else null
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		_ship = null
		return
	# Step 3: a ship we have not seen before is a new launch: write down the
	# cooldowns its guns start with.
	if ship != _ship:
		_ship = ship
		launches += 1
		hull_launches[ship.hull_id] = int(hull_launches.get(ship.hull_id, 0)) + 1
		_remember_cooldowns(ship)
	hull_secs[ship.hull_id] = float(hull_secs.get(ship.hull_id, 0.0)) + dt
	# Step 4: the guns. (A refit that adds a gun changes the list: start the
	# cooldown notes again, and count nothing this tick.)
	if _cds.size() != ship.mounts.size():
		_remember_cooldowns(ship)
		return
	for i in ship.mounts.size():
		var m: WeaponMount = ship.mounts[i]
		var fired := 0
		if m.is_beam:
			fired = 1 if m.beam_firing else 0
		elif m.cd > float(_cds[i]) + 0.0001:
			fired = int(m.def.get("pellets", 1))
		_cds[i] = m.cd
		if fired > 0:
			var w := _weapon(str(m.def.get("kind", "bolt")))
			w["shots"] += fired


## This pilot's ship hit `target` with the note `info`; `amount` is the
## damage after every rule (before the shields).
func on_dealt(target: Unit, info: DamageInfo, amount: float) -> void:
	# Step 1: the weapon kind and the kind of target.
	var w := _weapon(kind_name(info.kind))
	w["hits"] += 1
	w["dmg"] += amount
	var tk: String = Unit.KIND_NAMES[target.kind]
	hits_by_target[tk] = int(hits_by_target.get(tk, 0)) + 1
	dmg_by_target[tk] = float(dmg_by_target.get(tk, 0.0)) + amount
	# Step 2: how far the shooter was (the shooter may be gone by now).
	if info.source != null and is_instance_valid(info.source):
		var d := info.source.global_position.distance_to(target.global_position)
		dist_all_sum += d
		dist_all_n += 1
		if target.kind == Unit.K_SHIP:
			dist_ship_sum += d
			dist_ship_n += 1
			var b := mini(int(d / DIST_BUCKET), DIST_BUCKETS - 1)
			dist_hist[b] = int(dist_hist[b]) + 1


## This pilot's ship took a hit of `amount` (before the shields), of which
## `hull_dmg` reached the hull; `info` says what hit it.
func on_taken(info: DamageInfo, amount: float, hull_dmg: float) -> void:
	dmg_in += amount
	dmg_in_hull += hull_dmg
	if info.kind == Rules.W_COLLISION:
		dmg_in_crash += amount


## The page as plain data, ready for JSON.
func to_dict() -> Dictionary:
	var p := profile
	var flying := float(secs_in["flying"])
	var mins := maxf(flying / 60.0, 1.0 / 60.0)
	# The weapons, with a hit rate for each, and the totals without point
	# defence.
	var weapons_out := {}
	var shots := 0
	var hits := 0
	var dmg_out := 0.0
	for k: String in weapons:
		var w: Dictionary = weapons[k]
		weapons_out[k] = {"shots": int(w["shots"]), "hits": int(w["hits"]),
			"hit_rate": _ratio(float(w["hits"]), float(w["shots"])), "dmg": snappedf(float(w["dmg"]), 0.1)}
		dmg_out += float(w["dmg"])
		if k != "pd":
			shots += int(w["shots"])
			hits += int(w["hits"])
	var hulls_out := {}
	for h: String in hull_secs:
		hulls_out[h] = {"s": snappedf(float(hull_secs[h]), 0.1), "launches": int(hull_launches.get(h, 0))}
	var out := {
		"callsign": p.callsign, "team": Rules.TEAM_NAMES[p.team], "slot": p.slot, "role": p.role, "human": p.is_human,
		"kills": p.kills, "deaths": p.deaths, "assists": p.assists, "minion_kills": p.minion_kills, "monster_kills": p.monster_kills,
		"best_streak": p.best_streak, "credits_earned": snappedf(p.earned, 1.0),
		"time_s": {"flying": snappedf(flying, 0.1), "docked": snappedf(float(secs_in["docked"]), 0.1),
			"dead": snappedf(float(secs_in["dead"]), 0.1), "spooling": snappedf(float(secs_in["spooling"]), 0.1)},
		"launches": launches, "hulls": hulls_out,
		"weapons": weapons_out, "shots": shots, "hits": hits, "hit_rate": _ratio(float(hits), float(shots)),
		"hits_by_target": hits_by_target, "dmg_by_target": _snapped_map(dmg_by_target),
		"dmg_out": snappedf(dmg_out, 0.1), "dmg_out_per_min": snappedf(dmg_out / mins, 0.1),
		"dmg_in": snappedf(dmg_in, 0.1), "dmg_in_hull": snappedf(dmg_in_hull, 0.1), "dmg_in_crash": snappedf(dmg_in_crash, 0.1),
		"dmg_in_per_min": snappedf(dmg_in / mins, 0.1),
		"hit_dist_ship_mean": _ratio(dist_ship_sum, float(dist_ship_n), 1.0), "hit_dist_ship_n": dist_ship_n,
		"hit_dist_all_mean": _ratio(dist_all_sum, float(dist_all_n), 1.0), "hit_dist_all_n": dist_all_n,
		"hit_dist_ship_buckets": {"width": DIST_BUCKET, "counts": dist_hist},
	}
	# An AI pilot also says how good it is meant to be.
	if brain != null:
		out["skill"] = snappedf(brain.skill, 0.001)
		out["temperament"] = brain.temperament
	return out


## A few key numbers of the page (the totals so far), for the recorder's
## minute-by-minute history.
func brief() -> Dictionary:
	var d := to_dict()
	return {"flying_s": d["time_s"]["flying"], "shots": d["shots"], "hits": d["hits"], "hit_rate": d["hit_rate"],
		"dmg_out": d["dmg_out"], "dmg_in": d["dmg_in"], "kills": d["kills"], "deaths": d["deaths"], "assists": d["assists"]}


## The page for weapon kind `k`, made on first use.
func _weapon(k: String) -> Dictionary:
	if not weapons.has(k):
		weapons[k] = {"shots": 0, "hits": 0, "dmg": 0.0}
	return weapons[k]


## Write down the cooldown of each gun of `ship` as it is now.
func _remember_cooldowns(ship: Ship) -> void:
	_cds = []
	for m: WeaponMount in ship.mounts:
		_cds.append(m.cd)


## `a` divided by `b`, rounded to `step`; null when `b` is 0 (JSON then
## shows "null": nothing was measured).
func _ratio(a: float, b: float, step: float = 0.001) -> Variant:
	if b <= 0.0:
		return null
	return snappedf(a / b, step)


## A copy of `m` (name -> number) with every number rounded to one decimal.
func _snapped_map(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[k] = snappedf(float(m[k]), 0.1)
	return out
