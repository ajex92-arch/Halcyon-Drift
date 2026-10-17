extends Node
## WHAT THIS IS: the "perf probe" (perf = performance: how fast the game
## runs). It runs an all-AI match with profiling on (the World times each
## part of its work) and quits after --secs game seconds (default 300).
## Use it to find which part of the game costs the most computer time.
##
## HOW IT WORKS: setup() switches World.profiling on; the probe then counts
## how long each tick took and quits at the end. The per-system printing is
## done by main.gd: once every game minute it prints how many milliseconds
## of real computer time each part of the game took per second of game time
## ("ms per sim-second"; sim = the simulation, the game's own world). At the
## very end the probe prints one PERF_JSON line with the whole run in
## numbers (see "THE END LINE" below).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --profile --test=perf_probe --secs=300
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second.
##
## --noprof leaves the profiling off (the timing code itself costs a little),
## so the plain "sim ms/sim-s" line of main.gd is the cleanest speed number.
##
## --late starts the match at 25:00 with both sides fully teched and rich
## (LateGame.apply, as in tests/det_hash.gd --late); --secs then counts from
## 25:00. This measures the heavy late game (sieges, capital ships).
##
## --perf-worst keeps the load at its worst, and the same from one stage of
## the user test fork to the next (docs/USER_FORK_PLAN.md, gate 5). Use it
## with --late. While it is on:
##   - every respawn wait is 0 seconds (the tuned numbers respawn_base and
##     respawn_per_minute, Rules.TUNABLES, are set to 0), so a pilot who
##     dies is back in the hangar on the next tick;
##   - AI pilots never fly home to shop (the brain's `launched_at` is kept at
##     "just launched", and PilotShopping.wants_shopping() says "no" for the
##     first 150 s after a launch), so every seat stays in space;
##   - STAGE 4 HOOK (_fill_wings): every pilot will own the most wingmen it
##     may have. Nothing happens there yet; stage 4 puts the code in.
## Both settings are made here, in the test, so the game's own code is not
## touched. Without --perf-worst the probe only measures and nothing about
## the match changes.
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
## THE HEADER LINE: setup() prints "perf_probe: ..." once, naming the
## switches in force (late, perf_worst, profiling) and the run length, so
## every log says which kind of run it is.
##
## THE END LINE: "PERF_JSON {...}" (once, when the run ends or the match is
## over). Its numbers, measured from the start of the run (25:00 with
## --late):
##   secs, late, perf_worst, profiling   the switches and the run length
##   sim_s, ticks                        game seconds and ticks measured
##   wall_ms_per_sim_s                   real milliseconds the simulation took
##                                       per game second (the mean of every
##                                       tick; the same measure as the "sim"
##                                       figure of the minute lines). It grows
##                                       when other programs use the cores.
##   worst3_ms                           the 3 slowest single ticks after the
##                                       first 2 minutes of the run, in ms
##   p50_ms, p99_ms, p999_ms             the cost that half, 99% and 99.9% of
##                                       those ticks stayed under (whole-ms
##                                       steps). One slow tick can be luck (the
##                                       PC was busy that instant); these show
##                                       whether slow ticks are the rule.
##   over_17ms, over_33ms                the share (0..1) of those ticks that
##                                       took over one frame (16.7 ms) and over
##                                       two frames (33.3 ms) at 60 fps
##   cpu_s, cpu_ms_per_sim_s             the computer time this program used
##                                       (all of it, start-up included) and
##                                       that per game second. It does not
##                                       grow when other programs compete for
##                                       the cores, so it is the better speed
##                                       number on a busy PC. -1 = could not
##                                       be read.
##
## WHO USES IT: main.gd loads it for --test=perf_probe (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()) and
## prints the "prof" lines from World.prof. Ship and Minion add their own
## keys while World.profiling is on. tools/utf_compare.py reads PERF_JSON.

