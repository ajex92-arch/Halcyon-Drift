extends Node
## WHAT THIS IS: a replay of the places where AI ships got stuck in the
## asteroids. It puts one pilot at each of 91 spots of the map where a ship
## was found stuck on or next to a rock, points it at the goal it had, lets
## the AI fly for a while and reports how long the ship stayed near its
## spot, how long it scraped rocks and how far from the goal it ended.
##
## HOW IT WORKS: SPOTS lists the places (found in 12 long all-AI matches), in
## 3 waves: the places of one wave are at least 45 world units apart, so no
## two ships overlap (overlapping ships push each other apart). A wave is one
## run; --st-wave=K picks it (0, 1 or 2). setup() stops the minion waves and
## makes one pilot (an AI brain, skill 0.7) per place of the wave with the hull
## the stuck ship had; it launches the ship, moves it to the place, turns its
## nose to the goal and gives the brain that goal as its hold point. There is
## nothing else to fight: run it with --no-pilots --no-jungle
## --no-admiral-ai. Every tick the ships are kept at full health and kept
## from flying home to shop. For every ship it tracks the rock contact, the
## seconds spent within NEAR_DIST of the start, the first time it got EXIT_DIST
## away, and whether it flew with an escape planned (PilotEscape). After
## --secs seconds (100 by default) it prints one "SPOT" line per ship and one
## "SPOTS_SUMMARY {...}" line, and quits. A ship counts as "trapped" when it
## is still within EXIT_DIST of its start at the end.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --sim-only --test=stuck_spots --st-wave=0 --secs=100
##
## --st-trace=N also prints a "TRACE ..." line every half second for spot
## number N (its position, speed, nose, route, escape and timers), to see
## what the brain does there.
##
## Pictures (a windowed run): with --st-mode=shots the trace harness
## (tests/stuck_trace2.gd) is added too; it follows the pilot called "spotN"
## (--st-who=spotN) and saves a picture at each time of --st-times=T1,T2,...
## (--st-dir=PATH, --st-view=N) with the rocks, the route graph, the pilot's
## route, goal and escape path drawn on it. --secs must be later than the last
## picture.
##
## HOW TO READ THE OUTPUT:
##   "SPOT 12 team=1 bomber at=(23590,15049) goal_d=2323 exit_t=14.2 near_s=31.0 rock_s=9.4 esc_s=3.5 disp=1200 goal_end=1105"
##       spot number, team, hull, place, distance to the goal at the start,
##       when the ship first got EXIT_DIST away (-1 = never), seconds within
##       NEAR_DIST of the start, seconds of rock contact, seconds with an
##       escape on, the distance from the start at the end and from the goal.
##   "SPOTS_SUMMARY {...}": the wave, how many ships, how many got out and how
##       many are trapped, the median exit time, and the totals of the other
##       numbers.
##
## WHO USES IT: main.gd loads it for --test=stuck_spots. It reads the
## brains' hold_point, launched_at and flight state, and the asteroid field's
## contacts; it makes PilotProfile and PilotAI objects the way ArenaKit does.

