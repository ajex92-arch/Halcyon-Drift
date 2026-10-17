class_name WorldVisibility
extends RefCounted
## WHAT THIS IS: the "who can see what" part of the World (the fog of
## war). It decides which units each team can see, and which units are
## drawn on the screen.
##
## HOW IT WORKS: every 0.1 s it updates one team, taking turns, so each
## team is updated 5 times a second (Rules.VISION_HZ):
##   1. viewers(): list every unit of that team that can see, with its
##      sight radius (bigger with the Advanced Sensors Array facility,
##      much smaller near an enemy jammer).
##   2. Vision.update_team() lights the fog from that list.
##   3. refresh(): mark each unit as seen or unseen by that team, then
##      show or hide it on screen for the human.
## An enemy is seen if it stands in lit fog, or if it is touching one of
## our units (within Rules.VISION_TOUCH = 350 world units of its edge).
## Wards are stealthy: they are only seen by a Scout Ping reveal or by a
## unit close by (Structures.WARD "stealth_radius" = 500).
##
## A unit remembers who sees it in a "bitmask": one whole number used as a
## row of on/off switches, one per team. Switch 0 (value 1) is Aurelian,
## switch 1 (value 2) is Cinder; `1 << team` makes the switch for one team.
## Unit.visible_mask = seen right now; Unit.seen_mask = ever seen.
##
## WHO USES IT: World makes one (World.visibility) and calls tick() every
## tick. WorldSetup calls refresh() for both teams at the start, and
## World._viewers() forwards to viewers().

## The world whose units we check.
var world: World
## Seconds until the next vision update (counts down every tick).
var vision_t := 0.0
## Whose turn it is next: 0 = Aurelian, 1 = Cinder.
var vision_team := 0
## A reusable list the spatial hash fills with nearby units.
var scratch: Array = []


## Remember the world. World makes this part once.
func _init(w: World) -> void:
	world = w


## Called by World every tick. When the timer runs out, update one team's
## fog and visibility, then switch to the other team for next time.
func tick(dt: float) -> void:
	vision_t -= dt
	if vision_t <= 0.0:
		vision_t = 1.0 / (Rules.VISION_HZ * 2.0)
		world.vision.update_team(vision_team, viewers(vision_team))
		refresh(vision_team)
		vision_team = 1 - vision_team


## What lights the fog for `team`: one Vector3(x, y, radius) per live unit
## of the team that can see (vision_radius above 0). Non-ship units see
## 20% further with the Advanced Sensors Array facility ("sensors"); ships
## already include that bonus in their own vision_radius. A unit within
## 1400 world units of a jamming enemy ship sees only a quarter as far.
func viewers(team: int) -> Array:
	# First find every enemy ship that is jamming right now.
	var out: Array = []
	var jammers: Array = []
	for s in world.ships:
		if s.alive and s.team != team and s.jam_t > 0.0:
			jammers.append(s.global_position)
	var sensors := world.teams[team].facilities.has("sensors")
	# Then list our units that can see, with their sight radius.
	for u in world.units:
		if not u.alive or u.team != team or u.vision_radius <= 0.0:
			continue
		var r := u.vision_radius
		if sensors and u.kind != Unit.K_SHIP:
			r *= 1.2
		# One jammer nearby is enough to cut sight to a quarter.
		for jp: Vector2 in jammers:
			if jp.distance_to(u.global_position) < 1400.0:
				r *= 0.25
				break
		# Feature hook (World.vision_mods): a feature may change this unit's
		# sight radius; 0 or less means it lights nothing.
		if not world.vision_mods.is_empty():
			for f: Callable in world.vision_mods:
				r = float(f.call(team, u, r))
			if r <= 0.0:
				continue
		out.append(Vector3(u.global_position.x, u.global_position.y, r))
	# Feature hook (World.vision_sources): extra sight sources of this team
	# that are still running, for example a Sensor Sweep.
	for sv: Dictionary in world.vision_sources:
		if int(sv["team"]) == team and world.time < float(sv["until"]):
			var sp: Vector2 = sv["pos"]
			out.append(Vector3(sp.x, sp.y, float(sv["r"])))
	return out


## Refresh every live unit's "seen by `team`" switch, and its on-screen
## state when `team` is the team the screen shows (or the screen shows
## everything).
func refresh(team: int) -> void:
	var bit := 1 << team
	for u in world.units:
		if not u.alive:
			continue
		# Our own units: always seen by us.
		if u.team == team:
			u.visible_mask |= bit
		else:
			# Others: seen if in lit fog, or touching one of our units.
			# Wards follow their own stealth rule instead.
			var seen := world.vision.is_visible(team, u.global_position)
			if u.kind == Unit.K_WARD:
				seen = ward_spotted(u, team)
			elif not seen:
				seen = touching(u, team, Rules.VISION_TOUCH)
			# Switch it on (and remember it was seen once), or off.
			if seen:
				u.visible_mask |= bit
				u.seen_mask |= bit
			else:
				u.visible_mask &= ~bit
		# (--sim-only draws nothing, so it needs no on-screen state.)
		if (team == world.viewer_team or world.viewer_team < 0) and not Game.sim_only:
			apply_draw_visibility(u)


## True if a live unit of `team` is close to unit `u`: their edges are
## less than `r` world units apart (centre distance under r plus both
## radii). Looks a bit wider (r + 200) in the spatial hash to be safe.
func touching(u: Unit, team: int, r: float) -> bool:
	for o: Unit in world.unit_hash.query(u.global_position, r + 200.0, scratch):
		if o.team == team and o.alive and o.global_position.distance_to(u.global_position) < r + o.radius + u.radius:
			return true
	return false


## True if `team` can see ward `ward`: it lies inside one of the team's
## active reveal circles (Scout Ping, Vision.reveals), or one of the team's
## units is within the ward stealth radius (500) of it.
func ward_spotted(ward: Unit, team: int) -> bool:
	for rv: Dictionary in world.vision.reveals:
		if int(rv["team"]) == team and ward.global_position.distance_to(rv["pos"]) < float(rv["r"]):
			return true
	return touching(ward, team, float(Structures.WARD["stealth_radius"]))


## Show or hide unit `u` on screen for the human's view (World.viewer_team).
func apply_draw_visibility(u: Unit) -> void:
	# A spectator (viewer_team -1) sees everything.
	if world.viewer_team < 0:
		u.visible = true
		return
	# Structures (turrets, repair bays, motherships) stay drawn once seen,
	# as a last-known "ghost"; everything else only while seen right now.
	if u.is_structure():
		u.visible = (u.seen_mask & (1 << world.viewer_team)) != 0 or u.team == world.viewer_team
	else:
		u.visible = u.visible_to(world.viewer_team)
