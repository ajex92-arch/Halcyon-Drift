extends Node
## WHAT THIS IS: the mothership duel. A fleet of Cinder ships besieges the
## Aurelian mothership with nothing else on the map. It checks the design
## rule that the mothership is tough and has decent point defense (small
## quick guns that can also shoot down torpedoes) but is weak to big ships,
## and that a fully upgraded one can fight several frigates at once and
## (barely) win.
##
## HOW IT WORKS: setup() picks a scenario from SCENARIOS (--scenario,
## default B). For a "+" scenario it first gives Aurelian all the Flagship
## research and refills the mothership. Then it launches the attackers in
## an arc 4,200 world units from the mothership (1 world unit is about one
## pixel at normal zoom). Each attacker is flown by a simple Siege brain
## (below) instead of the normal AI: it closes to 80% of its weapon reach,
## faces the mothership and fires. Every 15 game seconds the test prints
## the state of the fight. It ends when the mothership dies, every attacker
## is dead, or after 420 seconds.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --variant=retreat:none --test=ms_duel --scenario=B
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second. --no-pilots,
## --no-jungle and --no-admiral-ai switch off the normal AI pilots, the
## jungle monsters and the computer admirals. --variant=retreat:none turns
## off the mothership's retreat (see Rules.VARIANT_DEFAULTS). --guns adds a
## line with what each mothership gun is shooting at.
##
## Scenarios (attackers; "+" = all Flagship research done):
##   A  base  vs 3 flak frigates + 1 destroyer        (mothership should lose)
##   B  +     vs 2 flak + 1 ion frigate               (should win, barely)
##   C  +     vs 3 ion frigates                       (close)
##   D  base  vs 8 fighters + 4 bombers               (should win comfortably)
##   E  base  vs 2 ion frigates + 1 destroyer         (should lose)
##   F  +     vs 2 flak + 1 ion + 1 destroyer         (should lose, slowly)
##   G  +     vs 3 flak frigates                      (should win)
##   H  +     vs 2 ion + 2 flak frigates              (THE benchmark: win, barely)
##   I  base  vs 2 flak + 1 ion frigate               (should lose)
##
## HOW TO READ THE OUTPUT:
##   "ms_duel B: mothership upgraded=true hull=... shields=... guns=... vs [...]"
##       the setup: the mothership's full hull and shield points, its
##       number of guns, and the attackers' hulls.
##   "t= 15s  mothership hull 96% shields 40%  attackers alive 3: flak 80%, ..."
##       every 15 s: how much the mothership and each attacker have left.
##   "guns: ms_pd:torp*, ..."  (with --guns) each gun's weapon id and its
##       target ("torp" = a torpedo, "name@distance", "-" = none); "*" =
##       the gun is engaged.
##   "RESULT B ATTACKERS DESTROYED after 212s: mothership 61% hull (48% of
##    total HP left), attackers alive 0"  the end. The reason is
##       MOTHERSHIP DESTROYED, ATTACKERS DESTROYED or TIMEOUT. "Total HP" is
##       hull + shields, compared with the start.
##
## WHO USES IT: main.gd loads it for --test=ms_duel (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()). The
## attackers' ships call Siege.update() every tick as their `controller`,
## and Ship.homing_target() reads Siege.lock_target.

## Each scenario's letter -> [is the mothership upgraded?, the attackers'
## hull ids].
const SCENARIOS := {
	"H": [true, ["ion", "ion", "flak", "flak"]],
	"I": [false, ["flak", "flak", "ion"]],
	"A": [false, ["flak", "flak", "flak", "destroyer"]],
	"B": [true, ["flak", "flak", "ion"]],
	"C": [true, ["ion", "ion", "ion"]],
	"D": [false, ["fighter", "fighter", "fighter", "fighter", "fighter", "fighter", "fighter", "fighter", "bomber", "bomber", "bomber", "bomber"]],
	"E": [false, ["ion", "ion", "destroyer"]],
	"F": [true, ["flak", "flak", "ion", "destroyer"]],
	"G": [true, ["flak", "flak", "flak"]],
}


## A very simple pilot brain (a "controller": the thing a ship asks every
## tick which way to fly and whether to shoot) for the attackers. It flies
## to a set distance from the enemy mothership, faces it and fires.
class Siege:
	extends RefCounted
	## The running match.
	var world: World
	## What our homing weapons should chase (always the enemy mothership
	## once update() has run). Ship.homing_target() reads it.
	var lock_target: Unit = null

	## Remember the match `w`.
	func _init(w: World) -> void:
		world = w

	## Steer and shoot `ship` for one tick (the ship calls this every tick;
	## `_dt` is not needed). It sets the ship's `controls`.
	func update(ship: Ship, _dt: float) -> void:
		var ms := world.mothership(1 - ship.team)
		lock_target = ms
		var c := ship.controls
		# Step 1: aim at the closest point on the mothership's centre line
		# (from nose to tail); `d` is our distance to its hull surface.
		var f := Vector2.from_angle(ms.rotation) * ms.half_len
		var tp := Util.closest_on_segment(ship.global_position, ms.global_position + f, ms.global_position - f)
		var d := ms.hull_dist(ship.global_position)
		# Step 2: our reach is our longest aimed (not automatic) weapon's
		# reach, at least 600; we want to sit at 80% of it.
		var reach := 600.0
		for m in ship.mounts:
			if m.mount_type != WeaponMount.AUTO:
				reach = maxf(reach, m.reach * ship.range_mult)
		var want := reach * 0.8
		c.aim_point = tp
		c.face_point = tp
		# Step 3: are we closing in, and are we facing it (within 0.5
		# radians, about 29 degrees)?
		var to := (tp - ship.global_position).normalized()
		var closing := ship.velocity.dot(to)
		var facing := absf(Util.ang_diff(ship.rotation, to.angle())) < 0.5
		# Step 4: too far: fly in (slowly until we face it). Too close
		# (under 70% of `want`): back off. In between: brake if closing
		# faster than 20 units a second, push in if drifting away faster
		# than 20, else coast.
		if d > want:
			c.forward = 1.0 if facing else 0.2
		elif d < want * 0.7:
			c.forward = -0.6
		else:
			c.forward = -0.5 if closing > 20.0 else (0.3 if closing < -20.0 else 0.0)
		# Step 5: no sliding sideways; fire (and use the special when it is
		# ready) inside our reach; shields to the front (-1 = no change
		# once they are); energy to the weapons.
		c.strafe = 0.0
		c.fire = d < reach
		c.special = ship.special_ready() and d < reach
		c.focus_request = Rules.FOCUS_FRONT if ship.shields.focus != Rules.FOCUS_FRONT else -1
		c.energy_request = Rules.ENERGY_WEAPONS


