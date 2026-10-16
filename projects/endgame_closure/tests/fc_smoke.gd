extends Node
## WHAT THIS IS: forced smoke tests for the endgame_closure fork's feature
## modules (scripts/features/). Some of them wait for rare events (a lane
## breach, a mothership at 35% hull, a surrender vote); this test makes the
## event happen at once so the module can be seen working.
##
## HOW IT WORKS: setup() starts the late game (LateGame.apply, symmetric),
## then picks a scenario (--scenario) and, about 2 game seconds in, forces
## its trigger:
##   breach     destroys Cinder's top-lane inner turrets (the lane is breached
##              for Halcyon; with --variant=breach:... / breach_extra:on the
##              next waves carry tougher corvettes);
##   laststand  drops Cinder's mothership to 30% hull (--variant=retreat:
##              last_stand: shields refill, guns faster, then a weak spot);
##   surrender  destroys up to 9 Cinder turrets and fakes 16 Halcyon pilot kills in
##              the module's kill book (--variant=surrender:vote: the vote
##              opens, passes after 30 s and the match ends);
##   siege      declares a Halcyon siege on the mid lane at 10 s and moves
##              Halcyon's big ships to the staging point (--variant=siege_fix:
##              gather3 / full: the assault is launched; full also holds
##              fast ships back on the way in);
##   stall      puts Halcyon's siege in "assault" with first contact 130 s ago
##              and no damage done (--variant=siege_fix:stall keeps it alive;
##              without it the AI admiral calls it off at once);
##   race       moves two Cinder big ships towards Halcyon's mothership every
##              tick, from 11,000 away at 100 units a second (--variant=
##              siege_fix:full: the early defend call "base race");
##   mscap      empties Cinder's shield and hits its hull with capital-ship
##              hits every tick (--variant=ms_cap:on or full: after 12% of
##              the hull is lost in 60 s the hull falls slower).
## It runs --secs game seconds (default 120) after the start, or until the
## match ends, then prints one line, FC_SMOKE {...}, with the scenario, the
## match state, Game.usage and a few scenario numbers, and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path forks/endgame_closure --fixed-fps 60 -- --all-ai --seed=7 --test=fc_smoke --scenario=breach --variant=breach:on --secs=400
##
## WHO USES IT: main.gd loads it for --test=fc_smoke (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). It is
## a measurement tool of the endgame_closure fork; no game code reads it.

## The running match (set by setup()).
var world: World
## The scenario name (--scenario).
var scenario := "breach"
## The match time (seconds) at which to stop.
var t_end := 0.0
## The match time (seconds) when the trigger fires.
var t_trigger := 0.0
## True once the trigger has fired.
var fired := false
## Cinder's mothership hull fraction a few times after the trigger:
## [seconds after the trigger, hull fraction] pairs (mscap numbers).
var samples: Array = []
## Seconds until the next sample.
var _t_sample := 10.0
## True once FC_SMOKE has been printed.
var _done := false


## main.gd calls this once, right after the World is built.
func setup(w: World) -> void:
	world = w
	scenario = str(Game.opt("scenario", "breach"))
	LateGame.apply(world, true)
	Events.feed.connect(_on_feed)
	t_trigger = world.time + (10.0 if scenario in ["siege", "race", "stall"] else 2.0)
	t_end = world.time + float(Game.opt("secs", 120.0))


## Godot calls this every tick: fire the trigger, take samples and print the
## result at the end.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	if not fired and world.time >= t_trigger:
		fired = true
		_fire()
	if fired and scenario == "mscap":
		_hit_mothership()
	if fired and scenario == "race":
		_race_step(dt)
	if fired:
		_t_sample -= dt
		if _t_sample <= 0.0:
			_t_sample = 10.0
			samples.append([int(world.time - t_trigger), snappedf(world.mothership(1).hull_frac(), 0.001)])
	if world.time >= t_end or world.phase != "play":
		_done = true
		print("FC_SMOKE " + JSON.stringify(_result()))
		get_tree().quit()


## A news-feed line (Events.feed): print the ones the feature modules send,
## so the output shows the messages the players would see.
func _on_feed(text: String, _tone: String, _team: int) -> void:
	for word in ["vote", "surrender", "breach", "last stand", "plating", "Supply", "Reinforcements", "racing"]:
		if text.containsn(word):
			print("FEED t=%d %s" % [int(world.time), text])
			return


