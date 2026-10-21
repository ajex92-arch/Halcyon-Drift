extends RefCounted
## WHAT THIS IS: the fun probe's kill book. It reads every kill and asks:
## who or what killed this pilot ship, did enemy pilots take part, which
## ship size made the kill, was it near the killers' turrets or bays, and
## how many pilots helped? From that come the "pilots decide fights",
## "skill", "both sizes needed", "admiral assets" and "teamwork" numbers
## (docs/FUN_RESEARCH.md, fun model ingredients 6, 7, 8, 10 and 11).
##
## HOW IT WORKS:
##   - on_unit_killed() (every Events.unit_killed): a monster death is
##     counted (v1); a minion finished off by an enemy pilot is credited to
##     the size class of the ship that fired; a pilot ship death is sorted
##     by cause (v1: pilot, minion, turret, mothership, derelict, rock ...)
##     and studied. The kill event comes before the dead ship is removed,
##     so its damage log is still there: Economy.contributors(victim, 15 s,
##     10%) lists the pilots who did at least 10% of its damage in the last
##     15 s, exactly as the game pays assists.
##     "Involved": a contributor is an enemy pilot. "Assisted": a PILOT
##     kill (an enemy pilot made the killing blow) with 2+ enemy pilot
##     contributors. Helpers (contributors other than the killer, on the
##     other team) earn assists, as in Economy.
##   - Ship sizes: the killing blow's DamageInfo.source_size is the size of
##     the ship that fired it. A helper's size is the ship it flies (or last
##     flew: FunProbeTime.size_of()). Medium ships are left out of the size
##     comparison ("small" vs "big" = large + capital).
##   - on_credits(): turret bounties (reason "turret") count as a turret
##     participation and derelict rewards ("derelict") as a derelict kill,
##     for the size class the pilot flies.
##   - on_turret_destroyed(): a turret loss is "unattended" when no live
##     pilot ship of the destroying team was within 3,000 world units.
##   - Asset kills: the victim died within 2,000 of a killer-team turret,
##     within 1,400 of a killer-team repair bay or ward, or inside the
##     killer team's live waypoint circle.
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom.)
##
## WHO USES IT: tests/fun_probe.gd makes one and calls on_unit_killed(),
## on_credits() and on_turret_destroyed() from the game's events, then
## merges results() into FUN_JSON.

## Helper maths (ratios, rank correlation).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## The pilot time part (for size_of(): which size a pilot flies).
const TimePart := preload("res://tests/lib/fun_probe_time.gd")
## Match time (seconds) of 10:00: kills before it are "early" (pk_ramp).
const EARLY_T := 600.0
## Match time (seconds) of 25:00: kills from it on are "late" (pk_ramp,
## small_late_kill_share).
const LATE25_T := 1500.0
## Match time (seconds) of 30:00: deaths from it on are "late"
## (pilot_kill_share_late).
const LATE30_T := 1800.0
## The assist rule: hits in the last this many seconds...
const WINDOW := 15.0
## ...of at least this share of the damage (a 0..1 fraction).
const MIN_SHARE := 0.10
## A turret loss with no destroying-team pilot within this (world units)
## is "unattended".
const UNATTENDED_RANGE := 3000.0
## Asset kill: within this of a killer-team turret (world units)...
const ASSET_TURRET := 2000.0
## ...or within this of a killer-team repair bay or ward.
const ASSET_BAY_WARD := 1400.0
## Impact weights (size_parity): a pilot kill counts 1, and these the rest.
const W_ASSIST := 0.5
## Impact weight of a turret participation.
const W_TURRET := 1.5
## Impact weight of a minion last hit.
const W_MINION := 0.05
## Impact weight of a derelict kill.
const W_DERELICT := 0.1

## The pilot time part (set by _init).
var time_part: TimePart

# --- v1 ---------------------------------------------------------------------------

## Ship deaths by what killed them ("pilot", "minion", "turret", ...).
var deaths_by := {}
## How many pilot ships died in total.
var ship_deaths := 0
## Match time (seconds) of the first pilot killed by a pilot; -1 = none.
var first_blood := -1.0
## Match time (seconds) of the first ship destroyed by anything; -1 = none.
var first_death := -1.0
## Derelict monsters killed.
var monsters_killed := 0

# --- v2 counts ----------------------------------------------------------------------

