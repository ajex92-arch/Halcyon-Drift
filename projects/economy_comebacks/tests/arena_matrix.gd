extends Node
## WHAT THIS IS: the arena measures of the fun experiments, in one run
## (docs/FUN_RESEARCH.md, fun model ingredients 7 and 8):
##   - the DUEL CURVE: does skill decide fights? A fighter flown at skill
##     0.90 duels a fighter flown at 0.55, 20 times. Result: the skilled
##     pilot's win rate (duel_skill_winrate; the target band is 0.70-0.85).
##   - the EQUAL-CREDIT MATRIX: are big ships "inherently better"? Four
##     match-ups where both sides cost about the same, every pilot at skill
##     0.72, 10 runs each: 7 fighters vs 1 flak frigate, 3 bombers vs 1 flak
##     frigate, 6 bombers vs 1 destroyer, 4 lances vs 1 ion frigate. Result:
##     the small side's mean win rate (arena_small_winrate; target
##     0.40-0.60).
## It prints one line, DUEL_JSON {...}, at the end.
##
## HOW IT WORKS: every fight is an arena fight (tests/arena.gd's setup,
## from tests/lib/arena_kit.gd: open space on the north-south connector,
## squads 1,000 world units either side of the centre, both holding the
## same ground, nobody may fly home to shop, a pilot that docks or dies is
## out). The fights run one after another in the same match: when one ends
## (a side is gone, or the time limit), the survivors are removed quietly,
## their pilot records are deleted, and after an 8-second pause (so shots
## still in flight run out) the next fight starts. Sides are alternated so
## neither team nor map side favours anyone: run i puts the focus side
## (the skilled pilot, or the small ships) on Halcyon when i is even and on
## Cinder when i is odd, and swaps the map sides (east/west) every second
## pair of runs, so all four team/side combinations come up equally.
## A win rate counts a draw (both sides alive at the time limit, or both
## gone at once) as half a win.
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom.)
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --seed=1 --test=arena_matrix
## --no-pilots, --no-jungle and --no-admiral-ai leave only our squads in
## space; --fixed-fps 60 runs as fast as the computer can. Its own options:
##   --duels=N     duels to fight (default 20)
##   --runs=N      runs per matrix match-up (default 10)
##   --only=duel   only the duel curve; --only=matrix only the matrix
##   --limit=S     the time limit of one fight, in seconds (default 180)
##
## HOW TO READ THE OUTPUT: one line per fight, such as
##   "fight 3/60 duel: Halcyon [fighter] @0.55 vs Cinder [fighter] @0.90,
##    swap no -> Cinder wins after 41s (focus side: win)"
## and at the end "DUEL_JSON {...}" with "duel_skill_winrate",
## "arena_small_winrate" and the details. tools/fun_score.py reads the
## DUEL_JSON line when it sits in the same folder as the FUN_JSON logs.
##
## WHO USES IT: main.gd loads it for --test=arena_matrix (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()).
## The fun experiments run it once per build (docs/FUN_PLAN.md).

## The arena toolkit: squads, keeping pilots in the fight, who is alive.
const ArenaKit := preload("res://tests/lib/arena_kit.gd")
## The duel hull.
const DUEL_HULL := "fighter"
## The skilled duellist's skill (PilotAI.skill, 0..1).
const SKILL_HI := 0.90
## The weaker duellist's skill.
const SKILL_LO := 0.55
## Every pilot's skill in the matrix.
const MATRIX_SKILL := 0.72
## The equal-credit match-ups: `n` small ships of hull `small` against one
## `big` (prices: fighter 150, bomber 350, lance 300, flak frigate 1,100,
## ion frigate 1,250, destroyer 2,200 credits).
const MATCHUPS := [
	{"name": "7 fighters vs flak frigate", "small": "fighter", "n": 7, "big": "flak"},
	{"name": "3 bombers vs flak frigate", "small": "bomber", "n": 3, "big": "flak"},
	{"name": "6 bombers vs destroyer", "small": "bomber", "n": 6, "big": "destroyer"},
	{"name": "4 lances vs ion frigate", "small": "lance", "n": 4, "big": "ion"},
]
## The pause between fights (seconds), so shots still in flight run out.
const GAP := 8.0

