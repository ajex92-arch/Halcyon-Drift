extends Node
## WHAT THIS IS: the "input bot" test. It flies the HUMAN player's ship by
## pressing the same input actions the keyboard would press, through the
## real PlayerController, and checks that each control does what the help
## screen says:
##   W thrusts forward, A slides to port (left), D slides to starboard
##   (right), the Up arrow focuses the shields to the front (and a second
##   press rebalances them), 1 routes energy to weapons, 3 routes energy
##   to the engines (with a short cooldown between switches), R launches a
##   repair kit drone that heals, and F docks at the mothership.
## It exists so a change to the controls, the ship or the HUD's key list
## can't quietly break what a real player presses.
##
## HOW IT WORKS: setup() gives the human 2,000 credits, buys a fighter and
## one repair kit, and launches it in open space. Then _physics_process()
## runs a list of numbered steps (`step`), one after another: each step
## presses or taps a key, waits a moment, and checks the ship (speed,
## shield focus, energy routing, hull, docked or not). Every check prints
## a PASS or FAIL line. The last step prints the number of failures and
## quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=bot_pilot
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second, so a run
## repeats. --bot=input tells main.gd not to buy and launch the human's
## ship by itself (this test does it). --no-pilots and --no-admiral-ai
## switch off the AI pilots and computer admirals, so nothing interferes.
##
## HOW TO READ THE OUTPUT: one line per check, "PASS <what> <detail>" or
## "FAIL <what> <detail>" (the detail is the number that was measured, for
## example "forward speed 412"). The last line is "bot_pilot: N failures";
## 0 means every control works.
##
## WHO USES IT: main.gd loads it for --test=bot_pilot (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()).
## docs/CODE_STYLE.md (Part 3) lists it as a check for player-facing code.
## It drives PlayerController (scripts/control/player_controller.gd) with
## Input.action_press(); the key names come from Game._define_actions().

## The running match (set by setup()).
var world: World
## The human's ship that we fly.
var ship: Ship
## Seconds since this test started.
var t := 0.0
## Which step of the test we are on (0, 1, 2 ...; see _physics_process).
var step := 0
## Seconds since the current step began.
var step_t := 0.0
## How many checks failed so far.
var fails := 0
## A remembered number to compare against later (here: the hull before
## the repair kit drone starts healing).
var mark := 0.0


## main.gd calls this once, right after the World is built. Stop the minion
## waves, then buy a fighter and a repair kit for the human and launch it.
func setup(w: World) -> void:
	world = w
	# Run before World each physics frame so "just pressed" lands on the
	# frame the ship reads it. (Lower priority numbers run first; this test
	# would otherwise run after the World.)
	process_physics_priority = -100
	# No minion waves: the next wave is "never" (INF = infinity).
	world.minion_director.next_wave = INF
	# Shop for the human: a fighter and one repair kit.
	var h := world.human
	h.credits = 2000.0
	h.buy_hull("fighter", world.teams[0])
	h.buy_kit()
	# Launch it at a quiet spot, standing still.
	ship = world.launch(h)
	ship.global_position = Vector2(9000, 13000)
	ship.velocity = Vector2.ZERO


## Print one PASS or FAIL line for the check `name` (`ok` = it passed),
## with the measured `detail`, and count the failures.
func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## Move on to the next step: restart the step clock and let go of the
## movement keys (so the next step starts with no key held).
func _next() -> void:
	step += 1
	step_t = 0.0
	for a in ["thrust_forward", "thrust_back", "strafe_left", "strafe_right"]:
		Input.action_release(a)


## Tap a key: press the input action `action` now and let it go 0.05
## seconds later (the timer keeps running when the game is paused and
## counts in physics ticks).
func _tap(action: String) -> void:
	Input.action_press(action)
	get_tree().create_timer(0.05, true, true).timeout.connect(func() -> void: Input.action_release(action))


