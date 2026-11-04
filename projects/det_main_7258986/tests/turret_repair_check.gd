extends "res://tests/turret_repair_probe.gd"
## WHAT THIS IS: the check that nothing repairs a turret and that a turret
## has no shield. It is the turret-repair probe (tests/turret_repair_probe.gd,
## whose scenario it reuses) with a verdict.
##
## HOW IT WORKS: it runs the probe's scenario: a damaged turret, a damaged
## repair bay and a damaged fighter beside a Logistics Corvette that sends its
## repair drones and uses Emergency Repair twice, for 40 seconds. At the end
## it checks:
##   - the turret has no shield pool and no shield points;
##   - the turret's hull is exactly what it started with (40% of its maximum);
##   - no Logistics drone ever had the turret as its target;
##   - the Corvette did use Emergency Repair twice and its drones did heal;
##   - the repair bay beside the turret was repaired (it gained hull), and so
##     was the fighter.
## It prints one line with the numbers and then "turret_repair_check: N
## failures" (0 means all is as it should be).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=turret_repair_check
##
## WHO USES IT: main.gd loads it for --test=turret_repair_check; run_checks
## runs it. It changes only the units the scenario builds itself.

## True once the verdict has been printed (the probe's timer may call again).
var _finished := false


## Check the end of the scenario, print the verdict and quit.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	var failures := 0
	var start_hull := turret.hull_max * START_FRAC
	var checks := {
		"the turret has no shield pool": turret.shields == null,
		"the turret has no shield points": turret.shield_total() == 0.0,
		"the turret's hull is exactly what it started with": turret.hull == start_hull,
		"no Logistics drone had the turret as its target": _drone_on_turret_s == 0.0,
		"Emergency Repair was used twice": _used == EMERGENCY_AT.size(),
		"the Logistics drones healed something": _healing_s > 0.0,
		"the repair bay beside the turret was repaired": bay.hull > bay.hull_max * START_FRAC + 1.0,
		"the fighter was repaired": fighter.hull > fighter.hull_max * START_FRAC + 1.0,
	}
	for what: String in checks:
		if not bool(checks[what]):
			failures += 1
			print("turret_repair_check: FAIL %s" % what)
	print("turret_repair_check: turret hull %s of %s (started %s), shield %s, drone seconds on the turret %s, bay hull %s of %s, fighter hull %s of %s" % [
		turret.hull, turret.hull_max, start_hull, turret.shield_total(), _drone_on_turret_s, bay.hull, bay.hull_max, fighter.hull, fighter.hull_max])
	print("turret_repair_check: %d failures" % failures)
	get_tree().quit()
