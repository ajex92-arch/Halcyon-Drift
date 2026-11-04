class_name Turret
extends Unit
## WHAT THIS IS: a gun tower that the admiral builds on a turret spot (a
## "slot") of an ore node, to guard a lane. DESIGN.md A9.
##
## HOW IT WORKS:
##   - Two types (TurretData.TURRETS): "pd" (point defense: any node; rapid
##     fire that shreds strike craft and shoots down torpedoes) and "torp"
##     (only at inner nodes, the ones near our mothership: homing torpedoes
##     that punish big hulls while the damage modifiers are kept).
##   - Building: a new turret is "under construction" for `build_left`
##     seconds (25 s for PD, 35 s for torpedo). It starts at 30% hull and
##     its hull grows to full while it builds. It can't shoot until it is
##     finished.
##   - No shield and no repair: a turret has only its hull (TurretData
##     "shield" is 0 for both types, so `shields` stays null), and nothing
##     raises that hull once it is built: Unit.heal() refuses turrets, so a
##     Logistics Corvette's repair drones and its Emergency Repair pass it by.
##     What does raise it is only the build itself, Platform Armor research
##     (which keeps the share of hull left, WorldResearch) and, in the rule
##     set that has node_persist, the slow repair of a turret rebuilt on a node
##     (NodePersistFeature).
##   - Choosing a target, 5 times a second: every enemy in range gets a
##     score, its distance plus a penalty by kind, and the LOWEST wins:
##        enemy ship that just hurt one of our ships near us   distance - 15000
##        enemy minion                                         distance
##        enemy ship                                           distance + 5000
##        anything else (drones, wards, structures)            distance + 8000
##     "Just hurt" means within the last 3 s (TurretData.AGGRO_WINDOW), with
##     the victim inside our range. Gamers call this "aggro": the turret's
##     anger goes to whoever attacks our pilots (the same rule as in League
##     of Legends). The current target gets 300 off, so the turret doesn't
##     flip between two equally close targets. It never shoots through
##     asteroids, and it only shoots a ward that our team can see.
##   - Damage ramp: every shot it fires at the same ship adds 20%
##     (TurretData.TURRET_RAMP) to the damage of the next ones, up to +100%
##     (TURRET_RAMP_MAX). The count starts again when it switches to
##     another ship or to a target that isn't a ship.
##   - Combat's special rules for turrets, while the damage modifiers are
##     kept: pilot damage is x0.3 unless a minion of the attacker's team is
##     within 1,800 ("backdoor protection": push a minion wave in to take a
##     turret), and minion damage is x0.35. With the damage modifiers
##     removed a turret takes the raw damage of every hit. The AI pilots
##     still like to push a turret together with a minion wave
##     (TurretData.BACKDOOR_RADIUS).
##   - When it is destroyed its slot frees up, but nobody can build on that
##     node for 60 s (TurretData.REBUILD_LOCK, tuned "rebuild_lock").
## Distances are in world units (1 world unit is about one pixel at normal
## zoom).
##
## WHO USES IT: AdmiralCommand builds turrets (World.spawn_turret ->
## WorldSpawner, which calls setup()); tests build finished ones. World
## calls sim_update() every tick. ResourceNode keeps the turret in its
## `slots`. WorldResearch raises hull_max after armour research. AI pilots
## read range_r, ttype and is_built(); UnitVisual draws it (ttype,
## is_built(), build_left, target); WeaponMount asks homing_target() for
## torpedoes; Economy pays the turret bounty when it dies.

