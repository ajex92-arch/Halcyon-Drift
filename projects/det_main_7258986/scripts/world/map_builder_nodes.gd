class_name MapBuilderNodes
extends RefCounted
## WHAT THIS IS: step 2 of the map maker (a part of MapBuilder, kept in its
## own file). It places the ore nodes: the rocky fields that mining drones
## scoop ore (the game's money) from, with spots around them where turrets
## can be built.
##
## HOW IT WORKS: for every node in MapLayout.NODES, in list order:
##   1. Work out its turret slots: 1 to 3 spots in a short arc on the side
##      of the node that faces its lane.
##   2. Scatter its ore rocks inside it, spaced apart (this uses random
##      numbers).
##   3. Write the node into the map. An "inner" node (near a mothership) is
##      authored for Aurelian only, so it is written twice: once as it is
##      and once mirrored for Vhorr ("hal_top" and "cin_top", say). A
##      "middle" node sits on the centre line and is shared, so it is
##      written once.
##   4. Keep later rocks out: lane wall rocks must stay out of the node
##      (MapBuilder.node_keep), and fill rocks must stay out of it with 250
##      world units to spare (MapBuilder.keep_out).
##   5. Add its ore rocks to the builder's rock list. Ore rocks are real,
##      solid rocks that can never be destroyed.
##
## WHO USES IT: only MapBuilder._run(), which makes one, calls run() once
## and throws it away.

## The map builder this part works for. We use its random numbers (rng),
## its map (info) and its lists (rocks, node_keep, keep_out).
var mb: MapBuilder


## Remember the builder. MapBuilder makes this part once per map.
func _init(builder: MapBuilder) -> void:
	mb = builder


## Place every ore node (see HOW IT WORKS).
func run() -> void:
	for nd: Dictionary in MapLayout.NODES:
		# Steps 1 and 2: the turret slots and the ore rocks. "The Crossing"
		# (c_mid) gets 6 ore rocks; every other node MapLayout.ORE_ROCKS (5).
		var p: Vector2 = nd["pos"]
		var lane: String = nd["lane"]
		var slots: int = int(nd["slots"])
		var slot_pos := _slot_positions(p, lane, slots)
		var ores := _ore_rocks(p, 6 if nd["id"] == "c_mid" else MapLayout.ORE_ROCKS, nd["kind"] == "middle")
		# Step 3: an inner node is written for both teams (t = 0 Aurelian as
		# authored, t = 1 Vhorr mirrored), with its slots and ore mirrored too.
		if nd["kind"] == "inner":
			for t in 2:
				var mp := p if t == 0 else MapLayout.mirror(p)
				var sp := PackedVector2Array()
				for s in slot_pos:
					sp.append(s if t == 0 else MapLayout.mirror(s))
				var ore_list: Array = []
				for o: Dictionary in ores:
					ore_list.append({"pos": o["pos"] if t == 0 else MapLayout.mirror(o["pos"]), "r": o["r"]})
				# "h_top" becomes "hal_top" or "cin_top", and "Halcyon Top"
				# becomes "Halcyon Top" or "Cinder Top".
				var id: String = ("hal" if t == 0 else "cin") + str(nd["id"]).substr(1)
				var nm: String = str(nd["name"]).replace("Halcyon", Rules.TEAM_NAMES[t])
				_add_node(id, nm, mp, "inner", t, lane, float(nd["value"]), sp, ore_list)
				# Step 4: keep later rocks out of this node.
				mb.node_keep.append({"c": mp, "r": MapLayout.NODE_RADIUS})
				mb.keep_out.append({"c": mp, "r": MapLayout.NODE_RADIUS + 250.0})
		else:
			# A middle node is shared (side -1) and written once.
			_add_node(nd["id"], nd["name"], p, "middle", -1, lane, float(nd["value"]), slot_pos, ores)
			mb.node_keep.append({"c": p, "r": MapLayout.NODE_RADIUS})
			mb.keep_out.append({"c": p, "r": MapLayout.NODE_RADIUS + 250.0})
		# Step 5: ore rocks are physical, indestructible rocks. An inner
		# node's rocks get a mirror copy later (MapBuilder._emit_rocks); a
		# middle node's rocks already cover both halves.
		for o: Dictionary in ores:
			mb.rocks.append({"p": o["pos"], "r": o["r"], "node": true, "mirror": nd["kind"] == "inner"})


