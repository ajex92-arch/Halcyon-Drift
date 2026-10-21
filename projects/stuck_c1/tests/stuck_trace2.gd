extends Node
## WHAT THIS IS: a trace harness for ships that get stuck in the asteroids.
## It watches a whole all-AI match and writes the lines that show how a pilot
## gets stuck and how (or whether) it gets free again. It only reads the
## game; it never changes the match.
##
## HOW IT WORKS: it has two modes (--st-mode=NAME).
##   log (the default; headless, with --sim-only): it runs the real
##     pilot_audit as a child, so the usual AUDIT and AUDIT_JSON lines come
##     out as well, and adds its own lines:
##       EPJ {...}     one per stuck episode (the audit's rule: within 150
##                     units for 8 s, far from the goal, not fighting), with
##                     its real start and end, how it ended, and how the
##                     brain spent the time (route empty, escape flying,
##                     backing off);
##       TRAPJ {...}   one per trap: a ship that stayed within 400 units for
##                     60 s while it scraped a rock for at least 2 s of it,
##                     whether it was fighting or not, with its real length,
##                     how it ended and how the brain spent the time;
##       TRACE ...     once a second for up to MAX_TRACES ships that are on
##                     a rock or trapped, for TRACE_LEN seconds: position,
##                     goal, route, the nearest route dot and whether it can
##                     be seen, the stuck timer, the escape state and the
##                     controls;
##       ESC ...       every change of a traced ship's escape (PilotEscape);
##       ST_SUMMARY {...}   once, at the end.
##     Everything is written out when the match ends (Events.match_over) as
##     well as at --secs.
##   shots (windowed): it follows one pilot and saves a picture at each time
##     in --st-times, with the rocks' hit circles, the route graph, the
##     pilot's route, goal, target and escape path drawn on top. Drawing is
##     switched off until 12 s before the first picture, so the match runs at
##     headless speed.
## Options: --secs=N (match seconds), --st-who=CALLSIGN and --st-team=0|1
## (the pilot to follow), --st-times=T1,T2,... (match seconds), --st-dir=PATH
## (the picture folder; the game's user folder by default), --st-view=N (world
## units across a picture, 2400 by default), --st-fast=0 (draw all the time).
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=305 --skill-jitter --sim-only --test=stuck_trace2 --st-mode=log --secs=3000
##
## WHO USES IT: main.gd loads it for --test=stuck_trace2 and calls setup(). It
## reads the brains' route (PilotAI.path), PilotFlight's stuck timers and
## PilotEscape's state, the route graph and the asteroid field.

## The real pilot_audit, run as a child in log mode so its lines come out too.
const AUDIT := preload("res://tests/pilot_audit.gd")
## The most ships traced at the same time over the whole match.
const MAX_TRACES := 6
## How long (seconds) a ship is traced after it was picked.
const TRACE_LEN := 60.0
## The trap window: this many position samples, 2 s apart (so 60 s).
const TRAP_WIN := 30
## A ship is trapped when it never went farther than this (world units) from
## where the window began.
const TRAP_RADIUS := 400.0
## ...and scraped a rock for at least this many ticks of the window (120 ticks
## = 2 s).
const TRAP_ROCK_TICKS := 120

## The running match (set by setup()).
var world: World
## The pilot_audit child (log mode), or null.
var audit: Node = null
## "log" or "shots" (see HOW IT WORKS).
var mode := "log"
## Game time (seconds) at which to stop (--secs).
var secs := 1500.0
## True once the end-of-run lines were written.
var _flushed := false
## Seconds until the next 2 s position sample.
var _t2 := 0.0
## Seconds until the next 0.5 s sample.
var _t05 := 0.0
## Per pilot (key "team:callsign"): the positions and rock ticks of the
## episode and trap windows, and the running episode and trap.
var hist := {}
## How many stuck episodes have ended so far.
var closed := 0
## How many traps have ended so far.
var traps_closed := 0
## When each pilot's ship last died (key -> game time), to tell a death from a
## dock when a ship leaves the sky.
var dead_at := {}
## The ships being traced (key -> {"until": end time, "next": next line time}).
var traces := {}
## How many ships have been picked for tracing so far.
var n_traces := 0
## The last escape state printed for each traced ship (key -> text).
var _esc_last := {}

