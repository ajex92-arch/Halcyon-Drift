class_name RoutingPayoffSystems
extends PilotSystems
## WHAT THIS IS: a version of the AI pilot's "power switches" part
## (PilotSystems) used by the routing_payoff variant. It does everything the
## original does, and then, for pilots who already route energy, holds the
## Weapons routing while an enemy ship is 1.2 to 2 weapon ranges away, so
## the ship is charged (RoutingPayoffFeature) by the time the fight starts.
##
## HOW IT WORKS: set_energy_and_shields() calls the original through super.
## After it, ShipControls.energy_request is 0 or more only when the original
## rule asked for a routing (that rule is the existing "skill above 0.55"
## one; this part adds no skill rule of its own). If so, and the pilot is not
## retreating, not weak (below 40% hull) and not asking for Shields, it looks
## at its target (or, with none, the nearest visible enemy pilot ship within
## 2 weapon ranges). When that ship is between 1.2 and 2 weapon ranges
## away (gap between hulls, with the pilot's main gun reach), the request
## becomes Weapons. Each such hold is counted in Game.usage as
## "routing_holds" (counted each time this rule switches the ship to Weapons).
##
## WHO USES IT: RoleBrains (installed by RoutingPayoffFeature); PilotAI._think()
## calls set_energy_and_shields() through brain.systems.

## Closest distance, in weapon ranges, at which the pilot holds Weapons.
const NEAR_RANGES := 1.2
## Farthest distance, in weapon ranges, at which the pilot holds Weapons.
const FAR_RANGES := 2.0


## Energy routing and shield focus for this think: the original rule, then
## the early Weapons hold (see HOW IT WORKS).
func set_energy_and_shields(ship: Ship) -> void:
	super.set_energy_and_shields(ship)
	var brain := ai
	var c := ship.controls
	# Step 1: only pilots whose original rule asked for a routing (they are
	# the ones who route energy at all), and not retreating, weak or about to
	# take Shields.
	if c.energy_request < 0 or c.energy_request == Rules.ENERGY_SHIELDS:
		return
	if brain.state == "retreat" or brain.state == "home" or ship.hull_frac() < 0.4:
		return
	# Step 2: the ship we are about to fight.
	var reach := PilotTargeting.main_reach(ship)
	var foe: Unit = brain.target
	if foe == null or not is_instance_valid(foe) or not foe.alive:
		foe = brain.world.nearest_enemy(ship.global_position, reach * FAR_RANGES + 200.0, ship.team,
			func(u: Unit) -> bool: return u.kind == Unit.K_SHIP and u.visible_to(ship.team))
	if foe == null:
		return
	# Step 3: between 1.2 and 2 weapon ranges away (hull to hull): Weapons.
	var gap := ship.global_position.distance_to(foe.global_position) - foe.radius - ship.radius
	if gap >= reach * NEAR_RANGES and gap <= reach * FAR_RANGES:
		c.energy_request = Rules.ENERGY_WEAPONS
		if ship.energy.mode != Rules.ENERGY_WEAPONS:
			Game.count_usage("routing_holds")
