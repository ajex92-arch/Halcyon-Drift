extends Node
## WHAT THIS IS: the scripted check of the admiral_command fork's feature
## modules (scripts/features/): Sensor Sweep, Supply Drop, Barrage, Bounty,
## Fortify, the mothership move rules and Mutiny. It plays the HUMAN
## admiral's part, giving every order through CommandOrders.run() exactly as
## the board's buttons and map tools do, and checks the results. (The AI
## admirals' use of the same orders is shown by the usage counters of the
## smoke matches, not here.) Checks for a feature that is not switched on
## are skipped, so one run tests whatever the --variant list switches on.
##
## HOW IT WORKS: setup() starts run(), a coroutine (a function that can
## stop and wait with `await`) that runs the checks one after another,
## waiting game time between them (wait()), and prints a PASS or FAIL line
## for each. Test ships are launched with no brain, so they stand still.
## It ends with "admiral_fork_probe: N failures" and quits.
##
## HOW TO RUN IT (from the fork's folder):
##   godot --headless --path . --fixed-fps 60 -- --all-ai --seed=7 --no-pilots --no-jungle --no-admiral-ai --test=admiral_fork_probe --variant=assets:full,orders:on,fortify:on,ms_move:both,mutiny:on
## (also with --variant=assets:xray to check the see-through-asteroids
## Sweep). Both flags and the list may be changed; a feature that is not in
## the list is skipped.
##
## WHO USES IT: main.gd loads it for --test=admiral_fork_probe (tests/<name>.gd,
## added after the World, then setup() is called). The lead runs it through
## the shared queue (run_batch.ps1 -Test admiral_fork_probe).

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## A test spot in open space (world units), where Halcyon test ships stand.
const SPOT := Vector2(9000, 13000)


## main.gd calls this once, right after the World is built: stop the minion
## waves, make Halcyon rich and start the checks.
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	world.teams[0].treasury = 20000.0
	run()


## Print one PASS or FAIL line for check `name` and count the failures.
func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Wait `secs` seconds of game time (physics frames).
func wait(secs: float) -> void:
	var end := world.time + secs
	while world.time < end:
		await get_tree().physics_frame