## Shots mode: the callsign of the pilot to follow.
var who := ""
## Shots mode: the pilot's team (0 or 1; -1 = either).
var who_team := -1
## Shots mode: the game times (seconds) of the pictures.
var shot_times: Array = []
## Shots mode: the next picture to take (a position in `shot_times`).
var shot_i := 0
## Shots mode: the folder the pictures go to.
var shot_dir := ""
## Shots mode: how many world units fit across a picture.
var view_w := 2400.0
## Shots mode: the node that draws the overlay.
var overlay: Node2D = null
## Shots mode: true = drawing is off until shortly before the first picture.
var fast := true
## Shots mode: true while the game is drawing.
var _render_on := true
## Shots mode: true while a picture is being taken.
var _taking := false


## A node that hands its drawing to the harness (draw_overlay()).
class Overlay extends Node2D:
	## The harness that does the drawing.
	var owner_node: Node

	## Godot calls this to draw; the harness draws on this node.
	func _draw() -> void:
		if owner_node != null:
			owner_node.call("draw_overlay", self)


## main.gd calls this once, right after the World is built. Read the options
## and set up the mode.
func setup(w: World) -> void:
	world = w
	mode = str(Game.opt("st-mode", "log"))
	secs = float(Game.opt("secs", 1500.0))
	Events.unit_killed.connect(_on_killed)
	Events.match_over.connect(_on_match_over)
	if mode == "log":
		audit = AUDIT.new()
		add_child(audit)
		audit.call("setup", w)
	else:
		who = str(Game.opt("st-who", ""))
		who_team = int(str(Game.opt("st-team", "-1")))
		shot_dir = str(Game.opt("st-dir", OS.get_user_data_dir()))
		DirAccess.make_dir_recursive_absolute(shot_dir)
		for t in str(Game.opt("st-times", "")).split(","):
			if t.strip_edges() != "":
				shot_times.append(float(t))
		view_w = float(str(Game.opt("st-view", "2400")))
		fast = str(Game.opt("st-fast", "1")) != "0"
		process_mode = Node.PROCESS_MODE_ALWAYS
		# The camera is placed by hand (a fresh window reports the mouse at the
		# corner, which would pan the free camera away).
		world.camera.set_process(false)
		overlay = Overlay.new()
		overlay.owner_node = self
		overlay.z_index = 60
		world.add_child(overlay)
		if fast and not shot_times.is_empty():
			RenderingServer.render_loop_enabled = false
			_render_on = false


## The key of a pilot's brain in `hist`: team, a colon and the callsign.
func _key(b: PilotAI) -> String:
	return "%d:%s" % [b.profile.team, b.profile.callsign]


## A unit died: remember when a pilot's ship did.
func _on_killed(u: Node, _info: RefCounted) -> void:
	if u is Ship and (u as Ship).controller is PilotAI:
		dead_at[_key((u as Ship).controller as PilotAI)] = world.time


## The match ended: write everything out (log mode).
func _on_match_over(_winner: int, _reason: String) -> void:
	if mode == "log":
		_flush("match_over")


## The history of the pilot called `key`; made on first use.
func _h(key: String) -> Dictionary:
	if not hist.has(key):
		hist[key] = {"pos": [], "stuck": false, "ep": null, "rock_cur": 0, "rwin": [], "tpos": [], "trock": [], "trap": null}
	return hist[key]


## Every tick (log mode): count rock contacts, print the escape changes of
## traced ships, run the 0.5 s and 2 s samples, and write everything out at
## the end.
func _physics_process(dt: float) -> void:
	if world == null or mode != "log":
		return
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var key := _key(b)
		var rock := false
		for i in s.get_slide_collision_count():
			if not (s.get_slide_collision(i).get_collider() is Unit):
				rock = true
				break
		if rock:
			var h := _h(key)
			h["rock_cur"] += 1
			if h["ep"] != null:
				(h["ep"] as Dictionary)["rock_ticks"] += 1
			if h["trap"] != null:
				(h["trap"] as Dictionary)["rock_ticks"] += 1
		# ESC lines for traced ships: any change of the escape's state.
		if traces.has(key):
			var esc := b.flight.escape
			var sig := "%d/%d/%d" % [1 if esc.is_active() else 0, esc._path.size(), esc._fires]
			if _esc_last.get(key, "") != sig:
				_esc_last[key] = sig
				print("ESC t=%.2f %s active/path/fires=%s cool=%.1f stuck_t=%.1f unstick_t=%.1f p=(%d,%d) path_len=%d" % [world.time, key, sig, maxf(0.0, esc._cool_until - world.time),
					b.flight._stuck_t, b.flight._unstick_t, s.global_position.x, s.global_position.y, b.path.size()])
	_t05 -= dt
	if _t05 <= 0.0:
		_t05 = 0.5
		_sample()
	_t2 -= dt
	if _t2 <= 0.0:
		_t2 = 2.0
		_positions()
	if world.time >= secs - 0.06:
		_flush("secs")


