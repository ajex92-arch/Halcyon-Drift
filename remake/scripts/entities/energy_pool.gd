class_name EnergyPool
extends RefCounted
## WHAT THIS IS: a pilot ship's battery (its "capacitor") plus the switch
## that decides where extra power goes ("energy routing"). DESIGN.md A5.
##
## HOW IT WORKS: the battery holds up to `max_value` energy and refills by
## `regen` energy per second. Guns (per shot; beams per second of firing),
## boosting and specials spend from it; if there isn't enough, the action
## simply doesn't happen. The routing `mode` is one of four settings in
## Rules.ENERGY_MODES (Balanced, Weapons, Shields, Thrusters). Each setting
## is a set of multipliers that trade fire rate, shield regeneration,
## shield resistance, thrust, turning and boost cost against each other
## (Weapons: guns fire 25% faster, but shields refill slower and the ship
## is a bit slower). This file only stores the mode; Ship applies the
## multipliers (m()).
##
## WHO USES IT: every Ship owns one (Ship.energy) and sets it up, refills
## it, changes its mode and reads m(). WeaponMount.update() spends from it
## when a gun fires (minions, turrets and monsters pass null instead and
## shoot for free). The HUD and the AI pilots read value, fraction() and
## mode.

## The most energy the battery can hold.
var max_value := 100.0
## The energy in the battery right now.
var value := 100.0
## How fast the battery refills, in energy per second.
var regen := 25.0
## The routing setting: one of Rules.ENERGY_BALANCED, ENERGY_WEAPONS,
## ENERGY_SHIELDS or ENERGY_THRUSTERS (0..3).
var mode := Rules.ENERGY_BALANCED


## Start full: `capacity` energy, refilling at `regen_rate` per second.
func setup(capacity: float, regen_rate: float) -> void:
	max_value = capacity
	value = capacity
	regen = regen_rate


## Change the battery size (e.g. a module or upgrade) keeping the same
## fraction full: a half-full battery stays half full.
func set_max(capacity: float) -> void:
	var f := value / max_value if max_value > 0.0 else 1.0
	max_value = capacity
	value = capacity * f


## Refill for one tick of `dt` seconds, never above the maximum.
func tick(dt: float) -> void:
	value = minf(max_value, value + regen * dt)


## Try to spend `amount` energy. Returns true and takes it if there is
## enough; otherwise returns false and takes nothing.
func spend(amount: float) -> bool:
	if value < amount:
		return false
	value -= amount
	return true


## How full the battery is, as a 0..1 fraction (0 if it has no size).
func fraction() -> float:
	return value / max_value if max_value > 0.0 else 0.0


## One multiplier from the current routing setting. `key` is one of:
## "fire" (fire rate), "regen" (shield refill speed), "sresist" (extra
## shield resistance, a 0..1 fraction to add), "thrust" (engine push and
## top speed), "turn" (turning speed) or "boost_cost" (boost energy cost).
func m(key: String) -> float:
	return float(Rules.ENERGY_MODES[mode][key])