## Launch a test ship of hull `hid` for team `team` at `at`, standing still
## and with no brain. Returns the ship.
func spawn(hid: String, team: int, at: Vector2) -> Ship:
	var p := PilotProfile.new("Test-" + hid, team, 40 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## The usage count of `key` so far (0 if none).
func used(key: String) -> int:
	return int(Game.usage.get(key, 0))


## The direction (a length-1 arrow) from `p` toward the middle of the map, so
## that a test ship placed that way stays inside the map.
func toward_center(p: Vector2) -> Vector2:
	return (Vector2(MapLayout.W, MapLayout.H) * 0.5 - p).normalized()


## Deal `amount` of "pure" damage to `u`, shot by `src` (a ship, so that the
## shooter's pilot counts as a damager).
func hit(u: Unit, amount: float, src: Unit) -> void:
	var info := DamageInfo.from_unit(src, amount, Rules.W_PURE, u.global_position + Vector2(200, 0))
	world.combat.apply_damage(u, info)


## A test layout for the sweep: a viewer position A, a sweep spot S that A
## sees (1,500 away, clear line), and an enemy spot E 3,000 beyond S that A
## can not see by itself (more than 2,700 from A). With `want_blocked` the
## line S-E must cross a rock, else it must be clear. Returns [A, S, E] or
## an empty list when this map has no such place among the candidates.
func find_layout(want_blocked: bool) -> Array:
	var spots := [SPOT, Vector2(20000, 13000), Vector2(30000, 13000), Vector2(14000, 6000), Vector2(14000, 20000), Vector2(26000, 6000), Vector2(26000, 20000)]
	for a: Vector2 in spots:
		for k in 8:
			var s: Vector2 = a + Vector2.from_angle(TAU * float(k) / 8.0) * 1500.0
			if world.asteroids.blocked(s, 40.0) or world.asteroids.segment_blocked(a, s):
				continue
			for j in 16:
				var e: Vector2 = s + Vector2.from_angle(TAU * float(j) / 16.0) * 3000.0
				if e.x < 600.0 or e.y < 600.0 or e.x > MapLayout.W - 600.0 or e.y > MapLayout.H - 600.0:
					continue
				if world.asteroids.blocked(e, 40.0) or e.distance_to(a) < 2700.0:
					continue
				if world.asteroids.segment_blocked(s, e) == want_blocked:
					return [a, s, e]
	return []


## The checks, in order (see the top).
func run() -> void:
	await get_tree().physics_frame
	var orders: Dictionary = world.command.orders
	# --- the orders exist ---------------------------------------------------------------
	for key in ["assets", "orders", "fortify"]:
		if world.features.has(key):
			check("feature installed: " + key, true)
	if orders.is_empty() and not world.features.has("ms_move") and not world.features.has("mutiny"):
		check("some feature is on (pass --variant=...)", false)
	if orders.has("sweep"):
		await check_sweep()
	if orders.has("supply"):
		await check_supply()
	if orders.has("barrage"):
		await check_barrage()
	if orders.has("bounty"):
		await check_bounty()
	if orders.has("fortify"):
		await check_fortify()
	if world.features.has("ms_move"):
		check_ms_move()
	if world.features.has("mutiny"):
		check_mutiny()
	print("admiral_fork_probe: %d failures" % fails)
	get_tree().quit()


## Sensor Sweep: it lights the fog around its spot (rocks block it, unless
## the variant is "xray"), costs 250 and then recharges.
func check_sweep() -> void:
	var xray := Game.variant("assets") == "xray"
	var layout := find_layout(xray)
	if layout.is_empty():
		check("sweep layout found (%s)" % ("rock between" if xray else "clear line"), false, "no such place on the map")
		return
	var a: Vector2 = layout[0]
	var s: Vector2 = layout[1]
	var e: Vector2 = layout[2]
	var me := spawn("fighter", 0, a)
	var enemy := spawn("fighter", 1, e)
	await wait(1.0)
	check("sweep: enemy not seen before the sweep", not enemy.visible_to(0))
	var before := world.teams[0].treasury
	var msg := CommandOrders.run(world, "sweep", 0, s)
	check("sweep: order accepted", msg == "", msg)
	check("sweep: costs 250", absf(before - world.teams[0].treasury - 250.0) < 1.0)
	await wait(1.0)
	# With "xray" the sweep sees through the rock; otherwise the case tested
	# has a clear line, so the enemy is seen either way.
	check("sweep: enemy seen during the sweep (%s)" % ("through a rock" if xray else "clear line"), enemy.visible_to(0))
	check("sweep: a second sweep is refused (recharging)", CommandOrders.run(world, "sweep", 0, s) != "")
	if not xray:
		var blocked_layout := find_layout(true)
		if blocked_layout.is_empty():
			check("sweep: rocks block it (no rock case on this map)", true, "skipped")
		else:
			CommandOrders.reset_cooldown(world, "sweep", 0)
			var a2: Vector2 = blocked_layout[0]
			me.global_position = a2
			enemy.global_position = blocked_layout[2]
			await wait(1.0)
			CommandOrders.run(world, "sweep", 0, blocked_layout[1])
			await wait(1.0)
			check("sweep: a rock between hides the enemy", not enemy.visible_to(0))
	await wait(9.0)
	check("sweep: the sight source ran out", world.vision_sources.is_empty() or Game.variant("assets") == "xray")
	check("sweep: usage counted", used("assets_sweep") >= 1, str(used("assets_sweep")))
	for sh in [me, enemy]:
		world.combat.kill_silently(sh)


## Supply Drop: four drones fly out and mend a hurt ship at the spot.
func check_supply() -> void:
	var ship := spawn("flak", 0, SPOT)
	ship.hull = ship.hull_max * 0.4
	await wait(1.0)
	var before := ship.hull
	var drones_before := world.repair_drones.size()
	var msg := CommandOrders.run(world, "supply", 0, SPOT)
	check("supply: order accepted", msg == "", msg)
	var n := 0
	for d: RepairDrone in world.repair_drones:
		if d is SupplyDrone:
			n += 1
	check("supply: four supply drones launched", n == 4 and world.repair_drones.size() - drones_before == 4, str(n))
	await wait(30.0)
	check("supply: the hurt ship was mended", ship.hull > before + 50.0, "%d -> %d" % [int(before), int(ship.hull)])
	check("supply: the drones left after their work", world.repair_drones.size() == drones_before)
	check("supply: usage counted", used("assets_supply") >= 1)
	world.combat.kill_silently(ship)


## Barrage: refused beyond 12,000; both teams see the red circle; after 3 s
## the enemy in it is hurt or destroyed.
func check_barrage() -> void:
	var ms := world.mothership(0)
	var far := ms.global_position + Vector2(13000, 0)
	check("barrage: refused beyond 12,000", CommandOrders.blocker(world, "barrage", 0, far) != "")
	var b := ms.global_position + Vector2(5000, 0)
	var enemy := spawn("fighter", 1, b)
	var before := enemy.hull
	var msg := CommandOrders.run(world, "barrage", 0, b)
	check("barrage: order accepted", msg == "", msg)
	var seen_by_both := false
	for m: Dictionary in world.command.marks:
		if str(m.get("label", "")) == "BARRAGE" and (m["teams"] as Array).has(0) and (m["teams"] as Array).has(1):
			seen_by_both = true
	check("barrage: the red circle shows to both teams", seen_by_both)
	await wait(1.0)
	check("barrage: nothing hit during the warning", enemy.alive and enemy.hull >= before - 1.0)
	await wait(3.0)
	# A destroyed ship is freed at the end of the frame, so test the pointer first.
	var gone := not is_instance_valid(enemy) or not enemy.alive
	check("barrage: the enemy in the circle was hit", gone or enemy.hull < before, "destroyed=%s" % str(gone))
	check("barrage: usage counted", used("assets_barrage") >= 1 and used("assets_barrage_hits") >= 1)
	if not gone:
		world.combat.kill_silently(enemy)


## The first node of kind `kind` ("inner" or "middle") on `side`.
func node_of(kind: String, side: int) -> ResourceNode:
	for n: ResourceNode in world.nodes:
		if n.node_kind == kind and n.side == side:
			return n
	return null


## Bounty: paid up front, shared by the pilots who help kill the target,
## half back when it runs out.
func check_bounty() -> void:
	var feature: AdmiralOrdersFeature = world.features["orders"]
	var n := node_of("inner", 1)
	var tu := world.spawn_turret(1, n, n.free_slot(), "pd", true)
	tu.seen_mask |= 1
	# The friend stands well outside the turret's range (it would shoot it).
	var friend := spawn("fighter", 0, tu.global_position + toward_center(tu.global_position) * 4000.0)
	var ts := world.teams[0]
	var before := ts.treasury
	var msg := CommandOrders.run(world, "bounty", 0, tu.global_position)
	check("bounty: order accepted", msg == "", msg)
	check("bounty: 10% (max 1,000) paid up front", absf(before - ts.treasury - 1000.0) < 1.0, str(before - ts.treasury))
	check("bounty: a second bounty on the same target is refused", CommandOrders.blocker(world, "bounty", 0, tu.global_position) != "")
	var credits := friend.profile.credits
	hit(tu, 99999.0, friend)
	check("bounty: the target died", not tu.alive)
	check("bounty: the pilot nearby got the amount", friend.profile.credits - credits >= 1000.0, str(friend.profile.credits - credits))
	check("bounty: usage counted", used("bounties_posted") == 1 and used("bounties_claimed") == 1)
	# An unclaimed bounty gives back half.
	CommandOrders.reset_cooldown(world, "bounty", 0)
	var tu2 := world.spawn_turret(1, n, n.free_slot(), "pd", true)
	tu2.seen_mask |= 1
	var t0 := ts.treasury
	check("bounty: post_bounty", feature.post_bounty(0, tu2, 200.0) == "")
	world.time += 200.0
	await wait(2.0)
	# (Ore deliveries add to the treasury meanwhile, so only "at least" is checked.)
	check("bounty: unclaimed bounty refunds half", ts.treasury >= t0 - 200.0 + 100.0 - 1.0, str(ts.treasury - t0))
	check("bounty: usage expired counted", used("bounties_expired") >= 1)
	world.combat.kill_silently(tu2)
	world.combat.kill_silently(friend)


## Fortify: x0.2 damage for 4 s on turrets and the mothership; ready again
## when the first inner turret is lost.
func check_fortify() -> void:
	var n := node_of("inner", 0)
	var tu := world.spawn_turret(0, n, n.free_slot(), "pd", true)
	var foe := spawn("fighter", 1, tu.global_position + toward_center(tu.global_position) * 4000.0)
	var total := func() -> float: return tu.hull + tu.shield_total()
	var t0: float = total.call()
	hit(tu, 100.0, foe)
	var plain: float = t0 - float(total.call())
	check("fortify: normal hit hurts", plain > 1.0, str(plain))
	var msg := CommandOrders.run(world, "fortify", 0, Vector2.ZERO)
	check("fortify: order accepted (free)", msg == "", msg)
	var t1: float = total.call()
	hit(tu, 100.0, foe)
	var fort: float = t1 - float(total.call())
	check("fortify: the same hit does about a fifth", fort > 0.0 and fort < plain * 0.35, "%.1f vs %.1f" % [fort, plain])
	check("fortify: the mothership is covered", world.mothership(0).incoming_mults.has("fortify"))
	check("fortify: recharging", CommandOrders.run(world, "fortify", 0, Vector2.ZERO) != "")
	await wait(4.5)
	check("fortify: ended after 4 s", not tu.incoming_mults.has("fortify") and not world.mothership(0).incoming_mults.has("fortify"))
	# Losing the first inner turret makes it ready again.
	hit(tu, 99999.0, foe)
	check("fortify: ready again after the first inner turret fell", CommandOrders.ready_in(world, "fortify", 0) == 0.0)
	check("fortify: usage counted", used("fortify_uses") == 1)
	world.combat.kill_silently(foe)


## Mothership moves: early (from 12:00) and/or with the admiral flying.
func check_ms_move() -> void:
	var value := Game.variant("ms_move")
	var ts := world.teams[0]
	world.time = 800.0
	ts.admiral_docked = true
	var b1 := world.command.move_blocker(0)
	check("ms_move: at 13:20 docked, the move is %s" % ("allowed" if value in ["early", "both"] else "refused"), (b1 == "") == (value in ["early", "both"]), b1)
	world.time = 1300.0
	ts.admiral_docked = false
	var b2 := world.command.move_blocker(0)
	check("ms_move: flying admiral, the move is %s" % ("allowed" if value in ["flying", "both"] else "refused"), (b2 == "") == (value in ["flying", "both"]), b2)
	# Really move it once while flying (or docked, at 13:20).
	ts.admiral_docked = not (value in ["flying", "both"])
	var pts := MapLayout.lane_points("mid", 0)
	var p := Util.polyline_at(pts, Util.polyline_length(pts) * 0.2)
	var msg := world.command.move_mothership(0, p)
	check("ms_move: the mothership accepts the order", msg == "", msg)
	if value in ["flying", "both"]:
		check("ms_move: flying move counted", used("flying_moves") >= 1)
	world.time = 800.0
	ts.admiral_docked = true
	if value in ["early", "both"]:
		world.mothership(0).move_target = Vector2.INF
		world.command.move_mothership(0, p)
		check("ms_move: early move counted", used("early_moves") >= 1)
	world.time = 1300.0


## Mutiny: a failed vote changes nothing; a passed vote makes the human
## admiral a pilot in the richest seat and gives the chair to a computer
## admiral.
func check_mutiny() -> void:
	var feature: MutinyFeature = world.features["mutiny"]
	var ts := world.teams[0]
	# A human admiral and 12 computer pilot seats (profiles only).
	var ap := PilotProfile.new("Admiral", 0, 12, true)
	ap.role = "admiral"
	world.profiles.append(ap)
	world.human = ap
	world.human_role = "admiral"
	ts.admiral = "human"
	world.admiral_ai[0] = null
	var seats: Array = []
	for i in 12:
		var p := PilotProfile.new("Seat%d" % i, 0, i, false)
		p.role = PilotAI.ROLE_PLAN[i % PilotAI.ROLE_PLAN.size()]
		p.credits = 100.0 + float(i) * 10.0
		p.kills = 5
		p.deaths = 1
		world.profiles.append(p)
		seats.append(p)
	world.time = 2000.0
	feature.behind_since[0] = 1000.0
	feature.last_vote[0] = -99999.0
	ts.treasury = 100.0
	# A vote with happy pilots fails.
	check("mutiny: a vote is possible when behind for 5 min", feature.vote_blocker(0) == "", feature.vote_blocker(0))
	var yes_before := used("mutiny_yes")
	feature.call_vote(0, seats[0])
	check("mutiny: a vote with happy pilots fails (only the caller votes yes)", ts.admiral == "human" and used("mutiny_yes") - yes_before == 1, str(used("mutiny_yes") - yes_before))
	check("mutiny: no second vote at once", feature.vote_blocker(0) != "")
	# Unhappy pilots (more deaths than kills) pass it.
	feature.last_vote[0] = -99999.0
	for i in 10:
		(seats[i] as PilotProfile).deaths = 9
	var rich: PilotProfile = seats[11]
	rich.credits = 5000.0
	feature.call_vote(0, seats[0])
	check("mutiny: the vote passed and the chair is a computer admiral's", ts.admiral == "ai" and world.admiral_ai[0] != null)
	check("mutiny: the human is a pilot now", world.human_role == "pilot" and world.human == ap)
	check("mutiny: the human took the richest seat", ap.slot == rich.slot and ap.role == rich.role and ap.credits >= 5000.0, "slot %d credits %d" % [ap.slot, int(ap.credits)])
	check("mutiny: the old seat holder is gone", not world.profiles.has(rich))
	check("mutiny: usage counted", used("mutiny_votes") == 2 and used("mutiny_swaps") == 1)