## The trace harness, which takes the pictures in a windowed run.
const TRACE := preload("res://tests/stuck_trace2.gd")
## The places: [wave, team, hull id, x, y, goal x, goal y] (world units). They
## come from the stuck episodes of 12 long all-AI matches (one place for each
## team, hull and 50-unit square), so the same places repeat across matches.
const SPOTS := [	[0, 1, "bomber", 11600, 20389, 14856, 21750],
	[0, 1, "bomber", 29352, 14978, 30225, 13479],
	[0, 1, "fighter", 11351, 11090, 13209, 12550],
	[0, 0, "fighter", 14853, 14940, 16471, 9531],
	[0, 1, "fighter", 15612, 5679, 17737, 3800],
	[0, 0, "fighter", 15664, 5678, 17779, 4250],
	[0, 0, "fighter", 18216, 18752, 24785, 21750],
	[0, 1, "fighter", 21806, 18745, 12284, 22200],
	[0, 0, "fighter", 24350, 5718, 26184, 4250],
	[0, 0, "fighter", 25147, 11063, 25429, 13000],
	[0, 1, "fighter", 25201, 14967, 35570, 13000],
	[0, 0, "fighter", 28154, 20295, 31486, 21822],
	[0, 0, "lance", 14844, 15030, 16471, 9531],
	[0, 0, "lance", 18088, 18632, 22974, 17044],
	[0, 1, "lance", 25115, 14854, 17038, 16795],
	[0, 1, "lance", 25125, 11133, 23691, 9443],
	[0, 1, "lance", 25131, 15066, 23528, 9532],
	[0, 0, "scout", 8244, 17970, 8146, 21086],
	[0, 1, "bomber", 14162, 14970, 13655, 22200],
	[0, 1, "bomber", 16161, 14996, 13533, 3350],
	[0, 1, "bomber", 16410, 15049, 16830, 12724],
	[0, 1, "bomber", 16418, 10708, 13533, 3350],
	[0, 1, "bomber", 16691, 10559, 16830, 12724],
	[0, 0, "bomber", 23243, 15070, 16988, 12578],
	[0, 0, "bomber", 23561, 15067, 23171, 12724],
	[0, 0, "bomber", 23629, 15099, 22482, 22200],
	[0, 0, "bomber", 23717, 15128, 28895, 22367],
	[0, 0, "bomber", 23732, 15201, 29433, 21750],
	[0, 0, "bomber", 23762, 10712, 23171, 12724],
	[0, 0, "bomber", 23817, 15034, 23171, 12724],
	[0, 1, "bomber", 27265, 20308, 35570, 13000],
	[0, 1, "bomber", 29447, 14928, 31056, 13362],
	[0, 1, "fighter", 8197, 18228, 18391, 22650],
	[0, 0, "fighter", 10469, 5703, 11012, 3415],
	[0, 1, "fighter", 12735, 20290, 11101, 22650],
	[0, 1, "fighter", 16228, 10705, 20919, 11600],
	[0, 1, "fighter", 16340, 15119, 20003, 12050],
	[0, 0, "fighter", 16638, 20112, 4430, 13000],
	[0, 1, "fighter", 18155, 20297, 15718, 22650],
	[0, 1, "fighter", 18295, 9173, 19843, 12050],
	[0, 1, "fighter", 18303, 6135, 35570, 13000],
	[0, 0, "fighter", 21698, 8286, 4430, 13000],
	[0, 0, "fighter", 21845, 20297, 26083, 22200],
	[0, 1, "fighter", 21926, 6261, 23797, 4250],
	[0, 1, "fighter", 23269, 10631, 20233, 12050],
	[0, 0, "fighter", 25240, 14909, 24099, 13450],
	[0, 1, "fighter", 25838, 14952, 26027, 12550],
	[0, 1, "fighter", 28241, 15450, 23605, 12537],
	[0, 0, "fighter", 29531, 5702, 10300, 4250],
	[0, 1, "fighter", 29626, 10919, 29160, 12550],
	[0, 0, "lance", 14762, 14912, 16464, 9529],
	[0, 1, "scout", 26191, 11066, 35570, 13000],
	[0, 0, "bomber", 13617, 24188, 26382, 13000],
	[0, 0, "bomber", 18184, 14524, 21696, 4250],
	[0, 0, "bomber", 22583, 14767, 20598, 12421],
	[0, 1, "bomber", 27617, 24202, 29379, 22459],
	[0, 1, "fighter", 12933, 1904, 12172, 3350],
	[0, 0, "fighter", 17334, 10416, 23401, 12955],
	[0, 1, "fighter", 27595, 1823, 27748, 4250],
	[0, 1, "ion", 20249, 12829, 18121, 4250],
	[0, 0, "fighter", 13226, 16382, 16155, 16832],
	[0, 0, "fighter", 13606, 8987, 16150, 9085],
	[0, 0, "fighter", 13615, 8938, 4430, 13000],
	[0, 0, "fighter", 13644, 8891, 4430, 13000],
	[0, 0, "fighter", 13652, 8789, 4430, 13000],
	[0, 0, "fighter", 13678, 8628, 16156, 9028],
	[0, 0, "fighter", 23226, 15899, 17045, 16833],
	[0, 1, "fighter", 25997, 6400, 27970, 4250],
	[0, 1, "fighter", 26319, 8611, 23844, 9028],
	[0, 0, "lance", 14045, 6616, 10604, 8202],
	[0, 0, "lance", 14610, 16900, 16150, 16900],
	[0, 0, "lance", 16777, 15904, 16612, 9550],
	[0, 1, "lance", 28512, 17392, 27311, 12803],
	[0, 1, "lance", 29331, 19410, 23814, 17075],
	[1, 0, "fighter", 15614, 5680, 15445, 3350],
	[1, 1, "fighter", 21846, 18734, 10032, 22650],
	[1, 1, "fighter", 24358, 5687, 22784, 4250],
	[1, 0, "lance", 18203, 18749, 22976, 17051],
	[1, 1, "bomber", 16175, 15027, 29700, 22200],
	[1, 0, "bomber", 23590, 15049, 23171, 12724],
	[1, 0, "bomber", 23839, 14997, 30874, 22200],
	[1, 1, "fighter", 16410, 15042, 16598, 13068],
	[1, 0, "bomber", 22583, 14781, 28999, 4121],
	[1, 0, "fighter", 13621, 8925, 4430, 13000],
	[1, 0, "fighter", 13649, 8856, 4430, 13000],
	[1, 0, "fighter", 13664, 8746, 4430, 13000],
	[1, 0, "lance", 13678, 8623, 10649, 8429],
	[2, 1, "lance", 18214, 18752, 22976, 17051],
	[2, 0, "bomber", 23594, 15093, 29134, 22126],
	[2, 0, "bomber", 23851, 15028, 23171, 12724],
	[2, 0, "fighter", 13629, 8929, 4430, 13000],
]
## How many waves SPOTS has.
const WAVES := 3
## How far from its start (world units) a ship must get to count as out.
const EXIT_DIST := 400.0
## A ship is "near" its start while it is within this many world units of it.
const NEAR_DIST := 400.0
## The skill (0..1) given to every pilot, so the seat does not matter.
const SKILL := 0.7

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to quit (--secs).
var secs := 100.0
## The wave of SPOTS being replayed (--st-wave).
var wave := 0
## The spot number whose brain is traced every half second (--st-trace; -1 =
## none).
var trace_spot := -1
## One record per ship: {"i": spot number, "ship": the ship, "ai": its brain,
## "row": the SPOTS row, "start": where it began, "rock": ticks of rock
## contact, "near": ticks within NEAR_DIST of the start, "esc": ticks with an
## escape on, "exit": game time it first got EXIT_DIST away (-1 = not yet)}.
var recs: Array = []


