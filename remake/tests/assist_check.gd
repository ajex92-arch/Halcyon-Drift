extends Node
## WHAT THIS IS: the exact check for assist money (T-25).
## It sets up kills one at a time in a small world, lets Economy pay them,
## and checks the payouts to the cent: what the last hitter gets, what the
## helpers get, and that the total paid is exactly the bounty (never more).
##
## HOW IT WORKS: for each case it makes the pilots (plain records, they need
## no ship), writes who hurt the victim into the victim's damage log (hits
## from pilots, with how much damage and how many seconds ago), and calls
## Economy.on_unit_killed() with a killing blow from a pilot, a minion or a
## turret. It listens to Events.credits_earned, adds up what each pilot was
## paid per reason, and compares it with the amounts the rule says. All the
## checks are made before the gear bonus ("bounty_pct"), except the cases
## that give a pilot the Salvager's Helm (+15%) on purpose, to show that each
## pilot's own cut is multiplied by their own gear and nobody else's. The last
## cases are end to end: real ships and real hits, and the kill comes out of
## the normal damage code.
##   - Minion (bomber, 18 credits; patrol leader, 45): the last hitter alone
##     gets all of it; with one or two helpers 75% / 25%, the helpers' part
##     split by their damage; a hit under 10% of the damage, or older than 15 s,
##     does not make a helper; a minion finished by a minion, a turret, or a
##     pilot of its own team pays nobody.
##   - Pilot kill: the killer alone gets the whole bounty; with helpers the
##     killer gets two thirds and the helpers share one third in equal parts,
##     and the total is exactly the bounty (also with a kill streak); a kill
##     finished by a turret or a minion gives the helpers the whole bounty.
##   - The counters: kills, assists, minion_kills, minion_assists.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=assist_check
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <case> <details>" or
## "FAIL <case> <details>" (the details are "pilot reason got/wanted"). The
## last line is "assist_check: N failures (M checks)"; 0 failures means the
## rule pays exactly as written.
##
## WHO USES IT: main.gd loads it for --test=assist_check. It is one of the
## checks of the Feature lane for anything that changes who is paid.

## A payout may differ from the wanted amount by this much (credits), for
## rounding in floating point numbers.
const EPS := 0.0001

## The running match (set by setup()).
var world: World
## How many checks failed.
var fails := 0
## How many checks were made.
var checks := 0
## True once the cases have run (they all run in the first tick).
var _ran := false
## What each pilot was paid in the case that is running: profile -> reason -> credits.
var _paid := {}
## The id number used in damage logs for each pilot: profile -> uid.
var _uids := {}
## The next id number to give out (far above the ids of real units).
var _next_uid := 90000
## A Vhorr ship that plays the victim in the pilot-kill cases.
var _victim_ship: Ship = null
## The Salvager's Helm: the gear item with +15% on every kill reward.
const HELM := "helm_salvager"


## main.gd calls this once, right after the World is built. Stop the minion
## waves and listen to the payments.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	Events.credits_earned.connect(_on_paid)


## A pilot was paid: add it to what that pilot has been paid in this case.
func _on_paid(p: RefCounted, amount: float, reason: String) -> void:
	if not _paid.has(p):
		_paid[p] = {}
	var d: Dictionary = _paid[p]
	d[reason] = float(d.get(reason, 0.0)) + amount


## Run every case in the first tick, print the result and quit.
func _physics_process(_dt: float) -> void:
	if _ran or world == null:
		return
	_ran = true
	_check("early in the match (no minion bounty growth yet)", world.time < 300.0, "t=%.2f" % world.time)
	_victim_ship = _spawn_ship("Victim", 1)
	_minion_cases()
	_ship_cases()
	_gear_cases()
	_end_to_end()
	print("assist_check: %d failures (%d checks)" % [fails, checks])
	get_tree().quit()


# --- helpers for the cases ---------------------------------------------------------

## Print one PASS or FAIL line for the check `name` (`ok` = it passed), with
## the `detail`, and count it.
func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## A new pilot record `name` of team `team`. It has no ship; its id number is
## made when it first hits something.
func _pilot(name: String, team: int) -> PilotProfile:
	return PilotProfile.new(name, team, 40 + _uids.size(), false)


