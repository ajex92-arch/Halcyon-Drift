class_name TeamDefense
extends RefCounted
## WHAT THIS IS: the team's alarm bell. When enemy big ships (frigates and
## capital ships) push into our base, it calls every AI pilot nearby home
## to fight them, and calls off our own siege.
##
## HOW IT WORKS: once a second (tick) it looks for enemy big ships that we
## can see within DEFEND_RADIUS (7,000 world units) of our mothership's
## hull. The closest one leads the push; it and every other one within
## 5,000 units of it make up the push. (Once our mothership is parked up a
## lane, more than 2,500 from its home spot, the search radius is cut to
## FORWARD_DEFEND_RADIUS, 4,000, so a fight in the middle of the map is not
## "an attack on the base".) With 2 or more ships in the push, the alarm
## goes off, except that while our own siege is on it takes a push within
## SIEGE_DROP_RADIUS (2,500) of our hull:
##   - TeamState.defend_point is set on our side of the push (the place
##     pilots come to fight), and the call lasts 12 seconds
##     (TeamState.defend_until). It is renewed every second while the push
##     goes on.
##   - when the call is new (it was not already on), a message goes to
##     the message feed.
##   - our own siege is called off, unless it is in its "assault" phase and
##     the enemy mothership is under 35% hull (about to win).
## It runs for both teams, whoever the admiral is (AI or human). (Playtest:
## both fleets sieged at once, and the first to arrive won the race for a
## base while the defenders were away.)
##
## WHO USES IT: TeamState makes one (TeamState.defense), runs tick() every
## tick and forwards defending() and _update_defense() here. PilotGoals
## sends AI pilots to TeamState.defend_point; AdmiralSiege won't start a
## siege while defending; AdmiralAI and AdmiralMothershipMover check
## defending() too.

## How close (world units, to our mothership's hull) enemy big ships must
## be to count as attacking the base. Our inner ore nodes are about 7,200
## (mid) and 12,100 (top and bottom) from the hull. A tuned number: a
## feature module may change it for one match ("defend_radius", see
## Rules.tune).
const DEFEND_RADIUS := 7000.0
## The radius used instead (at most) while our mothership is parked away
## from its home spot (more than 2,500 from it): 4,000 world units. From
## 20:00 the AI parks it 35% up a lane, where 7,000 from its hull reaches
## the middle of the map.
const FORWARD_DEFEND_RADIUS := 4000.0
## While our siege is on, the push must be this close to our hull (world
## units) to sound the alarm and drop the siege. Our siege fleet gathers
## about 3,000 from our own mothership once both motherships are parked
## mid, so an enemy fleet meeting it there is a fight, not an attack on the
## base.
const SIEGE_DROP_RADIUS := 2500.0

## The team this part belongs to (we read and set its defend and siege
## fields). It is reached through a weak link: see `_ts_ref`.
var ts: TeamState:
	get:
		return _ts_ref.get_ref() as TeamState

## A "weak" link to the team. TeamState holds this part with a normal
## (strong) link. If the part held the team strongly too, each would keep
## the other alive forever and Godot could never free them (a memory
## leak). A weak link points at the team without keeping it alive.
var _ts_ref: WeakRef
## Seconds until the next check. It starts at 0, so the first check runs
## on the first tick; after that it runs once a second.
var check_t := 0.0


## Remember our team (through a weak link). TeamState makes this part once.
func _init(owner: TeamState) -> void:
	_ts_ref = weakref(owner)


## Is the defend call on at match time `now` (seconds)? True when a
## defend point has been set and its time has not run out.
func defending(now: float) -> bool:
	return ts.defend_point != Vector2.INF and now < ts.defend_until


## Count down to the next check by one tick of `dt` seconds, and run the
## check (update) once a second.
func tick(dt: float) -> void:
	check_t -= dt
	if check_t <= 0.0:
		check_t = 1.0
		update()


## The check: are enemy big ships pushing into our base? If so, set the
## defend point and call off our siege (see HOW IT WORKS at the top).
func update() -> void:
	var world := ts.world
	var team := ts.team
	var ms: Mothership = world.mothership(team)
	if ms == null or not ms.alive:
		return
	# Step 1: find enemy big ships we can see past our inner nodes
	# (DEFEND_RADIUS), and the closest of them (the lead). Pressure on an
	# inner turret is answered by that lane's pilots instead
	# (PilotAI._turret_under_attack). Playtest: at 14,000 every inner node
	# was inside the radius, so frigates working those lanes kept BOTH
	# teams "defending" for whole matches; and since defending blocks and
	# cancels sieges, no siege ever started.
	var seen: Array[Vector2] = []
	var lead := Vector2.INF
	var lead_d := INF
	var radius := float(Rules.tune("defend_radius", DEFEND_RADIUS))
	# Away from home "under attack" means close to the hull (see
	# FORWARD_DEFEND_RADIUS); never wider than the home radius.
	if ms.global_position.distance_to(world.map.mothership_pos[team]) > 2500.0:
		radius = minf(radius, FORWARD_DEFEND_RADIUS)
	for s: Ship in world.ships:
		if s.team != team and s.alive and s.size_class >= Rules.SIZE_LARGE and s.visible_to(team):
			var d := ms.hull_dist(s.global_position)
			if d < radius:
				seen.append(s.global_position)
				if d < lead_d:
					lead_d = d
					lead = s.global_position
	# Step 2: the push is the lead plus whoever is within 5,000 of it (two
	# frigates on different lanes are two lane fights, not an attack on the
	# base). Fewer than 2 ships: no alarm.
	var threat := 0
	var centre := Vector2.ZERO
	for p in seen:
		if p.distance_to(lead) < 5000.0:
			threat += 1
			centre += p
	if threat < 2:
		return
	centre /= float(threat)
	# With our siege on, only a push right at our hull (SIEGE_DROP_RADIUS)
	# counts: otherwise the enemy fleet meeting our siege fleet near our own
	# mothership would cancel the siege (and pull every pilot off the siege
	# goal, PilotGoals step 6) within seconds.
	if ts.siege_lane != "" and ms.hull_dist(centre) > SIEGE_DROP_RADIUS:
		return
	# Step 3: meet them where they are, 1,500 units from the middle of the
	# push towards our mothership. (Playtest: a point at the hull left the
	# whole team idling there while frigates took an inner turret 8,000 to
	# 12,000 away.) When the push is right at the hull (under 2,500), the
	# point is between the mothership and them instead, at most
	# half its length + 1,800 from its centre.
	var near := centre.move_toward(ms.global_position, 1500.0)
	if ms.hull_dist(centre) < 2500.0:
		near = ms.global_position + (centre - ms.global_position).limit_length(ms.half_len + 1800.0)
	# Step 4: sound the alarm (the message only when it is new) and keep
	# the call on for 12 more seconds.
	if not defending(world.time):
		Events.feed.emit("%s capital ships are pushing into the %s base: all pilots defend!" % [Rules.TEAM_NAMES[1 - team], Rules.TEAM_NAMES[team]], "team", team)
	ts.defend_point = near
	ts.defend_until = world.time + 12.0
	# Step 5: call off our own siege, unless our assault is about to win.
	var ems: Mothership = world.mothership(Rules.enemy_of(team))
	if ts.siege_lane != "" and not (ts.siege_phase == "assault" and ems != null and ems.hull_frac() < 0.35):
		ts.siege_lane = ""
		ts.siege_phase = ""
