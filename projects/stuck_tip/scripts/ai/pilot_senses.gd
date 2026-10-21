class_name PilotSenses
extends RefCounted
## WHAT THIS IS: the "eyes" of an AI pilot (a part of PilotAI): small
## questions about what is around a point, which the other parts use to make
## decisions. "Are we outnumbered here?", "Are our minions soaking up that
## turret's fire?", "Is a turret shooting at me?"
##
## HOW IT WORKS: most questions ask the world's spatial hash for nearby
## units and count them. (The spatial hash, world.unit_hash, is a grid laid
## over the map: asking it for units near a point only looks in the few
## grid cells around that point, which is fast. It can also return units a
## little outside the circle. Some questions here check the exact distance
## themselves; odds, minions_tanking and turret_under_attack accept that
## small slack.) When ships are counted as "odds", each ship counts
## by its size: small 1, medium 2, large 3, capital 4. Allies add, enemies
## subtract, and enemies we can't see don't count.
##
## WHO USES IT: PilotAI._think() (odds, turret_targeting), PilotGoals
## (turret_under_attack, allies_near, minions_tanking) and PilotTargeting
## (odds_at, enemy_turret_at, minions_near, minions_tanking,
## minions_at_hull). PilotAI._turret_under_attack() forwards here.
##
## Words used here:
##   tanking  our minions stand inside an enemy turret's range, so the
##            turret shoots them instead of us (and, because our minions
##            are near, our ships deal full damage to it).

## The pilot brain this part belongs to (we read its world). It is reached
## through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef
## A reusable list that the spatial hash fills with nearby units (reusing
## one list avoids making a new one for every question).
var _scratch: Array = []


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## The odds if we join a fight at point p: allies minus enemies (pilot
## ships within 2,000 of p, weighted by size), counting ourselves as joining
## even if we're not there yet. Above 0 = we'd outnumber them.
func odds_at(p: Vector2, ship: Ship) -> int:
	var brain := ai
	var score := 0
	var me_counted := false
	for u: Unit in brain.world.unit_hash.query(p, 2000.0, _scratch):
		# Only live ships truly within 2,000; only enemies we can see.
		if u.kind != Unit.K_SHIP or not u.alive or u.global_position.distance_to(p) > 2000.0:
			continue
		if u.team != ship.team and not u.visible_to(ship.team):
			continue
		var w := 1 + Rules.size_index(u.size_class)
		score += w if u.team == ship.team else -w
		if u == ship:
			me_counted = true
	# Add ourselves if we weren't already in the count.
	if not me_counted:
		score += 1 + Rules.size_index(ship.size_class)
	return score


## Allies minus enemies (pilot ships, weighted by size) around us right now,
## from the grid cells within 1,800 of us. Our own ship is in that grid
## too, so it counts as one of the allies.
func odds(ship: Ship) -> int:
	var brain := ai
	var score := 0
	for u: Unit in brain.world.unit_hash.query(ship.global_position, 1800.0, _scratch):
		if u.kind != Unit.K_SHIP or not u.alive:
			continue
		if u.team != ship.team and not u.visible_to(ship.team):
			continue
		var w := 1 + Rules.size_index(u.size_class)
		score += w if u.team == ship.team else -w
	return score


## How many friendly pilot ships (not counting us) are within r of us.
func allies_near(ship: Ship, r: float) -> int:
	var brain := ai
	var n := 0
	for u: Unit in brain.world.unit_hash.query(ship.global_position, r, _scratch):
		if u.kind == Unit.K_SHIP and u.team == ship.team and u.alive and u != ship and u.global_position.distance_to(ship.global_position) < r:
			n += 1
	return n


## Is at least one live minion of `team` within r of point p?
func minions_near(p: Vector2, team: int, r: float) -> bool:
	var brain := ai
	for u: Unit in brain.world.unit_hash.query(p, r, _scratch):
		if u.kind == Unit.K_MINION and u.team == team and u.alive and u.global_position.distance_to(p) < r:
			return true
	return false


## Our minions are inside this enemy turret's reach (so it shoots them, and
## we deal full damage to it): true when the turret is aiming at one of our
## minions, or when the grid cells covering its range hold 3 or more of our
## live minions.
func minions_tanking(t: Turret, team: int) -> bool:
	var brain := ai
	# Step 1: the turret is shooting one of our minions right now.
	var tg := t.target
	if tg != null and is_instance_valid(tg) and tg.alive and tg.kind == Unit.K_MINION and tg.team == team:
		return true
	# Step 2: or 3+ of our minions are around it.
	var n := 0
	for u: Unit in brain.world.unit_hash.query(t.global_position, t.range_r, _scratch):
		if u.kind == Unit.K_MINION and u.team == team and u.alive:
			n += 1
			if n >= 3:
				return true
	return false


## How many live minions of `team` are within r of the mothership's hull
## (its surface, not its centre).
func minions_at_hull(ms: Mothership, team: int, r: float) -> int:
	var brain := ai
	var n := 0
	for m: Minion in brain.world.minions:
		if m.team == team and m.alive and ms.hull_dist(m.position) < r:
			n += 1
	return n


## An enemy turret currently shooting at this ship, or null.
func turret_targeting(ship: Ship) -> Turret:
	var brain := ai
	for t: Turret in brain.world.turrets:
		if t.alive and t.team != ship.team and t.target == ship:
			return t
	return null


## A built enemy turret (not ours, not neutral) whose range covers point p,
## plus `margin` extra world units, or null.
func enemy_turret_at(p: Vector2, team: int, margin: float) -> Turret:
	var brain := ai
	for t: Turret in brain.world.turrets:
		if t.alive and t.team != team and t.team != Rules.NEUTRAL and t.is_built() and p.distance_to(t.global_position) < t.range_r + margin:
			return t
	return null


## One of our turrets on `lane` that an enemy PILOT is attacking, or null:
## it took damage in the last 3 seconds, and an enemy pilot ship is around
## it (within its range + 600).
func turret_under_attack(team: int, lane: String) -> Turret:
	var brain := ai
	var world := brain.world
	for t: Turret in world.turrets:
		# Only our live turrets that stand on a node of this lane.
		if t.team != team or not t.alive or t.node == null or t.node.lane != lane:
			continue
		# Hit recently, with an enemy ship or minion close (a quick check
		# first), then make sure one of those enemies is a pilot ship.
		if world.time - t.last_damage_time < 3.0 and world.any_enemy_ship_near(t.global_position, t.range_r + 600.0, team):
			for u: Unit in world.unit_hash.query(t.global_position, t.range_r + 600.0, _scratch):
				if u.kind == Unit.K_SHIP and u.team != team and u.alive:
					return t
	return null
