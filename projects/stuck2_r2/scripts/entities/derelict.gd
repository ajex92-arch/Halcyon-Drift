class_name Derelict
extends Unit
## WHAT THIS IS: a jungle "monster" camp: an abandoned (derelict) hull whose
## automatic guns still fire. The Carrier type also launches snub fighters.
## Camps belong to no team (they are "neutral"). DESIGN.md A10.
##
## HOW IT WORKS:
##   - It never moves: it sits at `home`, where it was made.
##   - Choosing a target (every 0.3 s): it only looks within its leash
##     (Jungle.CAMPS "leash", 2,500) of home. It fights anyone who hurt it
##     in the last 8 s, or anyone who comes within its aggro range (700;
##     "aggro" is the gaming word for who a computer enemy attacks).
##     Attackers get 1500 off their distance, so it prefers them; otherwise
##     the nearest wins. It ignores repair drones and wards.
##   - Reset: 6 s after it last had a target it "resets": it repairs 20% of
##     its hull per second (Jungle.RESET_REGEN) and, once fully repaired,
##     forgets who hurt it.
##   - Carrier: while fighting it keeps up to 2 snub fighters out: the first
##     at once, then one more every 12 s while it is short.
##   - Reward: killing it pays the pilots who damaged it in the last 30 s
##     (Economy.on_unit_killed), and JungleDirector brings the camp back
##     later.
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: JungleDirector makes the camps (World.spawn_derelict ->
## WorldSpawner, which calls setup()) and respawns them. World calls
## sim_update() every tick. SnubFighter reads `target` and is_engaged();
## Economy pays the reward from cdef "reward"; AI pilots hunt camps.

## Which camp this is (its id in the map's camp list); JungleDirector uses
## it to respawn the camp.
var camp_id := ""
## The camp type: "gunship" or "carrier" (a key of Jungle.CAMPS).
var ctype := "gunship"
## This type's data row from Jungle.CAMPS (hull, guns, aggro, leash,
## reward, snubs...).
var cdef: Dictionary
## Where it sits (world position); the leash is measured from here.
var home := Vector2.ZERO
## Its automatic guns (WeaponMount).
var mounts: Array[WeaponMount] = []
## Who it is fighting, or null.
var target: Unit = null
## Seconds until its next target choice.
var think_t := 0.0
## Seconds left before it resets: set to 6 while it has a target, counts
## down without one.
var engaged_t := 0.0
## Its live snub fighters (SnubFighter).
var snubs: Array = []
## Seconds until it may launch the next snub fighter.
var snub_t := 0.0
## A reusable list for searching the spatial hash (World.unit_hash, a grid
## that quickly finds the units near a point).
var _scratch: Array = []


## Set up the derelict of camp `camp`, of type `type_id`, at `at`.
## WorldSpawner.spawn_derelict() calls this. It draws one random number
## (its facing).
func setup(w: World, camp: String, type_id: String, at: Vector2) -> void:
	# Step 1: who and what we are: neutral, medium sized.
	world = w
	camp_id = camp
	ctype = type_id
	cdef = Jungle.CAMPS[type_id]
	team = Rules.NEUTRAL
	kind = Unit.K_MONSTER
	size_class = Rules.SIZE_MEDIUM
	radius = float(cdef["radius"])
	hull_max = float(cdef["hull"])
	hull = hull_max
	display_name = cdef["label"]
	# Step 2: where we sit, facing a random way.
	position = at
	home = at
	rotation = randf() * TAU
	# Step 3: physics. collision_layer is a "bitmask" (a number whose binary
	# digits are on/off switches); 4 switches on layer 3, the "structures"
	# layer that pilot ships bump into. The mask is 0: it never checks for
	# bumps itself. Its collision shape is a circle of our radius.
	collision_layer = 4
	collision_mask = 0
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
	# Step 4: the guns, spread evenly round the hull at 60% of our radius,
	# each free to swing 180 degrees either side.
	var n: int = int(cdef["turrets"])
	for i in n:
		var off := Vector2.from_angle(TAU * float(i) / float(n)) * radius * 0.6
		mounts.append(WeaponMount.new(self, cdef["weapon"], "turret", off, 180.0))


## True while it has someone to fight.
func is_engaged() -> bool:
	return target != null and is_instance_valid(target) and target.alive


## One tick of `dt` seconds: choose a target, then fight or reset. World
## calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: choose a target every 0.3 s.
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.3
		_pick_target()
	# Step 2: by default aim at ourselves (nowhere) and hold fire.
	var aim := global_position
	var firing := false
	if is_engaged():
		# Step 3: fighting: hold off the reset, aim where the target will be
		# when our round gets there (a "lead" shot), fire once it is in the
		# first gun's reach (to its edge), and launch snub fighters.
		engaged_t = 6.0
		var m := mounts[0]
		aim = Util.lead_point(global_position, Vector2.ZERO, target.global_position, target.velocity, float(m.def.get("speed", 1000.0)))
		firing = global_position.distance_to(target.global_position) < m.reach + target.hit_radius()
		_launch_snubs(dt)
	else:
		# Step 4: nobody to fight: count down, then reset.
		engaged_t = maxf(0.0, engaged_t - dt)
		if engaged_t <= 0.0:
			# Reset: regenerate and forget who hurt us.
			heal(hull_max * Jungle.RESET_REGEN * dt)
			if hull >= hull_max:
				damage_log.clear()
	# Step 5: every gun takes its turn (free shots, no battery).
	for m in mounts:
		m.update(dt, aim, firing, 1.0, 1.0, 1.0, null)


## Choose who to fight: sets `target` (null for nobody). See "Choosing a
## target" at the top.
func _pick_target() -> void:
	var leash: float = float(cdef["leash"])
	var aggro: float = float(cdef["aggro"])
	var now := world.time
	var best: Unit = null
	var best_score := INF
	# Step 1: look at every unit within the leash of home.
	for u: Unit in world.unit_hash.query(home, leash, _scratch):
		# Skip the dead, the unshootable and other neutrals.
		if not u.alive or u.team == Rules.NEUTRAL:
			continue
		# Repair drones and wards aren't worth a monster's time.
		if u.kind == Unit.K_REPAIR_DRONE or u.kind == Unit.K_WARD:
			continue
		var d := home.distance_to(u.global_position)
		if d > leash:
			continue
		# Step 2: did it hurt us in the last 8 s (our damage_log)? If not,
		# it must be within our aggro range to count.
		var hurt_us := damage_log.has(u.uid) and now - float(damage_log[u.uid][1]) < 8.0
		if not hurt_us and global_position.distance_to(u.global_position) > aggro:
			continue
		# Step 3: nearest wins, and attackers get 1500 off.
		var score := global_position.distance_to(u.global_position) - (1500.0 if hurt_us else 0.0)
		if score < best_score:
			best_score = score
			best = u
	target = best


## While fighting: keep up to cdef "snubs" snub fighters out (2 for the
## Carrier, 0 for the Gunship). Dead ones are dropped from the list; a new
## one launches when we are short and the snub_every timer (12 s) has run
## out.
func _launch_snubs(dt: float) -> void:
	var want: int = int(cdef.get("snubs", 0))
	if want <= 0:
		return
	# Drop the dead ones (walking backwards, so removing one doesn't skip
	# the next).
	for i in range(snubs.size() - 1, -1, -1):
		if not is_instance_valid(snubs[i]) or not snubs[i].alive:
			snubs.remove_at(i)
	snub_t -= dt
	if snubs.size() < want and snub_t <= 0.0:
		snub_t = float(cdef.get("snub_every", 12.0))
		snubs.append(world.spawn_snub(self))


## Combat.kill() calls this when we die: an explosion, and JungleDirector
## starts the camp's respawn timer.
func on_killed(_info: DamageInfo) -> void:
	world.effects.explosion(global_position, radius * 2.0, Palette.DERELICT)
	world.jungle_director.on_camp_killed(camp_id)