## The id number that pilot `p`'s hits carry in a damage log.
func _uid(p: PilotProfile) -> int:
	if not _uids.has(p):
		_uids[p] = _next_uid
		_next_uid += 1
	return _uids[p]


## Give pilot `p` the Salvager's Helm (+15% on kill rewards).
func _give_helm(p: PilotProfile) -> void:
	p.inventory[0] = {"id": HELM, "count": 1}
	p.gear_changed()


## Launch a still ship for a new pilot `name` of team `team` (in a Fighter),
## and return the ship.
func _spawn_ship(name: String, team: int) -> Ship:
	var p := PilotProfile.new(name, team, 40 + world.profiles.size(), false)
	p.hull_id = "fighter"
	world.profiles.append(p)
	var s := world.launch(p)
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## Write into `victim`'s damage log that pilot `p` did `dmg` damage, `age`
## seconds ago.
func _hit(victim: Unit, p: PilotProfile, dmg: float, age: float = 0.0) -> void:
	victim.damage_log[_uid(p)] = [dmg, world.time - age, p]


## Write into the log damage from something that is not a pilot (a turret):
## it counts in the total damage, but nobody is paid for it.
func _hit_turret(victim: Unit, dmg: float) -> void:
	victim.damage_log[99990] = [dmg, world.time, null]


## The killing blow. `who` is a PilotProfile (a pilot's blow), "minion" (a
## minion's) or "turret" (a turret's). The last two carry no pilot profile,
## which is how Economy tells that no pilot made the last hit.
func _blow(who: Variant) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = 1.0
	d.kind = Rules.W_PURE
	if who is PilotProfile:
		var p: PilotProfile = who
		d.source_uid = _uid(p)
		d.source_team = p.team
		d.source_is_pilot = true
		d.source_profile = p
	elif str(who) == "minion":
		d.source_uid = 99991
		d.source_team = 0
		d.source_is_minion = true
	else:
		d.source_uid = 99992
		d.source_team = 0
	return d


## What `p` was paid for `reason` in this case (0 if nothing).
func _got(p: PilotProfile, reason: String) -> float:
	if not _paid.has(p):
		return 0.0
	return float((_paid[p] as Dictionary).get(reason, 0.0))


## Compare what was paid in this case with `want` (profile -> reason ->
## fraction of `base`), and print one line. Every payment must be wanted, and
## every wanted payment must be there. A fraction of 0 means "must not be paid".
func _compare(label: String, base: float, want: Dictionary) -> void:
	var ok := true
	var parts := PackedStringArray()
	var total := 0.0
	for p: PilotProfile in want:
		for reason: String in want[p]:
			var wanted := base * float(want[p][reason])
			var got := _got(p, reason)
			if absf(got - wanted) > EPS:
				ok = false
			parts.append("%s %s %.3f/%.3f" % [p.callsign, reason, got, wanted])
	for p: PilotProfile in _paid:
		for reason: String in _paid[p]:
			total += float(_paid[p][reason])
			if not (want.has(p) and (want[p] as Dictionary).has(reason)):
				ok = false
				parts.append("UNEXPECTED %s %s %.3f" % [p.callsign, reason, float(_paid[p][reason])])
	parts.append("total %.3f of %.3f" % [total, base])
	_check(label, ok, "; ".join(parts))


## Compare the score counters of pilot `p`: kills, assists, last hits on
## minions and minion assists.
func _counts(label: String, p: PilotProfile, kills: int, assists: int, minion_kills: int, minion_assists: int) -> void:
	var ok := p.kills == kills and p.assists == assists and p.minion_kills == minion_kills and p.minion_assists == minion_assists
	_check(label, ok, "%s kills %d/%d assists %d/%d minion_kills %d/%d minion_assists %d/%d" % [p.callsign, p.kills, kills, p.assists, assists, p.minion_kills, minion_kills, p.minion_assists, minion_assists])