## Write out the running episodes and traps and the summary line, once. `why`
## says what ended the run.
func _flush(why: String) -> void:
	if _flushed:
		return
	_flushed = true
	for key in hist.keys():
		var h2: Dictionary = hist[key]
		if h2["ep"] != null:
			_ep_end(h2, why)
		if h2["trap"] != null:
			_trap_end(h2, why)
	print("ST_SUMMARY ", JSON.stringify({"t": snappedf(world.time, 0.1), "episodes_closed": closed, "traps_closed": traps_closed, "traces": n_traces, "why": why}))


## Every 2 s: the stuck-episode rule of pilot_audit and the 60-second trap
## rule for every flying pilot; episodes and traps of pilots that left the sky
## end here.
func _positions() -> void:
	var seen := {}
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var key := _key(b)
		seen[key] = true
		var h := _h(key)
		# The audit-style episode window (5 samples).
		var ps: Array = h["pos"]
		ps.append(s.global_position)
		if ps.size() > 5:
			ps.pop_front()
		var rw: Array = h["rwin"]
		rw.append(h["rock_cur"])
		if rw.size() > 5:
			rw.pop_front()
		# The trap window (60 s).
		var tp: Array = h["tpos"]
		tp.append(s.global_position)
		if tp.size() > TRAP_WIN:
			tp.pop_front()
		var tr: Array = h["trock"]
		tr.append(h["rock_cur"])
		if tr.size() > TRAP_WIN:
			tr.pop_front()
		h["rock_cur"] = 0
		var has_t: bool = b.target != null and is_instance_valid(b.target) and b.target.alive
		var fighting: bool = has_t and b.state != "home" and b.state != "retreat" and not b.combat.target_far(s)
		if ps.size() >= 5:
			var moved := 0.0
			for p: Vector2 in ps:
				moved = maxf(moved, p.distance_to(ps[0]))
			var far := s.global_position.distance_to(b.goal) > 800.0
			var stuck := moved < 150.0 and far and not fighting
			if stuck and not h["stuck"]:
				_ep_start(s, b, h)
			elif (not stuck) and h["stuck"] and h["ep"] != null:
				_ep_end(h, "moved")
			h["stuck"] = stuck
			if stuck and h["ep"] != null:
				(h["ep"] as Dictionary)["flags"] += 1
		# The trap rule.
		if tp.size() >= TRAP_WIN:
			var dmax := 0.0
			for p2: Vector2 in tp:
				dmax = maxf(dmax, p2.distance_to(tp[0]))
			var rsum := 0
			for v in tr:
				rsum += int(v)
			if h["trap"] == null and dmax < TRAP_RADIUS and rsum >= TRAP_ROCK_TICKS:
				_trap_start(s, b, h, rsum, tp[0])
			elif h["trap"] != null:
				var trp: Dictionary = h["trap"]
				var c: Vector2 = trp["center"]
				if s.global_position.distance_to(c) > TRAP_RADIUS + 150.0:
					_trap_end(h, "left")
	for key in hist.keys():
		var hh: Dictionary = hist[key]
		if not seen.has(key):
			var d := "died" if dead_at.has(key) and world.time - float(dead_at[key]) < 4.0 else "gone"
			if hh["ep"] != null:
				_ep_end(hh, d)
			if hh["trap"] != null:
				_trap_end(hh, d)
			hh["stuck"] = false
			(hh["pos"] as Array).clear()
			(hh["tpos"] as Array).clear()
			(hh["trock"] as Array).clear()


## The gap (world units) between a circle at `p` with radius `r` and the
## nearest rock's solid circle (95% of its radius); negative = overlapping.
func _rock_gap(p: Vector2, r: float) -> float:
	var tmp := PackedInt32Array()
	world.asteroids.nearby(p, r + 400.0, tmp)
	var best := 9999.0
	for i in tmp:
		best = minf(best, p.distance_to(world.asteroids.pos[i]) - 0.95 * world.asteroids.rad[i] - r)
	return best


