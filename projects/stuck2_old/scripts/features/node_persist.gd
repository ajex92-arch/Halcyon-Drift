class_name NodePersistFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "node_persist" rule variant (fork
## teamfights_jungle, idea D4). It makes a lost turret cost more: the node
## stays locked for building much longer, and a turret that is built again
## comes back weak and has to heal. So a push that breaks a node keeps its
## value, and the fights over the nodes matter. REQ-CHANGE: none. This
## module OWNS the turret rebuild-lock lever (the other forks do not touch
## it).
##
## HOW IT WORKS:
##   - install() sets the tuned number "rebuild_lock" (TurretData.
##     REBUILD_LOCK, normally 60 s) to 150 s (LOCK), so nobody can build on a
##     node for 150 seconds after a turret there is destroyed.
##   - It remembers, per node, how many turrets were destroyed there (it
##     listens to Events.turret_destroyed). When a new turret appears on such
##     a node it is a "rebuilt" turret: it starts at 50% of its hull instead
##     of 30%, and from then on its hull does not grow by the usual building
##     rule; instead it repairs 1% of its maximum hull per second until it is
##     full (so it is 50 seconds from 50% to full, about the same time as
##     the build plus a second 25 seconds). A rebuilt turret is counted in
##     the usage count "persist_rebuilds".
##   - The AI admiral (AdmiralBuilder, through nodes_by_distance) visits the
##     nodes nearest its own mothership first, so a lost turret near home is
##     rebuilt before a far one. Backdoor protection and the aggro rules are
##     not touched.
## No random numbers are drawn.
##
## WHO USES IT: FeatureRegistry installs it for --variant=node_persist:on.
## Turret.on_killed reads the tuned lock; AdmiralBuilder asks
## nodes_by_distance().

## The variant key this module belongs to.
const KEY := "node_persist"
## The new rebuild lock, in seconds.
const LOCK := 150.0
## A rebuilt turret's starting hull, as a fraction of its maximum.
const START_FRAC := 0.5
## How much of its maximum hull a rebuilt turret repairs per second.
const REPAIR_PER_SEC := 0.01

## The match.
var world: World
## Node id -> how many turrets destroyed there are still waiting to be
## "rebuilt".
var lost := {}
## Turret instance id -> {"rebuilt": true, "building": whether the turret was
## still building at the start of the last tick}. Every turret seen is listed.
var seen := {}


## Hook the module into match `w`: raise the lock, listen for lost turrets
## and start the tick.
func install(w: World) -> void:
	world = w
	Game.tunables["rebuild_lock"] = LOCK
	Events.turret_destroyed.connect(_on_turret_destroyed)
	w.tick_hooks.append(Callable(self, "tick"))


## Events.turret_destroyed: remember a lost turret's node.
func _on_turret_destroyed(turret: Node, _by_team: int) -> void:
	var node := (turret as Turret).node
	if node != null:
		lost[node.node_id] = int(lost.get(node.node_id, 0)) + 1


## Called by World every tick (after every turret has had its turn): notice
## new turrets, and heal the rebuilt ones by the module's rule.
func tick(dt: float) -> void:
	for t: Turret in world.turrets:
		if not t.alive:
			continue
		var id := t.get_instance_id()
		if not seen.has(id):
			# First sight of this turret (it was made this tick, so it has not
			# had a tick of building yet).
			var rec := {"rebuilt": false, "building": t.build_left > 0.0}
			if t.node != null and int(lost.get(t.node.node_id, 0)) > 0:
				lost[t.node.node_id] = int(lost[t.node.node_id]) - 1
				rec["rebuilt"] = true
				t.hull = minf(t.hull_max, t.hull_max * START_FRAC)
				Game.count_usage("persist_rebuilds")
			seen[id] = rec
			continue
		var r: Dictionary = seen[id]
		if not bool(r["rebuilt"]):
			continue
		# A rebuilt turret: while it was building, undo the usual building
		# growth of this tick (70% of the maximum hull over the build time);
		# then add the repair, until the hull is full.
		if bool(r["building"]):
			t.hull -= t.hull_max * 0.7 * dt / t.build_total
		t.hull = clampf(t.hull + t.hull_max * REPAIR_PER_SEC * dt, 1.0, t.hull_max)
		r["building"] = t.build_left > 0.0
		if t.hull >= t.hull_max and t.build_left <= 0.0:
			r["rebuilt"] = false


## The match's ore nodes, nearest to team `team`'s mothership first (ties in
## map order). AdmiralBuilder visits them in this order.
func nodes_by_distance(team: int) -> Array:
	var ms := world.mothership(team)
	var out: Array = world.nodes.duplicate()
	if ms == null:
		return out
	var at := ms.global_position
	# A stable insertion sort (the node list is only nine long).
	for i in range(1, out.size()):
		var n: ResourceNode = out[i]
		var d := n.global_position.distance_to(at)
		var j := i - 1
		while j >= 0 and (out[j] as ResourceNode).global_position.distance_to(at) > d:
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = n
	return out