## Make a Vhorr minion of type `type_id` to be the victim.
func _minion(type_id: String) -> Minion:
	return world.spawn_minion(1, type_id, "mid", world.mothership(1).global_position)


## Pay the kill of `victim` for blow `who` and drop the minion if it is one.
func _kill(victim: Unit, who: Variant) -> void:
	Economy.on_unit_killed(world, victim, _blow(who))
	if victim.kind == Unit.K_MINION:
		world.combat.kill_silently(victim)


# --- the minion cases -------------------------------------------------------------

## Last hit on minions: alone, with one and two helpers, and the cases that
## pay nobody.
func _minion_cases() -> void:
	# The last hitter alone gets all of it (a bomber pays 18).
	var a := _pilot("A", 0)
	var m := _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_kill(m, a)
	_compare("minion: last hitter alone gets all", 18.0, {a: {"minion": 1.0}})
	_counts("minion: counters, last hitter alone", a, 0, 0, 1, 0)

	# One helper: 75% / 25%, the total is exactly the bounty.
	a = _pilot("A", 0)
	var b := _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 60.0)
	_kill(m, a)
	_compare("minion: one helper, 75% / 25%", 18.0, {a: {"minion": 0.75}, b: {"minion assist": 0.25}})
	_counts("minion: counters, killer", a, 0, 0, 1, 0)
	_counts("minion: counters, helper (minion_assists, not assists)", b, 0, 0, 0, 1)

	# Two helpers: the 25% is split by their damage (60 and 20 of the 80).
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	var c := _pilot("C", 0)
	m = _minion("corvette")
	_paid.clear()
	_hit(m, a, 20.0)
	_hit(m, b, 60.0)
	_hit(m, c, 20.0)
	_kill(m, a)
	_compare("minion: two helpers, 75% / 25% split by damage", 45.0, {a: {"minion": 0.75}, b: {"minion assist": 0.25 * 60.0 / 80.0}, c: {"minion assist": 0.25 * 20.0 / 80.0}})
	_counts("minion: counters, helper B", b, 0, 0, 0, 1)
	_counts("minion: counters, helper C", c, 0, 0, 0, 1)

	# A hit under 10% of the damage is not help: the last hitter keeps all.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 95.0)
	_hit(m, b, 5.0)
	_kill(m, a)
	_compare("minion: a hit under 10% is not a helper", 18.0, {a: {"minion": 1.0}})
	_counts("minion: counters, the small hitter", b, 0, 0, 0, 0)

	# A hit older than 15 s is not help either.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 50.0)
	_hit(m, b, 50.0, 20.0)
	_kill(m, a)
	_compare("minion: a hit 20 s ago is not a helper", 18.0, {a: {"minion": 1.0}})

	# A hit by a pilot of the minion's own team is not an assist and not a kill.
	var own := _pilot("Own", 1)
	a = _pilot("A", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 50.0)
	_kill(m, own)
	_compare("minion: finished by a pilot of its own team pays nobody", 18.0, {})

	# Finished by a minion: nobody is paid, even though pilots hurt it.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 60.0)
	_kill(m, "minion")
	_compare("minion: finished by a minion pays nobody", 18.0, {})
	_counts("minion: counters, nobody scores", a, 0, 0, 0, 0)

	# Finished by a turret: nobody is paid either.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 30.0)
	_hit_turret(m, 30.0)
	_kill(m, "turret")
	_compare("minion: finished by a turret pays nobody", 18.0, {})

	# A turret's damage counts in the total: A 40, B 10, turret 50 -> B has
	# exactly 10% and is a helper; with a turret share of 55 B would not be.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 10.0)
	_hit_turret(m, 50.0)
	_kill(m, a)
	_compare("minion: a turret's damage counts in the total (B has exactly 10%)", 18.0, {a: {"minion": 0.75}, b: {"minion assist": 0.25}})
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 9.0)
	_hit_turret(m, 51.0)
	_kill(m, a)
	_compare("minion: a turret's damage counts in the total (B has 9%)", 18.0, {a: {"minion": 1.0}})


# --- the pilot-kill cases ---------------------------------------------------------

