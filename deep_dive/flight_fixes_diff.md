# Code changes in the flight copy vs main (scripts only; tests listed at the end)

## scripts\ai\pilot_ai.gd

```diff
--- main/scripts\ai\pilot_ai.gd
+++ copy/scripts\ai\pilot_ai.gd
@@ -136,4 +136,8 @@
 ## reports it.
 var home_reason := ""
+## DEEP-DIVE fix I: a target we gave up on because it stayed hidden behind
+## rocks: its instance id, and the game time until which we ignore it.
+var skip_id := 0
+var skip_until := 0.0
 
 # --- the parts (see THE PARTS at the top) ----------------------------------------------
```

## scripts\ai\pilot_combat.gd

```diff
--- main/scripts\ai\pilot_combat.gd
+++ copy/scripts\ai\pilot_combat.gd
@@ -105,4 +105,5 @@
 	var c := ship.controls
 	var target := brain.target
+	brain.flight.dbg = ""
 	# Step 1: where the target is. For a mothership, the closest point on
 	# its spine (the line from bow to stern).
@@ -140,5 +141,10 @@
 			hold = tp + (ship.global_position - tp).normalized() * reach * 0.75
 		brain.flight.travel(ship, hold, 200.0)
-		c.face_point = tp
+		# Fix D: far from the hold point, keep travel()'s nose (its thrust was
+		# worked out for it) and let the turrets aim; the ion frigate's beam
+		# is fixed, so it turns to the target once the target is in reach.
+		var far_hold := ship.global_position.distance_to(hold) > 500.0
+		if not (brain.flight.ff("D") and far_hold and (ship.hull_id != "ion" or d > reach + target.radius)):
+			c.face_point = tp
 		c.fire = d < reach + target.radius
 		# Use the special in reach (a logistics ship saves its emergency
@@ -147,4 +153,28 @@
 		if ship.special_ready() and d < reach:
 			c.special = ship.hull_id != "logistics" or ship.hull_frac() < 0.7
+		return
+	# Fix I: a target hidden behind rocks: hold fire (no shots into the rock),
+	# and once it has stayed hidden for 3 s give it up for 6 s (the brain
+	# picks another target, or goes back to its station).
+	var hidden := false
+	if brain.flight.ff("I"):
+		hidden = brain.flight.target_hidden(ship, tp)
+		if hidden and brain.flight.hidden_t > 3.0:
+			brain.skip_id = target.get_instance_id()
+			brain.skip_until = brain.world.time + 6.0
+			brain.target = null
+			brain.lock_target = null
+			brain.flight.hidden_t = 0.0
+			brain.flight.dbg = "i_drop"
+			brain.flight.dbg_drops += 1
+			brain.flight.travel(ship, brain.goal, 160.0)
+			c.aim_point = c.face_point
+			return
+	# Fix H: strike craft whose straight line to the target hits rocks
+	# follow the route to it instead of grinding on the rocks between.
+	if brain.flight.ff("H") and brain.flight.target_line_blocked(ship, tp):
+		brain.flight.dbg = "h"
+		brain.flight.travel(ship, tp, 300.0)
+		c.aim_point = aim
 		return
 	# How far (in radians) the nose is from the aim point.
@@ -205,4 +235,10 @@
 			if ship.hull_id == "scout":
 				c.special = ship.special_ready() and d < 1500.0
+	# Fix I: no shots into the rock between us and the target.
+	if hidden:
+		brain.flight.dbg_holds += 1
+		c.fire = false
+		if ship.hull_id == "bomber":
+			c.special = false
 	# Step 4: don't fly into rocks while dogfighting (PilotFlight).
 	brain.flight.avoid_rocks(ship)
```

## scripts\ai\pilot_flight.gd

