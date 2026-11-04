class_name LateGame
extends RefCounted
## WHAT THIS IS: the "skip to the late game" setup that several tests
## share: tests/endgame.gd, tests/det_hash.gd --late, tests/fun_probe.gd
## --late, tests/pilot_audit.gd --late and tests/admiral_audit.gd --late.
##
## HOW IT WORKS: apply() moves the match clock to 25:00 and makes both
## sides late-game strong at once: every facility except Fleet Command,
## all research done (with its effects), upgraded and full motherships,
## 6,000 credits in each treasury and for every pilot (enough for a
## capital ship), and a point-defense plus a torpedo turret at every inner
## ore node except Cinder's mid (as if Cinder had already lost it).
## With `symmetric` true, Cinder's mid gets its turrets too, so both sides
## start exactly alike (the research's "symmetric --late start"; the
## fun probe's --symmetric option).
## This is a "static library": plain functions with no state of their own.
##
## WHO USES IT: tests/endgame.gd, tests/det_hash.gd (with --late),
## tests/fun_probe.gd (with --late), tests/pilot_audit.gd (with --late) and
## tests/admiral_audit.gd (with --late) call apply() from their setup().

## The match clock after apply(): 1,500 s = 25:00.
const START := 1500.0


## Set up the late game in `world` (see HOW IT WORKS). Call it right after
## the World is built, before the first tick. `symmetric` = also build
## Cinder's mid inner turrets (default false: the usual setup, which
## det_hash's late baseline was made with).
static func apply(world: World, symmetric: bool = false) -> void:
	# Step 1: move the clock to 25:00; the next minion wave comes 5 s later.
	world.time = START
	world.minion_director.next_wave = START + 5.0
	# Step 2: for both teams, build every facility except "fleet", finish
	# all research (and apply its effects), upgrade and refill the
	# mothership, and fill the treasury with 6,000 credits.
	for t in 2:
		var ts := world.teams[t]
		for f: String in Tech.FACILITY_ORDER:
			if f != "fleet":
				ts.facilities[f] = true
		for id: String in Tech.ORDER:
			ts.done[id] = true
			ts.apply_effect(Tech.TECHS[id]["effect"])
		var ms := world.mothership(t)
		ms.apply_upgrades(ts)
		ms.hull = ms.hull_max
		ms.shields.fill()
		ts.treasury = 6000.0
	# Step 3: every pilot gets 6,000 credits.
	for p: PilotProfile in world.profiles:
		p.credits = 6000.0
	# Step 4: a point-defense ("pd") and a torpedo ("torp") turret, built at
	# once, at every inner ore node, except Cinder's mid (already lost)
	# unless `symmetric`.
	for n: ResourceNode in world.nodes:
		if n.node_kind != "inner" or (not symmetric and n.side == Rules.CINDER and n.lane == "mid"):
			continue
		world.spawn_turret(n.side, n, n.free_slot(), "pd", true)
		world.spawn_turret(n.side, n, n.free_slot(), "torp", true)
