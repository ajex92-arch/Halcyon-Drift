class_name MiningDrone
extends Unit
## WHAT THIS IS: a small robot ship that flies to an ore node, cuts ore
## (the game's money) from its rocks, and carries it home to the
## mothership. DESIGN.md A7.
##
## HOW IT WORKS: it is always in one of four moods, kept in `state`:
##   "out"   fly to the chosen node along the route map's big-ship links
##           (the lanes), then to the best rock there;
##   "mine"  sit at the rock and cut ore (mine_rate per second) until the
##           hold is full or the rock runs dry;
##   "home"  fly back to the drop-off point beside the mothership and hand
##           the ore over;
##   "idle"  no node to go to: wait beside the mothership and try again
##           every 3 s.
## Ore pays ONLY when it is delivered (Economy.deliver_ore): 60% to the
## team treasury, 40% split among living pilots, plus an escort bonus for
## pilots who flew near the drone on the trip. Enemy pilots get a bounty
## for shooting it down, and the team remembers where it lost drones, so
## for a while new trips avoid that node (TeamState.note_drone_loss).
##
## `assign` is the node the admiral ordered it to ("" = automatic:
## World.best_node_for_drone() picks the best node each trip).
##
## WHO USES IT: TeamState's drone line (TeamDrones: free drones and the ones
## the admiral orders) and WorldSetup (the starting drones) make them
## through World.spawn_mining_drone -> WorldSpawner, which calls setup().
## World calls sim_update() every tick. AdmiralCommand changes `assign`;
## WorldResearch changes hull_max and capacity after research; WorldMining
## counts drones per node (node_id); Economy reads `escorts`; UnitVisual
## draws cargo, capacity, state and rock.

## The node id the admiral ordered it to, or "" to choose automatically.
var assign := ""
## The id of the node it is flying to or mining now ("" for none).
var node_id := ""
## Which rock of that node it is going to or mining (an index into the
## node's ore lists), or -1 for none yet.
var rock := -1
## Its mood: "out", "mine", "home" or "idle" (see HOW IT WORKS).
var state := "out"
## Ore in the hold right now.
var cargo := 0.0
## The most ore the hold takes: 300 x (1 + the team's mining capacity
## research).
var capacity := 300.0
## How fast it cuts ore, in ore per second.
var mine_rate := 40.0
## Top speed, in world units per second (1 world unit is about one pixel at
## normal zoom).
var speed := 460.0
## How fast it can change its velocity, in world units per second, per
## second.
var accel := 300.0
## The route it is following: points in world positions.
var path := PackedVector2Array()
## Which point of `path` it is flying to (an index).
var path_i := 0
## The pilots who escorted it on this trip: PilotProfile -> true (used as
## a set: only the keys matter). Cleared at each delivery.
var escorts := {}
## Seconds until the next escort check (every 0.5 s).
var escort_t := 0.0
## A reusable list for the asteroid search in Steer.avoid_rocks().
var _rocks := PackedInt32Array()
## A reusable list for searching the spatial hash (World.unit_hash, a grid
## that quickly finds the units near a point).
var _scratch: Array = []


## Set up a mining drone for team `t` at `at`, ordered to node `assigned`
## ("" = choose automatically), and send it out at once.
## WorldSpawner.spawn_mining_drone() calls this.
func setup(w: World, t: int, at: Vector2, assigned: String) -> void:
	# Step 1: who and what we are; drone armour and mining capacity research
	# make the hull and the hold bigger.
	world = w
	team = t
	kind = Unit.K_MINING_DRONE
	size_class = Rules.SIZE_SMALL
	var d: Dictionary = Structures.MINING_DRONE
	radius = float(d["radius"])
	speed = float(d["speed"])
	accel = float(d["accel"])
	vision_radius = float(d["vision"])
	var ts: TeamState = w.teams[t]
	hull_max = float(d["hp"]) * (1.0 + ts.drone_armor)
	hull = hull_max
	capacity = float(d["capacity"]) * (1.0 + ts.mining_capacity)
	mine_rate = float(d["mine_rate"])
	assign = assigned
	# Step 2: where we start. Drones take no part in physics bumps (layer
	# and mask 0): they move by setting `position`.
	position = at
	collision_layer = 0
	collision_mask = 0
	display_name = "Mining drone"
	# Step 3: off we go.
	_go_out()


## Start a trip out: pick the node (the admiral's, or the best one), and get
## a route there. With no node to go to, wait ("idle").
func _go_out() -> void:
	state = "out"
	rock = -1
	node_id = assign if assign != "" else world.best_node_for_drone(team, global_position)
	var n := world.node_by_id(node_id)
	if n == null:
		state = "idle"
		path = PackedVector2Array()
		return
	# Big-ship links only (`false`), so drones keep to the lanes.
	path = world.map.route.path(global_position, n.global_position, false)
	path_i = 0