## The turret type: "pd" or "torp" (a key of TurretData.TURRETS).
var ttype := "pd"
## This type's data row from TurretData.TURRETS (hull, range, guns...).
var tdef: Dictionary
## The ore node it stands on.
var node: ResourceNode = null
## Which turret spot of that node it uses (an index into node.slots and
## node.slot_pos).
var slot := 0
## Its guns (WeaponMount): TURRET mounts at its centre that can swing all
## the way round.
var mounts: Array[WeaponMount] = []
## Seconds of building left (0 = finished).
var build_left := 0.0
## Seconds the whole build takes (tdef "build").
var build_total := 1.0
## The enemy it is shooting, or null.
var target: Unit = null
## Seconds until its next target choice.
var think_t := 0.0
## The uid (id number) of the ship the damage ramp is counting for, or -1
## for none.
var ramp_target_uid := -1
## How many shots it has fired at that ship so far (the damage ramp).
var ramp := 0
## Its range in world units before research (1,500 for PD, 2,300 for
## torpedo). reach() adds the research bonus.
var range_r := 1500.0
## A reusable list for searching the spatial hash (World.unit_hash, a grid
## that quickly finds the units near a point).
var _scratch: Array = []


## Build a `type_id` turret for team `t` on slot `slot_index` of ore node
## `n`. Normally it starts at 30% hull and builds up over time; `instant` =
## finished at once with full hull (tests use this).
## WorldSpawner.spawn_turret() calls it.
func setup(w: World, t: int, n: ResourceNode, slot_index: int, type_id: String, instant: bool = false) -> void:
	# Step 1: who and what we are. Turret armour research makes the hull
	# bigger.
	world = w
	team = t
	node = n
	slot = slot_index
	ttype = type_id
	tdef = TurretData.TURRETS[type_id]
	kind = Unit.K_TURRET
	size_class = Rules.SIZE_STRUCTURE
	radius = float(tdef["radius"])
	var ts: TeamState = w.teams[t]
	hull_max = float(tdef["hull"]) * (1.0 + ts.turret_armor)
	# No shield: both turret types have 0 (TurretData), so `shields` stays null
	# and every hit goes straight to the hull. A type with a shield number would
	# get one shared pool (no zones), refilling at 2% of its size per second
	# after 8 s without a hit.
	if float(tdef["shield"]) > 0.0:
		shields = ShieldZones.new()
		shields.setup(float(tdef["shield"]), float(tdef["shield"]) * 0.02, 8.0, true)
	range_r = float(tdef["range"])
	vision_radius = float(tdef["vision"])
	display_name = tdef["label"]
	# Step 2: stand on the slot, facing away from the node's centre.
	position = n.slot_pos[slot_index]
	rotation = (position - n.global_position).angle()
	# Physics: collision_layer is a "bitmask" (a number whose binary digits
	# are on/off switches); 4 switches on layer 3, the "structures" layer
	# that pilot ships bump into. The mask is 0: the turret itself never
	# checks for bumps. Its collision shape is a circle of our radius.
	collision_layer = 4
	collision_mask = 0
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs != null:
		var circ := CircleShape2D.new()
		circ.radius = radius
		cs.shape = circ
	# Step 3: the guns, at our centre, free to swing 180 degrees either side.
	for wid: String in tdef["weapons"]:
		mounts.append(WeaponMount.new(self, wid, "turret", Vector2.ZERO, 180.0))
	# Step 4: start building (or be finished at once), and take our slot on
	# the node.
	build_total = float(tdef["build"])
	build_left = 0.0 if instant else build_total
	hull = hull_max if instant else hull_max * 0.3
	n.slots[slot_index] = self


## True once building is finished.
func is_built() -> bool:
	return build_left <= 0.0


