class_name SalvageCoreFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "salvage_core" rule variant (fork
## teamfights_jungle, idea D2). In each quarter of the jungle the carrier
## camp is replaced by a Derelict Battleship (a bigger, tougher camp), and
## whoever lands the last hit on it carries a Salvage Core for a while that
## makes the friendly minions near them stronger. REQ-CHANGE: none (a
## permanent camp that comes back after a normal wait, not an event).
##
## HOW IT WORKS:
##   - At match start install() takes, in every quarter, the carrier camp
##     nearest the connector (the original "_b" camp; the extra camp of the
##     camp4 variant is never used) and makes it a "battleship"
##     (Jungle.CAMPS["battleship"]): 4,000 hull, three guns of 2 shots per
##     second x 12 damage and 1,000 reach, up to three snub fighters (a new
##     one every 10 seconds while it fights), a reward of 450 credits shared
##     by damage as for every camp (with the usual 25% last-hit bonus), and
##     300 seconds before it comes back. JungleDirector spawns it again by
##     itself, as the new type.
##   - The pilot who makes the last hit becomes the Core carrier for 120
##     seconds (CORE_TIME): their ship glows gold, and every friendly minion
##     within 2,500 of them gets +20% hull and hits enemy structures and the
##     mothership x1.4 (never harder against ships). MinionBuffs does the
##     minion part. The core is lost when the carrier dies or docks, and the
##     enemy pilot who destroys the carrier earns 150 credits extra.
##   - The AI uses it: a jungler takes the Battleship when two or more
##     friendly small ships are within 3,000 of it, or at any time after
##     18:00 (allow_camp keeps a lone jungler off it before that; pilot_think
##     steers the jungler to it); a laner on a lane next to its quarter joins
##     the fight when a friendly ship is fighting it and the laner is within
##     4,000. No skill is read.
## Usage counts: "cores_carried" (cores given out) and "core_minion_seconds"
## (minion-seconds under a core). No random numbers are drawn (the
## replacement derelicts use the game's own spawn, which rolls their facing,
## but only while this variant is on).
##
## WHO USES IT: FeatureRegistry installs it for --variant=salvage_core:on.
## PilotAI's feature hook calls pilot_think(); PilotGoals.think_jungle calls
## allow_camp().

## The variant key this module belongs to.
const KEY := "salvage_core"
## Seconds a Core lasts.
const CORE_TIME := 120.0
## Friendly minions within this many world units of the carrier are helped.
const MINION_RADIUS := 2500.0
## Extra hull for helped minions (1.2 = +20%).
const HULL_MULT := 1.2
## Damage multiplier of helped minions against structures and motherships.
const STRUCT_MULT := 1.4
## Credits the enemy who destroys the carrier earns.
const KILL_BONUS := 150.0
## The colour multiplier that makes the carrier's ship glow gold.
const GOLD := Color(1.6, 1.3, 0.5)
## Match time (seconds) after which a lone jungler may take the Battleship:
## 18:00.
const LONE_OK_TIME := 1080.0
## A jungler needs two small friendly ships within this many world units to
## take the Battleship before LONE_OK_TIME.
const GROUP_RADIUS := 3000.0
## A laner joins a fight on the Battleship when within this many world units.
const HELP_RADIUS := 4000.0

## The match.
var world: World
## The shared minion buffs.
var buffs: MinionBuffs
## The live Battleships (refreshed by tick()).
var battleships: Array = []
## The Cores now carried: ship uid -> {"ship": the Ship, "until": match time}.
var cores := {}
## Uids of the Battleships already weakened by the --tfj-hull-scale test
## option (unused without it).
var tested := {}
## Seconds until the next refresh.
var _t := 0.0


## Hook the module into match `w`: turn the carrier camps into Battleships,
## listen for kills, and start the tick.
func install(w: World) -> void:
	world = w
	buffs = MinionBuffs.ensure(w)
	_convert_camps()
	Events.unit_killed.connect(_on_unit_killed)
	w.tick_hooks.append(Callable(self, "tick"))


## Turn the carrier camp nearest the connector in every quarter into a
## "battleship" camp, replacing the derelict that stands there now. Does
## nothing when the match has no jungle camps (the --no-jungle test switch).
func _convert_camps() -> void:
	var jd := world.jungle_director
	# Step 1: per quarter, the carrier camp nearest the centre line (the
	# connector), ignoring the camp4 variant's extra "_d" camps.
	var best := {}
	for id: String in jd.camps:
		var info: Dictionary = jd.camps[id]["info"]
		if str(info["type"]) != "carrier" or id.ends_with("_d"):
			continue
		var q := str(info["quad"])
		var x := absf((info["pos"] as Vector2).x - MapLayout.CX)
		if not best.has(q) or x < absf(((jd.camps[best[q]]["info"] as Dictionary)["pos"] as Vector2).x - MapLayout.CX):
			best[q] = id
	# Step 2: change each one's type and swap the derelict standing there.
	for q in best:
		var id: String = best[q]
		var e: Dictionary = jd.camps[id]
		var info: Dictionary = e["info"]
		var u: Variant = e["unit"]
		if u != null and is_instance_valid(u) and (u as Unit).alive:
			world.combat.kill_silently(u as Unit)
			info["type"] = "battleship"
			e["unit"] = world.spawn_derelict(id, "battleship", info["pos"])
		else:
			info["type"] = "battleship"


## Called by World every tick: every quarter second refresh the list of live
## Battleships and end Cores that ran out.
func tick(_dt: float) -> void:
	_t -= _dt
	if _t > 0.0:
		return
	_t = 0.25
	battleships.clear()
	var test_scale := TfjKit.test_hull_scale() != 1.0
	for u: Unit in world.monsters:
		if u.alive and u is Derelict and (u as Derelict).ctype == "battleship":
			battleships.append(u)
			# Test option only: weaken each new Battleship once.
			if test_scale and not tested.has(u.uid):
				tested[u.uid] = true
				TfjKit.apply_test_hull(u as Derelict)
	for uid in cores.keys():
		var c: Dictionary = cores[uid]
		var s: Variant = c["ship"]
		if world.time >= float(c["until"]) or s == null or not is_instance_valid(s) or not (s as Ship).alive:
			_drop(uid)


## Give the Core to `ship` (the pilot who made the last hit).
func _grant(ship: Ship) -> void:
	_drop(ship.uid)
	cores[ship.uid] = {"ship": ship, "until": world.time + CORE_TIME}
	buffs.add_source("core:%d" % ship.uid, ship.team, world.time + CORE_TIME, HULL_MULT, STRUCT_MULT, ship, MINION_RADIUS, "core_minion_seconds")
	ship.modulate = GOLD
	Game.count_usage("cores_carried")
	TfjKit.news("%s carries a Salvage Core" % ship.profile.callsign, ship.team)


## End the Core of ship uid `uid` (it runs out, or the carrier is lost).
func _drop(uid: int) -> void:
	if not cores.has(uid):
		return
	var s: Variant = (cores[uid] as Dictionary)["ship"]
	if s != null and is_instance_valid(s):
		(s as Ship).modulate = Color.WHITE
	buffs.remove_source("core:%d" % uid)
	cores.erase(uid)


## Events.unit_killed: a Battleship died (its last-hitter gets the Core), or
## a Core carrier died (the killer earns KILL_BONUS and the Core is lost).
func _on_unit_killed(unit: Node, info: RefCounted) -> void:
	var di := info as DamageInfo
	if unit is Derelict and (unit as Derelict).ctype == "battleship":
		var killer := di.source_profile as PilotProfile
		if killer != null and killer.ship != null and is_instance_valid(killer.ship) and killer.ship.alive:
			_grant(killer.ship)
	elif unit is Ship and cores.has((unit as Ship).uid):
		var kp := di.source_profile as PilotProfile
		if kp != null and kp.team != (unit as Ship).team:
			kp.earn(KILL_BONUS, "core")
		_drop((unit as Ship).uid)


## Feature hook (PilotAI._feature_takes_over): the AI rules for the
## Battleship. A jungler picks it as its next camp when allowed (it only
## sets the brain's camp and lets the normal jungle job fly there); a laner
## next to its quarter joins a fight on it. Returns true only when it set the
## goal and target itself.
func pilot_think(brain: PilotAI, ship: Ship) -> bool:
	# Drop Battleships that died since the last refresh (a freed unit cannot
	# be put in a typed variable).
	for i in range(battleships.size() - 1, -1, -1):
		var bv: Variant = battleships[i]
		if not is_instance_valid(bv) or not (bv as Derelict).alive:
			battleships.remove_at(i)
	if battleships.is_empty():
		return false
	if brain.state == "jungle" and brain.profile.role == "jungle":
		_jungler_pick(brain, ship)
		return false
	if brain.state == "lane" and ship.hull_frac() >= 0.5 and brain.fallback_t <= 0.0:
		for b: Derelict in battleships:
			if _helps(brain, ship, b):
				TfjKit.attack_derelict(brain, ship, b)
				return true
	return false


## A jungler without a live camp chooses the nearest Battleship (its own
## half of the map first) when it may take it and has most of its hull.
func _jungler_pick(brain: PilotAI, ship: Ship) -> void:
	if brain.camp != null and is_instance_valid(brain.camp) and brain.camp.alive:
		return
	if ship.hull_frac() < 0.6 or not _may_take(ship):
		return
	var best: Derelict = null
	var bd := INF
	for b: Derelict in battleships:
		var mine := (b.global_position.x < MapLayout.CX) == (ship.team == Rules.HALCYON)
		var d := b.global_position.distance_to(ship.global_position) + (0.0 if mine else 6000.0)
		if d < bd:
			bd = d
			best = b
	if best != null:
		brain.camp = best


## May this jungler take a Battleship now? Two or more friendly small ships
## within GROUP_RADIUS of it, or the match is past LONE_OK_TIME.
func _may_take(ship: Ship) -> bool:
	return world.time >= LONE_OK_TIME or TfjKit.friends_near(world, ship, ship.global_position, GROUP_RADIUS, true) >= 2


## Should laner `ship` help with Battleship `b`? A friendly pilot ship is
## fighting it, `ship` is within HELP_RADIUS of it, and `ship`'s lane is one
## of the two lanes next to its quarter (the flex pilot has no lane).
func _helps(brain: PilotAI, ship: Ship, b: Derelict) -> bool:
	if not b.is_engaged() or b.target.team != ship.team or b.target.kind != Unit.K_SHIP:
		return false
	if ship.global_position.distance_to(b.global_position) > HELP_RADIUS:
		return false
	if brain.profile.role == "flex":
		return true
	var top_half := b.camp_id.begins_with("tl") or b.camp_id.begins_with("tr")
	var lane := brain.goals.lane_id()
	return lane == "mid" or lane == ("top" if top_half else "bot")


## Feature hook (PilotGoals.think_jungle): may jungler `ship` clear camp
## `d`? A lone jungler may not take a Battleship before LONE_OK_TIME.
func allow_camp(_brain: PilotAI, ship: Ship, d: Derelict) -> bool:
	if d.ctype != "battleship":
		return true
	return _may_take(ship)