```diff
--- main/scripts\ai\pilot_flight.gd
+++ copy/scripts\ai\pilot_flight.gd
@@ -57,4 +57,51 @@
 ## A reusable list that the asteroid field fills with nearby rock numbers.
 var _rocks := PackedInt32Array()
+## DEEP-DIVE fix switches (--ff=<letters>): A route when the straight line
+## is blocked, E brake the right way in avoid_rocks, H strike craft route to
+## a target behind rocks, D big ships fly to a far hold point.
+var _ff := ""
+## Straight-line cache for travel() (fix A) and fight() (fix H): calls until
+## the next check, the point last checked, and the answer.
+var _line_t := 0
+var _line_goal := Vector2.INF
+var _line_blocked := false
+var _tline_t := 0
+var _tline_goal := Vector2.INF
+var _tline_blocked := false
+## Fix I: seconds the current target has been hidden behind rocks (0 once it
+## has been in the clear for half a second), and the cache of the check.
+var hidden_t := 0.0
+var _hid_t := 0
+var _hid_goal := Vector2.INF
+var _hid := false
+var _hid_clear := 0
+## Fix U (get out of a rock pocket): the escape waypoints, which one we fly
+## to, the seconds left to follow them, and where and when the stuck timer
+## last fired (a second fire nearby plans an escape).
+var _esc := PackedVector2Array()
+var _esc_i := 0
+var _esc_t := 0.0
+var _esc_dot := Vector2.INF
+var _esc_goal := Vector2.INF
+var _esc_best := INF
+var _esc_np := 0.0
+var _unst_cool := 0.0
+var _crumbs := PackedVector2Array()
+var _esc_replan := false
+var _unst_n := 0
+var _unst_p := Vector2.INF
+var _unst_at := -999.0
+## PROBE FIELDS (read by tests/fl_audit.gd, they change nothing): what
+## fight() chose on its last call ("" = plain fight, "h" = fix H routing),
+## how many routes travel() has planned, and how often it fired the unstick.
+var dbg := ""
+var dbg_plans := 0
+var dbg_unsticks := 0
+var dbg_escapes := 0
+var dbg_drops := 0
+var dbg_holds := 0
+var dbg_escape_fail := 0
+var dbg_escape_abort := 0
+var dbg_escape_us := 0
 
 
@@ -62,4 +109,41 @@
 func _init(owner: PilotAI) -> void:
 	_ai_ref = weakref(owner)
+	_ff = str(Game.opt("ff", ""))
+
+
+## Fix switch `ch` on?
+func ff(ch: String) -> bool:
+	return _ff.contains(ch)
+
+
+## Fix H: is the straight line from the ship to `to` blocked by rocks?
+## Checked about 4 times a second (or when `to` moves 150).
+func target_line_blocked(ship: Ship, to: Vector2) -> bool:
+	_tline_t -= 1
+	if _tline_t <= 0 or to.distance_to(_tline_goal) > 150.0:
+		_tline_t = 15
+		_tline_goal = to
+		_tline_blocked = not ai.world.asteroids.segment_hit(ship.global_position, to, ship.radius + 8.0).is_empty()
+	return _tline_blocked
+
+
+## Fix I: is the target hidden, i.e. does a rock stop a shot flying straight
+## from the ship to `to`? Checked about 4 times a second (or when `to` moves
+## 150); called once per tick while fighting, which also times how long the
+## target has been hidden (hidden_t).
+func target_hidden(ship: Ship, to: Vector2) -> bool:
+	_hid_t -= 1
+	if _hid_t <= 0 or to.distance_to(_hid_goal) > 150.0:
+		_hid_t = 15
+		_hid_goal = to
+		_hid = ai.world.asteroids.segment_blocked(ship.global_position, to)
+	if _hid:
+		hidden_t += 1.0 / 60.0
+		_hid_clear = 0
+	else:
+		_hid_clear += 1
+		if _hid_clear > 30:
+			hidden_t = 0.0
+	return _hid
 
 
@@ -74,11 +158,28 @@
 	var p := ship.global_position
 	var waypoint := to
+	# Fix U: while an escape path is on, follow it and nothing else.
+	if _esc_t > 0.0 and _follow_escape(ship):
+		return
+	if ff("V") and (_crumbs.is_empty() or p.distance_to(_crumbs[_crumbs.size() - 1]) > 80.0):
+		_crumbs.append(p)
+		if _crumbs.size() > 24:
+			_crumbs.remove_at(0)
 	# Step 1: long trips (over 2,500) or anywhere off the open lanes follow
 	# a route. Plan a new one when we have none or the goal moved over 600.
-	if p.distance_to(to) > 2500.0 or not world.map.in_open_lane(p):
+	var use_route := p.distance_to(to) > 2500.0 or not world.map.in_open_lane(p)
+	if not use_route and ff("A"):
+		# Fix A: a short hop whose straight line hits rocks routes too.
+		_line_t -= 1
+		if _line_t <= 0 or to.distance_to(_line_goal) > 150.0:
+			_line_t = 15
+			_line_goal = to
+			_line_blocked = not world.asteroids.segment_hit(p, to, ship.radius + 8.0).is_empty()
+		use_route = _line_blocked
+	if use_route:
 		if brain.path_goal == Vector2.INF or brain.path_goal.distance_to(to) > 600.0 or brain.path.is_empty():
 			brain.path = world.map.route.path(p, to, ship.is_small())
 			brain.path_i = 0
 			brain.path_goal = to
+			dbg_plans += 1
 		if not brain.path.is_empty():
 			# Thread jungle gates (86 wide) precisely: near or in the jungle,
@@ -90,4 +191,10 @@
 			if not world.map.in_open_lane(p) or not world.map.in_open_lane(brain.path[nxt]):
 				reach = 110.0
+				# Fix X: a bomber turns at 1.15 rad/s; at its jungle speed of 260
+				# its turning circle is 226 units across, so a 110-unit reach can
+				# never be hit and it circles every waypoint. Reach within the
+				# turning radius (at most 300) instead.
+				if ff("X") and ship.f_turn < 2.0:
+					reach = clampf(ship.f_max * 0.65 / ship.f_turn, 110.0, 300.0)
 			brain.path_i = Steer.advance(brain.path, brain.path_i, p, reach)
 			# Head for the current waypoint (on the last leg we fly
@@ -121,6 +228,11 @@
 			_stuck_t = 0.0
 			_unstick_t = 1.0
+			dbg_unsticks += 1
+			if ff("U"):
+				_note_unstick(ship, to)
 			brain.path = PackedVector2Array()
 			brain.path_goal = Vector2.INF
+			if _esc_t > 0.0:
+				_unstick_t = 0.0
 	# Step 4: how far off the nose is, how fast we're closing, and how far
 	# we'd slide while braking (stopping distance = speed^2 / (2 x braking
@@ -163,5 +275,45 @@
 	if in_jungle and ship.velocity.length() > ship.f_max * (0.55 + 0.15 * brain.skill):
 		c.forward = minf(c.forward, 0.0 if err < 0.4 else -0.4)
+	# Fix O: slow down before a sharp corner of the route or the entry into the
+	# jungle (a gate). A ship coming down a lane at boost speed (about 1,000
+	# units a second) cannot turn through a gate: its turning circle is 300
+	# units wide, so it swings wide of the gate and rams the wall beside it.
+	# (Every match the first jungler crashes at the same notch next to a gate
+	# 13 s after launch.) The corner speed is 28-45% of top speed, and braking
+	# starts early enough (braking power 80% of the reverse thrusters).
+	if ff("O") and use_route and brain.path_i < brain.path.size() - 1:
+		var after: Vector2 = brain.path[brain.path_i + 1]
+		var v_in := (waypoint - p).normalized()
+		var v_out := (after - waypoint).normalized()
+		var turn := acos(clampf(v_in.dot(v_out), -1.0, 1.0))
+		var to_jungle := not world.map.in_open_lane(after) and world.map.in_open_lane(waypoint)
+		# How far along the route is the first waypoint inside the jungle (the
+		# far side of a gate)? Within 1,000 of it, fly the gate approach slowly.
+		var gate_d := INF
+		if world.map.in_open_lane(p):
+			var acc := dist
+			for k in range(brain.path_i, brain.path.size()):
+				if k > brain.path_i:
+					acc += brain.path[k - 1].distance_to(brain.path[k])
+				if not world.map.in_open_lane(brain.path[k]):
+					gate_d = acc
+					break
+		var v_cap := INF
+		if turn > 0.7 or to_jungle:
+			v_cap = maxf(120.0, ship.f_max * (0.28 if (turn > 1.2 or to_jungle) else 0.45))
+		if gate_d < 1000.0:
+			v_cap = minf(v_cap, ship.f_max * 0.38)
+		var v_now := ship.velocity.length()
+		if v_now > v_cap:
+			# Distance to the point where the cap applies: the corner (turn) or
+			# 1,000 before the gate's far side.
+			var cap_d := dist if (turn > 0.7 or to_jungle) else maxf(0.0, gate_d - 800.0)
+			var need := (v_now * v_now - v_cap * v_cap) / (2.0 * rev * 0.8)
+			if cap_d < need + 120.0 or gate_d < 800.0:
+				c.forward = minf(c.forward, -0.8 if v_now > v_cap * 1.3 else 0.0)
+				c.boost = false
 	# Step 8: steer around rocks just ahead.
+	if ff("N") and use_route and brain.path_i < brain.path.size() - 1 and world.map.in_open_lane(p) and not world.map.in_open_lane(brain.path[brain.path_i + 1]):
+		return
 	avoid_rocks(ship)
 
@@ -206,3 +358,300 @@
 		c.strafe = clampf(c.strafe + port.dot(s) * 1.5, -1.0, 1.0)
 		if ship.velocity.normalized().dot(-s) > 0.6:
-			c.forward = minf(c.forward, -0.3)
+			if ff("E") and ship.velocity.dot(Vector2.from_angle(ship.rotation)) < 0.0:
+				# Fix E: sliding tail-first into the rock: brake with the
+				# main engine, not the reverse thrusters.
+				c.forward = maxf(c.forward, 0.3)
+			else:
+				c.forward = minf(c.forward, -0.3)
+
+
+## Fix U: the stuck timer just fired. Count fires that happen close together
+## in time (25 s) and place (300 units); the second one plans a way out of
+## the pocket (the plain unstick, back off and plan the same route again,
+## brings a ship back into the same notch for ever). `to` is the final goal.
+func _note_unstick(ship: Ship, to: Vector2) -> void:
+	var now := ai.world.time
+	var p := ship.global_position
+	if now - _unst_at < 25.0 and p.distance_to(_unst_p) < 300.0:
+		_unst_n += 1
+	else:
+		_unst_n = 1
+	_unst_at = now
+	_unst_p = p
+	if _unst_n >= 2 and now >= _unst_cool:
+		var t0 := Time.get_ticks_usec()
+		_plan_escape(ship, to)
+		dbg_escape_us += Time.get_ticks_usec() - t0
+
+
+## Fix U: plan a way out of the rocks around the ship. A grid of small
+## cells (about the ship's size) is laid over the square around it (1,400
+## wide, or 2,200 in the rock fields where the route dots are far); a cell
+## is blocked when a rock, grown by the ship's radius, covers its centre. A
+## breadth-first search floods the free cells from the ship's cell, nearest
+## first, until it reaches a cell with a clear straight line to one of the 8
+## nearest route dots (or to the goal itself). The path to that cell is
+## pulled tight into a few waypoints (_esc); when it is flown, the route is
+## planned again FROM that dot (the graph alone enters at the nearest dot
+## in sight, which can lie on the far side of a rock wall: the ship presses
+## against the wall for ever, or is led back into the same notch). With no
+## such cell it goes to the farthest cell reached. Costs about a tenth of a
+## second and only runs when a ship is stuck for the second time.
+func _plan_escape(ship: Ship, to: Vector2, fine := false, no_retrace := false) -> void:
+	var world := ai.world
+	var field := world.asteroids
+	var p := ship.global_position
+	var route := world.map.route
+	var small := ship.is_small()
+	# The 8 nearest dots we may use, nearest first, then the goal.
+	var order: Array = []
+	for k in route.pos.size():
+		if small or route.jungle[k] == 0:
+			order.append([p.distance_squared_to(route.pos[k]), k])
+	order.sort_custom(func(x, y): return x[0] < y[0])
+	var cands := PackedVector2Array()
+	for k in mini(8, order.size()):
+		cands.append(route.pos[order[k][1]])
+	cands.append(to)
+	var half := 1100.0
+	var cs := clampf(maxf(ship.radius * 1.2, half / 100.0), 12.0, 40.0)
+	var grow := ship.radius + 4.0
+	if fine:
+		# Second try, for a tight notch: small cells and almost no margin.
+		half = 500.0
+		cs = 6.0
+		grow = ship.radius + 0.4
+	var n := int(2.0 * half / cs)
+	var o := p - Vector2(half, half)
+	# Step 1: the blocked cells.
+	var blocked := PackedByteArray()
+	blocked.resize(n * n)
+	field.nearby(p, half * 1.5, _rocks)
+	for r in _rocks:
+		var rc := field.pos[r]
+		var rr := field.rad[r] * 0.95 + grow
+		if absf(rc.x - p.x) > half + rr or absf(rc.y - p.y) > half + rr:
+			continue
+		var j0 := maxi(0, int((rc.y - rr - o.y) / cs))
+		var j1 := mini(n - 1, int((rc.y + rr - o.y) / cs))
+		for j in range(j0, j1 + 1):
+			var dy := o.y + (float(j) + 0.5) * cs - rc.y
+			var rem := rr * rr - dy * dy
+			if rem <= 0.0:
+				continue
+			var dx := sqrt(rem)
+			var ia := maxi(0, int(ceil((rc.x - dx - o.x) / cs - 0.5)))
+			var ib := mini(n - 1, int(floor((rc.x + dx - o.x) / cs - 0.5)))
+			for i in range(ia, ib + 1):
+				blocked[j * n + i] = 1
+	# Step 2: the start cell, and a free disc around it (a ship pressed
+	# against a rock sits inside the grown rock by a few units).
+	var si := clampi(int((p.x - o.x) / cs), 0, n - 1)
+	var sj := clampi(int((p.y - o.y) / cs), 0, n - 1)
+	for j in range(maxi(0, sj - 3), mini(n, sj + 4)):
+		for i in range(maxi(0, si - 3), mini(n, si + 4)):
+			blocked[j * n + i] = 0
+	# Step 3: flood the free cells, nearest first, and test every third cell
+	# for a clear line to a wanted point.
+	var came := PackedInt32Array()
+	came.resize(n * n)
+	came.fill(-2)
+	var queue := PackedInt32Array()
+	queue.resize(n * n)
+	var s_idx := sj * n + si
+	var head := 0
+	var tail := 1
+	queue[0] = s_idx
+	came[s_idx] = -1
+	var found := -1
+	var found_dot := Vector2.INF
+	var last := s_idx
+	var k_test := 0
+	var dxs := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
+	var dys := PackedInt32Array([0, 0, 1, -1, 1, -1, 1, -1])
+	while head < tail and found < 0:
+		var cur := queue[head]
+		head += 1
+		last = cur
+		var ci := cur % n
+		var cj := cur / n
+		var cc := o + Vector2((float(ci) + 0.5) * cs, (float(cj) + 0.5) * cs)
+		if cur != s_idx and cc.distance_squared_to(p) > 10000.0:
+			k_test += 1
+			if k_test % 3 == 0:
+				for q in cands:
+					if field.segment_hit(cc, q, ship.radius + 10.0).is_empty():
+						found = cur
+						found_dot = q
+						break
+				if found >= 0:
+					break
+		for k in 8:
+			var ni := ci + dxs[k]
+			var nj := cj + dys[k]
+			if ni < 0 or nj < 0 or ni >= n or nj >= n:
+				continue
+			var nb := nj * n + ni
+			if came[nb] != -2 or blocked[nb] == 1:
+				continue
+			# No cutting corners on a diagonal step.
+			if k >= 4 and (blocked[cj * n + ni] == 1 or blocked[nj * n + ci] == 1):
+				continue
+			came[nb] = cur
+			queue[tail] = nb
+			tail += 1
+	if found < 0:
+		found = last
+	var fc := o + Vector2((float(found % n) + 0.5) * cs, (float(found / n) + 0.5) * cs)
+	if found == s_idx or fc.distance_to(p) < 120.0:
+		if not fine:
+			_plan_escape(ship, to, true, no_retrace)
+		elif ff("V") and not no_retrace and _retrace(ship, to):
+			pass
+		else:
+			dbg_escape_fail += 1
+		return
+	# Step 4: walk back from the goal cell to the start, then pull the cell
+	# path tight: from each point jump to the farthest later cell that can be
+	# reached in a straight line over free cells.
+	var cells := PackedInt32Array()
+	var cur2 := found
+	while cur2 != -1:
+		cells.append(cur2)
+		cur2 = came[cur2]
+	cells.reverse()
+	var pts := PackedVector2Array()
+	var a := 0
+	while a < cells.size() - 1:
+		var b := cells.size() - 1
+		while b > a + 1 and not _grid_line_free(blocked, n, cells[a], cells[b]):
+			b -= 1
+		pts.append(o + Vector2((float(cells[b] % n) + 0.5) * cs, (float(cells[b] / n) + 0.5) * cs))
+		a = b
+	_esc = pts
+	_esc_i = 0
+	_esc_t = 14.0 + 0.012 * fc.distance_to(p)
+	_esc_dot = found_dot
+	_esc_goal = to
+	_esc_best = INF
+	_esc_np = 0.0
+	dbg_escapes += 1
+
+
+## Fix U: the grid search found no way out (the ship is wedged between rocks:
+## the room it has left is thinner than a grid cell). It did get in, though,
+## so back out the way it came: fly its last positions (_crumbs, one every
+## 80 units) in reverse until about 450 units are covered, then plan again
+## from there (a free spot). Returns false when there is no trail.
+func _retrace(ship: Ship, to: Vector2) -> bool:
+	var p := ship.global_position
+	var pts := PackedVector2Array()
+	var total := 0.0
+	var last := p
+	for k in range(_crumbs.size() - 1, -1, -1):
+		var q := _crumbs[k]
+		if q.distance_to(p) < 100.0:
+			continue
+		pts.append(q)
+		total += last.distance_to(q)
+		last = q
+		if total > 450.0:
+			break
+	if pts.is_empty():
+		return false
+	_esc = pts
+	_esc_i = 0
+	_esc_t = 12.0
+	_esc_dot = Vector2.INF
+	_esc_goal = to
+	_esc_best = INF
+	_esc_np = 0.0
+	_esc_replan = true
+	dbg_escapes += 1
+	return true
+
+
+## Fix U: are all grid cells on the straight line between cells `a` and `b`
+## free?
+func _grid_line_free(blocked: PackedByteArray, n: int, a: int, b: int) -> bool:
+	var x0 := a % n
+	var y0 := a / n
+	var x1 := b % n
+	var y1 := b / n
+	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
+	for s in range(1, steps):
+		var x := x0 + int(round(float(x1 - x0) * float(s) / float(steps)))
+		var y := y0 + int(round(float(y1 - y0) * float(s) / float(steps)))
+		if blocked[y * n + x] == 1:
+			return false
+	return true
+
+
+## Fix U: fly the escape path slowly and exactly. Returns false (and plans
+## the route again) when it is finished, timed out or no longer makes sense.
+func _follow_escape(ship: Ship) -> bool:
+	var brain := ai
+	var c := ship.controls
+	var p := ship.global_position
+	_esc_t -= 1.0 / 60.0
+	var reach := maxf(35.0, ship.radius * 2.0)
+	while _esc_i < _esc.size() and p.distance_to(_esc[_esc_i]) < reach:
+		_esc_i += 1
+		_esc_best = INF
+		_esc_np = 0.0
+	if _esc_i >= _esc.size() or _esc_t <= 0.0 or p.distance_to(_esc[_esc_i]) > 900.0:
+		var done := _esc_i >= _esc.size()
+		_esc = PackedVector2Array()
+		_esc_t = 0.0
+		if done and _esc_replan:
+			# We backed out of a wedge along our own crumbs: plan properly from
+			# the free spot we are at now.
+			_esc_replan = false
+			_unst_cool = 0.0
+			var goal := _esc_goal
+			_plan_escape(ship, goal, false, true)
+			if _esc_t > 0.0:
+				return true
+		if done and _esc_dot != Vector2.INF:
+			# Plan the rest of the way from the dot we were led to.
+			brain.path = brain.world.map.route.path(_esc_dot, _esc_goal, ship.is_small())
+			brain.path_i = 0
+			brain.path_goal = _esc_goal
+		else:
+			brain.path = PackedVector2Array()
+			brain.path_goal = Vector2.INF
+		_stuck_t = 0.0
+		_prog_wp = Vector2.INF
+		return false
+	var wp := _esc[_esc_i]
+	# No progress toward this waypoint for 2 s: the path cannot be flown (a
+	# gap too tight for the real ship). Give up and let the plain unstick run;
+	# no new escape for 15 s.
+	var dwp := p.distance_to(wp)
+	if dwp < _esc_best - 15.0:
+		_esc_best = dwp
+		_esc_np = 0.0
+	else:
+		_esc_np += 1.0 / 60.0
+		if _esc_np > 2.0:
+			_esc = PackedVector2Array()
+			_esc_t = 0.0
+			_esc_best = INF
+			_esc_np = 0.0
+			_unst_cool = brain.world.time + 15.0
+			brain.path = PackedVector2Array()
+			brain.path_goal = Vector2.INF
+			dbg_escape_fail += 1
+			dbg_escape_abort += 1
+			return false
+	var err := absf(Util.ang_diff(ship.rotation, (wp - p).angle()))
+	var speed := ship.velocity.length()
+	var fwd := 0.45 if err < 0.5 else (0.1 if err < 1.2 else 0.0)
+	if speed > 170.0:
+		fwd = minf(fwd, -0.4 if speed > 260.0 else 0.0)
+	c.face_point = wp
+	c.forward = fwd
+	var lat := ship.velocity.dot(Util.starboard_of(ship.rotation))
+	c.strafe = clampf(lat / 80.0, -1.0, 1.0) if err < 0.5 else 0.0
+	c.boost = false
+	return true
```

