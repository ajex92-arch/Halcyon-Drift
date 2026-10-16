class_name StatBlock
extends RefCounted
## WHAT THIS IS: a running total of stat bonuses, by name. For example
## "speed_pct" -> 0.15 means "+15% top speed" in total. Keys are listed in
## items.gd. Percent keys are fractions (0.10 = +10%).
##
## HOW IT WORKS: clear() empties it, add_dict() and add() add bonuses on
## top of what is there, and g() / mul() read a total back (a name that
## was never added counts as 0). It only adds numbers up; what a stat does
## is up to whoever reads it.
##
## WHO USES IT: each Ship owns one (Ship.stats). ShipStats.recompute()
## (which Ship.recompute_stats() forwards to) refills it from the pilot's
## gear and the fitted modules, and reads it to work out the ship's
## numbers; team upgrades and buffs are applied there separately, not
## stored here. Each PilotProfile also keeps one for its gear only
## (gear_stats()), which Economy and MatchRules read (income, bounty,
## insurance, respawn time). ShipAbilities reads Ship.stats too.

## The totals: stat name (String) -> summed amount (float).
var v := {}


## Forget every total.
func clear() -> void:
	v.clear()


## Add every bonus in `d` (stat name -> amount) to the totals.
func add_dict(d: Dictionary) -> void:
	for k: String in d:
		v[k] = float(v.get(k, 0.0)) + float(d[k])


## Add `amount` to the total for `key`. (Nothing calls this at the moment.)
func add(key: String, amount: float) -> void:
	v[key] = float(v.get(key, 0.0)) + amount


## The total for `key` (0 if never added).
func g(key: String) -> float:
	return float(v.get(key, 0.0))


## 1 + value: a ready multiplier for "*_pct" keys.
## For example a total of 0.15 gives 1.15 (multiply by it for +15%).
func mul(key: String) -> float:
	return 1.0 + float(v.get(key, 0.0))
