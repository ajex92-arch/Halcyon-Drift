class_name JungleScaleFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "jungle_scale" rule variant (fork
## teamfights_jungle, idea D3). The jungle grows with the match: camps pay
## more and fight harder as the minutes pass, and after 20:00 the AI
## junglers ambush hurt enemy pilots near the jungle exits. REQ-CHANGE: none.
##
## HOW IT WORKS:
##   - Every 2 seconds it sets the tuned number "derelict_reward_mult" to
##     1 + 0.08 for every 5 minutes of match time, so every camp's reward
##     (Economy) grows by 8% per 5 minutes.
##   - Every derelict (and snub fighter) is scaled up as the match goes on:
##     hull, and the damage of its guns, x(1 + 0.05 per 5 minutes). A derelict
##     that is made later (a camp that comes back) is scaled when it is first
##     seen. The scaling is applied in steps of at least 1%.
##   - The AI rule (pilot_think): after 20:00 a jungler with most of its hull
##     "gangs" a lane when (1) that lane's enemy wave has gone past the
##     middle node (some enemy minion on it is nearer our end than the lane's
##     middle) and (2) a visible enemy pilot below 50% hull is within 5,000 of
##     a jungle exit of that lane (and within 8,000 of the jungler). The
##     jungler then hunts that pilot instead of clearing camps. It never
##     reads skill. No random numbers are drawn.
## Usage counts: "gank_attempts" (a jungler starts a hunt; at most one per
## jungler per 25 seconds).
##
## WHO USES IT: FeatureRegistry installs it for --variant=jungle_scale:on.
## PilotAI's feature hook calls pilot_think(). Economy reads the tuned
## reward multiplier.

## The variant key this module belongs to.
const KEY := "jungle_scale"
## Extra camp reward per 5 minutes of match time (0.08 = +8%).
const REWARD_PER_5 := 0.08
## Extra derelict hull and gun damage per 5 minutes (0.05 = +5%).
const STRENGTH_PER_5 := 0.05
## Match time (seconds) from which the AI junglers gank: 20:00.
const GANK_FROM := 1200.0
## An enemy pilot below this hull fraction is a gank target.
const GANK_HULL := 0.5
## The enemy pilot must be within this many world units of a jungle exit.
const EXIT_RANGE := 5000.0
## ...and within this many world units of the jungler.
const GANK_REACH := 8000.0
## Seconds before the same jungler can count another gank attempt.
const GANK_COOLDOWN := 25.0
## Seconds between two refreshes.
const STEP := 2.0

## The match.
var world: World
## Unit uid -> the strength factor already applied to that derelict or snub.
var scaled := {}
## Jungler key (team * 100 + seat) -> the earliest match time of its next
## counted gank attempt.
var gank_next := {}
## For each team, lane id -> true when the ENEMY wave on that lane is past the
## middle node (refreshed every STEP seconds).
var past_middle: Array = [{}, {}]
## Lane id -> the jungle exits (world positions on that lane's centre line).
var exits := {}
## Seconds until the next refresh.
var _t := 0.0


## Hook the module into match `w`: list the jungle exits of each lane and
## start the tick.
func install(w: World) -> void:
	world = w
	for lane: String in MapLayout.LANE_ORDER:
		var pts: PackedVector2Array = w.map.lanes[lane]
		var list: Array = []
		for e: Dictionary in w.map.entrances:
			if Util.dist_to_polyline(e["lane"], pts) < 600.0:
				list.append(e["lane"])
		exits[lane] = list
	w.tick_hooks.append(Callable(self, "tick"))


## Called by World every tick: every STEP seconds update the reward number,
## scale the derelicts and refresh which enemy waves are past the middle.
func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = STEP
	var fives := world.time / 300.0
	Game.tunables["derelict_reward_mult"] = 1.0 + REWARD_PER_5 * fives
	_scale_monsters(1.0 + STRENGTH_PER_5 * fives)
	for t in 2:
		past_middle[t] = _waves_past_middle(t)


## Scale every derelict and snub fighter up to strength factor `f`.
func _scale_monsters(f: float) -> void:
	for u: Unit in world.monsters:
		if not u.alive:
			continue
		var had := float(scaled.get(u.uid, 1.0))
		if f / had < 1.01:
			continue
		var r := f / had
		u.hull_max *= r
		u.hull *= r
		var mounts: Array = []
		if u is Derelict:
			mounts = (u as Derelict).mounts
		elif u is SnubFighter:
			mounts = [(u as SnubFighter).mount]
		for m: WeaponMount in mounts:
			# Each gun gets its own copy of the weapon data (the shared table
			# must not change) with the damage scaled up.
			var d: Dictionary = m.def.duplicate()
			d["dmg"] = float(d["dmg"]) * r
			m.def = d
		scaled[u.uid] = f


## For team `t`: lane id -> true when an ENEMY minion on that lane is nearer
## team `t`'s end than the lane's middle (the enemy wave is "past the middle
## node").
func _waves_past_middle(t: int) -> Dictionary:
	var out := {}
	for lane: String in MapLayout.LANE_ORDER:
		var pts := MapLayout.lane_points(lane, t)
		var half := Util.polyline_length(pts) * 0.5
		for m: Minion in world.minions:
			if m.alive and m.team != t and m.lane == lane and float(Util.project_on_polyline(m.global_position, pts)["s"]) < half:
				out[lane] = true
				break
	return out


## The best gank target for jungler `ship` of team `team`: the nearest visible
## enemy pilot below GANK_HULL hull, within EXIT_RANGE of a jungle exit of a
## lane whose enemy wave is past the middle, and within GANK_REACH of the
## jungler. null when there is none.
func _target_for(team: int, ship: Ship) -> Ship:
	var best: Ship = null
	var bd := GANK_REACH
	for s: Ship in world.ships:
		if not s.alive or s.team == team or s.hull_frac() >= GANK_HULL or not s.visible_to(team):
			continue
		var d := s.global_position.distance_to(ship.global_position)
		if d >= bd:
			continue
		for lane in past_middle[team]:
			for ex: Vector2 in exits[lane]:
				if ex.distance_to(s.global_position) < EXIT_RANGE:
					best = s
					bd = d
					break
			if best == s:
				break
	return best


## Feature hook (PilotAI._feature_takes_over): after GANK_FROM a jungler with
## most of its hull hunts a gank target (see HOW IT WORKS). Returns true when
## it set the goal and target.
func pilot_think(brain: PilotAI, ship: Ship) -> bool:
	if brain.state != "jungle" or brain.profile.role != "jungle" or world.time < GANK_FROM:
		return false
	if ship.hull_frac() < 0.6 or brain.fallback_t > 0.0:
		return false
	var prey := _target_for(brain.profile.team, ship)
	if prey == null:
		return false
	var key := brain.profile.team * 100 + brain.profile.slot
	if world.time >= float(gank_next.get(key, 0.0)):
		Game.count_usage("gank_attempts")
		gank_next[key] = world.time + GANK_COOLDOWN
	brain.target = prey
	brain.lock_target = prey
	brain.intent = "prey"
	brain.goal = prey.global_position
	return true