## The running match (set by setup()).
var world: World
## How many game seconds to run (--secs, default 300).
var secs := 300.0
## True with --perf-worst: keep the load at its worst (see the header).
var worst_case := false
## True with --late: the run started at 25:00.
var late := false
## The match time (seconds) at which the measuring began: 0, or 25:00 with
## --late.
var _t0 := 0.0
## How many ticks have been measured, and what they cost in all
## (microseconds).
var _ticks := 0
var _usec := 0
## The three slowest ticks after the first 2 minutes of the run, slowest
## first (microseconds).
var _slow: Array = []
## Seconds until the stage 4 hook runs next (it runs once a second).
var _wings_t := 0.0
## True once PERF_JSON has been printed (it is printed only once).
var _done := false
## The first seconds of a run are left out of the "slowest ticks": the first
## ticks fill caches and are not typical.
const SKIP_SECS := 120.0
## The ticks after those first seconds, by cost: slot i holds the ticks that
## took i whole milliseconds (the last slot, HIST_MS or more).
var _hist := PackedInt32Array()
const HIST_MS := 400
## How many ticks are in the list above, and how many of them took over 33.3 ms
## (two frames at 60 fps) and over 16.7 ms (one frame).
var _counted := 0
var _over_33 := 0
var _over_17 := 0


## main.gd calls this once, right after the World is built. Turn profiling
## on, read --secs and the switches, and print the header line.
func setup(w: World) -> void:
	world = w
	_hist.resize(HIST_MS)
	world.profiling = not Game.opt("noprof", false)
	secs = float(Game.opt("secs", 300.0))
	# With --late: the late-game setup (tests/lib/late_game.gd); --secs then
	# counts from 25:00.
	late = bool(Game.opt("late", false))
	if late:
		LateGame.apply(world)
		secs += LateGame.START
	_t0 = world.time
	# With --perf-worst: the worst-case load (see the header).
	worst_case = bool(Game.opt("perf-worst", false))
	if worst_case:
		_apply_worst_case()
	Events.match_over.connect(_on_match_over)
	print("perf_probe: late=%s perf_worst=%s profiling=%s secs=%d start_t=%d" % [late, worst_case, world.profiling, int(secs - _t0), int(_t0)])
	if worst_case:
		print("perf_probe: worst-case load on: respawn waits 0 s, no AI shopping trips home, wingman hook (stage 4) idle")


## Godot calls this every tick. Count the tick, keep the worst case going,
## and quit once --secs of game time have passed.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	# Step 1: the cost of the tick the World has just run (the probe is
	# added after the World, so it runs after it in every frame).
	if world.phase == "play":
		_count(world.tick_usec)
	# Step 2: the worst-case load, if asked for.
	if worst_case:
		_keep_worst_case(dt)
	# Step 3: the end.
	if world.time >= secs:
		_finish()
		get_tree().quit()


## The match ended before --secs (a mothership fell): print the end line
## now. main.gd quits the program in the same frame.
func _on_match_over(_winner: int, _reason: String) -> void:
	_finish()


# --- the worst case (--perf-worst) -----------------------------------------------------

## Set up the worst-case load once, at the start: no waiting to respawn.
## (MatchRules.respawn_time() reads these two tuned numbers; its wait is
## base + per_minute x minutes, so 0 and 0 mean no wait at all.)
func _apply_worst_case() -> void:
	Game.tunables["respawn_base"] = 0.0
	Game.tunables["respawn_per_minute"] = 0.0


## Every tick of a --perf-worst run: keep every AI pilot "just launched", so
## that PilotShopping.wants_shopping() never sends it home to shop (it says
## "no" in the first 150 s after a launch), and run the stage 4 hook once a
## second.
func _keep_worst_case(dt: float) -> void:
	for p: PilotProfile in world.pilot_ai:
		(world.pilot_ai[p] as PilotAI).launched_at = world.time
	_wings_t -= dt
	if _wings_t <= 0.0:
		_wings_t = 1.0
		_fill_wings()


## STAGE 4 HOOK. Stage 4 (wingmen) fills this in: every pilot in space that
## has a free wingman slot buys the most wingmen it may have (up to 3 with
## the full Wing Command research), so the performance runs measure the
## heaviest load. It is called once a second while --perf-worst is on, so
## wingmen lost in a fight are bought again. Today the game has no wingmen,
## so there is nothing to do.
func _fill_wings() -> void:
	pass


# --- measuring ---------------------------------------------------------------------------------

