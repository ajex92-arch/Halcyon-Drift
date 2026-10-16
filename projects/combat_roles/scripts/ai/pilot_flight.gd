class_name PilotFlight
extends RefCounted
## WHAT THIS IS: how an AI pilot flies its ship to a point (a part of
## PilotAI): follow a route around the asteroids, slow down so we arrive
## without overshooting, get unstuck when pinned on a rock, and nudge away
## from rocks and mothership hulls just ahead.
##
## HOW IT WORKS:
##   - travel(): for long trips (or when we're off the open lanes, or when
##     a rock is in the way of the straight line) ask the map's route graph
##     (a network of safe paths, with jungle paths only for strike craft)
##     for a list of waypoints (stepping-stone points along the way), and
##     fly to them one by one.
##     Point the nose at the next waypoint, thrust when lined up, and brake
##     when we would overshoot the end. Slow down before a sharp corner of
##     the route and before a jungle gate, so we do not swing wide into the
##     wall. If we make no real progress for 4 seconds, back off for a
##     second and plan again; if that happens twice in the same place,
##     PilotEscape plans a way out of the rock pocket.
##   - avoid_rocks(): look a little ahead of where we're going; if that spot
##     is inside a rock, turn and slide away from it (and brake if we're
##     heading straight in). It starts with avoid_hulls(): a ship about to
##     run into a mothership hull (the route knows only rocks) slides along
##     the hull instead of pinning itself against it.
##   - target_hidden(): is a rock between us and the target? PilotCombat
##     asks it so that nobody shoots into a rock.
##
## WHO USES IT: PilotCombat (steer and fight call travel, avoid_rocks and
## target_hidden). It reads the route graph (world.map.route), the
## asteroid field (world.asteroids) and the motherships' hulls
## (World.mothership(), Mothership.hull_dist; avoid_hulls), and makes a
## PilotEscape part for the rock pockets. The planned route itself lives on the brain
## (PilotAI.path, path_i, path_goal) because tests read it.
##
## Timing note: the stuck timers here count 1/60 of a second per call:
## travel() is called at most once per tick, and the game runs 60 ticks a
## second. (Ticks where we dogfight instead don't count.)
## Angles are in radians ("rad"): 0.1 rad is about 6 degrees, 1 rad about
## 57 degrees.

## The pilot brain this part belongs to (we read its goal, skill and orbit,
## and keep its route). It is reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef
## Seconds without real progress toward the current waypoint.
var _stuck_t := 0.0
## Seconds left backing off to get unstuck (0 = not unsticking).
var _unstick_t := 0.0
## The waypoint we are measuring progress toward (INF = none yet).
var _prog_wp := Vector2.INF
## The closest we have come to that waypoint so far (world units).
var _prog_best := INF
## Calls until the next rock check (we look for rocks on every 5th call,
## about 12 times a second, because it's the costliest part of steering).
var _rock_t := 0
## The push away from rocks found by the last rock check (reused between
## checks).
var _rock_push := Vector2.ZERO
## A reusable list that the asteroid field fills with nearby rock numbers.
var _rocks := PackedInt32Array()
## Calls until travel() checks again whether a rock blocks the straight line
## to the goal (about 4 times a second).
var _line_t := 0
## The goal that the last straight-line check was made for.
var _line_goal := Vector2.INF
## The answer of the last straight-line check: true = a rock is in the way.
var _line_blocked := false
## Seconds the current target has been hidden behind rocks (it restarts from
## 0 once the target has been in the clear for half a second).
var hidden_t := 0.0
## Calls until target_hidden() checks again (about 4 times a second).
var _hid_t := 0
## The target position that the last hidden check was made for.
var _hid_goal := Vector2.INF
## The answer of the last hidden check: true = a rock stops a shot.
var _hid := false
## How many calls in a row the target has been in the clear.
var _hid_clear := 0
## The part that gets the ship out of rock pockets (see PilotEscape).
var escape: PilotEscape


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)
	escape = PilotEscape.new(owner)


## Start measuring progress afresh (the stuck timer and the waypoint it
## watches). PilotEscape calls it when an escape path ends.
func reset_progress() -> void:
	_stuck_t = 0.0
	_prog_wp = Vector2.INF


## Is the target hidden, i.e. does a rock stop a shot flying straight from
## the ship to `to`? Checked about 4 times a second (or when `to` moves 150
## units); called once per tick while fighting, which also times how long
## the target has been hidden (hidden_t).
func target_hidden(ship: Ship, to: Vector2) -> bool:
	_hid_t -= 1
	if _hid_t <= 0 or to.distance_to(_hid_goal) > 150.0:
		_hid_t = 15
		_hid_goal = to
		_hid = ai.world.asteroids.segment_blocked(ship.global_position, to)
	if _hid:
		hidden_t += 1.0 / 60.0
		_hid_clear = 0
	else:
		_hid_clear += 1
		if _hid_clear > 30:
			hidden_t = 0.0
	return _hid


