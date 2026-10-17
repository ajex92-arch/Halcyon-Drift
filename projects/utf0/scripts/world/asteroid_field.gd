class_name AsteroidField
extends Node2D
## WHAT THIS IS: every asteroid in the match: the jungle rocks, the lane
## walls, the rocks along the map's rim and the ore rocks of resource
## nodes. It knows where each rock is, how big it is, how much more damage
## it can take, and whether it is still there. DESIGN.md A4.
##
## HOW IT WORKS: each rock is a number (its "index", 0, 1, 2, ...), and
## its facts sit at that index in several lists: pos[i], rad[i], hp[i],
## alive[i], node_rock[i], outline[i], shade[i], bodies[i], shapes[i].
##   - Collision: every rock gets one invisible, solid circle in Godot's
##     physics engine. We talk to the engine directly (PhysicsServer2D)
##     instead of making a scene node per rock, which is much lighter.
##     Ordinary rocks are on collision layer 1, ore rocks on layer 4, so
##     pilot ships bump off them when they move (move_and_slide()).
##   - Finding rocks: a grid over the map remembers which rocks touch each
##     square, so "which rocks are near here?" and "does this line hit a
##     rock?" only look at a few rocks (the AsteroidFieldQueries part).
##   - Drawing: the rocks are grouped into square "chunks" CHUNK world
##     units wide (AsteroidFieldChunk). Godot remembers what each chunk
##     drew, so a chunk is only drawn again when one of its rocks is
##     destroyed.
##   - Destruction: rocks can be shot apart, except ore rocks. Only
##     "cutting" weapons (capital-class shells and ion beams, marked "cuts"
##     in Weapons) call damage(). At 0 hp the rock is gone for good: its
##     collision circle is removed, its chunk redraws, and rock_destroyed
##     tells Vision to work out again what blocks sight. Searches skip dead
##     rocks, so steering and line-of-fire checks update by themselves.
##   - Sealing tight gaps: right after build(), seal_tight_gaps() grows the
##     rocks on both sides of every gap that is just wide enough for a
##     fighter, so no ship can wedge itself between two rocks and stay
##     there (see the comment above TIGHT_LO).
##
## The rock shapes and shades use their own random number maker (Mulberry,
## seeded MapLayout.SEED + 77), so they are the same every match and don't
## disturb any other random numbers.
##
## WHO USES IT: the World scene has one, the "Asteroids" node
## (World.asteroids). WorldSetup.build() calls build() with the map, then
## seal_tight_gaps(), hooks rock_destroyed up to Vision, and lets the route
## graph use segment_hit() to test straight hops. Projectiles and Combat
## (beams) call segment_hit() and damage(); turrets, weapon mounts and
## MinionTargeting.pick_target() ask segment_blocked() before firing; the AI
## pilot's PilotTargeting (pick_target() and prey()) asks segment_blocked()
## to score a target behind a rock worse; PilotFlight calls segment_hit()
## in travel() (is the straight line to the goal clear?) and
## segment_blocked() in target_hidden(); PilotEscape
## uses nearby() and segment_hit() and reads pos and rad; Steer.avoid_rocks()
## and PilotFlight use nearby() and read pos and rad; the command desk
## (AdmiralCommand) asks blocked(); Vision reads pos, rad and alive; main.gd
## prints how many rocks there are.
##
## THE PARTS: asteroid_field_queries.gd (AsteroidFieldQueries) does the
## searching; asteroid_field_chunk.gd (AsteroidFieldChunk) does the
## drawing. The search functions here forward to the queries part.

## Sent once when a rock is destroyed; `index` is the rock's number.
signal rock_destroyed(index: int)

## Size (world units) of a drawing chunk (a square this wide).
const CHUNK := 4000.0
## Hit points per world unit of radius: a rock of radius 100 can take
## 1,200 damage.
const HP_PER_RADIUS := 12.0
## Sealing tight gaps: a gap between two rocks (edge to edge, world units)
## is "tight" when it is wider than TIGHT_LO and narrower than TIGHT_HI.
## A scout is 18 across, a fighter 24 and a lance 26, so in such a gap a
## small ship can slide in between the rocks and wedge there, touching both
## (playtest: every stuck position recorded in 122 match logs touched two
## rocks within 1 unit). Narrower gaps already keep every ship out.
const TIGHT_LO := 17.5
## The widest gap (world units) that counts as tight (see TIGHT_LO).
const TIGHT_HI := 34.0
## How wide (world units) a tight gap is made when it is sealed: just
## under a scout's width, so no ship fits.
const TIGHT_TARGET := 17.0

