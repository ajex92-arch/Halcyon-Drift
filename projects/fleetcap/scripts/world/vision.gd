class_name Vision
extends RefCounted
## WHAT THIS IS: the fog of war, with line of sight. It keeps track of which
## parts of the map each team can see right now, and which parts it has
## ever seen. Asteroids block sight (DESIGN.md A4: "players cannot see
## through asteroids").
##
## HOW IT WORKS: the map is cut into a grid of square cells,
## Rules.VISION_CELL (200) world units wide.
##   - A cell is "blocked" when an asteroid covers its centre
##     (rebuild_blocked).
##   - Each "viewer" (a unit of the team that can see, with its sight
##     radius) lights the cells it can see. Rays go out from its cell in
##     every direction and stop at the first blocked cell; that cell itself
##     is lit, so you see the rock. VisionRays (vision_rays.gd) casts the
##     rays and remembers the answer for each cell and radius, so viewers
##     standing where others stood before cost almost nothing. That memory
##     (the "cache") is emptied when a rock is destroyed.
##   - Reveals (the Scout Ping special) light a whole circle for a few
##     seconds, ignoring rocks.
##
## The "stamp" trick: each team has a counter (its stamp) that goes up by
## one at every update, and a lit cell stores the stamp of the update that
## lit it. A cell is lit right now when its number equals the team's
## current stamp. So the old light never needs to be wiped: it simply stops
## matching.
##
## Whether a UNIT is seen is decided by WorldVisibility: it is seen if its
## cell is lit, or if it is within Rules.VISION_TOUCH (350 world units) of
## one of the team's units. Wards have their own stealth rule there.
##
## WHO USES IT: WorldSetup makes it (World.vision), calls setup(), connects
## AsteroidField.rock_destroyed to on_rock_destroyed(), and lights both
## teams once at the start. WorldVisibility calls update_team() for one
## team every 0.1 s (so each team 5 times a second, Rules.VISION_HZ) and
## reads is_visible() and reveals. ShipAbilities adds reveals (Scout Ping).
## FogView draws the fog from lit, explored and stamp; the Minimap asks
## is_explored(). Projectiles, Effects, Sfx, WorldRegistry and
## AdmiralCommand ask is_visible().

## Number of grid columns: the map width divided by the cell size, rounded
## up. Set by setup().
var cols := 1
## Number of grid rows (the same for the map height).
var rows := 1
## Width of one square cell (world units): Rules.VISION_CELL (200).
var cell := Rules.VISION_CELL
## Per cell: 1 if an asteroid blocks sight there, else 0. Cell (cx, cy) is
## at index cx + cy * cols in this list and in the lists below.
var blocked := PackedByteArray()
## Per team (index 0 and 1): a list with, for each cell, the stamp of the
## last update that lit it (see the stamp trick above).
var lit: Array = []
## Per team: the stamp of its latest update. Starts at 1, and every cell
## starts at 0, so nothing is lit before the first update.
var stamp := [1, 1]
## Per team: a list with, for each cell, 1 once the team has ever seen it
## (FogView draws those cells less dark; the Minimap shows them).
var explored: Array = []
## Active reveal circles, each {"team", "pos", "r" (world units), "until"
## (match time in seconds)}. update_team() drops the expired ones.
var reveals: Array = []
## The ray caster part (vision_rays.gd), made by setup().
var rays: VisionRays
## Per team (index 0 and 1): the cell + radius keys (cell * 64 + radius in
## cells) whose cells update_team() has already marked as explored, so it
## doesn't mark them again at every update. Emptied with the ray cache when
## the rocks change (rebuild_blocked).
var _explored_keys: Array = [{}, {}]
## The world (we read its asteroids and its match clock).
var world: World


## Build the grid for the whole map (MapLayout.W by MapLayout.H world
## units): the blocked cells, and an empty "lit" and "explored" list for
## each of the two teams. WorldSetup calls this once.
func setup(w: World) -> void:
	world = w
	# Step 1: the grid size, rounded up so the whole map is covered.
	cols = int(ceil(MapLayout.W / cell))
	rows = int(ceil(MapLayout.H / cell))
	blocked.resize(cols * rows)
	# Step 2: the ray caster (it needs the grid size).
	rays = VisionRays.new(self)
	# Step 3: empty lit and explored lists for both teams.
	for t in 2:
		var l := PackedInt32Array()
		l.resize(cols * rows)
		lit.append(l)
		var e := PackedByteArray()
		e.resize(cols * rows)
		explored.append(e)
	# Step 4: mark the cells the asteroids block.
	rebuild_blocked()