## Fly to a point and arrive slow (as in version 1 of the game): brake when
## the stopping distance would overshoot; kill sideways drift while lined
## up. Long trips follow the route graph (jungle paths for strike craft).
## `arrive` is how close (world units) counts as "there".
func travel(ship: Ship, to: Vector2, arrive: float) -> void:
	var brain := ai
	var world := brain.world
	var c := ship.controls
	var p := ship.global_position
	var waypoint := to
	# Step 0: while an escape path is on (see PilotEscape), follow it and
	# nothing else.
	if escape.is_active() and escape.follow(ship):
		return
	# Step 1: long trips (over 2,500) or anywhere off the open lanes follow
	# a route. So does a short hop on the open lane when a rock is in the way
	# of the straight line (checked about 4 times a second, or when the goal
	# moves 150 units; playtest: the first jungler of every match flew
	# straight at its camp from a gate and clipped the wall beside it). Plan a
	# new route when we have none or the goal moved over 600.
	var use_route := p.distance_to(to) > 2500.0 or not world.map.in_open_lane(p)
	if not use_route:
		_line_t -= 1
		if _line_t <= 0 or to.distance_to(_line_goal) > 150.0:
			_line_t = 15
			_line_goal = to
			_line_blocked = not world.asteroids.segment_hit(p, to, ship.radius + 8.0).is_empty()
		use_route = _line_blocked
	if use_route:
		if brain.path_goal == Vector2.INF or brain.path_goal.distance_to(to) > 600.0 or brain.path.is_empty():
			brain.path = JungleBigFeature.plan_route(world.map.route, ship, p, to)
			brain.path_i = 0
			brain.path_goal = to
		if not brain.path.is_empty():
			# Thread jungle gates (86 wide) precisely: near or in the jungle,
			# reach each waypoint (within 110 instead of 350) before turning
			# for the next (playtest: a 350 reach cut the corner into the
			# gate rocks and pinned ships).
			var reach := 350.0
			var nxt := mini(brain.path_i + 1, brain.path.size() - 1)
			if not world.map.in_open_lane(p) or not world.map.in_open_lane(brain.path[nxt]):
				reach = 110.0
				# A bomber turns at 1.15 rad/s; at its jungle speed of about 260
				# its turning circle is 226 units across, so a reach of 110 can
				# never be hit and it would circle every waypoint. Reach within
				# the turning radius instead (at most 300).
				if ship.f_turn < 2.0:
					reach = clampf(ship.f_max * 0.65 / ship.f_turn, 110.0, 300.0)
			brain.path_i = Steer.advance(brain.path, brain.path_i, p, reach)
			# Head for the current waypoint (on the last leg we fly
			# straight at `to`).
			if brain.path_i < brain.path.size() - 1:
				waypoint = brain.path[brain.path_i]
	# Step 2: unstick. No real progress toward the current waypoint for 4 s
	# (pinned on rocks, or circling one) -> back off for a second and plan
	# again (the second time in the same place, plan an escape instead: see
	# PilotEscape). While backing off we reverse and slide, nothing else.
	if _unstick_t > 0.0:
		_unstick_t -= 1.0 / 60.0
		c.face_point = p + Vector2.from_angle(ship.rotation) * 400.0
		c.forward = -1.0
		c.strafe = brain.orbit
		c.boost = false
		return
	# Step 3: measure progress. A new waypoint resets the count; getting
	# 150 closer than our best resets it; otherwise (unless we're within
	# 600 of arriving) the stuck timer runs.
	var wd := p.distance_to(waypoint)
	if waypoint.distance_to(_prog_wp) > 1.0:
		_prog_wp = waypoint
		_prog_best = wd
		_stuck_t = 0.0
	elif wd < _prog_best - 150.0:
		_prog_best = wd
		_stuck_t = 0.0
	elif p.distance_to(to) > arrive + 600.0:
		_stuck_t += 1.0 / 60.0
		if _stuck_t > 4.0:
			_stuck_t = 0.0
			_unstick_t = 1.0
			escape.note_unstick(ship, to)
			brain.path = PackedVector2Array()
			brain.path_goal = Vector2.INF
			# A planned escape replaces the backing off.
			if escape.is_active():
				_unstick_t = 0.0
	# Step 4: how far off the nose is, how fast we're closing, and how far
	# we'd slide while braking (stopping distance = speed^2 / (2 x braking
	# power), the usual physics formula).
	var dvec := waypoint - p
	var dist := dvec.length()
	if dist < 1.0:
		dist = 1.0
	var aim := dvec.angle()
	var err := absf(Util.ang_diff(ship.rotation, aim))
	var closing := ship.velocity.dot(dvec) / dist
	var rev := maxf(40.0, ship.f_reverse)
	var stop := closing * closing / (2.0 * rev)
	var left := p.distance_to(to) - arrive
	# Step 5: thrust: full when lined up (within 0.6 rad), a little when
	# half turned (within 1.4 rad), none otherwise. On the last leg, brake
	# hard if we'd overshoot; once we've arrived, brake gently while still
	# closing, else coast.
	var fwd := 1.0 if err < 0.6 else (0.25 if err < 1.4 else 0.0)
	if waypoint == to:
		if left < stop * 1.15 and closing > 50.0:
			fwd = -1.0
		elif left < 0.0:
			fwd = -0.6 if closing > 30.0 else 0.0
	# Step 6: work the controls. Nose at the waypoint (or straight ahead
	# when we're on top of it); side thrusters cancel sideways drift when
	# lined up (within 0.5 rad).
	var lat := ship.velocity.dot(Util.starboard_of(ship.rotation))
	c.face_point = waypoint if dist > 60.0 else p + Vector2.from_angle(ship.rotation) * 400.0
	c.forward = fwd
	c.strafe = clampf(lat / 120.0, -1.0, 1.0) if err < 0.5 else 0.0
	# Step 7: boost on long straight runs in the open (more than 3,500 to
	# go, nose within 0.2 rad, energy over half full).
	var in_jungle := not world.map.in_open_lane(p)
	c.boost = ship.can_boost and ship.energy.fraction() > 0.5 and left > 3500.0 and err < 0.2 and not in_jungle
	# Jungle paths are narrow: keep it slow enough to make the turns
	# (playtest: every rock death was a damaged ship racing home). The
	# speed limit is 55% of top speed plus 15% times skill (about 62% to
	# 69% for our pilots).
	if in_jungle and ship.velocity.length() > ship.f_max * (0.55 + 0.15 * brain.skill):
		c.forward = minf(c.forward, 0.0 if err < 0.4 else -0.4)
	# Step 8: slow down before a sharp corner of the route or the entry into
	# the jungle (a gate). A ship coming down a lane at boost speed (about
	# 1,000 units a second) cannot turn through a gate: its turning circle is
	# 300 units wide, so it swings wide of the gate and rams the wall beside
	# it (playtest: the first jungler crashed at the same notch next to a gate
	# 13 s after launch, every match). The corner speed is 28-45% of top
	# speed (at most 38% within 1,000 units of the gate), and braking starts
	# early enough (counting on 80% of the reverse thrusters' power).
	if use_route and brain.path_i < brain.path.size() - 1:
		var after: Vector2 = brain.path[brain.path_i + 1]
		var v_in := (waypoint - p).normalized()
		var v_out := (after - waypoint).normalized()
		var turn := acos(clampf(v_in.dot(v_out), -1.0, 1.0))
		var to_jungle := not world.map.in_open_lane(after) and world.map.in_open_lane(waypoint)
		# How far along the route is the first waypoint inside the jungle (the
		# far side of a gate)? Within 1,000 of it, fly the gate approach slowly.
		var gate_d := INF
		if world.map.in_open_lane(p):
			var acc := dist
			for k in range(brain.path_i, brain.path.size()):
				if k > brain.path_i:
					acc += brain.path[k - 1].distance_to(brain.path[k])
				if not world.map.in_open_lane(brain.path[k]):
					gate_d = acc
					break
		var v_cap := INF
		if turn > 0.7 or to_jungle:
			v_cap = maxf(120.0, ship.f_max * (0.28 if (turn > 1.2 or to_jungle) else 0.45))
		if gate_d < 1000.0:
			v_cap = minf(v_cap, ship.f_max * 0.38)
		var v_now := ship.velocity.length()
		if v_now > v_cap:
			# Distance to the point where the cap applies: the corner (turn) or
			# 800 before the gate's far side.
			var cap_d := dist if (turn > 0.7 or to_jungle) else maxf(0.0, gate_d - 800.0)
			var need := (v_now * v_now - v_cap * v_cap) / (2.0 * rev * 0.8)
			if cap_d < need + 120.0 or gate_d < 800.0:
				c.forward = minf(c.forward, -0.8 if v_now > v_cap * 1.3 else 0.0)
				c.boost = false
	# Step 9: steer around mothership hulls and rocks just ahead.
	avoid_rocks(ship)


