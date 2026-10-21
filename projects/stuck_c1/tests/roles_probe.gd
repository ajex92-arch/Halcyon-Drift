extends Node
## WHAT THIS IS: a small arena test for the combat_roles features. Like
## tests/arena.gd it puts two squads of AI pilots in open space (no
## minions, turrets or jungle monsters), but it runs for a fixed time, keeps
## going after kills, and prints the feature usage counters (Game.usage)
## and what the squads did, so one short run shows whether a mechanic works
## and whether the AI uses it.
##
## HOW IT WORKS: setup() stops the minion waves and builds squad A for
## Halcyon and squad B for Cinder with the arena toolkit
## (tests/lib/arena_kit.gd). Every tick it keeps the pilots in the fight.
## Every 10 s it prints who is alive. At the end (--secs seconds, default
## 90, or when a squad is gone) it prints one line, "ROLES_PROBE ...", with
## the squads, the time, the survivors and Game.usage. With --show it also
## prints, every 5 s, the hulls' distance to the first enemy and (for the
## lance_role variant) the Lance's angle in the target's own frame.
##
## HOW TO RUN IT ("godot" is the Godot console program):
##   godot --headless --path forks/combat_roles --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=roles_probe --a=lance,lance --b=flak --variant=lance_role:on,escort_pd:on --secs=90
## Options: --a=<hulls> and --b=<hulls> (comma-separated hull ids; default
## 2 lances against 1 flak frigate; --b=none for no enemy), --secs=<n>,
## --unit (the E1 and E2 checks), --unit4 (the E4 Shields check), --show, --debug (a --goto line every 2 s), --swap, --start=x,y and --goto=x,y (put squad A at a point and
## tell it to hold another: a travel test, for jungle_big).
##
## WHO USES IT: main.gd loads it for --test=roles_probe. The combat_roles
## build report (SP/fun/reports/combat_roles_build.md) quotes its output.

## The arena toolkit: squads, keeping pilots in the fight, who is alive.
const ArenaKit := preload("res://tests/lib/arena_kit.gd")

## The running match (set by setup()).
var world: World
## Squad A's ships (Halcyon).
var a: Array = []
## Squad B's ships (Cinder).
var b: Array = []
## Seconds since this test started.
var t := 0.0
## Seconds until the next progress line.
var report_t := 0.0
## Seconds until the next --show line.
var show_t := 0.0
## Seconds until the next --goto line.
var goto_t := 0.0
## How long to run (seconds).
var secs := 90.0
## The --goto point (Vector2.INF = none): squad A holds it, and the report
## shows how far away the first ship is.
var goto_point := Vector2.INF


## main.gd calls this once, right after the World is built: stop the minion
## waves and launch both squads.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 90.0))
	world.minion_director.next_wave = INF
	var la := str(Game.opt("a", "lance,lance")).split(",")
	var lb := str(Game.opt("b", "flak")).split(",")
	var swap := Game.opt("swap") != null
	a = ArenaKit.squad(world, Rules.HALCYON, la, swap, -1.0)
	if lb != PackedStringArray(["none"]):
		b = ArenaKit.squad(world, Rules.CINDER, lb, swap, -1.0)
	# --start=x,y and --goto=x,y: put squad A at one point and tell it to
	# hold another (a travel test: does it get there, and how?).
	var start := _point(str(Game.opt("start", "")))
	var goto := _point(str(Game.opt("goto", "")))
	for s: Ship in a:
		if start != Vector2.INF:
			s.global_position = start
			s.velocity = Vector2.ZERO
		if goto != Vector2.INF:
			(world.pilot_ai[s.profile] as PilotAI).hold_point = goto
	goto_point = goto
	print("roles_probe: %s vs %s" % [la, lb])
	if Game.opt("unit", false):
		_unit_e1()
	if Game.opt("unit4", false):
		(a[0] as Ship).energy.mode = Rules.ENERGY_SHIELDS


## Godot calls this every tick: keep the pilots in the fight, print progress,
## and end after --secs seconds or when a squad is gone.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	ArenaKit.keep_in_fight(world)
	var aa := ArenaKit.alive_text(a)
	var bb := ArenaKit.alive_text(b)
	report_t -= dt
	if report_t <= 0.0:
		report_t = 10.0
		print("  t=%3ds A %s | B %s" % [int(t), aa, bb])
	if Game.opt("unit", false) and t >= 2.0 and t < 2.0 + dt:
		_unit_e2()
	if Game.opt("unit4", false):
		_unit_e4(dt)
	if Game.opt("show", false):
		show_t -= dt
		if show_t <= 0.0:
			show_t = 5.0
			_show()
	if goto_point != Vector2.INF and not aa.is_empty():
		goto_t -= dt
		if goto_t <= 0.0:
			goto_t = 2.0 if Game.opt("debug", false) else 10.0
			var s0 = a[0]
			if is_instance_valid(s0) and s0.alive:
				var ai0: PilotAI = world.pilot_ai[s0.profile]
				print("    goto: %s at (%d, %d) is %d from the goal, speed %d, hull %d%%, route %d points at %d" % [s0.hull_id, int(s0.global_position.x), int(s0.global_position.y), int(s0.global_position.distance_to(goto_point)), int(s0.velocity.length()), int(s0.hull_frac() * 100.0), ai0.path.size(), ai0.path_i])
	if aa.is_empty() or (not b.is_empty() and bb.is_empty()) or t >= secs:
		print("ROLES_PROBE after %ds: A alive %d, B alive %d, usage %s" % [int(t), aa.size(), bb.size(), JSON.stringify(Game.usage)])
		# The queue (run_batch.ps1) counts a PROBE_JSON line as a result.
		print("PROBE_JSON %s" % JSON.stringify({"test": "roles_probe", "secs": int(t), "a_alive": aa.size(), "b_alive": bb.size(), "usage": Game.usage}))
		get_tree().quit()


