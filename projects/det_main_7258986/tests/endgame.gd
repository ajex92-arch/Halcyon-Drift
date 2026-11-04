extends Node
## WHAT THIS IS: an end-game scenario. It skips straight to the last part
## of a match to test the C11 "retreat" variants and late-game balance.
## (C11 is a design question in docs/DESIGN.md, section A2: what a badly
## damaged mothership does. The choices are --variant=retreat:none or
## retreat:systems_failure; Rules.VARIANT_DEFAULTS holds the default.)
##
## HOW IT WORKS: setup() starts the match at 25:00 with both sides fully
## teched (every facility except "fleet", and all research), every pilot
## rich enough for a capital ship, two turrets at each inner node, and
## Cinder's mid turrets already lost (all done by LateGame.apply, in
## tests/lib/late_game.gd). Then the AI plays it out. Every 30
## game seconds it prints both motherships and fleets. It stops when a
## mothership dies, or after --secs game seconds of play.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --variant=retreat:none --test=endgame --secs=900
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second. --secs is how
## many game seconds to play after 25:00 (default 900). --debug adds one
## line per big AI ship at every report.
##
## HOW TO READ THE OUTPUT:
##   "endgame: variant retreat=none start 25:00"  the setup.
##   Every 30 s, one line: the match clock, then for each team:
##     "Halcyon ms 87% sh 3200 [FAILURE] turrets 5
##      siege=mid/assault def=false {"destroyer": 2, ...}"
##     = mothership hull left, its shield points, FAILURE while its
##     systems are failing, live turrets, the siege lane and phase
##     ("/" alone = no siege), whether the "defend the mothership" call is
##     on, and how many ships of each hull the team has.
##   "ENDGAME RESULT: Cinder wins at 31:40 (400s after start), variant none"
##   or "ENDGAME RESULT: no winner after 900s (H 54%, C 61%), variant none"
##       the final result (H and C are the two motherships' hull left).
##
## WHO USES IT: main.gd loads it for --test=endgame (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()).
## tests/det_hash.gd --late uses the same LateGame setup.

## The running match (set by setup()).
var world: World
## How many game seconds to play after the start (--secs, default 900).
var secs := 900.0
## The match clock at the start of this scenario: 1,500 s = 25:00.
var start := LateGame.START
## Game time (seconds) of the last report.
var last := 0.0

## main.gd calls this once, right after the World is built. Jump to 25:00
## and set up the late game (see HOW IT WORKS above).
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 900.0))
	# The late-game setup (tests/lib/late_game.gd).
	LateGame.apply(world)
	print("endgame: variant retreat=%s start %s" % [Game.variant("retreat"), Util.clock(start)])


## Godot calls this every tick. Report every 30 game seconds, and print the
## result (then quit) when a mothership dies or --secs have passed.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time - last >= 30.0:
		last = world.time
		var parts: Array = []
		for t in 2:
			var ms := world.mothership(t)
			# Count this team's pilot ships by hull id.
			var hulls := {}
			for s: Ship in world.ships:
				if s.team == t:
					hulls[s.hull_id] = int(hulls.get(s.hull_id, 0)) + 1
			# Count this team's live turrets.
			var tur := 0
			for tu: Turret in world.turrets:
				if tu.team == t and tu.alive:
					tur += 1
			# One part of the line for this team (see HOW TO READ THE OUTPUT).
			parts.append("%s ms %d%% sh %d%s turrets %d siege=%s/%s def=%s %s" % [Rules.TEAM_NAMES[t], int(ms.hull_frac() * 100.0), int(ms.shields.total()),
				" FAILURE" if ms.failure_t > 0.0 else "", tur, world.teams[t].siege_lane, world.teams[t].siege_phase,
				world.teams[t].defending(world.time), hulls])
		print("  %s  %s" % [Util.clock(world.time), "  |  ".join(parts)])
		# --debug: one line per living big ship (size class large or more)
		# that has an AI brain: hull, AI state, target, and its distance to
		# the enemy mothership's hull and its goal's distance to it.
		if Game.opt("debug", false):
			for s: Ship in world.ships:
				if not s.alive or s.size_class < Rules.SIZE_LARGE:
					continue
				var ai: PilotAI = world.pilot_ai.get(s.profile)
				if ai == null:
					continue
				var ems := world.mothership(1 - s.team)
				var tg := "-"
				if ai.target != null and is_instance_valid(ai.target):
					tg = "%s@%d" % [ai.target.display_name, int(s.global_position.distance_to(ai.target.global_position))]
				print("    %s %s hp=%d%% state=%s intent=%s target=%s ms_dist=%d goal_ms_dist=%d fire=%s" % [Rules.TEAM_NAMES[s.team], s.hull_id, int(s.hull_frac() * 100.0), ai.state, ai.intent, tg, int(ems.hull_dist(s.global_position)), int(ems.hull_dist(ai.goal)), s.controls.fire])
	# The end: a mothership died (the phase is no longer "play"), or time
	# is up.
	if world.phase != "play":
		print("ENDGAME RESULT: %s wins at %s (%.0fs after start), variant %s" % [Rules.TEAM_NAMES[world.winner], Util.clock(world.time), world.time - start, Game.variant("retreat")])
		get_tree().quit()
	elif world.time - start >= secs:
		print("ENDGAME RESULT: no winner after %.0fs (H %d%%, C %d%%), variant %s" % [secs, int(world.mothership(0).hull_frac() * 100.0), int(world.mothership(1).hull_frac() * 100.0), Game.variant("retreat")])
		get_tree().quit()