## Force the scenario's trigger.
func _fire() -> void:
	match scenario:
		"breach":
			# Destroy Cinder's top-lane inner turrets (by name of the node).
			for t: Turret in world.turrets.duplicate():
				if t.team == Rules.CINDER and t.node != null and t.node.node_kind == "inner" and t.node.lane == "top":
					world.combat.kill(t, DamageInfo.from_unit(null, 1.0, Rules.W_BOLT, t.global_position))
		"laststand":
			var ms := world.mothership(Rules.CINDER)
			ms.hull = ms.hull_max * 0.30
		"surrender":
			var n := 0
			for t: Turret in world.turrets.duplicate():
				if t.team == Rules.CINDER and n < 9:
					n += 1
					world.combat.kill(t, DamageInfo.from_unit(null, 1.0, Rules.W_BOLT, t.global_position))
			var sf = world.features.get("surrender")
			if sf != null:
				for i in 16:
					sf._kills.append([world.time, Rules.HALCYON])
		"mscap":
			world.mothership(Rules.CINDER).shields.values = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		"stall":
			var ts2 := world.teams[Rules.HALCYON]
			var ai: AdmiralAI = world.admiral_ai[Rules.HALCYON]
			ts2.siege_lane = "mid"
			ts2.siege_phase = "assault"
			ts2.siege_t = world.time
			ai.siege.contact_t = world.time - 130.0
			ai.siege.contact_ms_hp = world.mothership(Rules.CINDER).hull_frac()
		"siege":
			# Declare the siege and bring the big ships to the staging point.
			var ts := world.teams[Rules.HALCYON]
			ts.siege_lane = "mid"
			ts.siege_phase = "gather"
			ts.siege_t = world.time
			var stage := ts.siege_stage_point("mid")
			var i := 0
			for s: Ship in world.ships:
				if s.team == Rules.HALCYON and s.alive and s.size_class >= Rules.SIZE_LARGE:
					s.global_position = stage + Vector2.from_angle(float(i) * 2.0) * 600.0
					i += 1
			# One bomber (fast) is put 5,000 units ahead of the rest, towards
			# the enemy mothership, so the formation throttle has work to do.
			var toward := (world.mothership(Rules.CINDER).global_position - stage).normalized()
			for s: Ship in world.ships:
				if s.team == Rules.HALCYON and s.alive and s.hull_id == "bomber":
					s.global_position = stage + toward * 5000.0
					break


## race: put two Cinder big ships on a line towards Halcyon's mothership and
## move them along it at 100 units a second (so they are "closing").
func _race_step(dt: float) -> void:
	var ms := world.mothership(Rules.HALCYON)
	var k := 0
	for s: Ship in world.ships:
		if s.team == Rules.CINDER and s.alive and s.size_class >= Rules.SIZE_LARGE and k < 2:
			var dist := 11000.0 - 100.0 * (world.time - t_trigger)
			s.global_position = ms.global_position + Vector2(dist, float(k) * 400.0)
			s.velocity = Vector2.ZERO
			k += 1


## mscap: hit Cinder's mothership with a capital ship's shell every tick
## (3 raw damage x1.5 shell x2.0 capital = 9 a tick, 540 a second), with the
## shield kept empty.
func _hit_mothership() -> void:
	var ms := world.mothership(Rules.CINDER)
	if ms == null or not ms.alive:
		return
	ms.shields.values = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var info := DamageInfo.from_unit(null, 3.0, Rules.W_SHELL, ms.global_position + Vector2(-800, 0))
	info.source_size = Rules.SIZE_CAPITAL
	world.combat.apply_damage(ms, info)


## Everything FC_SMOKE prints.
func _result() -> Dictionary:
	var tagged := {}
	for m: Minion in world.minions:
		for tag in ["breach_corvette", "super_minion"]:
			if m.has_meta(tag):
				tagged[tag] = int(tagged.get(tag, 0)) + 1
	var h := world.mothership(Rules.HALCYON)
	var c := world.mothership(Rules.CINDER)
	var bigs := [0, 0]
	for s: Ship in world.ships:
		if s.alive and s.size_class >= Rules.SIZE_LARGE and s.team <= 1:
			bigs[s.team] += 1
	# For the siege scenario: each Halcyon siege ship's distance to the enemy hull
	# and speed, and the siege_fix speed cap (if that module is on).
	var dbg: Array = []
	for s: Ship in world.ships:
		if s.alive and s.team == Rules.HALCYON and (s.size_class >= Rules.SIZE_LARGE or s.hull_id == "bomber"):
			dbg.append([s.hull_id, int(c.hull_dist(s.global_position)), int(s.velocity.length()), int(s.f_max)])
	var sf = world.features.get("siege_fix")
	return {
		"siege_ships": dbg,
		"siege_cap": [sf.cap[0] if sf != null else null, sf.cap[1] if sf != null else null],
		"big_ships": bigs,
		"siege": [world.teams[0].siege_phase, world.teams[1].siege_phase],
		"scenario": scenario,
		"variants": Game.variants,
		"features": world.features.keys(),
		"minutes": snappedf(world.time / 60.0, 0.01),
		"phase": world.phase,
		"winner": world.winner,
		"usage": Game.usage,
		"tagged_minions_alive": tagged,
		"hull_frac": [snappedf(h.hull_frac(), 0.001), snappedf(c.hull_frac(), 0.001)],
		"cinder_mults": c.incoming_mults,
		"cinder_hull_samples": samples,
	}