## A trap is found: the ship `s` (brain `b`, history `h`) stayed within
## TRAP_RADIUS for 60 s with `rsum` ticks of rock contact; `p_old` is where
## the window began. Start counting it, and trace the ship if there is room.
func _trap_start(s: Ship, b: PilotAI, h: Dictionary, rsum: int, p_old: Vector2) -> void:
	var key := _key(b)
	h["trap"] = {"t0": world.time - 60.0, "tdet": world.time, "team": b.profile.team, "who": b.profile.callsign, "hull": s.hull_id, "state0": b.state,
		"p0": [roundi(p_old.x), roundi(p_old.y)], "center": s.global_position, "g0": [roundi(b.goal.x), roundi(b.goal.y)], "launched": snappedf(b.launched_at, 0.1),
		"rock_pre": rsum, "rock_ticks": 0, "n": 0, "st": {}, "fight": 0, "path_empty": 0, "esc": 0, "unst": 0, "hidden_leg": 0, "aerr_big": 0, "fires_max": 0,
		"gap0": snappedf(_rock_gap(s.global_position, s.radius), 0.1), "hold": b.intent}
	if n_traces < MAX_TRACES and not traces.has(key):
		traces[key] = {"until": world.time + TRACE_LEN, "next": world.time}
		n_traces += 1
		print("TRACE_START ", key, " ", s.hull_id, " t=", snappedf(world.time, 0.1), " gap0=", h["trap"]["gap0"], " (trap)")


## The trap of history `h` ends now, for reason `why`: print its TRAPJ line.
func _trap_end(h: Dictionary, why: String) -> void:
	var tp: Dictionary = h["trap"]
	h["trap"] = null
	var n := maxf(1.0, float(tp["n"]))
	var out := {"t0": snappedf(tp["t0"], 0.1), "t1": snappedf(world.time, 0.1), "dur": snappedf(world.time - float(tp["t0"]), 0.1), "team": tp["team"], "who": tp["who"], "hull": tp["hull"],
		"state0": tp["state0"], "states": tp["st"], "p0": tp["p0"], "g0": tp["g0"], "gap0": tp["gap0"], "rock_s": snappedf(float(tp["rock_ticks"]) / 60.0 + float(tp["rock_pre"]) / 60.0, 0.1),
		"fight_frac": snappedf(float(tp["fight"]) / n, 0.01), "path_empty_frac": snappedf(float(tp["path_empty"]) / n, 0.01), "esc_frac": snappedf(float(tp["esc"]) / n, 0.01),
		"unst_frac": snappedf(float(tp["unst"]) / n, 0.01), "hidden_leg_frac": snappedf(float(tp["hidden_leg"]) / n, 0.01), "aerr_big_frac": snappedf(float(tp["aerr_big"]) / n, 0.01),
		"fires_max": tp["fires_max"], "end": why, "launched": tp["launched"]}
	traps_closed += 1
	print("TRAPJ ", JSON.stringify(out))


## A stuck episode begins for ship `s` (brain `b`, history `h`). Trace the ship
## if it touches rock.
func _ep_start(s: Ship, b: PilotAI, h: Dictionary) -> void:
	var rsum := 0
	for v in (h["rwin"] as Array):
		rsum += int(v)
	var gap := _rock_gap(s.global_position, s.radius)
	h["ep"] = {"t0": world.time - 8.0, "team": b.profile.team, "who": b.profile.callsign, "hull": s.hull_id,
		"state0": b.state, "p0": [roundi(s.global_position.x), roundi(s.global_position.y)], "g0": [roundi(b.goal.x), roundi(b.goal.y)],
		"gap0": snappedf(gap, 0.1), "rock_pre": rsum, "route_len0": b.path.size(), "route_i0": b.path_i, "launched": snappedf(b.launched_at, 0.1),
		"flags": 0, "n": 0, "path_empty": 0, "esc": 0, "unst": 0, "rock_ticks": 0, "maxd": 0.0, "state1": b.state, "p": s.global_position}
	var key := _key(b)
	if (rsum > 0 or gap <= 8.0) and n_traces < MAX_TRACES and not traces.has(key):
		traces[key] = {"until": world.time + TRACE_LEN, "next": world.time}
		n_traces += 1
		print("TRACE_START ", key, " ", s.hull_id, " t=", snappedf(world.time, 0.1), " gap0=", snappedf(gap, 0.1))