## Ship deaths from 30:00 on, and how many of them pilots caused.
var deaths_late := 0
## Pilot-caused ship deaths from 30:00 on.
var pilot_deaths_late := 0
## Pilot kills: an enemy pilot made the killing blow.
var pilot_kills := 0
## Ship deaths with an enemy pilot among the 10% contributors.
var involved := 0
## Pilot kills with 2 or more enemy pilot contributors.
var assisted := 0
## Pilot kills before 10:00, and from 25:00 on.
var pk_early := 0
## Pilot kills from 25:00 on.
var pk_late := 0
## Pilot kills from 25:00 on made by small ships.
var small_late := 0
## Pilot kills made by big ships (large, capital).
var big_kills := 0
## Of those, killing blows from a flak or point-defense weapon.
var big_flak_pd := 0
## Pilot kills near the killers' turrets, bays, wards or waypoint.
var asset_kills := 0
## Turrets destroyed (both teams' losses).
var turret_losses := 0
## Turret losses with no destroying-team pilot near.
var unattended := 0
## Impact counts per size class index (small, medium, large, capital):
## pilot kills, assists, turret participations, minion last hits,
## derelict kills.
var by_size := {"kills": [0, 0, 0, 0], "assists": [0, 0, 0, 0], "turrets": [0, 0, 0, 0], "minions": [0, 0, 0, 0], "derelicts": [0, 0, 0, 0]}
## Per pilot, while flying a SMALL hull: kills, assists and deaths
## (PilotProfile -> count each).
var small_k := {}
## Small-hull assists per pilot.
var small_a := {}
## Small-hull deaths per pilot.
var small_d := {}


## Make the kill book; `tp` is the probe's pilot time part (for size_of()).
func _init(tp: TimePart) -> void:
	time_part = tp


## Add 1 to box `key` of `by_size` for size class `size` (ignored when the
## size is unknown, -1).
func _add_size(key: String, size: int) -> void:
	if size < 0:
		return
	var arr: Array = by_size[key]
	arr[Rules.size_index(size)] = int(arr[Rules.size_index(size)]) + 1


## Add 1 to pilot `p`'s count in `d`.
func _bump(d: Dictionary, p: PilotProfile) -> void:
	d[p] = int(d.get(p, 0)) + 1


## A unit died (Events.unit_killed): `u` is the unit, `d` the killing blow.
## See HOW IT WORKS.
func on_unit_killed(world: World, u: Unit, d: DamageInfo) -> void:
	# A monster: just count it (v1).
	if u.kind == Unit.K_MONSTER:
		monsters_killed += 1
		return
	# A minion finished off by an enemy pilot: a last hit for that ship size.
	if u.kind == Unit.K_MINION:
		var mk := d.source_profile as PilotProfile
		if mk != null and mk.team != u.team:
			_add_size("minions", d.source_size)
		return
	if u.kind == Unit.K_SHIP:
		_ship_died(world, u as Ship, d)


## A pilot ship `s` died from blow `d` (see HOW IT WORKS).
func _ship_died(world: World, s: Ship, d: DamageInfo) -> void:
	var now := world.time
	# Step 1 (v1): count it, note the first death, sort it by cause.
	ship_deaths += 1
	if first_death < 0.0:
		first_death = now
	var cause := _cause(d)
	if cause == "pilot" and first_blood < 0.0:
		first_blood = now
	deaths_by[cause] = int(deaths_by.get(cause, 0)) + 1
	if now >= LATE30_T:
		deaths_late += 1
		if cause == "pilot":
			pilot_deaths_late += 1
	# Step 2: the 10% contributors (Economy's assist rule) and the helpers.
	var killer := d.source_profile as PilotProfile
	var who := Economy.contributors(world, s, WINDOW, MIN_SHARE)
	var enemy_pilots := 0
	for p: PilotProfile in who:
		if p.team != s.team:
			enemy_pilots += 1
			if p != killer:
				var hs := time_part.size_of(p)
				_add_size("assists", hs)
				if hs == Rules.SIZE_SMALL:
					_bump(small_a, p)
	if enemy_pilots > 0:
		involved += 1
	# Step 3: the victim's small-hull death (skill_rho_small).
	if s.profile != null and s.size_class == Rules.SIZE_SMALL:
		_bump(small_d, s.profile)
	# Step 4: pilot kills only from here on.
	if killer == null or killer.team == s.team:
		return
	pilot_kills += 1
	if enemy_pilots >= 2:
		assisted += 1
	_add_size("kills", d.source_size)
	if d.source_size == Rules.SIZE_SMALL:
		_bump(small_k, killer)
	# Step 5: early/late kills, big-ship flak and point-defense kills, and
	# kills near the killers' assets.
	if now < EARLY_T:
		pk_early += 1
	if now >= LATE25_T:
		pk_late += 1
		if d.source_size == Rules.SIZE_SMALL:
			small_late += 1
	if d.source_size >= Rules.SIZE_LARGE:
		big_kills += 1
		if d.kind == Rules.W_FLAK or d.kind == Rules.W_PD:
			big_flak_pd += 1
	if _near_asset(world, s.global_position, killer.team):
		asset_kills += 1