## Remember a tick that cost `usec` microseconds.
func _count(usec: int) -> void:
	_ticks += 1
	_usec += usec
	if world.time - _t0 < SKIP_SECS:
		return
	# File the tick by its cost in whole milliseconds, and count the ticks
	# over one frame (16.7 ms) and over two frames (33.3 ms) at 60 fps.
	_counted += 1
	_hist[mini(usec / 1000, HIST_MS - 1)] += 1
	if usec > 16667:
		_over_17 += 1
		if usec > 33333:
			_over_33 += 1
	# Keep the three slowest, slowest first (the list is only touched by a tick
	# that is among the three slowest so far).
	if _slow.size() < 3 or usec > int(_slow[2]):
		_slow.append(usec)
		_slow.sort_custom(func(a: int, b: int) -> bool: return a > b)
		if _slow.size() > 3:
			_slow.resize(3)


## The cost (milliseconds) that the fraction `q` (0..1) of the counted ticks
## stayed under, read from the milliseconds list: the upper edge of the
## millisecond slot where the count reaches q (0 when nothing was counted).
func _percentile_ms(q: float) -> float:
	if _counted == 0:
		return 0.0
	var want := int(ceil(q * float(_counted)))
	var seen := 0
	for ms in HIST_MS:
		seen += _hist[ms]
		if seen >= want:
			return float(ms + 1)
	return float(HIST_MS)


## Print the PERF_JSON line (once).
func _finish() -> void:
	if _done:
		return
	_done = true
	var sim_s := maxf(1.0, float(_ticks) / 60.0)
	var cpu := _cpu_seconds()
	var worst3: Array = []
	for u: int in _slow:
		worst3.append(snappedf(float(u) / 1000.0, 0.01))
	var out := {
		"secs": int(secs - _t0), "late": late, "perf_worst": worst_case, "profiling": world.profiling,
		"sim_s": snappedf(float(_ticks) / 60.0, 0.1), "ticks": _ticks,
		"wall_ms_per_sim_s": snappedf(float(_usec) / 1000.0 / sim_s, 0.01),
		"worst3_ms": worst3,
		"p50_ms": _percentile_ms(0.5), "p99_ms": _percentile_ms(0.99), "p999_ms": _percentile_ms(0.999),
		"over_17ms": snappedf(float(_over_17) / maxf(1.0, float(_counted)), 0.0001), "over_33ms": snappedf(float(_over_33) / maxf(1.0, float(_counted)), 0.0001),
		"cpu_s": snappedf(cpu, 0.01), "cpu_ms_per_sim_s": snappedf(cpu * 1000.0 / sim_s, 0.01) if cpu >= 0.0 else -1.0,
		"ended": world.phase != "play",
	}
	print("PERF_JSON ", JSON.stringify(out))


## Seconds of computer time this program has used so far (all its threads),
## read from the operating system, or -1.0 when that cannot be done.
##   Windows: PowerShell reads the process's TotalProcessorTime (about a
##            second to start); if that fails, tasklist (whole seconds).
##   Linux:   /proc/self/stat (user plus system time, in 1/100 s).
func _cpu_seconds() -> float:
	var pid := OS.get_process_id()
	var os_name := OS.get_name()
	if os_name == "Windows":
		var out: Array = []
		var rc := OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).TotalProcessorTime.TotalSeconds" % pid], out)
		if rc == 0 and out.size() > 0:
			# (Some regional settings print a comma as the decimal point.)
			var txt := str(out[0]).strip_edges().replace(",", ".")
			if txt.is_valid_float():
				return float(txt)
		# Fall back to tasklist: its "CPU Time" column is h:mm:ss.
		out.clear()
		rc = OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/V", "/NH"], out)
		if rc == 0 and out.size() > 0:
			var cols := str(out[0]).strip_edges().split("\",\"")
			if cols.size() >= 8:
				var hms := cols[7].split(":")
				if hms.size() == 3:
					return float(hms[0]) * 3600.0 + float(hms[1]) * 60.0 + float(hms[2])
	elif os_name == "Linux":
		var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
		if f != null:
			# After "pid (name) " the fields go on from field 3, so user and
			# system time (fields 14 and 15) are items 11 and 12.
			var stat := f.get_as_text()
			var tail := stat.substr(stat.rfind(")") + 2).split(" ")
			if tail.size() > 12:
				return (float(tail[11]) + float(tail[12])) / 100.0
	return -1.0
