class_name AdmiralAssetsAI
extends RefCounted
## WHAT THIS IS: how the computer admiral of one team uses the command
## assets of the "assets" variant (Sensor Sweep, Supply Drop, Barrage; see
## AdmiralAssetsFeature). It is the "AdmiralAssets part" of the AI admiral,
## kept next to its feature module so a match without the variant has none
## of it.
##
## HOW IT WORKS: once a second (the two teams half a second apart) tick()
## looks at the situation, but only for a team whose admiral is the
## computer (World.admiral_ai) and only for the orders that are installed
## and ready. It never spends money the build plan is waiting for: an order
## goes only when the treasury holds its price, the price of the next plan
## step and 100 more (afford()). The rules, in this order:
##   1. Barrage: when 3 or more enemy pilot ships that we can see stand
##      within 500 units of each other and the middle of that group is
##      within the barrage's reach (12,000) of our mothership, fire at the
##      middle of the group.
##   2. Supply Drop: the largest cluster (3 or more) of our pilot ships
##      within 1,200 of each other whose average hull is below 60%, with an
##      enemy ship or minion within 2,500 of it (a fight), and not farther
##      than 18,000 from our mothership: drop at the middle of the cluster.
##   3. Sensor Sweep: (a) while a siege runs, ahead of our front big ship,
##      toward the enemy mothership, as far as we can still see; (b) while
##      the base is under attack (the defend call), at the defend point;
##      (c) at one of our turrets that was hit in the last 4 s while no
##      enemy ship that we can see is within 3,500 of it.
## Every order is given through CommandOrders.run(), the same call a human
## admiral's button uses, so it follows the same rules, pays the same price
## and is counted by the usage counters of AdmiralAssetsFeature. The AI reads
## only what its team can see (visible_to) and the team notebook; it draws
## no random numbers and has no skill threshold.
##
## WHO USES IT: AdmiralAssetsFeature makes one per team and calls tick() from
## its tick hook.

## Barrage: enemy ships count as a group when this close together (world units).
const BARRAGE_GROUP_RADIUS := 500.0
## Barrage: the fewest ships in a group.
const BARRAGE_GROUP_MIN := 3
## Supply Drop: the fewest ships in a cluster.
const SUPPLY_CLUSTER_MIN := 3
## Supply Drop: our ships count as one cluster when within this of each
## other (world units).
const SUPPLY_CLUSTER := 1200.0
## Supply Drop: the cluster's average hull fraction must be below this (0..1).
const SUPPLY_HULL := 0.6
## Supply Drop: an enemy must stand within this of the cluster's middle
## (world units): it is a fight.
const SUPPLY_FIGHT := 2500.0
## Supply Drop: the cluster may be at most this far from our mothership
## (world units).
const SUPPLY_REACH := 18000.0
## Sweep for a turret under attack: the turret must have been hit within
## this many seconds...
const TURRET_HIT := 4.0
## ...and no visible enemy ship may be within this of it (world units).
const TURRET_QUIET := 3500.0
## How far ahead of our front big ship a siege sweep may reach (world units).
const SIEGE_AHEAD := 1500.0
## Money kept back beyond the next plan step (credits).
const SPARE := 100.0

## The game world.
var world: World
## Our team: 0 = Halcyon, 1 = Cinder.
var team := 0
## Seconds until the next think.
var think_t := 1.0


## Make the part for team `t` in world `w`; the two teams think half a
## second apart.
func _init(w: World, t: int) -> void:
	world = w
	team = t
	think_t = 1.0 + float(t) * 0.5


## Called by the feature's tick hook every tick: once a second, think.
func tick(dt: float) -> void:
	# Only a computer admiral uses these orders on its own.
	if not AdmiralWeak.ai_acts(world, team):
		return
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return
	var orders: Dictionary = world.command.orders
	# One order per think: the biggest first.
	if orders.has("barrage") and _barrage(ms):
		return
	if orders.has("supply") and _supply(ms):
		return
	if orders.has("sweep"):
		_sweep()


## Can we pay for order `id` now without starving the build plan? It must be
## ready (no cooldown), and the treasury must hold its price, the next plan
## step's price and SPARE.
func afford(id: String) -> bool:
	if CommandOrders.ready_in(world, id, team) > 0.0:
		return false
	var ts := world.teams[team]
	var step := AdmiralPlan.next_step(ts)
	var reserve := float(step["cost"]) if not step.is_empty() else 0.0
	return ts.treasury >= CommandOrders.cost_of(world.command.orders[id], team) + reserve + SPARE


# --- Barrage ------------------------------------------------------------------------------------

