extends "res://tests/hit_size_probe.gd"
## WHAT THIS IS: the check that the small pilot ships are 10% bigger for
## shots and no bigger anywhere else. It is the hit-size probe
## (tests/hit_size_probe.gd, whose measuring it reuses) with a verdict.
##
## HOW IT WORKS: it freezes the match, makes every pilot hull and every minion
## type, and asks the real game code how big each is for a round, a beam and
## a blast, how big its physics circle is and how close two ships of the hull
## can be before they are pushed apart (the probe's methods). It then checks:
##   - the four small pilot hulls (Scout, Fighter, Lance Fighter, Bomber) count
##     Rules.SMALL_PILOT_HIT_MUL times their radius for a round, a beam and a
##     blast, and hit_radius() says the same; a plain round that passes the
##     centre at 1.05 x radius plus the round's own radius hits, one that
##     passes at 1.15 x radius plus its own radius misses;
##   - their body does not change: the physics circle is the radius and two
##     ships are pushed apart at twice the radius;
##   - every other pilot hull and every minion type counts exactly its radius
##     (so a round that passes a minion Snub-Fighter at 1.05 x radius plus the
##     round's own radius misses).
## It prints one line per unit and then "hit_size_check: N failures" (0 means
## all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_size_check
##
## WHO USES IT: main.gd loads it for --test=hit_size_check; run_checks runs it.
## It changes only units of a frozen match that is thrown away.

## How close (world units) a measured size must be to the wanted one.
const TOLERANCE := 0.02
## How many things have gone wrong so far.
var failures := 0


## Check every unit, print the verdict and quit.
func _run() -> void:
	for _i in 5:
		await get_tree().process_frame
	_src = world.mothership(0)
	for hid: String in Ships.ORDER:
		var a := _launch(hid, 1)
		var b := _launch(hid, 0)
		_check_ship("ship:" + hid, a, b)
		_put(a)
		_put(b)
	for type_id: String in MINION_TYPES:
		var m := world.spawn_minion(1, type_id, "mid", _home)
		_check_minion("minion:" + type_id, m)
		_put(m)
	print("hit_size_check: %d failures" % failures)
	get_tree().quit()


## Count a failure and say what went wrong when `ok` is false.
func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("hit_size_check: FAIL %s" % what)


## Check pilot ship `a` (team 1) with its partner `b` (team 0, same hull).
func _check_ship(label: String, a: Ship, b: Ship) -> void:
	var small := a.size_class == Rules.SIZE_SMALL
	var want := a.radius * (Rules.SMALL_PILOT_HIT_MUL if small else 1.0)
	_place(a, _home)
	var shape := _shape_radius(a)
	var round_edge := _edge(a, "round")
	var beam_edge := _edge(a, "beam")
	var blast_edge := _edge(a, "blast")
	var push := _push_min_d(a, b)
	_expect(absf(a.hit_radius() - want) < 1e-6, "%s hit_radius %s, wanted %s" % [label, a.hit_radius(), want])
	_expect(absf(round_edge - want) < TOLERANCE, "%s round edge %s, wanted %s" % [label, round_edge, want])
	_expect(absf(beam_edge - want) < TOLERANCE, "%s beam edge %s, wanted %s" % [label, beam_edge, want])
	_expect(absf(blast_edge - want) < TOLERANCE, "%s blast edge %s, wanted %s" % [label, blast_edge, want])
	_expect(absf(shape - a.radius) < 1e-6, "%s physics circle %s, wanted %s" % [label, shape, a.radius])
	_expect(absf(push - 2.0 * a.radius) < TOLERANCE, "%s pushed apart at %s, wanted %s" % [label, push, 2.0 * a.radius])
	# A plain round passing at 1.05 x radius plus its own radius: it hits a
	# small pilot ship and misses every other.
	_place(a, _home)
	var near_hit := _touches(a, "round", a.radius * 1.05 + ROUND_RADIUS)
	_expect(near_hit == small, "%s a round at 1.05 x radius %s, wanted %s" % [label, "hit" if near_hit else "missed", "hit" if small else "missed"])
	# A round passing at 1.15 x radius plus its own radius misses every one.
	var far_hit := _touches(a, "round", a.radius * 1.15 + ROUND_RADIUS)
	_expect(not far_hit, "%s a round at 1.15 x radius hit" % label)
	print("hit_size_check: %s radius %s hit_radius %s shape %s push %s round %s beam %s blast %s" % [
		label, a.radius, a.hit_radius(), shape, push, round_edge, beam_edge, blast_edge])


## Check minion `m` (team 1): it counts exactly its radius.
func _check_minion(label: String, m: Minion) -> void:
	_place(m, _home)
	var round_edge := _edge(m, "round")
	var beam_edge := _edge(m, "beam")
	var blast_edge := _edge(m, "blast")
	_expect(absf(m.hit_radius() - m.radius) < 1e-6, "%s hit_radius %s, wanted %s" % [label, m.hit_radius(), m.radius])
	_expect(absf(round_edge - m.radius) < TOLERANCE, "%s round edge %s, wanted %s" % [label, round_edge, m.radius])
	_expect(absf(beam_edge - m.radius) < TOLERANCE, "%s beam edge %s, wanted %s" % [label, beam_edge, m.radius])
	_expect(absf(blast_edge - m.radius) < TOLERANCE, "%s blast edge %s, wanted %s" % [label, blast_edge, m.radius])
	var near_hit := _touches(m, "round", m.radius * 1.05 + ROUND_RADIUS)
	_expect(not near_hit, "%s a round at 1.05 x radius hit" % label)
	print("hit_size_check: %s radius %s hit_radius %s round %s beam %s blast %s" % [label, m.radius, m.hit_radius(), round_edge, beam_edge, blast_edge])