## Slide along a mothership hull instead of flying into it. A mothership is
## a solid wall to a ship, and once it has moved up into a lane (after
## 20:00) it lies right across the lane line. The route and avoid_rocks()
## know only rocks, and avoid_rocks() does nothing under 60 units a second,
## so ships (frigates and capitals above all, they turn slowly) flew into
## the hull and stayed pressed against it. A ship that is about to run into
## a mothership hull, its own or the enemy's, now turns to slide along it,
## toward the side it wants to go, a little outward. Not when the goal
## itself is within 600 of the hull (docking, defending, attacking it).
## It changes the controls' face point, forward and strafe; avoid_rocks()
## calls it first.
func avoid_hulls(ship: Ship) -> void:
	var brain := ai
	var c := ship.controls
	var p := ship.global_position
	var want := c.face_point - p
	if want.length() < 1.0:
		return
	want = want.normalized()
	# How near the hull has to be to matter: our size, 140, and how far we
	# will travel while we turn (slower turners look further ahead).
	var trig := ship.radius + 140.0 + ship.velocity.length() * clampf(1.2 / maxf(ship.f_turn, 0.3), 0.3, 3.0)
	for t in 2:
		var ms := brain.world.mothership(t)
		if ms == null or not ms.alive or ms.hull_dist(p) > trig or ms.hull_dist(brain.goal) < 600.0:
			continue
		var a := ms.global_position + Vector2.from_angle(ms.rotation) * ms.half_len
		var b := ms.global_position - Vector2.from_angle(ms.rotation) * ms.half_len
		# `n` points from the hull's keel (its centre line) to us. A ship
		# heading within about 75 degrees of straight away from it is fine.
		var n := (p - Util.closest_on_segment(p, a, b)).normalized()
		if want.dot(n) >= 0.25:
			continue
		# Slide along the hull the way we want to go, a little outward.
		var tang := Vector2(-n.y, n.x)
		if tang.dot(want) < 0.0:
			tang = -tang
		var dir := (tang + n * 0.5).normalized()
		c.face_point = p + dir * 400.0
		c.forward = maxf(c.forward, 0.6)
		c.strafe = clampf(Util.port_of(ship.rotation).dot(dir) * 1.5, -1.0, 1.0)
		return