## Fire a barrage at the biggest group of visible enemy ships in reach.
## Returns true if the order was given.
func _barrage(ms: Mothership) -> bool:
	if not afford("barrage"):
		return false
	# Step 1: the enemy pilot ships we can see, within reach.
	var seen: Array = []
	for s: Ship in world.ships:
		if s.team != 1 - team or not s.alive or not s.visible_to(team):
			continue
		if ms.global_position.distance_to(s.global_position) <= AdmiralAssetsFeature.BARRAGE_RANGE:
			seen.append(s)
	# Step 2: around each ship, how many stand within the group radius; the
	# biggest group wins (the first one on a tie).
	var best: Array = []
	for s: Ship in seen:
		var group: Array = []
		for o: Ship in seen:
			if o.global_position.distance_to(s.global_position) <= BARRAGE_GROUP_RADIUS:
				group.append(o)
		if group.size() > best.size():
			best = group
	if best.size() < BARRAGE_GROUP_MIN:
		return false
	# Step 3: fire at the middle of the group.
	var mid := Vector2.ZERO
	for o: Ship in best:
		mid += o.global_position
	mid /= float(best.size())
	return CommandOrders.run(world, "barrage", team, mid) == ""


# --- Supply Drop ----------------------------------------------------------------------------------

## Drop supplies on the biggest hurt cluster of our ships that is in a fight.
## Returns true if the order was given.
func _supply(ms: Mothership) -> bool:
	if not afford("supply"):
		return false
	# Step 1: our flying pilot ships.
	var mine: Array = []
	for s: Ship in world.ships:
		if s.team == team and s.alive:
			mine.append(s)
	# Step 2: around each ship, its cluster; keep the biggest hurt one that
	# stands in a fight within reach.
	var best_n := 0
	var best_mid := Vector2.INF
	for s: Ship in mine:
		var n := 0
		var sum := Vector2.ZERO
		var hull := 0.0
		for o: Ship in mine:
			if o.global_position.distance_to(s.global_position) <= SUPPLY_CLUSTER:
				n += 1
				sum += o.global_position
				hull += o.hull_frac()
		if n < SUPPLY_CLUSTER_MIN or n <= best_n or hull / float(n) >= SUPPLY_HULL:
			continue
		var mid := sum / float(n)
		if ms.global_position.distance_to(mid) > SUPPLY_REACH or not world.any_enemy_ship_near(mid, SUPPLY_FIGHT, team):
			continue
		best_n = n
		best_mid = mid
	if best_mid == Vector2.INF:
		return false
	return CommandOrders.run(world, "supply", team, best_mid) == ""


# --- Sensor Sweep ----------------------------------------------------------------------------------

## Sweep where it helps most (see the list at the top). The order is only
## given when a reason is found.
func _sweep() -> void:
	if not afford("sweep"):
		return
	var ts := world.teams[team]
	var p := Vector2.INF
	# Reason (a): a siege is on: ahead of our front big ship.
	if ts.siege_lane != "":
		p = _siege_point()
	# Reason (b): the base is under attack: the defend point.
	if p == Vector2.INF and ts.defending(world.time) and ts.defend_point != Vector2.INF and world.vision.is_visible(team, ts.defend_point):
		p = ts.defend_point
	# Reason (c): a turret under attack that sees no enemy.
	if p == Vector2.INF:
		p = _turret_point()
	if p != Vector2.INF:
		CommandOrders.run(world, "sweep", team, p)


## Reason (a): the point ahead of our front big ship toward the enemy
## mothership, as far as the team can still see (up to SIEGE_AHEAD). Returns
## Vector2.INF if there is no big ship or the enemy mothership is gone.
func _siege_point() -> Vector2:
	var ems := world.mothership(1 - team)
	if ems == null or not ems.alive:
		return Vector2.INF
	var lead: Ship = null
	var lead_d := INF
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.size_class >= Rules.SIZE_LARGE:
			var d := ems.hull_dist(s.global_position)
			if d < lead_d:
				lead_d = d
				lead = s
	if lead == null:
		return Vector2.INF
	var dir := (ems.global_position - lead.global_position).normalized()
	for frac in [1.0, 0.66, 0.33, 0.0]:
		var p: Vector2 = lead.global_position + dir * SIEGE_AHEAD * float(frac)
		if world.vision.is_visible(team, p):
			return p
	return Vector2.INF


## Reason (c): the position of one of our turrets that was hit in the last
## TURRET_HIT seconds while no enemy pilot ship that we can see is within
## TURRET_QUIET of it. Vector2.INF if none.
func _turret_point() -> Vector2:
	for tu: Turret in world.turrets:
		if tu.team != team or not tu.alive or world.time - tu.last_damage_time > TURRET_HIT:
			continue
		var quiet := true
		for s: Ship in world.ships:
			if s.team != team and s.alive and s.visible_to(team) and s.global_position.distance_to(tu.global_position) < TURRET_QUIET:
				quiet = false
				break
		if quiet and world.vision.is_visible(team, tu.global_position):
			return tu.global_position
	return Vector2.INF