## The running match (set by setup()).
var world: World
## Every fight to run, in order. Each is {"kind": "duel" or "matrix", "m":
## match-up number (-1 for duels), "a"/"b": Halcyon's/Cinder's hull ids,
## "ska"/"skb": their skills, "swap": map sides swapped, "focus": "a" or
## "b", the side whose win rate we report}.
var plan: Array = []
## The number of the fight running now (-1 while pausing).
var cur := -1
## The number of the next fight to start.
var next := 0
## Halcyon's ships in the fight running now.
var a: Array = []
## Cinder's ships in the fight running now.
var b: Array = []
## Seconds since the fight running now began.
var fight_t := 0.0
## Seconds left of the pause before the next fight.
var pause_t := 1.0
## The time limit of one fight (seconds; --limit).
var limit := 180.0
## One result per fight: [kind, match-up, swap, focus side, result for
## the focus side ("win"/"loss"/"draw"), seconds].
var results: Array = []
## True once DUEL_JSON has been printed.
var _done := false


## main.gd calls this once, right after the World is built. Stop the minion
## waves and write the fight plan (see HOW IT WORKS).
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	limit = float(Game.opt("limit", 180.0))
	var only := str(Game.opt("only", ""))
	# Step 1: the duels: the skilled pilot on Halcyon for even runs, on
	# Cinder for odd ones; map sides swapped every second pair.
	if only != "matrix":
		for i in int(Game.opt("duels", 20)):
			var hi_on_a := i % 2 == 0
			plan.append({"kind": "duel", "m": -1, "a": [DUEL_HULL], "b": [DUEL_HULL],
				"ska": SKILL_HI if hi_on_a else SKILL_LO, "skb": SKILL_LO if hi_on_a else SKILL_HI,
				"swap": i % 4 >= 2, "focus": "a" if hi_on_a else "b"})
	# Step 2: the matrix: the small side on Halcyon for even runs, on Cinder
	# for odd ones; map sides swapped every second pair.
	if only != "duel":
		for m in MATCHUPS.size():
			var mu: Dictionary = MATCHUPS[m]
			var small: Array = []
			for k in int(mu["n"]):
				small.append(mu["small"])
			for i in int(Game.opt("runs", 10)):
				var small_on_a := i % 2 == 0
				plan.append({"kind": "matrix", "m": m, "a": small if small_on_a else [mu["big"]], "b": [mu["big"]] if small_on_a else small,
					"ska": MATRIX_SKILL, "skb": MATRIX_SKILL, "swap": i % 4 >= 2, "focus": "a" if small_on_a else "b"})
	print("arena_matrix: %d fights, limit %ds" % [plan.size(), int(limit)])


## Godot calls this every tick; `dt` is the tick's length in seconds. Run
## the fight that is on, or count down the pause and start the next one;
## after the last fight print DUEL_JSON and quit.
func _physics_process(dt: float) -> void:
	if world == null or _done:
		return
	# A fight is on: keep the pilots fighting, and end it when a side is
	# gone or time is up.
	if cur >= 0:
		fight_t += dt
		ArenaKit.keep_in_fight(world)
		var na := ArenaKit.alive_count(a)
		var nb := ArenaKit.alive_count(b)
		if na == 0 or nb == 0 or fight_t > limit:
			_end_fight(na, nb)
		return
	# Pausing: wait, then start the next fight (or finish).
	pause_t -= dt
	if pause_t > 0.0:
		return
	if next < plan.size():
		_start_fight(next)
		next += 1
	else:
		_done = true
		print("DUEL_JSON " + JSON.stringify(_summary()))
		get_tree().quit()


## Start fight number `i` of the plan: both squads, with their skills.
func _start_fight(i: int) -> void:
	var f: Dictionary = plan[i]
	var tag := "f%d-" % i
	a = ArenaKit.squad(world, Rules.HALCYON, PackedStringArray(f["a"]), f["swap"], float(f["ska"]), tag)
	b = ArenaKit.squad(world, Rules.CINDER, PackedStringArray(f["b"]), f["swap"], float(f["skb"]), tag)
	fight_t = 0.0
	cur = i