## Add one node to the map's node list (MapInfo.nodes). `side` is the
## owning team (0 Aurelian, 1 Vhorr) or -1 for a shared middle node;
## `value` is how rich the node is (from MapLayout.NODES); `slot_pos` are
## its turret slots and `ore` its ore rocks ([{pos, r}]).
func _add_node(id: String, nm: String, pos: Vector2, kind: String, side: int, lane: String, value: float, slot_pos: PackedVector2Array, ore: Array) -> void:
	mb.info.nodes.append({"id": id, "name": nm, "pos": pos, "kind": kind, "side": side, "lane": lane,
		"value": value, "slot_pos": slot_pos, "ore": ore})


## Turret slots for a node at `p`: `n` spots (1, 2 or 3) in an arc on the
## side of the node that faces the nearest point of its lane, each
## MapLayout.NODE_RADIUS + 140 world units from the node's centre.
func _slot_positions(p: Vector2, lane: String, n: int) -> PackedVector2Array:
	# Which way the lane is, seen from the node (straight up if the node
	# sits exactly on the lane's centre line).
	var proj := Util.project_on_polyline(p, mb.info.lanes[lane])
	var dir: Vector2 = ((proj["point"] as Vector2) - p).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	# How far each slot is turned from that direction (radians): one slot
	# straight ahead, two at +-0.34, three at -0.6, 0 and +0.6.
	var offs := [0.0] if n == 1 else ([-0.34, 0.34] if n == 2 else [-0.6, 0.0, 0.6])
	var out := PackedVector2Array()
	for o: float in offs:
		out.append(p + dir.rotated(o) * (MapLayout.NODE_RADIUS + 140.0))
	return out


## Scatter `n` ore rocks inside the node at `p` and return them as
## [{pos, r}]. Each rock sits 140 to 480 world units from the centre, has a
## radius of 42 to 72, and keeps clear of the others. Middle nodes sit on
## the mirror line (`on_axis`), so we make half the rocks on Aurelian's side
## and mirror them, so both sides see the same field; if `n` is odd, one
## more rock (radius 50) goes 60 units above the centre.
func _ore_rocks(p: Vector2, n: int, on_axis: bool) -> Array:
	var out: Array = []
	var guard := 0
	var want := n
	if on_axis:
		want = n / 2
	# Try random spots until we have enough rocks (at most 400 tries, so a
	# crowded node can't loop forever). Each try uses 3 random numbers.
	while out.size() < want and guard < 400:
		guard += 1
		var a := mb.rng.next() * TAU
		var d := 140.0 + mb.rng.next() * (MapLayout.NODE_RADIUS - 220.0)
		var r := 42.0 + mb.rng.next() * 30.0
		var q := p + Vector2.from_angle(a) * d
		# On the mirror line, a rock too close to (or past) the centre line
		# is flipped over to Aurelian's side; if it is still too close, the
		# try is wasted.
		if on_axis and q.x > MapLayout.CX - r - 40.0:
			q.x = 2.0 * MapLayout.CX - q.x
			if q.x > MapLayout.CX - r - 40.0:
				continue
		# Keep the rock only if it is well clear of the rocks we already
		# have (1.6 times the two radii added together).
		var ok := true
		for o: Dictionary in out:
			if (o["pos"] as Vector2).distance_to(q) < (float(o["r"]) + r) * 1.6:
				ok = false
				break
		if ok:
			out.append({"pos": q, "r": r})
	# On the mirror line: add the mirror copies, plus the odd middle rock.
	if on_axis:
		var half := out.duplicate()
		for o: Dictionary in half:
			out.append({"pos": MapLayout.mirror(o["pos"]), "r": o["r"]})
		if n % 2 == 1:
			out.append({"pos": p + Vector2(0, -60), "r": 50.0})
	return out
