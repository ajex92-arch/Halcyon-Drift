class_name Minion
extends Unit
## WHAT THIS IS: a minion: one of the small computer-flown ships that each
## mothership sends down the three lanes in waves. One minion is not clever
## or strong, but together they push the lanes, keep enemy turrets busy and
## pay money to whoever shoots them down. DESIGN.md A8.
##
## HOW IT WORKS:
##   - Types: a wave (MinionDirector) is 1 escort corvette, 5 fighters and
##     4 bombers per lane. `mtype` says which one this is; Minions.TYPES
##     holds its numbers (hull, speed, guns...).
##   - Walking the lane: with nobody to fight, a minion follows its lane's
##     points toward the enemy base at the wave's shared pace
##     (Minions.FORMATION_SPEED), so the wave stays together. The last
##     stretch goes to wherever the enemy mothership is now (it can move
##     from 20:00). A minion that starts outside its lane's corridor (its
##     mothership is parked up another lane) first follows the big-ship
##     route graph to the lane (World.lane_path_from).
##   - Picking a fight ("aggro", the gaming word for who a computer enemy
##     attacks): four times a second it looks around (MinionTargeting). It
##     likes, from most to least: an enemy ship that just hurt one of our
##     ships nearby, enemy minions, enemy structures, drones and wards, any
##     other enemy ship. Each liking is a head start in distance, so a much
##     nearer enemy can still win (the exact scores are in
##     MinionTargeting). Bombers prefer structures and bigger hulls. A
##     minion never chases more than LEASH away from its lane, and never
##     picks (or keeps) a target that a rock hides.
##   - Fighting: each type flies its own way (MinionFlight): fighters circle
##     the target, bombers make straight attack runs, the corvette keeps its
##     distance. Fighters and bombers have fixed guns, so they turn the nose
##     to the aim point (the lead point, see `aim_pt`) and only fire while
##     the nose is on it.
##   - Damage rules live in Combat: minions do x0.35 damage to turrets and
##     x0.5 to motherships, so a wave alone chips a turret slowly, but it
##     keeps the turret busy while pilots attack it.
##   - Fleet Command: with that module the admiral can give minions an
##     `order` instead of the lane walk (see `order` below).
##   - Saving work: there are many minions, so the costly parts are spread
##     out. The game moves forward in small steps called ticks (60 per
##     second). Choosing a target and checking for rocks happen 4 times a
##     second (at different moments for different minions); steering and
##     shooting happen on every second tick (half the minions on each
##     tick); only "move by our velocity" runs on every tick.
##
## WHO USES IT: MinionDirector launches minions (World.spawn_minion ->
## WorldSpawner, which calls setup()) and changes their `order` and lane
## (set_lane()). World calls sim_update() every tick. Combat damages them
## and calls on_killed(); Economy pays the kill bounty from mdef. UnitVisual
## draws them by mtype; AI pilots and admirals count them by `lane`.

## How far (world units; 1 world unit is about one pixel at normal zoom) a
## minion may chase away from its "anchor" (the nearest point of its lane,
## or its ordered spot). Enemies further than this from the anchor are
## ignored, and a target that gets that far is let go.
const LEASH := 2200.0

# --- what it is ------------------------------------------------------------------------

## The minion type: "fighter", "bomber" or "corvette" (a key of
## Minions.TYPES). UnitVisual picks its drawing by this.
var mtype := "fighter"
## The lane it pushes: "top", "mid" or "bot" (MapLayout.LANE_ORDER).
var lane := "mid"
## This type's data row from Minions.TYPES (Economy reads its "bounty").
var mdef: Dictionary
## Its guns (WeaponMount). The first one sets the fighting range and the
## round speed used for aiming.
var mounts: Array[WeaponMount] = []
## The lane's points, in world positions, from where it joined the lane to
## the enemy end (World.lane_path_from).
var path := PackedVector2Array()
## Which point of `path` it is flying to now (an index into `path`).
var path_i := 0
## The enemy it is fighting, or null for nobody.
var target: Unit = null
## Seconds until its next "think" (target choice and rock check).
var think_t := 0.0

# --- how it flies and fights (filled in from Minions.TYPES) ----------------------------