## What killed a ship (v1 words): "pilot", "rock" (a crash), or the kind of
## unit that fired: "minion", "turret", "mothership", "derelict",
## "repair_bay", or "other".
func _cause(d: DamageInfo) -> String:
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


## Did a ship die at `p` near team `team`'s assets: a turret within 2,000,
## a repair bay or ward within 1,400, or inside its live waypoint circle?
func _near_asset(world: World, p: Vector2, team: int) -> bool:
	for tu: Turret in world.turrets:
		if tu.alive and tu.team == team and tu.global_position.distance_to(p) <= ASSET_TURRET:
			return true
	for b: RepairBay in world.bays:
		if b.alive and b.team == team and b.global_position.distance_to(p) <= ASSET_BAY_WARD:
			return true
	for w: Ward in world.wards:
		if w.alive and w.team == team and w.global_position.distance_to(p) <= ASSET_BAY_WARD:
			return true
	return world.teams[team].in_waypoint(p)


## A pilot was paid (Events.credits_earned): turret bounties and derelict
## rewards count for the size class the pilot flies.
func on_credits(p: PilotProfile, reason: String) -> void:
	if reason == "turret":
		_add_size("turrets", time_part.size_of(p))
	elif reason == "derelict":
		_add_size("derelicts", time_part.size_of(p))


## A turret was destroyed (Events.turret_destroyed) by team `by_team`: was
## any of that team's pilots within 3,000?
func on_turret_destroyed(world: World, turret: Node2D, by_team: int) -> void:
	turret_losses += 1
	for s: Ship in world.ships:
		if s.alive and s.team == by_team and s.global_position.distance_to(turret.global_position) <= UNATTENDED_RANGE:
			return
	unattended += 1


## A size class's impact: pilot kills + 0.5 x assists + 1.5 x turret
## participations + 0.05 x minion last hits + 0.1 x derelict kills, summed
## over the size class indexes in `idx`.
func _impact(idx: Array) -> float:
	var total := 0.0
	for i: int in idx:
		total += float(by_size["kills"][i]) + W_ASSIST * float(by_size["assists"][i]) + W_TURRET * float(by_size["turrets"][i])
		total += W_MINION * float(by_size["minions"][i]) + W_DERELICT * float(by_size["derelicts"][i])
	return total


## The low-kill-participation count: per team, the pilots whose (kills +
## assists) / (the team's pilot kills) is under 0.08; the mean of both
## teams. `pilots` = the AI pilots.
func _low_kp(world: World, pilots: Array) -> float:
	var low := [0, 0]
	for p: PilotProfile in pilots:
		if p.team < 0 or p.team > 1:
			continue
		var team_kills := maxf(1.0, float(world.teams[p.team].kills))
		if float(p.kills + p.assists) / team_kills < 0.08:
			low[p.team] = int(low[p.team]) + 1
	return (float(low[0]) + float(low[1])) * 0.5


