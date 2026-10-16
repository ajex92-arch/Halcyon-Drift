extends Node
## WHAT THIS IS: a dogfight arena test. Two small squads of AI pilots meet
## in open space (no minions, turrets or jungle monsters) and fight until
## one side is gone. It measures whether the AI pilots can actually kill
## things, and how long their fights last.
##
## HOW IT WORKS: setup() stops the minion waves and builds the two squads
## with the arena toolkit (tests/lib/arena_kit.gd): squad A flies for
## Halcyon, squad B for Cinder. They start 1,000 world units either side of
## the arena's centre (1 world unit is about one pixel at normal zoom), all
## facing the middle, and every pilot holds a spot 500 units from the centre
## on its own side, so both squads want the same ground and must fight for
## it. Every tick (one small step of game time, 60 per game second here)
## the toolkit stops the pilots from flying home to shop, and a pilot that
## docks anyway, or dies, is out for good. The test ends when one squad is
## empty, or after 180 seconds.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=arena --a=fighter,fighter,fighter --b=lance,lance,lance
## --headless runs with no window. --fixed-fps 60 makes every tick exactly
## 1/60 of a game second, so a run repeats and goes as fast as the computer
## can. --no-pilots, --no-jungle and --no-admiral-ai switch off the normal
## AI pilots, the jungle monsters and the computer admirals, so only our
## two squads fly. This test's own options:
##   --a=<hulls>  squad A's hull ids, comma-separated (default: 3 fighters)
##   --b=<hulls>  squad B's hull ids (default: 3 lances)
##   --skill-a=<0..1>  every squad A pilot's skill (PilotAI.skill; default:
##                the skill of each pilot's seat number, as before)
##   --skill-b=<0..1>  the same for squad B
##   --swap       Halcyon starts east and Cinder west (this tells "which
##                side of the map" apart from "which team")
##   --debug      report every 2 s instead of every 10 s, with one extra
##                line per ship (its AI state, target, beams ...)
## (tests/arena_matrix.gd runs many such fights in a row for the fun
## experiments: a duel curve and an equal-credit matrix.)
##
## HOW TO READ THE OUTPUT:
##   "arena: [...] vs [...]"  the hulls of squad A and squad B.
##   "t= 10s A [fighter 85%, ...] | B [...]"  every 10 s: who is still
##       alive in each squad, and how much hull each has left (100% =
##       undamaged). The time counts from the start of this test.
##   "... DOCKED (counts as out)"  a pilot flew home and docked; it no
##       longer counts.
##   "ARENA RESULT after 64s: A alive 2, B alive 0, first kill at 23s"
##       the final score. "first kill at -1s" means no ship died.
##
## WHO USES IT: main.gd loads it for --test=arena (for --test=<name> it
## loads tests/<name>.gd, adds it to the scene after the World and calls
## setup()). The squads come from ArenaKit (tests/lib/arena_kit.gd), which
## makes their PilotAI brains.

## The arena toolkit: squads, keeping pilots in the fight, who is alive.
const ArenaKit := preload("res://tests/lib/arena_kit.gd")

## The running match (set by setup()).
var world: World
## Squad A's ships (Halcyon), in launch order.
var a: Array = []
## Squad B's ships (Cinder), in launch order.
var b: Array = []
## Seconds since this test started.
var t := 0.0
## Seconds until the next progress report.
var report_t := 0.0
## When (seconds since the test started) the first ship died; -1 = none yet.
var first_kill := -1.0


## main.gd calls this once, right after the World is built. Stop the minion
## waves, read the squad lists and skills, launch both squads and start
## listening for the first kill.
func setup(w: World) -> void:
	world = w
	# No minion waves at all: the next wave is "never" (INF = infinity).
	world.minion_director.next_wave = INF
	# Read the hull lists and skills from the command line (or use the
	# defaults; a skill below 0 means "the seat's own skill").
	var la := str(Game.opt("a", "fighter,fighter,fighter")).split(",")
	var lb := str(Game.opt("b", "lance,lance,lance")).split(",")
	var ska := float(Game.opt("skill-a", -1.0))
	var skb := float(Game.opt("skill-b", -1.0))
	# --swap: Halcyon starts east, Cinder west (separates side from team).
	var swap := Game.opt("swap") != null
	a = ArenaKit.squad(world, Rules.HALCYON, la, swap, ska)
	b = ArenaKit.squad(world, Rules.CINDER, lb, swap, skb)
	# Remember when the first ship dies. (Events.unit_killed is a "signal":
	# the game calls every connected function whenever any unit dies. The
	# function here is a "lambda", a small function written in place.)
	Events.unit_killed.connect(func(u: Node, _i: RefCounted) -> void:
		if u is Ship and first_kill < 0.0:
			first_kill = t)
	print("arena: %s vs %s" % [la, lb])


## Godot calls this every tick; `dt` is the tick's length in seconds. Keep
## every pilot in the fight, print a report every 10 s (2 s with --debug)
## and end the test when a squad is gone or 180 s have passed.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	# Keep the fight here (ArenaKit.keep_in_fight); a pilot that docked is
	# out, and we say so.
	for p: PilotProfile in ArenaKit.keep_in_fight(world):
		print("  t=%3ds %s %s DOCKED (counts as out)" % [int(t), Rules.TEAM_NAMES[p.team], p.callsign])
	var aa := ArenaKit.alive_text(a)
	var bb := ArenaKit.alive_text(b)
	# The progress report: who is alive in each squad.
	report_t -= dt
	if report_t <= 0.0:
		report_t = 2.0 if Game.opt("debug", false) else 10.0
		print("  t=%3ds A %s | B %s" % [int(t), aa, bb])
		# --debug: one line per living ship with what its brain is doing.
		if Game.opt("debug", false):
			_debug_lines()
	# The end: one squad is gone, or the 180-second time limit.
	if aa.is_empty() or bb.is_empty() or t > 180.0:
		print("ARENA RESULT after %ds: A alive %d, B alive %d, first kill at %.0fs" % [int(t), aa.size(), bb.size(), first_kill])
		get_tree().quit()


## --debug: one line per living ship: hull, callsign, AI state and intent,
## its target as "name@distance" ("-" for none), firing, energy, rotation,
## and each beam weapon's on/off timers.
func _debug_lines() -> void:
	for s in a + b:
		if not is_instance_valid(s) or not s.alive:
			continue
		var ai: PilotAI = world.pilot_ai[s.profile]
		# Its target as "name@distance", or "-" for none.
		var tg := "-"
		if ai.target != null and is_instance_valid(ai.target):
			tg = "%s@%d" % [ai.target.display_name, int(s.global_position.distance_to(ai.target.global_position))]
		# Each beam weapon's on/off timers and whether it is firing.
		var beams := ""
		for m: WeaponMount in s.mounts:
			if m.is_beam:
				beams += " beam(on %.1f off %.1f firing %s)" % [m.beam_on, m.beam_off, m.beam_firing]
		print("    %s %s state=%s intent=%s target=%s fire=%s energy=%d rot=%.2f%s" % [s.hull_id, s.profile.callsign, ai.state, ai.intent, tg, s.controls.fire, int(s.energy.value), s.rotation, beams])
