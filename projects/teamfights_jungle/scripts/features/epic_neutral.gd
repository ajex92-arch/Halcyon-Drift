class_name EpicNeutralFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "epic" rule variant (fork
## teamfights_jungle, idea D5): a timed epic neutral at the Crossing, the
## middle of the connector, that both teams fight over. REQ-CHANGE: "Remove
## the dynamic event zones" (this is a timed spawn event).
##
## HOW IT WORKS: the variant has two values.
##   "dreadnought"  A Derelict Dreadnought (Jungle.CAMPS["dreadnought"]: 9,000
##                  hull, four guns of 3 shots per second x 15 damage and
##                  1,200 reach, up to four snub fighters, a new one every 12
##                  seconds while it fights) appears at the Crossing at 18:00
##                  and again 6 minutes after each time it dies. Every hull
##                  class can reach it: the Crossing is open space (not
##                  jungle), so big ships fly there too. Both teams get a
##                  news line and a minimap mark. The team that makes the last
##                  hit gets the "Dreadnought Boon" for 180 seconds: all its
##                  minions get +25% hull and hit enemy structures and the
##                  mothership x1.4 (never harder against ships; MinionBuffs),
##                  and every pilot of that team within 3,000 of the kill
##                  earns 250 credits.
##   "elder"        The same Dreadnought, but the first one killed after 30:00
##                  gives the "Elder Core" for 150 seconds INSTEAD of the
##                  Boon (the credits are still paid): the team's pilot hits
##                  destroy an enemy turret below 25% hull outright, and
##                  deal x1.25 to the enemy mothership while it is below 50%
##                  hull (an execute, meant to end a stalled siege). It
##                  needs the hit report Events.damage_applied, which the
##                  game only sends while Combat.emit_damage_events is on, so
##                  the module turns that on while the Core lasts (and puts
##                  it back after).
## The AI uses it (pilot_think, no skill read): a flex or jungler seat goes
## for the Dreadnought when 3 or more friendly small ships (itself counted if
## it is small) are within 6,000 of it, and then keeps going; a laner within
## 5,000 of it joins when its lane's wave is dead. They fly to a standoff
## spot, shoot the best enemy in reach first, and the Dreadnought when nothing
## else is.
## Usage counts: "epic_kills", "boon_seconds", "elder_cores",
## "elder_executes" (turrets destroyed by the Core) and "elder_ms_hits"
## (mothership hits boosted by the Core). No random numbers are drawn here
## (the Dreadnought's own facing and snub launches roll a few, like any
## derelict).
##
## WHO USES IT: FeatureRegistry installs it for --variant=epic:dreadnought or
## epic:elder. PilotAI's feature hook calls pilot_think(); the minimap calls
## minimap_marks().

## The variant key this module belongs to.
const KEY := "epic"
## Match time (seconds) of the first Dreadnought: 18:00.
const FIRST_SPAWN := 1080.0
## Seconds after a death before the next Dreadnought appears.
const RESPAWN_AFTER := 360.0
## Seconds the Boon lasts.
const BOON_TIME := 180.0
## Extra minion hull of the Boon (1.25 = +25%).
const BOON_HULL := 1.25
## Boon minions' damage multiplier against structures and motherships.
const BOON_STRUCT := 1.4
## Credits each pilot near the kill earns.
const KILL_PAY := 250.0
## A pilot within this many world units of the kill is paid.
const PAY_RADIUS := 3000.0
## Match time (seconds) after which the first kill gives the Elder Core
## ("elder" value): 30:00.
const ELDER_FROM := 1800.0
## Seconds the Elder Core lasts.
const ELDER_TIME := 150.0
## The Core destroys enemy turrets below this hull fraction outright.
const EXECUTE_BELOW := 0.25
## The Core's damage multiplier against the enemy mothership...
const MS_BONUS := 1.25
## ...while the mothership is below this hull fraction.
const MS_BELOW := 0.5
## The Crossing: the middle of the connector (world position); the actual
## spawn spot is the nearest free spot along the connector (see _find_spot).
const CROSSING := Vector2(20000, 13000)
## A flex or jungler seat needs this many friendly small ships within
## FRIEND_RADIUS of it to go.
const FRIENDS_NEEDED := 3
## See FRIENDS_NEEDED (world units).
const FRIEND_RADIUS := 6000.0
## A laner within this many world units joins when its lane wave is dead.
const LANER_RADIUS := 5000.0

## The match.
var world: World
## The shared minion buffs (for the Boon).
var buffs: MinionBuffs
## Where the Dreadnought stands (world position).
var spot := CROSSING
## The live Dreadnought, or null (kept as a Variant: it may be freed).
var dread: Variant = null
## Match time (seconds) at which the next Dreadnought appears.
var next_spawn := FIRST_SPAWN
## The Boon of each team: the match time it ends (index = team; 0 = none).
var boon_until: Array = [0.0, 0.0]
## True once the Elder Core has been given (the "elder" value gives it once).
var elder_given := false
## The team that holds the Elder Core now, or -1.
var elder_team := -1
## Match time (seconds) at which the Elder Core ends.
var elder_until := 0.0
## What Combat.emit_damage_events was before the Core turned it on.
var _prev_emit := false
## True while the Core's extra mothership damage is being applied.
var _in_extra := false
## Seat uids (ship uids) of pilots that committed to the Dreadnought.
var committed := {}
## Boon-seconds not yet added to the usage count.
var _acc := 0.0
## Seconds until the next tick work.
var _t := 0.0


## Hook the module into match `w`: pick the spot, listen for kills (and, for
## "elder", for hits) and start the tick.
func install(w: World) -> void:
	world = w
	buffs = MinionBuffs.ensure(w)
	spot = _find_spot()
	Events.unit_killed.connect(_on_unit_killed)
	if Game.variant(KEY) == "elder":
		Events.damage_applied.connect(_on_damage)
	w.tick_hooks.append(Callable(self, "tick"))


## The spawn spot: the Crossing itself if no rock is within 600 of it,
## otherwise the nearest free spot on the connector's centre line, trying
## 1,300, 1,800 and 2,400 world units down and up from the middle.
func _find_spot() -> Vector2:
	for dy: float in [0.0, 1300.0, -1300.0, 1800.0, -1800.0, 2400.0, -2400.0]:
		var p := CROSSING + Vector2(0.0, dy)
		if not world.asteroids.blocked(p, 600.0):
			return p
	return CROSSING


## The live Dreadnought as a Derelict, or null.
func live() -> Derelict:
	if dread != null and is_instance_valid(dread) and (dread as Derelict).alive:
		return dread as Derelict
	return null


## Called by World every tick: every quarter second spawn a due Dreadnought,
## end the Elder Core when it runs out, and count Boon-seconds.
func tick(dt: float) -> void:
	var active := 0
	for t in 2:
		if float(boon_until[t]) > world.time:
			active += 1
	_acc += dt * float(active)
	if _acc >= 1.0:
		Game.count_usage("boon_seconds", int(_acc))
		_acc -= float(int(_acc))
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	# Step 1: a due Dreadnought.
	if live() == null and world.time >= next_spawn:
		dread = world.spawn_derelict("epic", "dreadnought", spot)
		TfjKit.apply_test_hull(dread as Derelict)
		TfjKit.news("A Derelict Dreadnought has appeared at the Crossing!")
	# Step 2: the Elder Core running out.
	if elder_team >= 0 and world.time >= elder_until:
		_end_elder()
	# Step 3: forget committed pilots when there is nothing to go for.
	if live() == null and not committed.is_empty():
		committed.clear()


## Events.unit_killed: the Dreadnought died (reward its killer's team).
func _on_unit_killed(unit: Node, info: RefCounted) -> void:
	if not (unit is Derelict) or (unit as Derelict).camp_id != "epic":
		return
	var di := info as DamageInfo
	var team := di.source_team if di != null else Rules.NEUTRAL
	next_spawn = world.time + RESPAWN_AFTER
	Game.count_usage("epic_kills")
	if team < 0 or team > 1:
		return
	# Step 1: credits for every pilot of the killing team near the kill.
	for s: Ship in world.ships:
		if s.alive and s.team == team and s.profile != null and s.global_position.distance_to((unit as Derelict).global_position) < PAY_RADIUS:
			s.profile.earn(KILL_PAY, "epic")
	# Step 2: the Elder Core (first kill after ELDER_FROM, "elder" value) or
	# the Boon.
	# (TEST OPTION --tfj-elder-from=SECONDS replaces ELDER_FROM, so a short
	# smoke run can reach the Elder Core; without it this is ELDER_FROM.)
	if Game.variant(KEY) == "elder" and world.time >= float(Game.opt("tfj-elder-from", ELDER_FROM)) and not elder_given:
		elder_given = true
		_start_elder(team)
	else:
		boon_until[team] = world.time + BOON_TIME
		buffs.add_source("boon:%d" % team, team, world.time + BOON_TIME, BOON_HULL, BOON_STRUCT)
		TfjKit.news("%s slew the Dreadnought: Dreadnought Boon for 3:00" % Rules.TEAM_NAMES[team])


## Give team `team` the Elder Core for ELDER_TIME seconds.
func _start_elder(team: int) -> void:
	elder_team = team
	elder_until = world.time + ELDER_TIME
	_prev_emit = world.combat.emit_damage_events
	world.combat.emit_damage_events = true
	Game.count_usage("elder_cores")
	TfjKit.news("%s slew the Dreadnought: the Elder Core for 2:30" % Rules.TEAM_NAMES[team])


## End the Elder Core.
func _end_elder() -> void:
	elder_team = -1
	world.combat.emit_damage_events = _prev_emit


## Events.damage_applied (only connected for "elder", and only sent while the
## Core has switched the reports on): while a team holds the Elder Core, its
## pilots' hits destroy enemy turrets below 25% hull and hit the enemy
## mothership x1.25 below 50% hull.
func _on_damage(target: Node, info: RefCounted, amount: float, _hull_dmg: float) -> void:
	if elder_team < 0 or _in_extra:
		return
	var di := info as DamageInfo
	var tu := target as Unit
	if di == null or tu == null or not tu.alive or not di.source_is_pilot or di.source_team != elder_team or tu.team != 1 - elder_team:
		return
	if tu.kind == Unit.K_TURRET and tu.hull_frac() < EXECUTE_BELOW:
		Game.count_usage("elder_executes")
		world.combat.kill(tu, di)
	elif tu.kind == Unit.K_MOTHERSHIP and tu.hull_frac() < MS_BELOW:
		_in_extra = true
		tu.take_hit(di, amount * (MS_BONUS - 1.0))
		_in_extra = false
		Game.count_usage("elder_ms_hits")


## Feature hook (PilotAI._feature_takes_over): go for the Dreadnought by the
## AI rules in the header. Returns true when it set the goal and target.
func pilot_think(brain: PilotAI, ship: Ship) -> bool:
	var d := live()
	if d == null or ship.hull_frac() < 0.5 or brain.fallback_t > 0.0:
		return false
	var go := committed.has(ship.uid)
	var role := brain.profile.role
	if not go:
		if role == "flex" or role == "jungle":
			var n := TfjKit.friends_near(world, ship, ship.global_position, FRIEND_RADIUS, true) + (1 if ship.is_small() else 0)
			go = n >= FRIENDS_NEEDED
			if go:
				committed[ship.uid] = true
		elif ship.global_position.distance_to(d.global_position) < LANER_RADIUS:
			go = TfjKit.minions_on_lane(world, ship.team, brain.goals.lane_id()) == 0
	if not go:
		return false
	TfjKit.attack_derelict(brain, ship, d)
	return true


## Feature hook (the minimap): the Dreadnought's mark, a gold diamond, for
## both teams.
func minimap_marks(_vt: int) -> Array:
	var d := live()
	if d == null:
		return []
	return [{"pos": d.global_position, "color": Color(1.0, 0.8, 0.2), "shape": "diamond", "r": 5.0}]