## The fight running now is over, with `na` Halcyon and `nb` Cinder ships
## alive. Note the result, print a line, clear the arena, start the pause.
func _end_fight(na: int, nb: int) -> void:
	var f: Dictionary = plan[cur]
	# Step 1: who won: a side with ships left against an empty side; else a
	# draw (time limit, or both gone at once).
	var win := "draw"
	if na > 0 and nb == 0:
		win = "a"
	elif nb > 0 and na == 0:
		win = "b"
	var res := "draw" if win == "draw" else ("win" if win == f["focus"] else "loss")
	results.append([f["kind"], f["m"], f["swap"], f["focus"], res, int(fight_t)])
	var who := "draw" if win == "draw" else "%s wins" % Rules.TEAM_NAMES[0 if win == "a" else 1]
	print("fight %d/%d %s: Halcyon %s @%.2f vs Cinder %s @%.2f, swap %s -> %s after %ds (focus side: %s)" % [cur + 1, plan.size(), f["kind"],
		f["a"], float(f["ska"]), f["b"], float(f["skb"]), "yes" if f["swap"] else "no", who, int(fight_t), res])
	# Step 2: clear the arena: remove the survivors quietly and delete this
	# fight's pilot records, so they never come back.
	for s in a + b:
		if is_instance_valid(s) and s.alive:
			world.combat.kill_silently(s)
	for p: PilotProfile in world.pilot_ai.keys():
		world.profiles.erase(p)
		world.pilot_ai.erase(p)
	a = []
	b = []
	cur = -1
	pause_t = GAP


## Win, loss and draw counts of the focus side over the results that pass
## `keep` (a function of one result row), as {"runs", "wins", "losses",
## "draws", "winrate" (draws count half), "mean_secs"}.
func _tally(keep: Callable) -> Dictionary:
	var n := 0
	var w := 0
	var l := 0
	var secs := 0.0
	for r: Array in results:
		if not keep.call(r):
			continue
		n += 1
		secs += float(r[5])
		if r[4] == "win":
			w += 1
		elif r[4] == "loss":
			l += 1
	var rate: Variant = null
	if n > 0:
		rate = snappedf((float(w) + 0.5 * float(n - w - l)) / float(n), 0.001)
	return {"runs": n, "wins": w, "losses": l, "draws": n - w - l, "winrate": rate, "mean_secs": snappedf(secs / maxf(1.0, float(n)), 0.1)}


## The DUEL_JSON dictionary: the duel curve, every match-up, and the two
## numbers tools/fun_score.py scores.
func _summary() -> Dictionary:
	# Step 1: the duel curve (the skilled pilot is the focus side).
	var duel := _tally(func(r: Array) -> bool: return r[0] == "duel")
	duel["hull"] = DUEL_HULL
	duel["skill_hi"] = SKILL_HI
	duel["skill_lo"] = SKILL_LO
	# Step 2: each match-up (the small side is the focus side), and the
	# mean of their small-side win rates.
	var matrix: Array = []
	var rates: Array = []
	for m in MATCHUPS.size():
		var row := _tally(func(r: Array) -> bool: return r[0] == "matrix" and int(r[1]) == m)
		if int(row["runs"]) == 0:
			continue
		row.merge(MATCHUPS[m])
		matrix.append(row)
		rates.append(float(row["winrate"]))
	var small_rate: Variant = null
	if not rates.is_empty():
		var total := 0.0
		for x: float in rates:
			total += x
		small_rate = snappedf(total / float(rates.size()), 0.001)
	return {
		"probe": "arena_matrix",
		"version": 1,
		"seed": int(Game.opt("seed", -1)),
		"limit_secs": int(limit),
		"matrix_skill": MATRIX_SKILL,
		"duel": duel if int(duel["runs"]) > 0 else null,
		"matrix": matrix,
		"duel_skill_winrate": duel["winrate"],
		"arena_small_winrate": small_rate,
		"fights": results,
	}