## The stuck episode of history `h` ends now, for reason `why`: print its EPJ
## line.
func _ep_end(h: Dictionary, why: String) -> void:
	var ep: Dictionary = h["ep"]
	h["ep"] = null
	var out := {"t0": snappedf(ep["t0"], 0.1), "t1": snappedf(world.time, 0.1), "dur": snappedf(world.time - float(ep["t0"]), 0.1), "team": ep["team"], "who": ep["who"],
		"hull": ep["hull"], "state0": ep["state0"], "state1": ep["state1"], "p0": ep["p0"], "g0": ep["g0"], "gap0": ep["gap0"], "rock_pre": ep["rock_pre"],
		"route0": [ep["route_i0"], ep["route_len0"]], "flags": ep["flags"], "rock_s": snappedf(float(ep["rock_ticks"]) / 60.0, 0.1),
		"path_empty_s": snappedf(float(ep["path_empty"]) * 0.5, 0.1), "esc_s": snappedf(float(ep["esc"]) * 0.5, 0.1), "unst_s": snappedf(float(ep["unst"]) * 0.5, 0.1),
		"maxd": roundi(ep["maxd"]), "end": why, "launched": ep["launched"]}
	closed += 1
	print("EPJ ", JSON.stringify(out))


## Every 0.5 s: how each running episode and trap spends its time, and the
## once-a-second TRACE lines of traced ships.
func _sample() -> void:
	for s: Ship in world.ships:
		if not s.alive or not (s.controller is PilotAI):
			continue
		var b := s.controller as PilotAI
		var key := _key(b)
		var h: Dictionary = hist.get(key, {})
		if h.is_empty():
			continue
		var esc := b.flight.escape
		if h["ep"] != null:
			var ep: Dictionary = h["ep"]
			ep["n"] += 1
			if b.path.is_empty():
				ep["path_empty"] += 1
			if esc.is_active():
				ep["esc"] += 1
			if b.flight._unstick_t > 0.0:
				ep["unst"] += 1
			ep["maxd"] = maxf(float(ep["maxd"]), s.global_position.distance_to(ep["p"]))
			ep["state1"] = b.state
		if h["trap"] != null:
			var tp: Dictionary = h["trap"]
			tp["n"] += 1
			var st: Dictionary = tp["st"]
			st[b.state] = int(st.get(b.state, 0)) + 1
			var has_t: bool = b.target != null and is_instance_valid(b.target) and b.target.alive
			if has_t and b.state != "home" and b.state != "retreat" and not b.combat.target_far(s):
				tp["fight"] += 1
			if b.path.is_empty():
				tp["path_empty"] += 1
			if esc.is_active():
				tp["esc"] += 1
			if b.flight._unstick_t > 0.0:
				tp["unst"] += 1
			tp["fires_max"] = maxi(int(tp["fires_max"]), esc._fires)
			if not b.path.is_empty():
				var wp: Vector2 = b.path[mini(b.path_i, b.path.size() - 1)]
				if absf(Util.ang_diff(s.rotation, (wp - s.global_position).angle())) > 1.4:
					tp["aerr_big"] += 1
				var nd := world.map.route.nearest(s.global_position, s.is_small())
				if nd >= 0 and not world.asteroids.segment_hit(s.global_position, world.map.route.pos[nd], 16.0).is_empty():
					tp["hidden_leg"] += 1
		if traces.has(key):
			var tr: Dictionary = traces[key]
			if world.time > float(tr["until"]):
				traces.erase(key)
				_esc_last.erase(key)
			elif world.time >= float(tr["next"]):
				tr["next"] = world.time + 1.0
				_trace_line(s, b, key)


