class_name RecallFeature
extends Node2D
## WHAT THIS IS: the feature module for the "recall" rule variant (idea A3
## of the pacing_downtime fork): "Recall". Press T and the ship "channels" (a
## calm countdown) for 8, 10 or 12 seconds, then docks at the mothership
## from wherever it is, with the normal full repair. It cuts the long flight
## home after a fight, and it lets a hurt ship escape for good.
##
## HOW IT WORKS: --variant=recall:on installs this object under the World.
##   - Starting: the human presses T (the key is added to the controls here)
##     or an AI pilot decides to (see below). Allowed when the ship is alive,
##     has no recall running, the pilot's cooldown is over, and the mothership
##     is working.
##   - Channelling: SECONDS gives the time by hull size (small 8, medium 10,
##     large and capital 12). It is cancelled by damage taken, firing the
##     guns, boosting, or pushing the main engine forward harder than 30%
##     (braking and sliding are fine). A cancelled or completed recall starts
##     a COOLDOWN of 60 s for that pilot.
##   - Completing: the ship docks as WorldHangar.try_dock() does, but without
##     the distance test, so it is repaired and the pilot is "docked".
##   - Everyone sees a pulsing ring (in the team's colour, with a progress
##     arc) on a channelling ship, as far as the fog of war shows the ship.
##     The human also gets a bar on the HUD (RecallBar).
##   - The AI (ai_think_home(), called by PilotGoals.think_home for the
##     "retreat" and "home" states): when the ship is more than 9,000 from the
##     mothership's hull, no enemy pilot ship that its team can see is within
##     3,000, and nothing has hurt it for 4 s, it starts a recall, then
##     holds still (its goal becomes its own position and it shoots nothing)
##     until the recall ends.
## Usage counters in Game.usage: "recalls_started", "recalls_completed",
## "recalls_cancelled". REQ-CHANGE: none. The test to watch is
## pilot_kill_share: fleeing ships stop dying.
##
## WHO USES IT: FeatureRegistry installs it. PilotGoals.think_home() calls
## ai_think_home(). World's tick_hooks call tick().

## The variant key this module belongs to.
const KEY := "recall"
## Channel time in seconds by size class (small, medium, large, capital).
const SECONDS := [8.0, 10.0, 12.0, 12.0]
## Seconds before the same pilot may recall again, after a recall ended
## (completed or cancelled).
const COOLDOWN := 60.0
## The AI recalls only when its ship is this far (world units) from the
## mothership's hull.
const FAR_FROM_HOME := 9000.0
## ...and when no visible enemy pilot ship is within this distance (world
## units).
const ENEMY_NEAR := 3000.0
## ...and when nothing has hurt the ship for this many seconds.
const QUIET_TIME := 4.0
## Pushing the main engine forward harder than this (0..1) cancels a recall.
const THRUST_LIMIT := 0.3

## The running match.
var world: World
## The recalls under way: Ship -> {"t": seconds channelled so far, "total":
## seconds needed, "since": match time it started}.
var channels := {}
## Match time before which a pilot may not start a recall: PilotProfile ->
## seconds.
var cooldown_until := {}
## The HUD bar for the human pilot (a Control), or null when there is no
## window (headless runs).
var bar: Control = null
## True while the ring layer has something drawn (so it is wiped once after
## the last recall ends).
var _ring_shown := false


## Plug the feature into match `w`: add the T key, the tick hook, the ring's
## drawing layer and (with a window) the HUD bar.
func install(w: World) -> void:
	world = w
	z_index = 6
	if not InputMap.has_action("recall"):
		InputMap.add_action("recall")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_T
		InputMap.action_add_event("recall", ev)
	w.tick_hooks.append(tick)
	# The bar needs a screen; headless runs have none.
	if DisplayServer.get_name() != "headless":
		var layer := CanvasLayer.new()
		layer.layer = 4
		var b := RecallBar.new()
		b.feature = self
		layer.add_child(b)
		add_child(layer)
		bar = b


# --- starting and stopping -----------------------------------------------------------------

## May `ship` start a recall now? Returns "" or the reason (shown to the human
## as a toast).
func blocker(ship: Ship) -> String:
	if ship == null or not is_instance_valid(ship) or not ship.alive or ship.profile == null:
		return "No ship"
	if channels.has(ship):
		return "Recall is already running"
	var ready_at := float(cooldown_until.get(ship.profile, 0.0))
	if world.time < ready_at:
		return "Recall is cooling down (%ds)" % int(ceil(ready_at - world.time))
	var ms := world.mothership(ship.team)
	if ms == null or not ms.available():
		return "The mothership is offline"
	return ""


## Start a recall for `ship`. Returns "" when it started, or why not.
func start(ship: Ship) -> String:
	var b := blocker(ship)
	if b != "":
		return b
	channels[ship] = {"t": 0.0, "total": float(SECONDS[Rules.size_index(ship.size_class)]), "since": world.time}
	Game.count_usage("recalls_started")
	return ""


