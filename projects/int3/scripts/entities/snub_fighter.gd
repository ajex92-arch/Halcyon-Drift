class_name SnubFighter
extends Unit
## WHAT THIS IS: a small automatic fighter that a Derelict Carrier (a
## jungle monster camp) launches. Neutral, like its carrier.
##
## HOW IT WORKS: it chases whoever its carrier is fighting: it flies
## straight at the target, then circles it once within 450 world units
## (1 world unit is about one pixel at normal zoom), and fires its one
## forward gun when its nose points at the target. When the carrier stops
## fighting it flies home and, once back at the carrier, disappears (it
## "lands"). If the carrier dies, it disappears at once.
##
## WHO USES IT: Derelict launches it (World.spawn_snub -> WorldSpawner,
## which calls setup()). World calls sim_update() every tick.

## The carrier it belongs to.
var carrier: Derelict = null
## Its one gun (WeaponMount), fixed to fire straight ahead.
var mount: WeaponMount
## Top speed, in world units per second.
var speed := 520.0
## How fast it can change its velocity, in world units per second, per
## second.
var accel := 520.0
## Turning speed, in radians per second (a radian is about 57 degrees).
var turn := 3.2
## +1 or -1: which way it circles a target (a coin toss at launch).
var orbit := 1.0
## A reusable list for the asteroid search in Steer.avoid_rocks().
var _rocks := PackedInt32Array()


## Set up a snub fighter launched by carrier `from`.
## WorldSpawner.spawn_snub() calls this. It draws two random numbers, in
## this order: where round the carrier it appears, then its circling side.
func setup(w: World, from: Derelict) -> void:
	# Step 1: who and what we are (numbers from Jungle.SNUB).
	world = w
	carrier = from
	team = Rules.NEUTRAL
	kind = Unit.K_SNUB
	size_class = Rules.SIZE_SMALL
	var d: Dictionary = Jungle.SNUB
	radius = float(d["radius"])
	hull_max = float(d["hull"])
	hull = hull_max
	speed = float(d["speed"])
	accel = float(d["accel"])
	turn = float(d["turn"])
	display_name = d["label"]
	# Step 2: appear just outside the carrier, at a random angle, and toss
	# a coin for the circling side. No physics bumps (layer and mask 0).
	position = from.global_position + Vector2.from_angle(randf() * TAU) * (from.radius + 30.0)
	orbit = 1.0 if randf() < 0.5 else -1.0
	collision_layer = 0
	collision_mask = 0
	# Step 3: one FIXED gun on the nose (it can't swing: arc 0).
	mount = WeaponMount.new(self, d["weapon"], "fixed", Vector2(radius, 0), 0.0)


## One tick of `dt` seconds: chase the carrier's target, or fly home. World
## calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: no carrier any more: vanish quietly (no bounty, no news).
	if carrier == null or not is_instance_valid(carrier) or not carrier.alive:
		world.combat.kill_silently(self)
		return
	var tgt: Unit = carrier.target if carrier.is_engaged() else null
	var want := Vector2.ZERO
	var firing := false
	if tgt != null:
		# Step 2: fighting: fly straight at the target until within 450,
		# then circle it sideways at 70% speed. Turn the nose toward it, and
		# fire when it is in reach and the nose is within 0.25 radians
		# (about 14 degrees) of it.
		var to := tgt.global_position - global_position
		var d := to.length()
		if d > 450.0:
			want = to.normalized() * speed
		else:
			want = to.normalized().orthogonal() * orbit * speed * 0.7
		rotation = Util.wrap_angle(rotation + clampf(Util.ang_diff(rotation, to.angle()), -turn * dt, turn * dt))
		firing = d < mount.reach and absf(Util.ang_diff(rotation, to.angle())) < 0.25
	else:
		# Step 3: the fight is over: fly home at full speed (nose snapped to
		# the way home), and vanish once back at the carrier.
		var home := carrier.global_position
		if global_position.distance_to(home) < carrier.radius + 60.0:
			world.combat.kill_silently(self)
			return
		want = (home - global_position).normalized() * speed
		rotation = want.angle()
	# Step 4: change velocity toward the wanted one (no faster than accel
	# allows), slide around asteroids, move, and let the gun take its turn
	# (it fires straight ahead; free shots, no battery).
	velocity = velocity.move_toward(want, accel * dt)
	velocity += Steer.avoid_rocks(world.asteroids, global_position, radius, velocity * 0.3, _rocks) * dt
	position += velocity * dt
	mount.update(dt, global_position + Vector2.from_angle(rotation) * 300.0, firing, 1.0, 1.0, 1.0, null)


## Combat.kill() calls this when we are shot down: a small puff of sparks.
func on_killed(_info: DamageInfo) -> void:
	world.effects.puff(global_position, Palette.DERELICT, 8)
