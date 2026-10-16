extends Node
## WHAT THIS IS: the support systems check (DESIGN.md A11). It tests, one
## after another, that:
##   repair bays fly out and anchor (stop for good at their spot),
##   their drones heal (1 per strike craft, up to 3 on a frigate),
##   a hit on the bay's hull locks repairs out for a while,
##   with Bay Defenses research the bay's shield lets repairs continue,
##   repair kits launch a drone that heals and then expires,
##   wards (small watch drones) can only be placed where we can see, then
##   anchor and see around them,
##   and a killed bay drone is rebuilt.
## Prints PASS / FAIL lines.
##
## HOW IT WORKS: setup() gives Halcyon (team 0) 20,000 credits, the repair
## bay research and 4 bay drones, and orders a bay to the test spot P.
## Then _physics_process() runs numbered steps (`step`), one after
## another. Each step waits for something to happen (the bay anchors, 25
## seconds of healing ...), checks it with _check(), and sets up the next
## step. Test ships are launched with no brain, so they just sit still.
## Step 99 prints the number of failures and quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=support_probe
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second. --no-pilots,
## --no-jungle and --no-admiral-ai switch off the AI pilots, the jungle
## monsters and the computer admirals, so nothing interferes.
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>" (the detail is what was measured, for example
## "+52 hull in 25s"). The last line is "support_probe: N failures"; 0
## means everything works.
##
## WHO USES IT: main.gd loads it for --test=support_probe (for
## --test=<name> it loads tests/<name>.gd, adds it after the World and
## calls setup()). docs/CODE_STYLE.md (Part 3) lists it as a check for
## player-facing code. It orders bays and wards through AdmiralCommand
## (World.command) and deals damage through Combat.apply_damage().

## The running match (set by setup()).
var world: World
## Seconds since this test started.
var t := 0.0
## Which step of the test we are on (0-7, then 99 = finish).
var step := 0
## The repair bay we deployed.
var bay: RepairBay
## A test fighter (a strike craft).
var fighter: Ship
## A test frigate (a flak frigate).
var frigate: Ship
## Where we place the ward (world position).
var ward_point := Vector2.ZERO
## A remembered number to compare against later (a hull value, or the
## number of bay drones).
var mark := 0.0
## The test time (seconds) when the current wait began.
var mark_t := 0.0
## How many checks failed so far.
var fails := 0
## The test spot for the bay (world units; 1 world unit is about one pixel
## at normal zoom).
const P := Vector2(9000, 13000)


## main.gd calls this once, right after the World is built. Stop the minion
## waves, give Halcyon money and the repair bay research, and order a bay
## to P.
func setup(w: World) -> void:
	world = w
	# No minion waves: the next wave is "never" (INF = infinity).
	world.minion_director.next_wave = INF
	# Halcyon: rich, with repair bays researched and 4 drones per bay.
	var ts := world.teams[0]
	ts.treasury = 20000.0
	ts.repair_bays = true
	ts.bay_drones = 4
	# Order a bay to P ("" = the order worked, else the reason it failed).
	var err := world.command.deploy_bay(0, P)
	_check("deploy bay", err == "", err)
	bay = world.bays[world.bays.size() - 1]


## Print one PASS or FAIL line for the check `name` (`ok` = it passed),
## with the measured `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Launch a Halcyon test ship of hull `hid` at `at`, standing still and
## with no brain (controller = null), so it doesn't move. The pilot is
## named "Test-<hull>". Returns the ship.
func _spawn(hid: String, at: Vector2) -> Ship:
	var p := PilotProfile.new("Test-" + hid, 0, 40 + world.profiles.size(), false)
	p.hull_id = hid
	world.profiles.append(p)
	var s := world.launch(p)
	s.global_position = at
	s.velocity = Vector2.ZERO
	s.controller = null
	return s


## How many live bay drones (not kit drones) are working on unit `u`.
func _drones_on(u: Unit) -> int:
	var n := 0
	for d: RepairDrone in world.repair_drones:
		if d.alive and d.target == u and d.mode == RepairDrone.MODE_BAY:
			n += 1
	return n


## Deal `amount` damage to unit `u`, as if Cinder (team 1) shot it from 200
## world units to its right (east). The damage kind is Rules.W_PURE.
func _hit(u: Unit, amount: float) -> void:
	var info := DamageInfo.new()
	info.amount = amount
	info.kind = Rules.W_PURE
	info.source_team = 1
	info.from_pos = u.global_position + Vector2(200, 0)
	world.combat.apply_damage(u, info)