## The running match (set by setup()).
var world: World
## The scenario letter (--scenario, default "B").
var scenario := "B"
## The attackers' ships.
var ships: Array = []
## Seconds since this test started.
var t := 0.0
## Seconds until the next progress report.
var report_t := 0.0
## The Aurelian mothership under attack.
var ms: Mothership
## The mothership's hull + shield points at the start.
var start_hp := 0.0


## main.gd calls this once, right after the World is built. Stop the minion
## waves, upgrade the mothership for "+" scenarios, and launch the
## attackers.
func setup(w: World) -> void:
	world = w
	scenario = str(Game.opt("scenario", "B"))
	# No minion waves: the next wave is "never" (INF = infinity).
	world.minion_director.next_wave = INF
	ms = world.mothership(Rules.HALCYON)
	var sc: Array = SCENARIOS[scenario]
	# A "+" scenario: build the capital facility, finish every research in
	# the Flagship column (and apply it), then refill hull and shields.
	if sc[0]:
		var ts := world.teams[Rules.HALCYON]
		ts.facilities["capital"] = true
		for id: String in Tech.ORDER:
			if Tech.TECHS[id]["column"] == "flagship":
				ts.done[id] = true
				ts.apply_effect(Tech.TECHS[id]["effect"])
		ms.apply_upgrades(ts)
		ms.hull = ms.hull_max
		ms.shields.fill()
	# The attackers: Cinder pilots "Attacker0", "Attacker1" ... (seats 30
	# and up; the normal seats are 0-11), launched 4,200 units from the
	# mothership's centre, spread from -0.5 to +0.5 radians (an arc of about
	# 57 degrees), standing still, facing it, flown by a Siege brain.
	var i := 0
	for hid: String in sc[1]:
		var p := PilotProfile.new("Attacker%d" % i, Rules.CINDER, 30 + i, false)
		p.hull_id = hid
		world.profiles.append(p)
		var s := world.launch(p)
		var ang := -0.5 + float(i) / maxf(1.0, float(sc[1].size() - 1))
		s.global_position = ms.global_position + Vector2.from_angle(ang) * 4200.0
		s.rotation = (ms.global_position - s.global_position).angle()
		s.velocity = Vector2.ZERO
		s.controller = Siege.new(world)
		ships.append(s)
		i += 1
	start_hp = ms.hull + ms.shields.total()
	print("ms_duel %s: mothership upgraded=%s hull=%d shields=%d guns=%d vs %s" % [scenario, sc[0], int(ms.hull_max), int(ms.shields.max_total), ms.mounts.size(), sc[1]])


## Godot calls this every tick; `dt` is the tick's length in seconds.
## Report every 15 s and end the duel when one side is gone or time is up.
func _physics_process(dt: float) -> void:
	if world == null:
		return
	t += dt
	# The attackers still alive, as "hull 80%" texts.
	var alive := 0
	var parts: Array = []
	for s in ships:
		if is_instance_valid(s) and s.alive:
			alive += 1
			parts.append("%s %d%%" % [s.hull_id, int(s.hull_frac() * 100.0)])
	# Every 15 s (and on the first tick): the progress line.
	report_t -= dt
	if report_t <= 0.0:
		report_t = 15.0
		print("  t=%3ds  mothership hull %d%% shields %d%%  attackers alive %d: %s" % [int(t), int(ms.hull_frac() * 100.0), int(ms.shields.fraction() * 100.0), alive, ", ".join(parts)])
		# --guns: what each mothership gun is aiming at.
		if Game.opt("guns", false):
			var g: Array = []
			for m: WeaponMount in ms.mounts:
				var what := "-"
				if m.target_torp >= 0:
					what = "torp"
				elif m.target != null and is_instance_valid(m.target):
					what = "%s@%d" % [(m.target as Unit).display_name, int(m.world_pos().distance_to(m.target.global_position))]
				g.append("%s:%s%s" % [m.weapon_id, what, "*" if m.engaged else ""])
			print("    guns: ", ", ".join(g))
	# The end: the mothership is gone (or the match is over), every
	# attacker is gone, or 420 seconds have passed.
	var done := ""
	if not ms.alive or world.phase != "play":
		done = "MOTHERSHIP DESTROYED"
	elif alive == 0:
		done = "ATTACKERS DESTROYED"
	elif t > 420.0:
		done = "TIMEOUT"
	if done != "":
		var left := (ms.hull + ms.shields.total()) / maxf(1.0, start_hp)
		print("RESULT %s %s after %ds: mothership %d%% hull (%d%% of total HP left), attackers alive %d" % [scenario, done, int(t), int(ms.hull_frac() * 100.0), int(left * 100.0), alive])
		get_tree().quit()