## --show: for every ship of squad A, its distance to the nearest living
## ship of squad B and its angle in that ship's own frame (0 = dead ahead
## of it, 180 = right behind it), plus the AI intent.
func _show() -> void:
	for s0 in a:
		if not is_instance_valid(s0) or not s0.alive:
			continue
		var s: Ship = s0
		var best: Ship = null
		for e0 in b:
			if not is_instance_valid(e0) or not e0.alive:
				continue
			var e: Ship = e0
			if best == null or s.global_position.distance_to(e.global_position) < s.global_position.distance_to(best.global_position):
				best = e
		if best == null:
			continue
		var rel := (s.global_position - best.global_position).rotated(-best.rotation)
		var ai: PilotAI = world.pilot_ai[s.profile]
		print("    %s d=%d ang=%d intent=%s state=%s hull=%d%%" % [s.hull_id, int(s.global_position.distance_to(best.global_position)), int(rad_to_deg(absf(rel.angle()))), ai.intent, ai.state, int(s.hull_frac() * 100.0)])

## Read a point written as "x,y" (world units); Vector2.INF for empty text.
func _point(text: String) -> Vector2:
	var parts := text.split(",")
	if parts.size() != 2:
		return Vector2.INF
	return Vector2(float(parts[0]), float(parts[1]))

## --unit, idea E1 (minion_cap): a minion with strength 1.35 (and a 10%
## Reinforced Waves bonus on top) hits the first ship of squad A, and a
## minion of ours; print the damage the hit has with and without the hook.
## With the variant on, the hit on the ship should be cut to 1.15 / 1.485
## (0.774) of what it was; the hit on the minion should not change.
func _unit_e1() -> void:
	world.teams[Rules.CINDER].minion_buff = 0.1
	var target_ship: Ship = a[0]
	var m := world.spawn_minion(Rules.CINDER, "fighter", "mid", target_ship.global_position + Vector2(300, 0))
	m.stat_scale = 1.35 * 1.1
	var friend := world.spawn_minion(Rules.HALCYON, "fighter", "mid", target_ship.global_position + Vector2(-300, 0))
	for victim: Unit in [target_ship, friend]:
		var info := DamageInfo.from_unit(m, 10.0, Rules.W_BOLT, m.global_position)
		var base := world.combat.scaling.final_amount(victim, info)
		var after := base
		if world.combat.minion_scale_hook.is_valid():
			after = world.combat._rescale_minion_hit(victim, info, base)
		print("UNIT e1: minion hit on %s: %.3f -> %.3f (ratio %.3f)" % [Unit.KIND_NAMES[victim.kind], base, after, after / base])
	print("UNIT e1: usage %s" % JSON.stringify(Game.usage))


## --unit, idea E2 (escort_pd): print, for every big ship of squad A, the
## words on its status panel, its shield refill number (normal in
## brackets) and the rate of its first point-defense gun (normal in
## brackets).
func _unit_e2() -> void:
	for s0 in a:
		if not is_instance_valid(s0) or not s0.alive or s0.size_class < Rules.SIZE_LARGE:
			continue
		var s: Ship = s0
		var esc = world.features.get("escort_pd")
		var words := "" if esc == null else (esc as EscortPdFeature).status(s)
		var rate := -1.0
		for m: WeaponMount in s.mounts:
			if m.weapon_id == "pd_gun":
				rate = float(m.def["rate"])
				break
		print("UNIT e2: %s %s shield regen %.1f (%.1f) pd rate %.2f (%.2f)" % [s.hull_id, words, s.shields.regen, float(s.def["shield_regen"]), rate, float(Weapons.get_def("pd_gun")["rate"])])

## --unit4, idea E4 (routing_payoff), the Shields payoff: squad A's first
## ship is put in Shields routing at the start. At 3.6 s (past the 3 s a
## small ship needs) one hit lands on it; the front shield zone is printed
## just before, 0.2 s after, and again at 4.8 s and 10 s (the overshield
## should appear after the hit, and be gone 6 s later).
func _unit_e4(dt: float) -> void:
	var s: Ship = a[0]
	# The AI would switch back to Balanced: keep the mode, and lock the switch.
	s.energy.mode = Rules.ENERGY_SHIELDS
	s.energy_cd = 99.0
	if t >= 3.6 and t < 3.6 + dt:
		print("UNIT e4: before the hit: zone values %s (cap %.1f), mode %d" % [s.shields.values, s.shields.cap(0), s.energy.mode])
		var info := DamageInfo.new()
		info.amount = 5.0
		info.kind = Rules.W_PURE
		info.from_pos = s.global_position + Vector2(500, 0).rotated(s.rotation)
		world.combat.apply_damage(s, info)
	for mark in [3.8, 4.8, 10.0]:
		if t >= mark and t < mark + dt:
			print("UNIT e4: t=%.1f zone values %s (cap %.1f), usage %s" % [mark, s.shields.values, s.shields.cap(0), JSON.stringify(Game.usage)])