## Godot calls this every tick; `dt` is the tick's length in seconds. Run
## the current step: each one presses keys, waits, checks, then calls
## _next().
func _physics_process(dt: float) -> void:
	# (Not "ship == null": after docking the freed ship compares equal to null.)
	if world == null:
		return
	t += dt
	step_t += dt
	match step:
		# W: hold "thrust forward" from a standstill.
		0:
			ship.velocity = Vector2.ZERO
			Input.action_press("thrust_forward")
			_next()
		# After 1 s of W, the speed along our nose must be over 250.
		1:
			Input.action_press("thrust_forward")
			if step_t > 1.0:
				var fwd := ship.velocity.dot(Vector2.from_angle(ship.rotation))
				_check("W thrusts forward", fwd > 250.0, "forward speed %.0f" % fwd)
				_next()
		# A: stop on the first frame, then hold "strafe left" for 0.6 s;
		# the speed toward our left side (port) must be over 100.
		2:
			if step_t <= dt:
				ship.velocity = Vector2.ZERO
			Input.action_press("strafe_left")
			if step_t > 0.6:
				var lat := ship.velocity.dot(Util.port_of(ship.rotation))
				_check("A slides left (port)", lat > 100.0, "port speed %.0f" % lat)
				_next()
		# D: the same to the right side (starboard).
		3:
			if step_t <= dt:
				ship.velocity = Vector2.ZERO
			Input.action_press("strafe_right")
			if step_t > 0.6:
				var lat := ship.velocity.dot(Util.starboard_of(ship.rotation))
				_check("D slides right (starboard)", lat > 100.0, "starboard speed %.0f" % lat)
				_next()
		# Wait 2 s, then tap the Up arrow ("shield_front").
		4:
			if step_t > 2.0:
				_tap("shield_front")
				_next()
		# The shields must now focus front, and the front zone must hold
		# half (50%) of all the shield points.
		5:
			if step_t > 0.3:
				_check("Up arrow focuses front shields", ship.shields.focus == Rules.FOCUS_FRONT, Rules.FOCUS_NAMES[ship.shields.focus])
				var cap_front := ship.shields.cap(Rules.ZONE_FRONT) / ship.shields.max_total
				_check("front zone holds 50%", absf(cap_front - 0.5) < 0.01, "%.2f" % cap_front)
				_next()
		# Wait 1.2 s, then tap Up again.
		6:
			if step_t > 1.2:
				_tap("shield_front")
				_next()
		# A second Up puts the shields back to balanced. Then tap 1
		# ("energy_weapons").
		7:
			if step_t > 0.3:
				_check("Up again rebalances", ship.shields.focus == Rules.FOCUS_BALANCED, Rules.FOCUS_NAMES[ship.shields.focus])
				_tap("energy_weapons")
				_next()
		# Energy must now go to the weapons. Then tap 3 ("energy_thrusters")
		# straight away.
		8:
			if step_t > 0.3:
				_check("1 routes energy to weapons", ship.energy.mode == Rules.ENERGY_WEAPONS, Rules.ENERGY_NAMES[ship.energy.mode])
				_tap("energy_thrusters")
				_next()
		# On the one tick just after 0.3 s: the quick second switch must be
		# refused (routing has a cooldown), so it is still "weapons". After
		# 2 s, tap 3 again.
		9:
			if step_t > 0.3 and step_t <= 0.3 + dt:
				_check("energy routing has a cooldown", ship.energy.mode == Rules.ENERGY_WEAPONS, "still %s right after" % Rules.ENERGY_NAMES[ship.energy.mode])
			if step_t > 2.0:
				_tap("energy_thrusters")
				_next()
		# Now energy must go to the engines. Then damage the ship to 40%
		# hull, remember that hull, and tap R ("use_kit").
		10:
			if step_t > 0.3:
				_check("3 routes energy to engines", ship.energy.mode == Rules.ENERGY_THRUSTERS, Rules.ENERGY_NAMES[ship.energy.mode])
				ship.hull = ship.hull_max * 0.4
				mark = ship.hull
				_tap("use_kit")
				_next()
		# On the tick just after 0.3 s: one repair kit drone must be flying.
		# After 5 s it must have healed more than 15 hull. Then put the
		# ship, still, just in front of our mothership's nose (its half
		# length + 300 world units from its centre) so it can dock.
		11:
			if step_t > 0.3 and step_t <= 0.3 + dt:
				_check("R launches a repair kit drone", ship.kit_drones.size() == 1, "kits left %d" % world.human.kit_count())
			if step_t > 5.0:
				_check("kit drone heals", ship.hull > mark + 15.0, "+%.0f" % (ship.hull - mark))
				var ms := world.mothership(0)
				ship.global_position = ms.global_position + Vector2.from_angle(ms.rotation) * (ms.half_len + 300.0)
				ship.velocity = Vector2.ZERO
				_next()
		# After 0.2 s, tap F ("dock").
		12:
			if step_t > 0.2:
				_tap("dock")
				_next()
		# The human must now be docked. Print the total and quit.
		13:
			if step_t > 0.3:
				_check("F docks near the mothership", world.human.state == "docked", world.human.state)
				print("bot_pilot: %d failures" % fails)
				get_tree().quit()