## Work out again which cells the asteroids block. A live rock blocks every
## cell whose centre lies within 90% of its radius. A rock that covers no
## cell centre that way still blocks the one cell it sits in, if its radius
## is over 60 world units. Afterwards the ray cache is emptied, because the
## old answers may be wrong now.
func rebuild_blocked() -> void:
	blocked.fill(0)
	var f := world.asteroids
	for i in f.pos.size():
		# Destroyed rocks block nothing.
		if f.alive[i] == 0:
			continue
		# The box of cells that the rock (shrunk to 90%) could cover.
		var p := f.pos[i]
		var r := f.rad[i] * 0.9
		var x0 := clampi(int((p.x - r) / cell), 0, cols - 1)
		var x1 := clampi(int((p.x + r) / cell), 0, cols - 1)
		var y0 := clampi(int((p.y - r) / cell), 0, rows - 1)
		var y1 := clampi(int((p.y + r) / cell), 0, rows - 1)
		# Block each cell in that box whose centre is inside the circle.
		var marked := false
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var c := Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
				if c.distance_to(p) < r:
					blocked[cx + cy * cols] = 1
					marked = true
		# Smaller rocks (radius over 60) still block the cell they sit in.
		if not marked and f.rad[i] > 60.0:
			blocked[clampi(int(p.x / cell), 0, cols - 1) + clampi(int(p.y / cell), 0, rows - 1) * cols] = 1
	rays.clear_cache()
	# With the rocks changed, the same cell + radius may now reach more
	# cells: forget which ones were already explored.
	for keys: Dictionary in _explored_keys:
		keys.clear()


## The cell number (index into blocked, lit and explored) of world point
## `p`. Points outside the map count as the nearest edge cell.
func cell_of(p: Vector2) -> int:
	return clampi(int(p.x / cell), 0, cols - 1) + clampi(int(p.y / cell), 0, rows - 1) * cols


## True if team `team` can see point `p` right now (its cell is lit). Any
## other team number (such as -1 for a spectator) sees everything.
func is_visible(team: int, p: Vector2) -> bool:
	if team < 0 or team > 1:
		return true
	return (lit[team] as PackedInt32Array)[cell_of(p)] == int(stamp[team])


## True if team `team` (0 or 1) has ever seen point `p`'s cell.
func is_explored(team: int, p: Vector2) -> bool:
	return (explored[team] as PackedByteArray)[cell_of(p)] == 1


## Light a circle of radius `r` (world units) around `p` for team `team`,
## for `secs` seconds, ignoring asteroids (Scout Ping). It shows from the
## team's next update_team() on.
func reveal(team: int, p: Vector2, r: float, secs: float) -> void:
	reveals.append({"team": team, "pos": p, "r": r, "until": world.time + secs})


## Work out again which cells team `team` sees. `viewers` holds one
## Vector3(x, y, sight radius) per unit that can see (from
## WorldVisibility.viewers()). WorldVisibility calls this for one team
## every 0.1 s.
func update_team(team: int, viewers: Array) -> void:
	# Step 1: a new stamp. Everything the last update lit now stops
	# counting, without touching it.
	stamp[team] = int(stamp[team]) + 1
	var s: int = stamp[team]
	var l: PackedInt32Array = lit[team]
	var e: PackedByteArray = explored[team]
	# Step 2: each viewer lights (and explores) the cells its rays reach.
	# Its radius is counted in whole cells, rounded up, from 1 to 40.
	# Speed-ups (they change nothing about what is lit or explored):
	#  - viewers in the same cell with the same radius see exactly the same
	#    cells, so only the first of them does the work (`done_now`); a wave
	#    of minions flying in a clump often shares a few cells;
	#  - "explored" only ever gains cells, and a given cell + radius always
	#    reaches the same cells (until a rock is destroyed, which empties
	#    `_explored_keys`), so each cell + radius marks explored cells just
	#    once per team (`done_ever`) instead of at every update.
	var done_now := {}
	var done_ever: Dictionary = _explored_keys[team]
	for v: Vector3 in viewers:
		var r := v.z
		if r <= 0.0:
			continue
		var c := cell_of(Vector2(v.x, v.y))
		var rc := clampi(int(ceil(r / cell)), 1, 40)
		# The same key the ray cache uses for this cell + radius.
		var key := c * 64 + rc
		if done_now.has(key):
			continue
		done_now[key] = true
		var seen := rays.cells_seen(c, rc)
		if done_ever.has(key):
			# Already explored: just light the cells.
			for idx in seen:
				l[idx] = s
		else:
			done_ever[key] = true
			for idx in seen:
				l[idx] = s
				e[idx] = 1
	# Step 3: reveals light every cell whose centre is in their circle,
	# ignoring rocks. Expired reveals (of either team) are dropped here.
	var keep: Array = []
	for rv: Dictionary in reveals:
		if world.time > float(rv["until"]):
			continue
		keep.append(rv)
		if int(rv["team"]) != team:
			continue
		var p: Vector2 = rv["pos"]
		var rr: float = rv["r"]
		var x0 := clampi(int((p.x - rr) / cell), 0, cols - 1)
		var x1 := clampi(int((p.x + rr) / cell), 0, cols - 1)
		var y0 := clampi(int((p.y - rr) / cell), 0, rows - 1)
		var y1 := clampi(int((p.y + rr) / cell), 0, rows - 1)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var cc := Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
				if cc.distance_to(p) <= rr:
					l[cx + cy * cols] = s
					e[cx + cy * cols] = 1
	reveals = keep


## A rock was shot apart (AsteroidField.rock_destroyed): work out the
## blocked cells again, so sight passes where the rock was.
func on_rock_destroyed() -> void:
	rebuild_blocked()