## Godot calls this every tick; `dt` is the tick's length in seconds. Run
## the current step (see the comment above each one).
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	match step:
		# Wait for the bay to anchor (give up after 120 s). Then launch a
		# fighter and a flak frigate near P, both at 30% hull.
		0:
			if bay.is_anchored():
				_check("bay anchored", true, "after %.0fs at %s" % [t, world.place_name(bay.global_position)])
				fighter = _spawn("fighter", P + Vector2(300, 200))
				fighter.hull = fighter.hull_max * 0.3
				frigate = _spawn("flak", P + Vector2(-400, -300))
				frigate.hull = frigate.hull_max * 0.3
				mark = fighter.hull
				mark_t = t
				step = 1
			elif t > 120.0:
				_check("bay anchored", false, "still flying after 120s")
				step = 99
		# After 25 s: the fighter healed over 40 hull, with at most 1 drone
		# on it; the frigate has 2 or 3 drones.
		1:
			if t - mark_t > 25.0:
				var healed := fighter.hull - mark
				_check("fighter healed by bay", healed > 40.0, "+%.0f hull in 25s" % healed)
				_check("strike craft gets 1 drone", _drones_on(fighter) <= 1, "%d drones" % _drones_on(fighter))
				_check("frigate gets up to 3 drones", _drones_on(frigate) <= 3 and _drones_on(frigate) >= 2, "%d drones" % _drones_on(frigate))
				# Lockout: hit the bay's hull, damage the fighter again.
				fighter.hull = fighter.hull_max * 0.3
				_hit(bay, 50.0)
				_check("bay locked out after hull hit", not bay.can_repair())
				mark = fighter.hull
				mark_t = t
				step = 2
		# After 3 s: the fighter gained less than 1 hull (no repairs).
		2:
			if t - mark_t > 3.0:
				_check("no healing during lockout", fighter.hull - mark < 1.0, "+%.1f" % (fighter.hull - mark))
				step = 3
				mark_t = t
		# After 4 more s: the lockout is over.
		3:
			if t - mark_t > 4.0:
				_check("lockout ends", bay.can_repair())
				# Bay Defenses: shield soaks the hit, repairs continue.
				world.teams[0].bay_defenses = true
				step = 4
				mark_t = t
		# After 0.5 s: the bay has a shield and one gun. A hit now only
		# drains the shield, so repairs go on.
		4:
			if t - mark_t > 0.5:
				_check("bay got defenses", bay.has_defenses and bay.shields != null and bay.mounts.size() == 1)
				_hit(bay, 50.0)
				_check("shield-only hit keeps repairing", bay.can_repair(), "hull %.0f/%.0f shield %.0f" % [bay.hull, bay.hull_max, bay.shields.total()])
				# Repair kit: buy one, move the fighter 5,000 units east of
				# P (away from the bay), damage it to 30% and use the kit.
				var p := fighter.profile
				p.credits = 1000.0
				p.buy_kit()
				fighter.global_position = P + Vector2(5000, 0)
				fighter.hull = fighter.hull_max * 0.3
				mark = fighter.hull
				fighter.use_repair_kit()
				_check("kit drone launched", fighter.kit_drones.size() == 1 and p.kit_count() == 0)
				mark_t = t
				step = 5
		# After 11 s: the kit healed between 35 and 65 hull, and no kit
		# drone is alive any more. Then try two wards: one at a spot we can
		# see near the bay (must work), one far away in the dark (must be
		# refused).
		5:
			if t - mark_t > 11.0:
				var healed := fighter.hull - mark
				_check("kit healed ~50", healed > 35.0 and healed < 65.0, "+%.0f" % healed)
				_check("kit drone expired", world.repair_drones.filter(func(d): return d.mode == RepairDrone.MODE_KIT and d.alive).is_empty())
				# Ward at a lit spot near the bay.
				ward_point = P + Vector2(800, 600)
				var err := world.command.place_ward(0, ward_point)
				_check("place ward where we see", err == "", err)
				var bad := world.command.place_ward(0, Vector2(30000, 13000))
				_check("refuse ward in the dark", bad != "", bad)
				mark_t = t
				step = 6
		# Wait for our ward to anchor (give up after 30 s). Then refresh
		# Halcyon's fog of war at once and check the ward sees 900 units
		# past its spot. Then kill one bay drone.
		6:
			var w: Ward = null
			for x: Ward in world.wards:
				if x.team == 0 and x.alive:
					w = x
			if w != null and w.is_anchored():
				_check("ward anchored", true, "after %.0fs" % (t - mark_t))
				world.vision.update_team(0, world._viewers(0))
				_check("ward sees around it", world.vision.is_visible(0, ward_point + Vector2(900, 0)))
				# Kill one bay drone; it should be rebuilt in ~15 s.
				var before := bay.drones.size()
				for d in bay.drones:
					if is_instance_valid(d) and d.alive:
						_hit(d, 999.0)
						break
				mark = float(before)
				mark_t = t
				step = 7
			elif t - mark_t > 30.0:
				_check("ward anchored", false, "not anchored after 30s")
				step = 99
		# After 17 s: the bay has at least as many live drones as before.
		7:
			if t - mark_t > 17.0:
				var alive_drones := 0
				for d in bay.drones:
					if is_instance_valid(d) and d.alive:
						alive_drones += 1
				_check("killed drone rebuilt", alive_drones >= int(mark), "%d of %d" % [alive_drones, int(mark)])
				step = 99
		# The end: print the total and quit.
		99:
			print("support_probe: %d failures" % fails)
			get_tree().quit()
