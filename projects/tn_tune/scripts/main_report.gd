class_name MainReport
extends RefCounted
## WHAT THIS IS: the match reporter. In test runs it prints a short report
## every minute of match time (how fast the simulation runs, how many
## units there are, how each team is doing), and at the end one "SUMMARY"
## line with the result.
##
## HOW IT WORKS: main.gd calls count_tick() every physics tick. It adds up
## how long the World's simulation took (World.tick_usec) and remembers
## the slowest tick. Once 60 seconds of match time have passed since the
## last report, it prints a new one (print_minute) and starts counting
## again from zero. At the end of the match main.gd calls print_minute()
## one last time and then print_summary(), which prints the result as
## JSON and, with --report=<path>, also saves it to that file.
##
## WHO USES IT: main.gd makes one (its `reports` variable) and calls all
## three functions. Test tools read the printed lines, so the wording and
## layout of every print must stay exactly as they are.
##
## Words used here: a "tick" is one small step of game time (normally 60
## per second). "ms" means milliseconds (thousandths of a second) and
## "usec" microseconds (millionths of a second). "sim-s" is one second of
## match time, counted as 60 ticks. JSON is a common text format for data
## that other programs can read easily.

## Match time (seconds) when the last minute report was printed.
var _report_t := 0.0
## Physics ticks counted since the last report.
var _frames := 0
## The simulation time of those ticks added together (microseconds).
var _usec := 0
## The slowest of those ticks (microseconds).
var _worst := 0


## Count one physics tick of `world`, and print the minute report once 60
## seconds of match time have passed since the last one.
func count_tick(world: World) -> void:
	# Step 1: add this tick's cost and remember the slowest tick.
	_frames += 1
	_usec += world.tick_usec
	_worst = maxi(_worst, world.tick_usec)
	# Step 2: a minute of match time since the last report? Print one.
	if world.time - _report_t >= 60.0:
		_report_t = world.time
		print_minute(world)


## Print the minute report, then start counting again. The first line has
## the match clock, the simulation cost (ms of computer time per second of
## match time, and the slowest tick in ms), how many units, ships, minions,
## mining drones and projectiles exist, and the frames drawn per second.
## Then one line per team: tr = treasury (credits), ore = all ore
## delivered, fac = facilities owned, tech = research finished, turrets =
## live turrets, killed_turrets = enemy turrets destroyed, K/D = the
## pilots' kills and deaths added up, avg_cr = the pilots' credits divided
## by 12 (the number of pilots per team), ms and sh = the mothership's hull
## and shields in percent, flying = hull id -> how many ships of it are out.
## With --profile there is one more line: ms per sim-s for each part of the
## tick (World.prof), which is then emptied.
func print_minute(world: World) -> void:
	# Step 1: the overall line. Sim-seconds = ticks / 60 (at least 1).
	var ms_per_sim_s := float(_usec) / 1000.0 / maxf(1.0, float(_frames) / 60.0)
	print("t=%s  sim %.1f ms/sim-s  worst tick %.1f ms  units=%d ships=%d minions=%d drones=%d projectiles=%d fps=%d" % [
		Util.clock(world.time), ms_per_sim_s, _worst / 1000.0, world.units.size(), world.ships.size(),
		world.minions.size(), world.mining_drones.size(), world.projectiles.count(), Engine.get_frames_per_second()])
	# Step 2: one line per team (0 = Halcyon, 1 = Cinder).
	for t in 2:
		var ts := world.teams[t]
		var ms := world.mothership(t)
		# Count this team's live turrets.
		var turrets := 0
		for tu in world.turrets:
			if tu.team == t and tu.alive:
				turrets += 1
		# Count this team's ships in space by hull: hull id -> count.
		var hulls := {}
		for s in world.ships:
			if s.team == t:
				hulls[s.hull_id] = int(hulls.get(s.hull_id, 0)) + 1
		# Add up this team's pilots: credits, kills and deaths.
		var credits := 0.0
		var k := 0
		var d := 0
		for p in world.profiles:
			if p.team == t:
				credits += p.credits
				k += p.kills
				d += p.deaths
		print("  %s tr=%d ore=%d fac=%d tech=%d turrets=%d killed_turrets=%d K/D=%d/%d avg_cr=%d ms=%d%% sh=%d%% flying=%s" % [
			Rules.TEAM_NAMES[t], int(ts.treasury), int(ts.ore_delivered), ts.facilities.size(), ts.done.size(), turrets,
			ts.turrets_destroyed, k, d, int(credits / 12.0), int(ms.hull_frac() * 100.0), int(ms.shields.fraction() * 100.0), hulls])
	# Step 3: --profile: the cost of each part of the tick, then reset it.
	if world.profiling:
		var parts := []
		for key in world.prof:
			parts.append("%s=%.1f" % [key, float(world.prof[key]) / 1000.0 / maxf(1.0, float(_frames) / 60.0)])
		print("  prof ms/sim-s: ", ", ".join(parts))
		world.prof.clear()
	# Step 4: start counting the next minute from zero.
	_frames = 0
	_usec = 0
	_worst = 0


## Print the end-of-match "SUMMARY" line: `result` (such as "time limit" or
## "Halcyon wins: ..."), the match time (seconds), the winner (-1 = none
## yet), the rule variants, and for each team: ore delivered, ship kills,
## turrets destroyed, the mothership's hull (a 0..1 fraction) and when each
## unlock finished. With --report=<path> the same data is also written to
## that file, indented with two spaces so people can read it.
func print_summary(world: World, result: String) -> void:
	# Step 1: gather the result and each team's numbers.
	var out := {"result": result, "time": world.time, "winner": world.winner, "variants": Game.variants}
	for t in 2:
		var ts := world.teams[t]
		out[Rules.TEAM_NAMES[t]] = {"ore": ts.ore_delivered, "kills": ts.kills, "turrets_destroyed": ts.turrets_destroyed,
			"mothership": world.mothership(t).hull_frac(), "unlocks": ts.unlock_times}
	# Step 2: print it as one JSON line.
	print("SUMMARY ", JSON.stringify(out))
	# Step 3: --report=<path>: also save it to that file (if it opens).
	var path: String = str(Game.opt("report", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
