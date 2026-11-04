class_name BeaconsFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "beacons" rule variant (fork
## teamfights_jungle, idea D6): two salvage beacons on the connector that
## the teams capture by hovering next to them, and that pay their owner and
## blind the enemy's wards from time to time. REQ-CHANGE: "Remove the
## dynamic event zones" (a temporary sensor blackout) and the capture points
## that mining drones replaced.
##
## HOW IT WORKS:
##   - Two beacons stand on the connector's centre line (x = 20,000), one in
##     its upper half at y = 8,000 and one in its lower half at y = 18,000
##     (open ground between the top and mid lanes, and between the mid and
##     bottom lanes; if a rock is in the way the nearest free spot along the
##     line is used). Both teams see them on the minimap.
##   - A team captures a beacon when one of its pilot ships hovers within 700
##     world units of it for 20 seconds with no enemy pilot ship within
##     1,500. The progress waits while an enemy pilot is within 1,500, and
##     drains when nobody of the team is within 700. A held beacon stays held
##     until the other team captures it.
##   - A held beacon pays 60 credits to each of its team's pilot ships within
##     4,000 of it, once every 60 seconds it is held.
##   - Every 90 seconds it is held, the other team is blacked out for 15
##     seconds: its wards in that beacon's half of the map (the upper half
##     for the upper beacon, the lower half for the lower one) stop seeing,
##     and its minimap shows no enemy contacts in that half.
##   - The AI uses it (pilot_think, no skill read): a jungler or flex seat
##     with two or more friendly small ships within 4,000 flies to the
##     nearest beacon its team does not hold, and hovers there (fighting any
##     enemy that shows up, like the normal lane job). The trip lasts 90
##     seconds once started, even if the group stays behind.
## Usage counts: "beacon_trips" (trips started), "beacon_captures" and
## "blackout_seconds". No random numbers are drawn.
##
## WHO USES IT: FeatureRegistry installs it for --variant=beacons:on.
## PilotAI's feature hook calls pilot_think(); the minimap calls
## minimap_marks() and minimap_hides().

## The variant key this module belongs to.
const KEY := "beacons"
## Where the two beacons would stand (world positions): upper, then lower.
const SPOTS := [Vector2(20000, 8000), Vector2(20000, 18000)]
## A pilot within this many world units of a beacon counts as hovering at it.
const CAPTURE_RADIUS := 700.0
## An enemy pilot within this many world units pauses a capture.
const CONTEST_RADIUS := 1500.0
## Seconds of hovering needed to capture.
const CAPTURE_TIME := 20.0
## Credits per pilot per payment.
const PAY := 60.0
## Seconds between two payments.
const PAY_EVERY := 60.0
## Pilots within this many world units of a held beacon are paid.
const PAY_RADIUS := 4000.0
## Seconds between two blackouts of the same held beacon.
const BLACKOUT_EVERY := 90.0
## Seconds a blackout lasts.
const BLACKOUT_TIME := 15.0
## The y at which the map is split into the upper and lower half.
const MID_Y := 13000.0
## Seconds between two capture steps.
const STEP := 0.25
## A jungler or flex seat needs this many friendly small ships within
## AI_RADIUS to go for a beacon.
const AI_FRIENDS := 2
## See AI_FRIENDS (world units).
const AI_RADIUS := 4000.0
## Seconds a beacon trip lasts once the group rule has started it.
const COMMIT := 90.0

## The match.
var world: World
## The two beacons: dictionaries with pos (Vector2), upper (true for the
## upper half), owner (team or -1), progress (two floats, one per team),
## pay_t, black_t (seconds held since the last payment / blackout) and
## blackout_until (match time the current blackout ends; the team hit is the
## enemy of the owner).
var beacons: Array = []
## Ship uid -> the match time at which that pilot's beacon trip ends.
var committed := {}
## Seconds until the next capture step.
var _t := 0.0
## Blackout seconds not yet added to the usage count.
var _acc := 0.0


## Hook the module into match `w`: place the beacons and start the tick.
func install(w: World) -> void:
	world = w
	for i in SPOTS.size():
		beacons.append({"pos": _free_spot(SPOTS[i]), "upper": i == 0, "owner": -1, "progress": [0.0, 0.0],
			"pay_t": 0.0, "black_t": 0.0, "blackout_until": 0.0})
	w.tick_hooks.append(Callable(self, "tick"))


## `p` if no rock is within 300 of it, else the nearest free spot along the
## connector's centre line (700 to 3,000 world units up or down from `p`).
func _free_spot(p: Vector2) -> Vector2:
	for dy: float in [0.0, 700.0, -700.0, 1400.0, -1400.0, 2200.0, -2200.0, 3000.0, -3000.0]:
		var q := p + Vector2(0.0, dy)
		if not world.asteroids.blocked(q, 300.0):
			return q
	return p


## Called by World every tick: every STEP seconds update the captures, the
## payments and the blackouts; every tick keep blacked-out wards blind.
func tick(dt: float) -> void:
	# Blind wards must be re-blinded every tick: a ward sets its own sight
	# range during its turn.
	for b: Dictionary in beacons:
		if float(b["blackout_until"]) > world.time:
			for w: Ward in world.wards:
				if w.alive and w.team == 1 - int(b["owner"]) and _in_half(b, w.global_position):
					w.vision_radius = 0.0
	_t -= dt
	if _t > 0.0:
		return
	_t = STEP
	for b: Dictionary in beacons:
		_capture_step(b)
		if int(b["owner"]) >= 0:
			_held_step(b)
		if float(b["blackout_until"]) > world.time:
			_acc += STEP
	if _acc >= 1.0:
		Game.count_usage("blackout_seconds", int(_acc))
		_acc -= float(int(_acc))


## Is world point `p` in beacon `b`'s half of the map?
func _in_half(b: Dictionary, p: Vector2) -> bool:
	return (p.y < MID_Y) == bool(b["upper"])


## One capture step for beacon `b`: progress for a team with a pilot within
## CAPTURE_RADIUS and no enemy pilot within CONTEST_RADIUS; wait while
## contested; drain when nobody of that team is there.
func _capture_step(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var near := [false, false]
	var wide := [false, false]
	for s: Ship in world.ships:
		if not s.alive:
			continue
		var d := s.global_position.distance_to(pos)
		if d < CAPTURE_RADIUS:
			near[s.team] = true
		if d < CONTEST_RADIUS:
			wide[s.team] = true
	var prog: Array = b["progress"]
	for t in 2:
		if int(b["owner"]) == t:
			prog[t] = 0.0
		elif near[t] and not wide[1 - t]:
			prog[t] = float(prog[t]) + STEP
			if float(prog[t]) >= CAPTURE_TIME:
				_capture(b, t)
				return
		elif not near[t]:
			prog[t] = maxf(0.0, float(prog[t]) - STEP)


## Team `t` captures beacon `b`.
func _capture(b: Dictionary, t: int) -> void:
	b["owner"] = t
	b["progress"] = [0.0, 0.0]
	b["pay_t"] = 0.0
	b["black_t"] = 0.0
	b["blackout_until"] = 0.0
	Game.count_usage("beacon_captures")
	TfjKit.news("%s captured the %s salvage beacon" % [Rules.TEAM_NAMES[t], "northern" if bool(b["upper"]) else "southern"])


## One step for a held beacon `b`: the payment and the blackout timers.
func _held_step(b: Dictionary) -> void:
	var owner := int(b["owner"])
	b["pay_t"] = float(b["pay_t"]) + STEP
	if float(b["pay_t"]) >= PAY_EVERY:
		b["pay_t"] = 0.0
		for s: Ship in world.ships:
			if s.alive and s.team == owner and s.profile != null and s.global_position.distance_to(b["pos"]) < PAY_RADIUS:
				s.profile.earn(PAY, "beacon")
	b["black_t"] = float(b["black_t"]) + STEP
	if float(b["black_t"]) >= BLACKOUT_EVERY:
		b["black_t"] = 0.0
		b["blackout_until"] = world.time + BLACKOUT_TIME
		TfjKit.news("Sensor blackout: %s wards in the %s half go dark" % [Rules.TEAM_NAMES[1 - owner], "northern" if bool(b["upper"]) else "southern"])


## Feature hook (PilotAI._feature_takes_over): a jungler or flex seat with
## friends nearby flies to the nearest beacon its team does not hold.
## Returns true when it set the goal.
func pilot_think(brain: PilotAI, ship: Ship) -> bool:
	var role := brain.profile.role
	if (role != "jungle" and role != "flex") or ship.hull_frac() < 0.5 or brain.fallback_t > 0.0:
		return false
	var best: Dictionary = {}
	var bd := INF
	for b: Dictionary in beacons:
		if int(b["owner"]) != ship.team:
			var d := ship.global_position.distance_to(b["pos"])
			if d < bd:
				bd = d
				best = b
	if best.is_empty():
		committed.erase(ship.uid)
		return false
	# The group rule starts a trip; the trip then lasts COMMIT seconds even if
	# the group is left behind on the way (a pilot who flew off would
	# otherwise drop the rule 4,000 units out and never arrive).
	if float(committed.get(ship.uid, 0.0)) < world.time:
		# (TEST/TUNING OPTION --tfj-beacon-any=1: count friendly ships of every
		# size, not only small ones, for the group rule above. Without it,
		# only small ships count, as the idea says.)
		var small_only: bool = str(Game.opt("tfj-beacon-any", "0")) != "1"
		if TfjKit.friends_near(world, ship, ship.global_position, AI_RADIUS, small_only) < AI_FRIENDS:
			return false
		committed[ship.uid] = world.time + COMMIT
		Game.count_usage("beacon_trips")
	brain.goal = best["pos"]
	brain.intent = ""
	brain.target = brain.targeting.pick_target(ship, PilotTargeting.engage_range(ship))
	brain.lock_target = brain.target
	return true


## Feature hook (the minimap): a ring for each beacon in its owner's colour
## (grey while nobody holds it), for both teams.
func minimap_marks(_vt: int) -> Array:
	var out: Array = []
	for b: Dictionary in beacons:
		var owner := int(b["owner"])
		out.append({"pos": b["pos"], "color": Palette.team(owner) if owner >= 0 else Palette.NEUTRAL, "shape": "diamond", "r": 4.0})
	return out


## Feature hook (the minimap): is unit `u` blacked out for the team `vt` that
## the minimap shows? An enemy contact in the half of a beacon that is
## blacking `vt` out right now.
func minimap_hides(u: Unit, vt: int) -> bool:
	if vt < 0 or u.team == vt:
		return false
	for b: Dictionary in beacons:
		if float(b["blackout_until"]) > world.time and 1 - int(b["owner"]) == vt and _in_half(b, u.global_position):
			return true
	return false