## Top speed, in world units per second.
var speed := 400.0
## How fast it can change its velocity, in world units per second, per
## second.
var accel := 400.0
## Turning speed, in radians per second (a radian is about 57 degrees).
var turn := 2.0
## How far it looks for enemies to fight, in world units.
var aggro := 1000.0
## How sloppy its aim is, as a fraction of the distance to the target:
## 0.035 means up to 35 world units off at 1,000 away.
var aim_error := 0.03
## +1 or -1: which way it circles a target (a coin toss at birth).
var orbit := 1.0
## Fleet Command orders from the admiral. One of:
##   {"type": "lane"} (the default) or {"type": "lane", "lane": id}:
##     walk the lane;
##   {"type": "move", "pos": Vector2} or {"type": "hold", "pos": Vector2}:
##     go to that spot and fight around it (both work the same way here).
## MinionDirector.set_order() gives each minion its own copy.
var order := {"type": "lane"}
## Strength multiplier on its hull, shield and gun damage (1.0 = normal).
## It grows with match time (+7% per full 5 minutes) and with the team's
## minion research; WorldSpawner.spawn_minion() works it out.
var stat_scale := 1.0

# --- working memory --------------------------------------------------------------------

## This think's aiming error: an arrow that is multiplied by the distance
## to the target and added to the aim point. It changes only at each think,
## so the aim is steadily off rather than shaking.
var _aim_offset := Vector2.ZERO
## The push away from nearby asteroids found at the last think (a velocity
## change per second, in world units per second, per second).
var _rock_push := Vector2.ZERO
## Flips on every tick; on ticks where it becomes true the minion only moves
## (see sim_update()).
var _skip := false
## A reusable list for searching the spatial hash (World.unit_hash, a grid
## that quickly finds the units near a point), so no new list is made on
## every search.
var _scratch: Array = []
## A reusable list for the asteroid search in Steer.avoid_rocks().
var _rocks := PackedInt32Array()
## The first gun's round speed (world units per second), for leading shots.
## setup() reads it once from the gun's data.
var _round_speed := 1000.0
## Where this minion aims at this step (world position): the lead point plus
## its aiming error. MinionFlight turns the nose of a fixed-gun minion
## toward it, and sim_update() lets a fixed gun fire only while the nose is
## on it.
var aim_pt := Vector2.ZERO


## Set the minion up for team `t` as a `type_id` on lane `lane_id`, at
## point `at`. `match_scale` becomes stat_scale. WorldSpawner.spawn_minion()
## calls this right after World gave it its uid. It draws two random
## numbers, in this order: its circling side, then its first think delay.
func setup(w: World, t: int, type_id: String, lane_id: String, at: Vector2, match_scale: float) -> void:
	# Step 1: who and what we are, and this type's numbers. Hull and shield
	# grow with the strength multiplier.
	world = w
	team = t
	mtype = type_id
	lane = lane_id
	kind = Unit.K_MINION
	mdef = Minions.TYPES[type_id]
	size_class = int(mdef["size"])
	radius = float(mdef["radius"])
	stat_scale = match_scale
	hull_max = float(mdef["hull"]) * stat_scale
	hull = hull_max
	# One shared shield pool (no zones), refilling at 10% of the type's base
	# shield per second after 4 s without a hit.
	shields = ShieldZones.new()
	shields.setup(float(mdef["shield"]) * stat_scale, float(mdef["shield"]) * 0.1, 4.0, true)
	speed = float(mdef["speed"])
	accel = float(mdef["accel"])
	turn = float(mdef["turn"])
	aggro = float(mdef["aggro"])
	aim_error = float(mdef["aim_error"])
	vision_radius = float(mdef["vision"])
	display_name = mdef["label"]
	# Step 2: circle left or right (a coin toss), start where we were
	# launched, facing the same way as our mothership. Minions take no part
	# in physics bumps (layer and mask 0): they move by setting `position`.
	orbit = 1.0 if randf() < 0.5 else -1.0
	position = at
	rotation = w.mothership(t).rotation
	collision_layer = 0
	collision_mask = 0
	# Step 3: the guns, all on the nose, each free to swing 150 degrees
	# either side. A gun whose data has a "prefer" entry picks its own
	# targets (an AUTO mount, like point defense); the first gun of a
	# medium-or-bigger minion (the corvette) swings toward the aim point (a
	# TURRET mount); anything else fires straight ahead (FIXED).
	var first := true
	for wid: String in mdef["weapons"]:
		var wd: Dictionary = Weapons.get_def(wid)
		var mtype_name := "fixed"
		if wd.has("prefer"):
			mtype_name = "auto"
		elif size_class >= Rules.SIZE_MEDIUM and first:
			mtype_name = "turret"
		mounts.append(WeaponMount.new(self, wid, mtype_name, Vector2(radius, 0), 150.0))
		first = false
	# The first gun's round speed, used to aim (looked up once here instead
	# of on every fight step).
	_round_speed = float(mounts[0].def.get("speed", 1000.0))
	# Step 4: our lane's path, a random first think delay (0 to 0.25 s, so
	# minions launched together don't all think on the same tick), and
	# which half of the ticks we act on (by our uid being even or odd).
	set_lane(lane_id)
	think_t = randf() * 0.25
	_skip = uid % 2 == 0


