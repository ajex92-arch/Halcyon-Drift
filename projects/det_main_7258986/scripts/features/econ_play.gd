class_name EconPlayFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C1, "income from play"
## (variant econ:play). It moves pilot income away from the steady trickle
## and from ore, toward kills, turrets and minion last hits, so skill and
## objectives move the economy.
##
## HOW IT WORKS: install() changes seven tuned numbers for the match
## (Rules.tune, names in Rules.TUNABLES) and adds one new payout:
##   passive_income        1.5 -> 1.0   credits per second for every pilot
##   ore_treasury_share    0.6 -> 0.75  the pilots' share of delivered ore
##                                      falls from 40% to 25%
##   kill_base             100 -> 150   credits for destroying a pilot ship
##   kill_value_share      0.12 -> 0.15 share of the ship's value on top
##   turret_bounty         350 -> 500   split among the pilots who hit a turret
##   minion_bounty_growth  0.05 -> 0.10 minion last-hit pay growth per 5 min
##   (the shopping reserve is unchanged)
## New: when a turret is destroyed, every pilot of the destroying team whose
## ship flies within 5,000 world units of it also gets 60 credits
## (Events.turret_destroyed). The AI needs no new behaviour: the pilots
## simply earn more for what they already do, and the pilots near a fallen
## turret are paid for being there.
## It also counts every credit paid to pilots by reason in Game.usage
## ("credits_kill", "credits_ore" ...), so the screens can show where the
## money comes from.
##
## WHO USES IT: FeatureRegistry installs it for --variant=econ:play.

## The variant key.
const KEY := "econ"
## Credits to every pilot of the team near a destroyed turret.
const NEAR_PAY := 60.0
## "Near" means within this many world units of the destroyed turret.
const NEAR_RANGE := 5000.0

## The match.
var world: World


## Switch the match to the econ:play numbers (see HOW IT WORKS). Any other
## value only gets a warning.
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	if value != "play":
		push_warning("econ: unknown value \"%s\" (use off or play); nothing changed" % value)
		return
	# Step 1: the tuned numbers.
	Game.tunables["passive_income"] = 1.0
	Game.tunables["ore_treasury_share"] = 0.75
	Game.tunables["kill_base"] = 150.0
	Game.tunables["kill_value_share"] = 0.15
	Game.tunables["turret_bounty"] = 500.0
	Game.tunables["minion_bounty_growth"] = 0.10
	# Step 2: the new payout for pilots near a destroyed turret, and the
	# credit counters.
	Events.turret_destroyed.connect(_on_turret_destroyed)
	Events.credits_earned.connect(_on_credits_earned)


## A turret was destroyed by team `by_team`: pay 60 credits to every pilot of
## that team whose ship is within 5,000 of it.
func _on_turret_destroyed(turret: Node, by_team: int) -> void:
	if by_team < 0 or by_team > 1:
		return
	var at := (turret as Node2D).global_position
	for p: PilotProfile in world.profiles:
		if p.team != by_team or p.state != "flying" or p.ship == null or not is_instance_valid(p.ship):
			continue
		if p.ship.global_position.distance_to(at) <= NEAR_RANGE:
			p.earn(NEAR_PAY, "turret zone")
			Game.count_usage("turret_proximity_payouts")


## A pilot was paid: add the credits to the counter of its reason.
func _on_credits_earned(_p: RefCounted, amount: float, reason: String) -> void:
	Game.count_usage("credits_" + reason, int(amount))
