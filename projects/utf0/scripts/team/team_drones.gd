class_name TeamDrones
extends RefCounted
## WHAT THIS IS: the mothership's mining-drone factory, plus the team's
## memory of where its drones were shot down. (Mining drones are small
## robot ships that fly to ore nodes, scoop up ore and carry it home, which
## pays the team and its pilots.)
##
## HOW IT WORKS: tick() runs every tick while our mothership is alive. It
## does two things:
##   - Free drones: while we have fewer than 3 drones (living plus queued;
##     Structures.MINING_DRONE "free_floor"), a clock counts down from 20 s
##     ("free_every"). When it runs out, the mothership builds a free drone
##     that picks its own node, and the clock starts again. With 3 or more
##     drones, the clock is simply kept full.
##   - Ordered drones: the admiral pays for drones
##     (AdmiralCommand.build_drone), which wait in TeamState.drone_queue.
##     The first one is finished after 6 s ("build"), then the next one
##     starts: one at a time.
## When a drone is destroyed, MiningDrone calls note_drone_loss() with the
## node it was working. danger() counts the recent losses at a node, so
## WorldMining.best_node_for_drone() can steer drones away from nodes where
## they keep dying.
##
## WHO USES IT: TeamState makes one (TeamState.drone_line) and forwards
## _drone_line(), note_drone_loss() and drone_danger() here.
## AdmiralCommand.build_drone() fills the queue; the AI admiral and the
## admiral board read TeamState.drone_queue and drones_lost.

## The team this part belongs to (we read and change its drone fields).
## It is reached through a weak link: see `_ts_ref`.
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A "weak" link to the team. TeamState holds this part with a normal
## (strong) link. If the part held the team strongly too, each would keep
## the other alive forever and Godot could never free them (a memory
## leak). A weak link points at the team without keeping it alive.
var _ts_ref: WeakRef


## Remember our team (through a weak link). TeamState makes this part once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)


## Run the drone factory for one tick of `dt` seconds: free drones when we
## are short, and the drones the admiral ordered.
func tick(dt: float) -> void:
	var world := ts.world
	var team := ts.team
	# Step 1: free drones. Count living drones plus the ones in the queue.
	var count := world.mining_drone_count(team) + ts.drone_queue.size()
	if count < int(Structures.MINING_DRONE["free_floor"]):
		ts.free_drone_t -= dt
		# The clock ran out: build one free drone (it picks its own node).
		if ts.free_drone_t <= 0.0:
			ts.free_drone_t = float(Structures.MINING_DRONE["free_every"])
			world.spawn_mining_drone(team, "")
			Events.feed.emit("The %s mothership built a free mining drone." % Rules.TEAM_DISPLAY[team], "info", team)
	else:
		# Enough drones: keep the free-drone clock full.
		ts.free_drone_t = float(Structures.MINING_DRONE["free_every"])
	# Step 2: ordered drones, one at a time. When the build clock runs
	# out, the first drone in the queue is built and sent to its node.
	if not ts.drone_queue.is_empty():
		ts.drone_t -= dt
		if ts.drone_t <= 0.0:
			var assign: String = ts.drone_queue.pop_front()
			world.spawn_mining_drone(team, assign)
			ts.drone_t = float(Structures.MINING_DRONE["build"])


## One of our drones was destroyed while working node `node_id`, at match
## time `now` (seconds). Write it down (a drone with no node, "", is not
## written down).
func note_drone_loss(node_id: String, now: float) -> void:
	if node_id == "":
		return
	var times: Array = ts.drone_loss_log.get(node_id, [])
	times.append(now)
	ts.drone_loss_log[node_id] = times


## How many of our drones were lost at node `node_id` in the `window`
## seconds before match time `now`.
func danger(node_id: String, now: float, window: float) -> int:
	var n := 0
	for t in ts.drone_loss_log.get(node_id, []):
		if now - float(t) < window:
			n += 1
	return n
