extends Node
## WHAT THIS IS: a behaviour fingerprint. It runs a seeded all-AI match and
## every 5 seconds of game time prints a "hash" of the whole game state. (A
## hash is one short number made from a long text: if even one letter of
## the text changes, the number almost always changes too.) It proves that
## a code change did not change what the game does.
##
## HOW IT WORKS: two runs of the same build with the same --seed (the
## starting number for all the game's random rolls) print the same hashes,
## and so does a refactor (a tidy-up of the code) that changes nothing. If
## a change does alter the game, the first line that differs shows when
## the two builds started behaving differently. Each hash is made by
## _fingerprint(): it writes every live unit, every pilot and both
## treasuries into one long text and hashes it.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=1 --test=det_hash --secs=600
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second, which a
## repeatable run needs. --secs is how many game seconds to run (default
## 600).
##
## --late starts the match at 25:00 with both sides fully teched and rich
## (LateGame.apply, the same setup as tests/endgame.gd), so sieges,
## capital ships and the defend call run within the first minutes;
## --secs then counts from 25:00.
##
## HOW TO READ THE OUTPUT:
##   "hash t=5 412 units, 1a2b3c4d"  at game time 5 s there were 412 units
##       in the match, and the state's hash was 1a2b3c4d (8 hex digits).
##   "DET_HASH END t=600 ..."  the same, once, at the end.
## Compare the "hash" lines of two runs: they must be the same, line by
## line.
##
## WHO USES IT: main.gd loads it for --test=det_hash (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()).
## docs/CODE_STYLE.md (Part 3) uses it to prove that a refactor keeps the
## game's behaviour.

## The running match (set by setup()).
var world: World
## Game time (seconds) at which to stop (--secs, default 600; with --late
## the 25:00 start is added on).
var secs := 600.0
## Game time (seconds) of the next hash line.
var next_t := 5.0


## main.gd calls this once, right after the World is built. Read --secs and,
## with --late, jump to the late-game setup.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 600.0))
	# With --late: the late-game setup (tests/lib/late_game.gd); --secs
	# and the hash lines then count from 25:00.
	if Game.opt("late", false):
		LateGame.apply(world)
		secs += LateGame.START
		next_t = LateGame.START + 5.0


## Godot calls this every tick. Print a hash line every 5 game seconds, and
## a last line (then quit) at the end time or when the match is over.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time >= next_t:
		next_t += 5.0
		print("hash t=%d %s" % [int(world.time), _fingerprint()])
	if world.time >= secs or world.phase != "play":
		print("DET_HASH END t=%d %s" % [int(world.time), _fingerprint()])
		get_tree().quit()


## One string that changes if anything about the match changes: every unit's
## kind, team, position and hull (rounded so float printing can't wobble),
## every pilot's credits and state, both treasuries, and the projectile count.
func _fingerprint() -> String:
	var parts := PackedStringArray()
	# Every live unit: "kind:team:x,y:hull" (whole numbers).
	for u: Unit in world.units:
		if u.alive:
			parts.append("%d:%d:%d,%d:%d" % [u.kind, u.team, roundi(u.global_position.x), roundi(u.global_position.y), roundi(u.hull)])
	# Every pilot: "callsign:credits:state".
	for p: PilotProfile in world.profiles:
		parts.append("%s:%d:%s" % [p.callsign, roundi(p.credits), p.state])
	# Both treasuries, and how many shots are in flight.
	for t in 2:
		parts.append("tr%d:%d" % [t, roundi(world.teams[t].treasury)])
	parts.append("proj:%d" % world.projectiles.count())
	# Join it all into one long text and hash it (%08x = 8 hex digits).
	var s := "|".join(parts)
	return "%d units, %08x" % [world.units.size(), hash(s)]