## Switch to lane `lane_id` and get that lane's path from where we are now.
## setup() calls it, and so does MinionDirector.set_order() for a "lane"
## order.
func set_lane(lane_id: String) -> void:
	lane = lane_id
	path = world.lane_path_from(lane_id, team, position)
	path_i = 0


## One tick of `tick_dt` seconds. World calls it every tick. Moving happens
## every tick; thinking, steering and shooting only on every second tick
## (see "Saving work" at the top).
func sim_update(tick_dt: float) -> void:
	if not alive:
		return
	# Step 1: move by our velocity (cheap, every tick), then act only on
	# every second tick. On those ticks `dt` covers both ticks.
	position += velocity * tick_dt
	_skip = not _skip
	if _skip:
		return
	var dt := tick_dt * 2.0
	# Step 2: timers: the hit flash, the shield refill, and the next think
	# (every 0.25 s). With profiling on, the think is also timed (in
	# microseconds, added up in world.prof["m_think"]).
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	shields.tick(dt, 1.0)
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.25
		if world.profiling:
			var tt := Time.get_ticks_usec()
			_think()
			world.prof["m_think"] = int(world.prof.get("m_think", 0)) + (Time.get_ticks_usec() - tt)
		else:
			_think()
	# Step 3: by default aim 500 straight ahead and hold fire.
	var aim := position + Vector2.from_angle(rotation) * 500.0
	var firing := false
	if target != null and is_instance_valid(target) and target.alive:
		# Step 4: a target to fight. Aim where it will be when our round
		# gets there (a "lead" shot, using the first gun's round speed and
		# 35% of our own velocity), plus our steady aiming error, which
		# grows with the distance.
		var tp := MinionTargeting.target_point(self)
		var d := position.distance_to(tp)
		var m0 := mounts[0]
		var reach := m0.reach
		var lead := Util.lead_point(position, velocity * 0.35, tp, target.velocity, _round_speed)
		aim = lead + _aim_offset * d
		aim_pt = aim
		# Fly our type's fighting pattern, and fire once it is in reach.
		# (Against a mothership the distance is to its keel line, and its
		# radius is not added.)
		MinionFlight.combat_move(self, tp, d, reach, dt)
		firing = d < reach + (0.0 if target is Mothership else target.radius)
		# A fixed gun fires along the nose, so it fires only while the nose is
		# on the aim point: within the angle that the target (its radius plus
		# 15) covers at that distance, but between 0.08 and 0.3 rad. (Playtest:
		# a quarter of the bomber torpedoes were fired 90 degrees or more off
		# the target.)
		if m0.mount_type == WeaponMount.FIXED and firing:
			var trad := 170.0 if target is Mothership else target.radius
			var ad := aim.distance_to(position)
			var tol := clampf(atan2(trad + 15.0, maxf(1.0, ad)), 0.08, 0.3)
			firing = absf(Util.ang_diff(rotation, (aim - position).angle())) < tol
	else:
		# Step 5: no target: forget it and walk the lane (or follow orders).
		target = null
		MinionFlight.lane_move(self, dt)
	# Step 6: every gun takes its turn. Damage is scaled by stat_scale, and
	# minion shots are free (no battery, so null).
	for m in mounts:
		m.update(dt, aim, firing, 1.0, stat_scale, 1.0, null)


## Four times a second: choose a target, roll a fresh aiming error and look
## for asteroids ahead.
func _think() -> void:
	MinionTargeting.pick_target(self)
	# A fresh, steady aiming error each think: low skill, but not random
	# noise. Its direction and its size (up to aim_error) are two random
	# numbers, drawn in that order.
	_aim_offset = Vector2.from_angle(randf() * TAU) * aim_error * randf()
	# The push away from asteroids, looking half a second ahead.
	_rock_push = Steer.avoid_rocks(world.asteroids, position, radius, velocity * 0.5, _rocks)


## Combat.kill() calls this when we die: a small explosion in our team's
## colour, 1.5x our size. (Economy pays the bounty separately.)
func on_killed(_info: DamageInfo) -> void:
	world.effects.explosion(position, radius * 1.5, Palette.team(team))
