class_name ComebackBountiesFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C2 (variants bounties:on and
## bounties:equal): accrued pilot bounties, and big structure bounties that
## only the team that is BEHIND can earn. It is the "earned way back" for a
## trailing team, and the alternative to the admiral fork's F2.
##
## HOW IT WORKS:
##  (a) Accrued bounty. Every pilot has a running score. It grows by 1 for
##  every 3 credits earned from kills and assists, and by 1 for every 20
##  credits from minions and derelicts (Events.credits_earned). The first
##  100 points are a buffer; the bounty is the score above it, at most 700.
##  When that pilot's ship is destroyed, the killer's bounty grows by it
##  (World.bounty_hooks, read by Economy._ship_killed) and the score is
##  reset to 0. This replaces the 50-per-streak shutdown bonus (the tuned
##  number shutdown_per_streak is set to 0); the ace buff is unchanged.
##  While the killer's team is behind, that payout is halved.
##  (b) Structure bounties. ComebackDirector keeps its own deficit D and says
##  when a team is "behind" (from 14:00, D of 3 for 60 s, plus a 30 s
##  linger). Each enemy turret or repair bay that team destroys while
##  behind pays 600 + 150 x D credits (at most 2,000): 60% split among its
##  pilots who damaged the structure in the last 15 s or flew within 3,000
##  of it, 40% split among all 12 of its pilots, and 50% of that total is
##  added to its treasury. With bounties:equal the whole pay is split
##  equally among all 12 pilots, alive or dead, with no contributor share.
##  A gold ring and a banner show both teams which structures pay.
##  The AI uses it: it scores those enemy turrets 1.5 times better when
##  choosing a turret to push (World.push_weight_hooks), and the flex pilot
##  and the junglers within 8,000 of one fly off to attack it
##  (World.pilot_think_hooks). Counted in Game.usage as
##  "bounty_structure_kills", "bounty_structure_credits", "bounty_acc_paid"
##  and "bounty_diverts".
##
## WHO USES IT: FeatureRegistry installs it for --variant=bounties:on or
## bounties:equal.

## The variant key.
const KEY := "bounties"
## The first points of the accrued score do not count (a buffer).
const ACC_BUFFER := 100.0
## The most accrued bounty a ship can carry, in credits.
const ACC_CAP := 700.0
## Credits earned from kills and assists per point of score.
const KILL_PER_POINT := 3.0
## Credits earned from minions and derelicts per point of score.
const MINION_PER_POINT := 20.0
## A structure bounty starts at this many credits...
const STRUCT_BASE := 600.0
## ...plus this many for every point of the deficit D...
const STRUCT_PER_D := 150.0
## ...and never exceeds this many credits.
const STRUCT_CAP := 2000.0
## The share paid to the pilots who helped (the rest goes to all 12).
const CONTRIB_SHARE := 0.6
## The treasury also gets this share of the total, on top.
const TREASURY_SHARE := 0.5
## Seconds back that a hit on the structure counts as helping.
const CONTRIB_WINDOW := 15.0
## A pilot this near (world units) to the structure when it falls also counts.
const NEAR_RANGE := 3000.0
## A payout earned while the killer's team is behind is multiplied by this.
const BEHIND_ACC_MULT := 0.5
## Flex pilots and junglers this near (world units) to a bounty structure
## fly off to attack it.
const DIVERT_RANGE := 8000.0
## The AI scores a bounty turret this many times better.
const PUSH_WEIGHT := 1.5

## The match.
var world: World
## The shared who-is-behind scorekeeper.
var director: ComebackDirector
## True for bounties:equal (the whole structure pay split equally).
var equal := false
## Each pilot's accrued score: PilotProfile -> points.
var score := {}
## The pilots currently flying off at a bounty structure: PilotProfile ->
## true. Used to count each diversion once.
var diverting := {}


## Switch the match to this idea (see HOW IT WORKS).
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	if value != "on" and value != "equal":
		push_warning("bounties: unknown value \"%s\" (use off, on or equal); nothing changed" % value)
		return
	equal = value == "equal"
	# Step 1: (a) the accrued bounty replaces the streak bonus.
	Game.tunables["shutdown_per_streak"] = 0.0
	w.bounty_hooks.append(_accrued_bounty)
	Events.credits_earned.connect(_on_credits_earned)
	# Step 2: (b) the director, the structure payouts and the AI use.
	director = ComebackDirector.ensure(w)
	director.enable_banner()
	Events.unit_killed.connect(_on_unit_killed)
	w.push_weight_hooks.append(_push_weight)
	w.pilot_think_hooks.append(_divert)


## A pilot was paid: grow their accrued score (see HOW IT WORKS (a)).
func _on_credits_earned(p: RefCounted, amount: float, reason: String) -> void:
	var gain := 0.0
	if reason == "kill" or reason == "assist":
		gain = amount / KILL_PER_POINT
	elif reason == "minion" or reason == "derelict":
		gain = amount / MINION_PER_POINT
	if gain > 0.0:
		score[p] = minf(ACC_BUFFER + ACC_CAP, float(score.get(p, 0.0)) + gain)


## World.bounty_hooks entry: pilot `victim`'s ship `_ship` was destroyed.
## Returns the accrued bounty (score above the buffer, at most 700, halved
## when the killer's team is behind) and resets the score to 0.
func _accrued_bounty(victim: PilotProfile, _ship: Ship) -> float:
	var points := float(score.get(victim, 0.0))
	score[victim] = 0.0
	var pay := clampf(points - ACC_BUFFER, 0.0, ACC_CAP)
	if pay <= 0.0:
		return 0.0
	if director.is_behind(1 - victim.team):
		pay *= BEHIND_ACC_MULT
	Game.count_usage("bounty_acc_paid", int(pay))
	return pay


## A unit died: if it was an enemy turret or repair bay destroyed by the
## team that is behind, pay the structure bounty (see HOW IT WORKS (b)).
func _on_unit_killed(unit: Node, _info: RefCounted) -> void:
	var s := unit as Unit
	if s == null or (s.kind != Unit.K_TURRET and s.kind != Unit.K_BAY):
		return
	var team := Rules.enemy_of(s.team)
	if team < 0 or not director.is_behind(team):
		return
	# Step 1: how much, and who is in the team.
	var total := minf(STRUCT_CAP, STRUCT_BASE + STRUCT_PER_D * maxf(0.0, float(director.d[team])))
	var pilots: Array = []
	for p: PilotProfile in world.profiles:
		if p.team == team and p.role != "admiral" and p.slot < Rules.PILOTS_PER_TEAM:
			pilots.append(p)
	if pilots.is_empty():
		return
	# Step 2: equal split, or the contributors' 60% and everybody's 40%.
	if equal:
		for p: PilotProfile in pilots:
			p.earn(total / float(pilots.size()), "comeback")
	else:
		var helpers: Array = []
		var who := Economy.contributors(world, s, CONTRIB_WINDOW, 0.0)
		for p: PilotProfile in pilots:
			var near: bool = p.ship != null and is_instance_valid(p.ship) and p.state == "flying" and p.ship.global_position.distance_to(s.global_position) <= NEAR_RANGE
			if who.has(p) or near:
				helpers.append(p)
		var helper_pool := total * CONTRIB_SHARE if not helpers.is_empty() else 0.0
		var everyone_pool := total - helper_pool
		for p: PilotProfile in helpers:
			p.earn(helper_pool / float(helpers.size()), "comeback")
		for p: PilotProfile in pilots:
			p.earn(everyone_pool / float(pilots.size()), "comeback")
	# Step 3: the treasury, the news, and the counters.
	world.teams[team].earn(total * TREASURY_SHARE)
	Events.feed.emit("Comeback bounty: the %s are paid %d for the %s." % [Rules.TEAM_NAMES[team], int(total), "turret" if s.kind == Unit.K_TURRET else "repair bay"], "info", -1)
	Game.count_usage("bounty_structure_kills")
	Game.count_usage("bounty_structure_credits", int(total))


## World.push_weight_hooks entry: while the pilot's team is behind, enemy
## turrets count 1.5 times better (their score, a distance, is divided).
func _push_weight(ship: Ship, t: Unit, score_in: float) -> float:
	if t.team == 1 - ship.team and director.is_behind(ship.team):
		return score_in / PUSH_WEIGHT
	return score_in


## World.pilot_think_hooks entry: a flex pilot or jungler of the team that
## is behind, healthy and within 8,000 of a bounty structure, flies off and
## attacks the nearest one. A ship that cannot enter the jungle only picks
## structures in the open lanes.
func _divert(ship: Ship, brain: PilotAI) -> void:
	var p := brain.profile
	if p.role != "flex" and p.role != "jungle":
		return
	if (brain.state != "lane" and brain.state != "jungle") or ship.hull_frac() < 0.6 or not director.is_behind(ship.team):
		diverting.erase(p)
		return
	# Step 1: the nearest bounty structure in reach.
	var best: Unit = null
	var best_d := DIVERT_RANGE
	for s: Unit in director.bounty_structures(ship.team):
		var dist := ship.global_position.distance_to(s.global_position)
		if dist < best_d and (ship.is_small() or world.map.in_open_lane(s.global_position)):
			best_d = dist
			best = s
	if best == null:
		diverting.erase(p)
		return
	# Step 2: attack it (the same way the pilots push a turret).
	brain.target = best
	brain.lock_target = best
	brain.intent = "push"
	brain.goal = PilotTargeting.standoff(ship, best, ship.global_position)
	if not diverting.has(p):
		diverting[p] = true
		Game.count_usage("bounty_diverts")