## scripts\ai\pilot_goals.gd

```diff
--- main/scripts\ai\pilot_goals.gd
+++ copy/scripts\ai\pilot_goals.gd
@@ -278,5 +278,6 @@
 	if brain.camp != null:
 		brain.goal = brain.camp.global_position + (ship.global_position - brain.camp.global_position).normalized() * 450.0
-		if brain.target == null and ship.global_position.distance_to(brain.camp.global_position) < 1200.0:
+		if brain.target == null and ship.global_position.distance_to(brain.camp.global_position) < 1200.0 \
+				and not (brain.skip_id != 0 and brain.camp.get_instance_id() == brain.skip_id and brain.world.time < brain.skip_until):
 			brain.target = brain.camp
 	else:
```

## scripts\ai\pilot_targeting.gd

```diff
--- main/scripts\ai\pilot_targeting.gd
+++ copy/scripts\ai\pilot_targeting.gd
@@ -85,4 +85,7 @@
 			continue
 		if u.team == Rules.NEUTRAL and brain.state != "jungle":
+			continue
+		# Fix I: a target given up on (hidden behind rocks) waits 6 s.
+		if brain.skip_id != 0 and u.get_instance_id() == brain.skip_id and world.time < brain.skip_until:
 			continue
 		if not u.visible_to(ship.team):
@@ -170,4 +173,6 @@
 		if not t.alive or t.team == ship.team or t.team == Rules.NEUTRAL or not t.is_built():
 			continue
+		if brain.skip_id != 0 and t.get_instance_id() == brain.skip_id and world.time < brain.skip_until:
+			continue
 		var d := station.distance_to(t.global_position)
 		if d > bd:
@@ -209,4 +214,6 @@
 			continue
 		if not u.visible_to(ship.team):
+			continue
+		if brain.skip_id != 0 and u.get_instance_id() == brain.skip_id and brain.world.time < brain.skip_until:
 			continue
 		# Step 3: close to us, close to our station, not under a turret
```