## Everything this part measured, for FUN_JSON. `pilots` = the AI pilots,
## `skills` = their PilotAI.skill (same order), `size_minutes` = minutes
## flown per size class index, `early_min` / `late_min` = minutes watched
## before 10:00 and from 25:00 on (for pk_ramp's kills per pilot-minute).
func results(world: World, pilots: Array, skills: Array, size_minutes: Array, early_min: float, late_min: float) -> Dictionary:
	# Step 1: skill_rho_small: skill against the small-hull score
	# (kills + 0.5 x assists) / (deaths + 1).
	var scores: Array = []
	for p: PilotProfile in pilots:
		scores.append((float(small_k.get(p, 0)) + 0.5 * float(small_a.get(p, 0))) / (float(small_d.get(p, 0)) + 1.0))
	# Step 2: size parity: impact per pilot-minute, small vs big.
	var sm := float(size_minutes[0])
	var mm := float(size_minutes[1])
	var bm := float(size_minutes[2]) + float(size_minutes[3])
	var rate_s: Variant = FunStats.ratio(_impact([0]), sm)
	var rate_b: Variant = FunStats.ratio(_impact([2, 3]), bm)
	var parity: Variant = null
	if typeof(rate_s) != TYPE_NIL and typeof(rate_b) != TYPE_NIL and float(rate_s) > 0.0 and float(rate_b) > 0.0:
		parity = absf(log(float(rate_s) / float(rate_b)) / log(2.0))
	# Step 3: pk_ramp: pilot kills per pilot-minute late / early.
	var n := float(pilots.size())
	var pk_e: Variant = FunStats.ratio(float(pk_early), n * early_min)
	var pk_l: Variant = FunStats.ratio(float(pk_late), n * late_min)
	var ramp: Variant = null
	if typeof(pk_e) != TYPE_NIL and typeof(pk_l) != TYPE_NIL and float(pk_e) > 0.0:
		ramp = float(pk_l) / float(pk_e)
	return {
		"ship_deaths": ship_deaths,
		"deaths_by": deaths_by,
		"pilot_kill_share": snappedf(float(int(deaths_by.get("pilot", 0))) / maxf(1.0, float(ship_deaths)), 0.001),
		"first_death_min": snappedf(first_death / 60.0, 0.01) if first_death >= 0.0 else -1.0,
		"first_blood_min": snappedf(first_blood / 60.0, 0.01) if first_blood >= 0.0 else -1.0,
		"monsters_killed": monsters_killed,
		"deaths_late": deaths_late,
		"pilot_kill_share_late": FunStats.snap(FunStats.ratio(float(pilot_deaths_late), float(deaths_late)), 0.001),
		"pilot_involved_death_share": FunStats.snap(FunStats.ratio(float(involved), float(ship_deaths)), 0.001),
		"turret_losses": turret_losses,
		"unattended_turret_losses": unattended,
		"unattended_turret_loss_share": FunStats.snap(FunStats.ratio(float(unattended), float(turret_losses)), 0.001),
		"skill_rho_small": FunStats.snap(FunStats.spearman(skills, scores), 0.001),
		"size_impact": {
			"small": {"impact": snappedf(_impact([0]), 0.01), "minutes": snappedf(sm, 0.01)},
			"medium": {"impact": snappedf(_impact([1]), 0.01), "minutes": snappedf(mm, 0.01)},
			"big": {"impact": snappedf(_impact([2, 3]), 0.01), "minutes": snappedf(bm, 0.01)},
		},
		"size_parity": FunStats.snap(parity, 0.001),
		"big_pilot_kills": big_kills,
		"big_flak_pd_kills": big_flak_pd,
		"big_flak_pd_kill_share": FunStats.snap(FunStats.ratio(float(big_flak_pd), float(big_kills)), 0.001),
		"pilot_kills_late25": pk_late,
		"small_kills_late25": small_late,
		"small_late_kill_share": FunStats.snap(FunStats.ratio(float(small_late), float(pk_late)), 0.001),
		"pk_early": pk_early,
		"pk_ramp": FunStats.snap(ramp, 0.001),
		"pilot_kills": pilot_kills,
		"assisted_kills": assisted,
		"assisted_kill_share": FunStats.snap(FunStats.ratio(float(assisted), float(pilot_kills)), 0.001),
		"asset_kills": asset_kills,
		"asset_kill_share": FunStats.snap(FunStats.ratio(float(asset_kills), float(pilot_kills)), 0.001),
		"low_kp_pilots": _low_kp(world, pilots),
	}


## Pilot `p`'s small-hull kills, assists and deaths, as [k, a, d] (for the
## per-pilot table).
func small_counts(p: PilotProfile) -> Array:
	return [int(small_k.get(p, 0)), int(small_a.get(p, 0)), int(small_d.get(p, 0))]