## main.gd calls this once, right after the World is built. Stop the minion
## waves and make the ships of the wave.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 100.0))
	wave = int(str(Game.opt("st-wave", "0")))
	trace_spot = int(str(Game.opt("st-trace", "-1")))
	world.minion_director.next_wave = INF
	var n := 0
	for i in SPOTS.size():
		var row: Array = SPOTS[i]
		if int(row[0]) != wave:
			continue
		var p := PilotProfile.new("spot%d" % i, int(row[1]), n % Rules.PILOTS_PER_TEAM, false)
		p.hull_id = str(row[2])
		p.role = "mid"
		world.profiles.append(p)
		var ai := PilotAI.new(world, p)
		ai.skill = SKILL
		world.pilot_ai[p] = ai
		var s := world.launch(p)
		if s == null:
			print("stuck_spots: spot %d could not launch" % i)
			continue
		var at := Vector2(float(row[3]), float(row[4]))
		var goal := Vector2(float(row[5]), float(row[6]))
		s.global_position = at
		s.rotation = (goal - at).angle()
		s.velocity = Vector2.ZERO
		ai._reset_after_launch()
		ai.hold_point = goal
		recs.append({"i": i, "ship": s, "ai": ai, "row": row, "start": at, "rock": 0, "near": 0, "esc": 0, "exit": -1.0})
		n += 1
	print("stuck_spots: wave %d, %d ships" % [wave, recs.size()])
	# A windowed run with pictures: the trace harness follows one spot's pilot.
	if str(Game.opt("st-mode", "")) == "shots":
		var shots := TRACE.new()
		add_child(shots)
		shots.call("setup", w)