## End the recall of `ship` without docking it: start the pilot's cooldown,
## count it and tell a human why.
func _cancel(ship: Ship, why: String) -> void:
	channels.erase(ship)
	if is_instance_valid(ship) and ship.profile != null:
		cooldown_until[ship.profile] = world.time + COOLDOWN
		if ship.profile.is_human:
			Events.toast.emit("Recall cancelled: " + why)
	Game.count_usage("recalls_cancelled")


# --- every tick ----------------------------------------------------------------------------------

## The tick hook (World.tick_hooks): read the human's T key, then advance
## every recall by `dt` seconds and cancel or complete it.
func tick(dt: float) -> void:
	# Step 1: the human's key.
	var me := world.human
	if me != null and me.state == "flying" and me.ship != null and is_instance_valid(me.ship) \
			and Input.is_action_just_pressed("recall"):
		var why := start(me.ship)
		if why != "":
			Events.toast.emit(why)
		else:
			Events.toast.emit("Recalling: hold still, hold fire (%d s)" % int(channels[me.ship]["total"]))
	if channels.is_empty():
		# Wipe the last ring once when the last recall has just ended.
		if _ring_shown:
			_ring_shown = false
			queue_redraw()
		return
	_ring_shown = true
	# Step 2: every channelling ship. We walk a copy: the list changes inside.
	for key in channels.keys():
		if not is_instance_valid(key) or not (key as Ship).alive:
			channels.erase(key)
			continue
		var ship: Ship = key
		var ch: Dictionary = channels[ship]
		# Cancel when anything breaks the calm.
		if ship.last_damage_time >= float(ch["since"]):
			_cancel(ship, "you were hit")
			continue
		if ship.controls.fire:
			_cancel(ship, "you fired")
			continue
		if ship.boosting or ship.controls.boost:
			_cancel(ship, "you boosted")
			continue
		if ship.controls.forward > THRUST_LIMIT:
			_cancel(ship, "you used the engines")
			continue
		# Count the time; at the end dock from anywhere.
		ch["t"] = float(ch["t"]) + dt
		if float(ch["t"]) >= float(ch["total"]):
			_complete(ship)
	queue_redraw()


## The channel of `ship` ran its full time: dock it where it is.
func _complete(ship: Ship) -> void:
	channels.erase(ship)
	var profile := ship.profile
	if world.try_dock(ship, true):
		cooldown_until[profile] = world.time + COOLDOWN
		Game.count_usage("recalls_completed")
	else:
		# The mothership went offline during the channel.
		cooldown_until[profile] = world.time + COOLDOWN
		Game.count_usage("recalls_cancelled")


# --- the AI --------------------------------------------------------------------------------------

## Called by PilotGoals.think_home() for an AI pilot (state "retreat" or
## "home") that is thinking about where to fly. Returns true when this
## feature has taken over this think (a recall is running or just started):
## the pilot's goal is its own position, so it holds still, and it shoots
## nothing. See HOW IT WORKS for when the AI starts a recall.
func ai_think_home(brain: PilotAI, ship: Ship, ms: Mothership) -> bool:
	# Step 1: a recall is running: hold still.
	if channels.has(ship):
		_hold(brain, ship)
		return true
	# Step 2: the conditions to start one.
	if ms == null or ms.hull_dist(ship.global_position) <= FAR_FROM_HOME:
		return false
	if world.time - ship.last_damage_time < QUIET_TIME:
		return false
	for e: Ship in world.ships:
		if e.team != ship.team and e.alive and e.visible_to(ship.team) and e.global_position.distance_to(ship.global_position) < ENEMY_NEAR:
			return false
	if start(ship) != "":
		return false
	_hold(brain, ship)
	return true


## Make the AI pilot hold still: its goal is where it is, and it has no
## target (so it fires nothing).
func _hold(brain: PilotAI, ship: Ship) -> void:
	brain.goal = ship.global_position
	brain.target = null
	brain.lock_target = null


# --- drawing -----------------------------------------------------------------------------------

## Draw a pulsing ring with a progress arc around each channelling ship
## (below the fog layer, so only ships the viewer can see show a ring).
func _draw() -> void:
	for key in channels.keys():
		if not is_instance_valid(key):
			continue
		var ship: Ship = key
		var ch: Dictionary = channels[ship]
		var col := Palette.team(ship.team)
		var pulse := 0.5 + 0.5 * sin(world.time * 6.0)
		var r := ship.radius + 70.0 + 14.0 * pulse
		draw_arc(ship.global_position, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.25 + 0.3 * pulse), 4.0, true)
		var frac := clampf(float(ch["t"]) / float(ch["total"]), 0.0, 1.0)
		draw_arc(ship.global_position, r + 10.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(col.r, col.g, col.b, 0.9), 5.0, true)


## Seconds left and total seconds of the human pilot's recall as
## [left, total], or an empty array when the human is not recalling. The
## HUD bar (RecallBar) reads it.
func human_progress() -> Array:
	var me := world.human
	if me == null or me.ship == null or not is_instance_valid(me.ship) or not channels.has(me.ship):
		return []
	var ch: Dictionary = channels[me.ship]
	return [float(ch["total"]) - float(ch["t"]), float(ch["total"])]
