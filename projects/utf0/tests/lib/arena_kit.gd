extends RefCounted
## WHAT THIS IS: the shared toolkit of the arena tests: it builds a squad of
## AI pilots in open space, keeps them in the fight, and says who is still
## alive.
##
## HOW IT WORKS: the arena is open space on the north-south connector, the
## same distance from both motherships (CENTER). squad() makes one AI pilot
## per hull, launches the ships and lines them up in a column 300 world
## units apart, 1,000 units to one side of CENTER, all facing the middle.
## Every pilot is told to hold a spot 500 units from CENTER on its own side,
## so both squads want the same ground and must fight for it. Aurelian starts
## west and Cinder east; `swap` turns that round (this tells "which side of
## the map" apart from "which team"). keep_in_fight(), called every tick,
## stops pilots from flying home to shop, and takes any pilot that docks
## anyway (or dies) out for good.
## (A "world unit" is the game's distance unit, about one pixel at normal
## zoom. This is a "static library": plain functions with no memory.)
##
## WHO USES IT: tests/arena.gd (one fight) and tests/arena_matrix.gd (many
## fights in a row) load it with preload(). It makes PilotAI brains, sets
## their skill, hold_point and launched_at, and calls their
## _reset_after_launch() (see pilot_ai.gd).

## The middle of the arena (world units): open space on the north-south
## connector, the same distance from both motherships (not on a resource
## node: its ore rocks block beams and sight).
## Playtest: it used to sit in Aurelian's base clearing. Damaged Aurelian
## ships flew back and docked there within seconds (counted as out), and
## Cinder ships that drifted west met Aurelian's mothership guns, so two
## identical squads finished 11-2 for Cinder.
const CENTER := Vector2(20000, 8600)
## How far from CENTER each squad starts (world units).
const START_GAP := 1000.0
## How far from CENTER each pilot holds its spot (world units).
const HOLD_GAP := 500.0
## The gap between ships in a squad's column (world units).
const ROW_GAP := 300.0
## A pilot that docks or dies is "dead" with this respawn wait (seconds):
## out for good.
const OUT_FOR_GOOD := 9999.0


## Which side of CENTER team `team` fights on: -1 = west, +1 = east.
## Aurelian is west and Cinder east, unless `swap`.
static func side(team: int, swap: bool) -> float:
	var s := -1.0 if team == Rules.HALCYON else 1.0
	return -s if swap else s


## Make one squad for team `team`: one AI pilot per hull id in `hulls`,
## launched in a column centred START_GAP from CENTER on the team's side
## (see side()) and facing CENTER. `skill` (0..1) sets every pilot's
## PilotAI.skill; below 0 keeps the skill of its seat number. `tag` is put
## in front of the callsigns (so pilots of different fights have different
## names). Returns the squad's ships.
static func squad(world: World, team: int, hulls: PackedStringArray, swap: bool, skill: float = -1.0, tag: String = "") -> Array:
	var out: Array = []
	var sx := side(team, swap)
	var at := CENTER + Vector2(START_GAP * sx, 0)
	var i := 0
	for hid in hulls:
		# Step 1: a pilot record ("profile") named like "fighter-0", seat i,
		# not a human, who will fly hull `hid` in the mid lane role.
		var p := PilotProfile.new("%s%s-%d" % [tag, hid, i], team, i, false)
		p.hull_id = hid
		p.role = "mid"
		world.profiles.append(p)
		# Step 2: give it an AI brain (with the asked-for skill) and launch
		# its ship.
		var ai := PilotAI.new(world, p)
		if skill >= 0.0:
			ai.skill = skill
		world.pilot_ai[p] = ai
		var s := world.launch(p)
		# Step 3: put the ship in its place in the column, still, facing
		# the middle, and give the brain a fresh plan.
		s.global_position = at + Vector2(0, (float(i) - float(hulls.size() - 1) * 0.5) * ROW_GAP)
		s.rotation = (CENTER - s.global_position).angle()
		s.velocity = Vector2.ZERO
		ai._reset_after_launch()
		# Both squads hold the same ground, so they must fight for it.
		ai.hold_point = CENTER + Vector2(HOLD_GAP * sx, 0)
		out.append(s)
		i += 1
	return out


## Every tick: keep every AI pilot in the fight. A pilot won't fly home to
## shop in the first 150 s after a launch (PilotShopping checks
## launched_at), so we say "you just launched" every tick. A pilot that
## docks anyway (or dies) is marked dead with a 9,999-second respawn: out
## for good. Returns the pilots that docked this tick (callers may print
## them).
static func keep_in_fight(world: World) -> Array:
	var docked: Array = []
	for p: PilotProfile in world.pilot_ai:
		var ai: PilotAI = world.pilot_ai[p]
		ai.launched_at = world.time
		if p.state == "docked" or p.state == "dead":
			if p.state == "docked":
				docked.append(p)
			p.state = "dead"
			p.respawn_t = OUT_FOR_GOOD
	return docked


## The living ships of `list`, each as text like "fighter 85%" (its hull id
## and how much hull it has left).
static func alive_text(list: Array) -> Array:
	var out: Array = []
	for s in list:
		if is_instance_valid(s) and s.alive:
			out.append("%s %d%%" % [s.hull_id, int(s.hull_frac() * 100.0)])
	return out


## How many ships of `list` are still alive.
static func alive_count(list: Array) -> int:
	var n := 0
	for s in list:
		if is_instance_valid(s) and s.alive:
			n += 1
	return n