## One tick of `dt` seconds: build, or choose a target and shoot. World
## calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: still building: the hull grows by 70% of hull_max spread over
	# the build time (on top of the 30% we started with). Nothing else
	# happens while building.
	if build_left > 0.0:
		build_left -= dt
		hull = minf(hull_max, hull + hull_max * 0.7 * dt / build_total)
		return
	# Step 2: refill the shield (if the type has one); choose a target every
	# 0.2 s.
	if shields != null:
		shields.tick(dt, 1.0)
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.2
		_pick_target()
	# Step 3: by default aim 100 straight ahead, hold fire, normal damage.
	var aim := global_position + Vector2.from_angle(rotation) * 100.0
	var firing := false
	var dmg := 1.0
	if target != null and is_instance_valid(target) and target.alive:
		# Step 4: aim where the target will be when our round gets there (a
		# "lead" shot, using the first gun's round speed; the turret itself
		# doesn't move), and fire once it is in reach (to its edge).
		var m := mounts[0]
		aim = Util.lead_point(global_position, Vector2.ZERO, target.global_position, target.velocity, float(m.def.get("speed", 1000.0)))
		firing = global_position.distance_to(target.global_position) < reach() + target.hit_radius()
		# Step 5: the damage ramp. A new ship starts the count again; a
		# target that isn't a ship gets no ramp.
		if target.kind == Unit.K_SHIP:
			if target.uid != ramp_target_uid:
				ramp_target_uid = target.uid
				ramp = 0
			dmg = 1.0 + minf(TurretData.TURRET_RAMP_MAX, TurretData.TURRET_RAMP * float(ramp))
		else:
			ramp_target_uid = -1
			ramp = 0
	else:
		target = null
	# Step 6: every gun takes its turn: damage x the ramp, and range x
	# (1 + the team's range research). Shots are free (no battery).
	# A gun's cooldown (`cd`) jumping up means it just fired: count that
	# shot for the ramp if we are shooting a ship.
	var ts: TeamState = world.teams[team]
	for m in mounts:
		var before := m.cd
		m.update(dt, aim, firing, 1.0, dmg, 1.0 + ts.team_range, null)
		if firing and m.cd > before and target != null and target.kind == Unit.K_SHIP:
			ramp += 1


## The unit a torpedo fired by this turret should chase: our current
## target. WeaponMount asks this when a gun fires.
func homing_target() -> Unit:
	return target


## Engagement range including Fire Control research: range_r x (1 + the
## team's range bonus), in world units.
func reach() -> float:
	return range_r * (1.0 + world.teams[team].team_range)


## Choose what to shoot: sets `target` (null for nothing). See "Choosing a
## target" at the top for the scores.
func _pick_target() -> void:
	var now := world.time
	var best: Unit = null
	var best_score := INF
	var r := reach()
	# Step 1: look at every unit near us (a little past our reach).
	for u: Unit in world.unit_hash.query(global_position, r + Projectiles.MAX_UNIT_RADIUS, _scratch):
		# Skip the dead, the unshootable, friends and neutrals.
		if not u.alive or u.team == team or u.team == Rules.NEUTRAL:
			continue
		# It must be in reach (measured to its edge, the size shots see).
		var d := global_position.distance_to(u.global_position)
		if d > r + u.hit_radius():
			continue
		# Wards are stealthy: only shoot one our team can see.
		if u.kind == Unit.K_WARD and not u.visible_to(team):
			continue
		# No shooting through asteroids.
		if world.asteroids.segment_blocked(global_position, u.global_position):
			continue
		# Step 2: the score (lower is better).
		var score := d
		if u.kind == Unit.K_SHIP:
			score += 5000.0
			# The LoL rule: hurting one of our ships near us draws fire.
			if now - u.aggro_time < TurretData.AGGRO_WINDOW and u.aggro_victim_pos.distance_to(global_position) < range_r:
				score -= 20000.0
		elif u.kind == Unit.K_MINION:
			score += 0.0
		else:
			score += 8000.0
		# Keep shooting the current target unless something better turns up.
		if u == target:
			score -= 300.0
		if score < best_score:
			best_score = score
			best = u
	target = best


## Combat.kill() calls this when we die: an explosion, our slot on the node
## is freed (if it is still ours), and nobody can build on the node for
## TurretData.REBUILD_LOCK (60 s; a feature module may tune it for one
## match as "rebuild_lock", see Rules.tune).
func on_killed(_info: DamageInfo) -> void:
	world.effects.explosion(global_position, radius * 2.5, Palette.team(team))
	if node != null and slot < node.slots.size() and node.slots[slot] == self:
		node.slots[slot] = null
	if node != null:
		node.rebuild_lock_until = world.time + float(Rules.tune("rebuild_lock", TurretData.REBUILD_LOCK))