## Godot calls this every tick: keep the ships healthy and from shopping,
## track them, and at the end print the report and quit.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	for r in recs:
		var sv: Variant = r["ship"]
		if not is_instance_valid(sv) or not (sv as Ship).alive:
			continue
		var s: Ship = sv
		s.hull = s.hull_max
		(r["ai"] as PilotAI).launched_at = world.time
		# Rock contact: the last move slid along something that is not a unit.
		for k in s.get_slide_collision_count():
			if not (s.get_slide_collision(k).get_collider() is Unit):
				r["rock"] += 1
				break
		var d := s.global_position.distance_to(r["start"])
		if d <= NEAR_DIST:
			r["near"] += 1
		if r["exit"] < 0.0 and d >= EXIT_DIST:
			r["exit"] = world.time
		if (r["ai"] as PilotAI).flight.escape.is_active():
			r["esc"] += 1
		if int(r["i"]) == trace_spot and int(world.time * 60.0 + 0.5) % 30 == 0:
			_trace_line(s, r["ai"])
	if world.time >= secs:
		_report()
		get_tree().quit()


## Print one TRACE line for ship `s` (brain `ai`): where it is, how fast, where
## its nose points, the route (position in it and the waypoint), the escape
## (on, waypoints, stuck-timer fires) and the stuck and back-off timers, and
## the controls.
func _trace_line(s: Ship, ai: PilotAI) -> void:
	var esc := ai.flight.escape
	var wp := Vector2.ZERO
	if not ai.path.is_empty():
		wp = ai.path[mini(ai.path_i, ai.path.size() - 1)]
	print("TRACE t=%.1f p=(%d,%d) v=%d rot=%.2f state=%s goal=(%d,%d) path=%d/%d wp=(%d,%d) esc=%d/%d fires=%d stk=%.1f unst=%.1f fwd=%.2f str=%.2f slides=%d tgt=%d" % [
		world.time, s.global_position.x, s.global_position.y, s.velocity.length(), s.rotation, ai.state, ai.goal.x, ai.goal.y, ai.path_i, ai.path.size(), wp.x, wp.y,
		1 if esc.is_active() else 0, esc._path.size(), esc._fires, ai.flight._stuck_t, ai.flight._unstick_t, s.controls.forward, s.controls.strafe, s.get_slide_collision_count(),
		1 if ai.target != null else 0])


## Print one SPOT line per ship and the summary line.
func _report() -> void:
	var exits: Array = []
	var trapped := 0
	var near_total := 0.0
	var rock_total := 0.0
	var goal_total := 0.0
	for r in recs:
		var sv: Variant = r["ship"]
		if not is_instance_valid(sv):
			continue
		var s: Ship = sv
		var row: Array = r["row"]
		var goal := Vector2(float(row[5]), float(row[6]))
		var disp := s.global_position.distance_to(r["start"])
		var near_s := float(r["near"]) / 60.0
		var rock_s := float(r["rock"]) / 60.0
		var exit_t: float = r["exit"]
		print("SPOT %d team=%d %s at=(%d,%d) goal_d=%d exit_t=%.1f near_s=%.1f rock_s=%.1f esc_s=%.1f disp=%d goal_end=%d" % [r["i"], int(row[1]), row[2], int(row[3]), int(row[4]),
			int((r["start"] as Vector2).distance_to(goal)), exit_t, near_s, rock_s, float(r["esc"]) / 60.0, int(disp), int(s.global_position.distance_to(goal))])
		if exit_t >= 0.0:
			exits.append(exit_t)
		if disp < EXIT_DIST:
			trapped += 1
		near_total += near_s
		rock_total += rock_s
		goal_total += s.global_position.distance_to(goal)
	exits.sort()
	var median := -1.0
	if not exits.is_empty():
		median = exits[exits.size() / 2]
	print("SPOTS_SUMMARY ", JSON.stringify({"wave": wave, "ships": recs.size(), "exited": exits.size(), "trapped": trapped, "median_exit_s": snappedf(median, 0.1),
		"near_s": snappedf(near_total, 0.1), "rock_s": snappedf(rock_total, 0.1), "goal_end_mean": roundi(goal_total / maxf(1.0, float(recs.size())))}))