## scripts\core\route_graph.gd

```diff
--- main/scripts\core\route_graph.gd
+++ copy/scripts\core\route_graph.gd
@@ -61,4 +61,10 @@
 		return
 	var cost := pos[a].distance_to(pos[b])
+	# Fix R (--ff=R): a jungle link costs its flying TIME, about twice its
+	# length: ships fly the jungle at 62-69% of top speed without boost, and
+	# the lanes at up to 1.4 times top speed, so a jungle shortcut is only
+	# faster when it saves more than half the way.
+	if small_only and str(Game.opt("ff", "")).contains("R"):
+		cost *= 2.0
 	(adj[a] as Array).append([b, small_only, cost])
 	(adj[b] as Array).append([a, small_only, cost])
```

## scripts\world\asteroid_field.gd

```diff
--- main/scripts\world\asteroid_field.gd
+++ copy/scripts\world\asteroid_field.gd
@@ -220,2 +220,62 @@
 	bodies.clear()
 	shapes.clear()
+
+
+## DEEP-DIVE fix M (--ff=M): seal the rock gaps a ship can wedge itself in.
+## A gap between two rocks that is 18 to 34 units wide is just about the width
+## of a fighter (24 across) or a lance (26): the pilot code flies straight at
+## its next waypoint, the line leads through such a gap, the ship slides in
+## and sticks between the two rocks (it touches both), and the stuck handling
+## (reverse, plan the same route again) cannot get it out: it sits there for
+## the rest of the match. Every stuck position recorded in 122 match logs
+## touches two rocks within 1 unit. seal_tight_gaps() grows both rocks of
+## every such pair until the gap is 17 (a scout, 18 across, no longer fits),
+## in up to 4 sweeps because growing a rock narrows its other gaps. About
+## 460 gaps and 720 rocks change by 6.5 units on average (25 at most); no
+## route link, no gate choke (101) and no ore rock is touched.
+const TIGHT_LO := 17.5
+const TIGHT_HI := 34.0
+const TIGHT_TARGET := 17.0
+
+
+## Fix M: grow rocks until no gap between two ordinary rocks is 17.5 to 34 wide.
+func seal_tight_gaps() -> int:
+	var tmp := PackedInt32Array()
+	var sealed := 0
+	for sweep in 4:
+		var n := 0
+		for i in pos.size():
+			if alive[i] == 0 or node_rock[i] == 1:
+				continue
+			nearby(pos[i], rad[i] + 300.0, tmp)
+			for j in tmp:
+				if j <= i or alive[j] == 0 or node_rock[j] == 1:
+					continue
+				var gap := pos[i].distance_to(pos[j]) - 0.95 * (rad[i] + rad[j])
+				if gap > TIGHT_LO and gap < TIGHT_HI:
+					var grow := (gap - TIGHT_TARGET) / (2.0 * 0.95)
+					_resize(i, rad[i] + grow)
+					_resize(j, rad[j] + grow)
+					n += 1
+		sealed += n
+		if n == 0:
+			break
+	# The clear-space map is built on first use: make sure it sees the new sizes.
+	queries._clear = PackedFloat32Array()
+	for key in chunks:
+		(chunks[key] as AsteroidFieldChunk).queue_redraw()
+	return sealed
+
+
+## Fix M: give rock `i` the radius `r1` (collision circle, outline, search grid).
+func _resize(i: int, r1: float) -> void:
+	var r0 := rad[i]
+	rad[i] = r1
+	PhysicsServer2D.shape_set_data(shapes[i], r1 * 0.95)
+	var poly: PackedVector2Array = outline[i]
+	for k in poly.size():
+		poly[k] *= r1 / r0
+	outline[i] = poly
+	# Filed again so the squares the bigger rock now reaches list it (a rock may
+	# stand in a square twice; the searches count each rock once).
+	queries.add_rock(i, pos[i], r1)
```