## The bounty of the victim ship now (Rules.KILL_BASE plus its share of the
## ship's value, plus 50 for each kill of its streak after the first).
func _bounty() -> float:
	var v := _victim_ship.profile
	return Rules.KILL_BASE + _victim_ship.bounty_value() * Rules.KILL_VALUE_SHARE + Rules.SHUTDOWN_PER_STREAK * float(maxi(0, v.streak - 1))


## Pilot kills: alone, with one and two helpers, with a streak, and finished
## by a turret or a minion.
func _ship_cases() -> void:
	var v := _victim_ship
	# The killer alone gets the whole bounty.
	var a := _pilot("A", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 100.0)
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("pilot kill: killer alone gets the whole bounty", _bounty(), {a: {"kill": 1.0}})
	_counts("pilot kill: counters, killer alone", a, 1, 0, 0, 0)

	# One helper: 2/3 and 1/3, exactly the bounty.
	a = _pilot("A", 0)
	var b := _pilot("B", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 70.0)
	_hit(v, b, 30.0)
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("pilot kill: one helper, killer 2/3 and helper 1/3", _bounty(), {a: {"kill": 2.0 / 3.0}, b: {"assist": 1.0 / 3.0}})
	_counts("pilot kill: counters, killer", a, 1, 0, 0, 0)
	_counts("pilot kill: counters, helper (assists, not minion_assists)", b, 0, 1, 0, 0)

	# Two helpers: the third is split in equal parts, whatever their damage.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	var c := _pilot("C", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 30.0)
	_hit(v, b, 60.0)
	_hit(v, c, 10.0)
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("pilot kill: two helpers, killer 2/3 and 1/6 each", _bounty(), {a: {"kill": 2.0 / 3.0}, b: {"assist": 1.0 / 6.0}, c: {"assist": 1.0 / 6.0}})

	# A hit under 10% is not help.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 95.0)
	_hit(v, b, 5.0)
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("pilot kill: a hit under 10% is not a helper", _bounty(), {a: {"kill": 1.0}})

	# A kill streak: the shutdown bonus is part of the bounty, and the total
	# paid is still exactly the bounty.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	v.damage_log.clear()
	v.profile.streak = 4
	_paid.clear()
	_hit(v, a, 50.0)
	_hit(v, b, 50.0)
	var streak_bounty := _bounty()
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("pilot kill: victim on a 4-kill streak, still exactly the bounty", streak_bounty, {a: {"kill": 2.0 / 3.0}, b: {"assist": 1.0 / 3.0}})
	_check("pilot kill: the streak ended and the death counted", v.profile.streak == 0 and v.profile.deaths > 0, "streak %d deaths %d" % [v.profile.streak, v.profile.deaths])
	_counts("pilot kill: counters, killer streak", a, 1, 0, 0, 0)
	_check("pilot kill: killer's streak is 1", a.streak == 1, "streak %d" % a.streak)

	# Finished by a turret: the helpers share the whole bounty, equally.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 40.0)
	_hit(v, b, 40.0)
	_hit_turret(v, 20.0)
	Economy.on_unit_killed(world, v, _blow("turret"))
	_compare("pilot kill: finished by a turret, the helpers share the whole bounty", _bounty(), {a: {"assist": 0.5}, b: {"assist": 0.5}})
	_counts("pilot kill: counters, turret kill helper", a, 0, 1, 0, 0)

	# Finished by a minion, one helper: the helper gets the whole bounty.
	b = _pilot("B", 0)
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, b, 80.0)
	Economy.on_unit_killed(world, v, _blow("minion"))
	_compare("pilot kill: finished by a minion, one helper gets the whole bounty", _bounty(), {b: {"assist": 1.0}})

	# Finished by a turret with nobody helping: nobody is paid.
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit_turret(v, 100.0)
	Economy.on_unit_killed(world, v, _blow("turret"))
	_compare("pilot kill: finished by a turret with no pilot damage pays nobody", _bounty(), {})


# --- gear -------------------------------------------------------------------------