## Centre of every rock.
var pos := PackedVector2Array()
## Radius of every rock (world units).
var rad := PackedFloat32Array()
## Damage each rock can still take (hit points).
var hp := PackedFloat32Array()
## 1 = the rock is still there, 0 = destroyed.
var alive := PackedByteArray()
## 1 = belongs to a resource node (indestructible).
var node_rock := PackedByteArray()
## The outline of every rock: a PackedVector2Array of 7 to 10 corner
## points around its centre (relative to pos[i]).
var outline: Array = []
## Colour of every rock: 0..1, how far from Palette.ROCK_A towards
## Palette.ROCK_B.
var shade := PackedFloat32Array()
## Every rock's physics body (an RID: the physics engine's id for it).
var bodies: Array[RID] = []
## Every rock's collision circle (an RID: the physics engine's id for it).
var shapes: Array[RID] = []
## The drawing chunks: chunk key (Vector2i: which CHUNK square, across
## and down) -> AsteroidFieldChunk.
var chunks := {}
## The part that finds rocks (made in _init()).
var queries: AsteroidFieldQueries


## Make the search part (with its empty grid) as soon as the node exists.
func _init() -> void:
	queries = AsteroidFieldQueries.new(self)


## Add every rock from the map. Call once after entering the tree.
func build(info: MapInfo) -> void:
	# One random number maker for all the rock shapes, used in rock order.
	var rng := Mulberry.new(MapLayout.SEED + 77)
	for i in info.rock_pos.size():
		_add(info.rock_pos[i], info.rock_r[i], info.rock_node[i] == 1, rng)
	# Let the search part get ready for this many rocks, then draw them all.
	queries.make_room(pos.size())
	for key in chunks:
		(chunks[key] as AsteroidFieldChunk).queue_redraw()


## Add one rock: its facts, its outline, its collision circle, its grid
## squares and its drawing chunk. `is_node` = an ore rock. Uses 3 random
## numbers plus one per corner, always in that order.
func _add(p: Vector2, r: float, is_node: bool, rng: Mulberry) -> void:
	# Step 1: the facts. A rock starts with HP_PER_RADIUS hp per unit of
	# radius, and a random shade.
	var i := pos.size()
	pos.append(p)
	rad.append(r)
	hp.append(r * HP_PER_RADIUS)
	alive.append(1)
	node_rock.append(1 if is_node else 0)
	shade.append(rng.next())
	# Step 2: a lumpy outline with 7 to 10 corners, turned by a random
	# amount, each corner 0.9 to 1.12 times the radius from the centre.
	var n := 7 + int(rng.next() * 4.0)
	var poly := PackedVector2Array()
	var spin := rng.next() * TAU
	for k in n:
		var a := spin + TAU * float(k) / float(n)
		poly.append(Vector2.from_angle(a) * r * (0.9 + rng.next() * 0.22))
	outline.append(poly)
	# Step 3: collision. A slightly smaller circle (95% of the radius) so
	# bumps match the drawn edge. It never moves ("static"). The layer is a
	# "bitmask" (one bit per layer): 1 = layer 1 (rocks), 8 = layer 4 (ore
	# rocks). Mask 0: the rock itself doesn't look for anything to hit.
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, r * 0.95)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, p))
	PhysicsServer2D.body_set_collision_layer(body, 8 if is_node else 1)
	PhysicsServer2D.body_set_collision_mask(body, 0)
	PhysicsServer2D.body_set_space(body, get_world_2d().space)
	bodies.append(body)
	shapes.append(shape)
	# Step 4: the search grid: every square the rock overlaps.
	queries.add_rock(i, p, r)
	# Step 5: the drawing chunk its centre is in (made the first time it is
	# needed, drawn behind the units).
	var key := Vector2i(int(p.x / CHUNK), int(p.y / CHUNK))
	if not chunks.has(key):
		var c := AsteroidFieldChunk.new()
		c.field = self
		c.z_index = -2
		# --sim-only: nothing is drawn, so the chunk is hidden (it then never
		# draws, not even when a rock in it is destroyed).
		c.visible = not Game.sim_only
		add_child(c)
		chunks[key] = c
	var ch: AsteroidFieldChunk = chunks[key]
	ch.members.append(i)


## Rock numbers whose grid squares overlap the circle at `p` with radius
## `r`, each once, dead rocks left out. Fills and returns `out` (it is
## cleared first). The real work is in AsteroidFieldQueries.nearby().
func nearby(p: Vector2, r: float, out: PackedInt32Array) -> PackedInt32Array:
	return queries.nearby(p, r, out)


## True when every rock's edge is at least `need` world units from `p`: a
## quick "nothing to dodge here" test that lets steering skip the rock
## search in open space. The real work is in
## AsteroidFieldQueries.clear_at().
func clear_at(p: Vector2, need: float) -> bool:
	return queries.clear_at(p, need)