## Print one TRACE line for ship `s` (brain `b`, history key `key`): where it
## is, what it flies to, the nearest route dot and whether it can be seen, and
## the timers and controls.
func _trace_line(s: Ship, b: PilotAI, key: String) -> void:
	var small := s.is_small()
	var route := world.map.route
	var nd := route.nearest(s.global_position, small)
	var ndp := route.pos[nd] if nd >= 0 else Vector2.ZERO
	var vis := nd >= 0 and world.asteroids.segment_hit(s.global_position, ndp, 16.0).is_empty()
	var wp := Vector2.ZERO
	if not b.path.is_empty():
		wp = b.path[mini(b.path_i, b.path.size() - 1)]
	var esc := b.flight.escape
	var a_err := 0.0
	if wp != Vector2.ZERO:
		a_err = absf(Util.ang_diff(s.rotation, (wp - s.global_position).angle()))
	var has_t: bool = b.target != null and is_instance_valid(b.target) and b.target.alive
	print("TRACE t=%.1f %s %s st=%s int=%s p=(%d,%d) v=%d rot=%.2f g=(%d,%d) gd=%d path=%d/%d wp=(%d,%d) wpd=%d aerr=%.2f nd=(%d,%d) ndd=%d ndvis=%d stk=%.1f unst=%.1f esc=%d/%d/%d fires=%d cool=%.0f fwd=%.2f str=%.2f gap=%.1f slides=%d tgt=%d far=%d" % [
		world.time, key, s.hull_id, b.state, b.intent, s.global_position.x, s.global_position.y, s.velocity.length(), s.rotation, b.goal.x, b.goal.y,
		s.global_position.distance_to(b.goal), b.path_i, b.path.size(), wp.x, wp.y, s.global_position.distance_to(wp), a_err, ndp.x, ndp.y,
		s.global_position.distance_to(ndp), 1 if vis else 0, b.flight._stuck_t, b.flight._unstick_t, 1 if esc.is_active() else 0, esc._path.size(), esc._path_i,
		esc._fires, maxf(0.0, esc._cool_until - world.time), s.controls.forward, s.controls.strafe, _rock_gap(s.global_position, s.radius),
		s.get_slide_collision_count(), 1 if has_t else 0, 1 if (has_t and b.combat.target_far(s)) else 0])


# ============================================================== shots mode

## Shots mode: the ship of the pilot being followed, or null while it is not
## flying.
func _find_ship() -> Ship:
	for p: PilotProfile in world.profiles:
		if p.callsign == who and (who_team < 0 or p.team == who_team) and p.ship != null and is_instance_valid(p.ship) and p.ship.alive:
			return p.ship
	return null


## Shots mode, every drawn frame: switch drawing on shortly before the first
## picture, keep the camera on the followed ship, and take a picture at each
## wanted time.
func _process(_dt: float) -> void:
	if world == null or mode != "shots":
		return
	if not _render_on and not shot_times.is_empty() and world.time >= float(shot_times[0]) - 12.0:
		RenderingServer.render_loop_enabled = true
		_render_on = true
	var s := _find_ship()
	if s != null and _render_on:
		var z := get_viewport().get_visible_rect().size.x / view_w
		world.camera.global_position = s.global_position
		world.camera.zoom = Vector2(z, z)
	if overlay != null and _render_on:
		overlay.queue_redraw()
	if shot_i < shot_times.size() and world.time >= float(shot_times[shot_i]) and _render_on and not _taking:
		_taking = true
		var t_now := world.time
		var idx := shot_i
		shot_i += 1
		await RenderingServer.frame_post_draw
		var path := shot_dir.path_join("seed%s_%s_t%04d_%02d.png" % [str(Game.opt("seed", "x")), who, int(t_now), idx])
		get_viewport().get_texture().get_image().save_png(path)
		var info := ""
		if s != null and s.controller is PilotAI:
			var bb := s.controller as PilotAI
			info = " pos=(%d,%d) v=%d state=%s intent=%s path=%d/%d stuck_t=%.1f unstick_t=%.1f esc=%s tgt=%s" % [s.global_position.x, s.global_position.y, s.velocity.length(), bb.state, bb.intent,
				bb.path_i, bb.path.size(), bb.flight._stuck_t, bb.flight._unstick_t, str(bb.flight.escape.is_active()), str(bb.target != null and is_instance_valid(bb.target))]
		print("shot ", path, " t=", snappedf(t_now, 0.1), " found=", s != null, info)
		_taking = false
		if shot_i >= shot_times.size():
			get_tree().quit()