## scripts\world\map_builder_route.gd

```diff
--- main/scripts\world\map_builder_route.gd
+++ copy/scripts\world\map_builder_route.gd
@@ -72,15 +72,28 @@
 	var ctotal := Util.polyline_length(info.connector)
 	var csteps := int(ceil(ctotal / MapBuilder.LANE_NODE_STEP))
-	var cprev := -1
+	var cprev: Array = []
+	var fix_b := str(Game.opt("ff", "")).contains("B")
 	for k in csteps + 1:
 		var p := Util.polyline_at(info.connector, ctotal * float(k) / float(csteps))
-		var nid := _node_at(g, by_pos, p, false)
-		if cprev >= 0:
-			g.connect_nodes(cprev, nid, false)
-		cprev = nid
-		# Tie into any lane dot close by (within 1.1 times LANE_NODE_STEP).
-		for ln: int in lane_nodes:
-			if g.pos[ln].distance_to(p) < MapBuilder.LANE_NODE_STEP * 1.1 and ln != nid:
-				g.connect_nodes(ln, nid, false)
+		# Fix B: a connector dot inside an ore node's field (The Crossing sits
+		# on the connector) becomes two dots, one each side of the field.
+		var group: Array = [p]
+		if fix_b:
+			for nd: Dictionary in info.nodes:
+				var np: Vector2 = nd["pos"]
+				if p.distance_to(np) < MapLayout.NODE_RADIUS + 300.0:
+					group = [Vector2(np.x - 1050.0, p.y), Vector2(np.x + 1050.0, p.y)]
+					break
+		var ids: Array = []
+		for q: Vector2 in group:
+			var nid := _node_at(g, by_pos, q, false)
+			ids.append(nid)
+			for a: int in cprev:
+				g.connect_nodes(a, nid, false)
+			# Tie into any lane dot close by (within 1.1 times LANE_NODE_STEP).
+			for ln: int in lane_nodes:
+				if g.pos[ln].distance_to(q) < MapBuilder.LANE_NODE_STEP * 1.1 and ln != nid:
+					g.connect_nodes(ln, nid, false)
+		cprev = ids
 	# Step 4: jungle entrances (both halves). A lane dot at the entrance,
 	# linked to the nearest lane dot; then a jungle dot just inside, linked
```

## scripts\world\world_setup.gd

```diff
--- main/scripts\world\world_setup.gd
+++ copy/scripts\world\world_setup.gd
@@ -45,4 +45,6 @@
 	w.asteroids = w.get_node("Asteroids")
 	w.asteroids.build(w.map)
+	if str(Game.opt("ff", "")).contains("M"):
+		print("fix M: sealed %d tight rock gaps" % w.asteroids.seal_tight_gaps())
 	# The map's route finder asks this whether a straight hop from a to b
 	# misses every rock (with 16 world units to spare).
```

## New test files

- tests\ab_audit.gd
- tests\escape_bench.gd
- tests\fl_audit.gd
- tests\gap_check.gd
- tests\map_dump.gd
- tests\wall_duel.gd