## Each pilot's cut is raised by their own gear, and only theirs.
func _gear_cases() -> void:
	# Minion: the helper has the helm, the killer has none.
	var a := _pilot("A", 0)
	var b := _pilot("B", 0)
	_give_helm(b)
	var m := _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 60.0)
	_kill(m, a)
	_compare("gear: minion, only the helper has the helm", 18.0, {a: {"minion": 0.75}, b: {"minion assist": 0.25 * 1.15}})
	# Minion: the killer has the helm, the helper has none.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	_give_helm(a)
	m = _minion("bomber")
	_paid.clear()
	_hit(m, a, 40.0)
	_hit(m, b, 60.0)
	_kill(m, a)
	_compare("gear: minion, only the killer has the helm", 18.0, {a: {"minion": 0.75 * 1.15}, b: {"minion assist": 0.25}})
	# Pilot kill: the helper has the helm.
	a = _pilot("A", 0)
	b = _pilot("B", 0)
	_give_helm(b)
	var v := _victim_ship
	v.damage_log.clear()
	v.profile.streak = 0
	_paid.clear()
	_hit(v, a, 50.0)
	_hit(v, b, 50.0)
	Economy.on_unit_killed(world, v, _blow(a))
	_compare("gear: pilot kill, only the helper has the helm", _bounty(), {a: {"kill": 2.0 / 3.0}, b: {"assist": 1.0 / 3.0 * 1.15}})


# --- end to end -------------------------------------------------------------------

## Real ships and real hits: the kill comes out of the normal damage code
## (Combat.apply_damage), and the pay is what the rule says.
func _end_to_end() -> void:
	# A real minion (a patrol leader, 45): pilot B hurts it down to half, pilot
	# A finishes it. B is the only helper.
	var ship_a := _spawn_ship("E-A", 0)
	var ship_b := _spawn_ship("E-B", 0)
	var m := _minion("corvette")
	var at := m.global_position + Vector2(200.0, 0.0)
	_paid.clear()
	var n := 0
	while m.alive and m.hull > m.hull_max * 0.5 and n < 2000:
		world.combat.apply_damage(m, DamageInfo.from_unit(ship_b, 30.0, Rules.W_PURE, at))
		n += 1
	n = 0
	while m.alive and n < 2000:
		world.combat.apply_damage(m, DamageInfo.from_unit(ship_a, 15.0, Rules.W_PURE, at))
		n += 1
	_check("end to end: the minion died", not m.alive, "%d hits" % n)
	_compare("end to end: real minion kill, killer 75% and helper 25%", 45.0, {ship_a.profile: {"minion": 0.75}, ship_b.profile: {"minion assist": 0.25}})
	_counts("end to end: counters, killer", ship_a.profile, 0, 0, 1, 0)
	_counts("end to end: counters, helper", ship_b.profile, 0, 0, 0, 1)

	# A real pilot ship (a Vhorr Fighter): B hurts it down to half, A finishes it.
	var victim := _spawn_ship("E-V", 1)
	var bounty := Rules.KILL_BASE + victim.bounty_value() * Rules.KILL_VALUE_SHARE
	at = victim.global_position + Vector2(200.0, 0.0)
	_paid.clear()
	n = 0
	while victim.alive and victim.hull_frac() > 0.5 and n < 4000:
		world.combat.apply_damage(victim, DamageInfo.from_unit(ship_b, 25.0, Rules.W_PURE, at))
		n += 1
	n = 0
	while victim.alive and n < 4000:
		world.combat.apply_damage(victim, DamageInfo.from_unit(ship_a, 12.0, Rules.W_PURE, at))
		n += 1
	_check("end to end: the pilot ship died", not victim.alive, "%d hits" % n)
	_compare("end to end: real pilot kill, killer 2/3 and helper 1/3", bounty, {ship_a.profile: {"kill": 2.0 / 3.0}, ship_b.profile: {"assist": 1.0 / 3.0}})
	_counts("end to end: counters, killer (one minion last hit, one kill)", ship_a.profile, 1, 0, 1, 0)
	_counts("end to end: counters, helper (one minion assist, one assist)", ship_b.profile, 0, 1, 0, 1)