## Shots mode: draw the overlay on `cv`: the rocks' hit circles near the
## camera, the route graph, the followed pilot's route (cyan, the next
## waypoint yellow), goal (orange), target (red), escape path (magenta),
## velocity (green) and a line of text about its brain.
func draw_overlay(cv: Node2D) -> void:
	if world == null or world.camera == null:
		return
	var z := maxf(world.camera.zoom.x, 0.02)
	var u := 1.0 / z
	var c := world.camera.global_position
	var half := view_w * 0.75
	var tmp := PackedInt32Array()
	world.asteroids.nearby(c, half * 1.1, tmp)
	for i in tmp:
		var rp: Vector2 = world.asteroids.pos[i]
		cv.draw_arc(rp, 0.95 * world.asteroids.rad[i], 0.0, TAU, 40, Color(1, 1, 1, 0.55), 1.2 * u)
	var route := world.map.route
	for i in route.pos.size():
		var p: Vector2 = route.pos[i]
		if absf(p.x - c.x) > half or absf(p.y - c.y) > half:
			continue
		cv.draw_circle(p, 5.0 * u, Color(0.3, 0.95, 0.6, 0.95))
		for e: Array in route.adj[i]:
			if int(e[0]) > i:
				var q: Vector2 = route.pos[int(e[0])]
				cv.draw_line(p, q, Color(0.3, 0.9, 0.6, 0.55) if bool(e[1]) else Color(0.9, 0.9, 0.3, 0.5), 1.6 * u)
	var s := _find_ship()
	if s == null:
		return
	var b := s.controller as PilotAI
	if b == null:
		return
	var pos := s.global_position
	if not b.path.is_empty():
		for k in b.path.size() - 1:
			cv.draw_line(b.path[k], b.path[k + 1], Color(0.2, 0.8, 1.0, 0.95), 2.4 * u)
		for k in b.path.size():
			cv.draw_circle(b.path[k], 7.0 * u, Color(0.2, 0.8, 1.0, 0.9) if k != b.path_i else Color(1, 1, 0.2, 1))
		var wp: Vector2 = b.path[mini(b.path_i, b.path.size() - 1)]
		cv.draw_line(pos, wp, Color(1, 1, 0.2, 0.9), 2.0 * u)
	cv.draw_line(pos, pos + (b.goal - pos).limit_length(900.0), Color(1.0, 0.5, 0.1, 0.9), 2.0 * u)
	if b.goal.distance_to(pos) < view_w:
		cv.draw_circle(b.goal, 14.0 * u, Color(1.0, 0.5, 0.1, 0.8))
	if b.target != null and is_instance_valid(b.target):
		cv.draw_line(pos, b.target.global_position, Color(1.0, 0.1, 0.1, 0.6), 1.6 * u)
	var esc := b.flight.escape
	if esc.is_active() and not esc._path.is_empty():
		var prev := pos
		for k in range(esc._path_i, esc._path.size()):
			cv.draw_line(prev, esc._path[k], Color(1.0, 0.2, 1.0, 0.95), 2.6 * u)
			cv.draw_circle(esc._path[k], 6.0 * u, Color(1.0, 0.2, 1.0, 1.0))
			prev = esc._path[k]
	cv.draw_arc(pos, s.radius, 0.0, TAU, 24, Color(1, 0.2, 0.2, 1), 2.0 * u)
	cv.draw_line(pos, pos + Vector2.from_angle(s.rotation) * 120.0, Color(1, 1, 1, 1), 2.0 * u)
	cv.draw_line(pos, pos + s.velocity * 0.6, Color(0.3, 1, 0.3, 1), 2.4 * u)
	var txt := "%s %s %s  t=%.0f  state=%s/%s  v=%d  path=%d/%d  stuck=%.1f unstick=%.1f  esc=%s fires=%d  target=%s" % [who, "A" if s.team == 0 else "C", s.hull_id, world.time, b.state, b.intent,
		s.velocity.length(), b.path_i, b.path.size(), b.flight._stuck_t, b.flight._unstick_t, "ON" if esc.is_active() else "off", esc._fires, "yes" if (b.target != null and is_instance_valid(b.target)) else "no"]
	var font := ThemeDB.fallback_font
	cv.draw_string(font, c - Vector2(view_w * 0.5 - 12.0 * u, view_w * 0.3 - 22.0 * u), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * u), Color(1, 1, 1, 1))
	cv.draw_string(font, c - Vector2(view_w * 0.5 - 12.0 * u, view_w * 0.3 - 44.0 * u), "white circles = rock hit shapes; cyan = route; yellow = next waypoint; orange = goal; red = target; magenta = escape path; green = velocity", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * u), Color(0.8, 0.8, 0.8, 1))
