extends Node
## WHAT THIS IS: a short smoke test for the economy_comebacks features. It
## starts a match at 25:00 (the same late-game setup as det_hash --late),
## nudges the match into the situations the features need, lets the AI
## play for about 100 game seconds, and then checks that the usage counters
## you asked for are above zero.
##
## HOW IT WORKS: the nudges are the only thing that is not "natural" play,
## and they only create situations (they never touch the features):
##   +0.5 s   two Cinder turrets are removed quietly, so Cinder's deficit D
##            (turrets standing) is 4 and, after 60 s, Cinder is "behind"
##            (ComebackDirector);
##   +8 s     every pilot is given 15,000 credits (the late pile-up of idle
##            money that the sinks are meant for);
##   +62.5 s  Cinder's flex pilot and jungler are moved to 3,500 world units
##            from a Halcyon turret, and one more Cinder pilot to 4,500;
##   +66 s    that Halcyon turret is destroyed by Cinder (a comeback bounty,
##            and the pilots nearby are paid by econ:play);
##   +67 s    two Halcyon pilot ships are destroyed by Cinder (an accrued
##            bounty is paid; the Halcyon mothership is set to 55% hull so
##            the AI buys back);
##   +70 s    Halcyon spends 2,500 from its treasury (ms_spend_weak).
## At the end it prints one line  ECON_SMOKE {usage json}  and, for every
## name in --expect=a,b,c, PASS or FAIL; the last line is
## "econ_smoke: N failures".
##
## HOW TO RUN IT: godot --headless --path <project> --fixed-fps 60 -- --all-ai
## --seed=7 --test=econ_smoke --secs=100 --variant=bounties:on
## --expect=bounty_structure_kills,bounty_acc_paid
##
## WHO USES IT: main.gd loads it for --test=econ_smoke; it is run by hand
## and is not part of run_checks.

## The running match.
var world: World
## Game seconds to run after the 25:00 start (--secs, default 100).
var secs := 100.0
## The counters that must be above zero (--expect=a,b,c).
var expect := PackedStringArray()
## The match clock at the start (25:00).
var t0 := 0.0
## Which nudge comes next (0..5).
var stage := 0
## The Halcyon turret destroyed at +66 s.
var target_turret: Turret = null


## main.gd calls this once after the World is built: read the options and
## jump to the late-game setup.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 100.0))
	expect = str(Game.opt("expect", "")).split(",", false)
	LateGame.apply(world)
	t0 = LateGame.START


## Every tick: do the next nudge when its time has come, and finish at the
## end time.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	var t := world.time - t0
	if stage == 0 and t >= 0.5:
		stage = 1
		_remove_cinder_turrets(2)
	elif stage == 1 and t >= 8.0:
		stage = 2
		for p: PilotProfile in world.profiles:
			p.credits += 15000.0
	elif stage == 2 and t >= 62.5:
		stage = 3
		_move_cinder_pilots()
	elif stage == 3 and t >= 66.0:
		stage = 4
		_destroy_halcyon_turret()
	elif stage == 4 and t >= 67.0:
		stage = 5
		_destroy_halcyon_ships(2)
	elif stage == 5 and t >= 70.0:
		stage = 6
		world.teams[0].spend(2500.0)
	if t >= secs or world.phase != "play":
		_finish()


## Remove `n` built Cinder turrets without any reward or news.
func _remove_cinder_turrets(n: int) -> void:
	for tr: Turret in world.turrets.duplicate():
		if n > 0 and tr.team == Rules.CINDER and tr.alive and tr.is_built():
			world.combat.kill_silently(tr)
			n -= 1


## A live Cinder pilot ship (the first one found), or null.
func _cinder_ship() -> Ship:
	for s: Ship in world.ships:
		if s.team == Rules.CINDER and s.alive:
			return s
	return null


## Move Cinder's flex pilot and jungler next to a Halcyon turret (3,500
## away), and one more Cinder pilot 4,500 away.
func _move_cinder_pilots() -> void:
	for tr: Turret in world.turrets:
		if tr.team == Rules.HALCYON and tr.alive and tr.is_built():
			target_turret = tr
			break
	if target_turret == null:
		return
	var moved := 0
	for s: Ship in world.ships:
		if s.team != Rules.CINDER or not s.alive or s.profile == null:
			continue
		if s.profile.role == "flex" or s.profile.role == "jungle":
			s.global_position = target_turret.global_position + Vector2(3500.0, 0.0).rotated(float(moved))
			moved += 1
		elif moved >= 2 and moved < 3:
			s.global_position = target_turret.global_position + Vector2(0.0, 4500.0)
			moved += 1


## Destroy the chosen Halcyon turret with a Cinder pilot as the killer.
func _destroy_halcyon_turret() -> void:
	if target_turret == null or not target_turret.alive:
		return
	var killer := _cinder_ship()
	world.combat.kill(target_turret, DamageInfo.from_unit(killer, 99999.0, Rules.W_PURE, target_turret.global_position))


## Destroy `n` Halcyon pilot ships (Cinder is the killer) after giving them
## a big accrued bounty, and set the Halcyon mothership to 55% hull.
func _destroy_halcyon_ships(n: int) -> void:
	var killer := _cinder_ship()
	var bf = world.features.get("bounties")
	for s: Ship in world.ships.duplicate():
		if n > 0 and s.team == Rules.HALCYON and s.alive and s.profile != null and not s.profile.is_human:
			if bf != null:
				bf.score[s.profile] = 800.0
			world.combat.kill(s, DamageInfo.from_unit(killer, 99999.0, Rules.W_PURE, s.global_position))
			n -= 1
	var ms := world.mothership(Rules.HALCYON)
	ms.hull = ms.hull_max * 0.55


## Print the usage counters, check the expected ones and quit.
func _finish() -> void:
	var fails := 0
	print("ECON_SMOKE PROBE_JSON ", JSON.stringify(Game.usage))
	print("ECON_SMOKE state: t=%d D=%s features=%s" % [int(world.time - t0), str(world.get_meta("comeback_director").d) if world.has_meta("comeback_director") else "-", ",".join(PackedStringArray(world.features.keys()))])
	for key in expect:
		if int(Game.usage.get(key, 0)) > 0:
			print("PASS %s = %d" % [key, int(Game.usage[key])])
		else:
			print("FAIL %s is zero" % key)
			fails += 1
	print("econ_smoke: %d failures" % fails)
	get_tree().quit()