## First rock the segment a->b (thickened by pad) touches:
## {"index": i, "t": 0..1} or {} if clear. `t` is how far along a->b the
## hit is (0 = at a, 1 = at b). The real work is in
## AsteroidFieldQueries.segment_hit().
func segment_hit(a: Vector2, b: Vector2, pad: float) -> Dictionary:
	return queries.segment_hit(a, b, pad)


## True if a rock blocks the straight line between a and b (forwards to
## AsteroidFieldQueries.segment_blocked()).
func segment_blocked(a: Vector2, b: Vector2) -> bool:
	return queries.segment_blocked(a, b)


## True if a circle at p (radius `r`) overlaps any rock (forwards to
## AsteroidFieldQueries.blocked()).
func blocked(p: Vector2, r: float) -> bool:
	return queries.blocked(p, r)


## Capital guns chip destructible rocks; at 0 hp the rock is gone for good.
## Rock number `i` loses `amount` hp. A bad number, a dead rock or an ore
## rock is ignored.
func damage(i: int, amount: float) -> void:
	if i < 0 or alive[i] == 0 or node_rock[i] == 1:
		return
	hp[i] -= amount
	if hp[i] <= 0.0:
		destroy(i)


## Close every tight gap between two ordinary rocks (see TIGHT_LO): the pilot
## code flies straight at its next waypoint, the line can lead through such
## a gap, and the stuck handling (reverse, plan the same route again) cannot
## get a wedged ship out. Both rocks of every pair whose gap is between
## TIGHT_LO and TIGHT_HI grow until the gap is TIGHT_TARGET (a scout no
## longer fits). Growing a rock narrows its other gaps, so this repeats, up
## to 4 sweeps. About 460 gaps are sealed and 720 rocks change by 6.5 units
## of radius on average (25 at most); ore rocks are not touched and no gate
## (101 wide) or route link is closed. Call once, right after build().
## Returns how many gaps it sealed. Costs about 0.1 s.
func seal_tight_gaps() -> int:
	var nearby_rocks := PackedInt32Array()
	var sealed := 0
	for sweep in 4:
		var n := 0
		# Step 1: every pair of ordinary rocks, each pair once (j after i).
		for i in pos.size():
			if alive[i] == 0 or node_rock[i] == 1:
				continue
			nearby(pos[i], rad[i] + 300.0, nearby_rocks)
			for j in nearby_rocks:
				if j <= i or alive[j] == 0 or node_rock[j] == 1:
					continue
				# Step 2: the gap between their solid circles (95% of the
				# radius, as in _add()). Grow both rocks by the same amount.
				var gap := pos[i].distance_to(pos[j]) - 0.95 * (rad[i] + rad[j])
				if gap > TIGHT_LO and gap < TIGHT_HI:
					var grow := (gap - TIGHT_TARGET) / (2.0 * 0.95)
					_resize(i, rad[i] + grow)
					_resize(j, rad[j] + grow)
					n += 1
		sealed += n
		if n == 0:
			break
	# Step 3: the clear-space map is built on first use; make sure it sees
	# the new sizes. Redraw the chunks, whose outlines changed.
	queries.reset_clear()
	for key in chunks:
		(chunks[key] as AsteroidFieldChunk).queue_redraw()
	return sealed


## Give rock `i` the radius `r1`: its collision circle, its outline and its
## grid squares.
func _resize(i: int, r1: float) -> void:
	var r0 := rad[i]
	rad[i] = r1
	PhysicsServer2D.shape_set_data(shapes[i], r1 * 0.95)
	var poly: PackedVector2Array = outline[i]
	for k in poly.size():
		poly[k] *= r1 / r0
	outline[i] = poly
	# Filed again so the squares the bigger rock now reaches list it (a rock
	# may stand in a square twice; the searches count each rock once).
	queries.add_rock(i, pos[i], r1)


## Remove rock `i` for good: mark it dead, take its collision circle out
## of the physics world, redraw its chunk and send rock_destroyed. Does
## nothing if it is already gone.
func destroy(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	# An empty RID() means "in no physics space": nothing can hit it now.
	PhysicsServer2D.body_set_space(bodies[i], RID())
	var key := Vector2i(int(pos[i].x / CHUNK), int(pos[i].y / CHUNK))
	if chunks.has(key):
		(chunks[key] as AsteroidFieldChunk).queue_redraw()
	rock_destroyed.emit(i)


## When the field leaves the scene, hand every physics body and shape back
## to the physics engine (they are not freed by themselves).
func _exit_tree() -> void:
	for b in bodies:
		PhysicsServer2D.free_rid(b)
	for s in shapes:
		PhysicsServer2D.free_rid(s)
	bodies.clear()
	shapes.clear()
