extends Node
## WHAT THIS IS: the "perf probe" (perf = performance: how fast the game
## runs). It runs an all-AI match with profiling on (the World times each
## part of its work) and quits after --secs game seconds (default 300).
## Use it to find which part of the game costs the most computer time.
##
## HOW IT WORKS: setup() switches World.profiling on; this script does
## nothing else but quit at the end. The printing is done by main.gd: once
## every game minute it prints how many milliseconds of real computer time
## each part of the game took per second of game time ("ms per
## sim-second"; sim = the simulation, the game's own world).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --profile --test=perf_probe --secs=300
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second.
##
## HOW TO READ THE OUTPUT: main.gd prints each minute a line like
## "  prof ms/sim-s: directors=0.4, hash=1.2, vision=2.0, units=9.1, ..."
## Main prints the per-system ms per sim-second each minute (keys:
## directors, hash, vision, units, u_<kind>, s_ctrl / s_flight / s_move /
## s_weap for pilot ships, m_think for minions, projectiles). A "u_<kind>"
## key is one kind of unit; s_ctrl / s_flight / s_move / s_weap are a
## pilot ship's controller (its AI brain or the player's keys), flight,
## movement and weapons; m_think is the minions' thinking. World also
## writes a "rest" key. Bigger numbers = more time spent.
##
## WHO USES IT: main.gd loads it for --test=perf_probe (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()) and
## prints the "prof" lines from World.prof. Ship and Minion add their own
## keys while World.profiling is on.

## The running match (set by setup()).
var world: World
## How many game seconds to run (--secs, default 300).
var secs := 300.0


## main.gd calls this once, right after the World is built. Turn profiling
## on and read --secs.
func setup(w: World) -> void:
	world = w
	world.profiling = true
	secs = float(Game.opt("secs", 300.0))


## Godot calls this every tick. Quit once --secs of game time have passed.
func _physics_process(_dt: float) -> void:
	if world != null and world.time >= secs:
		get_tree().quit()