## Start the trip home: get a route to the drop-off point beside our
## mothership.
func _go_home() -> void:
	state = "home"
	path = world.map.route.path(global_position, world.drop_off_point(team, global_position), false)
	path_i = 0


## One tick of `dt` seconds: note escorts, then do whatever our mood says.
## World calls it every tick.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
	# Step 1: every 0.5 s, note the friendly pilots flying near us.
	escort_t -= dt
	if escort_t <= 0.0:
		escort_t = 0.5
		_note_escorts()
	match state:
		"idle":
			# Wait 700 world units to the left (team 0) or right (team 1) of
			# our mothership's centre, spread up and down by our uid so idle
			# drones don't stack. Every 3 s try to go out again (the time of
			# the last try is kept in the node's "metadata", a little named
			# value Godot lets us store on any node).
			_steer_to(world.mothership(team).global_position + Vector2(-700.0 if team == 0 else 700.0, float(uid % 7 - 3) * 80.0), dt, 200.0)
			if world.time - float(get_meta("idle_t", 0.0)) > 3.0:
				set_meta("idle_t", world.time)
				_go_out()
		"out":
			# The node is gone: choose again.
			var n := world.node_by_id(node_id)
			if n == null:
				_go_out()
				return
			# Choose a rock at the node, if we have none yet.
			if rock < 0:
				rock = n.best_rock(global_position)
				if rock < 0:
					# Node is dry; try somewhere else.
					node_id = ""
					_go_out()
					return
			# Close to the rock (its radius + 50): stop and start mining.
			# Otherwise keep flying.
			var target := n.ore_pos[rock]
			if global_position.distance_to(target) < n.ore_r[rock] + 50.0:
				state = "mine"
				velocity = Vector2.ZERO
			else:
				_follow(target, dt)
		"mine":
			# The node or rock is gone: go home with what we have.
			var n := world.node_by_id(node_id)
			if n == null or rock < 0:
				_go_home()
				return
			# Cut ore, slow to a stop (we don't move while mining) and face
			# the rock.
			cargo += n.take_ore(rock, mine_rate * dt)
			velocity = velocity.move_toward(Vector2.ZERO, accel * dt)
			rotation = (n.ore_pos[rock] - global_position).angle()
			# Hold full: go home. Rock dry (under 1 ore): pick another rock
			# here; if none is left, go home with any cargo, or else find a
			# new node.
			if cargo >= capacity - 0.01:
				_go_home()
			elif n.ore[rock] < 1.0:
				rock = n.best_rock(global_position)
				if rock < 0:
					if cargo > 0.0:
						_go_home()
					else:
						_go_out()
				else:
					state = "out"
		"home":
			# Within 140 of the mothership's hull: deliver (only now does the
			# ore pay), forget this trip's escorts and go out again.
			# Otherwise keep flying to the drop-off point.
			var drop := world.drop_off_point(team, global_position)
			if world.drop_off_dist(team, global_position) < 140.0:
				if cargo > 0.0:
					Economy.deliver_ore(world, team, cargo, self)
				cargo = 0.0
				escorts.clear()
				_go_out()
			else:
				_follow(drop, dt)


## Fly along our route toward `final` for one step of `dt` seconds. We aim
## at the route's next point (moving on within 500 of it), and at `final`
## itself once on the last leg, or when there is no route.
func _follow(final: Vector2, dt: float) -> void:
	if path.size() > 0:
		path_i = Steer.advance(path, path_i, global_position, 500.0)
		var tgt := path[path_i] if path_i < path.size() - 1 else final
		_steer_to(tgt, dt, 120.0)
	else:
		_steer_to(final, dt, 120.0)


## Fly toward `target` for one step of `dt` seconds, slowing down within
## `arrive` world units of it, sliding around asteroids, and facing the way
## we fly (when faster than 10 world units per second).
func _steer_to(target: Vector2, dt: float, arrive: float) -> void:
	velocity = Steer.seek(global_position, velocity, target, speed, accel, dt, arrive)
	velocity += Steer.avoid_rocks(world.asteroids, global_position, radius, velocity * 0.3, _rocks) * dt
	position += velocity * dt
	if velocity.length_squared() > 100.0:
		rotation = velocity.angle()


## Remember every friendly pilot whose ship is within Rules.ESCORT_RANGE
## (1,100 world units) of us: they share the escort bonus on delivery.
func _note_escorts() -> void:
	for u: Unit in world.unit_hash.query(global_position, Rules.ESCORT_RANGE, _scratch):
		if u is Ship and u.team == team and u.alive and u.global_position.distance_to(global_position) < Rules.ESCORT_RANGE:
			var p: PilotProfile = (u as Ship).profile
			if p != null:
				escorts[p] = true


## Combat.kill() calls this when we are shot down: a small explosion, and
## our team remembers that it lost a drone at this node (so new trips avoid
## it for a while).
func on_killed(_info: DamageInfo) -> void:
	world.effects.explosion(global_position, 40.0, Palette.team(team))
	world.teams[team].note_drone_loss(node_id, world.time)