## Nudge the nose away from mothership hulls (avoid_hulls()) and from rocks
## just ahead. It runs about once a tick; the rock search itself runs on
## every 5th call (about 12 times a second; it's the costliest part of
## steering), and the push it finds is reused in between.
func avoid_rocks(ship: Ship) -> void:
	var brain := ai
	var c := ship.controls
	var v := ship.velocity
	avoid_hulls(ship)
	# Step 1: nearly stopped (under 60 units a second): nothing to dodge.
	if v.length() < 60.0:
		return
	# Step 2: every 5th call, look at the spot we'll reach in 0.6 seconds.
	# Each rock overlapping it (rock radius + our radius + 30) pushes that
	# spot away from the rock's centre, harder the deeper the overlap.
	_rock_t -= 1
	if _rock_t <= 0:
		_rock_t = 5
		var look := ship.global_position + v * 0.6
		var push := Vector2.ZERO
		# In open space no rock can reach that spot: skip the search (the
		# push would stay zero anyway; AsteroidField.clear_at()).
		if not brain.world.asteroids.clear_at(look, ship.radius + 30.0):
			brain.world.asteroids.nearby(look, ship.radius + 260.0, _rocks)
			for i in _rocks:
				var rc := brain.world.asteroids.pos[i]
				var rr := brain.world.asteroids.rad[i] + ship.radius + 30.0
				var d := look.distance_to(rc)
				if d < rr and d > 0.01:
					push += (look - rc) / d * (rr - d)
		_rock_push = push
	# Step 3: turn the nose toward the push and slide that way; brake if
	# we're flying mostly straight at the rock.
	var push := _rock_push
	if push.length() > 1.0:
		var s := push.normalized()
		c.face_point = ship.global_position + (c.face_point - ship.global_position).normalized() * 300.0 + s * 400.0
		var port := Util.port_of(ship.rotation)
		c.strafe = clampf(c.strafe + port.dot(s) * 1.5, -1.0, 1.0)
		if ship.velocity.normalized().dot(-s) > 0.6:
			if ship.velocity.dot(Vector2.from_angle(ship.rotation)) < 0.0:
				# Moving tail-first into the rock: brake with the main engine;
				# the reverse thrusters would push us on toward the rock.
				c.forward = maxf(c.forward, 0.3)
			else:
				c.forward = minf(c.forward, -0.3)
