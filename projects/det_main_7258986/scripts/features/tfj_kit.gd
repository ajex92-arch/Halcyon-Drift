class_name TfjKit
extends RefCounted
## WHAT THIS IS: a small toolbox shared by the feature modules of the fork
## "teamfights_jungle" (GroupLateFeature, SalvageCoreFeature,
## JungleScaleFeature, NodePersistFeature, EpicNeutralFeature,
## BeaconsFeature, Camp4Feature, FeatsFeature). It only holds helper
## functions that look at the match or tell the players something. It never
## changes the game by itself and draws no random numbers.
##
## HOW IT WORKS: every function is static (called as TfjKit.name(...)
## without making an object). The helpers are the questions the AI rules of
## several modules ask ("how many friendly small ships are near me?", "fly
## to that derelict and shoot it") and the one-line news banner.
##
## WHO USES IT: the feature modules listed above, in scripts/features/.

## A news line for everybody (the feed at the side of the HUD): this is the
## "banner" of the fork's events. `team` is -1 for both teams, or one team's
## number to show it to that team only (as a "team" line).
static func news(text: String, team: int = -1) -> void:
	Events.feed.emit(text, "info" if team < 0 else "team", team)


## How many live friendly pilot ships (not counting `ship` itself) are
## within `r` world units of point `p`. With `small_only` only strike craft
## (small ships) count.
static func friends_near(world: World, ship: Ship, p: Vector2, r: float, small_only: bool) -> int:
	var n := 0
	for s: Ship in world.ships:
		if s == ship or not s.alive or s.team != ship.team:
			continue
		if small_only and not s.is_small():
			continue
		if s.global_position.distance_to(p) < r:
			n += 1
	return n


## True if a live enemy pilot ship of team `team` is within `r` of point `p`.
static func enemy_pilot_near(world: World, team: int, p: Vector2, r: float) -> bool:
	for s: Ship in world.ships:
		if s.alive and s.team != team and s.global_position.distance_to(p) < r:
			return true
	return false


## Number of live friendly minions of `team` on `lane`.
static func minions_on_lane(world: World, team: int, lane: String) -> int:
	var n := 0
	for m: Minion in world.minions:
		if m.alive and m.team == team and m.lane == lane:
			n += 1
	return n


## TEST OPTION --tfj-hull-scale=F (default 1.0 = off, no effect): multiplies
## the hull of every Battleship and Dreadnought when it is made, so a short
## smoke run can kill one. Only the fork's modules read it, and only while
## their variant is on.
static func test_hull_scale() -> float:
	return float(Game.opt("tfj-hull-scale", 1.0))


## Apply --tfj-hull-scale to derelict `d` (does nothing when it is 1.0).
static func apply_test_hull(d: Derelict) -> void:
	var f := test_hull_scale()
	if f != 1.0:
		d.hull_max *= f
		d.hull = d.hull_max


## Make AI pilot `brain` (flying `ship`) go for the derelict `d` and shoot
## it: the goal is a standoff spot on our side of it (450 or its radius plus
## 300 for strike craft; 75% of the main gun's reach, between that and 1,500,
## for bigger ships), the target is the best enemy near us (pilots and
## structures first, like the normal lane job) or, when nothing else is in
## reach and we are close, the derelict itself. Sets the brain's goal,
## target, lock_target and intent. The modules call this from their
## pilot_think() when their AI rule says "go".
static func attack_derelict(brain: PilotAI, ship: Ship, d: Derelict) -> void:
	var away := ship.global_position - d.global_position
	var dir := away.normalized() if away.length() > 1.0 else Vector2.LEFT
	var stand := maxf(450.0, d.radius + 300.0)
	if not ship.is_small():
		stand = clampf(PilotTargeting.main_reach(ship) * 0.75, d.radius + 300.0, 1500.0)
	brain.goal = d.global_position + dir * stand
	brain.intent = ""
	brain.target = brain.targeting.pick_target(ship, PilotTargeting.engage_range(ship))
	var given_up := brain.skip_id != 0 and d.get_instance_id() == brain.skip_id and brain.world.time < brain.skip_until
	if brain.target == null and not given_up and ship.global_position.distance_to(d.global_position) < maxf(1500.0, stand + 700.0):
		brain.target = d
	brain.lock_target = brain.target
