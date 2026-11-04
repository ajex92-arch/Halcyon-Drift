class_name ShipControls
extends RefCounted
## WHAT THIS IS: the "control sticks" of one pilot ship: a small form that
## says what the pilot wants the ship to do this tick (a tick is one small
## step of game time, 60 a second). Which way to aim, how hard to thrust,
## whether to fire, and so on.
##
## HOW IT WORKS: every tick a controller fills it in first: PlayerController
## for the human (from keys and mouse) or PilotAI for computer pilots. Then
## the ship reads it in Ship.sim_update() and flies by it. Humans and bots
## use exactly the same form, so they fly by exactly the same rules.
##
## Some fields are "edge" fields: one-off requests for a single moment, like
## a button press (special, focus_request, energy_request, use_kit, dock).
## The ship clears them with clear_edges() after reading them, so each
## press acts once. The other fields are held: they keep their value until
## the controller changes them.
##
## WHO USES IT: every Ship owns one (Ship.controls). PlayerController and
## PilotAI write it; Ship reads it (turning, thrust, weapons, requests).

## The world point the guns aim at (and where the aiming reticle is drawn).
var aim_point := Vector2.ZERO
## The world point the hull turns toward. Usually the same as aim_point, but
## a big ship can hold its heading (to keep its shields facing a threat)
## while its turrets aim somewhere else.
var face_point := Vector2.ZERO
## Main engine, from -1 to +1: +1 = full thrust forward, -1 = brake and
## reverse, 0 = engines off.
var forward := 0.0
## Side thrusters, from -1 to +1: +1 slides the ship to its left (port side,
## key A), -1 to its right (starboard side, key D).
var strafe := 0.0
## True while the pilot wants to boost (extra speed that costs energy).
var boost := false
## True while the pilot wants to fire the guns.
var fire := false
## Edge: true for one tick to use the hull's special ability.
var special := false
## Edge: the shield focus wanted (Rules.FOCUS_BALANCED, FOCUS_FRONT, ...),
## or -1 for "no change".
var focus_request := -1
## Edge: the energy routing wanted (Rules.ENERGY_BALANCED, ENERGY_WEAPONS,
## ...), or -1 for "no change".
var energy_request := -1
## Edge: true for one tick to use a repair kit.
var use_kit := false
## Edge: true for one tick to dock at the mothership.
var dock := false
## Flight assist on (true) or off. When on, the ship damps its sideways
## drift while it isn't strafing or boosting, so it travels the way its
## nose points instead of sliding sideways (Ship._flight).
var assist := true


## Reset the edge fields after the ship has read them, so each one-off
## request (special, shield focus, energy routing, repair kit, dock) acts
## only once. Called by Ship.sim_update().
func clear_edges() -> void:
	special = false
	focus_request = -1
	energy_request = -1
	use_kit = false
	dock = false
